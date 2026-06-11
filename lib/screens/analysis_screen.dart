import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/project_session.dart';
import '../models/measurement_point.dart';
import '../services/csv_export_service.dart';
import '../services/xlsx_export_service.dart';
import '../services/txt_export_service.dart';
import '../models/voltammetry_mode.dart';
import '../providers/measurement_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/cv_chart.dart';
import 'parameters_screen.dart';

// ── Bar metadata for touch tooltip ───────────────────────────────────────────
class _BarMeta {
  final int  measurementIdx;
  final int? cycleNum;
  _BarMeta(this.measurementIdx, this.cycleNum);
}

// ── AnalysisScreen ────────────────────────────────────────────────────────────
class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key, this.isImportedSession = false});
  final bool isImportedSession;

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  final Set<int>    _hiddenMeasurements = {};
  final Set<String> _hiddenCycles       = {}; // "measIdx:cycleNum"
  bool _showSg = true;

  String _cycleKey(int mIdx, int cNum) => '$mIdx:$cNum';

  bool _isMeasHidden(int i)         => _hiddenMeasurements.contains(i);
  bool _isCycleHidden(int m, int c) => _hiddenCycles.contains(_cycleKey(m, c));

  void _toggleMeas(int i) => setState(() => _hiddenMeasurements.contains(i)
      ? _hiddenMeasurements.remove(i)
      : _hiddenMeasurements.add(i));

  void _toggleCycle(int m, int c) => setState(() {
        final k = _cycleKey(m, c);
        _hiddenCycles.contains(k) ? _hiddenCycles.remove(k) : _hiddenCycles.add(k);
      });

  // ── Confirm dialogs ────────────────────────────────────────────────────────

  Future<void> _confirmDeleteMeas(int index, MeasurementProvider provider) async {
    final session = provider.project?.measurements[index];
    if (session == null) return;
    final confirmed = await _confirmDialog(
        context, 'Delete "${session.displayName}"?',
        'Remove this measurement? Cannot be undone.');
    if (confirmed != true || !mounted) return;
    setState(() => _hiddenMeasurements.remove(index));
    provider.deleteMeasurement(index);
  }

  Future<void> _confirmDeleteCycle(
      int measIdx, int cycleNum, MeasurementProvider provider) async {
    final session = provider.project?.measurements[measIdx];
    if (session == null) return;
    final confirmed = await _confirmDialog(context, 'Delete Cycle $cycleNum?',
        'Remove all data for cycle $cycleNum from "${session.displayName}"?');
    if (confirmed != true || !mounted) return;
    setState(() => _hiddenCycles.remove(_cycleKey(measIdx, cycleNum)));
    provider.deleteCycle(measIdx, cycleNum);
  }

  Future<bool?> _confirmDialog(BuildContext ctx, String title, String body) =>
      showDialog<bool>(
        context: ctx,
        builder: (c) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title:   Text(title, style: const TextStyle(color: Colors.white)),
          content: Text(body,  style: const TextStyle(color: AppColors.textSecondary)),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(c).pop(false),
                child: const Text('Cancel')),
            ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                onPressed: () => Navigator.of(c).pop(true),
                child: const Text('Delete')),
          ],
        ),
      );

  // ── Build ──────────────────────────────────────────────────────────────────

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
                Expanded(
                  flex: 6,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 10, 12, 4),
                    child: RepaintBoundary(
                      child: _OverlayChart(
                        project:            project,
                        hiddenMeasurements: _hiddenMeasurements,
                        hiddenCycles:       _hiddenCycles,
                        isCv:               isCv,
                        showSg:             _showSg,
                        xLabel: mode?.xAxisLabel ?? 'Potential (mV)',
                        yLabel: mode?.yAxisLabel ?? 'Current (nA)',
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: RepaintBoundary(
                    child: _MeasurementTree(
                      project:            project,
                      provider:           provider,
                      isCv:               isCv,
                      hiddenMeasurements: _hiddenMeasurements,
                      hiddenCycles:       _hiddenCycles,
                      onToggleMeas:       _toggleMeas,
                      onToggleCycle:      _toggleCycle,
                      onDeleteMeas:  (i)      => _confirmDeleteMeas(i, provider),
                      onDeleteCycle: (m, c)   => _confirmDeleteCycle(m, c, provider),
                    ),
                  ),
                ),
                if (!widget.isImportedSession)
                  _BottomBar(
                    provider:           provider,
                    project:            project,
                    mode:               mode,
                    hiddenMeasurements: _hiddenMeasurements,
                    hiddenCycles:       _hiddenCycles,
                  ),
              ],
            ),
    );
  }

  Widget _empty() => const Center(
        child: Text('No measurements in this project.',
            style: TextStyle(color: AppColors.textSecondary)),
      );
}

// ── Overlay chart ─────────────────────────────────────────────────────────────

const double _kAxisNameSize   = 16;
const double _kLeftReserved   = 56;
const double _kBottomReserved = 30;
const double _kTopReserved    = 16;
const double _kRightReserved  = 24;

class _OverlayChart extends StatefulWidget {
  const _OverlayChart({
    required this.project,
    required this.hiddenMeasurements,
    required this.hiddenCycles,
    required this.isCv,
    required this.showSg,
    required this.xLabel,
    required this.yLabel,
  });

  final ProjectSession  project;
  final Set<int>        hiddenMeasurements;
  final Set<String>     hiddenCycles;
  final bool   isCv;
  final bool   showSg;
  final String xLabel;
  final String yLabel;

  @override
  State<_OverlayChart> createState() => _OverlayChartState();
}

class _OverlayChartState extends State<_OverlayChart> {
  // ── FlSpot cache — invalidated per-series when point count changes ──────────
  final Map<String, List<FlSpot>> _spotCache = {};
  final Map<String, int>          _spotLen   = {};

  // ── Axis bounds cache — recomputed only when spot cache is invalidated ──────
  double? _axisMinX, _axisMaxX, _axisMinY, _axisMaxY;
  bool    _axisDirty = true;

  List<FlSpot> _cachedSpots(String key, List<MeasurementPoint> pts) {
    if (_spotLen[key] != pts.length) {
      _spotCache[key] = List<FlSpot>.unmodifiable(
          pts.map((p) => FlSpot(p.x, p.y)));
      _spotLen[key]   = pts.length;
      _axisDirty      = true;
    }
    return _spotCache[key]!;
  }

  @override
  Widget build(BuildContext context) {
    final project            = widget.project;
    final hiddenMeasurements = widget.hiddenMeasurements;
    final hiddenCycles       = widget.hiddenCycles;
    final isCv               = widget.isCv;
    final showSg             = widget.showSg;
    final xLabel             = widget.xLabel;
    final yLabel             = widget.yLabel;

    final barMetas      = <_BarMeta>[];
    final bars          = <LineChartBarData>[];
    int globalColorIdx  = 0;

    for (int mIdx = 0; mIdx < project.measurements.length; mIdx++) {
      if (hiddenMeasurements.contains(mIdx)) continue;
      final session = project.measurements[mIdx];

      if (isCv) {
        final cycles = session.cycles.toList()..sort();
        for (final cNum in cycles) {
          if (hiddenCycles.contains('$mIdx:$cNum')) { globalColorIdx++; continue; }
          final cyclePts = session.points.where((p) => p.cycle == cNum).toList();
          if (cyclePts.isEmpty) { globalColorIdx++; continue; }

          final color    = kCycleColors[globalColorIdx % kCycleColors.length];
          final hasSgNow = showSg && cNum == 1 && session.hasSgData;
          bars.add(LineChartBarData(
            spots:           _cachedSpots('$mIdx:$cNum', cyclePts),
            isCurved:        true,
            curveSmoothness: 0.2,
            color:           hasSgNow ? color.withOpacity(0.3) : color,
            barWidth:        hasSgNow ? 1.5 : 2,
            dotData:         const FlDotData(show: false),
            belowBarData:    BarAreaData(show: !hasSgNow, color: color.withOpacity(0.05)),
          ));
          barMetas.add(_BarMeta(mIdx, cNum));

          if (hasSgNow) {
            final sgSpots = <FlSpot>[];
            for (int i = 0; i < cyclePts.length && i < session.sgPoints.length; i++) {
              final sg = session.sgPoints[i];
              if (sg != null) sgSpots.add(FlSpot(cyclePts[i].x, sg));
            }
            if (sgSpots.isNotEmpty) {
              bars.add(LineChartBarData(
                spots:           sgSpots,
                isCurved:        true,
                curveSmoothness: 0.3,
                color:           color,
                barWidth:        2,
                dotData:         const FlDotData(show: false),
                belowBarData:    BarAreaData(show: true, color: color.withOpacity(0.05)),
              ));
              barMetas.add(_BarMeta(mIdx, null));
            }
          }
          globalColorIdx++;
        }
      } else {
        if (session.points.isEmpty) { globalColorIdx++; continue; }
        final color    = kCycleColors[globalColorIdx % kCycleColors.length];
        final hasSgNow = showSg && session.hasSgData;
        bars.add(LineChartBarData(
          spots:           _cachedSpots('$mIdx', session.points),
          isCurved:        true,
          curveSmoothness: 0.2,
          color:           hasSgNow ? color.withOpacity(0.3) : color,
          barWidth:        hasSgNow ? 1.5 : 2,
          dotData:         const FlDotData(show: false),
          belowBarData:    BarAreaData(show: !hasSgNow, color: color.withOpacity(0.05)),
        ));
        barMetas.add(_BarMeta(mIdx, null));
        if (hasSgNow) {
          final pts     = session.points;
          final sgSpots = <FlSpot>[];
          for (int i = 0; i < pts.length && i < session.sgPoints.length; i++) {
            final sg = session.sgPoints[i];
            if (sg != null) sgSpots.add(FlSpot(pts[i].x, sg));
          }
          if (sgSpots.isNotEmpty) {
            bars.add(LineChartBarData(
              spots:           sgSpots,
              isCurved:        true,
              curveSmoothness: 0.3,
              color:           color,
              barWidth:        2,
              dotData:         const FlDotData(show: false),
              belowBarData:    BarAreaData(show: true, color: color.withOpacity(0.05)),
            ));
            barMetas.add(_BarMeta(mIdx, null));
          }
        }
        globalColorIdx++;
      }
    }

    if (bars.isEmpty) {
      return const Center(
        child: Text('All measurements hidden.',
            style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    // Recompute axis bounds only when cached spot lists changed.
    if (_axisDirty) {
      _axisDirty = false;
      double? rxMin, rxMax, ryMin, ryMax;
      for (final spots in _spotCache.values) {
        for (final s in spots) {
          if (rxMin == null || s.x < rxMin) rxMin = s.x;
          if (rxMax == null || s.x > rxMax) rxMax = s.x;
          if (ryMin == null || s.y < ryMin) ryMin = s.y;
          if (ryMax == null || s.y > ryMax) ryMax = s.y;
        }
      }
      if (rxMin != null) {
        _axisMinX = rxMin; _axisMaxX = rxMax;
        _axisMinY = ryMin; _axisMaxY = ryMax;
      }
    }

    double minX, maxX, minY, maxY;
    if (_axisMinX != null) {
      minX = _axisMinX!; maxX = _axisMaxX!;
      minY = _axisMinY!; maxY = _axisMaxY!;
    } else {
      final allSpots = bars.expand((b) => b.spots).toList();
      final xs = allSpots.map((s) => s.x);
      final ys = allSpots.map((s) => s.y);
      minX = xs.reduce(min); maxX = xs.reduce(max);
      minY = ys.reduce(min); maxY = ys.reduce(max);
    }
    final xPad = max((maxX - minX) * 0.08, 1.0);
    final yPad = max((maxY - minY) * 0.12, 0.1);

    final tickStyle     = const TextStyle(color: AppColors.textSecondary, fontSize: 10);
    final axisNameStyle = const TextStyle(color: AppColors.textSecondary, fontSize: 11);

    return LineChart(
      LineChartData(
        backgroundColor: AppColors.cardBg,
        clipData:        const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: AppColors.chartGrid, strokeWidth: 0.8),
          getDrawingVerticalLine:   (_) =>
              const FlLine(color: AppColors.chartGrid, strokeWidth: 0.8),
        ),
        borderData: FlBorderData(
            show: true,
            border: Border.all(color: AppColors.divider)),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            axisNameSize:   _kAxisNameSize,
            axisNameWidget: Text(yLabel, style: axisNameStyle),
            sideTitles: SideTitles(
              showTitles:   true,
              reservedSize: _kLeftReserved,
              getTitlesWidget: (v, _) =>
                  Text(v.toStringAsFixed(1), style: tickStyle),
            ),
          ),
          bottomTitles: AxisTitles(
            axisNameSize:   _kAxisNameSize,
            axisNameWidget: Text(xLabel, style: axisNameStyle),
            sideTitles: SideTitles(
              showTitles:   true,
              reservedSize: _kBottomReserved,
              getTitlesWidget: (v, _) =>
                  Text(v.toStringAsFixed(0), style: tickStyle),
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(
                showTitles:   true,
                reservedSize: _kRightReserved,
                getTitlesWidget: _emptyTitle),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(
                showTitles:   true,
                reservedSize: _kTopReserved,
                getTitlesWidget: _emptyTitle),
          ),
        ),
        minX: minX - xPad, maxX: maxX + xPad,
        minY: minY - yPad, maxY: maxY + yPad,
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.surface,
            getTooltipItems: (spots) => spots.map((s) {
              if (s.barIndex >= barMetas.length) {
                return LineTooltipItem('', const TextStyle());
              }
              final meta    = barMetas[s.barIndex];
              final session = project.measurements[meta.measurementIdx];
              final label   = meta.cycleNum != null
                  ? '${session.displayName} · C${meta.cycleNum}'
                  : session.displayName;
              return LineTooltipItem(
                '$label\n${s.x.toStringAsFixed(1)} mV\n${s.y.toStringAsFixed(3)} nA',
                TextStyle(
                    color: kCycleColors[s.barIndex % kCycleColors.length],
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

Widget _emptyTitle(double value, TitleMeta meta) => const SizedBox.shrink();

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
  final void Function(int)     onToggleMeas;
  final void Function(int, int) onToggleCycle;
  final void Function(int)     onDeleteMeas;
  final void Function(int, int) onDeleteCycle;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.divider))),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: project.measurements.length,
        itemBuilder: (ctx, mIdx) {
          final session  = project.measurements[mIdx];
          final isHidden = hiddenMeasurements.contains(mIdx);

          if (!isCv || session.cycles.isEmpty) {
            return _MeasRow(
              label:    session.displayName,
              sublabel: session.label.isNotEmpty ? session.label : null,
              visible:  !isHidden,
              colorDot: kCycleColors[mIdx % kCycleColors.length],
              onToggle: () => onToggleMeas(mIdx),
              onDelete: () => onDeleteMeas(mIdx),
            );
          }

          final cycles = session.cycles.toList()..sort();
          return Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              leading: Icon(Icons.expand_more,
                  color: isHidden ? AppColors.textSecondary : AppColors.accent2,
                  size: 20),
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
                final color     = kCycleColors[(cNum - 1) % kCycleColors.length];
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
        contentPadding: EdgeInsets.only(left: indent ? 32.0 : 12.0, right: 4),
        leading: Container(
          width: 10, height: 10,
          decoration: BoxDecoration(
            color:  visible ? colorDot : AppColors.divider,
            shape:  BoxShape.circle,
          ),
        ),
        title: Text(label,
            style: TextStyle(
                color:    visible ? Colors.white : AppColors.textSecondary,
                fontSize: indent ? 13 : 14)),
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
                size:  18,
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
    required this.hiddenMeasurements,
    required this.hiddenCycles,
  });

  final MeasurementProvider provider;
  final ProjectSession       project;
  final VoltammetryMode?     mode;
  final Set<int>             hiddenMeasurements;
  final Set<String>          hiddenCycles;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      decoration: const BoxDecoration(
        color:  AppColors.primary,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _showExportSheet(context),
            icon:  const Icon(Icons.save_alt, size: 18),
            label: const Text('Export File'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton(
            onPressed: () {
              provider.resetMeasurement();
              if (mode != null) {
                Navigator.push(context,
                    MaterialPageRoute(
                        builder: (_) => ParametersScreen(mode: mode!)));
              }
            },
            child: const Text('+ New'),
          ),
        ),
      ]),
    );
  }

  void _showExportSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => _ExportFormatSheet(
        project:            project,
        hiddenMeasurements: hiddenMeasurements,
        hiddenCycles:       hiddenCycles,
      ),
    );
  }
}

// ── Export format picker sheet ────────────────────────────────────────────────
class _ExportFormatSheet extends StatefulWidget {
  const _ExportFormatSheet({
    required this.project,
    required this.hiddenMeasurements,
    required this.hiddenCycles,
  });

  final ProjectSession project;
  final Set<int>       hiddenMeasurements;
  final Set<String>    hiddenCycles;

  @override
  State<_ExportFormatSheet> createState() => _ExportFormatSheetState();
}

class _ExportFormatSheetState extends State<_ExportFormatSheet> {
  bool    _exporting = false;
  String? _error;

  Future<void> _run(Future<void> Function() fn) async {
    setState(() { _exporting = true; _error = null; });
    try {
      await fn();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            width: 36, height: 4,
            decoration: BoxDecoration(
                color:        AppColors.divider,
                borderRadius: BorderRadius.circular(2)),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Export File',
                  style: TextStyle(
                      color:      Colors.white,
                      fontSize:   17,
                      fontWeight: FontWeight.bold)),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Text(_error!,
                  style: const TextStyle(
                      color: Colors.redAccent, fontSize: 12)),
            ),
          if (_exporting)
            const Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            )
          else ...[
            ListTile(
              leading:  const Icon(Icons.table_chart, color: AppColors.accent2),
              title:    const Text('CSV', style: TextStyle(color: Colors.white)),
              subtitle: const Text('UTF-16 LE, PalmSens-compatible',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
              onTap: () => _run(() => CsvExportService.export(
                widget.project,
                hiddenMeasurements: widget.hiddenMeasurements,
                hiddenCycles:       widget.hiddenCycles,
              )),
            ),
            ListTile(
              leading:  const Icon(Icons.grid_on, color: AppColors.accent2),
              title:    const Text('XLSX', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Excel workbook',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
              onTap: () => _run(() => XlsxExportService.export(
                widget.project,
                hiddenMeasurements: widget.hiddenMeasurements,
                hiddenCycles:       widget.hiddenCycles,
              )),
            ),
            ListTile(
              leading:  const Icon(Icons.text_snippet, color: AppColors.accent2),
              title:    const Text('TXT', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Plain text (PalmSens-compatible)',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
              onTap: () => _run(() => TxtExportService.export(widget.project)),
            ),
          ],
        ]),
      );
}
