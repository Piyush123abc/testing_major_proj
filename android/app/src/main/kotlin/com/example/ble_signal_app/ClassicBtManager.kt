package com.example.ble_signal_app

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import kotlin.concurrent.thread

@SuppressLint("MissingPermission") // Permissions handled in Flutter
class ClassicBtManager(context: Context) {
    private val bluetoothAdapter: BluetoothAdapter? = (context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter
    
    // Server (Teacher) Variables
    private var serverSocket: BluetoothServerSocket? = null
    private var isServerRunning = false
    
    // Client (Student) Variables
    private var clientSocket: BluetoothSocket? = null

    // --- 1. HOST SERVER (TEACHER) ---
    fun startServer(uuidString: String, result: MethodChannel.Result) {
        if (bluetoothAdapter == null) {
            result.error("NO_BT", "Bluetooth not supported on this device", null)
            return
        }
        
        val uuid = UUID.fromString(uuidString)
        
        // Run on a background thread so the app doesn't freeze!
        thread {
            try {
                // This is the magic "Bypass Pairing Popup" socket
                serverSocket = bluetoothAdapter.listenUsingInsecureRfcommWithServiceRecord("AttendanceServer", uuid)
                isServerRunning = true
                
                // Tell Flutter the server started successfully
                Handler(Looper.getMainLooper()).post { result.success("Server Started") }
                
                // Keep listening for student connections
                while (isServerRunning) {
                    val socket = serverSocket?.accept() // This blocks until a student connects
                    socket?.let {
                        handleStudentPing(it)
                    }
                }
            } catch (e: Exception) {
                if (isServerRunning) {
                    Handler(Looper.getMainLooper()).post { result.error("SERVER_ERR", e.message, null) }
                }
            }
        }
    }
    
    // Read the student's payload and instantly fire an ACK back
    private fun handleStudentPing(socket: BluetoothSocket) {
        thread {
            try {
                val inputStream = socket.inputStream
                val outputStream = socket.outputStream
                
                // Read payload (e.g., Student ID)
                val buffer = ByteArray(1024)
                val bytes = inputStream.read(buffer)
                val received = String(buffer, 0, bytes)
                
                // Fire Acknowledgement back instantly to stop the Stopwatch
                val ack = "ACK_$received"
                outputStream.write(ack.toByteArray())
                outputStream.flush()
                
            } catch (e: Exception) {
                e.printStackTrace()
            } finally {
                // Close the socket immediately so the next student can connect
                try { socket.close() } catch (e: Exception) {}
            }
        }
    }

    fun stopServer() {
        isServerRunning = false
        try { serverSocket?.close() } catch (e: Exception) {}
    }

    // --- 2. CONNECT AND PING (STUDENT) ---
    fun connectAndPing(macAddress: String, uuidString: String, payload: String, result: MethodChannel.Result) {
        if (bluetoothAdapter == null) {
            result.error("NO_BT", "Bluetooth not supported", null)
            return
        }
        
        thread {
            try {
                val device = bluetoothAdapter.getRemoteDevice(macAddress)
                val uuid = UUID.fromString(uuidString)
                
                // Connect to the Teacher's insecure socket
                clientSocket = device.createInsecureRfcommSocketToServiceRecord(uuid)
                clientSocket?.connect()
                
                val outputStream = clientSocket?.outputStream
                val inputStream = clientSocket?.inputStream
                
                // Send Student ID
                outputStream?.write(payload.toByteArray())
                outputStream?.flush()
                
                // Wait for the Teacher's ACK response
                val buffer = ByteArray(1024)
                val bytes = inputStream?.read(buffer) ?: 0
                val ackResponse = if (bytes > 0) String(buffer, 0, bytes) else "NO_ACK"
                
                // Send the success data back to Flutter
                val responseMap = mapOf(
                    "success" to true,
                    "rssi" to 0, // Note: Classic BT RSSI is asynchronous. Returning 0 for socket stability.
                    "ackPayload" to ackResponse
                )
                
                Handler(Looper.getMainLooper()).post { result.success(responseMap) }
                
            } catch (e: Exception) {
                Handler(Looper.getMainLooper()).post { result.error("CLIENT_ERR", e.message, null) }
            } finally {
                try { clientSocket?.close() } catch (e: Exception) {}
            }
        }
    }
    
    fun stopClient() {
        try { clientSocket?.close() } catch (e: Exception) {}
    }
}