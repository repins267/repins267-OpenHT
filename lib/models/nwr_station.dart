// lib/models/nwr_station.dart
// NOAA Weather Radio station model

class NwrStation {
  final String callSign;
  final double frequency; // MHz, e.g. 162.400
  final String city;
  final String state;
  final double lat;
  final double lon;
  final String? sameCode;
  final double? distanceMiles;

  const NwrStation({
    required this.callSign,
    required this.frequency,
    required this.city,
    required this.state,
    required this.lat,
    required this.lon,
    this.sameCode,
    this.distanceMiles,
  });

  String get displayFreq => '${frequency.toStringAsFixed(3)} MHz';

  String get displayDistance => distanceMiles != null
      ? '${distanceMiles!.toStringAsFixed(1)} mi'
      : '';
}
