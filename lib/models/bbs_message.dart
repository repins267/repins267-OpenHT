// lib/models/bbs_message.dart
// Local BBS inbox message model (Winlink-style)

class BbsMessage {
  final int? id;
  final String from;
  final String to;
  final String subject;
  final String body;
  final String timestamp; // ISO 8601
  final bool read;

  const BbsMessage({
    this.id,
    required this.from,
    required this.to,
    required this.subject,
    required this.body,
    required this.timestamp,
    this.read = false,
  });

  BbsMessage copyWith({bool? read}) => BbsMessage(
        id: id,
        from: from,
        to: to,
        subject: subject,
        body: body,
        timestamp: timestamp,
        read: read ?? this.read,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'from_call': from,
        'to_call': to,
        'subject': subject,
        'body': body,
        'timestamp': timestamp,
        'read': read ? 1 : 0,
      };

  factory BbsMessage.fromMap(Map<String, dynamic> m) => BbsMessage(
        id: m['id'] as int?,
        from: m['from_call'] as String? ?? '',
        to: m['to_call'] as String? ?? '',
        subject: m['subject'] as String? ?? '',
        body: m['body'] as String? ?? '',
        timestamp: m['timestamp'] as String? ?? '',
        read: (m['read'] as int? ?? 0) == 1,
      );

  String get displayTime {
    try {
      final dt = DateTime.parse(timestamp).toLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2,"0")}-'
          '${dt.day.toString().padLeft(2,"0")} '
          '${dt.hour.toString().padLeft(2,"0")}:'
          '${dt.minute.toString().padLeft(2,"0")}';
    } catch (_) {
      return timestamp;
    }
  }
}
