// lib/screens/near_repeater/near_repeater_screen.dart
// Near Repeater — fully offline, loads from bundled GPX assets (no network).
// GPX data © RepeaterBook.com · Colorado 2m/70cm · Exported 2026-03-03

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:xml/xml.dart';
import '../../services/gps_service.dart';
import '../../bluetooth/radio_service.dart';

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
  });
}

// ─── GPX parsing ─────────────────────────────────────────────────────────────

List<_Repeater> _parseGpx(String gpxXml, String band) {
  final doc = XmlDocument.parse(gpxXml);
  final repeaters = <_Repeater>[];

  for (final wpt in doc.findAllElements('wpt')) {
    final lat = double.tryParse(wpt.getAttribute('lat') ?? '') ?? 0.0;
    final lon = double.tryParse(wpt.getAttribute('lon') ?? '') ?? 0.0;
    if (lat == 0.0 && lon == 0.0) continue;

    final nameEl = wpt.findElements('name').firstOrNull;
    final descEl = wpt.findElements('desc').firstOrNull
        ?? wpt.findElements('cmt').firstOrNull;

    final nameText = nameEl?.innerText.trim() ?? '';
    final descText = descEl?.innerText.trim() ?? '';

    // Name format: CALLSIGN OUTPUT_FREQ INPUT_FREQ+/- [CTCSS]
    final parts = nameText.split(RegExp(r'\s+'));
    if (parts.length < 2) continue;

    final callsign   = parts[0];
    final outputFreq = double.tryParse(parts[1]) ?? 0.0;
    if (outputFreq == 0.0) continue;

    // Offset direction: trailing '+' or '-' on parts[2]
    String offsetDir = '';
    if (parts.length > 2) {
      final field = parts[2];
      if (field.endsWith('+')) offsetDir = '+';
      if (field.endsWith('-')) offsetDir = '-';
    }

    // CTCSS: parts[3] (Hz, e.g. "103.5")
    double? ctcss;
    if (parts.length > 3) {
      ctcss = double.tryParse(parts[3]);
    }

    final descNorm = descText.replaceAll(RegExp(r'\s+'), ' ').trim();
    final isOpen = !descNorm.toUpperCase().contains('CLOSED');

    // Location: strip callsign and OPEN/CLOSED tags from desc
    String location = descNorm
        .replaceAll(RegExp(r'\bOPEN\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\bCLOSED\b', caseSensitive: false), '')
        .replaceAll(callsign, '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (location.isEmpty) location = descNorm;

    repeaters.add(_Repeater(
      lat: lat,
      lon: lon,
      callsign: callsign,
      outputFreq: outputFreq,
      offsetDir: offsetDir,
      ctcssHz: ctcss,
      location: location,
      isOpen: isOpen,
      band: band,
    ));
  }
  return repeaters;
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

// ─── Screen ───────────────────────────────────────────────────────────────────

class NearRepeaterScreen extends StatefulWidget {
  const NearRepeaterScreen({super.key});

  @override
  State<NearRepeaterScreen> createState() => _NearRepeaterScreenState();
}

// Compute input (TX) frequency from output freq + offset direction + band
double _computeInputFreq(_Repeater r) {
  if (r.offsetDir.isEmpty) return r.outputFreq; // simplex
  final offset = r.outputFreq >= 400 ? 5.0 : 0.6; // 70cm vs 2m standard offset
  return r.offsetDir == '+' ? r.outputFreq + offset : r.outputFreq - offset;
}

class _NearRepeaterScreenState extends State<NearRepeaterScreen> {
  List<_Repeater> _all = [];
  bool _isLoading = true;
  String? _error;
  String _bandFilter = 'All';
  bool _onlyOpen = true;
  int? _tuningIndex;
  bool _isWritingGroup = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final gps = context.read<GpsService>();
      final double? lat = gps.hasPosition ? gps.latitude : null;
      final double? lon = gps.hasPosition ? gps.longitude : null;

      final raw2m   = await rootBundle.loadString('assets/repeaters/colorado_2m.gpx');
      final raw70cm = await rootBundle.loadString('assets/repeaters/colorado_70cm.gpx');

      final list2m   = _parseGpx(raw2m,   '2m');
      final list70cm = _parseGpx(raw70cm, '70cm');
      final all      = [...list2m, ...list70cm];

      if (lat != null && lon != null) {
        for (final r in all) {
          r.distanceMiles = _distanceMiles(lat, lon, r.lat, r.lon);
        }
        all.sort((a, b) => a.distanceMiles.compareTo(b.distanceMiles));
      }

      if (mounted) {
        setState(() {
          _all = all;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  List<_Repeater> get _filtered {
    return _all.where((r) {
      if (_bandFilter == '2m'   && r.band != '2m')   return false;
      if (_bandFilter == '70cm' && r.band != '70cm') return false;
      if (_onlyOpen && !r.isOpen) return false;
      return true;
    }).toList();
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
    final inputFreq = _computeInputFreq(r);
    final tuneOk = await radio.tuneToRepeaterGpx(
      outputFreqMhz: r.outputFreq,
      ctcssHz: r.ctcssHz,
    );
    bool saveOk = false;
    if (tuneOk) {
      saveOk = await radio.writeNearRepeaterChannel(
        outputFreqMhz: r.outputFreq,
        inputFreqMhz: inputFreq,
        ctcssHz: r.ctcssHz,
        name: r.callsign,
      );
    }
    if (!mounted) return;
    setState(() => _tuningIndex = null);

    final freqStr = r.outputFreq.toStringAsFixed(3);
    final toneStr = r.ctcssHz != null ? ' · PL ${r.ctcssHz!.toStringAsFixed(1)} Hz' : '';
    final savedStr = saveOk ? ' · Saved to Group 6' : '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tuneOk
            ? 'Tuned to $freqStr MHz$toneStr$savedStr'
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

    setState(() => _isWritingGroup = true);
    final list = _filtered;
    int written = 0;
    final toWrite = list.take(32).toList();
    for (int i = 0; i < toWrite.length; i++) {
      final r = toWrite[i];
      final ok = await radio.writeNearRepeaterChannel(
        outputFreqMhz: r.outputFreq,
        inputFreqMhz: _computeInputFreq(r),
        ctcssHz: r.ctcssHz,
        name: r.callsign,
      );
      if (ok) written++;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    if (!mounted) return;
    setState(() => _isWritingGroup = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Wrote $written/${toWrite.length} repeaters to Group 6'),
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
    final gps   = context.watch<GpsService>();
    final radio = context.watch<RadioService>();
    final list  = _filtered;

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
            IconButton(
              icon: const Icon(Icons.save_alt),
              tooltip: 'Write top 32 to Group 6',
              onPressed: _isLoading ? null : _writeGroupToRadio,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
            onPressed: _isLoading ? null : _load,
          ),
        ],
      ),
      body: Column(
        children: [
          _StatusBar(gps: gps, radio: radio),
          _FilterBar(
            bandFilter: _bandFilter,
            onlyOpen: _onlyOpen,
            onBandChanged: (v) => setState(() => _bandFilter = v),
            onOpenChanged: (v) => setState(() => _onlyOpen = v),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _ErrorState(error: _error!, onRetry: _load)
                    : list.isEmpty
                        ? const _EmptyState()
                        : ListView.builder(
                            itemCount: list.length + 1,
                            itemBuilder: (ctx, i) {
                              if (i == list.length) return _attributionFooter();
                              final r = list[i];
                              return _RepeaterCard(
                                repeater: r,
                                isTuning: _tuningIndex == i,
                                radioConnected: radio.isConnected,
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
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Text(
        'Repeater data © RepeaterBook.com · Colorado 2m/70cm · Exported 2026-03-03',
        style: TextStyle(color: Colors.white24, fontSize: 10),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _StatusBar extends StatelessWidget {
  final GpsService gps;
  final RadioService radio;

  const _StatusBar({required this.gps, required this.radio});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey[900],
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Row(
        children: [
          Icon(
            gps.hasPosition ? Icons.gps_fixed : Icons.gps_off,
            size: 13,
            color: gps.hasPosition ? Colors.green : Colors.orange,
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              gps.hasPosition ? gps.displayPosition : 'Waiting for GPS…',
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ),
          Icon(
            radio.isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
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
  final ValueChanged<String> onBandChanged;
  final ValueChanged<bool> onOpenChanged;

  const _FilterBar({
    required this.bandFilter,
    required this.onlyOpen,
    required this.onBandChanged,
    required this.onOpenChanged,
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
  final VoidCallback onTune;

  const _RepeaterCard({
    required this.repeater,
    required this.isTuning,
    required this.radioConnected,
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
      color: Colors.grey[850],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
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
            const SizedBox(width: 10),

            // Main info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        r.callsign,
                        style: TextStyle(
                          color: r.isOpen ? Colors.white : Colors.white38,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      if (distStr.isNotEmpty)
                        Text(
                          distStr,
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$freqStr MHz  ${r.offsetDir}  $toneStr',
                    style: TextStyle(
                      color: Colors.green[400],
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
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
            const SizedBox(width: 8),

            // Tune button
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
                    tooltip: 'Tune to this repeater',
                    onPressed: radioConnected ? onTune : null,
                    iconSize: 22,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cell_tower, size: 64, color: Colors.white24),
          SizedBox(height: 12),
          Text('No repeaters match filters',
              style: TextStyle(color: Colors.white54, fontSize: 16)),
        ],
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
