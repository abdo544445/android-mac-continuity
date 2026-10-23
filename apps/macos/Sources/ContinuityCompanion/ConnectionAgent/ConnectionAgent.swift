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
        do {
            let listener = ContinuityNetworkListener(port: 52400)
            listener.onNewSession = { [weak self] session in
                Task { @MainActor [weak self] in
                    self?.handleNewSession(session)
                }
            }
            try listener.start()
            self.listener = listener
            self.isListening = true
            print("[ConnectionAgent] Listener started successfully.")
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
        let deviceId = "mac-\(Host.current().localizedName?.replacingOccurrences(of: " ", with: "-").lowercased() ?? "macbook")"
        let hostName = "127.0.0.1" // In actual local Wi-Fi, resolved from local network interface
        let pubKey = keyPair.publicKeyBase64
        let exp = Int64(Date().addingTimeInterval(180).timeIntervalSince1970)

        let qrString = "continuity://pair?v=1&id=\(deviceId)&name=macOS-Companion&host=\(hostName)&port=52400&pk=\(pubKey)&pin=\(pairingPin)&exp=\(exp)"
        return (qrString, pairingPin)
    }

    private func handleNewSession(_ session: ContinuityNetworkSession) {
        self.activeSession = session
        session.delegate = self
        self.isConnected = true
        DeviceRegistry.shared.updateConnectionStatus(deviceId: session.id, isConnected: true)
        startHeartbeats()
    }

    // MARK: - NetworkSessionDelegate

    public nonisolated func sessionDidConnect(_ session: ContinuityNetworkSession) {
        Task { @MainActor in
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
                print("[ConnectionAgent] Session disconnected: \(session.id), error: \(String(describing: error))")
            }
        }
    }

    public nonisolated func session(_ session: ContinuityNetworkSession, didReceiveEnvelope envelope: ContinuityEnvelope) {
        Task { @MainActor in
            self.processEnvelope(envelope, session: session)
        }
    }

    // MARK: - Envelope Dispatch

    private func processEnvelope(_ envelope: ContinuityEnvelope, session: ContinuityNetworkSession) {
        if let pairReq = envelope.pairRequest {
            handlePairRequest(pairReq, envelope: envelope, session: session)
        } else if let status = envelope.deviceStatus {
            DeviceRegistry.shared.updateDeviceStatus(deviceId: envelope.senderDeviceId, status: status)
        } else if let offer = envelope.transferOffer {
            FileTransferEngine.shared.handleIncomingOffer(offer, session: session)
        } else if let chunk = envelope.transferChunk {
            FileTransferEngine.shared.handleIncomingChunk(chunk, session: session)
        } else if let complete = envelope.transferComplete {
            FileTransferEngine.shared.handleIncomingComplete(complete)
        } else if let clip = envelope.clipboardPayload {
            ClipboardBridge.shared.handleIncomingClipboard(clip)
        } else if let notif = envelope.notificationEvent {
            NotificationBridge.shared.handleIncomingNotification(notif)
        } else if envelope.heartbeat != nil {
            // Heartbeat received
        }
    }

    private func handlePairRequest(_ req: PairRequest, envelope: ContinuityEnvelope, session: ContinuityNetworkSession) {
        // Derive session key
        let sessionToken = "tok_\(UUID().uuidString)"
        var authTag = ""

        if let sessionKey = try? CryptoManager.shared.deriveSessionKey(
            localPrivateKey: keyPair.privateKey,
            remotePublicKeyBase64: req.ephemeralPublicKeyBase64,
            pin: req.pairingPin
        ) {
            authTag = CryptoManager.shared.computeAuthTag(sessionKey: sessionKey, challenge: req.deviceId)
        }

        let confirm = PairConfirm(
            deviceId: "mac-companion",
            deviceName: Host.current().localizedName ?? "MacBook Pro",
            platform: .macOS,
            ephemeralPublicKeyBase64: keyPair.publicKeyBase64,
            approved: true,
            assignedSessionToken: sessionToken,
            authTagBase64: authTag
        )

        var replyEnv = ContinuityEnvelope(senderDeviceId: "mac-companion", sessionToken: sessionToken)
        replyEnv.pairConfirm = confirm
        session.send(envelope: replyEnv)

        // Register device
        let paired = PairedDevice(
            deviceId: req.deviceId,
            name: req.deviceName,
            platform: req.platform,
            edition: req.edition,
            sessionToken: sessionToken,
            isConnected: true
        )
        DeviceRegistry.shared.addOrUpdateDevice(paired)
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
