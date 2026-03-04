// lib/services/spotter_service.dart
// Polls the Spotter Network KML feed every 60 seconds and
// exposes parsed storm spotter positions.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/spotter_station.dart';

class SpotterService extends ChangeNotifier {
  static const String _defaultAppId = '4f2e07d475ae4';
  static const Duration _pollInterval = Duration(seconds: 60);

  List<SpotterStation> _spotters = [];
  bool _isLoading = false;
  String? _error;
  Timer? _timer;
  String _appId = _defaultAppId;

  List<SpotterStation> get spotters => List.unmodifiable(_spotters);
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _appId = prefs.getString('spotter_app_id') ?? _defaultAppId;
    await fetch();
    _timer = Timer.periodic(_pollInterval, (_) => fetch());
  }

  Future<void> fetch() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final url = 'https://www.spotternetwork.org/pro/feed/$_appId/gm.php';
      debugPrint('SpotterService: GET $url');

      final response = await http
          .get(Uri.parse(url), headers: {
            'User-Agent': 'OpenHT/0.1 (github.com/repins267/OpenHT)',
          })
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        debugPrint('SpotterService: HTTP ${response.statusCode}');
        _error = 'Spotter feed HTTP ${response.statusCode}';
        _isLoading = false;
        notifyListeners();
        return;
      }

      _spotters = _parseKml(response.body);
      debugPrint('SpotterService: Loaded ${_spotters.length} spotters');
    } catch (e) {
      debugPrint('SpotterService: Fetch error — $e');
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  List<SpotterStation> _parseKml(String body) {
    try {
      final doc = XmlDocument.parse(body);
      final placemarks = doc.findAllElements('Placemark');
      final result = <SpotterStation>[];

      for (final pm in placemarks) {
        try {
          final name = pm.findElements('name').firstOrNull?.innerText.trim() ?? '';
          final desc = pm.findElements('description').firstOrNull?.innerText.trim();
          final coordStr = pm.findAllElements('coordinates').firstOrNull?.innerText.trim() ?? '';

          // KML coordinates are "lon,lat[,alt]"
          final parts = coordStr.split(',');
          if (parts.length < 2) continue;
          final lon = double.tryParse(parts[0].trim());
          final lat = double.tryParse(parts[1].trim());
          if (lat == null || lon == null) continue;

          // Try to extract report type from description (HTML)
          String? reportType;
          String? lastReport;
          if (desc != null) {
            final typeMatch = RegExp(r'Type:\s*([^\n<]+)').firstMatch(desc);
            reportType = typeMatch?.group(1)?.trim();
            final timeMatch = RegExp(r'Time:\s*([^\n<]+)').firstMatch(desc);
            lastReport = timeMatch?.group(1)?.trim();
          }

          result.add(SpotterStation(
            name: name,
            lat: lat,
            lon: lon,
            reportType: reportType,
            lastReport: lastReport,
            description: desc != null ? _stripHtml(desc) : null,
          ));
        } catch (_) {}
      }

      return result;
    } catch (e) {
      debugPrint('SpotterService: KML parse error — $e');
      return [];
    }
  }

  static String _stripHtml(String html) =>
      html.replaceAll(RegExp(r'<[^>]+>'), '').trim();

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
