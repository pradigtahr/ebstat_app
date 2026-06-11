import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ble/protocol.dart';
import '../models/measurement_point.dart';
import '../models/project_session.dart';
import '../models/voltammetry_mode.dart';
import '../services/ble_service.dart';
import '../services/transcript_service.dart';
import '../services/xlsx_export_service.dart';

enum MeasurementState { idle, running, done }

class MeasurementProvider extends ChangeNotifier {
  // ── Locked LMP91000 constants ─────────────────────────────────────────────
  // biasSign MUST be 1 (POS): the firmware bias resolver assumes positive sign.
  // refSrc   MUST be 1 (EXT): firmware drives VREF from the MCP4725 DAC; with
  //   INT the chip ignores the DAC and uses its internal divider, producing
  //   sawtooth artifacts on every VREF switch.
  static const int kLmpRload    = 0; // 10 Ω
  static const int kLmpIntz     = 1; // 50 %
  static const int kLmpBiasSign = 1; // POS — required by firmware
  static const int kLmpBiasPct  = 0; // per-step override by firmware
  static const int kLmpRefSrc   = 1; // EXT — required for DAC VREF
  VoltammetryMode?      _selectedMode;
  Map<String, double>   _parameters  = {};
  MeasurementState      _state       = MeasurementState.idle;
  MeasurementSession?   _session;
  ProjectSession?       _project;
  String?               _exportError;
  String                _nextLabel   = '';
  ProgressUpdate?       _progress;
  String?               _lastBleRow;
  bool                  _sgEnabled       = false;
  int                   _sgFilterWindow  = -1; // -1 = None (UI placeholder; TODO: implement SG filtering)
  int                   _selectedGainCode = 5; // default 35 kΩ (±65 µA)

  StreamSubscription<String>?         _dataSub;
  StreamSubscription<ProgressUpdate>? _progressSub;
  Timer?                              _demoTimer;
  Timer?                              _sgTimer;
  Timer?                              _silenceTimer;
  Timer?                              _updateTimer;     // 50 ms UI-flush during live BLE run
  bool                                _progressReceived = false;
  bool                                _runCompleted     = false;
  VoidCallback?                       _navigateToAnalysis;
  VoidCallback?                       _popToParameters;
  void Function(String)?              _onWarning;

  // ── Getters ───────────────────────────────────────────────────────────────
  VoltammetryMode?       get selectedMode => _selectedMode;
  Map<String, double>    get parameters   => Map.unmodifiable(_parameters);
  MeasurementState       get state        => _state;
  MeasurementSession?    get session      => _session;
  ProjectSession?        get project      => _project;
  List<MeasurementPoint> get points       => _session?.points ?? [];
  String?                get exportError  => _exportError;
  ProgressUpdate?        get progress     => _progress;
  String?                get lastBleRow   => _lastBleRow;
  bool                   get sgEnabled        => _sgEnabled;
  int                    get sgFilterWindow   => _sgFilterWindow;
  int                    get selectedGainCode => _selectedGainCode;

  MeasurementProvider() {
    _loadSgEnabled();
  }

  Future<void> _loadSgEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    _sgEnabled = prefs.getBool('sg_enabled') ?? false;
    notifyListeners();
  }

  Future<void> setSgEnabled(bool value) async {
    _sgEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sg_enabled', value);
  }

  void setSgFilterWindow(int window) {
    _sgFilterWindow = window;
    notifyListeners();
    // TODO: implement SG filtering using _sgFilterWindow
  }

  void setSelectedGainCode(int code) {
    _selectedGainCode = code;
    notifyListeners();
  }

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
    final measurementNumber = _project!.measurements.length + 1;
    final displayName = '${_selectedMode!.fullName} $measurementNumber';
    _session = MeasurementSession(
      mode:        _selectedMode!.abbreviation,
      label:       _nextLabel,
      displayName: displayName,
      parameters:  Map.from(_parameters),
      startedAt:   DateTime.now(),
    );
    _nextLabel        = '';
    _state            = MeasurementState.running;
    _exportError      = null;
    _progress         = null;
    _lastBleRow       = null;
    _progressReceived = false;
    _runCompleted     = false;
    notifyListeners();

    if (BleService().isConnected) {
      _startBleMeasurement();
    } else {
      _startDemoSimulation();
    }
  }

  // ── BLE path ──────────────────────────────────────────────────────────────

  Future<void> _startBleMeasurement() async {
    // Send LMP91000 config with selected RTIA (gain code) and locked values.
    final lmpCmd = EbstatProtocol.buildLmpCmd(
      gain:     _selectedGainCode,
      rload:    kLmpRload,
      intz:     kLmpIntz,
      biasSign: kLmpBiasSign,
      biasPct:  kLmpBiasPct,
      refSrc:   kLmpRefSrc,
    );
    // Safety guard: refuse to send if the command would enable the wrong
    // reference source or bias polarity — both cause data corruption.
    if (kLmpBiasSign != 1 || kLmpRefSrc != 1) {
      debugPrint('⚠ LMP pre-command blocked: biasSign=$kLmpBiasSign '
          'refSrc=$kLmpRefSrc — must be biasSign=1 (POS) and refSrc=1 (EXT)');
      // Do not send; fall through to measurement command without LMP setup.
    } else {
      try {
        await BleService().sendCommand(lmpCmd);
      } catch (_) {
        // Best-effort: proceed even if LMP command fails
      }
    }
    if (_state != MeasurementState.running) return;

    // Configure SG filter window if SG is enabled and a specific window is set.
    // _sgFilterWindow: -1 = None (no SGSET), 0 = default, >0 = half_window size.
    if (_sgEnabled && _sgFilterWindow > 0) {
      try {
        await BleService().sendCommand('${FwCmd.sgset},$_sgFilterWindow,2');
      } catch (_) {
        // Best-effort
      }
      if (_state != MeasurementState.running) return;
    }

    // Send SG toggle — info command, resolves after 400 ms quiet period
    final sgCmd = _sgEnabled ? FwCmd.sgon : FwCmd.sgoff;
    try {
      await BleService().sendCommand(sgCmd);
    } catch (_) {
      // Best-effort: proceed even if SG command fails
    }
    if (_state != MeasurementState.running) return; // stopped during pre-cmd

    final mode     = _selectedMode!.abbreviation;
    final paramMap = <String, dynamic>{
      for (final e in _parameters.entries) e.key: e.value.round(),
    };
    final cmd = EbstatProtocol.buildMeasurementCmd(mode, paramMap);

    bool headerSeen = false;
    final xy   = EbstatProtocol.xyColumns(mode);
    final xIdx = xy[0];
    final yIdx = xy[1];
    final isCv = mode == 'CV';

    _dataSub = BleService().rawLines.listen((line) {
      // Reset silence timer on every incoming line once progress has started
      if (_progressReceived) _resetSilenceTimer();

      if (_state == MeasurementState.running) {
        final trimmed = line.trim();

        // Intercept special # lines before the generic isMetadata early-return
        if (trimmed == '# DONE') {
          _triggerRunComplete();
          return;
        }
        if (trimmed == '# ABORT') {
          _triggerRunAbort();
          return;
        }
        if (trimmed.startsWith('# ERR') || trimmed.startsWith('# WARN')) {
          debugPrint('[BLE] $trimmed');
          _onWarning?.call(trimmed.replaceFirst(RegExp(r'^#\s*'), ''));
          return;
        }

        // Detect first # progress= line → start silence timer
        if (EbstatProtocol.isMetadata(line)) {
          if (!_progressReceived) {
            final meta = EbstatProtocol.parseMetadata(line);
            if (meta.containsKey('progress')) {
              _progressReceived = true;
              _startSilenceTimer();
            }
          }
          return;
        }

        if (FwTerminator.is_(line)) return;
        if (!headerSeen) { headerSeen = true; return; }
        _lastBleRow = line;
        final cols = line.split(',');
        if (cols.length > yIdx) {
          final x = double.tryParse(cols[xIdx].trim());
          final y = double.tryParse(cols[yIdx].trim());
          if (x != null && y != null) {
            final MeasurementPoint pt;
            if (isCv && cols.length > 2) {
              // CV: col[1]=cycle (int), col[2]=direction ('start'/'fwd'/'rev')
              final cycle = int.tryParse(cols[1].trim());
              // cycle 0 is a warmup/parking sample at V_start — discard it
              if (cycle == 0) return;
              final dir   = cols[2].trim();
              pt = MeasurementPoint(x, y,
                  cycle: cycle, direction: dir.isNotEmpty ? dir : null);
            } else {
              pt = MeasurementPoint(x, y);
            }
            _session!.points.add(pt);
            // notifyListeners deferred to _updateTimer (50 ms batch)
          }
        }
      } else if (_state == MeasurementState.done) {
        // Collect SG post-DONE lines: "SG,<index>,<current_nA>"
        _parseSgLine(line);
      }
    });

    _progressSub = BleService().progressStream.listen((prog) {
      _progress = prog;
      notifyListeners();
    });

    // Flush buffered points to UI at ≤20 fps — prevents per-point setState at high scan rates
    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (_state == MeasurementState.running) notifyListeners();
    });

    BleService()
        .sendCommand(cmd)
        .then((result) async {
          await _onBleRunComplete(result);
          _navigateToAnalysis?.call();
        })
        .catchError(_onBleRunError);
  }

  void _parseSgLine(String line) {
    if (!line.startsWith('SG,')) return;
    final parts = line.split(',');
    if (parts.length < 3) return;
    final idx     = int.tryParse(parts[1].trim());
    final current = double.tryParse(parts[2].trim());
    if (idx == null || current == null) return;
    final sessions = _project?.measurements;
    if (sessions == null || sessions.isEmpty) return;
    final session = sessions.last;
    while (session.sgPoints.length <= idx) session.sgPoints.add(null);
    session.sgPoints[idx] = current;
    notifyListeners();
  }

  Future<void> _onBleRunComplete(RunResult result) async {
    if (_runCompleted) return; // already handled (e.g. via # DONE line)
    _runCompleted = true;
    _cancelSilenceTimer();
    _updateTimer?.cancel();
    _updateTimer = null;
    _progressSub?.cancel();
    _progressSub = null;
    _progress    = null;

    if (_session != null && _session!.points.isNotEmpty) {
      if (_selectedMode?.abbreviation == 'CA' && _session!.points.length > 1) {
        final t0 = _session!.points.first.x;
        final normalized = _session!.points
            .map((p) => MeasurementPoint(p.x - t0, p.y))
            .toList();
        _session!.points..clear()..addAll(normalized);
      }
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

    // Keep _dataSub alive for 3 s after DONE to collect SG,<idx>,<I> lines.
    _sgTimer?.cancel();
    _sgTimer = Timer(const Duration(seconds: 3), () {
      _dataSub?.cancel();
      _dataSub = null;
    });
  }

  void _onBleRunError(Object error) {
    _cancelSilenceTimer();
    _updateTimer?.cancel();
    _updateTimer = null;
    _dataSub?.cancel();
    _dataSub = null;
    _progressSub?.cancel();
    _progressSub = null;
    _progress    = null;
    _sgTimer?.cancel();
    _sgTimer = null;
    if (_session != null && _session!.points.isNotEmpty) {
      _project?.addMeasurement(_session!);
    }
    _state       = MeasurementState.done;
    _exportError = error is BleDisconnectedException
        ? 'Device disconnected mid-run'
        : 'BLE error: $error';
    notifyListeners();
  }

  // ── Silence timer ─────────────────────────────────────────────────────────

  void _startSilenceTimer() {
    _silenceTimer?.cancel();
    _silenceTimer = Timer(const Duration(milliseconds: 3000), () {
      debugPrint('[BLE] ⚠ 3 s silence after progress — treating as implicit DONE');
      _triggerRunComplete();
    });
  }

  void _resetSilenceTimer() {
    if (_silenceTimer == null) return;
    _silenceTimer!.cancel();
    _silenceTimer = Timer(const Duration(milliseconds: 3000), () {
      debugPrint('[BLE] ⚠ 3 s silence after progress — treating as implicit DONE');
      _triggerRunComplete();
    });
  }

  void _cancelSilenceTimer() {
    _silenceTimer?.cancel();
    _silenceTimer = null;
  }

  // ── Completion triggers ───────────────────────────────────────────────────

  Future<void> _triggerRunComplete() async {
    await _onBleRunComplete(const RunResult(aborted: false));
    _navigateToAnalysis?.call();
  }

  Future<void> _triggerRunAbort() async {
    _cancelSilenceTimer();
    if (_session != null && _session!.points.isNotEmpty) {
      await _onBleRunComplete(const RunResult(aborted: true));
      _navigateToAnalysis?.call();
    } else {
      _dataSub?.cancel();      _dataSub      = null;
      _progressSub?.cancel();  _progressSub  = null;
      _progress     = null;
      _runCompleted = true;
      _state        = MeasurementState.idle;
      notifyListeners();
      _popToParameters?.call();
    }
  }

  // ── Navigation / warning callbacks ────────────────────────────────────────

  void registerMeasurementCallbacks({
    required VoidCallback onNavigateToAnalysis,
    required VoidCallback onPopToParameters,
    required void Function(String) onWarning,
  }) {
    _navigateToAnalysis = onNavigateToAnalysis;
    _popToParameters    = onPopToParameters;
    _onWarning          = onWarning;
  }

  void unregisterMeasurementCallbacks() {
    _navigateToAnalysis = null;
    _popToParameters    = null;
    _onWarning          = null;
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
      VoltammetryMode.cv => _cvPoints(scanIndex),
      VoltammetryMode.ca => _caPoints(scanIndex),
      _                  => _pulsePoints(scanIndex),
    };
  }

  List<MeasurementPoint> _cvPoints(int scanIndex) {
    final scale = [1.0, 1.55, 0.65][scanIndex % 3];
    const eStart = -200.0, eVertex = 500.0;
    const ePc = 150.0, ePa = 220.0;
    const iPc = 7.0, iPa = 5.5, sigma = 50.0, step = 5.0;
    final pts = <MeasurementPoint>[];
    for (double e = eStart; e <= eVertex; e += step) {
      final c = -iPc * scale *
          math.exp(-math.pow(e - ePc, 2) / (2 * sigma * sigma));
      pts.add(MeasurementPoint(e, -0.4 * scale + c,
          cycle: 1, direction: 'fwd'));
    }
    for (double e = eVertex - step; e >= eStart; e -= step) {
      final a = iPa * scale *
          math.exp(-math.pow(e - ePa, 2) / (2 * sigma * sigma));
      pts.add(MeasurementPoint(e, 0.3 * scale + a,
          cycle: 1, direction: 'rev'));
    }
    if (scanIndex == 0) {
      // Two-cycle demo for the first scan
      for (double e = eStart; e <= eVertex; e += step) {
        final c = -iPc * scale * 0.9 *
            math.exp(-math.pow(e - ePc - 10, 2) / (2 * sigma * sigma));
        pts.add(MeasurementPoint(e, -0.35 * scale + c,
            cycle: 2, direction: 'fwd'));
      }
      for (double e = eVertex - step; e >= eStart; e -= step) {
        final a = iPa * scale * 0.9 *
            math.exp(-math.pow(e - ePa - 10, 2) / (2 * sigma * sigma));
        pts.add(MeasurementPoint(e, 0.28 * scale + a,
            cycle: 2, direction: 'rev'));
      }
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
      _cancelSilenceTimer();
      _updateTimer?.cancel();
      _updateTimer = null;
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
    _sgTimer?.cancel();
    _sgTimer = null;
    _updateTimer?.cancel();
    _updateTimer = null;
    _cancelSilenceTimer();
    if (_session != null && _session!.points.isNotEmpty) {
      _project?.addMeasurement(_session!);
    }
    _state = MeasurementState.done;
    notifyListeners();
  }

  /// Replace the current project with an externally-constructed [project]
  /// (e.g. imported from CSV). Cancels any in-progress measurement.
  void importProject(ProjectSession project, VoltammetryMode mode) {
    _demoTimer?.cancel();
    _demoTimer = null;
    _dataSub?.cancel();
    _dataSub = null;
    _progressSub?.cancel();
    _progressSub = null;
    _sgTimer?.cancel();
    _sgTimer = null;
    _updateTimer?.cancel();
    _updateTimer = null;
    _cancelSilenceTimer();
    _project      = project;
    _selectedMode = mode;
    _session      = null;
    _state        = MeasurementState.done;
    _exportError  = null;
    _progress     = null;
    notifyListeners();
  }

  void resetMeasurement() {
    _demoTimer?.cancel();
    _demoTimer = null;
    _dataSub?.cancel();
    _dataSub = null;
    _progressSub?.cancel();
    _progressSub = null;
    _sgTimer?.cancel();
    _sgTimer = null;
    _updateTimer?.cancel();
    _updateTimer = null;
    _cancelSilenceTimer();
    _session     = null;
    _state       = MeasurementState.idle;
    _exportError = null;
    _progress    = null;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Project mutations
  // ═══════════════════════════════════════════════════════════════════════════

  void deleteMeasurement(int index) {
    _project?.deleteMeasurement(index);
    notifyListeners();
  }

  void deleteCycle(int measurementIndex, int cycleNum) {
    final session = _project?.measurements[measurementIndex];
    if (session == null) return;
    session.deleteCycle(cycleNum);
    if (session.points.isEmpty) {
      deleteMeasurement(measurementIndex);
      return;
    }
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
    _sgTimer?.cancel();
    _updateTimer?.cancel();
    _silenceTimer?.cancel();
    super.dispose();
  }
}
