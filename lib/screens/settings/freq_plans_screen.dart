// Frequency Plans list — pick a plan for any location/area, create new plans,
// or edit/delete existing ones. Tapping a plan opens the editor (which can also
// write it to any channel group).

import 'package:flutter/material.dart';
import '../../services/freq_plan_service.dart';
import 'freq_plan_editor_screen.dart';
import 'emergency_nets_screen.dart';

class FreqPlansScreen extends StatefulWidget {
  const FreqPlansScreen({super.key});

  @override
  State<FreqPlansScreen> createState() => _FreqPlansScreenState();
}

class _FreqPlansScreenState extends State<FreqPlansScreen> {
  List<FreqPlanMeta> _plans = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final plans = await FreqPlanService.listPlans();
    if (!mounted) return;
    setState(() {
      _plans = plans;
      _loading = false;
    });
  }

  Future<void> _open(FreqPlanMeta? meta) async {
    final plan = meta == null ? null : await FreqPlanService.loadPlan(meta.id);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => FreqPlanEditorScreen(plan: plan)),
    );
    _load();
  }

  Future<void> _delete(FreqPlanMeta meta) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: Text('Delete "${meta.name}"?',
            style: const TextStyle(color: Colors.white)),
        content: Text(
          FreqPlanService.isBundled(meta.id)
              ? 'This resets your edits back to the bundled template.'
              : 'This permanently removes the plan.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await FreqPlanService.deletePlan(meta.id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: const Text('Frequency Plans'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(null),
        icon: const Icon(Icons.add),
        label: const Text('New Plan'),
      ),
      body: Column(
        children: [
          // Emergency Nets (RepeaterBook) → Group 4
          Card(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            color: Colors.grey[850],
            child: ListTile(
              leading: const Icon(Icons.emergency_share, color: Colors.redAccent),
              title: const Text('Emergency Nets (RepeaterBook)',
                  style: TextStyle(color: Colors.white)),
              subtitle: const Text(
                  'ARES / RACES / SKYWARN near you → Group 4',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              trailing: const Icon(Icons.chevron_right, color: Colors.white38),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const EmergencyNetsScreen()),
              ),
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _plans.isEmpty
                    ? const Center(
                        child: Text('No saved plans yet — tap "New Plan".',
                            style: TextStyle(color: Colors.white54)))
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 90),
                        itemCount: _plans.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, color: Colors.white12),
                        itemBuilder: (_, i) {
                          final p = _plans[i];
                          return ListTile(
                            leading: Icon(
                              p.isUser ? Icons.edit_note : Icons.public,
                              color: p.isUser ? Colors.tealAccent : Colors.blueGrey,
                            ),
                            title: Text(p.name, style: const TextStyle(color: Colors.white)),
                            subtitle: Text(
                              '${p.channelCount} channel(s) · ${p.isUser ? 'Your plan' : 'Bundled template'}',
                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                            trailing: p.isUser
                                ? IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                    onPressed: () => _delete(p),
                                  )
                                : const Icon(Icons.chevron_right, color: Colors.white38),
                            onTap: () => _open(p),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
