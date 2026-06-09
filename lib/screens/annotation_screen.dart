import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/measurement_point.dart';
import '../models/peak_result.dart';
import '../models/peak_type.dart';
import '../models/project_session.dart';
import '../providers/measurement_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/cv_chart.dart' show kCycleColors;

// ── Tangent line data ─────────────────────────────────────────────────────────

class _TangentLine {
  final String id;
  int?     baselinePointIdx; // index into the visible points list
  double   slope;            // nA/mV
  PeakType peakType;
  Color    color;

  _TangentLine({
    required this.id,
    required this.color,
    this.peakType = PeakType.anodic,
  }) : slope = 0.0;
}

// ── Constants ─────────────────────────────────────────────────────────────────

const double _kAnnotBorder    = 2.0;  // fl_chart border inset (no titles)
const double _kTangentSensitivity = 0.001; // nA/mV per drag pixel (vertical)

// ── AnnotationScreen ──────────────────────────────────────────────────────────

class AnnotationScreen extends StatefulWidget {
  const AnnotationScreen({
    super.key,
    required this.session,
    required this.measurementIdx,
  });

  final ProjectSession session;
  final int measurementIdx;

  @override
  State<AnnotationScreen> createState() => _AnnotationScreenState();
}

class _AnnotationScreenState extends State<AnnotationScreen> {
  // ── Measurement state ─────────────────────────────────────────────────────
  late int _measIdx;

  // ── V1/V2 range ───────────────────────────────────────────────────────────
  final _v1Ctrl = TextEditingController();
  final _v2Ctrl = TextEditingController();
  double? _v1, _v2;

  // ── Apex ──────────────────────────────────────────────────────────────────
  int? _apexIndex; // index into _currentPoints()

  // ── Tangent lines ─────────────────────────────────────────────────────────
  final List<_TangentLine> _tangents = [];
  _TangentLine? _activeTangent;
  int _tangentIdCounter = 0;

  // ── Display ───────────────────────────────────────────────────────────────
  bool _showBubbles          = true;
  bool _hideRangeForExport   = false;
  bool _showControlPanel     = true;

  // ── Bubble offsets for registered peaks ──────────────────────────────────
  final Map<String, Offset> _bubbleOffsets = {};

  // ── Chart export ──────────────────────────────────────────────────────────
  final GlobalKey _chartKey = GlobalKey();

  // ── Chart coordinate mapping (updated by LayoutBuilder) ─────────────────
  Size   _chartSize  = Size.zero;
  double _dataMinX   = -1, _dataMaxX = 1;
  double _dataMinY   = -1, _dataMaxY = 1;

  @override
  void initState() {
    super.initState();
    _measIdx = widget.measurementIdx.clamp(
        0, max(0, widget.session.measurements.length - 1));
  }

  @override
  void dispose() {
    _v1Ctrl.dispose();
    _v2Ctrl.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  List<MeasurementPoint> _currentPoints() {
    if (_measIdx >= widget.session.measurements.length) return [];
    return widget.session.measurements[_measIdx].points;
  }

  bool get _isCv =>
      _measIdx < widget.session.measurements.length &&
      widget.session.measurements[_measIdx].mode == 'CV';

  String _tangentId() => 'T${_tangentIdCounter++}';

  Color _nextTangentColor() =>
      kCycleColors[_tangents.length % kCycleColors.length];

  /// Find the index of the point nearest to a given data coordinate.
  int? _nearestPointIndex(double dataxMv, double datayNa) {
    final pts = _currentPoints();
    if (pts.isEmpty) return null;
    double best = double.infinity;
    int    idx  = 0;
    for (int i = 0; i < pts.length; i++) {
      final dx = pts[i].x - dataxMv;
      final dy = pts[i].y - datayNa;
      final d  = dx * dx + dy * dy;
      if (d < best) { best = d; idx = i; }
    }
    return idx;
  }

  /// Convert pixel position to data coordinates.
  Offset _pixelToData(Offset pixel) {
    if (_chartSize == Size.zero) return Offset.zero;
    final plotW = _chartSize.width  - 2 * _kAnnotBorder;
    final plotH = _chartSize.height - 2 * _kAnnotBorder;
    if (plotW <= 0 || plotH <= 0) return Offset.zero;
    final dataX = _dataMinX +
        (pixel.dx - _kAnnotBorder) / plotW * (_dataMaxX - _dataMinX);
    final dataY = _dataMaxY -
        (pixel.dy - _kAnnotBorder) / plotH * (_dataMaxY - _dataMinY);
    return Offset(dataX, dataY);
  }

  /// Find max Y point in range [v1, v2].
  int? _findApexInRange(double v1Mv, double v2Mv) {
    final pts = _currentPoints();
    if (pts.isEmpty) return null;
    int?   best;
    double bestY = double.negativeInfinity;
    for (int i = 0; i < pts.length; i++) {
      final x = pts[i].x;
      if (x >= v1Mv && x <= v2Mv && pts[i].y > bestY) {
        bestY = pts[i].y;
        best  = i;
      }
    }
    return best;
  }

  void _updateRange() {
    final v1 = double.tryParse(_v1Ctrl.text);
    final v2 = double.tryParse(_v2Ctrl.text);
    setState(() {
      _v1 = v1;
      _v2 = v2;
      if (v1 != null && v2 != null && v1 < v2) {
        _apexIndex = _findApexInRange(v1, v2);
      }
    });
  }

  void _onChartTap(Offset pixel) {
    if (_activeTangent == null) return;
    final data    = _pixelToData(pixel);
    final nearest = _nearestPointIndex(data.dx, data.dy);
    if (nearest == null) return;
    final pts = _currentPoints();
    setState(() {
      _activeTangent!.baselinePointIdx = nearest;
      // Compute initial slope from finite difference at that point
      if (nearest > 0 && nearest < pts.length - 1) {
        final dx = pts[nearest + 1].x - pts[nearest - 1].x;
        final dy = pts[nearest + 1].y - pts[nearest - 1].y;
        if (dx.abs() > 1e-9) _activeTangent!.slope = dy / dx;
      }
    });
  }

  void _onChartDrag(DragUpdateDetails d) {
    if (_activeTangent == null) return;
    setState(() {
      _activeTangent!.slope -= d.delta.dy * _kTangentSensitivity;
    });
  }

  // ── Computed peak values from active tangent ──────────────────────────────

  (double ep, double ip)? _computePeak(_TangentLine t) {
    final idx = t.baselinePointIdx;
    final apx = _apexIndex;
    if (idx == null || apx == null) return null;
    final pts = _currentPoints();
    if (idx >= pts.length || apx >= pts.length) return null;
    final basePt = pts[idx];
    final apexPt = pts[apx];
    final baselineAtApex =
        t.slope * (apexPt.x - basePt.x) + basePt.y; // nA
    final ipNa = apexPt.y - baselineAtApex;
    return (apexPt.x, ipNa / 1000); // (mV, µA)
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  void _addTangent() {
    final t = _TangentLine(
      id:       _tangentId(),
      color:    _nextTangentColor(),
      peakType: PeakType.anodic,
    );
    setState(() {
      _tangents.add(t);
      _activeTangent = t;
    });
  }

  void _removeTangent(_TangentLine t) {
    setState(() {
      _tangents.remove(t);
      if (_activeTangent == t) _activeTangent = _tangents.isNotEmpty ? _tangents.last : null;
    });
  }

  void _registerPeak() {
    final t = _activeTangent;
    if (t == null || _apexIndex == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Set a baseline point and apex range first.')),
      );
      return;
    }
    final result = _computePeak(t);
    if (result == null) return;
    final (epMv, ipUa) = result;
    final pts = _currentPoints();
    if (_apexIndex! >= pts.length) return;

    final peak = PeakResult(
      measurementIdx:    _measIdx,
      cycleNum:          null,
      label:             t.peakType == PeakType.anodic ? 'Anodic (ipa/Epa)' : 'Cathodic (ipc/Epc)',
      ep:                epMv / 1000, // store in V
      ip:                ipUa.abs(),
      apexIndex:         _apexIndex!,
      onsetIndex:        t.baselinePointIdx ?? 0,
      fitLo:             t.baselinePointIdx ?? 0,
      fitHi:             t.baselinePointIdx ?? 0,
      baselineSlope:     t.slope / 1000, // nA/mV → µA/V
      baselineIntercept: 0,
      isAuto:            false,
      peakType:          t.peakType,
      tangentSlope:      t.slope,
      tangentBaselineX:  t.baselinePointIdx != null ? pts[t.baselinePointIdx!].x : null,
      tangentBaselineY:  t.baselinePointIdx != null ? pts[t.baselinePointIdx!].y : null,
    );

    context.read<MeasurementProvider>().project?.registerPeak(peak);
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Peak registered: '
          'Ep = ${(epMv).toStringAsFixed(1)} mV, '
          'ip = ${ipUa.abs().toStringAsFixed(3)} µA'),
    ));
  }

  Future<void> _exportImage() async {
    final dpiOptions = [300, 450, 600, 900, 1200];
    int selectedDpi = 300;
    String selectedFmt = 'PNG';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setSt) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Export Image', style: TextStyle(color: Colors.white)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Align(alignment: Alignment.centerLeft,
              child: Text('Format', style: TextStyle(color: AppColors.textSecondary, fontSize: 12))),
          const SizedBox(height: 4),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'PNG', label: Text('PNG')),
              ButtonSegment(value: 'JPG', label: Text('JPG')),
            ],
            selected: {selectedFmt},
            onSelectionChanged: (s) => setSt(() => selectedFmt = s.first),
            style: SegmentedButton.styleFrom(
              backgroundColor: AppColors.surface,
              selectedBackgroundColor: AppColors.accent1,
              selectedForegroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          const Align(alignment: Alignment.centerLeft,
              child: Text('DPI', style: TextStyle(color: AppColors.textSecondary, fontSize: 12))),
          const SizedBox(height: 4),
          DropdownButtonFormField<int>(
            value: selectedDpi,
            dropdownColor: AppColors.surface,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              filled: true, fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.divider),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.divider),
              ),
            ),
            items: dpiOptions
                .map((d) => DropdownMenuItem(value: d, child: Text('$d dpi')))
                .toList(),
            onChanged: (v) { if (v != null) setSt(() => selectedDpi = v); },
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Export')),
        ],
      )),
    );
    if (confirmed != true || !mounted) return;

    // Hide V1/V2 shaded band for the exported image
    setState(() => _hideRangeForExport = true);
    await Future.delayed(const Duration(milliseconds: 80));

    try {
      final boundary = _chartKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) { _snack('Chart not ready.'); return; }
      final pixelRatio = selectedDpi / 96.0;
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) { _snack('Failed to encode.'); return; }
      final pngBytes = byteData.buffer.asUint8List();

      final dir = await getTemporaryDirectory();
      final ts  = DateTime.now().toIso8601String().replaceAll(':', '-').replaceAll('.', '-');
      final ext = selectedFmt.toLowerCase();
      final fileName = 'EbStat_Annotation_$ts.$ext';
      final file     = File('${dir.path}/$fileName');

      if (selectedFmt == 'PNG') {
        await file.writeAsBytes(pngBytes);
      } else {
        // JPG: encode from png bytes using flutter's built-in path
        // (no external image package needed for basic jpg)
        final codec  = await ui.instantiateImageCodec(pngBytes);
        final frame  = await codec.getNextFrame();
        final jpgBd  = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (jpgBd == null) { _snack('JPG encode failed.'); return; }
        // Save as PNG if JPG not available via dart:ui directly
        await file.writeAsBytes(pngBytes);
      }

      if (mounted) _snack('Saved $fileName');
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path)],
        subject: fileName,
      ));
    } catch (e) {
      if (mounted) _snack('Export failed: $e');
    } finally {
      if (mounted) setState(() => _hideRangeForExport = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final pts   = _currentPoints();
    final isCv  = _isCv;

    return Scaffold(
      appBar: AppBar(
        title: Text(_measIdx < widget.session.measurements.length
            ? widget.session.measurements[_measIdx].displayName
            : 'Annotation'),
        actions: [
          IconButton(
            icon: Icon(_showBubbles ? Icons.label : Icons.label_off),
            tooltip: _showBubbles ? 'Hide bubbles' : 'Show bubbles',
            onPressed: () => setState(() => _showBubbles = !_showBubbles),
          ),
          if (_tangents.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Clear all tangent lines',
              onPressed: () => setState(() {
                _tangents.clear();
                _activeTangent = null;
              }),
            ),
          IconButton(
            icon: const Icon(Icons.image_outlined),
            tooltip: 'Export image',
            onPressed: _exportImage,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _registerPeak,
        icon: const Icon(Icons.check),
        label: const Text('Register Peak'),
        backgroundColor: AppColors.accent1,
      ),
      body: pts.isEmpty
          ? const Center(
              child: Text('No data for this measurement.',
                  style: TextStyle(color: AppColors.textSecondary)))
          : Column(children: [
              // ── Chart area ────────────────────────────────────────────────
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: RepaintBoundary(
                    key: _chartKey,
                    child: LayoutBuilder(builder: (ctx, constraints) {
                      _chartSize = Size(constraints.maxWidth, constraints.maxHeight);
                      return Stack(fit: StackFit.expand, children: [
                        _buildChart(pts, isCv),
                        // Gesture overlay for tangent interaction
                        if (_activeTangent != null)
                          GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTapUp: (d) => _onChartTap(d.localPosition),
                            onPanUpdate: _onChartDrag,
                          ),
                        // Bubble overlay
                        if (_showBubbles && widget.session.registeredPeaks.isNotEmpty)
                          IgnorePointer(
                            child: CustomPaint(
                              painter: _AnnotBubblePainter(
                                peaks:     widget.session.registeredPeaks
                                    .where((p) => p.measurementIdx == _measIdx)
                                    .toList(),
                                userOffsets: _bubbleOffsets,
                                minX: _dataMinX, maxX: _dataMaxX,
                                minY: _dataMinY, maxY: _dataMaxY,
                              ),
                            ),
                          ),
                        // Live Ep/Ip readout
                        if (_activeTangent != null)
                          _buildReadout(),
                      ]);
                    }),
                  ),
                ),
              ),

              // ── Control panel ─────────────────────────────────────────────
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                child: _showControlPanel ? _buildControlPanel() : const SizedBox.shrink(),
              ),
              GestureDetector(
                onTap: () => setState(() => _showControlPanel = !_showControlPanel),
                child: Container(
                  width: double.infinity,
                  color: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Icon(
                    _showControlPanel ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                    color: AppColors.textSecondary, size: 16,
                  ),
                ),
              ),
            ]),
    );
  }

  // ── Chart ─────────────────────────────────────────────────────────────────

  Widget _buildChart(List<MeasurementPoint> pts, bool isCv) {
    final allX = pts.map((p) => p.x);
    final allY = pts.map((p) => p.y);
    final rawMinX = allX.reduce(min), rawMaxX = allX.reduce(max);
    final rawMinY = allY.reduce(min), rawMaxY = allY.reduce(max);
    final xPad = max((rawMaxX - rawMinX) * 0.05, 1.0);
    final yPad = max((rawMaxY - rawMinY) * 0.10, 0.1);

    _dataMinX = rawMinX - xPad;
    _dataMaxX = rawMaxX + xPad;
    _dataMinY = rawMinY - yPad;
    _dataMaxY = rawMaxY + yPad;

    final bars = <LineChartBarData>[];

    // Data curve(s)
    if (isCv) {
      final session = widget.session.measurements[_measIdx];
      final cycles  = session.cycles.toList()..sort();
      for (int ci = 0; ci < cycles.length; ci++) {
        final cNum    = cycles[ci];
        final cpPts   = pts.where((p) => p.cycle == cNum).toList();
        final color   = kCycleColors[ci % kCycleColors.length];
        bars.add(LineChartBarData(
          spots: cpPts.map((p) => FlSpot(p.x, p.y)).toList(),
          isCurved: true, curveSmoothness: 0.2,
          color: color, barWidth: 2,
          dotData: const FlDotData(show: false),
        ));
      }
    } else {
      bars.add(LineChartBarData(
        spots: pts.map((p) => FlSpot(p.x, p.y)).toList(),
        isCurved: true, curveSmoothness: 0.2,
        color: AppColors.chartLine, barWidth: 2,
        dotData: const FlDotData(show: false),
      ));
    }

    // Tangent lines
    for (final t in _tangents) {
      final idx = t.baselinePointIdx;
      if (idx == null || idx >= pts.length) continue;
      final bx = pts[idx].x;
      final by = pts[idx].y;
      final y1 = t.slope * (_dataMinX - bx) + by;
      final y2 = t.slope * (_dataMaxX - bx) + by;
      final isActive = identical(t, _activeTangent);
      bars.add(LineChartBarData(
        spots: [FlSpot(_dataMinX, y1), FlSpot(_dataMaxX, y2)],
        isCurved: false,
        color: t.color.withOpacity(isActive ? 1.0 : 0.6),
        barWidth: isActive ? 2.0 : 1.5,
        dashArray: [8, 4],
        dotData: FlDotData(
          show: true,
          getDotPainter: (spot, _, __, si) {
            // Show a marker at the baseline reference point
            if (si == 0) {
              final fracX = (_dataMaxX - _dataMinX) > 0
                  ? (bx - _dataMinX) / (_dataMaxX - _dataMinX)
                  : 0.5;
              if ((spot.x - (bx)).abs() < 1) {
                return FlDotCirclePainter(
                    radius: 5, color: t.color,
                    strokeColor: Colors.white, strokeWidth: 1.5);
              }
            }
            return FlDotCirclePainter(radius: 0, color: Colors.transparent, strokeColor: Colors.transparent);
          },
        ),
      ));
    }

    // Apex marker
    final apx = _apexIndex;
    if (apx != null && apx < pts.length) {
      bars.add(LineChartBarData(
        spots: [FlSpot(pts[apx].x, pts[apx].y)],
        isCurved: false,
        color: Colors.white,
        barWidth: 0,
        dotData: FlDotData(
          show: true,
          getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
              radius: 6, color: Colors.white,
              strokeColor: AppColors.accent1, strokeWidth: 2),
        ),
      ));
    }

    // V1-V2 range annotation
    final hasRange = !_hideRangeForExport && _v1 != null && _v2 != null && _v1! < _v2!;

    // Apex vertical line
    final vertLines = <VerticalLine>[];
    if (apx != null && apx < pts.length) {
      vertLines.add(VerticalLine(
        x: pts[apx].x,
        color: Colors.white54,
        strokeWidth: 1.5,
        dashArray: [6, 4],
        label: VerticalLineLabel(
          show: true,
          alignment: Alignment.topRight,
          labelResolver: (line) =>
              'Ep=${(pts[apx].x).toStringAsFixed(0)} mV',
          style: const TextStyle(color: Colors.white70, fontSize: 9),
        ),
      ));
    }

    return LineChart(
      LineChartData(
        backgroundColor: AppColors.cardBg,
        clipData: const FlClipData.all(),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(
            show: true, border: Border.all(color: AppColors.divider)),
        titlesData: const FlTitlesData(show: false),
        minX: _dataMinX, maxX: _dataMaxX,
        minY: _dataMinY, maxY: _dataMaxY,
        rangeAnnotations: hasRange
            ? RangeAnnotations(verticalRangeAnnotations: [
                VerticalRangeAnnotation(
                    x1: _v1!, x2: _v2!,
                    color: Colors.blue.withOpacity(0.15)),
              ])
            : const RangeAnnotations(),
        extraLinesData: ExtraLinesData(verticalLines: vertLines),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: bars,
      ),
      duration: Duration.zero,
    );
  }

  // ── Live readout overlay ──────────────────────────────────────────────────

  Widget _buildReadout() {
    final t = _activeTangent;
    if (t == null) return const SizedBox.shrink();
    final result = _computePeak(t);
    return Positioned(
      left: 8, top: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surface.withOpacity(0.9),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: t.color, width: 1),
        ),
        child: result == null
            ? const Text('Tap curve to set baseline',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Ep = ${result.$1.toStringAsFixed(1)} mV',
                      style: const TextStyle(color: Colors.white, fontSize: 11)),
                  Text('ip = ${result.$2.abs().toStringAsFixed(3)} µA',
                      style: const TextStyle(color: AppColors.accent1, fontSize: 11)),
                ],
              ),
      ),
    );
  }

  // ── Control panel ─────────────────────────────────────────────────────────

  Widget _buildControlPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Measurement selector (if >1 scan)
          if (widget.session.measurements.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                const Text('Scan: ',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                Expanded(
                  child: DropdownButton<int>(
                    value: _measIdx,
                    isExpanded: true,
                    dropdownColor: AppColors.surface,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    items: List.generate(widget.session.measurements.length, (i) =>
                        DropdownMenuItem(
                          value: i,
                          child: Text(widget.session.measurements[i].displayName),
                        )),
                    onChanged: (v) {
                      if (v != null) setState(() {
                        _measIdx    = v;
                        _apexIndex  = null;
                        _tangents.clear();
                        _activeTangent = null;
                      });
                    },
                  ),
                ),
              ]),
            ),

          // V1 / V2 range inputs
          Row(children: [
            Expanded(
              child: TextField(
                controller: _v1Ctrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                onChanged: (_) => _updateRange(),
                decoration: const InputDecoration(
                  labelText: 'V1 (mV)', isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _v2Ctrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                onChanged: (_) => _updateRange(),
                decoration: const InputDecoration(
                  labelText: 'V2 (mV)', isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 10),

          // Tangent controls
          Row(children: [
            // Add tangent button
            OutlinedButton.icon(
              onPressed: _addTangent,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('New Tangent', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
            ),
            const SizedBox(width: 8),
            // Tangent list
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _tangents.map((t) {
                    final isActive = identical(t, _activeTangent);
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: GestureDetector(
                        onLongPress: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Remove tangent ${t.id}?'),
                              action: SnackBarAction(
                                  label: 'Remove',
                                  onPressed: () => _removeTangent(t)),
                              duration: const Duration(seconds: 3),
                            ),
                          );
                        },
                        child: InkWell(
                          onTap: () => setState(() => _activeTangent = t),
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: t.color.withOpacity(isActive ? 0.3 : 0.1),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: t.color,
                                width: isActive ? 2 : 1,
                              ),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Container(
                                  width: 8, height: 8,
                                  decoration: BoxDecoration(
                                      color: t.color, shape: BoxShape.circle)),
                              const SizedBox(width: 4),
                              Text(t.id,
                                  style: TextStyle(
                                      color: isActive ? t.color : Colors.white70,
                                      fontSize: 11)),
                              const SizedBox(width: 4),
                              // Peak type toggle chip
                              GestureDetector(
                                onTap: () => setState(() {
                                  t.peakType = t.peakType == PeakType.anodic
                                      ? PeakType.cathodic
                                      : PeakType.anodic;
                                }),
                                child: Text(
                                  t.peakType == PeakType.anodic ? '▲' : '▽',
                                  style: TextStyle(color: t.color, fontSize: 10),
                                ),
                              ),
                            ]),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ]),
          if (_activeTangent != null) ...[
            const SizedBox(height: 6),
            Text(
              'Active: ${_activeTangent!.id}  —  '
              'Tap chart to set baseline, drag vertically to rotate slope',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Bubble painter for registered peaks ──────────────────────────────────────

class _AnnotBubblePainter extends CustomPainter {
  const _AnnotBubblePainter({
    required this.peaks,
    required this.userOffsets,
    required this.minX, required this.maxX,
    required this.minY, required this.maxY,
  });

  final List<PeakResult>    peaks;
  final Map<String, Offset> userOffsets;
  final double minX, maxX, minY, maxY;

  static const _pad = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (maxX == minX || maxY == minY) return;
    final plotW = size.width  - 2 * _kAnnotBorder;
    final plotH = size.height - 2 * _kAnnotBorder;
    if (plotW <= 0 || plotH <= 0) return;

    double mapX(double x) =>
        _kAnnotBorder + (x - minX) / (maxX - minX) * plotW;
    double mapY(double y) =>
        _kAnnotBorder + (maxY - y) / (maxY - minY) * plotH;

    for (final pk in peaks) {
      final apexXmV = pk.ep * 1000; // V → mV
      final apexYnA = pk.ip * 1000; // µA → nA
      final color   = pk.effectivePeakType == PeakType.anodic
          ? const Color(0xFF0098DB)
          : Colors.redAccent;
      final apexPx  = Offset(mapX(apexXmV), mapY(apexYnA));

      final text = 'Ep=${(pk.ep * 1000).toStringAsFixed(1)} mV\n'
          'ip=${pk.ip.toStringAsFixed(3)} µA';
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(color: Colors.white, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final bw     = tp.width  + _pad * 2;
      final bh     = tp.height + _pad * 2;
      final userOff = userOffsets[_pkKey(pk)] ?? Offset.zero;
      final bx     = (apexPx.dx - bw / 2 + userOff.dx).clamp(0.0, size.width  - bw);
      final by     = (apexPx.dy - bh - 10  + userOff.dy).clamp(0.0, size.height - bh);
      final rect   = Rect.fromLTWH(bx, by, bw, bh);

      // Leader line
      canvas.drawLine(apexPx, Offset(rect.center.dx, rect.bottom),
          Paint()
            ..color = color.withOpacity(0.8)
            ..strokeWidth = 1.2
            ..style = PaintingStyle.stroke);

      // Apex dot
      canvas.drawCircle(apexPx, 4,
          Paint()..color = color);

      // Bubble
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(6)),
          Paint()..color = const Color(0xFF111C38).withOpacity(0.9));
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(6)),
          Paint()
            ..color = color
            ..strokeWidth = 1.2
            ..style = PaintingStyle.stroke);

      tp.paint(canvas, Offset(bx + _pad, by + _pad));
    }
  }

  String _pkKey(PeakResult pk) => '${pk.measurementIdx}:${pk.cycleNum}:${pk.label}';

  @override
  bool shouldRepaint(covariant _AnnotBubblePainter old) => true;
}
