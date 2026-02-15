import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class AppPermissions {
  static final List<Permission> _permissions = [
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.bluetoothAdvertise,
    Permission.location,
    Permission.camera,
    // Permission.microphone,
  ];

  /// Requests all runtime permissions (without NFC)
  static Future<bool> requestAllPermissions(BuildContext context) async {
    for (Permission perm in _permissions) {
      PermissionStatus status = await perm.status;

      if (status.isGranted) continue;

      status = await perm.request();

      if (status.isPermanentlyDenied) {
        await _showPermanentDeniedDialog(context, perm);
        return false;
      }

      if (!status.isGranted) return false;
    }

    // NFC is optional; do NOT block
    return true;
  }

  // /// Checks NFC status (optional, non-blocking)
  // static Future<void> checkNfcStatus(BuildContext context) async {
  //   try {
  //     bool isAvailable = await NfcManager.instance.isAvailable();
  //     if (!isAvailable) {
  //       // Inform the user but don't block the app
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         const SnackBar(
  //           content: Text("NFC is not available or is turned off."),
  //           duration: Duration(seconds: 3),
  //         ),
  //       );
  //     }
  //   } catch (e) {
  //     // Device does not support NFC
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       const SnackBar(
  //         content: Text("NFC is not supported on this device."),
  //         duration: Duration(seconds: 3),
  //       ),
  //     );
  //   }
  // }

  static Future<void> _showPermanentDeniedDialog(
    BuildContext context,
    Permission perm,
  ) async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Permission Required"),
        content: Text(
          "${perm.toString().replaceAll("Permission.", "")} is permanently denied. Please enable it in settings.",
        ),
        actions: [
          TextButton(
            onPressed: () {
              openAppSettings();
              Navigator.pop(context);
            },
            child: const Text("Open Settings"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
        ],
      ),
    );
  }
}
