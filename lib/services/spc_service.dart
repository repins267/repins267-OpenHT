// lib/services/spc_service.dart
// Fetches SPC convective outlook GeoJSON (Day 1/2/3) and mesoscale discussions.
// Polls every 15 minutes — SPC products update roughly hourly.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/spc_outlook.dart';

class SpcService extends ChangeNotifier {
  static const _pollInterval = Duration(minutes: 15);

  List<SpcDayOutlook> _outlooks = [];
  List<SpcMd> _mds = [];
  bool _isLoading = false;
  String? _error;
  Timer? _timer;

  List<SpcDayOutlook> get outlooks => List.unmodifiable(_outlooks);
  List<SpcMd> get mesoscaleDiscussions => List.unmodifiable(_mds);
  bool get isLoading => _isLoading;
  String? get error => _error;

  SpcDayOutlook? get day1 =>
      _outlooks.where((o) => o.day == 1).firstOrNull;
  SpcDayOutlook? get day2 =>
      _outlooks.where((o) => o.day == 2).firstOrNull;
  SpcDayOutlook? get day3 =>
      _outlooks.where((o) => o.day == 3).firstOrNull;

  void startPolling() {
    _timer?.cancel();
    fetch();
    _timer = Timer.periodic(_pollInterval, (_) => fetch());
  }

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> fetch() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final d1 = await _fetchDay(1);
      final d2 = await _fetchDay(2);
      final d3 = await _fetchDay(3);
      final mds = await _fetchMds();
      _outlooks = [d1, d2, d3].whereType<SpcDayOutlook>().toList();
      _mds = mds;
      _error = null;
    } catch (e) {
      debugPrint('SpcService: $e');
      if (_outlooks.isEmpty) _error = 'SPC data unavailable';
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<SpcDayOutlook?> _fetchDay(int day) async {
    try {
      final url =
          'https://www.spc.noaa.gov/products/outlook/day${day}otlk_cat.lyr.geojson';
      final resp = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'OpenHT/0.1',
      }).timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final features = (data['features'] as List?) ?? [];
      String maxRisk = '';
      int maxSeverity = -1;
      String? issued;
      for (final f in features) {
        final props =
            ((f as Map<String, dynamic>)['properties'] as Map<String, dynamic>?) ??
            {};
        final label = ((props['LABEL'] as String?) ??
                (props['label'] as String?) ??
                '')
            .trim()
            .toUpperCase();
        issued ??= (props['ISSUE'] as String?) ?? (props['VALID'] as String?);
        final sev = SpcRisk.severity(label);
        if (sev > maxSeverity) {
          maxSeverity = sev;
          maxRisk = label;
        }
      }
      return SpcDayOutlook(
        day: day,
        maxRisk: maxRisk.isEmpty ? 'NONE' : maxRisk,
        issued: issued,
      );
    } catch (e) {
      debugPrint('SpcService: day$day error — $e');
      return null;
    }
  }

  Future<List<SpcMd>> _fetchMds() async {
    try {
      const url =
          'https://www.spc.noaa.gov/products/md/current_md.lyr.geojson';
      final resp = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'OpenHT/0.1',
      }).timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final features = (data['features'] as List?) ?? [];
      return features.map((f) {
        final props =
            ((f as Map<String, dynamic>)['properties'] as Map<String, dynamic>?) ??
            {};
        final num = props['MDNUM'] ?? props['mdnum'] ?? '';
        final url = (props['URL'] as String?) ?? (props['url'] as String?);
        final text =
            (props['DISCUSSION'] as String?) ?? (props['text'] as String?);
        return SpcMd(title: 'MD #$num', url: url, text: text);
      }).toList();
    } catch (e) {
      debugPrint('SpcService: MDs error — $e');
      return [];
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
