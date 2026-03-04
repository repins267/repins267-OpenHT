// lib/screens/messages/messages_screen.dart
// Amateur Radio BBS inbox (Winlink-style)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/bbs_service.dart';
import '../../models/bbs_message.dart';
import 'compose_screen.dart';
import 'message_detail_screen.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BbsService>().fetchMessages();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bbs = context.watch<BbsService>();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Messages'),
            if (bbs.unreadCount > 0) ...[
              const SizedBox(width: 8),
              CircleAvatar(
                radius: 10,
                backgroundColor: Colors.red,
                child: Text(
                  '${bbs.unreadCount}',
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ],
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: bbs.isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.refresh),
            onPressed: bbs.isLoading ? null : bbs.fetchMessages,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(text: 'INBOX'),
            Tab(text: 'SENT'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _MessageList(
            messages: bbs.inbox,
            emptyMessage: 'No messages in inbox',
            onTap: (msg) => _openMessage(bbs, msg),
            onDelete: (msg) => bbs.deleteMessage(msg),
          ),
          _MessageList(
            messages: bbs.sent,
            emptyMessage: 'No sent messages',
            onTap: (msg) => _openMessage(bbs, msg),
            onDelete: (msg) => bbs.deleteMessage(msg),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ComposeScreen()),
        ),
        tooltip: 'Compose',
        child: const Icon(Icons.edit),
      ),
    );
  }

  void _openMessage(BbsService bbs, BbsMessage msg) {
    bbs.markRead(msg);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MessageDetailScreen(message: msg)),
    );
  }
}

class _MessageList extends StatelessWidget {
  final List<BbsMessage> messages;
  final String emptyMessage;
  final void Function(BbsMessage) onTap;
  final void Function(BbsMessage) onDelete;

  const _MessageList({
    required this.messages,
    required this.emptyMessage,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox, size: 48, color: Colors.white24),
            const SizedBox(height: 8),
            Text(emptyMessage, style: const TextStyle(color: Colors.white38)),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: messages.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: Colors.white12),
      itemBuilder: (ctx, i) {
        final msg = messages[i];
        return Dismissible(
          key: ValueKey(msg.id),
          background: Container(
            color: Colors.red[900],
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 16),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          direction: DismissDirection.endToStart,
          onDismissed: (_) => onDelete(msg),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: msg.read ? Colors.grey[800] : Colors.blue[900],
              child: Text(
                msg.from.isNotEmpty ? msg.from[0] : '?',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(
              msg.subject.isEmpty ? '(no subject)' : msg.subject,
              style: TextStyle(
                color: Colors.white,
                fontWeight: msg.read ? FontWeight.normal : FontWeight.bold,
              ),
            ),
            subtitle: Text(
              '${msg.from} • ${msg.displayTime}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            trailing: msg.read
                ? null
                : Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                    ),
                  ),
            onTap: () => onTap(msg),
          ),
        );
      },
    );
  }
}
