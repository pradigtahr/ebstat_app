import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';

import '../providers/ble_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/device_tile.dart';
import 'mode_selection_screen.dart';

class BluetoothScreen extends StatefulWidget {
  const BluetoothScreen({super.key, this.goToModeSelection = false});
  final bool goToModeSelection;

  @override
  State<BluetoothScreen> createState() => _BluetoothScreenState();
}

class _BluetoothScreenState extends State<BluetoothScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BleProvider>().startScan();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bluetooth Devices'),
        actions: [
          StreamBuilder<bool>(
            stream: ble.isScanning,
            builder: (_, snap) {
              final scanning = snap.data ?? false;
              return IconButton(
                icon: Icon(scanning ? Icons.stop : Icons.refresh),
                tooltip: scanning ? 'Stop scan' : 'Rescan',
                onPressed: scanning
                    ? ble.stopScan
                    : ble.startScan,
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _ScanBar(ble: ble),
          if (ble.isConnected) _ConnectedBanner(ble: ble),
          Expanded(
            child: StreamBuilder<List<ScanResult>>(
              stream: ble.scanResults,
              builder: (_, snap) {
                final results = snap.data ?? [];
                if (results.isEmpty) {
                  return _EmptyState(ble: ble);
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  itemCount: results.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final r = results[i];
                    final isConnected =
                        ble.connectedDevice?.remoteId == r.device.remoteId;
                    return DeviceTile(
                      result: r,
                      isConnected: isConnected,
                      isConnecting: ble.status == BleStatus.connecting,
                      onTap: () => _onDeviceTap(context, ble, r.device),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onDeviceTap(
      BuildContext context, BleProvider ble, BluetoothDevice device) async {
    if (ble.isConnected &&
        ble.connectedDevice?.remoteId == device.remoteId) {
      await ble.disconnect();
      return;
    }
    await ble.connect(device);
    if (!mounted) return;
    if (ble.isConnected && widget.goToModeSelection) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ModeSelectionScreen()),
      );
    } else if (ble.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Connected to ${device.platformName.isNotEmpty ? device.platformName : device.remoteId}'),
          backgroundColor: AppColors.accent1,
        ),
      );
    }
  }
}

class _ScanBar extends StatelessWidget {
  const _ScanBar({required this.ble});
  final BleProvider ble;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: ble.isScanning,
      builder: (_, snap) {
        final scanning = snap.data ?? false;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          height: scanning ? 4 : 0,
          child: LinearProgressIndicator(
            backgroundColor: AppColors.surface,
            valueColor:
                const AlwaysStoppedAnimation<Color>(AppColors.accent1),
          ),
        );
      },
    );
  }
}

class _ConnectedBanner extends StatelessWidget {
  const _ConnectedBanner({required this.ble});
  final BleProvider ble;

  @override
  Widget build(BuildContext context) {
    final name = ble.connectedDevice?.platformName;
    final label = (name != null && name.isNotEmpty)
        ? name
        : ble.connectedDevice?.remoteId.str ?? 'Device';
    return Container(
      width: double.infinity,
      color: AppColors.accent1.withOpacity(0.15),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.bluetooth_connected,
              color: AppColors.accent1, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Connected to $label',
              style: const TextStyle(color: AppColors.accent1, fontSize: 13),
            ),
          ),
          TextButton(
            style:
                TextButton.styleFrom(foregroundColor: Colors.redAccent),
            onPressed: ble.disconnect,
            child: const Text('Disconnect'),
          ),
          if (Navigator.canPop(context))
            TextButton(
              style: TextButton.styleFrom(
                  foregroundColor: AppColors.accent2),
              onPressed: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (_) => const ModeSelectionScreen()),
              ),
              child: const Text('Continue →'),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.ble});
  final BleProvider ble;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: ble.isScanning,
      builder: (_, snap) {
        final scanning = snap.data ?? false;
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                scanning ? Icons.radar : Icons.bluetooth_disabled,
                size: 64,
                color: AppColors.textSecondary,
              ),
              const SizedBox(height: 16),
              Text(
                scanning ? 'Scanning for devices…' : 'No devices found',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              if (!scanning) ...[
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: ble.startScan,
                  child: const Text('Scan Again'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
