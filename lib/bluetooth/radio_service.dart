// lib/bluetooth/radio_service.dart
// Wraps flutter_benlink RadioController with OpenHT-specific logic
// Protocol decoded by Kyle Husmann KC3SLD (https://github.com/khusmann/benlink)

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:flutter_benlink/flutter_benlink.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/repeater.dart';

enum RadioConnectionState {
  disconnected,
  scanning,
  connecting,
  syncing,    // connected but waiting for handshake
  connected,  // ready for writes
  error,
}

class RadioException implements Exception {
  final String message;
  RadioException(this.message);
  @override
  String toString() => 'RadioException: $message';
}

// NOAA Weather Radio standard frequencies
const List<(String, double)> kNoaaChannels = [
  ('WX1', 162.400),
  ('WX2', 162.425),
  ('WX3', 162.450),
  ('WX4', 162.475),
  ('WX5', 162.500),
  ('WX6', 162.525),
  ('WX7', 162.550),
];

class RadioService extends ChangeNotifier {
  RadioController? _controller;
  RadioConnectionState _connectionState = RadioConnectionState.disconnected;
  String? _errorMessage;
  List<BluetoothDevice> _pairedDevices = [];

  int _nearRepeaterSlot = 0;

  // Raw byte callbacks for debug terminal
  void Function(Uint8List)? onRawBytesSent;
  void Function(Uint8List)? onRawBytesReceived;

  RadioConnectionState get connectionState => _connectionState;
  bool get isConnected => _connectionState == RadioConnectionState.connected;
  RadioController? get controller => _controller;
  String? get errorMessage => _errorMessage;
  List<BluetoothDevice> get pairedDevices => _pairedDevices;

  String? get currentChannelName => _controller?.currentChannelName;
  double? get batteryVoltage => _controller?.batteryVoltage;
  int? get batteryPercent => _controller?.batteryLevelAsPercentage;
  bool? get isGpsLocked => _controller?.isGpsLocked;
  bool? get isTransmitting => _controller?.isInTx;
  bool? get isReceiving => _controller?.isInRx;

  double get currentRxFreq => _controller?.currentRxFreq ?? 0.0;
  ModulationType? get currentMode => _controller?.currentChannel?.rxMod;
  BandwidthType? get currentBandwidth => _controller?.currentChannel?.bandwidth;
  int get squelchLevel => _controller?.settings?.squelchLevel ?? 0;
  int get volumeLevel => _controller?.settings?.micGain ?? 0;
  int get currentChannelId => _controller?.currentChannelId ?? 0;

  // Radio GPS (from the radio's built-in GPS chip)
  double? get radioLatitude  => _controller?.gps?.latitude;
  double? get radioLongitude => _controller?.gps?.longitude;
  bool get hasRadioGps =>
      _controller?.gps != null &&
      (_controller!.gps!.latitude != 0.0 || _controller!.gps!.longitude != 0.0);

  Future<bool> requestBluetoothPermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.microphone,
    ].request();

    final scanGranted    = statuses[Permission.bluetoothScan]?.isGranted    ?? false;
    final connectGranted = statuses[Permission.bluetoothConnect]?.isGranted ?? false;

    if (!scanGranted || !connectGranted) {
      _errorMessage = 'Bluetooth permissions required.';
      notifyListeners();
      return false;
    }
    return true;
  }

  void _assertSynced() {
    if (_connectionState != RadioConnectionState.connected) {
      throw RadioException('Radio not synced. Current state: $_connectionState');
    }
  }

  Future<void> syncSettings() async {
    if (_controller == null) return;
    // GAIA protocol initializes via _initializeRadioState() on connect.
    // This re-reads settings to confirm the radio is responsive.
    debugPrint('OpenHT: syncSettings — re-reading radio settings...');
    await _controller!.getSettings();
  }

  Future<List<BluetoothDevice>> scanPairedDevices() async {
    _connectionState = RadioConnectionState.scanning;
    _errorMessage = null;
    notifyListeners();

    if (!await requestBluetoothPermissions()) {
      _connectionState = RadioConnectionState.error;
      notifyListeners();
      return [];
    }

    try {
      final devices = await FlutterBluetoothSerial.instance.getBondedDevices();
      _pairedDevices = devices;
      _connectionState = RadioConnectionState.disconnected;
      notifyListeners();
      return _pairedDevices;
    } catch (e) {
      _errorMessage = 'Scan error: $e';
      _connectionState = RadioConnectionState.error;
      notifyListeners();
      return [];
    }
  }

  Future<bool> connect(BluetoothDevice device) async {
    _connectionState = RadioConnectionState.connecting;
    _errorMessage = null;
    notifyListeners();

    try {
      _controller = RadioController(device: device);

      _controller!.onBytesSent = (b) => onRawBytesSent?.call(b);
      _controller!.onBytesReceived = (b) => onRawBytesReceived?.call(b);

      await _controller!.connect().timeout(const Duration(seconds: 15));

      _connectionState = RadioConnectionState.syncing;
      notifyListeners();

      // Wait for SETTINGS_SYNCING_COMPLETE
      // For now, we simulate or wait for the controller to be "ready" 
      // as a fallback until the handshake is fully implemented.
      int attempts = 0;
      while (!(_controller?.isReady ?? false) && attempts < 50) {
        await Future.delayed(const Duration(milliseconds: 200));
        attempts++;
      }

      if (!(_controller?.isReady ?? false)) {
        throw RadioException('Radio sync timeout');
      }

      _connectionState = RadioConnectionState.connected;
      _controller?.addListener(_onRadioStateChanged);
      notifyListeners();

      return true;
    } catch (e) {
      _errorMessage = 'Connection failed: $e';
      _connectionState = RadioConnectionState.error;
      _controller = null;
      notifyListeners();
      return false;
    }
  }

  void _onRadioStateChanged() {
    notifyListeners();
  }

  /// Tune Band B (dual-watch) VFO to [frequencyMhz] with FM+Wide, no tone.
  Future<bool> tuneBandB(double frequencyMhz) async {
    _assertSynced();
    try {
      final ch = _controller!.channelB;
      if (ch == null) throw RadioException('Band B channel not loaded');
      final updated = ch.copyWith(
        rxFreq: frequencyMhz,
        txFreq: frequencyMhz,
        txMod: ModulationType.FM,
        rxMod: ModulationType.FM,
        bandwidth: BandwidthType.WIDE,
        txSubAudio: 0,
        rxSubAudio: 0,
      );
      await _controller!.writeChannel(updated);
      debugPrint('OpenHT: tuneBandB → ${frequencyMhz}MHz FM no-tone');
    } catch (e) {
      _errorMessage = 'Band B tune failed: $e';
      notifyListeners();
      return false;
    }
    notifyListeners();
    return true;
  }

  Future<bool> tuneToFrequency(double frequencyMhz) async {
    _assertSynced();
    try {
      // Ensure radio is in VFO mode
      final s = _controller!.settings;
      if (s != null && s.vfoX == 0) {
        debugPrint('OpenHT: tuneToFrequency — switching to VFO mode first');
        await _controller!.writeSettings(s.copyWith(vfoX: 1));
        await Future.delayed(const Duration(milliseconds: 200));
      }
      // Use getVfoChannel+writeChannel so we can explicitly clear CTCSS (0 = no tone).
      // setVfoFrequency() preserves the old subAudio via copyWith's null fall-through.
      final vfoChannel = await _controller!.getVfoChannel();
      final updated = vfoChannel.copyWith(
        rxFreq: frequencyMhz,
        txFreq: frequencyMhz,
        txMod: ModulationType.FM,
        rxMod: ModulationType.FM,
        bandwidth: BandwidthType.WIDE,
        txSubAudio: 0,   // 0 = no tone
        rxSubAudio: 0,
      );
      await _controller!.writeChannel(updated);
      _controller!.currentChannel = updated;
      _controller!.currentVfoFrequencyMhz = frequencyMhz;
      debugPrint('OpenHT: tuneToFrequency → ${frequencyMhz}MHz FM no-tone');
    } catch (e) {
      _errorMessage = 'Tune failed: $e';
      notifyListeners();
      return false;
    }
    notifyListeners();
    return true;
  }

  /// Tune to a repeater output frequency with optional CTCSS tone.
  Future<bool> tuneToRepeaterGpx({
    required double outputFreqMhz,
    double? ctcssHz,
    String? name,
  }) async {
    _assertSynced();
    bool tuneOk = false;
    try {
      final vfoChannel = await _controller!.getVfoChannel();
      final updated = vfoChannel.copyWith(
        rxFreq: outputFreqMhz,
        txFreq: outputFreqMhz,
        // Pass 0 (not null) when no tone — copyWith uses `??` so null falls through
        // to the previous channel's tone, which would prevent squelch from opening.
        rxSubAudio: ctcssHz ?? 0,
        txSubAudio: ctcssHz ?? 0,
        txMod: ModulationType.FM,
        rxMod: ModulationType.FM,
        bandwidth: BandwidthType.WIDE,
        name: name != null
            ? (name.length > 10 ? name.substring(0, 10) : name)
            : null,
      );
      await _controller!.writeChannel(updated);
      _controller!.currentChannel = updated;
      _controller!.currentVfoFrequencyMhz = outputFreqMhz;
      tuneOk = true;
      debugPrint('OpenHT: tuneToRepeaterGpx → ${outputFreqMhz}MHz PL:${ctcssHz}Hz');
    } catch (e) {
      _errorMessage = 'Tune failed: $e';
    }
    // notifyListeners outside try-catch so Flutter lifecycle exceptions during
    // widget rebuild don't get caught and misreported as tune failures.
    notifyListeners();
    return tuneOk;
  }

  /// Write a repeater into Group 6 (Near Repeater group), slot [_nearRepeaterSlot].
  Future<bool> writeNearRepeaterChannel({
    required double outputFreqMhz,
    required double inputFreqMhz,
    double? ctcssHz,
    required String name,
  }) async {
    _assertSynced();
    try {
      final slotIndex = _nearRepeaterSlot % 32;
      final channelId = 5 * 32 + slotIndex; // UI Group 6 (0-indexed group 5, channels 160-191)
      final vfoChannel = await _controller!.getVfoChannel();
      final ch = vfoChannel.copyWith(
        channelId: channelId,
        rxFreq: outputFreqMhz,
        txFreq: inputFreqMhz,
        rxSubAudio: ctcssHz,
        txSubAudio: ctcssHz,
        txMod: ModulationType.FM,
        rxMod: ModulationType.FM,
        bandwidth: BandwidthType.WIDE,
        name: name.length > 10 ? name.substring(0, 10) : name,
      );
      await _controller!.writeChannel(ch);
      _nearRepeaterSlot++;
      debugPrint('OpenHT: writeNearRepeaterChannel slot $slotIndex → ${outputFreqMhz}MHz');
      return true;
    } catch (e) {
      _errorMessage = 'Write channel failed: $e';
      notifyListeners();
      return false;
    }
  }

  /// Switch to channel mode (vfoX=0) for bulk writes.
  /// Returns the previous vfoX value so [endBulkWrite] can restore it.
  /// Returns null if already in channel mode or settings unavailable.
  Future<int?> beginBulkWrite() async {
    _assertSynced();
    final s = _controller!.settings;
    if (s == null || s.vfoX == 0) return null;
    debugPrint('OpenHT: beginBulkWrite — switching to channel mode (vfoX=0)');
    await _controller!.writeSettings(s.copyWith(vfoX: 0));
    await Future.delayed(const Duration(milliseconds: 300));
    return s.vfoX;
  }

  /// Restore VFO mode after bulk writes; pass the value returned by [beginBulkWrite].
  Future<void> endBulkWrite(int? prevVfoX) async {
    if (prevVfoX == null) return;
    final s = _controller?.settings;
    if (s == null) return;
    debugPrint('OpenHT: endBulkWrite — restoring vfoX=$prevVfoX');
    await _controller!.writeSettings(s.copyWith(vfoX: prevVfoX));
    await Future.delayed(const Duration(milliseconds: 200));
  }

  /// Write a single channel into [groupIndex] (0-5 for UI Groups 1-6), [slotIndex] (0-31).
  ///
  /// Used by FreqPlanService for served-agency frequency plans.
  Future<bool> writeRegionChannel({
    required int    groupIndex,
    required int    slotIndex,
    required double rxFreqMhz,
    required double txFreqMhz,
    double?         ctcssHz,
    required String name,
  }) async {
    _assertSynced();
    try {
      final channelId = groupIndex * 32 + slotIndex;
      final ch = Channel(
        channelId:    channelId,
        txMod:        ModulationType.FM,
        rxMod:        ModulationType.FM,
        txFreq:       txFreqMhz,
        rxFreq:       rxFreqMhz,
        txSubAudio:   ctcssHz,
        rxSubAudio:   ctcssHz,
        bandwidth:    BandwidthType.WIDE,
        scan:         true,
        txAtMaxPower: false,
        txAtMedPower: true,
        name:         name.length > 10 ? name.substring(0, 10) : name,
      );
      await _controller!.writeChannel(ch);
      debugPrint('OpenHT: writeRegionChannel G${groupIndex + 1}:$slotIndex → ${rxFreqMhz}MHz');
      return true;
    } catch (e) {
      _errorMessage = 'Region channel write failed: $e';
      notifyListeners();
      return false;
    }
  }

  /// Write NOAA weather channels into Group 4.
  Future<int> writeNoaaGroup() async {
    _assertSynced();
    int written = 0;
    final vfoChannel = await _controller!.getVfoChannel();
    for (int i = 0; i < kNoaaChannels.length; i++) {
      final (name, freqMhz) = kNoaaChannels[i];
      try {
        final ch = vfoChannel.copyWith(
          channelId: 4 * 32 + i,
          rxFreq: freqMhz,
          txFreq: freqMhz,
          rxSubAudio: 0,   // 0 = no tone (null falls through copyWith to old value)
          txSubAudio: 0,
          txMod: ModulationType.FM,
          rxMod: ModulationType.FM,
          bandwidth: BandwidthType.WIDE,
          name: name,
        );
        await _controller!.writeChannel(ch);
        written++;
        await Future.delayed(const Duration(milliseconds: 150));
      } catch (e) {
        debugPrint('OpenHT: writeNoaaGroup slot $i failed: $e');
      }
    }
    return written;
  }

  /// Bulk-write up to 32 repeaters into the radio's currently active channel group.
  ///
  /// The radio firmware only exposes 32 channel slots (IDs 0-31) per protocol
  /// command — one set per active group. Writes only persist to memory when the
  /// radio is in CHANNEL mode (vfoX=0), so this method temporarily switches to
  /// channel mode, writes all slots, then restores VFO mode.
  Future<int> bulkWriteNearRepeaterGroup({
    required List<({double outputFreqMhz, double inputFreqMhz, double? ctcssHz, String name})> channels,
  }) async {
    _assertSynced();
    int written = 0;

    // Switch to channel mode so writes go to actual memory channels.
    final s = _controller!.settings;
    final wasInVfo = s != null && s.vfoX != 0;
    if (wasInVfo) {
      debugPrint('OpenHT: bulkWrite — switching to channel mode (vfoX=0)');
      await _controller!.writeSettings(s.copyWith(vfoX: 0));
      await Future.delayed(const Duration(milliseconds: 300));
    }

    final toWrite = channels.take(32).toList();
    for (int i = 0; i < toWrite.length; i++) {
      final entry = toWrite[i];
      final channelId = 5 * 32 + i; // Group 6 (0-indexed group 5), channels 160–191
      try {
        final ch = Channel(
          channelId: channelId,
          txMod: ModulationType.FM,
          rxMod: ModulationType.FM,
          txFreq: entry.inputFreqMhz,
          rxFreq: entry.outputFreqMhz,
          txSubAudio: entry.ctcssHz,
          rxSubAudio: entry.ctcssHz,
          bandwidth: BandwidthType.WIDE,
          scan: true,
          txAtMaxPower: false,
          txAtMedPower: true,
          name: entry.name.length > 10 ? entry.name.substring(0, 10) : entry.name,
        );
        await _controller!.writeChannel(ch);
        written++;
        debugPrint('OpenHT: bulkWrite slot$i ${entry.outputFreqMhz}MHz OK');
      } catch (e) {
        debugPrint('OpenHT: bulkWrite slot$i FAILED: $e');
      }
      await Future.delayed(const Duration(milliseconds: 150));
    }

    // Restore VFO mode.
    if (wasInVfo) {
      debugPrint('OpenHT: bulkWrite — restoring VFO mode (vfoX=${s!.vfoX})');
      await _controller!.writeSettings(s.copyWith(vfoX: s.vfoX));
      await Future.delayed(const Duration(milliseconds: 200));
    }

    notifyListeners();
    return written;
  }

  /// Get all radio memory channels.
  Future<List<Channel>> getAllChannels() async {
    _assertSynced();
    return await _controller!.getAllChannels();
  }

  /// Returns the total channel count reported by the radio firmware.
  int get firmwareChannelCount => _controller?.deviceInfo?.channelCount ?? -1;

  /// Diagnostic: read all 32 channels in [group] (0-indexed, group 6 = index 5 = IDs 160–191).
  Future<List<String>> diagReadGroup(int group) async {
    _assertSynced();
    final results = <String>[];
    for (int i = 0; i < 32; i++) {
      results.add(await diagReadChannel(group * 32 + i));
      await Future.delayed(const Duration(milliseconds: 50));
    }
    return results;
  }

  /// Diagnostic: try reading channel [id] and return a human-readable result.
  Future<String> diagReadChannel(int id) async {
    _assertSynced();
    try {
      final ch = await _controller!.getChannel(id);
      return 'Ch$id OK: rxFreq=${ch.rxFreq.toStringAsFixed(3)} '
          'txFreq=${ch.txFreq.toStringAsFixed(3)} '
          'mod=${ch.rxMod.name} name="${ch.name}"';
    } catch (e) {
      return 'Ch$id FAILED: $e';
    }
  }

  /// Diagnostic: write a single test channel at [id] and return result.
  Future<String> diagWriteChannel(int id, double freqMhz) async {
    _assertSynced();
    try {
      final ch = Channel(
        channelId: id,
        txMod: ModulationType.FM,
        rxMod: ModulationType.FM,
        txFreq: freqMhz,
        rxFreq: freqMhz,
        bandwidth: BandwidthType.WIDE,
        scan: true,
        txAtMaxPower: false,
        txAtMedPower: true,
        name: 'TEST',
      );
      await _controller!.writeChannel(ch);
      return 'Write ch$id OK';
    } catch (e) {
      return 'Write ch$id FAILED: $e';
    }
  }

  Future<void> setVolume(int level) async {
    if (_controller == null) return;
    final s = _controller!.settings;
    if (s == null) return;
    try {
      await _controller!.writeSettings(s.copyWith(micGain: level.clamp(0, 7)));
    } catch (e) {
      debugPrint('OpenHT: setVolume failed: $e');
    }
  }

  Future<void> setSquelch(int level) async {
    if (_controller == null) return;
    final s = _controller!.settings;
    if (s == null) return;
    try {
      await _controller!.writeSettings(s.copyWith(squelchLevel: level.clamp(0, 9)));
    } catch (e) {
      debugPrint('OpenHT: setSquelch failed: $e');
    }
  }

  Future<void> stepFrequency(double stepMhz) async {
    if (_controller == null) return;
    final current = _controller!.currentRxFreq;
    await tuneToFrequency(current + stepMhz);
  }

  Future<void> setVfoMode(ModulationType mod, BandwidthType bw) async {
    _assertSynced();
    try {
      final vfoChannel = await _controller!.getVfoChannel();
      final updated = vfoChannel.copyWith(rxMod: mod, txMod: mod, bandwidth: bw);
      await _controller!.writeChannel(updated);
    } catch (e) {
      debugPrint('OpenHT: setVfoMode failed: $e');
    }
  }

  // TODO: VR-N76 PTT command opcode not yet identified in the Benshi protocol.
  // SCO audio routing works; the PTT button is visually functional but does
  // not key the radio transmitter until the opcode is found and implemented.

  /// Key up the transmitter (PTT on). Currently a no-op stub.
  Future<bool> startTransmit() async {
    debugPrint('OpenHT PTT: WARNING — startTransmit() not yet implemented (no opcode)');
    return false;
  }

  /// Release the transmitter (PTT off). Currently a no-op stub.
  Future<bool> stopTransmit() async {
    debugPrint('OpenHT PTT: WARNING — stopTransmit() not yet implemented (no opcode)');
    return false;
  }

  Future<void> forceVfoMode() async {
    _assertSynced();
    final s = _controller?.settings;
    if (s == null) return;
    await _controller!.writeSettings(s.copyWith(vfoX: 1));
  }

  void disconnect() {
    _controller?.removeListener(_onRadioStateChanged);
    _controller?.dispose();
    _controller = null;
    _connectionState = RadioConnectionState.disconnected;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
