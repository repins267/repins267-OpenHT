// lib/services/gps_service.dart
// Continuous GPS tracking service — feeds Near Repeater and APRS features.
// Supports adaptive frequency: high (connected radio) and low (background).

import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';

class GpsService extends ChangeNotifier {
  Position? _lastPosition;
  StreamSubscription<Position>? _positionStream;
  bool _isTracking = false;
  String? _errorMessage;
  bool _isHighFrequency = false;

  Position? get lastPosition => _lastPosition;
  bool get isTracking => _isTracking;
  bool get hasPosition => _lastPosition != null;
  String? get errorMessage => _errorMessage;
  bool get isHighFrequency => _isHighFrequency;

  double? get latitude => _lastPosition?.latitude;
  double? get longitude => _lastPosition?.longitude;
  double? get altitudeMeters => _lastPosition?.altitude;
  double? get speedMps => _lastPosition?.speed;
  double? get headingDegrees => _lastPosition?.heading;

  String get displayPosition {
    if (_lastPosition == null) return 'No GPS Fix';
    final lat = _lastPosition!.latitude;
    final lon = _lastPosition!.longitude;
    final latDir = lat >= 0 ? 'N' : 'S';
    final lonDir = lon >= 0 ? 'E' : 'W';
    return '${lat.abs().toStringAsFixed(4)}°$latDir  '
        '${lon.abs().toStringAsFixed(4)}°$lonDir';
  }

  /// Request permissions and start position stream at low-frequency mode.
  Future<bool> startTracking() async {
    _errorMessage = null;

    // Check/request permissions
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _errorMessage = 'Location permission denied';
        notifyListeners();
        return false;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      _errorMessage =
          'Location permission permanently denied — enable in Settings';
      notifyListeners();
      return false;
    }

    // Check if location services are enabled
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _errorMessage = 'Location services are disabled';
      notifyListeners();
      return false;
    }

    // Get an immediate position fix
    try {
      _lastPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (_) {
      // Non-fatal — stream will populate position
    }

    _isHighFrequency = false;
    await _startStream(_lowFreqSettings());
    _isTracking = true;
    notifyListeners();
    return true;
  }

  /// Switch to high-frequency updates (radio connected / active navigation).
  /// Updates every ~1 second with a 5 m movement threshold.
  Future<void> setHighFrequency() async {
    if (!_isTracking) return;
    _isHighFrequency = true;
    await _startStream(_highFreqSettings());
    debugPrint('GPS: → high-frequency mode (1s / 5m)');
    notifyListeners();
  }

  /// Switch to low-frequency updates (background / radio disconnected).
  /// Updates every 5 minutes or after 50 m movement.
  Future<void> setLowFrequency() async {
    if (!_isTracking) return;
    _isHighFrequency = false;
    await _startStream(_lowFreqSettings());
    debugPrint('GPS: → low-frequency mode (5min / 50m)');
    notifyListeners();
  }

  Future<void> _startStream(LocationSettings settings) async {
    await _positionStream?.cancel();
    _positionStream =
        Geolocator.getPositionStream(locationSettings: settings).listen(
      (position) {
        _lastPosition = position;
        _isTracking = true;
        notifyListeners();
      },
      onError: (e) {
        _errorMessage = 'GPS error: $e';
        notifyListeners();
      },
    );
  }

  static LocationSettings _highFreqSettings() => const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        timeLimit: Duration(milliseconds: 1000),
      );

  static LocationSettings _lowFreqSettings() => const LocationSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 50,
        timeLimit: Duration(milliseconds: 300000),
      );

  void stopTracking() {
    _positionStream?.cancel();
    _positionStream = null;
    _isTracking = false;
    notifyListeners();
  }

  /// Calculate distance in miles to a [targetLat]/[targetLon].
  double? distanceMilesTo(double targetLat, double targetLon) {
    if (_lastPosition == null) return null;
    final meters = Geolocator.distanceBetween(
      _lastPosition!.latitude,
      _lastPosition!.longitude,
      targetLat,
      targetLon,
    );
    return meters / 1609.344;
  }

  @override
  void dispose() {
    stopTracking();
    super.dispose();
  }
}
