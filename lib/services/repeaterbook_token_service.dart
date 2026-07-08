// lib/services/repeaterbook_token_service.dart
// Securely stores the user's RepeaterBook app-bound API token (rbuapp_...) and
// exposes it for API calls. The token is generated per-user from
// repeaterbook.com/user/api_apps.php once OpenHT is an approved distributed app.
//
// Access model:
//  - No token  -> Near Repeaters "Tune To" (RB Web API) is locked.
//  - Token set -> Tune To unlocked; requests send `X-RB-App-Token: <token>`.
// (The RB Connect content provider path — emergency-net plan building — does NOT
//  require this token.)

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class RepeaterBookTokenService extends ChangeNotifier {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _tokenKey = 'repeaterbook_api_token';

  /// Where users generate their app-bound token (after OpenHT is approved).
  static const apiAppsUrl = 'https://repeaterbook.com/user/api_apps.php';

  /// Attribution string to show wherever RepeaterBook data appears.
  static const attribution = 'Data courtesy of RepeaterBook.com';

  String? _token;

  /// True when a token is stored — gates RB Web API features (Tune To).
  bool get hasToken => (_token != null && _token!.isNotEmpty);

  /// The stored token, or null.
  String? get token => _token;

  /// Masked form for display (never show the full token in the UI).
  String get maskedToken {
    final t = _token;
    if (t == null || t.length < 12) return '(not set)';
    return '${t.substring(0, 10)}…${t.substring(t.length - 4)}';
  }

  Future<void> load() async {
    _token = await _storage.read(key: _tokenKey);
    notifyListeners();
  }

  Future<void> setToken(String token) async {
    final t = token.trim();
    _token = t.isEmpty ? null : t;
    if (_token == null) {
      await _storage.delete(key: _tokenKey);
    } else {
      await _storage.write(key: _tokenKey, value: _token);
    }
    notifyListeners();
  }

  Future<void> clear() async {
    _token = null;
    await _storage.delete(key: _tokenKey);
    notifyListeners();
  }

  /// Auth headers for RepeaterBook Web API calls. Empty when no token.
  Map<String, String> authHeaders() {
    final t = _token;
    if (t == null || t.isEmpty) return {};
    return {
      'X-RB-App-Token': t,
      'User-Agent': 'OpenHT (github.com/repins267/repins267-OpenHT; N0TEZ)',
    };
  }
}
