// lib/services/repeaterbook_service.dart
// Imports repeater data from files EXPORTED FROM repeaterbook.com (the website's
// "Download" panel) — both GPX and CSV — as well as the RepeaterBook *app*'s GPX.
// Parsed data is cached to local storage and survives app restarts.
// Supports multiple imports (merged, deduped by callsign+freq).
//
// Why this exists: the RepeaterBook web API token was denied and the content
// provider only returns regions the RepeaterBook app has loaded. When the user
// travels outside a pre-loaded area, manual import of a repeaterbook.com export
// is the reliable last-resort path to get local repeaters into OpenHT.
//
// repeaterbook.com CSV export columns (confirmed 2026):
//   Output Freq,Input Freq,Offset,Uplink Tone,Downlink Tone,Call,Location,
//   County,State,Modes,Digital Access
//   NOTE: the website CSV export has NO lat/long columns — imported CSV
//   repeaters therefore have no distance and are not distance-filtered.
//   Use the GPX export instead when you want distance sorting.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';

class RbRepeater {
  final double lat;
  final double lon;
  final bool hasCoords;      // false when imported from a coordinate-less CSV
  final String callsign;
  final double outputFreq;   // MHz
  final double inputFreq;    // MHz
  final double? ctcssHz;     // uplink (TX) tone preferred
  final String name;
  final String city;
  final String state;
  final bool isOpen;
  final String band;         // '2m' or '70cm'
  final String serviceText;  // 'FM', 'DMR', 'Fusion', etc.
  double distanceMiles = 0;

  RbRepeater({
    required this.lat,
    required this.lon,
    this.hasCoords = true,
    required this.callsign,
    required this.outputFreq,
    required this.inputFreq,
    this.ctcssHz,
    required this.name,
    required this.city,
    required this.state,
    required this.isOpen,
    required this.band,
    this.serviceText = 'FM',
  });

  String get dedupeKey => '$callsign:${outputFreq.toStringAsFixed(4)}';
  bool get isFmCompatible => serviceText.toUpperCase().contains('FM');

  Map<String, dynamic> toJson() => {
    'lat': lat, 'lon': lon, 'hasCoords': hasCoords,
    'callsign': callsign,
    'outputFreq': outputFreq,
    'inputFreq': inputFreq,
    'ctcssHz': ctcssHz,
    'name': name,
    'city': city,
    'state': state,
    'isOpen': isOpen,
    'band': band,
    'serviceText': serviceText,
  };

  factory RbRepeater.fromJson(Map<String, dynamic> j) => RbRepeater(
    lat:        (j['lat'] as num).toDouble(),
    lon:        (j['lon'] as num).toDouble(),
    hasCoords:  j['hasCoords'] as bool? ?? true,
    callsign:   j['callsign'] as String,
    outputFreq: (j['outputFreq'] as num).toDouble(),
    inputFreq:  (j['inputFreq'] as num).toDouble(),
    ctcssHz:    (j['ctcssHz'] as num?)?.toDouble(),
    name:       j['name'] as String,
    city:       j['city'] as String,
    state:      j['state'] as String,
    isOpen:     j['isOpen'] as bool,
    band:       j['band'] as String,
    serviceText: j['serviceText'] as String? ?? 'FM',
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
  bool             get anyHasCoords => _repeaters.any((r) => r.hasCoords);

  String get statusLabel {
    if (_isLoading) return 'Importing…';
    if (_repeaters.isEmpty) return 'No data — import a RepeaterBook GPX/CSV';
    final age = _lastImport == null ? '' : ' · ${_timeSince(_lastImport!)} ago';
    return '${_repeaters.length} repeaters from $_importCount import(s)$age';
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

  // ── Import dispatch ──────────────────────────────────────────────────────────

  /// Import a file by extension (.gpx or .csv). Falls back to sniffing the
  /// content when the extension is missing/unreliable (common with Android's
  /// document picker returning content:// URIs).
  Future<int> importFile(String path, {Uint8List? bytes}) async {
    final lower = path.toLowerCase();
    String content;
    if (bytes != null) {
      content = utf8.decode(bytes, allowMalformed: true);
    } else {
      content = await File(path).readAsString();
    }
    final looksGpx = lower.endsWith('.gpx') ||
        content.trimLeft().startsWith('<?xml') ||
        content.contains('<gpx');
    if (looksGpx) {
      return _importParsed(_parseGpx(content));
    }
    return _importParsed(_parseCsv(content));
  }

  /// Import a RepeaterBook GPX export (app or website format).
  Future<int> importGpxFile(String path, {Uint8List? bytes}) async {
    final content = bytes != null
        ? utf8.decode(bytes, allowMalformed: true)
        : await File(path).readAsString();
    return _importParsed(_parseGpx(content));
  }

  /// Import a repeaterbook.com CSV export.
  Future<int> importCsvFile(String path, {Uint8List? bytes}) async {
    final content = bytes != null
        ? utf8.decode(bytes, allowMalformed: true)
        : await File(path).readAsString();
    return _importParsed(_parseCsv(content));
  }

  Future<int> _importParsed(List<RbRepeater> parsed) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    int added = 0;
    try {
      if (parsed.isEmpty) {
        _error = 'No repeaters found — is this a RepeaterBook GPX/CSV export?';
      } else {
        final existing = {for (final r in _repeaters) r.dedupeKey: r};
        for (final r in parsed) {
          if (!existing.containsKey(r.dedupeKey)) {
            existing[r.dedupeKey] = r;
            added++;
          }
        }
        _repeaters = existing.values.toList();
        _importCount++;
        _lastImport = DateTime.now();
        await _saveCache();
        debugPrint('RepeaterBook: imported $added new (total ${_repeaters.length})');
      }
    } catch (e) {
      _error = 'Import failed: $e';
      debugPrint('RepeaterBook: $_error');
    }

    _isLoading = false;
    notifyListeners();
    return added;
  }

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

  // ── GPX parsing (tolerant: app format AND website format) ────────────────────
  // App <name>:     "CALLSIGN OUTPUT INPUT[+/-] [TONE]"
  // Website <name>: often just "CALLSIGN"; freq/tone live in <desc>.
  // We therefore harvest freq/offset/tone from BOTH name and desc.

  List<RbRepeater> _parseGpx(String gpxXml) {
    final doc = XmlDocument.parse(gpxXml);
    final result = <RbRepeater>[];

    for (final wpt in doc.findAllElements('wpt')) {
      final lat = double.tryParse(wpt.getAttribute('lat') ?? '') ?? 0.0;
      final lon = double.tryParse(wpt.getAttribute('lon') ?? '') ?? 0.0;
      final hasCoords = !(lat == 0.0 && lon == 0.0);

      final nameText = wpt.findElements('name').firstOrNull?.innerText.trim() ?? '';
      final descText = (wpt.findElements('desc').firstOrNull
              ?? wpt.findElements('cmt').firstOrNull)
          ?.innerText.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
      final blob = '$nameText | $descText';

      // Callsign: first whitespace token of <name> that isn't a number.
      String callsign = '';
      for (final tok in nameText.split(RegExp(r'\s+'))) {
        if (tok.isNotEmpty && double.tryParse(tok) == null) { callsign = tok; break; }
      }
      if (callsign.isEmpty) continue;

      // Output frequency: first VHF/UHF-looking number (28–1300 MHz).
      double outFreq = 0;
      for (final m in RegExp(r'\d{2,4}\.\d{2,6}').allMatches(blob)) {
        final v = double.tryParse(m.group(0)!) ?? 0;
        if (v >= 28 && v <= 1300) { outFreq = v; break; }
      }
      if (outFreq == 0) continue;

      // Offset direction: a "+" / "-" adjacent to a frequency, or explicit input.
      double inFreq = outFreq;
      final off = RegExp(r'\d{2,4}\.\d{2,6}\s*([+\-])').firstMatch(blob);
      if (off != null) {
        final sign = off.group(1);
        final delta = outFreq >= 400 ? 5.0 : 0.6;
        inFreq = sign == '+' ? outFreq + delta : outFreq - delta;
      } else {
        // Explicit second frequency (website sometimes lists input freq).
        final freqs = RegExp(r'\d{2,4}\.\d{2,6}')
            .allMatches(blob)
            .map((m) => double.parse(m.group(0)!))
            .where((v) => v >= 28 && v <= 1300)
            .toList();
        if (freqs.length > 1 && (freqs[1] - outFreq).abs() < 12) inFreq = freqs[1];
      }

      // CTCSS tone: a number that looks like a PL tone (67.0–254.1 Hz).
      double? ctcss;
      for (final m in RegExp(r'\b(\d{2,3}\.\d)\b').allMatches(blob)) {
        final v = double.tryParse(m.group(1)!) ?? 0;
        if (v >= 67 && v <= 255) { ctcss = v; break; }
      }

      final isOpen = !blob.toUpperCase().contains('CLOSED');
      final serviceText = _serviceFromBlob(blob);

      String city = '', state = '';
      final descParts = descText.split(',');
      if (descParts.length >= 2) {
        city  = descParts[0].replaceAll(callsign, '').replaceAll(RegExp(r'\bOPEN\b|\bCLOSED\b', caseSensitive: false), '').trim();
        state = descParts[1].trim().split(' ').first;
      }

      result.add(RbRepeater(
        lat: lat, lon: lon, hasCoords: hasCoords,
        callsign: callsign,
        outputFreq: outFreq,
        inputFreq: inFreq,
        ctcssHz: ctcss,
        name: descText.isEmpty ? callsign : descText,
        city: city, state: state,
        isOpen: isOpen,
        band: outFreq >= 300 ? '70cm' : '2m',
        serviceText: serviceText,
      ));
    }
    return result;
  }

  // ── CSV parsing (repeaterbook.com website export) ────────────────────────────
  // Header-driven so it tolerates column reordering and the several CSV
  // variants RepeaterBook offers. Recognised header aliases below.

  List<RbRepeater> _parseCsv(String csv) {
    final rows = _splitCsvRows(csv);
    if (rows.isEmpty) return [];

    // Map header name -> index using fuzzy aliases.
    final header = rows.first.map((h) => h.trim().toLowerCase()).toList();
    int col(List<String> aliases) {
      for (int i = 0; i < header.length; i++) {
        for (final a in aliases) {
          if (header[i] == a || header[i].contains(a)) return i;
        }
      }
      return -1;
    }

    final iCall   = col(['call', 'callsign']);
    final iOut    = col(['output freq', 'output', 'frequency', 'freq', 'rx']);
    final iIn     = col(['input freq', 'input', 'tx']);
    final iOffset = col(['offset', 'duplex']);
    final iUp     = col(['uplink tone', 'uplink', 'tx tone', 'ctcss', 'tone']);
    final iDown   = col(['downlink tone', 'downlink', 'rx tone']);
    final iLoc    = col(['location', 'nearest city', 'city']);
    final iCounty = col(['county']);
    final iState  = col(['state', 'province']);
    final iModes  = col(['modes', 'mode', 'service']);
    final iLat    = col(['lat', 'latitude']);
    final iLon    = col(['long', 'lng', 'lon', 'longitude']);
    final iStatus = col(['operational status', 'status', 'use']);

    if (iCall < 0 || iOut < 0) return []; // not a RepeaterBook CSV

    String cell(List<String> r, int i) =>
        (i >= 0 && i < r.length) ? r[i].trim() : '';

    final result = <RbRepeater>[];
    for (int n = 1; n < rows.length; n++) {
      final r = rows[n];
      if (r.every((c) => c.trim().isEmpty)) continue;

      final callsign = cell(r, iCall);
      final outFreq  = double.tryParse(cell(r, iOut)) ?? 0;
      if (callsign.isEmpty || outFreq == 0) continue;

      double inFreq = double.tryParse(cell(r, iIn)) ?? 0;
      if (inFreq == 0) {
        final offset = cell(r, iOffset);
        final delta  = outFreq >= 400 ? 5.0 : 0.6;
        if (offset.contains('+')) {
          inFreq = outFreq + delta;
        } else if (offset.contains('-')) {
          inFreq = outFreq - delta;
        } else {
          inFreq = outFreq;
        }
      }

      // Prefer uplink (TX) tone for programming; fall back to downlink.
      double? tone = _parseTone(cell(r, iUp));
      tone ??= _parseTone(cell(r, iDown));

      final lat = double.tryParse(cell(r, iLat)) ?? 0;
      final lon = double.tryParse(cell(r, iLon)) ?? 0;
      final hasCoords = !(lat == 0 && lon == 0) && iLat >= 0 && iLon >= 0;

      final modes = cell(r, iModes);
      final status = cell(r, iStatus).toLowerCase();
      final isOpen = !(status.contains('off') || status.contains('closed'));

      result.add(RbRepeater(
        lat: lat, lon: lon, hasCoords: hasCoords,
        callsign: callsign,
        outputFreq: outFreq,
        inputFreq: inFreq,
        ctcssHz: tone,
        name: cell(r, iLoc).isEmpty ? callsign : cell(r, iLoc),
        city: cell(r, iLoc),
        state: cell(r, iState).isEmpty ? cell(r, iCounty) : cell(r, iState),
        isOpen: isOpen,
        band: outFreq >= 300 ? '70cm' : '2m',
        serviceText: modes.isEmpty ? 'FM' : modes.trim(),
      ));
    }
    return result;
  }

  static double? _parseTone(String s) {
    final v = double.tryParse(s.replaceAll(RegExp(r'[^0-9.]'), ''));
    if (v == null || v < 60 || v > 260) return null;
    return v;
  }

  static String _serviceFromBlob(String blob) {
    final up = blob.toUpperCase();
    if (up.contains('DMR')) return 'DMR';
    if (up.contains('FUSION') || up.contains('YSF') || up.contains('C4FM')) return 'Fusion';
    if (up.contains('D-STAR') || up.contains('DSTAR')) return 'D-Star';
    if (up.contains('P25')) return 'P25';
    if (up.contains('NXDN')) return 'NXDN';
    return 'FM';
  }

  /// RFC-4180-ish CSV splitter that handles quoted fields containing commas.
  static List<List<String>> _splitCsvRows(String csv) {
    final rows = <List<String>>[];
    var field = StringBuffer();
    var row = <String>[];
    bool inQuotes = false;
    for (int i = 0; i < csv.length; i++) {
      final c = csv[i];
      if (inQuotes) {
        if (c == '"') {
          if (i + 1 < csv.length && csv[i + 1] == '"') { field.write('"'); i++; }
          else { inQuotes = false; }
        } else { field.write(c); }
      } else {
        if (c == '"') { inQuotes = true; }
        else if (c == ',') { row.add(field.toString()); field = StringBuffer(); }
        else if (c == '\n') {
          row.add(field.toString()); field = StringBuffer();
          rows.add(row); row = <String>[];
        } else if (c == '\r') { /* skip */ }
        else { field.write(c); }
      }
    }
    if (field.isNotEmpty || row.isNotEmpty) { row.add(field.toString()); rows.add(row); }
    return rows;
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

  static double haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 3958.8;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(_rad(lat1)) * math.cos(_rad(lat2)) *
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
