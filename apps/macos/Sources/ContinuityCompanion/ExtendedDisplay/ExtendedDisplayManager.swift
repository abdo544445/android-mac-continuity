import Foundation
import AppKit
import CoreGraphics
import CoreImage
import CoreMedia
import ScreenCaptureKit
import ContinuityProtocol

public enum DisplaySourceMode: String, CaseIterable, Identifiable, Sendable {
    case virtualDisplay = "Virtual Display (DeskPad)"
    case entireScreen = "Entire Screen"
    case singleWindow = "Single App Window"

    public var id: String { rawValue }
}

public struct ShareableDisplayOption: Identifiable, Equatable, Sendable {
    public let id: CGDirectDisplayID
    public let title: String
    public let width: Int
    public let height: Int
    public let isVirtual: Bool
}

public struct ShareableWindowOption: Identifiable, Equatable, Sendable {
    public let id: CGWindowID
    public let appName: String
    public let windowTitle: String
    public let frame: CGRect

    public var displayLabel: String {
        windowTitle.isEmpty ? appName : "\(appName) — \(windowTitle)"
    }
}

/// Unified Extended Display & Screen Sharing Manager uniting:
/// 1. DeskPad Virtual Display (true macOS software secondary monitor via CGVirtualDisplay)
/// 2. Deskreen Universal Web Viewer & Single-Window Sharing (via ScreenCaptureKit + DeskreenWebHost)
/// 3. Native Continuity Android Tablet/Phone Secondary Display (via RawBinaryChunk)
@MainActor
public final class ExtendedDisplayManager: ObservableObject {
    public static let shared = ExtendedDisplayManager()

    // Exact 36-byte transfer ID matching FrameEncoder's 36-byte fixed UUID slot
    public static let EXTENDED_DISPLAY_TRANSFER_ID = "00000000-0000-0000-0000-0EXT_DISPLAY"

    @Published public var isStreaming: Bool = false        // True when streaming to Android Continuity App
    @Published public var isCaptureActive: Bool = false    // True whenever SCStream is capturing (Android, Web, or Preview)
    @Published public var fps: Int = 30
    @Published public var quality: Float = 0.75
    @Published public var liveFps: Double = 0.0
    @Published public var captureStatus: String = "Idle"
    @Published public var sourceMode: DisplaySourceMode = .virtualDisplay
    @Published public var availableDisplays: [ShareableDisplayOption] = []
    @Published public var availableWindows: [ShareableWindowOption] = []
    @Published public var selectedDisplayID: CGDirectDisplayID = CGMainDisplayID()
    @Published public var selectedWindowID: CGWindowID? = nil
    @Published public var latestPreviewImage: NSImage? = nil

    public var activeSourceDescription: String {
        switch sourceMode {
        case .virtualDisplay:
            let vd = VirtualDisplayEngine.shared
            return "Virtual Display (\(Int(vd.currentResolution.width))×\(Int(vd.currentResolution.height)))"
        case .entireScreen:
            if let d = availableDisplays.first(where: { $0.id == selectedDisplayID }) {
                return d.title
            }
            return "Main Screen"
        case .singleWindow:
            if let w = availableWindows.first(where: { $0.id == selectedWindowID }) {
                return w.displayLabel
            }
            return "App Window"
        }
    }

    private var scStream: SCStream?
    private var streamOutput: CaptureStreamOutput?
    private var activeAndroidSession: ContinuityNetworkSession?
    private var isSendingAndroidFrame: Bool = false
    private var lastAndroidSendStartedAt: Date = .distantPast
    private var sequenceNumber: UInt32 = 0
    private var frameCounterForFps: Int = 0
    private var lastFpsSample = Date()
    private var activeTargetBounds: CGRect = CGDisplayBounds(CGMainDisplayID())

    private init() {
        Task {
            await refreshShareableSources()
        }
    }

    // MARK: - Source Discovery (Displays + Windows via ScreenCaptureKit)

    public func refreshShareableSources() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let virtualID = VirtualDisplayEngine.shared.displayID

            let displays: [ShareableDisplayOption] = content.displays.enumerated().map { idx, disp in
                let isVirtual = (virtualID != kCGNullDirectDisplay && disp.displayID == virtualID)
                let label = isVirtual
                    ? "Continuity Virtual Display (\(disp.width)×\(disp.height))"
                    : (disp.displayID == CGMainDisplayID()
                        ? "Main Display (\(disp.width)×\(disp.height))"
                        : "External Display \(idx + 1) (\(disp.width)×\(disp.height))")
                return ShareableDisplayOption(
                    id: disp.displayID,
                    title: label,
                    width: disp.width,
                    height: disp.height,
                    isVirtual: isVirtual
                )
            }
            self.availableDisplays = displays
            if !displays.contains(where: { $0.id == self.selectedDisplayID }) {
                self.selectedDisplayID = displays.first(where: { !$0.isVirtual })?.id ?? CGMainDisplayID()
            }

            let ownBundle = Bundle.main.bundleIdentifier
            let windows: [ShareableWindowOption] = content.windows.compactMap { win in
                guard win.isOnScreen,
                      win.frame.width >= 200,
                      win.frame.height >= 150,
                      let app = win.owningApplication,
                      app.bundleIdentifier != ownBundle,
                      !app.applicationName.isEmpty
                else { return nil }
                let title = (win.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                // Filter out invisible system chrome windows with empty titles
                if title.isEmpty && (app.applicationName == "Window Server" || app.applicationName == "Dock" || app.applicationName == "Control Center") {
                    return nil
                }
                return ShareableWindowOption(
                    id: win.windowID,
                    appName: app.applicationName,
                    windowTitle: title,
                    frame: win.frame
                )
            }.sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }

            self.availableWindows = windows
            if let curWin = self.selectedWindowID, !windows.contains(where: { $0.id == curWin }) {
                self.selectedWindowID = windows.first?.id
            } else if self.selectedWindowID == nil {
                self.selectedWindowID = windows.first?.id
            }
        } catch {
            self.captureStatus = "Screen Recording permission required in System Settings"
            ConnectionAgent.shared.debugLog("ExtendedDisplayManager: SCShareableContent failed: \(error.localizedDescription)")
        }
    }

    public func switchSourceMode(_ mode: DisplaySourceMode) {
        self.sourceMode = mode
        if isCaptureActive {
            Task {
                await restartCapturePipeline()
            }
        }
    }

    public func updateFPS(_ newFps: Int) {
        self.fps = newFps
        if isCaptureActive {
            Task {
                await restartCapturePipeline()
            }
        }
    }

    // MARK: - Streaming Lifecycle

    public func toggleExtendedDisplay(session: ContinuityNetworkSession?) {
        if isStreaming {
            stopStreaming(session: session)
        } else {
            startStreaming(session: session)
        }
    }

    /// Starts streaming to the connected Android Continuity app (also feeds Deskreen Web Host & DeskPad Preview if active).
    public func startStreaming(session: ContinuityNetworkSession?) {
        guard !isStreaming else { return }
        let activeSession = session ?? ConnectionAgent.shared.activeSession
        guard let activeSession = activeSession else {
            captureStatus = "No Android device connected via Continuity"
            ConnectionAgent.shared.debugLog("Extended Display: No active Android session")
            return
        }

        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }

        self.activeAndroidSession = activeSession
        self.isStreaming = true
        self.isSendingAndroidFrame = false
        self.lastAndroidSendStartedAt = .distantPast
        self.sequenceNumber = 0

        // Notify Android device that extended display session is starting
        var req = ContinuityEnvelope(senderDeviceId: "macos-companion")
        req.sessionRequest = SessionRequest(sessionId: "ext_display", type: .extendedDisplay)
        activeSession.send(envelope: req)

        ConnectionAgent.shared.debugLog("Extended Display streaming to Android started (\(activeSourceDescription) @ \(fps) FPS)")

        Task {
            await ensureCaptureRunning()
        }
    }

    /// Starts ScreenCaptureKit without requiring an Android session (for Deskreen Web Viewers or DeskPad Preview Window).
    public func startCaptureOnly() {
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
        Task {
            await ensureCaptureRunning()
        }
    }

    public func stopStreaming(session: ContinuityNetworkSession?) {
        guard isStreaming else { return }
        isStreaming = false
        isSendingAndroidFrame = false
        let activeSession = session ?? activeAndroidSession ?? ConnectionAgent.shared.activeSession
        activeAndroidSession = nil

        if let activeSession = activeSession {
            var stop = ContinuityEnvelope(senderDeviceId: "macos-companion")
            stop.sessionStop = SessionStop(sessionId: "ext_display")
            activeSession.send(envelope: stop)
        }

        ConnectionAgent.shared.debugLog("Extended Display streaming to Android stopped")

        // Keep capture alive only if Deskreen web viewers or DeskPad preview are still active
        if !DeskreenWebHost.shared.isRunning && !VirtualDisplayEngine.shared.isPreviewWindowOpen {
            Task {
                await stopCapturePipeline()
            }
        }
    }

    public func stopAllCapture() {
        if isStreaming {
            stopStreaming(session: activeAndroidSession)
        }
        Task {
            await stopCapturePipeline()
        }
    }

    private func ensureCaptureRunning() async {
        if isCaptureActive, scStream != nil {
            return
        }
        await startCapturePipeline()
    }

    public func restartCapturePipeline() async {
        await stopCapturePipeline()
        await startCapturePipeline()
    }

    private func startCapturePipeline() async {
        // If user chose DeskPad Virtual Display mode and hasn't created one yet, spin it up automatically!
        if sourceMode == .virtualDisplay && !VirtualDisplayEngine.shared.isActive {
            let created = VirtualDisplayEngine.shared.createVirtualDisplay()
            if created {
                // Give macOS WindowServer a brief moment to register the new CGVirtualDisplay in SCShareableContent
                try? await Task.sleep(nanoseconds: 450_000_000)
            }
        }

        await refreshShareableSources()

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let filter: SCContentFilter
            let targetWidth: Int
            let targetHeight: Int

            switch sourceMode {
            case .virtualDisplay:
                let vdID = VirtualDisplayEngine.shared.displayID
                if vdID != kCGNullDirectDisplay,
                   let scDisplay = content.displays.first(where: { $0.displayID == vdID }) {
                    filter = SCContentFilter(display: scDisplay, excludingWindows: [])
                    targetWidth = min(scDisplay.width, 1920)
                    targetHeight = min(scDisplay.height, 1200)
                    activeTargetBounds = CGDisplayBounds(vdID)
                    captureStatus = "Capturing DeskPad Virtual Display (\(scDisplay.width)×\(scDisplay.height))"
                } else if let fallback = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first {
                    filter = SCContentFilter(display: fallback, excludingWindows: [])
                    targetWidth = min(fallback.width, 1920)
                    targetHeight = min(fallback.height, 1080)
                    activeTargetBounds = CGDisplayBounds(fallback.displayID)
                    captureStatus = "Fallback: Capturing Main Display"
                } else {
                    captureStatus = "No display available to capture"
                    return
                }

            case .entireScreen:
                let targetID = selectedDisplayID
                guard let scDisplay = content.displays.first(where: { $0.displayID == targetID }) ?? content.displays.first else {
                    captureStatus = "Selected display unavailable"
                    return
                }
                filter = SCContentFilter(display: scDisplay, excludingWindows: [])
                targetWidth = min(scDisplay.width, 1920)
                targetHeight = min(scDisplay.height, 1200)
                activeTargetBounds = CGDisplayBounds(scDisplay.displayID)
                captureStatus = "Capturing Display (\(scDisplay.width)×\(scDisplay.height))"

            case .singleWindow:
                guard let winID = selectedWindowID,
                      let scWindow = content.windows.first(where: { $0.windowID == winID }) else {
                    captureStatus = "Select an open application window to share"
                    return
                }
                filter = SCContentFilter(desktopIndependentWindow: scWindow)
                targetWidth = max(320, min(Int(scWindow.frame.width), 1920))
                targetHeight = max(240, min(Int(scWindow.frame.height), 1200))
                activeTargetBounds = scWindow.frame
                captureStatus = "Sharing Window: \(scWindow.owningApplication?.applicationName ?? "App")"
            }

            let maxDimW = AdvancedHostManager.shared.isUsbTunnelActive ? 1600 : 1280
            let maxDimH = AdvancedHostManager.shared.isUsbTunnelActive ? 1000 : 800
            let scaled = Self.fitSize(width: targetWidth, height: targetHeight, maxW: maxDimW, maxH: maxDimH)

            let config = SCStreamConfiguration()
            config.width = scaled.width
            config.height = scaled.height
            config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(10, fps)))
            config.showsCursor = true
            config.capturesAudio = false
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.queueDepth = 2

            let output = CaptureStreamOutput(
                qualityProvider: { [weak self] in
                    self?.currentQualityValue ?? 0.75
                },
                onFrameEncoded: { [weak self] jpegData in
                    self?.dispatchEncodedFrame(jpegData)
                }
            )

            let stream = SCStream(filter: filter, configuration: config, delegate: nil)
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.processingQueue)
            try await stream.startCapture()

            self.streamOutput = output
            self.scStream = stream
            self.isCaptureActive = true
            self.frameCounterForFps = 0
            self.lastFpsSample = Date()
            ConnectionAgent.shared.debugLog("ScreenCaptureKit stream started: \(captureStatus) @ \(fps) FPS")
        } catch {
            self.captureStatus = "Capture failed: \(error.localizedDescription)"
            self.isCaptureActive = false
            ConnectionAgent.shared.debugLog("ExtendedDisplayManager SCStream error: \(error.localizedDescription)")
        }
    }

    private static func fitSize(width: Int, height: Int, maxW: Int, maxH: Int) -> (width: Int, height: Int) {
        guard width > 0, height > 0 else { return (maxW, maxH) }
        let ratio = min(1.0, min(Double(maxW) / Double(width), Double(maxH) / Double(height)))
        let w = max(320, Int((Double(width) * ratio).rounded()) & ~1)
        let h = max(240, Int((Double(height) * ratio).rounded()) & ~1)
        return (w, h)
    }

    private func stopCapturePipeline() async {
        if let stream = scStream {
            try? await stream.stopCapture()
        }
        scStream = nil
        streamOutput = nil
        isCaptureActive = false
        isSendingAndroidFrame = false
        liveFps = 0
        latestPreviewImage = nil
        captureStatus = "Idle"
    }

    // Thread-safe atomic mirror of quality for background JPEG encoder
    private nonisolated var currentQualityValue: Float {
        qualityLock.lock()
        defer { qualityLock.unlock() }
        return _atomicQuality
    }
    private let qualityLock = NSLock()
    private nonisolated(unsafe) var _atomicQuality: Float = 0.75

    public func setQuality(_ newValue: Float) {
        self.quality = newValue
        qualityLock.lock()
        _atomicQuality = newValue
        qualityLock.unlock()
    }

    private nonisolated func dispatchEncodedFrame(_ jpegData: Data) {
        Task { @MainActor [weak self] in
            guard let self = self, self.isCaptureActive else { return }

            // 1. Push to Native Android Continuity App if streaming (always prefer current live session + watchdog-protected backpressure)
            if self.isStreaming,
               let session = ConnectionAgent.shared.activeSession ?? self.activeAndroidSession {
                if self.isSendingAndroidFrame && Date().timeIntervalSince(self.lastAndroidSendStartedAt) > 1.5 {
                    self.isSendingAndroidFrame = false
                }
                if !self.isSendingAndroidFrame {
                    self.isSendingAndroidFrame = true
                    self.lastAndroidSendStartedAt = Date()
                    self.sequenceNumber &+= 1
                    let chunk = RawBinaryChunk(
                        transferId: Self.EXTENDED_DISPLAY_TRANSFER_ID,
                        chunkIndex: self.sequenceNumber,
                        chunkTotal: 1,
                        data: jpegData
                    )
                    session.send(binaryChunk: chunk) { [weak self] _ in
                        Task { @MainActor [weak self] in
                            self?.isSendingAndroidFrame = false
                        }
                    }
                }
            }

            // 2. Broadcast to all Deskreen Web Browser Viewers
            if DeskreenWebHost.shared.isRunning {
                DeskreenWebHost.shared.broadcastFrame(jpegData)
            }

            // 3. Feed DeskPad Local Preview Window when open
            if VirtualDisplayEngine.shared.isPreviewWindowOpen {
                if let img = NSImage(data: jpegData) {
                    self.latestPreviewImage = img
                }
            }

            // Update live FPS counter
            self.frameCounterForFps += 1
            let now = Date()
            let elapsed = now.timeIntervalSince(self.lastFpsSample)
            if elapsed >= 1.0 {
                self.liveFps = Double(self.frameCounterForFps) / elapsed
                self.frameCounterForFps = 0
                self.lastFpsSample = now
            }
        }
    }

    // MARK: - Accurate Remote Touch / Mouse Input Mapping (Android + Deskreen Web Viewer)

    private func resolveQuartzPoint(xRatio: Float, yRatio: Float) -> CGPoint {
        var bounds = activeTargetBounds
        if sourceMode == .virtualDisplay, let vdBounds = VirtualDisplayEngine.shared.virtualDisplayBounds() {
            bounds = vdBounds
        } else if sourceMode == .entireScreen {
            bounds = CGDisplayBounds(selectedDisplayID)
        }
        if bounds.isEmpty {
            bounds = CGDisplayBounds(CGMainDisplayID())
        }
        // CGEvent uses top-left Quartz global display coordinates directly!
        let targetX = bounds.origin.x + CGFloat(max(0, min(1, xRatio))) * bounds.width
        let targetY = bounds.origin.y + CGFloat(max(0, min(1, yRatio))) * bounds.height
        return CGPoint(x: targetX, y: targetY)
    }

    /// Handles touch/pointer events from Android Extended Display screen
    public func handleRemoteInput(xRatio: Float, yRatio: Float, action: InputAction) {
        let point = resolveQuartzPoint(xRatio: xRatio, yRatio: yRatio)
        switch action {
        case .down:
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
            CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        case .move:
            CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        case .up:
            CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        default:
            break
        }
    }

    /// Backwards-compatible overload
    public func handleRemoteInput(xRatio: Float, yRatio: Float, isDown: Bool) {
        handleRemoteInput(xRatio: xRatio, yRatio: yRatio, action: isDown ? .down : .up)
    }

    /// Handles interactive mouse/touch/scroll input from Deskreen Browser Viewers
    public func handleWebInput(type: String, xRatio: Float, yRatio: Float, deltaY: Float = 0) {
        let point = resolveQuartzPoint(xRatio: xRatio, yRatio: yRatio)
        switch type {
        case "down":
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
            CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        case "move":
            CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        case "up":
            CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        case "rightclick":
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .right)?.post(tap: .cghidEventTap)
            CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: point, mouseButton: .right)?.post(tap: .cghidEventTap)
            CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp, mouseCursorPosition: point, mouseButton: .right)?.post(tap: .cghidEventTap)
        case "scroll":
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
            let lines = Int32((-deltaY / 25.0).rounded())
            if lines != 0 {
                CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0)?.post(tap: .cghidEventTap)
            }
        default:
            break
        }
    }
}

/// Hardware-accelerated ScreenCaptureKit sample output encoder using GPU CIContext JPEG compression.
private final class CaptureStreamOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    let processingQueue = DispatchQueue(label: "com.continuity.screencapture.encode", qos: .userInteractive)
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private let qualityProvider: () -> Float
    private let onFrameEncoded: (Data) -> Void

    init(qualityProvider: @escaping () -> Float, onFrameEncoded: @escaping (Data) -> Void) {
        self.qualityProvider = qualityProvider
        self.onFrameEncoded = onFrameEncoded
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              CMSampleBufferIsValid(sampleBuffer),
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        let quality = max(0.35, min(0.95, qualityProvider()))
        let options: [CIImageRepresentationOption: Any] = [
            kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality
        ]
        if let jpegData = ciContext.jpegRepresentation(of: ciImage, colorSpace: colorSpace, options: options) {
            onFrameEncoded(jpegData)
        }
    }
}
