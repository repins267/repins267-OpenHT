// lib/screens/aprs_map/aprs_map_screen.dart
// Map screen: shows APRS stations, repeaters (RepeaterBook live data), storm spotters.

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import '../../services/gps_service.dart';
import '../../aprs/aprs_service.dart';
import '../../aprs/aprs_is_service.dart';
import '../../aprs/aprs_packet.dart';
import '../../services/spotter_service.dart';
import '../../models/spotter_station.dart';
import '../../services/track_service.dart';
import '../../services/map_tile_service.dart';
import '../../bluetooth/radio_service.dart';
import '../../services/repeaterbook_connect_service.dart';
import '../../services/repeaterbook_service.dart';
import '../../services/aprs_map_settings.dart';
import '../aprs/station_detail_screen.dart';
import '../aprs/message_thread_screen.dart';

enum _RepeaterSource { repeaterBook, importedGpx, bundledGpx }

// ─── Repeater data model (map use only) ──────────────────────────────────────

class _MapRepeater {
  final double lat;
  final double lon;
  final String callsign;
  final double outputFreq;
  final double inputFreq;
  final String offsetDir;
  final double? ctcssHz;
  final String band;
  final String serviceText;
  final double distanceMiles;

  const _MapRepeater({
    required this.lat,
    required this.lon,
    required this.callsign,
    required this.outputFreq,
    required this.inputFreq,
    required this.offsetDir,
    this.ctcssHz,
    required this.band,
    this.serviceText = 'FM',
    required this.distanceMiles,
  });

  bool get isFmCompatible => serviceText.toUpperCase().contains('FM');
}

// Parse all repeaters from GPX — no distance filter at load time.
// Distance is calculated at render time from current GPS position.
List<_MapRepeater> _parseGpxForMap(String gpxXml, String band) {
  final doc = XmlDocument.parse(gpxXml);
  final result = <_MapRepeater>[];

  for (final wpt in doc.findAllElements('wpt')) {
    final lat = double.tryParse(wpt.getAttribute('lat') ?? '') ?? 0.0;
    final lon = double.tryParse(wpt.getAttribute('lon') ?? '') ?? 0.0;
    if (lat == 0.0 && lon == 0.0) continue;

    final nameText =
        wpt.findElements('name').firstOrNull?.innerText.trim() ?? '';
    final parts = nameText.split(RegExp(r'\s+'));
    if (parts.length < 2) continue;

    final callsign   = parts[0];
    final outputFreq = double.tryParse(parts[1]) ?? 0.0;
    if (outputFreq == 0.0) continue;

    String offsetDir = '';
    if (parts.length > 2) {
      if (parts[2].endsWith('+')) offsetDir = '+';
      if (parts[2].endsWith('-')) offsetDir = '-';
    }

    double? ctcss;
    if (parts.length > 3) ctcss = double.tryParse(parts[3]);

    final offset   = offsetDir.isEmpty ? 0.0 : (outputFreq >= 400 ? 5.0 : 0.6);
    final inputFreq = offsetDir == '+'
        ? outputFreq + offset
        : offsetDir == '-'
            ? outputFreq - offset
            : outputFreq;

    result.add(_MapRepeater(
      lat: lat,
      lon: lon,
      callsign: callsign,
      outputFreq: outputFreq,
      inputFreq: inputFreq,
      offsetDir: offsetDir,
      ctcssHz: ctcss,
      band: band,
      serviceText: 'FM',
      distanceMiles: 0,
    ));
  }
  return result;
}

double _haversine(double lat1, double lon1, double lat2, double lon2) {
  const r = 3958.8;
  double toRad(double d) => d * math.pi / 180;
  final dLat = toRad(lat2 - lat1);
  final dLon = toRad(lon2 - lon1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(toRad(lat1)) *
          math.cos(toRad(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

class AprsMapScreen extends StatefulWidget {
  const AprsMapScreen({super.key});

  @override
  State<AprsMapScreen> createState() => _AprsMapScreenState();
}

class _AprsMapScreenState extends State<AprsMapScreen> {
  final MapController _mapController = MapController();
  bool _followMyLocation = true;
  AprsPacket? _selectedStation;
  SpotterStation? _selectedSpotter;
  _MapRepeater? _selectedRepeater;
  bool _showAprs = true;
  bool _showSpotters = true;
  bool _showRepeaters = true;
  bool _isRecording = false;
  _RepeaterSource _repeaterSource = _RepeaterSource.bundledGpx;
  bool _isCachingTiles = false;
  MapTileSource _tileSource = MapTileSource.openStreetMap;
  List<_MapRepeater> _repeaters = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initAprsIs();
      _loadRepeaters();
      // React to settings changes (e.g. user saves APRS Settings → come back to map)
      context.read<AprsMapSettings>().addListener(_onSettingsChanged);
    });
    _loadTileSource();
  }

  @override
  void dispose() {
    context.read<AprsMapSettings>().removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    final settings = context.read<AprsMapSettings>();
    final aprsIs   = context.read<AprsIsService>();
    // Connect or disconnect APRS-IS based on the enabled toggle
    if (!settings.isEnabled && aprsIs.isConnected) {
      aprsIs.disconnect();
    } else if (settings.isEnabled && !aprsIs.isConnected) {
      final gps   = context.read<GpsService>();
      final radio = context.read<RadioService>();
      aprsIs.connect(
        lat: radio.radioLatitude ?? gps.latitude,
        lon: radio.radioLongitude ?? gps.longitude,
      );
    }
    // Force a rebuild so filtered station count updates immediately
    if (mounted) setState(() {});
  }

  Future<void> _loadRepeaters() async {
    final rbService = context.read<RepeaterBookService>();

    // Tier 1: RepeaterBook content provider (live, North America)
    try {
      final rbRepeaters = await RepeaterBookConnectService.queryRepeaters();
      if (rbRepeaters.isNotEmpty) {
        final all = rbRepeaters
          .where((r) => r.isFmCompatible) // VR-N76 can't use DMR/D-Star/digital-only
          .map((r) => _MapRepeater(
          lat: r.lat, lon: r.lon,
          callsign: r.callsign,
          outputFreq: r.outputFreq,
          inputFreq: r.inputFreq,
          offsetDir: r.outputFreq > r.inputFreq ? '-' : (r.outputFreq < r.inputFreq ? '+' : ''),
          ctcssHz: r.ctcssHz,
          band: r.band,
          serviceText: r.serviceText,
          distanceMiles: 0,
        )).toList();
        debugPrint('MapScreen: Loaded ${all.length} repeaters from RepeaterBook');
        if (mounted) setState(() {
          _repeaters = all;
          _repeaterSource = _RepeaterSource.repeaterBook;
        });
        return;
      }
    } catch (e) {
      debugPrint('MapScreen: RepeaterBook provider failed: $e');
    }

    // Tier 2: Imported GPX cache
    if (rbService.hasData) {
      final all = rbService.repeaters.map((r) => _MapRepeater(
        lat: r.lat, lon: r.lon,
        callsign: r.callsign,
        outputFreq: r.outputFreq,
        inputFreq: r.inputFreq,
        offsetDir: r.outputFreq > r.inputFreq ? '-' : (r.outputFreq < r.inputFreq ? '+' : ''),
        ctcssHz: r.ctcssHz,
        band: r.band,
        serviceText: 'FM',
        distanceMiles: 0,
      )).toList();
      debugPrint('MapScreen: Loaded ${all.length} repeaters from imported GPX');
      if (mounted) setState(() {
        _repeaters = all;
        _repeaterSource = _RepeaterSource.importedGpx;
      });
      return;
    }

    // Tier 4: Bundled Colorado GPX
    try {
      final raw2m   = await rootBundle.loadString('assets/repeaters/colorado_2m.gpx');
      final raw70cm = await rootBundle.loadString('assets/repeaters/colorado_70cm.gpx');
      final all = [
        ..._parseGpxForMap(raw2m,   '2m'),
        ..._parseGpxForMap(raw70cm, '70cm'),
      ];
      debugPrint('MapScreen: Loaded ${all.length} repeaters from bundled GPX');
      if (mounted) setState(() {
        _repeaters = all;
        _repeaterSource = _RepeaterSource.bundledGpx;
      });
    } catch (e) {
      debugPrint('MapScreen: Failed to load repeaters: $e');
    }
  }

  Future<void> _loadTileSource() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('map_tile_source');
    if (name != null && mounted) {
      setState(() => _tileSource = MapTileService.fromName(name));
    }
  }

  Future<void> _setTileSource(MapTileSource src) async {
    setState(() => _tileSource = src);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('map_tile_source', src.name);
  }

  List<AprsPacket> _filteredStations(AprsService aprs, AprsMapSettings settings) {
    if (!_showAprs) return [];
    final now = DateTime.now();
    return aprs.stations.where((s) {
      final sources = aprs.sourcesFor(s.fullCallsign);
      if (settings.directOnly) {
        if (s.source != AprsSource.rf || s.rfHops != 0) return false;
      } else {
        if (!settings.showIs && sources.contains(AprsSource.aprsIs) &&
            !sources.contains(AprsSource.rf)) return false;
        if (!settings.showRf && sources.contains(AprsSource.rf) &&
            !sources.contains(AprsSource.aprsIs)) return false;
        if (!settings.showIs && !settings.showRf) return false;
      }
      final age = now.difference(s.receivedAt);
      switch (settings.maxAge) {
        case '1hr':  if (age.inHours >= 1)  return false;
        case '6hr':  if (age.inHours >= 6)  return false;
        case '24hr': if (age.inHours >= 24) return false;
      }
      return true;
    }).toList();
  }

  void _initAprsIs() {
    final settings = context.read<AprsMapSettings>();
    final aprsIs   = context.read<AprsIsService>();
    final aprs     = context.read<AprsService>();
    final gps      = context.read<GpsService>();
    final radio    = context.read<RadioService>();
    aprs.attachPacketStream(aprsIs.packets);
    if (!settings.isEnabled) {
      aprsIs.disconnect();
      return;
    }
    final lat = radio.radioLatitude ?? gps.latitude;
    final lon = radio.radioLongitude ?? gps.longitude;
    aprsIs.connect(lat: lat, lon: lon);
  }

  @override
  Widget build(BuildContext context) {
    final gps         = context.watch<GpsService>();
    final radio       = context.watch<RadioService>();
    final aprs        = context.watch<AprsService>();
    final aprsIs      = context.watch<AprsIsService>();
    final spotter     = context.watch<SpotterService>();
    final track       = context.watch<TrackService>();
    final mapSettings = context.watch<AprsMapSettings>();

    // Prefer radio GPS; fall back to phone GPS; default to center of USA
    final myLatLon = radio.hasRadioGps
        ? LatLng(radio.radioLatitude!, radio.radioLongitude!)
        : gps.hasPosition
            ? LatLng(gps.latitude!, gps.longitude!)
            : const LatLng(39.8283, -98.5795);
    final hasPos = radio.hasRadioGps || gps.hasPosition;

    if (_followMyLocation && hasPos) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _mapController.move(myLatLon, _mapController.camera.zoom);
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Map'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          // Track record toggle
          IconButton(
            icon: Icon(
              Icons.fiber_manual_record,
              color: _isRecording ? Colors.red : Colors.white70,
            ),
            tooltip: _isRecording ? 'Stop Recording' : 'Record Track',
            onPressed: () => _toggleTrackRecording(track),
          ),
          // Follow location toggle
          IconButton(
            icon: Icon(
              _followMyLocation ? Icons.gps_fixed : Icons.gps_not_fixed,
              color: _followMyLocation ? Colors.yellow : Colors.white70,
            ),
            tooltip: 'Follow my location',
            onPressed: () => setState(() => _followMyLocation = !_followMyLocation),
          ),
          // Layer options
          IconButton(
            icon: const Icon(Icons.layers),
            tooltip: 'Layer options',
            onPressed: _showLayerOptions,
          ),
        ],
      ),
      body: Stack(
        children: [
          // ─── Map ───────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: myLatLon,
              initialZoom: 11,
              onTap: (_, __) => setState(() {
                _selectedStation = null;
                _selectedSpotter = null;
                _selectedRepeater = null;
              }),
            ),
            children: [
              // Base tile layer — source switchable (OSM / Topo / Satellite)
              TileLayer(
                urlTemplate: MapTileService.urlTemplate(_tileSource),
                userAgentPackageName: 'com.openht.app',
                maxZoom: 19,
              ),

              // APRS station markers
              MarkerLayer(
                markers: [
                  // My position marker (radio GPS preferred)
                  if (hasPos)
                    Marker(
                      point: myLatLon,
                      width: 24,
                      height: 24,
                      child: _MyPositionMarker(fromRadio: radio.hasRadioGps),
                    ),

                  // APRS station POIs
                  ..._filteredStations(aprs, mapSettings).where((s) => s.hasPosition).map((station) {
                    final isSelected = _selectedStation?.callsign == station.callsign;
                    final allSources = aprs.sourcesFor(station.fullCallsign);
                    return Marker(
                      point: LatLng(station.latitude!, station.longitude!),
                      width: isSelected ? 48 : 32,
                      height: isSelected ? 48 : 32,
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _selectedStation = station;
                          _selectedSpotter = null;
                        }),
                        child: _AprsStationMarker(
                            station: station,
                            allSources: allSources,
                            selected: isSelected),
                      ),
                    );
                  }),

                  // Spotter Network markers
                  if (_showSpotters)
                    ...spotter.spotters.map((s) {
                      final isSelected = _selectedSpotter?.name == s.name;
                      return Marker(
                        point: LatLng(s.lat, s.lon),
                        width: isSelected ? 44 : 30,
                        height: isSelected ? 44 : 30,
                        child: GestureDetector(
                          onTap: () => setState(() {
                            _selectedSpotter = s;
                            _selectedStation = null;
                            _selectedRepeater = null;
                          }),
                          child: _SpotterMarker(spotter: s, selected: isSelected),
                        ),
                      );
                    }),

                  // Repeater markers — filter to 100 mi radius
                  if (_showRepeaters)
                    ..._repeaters.where((r) {
                      if (!hasPos) return true; // no GPS yet, show all
                      final dist = _haversine(
                          myLatLon.latitude, myLatLon.longitude, r.lat, r.lon);
                      return dist <= 100;
                    }).map((r) {
                      final dist = hasPos
                          ? _haversine(myLatLon.latitude, myLatLon.longitude,
                              r.lat, r.lon)
                          : 0.0;
                      final rWithDist = _MapRepeater(
                        lat: r.lat, lon: r.lon, callsign: r.callsign,
                        outputFreq: r.outputFreq, inputFreq: r.inputFreq,
                        offsetDir: r.offsetDir, ctcssHz: r.ctcssHz,
                        band: r.band, serviceText: r.serviceText,
                        distanceMiles: dist,
                      );
                      final isSelected =
                          _selectedRepeater?.callsign == r.callsign &&
                          _selectedRepeater?.outputFreq == r.outputFreq;
                      return Marker(
                        point: LatLng(r.lat, r.lon),
                        width: isSelected ? 44 : 30,
                        height: isSelected ? 44 : 30,
                        child: GestureDetector(
                          onTap: () => setState(() {
                            _selectedRepeater = rWithDist;
                            _selectedStation = null;
                            _selectedSpotter = null;
                          }),
                          child: _RepeaterMarker(repeater: r, selected: isSelected),
                        ),
                      );
                    }),
                ],
              ),
            ],
          ),

          // ─── APRS-IS status chip ───────────────────────
          Positioned(
            top: 8,
            left: 8,
            child: _AprsIsStatusChip(state: aprsIs.state),
          ),

          // ─── APRS stats overlay ────────────────────────
          Positioned(
            top: 8,
            left: 8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AprsStatsChip(
                  filtered: _filteredStations(aprs, mapSettings).length,
                  total: aprs.stations.length,
                ),
                if (_showSpotters && spotter.spotters.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _SpotterCountChip(count: spotter.spotters.length),
                ],
                if (_showRepeaters && _repeaters.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _RepeaterCountChip(
                    count: _repeaters.where((r) {
                      if (!hasPos) return true;
                      return _haversine(myLatLon.latitude, myLatLon.longitude,
                              r.lat, r.lon) <= 100;
                    }).length,
                    source: _repeaterSource,
                  ),
                ],
                if (_isRecording) ...[
                  const SizedBox(height: 4),
                  _RecordingChip(pointCount: track.pointCount),
                ],
                if (_isCachingTiles) ...[
                  const SizedBox(height: 4),
                  _CachingChip(),
                ],
              ],
            ),
          ),

          // ─── North arrow (tap to reset rotation) ───────
          Positioned(
            top: 12,
            right: 12,
            child: _NorthArrow(mapController: _mapController),
          ),

          // ─── Station info popup ────────────────────────
          if (_selectedStation != null)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: _StationInfoCard(
                station: _selectedStation!,
                allSources: aprs.sourcesFor(_selectedStation!.fullCallsign),
                myLat: radio.hasRadioGps ? radio.radioLatitude : gps.latitude,
                myLon: radio.hasRadioGps ? radio.radioLongitude : gps.longitude,
                onClose: () => setState(() => _selectedStation = null),
              ),
            ),

          // ─── Spotter popup ─────────────────────────────
          if (_selectedSpotter != null)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: _SpotterInfoCard(
                spotter: _selectedSpotter!,
                onClose: () => setState(() => _selectedSpotter = null),
              ),
            ),

          // ─── Repeater popup ────────────────────────────
          if (_selectedRepeater != null)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: _RepeaterInfoCard(
                repeater: _selectedRepeater!,
                onClose: () => setState(() => _selectedRepeater = null),
              ),
            ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Cache tiles button
          FloatingActionButton.small(
            heroTag: 'cache',
            onPressed: _isCachingTiles ? null : () => _cacheMapArea(context),
            tooltip: 'Cache map area for offline use',
            backgroundColor: _isCachingTiles ? Colors.grey : Colors.blue[800],
            child: const Icon(Icons.download_outlined, color: Colors.white),
          ),
          const SizedBox(height: 8),
          // Center on location button
          FloatingActionButton(
            heroTag: 'center',
            onPressed: () => _mapController.move(myLatLon, 12),
            tooltip: 'Center on my location',
            child: const Icon(Icons.my_location),
          ),
        ],
      ),
    );
  }

  void _showLayerOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[850],
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('Map Layers', style: TextStyle(color: Colors.white)),
            ),
            // ─── Tile source picker ───────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: MapTileSource.values.map((src) {
                  final selected = _tileSource == src;
                  return GestureDetector(
                    onTap: () {
                      setSheetState(() {});
                      _setTileSource(src);
                      Navigator.pop(ctx);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: selected ? Colors.blue[800] : Colors.grey[700],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected ? Colors.blue : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(MapTileService.icon(src),
                              style: const TextStyle(fontSize: 20)),
                          const SizedBox(height: 4),
                          Text(MapTileService.label(src),
                              style: TextStyle(
                                  color: selected ? Colors.white : Colors.white70,
                                  fontSize: 12)),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const Divider(color: Colors.white24),
            CheckboxListTile(
              title: const Text('APRS Stations', style: TextStyle(color: Colors.white70)),
              value: _showAprs,
              onChanged: (v) {
                setSheetState(() => _showAprs = v ?? true);
                setState(() => _showAprs = v ?? true);
              },
            ),
            CheckboxListTile(
              title: const Text('Storm Spotters', style: TextStyle(color: Colors.white70)),
              value: _showSpotters,
              onChanged: (v) {
                setSheetState(() => _showSpotters = v ?? true);
                setState(() => _showSpotters = v ?? true);
              },
            ),
            CheckboxListTile(
              title: Text(
                'Repeaters (${_repeaters.length} total)',
                style: const TextStyle(color: Colors.white70),
              ),
              subtitle: Text(
                switch (_repeaterSource) {
                  _RepeaterSource.repeaterBook => 'Live · RepeaterBook app · FM only',
                  _RepeaterSource.importedGpx  => 'Imported GPX · FM only',
                  _RepeaterSource.bundledGpx   => 'Bundled CO fallback · FM only',
                },
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
              value: _showRepeaters,
              onChanged: (v) {
                setSheetState(() => _showRepeaters = v ?? true);
                setState(() => _showRepeaters = v ?? true);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleTrackRecording(TrackService track) async {
    if (_isRecording) {
      final path = await track.stopRecording();
      setState(() => _isRecording = false);
      if (mounted && path != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Track saved: ${path.split('/').last}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } else {
      await track.startRecording();
      setState(() => _isRecording = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Track recording started'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  // ─── Map Tile Caching (Section 8) ─────────────────────────────────────────

  Future<void> _cacheMapArea(BuildContext context) async {
    setState(() => _isCachingTiles = true);

    try {
      final bounds = _mapController.camera.visibleBounds;
      final minZoom = 8;
      final maxZoom = 14;

      final cacheDir = await getApplicationCacheDirectory();
      final tilesDir = Directory('${cacheDir.path}/map_tiles');
      await tilesDir.create(recursive: true);

      int total = 0;
      int done  = 0;

      // Count total tiles
      for (int z = minZoom; z <= maxZoom; z++) {
        final tileRange = _boundsToTileRange(bounds, z);
        total += (tileRange[2] - tileRange[0] + 1) * (tileRange[3] - tileRange[1] + 1);
      }

      debugPrint('MapCache: Caching $total tiles (zoom $minZoom–$maxZoom)');

      for (int z = minZoom; z <= maxZoom; z++) {
        final r = _boundsToTileRange(bounds, z);
        for (int x = r[0]; x <= r[2]; x++) {
          for (int y = r[1]; y <= r[3]; y++) {
            final file = File('${tilesDir.path}/$z-$x-$y.png');
            if (!file.existsSync()) {
              try {
                final url = MapTileService.tileUrl(_tileSource, z, x, y);
                final response = await http.get(Uri.parse(url), headers: {
                  'User-Agent': 'OpenHT/0.1 (github.com/repins267/OpenHT)',
                });
                if (response.statusCode == 200) {
                  await file.writeAsBytes(response.bodyBytes);
                }
              } catch (_) {}
              await Future.delayed(const Duration(milliseconds: 50));
            }
            done++;
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cached! $done tiles downloaded for offline use.'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCachingTiles = false);
    }
  }

  /// Returns [xMin, yMin, xMax, yMax] tile coordinates for the given bounds at zoom z.
  List<int> _boundsToTileRange(LatLngBounds bounds, int z) {
    int lat2tile(double lat, int zoom) {
      final latRad = lat * math.pi / 180;
      return ((1 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) /
              2 *
              math.pow(2, zoom))
          .floor();
    }

    int lon2tile(double lon, int zoom) =>
        ((lon + 180) / 360 * math.pow(2, zoom)).floor();

    return [
      lon2tile(bounds.west, z),
      lat2tile(bounds.north, z),
      lon2tile(bounds.east, z),
      lat2tile(bounds.south, z),
    ];
  }
}

// ─── Status Chips ─────────────────────────────────────────────────────────────

class _AprsIsStatusChip extends StatelessWidget {
  final AprsIsState state;
  const _AprsIsStatusChip({required this.state});

  @override
  Widget build(BuildContext context) {
    final color = state == AprsIsState.connected
        ? Colors.green
        : state == AprsIsState.connecting
            ? Colors.orange
            : state == AprsIsState.error
                ? Colors.red
                : Colors.grey;

    final label = state == AprsIsState.connected
        ? 'APRS-IS ✓'
        : state == AprsIsState.connecting
            ? 'APRS-IS…'
            : state == AprsIsState.error
                ? 'APRS-IS ✗'
                : 'APRS-IS off';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}

class _AprsStatsChip extends StatelessWidget {
  final int filtered;
  final int total;
  const _AprsStatsChip({required this.filtered, required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        filtered == total ? '$filtered stations' : '$filtered / $total stations',
        style: const TextStyle(color: Colors.white70, fontSize: 11),
      ),
    );
  }
}

class _SpotterCountChip extends StatelessWidget {
  final int count;
  const _SpotterCountChip({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange, width: 1),
      ),
      child: Text(
        '$count spotters',
        style: const TextStyle(color: Colors.orange, fontSize: 11),
      ),
    );
  }
}

class _RecordingChip extends StatelessWidget {
  final int pointCount;
  const _RecordingChip({required this.pointCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.fiber_manual_record, color: Colors.white, size: 10),
          const SizedBox(width: 4),
          Text('REC $pointCount pts', style: const TextStyle(color: Colors.white, fontSize: 11)),
        ],
      ),
    );
  }
}

class _CachingChip extends StatelessWidget {
  const _CachingChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 10, height: 10,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white)),
          SizedBox(width: 4),
          Text('Caching…', style: TextStyle(color: Colors.white, fontSize: 11)),
        ],
      ),
    );
  }
}

// ─── Marker Widgets ─────────────────────────────────────────────────────────

class _MyPositionMarker extends StatelessWidget {
  final bool fromRadio;
  const _MyPositionMarker({this.fromRadio = false});

  @override
  Widget build(BuildContext context) {
    // Green when using radio GPS, blue when using phone GPS
    final color = fromRadio ? Colors.green : Colors.blue;
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
              color: color.withOpacity(0.4), blurRadius: 8, spreadRadius: 2),
        ],
      ),
      child: fromRadio
          ? const Center(
              child: Icon(Icons.radio, color: Colors.white, size: 10))
          : null,
    );
  }
}

class _AprsStationMarker extends StatelessWidget {
  final AprsPacket station;
  final Set<AprsSource> allSources;
  final bool selected;

  const _AprsStationMarker({
    required this.station,
    required this.allSources,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    // Border color by source: green=RF, blue=IS, yellow=both
    final hasRf = allSources.contains(AprsSource.rf);
    final hasIs = allSources.contains(AprsSource.aprsIs);
    final borderColor = selected
        ? Colors.yellow
        : (hasRf && hasIs)
            ? Colors.yellow[700]!
            : hasRf
                ? Colors.green[400]!
                : Colors.blue[400]!;

    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.grey[850]!.withOpacity(selected ? 1.0 : 0.85),
        border: Border.all(color: borderColor, width: selected ? 2.5 : 1.5),
      ),
      child: Center(
        child: Text(
          _emojiForSymbol(station.symbol),
          style: TextStyle(fontSize: selected ? 18 : 12),
        ),
      ),
    );
  }

  String _emojiForSymbol(String? symbol) {
    switch (symbol) {
      case '>': return '🚗';
      case 'j': return '🚙';
      case '/': return '📡';
      case '_': return '🌤';
      default:  return '📻';
    }
  }
}

class _SpotterMarker extends StatelessWidget {
  final SpotterStation spotter;
  final bool selected;

  const _SpotterMarker({required this.spotter, required this.selected});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.orange.withOpacity(selected ? 1.0 : 0.8),
        border: Border.all(
          color: selected ? Colors.yellow : Colors.white,
          width: selected ? 2.5 : 1.5,
        ),
      ),
      child: Center(
        child: Text('⚡', style: TextStyle(fontSize: selected ? 18 : 12)),
      ),
    );
  }
}

// ─── Info Cards ──────────────────────────────────────────────────────────────

class _StationInfoCard extends StatelessWidget {
  final AprsPacket station;
  final Set<AprsSource> allSources;
  final double? myLat;
  final double? myLon;
  final VoidCallback onClose;

  const _StationInfoCard({
    required this.station,
    required this.allSources,
    required this.myLat,
    required this.myLon,
    required this.onClose,
  });

  String get _distanceStr {
    if (myLat == null || myLon == null || !station.hasPosition) return '';
    final dist = const Distance().as(
      LengthUnit.Mile,
      LatLng(myLat!, myLon!),
      LatLng(station.latitude!, station.longitude!),
    );
    return '${dist.toStringAsFixed(1)} mi';
  }

  @override
  Widget build(BuildContext context) {
    final hasRf = allSources.contains(AprsSource.rf);
    final hasIs = allSources.contains(AprsSource.aprsIs);

    return Card(
      color: Colors.grey[900],
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header row ──────────────────────────────
            Row(
              children: [
                Text(
                  station.fullCallsign,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(width: 6),
                if (hasRf && hasIs)
                  _SourceBadge('RF+IS', Colors.yellow[800]!)
                else if (hasRf)
                  _SourceBadge('RF', Colors.green[700]!)
                else
                  _SourceBadge('IS', Colors.blue[700]!),
                const Spacer(),
                if (_distanceStr.isNotEmpty)
                  Text('📍 $_distanceStr',
                      style: const TextStyle(color: Colors.blue, fontSize: 11)),
                const SizedBox(width: 6),
                GestureDetector(onTap: onClose,
                    child: const Icon(Icons.close, color: Colors.white54, size: 20)),
              ],
            ),

            const SizedBox(height: 4),

            // ── Last heard ──────────────────────────────
            Text('🕐 ${station.timestampDisplay}',
                style: const TextStyle(color: Colors.white54, fontSize: 11)),

            // ── Via path (RF only) ──────────────────────
            if (station.source == AprsSource.rf && station.digiPath != null &&
                station.digiPath!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                '📡 Via: ${station.digiPath}  '
                '(${station.rfHops == 0 ? "direct" : "${station.rfHops} hop${station.rfHops > 1 ? "s" : ""}"})',
                style: const TextStyle(color: Colors.white54, fontSize: 11,
                    fontFamily: 'monospace'),
              ),
            ],

            // ── Comment ─────────────────────────────────
            if (station.comment != null && station.comment!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('💬 "${station.comment}"',
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.message_outlined, size: 16),
                  label: const Text('Message', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[800],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MessageThreadScreen(
                          peerCallsign: station.fullCallsign),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.info_outline, size: 16),
                  label: const Text('Details', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StationDetailScreen(packet: station),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RepeaterCountChip extends StatelessWidget {
  final int count;
  final _RepeaterSource source;
  const _RepeaterCountChip({required this.count, required this.source});

  @override
  Widget build(BuildContext context) {
    final label = switch (source) {
      _RepeaterSource.repeaterBook => '$count rptrs (live)',
      _RepeaterSource.importedGpx  => '$count rptrs (GPX)',
      _RepeaterSource.bundledGpx   => '$count rptrs (CO)',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green, width: 1),
      ),
      child: Text(label, style: const TextStyle(color: Colors.green, fontSize: 11)),
    );
  }
}

class _RepeaterMarker extends StatelessWidget {
  final _MapRepeater repeater;
  final bool selected;
  const _RepeaterMarker({required this.repeater, required this.selected});

  @override
  Widget build(BuildContext context) {
    final isFm = repeater.isFmCompatible;
    final color = isFm
        ? (repeater.band == '2m' ? Colors.green : Colors.blue)
        : Colors.purple;
    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(selected ? 1.0 : 0.85),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: selected ? Colors.yellow : Colors.white,
          width: selected ? 2.5 : 1.5,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.cell_tower,
          color: Colors.white,
          size: selected ? 22 : 14,
        ),
      ),
    );
  }
}

class _RepeaterInfoCard extends StatelessWidget {
  final _MapRepeater repeater;
  final VoidCallback onClose;
  const _RepeaterInfoCard({required this.repeater, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final radio  = context.read<RadioService>();
    final freqStr = repeater.outputFreq.toStringAsFixed(3);
    final toneStr = repeater.ctcssHz != null
        ? 'PL ${repeater.ctcssHz!.toStringAsFixed(1)} Hz'
        : 'No tone';

    return Card(
      color: Colors.grey[900],
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: repeater.band == '2m'
                        ? Colors.green[800]
                        : Colors.blue[800],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(repeater.band,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
                Text(repeater.callsign,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('${repeater.distanceMiles.toStringAsFixed(1)} mi',
                    style: const TextStyle(color: Colors.amber, fontSize: 12)),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onClose,
                  child: const Icon(Icons.close,
                      color: Colors.white54, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '$freqStr MHz  ${repeater.offsetDir}  $toneStr',
              style: TextStyle(
                  color: Colors.green[300],
                  fontSize: 13,
                  fontFamily: 'monospace'),
            ),
            if (repeater.serviceText.isNotEmpty && repeater.serviceText != 'FM') ...[
              const SizedBox(height: 2),
              Text(
                repeater.serviceText.trim(),
                style: TextStyle(color: Colors.purple[300], fontSize: 11),
              ),
            ],
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.radio, size: 16),
                label: const Text('Tap to Tune (VFO A)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: radio.isConnected
                      ? Colors.blue[700]
                      : Colors.grey[700],
                ),
                onPressed: radio.isConnected
                    ? () {
                        radio.tuneToRepeaterGpx(
                          outputFreqMhz: repeater.outputFreq,
                          ctcssHz: repeater.ctcssHz,
                          name: repeater.callsign,
                        );
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(
                              'Tuned VFO A → ${repeater.callsign} $freqStr MHz'),
                          backgroundColor: Colors.blue[800],
                          duration: const Duration(seconds: 2),
                        ));
                        onClose();
                      }
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── North arrow ───────────────────────────────────────────────────────────────
class _NorthArrow extends StatelessWidget {
  final MapController mapController;
  const _NorthArrow({required this.mapController});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => mapController.rotate(0),
      child: Tooltip(
        message: 'Reset North',
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.black54,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24, width: 1),
          ),
          child: CustomPaint(painter: _NorthArrowPainter()),
        ),
      ),
    );
  }
}

class _NorthArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final tipN = Offset(cx, cy - 14);
    final tipS = Offset(cx, cy + 14);
    final left = Offset(cx - 5, cy + 2);
    final right = Offset(cx + 5, cy + 2);
    final leftS = Offset(cx - 5, cy - 2);
    final rightS = Offset(cx + 5, cy - 2);

    // North half — red
    final redPaint = Paint()..color = Colors.red..style = PaintingStyle.fill;
    final northPath = ui.Path()
      ..moveTo(tipN.dx, tipN.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();
    canvas.drawPath(northPath, redPaint);

    // South half — white
    final whitePaint = Paint()..color = Colors.white..style = PaintingStyle.fill;
    final southPath = ui.Path()
      ..moveTo(tipS.dx, tipS.dy)
      ..lineTo(leftS.dx, leftS.dy)
      ..lineTo(rightS.dx, rightS.dy)
      ..close();
    canvas.drawPath(southPath, whitePaint);

    // "N" label
    final tp = TextPainter(
      text: const TextSpan(
        text: 'N',
        style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, 2));
  }

  @override
  bool shouldRepaint(_NorthArrowPainter old) => false;
}

// ── Source badge ──────────────────────────────────────────────────────────────
class _SourceBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _SourceBadge(this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.85),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label,
            style: const TextStyle(
                color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
      );
}


class _SpotterInfoCard extends StatelessWidget {
  final SpotterStation spotter;
  final VoidCallback onClose;

  const _SpotterInfoCard({required this.spotter, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.grey[900],
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text('⚡ ', style: TextStyle(fontSize: 16)),
                Text(
                  spotter.name,
                  style: const TextStyle(
                    color: Colors.orange,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                GestureDetector(onTap: onClose,
                    child: const Icon(Icons.close, color: Colors.white54, size: 20)),
              ],
            ),
            if (spotter.reportType != null)
              Text(spotter.reportType!,
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            if (spotter.description != null)
              Text(spotter.description!,
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 4),
            Text(
              '${spotter.lat.toStringAsFixed(4)}°, ${spotter.lon.toStringAsFixed(4)}°',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
            if (spotter.lastReport != null)
              Text(
                spotter.lastReport!,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
          ],
        ),
      ),
    );
  }
}
