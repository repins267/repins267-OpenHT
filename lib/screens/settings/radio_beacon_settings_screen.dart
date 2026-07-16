import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_benlink/flutter_benlink.dart';
import '../../bluetooth/radio_service.dart';

/// Radio-side APRS beacon (BSS) settings: SmartBeacon, Mic-E, share-location,
/// interval, message. Read/written via READ/WRITE_BSS_SETTINGS (BSSSettings).
class RadioBeaconSettingsScreen extends StatefulWidget {
  const RadioBeaconSettingsScreen({super.key});

  @override
  State<RadioBeaconSettingsScreen> createState() =>
      _RadioBeaconSettingsScreenState();
}

class _RadioBeaconSettingsScreenState extends State<RadioBeaconSettingsScreen> {
  bool _loading = true;
  bool _busy = false;
  BSSSettings? _bss;
  final _msgCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final bss = await context.read<RadioService>().getBeaconSettings();
    if (!mounted) return;
    setState(() {
      _bss = bss;
      _msgCtrl.text = bss?.beaconMessage ?? '';
      _loading = false;
    });
  }

  Future<void> _save() async {
    final radio = context.read<RadioService>();
    if (_bss == null) return;
    setState(() => _busy = true);
    await radio.setBeaconSettings(_bss!.copyWith(beaconMessage: _msgCtrl.text));
    final fresh = await radio.getBeaconSettings();
    if (!mounted) return;
    setState(() {
      _bss = fresh ?? _bss;
      _busy = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Beacon settings written to radio')));
  }

  @override
  Widget build(BuildContext context) {
    final connected = context.watch<RadioService>().isConnected;
    return Scaffold(
      appBar: AppBar(title: const Text('Radio Beacon (SmartBeacon)')),
      body: !connected
          ? const Center(child: Text('Radio not connected'))
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : _bss == null
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                            'Radio did not return BSS settings (older firmware?).',
                            textAlign: TextAlign.center),
                      ),
                    )
                  : ListView(
                      children: [
                        ListTile(
                          title: const Text('Callsign'),
                          trailing: Text('${_bss!.aprsCallsign}-${_bss!.aprsSsid}',
                              style: const TextStyle(fontFamily: 'monospace')),
                        ),
                        SwitchListTile(
                          title: const Text('Share location (beacon on)'),
                          value: _bss!.shouldShareLocation,
                          onChanged: _busy
                              ? null
                              : (v) => setState(() => _bss =
                                  _bss!.copyWith(shouldShareLocation: v)),
                        ),
                        ListTile(
                          title: const Text('Fixed interval'),
                          subtitle: Slider(
                            min: 60,
                            max: 3600,
                            divisions: 59,
                            label: '${_bss!.locationShareInterval}s',
                            value: _bss!.locationShareInterval
                                .clamp(60, 3600)
                                .toDouble(),
                            onChanged: _busy
                                ? null
                                : (v) => setState(() => _bss = _bss!.copyWith(
                                    locationShareInterval: (v ~/ 10) * 10)),
                          ),
                          trailing: Text('${_bss!.locationShareInterval}s'),
                        ),
                        const Divider(),
                        SwitchListTile(
                          title: const Text('SmartBeacon'),
                          subtitle: const Text(
                              'Variable interval based on speed/heading'),
                          value: _bss!.smartBeaconEn,
                          onChanged: _busy
                              ? null
                              : (v) => setState(
                                  () => _bss = _bss!.copyWith(smartBeaconEn: v)),
                        ),
                        if (_bss!.smartBeaconEn) ...[
                          ListTile(
                            title: const Text('SmartBeacon min interval'),
                            subtitle: Slider(
                              min: 0,
                              max: 15,
                              divisions: 15,
                              label: '${_bss!.smartBeaconMinInterval}',
                              value: _bss!.smartBeaconMinInterval.toDouble(),
                              onChanged: _busy
                                  ? null
                                  : (v) => setState(() => _bss = _bss!.copyWith(
                                      smartBeaconMinInterval: v.round())),
                            ),
                            trailing: Text('${_bss!.smartBeaconMinInterval}'),
                          ),
                          ListTile(
                            title: const Text('SmartBeacon max interval'),
                            subtitle: Slider(
                              min: 0,
                              max: 31,
                              divisions: 31,
                              label: '${_bss!.smartBeaconMaxInterval}',
                              value: _bss!.smartBeaconMaxInterval.toDouble(),
                              onChanged: _busy
                                  ? null
                                  : (v) => setState(() => _bss = _bss!.copyWith(
                                      smartBeaconMaxInterval: v.round())),
                            ),
                            trailing: Text('${_bss!.smartBeaconMaxInterval}'),
                          ),
                        ],
                        SwitchListTile(
                          title: const Text('Mic-E encoding'),
                          value: _bss!.micEEn,
                          onChanged: _busy
                              ? null
                              : (v) => setState(
                                  () => _bss = _bss!.copyWith(micEEn: v)),
                        ),
                        SwitchListTile(
                          title: const Text('Send ID by APRS'),
                          value: _bss!.sendIdByAprs,
                          onChanged: _busy
                              ? null
                              : (v) => setState(
                                  () => _bss = _bss!.copyWith(sendIdByAprs: v)),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          child: TextField(
                            controller: _msgCtrl,
                            maxLength: 18,
                            decoration: const InputDecoration(
                                labelText: 'Beacon message',
                                border: OutlineInputBorder()),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: FilledButton.icon(
                            onPressed: _busy ? null : _save,
                            icon: _busy
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Icon(Icons.save),
                            label: const Text('Write beacon settings to radio'),
                          ),
                        ),
                      ],
                    ),
    );
  }
}
