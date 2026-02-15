import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

// 1. STRUCTURED LOGGING CLASS
enum LogType { info, success, warning, error }

class LogEvent {
  final String timestamp;
  final String message;
  final LogType type;

  LogEvent(this.message, this.type)
    : timestamp = DateTime.now()
          .toIso8601String()
          .split('T')[1]
          .substring(0, 8);
}

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});
  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final TextEditingController _uidController = TextEditingController();
  final MobileScannerController _scannerController = MobileScannerController();

  bool _isScanning = false;
  bool _handshakeComplete = false;
  int? _rttMs;
  int? _rssi;

  // Upgraded Log List
  final List<LogEvent> _terminalLogs = [];

  // Store subscriptions to clean them up properly
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

  final String charUuid = "11111111-2222-3333-4444-555555555555";

  // 2. ENHANCED LOGGING FUNCTION WITH MOUNTED CHECK
  void _log(String msg, {LogType type = LogType.info}) {
    if (!mounted) return; // FIX: Prevents crash if page is disposed

    setState(() {
      _terminalLogs.insert(0, LogEvent(msg, type));
    });
    // Also print to standard console for VS Code debugging
    debugPrint("[${type.name.toUpperCase()}] $msg");
  }

  void _startScanning() {
    if (_uidController.text.isEmpty) {
      _log("Validation Failed: Student UID is empty.", type: LogType.error);
      return;
    }
    if (!mounted) return;
    setState(() => _isScanning = true);
    _log("Scanner Activated. Awaiting QR Payload...", type: LogType.info);
    _scannerController.start();
  }

  void _onDetect(BarcodeCapture capture) {
    if (capture.barcodes.isNotEmpty && _isScanning) {
      final String scannedUuid = capture.barcodes.first.rawValue ?? "";
      if (scannedUuid.length > 20) {
        if (!mounted) return;
        setState(() => _isScanning = false);
        _scannerController.stop();
        _log(
          "TARGET LOCK: Extracted UUID [$scannedUuid]",
          type: LogType.success,
        );
        _executeDistanceBounding(scannedUuid);
      } else {
        _log("Invalid QR Code: Payload too short.", type: LogType.warning);
      }
    }
  }

  Future<void> _executeDistanceBounding(String serviceUuidStr) async {
    _log("PHASE 1: Hardware Filtered Scan Initiated...", type: LogType.info);

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) async {
      if (results.isNotEmpty) {
        await FlutterBluePlus.stopScan();
        BluetoothDevice device = results.last.device;
        int initialRssi = results.last.rssi;

        _log(
          "SERVER FOUND: [${device.remoteId}] (Init RSSI: $initialRssi dBm)",
          type: LogType.success,
        );

        // 3. REAL-TIME CONNECTION STATE TRACKING
        _connectionSubscription = device.connectionState.listen((
          BluetoothConnectionState state,
        ) {
          if (state == BluetoothConnectionState.disconnected) {
            _log("STATE: Device Disconnected.", type: LogType.warning);
          } else if (state == BluetoothConnectionState.connected) {
            _log("STATE: Device Connected.", type: LogType.success);
          }
        });

        try {
          _log("PHASE 2: Attempting Connection...", type: LogType.info);
          // 4. TIMEOUT TRAPS FOR CONNECTION
          await device
              .connect(autoConnect: false)
              .timeout(
                const Duration(seconds: 5),
                onTimeout: () =>
                    throw TimeoutException("Connection attempt timed out."),
              );

          _log("PHASE 3: Discovering Services...", type: LogType.info);
          List<BluetoothService> services = await device
              .discoverServices()
              .timeout(
                const Duration(seconds: 5),
                onTimeout: () =>
                    throw TimeoutException("Service discovery timed out."),
              );

          BluetoothCharacteristic? targetChar;
          for (var service in services) {
            for (var characteristic in service.characteristics) {
              if (characteristic.uuid.toString() == charUuid) {
                targetChar = characteristic;
              }
            }
          }

          if (targetChar != null) {
            _log(
              "PROTOCOL: Target Characteristic Found.",
              type: LogType.success,
            );
            _log(
              "PHASE 4: Executing Stopwatch Distance Calculation...",
              type: LogType.info,
            );

            List<int> studentUidBytes = utf8.encode(_uidController.text);
            Stopwatch sw = Stopwatch()..start();

            // Hardware Write with strict try-catch
            try {
              await targetChar
                  .write(studentUidBytes, withoutResponse: false)
                  .timeout(
                    const Duration(seconds: 3),
                    onTimeout: () =>
                        throw TimeoutException("Write ACK timed out."),
                  );
            } catch (e) {
              _log("WRITE FAILED: $e", type: LogType.error);
              await device.disconnect();
              return;
            }

            sw.stop();
            _rttMs = sw.elapsedMilliseconds;
            _rssi = await device.readRssi();

            _log(
              "PROTOCOL SUCCESS: ACK in ${_rttMs}ms | RSSI: ${_rssi}dBm",
              type: LogType.success,
            );
            HapticFeedback.heavyImpact();

            if (!mounted)
              return; // FIX: Prevent crash if user left page during async gap
            setState(() => _handshakeComplete = true);

            _log("PHASE 5: Terminating Session safely...", type: LogType.info);
            await device.disconnect();
          } else {
            _log(
              "PROTOCOL ERROR: Characteristic [$charUuid] not found on Server.",
              type: LogType.error,
            );
            await device.disconnect();
          }
        } on TimeoutException catch (te) {
          _log("TIMEOUT ERROR: ${te.message}", type: LogType.error);
          await device.disconnect();
        } catch (e) {
          _log("UNEXPECTED ERROR: $e", type: LogType.error);
          await device.disconnect();
        }
      }
    });

    try {
      await FlutterBluePlus.startScan(
        withServices: [Guid(serviceUuidStr)],
        timeout: const Duration(seconds: 5),
      );
    } catch (e) {
      _log("SCAN START FAILED: $e", type: LogType.error);
    }
  }

  // 5. HELPER FOR LOG COLORS
  Color _getLogColor(LogType type) {
    switch (type) {
      case LogType.info:
        return Colors.cyanAccent;
      case LogType.success:
        return Colors.greenAccent;
      case LogType.warning:
        return Colors.orangeAccent;
      case LogType.error:
        return Colors.redAccent;
    }
  }

  @override
  void dispose() {
    _uidController.dispose();
    _scannerController.dispose();
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: const Text(
          "STUDENT: SECURE CHECK-IN",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.indigo[900],
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 10,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              flex: 5,
              child: _handshakeComplete
                  ? Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: _rttMs! < 150
                            ? Colors.green.withOpacity(0.1)
                            : Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _rttMs! < 150
                              ? Colors.greenAccent
                              : Colors.redAccent,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _rttMs! < 150 ? Icons.verified_user : Icons.gpp_bad,
                            color: _rttMs! < 150
                                ? Colors.greenAccent
                                : Colors.redAccent,
                            size: 90,
                          ),
                          const SizedBox(height: 15),
                          Text(
                            "${_rttMs}ms",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 56,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if (_rssi != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.indigo.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.indigoAccent),
                              ),
                              child: Text(
                                "SIGNAL: ${_rssi} dBm",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          const SizedBox(height: 15),
                          Text(
                            _rttMs! < 150
                                ? "PROXIMITY VERIFIED"
                                : "RELAY ATTACK DETECTED",
                            style: TextStyle(
                              color: _rttMs! < 150
                                  ? Colors.greenAccent
                                  : Colors.redAccent,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 40),
                          ElevatedButton.icon(
                            onPressed: () => setState(() {
                              _handshakeComplete = false;
                              _rttMs = null;
                              _rssi = null;
                            }),
                            icon: const Icon(Icons.refresh),
                            label: const Text("NEW SESSION"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white12,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    )
                  : _isScanning
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          MobileScanner(
                            controller: _scannerController,
                            onDetect: _onDetect,
                          ),
                          Container(
                            width: 250,
                            height: 250,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Colors.indigoAccent,
                                width: 3,
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.bluetooth_searching,
                          color: Colors.indigoAccent,
                          size: 60,
                        ),
                        const SizedBox(height: 25),
                        TextField(
                          controller: _uidController,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                          ),
                          decoration: InputDecoration(
                            labelText: "ENTER STUDENT UID",
                            labelStyle: const TextStyle(color: Colors.white70),
                            filled: true,
                            fillColor: Colors.white10,
                            enabledBorder: OutlineInputBorder(
                              borderSide: const BorderSide(
                                color: Colors.indigoAccent,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: const BorderSide(
                                color: Colors.cyanAccent,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            prefixIcon: const Icon(
                              Icons.badge,
                              color: Colors.indigoAccent,
                            ),
                          ),
                        ),
                        const SizedBox(height: 30),
                        SizedBox(
                          width: double.infinity,
                          height: 55,
                          child: ElevatedButton.icon(
                            onPressed: _startScanning,
                            icon: const Icon(Icons.qr_code_scanner),
                            label: const Text(
                              "START PROTOCOL",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigoAccent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 20),

            // Upgraded Terminal UI
            Expanded(
              flex: 2,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blueGrey[900]!.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.cyanAccent.withOpacity(0.3)),
                ),
                child: ListView.builder(
                  itemCount: _terminalLogs.length,
                  itemBuilder: (c, i) {
                    final log = _terminalLogs[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3.0),
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                          children: [
                            TextSpan(
                              text: "[${log.timestamp}] ",
                              style: const TextStyle(color: Colors.grey),
                            ),
                            TextSpan(
                              text: log.message,
                              style: TextStyle(
                                color: _getLogColor(log.type),
                                fontWeight: log.type == LogType.error
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
