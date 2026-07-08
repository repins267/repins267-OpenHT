// lib/screens/near_repeater/near_repeater_screen.dart
// Near Repeater — primary source: RepeaterBook app content provider (live, North America).
// Fallbacks: cached provider data, then user-imported GPX/CSV exports.
// No repeater data is bundled with the app (RepeaterBook policy: offline
// bundling/redistribution requires written permission).

import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/gps_service.dart';
import '../../bluetooth/radio_service.dart';
import '../../services/repeaterbook_connect_service.dart';
import '../../services/repeaterbook_service.dart';

// Returns radio GPS if the radio has a fix, otherwise falls back to phone GPS.
({double? lat, double? lon, bool hasPos}) _bestGps(
    GpsService gps, RadioService radio) {
  if (radio.hasRadioGps) {
    return (lat: radio.radioLatitude, lon: radio.radioLongitude, hasPos: true);
  }
  return (
    lat: gps.latitude,
    lon: gps.longitude,
    hasPos: gps.hasPosition,
  );
}

// ─── Data model ───────────────────────────────────────────────────────────────

class _Repeater {
  final double lat;
  final double lon;
  final String callsign;
  final double outputFreq;   // MHz — what the radio receives
  final String offsetDir;    // '+', '-', or ''
  final double? ctcssHz;     // CTCSS tone in Hz, null = no tone
  final String location;     // from <desc>
  final bool isOpen;
  final String band;         // '2m' or '70cm'
  final String serviceText;  // 'FM', 'FM Fusion', 'DMR', etc.
  double distanceMiles = 0;

  _Repeater({
    required this.lat,
    required this.lon,
    required this.callsign,
    required this.outputFreq,
    required this.offsetDir,
    this.ctcssHz,
    required this.location,
    required this.isOpen,
    required this.band,
    this.serviceText = 'FM',
  });

  bool get isFmCompatible => serviceText.toUpperCase().contains('FM');
}

// ─── Haversine distance (miles) ───────────────────────────────────────────────

double _distanceMiles(double lat1, double lon1, double lat2, double lon2) {
  const r = 3958.8;
  final dLat = _deg2rad(lat2 - lat1);
  final dLon = _deg2rad(lon2 - lon1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_deg2rad(lat1)) *
          math.cos(_deg2rad(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _deg2rad(double deg) => deg * math.pi / 180.0;

// ─── Input freq helper ────────────────────────────────────────────────────────

double _computeInputFreq(_Repeater r) {
  if (r.offsetDir.isEmpty) return r.outputFreq; // simplex
  final offset = r.outputFreq >= 400 ? 5.0 : 0.6; // 70cm vs 2m standard offset
  return r.offsetDir == '+' ? r.outputFreq + offset : r.outputFreq - offset;
}

// ─── Export builders ──────────────────────────────────────────────────────────

String _xmlEsc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String _csvEsc(String s) =>
    (s.contains(',') || s.contains('"')) ? '"${s.replaceAll('"', '""')}"' : s;

/// GPX in RepeaterBook-app <name> layout so OpenHT can re-import it later.
/// Repeaters without coordinates (CSV-sourced) are skipped.
String _buildGpx(List<_Repeater> list) {
  final b = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8" standalone="no" ?>')
    ..writeln('<gpx version="1.1" creator="OpenHT" '
        'xmlns="http://www.topografix.com/GPX/1/1">');
  for (final r in list) {
    if (r.lat == 0.0 && r.lon == 0.0) continue;
    final tone = r.ctcssHz != null ? ' ${r.ctcssHz!.toStringAsFixed(1)}' : '';
    final freq = r.outputFreq.toStringAsFixed(6);
    final name = '${r.callsign} $freq $freq${r.offsetDir}$tone';
    final desc = '${r.location} ${r.callsign} '
        '${r.isOpen ? 'OPEN' : 'CLOSED'} ${r.serviceText}';
    b
      ..writeln('  <wpt lat="${r.lat}" lon="${r.lon}">')
      ..writeln('    <name>${_xmlEsc(name)}</name>')
      ..writeln('    <desc>${_xmlEsc(desc)}</desc>')
      ..writeln('  </wpt>');
  }
  b.writeln('</gpx>');
  return b.toString();
}

/// CSV in repeaterbook.com column order so it round-trips through import.
String _buildCsv(List<_Repeater> list) {
  final b = StringBuffer()
    ..writeln('Output Freq,Input Freq,Offset,Uplink Tone,Downlink Tone,'
        'Call,Location,Modes');
  for (final r in list) {
    final tone = r.ctcssHz != null ? r.ctcssHz!.toStringAsFixed(1) : '';
    b.writeln([
      r.outputFreq.toStringAsFixed(6),
      _computeInputFreq(r).toStringAsFixed(6),
      r.offsetDir,
      tone,
      tone,
      _csvEsc(r.callsign),
      _csvEsc(r.location),
      _csvEsc(r.serviceText),
    ].join(','));
  }
  return b.toString();
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class NearRepeaterScreen extends StatefulWidget {
  const NearRepeaterScreen({super.key});

  @override
  State<NearRepeaterScreen> createState() => _NearRepeaterScreenState();
}

enum _DataSource { repeaterBook, cachedLive, importedGpx, none }

class _NearRepeaterScreenState extends State<NearRepeaterScreen> {
  List<_Repeater> _all = [];
  bool _isLoading = true;
  String? _error;
  String _bandFilter = 'All';
  bool _onlyOpen = true;
  bool _onlyFmCompat = true;
  int _maxMiles = 150; // max distance filter; 0 = no limit
  int? _tuningIndex;
  bool _isWritingGroup = false;
  final Set<_Repeater> _selectedRepeaters = {};
  _DataSource _dataSource = _DataSource.none;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _selectedRepeaters.clear();
    });

    final gps       = context.read<GpsService>();
    final radio     = context.read<RadioService>();
    final rbService = context.read<RepeaterBookService>();
    final pos   = _bestGps(gps, radio);
    final double? lat = pos.hasPos ? pos.lat : null;
    final double? lon = pos.hasPos ? pos.lon : null;

    // ── Try RepeaterBook content provider first ──────────────────────────────
    try {
      final rbRepeaters = await RepeaterBookConnectService.queryRepeaters();
      if (rbRepeaters.isNotEmpty) {
        final all = rbRepeaters.map((r) => _Repeater(
          lat: r.lat,
          lon: r.lon,
          callsign: r.callsign,
          outputFreq: r.outputFreq,
          offsetDir: r.outputFreq > r.inputFreq ? '-' : (r.outputFreq < r.inputFreq ? '+' : ''),
          ctcssHz: r.ctcssHz,
          location: r.location,
          isOpen: r.isOpen,
          band: r.band,
          serviceText: r.serviceText,
        )).toList();

        if (lat != null && lon != null) {
          for (final r in all) {
            r.distanceMiles = _distanceMiles(lat, lon, r.lat, r.lon);
          }
          all.sort((a, b) => a.distanceMiles.compareTo(b.distanceMiles));
        }

        if (mounted) {
          setState(() {
            _all = all;
            _dataSource = _DataSource.repeaterBook;
            _isLoading = false;
          });
        }
        return;
      }
    } catch (e) {
      debugPrint('NearRepeater: RepeaterBook provider failed: $e');
    }

    // ── Fallback 1: cached live data from previous RepeaterBook query ────────
    if (RepeaterBookConnectService.hasCachedData) {
      final rbRepeaters = RepeaterBookConnectService.cachedRepeaters;
      final all = rbRepeaters.map((r) => _Repeater(
        lat: r.lat,
        lon: r.lon,
        callsign: r.callsign,
        outputFreq: r.outputFreq,
        offsetDir: r.outputFreq > r.inputFreq ? '-' : (r.outputFreq < r.inputFreq ? '+' : ''),
        ctcssHz: r.ctcssHz,
        location: r.location,
        isOpen: r.isOpen,
        band: r.band,
        serviceText: r.serviceText,
      )).toList();

      if (lat != null && lon != null) {
        for (final r in all) {
          r.distanceMiles = _distanceMiles(lat, lon, r.lat, r.lon);
        }
        all.sort((a, b) => a.distanceMiles.compareTo(b.distanceMiles));
      }

      if (mounted) {
        setState(() {
          _all = all;
          _dataSource = _DataSource.cachedLive;
          _isLoading = false;
        });
      }
      return;
    }

    // ── Fallback 2: imported GPX cache (RepeaterBookService) ────────────────
    if (rbService.hasData) {
      final all = rbService.repeaters.map((r) => _Repeater(
        lat: r.lat,
        lon: r.lon,
        callsign: r.callsign,
        outputFreq: r.outputFreq,
        offsetDir: r.outputFreq > r.inputFreq ? '-' : (r.outputFreq < r.inputFreq ? '+' : ''),
        ctcssHz: r.ctcssHz,
        location: '${r.city}, ${r.state}'.trim().replaceAll(RegExp(r'^,\s*|,\s*$'), ''),
        isOpen: r.isOpen,
        band: r.band,
      )).toList();

      if (lat != null && lon != null) {
        for (final r in all) {
          r.distanceMiles = _distanceMiles(lat, lon, r.lat, r.lon);
        }
        all.sort((a, b) => a.distanceMiles.compareTo(b.distanceMiles));
      }

      if (mounted) {
        setState(() {
          _all = all;
          _dataSource = _DataSource.importedGpx;
          _isLoading = false;
        });
      }
      return;
    }

    // ── No data available — show empty state prompting RB app / import ──────
    if (mounted) {
      setState(() {
        _all = [];
        _dataSource = _DataSource.none;
        _isLoading = false;
      });
    }
  }

  Future<void> _import() async {
    final rbService = context.read<RepeaterBookService>();
    // FileType.custom with a 'gpx'/'csv' allowlist is unreliable on Android
    // (many document providers won't surface those extensions). Pick anything,
    // then validate by name; withData:true covers content:// URIs with no path.
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: true,
      withData: true,
      dialogTitle: 'Select RepeaterBook GPX or CSV export(s)',
    );
    if (result == null || result.files.isEmpty) return;

    int totalAdded = 0;
    int handled = 0;
    for (final file in result.files) {
      final name = file.name.toLowerCase();
      // RepeaterBook's website CSV export downloads as "RB_<timestamp>.csv.xls";
      // accept .xls and let importFile's content sniffing sort out the format.
      if (!name.endsWith('.gpx') && !name.endsWith('.csv') && !name.endsWith('.xls')) {
        continue;
      }
      try {
        final added = await rbService.importFile(
          file.path ?? file.name,
          bytes: file.bytes,
        );
        totalAdded += added;
        handled++;
      } catch (e) {
        debugPrint('NearRepeater: import failed for ${file.name}: $e');
      }
    }

    if (!mounted) return;
    final msg = handled == 0
        ? 'No .gpx, .csv, or .xls files selected'
        : totalAdded > 0
            ? 'Imported $totalAdded new repeaters — reloading…'
            : (rbService.error ?? 'No new repeaters found in file(s)');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: totalAdded > 0 ? Colors.green[700] : Colors.orange[700],
    ));
    if (totalAdded > 0) _load();
  }

  Future<void> _exportList() async {
    final gps   = context.read<GpsService>();
    final radio = context.read<RadioService>();
    final pos   = _bestGps(gps, radio);
    final list  = _filtered(pos.hasPos ? pos.lat : null, pos.hasPos ? pos.lon : null);
    if (list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing to export')));
      return;
    }
    try {
      final dir = await getTemporaryDirectory();
      final gpxFile = File('${dir.path}/openht_repeaters.gpx');
      final csvFile = File('${dir.path}/openht_repeaters.csv');
      await gpxFile.writeAsString(_buildGpx(list));
      await csvFile.writeAsString(_buildCsv(list));
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(gpxFile.path), XFile(csvFile.path)],
        text: 'OpenHT — ${list.length} repeaters',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')));
    }
  }

  Future<void> _clearImportedGpx() async {
    final rbService = context.read<RepeaterBookService>();
    await rbService.clearAll();
    if (mounted) _load();
  }

  List<_Repeater> _filtered(double? lat, double? lon) {
    // Recompute distances first so the distance filter is accurate.
    if (lat != null && lon != null) {
      for (final r in _all) {
        r.distanceMiles = _distanceMiles(lat, lon, r.lat, r.lon);
      }
    }

    final list = _all.where((r) {
      if (_bandFilter == '2m'   && r.band != '2m')   return false;
      if (_bandFilter == '70cm' && r.band != '70cm') return false;
      if (_onlyOpen && !r.isOpen) return false;
      if (_onlyFmCompat && !r.isFmCompatible) return false;
      if (_maxMiles > 0 && lat != null && lon != null &&
          r.distanceMiles > _maxMiles) return false;
      return true;
    }).toList();

    if (lat != null && lon != null) {
      list.sort((a, b) => a.distanceMiles.compareTo(b.distanceMiles));
    }
    return list;
  }

  void _toggleSelection(_Repeater r) {
    setState(() {
      if (_selectedRepeaters.contains(r)) {
        _selectedRepeaters.remove(r);
      } else {
        _selectedRepeaters.add(r);
      }
    });
  }

  Future<void> _tune(_Repeater r, int index) async {
    final radio = context.read<RadioService>();
    if (!radio.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Radio not connected')),
      );
      return;
    }

    setState(() => _tuningIndex = index);
    final tuneOk = await radio.tuneToRepeaterGpx(
      outputFreqMhz: r.outputFreq,
      ctcssHz: r.ctcssHz,
      name: r.callsign,
    );
    if (!mounted) return;
    setState(() => _tuningIndex = null);

    final freqStr = r.outputFreq.toStringAsFixed(3);
    final toneStr = r.ctcssHz != null ? ' · PL ${r.ctcssHz!.toStringAsFixed(1)} Hz' : '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tuneOk
            ? 'Tuned to $freqStr MHz$toneStr'
            : 'Tune failed: ${radio.errorMessage}'),
        backgroundColor: tuneOk ? Colors.green[700] : Colors.red[700],
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _writeGroupToRadio() async {
    final radio = context.read<RadioService>();
    if (!radio.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Radio not connected')),
      );
      return;
    }

    // Use selected repeaters (sorted by distance), or fall back to closest 32 from filter
    final gps   = context.read<GpsService>();
    final pos   = _bestGps(gps, radio);
    final lat   = pos.hasPos ? pos.lat : null;
    final lon   = pos.hasPos ? pos.lon : null;
    List<_Repeater> toWrite;
    if (_selectedRepeaters.isNotEmpty) {
      toWrite = _selectedRepeaters.toList()
        ..sort((a, b) => a.distanceMiles.compareTo(b.distanceMiles));
      toWrite = toWrite.take(32).toList();
    } else {
      toWrite = _filtered(lat, lon).take(32).toList();
    }

    if (toWrite.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No repeaters to write')),
      );
      return;
    }

    setState(() => _isWritingGroup = true);

    final channels = toWrite.map((r) => (
      outputFreqMhz: r.outputFreq,
      inputFreqMhz: _computeInputFreq(r),
      ctcssHz: r.ctcssHz,
      name: r.callsign,
    )).toList();

    final written = await radio.bulkWriteNearRepeaterGroup(channels: channels);

    if (!mounted) return;
    setState(() => _isWritingGroup = false);

    final sourceLabel = _selectedRepeaters.isNotEmpty
        ? '${_selectedRepeaters.length} selected'
        : 'closest ${toWrite.length}';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Wrote $written/${toWrite.length} to "Near Repeaters" Group 6 ($sourceLabel)'),
        backgroundColor: written == toWrite.length
            ? Colors.green[700]
            : written > 0
                ? Colors.orange[700]
                : Colors.red[700],
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gps      = context.watch<GpsService>();
    final radio    = context.watch<RadioService>();
    final pos      = _bestGps(gps, radio);
    final list     = _filtered(pos.hasPos ? pos.lat : null, pos.hasPos ? pos.lon : null);
    final selCount = _selectedRepeaters.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Near Repeaters'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          if (_isWritingGroup)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
            )
          else
            Badge(
              isLabelVisible: selCount > 0,
              label: Text('$selCount'),
              child: IconButton(
                icon: const Icon(Icons.save_alt),
                tooltip: selCount > 0
                    ? 'Write $selCount selected to Group 6'
                    : 'Write closest 32 to Group 6',
                onPressed: _isLoading ? null : _writeGroupToRadio,
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
            onPressed: _isLoading ? null : _load,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              if (v == 'deselect') setState(() => _selectedRepeaters.clear());
              if (v == 'import')   _import();
              if (v == 'export')   _exportList();
              if (v == 'clear')    _clearImportedGpx();
            },
            itemBuilder: (_) => [
              if (selCount > 0)
                PopupMenuItem(
                  value: 'deselect',
                  child: ListTile(
                    leading: const Icon(Icons.deselect),
                    title: Text('Clear $selCount selected'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              const PopupMenuItem(
                value: 'import',
                child: ListTile(
                  leading: Icon(Icons.file_upload_outlined),
                  title: Text('Import GPX / CSV…'),
                  subtitle: Text('Load a repeaterbook.com export'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'export',
                child: ListTile(
                  leading: Icon(Icons.ios_share),
                  title: Text('Export list…'),
                  subtitle: Text('Share current list as GPX + CSV'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: ListTile(
                  leading: Icon(Icons.delete_outline, color: Colors.red),
                  title: Text('Clear imported data'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _StatusBar(gps: gps, radio: radio, usingRadioGps: radio.hasRadioGps),
          _FilterBar(
            bandFilter: _bandFilter,
            onlyOpen: _onlyOpen,
            onlyFmCompat: _onlyFmCompat,
            maxMiles: _maxMiles,
            onBandChanged: (v) => setState(() => _bandFilter = v),
            onOpenChanged: (v) => setState(() => _onlyOpen = v),
            onFmCompatChanged: (v) => setState(() => _onlyFmCompat = v),
            onMaxMilesChanged: (v) => setState(() => _maxMiles = v),
          ),
          _InfoBanner(selectedCount: selCount),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _ErrorState(error: _error!, onRetry: _load)
                    : list.isEmpty
                        ? _EmptyState(
                            onImport: _import,
                            noData: _dataSource == _DataSource.none,
                          )
                        : ListView.builder(
                            itemCount: list.length + 1,
                            itemBuilder: (ctx, i) {
                              if (i == list.length) return _attributionFooter();
                              final r = list[i];
                              final selected = _selectedRepeaters.contains(r);
                              return _RepeaterCard(
                                repeater: r,
                                isTuning: _tuningIndex == i,
                                radioConnected: radio.isConnected,
                                isSelected: selected,
                                onToggle: () => _toggleSelection(r),
                                onTune: () => _tune(r, i),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _attributionFooter() {
    final rbService = context.read<RepeaterBookService>();
    String _ageLabel(DateTime? dt) {
      if (dt == null) return '';
      final d = DateTime.now().difference(dt);
      if (d.inDays  > 0) return ' · cached ${d.inDays}d ago';
      if (d.inHours > 0) return ' · cached ${d.inHours}h ago';
      return ' · cached ${d.inMinutes}m ago';
    }
    final text = switch (_dataSource) {
      _DataSource.repeaterBook => 'Live data via RepeaterBook app · © RepeaterBook.com',
      _DataSource.cachedLive   => 'Cached RepeaterBook data${_ageLabel(RepeaterBookConnectService.cachedAt)} · © RepeaterBook.com · Open RB app to refresh',
      _DataSource.importedGpx  => '${_all.length} repeaters from ${rbService.importCount} GPX file(s) · © RepeaterBook.com',
      _DataSource.none         => 'No repeater data · open the RepeaterBook app or tap ⋮ to import',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white24, fontSize: 10),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _InfoBanner extends StatelessWidget {
  final int selectedCount;
  const _InfoBanner({required this.selectedCount});

  @override
  Widget build(BuildContext context) {
    final text = selectedCount > 0
        ? '$selectedCount selected · set radio to "Near Repeaters" (Group 6) · tap ↓ to write'
        : 'Set radio to Group 6 "Near Repeaters" · Tap ↓ to write · Tap radio icon to tune';
    return Container(
      width: double.infinity,
      color: Colors.grey[800],
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(
        text,
        style: TextStyle(
          color: selectedCount > 0 ? Colors.blue[200] : Colors.white38,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  final GpsService gps;
  final RadioService radio;
  final bool usingRadioGps;

  const _StatusBar({
    required this.gps,
    required this.radio,
    required this.usingRadioGps,
  });

  @override
  Widget build(BuildContext context) {
    final hasPos = usingRadioGps || gps.hasPosition;
    final posLabel = usingRadioGps
        ? '📡 Radio GPS: ${radio.radioLatitude!.toStringAsFixed(4)}°, '
          '${radio.radioLongitude!.toStringAsFixed(4)}°'
        : gps.hasPosition
            ? '📱 ${gps.displayPosition}'
            : 'Waiting for GPS…';

    return Container(
      color: Colors.grey[900],
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Row(
        children: [
          Icon(
            hasPos ? Icons.gps_fixed : Icons.gps_off,
            size: 13,
            color: usingRadioGps
                ? Colors.green
                : gps.hasPosition
                    ? Colors.blue
                    : Colors.orange,
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              posLabel,
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ),
          Icon(
            radio.isConnected
                ? Icons.bluetooth_connected
                : Icons.bluetooth_disabled,
            size: 13,
            color: radio.isConnected ? Colors.blue : Colors.grey,
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final String bandFilter;
  final bool onlyOpen;
  final bool onlyFmCompat;
  final int maxMiles;
  final ValueChanged<String> onBandChanged;
  final ValueChanged<bool> onOpenChanged;
  final ValueChanged<bool> onFmCompatChanged;
  final ValueChanged<int> onMaxMilesChanged;

  const _FilterBar({
    required this.bandFilter,
    required this.onlyOpen,
    required this.onlyFmCompat,
    required this.maxMiles,
    required this.onBandChanged,
    required this.onOpenChanged,
    required this.onFmCompatChanged,
    required this.onMaxMilesChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey[850],
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          for (final b in ['All', '2m', '70cm'])
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(b, style: const TextStyle(fontSize: 12)),
                selected: bandFilter == b,
                onSelected: (_) => onBandChanged(b),
                selectedColor: b == '2m'
                    ? Colors.green[700]
                    : b == '70cm'
                        ? Colors.blue[700]
                        : Colors.grey[600],
                labelStyle: TextStyle(
                  color: bandFilter == b ? Colors.white : Colors.white70,
                ),
              ),
            ),
          const Spacer(),
          // Radius filter
          DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: maxMiles,
              isDense: true,
              dropdownColor: Colors.grey[850],
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              items: const [
                DropdownMenuItem(value: 50,  child: Text('50 mi')),
                DropdownMenuItem(value: 100, child: Text('100 mi')),
                DropdownMenuItem(value: 150, child: Text('150 mi')),
                DropdownMenuItem(value: 300, child: Text('300 mi')),
                DropdownMenuItem(value: 0,   child: Text('Any dist')),
              ],
              onChanged: (v) => onMaxMilesChanged(v ?? 150),
            ),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: 'Hide DMR/D-Star/digital-only repeaters',
            child: Text('FM', style: TextStyle(
              color: onlyFmCompat ? Colors.green[300] : Colors.white38,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            )),
          ),
          Switch(
            value: onlyFmCompat,
            onChanged: onFmCompatChanged,
            activeThumbColor: Colors.green,
          ),
          const Text('Open', style: TextStyle(color: Colors.white70, fontSize: 12)),
          Switch(
            value: onlyOpen,
            onChanged: onOpenChanged,
            activeThumbColor: Colors.green,
          ),
        ],
      ),
    );
  }
}

class _RepeaterCard extends StatelessWidget {
  final _Repeater repeater;
  final bool isTuning;
  final bool radioConnected;
  final bool isSelected;
  final VoidCallback onToggle;
  final VoidCallback onTune;

  const _RepeaterCard({
    required this.repeater,
    required this.isTuning,
    required this.radioConnected,
    required this.isSelected,
    required this.onToggle,
    required this.onTune,
  });

  @override
  Widget build(BuildContext context) {
    final r = repeater;
    final freqStr = r.outputFreq.toStringAsFixed(3);
    final distStr = r.distanceMiles > 0
        ? '${r.distanceMiles.toStringAsFixed(1)} mi'
        : '';
    final toneStr = r.ctcssHz != null
        ? 'PL ${r.ctcssHz!.toStringAsFixed(1)} Hz'
        : 'No tone';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      color: isSelected ? Colors.blue[900] : Colors.grey[850],
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Selection checkbox
              SizedBox(
                width: 32,
                height: 32,
                child: Checkbox(
                  value: isSelected,
                  onChanged: (_) => onToggle(),
                  activeColor: Colors.blue[400],
                  side: const BorderSide(color: Colors.white38),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),

              // Band badge
              Container(
                width: 36,
                padding: const EdgeInsets.symmetric(vertical: 3),
                decoration: BoxDecoration(
                  color: r.band == '2m' ? Colors.green[900] : Colors.blue[900],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  r.band,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: r.band == '2m' ? Colors.green[300] : Colors.blue[300],
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Main info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.callsign,
                      style: TextStyle(
                        color: r.isOpen ? Colors.white : Colors.white38,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '$freqStr MHz  ${r.offsetDir}  $toneStr',
                            style: TextStyle(
                              color: Colors.green[400],
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (r.serviceText.isNotEmpty && r.serviceText != 'FM') ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.purple[900],
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              r.serviceText.trim(),
                              style: TextStyle(color: Colors.purple[200], fontSize: 9),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      r.location,
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),

              // Distance + Tune button (stacked)
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (distStr.isNotEmpty)
                    Text(
                      distStr,
                      style: TextStyle(
                        color: Colors.amber[300],
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  isTuning
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : IconButton(
                          icon: Icon(
                            Icons.radio,
                            color: radioConnected ? Colors.blue[400] : Colors.grey,
                          ),
                          tooltip: 'Tune to ${r.callsign}',
                          onPressed: radioConnected
                              ? () {
                                  onTune();
                                }
                              : null,
                          iconSize: 22,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onImport;
  final bool noData;
  const _EmptyState({required this.onImport, required this.noData});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cell_tower, size: 64, color: Colors.white24),
            const SizedBox(height: 12),
            Text(
              noData
                  ? 'No repeater data loaded.\n\nInstall the RepeaterBook app and '
                    'load your area for live data (requires RepeaterBook Connect), '
                    'or import a GPX/CSV export from repeaterbook.com.'
                  : 'No repeaters match the current filters.\n\n'
                    'Try widening the distance filter or turning off "FM only".',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.file_upload_outlined),
              label: const Text('Import GPX / CSV'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
