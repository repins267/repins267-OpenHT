// lib/models/nws_alert.dart
import 'package:flutter/material.dart';

enum NwsAlertType { warning, watch, statement, advisory }

class NwsAlert {
  final String id;
  final String event;
  final String? headline;
  final String? description;
  final String? instruction;
  final String? areaDesc;
  final String? expires;
  final String severity;
  final NwsAlertType type;

  const NwsAlert({
    required this.id,
    required this.event,
    required this.severity,
    required this.type,
    this.headline,
    this.description,
    this.instruction,
    this.areaDesc,
    this.expires,
  });

  factory NwsAlert.fromJson(Map<String, dynamic> json) {
    final props = (json['properties'] as Map<String, dynamic>?) ?? {};
    final event = (props['event'] as String?) ?? '';
    final upper = event.toUpperCase();
    NwsAlertType type;
    if (upper.contains('WARNING')) {
      type = NwsAlertType.warning;
    } else if (upper.contains('WATCH')) {
      type = NwsAlertType.watch;
    } else if (upper.contains('STATEMENT')) {
      type = NwsAlertType.statement;
    } else {
      type = NwsAlertType.advisory;
    }
    return NwsAlert(
      id: (props['id'] as String?) ?? (json['id'] as String?) ?? '',
      event: event,
      severity: (props['severity'] as String?) ?? 'Unknown',
      type: type,
      headline: props['headline'] as String?,
      description: props['description'] as String?,
      instruction: props['instruction'] as String?,
      areaDesc: props['areaDesc'] as String?,
      expires: props['expires'] as String?,
    );
  }

  Color get severityColor {
    switch (type) {
      case NwsAlertType.warning:   return Colors.red;
      case NwsAlertType.watch:     return Colors.orange;
      case NwsAlertType.statement: return Colors.yellow;
      case NwsAlertType.advisory:  return Colors.blue;
    }
  }

  IconData get severityIcon {
    switch (type) {
      case NwsAlertType.warning:   return Icons.warning_rounded;
      case NwsAlertType.watch:     return Icons.watch_later_outlined;
      case NwsAlertType.statement: return Icons.info_outline;
      case NwsAlertType.advisory:  return Icons.announcement_outlined;
    }
  }

  String get typeLabel {
    switch (type) {
      case NwsAlertType.warning:   return 'WARNING';
      case NwsAlertType.watch:     return 'WATCH';
      case NwsAlertType.statement: return 'STATEMENT';
      case NwsAlertType.advisory:  return 'ADVISORY';
    }
  }

  String get expiresCountdown {
    if (expires == null) return '';
    final t = DateTime.tryParse(expires!);
    if (t == null) return '';
    final diff = t.difference(DateTime.now());
    if (diff.isNegative) return 'Expired';
    if (diff.inMinutes < 60) return 'Expires in ${diff.inMinutes}m';
    return 'Expires in ${diff.inHours}h ${diff.inMinutes % 60}m';
  }
}
