// lib/screens/settings/auth_settings_screen.dart
// Message Authentication settings — HMAC pre-shared keys for APRS messages

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/aprs_auth_service.dart';

class AuthSettingsScreen extends StatefulWidget {
  const AuthSettingsScreen({super.key});

  @override
  State<AuthSettingsScreen> createState() => _AuthSettingsScreenState();
}

class _AuthSettingsScreenState extends State<AuthSettingsScreen> {
  bool _hasMasterKey = false;
  bool _loadingKey = true;

  @override
  void initState() {
    super.initState();
    _checkKey();
  }

  Future<void> _checkKey() async {
    final auth = context.read<AprsAuthService>();
    final has = await auth.hasMasterKey();
    if (!mounted) return;
    setState(() {
      _hasMasterKey = has;
      _loadingKey = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AprsAuthService>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Message Authentication'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        children: [
          // ── Legal banner ──────────────────────────────────────────────────
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange[900]!.withOpacity(0.35),
              border: Border.all(color: Colors.orange[700]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: Colors.orange, size: 18),
                    SizedBox(width: 6),
                    Text('AUTHENTICATION ≠ ENCRYPTION',
                        style: TextStyle(
                            color: Colors.orange,
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                  ],
                ),
                SizedBox(height: 6),
                Text(
                  'Message text remains fully readable on-air. The auth tag '
                  'only verifies the sender\'s identity — it does not hide '
                  'content. Amateur radio regulations (§97.113) prohibit '
                  'obscuring the meaning of transmissions.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),

          // ── Master toggle ─────────────────────────────────────────────────
          _SectionHeader('Authentication'),
          SwitchListTile(
            secondary: Icon(
              Icons.verified_user_outlined,
              color: auth.enabled ? Colors.green : Colors.grey,
            ),
            title: const Text('Enable Message Authentication',
                style: TextStyle(color: Colors.white)),
            subtitle: Text(
              auth.enabled
                  ? 'Outgoing messages tagged · Incoming verified'
                  : 'Off — messages sent without auth tag',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            value: auth.enabled,
            onChanged: (v) async {
              if (v && !_hasMasterKey) {
                _showSetKeyDialog(isMaster: true);
                return;
              }
              await auth.setEnabled(v);
            },
          ),

          // ── Master key ────────────────────────────────────────────────────
          _SectionHeader('Master Key'),
          ListTile(
            leading: Icon(
              _hasMasterKey ? Icons.key : Icons.key_off_outlined,
              color: _hasMasterKey ? Colors.green : Colors.white38,
            ),
            title: Text(
              _hasMasterKey ? 'Master key set' : 'No master key',
              style: TextStyle(
                color: _hasMasterKey ? Colors.white : Colors.white54,
              ),
            ),
            subtitle: Text(
              _hasMasterKey
                  ? 'Used to sign all outgoing messages'
                  : 'Set a key to enable signing outgoing messages',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            trailing: _loadingKey
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () => _showSetKeyDialog(isMaster: true),
                        child: Text(_hasMasterKey ? 'Change' : 'Set Key'),
                      ),
                      if (_hasMasterKey)
                        TextButton(
                          onPressed: _deleteMasterKey,
                          child: const Text('Remove',
                              style: TextStyle(color: Colors.red)),
                        ),
                    ],
                  ),
          ),

          // ── Trusted stations ──────────────────────────────────────────────
          _SectionHeader('Trusted Stations'),
          if (auth.trustedStations.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'No trusted stations. Add a station and its shared key to '
                'verify incoming messages from that callsign.',
                style: TextStyle(color: Colors.white38, fontSize: 13),
              ),
            )
          else
            ...auth.trustedStations.map((s) => _StationTile(
                  station: s,
                  onSetKey: () =>
                      _showSetKeyDialog(isMaster: false, callsign: s.callsign),
                  onRemove: () => _removeStation(s.callsign),
                )),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('Add Trusted Station'),
              onPressed: () => _showAddStationDialog(),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.blue[300],
                side: BorderSide(color: Colors.blue[700]!),
              ),
            ),
          ),

          // ── Security best practices ───────────────────────────────────────
          _SectionHeader('Security Notes'),
          const _SecurityNote(
            icon: Icons.sync_outlined,
            text: 'Share keys out-of-band (e.g. in person or via encrypted '
                'message). Never transmit keys over radio.',
          ),
          const _SecurityNote(
            icon: Icons.schedule_outlined,
            text: 'Rotate keys periodically. Remove stations you no longer '
                'trust by tapping "Remove" above.',
          ),
          const _SecurityNote(
            icon: Icons.lock_outlined,
            text: 'Keys are stored in Android Keystore encrypted storage and '
                'are never included in backups.',
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  void _showSetKeyDialog({required bool isMaster, String? callsign}) {
    final controller = TextEditingController();
    bool obscure = true;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: Colors.grey[850],
          title: Text(
            isMaster ? 'Set Master Key' : 'Set Key for $callsign',
            style: const TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                obscureText: obscure,
                autocorrect: false,
                style: const TextStyle(
                    color: Colors.white, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: 'Enter pre-shared key',
                  hintStyle: const TextStyle(color: Colors.white38),
                  suffixIcon: IconButton(
                    icon: Icon(
                        obscure ? Icons.visibility_off : Icons.visibility,
                        color: Colors.white54),
                    onPressed: () => setDlgState(() => obscure = !obscure),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Use a strong random key (16+ characters). '
                'Agree on the same key with your contact.',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final key = controller.text.trim();
                if (key.isEmpty) return;
                final auth = context.read<AprsAuthService>();
                if (isMaster) {
                  await auth.setMasterKey(key);
                  setState(() => _hasMasterKey = true);
                } else if (callsign != null) {
                  await auth.addStation(callsign, key);
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddStationDialog() {
    final callController = TextEditingController();
    final keyController = TextEditingController();
    bool obscure = true;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: Colors.grey[850],
          title: const Text('Add Trusted Station',
              style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: callController,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(
                    color: Colors.white, fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  labelText: 'Callsign',
                  labelStyle: TextStyle(color: Colors.white54),
                  hintText: 'e.g. W0ABC-9',
                  hintStyle: TextStyle(color: Colors.white38),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: keyController,
                obscureText: obscure,
                autocorrect: false,
                style: const TextStyle(
                    color: Colors.white, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  labelText: 'Shared Key',
                  labelStyle: const TextStyle(color: Colors.white54),
                  hintText: 'Pre-shared key',
                  hintStyle: const TextStyle(color: Colors.white38),
                  suffixIcon: IconButton(
                    icon: Icon(
                        obscure ? Icons.visibility_off : Icons.visibility,
                        color: Colors.white54),
                    onPressed: () => setDlgState(() => obscure = !obscure),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final call = callController.text.trim().toUpperCase();
                final key = keyController.text.trim();
                if (call.isEmpty || key.isEmpty) return;
                await context.read<AprsAuthService>().addStation(call, key);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteMasterKey() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: const Text('Remove Master Key',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will disable signing of outgoing messages. Continue?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final auth = context.read<AprsAuthService>();
    await auth.deleteMasterKey();
    await auth.setEnabled(false);
    setState(() => _hasMasterKey = false);
  }

  Future<void> _removeStation(String callsign) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: Text('Remove $callsign', style: const TextStyle(color: Colors.white)),
        content: const Text(
          'Messages from this station will no longer be verified.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<AprsAuthService>().removeStation(callsign);
  }
}

// ── Trusted station tile ──────────────────────────────────────────────────────
class _StationTile extends StatelessWidget {
  final TrustedStation station;
  final VoidCallback onSetKey;
  final VoidCallback onRemove;

  const _StationTile({
    required this.station,
    required this.onSetKey,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      color: Colors.grey[850],
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Color(0xFF1A3A1A),
          child: Icon(Icons.verified_user, color: Colors.green, size: 20),
        ),
        title: Text(station.callsign,
            style: const TextStyle(
                color: Colors.white, fontFamily: 'monospace')),
        subtitle: Text(
          'Added ${_formatDate(station.addedAt)}',
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.key, color: Colors.blue, size: 20),
              tooltip: 'Change key',
              onPressed: onSetKey,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
              tooltip: 'Remove station',
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')}';
  }
}

// ── Security note widget ──────────────────────────────────────────────────────
class _SecurityNote extends StatelessWidget {
  final IconData icon;
  final String text;
  const _SecurityNote({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.white38),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ),
        ],
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
