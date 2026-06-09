import 'dart:math';

import '../models/measurement_point.dart';
import '../models/peak_result.dart';
import '../models/peak_type.dart';
import '../models/project_session.dart';

export '../models/peak_result.dart';

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
      sumX += x[i]; sumY += y[i];
      sumXX += x[i] * x[i]; sumXY += x[i] * y[i];
    }
    final denom = count * sumXX - sumX * sumX;
    if (denom.abs() < 1e-30) return (0.0, sumY / count);
    final slope     = (count * sumXY - sumX * sumY) / denom;
    final intercept = (sumY - slope * sumX) / count;
    return (slope, intercept);
  }

  static double _median(List<double> values) {
    if (values.isEmpty) return 0.0;
    final sorted = [...values]..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0;
  }

  static double _std(List<double> values) {
    if (values.isEmpty) return 1e-9;
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance =
        values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
            values.length;
    return max(sqrt(variance), 1e-9);
  }

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
    required PeakType peakType,
    double minWidthMv  = 10.0,
    double minHeightUa = 1.0,
  }) {
    final n = ys.length;
    if (i1 <= i0 || i0 < 0 || i1 >= n) return null;

    // 1. Find apex
    int apexIdx = i0;
    double apexVal = sign * ys[i0];
    for (int i = i0; i <= i1; i++) {
      if (sign * ys[i] > apexVal) { apexVal = sign * ys[i]; apexIdx = i; }
    }
    if (apexIdx <= i0 || apexIdx >= i1) return null;

    // 2. Find onset
    const smoothWin = 5;
    final k = max(2, smoothWin ~/ 2);
    final slopeStart = i0 + k;
    final slopeEnd   = apexIdx - k;
    final slopes = <double>[];
    for (int i = slopeStart; i <= slopeEnd && i < n - k; i++) {
      slopes.add(sign * (ys[i + k] - ys[i - k]));
    }
    int onsetIdx = slopeStart;
    if (slopes.isNotEmpty) {
      final half = slopes.length ~/ 2;
      final bg = _median(slopes.sublist(0, max(1, half)));
      final sd = _std(slopes);
      for (int i = 0; i < slopes.length; i++) {
        if (slopes[i] > bg + 0.5 * sd) { onsetIdx = slopeStart + i; break; }
      }
    }

    // 3. Baseline fit
    final span  = max(3, onsetIdx - i0);
    int fitHi   = max(i0 + 1, onsetIdx - 1);
    int fitLo   = max(i0, fitHi - max(2, (span * 0.20).toInt() + 1));
    if (fitHi - fitLo < 1) { fitLo = i0; fitHi = min(i0 + 3, apexIdx - 1); }
    fitLo = fitLo.clamp(0, n - 1);
    fitHi = fitHi.clamp(0, n - 1);

    final (slope, intercept) = _linFit(xV, ys, fitLo, fitHi);

    // 4. Peak height / ip
    final baselineAtApex = slope * xV[apexIdx] + intercept;
    final height = ys[apexIdx] - baselineAtApex;
    final ip = height.abs();

    // 5. Range-fraction guard (existing)
    double rangeMin = ys[i0], rangeMax = ys[i0];
    for (int i = i0; i <= i1; i++) {
      if (ys[i] < rangeMin) rangeMin = ys[i];
      if (ys[i] > rangeMax) rangeMax = ys[i];
    }
    final range = rangeMax - rangeMin;
    if (sign * height <= 0.05 * range) return null;

    // 6. Min height filter
    if (ip < minHeightUa) return null;

    // 7. Half-height width filter
    final halfLevel = baselineAtApex + sign * height / 2;
    double leftX  = xV[i0];
    for (int i = apexIdx; i >= i0; i--) {
      if (sign * (ys[i] - halfLevel) <= 0) { leftX = xV[i]; break; }
    }
    double rightX = xV[i1];
    for (int i = apexIdx; i <= i1; i++) {
      if (sign * (ys[i] - halfLevel) <= 0) { rightX = xV[i]; break; }
    }
    final widthMv = (rightX - leftX).abs() * 1000; // xV in V → mV
    if (widthMv < minWidthMv) return null;

    return PeakResult(
      measurementIdx:    measurementIdx,
      cycleNum:          cycleNum,
      label:             label,
      ep:                xV[apexIdx],
      ip:                ip,
      apexIndex:         apexIdx,
      onsetIndex:        onsetIdx,
      fitLo:             fitLo,
      fitHi:             fitHi,
      baselineSlope:     slope,
      baselineIntercept: intercept,
      isAuto:            true,
      peakType:          peakType,
    );
  }

  static List<PeakResult> analyzeCv(
      List<double> xV, List<double> yUa, int mIdx, int cycleNum,
      {double minWidthMv = 10.0, double minHeightUa = 1.0}) {
    final n = xV.length;
    if (n < 10) return [];
    final ys = smooth(yUa);

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

    final edge    = max(2, (n * 0.03).toInt());
    final results = <PeakResult>[];

    // Forward branch: anodic
    final fwdI0 = edge;
    final fwdI1 = max(edge + 3, turnIdx - edge);
    if (fwdI1 > fwdI0 + 5) {
      final r = _findPeak(
        xV: xV, yUa: yUa, ys: ys, sign: 1,
        i0: fwdI0, i1: fwdI1,
        measurementIdx: mIdx, cycleNum: cycleNum,
        label: 'Anodic (ipa/Epa)', peakType: PeakType.anodic,
        minWidthMv: minWidthMv, minHeightUa: minHeightUa,
      );
      if (r != null) results.add(r);
    }

    // Reverse branch: cathodic
    final revI0 = min(turnIdx + edge, n - 3);
    final revI1 = max(revI0 + 3, n - 1 - edge);
    if (revI1 > revI0 + 5) {
      final r = _findPeak(
        xV: xV, yUa: yUa, ys: ys, sign: -1,
        i0: revI0, i1: revI1,
        measurementIdx: mIdx, cycleNum: cycleNum,
        label: 'Cathodic (ipc/Epc)', peakType: PeakType.cathodic,
        minWidthMv: minWidthMv, minHeightUa: minHeightUa,
      );
      if (r != null) results.add(r);
    }
    return results;
  }

  static List<PeakResult> analyzeVoltammetry(
      List<double> xV, List<double> yUa, int mIdx,
      {double minWidthMv = 10.0, double minHeightUa = 1.0}) {
    final n = xV.length;
    if (n < 10) return [];
    final ys = smooth(yUa);
    final m  = max(2, (n * 0.05).toInt());
    final i0 = m;
    final i1 = n - 1 - m;
    if (i1 <= i0 + 5) return [];

    var r = _findPeak(
      xV: xV, yUa: yUa, ys: ys, sign: 1,
      i0: i0, i1: i1, measurementIdx: mIdx, cycleNum: null,
      label: 'Peak (ip/Ep)', peakType: PeakType.anodic,
      minWidthMv: minWidthMv, minHeightUa: minHeightUa,
    );
    r ??= _findPeak(
      xV: xV, yUa: yUa, ys: ys, sign: -1,
      i0: i0, i1: i1, measurementIdx: mIdx, cycleNum: null,
      label: 'Peak (ip/Ep)', peakType: PeakType.cathodic,
      minWidthMv: minWidthMv, minHeightUa: minHeightUa,
    );
    return r != null ? [r] : [];
  }

  /// Dispatch peak detection based on technique abbreviation.
  static List<PeakResult> analyze(
    MeasurementSession session,
    int mIdx,
    String technique, {
    double minWidthMv  = 10.0,
    double minHeightUa = 1.0,
  }) {
    if (technique == 'CA') return [];

    if (technique == 'CV') {
      final cycles  = session.cycles.toList()..sort();
      final results = <PeakResult>[];
      for (final cNum in cycles) {
        final cyclePoints =
            session.points.where((p) => p.cycle == cNum).toList();
        if (cyclePoints.isEmpty) continue;
        final xV  = cyclePoints.map((p) => p.x / 1000).toList();
        final yUa = cyclePoints.map((p) => p.y / 1000).toList();
        results.addAll(analyzeCv(xV, yUa, mIdx, cNum,
            minWidthMv: minWidthMv, minHeightUa: minHeightUa));
      }
      return results;
    }

    if (session.points.isEmpty) return [];
    final xV  = session.points.map((p) => p.x / 1000).toList();
    final yUa = session.points.map((p) => p.y / 1000).toList();
    return analyzeVoltammetry(xV, yUa, mIdx,
        minWidthMv: minWidthMv, minHeightUa: minHeightUa);
  }

  /// Recompute a peak result after manual apex/baseline adjustment.
  static PeakResult recompute(
      PeakResult old, List<double> xV, List<double> yUa) {
    final n   = xV.length;
    final ys  = smooth(yUa);
    final apexIdx = old.apexIndex.clamp(0, n - 1);
    final fitLo   = old.fitLo.clamp(0, n - 1);
    final fitHi   = old.fitHi.clamp(fitLo, n - 1);

    final (slope, intercept) = _linFit(xV, ys, fitLo, fitHi);
    final baselineAtApex = slope * xV[apexIdx] + intercept;
    final height = ys[apexIdx] - baselineAtApex;
    final ip     = height.abs();
    final ep     = xV[apexIdx];

    return old.copyWith(
      ep:                ep,
      ip:                ip,
      apexIndex:         apexIdx,
      fitLo:             fitLo,
      fitHi:             fitHi,
      baselineSlope:     slope,
      baselineIntercept: intercept,
      isAuto:            false,
    );
  }
}
