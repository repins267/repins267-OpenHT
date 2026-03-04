// lib/screens/weather/submit_report_screen.dart
// Storm spotter report submission form (Spotter Network)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/gps_service.dart';

class SubmitReportScreen extends StatefulWidget {
  const SubmitReportScreen({super.key});

  @override
  State<SubmitReportScreen> createState() => _SubmitReportScreenState();
}

class _SubmitReportScreenState extends State<SubmitReportScreen> {
  String _reportType = 'Tornado';
  String _size = '';
  String _notes = '';
  bool _isSubmitting = false;

  static const List<String> _reportTypes = [
    'Tornado',
    'Funnel Cloud',
    'Large Hail',
    'Damaging Wind',
    'Flash Flood',
    'Heavy Rain',
    'Other',
  ];

  @override
  Widget build(BuildContext context) {
    final gps = context.watch<GpsService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Submit Spotter Report'),
        backgroundColor: Colors.orange[900],
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── GPS Location ────────────────────────────
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[850],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    gps.hasPosition ? Icons.gps_fixed : Icons.gps_off,
                    color: gps.hasPosition ? Colors.green : Colors.red,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    gps.hasPosition
                        ? gps.displayPosition
                        : 'No GPS fix — position required',
                    style: TextStyle(
                      color: gps.hasPosition ? Colors.white70 : Colors.red,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ─── Report Type ─────────────────────────────
            const Text('Report Type', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _reportType,
              dropdownColor: Colors.grey[850],
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.grey[850],
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              items: _reportTypes
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) => setState(() => _reportType = v ?? _reportType),
            ),
            const SizedBox(height: 16),

            // ─── Size/Intensity ───────────────────────────
            const Text('Size / Intensity', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _HintField(
              hint: _sizeHint(),
              onChanged: (v) => _size = v,
            ),
            const SizedBox(height: 16),

            // ─── Notes ───────────────────────────────────
            const Text('Notes / Description', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextFormField(
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Additional details…',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.grey[850],
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              style: const TextStyle(color: Colors.white),
              onChanged: (v) => _notes = v,
            ),
            const SizedBox(height: 24),

            // ─── Submit ───────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange[800],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: (!gps.hasPosition || _isSubmitting)
                    ? null
                    : () => _submit(gps),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Submit Report', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _sizeHint() {
    switch (_reportType) {
      case 'Large Hail':     return 'Diameter in inches (e.g. 1.75)';
      case 'Damaging Wind':  return 'Estimated speed in mph (e.g. 80)';
      case 'Tornado':        return 'EF scale estimate (e.g. EF1) or "Unknown"';
      default:               return 'Intensity or size estimate';
    }
  }

  Future<void> _submit(GpsService gps) async {
    setState(() => _isSubmitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final appId = prefs.getString('spotter_app_id') ?? '4f2e07d475ae4';

      // Build the POST body for Spotter Network
      final body = {
        'app_id': appId,
        'type': _reportType,
        'size': _size,
        'notes': _notes,
        'lat': gps.latitude!.toStringAsFixed(6),
        'lon': gps.longitude!.toStringAsFixed(6),
      };

      final response = await http
          .post(
            Uri.parse('https://www.spotternetwork.org/reports/add'),
            headers: {
              'User-Agent': 'OpenHT/0.1 (github.com/repins267/OpenHT)',
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: body.entries
                .map((e) =>
                    '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
                .join('&'),
          )
          .timeout(const Duration(seconds: 15));

      if (mounted) {
        if (response.statusCode == 200 || response.statusCode == 201) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Report Submitted'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Submission failed: HTTP ${response.statusCode}\n${response.body}',
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 6),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Network error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}

class _HintField extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;

  const _HintField({required this.hint, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: Colors.grey[850],
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      style: const TextStyle(color: Colors.white),
      onChanged: onChanged,
    );
  }
}
