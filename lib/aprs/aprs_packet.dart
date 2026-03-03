// lib/aprs/aprs_packet.dart
// APRS packet data model
// Ported from aprs-parser by Lee K0QED (https://github.com/k0qed/aprs-parser)

class AprsPacket {
  final String callsign;
  final String? ssid;
  final String raw;
  final String? comment;
  final double? latitude;
  final double? longitude;
  final double? altitudeFeet;
  final double? speedKnots;
  final double? courseDegrees;
  final String? symbol;
  final String? symbolTable;
  final AprsPacketType type;
  final DateTime receivedAt;

  const AprsPacket({
    required this.callsign,
    this.ssid,
    required this.raw,
    this.comment,
    this.latitude,
    this.longitude,
    this.altitudeFeet,
    this.speedKnots,
    this.courseDegrees,
    this.symbol,
    this.symbolTable,
    required this.type,
    required this.receivedAt,
  });

  bool get hasPosition => latitude != null && longitude != null;

  String get fullCallsign => ssid != null ? '$callsign-$ssid' : callsign;

  String get timestampDisplay {
    final now = DateTime.now();
    final diff = now.difference(receivedAt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  /// Parse a raw APRS packet string
  /// Basic implementation - covers position reports and messages
  static AprsPacket? tryParse(String raw) {
    try {
      // Format: CALLSIGN-SSID>TOCALL,PATH:payload
      final colonIdx = raw.indexOf(':');
      if (colonIdx < 0) return null;

      final header = raw.substring(0, colonIdx);
      final payload = raw.substring(colonIdx + 1);
      if (payload.isEmpty) return null;

      final gtIdx = header.indexOf('>');
      if (gtIdx < 0) return null;

      final fromField = header.substring(0, gtIdx);
      final dashIdx = fromField.indexOf('-');
      final callsign = dashIdx >= 0 ? fromField.substring(0, dashIdx) : fromField;
      final ssid = dashIdx >= 0 ? fromField.substring(dashIdx + 1) : null;

      final type = _detectType(payload);
      double? lat, lon;
      String? symbol, symbolTable, comment;

      // Try to parse position from payload
      if (payload.length > 1) {
        final posResult = _tryParsePosition(payload);
        if (posResult != null) {
          lat = posResult['lat'];
          lon = posResult['lon'];
          symbol = posResult['symbol'];
          symbolTable = posResult['symbolTable'];
          comment = posResult['comment'];
        }
      }

      return AprsPacket(
        callsign: callsign.toUpperCase(),
        ssid: ssid,
        raw: raw,
        comment: comment,
        latitude: lat,
        longitude: lon,
        symbol: symbol,
        symbolTable: symbolTable,
        type: type,
        receivedAt: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  static AprsPacketType _detectType(String payload) {
    if (payload.isEmpty) return AprsPacketType.unknown;
    switch (payload[0]) {
      case '!': case '=': return AprsPacketType.positionNoTimestamp;
      case '/': case '@': return AprsPacketType.positionWithTimestamp;
      case ':': return AprsPacketType.message;
      case '>': return AprsPacketType.status;
      case ';': return AprsPacketType.object;
      case 'T': return AprsPacketType.telemetry;
      default: return AprsPacketType.unknown;
    }
  }

  /// Parse compressed or uncompressed APRS position
  static Map<String, dynamic>? _tryParsePosition(String payload) {
    // Uncompressed: !DDMM.mmN/DDDMM.mmW[symbol][comment]
    final uncompressedRe = RegExp(
      r'[!=/@](\d{4}\.\d{2})([NS])(.)(\d{5}\.\d{2})([EW])(.)(.*)',
    );
    final match = uncompressedRe.firstMatch(payload);
    if (match != null) {
      final latDeg = double.parse(match.group(1)!.substring(0, 2));
      final latMin = double.parse(match.group(1)!.substring(2));
      final latDir = match.group(2)!;
      final lonDeg = double.parse(match.group(4)!.substring(0, 3));
      final lonMin = double.parse(match.group(4)!.substring(3));
      final lonDir = match.group(5)!;
      final symTable = match.group(3)!;
      final sym = match.group(6)!;
      final cmt = match.group(7);

      double lat = latDeg + latMin / 60.0;
      double lon = lonDeg + lonMin / 60.0;
      if (latDir == 'S') lat = -lat;
      if (lonDir == 'W') lon = -lon;

      return {
        'lat': lat,
        'lon': lon,
        'symbol': sym,
        'symbolTable': symTable,
        'comment': cmt?.isNotEmpty == true ? cmt : null,
      };
    }
    return null;
  }
}

enum AprsPacketType {
  positionNoTimestamp,
  positionWithTimestamp,
  message,
  status,
  object,
  telemetry,
  unknown,
}
