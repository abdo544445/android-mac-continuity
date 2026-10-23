import Foundation

// MARK: - Enums

public enum DevicePlatform: String, Codable, Sendable {
    case unspecified = "PLATFORM_UNSPECIFIED"
    case macOS = "PLATFORM_MACOS"
    case android = "PLATFORM_ANDROID"
}

public enum DeviceEdition: String, Codable, Sendable {
    case publicEdition = "EDITION_PUBLIC"
    case advanced = "EDITION_ADVANCED"
}

public enum ThermalState: String, Codable, Sendable {
    case normal = "THERMAL_NORMAL"
    case fair = "THERMAL_FAIR"
    case serious = "THERMAL_SERIOUS"
    case critical = "THERMAL_CRITICAL"
}

public enum TransferRejectReason: String, Codable, Sendable {
    case userDeclined = "REJECT_USER_DECLINED"
    case insufficientStorage = "REJECT_INSUFFICIENT_STORAGE"
    case unsupportedType = "REJECT_UNSUPPORTED_TYPE"
    case rateLimited = "REJECT_RATE_LIMITED"
    case securityPolicy = "REJECT_SECURITY_POLICY"
}

public enum ClipboardDataType: String, Codable, Sendable {
    case text = "CLIP_TEXT"
    case url = "CLIP_URL"
    case imagePng = "CLIP_IMAGE_PNG"
    case html = "CLIP_HTML"
}

public enum SessionType: String, Codable, Sendable {
    case unknown = "SESSION_UNKNOWN"
    case screenMirror = "SESSION_SCREEN_MIRROR"
    case cameraStream = "SESSION_CAMERA_STREAM"
    case remoteInput = "SESSION_REMOTE_INPUT"
}

public enum StreamingState: String, Codable, Sendable {
    case idle = "STATE_IDLE"
    case starting = "STATE_STARTING"
    case active = "STATE_ACTIVE"
    case paused = "STATE_PAUSED"
    case stopped = "STATE_STOPPED"
    case error = "STATE_ERROR"
}

public enum InputAction: String, Codable, Sendable {
    case down = "ACTION_DOWN"
    case up = "ACTION_UP"
    case move = "ACTION_MOVE"
    case keyDown = "ACTION_KEY_DOWN"
    case keyUp = "ACTION_KEY_UP"
    case navBack = "ACTION_NAV_BACK"
    case navHome = "ACTION_NAV_HOME"
    case navRecents = "ACTION_NAV_RECENTS"
}

public enum ProtocolErrorCode: Int, Codable, Sendable {
    case unknown = 0
    case badRequest = 1
    case unauthorized = 2
    case forbidden = 3
    case notFound = 4
    case sessionExpired = 5
    case ioFailure = 6
    case checksumMismatch = 7
    case unsupportedVersion = 8
}

// MARK: - Message Payloads

public struct PairRequest: Codable, Sendable, Equatable {
    public var deviceId: String
    public var deviceName: String
    public var platform: DevicePlatform
    public var edition: DeviceEdition
    public var ephemeralPublicKeyBase64: String
    public var pairingPin: String
    public var identitySignatureBase64: String?

    public init(deviceId: String, deviceName: String, platform: DevicePlatform, edition: DeviceEdition, ephemeralPublicKeyBase64: String, pairingPin: String, identitySignatureBase64: String? = nil) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.platform = platform
        self.edition = edition
        self.ephemeralPublicKeyBase64 = ephemeralPublicKeyBase64
        self.pairingPin = pairingPin
        self.identitySignatureBase64 = identitySignatureBase64
    }
}

public struct PairConfirm: Codable, Sendable, Equatable {
    public var deviceId: String
    public var deviceName: String
    public var platform: DevicePlatform
    public var ephemeralPublicKeyBase64: String
    public var approved: Bool
    public var assignedSessionToken: String
    public var authTagBase64: String

    public init(deviceId: String, deviceName: String, platform: DevicePlatform, ephemeralPublicKeyBase64: String, approved: Bool, assignedSessionToken: String, authTagBase64: String) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.platform = platform
        self.ephemeralPublicKeyBase64 = ephemeralPublicKeyBase64
        self.approved = approved
        self.assignedSessionToken = assignedSessionToken
        self.authTagBase64 = authTagBase64
    }
}

public struct PairStatus: Codable, Sendable, Equatable {
    public var code: Int
    public var message: String

    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }
}

public struct DeviceHello: Codable, Sendable, Equatable {
    public var protocolVersion: UInt32
    public var appVersion: String
    public var osVersion: String
    public var deviceModel: String
    public var uptimeSeconds: Int64

    public init(protocolVersion: UInt32 = 1, appVersion: String, osVersion: String, deviceModel: String, uptimeSeconds: Int64 = 0) {
        self.protocolVersion = protocolVersion
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.uptimeSeconds = uptimeSeconds
    }
}

public struct CapabilityList: Codable, Sendable, Equatable {
    public var supportsFileTransfer: Bool
    public var supportsClipboard: Bool
    public var supportsNotifications: Bool
    public var supportsRemoteReplies: Bool
    public var supportsScreenMirroring: Bool
    public var supportsCameraStreaming: Bool
    public var supportsRemoteControl: Bool
    public var supportsPhotoBackup: Bool
    public var supportsAdvancedScrcpy: Bool
    public var maxChunkSizeBytes: UInt64
    public var supportedVideoCodecs: [String]

    public init(supportsFileTransfer: Bool = true, supportsClipboard: Bool = true, supportsNotifications: Bool = true, supportsRemoteReplies: Bool = true, supportsScreenMirroring: Bool = true, supportsCameraStreaming: Bool = true, supportsRemoteControl: Bool = false, supportsPhotoBackup: Bool = true, supportsAdvancedScrcpy: Bool = false, maxChunkSizeBytes: UInt64 = 524288, supportedVideoCodecs: [String] = ["H264"]) {
        self.supportsFileTransfer = supportsFileTransfer
        self.supportsClipboard = supportsClipboard
        self.supportsNotifications = supportsNotifications
        self.supportsRemoteReplies = supportsRemoteReplies
        self.supportsScreenMirroring = supportsScreenMirroring
        self.supportsCameraStreaming = supportsCameraStreaming
        self.supportsRemoteControl = supportsRemoteControl
        self.supportsPhotoBackup = supportsPhotoBackup
        self.supportsAdvancedScrcpy = supportsAdvancedScrcpy
        self.maxChunkSizeBytes = maxChunkSizeBytes
        self.supportedVideoCodecs = supportedVideoCodecs
    }
}

public struct Heartbeat: Codable, Sendable, Equatable {
    public var sequenceNumber: Int64
    public var timestampMs: Int64

    public init(sequenceNumber: Int64, timestampMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        self.sequenceNumber = sequenceNumber
        self.timestampMs = timestampMs
    }
}

public struct DeviceStatus: Codable, Sendable, Equatable {
    public var batteryPercentage: Int32
    public var isCharging: Bool
    public var isWifiConnected: Bool
    public var wifiSsid: String
    public var freeStorageBytes: Int64
    public var totalStorageBytes: Int64
    public var thermalState: ThermalState

    public init(batteryPercentage: Int32, isCharging: Bool, isWifiConnected: Bool, wifiSsid: String, freeStorageBytes: Int64, totalStorageBytes: Int64, thermalState: ThermalState = .normal) {
        self.batteryPercentage = batteryPercentage
        self.isCharging = isCharging
        self.isWifiConnected = isWifiConnected
        self.wifiSsid = wifiSsid
        self.freeStorageBytes = freeStorageBytes
        self.totalStorageBytes = totalStorageBytes
        self.thermalState = thermalState
    }
}

public struct TransferOffer: Codable, Sendable, Equatable {
    public var transferId: String
    public var fileName: String
    public var fileSizeBytes: Int64
    public var mimeType: String
    public var sha256Checksum: String
    public var totalChunks: Int32
    public var chunkSizeBytes: Int64
    public var isDirectoryBundle: Bool

    public init(transferId: String = UUID().uuidString, fileName: String, fileSizeBytes: Int64, mimeType: String = "application/octet-stream", sha256Checksum: String, totalChunks: Int32, chunkSizeBytes: Int64 = 524288, isDirectoryBundle: Bool = false) {
        self.transferId = transferId
        self.fileName = fileName
        self.fileSizeBytes = fileSizeBytes
        self.mimeType = mimeType
        self.sha256Checksum = sha256Checksum
        self.totalChunks = totalChunks
        self.chunkSizeBytes = chunkSizeBytes
        self.isDirectoryBundle = isDirectoryBundle
    }
}

public struct TransferAccept: Codable, Sendable, Equatable {
    public var transferId: String
    public var resumeChunkIndex: Int32
    public var saveDestinationHint: String?

    public init(transferId: String, resumeChunkIndex: Int32 = 0, saveDestinationHint: String? = nil) {
        self.transferId = transferId
        self.resumeChunkIndex = resumeChunkIndex
        self.saveDestinationHint = saveDestinationHint
    }
}

public struct TransferReject: Codable, Sendable, Equatable {
    public var transferId: String
    public var reason: TransferRejectReason
    public var details: String

    public init(transferId: String, reason: TransferRejectReason, details: String = "") {
        self.transferId = transferId
        self.reason = reason
        self.details = details
    }
}

public struct TransferChunk: Codable, Sendable, Equatable {
    public var transferId: String
    public var chunkIndex: Int32
    public var dataBase64: String
    public var chunkSha256: String

    public init(transferId: String, chunkIndex: Int32, dataBase64: String, chunkSha256: String) {
        self.transferId = transferId
        self.chunkIndex = chunkIndex
        self.dataBase64 = dataBase64
        self.chunkSha256 = chunkSha256
    }
}

public struct TransferComplete: Codable, Sendable, Equatable {
    public var transferId: String
    public var verified: Bool
    public var finalPathBasename: String
    public var bytesWritten: Int64

    public init(transferId: String, verified: Bool, finalPathBasename: String, bytesWritten: Int64) {
        self.transferId = transferId
        self.verified = verified
        self.finalPathBasename = finalPathBasename
        self.bytesWritten = bytesWritten
    }
}

public struct TransferCancel: Codable, Sendable, Equatable {
    public var transferId: String
    public var reason: String

    public init(transferId: String, reason: String) {
        self.transferId = transferId
        self.reason = reason
    }
}

public struct ClipboardOffer: Codable, Sendable, Equatable {
    public var clipId: String
    public var dataType: ClipboardDataType
    public var contentLength: Int64
    public var isSensitive: Bool
    public var textPreview: String

    public init(clipId: String = UUID().uuidString, dataType: ClipboardDataType = .text, contentLength: Int64, isSensitive: Bool = false, textPreview: String) {
        self.clipId = clipId
        self.dataType = dataType
        self.contentLength = contentLength
        self.isSensitive = isSensitive
        self.textPreview = textPreview
    }
}

public struct ClipboardPayload: Codable, Sendable, Equatable {
    public var clipId: String
    public var dataBase64: String
    public var mimeType: String

    public init(clipId: String, dataBase64: String, mimeType: String = "text/plain") {
        self.clipId = clipId
        self.dataBase64 = dataBase64
        self.mimeType = mimeType
    }
}

public struct NotificationEvent: Codable, Sendable, Equatable {
    public var notificationId: String
    public var packageName: String
    public var appDisplayName: String
    public var appIconPngBase64: String?
    public var title: String
    public var text: String
    public var postTimeMs: Int64
    public var isClearable: Bool
    public var hasReplyAction: Bool
    public var availableActions: [String]

    public init(notificationId: String, packageName: String, appDisplayName: String, appIconPngBase64: String? = nil, title: String, text: String, postTimeMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000), isClearable: Bool = true, hasReplyAction: Bool = false, availableActions: [String] = []) {
        self.notificationId = notificationId
        self.packageName = packageName
        self.appDisplayName = appDisplayName
        self.appIconPngBase64 = appIconPngBase64
        self.title = title
        self.text = text
        self.postTimeMs = postTimeMs
        self.isClearable = isClearable
        self.hasReplyAction = hasReplyAction
        self.availableActions = availableActions
    }
}

public struct NotificationAction: Codable, Sendable, Equatable {
    public var notificationId: String
    public var actionTitle: String
    public var replyText: String

    public init(notificationId: String, actionTitle: String, replyText: String = "") {
        self.notificationId = notificationId
        self.actionTitle = actionTitle
        self.replyText = replyText
    }
}

public struct SessionRequest: Codable, Sendable, Equatable {
    public var sessionId: String
    public var type: SessionType
    public var width: Int32
    public var height: Int32
    public var targetFps: Int32
    public var targetBitrateKbps: Int32
    public var codec: String
    public var cameraLens: String?

    public init(sessionId: String = UUID().uuidString, type: SessionType, width: Int32 = 1920, height: Int32 = 1080, targetFps: Int32 = 30, targetBitrateKbps: Int32 = 4000, codec: String = "H264", cameraLens: String? = nil) {
        self.sessionId = sessionId
        self.type = type
        self.width = width
        self.height = height
        self.targetFps = targetFps
        self.targetBitrateKbps = targetBitrateKbps
        self.codec = codec
        self.cameraLens = cameraLens
    }
}

public struct SessionStop: Codable, Sendable, Equatable {
    public var sessionId: String
    public var reason: String

    public init(sessionId: String, reason: String = "Normal termination") {
        self.sessionId = sessionId
        self.reason = reason
    }
}

public struct SessionState: Codable, Sendable, Equatable {
    public var sessionId: String
    public var state: StreamingState
    public var errorMessage: String?

    public init(sessionId: String, state: StreamingState, errorMessage: String? = nil) {
        self.sessionId = sessionId
        self.state = state
        self.errorMessage = errorMessage
    }
}

public struct InputEvent: Codable, Sendable, Equatable {
    public var sessionId: String
    public var action: InputAction
    public var normalizedX: Float
    public var normalizedY: Float
    public var keyCode: Int32
    public var textInput: String?

    public init(sessionId: String, action: InputAction, normalizedX: Float = 0, normalizedY: Float = 0, keyCode: Int32 = 0, textInput: String? = nil) {
        self.sessionId = sessionId
        self.action = action
        self.normalizedX = normalizedX
        self.normalizedY = normalizedY
        self.keyCode = keyCode
        self.textInput = textInput
    }
}

public struct ErrorResponse: Codable, Sendable, Equatable {
    public var code: ProtocolErrorCode
    public var message: String
    public var originalRequestId: String

    public init(code: ProtocolErrorCode, message: String, originalRequestId: String = "") {
        self.code = code
        self.message = message
        self.originalRequestId = originalRequestId
    }
}

// MARK: - Top-Level Envelope

public struct ContinuityEnvelope: Codable, Sendable, Equatable {
    public var version: UInt32
    public var requestId: String
    public var timestampMs: Int64
    public var senderDeviceId: String
    public var sessionToken: String?

    // Payloads
    public var pairRequest: PairRequest?
    public var pairConfirm: PairConfirm?
    public var pairStatus: PairStatus?
    public var deviceHello: DeviceHello?
    public var capabilities: CapabilityList?

    public var heartbeat: Heartbeat?
    public var deviceStatus: DeviceStatus?

    public var transferOffer: TransferOffer?
    public var transferAccept: TransferAccept?
    public var transferReject: TransferReject?
    public var transferChunk: TransferChunk?
    public var transferComplete: TransferComplete?
    public var transferCancel: TransferCancel?

    public var clipboardOffer: ClipboardOffer?
    public var clipboardPayload: ClipboardPayload?

    public var notificationEvent: NotificationEvent?
    public var notificationAction: NotificationAction?

    public var sessionRequest: SessionRequest?
    public var sessionStop: SessionStop?
    public var sessionState: SessionState?
    public var inputEvent: InputEvent?

    public var errorResponse: ErrorResponse?

    public init(
        version: UInt32 = 1,
        requestId: String = UUID().uuidString,
        timestampMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        senderDeviceId: String,
        sessionToken: String? = nil
    ) {
        self.version = version
        self.requestId = requestId
        self.timestampMs = timestampMs
        self.senderDeviceId = senderDeviceId
        self.sessionToken = sessionToken
    }
}
