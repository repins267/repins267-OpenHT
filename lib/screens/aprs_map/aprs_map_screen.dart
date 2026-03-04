// lib/screens/aprs_map/aprs_map_screen.dart
// APRS station map using OpenStreetMap via flutter_map
// Displays APRS beacons as POI markers

import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../../services/gps_service.dart';
import '../../aprs/aprs_service.dart';
import '../../aprs/aprs_is_service.dart';
import '../../aprs/aprs_packet.dart';
import '../../services/spotter_service.dart';
import '../../models/spotter_station.dart';
import '../../services/track_service.dart';

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
  bool _showSpotters = true;
  bool _isRecording = false;
  bool _isCachingTiles = false;

  @override
  void initState() {
    super.initState();
    // Wire APRS-IS packets into AprsService
    WidgetsBinding.instance.addPostFrameCallback((_) => _initAprsIs());
  }

  void _initAprsIs() {
    final aprsIs = context.read<AprsIsService>();
    final aprs   = context.read<AprsService>();
    aprs.attachPacketStream(aprsIs.packets);
    aprsIs.connect();
  }

  @override
  Widget build(BuildContext context) {
    final gps     = context.watch<GpsService>();
    final aprs    = context.watch<AprsService>();
    final aprsIs  = context.watch<AprsIsService>();
    final spotter = context.watch<SpotterService>();
    final track   = context.watch<TrackService>();

    final myLatLon = gps.hasPosition
        ? LatLng(gps.latitude!, gps.longitude!)
        : const LatLng(39.8283, -98.5795); // Geographic center of USA

    if (_followMyLocation && gps.hasPosition) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _mapController.move(myLatLon, _mapController.camera.zoom);
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('APRS Map'),
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
              }),
            ),
            children: [
              // Base tile layer (OpenStreetMap)
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.openht.app',
                maxZoom: 19,
              ),

              // APRS station markers
              MarkerLayer(
                markers: [
                  // My position marker
                  if (gps.hasPosition)
                    Marker(
                      point: myLatLon,
                      width: 24,
                      height: 24,
                      child: _MyPositionMarker(),
                    ),

                  // APRS station POIs
                  ...aprs.stations.where((s) => s.hasPosition).map((station) {
                    final isSelected = _selectedStation?.callsign == station.callsign;
                    return Marker(
                      point: LatLng(station.latitude!, station.longitude!),
                      width: isSelected ? 48 : 32,
                      height: isSelected ? 48 : 32,
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _selectedStation = station;
                          _selectedSpotter = null;
                        }),
                        child: _AprsStationMarker(station: station, selected: isSelected),
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
                          }),
                          child: _SpotterMarker(spotter: s, selected: isSelected),
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
            right: 8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _AprsStatsChip(stationCount: aprs.stations.length),
                if (_showSpotters && spotter.spotters.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _SpotterCountChip(count: spotter.spotters.length),
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

          // ─── Station info popup ────────────────────────
          if (_selectedStation != null)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: _StationInfoCard(
                station: _selectedStation!,
                myLat: gps.latitude,
                myLon: gps.longitude,
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
            CheckboxListTile(
              title: const Text('APRS Stations', style: TextStyle(color: Colors.white70)),
              value: true,
              onChanged: (_) {},
            ),
            CheckboxListTile(
              title: const Text('Storm Spotters', style: TextStyle(color: Colors.white70)),
              value: _showSpotters,
              onChanged: (v) {
                setSheetState(() => _showSpotters = v ?? true);
                setState(() => _showSpotters = v ?? true);
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
                final url = 'https://tile.openstreetmap.org/$z/$x/$y.png';
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
  final int stationCount;
  const _AprsStatsChip({required this.stationCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$stationCount stations',
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
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.blue,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(color: Colors.blue.withOpacity(0.4), blurRadius: 8, spreadRadius: 2),
        ],
      ),
    );
  }
}

class _AprsStationMarker extends StatelessWidget {
  final AprsPacket station;
  final bool selected;

  const _AprsStationMarker({required this.station, required this.selected});

  @override
  Widget build(BuildContext context) {
    final color = _colorForSymbol(station.symbol);
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(selected ? 1.0 : 0.7),
        border: Border.all(
          color: selected ? Colors.yellow : Colors.white,
          width: selected ? 2.5 : 1.5,
        ),
      ),
      child: Center(
        child: Text(
          _emojiForSymbol(station.symbol),
          style: TextStyle(fontSize: selected ? 18 : 12),
        ),
      ),
    );
  }

  Color _colorForSymbol(String? symbol) {
    switch (symbol) {
      case '>': return Colors.green;
      case 'j': return Colors.orange;
      case '/': return Colors.purple;
      case '_': return Colors.cyan;
      default:  return Colors.grey;
    }
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
  final double? myLat;
  final double? myLon;
  final VoidCallback onClose;

  const _StationInfoCard({
    required this.station,
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
    return '${dist.toStringAsFixed(1)} mi away';
  }

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
                Text(
                  station.callsign,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(_distanceStr,
                    style: const TextStyle(color: Colors.blue, fontSize: 12)),
                const SizedBox(width: 8),
                GestureDetector(onTap: onClose,
                    child: const Icon(Icons.close, color: Colors.white54, size: 20)),
              ],
            ),
            if (station.comment != null)
              Text(station.comment!,
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 4),
            Text(
              station.timestampDisplay,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
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
