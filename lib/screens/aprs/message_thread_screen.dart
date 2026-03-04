// lib/screens/aprs/message_thread_screen.dart
// APRS message chat thread — single conversation with one peer callsign

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../aprs/aprs_is_service.dart';
import '../../services/aprs_auth_service.dart';
import '../../services/aprs_message_service.dart';

class MessageThreadScreen extends StatefulWidget {
  final String peerCallsign;
  const MessageThreadScreen({super.key, required this.peerCallsign});

  @override
  State<MessageThreadScreen> createState() => _MessageThreadScreenState();
}

class _MessageThreadScreenState extends State<MessageThreadScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  List<AprsMessage> _messages = [];
  bool _sending = false;
  String _myCallsign = '';
  String _mySsid = '7';
  String _path = 'WIDE1-1,WIDE2-1';

  static const int _maxChars = 67; // APRS message body limit

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _loadThread();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AprsMessageService>().addListener(_loadThread);
    });
  }

  @override
  void dispose() {
    context.read<AprsMessageService>().removeListener(_loadThread);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _myCallsign = prefs.getString('callsign') ?? '';
      _mySsid = prefs.getString('aprs_ssid') ?? '7';
      _path = prefs.getString('aprs_path') ?? 'WIDE1-1,WIDE2-1';
    });
  }

  Future<void> _loadThread() async {
    final svc = context.read<AprsMessageService>();
    final msgs = await svc.getThread(widget.peerCallsign);
    await svc.markRead(widget.peerCallsign);
    if (!mounted) return;
    setState(() => _messages = msgs);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _myCallsign.isEmpty) return;

    final auth = context.read<AprsAuthService>();
    final svc = context.read<AprsMessageService>();
    final aprsIs = context.read<AprsIsService>();

    setState(() => _sending = true);

    // Optionally sign
    final signedText = (await auth.signMessage(text)) ?? text;

    // Store locally
    final msg = await svc.createOutgoing(
      toCallsign: widget.peerCallsign,
      text: text, // store clean text
    );

    // Send via APRS-IS if connected
    if (aprsIs.isConnected) {
      final line = AprsMessageService.formatOutgoingLine(
        myCallsign: _myCallsign,
        mySsid: _mySsid,
        path: _path,
        toCallsign: widget.peerCallsign,
        text: signedText,
        msgId: msg.msgId,
      );
      aprsIs.sendLine(line);
    }

    _controller.clear();
    setState(() => _sending = false);
    await _loadThread();
  }

  @override
  Widget build(BuildContext context) {
    final aprsIs = context.watch<AprsIsService>();
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.peerCallsign,
                style: const TextStyle(fontFamily: 'monospace')),
            Text(
              aprsIs.isConnected ? 'APRS-IS connected' : 'APRS-IS offline',
              style: TextStyle(
                fontSize: 11,
                color: aprsIs.isConnected ? Colors.green[300] : Colors.white38,
              ),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // ── Message list ────────────────────────────────────────────────
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Text('No messages yet',
                        style: TextStyle(color: Colors.white38)))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                        vertical: 8, horizontal: 12),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) => _MessageBubble(msg: _messages[i]),
                  ),
          ),

          // ── Offline warning ─────────────────────────────────────────────
          if (!aprsIs.isConnected)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: Colors.orange[900]!.withOpacity(0.4),
              child: const Row(
                children: [
                  Icon(Icons.wifi_off, size: 14, color: Colors.orange),
                  SizedBox(width: 6),
                  Text('APRS-IS offline — messages queued locally',
                      style: TextStyle(color: Colors.orange, fontSize: 12)),
                ],
              ),
            ),

          // ── Input bar ───────────────────────────────────────────────────
          _InputBar(
            controller: _controller,
            maxChars: _maxChars,
            sending: _sending,
            disabled: _myCallsign.isEmpty,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

// ── Message bubble ─────────────────────────────────────────────────────────────
class _MessageBubble extends StatelessWidget {
  final AprsMessage msg;
  const _MessageBubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final isOut = msg.dir == AprsMessageDir.outgoing;
    return Align(
      alignment: isOut ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: isOut ? Colors.blue[800] : Colors.grey[800],
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isOut ? 14 : 2),
            bottomRight: Radius.circular(isOut ? 2 : 14),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment:
              isOut ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Auth badge (incoming only)
            if (!isOut && msg.authResult != AprsAuthResult.unknown)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _AuthBadge(result: msg.authResult),
              ),

            // Message text
            Text(msg.text,
                style:
                    const TextStyle(color: Colors.white, fontSize: 14)),

            // Footer row
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(msg.ts),
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 10),
                ),
                if (isOut) ...[
                  const SizedBox(width: 4),
                  Icon(
                    msg.state == AprsMessageState.acked
                        ? Icons.done_all
                        : msg.state == AprsMessageState.rejected
                            ? Icons.error_outline
                            : Icons.done,
                    size: 12,
                    color: msg.state == AprsMessageState.acked
                        ? Colors.blue[300]
                        : msg.state == AprsMessageState.rejected
                            ? Colors.red[400]
                            : Colors.white38,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}

// ── Auth badge ─────────────────────────────────────────────────────────────────
class _AuthBadge extends StatelessWidget {
  final AprsAuthResult result;
  const _AuthBadge({required this.result});

  @override
  Widget build(BuildContext context) {
    final isVerified = result == AprsAuthResult.verified;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isVerified ? Icons.verified_user : Icons.gpp_bad_outlined,
          size: 11,
          color: isVerified ? Colors.green[400] : Colors.red[400],
        ),
        const SizedBox(width: 3),
        Text(
          isVerified ? 'Verified' : 'Auth failed',
          style: TextStyle(
            color: isVerified ? Colors.green[400] : Colors.red[400],
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

// ── Input bar ─────────────────────────────────────────────────────────────────
class _InputBar extends StatefulWidget {
  final TextEditingController controller;
  final int maxChars;
  final bool sending;
  final bool disabled;
  final VoidCallback onSend;

  const _InputBar({
    required this.controller,
    required this.maxChars,
    required this.sending,
    required this.disabled,
    required this.onSend,
  });

  @override
  State<_InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<_InputBar> {
  int _len = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_update);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_update);
    super.dispose();
  }

  void _update() => setState(() => _len = widget.controller.text.length);

  @override
  Widget build(BuildContext context) {
    final remaining = widget.maxChars - _len;
    final overLimit = remaining < 0;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: Colors.grey[900],
          border: Border(top: BorderSide(color: Colors.white12)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: widget.controller,
                enabled: !widget.disabled,
                maxLines: 3,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) {
                  if (!overLimit && !widget.disabled) widget.onSend();
                },
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: widget.disabled
                      ? 'Set callsign in Settings first'
                      : 'Message…',
                  hintStyle: const TextStyle(color: Colors.white38),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  filled: true,
                  fillColor: Colors.grey[850],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  suffix: Text(
                    '$remaining',
                    style: TextStyle(
                      color: overLimit ? Colors.red : Colors.white38,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (widget.sending)
              const SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              IconButton(
                icon: const Icon(Icons.send_rounded),
                color: overLimit || widget.disabled || _len == 0
                    ? Colors.white24
                    : Colors.blue[400],
                onPressed: overLimit || widget.disabled || _len == 0
                    ? null
                    : widget.onSend,
              ),
          ],
        ),
      ),
    );
  }
}
