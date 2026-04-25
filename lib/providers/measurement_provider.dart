import 'dart:async';
import 'package:flutter/material.dart';

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

  VoltammetryMode? get selectedMode => _selectedMode;
  Map<String, double> get parameters => Map.unmodifiable(_parameters);
  MeasurementState get state => _state;
  MeasurementSession? get session => _session;
  List<MeasurementPoint> get points => _session?.points ?? [];
  String? get exportError => _exportError;

  void selectMode(VoltammetryMode mode) {
    _selectedMode = mode;
    // Reset to defaults for the chosen mode
    _parameters = {
      for (final p in modeParameters[mode]!)
        p.key: p.defaultValue,
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

    _dataSub?.cancel();
    _dataSub = BleService().dataStream.listen(_onData);
  }

  void _onData(String raw) {
    if (_state != MeasurementState.running) return;

    // Parse format "x,y" from BLE. Falls back to index-based if only one value.
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

  void stopMeasurement() {
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
    _dataSub?.cancel();
    super.dispose();
  }
}
