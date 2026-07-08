// lib/models/mping_report.dart
class MpingReport {
  final int id;
  final double lat;
  final double lon;
  final String category;
  final String description;
  final DateTime timestamp;

  const MpingReport({
    required this.id,
    required this.lat,
    required this.lon,
    required this.category,
    required this.description,
    required this.timestamp,
  });

  factory MpingReport.fromJson(Map<String, dynamic> json) {
    final geometry = (json['geometry'] as Map<String, dynamic>?) ?? {};
    final coords = (geometry['coordinates'] as List?) ?? [];
    final props = (json['properties'] as Map<String, dynamic>?) ?? {};
    return MpingReport(
      id: (props['id'] as int?) ?? 0,
      lat: coords.length >= 2 ? (coords[1] as num).toDouble() : 0.0,
      lon: coords.length >= 2 ? (coords[0] as num).toDouble() : 0.0,
      category: (props['category'] as String?) ?? '',
      description: (props['description'] as String?) ?? '',
      timestamp:
          DateTime.tryParse((props['obtime'] as String?) ?? '') ??
          DateTime.now(),
    );
  }

  String get emoji {
    final cat = category.toLowerCase();
    if (cat.contains('tornado')) return '🌪️';
    if (cat.contains('hail')) return '🧊';
    if (cat.contains('wind')) return '💨';
    if (cat.contains('rain')) return '🌧️';
    if (cat.contains('snow') || cat.contains('ice')) return '❄️';
    if (cat.contains('flood')) return '🌊';
    return '⚠️';
  }

  String get timeAgo {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
}
