// lib/screens/aprs/station_detail_screen.dart
// APRS Station detail — map mini-preview, info, Tune / Message / Track buttons

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../aprs/aprs_packet.dart';
import '../../bluetooth/radio_service.dart';
import '../../services/gps_service.dart';
import '../../services/map_tile_service.dart';
import 'message_thread_screen.dart';

class StationDetailScreen extends StatelessWidget {
  final AprsPacket packet;
  const StationDetailScreen({super.key, required this.packet});

  @override
  Widget build(BuildContext context) {
    final gps = context.watch<GpsService>();
    final radio = context.watch<RadioService>();
    final myLat = gps.latitude;
    final myLon = gps.longitude;

    double? distKm;
    double? bearing;
    if (myLat != null && myLon != null && packet.hasPosition) {
      distKm = _haversineKm(myLat, myLon, packet.latitude!, packet.longitude!);
      bearing = _bearing(myLat, myLon, packet.latitude!, packet.longitude!);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(packet.fullCallsign,
            style: const TextStyle(fontFamily: 'monospace')),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        children: [
          // ── Mini map ────────────────────────────────────────────────────
          if (packet.hasPosition)
            SizedBox(
              height: 200,
              child: FlutterMap(
                options: MapOptions(
                  initialCenter:
                      LatLng(packet.latitude!, packet.longitude!),
                  initialZoom: 12,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.none,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate: MapTileService.urlTemplate(
                        MapTileSource.openStreetMap),
                    userAgentPackageName: 'com.openht.app',
                  ),
                  MarkerLayer(markers: [
                    Marker(
                      point:
                          LatLng(packet.latitude!, packet.longitude!),
                      width: 36,
                      height: 36,
                      child: const Icon(Icons.location_on,
                          color: Colors.red, size: 32),
                    ),
                    if (myLat != null && myLon != null)
                      Marker(
                        point: LatLng(myLat, myLon),
                        width: 20,
                        height: 20,
                        child: const Icon(Icons.my_location,
                            color: Colors.blue, size: 18),
                      ),
                  ]),
                ],
              ),
            ),

          // ── Info rows ───────────────────────────────────────────────────
          _SectionHeader('Station Info'),
          _InfoRow(
            icon: Icons.badge_outlined,
            label: 'Callsign',
            value: packet.fullCallsign,
            mono: true,
          ),
          _InfoRow(
            icon: Icons.schedule_outlined,
            label: 'Last Heard',
            value: packet.timestampDisplay,
          ),
          if (packet.symbol != null)
            _InfoRow(
              icon: Icons.push_pin_outlined,
              label: 'Symbol',
              value: '${packet.symbolTable ?? ""}${packet.symbol}',
              mono: true,
            ),
          if (packet.comment != null && packet.comment!.isNotEmpty)
            _InfoRow(
              icon: Icons.comment_outlined,
              label: 'Comment',
              value: packet.comment!,
            ),

          if (packet.hasPosition) ...[
            _SectionHeader('Position'),
            _InfoRow(
              icon: Icons.gps_fixed,
              label: 'Coordinates',
              value: '${packet.latitude!.toStringAsFixed(5)}, '
                  '${packet.longitude!.toStringAsFixed(5)}',
              mono: true,
            ),
            if (distKm != null)
              _InfoRow(
                icon: Icons.straighten_outlined,
                label: 'Distance',
                value: distKm < 1
                    ? '${(distKm * 1000).round()} m'
                    : '${distKm.toStringAsFixed(2)} km',
              ),
            if (bearing != null)
              _InfoRow(
                icon: Icons.explore_outlined,
                label: 'Bearing',
                value: '${bearing.toStringAsFixed(0)}° '
                    '(${_compassFull(bearing)})',
              ),
            if (packet.altitudeFeet != null)
              _InfoRow(
                icon: Icons.terrain_outlined,
                label: 'Altitude',
                value:
                    '${packet.altitudeFeet!.round()} ft '
                    '(${(packet.altitudeFeet! * 0.3048).round()} m)',
              ),
          ],

          if (packet.speedKnots != null || packet.courseDegrees != null) ...[
            _SectionHeader('Motion'),
            if (packet.speedKnots != null)
              _InfoRow(
                icon: Icons.speed_outlined,
                label: 'Speed',
                value:
                    '${(packet.speedKnots! * 1.852).toStringAsFixed(1)} km/h',
              ),
            if (packet.courseDegrees != null)
              _InfoRow(
                icon: Icons.navigation_outlined,
                label: 'Course',
                value: '${packet.courseDegrees!.toStringAsFixed(0)}°',
              ),
          ],

          // ── Actions ─────────────────────────────────────────────────────
          _SectionHeader('Actions'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.message_outlined, size: 18),
                  label: const Text('Message'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MessageThreadScreen(
                          peerCallsign: packet.fullCallsign),
                    ),
                  ),
                ),
                if (radio.isConnected)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.radio, size: 18),
                    label: const Text('Tune (last freq)'),
                    onPressed: () => _showTuneDialog(context, radio),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue[300],
                      side: BorderSide(color: Colors.blue[700]!),
                    ),
                  ),
              ],
            ),
          ),

          // ── Raw packet ──────────────────────────────────────────────────
          _SectionHeader('Raw Packet'),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SelectableText(
              packet.raw,
              style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontFamily: 'monospace'),
            ),
          ),

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  void _showTuneDialog(BuildContext context, RadioService radio) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: Text('Tune to ${packet.fullCallsign}',
            style: const TextStyle(color: Colors.white)),
        content: const Text(
          'Enter the frequency for this station:',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
        ],
      ),
    );
  }

  String _compassFull(double bearing) {
    const dirs = ['N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
                   'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'];
    final idx = ((bearing + 11.25) / 22.5).floor() % 16;
    return dirs[idx];
  }
}

// ── Info row widget ───────────────────────────────────────────────────────────
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool mono;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(icon, color: Colors.white54, size: 20),
      title: Text(label,
          style: const TextStyle(color: Colors.white38, fontSize: 11)),
      subtitle: Text(
        value,
        style: TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontFamily: mono ? 'monospace' : null,
        ),
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────
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

// ── Geo helpers ───────────────────────────────────────────────────────────────
double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0;
  final dLat = _deg2rad(lat2 - lat1);
  final dLon = _deg2rad(lon2 - lon1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_deg2rad(lat1)) *
          math.cos(_deg2rad(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _bearing(double lat1, double lon1, double lat2, double lon2) {
  final dLon = _deg2rad(lon2 - lon1);
  final y = math.sin(dLon) * math.cos(_deg2rad(lat2));
  final x = math.cos(_deg2rad(lat1)) * math.sin(_deg2rad(lat2)) -
      math.sin(_deg2rad(lat1)) *
          math.cos(_deg2rad(lat2)) *
          math.cos(dLon);
  return (_rad2deg(math.atan2(y, x)) + 360) % 360;
}

double _deg2rad(double d) => d * math.pi / 180;
double _rad2deg(double r) => r * 180 / math.pi;
