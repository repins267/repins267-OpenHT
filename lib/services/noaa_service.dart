// lib/services/noaa_service.dart
// Fetches NOAA Weather Radio stations and active weather alerts.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import '../models/nwr_station.dart';
import '../models/weather_alert.dart';

class NoaaService extends ChangeNotifier {
  static const String _nwrStnUrl =
      'https://www.weather.gov/source/nwr/StnInfo.xml';
  static const String _alertBaseUrl = 'https://api.weather.gov/alerts/active';

  List<NwrStation> _stations = [];
  List<WeatherAlert> _alerts = [];
  bool _isLoading = false;
  String? _error;

  List<NwrStation> get stations => List.unmodifiable(_stations);
  List<WeatherAlert> get alerts => List.unmodifiable(_alerts);
  bool get isLoading => _isLoading;
  String? get error => _error;

  static const _headers = {
    'User-Agent': 'OpenHT/0.1 (github.com/repins267/OpenHT)',
    'Accept': 'application/geo+json',
  };

  /// Fetch NWR stations and alerts for [lat]/[lon].
  Future<void> refresh(double lat, double lon) async {
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
        if (_stations.isEmpty) _error = 'NWR station list unavailable (HTTP ${response.statusCode})';
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

          final distMiles = _distanceMiles(myLat, myLon, lat, lon);

          rawStations.add(NwrStation(
            callSign: callSign,
            frequency: freq,
            city: city,
            state: state,
            lat: lat,
            lon: lon,
            sameCode: sameCode?.isNotEmpty == true ? sameCode : null,
            distanceMiles: distMiles,
          ));
        } catch (_) {}
      }

      rawStations.sort((a, b) =>
          (a.distanceMiles ?? 99999).compareTo(b.distanceMiles ?? 99999));

      _stations = rawStations;
      debugPrint('NoaaService: Loaded ${_stations.length} NWR stations');
    } catch (e) {
      debugPrint('NoaaService: Station fetch error — $e');
      // Only show error if we have no cached data; otherwise keep showing existing stations silently.
      if (_stations.isEmpty) {
        _error = 'NWR stations unavailable — check internet connection';
      }
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

      _alerts = features
          .map((f) => WeatherAlert.fromJson(f as Map<String, dynamic>))
          .toList();

      _alerts.sort((a, b) => _severityOrder(b.severity) - _severityOrder(a.severity));

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
}
