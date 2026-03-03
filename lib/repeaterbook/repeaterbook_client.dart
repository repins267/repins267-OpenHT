// lib/repeaterbook/repeaterbook_client.dart
// RepeaterBook API integration for Near Repeater feature
// API docs: https://www.repeaterbook.com/wiki/doku.php?id=api

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/repeater.dart';

class RepeaterBookClient {
  static const String _baseUrl = 'https://www.repeaterbook.com/api/export.php';
  static const Duration _timeout = Duration(seconds: 15);

  // RepeaterBook API rate limit: be polite, max 1 req/sec
  static DateTime? _lastRequest;
  static const Duration _minInterval = Duration(milliseconds: 1100);

  /// Fetch open repeaters near [lat]/[lon] within [radiusMiles].
  /// Returns list sorted by distance ascending (closest first).
  ///
  /// [band] - filter band: '2m', '70cm', or null for both
  /// [onlyOpen] - if true, only return OPEN use repeaters
  Future<List<Repeater>> fetchNearby({
    required double lat,
    required double lon,
    double radiusMiles = 50,
    String? band,
    bool onlyOpen = true,
    String country = 'US',
  }) async {
    await _rateLimit();

    // Map band filter to frequency range for RepeaterBook API
    String freqFilter = '';
    if (band == '2m') freqFilter = '&freq=144&band=%25';
    if (band == '70cm') freqFilter = '&freq=440&band=%25';

    final use = onlyOpen ? 'OPEN' : '';

    final uri = Uri.parse(
      '$_baseUrl'
      '?country=$country'
      '&lat=$lat'
      '&lng=$lon'
      '&distance=${radiusMiles.round()}'
      '&Dunit=m'
      '$freqFilter'
      '&use=$use'
      '&order=distance_asc'
      '&format=json',
    );

    final response = await http
        .get(uri, headers: {'User-Agent': 'OpenHT/0.1 (github.com/repins267/OpenHT)'})
        .timeout(_timeout);

    if (response.statusCode != 200) {
      throw RepeaterBookException(
          'RepeaterBook API error: HTTP ${response.statusCode}');
    }

    final data = jsonDecode(response.body);

    // RepeaterBook returns {"count": N, "results": [...]}
    if (data is! Map || data['results'] == null) {
      return [];
    }

    final results = data['results'] as List<dynamic>;
    return results.map((json) {
      final distMiles = _parseDistanceMiles(json['distance']);
      return Repeater.fromRepeaterBookJson(
        json as Map<String, dynamic>,
        distanceMiles: distMiles,
      );
    }).toList();
  }

  /// Fetch repeaters by state (for offline pre-loading)
  Future<List<Repeater>> fetchByState(String stateAbbr) async {
    await _rateLimit();

    final uri = Uri.parse(
      '$_baseUrl?country=US&state=$stateAbbr&format=json&use=OPEN',
    );

    final response = await http
        .get(uri, headers: {'User-Agent': 'OpenHT/0.1 (github.com/repins267/OpenHT)'})
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw RepeaterBookException(
          'RepeaterBook API error: HTTP ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    if (data is! Map || data['results'] == null) return [];

    return (data['results'] as List)
        .map((j) => Repeater.fromRepeaterBookJson(j as Map<String, dynamic>))
        .toList();
  }

  static double? _parseDistanceMiles(dynamic v) {
    if (v == null) return null;
    return double.tryParse(v.toString());
  }

  static Future<void> _rateLimit() async {
    if (_lastRequest != null) {
      final elapsed = DateTime.now().difference(_lastRequest!);
      if (elapsed < _minInterval) {
        await Future.delayed(_minInterval - elapsed);
      }
    }
    _lastRequest = DateTime.now();
  }
}

class RepeaterBookException implements Exception {
  final String message;
  RepeaterBookException(this.message);
  @override
  String toString() => 'RepeaterBookException: $message';
}
