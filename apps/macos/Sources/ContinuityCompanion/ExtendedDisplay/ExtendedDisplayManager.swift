import Foundation
import AppKit
import CoreGraphics
import ContinuityProtocol

@MainActor
public final class ExtendedDisplayManager: ObservableObject {
    public static let shared = ExtendedDisplayManager()

    public static let EXTENDED_DISPLAY_TRANSFER_ID = "00000000-0000-0000-0000-00EXT_DISPLAY"

    @Published public var isStreaming: Bool = false
    @Published public var fps: Int = 30
    @Published public var quality: Float = 0.75

    private var captureTimer: Timer?
    private var sequenceNumber: UInt32 = 0

    private init() {}

    public func toggleExtendedDisplay(session: ContinuityNetworkSession?) {
        if isStreaming {
            stopStreaming(session: session)
        } else {
            startStreaming(session: session)
        }
    }

    public func startStreaming(session: ContinuityNetworkSession?) {
        guard !isStreaming else { return }
        let activeSession = session ?? ConnectionAgent.shared.activeSession
        guard let activeSession = activeSession else {
            ConnectionAgent.shared.debugLog("Extended Display: No active session")
            return
        }

        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }

        isStreaming = true
        sequenceNumber = 0

        // Notify Android device that extended display session is starting
        var req = ContinuityEnvelope(senderDeviceId: "macos-companion")
        req.sessionRequest = SessionRequest(sessionId: "ext_display", type: .extendedDisplay)
        activeSession.send(envelope: req)

        ConnectionAgent.shared.debugLog("Extended Display streaming started at \(fps) FPS")

        let interval = 1.0 / Double(fps)
        captureTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.captureAndSendFrame(session: activeSession)
            }
        }
    }

    public func stopStreaming(session: ContinuityNetworkSession?) {
        guard isStreaming else { return }
        isStreaming = false
        captureTimer?.invalidate()
        captureTimer = nil

        let activeSession = session ?? ConnectionAgent.shared.activeSession
        if let activeSession = activeSession {
            var stop = ContinuityEnvelope(senderDeviceId: "macos-companion")
            stop.sessionStop = SessionStop(sessionId: "ext_display")
            activeSession.send(envelope: stop)
        }

        ConnectionAgent.shared.debugLog("Extended Display streaming stopped")
    }

    private func captureAndSendFrame(session: ContinuityNetworkSession) {
        guard isStreaming else { return }

        // Capture main display
        let displayId = CGMainDisplayID()
        guard let imageRef = CGDisplayCreateImage(displayId) else { return }

        let rep = NSBitmapImageRep(cgImage: imageRef)
        guard let jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: quality]) else { return }

        sequenceNumber += 1

        // Send via binary chunk with extended display transfer ID
        let chunk = RawBinaryChunk(
            transferId: Self.EXTENDED_DISPLAY_TRANSFER_ID,
            chunkIndex: sequenceNumber,
            chunkTotal: 1,
            data: jpegData
        )
        session.send(binaryChunk: chunk)
    }

    /// Translates touch/stylus coordinate from Android back to macOS cursor and click
    public func handleRemoteInput(xRatio: Float, yRatio: Float, isDown: Bool) {
        guard let mainScreen = NSScreen.main else { return }
        let screenRect = mainScreen.frame
        let targetX = CGFloat(xRatio) * screenRect.width
        let targetY = CGFloat(1.0 - yRatio) * screenRect.height // Mac Cocoa coords are inverted Y

        let point = CGPoint(x: targetX, y: targetY)

        if isDown {
            let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
            moveEvent?.post(tap: .cghidEventTap)

            let clickDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
            clickDown?.post(tap: .cghidEventTap)
        } else {
            let clickUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
            clickUp?.post(tap: .cghidEventTap)
        }
    }
}
