// lib/screens/settings/settings_screen.dart
// Radio connection and app settings

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../bluetooth/radio_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isScanning = false;

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

          // ─── App Settings ────────────────────────────
          _SectionHeader('App Settings'),
          ListTile(
            leading: const Icon(Icons.my_location, color: Colors.green),
            title: const Text('Callsign', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Set your callsign for APRS', style: TextStyle(color: Colors.white54)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
            onTap: () => _editCallsign(context),
          ),
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
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: const Text('Your Callsign', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            hintText: 'e.g. N0CALL',
            hintStyle: TextStyle(color: Colors.white38),
          ),
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              // Save callsign to SharedPreferences
              Navigator.pop(ctx);
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
