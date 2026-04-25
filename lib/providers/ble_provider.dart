import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/ble_service.dart';

enum BleStatus { idle, scanning, connecting, connected, error }

class BleProvider extends ChangeNotifier {
  final _ble = BleService();

  BleStatus _status = BleStatus.idle;
  String? _errorMessage;
  String _lastReceivedData = '';

  StreamSubscription<String>? _dataSub;

  BleStatus get status => _status;
  String? get errorMessage => _errorMessage;
  String get lastReceivedData => _lastReceivedData;
  bool get isConnected => _ble.isConnected;
  BluetoothDevice? get connectedDevice => _ble.connectedDevice;

  Stream<List<ScanResult>> get scanResults => _ble.scanResults;
  Stream<bool> get isScanning => _ble.isScanning;

  Future<bool> requestPermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    return statuses.values.every((s) => s.isGranted);
  }

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
      await _ble.startScan(timeout: const Duration(seconds: 10));
      _status = BleStatus.idle;
      notifyListeners();
    } catch (e) {
      _setError('Scan failed: $e');
    }
  }

  Future<void> stopScan() async {
    await _ble.stopScan();
    _status = BleStatus.idle;
    notifyListeners();
  }

  Future<void> connect(BluetoothDevice device) async {
    _status = BleStatus.connecting;
    _errorMessage = null;
    notifyListeners();

    try {
      await _ble.connect(device);
      _status = BleStatus.connected;

      _dataSub?.cancel();
      _dataSub = _ble.dataStream.listen((data) {
        _lastReceivedData = data;
        notifyListeners();
      });

      notifyListeners();
    } catch (e) {
      _setError('Connection failed: $e');
    }
  }

  Future<void> disconnect() async {
    await _dataSub?.cancel();
    _dataSub = null;
    await _ble.disconnect();
    _status = BleStatus.idle;
    _lastReceivedData = '';
    notifyListeners();
  }

  void _setError(String msg) {
    _status = BleStatus.error;
    _errorMessage = msg;
    notifyListeners();
  }

  @override
  void dispose() {
    _dataSub?.cancel();
    _ble.dispose();
    super.dispose();
  }
}
