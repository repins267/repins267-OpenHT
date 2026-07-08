// Channel list view — shows every channel in the radio's ACTIVE group (read via
// READ_RF_CH). Tap a channel to open the full editor. The radio only serves the
// active group live over BT; to view a different group, switch it on the radio.

import 'package:flutter/material.dart';
import 'package:flutter_benlink/flutter_benlink.dart';
import 'package:provider/provider.dart';
import '../../bluetooth/radio_service.dart';
import 'channel_editor_screen.dart';

class ChannelListScreen extends StatefulWidget {
  const ChannelListScreen({super.key});

  @override
  State<ChannelListScreen> createState() => _ChannelListScreenState();
}

class _ChannelListScreenState extends State<ChannelListScreen> {
  List<Channel>? _channels;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final radio = context.read<RadioService>();
    if (!radio.isConnected) {
      setState(() => _error = 'Radio not connected');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final chans = await radio.getActiveGroupChannels();
      if (!mounted) return;
      setState(() {
        _channels = chans;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to read channels: $e';
        _loading = false;
      });
    }
  }

  Future<void> _edit(Channel ch) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ChannelEditorScreen(channel: ch), // groupIndex null = active
      ),
    );
    if (changed == true) _load();
  }

  static bool _isEmpty(Channel c) => c.rxFreq <= 0 && c.name.trim().isEmpty;

  static String _toneLabel(Channel c) {
    final t = c.rxSubAudio;
    if (t is double && t > 0) return 'CT ${t.toStringAsFixed(1)}';
    if (t is int && t > 0) return 'DCS $t';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: const Text('Active Group Channels'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload from radio',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54)),
        ),
      );
    }
    final chans = _channels ?? const <Channel>[];
    if (chans.isEmpty) {
      return const Center(
        child: Text('No channels', style: TextStyle(color: Colors.white54)),
      );
    }
    return ListView.separated(
      itemCount: chans.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white12),
      itemBuilder: (_, i) {
        final c = chans[i];
        final empty = _isEmpty(c);
        final tone = _toneLabel(c);
        return ListTile(
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: empty ? Colors.grey[800] : Colors.blueGrey[700],
            child: Text('${c.channelId + 1}',
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
          title: Text(
            empty ? '(empty)' : (c.name.trim().isEmpty ? '—' : c.name.trim()),
            style: TextStyle(color: empty ? Colors.white38 : Colors.white),
          ),
          subtitle: empty
              ? null
              : Text(
                  '${c.rxFreq.toStringAsFixed(4)} MHz'
                  '${c.txFreq != c.rxFreq ? '  ▸ TX ${c.txFreq.toStringAsFixed(4)}' : ''}'
                  '${tone.isNotEmpty ? '   $tone' : ''}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
          trailing: const Icon(Icons.edit, color: Colors.white38, size: 18),
          onTap: () => _edit(c),
        );
      },
    );
  }
}
