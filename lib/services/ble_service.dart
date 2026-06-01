import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ble/protocol.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BleService — singleton that manages the BLE NUS connection to the EBstat
// firmware.  All communication with the device goes through this class.
//
// Architecture:
//   • rawLines   — broadcast stream of every '\n'-terminated line from device
//   • sendCommand() — queues a command; returns Future<RunResult>
//     - Measurement commands (CA/CV/NPV/DPV/SWV): resolve on DONE/ABORTED
//     - Info commands (LMP, HELP, STATUS, CAPS, …): resolve after 400 ms of
//       silence following the last received line, or after a 3 s hard timeout
//       if the device never responds at all.
//   • sendStop()    — sends STOP immediately, bypassing the queue
//   • progressStream — emits ProgressUpdate from "# progress=N/M" lines
//   • connectionState — true = connected, false = disconnected
// ─────────────────────────────────────────────────────────────────────────────

class BleService {
  static final BleService _inst = BleService._();
  factory BleService() => _inst;
  BleService._();

  static const _kPrefDevId   = 'ble_last_device_id';
  static const _kPrefDevName = 'ble_last_device_name';

  // ── NUS characteristics ───────────────────────────────────────────────────
  BluetoothDevice?         _device;
  BluetoothCharacteristic? _rxChar; // app writes commands TO device
  BluetoothCharacteristic? _txChar; // device sends data TO app (notify)

  // ── Public streams ────────────────────────────────────────────────────────
  final _rawLineSC   = StreamController<String>.broadcast();
  final _progressSC  = StreamController<ProgressUpdate>.broadcast();
  final _connStateSC = StreamController<bool>.broadcast();

  Stream<String>         get rawLines        => _rawLineSC.stream;
  Stream<ProgressUpdate> get progressStream  => _progressSC.stream;
  Stream<bool>           get connectionState => _connStateSC.stream;

  // ── Scan pass-throughs ────────────────────────────────────────────────────
  Stream<List<ScanResult>> get scanResults => FlutterBluePlus.scanResults;
  Stream<bool>             get isScanning  => FlutterBluePlus.isScanning;

  // ── Rx byte buffer ────────────────────────────────────────────────────────
  // BLE MTU fragments can split across '\n'; we reassemble here.
  final _rxBuf = <int>[];

  // ── Command queue ─────────────────────────────────────────────────────────
  final _queue   = Queue<_PendingCmd>();
  bool  _inFlight = false;

  // ── Subscriptions ─────────────────────────────────────────────────────────
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<List<int>>?               _notifySub;

  // ── Connection state ──────────────────────────────────────────────────────
  bool             get isConnected     => _device != null;
  BluetoothDevice? get connectedDevice => _device;
  int _mtu = 23; // updated after MTU negotiation

  // ═══════════════════════════════════════════════════════════════════════════
  // Scan
  // ═══════════════════════════════════════════════════════════════════════════

  /// Start scanning.  When [filterNus] is true, only devices that advertise
  /// the NUS service UUID will appear (recommended for production use).
  Future<void> startScan({
    Duration timeout     = const Duration(seconds: 15),
    bool    filterNus    = true,
  }) async {
    final services = filterNus ? [Guid(NusUuids.service)] : <Guid>[];
    await FlutterBluePlus.startScan(
      withServices: services,
      timeout: timeout,
      androidUsesFineLocation: false,
    );
  }

  Future<void> stopScan() => FlutterBluePlus.stopScan();

  // ═══════════════════════════════════════════════════════════════════════════
  // Connect / disconnect
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> connect(BluetoothDevice device) async {
    if (_device != null) await disconnect();

    await device.connect(
      autoConnect: false,
      timeout: const Duration(seconds: 20),
    );
    _device = device;

    // Watch for unexpected disconnection
    _connSub = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        _onUnexpectedDisconnect();
      }
    });

    // Request MTU=247 — nRF52840 supports up to 247.
    try {
      _mtu = await device.requestMtu(247);
    } catch (_) {
      _mtu = 23;
    }

    await _discoverNus(device);
    _connStateSC.add(true);

    // Persist for next launch
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefDevId,   device.remoteId.str);
    await prefs.setString(_kPrefDevName,
        device.platformName.isNotEmpty ? device.platformName : device.remoteId.str);
  }

  /// Walk GATT table looking for the NUS service, then subscribe to TX and
  /// cache the RX characteristic for writing.
  Future<void> _discoverNus(BluetoothDevice device) async {
    final services = await device.discoverServices();
    for (final svc in services) {
      if (svc.uuid.toString().toUpperCase() != NusUuids.service) continue;

      for (final char in svc.characteristics) {
        final uuid = char.uuid.toString().toUpperCase();
        if (uuid == NusUuids.tx && char.properties.notify) {
          // Subscribe to notifications from device
          await char.setNotifyValue(true);
          _txChar    = char;
          _notifySub = char.lastValueStream.listen(_onBleBytes);
        } else if (uuid == NusUuids.rx &&
            (char.properties.write || char.properties.writeWithoutResponse)) {
          _rxChar = char;
        }
      }
      break; // found NUS service; stop walking
    }
  }

  void _onUnexpectedDisconnect() {
    _connStateSC.add(false);
    _device   = null;
    _rxChar   = null;
    _txChar   = null;
    _rxBuf.clear();
    _notifySub?.cancel();
    _notifySub = null;
    _connSub?.cancel();
    _connSub = null;
    // Fail any in-flight command so callers don't hang
    if (_inFlight && _queue.isNotEmpty) {
      final cmd = _queue.removeFirst();
      cmd.idleTimer?.cancel();
      _inFlight = false;
      if (!cmd.completer.isCompleted) {
        cmd.completer.completeError(
          BleDisconnectedException('BLE disconnected mid-command'),
        );
      }
    }
  }

  Future<void> disconnect() async {
    await _connSub?.cancel();
    _connSub = null;
    await _notifySub?.cancel();
    _notifySub = null;
    try { await _device?.disconnect(); } catch (_) {}
    _device   = null;
    _rxChar   = null;
    _txChar   = null;
    _rxBuf.clear();
    // Cancel any pending idle timers before clearing the queue
    for (final cmd in _queue) {
      cmd.idleTimer?.cancel();
    }
    _inFlight = false;
    _connStateSC.add(false);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Incoming data — byte buffer → line stream
  // ═══════════════════════════════════════════════════════════════════════════

  void _onBleBytes(List<int> bytes) {
    if (bytes.isEmpty) return;
    _rxBuf.addAll(bytes);

    // Emit every '\n'-terminated line we have buffered
    while (true) {
      final nl = _rxBuf.indexOf(0x0A); // 0x0A = '\n'
      if (nl < 0) break;
      var lineBytes = _rxBuf.sublist(0, nl);
      _rxBuf.removeRange(0, nl + 1);
      // Strip trailing '\r' in case firmware sends \r\n
      if (lineBytes.isNotEmpty && lineBytes.last == 0x0D) {
        lineBytes = lineBytes.sublist(0, lineBytes.length - 1);
      }
      final line = utf8.decode(lineBytes, allowMalformed: true);
      if (line.isNotEmpty) {
        _rawLineSC.add(line);
        _routeToQueue(line);
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Command queue routing
  // ═══════════════════════════════════════════════════════════════════════════

  void _routeToQueue(String line) {
    if (_queue.isEmpty || !_inFlight) return;
    final cmd = _queue.first;

    // ── Info commands: reset idle timer on every received line ─────────────
    // After 400 ms of silence, the command is considered complete.
    if (cmd.isInfoCmd) {
      cmd.idleTimer?.cancel();
      cmd.idleTimer = Timer(
        const Duration(milliseconds: 400),
        () => _resolveInfoCmd(cmd),
      );
    }

    // ── Terminator ────────────────────────────────────────────────────────
    // Measurement commands end here; also handle unexpected DONE for info cmds.
    if (FwTerminator.is_(line)) {
      cmd.idleTimer?.cancel();
      _queue.removeFirst();
      _inFlight = false;
      if (!cmd.completer.isCompleted) {
        cmd.completer.complete(RunResult(
          aborted:  line == FwTerminator.aborted,
          metadata: Map.from(cmd.meta),
          comments: List.from(cmd.rawComments),
          header:   List.from(cmd.header),
          rawRows:  List.from(cmd.rows),
        ));
      }
      _drainQueue();
      return;
    }

    // ── Metadata / comment lines ──────────────────────────────────────────
    if (EbstatProtocol.isMetadata(line)) {
      cmd.rawComments.add(line.substring(1).trim()); // stripped of leading "# "
      final parsed = EbstatProtocol.parseMetadata(line);
      cmd.meta.addAll(parsed);
      final prog = EbstatProtocol.extractProgress(parsed);
      if (prog != null) _progressSC.add(prog);
      return;
    }

    // ── CSV header (first non-# non-terminator line) ──────────────────────
    if (!cmd.headerSeen) {
      cmd.header     = EbstatProtocol.parseCsvLine(line);
      cmd.headerSeen = true;
      return;
    }

    // ── CSV data row ──────────────────────────────────────────────────────
    cmd.rows.add(line);
  }

  /// Called by the idle timer when an info command's response has gone quiet.
  void _resolveInfoCmd(_PendingCmd cmd) {
    if (_queue.isEmpty || _queue.first != cmd) return;
    if (cmd.completer.isCompleted) return;
    cmd.idleTimer = null;
    _queue.removeFirst();
    _inFlight = false;
    cmd.completer.complete(RunResult(
      aborted:  false,
      metadata: Map.from(cmd.meta),
      comments: List.from(cmd.rawComments),
      header:   List.from(cmd.header),
      rawRows:  List.from(cmd.rows),
    ));
    _drainQueue();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Send
  // ═══════════════════════════════════════════════════════════════════════════

  /// Queue [cmd] (with optional ID prefix) and return a [Future<RunResult>].
  ///
  /// • Measurement commands (CA/CV/NPV/DPV/SWV): resolve on DONE or ABORTED.
  /// • Info commands (everything else): resolve after 400 ms of silence, or
  ///   after a 3 s hard timeout if the device never responds.
  Future<RunResult> sendCommand(String cmd, {int? id}) {
    if (_rxChar == null) {
      return Future.error(
          StateError('BLE not connected — cannot send command'));
    }
    final text    = id != null ? 'ID:$id,$cmd\n' : '$cmd\n';
    final pending = _PendingCmd(text);
    _queue.addLast(pending);
    _drainQueue();
    return pending.completer.future;
  }

  /// Send STOP immediately, bypassing the normal queue.
  /// Safe to call while a measurement is running.
  /// Firmware: STOP sets abort_flag; the running loop will exit and emit ABORTED.
  Future<void> sendStop() async {
    if (_rxChar == null) return;
    await _writeBytes(utf8.encode('STOP\n'));
  }

  void _drainQueue() {
    if (_inFlight || _queue.isEmpty || _rxChar == null) return;
    _inFlight = true;
    final cmd = _queue.first;
    _writeBytes(utf8.encode(cmd.text));
    // For info commands, start a 3 s hard timeout in case the device never
    // responds at all.  This is cancelled and replaced with a 400 ms idle
    // timer each time a line actually arrives (_routeToQueue).
    if (cmd.isInfoCmd) {
      cmd.idleTimer = Timer(
        const Duration(seconds: 3),
        () => _resolveInfoCmd(cmd),
      );
    }
  }

  Future<void> _writeBytes(List<int> bytes) async {
    if (_rxChar == null) return;
    final withoutResponse = _rxChar!.properties.writeWithoutResponse;
    // Chunk at (MTU - 3) to respect ATT protocol overhead
    final mps = _mtu > 3 ? _mtu - 3 : 20;
    for (var off = 0; off < bytes.length; off += mps) {
      final end = (off + mps < bytes.length) ? off + mps : bytes.length;
      await _rxChar!.write(
        bytes.sublist(off, end),
        withoutResponse: withoutResponse,
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Saved device (SharedPreferences)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<({String? id, String? name})> loadSavedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      id:   prefs.getString(_kPrefDevId),
      name: prefs.getString(_kPrefDevName),
    );
  }

  Future<void> clearSavedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPrefDevId);
    await prefs.remove(_kPrefDevName);
  }

  void dispose() {
    _connSub?.cancel();
    _notifySub?.cancel();
    _rawLineSC.close();
    _progressSC.close();
    _connStateSC.close();
  }
}

// ── Internal: pending command in the send queue ───────────────────────────────
class _PendingCmd {
  final String               text;
  final bool                 isInfoCmd;
  final Completer<RunResult> completer   = Completer();
  final Map<String, String>  meta        = {};
  final List<String>         rawComments = [];
  List<String>               header      = [];
  final List<String>         rows        = [];
  bool                       headerSeen  = false;
  Timer?                     idleTimer;

  _PendingCmd(this.text) : isInfoCmd = _detectInfoCmd(text);

  /// Returns true for info/config commands that never emit DONE/ABORTED.
  /// Measurement commands (CA/CV/NPV/DPV/SWV) return false.
  static bool _detectInfoCmd(String cmdText) {
    var text = cmdText.trimRight(); // strip trailing \n
    // Strip optional ID: prefix: "ID:42,CV,..." → "CV,..."
    if (text.startsWith('ID:')) {
      final comma = text.indexOf(',');
      if (comma >= 0) text = text.substring(comma + 1);
    }
    final technique = text.split(',').first.toUpperCase();
    const measurementCmds = {'CA', 'CV', 'NPV', 'DPV', 'SWV'};
    return !measurementCmds.contains(technique);
  }
}

// ── Typed exception for disconnection mid-run ─────────────────────────────────
class BleDisconnectedException implements Exception {
  final String message;
  const BleDisconnectedException(this.message);
  @override
  String toString() => 'BleDisconnectedException: $message';
}
