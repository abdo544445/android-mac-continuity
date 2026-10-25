import Foundation
import AppKit
import ContinuityProtocol

@MainActor
public final class CallRelayBridge: ObservableObject {
    public static let shared = CallRelayBridge()

    @Published public var activeCall: TelephonyEvent? = nil
    @Published public var callHistory: [TelephonyEvent] = []

    private init() {}

    public func handleTelephonyEvent(_ event: TelephonyEvent) {
        ConnectionAgent.shared.debugLog("Call Relay event: \(event.callerName) [\(event.state)]")

        if event.state == "RINGING" {
            self.activeCall = event
            self.callHistory.insert(event, at: 0)

            // Play incoming call sound / alert
            NSSound.beep()

            let notif = NSUserNotification()
            notif.title = "Incoming Call from Phone"
            notif.subtitle = event.callerName
            notif.informativeText = event.callerNumber
            notif.hasActionButton = true
            notif.actionButtonTitle = "Answer"
            notif.otherButtonTitle = "Decline"
            NSUserNotificationCenter.default.deliver(notif)
        } else if event.state == "DISCONNECTED" {
            if self.activeCall?.callId == event.callId {
                self.activeCall = nil
            }
        }
    }

    public func respondToCall(callId: String, action: String, session: ContinuityNetworkSession?) {
        guard let activeSession = session ?? ConnectionAgent.shared.activeSession else { return }

        var env = ContinuityEnvelope(senderDeviceId: "macos-companion")
        env.telephonyAction = TelephonyAction(callId: callId, action: action)
        activeSession.send(envelope: env)

        if action == "REJECT" {
            self.activeCall = nil
        }
        ConnectionAgent.shared.debugLog("Sent TelephonyAction: \(action) for call \(callId)")
    }
}
