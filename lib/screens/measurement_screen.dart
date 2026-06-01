import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/voltammetry_mode.dart';
import '../providers/measurement_provider.dart';
import '../providers/ble_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/cv_chart.dart';
import '../widgets/voltammetry_chart.dart';
import 'analysis_screen.dart';

class MeasurementScreen extends StatefulWidget {
  const MeasurementScreen({super.key});

  @override
  State<MeasurementScreen> createState() => _MeasurementScreenState();
}

class _MeasurementScreenState extends State<MeasurementScreen> {
  bool _showSgOverlay = true;

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
    final ble         = context.watch<BleProvider>();
    final isRunning   = measurement.state == MeasurementState.running;
    final isDone      = measurement.state == MeasurementState.done;
    final isCv        = measurement.selectedMode == VoltammetryMode.cv;

    return Scaffold(
      appBar: AppBar(
        title: Text('${measurement.selectedMode?.abbreviation ?? ''} Measurement'),
        automaticallyImplyLeading: false,
        actions: [
          // SG overlay toggle — only relevant when done and SG data present
          if (isDone && isCv && _hasSgData(measurement))
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('SG',
                    style: TextStyle(
                        color: _showSgOverlay
                            ? AppColors.accent1
                            : AppColors.textSecondary,
                        fontSize: 12)),
                Switch(
                  value: _showSgOverlay,
                  onChanged: (v) => setState(() => _showSgOverlay = v),
                  activeColor: AppColors.accent1,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          // Status banner
          _StatusBanner(ble: ble, measurement: measurement),

          // Progress bar
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
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent1),
              minHeight: 3,
            ),

          // Chart
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: isCv
                  ? CvChart(
                      points: measurement.points,
                      sgPoints: _currentSgPoints(measurement),
                      showSg: _showSgOverlay,
                    )
                  : VoltammetryChart(
                      points: measurement.points,
                      xLabel:
                          measurement.selectedMode?.xAxisLabel ?? 'X',
                      yLabel:
                          measurement.selectedMode?.yAxisLabel ?? 'Y',
                    ),
            ),
          ),

          // Control bar
          _ControlBar(measurement: measurement, ble: ble),
        ],
      ),
    );
  }

  bool _hasSgData(MeasurementProvider m) {
    final project = m.project;
    if (project == null || project.measurements.isEmpty) return false;
    return project.measurements.last.hasSgData;
  }

  List<double?> _currentSgPoints(MeasurementProvider m) {
    final project = m.project;
    if (project == null || project.measurements.isEmpty) return const [];
    return project.measurements.last.sgPoints;
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
    final isDone    = measurement.state == MeasurementState.done;

    final String text;
    if (ble.isConnected) {
      if (isDone) {
        text = 'Measurement complete · ${measurement.points.length} pts';
      } else if (progress != null) {
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
    final isDone    = measurement.state == MeasurementState.done;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          if (isDone) ...[
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const AnalysisScreen()),
                ),
                icon: const Icon(Icons.analytics),
                label: const Text('View Analysis'),
              ),
            ),
          ] else ...[
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
        ],
      ),
    );
  }
}
