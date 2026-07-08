// lib/screens/settings/emergency_nets_screen.dart
// Emergency-Net frequency-plan builder. Pulls ARES/RACES/SKYWARN repeaters within
// a radius from the RepeaterBook Connect app, filtered to the radio's usable
// bands (2m/70cm, analog FM), and writes them to Channel Group 4 as a plan.
//
// This is the only path that programs RepeaterBook emergency-net data, and it
// only targets Group 4. Requires the RepeaterBook Connect app installed.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../bluetooth/radio_service.dart';
import '../../services/gps_service.dart';
import '../../services/repeaterbook_connect_service.dart';
import '../../services/freq_plan_service.dart';

const int kEmergencyNetGroupIndex = 3; // UI Group 4

class EmergencyNetsScreen extends StatefulWidget {
  const EmergencyNetsScreen({super.key});

  @override
  State<EmergencyNetsScreen> createState() => _EmergencyNetsScreenState();
}

class _EmergencyNetsScreenState extends State<EmergencyNetsScreen> {
  static const double _radiusMiles = 150;

  List<RbConnectRepeater>? _nets;
  bool _loading = false;
  bool _writing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      if (!await RepeaterBookConnectService.isInstalled()) {
        setState(() { _error = 'RepeaterBook Connect app is not installed. '
            'Install it and load your area, then try again.'; _loading = false; });
        return;
      }
      final gps = context.read<GpsService>();
      final lat = gps.latitude, lon = gps.longitude;
      if (lat == null || lon == null) {
        setState(() { _error = 'No GPS fix yet — location is needed to filter nearby nets.';
          _loading = false; });
        return;
      }
      final nets = await RepeaterBookConnectService.emergencyNetsNear(
        lat: lat, lon: lon, radiusMiles: _radiusMiles);
      if (!mounted) return;
      setState(() { _nets = nets; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = 'Failed to load emergency nets: $e'; _loading = false; });
    }
  }

  Future<void> _writeToGroup4() async {
    final radio = context.read<RadioService>();
    final nets = _nets ?? const <RbConnectRepeater>[];
    if (!radio.isConnected) { _snack('Radio not connected'); return; }
    if (nets.isEmpty) { _snack('No emergency nets to write'); return; }

    final channels = <FreqPlanChannel>[];
    for (int i = 0; i < nets.length && i < 32; i++) {
      final r = nets[i];
      channels.add(FreqPlanChannel(
        slot: i,
        name: r.callsign.length > 10 ? r.callsign.substring(0, 10) : r.callsign,
        rxMhz: r.outputFreq,
        txMhz: r.inputFreq,
        tone: r.ctcssHz ?? 0.0,
        notes: r.emergencyNetLabel,
      ));
    }
    final plan = FreqPlan(
      id: 'rb_emergency_nets', name: 'EmergNets', fips: '', channels: channels);

    setState(() => _writing = true);
    int written = 0;
    try {
      await for (final n in FreqPlanService.writePlanToRadio(
          plan, kEmergencyNetGroupIndex, radio)) {
        written = n;
      }
    } catch (e) {
      debugPrint('emergency-net write error: $e');
    }
    if (!mounted) return;
    setState(() => _writing = false);
    _snack('Wrote $written of ${channels.length} emergency-net channels to Group 4.');
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final nets = _nets ?? const <RbConnectRepeater>[];
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: const Text('Emergency Nets → Group 4'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      floatingActionButton: (nets.isNotEmpty && !_loading)
          ? FloatingActionButton.extended(
              onPressed: _writing ? null : _writeToGroup4,
              icon: _writing
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.download),
              label: Text(_writing ? 'Writing…' : 'Write to Group 4'),
            )
          : null,
      body: _body(nets),
    );
  }

  Widget _body(List<RbConnectRepeater> nets) {
    if (_loading) {
      return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(),
        SizedBox(height: 12),
        Text('Finding ARES / RACES / SKYWARN nets nearby…',
            style: TextStyle(color: Colors.white54)),
      ]));
    }
    if (_error != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(_error!, textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54)),
      ));
    }
    return Column(children: [
      Container(
        width: double.infinity,
        color: Colors.blueGrey[900],
        padding: const EdgeInsets.all(12),
        child: Text(
          '${nets.length} ARES/RACES/SKYWARN repeaters within '
          '${_radiusMiles.toInt()} mi · 2m/70cm FM. '
          '${nets.length > 32 ? 'Nearest 32 will be written. ' : ''}'
          'Data courtesy of RepeaterBook.com',
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
      ),
      Expanded(
        child: nets.isEmpty
            ? const Center(child: Text('No emergency nets found nearby',
                style: TextStyle(color: Colors.white54)))
            : ListView.separated(
                padding: const EdgeInsets.only(bottom: 90),
                itemCount: nets.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: Colors.white12),
                itemBuilder: (_, i) {
                  final r = nets[i];
                  return ListTile(
                    leading: CircleAvatar(
                      radius: 15,
                      backgroundColor: Colors.red[900],
                      child: Text('${i + 1}',
                          style: const TextStyle(color: Colors.white, fontSize: 11)),
                    ),
                    title: Text('${r.callsign}  ·  ${r.emergencyNetLabel}',
                        style: const TextStyle(color: Colors.white)),
                    subtitle: Text(
                      '${r.outputFreq.toStringAsFixed(4)} MHz'
                      '${r.ctcssHz != null ? '  PL ${r.ctcssHz!.toStringAsFixed(1)}' : ''}'
                      '   ·  ${r.distanceMiles.toStringAsFixed(1)} mi  ·  ${r.location}',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}
