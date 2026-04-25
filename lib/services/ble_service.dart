import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleService {
  static final BleService _instance = BleService._();
  factory BleService() => _instance;
  BleService._();

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _rxCharacteristic;

  final _dataController = StreamController<String>.broadcast();
  Stream<String> get dataStream => _dataController.stream;

  BluetoothDevice? get connectedDevice => _connectedDevice;
  bool get isConnected => _connectedDevice != null;

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

  Stream<List<ScanResult>> get scanResults => FlutterBluePlus.scanResults;
  Stream<bool> get isScanning => FlutterBluePlus.isScanning;

  Future<void> startScan({Duration timeout = const Duration(seconds: 10)}) async {
    await FlutterBluePlus.startScan(timeout: timeout);
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
  }

  Future<void> connect(BluetoothDevice device) async {
    await device.connect(autoConnect: false);
    _connectedDevice = device;

    _connectionSubscription = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        _connectedDevice = null;
        _rxCharacteristic = null;
      }
    });

    await _discoverAndSubscribe(device);
  }

  Future<void> _discoverAndSubscribe(BluetoothDevice device) async {
    final services = await device.discoverServices();
    for (final service in services) {
      for (final characteristic in service.characteristics) {
        if (characteristic.properties.notify ||
            characteristic.properties.indicate) {
          await characteristic.setNotifyValue(true);
          _rxCharacteristic = characteristic;

          characteristic.lastValueStream.listen((value) {
            if (value.isNotEmpty) {
              final decoded = utf8.decode(value, allowMalformed: true).trim();
              _dataController.add(decoded);
            }
          });
          return; // Subscribe to the first notifiable characteristic found
        }
      }
    }
  }

  Future<void> disconnect() async {
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _rxCharacteristic = null;
    await _connectedDevice?.disconnect();
    _connectedDevice = null;
  }

  void dispose() {
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    _dataController.close();
  }
}
