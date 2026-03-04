// lib/services/aprs_auth_service.dart
// APRS message authentication via HMAC-SHA256 pre-shared keys
// Appends an 8-hex-char tag: {XXXXXXXX} to outgoing messages.
// Verifies the same tag on incoming messages from trusted stations.
//
// LEGAL NOTE: This is NOT encryption — it is message authentication.
// Amateur radio regulations prohibit obscuring the meaning of transmissions.
// The message text is fully human-readable; only the auth tag is added.

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// ─── Auth result ──────────────────────────────────────────────────────────────
enum AprsAuthResult { verified, failed, unknown }

// ─── Trusted station model ────────────────────────────────────────────────────
class TrustedStation {
  final String callsign; // e.g. "W0ABC-9"
  final DateTime addedAt;

  const TrustedStation({required this.callsign, required this.addedAt});

  Map<String, dynamic> toJson() => {
        'callsign': callsign,
        'addedAt': addedAt.toIso8601String(),
      };

  factory TrustedStation.fromJson(Map<String, dynamic> j) => TrustedStation(
        callsign: j['callsign'] as String,
        addedAt: DateTime.parse(j['addedAt'] as String),
      );
}

// ─── Service ──────────────────────────────────────────────────────────────────
class AprsAuthService extends ChangeNotifier {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _masterKeyId = 'aprs_auth_master_key';
  static const _stationPrefix = 'aprs_auth_station_';
  static const _enabledKey = 'aprs_auth_enabled';

  bool _enabled = false;
  final List<TrustedStation> _trustedStations = [];

  bool get enabled => _enabled;
  List<TrustedStation> get trustedStations => List.unmodifiable(_trustedStations);

  // ── Init ───────────────────────────────────────────────────────────────────
  Future<void> load() async {
    final enabledStr = await _storage.read(key: _enabledKey);
    _enabled = enabledStr == 'true';

    _trustedStations.clear();
    final all = await _storage.readAll();
    for (final entry in all.entries) {
      if (!entry.key.startsWith(_stationPrefix)) continue;
      try {
        final json = jsonDecode(entry.value) as Map<String, dynamic>;
        _trustedStations.add(TrustedStation.fromJson(json));
      } catch (_) {}
    }
    _trustedStations.sort((a, b) => a.callsign.compareTo(b.callsign));
    notifyListeners();
  }

  // ── Enable / disable ───────────────────────────────────────────────────────
  Future<void> setEnabled(bool value) async {
    _enabled = value;
    await _storage.write(key: _enabledKey, value: value.toString());
    notifyListeners();
  }

  // ── Master key management ──────────────────────────────────────────────────
  /// Returns true if a master key is stored.
  Future<bool> hasMasterKey() async {
    final k = await _storage.read(key: _masterKeyId);
    return k != null && k.isNotEmpty;
  }

  /// Store a new master pre-shared key (raw text, stored securely).
  Future<void> setMasterKey(String key) async {
    await _storage.write(key: _masterKeyId, value: key);
  }

  Future<void> deleteMasterKey() async {
    await _storage.delete(key: _masterKeyId);
  }

  // ── Per-station key management ─────────────────────────────────────────────
  String _stationKeyId(String callsign) =>
      '${_stationPrefix}key_${callsign.toUpperCase()}';
  String _stationMetaId(String callsign) =>
      '$_stationPrefix${callsign.toUpperCase()}';

  Future<bool> hasStationKey(String callsign) async {
    final k = await _storage.read(key: _stationKeyId(callsign));
    return k != null && k.isNotEmpty;
  }

  Future<void> addStation(String callsign, String key) async {
    final call = callsign.toUpperCase();
    await _storage.write(key: _stationKeyId(call), value: key);
    final station = TrustedStation(callsign: call, addedAt: DateTime.now());
    await _storage.write(
        key: _stationMetaId(call), value: jsonEncode(station.toJson()));
    if (!_trustedStations.any((s) => s.callsign == call)) {
      _trustedStations.add(station);
      _trustedStations.sort((a, b) => a.callsign.compareTo(b.callsign));
    }
    notifyListeners();
  }

  Future<void> removeStation(String callsign) async {
    final call = callsign.toUpperCase();
    await _storage.delete(key: _stationKeyId(call));
    await _storage.delete(key: _stationMetaId(call));
    _trustedStations.removeWhere((s) => s.callsign == call);
    notifyListeners();
  }

  // ── Passcode helpers ───────────────────────────────────────────────────────
  /// Standard APRS-IS passcode hash (public algorithm).
  static int computeAprsPasscode(String callsign) {
    final base = callsign.split('-').first.toUpperCase();
    int hash = 0x73e2;
    for (int i = 0; i < base.length; i += 2) {
      hash ^= base.codeUnitAt(i) << 8;
      if (i + 1 < base.length) hash ^= base.codeUnitAt(i + 1);
    }
    return hash & 0x7FFF;
  }

  // ── HMAC signing ───────────────────────────────────────────────────────────
  /// Sign a message body with a given key.  Returns 8-char uppercase hex tag.
  static String _computeTag(String message, String key) {
    final mac = Hmac(sha256, utf8.encode(key));
    final digest = mac.convert(utf8.encode(message));
    return digest.toString().substring(0, 8).toUpperCase();
  }

  /// Returns the message with an auth tag appended: `text {XXXXXXXX}`
  Future<String?> signMessage(String message) async {
    if (!_enabled) return message;
    final key = await _storage.read(key: _masterKeyId);
    if (key == null || key.isEmpty) return message;
    final tag = _computeTag(message, key);
    return '$message {$tag}';
  }

  /// Verify a message from a specific callsign.
  /// Returns [AprsAuthResult.verified] / [.failed] / [.unknown].
  Future<AprsAuthResult> verifyMessage(
      String callsign, String rawMessage) async {
    final tagMatch = RegExp(r'\{([0-9A-Fa-f]{8})\}$').firstMatch(rawMessage);
    if (tagMatch == null) return AprsAuthResult.unknown;

    final receivedTag = tagMatch.group(1)!.toUpperCase();
    final body = rawMessage.substring(0, tagMatch.start).trimRight();

    // Try station-specific key first, fall back to master key.
    final keys = <String?>[];
    keys.add(await _storage.read(key: _stationKeyId(callsign)));
    keys.add(await _storage.read(key: _masterKeyId));

    for (final key in keys) {
      if (key == null || key.isEmpty) continue;
      final expected = _computeTag(body, key);
      if (expected == receivedTag) return AprsAuthResult.verified;
    }
    return AprsAuthResult.failed;
  }

  /// Strip the auth tag from a raw message, returning the clean body.
  static String stripTag(String rawMessage) {
    return rawMessage
        .replaceAll(RegExp(r'\s*\{[0-9A-Fa-f]{8}\}$'), '')
        .trimRight();
  }
}
