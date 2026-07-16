import 'dart:math';
import 'dart:typed_data';

/// Generates DTMF (touch-tone) audio as PCM to feed the radio's app-audio TX
/// path (`RadioService.sendAudioPcm` — **s16le, mono, 32 kHz**), then unkey with
/// `endTransmit()`. The radio transmits it over the air, mirroring how the
/// vendor app does DTMF (app-side DSP, no protocol command).
class DtmfGenerator {
  /// Native TX sample rate expected by the audio engine.
  static const int sampleRate = 32000;

  /// Row/column tone pair (Hz) for each DTMF character. Chars are the standard
  /// 16-key set: 0-9, *, #, A-D. Case-insensitive; unknown chars are skipped.
  static const Map<String, (int, int)> _tones = {
    '1': (697, 1209), '2': (697, 1336), '3': (697, 1477), 'A': (697, 1633),
    '4': (770, 1209), '5': (770, 1336), '6': (770, 1477), 'B': (770, 1633),
    '7': (852, 1209), '8': (852, 1336), '9': (852, 1477), 'C': (852, 1633),
    '*': (941, 1209), '0': (941, 1336), '#': (941, 1477), 'D': (941, 1633),
  };

  /// True if [ch] is a sendable DTMF character.
  static bool isDtmfChar(String ch) => _tones.containsKey(ch.toUpperCase());

  /// The 16 valid DTMF characters, in keypad order (for building a keypad UI).
  static const List<String> keypad = [
    '1', '2', '3', 'A',
    '4', '5', '6', 'B',
    '7', '8', '9', 'C',
    '*', '0', '#', 'D',
  ];

  /// Renders [digits] to s16le/mono/32 kHz PCM. Each valid character is a
  /// [toneMs] dual-tone burst followed by [gapMs] of silence. Non-DTMF chars
  /// (spaces, etc.) are rendered as a [gapMs] pause so timing stays readable.
  ///
  /// Default 150 ms tone + 60 ms gap ≈ the vendor app's 240 cpm.
  static Uint8List render(
    String digits, {
    int toneMs = 150,
    int gapMs = 60,
    double amplitude = 0.35, // per-tone; summed pair stays < 1.0 (no clipping)
  }) {
    final toneN = (sampleRate * toneMs / 1000).round();
    final gapN = (sampleRate * gapMs / 1000).round();

    // Pre-size the buffer.
    int total = 0;
    for (final ch in digits.split('')) {
      total += isDtmfChar(ch) ? toneN + gapN : gapN;
    }
    final bytes = ByteData(total * 2); // 16-bit samples
    int i = 0;

    void writeSample(double v) {
      final s = (v * 32767).clamp(-32768, 32767).round();
      bytes.setInt16(i * 2, s, Endian.little);
      i++;
    }

    for (final ch in digits.split('')) {
      final pair = _tones[ch.toUpperCase()];
      if (pair == null) {
        for (int n = 0; n < gapN; n++) {
          writeSample(0);
        }
        continue;
      }
      final (f1, f2) = pair;
      final w1 = 2 * pi * f1 / sampleRate;
      final w2 = 2 * pi * f2 / sampleRate;
      for (int n = 0; n < toneN; n++) {
        // Gentle 5 ms raised-cosine ramp in/out to avoid key-click artifacts.
        final ramp = _edge(n, toneN, (sampleRate * 5 / 1000).round());
        writeSample(ramp * amplitude * (sin(w1 * n) + sin(w2 * n)));
      }
      for (int n = 0; n < gapN; n++) {
        writeSample(0);
      }
    }
    return bytes.buffer.asUint8List();
  }

  /// Raised-cosine envelope: 0→1 over the first [edgeN] samples, 1→0 over the
  /// last [edgeN], flat 1 in between.
  static double _edge(int n, int len, int edgeN) {
    if (edgeN <= 0) return 1.0;
    if (n < edgeN) return 0.5 * (1 - cos(pi * n / edgeN));
    if (n >= len - edgeN) return 0.5 * (1 - cos(pi * (len - n) / edgeN));
    return 1.0;
  }
}
