import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../ble/protocol.dart';
import '../services/ble_service.dart';

enum BleStatus { idle, scanning, connecting, connected, error }

class BleProvider extends ChangeNotifier {
  final _ble = BleService();

  BleStatus _status        = BleStatus.idle;
  String?   _errorMessage;
  bool      _filterNus     = true;
  String?   _savedDeviceId;
  String?   _savedDeviceName;

  StreamSubscription<bool>? _connStateSub;

  BleProvider() {
    _connStateSub = _ble.connectionState.listen(_onConnectionState);
    _loadSavedDevice();
  }

  // ── Getters ───────────────────────────────────────────────────────────────
  // Status always reflects the physical connection first; _status only
  // matters when not connected (scanning, connecting, error, idle).
  BleStatus get status => _ble.isConnected ? BleStatus.connected : _status;
  String?   get errorMessage    => _errorMessage;
  bool      get filterNus       => _filterNus;
  bool      get isConnected     => _ble.isConnected;
  BluetoothDevice? get connectedDevice => _ble.connectedDevice;

  String?   get savedDeviceId   => _savedDeviceId;
  String?   get savedDeviceName => _savedDeviceName;

  Stream<List<ScanResult>> get scanResults   => _ble.scanResults;
  Stream<bool>             get isScanning    => _ble.isScanning;
  Stream<String>           get rawLines      => _ble.rawLines;
  Stream<ProgressUpdate>   get progressStream => _ble.progressStream;

  // ── NUS filter toggle ─────────────────────────────────────────────────────
  void setFilterNus(bool value) {
    _filterNus = value;
    notifyListeners();
  }

  // ── Connection state from BleService ─────────────────────────────────────
  void _onConnectionState(bool connected) {
    if (!connected && _status == BleStatus.connected) {
      _status = BleStatus.idle;
      notifyListeners();
    }
  }

  // ── Saved device ──────────────────────────────────────────────────────────
  Future<void> _loadSavedDevice() async {
    final saved = await _ble.loadSavedDevice();
    _savedDeviceId   = saved.id;
    _savedDeviceName = saved.name;
    notifyListeners();
  }

  Future<void> clearSavedDevice() async {
    await _ble.clearSavedDevice();
    _savedDeviceId   = null;
    _savedDeviceName = null;
    notifyListeners();
  }

  // ── Permissions ───────────────────────────────────────────────────────────
  Future<bool> requestPermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    return statuses.values.every((s) => s.isGranted);
  }

  // ── Scan ──────────────────────────────────────────────────────────────────
  Future<void> startScan() async {
    final granted = await requestPermissions();
    if (!granted) {
      _setError('Bluetooth/Location permissions denied.');
      return;
    }
    _status = BleStatus.scanning;
    _errorMessage = null;
    notifyListeners();
    try {
      await _ble.startScan(
        timeout: const Duration(seconds: 15),
        filterNus: _filterNus,
      );
      if (_status == BleStatus.scanning) {
        _status = BleStatus.idle;
        notifyListeners();
      }
    } catch (e) {
      _setError('Scan failed: $e');
    }
  }

  Future<void> stopScan() async {
    await _ble.stopScan();
    if (_status == BleStatus.scanning) {
      _status = BleStatus.idle;
      notifyListeners();
    }
  }

  // ── Connect / disconnect ──────────────────────────────────────────────────
  Future<void> connect(BluetoothDevice device) async {
    _status = BleStatus.connecting;
    _errorMessage = null;
    notifyListeners();
    try {
      await _ble.connect(device);
      _status = BleStatus.connected;
      // Refresh saved device info after successful connect
      await _loadSavedDevice();
      notifyListeners();
    } catch (e) {
      _setError('Connection failed: $e');
    }
  }

  Future<void> disconnect() async {
    await _ble.disconnect();
    _status = BleStatus.idle;
    notifyListeners();
  }

  // ── Command interface ─────────────────────────────────────────────────────
  Future<RunResult> sendCommand(String cmd, {int? id}) =>
      _ble.sendCommand(cmd, id: id);

  Future<void> sendStop() => _ble.sendStop();

  // ── Internal ──────────────────────────────────────────────────────────────
  void _setError(String msg) {
    _status = BleStatus.error;
    _errorMessage = msg;
    notifyListeners();
  }

  @override
  void dispose() {
    _connStateSub?.cancel();
    _ble.dispose();
    super.dispose();
  }
}
