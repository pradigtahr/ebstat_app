import 'peak_type.dart';

class PeakResult {
  final int    measurementIdx;
  final int?   cycleNum;
  final String label;
  final double ep;         // V
  final double ip;         // µA (absolute)
  final int    apexIndex;
  final int    onsetIndex;
  final int    fitLo;
  final int    fitHi;
  final double baselineSlope;     // µA/V
  final double baselineIntercept; // µA
  final bool   isAuto;

  // Fields added for manual tangent annotation:
  final PeakType?  peakType;          // explicit type; falls back to derivedPeakType
  final double?    tangentSlope;      // nA/mV slope of the manually-set tangent line
  final double?    tangentBaselineX;  // x-coord of baseline reference point (mV)
  final double?    tangentBaselineY;  // y-coord of baseline reference point (nA)
  final double?    iBaseline;         // current at Ep from tangent intersection (nA)

  const PeakResult({
    required this.measurementIdx,
    this.cycleNum,
    required this.label,
    required this.ep,
    required this.ip,
    required this.apexIndex,
    required this.onsetIndex,
    required this.fitLo,
    required this.fitHi,
    required this.baselineSlope,
    required this.baselineIntercept,
    required this.isAuto,
    this.peakType,
    this.tangentSlope,
    this.tangentBaselineX,
    this.tangentBaselineY,
    this.iBaseline,
  });

  /// Effective peak type: explicit peakType first, then derived from label.
  PeakType get effectivePeakType => peakType ??
      (label.toLowerCase().contains('cathodic')
          ? PeakType.cathodic
          : PeakType.anodic);

  PeakResult copyWith({
    int?     measurementIdx,
    int?     cycleNum,
    String?  label,
    double?  ep,
    double?  ip,
    int?     apexIndex,
    int?     onsetIndex,
    int?     fitLo,
    int?     fitHi,
    double?  baselineSlope,
    double?  baselineIntercept,
    bool?    isAuto,
    PeakType? peakType,
    double?  tangentSlope,
    double?  tangentBaselineX,
    double?  tangentBaselineY,
    double?  iBaseline,
  }) =>
      PeakResult(
        measurementIdx:    measurementIdx    ?? this.measurementIdx,
        cycleNum:          cycleNum          ?? this.cycleNum,
        label:             label             ?? this.label,
        ep:                ep                ?? this.ep,
        ip:                ip                ?? this.ip,
        apexIndex:         apexIndex         ?? this.apexIndex,
        onsetIndex:        onsetIndex        ?? this.onsetIndex,
        fitLo:             fitLo             ?? this.fitLo,
        fitHi:             fitHi             ?? this.fitHi,
        baselineSlope:     baselineSlope     ?? this.baselineSlope,
        baselineIntercept: baselineIntercept ?? this.baselineIntercept,
        isAuto:            isAuto            ?? this.isAuto,
        peakType:          peakType          ?? this.peakType,
        tangentSlope:      tangentSlope      ?? this.tangentSlope,
        tangentBaselineX:  tangentBaselineX  ?? this.tangentBaselineX,
        tangentBaselineY:  tangentBaselineY  ?? this.tangentBaselineY,
        iBaseline:         iBaseline         ?? this.iBaseline,
      );
}
