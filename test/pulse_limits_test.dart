import 'package:flutter_test/flutter_test.dart';
import 'package:ebstat_app/ble/pulse_limits.dart';

void main() {
  test('constants match firmware', () {
    expect(PulseLimits.adcWindowMs, 7);
    expect(PulseLimits.minPhaseMs, 10);
  });

  group('tIntDpvNpv', () {
    test('classic example: dE_step=5, scan_rate=50 → 100 ms', () {
      expect(PulseLimits.tIntDpvNpv(5, 50), 100);
    });
    test('floors the division', () {
      expect(PulseLimits.tIntDpvNpv(1, 3), 333);
    });
    test('null on invalid inputs', () {
      expect(PulseLimits.tIntDpvNpv(0, 50), isNull);
      expect(PulseLimits.tIntDpvNpv(5, 0), isNull);
    });
  });

  group('DPV t_pulse range', () {
    test('dE_step=5, scan_rate=50 → [10 .. 90]', () {
      final r = PulseLimits.dpvTPulseRange(5, 50);
      expect(r, isNotNull);
      expect(r!.min, 10);
      expect(r.max, 90);
    });
    test('empty range when t_int too short (dE_step=1, scan_rate=100)', () {
      final r = PulseLimits.dpvTPulseRange(1, 100); // t_int = 10
      expect(r, isNotNull);
      expect(r!.max < r.min, isTrue);
    });
    test('null on invalid inputs', () {
      expect(PulseLimits.dpvTPulseRange(0, 50), isNull);
    });
  });

  group('NPV t_pulse limit', () {
    test('classic example: dE_step=5, scan_rate=50 → t_pulse ≤ 50 ms', () {
      expect(PulseLimits.npvTPulseMax(5, 50), 50);
      final r = PulseLimits.npvTPulseRange(5, 50);
      expect(r!.min, 10);
      expect(r.max, 50);
    });
    test('empty range when t_int/2 < minPhaseMs', () {
      final r = PulseLimits.npvTPulseRange(1, 100); // t_int=10 → max=5
      expect(r!.max < r.min, isTrue);
    });
  });

  group('SWV', () {
    test('freq_max = 50 Hz at minPhaseMs = 10', () {
      expect(PulseLimits.swvFreqMax(), 50);
    });
    test('t_int from frequency', () {
      expect(PulseLimits.tIntSwv(25), 40);
      expect(PulseLimits.tIntSwv(50), 20);
      expect(PulseLimits.tIntSwv(0), isNull);
    });
  });
}
