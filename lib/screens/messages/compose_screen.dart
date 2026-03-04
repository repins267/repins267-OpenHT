// lib/screens/messages/compose_screen.dart
// Winlink message compose screen

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/bbs_service.dart';

class ComposeScreen extends StatefulWidget {
  final String? initialTo;
  final String? reSubject;

  const ComposeScreen({super.key, this.initialTo, this.reSubject});

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  late TextEditingController _toCtrl;
  late TextEditingController _subjectCtrl;
  late TextEditingController _bodyCtrl;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _toCtrl      = TextEditingController(text: widget.initialTo ?? '');
    _subjectCtrl = TextEditingController(text: widget.reSubject ?? '');
    _bodyCtrl    = TextEditingController();
  }

  @override
  void dispose() {
    _toCtrl.dispose();
    _subjectCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Compose'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: _isSending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.send),
            tooltip: 'Send via Winlink',
            onPressed: _isSending ? null : _send,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _FieldRow(
              label: 'To',
              child: TextField(
                controller: _toCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  hintText: 'CALLSIGN',
                  hintStyle: TextStyle(color: Colors.white38),
                  border: InputBorder.none,
                ),
                style: const TextStyle(color: Colors.white),
              ),
            ),
            const Divider(color: Colors.white24),
            _FieldRow(
              label: 'Subject',
              child: TextField(
                controller: _subjectCtrl,
                decoration: const InputDecoration(
                  hintText: 'Subject',
                  hintStyle: TextStyle(color: Colors.white38),
                  border: InputBorder.none,
                ),
                style: const TextStyle(color: Colors.white),
              ),
            ),
            const Divider(color: Colors.white24),
            Expanded(
              child: TextField(
                controller: _bodyCtrl,
                maxLines: null,
                expands: true,
                decoration: const InputDecoration(
                  hintText: 'Message body…',
                  hintStyle: TextStyle(color: Colors.white38),
                  border: InputBorder.none,
                ),
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _send() async {
    final to      = _toCtrl.text.trim().toUpperCase();
    final subject = _subjectCtrl.text.trim();
    final body    = _bodyCtrl.text.trim();

    if (to.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recipient callsign is required')),
      );
      return;
    }

    setState(() => _isSending = true);

    final bbs = context.read<BbsService>();
    final success = await bbs.sendMessage(
      to: to,
      subject: subject.isEmpty ? '(no subject)' : subject,
      body: body,
    );

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message sent via Winlink ✓'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(bbs.error ?? 'Send failed'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isSending = false);
      }
    }
  }
}

class _FieldRow extends StatelessWidget {
  final String label;
  final Widget child;

  const _FieldRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 56,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
