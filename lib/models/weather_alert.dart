// lib/models/weather_alert.dart
// NOAA weather alert model (from api.weather.gov)

import 'package:flutter/material.dart';

class WeatherAlert {
  final String id;   // NWS alert ID for deduplication
  final String event;
  final String severity; // 'Extreme', 'Severe', 'Moderate', 'Minor', 'Unknown'
  final String headline;
  final String? description;
  final String? expires;
  final String? areaDesc;
  final List<String> sameCodes; // FIPS/SAME codes from geocode.SAME

  const WeatherAlert({
    required this.id,
    required this.event,
    required this.severity,
    required this.headline,
    this.description,
    this.expires,
    this.areaDesc,
    this.sameCodes = const [],
  });

  factory WeatherAlert.fromJson(Map<String, dynamic> json) {
    final props = json['properties'] as Map<String, dynamic>? ?? {};
    final geocode = props['geocode'] as Map<String, dynamic>? ?? {};
    final same = (geocode['SAME'] as List<dynamic>? ?? []).cast<String>();
    return WeatherAlert(
      id:          json['id'] as String? ?? '${props['event']}_${props['expires']}',
      event:       props['event']    as String? ?? 'Weather Alert',
      severity:    props['severity'] as String? ?? 'Unknown',
      headline:    props['headline'] as String? ?? '',
      description: props['description'] as String?,
      expires:     props['expires']  as String?,
      areaDesc:    props['areaDesc'] as String?,
      sameCodes:   same,
    );
  }

  Color get severityColor {
    switch (severity) {
      case 'Extreme':  return Colors.red;
      case 'Severe':   return Colors.orange;
      case 'Moderate': return Colors.yellow;
      case 'Minor':    return Colors.blue;
      default:         return Colors.grey;
    }
  }

  IconData get severityIcon {
    switch (severity) {
      case 'Extreme':  return Icons.warning_rounded;
      case 'Severe':   return Icons.warning_amber_rounded;
      case 'Moderate': return Icons.info_rounded;
      default:         return Icons.info_outline;
    }
  }
}
