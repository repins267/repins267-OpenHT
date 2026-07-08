// lib/services/spotter_network_service.dart
// Authenticated Spotter Network service:
//  - sign-in / sign-out (credentials stored as SHA-256 hash)
//  - fetches public gr.txt pipe-delimited position feed
//  - controls location reporting and map display preferences

import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/spotter.dart';

class SpotterNetworkService extends ChangeNotifier {
  static const _grFeedUrl = 'http://www.spotternetwork.org/feeds/gr.txt';
  static const _pollInterval = Duration(minutes: 5);

  String? _username;
  bool _isSignedIn = false;
  bool _showOnMap = true;
  bool _showMyLocation = false;
  bool _notifyNearby = false;
  double _notifyRadiusMi = 25.0;
  bool _isLoading = false;
  List<SpotterPosition> _spotters = [];
  Timer? _timer;
  String? _error;

  String? get username => _username;
  bool get isSignedIn => _isSignedIn;
  bool get showOnMap => _showOnMap;
  bool get showMyLocation => _showMyLocation;
  bool get notifyNearby => _notifyNearby;
  double get notifyRadiusMi => _notifyRadiusMi;
  bool get isLoading => _isLoading;
  List<SpotterPosition> get spotters => List.unmodifiable(_spotters);
  String? get error => _error;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _username = prefs.getString('sn_username');
    _isSignedIn = _username != null && _username!.isNotEmpty;
    _showOnMap = prefs.getBool('sn_show_on_map') ?? true;
    _showMyLocation = prefs.getBool('sn_show_my_location') ?? false;
    _notifyNearby = prefs.getBool('sn_notify_nearby') ?? false;
    _notifyRadiusMi = prefs.getDouble('sn_notify_radius_mi') ?? 25.0;
    notifyListeners();
    if (_showOnMap) startPolling();
  }

  void startPolling() {
    _timer?.cancel();
    fetch();
    _timer = Timer.periodic(_pollInterval, (_) => fetch());
  }

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
    _spotters = [];
    notifyListeners();
  }

  Future<bool> signIn(String username, String password) async {
    // Store SHA-256 hash of password; never persist plaintext
    final hash = sha256.convert(utf8.encode(password)).toString();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sn_username', username);
    await prefs.setString('sn_password_hash', hash);
    _username = username;
    _isSignedIn = true;
    notifyListeners();
    return true;
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('sn_username');
    await prefs.remove('sn_password_hash');
    _username = null;
    _isSignedIn = false;
    notifyListeners();
  }

  Future<void> setShowOnMap(bool value) async {
    _showOnMap = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sn_show_on_map', value);
    value ? startPolling() : stopPolling();
    notifyListeners();
  }

  Future<void> setShowMyLocation(bool value) async {
    _showMyLocation = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sn_show_my_location', value);
    notifyListeners();
  }

  Future<void> setNotifyNearby(bool value) async {
    _notifyNearby = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sn_notify_nearby', value);
    notifyListeners();
  }

  Future<void> setNotifyRadius(double miles) async {
    _notifyRadiusMi = miles;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('sn_notify_radius_mi', miles);
    notifyListeners();
  }

  Future<void> fetch() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final resp = await http.get(Uri.parse(_grFeedUrl), headers: {
        'User-Agent': 'OpenHT/0.1 (github.com/repins267/OpenHT)',
      }).timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) {
        // Feed can contain non-UTF-8 bytes (accented names); resp.body throws
        // FormatException on those, so decode leniently from the raw bytes.
        _spotters = _parseGrFeed(utf8.decode(resp.bodyBytes, allowMalformed: true));
        _error = null;
        debugPrint(
            'SpotterNetworkService: loaded ${_spotters.length} spotters');
      } else {
        debugPrint('SpotterNetworkService: HTTP ${resp.statusCode}');
        if (_spotters.isEmpty) _error = 'Spotter feed HTTP ${resp.statusCode}';
      }
    } catch (e) {
      debugPrint('SpotterNetworkService: $e');
      if (_spotters.isEmpty) _error = 'Spotter feed unavailable';
    }
    _isLoading = false;
    notifyListeners();
  }

  List<SpotterPosition> _parseGrFeed(String body) {
    final results = <SpotterPosition>[];
    for (final line in body.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final parts = trimmed.split('|');
      if (parts.length < 3) continue;
      try {
        final lat = double.tryParse(parts[1].trim());
        final lon = double.tryParse(parts[2].trim());
        if (lat == null || lon == null) continue;
        if (lat == 0.0 && lon == 0.0) continue;
        results.add(SpotterPosition(
          name: parts[0].trim(),
          lat: lat,
          lon: lon,
          speedMph: parts.length > 3
              ? double.tryParse(parts[3].trim())
              : null,
          heading: parts.length > 4
              ? double.tryParse(parts[4].trim())
              : null,
          timestamp: parts.length > 5 ? parts[5].trim() : null,
          note: parts.length > 6 ? parts[6].trim() : null,
        ));
      } catch (_) {}
    }
    return results;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
