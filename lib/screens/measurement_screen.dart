import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
    final m = context.read<MeasurementProvider>();
    if (m.state == MeasurementState.done) {
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
    final ble = context.watch<BleProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${measurement.selectedMode?.abbreviation ?? ''} Measurement',
        ),
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
                backgroundColor: Colors.redAccent,
              ),
              icon: const Icon(Icons.stop),
              label: Text(isRunning ? 'Stop' : 'Finishing…'),
            ),
          ),
        ],
      ),
    );
  }
}
