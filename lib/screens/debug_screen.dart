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

class _DebugScreenState extends State<DebugScreen> {
  final _lines        = <_LogLine>[];
  final _scrollCtrl   = ScrollController();
  final _inputCtrl    = TextEditingController();
  StreamSubscription<String>? _rawSub;
  bool _autoScroll    = true;

  static const _maxLines = 500;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ble = context.read<BleProvider>();
      _rawSub = ble.rawLines.listen(_onLine);
    });
    _scrollCtrl.addListener(_onScroll);
  }

  void _onLine(String line) {
    if (!mounted) return;
    setState(() {
      _lines.add(_LogLine(line, DateTime.now()));
      if (_lines.length > _maxLines) _lines.removeAt(0);
    });
    if (_autoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
        }
      });
    }
  }

  void _onScroll() {
    final atBottom = _scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 40;
    if (atBottom != _autoScroll) {
      setState(() => _autoScroll = atBottom);
    }
  }

  Future<void> _send(String cmd) async {
    final text = cmd.trim();
    if (text.isEmpty) return;

    final ble = context.read<BleProvider>();
    if (!ble.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Not connected'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    // STOP is special — always bypass the queue
    if (text.toUpperCase() == FwCmd.stop) {
      await ble.sendStop();
      _inputCtrl.clear();
      return;
    }

    _inputCtrl.clear();
    try {
      await ble.sendCommand(text);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _rawSub?.cancel();
    _scrollCtrl.dispose();
    _inputCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug Console'),
        actions: [
          if (!_autoScroll)
            IconButton(
              icon: const Icon(Icons.arrow_downward),
              tooltip: 'Scroll to bottom',
              onPressed: () {
                _scrollCtrl.animateTo(
                  _scrollCtrl.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear log',
            onPressed: () => setState(() => _lines.clear()),
          ),
        ],
      ),
      body: Column(
        children: [
          // Connection indicator
          _ConnectionBar(ble: ble),

          // Raw line log
          Expanded(
            child: _lines.isEmpty
                ? Center(
                    child: Text(
                      ble.isConnected
                          ? 'Waiting for data…'
                          : 'Connect a device to see raw output',
                      style: const TextStyle(
                          color: AppColors.textSecondary),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    itemCount: _lines.length,
                    itemBuilder: (_, i) => _LineWidget(line: _lines[i]),
                  ),
          ),

          // Shortcut buttons
          _ShortcutBar(onTap: _send, isConnected: ble.isConnected),

          // Input row
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: connected
          ? AppColors.accent1.withOpacity(0.15)
          : Colors.redAccent.withOpacity(0.1),
      child: Row(
        children: [
          Icon(
            connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
            size: 14,
            color: connected ? AppColors.accent1 : Colors.redAccent,
          ),
          const SizedBox(width: 8),
          Text(
            connected ? 'Connected — $name' : 'Not connected',
            style: TextStyle(
              fontSize: 12,
              color: connected ? AppColors.accent1 : Colors.redAccent,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shortcut button bar ───────────────────────────────────────────────────────
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
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.surface.withOpacity(0.5)),
        ),
      ),
      child: Row(
        children: [
          const Text(
            'Quick: ',
            style: TextStyle(
                color: AppColors.textSecondary, fontSize: 12),
          ),
          ..._cmds.map(
            (e) => Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ActionChip(
                label: Text(
                  e.label,
                  style: TextStyle(
                    color: isConnected ? e.color : AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
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
  const _InputRow({
    required this.controller,
    required this.enabled,
    required this.onSend,
  });
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
              style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 13),
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

// ── Log line widget ───────────────────────────────────────────────────────────
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
    final ts = '${line.time.hour.toString().padLeft(2, '0')}:'
        '${line.time.minute.toString().padLeft(2, '0')}:'
        '${line.time.second.toString().padLeft(2, '0')}.'
        '${(line.time.millisecond ~/ 10).toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ts,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              line.text,
              style: TextStyle(
                color: _colorFor(line.text),
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogLine {
  final String   text;
  final DateTime time;
  const _LogLine(this.text, this.time);
}
