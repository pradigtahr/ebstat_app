import 'dart:math';

import '../models/measurement_point.dart';
import '../models/project_session.dart';

// ── PeakResult ────────────────────────────────────────────────────────────────

class PeakResult {
  final int measurementIdx;
  final int? cycleNum;
  final String label; // "Anodic (ipa/Epa)", "Cathodic (ipc/Epc)", "Peak (ip/Ep)"
  final double ep; // V
  final double ip; // µA (absolute)
  final int apexIndex; // index into per-series points array
  final int onsetIndex;
  final int fitLo;
  final int fitHi;
  final double baselineSlope; // µA/V
  final double baselineIntercept; // µA
  final bool isAuto;

  const PeakResult({
    required this.measurementIdx,
    this.cycleNum,
    required this.label,
    required this.ep,
    required this.ip,
    required this.apexIndex,
    required this.onsetIndex,
    required this.fitLo,
    required this.fitHi,
    required this.baselineSlope,
    required this.baselineIntercept,
    required this.isAuto,
  });

  PeakResult copyWith({
    int? measurementIdx,
    int? cycleNum,
    String? label,
    double? ep,
    double? ip,
    int? apexIndex,
    int? onsetIndex,
    int? fitLo,
    int? fitHi,
    double? baselineSlope,
    double? baselineIntercept,
    bool? isAuto,
  }) {
    return PeakResult(
      measurementIdx: measurementIdx ?? this.measurementIdx,
      cycleNum: cycleNum ?? this.cycleNum,
      label: label ?? this.label,
      ep: ep ?? this.ep,
      ip: ip ?? this.ip,
      apexIndex: apexIndex ?? this.apexIndex,
      onsetIndex: onsetIndex ?? this.onsetIndex,
      fitLo: fitLo ?? this.fitLo,
      fitHi: fitHi ?? this.fitHi,
      baselineSlope: baselineSlope ?? this.baselineSlope,
      baselineIntercept: baselineIntercept ?? this.baselineIntercept,
      isAuto: isAuto ?? this.isAuto,
    );
  }
}

// ── PeakFinder ────────────────────────────────────────────────────────────────

class PeakFinder {
  /// Centered moving average. Forces win to odd. Edge: truncate window.
  static List<double> smooth(List<double> y, {int win = 5}) {
    if (win % 2 == 0) win += 1;
    final half = win ~/ 2;
    final n = y.length;
    final out = List<double>.filled(n, 0.0);
    for (int i = 0; i < n; i++) {
      final lo = max(0, i - half);
      final hi = min(n - 1, i + half);
      double sum = 0;
      for (int j = lo; j <= hi; j++) sum += y[j];
      out[i] = sum / (hi - lo + 1);
    }
    return out;
  }

  /// Least-squares linear fit over indices [lo, hi] inclusive.
  /// Returns (slope, intercept). Handles count < 2 gracefully.
  static (double slope, double intercept) _linFit(
      List<double> x, List<double> y, int lo, int hi) {
    final count = hi - lo + 1;
    if (count < 2) {
      final xi = lo < x.length ? x[lo] : 0.0;
      final yi = lo < y.length ? y[lo] : 0.0;
      return (0.0, yi - 0.0 * xi);
    }
    double sumX = 0, sumY = 0, sumXX = 0, sumXY = 0;
    for (int i = lo; i <= hi; i++) {
      sumX += x[i];
      sumY += y[i];
      sumXX += x[i] * x[i];
      sumXY += x[i] * y[i];
    }
    final denom = count * sumXX - sumX * sumX;
    if (denom.abs() < 1e-30) {
      return (0.0, sumY / count);
    }
    final slope = (count * sumXY - sumX * sumY) / denom;
    final intercept = (sumY - slope * sumX) / count;
    return (slope, intercept);
  }

  static double _median(List<double> values) {
    if (values.isEmpty) return 0.0;
    final sorted = [...values]..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length % 2 == 1) return sorted[mid];
    return (sorted[mid - 1] + sorted[mid]) / 2.0;
  }

  static double _std(List<double> values) {
    if (values.isEmpty) return 1e-9;
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance =
        values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
            values.length;
    return max(sqrt(variance), 1e-9);
  }

  /// Find a single peak in the range [i0, i1] of the smoothed array ys.
  static PeakResult? _findPeak({
    required List<double> xV,
    required List<double> yUa,
    required List<double> ys,
    required int sign,
    required int i0,
    required int i1,
    required int measurementIdx,
    required int? cycleNum,
    required String label,
  }) {
    final n = ys.length;
    if (i1 <= i0 || i0 < 0 || i1 >= n) return null;

    // 1. Find apex
    int apexIdx = i0;
    double apexVal = sign * ys[i0];
    for (int i = i0; i <= i1; i++) {
      if (sign * ys[i] > apexVal) {
        apexVal = sign * ys[i];
        apexIdx = i;
      }
    }

    // 2. Reject if apex is at or beyond boundary
    if (apexIdx <= i0 || apexIdx >= i1) return null;

    // 3. Find onset
    const smoothWin = 5;
    final k = max(2, smoothWin ~/ 2);
    final slopeStart = i0 + k;
    final slopeEnd = apexIdx - k;

    if (slopeEnd <= slopeStart) {
      // Not enough room, default onset
    }

    final slopes = <double>[];
    for (int i = slopeStart; i <= slopeEnd && i < n - k; i++) {
      slopes.add(sign * (ys[i + k] - ys[i - k]));
    }

    int onsetIdx = slopeStart;
    if (slopes.isNotEmpty) {
      final half = slopes.length ~/ 2;
      final firstHalf = slopes.sublist(0, max(1, half));
      final bg = _median(firstHalf);
      final sd = _std(slopes);
      bool found = false;
      for (int i = 0; i < slopes.length; i++) {
        if (slopes[i] > bg + 0.5 * sd) {
          onsetIdx = slopeStart + i;
          found = true;
          break;
        }
      }
      if (!found) onsetIdx = slopeStart;
    }

    // 4. Baseline fit
    final span = max(3, onsetIdx - i0);
    int fitHi = max(i0 + 1, onsetIdx - 1);
    int fitLo =
        max(i0, fitHi - max(2, (span * 0.20).toInt() + 1));
    if (fitHi - fitLo < 1) {
      fitLo = i0;
      fitHi = min(i0 + 3, apexIdx - 1);
    }
    fitLo = fitLo.clamp(0, n - 1);
    fitHi = fitHi.clamp(0, n - 1);

    final (slope, intercept) = _linFit(xV, ys, fitLo, fitHi);

    // 5. Compute peak height and ip
    final baselineAtApex = slope * xV[apexIdx] + intercept;
    final height = ys[apexIdx] - baselineAtApex;
    final ip = height.abs();

    // 6. Reject if too small
    double rangeMin = ys[i0], rangeMax = ys[i0];
    for (int i = i0; i <= i1; i++) {
      if (ys[i] < rangeMin) rangeMin = ys[i];
      if (ys[i] > rangeMax) rangeMax = ys[i];
    }
    final range = rangeMax - rangeMin;
    if (sign * height <= 0.05 * range) return null;

    return PeakResult(
      measurementIdx: measurementIdx,
      cycleNum: cycleNum,
      label: label,
      ep: xV[apexIdx],
      ip: ip,
      apexIndex: apexIdx,
      onsetIndex: onsetIdx,
      fitLo: fitLo,
      fitHi: fitHi,
      baselineSlope: slope,
      baselineIntercept: intercept,
      isAuto: true,
    );
  }

  /// Analyze a CV (cyclic voltammetry) series.
  static List<PeakResult> analyzeCv(
      List<double> xV, List<double> yUa, int mIdx, int cycleNum) {
    final n = xV.length;
    if (n < 10) return [];

    final ys = smooth(yUa);

    // Find turning point
    int maxXIdx = 0, minXIdx = 0;
    for (int i = 1; i < n; i++) {
      if (xV[i] > xV[maxXIdx]) maxXIdx = i;
      if (xV[i] < xV[minXIdx]) minXIdx = i;
    }

    int turnIdx;
    if (maxXIdx > 2 && maxXIdx < n - 3) {
      turnIdx = maxXIdx;
    } else if (minXIdx > 2 && minXIdx < n - 3) {
      turnIdx = minXIdx;
    } else {
      turnIdx = n ~/ 2;
    }

    final edge = max(2, (n * 0.03).toInt());
    final results = <PeakResult>[];

    // Forward branch: anodic
    final fwdI0 = edge;
    final fwdI1 = max(edge + 3, turnIdx - edge);
    if (fwdI1 > fwdI0 + 5) {
      final r = _findPeak(
        xV: xV,
        yUa: yUa,
        ys: ys,
        sign: 1,
        i0: fwdI0,
        i1: fwdI1,
        measurementIdx: mIdx,
        cycleNum: cycleNum,
        label: 'Anodic (ipa/Epa)',
      );
      if (r != null) results.add(r);
    }

    // Reverse branch: cathodic
    final revI0 = min(turnIdx + edge, n - 3);
    final revI1 = max(revI0 + 3, n - 1 - edge);
    if (revI1 > revI0 + 5) {
      final r = _findPeak(
        xV: xV,
        yUa: yUa,
        ys: ys,
        sign: -1,
        i0: revI0,
        i1: revI1,
        measurementIdx: mIdx,
        cycleNum: cycleNum,
        label: 'Cathodic (ipc/Epc)',
      );
      if (r != null) results.add(r);
    }

    return results;
  }

  /// Analyze a linear sweep voltammetry series (DPV, SWV, NPV).
  static List<PeakResult> analyzeVoltammetry(
      List<double> xV, List<double> yUa, int mIdx) {
    final n = xV.length;
    if (n < 10) return [];

    final ys = smooth(yUa);
    final m = max(2, (n * 0.05).toInt());
    final i0 = m;
    final i1 = n - 1 - m;

    if (i1 <= i0 + 5) return [];

    // Try positive peak first
    var r = _findPeak(
      xV: xV,
      yUa: yUa,
      ys: ys,
      sign: 1,
      i0: i0,
      i1: i1,
      measurementIdx: mIdx,
      cycleNum: null,
      label: 'Peak (ip/Ep)',
    );

    // Fallback to negative peak
    r ??= _findPeak(
      xV: xV,
      yUa: yUa,
      ys: ys,
      sign: -1,
      i0: i0,
      i1: i1,
      measurementIdx: mIdx,
      cycleNum: null,
      label: 'Peak (ip/Ep)',
    );

    return r != null ? [r] : [];
  }

  /// Dispatch peak detection based on technique abbreviation.
  static List<PeakResult> analyze(
      MeasurementSession session, int mIdx, String technique) {
    if (technique == 'CA') return [];

    if (technique == 'CV') {
      final cycles = session.cycles.toList()..sort();
      final results = <PeakResult>[];
      for (final cNum in cycles) {
        final cyclePoints =
            session.points.where((p) => p.cycle == cNum).toList();
        if (cyclePoints.isEmpty) continue;
        final xV = cyclePoints.map((p) => p.x / 1000).toList();
        final yUa = cyclePoints.map((p) => p.y / 1000).toList();
        results.addAll(analyzeCv(xV, yUa, mIdx, cNum));
      }
      return results;
    }

    // DPV / SWV / NPV
    if (session.points.isEmpty) return [];
    final xV = session.points.map((p) => p.x / 1000).toList();
    final yUa = session.points.map((p) => p.y / 1000).toList();
    return analyzeVoltammetry(xV, yUa, mIdx);
  }

  /// Recompute a peak result (used when user adjusts apex/fitLo/fitHi).
  static PeakResult recompute(
      PeakResult old, List<double> xV, List<double> yUa) {
    final n = xV.length;
    final ys = smooth(yUa);

    final apexIdx = old.apexIndex.clamp(0, n - 1);
    final fitLo = old.fitLo.clamp(0, n - 1);
    final fitHi = old.fitHi.clamp(fitLo, n - 1);

    final (slope, intercept) = _linFit(xV, ys, fitLo, fitHi);
    final baselineAtApex = slope * xV[apexIdx] + intercept;
    final height = ys[apexIdx] - baselineAtApex;
    final ip = height.abs();
    final ep = xV[apexIdx];

    return old.copyWith(
      ep: ep,
      ip: ip,
      apexIndex: apexIdx,
      fitLo: fitLo,
      fitHi: fitHi,
      baselineSlope: slope,
      baselineIntercept: intercept,
      isAuto: false,
    );
  }
}
