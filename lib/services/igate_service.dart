// lib/services/igate_service.dart
// APRS iGate service — when enabled, forwards packets received from the
// radio's APRS decoder to the APRS-IS network (noam.aprs2.net:14580).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum IgateState { disabled, connecting, connected, error }

class IgateService extends ChangeNotifier {
  static const String _host     = 'noam.aprs2.net';
  static const int    _port     = 14580;
  static const String _callsign = 'KF0JKE-7';
  static const String _passcode = '17323';
  static const String _vers     = 'OpenHT 0.1.0';

  Socket? _socket;
  StreamSubscription? _socketSub;
  IgateState _state = IgateState.disabled;
  String? _errorMessage;
  int _packetCount = 0;
  bool _enabled = false;
  Timer? _reconnectTimer;

  bool get enabled    => _enabled;
  IgateState get state => _state;
  String? get errorMessage => _errorMessage;
  int get packetCount  => _packetCount;

  bool get isConnected => _state == IgateState.connected;

  String get statusLabel {
    if (!_enabled) return 'Disabled';
    switch (_state) {
      case IgateState.disabled:   return 'Disabled';
      case IgateState.connecting: return 'Connecting…';
      case IgateState.connected:  return 'Connected';
      case IgateState.error:      return 'Error';
    }
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool('igate_enabled') ?? false;
    if (_enabled) {
      await connect();
    }
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('igate_enabled', value);
    _enabled = value;
    if (value) {
      await connect();
    } else {
      disconnect();
    }
    notifyListeners();
  }

  Future<void> connect() async {
    if (_state == IgateState.connected || _state == IgateState.connecting) return;
    _reconnectTimer?.cancel();
    _setState(IgateState.connecting);

    try {
      _socket = await Socket.connect(_host, _port)
          .timeout(const Duration(seconds: 10));
      _socket!.encoding = utf8;

      // Catch done-future error to prevent unhandled SocketException on abrupt disconnect.
      _socket!.done.catchError((e) {
        debugPrint('IGate: Socket done error (handled) — $e');
      });

      final login = 'user $_callsign pass $_passcode vers $_vers\r\n';
      _socket!.write(login);
      debugPrint('IGate: → $login');

      _socketSub = _socket!
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) => debugPrint('IGate: ← $line'),
        onError: (e) {
          _errorMessage = e.toString();
          _setState(IgateState.error);
          _scheduleReconnect();
        },
        onDone: () {
          if (_enabled) {
            _setState(IgateState.connecting);
            _scheduleReconnect();
          }
        },
        cancelOnError: true,
      );

      _setState(IgateState.connected);
    } catch (e) {
      debugPrint('IGate: Connection failed — $e');
      _errorMessage = e.toString();
      _setState(IgateState.error);
      _scheduleReconnect();
    }
  }

  /// Forward a raw APRS packet string to APRS-IS.
  void forwardPacket(String rawPacket) {
    if (!isConnected) return;
    final line = rawPacket.endsWith('\r\n') ? rawPacket : '$rawPacket\r\n';
    _socket?.write(line);
    _packetCount++;
    debugPrint('IGate: forwarded packet #$_packetCount');
    notifyListeners();
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _socketSub?.cancel();
    _socket?.destroy();
    _socket = null;
    _setState(IgateState.disabled);
  }

  void _scheduleReconnect() {
    if (!_enabled) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 30), () {
      if (_enabled && _state != IgateState.connected) {
        connect();
      }
    });
  }

  void _setState(IgateState s) {
    _state = s;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
