// lib/models/spotter_station.dart
// Storm spotter station model (from Spotter Network KML feed)

class SpotterStation {
  final String name;
  final double lat;
  final double lon;
  final String? lastReport;
  final String? reportType;
  final String? description;

  const SpotterStation({
    required this.name,
    required this.lat,
    required this.lon,
    this.lastReport,
    this.reportType,
    this.description,
  });
}
