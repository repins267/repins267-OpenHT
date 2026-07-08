// lib/services/freq_plan_service.dart
// Served-agency frequency plan loader and radio writer.
// Plans live in assets/freq_plans/<id>.json

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
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

  Map<String, dynamic> toJson() => {
        'slot': slot,
        'name': name,
        'rxMhz': rxMhz,
        'txMhz': txMhz,
        'tone': tone,
        'notes': notes,
      };

  FreqPlanChannel copyWith({
    int? slot,
    String? name,
    double? rxMhz,
    double? txMhz,
    double? tone,
    String? notes,
  }) =>
      FreqPlanChannel(
        slot: slot ?? this.slot,
        name: name ?? this.name,
        rxMhz: rxMhz ?? this.rxMhz,
        txMhz: txMhz ?? this.txMhz,
        tone: tone ?? this.tone,
        notes: notes ?? this.notes,
      );
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
      fips:     json['fips'] as String? ?? '',
      channels: (json['channels'] as List<dynamic>)
          .map((c) => FreqPlanChannel.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'fips': fips,
        'channels': channels.map((c) => c.toJson()).toList(),
      };

  FreqPlan copyWith({
    String? id,
    String? name,
    String? fips,
    List<FreqPlanChannel>? channels,
  }) =>
      FreqPlan(
        id: id ?? this.id,
        name: name ?? this.name,
        fips: fips ?? this.fips,
        channels: channels ?? this.channels,
      );
}

// ─── Service ─────────────────────────────────────────────────────────────────

/// Lightweight plan descriptor for list UIs.
class FreqPlanMeta {
  final String id;
  final String name;
  final int channelCount;
  final bool isUser; // true = user-created/edited (editable), false = bundled template
  const FreqPlanMeta({
    required this.id,
    required this.name,
    required this.channelCount,
    required this.isUser,
  });
}

class FreqPlanService {
  /// Bundled read-only plan templates (assets/freq_plans/<id>.json).
  static const List<String> bundledIds = ['ppraa_el_paso'];

  static Future<Directory> _userDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/freq_plans');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Slugify a plan name into a stable file id.
  static String idForName(String name) {
    final s = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_|_$'), '');
    return s.isEmpty ? 'plan' : s;
  }

  /// List all plans (bundled + user). A user plan with the same id overrides the
  /// bundled one (i.e. an edited copy shadows the template).
  static Future<List<FreqPlanMeta>> listPlans() async {
    final metas = <String, FreqPlanMeta>{};
    for (final id in bundledIds) {
      final p = await _loadFromAsset(id);
      if (p != null) {
        metas[id] = FreqPlanMeta(id: id, name: p.name, channelCount: p.channels.length, isUser: false);
      }
    }
    try {
      final dir = await _userDir();
      for (final f in dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
        try {
          final p = FreqPlan.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
          metas[p.id] = FreqPlanMeta(id: p.id, name: p.name, channelCount: p.channels.length, isUser: true);
        } catch (_) {}
      }
    } catch (_) {}
    final list = metas.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  /// Load a plan by id — a user copy (editable) takes precedence over the bundled template.
  static Future<FreqPlan?> loadPlan(String planId) async {
    try {
      final dir = await _userDir();
      final f = File('${dir.path}/$planId.json');
      if (await f.exists()) {
        return FreqPlan.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
      }
    } catch (_) {}
    return _loadFromAsset(planId);
  }

  static Future<FreqPlan?> _loadFromAsset(String planId) async {
    try {
      final raw = await rootBundle.loadString('assets/freq_plans/$planId.json');
      return FreqPlan.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('FreqPlanService: Failed to load asset $planId: $e');
      return null;
    }
  }

  /// Save (create or overwrite) a user plan to app storage.
  static Future<void> savePlan(FreqPlan plan) async {
    final dir = await _userDir();
    await File('${dir.path}/${plan.id}.json').writeAsString(jsonEncode(plan.toJson()));
  }

  /// Delete a user plan. Bundled templates cannot be deleted (this only removes
  /// the user copy; the bundled template reappears in the list if one exists).
  static Future<void> deletePlan(String planId) async {
    final dir = await _userDir();
    final f = File('${dir.path}/$planId.json');
    if (await f.exists()) await f.delete();
  }

  /// True if [planId] has a bundled template (so it can't be truly deleted, only reset).
  static bool isBundled(String planId) => bundledIds.contains(planId);

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
      // Clear leftover channels outside the plan's slots so the group holds
      // only the plan's channels.
      await radio.clearRegionSlotsExcept(
          groupIndex, plan.channels.map((c) => c.slot).toSet());
      // Name the group after the plan (device stores 10 chars). Use the first
      // token before a separator so "PPRAA / PPARES — El Paso County" → "PPRAA"
      // rather than a garbled 10-char truncation of the full title.
      final short = plan.name.split(RegExp(r'\s*[/—–-]\s*')).first.trim();
      await radio.setGroupName(groupIndex, short.isEmpty ? plan.name : short);
    } finally {
      await radio.endBulkWrite(prevVfoX);
    }
  }
}
