import 'package:flutter_test/flutter_test.dart';

import 'package:ebstat_app/services/peak_finder.dart';
import 'package:ebstat_app/models/project_session.dart';
import 'package:ebstat_app/models/measurement_point.dart';

void main() {
  group('PeakFinder', () {
    // 1. smooth pads edges correctly for a short array
    test('smooth: edge truncation on short array', () {
      final y = [1.0, 2.0, 3.0, 4.0, 5.0];
      final s = PeakFinder.smooth(y, win: 5);
      expect(s.length, equals(y.length));
      // First element: window [0..2] → (1+2+3)/3 = 2.0
      expect(s[0], closeTo(2.0, 1e-9));
      // Last element: window [2..4] → (3+4+5)/3 = 4.0
      expect(s[4], closeTo(4.0, 1e-9));
      // Middle element: window [0..4] → (1+2+3+4+5)/5 = 3.0
      expect(s[2], closeTo(3.0, 1e-9));
    });

    // 2. analyzeVoltammetry detects a positive peak in a synthetic 25-point dataset
    test('analyzeVoltammetry: detects peak at ~0.5 V', () {
      final n = 25;
      final xV = List<double>.generate(n, (i) => i * (1.0 / (n - 1)));
      final yUa = List<double>.generate(n, (i) {
        // flat baseline at 1.0 µA with triangle peak of height 6 at center (index 12)
        const peakIdx = 12;
        const peakHeight = 6.0;
        const halfWidth = 5;
        final dist = (i - peakIdx).abs();
        if (dist <= halfWidth) {
          return 1.0 + peakHeight * (1.0 - dist / halfWidth);
        }
        return 1.0;
      });

      final results = PeakFinder.analyzeVoltammetry(xV, yUa, 0);
      expect(results, isNotEmpty);
      final peak = results.first;
      // ep should be roughly 0.5 V (within 0.1)
      expect(peak.ep, closeTo(0.5, 0.1));
      // ip should be greater than 3.0 µA
      expect(peak.ip, greaterThan(3.0));
    });

    // 3. analyze returns empty for CA
    test('analyze: returns empty for CA technique', () {
      final session = MeasurementSession(
        mode: 'CA',
        displayName: 'CA Test',
        parameters: {},
        startedAt: DateTime.now(),
        points: [
          const MeasurementPoint(100, 50),
          const MeasurementPoint(200, 60),
          const MeasurementPoint(300, 55),
        ],
      );
      final results = PeakFinder.analyze(session, 0, 'CA');
      expect(results, isEmpty);
    });

    // 4. Edge case: series of length 5 returns empty from analyzeVoltammetry
    test('analyzeVoltammetry: returns empty for length-5 series', () {
      final xV = [0.0, 0.25, 0.5, 0.75, 1.0];
      final yUa = [1.0, 2.0, 5.0, 2.0, 1.0];
      final results = PeakFinder.analyzeVoltammetry(xV, yUa, 0);
      expect(results, isEmpty);
    });
  });
}
