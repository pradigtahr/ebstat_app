import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../models/measurement_point.dart';
import '../models/project_session.dart';
import '../models/voltammetry_mode.dart';
import '../services/ble_service.dart';
import '../services/xlsx_export_service.dart';

enum MeasurementState { idle, running, paused, done }

class MeasurementProvider extends ChangeNotifier {
  VoltammetryMode? _selectedMode;
  Map<String, double> _parameters = {};
  MeasurementState _state = MeasurementState.idle;
  MeasurementSession? _session;
  ProjectSession? _project;
  String? _exportError;
  String _nextLabel = '';

  StreamSubscription<String>? _dataSub;
  Timer? _demoTimer;

  VoltammetryMode? get selectedMode => _selectedMode;
  Map<String, double> get parameters => Map.unmodifiable(_parameters);
  MeasurementState get state => _state;
  MeasurementSession? get session => _session;
  ProjectSession? get project => _project;
  List<MeasurementPoint> get points => _session?.points ?? [];
  String? get exportError => _exportError;

  void selectMode(VoltammetryMode mode) {
    _selectedMode = mode;
    _parameters = {
      for (final p in modeParameters[mode]!) p.key: p.defaultValue,
    };
    _project = ProjectSession(modeName: mode.abbreviation);
    _session = null;
    _state = MeasurementState.idle;
    _exportError = null;
    notifyListeners();
  }

  void updateParameter(String key, double value) {
    _parameters[key] = value;
    notifyListeners();
  }

  void setNextLabel(String label) => _nextLabel = label;

  void startMeasurement() {
    if (_selectedMode == null) return;
    _project ??= ProjectSession(modeName: _selectedMode!.abbreviation);
    _session = MeasurementSession(
      mode: _selectedMode!.abbreviation,
      label: _nextLabel,
      parameters: Map.from(_parameters),
      startedAt: DateTime.now(),
    );
    _nextLabel = '';
    _state = MeasurementState.running;
    _exportError = null;
    notifyListeners();

    if (BleService().isConnected) {
      _dataSub?.cancel();
      _dataSub = BleService().rawLines.listen(_onData);
    } else {
      _startDemoSimulation();
    }
  }

  // ── BLE data handler ───────────────────────────────────────────────────────

  void _onData(String raw) {
    if (_state != MeasurementState.running) return;
    final parts = raw.split(',');
    double? x, y;
    if (parts.length >= 2) {
      x = double.tryParse(parts[0].trim());
      y = double.tryParse(parts[1].trim());
    } else if (parts.length == 1) {
      y = double.tryParse(parts[0].trim());
      x = _session!.points.length.toDouble();
    }
    if (x != null && y != null) {
      _session!.points.add(MeasurementPoint(x, y));
      notifyListeners();
    }
  }

  // ── Demo simulation (single run, stops automatically) ─────────────────────

  void _startDemoSimulation() {
    final scanIndex = (_project?.measurements.length ?? 0) % 3;
    final pts = _getDemoPoints(scanIndex);
    if (pts.isEmpty) return;

    int i = 0;
    _demoTimer?.cancel();
    _demoTimer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      if (_state != MeasurementState.running) {
        timer.cancel();
        return;
      }
      if (i >= pts.length) {
        timer.cancel();
        stopMeasurement();
        return;
      }
      _session?.points.add(pts[i]);
      i++;
      notifyListeners();
    });
  }

  List<MeasurementPoint> _getDemoPoints(int scanIndex) {
    switch (_selectedMode) {
      case VoltammetryMode.cv:
        return _cvPoints(scanIndex);
      case VoltammetryMode.ca:
        return _caPoints(scanIndex);
      case VoltammetryMode.swv:
      case VoltammetryMode.dpv:
      case VoltammetryMode.npv:
        return _pulsePoints(scanIndex);
      case null:
        return [];
    }
  }

  /// Full cyclic voltammogram: forward sweep + backward sweep.
  /// Produces a recognisable CV with cathodic dip and anodic peak.
  List<MeasurementPoint> _cvPoints(int scanIndex) {
    // Scale peak amplitude to simulate different concentrations
    final scale = [1.0, 1.55, 0.65][scanIndex % 3];

    const eStart = -200.0; // mV
    const eVertex = 500.0; // mV
    const ePc = 150.0;     // cathodic peak potential
    const ePa = 220.0;     // anodic peak potential (ΔEp ≈ 70 mV)
    const iPc = 7.0;       // base cathodic peak height (µA)
    const iPa = 5.5;       // base anodic peak height (µA)
    const sigma = 50.0;    // peak width (mV)
    const step = 5.0;

    final pts = <MeasurementPoint>[];

    // Forward scan: eStart → eVertex
    for (double e = eStart; e <= eVertex; e += step) {
      final baseline = -0.4 * scale;
      final cathodic =
          -iPc * scale * math.exp(-math.pow(e - ePc, 2) / (2 * sigma * sigma));
      pts.add(MeasurementPoint(e, baseline + cathodic));
    }

    // Backward scan: eVertex → eStart (skip vertex to avoid duplicate)
    for (double e = eVertex - step; e >= eStart; e -= step) {
      final baseline = 0.3 * scale;
      final anodic =
          iPa * scale * math.exp(-math.pow(e - ePa, 2) / (2 * sigma * sigma));
      pts.add(MeasurementPoint(e, baseline + anodic));
    }

    return pts;
  }

  /// Chronoamperometry — Cottrell decay.
  List<MeasurementPoint> _caPoints(int scanIndex) {
    final scale = [1.0, 1.4, 0.7][scanIndex % 3];
    final pts = <MeasurementPoint>[];
    for (double t = 0.05; t <= 10.0; t += 0.05) {
      pts.add(MeasurementPoint(t, scale * (6.0 / math.sqrt(t) + 0.1)));
    }
    return pts;
  }

  /// SWV / DPV / NPV — single sharp peak.
  List<MeasurementPoint> _pulsePoints(int scanIndex) {
    final scale = [1.0, 1.4, 0.7][scanIndex % 3];
    final pts = <MeasurementPoint>[];
    for (double e = -400; e <= 400; e += 5) {
      final baseline = e * 0.0008;
      final peak = scale *
          7.5 *
          math.exp(-math.pow(e - 150, 2) / (2 * math.pow(40, 2)));
      pts.add(MeasurementPoint(e, baseline + peak));
    }
    return pts;
  }

  // ── Controls ───────────────────────────────────────────────────────────────

  void stopMeasurement() {
    _demoTimer?.cancel();
    _demoTimer = null;
    _dataSub?.cancel();
    _dataSub = null;
    if (_session != null && _session!.points.isNotEmpty) {
      _project?.addMeasurement(_session!);
    }
    _state = MeasurementState.done;
    notifyListeners();
  }

  /// Resets the current in-progress session but keeps the project intact.
  void resetMeasurement() {
    _demoTimer?.cancel();
    _demoTimer = null;
    _dataSub?.cancel();
    _dataSub = null;
    _session = null;
    _state = MeasurementState.idle;
    _exportError = null;
    notifyListeners();
  }

  void annotatePoint(int measurementIndex, int pointIndex, PeakType type) {
    if (_project == null) return;
    final session = _project!.measurements[measurementIndex];
    if (pointIndex >= session.points.length) return;
    _project!.annotatePeak(PeakAnnotation(
      measurementIndex: measurementIndex,
      pointIndex: pointIndex,
      type: type,
      point: session.points[pointIndex],
    ));
    notifyListeners();
  }

  void removePeakAnnotation(int measurementIndex, PeakType type) {
    _project?.removePeak(measurementIndex, type);
    notifyListeners();
  }

  void deleteMeasurement(int index) {
    _project?.deleteMeasurement(index);
    notifyListeners();
  }

  Future<void> exportProject() async {
    if (_project == null || _project!.measurements.isEmpty) {
      _exportError = 'No data to export.';
      notifyListeners();
      return;
    }
    try {
      _exportError = null;
      await XlsxExportService.export(_project!);
    } catch (e) {
      _exportError = 'Export failed: $e';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _demoTimer?.cancel();
    _dataSub?.cancel();
    super.dispose();
  }
}
