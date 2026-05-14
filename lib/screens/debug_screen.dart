import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ble/protocol.dart';
import '../providers/ble_provider.dart';
import '../theme/app_theme.dart';

class DebugScreen extends StatefulWidget {
  const DebugScreen({super.key});

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen>
    with SingleTickerProviderStateMixin {
  // ── Raw log ───────────────────────────────────────────────────────────────
  final _lines      = <_LogLine>[];
  final _scrollCtrl = ScrollController();
  final _inputCtrl  = TextEditingController();
  StreamSubscription<String>? _rawSub;
  bool _autoScroll  = true;

  // ── Last result ───────────────────────────────────────────────────────────
  RunResult? _lastResult;

  // ── Tabs ──────────────────────────────────────────────────────────────────
  late final TabController _tabCtrl;

  static const _maxLines = 500;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rawSub = context.read<BleProvider>().rawLines.listen(_onLine);
    });
    _scrollCtrl.addListener(_onScroll);
  }

  void _onLine(String line) {
    if (!mounted) return;
    setState(() {
      _lines.add(_LogLine(line, DateTime.now()));
      if (_lines.length > _maxLines) _lines.removeAt(0);
    });
    if (_autoScroll && _tabCtrl.index == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
        }
      });
    }
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final atBottom = _scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 40;
    if (atBottom != _autoScroll) setState(() => _autoScroll = atBottom);
  }

  Future<void> _send(String cmd) async {
    final text = cmd.trim();
    if (text.isEmpty) return;

    final ble = context.read<BleProvider>();
    if (!ble.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Not connected'),
            backgroundColor: Colors.redAccent),
      );
      return;
    }

    if (text.toUpperCase() == FwCmd.stop) {
      await ble.sendStop();
      _inputCtrl.clear();
      return;
    }

    _inputCtrl.clear();
    try {
      final result = await ble.sendCommand(text);
      if (mounted) setState(() => _lastResult = result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  void dispose() {
    _rawSub?.cancel();
    _scrollCtrl.dispose();
    _inputCtrl.dispose();
    _tabCtrl.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug Console'),
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: [
            const Tab(text: 'Raw Log'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Last Result'),
                  if (_lastResult != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: _lastResult!.aborted
                            ? Colors.redAccent
                            : AppColors.accent1,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _lastResult!.aborted ? 'ABORTED' : 'DONE',
                        style: const TextStyle(
                            fontSize: 9, color: Colors.white),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (_tabCtrl.index == 0) ...[
            if (!_autoScroll)
              IconButton(
                icon: const Icon(Icons.arrow_downward),
                tooltip: 'Scroll to bottom',
                onPressed: () => _scrollCtrl.animateTo(
                  _scrollCtrl.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                ),
              ),
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Clear log',
              onPressed: () => setState(() => _lines.clear()),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          _ConnectionBar(ble: ble),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _RawLogTab(
                  lines: _lines,
                  scrollCtrl: _scrollCtrl,
                  ble: ble,
                ),
                _LastResultTab(result: _lastResult),
              ],
            ),
          ),
          _ShortcutBar(onTap: _send, isConnected: ble.isConnected),
          _InputRow(
            controller: _inputCtrl,
            enabled: ble.isConnected,
            onSend: _send,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Raw log tab ───────────────────────────────────────────────────────────────
class _RawLogTab extends StatelessWidget {
  const _RawLogTab({
    required this.lines,
    required this.scrollCtrl,
    required this.ble,
  });
  final List<_LogLine> lines;
  final ScrollController scrollCtrl;
  final BleProvider ble;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) {
      return Center(
        child: Text(
          ble.isConnected
              ? 'Waiting for data…'
              : 'Connect a device to see raw output',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    return ListView.builder(
      controller: scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: lines.length,
      itemBuilder: (_, i) => _LineWidget(line: lines[i]),
    );
  }
}

// ── Last result tab ───────────────────────────────────────────────────────────
class _LastResultTab extends StatelessWidget {
  const _LastResultTab({required this.result});
  final RunResult? result;

  @override
  Widget build(BuildContext context) {
    if (result == null) {
      return const Center(
        child: Text(
          'Send a command to see the parsed result here.',
          style: TextStyle(color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
      );
    }

    final r = result!;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Status chip
        Row(
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: r.aborted
                    ? Colors.redAccent.withOpacity(0.2)
                    : AppColors.accent1.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: r.aborted ? Colors.redAccent : AppColors.accent1,
                ),
              ),
              child: Text(
                r.aborted ? '⚠ ABORTED' : '✓ DONE',
                style: TextStyle(
                  color: r.aborted ? Colors.redAccent : AppColors.accent1,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${r.rawRows.length} data row${r.rawRows.length != 1 ? "s" : ""}',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),

        // Metadata
        if (r.metadata.isNotEmpty) ...[
          const SizedBox(height: 16),
          const _SectionHeader('Metadata'),
          const SizedBox(height: 8),
          ...r.metadata.entries.map(
            (e) => _KvRow(k: e.key, v: e.value),
          ),
        ],

        // CSV data
        if (r.header.isNotEmpty) ...[
          const SizedBox(height: 16),
          const _SectionHeader('CSV Data'),
          const SizedBox(height: 8),
          _CsvTable(header: r.header, rows: r.rawRows),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      );
}

class _KvRow extends StatelessWidget {
  const _KvRow({required this.k, required this.v});
  final String k, v;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(k,
                  style: const TextStyle(
                      color: AppColors.accent2,
                      fontSize: 12,
                      fontFamily: 'monospace')),
            ),
            Expanded(
              flex: 3,
              child: Text(v,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontFamily: 'monospace')),
            ),
          ],
        ),
      );
}

class _CsvTable extends StatelessWidget {
  const _CsvTable({required this.header, required this.rows});
  final List<String> header;
  final List<String> rows;

  static const _maxRows = 100;

  @override
  Widget build(BuildContext context) {
    final displayRows = rows.length > _maxRows
        ? rows.sublist(0, _maxRows)
        : rows;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: header
                .map((h) => Expanded(
                      child: Text(h,
                          style: const TextStyle(
                            color: AppColors.accent1,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          )),
                    ))
                .toList(),
          ),
        ),
        // Data rows
        ...displayRows.map((row) {
          final cols = row.split(',');
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(
                      color: AppColors.divider.withOpacity(0.3))),
            ),
            child: Row(
              children: List.generate(header.length, (i) {
                final val = i < cols.length ? cols[i].trim() : '';
                return Expanded(
                  child: Text(val,
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontFamily: 'monospace')),
                );
              }),
            ),
          );
        }),
        if (rows.length > _maxRows)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '… ${rows.length - _maxRows} more rows not shown',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 11),
            ),
          ),
      ],
    );
  }
}

// ── Connection bar ────────────────────────────────────────────────────────────
class _ConnectionBar extends StatelessWidget {
  const _ConnectionBar({required this.ble});
  final BleProvider ble;

  @override
  Widget build(BuildContext context) {
    final connected = ble.isConnected;
    final name = connected
        ? (ble.connectedDevice?.platformName.isNotEmpty == true
            ? ble.connectedDevice!.platformName
            : ble.connectedDevice?.remoteId.str ?? 'Device')
        : null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      color: connected
          ? AppColors.accent1.withOpacity(0.12)
          : Colors.redAccent.withOpacity(0.1),
      child: Row(
        children: [
          Icon(
            connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
            size: 13,
            color: connected ? AppColors.accent1 : Colors.redAccent,
          ),
          const SizedBox(width: 8),
          Text(
            connected ? 'Connected — $name' : 'Not connected',
            style: TextStyle(
                fontSize: 11,
                color: connected ? AppColors.accent1 : Colors.redAccent),
          ),
        ],
      ),
    );
  }
}

// ── Shortcut bar ──────────────────────────────────────────────────────────────
class _ShortcutBar extends StatelessWidget {
  const _ShortcutBar({required this.onTap, required this.isConnected});
  final Future<void> Function(String) onTap;
  final bool isConnected;

  static const _cmds = [
    (label: 'HELP',   cmd: FwCmd.help,   color: AppColors.accent2),
    (label: 'STATUS', cmd: FwCmd.status, color: AppColors.accent2),
    (label: 'CAPS',   cmd: FwCmd.caps,   color: AppColors.accent2),
    (label: 'STOP',   cmd: FwCmd.stop,   color: Colors.redAccent),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: AppColors.surface,
      child: Row(
        children: [
          const Text('Quick: ',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ..._cmds.map(
            (e) => Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ActionChip(
                label: Text(e.label,
                    style: TextStyle(
                      color: isConnected
                          ? e.color
                          : AppColors.textSecondary,
                      fontSize: 12,
                    )),
                backgroundColor: AppColors.primary,
                side: BorderSide(
                  color: isConnected
                      ? e.color.withOpacity(0.5)
                      : AppColors.textSecondary.withOpacity(0.3),
                ),
                onPressed: isConnected ? () => onTap(e.cmd) : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Input row ─────────────────────────────────────────────────────────────────
class _InputRow extends StatelessWidget {
  const _InputRow(
      {required this.controller,
      required this.enabled,
      required this.onSend});
  final TextEditingController controller;
  final bool enabled;
  final Future<void> Function(String) onSend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              style:
                  const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: InputDecoration(
                hintText: enabled
                    ? 'Type command and press Send…'
                    : 'Not connected',
                hintStyle: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
                filled: true,
                fillColor: AppColors.surface,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: enabled ? onSend : null,
              textInputAction: TextInputAction.send,
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: enabled ? () => onSend(controller.text) : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent1,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }
}

// ── Log line ──────────────────────────────────────────────────────────────────
class _LineWidget extends StatelessWidget {
  const _LineWidget({required this.line});
  final _LogLine line;

  Color _colorFor(String text) {
    if (text == FwTerminator.done)    return AppColors.accent1;
    if (text == FwTerminator.aborted) return Colors.redAccent;
    if (text.startsWith('#'))         return AppColors.accent2;
    return Colors.white70;
  }

  @override
  Widget build(BuildContext context) {
    final t = line.time;
    final ts = '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}.'
        '${(t.millisecond ~/ 10).toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(ts,
              style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                  fontFamily: 'monospace')),
          const SizedBox(width: 8),
          Expanded(
            child: Text(line.text,
                style: TextStyle(
                    color: _colorFor(line.text),
                    fontSize: 12,
                    fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }
}

class _LogLine {
  final String text;
  final DateTime time;
  const _LogLine(this.text, this.time);
}
