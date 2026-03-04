// lib/screens/settings/tracks_screen.dart
// Lists saved GPX track files with share/delete options

import 'dart:io';
import 'package:flutter/material.dart';
import '../../services/track_service.dart';

class TracksScreen extends StatefulWidget {
  const TracksScreen({super.key});

  @override
  State<TracksScreen> createState() => _TracksScreenState();
}

class _TracksScreenState extends State<TracksScreen> {
  List<File> _tracks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTracks();
  }

  Future<void> _loadTracks() async {
    final tracks = await TrackService.listTracks();
    setState(() {
      _tracks  = tracks;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Tracks'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _tracks.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.route, size: 48, color: Colors.white24),
                      SizedBox(height: 8),
                      Text('No tracks recorded yet',
                          style: TextStyle(color: Colors.white38)),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: _tracks.length,
                  separatorBuilder: (_, __) =>
                      const Divider(color: Colors.white12, height: 1),
                  itemBuilder: (ctx, i) {
                    final track = _tracks[i];
                    final name  = track.path.split('/').last;
                    final size  = (track.lengthSync() / 1024).toStringAsFixed(1);

                    return ListTile(
                      leading: const Icon(Icons.route, color: Colors.green),
                      title: Text(name,
                          style: const TextStyle(color: Colors.white, fontSize: 13)),
                      subtitle: Text('$size KB',
                          style: const TextStyle(color: Colors.white54, fontSize: 11)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.share, color: Colors.white54, size: 20),
                            onPressed: () => _share(track),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                            onPressed: () => _delete(track),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }

  Future<void> _share(File track) async {
    // Show a dialog with the file path — deep share requires share_plus pkg
    final name = track.path.split('/').last;
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: Text(name, style: const TextStyle(color: Colors.white, fontSize: 14)),
        content: SelectableText(track.path,
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(File track) async {
    final name = track.path.split('/').last;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: const Text('Delete Track?', style: TextStyle(color: Colors.white)),
        content: Text('Delete $name?',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await track.delete();
      _loadTracks();
    }
  }
}
