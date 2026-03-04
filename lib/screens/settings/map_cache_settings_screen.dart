// lib/screens/settings/map_cache_settings_screen.dart
// Map tile cache settings — view size, clear cache by source

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../services/map_tile_service.dart';

class MapCacheSettingsScreen extends StatefulWidget {
  const MapCacheSettingsScreen({super.key});

  @override
  State<MapCacheSettingsScreen> createState() =>
      _MapCacheSettingsScreenState();
}

class _MapCacheSettingsScreenState extends State<MapCacheSettingsScreen> {
  bool _loading = true;
  Map<MapTileSource, _CacheInfo> _cacheInfo = {};

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() => _loading = true);
    final dir = await getApplicationDocumentsDirectory();
    final results = <MapTileSource, _CacheInfo>{};

    for (final source in MapTileSource.values) {
      final cacheDir =
          Directory(p.join(dir.path, 'tile_cache', source.name));
      if (!cacheDir.existsSync()) {
        results[source] = const _CacheInfo(tileCount: 0, sizeBytes: 0);
        continue;
      }
      int count = 0;
      int size = 0;
      await for (final entity in cacheDir.list(recursive: true)) {
        if (entity is File) {
          count++;
          size += await entity.length();
        }
      }
      results[source] = _CacheInfo(tileCount: count, sizeBytes: size);
    }

    if (!mounted) return;
    setState(() {
      _cacheInfo = results;
      _loading = false;
    });
  }

  Future<void> _clearSource(MapTileSource source) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: Text('Clear ${MapTileService.label(source)} cache',
            style: const TextStyle(color: Colors.white)),
        content: Text(
          'Delete all locally cached ${MapTileService.label(source)} tiles?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final dir = await getApplicationDocumentsDirectory();
    final cacheDir =
        Directory(p.join(dir.path, 'tile_cache', source.name));
    if (cacheDir.existsSync()) {
      await cacheDir.delete(recursive: true);
    }
    await _scan();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${MapTileService.label(source)} cache cleared'),
          backgroundColor: Colors.green[700],
        ),
      );
    }
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: const Text('Clear All Caches',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'Delete all locally cached map tiles? '
          'Tiles will re-download on next use.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear All',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory(p.join(dir.path, 'tile_cache'));
    if (cacheDir.existsSync()) {
      await cacheDir.delete(recursive: true);
    }
    await _scan();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All map caches cleared'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  int get _totalTiles =>
      _cacheInfo.values.fold(0, (s, c) => s + c.tileCount);
  int get _totalBytes =>
      _cacheInfo.values.fold(0, (s, c) => s + c.sizeBytes);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Map Cache'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _scan,
            tooltip: 'Rescan',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                // ── Summary ───────────────────────────────────────────────
                _SectionHeader('Total Cache'),
                ListTile(
                  leading:
                      const Icon(Icons.storage_outlined, color: Colors.blue),
                  title: const Text('All Sources',
                      style: TextStyle(color: Colors.white)),
                  subtitle: Text(
                    '$_totalTiles tiles · ${_formatBytes(_totalBytes)}',
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  trailing: _totalTiles > 0
                      ? TextButton(
                          onPressed: _clearAll,
                          child: const Text('Clear All',
                              style: TextStyle(color: Colors.red)),
                        )
                      : null,
                ),

                // ── Per-source ────────────────────────────────────────────
                _SectionHeader('By Source'),
                ...MapTileSource.values.map((source) {
                  final info = _cacheInfo[source] ??
                      const _CacheInfo(tileCount: 0, sizeBytes: 0);
                  return _SourceTile(
                    source: source,
                    info: info,
                    onClear: info.tileCount > 0
                        ? () => _clearSource(source)
                        : null,
                  );
                }),

                // ── Info ──────────────────────────────────────────────────
                _SectionHeader('About Map Cache'),
                const Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Text(
                    'Tiles are cached locally when you browse the map or use '
                    '"Cache This Area" in the map options. '
                    'Cached tiles are used offline when no internet is '
                    'available.\n\n'
                    'Tile data is copyright OpenStreetMap contributors, '
                    'OpenTopoMap, and ESRI where applicable.',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),

                const SizedBox(height: 80),
              ],
            ),
    );
  }
}

// ── Source tile ───────────────────────────────────────────────────────────────
class _SourceTile extends StatelessWidget {
  final MapTileSource source;
  final _CacheInfo info;
  final VoidCallback? onClear;

  const _SourceTile({
    required this.source,
    required this.info,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Text(
        MapTileService.icon(source),
        style: const TextStyle(fontSize: 22),
      ),
      title: Text(MapTileService.label(source),
          style: const TextStyle(color: Colors.white)),
      subtitle: Text(
        info.tileCount == 0
            ? 'No tiles cached'
            : '${info.tileCount} tiles · ${_formatBytes(info.sizeBytes)}',
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      ),
      trailing: onClear != null
          ? TextButton(
              onPressed: onClear,
              child: const Text('Clear',
                  style: TextStyle(color: Colors.red)),
            )
          : null,
    );
  }
}

// ── Cache info ────────────────────────────────────────────────────────────────
class _CacheInfo {
  final int tileCount;
  final int sizeBytes;
  const _CacheInfo({required this.tileCount, required this.sizeBytes});
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

// ── Format bytes helper ───────────────────────────────────────────────────────
String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}
