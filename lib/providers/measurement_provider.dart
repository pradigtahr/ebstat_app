import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../ble/protocol.dart';
import '../models/measurement_point.dart';
import '../models/project_session.dart';
import '../models/voltammetry_mode.dart';
import '../services/ble_service.dart';
import '../services/transcript_service.dart';
import '../services/xlsx_export_service.dart';

enum MeasurementState { idle, running, done }

class MeasurementProvider extends ChangeNotifier {
  VoltammetryMode?      _selectedMode;
  Map<String, double>   _parameters  = {};
  MeasurementState      _state       = MeasurementState.idle;
  MeasurementSession?   _session;
  ProjectSession?       _project;
  String?               _exportError;
  String                _nextLabel   = '';
  ProgressUpdate?       _progress;
  String?               _lastBleRow;

  StreamSubscription<String>?         _dataSub;
  StreamSubscription<ProgressUpdate>? _progressSub;
  Timer?                              _demoTimer;

  // ── Getters ───────────────────────────────────────────────────────────────
  VoltammetryMode?      get selectedMode => _selectedMode;
  Map<String, double>   get parameters   => Map.unmodifiable(_parameters);
  MeasurementState      get state        => _state;
  MeasurementSession?   get session      => _session;
  ProjectSession?       get project      => _project;
  List<MeasurementPoint> get points      => _session?.points ?? [];
  String?               get exportError  => _exportError;
  ProgressUpdate?       get progress     => _progress;
  String?               get lastBleRow   => _lastBleRow;

  void selectMode(VoltammetryMode mode) {
    _selectedMode = mode;
    _parameters   = {
      for (final p in modeParameters[mode]!) p.key: p.defaultValue,
    };
    _project = ProjectSession(modeName: mode.abbreviation);
    _session = null;
    _state   = MeasurementState.idle;
    _exportError = null;
    notifyListeners();
  }

  void updateParameter(String key, double value) {
    _parameters[key] = value;
    notifyListeners();
  }

  void setNextLabel(String label) => _nextLabel = label;

  // ═══════════════════════════════════════════════════════════════════════════
  // Start
  // ═══════════════════════════════════════════════════════════════════════════

  void startMeasurement() {
    if (_selectedMode == null) return;
    _project ??= ProjectSession(modeName: _selectedMode!.abbreviation);
    _session = MeasurementSession(
      mode:       _selectedMode!.abbreviation,
      label:      _nextLabel,
      parameters: Map.from(_parameters),
      startedAt:  DateTime.now(),
    );
    _nextLabel   = '';
    _state       = MeasurementState.running;
    _exportError = null;
    _progress    = null;
    _lastBleRow  = null;
    notifyListeners();

    if (BleService().isConnected) {
      _startBleMeasurement();
    } else {
      _startDemoSimulation();
    }
  }

  // ── BLE path ──────────────────────────────────────────────────────────────

  void _startBleMeasurement() {
    final mode     = _selectedMode!.abbreviation;
    final paramMap = <String, dynamic>{
      for (final e in _parameters.entries) e.key: e.value.round(),
    };
    final cmd = EbstatProtocol.buildMeasurementCmd(mode, paramMap);

    bool headerSeen = false;

    _dataSub = BleService().rawLines.listen((line) {
      if (_state != MeasurementState.running) return;
      if (FwTerminator.is_(line) || EbstatProtocol.isMetadata(line)) return;
      if (!headerSeen) {
        headerSeen = true; // first non-# line is the CSV header
        return;
      }
      _lastBleRow = line;
      final cols = EbstatProtocol.parseCsvLine(line);
      if (cols.length >= 2) {
        final x = double.tryParse(cols[0]);
        final y = double.tryParse(cols[1]);
        if (x != null && y != null) {
          _session!.points.add(MeasurementPoint(x, y));
          notifyListeners();
        }
      }
    });

    _progressSub = BleService().progressStream.listen((prog) {
      _progress = prog;
      notifyListeners();
    });

    BleService()
        .sendCommand(cmd)
        .then(_onBleRunComplete)
        .catchError(_onBleRunError);
  }

  Future<void> _onBleRunComplete(RunResult result) async {
    _dataSub?.cancel();
    _dataSub = null;
    _progressSub?.cancel();
    _progressSub = null;
    _progress   = null;

    if (_session != null && _session!.points.isNotEmpty) {
      _project?.addMeasurement(_session!);
      try {
        await TranscriptService.save(
          result:    result,
          technique: _session!.mode,
          label:     _session!.label,
          startedAt: _session!.startedAt,
          points:    _session!.points,
        );
      } catch (_) {
        // transcript save is best-effort
      }
    }
    _state = MeasurementState.done;
    notifyListeners();
  }

  void _onBleRunError(Object error) {
    _dataSub?.cancel();
    _dataSub = null;
    _progressSub?.cancel();
    _progressSub = null;
    _progress    = null;
    if (_session != null && _session!.points.isNotEmpty) {
      _project?.addMeasurement(_session!);
    }
    _state       = MeasurementState.done;
    _exportError = error is BleDisconnectedException
        ? 'Device disconnected mid-run'
        : 'BLE error: $error';
    notifyListeners();
  }

  // ── Demo simulation ───────────────────────────────────────────────────────

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
        _finishDemo();
        return;
      }
      _session?.points.add(pts[i]);
      i++;
      notifyListeners();
    });
  }

  void _finishDemo() {
    if (_session != null && _session!.points.isNotEmpty) {
      _project?.addMeasurement(_session!);
    }
    _state = MeasurementState.done;
    notifyListeners();
  }

  List<MeasurementPoint> _getDemoPoints(int scanIndex) {
    return switch (_selectedMode) {
      VoltammetryMode.cv  => _cvPoints(scanIndex),
      VoltammetryMode.ca  => _caPoints(scanIndex),
      _                   => _pulsePoints(scanIndex),
    };
  }

  List<MeasurementPoint> _cvPoints(int scanIndex) {
    final scale = [1.0, 1.55, 0.65][scanIndex % 3];
    const eStart = -200.0, eVertex = 500.0;
    const ePc = 150.0, ePa = 220.0;
    const iPc = 7.0,  iPa = 5.5, sigma = 50.0, step = 5.0;
    final pts = <MeasurementPoint>[];
    for (double e = eStart; e <= eVertex; e += step) {
      final cathodic =
          -iPc * scale * math.exp(-math.pow(e - ePc, 2) / (2 * sigma * sigma));
      pts.add(MeasurementPoint(e, -0.4 * scale + cathodic));
    }
    for (double e = eVertex - step; e >= eStart; e -= step) {
      final anodic =
          iPa * scale * math.exp(-math.pow(e - ePa, 2) / (2 * sigma * sigma));
      pts.add(MeasurementPoint(e, 0.3 * scale + anodic));
    }
    return pts;
  }

  List<MeasurementPoint> _caPoints(int scanIndex) {
    final scale = [1.0, 1.4, 0.7][scanIndex % 3];
    final pts = <MeasurementPoint>[];
    for (double t = 0.05; t <= 10.0; t += 0.05) {
      pts.add(MeasurementPoint(t, scale * (6.0 / math.sqrt(t) + 0.1)));
    }
    return pts;
  }

  List<MeasurementPoint> _pulsePoints(int scanIndex) {
    final scale = [1.0, 1.4, 0.7][scanIndex % 3];
    final pts = <MeasurementPoint>[];
    for (double e = -400; e <= 400; e += 5) {
      final peak = scale *
          7.5 *
          math.exp(-math.pow(e - 150, 2) / (2 * math.pow(40, 2)));
      pts.add(MeasurementPoint(e, e * 0.0008 + peak));
    }
    return pts;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Controls
  // ═══════════════════════════════════════════════════════════════════════════

  void stopMeasurement() {
    if (BleService().isConnected && _state == MeasurementState.running) {
      BleService().sendStop();
      // State transitions in _onBleRunComplete when ABORTED arrives
      return;
    }
    _demoTimer?.cancel();
    _demoTimer = null;
    _dataSub?.cancel();
    _dataSub = null;
    _progressSub?.cancel();
    _progressSub = null;
    if (_session != null && _session!.points.isNotEmpty) {
      _project?.addMeasurement(_session!);
    }
    _state = MeasurementState.done;
    notifyListeners();
  }

  void resetMeasurement() {
    _demoTimer?.cancel();
    _demoTimer = null;
    _dataSub?.cancel();
    _dataSub = null;
    _progressSub?.cancel();
    _progressSub = null;
    _session     = null;
    _state       = MeasurementState.idle;
    _exportError = null;
    _progress    = null;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Annotations / project
  // ═══════════════════════════════════════════════════════════════════════════

  void annotatePoint(int measurementIndex, int pointIndex, PeakType type) {
    if (_project == null) return;
    final session = _project!.measurements[measurementIndex];
    if (pointIndex >= session.points.length) return;
    _project!.annotatePeak(PeakAnnotation(
      measurementIndex: measurementIndex,
      pointIndex:       pointIndex,
      type:             type,
      point:            session.points[pointIndex],
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

  // ═══════════════════════════════════════════════════════════════════════════
  // Export
  // ═══════════════════════════════════════════════════════════════════════════

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
    _progressSub?.cancel();
    super.dispose();
  }
}
