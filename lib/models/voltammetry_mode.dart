// Parameter keys MUST match EbstatProtocol.techniqueParamNames so
// MeasurementProvider can pass them directly to buildMeasurementCmd().
enum VoltammetryMode {
  cv('Cyclic Voltammetry', 'CV'),
  ca('Chronoamperometry', 'CA'),
  swv('Square Wave Voltammetry', 'SWV'),
  dpv('Differential Pulse Voltammetry', 'DPV'),
  npv('Normal Pulse Voltammetry', 'NPV');

  const VoltammetryMode(this.fullName, this.abbreviation);

  final String fullName;
  final String abbreviation;

  /// X-axis label for the chart.
  String get xAxisLabel =>
      this == VoltammetryMode.ca ? 'Time (ms)' : 'Potential (mV)';
  String get yAxisLabel => 'Current (µA)';
}

class VoltammetryParameter {
  final String key;
  final String label;
  final String unit;
  final String hint;
  final double defaultValue;
  final double? min;
  final double? max;

  const VoltammetryParameter({
    required this.key,
    required this.label,
    required this.unit,
    required this.hint,
    required this.defaultValue,
    this.min,
    this.max,
  });
}

final Map<VoltammetryMode, List<VoltammetryParameter>> modeParameters = {
  VoltammetryMode.cv: [
    const VoltammetryParameter(
      key: 'V_start_mV', label: 'Start Potential', unit: 'mV',
      hint: '-200', defaultValue: -200, min: -1500, max: 1500,
    ),
    const VoltammetryParameter(
      key: 'V_vertex_mV', label: 'Vertex Potential', unit: 'mV',
      hint: '500', defaultValue: 500, min: -1500, max: 1500,
    ),
    const VoltammetryParameter(
      key: 'step_mV', label: 'Step Size', unit: 'mV',
      hint: '5', defaultValue: 5, min: 1, max: 50,
    ),
    const VoltammetryParameter(
      key: 'scan_rate_mV_s', label: 'Scan Rate', unit: 'mV/s',
      hint: '50', defaultValue: 50, min: 1, max: 500,
    ),
    const VoltammetryParameter(
      key: 'n_cycles', label: 'Cycles', unit: '#',
      hint: '1', defaultValue: 1, min: 1, max: 10,
    ),
  ],
  VoltammetryMode.ca: [
    const VoltammetryParameter(
      key: 'E_quiet_mV', label: 'Quiet Potential', unit: 'mV',
      hint: '0', defaultValue: 0, min: -1500, max: 1500,
    ),
    const VoltammetryParameter(
      key: 'E_step_mV', label: 'Step Potential', unit: 'mV',
      hint: '200', defaultValue: 200, min: -1500, max: 1500,
    ),
    const VoltammetryParameter(
      key: 'quiet_ms', label: 'Quiet Time', unit: 'ms',
      hint: '2000', defaultValue: 2000, min: 0, max: 30000,
    ),
    const VoltammetryParameter(
      key: 'step_ms', label: 'Step Duration', unit: 'ms',
      hint: '100', defaultValue: 100, min: 10, max: 10000,
    ),
    const VoltammetryParameter(
      key: 'samples', label: 'Samples', unit: '#',
      hint: '50', defaultValue: 50, min: 1, max: 500,
    ),
  ],
  VoltammetryMode.swv: [
    const VoltammetryParameter(
      key: 'E_start_mV', label: 'Start Potential', unit: 'mV',
      hint: '-200', defaultValue: -200, min: -1500, max: 1500,
    ),
    const VoltammetryParameter(
      key: 'E_end_mV', label: 'End Potential', unit: 'mV',
      hint: '600', defaultValue: 600, min: -1500, max: 1500,
    ),
    const VoltammetryParameter(
      key: 'dE_step_mV', label: 'Step Size', unit: 'mV',
      hint: '10', defaultValue: 10, min: 1, max: 50,
    ),
    const VoltammetryParameter(
      key: 'dE_pulse_mV', label: 'Pulse Amplitude', unit: 'mV',
      hint: '50', defaultValue: 50, min: 1, max: 200,
    ),
    const VoltammetryParameter(
      key: 'freq_hz', label: 'Frequency', unit: 'Hz',
      hint: '25', defaultValue: 25, min: 1, max: 1000,
    ),
  ],
  VoltammetryMode.dpv: [
    const VoltammetryParameter(
      key: 'E_start_mV', label: 'Start Potential', unit: 'mV',
      hint: '-200', defaultValue: -200, min: -1500, max: 1500,
    ),
    const VoltammetryParameter(
      key: 'E_end_mV', label: 'End Potential', unit: 'mV',
      hint: '600', defaultValue: 600, min: -1500, max: 1500,
    ),
    const VoltammetryParameter(
      key: 'dE_step_mV', label: 'Step Size', unit: 'mV',
      hint: '10', defaultValue: 10, min: 1, max: 50,
    ),
    const VoltammetryParameter(
      key: 'dE_pulse_mV', label: 'Pulse Amplitude', unit: 'mV',
      hint: '50', defaultValue: 50, min: 1, max: 200,
    ),
    const VoltammetryParameter(
      key: 'freq_hz', label: 'Frequency', unit: 'Hz',
      hint: '5', defaultValue: 5, min: 1, max: 200,
    ),
  ],
  VoltammetryMode.npv: [
    const VoltammetryParameter(
      key: 'E_start_mV', label: 'Start Potential', unit: 'mV',
      hint: '-200', defaultValue: -200, min: -1500, max: 1500,
    ),
    const VoltammetryParameter(
      key: 'E_end_mV', label: 'End Potential', unit: 'mV',
      hint: '600', defaultValue: 600, min: -1500, max: 1500,
    ),
    const VoltammetryParameter(
      key: 'dE_step_mV', label: 'Step Size', unit: 'mV',
      hint: '10', defaultValue: 10, min: 1, max: 50,
    ),
    const VoltammetryParameter(
      key: 'dE_pulse_mV', label: 'Pulse Amplitude', unit: 'mV',
      hint: '50', defaultValue: 50, min: 1, max: 200,
    ),
    const VoltammetryParameter(
      key: 'freq_hz', label: 'Frequency', unit: 'Hz',
      hint: '5', defaultValue: 5, min: 1, max: 200,
    ),
  ],
};
