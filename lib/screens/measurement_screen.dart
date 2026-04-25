import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/measurement_provider.dart';
import '../providers/ble_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/voltammetry_chart.dart';

class MeasurementScreen extends StatefulWidget {
  const MeasurementScreen({super.key});

  @override
  State<MeasurementScreen> createState() => _MeasurementScreenState();
}

class _MeasurementScreenState extends State<MeasurementScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MeasurementProvider>().startMeasurement();
    });
  }

  @override
  Widget build(BuildContext context) {
    final measurement = context.watch<MeasurementProvider>();
    final ble = context.watch<BleProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${measurement.selectedMode?.abbreviation ?? ''} Measurement',
        ),
        actions: [
          if (measurement.state == MeasurementState.done ||
              measurement.points.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.download_outlined),
              tooltip: 'Export CSV',
              onPressed: measurement.exportCsv,
            ),
        ],
      ),
      body: Column(
        children: [
          _DataBanner(ble: ble, measurement: measurement),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: VoltammetryChart(points: measurement.points),
            ),
          ),
          _ControlBar(measurement: measurement),
        ],
      ),
    );
  }
}

class _DataBanner extends StatelessWidget {
  const _DataBanner({required this.ble, required this.measurement});
  final BleProvider ble;
  final MeasurementProvider measurement;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.surface,
      child: Row(
        children: [
          const Icon(Icons.circle, size: 8, color: AppColors.accent1),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              ble.lastReceivedData.isNotEmpty
                  ? 'RX: ${ble.lastReceivedData}'
                  : 'Waiting for data…',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${measurement.points.length} pts',
            style: const TextStyle(
              color: AppColors.accent2,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlBar extends StatelessWidget {
  const _ControlBar({required this.measurement});
  final MeasurementProvider measurement;

  @override
  Widget build(BuildContext context) {
    final isRunning = measurement.state == MeasurementState.running;
    final isDone = measurement.state == MeasurementState.done;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        children: [
          if (measurement.exportError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                measurement.exportError!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: isRunning
                      ? measurement.stopMeasurement
                      : isDone
                          ? measurement.resetMeasurement
                          : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isRunning
                        ? Colors.redAccent
                        : AppColors.accent1,
                  ),
                  icon: Icon(isRunning
                      ? Icons.stop
                      : isDone
                          ? Icons.refresh
                          : Icons.play_arrow),
                  label: Text(
                    isRunning
                        ? 'Stop'
                        : isDone
                            ? 'New Measurement'
                            : 'Starting…',
                  ),
                ),
              ),
              if (measurement.points.isNotEmpty) ...[
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: measurement.exportCsv,
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Export CSV'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
