// lib/screens/settings/spotter_network_settings_screen.dart
// Spotter Network sign-in, location reporting, and map display settings.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/spotter_network_service.dart';

class SpotterNetworkSettingsScreen extends StatefulWidget {
  const SpotterNetworkSettingsScreen({super.key});

  @override
  State<SpotterNetworkSettingsScreen> createState() =>
      _SpotterNetworkSettingsScreenState();
}

class _SpotterNetworkSettingsScreenState
    extends State<SpotterNetworkSettingsScreen> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _signingIn = false;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn(SpotterNetworkService svc) async {
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (username.isEmpty || password.isEmpty) return;
    setState(() => _signingIn = true);
    await svc.signIn(username, password);
    _passwordCtrl.clear();
    if (!mounted) return;
    setState(() => _signingIn = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Signed in to Spotter Network'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _signOut(SpotterNetworkService svc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: const Text('Sign Out',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'Sign out of Spotter Network?\nLocation reporting will stop.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[700]),
              child: const Text('Sign Out')),
        ],
      ),
    );
    if (confirmed == true) await svc.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<SpotterNetworkService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Spotter Network')),
      body: ListView(
        children: [
          // ─── Account ──────────────────────────────────
          _SectionHeader('Account'),
          if (!svc.isSignedIn) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _usernameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      labelStyle: TextStyle(color: Colors.white54),
                      hintText: 'spotternetwork.org username',
                      hintStyle: TextStyle(color: Colors.white24),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _passwordCtrl,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      labelStyle: const TextStyle(color: Colors.white54),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: Colors.white38,
                        ),
                        onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: _signingIn
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.login),
                    label: Text(_signingIn ? 'Signing in…' : 'Sign In'),
                    onPressed: _signingIn ? null : () => _signIn(svc),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Account required at spotternetwork.org to report your location.',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ] else ...[
            ListTile(
              leading: const Icon(Icons.account_circle, color: Colors.green),
              title: const Text('Signed in as',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              subtitle: Text(
                svc.username ?? '',
                style: const TextStyle(
                  color: Colors.green,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              trailing: TextButton(
                onPressed: () => _signOut(svc),
                child: const Text('Sign Out',
                    style: TextStyle(color: Colors.red)),
              ),
            ),
          ],

          // ─── Map Display ──────────────────────────────
          _SectionHeader('Map Display'),
          SwitchListTile(
            secondary: Icon(
              Icons.person_pin_circle_outlined,
              color: svc.showOnMap ? Colors.orange : Colors.grey,
            ),
            title: const Text('Show Spotters on Map',
                style: TextStyle(color: Colors.white)),
            subtitle: Text(
              svc.showOnMap
                  ? '${svc.spotters.length} spotter(s) from gr.txt feed'
                  : 'Orange markers on the APRS map',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            value: svc.showOnMap,
            onChanged: svc.setShowOnMap,
          ),
          if (svc.isSignedIn)
            SwitchListTile(
              secondary: Icon(
                Icons.my_location,
                color: svc.showMyLocation ? Colors.blue : Colors.grey,
              ),
              title: const Text('Show My Location',
                  style: TextStyle(color: Colors.white)),
              subtitle: const Text(
                'Display your position on the spotter map',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              value: svc.showMyLocation,
              onChanged: svc.setShowMyLocation,
            ),

          // ─── Nearby Alerts ────────────────────────────
          _SectionHeader('Nearby Alerts'),
          SwitchListTile(
            secondary: Icon(
              Icons.notifications_active_outlined,
              color: svc.notifyNearby ? Colors.orange : Colors.grey,
            ),
            title: const Text('Notify for Nearby Spotters',
                style: TextStyle(color: Colors.white)),
            subtitle: const Text(
              'Alert when storm spotters are in your area',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            value: svc.notifyNearby,
            onChanged: svc.setNotifyNearby,
          ),
          if (svc.notifyNearby) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.social_distance, color: Colors.orange, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Radius: ${svc.notifyRadiusMi.toStringAsFixed(0)} mi',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
            Slider(
              value: svc.notifyRadiusMi,
              min: 5,
              max: 100,
              divisions: 19,
              label: '${svc.notifyRadiusMi.toStringAsFixed(0)} mi',
              activeColor: Colors.orange,
              onChanged: svc.setNotifyRadius,
            ),
          ],

          // ─── Feed Info ────────────────────────────────
          _SectionHeader('Feed Information'),
          ListTile(
            leading: const Icon(Icons.info_outline, color: Colors.white38),
            title: const Text('Public Feed',
                style: TextStyle(color: Colors.white70)),
            subtitle: const Text(
              'spotternetwork.org/feeds/gr.txt\nUpdates every 5 minutes',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
            isThreeLine: true,
          ),
          if (svc.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red[900],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  svc.error!,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ),

          const SizedBox(height: 80),
        ],
      ),
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
