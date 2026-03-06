// lib/services/freq_plan_service.dart
// Served-agency frequency plan loader and radio writer.
// Plans live in assets/freq_plans/<id>.json

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../bluetooth/radio_service.dart';

// ─── Models ──────────────────────────────────────────────────────────────────

class FreqPlanChannel {
  final int    slot;
  final String name;
  final double rxMhz;
  final double txMhz;
  final double tone;   // 0.0 = no tone
  final String notes;

  const FreqPlanChannel({
    required this.slot,
    required this.name,
    required this.rxMhz,
    required this.txMhz,
    required this.tone,
    required this.notes,
  });

  factory FreqPlanChannel.fromJson(Map<String, dynamic> json) {
    return FreqPlanChannel(
      slot:  json['slot']  as int,
      name:  json['name']  as String,
      rxMhz: (json['rxMhz'] as num).toDouble(),
      txMhz: (json['txMhz'] as num).toDouble(),
      tone:  (json['tone']  as num).toDouble(),
      notes: json['notes'] as String? ?? '',
    );
  }
}

class FreqPlan {
  final String id;
  final String name;
  final String fips;   // 6-digit county FIPS / SAME code
  final List<FreqPlanChannel> channels;

  const FreqPlan({
    required this.id,
    required this.name,
    required this.fips,
    required this.channels,
  });

  factory FreqPlan.fromJson(Map<String, dynamic> json) {
    return FreqPlan(
      id:       json['id']   as String,
      name:     json['name'] as String,
      fips:     json['fips'] as String,
      channels: (json['channels'] as List<dynamic>)
          .map((c) => FreqPlanChannel.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }
}

// ─── Service ─────────────────────────────────────────────────────────────────

class FreqPlanService {
  /// Load a frequency plan from assets/freq_plans/[planId].json.
  /// Returns null if the plan cannot be loaded.
  static Future<FreqPlan?> loadPlan(String planId) async {
    try {
      final raw = await rootBundle.loadString('assets/freq_plans/$planId.json');
      return FreqPlan.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('FreqPlanService: Failed to load $planId: $e');
      return null;
    }
  }

  /// Write all channels from [plan] into [groupIndex] (0-indexed, 0 = Group 1).
  ///
  /// Yields the running count of successfully written channels so the caller
  /// can drive a "Writing N/M…" progress indicator.
  ///
  /// Example — write to Group 3 (groupIndex = 2):
  /// ```dart
  /// await for (final n in FreqPlanService.writePlanToRadio(plan, 2, radio)) {
  ///   setState(() => _written = n);
  /// }
  /// ```
  static Stream<int> writePlanToRadio(
    FreqPlan plan,
    int groupIndex,
    RadioService radio,
  ) async* {
    // Switch to channel mode so writes persist to radio memory (same as bulkWriteNearRepeaterGroup).
    final prevVfoX = await radio.beginBulkWrite();
    int written = 0;
    try {
      for (final ch in plan.channels) {
        final ok = await radio.writeRegionChannel(
          groupIndex: groupIndex,
          slotIndex:  ch.slot,
          rxFreqMhz:  ch.rxMhz,
          txFreqMhz:  ch.txMhz,
          ctcssHz:    ch.tone > 0 ? ch.tone : null,
          name:       ch.name,
        );
        if (ok) written++;
        yield written;
        await Future.delayed(const Duration(milliseconds: 150));
      }
    } finally {
      await radio.endBulkWrite(prevVfoX);
    }
  }
}
