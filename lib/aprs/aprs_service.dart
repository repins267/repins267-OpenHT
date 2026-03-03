// lib/aprs/aprs_service.dart
// Receives and manages APRS packets decoded from the radio via BT TNC

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'aprs_packet.dart';

class AprsService extends ChangeNotifier {
  final List<AprsPacket> _stations = [];
  final int _maxStations = 200;

  // Last heard: callsign → most recent packet
  final Map<String, AprsPacket> _lastHeard = {};

  StreamSubscription? _packetSubscription;

  List<AprsPacket> get stations => List.unmodifiable(_lastHeard.values.toList());
  List<AprsPacket> get recentPackets => List.unmodifiable(_stations);
  int get stationCount => _lastHeard.length;

  /// Connect to a raw packet stream (from radio BT TNC KISS interface)
  void attachPacketStream(Stream<String> rawPacketStream) {
    _packetSubscription?.cancel();
    _packetSubscription = rawPacketStream.listen((raw) {
      final packet = AprsPacket.tryParse(raw);
      if (packet != null) _processPacket(packet);
    });
  }

  void _processPacket(AprsPacket packet) {
    // Add to recent log
    _stations.add(packet);
    if (_stations.length > _maxStations) {
      _stations.removeAt(0);
    }

    // Update last-heard map (deduplicated by callsign)
    _lastHeard[packet.fullCallsign] = packet;

    notifyListeners();
  }

  /// Inject a test packet (for development/testing without radio)
  void injectTestPacket(String raw) {
    final packet = AprsPacket.tryParse(raw);
    if (packet != null) _processPacket(packet);
  }

  void clear() {
    _stations.clear();
    _lastHeard.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _packetSubscription?.cancel();
    super.dispose();
  }
}
