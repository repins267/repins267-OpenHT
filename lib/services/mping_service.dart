// lib/services/mping_service.dart
// Fetches crowdsourced weather reports from mPING (NOAA/OU).
// API: https://mping.ou.edu/mping/api/v2/reports/

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/mping_report.dart';

class MpingService extends ChangeNotifier {
  static const _pollInterval = Duration(minutes: 5);
  static const _radiusMiles = 75;
  static const _windowMinutes = 60;

  List<MpingReport> _reports = [];
  bool _isLoading = false;
  String? _error;
  Timer? _timer;

  List<MpingReport> get reports => List.unmodifiable(_reports);
  bool get isLoading => _isLoading;
  String? get error => _error;

  void startPolling(double lat, double lon) {
    _timer?.cancel();
    fetch(lat, lon);
    _timer = Timer.periodic(_pollInterval, (_) => fetch(lat, lon));
  }

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> fetch(double lat, double lon) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final uri = Uri.parse(
        'https://mping.ou.edu/mping/api/v2/reports/'
        '?lat=${lat.toStringAsFixed(4)}'
        '&lon=${lon.toStringAsFixed(4)}'
        '&dist=$_radiusMiles'
        '&minutes=$_windowMinutes'
        '&format=json',
      );
      final resp = await http.get(uri, headers: {
        'User-Agent': 'OpenHT/0.1 (github.com/repins267/OpenHT)',
      }).timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        List<dynamic> features;
        if (data is Map && data.containsKey('features')) {
          features = data['features'] as List<dynamic>;
        } else if (data is List) {
          features = data;
        } else {
          features = [];
        }
        _reports = features
            .map((f) => MpingReport.fromJson(f as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        _error = null;
      } else {
        debugPrint('MpingService: HTTP ${resp.statusCode}');
        if (_reports.isEmpty) _error = 'mPING HTTP ${resp.statusCode}';
      }
    } catch (e) {
      debugPrint('MpingService: $e');
      if (_reports.isEmpty) _error = 'mPING unavailable';
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
