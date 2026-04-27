import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../data/demo_cv_data.dart';
import '../models/measurement_point.dart';
import '../models/voltammetry_mode.dart';
import '../services/ble_service.dart';
import '../services/csv_export_service.dart';

enum MeasurementState { idle, running, paused, done }

class MeasurementProvider extends ChangeNotifier {
  VoltammetryMode? _selectedMode;
  Map<String, double> _parameters = {};
  MeasurementState _state = MeasurementState.idle;
  MeasurementSession? _session;
  String? _exportError;

  StreamSubscription<String>? _dataSub;
  Timer? _demoTimer;

  VoltammetryMode? get selectedMode => _selectedMode;
  Map<String, double> get parameters => Map.unmodifiable(_parameters);
  MeasurementState get state => _state;
  MeasurementSession? get session => _session;
  List<MeasurementPoint> get points => _session?.points ?? [];
  String? get exportError => _exportError;

  void selectMode(VoltammetryMode mode) {
    _selectedMode = mode;
    _parameters = {
      for (final p in modeParameters[mode]!) p.key: p.defaultValue,
    };
    notifyListeners();
  }

  void updateParameter(String key, double value) {
    _parameters[key] = value;
    notifyListeners();
  }

  void startMeasurement() {
    if (_selectedMode == null) return;
    _session = MeasurementSession(
      mode: _selectedMode!.abbreviation,
      parameters: Map.from(_parameters),
      startedAt: DateTime.now(),
    );
    _state = MeasurementState.running;
    _exportError = null;
    notifyListeners();

    if (BleService().isConnected) {
      _dataSub?.cancel();
      _dataSub = BleService().dataStream.listen(_onData);
    } else {
      _startDemoLoop();
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

  // ── Demo loop ──────────────────────────────────────────────────────────────

  void _startDemoLoop() {
    final pts = _generateDemoPoints();
    if (pts.isEmpty) return;

    int i = 0;
    _demoTimer?.cancel();
    _demoTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (_state != MeasurementState.running) {
        timer.cancel();
        return;
      }

      // Loop: clear chart and restart when one full scan is done
      if (i >= pts.length) {
        _session?.points.clear();
        i = 0;
      }

      _session?.points.add(pts[i]);
      i++;
      notifyListeners();
    });
  }

  List<MeasurementPoint> _generateDemoPoints() {
    switch (_selectedMode) {
      case VoltammetryMode.cv:
        return palmSenseCvData;
      case VoltammetryMode.ca:
        return _caPoints();
      case VoltammetryMode.swv:
      case VoltammetryMode.dpv:
      case VoltammetryMode.npv:
        return _pulsePoints();
      case null:
        return [];
    }
  }

  /// Chronoamperometry — Cottrell decay.
  List<MeasurementPoint> _caPoints() {
    final pts = <MeasurementPoint>[];
    for (double t = 0.05; t <= 10.0; t += 0.05) {
      pts.add(MeasurementPoint(t, 6.0 / math.sqrt(t) + 0.1));
    }
    return pts;
  }

  /// SWV / DPV / NPV — single sharp peak.
  List<MeasurementPoint> _pulsePoints() {
    final pts = <MeasurementPoint>[];
    for (double e = -400; e <= 400; e += 5) {
      final baseline = e * 0.0008;
      final peak =
          7.5 * math.exp(-math.pow(e - 150, 2) / (2 * math.pow(40, 2)));
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
    _state = MeasurementState.done;
    notifyListeners();
  }

  void resetMeasurement() {
    stopMeasurement();
    _session = null;
    _state = MeasurementState.idle;
    _exportError = null;
    notifyListeners();
  }

  Future<void> exportCsv() async {
    if (_session == null || _session!.points.isEmpty) {
      _exportError = 'No data to export.';
      notifyListeners();
      return;
    }
    try {
      _exportError = null;
      await CsvExportService.export(_session!);
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
