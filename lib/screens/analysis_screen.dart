import 'dart:math';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/project_session.dart';
import '../services/peak_finder.dart';
import '../models/voltammetry_mode.dart';
import '../providers/measurement_provider.dart';
import '../services/palmsens_csv_service.dart';
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

/// Stable key identifying a detected peak across rebuilds.
String _peakKey(PeakResult pk) =>
    '${pk.measurementIdx}:${pk.cycleNum}:${pk.label}';

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
  bool _showSg     = true;
  bool _exportMode = false; // temporarily true while capturing export PNG

  List<PeakResult> _detectedPeaks = [];
  List<PeakResult> _initialPeaks  = []; // first auto-detection snapshot for Reset
  PeakResult?      _previewPeak;        // live preview while editing

  /// User-dragged bubble offsets keyed by _peakKey(pk).
  final Map<String, Offset> _bubbleOffsets = {};

  ProjectSession?  _lastProjectRef;
  String?          _lastTechnique;

  final GlobalKey _chartKey = GlobalKey(); // RepaintBoundary key for capture

  String _cycleKey(int mIdx, int cNum) => '$mIdx:$cNum';

  static bool _samePeak(PeakResult a, PeakResult b) =>
      a.measurementIdx == b.measurementIdx &&
      a.cycleNum == b.cycleNum &&
      a.label == b.label;

  bool _isMeasHidden(int i)    => _hiddenMeasurements.contains(i);
  bool _isCycleHidden(int m, int c) => _hiddenCycles.contains(_cycleKey(m, c));

  void _toggleMeas(int i) => setState(() => _hiddenMeasurements.contains(i)
      ? _hiddenMeasurements.remove(i) : _hiddenMeasurements.add(i));

  void _toggleCycle(int m, int c) => setState(() {
        final k = _cycleKey(m, c);
        _hiddenCycles.contains(k) ? _hiddenCycles.remove(k) : _hiddenCycles.add(k);
      });

  // ── Peak detection ─────────────────────────────────────────────────────────

  void _maybeRedetect(ProjectSession? project, String? technique) {
    if (project == null || technique == null) return;
    if (identical(project, _lastProjectRef) && technique == _lastTechnique) return;
    _lastProjectRef = project;
    _lastTechnique  = technique;
    final fresh = <PeakResult>[];
    for (int i = 0; i < project.measurements.length; i++) {
      fresh.addAll(PeakFinder.analyze(project.measurements[i], i, technique));
    }
    _initialPeaks = List<PeakResult>.from(fresh);
    _detectedPeaks = fresh.map((newPk) => _detectedPeaks.firstWhere(
          (old) => _samePeak(old, newPk) && !old.isAuto,
          orElse: () => newPk,
        )).toList();
  }

  List<PeakResult> get _effectivePeaks {
    final preview = _previewPeak;
    if (preview == null) return _detectedPeaks;
    return _detectedPeaks
        .map((p) => _samePeak(p, preview) ? preview : p)
        .toList();
  }

  void _replacePeak(PeakResult updated) {
    setState(() {
      final idx = _detectedPeaks.indexWhere((p) => _samePeak(p, updated));
      if (idx >= 0) _detectedPeaks[idx] = updated;
    });
  }

  // Called by the draggable bubble overlay.
  void _bubbleMoved(String key, Offset delta) {
    setState(() {
      _bubbleOffsets[key] = (_bubbleOffsets[key] ?? Offset.zero) + delta;
    });
  }

  // ── Peak edit sheet ─────────────────────────────────────────────────────────

  void _showPeakEditSheet(BuildContext context, PeakResult peak,
      ProjectSession project, String technique) {
    final session = project.measurements[peak.measurementIdx];
    final seriesPts = peak.cycleNum != null
        ? session.points.where((p) => p.cycle == peak.cycleNum).toList()
        : session.points;
    final xV  = seriesPts.map((p) => p.x / 1000).toList();
    final yUa = seriesPts.map((p) => p.y / 1000).toList();

    final initial = _initialPeaks.firstWhere(
      (p) => _samePeak(p, peak),
      orElse: () => peak,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.42,
        minChildSize:     0.35,
        maxChildSize:     0.65,
        expand: false,
        builder: (_, ctrl) => Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SingleChildScrollView(
            controller: ctrl,
            child: _PeakEditSheet(
              peak: peak,
              initialPeak: initial,
              xV: xV,
              yUa: yUa,
              onPreview: (p) => setState(() => _previewPeak = p),
              onApply: _replacePeak,
            ),
          ),
        ),
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _previewPeak = null);
    });
  }

  // ── Save chart image (export-styled) ───────────────────────────────────────

  Future<void> _saveChartImage() async {
    final mode = context.read<MeasurementProvider>().selectedMode;
    final tech = mode?.abbreviation ?? 'EbStat';

    // Switch chart to export theme, wait one frame to repaint, capture, restore.
    setState(() => _exportMode = true);
    await Future.delayed(const Duration(milliseconds: 80));

    try {
      final boundary = _chartKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        _snack('Chart not ready to capture.');
        return;
      }
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        _snack('Failed to encode image.');
        return;
      }
      final pngBytes = byteData.buffer.asUint8List();

      final fileName = 'EbStat_${tech}_${_imgTimestamp(DateTime.now())}.png';
      Directory dir = await getApplicationDocumentsDirectory();
      try {
        final ext = await getExternalStorageDirectory();
        if (ext != null) dir = ext;
      } catch (_) {/* keep docs dir */}
      final picsDir = Directory('${dir.path}/Pictures');
      if (!await picsDir.exists()) await picsDir.create(recursive: true);
      final file = File('${picsDir.path}/$fileName');
      await file.writeAsBytes(pngBytes);

      if (mounted) _snack('Saved $fileName');
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        subject: fileName,
      ));
    } catch (e) {
      if (mounted) _snack('Save failed: $e');
    } finally {
      if (mounted) setState(() => _exportMode = false);
    }
  }

  static String _imgTimestamp(DateTime dt) {
    String p(int v, [int w = 2]) => v.toString().padLeft(w, '0');
    return '${p(dt.year, 4)}${p(dt.month)}${p(dt.day)}_'
        '${p(dt.hour)}${p(dt.minute)}${p(dt.second)}';
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MeasurementProvider>();
    final project  = provider.project;
    final mode     = provider.selectedMode;
    final isCv     = mode == VoltammetryMode.cv;
    final hasSg    = project?.measurements.any((s) => s.hasSgData) ?? false;

    _maybeRedetect(project, mode?.abbreviation);

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
                      color: _showSg ? AppColors.accent1 : AppColors.textSecondary,
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
          if (project != null && project.measurements.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.save_alt),
              tooltip: 'Save chart image',
              onPressed: _saveChartImage,
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
                      key: _chartKey,
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
                        detectedPeaks: _effectivePeaks,
                        onEditPeak: (peak) => _showPeakEditSheet(
                            context, peak, project, mode?.abbreviation ?? ''),
                        bubbleOffsets: _bubbleOffsets,
                        onBubbleMoved: _bubbleMoved,
                        exportMode: _exportMode,
                      ),
                    ),
                  ),
                ),

                if (project.peaks.isNotEmpty)
                  _PeakStrip(project: project, provider: provider),

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
                    onDeleteCycle: (m, c) => _confirmDeleteCycle(m, c, provider),
                  ),
                ),

                if (!widget.isImportedSession)
                  _BottomBar(provider: provider, project: project, mode: mode),
              ],
            ),
    );
  }

  Widget _empty() => const Center(
        child: Text('No measurements in this project.',
            style: TextStyle(color: AppColors.textSecondary)),
      );

  // ── Manual annotation sheet ────────────────────────────────────────────────

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
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            const Text('Annotate as peak:',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                  icon: const Icon(Icons.arrow_downward, size: 18),
                  label: const Text('Cathodic (Ec)'),
                  onPressed: () {
                    context.read<MeasurementProvider>()
                        .annotatePoint(measIdx, ptIdx, PeakType.cathodic);
                    Navigator.of(context).pop();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
                  icon: const Icon(Icons.arrow_upward, size: 18),
                  label: const Text('Anodic (Ea)'),
                  onPressed: () {
                    context.read<MeasurementProvider>()
                        .annotatePoint(measIdx, ptIdx, PeakType.anodic);
                    Navigator.of(context).pop();
                  },
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  // ── Confirm dialogs ────────────────────────────────────────────────────────

  Future<void> _confirmDeleteMeas(int index, MeasurementProvider provider) async {
    final session = provider.project?.measurements[index];
    if (session == null) return;
    final confirmed = await _confirmDialog(context, 'Delete "${session.displayName}"?',
        'Remove this measurement and all its annotations? Cannot be undone.');
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
          title: Text(title, style: const TextStyle(color: Colors.white)),
          content: Text(body, style: const TextStyle(color: AppColors.textSecondary)),
          actions: [
            TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
            ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                onPressed: () => Navigator.of(c).pop(true),
                child: const Text('Delete')),
          ],
        ),
      );
}

// ── Overlay chart ─────────────────────────────────────────────────────────────
//
// Plot-area insets — MUST match the titlesData reserved sizes so the bubble
// overlay can map data-coordinates to pixels accurately.
const double _kAxisNameSize   = 16;
const double _kLeftReserved   = 56;
const double _kBottomReserved = 30;
const double _kTopReserved    = 16;
const double _kRightReserved  = 24;
const double _kLeftInset   = _kLeftReserved + _kAxisNameSize;   // 72
const double _kBottomInset = _kBottomReserved + _kAxisNameSize; // 46
const double _kTopInset    = _kTopReserved;                     // 16
const double _kRightInset  = _kRightReserved;                   // 24

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
    required this.detectedPeaks,
    required this.onEditPeak,
    required this.bubbleOffsets,
    this.onBubbleMoved,
    this.exportMode = false,
  });

  final ProjectSession  project;
  final Set<int>        hiddenMeasurements;
  final Set<String>     hiddenCycles;
  final bool isCv;
  final bool showSg;
  final String xLabel;
  final String yLabel;
  final void Function(int measIdx, int ptIdx) onPointTapped;
  final List<PeakResult> detectedPeaks;
  final void Function(PeakResult) onEditPeak;
  final Map<String, Offset> bubbleOffsets;
  final void Function(String key, Offset delta)? onBubbleMoved;
  final bool exportMode;

  @override
  Widget build(BuildContext context) {
    final barMetas     = <_BarMeta>[];
    final bars         = <LineChartBarData>[];
    final peaks        = project.peaks;
    final peakBarIndex = <int, PeakResult>{};
    final bubbleSpecs  = <_BubbleSpec>[];
    final seriesColorMap = <String, Color>{};
    int globalColorIdx = 0;

    for (int mIdx = 0; mIdx < project.measurements.length; mIdx++) {
      if (hiddenMeasurements.contains(mIdx)) continue;
      final session = project.measurements[mIdx];

      if (isCv) {
        final cycles = session.cycles.toList()..sort();
        for (final cNum in cycles) {
          if (hiddenCycles.contains('$mIdx:$cNum')) { globalColorIdx++; continue; }
          final cyclePts = session.points.where((p) => p.cycle == cNum).toList();
          if (cyclePts.isEmpty) { globalColorIdx++; continue; }

          final originalIndices = <int>[];
          for (int i = 0; i < session.points.length; i++) {
            if (session.points[i].cycle == cNum) originalIndices.add(i);
          }

          final color = kCycleColors[globalColorIdx % kCycleColors.length];
          seriesColorMap['$mIdx:$cNum'] = color;
          final peaksForMeas = peaks.where((p) => p.measurementIndex == mIdx);

          bars.add(LineChartBarData(
            spots: cyclePts.map((p) => FlSpot(p.x, p.y)).toList(),
            isCurved: true, curveSmoothness: 0.2,
            color: color, barWidth: 2,
            dotData: FlDotData(
              show: peaksForMeas.isNotEmpty,
              getDotPainter: (spot, _, __, spotIdx) {
                if (spotIdx >= originalIndices.length) {
                  return FlDotCirclePainter(radius: 0, color: Colors.transparent, strokeColor: Colors.transparent);
                }
                final origIdx = originalIndices[spotIdx];
                final peak = peaksForMeas.where((p) => p.pointIndex == origIdx).firstOrNull;
                if (peak == null) {
                  return FlDotCirclePainter(radius: 0, color: Colors.transparent, strokeColor: Colors.transparent);
                }
                return FlDotCirclePainter(
                  radius: 6,
                  color: peak.type == PeakType.cathodic ? Colors.redAccent : Colors.amber,
                  strokeColor: Colors.white, strokeWidth: 1.5,
                );
              },
            ),
            belowBarData: BarAreaData(show: true, color: color.withOpacity(0.05)),
          ));
          barMetas.add(_BarMeta(mIdx, cNum, originalIndices));

          if (showSg && cNum == 1 && session.hasSgData) {
            final sgSpots = <FlSpot>[];
            for (int i = 0; i < cyclePts.length && i < session.sgPoints.length; i++) {
              final sg = session.sgPoints[i];
              if (sg != null) sgSpots.add(FlSpot(cyclePts[i].x, sg));
            }
            if (sgSpots.isNotEmpty) {
              bars.add(LineChartBarData(
                spots: sgSpots, isCurved: true, curveSmoothness: 0.3,
                color: Colors.white60, barWidth: 1.5, dashArray: [4, 4],
                dotData: const FlDotData(show: false),
              ));
              barMetas.add(_BarMeta(mIdx, null, []));
            }
          }
          globalColorIdx++;
        }
      } else {
        if (session.points.isEmpty) { globalColorIdx++; continue; }
        final color = kCycleColors[globalColorIdx % kCycleColors.length];
        seriesColorMap['$mIdx'] = color;
        final peaksForMeas = peaks.where((p) => p.measurementIndex == mIdx).toList();
        final indices = List<int>.generate(session.points.length, (i) => i);

        bars.add(LineChartBarData(
          spots: session.points.map((p) => FlSpot(p.x, p.y)).toList(),
          isCurved: true, curveSmoothness: 0.2,
          color: color, barWidth: 2,
          dotData: FlDotData(
            show: peaksForMeas.isNotEmpty,
            getDotPainter: (spot, _, __, spotIdx) {
              final peak = peaksForMeas.where((p) => p.pointIndex == spotIdx).firstOrNull;
              if (peak == null) {
                return FlDotCirclePainter(radius: 0, color: Colors.transparent, strokeColor: Colors.transparent);
              }
              return FlDotCirclePainter(
                radius: 6,
                color: peak.type == PeakType.cathodic ? Colors.redAccent : Colors.amber,
                strokeColor: Colors.white, strokeWidth: 1.5,
              );
            },
          ),
          belowBarData: BarAreaData(show: true, color: color.withOpacity(0.05)),
        ));
        barMetas.add(_BarMeta(mIdx, null, indices));
        globalColorIdx++;
      }
    }

    // ── Peak overlays: baseline + ip line + bubble specs ──────────────────────
    for (final pk in detectedPeaks) {
      if (hiddenMeasurements.contains(pk.measurementIdx)) continue;
      if (pk.cycleNum != null &&
          hiddenCycles.contains('${pk.measurementIdx}:${pk.cycleNum}')) continue;

      final colorKey = pk.cycleNum != null
          ? '${pk.measurementIdx}:${pk.cycleNum}'
          : '${pk.measurementIdx}';
      final pkColor = seriesColorMap[colorKey];
      if (pkColor == null) continue;

      final session = project.measurements[pk.measurementIdx];
      final seriesPts = pk.cycleNum != null
          ? session.points.where((p) => p.cycle == pk.cycleNum).toList()
          : session.points;
      if (seriesPts.isEmpty) continue;
      final spn = seriesPts.length;
      final apexIdx = pk.apexIndex.clamp(0, spn - 1);

      double blY(double xMv) => pk.baselineSlope * xMv + pk.baselineIntercept * 1000;

      final blStart = max(0, pk.fitLo - 3);
      final blEnd   = min(spn - 1, apexIdx + 8);
      final blSpots = [for (int i = blStart; i <= blEnd; i++) FlSpot(seriesPts[i].x, blY(seriesPts[i].x))];
      if (blSpots.length >= 2) {
        bars.add(LineChartBarData(
          spots: blSpots, isCurved: false,
          color: pkColor.withOpacity(0.55), barWidth: 1.5, dashArray: [5, 4],
          dotData: const FlDotData(show: false),
        ));
        barMetas.add(_BarMeta(pk.measurementIdx, pk.cycleNum, []));
      }

      final apexXmV = seriesPts[apexIdx].x;
      final apexYnA = seriesPts[apexIdx].y;
      final baselineAtApex = blY(apexXmV);
      final ipBarIdx = bars.length;
      bars.add(LineChartBarData(
        spots: [FlSpot(apexXmV, baselineAtApex), FlSpot(apexXmV, apexYnA)],
        isCurved: false, color: pkColor, barWidth: 2.0,
        dotData: FlDotData(
          show: true,
          getDotPainter: (spot, _, __, idx) => FlDotCirclePainter(
            radius: idx == 1 ? 5.5 : 3.0,
            color: idx == 1 ? pkColor : pkColor.withOpacity(0.55),
            strokeColor: Colors.white, strokeWidth: 1.0,
          ),
        ),
      ));
      barMetas.add(_BarMeta(pk.measurementIdx, pk.cycleNum, []));
      peakBarIndex[ipBarIdx] = pk;

      final isCathodic = pk.label.toLowerCase().contains('cathodic');
      final shortLabel = pk.label.toLowerCase().contains('anodic')
          ? 'Anodic (ipa)'
          : isCathodic ? 'Cathodic (ipc)' : 'Peak';
      bubbleSpecs.add(_BubbleSpec(
        peakKey:  _peakKey(pk),
        apexX:    apexXmV,
        apexY:    apexYnA,
        color:    pkColor,
        preferUp: !isCathodic,
        lines: [
          shortLabel,
          'Ep = ${pk.ep.toStringAsFixed(3)} V',
          'ip = ${pk.ip.toStringAsFixed(1)} µA',
        ],
      ));
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
    final xPad = max((maxX - minX) * 0.08, 1.0);
    final yPad = max((maxY - minY) * 0.12, 0.1);

    final minXEff = minX - xPad;
    final maxXEff = maxX + xPad;
    final minYEff = minY - yPad;
    final maxYEff = maxY + yPad;

    // ── Axis theme: dark for screen, white/black for export ──────────────────
    final bgColor      = exportMode ? Colors.white : AppColors.cardBg;
    final borderColor  = exportMode ? Colors.black26 : AppColors.divider;
    final tickStyle    = TextStyle(
        color: exportMode ? Colors.black87 : AppColors.textSecondary, fontSize: 10);
    final axisNameColor = exportMode ? Colors.grey.shade700 : AppColors.textSecondary;
    final axisNameStyle = TextStyle(color: axisNameColor, fontSize: 11);

    final chart = LineChart(
      LineChartData(
        backgroundColor: bgColor,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: !exportMode,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: AppColors.chartGrid, strokeWidth: 0.8),
          getDrawingVerticalLine: (_) =>
              const FlLine(color: AppColors.chartGrid, strokeWidth: 0.8),
        ),
        borderData: FlBorderData(show: true, border: Border.all(color: borderColor)),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            axisNameSize: _kAxisNameSize,
            axisNameWidget: Text(yLabel, style: axisNameStyle),
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: _kLeftReserved,
              getTitlesWidget: (v, _) => Text(v.toStringAsFixed(1), style: tickStyle),
            ),
          ),
          bottomTitles: AxisTitles(
            axisNameSize: _kAxisNameSize,
            axisNameWidget: Text(xLabel, style: axisNameStyle),
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: _kBottomReserved,
              getTitlesWidget: (v, _) => Text(v.toStringAsFixed(0), style: tickStyle),
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: _kRightReserved,
                getTitlesWidget: _emptyTitle),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: _kTopReserved,
                getTitlesWidget: _emptyTitle),
          ),
        ),
        minX: minXEff, maxX: maxXEff, minY: minYEff, maxY: maxYEff,
        lineTouchData: LineTouchData(
          handleBuiltInTouches: !exportMode,
          touchCallback: exportMode ? null : (event, response) {
            if (event is FlTapUpEvent &&
                response?.lineBarSpots != null &&
                response!.lineBarSpots!.isNotEmpty) {
              final spot = response.lineBarSpots!.first;
              final pk = peakBarIndex[spot.barIndex];
              if (pk != null) { onEditPeak(pk); return; }
              if (spot.barIndex >= barMetas.length) return;
              final meta = barMetas[spot.barIndex];
              if (meta.pointIndices.isEmpty) return;
              final spotIdx = spot.spotIndex;
              if (spotIdx >= meta.pointIndices.length) return;
              onPointTapped(meta.measurementIdx, meta.pointIndices[spotIdx]);
            }
          },
          touchTooltipData: exportMode
              ? const LineTouchTooltipData()
              : LineTouchTooltipData(
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

    // ── Bubble overlay ────────────────────────────────────────────────────────
    if (bubbleSpecs.isEmpty) return chart;

    final onMoved = onBubbleMoved;
    return Stack(
      fit: StackFit.expand,
      children: [
        chart,
        if (!exportMode && onMoved != null)
          _DraggableBubbleLayer(
            specs: bubbleSpecs,
            userOffsets: bubbleOffsets,
            minX: minXEff, maxX: maxXEff, minY: minYEff, maxY: maxYEff,
            onMoved: onMoved,
          )
        else
          IgnorePointer(
            child: CustomPaint(
              painter: _PeakBubblePainter(
                specs: bubbleSpecs, userOffsets: bubbleOffsets,
                minX: minXEff, maxX: maxXEff, minY: minYEff, maxY: maxYEff,
                exportMode: exportMode,
              ),
            ),
          ),
      ],
    );
  }
}

Widget _emptyTitle(double value, TitleMeta meta) => const SizedBox.shrink();
double _safeClamp(double v, double lo, double hi) =>
    hi < lo ? lo : v.clamp(lo, hi);

// ── Bubble spec & layout ──────────────────────────────────────────────────────

class _BubbleSpec {
  final String peakKey; // from _peakKey(pk)
  final double apexX;
  final double apexY;
  final Color  color;
  final bool   preferUp;
  final List<String> lines;
  const _BubbleSpec({
    required this.peakKey,
    required this.apexX,
    required this.apexY,
    required this.color,
    required this.preferUp,
    required this.lines,
  });
}

class _BubbleLayout {
  final Rect   rect;         // final rect including user offset
  final Offset textOrigin;
  final TextPainter tp;
  const _BubbleLayout(this.rect, this.textOrigin, this.tp);
}

// ── Peak bubble painter ───────────────────────────────────────────────────────

class _PeakBubblePainter extends CustomPainter {
  _PeakBubblePainter({
    required this.specs,
    required this.userOffsets,
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
    required this.exportMode,
  });

  final List<_BubbleSpec> specs;
  final Map<String, Offset> userOffsets;
  final double minX, maxX, minY, maxY;
  final bool exportMode;

  static const _padH = 7.0, _padV = 5.0;

  /// Build TextPainters for a spec (respects export colour scheme).
  TextPainter _buildTextPainter(_BubbleSpec spec) {
    final titleColor = spec.color;
    final bodyColor  = exportMode ? Colors.black87 : Colors.white;
    return TextPainter(
      text: TextSpan(children: [
        TextSpan(
            text: spec.lines.first,
            style: TextStyle(
                color: titleColor, fontSize: 10.5, fontWeight: FontWeight.w700)),
        TextSpan(
            text: '\n${spec.lines.skip(1).join('\n')}',
            style: TextStyle(color: bodyColor, fontSize: 10.5, height: 1.25)),
      ]),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  /// Compute final bubble rects + text layout for all specs.
  List<_BubbleLayout> computeLayouts(Size size) {
    final left   = _kLeftInset;
    final top    = _kTopInset;
    final right  = size.width - _kRightInset;
    final bottom = size.height - _kBottomInset;
    final plotW  = right - left;
    final plotH  = bottom - top;
    if (plotW <= 0 || plotH <= 0 || maxX == minX || maxY == minY) {
      return List.filled(specs.length, _BubbleLayout(Rect.zero, Offset.zero,
          TextPainter(textDirection: TextDirection.ltr)));
    }

    double mapX(double x) => left + (x - minX) / (maxX - minX) * plotW;
    double mapY(double y) => top  + (maxY - y) / (maxY - minY) * plotH;

    final result    = <_BubbleLayout>[];
    final autoRects = <Rect>[];

    for (final spec in specs) {
      final apex = Offset(mapX(spec.apexX), mapY(spec.apexY));
      final tp   = _buildTextPainter(spec);
      final bw   = tp.width  + _padH * 2;
      final bh   = tp.height + _padV * 2;

      const gap = 16.0;
      double bx = spec.preferUp ? apex.dx + gap : apex.dx - gap - bw;
      double by = spec.preferUp ? apex.dy - gap - bh : apex.dy + gap;

      bx = _safeClamp(bx, left + 2, right - bw - 2);
      by = _safeClamp(by, top + 2, bottom - bh - 2);

      var autoRect = Rect.fromLTWH(bx, by, bw, bh);
      int guard = 0;
      while (autoRects.any((r) => r.overlaps(autoRect.inflate(2))) && guard < 12) {
        by += spec.preferUp ? -(bh + 6) : (bh + 6);
        by = _safeClamp(by, top + 2, bottom - bh - 2);
        autoRect = Rect.fromLTWH(bx, by, bw, bh);
        guard++;
      }
      autoRects.add(autoRect);

      final userOff = userOffsets[spec.peakKey] ?? Offset.zero;
      final finalRect = autoRect.shift(userOff);
      result.add(_BubbleLayout(finalRect, finalRect.topLeft + const Offset(_padH, _padV), tp));
    }
    return result;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final layouts = computeLayouts(size);

    final left   = _kLeftInset;
    final top    = _kTopInset;
    final right  = size.width - _kRightInset;
    final bottom = size.height - _kBottomInset;
    if (maxX == minX || maxY == minY) return;
    final plotW = right - left;
    final plotH = bottom - top;
    if (plotW <= 0 || plotH <= 0) return;
    double mapX(double x) => left + (x - minX) / (maxX - minX) * plotW;
    double mapY(double y) => top  + (maxY - y) / (maxY - minY) * plotH;

    final bubbleBg = exportMode
        ? Colors.white.withOpacity(0.96)
        : const Color(0xFF111C38).withOpacity(0.92);

    for (int i = 0; i < specs.length; i++) {
      final spec   = specs[i];
      final layout = layouts[i];
      final rect   = layout.rect;
      final apex   = Offset(mapX(spec.apexX), mapY(spec.apexY));

      // Leader line.
      final anchor = Offset(
        apex.dx.clamp(rect.left, rect.right),
        apex.dy.clamp(rect.top, rect.bottom),
      );
      canvas.drawLine(anchor, apex,
          Paint()
            ..color = spec.color.withOpacity(0.9)
            ..strokeWidth = 1.4
            ..style = PaintingStyle.stroke);

      // Apex dot.
      canvas.drawCircle(apex, 3.0, Paint()..color = spec.color);
      canvas.drawCircle(apex, 3.0,
          Paint()
            ..color = Colors.white
            ..strokeWidth = 1.0
            ..style = PaintingStyle.stroke);

      // Bubble body.
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(7));
      canvas.drawRRect(rrect, Paint()..color = bubbleBg);
      canvas.drawRRect(rrect,
          Paint()
            ..color = spec.color
            ..strokeWidth = 1.4
            ..style = PaintingStyle.stroke);

      layout.tp.paint(canvas, layout.textOrigin);
    }
  }

  @override
  bool shouldRepaint(covariant _PeakBubblePainter old) => true;
}

// ── Draggable bubble overlay ──────────────────────────────────────────────────

class _DraggableBubbleLayer extends StatefulWidget {
  const _DraggableBubbleLayer({
    required this.specs,
    required this.userOffsets,
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
    required this.onMoved,
  });

  final List<_BubbleSpec>  specs;
  final Map<String, Offset> userOffsets;
  final double minX, maxX, minY, maxY;
  final void Function(String key, Offset delta) onMoved;

  @override
  State<_DraggableBubbleLayer> createState() => _DraggableBubbleLayerState();
}

class _DraggableBubbleLayerState extends State<_DraggableBubbleLayer> {
  String? _activeKey;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      final painter = _PeakBubblePainter(
        specs: widget.specs,
        userOffsets: widget.userOffsets,
        minX: widget.minX, maxX: widget.maxX,
        minY: widget.minY, maxY: widget.maxY,
        exportMode: false,
      );

      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (d) {
          final layouts = painter.computeLayouts(size);
          _activeKey = null;
          for (int i = 0; i < widget.specs.length; i++) {
            if (layouts[i].rect.inflate(8).contains(d.localPosition)) {
              _activeKey = widget.specs[i].peakKey;
              break;
            }
          }
        },
        onPanUpdate: (d) {
          if (_activeKey != null) widget.onMoved(_activeKey!, d.delta);
        },
        onPanEnd:    (_) { _activeKey = null; },
        onPanCancel: ()  { _activeKey = null; },
        child: CustomPaint(painter: painter),
      );
    });
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
          top:    BorderSide(color: AppColors.divider),
          bottom: BorderSide(color: AppColors.divider),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('PEAK ANNOTATIONS',
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 10,
                  fontWeight: FontWeight.w600, letterSpacing: 0.8)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8, runSpacing: 4,
            children: sorted.map((peak) {
              final color = peak.type == PeakType.cathodic ? Colors.redAccent : Colors.amber;
              final session = project.measurements[peak.measurementIndex];
              final typeLabel = peak.type == PeakType.cathodic ? 'Ec' : 'Ea';
              return Chip(
                label: Text(
                  '$typeLabel (${session.displayName}): '
                  '${peak.point.x.toStringAsFixed(1)} mV, '
                  '${peak.point.y.toStringAsFixed(3)} nA',
                  style: const TextStyle(fontSize: 11, color: Colors.white),
                ),
                backgroundColor: color.withOpacity(0.2),
                side: BorderSide(color: color.withOpacity(0.5)),
                padding: EdgeInsets.zero,
                deleteIcon: const Icon(Icons.close, size: 14, color: Colors.white54),
                onDeleted: () => provider.removePeakAnnotation(peak.measurementIndex, peak.type),
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
    required this.project, required this.provider, required this.isCv,
    required this.hiddenMeasurements, required this.hiddenCycles,
    required this.onToggleMeas, required this.onToggleCycle,
    required this.onDeleteMeas, required this.onDeleteCycle,
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
              label: session.displayName,
              sublabel: session.label.isNotEmpty ? session.label : null,
              visible: !isHidden,
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
                    color: isHidden ? AppColors.textSecondary : Colors.white,
                    fontSize: 14, fontWeight: FontWeight.w600,
                  )),
              subtitle: session.label.isNotEmpty
                  ? Text(session.label,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11))
                  : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
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
    required this.label, required this.visible, required this.colorDot,
    required this.onToggle, required this.onDelete,
    this.sublabel, this.indent = false,
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
            color: visible ? colorDot : AppColors.divider, shape: BoxShape.circle),
        ),
        title: Text(label,
            style: TextStyle(
                color: visible ? Colors.white : AppColors.textSecondary,
                fontSize: indent ? 13 : 14)),
        subtitle: sublabel != null
            ? Text(sublabel!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11))
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
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
          ],
        ),
      );
}

// ── Bottom action bar ─────────────────────────────────────────────────────────
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.provider, required this.project, required this.mode});
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
      child: Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _showExportSheet(context),
            icon: const Icon(Icons.save_alt, size: 18),
            label: const Text('Export CSV'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton(
            onPressed: () {
              provider.resetMeasurement();
              if (mode != null) {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => ParametersScreen(mode: mode!)));
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
      context: context, isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => _ExportSheet(project: project, mode: mode),
    );
  }
}

// ── Peak manual-edit sheet ────────────────────────────────────────────────────
class _PeakEditSheet extends StatefulWidget {
  const _PeakEditSheet({
    required this.peak,
    required this.initialPeak,
    required this.xV,
    required this.yUa,
    required this.onPreview,
    required this.onApply,
  });

  final PeakResult peak;
  final PeakResult initialPeak;
  final List<double> xV;
  final List<double> yUa;
  final void Function(PeakResult) onPreview;
  final void Function(PeakResult) onApply;

  @override
  State<_PeakEditSheet> createState() => _PeakEditSheetState();
}

class _PeakEditSheetState extends State<_PeakEditSheet> {
  late int _apexIdx;
  late int _fitLo;
  late int _fitHi;
  late PeakResult _preview;

  @override
  void initState() {
    super.initState();
    _apexIdx = widget.peak.apexIndex;
    _fitLo   = widget.peak.fitLo;
    _fitHi   = widget.peak.fitHi;
    _preview = widget.peak;
  }

  void _recompute() {
    final updated = PeakFinder.recompute(
      widget.peak.copyWith(apexIndex: _apexIdx, fitLo: _fitLo, fitHi: _fitHi),
      widget.xV, widget.yUa,
    );
    setState(() => _preview = updated);
    widget.onPreview(updated);
  }

  void _reset() {
    final initial = widget.initialPeak;
    setState(() {
      _apexIdx = initial.apexIndex;
      _fitLo   = initial.fitLo;
      _fitHi   = initial.fitHi;
      _preview = initial;
    });
    widget.onPreview(initial);
    widget.onApply(initial);
  }

  /// Snap apex to the nearest local max (anodic/peak) or min (cathodic) within ±8 pts.
  void _snap() {
    final isPositive = !widget.peak.label.toLowerCase().contains('cathodic');
    const window = 8;
    final lo = max(0, _apexIdx - window);
    final hi = min(widget.yUa.length - 1, _apexIdx + window);
    int best = _apexIdx;
    double bestVal = widget.yUa[_apexIdx];
    for (int i = lo; i <= hi; i++) {
      if (isPositive  && widget.yUa[i] > bestVal) { bestVal = widget.yUa[i]; best = i; }
      if (!isPositive && widget.yUa[i] < bestVal) { bestVal = widget.yUa[i]; best = i; }
    }
    if (best != _apexIdx) {
      setState(() => _apexIdx = best);
      _recompute();
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.xV.length;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 14, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                  color: AppColors.divider, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: Text(widget.peak.label,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
            ),
            TextButton.icon(
              onPressed: _snap,
              icon: const Icon(Icons.my_location, size: 14),
              label: Text(
                widget.peak.label.toLowerCase().contains('cathodic')
                    ? 'Snap ▽' : 'Snap ▲',
                style: const TextStyle(fontSize: 12),
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.accent2,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
            ),
          ]),
          const SizedBox(height: 2),
          Text(
            'Ep = ${_preview.ep.toStringAsFixed(4)} V   '
            'ip = ${_preview.ip.toStringAsFixed(4)} µA',
            style: const TextStyle(color: AppColors.accent1, fontSize: 12),
          ),
          const SizedBox(height: 12),
          _NudgeSliderRow(
            label: 'Apex index',
            value: _apexIdx, min: 0, max: n - 1,
            onChanged: (v) => setState(() { _apexIdx = v; _recompute(); }),
          ),
          _NudgeSliderRow(
            label: 'Baseline start',
            value: _fitLo, min: 0, max: n - 2,
            onChanged: (v) {
              setState(() {
                _fitLo = v;
                if (_fitHi <= _fitLo) _fitHi = _fitLo + 1;
                _recompute();
              });
            },
          ),
          _NudgeSliderRow(
            label: 'Baseline end',
            value: _fitHi, min: _fitLo + 1, max: n - 1,
            onChanged: (v) => setState(() { _fitHi = v; _recompute(); }),
          ),
          const SizedBox(height: 16),
          Row(children: [
            OutlinedButton(onPressed: _reset, child: const Text('Reset')),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: () { widget.onApply(_preview); Navigator.pop(context); },
                child: const Text('Apply'),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

/// Slider row with "−" / "+" nudge buttons for single-step adjustments.
class _NudgeSliderRow extends StatelessWidget {
  const _NudgeSliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int    value;
  final int    min;
  final int    max;
  final void Function(int) onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      SizedBox(
        width: 92,
        child: Text('$label:', style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
      ),
      // Decrement button
      SizedBox(
        width: 28, height: 28,
        child: IconButton(
          padding: EdgeInsets.zero,
          iconSize: 14,
          icon: const Icon(Icons.remove),
          color: AppColors.accent2,
          disabledColor: AppColors.divider,
          onPressed: value > min ? () => onChanged(value - 1) : null,
        ),
      ),
      // Slider
      Expanded(
        child: Slider(
          value: value.toDouble(),
          min:   min.toDouble(),
          max:   max.toDouble(),
          divisions: max > min ? max - min : null,
          onChanged: (v) => onChanged(v.round()),
          activeColor: AppColors.accent1,
        ),
      ),
      // Increment button
      SizedBox(
        width: 28, height: 28,
        child: IconButton(
          padding: EdgeInsets.zero,
          iconSize: 14,
          icon: const Icon(Icons.add),
          color: AppColors.accent2,
          disabledColor: AppColors.divider,
          onPressed: value < max ? () => onChanged(value + 1) : null,
        ),
      ),
      // Value
      SizedBox(
        width: 32,
        child: Text('$value', style: const TextStyle(color: Colors.white, fontSize: 11)),
      ),
    ]);
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
  late TextEditingController _filenameCtrl;

  bool get _isCv => widget.mode == VoltammetryMode.cv;

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < widget.project.measurements.length; i++) {
      _selMeasurements.add(i);
      if (_isCv) {
        for (final c in widget.project.measurements[i].cycles) {
          _selCycles.add('$i:$c');
        }
      }
    }
    final tech = widget.mode?.abbreviation ?? 'EbStat';
    _filenameCtrl = TextEditingController(
        text: 'EbStat_${tech}_${_filenameTimestamp(DateTime.now())}');
  }

  @override
  void dispose() { _filenameCtrl.dispose(); super.dispose(); }

  static String _filenameTimestamp(DateTime dt) {
    final y  = dt.year.toString().padLeft(4, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    final d  = dt.day.toString().padLeft(2, '0');
    final h  = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    final s  = dt.second.toString().padLeft(2, '0');
    return '${y}${mo}${d}_${h}${mi}${s}';
  }

  static String _sanitizeFilename(String raw) =>
      raw.replaceAll(RegExp(r'[/\\:*?"<>|]'), '').trim();

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (_, ctrl) => Column(children: [
        Container(
          margin: const EdgeInsets.only(top: 10, bottom: 4),
          width: 36, height: 4,
          decoration: BoxDecoration(
              color: AppColors.divider, borderRadius: BorderRadius.circular(2)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(children: [
            const Text('Export CSV',
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
            const Spacer(),
            TextButton(
              onPressed: _exporting ? null : () => _export(context),
              child: _exporting
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Export'),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: TextField(
            controller: _filenameCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'File name', suffixText: '.csv',
              suffixStyle: const TextStyle(color: AppColors.textSecondary),
              helperText: 'Illegal characters ( / \\ : * ? " < > | ) are removed',
              helperStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
              helperMaxLines: 1,
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
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
                      style: const TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: session.label.isNotEmpty
                      ? Text(session.label,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11))
                      : null,
                  value: measSel, activeColor: AppColors.accent1,
                  onChanged: (v) => setState(() =>
                      v! ? _selMeasurements.add(mIdx) : _selMeasurements.remove(mIdx)),
                );
              }

              final cycles = session.cycles.toList()..sort();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CheckboxListTile(
                    dense: true,
                    title: Text(session.displayName,
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                    value: measSel, activeColor: AppColors.accent1,
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
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                        value: cSel, activeColor: AppColors.accent1,
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
      ]),
    );
  }

  Future<void> _export(BuildContext context) async {
    final rawName   = _filenameCtrl.text;
    final cleanName = _sanitizeFilename(rawName);
    if (cleanName.isEmpty) {
      setState(() => _error = 'File name cannot be empty.'); return;
    }
    setState(() { _exporting = true; _error = null; });
    try {
      final csvContent = PalmsensCsvService.build(
        widget.project, widget.mode,
        selMeasurements: _selMeasurements, selCycles: _selCycles,
      );
      if (csvContent.isEmpty) {
        setState(() { _exporting = false; _error = 'Nothing selected to export.'; }); return;
      }
      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}/$cleanName.csv');
      await file.writeAsString(csvContent);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: 'EbStat export — $cleanName',
      ));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}
