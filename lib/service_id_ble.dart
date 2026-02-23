import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:barcode_widget/barcode_widget.dart' as bw;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

// import 'package:attendance_app/permissions.dart';

class BleTestDebugPage extends StatefulWidget {
  const BleTestDebugPage({super.key});

  @override
  State<BleTestDebugPage> createState() => _BleTestDebugPageState();
}

class _BleTestDebugPageState extends State<BleTestDebugPage> {
  // --- Core Controllers & State ---
  final MobileScannerController _cameraController = MobileScannerController();
  final FlutterBlePeripheral _blePeripheral = FlutterBlePeripheral();
  StreamSubscription? _scanSubscription;

  // Default values pre-filled for instant testing
  final TextEditingController _uuidController = TextEditingController(
    text: "12345678-1234-1234-1234-1234567890ab",
  );
  final TextEditingController _payloadController = TextEditingController(
    text: "TEST123",
  );

  bool _isScanning = false;
  bool _isAdvertising = false;
  bool _isContinuousMode = false;

  // Scan Mode state
  AndroidScanMode _selectedScanMode = AndroidScanMode.lowLatency;

  // Debug Output
  String _statusLog = "Idle. Ready to test.";
  String _lastRssi = "--";
  String _receivedPayload = "--";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // await AppPermissions.requestAllPermissions(context);
    });

    // Rebuild QR code dynamically if user types a new UUID manually
    _uuidController.addListener(() {
      setState(() {});
    });
  }

  // --- Helpers ---
  void _log(String message) {
    if (!mounted) return;
    setState(() {
      _statusLog = "${DateTime.now().second}s: $message\n$_statusLog";
      // Prevent the log from getting so huge it lags the UI during continuous scans
      if (_statusLog.length > 2500) {
        _statusLog = _statusLog.substring(0, 2500);
      }
    });
    print("BLE_DEBUG: $message");
  }

  Uint8List _getPayloadBytes() {
    // Hard truncation to 8 bytes to prevent BLE packet overflow
    String text = _payloadController.text;
    if (text.length > 8) text = text.substring(0, 8);
    return Uint8List.fromList(text.codeUnits);
  }

  // --- Advertising (Phone A) ---
  Future<void> _startAdvertising(String targetUuid) async {
    await _stopAll(); // Ensure clean slate

    try {
      final advertiseData = AdvertiseData(
        serviceUuid: targetUuid,
        manufacturerId: 1234, // Strict ID handshake
        manufacturerData: _getPayloadBytes(),
        includeDeviceName: false, // Save packet space
      );

      await _blePeripheral.start(advertiseData: advertiseData);
      setState(() => _isAdvertising = true);
      _log(
        "📡 ADVERTISING Started -> UUID: $targetUuid | Payload: ${_payloadController.text}",
      );
    } catch (e) {
      _log("❌ Advertise Error: $e");
    }
  }

  // --- Scanning (Phone B) ---
  Future<void> _startScanning({required bool isContinuous}) async {
    await _stopAll(); // Ensure clean slate

    String targetUuid = _uuidController.text.trim();
    if (targetUuid.length != 36) {
      _log("❌ Invalid UUID length. Must be 36 chars with dashes.");
      return;
    }

    try {
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (var result in results) {
          if (result.advertisementData.manufacturerData.containsKey(1234)) {
            final payloadBytes =
                result.advertisementData.manufacturerData[1234]!;
            final payloadStr = String.fromCharCodes(payloadBytes);

            setState(() {
              _lastRssi = "${result.rssi} dBm";
              _receivedPayload = payloadStr;
            });

            _log("✅ MATCH! Payload: $payloadStr | RSSI: ${result.rssi}");

            if (!isContinuous) {
              _log("One-shot scan complete. Stopping scanner.");
              _stopAll();
            }
            break;
          }
        }
      });

      await FlutterBluePlus.startScan(
        withServices: [Guid(targetUuid)],
        androidScanMode: _selectedScanMode, // Dynamic mode selected by user
        continuousUpdates: true,
      );

      setState(() {
        _isScanning = true;
        _isContinuousMode = isContinuous;
      });

      // FIX: Extracted string properly to avoid .name getter error
      String modeName = _selectedScanMode.toString().split('.').last;

      _log(
        "🔍 SCANNING Started (${isContinuous ? "Cont." : "Once"} | Mode: $modeName)",
      );
    } catch (e) {
      _log("❌ Scan Error: $e");
    }
  }

  Future<void> _stopAll() async {
    await _scanSubscription?.cancel();
    await FlutterBluePlus.stopScan();
    await _blePeripheral.stop();
    if (mounted) {
      setState(() {
        _isScanning = false;
        _isAdvertising = false;
        _isContinuousMode = false;
      });
    }
    _log("🛑 All BLE activity stopped.");
  }

  // --- QR Handling ---
  void _onQrScanned(BarcodeCapture capture) {
    if (_isAdvertising || _isScanning) return; // Ignore if busy

    final rawValue = capture.barcodes.first.rawValue;
    if (rawValue != null && rawValue.length == 36) {
      _uuidController.text = rawValue;
      _log("📷 QR Scanned! Auto-starting advertiser...");
      _startAdvertising(rawValue);
    }
  }

  @override
  void dispose() {
    _cameraController.dispose();
    _stopAll();
    _uuidController.dispose();
    _payloadController.dispose();
    super.dispose();
  }

  // --- UI ---
  @override
  Widget build(BuildContext context) {
    // Disable inputs if we are actively scanning or advertising
    bool isBusy = _isScanning || _isAdvertising;

    return Scaffold(
      appBar: AppBar(
        title: const Text("BLE Handshake Tester"),
        backgroundColor: Colors.grey[900],
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // TOP ROW: Camera & QR Code Side-by-Side
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
                      data: _uuidController.text.isEmpty
                          ? "empty"
                          : _uuidController.text,
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
                  controller: _uuidController,
                  enabled: !isBusy,
                  decoration: const InputDecoration(
                    labelText: "Target UUID (36 chars)",
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 0,
                    ),
                  ),
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _payloadController,
                  enabled: !isBusy,
                  maxLength: 8,
                  decoration: const InputDecoration(
                    labelText: "Payload (Max 8 bytes)",
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Scan Mode Dropdown
                DropdownButtonFormField<AndroidScanMode>(
                  value: _selectedScanMode,
                  decoration: const InputDecoration(
                    labelText: "Android Scan Mode",
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 0,
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: AndroidScanMode.lowLatency,
                      child: Text("Low Latency (Sprint / Aggressive)"),
                    ),
                    DropdownMenuItem(
                      value: AndroidScanMode.balanced,
                      child: Text("Balanced (Jog / Reliable)"),
                    ),
                    DropdownMenuItem(
                      value: AndroidScanMode.lowPower,
                      child: Text("Low Power (Walk / Battery Saver)"),
                    ),
                  ],
                  onChanged: isBusy
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _selectedScanMode = value);
                          }
                        },
                ),
              ],
            ),
          ),

          // BUTTONS: Clean responsive layout
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 12.0,
            ),
            child: Column(
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: isBusy
                          ? null
                          : () => _startScanning(isContinuous: false),
                      icon: const Icon(Icons.search, size: 18),
                      label: const Text("Scan (Once)"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[100],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: isBusy
                          ? null
                          : () => _startScanning(isContinuous: true),
                      icon: const Icon(Icons.wifi_tethering, size: 18),
                      label: const Text("Scan (Cont.)"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.cyan[100],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: isBusy
                          ? null
                          : () => _startAdvertising(_uuidController.text),
                      icon: const Icon(Icons.cell_tower, size: 18),
                      label: const Text("Advertise"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[100],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Massive Stop Button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: isBusy ? _stopAll : null,
                    icon: const Icon(Icons.stop_circle, size: 28),
                    label: const Text(
                      "STOP ALL BLE ACTIVITY",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[600],
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey[300],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(thickness: 2, height: 1),

          // BOTTOM: Massive Results & Logs
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.grey[200],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "RSSI: $_lastRssi",
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueAccent,
                        ),
                      ),
                      Text(
                        "Data: $_receivedPayload",
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "Debug Console:",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Text(
                        _statusLog,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
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
