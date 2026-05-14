import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/ble_provider.dart';
import '../theme/app_theme.dart';
import 'bluetooth_screen.dart';
import 'debug_screen.dart';
import 'mode_selection_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleProvider>();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
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
                'EbStat',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Electrochemistry Bluetooth Stat',
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
              const SizedBox(height: 16),
              if (ble.isConnected)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const BluetoothScreen(
                              goToModeSelection: true)),
                    ),
                    icon: const Icon(Icons.science_outlined),
                    label: const Text('Start Measurement'),
                  ),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ModeSelectionScreen()),
                  ),
                  icon: const Icon(Icons.play_circle_outline,
                      color: AppColors.textSecondary),
                  label: const Text(
                    'Demo Mode (no device)',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
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
