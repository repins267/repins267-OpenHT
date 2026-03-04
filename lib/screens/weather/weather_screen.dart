// lib/screens/weather/weather_screen.dart
// NOAA Weather Radio tab — active alerts + nearest NWR stations

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/noaa_service.dart';
import '../../services/gps_service.dart';
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final gps  = context.read<GpsService>();
    final noaa = context.read<NoaaService>();
    if (gps.hasPosition) {
      await noaa.refresh(gps.latitude!, gps.longitude!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final noaa  = context.watch<NoaaService>();
    final gps   = context.watch<GpsService>();

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
                    ...noaa.stations
                        .take(20)
                        .map((s) => _NwrStationCard(station: s)),

                  const SizedBox(height: 80), // FAB clearance
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

class _NwrStationCard extends StatelessWidget {
  final NwrStation station;
  const _NwrStationCard({required this.station});

  @override
  Widget build(BuildContext context) {
    final radio = context.watch<RadioService>();

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.blue[900],
        radius: 22,
        child: Text(
          station.displayFreq.split(' ')[0],
          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
      ),
      title: Text(
        station.callSign,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        '${station.city}, ${station.state}  •  ${station.displayFreq}',
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (station.distanceMiles != null)
            Text(
              station.displayDistance,
              style: const TextStyle(color: Colors.blue, fontSize: 12),
            ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: radio.isConnected ? Colors.blue[700] : Colors.grey[700],
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
            ),
            onPressed: radio.isConnected
                ? () => _tuneStation(context, radio, station)
                : null,
            child: const Text('Tune', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  void _tuneStation(BuildContext context, RadioService radio, NwrStation station) {
    radio.tuneToFrequency(station.frequency);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Tuned to ${station.callSign} — ${station.displayFreq}'),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.blue[800],
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
