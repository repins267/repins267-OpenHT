// lib/services/track_service.dart
// GPX track recording service — records GPS positions to a .gpx file.

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';

class TrackService extends ChangeNotifier {
  final List<_TrackPoint> _points = [];
  bool _isRecording = false;
  StreamSubscription<Position>? _sub;

  bool get isRecording  => _isRecording;
  int  get pointCount   => _points.length;

  Future<void> startRecording() async {
    if (_isRecording) return;
    _points.clear();
    _isRecording = true;
    notifyListeners();

    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((pos) {
      _points.add(_TrackPoint(
        lat: pos.latitude,
        lon: pos.longitude,
        alt: pos.altitude,
        time: DateTime.now(),
      ));
      notifyListeners();
    });

    debugPrint('TrackService: Recording started');
  }

  /// Stop recording and save to GPX. Returns the file path or null on error.
  Future<String?> stopRecording() async {
    if (!_isRecording) return null;
    _isRecording = false;
    await _sub?.cancel();
    _sub = null;
    notifyListeners();

    if (_points.isEmpty) return null;

    try {
      final dir  = await getApplicationDocumentsDirectory();
      final ts   = DateTime.now();
      final name = 'track_'
          '${ts.year.toString().padLeft(4,"0")}'
          '${ts.month.toString().padLeft(2,"0")}'
          '${ts.day.toString().padLeft(2,"0")}'
          '_${ts.hour.toString().padLeft(2,"0")}'
          '${ts.minute.toString().padLeft(2,"0")}'
          '${ts.second.toString().padLeft(2,"0")}'
          '.gpx';

      final file = File('${dir.path}/$name');
      await file.writeAsString(_buildGpx(name));
      debugPrint('TrackService: Saved ${_points.length} points → ${file.path}');
      return file.path;
    } catch (e) {
      debugPrint('TrackService: Save failed — $e');
      return null;
    }
  }

  String _buildGpx(String name) {
    final sb = StringBuffer();
    sb.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    sb.writeln('<gpx version="1.1" creator="OpenHT 0.1.0" '
        'xmlns="http://www.topografix.com/GPX/1/1">');
    sb.writeln('  <trk>');
    sb.writeln('    <name>$name</name>');
    sb.writeln('    <trkseg>');
    for (final pt in _points) {
      sb.writeln(
          '      <trkpt lat="${pt.lat}" lon="${pt.lon}">');
      if (pt.alt != null) sb.writeln('        <ele>${pt.alt!.toStringAsFixed(1)}</ele>');
      sb.writeln('        <time>${pt.time.toUtc().toIso8601String()}</time>');
      sb.writeln('      </trkpt>');
    }
    sb.writeln('    </trkseg>');
    sb.writeln('  </trk>');
    sb.writeln('</gpx>');
    return sb.toString();
  }

  /// List all saved GPX tracks in documents directory.
  static Future<List<File>> listTracks() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.gpx'))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
    } catch (_) {
      return [];
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

class _TrackPoint {
  final double lat;
  final double lon;
  final double? alt;
  final DateTime time;
  _TrackPoint({required this.lat, required this.lon, this.alt, required this.time});
}
