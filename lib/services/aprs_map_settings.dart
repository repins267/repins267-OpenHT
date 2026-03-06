// lib/services/aprs_map_settings.dart
// ChangeNotifier that holds APRS map display preferences.
// Settings screen calls load() after saving so the map reacts immediately.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AprsMapSettings extends ChangeNotifier {
  bool   showAprs   = true;
  bool   showIs     = true;
  bool   showRf     = true;
  bool   directOnly = false;
  String maxAge     = 'all';
  bool   isEnabled  = true;
  bool   rfEnabled  = false;

  AprsMapSettings() {
    load();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    showAprs   = prefs.getBool('aprs_map_show_aprs')    ?? true;
    showIs     = prefs.getBool('aprs_map_show_is')      ?? true;
    showRf     = prefs.getBool('aprs_map_show_rf')      ?? true;
    directOnly = prefs.getBool('aprs_map_direct_only')  ?? false;
    maxAge     = prefs.getString('aprs_map_max_age')    ?? 'all';
    isEnabled  = prefs.getBool('aprs_is_enabled')       ?? true;
    rfEnabled  = prefs.getBool('aprs_rf_enabled')       ?? false;
    notifyListeners();
  }
}
