// lib/screens/messages/message_detail_screen.dart
// Message detail view with reply button

import 'package:flutter/material.dart';
import '../../models/bbs_message.dart';
import 'compose_screen.dart';

class MessageDetailScreen extends StatelessWidget {
  final BbsMessage message;

  const MessageDetailScreen({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(message.subject.isEmpty ? '(no subject)' : message.subject,
            overflow: TextOverflow.ellipsis),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.reply),
            tooltip: 'Reply',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ComposeScreen(
                  initialTo: message.from,
                  reSubject: message.subject.startsWith('Re:')
                      ? message.subject
                      : 'Re: ${message.subject}',
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ─── Header ────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[850],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HeaderRow('From', message.from),
                const SizedBox(height: 4),
                _HeaderRow('To', message.to),
                const SizedBox(height: 4),
                _HeaderRow('Date', message.displayTime),
              ],
            ),
          ),

          // ─── Body ──────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                message.body.isEmpty ? '(no body)' : message.body,
                style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  final String label;
  final String value;

  const _HeaderRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 40,
          child: Text(label,
              style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 13)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(value,
              style: const TextStyle(color: Colors.white, fontSize: 13)),
        ),
      ],
    );
  }
}
