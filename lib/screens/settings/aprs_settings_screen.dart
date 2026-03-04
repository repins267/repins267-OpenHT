// lib/screens/settings/aprs_settings_screen.dart
// APRS / BSS settings — mirrors VR-N76 on-radio menus exactly
// Sections: Station, APRS-IS, Digital Mode, Beacon, Digipeater/Relay, BSS

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── APRS passcode algorithm (standard hash, KC0AXJ) ─────────────────────────
int computeAprsPasscode(String callsign) {
  final base = callsign.split('-').first.toUpperCase();
  int hash = 0x73e2;
  for (int i = 0; i < base.length; i += 2) {
    hash ^= base.codeUnitAt(i) << 8;
    if (i + 1 < base.length) hash ^= base.codeUnitAt(i + 1);
  }
  return hash & 0x7FFF;
}

// ─── Common APRS paths ────────────────────────────────────────────────────────
const _kCommonPaths = [
  'WIDE1-1',
  'WIDE1-1,WIDE2-1',
  'WIDE2-1',
  'WIDE2-2',
  'RELAY,WIDE',
];

// ─── Common APRS symbols (table char + symbol char + display label) ───────────
const _kSymbols = [
  ('/', '>', 'Car'),
  ('/', '-', 'House'),
  ('/', '[', 'Jogger'),
  ('/', '_', 'Wx Stn'),
  ('/', '^', 'Aircraft'),
  ('/', 'k', 'Truck'),
  ('/', 'O', 'Balloon'),
  ('/', 'Y', 'Sailboat'),
  ('/', 's', 'Ship'),
  ('/', 'j', 'Jeep'),
  ('/', '*', 'Star'),
  ('/', 'R', 'Repeater'),
];

// ─── Share location intervals ─────────────────────────────────────────────────
const _kIntervals = [
  ('Off', '0'),
  ('5s',  '5'),
  ('10s', '10'),
  ('15s', '15'),
  ('30s', '30'),
  ('1m',  '60'),
  ('2m',  '120'),
  ('5m',  '300'),
  ('10m', '600'),
];

class AprsSettingsScreen extends StatefulWidget {
  const AprsSettingsScreen({super.key});

  @override
  State<AprsSettingsScreen> createState() => _AprsSettingsScreenState();
}

class _AprsSettingsScreenState extends State<AprsSettingsScreen> {
  // Station
  String _callsign = '';
  int    _ssid     = 7;
  int    _passcode = -1; // -1 = receive-only

  // APRS-IS
  String _server   = 'rotate.aprs2.net';
  int    _filterKm = 50;

  // Path
  String _path = 'WIDE1-1';

  // Symbol
  String _symbolTable = '/';
  String _symbolChar  = '>';

  // Digital Mode (mirrors on-radio Digital Mode menu)
  bool   _digitalModeEnabled  = false;
  String _shareLocInterval    = '0'; // seconds
  int    _digitalChannel      = 0;
  bool   _bssMode             = false; // false=APRS, true=BSS

  // Beacon
  String _beaconComment  = '';
  bool   _smartBeaconing = false;
  int    _beaconIntervalMin = 5;

  // Digipeater / Relay (mirrors on-radio Signaling menu)
  bool _digiEnabled = false;
  int  _digiTtl     = 3; // 0-8
  int  _digiMaxHops = 3; // 0-8

  bool _isDirty = false;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _callsign           = prefs.getString('callsign')                  ?? '';
      _ssid               = prefs.getInt('aprs_ssid')                    ?? 7;
      _passcode           = prefs.getInt('aprs_passcode')                ?? -1;
      _server             = prefs.getString('aprs_server')               ?? 'rotate.aprs2.net';
      _filterKm           = prefs.getInt('aprs_filter_km')               ?? 50;
      _path               = prefs.getString('aprs_path')                 ?? 'WIDE1-1';
      _symbolTable        = prefs.getString('aprs_symbol_table')         ?? '/';
      _symbolChar         = prefs.getString('aprs_symbol_char')          ?? '>';
      _digitalModeEnabled = prefs.getBool('aprs_digital_mode')           ?? false;
      _shareLocInterval   = prefs.getString('aprs_share_loc_interval')   ?? '0';
      _digitalChannel     = prefs.getInt('aprs_digital_channel')         ?? 0;
      _bssMode            = prefs.getBool('aprs_bss_mode')               ?? false;
      _beaconComment      = prefs.getString('aprs_beacon_comment')       ?? '';
      _smartBeaconing     = prefs.getBool('aprs_smart_beaconing')        ?? false;
      _beaconIntervalMin  = prefs.getInt('aprs_beacon_interval_min')     ?? 5;
      _digiEnabled        = prefs.getBool('aprs_digipeater')             ?? false;
      _digiTtl            = prefs.getInt('aprs_digi_ttl')                ?? 3;
      _digiMaxHops        = prefs.getInt('aprs_digi_max_hops')           ?? 3;
      // Auto-compute passcode from loaded callsign
      if (_callsign.isNotEmpty && _passcode == -1) {
        _passcode = computeAprsPasscode(_callsign);
      }
      _isDirty = false;
    });
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('callsign',                  _callsign);
    await prefs.setInt   ('aprs_ssid',                 _ssid);
    await prefs.setInt   ('aprs_passcode',             _passcode);
    await prefs.setString('aprs_server',               _server);
    await prefs.setInt   ('aprs_filter_km',            _filterKm);
    await prefs.setString('aprs_path',                 _path);
    await prefs.setString('aprs_symbol_table',         _symbolTable);
    await prefs.setString('aprs_symbol_char',          _symbolChar);
    await prefs.setBool  ('aprs_digital_mode',         _digitalModeEnabled);
    await prefs.setString('aprs_share_loc_interval',   _shareLocInterval);
    await prefs.setInt   ('aprs_digital_channel',      _digitalChannel);
    await prefs.setBool  ('aprs_bss_mode',             _bssMode);
    await prefs.setString('aprs_beacon_comment',       _beaconComment);
    await prefs.setBool  ('aprs_smart_beaconing',      _smartBeaconing);
    await prefs.setInt   ('aprs_beacon_interval_min',  _beaconIntervalMin);
    await prefs.setBool  ('aprs_digipeater',           _digiEnabled);
    await prefs.setInt   ('aprs_digi_ttl',             _digiTtl);
    await prefs.setInt   ('aprs_digi_max_hops',        _digiMaxHops);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('APRS settings saved'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _markDirty() => setState(() => _isDirty = true);

  Future<void> _testConnection() async {
    setState(() => _testing = true);
    try {
      final socket = await Socket.connect(_server, 14580,
          timeout: const Duration(seconds: 5));
      final completer = Completer<String>();
      late StreamSubscription<String> sub;
      sub = socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .listen((data) {
        if (!completer.isCompleted) {
          completer.complete(data);
          sub.cancel();
        }
      }, onError: (e) {
        if (!completer.isCompleted) completer.completeError(e);
      });
      final banner = await completer.future
          .timeout(const Duration(seconds: 5));
      socket.destroy();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Connected: ${banner.split('\n').first.trim()}'),
          backgroundColor: Colors.green[700],
          duration: const Duration(seconds: 4),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Connection failed: $e'),
          backgroundColor: Colors.red[700],
          duration: const Duration(seconds: 4),
        ));
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  bool get _canSave =>
      _callsign.isNotEmpty &&
      _path.isNotEmpty &&
      (!_digiEnabled || _digiTtl > 0);

  String get _sourceAddress => '$_callsign-$_ssid';

  String get _formatLabel => _bssMode ? 'BSS' : 'APRS';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('APRS / BSS Settings'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: (_canSave && _isDirty) ? _save : null,
            child: Text(
              'Save',
              style: TextStyle(
                  color: (_canSave && _isDirty) ? Colors.white : Colors.white38,
                  fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: ListView(
        children: [

          // ─── Station Identity ─────────────────────────
          _SectionHeader('Station Identity'),
          ListTile(
            leading: const Icon(Icons.badge_outlined, color: Colors.green),
            title: const Text('Callsign', style: TextStyle(color: Colors.white)),
            subtitle: Text(
              _callsign.isEmpty ? 'Required — tap to set' : _callsign,
              style: TextStyle(
                  color: _callsign.isEmpty ? Colors.red[400] : Colors.green[300]),
            ),
            trailing: const Icon(Icons.edit, color: Colors.white38, size: 18),
            onTap: () => _editCallsign(),
          ),
          ListTile(
            leading: const Icon(Icons.tag, color: Colors.blue),
            title: const Text('SSID', style: TextStyle(color: Colors.white)),
            subtitle: Text(
              '$_sourceAddress  ·  ${_ssidHint(_ssid)}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            trailing: SizedBox(
              width: 90,
              child: DropdownButton<int>(
                value: _ssid.clamp(0, 15),
                dropdownColor: Colors.grey[850],
                isExpanded: true,
                items: List.generate(
                  16,
                  (i) => DropdownMenuItem(
                    value: i,
                    child: Text('$i${_ssidHintShort(i)}',
                        style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ),
                onChanged: (v) {
                  setState(() {
                    _ssid = v ?? 7;
                    if (_callsign.isNotEmpty) {
                      _passcode = computeAprsPasscode(_callsign);
                    }
                  });
                  _markDirty();
                },
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.key_outlined, color: Colors.orange),
            title: const Text('Passcode', style: TextStyle(color: Colors.white)),
            subtitle: Text(
              _passcode == -1
                  ? '-1 (receive-only — set callsign to compute)'
                  : '$_passcode  (auto-computed from callsign)',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            trailing: TextButton(
              onPressed: _callsign.isEmpty ? null : () {
                setState(() => _passcode = computeAprsPasscode(_callsign));
                _markDirty();
              },
              child: const Text('Recompute', style: TextStyle(fontSize: 11)),
            ),
          ),

          // ─── APRS-IS Connection ───────────────────────
          _SectionHeader('APRS-IS Connection'),
          ListTile(
            leading: const Icon(Icons.dns_outlined, color: Colors.blue),
            title: const Text('Server', style: TextStyle(color: Colors.white)),
            subtitle: Text('$_server:14580',
                style: const TextStyle(
                    color: Colors.white54, fontSize: 12, fontFamily: 'monospace')),
            trailing: const Icon(Icons.edit, color: Colors.white38, size: 18),
            onTap: () => _editServer(),
          ),
          ListTile(
            leading: const Icon(Icons.network_check, color: Colors.cyan),
            title: const Text('Test Connection',
                style: TextStyle(color: Colors.white)),
            subtitle: Text('$_server:14580',
                style: const TextStyle(
                    color: Colors.white54, fontSize: 12, fontFamily: 'monospace')),
            trailing: _testing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    icon: const Icon(Icons.play_circle_outline,
                        color: Colors.cyan),
                    tooltip: 'Test APRS-IS connection',
                    onPressed: _testConnection,
                  ),
          ),
          ListTile(
            leading: const Icon(Icons.radar, color: Colors.blue),
            title: const Text('Range Filter', style: TextStyle(color: Colors.white)),
            subtitle: Text('Receive packets within $_filterKm km',
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
            trailing: SizedBox(
              width: 100,
              child: DropdownButton<int>(
                value: _filterKm,
                dropdownColor: Colors.grey[850],
                isExpanded: true,
                items: [10, 25, 50, 100, 200, 500].map((km) => DropdownMenuItem(
                  value: km,
                  child: Text('$km km', style: const TextStyle(color: Colors.white)),
                )).toList(),
                onChanged: (v) {
                  setState(() => _filterKm = v ?? 50);
                  _markDirty();
                },
              ),
            ),
          ),

          // ─── Digipeater Path ──────────────────────────
          _SectionHeader('Digipeater Path'),
          ListTile(
            leading: Icon(Icons.route,
                color: _path.isEmpty ? Colors.red : Colors.orange),
            title: const Text('Path', style: TextStyle(color: Colors.white)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _path.isEmpty ? '⚠ Required — must not be empty' : _path,
                  style: TextStyle(
                    color: _path.isEmpty ? Colors.red[400] : Colors.orange[300],
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: _kCommonPaths.map((p) => GestureDetector(
                    onTap: () {
                      setState(() => _path = p);
                      _markDirty();
                    },
                    child: Chip(
                      label: Text(p, style: const TextStyle(fontSize: 10)),
                      backgroundColor:
                          _path == p ? Colors.orange[900] : Colors.grey[700],
                      side: BorderSide.none,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: EdgeInsets.zero,
                    ),
                  )).toList(),
                ),
              ],
            ),
            trailing: const Icon(Icons.edit, color: Colors.white38, size: 18),
            onTap: () => _editPath(),
          ),

          // ─── Symbol ───────────────────────────────────
          _SectionHeader('Station Symbol'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _kSymbols.map((sym) {
                final isSelected =
                    _symbolTable == sym.$1 && _symbolChar == sym.$2;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _symbolTable = sym.$1;
                      _symbolChar  = sym.$2;
                    });
                    _markDirty();
                  },
                  child: Container(
                    width: 72,
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.blue[900] : Colors.grey[800],
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isSelected ? Colors.blue : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          sym.$2,
                          style: TextStyle(
                            color: isSelected ? Colors.blue[200] : Colors.white70,
                            fontSize: 18,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          sym.$3,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white54,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // ─── Digital Mode ─────────────────────────────
          _SectionHeader('Digital Mode'),
          SwitchListTile(
            secondary: Icon(Icons.wifi,
                color: _digitalModeEnabled ? Colors.green : Colors.grey),
            title: const Text('Enable Digital Mode',
                style: TextStyle(color: Colors.white)),
            subtitle: Text(
              _digitalModeEnabled
                  ? 'Format: $_formatLabel · Ch: $_digitalChannel'
                  : 'Mirrors on-radio "Digital Mode → Enable"',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            value: _digitalModeEnabled,
            onChanged: (v) {
              setState(() => _digitalModeEnabled = v);
              _markDirty();
            },
          ),
          if (_digitalModeEnabled) ...[
            ListTile(
              leading: const Icon(Icons.swap_horiz, color: Colors.purple),
              title: const Text('Format', style: TextStyle(color: Colors.white)),
              subtitle: Text(
                _bssMode
                    ? 'BSS (Benshi Special Signaling)'
                    : 'APRS (standard position reporting)',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              trailing: ToggleButtons(
                isSelected: [!_bssMode, _bssMode],
                onPressed: (i) {
                  setState(() => _bssMode = i == 1);
                  _markDirty();
                },
                color: Colors.white54,
                selectedColor: Colors.white,
                fillColor: Colors.blue[800],
                borderRadius: BorderRadius.circular(6),
                constraints:
                    const BoxConstraints(minWidth: 56, minHeight: 32),
                children: const [
                  Text('APRS', style: TextStyle(fontSize: 12)),
                  Text('BSS',  style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.schedule, color: Colors.teal),
              title: const Text('Share Location Interval',
                  style: TextStyle(color: Colors.white)),
              subtitle: const Text(
                  'Mirrors on-radio "Share Location" interval',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              trailing: SizedBox(
                width: 90,
                child: DropdownButton<String>(
                  value: _shareLocInterval,
                  dropdownColor: Colors.grey[850],
                  isExpanded: true,
                  items: _kIntervals.map((iv) => DropdownMenuItem(
                    value: iv.$2,
                    child: Text(iv.$1,
                        style: const TextStyle(color: Colors.white, fontSize: 12)),
                  )).toList(),
                  onChanged: (v) {
                    setState(() => _shareLocInterval = v ?? '0');
                    _markDirty();
                  },
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.tune, color: Colors.teal),
              title: const Text('Digital Channel',
                  style: TextStyle(color: Colors.white)),
              subtitle: const Text('Channel number for digital data TX',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              trailing: SizedBox(
                width: 80,
                child: DropdownButton<int>(
                  value: _digitalChannel.clamp(0, 127),
                  dropdownColor: Colors.grey[850],
                  isExpanded: true,
                  items: List.generate(128, (i) => DropdownMenuItem(
                    value: i,
                    child: Text('Ch ${i + 1}',
                        style: const TextStyle(color: Colors.white, fontSize: 12)),
                  )),
                  onChanged: (v) {
                    setState(() => _digitalChannel = v ?? 0);
                    _markDirty();
                  },
                ),
              ),
            ),
          ],

          // ─── Beacon ───────────────────────────────────
          _SectionHeader('Beacon'),
          ListTile(
            leading: const Icon(Icons.wifi_tethering, color: Colors.green),
            title: const Text('Beacon Comment',
                style: TextStyle(color: Colors.white)),
            subtitle: Text(
              _beaconComment.isEmpty ? 'Empty (tap to set)' : _beaconComment,
              style: TextStyle(
                  color: _beaconComment.isEmpty ? Colors.white38 : Colors.white70,
                  fontSize: 12),
            ),
            trailing: Text(
              '${_beaconComment.length}/43',
              style: TextStyle(
                  color: _beaconComment.length > 43 ? Colors.red : Colors.white38,
                  fontSize: 11),
            ),
            onTap: () => _editBeaconComment(),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.auto_mode, color: Colors.blue),
            title: const Text('Smart Beaconing',
                style: TextStyle(color: Colors.white)),
            subtitle: const Text(
                'Adjusts interval based on speed and direction change',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            value: _smartBeaconing,
            onChanged: (v) {
              setState(() => _smartBeaconing = v);
              _markDirty();
            },
          ),
          if (!_smartBeaconing)
            ListTile(
              leading: const Icon(Icons.timer_outlined, color: Colors.blue),
              title: const Text('Beacon Interval',
                  style: TextStyle(color: Colors.white)),
              subtitle: Text('Every $_beaconIntervalMin minute(s)',
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              trailing: SizedBox(
                width: 100,
                child: DropdownButton<int>(
                  value: _beaconIntervalMin,
                  dropdownColor: Colors.grey[850],
                  isExpanded: true,
                  items: [1, 2, 5, 10, 15, 30].map((m) => DropdownMenuItem(
                    value: m,
                    child: Text('$m min',
                        style: const TextStyle(color: Colors.white)),
                  )).toList(),
                  onChanged: (v) {
                    setState(() => _beaconIntervalMin = v ?? 5);
                    _markDirty();
                  },
                ),
              ),
            ),

          // ─── Digipeater / Relay ───────────────────────
          _SectionHeader('Digipeater / Relay'),
          SwitchListTile(
            secondary: Icon(Icons.repeat,
                color: _digiEnabled ? Colors.green : Colors.grey),
            title: const Text('Enable Digipeater',
                style: TextStyle(color: Colors.white)),
            subtitle: const Text(
                'Mirrors on-radio "Signaling → Digipeater"',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            value: _digiEnabled,
            onChanged: (v) {
              setState(() => _digiEnabled = v);
              _markDirty();
            },
          ),
          if (_digiEnabled) ...[
            _SliderTile(
              icon: Icons.timer,
              iconColor: _digiTtl == 0 ? Colors.red : Colors.orange,
              title: 'Digipeater TTL',
              subtitle: _digiTtl == 0
                  ? '⚠ TTL must be > 0 to relay packets'
                  : 'Packets re-broadcasted $_digiTtl time(s)',
              value: _digiTtl.toDouble(),
              min: 0,
              max: 8,
              divisions: 8,
              activeColor: _digiTtl == 0 ? Colors.red : Colors.orange,
              onChanged: (v) {
                setState(() => _digiTtl = v.round());
                _markDirty();
              },
            ),
            _SliderTile(
              icon: Icons.device_hub,
              iconColor: _digiMaxHops == 0 ? Colors.red : Colors.orange,
              title: 'Max Hops',
              subtitle: _digiMaxHops == 0
                  ? '⚠ Hops must be > 0 to relay packets'
                  : 'Relay up to $_digiMaxHops hops',
              value: _digiMaxHops.toDouble(),
              min: 0,
              max: 8,
              divisions: 8,
              activeColor: _digiMaxHops == 0 ? Colors.red : Colors.orange,
              onChanged: (v) {
                setState(() => _digiMaxHops = v.round());
                _markDirty();
              },
            ),
          ],

          if (!_canSave)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red[900],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber, color: Colors.white, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _callsign.isEmpty
                          ? 'Callsign is required before saving.'
                          : _path.isEmpty
                              ? 'Path must not be empty.'
                              : 'Digipeater TTL must be > 0 when digipeater is enabled.',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ─── Edit dialogs ────────────────────────────────────────────────────────────

  void _editCallsign() {
    final ctl = TextEditingController(text: _callsign);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: const Text('Callsign', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctl,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
              hintText: 'e.g. KF0JKE',
              hintStyle: TextStyle(color: Colors.white38)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final v = ctl.text.trim().toUpperCase();
              setState(() {
                _callsign = v;
                if (v.isNotEmpty) _passcode = computeAprsPasscode(v);
              });
              _markDirty();
              Navigator.pop(ctx);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _editPath() {
    final ctl = TextEditingController(text: _path);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: const Text('Digipeater Path', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctl,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
          decoration: const InputDecoration(
              hintText: 'e.g. WIDE1-1,WIDE2-1',
              hintStyle: TextStyle(color: Colors.white38)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              setState(() => _path = ctl.text.trim().toUpperCase());
              _markDirty();
              Navigator.pop(ctx);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _editServer() {
    final ctl = TextEditingController(text: _server);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: const Text('APRS-IS Server', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctl,
          style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
          decoration: const InputDecoration(
              hintText: 'rotate.aprs2.net',
              hintStyle: TextStyle(color: Colors.white38)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              setState(() => _server = ctl.text.trim());
              _markDirty();
              Navigator.pop(ctx);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _editBeaconComment() {
    final ctl = TextEditingController(text: _beaconComment);
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => AlertDialog(
          backgroundColor: Colors.grey[850],
          title:
              const Text('Beacon Comment', style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: ctl,
            maxLength: 43,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'e.g. OpenHT KF0JKE mobile',
              hintStyle: TextStyle(color: Colors.white38),
              counterStyle: TextStyle(color: Colors.white38),
            ),
            onChanged: (_) => setSheetState(() {}),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                setState(() => _beaconComment = ctl.text.trim());
                _markDirty();
                Navigator.pop(ctx);
              },
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── SSID convention helpers ──────────────────────────────────────────────────
String _ssidHint(int ssid) {
  const hints = {
    0: 'Base/Fixed',
    1: 'No override',
    2: 'No override',
    3: 'No override',
    5: 'IGate/Node',
    6: 'Mobile ops',
    7: 'Handheld (HT)',
    8: 'Boat/marine',
    9: 'Mobile vehicle',
    10: 'Internet link',
    11: 'Balloon',
    12: 'APO',
    14: 'Wires-X',
    15: 'Gateway',
  };
  return hints[ssid] ?? 'No override';
}

String _ssidHintShort(int ssid) {
  const hints = {0: ' Base', 7: ' HT', 9: ' Car', 5: ' IGate'};
  return hints[ssid] != null ? ' (${hints[ssid]})' : '';
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

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

class _SliderTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final Color activeColor;
  final ValueChanged<double> onChanged;

  const _SliderTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.activeColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(color: Colors.white, fontSize: 14)),
                    Text(subtitle,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ),
              Text(
                value.round().toString(),
                style:
                    TextStyle(color: activeColor, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            activeColor: activeColor,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
