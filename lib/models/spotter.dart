// lib/models/spotter.dart
// Spotter Network position from gr.txt public feed
class SpotterPosition {
  final String name;
  final double lat;
  final double lon;
  final double? speedMph;
  final double? heading;
  final String? timestamp;
  final String? note;

  const SpotterPosition({
    required this.name,
    required this.lat,
    required this.lon,
    this.speedMph,
    this.heading,
    this.timestamp,
    this.note,
  });
}
