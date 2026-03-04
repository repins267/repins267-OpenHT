// lib/screens/aprs/conversations_screen.dart
// APRS message conversations list — one row per peer callsign

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/aprs_message_service.dart';
import 'message_thread_screen.dart';

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  List<Conversation> _conversations = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    // Reload when message service notifies
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AprsMessageService>().addListener(_load);
    });
  }

  @override
  void dispose() {
    context.read<AprsMessageService>().removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final svc = context.read<AprsMessageService>();
    final convs = await svc.getConversations();
    if (!mounted) return;
    setState(() {
      _conversations = convs;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('APRS Messages'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'New message',
            onPressed: () => _startNewConversation(context),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _conversations.isEmpty
              ? _EmptyState(onNew: () => _startNewConversation(context))
              : ListView.separated(
                  itemCount: _conversations.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: Colors.white12),
                  itemBuilder: (ctx, i) {
                    final c = _conversations[i];
                    return _ConversationTile(
                      conv: c,
                      onTap: () => _openThread(c.peerCallsign),
                    );
                  },
                ),
    );
  }

  void _openThread(String callsign) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MessageThreadScreen(peerCallsign: callsign),
      ),
    ).then((_) => _load());
  }

  void _startNewConversation(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: const Text('New Message', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
          decoration: const InputDecoration(
            hintText: 'Callsign (e.g. W0ABC-9)',
            hintStyle: TextStyle(color: Colors.white38),
            labelText: 'To',
            labelStyle: TextStyle(color: Colors.white54),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final call = controller.text.trim().toUpperCase();
              if (call.isEmpty) return;
              Navigator.pop(ctx);
              _openThread(call);
            },
            child: const Text('Open'),
          ),
        ],
      ),
    );
  }
}

// ── Conversation tile ─────────────────────────────────────────────────────────
class _ConversationTile extends StatelessWidget {
  final Conversation conv;
  final VoidCallback onTap;

  const _ConversationTile({required this.conv, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final msg = conv.lastMessage;
    final isOutgoing = msg.dir == AprsMessageDir.outgoing;
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: Colors.blueGrey[700],
        child: Text(
          conv.peerCallsign.substring(0, 1),
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              conv.peerCallsign,
              style: TextStyle(
                color: Colors.white,
                fontWeight: conv.unreadCount > 0
                    ? FontWeight.bold
                    : FontWeight.normal,
                fontFamily: 'monospace',
              ),
            ),
          ),
          Text(
            _formatTime(msg.ts),
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
      subtitle: Row(
        children: [
          if (isOutgoing)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                msg.state == AprsMessageState.acked
                    ? Icons.done_all
                    : Icons.done,
                size: 13,
                color: msg.state == AprsMessageState.acked
                    ? Colors.blue[400]
                    : Colors.white38,
              ),
            ),
          Expanded(
            child: Text(
              msg.text.length > 60
                  ? '${msg.text.substring(0, 60)}…'
                  : msg.text,
              style: TextStyle(
                color: conv.unreadCount > 0 ? Colors.white70 : Colors.white38,
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (conv.unreadCount > 0)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.blue[700],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${conv.unreadCount}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
      return '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.month}/${dt.day}';
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final VoidCallback onNew;
  const _EmptyState({required this.onNew});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.message_outlined, size: 56, color: Colors.white24),
          const SizedBox(height: 16),
          const Text('No messages yet',
              style: TextStyle(color: Colors.white54, fontSize: 16)),
          const SizedBox(height: 8),
          const Text('APRS messages from the air appear here.',
              style: TextStyle(color: Colors.white38, fontSize: 13)),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Start a Conversation'),
            onPressed: onNew,
          ),
        ],
      ),
    );
  }
}
