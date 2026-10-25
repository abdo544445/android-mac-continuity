package com.continuity.ecosystem.core

import java.util.UUID

enum class DevicePlatform {
    PLATFORM_UNSPECIFIED,
    PLATFORM_MACOS,
    PLATFORM_ANDROID
}

enum class DeviceEdition {
    EDITION_PUBLIC,
    EDITION_ADVANCED
}

enum class ThermalState {
    THERMAL_NORMAL,
    THERMAL_FAIR,
    THERMAL_SERIOUS,
    THERMAL_CRITICAL
}

enum class TransferRejectReason {
    REJECT_USER_DECLINED,
    REJECT_INSUFFICIENT_STORAGE,
    REJECT_UNSUPPORTED_TYPE,
    REJECT_RATE_LIMITED,
    REJECT_SECURITY_POLICY
}

enum class ClipboardDataType {
    CLIP_TEXT,
    CLIP_URL,
    CLIP_IMAGE_PNG,
    CLIP_HTML
}

enum class SessionType {
    SESSION_UNKNOWN,
    SESSION_SCREEN_MIRROR,
    SESSION_CAMERA_STREAM,
    SESSION_REMOTE_INPUT,
    SESSION_EXTENDED_DISPLAY
}

enum class StreamingState {
    STATE_IDLE,
    STATE_STARTING,
    STATE_ACTIVE,
    STATE_PAUSED,
    STATE_STOPPED,
    STATE_ERROR
}

enum class InputAction {
    ACTION_DOWN,
    ACTION_UP,
    ACTION_MOVE,
    ACTION_KEY_DOWN,
    ACTION_KEY_UP,
    ACTION_NAV_BACK,
    ACTION_NAV_HOME,
    ACTION_NAV_RECENTS
}

data class PairRequest(
    val deviceId: String,
    val deviceName: String,
    val platform: DevicePlatform = DevicePlatform.PLATFORM_ANDROID,
    val edition: DeviceEdition = DeviceEdition.EDITION_PUBLIC,
    val ephemeralPublicKeyBase64: String,
    val pairingPin: String,
    val identitySignatureBase64: String? = null
)

data class PairConfirm(
    val deviceId: String,
    val deviceName: String,
    val platform: DevicePlatform,
    val ephemeralPublicKeyBase64: String,
    val approved: Boolean,
    val assignedSessionToken: String,
    val authTagBase64: String
)

data class PairStatus(
    val code: Int,
    val message: String
)

data class DeviceHello(
    val protocolVersion: Long = 1,
    val appVersion: String,
    val osVersion: String,
    val deviceModel: String,
    val uptimeSeconds: Long = 0
)

data class CapabilityList(
    val supportsFileTransfer: Boolean = true,
    val supportsClipboard: Boolean = true,
    val supportsNotifications: Boolean = true,
    val supportsRemoteReplies: Boolean = true,
    val supportsScreenMirroring: Boolean = true,
    val supportsCameraStreaming: Boolean = true,
    val supportsRemoteControl: Boolean = false,
    val supportsPhotoBackup: Boolean = true,
    val supportsAdvancedScrcpy: Boolean = false,
    val maxChunkSizeBytes: Long = 524288,
    val supportedVideoCodecs: List<String> = listOf("H264")
)

data class Heartbeat(
    val sequenceNumber: Long,
    val timestampMs: Long = System.currentTimeMillis()
)

data class DeviceStatus(
    val batteryPercentage: Int,
    val isCharging: Boolean,
    val isWifiConnected: Boolean,
    val wifiSsid: String,
    val freeStorageBytes: Long,
    val totalStorageBytes: Long,
    val thermalState: ThermalState = ThermalState.THERMAL_NORMAL
)

data class TransferOffer(
    val transferId: String = UUID.randomUUID().toString(),
    val fileName: String,
    val fileSizeBytes: Long,
    val mimeType: String = "application/octet-stream",
    val sha256Checksum: String,
    val totalChunks: Int,
    val chunkSizeBytes: Long = 524288,
    val isDirectoryBundle: Boolean = false
)

data class TransferAccept(
    val transferId: String,
    val resumeChunkIndex: Int = 0,
    val saveDestinationHint: String? = null
)

data class TransferReject(
    val transferId: String,
    val reason: TransferRejectReason,
    val details: String = ""
)

data class TransferChunk(
    val transferId: String,
    val chunkIndex: Int,
    val dataBase64: String,
    val chunkSha256: String
)

data class TransferComplete(
    val transferId: String,
    val verified: Boolean,
    val finalPathBasename: String,
    val bytesWritten: Long
)

data class TransferCancel(
    val transferId: String,
    val reason: String
)

data class ClipboardOffer(
    val clipId: String = UUID.randomUUID().toString(),
    val dataType: ClipboardDataType = ClipboardDataType.CLIP_TEXT,
    val contentLength: Long,
    val isSensitive: Boolean = false,
    val textPreview: String
)

data class ClipboardPayload(
    val clipId: String,
    val dataBase64: String,
    val mimeType: String = "text/plain"
)

data class NotificationEvent(
    val notificationId: String,
    val packageName: String,
    val appDisplayName: String,
    val appIconPngBase64: String? = null,
    val title: String,
    val text: String,
    val postTimeMs: Long = System.currentTimeMillis(),
    val isClearable: Boolean = true,
    val hasReplyAction: Boolean = false,
    val availableActions: List<String> = emptyList()
)

data class NotificationAction(
    val notificationId: String,
    val actionTitle: String,
    val replyText: String
)

data class SessionRequest(
    val sessionId: String = UUID.randomUUID().toString(),
    val type: SessionType,
    val width: Int = 1920,
    val height: Int = 1080,
    val targetFps: Int = 30,
    val targetBitrateKbps: Int = 4000,
    val codec: String = "H264",
    val cameraLens: String? = null
)

data class SessionStop(
    val sessionId: String,
    val reason: String = "Normal termination"
)

data class SessionState(
    val sessionId: String,
    val state: StreamingState,
    val errorMessage: String? = null
)

data class InputEvent(
    val sessionId: String,
    val action: InputAction,
    val normalizedX: Float = 0f,
    val normalizedY: Float = 0f,
    val keyCode: Int = 0,
    val textInput: String? = null
)

data class ErrorResponse(
    val code: Int,
    val message: String,
    val originalRequestId: String = ""
)

// MARK: - Expanded Ecosystem Payloads

data class HandoffActivity(
    val activityId: String = UUID.randomUUID().toString(),
    val url: String,
    val title: String,
    val sourceApp: String,
    val scrollPosition: Float = 0f
)

data class BiometricChallenge(
    val challengeId: String = UUID.randomUUID().toString(),
    val promptTitle: String,
    val clientNonce: String,
    val timeoutSeconds: Int = 30
)

data class BiometricResponse(
    val challengeId: String,
    val approved: Boolean,
    val signatureBase64: String = "",
    val biometricType: String = "BIOMETRIC_FINGERPRINT"
)

data class SyncFileEntry(
    val path: String,
    val sizeBytes: Long,
    val sha256: String,
    val modifiedTimeMs: Long
)

data class FolderSyncManifest(
    val syncId: String = UUID.randomUUID().toString(),
    val folderName: String,
    val files: List<SyncFileEntry>
)

data class TelephonyEvent(
    val callId: String = UUID.randomUUID().toString(),
    val callerName: String,
    val callerNumber: String,
    val state: String, // "RINGING", "ANSWERED", "DISCONNECTED"
    val isVideo: Boolean = false
)

data class TelephonyAction(
    val callId: String,
    val action: String // "ACCEPT", "REJECT", "MUTE"
)

data class StorageItem(
    val name: String,
    val isDirectory: Boolean,
    val sizeBytes: Long,
    val modifiedTimeMs: Long
)

data class StorageListRequest(
    val requestId: String = UUID.randomUUID().toString(),
    val path: String
)

data class StorageListResponse(
    val requestId: String,
    val path: String,
    val items: List<StorageItem>
)

data class ContinuityEnvelope(
    val version: Long = 1,
    val requestId: String = UUID.randomUUID().toString(),
    val timestampMs: Long = System.currentTimeMillis(),
    val senderDeviceId: String,
    val sessionToken: String? = null,

    // Payloads
    var pairRequest: PairRequest? = null,
    var pairConfirm: PairConfirm? = null,
    var pairStatus: PairStatus? = null,
    var deviceHello: DeviceHello? = null,
    var capabilities: CapabilityList? = null,

    var heartbeat: Heartbeat? = null,
    var deviceStatus: DeviceStatus? = null,

    var transferOffer: TransferOffer? = null,
    var transferAccept: TransferAccept? = null,
    var transferReject: TransferReject? = null,
    var transferChunk: TransferChunk? = null,
    var transferComplete: TransferComplete? = null,
    var transferCancel: TransferCancel? = null,

    var clipboardOffer: ClipboardOffer? = null,
    var clipboardPayload: ClipboardPayload? = null,

    var notificationEvent: NotificationEvent? = null,
    var notificationAction: NotificationAction? = null,

    var sessionRequest: SessionRequest? = null,
    var sessionStop: SessionStop? = null,
    var sessionState: SessionState? = null,
    var inputEvent: InputEvent? = null,

    var errorResponse: ErrorResponse? = null,

    // Expanded Ecosystem Payloads
    var handoffActivity: HandoffActivity? = null,
    var biometricChallenge: BiometricChallenge? = null,
    var biometricResponse: BiometricResponse? = null,
    var folderSyncManifest: FolderSyncManifest? = null,
    var telephonyEvent: TelephonyEvent? = null,
    var telephonyAction: TelephonyAction? = null,
    var storageListRequest: StorageListRequest? = null,
    var storageListResponse: StorageListResponse? = null
)
