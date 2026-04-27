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
}
