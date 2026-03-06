// lib/screens/settings/settings_screen.dart
// Radio connection and app settings

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../bluetooth/radio_service.dart';
import '../../services/freq_plan_service.dart';
import '../../services/noaa_service.dart';
import 'tracks_screen.dart';
import 'aprs_settings_screen.dart';
import 'auth_settings_screen.dart';
import 'channel_manager_screen.dart';
import 'js8call_settings_screen.dart';
import 'map_cache_settings_screen.dart';
import 'radio_debug_screen.dart';

// Known Benshi-protocol radio name prefixes and Vero OUI
bool _isLikelyRadio(device) {
  final name = ((device.name ?? '') as String).toUpperCase();
  final mac  = (device.address as String).toUpperCase();
  if (name.startsWith('VR-N'))   return true; // Vero VR-N series
  if (name.startsWith('UV-PRO')) return true; // BTech UV-Pro (same protocol)
  if (name.startsWith('VR-N76')) return true; // exact default name
  if (mac.startsWith('38:D2:00')) return true; // Vero/VGC OUI
  return false;
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isScanning = false;
  bool _showAllDevices = false;

  // Station Identity
  String _callsign = '';
  String _sameCode = '';

  // Frequency Plans
  FreqPlan? _freqPlan;
  bool _planWriting = false;
  int  _planWritten = 0;

  // Weather Monitoring
  bool _weatherAlertsEnabled = false;
  bool _nwrMonitorEnabled    = false;

  // APRS
  bool _aprsReceive       = true;
  bool _aprsBeaconEnabled = false;
  int  _beaconIntervalMin = 5;
  bool _igateEnabled      = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _loadFreqPlan();
  }

  Future<void> _loadFreqPlan() async {
    final plan = await FreqPlanService.loadPlan('ppraa_el_paso');
    if (mounted) setState(() => _freqPlan = plan);
  }

  Future<void> _loadPrefs() async {
    final noaa  = context.read<NoaaService>(); // capture before await
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final weatherEnabled = prefs.getBool('weather_alerts_enabled') ?? false;
    final sameCode = prefs.getString('same_code') ?? '';
    setState(() {
      _callsign           = prefs.getString('callsign')          ?? '';
      _sameCode           = sameCode;
      _weatherAlertsEnabled = weatherEnabled;
      _nwrMonitorEnabled  = prefs.getBool('nwr_monitor_enabled') ?? false;
      _aprsReceive        = prefs.getBool('aprs_is_enabled')      ?? true;
      _aprsBeaconEnabled  = prefs.getBool('aprs_beacon_enabled')  ?? false;
      _beaconIntervalMin  = prefs.getInt('aprs_beacon_interval_min') ?? 5;
      _igateEnabled       = prefs.getBool('igate_enabled')        ?? false;
    });

    // Restart polling if it was previously enabled
    if (weatherEnabled) {
      noaa.startPolling(sameCode: sameCode.isEmpty ? null : sameCode);
    }
  }

  @override
  Widget build(BuildContext context) {
    final radio = context.watch<RadioService>();
    final noaa  = context.watch<NoaaService>();
    final nearestStation = noaa.stations.isNotEmpty ? noaa.stations.first : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [

          // ─── Radio Connection ────────────────────────
          _SectionHeader('Radio Connection'),
          if (radio.isConnected)
            ListTile(
              leading: const Icon(Icons.bluetooth_connected, color: Colors.blue),
              title: const Text('Radio connected', style: TextStyle(color: Colors.white)),
              subtitle: Text(
                'Battery: ${radio.batteryPercent ?? "—"}%',
                style: const TextStyle(color: Colors.white54),
              ),
              trailing: TextButton(
                onPressed: radio.disconnect,
                child: const Text('Disconnect', style: TextStyle(color: Colors.red)),
              ),
            )
          else ...[
            ListTile(
              leading: const Icon(Icons.bluetooth_searching, color: Colors.grey),
              title: const Text('No radio connected', style: TextStyle(color: Colors.white54)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ElevatedButton.icon(
                icon: _isScanning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.bluetooth_searching),
                label: Text(_isScanning ? 'Scanning...' : 'Scan for Radio'),
                onPressed: _isScanning ? null : () => _scanAndConnect(radio),
              ),
            ),
          ],

          // ─── Paired Devices List ─────────────────────
          if (radio.pairedDevices.isNotEmpty) ...[
            _SectionHeader(
              _showAllDevices ? 'All Paired Devices' : 'Compatible Radios',
            ),
            ...(_showAllDevices
                    ? radio.pairedDevices
                    : radio.pairedDevices.where(_isLikelyRadio).toList())
                .map((device) => ListTile(
                      leading: const Icon(Icons.radio, color: Colors.blue),
                      title: Text(device.name ?? 'Unknown',
                          style: const TextStyle(color: Colors.white)),
                      subtitle: Text(device.address,
                          style: const TextStyle(color: Colors.white38, fontSize: 11)),
                      trailing: ElevatedButton(
                        onPressed:
                            radio.connectionState == RadioConnectionState.connecting
                                ? null
                                : () => radio.connect(device),
                        child: const Text('Connect'),
                      ),
                    )),
            if (!_showAllDevices &&
                radio.pairedDevices.where(_isLikelyRadio).length <
                    radio.pairedDevices.length)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    Text(
                      '${radio.pairedDevices.length - radio.pairedDevices.where(_isLikelyRadio).length} non-radio device(s) hidden',
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => setState(() => _showAllDevices = true),
                      child: const Text('Show all', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
              )
            else if (_showAllDevices)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: TextButton(
                  onPressed: () => setState(() => _showAllDevices = false),
                  child: const Text('Show radios only', style: TextStyle(fontSize: 11)),
                ),
              ),
          ],

          // ─── Station Identity ─────────────────────────
          _SectionHeader('Station Identity'),
          ListTile(
            leading: const Icon(Icons.badge_outlined, color: Colors.green),
            title: const Text('Callsign', style: TextStyle(color: Colors.white)),
            subtitle: Text(
              _callsign.isEmpty ? 'Not set' : _callsign,
              style: TextStyle(
                color: _callsign.isEmpty ? Colors.white38 : Colors.green[300],
              ),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
            onTap: () => _editCallsign(context),
          ),
          ListTile(
            leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
            title: const Text('SAME Code', style: TextStyle(color: Colors.white)),
            subtitle: Text(
              _sameCode.isEmpty ? 'Not set — alerts unfiltered' : _sameCode,
              style: TextStyle(
                color: _sameCode.isEmpty ? Colors.white38 : Colors.orange[300],
              ),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
            onTap: () => _editSameCode(context),
          ),

          // ─── Weather Monitoring ───────────────────────
          _SectionHeader('Weather Monitoring'),
          SwitchListTile(
            secondary: Icon(
              Icons.notifications_active_outlined,
              color: _weatherAlertsEnabled ? Colors.orange : Colors.grey,
            ),
            title: const Text('Weather Alert Notifications',
                style: TextStyle(color: Colors.white)),
            subtitle: Text(
              _weatherAlertsEnabled
                  ? 'Notifying on Extreme/Severe alerts · every 5 min'
                  : 'Get notified of tornado and severe thunderstorm warnings',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            value: _weatherAlertsEnabled,
            onChanged: _setWeatherAlertsEnabled,
          ),
          SwitchListTile(
            secondary: Icon(
              Icons.radio_outlined,
              color: (_nwrMonitorEnabled && radio.isConnected) ? Colors.blue : Colors.grey,
            ),
            title: const Text('NWR Auto-Monitor',
                style: TextStyle(color: Colors.white)),
            subtitle: Text(
              !radio.isConnected
                  ? 'Connect radio to use'
                  : _nwrMonitorEnabled && nearestStation != null
                      ? 'Band B → ${nearestStation.callSign} ${nearestStation.displayFreq}'
                      : 'Tunes Band B to the nearest NOAA weather station',
              style: TextStyle(
                color: !radio.isConnected ? Colors.white38 : Colors.white54,
                fontSize: 12,
              ),
            ),
            value: _nwrMonitorEnabled && radio.isConnected,
            onChanged: radio.isConnected ? _setNwrMonitorEnabled : null,
          ),

          // ─── APRS ─────────────────────────────────────
          _SectionHeader('APRS'),
          SwitchListTile(
            secondary: Icon(
              Icons.cloud_outlined,
              color: _aprsReceive ? Colors.blue : Colors.grey,
            ),
            title: const Text('Receive APRS', style: TextStyle(color: Colors.white)),
            subtitle: Text(
              _aprsReceive
                  ? 'Stations visible on map via APRS-IS'
                  : 'APRS-IS receive disabled — map will be empty',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            value: _aprsReceive,
            onChanged: _setAprsReceive,
          ),
          if (_aprsReceive) ...[
            SwitchListTile(
              secondary: Icon(
                Icons.wifi_tethering,
                color: _aprsBeaconEnabled ? Colors.green : Colors.grey,
              ),
              title: const Text('Beacon', style: TextStyle(color: Colors.white)),
              subtitle: Text(
                _callsign.isEmpty
                    ? 'Set callsign first'
                    : _aprsBeaconEnabled
                        ? 'Transmitting $_callsign every $_beaconIntervalMin min'
                        : 'Your position is not being transmitted',
                style: TextStyle(
                  color: _callsign.isEmpty ? Colors.red[400] : Colors.white54,
                  fontSize: 12,
                ),
              ),
              value: _aprsBeaconEnabled,
              onChanged: _callsign.isEmpty ? null : _setAprsBeaconEnabled,
            ),
            SwitchListTile(
              secondary: Icon(
                Icons.router_outlined,
                color: _igateEnabled ? Colors.green : Colors.grey,
              ),
              title: const Text('iGate', style: TextStyle(color: Colors.white)),
              subtitle: Text(
                _igateEnabled
                    ? 'Received RF packets forwarded to APRS-IS'
                    : 'RF packets stay local — not uploaded to internet',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              value: _igateEnabled,
              onChanged: _setIgateEnabled,
            ),
          ],
          ListTile(
            leading: const Icon(Icons.settings_input_antenna, color: Colors.green),
            title: const Text('Advanced APRS Settings',
                style: TextStyle(color: Colors.white)),
            subtitle: const Text('Station, path, symbol, iGate, digipeater',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AprsSettingsScreen())),
          ),

          // ─── Frequency Plans ─────────────────────────
          _SectionHeader('Frequency Plans'),
          if (_freqPlan == null)
            const ListTile(
              leading: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              title: Text('Loading plans…',
                  style: TextStyle(color: Colors.white54, fontSize: 13)),
            )
          else
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              color: Colors.grey[850],
              child: ListTile(
                leading: const Icon(Icons.folder_open_outlined,
                    color: Colors.teal),
                title: Text(_freqPlan!.name,
                    style: const TextStyle(color: Colors.white)),
                subtitle: Text(
                  '${_freqPlan!.channels.length} channels · FIPS ${_freqPlan!.fips}\n'
                  'Writes PPARES · SKYWARN · RACES channels to Group 3 slots 0–7',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                isThreeLine: true,
                trailing: _planWriting
                    ? SizedBox(
                        width: 64,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$_planWritten/${_freqPlan!.channels.length}',
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 10),
                            ),
                          ],
                        ),
                      )
                    : ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              radio.isConnected ? Colors.teal[700] : null,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          minimumSize: Size.zero,
                        ),
                        onPressed:
                            radio.isConnected ? _writePlanToGroup3 : null,
                        child: const Text('Write\nGroup 3',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11)),
                      ),
              ),
            ),

          // ─── Channels & Radio ─────────────────────────
          _SectionHeader('Channels & Radio'),
          ListTile(
            leading: const Icon(Icons.list_alt, color: Colors.blue),
            title: const Text('Channel & Group Manager',
                style: TextStyle(color: Colors.white)),
            subtitle: const Text('Import/export CSV, sync to radio',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ChannelManagerScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.verified_user_outlined, color: Colors.green),
            title: const Text('Message Authentication',
                style: TextStyle(color: Colors.white)),
            subtitle: const Text('HMAC pre-shared keys for APRS messages',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AuthSettingsScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.waves_outlined, color: Colors.cyan),
            title: const Text('JS8Call Settings',
                style: TextStyle(color: Colors.white)),
            subtitle: const Text('FM digital text mode (DSP stub)',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const Js8CallSettingsScreen())),
          ),

          // ─── Track Recording ─────────────────────────
          _SectionHeader('Track Recording'),
          ListTile(
            leading: const Icon(Icons.route, color: Colors.green),
            title: const Text('View Saved Tracks',
                style: TextStyle(color: Colors.white)),
            subtitle: const Text('Browse, share, or delete GPX files',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const TracksScreen())),
          ),

          // ─── Map ─────────────────────────────────────
          _SectionHeader('Map'),
          ListTile(
            leading: const Icon(Icons.map_outlined, color: Colors.teal),
            title: const Text('Map Tile Cache',
                style: TextStyle(color: Colors.white)),
            subtitle: const Text('View cache size, clear tiles by source',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const MapCacheSettingsScreen())),
          ),

          // ─── Developer ───────────────────────────────
          _SectionHeader('Developer'),
          ListTile(
            leading: const Icon(Icons.bug_report_outlined, color: Colors.redAccent),
            title: const Text('Radio Protocol Debug',
                style: TextStyle(color: Colors.white)),
            subtitle: const Text('Raw HEX terminal for packet analysis',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const RadioDebugScreen())),
          ),

          // ─── About ───────────────────────────────────
          _SectionHeader('About'),
          ListTile(
            leading: const Icon(Icons.info_outline, color: Colors.white38),
            title: const Text('About OpenHT', style: TextStyle(color: Colors.white)),
            subtitle: const Text('v0.1.0 • github.com/repins267/OpenHT',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
            onTap: () => _showAbout(context),
          ),

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  // ─── Actions ─────────────────────────────────────────────────────────────

  Future<void> _scanAndConnect(RadioService radio) async {
    setState(() => _isScanning = true);
    await radio.scanPairedDevices();
    setState(() => _isScanning = false);
  }

  Future<void> _writePlanToGroup3() async {
    if (_freqPlan == null) return;
    final radio     = context.read<RadioService>();
    final messenger = ScaffoldMessenger.of(context);
    if (!radio.isConnected) return;

    final total = _freqPlan!.channels.length;
    setState(() {
      _planWriting = true;
      _planWritten = 0;
    });

    // Group 3 = groupIndex 2 (0-indexed)
    final stream = FreqPlanService.writePlanToRadio(_freqPlan!, 2, radio);
    await for (final written in stream) {
      if (!mounted) break;
      setState(() => _planWritten = written);
    }

    if (!mounted) return;
    setState(() => _planWriting = false);
    messenger.showSnackBar(SnackBar(
      content: Text('Wrote $_planWritten/$total channels to Group 3'),
      backgroundColor:
          _planWritten == total ? Colors.green[700] : Colors.orange[700],
      duration: const Duration(seconds: 3),
    ));
  }

  Future<void> _setWeatherAlertsEnabled(bool v) async {
    final noaa = context.read<NoaaService>(); // capture before await
    // Request POST_NOTIFICATIONS permission on Android 13+
    if (v) await Permission.notification.request();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('weather_alerts_enabled', v);
    if (!mounted) return;
    setState(() => _weatherAlertsEnabled = v);
    if (v) {
      noaa.startPolling(sameCode: _sameCode.isEmpty ? null : _sameCode);
    } else {
      noaa.stopPolling();
    }
  }

  Future<void> _setNwrMonitorEnabled(bool v) async {
    // Capture context-dependent objects before any await
    final radio     = context.read<RadioService>();
    final noaa      = context.read<NoaaService>();
    final messenger = ScaffoldMessenger.of(context);
    final prefs     = await SharedPreferences.getInstance();
    await prefs.setBool('nwr_monitor_enabled', v);
    if (!mounted) return;
    setState(() => _nwrMonitorEnabled = v);
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

  Future<void> _setAprsReceive(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('aprs_is_enabled', v);
    setState(() => _aprsReceive = v);
  }

  Future<void> _setAprsBeaconEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('aprs_beacon_enabled', v);
    setState(() => _aprsBeaconEnabled = v);
  }

  Future<void> _setIgateEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('igate_enabled', v);
    setState(() => _igateEnabled = v);
  }

  // ─── Edit dialogs ─────────────────────────────────────────────────────────

  void _editCallsign(BuildContext context) {
    final controller = TextEditingController(text: _callsign);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: const Text('Your Callsign', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            hintText: 'e.g. KF0JKE',
            hintStyle: TextStyle(color: Colors.white38),
          ),
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final value     = controller.text.trim().toUpperCase();
              final prefs     = await SharedPreferences.getInstance();
              await prefs.setString('callsign', value);
              if (!mounted) return;
              setState(() => _callsign = value);
              if (ctx.mounted) Navigator.pop(ctx);
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('Saved!'),
                  duration: Duration(seconds: 2),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _editSameCode(BuildContext context) {
    final controller = TextEditingController(text: _sameCode);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: const Text('SAME Code', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                hintText: 'e.g. 008001 (county FIPS)',
                hintStyle: TextStyle(color: Colors.white38),
                counterStyle: TextStyle(color: Colors.white38),
              ),
              style: const TextStyle(
                  color: Colors.white, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 8),
            const Text(
              'SAME codes filter weather alerts to your county.\n'
              'Find yours at weather.gov/nwr/Counties.',
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final noaa      = context.read<NoaaService>();
              final messenger = ScaffoldMessenger.of(context);
              final value     = controller.text.trim();
              final prefs     = await SharedPreferences.getInstance();
              await prefs.setString('same_code', value);
              if (!mounted) return;
              setState(() => _sameCode = value);
              // Update polling SAME code filter if polling is active
              if (_weatherAlertsEnabled) {
                noaa.startPolling(sameCode: value.isEmpty ? null : value);
              }
              if (ctx.mounted) Navigator.pop(ctx);
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('Saved!'),
                  duration: Duration(seconds: 2),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'OpenHT',
      applicationVersion: '0.1.0',
      applicationLegalese:
          'Open-source Android controller for VGC/Benshi protocol radios.\n\n'
          'Protocol decoded by Kyle Husmann KC3SLD (benlink)\n'
          'Flutter port by SarahRoseLives (flutter_benlink)\n'
          'APRS parser by Lee K0QED (aprs-parser)\n'
          'Inspired by HtStation by Ylianst\n\n'
          'Apache-2.0 License',
      children: [
        const SizedBox(height: 8),
        const Text(
          'An amateur radio license is required to transmit using this software.',
          style: TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: Colors.blue[400],
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}
