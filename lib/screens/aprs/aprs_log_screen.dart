// lib/screens/aprs/aprs_log_screen.dart
// Raw APRS packet log — color-coded by type, filterable, exportable

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../aprs/aprs_packet.dart';
import '../../aprs/aprs_service.dart';

class AprsLogScreen extends StatefulWidget {
  const AprsLogScreen({super.key});

  @override
  State<AprsLogScreen> createState() => _AprsLogScreenState();
}

class _AprsLogScreenState extends State<AprsLogScreen> {
  String _filter = '';
  bool _autoScroll = true;
  AprsPacketType? _typeFilter;
  final _scrollController = ScrollController();
  final _filterController = TextEditingController();

  static const _typeLabels = {
    AprsPacketType.positionNoTimestamp: 'Pos',
    AprsPacketType.positionWithTimestamp: 'Pos+T',
    AprsPacketType.message: 'Msg',
    AprsPacketType.status: 'Status',
    AprsPacketType.object: 'Object',
    AprsPacketType.telemetry: 'Telem',
    AprsPacketType.unknown: '???',
  };

  static const _typeColors = {
    AprsPacketType.positionNoTimestamp: Color(0xFF4CAF50),
    AprsPacketType.positionWithTimestamp: Color(0xFF8BC34A),
    AprsPacketType.message: Color(0xFF2196F3),
    AprsPacketType.status: Color(0xFF9C27B0),
    AprsPacketType.object: Color(0xFFFF9800),
    AprsPacketType.telemetry: Color(0xFF00BCD4),
    AprsPacketType.unknown: Color(0xFF9E9E9E),
  };

  @override
  void dispose() {
    _filterController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final aprs = context.watch<AprsService>();
    var packets = aprs.recentPackets.toList();

    // Apply type filter
    if (_typeFilter != null) {
      packets = packets.where((p) => p.type == _typeFilter).toList();
    }

    // Apply text filter
    if (_filter.isNotEmpty) {
      final q = _filter.toUpperCase();
      packets = packets
          .where((p) =>
              p.fullCallsign.contains(q) ||
              p.raw.toUpperCase().contains(q))
          .toList();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Packet Log (${packets.length})'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(
              _autoScroll ? Icons.vertical_align_bottom : Icons.pause,
              color: _autoScroll ? Colors.green[300] : Colors.white54,
            ),
            tooltip: _autoScroll ? 'Auto-scroll on' : 'Auto-scroll off',
            onPressed: () => setState(() => _autoScroll = !_autoScroll),
          ),
          IconButton(
            icon: const Icon(Icons.copy_outlined),
            tooltip: 'Copy all to clipboard',
            onPressed: packets.isEmpty
                ? null
                : () => _copyAll(packets),
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear log',
            onPressed: packets.isEmpty
                ? null
                : () => _confirmClear(context, aprs),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(90),
          child: Column(
            children: [
              // Text filter
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: TextField(
                  controller: _filterController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Filter packets…',
                    hintStyle: const TextStyle(color: Colors.white38),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.black26,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(Icons.search,
                        color: Colors.white38, size: 18),
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
              // Type chips
              SizedBox(
                height: 34,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                  children: [
                    _TypeChip(
                      label: 'All',
                      color: Colors.white54,
                      selected: _typeFilter == null,
                      onTap: () => setState(() => _typeFilter = null),
                    ),
                    ...AprsPacketType.values.map((t) => _TypeChip(
                          label: _typeLabels[t] ?? '?',
                          color: _typeColors[t] ?? Colors.grey,
                          selected: _typeFilter == t,
                          onTap: () => setState(() =>
                              _typeFilter = _typeFilter == t ? null : t),
                        )),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: packets.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.receipt_long_outlined,
                      size: 48, color: Colors.white24),
                  SizedBox(height: 12),
                  Text('No packets',
                      style: TextStyle(color: Colors.white38)),
                ],
              ),
            )
          : NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n is ScrollUpdateNotification) {
                  final atBottom = _scrollController.position.pixels >=
                      _scrollController.position.maxScrollExtent - 40;
                  if (!atBottom && _autoScroll) {
                    setState(() => _autoScroll = false);
                  }
                }
                return false;
              },
              child: ListView.builder(
                controller: _scrollController,
                itemCount: packets.length,
                itemBuilder: (_, i) => _PacketRow(packet: packets[i]),
              ),
            ),
    );
  }

  void _copyAll(List<AprsPacket> packets) {
    final text = packets.map((p) => p.raw).join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied ${packets.length} packets'),
        backgroundColor: Colors.green[700],
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _confirmClear(BuildContext context, AprsService aprs) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: const Text('Clear Log', style: TextStyle(color: Colors.white)),
        content: const Text('Remove all packets from the log?',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              aprs.clear();
              Navigator.pop(ctx);
            },
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

// ── Packet row ────────────────────────────────────────────────────────────────
class _PacketRow extends StatelessWidget {
  final AprsPacket packet;
  const _PacketRow({required this.packet});

  static const _typeColors = {
    AprsPacketType.positionNoTimestamp: Color(0xFF4CAF50),
    AprsPacketType.positionWithTimestamp: Color(0xFF8BC34A),
    AprsPacketType.message: Color(0xFF2196F3),
    AprsPacketType.status: Color(0xFF9C27B0),
    AprsPacketType.object: Color(0xFFFF9800),
    AprsPacketType.telemetry: Color(0xFF00BCD4),
    AprsPacketType.unknown: Color(0xFF9E9E9E),
  };

  static const _typeLabels = {
    AprsPacketType.positionNoTimestamp: 'POS',
    AprsPacketType.positionWithTimestamp: 'POS+T',
    AprsPacketType.message: 'MSG',
    AprsPacketType.status: 'STS',
    AprsPacketType.object: 'OBJ',
    AprsPacketType.telemetry: 'TEL',
    AprsPacketType.unknown: '???',
  };

  @override
  Widget build(BuildContext context) {
    final color = _typeColors[packet.type] ?? Colors.grey;
    final label = _typeLabels[packet.type] ?? '???';
    return InkWell(
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: packet.raw));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Packet copied'),
            duration: Duration(seconds: 1),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Type tag
            Container(
              width: 44,
              padding:
                  const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                border: Border.all(color: color.withOpacity(0.5)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                label,
                style: TextStyle(
                    color: color,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace'),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 8),
            // Raw text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    packet.fullCallsign,
                    style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace'),
                  ),
                  Text(
                    packet.raw.length > 200
                        ? '${packet.raw.substring(0, 200)}…'
                        : packet.raw,
                    style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 10,
                        fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
            // Timestamp
            Text(
              _formatTime(packet.receivedAt),
              style:
                  const TextStyle(color: Colors.white24, fontSize: 9),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }
}

// ── Type chip ─────────────────────────────────────────────────────────────────
class _TypeChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _TypeChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? color.withOpacity(0.25) : Colors.transparent,
            border: Border.all(
                color: selected ? color : Colors.white24),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? color : Colors.white54,
              fontSize: 11,
              fontWeight:
                  selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}
