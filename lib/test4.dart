import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart'; // Scanning uses 'Barcode'
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:barcode_widget/barcode_widget.dart'
    as bw; // Generating uses 'bw.Barcode'

class TokenTransferPage extends StatefulWidget {
  const TokenTransferPage({super.key});

  @override
  State<TokenTransferPage> createState() => _TokenTransferPageState();
}

class _TokenTransferPageState extends State<TokenTransferPage> {
  // --- LIBRARY INSTANCES ---
  final MobileScannerController _cameraController = MobileScannerController();
  final FlutterBlePeripheral _blePeripheral = FlutterBlePeripheral();

  // --- CONTROLLERS ---
  late TextEditingController _uuidController;
  late TextEditingController _payloadController;

  // --- STATE ---
  bool _isAdvertising = false;
  bool _isScanning = false;

  // LOGS & RESULTS
  String _statusLog = "Ready. Enter UUID and Payload.";
  Color _statusColor = Colors.black87; // Dynamic status color
  List<ScanResult> _scanResults = [];

  // CONSTANTS
  final int _manufacturerId = 1234;
  // LIMIT: BLE Legacy packets (31 bytes) - Overhead (23 bytes) = ~8 Bytes safe
  final int _maxPayloadLength = 8;

  @override
  void initState() {
    super.initState();
    // 1. UUID: Default valid UUID for testing (User can change this)
    _uuidController = TextEditingController(
      text: "bf27730d-860a-4e09-889c-2d8b6a9e0fe7",
    );
    // 2. PAYLOAD: Empty by default
    _payloadController = TextEditingController(text: "");

    _requestPermissions();
  }

  @override
  void dispose() {
    _cameraController.dispose();
    _uuidController.dispose();
    _payloadController.dispose();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.camera,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
  }

  // --- HELPER: LOGGING ---
  void _log(String msg, {bool isError = false}) {
    setState(() {
      _statusLog = msg;
      _statusColor = isError ? Colors.red[900]! : Colors.black87;
    });
  }

  // --- HELPER: UUID VALIDATOR ---
  bool _isValidUuid(String uuid) {
    if (uuid.length < 32) return false;
    try {
      Guid(uuid); // Tries to parse
      return true;
    } catch (e) {
      return false;
    }
  }

  // --- QR LOGIC (SCANNER) ---
  void _onQrDetected(BarcodeCapture capture) {
    if (capture.barcodes.isNotEmpty) {
      final code = capture.barcodes.first.rawValue;
      if (code != null && code.isNotEmpty) {
        if (_uuidController.text != code) {
          setState(() {
            _uuidController.text = code;
          });
          _log("✅ QR Scanned! Target Updated.");
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("UUID Detected: $code")));
        }
      }
    }
  }

  // ==========================================
  //  TRANSMITTER (ADVERTISING)
  // ==========================================
  Future<void> _startAdvertising() async {
    // 1. Validation
    if (_uuidController.text.isEmpty) {
      _log("❌ Error: UUID cannot be empty", isError: true);
      return;
    }
    if (!_isValidUuid(_uuidController.text)) {
      _log("❌ Error: Invalid UUID format", isError: true);
      return;
    }
    if (_payloadController.text.isEmpty) {
      _log("❌ Error: Payload cannot be empty", isError: true);
      return;
    }

    // 2. Byte Size Check
    final Uint8List payload = utf8.encode(_payloadController.text);
    if (payload.length > _maxPayloadLength) {
      _log(
        "❌ Payload too large! (${payload.length}/$_maxPayloadLength bytes)",
        isError: true,
      );
      return;
    }

    final String uuid = _uuidController.text.trim();

    // 3. Setup Packet
    final AdvertiseData advertiseData = AdvertiseData(
      serviceUuid: uuid,
      manufacturerId: _manufacturerId,
      manufacturerData: payload,
      includeDeviceName: false, // Critical to save space
    );

    try {
      await _blePeripheral.start(advertiseData: advertiseData);
      setState(() => _isAdvertising = true);
      _log("📡 Transmitting...\nID: ${_payloadController.text}");
    } catch (e) {
      _log("❌ BLE Error: $e", isError: true);
    }
  }

  Future<void> _stopAdvertising() async {
    await _blePeripheral.stop();
    setState(() {
      _isAdvertising = false;
    });
    _log("📴 Transmission Stopped");
  }

  // ==========================================
  //  RECEIVER (SCANNING)
  // ==========================================

  // MODE 1: SCAN ALL (Sniffer)
  // Scans everything, but highlights the match.
  Future<void> _startScanSniffer() async {
    await _resetScan();
    _log("👀 Sniffing ALL signals...");

    try {
      // Empty services list = listen to everything
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        androidScanMode: AndroidScanMode.lowLatency,
        withServices: [],
      );
      _listenToScan(stopOnMatch: false);
    } catch (e) {
      _log("❌ Scan Error: $e", isError: true);
    }
  }

  // MODE 2: TARGET ONLY
  // Hardware filter - only wakes up for specific UUID
  Future<void> _startScanTarget() async {
    if (!_isValidUuid(_uuidController.text)) {
      _log("❌ Error: Invalid UUID for targeting", isError: true);
      return;
    }

    await _resetScan();
    _log("🎯 Searching for Target...");

    try {
      final Guid targetGuid = Guid(_uuidController.text.trim());

      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 20),
        androidScanMode: AndroidScanMode.lowLatency,
        withServices: [targetGuid], // <--- The Filter
      );
      _listenToScan(stopOnMatch: true); // Stop when found
    } catch (e) {
      _log("❌ Scan Error: $e", isError: true);
    }
  }

  void _listenToScan({required bool stopOnMatch}) {
    FlutterBluePlus.scanResults.listen((results) {
      if (!mounted) return;
      setState(() => _scanResults = results);

      final targetUuidStr = _uuidController.text.trim().toLowerCase();

      for (ScanResult r in results) {
        // CHECK 1: UUID Match
        bool isServiceMatch = r.advertisementData.serviceUuids.any(
          (uuid) => uuid.toString().toLowerCase() == targetUuidStr,
        );

        // CHECK 2: Manufacturer Data Match
        bool hasData = r.advertisementData.manufacturerData.containsKey(
          _manufacturerId,
        );

        if (isServiceMatch || (hasData && targetUuidStr.isEmpty)) {
          // Decode Payload
          String payload = "N/A";
          if (hasData) {
            try {
              payload = utf8.decode(
                r.advertisementData.manufacturerData[_manufacturerId]!,
                allowMalformed: true,
              );
            } catch (_) {
              payload = "Binary Data";
            }
          }

          String msg = "✅ MATCH FOUND!\nData: $payload\nSignal: ${r.rssi} dBm";

          if (stopOnMatch) {
            _stopScan();
            _log(msg);
          } else {
            // Sniffer mode: don't stop, just log if it's new
            if (!_statusLog.contains("MATCH")) {
              _log(msg);
            }
          }
        }
      }
    });
  }

  Future<void> _resetScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    setState(() {
      _isScanning = true;
      _scanResults.clear();
    });
  }

  Future<void> _stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    setState(() => _isScanning = false);
    if (!_statusLog.contains("MATCH")) _log("🛑 Scanning Stopped");
  }

  // ==========================================
  //  UI
  // ==========================================
  @override
  Widget build(BuildContext context) {
    final String qrData = _uuidController.text.isNotEmpty
        ? _uuidController.text
        : "No UUID";

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(title: const Text("BLE Safe Tester")),
      body: Column(
        children: [
          // --- 1. QR SECTION ---
          SizedBox(
            height: 180,
            child: Row(
              children: [
                // Generator
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    color: Colors.white,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          "YOUR ID",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 5),
                        bw.BarcodeWidget(
                          barcode: bw.Barcode.qrCode(),
                          data: qrData,
                          width: 100,
                          height: 100,
                        ),
                      ],
                    ),
                  ),
                ),
                // Scanner
                Expanded(
                  child: Stack(
                    children: [
                      MobileScanner(
                        controller: _cameraController,
                        onDetect: _onQrDetected,
                      ),
                      Center(
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.red, width: 2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const Positioned(
                        bottom: 10,
                        left: 0,
                        right: 0,
                        child: Text(
                          "SCAN TARGET QR",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // --- 2. INPUTS ---
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.blueGrey[50],
            child: Column(
              children: [
                TextField(
                  controller: _uuidController,
                  decoration: const InputDecoration(
                    labelText: "Target UUID (Channel)",
                    border: OutlineInputBorder(),
                    isDense: true,
                    prefixIcon: Icon(Icons.fingerprint, size: 18),
                  ),
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _payloadController,
                  maxLength: _maxPayloadLength, // STRICT UI LIMIT
                  decoration: InputDecoration(
                    labelText: "Payload (Max $_maxPayloadLength chars)",
                    border: const OutlineInputBorder(),
                    isDense: true,
                    prefixIcon: const Icon(Icons.message, size: 18),
                    counterText: "", // Hide character counter
                  ),
                ),
              ],
            ),
          ),

          // --- 3. STATUS BAR ---
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            color: _statusColor, // Dynamic Error Color
            child: Text(
              _statusLog,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          // --- 4. BUTTONS ---
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                // Row 1: Transmit
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isAdvertising
                        ? _stopAdvertising
                        : _startAdvertising,
                    icon: Icon(
                      _isAdvertising ? Icons.stop : Icons.wifi_tethering,
                    ),
                    label: Text(
                      _isAdvertising ? "STOP BROADCAST" : "START BROADCAST",
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isAdvertising
                          ? Colors.red
                          : Colors.blueAccent,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Row 2: Scan Options
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isScanning ? _stopScan : _startScanTarget,
                        icon: const Icon(Icons.gps_fixed, size: 16),
                        label: const Text("TARGET ONLY"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isScanning ? _stopScan : _startScanSniffer,
                        icon: const Icon(Icons.radar, size: 16),
                        label: const Text("SCAN ALL"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // --- 5. RESULTS LIST ---
          Expanded(
            child: _scanResults.isEmpty
                ? const Center(
                    child: Text(
                      "Waiting for signals...",
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: _scanResults.length,
                    itemBuilder: (context, index) {
                      final r = _scanResults[index];
                      // Highlight Logic
                      final target = _uuidController.text.trim();
                      bool isMatch =
                          target.isNotEmpty &&
                          r.advertisementData.serviceUuids.any(
                            (u) => u.toString() == target,
                          );

                      return Container(
                        color: isMatch ? Colors.green[100] : Colors.white,
                        child: ListTile(
                          dense: true,
                          leading: Text(
                            "${r.rssi}\ndBm",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                              color: r.rssi > -60 ? Colors.green : Colors.grey,
                            ),
                          ),
                          title: Text(
                            r.device.platformName.isEmpty
                                ? "Unknown Device"
                                : r.device.platformName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r.device.remoteId.toString(),
                                style: const TextStyle(fontSize: 10),
                              ),
                              if (isMatch)
                                Text(
                                  "MATCHED! (See payload in log)",
                                  style: TextStyle(
                                    color: Colors.green[800],
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                            ],
                          ),
                          trailing: isMatch
                              ? const Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                )
                              : null,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
