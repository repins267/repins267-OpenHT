// lib/services/channel_csv_service.dart
// VGC CSV wire format encoder/decoder (matches VGC HT App v2.7.4.3)
//
// Field encoding reference:
//   Frequency  — 9-digit Hz integer (e.g. 438500000)
//   CTCSS tone — Hz × 100 integer   (e.g. 8850 = 88.5 Hz)
//   DCS code   — tone number only    (e.g. 47 = D047N)
//   Modulation — 0=FM, 1=AM
//   Bandwidth  — 0=Narrow, 1=Wide

import 'package:flutter_benlink/flutter_benlink.dart';

// CSV column indices
const int _kColName      = 0;
const int _kColRxFreq    = 1;
const int _kColTxFreq    = 2;
const int _kColRxTone    = 3;
const int _kColTxTone    = 4;
const int _kColMod       = 5;
const int _kColBandwidth = 6;
const int _kColScan      = 7;

const String _kCsvHeader =
    'Name,RxFreqHz,TxFreqHz,RxTone,TxTone,Modulation,Bandwidth,Scan';

class ChannelCsvService {
  /// Encode a list of [Channel] objects to a VGC-compatible CSV string.
  static String encode(List<Channel> channels) {
    final buf = StringBuffer()..writeln(_kCsvHeader);
    for (final ch in channels) {
      buf.writeln([
        _escapeCsv(ch.name.trim()),
        _freqToHz(ch.rxFreq),
        _freqToHz(ch.txFreq),
        _encodeSubAudio(ch.rxSubAudio),
        _encodeSubAudio(ch.txSubAudio),
        ch.rxMod == ModulationType.AM ? 1 : 0,
        ch.bandwidth == BandwidthType.WIDE ? 1 : 0,
        ch.scan ? 1 : 0,
      ].join(','));
    }
    return buf.toString();
  }

  /// Decode a VGC CSV string into [Channel] objects.
  /// Skips the header row and any malformed rows.
  static List<Channel> decode(String csv) {
    final lines = csv.split(RegExp(r'\r?\n'));
    final channels = <Channel>[];
    int lineNum = 0;
    for (final raw in lines) {
      final line = raw.trim();
      lineNum++;
      if (line.isEmpty || lineNum == 1) continue; // skip header + blank
      final cols = _splitCsvRow(line);
      if (cols.length < 7) continue;
      try {
        final rxFreq = _hzToFreq(cols[_kColRxFreq]);
        final txFreq = _hzToFreq(cols[_kColTxFreq]);
        final rxSub  = _decodeSubAudio(cols[_kColRxTone]);
        final txSub  = _decodeSubAudio(cols[_kColTxTone]);
        final mod    = cols[_kColMod].trim() == '1'
            ? ModulationType.AM
            : ModulationType.FM;
        final bw     = cols[_kColBandwidth].trim() == '1'
            ? BandwidthType.WIDE
            : BandwidthType.NARROW;
        final scan   = cols.length > _kColScan
            ? cols[_kColScan].trim() != '0'
            : true;
        channels.add(Channel(
          channelId: channels.length,
          name: cols[_kColName].replaceAll('"', '').trim(),
          rxFreq: rxFreq,
          txFreq: txFreq,
          rxMod: mod,
          txMod: mod,
          rxSubAudio: rxSub,
          txSubAudio: txSub,
          bandwidth: bw,
          scan: scan,
          txAtMaxPower: false,
          txAtMedPower: false,
        ));
      } catch (_) {
        // Skip unparseable rows
      }
    }
    return channels;
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  /// MHz double → 9-digit Hz string (e.g. 146.940 → "146940000")
  static String _freqToHz(double mhz) =>
      (mhz * 1e6).round().toString().padLeft(9, '0');

  /// Hz string → MHz double
  static double _hzToFreq(String hz) =>
      int.parse(hz.trim()) / 1e6;

  /// Encode CTCSS (double Hz) or DCS (int) as VGC integer.
  /// null → "0"
  static String _encodeSubAudio(dynamic val) {
    if (val == null) return '0';
    if (val is double) return (val * 100).round().toString(); // CTCSS: Hz × 100
    if (val is int) return val.toString();                    // DCS: code as-is
    return '0';
  }

  /// Decode VGC integer to CTCSS double or DCS int.
  /// 0 → null, <6700 → DCS int, ≥6700 → CTCSS Hz
  static dynamic _decodeSubAudio(String raw) {
    final v = int.tryParse(raw.trim()) ?? 0;
    if (v == 0) return null;
    if (v < 6700) return v;       // DCS code
    return v / 100.0;             // CTCSS Hz
  }

  static String _escapeCsv(String s) =>
      s.contains(',') || s.contains('"') ? '"${s.replaceAll('"', '""')}"' : s;

  static List<String> _splitCsvRow(String row) {
    final result = <String>[];
    final buf = StringBuffer();
    bool inQuote = false;
    for (int i = 0; i < row.length; i++) {
      final c = row[i];
      if (c == '"') {
        if (inQuote && i + 1 < row.length && row[i + 1] == '"') {
          buf.write('"');
          i++;
        } else {
          inQuote = !inQuote;
        }
      } else if (c == ',' && !inQuote) {
        result.add(buf.toString());
        buf.clear();
      } else {
        buf.write(c);
      }
    }
    result.add(buf.toString());
    return result;
  }
}
