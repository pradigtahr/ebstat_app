class MeasurementPoint {
  final double x; // voltage (V) or time (s) depending on mode
  final double y; // current (µA)

  const MeasurementPoint(this.x, this.y);

  List<String> toCsvRow() => [x.toStringAsFixed(4), y.toStringAsFixed(6)];
}

class MeasurementSession {
  final String mode;
  final Map<String, double> parameters;
  final DateTime startedAt;
  final List<MeasurementPoint> points;

  MeasurementSession({
    required this.mode,
    required this.parameters,
    required this.startedAt,
    List<MeasurementPoint>? points,
  }) : points = points ?? [];

  List<List<String>> toCsv() {
    final header = ['EbStat — $mode measurement'];
    final paramRows = parameters.entries
        .map((e) => ['${e.key}', '${e.value}'])
        .toList();
    final dataHeader = ['x', 'y (µA)'];
    final dataRows = points.map((p) => p.toCsvRow()).toList();

    return [
      header,
      ['Started', startedAt.toIso8601String()],
      ['--- Parameters ---'],
      ...paramRows,
      ['--- Data ---'],
      dataHeader,
      ...dataRows,
    ];
  }
}
