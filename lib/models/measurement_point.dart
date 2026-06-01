class MeasurementPoint {
  final double x; // potential (mV) or time (ms) depending on mode
  final double y; // current (nA)
  final int? cycle;        // CV only: cycle number (1-based)
  final String? direction; // CV only: 'start', 'fwd', or 'rev'

  const MeasurementPoint(this.x, this.y, {this.cycle, this.direction});

  List<String> toCsvRow() => [x.toStringAsFixed(4), y.toStringAsFixed(6)];
}
