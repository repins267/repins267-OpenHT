// lib/screens/near_repeater/near_repeater_screen.dart
// Near Repeater screen - GPS-based repeater lookup and radio tuning
// Analogous to Icom's DR Mode "Near Repeater" but powered by RepeaterBook

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/repeater.dart';
import '../../services/gps_service.dart';
import '../../bluetooth/radio_service.dart';
import '../../repeaterbook/repeaterbook_client.dart';
import '../../services/repeater_cache.dart';

class NearRepeaterScreen extends StatefulWidget {
  const NearRepeaterScreen({super.key});

  @override
  State<NearRepeaterScreen> createState() => _NearRepeaterScreenState();
}

class _NearRepeaterScreenState extends State<NearRepeaterScreen> {
  final _client = RepeaterBookClient();
  final _cache = RepeaterCache();

  List<Repeater> _repeaters = [];
  bool _isLoading = false;
  String? _statusMessage;
  String _bandFilter = 'All';
  bool _onlyOpen = true;
  double _radiusMiles = 50;
  int? _tuningIndex;

  static const List<String> _bandOptions = ['All', '2m', '70cm'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadNearRepeaters());
  }

  Future<void> _loadNearRepeaters({bool forceRefresh = false}) async {
    final gps = context.read<GpsService>();
    if (!gps.hasPosition) {
      setState(() => _statusMessage = 'Waiting for GPS fix...');
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    final lat = gps.latitude!;
    final lon = gps.longitude!;

    try {
      // Try cache first (unless forcing refresh)
      if (!forceRefresh) {
        final cached = await _cache.queryNearby(
          lat: lat, lon: lon, radiusMiles: _radiusMiles,
        );
        if (cached.isNotEmpty) {
          setState(() {
            _repeaters = _applyFilters(cached);
            _isLoading = false;
            _statusMessage = 'Showing ${_repeaters.length} cached repeaters';
          });
          return;
        }
      }

      // Fetch from RepeaterBook API
      setState(() => _statusMessage = 'Fetching from RepeaterBook...');
      final results = await _client.fetchNearby(
        lat: lat,
        lon: lon,
        radiusMiles: _radiusMiles,
        band: _bandFilter == 'All' ? null : _bandFilter,
        onlyOpen: _onlyOpen,
      );

      // Cache results for offline use
      await _cache.cacheRepeaters(results);

      setState(() {
        _repeaters = _applyFilters(results);
        _isLoading = false;
        _statusMessage = 'Found ${_repeaters.length} repeaters within '
            '${_radiusMiles.round()} miles';
      });
    } catch (e) {
      // On network error, fall back to stale cache
      final stale = await _cache.queryNearby(
        lat: lat, lon: lon,
        radiusMiles: _radiusMiles,
        includeStale: true,
      );
      setState(() {
        _repeaters = _applyFilters(stale);
        _isLoading = false;
        _statusMessage = stale.isEmpty
            ? 'Network error and no cached data: $e'
            : 'Offline: showing ${stale.length} cached repeaters (may be stale)';
      });
    }
  }

  List<Repeater> _applyFilters(List<Repeater> list) {
    return list.where((r) {
      if (_bandFilter == '2m' && !(r.frequency >= 144 && r.frequency <= 148)) {
        return false;
      }
      if (_bandFilter == '70cm' && !(r.frequency >= 420 && r.frequency <= 450)) {
        return false;
      }
      if (_onlyOpen && !r.isOpen) return false;
      return true;
    }).toList();
  }

  Future<void> _tuneToRepeater(Repeater repeater, int index) async {
    final radio = context.read<RadioService>();
    if (!radio.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Radio not connected')),
      );
      return;
    }

    setState(() => _tuningIndex = index);
    final success = await radio.tuneToRepeater(repeater);
    setState(() => _tuningIndex = null);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? 'Tuned to ${repeater.displayFreq} — ${repeater.sysname}'
              : 'Tune failed: ${radio.errorMessage}'),
          backgroundColor: success ? Colors.green[700] : Colors.red[700],
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _writeGroupToRadio() async {
    final radio = context.read<RadioService>();
    if (!radio.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Radio not connected')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Write Near Repeaters to Radio'),
        content: Text(
          'Write up to ${_repeaters.take(32).length} repeaters '
          'to Group 6 (Near) on your radio?\n\n'
          'Existing channels in that group will be overwritten.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Write')),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isLoading = true;
      _statusMessage = 'Writing to radio...';
    });

    final written = await radio.writeNearRepeaterGroup(repeaters: _repeaters);

    setState(() {
      _isLoading = false;
      _statusMessage = 'Wrote $written repeaters to Group 6 on radio';
    });
  }

  @override
  Widget build(BuildContext context) {
    final gps = context.watch<GpsService>();
    final radio = context.watch<RadioService>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Near Repeaters'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh from RepeaterBook',
            onPressed: _isLoading ? null : () => _loadNearRepeaters(forceRefresh: true),
          ),
          if (radio.isConnected)
            IconButton(
              icon: const Icon(Icons.upload),
              tooltip: 'Write group to radio',
              onPressed: _isLoading || _repeaters.isEmpty ? null : _writeGroupToRadio,
            ),
        ],
      ),
      body: Column(
        children: [
          // Status bar
          _StatusBar(gps: gps, radio: radio, message: _statusMessage),

          // Filters
          _FilterBar(
            bandFilter: _bandFilter,
            onlyOpen: _onlyOpen,
            radiusMiles: _radiusMiles,
            onBandChanged: (v) {
              setState(() => _bandFilter = v);
              _loadNearRepeaters(forceRefresh: false);
            },
            onOpenChanged: (v) {
              setState(() => _onlyOpen = v);
              _loadNearRepeaters(forceRefresh: false);
            },
            onRadiusChanged: (v) {
              setState(() => _radiusMiles = v);
              _loadNearRepeaters(forceRefresh: false);
            },
            bandOptions: _bandOptions,
          ),

          // Repeater list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _repeaters.isEmpty
                    ? _EmptyState(onRefresh: () => _loadNearRepeaters(forceRefresh: true))
                    : ListView.builder(
                        itemCount: _repeaters.length,
                        itemBuilder: (ctx, i) => _RepeaterTile(
                          repeater: _repeaters[i],
                          index: i,
                          isTuning: _tuningIndex == i,
                          radioConnected: radio.isConnected,
                          onTune: () => _tuneToRepeater(_repeaters[i], i),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

// ─── Sub-widgets ────────────────────────────────────────────────────────────

class _StatusBar extends StatelessWidget {
  final GpsService gps;
  final RadioService radio;
  final String? message;

  const _StatusBar({required this.gps, required this.radio, this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey[900],
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(
            gps.hasPosition ? Icons.gps_fixed : Icons.gps_off,
            size: 14,
            color: gps.hasPosition ? Colors.green : Colors.orange,
          ),
          const SizedBox(width: 6),
          Text(
            gps.displayPosition,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          const Spacer(),
          Icon(
            radio.isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
            size: 14,
            color: radio.isConnected ? Colors.blue : Colors.grey,
          ),
          const SizedBox(width: 4),
          Text(
            message ?? (radio.isConnected ? 'Radio connected' : 'No radio'),
            style: const TextStyle(color: Colors.white70, fontSize: 11),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final String bandFilter;
  final bool onlyOpen;
  final double radiusMiles;
  final ValueChanged<String> onBandChanged;
  final ValueChanged<bool> onOpenChanged;
  final ValueChanged<double> onRadiusChanged;
  final List<String> bandOptions;

  const _FilterBar({
    required this.bandFilter,
    required this.onlyOpen,
    required this.radiusMiles,
    required this.onBandChanged,
    required this.onOpenChanged,
    required this.onRadiusChanged,
    required this.bandOptions,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey[850],
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          // Band filter chips
          ...bandOptions.map((b) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(b, style: const TextStyle(fontSize: 12)),
                  selected: bandFilter == b,
                  onSelected: (_) => onBandChanged(b),
                  selectedColor: Colors.blue[700],
                  labelStyle: TextStyle(
                    color: bandFilter == b ? Colors.white : Colors.white70,
                  ),
                ),
              )),
          const Spacer(),
          // Open only toggle
          Text('Open', style: TextStyle(color: Colors.white70, fontSize: 12)),
          Switch(
            value: onlyOpen,
            onChanged: onOpenChanged,
            activeColor: Colors.green,
          ),
          // Radius selector
          DropdownButton<double>(
            value: radiusMiles,
            dropdownColor: Colors.grey[800],
            style: const TextStyle(color: Colors.white70, fontSize: 12),
            underline: const SizedBox(),
            items: [25.0, 50.0, 100.0, 150.0]
                .map((r) => DropdownMenuItem(
                      value: r,
                      child: Text('${r.round()} mi'),
                    ))
                .toList(),
            onChanged: (v) => onRadiusChanged(v ?? radiusMiles),
          ),
        ],
      ),
    );
  }
}

class _RepeaterTile extends StatelessWidget {
  final Repeater repeater;
  final int index;
  final bool isTuning;
  final bool radioConnected;
  final VoidCallback onTune;

  const _RepeaterTile({
    required this.repeater,
    required this.index,
    required this.isTuning,
    required this.radioConnected,
    required this.onTune,
  });

  @override
  Widget build(BuildContext context) {
    final isOnAir = repeater.isOnAir;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      color: Colors.grey[850],
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              repeater.displayFreq.split(' ')[0], // Just the number
              style: TextStyle(
                color: isOnAir ? Colors.green[400] : Colors.orange[400],
                fontWeight: FontWeight.bold,
                fontSize: 14,
                fontFamily: 'monospace',
              ),
            ),
            Text(
              'MHz',
              style: TextStyle(color: Colors.white54, fontSize: 10),
            ),
          ],
        ),
        title: Text(
          repeater.sysname,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${repeater.city ?? ''}, ${repeater.state ?? ''}  •  ${repeater.callsign ?? ''}',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
            Row(
              children: [
                _tag(repeater.displayTone, Colors.blue[700]!),
                const SizedBox(width: 4),
                if (repeater.displayDistance.isNotEmpty)
                  _tag(repeater.displayDistance, Colors.purple[700]!),
                const SizedBox(width: 4),
                if (!isOnAir) _tag('OFF AIR', Colors.red[800]!),
              ],
            ),
          ],
        ),
        trailing: isTuning
            ? const SizedBox(
                width: 24, height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : IconButton(
                icon: Icon(
                  Icons.radio,
                  color: radioConnected ? Colors.blue[400] : Colors.grey,
                ),
                tooltip: 'Tune radio to this repeater',
                onPressed: radioConnected ? onTune : null,
              ),
      ),
    );
  }

  Widget _tag(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: color.withOpacity(0.3),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: color, width: 0.5),
        ),
        child: Text(label, style: TextStyle(color: color, fontSize: 9)),
      );
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onRefresh;
  const _EmptyState({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cell_tower, size: 64, color: Colors.white30),
          const SizedBox(height: 16),
          const Text(
            'No repeaters found',
            style: TextStyle(color: Colors.white54, fontSize: 18),
          ),
          const SizedBox(height: 8),
          const Text(
            'Check your GPS fix and internet connection,\nor try increasing the search radius.',
            style: TextStyle(color: Colors.white38, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
