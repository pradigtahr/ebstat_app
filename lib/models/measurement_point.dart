class MeasurementPoint {
  final double x; // potential (mV) or time (ms) depending on mode
  final double y; // current (nA)

  const MeasurementPoint(this.x, this.y);

  List<String> toCsvRow() => [x.toStringAsFixed(4), y.toStringAsFixed(6)];
}

class MeasurementSession {
  final String mode;
  final String label;
  final Map<String, double> parameters;
  final DateTime startedAt;
  final List<MeasurementPoint> points;

  MeasurementSession({
    required this.mode,
    this.label = '',
    required this.parameters,
    required this.startedAt,
    List<MeasurementPoint>? points,
  }) : points = points ?? [];

  List<List<String>> toCsv() {
    final paramRows = parameters.entries
        .map((e) => ['${e.key}', '${e.value}'])
        .toList();
    return [
      ['EbStat — $mode measurement'],
      if (label.isNotEmpty) ['Label', label],
      ['Started', startedAt.toIso8601String()],
      ['--- Parameters ---'],
      ...paramRows,
      ['--- Data ---'],
      [mode == 'CA' ? 'Time (ms)' : 'Potential (mV)', 'Current (nA)'],
      ...points.map((p) => p.toCsvRow()),
    ];
  }
}
