// lib/services/bbs_service.dart
// Local BBS inbox using SQLite + Winlink HTTP API for send/receive.
// Callsign: KF0JKE

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/bbs_message.dart';

class BbsService extends ChangeNotifier {
  static const String _myCallsign = 'KF0JKE';
  static const String _winlinkBase = 'https://api.winlink.org';

  Database? _db;
  List<BbsMessage> _inbox = [];
  List<BbsMessage> _sent  = [];
  bool _isLoading = false;
  String? _error;

  List<BbsMessage> get inbox   => List.unmodifiable(_inbox);
  List<BbsMessage> get sent    => List.unmodifiable(_sent);
  bool get isLoading           => _isLoading;
  String? get error            => _error;
  int get unreadCount          => _inbox.where((m) => !m.read).length;

  Future<void> init() async {
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dbPath, 'bbs.db'),
      version: 1,
      onCreate: (db, version) => db.execute('''
        CREATE TABLE messages (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          from_call TEXT,
          to_call TEXT,
          subject TEXT,
          body TEXT,
          timestamp TEXT,
          read INTEGER DEFAULT 0
        )
      '''),
    );
    await _loadLocal();
  }

  Future<void> _loadLocal() async {
    if (_db == null) return;
    final rows = await _db!.query('messages', orderBy: 'timestamp DESC');
    final all = rows.map((r) => BbsMessage.fromMap(r)).toList();
    _inbox = all.where((m) => m.to.toUpperCase() == _myCallsign).toList();
    _sent  = all.where((m) => m.from.toUpperCase() == _myCallsign).toList();
    notifyListeners();
  }

  /// Poll Winlink for new messages addressed to KF0JKE.
  Future<void> fetchMessages() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Winlink API: GET /account/messages?callsign=KF0JKE&password=...
      // Using the public gateway endpoint (no auth for inbox listing)
      final uri = Uri.parse(
          '$_winlinkBase/account/messages?callsign=$_myCallsign&format=json');
      debugPrint('BBS: GET $uri');

      final response = await http
          .get(uri, headers: {
            'User-Agent': 'OpenHT/0.1 (github.com/repins267/OpenHT)',
            'Accept': 'application/json',
          })
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final messages = (data['Messages'] as List<dynamic>? ?? []);

        for (final m in messages) {
          final msg = BbsMessage(
            from: m['From'] as String? ?? '',
            to: m['To'] as String? ?? _myCallsign,
            subject: m['Subject'] as String? ?? '(no subject)',
            body: m['Body'] as String? ?? '',
            timestamp: m['Timestamp'] as String? ?? DateTime.now().toIso8601String(),
          );
          await _insertIfNew(msg);
        }

        await _loadLocal();
        debugPrint('BBS: Fetched ${messages.length} messages');
      } else {
        debugPrint('BBS: HTTP ${response.statusCode}');
        _error = 'Winlink HTTP ${response.statusCode}';
      }
    } catch (e) {
      debugPrint('BBS: Fetch error — $e');
      _error = 'Could not reach Winlink: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Send a message via Winlink HTTP gateway.
  Future<bool> sendMessage({
    required String to,
    required String subject,
    required String body,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final now = DateTime.now().toUtc().toIso8601String();

    try {
      final payload = {
        'From': _myCallsign,
        'To': to.toUpperCase(),
        'Subject': subject,
        'Body': body,
        'Date': now,
      };

      debugPrint('BBS: Sending message to $to via Winlink');

      final response = await http
          .post(
            Uri.parse('$_winlinkBase/message/submit'),
            headers: {
              'User-Agent': 'OpenHT/0.1 (github.com/repins267/OpenHT)',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 20));

      final success = response.statusCode == 200 || response.statusCode == 201;

      // Always save locally
      final local = BbsMessage(
        from: _myCallsign,
        to: to.toUpperCase(),
        subject: subject,
        body: body,
        timestamp: now,
        read: true,
      );
      await _db?.insert('messages', local.toMap());
      await _loadLocal();

      if (!success) {
        _error = 'Winlink send error: HTTP ${response.statusCode}';
        debugPrint('BBS: Send failed HTTP ${response.statusCode}: ${response.body}');
      }

      _isLoading = false;
      notifyListeners();
      return success;
    } catch (e) {
      debugPrint('BBS: Send error — $e');
      _error = 'Send failed: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> markRead(BbsMessage msg) async {
    if (_db == null || msg.id == null) return;
    await _db!.update('messages', {'read': 1},
        where: 'id = ?', whereArgs: [msg.id]);
    await _loadLocal();
  }

  Future<void> deleteMessage(BbsMessage msg) async {
    if (_db == null || msg.id == null) return;
    await _db!.delete('messages', where: 'id = ?', whereArgs: [msg.id]);
    await _loadLocal();
  }

  Future<void> _insertIfNew(BbsMessage msg) async {
    if (_db == null) return;
    final existing = await _db!.query(
      'messages',
      where: 'from_call = ? AND timestamp = ? AND subject = ?',
      whereArgs: [msg.from, msg.timestamp, msg.subject],
      limit: 1,
    );
    if (existing.isEmpty) {
      await _db!.insert('messages', msg.toMap());
    }
  }

  @override
  void dispose() {
    _db?.close();
    super.dispose();
  }
}
