// lib/screens/settings/channel_manager_screen.dart
// Channel & Group Manager — import/export CSV, sync to radio

import 'package:flutter/material.dart';
import 'package:flutter_benlink/flutter_benlink.dart';
import 'package:provider/provider.dart';
import '../../bluetooth/radio_service.dart';
import '../../services/channel_csv_service.dart';

class ChannelManagerScreen extends StatefulWidget {
  const ChannelManagerScreen({super.key});

  @override
  State<ChannelManagerScreen> createState() => _ChannelManagerScreenState();
}

class _ChannelManagerScreenState extends State<ChannelManagerScreen> {
  bool _isLoadingChannels = false;
  bool _isSyncing = false;
  List<_GroupInfo> _groups = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFromRadio());
  }

  Future<void> _loadFromRadio() async {
    final radio = context.read<RadioService>();
    if (!radio.isConnected) return;
    setState(() => _isLoadingChannels = true);
    final all = await radio.getAllChannels();
    if (!mounted) return;
    final groups = <_GroupInfo>[];
    for (int g = 0; g < 6; g++) {
      final start = g * 32;
      final end = start + 32;
      final chans = all.where((c) => c.channelId >= start && c.channelId < end).toList();
      String label = 'Group ${g + 1}';
      if (g == 4) label = 'Group 5 — NOAA Weather';
      if (g == 5) label = 'Group 6 — Near Repeaters';
      groups.add(_GroupInfo(index: g, label: label, channels: chans));
    }
    setState(() {
      _groups = groups;
      _isLoadingChannels = false;
    });
  }

  Future<void> _exportCsv(int groupIndex) async {
    final group = _groups.firstWhere((g) => g.index == groupIndex,
        orElse: () => _GroupInfo(index: groupIndex, label: '', channels: []));
    if (group.channels.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No channels to export')),
      );
      return;
    }
    final csv = ChannelCsvService.encode(group.channels);
    // Show CSV in a dialog (share intent requires extra plugin)
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: Text('Group ${groupIndex + 1} CSV',
            style: const TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: SelectableText(
            csv,
            style: const TextStyle(
                color: Colors.white70, fontSize: 10, fontFamily: 'monospace'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _writeNoaaGroup() async {
    final radio = context.read<RadioService>();
    if (!radio.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Radio not connected')),
      );
      return;
    }
    setState(() => _isSyncing = true);
    final n = await radio.writeNoaaGroup();
    if (!mounted) return;
    setState(() => _isSyncing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Wrote $n/7 NOAA channels to Group 5'),
        backgroundColor: n == 7 ? Colors.green[700] : Colors.orange[700],
      ),
    );
    await _loadFromRadio();
  }

  @override
  Widget build(BuildContext context) {
    final radio = context.watch<RadioService>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Channel & Group Manager'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          if (_isLoadingChannels || _isSyncing)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Reload from radio',
              onPressed: radio.isConnected ? _loadFromRadio : null,
            ),
        ],
      ),
      body: !radio.isConnected
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bluetooth_disabled, size: 48, color: Colors.white38),
                  SizedBox(height: 12),
                  Text('Connect radio to manage channels',
                      style: TextStyle(color: Colors.white54)),
                ],
              ),
            )
          : _isLoadingChannels
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  children: [
                    _SectionHeader('Quick Actions'),
                    ListTile(
                      leading: const Icon(Icons.wb_cloudy_outlined, color: Colors.blue),
                      title: const Text('Re-write NOAA Weather Channels',
                          style: TextStyle(color: Colors.white)),
                      subtitle: const Text('Overwrites Group 5 with 7 standard WX freqs',
                          style: TextStyle(color: Colors.white54, fontSize: 12)),
                      trailing: ElevatedButton(
                        onPressed: _isSyncing ? null : _writeNoaaGroup,
                        child: const Text('Write'),
                      ),
                    ),
                    _SectionHeader('Channel Groups'),
                    ..._groups.map((g) => _GroupTile(
                          info: g,
                          onExport: () => _exportCsv(g.index),
                        )),
                    const SizedBox(height: 80),
                  ],
                ),
    );
  }
}

class _GroupInfo {
  final int index;
  final String label;
  final List<Channel> channels;

  const _GroupInfo({
    required this.index,
    required this.label,
    required this.channels,
  });
}

class _GroupTile extends StatelessWidget {
  final _GroupInfo info;
  final VoidCallback onExport;

  const _GroupTile({required this.info, required this.onExport});

  @override
  Widget build(BuildContext context) {
    final isReserved = info.index == 4 || info.index == 5;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: Colors.grey[850],
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isReserved ? Colors.blue[900] : Colors.grey[700],
          child: Text(
            '${info.index + 1}',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(info.label, style: const TextStyle(color: Colors.white)),
        subtitle: Text(
          '${info.channels.length} channel(s) loaded',
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.download_outlined, color: Colors.blue),
          tooltip: 'Export as CSV',
          onPressed: info.channels.isEmpty ? null : onExport,
        ),
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
