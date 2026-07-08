// lib/models/spc_outlook.dart
import 'package:flutter/material.dart';

class SpcRisk {
  static Color color(String cat) {
    switch (cat.toUpperCase()) {
      case 'TSTM': return const Color(0xFF39A639);
      case 'MRGL': return const Color(0xFF92DA92);
      case 'SLGT': return const Color(0xFFF6F67B);
      case 'ENH':  return const Color(0xFFE8C03E);
      case 'MDT':  return const Color(0xFFF6711F);
      case 'HIGH': return const Color(0xFFFF0000);
      default:     return Colors.grey;
    }
  }

  static String label(String cat) {
    switch (cat.toUpperCase()) {
      case 'TSTM': return 'Thunderstorm';
      case 'MRGL': return 'Marginal';
      case 'SLGT': return 'Slight';
      case 'ENH':  return 'Enhanced';
      case 'MDT':  return 'Moderate';
      case 'HIGH': return 'High';
      default:     return cat.isNotEmpty ? cat : 'None';
    }
  }

  static int severity(String cat) {
    const order = ['TSTM', 'MRGL', 'SLGT', 'ENH', 'MDT', 'HIGH'];
    final idx = order.indexOf(cat.toUpperCase());
    return idx < 0 ? -1 : idx;
  }
}

class SpcDayOutlook {
  final int day;
  final String maxRisk;
  final String? issued;

  const SpcDayOutlook({
    required this.day,
    required this.maxRisk,
    this.issued,
  });
}

class SpcMd {
  final String title;
  final String? url;
  final String? text;

  const SpcMd({required this.title, this.url, this.text});
}
