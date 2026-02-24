import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:barcode_widget/barcode_widget.dart' as bw;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

class ClassicBtTestPage extends StatefulWidget {
  const ClassicBtTestPage({super.key});

  @override
  State<ClassicBtTestPage> createState() => _ClassicBtTestPageState();
}

class _ClassicBtTestPageState extends State<ClassicBtTestPage> {
  // --- Core Controllers & State ---
  final MobileScannerController _cameraController = MobileScannerController();
  
  // Bridge to the Kotlin RFCOMM Socket logic we will write next
  static const MethodChannel _btChannel = MethodChannel('com.attendance/classic_bt');

  // Default values pre-filled for instant testing
  final TextEditingController _macController = TextEditingController(
    text: "00:11:22:33:44:55", // Replace with Teacher's actual MAC for testing
  );
  final TextEditingController _uuidController = TextEditingController(
    text: "12345678-1234-1234-1234-1234567890ab",
  );
  final TextEditingController _payloadController = TextEditingController(
    text: "STUDENT_123",
  );

  bool _isServerRunning = false;
  bool _isConnecting = false;
  bool _useForegroundService = true;

  // Debug Output
  String _statusLog = "Idle. Ready to test Classic BT.";
  String _lastRtt = "--";
  String _lastRssi = "--";
  String _receivedPayload = "--";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _requestBatteryOptimization();
    });

    // Rebuild QR code dynamically if user types new data
    _macController.addListener(() => setState(() {}));
    _uuidController.addListener(() => setState(() {}));
  }

  // --- Helpers ---
  void _log(String message) {
    if (!mounted) return;
    setState(() {
      _statusLog = "${DateTime.now().second}s: $message\n$_statusLog";
      if (_statusLog.length > 2500) {
        _statusLog = _statusLog.substring(0, 2500);
      }
    });
    debugPrint("CLASSIC_BT_DEBUG: $message");
  }

  Future<void> _requestBatteryOptimization() async {
    PermissionStatus status = await Permission.ignoreBatteryOptimizations.status;
    if (!status.isGranted) {
      _log("⚠️ Requesting Battery Optimization Exemption...");
      await Permission.ignoreBatteryOptimizations.request();
    } else {
      _log("🛡️ Battery Restrictions already disabled.");
    }
  }

  // --- Server (Teacher) ---
  Future<void> _startRfcommServer() async {
    await _stopAll();
    String targetUuid = _uuidController.text.trim();

    try {
      setState(() => _isServerRunning = true);
      _log("📡 Starting RFCOMM Server -> UUID: $targetUuid");
      
      // Tell Kotlin to open the Server Socket
      await _btChannel.invokeMethod('startServer', {
        'uuid': targetUuid,
        'useForeground': _useForegroundService,
      });
      
      _log("✅ Server Listening! Scan QR on another device.");
    } catch (e) {
      setState(() => _isServerRunning = false);
      _log("❌ Server Error: $e");
    }
  }

  // --- Client (Student) ---
  Future<void> _connectAndPing(String macAddress, String targetUuid) async {
    await _stopAll();
    
    try {
      setState(() => _isConnecting = true);
      _log("🔗 Dialing MAC: $macAddress | UUID: $targetUuid");

      Stopwatch sw = Stopwatch()..start();

      // Tell Kotlin to connect, send payload, and wait for ACK
      final Map<dynamic, dynamic>? result = await _btChannel.invokeMethod('connectAndPing', {
        'mac': macAddress,
        'uuid': targetUuid,
        'payload': _payloadController.text,
      });

      sw.stop();

      if (result != null && result['success'] == true) {
        setState(() {
          _lastRtt = "${sw.elapsedMilliseconds} ms";
          _lastRssi = "${result['rssi']} dBm";
          _receivedPayload = result['ackPayload'] ?? "ACK";
        });
        _log("✅ PING SUCCESS! RTT: ${_lastRtt} | RSSI: ${_lastRssi}");
      } else {
        _log("❌ Connection failed or rejected by Server.");
      }
    } catch (e) {
      _log("❌ Client Error: $e");
    } finally {
      setState(() => _isConnecting = false);
    }
  }

  Future<void> _stopAll() async {
    try {
      await _btChannel.invokeMethod('stopServer');
      await _btChannel.invokeMethod('disconnectClient');
    } catch (e) {
      _log("⚠️ Error stopping processes: $e");
    }
    
    if (mounted) {
      setState(() {
        _isServerRunning = false;
        _isConnecting = false;
      });
    }
    _log("🛑 Sockets closed.");
  }

  // --- QR Handling ---
  void _onQrScanned(BarcodeCapture capture) {
    if (_isServerRunning || _isConnecting) return; 

    final rawValue = capture.barcodes.first.rawValue;
    if (rawValue != null && rawValue.contains("|")) {
      List<String> parts = rawValue.split("|");
      if (parts.length == 2) {
        String scannedMac = parts[0];
        String scannedUuid = parts[1];
        
        _macController.text = scannedMac;
        _uuidController.text = scannedUuid;
        
        _log("📷 QR Scanned! Connecting to Server...");
        _connectAndPing(scannedMac, scannedUuid);
      }
    } else {
      _log("❌ Invalid QR format. Expected MAC|UUID.");
    }
  }

  @override
  void dispose() {
    _cameraController.dispose();
    _stopAll();
    _macController.dispose();
    _uuidController.dispose();
    _payloadController.dispose();
    super.dispose();
  }

  // --- UI ---
  @override
  Widget build(BuildContext context) {
    bool isBusy = _isServerRunning || _isConnecting;
    String qrData = "${_macController.text}|${_uuidController.text}";

    return Scaffold(
      appBar: AppBar(
        title: const Text("Classic BT RFCOMM Tester"),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // TOP ROW: Camera & QR Code
          SizedBox(
            height: 160,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(8),
                    color: Colors.black,
                    child: MobileScanner(
                      controller: _cameraController,
                      onDetect: _onQrScanned,
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(8),
                    alignment: Alignment.center,
                    child: bw.BarcodeWidget(
                      barcode: bw.Barcode.qrCode(),
                      data: qrData.length < 5 ? "empty" : qrData,
                      width: 120,
                      height: 120,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // MIDDLE: Inputs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              children: [
                TextField(
                  controller: _macController,
                  enabled: !isBusy,
                  decoration: const InputDecoration(
                    labelText: "Server MAC Address (e.g., A1:B2...)",
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  ),
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _uuidController,
                  enabled: !isBusy,
                  decoration: const InputDecoration(
                    labelText: "Session UUID",
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  ),
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _payloadController,
                  enabled: !isBusy,
                  decoration: const InputDecoration(
                    labelText: "Payload (Student ID)",
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  ),
                ),
                const SizedBox(height: 8),

                // Toggles
                SwitchListTile(
                  title: const Text("Use Foreground Service (Server)", style: TextStyle(fontSize: 14)),
                  value: _useForegroundService,
                  onChanged: isBusy ? null : (val) => setState(() => _useForegroundService = val),
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),

          // BUTTONS
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Column(
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: isBusy ? null : () => _connectAndPing(_macController.text, _uuidController.text),
                      icon: const Icon(Icons.flash_on, size: 18),
                      label: const Text("Ping Server (Client)"),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[100]),
                    ),
                    ElevatedButton.icon(
                      onPressed: isBusy ? null : _startRfcommServer,
                      icon: const Icon(Icons.cell_tower, size: 18),
                      label: const Text("Host Server"),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green[100]),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 45,
                  child: ElevatedButton.icon(
                    onPressed: isBusy ? _stopAll : null,
                    icon: const Icon(Icons.stop_circle, size: 24),
                    label: const Text("STOP SOCKETS", style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[600],
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(thickness: 2, height: 1),

          // BOTTOM: Results & Logs
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.grey[200],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Text("RTT: $_lastRtt", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.purple)),
                      Text("RSSI: $_lastRssi", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text("ACK Data: $_receivedPayload", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green)),
                  const SizedBox(height: 12),
                  const Text("Debug Console:", style: TextStyle(fontWeight: FontWeight.bold)),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Text(
                        _statusLog,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}