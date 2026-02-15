import 'package:ble_signal_app/gatt_ble/QR_code_page.dart';
import 'package:ble_signal_app/gatt_ble/scanner_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AttendanceEntryPage extends StatelessWidget {
  // This would dynamically come from your GlobalStudentProfile
  final String studentUid = "2023800010";

  const AttendanceEntryPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Lock orientation to portrait to keep the split screen UX consistent
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            // BACKGROUND: The 50/50 Split Screen
            Column(
              children: [
                // ---------------- TOP HALF: SCAN (SENDER) ----------------
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.heavyImpact();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ScannerPage(),
                        ),
                      );
                    },
                    child: Container(
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        color: Color(0xFF1E1E1E), // Dark slate
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.greenAccent.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.qr_code_scanner_rounded,
                              size: 80,
                              color: Colors.greenAccent,
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            "I am Sending",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "Tap to scan your neighbor's QR",
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ---------------- BOTTOM HALF: SHOW (RECEIVER) ----------------
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.heavyImpact();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ReceiverPage(),
                        ),
                      );
                    },
                    child: Container(
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(32),
                          topRight: Radius.circular(32),
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.blueAccent.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.qr_code_2_rounded,
                              size: 80,
                              color: Colors.blueAccent,
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            "I am Receiving",
                            style: TextStyle(
                              color: Colors.black87,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            "Tap to show your QR to a neighbor",
                            style: TextStyle(
                              color: Colors.black54,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Subtly display the bound UID at the very bottom
                Container(
                  color: Colors.white,
                  width: double.infinity,
                  padding: const EdgeInsets.only(bottom: 24, top: 12),
                  alignment: Alignment.center,
                  child: Text(
                    "Secured Session • UID: $studentUid",
                    style: const TextStyle(
                      color: Colors.black38,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),

            // FOREGROUND: Floating Back Button
            // FOREGROUND: Floating Back Button (Smaller & Tucked away)
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                padding: EdgeInsets.zero, // Removes default extra padding
                constraints:
                    const BoxConstraints(), // Shrinks the hitbox tightly around the icon
                splashRadius: 20, // Smaller tap ripple
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color:
                      Colors.white70, // Slightly dimmed so it doesn't distract
                  size: 20, // Smaller icon
                ),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
