// Channel-group editor — opens ANY of the 6 groups, reads its real channels
// (SET_REGION → READ_RF_CH), shows them, and lets you rename the group and edit
// each channel with its actual current values prefilled. Writes go via region
// addressing (WRITE_REGION_CH / WRITE_REGION_NAME).
//
// Note: opening a group SET_REGIONs it, i.e. makes it the radio's active group.

import 'package:flutter/material.dart';
import 'package:flutter_benlink/flutter_benlink.dart';
import 'package:provider/provider.dart';
import '../../bluetooth/radio_service.dart';
import 'channel_editor_screen.dart';

class GroupEditorScreen extends StatefulWidget {
  final int groupIndex;    // 0..5 (UI Groups 1-6)
  final String? groupName; // best-known current name, if any

  const GroupEditorScreen({super.key, required this.groupIndex, this.groupName});

  @override
  State<GroupEditorScreen> createState() => _GroupEditorScreenState();
}

class _GroupEditorScreenState extends State<GroupEditorScreen> {
  List<Channel>? _channels;
  bool _loading = false;
  String? _error;
  String? _name;

  @override
  void initState() {
    super.initState();
    _name = widget.groupName;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final radio = context.read<RadioService>();
    if (!radio.isConnected) {
      setState(() => _error = 'Radio not connected');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final nm = await radio.getGroupName(widget.groupIndex);
      final chans = await radio.readGroupChannels(widget.groupIndex);
      if (!mounted) return;
      setState(() {
        if (nm != null && nm.isNotEmpty) _name = nm;
        _channels = chans;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = 'Failed to read group: $e'; _loading = false; });
    }
  }

  Channel _blank(int slot) => Channel(
        channelId: slot,
        txMod: ModulationType.FM,
        rxMod: ModulationType.FM,
        txFreq: 146.520,
        rxFreq: 146.520,
        bandwidth: BandwidthType.WIDE,
        scan: true,
        txAtMaxPower: false,
        txAtMedPower: true,
        name: '',
      );

  static bool _isEmpty(Channel c) => c.rxFreq <= 0 && c.name.trim().isEmpty;

  static String _tone(Channel c) {
    final t = c.rxSubAudio;
    if (t is double && t > 0) return 'CT ${t.toStringAsFixed(1)}';
    if (t is int && t > 0) return 'DCS $t';
    return '';
  }

  Future<void> _edit(Channel ch) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ChannelEditorScreen(
          channel: ch,
          groupIndex: widget.groupIndex,
        ),
      ),
    );
    if (changed == true) _load();
  }

  Future<void> _rename() async {
    final ctl = TextEditingController(text: _name ?? '');
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: Text('Rename Group ${widget.groupIndex + 1}',
            style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctl,
          maxLength: 10,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Up to 10 characters',
            hintStyle: TextStyle(color: Colors.white30),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || !mounted) return;
    final radio = context.read<RadioService>();
    final ok = await radio.setGroupName(widget.groupIndex, newName);
    if (!mounted) return;
    if (ok) setState(() => _name = newName);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'Group renamed to "$newName"'
          : 'Rename failed: ${radio.errorMessage ?? 'error'}'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.groupIndex + 1;
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: Text(_name == null ? 'Group $g' : 'Group $g · $_name'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.drive_file_rename_outline),
            tooltip: 'Rename group',
            onPressed: _rename,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload from radio',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(),
          SizedBox(height: 12),
          Text('Switching to group & reading channels…',
              style: TextStyle(color: Colors.white54)),
        ]),
      );
    }
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
    return ListView.separated(
      itemCount: chans.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white12),
      itemBuilder: (_, i) {
        final c = chans[i];
        final empty = _isEmpty(c);
        final tone = _tone(c);
        return ListTile(
          leading: CircleAvatar(
            radius: 15,
            backgroundColor: empty ? Colors.grey[800] : Colors.blueGrey[700],
            child: Text('${c.channelId + 1}',
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
          title: Text(
            empty ? '(empty)' : (c.name.trim().isEmpty ? '—' : c.name.trim()),
            style: TextStyle(color: empty ? Colors.white38 : Colors.white),
          ),
          subtitle: empty
              ? const Text('Tap to program',
                  style: TextStyle(color: Colors.white38, fontSize: 12))
              : Text(
                  '${c.rxFreq.toStringAsFixed(4)} MHz'
                  '${c.txFreq != c.rxFreq ? '  ▸ TX ${c.txFreq.toStringAsFixed(4)}' : ''}'
                  '${tone.isNotEmpty ? '   $tone' : ''}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
          trailing: const Icon(Icons.edit, color: Colors.white38, size: 18),
          onTap: () => _edit(empty ? _blank(c.channelId) : c),
        );
      },
    );
  }
}
