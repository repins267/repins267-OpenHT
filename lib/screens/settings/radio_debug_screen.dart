import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_benlink/flutter_benlink.dart';
import 'package:provider/provider.dart';
import '../../bluetooth/radio_service.dart';

class RadioDebugScreen extends StatefulWidget {
  const RadioDebugScreen({super.key});

  @override
  State<RadioDebugScreen> createState() => _RadioDebugScreenState();
}

class _RadioDebugScreenState extends State<RadioDebugScreen> {
  final List<(String, String)> _logs = []; // (direction, hex)
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final radio = context.read<RadioService>();
    radio.onRawBytesSent = (b) => _addLog('TX', b);
    radio.onRawBytesReceived = (b) => _addLog('RX', b);
  }

  @override
  void dispose() {
    final radio = context.read<RadioService>();
    radio.onRawBytesSent = null;
    radio.onRawBytesReceived = null;
    _scrollController.dispose();
    super.dispose();
  }

  void _addLog(String direction, Uint8List bytes) {
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
    final timestamp = DateTime.now().toString().split(' ').last.substring(0, 8);
    if (!mounted) return;
    setState(() {
      _logs.add((direction, '[$timestamp] $direction: $hex'));
    });
    _scrollToBottom();
  }

  void _addTextLog(String message) {
    if (!mounted) return;
    setState(() {
      _logs.add(('INFO', message));
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final radio = context.watch<RadioService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Radio Protocol Debug'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy log',
            onPressed: () {
              final text = _logs.map((e) => e.$2).join('\n');
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Log copied'), duration: Duration(seconds: 1)),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Clear log',
            onPressed: () => setState(() => _logs.clear()),
          ),
        ],
      ),
      body: Column(
        children: [
          // ─── State Info Panel ───────────────────────────
          _RadioStatePanel(radio: radio),

          // Control Buttons
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: radio.connectionState == RadioConnectionState.scanning
                      ? null
                      : () => radio.scanPairedDevices(),
                  child: const Text('Scan & Connect'),
                ),
                ElevatedButton(
                  onPressed: !radio.isConnected ? null : () => _sendVfoMode(radio),
                  child: const Text('VFO Mode'),
                ),
                ElevatedButton(
                  onPressed: !radio.isConnected ? null : () => _sendTuneCommand(radio),
                  child: const Text('Tune 146.520'),
                ),
                ElevatedButton(
                  onPressed: !radio.isConnected ? null : () => _sendSyncSettings(radio),
                  child: const Text('Re-sync'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800]),
                  onPressed: !radio.isConnected ? null : () => _diagChannelCount(radio),
                  child: const Text('Ch Count'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800]),
                  onPressed: !radio.isConnected ? null : () => _diagReadChannels(radio),
                  child: const Text('Read 0,31,160'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800]),
                  onPressed: !radio.isConnected ? null : () => _diagReadGroup6(radio),
                  child: const Text('Read Grp 6'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red[800]),
                  onPressed: !radio.isConnected ? null : () => _diagWriteChannels(radio),
                  child: const Text('Write Test'),
                ),
              ],
            ),
          ),

          // Terminal
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.grey[800]!),
              ),
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _logs.length,
                itemBuilder: (context, index) {
                  final (direction, text) = _logs[index];
                  final color = switch (direction) {
                    'TX'   => Colors.greenAccent,
                    'RX'   => Colors.lightBlueAccent,
                    _      => Colors.white54,
                  };
                  return Text(
                    text,
                    style: TextStyle(
                      color: color,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendVfoMode(RadioService radio) async {
    try {
      _addTextLog('[INFO] Sending VFO mode command...');
      await radio.forceVfoMode();
      _addTextLog('[INFO] VFO mode command sent.');
    } catch (e) {
      _addTextLog('[ERROR] $e');
    }
  }

  Future<void> _sendTuneCommand(RadioService radio) async {
    try {
      _addTextLog('[INFO] Tuning to 146.520 MHz...');
      await radio.tuneToFrequency(146.520);
      _addTextLog('[INFO] Tune command sent.');
    } catch (e) {
      _addTextLog('[ERROR] $e');
    }
  }

  Future<void> _sendSyncSettings(RadioService radio) async {
    try {
      _addTextLog('[INFO] Sending sync (re-reading settings)...');
      await radio.syncSettings();
      _addTextLog('[INFO] Sync complete.');
    } catch (e) {
      _addTextLog('[ERROR] $e');
    }
  }

  Future<void> _diagChannelCount(RadioService radio) async {
    _addTextLog('[DIAG] firmwareChannelCount = ${radio.firmwareChannelCount}');
    _addTextLog('[DIAG] channelA (VFO A) = ${radio.controller?.settings?.channelA ?? "?"}');
  }

  Future<void> _diagReadGroup6(RadioService radio) async {
    _addTextLog('[DIAG] Reading Group 6 (channels 160–191)...');
    try {
      final results = await radio.diagReadGroup(5); // group index 5 = IDs 160-191
      for (final line in results) {
        _addTextLog('[DIAG] $line');
      }
      _addTextLog('[DIAG] Group 6 read complete (${results.length} channels).');
    } catch (e) {
      _addTextLog('[ERROR] Read Group 6 failed: $e');
    }
  }

  Future<void> _diagReadChannels(RadioService radio) async {
    _addTextLog('[DIAG] Reading channels 0, 31, 160...');
    for (final id in [0, 31, 160]) {
      final result = await radio.diagReadChannel(id);
      _addTextLog('[DIAG] $result');
    }
  }

  Future<void> _diagWriteChannels(RadioService radio) async {
    _addTextLog('[DIAG] Writing test channel at IDs 0 and 160 (146.520 MHz)...');
    final r0 = await radio.diagWriteChannel(0, 146.520);
    _addTextLog('[DIAG] $r0');
    final r160 = await radio.diagWriteChannel(160, 146.520);
    _addTextLog('[DIAG] $r160');
  }
}

// ─── Radio State Info Panel ────────────────────────────────────────────────

class _RadioStatePanel extends StatelessWidget {
  final RadioService radio;
  const _RadioStatePanel({required this.radio});

  @override
  Widget build(BuildContext context) {
    final info = radio.controller?.deviceInfo;
    final connected = radio.isConnected;

    final stateColor = switch (radio.connectionState) {
      RadioConnectionState.connected  => Colors.green,
      RadioConnectionState.syncing    => Colors.orange,
      RadioConnectionState.connecting => Colors.orange,
      RadioConnectionState.error      => Colors.red,
      _                               => Colors.grey,
    };

    return Container(
      width: double.infinity,
      color: Colors.grey[900],
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status + model row
          Row(
            children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(color: stateColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                radio.connectionState.name.toUpperCase(),
                style: TextStyle(color: stateColor, fontSize: 11, fontWeight: FontWeight.bold),
              ),
              if (info != null) ...[
                const SizedBox(width: 8),
                Text(
                  '${info.vendorName} ${info.productName}  '
                  'HW:${info.hardwareVersion}  FW:${info.firmwareVersion}  '
                  '${info.channelCount}ch',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ],
          ),
          if (connected) ...[
            const SizedBox(height: 4),
            // Frequency / mode / battery row
            Row(
              children: [
                _InfoChip(
                  label: radio.currentRxFreq > 0
                      ? '${radio.currentRxFreq.toStringAsFixed(3)} MHz'
                      : '---',
                  color: Colors.greenAccent,
                ),
                const SizedBox(width: 6),
                _InfoChip(
                  label: radio.currentMode?.name.toUpperCase() ?? '??',
                  color: Colors.cyan,
                ),
                const SizedBox(width: 6),
                _InfoChip(
                  label: radio.currentBandwidth == BandwidthType.WIDE ? 'WIDE' : 'NARR',
                  color: Colors.cyan,
                ),
                const SizedBox(width: 6),
                _InfoChip(
                  label: 'Ch ${radio.currentChannelId}',
                  color: Colors.white54,
                ),
                const SizedBox(width: 6),
                if (radio.batteryPercent != null)
                  _InfoChip(
                    label: '${radio.batteryPercent}%',
                    color: (radio.batteryPercent ?? 0) > 30 ? Colors.green : Colors.red,
                  ),
                if (radio.isTransmitting == true)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Text('TX', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                if (radio.isReceiving == true)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Text('RX', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final Color color;
  const _InfoChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black38,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.5), width: 1),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontFamily: 'monospace')),
    );
  }
}
