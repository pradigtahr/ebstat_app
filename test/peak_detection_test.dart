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

void main() {
  group('detectPeaks', () {
    test('finds anodic peak in Gaussian data', () {
      final res = detectPeaks(
        cycleId: 'test', pts: _gaussPts(),
        minWidthMv: 20, minHeightUa: 0.5,
        baselineRegionPct: 15, peakType: PeakType.both,
      );
      expect(res, isNotNull);
      expect(res!.eAnodicMv, closeTo(200, 15));
      expect(res.ipaUa, greaterThan(0));
    });

    test('returns null when height below threshold', () {
      final res = detectPeaks(
        cycleId: 'test', pts: _gaussPts(height: 0.01),
        minWidthMv: 20, minHeightUa: 0.1,
        baselineRegionPct: 15, peakType: PeakType.both,
      );
      expect(res, isNull);
    });

    test('oxidationOnly skips cathodic', () {
      final pts = List.generate(100, (i) {
        final e = -200.0 + i * 4.0;
        final anodic   =  3.0 * exp(-(e - 100) * (e - 100) / (2 * 20 * 20));
        final cathodic = -2.0 * exp(-(e + 80)  * (e + 80)  / (2 * 20 * 20));
        return (eMv: e, iUa: anodic + cathodic);
      });
      final res = detectPeaks(
        cycleId: 't', pts: pts,
        minWidthMv: 10, minHeightUa: 0.5,
        baselineRegionPct: 15, peakType: PeakType.oxidationOnly,
      );
      expect(res, isNotNull);
      expect(res!.eCathodicMv, isNull);
      expect(res.eAnodicMv,    isNotNull);
    });

    test('returns null for fewer than 10 points', () {
      final pts = List.generate(5, (i) => (eMv: i * 10.0, iUa: 1.0));
      final res = detectPeaks(
        cycleId: 't', pts: pts,
        minWidthMv: 5, minHeightUa: 0.1,
        baselineRegionPct: 15, peakType: PeakType.both,
      );
      expect(res, isNull);
    });
  });

  group('findLevels', () {
    test('finds plateau', () {
      // 0-5 s: noisy, 5-10 s: stable plateau at 3 µA
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
