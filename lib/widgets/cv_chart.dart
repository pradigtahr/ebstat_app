import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/measurement_point.dart';
import '../theme/app_theme.dart';

/// Shared cycle color palette — used by CvChart and AnalysisScreen.
const kCycleColors = [
  Color(0xFF0098DB),
  Color(0xFF4CAF50),
  Color(0xFFFF9800),
  Color(0xFFE91E63),
  Color(0xFF9C27B0),
  Color(0xFF00BCD4),
  Color(0xFFFF5722),
  Color(0xFFCDDC39),
];

/// Real-time CV chart: groups [points] by cycle number, renders each cycle
/// with a distinct color. Points within a cycle are concatenated fwd→rev,
/// producing the closed voltammogram loop naturally.
class CvChart extends StatelessWidget {
  const CvChart({
    super.key,
    required this.points,
    this.sgPoints = const [],
    this.showSg = false,
  });

  final List<MeasurementPoint> points;
  /// SG smoothed current values indexed from 0 (null = missing).
  final List<double?> sgPoints;
  final bool showSg;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.show_chart, size: 64, color: AppColors.divider),
            SizedBox(height: 12),
            Text('Waiting for CV data…',
                style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      );
    }

    // Group points by cycle number
    final byC = <int, List<MeasurementPoint>>{};
    for (final pt in points) {
      final c = pt.cycle;
      if (c != null) {
        (byC[c] ??= []).add(pt);
      }
    }

    // Fall back if no cycle metadata (e.g. pre-cycle 'start' rows)
    if (byC.isEmpty) {
      final spots = points.map((p) => FlSpot(p.x, p.y)).toList();
      return _buildSimpleChart(spots);
    }

    final allPts = byC.values.expand((l) => l).toList();
    final (minX, maxX, minY, maxY) = _bounds(allPts);
    final xPad = (maxX - minX) * 0.05;
    final yPad = max((maxY - minY) * 0.1, 0.1);

    final cycles = byC.keys.toList()..sort();
    final bars = <LineChartBarData>[];

    // Raw data bars per cycle
    for (final cycleNum in cycles) {
      final color = kCycleColors[(cycleNum - 1) % kCycleColors.length];
      bars.add(LineChartBarData(
        spots: byC[cycleNum]!.map((p) => FlSpot(p.x, p.y)).toList(),
        isCurved: true,
        curveSmoothness: 0.2,
        color: color,
        barWidth: 2,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(show: true, color: color.withOpacity(0.05)),
      ));
    }

    // SG overlay — dashed line using sgPoints indexed to match cycle 1 points
    if (showSg && sgPoints.isNotEmpty) {
      final c1Pts = byC[cycles.first];
      if (c1Pts != null) {
        final sgSpots = <FlSpot>[];
        for (int i = 0; i < c1Pts.length && i < sgPoints.length; i++) {
          final sg = sgPoints[i];
          if (sg != null) sgSpots.add(FlSpot(c1Pts[i].x, sg));
        }
        if (sgSpots.isNotEmpty) {
          bars.add(LineChartBarData(
            spots: sgSpots,
            isCurved: true,
            curveSmoothness: 0.3,
            color: Colors.white70,
            barWidth: 1.5,
            dashArray: [4, 4],
            dotData: const FlDotData(show: false),
          ));
        }
      }
    }

    return LineChart(
      LineChartData(
        backgroundColor: AppColors.cardBg,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: AppColors.chartGrid, strokeWidth: 0.8),
          getDrawingVerticalLine: (_) =>
              const FlLine(color: AppColors.chartGrid, strokeWidth: 0.8),
        ),
        borderData: FlBorderData(
            show: true, border: Border.all(color: AppColors.divider)),
        titlesData: _titlesData(),
        minX: minX - xPad,
        maxX: maxX + xPad,
        minY: minY - yPad,
        maxY: maxY + yPad,
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.surface,
            getTooltipItems: (spots) => spots.map((s) {
              final cycleNum = s.barIndex < cycles.length
                  ? cycles[s.barIndex]
                  : null;
              final label = cycleNum != null ? 'Cycle $cycleNum' : 'SG';
              return LineTooltipItem(
                '$label\n'
                '${s.x.toStringAsFixed(1)} mV\n'
                '${s.y.toStringAsFixed(3)} nA',
                TextStyle(
                  color: s.barIndex < kCycleColors.length
                      ? kCycleColors[s.barIndex]
                      : Colors.white70,
                  fontSize: 11,
                ),
              );
            }).toList(),
          ),
        ),
        lineBarsData: bars,
      ),
      duration: const Duration(milliseconds: 0),
    );
  }

  Widget _buildSimpleChart(List<FlSpot> spots) {
    final (minX, maxX, minY, maxY) = _boundsFromSpots(spots);
    final xPad = (maxX - minX) * 0.05;
    final yPad = max((maxY - minY) * 0.1, 0.1);
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
            show: true, border: Border.all(color: AppColors.divider)),
        titlesData: _titlesData(),
        minX: minX - xPad,
        maxX: maxX + xPad,
        minY: minY - yPad,
        maxY: maxY + yPad,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.2,
            color: AppColors.chartLine,
            barWidth: 2,
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
      duration: const Duration(milliseconds: 0),
    );
  }

  FlTitlesData _titlesData() => FlTitlesData(
        leftTitles: AxisTitles(
          axisNameWidget: const Text('Current (nA)',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 46,
            getTitlesWidget: (v, _) => Text(v.toStringAsFixed(2),
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 10)),
          ),
        ),
        bottomTitles: AxisTitles(
          axisNameWidget: const Text('Potential (mV)',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 28,
            getTitlesWidget: (v, _) => Text(v.toStringAsFixed(0),
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 10)),
          ),
        ),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      );

  static (double, double, double, double) _bounds(
      List<MeasurementPoint> pts) {
    final xs = pts.map((p) => p.x);
    final ys = pts.map((p) => p.y);
    return (xs.reduce(min), xs.reduce(max), ys.reduce(min), ys.reduce(max));
  }

  static (double, double, double, double) _boundsFromSpots(
      List<FlSpot> spots) {
    final xs = spots.map((s) => s.x);
    final ys = spots.map((s) => s.y);
    return (xs.reduce(min), xs.reduce(max), ys.reduce(min), ys.reduce(max));
  }
}
