import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:barcode_widget/barcode_widget.dart' as bw;

class ReceiverPage extends StatefulWidget {
  const ReceiverPage({super.key});

  @override
  State<ReceiverPage> createState() => _ReceiverPageState();
}

class _ReceiverPageState extends State<ReceiverPage> {
  final TextEditingController _uidController = TextEditingController();

  // The Bridge to Native Kotlin
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

  // This is the static UUID we put in the QR code
  final String serviceUuid = "87654321-4321-4321-4321-cba987654321";

  @override
  void initState() {
    super.initState();
    // Listen to the ticker-tape feed from Kotlin
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen((
      dynamic event,
    ) {
      String studentUid = event.toString();
      _addLog(
        "HARDWARE ACK: Received Student UID [$studentUid]",
        isMatch: true,
      );
      HapticFeedback.heavyImpact();
    });
  }

  void _addLog(String msg, {bool isMatch = false}) {
    if (!_verboseMode && !isMatch) return;
    setState(() {
      _terminalLogs.insert(
        0,
        "[${DateTime.now().toIso8601String().split('T')[1].substring(0, 8)}] $msg",
      );
    });
  }

  Future<void> _startNativeServer() async {
    if (_uidController.text.isEmpty) {
      _addLog("ERROR: Teacher UID cannot be empty.");
      return;
    }

    try {
      // Tell Kotlin to start the GATT server and Advertiser
      await _methodChannel.invokeMethod('startServer');
      setState(() => _isAdvertising = true);
      _addLog("PIPE: Native GATT Server Hosted.", isMatch: false);
      _addLog("BROADCASTING: $serviceUuid", isMatch: false);
    } catch (e) {
      _addLog("ERROR: Native bridge failed - $e");
    }
  }

  Future<void> _stopNativeServer() async {
    try {
      await _methodChannel.invokeMethod('stopServer');
      setState(() => _isAdvertising = false);
      _addLog("PIPE: Server Offline. Port closed.", isMatch: false);
    } catch (e) {
      _addLog("ERROR: Could not stop server - $e");
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
      backgroundColor: const Color(0xFF0A0A0A), // Deep black-grey
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
            // Header Card
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
                    ? Column(
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
                          const SizedBox(height: 25),
                          TextField(
                            controller: _uidController,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                            ), // Large white text
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
                          const SizedBox(height: 30),
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

            // Terminal Log Header
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

            // Terminal Window
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
                      style: const TextStyle(
                        color: Colors.greenAccent,
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
