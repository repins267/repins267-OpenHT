// lib/screens/weather/weather_screen.dart
// NOAA Weather Radio tab — active alerts + nearest NWR stations + SPC/mPING/LSR

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/noaa_service.dart';
import '../../services/gps_service.dart';
import '../../services/weather_alert_controller.dart';
import '../../services/nws_alert_service.dart';
import '../../services/spc_service.dart';
import '../../services/mping_service.dart';
import '../../services/lsr_service.dart';
import '../../services/spotter_network_service.dart';
import '../../bluetooth/radio_service.dart';
import '../../models/nwr_station.dart';
import '../../models/weather_alert.dart';
import '../../models/nws_alert.dart';
import '../../models/spc_outlook.dart';
import '../../models/mping_report.dart';
import 'nws_alert_detail_screen.dart';
import 'mping_report_list_screen.dart';
import 'spotter_list_screen.dart';
import 'submit_report_screen.dart';
import 'weather_layer_drawer.dart';

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
    // Load layer prefs
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WeatherLayerState>().load();
      _refresh();
    });
  }

  Future<void> _refresh() async {
    final gps       = context.read<GpsService>();
    final noaa      = context.read<NoaaService>();
    final alertCtrl = context.read<WeatherAlertController>();
    final nwsAlerts = context.read<NwsAlertService>();
    final mping     = context.read<MpingService>();
    final lsr       = context.read<LsrService>();
    final spc       = context.read<SpcService>();
    if (gps.hasPosition) {
      final lat = gps.latitude!;
      final lon = gps.longitude!;
      await noaa.refresh(lat, lon);
      await alertCtrl.checkNow();
      nwsAlerts.startPolling(lat, lon);
      mping.startPolling(lat, lon);
      lsr.startPolling(lat, lon);
    }
    spc.startPolling();
  }

  @override
  Widget build(BuildContext context) {
    final noaa      = context.watch<NoaaService>();
    final gps       = context.watch<GpsService>();
    final alertCtrl = context.watch<WeatherAlertController>();
    final radio     = context.watch<RadioService>();
    final nwsAlerts = context.watch<NwsAlertService>();
    final spc       = context.watch<SpcService>();
    final mping     = context.watch<MpingService>();
    final lsr       = context.watch<LsrService>();
    final snSvc     = context.watch<SpotterNetworkService>();
    final layers    = context.watch<WeatherLayerState>();

    return Scaffold(
      drawer: WeatherLayerDrawer(state: layers),
      appBar: AppBar(
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.layers_outlined),
            tooltip: 'Weather Layers',
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: const Text('Weather'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: (noaa.isLoading || nwsAlerts.isLoading || spc.isLoading)
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: (noaa.isLoading || nwsAlerts.isLoading || spc.isLoading)
                ? null
                : _refresh,
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

                  // ─── Error banners ─────────────────────
                  if (noaa.error != null) _ErrorBanner(message: noaa.error!),

                  // ─── NWS API Alerts ─────────────────────────────────
                  if (layers.get(WeatherLayers.warnings) ||
                      layers.get(WeatherLayers.watches) ||
                      layers.get(WeatherLayers.statements)) ...[
                    if (nwsAlerts.alerts.isNotEmpty) ...[
                      _SectionHeader(
                          'NWS Alerts (${nwsAlerts.alerts.length})'),
                      ...nwsAlerts.warnings
                          .where((_) => layers.get(WeatherLayers.warnings))
                          .map((a) => _NwsAlertCard(alert: a)),
                      ...nwsAlerts.watches
                          .where((_) => layers.get(WeatherLayers.watches))
                          .map((a) => _NwsAlertCard(alert: a)),
                      ...nwsAlerts.statements
                          .where((_) => layers.get(WeatherLayers.statements))
                          .map((a) => _NwsAlertCard(alert: a)),
                      ...nwsAlerts.alerts
                          .where((a) =>
                              a.type == NwsAlertType.advisory)
                          .map((a) => _NwsAlertCard(alert: a)),
                    ],
                  ],

                  // ─── NOAA WX Alerts (legacy) ───────────
                  if (noaa.alerts.isNotEmpty) ...[
                    _SectionHeader('NOAA Alerts (${noaa.alerts.length})'),
                    ...noaa.alerts.map((a) => _AlertCard(alert: a)),
                  ] else if (!noaa.isLoading && nwsAlerts.alerts.isEmpty)
                    const _NoAlertsCard(),

                  // ─── SPC Outlook Card ──────────────────
                  if (layers.get(WeatherLayers.outlooks) &&
                      spc.outlooks.isNotEmpty) ...[
                    _SectionHeader('SPC Convective Outlook'),
                    _SpcOutlookCard(spc: spc),
                  ],

                  // ─── SPC Mesoscale Discussions ─────────
                  if (layers.get(WeatherLayers.discussions) &&
                      spc.mesoscaleDiscussions.isNotEmpty) ...[
                    _SectionHeader(
                        'SPC Discussions (${spc.mesoscaleDiscussions.length})'),
                    ...spc.mesoscaleDiscussions
                        .take(3)
                        .map((md) => _MdCard(md: md)),
                  ],

                  // ─── mPING Reports ─────────────────────
                  if (layers.get(WeatherLayers.mping)) ...[
                    _SectionHeader(
                        'mPING Reports (${mping.reports.length})'),
                    _MpingCard(reports: mping.reports.take(5).toList()),
                    if (mping.reports.isNotEmpty)
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12),
                        child: TextButton.icon(
                          icon: const Icon(Icons.list),
                          label: Text(
                              'View all ${mping.reports.length} reports'),
                          onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const MpingReportListScreen())),
                        ),
                      ),
                  ],

                  // ─── Storm Reports (LSR) ───────────────
                  if (layers.get(WeatherLayers.lsr)) ...[
                    _SectionHeader(
                        'Storm Reports — ${lsr.wfo ?? "LSR"} (${lsr.reports.length})'),
                    _LsrCard(reports: lsr.reports.take(5).toList()),
                  ],

                  // ─── Storm Spotters ────────────────────
                  if (layers.get(WeatherLayers.spotter) &&
                      snSvc.showOnMap &&
                      snSvc.spotters.isNotEmpty) ...[
                    _SectionHeader('Storm Spotters (${snSvc.spotters.length})'),
                    _SpotterCard(count: snSvc.spotters.length),
                  ],

                  // ─── Selected Station Tune Panel ───────
                  if (_selectedStation != null)
                    _SelectedStationPanel(
                      station: _selectedStation!,
                      radio: radio,
                      onClear: () =>
                          setState(() => _selectedStation = null),
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
                    ...noaa.stations.take(20).map(
                          (s) => _NwrStationCard(
                            station: s,
                            isSelected: _selectedStation == s,
                            onSelect: () =>
                                setState(() => _selectedStation = s),
                          ),
                        ),

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

// ─── NWS Alert Card ───────────────────────────────────────────────────────────

class _NwsAlertCard extends StatelessWidget {
  final NwsAlert alert;
  const _NwsAlertCard({required this.alert});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: alert.severityColor.withOpacity(0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: alert.severityColor, width: 1),
      ),
      child: ListTile(
        leading: Icon(alert.severityIcon, color: alert.severityColor),
        title: Text(
          alert.event,
          style: TextStyle(
            color: alert.severityColor,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          alert.expiresCountdown.isNotEmpty
              ? alert.expiresCountdown
              : (alert.areaDesc ?? ''),
          style: const TextStyle(color: Colors.white54, fontSize: 11),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.white38),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => NwsAlertDetailScreen(alert: alert)),
        ),
      ),
    );
  }
}

// ─── SPC Outlook Card ─────────────────────────────────────────────────────────

class _SpcOutlookCard extends StatelessWidget {
  final SpcService spc;
  const _SpcOutlookCard({required this.spc});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: Colors.grey[850],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_outlined, color: Colors.purple, size: 18),
                const SizedBox(width: 6),
                const Text('Convective Outlook',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
                const Spacer(),
                Text(
                  'SPC',
                  style: TextStyle(
                      color: Colors.purple[300],
                      fontSize: 11,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _OutlookDay(label: 'Day 1', outlook: spc.day1),
                _OutlookDay(label: 'Day 2', outlook: spc.day2),
                _OutlookDay(label: 'Day 3', outlook: spc.day3),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OutlookDay extends StatelessWidget {
  final String label;
  final SpcDayOutlook? outlook;
  const _OutlookDay({required this.label, required this.outlook});

  @override
  Widget build(BuildContext context) {
    final risk = outlook?.maxRisk ?? 'N/A';
    final color = outlook != null ? SpcRisk.color(risk) : Colors.grey;
    final riskLabel = outlook != null ? SpcRisk.label(risk) : '—';
    return Column(
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(height: 4),
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            border: Border.all(color: color, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              risk,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(riskLabel,
            style: TextStyle(color: color, fontSize: 10)),
      ],
    );
  }
}

// ─── SPC MD Card ──────────────────────────────────────────────────────────────

class _MdCard extends StatelessWidget {
  final SpcMd md;
  const _MdCard({required this.md});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.article_outlined, color: Colors.blue, size: 20),
      title: Text(md.title,
          style: const TextStyle(color: Colors.white, fontSize: 13)),
      subtitle: md.text != null
          ? Text(
              md.text!,
              style:
                  const TextStyle(color: Colors.white54, fontSize: 11),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            )
          : null,
    );
  }
}

// ─── mPING Card ───────────────────────────────────────────────────────────────

class _MpingCard extends StatelessWidget {
  final List<MpingReport> reports;
  const _MpingCard({required this.reports});

  @override
  Widget build(BuildContext context) {
    if (reports.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.grey[850],
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text('No mPING reports in the last hour (75 mi)',
              style: TextStyle(color: Colors.white38, fontSize: 12)),
        ),
      );
    }
    return Column(
      children: reports
          .map((r) => ListTile(
                leading: Text(r.emoji,
                    style: const TextStyle(fontSize: 20)),
                title: Text(r.category,
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
                subtitle: r.description.isNotEmpty
                    ? Text(r.description,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis)
                    : null,
                trailing: Text(r.timeAgo,
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 11)),
                dense: true,
              ))
          .toList(),
    );
  }
}

// ─── LSR Card ─────────────────────────────────────────────────────────────────

class _LsrCard extends StatelessWidget {
  final List<LsrReport> reports;
  const _LsrCard({required this.reports});

  @override
  Widget build(BuildContext context) {
    if (reports.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.grey[850],
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text('No storm reports in last 24 hours',
              style: TextStyle(color: Colors.white38, fontSize: 12)),
        ),
      );
    }
    return Column(
      children: reports
          .map((r) => ListTile(
                leading: Text(r.emoji,
                    style: const TextStyle(fontSize: 20)),
                title: Text(
                  r.type.isNotEmpty ? r.type : 'Report',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
                subtitle: Text(
                  [
                    if (r.city.isNotEmpty) r.city,
                    if (r.magnitude.isNotEmpty) r.magnitude,
                  ].join(' · '),
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(r.timeAgo,
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 11)),
                dense: true,
              ))
          .toList(),
    );
  }
}

// ─── Spotter Count Card ───────────────────────────────────────────────────────

class _SpotterCard extends StatelessWidget {
  final int count;
  const _SpotterCard({required this.count});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: Colors.orange[900]!.withOpacity(0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.orange, width: 1),
      ),
      child: ListTile(
        leading: const Icon(Icons.person_pin_circle,
            color: Colors.orange, size: 28),
        title: Text(
          '$count active storm spotter${count == 1 ? '' : 's'}',
          style: const TextStyle(
              color: Colors.orange, fontWeight: FontWeight.bold),
        ),
        subtitle: const Text('Visible on APRS map as orange markers',
            style: TextStyle(color: Colors.white54, fontSize: 11)),
        trailing: const Icon(Icons.chevron_right, color: Colors.white38),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const SpotterListScreen())),
      ),
    );
  }
}

// ─── Sub-widgets (unchanged) ──────────────────────────────────────────────────

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
          Expanded(
              child: Text(message,
                  style: const TextStyle(color: Colors.white, fontSize: 12))),
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
                style:
                    const TextStyle(color: Colors.white54, fontSize: 11),
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
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 13)),
                if (alert.description != null) ...[
                  const SizedBox(height: 6),
                  Text(alert.description!,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12)),
                ],
                if (alert.expires != null) ...[
                  const SizedBox(height: 6),
                  Text('Expires: ${alert.expires}',
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 11)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmergencyAlertBanner extends StatelessWidget {
  final String freq;
  final VoidCallback onDismiss;
  const _EmergencyAlertBanner(
      {required this.freq, required this.onDismiss});

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

class _SelectedStationPanel extends StatelessWidget {
  final NwrStation station;
  final RadioService radio;
  final VoidCallback onClear;
  const _SelectedStationPanel(
      {required this.station,
      required this.radio,
      required this.onClear});

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
                Text(
                    '${station.city}, ${station.state}  ·  ${station.displayFreq}',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.radio, size: 16),
            label: const Text('Tune', style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: radio.isConnected
                  ? Colors.green[700]
                  : Colors.grey[700],
            ),
            onPressed: radio.isConnected
                ? () async {
                    final ok =
                        await radio.tuneToFrequency(station.frequency);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(ok
                          ? 'Tuned VFO A → ${station.callSign} ${station.displayFreq}'
                          : 'Tune failed: ${radio.errorMessage}'),
                      backgroundColor:
                          ok ? Colors.blue[800] : Colors.red[700],
                      duration: const Duration(seconds: 2),
                    ));
                  }
                : null,
          ),
          const SizedBox(width: 4),
          IconButton(
            icon:
                const Icon(Icons.close, color: Colors.white54, size: 18),
            onPressed: onClear,
            padding: EdgeInsets.zero,
            constraints:
                const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
        ],
      ),
    );
  }
}

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
      tileColor: isSelected
          ? Colors.blue[900]!.withOpacity(0.3)
          : null,
      leading: CircleAvatar(
        backgroundColor:
            isSelected ? Colors.blue[700] : Colors.blue[900],
        radius: 22,
        child: Text(
          station.displayFreq.split(' ')[0],
          style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
      ),
      title: Text(station.callSign,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold)),
      subtitle: Text(
        '${station.city}, ${station.state}  ·  ${station.displayFreq}',
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (station.distanceMiles != null)
            Text(station.displayDistance,
                style:
                    const TextStyle(color: Colors.blue, fontSize: 12)),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  isSelected ? Colors.blue[600] : Colors.grey[700],
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
            ),
            onPressed: onSelect,
            child: Text(isSelected ? 'Selected' : 'Select',
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
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 10)),
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
                        backgroundColor: ok
                            ? Colors.blue[800]
                            : Colors.red[700],
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
