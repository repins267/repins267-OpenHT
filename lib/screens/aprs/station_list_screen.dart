// lib/screens/aprs/station_list_screen.dart
// APRS Station Hub — lists all heard stations with distance, bearing, age

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../aprs/aprs_packet.dart';
import '../../aprs/aprs_service.dart';
import '../../services/gps_service.dart';
import 'station_detail_screen.dart';

// ── Sort options ──────────────────────────────────────────────────────────────
enum _SortBy { distance, callsign, age }

class StationListScreen extends StatefulWidget {
  const StationListScreen({super.key});

  @override
  State<StationListScreen> createState() => _StationListScreenState();
}

class _StationListScreenState extends State<StationListScreen> {
  _SortBy _sortBy = _SortBy.distance;
  String _filter = '';
  final _filterController = TextEditingController();

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final aprs = context.watch<AprsService>();
    final gps = context.watch<GpsService>();
    final myLat = gps.currentPosition?.latitude;
    final myLon = gps.currentPosition?.longitude;

    var stations = aprs.stations.where((s) => s.hasPosition).toList();

    // Filter by callsign substring
    if (_filter.isNotEmpty) {
      final q = _filter.toUpperCase();
      stations = stations
          .where((s) => s.fullCallsign.contains(q) ||
              (s.comment?.toUpperCase().contains(q) ?? false))
          .toList();
    }

    // Sort
    stations.sort((a, b) {
      switch (_sortBy) {
        case _SortBy.callsign:
          return a.fullCallsign.compareTo(b.fullCallsign);
        case _SortBy.age:
          return b.receivedAt.compareTo(a.receivedAt);
        case _SortBy.distance:
          if (myLat == null || myLon == null) {
            return a.fullCallsign.compareTo(b.fullCallsign);
          }
          final da =
              _haversineKm(myLat, myLon, a.latitude!, a.longitude!);
          final db =
              _haversineKm(myLat, myLon, b.latitude!, b.longitude!);
          return da.compareTo(db);
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text('Stations (${stations.length})'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _filterController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Filter callsign…',
                hintStyle: const TextStyle(color: Colors.white38),
                isDense: true,
                filled: true,
                fillColor: Colors.black26,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                prefixIcon:
                    const Icon(Icons.search, color: Colors.white38, size: 18),
                suffixIcon: _filter.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear,
                            color: Colors.white38, size: 18),
                        onPressed: () {
                          _filterController.clear();
                          setState(() => _filter = '');
                        },
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => _filter = v.trim()),
            ),
          ),
        ),
        actions: [
          PopupMenuButton<_SortBy>(
            icon: const Icon(Icons.sort),
            onSelected: (v) => setState(() => _sortBy = v),
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: _SortBy.distance, child: Text('Sort by Distance')),
              PopupMenuItem(
                  value: _SortBy.callsign, child: Text('Sort by Callsign')),
              PopupMenuItem(value: _SortBy.age, child: Text('Sort by Age')),
            ],
          ),
        ],
      ),
      body: stations.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.radar, size: 56, color: Colors.white24),
                  const SizedBox(height: 12),
                  Text(
                    _filter.isNotEmpty
                        ? 'No stations matching "$_filter"'
                        : 'No stations heard yet',
                    style: const TextStyle(color: Colors.white38),
                  ),
                ],
              ),
            )
          : ListView.separated(
              itemCount: stations.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: Colors.white10),
              itemBuilder: (ctx, i) {
                final s = stations[i];
                final distKm = myLat != null && myLon != null
                    ? _haversineKm(myLat, myLon, s.latitude!, s.longitude!)
                    : null;
                final bearing = myLat != null && myLon != null
                    ? _bearing(myLat, myLon, s.latitude!, s.longitude!)
                    : null;
                return _StationRow(
                  packet: s,
                  distKm: distKm,
                  bearing: bearing,
                  onTap: () => Navigator.push(
                    ctx,
                    MaterialPageRoute(
                      builder: (_) =>
                          StationDetailScreen(packet: s),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ── Station row ───────────────────────────────────────────────────────────────
class _StationRow extends StatelessWidget {
  final AprsPacket packet;
  final double? distKm;
  final double? bearing;
  final VoidCallback onTap;

  const _StationRow({
    required this.packet,
    required this.distKm,
    required this.bearing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final age = DateTime.now().difference(packet.receivedAt);
    final ageColor = age.inMinutes < 10
        ? Colors.green[400]!
        : age.inMinutes < 30
            ? Colors.yellow[700]!
            : Colors.white38;

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: Colors.blueGrey[800],
        child: Text(
          packet.symbol ?? '?',
          style: const TextStyle(fontSize: 16),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              packet.fullCallsign,
              style: const TextStyle(
                  color: Colors.white, fontFamily: 'monospace'),
            ),
          ),
          if (distKm != null)
            Text(
              distKm! < 1
                  ? '${(distKm! * 1000).round()} m'
                  : '${distKm!.toStringAsFixed(1)} km',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
        ],
      ),
      subtitle: Row(
        children: [
          Icon(Icons.circle, size: 8, color: ageColor),
          const SizedBox(width: 4),
          Text(packet.timestampDisplay,
              style: TextStyle(color: ageColor, fontSize: 11)),
          if (bearing != null) ...[
            const SizedBox(width: 8),
            Text(_compassPoint(bearing!),
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ],
          if (packet.comment != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                packet.comment!,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ],
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.white24),
    );
  }

  String _compassPoint(double bearing) {
    const dirs = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final idx = ((bearing + 22.5) / 45).floor() % 8;
    return dirs[idx];
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
      math.sin(_deg2rad(lat1)) * math.cos(_deg2rad(lat2)) * math.cos(dLon);
  return (_rad2deg(math.atan2(y, x)) + 360) % 360;
}

double _deg2rad(double d) => d * math.pi / 180;
double _rad2deg(double r) => r * 180 / math.pi;
