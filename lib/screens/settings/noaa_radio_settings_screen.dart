import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../bluetooth/radio_service.dart';
import '../../services/noaa_service.dart';

/// wxMode enum from the vendor `R.array.wx_modes` = [off, monitor, alert] (2-bit).
const _wxModes = <(int, String, String)>[
  (0, 'Off', 'Weather radio off'),
  (1, 'Monitor', 'Continuously receive the selected NOAA weather channel'),
  (2, 'Alert', 'Silently watch the channel for SAME weather alerts; sounds on alert'),
];

String _wxModeDesc(int mode) =>
    _wxModes.firstWhere((m) => m.$1 == mode, orElse: () => _wxModes[0]).$3;

/// Consolidated NOAA / weather-monitoring settings:
///   • Native firmware WX mode + NOAA channel (Settings.wxMode / noaaCh)
///   • Weather Alert Notifications (NWS/SAME polling)
///   • NWR Auto-Monitor (tune Band B to nearest weather station)
class NoaaRadioSettingsScreen extends StatefulWidget {
  const NoaaRadioSettingsScreen({super.key});

  @override
  State<NoaaRadioSettingsScreen> createState() =>
      _NoaaRadioSettingsScreenState();
}

class _NoaaRadioSettingsScreenState extends State<NoaaRadioSettingsScreen> {
  bool _weatherAlerts = false;
  bool _nwrMonitor = false;
  String _sameCode = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _weatherAlerts = prefs.getBool('weather_alerts_enabled') ?? false;
      _nwrMonitor = prefs.getBool('nwr_monitor_enabled') ?? false;
      _sameCode = prefs.getString('same_code') ?? '';
    });
  }

  Future<void> _setWeatherAlerts(bool v) async {
    final noaa = context.read<NoaaService>();
    if (v) await Permission.notification.request();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('weather_alerts_enabled', v);
    if (!mounted) return;
    setState(() => _weatherAlerts = v);
    if (v) {
      noaa.startPolling(sameCode: _sameCode.isEmpty ? null : _sameCode);
    } else {
      noaa.stopPolling();
    }
  }

  Future<void> _setNwrMonitor(bool v) async {
    final radio = context.read<RadioService>();
    final noaa = context.read<NoaaService>();
    final messenger = ScaffoldMessenger.of(context);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('nwr_monitor_enabled', v);
    if (!mounted) return;
    setState(() => _nwrMonitor = v);
    if (!v || !radio.isConnected || noaa.stations.isEmpty) return;
    final station = noaa.stations.first;
    final ok = await radio.tuneBandB(station.frequency);
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(ok
          ? 'Band B → ${station.callSign} ${station.displayFreq}'
          : 'Band B tune failed: ${radio.errorMessage}'),
      backgroundColor: ok ? Colors.blue[700] : Colors.red[700],
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final radio = context.watch<RadioService>();
    final noaa = context.watch<NoaaService>();
    final connected = radio.isConnected;
    final nearest = noaa.stations.isNotEmpty ? noaa.stations.first : null;
    return Scaffold(
      appBar: AppBar(title: const Text('NOAA Radio Settings')),
      body: ListView(
        children: [
          // ─── Native firmware weather mode ───
          const _Header('Weather Radio (on-radio)'),
          ListTile(
            leading: Icon(Icons.radio,
                color: radio.wxMode != 0 ? Colors.lightBlue : Colors.grey),
            title: const Text('WX mode'),
            subtitle: Text(_wxModeDesc(radio.wxMode)),
            trailing: DropdownButton<int>(
              value: radio.wxMode.clamp(0, _wxModes.length - 1),
              items: [
                for (final m in _wxModes)
                  DropdownMenuItem(value: m.$1, child: Text(m.$2)),
              ],
              onChanged:
                  connected ? (v) { if (v != null) radio.setWxMode(v); } : null,
            ),
          ),
          ListTile(
            enabled: connected,
            title: const Text('WX channel'),
            subtitle: const Text('NOAA weather frequency to receive/monitor'),
            trailing: DropdownButton<int>(
              value: radio.noaaChannel.clamp(0, kNoaaChannels.length - 1),
              items: [
                for (int i = 0; i < kNoaaChannels.length; i++)
                  DropdownMenuItem(
                    value: i,
                    child: Text(
                        '${kNoaaChannels[i].$1}  ${kNoaaChannels[i].$2.toStringAsFixed(3)}'),
                  ),
              ],
              onChanged: connected
                  ? (v) { if (v != null) radio.setNoaaChannel(v); }
                  : null,
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
                'Tip: the radio\'s front-panel "WX Scan" sweeps the NOAA channels '
                'to find the strongest station and sets the WX channel above.',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
          ),
          const Divider(),

          // ─── App-side weather alerts + auto-monitor ───
          const _Header('Alerts & Monitoring'),
          SwitchListTile(
            secondary: Icon(Icons.notifications_active,
                color: _weatherAlerts ? Colors.orange : Colors.grey),
            title: const Text('Weather Alert Notifications'),
            subtitle: Text(_sameCode.isEmpty
                ? 'NWS alerts (unfiltered — set a SAME code in APRS/Station identity)'
                : 'NWS alerts filtered to SAME $_sameCode'),
            value: _weatherAlerts,
            onChanged: _setWeatherAlerts,
          ),
          SwitchListTile(
            secondary: Icon(Icons.sensors,
                color: (_nwrMonitor && connected) ? Colors.blue : Colors.grey),
            title: const Text('NWR Auto-Monitor'),
            subtitle: Text(!connected
                ? 'Connect the radio to enable'
                : _nwrMonitor && nearest != null
                    ? 'Band B → ${nearest.callSign} ${nearest.displayFreq}'
                    : 'Tune Band B to the nearest NWR station'),
            value: _nwrMonitor && connected,
            onChanged: connected ? _setNwrMonitor : null,
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text,
            style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold)),
      );
}
