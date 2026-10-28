package com.continuity.ecosystem.core

import com.google.gson.annotations.SerializedName
import java.util.UUID

enum class DevicePlatform {
    @SerializedName("PLATFORM_UNSPECIFIED", alternate = ["0", "UNSPECIFIED"])
    PLATFORM_UNSPECIFIED,
    @SerializedName("PLATFORM_MACOS", alternate = ["1", "MACOS"])
    PLATFORM_MACOS,
    @SerializedName("PLATFORM_ANDROID", alternate = ["2", "ANDROID"])
    PLATFORM_ANDROID
}

enum class DeviceEdition {
    @SerializedName("EDITION_PUBLIC", alternate = ["0", "PUBLIC"])
    EDITION_PUBLIC,
    @SerializedName("EDITION_ADVANCED", alternate = ["1", "ADVANCED"])
    EDITION_ADVANCED
}

enum class ThermalState {
    @SerializedName("THERMAL_NORMAL")
    THERMAL_NORMAL,
    @SerializedName("THERMAL_FAIR")
    THERMAL_FAIR,
    @SerializedName("THERMAL_SERIOUS")
    THERMAL_SERIOUS,
    @SerializedName("THERMAL_CRITICAL")
    THERMAL_CRITICAL
}

enum class TransferRejectReason {
    @SerializedName("REJECT_USER_DECLINED")
    REJECT_USER_DECLINED,
    @SerializedName("REJECT_INSUFFICIENT_STORAGE")
    REJECT_INSUFFICIENT_STORAGE,
    @SerializedName("REJECT_UNSUPPORTED_TYPE")
    REJECT_UNSUPPORTED_TYPE,
    @SerializedName("REJECT_RATE_LIMITED")
    REJECT_RATE_LIMITED,
    @SerializedName("REJECT_SECURITY_POLICY")
    REJECT_SECURITY_POLICY
}

enum class ClipboardDataType {
    @SerializedName("CLIP_TEXT")
    CLIP_TEXT,
    @SerializedName("CLIP_URL")
    CLIP_URL,
    @SerializedName("CLIP_IMAGE_PNG")
    CLIP_IMAGE_PNG,
    @SerializedName("CLIP_HTML")
    CLIP_HTML
}

enum class SessionType {
    @SerializedName("SESSION_UNKNOWN")
    SESSION_UNKNOWN,
    @SerializedName("SESSION_SCREEN_MIRROR")
    SESSION_SCREEN_MIRROR,
    @SerializedName("SESSION_CAMERA_STREAM")
    SESSION_CAMERA_STREAM,
    @SerializedName("SESSION_REMOTE_INPUT")
    SESSION_REMOTE_INPUT,
    @SerializedName("SESSION_EXTENDED_DISPLAY")
    SESSION_EXTENDED_DISPLAY
}

enum class StreamingState {
    @SerializedName("STATE_IDLE")
    STATE_IDLE,
    @SerializedName("STATE_STARTING")
    STATE_STARTING,
    @SerializedName("STATE_ACTIVE")
    STATE_ACTIVE,
    @SerializedName("STATE_PAUSED")
    STATE_PAUSED,
    @SerializedName("STATE_STOPPED")
    STATE_STOPPED,
    @SerializedName("STATE_ERROR")
    STATE_ERROR
}

enum class InputAction {
    @SerializedName("ACTION_DOWN")
    ACTION_DOWN,
    @SerializedName("ACTION_UP")
    ACTION_UP,
    @SerializedName("ACTION_MOVE")
    ACTION_MOVE,
    @SerializedName("ACTION_KEY_DOWN")
    ACTION_KEY_DOWN,
    @SerializedName("ACTION_KEY_UP")
    ACTION_KEY_UP,
    @SerializedName("ACTION_NAV_BACK")
    ACTION_NAV_BACK,
    @SerializedName("ACTION_NAV_HOME")
    ACTION_NAV_HOME,
    @SerializedName("ACTION_NAV_RECENTS")
    ACTION_NAV_RECENTS
}

data class PairRequest(
    @SerializedName("deviceId", alternate = ["device_id"])
    val deviceId: String,
    @SerializedName("deviceName", alternate = ["device_name"])
    val deviceName: String,
    @SerializedName("platform")
    val platform: DevicePlatform = DevicePlatform.PLATFORM_ANDROID,
    @SerializedName("edition")
    val edition: DeviceEdition = DeviceEdition.EDITION_PUBLIC,
    @SerializedName("ephemeralPublicKeyBase64", alternate = ["ephemeral_public_key_base64", "ephemeral_public_key"])
    val ephemeralPublicKeyBase64: String = "",
    @SerializedName("pairingPin", alternate = ["pairing_pin"])
    val pairingPin: String,
    @SerializedName("identitySignatureBase64", alternate = ["identity_signature_base64", "identity_signature"])
    val identitySignatureBase64: String? = null
)

data class PairConfirm(
    @SerializedName("deviceId", alternate = ["device_id"])
    val deviceId: String,
    @SerializedName("deviceName", alternate = ["device_name"])
    val deviceName: String,
    @SerializedName("platform")
    val platform: DevicePlatform,
    @SerializedName("ephemeralPublicKeyBase64", alternate = ["ephemeral_public_key_base64", "ephemeral_public_key"])
    val ephemeralPublicKeyBase64: String = "",
    @SerializedName("approved")
    val approved: Boolean,
    @SerializedName("assignedSessionToken", alternate = ["assigned_session_token"])
    val assignedSessionToken: String,
    @SerializedName("authTagBase64", alternate = ["auth_tag_base64", "auth_tag"])
    val authTagBase64: String
)

data class PairStatus(
    @SerializedName("code")
    val code: Int,
    @SerializedName("message")
    val message: String
)

data class DeviceHello(
    @SerializedName("protocolVersion", alternate = ["protocol_version"])
    val protocolVersion: Long = 1,
    @SerializedName("appVersion", alternate = ["app_version"])
    val appVersion: String,
    @SerializedName("osVersion", alternate = ["os_version"])
    val osVersion: String,
    @SerializedName("deviceModel", alternate = ["device_model"])
    val deviceModel: String,
    @SerializedName("uptimeSeconds", alternate = ["uptime_seconds"])
    val uptimeSeconds: Long = 0
)

data class CapabilityList(
    @SerializedName("supportsFileTransfer", alternate = ["supports_file_transfer"])
    val supportsFileTransfer: Boolean = true,
    @SerializedName("supportsClipboard", alternate = ["supports_clipboard"])
    val supportsClipboard: Boolean = true,
    @SerializedName("supportsNotifications", alternate = ["supports_notifications"])
    val supportsNotifications: Boolean = true,
    @SerializedName("supportsRemoteReplies", alternate = ["supports_remote_replies"])
    val supportsRemoteReplies: Boolean = true,
    @SerializedName("supportsScreenMirroring", alternate = ["supports_screen_mirroring"])
    val supportsScreenMirroring: Boolean = true,
    @SerializedName("supportsCameraStreaming", alternate = ["supports_camera_streaming"])
    val supportsCameraStreaming: Boolean = true,
    @SerializedName("supportsRemoteControl", alternate = ["supports_remote_control"])
    val supportsRemoteControl: Boolean = false,
    @SerializedName("supportsPhotoBackup", alternate = ["supports_photo_backup"])
    val supportsPhotoBackup: Boolean = true,
    @SerializedName("supportsAdvancedScrcpy", alternate = ["supports_advanced_scrcpy"])
    val supportsAdvancedScrcpy: Boolean = false,
    @SerializedName("maxChunkSizeBytes", alternate = ["max_chunk_size_bytes"])
    val maxChunkSizeBytes: Long = 524288,
    @SerializedName("supportedVideoCodecs", alternate = ["supported_video_codecs"])
    val supportedVideoCodecs: List<String> = listOf("H264")
)

data class Heartbeat(
    @SerializedName("sequenceNumber", alternate = ["sequence_number"])
    val sequenceNumber: Long,
    @SerializedName("timestampMs", alternate = ["timestamp_ms"])
    val timestampMs: Long = System.currentTimeMillis()
)

data class DeviceStatus(
    @SerializedName("batteryPercentage", alternate = ["battery_percentage"])
    val batteryPercentage: Int,
    @SerializedName("isCharging", alternate = ["is_charging"])
    val isCharging: Boolean,
    @SerializedName("isWifiConnected", alternate = ["is_wifi_connected"])
    val isWifiConnected: Boolean,
    @SerializedName("wifiSsid", alternate = ["wifi_ssid"])
    val wifiSsid: String,
    @SerializedName("freeStorageBytes", alternate = ["free_storage_bytes"])
    val freeStorageBytes: Long,
    @SerializedName("totalStorageBytes", alternate = ["total_storage_bytes"])
    val totalStorageBytes: Long,
    @SerializedName("thermalState", alternate = ["thermal_state"])
    val thermalState: ThermalState = ThermalState.THERMAL_NORMAL
)

data class TransferOffer(
    @SerializedName("transferId", alternate = ["transfer_id"])
    val transferId: String = UUID.randomUUID().toString(),
    @SerializedName("fileName", alternate = ["file_name"])
    val fileName: String,
    @SerializedName("fileSizeBytes", alternate = ["file_size_bytes"])
    val fileSizeBytes: Long,
    @SerializedName("mimeType", alternate = ["mime_type"])
    val mimeType: String = "application/octet-stream",
    @SerializedName("sha256Checksum", alternate = ["sha256_checksum"])
    val sha256Checksum: String,
    @SerializedName("totalChunks", alternate = ["total_chunks"])
    val totalChunks: Int,
    @SerializedName("chunkSizeBytes", alternate = ["chunk_size_bytes"])
    val chunkSizeBytes: Long = 524288,
    @SerializedName("isDirectoryBundle", alternate = ["is_directory_bundle"])
    val isDirectoryBundle: Boolean = false
)

data class TransferAccept(
    @SerializedName("transferId", alternate = ["transfer_id"])
    val transferId: String,
    @SerializedName("resumeChunkIndex", alternate = ["resume_chunk_index"])
    val resumeChunkIndex: Int = 0,
    @SerializedName("saveDestinationHint", alternate = ["save_destination_hint"])
    val saveDestinationHint: String? = null
)

data class TransferReject(
    @SerializedName("transferId", alternate = ["transfer_id"])
    val transferId: String,
    @SerializedName("reason")
    val reason: TransferRejectReason,
    @SerializedName("details")
    val details: String = ""
)

data class TransferChunk(
    @SerializedName("transferId", alternate = ["transfer_id"])
    val transferId: String,
    @SerializedName("chunkIndex", alternate = ["chunk_index"])
    val chunkIndex: Int,
    @SerializedName("dataBase64", alternate = ["data_base64", "data"])
    val dataBase64: String,
    @SerializedName("chunkSha256", alternate = ["chunk_sha256"])
    val chunkSha256: String
)

data class TransferComplete(
    @SerializedName("transferId", alternate = ["transfer_id"])
    val transferId: String,
    @SerializedName("verified")
    val verified: Boolean,
    @SerializedName("finalPathBasename", alternate = ["final_path_basename"])
    val finalPathBasename: String,
    @SerializedName("bytesWritten", alternate = ["bytes_written"])
    val bytesWritten: Long
)

data class TransferCancel(
    @SerializedName("transferId", alternate = ["transfer_id"])
    val transferId: String,
    @SerializedName("reason")
    val reason: String
)

data class ClipboardOffer(
    @SerializedName("clipId", alternate = ["clip_id"])
    val clipId: String = UUID.randomUUID().toString(),
    @SerializedName("dataType", alternate = ["data_type"])
    val dataType: ClipboardDataType = ClipboardDataType.CLIP_TEXT,
    @SerializedName("contentLength", alternate = ["content_length"])
    val contentLength: Long,
    @SerializedName("isSensitive", alternate = ["is_sensitive"])
    val isSensitive: Boolean = false,
    @SerializedName("textPreview", alternate = ["text_preview"])
    val textPreview: String
)

data class ClipboardPayload(
    @SerializedName("clipId", alternate = ["clip_id"])
    val clipId: String,
    @SerializedName("dataBase64", alternate = ["data_base64", "data"])
    val dataBase64: String,
    @SerializedName("mimeType", alternate = ["mime_type"])
    val mimeType: String = "text/plain"
)

data class NotificationEvent(
    @SerializedName("notificationId", alternate = ["notification_id"])
    val notificationId: String,
    @SerializedName("packageName", alternate = ["package_name"])
    val packageName: String,
    @SerializedName("appDisplayName", alternate = ["app_display_name"])
    val appDisplayName: String,
    @SerializedName("appIconPngBase64", alternate = ["app_icon_png_base64", "app_icon_png"])
    val appIconPngBase64: String? = null,
    @SerializedName("title")
    val title: String,
    @SerializedName("text")
    val text: String,
    @SerializedName("postTimeMs", alternate = ["post_time_ms"])
    val postTimeMs: Long = System.currentTimeMillis(),
    @SerializedName("isClearable", alternate = ["is_clearable"])
    val isClearable: Boolean = true,
    @SerializedName("hasReplyAction", alternate = ["has_reply_action"])
    val hasReplyAction: Boolean = false,
    @SerializedName("availableActions", alternate = ["available_actions"])
    val availableActions: List<String> = emptyList()
)

data class NotificationAction(
    @SerializedName("notificationId", alternate = ["notification_id"])
    val notificationId: String,
    @SerializedName("actionTitle", alternate = ["action_title"])
    val actionTitle: String,
    @SerializedName("replyText", alternate = ["reply_text"])
    val replyText: String
)

data class SessionRequest(
    @SerializedName("sessionId", alternate = ["session_id"])
    val sessionId: String = UUID.randomUUID().toString(),
    @SerializedName("type")
    val type: SessionType,
    @SerializedName("width")
    val width: Int = 1920,
    @SerializedName("height")
    val height: Int = 1080,
    @SerializedName("targetFps", alternate = ["target_fps"])
    val targetFps: Int = 30,
    @SerializedName("targetBitrateKbps", alternate = ["target_bitrate_kbps"])
    val targetBitrateKbps: Int = 4000,
    @SerializedName("codec")
    val codec: String = "H264",
    @SerializedName("cameraLens", alternate = ["camera_lens"])
    val cameraLens: String? = null
)

data class SessionStop(
    @SerializedName("sessionId", alternate = ["session_id"])
    val sessionId: String,
    @SerializedName("reason")
    val reason: String = "Normal termination"
)

data class SessionState(
    @SerializedName("sessionId", alternate = ["session_id"])
    val sessionId: String,
    @SerializedName("state")
    val state: StreamingState,
    @SerializedName("errorMessage", alternate = ["error_message"])
    val errorMessage: String? = null
)

data class InputEvent(
    @SerializedName("sessionId", alternate = ["session_id"])
    val sessionId: String,
    @SerializedName("action")
    val action: InputAction,
    @SerializedName("normalizedX", alternate = ["normalized_x"])
    val normalizedX: Float = 0f,
    @SerializedName("normalizedY", alternate = ["normalized_y"])
    val normalizedY: Float = 0f,
    @SerializedName("keyCode", alternate = ["key_code"])
    val keyCode: Int = 0,
    @SerializedName("textInput", alternate = ["text_input"])
    val textInput: String? = null
)

data class ErrorResponse(
    @SerializedName("code")
    val code: Int,
    @SerializedName("message")
    val message: String,
    @SerializedName("originalRequestId", alternate = ["original_request_id"])
    val originalRequestId: String = ""
)

// MARK: - Expanded Ecosystem Payloads

data class HandoffActivity(
    @SerializedName("activityId", alternate = ["activity_id"])
    val activityId: String = UUID.randomUUID().toString(),
    @SerializedName("url")
    val url: String,
    @SerializedName("title")
    val title: String,
    @SerializedName("sourceApp", alternate = ["source_app"])
    val sourceApp: String,
    @SerializedName("scrollPosition", alternate = ["scroll_position"])
    val scrollPosition: Float = 0f
)

data class BiometricChallenge(
    @SerializedName("challengeId", alternate = ["challenge_id"])
    val challengeId: String = UUID.randomUUID().toString(),
    @SerializedName("promptTitle", alternate = ["prompt_title"])
    val promptTitle: String,
    @SerializedName("clientNonce", alternate = ["client_nonce"])
    val clientNonce: String,
    @SerializedName("timeoutSeconds", alternate = ["timeout_seconds"])
    val timeoutSeconds: Int = 30
)

data class BiometricResponse(
    @SerializedName("challengeId", alternate = ["challenge_id"])
    val challengeId: String,
    @SerializedName("approved")
    val approved: Boolean,
    @SerializedName("signatureBase64", alternate = ["signature_base64"])
    val signatureBase64: String = "",
    @SerializedName("biometricType", alternate = ["biometric_type"])
    val biometricType: String = "BIOMETRIC_FINGERPRINT"
)

data class SyncFileEntry(
    @SerializedName("path")
    val path: String,
    @SerializedName("sizeBytes", alternate = ["size_bytes"])
    val sizeBytes: Long,
    @SerializedName("sha256")
    val sha256: String,
    @SerializedName("modifiedTimeMs", alternate = ["modified_time_ms"])
    val modifiedTimeMs: Long
)

data class FolderSyncManifest(
    @SerializedName("syncId", alternate = ["sync_id"])
    val syncId: String = UUID.randomUUID().toString(),
    @SerializedName("folderName", alternate = ["folder_name"])
    val folderName: String,
    @SerializedName("files")
    val files: List<SyncFileEntry>
)

data class TelephonyEvent(
    @SerializedName("callId", alternate = ["call_id"])
    val callId: String = UUID.randomUUID().toString(),
    @SerializedName("callerName", alternate = ["caller_name"])
    val callerName: String,
    @SerializedName("callerNumber", alternate = ["caller_number"])
    val callerNumber: String,
    @SerializedName("state")
    val state: String,
    @SerializedName("isVideo", alternate = ["is_video"])
    val isVideo: Boolean = false
)

data class TelephonyAction(
    @SerializedName("callId", alternate = ["call_id"])
    val callId: String,
    @SerializedName("action")
    val action: String
)

data class StorageItem(
    @SerializedName("name")
    val name: String,
    @SerializedName("isDirectory", alternate = ["is_directory"])
    val isDirectory: Boolean,
    @SerializedName("sizeBytes", alternate = ["size_bytes"])
    val sizeBytes: Long,
    @SerializedName("modifiedTimeMs", alternate = ["modified_time_ms"])
    val modifiedTimeMs: Long
)

data class StorageListRequest(
    @SerializedName("requestId", alternate = ["request_id"])
    val requestId: String = UUID.randomUUID().toString(),
    @SerializedName("path")
    val path: String
)

data class StorageListResponse(
    @SerializedName("requestId", alternate = ["request_id"])
    val requestId: String,
    @SerializedName("path")
    val path: String,
    @SerializedName("items")
    val items: List<StorageItem>
)

data class ContinuityEnvelope(
    @SerializedName("version")
    val version: Long = 1,
    @SerializedName("requestId", alternate = ["request_id"])
    val requestId: String = UUID.randomUUID().toString(),
    @SerializedName("timestampMs", alternate = ["timestamp_ms"])
    val timestampMs: Long = System.currentTimeMillis(),
    @SerializedName("senderDeviceId", alternate = ["sender_device_id"])
    val senderDeviceId: String,
    @SerializedName("sessionToken", alternate = ["session_token"])
    val sessionToken: String? = null,

    // Payloads
    @SerializedName("pairRequest", alternate = ["pair_request"])
    var pairRequest: PairRequest? = null,
    @SerializedName("pairConfirm", alternate = ["pair_confirm"])
    var pairConfirm: PairConfirm? = null,
    @SerializedName("pairStatus", alternate = ["pair_status"])
    var pairStatus: PairStatus? = null,
    @SerializedName("deviceHello", alternate = ["device_hello"])
    var deviceHello: DeviceHello? = null,
    @SerializedName("capabilities", alternate = ["capability_list"])
    var capabilities: CapabilityList? = null,

    @SerializedName("heartbeat")
    var heartbeat: Heartbeat? = null,
    @SerializedName("deviceStatus", alternate = ["device_status"])
    var deviceStatus: DeviceStatus? = null,

    @SerializedName("transferOffer", alternate = ["transfer_offer"])
    var transferOffer: TransferOffer? = null,
    @SerializedName("transferAccept", alternate = ["transfer_accept"])
    var transferAccept: TransferAccept? = null,
    @SerializedName("transferReject", alternate = ["transfer_reject"])
    var transferReject: TransferReject? = null,
    @SerializedName("transferChunk", alternate = ["transfer_chunk"])
    var transferChunk: TransferChunk? = null,
    @SerializedName("transferComplete", alternate = ["transfer_complete"])
    var transferComplete: TransferComplete? = null,
    @SerializedName("transferCancel", alternate = ["transfer_cancel"])
    var transferCancel: TransferCancel? = null,

    @SerializedName("clipboardOffer", alternate = ["clipboard_offer"])
    var clipboardOffer: ClipboardOffer? = null,
    @SerializedName("clipboardPayload", alternate = ["clipboard_payload"])
    var clipboardPayload: ClipboardPayload? = null,

    @SerializedName("notificationEvent", alternate = ["notification_event"])
    var notificationEvent: NotificationEvent? = null,
    @SerializedName("notificationAction", alternate = ["notification_action"])
    var notificationAction: NotificationAction? = null,

    @SerializedName("sessionRequest", alternate = ["session_request"])
    var sessionRequest: SessionRequest? = null,
    @SerializedName("sessionStop", alternate = ["session_stop"])
    var sessionStop: SessionStop? = null,
    @SerializedName("sessionState", alternate = ["session_state"])
    var sessionState: SessionState? = null,
    @SerializedName("inputEvent", alternate = ["input_event"])
    var inputEvent: InputEvent? = null,

    @SerializedName("errorResponse", alternate = ["error_response"])
    var errorResponse: ErrorResponse? = null,

    // Expanded Ecosystem Payloads
    @SerializedName("handoffActivity", alternate = ["handoff_activity"])
    var handoffActivity: HandoffActivity? = null,
    @SerializedName("biometricChallenge", alternate = ["biometric_challenge"])
    var biometricChallenge: BiometricChallenge? = null,
    @SerializedName("biometricResponse", alternate = ["biometric_response"])
    var biometricResponse: BiometricResponse? = null,
    @SerializedName("folderSyncManifest", alternate = ["folder_sync_manifest"])
    var folderSyncManifest: FolderSyncManifest? = null,
    @SerializedName("telephonyEvent", alternate = ["telephony_event"])
    var telephonyEvent: TelephonyEvent? = null,
    @SerializedName("telephonyAction", alternate = ["telephony_action"])
    var telephonyAction: TelephonyAction? = null,
    @SerializedName("storageListRequest", alternate = ["storage_list_request"])
    var storageListRequest: StorageListRequest? = null,
    @SerializedName("storageListResponse", alternate = ["storage_list_response"])
    var storageListResponse: StorageListResponse? = null,
    @SerializedName("cameraControl", alternate = ["camera_control"])
    var cameraControl: CameraControlRequest? = null
)

data class CameraControlRequest(
    @SerializedName("lens")
    val lens: String? = null,
    @SerializedName("torch")
    val torch: Boolean? = null,
    @SerializedName("zoomRatio", alternate = ["zoom_ratio"])
    val zoomRatio: Float? = null,
    @SerializedName("exposureCompensation", alternate = ["exposure_compensation"])
    val exposureCompensation: Int? = null,
    @SerializedName("focusMode", alternate = ["focus_mode"])
    val focusMode: String? = null,
    @SerializedName("whiteBalance", alternate = ["white_balance"])
    val whiteBalance: String? = null
)
