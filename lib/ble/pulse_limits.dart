// Mirrors the pulse-method parameter guards in the EBstat firmware so the app
// can validate DPV/NPV/SWV parameters before sending a command (the firmware
// rejects invalid commands with a single "# ERR: ..." line and no data).
//
// All limits derive from the interval time:
//   DPV / NPV: t_int_ms = dE_step_mV * 1000 / scan_rate_mV_s
//   SWV:       t_int_ms = 1000 / freq_hz
class PulseLimits {
  /// Firmware CFG_ADC_READ_MS — length of one averaged ADC read.
  /// COUPLED to firmware CFG_ADC_AVG_N: if the firmware changes its averaging
  /// count, this constant must change with it.
  static const int adcWindowMs = 7;

  /// Minimum width of any potential phase (ADC window + scheduling margin).
  static const int minPhaseMs = adcWindowMs + 3; // = 10 ms

  /// DPV/NPV interval time in ms, or null when inputs are not yet valid.
  static int? tIntDpvNpv(int dEstepMv, int scanRateMvS) {
    if (dEstepMv < 1 || scanRateMvS < 1) return null;
    return (dEstepMv * 1000) ~/ scanRateMvS;
  }

  /// SWV interval time in ms, or null when freq is not yet valid.
  static int? tIntSwv(int freqHz) {
    if (freqHz < 1) return null;
    return 1000 ~/ freqHz;
  }

  /// DPV: allowed t_pulse range [minPhaseMs .. t_int - minPhaseMs].
  /// Returns null when inputs are not yet valid. The returned range may be
  /// empty (max < min) when t_int is too short for any pulse.
  static ({int min, int max})? dpvTPulseRange(int dEstepMv, int scanRateMvS) {
    final tInt = tIntDpvNpv(dEstepMv, scanRateMvS);
    if (tInt == null) return null;
    return (min: minPhaseMs, max: tInt - minPhaseMs);
  }

  /// NPV: maximum t_pulse = t_int / 2 (PalmSens rule), or null when inputs
  /// are not yet valid.
  static int? npvTPulseMax(int dEstepMv, int scanRateMvS) {
    final tInt = tIntDpvNpv(dEstepMv, scanRateMvS);
    if (tInt == null) return null;
    return tInt ~/ 2;
  }

  /// NPV: allowed t_pulse range [minPhaseMs .. t_int/2], or null when inputs
  /// are not yet valid. May be empty (max < min) when t_int is too short.
  static ({int min, int max})? npvTPulseRange(int dEstepMv, int scanRateMvS) {
    final maxP = npvTPulseMax(dEstepMv, scanRateMvS);
    if (maxP == null) return null;
    return (min: minPhaseMs, max: maxP);
  }

  /// SWV: maximum frequency such that each half-cycle is >= minPhaseMs.
  static int swvFreqMax() => 1000 ~/ (2 * minPhaseMs); // = 50 Hz
}
