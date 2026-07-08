// lib/services/audio_service.dart
// UI-facing audio state for the VR-N76. The radio audio path is the native
// RFCOMM-ch4 SBC engine (Kotlin RadioAudioEngine + libsbc); this service is a
// thin ChangeNotifier that delegates to RadioService and mirrors its audio
// state so existing widgets keep working.
//
// NOTE: The legacy `ScoState` name is retained (status bar / dashboard switch
// on it) but no longer means Bluetooth SCO — it reflects the ch4 audio engine.

import 'package:flutter/foundation.dart';
import 'package:flutter_benlink/flutter_benlink.dart';
import '../bluetooth/radio_service.dart';

enum ScoState { off, connecting, connected, error }

class AudioService extends ChangeNotifier {
  RadioService? _radio;
  bool _pttActive = false;

  /// Injected by the provider once RadioService exists (see main.dart).
  void attach(RadioService radio) {
    if (identical(_radio, radio)) return;
    _radio?.removeListener(_onRadioChanged);
    _radio = radio;
    _radio?.addListener(_onRadioChanged);
  }

  void _onRadioChanged() => notifyListeners();

  ScoState get scoState {
    final r = _radio;
    if (r == null || !r.isConnected) return ScoState.off;
    return switch (r.audioState) {
      RadioAudioState.connecting => ScoState.connecting,
      RadioAudioState.connected || RadioAudioState.transmitting => ScoState.connected,
      RadioAudioState.error => ScoState.error,
      RadioAudioState.off => ScoState.off,
    };
  }

  bool get isAudioActive =>
      scoState == ScoState.connected || scoState == ScoState.connecting;
  bool get pttActive => _pttActive;

  Future<void> startAudio() async {
    await _radio?.startAudioMonitor();
  }

  Future<void> stopAudio() async {
    await _radio?.stopAudioMonitor();
    _pttActive = false;
    notifyListeners();
  }

  Future<void> toggleAudio() async {
    isAudioActive ? await stopAudio() : await startAudio();
  }

  /// Mark PTT active and ensure the audio socket is open. The actual key-up
  /// (mic capture) is done by RadioService.startTransmit() from the caller.
  Future<void> startPtt() async {
    if (!isAudioActive) await startAudio();
    _pttActive = true;
    notifyListeners();
  }

  /// Mark PTT released. RadioService.stopTransmit() performs the unkey.
  Future<void> stopPtt() async {
    _pttActive = false;
    notifyListeners();
  }

  void onRadioDisconnected() {
    _pttActive = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _radio?.removeListener(_onRadioChanged);
    super.dispose();
  }
}
