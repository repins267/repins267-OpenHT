// lib/bluetooth/radio_service.dart
// Wraps flutter_benlink RadioController with OpenHT-specific logic
// Protocol decoded by Kyle Husmann KC3SLD (https://github.com/khusmann/benlink)

import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:flutter_benlink/flutter_benlink.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/repeater.dart';

enum RadioConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
  error,
}

class RadioService extends ChangeNotifier {
  RadioController? _controller;
  RadioConnectionState _connectionState = RadioConnectionState.disconnected;
  String? _errorMessage;
  List<BluetoothDevice> _pairedDevices = [];

  // RFCOMM UUIDs in connection priority order
  // Primary:   00001101-0000-1000-8000-00805F9B34FB (Standard SPP)
  // Fallback:  00001107-D102-11E1-9B23-00025B00A5A5 (GAIA protocol)
  // Secondary: 00001102-D102-11E1-9B23-00025B00A5A5 (audio/PTT channel)
  static const String uuidSpp  = '00001101-0000-1000-8000-00805F9B34FB';
  static const String uuidGaia = '00001107-D102-11E1-9B23-00025B00A5A5';
  static const String uuidAux  = '00001102-D102-11E1-9B23-00025B00A5A5';

  RadioConnectionState get connectionState => _connectionState;
  bool get isConnected => _connectionState == RadioConnectionState.connected;
  RadioController? get controller => _controller;
  String? get errorMessage => _errorMessage;
  List<BluetoothDevice> get pairedDevices => _pairedDevices;

  // Expose radio state from controller
  String? get currentChannelName => _controller?.currentChannelName;
  double? get batteryVoltage => _controller?.batteryVoltage;
  int? get batteryPercent => _controller?.batteryLevelAsPercentage;
  bool? get isGpsLocked => _controller?.isGpsLocked;
  bool? get isTransmitting => _controller?.isInTx;
  bool? get isReceiving => _controller?.isInRx;

  // VFO / channel state
  double get currentRxFreq => _controller?.currentRxFreq ?? 0.0;
  ModulationType? get currentMode => _controller?.currentChannel?.rxMod;
  BandwidthType? get currentBandwidth => _controller?.currentChannel?.bandwidth;
  int get squelchLevel => _controller?.settings?.squelchLevel ?? 0;
  int get volumeLevel => _controller?.settings?.micGain ?? 0;
  int get currentChannelId => _controller?.currentChannelId ?? 0;

  /// Request BLUETOOTH_SCAN + BLUETOOTH_CONNECT + RECORD_AUDIO runtime permissions.
  /// Returns true if all are granted.
  Future<bool> requestBluetoothPermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.microphone, // Required for BT SCO audio routing
    ].request();

    final scanGranted    = statuses[Permission.bluetoothScan]?.isGranted    ?? false;
    final connectGranted = statuses[Permission.bluetoothConnect]?.isGranted ?? false;
    final micGranted     = statuses[Permission.microphone]?.isGranted       ?? false;

    if (!scanGranted || !connectGranted) {
      _errorMessage =
          'Bluetooth permissions are required to find and connect to the radio.\n'
          'Please allow Bluetooth access when prompted.';
      notifyListeners();
      return false;
    }
    if (!micGranted) {
      debugPrint('OpenHT: RECORD_AUDIO not granted — BT audio routing will not work');
    }
    return true;
  }

  /// Ensure the radio is in VFO mode before writing frequency.
  /// Per the Benshi protocol, vfoX=1 (VFO A) must be set before setVfoFrequency()
  /// or the radio stays in channel/memory mode and ignores frequency writes.
  Future<void> _ensureVfoMode() async {
    final s = _controller?.settings;
    if (s == null || s.vfoX == 1) return;
    await _controller!.writeSettings(s.copyWith(vfoX: 1));
    await Future.delayed(const Duration(milliseconds: 150));
  }

  /// Scan for paired Bluetooth devices — user selects the radio.
  /// Requests BLUETOOTH_SCAN/CONNECT permissions before scanning.
  Future<List<BluetoothDevice>> scanPairedDevices() async {
    _connectionState = RadioConnectionState.scanning;
    _errorMessage = null;
    notifyListeners();

    // ── Runtime permission check (Android 12+) ──────────────────────────────
    if (!await requestBluetoothPermissions()) {
      _connectionState = RadioConnectionState.error;
      notifyListeners();
      return [];
    }

    try {
      final devices = await FlutterBluetoothSerial.instance.getBondedDevices();
      // Filter to likely radio devices by name patterns
      _pairedDevices = devices.where((d) {
        final name = (d.name ?? '').toUpperCase();
        return name.contains('VR-N') ||
            name.contains('UV-PRO') ||
            name.contains('GA-5WB') ||
            name.contains('GMRS') ||
            name.contains('HT') ||
            name.contains('VGC') ||
            name.contains('BENSHI');
      }).toList();

      // If no known radios, show all devices so user can pick
      if (_pairedDevices.isEmpty) _pairedDevices = devices;

      _connectionState = RadioConnectionState.disconnected;
      notifyListeners();
      return _pairedDevices;
    } catch (e) {
      _errorMessage = 'Bluetooth scan error: $e';
      _connectionState = RadioConnectionState.error;
      notifyListeners();
      return [];
    }
  }

  /// Connect to a paired Bluetooth device (radio).
  Future<bool> connect(BluetoothDevice device) async {
    _connectionState = RadioConnectionState.connecting;
    _errorMessage = null;
    notifyListeners();

    try {
      _controller = RadioController(device: device);
      await _controller!.connect().timeout(const Duration(seconds: 15));

      // Wait for controller to become ready (fetches device info + state)
      int attempts = 0;
      while (!(_controller?.isReady ?? false) && attempts < 30) {
        await Future.delayed(const Duration(milliseconds: 200));
        attempts++;
      }

      if (!(_controller?.isReady ?? false)) {
        throw Exception('Radio did not become ready in time');
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

  /// Tune the radio to a specific frequency in MHz (e.g. NWR: 162.400).
  Future<bool> tuneToFrequency(double frequencyMhz) async {
    if (_controller == null || !isConnected) return false;
    try {
      await _ensureVfoMode();
      await _controller!.setVfoFrequency(frequencyMhz);
      debugPrint('OpenHT: Tuned to ${frequencyMhz.toStringAsFixed(4)} MHz');
      return true;
    } catch (e) {
      _errorMessage = 'Tune failed: $e';
      notifyListeners();
      return false;
    }
  }

  /// Step VFO frequency up or down by stepMhz (e.g. 0.025 for 25 kHz).
  Future<bool> stepFrequency(double stepMhz) async {
    if (_controller == null || !isConnected) return false;
    try {
      await _ensureVfoMode();
      final newFreq = _controller!.currentRxFreq + stepMhz;
      await _controller!.setVfoFrequency(newFreq);
      return true;
    } catch (e) {
      _errorMessage = 'Step failed: $e';
      notifyListeners();
      return false;
    }
  }

  /// Set modulation mode on the VFO channel.
  Future<bool> setVfoMode(ModulationType mod, BandwidthType bw) async {
    if (_controller == null || !isConnected) return false;
    try {
      await _ensureVfoMode();
      final vfo = await _controller!.getChannel(0);
      await _controller!.writeChannel(
        vfo.copyWith(rxMod: mod, txMod: mod, bandwidth: bw),
      );
      return true;
    } catch (e) {
      _errorMessage = 'Mode set failed: $e';
      notifyListeners();
      return false;
    }
  }

  /// Set squelch level (0–15).
  Future<bool> setSquelch(int level) async {
    if (_controller == null || !isConnected) return false;
    final s = _controller!.settings;
    if (s == null) return false;
    try {
      await _controller!.writeSettings(s.copyWith(squelchLevel: level.clamp(0, 15)));
      return true;
    } catch (e) {
      _errorMessage = 'Squelch set failed: $e';
      notifyListeners();
      return false;
    }
  }

  /// Set speaker volume / mic gain (0–7).
  Future<bool> setVolume(int level) async {
    if (_controller == null || !isConnected) return false;
    final s = _controller!.settings;
    if (s == null) return false;
    try {
      await _controller!.writeSettings(s.copyWith(micGain: level.clamp(0, 7)));
      return true;
    } catch (e) {
      _errorMessage = 'Volume set failed: $e';
      notifyListeners();
      return false;
    }
  }

  /// Fetch all memory channels from the radio (slow — ~50 ms per channel).
  Future<List<Channel>> getAllChannels() async {
    if (_controller == null) return [];
    try {
      return await _controller!.getAllChannels();
    } catch (e) {
      debugPrint('OpenHT: getAllChannels failed — $e');
      return [];
    }
  }

  /// Tune VFO to a repeater output freq and set its CTCSS tone (NFM mode).
  Future<bool> tuneToRepeaterGpx({
    required double outputFreqMhz,
    double? ctcssHz,
  }) async {
    if (_controller == null || !isConnected) return false;
    try {
      await _ensureVfoMode();
      final vfo = await _controller!.getChannel(0);
      final updated = vfo.copyWith(
        rxFreq: outputFreqMhz,
        txFreq: outputFreqMhz,
        rxMod: ModulationType.FM,
        txMod: ModulationType.FM,
        bandwidth: BandwidthType.NARROW,
        txSubAudio: ctcssHz,
        rxSubAudio: ctcssHz,
      );
      await _controller!.writeChannel(updated);
      debugPrint('OpenHT: Tuned to ${outputFreqMhz.toStringAsFixed(4)} MHz'
          '${ctcssHz != null ? ' PL ${ctcssHz.toStringAsFixed(1)} Hz' : ''}');
      return true;
    } catch (e) {
      _errorMessage = 'Tune failed: $e';
      notifyListeners();
      return false;
    }
  }

  /// Tune the radio to a repeater's output frequency with correct tone.
  Future<bool> tuneToRepeater(Repeater repeater) async {
    if (_controller == null || !isConnected) return false;

    try {
      await _controller!.setVfoFrequency(repeater.frequency);
      debugPrint(
          'OpenHT: Tuned to ${repeater.displayFreq} ${repeater.displayTone}');
      return true;
    } catch (e) {
      _errorMessage = 'Tune failed: $e';
      notifyListeners();
      return false;
    }
  }

  /// Write a repeater as a named memory channel in the radio.
  Future<bool> writeChannel({
    required Repeater repeater,
    required int groupIndex,   // 0-5 (radio has 6 groups)
    required int channelIndex, // 0-31 (32 channels per group)
  }) async {
    if (_controller == null || !isConnected) return false;

    try {
      final channel = Channel(
        channelId: groupIndex * 32 + channelIndex,
        txMod: ModulationType.FM,
        txFreq: repeater.frequency,
        rxMod: ModulationType.FM,
        rxFreq: repeater.frequency,
        scan: true,
        txAtMaxPower: false,
        txAtMedPower: false,
        bandwidth: BandwidthType.NARROW,
        name: _sanitizeChannelName(repeater.sysname),
      );
      await _controller!.writeChannel(channel);
      return true;
    } catch (e) {
      _errorMessage = 'Write channel failed: $e';
      notifyListeners();
      return false;
    }
  }

  /// Batch write up to 32 nearest repeaters into a dedicated group.
  Future<int> writeNearRepeaterGroup({
    required List<Repeater> repeaters,
    int groupIndex = 5, // Use last group "Near" by default
  }) async {
    if (_controller == null || !isConnected) return 0;

    int written = 0;
    final toWrite = repeaters.take(32).toList();

    for (int i = 0; i < toWrite.length; i++) {
      final success = await writeChannel(
        repeater: toWrite[i],
        groupIndex: groupIndex,
        channelIndex: i,
      );
      if (success) written++;
      // Small delay between channel writes to avoid overwhelming radio
      await Future.delayed(const Duration(milliseconds: 100));
    }

    debugPrint('OpenHT: Wrote $written/${toWrite.length} near repeaters to Group $groupIndex');
    return written;
  }

  void disconnect() {
    _controller?.removeListener(_onRadioStateChanged);
    _controller?.dispose();
    _controller = null;
    _connectionState = RadioConnectionState.disconnected;
    notifyListeners();
  }

  /// Sanitize channel name to fit radio's 8-char limit.
  static String _sanitizeChannelName(String name) {
    return name.replaceAll(RegExp(r'[^A-Z0-9\-\s]', caseSensitive: false), '')
        .toUpperCase()
        .trim()
        .padRight(1)
        .substring(0, name.length.clamp(1, 8));
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
