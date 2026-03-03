// lib/models/repeater.dart
// Data model for a repeater entry from RepeaterBook API

class Repeater {
  final String sysname;
  final double frequency;    // Output frequency in MHz
  final double? inputFreq;   // Input (offset) frequency
  final String? offset;      // Offset direction: '+', '-', 'S' (simplex)
  final String? tone;        // CTCSS tone (e.g. "100.0")
  final String? dtcs;        // DCS code if applicable
  final String? toneMode;    // 'CTCSS', 'DCS', 'NONE'
  final String? callsign;    // Trustee callsign
  final String? city;
  final String? state;
  final double latitude;
  final double longitude;
  final double? distanceMiles;
  final String? use;         // 'OPEN', 'CLOSED', 'PRIVATE'
  final String? operational; // 'On', 'Off', 'Unknown'
  final String? modes;       // FM, DMR, P25, etc.
  final String? notes;
  final DateTime? lastUpdated;

  const Repeater({
    required this.sysname,
    required this.frequency,
    this.inputFreq,
    this.offset,
    this.tone,
    this.dtcs,
    this.toneMode,
    this.callsign,
    this.city,
    this.state,
    required this.latitude,
    required this.longitude,
    this.distanceMiles,
    this.use,
    this.operational,
    this.modes,
    this.notes,
    this.lastUpdated,
  });

  /// Compute input frequency from output + offset string
  double get computedInputFreq {
    if (inputFreq != null) return inputFreq!;
    if (offset == null || offset == 'S') return frequency;
    // Standard offsets: +/- 0.6 MHz on 2m, +/- 5 MHz on 70cm
    final std = frequency >= 400 ? 5.0 : 0.6;
    return offset == '+' ? frequency + std : frequency - std;
  }

  String get displayFreq => '${frequency.toStringAsFixed(4)} MHz';

  String get displayTone {
    if (toneMode == 'DCS' && dtcs != null) return 'DCS $dtcs';
    if (toneMode == 'CTCSS' && tone != null) return 'PL $tone Hz';
    return 'No Tone';
  }

  String get displayDistance =>
      distanceMiles != null ? '${distanceMiles!.toStringAsFixed(1)} mi' : '';

  bool get isOpen => use == null || use!.toUpperCase() == 'OPEN';
  bool get isOnAir => operational == null || operational!.toLowerCase() == 'on';

  factory Repeater.fromRepeaterBookJson(Map<String, dynamic> json,
      {double? distanceMiles}) {
    return Repeater(
      sysname: json['Sysname'] ?? json['sysname'] ?? 'Unknown',
      frequency: _parseDouble(json['Frequency'] ?? json['frequency']),
      inputFreq: _parseDoubleOrNull(json['Input_Freq'] ?? json['input_freq']),
      offset: json['Offset'] ?? json['offset'],
      tone: json['PL'] ?? json['pl'] ?? json['tone'],
      dtcs: json['TSQ'] ?? json['tsq'],
      toneMode: _parseToneMode(json),
      callsign: json['Callsign'] ?? json['callsign'],
      city: json['Nearest_City'] ?? json['nearest_city'] ?? json['city'],
      state: json['State'] ?? json['state'],
      latitude: _parseDouble(json['Lat'] ?? json['lat']),
      longitude: _parseDouble(json['Long'] ?? json['long']),
      distanceMiles: distanceMiles,
      use: json['Use'] ?? json['use'],
      operational: json['Operational'] ?? json['operational'],
      modes: json['FM_Analog'] == 'Yes' ? 'FM' : (json['Digital_Code'] ?? 'FM'),
      notes: json['Notes'] ?? json['notes'],
    );
  }

  Map<String, dynamic> toMap() => {
        'sysname': sysname,
        'frequency': frequency,
        'input_freq': inputFreq,
        'offset': offset,
        'tone': tone,
        'dtcs': dtcs,
        'tone_mode': toneMode,
        'callsign': callsign,
        'city': city,
        'state': state,
        'latitude': latitude,
        'longitude': longitude,
        'distance_miles': distanceMiles,
        'use': use,
        'operational': operational,
        'modes': modes,
        'notes': notes,
      };

  factory Repeater.fromMap(Map<String, dynamic> map) => Repeater(
        sysname: map['sysname'],
        frequency: map['frequency'],
        inputFreq: map['input_freq'],
        offset: map['offset'],
        tone: map['tone'],
        dtcs: map['dtcs'],
        toneMode: map['tone_mode'],
        callsign: map['callsign'],
        city: map['city'],
        state: map['state'],
        latitude: map['latitude'],
        longitude: map['longitude'],
        distanceMiles: map['distance_miles'],
        use: map['use'],
        operational: map['operational'],
        modes: map['modes'],
        notes: map['notes'],
      );

  static double _parseDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  static double? _parseDoubleOrNull(dynamic v) {
    if (v == null) return null;
    final d = _parseDouble(v);
    return d == 0.0 ? null : d;
  }

  static String? _parseToneMode(Map<String, dynamic> json) {
    final pl = json['PL'] ?? json['pl'];
    final tsq = json['TSQ'] ?? json['tsq'];
    if (tsq != null && tsq.toString().isNotEmpty) return 'DCS';
    if (pl != null && pl.toString().isNotEmpty && pl != '0') return 'CTCSS';
    return 'NONE';
  }
}
