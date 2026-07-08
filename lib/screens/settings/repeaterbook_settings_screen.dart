// lib/screens/settings/repeaterbook_settings_screen.dart
// RepeaterBook API token — enter the app-bound token generated from
// repeaterbook.com/user/api_apps.php to unlock the Near Repeaters "Tune To"
// (RB Web API) feature. Emergency-net frequency-plan building (RB Connect app)
// does NOT need this token.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../services/repeaterbook_token_service.dart';

class RepeaterBookSettingsScreen extends StatefulWidget {
  const RepeaterBookSettingsScreen({super.key});

  @override
  State<RepeaterBookSettingsScreen> createState() =>
      _RepeaterBookSettingsScreenState();
}

class _RepeaterBookSettingsScreenState
    extends State<RepeaterBookSettingsScreen> {
  final _tokenCtrl = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _save(RepeaterBookTokenService svc) async {
    final t = _tokenCtrl.text.trim();
    if (t.isEmpty) return;
    if (!t.startsWith('rbuapp_')) {
      _snack('That doesn\'t look like a RepeaterBook app token (rbuapp_…).');
      return;
    }
    await svc.setToken(t);
    _tokenCtrl.clear();
    if (!mounted) return;
    _snack('Token saved — Near Repeaters "Tune To" unlocked.');
  }

  Future<void> _clear(RepeaterBookTokenService svc) async {
    await svc.clear();
    if (!mounted) return;
    _snack('Token removed.');
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<RepeaterBookTokenService>();
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: const Text('RepeaterBook'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Status
          Card(
            color: Colors.grey[850],
            child: ListTile(
              leading: Icon(
                svc.hasToken ? Icons.verified_user : Icons.lock_outline,
                color: svc.hasToken ? Colors.tealAccent : Colors.white38,
              ),
              title: Text(
                svc.hasToken ? 'API token set' : 'No API token',
                style: const TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                svc.hasToken
                    ? '${svc.maskedToken} · "Tune To" enabled'
                    : 'Near Repeaters "Tune To" is locked until a token is added',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          ),
          const SizedBox(height: 16),

          const Text('How to get a token',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 6),
          const Text(
            '1. Sign in to RepeaterBook.com.\n'
            '2. Open the API Apps & Tokens page (link below).\n'
            '3. Under Approved Distributed Apps, find OpenHT and tap "Generate Token".\n'
            '4. Copy the rbuapp_… token and paste it here.\n\n'
            'The token is app-bound to your RepeaterBook account. RepeaterBook '
            'shows it only once — if you lose it, rotate it and paste the new one.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(
                child: SelectableText(
                  RepeaterBookTokenService.apiAppsUrl,
                  style: TextStyle(color: Colors.tealAccent, fontSize: 12),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, color: Colors.white54, size: 18),
                tooltip: 'Copy link',
                onPressed: () {
                  Clipboard.setData(const ClipboardData(
                      text: RepeaterBookTokenService.apiAppsUrl));
                  _snack('Link copied — open it in your browser.');
                },
              ),
            ],
          ),
          const Divider(color: Colors.white24, height: 28),

          // Token entry
          TextField(
            controller: _tokenCtrl,
            obscureText: _obscure,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'RepeaterBook API token',
              hintText: 'rbuapp_…',
              labelStyle: const TextStyle(color: Colors.white70),
              hintStyle: const TextStyle(color: Colors.white30),
              enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24)),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off,
                    color: Colors.white54),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: () => _save(svc),
                icon: const Icon(Icons.save),
                label: const Text('Save token'),
              ),
              const SizedBox(width: 12),
              if (svc.hasToken)
                TextButton(
                  onPressed: () => _clear(svc),
                  child: const Text('Remove',
                      style: TextStyle(color: Colors.redAccent)),
                ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            RepeaterBookTokenService.attribution,
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
