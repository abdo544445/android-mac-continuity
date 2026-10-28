package com.continuity.ecosystem.connection

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.os.BatteryManager
import android.os.Binder
import android.os.Build
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

    companion object {
        @Volatile
        var activeInstance: ConnectionService? = null
    }

    private val binder = LocalBinder()
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    private var socket: Socket? = null
    private var outputStream: OutputStream? = null
    private var inputStream: InputStream? = null
    private var telemetryJob: Job? = null

    private lateinit var identity: DeviceIdentity
    var currentHost: String = "127.0.0.1"
        private set
    var currentPort: Int = 52400
        private set
    var currentConnectionState: Boolean = false
        private set
    private var sessionToken: String? = null
    private val writeMutex = Mutex()

    val hostControlHandler: HostControlHandler by lazy { HostControlHandler(this) }

    var onConnectionStateChanged: ((Boolean) -> Unit)? = null
    var onEnvelopeReceived: ((ContinuityEnvelope) -> Unit)? = null
    var onBinaryChunkReceived: ((RawBinaryChunk) -> Unit)? = null

    inner class LocalBinder : Binder() {
        fun getService(): ConnectionService = this@ConnectionService
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onCreate() {
        super.onCreate()
        activeInstance = this
        identity = DeviceIdentity(this)
        startForegroundNotification()
    }

    fun connect(
        targetHost: String,
        targetPort: Int,
        initialPairRequest: PairRequest? = null,
        onError: ((String) -> Unit)? = null
    ) {
        this.currentHost = targetHost
        this.currentPort = targetPort

        scope.launch {
            try {
                closeSocketQuietly()
                Log.w("ContinuityDebug", "Connecting to Mac (target=$targetHost:$targetPort, usbTunnel=127.0.0.1:$targetPort)...")

                // Try USB-C ADB Fast-Path (127.0.0.1) FIRST if plugged in via USB cable, then Wi-Fi LAN IP
                val sock = try {
                    Socket().apply {
                        tcpNoDelay = true
                        sendBufferSize = 4 * 1024 * 1024
                        receiveBufferSize = 4 * 1024 * 1024
                        connect(InetSocketAddress("127.0.0.1", targetPort), 400)
                    }.also {
                        Log.w("ContinuityDebug", "Connected via high-speed USB-C tunnel (127.0.0.1:$targetPort)")
                    }
                } catch (_: Exception) {
                    Socket().apply {
                        tcpNoDelay = true
                        sendBufferSize = 4 * 1024 * 1024
                        receiveBufferSize = 4 * 1024 * 1024
                        connect(InetSocketAddress(targetHost, targetPort), 4000)
                    }.also {
                        Log.w("ContinuityDebug", "Connected via Wi-Fi LAN ($targetHost:$targetPort)")
                    }
                }

                socket = sock
                outputStream = sock.getOutputStream()
                inputStream = sock.getInputStream()
                currentConnectionState = true

                withContext(Dispatchers.Main) {
                    onConnectionStateChanged?.invoke(true)
                }

                // 1. If pairing was initiated, send PairRequest immediately over the open socket
                if (initialPairRequest != null) {
                    val pairEnv = ContinuityEnvelope(
                        senderDeviceId = identity.deviceId,
                        pairRequest = initialPairRequest
                    )
                    writeMutex.withLock {
                        outputStream?.let { ProtocolFraming.writeEnvelope(it, pairEnv) }
                    }
                }

                // 2. Send DeviceHello immediately
                val helloEnv = ContinuityEnvelope(
                    senderDeviceId = identity.deviceId,
                    sessionToken = sessionToken,
                    deviceHello = DeviceHello(
                        appVersion = "1.0.0",
                        osVersion = "Android ${android.os.Build.VERSION.RELEASE}",
                        deviceModel = identity.deviceName
                    )
                )
                writeMutex.withLock {
                    outputStream?.let { ProtocolFraming.writeEnvelope(it, helloEnv) }
                }

                // 3. Start telemetry loop
                startTelemetryJob()

                // 4. Start reading loop
                readLoop(sock)
            } catch (e: Exception) {
                Log.e("ConnectionService", "Connection error: ${e.message}", e)
                handleDisconnect()
                withContext(Dispatchers.Main) {
                    onError?.invoke(e.localizedMessage ?: "Could not reach Mac at $targetHost:$targetPort")
                }
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

    fun sendBinaryChunk(chunk: RawBinaryChunk) {
        scope.launch {
            try {
                writeMutex.withLock {
                    outputStream?.let {
                        ProtocolFraming.writeBinaryChunk(it, chunk)
                    }
                }
            } catch (e: Exception) {
                Log.e("ConnectionService", "Send chunk error: ${e.message}")
                handleDisconnect()
            }
        }
    }

    private val isWritingStreamChunk = java.util.concurrent.atomic.AtomicBoolean(false)

    fun sendStreamChunk(chunk: RawBinaryChunk) {
        if (!isWritingStreamChunk.compareAndSet(false, true)) {
            // Drop stale frame if socket is currently transmitting previous frame
            return
        }
        scope.launch(Dispatchers.IO) {
            try {
                val os = outputStream
                if (os != null && currentConnectionState) {
                    writeMutex.withLock {
                        ProtocolFraming.writeBinaryChunk(os, chunk)
                    }
                }
            } catch (e: Exception) {
                Log.w("ConnectionService", "Stream frame drop: ${e.message}")
            } finally {
                isWritingStreamChunk.set(false)
            }
        }
    }

    suspend fun sendBinaryChunkSync(chunk: RawBinaryChunk) {
        try {
            writeMutex.withLock {
                outputStream?.let {
                    ProtocolFraming.writeBinaryChunk(it, chunk)
                }
            }
        } catch (e: Exception) {
            Log.e("ContinuityDebug", "Send chunk error: ${e.message}")
            handleDisconnect()
            throw e
        }
    }

    private fun readLoop(activeSock: Socket) {
        val ins = inputStream ?: return
        while (currentConnectionState && socket === activeSock && !activeSock.isClosed) {
            try {
                val frame = ProtocolFraming.readFrame(ins)
                if (frame != null) {
                    when (frame) {
                        is DecodedFrame.Envelope -> {
                            frame.envelope.sessionToken?.let { sessionToken = it }
                            frame.envelope.inputEvent?.let { hostControlHandler.handleInputEvent(it) }
                            scope.launch(Dispatchers.Main) {
                                onEnvelopeReceived?.invoke(frame.envelope)
                            }
                        }
                        is DecodedFrame.BinaryChunk -> {
                            // Process binary file chunks directly on the IO thread to preserve order and avoid Main thread stalls
                            onBinaryChunkReceived?.invoke(frame.chunk)
                        }
                    }
                } else {
                    break
                }
            } catch (e: Exception) {
                Log.w("ContinuityDebug", "Socket readLoop ended: ${e.message}")
                break
            }
        }
        if (socket === activeSock) {
            handleDisconnect()
        }
    }

    private fun startTelemetryJob() {
        telemetryJob?.cancel()
        telemetryJob = scope.launch {
            // Send initial status immediately upon socket connection
            try {
                val initStatus = collectDeviceStatus()
                sendEnvelope(
                    ContinuityEnvelope(
                        senderDeviceId = identity.deviceId,
                        sessionToken = sessionToken,
                        deviceStatus = initStatus
                    )
                )
            } catch (_: Exception) {}

            while (currentConnectionState && isActive) {
                delay(8000)
                if (!currentConnectionState || !isActive) break
                val status = collectDeviceStatus()
                val env = ContinuityEnvelope(
                    senderDeviceId = identity.deviceId,
                    sessionToken = sessionToken,
                    deviceStatus = status
                )
                sendEnvelope(env)
            }
        }
    }

    private fun collectDeviceStatus(): DeviceStatus {
        var batteryPct = 100
        var isCharging = false
        try {
            val ifilter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
            val batteryStatus = registerReceiver(null, ifilter)
            val level = batteryStatus?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
            val scale = batteryStatus?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
            if (level >= 0 && scale > 0) {
                batteryPct = (level * 100 / scale.toFloat()).toInt()
            } else {
                val bm = getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
                val prop = bm?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: -1
                if (prop in 0..100) {
                    batteryPct = prop
                }
            }
            val status = batteryStatus?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
            isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL
        } catch (_: Exception) {}

        val wifiSsid = getConnectedWifiSsid()

        val stat = StatFs(filesDir.path)
        val freeBytes = stat.availableBlocksLong * stat.blockSizeLong
        val totalBytes = stat.blockCountLong * stat.blockSizeLong

        return DeviceStatus(
            batteryPercentage = batteryPct,
            isCharging = isCharging,
            isWifiConnected = true,
            wifiSsid = wifiSsid,
            freeStorageBytes = freeBytes,
            totalStorageBytes = totalBytes
        )
    }

    private fun getConnectedWifiSsid(): String {
        try {
            val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            val wifiInfo = wm?.connectionInfo
            var ssid = wifiInfo?.ssid
            if (!ssid.isNullOrEmpty() && ssid != "<unknown ssid>") {
                if (ssid.startsWith("\"") && ssid.endsWith("\"") && ssid.length >= 2) {
                    ssid = ssid.substring(1, ssid.length - 1)
                }
                if (ssid.isNotEmpty() && ssid != "<unknown ssid>") {
                    return ssid
                }
            }
        } catch (_: Exception) {}

        try {
            val cm = applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val net = cm?.activeNetwork
                val caps = cm?.getNetworkCapabilities(net)
                if (caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true) {
                    val wifiInfo = caps.transportInfo as? WifiInfo
                    var ssid = wifiInfo?.ssid
                    if (!ssid.isNullOrEmpty() && ssid != "<unknown ssid>") {
                        if (ssid.startsWith("\"") && ssid.endsWith("\"") && ssid.length >= 2) {
                            ssid = ssid.substring(1, ssid.length - 1)
                        }
                        if (ssid.isNotEmpty() && ssid != "<unknown ssid>") {
                            return ssid
                        }
                    }
                }
            }
        } catch (_: Exception) {}

        return "Wi-Fi"
    }

    private fun closeSocketQuietly() {
        currentConnectionState = false
        telemetryJob?.cancel()
        try {
            socket?.close()
        } catch (_: Exception) {}
        socket = null
        outputStream = null
        inputStream = null
    }

    fun disconnect() {
        closeSocketQuietly()
        scope.launch(Dispatchers.Main) {
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
            "Continuity Connection",
            NotificationManager.IMPORTANCE_LOW
        )
        nm.createNotificationChannel(channel)

        val notification = Notification.Builder(this, channelId)
            .setContentTitle("Continuity Companion")
            .setContentText("Ready for local Mac connection")
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .build()

        startForeground(1001, notification)
    }

    override fun onDestroy() {
        super.onDestroy()
        if (activeInstance === this) {
            activeInstance = null
        }
        disconnect()
        scope.cancel()
    }
}
