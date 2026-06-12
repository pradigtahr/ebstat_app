// Pure Dart — no Flutter imports.
import 'dart:math';

enum PeakType { both, oxidationOnly, reductionOnly }

class PeakResult {
  final String cycleId;
  // anodic (null if not found or filtered)
  final double? eAnodicMv;
  final double? iRawAnodicUa;
  final double? ipaUa;
  // cathodic (null if not found or filtered)
  final double? eCathodicMv;
  final double? iRawCathodicUa;
  final double? ipcUa;
  // shared baseline y = slope * E + intercept  (units: µA, µA/mV)
  final double baselineSlope;
  final double baselineIntercept;

  const PeakResult({
    required this.cycleId,
    this.eAnodicMv,
    this.iRawAnodicUa,
    this.ipaUa,
    this.eCathodicMv,
    this.iRawCathodicUa,
    this.ipcUa,
    required this.baselineSlope,
    required this.baselineIntercept,
  });
}

class LevelResult {
  final String datasetId;
  final double tStartS;
  final double tEndS;
  final double iMeanUa;
  final double iStdUa;

  const LevelResult({
    required this.datasetId,
    required this.tStartS,
    required this.tEndS,
    required this.iMeanUa,
    required this.iStdUa,
  });
}

// ── Detect Peaks ──────────────────────────────────────────────────────────────

/// Run the spec algorithm on one cycle/series.
/// [pts] E in mV, I in µA.  Returns null if no peak passes filters.
PeakResult? detectPeaks({
  required String cycleId,
  required List<({double eMv, double iUa})> pts,
  required double minWidthMv,
  required double minHeightUa,
  required double baselineRegionPct,
  required PeakType peakType,
}) {
  if (pts.length < 10) return null;

  final eMin = pts.map((p) => p.eMv).reduce(min);
  final eMax = pts.map((p) => p.eMv).reduce(max);
  final eRange = eMax - eMin;
  if (eRange <= 0) return null;

  // ── Shared baseline (linear regression through outer regions) ─────────────
  final frac     = baselineRegionPct / 100.0;
  final leftPts  = pts.where((p) => p.eMv <= eMin + frac * eRange).toList();
  final rightPts = pts.where((p) => p.eMv >= eMax - frac * eRange).toList();
  final (:slope, :intercept) = _linReg([...leftPts, ...rightPts]);

  // Local baseline estimate for width midpoint (mean of outermost 10 pts)
  final localBase = (_mean(pts.take(10).map((p) => p.iUa)) +
                     _mean(pts.skip(max(0, pts.length - 10)).map((p) => p.iUa))) /
                    2.0;

  double? aE, aIRaw, aIpa, cE, cIRaw, cIpc;

  // ── Anodic peak (global max) ──────────────────────────────────────────────
  if (peakType != PeakType.reductionOnly) {
    int mi = 0;
    for (int i = 1; i < pts.length; i++) {
      if (pts[i].iUa > pts[mi].iUa) mi = i;
    }
    final cand = pts[mi];
    if (cand.iUa >= minHeightUa) {
      final mid = (cand.iUa + localBase) / 2.0;
      int li = mi, ri = mi;
      while (li > 0 && pts[li].iUa >= mid) li--;
      while (ri < pts.length - 1 && pts[ri].iUa >= mid) ri++;
      if (pts[ri].eMv - pts[li].eMv >= minWidthMv) {
        aE    = cand.eMv;
        aIRaw = cand.iUa;
        aIpa  = cand.iUa - (slope * cand.eMv + intercept);
      }
    }
  }

  // ── Cathodic peak (global min) ────────────────────────────────────────────
  if (peakType != PeakType.oxidationOnly) {
    int mi = 0;
    for (int i = 1; i < pts.length; i++) {
      if (pts[i].iUa < pts[mi].iUa) mi = i;
    }
    final cand = pts[mi];
    if (cand.iUa.abs() >= minHeightUa) {
      final mid = (cand.iUa + localBase) / 2.0;
      int li = mi, ri = mi;
      while (li > 0 && pts[li].iUa <= mid) li--;
      while (ri < pts.length - 1 && pts[ri].iUa <= mid) ri++;
      if (pts[ri].eMv - pts[li].eMv >= minWidthMv) {
        cE    = cand.eMv;
        cIRaw = cand.iUa;
        cIpc  = cand.iUa - (slope * cand.eMv + intercept);
      }
    }
  }

  if (aE == null && cE == null) return null;
  return PeakResult(
    cycleId:           cycleId,
    eAnodicMv:         aE,
    iRawAnodicUa:      aIRaw,
    ipaUa:             aIpa,
    eCathodicMv:       cE,
    iRawCathodicUa:    cIRaw,
    ipcUa:             cIpc,
    baselineSlope:     slope,
    baselineIntercept: intercept,
  );
}

// ── Find Levels ───────────────────────────────────────────────────────────────

/// Plateau (level) detection for CA data.
/// [pts] t in seconds (normalised to 0), I in µA.
List<LevelResult> findLevels({
  required String datasetId,
  required List<({double tS, double iUa})> pts,
  required double minDurationS,
  required double minHeightUa,
}) {
  if (pts.length < 3) return [];
  final tRange = pts.last.tS - pts.first.tS;
  if (tRange <= 0) return [];
  final dt = tRange / (pts.length - 1);
  final winPts = max(2, (minDurationS / dt).ceil());
  if (winPts > pts.length) return [];

  // Mark each point that falls inside at least one qualifying window.
  final inLevel = List<bool>.filled(pts.length, false);
  for (int i = 0; i <= pts.length - winPts; i++) {
    final ys   = pts.sublist(i, i + winPts).map((p) => p.iUa).toList();
    final mean = _listMean(ys);
    if (mean.abs() < minHeightUa) continue;
    final std = _listStd(ys, mean);
    if (std / mean.abs() < 0.05) {
      for (int j = i; j < i + winPts; j++) inLevel[j] = true;
    }
  }

  // Merge contiguous regions.
  final out = <LevelResult>[];
  int? start;
  for (int i = 0; i <= pts.length; i++) {
    final on = i < pts.length && inLevel[i];
    if (on && start == null) { start = i; }
    if (!on && start != null) {
      final ys   = pts.sublist(start!, i).map((p) => p.iUa).toList();
      final mean = _listMean(ys);
      out.add(LevelResult(
        datasetId: datasetId,
        tStartS:   pts[start!].tS,
        tEndS:     pts[i - 1].tS,
        iMeanUa:   mean,
        iStdUa:    _listStd(ys, mean),
      ));
      start = null;
    }
  }
  return out;
}

// ── Private helpers ───────────────────────────────────────────────────────────

({double slope, double intercept}) _linReg(
    List<({double eMv, double iUa})> pts) {
  if (pts.isEmpty) return (slope: 0, intercept: 0);
  if (pts.length == 1) return (slope: 0, intercept: pts.first.iUa);
  final n = pts.length.toDouble();
  double sx = 0, sy = 0, sxy = 0, sx2 = 0;
  for (final p in pts) {
    sx  += p.eMv;
    sy  += p.iUa;
    sxy += p.eMv * p.iUa;
    sx2 += p.eMv * p.eMv;
  }
  final d = n * sx2 - sx * sx;
  if (d == 0) return (slope: 0, intercept: sy / n);
  final s = (n * sxy - sx * sy) / d;
  return (slope: s, intercept: (sy - s * sx) / n);
}

double _mean(Iterable<double> xs) {
  final list = xs.toList();
  if (list.isEmpty) return 0;
  return list.reduce((a, b) => a + b) / list.length;
}

double _listMean(List<double> xs) {
  if (xs.isEmpty) return 0;
  return xs.reduce((a, b) => a + b) / xs.length;
}

double _listStd(List<double> xs, double mean) {
  if (xs.length < 2) return 0;
  final v = xs.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) /
            (xs.length - 1);
  return sqrt(v);
}
