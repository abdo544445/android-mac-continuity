package com.continuity.ecosystem

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.net.Uri
import android.os.Bundle
import android.os.IBinder
import android.media.projection.MediaProjectionManager
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
import com.continuity.ecosystem.files.FileTransferManager
import com.continuity.ecosystem.pairing.PairingManager
import com.continuity.ecosystem.mirroring.ScreenShareService
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

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            val binder = service as ConnectionService.LocalBinder
            connectionService = binder.getService()
            isBound = true
            setupServiceListeners()
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            connectionService = null
            isBound = false
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

    private fun setupServiceListeners() {
        val service = connectionService ?: return
        service.onBinaryChunkReceived = { chunk ->
            transferManager.handleIncomingBinaryChunk(chunk)
        }
        service.onEnvelopeReceived = { env ->
            env.pairConfirm?.let { confirm ->
                // Handled in pairing
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
        var isConnected by remember { mutableStateOf(false) }
        var pairedMacName by remember { mutableStateOf("MacBook Pro") }
        var transfersList by remember { mutableStateOf(transferManager.activeTransfers.toList()) }
        var isWebcamActive by remember { mutableStateOf(false) }

        transferManager.onTransfersUpdated = {
            transfersList = transferManager.activeTransfers.toList()
        }

        connectionService?.onConnectionStateChanged = { connected ->
            isConnected = connected
        }

        if (isWebcamActive) {
            ContinuityWebcamScreen(
                macName = pairedMacName,
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
                            isConnected = isConnected,
                            connectedMacName = pairedMacName,
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
                            transfers = transfersList
                        )
                    1 -> PairingScreen(
                        onPairWithUri = { uriStr ->
                            val qrData = pairingManager.parseQrCode(uriStr)
                            if (qrData != null) {
                                pairedMacName = qrData.macName
                                connectionService?.connect(qrData.host, qrData.port)
                                val pairReq = pairingManager.createPairRequest(qrData)
                                connectionService?.sendEnvelope(
                                    com.continuity.ecosystem.core.ContinuityEnvelope(
                                        senderDeviceId = identity.deviceId,
                                        pairRequest = pairReq
                                    )
                                )
                                selectedTab = 0
                            }
                        }
                    )
                    2 -> SettingsScreen(
                        pairedMacName = pairedMacName,
                        onUnpairClicked = {
                            pairingManager.unpair()
                            connectionService?.disconnect()
                            pairedMacName = ""
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
