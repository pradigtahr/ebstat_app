import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/measurement_point.dart';
import '../theme/app_theme.dart';

class VoltammetryChart extends StatelessWidget {
  const VoltammetryChart({
    super.key,
    required this.points,
    this.xLabel = 'Potential (mV)',
    this.yLabel = 'Current (µA)',
  });
  final List<MeasurementPoint> points;
  final String xLabel;
  final String yLabel;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.show_chart, size: 64, color: AppColors.divider),
            SizedBox(height: 12),
            Text(
              'Waiting for measurement data…',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    final spots = points
        .map((p) => FlSpot(p.x, p.y))
        .toList();

    final minX = spots.map((s) => s.x).reduce((a, b) => a < b ? a : b);
    final maxX = spots.map((s) => s.x).reduce((a, b) => a > b ? a : b);
    final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);

    final xPad = (maxX - minX) * 0.05;
    final yPad = (maxY - minY) * 0.1;

    return LineChart(
      LineChartData(
        backgroundColor: AppColors.cardBg,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          getDrawingHorizontalLine: (_) => const FlLine(
            color: AppColors.chartGrid,
            strokeWidth: 0.8,
          ),
          getDrawingVerticalLine: (_) => const FlLine(
            color: AppColors.chartGrid,
            strokeWidth: 0.8,
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: AppColors.divider),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            axisNameWidget: Text(
              yLabel,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 46,
              getTitlesWidget: (value, _) => Text(
                value.toStringAsFixed(2),
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 10),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            axisNameWidget: Text(
              xLabel,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, _) => Text(
                value.toStringAsFixed(0),
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 10),
              ),
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        minX: minX - xPad,
        maxX: maxX + xPad,
        minY: minY - yPad,
        maxY: maxY + yPad,
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.surface,
            getTooltipItems: (spots) => spots
                .map((s) => LineTooltipItem(
                      'x: ${s.x.toStringAsFixed(2)}\ny: ${s.y.toStringAsFixed(4)} µA',
                      const TextStyle(
                          color: Colors.white, fontSize: 11),
                    ))
                .toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.3,
            color: AppColors.chartLine,
            barWidth: 2,
            dotData: FlDotData(
              show: points.length <= 50,
              getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                radius: 3,
                color: AppColors.accent2,
                strokeColor: AppColors.chartLine,
                strokeWidth: 1,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.accent1.withOpacity(0.08),
            ),
          ),
        ],
      ),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeInOut,
    );
  }
}
