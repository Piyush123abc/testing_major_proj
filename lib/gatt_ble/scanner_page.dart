import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:barcode_widget/barcode_widget.dart' as bw;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

// ------------------- RECEIVER PAGE -------------------

class ReceiverPage extends StatefulWidget {
  const ReceiverPage({super.key});

  @override
  State<ReceiverPage> createState() => _ReceiverPageState();
}

class _ReceiverPageState extends State<ReceiverPage> {
  final TextEditingController _uidController = TextEditingController();

  static const MethodChannel _methodChannel = MethodChannel(
    'com.attendance/command',
  );
  static const EventChannel _eventChannel = EventChannel(
    'com.attendance/events',
  );
  StreamSubscription? _eventSubscription;

  bool _isAdvertising = false;
  final bool _verboseMode = true;
  final List<String> _terminalLogs = [];

  bool _useForegroundService = true;
  String _selectedAdvMode = 'LOW_LATENCY';

  final String serviceUuid = "87654321-4321-4321-4321-cba987654321";

  @override
  void initState() {
    super.initState();
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen((
      dynamic event,
    ) {
      String payload = event.toString();

      if (payload.startsWith("FATAL:HARDWARE:")) {
        _addLog(payload, isError: true);
        setState(() => _isAdvertising = false);
      } else if (payload.startsWith("LOG:")) {
        _addLog(payload, isError: false);
      } else if (payload.startsWith("ACK:")) {
        String studentUid = payload.substring(4);
        _addLog(
          "HARDWARE ACK: Received Student UID [$studentUid]",
          isError: false,
        );
        HapticFeedback.heavyImpact();
      } else {
        _addLog("MSG: $payload", isError: false);
      }
    });
  }

  void _addLog(String msg, {bool isError = false}) {
    if (!_verboseMode) return;
    if (!mounted) return;
    setState(() {
      String prefix = isError ? "🔴 " : "🟢 ";
      _terminalLogs.insert(
        0,
        "$prefix[${DateTime.now().toIso8601String().split('T')[1].substring(0, 8)}] $msg",
      );
    });
  }

  Future<void> _startNativeServer() async {
    if (_uidController.text.isEmpty) {
      _addLog("ERROR: Teacher UID cannot be empty.", isError: true);
      return;
    }

    try {
      await _methodChannel.invokeMethod('startServer', {
        'useForegroundService': _useForegroundService,
        'advMode': _selectedAdvMode,
      });
      setState(() => _isAdvertising = true);
      _addLog("PIPE: Native GATT Server Hosted | Mode: $_selectedAdvMode");
      if (_useForegroundService)
        _addLog("SHIELD: Foreground Keep-Alive Active.");
      _addLog("BROADCASTING: $serviceUuid");
    } catch (e) {
      _addLog("ERROR: Native bridge failed - $e", isError: true);
    }
  }

  Future<void> _stopNativeServer() async {
    try {
      await _methodChannel.invokeMethod('stopServer');
      setState(() => _isAdvertising = false);
      _addLog("PIPE: Server Offline. Port closed.");
    } catch (e) {
      _addLog("ERROR: Could not stop server - $e", isError: true);
    }
  }

  @override
  void dispose() {
    _stopNativeServer();
    _eventSubscription?.cancel();
    _uidController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String qrData = serviceUuid;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: const Text(
          "TEACHER: ATTENDANCE HUB",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.blueGrey[900],
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 10,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              flex: 5,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.blueGrey[900]!.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.blueAccent.withOpacity(0.5)),
                ),
                child: !_isAdvertising
                    ? SingleChildScrollView(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              "CREATE SESSION",
                              style: TextStyle(
                                color: Colors.blueAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 15),
                            TextField(
                              controller: _uidController,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                              ),
                              decoration: InputDecoration(
                                labelText: "TEACHER NAME / UID",
                                labelStyle: const TextStyle(
                                  color: Colors.white70,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: const BorderSide(
                                    color: Colors.blueAccent,
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
                                  Icons.person,
                                  color: Colors.blueAccent,
                                ),
                              ),
                            ),
                            const SizedBox(height: 15),
                            DropdownButtonFormField<String>(
                              value: _selectedAdvMode,
                              dropdownColor: Colors.blueGrey[900],
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: "BLE Transmit Power",
                                labelStyle: const TextStyle(
                                  color: Colors.blueAccent,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: const BorderSide(
                                    color: Colors.blueAccent,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'LOW_LATENCY',
                                  child: Text("Low Latency (High Power)"),
                                ),
                                DropdownMenuItem(
                                  value: 'BALANCED',
                                  child: Text("Balanced"),
                                ),
                                DropdownMenuItem(
                                  value: 'LOW_POWER',
                                  child: Text("Low Power (Battery Saver)"),
                                ),
                              ],
                              onChanged: (val) =>
                                  setState(() => _selectedAdvMode = val!),
                            ),
                            const SizedBox(height: 10),
                            SwitchListTile(
                              title: const Text(
                                "Foreground Keep-Alive",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: const Text(
                                "Stops Infinix from killing server",
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                ),
                              ),
                              value: _useForegroundService,
                              activeColor: Colors.blueAccent,
                              contentPadding: EdgeInsets.zero,
                              onChanged: (val) =>
                                  setState(() => _useForegroundService = val),
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              height: 55,
                              child: ElevatedButton.icon(
                                onPressed: _startNativeServer,
                                icon: const Icon(Icons.radar),
                                label: const Text(
                                  "HOST GATT SERVER",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blueAccent,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            "BROADCASTING ACTIVE",
                            style: TextStyle(
                              color: Colors.greenAccent,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(height: 25),
                          Container(
                            padding: const EdgeInsets.all(15),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: bw.BarcodeWidget(
                              barcode: bw.Barcode.qrCode(),
                              data: qrData,
                              width: 200,
                              height: 200,
                            ),
                          ),
                          const SizedBox(height: 30),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton.icon(
                              onPressed: _stopNativeServer,
                              icon: const Icon(Icons.stop_circle),
                              label: const Text(
                                "SHUTDOWN SERVER",
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.redAccent,
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
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                const Icon(Icons.terminal, color: Colors.greenAccent, size: 18),
                const SizedBox(width: 8),
                Text(
                  "SYSTEM LOGS",
                  style: TextStyle(
                    color: Colors.greenAccent.withOpacity(0.8),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            const Divider(color: Colors.greenAccent, thickness: 0.5),
            Expanded(
              flex: 2,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.greenAccent.withOpacity(0.3),
                  ),
                ),
                child: ListView.builder(
                  itemCount: _terminalLogs.length,
                  itemBuilder: (c, i) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3.0),
                    child: Text(
                      _terminalLogs[i],
                      style: TextStyle(
                        color: _terminalLogs[i].startsWith("🔴")
                            ? Colors.redAccent
                            : Colors.greenAccent,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------- SCANNER PAGE -------------------

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

class _ScannerPageState extends State<ScannerPage> with WidgetsBindingObserver {
  final TextEditingController _uidController = TextEditingController();

  // FIX 1: Not final — reassigned on every new session to give the
  // MobileScanner widget a completely fresh hardware binding.
  MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  bool _isScanning = false;
  bool _handshakeComplete = false;
  bool _isProcessingScan = false;

  // RTT: 3 raw samples + computed min and average
  int? _minRttMs;
  int? _avgRttMs;
  List<int> _rttSamples = [];
  int? _rssi;

  AndroidScanMode _selectedScanMode = AndroidScanMode.lowLatency;
  bool _useForegroundService = true;

  final List<LogEvent> _terminalLogs = [];
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

  final String charUuid = "11111111-2222-3333-4444-555555555555";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_scannerController.value.isInitialized) {
      if (state == AppLifecycleState.resumed && _isScanning) {
        _scannerController.start();
        _log("SYSTEM: Camera resumed from background.", type: LogType.info);
      } else if (state == AppLifecycleState.inactive ||
          state == AppLifecycleState.paused) {
        _scannerController.stop();
        _log("SYSTEM: Camera paused to save memory.", type: LogType.warning);
      }
    }
  }

  void _log(String msg, {LogType type = LogType.info}) {
    if (!mounted) return;
    setState(() => _terminalLogs.insert(0, LogEvent(msg, type)));
    debugPrint("[${type.name.toUpperCase()}] $msg");
  }

  Future<void> _startScanning() async {
    if (_uidController.text.isEmpty) {
      _log("Validation Failed: Student UID is empty.", type: LogType.error);
      return;
    }
    if (!mounted) return;

    setState(() {
      _isScanning = true;
      _isProcessingScan = false;
    });

    if (_useForegroundService) {
      _log("SHIELD: Foreground Keep-Alive simulated.", type: LogType.warning);
    }
    _log("Scanner Activated. Awaiting QR Payload...", type: LogType.info);

    // FIX 2: Do NOT call _scannerController.start() manually.
    // MobileScanner widget auto-starts when it enters the tree.
    // A double-start causes a race condition → black camera on next session.
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_isProcessingScan) return;

    if (capture.barcodes.isNotEmpty && _isScanning) {
      _isProcessingScan = true;

      final String scannedUuid = capture.barcodes.first.rawValue ?? "";
      if (scannedUuid.length > 20) {
        if (!mounted) return;

        // FIX 3: Stop hardware BEFORE removing MobileScanner from the tree.
        // Tearing down the widget while the camera is running corrupts the
        // controller's internal surface state for the next session.
        await _scannerController.stop();

        if (!mounted) return;
        setState(() => _isScanning = false);

        _log(
          "TARGET LOCK: Extracted UUID [$scannedUuid]",
          type: LogType.success,
        );
        _executeDistanceBounding(scannedUuid);
      } else {
        _log("Invalid QR Code: Payload too short.", type: LogType.warning);
        // FIX 4: Unlock on invalid read or the camera appears frozen.
        _isProcessingScan = false;
      }
    }
  }

  // FIX 5: Dispose stale controller and create a fresh hardware binding
  // before the MobileScanner widget re-enters the tree.
  void _resetSession() {
    _scannerController.dispose();
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
    );
    setState(() {
      _handshakeComplete = false;
      _minRttMs = null;
      _avgRttMs = null;
      _rttSamples = [];
      _rssi = null;
      _isScanning = false;
      _isProcessingScan = false;
    });
  }

  Future<void> _executeDistanceBounding(String serviceUuidStr) async {
    _log("PHASE 1: SOFTWARE Filtered Scan Initiated...", type: LogType.info);

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) async {
      for (ScanResult result in results) {
        if (result.advertisementData.serviceUuids.contains(
          Guid(serviceUuidStr),
        )) {
          await FlutterBluePlus.stopScan();
          BluetoothDevice device = result.device;
          int initialRssi = result.rssi;

          _log(
            "SERVER FOUND: [${device.remoteId}] (Init RSSI: $initialRssi dBm)",
            type: LogType.success,
          );

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
            await device
                .connect(autoConnect: false)
                .timeout(
                  const Duration(seconds: 5),
                  onTimeout: () =>
                      throw TimeoutException("Connection attempt timed out."),
                );

            // JITTER FIX: Forces Android to negotiate a ~7.5ms connection
            // interval instead of the default ~45ms. This cuts variable
            // scheduling jitter from ±40ms down to ±5ms per sample.
            await device.requestConnectionPriority(
              connectionPriorityRequest: ConnectionPriority.high,
            );
            _log(
              "JITTER FIX: High-priority connection interval requested.",
              type: LogType.info,
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
              _log("PHASE 4: Taking 3 RTT samples...", type: LogType.info);

              List<int> studentUidBytes = utf8.encode(_uidController.text);
              List<int> samples = [];

              // 3-sample loop. Using the minimum discards OS scheduling
              // spikes that inflate individual readings — a relay attack
              // cannot compress all 3 samples simultaneously.
              for (int i = 0; i < 3; i++) {
                try {
                  _log(
                    "SAMPLE ${i + 1}/3: Firing write...",
                    type: LogType.info,
                  );
                  final Stopwatch sw = Stopwatch()..start();
                  await targetChar
                      .write(studentUidBytes, withoutResponse: false)
                      .timeout(
                        const Duration(seconds: 3),
                        onTimeout: () =>
                            throw TimeoutException("Write ACK timed out."),
                      );
                  sw.stop();
                  samples.add(sw.elapsedMilliseconds);
                  _log(
                    "SAMPLE ${i + 1}/3: ${sw.elapsedMilliseconds}ms ✓",
                    type: LogType.success,
                  );
                  // Brief pause so the server GATT stack is ready for the
                  // next write — skip the pause after the last sample.
                  if (i < 2) {
                    await Future.delayed(const Duration(milliseconds: 50));
                  }
                } catch (e) {
                  _log("SAMPLE ${i + 1}/3 FAILED: $e", type: LogType.error);
                  await device.disconnect();
                  return;
                }
              }

              final int minRtt = samples.reduce((a, b) => a < b ? a : b);
              final int avgRtt =
                  (samples.reduce((a, b) => a + b) / samples.length).round();

              _rssi = await device.readRssi();

              _log(
                "SAMPLES: [${samples[0]}ms, ${samples[1]}ms, ${samples[2]}ms]",
                type: LogType.success,
              );
              _log(
                "VERDICT: Min=${minRtt}ms | Avg=${avgRtt}ms | RSSI: ${_rssi}dBm",
                type: LogType.success,
              );
              HapticFeedback.heavyImpact();

              if (!mounted) return;
              setState(() {
                _minRttMs = minRtt;
                _avgRttMs = avgRtt;
                _rttSamples = samples;
                _handshakeComplete = true;
              });

              _log(
                "PHASE 5: Terminating Session safely...",
                type: LogType.info,
              );
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
          break;
        }
      }
    });

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 5),
        androidScanMode: _selectedScanMode,
      );
    } catch (e) {
      _log("SCAN START FAILED: $e", type: LogType.error);
    }
  }

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
    WidgetsBinding.instance.removeObserver(this);
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
                  ? _buildResultScreen()
                  : _isScanning
                  ? _buildScannerScreen()
                  : _buildSetupScreen(),
            ),
            const SizedBox(height: 20),
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

  // ── Build helpers ──────────────────────────────────────────────────────────

  Widget _buildResultScreen() {
    // Verdict uses the MINIMUM of the 3 samples — most conservative and
    // relay-attack-resistant: an attacker cannot shorten all 3 trips at once.
    final bool verified = _minRttMs! < 150;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: verified
            ? Colors.green.withOpacity(0.1)
            : Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: verified ? Colors.greenAccent : Colors.redAccent,
          width: 2,
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 24),

            // ── Verdict icon ───────────────────────────────────────────────
            Icon(
              verified ? Icons.verified_user : Icons.gpp_bad,
              color: verified ? Colors.greenAccent : Colors.redAccent,
              size: 70,
            ),
            const SizedBox(height: 10),
            Text(
              verified ? "PROXIMITY VERIFIED" : "RELAY ATTACK DETECTED",
              style: TextStyle(
                color: verified ? Colors.greenAccent : Colors.redAccent,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // ── 3 sample bubbles ───────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(_rttSamples.length, (i) {
                  final int ms = _rttSamples[i];
                  final bool isMin = ms == _minRttMs;
                  return Column(
                    children: [
                      Text(
                        "S${i + 1}",
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isMin
                              ? Colors.indigoAccent.withOpacity(0.25)
                              : Colors.white10,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isMin ? Colors.indigoAccent : Colors.white24,
                            width: isMin ? 2 : 1,
                          ),
                        ),
                        child: Text(
                          "${ms}ms",
                          style: TextStyle(
                            color: isMin ? Colors.cyanAccent : Colors.white70,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      if (isMin)
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text(
                            "MIN",
                            style: TextStyle(
                              color: Colors.cyanAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  );
                }),
              ),
            ),
            const SizedBox(height: 16),

            // ── Min / Avg stat cards ───────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _statCard(
                      label: "MINIMUM",
                      value: "${_minRttMs}ms",
                      color: Colors.cyanAccent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _statCard(
                      label: "AVERAGE",
                      value: "${_avgRttMs}ms",
                      color: Colors.orangeAccent,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ── RSSI chip ──────────────────────────────────────────────────
            if (_rssi != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
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
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            const SizedBox(height: 24),

            // ── New session button ─────────────────────────────────────────
            ElevatedButton.icon(
              onPressed: _resetSession,
              icon: const Icon(Icons.refresh),
              label: const Text("NEW SESSION"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white12,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _statCard({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: color.withOpacity(0.8),
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScannerScreen() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(controller: _scannerController, onDetect: _onDetect),
          Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.indigoAccent, width: 3),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSetupScreen() {
    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.bluetooth_searching,
            color: Colors.indigoAccent,
            size: 60,
          ),
          const SizedBox(height: 15),
          TextField(
            controller: _uidController,
            style: const TextStyle(color: Colors.white, fontSize: 18),
            decoration: InputDecoration(
              labelText: "ENTER STUDENT UID",
              labelStyle: const TextStyle(color: Colors.white70),
              filled: true,
              fillColor: Colors.white10,
              enabledBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: Colors.indigoAccent),
                borderRadius: BorderRadius.circular(10),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: const BorderSide(
                  color: Colors.cyanAccent,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              prefixIcon: const Icon(Icons.badge, color: Colors.indigoAccent),
            ),
          ),
          const SizedBox(height: 15),
          DropdownButtonFormField<AndroidScanMode>(
            value: _selectedScanMode,
            dropdownColor: Colors.blueGrey[900],
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: "BLE Scan Sensitivity",
              labelStyle: const TextStyle(color: Colors.indigoAccent),
              enabledBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: Colors.indigoAccent),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            items: const [
              DropdownMenuItem(
                value: AndroidScanMode.lowLatency,
                child: Text("Low Latency (Aggressive)"),
              ),
              DropdownMenuItem(
                value: AndroidScanMode.balanced,
                child: Text("Balanced"),
              ),
              DropdownMenuItem(
                value: AndroidScanMode.lowPower,
                child: Text("Low Power (Battery Saver)"),
              ),
            ],
            onChanged: (val) => setState(() => _selectedScanMode = val!),
          ),
          const SizedBox(height: 10),
          SwitchListTile(
            title: const Text(
              "Foreground Keep-Alive",
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
            subtitle: const Text(
              "Stops OS background kills",
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            value: _useForegroundService,
            activeColor: Colors.indigoAccent,
            contentPadding: EdgeInsets.zero,
            onChanged: (val) => setState(() => _useForegroundService = val),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton.icon(
              onPressed: _startScanning,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text(
                "START PROTOCOL",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
    );
  }
}
