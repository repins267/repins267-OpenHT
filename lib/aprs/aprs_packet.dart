// lib/aprs/aprs_packet.dart
// APRS packet data model

enum AprsSource { rf, aprsIs }

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
  final AprsSource source;
  final String? digiPath; // e.g. "WIDE1-1,KD0XYZ*" (RF only)

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
    this.source = AprsSource.aprsIs,
    this.digiPath,
  });

  /// Number of digipeater hops (RF only; 0 = heard direct).
  int get rfHops {
    if (source != AprsSource.rf || digiPath == null) return 0;
    return digiPath!.split(',').where((p) => p.endsWith('*')).length;
  }

  /// True if heard direct (RF, 0 hops).
  bool get isDirect => source == AprsSource.rf && rfHops == 0;

  bool get hasPosition => latitude != null && longitude != null;

  String get fullCallsign => ssid != null ? '$callsign-$ssid' : callsign;

  String get timestampDisplay {
    final now = DateTime.now();
    final diff = now.difference(receivedAt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  /// Parse a raw APRS packet string.
  /// [source] — tag as RF or APRS-IS at the call site.
  static AprsPacket? tryParse(String raw,
      {AprsSource source = AprsSource.aprsIs}) {
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

      // Extract digi path (everything after first comma in header path, skip q-codes)
      String? digiPath;
      final pathField = header.substring(gtIdx + 1);
      final pathParts = pathField.split(',');
      if (pathParts.length > 1) {
        final digiParts = pathParts.skip(1)
            .where((p) => !p.startsWith('q') && p != 'TCPIP*' && p != 'TCPXX*')
            .toList();
        if (digiParts.isNotEmpty) digiPath = digiParts.join(',');
      }

      final type = _detectType(payload);
      double? lat, lon;
      String? symbol, symbolTable, comment;

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
        source: source,
        digiPath: digiPath,
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

  /// Parse compressed or uncompressed APRS position.
  /// Handles: uncompressed (with or without timestamp), compressed base91.
  static Map<String, dynamic>? _tryParsePosition(String payload) {
    if (payload.isEmpty) return null;

    // For / and @ packets strip the 7-char timestamp (DDHHMMz / HHMMSSh / etc.)
    // so the position block starts right after.
    String pos = payload;
    if ((payload[0] == '/' || payload[0] == '@') && payload.length >= 8) {
      pos = payload[0] + payload.substring(8);
    }

    // ── Uncompressed: [!=/@]DDMM.mmN/DDDMM.mmW[sym][comment] ────────────────
    final ucRe = RegExp(r'[!=/@](\d{4}\.\d{2})([NS])(.)(\d{5}\.\d{2})([EW])(.*)');
    final ucm = ucRe.firstMatch(pos);
    if (ucm != null) {
      final latDeg = double.parse(ucm.group(1)!.substring(0, 2));
      final latMin = double.parse(ucm.group(1)!.substring(2));
      final latDir = ucm.group(2)!;
      final lonDeg = double.parse(ucm.group(4)!.substring(0, 3));
      final lonMin = double.parse(ucm.group(4)!.substring(3));
      final lonDir = ucm.group(5)!;
      final rest   = ucm.group(6) ?? '';
      final sym      = rest.isNotEmpty ? rest[0] : '';
      final symTable = ucm.group(3)!;
      final cmt      = rest.length > 1 ? rest.substring(1) : null;

      double lat = latDeg + latMin / 60.0;
      double lon = lonDeg + lonMin / 60.0;
      if (latDir == 'S') lat = -lat;
      if (lonDir == 'W') lon = -lon;

      return {'lat': lat, 'lon': lon, 'symbol': sym, 'symbolTable': symTable,
              'comment': cmt?.isNotEmpty == true ? cmt : null};
    }

    // ── Compressed base91: [!/=@]<symTable><lat4><lon4><symbol>[cs][T][cmt] ─
    // Minimum: 1 type + 1 symTable + 4 lat + 4 lon + 1 symbol = 11 chars
    if (pos.length >= 11) {
      final symTable = pos[1];
      final latS = pos.substring(2, 6);
      final lonS = pos.substring(6, 10);
      final sym  = pos[10];

      // Base91 chars must be in range 33–124 and NOT all decimal digits
      bool isBase91(String s) =>
          s.codeUnits.every((c) => c >= 33 && c <= 124) &&
          !RegExp(r'^\d+$').hasMatch(s);

      if (isBase91(latS) && isBase91(lonS)) {
        int b91(String s) =>
            (s.codeUnitAt(0) - 33) * 753571 +
            (s.codeUnitAt(1) - 33) * 8281 +
            (s.codeUnitAt(2) - 33) * 91 +
            (s.codeUnitAt(3) - 33);

        final lat = 90.0  - b91(latS) / 380926.0;
        final lon = -180.0 + b91(lonS) / 190463.0;

        // Sanity-check decoded coordinates
        if (lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180) {
          final cmt = pos.length > 13 ? pos.substring(13) : null;
          return {'lat': lat, 'lon': lon, 'symbol': sym, 'symbolTable': symTable,
                  'comment': cmt?.isNotEmpty == true ? cmt : null};
        }
      }
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
