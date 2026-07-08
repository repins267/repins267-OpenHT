// lib/services/nws_alert_service.dart
// Polls api.weather.gov for active alerts at the user's GPS position.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/nws_alert.dart';

class NwsAlertService extends ChangeNotifier {
  static const _pollInterval = Duration(minutes: 2);

  List<NwsAlert> _alerts = [];
  bool _isLoading = false;
  String? _error;
  Timer? _timer;
  double? _lastLat;
  double? _lastLon;

  List<NwsAlert> get alerts => List.unmodifiable(_alerts);
  List<NwsAlert> get warnings =>
      _alerts.where((a) => a.type == NwsAlertType.warning).toList();
  List<NwsAlert> get watches =>
      _alerts.where((a) => a.type == NwsAlertType.watch).toList();
  List<NwsAlert> get statements =>
      _alerts.where((a) => a.type == NwsAlertType.statement).toList();
  bool get isLoading => _isLoading;
  String? get error => _error;

  void startPolling(double lat, double lon) {
    _lastLat = lat;
    _lastLon = lon;
    _timer?.cancel();
    fetch(lat, lon);
    _timer = Timer.periodic(_pollInterval, (_) {
      if (_lastLat != null && _lastLon != null) {
        fetch(_lastLat!, _lastLon!);
      }
    });
  }

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  void updateLocation(double lat, double lon) {
    _lastLat = lat;
    _lastLon = lon;
    if (_timer != null) fetch(lat, lon);
  }

  Future<void> fetch(double lat, double lon) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final uri = Uri.parse(
        'https://api.weather.gov/alerts/active'
        '?point=${lat.toStringAsFixed(4)},${lon.toStringAsFixed(4)}',
      );
      final resp = await http.get(uri, headers: {
        'User-Agent': 'OpenHT/0.1 (github.com/repins267/OpenHT)',
        'Accept': 'application/geo+json',
      }).timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final features = (data['features'] as List?) ?? [];
        _alerts = features
            .map((f) => NwsAlert.fromJson(f as Map<String, dynamic>))
            .toList();
        _error = null;
      } else {
        debugPrint('NwsAlertService: HTTP ${resp.statusCode}');
        if (_alerts.isEmpty) _error = 'NWS alerts HTTP ${resp.statusCode}';
      }
    } catch (e) {
      debugPrint('NwsAlertService: $e');
      if (_alerts.isEmpty) _error = 'NWS alerts unavailable';
    }
    _isLoading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
