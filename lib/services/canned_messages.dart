import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistent store of pre-saved APRS text messages ("canned messages"), so you
/// can tap-to-send common phrases instead of thumb-typing them each time —
/// mirroring the vendor app's saved-message feature.
class CannedMessages {
  static const _key = 'aprs_canned_messages';

  /// Sensible starter set on first run (user can edit/delete freely).
  static const List<String> defaults = [
    'QSL, thanks',
    'On my way',
    'At the site',
    'Running late',
    'Need assistance',
    'Monitoring 146.520',
  ];

  /// Loads the saved list, seeding [defaults] the first time.
  static Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) {
      await save(defaults);
      return List.of(defaults);
    }
    try {
      return (jsonDecode(raw) as List).map((e) => e.toString()).toList();
    } catch (_) {
      return List.of(defaults);
    }
  }

  static Future<void> save(List<String> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(list));
  }

  /// Adds [text] if non-empty and not already present; returns the new list.
  static Future<List<String>> add(String text) async {
    final t = text.trim();
    final list = await load();
    if (t.isNotEmpty && !list.contains(t)) {
      list.add(t);
      await save(list);
    }
    return list;
  }

  static Future<List<String>> removeAt(int index) async {
    final list = await load();
    if (index >= 0 && index < list.length) {
      list.removeAt(index);
      await save(list);
    }
    return list;
  }
}
