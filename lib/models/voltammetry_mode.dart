enum VoltammetryMode {
  cv('Cyclic Voltammetry', 'CV'),
  ca('Chronoamperometry', 'CA'),
  swv('Square Wave Voltammetry', 'SWV'),
  dpv('Differential Pulse Voltammetry', 'DPV'),
  npv('Normal Pulse Voltammetry', 'NPV');

  const VoltammetryMode(this.fullName, this.abbreviation);

  final String fullName;
  final String abbreviation;
}

class VoltammetryParameter {
  final String key;
  final String label;
  final String unit;
  final String hint;
  final double defaultValue;

  const VoltammetryParameter({
    required this.key,
    required this.label,
    required this.unit,
    required this.hint,
    required this.defaultValue,
  });
}

/// Placeholder parameters for each mode — replace with real values later.
final Map<VoltammetryMode, List<VoltammetryParameter>> modeParameters = {
  VoltammetryMode.cv: [
    const VoltammetryParameter(key: 'e_start', label: 'Lorem Ipsum Start', unit: 'mV', hint: '0.0', defaultValue: 0),
    const VoltammetryParameter(key: 'e_end', label: 'Lorem Ipsum End', unit: 'mV', hint: '500.0', defaultValue: 500),
    const VoltammetryParameter(key: 'scan_rate', label: 'Lorem Scan Rate', unit: 'mV/s', hint: '50.0', defaultValue: 50),
    const VoltammetryParameter(key: 'step_e', label: 'Lorem Step Potential', unit: 'mV', hint: '5.0', defaultValue: 5),
    const VoltammetryParameter(key: 'cycles', label: 'Lorem Cycles', unit: '#', hint: '1', defaultValue: 1),
  ],
  VoltammetryMode.ca: [
    const VoltammetryParameter(key: 'e_step', label: 'Lorem Step Potential', unit: 'mV', hint: '0.0', defaultValue: 0),
    const VoltammetryParameter(key: 'e_end', label: 'Lorem End Potential', unit: 'mV', hint: '500.0', defaultValue: 500),
    const VoltammetryParameter(key: 'duration', label: 'Lorem Duration', unit: 's', hint: '10.0', defaultValue: 10),
    const VoltammetryParameter(key: 'interval', label: 'Lorem Interval', unit: 'ms', hint: '100.0', defaultValue: 100),
  ],
  VoltammetryMode.swv: [
    const VoltammetryParameter(key: 'e_start', label: 'Lorem Ipsum Start', unit: 'mV', hint: '0.0', defaultValue: 0),
    const VoltammetryParameter(key: 'e_end', label: 'Lorem Ipsum End', unit: 'mV', hint: '500.0', defaultValue: 500),
    const VoltammetryParameter(key: 'amplitude', label: 'Lorem Amplitude', unit: 'mV', hint: '25.0', defaultValue: 25),
    const VoltammetryParameter(key: 'frequency', label: 'Lorem Frequency', unit: 'Hz', hint: '25.0', defaultValue: 25),
    const VoltammetryParameter(key: 'step_e', label: 'Lorem Step Potential', unit: 'mV', hint: '5.0', defaultValue: 5),
    const VoltammetryParameter(key: 'equilibration', label: 'Lorem Equilibration', unit: 's', hint: '5.0', defaultValue: 5),
  ],
  VoltammetryMode.dpv: [
    const VoltammetryParameter(key: 'e_start', label: 'Lorem Ipsum Start', unit: 'mV', hint: '0.0', defaultValue: 0),
    const VoltammetryParameter(key: 'e_end', label: 'Lorem Ipsum End', unit: 'mV', hint: '500.0', defaultValue: 500),
    const VoltammetryParameter(key: 'pulse_amp', label: 'Lorem Pulse Amplitude', unit: 'mV', hint: '50.0', defaultValue: 50),
    const VoltammetryParameter(key: 'pulse_width', label: 'Lorem Pulse Width', unit: 'ms', hint: '50.0', defaultValue: 50),
    const VoltammetryParameter(key: 'step_e', label: 'Lorem Step Potential', unit: 'mV', hint: '5.0', defaultValue: 5),
  ],
  VoltammetryMode.npv: [
    const VoltammetryParameter(key: 'e_start', label: 'Lorem Ipsum Start', unit: 'mV', hint: '0.0', defaultValue: 0),
    const VoltammetryParameter(key: 'e_end', label: 'Lorem Ipsum End', unit: 'mV', hint: '500.0', defaultValue: 500),
    const VoltammetryParameter(key: 'pulse_width', label: 'Lorem Pulse Width', unit: 'ms', hint: '50.0', defaultValue: 50),
    const VoltammetryParameter(key: 'step_e', label: 'Lorem Step Potential', unit: 'mV', hint: '5.0', defaultValue: 5),
  ],
};
