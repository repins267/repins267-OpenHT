// lib/screens/settings/js8call_settings_screen.dart
// JS8Call settings — FM-audio DSP digital mode (stub UI, no DSP yet)
// All settings stored in SharedPreferences; actual DSP wired in a future PR.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── JS8 speed/window presets ──────────────────────────────────────────────────
const _kJs8Speeds = [
  ('Normal', '15', '~50 WPM · 15 s TX window'),
  ('Fast',   '10', '~25 WPM · 10 s TX window'),
  ('Turbo',  '6',  '~100 WPM · 6 s TX window'),
];

// ── Grid square helper ────────────────────────────────────────────────────────
String _normalizeGrid(String g) {
  // Maidenhead 4-char (field + square)
  g = g.toUpperCase().trim();
  if (g.length >= 4) return g.substring(0, 4);
  return g;
}

class Js8CallSettingsScreen extends StatefulWidget {
  const Js8CallSettingsScreen({super.key});

  @override
  State<Js8CallSettingsScreen> createState() => _Js8CallSettingsScreenState();
}

class _Js8CallSettingsScreenState extends State<Js8CallSettingsScreen> {
  bool _enabled = false;
  String _speed = '15';           // TX window in seconds
  String _grid = '';
  bool _heartbeatEnabled = false;
  int _heartbeatIntervalMin = 10;
  bool _relayEnabled = false;
  int _relayTtl = 3;
  bool _storeForwardEnabled = false;
  int _audioOffsetHz = 1500;      // audio offset within the FM channel
  bool _dirty = false;

  static const _kOffsets = [900, 1000, 1250, 1500, 1800, 2000];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _enabled              = p.getBool('js8_enabled')           ?? false;
      _speed                = p.getString('js8_speed')           ?? '15';
      _grid                 = p.getString('js8_grid')            ?? '';
      _heartbeatEnabled     = p.getBool('js8_heartbeat')         ?? false;
      _heartbeatIntervalMin = p.getInt('js8_heartbeat_interval') ?? 10;
      _relayEnabled         = p.getBool('js8_relay')             ?? false;
      _relayTtl             = p.getInt('js8_relay_ttl')          ?? 3;
      _storeForwardEnabled  = p.getBool('js8_store_forward')     ?? false;
      _audioOffsetHz        = p.getInt('js8_audio_offset')       ?? 1500;
      _dirty = false;
    });
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('js8_enabled',            _enabled);
    await p.setString('js8_speed',            _speed);
    await p.setString('js8_grid',             _grid);
    await p.setBool('js8_heartbeat',          _heartbeatEnabled);
    await p.setInt('js8_heartbeat_interval',  _heartbeatIntervalMin);
    await p.setBool('js8_relay',              _relayEnabled);
    await p.setInt('js8_relay_ttl',           _relayTtl);
    await p.setBool('js8_store_forward',      _storeForwardEnabled);
    await p.setInt('js8_audio_offset',        _audioOffsetHz);
    setState(() => _dirty = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('JS8Call settings saved'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _markDirty() => setState(() => _dirty = true);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('JS8Call Settings'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _dirty ? _save : null,
            child: Text(
              'Save',
              style: TextStyle(
                  color: _dirty ? Colors.white : Colors.white38),
            ),
          ),
        ],
      ),
      body: ListView(
        children: [
          // ── DSP stub banner ────────────────────────────────────────────
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue[900]!.withOpacity(0.3),
              border: Border.all(color: Colors.blue[700]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(Icons.construction_outlined,
                    color: Colors.blue, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'JS8Call DSP is under development. Settings are saved '
                    'but audio decoding/encoding is not yet active.',
                    style: TextStyle(color: Colors.blue, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),

          // ── Enable ─────────────────────────────────────────────────────
          _SectionHeader('JS8Call'),
          SwitchListTile(
            secondary: Icon(
              Icons.waves_outlined,
              color: _enabled ? Colors.green : Colors.grey,
            ),
            title: const Text('Enable JS8Call',
                style: TextStyle(color: Colors.white)),
            subtitle: const Text(
                'FM-compatible weak-signal text messaging',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            value: _enabled,
            onChanged: (v) {
              setState(() => _enabled = v);
              _markDirty();
            },
          ),

          // ── Speed ──────────────────────────────────────────────────────
          _SectionHeader('TX Speed'),
          ...(_kJs8Speeds.map((s) {
            final (label, value, desc) = s;
            return RadioListTile<String>(
              title: Text(label,
                  style: const TextStyle(color: Colors.white)),
              subtitle: Text(desc,
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 12)),
              value: value,
              groupValue: _speed,
              activeColor: Colors.blue,
              onChanged: _enabled
                  ? (v) {
                      if (v != null) {
                        setState(() => _speed = v);
                        _markDirty();
                      }
                    }
                  : null,
            );
          })),

          // ── Audio offset ───────────────────────────────────────────────
          _SectionHeader('Audio Offset'),
          ListTile(
            leading: const Icon(Icons.graphic_eq, color: Colors.white54),
            title: const Text('AF Offset',
                style: TextStyle(color: Colors.white)),
            subtitle: Text(
              '$_audioOffsetHz Hz within FM channel',
              style:
                  const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            trailing: DropdownButton<int>(
              value: _kOffsets.contains(_audioOffsetHz)
                  ? _audioOffsetHz
                  : 1500,
              dropdownColor: Colors.grey[850],
              style: const TextStyle(color: Colors.white),
              underline: const SizedBox(),
              items: _kOffsets
                  .map((o) => DropdownMenuItem(
                        value: o,
                        child: Text('$o Hz'),
                      ))
                  .toList(),
              onChanged: _enabled
                  ? (v) {
                      if (v != null) {
                        setState(() => _audioOffsetHz = v);
                        _markDirty();
                      }
                    }
                  : null,
            ),
          ),

          // ── Grid square ────────────────────────────────────────────────
          _SectionHeader('Station'),
          ListTile(
            leading: const Icon(Icons.grid_view_outlined,
                color: Colors.white54),
            title: const Text('Maidenhead Grid',
                style: TextStyle(color: Colors.white)),
            subtitle: Text(
              _grid.isEmpty ? 'Not set — used in heartbeat beacons' : _grid,
              style: TextStyle(
                color:
                    _grid.isEmpty ? Colors.white38 : Colors.green[300],
                fontSize: 12,
              ),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
            onTap: _enabled ? () => _editGrid() : null,
          ),

          // ── Heartbeat ──────────────────────────────────────────────────
          _SectionHeader('Heartbeat'),
          SwitchListTile(
            secondary: const Icon(Icons.favorite_border, color: Colors.white54),
            title: const Text('Auto Heartbeat',
                style: TextStyle(color: Colors.white)),
            subtitle: const Text(
                'Periodic @ALLCALL CQ beacon with grid square',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            value: _heartbeatEnabled,
            onChanged: _enabled
                ? (v) {
                    setState(() => _heartbeatEnabled = v);
                    _markDirty();
                  }
                : null,
          ),
          if (_heartbeatEnabled)
            _SliderTile(
              label: 'Heartbeat Interval',
              value: _heartbeatIntervalMin.toDouble(),
              min: 5,
              max: 60,
              divisions: 11,
              displayValue: '$_heartbeatIntervalMin min',
              onChanged: _enabled
                  ? (v) {
                      setState(() => _heartbeatIntervalMin = v.round());
                      _markDirty();
                    }
                  : null,
            ),

          // ── Relay ──────────────────────────────────────────────────────
          _SectionHeader('Relay & Store-and-Forward'),
          SwitchListTile(
            secondary: const Icon(Icons.repeat_outlined, color: Colors.white54),
            title: const Text('Enable Relay',
                style: TextStyle(color: Colors.white)),
            subtitle: const Text(
                'Re-transmit messages with TTL > 0 for network extension',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            value: _relayEnabled,
            onChanged: _enabled
                ? (v) {
                    setState(() => _relayEnabled = v);
                    _markDirty();
                  }
                : null,
          ),
          if (_relayEnabled)
            _SliderTile(
              label: 'Relay TTL',
              value: _relayTtl.toDouble(),
              min: 1,
              max: 8,
              divisions: 7,
              displayValue: '$_relayTtl hops',
              warn: _relayTtl > 5,
              onChanged: (v) {
                setState(() => _relayTtl = v.round());
                _markDirty();
              },
            ),
          SwitchListTile(
            secondary: const Icon(Icons.inbox_outlined, color: Colors.white54),
            title: const Text('Store and Forward',
                style: TextStyle(color: Colors.white)),
            subtitle: const Text(
                'Buffer messages for offline stations (requires relay)',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            value: _storeForwardEnabled,
            onChanged: (_relayEnabled && _enabled)
                ? (v) {
                    setState(() => _storeForwardEnabled = v);
                    _markDirty();
                  }
                : null,
          ),

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  void _editGrid() {
    final controller = TextEditingController(text: _grid);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: const Text('Maidenhead Grid Square',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
              style: const TextStyle(
                  color: Colors.white, fontFamily: 'monospace'),
              decoration: const InputDecoration(
                hintText: 'e.g. DN70',
                hintStyle: TextStyle(color: Colors.white38),
                counterStyle: TextStyle(color: Colors.white38),
              ),
            ),
            const Text(
              '4-character Maidenhead locator (field + square).\n'
              'Used in heartbeat beacons.',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              setState(
                  () => _grid = _normalizeGrid(controller.text));
              _markDirty();
              Navigator.pop(ctx);
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );
  }
}

// ── Slider tile ───────────────────────────────────────────────────────────────
class _SliderTile extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String displayValue;
  final bool warn;
  final ValueChanged<double>? onChanged;

  const _SliderTile({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.displayValue,
    this.warn = false,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white)),
          Text(
            displayValue,
            style: TextStyle(
              color: warn ? Colors.orange : Colors.white54,
              fontWeight: warn ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
      subtitle: Slider(
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        activeColor: warn ? Colors.orange : Colors.blue,
        inactiveColor: Colors.white12,
        onChanged: onChanged,
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────
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
