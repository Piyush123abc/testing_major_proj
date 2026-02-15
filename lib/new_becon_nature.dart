import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: UniversalBlePage(),
    ),
  );
}

class UniversalBlePage extends StatefulWidget {
  const UniversalBlePage({super.key});

  @override
  State<UniversalBlePage> createState() => _UniversalBlePageState();
}

class _UniversalBlePageState extends State<UniversalBlePage> {
  // --- LIBRARY INSTANCES ---
  final FlutterBlePeripheral _blePeripheral = FlutterBlePeripheral();

  // --- CONTROLLERS ---
  final TextEditingController _uuidController = TextEditingController(
    text: "bf27730d-860a-4e09-889c-2d8b6a9e0fe7", // Default Valid UUID
  );
  final TextEditingController _payloadController = TextEditingController(
    text: "Student_ID_12345",
  );

  // --- STATE ---
  bool _isAdvertising = false;
  bool _isScanning = false;

  // We use this list to display results on screen
  List<ScanResult> _scanResults = [];

  // Status message for the top box
  String _statusLog = "Idle. Ready to Transmit or Scan.";

  // CONSTANTS
  final int _manufacturerId = 1234; // Custom ID to identify OUR data packets

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
  }

  // ==========================================
  //  TRANSMITTER (ADVERTISING) LOGIC
  // ==========================================
  Future<void> startAdvertising() async {
    if (_uuidController.text.isEmpty) {
      setState(() => _statusLog = "❌ Error: UUID cannot be empty");
      return;
    }

    // 1. Prepare Data
    final Uint8List payload = utf8.encode(_payloadController.text);

    // 2. Configure Advertisement
    // We advertise the ServiceUUID so scanners can find us
    // We put the Payload in ManufacturerData
    final AdvertiseData advertiseData = AdvertiseData(
      serviceUuid: _uuidController.text.trim(),
      manufacturerId: _manufacturerId,
      manufacturerData: payload,
      includeDeviceName: false,
    );

    setState(() => _statusLog = "🚀 Starting Broadcast...");

    try {
      await _blePeripheral.start(advertiseData: advertiseData);
      setState(() {
        _isAdvertising = true;
        _statusLog =
            "📡 BROADCASTING LIVE\nUUID: ${_uuidController.text}\nData: ${_payloadController.text}";
      });
    } catch (e) {
      setState(() => _statusLog = "❌ Advertise Error: $e");
    }
  }

  Future<void> stopAdvertising() async {
    await _blePeripheral.stop();
    setState(() {
      _isAdvertising = false;
      _statusLog = "📴 Transmission Stopped";
    });
  }

  // ==========================================
  //  RECEIVER (SCANNING) LOGIC
  // ==========================================

  /// MODE 1: TARGETED SCAN
  /// Only wakes up for the specific UUID. Ignores everything else.
  Future<void> startTargetedScan() async {
    await _resetScanState();
    setState(() => _statusLog = "🎯 Targeted Mode: Waiting for match...");

    try {
      final Guid targetGuid = Guid(_uuidController.text.trim());

      // Start Scan with Filter
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        androidScanMode: AndroidScanMode.lowLatency,
        withServices: [targetGuid], // <--- HARDWARE FILTER
      );

      _listenToScanResults(targetGuid, stopOnMatch: false);
    } catch (e) {
      setState(() => _statusLog = "❌ Scan Error: $e");
    }
  }

  /// MODE 2: SNIFFER SCAN
  /// Scans everything, prints everything, but STOPS if it finds the UUID.
  Future<void> startSnifferScan() async {
    await _resetScanState();
    setState(() => _statusLog = "👀 Sniffer Mode: Listening to ALL signals...");

    try {
      final Guid targetGuid = Guid(_uuidController.text.trim());

      // Start Scan WITHOUT Filter
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        androidScanMode: AndroidScanMode.lowLatency,
        withServices: [], // <--- EMPTY LIST = SHOW EVERYTHING
      );

      _listenToScanResults(targetGuid, stopOnMatch: true);
    } catch (e) {
      setState(() => _statusLog = "❌ Scan Error: $e");
    }
  }

  void _listenToScanResults(Guid targetGuid, {required bool stopOnMatch}) {
    FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        _scanResults = results; // Update UI List
      });

      // Check for our target in the results
      for (ScanResult r in results) {
        // 1. Check if this device has our Service UUID
        bool serviceMatch = r.advertisementData.serviceUuids.contains(
          targetGuid,
        );

        // 2. Check if it has our Manufacturer ID (secondary check)
        bool dataMatch = r.advertisementData.manufacturerData.containsKey(
          _manufacturerId,
        );

        if (serviceMatch || dataMatch) {
          // WE FOUND IT!
          String payloadString = "Unknown Data";

          // Try to decode payload
          if (dataMatch) {
            final data = r.advertisementData.manufacturerData[_manufacturerId]!;
            payloadString = utf8.decode(data, allowMalformed: true);
          }

          String matchMsg =
              "✅ FOUND MATCH!\nID: $payloadString\nRSSI: ${r.rssi} dBm";

          setState(() => _statusLog = matchMsg);

          // If in Sniffer Mode, we stop immediately upon finding it
          if (stopOnMatch) {
            FlutterBluePlus.stopScan();
            setState(() {
              _isScanning = false;
              _statusLog += "\n(Scan Stopped Automatically)";
            });
          }
        }
      }
    });
  }

  Future<void> _resetScanState() async {
    await FlutterBluePlus.stopScan();
    setState(() {
      _isScanning = true;
      _scanResults.clear();
    });
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    setState(() {
      _isScanning = false;
      _statusLog = "🛑 Scanning Stopped Manually";
    });
  }

  // ==========================================
  //  UI BUILDER
  // ==========================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Universal BLE Tool"),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // --- CONFIGURATION SECTION ---
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.blueGrey[50],
            child: Column(
              children: [
                // UUID Input
                TextField(
                  controller: _uuidController,
                  decoration: const InputDecoration(
                    labelText: "Service UUID (The Channel)",
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                ),
                const SizedBox(height: 8),
                // Payload Input
                TextField(
                  controller: _payloadController,
                  decoration: const InputDecoration(
                    labelText: "Payload (Student ID/Token)",
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),

          // --- STATUS LOG ---
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            color: Colors.black87,
            child: Text(
              _statusLog,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.greenAccent,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          // --- BUTTONS ---
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                // 1. TRANSMIT ROW
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isAdvertising
                              ? Colors.red
                              : Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                        icon: Icon(
                          _isAdvertising ? Icons.stop : Icons.wifi_tethering,
                        ),
                        label: Text(
                          _isAdvertising ? "STOP Sending" : "START Sending",
                        ),
                        onPressed: _isAdvertising
                            ? stopAdvertising
                            : startAdvertising,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                // 2. RECEIVE ROW
                Row(
                  children: [
                    // Mode A: Targeted
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.filter_center_focus),
                        label: const Text("Target Only"),
                        onPressed: _isScanning ? stopScan : startTargetedScan,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Mode B: Sniffer
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.radar),
                        label: const Text("Sniffer & Stop"),
                        onPressed: _isScanning ? stopScan : startSnifferScan,
                      ),
                    ),
                  ],
                ),
                if (_isScanning)
                  TextButton(
                    onPressed: stopScan,
                    child: const Text(
                      "STOP SCANNING",
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
              ],
            ),
          ),

          const Divider(thickness: 2),

          // --- RESULTS LIST ---
          Expanded(
            child: _scanResults.isEmpty
                ? const Center(
                    child: Text(
                      "No devices found yet.",
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: _scanResults.length,
                    itemBuilder: (context, index) {
                      final result = _scanResults[index];

                      // Check if this result matches our custom UUID
                      final targetGuid = Guid(_uuidController.text.trim());
                      final isMatch = result.advertisementData.serviceUuids
                          .contains(targetGuid);

                      return Card(
                        color: isMatch ? Colors.green[100] : Colors.white,
                        elevation: isMatch ? 4 : 1,
                        margin: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        child: ListTile(
                          leading: Text(
                            "${result.rssi}\ndBm",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: result.rssi > -60
                                  ? Colors.green
                                  : (result.rssi > -80
                                        ? Colors.orange
                                        : Colors.grey),
                            ),
                          ),
                          title: Text(
                            result.device.platformName.isNotEmpty
                                ? result.device.platformName
                                : "Unknown Device",
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                result.device.remoteId.toString(),
                                style: const TextStyle(fontSize: 10),
                              ),
                              if (isMatch &&
                                  result.advertisementData.manufacturerData
                                      .containsKey(_manufacturerId))
                                Text(
                                  "PAYLOAD: ${utf8.decode(result.advertisementData.manufacturerData[_manufacturerId]!)}",
                                  style: const TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.w900,
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
