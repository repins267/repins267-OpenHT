// lib/services/noaa_service.dart
// Fetches NOAA Weather Radio stations and active weather alerts.

import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Color;
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:xml/xml.dart';
import '../models/nwr_station.dart';
import '../models/weather_alert.dart';

class NoaaService extends ChangeNotifier {
  static const String _nwrStnUrl =
      'https://www.weather.gov/source/nwr/StnInfo.xml';
  static const String _alertBaseUrl = 'https://api.weather.gov/alerts/active';
  static const String _prefKey = 'noaa_stations_cache';

  List<NwrStation> _stations = List.of(_startupCache); // pre-populate from static cache
  List<WeatherAlert> _alerts = [];
  bool _isLoading = false;
  String? _error;

  // Pre-loaded at startup before any instance exists
  static List<NwrStation> _startupCache = [];

  // Polling support
  Timer? _pollTimer;
  double? _lastLat;
  double? _lastLon;
  String? _sameCode;
  final Set<String> _notifiedAlertIds = {};

  // flutter_local_notifications plugin — injected from main()
  static FlutterLocalNotificationsPlugin? _notifPlugin;

  static void initNotifications(FlutterLocalNotificationsPlugin plugin) {
    _notifPlugin = plugin;
  }

  /// Call in main() before runApp to pre-populate the cache.
  static Future<void> loadCacheStatic() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString(_prefKey);
      if (raw != null && raw.isNotEmpty) {
        _startupCache = NwrStation.listFromJson(raw);
        debugPrint('NoaaService: startup cache — ${_startupCache.length} stations');
      }
    } catch (e) {
      debugPrint('NoaaService: startup cache load failed: $e');
    }
  }

  /// Load cached station list from SharedPreferences (call at startup).
  Future<void> loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString(_prefKey);
      if (raw != null && raw.isNotEmpty && _stations.isEmpty) {
        _stations = NwrStation.listFromJson(raw);
        debugPrint('NoaaService: cache loaded — ${_stations.length} stations');
        notifyListeners();
      }
    } catch (e) {
      debugPrint('NoaaService: cache load failed: $e');
    }
  }

  Future<void> _saveCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, NwrStation.listToJson(_stations));
    } catch (e) {
      debugPrint('NoaaService: cache save failed: $e');
    }
  }

  List<NwrStation> get stations => List.unmodifiable(_stations);
  List<WeatherAlert> get alerts => List.unmodifiable(_alerts);
  bool get isLoading => _isLoading;
  String? get error => _error;

  static const _headers = {
    'User-Agent': 'OpenHT/0.1 (github.com/repins267/OpenHT)',
    'Accept': 'application/geo+json',
  };

  // ─── Polling ──────────────────────────────────────────────────────────────

  /// Start 5-minute background polling.
  /// Uses lat/lon from the most recent [refresh()] call.
  /// [sameCode] optionally filters alerts to the user's county (6-digit FIPS).
  void startPolling({String? sameCode}) {
    _sameCode = sameCode;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(minutes: 5), (_) => _pollAndNotify());
    // Fire immediately if we already have coordinates
    if (_lastLat != null) unawaited(_pollAndNotify());
    debugPrint('NoaaService: polling started (SAME: ${sameCode ?? "none"})');
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    debugPrint('NoaaService: polling stopped');
  }

  Future<void> _pollAndNotify() async {
    if (_lastLat == null || _lastLon == null) return;
    await refresh(_lastLat!, _lastLon!);
    await _checkAndNotify();
  }

  Future<void> _checkAndNotify() async {
    if (_notifPlugin == null) return;
    for (final alert in _alerts) {
      if (alert.severity != 'Extreme' && alert.severity != 'Severe') continue;
      // Skip if not in user's county (when SAME code is configured)
      if (_sameCode != null &&
          _sameCode!.isNotEmpty &&
          alert.sameCodes.isNotEmpty &&
          !alert.sameCodes.contains(_sameCode)) continue;
      // Dedup — only notify once per alert ID
      if (_notifiedAlertIds.contains(alert.id)) continue;
      _notifiedAlertIds.add(alert.id);
      try {
        await _notifPlugin!.show(
          alert.id.hashCode & 0x7FFFFFFF,
          '${alert.severity == "Extreme" ? "⚠ EXTREME" : "⚠ SEVERE"}: ${alert.event}',
          alert.areaDesc ?? alert.headline,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'weather_alerts',
              'Weather Alerts',
              channelDescription: 'NOAA weather alerts for your area',
              importance: Importance.high,
              priority: Priority.high,
              color: Color(0xFFB71C1C),
            ),
          ),
        );
        debugPrint('NoaaService: notification sent for ${alert.event}');
      } catch (e) {
        debugPrint('NoaaService: notification failed: $e');
      }
    }
  }

  // ─── Fetch ────────────────────────────────────────────────────────────────

  /// Fetch NWR stations and alerts for [lat]/[lon].
  Future<void> refresh(double lat, double lon) async {
    _lastLat = lat;
    _lastLon = lon;
    _isLoading = true;
    _error = null;
    notifyListeners();

    await Future.wait([
      _fetchStations(lat, lon),
      _fetchAlerts(lat, lon),
    ]);

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _fetchStations(double myLat, double myLon) async {
    try {
      debugPrint('NoaaService: GET $_nwrStnUrl');
      final response = await http
          .get(Uri.parse(_nwrStnUrl), headers: _headers)
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        debugPrint('NoaaService: NWR stations HTTP ${response.statusCode}');
        if (_stations.isEmpty) await _loadBundledStations(myLat, myLon);
        return;
      }

      final doc = XmlDocument.parse(response.body);
      final rawStations = <NwrStation>[];

      for (final stn in doc.findAllElements('station')) {
        try {
          final callSign  = stn.findElements('callSign').firstOrNull?.innerText.trim() ?? '';
          final freqStr   = stn.findElements('frequency').firstOrNull?.innerText.trim() ?? '';
          final city      = stn.findElements('city').firstOrNull?.innerText.trim() ?? '';
          final state     = stn.findElements('state').firstOrNull?.innerText.trim() ?? '';
          final latStr    = stn.findElements('lat').firstOrNull?.innerText.trim() ?? '';
          final lonStr    = stn.findElements('lon').firstOrNull?.innerText.trim() ?? '';
          final sameCode  = stn.findElements('sameCode').firstOrNull?.innerText.trim();

          final freq = double.tryParse(freqStr);
          final lat  = double.tryParse(latStr);
          final lon  = double.tryParse(lonStr);

          if (callSign.isEmpty || freq == null || lat == null || lon == null) continue;

          rawStations.add(NwrStation(
            callSign: callSign,
            frequency: freq,
            city: city,
            state: state,
            lat: lat,
            lon: lon,
            sameCode: sameCode?.isNotEmpty == true ? sameCode : null,
            distanceMiles: _distanceMiles(myLat, myLon, lat, lon),
          ));
        } catch (_) {}
      }

      rawStations.sort((a, b) =>
          (a.distanceMiles ?? 99999).compareTo(b.distanceMiles ?? 99999));

      _stations = rawStations;
      debugPrint('NoaaService: Loaded ${_stations.length} NWR stations');
      unawaited(_saveCache());
    } catch (e) {
      debugPrint('NoaaService: Station fetch error — $e');
      if (_stations.isEmpty) await _loadBundledStations(myLat, myLon);
    }
  }

  /// Fallback: parse assets/transmitters/test_transmitters.json → NwrStation list.
  Future<void> _loadBundledStations(double myLat, double myLon) async {
    try {
      const asset = 'assets/transmitters/test_transmitters.json';
      final raw  = await rootBundle.loadString(asset);
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      final stations = list.map((tx) {
        final lat  = (tx['lat']  as num).toDouble();
        final lon  = (tx['lon']  as num).toDouble();
        final codes = (tx['same_codes'] as List<dynamic>).cast<String>();
        return NwrStation(
          callSign:     tx['callsign']  as String,
          frequency:    (tx['frequency'] as num).toDouble(),
          city:         tx['site']      as String,
          state:        tx['state']     as String,
          lat:          lat,
          lon:          lon,
          sameCode:     codes.isNotEmpty ? codes.first : null,
          distanceMiles: _distanceMiles(myLat, myLon, lat, lon),
        );
      }).toList();
      stations.sort((a, b) =>
          (a.distanceMiles ?? 99999).compareTo(b.distanceMiles ?? 99999));
      _stations = stations;
      debugPrint('NoaaService: Loaded ${_stations.length} bundled NWR stations');
    } catch (e) {
      debugPrint('NoaaService: Bundled station load failed: $e');
      _error = 'NWR stations unavailable';
    }
  }

  Future<void> _fetchAlerts(double lat, double lon) async {
    try {
      final uri = Uri.parse('$_alertBaseUrl?point=$lat,$lon');
      debugPrint('NoaaService: GET $uri');
      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        debugPrint('NoaaService: Alerts HTTP ${response.statusCode}');
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final features = data['features'] as List<dynamic>? ?? [];

      var alerts = features
          .map((f) => WeatherAlert.fromJson(f as Map<String, dynamic>))
          .toList();

      // Client-side SAME code filter — keeps alerts with matching county code.
      // Alerts with no SAME codes are kept (they may be region-wide).
      if (_sameCode != null && _sameCode!.isNotEmpty) {
        alerts = alerts
            .where((a) =>
                a.sameCodes.isEmpty || a.sameCodes.contains(_sameCode))
            .toList();
      }

      alerts.sort((a, b) => _severityOrder(b.severity) - _severityOrder(a.severity));
      _alerts = alerts;

      debugPrint('NoaaService: Loaded ${_alerts.length} active alerts');
    } catch (e) {
      debugPrint('NoaaService: Alert fetch error — $e');
      // Non-fatal — stations still shown
    }
  }

  static int _severityOrder(String s) {
    switch (s) {
      case 'Extreme':  return 4;
      case 'Severe':   return 3;
      case 'Moderate': return 2;
      case 'Minor':    return 1;
      default:         return 0;
    }
  }

  /// Haversine distance in miles between two lat/lon points.
  static double _distanceMiles(double lat1, double lon1, double lat2, double lon2) {
    const r = 3958.8; // Earth radius in miles
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = _sin2(dLat / 2) +
        _cos(_toRad(lat1)) * _cos(_toRad(lat2)) * _sin2(dLon / 2);
    final c = 2 * _atan2(a);
    return r * c;
  }

  static double _toRad(double d) => d * 3.141592653589793 / 180;
  static double _sin2(double x) {
    final s = _sin(x);
    return s * s;
  }

  // Simple math helpers to avoid dart:math import coupling
  static double _sin(double x) => _taylorSin(x);
  static double _cos(double x) => _taylorSin(x + 1.5707963267948966);
  static double _atan2(double a) => 2 * _taylorAtan(a / (1 + _taylorSqrt(1 - a)));

  // Taylor-series approximations (sufficient for geographic distances)
  static double _taylorSin(double x) {
    // Reduce to [-pi, pi]
    x = x % (2 * 3.141592653589793);
    if (x > 3.141592653589793) x -= 2 * 3.141592653589793;
    double r = x;
    double t = x;
    for (int i = 1; i <= 7; i++) {
      t *= -x * x / ((2 * i) * (2 * i + 1));
      r += t;
    }
    return r;
  }

  static double _taylorSqrt(double x) {
    // Newton's method
    if (x <= 0) return 0;
    double r = x;
    for (int i = 0; i < 20; i++) r = (r + x / r) / 2;
    return r;
  }

  static double _taylorAtan(double x) {
    if (x > 1) return 3.141592653589793 / 2 - _taylorAtan(1 / x);
    if (x < -1) return -3.141592653589793 / 2 - _taylorAtan(1 / x);
    double r = x;
    double t = x;
    for (int i = 1; i <= 10; i++) {
      t *= -x * x;
      r += t / (2 * i + 1);
    }
    return r;
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
