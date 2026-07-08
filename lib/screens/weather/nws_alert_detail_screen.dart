// lib/screens/weather/nws_alert_detail_screen.dart
import 'package:flutter/material.dart';
import '../../models/nws_alert.dart';

class NwsAlertDetailScreen extends StatelessWidget {
  final NwsAlert alert;
  const NwsAlertDetailScreen({super.key, required this.alert});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(alert.typeLabel),
        backgroundColor: alert.severityColor.withOpacity(0.8),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Badge + expires countdown
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: alert.severityColor,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  alert.typeLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(alert.severityIcon, color: alert.severityColor, size: 20),
              const Spacer(),
              if (alert.expiresCountdown.isNotEmpty)
                Text(
                  alert.expiresCountdown,
                  style: TextStyle(
                    color: alert.severityColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Event title
          Text(
            alert.event,
            style: TextStyle(
              color: alert.severityColor,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),

          // Headline
          if (alert.headline != null && alert.headline!.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: alert.severityColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: alert.severityColor.withOpacity(0.4),
                ),
              ),
              child: Text(
                alert.headline!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Affected area
          if (alert.areaDesc != null && alert.areaDesc!.isNotEmpty) ...[
            _Section(title: 'Affected Area', icon: Icons.place_outlined),
            const SizedBox(height: 4),
            Text(
              alert.areaDesc!,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
          ],

          // Description
          if (alert.description != null && alert.description!.isNotEmpty) ...[
            _Section(title: 'Description', icon: Icons.description_outlined),
            const SizedBox(height: 4),
            Text(
              alert.description!,
              style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 16),
          ],

          // Instructions
          if (alert.instruction != null && alert.instruction!.isNotEmpty) ...[
            _Section(title: 'Instructions', icon: Icons.safety_check_outlined),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Text(
                alert.instruction!,
                style: const TextStyle(
                  color: Colors.orange,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Expires
          if (alert.expires != null) ...[
            _Section(title: 'Expires', icon: Icons.schedule_outlined),
            const SizedBox(height: 4),
            Text(
              alert.expires!,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],

          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  const _Section({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.blue[400]),
        const SizedBox(width: 6),
        Text(
          title.toUpperCase(),
          style: TextStyle(
            color: Colors.blue[400],
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}
