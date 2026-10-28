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
    @Published public var zoomRatio: Float = 1.0
    @Published public var exposureCompensation: Int32 = 0
    @Published public var whiteBalance: String = "AUTO"
    @Published public var showGridOverlay: Bool = false
    @Published public var currentFrame: NSImage? = nil
    @Published public var fps: Double = 0.0
    @Published public var latencyMs: Double = 0.0
    @Published public var lastSnapshotPath: String? = nil

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

    public func sendCameraControl(
        lens: String? = nil,
        torch: Bool? = nil,
        zoomRatio: Float? = nil,
        exposureCompensation: Int32? = nil,
        whiteBalance: String? = nil,
        session: ContinuityNetworkSession?
    ) {
        var env = ContinuityEnvelope(senderDeviceId: "macos-companion")
        env.cameraControl = CameraControlRequest(
            lens: lens ?? selectedLens,
            torch: torch ?? isTorchOn,
            zoomRatio: zoomRatio ?? self.zoomRatio,
            exposureCompensation: exposureCompensation ?? self.exposureCompensation,
            whiteBalance: whiteBalance ?? self.whiteBalance
        )
        session?.send(envelope: env)
        ConnectionAgent.shared.debugLog("CameraStreamManager sent cameraControl (lens=\(lens ?? selectedLens), torch=\(torch ?? isTorchOn), zoom=\(zoomRatio ?? self.zoomRatio), ev=\(exposureCompensation ?? self.exposureCompensation))")
    }

    public func setTorch(enabled: Bool, session: ContinuityNetworkSession?) {
        self.isTorchOn = enabled
        sendCameraControl(torch: enabled, session: session)
    }

    public func setLens(lens: String, session: ContinuityNetworkSession?) {
        self.selectedLens = lens
        sendCameraControl(lens: lens, session: session)
    }

    public func setZoom(zoom: Float, session: ContinuityNetworkSession?) {
        self.zoomRatio = zoom
        sendCameraControl(zoomRatio: zoom, session: session)
    }

    public func setExposure(ev: Int32, session: ContinuityNetworkSession?) {
        self.exposureCompensation = ev
        sendCameraControl(exposureCompensation: ev, session: session)
    }

    public func setWhiteBalance(wb: String, session: ContinuityNetworkSession?) {
        self.whiteBalance = wb
        sendCameraControl(whiteBalance: wb, session: session)
    }

    public func takeSnapshot() -> URL? {
        guard let frame = currentFrame ?? ConnectionAgent.shared.liveCameraFrame,
              let tiffData = frame.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.95]) else {
            return nil
        }

        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!
        let continuityDir = pictures.appendingPathComponent("Continuity", isDirectory: true)
        try? FileManager.default.createDirectory(at: continuityDir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let filename = "Continuity_Photo_\(formatter.string(from: Date())).jpg"
        let destURL = continuityDir.appendingPathComponent(filename)

        do {
            try jpegData.write(to: destURL)
            self.lastSnapshotPath = destURL.path
            NSWorkspace.shared.activateFileViewerSelecting([destURL])
            return destURL
        } catch {
            return nil
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
