// lib/services/spotter_service.dart
// Polls the Spotter Network public data feed every 60 seconds and
// exposes parsed storm spotter positions.
// Public feed: http://www.spotternetwork.org/misc/data.xml
// Format: <spotter lat="..." lng="..." callsign="..." name="..." ago="..."/>

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';
import '../models/spotter_station.dart';

class SpotterService extends ChangeNotifier {
  static const String _feedUrl = 'http://www.spotternetwork.org/misc/data.xml';
  static const Duration _pollInterval = Duration(seconds: 60);
  static const String _prefKey = 'spotter_network_enabled';

  List<SpotterStation> _spotters = [];
  bool _isLoading = false;
  bool _enabled = false;
  String? _error;
  Timer? _timer;

  List<SpotterStation> get spotters => _enabled ? List.unmodifiable(_spotters) : const [];
  bool get isLoading => _isLoading;
  bool get enabled => _enabled;
  String? get error => _error;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_prefKey) ?? false;
    notifyListeners();
    if (_enabled) {
      await fetch();
      _timer = Timer.periodic(_pollInterval, (_) => fetch());
    }
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, value);
    if (value) {
      await fetch();
      _timer ??= Timer.periodic(_pollInterval, (_) => fetch());
    } else {
      _timer?.cancel();
      _timer = null;
      _spotters = [];
    }
    notifyListeners();
  }

  Future<void> fetch() async {
    if (!_enabled) return;
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
