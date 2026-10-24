package com.continuity.ecosystem.connection

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.BatteryManager
import android.os.Binder
import android.os.IBinder
import android.os.StatFs
import android.util.Log
import com.continuity.ecosystem.core.*
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.io.InputStream
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.Socket

class ConnectionService : Service() {

    private val binder = LocalBinder()
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    private var socket: Socket? = null
    private var outputStream: OutputStream? = null
    private var inputStream: InputStream? = null

    private lateinit var identity: DeviceIdentity
    private var host: String = "127.0.0.1"
    private var port: Int = 52400
    private var isConnected = false
    private var sessionToken: String? = null
    private val writeMutex = Mutex()

    var onConnectionStateChanged: ((Boolean) -> Unit)? = null
    var onEnvelopeReceived: ((ContinuityEnvelope) -> Unit)? = null

    inner class LocalBinder : Binder() {
        fun getService(): ConnectionService = this@ConnectionService
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onCreate() {
        super.onCreate()
        identity = DeviceIdentity(this)
        startForegroundNotification()
    }

    fun connect(targetHost: String, targetPort: Int) {
        this.host = targetHost
        this.port = targetPort

        scope.launch {
            try {
                disconnect()
                Log.d("ConnectionService", "Connecting to $host:$port...")
                val sock = Socket()
                sock.connect(InetSocketAddress(host, port), 5000)
                socket = sock
                outputStream = sock.getOutputStream()
                inputStream = sock.getInputStream()
                isConnected = true

                withContext(Dispatchers.Main) {
                    onConnectionStateChanged?.invoke(true)
                }

                // Send DeviceHello immediately
                val helloEnv = ContinuityEnvelope(
                    senderDeviceId = identity.deviceId,
                    deviceHello = DeviceHello(
                        appVersion = "1.0.0",
                        osVersion = "Android ${android.os.Build.VERSION.RELEASE}",
                        deviceModel = identity.deviceName
                    )
                )
                sendEnvelope(helloEnv)

                // Start telemetry loop
                startTelemetryJob()

                // Start reading loop
                readLoop()
            } catch (e: Exception) {
                Log.e("ConnectionService", "Connection error: ${e.message}")
                handleDisconnect()
            }
        }
    }

    fun sendEnvelope(envelope: ContinuityEnvelope) {
        scope.launch {
            try {
                writeMutex.withLock {
                    outputStream?.let {
                        ProtocolFraming.writeEnvelope(it, envelope)
                    }
                }
            } catch (e: Exception) {
                Log.e("ConnectionService", "Send error: ${e.message}")
                handleDisconnect()
            }
        }
    }

    private fun readLoop() {
        while (isConnected && inputStream != null) {
            try {
                val envelope = ProtocolFraming.readEnvelope(inputStream!!)
                if (envelope != null) {
                    envelope.sessionToken?.let { sessionToken = it }
                    withContext(Dispatchers.Main) {
                        onEnvelopeReceived?.invoke(envelope)
                    }
                } else {
                    break
                }
            } catch (e: Exception) {
                break
            }
        }
        handleDisconnect()
    }

    private fun startTelemetryJob() {
        scope.launch {
            while (isConnected) {
                val status = collectDeviceStatus()
                val env = ContinuityEnvelope(
                    senderDeviceId = identity.deviceId,
                    sessionToken = sessionToken,
                    deviceStatus = status
                )
                sendEnvelope(env)
                delay(15000) // Send every 15 seconds
            }
        }
    }

    private fun collectDeviceStatus(): DeviceStatus {
        val bm = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        val batteryPct = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        val isCharging = bm.isCharging

        val stat = StatFs(filesDir.path)
        val freeBytes = stat.availableBlocksLong * stat.blockSizeLong
        val totalBytes = stat.blockCountLong * stat.blockSizeLong

        return DeviceStatus(
            batteryPercentage = batteryPct,
            isCharging = isCharging,
            isWifiConnected = true,
            wifiSsid = "Wi-Fi",
            freeStorageBytes = freeBytes,
            totalStorageBytes = totalBytes
        )
    }

    fun disconnect() {
        isConnected = false
        try {
            socket?.close()
        } catch (_: Exception) {}
        socket = null
        outputStream = null
        inputStream = null
        withContext(Dispatchers.Main) {
            onConnectionStateChanged?.invoke(false)
        }
    }

    private fun handleDisconnect() {
        disconnect()
    }

    private fun startForegroundNotification() {
        val channelId = "continuity_connection"
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            channelId,
            "Continuity Status",
            NotificationManager.IMPORTANCE_LOW
        )
        nm.createNotificationChannel(channel)

        val notification = Notification.Builder(this, channelId)
            .setContentTitle("Continuity Active")
            .setContentText("Connected to Mac desktop workspace")
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setOngoing(true)
            .build()

        startForeground(1001, notification)
    }

    override fun onDestroy() {
        super.onDestroy()
        disconnect()
        scope.cancel()
    }
}
