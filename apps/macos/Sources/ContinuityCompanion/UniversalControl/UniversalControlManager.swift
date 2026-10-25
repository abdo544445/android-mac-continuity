import Foundation
import AppKit
import ContinuityProtocol

@MainActor
public final class UniversalControlManager: ObservableObject {
    public static let shared = UniversalControlManager()

    @Published public var isControlActive: Bool = false
    @Published public var edgeSwitchEnabled: Bool = true
    @Published public var edgeAlignment: ScreenEdge = .right

    public enum ScreenEdge: String, CaseIterable, Identifiable {
        case left = "Left"
        case right = "Right"
        public var id: String { rawValue }
    }

    private var eventMonitor: Any?
    private var mouseCheckTimer: Timer?

    public init() {}

    public func toggleControl(session: ContinuityNetworkSession?) {
        if isControlActive {
            stopControl()
        } else {
            startControl(session: session)
        }
    }

    public func startControl(session: ContinuityNetworkSession?) {
        guard !isControlActive else { return }
        isControlActive = true
        ConnectionAgent.shared.debugLog("Universal Control activated (Shared Mouse & Keyboard)")

        let activeSess = session ?? ConnectionAgent.shared.activeSession

        // Monitor local keystrokes when control is active to forward them to Android
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self = self, self.isControlActive else { return event }

            if event.keyCode == 53 { // ESC key exits Universal Control
                self.stopControl()
                return nil
            }

            if let chars = event.characters, !chars.isEmpty {
                self.sendTextToAndroid(chars, session: activeSess)
                return nil
            }
            return event
        }
    }

    public func stopControl() {
        guard isControlActive else { return }
        isControlActive = false
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        mouseCheckTimer?.invalidate()
        mouseCheckTimer = nil
        ConnectionAgent.shared.debugLog("Universal Control deactivated")
    }

    public func sendMouseTap(normalizedX: Float, normalizedY: Float, session: ContinuityNetworkSession?) {
        guard let activeSession = session ?? ConnectionAgent.shared.activeSession else { return }
        var env = ContinuityEnvelope(senderDeviceId: "macos-companion")
        env.inputEvent = InputEvent(
            sessionId: "universal_control",
            action: .down,
            normalizedX: normalizedX,
            normalizedY: normalizedY
        )
        activeSession.send(envelope: env)

        // Also if ADB is available, tap directly
        if AdvancedHostManager.shared.isAdbAvailable {
            let path = AdvancedHostManager.shared.adbPath
            Task.detached {
                let x = Int(normalizedX * 1280)
                let y = Int(normalizedY * 800)
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: path)
                proc.arguments = ["shell", "input", "tap", "\(x)", "\(y)"]
                try? proc.run()
            }
        }
    }

    private func sendTextToAndroid(_ text: String, session: ContinuityNetworkSession?) {
        guard let activeSession = session ?? ConnectionAgent.shared.activeSession else { return }
        var env = ContinuityEnvelope(senderDeviceId: "macos-companion")
        env.inputEvent = InputEvent(
            sessionId: "universal_control",
            action: .keyDown,
            textInput: text
        )
        activeSession.send(envelope: env)

        // Also if ADB is available, write text directly
        if AdvancedHostManager.shared.isAdbAvailable {
            let path = AdvancedHostManager.shared.adbPath
            let safeText = text.replacingOccurrences(of: " ", with: "%s")
            Task.detached {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: path)
                proc.arguments = ["shell", "input", "text", safeText]
                try? proc.run()
            }
        }
    }
}
