// lib/screens/weather/weather_layer_drawer.dart
// Left-side layer toggle drawer for the Weather tab.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Keys for SharedPreferences + layer IDs used by WeatherScreen
class WeatherLayers {
  static const warnings    = 'wx_layer_warnings';
  static const watches     = 'wx_layer_watches';
  static const statements  = 'wx_layer_statements';
  static const discussions = 'wx_layer_discussions';
  static const outlooks    = 'wx_layer_outlooks';
  static const mping       = 'wx_layer_mping';
  static const lsr         = 'wx_layer_lsr';
  static const spotter     = 'wx_layer_spotter';

  static const all = [
    warnings,
    watches,
    statements,
    discussions,
    outlooks,
    mping,
    lsr,
    spotter,
  ];
}

class WeatherLayerState extends ChangeNotifier {
  final Map<String, bool> _layers = {
    WeatherLayers.warnings:    true,
    WeatherLayers.watches:     true,
    WeatherLayers.statements:  true,
    WeatherLayers.discussions: true,
    WeatherLayers.outlooks:    true,
    WeatherLayers.mping:       true,
    WeatherLayers.lsr:         true,
    WeatherLayers.spotter:     true,
  };
  bool _loaded = false;

  bool get(String key) => _layers[key] ?? true;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    for (final key in WeatherLayers.all) {
      _layers[key] = prefs.getBool(key) ?? (_layers[key] ?? true);
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> set(String key, bool value) async {
    _layers[key] = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    notifyListeners();
  }
}

class WeatherLayerDrawer extends StatelessWidget {
  final WeatherLayerState state;
  const WeatherLayerDrawer({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final layers = [
      (
        WeatherLayers.warnings,
        Icons.warning_rounded,
        Colors.red,
        'NWS Warnings',
      ),
      (
        WeatherLayers.watches,
        Icons.watch_later_outlined,
        Colors.orange,
        'NWS Watches',
      ),
      (
        WeatherLayers.statements,
        Icons.info_outline,
        Colors.yellow,
        'NWS Statements',
      ),
      (
        WeatherLayers.discussions,
        Icons.article_outlined,
        Colors.blue,
        'SPC Discussions',
      ),
      (
        WeatherLayers.outlooks,
        Icons.cloud_outlined,
        Colors.purple,
        'SPC Outlooks',
      ),
      (
        WeatherLayers.mping,
        Icons.grain,
        Colors.green,
        'mPING Reports',
      ),
      (
        WeatherLayers.lsr,
        Icons.bolt,
        Colors.amber,
        'Storm Reports (LSR)',
      ),
      (
        WeatherLayers.spotter,
        Icons.person_pin_circle_outlined,
        Colors.orange,
        'Storm Spotters',
      ),
    ];

    return Drawer(
      backgroundColor: Colors.grey[900],
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'WEATHER LAYERS',
                style: TextStyle(
                  color: Colors.blue[400],
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            const Divider(color: Colors.white12),
            Expanded(
              child: ListenableBuilder(
                listenable: state,
                builder: (_, __) => ListView(
                  children: layers.map((item) {
                    final (key, icon, color, label) = item;
                    return SwitchListTile(
                      secondary: Icon(
                        icon,
                        color: state.get(key) ? color : Colors.grey,
                        size: 22,
                      ),
                      title: Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                      dense: true,
                      value: state.get(key),
                      onChanged: (v) => state.set(key, v),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
