// lib/screens/dashboard/dashboard_screen.dart
// Main radio control dashboard

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../bluetooth/radio_service.dart';
import '../../services/gps_service.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final radio = context.watch<RadioService>();
    final gps = context.watch<GpsService>();

    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: const Text('OpenHT'),
        backgroundColor: Colors.grey[850],
        foregroundColor: Colors.white,
        actions: [
          // Bluetooth connection status indicator
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Icon(
              radio.isConnected
                  ? Icons.bluetooth_connected
                  : Icons.bluetooth_disabled,
              color: radio.isConnected ? Colors.blue : Colors.grey,
            ),
          ),
        ],
      ),
      body: radio.isConnected ? _ConnectedView(radio: radio, gps: gps) : _DisconnectedView(),
    );
  }
}

class _ConnectedView extends StatelessWidget {
  final RadioService radio;
  final GpsService gps;

  const _ConnectedView({required this.radio, required this.gps});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // ─── Frequency Display ───────────────────────
          _FrequencyCard(radio: radio),
          const SizedBox(height: 12),

          // ─── Status Row ─────────────────────────────
          Row(
            children: [
              Expanded(child: _StatusTile(
                icon: Icons.battery_charging_full,
                label: 'Battery',
                value: radio.batteryPercent != null
                    ? '${radio.batteryPercent}% (${radio.batteryVoltage?.toStringAsFixed(1)}V)'
                    : '—',
                color: _batteryColor(radio.batteryPercent),
              )),
              const SizedBox(width: 8),
              Expanded(child: _StatusTile(
                icon: Icons.gps_fixed,
                label: 'GPS',
                value: gps.hasPosition ? gps.displayPosition : 'No Fix',
                color: gps.hasPosition ? Colors.green : Colors.orange,
              )),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _StatusTile(
                icon: Icons.radio,
                label: 'TX',
                value: (radio.isTransmitting ?? false) ? 'TRANSMITTING' : 'Idle',
                color: (radio.isTransmitting ?? false) ? Colors.red : Colors.grey,
              )),
              const SizedBox(width: 8),
              Expanded(child: _StatusTile(
                icon: Icons.hearing,
                label: 'RX',
                value: (radio.isReceiving ?? false) ? 'RECEIVING' : 'Idle',
                color: (radio.isReceiving ?? false) ? Colors.green : Colors.grey,
              )),
            ],
          ),
          const SizedBox(height: 16),

          // ─── Quick Actions ───────────────────────────
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Quick Actions',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
          ),
          const SizedBox(height: 8),
          _QuickActions(),
        ],
      ),
    );
  }

  Color _batteryColor(int? pct) {
    if (pct == null) return Colors.grey;
    if (pct > 60) return Colors.green;
    if (pct > 30) return Colors.orange;
    return Colors.red;
  }
}

class _FrequencyCard extends StatelessWidget {
  final RadioService radio;
  const _FrequencyCard({required this.radio});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green[700]!, width: 1),
      ),
      child: Column(
        children: [
          Text(
            radio.currentChannelName ?? '---',
            style: const TextStyle(color: Colors.green, fontSize: 13, letterSpacing: 2),
          ),
          const SizedBox(height: 4),
          Text(
            '--- . ---- MHz', // Will be populated from radio state
            style: TextStyle(
              color: Colors.green[400],
              fontSize: 36,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              letterSpacing: 3,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatusTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[850],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.3,
      children: [
        _ActionButton(icon: Icons.cell_tower, label: 'Near\nRepeaters',
            color: Colors.blue, onTap: () => _navigate(context, 1)),
        _ActionButton(icon: Icons.map, label: 'APRS\nMap',
            color: Colors.green, onTap: () => _navigate(context, 2)),
        _ActionButton(icon: Icons.settings, label: 'Radio\nSettings',
            color: Colors.orange, onTap: () => _navigate(context, 3)),
      ],
    );
  }

  void _navigate(BuildContext context, int index) {
    // Notify parent bottom nav to switch tab
    DefaultTabController.of(context)?.animateTo(index);
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.4), width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(color: color, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _DisconnectedView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.bluetooth_searching, size: 72, color: Colors.white24),
          const SizedBox(height: 16),
          const Text(
            'No Radio Connected',
            style: TextStyle(color: Colors.white54, fontSize: 20),
          ),
          const SizedBox(height: 8),
          const Text(
            'Pair your VGC radio via Android Settings,\nthen connect from the Radio Settings tab.',
            style: TextStyle(color: Colors.white38, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            icon: const Icon(Icons.bluetooth),
            label: const Text('Connect Radio'),
            onPressed: () {
              // Navigate to settings/connect tab
            },
          ),
        ],
      ),
    );
  }
}
