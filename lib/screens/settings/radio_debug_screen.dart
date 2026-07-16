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
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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
    // Scroll to bottom whenever log updates
    if (radio.debugLog.isNotEmpty) _scrollToBottom();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Radio Protocol Debug'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy log',
            onPressed: () {
              final text = radio.debugLog.map((e) => e.$2).join('\n');
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Log copied'), duration: Duration(seconds: 1)),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Clear log',
            onPressed: () => context.read<RadioService>().clearDebugLog(),
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
                // ── Recovery / revert: stock signed UV-Pro 260 (restores NOAA, no callsign) ──
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal[700],
                      foregroundColor: Colors.white),
                  onPressed: !radio.isConnected
                      ? null
                      : () => _fwFlashCommit(radio,
                          'assets/uv_pro_stock.firmware', 'STOCK UV-Pro 260 (signed → NOAA!)'),
                  child: const Text('✔ FLASH UV-Pro 260 (NOAA)'),
                ),
                // ── UV-Pro 260 + callsign splash (keeps NOAA; data-only logo edit) ──
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[900],
                      foregroundColor: Colors.white),
                  onPressed: !radio.isConnected
                      ? null
                      : () => _fwFlashCommit(radio,
                          'assets/uv_pro_callsign.firmware',
                          'UV-Pro 260 + N0TEZ callsign (NOAA kept)'),
                  child: const Text('⚠ FLASH+COMMIT UV-Pro + Callsign'),
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
                itemCount: radio.debugLog.length,
                itemBuilder: (context, index) {
                  final (direction, text) = radio.debugLog[index];
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
      radio.addDebugText('[INFO] Sending VFO mode command...');
      await radio.forceVfoMode();
      radio.addDebugText('[INFO] VFO mode command sent.');
    } catch (e) {
      radio.addDebugText('[ERROR] $e');
    }
  }

  Future<void> _sendTuneCommand(RadioService radio) async {
    try {
      radio.addDebugText('[INFO] Tuning to 146.520 MHz...');
      await radio.tuneToFrequency(146.520);
      radio.addDebugText('[INFO] Tune command sent.');
    } catch (e) {
      radio.addDebugText('[ERROR] $e');
    }
  }

  Future<void> _sendSyncSettings(RadioService radio) async {
    try {
      radio.addDebugText('[INFO] Sending sync (re-reading settings)...');
      await radio.syncSettings();
      radio.addDebugText('[INFO] Sync complete.');
    } catch (e) {
      radio.addDebugText('[ERROR] $e');
    }
  }

  Future<void> _diagChannelCount(RadioService radio) async {
    radio.addDebugText('[DIAG] firmwareChannelCount = ${radio.firmwareChannelCount}');
    radio.addDebugText('[DIAG] channelA (VFO A) = ${radio.controller?.settings?.channelA ?? "?"}');
  }

  Future<void> _diagReadGroup6(RadioService radio) async {
    radio.addDebugText('[DIAG] Reading Group 6 (channels 160–191)...');
    try {
      final results = await radio.diagReadGroup(5);
      for (final line in results) {
        radio.addDebugText('[DIAG] $line');
      }
      radio.addDebugText('[DIAG] Group 6 read complete (${results.length} channels).');
    } catch (e) {
      radio.addDebugText('[ERROR] Read Group 6 failed: $e');
    }
  }

  Future<void> _diagReadChannels(RadioService radio) async {
    radio.addDebugText('[DIAG] Reading channels 0, 31, 160...');
    for (final id in [0, 31, 160]) {
      final result = await radio.diagReadChannel(id);
      radio.addDebugText('[DIAG] $result');
    }
  }

  /// Full FLASH + COMMIT of the bundled N0TEZ image, with NO manual power-cycle.
  /// Phase 1 stages the image; Phase 2 is a multi-pass commit that rides through
  /// the radio's warm-reset(s): UPDATE_START_CFM=OK (applying+reboot) → reconnect
  /// → UPDATE_START_CFM=GOTO_NEXT_STATE → UPDATE_COMPLETE_IND (committed).
  /// Recovery image recon_259_from_capture.firmware is the fallback.
  Future<void> _fwFlashCommit(
      RadioService radio, String assetPath, String label) async {
    final controller0 = radio.controller;
    if (controller0 == null) {
      radio.addDebugText('[FW] No radio controller.');
      return;
    }
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('⚠ FLASH + COMMIT: $label?'),
        content: Text(
          'This transfers "$label" and COMMITS it as the radio\'s ACTIVE '
          'firmware. The radio will reboot (possibly a couple times).\n\n'
          'Do NOT power-cycle during this — the app handles the '
          'reboots/reconnects. Takes several minutes. Recovery image available. '
          'Proceed?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('FLASH + COMMIT'),
          ),
        ],
      ),
    );
    if (go != true) return;

    final device = controller0.device;
    try {
      radio.addDebugText('[FW] === $label ===');
      final data = (await rootBundle.load(assetPath)).buffer.asUint8List();
      final bundle = FirmwareBundle(data);

      // ── Phase 1: transfer ───────────────────────────────────────────────
      radio.addDebugText('[FW] Phase 1 transfer (~5 min)…');
      int lastDecile = -1;
      await FirmwareUpdater(controller0, bundle, progress: (s, d, t) {
        final dec = (d * 100 ~/ t) ~/ 10;
        if (dec > lastDecile) {
          lastDecile = dec;
          radio.addDebugText('[FW] $s ${dec * 10}%');
        }
      }).transfer();
      radio.addDebugText('[FW] staged ✓. Phase 2 commit (radio may reboot 1–2×)…');
      await _runCommitLoop(radio, bundle, device);
    } catch (e) {
      radio.addDebugText('[FW][ERROR] flash+commit: $e');
    }
  }

  /// Stage-2 commit (vendor-app RE two-stage flow): Phase-1 transfer has already
  /// sent UPDATE_TRANSFER_COMPLETE_RES[0x00] → the radio warm-reboots into the
  /// TRIAL image and the BT link drops. Reconnect through that reboot, then run
  /// confirm() (IN_PROGRESS_RES → COMMIT_REQ → COMMIT_CFM[0x00] → COMPLETE_IND)
  /// to make the image PERMANENT.
  Future<void> _runCommitLoop(
      RadioService radio, FirmwareBundle bundle, dynamic device) async {
    radio.addDebugText(
        '[FW] transfer done → radio rebooting into TRIAL image; reconnecting for commit…');
    // Let TRANSFER_COMPLETE_RES[0x00] land and the radio begin its trial reboot
    // before we cycle the link.
    await Future<void>.delayed(const Duration(seconds: 3));
    for (int pass = 1; pass <= 3; pass++) {
      final ok = await _reconnectThroughReboot(radio, device);
      if (!ok) {
        radio.addDebugText(
            '[FW][ERROR] reconnect after trial reboot failed (pass $pass). Check '
            'the radio, reconnect, and tap COMMIT to retry the handshake.');
        return;
      }
      final c = radio.controller;
      if (c == null || !c.isConnected) {
        radio.addDebugText('[FW][ERROR] no connection after reconnect.');
        return;
      }
      radio.addDebugText('[FW] reconnected — stage-2 commit handshake (pass $pass)…');
      try {
        final result = await FirmwareUpdater.confirm(c, bundle);
        if (result == FirmwareConfirmResult.committed) {
          radio.addDebugText(
              '[FW] ✓✓ COMMIT COMPLETE (UPDATE_COMPLETE_IND) — image is now PERMANENT! 🎉');
          return;
        }
        if (result == FirmwareConfirmResult.committing) {
          // COMMIT_CFM sent but COMPLETE_IND didn't arrive on this link — drop it
          // so the radio applies + reboots into the committed image.
          radio.addDebugText(
              '[FW] COMMIT_CFM sent, no COMPLETE_IND yet — dropping link so the '
              'radio applies + reboots. WATCH THE SPLASH, then reconnect to verify.');
          radio.disconnect();
          return;
        }
        radio.addDebugText(
            '[FW] pass $pass: START=OK / no commit — reconnecting for another pass…');
      } on Exception catch (e) {
        radio.addDebugText('[FW] pass $pass confirm error: $e — retrying…');
      }
    }
    radio.addDebugText('[FW][ERROR] did not finalise after 3 passes.');
  }

  /// Tear down the link, wait for the radio's warm-reset, then reconnect via the
  /// managed BT stack. Returns true once reconnected + synced.
  Future<bool> _reconnectThroughReboot(RadioService radio, dynamic device) async {
    radio.disconnect(); // stop auto-reconnect; clean teardown
    await Future<void>.delayed(const Duration(seconds: 15));
    for (int a = 0; a < 8; a++) {
      radio.addDebugText('[FW] reconnect attempt ${a + 1}/8…');
      final ok = await radio.connect(device);
      if (ok) {
        await Future<void>.delayed(const Duration(seconds: 1));
        return true;
      }
      await Future<void>.delayed(const Duration(seconds: 5));
    }
    return false;
  }

  Future<void> _diagWriteChannels(RadioService radio) async {
    radio.addDebugText('[DIAG] Writing test channel at IDs 0 and 160 (146.520 MHz)...');
    final r0 = await radio.diagWriteChannel(0, 146.520);
    radio.addDebugText('[DIAG] $r0');
    final r160 = await radio.diagWriteChannel(160, 146.520);
    radio.addDebugText('[DIAG] $r160');
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
