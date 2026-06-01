import 'measurement_point.dart';

enum PeakType { cathodic, anodic }

class PeakAnnotation {
  final int measurementIndex;
  final int pointIndex;
  final PeakType type;
  final MeasurementPoint point;

  const PeakAnnotation({
    required this.measurementIndex,
    required this.pointIndex,
    required this.type,
    required this.point,
  });
}

class MeasurementSession {
  final String mode;
  final String label;
  /// Human-readable name for the measurement tree, e.g. "Cyclic Voltammetry 1"
  final String displayName;
  final Map<String, double> parameters;
  final DateTime startedAt;
  final List<MeasurementPoint> points;
  /// SG Savitzky–Golay smoothed current values, indexed from 0 (null = missing).
  /// Populated after DONE from firmware SG,<idx>,<current_nA> lines.
  final List<double?> sgPoints;

  MeasurementSession({
    required this.mode,
    this.label = '',
    required this.displayName,
    required this.parameters,
    required this.startedAt,
    List<MeasurementPoint>? points,
  })  : points = points ?? [],
        sgPoints = [];

  /// Distinct cycle numbers in this session (CV only).
  Set<int> get cycles => {
        for (final p in points)
          if (p.cycle != null) p.cycle!,
      };

  bool get hasSgData => sgPoints.any((v) => v != null);

  /// Remove all points belonging to [cycleNum] (CV only).
  void deleteCycle(int cycleNum) =>
      points.removeWhere((p) => p.cycle == cycleNum);

  List<List<String>> toCsv() {
    final hasCycleData = points.any((p) => p.cycle != null);
    final paramRows =
        parameters.entries.map((e) => [e.key, '${e.value}']).toList();
    return [
      ['EbStat — $mode measurement'],
      if (label.isNotEmpty) ['Label', label],
      ['Name', displayName],
      ['Started', startedAt.toIso8601String()],
      ['--- Parameters ---'],
      ...paramRows,
      ['--- Data ---'],
      [
        mode == 'CA' ? 'Time (ms)' : 'Potential (mV)',
        'Current (nA)',
        if (hasCycleData) ...['Cycle', 'Direction'],
      ],
      ...points.map((p) => [
            ...p.toCsvRow(),
            if (hasCycleData) ...['${p.cycle ?? ''}', p.direction ?? ''],
          ]),
    ];
  }
}

class ProjectSession {
  final String modeName;
  final List<MeasurementSession> measurements;
  final List<PeakAnnotation> peaks;

  ProjectSession({required this.modeName})
      : measurements = [],
        peaks = [];

  void addMeasurement(MeasurementSession session) => measurements.add(session);

  void annotatePeak(PeakAnnotation peak) {
    peaks.removeWhere(
      (p) => p.measurementIndex == peak.measurementIndex && p.type == peak.type,
    );
    peaks.add(peak);
  }

  void removePeak(int measurementIndex, PeakType type) {
    peaks.removeWhere(
      (p) => p.measurementIndex == measurementIndex && p.type == type,
    );
  }

  void deleteMeasurement(int index) {
    if (index < 0 || index >= measurements.length) return;
    measurements.removeAt(index);
    peaks.removeWhere((p) => p.measurementIndex == index);
    final shifted = peaks
        .where((p) => p.measurementIndex > index)
        .map((p) => PeakAnnotation(
              measurementIndex: p.measurementIndex - 1,
              pointIndex: p.pointIndex,
              type: p.type,
              point: p.point,
            ))
        .toList();
    peaks.removeWhere((p) => p.measurementIndex > index);
    peaks.addAll(shifted);
  }
}
