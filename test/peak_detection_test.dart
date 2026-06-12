import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:ebstat_app/services/peak_detection.dart';

List<({double eMv, double iUa})> _gaussPts({
  double centre = 200, double height = 5, double sigma = 30,
  double eStart = -100, double eEnd = 500, int n = 100,
}) {
  return List.generate(n, (i) {
    final e = eStart + (eEnd - eStart) * i / (n - 1);
    final y = height * exp(-(e - centre) * (e - centre) / (2 * sigma * sigma));
    return (eMv: e, iUa: y);
  });
}

double _gauss(double x, double s) => exp(-x * x / (2 * s * s));

void main() {
  group('detectPeaks', () {
    test('finds anodic peak in Gaussian data', () {
      final res = detectPeaks(
        cycleId: 'test', pts: _gaussPts(),
        minWidthMv: 20, minHeightUa: 0.5,
        footThresholdPct: 10, peakType: PeakType.both,
      );
      expect(res, isNotNull);
      expect(res!.eAnodicMv, closeTo(200, 15));
      expect(res.ipaUa, greaterThan(0));
    });

    test('returns null when height below threshold', () {
      final res = detectPeaks(
        cycleId: 'test', pts: _gaussPts(height: 0.01),
        minWidthMv: 20, minHeightUa: 0.1,
        footThresholdPct: 10, peakType: PeakType.both,
      );
      expect(res, isNull);
    });

    test('oxidationOnly skips cathodic', () {
      final pts = List.generate(100, (i) {
        final e = -200.0 + i * 4.0;
        final anodic   =  3.0 * _gauss(e - 100, 20);
        final cathodic = -2.0 * _gauss(e + 80, 20);
        return (eMv: e, iUa: anodic + cathodic);
      });
      final res = detectPeaks(
        cycleId: 't', pts: pts,
        minWidthMv: 10, minHeightUa: 0.5,
        footThresholdPct: 10, peakType: PeakType.oxidationOnly,
      );
      expect(res, isNotNull);
      expect(res!.eCathodicMv, isNull);
      expect(res.eAnodicMv,    isNotNull);
    });

    test('finds cathodic peak on CV reverse sweep (E non-monotonic)', () {
      // Forward sweep -200→500 mV with anodic peak, then reverse sweep
      // 500→-200 mV with cathodic peak: E decreases with index on the
      // reverse half, which previously broke the signed width check.
      final pts = <({double eMv, double iUa})>[];
      for (int i = 0; i <= 140; i++) {
        final e = -200.0 + i * 5.0;
        pts.add((eMv: e, iUa: 4.0 * _gauss(e - 250, 40)));
      }
      for (int i = 1; i <= 140; i++) {
        final e = 500.0 - i * 5.0;
        pts.add((eMv: e, iUa: -4.0 * _gauss(e - 100, 40)));
      }
      final res = detectPeaks(
        cycleId: 'cv', pts: pts,
        minWidthMv: 20, minHeightUa: 0.5,
        footThresholdPct: 10, peakType: PeakType.both,
      );
      expect(res, isNotNull);
      expect(res!.eAnodicMv,   closeTo(250, 15));
      expect(res.eCathodicMv,  closeTo(100, 15));
      expect(res.ipcUa,        lessThan(0));
    });

    test('returns null for fewer than 10 points', () {
      final pts = List.generate(5, (i) => (eMv: i * 10.0, iUa: 1.0));
      final res = detectPeaks(
        cycleId: 't', pts: pts,
        minWidthMv: 5, minHeightUa: 0.1,
        footThresholdPct: 10, peakType: PeakType.both,
      );
      expect(res, isNull);
    });

    test('falls back to edge regions when peak fills the scan', () {
      // Very wide peak: the foot is never reached, so the foot regions are
      // too small and the edge-percentage fallback must be used (no crash).
      final res = detectPeaks(
        cycleId: 'wide', pts: _gaussPts(sigma: 400, height: 5),
        minWidthMv: 20, minHeightUa: 0.5,
        footThresholdPct: 10, peakType: PeakType.both,
      );
      expect(res, isNotNull);
      expect(res!.eAnodicMv, isNotNull);
    });
  });

  group('findLevels', () {
    test('finds plateau', () {
      final pts = List.generate(200, (i) {
        final t = i * 0.05;
        final y = t < 4.0
            ? 5.0 * exp(-t) + 1.0
            : 3.0 + (i.isEven ? 0.04 : -0.04);
        return (tS: t, iUa: y);
      });
      final res = findLevels(
          datasetId: 'ca', pts: pts, minDurationS: 1.0, minHeightUa: 0.1);
      expect(res, isNotEmpty);
      expect(res.first.iMeanUa, closeTo(3.0, 0.2));
    });

    test('returns empty for short array', () {
      expect(
        findLevels(
          datasetId: 'd',
          pts: [(tS: 0.0, iUa: 1.0), (tS: 1.0, iUa: 1.0)],
          minDurationS: 1, minHeightUa: 0.1),
        isEmpty,
      );
    });
  });
}
