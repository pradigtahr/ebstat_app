import 'dart:io';
import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/project_session.dart';
import '../models/voltammetry_mode.dart';
import '../providers/measurement_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/cv_chart.dart';
import 'parameters_screen.dart';

// ── Bar metadata for touch callback ──────────────────────────────────────────
class _BarMeta {
  final int measurementIdx;
  final int? cycleNum;
  final List<int> pointIndices; // indices into session.points
  _BarMeta(this.measurementIdx, this.cycleNum, this.pointIndices);
}

class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  final Set<int>    _hiddenMeasurements = {};
  final Set<String> _hiddenCycles       = {}; // "measIdx:cycleNum"
  bool _showSg = true;

  String _cycleKey(int mIdx, int cNum) => '$mIdx:$cNum';

  bool _isMeasHidden(int i) => _hiddenMeasurements.contains(i);
  bool _isCycleHidden(int m, int c) =>
      _hiddenCycles.contains(_cycleKey(m, c));

  void _toggleMeas(int i) => setState(() => _hiddenMeasurements.contains(i)
      ? _hiddenMeasurements.remove(i)
      : _hiddenMeasurements.add(i));

  void _toggleCycle(int m, int c) => setState(() {
        final k = _cycleKey(m, c);
        _hiddenCycles.contains(k) ? _hiddenCycles.remove(k) : _hiddenCycles.add(k);
      });

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MeasurementProvider>();
    final project  = provider.project;
    final mode     = provider.selectedMode;
    final isCv     = mode == VoltammetryMode.cv;
    final hasSg    = project?.measurements.any((s) => s.hasSgData) ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text('${mode?.abbreviation ?? ''} Analysis'),
        actions: [
          if (hasSg)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('SG',
                    style: TextStyle(
                      color: _showSg
                          ? AppColors.accent1
                          : AppColors.textSecondary,
                      fontSize: 12,
                    )),
                Switch(
                  value: _showSg,
                  onChanged: (v) => setState(() => _showSg = v),
                  activeColor: AppColors.accent1,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
        ],
      ),
      body: project == null || project.measurements.isEmpty
          ? _empty()
          : Column(
              children: [
                // Chart
                Expanded(
                  flex: 5,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                    child: _OverlayChart(
                      project:            project,
                      hiddenMeasurements: _hiddenMeasurements,
                      hiddenCycles:       _hiddenCycles,
                      isCv:               isCv,
                      showSg:             _showSg,
                      xLabel: mode?.xAxisLabel ?? 'Potential (mV)',
                      yLabel: mode?.yAxisLabel ?? 'Current (nA)',
                      onPointTapped: (measIdx, ptIdx) =>
                          _showAnnotationSheet(context, measIdx, ptIdx, project),
                    ),
                  ),
                ),

                // Peak annotations strip
                if (project.peaks.isNotEmpty)
                  _PeakStrip(project: project, provider: provider),

                // Measurement tree
                Expanded(
                  flex: 3,
                  child: _MeasurementTree(
                    project:            project,
                    provider:           provider,
                    isCv:               isCv,
                    hiddenMeasurements: _hiddenMeasurements,
                    hiddenCycles:       _hiddenCycles,
                    onToggleMeas:       _toggleMeas,
                    onToggleCycle:      _toggleCycle,
                    onDeleteMeas: (i) => _confirmDeleteMeas(i, provider),
                    onDeleteCycle: (m, c) =>
                        _confirmDeleteCycle(m, c, provider),
                  ),
                ),

                // Bottom action bar
                _BottomBar(
                  provider: provider,
                  project:  project,
                  mode:     mode,
                ),
              ],
            ),
    );
  }

  Widget _empty() => const Center(
        child: Text('No measurements in this project.',
            style: TextStyle(color: AppColors.textSecondary)),
      );

  // ── Peak annotation sheet ──────────────────────────────────────────────────

  void _showAnnotationSheet(
      BuildContext context, int measIdx, int ptIdx, ProjectSession project) {
    if (measIdx >= project.measurements.length) return;
    final session = project.measurements[measIdx];
    if (ptIdx >= session.points.length) return;
    final pt = session.points[ptIdx];

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${session.displayName}  ·  '
              '${pt.x.toStringAsFixed(1)} mV,  ${pt.y.toStringAsFixed(3)} nA'
              '${pt.cycle != null ? "  (cycle ${pt.cycle})" : ""}',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            const Text('Annotate as peak:',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent),
                    icon: const Icon(Icons.arrow_downward, size: 18),
                    label: const Text('Cathodic (Ec)'),
                    onPressed: () {
                      context
                          .read<MeasurementProvider>()
                          .annotatePoint(measIdx, ptIdx, PeakType.cathodic);
                      Navigator.of(context).pop();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber),
                    icon: const Icon(Icons.arrow_upward, size: 18),
                    label: const Text('Anodic (Ea)'),
                    onPressed: () {
                      context
                          .read<MeasurementProvider>()
                          .annotatePoint(measIdx, ptIdx, PeakType.anodic);
                      Navigator.of(context).pop();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Confirm delete dialogs ─────────────────────────────────────────────────

  Future<void> _confirmDeleteMeas(
      int index, MeasurementProvider provider) async {
    final session = provider.project?.measurements[index];
    if (session == null) return;
    final confirmed = await _confirmDialog(
        context, 'Delete "${session.displayName}"?',
        'Remove this measurement and all its annotations? Cannot be undone.');
    if (confirmed != true || !mounted) return;
    setState(() => _hiddenMeasurements.remove(index));
    provider.deleteMeasurement(index);
  }

  Future<void> _confirmDeleteCycle(
      int measIdx, int cycleNum, MeasurementProvider provider) async {
    final session = provider.project?.measurements[measIdx];
    if (session == null) return;
    final confirmed = await _confirmDialog(
        context, 'Delete Cycle $cycleNum?',
        'Remove all data for cycle $cycleNum from "${session.displayName}"?');
    if (confirmed != true || !mounted) return;
    setState(() => _hiddenCycles.remove(_cycleKey(measIdx, cycleNum)));
    provider.deleteCycle(measIdx, cycleNum);
  }

  Future<bool?> _confirmDialog(
      BuildContext ctx, String title, String body) =>
      showDialog<bool>(
        context: ctx,
        builder: (c) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title:   Text(title, style: const TextStyle(color: Colors.white)),
          content: Text(body,
              style: const TextStyle(color: AppColors.textSecondary)),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(c).pop(false),
                child: const Text('Cancel')),
            ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent),
                onPressed: () => Navigator.of(c).pop(true),
                child: const Text('Delete')),
          ],
        ),
      );
}

// ── Overlay chart ─────────────────────────────────────────────────────────────
class _OverlayChart extends StatelessWidget {
  const _OverlayChart({
    required this.project,
    required this.hiddenMeasurements,
    required this.hiddenCycles,
    required this.isCv,
    required this.showSg,
    required this.xLabel,
    required this.yLabel,
    required this.onPointTapped,
  });

  final ProjectSession project;
  final Set<int>    hiddenMeasurements;
  final Set<String> hiddenCycles;
  final bool isCv;
  final bool showSg;
  final String xLabel;
  final String yLabel;
  final void Function(int measIdx, int ptIdx) onPointTapped;

  @override
  Widget build(BuildContext context) {
    final barMetas = <_BarMeta>[];
    final bars     = <LineChartBarData>[];
    final peaks    = project.peaks;

    // Assign a global color index incremented across all (meas, cycle) pairs
    int globalColorIdx = 0;

    for (int mIdx = 0; mIdx < project.measurements.length; mIdx++) {
      if (hiddenMeasurements.contains(mIdx)) continue;
      final session = project.measurements[mIdx];

      if (isCv) {
        // Per-cycle bars for CV
        final cycles = session.cycles.toList()..sort();
        for (final cNum in cycles) {
          if (hiddenCycles.contains('$mIdx:$cNum')) {
            globalColorIdx++;
            continue;
          }
          final cyclePts = session.points
              .where((p) => p.cycle == cNum)
              .toList();
          if (cyclePts.isEmpty) { globalColorIdx++; continue; }

          final originalIndices = <int>[];
          for (int i = 0; i < session.points.length; i++) {
            if (session.points[i].cycle == cNum) originalIndices.add(i);
          }

          final color = kCycleColors[globalColorIdx % kCycleColors.length];
          final peaksForMeas = peaks.where((p) => p.measurementIndex == mIdx);

          bars.add(LineChartBarData(
            spots: cyclePts.map((p) => FlSpot(p.x, p.y)).toList(),
            isCurved: true,
            curveSmoothness: 0.2,
            color: color,
            barWidth: 2,
            dotData: FlDotData(
              show: peaksForMeas.isNotEmpty,
              getDotPainter: (spot, _, __, spotIdx) {
                if (spotIdx >= originalIndices.length) {
                  return FlDotCirclePainter(
                      radius: 0,
                      color: Colors.transparent,
                      strokeColor: Colors.transparent);
                }
                final origIdx = originalIndices[spotIdx];
                final peak = peaksForMeas
                    .where((p) => p.pointIndex == origIdx)
                    .firstOrNull;
                if (peak == null) {
                  return FlDotCirclePainter(
                      radius: 0,
                      color: Colors.transparent,
                      strokeColor: Colors.transparent);
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
                show: true, color: color.withOpacity(0.05)),
          ));
          barMetas.add(_BarMeta(mIdx, cNum, originalIndices));

          // SG overlay for cycle 1 of each measurement
          if (showSg && cNum == 1 && session.hasSgData) {
            final sgSpots = <FlSpot>[];
            for (int i = 0; i < cyclePts.length && i < session.sgPoints.length; i++) {
              final sg = session.sgPoints[i];
              if (sg != null) sgSpots.add(FlSpot(cyclePts[i].x, sg));
            }
            if (sgSpots.isNotEmpty) {
              bars.add(LineChartBarData(
                spots: sgSpots,
                isCurved: true,
                curveSmoothness: 0.3,
                color: Colors.white60,
                barWidth: 1.5,
                dashArray: [4, 4],
                dotData: const FlDotData(show: false),
              ));
              barMetas.add(_BarMeta(mIdx, null, [])); // SG bar — not tappable
            }
          }

          globalColorIdx++;
        }
      } else {
        // Non-CV: one bar per measurement
        if (session.points.isEmpty) { globalColorIdx++; continue; }
        final color =
            kCycleColors[globalColorIdx % kCycleColors.length];
        final peaksForMeas =
            peaks.where((p) => p.measurementIndex == mIdx).toList();
        final indices =
            List<int>.generate(session.points.length, (i) => i);

        bars.add(LineChartBarData(
          spots: session.points.map((p) => FlSpot(p.x, p.y)).toList(),
          isCurved: true,
          curveSmoothness: 0.2,
          color: color,
          barWidth: 2,
          dotData: FlDotData(
            show: peaksForMeas.isNotEmpty,
            getDotPainter: (spot, _, __, spotIdx) {
              final peak = peaksForMeas
                  .where((p) => p.pointIndex == spotIdx)
                  .firstOrNull;
              if (peak == null) {
                return FlDotCirclePainter(
                    radius: 0,
                    color: Colors.transparent,
                    strokeColor: Colors.transparent);
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
              show: true, color: color.withOpacity(0.05)),
        ));
        barMetas.add(_BarMeta(mIdx, null, indices));
        globalColorIdx++;
      }
    }

    if (bars.isEmpty) {
      return const Center(
        child: Text('All measurements hidden.',
            style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    final allSpots = bars.expand((b) => b.spots).toList();
    final xs = allSpots.map((s) => s.x);
    final ys = allSpots.map((s) => s.y);
    final minX = xs.reduce(min);
    final maxX = xs.reduce(max);
    final minY = ys.reduce(min);
    final maxY = ys.reduce(max);
    final xPad = max((maxX - minX) * 0.05, 1.0);
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
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            axisNameWidget: Text(yLabel,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 11)),
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 46,
              getTitlesWidget: (v, _) => Text(v.toStringAsFixed(1),
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 10)),
            ),
          ),
          bottomTitles: AxisTitles(
            axisNameWidget: Text(xLabel,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 11)),
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (v, _) => Text(v.toStringAsFixed(0),
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 10)),
            ),
          ),
          rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
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
              if (spot.barIndex >= barMetas.length) return;
              final meta = barMetas[spot.barIndex];
              if (meta.pointIndices.isEmpty) return; // SG bar
              final spotIdx = spot.spotIndex;
              if (spotIdx >= meta.pointIndices.length) return;
              final origIdx = meta.pointIndices[spotIdx];
              onPointTapped(meta.measurementIdx, origIdx);
            }
          },
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.surface,
            getTooltipItems: (spots) => spots.map((s) {
              if (s.barIndex >= barMetas.length) {
                return LineTooltipItem('', const TextStyle());
              }
              final meta = barMetas[s.barIndex];
              final session = project.measurements[meta.measurementIdx];
              final label = meta.cycleNum != null
                  ? '${session.displayName} · C${meta.cycleNum}'
                  : session.displayName;
              final color = s.barIndex < barMetas.length
                  ? kCycleColors[s.barIndex % kCycleColors.length]
                  : Colors.white70;
              return LineTooltipItem(
                '$label\n${s.x.toStringAsFixed(1)} mV\n'
                '${s.y.toStringAsFixed(3)} nA',
                TextStyle(color: color, fontSize: 11),
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

// ── Peak annotations strip ────────────────────────────────────────────────────
class _PeakStrip extends StatelessWidget {
  const _PeakStrip({required this.project, required this.provider});
  final ProjectSession project;
  final MeasurementProvider provider;

  @override
  Widget build(BuildContext context) {
    final sorted = [...project.peaks]
      ..sort((a, b) => a.measurementIndex.compareTo(b.measurementIndex));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
          const Text('PEAK ANNOTATIONS',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: sorted.map((peak) {
              final color = peak.type == PeakType.cathodic
                  ? Colors.redAccent
                  : Colors.amber;
              final session = project.measurements[peak.measurementIndex];
              final typeLabel =
                  peak.type == PeakType.cathodic ? 'Ec' : 'Ea';
              return Chip(
                label: Text(
                  '$typeLabel (${session.displayName}): '
                  '${peak.point.x.toStringAsFixed(1)} mV, '
                  '${peak.point.y.toStringAsFixed(3)} nA',
                  style:
                      const TextStyle(fontSize: 11, color: Colors.white),
                ),
                backgroundColor: color.withOpacity(0.2),
                side: BorderSide(color: color.withOpacity(0.5)),
                padding: EdgeInsets.zero,
                deleteIcon: const Icon(Icons.close,
                    size: 14, color: Colors.white54),
                onDeleted: () => provider.removePeakAnnotation(
                    peak.measurementIndex, peak.type),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ── Measurement tree ──────────────────────────────────────────────────────────
class _MeasurementTree extends StatelessWidget {
  const _MeasurementTree({
    required this.project,
    required this.provider,
    required this.isCv,
    required this.hiddenMeasurements,
    required this.hiddenCycles,
    required this.onToggleMeas,
    required this.onToggleCycle,
    required this.onDeleteMeas,
    required this.onDeleteCycle,
  });

  final ProjectSession project;
  final MeasurementProvider provider;
  final bool isCv;
  final Set<int>    hiddenMeasurements;
  final Set<String> hiddenCycles;
  final void Function(int) onToggleMeas;
  final void Function(int, int) onToggleCycle;
  final void Function(int) onDeleteMeas;
  final void Function(int, int) onDeleteCycle;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: project.measurements.length,
        itemBuilder: (ctx, mIdx) {
          final session  = project.measurements[mIdx];
          final isHidden = hiddenMeasurements.contains(mIdx);

          if (!isCv || session.cycles.isEmpty) {
            // Non-CV or single-shot: flat row
            return _MeasRow(
              label:    session.displayName,
              sublabel: session.label.isNotEmpty ? session.label : null,
              visible:  !isHidden,
              colorDot: kCycleColors[mIdx % kCycleColors.length],
              onToggle: () => onToggleMeas(mIdx),
              onDelete: () => onDeleteMeas(mIdx),
            );
          }

          // CV: expandable with cycle sub-rows
          final cycles = session.cycles.toList()..sort();
          return Theme(
            data: Theme.of(context)
                .copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              leading: Icon(
                isHidden
                    ? Icons.visibility_off_outlined
                    : Icons.expand_more,
                color: isHidden
                    ? AppColors.textSecondary
                    : AppColors.accent2,
                size: 20,
              ),
              title: Text(session.displayName,
                  style: TextStyle(
                    color: isHidden ? AppColors.textSecondary : Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  )),
              subtitle: session.label.isNotEmpty
                  ? Text(session.label,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 11))
                  : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      isHidden
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                      color: isHidden
                          ? AppColors.textSecondary
                          : AppColors.accent1,
                    ),
                    onPressed: () => onToggleMeas(mIdx),
                    tooltip: isHidden ? 'Show' : 'Hide',
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        size: 18, color: Colors.redAccent),
                    onPressed: () => onDeleteMeas(mIdx),
                    tooltip: 'Delete measurement',
                  ),
                ],
              ),
              children: cycles.map((cNum) {
                final key       = '$mIdx:$cNum';
                final cycHidden = hiddenCycles.contains(key);
                final color =
                    kCycleColors[(cNum - 1) % kCycleColors.length];
                return _MeasRow(
                  label:    'Cycle $cNum',
                  visible:  !cycHidden,
                  colorDot: color,
                  indent:   true,
                  onToggle: () => onToggleCycle(mIdx, cNum),
                  onDelete: () => onDeleteCycle(mIdx, cNum),
                );
              }).toList(),
            ),
          );
        },
      ),
    );
  }
}

class _MeasRow extends StatelessWidget {
  const _MeasRow({
    required this.label,
    required this.visible,
    required this.colorDot,
    required this.onToggle,
    required this.onDelete,
    this.sublabel,
    this.indent = false,
  });

  final String  label;
  final String? sublabel;
  final bool    visible;
  final Color   colorDot;
  final bool    indent;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        contentPadding: EdgeInsets.only(
            left: indent ? 32.0 : 12.0, right: 4),
        leading: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: visible ? colorDot : AppColors.divider,
            shape: BoxShape.circle,
          ),
        ),
        title: Text(
          label,
          style: TextStyle(
            color: visible ? Colors.white : AppColors.textSecondary,
            fontSize: indent ? 13 : 14,
          ),
        ),
        subtitle: sublabel != null
            ? Text(sublabel!,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 11))
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                visible
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 18,
                color: visible ? AppColors.accent1 : AppColors.textSecondary,
              ),
              onPressed: onToggle,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  size: 18, color: Colors.redAccent),
              onPressed: onDelete,
            ),
          ],
        ),
      );
}

// ── Bottom action bar ─────────────────────────────────────────────────────────
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.provider,
    required this.project,
    required this.mode,
  });

  final MeasurementProvider provider;
  final ProjectSession project;
  final VoltammetryMode? mode;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          OutlinedButton.icon(
            onPressed: () => _showExportSheet(context),
            icon: const Icon(Icons.save_alt, size: 18),
            label: const Text('Export CSV'),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () {
                provider.resetMeasurement();
                if (mode != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => ParametersScreen(mode: mode!)),
                  );
                }
              },
              icon: const Icon(Icons.add),
              label: const Text('New Measurement'),
            ),
          ),
        ],
      ),
    );
  }

  void _showExportSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => _ExportSheet(project: project, mode: mode),
    );
  }
}

// ── Export CSV sheet ──────────────────────────────────────────────────────────
class _ExportSheet extends StatefulWidget {
  const _ExportSheet({required this.project, required this.mode});
  final ProjectSession project;
  final VoltammetryMode? mode;

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  final Set<int>    _selMeasurements = {};
  final Set<String> _selCycles       = {};
  bool _exporting = false;
  String? _error;

  bool get _isCv => widget.mode == VoltammetryMode.cv;

  @override
  void initState() {
    super.initState();
    // Select all by default
    for (int i = 0; i < widget.project.measurements.length; i++) {
      _selMeasurements.add(i);
      if (_isCv) {
        for (final c in widget.project.measurements[i].cycles) {
          _selCycles.add('$i:$c');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (_, ctrl) => Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                const Text('Select data to export',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton(
                  onPressed: _exporting ? null : () => _export(context),
                  child: _exporting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Export'),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(_error!,
                  style: const TextStyle(
                      color: Colors.redAccent, fontSize: 12)),
            ),
          const Divider(color: AppColors.divider, height: 1),
          Expanded(
            child: ListView.builder(
              controller: ctrl,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: widget.project.measurements.length,
              itemBuilder: (_, mIdx) {
                final session = widget.project.measurements[mIdx];
                final measSel = _selMeasurements.contains(mIdx);

                if (!_isCv || session.cycles.isEmpty) {
                  return CheckboxListTile(
                    dense: true,
                    title: Text(session.displayName,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 14)),
                    subtitle: session.label.isNotEmpty
                        ? Text(session.label,
                            style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11))
                        : null,
                    value: measSel,
                    activeColor: AppColors.accent1,
                    onChanged: (v) => setState(() =>
                        v! ? _selMeasurements.add(mIdx) : _selMeasurements.remove(mIdx)),
                  );
                }

                // CV: header + cycle sub-items
                final cycles = session.cycles.toList()..sort();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CheckboxListTile(
                      dense: true,
                      title: Text(session.displayName,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                      value: measSel,
                      activeColor: AppColors.accent1,
                      onChanged: (v) {
                        setState(() {
                          if (v!) {
                            _selMeasurements.add(mIdx);
                            for (final c in cycles) _selCycles.add('$mIdx:$c');
                          } else {
                            _selMeasurements.remove(mIdx);
                            for (final c in cycles) _selCycles.remove('$mIdx:$c');
                          }
                        });
                      },
                    ),
                    ...cycles.map((cNum) {
                      final key  = '$mIdx:$cNum';
                      final cSel = _selCycles.contains(key);
                      return Padding(
                        padding: const EdgeInsets.only(left: 20),
                        child: CheckboxListTile(
                          dense: true,
                          title: Text('Cycle $cNum',
                              style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13)),
                          value: cSel,
                          activeColor: AppColors.accent1,
                          onChanged: (v) => setState(() =>
                              v! ? _selCycles.add(key) : _selCycles.remove(key)),
                        ),
                      );
                    }),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _export(BuildContext context) async {
    setState(() { _exporting = true; _error = null; });
    try {
      final buf = StringBuffer();
      bool headerWritten = false;
      final isCv = _isCv;

      for (int mIdx = 0; mIdx < widget.project.measurements.length; mIdx++) {
        if (!_selMeasurements.contains(mIdx)) continue;
        final session = widget.project.measurements[mIdx];

        for (int pIdx = 0; pIdx < session.points.length; pIdx++) {
          final pt = session.points[pIdx];

          // CV: skip if cycle not selected
          if (isCv && pt.cycle != null &&
              !_selCycles.contains('$mIdx:${pt.cycle}')) continue;

          if (!headerWritten) {
            if (isCv) {
              buf.writeln(
                  'measurement_name,label,cycle,direction,potential_mV,current_nA');
            } else {
              final xH = session.mode == 'CA' ? 'time_ms' : 'potential_mV';
              buf.writeln('measurement_name,label,$xH,current_nA');
            }
            headerWritten = true;
          }

          if (isCv) {
            buf.writeln('"${session.displayName}",'
                '"${session.label}",'
                '${pt.cycle ?? ""},'
                '${pt.direction ?? ""},'
                '${pt.x.toStringAsFixed(4)},'
                '${pt.y.toStringAsFixed(6)}');
          } else {
            buf.writeln('"${session.displayName}",'
                '"${session.label}",'
                '${pt.x.toStringAsFixed(4)},'
                '${pt.y.toStringAsFixed(6)}');
          }
        }

        // Append SG data section if selected
        if (isCv && _selCycles.isNotEmpty && session.hasSgData) {
          buf.writeln('# SG smoothed current for ${session.displayName}');
          buf.writeln('measurement_name,index,sg_current_nA');
          for (int i = 0; i < session.sgPoints.length; i++) {
            final sg = session.sgPoints[i];
            if (sg != null) {
              buf.writeln('"${session.displayName}",$i,${sg.toStringAsFixed(6)}');
            }
          }
        }
      }

      if (!headerWritten) {
        setState(() {
          _exporting = false;
          _error = 'Nothing selected to export.';
        });
        return;
      }

      final dir = await getTemporaryDirectory();
      final ts  = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final file = File('${dir.path}/ebstat_export_$ts.csv');
      await file.writeAsString(buf.toString());

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv')],
        subject: 'EbStat export',
      );

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}
