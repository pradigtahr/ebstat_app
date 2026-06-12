import 'measurement_point.dart';

class MeasurementSession {
  final String mode;
  final String label;
  final String displayName;
  final Map<String, double> parameters;
  final DateTime startedAt;
  final List<MeasurementPoint> points;
  final List<double?> sgPoints;
  final bool sgEnabled;

  MeasurementSession({
    required this.mode,
    this.label = '',
    required this.displayName,
    required this.parameters,
    required this.startedAt,
    this.sgEnabled = false,
    List<MeasurementPoint>? points,
  })  : points   = points ?? [],
        sgPoints = [];

  Set<int> get cycles => {
        for (final p in points)
          if (p.cycle != null) p.cycle!,
      };

  bool get hasSgData => sgPoints.any((v) => v != null);

  void deleteCycle(int cycleNum) =>
      points.removeWhere((p) => p.cycle == cycleNum);
}

class ProjectSession {
  final String modeName;
  final List<MeasurementSession> measurements;

  ProjectSession({required this.modeName}) : measurements = [];

  void addMeasurement(MeasurementSession session) => measurements.add(session);

  void deleteMeasurement(int index) {
    if (index < 0 || index >= measurements.length) return;
    measurements.removeAt(index);
  }
}
