// lib/bluetooth/radio_service.dart
// Wraps flutter_benlink RadioController with OpenHT-specific logic
// Protocol decoded by Kyle Husmann KC3SLD (https://github.com/khusmann/benlink)

import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:flutter_benlink/flutter_benlink.dart';
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
  bool? get isTransmitting => _controller?.isTransmitting;
  bool? get isReceiving => _controller?.isReceiving;

  /// Scan for paired Bluetooth devices - user selects the radio
  Future<List<BluetoothDevice>> scanPairedDevices() async {
    _connectionState = RadioConnectionState.scanning;
    notifyListeners();

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

  /// Connect to a paired Bluetooth device (radio)
  Future<bool> connect(BluetoothDevice device) async {
    _connectionState = RadioConnectionState.connecting;
    _errorMessage = null;
    notifyListeners();

    try {
      final connection =
          await BluetoothConnection.toAddress(device.address)
              .timeout(const Duration(seconds: 15));

      _controller = RadioController(connection: connection);

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

  /// Tune the radio to a repeater's output frequency with correct tone
  Future<bool> tuneToRepeater(Repeater repeater) async {
    if (_controller == null || !isConnected) return false;

    try {
      // Build a channel config from the repeater data
      // flutter_benlink's RadioController handles VFO writes
      await _controller!.setVfoFrequency(
        (repeater.frequency * 1e6).round(), // Hz integer
      );

      // TODO: Set CTCSS/DCS tone once flutter_benlink exposes that API
      // For now, frequency tuning is the primary action

      debugPrint(
          'OpenHT: Tuned to ${repeater.displayFreq} ${repeater.displayTone}');
      return true;
    } catch (e) {
      _errorMessage = 'Tune failed: $e';
      notifyListeners();
      return false;
    }
  }

  /// Write a repeater as a named memory channel in the radio
  Future<bool> writeChannel({
    required Repeater repeater,
    required int groupIndex,   // 0-5 (radio has 6 groups)
    required int channelIndex, // 0-31 (32 channels per group)
  }) async {
    if (_controller == null || !isConnected) return false;

    try {
      // Channel writing via flutter_benlink API
      // The library handles the Benshi BT protocol serialization
      await _controller!.writeChannel(
        groupIndex: groupIndex,
        channelIndex: channelIndex,
        frequency: (repeater.frequency * 1e6).round(),
        name: _sanitizeChannelName(repeater.sysname),
        // Additional fields (tone, offset) added as flutter_benlink expands API
      );
      return true;
    } catch (e) {
      _errorMessage = 'Write channel failed: $e';
      notifyListeners();
      return false;
    }
  }

  /// Batch write up to 32 nearest repeaters into a dedicated group
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

  /// Sanitize channel name to fit radio's 8-char limit
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
