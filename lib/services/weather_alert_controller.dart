// lib/services/weather_alert_controller.dart
// Polls NWS every 60 s for Tornado/Severe Thunderstorm warnings.
// If a critical alert matches the user's FIPS code, auto-tunes VFO A to the
// nearest NOAA transmitter and locks the frequency for 5 minutes.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/weather_alert.dart';
import '../services/noaa_service.dart';
import '../bluetooth/radio_service.dart';
import '../services/gps_service.dart';

class WeatherAlertController extends ChangeNotifier {
  NoaaService? _noaa;
  RadioService? _radio;
  GpsService? _gps;

  Timer? _timer;
  bool _initialized = false;

  String? _autoTunedFreq;   // e.g. "162.475 MHz (KEC76 – Denver)"
  DateTime? _lockUntil;
  List<Map<String, dynamic>> _transmitters = [];

  bool get isFreqLocked =>
      _lockUntil != null && DateTime.now().isBefore(_lockUntil!);
  bool get hasEmergencyAlert => isFreqLocked && _autoTunedFreq != null;
  String? get autoTunedFreq => _autoTunedFreq;

  /// Called by ProxyProvider whenever upstream services change.
  void update({
    required NoaaService noaa,
    required RadioService radio,
    required GpsService gps,
  }) {
    _noaa  = noaa;
    _radio = radio;
    _gps   = gps;

    if (!_initialized) {
      _initialized = true;
      _loadTransmitters().then((_) {
        _timer = Timer.periodic(const Duration(seconds: 60), (_) => _check());
      });
    }
  }

  Future<void> _loadTransmitters() async {
    try {
      final raw = await rootBundle
          .loadString('assets/transmitters/test_transmitters.json');
      _transmitters =
          (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      debugPrint(
          'WeatherAlertCtrl: Loaded ${_transmitters.length} transmitters');
    } catch (e) {
      debugPrint('WeatherAlertCtrl: Failed to load transmitters: $e');
    }
  }

  Future<void> _check() async {
    if (_noaa == null || _radio == null || _gps == null) return;
    // Prefer radio GPS; fall back to phone GPS
    final double lat;
    final double lon;
    if (_radio!.hasRadioGps) {
      lat = _radio!.radioLatitude!;
      lon = _radio!.radioLongitude!;
    } else if (_gps!.hasPosition) {
      lat = _gps!.latitude!;
      lon = _gps!.longitude!;
    } else {
      return; // no position available
    }
    if (isFreqLocked) return;

    await _noaa!.refresh(lat, lon);

    final critical = _noaa!.alerts
        .where((a) =>
            a.event.contains('Tornado') ||
            a.event.contains('Severe Thunderstorm Warning'))
        .firstOrNull;

    if (critical == null || critical.sameCodes.isEmpty) return;

    for (final tx in _transmitters) {
      final txCodes = (tx['same_codes'] as List<dynamic>).cast<String>();
      if (txCodes.any((c) => critical.sameCodes.contains(c))) {
        final freq     = (tx['frequency'] as num).toDouble();
        final callsign = tx['callsign']  as String? ?? '';
        final site     = tx['site']      as String? ?? '';

        if (_radio!.isConnected) {
          final ok = await _radio!.tuneToFrequency(freq);
          if (ok) {
            _autoTunedFreq =
                '${freq.toStringAsFixed(3)} MHz ($callsign – $site)';
            _lockUntil =
                DateTime.now().add(const Duration(minutes: 5));
            debugPrint(
                'WeatherAlertCtrl: AUTO-TUNED to $_autoTunedFreq for ${critical.event}');
            notifyListeners();
          }
        }
        return;
      }
    }
  }

  /// Manually run a check now (e.g. on Weather tab open).
  Future<void> checkNow() => _check();

  /// Clear the emergency lock (user dismisses the banner).
  void clearLock() {
    _autoTunedFreq = null;
    _lockUntil     = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
