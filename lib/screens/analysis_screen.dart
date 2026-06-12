import 'dart:math';
import 'dart:ui' as ui;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/project_session.dart';
import '../models/measurement_point.dart';
import '../services/csv_export_service.dart';
import '../services/xlsx_export_service.dart';
import '../services/txt_export_service.dart';
import '../services/peak_detection.dart';
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

// ── Annotation entry (per visible cycle/series) ───────────────────────────────
class _AnnEntry {
  final String id;       // '$mIdx:$cNum' for CV, '$mIdx' otherwise
  final Color  color;
  final double eMin;     // data x-range (mV or ms)
  final double eMax;
  _AnnEntry({required this.id, required this.color, required this.eMin, required this.eMax});
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
  final Set<String> _hiddenCycles       = {};
  bool _showSg = true;

  // ── Peak / level state ────────────────────────────────────────────────────
  final List<PeakResult>  _peaks  = [];
  final List<LevelResult> _levels = [];

  // Persisted popup defaults
  double   _lastMinWidthMv        = 20.0;
  double   _lastMinHeightUa       = 0.1;
  double   _lastBaselineRegionPct = 15.0;
  PeakType _lastPeakType          = PeakType.both;
  double   _lastMinDurationS      = 1.0;
  double   _lastMinLevelUa        = 0.1;

  // ── Helpers ───────────────────────────────────────────────────────────────
  String _cycleKey(int m, int c) => '$m:$c';
  bool _isMeasHidden(int i)         => _hiddenMeasurements.contains(i);
  bool _isCycleHidden(int m, int c) => _hiddenCycles.contains(_cycleKey(m, c));

  void _toggleMeas(int i)       => setState(() =>
      _hiddenMeasurements.contains(i) ? _hiddenMeasurements.remove(i) : _hiddenMeasurements.add(i));
  void _toggleCycle(int m, int c) => setState(() {
    final k = _cycleKey(m, c);
    _hiddenCycles.contains(k) ? _hiddenCycles.remove(k) : _hiddenCycles.add(k);
  });

  // ── Peak / level runners ──────────────────────────────────────────────────

  Future<void> _showPeakDialog(ProjectSession project) async {
    final minW   = TextEditingController(text: _lastMinWidthMv.toStringAsFixed(0));
    final minH   = TextEditingController(text: _lastMinHeightUa.toString());
    final basePct= TextEditingController(text: _lastBaselineRegionPct.toStringAsFixed(0));
    var   pType  = _lastPeakType;

    final run = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Detect Peaks', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          _dlgField('Min peak width', 'mV', minW),
          const SizedBox(height: 12),
          _dlgField('Min peak height', 'µA', minH),
          const SizedBox(height: 12),
          _dlgField('Baseline region (each side)', '%', basePct),
          const SizedBox(height: 12),
          DropdownButtonFormField<PeakType>(
            value: pType,
            dropdownColor: AppColors.surface,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: _dlgInputDeco('Peak type'),
            items: const [
              DropdownMenuItem(value: PeakType.both,            child: Text('Both')),
              DropdownMenuItem(value: PeakType.oxidationOnly,   child: Text('Oxidation only')),
              DropdownMenuItem(value: PeakType.reductionOnly,   child: Text('Reduction only')),
            ],
            onChanged: (v) { if (v != null) ss(() => pType = v); },
          ),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true),  child: const Text('Detect')),
        ],
      )),
    );
    if (run != true || !mounted) return;

    setState(() {
      _lastMinWidthMv        = double.tryParse(minW.text)    ?? _lastMinWidthMv;
      _lastMinHeightUa       = double.tryParse(minH.text)    ?? _lastMinHeightUa;
      _lastBaselineRegionPct = double.tryParse(basePct.text) ?? _lastBaselineRegionPct;
      _lastPeakType          = pType;
      _peaks.clear();
      _runDetectPeaks(project);
    });
  }

  void _runDetectPeaks(ProjectSession project) {
    int globalColorIdx = 0;
    for (int mIdx = 0; mIdx < project.measurements.length; mIdx++) {
      if (_isMeasHidden(mIdx)) { globalColorIdx++; continue; }
      final session = project.measurements[mIdx];
      final isCv = session.mode == 'CV';

      if (isCv) {
        final cycles = session.cycles.toList()..sort();
        for (final cNum in cycles) {
          if (_isCycleHidden(mIdx, cNum)) { globalColorIdx++; continue; }
          final cyclePts = session.points.where((p) => p.cycle == cNum).toList();
          if (cyclePts.isNotEmpty) {
            // Use SG data if shown and available
            final ys = _buildYsUa(cyclePts, session, 0);
            final inp = List.generate(cyclePts.length,
                (i) => (eMv: cyclePts[i].x, iUa: ys[i]));
            final res = detectPeaks(
              cycleId:           '$mIdx:$cNum',
              pts:               inp,
              minWidthMv:        _lastMinWidthMv,
              minHeightUa:       _lastMinHeightUa,
              baselineRegionPct: _lastBaselineRegionPct,
              peakType:          _lastPeakType,
            );
            if (res != null) _peaks.add(res);
          }
          globalColorIdx++;
        }
      } else {
        final pts = session.points;
        if (pts.isNotEmpty) {
          final ys  = _buildYsUa(pts, session, 0);
          final inp = List.generate(pts.length, (i) => (eMv: pts[i].x, iUa: ys[i]));
          final res = detectPeaks(
            cycleId:           '$mIdx',
            pts:               inp,
            minWidthMv:        _lastMinWidthMv,
            minHeightUa:       _lastMinHeightUa,
            baselineRegionPct: _lastBaselineRegionPct,
            peakType:          _lastPeakType,
          );
          if (res != null) _peaks.add(res);
        }
        globalColorIdx++;
      }
    }
  }

  Future<void> _showLevelDialog(ProjectSession project) async {
    final minD = TextEditingController(text: _lastMinDurationS.toString());
    final minH = TextEditingController(text: _lastMinLevelUa.toString());

    final run = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Find Levels', style: TextStyle(color: Colors.white)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _dlgField('Min level duration', 's', minD),
          const SizedBox(height: 12),
          _dlgField('Min level height', 'µA', minH),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true),  child: const Text('Find')),
        ],
      ),
    );
    if (run != true || !mounted) return;
    setState(() {
      _lastMinDurationS = double.tryParse(minD.text) ?? _lastMinDurationS;
      _lastMinLevelUa   = double.tryParse(minH.text) ?? _lastMinLevelUa;
      _levels.clear();
      _runFindLevels(project);
    });
  }

  void _runFindLevels(ProjectSession project) {
    for (int mIdx = 0; mIdx < project.measurements.length; mIdx++) {
      if (_isMeasHidden(mIdx)) continue;
      final session = project.measurements[mIdx];
      if (session.points.isEmpty) continue;
      // CA x is in ms; convert to seconds for the algorithm
      final inp = session.points
          .map((p) => (tS: p.x / 1000.0, iUa: p.y / 1000.0))
          .toList();
      final res = findLevels(
        datasetId:    '$mIdx',
        pts:          inp,
        minDurationS: _lastMinDurationS,
        minHeightUa:  _lastMinLevelUa,
      );
      _levels.addAll(res);
    }
  }

  /// Convert a measurement's y values to µA using SG data when available.
  List<double> _buildYsUa(
      List<MeasurementPoint> pts, MeasurementSession session, int offset) {
    if (!session.sgEnabled || !session.hasSgData) {
      return pts.map((p) => p.y / 1000.0).toList();
    }
    return List.generate(pts.length, (i) {
      final idx = offset + i;
      final sg  = idx < session.sgPoints.length ? session.sgPoints[idx] : null;
      return (sg ?? pts[i].y) / 1000.0;
    });
  }

  // ── Dialog widget helpers ─────────────────────────────────────────────────

  static Widget _dlgField(String label, String unit, TextEditingController ctrl) =>
      TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: false),
        style: const TextStyle(color: Colors.white),
        decoration: _dlgInputDeco(label).copyWith(suffixText: unit),
      );

  static InputDecoration _dlgInputDeco(String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: AppColors.textSecondary),
    filled: true,
    fillColor: AppColors.cardBg,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.divider)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.divider)),
  );

  // ── Confirm dialogs ───────────────────────────────────────────────────────

  Future<void> _confirmDeleteMeas(int index, MeasurementProvider provider) async {
    final session = provider.project?.measurements[index];
    if (session == null) return;
    final ok = await _confirmDialog(context,
        'Delete "${session.displayName}"?', 'Remove this measurement? Cannot be undone.');
    if (ok != true || !mounted) return;
    setState(() { _hiddenMeasurements.remove(index); _peaks.removeWhere((p) => p.cycleId.startsWith('$index')); _levels.removeWhere((l) => l.datasetId == '$index'); });
    provider.deleteMeasurement(index);
  }

  Future<void> _confirmDeleteCycle(
      int mIdx, int cNum, MeasurementProvider provider) async {
    final session = provider.project?.measurements[mIdx];
    if (session == null) return;
    final ok = await _confirmDialog(context, 'Delete Cycle $cNum?',
        'Remove cycle $cNum from "${session.displayName}"?');
    if (ok != true || !mounted) return;
    setState(() { _hiddenCycles.remove(_cycleKey(mIdx, cNum)); _peaks.removeWhere((p) => p.cycleId == '$mIdx:$cNum'); });
    provider.deleteCycle(mIdx, cNum);
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
            TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
            ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                onPressed: () => Navigator.of(c).pop(true),
                child: const Text('Delete')),
          ],
        ),
      );

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MeasurementProvider>();
    final project  = provider.project;
    final mode     = provider.selectedMode;
    final isCa     = mode == VoltammetryMode.ca;
    final hasSg    = project?.measurements.any((s) => s.hasSgData) ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text('${mode?.abbreviation ?? ''} Analysis'),
        actions: [
          // ── SG toggle ──────────────────────────────────────────────────
          if (hasSg)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text('SG', style: TextStyle(
                  color: _showSg ? AppColors.accent1 : AppColors.textSecondary,
                  fontSize: 12)),
              Switch(
                value: _showSg,
                onChanged: (v) => setState(() => _showSg = v),
                activeColor: AppColors.accent1,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ]),

          // ── Peak / Level buttons (shown only when data exists) ─────────
          if (project != null && project.measurements.isNotEmpty) ...[
            if (!isCa) ...[
              // Detect Peaks
              IconButton(
                tooltip: 'Detect Peaks',
                onPressed: () => _showPeakDialog(project),
                icon: _compoundIcon(Icons.show_chart, Icons.search,
                    Colors.white, AppColors.accent2),
              ),
              // Remove Peaks
              IconButton(
                tooltip: 'Remove Peaks',
                onPressed: _peaks.isEmpty ? null : () => setState(() => _peaks.clear()),
                icon: _compoundIcon(Icons.show_chart, Icons.close,
                    _peaks.isEmpty ? AppColors.textSecondary : Colors.redAccent,
                    Colors.redAccent),
              ),
            ] else ...[
              // Find Levels
              IconButton(
                tooltip: 'Find Levels',
                onPressed: () => _showLevelDialog(project),
                icon: _compoundIcon(Icons.stacked_line_chart, Icons.search,
                    Colors.white, AppColors.accent2),
              ),
              // Remove Levels
              IconButton(
                tooltip: 'Remove Levels',
                onPressed: _levels.isEmpty ? null : () => setState(() => _levels.clear()),
                icon: _compoundIcon(Icons.stacked_line_chart, Icons.close,
                    _levels.isEmpty ? AppColors.textSecondary : Colors.redAccent,
                    Colors.redAccent),
              ),
            ],
          ],
        ],
      ),
      body: project == null || project.measurements.isEmpty
          ? _empty()
          : Column(children: [
              Expanded(
                flex: 6,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 10, 12, 4),
                  child: RepaintBoundary(
                    child: _OverlayChart(
                      project:            project,
                      hiddenMeasurements: _hiddenMeasurements,
                      hiddenCycles:       _hiddenCycles,
                      isCv:               mode == VoltammetryMode.cv,
                      isCa:               isCa,
                      showSg:             _showSg,
                      xLabel:             mode?.xAxisLabel ?? 'Potential (mV)',
                      yLabel:             mode?.yAxisLabel ?? 'Current (nA)',
                      peaks:              List.unmodifiable(_peaks),
                      levels:             List.unmodifiable(_levels),
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
                    isCv:               mode == VoltammetryMode.cv,
                    hiddenMeasurements: _hiddenMeasurements,
                    hiddenCycles:       _hiddenCycles,
                    onToggleMeas:       _toggleMeas,
                    onToggleCycle:      _toggleCycle,
                    onDeleteMeas:  (i)    => _confirmDeleteMeas(i, provider),
                    onDeleteCycle: (m, c) => _confirmDeleteCycle(m, c, provider),
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
            ]),
    );
  }

  Widget _empty() => const Center(
    child: Text('No measurements in this project.',
        style: TextStyle(color: AppColors.textSecondary)));

  /// Two-icon button widget: base icon + small overlay icon.
  static Widget _compoundIcon(
      IconData base, IconData overlay, Color baseColor, Color overlayColor) {
    return SizedBox(
      width: 24, height: 24,
      child: Stack(children: [
        Icon(base, size: 20, color: baseColor),
        Positioned(
          right: 0, bottom: 0,
          child: Container(
            width: 10, height: 10,
            decoration: BoxDecoration(
                color: AppColors.primary, borderRadius: BorderRadius.circular(5)),
            child: Icon(overlay, size: 9, color: overlayColor),
          ),
        ),
      ]),
    );
  }
}

// ── Overlay chart ─────────────────────────────────────────────────────────────

const double _kAxisNameSize   = 16;
const double _kLeftReserved   = 56;
const double _kBottomReserved = 30;
const double _kTopReserved    = 16;
const double _kRightReserved  = 24;

// Total chart insets (axis name + tick labels)
const double _kLeftInset   = _kAxisNameSize + _kLeftReserved;   // 72
const double _kBottomInset = _kAxisNameSize + _kBottomReserved; // 46
const double _kTopInset    = _kTopReserved;                     // 16
const double _kRightInset  = _kRightReserved;                   // 24

class _OverlayChart extends StatefulWidget {
  const _OverlayChart({
    required this.project,
    required this.hiddenMeasurements,
    required this.hiddenCycles,
    required this.isCv,
    required this.isCa,
    required this.showSg,
    required this.xLabel,
    required this.yLabel,
    required this.peaks,
    required this.levels,
  });

  final ProjectSession  project;
  final Set<int>        hiddenMeasurements;
  final Set<String>     hiddenCycles;
  final bool   isCv;
  final bool   isCa;
  final bool   showSg;
  final String xLabel;
  final String yLabel;
  final List<PeakResult>  peaks;
  final List<LevelResult> levels;

  @override
  State<_OverlayChart> createState() => _OverlayChartState();
}

class _OverlayChartState extends State<_OverlayChart> {
  final Map<String, List<FlSpot>> _spotCache = {};
  final Map<String, int>          _spotLen   = {};
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
    final project  = widget.project;
    final isCv     = widget.isCv;
    final showSg   = widget.showSg;
    final peaks    = widget.peaks;
    final levels   = widget.levels;

    final barMetas      = <_BarMeta>[];
    final bars          = <LineChartBarData>[];
    final annEntries    = <_AnnEntry>[];
    int globalColorIdx  = 0;
    int dataBarCount    = 0; // bars added before annotation bars

    for (int mIdx = 0; mIdx < project.measurements.length; mIdx++) {
      if (widget.hiddenMeasurements.contains(mIdx)) continue;
      final session = project.measurements[mIdx];

      if (isCv) {
        final cycles = session.cycles.toList()..sort();
        int sgOffset = 0;
        for (final cNum in cycles) {
          if (widget.hiddenCycles.contains('$mIdx:$cNum')) { globalColorIdx++; continue; }
          final cyclePts = session.points.where((p) => p.cycle == cNum).toList();
          if (cyclePts.isEmpty) { sgOffset += cyclePts.length; globalColorIdx++; continue; }

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
                spots:    sgSpots,
                isCurved: true,
                curveSmoothness: 0.3,
                color:    color,
                barWidth: 2,
                dotData:  const FlDotData(show: false),
                belowBarData: BarAreaData(show: true, color: color.withOpacity(0.05)),
              ));
              barMetas.add(_BarMeta(mIdx, null));
            }
          }

          // Record annotation entry for this cycle
          if (cyclePts.isNotEmpty) {
            final xs = cyclePts.map((p) => p.x);
            annEntries.add(_AnnEntry(
              id:    '$mIdx:$cNum',
              color: color,
              eMin:  xs.reduce(min),
              eMax:  xs.reduce(max),
            ));
          }
          sgOffset    += cyclePts.length;
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
              spots:    sgSpots,
              isCurved: true,
              curveSmoothness: 0.3,
              color:    color,
              barWidth: 2,
              dotData:  const FlDotData(show: false),
              belowBarData: BarAreaData(show: true, color: color.withOpacity(0.05)),
            ));
            barMetas.add(_BarMeta(mIdx, null));
          }
        }

        final xs = session.points.map((p) => p.x);
        annEntries.add(_AnnEntry(
          id:    '$mIdx',
          color: color,
          eMin:  xs.reduce(min),
          eMax:  xs.reduce(max),
        ));
        globalColorIdx++;
      }
    }

    if (bars.isEmpty) {
      return const Center(
        child: Text('All measurements hidden.',
            style: TextStyle(color: AppColors.textSecondary)));
    }

    dataBarCount = bars.length;

    // ── Baseline / level annotation bars ─────────────────────────────────
    for (final ae in annEntries) {
      // Peak baselines
      for (final pk in peaks) {
        if (pk.cycleId != ae.id) continue;
        final s  = pk.baselineSlope;
        final b  = pk.baselineIntercept;
        // Baseline in nA (chart units): µA × 1000
        bars.add(LineChartBarData(
          spots:    [
            FlSpot(ae.eMin, (s * ae.eMin + b) * 1000),
            FlSpot(ae.eMax, (s * ae.eMax + b) * 1000),
          ],
          isCurved:  false,
          color:     ae.color.withOpacity(0.6),
          barWidth:  1,
          dashArray: [5, 4],
          dotData:   const FlDotData(show: false),
        ));
        barMetas.add(_BarMeta(-1, null));
      }
      // CA level lines
      for (final lv in levels) {
        if (lv.datasetId != ae.id) continue;
        // tStart/tEnd in seconds → ms (chart x-axis is ms for CA)
        final tStartMs = lv.tStartS * 1000;
        final tEndMs   = lv.tEndS   * 1000;
        final iNa      = lv.iMeanUa * 1000; // µA → nA
        bars.add(LineChartBarData(
          spots:    [FlSpot(tStartMs, iNa), FlSpot(tEndMs, iNa)],
          isCurved: false,
          color:    ae.color.withOpacity(0.8),
          barWidth: 2,
          dashArray: [6, 4],
          dotData:  const FlDotData(show: false),
        ));
        barMetas.add(_BarMeta(-1, null));
      }
    }

    // ── Axis bounds ───────────────────────────────────────────────────────
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
      final allSpots = bars.take(dataBarCount).expand((b) => b.spots).toList();
      final xs = allSpots.map((s) => s.x);
      final ys = allSpots.map((s) => s.y);
      minX = xs.reduce(min); maxX = xs.reduce(max);
      minY = ys.reduce(min); maxY = ys.reduce(max);
    }
    final xPad = max((maxX - minX) * 0.08, 1.0);
    final yPad = max((maxY - minY) * 0.12, 0.1);
    final axisMinX = minX - xPad; final axisMaxX = maxX + xPad;
    final axisMinY = minY - yPad; final axisMaxY = maxY + yPad;

    final tickStyle    = const TextStyle(color: AppColors.textSecondary, fontSize: 10);
    final nameStyle    = const TextStyle(color: AppColors.textSecondary, fontSize: 11);

    final chart = LineChart(
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
        borderData: FlBorderData(show: true, border: Border.all(color: AppColors.divider)),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            axisNameSize:   _kAxisNameSize,
            axisNameWidget: Text(widget.yLabel, style: nameStyle),
            sideTitles: SideTitles(
              showTitles: true, reservedSize: _kLeftReserved,
              getTitlesWidget: (v, _) => Text(v.toStringAsFixed(1), style: tickStyle),
            ),
          ),
          bottomTitles: AxisTitles(
            axisNameSize:   _kAxisNameSize,
            axisNameWidget: Text(widget.xLabel, style: nameStyle),
            sideTitles: SideTitles(
              showTitles: true, reservedSize: _kBottomReserved,
              getTitlesWidget: (v, _) => Text(v.toStringAsFixed(0), style: tickStyle),
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: _kRightReserved,
                getTitlesWidget: _emptyTitle)),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: _kTopReserved,
                getTitlesWidget: _emptyTitle)),
        ),
        minX: axisMinX, maxX: axisMaxX, minY: axisMinY, maxY: axisMaxY,
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.surface,
            getTooltipItems: (spots) => spots.map((s) {
              if (s.barIndex >= dataBarCount) {
                // Annotation bar — suppress tooltip
                return LineTooltipItem('', const TextStyle());
              }
              if (s.barIndex >= barMetas.length) {
                return LineTooltipItem('', const TextStyle());
              }
              final meta    = barMetas[s.barIndex];
              if (meta.measurementIdx < 0) return LineTooltipItem('', const TextStyle());
              final session = project.measurements[meta.measurementIdx];
              final label   = meta.cycleNum != null
                  ? '${session.displayName} · C${meta.cycleNum}'
                  : session.displayName;
              return LineTooltipItem(
                '$label\n${s.x.toStringAsFixed(1)}\n${s.y.toStringAsFixed(3)} nA',
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

    // Overlay tick marks and label chips via custom paint.
    return LayoutBuilder(builder: (ctx, box) {
      return Stack(children: [
        chart,
        CustomPaint(
          size: Size(box.maxWidth, box.maxHeight),
          painter: _AnnotationPainter(
            annEntries: annEntries,
            peaks:      peaks,
            levels:     levels,
            isCa:       widget.isCa,
            axisMinX:   axisMinX, axisMaxX: axisMaxX,
            axisMinY:   axisMinY, axisMaxY: axisMaxY,
          ),
        ),
      ]);
    });
  }
}

Widget _emptyTitle(double value, TitleMeta meta) => const SizedBox.shrink();

// ── Annotation painter ────────────────────────────────────────────────────────

class _AnnotationPainter extends CustomPainter {
  _AnnotationPainter({
    required this.annEntries,
    required this.peaks,
    required this.levels,
    required this.isCa,
    required this.axisMinX, required this.axisMaxX,
    required this.axisMinY, required this.axisMaxY,
  });

  final List<_AnnEntry>   annEntries;
  final List<PeakResult>  peaks;
  final List<LevelResult> levels;
  final bool isCa;
  final double axisMinX, axisMaxX, axisMinY, axisMaxY;

  @override
  void paint(Canvas canvas, Size size) {
    final chartLeft   = _kLeftInset;
    final chartRight  = size.width  - _kRightInset;
    final chartTop    = _kTopInset;
    final chartBottom = size.height - _kBottomInset;
    final chartW = chartRight - chartLeft;
    final chartH = chartBottom - chartTop;
    if (chartW <= 0 || chartH <= 0) return;

    double px(double dataX) =>
        chartLeft + (dataX - axisMinX) / (axisMaxX - axisMinX) * chartW;
    double py(double dataY) =>
        chartTop  + (axisMaxY - dataY) / (axisMaxY - axisMinY) * chartH;

    for (final ae in annEntries) {
      // ── Peak annotations ────────────────────────────────────────────────
      for (final pk in peaks) {
        if (pk.cycleId != ae.id) continue;
        _drawPeakAnn(canvas, size, ae.color, pk, px, py);
      }
      // ── Level chip annotations ──────────────────────────────────────────
      for (final lv in levels) {
        if (lv.datasetId != ae.id) continue;
        _drawLevelAnn(canvas, ae.color, lv, px, py);
      }
    }
  }

  void _drawPeakAnn(Canvas canvas, Size size, Color color, PeakResult pk,
      double Function(double) px, double Function(double) py) {
    final tickPaint = Paint()
      ..color     = color
      ..strokeWidth = 1.5
      ..style     = PaintingStyle.stroke;

    // Anodic
    if (pk.eAnodicMv != null && pk.iRawAnodicUa != null && pk.ipaUa != null) {
      final x  = px(pk.eAnodicMv!);
      final y  = py(pk.iRawAnodicUa! * 1000); // µA → nA for chart
      canvas.drawLine(Offset(x, y - 8), Offset(x, y + 4), tickPaint);
      final label = 'Ipa ${pk.ipaUa!.toStringAsFixed(2)} µA';
      _drawChip(canvas, color, label, x, y - 12);
    }

    // Cathodic
    if (pk.eCathodicMv != null && pk.iRawCathodicUa != null && pk.ipcUa != null) {
      final x  = px(pk.eCathodicMv!);
      final y  = py(pk.iRawCathodicUa! * 1000);
      canvas.drawLine(Offset(x, y - 4), Offset(x, y + 8), tickPaint);
      final label = 'Ipc ${pk.ipcUa!.toStringAsFixed(2)} µA';
      _drawChip(canvas, color, label, x, y + 10);
    }
  }

  void _drawLevelAnn(Canvas canvas, Color color, LevelResult lv,
      double Function(double) px, double Function(double) py) {
    // CA: x-axis is ms in chart; tStart/tEnd stored in seconds
    final xMid = px((lv.tStartS * 1000 + lv.tEndS * 1000) / 2);
    final yPos  = py(lv.iMeanUa * 1000); // µA → nA
    final label = 'I ${lv.iMeanUa.toStringAsFixed(2)} µA';
    _drawChip(canvas, color, label, xMid, yPos - 16);
  }

  void _drawChip(Canvas canvas, Color color, String label,
      double cx, double topY) {
    final span = TextSpan(
      text:  label,
      style: const TextStyle(color: Colors.white, fontSize: 10,
          fontWeight: FontWeight.w500),
    );
    final tp = TextPainter(text: span, textDirection: ui.TextDirection.ltr);
    tp.layout();

    final padH = 5.0, padV = 3.0;
    final chipW = tp.width + padH * 2;
    final chipH = tp.height + padV * 2;
    final left  = cx - chipW / 2;

    final bgPaint = Paint()..color = color.withOpacity(0.8);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(left, topY, chipW, chipH),
          const Radius.circular(4)),
      bgPaint,
    );
    tp.paint(canvas, Offset(left + padH, topY + padV));
  }

  @override
  bool shouldRepaint(_AnnotationPainter old) =>
      old.peaks != peaks ||
      old.levels != levels ||
      old.axisMinX != axisMinX || old.axisMaxX != axisMaxX ||
      old.axisMinY != axisMinY || old.axisMaxY != axisMaxY;
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

  final ProjectSession       project;
  final MeasurementProvider  provider;
  final bool                 isCv;
  final Set<int>             hiddenMeasurements;
  final Set<String>          hiddenCycles;
  final void Function(int)       onToggleMeas;
  final void Function(int, int)  onToggleCycle;
  final void Function(int)       onDeleteMeas;
  final void Function(int, int)  onDeleteCycle;

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
                  color: isHidden ? AppColors.textSecondary : AppColors.accent2, size: 20),
              title: Text(session.displayName,
                  style: TextStyle(
                    color:      isHidden ? AppColors.textSecondary : Colors.white,
                    fontSize:   14,
                    fontWeight: FontWeight.w600,
                  )),
              subtitle: session.label.isNotEmpty
                  ? Text(session.label,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11))
                  : null,
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  icon: Icon(
                    isHidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    size: 18,
                    color: isHidden ? AppColors.textSecondary : AppColors.accent1,
                  ),
                  onPressed: () => onToggleMeas(mIdx),
                  tooltip: isHidden ? 'Show' : 'Hide',
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                  onPressed: () => onDeleteMeas(mIdx),
                  tooltip: 'Delete measurement',
                ),
              ]),
              children: [
                _CycleDropdown(
                  mIdx:         mIdx,
                  cycles:       cycles,
                  hiddenCycles: hiddenCycles,
                  onToggle:     onToggleCycle,
                  onDelete:     onDeleteCycle,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Cycle dropdown widget (replaces individual cycle rows) ────────────────────

class _CycleDropdown extends StatelessWidget {
  const _CycleDropdown({
    required this.mIdx,
    required this.cycles,
    required this.hiddenCycles,
    required this.onToggle,
    required this.onDelete,
  });

  final int           mIdx;
  final List<int>     cycles;
  final Set<String>   hiddenCycles;
  final void Function(int mIdx, int cNum) onToggle;
  final void Function(int mIdx, int cNum) onDelete;

  @override
  Widget build(BuildContext context) {
    final visCount = cycles.where((c) => !hiddenCycles.contains('$mIdx:$c')).length;

    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 8, bottom: 8),
      child: Row(children: [
        PopupMenuButton<int>(
          onSelected: (cNum) => onToggle(mIdx, cNum),
          color: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          itemBuilder: (ctx) => cycles.map((cNum) {
            final visible = !hiddenCycles.contains('$mIdx:$cNum');
            final color   = kCycleColors[(cNum - 1) % kCycleColors.length];
            return CheckedPopupMenuItem<int>(
              value:   cNum,
              checked: visible,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text('Cycle $cNum',
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
              ]),
            );
          }).toList(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              border:       Border.all(color: AppColors.divider),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(
                'Cycles ($visCount / ${cycles.length} visible)',
                style: const TextStyle(color: AppColors.accent2, fontSize: 12),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_drop_down, color: AppColors.accent2, size: 18),
            ]),
          ),
        ),
        const Spacer(),
        // Per-cycle delete: open a small menu to pick which cycle to delete
        PopupMenuButton<int>(
          tooltip: 'Delete a cycle',
          color:   AppColors.surface,
          shape:   RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
          onSelected: (cNum) => onDelete(mIdx, cNum),
          itemBuilder: (ctx) => cycles.map((cNum) => PopupMenuItem<int>(
            value: cNum,
            child: Text('Delete Cycle $cNum',
                style: const TextStyle(color: Colors.white, fontSize: 13)),
          )).toList(),
        ),
      ]),
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
            color: visible ? colorDot : AppColors.divider,
            shape: BoxShape.circle,
          ),
        ),
        title: Text(label,
            style: TextStyle(
                color:    visible ? Colors.white : AppColors.textSecondary,
                fontSize: indent  ? 13 : 14)),
        subtitle: sublabel != null
            ? Text(sublabel!, style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 11))
            : null,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            icon: Icon(
              visible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              size: 18,
              color: visible ? AppColors.accent1 : AppColors.textSecondary,
            ),
            onPressed: onToggle,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
            onPressed: onDelete,
          ),
        ]),
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
  Widget build(BuildContext context) => Container(
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

// ── Export format picker ──────────────────────────────────────────────────────

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
                color: AppColors.divider, borderRadius: BorderRadius.circular(2)),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Export File',
                  style: TextStyle(color: Colors.white, fontSize: 17,
                      fontWeight: FontWeight.bold)),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Text(_error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ),
          if (_exporting)
            const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())
          else ...[
            ListTile(
              leading:  const Icon(Icons.table_chart, color: AppColors.accent2),
              title:    const Text('CSV', style: TextStyle(color: Colors.white)),
              subtitle: const Text('UTF-16 LE, PalmSens-compatible',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
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
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
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
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              onTap: () => _run(() => TxtExportService.export(widget.project)),
            ),
          ],
        ]),
      );
}
