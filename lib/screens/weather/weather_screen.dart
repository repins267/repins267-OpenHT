// lib/screens/weather/weather_screen.dart
// NOAA Weather Radio tab — active alerts + nearest NWR stations

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/noaa_service.dart';
import '../../services/gps_service.dart';
import '../../services/weather_alert_controller.dart';
import '../../bluetooth/radio_service.dart';
import '../../models/nwr_station.dart';
import '../../models/weather_alert.dart';
import 'submit_report_screen.dart';

class WeatherScreen extends StatefulWidget {
  const WeatherScreen({super.key});

  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> {
  NwrStation? _selectedStation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final gps        = context.read<GpsService>();
    final noaa       = context.read<NoaaService>();
    final alertCtrl  = context.read<WeatherAlertController>();
    if (gps.hasPosition) {
      await noaa.refresh(gps.latitude!, gps.longitude!);
      await alertCtrl.checkNow();
    }
  }

  @override
  Widget build(BuildContext context) {
    final noaa      = context.watch<NoaaService>();
    final gps       = context.watch<GpsService>();
    final alertCtrl = context.watch<WeatherAlertController>();
    final radio     = context.watch<RadioService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Weather'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: noaa.isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: noaa.isLoading ? null : _refresh,
          ),
        ],
      ),
      body: gps.hasPosition
          ? RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                children: [
                  // ─── Emergency Alert Banner ────────────
                  if (alertCtrl.hasEmergencyAlert)
                    _EmergencyAlertBanner(
                      freq: alertCtrl.autoTunedFreq!,
                      onDismiss: alertCtrl.clearLock,
                    ),

                  // ─── GPS Location ──────────────────────
                  _LocationBar(gps: gps),

                  // ─── Error banner ──────────────────────
                  if (noaa.error != null)
                    _ErrorBanner(message: noaa.error!),

                  // ─── Active Alerts ─────────────────────
                  if (noaa.alerts.isNotEmpty) ...[
                    _SectionHeader('Active Alerts (${noaa.alerts.length})'),
                    ...noaa.alerts.map((a) => _AlertCard(alert: a)),
                  ] else if (!noaa.isLoading)
                    const _NoAlertsCard(),

                  // ─── Selected Station Tune Panel ───────
                  if (_selectedStation != null)
                    _SelectedStationPanel(
                      station: _selectedStation!,
                      radio: radio,
                      onClear: () => setState(() => _selectedStation = null),
                    ),

                  // ─── NOAA WX Channels ──────────────────
                  _SectionHeader('NOAA WX Channels'),
                  _NoaaChannelSelector(),

                  // ─── NWR Stations ──────────────────────
                  _SectionHeader('Nearest NWR Stations'),
                  if (noaa.isLoading && noaa.stations.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (noaa.stations.isEmpty && !noaa.isLoading)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No stations loaded. Pull to refresh.',
                          style: TextStyle(color: Colors.white54)),
                    )
                  else
                    ...noaa.stations.take(20).map((s) => _NwrStationCard(
                          station: s,
                          isSelected: _selectedStation == s,
                          onSelect: () =>
                              setState(() => _selectedStation = s),
                        )),

                  const SizedBox(height: 80),
                ],
              ),
            )
          : const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.gps_off, size: 48, color: Colors.white38),
                  SizedBox(height: 8),
                  Text('Waiting for GPS fix…',
                      style: TextStyle(color: Colors.white54)),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SubmitReportScreen()),
        ),
        icon: const Text('⚠️', style: TextStyle(fontSize: 16)),
        label: const Text('Submit Report'),
        backgroundColor: Colors.orange[800],
        foregroundColor: Colors.white,
      ),
    );
  }
}

// ─── Sub-widgets ─────────────────────────────────────────────────────────────

class _LocationBar extends StatelessWidget {
  final GpsService gps;
  const _LocationBar({required this.gps});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey[850],
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.my_location, size: 14, color: Colors.blue),
          const SizedBox(width: 6),
          Text(gps.displayPosition,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red[900],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: const TextStyle(color: Colors.white, fontSize: 12))),
        ],
      ),
    );
  }
}

class _NoAlertsCard extends StatelessWidget {
  const _NoAlertsCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green[900],
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        children: [
          Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
          SizedBox(width: 8),
          Text('No active weather alerts for your area',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  final WeatherAlert alert;
  const _AlertCard({required this.alert});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: alert.severityColor.withOpacity(0.15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: alert.severityColor, width: 1),
      ),
      child: ExpansionTile(
        leading: Icon(alert.severityIcon, color: alert.severityColor),
        title: Text(alert.event,
            style: TextStyle(
              color: alert.severityColor,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            )),
        subtitle: alert.areaDesc != null
            ? Text(alert.areaDesc!,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis)
            : null,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (alert.headline.isNotEmpty)
                  Text(alert.headline,
                      style: const TextStyle(color: Colors.white70, fontSize: 13)),
                if (alert.description != null) ...[
                  const SizedBox(height: 6),
                  Text(alert.description!,
                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
                if (alert.expires != null) ...[
                  const SizedBox(height: 6),
                  Text('Expires: ${alert.expires}',
                      style: const TextStyle(color: Colors.white38, fontSize: 11)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Emergency Alert Banner ───────────────────────────────────────────────────

class _EmergencyAlertBanner extends StatelessWidget {
  final String freq;
  final VoidCallback onDismiss;
  const _EmergencyAlertBanner({required this.freq, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.red[900],
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.warning_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'EMERGENCY ALERT: AUTO-TUNED TO $freq',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          TextButton(
            onPressed: onDismiss,
            child: const Text('DISMISS',
                style: TextStyle(color: Colors.white70, fontSize: 11)),
          ),
        ],
      ),
    );
  }
}

// ─── Selected Station Tune Panel ──────────────────────────────────────────────

class _SelectedStationPanel extends StatelessWidget {
  final NwrStation station;
  final RadioService radio;
  final VoidCallback onClear;
  const _SelectedStationPanel(
      {required this.station, required this.radio, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue[900],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue, width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(station.callSign,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
                Text('${station.city}, ${station.state}  •  ${station.displayFreq}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.radio, size: 16),
            label: const Text('Tap Radio to Tune',
                style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  radio.isConnected ? Colors.green[700] : Colors.grey[700],
            ),
            onPressed: radio.isConnected
                ? () async {
                    final ok = await radio.tuneToFrequency(station.frequency);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(ok
                          ? 'Tuned VFO A → ${station.callSign} ${station.displayFreq}'
                          : 'Tune failed: ${radio.errorMessage}'),
                      backgroundColor: ok ? Colors.blue[800] : Colors.red[700],
                      duration: const Duration(seconds: 2),
                    ));
                  }
                : null,
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54, size: 18),
            onPressed: onClear,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
        ],
      ),
    );
  }
}

// ─── NWR Station Card ─────────────────────────────────────────────────────────

class _NwrStationCard extends StatelessWidget {
  final NwrStation station;
  final bool isSelected;
  final VoidCallback onSelect;
  const _NwrStationCard(
      {required this.station,
      required this.isSelected,
      required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      tileColor: isSelected ? Colors.blue[900]!.withOpacity(0.3) : null,
      leading: CircleAvatar(
        backgroundColor: isSelected ? Colors.blue[700] : Colors.blue[900],
        radius: 22,
        child: Text(
          station.displayFreq.split(' ')[0],
          style: const TextStyle(
              color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
      ),
      title: Text(station.callSign,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold)),
      subtitle: Text(
        '${station.city}, ${station.state}  •  ${station.displayFreq}',
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (station.distanceMiles != null)
            Text(station.displayDistance,
                style: const TextStyle(color: Colors.blue, fontSize: 12)),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  isSelected ? Colors.blue[600] : Colors.grey[700],
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
            ),
            onPressed: onSelect,
            child: Text(isSelected ? 'Selected' : 'Tap to Select',
                style: const TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }
}

class _NoaaChannelSelector extends StatelessWidget {
  const _NoaaChannelSelector();

  @override
  Widget build(BuildContext context) {
    final radio = context.watch<RadioService>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: kNoaaChannels.map((entry) {
          final (label, freq) = entry;
          return ActionChip(
            label: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
                Text(freq.toStringAsFixed(3),
                    style: const TextStyle(color: Colors.white70, fontSize: 10)),
              ],
            ),
            backgroundColor: Colors.blue[900],
            side: const BorderSide(color: Colors.blue, width: 0.5),
            onPressed: radio.isConnected
                ? () async {
                    final ok = await radio.tuneToFrequency(freq);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(ok
                            ? 'Tuned to $label — $freq MHz'
                            : 'Tune failed: ${radio.errorMessage}'),
                        duration: const Duration(seconds: 2),
                        backgroundColor: ok ? Colors.blue[800] : Colors.red[700],
                      ),
                    );
                  }
                : null,
          );
        }).toList(),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: Colors.blue[400],
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}
