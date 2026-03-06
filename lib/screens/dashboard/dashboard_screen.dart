// lib/screens/dashboard/dashboard_screen.dart
// Main radio control dashboard — frequency, mode, squelch, volume, CH/VFO, PTT

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_benlink/flutter_benlink.dart';
import '../../bluetooth/radio_service.dart';
import '../../services/audio_service.dart';
import '../../services/gps_service.dart';

class DashboardScreen extends StatefulWidget {
  /// Called when the user taps a Quick Action that navigates to another tab.
  final ValueChanged<int>? onNavigate;

  const DashboardScreen({super.key, this.onNavigate});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // VFO step size in kHz; stored in SharedPreferences
  double _stepKhz = 25.0;
  static const _kStepKhz = 'vfo_step_khz';

  // CH mode state
  bool _isChannelMode = false;
  List<Channel> _channels = [];
  int _channelIndex = 0;
  bool _isLoadingChannels = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _stepKhz = prefs.getDouble(_kStepKhz) ?? 25.0;
      });
    }
  }

  Future<void> _saveStepKhz(double step) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kStepKhz, step);
  }

  // ─── Mode helpers ──────────────────────────────────────────────────────────

  String _modeLabel(RadioService radio) {
    final mod = radio.currentMode;
    final bw  = radio.currentBandwidth;
    if (mod == null) return '—';
    if (mod == ModulationType.AM) return 'AM';
    return bw == BandwidthType.NARROW ? 'NFM' : 'FM';
  }

  // ─── CH mode loading ───────────────────────────────────────────────────────

  Future<void> _toggleChannelMode(RadioService radio) async {
    if (!_isChannelMode) {
      // Switch to CH mode: load channel list first
      setState(() => _isLoadingChannels = true);
      final ch = await radio.getAllChannels();
      if (!mounted) return;
      setState(() {
        _channels = ch.where((c) => c.name.trim().isNotEmpty).toList();
        _channelIndex = 0;
        _isLoadingChannels = false;
        _isChannelMode = _channels.isNotEmpty;
      });
      if (_channels.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No named channels found on radio')),
        );
      }
    } else {
      setState(() => _isChannelMode = false);
    }
  }

  Future<void> _stepChannel(RadioService radio, int delta) async {
    if (_channels.isEmpty) return;
    final newIdx = (_channelIndex + delta).clamp(0, _channels.length - 1);
    setState(() => _channelIndex = newIdx);
    final ch = _channels[newIdx];
    await radio.tuneToFrequency(ch.rxFreq);
  }

  // ─── Frequency keypad ──────────────────────────────────────────────────────

  Future<void> _openFreqKeypad(RadioService radio) async {
    final current = radio.currentRxFreq;
    final result = await showDialog<double>(
      context: context,
      builder: (_) => _FreqKeypadDialog(initialFreq: current),
    );
    if (result != null && result > 0) {
      await radio.tuneToFrequency(result);
    }
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final radio = context.watch<RadioService>();
    final audio = context.watch<AudioService>();
    final gps   = context.watch<GpsService>();

    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: const Text('OpenHT'),
        backgroundColor: Colors.grey[850],
        foregroundColor: Colors.white,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Icon(
              radio.isConnected
                  ? Icons.bluetooth_connected
                  : Icons.bluetooth_disabled,
              color: radio.isConnected ? Colors.blue : Colors.grey,
            ),
          ),
        ],
      ),
      body: radio.isConnected
          ? _ConnectedView(
              radio: radio,
              audio: audio,
              gps: gps,
              stepKhz: _stepKhz,
              isChannelMode: _isChannelMode,
              channels: _channels,
              channelIndex: _channelIndex,
              isLoadingChannels: _isLoadingChannels,
              modeLabel: _modeLabel(radio),
              onStepKhzChanged: (v) {
                setState(() => _stepKhz = v);
                _saveStepKhz(v);
              },
              onFreqTap: () => _openFreqKeypad(radio),
              onStepUp: () => radio.stepFrequency(_stepKhz / 1000.0),
              onStepDown: () => radio.stepFrequency(-_stepKhz / 1000.0),
              onToggleChannelMode: () => _toggleChannelMode(radio),
              onChannelUp: () => _stepChannel(radio, 1),
              onChannelDown: () => _stepChannel(radio, -1),
              onNavigate: widget.onNavigate,
            )
          : _DisconnectedView(onNavigate: widget.onNavigate),
    );
  }
}

// ─── Connected View ──────────────────────────────────────────────────────────

class _ConnectedView extends StatelessWidget {
  final RadioService radio;
  final AudioService audio;
  final GpsService gps;
  final double stepKhz;
  final bool isChannelMode;
  final List<Channel> channels;
  final int channelIndex;
  final bool isLoadingChannels;
  final String modeLabel;
  final ValueChanged<double> onStepKhzChanged;
  final VoidCallback onFreqTap;
  final VoidCallback onStepUp;
  final VoidCallback onStepDown;
  final VoidCallback onToggleChannelMode;
  final VoidCallback onChannelUp;
  final VoidCallback onChannelDown;
  final ValueChanged<int>? onNavigate;

  const _ConnectedView({
    required this.radio,
    required this.audio,
    required this.gps,
    required this.stepKhz,
    required this.isChannelMode,
    required this.channels,
    required this.channelIndex,
    required this.isLoadingChannels,
    required this.modeLabel,
    required this.onStepKhzChanged,
    required this.onFreqTap,
    required this.onStepUp,
    required this.onStepDown,
    required this.onToggleChannelMode,
    required this.onChannelUp,
    required this.onChannelDown,
    this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Frequency / Channel Display ─────────────────────────────────
          _FrequencyCard(
            radio: radio,
            audio: audio,
            isChannelMode: isChannelMode,
            channels: channels,
            channelIndex: channelIndex,
            isLoadingChannels: isLoadingChannels,
            stepKhz: stepKhz,
            modeLabel: modeLabel,
            onFreqTap: onFreqTap,
            onStepUp: onStepUp,
            onStepDown: onStepDown,
            onStepKhzChanged: onStepKhzChanged,
            onToggleChannelMode: onToggleChannelMode,
            onChannelUp: onChannelUp,
            onChannelDown: onChannelDown,
          ),
          const SizedBox(height: 10),

          // ── Mode / Squelch / Volume ─────────────────────────────────────
          _RadioControls(radio: radio, modeLabel: modeLabel),
          const SizedBox(height: 10),

          // ── Status Row ─────────────────────────────────────────────────
          Row(
            children: [
              Expanded(child: _StatusTile(
                icon: Icons.battery_charging_full,
                label: 'Battery',
                value: radio.batteryPercent != null
                    ? '${radio.batteryPercent}% (${radio.batteryVoltage?.toStringAsFixed(1)}V)'
                    : '—',
                color: _batteryColor(radio.batteryPercent),
              )),
              const SizedBox(width: 8),
              Expanded(child: _StatusTile(
                icon: Icons.gps_fixed,
                label: 'GPS',
                value: gps.hasPosition ? gps.displayPosition : 'No Fix',
                color: gps.hasPosition ? Colors.green : Colors.orange,
              )),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _StatusTile(
                icon: Icons.radio,
                label: 'TX',
                value: (radio.isTransmitting ?? false) ? 'TRANSMITTING' : 'Idle',
                color: (radio.isTransmitting ?? false) ? Colors.red : Colors.grey,
              )),
              const SizedBox(width: 8),
              Expanded(child: _StatusTile(
                icon: Icons.hearing,
                label: 'RX',
                value: (radio.isReceiving ?? false) ? 'RECEIVING' : 'Idle',
                color: (radio.isReceiving ?? false) ? Colors.green : Colors.grey,
              )),
            ],
          ),
          const SizedBox(height: 14),

          // ── Quick Actions ──────────────────────────────────────────────
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Quick Actions',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
          ),
          const SizedBox(height: 8),
          _QuickActions(radio: radio, audio: audio, onNavigate: onNavigate),
        ],
      ),
    );
  }

  Color _batteryColor(int? pct) {
    if (pct == null) return Colors.grey;
    if (pct > 60) return Colors.green;
    if (pct > 30) return Colors.orange;
    return Colors.red;
  }
}

// ─── Frequency Display Card ───────────────────────────────────────────────────

class _FrequencyCard extends StatelessWidget {
  final RadioService radio;
  final AudioService audio;
  final bool isChannelMode;
  final List<Channel> channels;
  final int channelIndex;
  final bool isLoadingChannels;
  final double stepKhz;
  final String modeLabel;
  final VoidCallback onFreqTap;
  final VoidCallback onStepUp;
  final VoidCallback onStepDown;
  final ValueChanged<double> onStepKhzChanged;
  final VoidCallback onToggleChannelMode;
  final VoidCallback onChannelUp;
  final VoidCallback onChannelDown;

  const _FrequencyCard({
    required this.radio,
    required this.audio,
    required this.isChannelMode,
    required this.channels,
    required this.channelIndex,
    required this.isLoadingChannels,
    required this.stepKhz,
    required this.modeLabel,
    required this.onFreqTap,
    required this.onStepUp,
    required this.onStepDown,
    required this.onStepKhzChanged,
    required this.onToggleChannelMode,
    required this.onChannelUp,
    required this.onChannelDown,
  });

  String _freqDisplay() {
    if (isChannelMode && channels.isNotEmpty) {
      return channels[channelIndex].rxFreq.toStringAsFixed(4);
    }
    final f = radio.currentRxFreq;
    return f > 0 ? f.toStringAsFixed(4) : '--- . ----';
  }

  String _channelLabel() {
    if (!isChannelMode || channels.isEmpty) return radio.currentChannelName ?? '';
    final ch = channels[channelIndex];
    return 'CH ${ch.channelId}  ${ch.name.trim()}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green[700]!, width: 1),
      ),
      child: Column(
        children: [
          // Channel name / VFO label row with SCO audio icon
          Row(
            children: [
              Expanded(
                child: Text(
                  isChannelMode ? _channelLabel() : (radio.currentChannelName ?? 'VFO'),
                  style: const TextStyle(
                      color: Colors.green, fontSize: 12, letterSpacing: 1.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _ScoStatusIcon(audio: audio),
            ],
          ),
          const SizedBox(height: 6),

          // Frequency — tappable in VFO mode
          GestureDetector(
            onTap: isChannelMode ? null : onFreqTap,
            child: Text(
              '${_freqDisplay()} MHz',
              style: TextStyle(
                color: Colors.green[400],
                fontSize: 32,
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
          ),
          const SizedBox(height: 10),

          // VFO: step buttons + step selector  |  CH: channel step buttons
          if (isChannelMode)
            _ChannelStepButtons(
              onUp: onChannelUp,
              onDown: onChannelDown,
              chIndex: channelIndex,
              chCount: channels.length,
            )
          else
            _VfoStepControls(
              stepKhz: stepKhz,
              onStepUp: onStepUp,
              onStepDown: onStepDown,
              onStepKhzChanged: onStepKhzChanged,
            ),
          const SizedBox(height: 8),

          // CH / VFO toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              isLoadingChannels
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.green),
                    )
                  : OutlinedButton.icon(
                      onPressed: onToggleChannelMode,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.green,
                        side: const BorderSide(color: Colors.green),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: Icon(
                        isChannelMode ? Icons.tune : Icons.list,
                        size: 16,
                      ),
                      label: Text(
                        isChannelMode ? 'VFO' : 'CH',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── SCO Audio Status Icon ────────────────────────────────────────────────────

class _ScoStatusIcon extends StatelessWidget {
  final AudioService audio;
  const _ScoStatusIcon({required this.audio});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (audio.scoState) {
      ScoState.off        => (Icons.volume_off,     Colors.grey),
      ScoState.connecting => (Icons.volume_up,       Colors.orange),
      ScoState.connected  => (Icons.volume_up,       Colors.green),
      ScoState.error      => (Icons.error_outline,   Colors.red),
    };
    return GestureDetector(
      onTap: () => audio.toggleAudio(),
      child: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }
}

class _VfoStepControls extends StatelessWidget {
  final double stepKhz;
  final VoidCallback onStepUp;
  final VoidCallback onStepDown;
  final ValueChanged<double> onStepKhzChanged;

  const _VfoStepControls({
    required this.stepKhz,
    required this.onStepUp,
    required this.onStepDown,
    required this.onStepKhzChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _GreenButton(icon: Icons.remove, onTap: onStepDown),
        const SizedBox(width: 8),
        // Step size selector
        DropdownButton<double>(
          value: stepKhz,
          dropdownColor: Colors.grey[850],
          style: const TextStyle(color: Colors.green, fontSize: 12),
          underline: const SizedBox(),
          items: const [
            DropdownMenuItem(value: 5.0, child: Text('5 kHz')),
            DropdownMenuItem(value: 12.5, child: Text('12.5 kHz')),
            DropdownMenuItem(value: 25.0, child: Text('25 kHz')),
          ],
          onChanged: (v) => onStepKhzChanged(v ?? stepKhz),
        ),
        const SizedBox(width: 8),
        _GreenButton(icon: Icons.add, onTap: onStepUp),
      ],
    );
  }
}

class _ChannelStepButtons extends StatelessWidget {
  final VoidCallback onUp;
  final VoidCallback onDown;
  final int chIndex;
  final int chCount;

  const _ChannelStepButtons({
    required this.onUp,
    required this.onDown,
    required this.chIndex,
    required this.chCount,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _GreenButton(icon: Icons.arrow_upward, onTap: chIndex < chCount - 1 ? onUp : null),
        const SizedBox(width: 16),
        Text(
          '${chIndex + 1} / $chCount',
          style: const TextStyle(color: Colors.green, fontSize: 12),
        ),
        const SizedBox(width: 16),
        _GreenButton(icon: Icons.arrow_downward, onTap: chIndex > 0 ? onDown : null),
      ],
    );
  }
}

class _GreenButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _GreenButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.green[900],
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: onTap != null ? Colors.green[600]! : Colors.grey[700]!,
          ),
        ),
        child: Icon(
          icon,
          size: 18,
          color: onTap != null ? Colors.green[300] : Colors.grey[600],
        ),
      ),
    );
  }
}

// ─── Radio Controls (Mode / Squelch / Volume) ─────────────────────────────────

class _RadioControls extends StatelessWidget {
  final RadioService radio;
  final String modeLabel;

  const _RadioControls({required this.radio, required this.modeLabel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[850],
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          // Mode selector
          Row(
            children: [
              const Text('Mode', style: TextStyle(color: Colors.white54, fontSize: 11)),
              const SizedBox(width: 12),
              _ModeButton(
                label: 'FM',
                selected: modeLabel == 'FM',
                onTap: () => radio.setVfoMode(ModulationType.FM, BandwidthType.WIDE),
              ),
              const SizedBox(width: 6),
              _ModeButton(
                label: 'NFM',
                selected: modeLabel == 'NFM',
                onTap: () => radio.setVfoMode(ModulationType.FM, BandwidthType.NARROW),
              ),
              const SizedBox(width: 6),
              _ModeButton(
                label: 'AM',
                selected: modeLabel == 'AM',
                onTap: () => radio.setVfoMode(ModulationType.AM, BandwidthType.NARROW),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Squelch slider
          _SliderRow(
            label: 'SQL',
            value: radio.squelchLevel.toDouble(),
            min: 0,
            max: 9,
            divisions: 9,
            color: Colors.orange,
            onChanged: (v) => radio.setSquelch(v.round()),
          ),
          const SizedBox(height: 6),

          // Volume slider
          _SliderRow(
            label: 'VOL',
            value: radio.volumeLevel.toDouble(),
            min: 0,
            max: 7,
            divisions: 7,
            color: Colors.blue,
            onChanged: (v) => radio.setVolume(v.round()),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ModeButton({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? Colors.blue[700] : Colors.grey[800],
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected ? Colors.blue[400]! : Colors.grey[600]!,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white60,
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final Color color;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 32,
          child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: color,
              thumbColor: color,
              overlayColor: color.withOpacity(0.2),
              inactiveTrackColor: Colors.grey[700],
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 24,
          child: Text(
            value.round().toString(),
            textAlign: TextAlign.right,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

// ─── Status Tile ───────────────────────────────────────────────────────────────

class _StatusTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatusTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey[850],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
              Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ─── Quick Actions ─────────────────────────────────────────────────────────────

class _QuickActions extends StatelessWidget {
  final RadioService radio;
  final AudioService audio;
  final ValueChanged<int>? onNavigate;

  const _QuickActions({
    required this.radio,
    required this.audio,
    this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.3,
          children: [
            _ActionButton(
              icon: Icons.cell_tower,
              label: 'Near\nRepeaters',
              color: Colors.blue,
              onTap: () => onNavigate?.call(1),
            ),
            _ActionButton(
              icon: Icons.map,
              label: 'APRS\nMap',
              color: Colors.green,
              onTap: () => onNavigate?.call(2),
            ),
            _ActionButton(
              icon: Icons.settings,
              label: 'Radio\nSettings',
              color: Colors.orange,
              onTap: () => onNavigate?.call(5),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _PttButton(audio: audio, radio: radio),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.4), width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(color: color, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── PTT Button ───────────────────────────────────────────────────────────────

class _PttButton extends StatefulWidget {
  final AudioService audio;
  final RadioService radio;

  const _PttButton({required this.audio, required this.radio});

  @override
  State<_PttButton> createState() => _PttButtonState();
}

class _PttButtonState extends State<_PttButton> {
  bool _pressing = false;

  Future<void> _onPressStart() async {
    setState(() => _pressing = true);
    await widget.audio.startPtt();
    await widget.radio.startTransmit();
  }

  Future<void> _onPressEnd() async {
    await widget.radio.stopTransmit();
    await widget.audio.stopPtt();
    if (mounted) setState(() => _pressing = false);
  }

  @override
  Widget build(BuildContext context) {
    final canTransmit = widget.radio.isConnected;

    return GestureDetector(
      onLongPressStart: canTransmit ? (_) => _onPressStart() : null,
      onLongPressEnd:   canTransmit ? (_) => _onPressEnd()   : null,
      onLongPressCancel: () => _onPressEnd(),
      onTap: canTransmit
          ? () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Hold to transmit'),
                  duration: Duration(seconds: 1),
                ))
          : null,
      child: Container(
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          color: _pressing
              ? Colors.red[700]
              : canTransmit
                  ? Colors.red[900]
                  : Colors.grey[850],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _pressing
                ? Colors.red[300]!
                : canTransmit
                    ? Colors.red[700]!
                    : Colors.grey[700]!,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.mic,
              color: _pressing
                  ? Colors.white
                  : canTransmit
                      ? Colors.red[300]
                      : Colors.grey[600],
              size: 22,
            ),
            const SizedBox(width: 8),
            Text(
              _pressing ? 'TRANSMITTING' : 'PTT',
              style: TextStyle(
                color: _pressing
                    ? Colors.white
                    : canTransmit
                        ? Colors.red[300]
                        : Colors.grey[600],
                fontSize: 15,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Disconnected View ────────────────────────────────────────────────────────

class _DisconnectedView extends StatelessWidget {
  final ValueChanged<int>? onNavigate;

  const _DisconnectedView({this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.bluetooth_searching, size: 72, color: Colors.white24),
          const SizedBox(height: 16),
          const Text(
            'No Radio Connected',
            style: TextStyle(color: Colors.white54, fontSize: 20),
          ),
          const SizedBox(height: 8),
          const Text(
            'Pair your VGC radio via Android Settings,\nthen connect from the Radio Settings tab.',
            style: TextStyle(color: Colors.white38, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            icon: const Icon(Icons.settings),
            label: const Text('Go to Radio Settings'),
            onPressed: () => onNavigate?.call(5),
          ),
        ],
      ),
    );
  }
}

// ─── Frequency Keypad Dialog ──────────────────────────────────────────────────

class _FreqKeypadDialog extends StatefulWidget {
  final double initialFreq;

  const _FreqKeypadDialog({required this.initialFreq});

  @override
  State<_FreqKeypadDialog> createState() => _FreqKeypadDialogState();
}

class _FreqKeypadDialogState extends State<_FreqKeypadDialog> {
  String _input = '';
  bool _hasDecimal = false;

  @override
  void initState() {
    super.initState();
    _input = widget.initialFreq.toStringAsFixed(4);
    _hasDecimal = _input.contains('.');
  }

  void _onKey(String key) {
    setState(() {
      if (key == '.') {
        if (!_hasDecimal) {
          _input += '.';
          _hasDecimal = true;
        }
      } else if (key == '⌫') {
        if (_input.isNotEmpty) {
          if (_input[_input.length - 1] == '.') _hasDecimal = false;
          _input = _input.substring(0, _input.length - 1);
        }
      } else {
        // Limit total length
        if (_input.length < 11) _input += key;
      }
    });
  }

  void _confirm() {
    final freq = double.tryParse(_input);
    if (freq != null && freq > 0) {
      Navigator.pop(context, freq);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid frequency')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.grey[900],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter Frequency (MHz)',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green[700]!),
              ),
              child: Text(
                _input.isEmpty ? '—' : '$_input MHz',
                style: TextStyle(
                  color: Colors.green[400],
                  fontSize: 24,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 12),
            // Numpad
            for (final row in [
              ['1', '2', '3'],
              ['4', '5', '6'],
              ['7', '8', '9'],
              ['.', '0', '⌫'],
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: row.map((k) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: SizedBox(
                      width: 64,
                      height: 44,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[800],
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        onPressed: () => _onKey(k),
                        child: Text(k, style: const TextStyle(fontSize: 18)),
                      ),
                    ),
                  )).toList(),
                ),
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700]),
                    onPressed: _confirm,
                    child: const Text('Tune'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
