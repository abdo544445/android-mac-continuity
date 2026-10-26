import SwiftUI
import AppKit
import ContinuityProtocol

@MainActor
public final class MirroringManager: ObservableObject {
    public static let shared = MirroringManager()

    @Published public var isMirroringActive: Bool = false
    @Published public var selectedResolution: String = "1080p"
    @Published public var currentFrame: NSImage? = nil
    @Published public var fps: Double = 0.0
    @Published public var latencyMs: Double = 0.0

    private var frameCount: Int = 0
    private var lastFpsCalculationTime = Date()

    public init() {}

    public func startMirroring(session: ContinuityNetworkSession?) {
        guard !isMirroringActive else { return }
        isMirroringActive = true
        frameCount = 0
        lastFpsCalculationTime = Date()

        let width = selectedResolution == "1080p" ? 1920 : 1280
        let height = selectedResolution == "1080p" ? 1080 : 720

        var env = ContinuityEnvelope(senderDeviceId: "macos-companion")
        env.sessionRequest = SessionRequest(
            type: .screenMirror,
            width: Int32(width),
            height: Int32(height),
            targetFps: 30,
            codec: "H264"
        )
        session?.send(envelope: env)
        ConnectionAgent.shared.debugLog("MirroringManager requested screen mirror (\(selectedResolution))")
    }

    public func stopMirroring(session: ContinuityNetworkSession?) {
        isMirroringActive = false
        currentFrame = nil
        fps = 0.0

        var env = ContinuityEnvelope(senderDeviceId: "macos-companion")
        env.sessionStop = SessionStop(sessionId: "mirror", reason: "User stopped")
        session?.send(envelope: env)
        ConnectionAgent.shared.liveMirrorFrame = nil
        ConnectionAgent.shared.debugLog("MirroringManager stopped screen mirror")
    }

    public func updateFrame(_ image: NSImage) {
        self.currentFrame = image
        self.frameCount += 1

        let now = Date()
        let interval = now.timeIntervalSince(lastFpsCalculationTime)
        if interval >= 1.0 {
            self.fps = Double(frameCount) / interval
            self.frameCount = 0
            self.lastFpsCalculationTime = now
        }
    }

    public func sendInput(action: InputAction, session: ContinuityNetworkSession?) {
        var env = ContinuityEnvelope(senderDeviceId: "macos-companion")
        env.inputEvent = InputEvent(sessionId: "mirror", action: action)
        session?.send(envelope: env)

        let keycode: Int?
        switch action {
        case .navBack: keycode = 4
        case .navHome: keycode = 3
        case .navRecents: keycode = 187
        default: keycode = nil
        }
        if let kc = keycode {
            AdvancedHostManager.shared.executeAdbCommand(args: ["shell", "input", "keyevent", "\(kc)"])
        }
    }

    public func sendKey(code: Int32, session: ContinuityNetworkSession?) {
        var env = ContinuityEnvelope(senderDeviceId: "macos-companion")
        env.inputEvent = InputEvent(sessionId: "mirror", action: .keyDown, keyCode: code)
        session?.send(envelope: env)
        AdvancedHostManager.shared.executeAdbCommand(args: ["shell", "input", "keyevent", "\(code)"])
    }

    public func handleTap(normX: Float, normY: Float, session: ContinuityNetworkSession?) {
        var env = ContinuityEnvelope(senderDeviceId: "macos-companion")
        env.inputEvent = InputEvent(sessionId: "mirror", action: .down, normalizedX: normX, normalizedY: normY)
        session?.send(envelope: env)

        let targetX = Int(normX * 1080)
        let targetY = Int(normY * 2400)
        AdvancedHostManager.shared.executeAdbCommand(args: ["shell", "input", "tap", "\(targetX)", "\(targetY)"])
    }
}
