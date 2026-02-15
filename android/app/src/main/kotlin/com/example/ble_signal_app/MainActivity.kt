package com.example.ble_signal_app

import android.annotation.SuppressLint
import android.bluetooth.*
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

@SuppressLint("MissingPermission") // We handle permissions natively in Flutter!
class MainActivity: FlutterActivity() {
    private val METHOD_CHANNEL = "com.attendance/command"
    private val EVENT_CHANNEL = "com.attendance/events"
    
    // The fixed UUIDs for your classroom
    private val SERVICE_UUID = UUID.fromString("87654321-4321-4321-4321-cba987654321")
    private val CHAR_UUID = UUID.fromString("11111111-2222-3333-4444-555555555555")

    private var eventSink: EventChannel.EventSink? = null
    private var bluetoothGattServer: BluetoothGattServer? = null
    private var bluetoothManager: BluetoothManager? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. The Walkie-Talkie (Commands from Flutter)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "startServer") {
                startBleServer()
                result.success("Server Started")
            } else if (call.method == "stopServer") {
                stopBleServer()
                result.success("Server Stopped")
            } else {
                result.notImplemented()
            }
        }

        // 2. The Ticker-Tape (Data to Flutter)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )
    }

    private fun startBleServer() {
        bluetoothManager = getSystemService(BLUETOOTH_SERVICE) as BluetoothManager
        
        // --- 1. SET UP THE NATIVE ANDROID GATT SERVER ---
        bluetoothGattServer = bluetoothManager?.openGattServer(this, gattServerCallback)
        
        val service = BluetoothGattService(SERVICE_UUID, BluetoothGattService.SERVICE_TYPE_PRIMARY)
        val writeChar = BluetoothGattCharacteristic(CHAR_UUID, 
            BluetoothGattCharacteristic.PROPERTY_WRITE, 
            BluetoothGattCharacteristic.PERMISSION_WRITE)
        
        service.addCharacteristic(writeChar)
        bluetoothGattServer?.addService(service)

        // --- 2. START ADVERTISING ---
        val advertiser = bluetoothManager?.adapter?.bluetoothLeAdvertiser
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setConnectable(true)
            .build()
        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .addServiceUuid(ParcelUuid(SERVICE_UUID))
            .build()
        
        advertiser?.startAdvertising(settings, data, object : AdvertiseCallback() {})
    }

    private fun stopBleServer() {
        bluetoothGattServer?.clearServices()
        bluetoothGattServer?.close()
    }

    // --- 3. THE HARDWARE ACKNOWLEDGMENT MAGIC ---
    private val gattServerCallback = object : BluetoothGattServerCallback() {
        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray
        ) {
            super.onCharacteristicWriteRequest(device, requestId, characteristic, preparedWrite, responseNeeded, offset, value)
            
            // THIS is the line that fires the ACK back to the Student's phone to stop the Stopwatch!
            if (responseNeeded) {
                bluetoothGattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value)
            }

            // Convert the bytes to a String and push it to the Flutter UI
            val studentUid = String(value, Charsets.UTF_8)
            Handler(Looper.getMainLooper()).post {
                eventSink?.success(studentUid)
            }
        }
    }
}