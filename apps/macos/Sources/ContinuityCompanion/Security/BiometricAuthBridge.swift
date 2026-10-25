import Foundation
import AppKit
import ContinuityProtocol

@MainActor
public final class BiometricAuthBridge: ObservableObject {
    public static let shared = BiometricAuthBridge()

    @Published public var isChallenging: Bool = false
    @Published public var lastAuthResult: String = ""
    @Published public var lastAuthSuccess: Bool = false

    private var currentChallengeId: String? = nil

    private init() {}

    public func requestBiometricUnlock(session: ContinuityNetworkSession?) {
        guard let activeSession = session ?? ConnectionAgent.shared.activeSession else {
            lastAuthResult = "Cannot request: No connected device"
            return
        }

        let challenge = BiometricChallenge(
            promptTitle: "Unlock macOS",
            clientNonce: UUID().uuidString
        )
        self.currentChallengeId = challenge.challengeId
        self.isChallenging = true
        self.lastAuthResult = "Waiting for fingerprint/face on device..."

        var env = ContinuityEnvelope(senderDeviceId: "macos-companion")
        env.biometricChallenge = challenge
        activeSession.send(envelope: env)
        ConnectionAgent.shared.debugLog("Sent BiometricChallenge: \(challenge.challengeId)")
    }

    public func handleBiometricResponse(_ response: BiometricResponse) {
        guard isChallenging, response.challengeId == currentChallengeId else { return }

        self.isChallenging = false
        self.lastAuthSuccess = response.approved

        if response.approved {
            self.lastAuthResult = "Biometric authentication approved (\(response.biometricType))"
            ConnectionAgent.shared.debugLog("Biometric auth SUCCESS from device")

            let notif = NSUserNotification()
            notif.title = "Device Authenticated"
            notif.informativeText = "Biometric unlock verified successfully."
            NSUserNotificationCenter.default.deliver(notif)
        } else {
            self.lastAuthResult = "Biometric authentication rejected or cancelled"
            ConnectionAgent.shared.debugLog("Biometric auth REJECTED from device")
        }
    }
}
