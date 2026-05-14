import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';

import '../providers/ble_provider.dart';
import '../theme/app_theme.dart';
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
          // NUS filter toggle
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'NUS only',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              Switch(
                value: ble.filterNus,
                onChanged: (v) {
                  ble.setFilterNus(v);
                  ble.stopScan().then((_) => ble.startScan());
                },
                activeColor: AppColors.accent1,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
          // Scan / stop button
          StreamBuilder<bool>(
            stream: ble.isScanning,
            builder: (_, snap) {
              final scanning = snap.data ?? false;
              return IconButton(
                icon: Icon(scanning ? Icons.stop : Icons.refresh),
                tooltip: scanning ? 'Stop scan' : 'Rescan',
                onPressed: scanning ? ble.stopScan : ble.startScan,
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _ScanBar(ble: ble),
          if (ble.isConnected) _ConnectedBanner(ble: ble),
          // Saved device chip
          if (!ble.isConnected &&
              ble.savedDeviceId != null &&
              ble.savedDeviceName != null)
            _SavedDeviceChip(ble: ble),
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
                    final isConn =
                        ble.connectedDevice?.remoteId == r.device.remoteId;
                    return _DeviceTileWithRssi(
                      result: r,
                      isConnected: isConn,
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
    if (ble.isConnected) {
      if (widget.goToModeSelection) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ModeSelectionScreen()),
        );
      } else {
        final name = device.platformName.isNotEmpty
            ? device.platformName
            : device.remoteId.str;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connected to $name'),
            backgroundColor: AppColors.accent1,
          ),
        );
      }
    } else if (ble.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ble.errorMessage!),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }
}

// ── Scan progress bar ─────────────────────────────────────────────────────────
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

// ── Connected device banner ───────────────────────────────────────────────────
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
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            onPressed: ble.disconnect,
            child: const Text('Disconnect'),
          ),
          if (Navigator.canPop(context))
            TextButton(
              style:
                  TextButton.styleFrom(foregroundColor: AppColors.accent2),
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

// ── Saved-device reconnect chip ───────────────────────────────────────────────
class _SavedDeviceChip extends StatelessWidget {
  const _SavedDeviceChip({required this.ble});
  final BleProvider ble;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.surface,
      child: Row(
        children: [
          const Icon(Icons.history, size: 14, color: AppColors.accent2),
          const SizedBox(width: 8),
          Text(
            'Last device: ${ble.savedDeviceName}',
            style: const TextStyle(
                color: AppColors.accent2, fontSize: 12),
          ),
          const Spacer(),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: AppColors.accent2,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () async {
              await ble.clearSavedDevice();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Saved device cleared')),
                );
              }
            },
            child: const Text('Forget', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

// ── Device tile with RSSI ─────────────────────────────────────────────────────
class _DeviceTileWithRssi extends StatelessWidget {
  const _DeviceTileWithRssi({
    required this.result,
    required this.isConnected,
    required this.isConnecting,
    required this.onTap,
  });

  final ScanResult result;
  final bool       isConnected;
  final bool       isConnecting;
  final VoidCallback onTap;

  String _rssiLabel(int rssi) {
    if (rssi >= -60) return 'Excellent ($rssi dBm)';
    if (rssi >= -70) return 'Good ($rssi dBm)';
    if (rssi >= -80) return 'Fair ($rssi dBm)';
    return 'Weak ($rssi dBm)';
  }

  Color _rssiColor(int rssi) {
    if (rssi >= -60) return AppColors.accent1;
    if (rssi >= -70) return Colors.greenAccent;
    if (rssi >= -80) return Colors.orangeAccent;
    return Colors.redAccent;
  }

  @override
  Widget build(BuildContext context) {
    final device = result.device;
    final name   = device.platformName.isNotEmpty
        ? device.platformName
        : 'Unknown Device';
    final rssi   = result.rssi;

    return Card(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isConnected
              ? AppColors.accent1
              : AppColors.surface,
        ),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Icon(
          isConnected ? Icons.bluetooth_connected : Icons.bluetooth,
          color: isConnected ? AppColors.accent1 : AppColors.textSecondary,
        ),
        title: Text(
          name,
          style: TextStyle(
            color: isConnected ? AppColors.accent1 : Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              device.remoteId.str,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 11),
            ),
            if (rssi != 0)
              Text(
                _rssiLabel(rssi),
                style: TextStyle(
                    color: _rssiColor(rssi), fontSize: 11),
              ),
          ],
        ),
        trailing: isConnecting && !isConnected
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : isConnected
                ? const Icon(Icons.check_circle,
                    color: AppColors.accent1)
                : const Icon(Icons.chevron_right,
                    color: AppColors.textSecondary),
        onTap: isConnecting ? null : onTap,
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────
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
                scanning
                    ? 'Scanning for devices…'
                    : 'No devices found',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              if (!scanning && ble.filterNus)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'NUS filter is ON — only EBstat devices shown',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
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
