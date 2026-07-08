// lib/aprs/aprs_service.dart
// Receives and manages APRS packets decoded from the radio via BT TNC

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'aprs_packet.dart';

class AprsService extends ChangeNotifier {
  final List<AprsPacket> _log = [];
  final int _maxLog = 500;

  // Last heard: callsign → most recent packet (from any source)
  final Map<String, AprsPacket> _lastHeard = {};
  // All sources that have heard each callsign
  final Map<String, Set<AprsSource>> _heardSources = {};

  StreamSubscription? _isSubscription;
  StreamSubscription? _rfSubscription;

  List<AprsPacket> get stations => List.unmodifiable(_lastHeard.values.toList());
  List<AprsPacket> get recentPackets => List.unmodifiable(_log);
  int get stationCount => _lastHeard.length;

  /// All sources heard for a given callsign.
  Set<AprsSource> sourcesFor(String fullCallsign) =>
      _heardSources[fullCallsign.toUpperCase()] ?? {};

  /// Attach APRS-IS packet stream (internet).
  void attachIsStream(Stream<String> rawPacketStream) {
    _isSubscription?.cancel();
    _isSubscription = rawPacketStream.listen((raw) {
      final packet = AprsPacket.tryParse(raw, source: AprsSource.aprsIs);
      if (packet != null) _processPacket(packet);
    });
  }

  /// Attach RF/TNC packet stream (radio).
  void attachRfStream(Stream<String> rawPacketStream) {
    _rfSubscription?.cancel();
    _rfSubscription = rawPacketStream.listen((raw) {
      final packet = AprsPacket.tryParse(raw, source: AprsSource.rf);
      if (packet != null) _processPacket(packet);
    });
  }

  /// Legacy — kept for compatibility; treats stream as APRS-IS.
  void attachPacketStream(Stream<String> rawPacketStream) =>
      attachIsStream(rawPacketStream);

  void _processPacket(AprsPacket packet) {
    _log.add(packet);
    if (_log.length > _maxLog) _log.removeAt(0);

    final key = packet.fullCallsign.toUpperCase();
    // Prefer RF packet in _lastHeard if both sources are present
    final existing = _lastHeard[key];
    if (existing == null ||
        packet.source == AprsSource.rf ||
        existing.source == AprsSource.aprsIs) {
      // Carry the station's last-known position forward. Many APRS packets
      // (status, messages, telemetry, WX-without-position) have no lat/lon;
      // without this they clobber the stored position and the station is
      // counted but silently dropped from the map.
      var toStore = packet;
      if (!packet.hasPosition && existing != null && existing.hasPosition) {
        toStore = packet.copyWith(
          latitude: existing.latitude,
          longitude: existing.longitude,
          symbol: packet.symbol ?? existing.symbol,
          symbolTable: packet.symbolTable ?? existing.symbolTable,
        );
      }
      _lastHeard[key] = toStore;
    }

    // Track all sources heard
    _heardSources.putIfAbsent(key, () => {}).add(packet.source);

    notifyListeners();
  }

  /// Inject a test packet (for development/testing without radio)
  void injectTestPacket(String raw) {
    final packet = AprsPacket.tryParse(raw);
    if (packet != null) _processPacket(packet);
  }

  void clear() {
    _log.clear();
    _lastHeard.clear();
    _heardSources.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _isSubscription?.cancel();
    _rfSubscription?.cancel();
    super.dispose();
  }
}
