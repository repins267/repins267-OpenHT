// lib/screens/aprs_map/aprs_map_screen.dart
// APRS station map using OpenStreetMap via flutter_map
// Displays APRS beacons as POI markers

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../services/gps_service.dart';
import '../../aprs/aprs_service.dart';
import '../../aprs/aprs_packet.dart';

class AprsMapScreen extends StatefulWidget {
  const AprsMapScreen({super.key});

  @override
  State<AprsMapScreen> createState() => _AprsMapScreenState();
}

class _AprsMapScreenState extends State<AprsMapScreen> {
  final MapController _mapController = MapController();
  bool _followMyLocation = true;
  AprsPacket? _selectedStation;

  @override
  Widget build(BuildContext context) {
    final gps = context.watch<GpsService>();
    final aprs = context.watch<AprsService>();

    final myLatLon = gps.hasPosition
        ? LatLng(gps.latitude!, gps.longitude!)
        : const LatLng(39.8283, -98.5795); // Geographic center of USA

    if (_followMyLocation && gps.hasPosition) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapController.move(myLatLon, _mapController.camera.zoom);
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('APRS Map'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(
              _followMyLocation ? Icons.gps_fixed : Icons.gps_not_fixed,
              color: _followMyLocation ? Colors.yellow : Colors.white70,
            ),
            tooltip: 'Follow my location',
            onPressed: () => setState(() => _followMyLocation = !_followMyLocation),
          ),
          IconButton(
            icon: const Icon(Icons.layers),
            tooltip: 'Layer options',
            onPressed: _showLayerOptions,
          ),
        ],
      ),
      body: Stack(
        children: [
          // ─── Map ───────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: myLatLon,
              initialZoom: 11,
              onTap: (_, __) => setState(() => _selectedStation = null),
            ),
            children: [
              // Base tile layer (OpenStreetMap)
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.openht.app',
                maxZoom: 19,
              ),

              // APRS station markers
              MarkerLayer(
                markers: [
                  // My position marker
                  if (gps.hasPosition)
                    Marker(
                      point: myLatLon,
                      width: 24,
                      height: 24,
                      child: _MyPositionMarker(),
                    ),

                  // APRS station POIs
                  ...aprs.stations.where((s) => s.hasPosition).map((station) {
                    final isSelected = _selectedStation?.callsign == station.callsign;
                    return Marker(
                      point: LatLng(station.latitude!, station.longitude!),
                      width: isSelected ? 48 : 32,
                      height: isSelected ? 48 : 32,
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedStation = station),
                        child: _AprsStationMarker(station: station, selected: isSelected),
                      ),
                    );
                  }),
                ],
              ),
            ],
          ),

          // ─── Station info popup ────────────────────────
          if (_selectedStation != null)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: _StationInfoCard(
                station: _selectedStation!,
                myLat: gps.latitude,
                myLon: gps.longitude,
                onClose: () => setState(() => _selectedStation = null),
              ),
            ),

          // ─── APRS stats overlay ────────────────────────
          Positioned(
            top: 8,
            right: 8,
            child: _AprsStatsChip(stationCount: aprs.stations.length),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _mapController.move(myLatLon, 12),
        tooltip: 'Center on my location',
        child: const Icon(Icons.my_location),
      ),
    );
  }

  void _showLayerOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[850],
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(
            title: Text('Map Layers', style: TextStyle(color: Colors.white)),
          ),
          CheckboxListTile(
            title: const Text('APRS Stations', style: TextStyle(color: Colors.white70)),
            value: true,
            onChanged: (_) {},
          ),
          CheckboxListTile(
            title: const Text('Repeater Locations', style: TextStyle(color: Colors.white70)),
            value: false,
            onChanged: (_) {},
          ),
        ],
      ),
    );
  }
}

// ─── Marker Widgets ─────────────────────────────────────────────────────────

class _MyPositionMarker extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.blue,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(color: Colors.blue.withOpacity(0.4), blurRadius: 8, spreadRadius: 2),
        ],
      ),
    );
  }
}

class _AprsStationMarker extends StatelessWidget {
  final AprsPacket station;
  final bool selected;

  const _AprsStationMarker({required this.station, required this.selected});

  @override
  Widget build(BuildContext context) {
    final color = _colorForSymbol(station.symbol);
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(selected ? 1.0 : 0.7),
        border: Border.all(
          color: selected ? Colors.yellow : Colors.white,
          width: selected ? 2.5 : 1.5,
        ),
      ),
      child: Center(
        child: Text(
          _emojiForSymbol(station.symbol),
          style: TextStyle(fontSize: selected ? 18 : 12),
        ),
      ),
    );
  }

  Color _colorForSymbol(String? symbol) {
    switch (symbol) {
      case '>': return Colors.green;     // Car
      case 'j': return Colors.orange;   // Jeep/truck
      case '/': return Colors.purple;   // Fixed station
      case '_': return Colors.cyan;     // Weather
      default:  return Colors.grey;
    }
  }

  String _emojiForSymbol(String? symbol) {
    switch (symbol) {
      case '>': return '🚗';
      case 'j': return '🚙';
      case '/': return '📡';
      case '_': return '🌤';
      default:  return '📻';
    }
  }
}

class _StationInfoCard extends StatelessWidget {
  final AprsPacket station;
  final double? myLat;
  final double? myLon;
  final VoidCallback onClose;

  const _StationInfoCard({
    required this.station,
    required this.myLat,
    required this.myLon,
    required this.onClose,
  });

  String get _distanceStr {
    if (myLat == null || myLon == null || !station.hasPosition) return '';
    final dist = const Distance().as(
      LengthUnit.Mile,
      LatLng(myLat!, myLon!),
      LatLng(station.latitude!, station.longitude!),
    );
    return '${dist.toStringAsFixed(1)} mi away';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.grey[900],
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  station.callsign,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(_distanceStr,
                    style: const TextStyle(color: Colors.blue, fontSize: 12)),
                const SizedBox(width: 8),
                GestureDetector(onTap: onClose,
                    child: const Icon(Icons.close, color: Colors.white54, size: 20)),
              ],
            ),
            if (station.comment != null)
              Text(station.comment!,
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 4),
            Text(
              station.timestampDisplay,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _AprsStatsChip extends StatelessWidget {
  final int stationCount;
  const _AprsStatsChip({required this.stationCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$stationCount stations',
        style: const TextStyle(color: Colors.white70, fontSize: 11),
      ),
    );
  }
}
