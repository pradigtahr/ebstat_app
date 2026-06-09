import 'measurement_point.dart';
import 'peak_result.dart';
import 'peak_type.dart';

export 'peak_type.dart';

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
  final String displayName;
  final Map<String, double> parameters;
  final DateTime startedAt;
  final List<MeasurementPoint> points;
  /// SG smoothed current values indexed from 0 (null = missing).
  final List<double?> sgPoints;

  MeasurementSession({
    required this.mode,
    this.label = '',
    required this.displayName,
    required this.parameters,
    required this.startedAt,
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

  /// Peaks registered via the tangent-line AnnotationScreen.
  final List<PeakResult> registeredPeaks;

  ProjectSession({required this.modeName})
      : measurements    = [],
        peaks           = [],
        registeredPeaks = [];

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

  /// Register (or replace) a peak from the AnnotationScreen.
  void registerPeak(PeakResult peak) {
    registeredPeaks.removeWhere(
      (p) => p.effectivePeakType == peak.effectivePeakType &&
             p.measurementIdx == peak.measurementIdx,
    );
    registeredPeaks.add(peak);
  }

  void deleteMeasurement(int index) {
    if (index < 0 || index >= measurements.length) return;
    measurements.removeAt(index);
    peaks.removeWhere((p) => p.measurementIndex == index);
    registeredPeaks.removeWhere((p) => p.measurementIdx == index);
    final shiftedPeaks = peaks
        .where((p) => p.measurementIndex > index)
        .map((p) => PeakAnnotation(
              measurementIndex: p.measurementIndex - 1,
              pointIndex:       p.pointIndex,
              type:             p.type,
              point:            p.point,
            ))
        .toList();
    peaks.removeWhere((p) => p.measurementIndex > index);
    peaks.addAll(shiftedPeaks);
    final shiftedResults = registeredPeaks
        .where((p) => p.measurementIdx > index)
        .map((p) => p.copyWith(measurementIdx: p.measurementIdx - 1))
        .toList();
    registeredPeaks.removeWhere((p) => p.measurementIdx > index);
    registeredPeaks.addAll(shiftedResults);
  }

  // ── Experiment summary getters (from registered tangent peaks) ─────────────

  PeakResult? get anodicPeak => registeredPeaks
      .where((p) => p.effectivePeakType == PeakType.anodic)
      .firstOrNull;

  PeakResult? get cathodicPeak => registeredPeaks
      .where((p) => p.effectivePeakType == PeakType.cathodic)
      .firstOrNull;

  double? get ipa => anodicPeak?.ip;
  double? get ipc => cathodicPeak?.ip;
  /// Epa in mV (ep field is in V).
  double? get epa => anodicPeak != null ? anodicPeak!.ep * 1000 : null;
  /// Epc in mV (ep field is in V).
  double? get epc => cathodicPeak != null ? cathodicPeak!.ep * 1000 : null;
}
