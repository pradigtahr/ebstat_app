import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../theme/app_theme.dart';

class DeviceTile extends StatelessWidget {
  const DeviceTile({
    super.key,
    required this.result,
    required this.isConnected,
    required this.isConnecting,
    required this.onTap,
  });

  final ScanResult result;
  final bool isConnected;
  final bool isConnecting;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = result.device.platformName.isNotEmpty
        ? result.device.platformName
        : result.advertisementData.advName.isNotEmpty
            ? result.advertisementData.advName
            : 'Unknown Device';

    final rssi = result.rssi;
    final rssiIcon = rssi > -60
        ? Icons.signal_wifi_4_bar
        : rssi > -75
            ? Icons.network_wifi_3_bar
            : rssi > -85
                ? Icons.network_wifi_2_bar
                : Icons.network_wifi_1_bar;

    return InkWell(
      onTap: isConnecting ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isConnected ? AppColors.accent1 : AppColors.divider,
            width: isConnected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isConnected
                    ? AppColors.accent1.withOpacity(0.15)
                    : AppColors.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isConnected ? Icons.bluetooth_connected : Icons.bluetooth,
                color: isConnected ? AppColors.accent1 : AppColors.accent2,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: isConnected ? AppColors.accent1 : Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    result.device.remoteId.str,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            Column(
              children: [
                Icon(rssiIcon, color: AppColors.textSecondary, size: 16),
                Text(
                  '$rssi dBm',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            if (isConnecting)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                isConnected ? Icons.check_circle : Icons.chevron_right,
                color: isConnected ? AppColors.accent1 : AppColors.textSecondary,
              ),
          ],
        ),
      ),
    );
  }
}
