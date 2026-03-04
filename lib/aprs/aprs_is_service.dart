// lib/aprs/aprs_is_service.dart
// APRS-IS TCP connection — connects to noam.aprs2.net:14580 and
// subscribes to a position-filtered packet stream, feeding AprsService.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

enum AprsIsState { disconnected, connecting, connected, error }

class AprsIsService extends ChangeNotifier {
  static const String _host    = 'noam.aprs2.net';
  static const int    _port    = 14580;
  static const String _callsign = 'KF0JKE-7';
  static const String _passcode = '17323';
  static const String _appName  = 'OpenHT';
  static const String _appVersion = '0.1.0';

  Socket? _socket;
  StreamSubscription? _sub;
  AprsIsState _state = AprsIsState.disconnected;
  String? _errorMessage;
  Timer? _reconnectTimer;

  // Raw packet stream broadcast — AprsService subscribes to this
  final _packetController = StreamController<String>.broadcast();
  Stream<String> get packets => _packetController.stream;

  AprsIsState get state => _state;
  bool get isConnected => _state == AprsIsState.connected;
  String? get errorMessage => _errorMessage;

  String get statusLabel {
    switch (_state) {
      case AprsIsState.disconnected: return 'Disconnected';
      case AprsIsState.connecting:   return 'Connecting…';
      case AprsIsState.connected:    return 'Connected';
      case AprsIsState.error:        return 'Error';
    }
  }

  /// Connect to APRS-IS and start receiving packets.
  /// [filter] — optional server-side filter, e.g. 'r/39.8/-98.6/400'
  Future<void> connect({String? filter}) async {
    if (_state == AprsIsState.connected || _state == AprsIsState.connecting) return;

    _setState(AprsIsState.connecting);
    _reconnectTimer?.cancel();

    try {
      _socket = await Socket.connect(_host, _port)
          .timeout(const Duration(seconds: 10));

      _socket!.encoding = utf8;

      // Catch the socket's done-future error to prevent unhandled exceptions
      // when the server closes the connection abruptly (errno 103 ECONNABORTED).
      _socket!.done.catchError((e) {
        debugPrint('AprsIS: Socket done error (handled) — $e');
      });

      final loginLine = 'user $_callsign pass $_passcode '
          'vers $_appName $_appVersion'
          '${filter != null ? ' filter $filter' : ''}\r\n';
      _socket!.write(loginLine);
      debugPrint('AprsIS: → $loginLine');

      _setState(AprsIsState.connected);

      _sub = _socket!
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          debugPrint('AprsIS: ← $line');
          if (!line.startsWith('#')) {
            _packetController.add(line);
          }
        },
        onError: (e) {
          debugPrint('AprsIS: Stream error — $e');
          _errorMessage = e.toString();
          _setState(AprsIsState.error);
          _scheduleReconnect();
        },
        onDone: () {
          debugPrint('AprsIS: Connection closed');
          if (_state == AprsIsState.connected) {
            _setState(AprsIsState.disconnected);
            _scheduleReconnect();
          }
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('AprsIS: Connection failed — $e');
      _errorMessage = e.toString();
      _setState(AprsIsState.error);
      _scheduleReconnect();
    }
  }

  /// Send a raw APRS-IS line (e.g. a beacon or iGate forward).
  void sendLine(String line) {
    if (!isConnected) return;
    final msg = line.endsWith('\r\n') ? line : '$line\r\n';
    _socket?.write(msg);
    debugPrint('AprsIS: → $msg');
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _sub?.cancel();
    _socket?.destroy();
    _socket = null;
    _setState(AprsIsState.disconnected);
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 30), () {
      if (_state != AprsIsState.connected) {
        debugPrint('AprsIS: Reconnecting…');
        connect();
      }
    });
  }

  void _setState(AprsIsState s) {
    _state = s;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    _packetController.close();
    super.dispose();
  }
}
