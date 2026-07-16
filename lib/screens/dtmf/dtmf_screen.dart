import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_benlink/flutter_benlink.dart' show RadioAudioState;
import '../../bluetooth/radio_service.dart';
import '../../services/dtmf_generator.dart';

/// Compose, save, and transmit DTMF (touch-tone) strings from the phone
/// keyboard — the thing the vendor app makes you pad-type on the radio.
/// Sends by synthesizing dual-tone PCM and pushing it through the radio's
/// app-audio TX path (keys → tones → unkey). No protocol command needed.
class DtmfScreen extends StatefulWidget {
  const DtmfScreen({super.key});

  @override
  State<DtmfScreen> createState() => _DtmfScreenState();
}

class _Preset {
  final String name;
  final String digits;
  const _Preset(this.name, this.digits);
  Map<String, String> toJson() => {'name': name, 'digits': digits};
  static _Preset fromJson(Map<String, dynamic> j) =>
      _Preset(j['name'] as String? ?? '', j['digits'] as String? ?? '');
}

/// Speed presets: (label, toneMs, gapMs). Normal ≈ vendor's 240 cpm.
const _speeds = <(String, int, int)>[
  ('Slow', 200, 90),
  ('Normal', 150, 60),
  ('Fast', 100, 40),
];

class _DtmfScreenState extends State<DtmfScreen> {
  final _ctrl = TextEditingController();
  List<_Preset> _presets = [];
  int _speed = 1; // index into _speeds
  bool _busy = false;

  static const _prefsKey = 'dtmf_presets';
  static const _speedKey = 'dtmf_speed_idx';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    final idx = prefs.getInt(_speedKey) ?? 1;
    if (!mounted) return;
    setState(() {
      _speed = idx.clamp(0, _speeds.length - 1);
      if (raw != null) {
        try {
          _presets = (jsonDecode(raw) as List)
              .map((e) => _Preset.fromJson(e as Map<String, dynamic>))
              .toList();
        } catch (_) {}
      }
    });
  }

  Future<void> _savePresets() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _prefsKey, jsonEncode(_presets.map((p) => p.toJson()).toList()));
  }

  void _append(String ch) {
    final t = _ctrl.text;
    final sel = _ctrl.selection;
    final at = sel.isValid ? sel.start : t.length;
    _ctrl.text = t.substring(0, at) + ch + t.substring(at);
    _ctrl.selection = TextSelection.collapsed(offset: at + ch.length);
  }

  Future<void> _transmit(String digits) async {
    final radio = context.read<RadioService>();
    final messenger = ScaffoldMessenger.of(context);
    if (digits.trim().isEmpty) return;
    if (!radio.isConnected) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Radio not connected')));
      return;
    }
    setState(() => _busy = true);
    // The native app-audio TX path (sendPcm) silently no-ops unless the audio
    // channel is already open, so open it first if needed and close it after.
    bool openedHere = false;
    try {
      if (radio.audioState == RadioAudioState.off) {
        openedHere = true;
        await radio.startAudioMonitor();
        // Wait up to ~4 s for the RFCOMM audio socket to come up.
        for (int i = 0;
            i < 40 && radio.audioState == RadioAudioState.off;
            i++) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
        await Future.delayed(const Duration(milliseconds: 250)); // settle
      }
      if (radio.audioState == RadioAudioState.off) {
        if (mounted) {
          messenger.showSnackBar(
              const SnackBar(content: Text('Audio channel didn\'t open')));
        }
        return;
      }

      final (_, toneMs, gapMs) = _speeds[_speed];
      final pcm = DtmfGenerator.render(digits, toneMs: toneMs, gapMs: gapMs);
      // Stream ~8 KB (~128 ms) chunks paced near real-time so the radio's audio
      // buffer isn't overrun; the engine keys on the first chunk.
      const chunk = 8192;
      const chunkMs =
          (chunk ~/ 2) * 1000 ~/ DtmfGenerator.sampleRate; // audio ms per chunk
      for (int o = 0; o < pcm.length; o += chunk) {
        final end = (o + chunk < pcm.length) ? o + chunk : pcm.length;
        await radio.sendAudioPcm(Uint8List.sublistView(pcm, o, end));
        if (end < pcm.length) {
          await Future.delayed(
              Duration(milliseconds: (chunkMs * 0.85).round()));
        }
      }
      await radio.endTransmit();
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Sent DTMF: $digits')));
      }
    } catch (e) {
      await radio.endTransmit();
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('DTMF failed: $e')));
      }
    } finally {
      if (openedHere) {
        await Future.delayed(const Duration(milliseconds: 300));
        await radio.stopAudioMonitor();
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveCurrentAsPreset() async {
    final digits = _ctrl.text.trim();
    if (digits.isEmpty) return;
    final name = await _askName();
    if (name == null || name.isEmpty) return;
    setState(() => _presets = [..._presets, _Preset(name, digits)]);
    await _savePresets();
  }

  Future<String?> _askName() {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Name this DTMF preset'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. Gate open'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connected = context.watch<RadioService>().isConnected;
    return Scaffold(
      appBar: AppBar(
        title: const Text('DTMF'),
        actions: [
          PopupMenuButton<int>(
            initialValue: _speed,
            tooltip: 'Speed',
            icon: const Icon(Icons.speed),
            onSelected: (v) async {
              setState(() => _speed = v);
              (await SharedPreferences.getInstance()).setInt(_speedKey, v);
            },
            itemBuilder: (_) => [
              for (int i = 0; i < _speeds.length; i++)
                PopupMenuItem(value: i, child: Text(_speeds[i].$1)),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _ctrl,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 24, letterSpacing: 4),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Da-d*#, ]')),
                TextInputFormatter.withFunction((_, n) =>
                    n.copyWith(text: n.text.toUpperCase())),
              ],
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: 'Type or tap digits',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.backspace_outlined),
                  onPressed: () => setState(() => _ctrl.clear()),
                ),
              ),
            ),
          ),
          // Keypad
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.6,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                for (final k in DtmfGenerator.keypad)
                  OutlinedButton(
                    onPressed: _busy ? null : () => _append(k),
                    child: Text(k,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: (_busy || !connected)
                        ? null
                        : () => _transmit(_ctrl.text),
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.graphic_eq),
                    label: Text(connected ? 'Transmit' : 'Radio offline'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _saveCurrentAsPreset,
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: const Text('Save'),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: _presets.isEmpty
                ? const Center(
                    child: Text('No saved presets',
                        style: TextStyle(color: Colors.white38)))
                : ListView.builder(
                    itemCount: _presets.length,
                    itemBuilder: (_, i) {
                      final p = _presets[i];
                      return ListTile(
                        leading: const Icon(Icons.dialpad),
                        title: Text(p.name),
                        subtitle: Text(p.digits,
                            style: const TextStyle(fontFamily: 'monospace')),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.north_east),
                              tooltip: 'Load to editor',
                              onPressed: () {
                                _ctrl.text = p.digits;
                                _ctrl.selection = TextSelection.collapsed(
                                    offset: p.digits.length);
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.graphic_eq),
                              tooltip: 'Send',
                              onPressed: (_busy || !connected)
                                  ? null
                                  : () => _transmit(p.digits),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                setState(() => _presets =
                                    List.of(_presets)..removeAt(i));
                                await _savePresets();
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
