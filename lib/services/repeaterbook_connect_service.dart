// lib/services/repeaterbook_connect_service.dart
// Queries the RepeaterBook Android app's content provider for nearby repeaters.
// RepeaterBook must be installed (com.zbm2.repeaterbook) and the user must
// have opened it at least once so its database is initialized.
// URI discovered via libapp.so string analysis:
//   content://com.zbm2.repeaterbook.RBContentProvider/repeaters

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class RbConnectRepeater {
  final double lat;
  final double lon;
  final String callsign;
  final double outputFreq;   // MHz
  final double inputFreq;    // MHz
  final double? ctcssHz;     // null = no tone
  final String location;
  final String state;
  final String country;
  final bool isOpen;
  final String band;         // '2m' or '70cm'
  final String serviceText;  // 'FM', 'FM Fusion', 'DMR', 'DStar', etc.
  double distanceMiles;

  RbConnectRepeater({
    required this.lat,
    required this.lon,
    required this.callsign,
    required this.outputFreq,
    required this.inputFreq,
    this.ctcssHz,
    required this.location,
    required this.state,
    required this.country,
    required this.isOpen,
    required this.band,
    this.serviceText = 'FM',
    this.distanceMiles = 0,
  });

  Map<String, dynamic> toJson() => {
    'lat': lat, 'lon': lon,
    'callsign': callsign,
    'outputFreq': outputFreq,
    'inputFreq': inputFreq,
    'ctcssHz': ctcssHz,
    'location': location,
    'state': state,
    'country': country,
    'isOpen': isOpen,
    'band': band,
    'serviceText': serviceText,
  };

  factory RbConnectRepeater.fromJson(Map<String, dynamic> j) =>
      RbConnectRepeater(
        lat:          (j['lat'] as num).toDouble(),
        lon:          (j['lon'] as num).toDouble(),
        callsign:     j['callsign'] as String,
        outputFreq:   (j['outputFreq'] as num).toDouble(),
        inputFreq:    (j['inputFreq'] as num).toDouble(),
        ctcssHz:      (j['ctcssHz'] as num?)?.toDouble(),
        location:     j['location'] as String,
        state:        j['state'] as String,
        country:      j['country'] as String,
        isOpen:       j['isOpen'] as bool,
        band:         j['band'] as String,
        serviceText:  j['serviceText'] as String? ?? 'FM',
      );

  /// True if this repeater is compatible with analog FM radios (VR-N76, etc.).
  bool get isFmCompatible => serviceText.toUpperCase().contains('FM');
}

class RepeaterBookConnectService {
  static const _channel    = MethodChannel('com.openht.app/repeaterbook');
  static const _cacheFile  = 'rb_live_cache.json';

  // In-memory cache so callers can access data between queries
  static List<RbConnectRepeater> _cache    = [];
  static DateTime?               _cachedAt;

  static List<RbConnectRepeater> get cachedRepeaters => List.unmodifiable(_cache);
  static DateTime?               get cachedAt        => _cachedAt;
  static bool                    get hasCachedData   => _cache.isNotEmpty;

  /// Load previously saved results from disk into memory.
  /// Call this once at app startup.
  static Future<void> loadCache() async {
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final raw = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final ms  = raw['cachedAt'] as int?;
      _cachedAt = ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
      _cache    = (raw['repeaters'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(RbConnectRepeater.fromJson)
          .toList();
      debugPrint('RbConnect: cache loaded — ${_cache.length} repeaters '
          'from ${_cachedAt?.toLocal()}');
    } catch (e) {
      debugPrint('RbConnect: cache load failed: $e');
    }
  }

  static Future<void> _saveCache(List<RbConnectRepeater> data) async {
    try {
      _cache    = data;
      _cachedAt = DateTime.now();
      final f   = await _file();
      await f.writeAsString(jsonEncode({
        'cachedAt':  _cachedAt!.millisecondsSinceEpoch,
        'repeaters': data.map((r) => r.toJson()).toList(),
      }));
    } catch (e) {
      debugPrint('RbConnect: cache write failed: $e');
    }
  }

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_cacheFile');
  }

  /// Returns true if the RepeaterBook app is installed.
  static Future<bool> isInstalled() async {
    try {
      return await _channel.invokeMethod<bool>('isInstalled') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Queries the RepeaterBook content provider and returns parsed repeaters.
  /// On success the results are persisted to disk for offline use.
  /// Returns an empty list if RepeaterBook is not installed or the query fails.
  static Future<List<RbConnectRepeater>> queryRepeaters() async {
    try {
      final rawList = await _channel.invokeMethod<List>('queryRepeaters');
      if (rawList == null || rawList.isEmpty) return [];

      final result = <RbConnectRepeater>[];
      for (final raw in rawList) {
        final row = Map<String, dynamic>.from(raw as Map);
        final r = _parseRow(row);
        if (r != null) result.add(r);
      }
      if (result.isNotEmpty) unawaited(_saveCache(result));
      return result;
    } on PlatformException catch (e) {
      debugPrint('RepeaterBookConnect: query failed: ${e.message}');
      return [];
    } catch (e) {
      debugPrint('RepeaterBookConnect: unexpected error: $e');
      return [];
    }
  }

  static RbConnectRepeater? _parseRow(Map<String, dynamic> row) {
    try {
      final lat = _toDouble(row['Lat']);
      final lon = _toDouble(row['Lng']);
      if (lat == null || lon == null) return null;
      if (lat == 0.0 && lon == 0.0) return null;

      final callsign  = (row['Call'] as String?)?.trim() ?? '';
      if (callsign.isEmpty) return null;

      final rxFreq = _toDouble(row['RX']);
      final txFreq = _toDouble(row['TX']);
      if (rxFreq == null || rxFreq == 0.0) return null;

      // CTCSS: 0 means no tone
      final ctcssRaw = _toDouble(row['CTCSS']);
      final ctcssHz = (ctcssRaw != null && ctcssRaw > 0) ? ctcssRaw : null;

      final location = _buildLocation(row);
      final state    = (row['State'] as String?)?.trim() ?? '';
      final country  = (row['Country'] as String?)?.trim() ?? 'US';

      // OpStatus: 1 = on-air, 2 = on-air-unverified; others = closed/unknown
      final opStatus = _toLong(row['OpStatus']) ?? 0;
      final isOpen   = opStatus == 1 || opStatus == 2;

      final bandStr  = (row['Band'] as String?)?.trim() ?? '';
      final band     = bandStr == '70cm' ? '70cm' : '2m';

      final serviceText = (row['ServiceTxt'] as String?)?.trim() ?? 'FM';

      // Pre-computed distance from Repeaterbook's configured location
      final distance = _toDouble(row['Distance']) ?? 0.0;

      return RbConnectRepeater(
        lat: lat,
        lon: lon,
        callsign: callsign,
        outputFreq: rxFreq,
        inputFreq: txFreq ?? rxFreq,
        ctcssHz: ctcssHz,
        location: location,
        state: state,
        country: country,
        isOpen: isOpen,
        band: band,
        serviceText: serviceText,
        distanceMiles: distance,
      );
    } catch (e) {
      debugPrint('RepeaterBookConnect: row parse error: $e');
      return null;
    }
  }

  static String _buildLocation(Map<String, dynamic> row) {
    final loc    = (row['Location'] as String?)?.trim() ?? '';
    final county = (row['County']   as String?)?.trim() ?? '';
    final state  = (row['State']    as String?)?.trim() ?? '';

    if (loc.isNotEmpty && state.isNotEmpty) return '$loc, $state';
    if (loc.isNotEmpty) return loc;
    if (county.isNotEmpty && state.isNotEmpty) return '$county, $state';
    return state;
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static int? _toLong(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }
}
