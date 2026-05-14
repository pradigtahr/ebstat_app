import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ble/protocol.dart';
import '../providers/measurement_provider.dart';
import '../providers/ble_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/voltammetry_chart.dart';
import 'results_screen.dart';

class MeasurementScreen extends StatefulWidget {
  const MeasurementScreen({super.key});

  @override
  State<MeasurementScreen> createState() => _MeasurementScreenState();
}

class _MeasurementScreenState extends State<MeasurementScreen> {
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    final provider = context.read<MeasurementProvider>();
    provider.addListener(_handleStateChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      provider.startMeasurement();
    });
  }

  @override
  void dispose() {
    context.read<MeasurementProvider>().removeListener(_handleStateChange);
    super.dispose();
  }

  void _handleStateChange() {
    if (!mounted || _navigated) return;
    if (context.read<MeasurementProvider>().state == MeasurementState.done) {
      _navigated = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ResultsScreen()),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final measurement = context.watch<MeasurementProvider>();
    final ble         = context.watch<BleProvider>();
    final isRunning   = measurement.state == MeasurementState.running;

    return Scaffold(
      appBar: AppBar(
        title: Text('${measurement.selectedMode?.abbreviation ?? ''} Measurement'),
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          // Progress / status banner
          _StatusBanner(ble: ble, measurement: measurement),

          // Progress bar (BLE mode only)
          if (ble.isConnected && measurement.progress != null)
            LinearProgressIndicator(
              value: measurement.progress!.fraction,
              backgroundColor: AppColors.surface,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.accent1),
              minHeight: 3,
            )
          else if (isRunning)
            const LinearProgressIndicator(
              backgroundColor: AppColors.surface,
              valueColor:
                  AlwaysStoppedAnimation<Color>(AppColors.accent1),
              minHeight: 3,
            ),

          // Chart
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: VoltammetryChart(
                points: measurement.points,
                xLabel: measurement.selectedMode?.xAxisLabel ?? 'X',
                yLabel: measurement.selectedMode?.yAxisLabel ?? 'Y',
              ),
            ),
          ),

          // Control bar
          _ControlBar(measurement: measurement, ble: ble),
        ],
      ),
    );
  }
}

// ── Status banner ─────────────────────────────────────────────────────────────
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.ble, required this.measurement});
  final BleProvider ble;
  final MeasurementProvider measurement;

  @override
  Widget build(BuildContext context) {
    final progress  = measurement.progress;
    final isRunning = measurement.state == MeasurementState.running;

    String text;
    if (ble.isConnected) {
      if (progress != null) {
        text = 'RX: ${measurement.lastBleRow ?? "…"}  '
            '· ${progress.current}/${progress.total} pts';
      } else if (isRunning) {
        text = 'Waiting for data…';
      } else {
        text = 'Finalising…';
      }
    } else {
      text = 'Demo mode · ${measurement.points.length} pts';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: AppColors.surface,
      child: Row(
        children: [
          Icon(
            ble.isConnected ? Icons.circle : Icons.science_outlined,
            size: 8,
            color: ble.isConnected ? AppColors.accent1 : AppColors.accent2,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${measurement.points.length} pts',
            style: const TextStyle(color: AppColors.accent2, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ── Control bar ───────────────────────────────────────────────────────────────
class _ControlBar extends StatelessWidget {
  const _ControlBar({required this.measurement, required this.ble});
  final MeasurementProvider measurement;
  final BleProvider ble;

  @override
  Widget build(BuildContext context) {
    final isRunning = measurement.state == MeasurementState.running;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: isRunning ? measurement.stopMeasurement : null,
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent),
              icon: const Icon(Icons.stop),
              label: Text(isRunning ? 'Stop' : 'Finishing…'),
            ),
          ),
        ],
      ),
    );
  }
}
