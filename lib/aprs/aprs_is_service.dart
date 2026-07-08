// lib/aprs/aprs_is_service.dart
// APRS-IS TCP connection — connects to a filtered APRS-IS server and
// subscribes to a position-filtered packet stream, feeding AprsService.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AprsIsState { disconnected, connecting, connected, error }

class AprsIsService extends ChangeNotifier {
  static const int    _port       = 14580;
  static const String _appName    = 'OpenHT';
  static const String _appVersion = '0.1.0';

  Socket? _socket;
  StreamSubscription? _sub;
  AprsIsState _state = AprsIsState.disconnected;
  String? _errorMessage;
  Timer? _reconnectTimer;
  Timer? _beaconTimer;
  DateTime? _lastBeaconAt;

  // Live phone GPS, kept fresh by the GpsService proxy in main.dart.
  double? _gpsLat;
  double? _gpsLon;

  DateTime? get lastBeaconAt => _lastBeaconAt;

  /// Called by the provider wiring whenever GpsService updates.
  void updateGps(double? lat, double? lon) {
    _gpsLat = lat;
    _gpsLon = lon;
  }

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
  /// Reads callsign/passcode/server/filter from SharedPreferences.
  /// [lat]/[lon] — current position for building the range filter.
  Future<void> connect({double? lat, double? lon}) async {
    if (_state == AprsIsState.connected || _state == AprsIsState.connecting) return;

    _setState(AprsIsState.connecting);
    _reconnectTimer?.cancel();

    final prefs    = await SharedPreferences.getInstance();
    final callsign = prefs.getString('callsign') ?? '';
    final ssid     = prefs.getInt('aprs_ssid') ?? 7;
    final passcode = prefs.getInt('aprs_passcode') ?? -1;
    final server   = prefs.getString('aprs_server') ?? 'rotate.aprs2.net';
    final filterKm = prefs.getInt('aprs_filter_km') ?? 200;

    if (callsign.isEmpty) {
      debugPrint('AprsIS: No callsign configured — set it in APRS Settings');
      _errorMessage = 'No callsign — configure in Settings → APRS';
      _setState(AprsIsState.error);
      return;
    }

    final sourceAddr = '$callsign-$ssid';
    final passStr    = passcode == -1 ? '-1' : '$passcode';

    // Build position filter; fall back to center of USA if no GPS
    final filterLat = lat ?? 39.83;
    final filterLon = lon ?? -98.58;
    _lastLat = filterLat;
    _lastLon = filterLon;
    final filter    = 'r/${filterLat.toStringAsFixed(2)}/${filterLon.toStringAsFixed(2)}/$filterKm';

    try {
      _socket = await Socket.connect(server, _port)
          .timeout(const Duration(seconds: 10));

      _socket!.encoding = utf8;

      // Catch the socket's done-future error to prevent unhandled exceptions
      // when the server closes the connection abruptly (errno 103 ECONNABORTED).
      _socket!.done.catchError((e) {
        debugPrint('AprsIS: Socket done error (handled) — $e');
      });

      final loginLine = 'user $sourceAddr pass $passStr '
          'vers $_appName $_appVersion filter $filter\r\n';
      _socket!.write(loginLine);
      debugPrint('AprsIS: → $loginLine');

      _setState(AprsIsState.connected);

      // First beacon shortly after login so the server has processed logresp;
      // subsequent beacons follow the configured interval.
      _scheduleNextBeacon(delay: const Duration(seconds: 15));

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
    _beaconTimer?.cancel();
    _sub?.cancel();
    _socket?.destroy();
    _socket = null;
    _setState(AprsIsState.disconnected);
  }

  // ── Position beaconing ─────────────────────────────────────────────────────
  // Fixed-interval position reports to APRS-IS, driven by the Beacon settings
  // (aprs_beacon_enabled / aprs_beacon_interval_min / aprs_beacon_comment).
  // Prefs are re-read every cycle so settings changes apply without reconnect.

  void _scheduleNextBeacon({Duration? delay}) async {
    _beaconTimer?.cancel();
    if (!isConnected) return;
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('aprs_beacon_enabled') ?? false)) {
      // Disabled — re-check periodically so enabling it takes effect live.
      _beaconTimer = Timer(const Duration(seconds: 30), _scheduleNextBeacon);
      return;
    }
    final interval =
        Duration(minutes: prefs.getInt('aprs_beacon_interval_min') ?? 5);
    _beaconTimer = Timer(delay ?? interval, () async {
      await _sendBeacon();
      _scheduleNextBeacon();
    });
  }

  /// Send one position beacon immediately (also used by the beacon timer).
  Future<void> beaconNow() => _sendBeacon();

  Future<void> _sendBeacon() async {
    if (!isConnected) return;
    final lat = _gpsLat, lon = _gpsLon;
    if (lat == null || lon == null) {
      debugPrint('AprsIS: beacon skipped — no GPS fix');
      return;
    }
    final prefs    = await SharedPreferences.getInstance();
    final callsign = prefs.getString('callsign') ?? '';
    if (callsign.isEmpty) return;
    final ssid    = prefs.getInt('aprs_ssid') ?? 7;
    final table   = prefs.getString('aprs_symbol_table') ?? '/';
    final symbol  = prefs.getString('aprs_symbol_char') ?? '>';
    final comment = prefs.getString('aprs_beacon_comment') ?? '';

    // Uncompressed position report, no timestamp, messaging-capable ('=').
    // APZOHT: APZ* is the experimental tocall range per the APRS spec.
    final line = '$callsign-$ssid>APZOHT,TCPIP*:'
        '=${_aprsLat(lat)}$table${_aprsLon(lon)}$symbol$comment';
    sendLine(line);
    _lastBeaconAt = DateTime.now();
    notifyListeners();
  }

  // DDMM.mmN / DDDMM.mmW per APRS spec §6 (uncompressed position format).
  static String _aprsLat(double lat) {
    final hemi = lat >= 0 ? 'N' : 'S';
    var deg = lat.abs().floor();
    var min = (lat.abs() - deg) * 60;
    if (min >= 59.995) { deg += 1; min = 0; }
    return '${deg.toString().padLeft(2, '0')}'
        '${min.toStringAsFixed(2).padLeft(5, '0')}$hemi';
  }

  static String _aprsLon(double lon) {
    final hemi = lon >= 0 ? 'E' : 'W';
    var deg = lon.abs().floor();
    var min = (lon.abs() - deg) * 60;
    if (min >= 59.995) { deg += 1; min = 0; }
    return '${deg.toString().padLeft(3, '0')}'
        '${min.toStringAsFixed(2).padLeft(5, '0')}$hemi';
  }

  double? _lastLat;
  double? _lastLon;

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 30), () {
      if (_state != AprsIsState.connected) {
        debugPrint('AprsIS: Reconnecting…');
        connect(lat: _lastLat, lon: _lastLon);
      }
    });
  }

  void _setState(AprsIsState s) {
    _state = s;
    notifyListeners();
  }

  @override
  void dispose() {
    _beaconTimer?.cancel();
    disconnect();
    _packetController.close();
    super.dispose();
  }
}
