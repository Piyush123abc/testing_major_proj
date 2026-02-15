package com.example.ble_signal_app


import android.bluetooth.*
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.util.*

class BluetoothService(private val context: Context, private val eventCallback: (Map<String, Any>) -> Unit) {

    private val TAG = "BluetoothService"
    private val APP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB") // SPP UUID

    private var serverThread: Thread? = null
    private var clientThread: Thread? = null
    private var running = false

    private var serverSocket: BluetoothServerSocket? = null
    private var clientSocket: BluetoothSocket? = null

    private val handler = Handler(Looper.getMainLooper())

    // -------------------- SERVER LOGIC --------------------
    fun startServer() {
        stopServer()
        running = true
        serverThread = Thread {
            try {
                val bluetoothAdapter = BluetoothAdapter.getDefaultAdapter()
                serverSocket = bluetoothAdapter.listenUsingRfcommWithServiceRecord("ClassicBTServer", APP_UUID)
                logDebug("Server socket opened, waiting for connections...")

                while (running) {
                    val socket = serverSocket?.accept()
                    if (socket != null) {
                        logDebug("Device connected: ${socket.remoteDevice.name}")
                        handleClient(socket)
                    }
                }
            } catch (e: IOException) {
                logDebug("Server error: ${e.message}")
            }
        }
        serverThread?.start()
    }

    fun stopServer() {
        running = false
        try {
            serverSocket?.close()
            clientSocket?.close()
        } catch (e: IOException) {
            logDebug("Stop error: ${e.message}")
        }
        serverThread = null
    }

    // -------------------- CLIENT LOGIC --------------------
    fun connectToDevice(deviceAddress: String, payload: String) {
        clientThread?.interrupt()
        clientThread = Thread {
            try {
                val adapter = BluetoothAdapter.getDefaultAdapter()
                val device = adapter.getRemoteDevice(deviceAddress)
                clientSocket = device.createRfcommSocketToServiceRecord(APP_UUID)
                adapter.cancelDiscovery()
                clientSocket?.connect()
                logDebug("Connected to ${device.name}")

                // Send payload
                sendPayload(clientSocket!!, payload)

                // Wait for OK
                val received = readPayload(clientSocket!!)
                if (received.trim() == "OK") {
                    logDebug("✅ OK received from ${device.name}")
                }

                clientSocket?.close()
            } catch (e: IOException) {
                logDebug("Client error: ${e.message}")
            }
        }
        clientThread?.start()
    }

    private fun sendPayload(socket: BluetoothSocket, payload: String) {
        try {
            val out: OutputStream = socket.outputStream
            out.write((payload + "\n").toByteArray())
            out.flush()
            logDebug("Payload sent: $payload")
        } catch (e: IOException) {
            logDebug("Send error: ${e.message}")
        }
    }

    private fun readPayload(socket: BluetoothSocket): String {
        return try {
            val input: InputStream = socket.inputStream
            val buffer = ByteArray(1024)
            val bytes = input.read(buffer)
            val received = String(buffer, 0, bytes)
            logDebug("Payload received: $received")
            received
        } catch (e: IOException) {
            logDebug("Read error: ${e.message}")
            ""
        }
    }

    private fun handleClient(socket: BluetoothSocket) {
        try {
            val input: InputStream = socket.inputStream
            val buffer = ByteArray(1024)
            val bytes = input.read(buffer)
            val received = String(buffer, 0, bytes)
            val deviceName = socket.remoteDevice.name
            val rssi = socket.remoteDevice.fetchRssi() // approximation; requires workaround

            logDebug("Received payload: $received, RSSI: $rssi, from: $deviceName")

            // Send OK back
            val out: OutputStream = socket.outputStream
            out.write("OK\n".toByteArray())
            out.flush()
            logDebug("✅ OK sent back to sender")

            socket.close()
        } catch (e: IOException) {
            logDebug("Client handling error: ${e.message}")
        }
    }

    private fun logDebug(message: String) {
        Log.d(TAG, message)
        handler.post {
            eventCallback(mapOf("event" to "debug", "message" to message))
        }
    }

    // -------------------- UTILS --------------------
    private fun BluetoothDevice.fetchRssi(): Int {
        // Classic BT does not provide direct RSSI; can implement periodic discovery callback if needed
        return -1
    }
}
