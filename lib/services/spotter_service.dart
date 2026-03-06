// lib/services/spotter_service.dart
// Polls the Spotter Network public data feed every 60 seconds and
// exposes parsed storm spotter positions.
// Public feed: http://www.spotternetwork.org/misc/data.xml
// Format: <spotter lat="..." lng="..." callsign="..." name="..." ago="..."/>

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import '../models/spotter_station.dart';

class SpotterService extends ChangeNotifier {
  static const String _feedUrl = 'http://www.spotternetwork.org/misc/data.xml';
  static const Duration _pollInterval = Duration(seconds: 60);

  List<SpotterStation> _spotters = [];
  bool _isLoading = false;
  String? _error;
  Timer? _timer;

  List<SpotterStation> get spotters => List.unmodifiable(_spotters);
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> init() async {
    await fetch();
    _timer = Timer.periodic(_pollInterval, (_) => fetch());
  }

  Future<void> fetch() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      debugPrint('SpotterService: GET $_feedUrl');

      final response = await http
          .get(Uri.parse(_feedUrl), headers: {
            'User-Agent': 'OpenHT/0.1 (github.com/repins267/OpenHT)',
          })
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        debugPrint('SpotterService: HTTP ${response.statusCode}');
        if (_spotters.isEmpty) _error = 'Spotter feed HTTP ${response.statusCode}';
        _isLoading = false;
        notifyListeners();
        return;
      }

      final parsed = _parseXml(response.body);
      _spotters = parsed;
      debugPrint('SpotterService: Loaded ${_spotters.length} spotters');
    } catch (e) {
      debugPrint('SpotterService: Fetch error — $e');
      if (_spotters.isEmpty) _error = 'Spotter data unavailable';
    }

    _isLoading = false;
    notifyListeners();
  }

  List<SpotterStation> _parseXml(String body) {
    try {
      final doc = XmlDocument.parse(body);
      final result = <SpotterStation>[];

      // <spotter lat="..." lng="..." callsign="..." name="..." ago="..."/>
      for (final el in doc.findAllElements('spotter')) {
        try {
          final lat = double.tryParse(el.getAttribute('lat') ?? '');
          final lon = double.tryParse(el.getAttribute('lng') ?? '');
          if (lat == null || lon == null) continue;
          if (lat == 0.0 && lon == 0.0) continue;

          final callsign = el.getAttribute('callsign')?.trim() ?? '';
          final name     = el.getAttribute('name')?.trim() ?? callsign;
          final ago      = el.getAttribute('ago')?.trim();

          result.add(SpotterStation(
            name: callsign.isNotEmpty ? callsign : name,
            lat: lat,
            lon: lon,
            lastReport: ago != null && ago.isNotEmpty ? '$ago ago' : null,
            description: name.isNotEmpty && name != callsign ? name : null,
          ));
        } catch (_) {}
      }

      return result;
    } catch (e) {
      debugPrint('SpotterService: XML parse error — $e');
      return [];
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
