// lib/services/lsr_service.dart
// Local Storm Reports via Iowa Environmental Mesonet GeoJSON feed.
// WFO is determined via api.weather.gov/points/{lat},{lon} → properties.cwa

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class LsrReport {
  final double lat;
  final double lon;
  final String type;
  final String city;
  final String magnitude;
  final DateTime valid;

  const LsrReport({
    required this.lat,
    required this.lon,
    required this.type,
    required this.city,
    required this.magnitude,
    required this.valid,
  });

  factory LsrReport.fromJson(Map<String, dynamic> json) {
    final geometry = (json['geometry'] as Map<String, dynamic>?) ?? {};
    final coords = (geometry['coordinates'] as List?) ?? [];
    final props = (json['properties'] as Map<String, dynamic>?) ?? {};
    return LsrReport(
      lat: coords.length >= 2 ? (coords[1] as num).toDouble() : 0.0,
      lon: coords.length >= 2 ? (coords[0] as num).toDouble() : 0.0,
      type: (props['typetext'] as String?) ?? (props['type'] as String?) ?? '',
      city: (props['city'] as String?) ?? '',
      magnitude: (props['magnitude'] as String?) ?? '',
      valid: DateTime.tryParse((props['valid'] as String?) ?? '') ?? DateTime.now(),
    );
  }

  String get emoji {
    final t = type.toLowerCase();
    if (t.contains('tornado')) return '🌪️';
    if (t.contains('hail')) return '🧊';
    if (t.contains('wind')) return '💨';
    if (t.contains('flood')) return '🌊';
    if (t.contains('snow') || t.contains('blizzard')) return '❄️';
    if (t.contains('funnel')) return '🌀';
    if (t.contains('lightning')) return '⚡';
    return '⚠️';
  }

  String get timeAgo {
    final diff = DateTime.now().difference(valid);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
}

class LsrService extends ChangeNotifier {
  static const _pollInterval = Duration(minutes: 5);

  List<LsrReport> _reports = [];
  bool _isLoading = false;
  String? _error;
  String? _wfo;
  Timer? _timer;

  List<LsrReport> get reports => List.unmodifiable(_reports);
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get wfo => _wfo;

  void startPolling(double lat, double lon) {
    _timer?.cancel();
    _fetchAll(lat, lon);
    _timer = Timer.periodic(_pollInterval, (_) => _fetchAll(lat, lon));
  }

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _fetchAll(double lat, double lon) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      // Determine WFO once
      if (_wfo == null) {
        final pointsUri = Uri.parse(
          'https://api.weather.gov/points'
          '/${lat.toStringAsFixed(4)},${lon.toStringAsFixed(4)}',
        );
        final pointsResp = await http.get(pointsUri, headers: {
          'User-Agent': 'OpenHT/0.1 (github.com/repins267/OpenHT)',
          'Accept': 'application/geo+json',
        }).timeout(const Duration(seconds: 15));
        if (pointsResp.statusCode == 200) {
          final data = jsonDecode(pointsResp.body) as Map<String, dynamic>;
          final props = data['properties'] as Map<String, dynamic>?;
          _wfo = props?['cwa'] as String?;
        }
      }
      if (_wfo == null) {
        _error = 'Could not determine WFO';
        _isLoading = false;
        notifyListeners();
        return;
      }
      final lsrUri = Uri.parse(
        'https://mesonet.agron.iastate.edu/geojson/lsr.geojson'
        '?wfo=$_wfo&hours=24',
      );
      final lsrResp = await http.get(lsrUri, headers: {
        'User-Agent': 'OpenHT/0.1',
      }).timeout(const Duration(seconds: 15));
      if (lsrResp.statusCode == 200) {
        final data = jsonDecode(lsrResp.body) as Map<String, dynamic>;
        final features = (data['features'] as List?) ?? [];
        _reports = features
            .map((f) => LsrReport.fromJson(f as Map<String, dynamic>))
            .where((r) => r.lat != 0.0 || r.lon != 0.0)
            .toList()
          ..sort((a, b) => b.valid.compareTo(a.valid));
        _error = null;
      } else {
        debugPrint('LsrService: HTTP ${lsrResp.statusCode}');
        if (_reports.isEmpty) _error = 'LSR HTTP ${lsrResp.statusCode}';
      }
    } catch (e) {
      debugPrint('LsrService: $e');
      if (_reports.isEmpty) _error = 'LSR unavailable';
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
