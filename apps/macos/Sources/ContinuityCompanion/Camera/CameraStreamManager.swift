import SwiftUI
import AppKit
import ContinuityProtocol

@MainActor
public final class CameraStreamManager: ObservableObject {
    public static let shared = CameraStreamManager()

    @Published public var isStreaming: Bool = false
    @Published public var selectedLens: String = "BACK"
    @Published public var selectedResolution: String = "1080p"
    @Published public var isTorchOn: Bool = false
    @Published public var currentFrame: NSImage? = nil
    @Published public var fps: Double = 0.0
    @Published public var latencyMs: Double = 0.0

    private var frameCount: Int = 0
    private var lastFpsCalculationTime = Date()

    public init() {}

    public func startStreaming(session: ContinuityNetworkSession?) {
        guard !isStreaming else { return }
        isStreaming = true
        frameCount = 0
        lastFpsCalculationTime = Date()

        let width = selectedResolution == "1080p" ? 1920 : 1280
        let height = selectedResolution == "1080p" ? 1080 : 720

        var env = ContinuityEnvelope(senderDeviceId: "macos-companion")
        env.sessionRequest = SessionRequest(
            type: .cameraStream,
            width: Int32(width),
            height: Int32(height),
            targetFps: 30,
            codec: "H264",
            cameraLens: selectedLens
        )
        session?.send(envelope: env)
        ConnectionAgent.shared.debugLog("CameraStreamManager requested camera stream (\(selectedLens), \(selectedResolution))")
    }

    public func stopStreaming(session: ContinuityNetworkSession?) {
        isStreaming = false
        currentFrame = nil
        fps = 0.0

        var env = ContinuityEnvelope(senderDeviceId: "macos-companion")
        env.sessionStop = SessionStop(sessionId: "camera", reason: "User stopped")
        session?.send(envelope: env)
        ConnectionAgent.shared.liveCameraFrame = nil
        ConnectionAgent.shared.debugLog("CameraStreamManager stopped camera stream")
    }

    public func toggleStreaming(session: ContinuityNetworkSession?) {
        if isStreaming {
            stopStreaming(session: session)
        } else {
            startStreaming(session: session)
        }
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
}
