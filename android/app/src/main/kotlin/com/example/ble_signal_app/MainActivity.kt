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

@SuppressLint("MissingPermission")
class MainActivity: FlutterActivity() {
    private val METHOD_CHANNEL = "com.attendance/command"
    private val EVENT_CHANNEL = "com.attendance/events"
    
    private val CLASSIC_BT_CHANNEL = "com.attendance/classic_bt"
    private var classicBtManager: ClassicBtManager? = null

    private val SERVICE_UUID = UUID.fromString("87654321-4321-4321-4321-cba987654321")
    private val CHAR_UUID = UUID.fromString("11111111-2222-3333-4444-555555555555")

    private var eventSink: EventChannel.EventSink? = null
    private var bluetoothGattServer: BluetoothGattServer? = null
    private var bluetoothManager: BluetoothManager? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        classicBtManager = ClassicBtManager(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "startServer") {
                startBleServer()
                result.success("Server Initialization Command Sent to OS")
            } else if (call.method == "stopServer") {
                stopBleServer()
                result.success("Server Stopped")
            } else {
                result.notImplemented()
            }
        }

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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CLASSIC_BT_CHANNEL).setMethodCallHandler { call, result ->
            // (Keeping your classic BT channel intact)
            when (call.method) {
                "startServer" -> {
                    val uuid = call.argument<String>("uuid") ?: return@setMethodCallHandler result.error("ERR", "No UUID", null)
                    classicBtManager?.startServer(uuid, result)
                }
                "stopServer" -> {
                    classicBtManager?.stopServer()
                    result.success("Server Stopped")
                }
                "connectAndPing" -> {
                    val mac = call.argument<String>("mac") ?: return@setMethodCallHandler result.error("ERR", "No MAC", null)
                    val uuid = call.argument<String>("uuid") ?: return@setMethodCallHandler result.error("ERR", "No UUID", null)
                    val payload = call.argument<String>("payload") ?: "PING"
                    classicBtManager?.connectAndPing(mac, uuid, payload, result)
                }
                "disconnectClient" -> {
                    classicBtManager?.stopClient()
                    result.success("Client Stopped")
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startBleServer() {
        bluetoothManager = getSystemService(BLUETOOTH_SERVICE) as BluetoothManager
        val adapter = bluetoothManager?.adapter

        if (adapter == null || !adapter.isMultipleAdvertisementSupported) {
            Handler(Looper.getMainLooper()).post {
                eventSink?.success("FATAL:HARDWARE: FEATURE_UNSUPPORTED. This phone physically cannot host a GATT server.")
            }
            return
        }
        
        bluetoothGattServer = bluetoothManager?.openGattServer(this, gattServerCallback)
        
        val service = BluetoothGattService(SERVICE_UUID, BluetoothGattService.SERVICE_TYPE_PRIMARY)
        val writeChar = BluetoothGattCharacteristic(CHAR_UUID, 
            BluetoothGattCharacteristic.PROPERTY_WRITE, 
            BluetoothGattCharacteristic.PERMISSION_WRITE)
        
        service.addCharacteristic(writeChar)
        bluetoothGattServer?.addService(service)

        val advertiser = adapter.bluetoothLeAdvertiser
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setConnectable(true)
            .build()
        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .addServiceUuid(ParcelUuid(SERVICE_UUID))
            .build()
        
        // --- NEW: THE HARDWARE TRUTH-TELLER CALLBACK ---
        advertiser?.startAdvertising(settings, data, object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
                super.onStartSuccess(settingsInEffect)
                Handler(Looper.getMainLooper()).post {
                    eventSink?.success("LOG: OS confirmed broadcast is active on hardware.")
                }
            }

            override fun onStartFailure(errorCode: Int) {
                super.onStartFailure(errorCode)
                val errorMsg = when(errorCode) {
                    ADVERTISE_FAILED_DATA_TOO_LARGE -> "DATA_TOO_LARGE"
                    ADVERTISE_FAILED_TOO_MANY_ADVERTISERS -> "TOO_MANY_ADVERTISERS (OS/Memory Throttling)"
                    ADVERTISE_FAILED_ALREADY_STARTED -> "ALREADY_STARTED"
                    ADVERTISE_FAILED_INTERNAL_ERROR -> "INTERNAL_ERROR (Android Bluetooth Stack Crashed)"
                    ADVERTISE_FAILED_FEATURE_UNSUPPORTED -> "FEATURE_UNSUPPORTED (Hardware limitation)"
                    else -> "UNKNOWN_HARDWARE_ERROR_$errorCode"
                }
                Handler(Looper.getMainLooper()).post {
                    eventSink?.success("FATAL:HARDWARE: $errorMsg")
                }
            }
        })
    }

    private fun stopBleServer() {
        bluetoothGattServer?.clearServices()
        bluetoothGattServer?.close()
    }

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
            
            if (responseNeeded) {
                bluetoothGattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value)
            }

            val studentUid = String(value, Charsets.UTF_8)
            Handler(Looper.getMainLooper()).post {
                eventSink?.success("ACK:$studentUid")
            }
        }
    }
}