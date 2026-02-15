// // scanner_page.dart
// import 'dart:convert';
// import 'dart:developer';
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:flutter_blue_plus/flutter_blue_plus.dart';

// class ScannerPage extends StatefulWidget {
//   const ScannerPage({super.key});

//   @override
//   State<ScannerPage> createState() => _ScannerPageState();
// }

// class _ScannerPageState extends State<ScannerPage> {
//   final TextEditingController _uid = TextEditingController();
//   final TextEditingController _serviceId = TextEditingController();
//   final TextEditingController _charId = TextEditingController();

//   BluetoothDevice? _device;
//   BluetoothCharacteristic? _writeChar;

//   bool _isScanning = false;
//   bool _connected = false;
//   bool _handshakeDone = false;

//   String debugLog = "";
//   int rssiValue = 0;
//   int rttMs = 0;

//   String _formatUuid(String input) {
//     if (input.length <= 8) {
//       return "0000$input-0000-1000-8000-00805f9b34fb";
//     }
//     return input;
//   }

//   void addLog(String msg) {
//     setState(() => debugLog += "$msg\n");
//     log(msg);
//   }

//   Future<void> startScan() async {
//     if (_uid.text.isEmpty || _serviceId.text.isEmpty || _charId.text.isEmpty) {
//       addLog("❗ Enter UID + Service ID + Characteristic ID first.");
//       return;
//     }

//     final serviceUuid = Guid(_formatUuid(_serviceId.text));

//     setState(() {
//       _isScanning = true;
//       debugLog = "";
//     });

//     addLog("🔍 Scanning for service: $serviceUuid");

//     FlutterBluePlus.startScan(withServices: [serviceUuid]).listen((
//       scanResult,
//     ) async {
//       rssiValue = scanResult.rssi;

//       if (scanResult.advertisementData.localName.startsWith("Node_")) {
//         addLog("🎯 Found Target: ${scanResult.device.remoteId}");
//         _device = scanResult.device;

//         FlutterBluePlus.stopScan();
//         connectToDevice();
//       }
//     });
//   }

//   Future<void> connectToDevice() async {
//     if (_device == null) {
//       addLog("❗ No device selected.");
//       return;
//     }

//     addLog("🔗 Connecting...");
//     await _device!.connect();

//     setState(() => _connected = true);
//     addLog("✅ Connected!");

//     await discoverServices();
//   }

//   Future<void> discoverServices() async {
//     final services = await _device!.discoverServices();

//     final sid = Guid(_formatUuid(_serviceId.text));
//     final cid = Guid(_formatUuid(_charId.text));

//     for (var s in services) {
//       if (s.uuid == sid) {
//         for (var c in s.characteristics) {
//           if (c.uuid == cid) {
//             _writeChar = c;
//             addLog("📮 Characteristic Found!");
//             performHandshake();
//             return;
//           }
//         }
//       }
//     }

//     addLog("❗ Characteristic not found.");
//   }

//   Future<void> performHandshake() async {
//     if (_writeChar == null) {
//       addLog("❗ _writeChar is null");
//       return;
//     }

//     final sendData = utf8.encode(_uid.text);

//     addLog("📤 Sending UID...");
//     final startTime = DateTime.now();

//     await _writeChar!.write(sendData, withoutResponse: false);

//     await Future.delayed(const Duration(milliseconds: 150));

//     addLog("📥 Reading ACK...");
//     final ackBytes = await _writeChar!.read();

//     final ack = utf8.decode(ackBytes);
//     rttMs = DateTime.now().difference(startTime).inMilliseconds;

//     if (ack == "ACK") {
//       setState(() => _handshakeDone = true);
//       HapticFeedback.heavyImpact();

//       addLog("🎉 Handshake SUCCESS!");
//       addLog("📡 RSSI = $rssiValue dBm");
//       addLog("⏱ RTT = $rttMs ms");
//     } else {
//       addLog("❗ Wrong ACK: $ack");
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: Colors.black,
//       appBar: AppBar(
//         title: const Text(
//           "Scanner (Client)",
//           style: TextStyle(color: Colors.white),
//         ),
//         backgroundColor: Colors.black,
//       ),
//       body: Column(
//         children: [
//           Expanded(
//             child: Center(
//               child: !_handshakeDone ? buildInputUI() : buildSuccessUI(),
//             ),
//           ),
//           buildDebugConsole(),
//         ],
//       ),
//     );
//   }

//   Widget buildInputUI() {
//     return Column(
//       mainAxisAlignment: MainAxisAlignment.center,
//       children: [
//         buildField(_uid, "Your UID"),
//         const SizedBox(height: 12),
//         buildField(_serviceId, "Service ID (e.g., 1223)"),
//         const SizedBox(height: 12),
//         buildField(_charId, "Characteristic ID (e.g., 3344)"),
//         const SizedBox(height: 25),

//         _isScanning
//             ? const CircularProgressIndicator(color: Colors.greenAccent)
//             : ElevatedButton(
//                 onPressed: startScan,
//                 style: ElevatedButton.styleFrom(
//                   backgroundColor: Colors.blueAccent,
//                 ),
//                 child: const Text("Start Scan"),
//               ),
//       ],
//     );
//   }

//   Widget buildSuccessUI() {
//     return Column(
//       mainAxisAlignment: MainAxisAlignment.center,
//       children: [
//         const Icon(Icons.verified, color: Colors.greenAccent, size: 80),
//         const SizedBox(height: 20),
//         Text("Handshake DONE!", style: const TextStyle(color: Colors.white)),
//         const SizedBox(height: 10),
//         Text(
//           "RSSI: $rssiValue dBm",
//           style: const TextStyle(color: Colors.white70),
//         ),
//         Text("RTT: $rttMs ms", style: const TextStyle(color: Colors.white70)),
//       ],
//     );
//   }

//   Widget buildField(TextEditingController c, String label) {
//     return SizedBox(
//       width: 260,
//       child: TextField(
//         controller: c,
//         style: const TextStyle(color: Colors.white),
//         decoration: InputDecoration(
//           labelText: label,
//           labelStyle: const TextStyle(color: Colors.blueAccent),
//           enabledBorder: const UnderlineInputBorder(
//             borderSide: BorderSide(color: Colors.white54),
//           ),
//         ),
//       ),
//     );
//   }

//   Widget buildDebugConsole() {
//     return Container(
//       height: 180,
//       width: double.infinity,
//       padding: const EdgeInsets.all(8),
//       color: Colors.black87,
//       child: SingleChildScrollView(
//         child: Text(
//           debugLog,
//           style: const TextStyle(color: Colors.greenAccent),
//         ),
//       ),
//     );
//   }
// }
