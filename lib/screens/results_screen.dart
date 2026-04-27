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
  @override
  Widget build(BuildContext context) {
    final measurement = context.watch<MeasurementProvider>();
    final project = measurement.project;

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
        actions: [
          if (project != null && project.measurements.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.download_outlined),
              tooltip: 'Export XLSX',
              onPressed: measurement.exportProject,
            ),
        ],
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
                _ScanLegend(project: project),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                    child: _MultiScanChart(
                      project: project,
                      onPointTapped: (barIndex, spotIndex) =>
                          _showAnnotationSheet(context, barIndex, spotIndex, project),
                    ),
                  ),
                ),
                if (project.peaks.isNotEmpty) _PeakList(project: project),
                _BottomBar(measurement: measurement),
              ],
            ),
    );
  }

  void _showAnnotationSheet(
    BuildContext context,
    int barIndex,
    int spotIndex,
    ProjectSession project,
  ) {
    if (barIndex >= project.measurements.length) return;
    final session = project.measurements[barIndex];
    if (spotIndex >= session.points.length) return;
    final pt = session.points[spotIndex];
    final color = _scanColors[barIndex % _scanColors.length];

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(
                  'Scan ${barIndex + 1}  ·  '
                  '${pt.x.toStringAsFixed(2)} mV, ${pt.y.toStringAsFixed(4)} µA',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Label this point as a peak:',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                    icon: const Icon(Icons.arrow_downward, size: 18),
                    label: const Text('Cathodic'),
                    onPressed: () {
                      context.read<MeasurementProvider>().annotatePoint(
                            barIndex, spotIndex, PeakType.cathodic);
                      Navigator.of(context).pop();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade700),
                    icon: const Icon(Icons.arrow_upward, size: 18),
                    label: const Text('Anodic'),
                    onPressed: () {
                      context.read<MeasurementProvider>().annotatePoint(
                            barIndex, spotIndex, PeakType.anodic);
                      Navigator.of(context).pop();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Multi-scan chart ─────────────────────────────────────────────────────────

class _MultiScanChart extends StatelessWidget {
  const _MultiScanChart({
    required this.project,
    required this.onPointTapped,
  });

  final ProjectSession project;
  final void Function(int barIndex, int spotIndex) onPointTapped;

  @override
  Widget build(BuildContext context) {
    final allSpots = project.measurements
        .expand((s) => s.points.map((p) => FlSpot(p.x, p.y)))
        .toList();

    if (allSpots.isEmpty) return const SizedBox.shrink();

    final minX = allSpots.map((s) => s.x).reduce((a, b) => a < b ? a : b);
    final maxX = allSpots.map((s) => s.x).reduce((a, b) => a > b ? a : b);
    final minY = allSpots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final maxY = allSpots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final xPad = (maxX - minX) * 0.05;
    final yPad = (maxY - minY) * 0.1;

    return LineChart(
      LineChartData(
        backgroundColor: AppColors.cardBg,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: AppColors.chartGrid, strokeWidth: 0.8),
          getDrawingVerticalLine: (_) =>
              const FlLine(color: AppColors.chartGrid, strokeWidth: 0.8),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: AppColors.divider),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            axisNameWidget: const Text(
              'Current (µA)',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 46,
              getTitlesWidget: (v, _) => Text(
                v.toStringAsFixed(2),
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            axisNameWidget: const Text(
              'Potential (mV)',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (v, _) => Text(
                v.toStringAsFixed(0),
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
              ),
            ),
          ),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        minX: minX - xPad,
        maxX: maxX + xPad,
        minY: minY - yPad,
        maxY: maxY + yPad,
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          touchCallback: (event, response) {
            if (event is FlTapUpEvent &&
                response?.lineBarSpots != null &&
                response!.lineBarSpots!.isNotEmpty) {
              final spot = response.lineBarSpots!.first;
              onPointTapped(spot.barIndex, spot.spotIndex);
            }
          },
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.surface,
            getTooltipItems: (spots) => spots
                .map((s) => LineTooltipItem(
                      'Scan ${s.barIndex + 1}\n'
                      '${s.x.toStringAsFixed(2)} mV\n'
                      '${s.y.toStringAsFixed(4)} µA',
                      TextStyle(
                        color: _scanColors[s.barIndex % _scanColors.length],
                        fontSize: 11,
                      ),
                    ))
                .toList(),
          ),
        ),
        lineBarsData: _buildBars(project),
      ),
      duration: const Duration(milliseconds: 0),
    );
  }

  List<LineChartBarData> _buildBars(ProjectSession project) {
    return project.measurements.asMap().entries.map((entry) {
      final idx = entry.key;
      final session = entry.value;
      final color = _scanColors[idx % _scanColors.length];
      final peaksForScan =
          project.peaks.where((p) => p.measurementIndex == idx).toList();

      return LineChartBarData(
        spots: session.points.map((p) => FlSpot(p.x, p.y)).toList(),
        isCurved: true,
        curveSmoothness: 0.3,
        color: color,
        barWidth: 2,
        dotData: FlDotData(
          show: peaksForScan.isNotEmpty,
          getDotPainter: (spot, percent, bar, spotIndex) {
            final peak = peaksForScan
                .where((p) => p.pointIndex == spotIndex)
                .firstOrNull;
            if (peak == null) {
              return FlDotCirclePainter(
                radius: 0,
                color: Colors.transparent,
                strokeColor: Colors.transparent,
              );
            }
            return FlDotCirclePainter(
              radius: 6,
              color: peak.type == PeakType.cathodic
                  ? Colors.redAccent
                  : Colors.amber,
              strokeColor: Colors.white,
              strokeWidth: 1.5,
            );
          },
        ),
        belowBarData: BarAreaData(
          show: true,
          color: color.withOpacity(0.06),
        ),
      );
    }).toList();
  }
}

// ── Scan legend ──────────────────────────────────────────────────────────────

class _ScanLegend extends StatelessWidget {
  const _ScanLegend({required this.project});
  final ProjectSession project;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.surface,
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        children: project.measurements.asMap().entries.map((entry) {
          final idx = entry.key;
          final color = _scanColors[idx % _scanColors.length];
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 20,
                height: 3,
                color: color,
              ),
              const SizedBox(width: 6),
              Text(
                'Scan ${idx + 1}',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

// ── Peak annotation list ─────────────────────────────────────────────────────

class _PeakList extends StatelessWidget {
  const _PeakList({required this.project});
  final ProjectSession project;

  @override
  Widget build(BuildContext context) {
    final sorted = [...project.peaks]
      ..sort((a, b) => a.measurementIndex.compareTo(b.measurementIndex));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        border: Border(
          top: BorderSide(color: AppColors.divider),
          bottom: BorderSide(color: AppColors.divider),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Peak Annotations',
            style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: sorted.map((peak) {
              final color = peak.type == PeakType.cathodic
                  ? Colors.redAccent
                  : Colors.amber;
              final label =
                  '${peak.type == PeakType.cathodic ? 'Ec' : 'Ea'} (S${peak.measurementIndex + 1}): '
                  '${peak.point.x.toStringAsFixed(1)} mV, '
                  '${peak.point.y.toStringAsFixed(3)} µA';
              return Chip(
                label: Text(label,
                    style: const TextStyle(fontSize: 11, color: Colors.white)),
                backgroundColor: color.withOpacity(0.2),
                side: BorderSide(color: color.withOpacity(0.5)),
                padding: EdgeInsets.zero,
                deleteIcon: const Icon(Icons.close, size: 14, color: Colors.white54),
                onDeleted: () {
                  context.read<MeasurementProvider>().removePeakAnnotation(
                        peak.measurementIndex, peak.type);
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ── Bottom action bar ────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.measurement});
  final MeasurementProvider measurement;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
                  onPressed: () {
                    measurement.resetMeasurement();
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent1),
                  icon: const Icon(Icons.add),
                  label: const Text('New Measurement'),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: measurement.exportProject,
                icon: const Icon(Icons.save_alt),
                label: const Text('Export'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
