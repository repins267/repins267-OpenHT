// Frequency-plan editor — create or edit a plan (name + channel list) and write
// it to any of the 6 channel groups. Bundled templates are edited by saving a
// user copy (same id) that shadows the template.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../bluetooth/radio_service.dart';
import '../../services/freq_plan_service.dart';

class FreqPlanEditorScreen extends StatefulWidget {
  final FreqPlan? plan; // null = new plan

  const FreqPlanEditorScreen({super.key, this.plan});

  @override
  State<FreqPlanEditorScreen> createState() => _FreqPlanEditorScreenState();
}

class _FreqPlanEditorScreenState extends State<FreqPlanEditorScreen> {
  late TextEditingController _name;
  late List<FreqPlanChannel> _channels;
  String? _id;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.plan?.name ?? '');
    _channels = List<FreqPlanChannel>.from(widget.plan?.channels ?? const []);
    _id = widget.plan?.id;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  FreqPlan _build() {
    final id = _id ?? FreqPlanService.idForName(_name.text);
    return FreqPlan(
      id: id,
      name: _name.text.trim().isEmpty ? 'Untitled plan' : _name.text.trim(),
      fips: widget.plan?.fips ?? '',
      channels: _channels,
    );
  }

  Future<void> _save() async {
    final plan = _build();
    await FreqPlanService.savePlan(plan);
    _id = plan.id;
    _dirty = false;
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Saved "${plan.name}"')));
  }

  Future<void> _editChannel(int? index) async {
    final existing = index == null ? null : _channels[index];
    final result = await showModalBottomSheet<FreqPlanChannel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey[900],
      builder: (_) => _ChannelSheet(
        channel: existing,
        defaultSlot: existing?.slot ?? _channels.length,
      ),
    );
    if (result == null) return;
    setState(() {
      if (index == null) {
        _channels.add(result);
      } else {
        _channels[index] = result;
      }
      _channels.sort((a, b) => a.slot.compareTo(b.slot));
      _dirty = true;
    });
  }

  Future<void> _writeToRadio() async {
    final radio = context.read<RadioService>();
    if (!radio.isConnected) {
      _snack('Radio not connected');
      return;
    }
    if (_channels.isEmpty) {
      _snack('Add at least one channel first');
      return;
    }
    final group = await _pickGroup();
    if (group == null) return;
    if (_dirty || _id == null) await _save();
    final plan = _build();
    if (!mounted) return;

    int written = 0;
    final total = plan.channels.length;
    // Progress dialog.
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.grey[850],
        content: Row(children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 16),
          Text('Writing to Group ${group + 1}…',
              style: const TextStyle(color: Colors.white)),
        ]),
      ),
    );
    try {
      await for (final n in FreqPlanService.writePlanToRadio(plan, group, radio)) {
        written = n;
      }
    } catch (e) {
      debugPrint('plan write error: $e');
    }
    if (!mounted) return;
    Navigator.of(context).pop(); // close progress
    _snack('Wrote $written/$total channels to Group ${group + 1}');
  }

  Future<int?> _pickGroup() {
    return showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: Colors.grey[850],
        title: const Text('Write to which group?',
            style: TextStyle(color: Colors.white)),
        children: [
          for (int g = 0; g < 6; g++)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, g),
              child: Text('Group ${g + 1}',
                  style: const TextStyle(color: Colors.white)),
            ),
        ],
      ),
    );
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final isBundled = _id != null && FreqPlanService.isBundled(_id!);
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: Text(widget.plan == null ? 'New Plan' : 'Edit Plan'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('SAVE', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _writeToRadio,
        icon: const Icon(Icons.download),
        label: const Text('Write to radio'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
        children: [
          if (isBundled)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Bundled template — saving keeps your edits as a personal copy.',
                  style: TextStyle(color: Colors.amberAccent, fontSize: 12)),
            ),
          TextField(
            controller: _name,
            style: const TextStyle(color: Colors.white),
            onChanged: (_) => _dirty = true,
            decoration: const InputDecoration(
              labelText: 'Plan name',
              labelStyle: TextStyle(color: Colors.white70),
              enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24)),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Channels (${_channels.length})',
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
              TextButton.icon(
                onPressed: () => _editChannel(null),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
              ),
            ],
          ),
          ..._channels.asMap().entries.map((e) {
            final i = e.key;
            final c = e.value;
            return Card(
              color: Colors.grey[850],
              child: ListTile(
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: Colors.blueGrey[700],
                  child: Text('${c.slot + 1}',
                      style: const TextStyle(color: Colors.white, fontSize: 11)),
                ),
                title: Text(c.name, style: const TextStyle(color: Colors.white)),
                subtitle: Text(
                  'RX ${c.rxMhz.toStringAsFixed(4)}  TX ${c.txMhz.toStringAsFixed(4)}'
                  '${c.tone > 0 ? '  CT ${c.tone.toStringAsFixed(1)}' : ''}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  onPressed: () => setState(() {
                    _channels.removeAt(i);
                    _dirty = true;
                  }),
                ),
                onTap: () => _editChannel(i),
              ),
            );
          }),
          if (_channels.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No channels yet — tap "Add".',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38)),
            ),
        ],
      ),
    );
  }
}

// ─── Channel edit sheet ──────────────────────────────────────────────────────
class _ChannelSheet extends StatefulWidget {
  final FreqPlanChannel? channel;
  final int defaultSlot;
  const _ChannelSheet({required this.channel, required this.defaultSlot});

  @override
  State<_ChannelSheet> createState() => _ChannelSheetState();
}

class _ChannelSheetState extends State<_ChannelSheet> {
  late TextEditingController _slot, _name, _rx, _tx, _tone;

  @override
  void initState() {
    super.initState();
    final c = widget.channel;
    _slot = TextEditingController(text: '${(c?.slot ?? widget.defaultSlot) + 1}');
    _name = TextEditingController(text: c?.name ?? '');
    _rx = TextEditingController(text: c?.rxMhz.toStringAsFixed(4) ?? '');
    _tx = TextEditingController(text: c?.txMhz.toStringAsFixed(4) ?? '');
    _tone = TextEditingController(text: (c?.tone ?? 0) > 0 ? c!.tone.toStringAsFixed(1) : '');
  }

  @override
  void dispose() {
    for (final c in [_slot, _name, _rx, _tx, _tone]) {
      c.dispose();
    }
    super.dispose();
  }

  void _done() {
    final rx = double.tryParse(_rx.text.trim());
    final tx = double.tryParse(_tx.text.trim());
    if (rx == null || tx == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('RX and TX must be valid numbers')));
      return;
    }
    final slot = (int.tryParse(_slot.text.trim()) ?? 1) - 1;
    Navigator.pop(
      context,
      FreqPlanChannel(
        slot: slot.clamp(0, 31),
        name: _name.text.trim(),
        rxMhz: rx,
        txMhz: tx,
        tone: double.tryParse(_tone.text.trim()) ?? 0.0,
        notes: widget.channel?.notes ?? '',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _f(_slot, 'Slot (1-32)', number: true),
          _f(_name, 'Name'),
          _f(_rx, 'RX Freq (MHz)', number: true),
          _f(_tx, 'TX Freq (MHz)', number: true),
          _f(_tone, 'CTCSS (Hz, blank = none)', number: true),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel')),
              const SizedBox(width: 8),
              ElevatedButton(onPressed: _done, child: const Text('Done')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _f(TextEditingController c, String label, {bool number = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: TextField(
          controller: c,
          style: const TextStyle(color: Colors.white),
          keyboardType: number
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          inputFormatters:
              number ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))] : null,
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: Colors.white70),
            enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white24)),
          ),
        ),
      );
}
