import Foundation
import ContinuityProtocol

@MainActor
public final class ConnectionAgent: ObservableObject, NetworkSessionDelegate {
    public static let shared = ConnectionAgent()

    @Published public var isListening: Bool = false
    @Published public var activeSession: ContinuityNetworkSession?
    @Published public var isConnected: Bool = false
    @Published public var pairingPin: String = ""
    @Published public var isPairingSheetVisible: Bool = false

    private var listener: ContinuityNetworkListener?
    private var heartbeatTimer: Timer?
    private var keyPair = CryptoManager.shared.generateKeyPair()

    public init() {}

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
            print("[ConnectionAgent] Listener started successfully on port 52400.")
        } catch {
            print("[ConnectionAgent] Failed to start listener: \(error)")
        }
    }

    public func stop() {
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
        if let hello = envelope.deviceHello {
            if DeviceRegistry.shared.pairedDevices.contains(where: { $0.deviceId == envelope.senderDeviceId }) {
                DeviceRegistry.shared.updateConnectionStatus(deviceId: envelope.senderDeviceId, isConnected: true)
            } else {
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
    }

    private func handlePairRequest(_ req: PairRequest, envelope: ContinuityEnvelope, session: ContinuityNetworkSession) {
        let sessionToken = "tok_\(UUID().uuidString)"
        var authTag = ""

        if let sessionKey = try? CryptoManager.shared.deriveSessionKey(
            localPrivateKey: keyPair.privateKey,
            remotePublicKeyBase64: req.ephemeralPublicKeyBase64,
            pin: req.pairingPin
        ) {
            authTag = CryptoManager.shared.computeAuthTag(sessionKey: sessionKey, challenge: req.deviceId)
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
            deviceId: req.deviceId,
            name: req.deviceName,
            platform: req.platform,
            edition: req.edition,
            sessionToken: sessionToken,
            isConnected: true
        )
        DeviceRegistry.shared.addOrUpdateDevice(paired)
        self.isPairingSheetVisible = false
        print("[ConnectionAgent] Paired and connected with \(req.deviceName) (\(req.deviceId))")
    }

    private func startHeartbeats() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let session = self.activeSession else { return }
                var env = ContinuityEnvelope(senderDeviceId: "mac-companion")
                env.heartbeat = Heartbeat(sequenceNumber: 1)
                session.send(envelope: env)
            }
        }
    }
}
