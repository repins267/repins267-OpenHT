// lib/screens/settings/channel_manager_screen.dart
// Channel & Group Manager — import/export CSV, sync to radio

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_benlink/flutter_benlink.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
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
    final csv      = ChannelCsvService.encode(group.channels);
    final dir      = await getTemporaryDirectory();
    final fileName = 'openht_group${groupIndex + 1}.csv';
    final file     = File('${dir.path}/$fileName');
    await file.writeAsString(csv);
    if (!mounted) return;
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'OpenHT Group ${groupIndex + 1} channels',
    );
  }

  Future<void> _importCsv() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      dialogTitle: 'Select VGC CSV file to import',
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;

    final csv = await File(path).readAsString();
    final channels = ChannelCsvService.decode(csv);
    if (channels.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No valid channels found in file'),
            backgroundColor: Colors.orange),
      );
      return;
    }

    // Ask the user which group to import into
    if (!mounted) return;
    final groupIndex = await showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: const Text('Import to Group',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${channels.length} channels found. Choose a group (overwrites slots):',
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 12),
            ...List.generate(6, (i) => ListTile(
              title: Text(i == 4 ? 'Group 5 — NOAA Weather'
                  : i == 5 ? 'Group 6 — Near Repeaters'
                  : 'Group ${i + 1}',
                  style: const TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context, i),
            )),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
        ],
      ),
    );
    if (groupIndex == null || !mounted) return;

    final radio = context.read<RadioService>();
    if (!radio.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Radio not connected')),
      );
      return;
    }

    setState(() => _isSyncing = true);
    int written = 0;
    for (int i = 0; i < channels.length && i < 32; i++) {
      try {
        final ch = channels[i].copyWith(channelId: groupIndex * 32 + i);
        await radio.controller!.writeChannel(ch);
        written++;
        await Future.delayed(const Duration(milliseconds: 150));
      } catch (e) {
        debugPrint('Channel import slot $i failed: $e');
      }
    }
    if (!mounted) return;
    setState(() => _isSyncing = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Imported $written/${channels.length} channels to Group ${groupIndex + 1}'),
      backgroundColor: written > 0 ? Colors.green[700] : Colors.red[700],
    ));
    await _loadFromRadio();
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
                    ListTile(
                      leading: const Icon(Icons.upload_file_outlined, color: Colors.green),
                      title: const Text('Import CSV',
                          style: TextStyle(color: Colors.white)),
                      subtitle: const Text('Load VGC/HTCommander CSV → write to a group',
                          style: TextStyle(color: Colors.white54, fontSize: 12)),
                      trailing: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700]),
                        onPressed: _isSyncing ? null : _importCsv,
                        child: const Text('Import'),
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
          icon: const Icon(Icons.share_outlined, color: Colors.blue),
          tooltip: 'Export as CSV (share)',
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
