import Foundation
import AppKit
import ContinuityProtocol

@MainActor
public final class HandoffBridge: ObservableObject {
    public static let shared = HandoffBridge()

    @Published public var activeHandoff: HandoffActivity? = nil
    @Published public var handoffHistory: [HandoffActivity] = []

    public init() {}

    public func handleIncomingHandoff(_ activity: HandoffActivity) {
        self.activeHandoff = activity
        self.handoffHistory.insert(activity, at: 0)
        ConnectionAgent.shared.debugLog("Received Handoff: '\(activity.title)' (\(activity.url)) from \(activity.sourceApp)")

        // Post a macOS system notification
        let notif = NSUserNotification()
        notif.title = "Handoff from Phone"
        notif.subtitle = activity.title.isEmpty ? activity.sourceApp : activity.title
        notif.informativeText = activity.url
        notif.actionButtonTitle = "Open"
        notif.hasActionButton = true
        NSUserNotificationCenter.default.deliver(notif)
    }

    public func openActiveHandoff() {
        guard let activity = activeHandoff, let url = URL(string: activity.url) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Pushes the current active browser tab (Safari or Chrome) from Mac to Android
    public func pushCurrentMacBrowserTab(session: ContinuityNetworkSession?) {
        guard let activeSession = session ?? ConnectionAgent.shared.activeSession else { return }

        Task.detached {
            var targetUrl = ""
            var targetTitle = ""

            // Try Safari
            let safariScript = "tell application \"Safari\" to if (count of windows) > 0 then return {URL, name} of current tab of front window"
            if let result = self.executeAppleScript(safariScript) {
                let parts = result.components(separatedBy: ", ")
                if parts.count >= 2 {
                    targetUrl = parts[0]
                    targetTitle = parts[1]
                }
            }

            // Try Google Chrome if Safari was empty
            if targetUrl.isEmpty {
                let chromeScript = "tell application \"Google Chrome\" to if (count of windows) > 0 then return {URL, title} of active tab of front window"
                if let result = self.executeAppleScript(chromeScript) {
                    let parts = result.components(separatedBy: ", ")
                    if parts.count >= 2 {
                        targetUrl = parts[0]
                        targetTitle = parts[1]
                    }
                }
            }

            if !targetUrl.isEmpty {
                let activity = HandoffActivity(
                    url: targetUrl,
                    title: targetTitle,
                    sourceApp: "macOS"
                )
                var env = ContinuityEnvelope(senderDeviceId: "macos-companion")
                env.handoffActivity = activity
                activeSession.send(envelope: env)
                await MainActor.run {
                    ConnectionAgent.shared.debugLog("Pushed Mac browser tab to Android: \(targetUrl)")
                }
            }
        }
    }

    private nonisolated func executeAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: source) {
            let output = scriptObject.executeAndReturnError(&error)
            if error == nil {
                return output.stringValue
            }
        }
        return nil
    }
}
