// lib/widgets/radio_status_bar.dart
// Persistent radio status strip shown above the bottom navigation bar.
// Only visible when a radio is connected.

import 'package:flutter/material.dart';
import 'package:flutter_benlink/flutter_benlink.dart';
import 'package:provider/provider.dart';
import '../bluetooth/radio_service.dart';
import '../services/audio_service.dart';

class RadioStatusBar extends StatelessWidget {
  const RadioStatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    final radio = context.watch<RadioService>();
    if (!radio.isConnected) return const SizedBox.shrink();

    final audio = context.watch<AudioService>();
    final freqText = radio.currentRxFreq > 0
        ? radio.currentRxFreq.toStringAsFixed(3)
        : '---.-—-';
    final modeText = switch (radio.currentMode) {
      ModulationType.AM  => 'AM',
      ModulationType.DMR => 'DMR',
      _ => radio.currentBandwidth == BandwidthType.NARROW ? 'NFM' : 'FM',
    };

    return Container(
      width: double.infinity,
      color: Colors.grey[850],
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          // Frequency
          Text(
            '$freqText MHz',
            style: const TextStyle(
              color: Colors.green,
              fontSize: 13,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          // Mode badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.green[900],
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              modeText,
              style: const TextStyle(color: Colors.green, fontSize: 10),
            ),
          ),
          const Spacer(),
          // TX / RX indicator
          if (radio.isTransmitting == true)
            const Text('TX', style: TextStyle(
              color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold)),
          if (radio.isReceiving == true)
            const Text('RX', style: TextStyle(
              color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          // SCO audio state dot
          Icon(
            switch (audio.scoState) {
              ScoState.connected  => Icons.volume_up,
              ScoState.connecting => Icons.volume_up,
              ScoState.error      => Icons.error_outline,
              ScoState.off        => Icons.volume_off,
            },
            size: 14,
            color: switch (audio.scoState) {
              ScoState.connected  => Colors.green,
              ScoState.connecting => Colors.orange,
              ScoState.error      => Colors.red,
              ScoState.off        => Colors.grey,
            },
          ),
          const SizedBox(width: 8),
          // Battery
          if (radio.batteryPercent != null) ...[
            Icon(
              Icons.battery_full,
              size: 14,
              color: _batteryColor(radio.batteryPercent),
            ),
            const SizedBox(width: 2),
            Text(
              '${radio.batteryPercent}%',
              style: TextStyle(
                color: _batteryColor(radio.batteryPercent),
                fontSize: 11,
              ),
            ),
          ],
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
