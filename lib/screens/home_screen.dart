import 'dart:io' as dart_io;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/voltammetry_mode.dart';
import '../providers/ble_provider.dart';
import '../providers/measurement_provider.dart';
import '../services/csv_import_service.dart';
import '../theme/app_theme.dart';
import 'analysis_screen.dart';
import 'bluetooth_screen.dart';
import 'debug_screen.dart';
import 'history_screen.dart';
import 'mode_selection_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _importing = false;

  // ── Import ────────────────────────────────────────────────────────────────

  Future<void> _importData() async {
    setState(() => _importing = true);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true, // ensure bytes are always loaded, regardless of platform
      );
      if (result == null || result.files.isEmpty || !mounted) return;

      final file = result.files.single;
      final Uint8List bytes;
      if (file.bytes != null) {
        bytes = file.bytes!;
      } else if (file.path != null) {
        bytes = await _HomeScreenState._readBytes(file.path!);
      } else {
        _showError('Could not read file content.');
        return;
      }

      final project = CsvImportService.importFromBytes(bytes);
      final mode = VoltammetryMode.values
          .where((m) => m.abbreviation == project.modeName)
          .firstOrNull;
      if (mode == null) {
        _showError('Unsupported technique: ${project.modeName}');
        return;
      }

      if (!mounted) return;
      context.read<MeasurementProvider>().importProject(project, mode);

      final count = project.measurements.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Imported $count measurement${count == 1 ? '' : 's'}'),
        ),
      );
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AnalysisScreen()),
      );
    } on CsvImportException catch (e) {
      if (mounted) _showError(e.message);
    } catch (e) {
      if (mounted) _showError('Import failed: $e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  static Future<Uint8List> _readBytes(String path) async {
    final dart_io.File file = dart_io.File(path);
    return file.readAsBytes();
  }

  void _showError(String message) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text('Import Error',
            style: TextStyle(color: Colors.white)),
        content: Text(message,
            style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleProvider>();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.history,
                color: AppColors.textSecondary),
            tooltip: 'Saved Transcripts',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HistoryScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.terminal,
                color: AppColors.textSecondary),
            tooltip: 'Debug Console',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DebugScreen()),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 2),
              _Logo(),
              const SizedBox(height: 12),
              const Text(
                'EBstat',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Malaria Electrochemistry Diagnostic Kit',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(flex: 2),
              _StatusBadge(ble: ble),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const BluetoothScreen()),
                  ),
                  icon: const Icon(Icons.bluetooth_searching),
                  label: Text(
                    ble.isConnected ? 'Manage Connection' : 'Scan for Device',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _importing ? null : _importData,
                  icon: _importing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.file_open),
                  label: const Text('Import Data'),
                ),
              ),
              const SizedBox(height: 16),
              if (ble.isConnected)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ModeSelectionScreen()),
                    ),
                    icon: const Icon(Icons.science_outlined),
                    label: const Text('Start Measurement'),
                  ),
                ),
              const Spacer(flex: 1),
              const Text(
                'XIAO nRF52840 · BLE 5.0',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: AppColors.surface,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.accent1, width: 2),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent1.withOpacity(0.3),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: const Icon(
        Icons.show_chart,
        color: AppColors.accent1,
        size: 52,
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.ble});
  final BleProvider ble;

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = switch (ble.status) {
      BleStatus.connected => (
          AppColors.accent1,
          Icons.bluetooth_connected,
          'Connected — ${ble.connectedDevice?.platformName ?? "Device"}'
        ),
      BleStatus.connecting => (
          AppColors.accent2,
          Icons.bluetooth_searching,
          'Connecting…'
        ),
      BleStatus.scanning => (
          AppColors.accent2,
          Icons.radar,
          'Scanning…'
        ),
      BleStatus.error => (
          Colors.redAccent,
          Icons.error_outline,
          ble.errorMessage ?? 'Error'
        ),
      _ => (
          AppColors.textSecondary,
          Icons.bluetooth_disabled,
          'Not connected'
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: TextStyle(color: color, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
