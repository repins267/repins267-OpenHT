// lib/services/repeaterbook_service.dart
// Imports repeater data from a GPX file exported by the Repeaterbook app.
// Parsed data is cached to local storage and survives app restarts.
// Supports multiple GPX imports (merged, deduped by callsign+freq).

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';

class RbRepeater {
  final double lat;
  final double lon;
  final String callsign;
  final double outputFreq;  // MHz
  final double inputFreq;   // MHz
  final double? ctcssHz;
  final String name;
  final String city;
  final String state;
  final bool isOpen;
  final String band;        // '2m' or '70cm'
  double distanceMiles = 0;

  RbRepeater({
    required this.lat,
    required this.lon,
    required this.callsign,
    required this.outputFreq,
    required this.inputFreq,
    this.ctcssHz,
    required this.name,
    required this.city,
    required this.state,
    required this.isOpen,
    required this.band,
  });

  String get dedupeKey => '$callsign:${outputFreq.toStringAsFixed(4)}';

  Map<String, dynamic> toJson() => {
    'lat': lat, 'lon': lon,
    'callsign': callsign,
    'outputFreq': outputFreq,
    'inputFreq': inputFreq,
    'ctcssHz': ctcssHz,
    'name': name,
    'city': city,
    'state': state,
    'isOpen': isOpen,
    'band': band,
  };

  factory RbRepeater.fromJson(Map<String, dynamic> j) => RbRepeater(
    lat:        (j['lat'] as num).toDouble(),
    lon:        (j['lon'] as num).toDouble(),
    callsign:   j['callsign'] as String,
    outputFreq: (j['outputFreq'] as num).toDouble(),
    inputFreq:  (j['inputFreq'] as num).toDouble(),
    ctcssHz:    (j['ctcssHz'] as num?)?.toDouble(),
    name:       j['name'] as String,
    city:       j['city'] as String,
    state:      j['state'] as String,
    isOpen:     j['isOpen'] as bool,
    band:       j['band'] as String,
  );
}

class RepeaterBookService extends ChangeNotifier {
  static const _cacheFileName = 'repeaterbook_cache.json';

  List<RbRepeater> _repeaters = [];
  bool    _isLoading = false;
  String? _error;
  int     _importCount = 0;
  DateTime? _lastImport;

  List<RbRepeater> get repeaters    => _repeaters;
  bool             get isLoading    => _isLoading;
  String?          get error        => _error;
  bool             get hasData      => _repeaters.isNotEmpty;
  int              get importCount  => _importCount;

  String get statusLabel {
    if (_isLoading) return 'Importing…';
    if (_repeaters.isEmpty) return 'No data — import a Repeaterbook GPX';
    final age = _lastImport == null
        ? ''
        : ' · ${_timeSince(_lastImport!)} ago';
    return '${_repeaters.length} repeaters from $_importCount GPX file(s)$age';
  }

  // ── Init / persist ──────────────────────────────────────────────────────────

  Future<void> loadCache() async {
    try {
      final f = await _cacheFile();
      if (!await f.exists()) return;
      final raw = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      _importCount = raw['importCount'] as int? ?? 0;
      final ms = raw['lastImport'] as int?;
      _lastImport = ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
      _repeaters = (raw['repeaters'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(RbRepeater.fromJson)
          .toList();
      debugPrint('RepeaterBook: cache loaded — ${_repeaters.length} repeaters');
      notifyListeners();
    } catch (e) {
      debugPrint('RepeaterBook: cache load failed: $e');
    }
  }

  // ── GPX import ──────────────────────────────────────────────────────────────

  /// Parse a GPX file and merge into the existing dataset.
  /// Returns number of new repeaters added.
  Future<int> importGpxFile(String path) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    int added = 0;
    try {
      final content = await File(path).readAsString();
      final parsed  = _parseGpx(content);

      final existing = {for (final r in _repeaters) r.dedupeKey: r};
      for (final r in parsed) {
        if (!existing.containsKey(r.dedupeKey)) {
          existing[r.dedupeKey] = r;
          added++;
        }
      }
      _repeaters  = existing.values.toList();
      _importCount++;
      _lastImport = DateTime.now();
      await _saveCache();
      debugPrint('RepeaterBook: imported $added new from GPX '
          '(total ${_repeaters.length})');
    } catch (e) {
      _error = 'Import failed: $e';
      debugPrint('RepeaterBook: $_error');
    }

    _isLoading = false;
    notifyListeners();
    return added;
  }

  /// Clear all imported data.
  Future<void> clearAll() async {
    _repeaters   = [];
    _importCount = 0;
    _lastImport  = null;
    _error       = null;
    try {
      final f = await _cacheFile();
      if (await f.exists()) await f.delete();
    } catch (_) {}
    notifyListeners();
  }

  // ── GPX parsing ─────────────────────────────────────────────────────────────
  // Repeaterbook GPX <name> format:
  //   CALLSIGN OUTPUT_FREQ INPUT_FREQ[+/-] [CTCSS_TONE]
  // e.g. "W0DMR 147.390000 147.390000+ 100.0"

  List<RbRepeater> _parseGpx(String gpxXml) {
    final doc = XmlDocument.parse(gpxXml);
    final result = <RbRepeater>[];

    for (final wpt in doc.findAllElements('wpt')) {
      final lat = double.tryParse(wpt.getAttribute('lat') ?? '') ?? 0.0;
      final lon = double.tryParse(wpt.getAttribute('lon') ?? '') ?? 0.0;
      if (lat == 0.0 && lon == 0.0) continue;

      final nameText = wpt.findElements('name').firstOrNull?.innerText.trim() ?? '';
      final descText = (wpt.findElements('desc').firstOrNull
              ?? wpt.findElements('cmt').firstOrNull)
          ?.innerText.trim() ?? '';

      final parts = nameText.split(RegExp(r'\s+'));
      if (parts.length < 2) continue;

      final callsign  = parts[0];
      final outFreq   = double.tryParse(parts[1]) ?? 0.0;
      if (outFreq == 0.0) continue;

      // Input freq — may be encoded as "OUTPUT+" / "OUTPUT-", or explicit
      double inFreq = outFreq;
      if (parts.length > 2) {
        final f2 = parts[2];
        if (f2.endsWith('+')) {
          final base = double.tryParse(f2.replaceAll('+', ''));
          if (base != null) {
            inFreq = base + (outFreq >= 400 ? 5.0 : 0.6);
          }
        } else if (f2.endsWith('-')) {
          final base = double.tryParse(f2.replaceAll('-', ''));
          if (base != null) {
            inFreq = base - (outFreq >= 400 ? 5.0 : 0.6);
          }
        } else {
          inFreq = double.tryParse(f2) ?? outFreq;
        }
      }

      double? ctcss;
      if (parts.length > 3) ctcss = double.tryParse(parts[3]);

      final descNorm = descText.replaceAll(RegExp(r'\s+'), ' ').trim();
      final isOpen   = !descNorm.toUpperCase().contains('CLOSED');

      // Extract city/state from desc if possible (RepeaterBook format varies)
      String city  = '';
      String state = '';
      final descParts = descNorm.split(',');
      if (descParts.length >= 2) {
        city  = descParts[0].trim();
        state = descParts[1].trim().split(' ').first;
      }

      String band = '2m';
      if (outFreq >= 420 && outFreq <= 450) band = '70cm';

      result.add(RbRepeater(
        lat: lat, lon: lon,
        callsign: callsign,
        outputFreq: outFreq,
        inputFreq: inFreq,
        ctcssHz: ctcss,
        name: descNorm.isEmpty ? callsign : descNorm,
        city: city,
        state: state,
        isOpen: isOpen,
        band: band,
      ));
    }
    return result;
  }

  // ── Cache ───────────────────────────────────────────────────────────────────

  Future<File> _cacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_cacheFileName');
  }

  Future<void> _saveCache() async {
    try {
      final f = await _cacheFile();
      await f.writeAsString(jsonEncode({
        'importCount': _importCount,
        'lastImport':  _lastImport?.millisecondsSinceEpoch,
        'repeaters':   _repeaters.map((r) => r.toJson()).toList(),
      }));
    } catch (e) {
      debugPrint('RepeaterBook: cache write failed: $e');
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  static double haversine(
      double lat1, double lon1, double lat2, double lon2) {
    const r = 3958.8;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.pow(math.sin(dLon / 2), 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double d) => d * math.pi / 180;

  static String _timeSince(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inDays  > 0) return '${d.inDays}d';
    if (d.inHours > 0) return '${d.inHours}h';
    return '${d.inMinutes}m';
  }
}
