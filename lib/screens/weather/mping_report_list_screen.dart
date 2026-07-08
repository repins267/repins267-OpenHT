// lib/screens/weather/mping_report_list_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/mping_report.dart';
import '../../services/mping_service.dart';

class MpingReportListScreen extends StatelessWidget {
  const MpingReportListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final mping = context.watch<MpingService>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('mPING Reports'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          if (mping.isLoading)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              ),
            ),
        ],
      ),
      body: mping.reports.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🌦️', style: TextStyle(fontSize: 40)),
                  const SizedBox(height: 8),
                  Text(
                    mping.isLoading
                        ? 'Loading reports…'
                        : mping.error ?? 'No reports in the last hour (75 mi)',
                    style: const TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: mping.reports.length,
              itemBuilder: (_, i) => _ReportTile(report: mping.reports[i]),
            ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  final MpingReport report;
  const _ReportTile({required this.report});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: Text(report.emoji, style: const TextStyle(fontSize: 22)),
      title: Text(
        report.category,
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
      subtitle: Text(
        report.timeAgo,
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (report.description.isNotEmpty)
                Text(
                  report.description,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              const SizedBox(height: 4),
              Text(
                '${report.lat.toStringAsFixed(4)}, ${report.lon.toStringAsFixed(4)}',
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
              Text(
                report.timestamp.toLocal().toString().substring(0, 16),
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
