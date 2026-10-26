import Foundation
import ContinuityProtocol

public struct ActivePairingSession: Sendable, Equatable {
    public let pin: String
    public let qrString: String
    public let createdAt: Date
    public let expiresAt: Date

    public var isExpired: Bool {
        Date() > expiresAt
    }
}

public enum PairingState: Equatable, Sendable {
    case idle
    case awaitingConnection(ActivePairingSession)
    case proposalReceived(PendingPairProposal)
    case paired(PairedDevice)
    case failed(String)
}

@MainActor
public final class PairingManager: ObservableObject {
    public static let shared = PairingManager()

    @Published public var state: PairingState = .idle
    @Published public var activeSession: ActivePairingSession? = nil
    @Published public var pendingProposal: PendingPairProposal? = nil

    private let crypto = CryptoManager.shared

    public init() {}

    /// Generates a fresh QR code URI and 6-digit visual PIN for onboarding
    public func createPairingSession(
        hostName: String,
        hostIp: String,
        port: Int,
        publicKeyBase64: String
    ) -> ActivePairingSession {
        let pin = crypto.generatePairingPin()
        let cleanName = hostName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Mac"
        let rawId = "mac-\(hostName.replacingOccurrences(of: " ", with: "-").lowercased())"
        let exp = Int(Date().addingTimeInterval(180).timeIntervalSince1970)

        let qrString = "continuity://pair?v=1&id=\(rawId)&name=\(cleanName)&host=\(hostIp)&port=\(port)&pk=\(publicKeyBase64)&pin=\(pin)&exp=\(exp)"
        let session = ActivePairingSession(
            pin: pin,
            qrString: qrString,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(180)
        )
        self.activeSession = session
        self.state = .awaitingConnection(session)
        return session
    }

    /// Verifies if an incoming PIN matches the active pairing session
    public func verifyPin(_ incomingPin: String) -> Bool {
        guard let session = activeSession, !session.isExpired else { return false }
        return session.pin == incomingPin
    }

    /// Processes an incoming pair proposal and transitions state
    public func recordProposal(_ proposal: PendingPairProposal) {
        self.pendingProposal = proposal
        self.state = .proposalReceived(proposal)
    }

    /// Derives shared secret and creates a confirmed PairConfirm envelope
    public func confirmPairing(
        proposal: PendingPairProposal,
        localKeyPair: KeyPair,
        assignedToken: String = UUID().uuidString
    ) -> (confirm: PairConfirm, pairedDevice: PairedDevice)? {
        guard let derivedKey = try? crypto.deriveSessionKey(
            localPrivateKey: localKeyPair.privateKey,
            remotePublicKeyBase64: proposal.remotePublicKeyBase64,
            pin: proposal.pin
        ) else {
            self.state = .failed("Cryptographic key derivation failed")
            return nil
        }

        let authTag = crypto.computeAuthTag(sessionKey: derivedKey, challenge: proposal.deviceId)
        let confirm = PairConfirm(
            deviceId: proposal.deviceId,
            deviceName: Host.current().localizedName ?? "MacBook Pro",
            platform: .macOS,
            ephemeralPublicKeyBase64: localKeyPair.publicKeyBase64,
            approved: true,
            assignedSessionToken: assignedToken,
            authTagBase64: authTag
        )

        let device = PairedDevice(
            deviceId: proposal.deviceId,
            name: proposal.deviceName,
            platform: .android,
            edition: .publicEdition,
            sessionToken: assignedToken,
            isConnected: true
        )

        DeviceRegistry.shared.addOrUpdateDevice(device)
        self.state = .paired(device)
        self.pendingProposal = nil
        self.activeSession = nil

        return (confirm, device)
    }

    /// Rejects or cancels a pending pair proposal
    public func rejectPairing(proposal: PendingPairProposal, localKeyPair: KeyPair) -> PairConfirm {
        let rejectConfirm = PairConfirm(
            deviceId: proposal.deviceId,
            deviceName: Host.current().localizedName ?? "MacBook Pro",
            platform: .macOS,
            ephemeralPublicKeyBase64: localKeyPair.publicKeyBase64,
            approved: false,
            assignedSessionToken: "",
            authTagBase64: ""
        )
        self.pendingProposal = nil
        self.state = .idle
        return rejectConfirm
    }

    public func reset() {
        self.state = .idle
        self.activeSession = nil
        self.pendingProposal = nil
    }
}
