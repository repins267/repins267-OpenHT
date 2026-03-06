// lib/models/nwr_station.dart
// NOAA Weather Radio station model

import 'dart:convert';

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

  Map<String, dynamic> toJson() => {
    'callSign': callSign, 'frequency': frequency,
    'city': city, 'state': state,
    'lat': lat, 'lon': lon,
    'sameCode': sameCode,
  };

  factory NwrStation.fromJson(Map<String, dynamic> j) => NwrStation(
    callSign:  j['callSign']  as String,
    frequency: (j['frequency'] as num).toDouble(),
    city:      j['city']      as String,
    state:     j['state']     as String,
    lat:       (j['lat']      as num).toDouble(),
    lon:       (j['lon']      as num).toDouble(),
    sameCode:  j['sameCode']  as String?,
  );

  static String listToJson(List<NwrStation> list) =>
      jsonEncode(list.map((s) => s.toJson()).toList());

  static List<NwrStation> listFromJson(String raw) {
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => NwrStation.fromJson(e as Map<String, dynamic>)).toList();
  }
}
