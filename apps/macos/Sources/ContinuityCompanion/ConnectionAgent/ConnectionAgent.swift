import Foundation
import AppKit
import ContinuityProtocol

public struct PendingPairProposal: Identifiable, Equatable, @unchecked Sendable {
    public var id: String { deviceId }
    public let deviceId: String
    public let deviceName: String
    public let pin: String
    public let remotePublicKeyBase64: String
    public let session: ContinuityNetworkSession?

    public static func == (lhs: PendingPairProposal, rhs: PendingPairProposal) -> Bool {
        lhs.deviceId == rhs.deviceId && lhs.pin == rhs.pin && lhs.deviceName == rhs.deviceName
    }
}

@MainActor
public final class ConnectionAgent: ObservableObject, NetworkSessionDelegate {
    public static let shared = ConnectionAgent()

    @Published public var isListening: Bool = false
    @Published public var activeSession: ContinuityNetworkSession?
    @Published public var isConnected: Bool = false
    @Published public var pairingPin: String = ""
    @Published public var isPairingSheetVisible: Bool = false
    @Published public var pendingPairProposal: PendingPairProposal? = nil
    @Published public var liveMirrorFrame: NSImage? = nil
    @Published public var liveCameraFrame: NSImage? = nil
    @Published public var shouldNavigateToMirror: Bool = false
    @Published public var shouldNavigateToCamera: Bool = false

    private var listener: ContinuityNetworkListener?
    private var heartbeatTimer: Timer?
    private var keyPair = CryptoManager.shared.generateKeyPair()

    public init() {}

    public nonisolated func debugLog(_ message: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] [ConnectionAgent] \(message)\n"
        print(line, terminator: "")
        fflush(stdout)
        if let data = line.data(using: .utf8) {
            let logURL = URL(fileURLWithPath: "/tmp/continuity_macos.log")
            if let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: logURL)
            }
        }
    }

    public func start() {
        if isListening { return }
        do {
            if AdvancedHostManager.shared.isAdbAvailable {
                _ = AdvancedHostManager.shared.setupAdbReverseTunnel(port: 52400)
            }
            let listener = ContinuityNetworkListener(port: 52400)
            listener.onNewSession = { [weak self] session in
                guard let self = self else { return }
                // Synchronously retain delegate before session.start() begins reading frames
                session.setRetainedDelegate(self)
                Task { @MainActor [weak self] in
                    self?.handleNewSession(session)
                }
            }
            try listener.start()
            self.listener = listener
            self.isListening = true
            LanDiscoveryService.shared.start(publicKeyBase64: keyPair.publicKeyBase64)
            debugLog("Listener started successfully on port 52400 (IP: \(getLocalIPAddress())).")
        } catch {
            debugLog("Failed to start listener: \(error)")
        }
    }

    public func stop() {
        LanDiscoveryService.shared.stop()
        listener?.stop()
        activeSession?.stop()
        heartbeatTimer?.invalidate()
        activeSession = nil
        isConnected = false
        isListening = false
    }

    public func preparePairingSession() -> (qrString: String, pin: String) {
        self.pairingPin = CryptoManager.shared.generatePairingPin()
        let rawMacName = Host.current().localizedName ?? "Mac"
        let deviceId = "mac-\(rawMacName.replacingOccurrences(of: " ", with: "-").lowercased())"
        let hostName = getLocalIPAddress()
        let pubKey = keyPair.publicKeyBase64
        let exp = Int64(Date().addingTimeInterval(300).timeIntervalSince1970)

        var comps = URLComponents()
        comps.scheme = "continuity"
        comps.host = "pair"
        comps.queryItems = [
            URLQueryItem(name: "v", value: "1"),
            URLQueryItem(name: "id", value: deviceId),
            URLQueryItem(name: "name", value: rawMacName),
            URLQueryItem(name: "host", value: hostName),
            URLQueryItem(name: "port", value: "52400"),
            URLQueryItem(name: "pk", value: pubKey),
            URLQueryItem(name: "pin", value: pairingPin),
            URLQueryItem(name: "exp", value: "\(exp)")
        ]
        // Percent-encode '+' as '%2B' so Android Uri.getQueryParameter preserves Base64 '+' characters
        let qrString = (comps.url?.absoluteString ?? "").replacingOccurrences(of: "+", with: "%2B")
        return (qrString, pairingPin)
    }

    public func getLocalIPAddress() -> String {
        var address = "127.0.0.1"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return address }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name.starts(with: "en") || name.starts(with: "bridge") {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    let ip = String(cString: hostname)
                    if !ip.isEmpty && ip != "127.0.0.1" && !ip.starts(with: "169.254.") {
                        address = ip
                        if name == "en0" {
                            break // Prefer primary en0 interface
                        }
                    }
                }
            }
        }
        return address
    }

    private func handleNewSession(_ session: ContinuityNetworkSession) {
        self.activeSession = session
        session.setRetainedDelegate(self)
        self.isConnected = true
        startHeartbeats()
    }

    // MARK: - NetworkSessionDelegate

    public nonisolated func sessionDidConnect(_ session: ContinuityNetworkSession) {
        Task { @MainActor in
            self.activeSession = session
            self.isConnected = true
            print("[ConnectionAgent] Session connected: \(session.id)")
        }
    }

    public nonisolated func sessionDidDisconnect(_ session: ContinuityNetworkSession, error: Error?) {
        Task { @MainActor in
            if self.activeSession?.id == session.id {
                self.isConnected = false
                self.activeSession = nil
                self.heartbeatTimer?.invalidate()
                if let activeId = DeviceRegistry.shared.activeDevice?.deviceId {
                    DeviceRegistry.shared.updateConnectionStatus(deviceId: activeId, isConnected: false)
                }
                print("[ConnectionAgent] Session disconnected: \(session.id), error: \(String(describing: error))")
            }
        }
    }

    public nonisolated func session(_ session: ContinuityNetworkSession, didReceiveEnvelope envelope: ContinuityEnvelope) {
        Task { @MainActor in
            self.processEnvelope(envelope, session: session)
        }
    }

    public nonisolated func session(_ session: ContinuityNetworkSession, didReceiveBinaryChunk chunk: RawBinaryChunk) {
        if chunk.transferId == "00000000-0000-0000-0000-000000MIRROR" {
            if let img = NSImage(data: chunk.data) {
                Task { @MainActor in
                    if self.liveMirrorFrame == nil {
                        self.shouldNavigateToMirror = true
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    self.liveMirrorFrame = img
                }
            }
            return
        }
        if chunk.transferId == "00000000-0000-0000-0000-000000CAMERA" {
            if let img = NSImage(data: chunk.data) {
                Task { @MainActor in
                    if self.liveCameraFrame == nil {
                        self.shouldNavigateToCamera = true
                    }
                    self.liveCameraFrame = img
                    CameraStreamManager.shared.updateFrame(img)
                }
            }
            return
        }
        Task { @MainActor in
            FileTransferEngine.shared.handleIncomingBinaryChunk(chunk, session: session)
        }
    }

    // MARK: - Envelope Dispatch

    private func processEnvelope(_ envelope: ContinuityEnvelope, session: ContinuityNetworkSession) {
        self.activeSession = session
        self.isConnected = true

        if let pairReq = envelope.pairRequest {
            handlePairRequest(pairReq, envelope: envelope, session: session)
        }
        if let pairConf = envelope.pairConfirm {
            handleIncomingPairConfirm(pairConf, envelope: envelope, session: session)
        }
        if let hello = envelope.deviceHello {
            if DeviceRegistry.shared.pairedDevices.contains(where: { $0.deviceId == envelope.senderDeviceId }) {
                DeviceRegistry.shared.updateConnectionStatus(deviceId: envelope.senderDeviceId, isConnected: true)
            } else if pendingPairProposal == nil {
                // Only auto-register on DeviceHello if not waiting on a Bluetooth-style PIN confirmation
                let device = PairedDevice(
                    deviceId: envelope.senderDeviceId,
                    name: hello.deviceModel,
                    platform: .android,
                    edition: .publicEdition,
                    sessionToken: envelope.sessionToken ?? "tok_\(UUID().uuidString)",
                    isConnected: true
                )
                DeviceRegistry.shared.addOrUpdateDevice(device)
            }
        }
        if let status = envelope.deviceStatus {
            DeviceRegistry.shared.updateConnectionStatus(deviceId: envelope.senderDeviceId, isConnected: true)
            DeviceRegistry.shared.updateDeviceStatus(deviceId: envelope.senderDeviceId, status: status)
        }
        if let offer = envelope.transferOffer {
            FileTransferEngine.shared.handleIncomingOffer(offer, session: session)
        }
        if let chunk = envelope.transferChunk {
            FileTransferEngine.shared.handleIncomingChunk(chunk, session: session)
        }
        if let complete = envelope.transferComplete {
            FileTransferEngine.shared.handleIncomingComplete(complete)
        }
        if let clip = envelope.clipboardPayload {
            ClipboardBridge.shared.handleIncomingClipboard(clip)
        }
        if let notif = envelope.notificationEvent {
            NotificationBridge.shared.handleIncomingNotification(notif)
        }
        if let sessReq = envelope.sessionRequest, sessReq.type == .screenMirror {
            debugLog("Android requested Screen Mirror session!")
            self.shouldNavigateToMirror = true
            NSApp.activate(ignoringOtherApps: true)
        }
        if let sessStop = envelope.sessionStop {
            debugLog("Android stopped session: \(sessStop.reason)")
            self.liveMirrorFrame = nil
        }
        if let handoff = envelope.handoffActivity {
            HandoffBridge.shared.handleIncomingHandoff(handoff)
        }
        if let bioResp = envelope.biometricResponse {
            BiometricAuthBridge.shared.handleBiometricResponse(bioResp)
        }
        if let manifest = envelope.folderSyncManifest {
            FolderSyncEngine.shared.handleRemoteManifest(manifest, session: session)
        }
        if let callEvent = envelope.telephonyEvent {
            CallRelayBridge.shared.handleTelephonyEvent(callEvent)
        }
        if let storageResp = envelope.storageListResponse {
            StorageExplorerManager.shared.handleStorageListResponse(storageResp)
        }
        if let input = envelope.inputEvent, input.sessionId == "ext_display" {
            ExtendedDisplayManager.shared.handleRemoteInput(
                xRatio: input.normalizedX,
                yRatio: input.normalizedY,
                isDown: input.action == .down
            )
        }
    }

    public func requestWirelessMirrorFromAndroid() {
        var env = ContinuityEnvelope(senderDeviceId: "macos-companion")
        env.sessionRequest = SessionRequest(
            type: .screenMirror,
            width: 1280,
            height: 720,
            targetFps: 25,
            codec: "JPEG"
        )
        activeSession?.send(envelope: env)
        debugLog("Sent SessionRequest(.screenMirror) to Android")
    }

    public func initiatePairingWithDiscoveredPeer(_ peer: DiscoveredPeer) {
        let pin = CryptoManager.shared.generatePairingPin()
        self.pairingPin = pin
        self.pendingPairProposal = PendingPairProposal(
            deviceId: peer.deviceId,
            deviceName: peer.deviceName,
            pin: pin,
            remotePublicKeyBase64: peer.publicKeyBase64,
            session: activeSession
        )
        LanDiscoveryService.shared.sendPairInvite(
            to: peer,
            pin: pin,
            publicKeyBase64: keyPair.publicKeyBase64
        )
    }

    private func handlePairRequest(_ req: PairRequest, envelope: ContinuityEnvelope, session: ContinuityNetworkSession) {
        debugLog("Received PairRequest from \(req.deviceName) (\(req.deviceId)) with PIN \(req.pairingPin)")

        // If the user explicitly opened the QR code modal and scanned that exact PIN, complete immediately
        if isPairingSheetVisible && req.pairingPin == pairingPin && pendingPairProposal == nil {
            finalizePairing(
                deviceId: req.deviceId,
                deviceName: req.deviceName,
                pin: req.pairingPin,
                remotePublicKeyBase64: req.ephemeralPublicKeyBase64,
                session: session
            )
            return
        }

        // Otherwise, show Bluetooth-style 6-digit PIN comparison modal on Mac (and update session reference)
        self.pairingPin = req.pairingPin
        self.pendingPairProposal = PendingPairProposal(
            deviceId: req.deviceId,
            deviceName: req.deviceName,
            pin: req.pairingPin,
            remotePublicKeyBase64: req.ephemeralPublicKeyBase64,
            session: session
        )
        NSApp.activate(ignoringOtherApps: true)
    }

    private func handleIncomingPairConfirm(_ confirm: PairConfirm, envelope: ContinuityEnvelope, session: ContinuityNetworkSession) {
        if !confirm.approved {
            debugLog("Remote device \(confirm.deviceName) declined pairing.")
            self.pendingPairProposal = nil
            return
        }
        debugLog("Remote device \(confirm.deviceName) confirmed 6-digit PIN pairing! Finalizing on Mac...")
        let pin = pendingPairProposal?.pin ?? pairingPin
        let devId = confirm.deviceId.isEmpty ? (pendingPairProposal?.deviceId ?? envelope.senderDeviceId) : confirm.deviceId
        let devName = confirm.deviceName.isEmpty ? (pendingPairProposal?.deviceName ?? "Android Device") : confirm.deviceName
        let pubKey = confirm.ephemeralPublicKeyBase64.isEmpty ? (pendingPairProposal?.remotePublicKeyBase64 ?? "") : confirm.ephemeralPublicKeyBase64

        finalizePairing(
            deviceId: devId,
            deviceName: devName,
            pin: pin,
            remotePublicKeyBase64: pubKey,
            session: session
        )
    }

    public func confirmPendingPairing() {
        guard let proposal = pendingPairProposal else { return }
        guard let session = proposal.session ?? activeSession else {
            debugLog("Cannot confirm pairing yet: waiting for peer TCP socket connection...")
            return
        }
        finalizePairing(
            deviceId: proposal.deviceId,
            deviceName: proposal.deviceName,
            pin: proposal.pin,
            remotePublicKeyBase64: proposal.remotePublicKeyBase64,
            session: session
        )
    }

    public func declinePendingPairing() {
        if let proposal = pendingPairProposal, let session = proposal.session ?? activeSession {
            let macName = Host.current().localizedName ?? "Mac"
            let macId = "mac-\(macName.replacingOccurrences(of: " ", with: "-").lowercased())"
            let rejectConfirm = PairConfirm(
                deviceId: macId,
                deviceName: macName,
                platform: .macOS,
                ephemeralPublicKeyBase64: keyPair.publicKeyBase64,
                approved: false,
                assignedSessionToken: "",
                authTagBase64: ""
            )
            var replyEnv = ContinuityEnvelope(senderDeviceId: macId)
            replyEnv.pairConfirm = rejectConfirm
            session.send(envelope: replyEnv)
        }
        self.pendingPairProposal = nil
    }

    private func finalizePairing(
        deviceId: String,
        deviceName: String,
        pin: String,
        remotePublicKeyBase64: String,
        session: ContinuityNetworkSession
    ) {
        let sessionToken = "tok_\(UUID().uuidString)"
        var authTag = ""

        if let sessionKey = try? CryptoManager.shared.deriveSessionKey(
            localPrivateKey: keyPair.privateKey,
            remotePublicKeyBase64: remotePublicKeyBase64,
            pin: pin
        ) {
            authTag = CryptoManager.shared.computeAuthTag(sessionKey: sessionKey, challenge: deviceId)
        }

        let macName = Host.current().localizedName ?? "Mac"
        let macId = "mac-\(macName.replacingOccurrences(of: " ", with: "-").lowercased())"

        let confirm = PairConfirm(
            deviceId: macId,
            deviceName: macName,
            platform: .macOS,
            ephemeralPublicKeyBase64: keyPair.publicKeyBase64,
            approved: true,
            assignedSessionToken: sessionToken,
            authTagBase64: authTag
        )

        var replyEnv = ContinuityEnvelope(senderDeviceId: macId, sessionToken: sessionToken)
        replyEnv.pairConfirm = confirm
        session.send(envelope: replyEnv)

        let paired = PairedDevice(
            deviceId: deviceId,
            name: deviceName,
            platform: .android,
            edition: .publicEdition,
            sessionToken: sessionToken,
            isConnected: true
        )
        DeviceRegistry.shared.addOrUpdateDevice(paired)
        self.pendingPairProposal = nil
        self.isPairingSheetVisible = false
        self.isConnected = true
        debugLog("Paired and connected with \(deviceName) (\(deviceId))")
    }

    private func startHeartbeats() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if AdvancedHostManager.shared.isAdbAvailable {
                    _ = AdvancedHostManager.shared.setupAdbReverseTunnel(port: 52400)
                }
                guard let session = self.activeSession else { return }
                var env = ContinuityEnvelope(senderDeviceId: "mac-companion")
                env.heartbeat = Heartbeat(sequenceNumber: 1)
                session.send(envelope: env)
            }
        }
    }
}
