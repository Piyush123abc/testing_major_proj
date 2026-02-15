import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart' as ms;
import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter_bluetooth_classic_serial/flutter_bluetooth_classic.dart';

class ClassicBluetoothTestPage extends StatefulWidget {
  const ClassicBluetoothTestPage({super.key});
  @override
  State<ClassicBluetoothTestPage> createState() =>
      _ClassicBluetoothTestPageState();
}

class _ClassicBluetoothTestPageState extends State<ClassicBluetoothTestPage> {
  final TextEditingController _payloadController = TextEditingController();
  final ms.MobileScannerController _cameraController =
      ms.MobileScannerController();
  final FlutterBluetoothClassic _bluetooth = FlutterBluetoothClassic();

  BluetoothDevice? _connectedDevice;
  bool _isConnected = false;
  bool _isReceiving = false;
  bool _isSending = false;

  String? _ownToken = "SENDER123"; // app-generated token
  List<BluetoothDevice> _pairedDevices = [];
  Map<String, BluetoothDevice> _tokenDeviceMap = {}; // token -> device mapping

  StreamSubscription<BluetoothState>? _stateSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<BluetoothData>? _dataSub;

  List<String> _debugLogs = [];

  @override
  void initState() {
    super.initState();
    _initBluetooth();
  }

  Future<void> _initBluetooth() async {
    try {
      bool supported = await _bluetooth.isBluetoothSupported();
      bool enabled = await _bluetooth.isBluetoothEnabled();
      _log("Bluetooth supported: $supported, enabled: $enabled");

      _stateSub = _bluetooth.onStateChanged.listen((state) {
        _log("🔧 BT state changed: isEnabled=${state.isEnabled}");
      });

      _connSub = _bluetooth.onConnectionChanged.listen((cstate) {
        _log(
          "🔌 Connection state: device=${cstate.deviceAddress}, isConnected=${cstate.isConnected}",
        );
        setState(() {
          _isConnected = cstate.isConnected;
          if (!cstate.isConnected) _connectedDevice = null;
        });
      });

      _dataSub = _bluetooth.onDataReceived.listen((data) {
        String received = data.asString()!;
        _log("📥 Received from ${data.deviceAddress}: $received");
        if (received.trim().toLowerCase() == "ok") {
          _log("✅ OK received — disconnecting");
          _disconnect();
        }
      });

      // Load paired devices
      await _loadPairedDevices();
    } catch (e) {
      _log("❌ Init error: $e");
    }
  }

  Future<void> _loadPairedDevices() async {
    try {
      List<BluetoothDevice> devices = await _bluetooth.getPairedDevices();
      setState(() {
        _pairedDevices = devices;
      });
      _log("🔍 Found ${devices.length} paired devices");

      // For demo: assign each paired device a token for mapping
      // In real app, the QR code should contain this mapping info
      for (var i = 0; i < devices.length; i++) {
        String token = "RECEIVER$i";
        _tokenDeviceMap[token] = devices[i];
        _log("📦 Token $token -> Device ${devices[i].name}");
      }
    } catch (e) {
      _log("❌ Error fetching paired devices: $e");
    }
  }

  Future<void> _connectAndSend(String token, String payload) async {
    if (!_tokenDeviceMap.containsKey(token)) {
      _log("❌ Unknown token: $token");
      return;
    }
    BluetoothDevice device = _tokenDeviceMap[token]!;

    if (payload.isEmpty) {
      _showError("Payload is mandatory");
      return;
    }

    setState(() => _isSending = true);
    try {
      _log("🔗 Connecting to ${device.name} (${device.address}) …");
      bool ok = await _bluetooth.connect(device.address); // ✅ Pass MAC address
      if (!ok) throw Exception("Failed to connect");
      _log("✅ Connected to ${device.name}");
      _connectedDevice = device;

      _log("📤 Sending payload: $payload");
      bool sendOk = await _bluetooth.sendString(payload + "\n");
      if (!sendOk) _log("⚠️ sendString returned false");
    } catch (e) {
      _log("❌ Error in connect/send: $e");
      _disconnect();
    }
    setState(() => _isSending = false);
  }

  Future<void> _disconnect() async {
    try {
      await _bluetooth.disconnect();
      _log("📴 Disconnected");
    } catch (e) {
      _log("⚠️ Error disconnecting: $e");
    }
    setState(() {
      _isConnected = false;
      _connectedDevice = null;
    });
  }

  // Receiver simulation (discovery placeholder)
  Future<void> _startReceive() async {
    if (_isReceiving) return;
    setState(() => _isReceiving = true);
    _log("🟢 Ready to receive connections (simulation)");
  }

  Future<void> _stopReceive() async {
    setState(() => _isReceiving = false);
    _log("🛑 Receiver stopped");
  }

  void _onQrDetected(String token) {
    _log("📷 QR detected: $token");
    if (_payloadController.text.isEmpty) {
      _showError("Enter payload first");
      return;
    }
    _connectAndSend(token, _payloadController.text);
  }

  void _log(String msg) {
    setState(() {
      _debugLogs.insert(0, msg);
      if (_debugLogs.length > 50) _debugLogs.removeLast();
    });
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _connSub?.cancel();
    _dataSub?.cancel();
    _payloadController.dispose();
    _cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Classic Bluetooth Token Transfer")),
      body: Column(
        children: [
          // Camera Scanner
          Expanded(
            flex: 3,
            child: ms.MobileScanner(
              controller: _cameraController,
              onDetect: (capture) {
                if (capture.barcodes.isNotEmpty) {
                  final barcode = capture.barcodes.first;
                  if (barcode.rawValue != null) {
                    _onQrDetected(barcode.rawValue!);
                  }
                }
              },
            ),
          ),
          // Payload input & Receive button
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                TextField(
                  controller: _payloadController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: "Payload",
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _isReceiving ? _stopReceive : _startReceive,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isReceiving ? Colors.red : Colors.green,
                  ),
                  child: Text(_isReceiving ? "Stop Receive" : "Start Receive"),
                ),
                const SizedBox(height: 8),
                Text(
                  "Connected Device: ${_connectedDevice?.name ?? _connectedDevice?.address ?? "None"}",
                ),
                Text("Sending: $_isSending, Receiving: $_isReceiving"),
              ],
            ),
          ),
          const Divider(),
          // QR code display for own token
          if (_ownToken != null)
            Column(
              children: [
                BarcodeWidget(
                  barcode: Barcode.qrCode(),
                  data: _ownToken!,
                  width: 140,
                  height: 140,
                ),
                const SizedBox(height: 4),
                Text("Your Token: $_ownToken"),
              ],
            ),
          // Debug console
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.all(8),
              color: Colors.grey[200],
              child: ListView.builder(
                reverse: true,
                itemCount: _debugLogs.length,
                itemBuilder: (context, index) => Text(
                  _debugLogs[index],
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
