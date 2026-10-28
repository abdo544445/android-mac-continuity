package com.continuity.ecosystem

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.media.projection.MediaProjectionManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Bundle
import android.os.IBinder
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.QrCode
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.continuity.ecosystem.clipboard.ClipboardSyncManager
import com.continuity.ecosystem.connection.ConnectionService
import com.continuity.ecosystem.connection.DiscoveredPeer
import com.continuity.ecosystem.connection.LanDiscoveryManager
import com.continuity.ecosystem.core.*
import com.continuity.ecosystem.files.AndroidTransferItem
import com.continuity.ecosystem.files.FileTransferManager
import com.continuity.ecosystem.handoff.HandoffManager
import com.continuity.ecosystem.mirroring.ScreenShareService
import com.continuity.ecosystem.pairing.PairingManager
import com.continuity.ecosystem.pairing.PairingQrData
import com.continuity.ecosystem.security.BiometricAuthManager
import com.continuity.ecosystem.storage.StorageExplorerService
import com.continuity.ecosystem.sync.FolderSyncManager
import com.continuity.ecosystem.telephony.CallRelayService
import com.continuity.ecosystem.ui.screens.ContinuityWebcamScreen
import com.continuity.ecosystem.ui.screens.ExtendedDisplayScreen
import com.continuity.ecosystem.ui.screens.HomeScreen
import com.continuity.ecosystem.ui.screens.PairingScreen
import com.continuity.ecosystem.ui.screens.SettingsScreen
import com.continuity.ecosystem.ui.theme.ContinuityTheme
import java.util.UUID

class MainActivity : ComponentActivity() {

    @Deprecated("Deprecated in Java")
    override fun startActivityForResult(intent: Intent, requestCode: Int) {
        super.startActivityForResult(intent, requestCode and 0xFFFF)
    }

    private lateinit var identity: DeviceIdentity
    private lateinit var pairingManager: PairingManager
    private lateinit var transferManager: FileTransferManager
    private lateinit var clipboardManager: ClipboardSyncManager
    private lateinit var lanDiscoveryManager: LanDiscoveryManager

    private lateinit var handoffManager: HandoffManager
    private lateinit var storageExplorerService: StorageExplorerService
    private lateinit var folderSyncManager: FolderSyncManager
    private lateinit var callRelayService: CallRelayService
    private lateinit var biometricAuthManager: BiometricAuthManager

    private var connectionService: ConnectionService? = null
    private var isBound = false
    private var pendingQrData: PairingQrData? = null

    // Observable Compose UI states bound across service lifecycle
    private var isConnectedState by mutableStateOf(false)
    private var pairedMacNameState by mutableStateOf("")
    private var transfersListState by mutableStateOf<List<AndroidTransferItem>>(emptyList())
    private var discoveredPeersState by mutableStateOf<List<DiscoveredPeer>>(emptyList())
    private var pendingPinConfirmState by mutableStateOf<Pair<DiscoveredPeer, String>?>(null)

    private var isExtendedDisplayActiveState by mutableStateOf(false)
    private var extendedDisplayBitmapState by mutableStateOf<Bitmap?>(null)
    private var isWebcamActiveState by mutableStateOf(false)
    private var activeCameraControlState by mutableStateOf<CameraControlRequest?>(null)

    private var hasAllFilesAccessState by mutableStateOf(false)
    private var hasNotificationListenerState by mutableStateOf(false)
    private var hasCameraPermissionState by mutableStateOf(false)
    private var hasNotificationPermissionState by mutableStateOf(false)

    private val runtimePermissionsLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) {
        updatePermissionStates()
    }

    override fun onResume() {
        super.onResume()
        updatePermissionStates()
    }

    private fun updatePermissionStates() {
        hasAllFilesAccessState = PermissionsManager.hasAllFilesAccess()
        hasNotificationListenerState = PermissionsManager.hasNotificationListenerPermission(this)
        hasCameraPermissionState = PermissionsManager.hasCameraPermission(this)
        hasNotificationPermissionState = PermissionsManager.hasNotificationPermission(this)
    }

    private fun requestAllPermissions() {
        val needed = PermissionsManager.getRequiredRuntimePermissions().filter {
            androidx.core.content.ContextCompat.checkSelfPermission(this, it) != android.content.pm.PackageManager.PERMISSION_GRANTED
        }.toTypedArray()

        if (needed.isNotEmpty()) {
            runtimePermissionsLauncher.launch(needed)
        }
    }

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
        lanDiscoveryManager = LanDiscoveryManager(this, identity)

        handoffManager = HandoffManager(this)
        storageExplorerService = StorageExplorerService(this)
        folderSyncManager = FolderSyncManager(this)
        callRelayService = CallRelayService(this)
        biometricAuthManager = BiometricAuthManager(this)
        biometricAuthManager.attachActivity(this)

        lanDiscoveryManager.onPeersUpdated = { peers ->
            discoveredPeersState = peers
            val pairedId = pairingManager.getPairedMacId()
            val pairedName = pairingManager.getPairedMacName()
            if (!isConnectedState && (!pairedId.isNullOrEmpty() || pairedName.isNotBlank())) {
                val matchingMac = peers.firstOrNull { 
                    (!pairedId.isNullOrEmpty() && it.deviceId == pairedId) || 
                    (pairedName.isNotBlank() && it.deviceName == pairedName) 
                }
                if (matchingMac != null) {
                    pairingManager.savePairedMacInfo(
                        macId = matchingMac.deviceId,
                        macName = matchingMac.deviceName,
                        host = matchingMac.ip,
                        port = matchingMac.tcpPort,
                        sessionToken = pairingManager.getPairedMacToken() ?: ""
                    )
                    connectionService?.connect(matchingMac.ip, matchingMac.tcpPort)
                }
            }
        }
        lanDiscoveryManager.onPairInviteReceived = { peer, pin ->
            startBluetoothStylePairing(peer, customPin = pin)
        }
        lanDiscoveryManager.start()

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
        updatePermissionStates()
        requestAllPermissions()

        setContent {
            ContinuityTheme {
                MainAppScreen()
            }
        }
    }

    private fun setupServiceListeners(service: ConnectionService) {
        callRelayService.startListening(service)

        service.onConnectionStateChanged = { connected ->
            isConnectedState = connected
        }
        service.onBinaryChunkReceived = { chunk ->
            if (chunk.transferId == "00000000-0000-0000-0000-00EXT_DISPLAY") {
                val bmp = BitmapFactory.decodeByteArray(chunk.data, 0, chunk.data.size)
                if (bmp != null) {
                    extendedDisplayBitmapState = bmp
                    if (!isExtendedDisplayActiveState) {
                        isExtendedDisplayActiveState = true
                    }
                }
            } else {
                transferManager.handleIncomingBinaryChunk(chunk)
            }
        }
        service.onEnvelopeReceived = { env ->
            env.pairConfirm?.let { confirm ->
                if (!confirm.approved) {
                    pendingPinConfirmState = null
                    pendingQrData = null
                    isConnectedState = false
                    Toast.makeText(this@MainActivity, "Pairing declined", Toast.LENGTH_SHORT).show()
                    return@let
                }
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
                pendingPinConfirmState = null
                isConnectedState = true
                Toast.makeText(this@MainActivity, "Paired & Connected to $resolvedName", Toast.LENGTH_SHORT).show()
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
            env.handoffActivity?.let { activity ->
                handoffManager.handleIncomingHandoff(activity)
            }
            env.biometricChallenge?.let { challenge ->
                biometricAuthManager.handleBiometricChallenge(challenge, service)
            }
            env.folderSyncManifest?.let { manifest ->
                folderSyncManager.handleIncomingManifest(manifest, service)
            }
            env.telephonyAction?.let { action ->
                callRelayService.handleTelephonyAction(action)
            }
            env.storageListRequest?.let { req ->
                storageExplorerService.handleStorageListRequest(req, service)
            }
            env.inputEvent?.let { input ->
                input.textInput?.let { txt ->
                    if (txt.isNotEmpty()) {
                        clipboardManager.copyText(txt)
                    }
                }
                when (input.action) {
                    InputAction.ACTION_NAV_BACK -> {
                        runOnUiThread { onBackPressedDispatcher.onBackPressed() }
                    }
                    InputAction.ACTION_NAV_HOME -> {
                        try {
                            val homeIntent = Intent(Intent.ACTION_MAIN).apply {
                                addCategory(Intent.CATEGORY_HOME)
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            startActivity(homeIntent)
                        } catch (_: Exception) {}
                    }
                    else -> {}
                }
            }
            env.sessionRequest?.let { req ->
                if (req.type == SessionType.SESSION_SCREEN_MIRROR) {
                    val mpManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                    mediaProjectionLauncher.launch(mpManager.createScreenCaptureIntent())
                } else if (req.type == SessionType.SESSION_EXTENDED_DISPLAY) {
                    isExtendedDisplayActiveState = true
                } else if (req.type == SessionType.SESSION_CAMERA_STREAM) {
                    isWebcamActiveState = true
                }
            }
            env.cameraControl?.let { ctrl ->
                activeCameraControlState = ctrl
            }
            env.sessionStop?.let { stop ->
                if (isExtendedDisplayActiveState) {
                    isExtendedDisplayActiveState = false
                    extendedDisplayBitmapState = null
                }
                if (isWebcamActiveState && stop.sessionId == "camera") {
                    isWebcamActiveState = false
                }
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

    private fun startBluetoothStylePairing(peer: DiscoveredPeer, customPin: String? = null) {
        val pin = customPin ?: String.format("%06d", (100000..999999).random())
        val qrData = PairingQrData(
            macId = peer.deviceId,
            macName = peer.deviceName,
            host = peer.ip,
            port = peer.tcpPort,
            publicKeyBase64 = peer.publicKeyBase64.ifEmpty { identity.getPublicKeyBase64() },
            pin = pin,
            expiresAt = System.currentTimeMillis() / 1000 + 300
        )
        pendingQrData = qrData
        pendingPinConfirmState = peer to pin

        val pairReq = pairingManager.createPairRequest(qrData)
        connectionService?.connect(
            targetHost = peer.ip,
            targetPort = peer.tcpPort,
            initialPairRequest = pairReq,
            onError = { err ->
                pendingPinConfirmState = null
                Toast.makeText(this@MainActivity, "Connection error: $err", Toast.LENGTH_LONG).show()
            }
        )
    }

    private fun confirmPendingPinPairing() {
        val (peer, _) = pendingPinConfirmState ?: return
        val sessionTok = "tok_${UUID.randomUUID()}"
        pairingManager.savePairedMacInfo(
            macId = peer.deviceId,
            macName = peer.deviceName,
            host = peer.ip,
            port = peer.tcpPort,
            sessionToken = sessionTok
        )
        pairedMacNameState = peer.deviceName
        isConnectedState = true
        pendingPinConfirmState = null

        val confirmMsg = PairConfirm(
            deviceId = identity.deviceId,
            deviceName = identity.deviceName,
            platform = DevicePlatform.PLATFORM_ANDROID,
            ephemeralPublicKeyBase64 = identity.getPublicKeyBase64(),
            approved = true,
            assignedSessionToken = sessionTok,
            authTagBase64 = ""
        )
        connectionService?.sendEnvelope(
            ContinuityEnvelope(
                senderDeviceId = identity.deviceId,
                sessionToken = sessionTok,
                pairConfirm = confirmMsg
            )
        )
        Toast.makeText(this@MainActivity, "Paired & Connected to ${peer.deviceName}", Toast.LENGTH_SHORT).show()
    }

    private fun declinePendingPinPairing() {
        val confirmMsg = PairConfirm(
            deviceId = identity.deviceId,
            deviceName = identity.deviceName,
            platform = DevicePlatform.PLATFORM_ANDROID,
            ephemeralPublicKeyBase64 = identity.getPublicKeyBase64(),
            approved = false,
            assignedSessionToken = "",
            authTagBase64 = ""
        )
        connectionService?.sendEnvelope(
            ContinuityEnvelope(
                senderDeviceId = identity.deviceId,
                pairConfirm = confirmMsg
            )
        )
        pendingPinConfirmState = null
        pendingQrData = null
        connectionService?.disconnect()
    }

    @OptIn(ExperimentalMaterial3Api::class)
    @Composable
    fun MainAppScreen() {
        var selectedTab by remember { mutableIntStateOf(0) }

        pendingPinConfirmState?.let { (peer, pin) ->
            val formattedPin = if (pin.length == 6) "${pin.substring(0, 3)} ${pin.substring(3, 6)}" else pin
            AlertDialog(
                onDismissRequest = { declinePendingPinPairing() },
                title = {
                    Text(
                        text = "Bluetooth-Style Pairing",
                        fontWeight = FontWeight.Bold
                    )
                },
                text = {
                    Column(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        Text(
                            text = "Confirm that this 6-digit PIN matches the code shown on ${peer.deviceName}:",
                            textAlign = TextAlign.Center,
                            fontSize = 14.sp
                        )
                        Surface(
                            color = MaterialTheme.colorScheme.primaryContainer,
                            shape = RoundedCornerShape(12.dp)
                        ) {
                            Text(
                                text = formattedPin,
                                fontSize = 32.sp,
                                fontWeight = FontWeight.ExtraBold,
                                fontFamily = FontFamily.Monospace,
                                color = MaterialTheme.colorScheme.onPrimaryContainer,
                                modifier = Modifier.padding(horizontal = 24.dp, vertical = 12.dp)
                            )
                        }
                        Text(
                            text = "You can accept & confirm from either this Android device or your Mac.",
                            textAlign = TextAlign.Center,
                            fontSize = 12.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                },
                confirmButton = {
                    Button(onClick = { confirmPendingPinPairing() }) {
                        Text("Accept & Pair")
                    }
                },
                dismissButton = {
                    OutlinedButton(onClick = { declinePendingPinPairing() }) {
                        Text("Decline")
                    }
                }
            )
        }

        if (isExtendedDisplayActiveState) {
            ExtendedDisplayScreen(
                currentFrameBitmap = extendedDisplayBitmapState,
                connectionService = connectionService,
                onExit = {
                    isExtendedDisplayActiveState = false
                    extendedDisplayBitmapState = null
                    connectionService?.sendEnvelope(
                        ContinuityEnvelope(
                            senderDeviceId = identity.deviceId,
                            sessionStop = SessionStop(sessionId = "ext_display")
                        )
                    )
                }
            )
        } else if (isWebcamActiveState) {
            ContinuityWebcamScreen(
                macName = pairedMacNameState,
                remoteCameraControl = activeCameraControlState,
                onClose = { isWebcamActiveState = false }
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
                            discoveredPeers = discoveredPeersState,
                            onPairPeerClicked = { peer ->
                                startBluetoothStylePairing(peer)
                            },
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
                                isWebcamActiveState = true
                            },
                            onExtendedDisplayClicked = {
                                isExtendedDisplayActiveState = true
                                connectionService?.sendEnvelope(
                                    ContinuityEnvelope(
                                        senderDeviceId = identity.deviceId,
                                        sessionRequest = SessionRequest(sessionId = "ext_display", type = SessionType.SESSION_EXTENDED_DISPLAY)
                                    )
                                )
                            },
                            onFolderSyncClicked = {
                                connectionService?.let { svc ->
                                    val manifest = folderSyncManager.generateManifest()
                                    svc.sendEnvelope(
                                        ContinuityEnvelope(
                                            senderDeviceId = identity.deviceId,
                                            folderSyncManifest = manifest
                                        )
                                    )
                                    Toast.makeText(this@MainActivity, "Folder sync initiated", Toast.LENGTH_SHORT).show()
                                }
                            },
                            transfers = transfersListState,
                            hasAllFilesAccess = hasAllFilesAccessState,
                            hasNotificationListener = hasNotificationListenerState,
                            hasCameraPermission = hasCameraPermissionState,
                            onRequestAllFilesAccess = {
                                startActivity(PermissionsManager.createAllFilesAccessIntent(this@MainActivity))
                            },
                            onRequestNotificationListener = {
                                startActivity(PermissionsManager.createNotificationListenerSettingsIntent())
                            },
                            onRequestRuntimePermissions = {
                                requestAllPermissions()
                            }
                        )
                        1 -> PairingScreen(
                            discoveredPeers = discoveredPeersState,
                            onPairPeerClicked = { peer ->
                                startBluetoothStylePairing(peer)
                            },
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
                            },
                            hasAllFilesAccess = hasAllFilesAccessState,
                            hasNotificationListener = hasNotificationListenerState,
                            hasCameraPermission = hasCameraPermissionState,
                            hasNotificationPermission = hasNotificationPermissionState,
                            onRequestAllFilesAccess = {
                                startActivity(PermissionsManager.createAllFilesAccessIntent(this@MainActivity))
                            },
                            onRequestNotificationListener = {
                                startActivity(PermissionsManager.createNotificationListenerSettingsIntent())
                            },
                            onRequestRuntimePermissions = {
                                requestAllPermissions()
                            }
                        )
                    }
                }
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        if (::biometricAuthManager.isInitialized) {
            biometricAuthManager.detachActivity()
        }
        if (::lanDiscoveryManager.isInitialized) {
            lanDiscoveryManager.stop()
        }
        if (isBound) {
            unbindService(connection)
            isBound = false
        }
    }
}
