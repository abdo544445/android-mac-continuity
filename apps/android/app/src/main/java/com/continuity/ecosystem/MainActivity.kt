package com.continuity.ecosystem

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Bundle
import android.os.IBinder
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.QrCode
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import com.continuity.ecosystem.clipboard.ClipboardSyncManager
import com.continuity.ecosystem.connection.ConnectionService
import com.continuity.ecosystem.core.DeviceIdentity
import com.continuity.ecosystem.files.AndroidTransferItem
import com.continuity.ecosystem.files.FileTransferManager
import com.continuity.ecosystem.mirroring.ScreenShareService
import com.continuity.ecosystem.pairing.PairingManager
import com.continuity.ecosystem.pairing.PairingQrData
import com.continuity.ecosystem.ui.screens.ContinuityWebcamScreen
import com.continuity.ecosystem.ui.screens.HomeScreen
import com.continuity.ecosystem.ui.screens.PairingScreen
import com.continuity.ecosystem.ui.screens.SettingsScreen
import com.continuity.ecosystem.ui.theme.ContinuityTheme

class MainActivity : ComponentActivity() {

    private lateinit var identity: DeviceIdentity
    private lateinit var pairingManager: PairingManager
    private lateinit var transferManager: FileTransferManager
    private lateinit var clipboardManager: ClipboardSyncManager

    private var connectionService: ConnectionService? = null
    private var isBound = false
    private var pendingQrData: PairingQrData? = null

    // Observable Compose UI states bound across service lifecycle
    private var isConnectedState by mutableStateOf(false)
    private var pairedMacNameState by mutableStateOf("")
    private var transfersListState by mutableStateOf<List<AndroidTransferItem>>(emptyList())

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            val binder = service as ConnectionService.LocalBinder
            val svc = binder.getService()
            connectionService = svc
            isBound = true
            isConnectedState = svc.currentConnectionState
            setupServiceListeners(svc)

            // If user had a pending QR scan before service finished binding, connect now
            val pending = pendingQrData
            if (pending != null && !svc.currentConnectionState) {
                val pairReq = pairingManager.createPairRequest(pending)
                svc.connect(
                    targetHost = pending.host,
                    targetPort = pending.port,
                    initialPairRequest = pairReq,
                    onError = { err ->
                        Toast.makeText(this@MainActivity, "Connection error: $err", Toast.LENGTH_LONG).show()
                    }
                )
            } else if (!svc.currentConnectionState) {
                // Auto-reconnect if a Mac was previously paired
                val savedHost = pairingManager.getPairedMacHost()
                val savedPort = pairingManager.getPairedMacPort()
                if (!savedHost.isNullOrEmpty()) {
                    svc.connect(savedHost, savedPort)
                }
            }
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            connectionService = null
            isBound = false
            isConnectedState = false
        }
    }

    private val filePickerLauncher = registerForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri: Uri? ->
        uri?.let { fileUri ->
            connectionService?.let { service ->
                transferManager.sendFile(fileUri, service)
            }
        }
    }

    private val mediaProjectionLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == RESULT_OK && result.data != null) {
            ScreenShareService.resultCode = result.resultCode
            ScreenShareService.resultData = result.data
            startForegroundService(Intent(this, ScreenShareService::class.java))
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        identity = DeviceIdentity(this)
        pairingManager = PairingManager(this, identity)
        transferManager = FileTransferManager(this, identity)
        clipboardManager = ClipboardSyncManager(this)

        // Load actual saved Mac name (empty string "" if no Mac is paired)
        pairedMacNameState = pairingManager.getPairedMacName()
        transfersListState = transferManager.activeTransfers.toList()

        transferManager.onTransfersUpdated = {
            transfersListState = transferManager.activeTransfers.toList()
        }

        val serviceIntent = Intent(this, ConnectionService::class.java)
        startForegroundService(serviceIntent)
        bindService(serviceIntent, connection, Context.BIND_AUTO_CREATE)

        handleIncomingShareIntent(intent)

        setContent {
            ContinuityTheme {
                MainAppScreen()
            }
        }
    }

    private fun setupServiceListeners(service: ConnectionService) {
        service.onConnectionStateChanged = { connected ->
            isConnectedState = connected
        }
        service.onBinaryChunkReceived = { chunk ->
            transferManager.handleIncomingBinaryChunk(chunk)
        }
        service.onEnvelopeReceived = { env ->
            env.pairConfirm?.let { confirm ->
                val qr = pendingQrData
                if (qr != null) {
                    pairingManager.verifyAndSavePairing(confirm, qr)
                } else {
                    pairingManager.savePairedMacInfo(
                        macId = confirm.deviceId,
                        macName = confirm.deviceName,
                        host = service.currentHost,
                        port = service.currentPort,
                        sessionToken = confirm.assignedSessionToken
                    )
                }
                val resolvedName = confirm.deviceName.ifEmpty { qr?.macName ?: "Mac" }
                pairedMacNameState = resolvedName
                isConnectedState = true
                Toast.makeText(this@MainActivity, "Connected to $resolvedName", Toast.LENGTH_SHORT).show()
            }
            env.transferOffer?.let { offer ->
                transferManager.handleIncomingOffer(offer, service)
            }
            env.transferChunk?.let { chunk ->
                transferManager.handleIncomingChunk(chunk)
            }
            env.transferComplete?.let { complete ->
                transferManager.handleIncomingComplete(complete)
            }
            env.clipboardPayload?.let { clip ->
                clipboardManager.handleIncomingClipboard(clip)
            }
        }
    }

    private fun handleIncomingShareIntent(intent: Intent) {
        if (intent.action == Intent.ACTION_SEND) {
            @Suppress("DEPRECATION")
            val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            uri?.let {
                connectionService?.let { service ->
                    transferManager.sendFile(it, service)
                }
            }
        }
    }

    @OptIn(ExperimentalMaterial3Api::class)
    @Composable
    fun MainAppScreen() {
        var selectedTab by remember { mutableIntStateOf(0) }
        var isWebcamActive by remember { mutableStateOf(false) }

        if (isWebcamActive) {
            ContinuityWebcamScreen(
                macName = pairedMacNameState,
                onClose = { isWebcamActive = false }
            )
        } else {
            Scaffold(
                topBar = {
                    TopAppBar(
                        title = { Text("Continuity") }
                    )
                },
                bottomBar = {
                    NavigationBar {
                        NavigationBarItem(
                            selected = selectedTab == 0,
                            onClick = { selectedTab = 0 },
                            icon = { Icon(Icons.Default.Home, contentDescription = "Home") },
                            label = { Text("Home") }
                        )
                        NavigationBarItem(
                            selected = selectedTab == 1,
                            onClick = { selectedTab = 1 },
                            icon = { Icon(Icons.Default.QrCode, contentDescription = "Pairing") },
                            label = { Text("Pairing") }
                        )
                        NavigationBarItem(
                            selected = selectedTab == 2,
                            onClick = { selectedTab = 2 },
                            icon = { Icon(Icons.Default.Settings, contentDescription = "Settings") },
                            label = { Text("Settings") }
                        )
                    }
                }
            ) { paddingValues ->
                Surface(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(paddingValues)
                ) {
                    when (selectedTab) {
                        0 -> HomeScreen(
                            isConnected = isConnectedState,
                            connectedMacName = pairedMacNameState,
                            onSendFileClicked = {
                                filePickerLauncher.launch(arrayOf("*/*"))
                            },
                            onPushClipboardClicked = {
                                connectionService?.let { clipboardManager.sendCurrentClipboard(it) }
                            },
                            onMirrorClicked = {
                                val mpManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                                mediaProjectionLauncher.launch(mpManager.createScreenCaptureIntent())
                            },
                            onCameraClicked = {
                                isWebcamActive = true
                            },
                            transfers = transfersListState
                        )
                        1 -> PairingScreen(
                            onPairWithUri = { uriStr ->
                                val qrData = pairingManager.parseInputOrIp(uriStr)
                                if (qrData != null) {
                                    pendingQrData = qrData
                                    pairedMacNameState = qrData.macName
                                    pairingManager.savePairedMacInfo(
                                        macId = qrData.macId,
                                        macName = qrData.macName,
                                        host = qrData.host,
                                        port = qrData.port,
                                        sessionToken = ""
                                    )
                                    val pairReq = pairingManager.createPairRequest(qrData)
                                    connectionService?.connect(
                                        targetHost = qrData.host,
                                        targetPort = qrData.port,
                                        initialPairRequest = pairReq,
                                        onError = { err ->
                                            Toast.makeText(
                                                this@MainActivity,
                                                "Connection error: $err",
                                                Toast.LENGTH_LONG
                                            ).show()
                                        }
                                    )
                                    selectedTab = 0
                                } else {
                                    Toast.makeText(
                                        this@MainActivity,
                                        "Invalid QR code or IP address",
                                        Toast.LENGTH_SHORT
                                    ).show()
                                }
                            }
                        )
                        2 -> SettingsScreen(
                            pairedMacName = pairedMacNameState,
                            onUnpairClicked = {
                                pendingQrData = null
                                pairingManager.unpair()
                                connectionService?.disconnect()
                                pairedMacNameState = ""
                                isConnectedState = false
                            }
                        )
                    }
                }
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        if (isBound) {
            unbindService(connection)
            isBound = false
        }
    }
}
