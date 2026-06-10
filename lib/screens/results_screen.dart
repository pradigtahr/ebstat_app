import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/project_session.dart';
import '../providers/measurement_provider.dart';
import '../theme/app_theme.dart';

const _scanColors = [
  Color(0xFF0098DB),
  Color(0xFF4CAF50),
  Color(0xFFFF9800),
  Color(0xFFE91E63),
  Color(0xFF9C27B0),
];

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  final Set<int> _hiddenScans = {};

  @override
  Widget build(BuildContext context) {
    final measurement = context.watch<MeasurementProvider>();
    final project     = measurement.project;

    return Scaffold(
      appBar: AppBar(
        title: Text('${measurement.selectedMode?.abbreviation ?? ''} Results'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            measurement.resetMeasurement();
            Navigator.of(context).pop();
          },
        ),
      ),
      body: project == null || project.measurements.isEmpty
          ? const Center(
              child: Text(
                'No measurements in this project.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          : Column(
              children: [
                _ScanLegend(
                  project: project,
                  hiddenScans: _hiddenScans,
                  onToggleVisibility: (idx) => setState(() =>
                      _hiddenScans.contains(idx)
                          ? _hiddenScans.remove(idx)
                          : _hiddenScans.add(idx)),
                  onDelete: (idx) => _confirmDelete(idx, measurement),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                    child: _MultiScanChart(
                      project:    project,
                      hiddenScans: _hiddenScans,
                    ),
                  ),
                ),
                _BottomBar(measurement: measurement),
              ],
            ),
    );
  }

  Future<void> _confirmDelete(
      int index, MeasurementProvider measurement) async {
    final project = measurement.project;
    if (project == null || index >= project.measurements.length) return;

    final session  = project.measurements[index];
    final label    = session.label.isNotEmpty ? session.label : 'Scan ${index + 1}';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete scan?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Remove "$label" from this project? This cannot be undone.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    setState(() {
      _hiddenScans.remove(index);
      final adjusted =
          _hiddenScans.map((i) => i > index ? i - 1 : i).toSet();
      _hiddenScans..clear()..addAll(adjusted);
    });
    measurement.deleteMeasurement(index);
  }
}

// ── Scan legend ───────────────────────────────────────────────────────────────

class _ScanLegend extends StatelessWidget {
  const _ScanLegend({
    required this.project,
    required this.hiddenScans,
    required this.onToggleVisibility,
    required this.onDelete,
  });

  final ProjectSession     project;
  final Set<int>           hiddenScans;
  final void Function(int) onToggleVisibility;
  final void Function(int) onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      color: AppColors.surface,
      child: Wrap(
        spacing: 8, runSpacing: 6,
        children: project.measurements.asMap().entries.map((entry) {
          final idx      = entry.key;
          final session  = entry.value;
          final color    = _scanColors[idx % _scanColors.length];
          final isHidden = hiddenScans.contains(idx);
          final label    = session.label.isNotEmpty
              ? session.label
              : 'Scan ${idx + 1}';

          return GestureDetector(
            onTap: () => onToggleVisibility(idx),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isHidden
                    ? AppColors.primary
                    : color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isHidden ? AppColors.divider : color.withOpacity(0.6),
                ),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 18, height: 3,
                  decoration: BoxDecoration(
                    color:        isHidden ? AppColors.divider : color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                      color: isHidden ? AppColors.textSecondary : Colors.white,
                      fontSize: 12,
                      decoration: isHidden ? TextDecoration.lineThrough : null,
                    )),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => onDelete(idx),
                  child: const Icon(Icons.close, size: 14, color: Colors.white54),
                ),
              ]),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Multi-scan chart ──────────────────────────────────────────────────────────

class _MultiScanChart extends StatelessWidget {
  const _MultiScanChart({
    required this.project,
    required this.hiddenScans,
  });

  final ProjectSession project;
  final Set<int>       hiddenScans;

  @override
  Widget build(BuildContext context) {
    final visibleIndices = List.generate(project.measurements.length, (i) => i)
        .where((i) => !hiddenScans.contains(i))
        .toList();

    if (visibleIndices.isEmpty) {
      return const Center(
        child: Text('All scans hidden — tap a scan to show it.',
            style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    final allSpots = visibleIndices
        .expand((i) =>
            project.measurements[i].points.map((p) => FlSpot(p.x, p.y)))
        .toList();

    final minX = allSpots.map((s) => s.x).reduce((a, b) => a < b ? a : b);
    final maxX = allSpots.map((s) => s.x).reduce((a, b) => a > b ? a : b);
    final minY = allSpots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final maxY = allSpots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final xPad = (maxX - minX) * 0.05;
    final yPad = (maxY - minY) * 0.1;

    final bars = visibleIndices.map((idx) {
      final session = project.measurements[idx];
      final color   = _scanColors[idx % _scanColors.length];
      return LineChartBarData(
        spots:           session.points.map((p) => FlSpot(p.x, p.y)).toList(),
        isCurved:        true,
        curveSmoothness: 0.2,
        color:           color,
        barWidth:        2,
        dotData:         const FlDotData(show: false),
        belowBarData:    BarAreaData(show: true, color: color.withOpacity(0.05)),
      );
    }).toList();

    return LineChart(
      LineChartData(
        backgroundColor: AppColors.cardBg,
        clipData:        const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: AppColors.chartGrid, strokeWidth: 0.8),
          getDrawingVerticalLine: (_) =>
              const FlLine(color: AppColors.chartGrid, strokeWidth: 0.8),
        ),
        borderData: FlBorderData(
            show: true, border: Border.all(color: AppColors.divider)),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            axisNameWidget: const Text('Current (nA)',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
            sideTitles: SideTitles(
              showTitles:   true,
              reservedSize: 46,
              getTitlesWidget: (v, _) => Text(v.toStringAsFixed(1),
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 10)),
            ),
          ),
          bottomTitles: AxisTitles(
            axisNameWidget: const Text('Potential (mV)',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
            sideTitles: SideTitles(
              showTitles:   true,
              reservedSize: 28,
              getTitlesWidget: (v, _) => Text(v.toStringAsFixed(0),
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 10)),
            ),
          ),
          rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
        ),
        minX: minX - xPad, maxX: maxX + xPad,
        minY: minY - yPad, maxY: maxY + yPad,
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.surface,
            getTooltipItems: (spots) => spots.map((s) {
              final idx     = visibleIndices[s.barIndex];
              final session = project.measurements[idx];
              final lbl     = session.label.isNotEmpty
                  ? session.label
                  : 'Scan ${idx + 1}';
              return LineTooltipItem(
                '$lbl\n${s.x.toStringAsFixed(1)} mV\n${s.y.toStringAsFixed(3)} nA',
                TextStyle(
                    color:    _scanColors[idx % _scanColors.length],
                    fontSize: 11),
              );
            }).toList(),
          ),
        ),
        lineBarsData: bars,
      ),
      duration: Duration.zero,
    );
  }
}

// ── Bottom action bar ─────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.measurement});
  final MeasurementProvider measurement;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      decoration: const BoxDecoration(
        color:  AppColors.primary,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (measurement.exportError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(measurement.exportError!,
                  style: const TextStyle(
                      color: Colors.redAccent, fontSize: 12)),
            ),
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  measurement.resetMeasurement();
                  Navigator.of(context).pop();
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent1),
                icon:  const Icon(Icons.add),
                label: const Text('New Measurement'),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: measurement.exportProject,
              icon:  const Icon(Icons.save_alt),
              label: const Text('Export'),
            ),
          ]),
        ],
      ),
    );
  }
}
