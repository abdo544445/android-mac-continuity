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

    var onConnectionStateChanged: ((Boolean) -> Unit)? = null
    var onEnvelopeReceived: ((ContinuityEnvelope) -> Unit)? = null
    var onBinaryChunkReceived: ((RawBinaryChunk) -> Unit)? = null

    inner class LocalBinder : Binder() {
        fun getService(): ConnectionService = this@ConnectionService
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onCreate() {
        super.onCreate()
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
                Log.d("ConnectionService", "Connecting to $targetHost:$targetPort...")

                val sock = try {
                    Socket().apply {
                        tcpNoDelay = true
                        sendBufferSize = 4 * 1024 * 1024
                        receiveBufferSize = 4 * 1024 * 1024
                        connect(InetSocketAddress(targetHost, targetPort), 4000)
                    }
                } catch (primaryErr: Exception) {
                    if (targetHost != "127.0.0.1") {
                        Log.w("ConnectionService", "Primary host $targetHost failed (${primaryErr.message}), trying USB ADB tunnel 127.0.0.1:$targetPort...")
                        Socket().apply {
                            tcpNoDelay = true
                            sendBufferSize = 4 * 1024 * 1024
                            receiveBufferSize = 4 * 1024 * 1024
                            connect(InetSocketAddress("127.0.0.1", targetPort), 2500)
                        }
                    } else {
                        throw primaryErr
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

    private fun readLoop(activeSock: Socket) {
        val ins = inputStream ?: return
        while (currentConnectionState && socket === activeSock && !activeSock.isClosed) {
            try {
                val frame = ProtocolFraming.readFrame(ins)
                if (frame != null) {
                    when (frame) {
                        is DecodedFrame.Envelope -> {
                            frame.envelope.sessionToken?.let { sessionToken = it }
                            scope.launch(Dispatchers.Main) {
                                onEnvelopeReceived?.invoke(frame.envelope)
                            }
                        }
                        is DecodedFrame.BinaryChunk -> {
                            scope.launch(Dispatchers.Main) {
                                onBinaryChunkReceived?.invoke(frame.chunk)
                            }
                        }
                    }
                } else {
                    break
                }
            } catch (e: Exception) {
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
            while (currentConnectionState && isActive) {
                val status = collectDeviceStatus()
                val env = ContinuityEnvelope(
                    senderDeviceId = identity.deviceId,
                    sessionToken = sessionToken,
                    deviceStatus = status
                )
                sendEnvelope(env)
                delay(15000)
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
        disconnect()
        scope.cancel()
    }
}
