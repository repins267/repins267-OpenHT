// lib/bluetooth/radio_service.dart
// Wraps flutter_benlink RadioController with OpenHT-specific logic
// Protocol decoded by Kyle Husmann KC3SLD (https://github.com/khusmann/benlink)

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:flutter_benlink/flutter_benlink.dart';
import 'package:permission_handler/permission_handler.dart';

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

  // --- Auto-reconnect state ---
  BluetoothDevice? _connectedDevice;   // last device we connected to
  bool _userDisconnected = false;      // true only after an explicit disconnect()
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 8;
  bool get isReconnecting => _reconnectTimer?.isActive ?? false;

  // Raw byte callbacks for debug terminal (optional external hook)
  void Function(Uint8List)? onRawBytesSent;
  void Function(Uint8List)? onRawBytesReceived;

  // Persistent debug log — survives navigation (capped at 500 entries)
  final List<(String, String)> debugLog = [];

  void addDebugBytes(String direction, Uint8List bytes) {
    final hex = bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');
    final ts = DateTime.now().toString().split(' ').last.substring(0, 8);
    debugLog.add((direction, '[$ts] $direction: $hex'));
    if (debugLog.length > 500) debugLog.removeAt(0);
    notifyListeners();
  }

  void addDebugText(String message) {
    debugLog.add(('INFO', message));
    if (debugLog.length > 500) debugLog.removeAt(0);
    notifyListeners();
  }

  void clearDebugLog() {
    debugLog.clear();
    notifyListeners();
  }

  RadioConnectionState get connectionState => _connectionState;
  // Reflect the REAL socket, not just a cached state flag — a link that dropped
  // without a clean disconnect must read as not-connected.
  bool get isConnected =>
      _connectionState == RadioConnectionState.connected &&
      (_controller?.isConnected ?? false);
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
    _userDisconnected = false;
    _connectedDevice = device;
    _reconnectTimer?.cancel();
    _connectionState = RadioConnectionState.connecting;
    _errorMessage = null;
    notifyListeners();

    try {
      _controller = RadioController(device: device);
      _controller!.onDisconnected = _onLinkDown;

      _controller!.onBytesSent = (b) {
        onRawBytesSent?.call(b);
        addDebugBytes('TX', b);
      };
      _controller!.onBytesReceived = (b) {
        onRawBytesReceived?.call(b);
        addDebugBytes('RX', b);
      };

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

      _controller?.addListener(_onRadioStateChanged); // register before notify
      _reconnectAttempts = 0; // clean sync → reset backoff
      _connectionState = RadioConnectionState.connected;
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

  /// The command link dropped (RadioController.onDisconnected). Tear down the
  /// dead controller and start a backoff reconnect (unless the user disconnected).
  void _onLinkDown() {
    if (_userDisconnected) return;
    _controller?.removeListener(_onRadioStateChanged);
    _controller?.dispose();
    _controller = null;
    _connectionState = RadioConnectionState.connecting; // = reconnecting
    _errorMessage = 'Link dropped — reconnecting…';
    notifyListeners();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    if (_userDisconnected || _connectedDevice == null) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _connectionState = RadioConnectionState.error;
      _errorMessage = 'Reconnect failed after $_maxReconnectAttempts attempts';
      notifyListeners();
      return;
    }
    // Exponential backoff, capped at 30s: 2,4,8,16,30,30…
    final secs = (1 << (_reconnectAttempts + 1)).clamp(2, 30);
    _reconnectTimer = Timer(Duration(seconds: secs), () async {
      if (_userDisconnected || _connectedDevice == null) return;
      _reconnectAttempts++;
      final ok = await connect(_connectedDevice!);
      if (!ok && !_userDisconnected) _scheduleReconnect();
    });
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
      final vfoChannel = await _controller!.getVfoChannel();
      final ch = vfoChannel.copyWith(
        channelId: slotIndex, // slot within region; region carried by WRITE_REGION_CH
        rxFreq: outputFreqMhz,
        txFreq: inputFreqMhz,
        rxSubAudio: ctcssHz,
        txSubAudio: ctcssHz,
        txMod: ModulationType.FM,
        rxMod: ModulationType.FM,
        bandwidth: BandwidthType.WIDE,
        name: name.length > 10 ? name.substring(0, 10) : name,
      );
      await _controller!.writeRegionChannel(5, ch); // UI Group 6 = region 5
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
      // Region-addressed write: channelId is the 0..31 slot WITHIN the region;
      // the region (groupIndex) is carried by WRITE_REGION_CH, not baked into the id.
      final ch = Channel(
        channelId:    slotIndex,
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
      await _controller!.writeRegionChannel(groupIndex, ch);
      debugPrint('OpenHT: writeRegionChannel G${groupIndex + 1}:$slotIndex → ${rxFreqMhz}MHz');
      return true;
    } catch (e) {
      _errorMessage = 'Region channel write failed: $e';
      notifyListeners();
      return false;
    }
  }

  /// Read the on-device name of channel group [groupIndex] (0-5). Null if none.
  /// Does NOT change the active region (READ_REGION_NAME reads any region).
  Future<String?> getGroupName(int groupIndex) async {
    _assertSynced();
    return await _controller!.readRegionName(groupIndex);
  }

  /// Read all 6 channel-group names (index = groupIndex 0-5). Cheap; no region switch.
  Future<List<String?>> getGroupNames() async {
    _assertSynced();
    final names = <String?>[];
    for (int i = 0; i < 6; i++) {
      names.add(await _controller!.readRegionName(i));
      await Future.delayed(const Duration(milliseconds: 30));
    }
    return names;
  }

  /// A "blank"/empty channel matching the vendor's empty-slot encoding (zero
  /// freqs, no tone, empty name, flags 0x54 0x00) — used to clear a region slot.
  Channel _blankChannel(int slot) => Channel(
        channelId: slot,
        txMod: ModulationType.FM,
        rxMod: ModulationType.FM,
        txFreq: 0,
        rxFreq: 0,
        txSubAudio: 0,
        rxSubAudio: 0,
        bandwidth: BandwidthType.WIDE,
        scan: false,
        txAtMaxPower: true,
        txAtMedPower: false,
        sign: true,
        talkAround: false,
        preDeEmphBypass: false,
        txDisable: false,
        mute: false,
        name: '',
      );

  /// Blank every slot 0..31 of [region] EXCEPT those in [keep] — i.e. clear the
  /// leftovers after a themed write so the group holds only the new channels.
  Future<void> clearRegionSlotsExcept(int region, Set<int> keep) async {
    _assertSynced();
    for (int i = 0; i < 32; i++) {
      if (keep.contains(i)) continue;
      try {
        await _controller!.writeRegionChannel(region, _blankChannel(i));
      } catch (e) {
        debugPrint('OpenHT: clear region $region slot $i failed: $e');
      }
      await Future.delayed(const Duration(milliseconds: 120));
    }
  }

  /// Set the on-device name of a channel group [groupIndex] (0-5 = UI Groups 1-6).
  /// Device stores 10 chars; longer names are truncated.
  Future<bool> setGroupName(int groupIndex, String name) async {
    _assertSynced();
    try {
      await _controller!.writeRegionName(groupIndex, name);
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Group name write failed: $e';
      notifyListeners();
      return false;
    }
  }

  /// Read all channels of the radio's currently ACTIVE region (group). The radio
  /// only serves the active region over BT (READ_RF_CH 0..channelCount-1); other
  /// groups are reachable for writes via [writeChannelToGroup] but not live reads.
  Future<List<Channel>> getActiveGroupChannels() async {
    _assertSynced();
    return await _controller!.getAllChannels();
  }

  /// Read a single channel [slot] (0..31) of the active region.
  Future<Channel> getActiveChannel(int slot) async {
    _assertSynced();
    return await _controller!.getChannel(slot);
  }

  /// Switch the radio's active region (channel group) to [groupIndex] (0-5).
  Future<void> setActiveRegion(int groupIndex) async {
    _assertSynced();
    await _controller!.setRegion(groupIndex);
    notifyListeners();
  }

  /// Switch to [groupIndex] (0-5) and read all its channels. NOTE: SET_REGION
  /// changes the radio's active region, so this leaves the radio on [groupIndex].
  Future<List<Channel>> readGroupChannels(int groupIndex) async {
    _assertSynced();
    await _controller!.setRegion(groupIndex);
    await Future.delayed(const Duration(milliseconds: 150));
    return await _controller!.getAllChannels();
  }

  /// Write [channel] to the radio's ACTIVE region via WRITE_RF_CH (channelId =
  /// slot 0..31). Use this when editing the active group — we can't know the
  /// active region's numeric index, and WRITE_RF_CH targets it implicitly.
  Future<bool> writeActiveChannel(Channel channel) async {
    _assertSynced();
    try {
      await _controller!.writeChannel(channel);
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Channel write failed: $e';
      notifyListeners();
      return false;
    }
  }

  /// Write [channel] (its channelId = slot 0..31) into [groupIndex] (0-5 = UI
  /// Groups 1-6) via region addressing — works for any group, not just active.
  Future<bool> writeChannelToGroup(int groupIndex, Channel channel) async {
    _assertSynced();
    try {
      await _controller!.writeRegionChannel(groupIndex, channel);
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Channel write failed: $e';
      notifyListeners();
      return false;
    }
  }

  /// Write NOAA weather channels into Group 5 (0-indexed group 4, slots 128–134).
  Future<int> writeNoaaGroup() async {
    _assertSynced();
    // Must be in channel mode for WRITE_RF_CH to accept absolute channel IDs.
    final prevVfoX = await beginBulkWrite();
    int written = 0;
    try {
      final vfoChannel = await _controller!.getVfoChannel();
      for (int i = 0; i < kNoaaChannels.length; i++) {
        final (name, freqMhz) = kNoaaChannels[i];
        try {
          final ch = vfoChannel.copyWith(
            channelId: i,  // slot within region; Group 5 = region 4
            rxFreq: freqMhz,
            txFreq: freqMhz,
            rxSubAudio: 0,
            txSubAudio: 0,
            txMod: ModulationType.FM,
            rxMod: ModulationType.FM,
            bandwidth: BandwidthType.WIDE,
            name: name,
          );
          await _controller!.writeRegionChannel(4, ch);
          written++;
          await Future.delayed(const Duration(milliseconds: 150));
        } catch (e) {
          debugPrint('OpenHT: writeNoaaGroup slot $i failed: $e');
        }
      }
      // Clear leftover channels in the rest of the group.
      await clearRegionSlotsExcept(4, {for (int i = 0; i < kNoaaChannels.length; i++) i});
      // Also name the group so the radio shows "NOAA WX" for Group 5.
      try {
        await _controller!.writeRegionName(4, 'NOAA WX');
      } catch (e) {
        debugPrint('OpenHT: writeNoaaGroup name failed: $e');
      }
    } finally {
      await endBulkWrite(prevVfoX);
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
      try {
        final ch = Channel(
          channelId: i, // slot within region; Group 6 = region 5
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
        await _controller!.writeRegionChannel(5, ch); // UI Group 6 = region 5
        written++;
        debugPrint('OpenHT: bulkWrite slot$i ${entry.outputFreqMhz}MHz OK');
      } catch (e) {
        debugPrint('OpenHT: bulkWrite slot$i FAILED: $e');
      }
      await Future.delayed(const Duration(milliseconds: 150));
    }

    // Clear leftover channels in the rest of Group 6.
    await clearRegionSlotsExcept(5, {for (int i = 0; i < toWrite.length; i++) i});
    // Name the group so the radio shows "Near Rptr" for Group 6.
    try {
      await _controller!.writeRegionName(5, 'Near Rptr');
    } catch (e) {
      debugPrint('OpenHT: bulkWrite name failed: $e');
    }

    // Restore VFO mode.
    if (wasInVfo) {
      debugPrint('OpenHT: bulkWrite — restoring VFO mode (vfoX=${s.vfoX})');
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

  // ── Audio (RFCOMM ch4 SBC engine) ─────────────────────────────────────────
  // Keying is implicit on the audio channel: the radio keys TX when AudioData
  // frames arrive and unkeys on AudioEnd (PB5 is driven by the radio firmware).

  bool get isAudioMonitoring => _controller?.isAudioMonitoring ?? false;
  RadioAudioState get audioState =>
      _controller?.audioState ?? RadioAudioState.off;

  /// Decoded RX PCM (s16le, mono, 32 kHz) for DSP (SSTV / APT / LRPT).
  Stream<Uint8List>? get audioPcmStream => _controller?.audioPcmStream;

  Future<void> startAudioMonitor() async {
    await _controller?.startAudioMonitor();
    notifyListeners();
  }

  Future<void> stopAudioMonitor() async {
    await _controller?.stopAudioMonitor();
    notifyListeners();
  }

  Future<void> toggleAudioMonitor() async {
    await _controller?.toggleAudioMonitor();
    notifyListeners();
  }

  /// Key up via the phone microphone (voice PTT). Opens the audio socket if needed.
  Future<bool> startTransmit() async {
    final ok = await _controller?.startTransmit() ?? false;
    notifyListeners();
    return ok;
  }

  /// Release voice PTT (sends AudioEnd to unkey).
  Future<bool> stopTransmit() async {
    final ok = await _controller?.stopTransmit() ?? false;
    notifyListeners();
    return ok;
  }

  /// Stream app-generated PCM (s16le, mono, 32 kHz) — SSTV tones / wx uplink.
  /// Call [endTransmit] when the burst is finished to unkey.
  Future<void> sendAudioPcm(Uint8List pcm) async {
    await _controller?.sendAudioPcm(pcm);
  }

  Future<void> endTransmit() async {
    await _controller?.endTransmit();
  }

  Future<void> forceVfoMode() async {
    _assertSynced();
    final s = _controller?.settings;
    if (s == null) return;
    await _controller!.writeSettings(s.copyWith(vfoX: 1));
  }

  void disconnect() {
    _userDisconnected = true;
    _reconnectTimer?.cancel();
    _reconnectAttempts = 0;
    _connectedDevice = null;
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
