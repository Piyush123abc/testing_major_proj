import 'package:ble_signal_app/ble_page.dart';
import 'package:ble_signal_app/classical_b.dart';
import 'package:ble_signal_app/gatt_ble/options.dart';
import 'package:ble_signal_app/new_becon_nature.dart';
import 'package:ble_signal_app/permissions.dart';
import 'package:ble_signal_app/test4.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class HomePage extends StatefulWidget {
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _permissionsGranted = false;
  bool _bluetoothOn = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    // 1️⃣ Request permissions
    bool granted = await AppPermissions.requestAllPermissions(context);

    // 2️⃣ Check Bluetooth state
    BluetoothAdapterState state = await FlutterBluePlus.adapterState.first;

    if (mounted) {
      setState(() {
        _permissionsGranted = granted;
        _bluetoothOn = state == BluetoothAdapterState.on;
        _loading = false;
      });
    }

    // 3️⃣ Listen for Bluetooth changes
    FlutterBluePlus.adapterState.listen((state) {
      if (mounted) {
        setState(() {
          _bluetoothOn = state == BluetoothAdapterState.on;
        });
      }
    });
  }

  void _showBluetoothDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Bluetooth is OFF"),
        content: const Text("Please turn ON Bluetooth to scan BLE devices."),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              FlutterBluePlus.turnOn();
            },
            child: const Text("TURN ON"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BLE Scanner Home')),
      body: Center(
        child: _loading
            ? const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text("Initializing app..."),
                ],
              )
            : !_permissionsGranted
            ? const Text(
                "Required permissions not granted",
                style: TextStyle(color: Colors.red),
              )
            : !_bluetoothOn
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.bluetooth_disabled,
                    size: 80,
                    color: Colors.red,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Bluetooth is OFF",
                    style: TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _showBluetoothDialog,
                    child: const Text("Turn Bluetooth ON"),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      // Navigator.push(
                      //   context,
                      //   MaterialPageRoute(builder: (_) => BluetoothPage()),
                      // );
                    },
                    child: const Text('Old Scanner'),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ClassicBluetoothTestPage(),
                        ),
                      );
                    },
                    child: const Text('New Scanner'),
                  ),
                  // const SizedBox(height: 20),
                  // ElevatedButton(
                  //   onPressed: () {
                  //     Navigator.push(
                  //       context,
                  //       MaterialPageRoute(builder: (_) => UniversalBlePage()),
                  //     );
                  //   },
                  //   child: const Text('New New Scanner'),
                  // ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => TokenTransferPage()),
                      );
                    },
                    child: const Text('test4'),
                  ),

                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AttendanceEntryPage(),
                        ),
                      );
                    },
                    child: const Text('gatt_ble'),
                  ),
                ],
              ),
      ),
    );
  }
}
