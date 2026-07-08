// lib/screens/weather/spotter_list_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/spotter_network_service.dart';

class SpotterListScreen extends StatelessWidget {
  const SpotterListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<SpotterNetworkService>();
    return Scaffold(
      appBar: AppBar(
        title: Text('Storm Spotters (${svc.spotters.length})'),
        backgroundColor: Colors.orange[900],
        foregroundColor: Colors.white,
        actions: [
          if (svc.isLoading)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: svc.fetch,
              tooltip: 'Refresh',
            ),
        ],
      ),
      body: svc.spotters.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person_pin_circle_outlined,
                      size: 48, color: Colors.white38),
                  const SizedBox(height: 8),
                  Text(
                    svc.isLoading
                        ? 'Loading spotters…'
                        : svc.error ?? 'No spotters in current feed',
                    style: const TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: svc.spotters.length,
              itemBuilder: (_, i) {
                final s = svc.spotters[i];
                return ListTile(
                  leading: const Icon(Icons.person_pin_circle,
                      color: Colors.orange, size: 28),
                  title: Text(
                    s.name,
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${s.lat.toStringAsFixed(4)}, ${s.lon.toStringAsFixed(4)}'
                        '${s.speedMph != null ? ' · ${s.speedMph!.toStringAsFixed(0)} mph' : ''}',
                        style:
                            const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      if (s.note != null && s.note!.isNotEmpty)
                        Text(
                          s.note!,
                          style: const TextStyle(
                              color: Colors.orange, fontSize: 11),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                  isThreeLine: s.note != null && s.note!.isNotEmpty,
                  trailing: s.timestamp != null
                      ? Text(
                          s.timestamp!,
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 10),
                        )
                      : null,
                );
              },
            ),
    );
  }
}
