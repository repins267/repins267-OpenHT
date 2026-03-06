// lib/services/weather_alert_controller.dart
// Polls NWS every 60 s for Tornado/Severe Thunderstorm warnings.
// If a critical alert matches the user's FIPS code, auto-tunes VFO A to the
// agency SKYWARN repeater (from a loaded freq plan) or the nearest NOAA
// transmitter, and locks the frequency for 5 minutes.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../services/noaa_service.dart';
import '../bluetooth/radio_service.dart';
import '../services/gps_service.dart';
import '../services/freq_plan_service.dart';

class WeatherAlertController extends ChangeNotifier {
  NoaaService? _noaa;
  RadioService? _radio;
  GpsService? _gps;

  Timer? _timer;
  bool _initialized = false;

  String? _autoTunedFreq;   // e.g. "146.970 MHz (SKYWARN)"
  DateTime? _lockUntil;
  List<Map<String, dynamic>> _transmitters = [];

  /// FIPS → FreqPlan map for agency SKYWARN channel lookups.
  final Map<String, FreqPlan> _fipsPlanMap = {};

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
      _loadResources().then((_) {
        _timer = Timer.periodic(const Duration(seconds: 60), (_) => _check());
      });
    }
  }

  Future<void> _loadResources() async {
    await Future.wait([
      _loadTransmitters(),
      _loadFreqPlans(),
    ]);
  }

  Future<void> _loadTransmitters() async {
    try {
      final raw = await rootBundle
          .loadString('assets/transmitters/test_transmitters.json');
      _transmitters =
          (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      debugPrint(
          'WeatherAlertCtrl: Loaded ${_transmitters.length} NWR transmitters');
    } catch (e) {
      debugPrint('WeatherAlertCtrl: Failed to load transmitters: $e');
    }
  }

  Future<void> _loadFreqPlans() async {
    // Load served-agency plans from assets/freq_plans/.
    // Add more plan IDs here as new plans are created.
    const planIds = ['ppraa_el_paso'];
    for (final planId in planIds) {
      final plan = await FreqPlanService.loadPlan(planId);
      if (plan != null) {
        _fipsPlanMap[plan.fips] = plan;
        debugPrint(
            'WeatherAlertCtrl: Loaded freq plan "${plan.name}" (FIPS ${plan.fips})');
      }
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

    // ── Priority 1: Agency SKYWARN repeater from a loaded freq plan ──────────
    for (final sameCode in critical.sameCodes) {
      final plan = _fipsPlanMap[sameCode];
      if (plan == null) continue;

      final skywarnCh = plan.channels
          .where((c) => c.name.toUpperCase().contains('SKYWARN'))
          .firstOrNull;
      if (skywarnCh == null) continue;

      if (_radio!.isConnected) {
        final ok = await _radio!.tuneToFrequency(skywarnCh.rxMhz);
        if (ok) {
          _autoTunedFreq =
              '${skywarnCh.rxMhz.toStringAsFixed(3)} MHz (${skywarnCh.name})';
          _lockUntil =
              DateTime.now().add(const Duration(minutes: 5));
          debugPrint(
              'WeatherAlertCtrl: AUTO-TUNED (SKYWARN plan) → $_autoTunedFreq '
              'for ${critical.event}');
          notifyListeners();
        }
      }
      return;
    }

    // ── Priority 2: NWR transmitter lookup (generic fallback) ────────────────
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
                'WeatherAlertCtrl: AUTO-TUNED (NWR) → $_autoTunedFreq '
                'for ${critical.event}');
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
