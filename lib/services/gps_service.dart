// lib/services/gps_service.dart
// Continuous GPS tracking service - feeds Near Repeater and APRS features

import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';

class GpsService extends ChangeNotifier {
  Position? _lastPosition;
  StreamSubscription<Position>? _positionStream;
  bool _isTracking = false;
  String? _errorMessage;

  Position? get lastPosition => _lastPosition;
  bool get isTracking => _isTracking;
  bool get hasPosition => _lastPosition != null;
  String? get errorMessage => _errorMessage;

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

  /// Request permissions and start position stream
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
      // Non-fatal - stream will populate position
    }

    // Start continuous stream
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // Update every 10 meters of movement
    );

    _positionStream =
        Geolocator.getPositionStream(locationSettings: locationSettings)
            .listen((position) {
      _lastPosition = position;
      _isTracking = true;
      notifyListeners();
    }, onError: (e) {
      _errorMessage = 'GPS error: $e';
      notifyListeners();
    });

    _isTracking = true;
    notifyListeners();
    return true;
  }

  void stopTracking() {
    _positionStream?.cancel();
    _positionStream = null;
    _isTracking = false;
    notifyListeners();
  }

  /// Calculate distance in miles to a [targetLat]/[targetLon]
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
