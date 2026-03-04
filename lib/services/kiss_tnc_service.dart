// lib/services/kiss_tnc_service.dart
// KISS TNC frame encoder/decoder for AX.25 packet radio
// KISS spec: http://www.ax25.net/kiss.aspx
//
// Frame format:
//   FEND(0xC0) CMD(0x00) DATA FEND(0xC0)
// Escaping:
//   0xC0 in data → FESC(0xDB) TFEND(0xDC)
//   0xDB in data → FESC(0xDB) TFESC(0xDD)

import 'dart:typed_data';
import 'package:flutter/foundation.dart';

const int _fend  = 0xC0;
const int _fesc  = 0xDB;
const int _tfend = 0xDC;
const int _tfesc = 0xDD;
const int _cmdData = 0x00; // port 0, data frame

class KissTncService {
  // ── Encode AX.25 payload into a KISS data frame ──────────────────────────
  static Uint8List encode(Uint8List ax25Payload) {
    final buf = BytesBuilder();
    buf.addByte(_fend);
    buf.addByte(_cmdData);
    for (final byte in ax25Payload) {
      if (byte == _fend) {
        buf.addByte(_fesc);
        buf.addByte(_tfend);
      } else if (byte == _fesc) {
        buf.addByte(_fesc);
        buf.addByte(_tfesc);
      } else {
        buf.addByte(byte);
      }
    }
    buf.addByte(_fend);
    return buf.toBytes();
  }

  // ── Decode KISS frames from a raw byte stream ─────────────────────────────
  // [bytes] may contain multiple frames or partial frames.
  // Returns a list of decoded AX.25 payload buffers.
  static List<Uint8List> decode(Uint8List bytes) {
    final frames = <Uint8List>[];
    final current = <int>[];
    bool inFrame = false;
    bool escape = false;

    for (final byte in bytes) {
      if (byte == _fend) {
        if (inFrame && current.isNotEmpty) {
          // Strip leading command byte
          if (current.length > 1) {
            frames.add(Uint8List.fromList(current.sublist(1)));
          }
          current.clear();
        }
        inFrame = true;
        escape = false;
        continue;
      }
      if (!inFrame) continue;
      if (escape) {
        escape = false;
        if (byte == _tfend) {
          current.add(_fend);
        } else if (byte == _tfesc) {
          current.add(_fesc);
        } else {
          debugPrint('KissTNC: unexpected escape byte 0x${byte.toRadixString(16)}');
        }
      } else if (byte == _fesc) {
        escape = true;
      } else {
        current.add(byte);
      }
    }
    return frames;
  }

  // ── Build a minimal AX.25 UI frame for APRS (TNC2 → AX.25) ──────────────
  // This is a simplified APRS-over-AX.25 encoder:
  //   Destination: APRS  (generic APRS destination callsign)
  //   Source: myCallsign-ssid
  //   Control: UI (0x03)
  //   PID: No Layer 3 (0xF0)
  //   Info: TNC2 string as bytes
  static Uint8List buildAprsFrame({
    required String myCallsign,
    required int ssid,
    required String tnc2Payload,
  }) {
    final buf = BytesBuilder();

    // Destination: APRS (6 chars padded, SSID=0, C-bit=1 on last addr byte)
    buf.add(_encodeCallsign('APRS', 0, isLast: false));
    buf.add(_encodeCallsign(myCallsign, ssid, isLast: true));

    // Control: UI frame (0x03)
    buf.addByte(0x03);
    // PID: No Layer 3 (0xF0)
    buf.addByte(0xF0);
    // Info field
    buf.add(tnc2Payload.codeUnits);

    return buf.toBytes();
  }

  static List<int> _encodeCallsign(String call, int ssid,
      {required bool isLast}) {
    // Pad/trim to 6 chars, shift left 1 bit
    final padded = call.padRight(6).substring(0, 6).toUpperCase();
    final bytes = padded.codeUnits.map((c) => (c & 0xFF) << 1).toList();
    // SSID byte: 0b0SSSSxx1 where SSSS = ssid, last bit = end-of-address
    final ssidByte = ((ssid & 0x0F) << 1) | (isLast ? 0x01 : 0x00);
    return [...bytes, ssidByte];
  }
}
