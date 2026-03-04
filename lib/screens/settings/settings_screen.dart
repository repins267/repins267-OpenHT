// lib/screens/settings/settings_screen.dart
// Radio connection and app settings

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../bluetooth/radio_service.dart';
import 'tracks_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isScanning = false;
  String _callsign = '';
  String _sameCode = '';
  String _spotterAppId = '4f2e07d475ae4';
  bool _igateEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _callsign     = prefs.getString('callsign')        ?? '';
      _sameCode     = prefs.getString('same_code')       ?? '';
      _spotterAppId = prefs.getString('spotter_app_id')  ?? '4f2e07d475ae4';
      _igateEnabled = prefs.getBool('igate_enabled')     ?? false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final radio = context.watch<RadioService>();

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
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.bluetooth_searching),
                label: Text(_isScanning ? 'Scanning...' : 'Scan for Radio'),
                onPressed: _isScanning ? null : () => _scanAndConnect(radio),
              ),
            ),
          ],

          // ─── Paired Devices List ─────────────────────
          if (radio.pairedDevices.isNotEmpty) ...[
            _SectionHeader('Paired Devices'),
            ...radio.pairedDevices.map((device) => ListTile(
              leading: const Icon(Icons.radio, color: Colors.blue),
              title: Text(device.name ?? 'Unknown', style: const TextStyle(color: Colors.white)),
              subtitle: Text(device.address, style: const TextStyle(color: Colors.white38, fontSize: 11)),
              trailing: ElevatedButton(
                onPressed: radio.connectionState == RadioConnectionState.connecting
                    ? null
                    : () => radio.connect(device),
                child: const Text('Connect'),
              ),
            )),
          ],

          // ─── Callsign ────────────────────────────────
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
              _sameCode.isEmpty ? 'Not set (county alert filter)' : _sameCode,
              style: TextStyle(
                color: _sameCode.isEmpty ? Colors.white38 : Colors.orange[300],
              ),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
            onTap: () => _editSameCode(context),
          ),

          // ─── APRS iGate ──────────────────────────────
          _SectionHeader('APRS iGate'),
          SwitchListTile(
            secondary: Icon(
              Icons.router_outlined,
              color: _igateEnabled ? Colors.green : Colors.grey,
            ),
            title: const Text('Enable iGate', style: TextStyle(color: Colors.white)),
            subtitle: Text(
              _igateEnabled
                  ? 'Forwarding packets → noam.aprs2.net'
                  : 'Forwards received APRS frames to the internet',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            value: _igateEnabled,
            onChanged: (v) => _setIgateEnabled(v),
          ),

          // ─── Spotter Network ─────────────────────────
          _SectionHeader('Spotter Network'),
          ListTile(
            leading: const Icon(Icons.cloud_outlined, color: Colors.orange),
            title: const Text('App ID', style: TextStyle(color: Colors.white)),
            subtitle: Text(
              _spotterAppId,
              style: const TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'monospace'),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
            onTap: () => _editSpotterAppId(context),
          ),

          // ─── Track Recording ─────────────────────────
          _SectionHeader('Track Recording'),
          ListTile(
            leading: const Icon(Icons.route, color: Colors.green),
            title: const Text('View Saved Tracks', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Browse, share, or delete GPX files',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const TracksScreen())),
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
        ],
      ),
    );
  }

  Future<void> _scanAndConnect(RadioService radio) async {
    setState(() => _isScanning = true);
    await radio.scanPairedDevices();
    setState(() => _isScanning = false);
  }

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
              final value = controller.text.trim().toUpperCase();
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('callsign', value);
              setState(() => _callsign = value);
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Saved! ✓'),
                    duration: Duration(seconds: 2),
                    backgroundColor: Colors.green,
                  ),
                );
              }
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
              style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 8),
            const Text(
              'SAME codes filter NOAA weather alerts to your county.\n'
              'Find yours at weather.gov/nwr/Counties.',
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final value = controller.text.trim();
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('same_code', value);
              setState(() => _sameCode = value);
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Saved! ✓'),
                    duration: Duration(seconds: 2),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _editSpotterAppId(BuildContext context) {
    final controller = TextEditingController(text: _spotterAppId);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: const Text('Spotter Network App ID', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'e.g. 4f2e07d475ae4',
            hintStyle: TextStyle(color: Colors.white38),
          ),
          style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final value = controller.text.trim();
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('spotter_app_id', value);
              setState(() => _spotterAppId = value);
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Saved! ✓'),
                    duration: Duration(seconds: 2),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _setIgateEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('igate_enabled', value);
    setState(() => _igateEnabled = value);
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
