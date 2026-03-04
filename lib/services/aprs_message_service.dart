// lib/services/aprs_message_service.dart
// APRS message store — persists TNC2 `:` packets to SQLite
// Handles send / receive / ack / threading by callsign

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../services/aprs_auth_service.dart';

// ─── Message model ─────────────────────────────────────────────────────────────
enum AprsMessageDir { incoming, outgoing }
enum AprsMessageState { pending, acked, rejected }

class AprsMessage {
  final int? id;
  final DateTime ts;
  final String peerCallsign;   // full callsign including SSID
  final AprsMessageDir dir;
  final String msgId;          // APRS message number (e.g. "001")
  final String text;           // clean body (tag stripped)
  final AprsAuthResult authResult;
  final AprsMessageState state;
  final bool read;

  const AprsMessage({
    this.id,
    required this.ts,
    required this.peerCallsign,
    required this.dir,
    required this.msgId,
    required this.text,
    required this.authResult,
    required this.state,
    required this.read,
  });

  AprsMessage copyWith({AprsMessageState? state, bool? read}) => AprsMessage(
        id: id,
        ts: ts,
        peerCallsign: peerCallsign,
        dir: dir,
        msgId: msgId,
        text: text,
        authResult: authResult,
        state: state ?? this.state,
        read: read ?? this.read,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'ts': ts.millisecondsSinceEpoch,
        'peer': peerCallsign,
        'dir': dir.index,
        'msg_id': msgId,
        'text': text,
        'auth': authResult.index,
        'state': state.index,
        'read': read ? 1 : 0,
      };

  factory AprsMessage.fromMap(Map<String, dynamic> m) => AprsMessage(
        id: m['id'] as int?,
        ts: DateTime.fromMillisecondsSinceEpoch(m['ts'] as int),
        peerCallsign: m['peer'] as String,
        dir: AprsMessageDir.values[m['dir'] as int],
        msgId: m['msg_id'] as String,
        text: m['text'] as String,
        authResult: AprsAuthResult.values[m['auth'] as int],
        state: AprsMessageState.values[m['state'] as int],
        read: (m['read'] as int) == 1,
      );
}

// ─── Conversation summary ──────────────────────────────────────────────────────
class Conversation {
  final String peerCallsign;
  final AprsMessage lastMessage;
  final int unreadCount;

  const Conversation({
    required this.peerCallsign,
    required this.lastMessage,
    required this.unreadCount,
  });
}

// ─── Service ───────────────────────────────────────────────────────────────────
class AprsMessageService extends ChangeNotifier {
  static const _dbName = 'aprs_messages.db';
  static const _version = 1;

  Database? _db;
  int _nextMsgId = 1;

  // ── Init ───────────────────────────────────────────────────────────────────
  Future<void> open() async {
    if (_db != null) return;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, _dbName);
    _db = await openDatabase(
      path,
      version: _version,
      onCreate: (db, _) => db.execute('''
        CREATE TABLE messages (
          id      INTEGER PRIMARY KEY AUTOINCREMENT,
          ts      INTEGER NOT NULL,
          peer    TEXT    NOT NULL,
          dir     INTEGER NOT NULL,
          msg_id  TEXT    NOT NULL,
          text    TEXT    NOT NULL,
          auth    INTEGER NOT NULL DEFAULT 2,
          state   INTEGER NOT NULL DEFAULT 0,
          read    INTEGER NOT NULL DEFAULT 0
        )
      '''),
    );
    // seed next msg ID from max outgoing
    final rows = await _db!.rawQuery(
        "SELECT msg_id FROM messages WHERE dir=1 ORDER BY id DESC LIMIT 1");
    if (rows.isNotEmpty) {
      final last = rows.first['msg_id'] as String;
      _nextMsgId = (int.tryParse(last) ?? 0) + 1;
    }
  }

  void _requireDb() {
    if (_db == null) throw StateError('AprsMessageService not opened');
  }

  // ── Conversations list ─────────────────────────────────────────────────────
  Future<List<Conversation>> getConversations() async {
    _requireDb();
    // Get distinct peers ordered by latest message ts
    final peers = await _db!.rawQuery('''
      SELECT peer FROM messages GROUP BY peer ORDER BY MAX(ts) DESC
    ''');
    final conversations = <Conversation>[];
    for (final row in peers) {
      final peer = row['peer'] as String;
      final last = await getThread(peer, limit: 1);
      if (last.isEmpty) continue;
      final unread = await _unreadCount(peer);
      conversations.add(Conversation(
        peerCallsign: peer,
        lastMessage: last.first,
        unreadCount: unread,
      ));
    }
    return conversations;
  }

  Future<int> _unreadCount(String peer) async {
    final result = await _db!.rawQuery(
        "SELECT COUNT(*) as c FROM messages WHERE peer=? AND read=0 AND dir=0",
        [peer]);
    return (result.first['c'] as int?) ?? 0;
  }

  Future<int> get totalUnread async {
    _requireDb();
    final result = await _db!.rawQuery(
        "SELECT COUNT(*) as c FROM messages WHERE read=0 AND dir=0");
    return (result.first['c'] as int?) ?? 0;
  }

  // ── Thread ─────────────────────────────────────────────────────────────────
  Future<List<AprsMessage>> getThread(String peer,
      {int limit = 100, int offset = 0}) async {
    _requireDb();
    final rows = await _db!.query(
      'messages',
      where: 'peer = ?',
      whereArgs: [peer.toUpperCase()],
      orderBy: 'ts DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(AprsMessage.fromMap).toList().reversed.toList();
  }

  // ── Store incoming message (from packet stream) ────────────────────────────
  /// Parse an APRS `:` payload and store it.
  /// [fromCallsign] — the full sender callsign (e.g. "W0ABC-9")
  /// [payload]     — everything after the first `:` in the raw packet
  Future<void> handleIncomingPacket(
    String fromCallsign,
    String payload, {
    AprsAuthResult authResult = AprsAuthResult.unknown,
  }) async {
    _requireDb();
    // APRS message format:  :ADDRESSEE :text{msgid}
    // payload starts with ':'
    if (!payload.startsWith(':')) return;
    final rest = payload.substring(1);
    final addrEnd = rest.indexOf(':');
    if (addrEnd < 0) return;
    final body = rest.substring(addrEnd + 1);

    // Check if this is an ack/rej
    if (body.startsWith('ack') || body.startsWith('rej')) {
      final msgId = body.substring(3).trim();
      await _updateState(
          fromCallsign.toUpperCase(),
          msgId,
          body.startsWith('ack')
              ? AprsMessageState.acked
              : AprsMessageState.rejected);
      notifyListeners();
      return;
    }

    // Parse message id from body: text{msgid}
    String text = body;
    String msgId = '';
    final braceIdx = body.lastIndexOf('{');
    if (braceIdx >= 0) {
      msgId = body.substring(braceIdx + 1).replaceAll('}', '').trim();
      text = body.substring(0, braceIdx).trim();
    }

    // Strip auth tag from text
    text = AprsAuthService.stripTag(text);

    final msg = AprsMessage(
      ts: DateTime.now(),
      peerCallsign: fromCallsign.toUpperCase(),
      dir: AprsMessageDir.incoming,
      msgId: msgId,
      text: text,
      authResult: authResult,
      state: AprsMessageState.pending,
      read: false,
    );
    await _db!.insert('messages', msg.toMap());
    notifyListeners();
  }

  // ── Outgoing message ───────────────────────────────────────────────────────
  Future<AprsMessage> createOutgoing({
    required String toCallsign,
    required String text,
  }) async {
    _requireDb();
    final msgId = (_nextMsgId++).toString().padLeft(3, '0');
    final msg = AprsMessage(
      ts: DateTime.now(),
      peerCallsign: toCallsign.toUpperCase(),
      dir: AprsMessageDir.outgoing,
      msgId: msgId,
      text: text,
      authResult: AprsAuthResult.unknown,
      state: AprsMessageState.pending,
      read: true,
    );
    final id = await _db!.insert('messages', msg.toMap());
    final stored = AprsMessage(
      id: id,
      ts: msg.ts,
      peerCallsign: msg.peerCallsign,
      dir: msg.dir,
      msgId: msg.msgId,
      text: msg.text,
      authResult: msg.authResult,
      state: msg.state,
      read: msg.read,
    );
    notifyListeners();
    return stored;
  }

  // ── Mark thread as read ────────────────────────────────────────────────────
  Future<void> markRead(String peer) async {
    _requireDb();
    await _db!.update(
      'messages',
      {'read': 1},
      where: "peer = ? AND read = 0 AND dir = 0",
      whereArgs: [peer.toUpperCase()],
    );
    notifyListeners();
  }

  // ── Update ack/rej state ───────────────────────────────────────────────────
  Future<void> _updateState(
      String peer, String msgId, AprsMessageState state) async {
    await _db!.update(
      'messages',
      {'state': state.index},
      where: "peer = ? AND msg_id = ? AND dir = 1",
      whereArgs: [peer, msgId],
    );
  }

  /// Format the TNC2 APRS message packet body for sending via APRS-IS.
  /// Returns the full line to write to the socket:
  ///   MYCALL>APRS,PATH::DEST     :text{msgid}
  static String formatOutgoingLine({
    required String myCallsign,
    required String mySsid,
    required String path,
    required String toCallsign,
    required String text,
    required String msgId,
  }) {
    final from = mySsid.isNotEmpty ? '$myCallsign-$mySsid' : myCallsign;
    final dest = toCallsign.toUpperCase().padRight(9);
    return '$from>APRS,$path::$dest:$text{$msgId}';
  }

  @override
  void dispose() {
    _db?.close();
    super.dispose();
  }
}
