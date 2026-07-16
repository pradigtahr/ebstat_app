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

  /// UI-only rename override for presentation. Never written to exports —
  /// the canonical CSV/XLSX format always uses [displayName].
  String? customName;

  /// UI-only per-cycle rename overrides, keyed by cycle number.
  final Map<int, String> customCycleNames = {};

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

  /// Label shown in the UI: the rename override when set, else [displayName].
  String get uiName =>
      (customName != null && customName!.trim().isNotEmpty)
          ? customName!
          : displayName;

  /// UI label for a cycle: the rename override when set, else "Cycle N".
  String uiCycleName(int cycleNum) {
    final n = customCycleNames[cycleNum];
    return (n != null && n.trim().isNotEmpty) ? n : 'Cycle $cycleNum';
  }

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
