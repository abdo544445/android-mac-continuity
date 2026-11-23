import Foundation
import AppKit
import CoreGraphics
import SwiftUI
import CGVirtualDisplayBridge

public enum VirtualDisplayPreset: String, CaseIterable, Identifiable, Sendable {
    case hd720 = "1280×720 (HD 16:9)"
    case tablet800 = "1280×800 (Tablet 16:10)"
    case macbook900 = "1440×900 (16:10)"
    case fhd1080 = "1920×1080 (Full HD 16:9)"
    case tablet1200 = "1920×1200 (Tablet 16:10)"
    case tabletNative = "2456×1600 (Huawei Tablet Native)"
    case qhd1440 = "2560×1440 (QHD 16:9)"
    case retina1600 = "2560×1600 (Retina 16:10)"
    case uhd4k = "3840×2160 (4K UHD)"

    public var id: String { rawValue }

    public var width: Int {
        switch self {
        case .hd720: return 1280
        case .tablet800: return 1280
        case .macbook900: return 1440
        case .fhd1080: return 1920
        case .tablet1200: return 1920
        case .tabletNative: return 2456
        case .qhd1440: return 2560
        case .retina1600: return 2560
        case .uhd4k: return 3840
        }
    }

    public var height: Int {
        switch self {
        case .hd720: return 720
        case .tablet800: return 800
        case .macbook900: return 900
        case .fhd1080: return 1080
        case .tablet1200: return 1200
        case .tabletNative: return 1600
        case .qhd1440: return 1440
        case .retina1600: return 1600
        case .uhd4k: return 2160
        }
    }
}

public extension NSScreen {
    var continuityDisplayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? kCGNullDirectDisplay
    }
}

/// Native macOS Virtual Display Engine powered by DeskPad's CGVirtualDisplay architecture.
/// Creates a true software-defined extended monitor recognized natively by macOS System Settings -> Displays.
@MainActor
public final class VirtualDisplayEngine: ObservableObject {
    public static let shared = VirtualDisplayEngine()

    @Published public var isActive: Bool = false
    @Published public var isSupported: Bool = ContinuityVirtualDisplayBridge.isSupported()
    @Published public var displayID: CGDirectDisplayID = kCGNullDirectDisplay
    @Published public var selectedPreset: VirtualDisplayPreset = .fhd1080
    @Published public var hiDPI: Bool = true
    @Published public var currentResolution: CGSize = CGSize(width: 1920, height: 1080)
    @Published public var currentScaleFactor: CGFloat = 1.0
    @Published public var isCursorOnVirtualDisplay: Bool = false
    @Published public var isPreviewWindowOpen: Bool = false
    @Published public var statusMessage: String = "Virtual Display Ready (DeskPad Engine)"

    private var bridge: ContinuityVirtualDisplayBridge?
    private var mouseTimer: Timer?
    private var screenObserver: NSObjectProtocol?
    private var previewWindowController: VirtualDisplayPreviewWindowController?

    private init() {
        setupScreenParameterObserver()
    }

    public func toggleVirtualDisplay() {
        if isActive {
            destroyVirtualDisplay()
        } else {
            createVirtualDisplay()
        }
    }

    @discardableResult
    public func createVirtualDisplay() -> Bool {
        guard isSupported else {
            statusMessage = "CGVirtualDisplay API unavailable on this macOS version"
            return false
        }
        if isActive, displayID != kCGNullDirectDisplay {
            return true
        }

        let newBridge = ContinuityVirtualDisplayBridge(
            name: "Continuity Display",
            maxPixelsWide: 5120,
            maxPixelsHigh: 2160,
            sizeInMillimeters: CGSize(width: 1600, height: 1000),
            vendorID: 0x3456,
            productID: 0x1234,
            serialNum: 0x0001
        ) { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleExternalTermination()
            }
        }

        guard let created = newBridge, created.isActive else {
            statusMessage = "Failed to instantiate macOS Virtual Display"
            ConnectionAgent.shared.debugLog("VirtualDisplayEngine: failed to create CGVirtualDisplay")
            return false
        }

        self.bridge = created
        self.displayID = created.displayID
        self.isActive = true

        applyPreset(selectedPreset, hiDPI: hiDPI)
        startMouseTracking()
        refreshScreenParameters()

        statusMessage = "Virtual Monitor Active (\(selectedPreset.width)×\(selectedPreset.height), ID \(created.displayID))"
        ConnectionAgent.shared.debugLog("VirtualDisplayEngine: created DeskPad virtual display ID=\(created.displayID) at \(selectedPreset.width)x\(selectedPreset.height)")
        return true
    }

    public func applyPreset(_ preset: VirtualDisplayPreset, hiDPI: Bool? = nil) {
        self.selectedPreset = preset
        if let hiDPI = hiDPI {
            self.hiDPI = hiDPI
        }
        guard let bridge = bridge, isActive else { return }

        // Put the chosen preset first so macOS adopts it immediately, followed by all DeskPad modes
        var specs: [ContinuityVirtualDisplayModeSpec] = [
            ContinuityVirtualDisplayModeSpec(width: UInt(preset.width), height: UInt(preset.height), refreshRate: 60.0)
        ]
        for other in VirtualDisplayPreset.allCases where other != preset {
            specs.append(ContinuityVirtualDisplayModeSpec(width: UInt(other.width), height: UInt(other.height), refreshRate: 60.0))
        }

        _ = bridge.applyModes(specs, hiDPI: self.hiDPI)
        self.currentResolution = CGSize(width: preset.width, height: preset.height)
        self.statusMessage = "Virtual Monitor Active (\(preset.width)×\(preset.height), ID \(displayID))"

        // Refresh actual macOS display metrics shortly after mode switch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.refreshScreenParameters()
        }
    }

    public func destroyVirtualDisplay() {
        closePreviewWindow()
        stopMouseTracking()
        bridge?.destroy()
        bridge = nil
        displayID = kCGNullDirectDisplay
        isActive = false
        isCursorOnVirtualDisplay = false
        statusMessage = "Virtual Display Stopped"
        ConnectionAgent.shared.debugLog("VirtualDisplayEngine: destroyed virtual display")
    }

    public func openPreviewWindow() {
        if !isActive {
            guard createVirtualDisplay() else { return }
        }
        if previewWindowController == nil {
            previewWindowController = VirtualDisplayPreviewWindowController()
            previewWindowController?.onClose = { [weak self] in
                Task { @MainActor [weak self] in
                    self?.isPreviewWindowOpen = false
                }
            }
        }
        previewWindowController?.showWindow(nil)
        previewWindowController?.window?.makeKeyAndOrderFront(nil)
        isPreviewWindowOpen = true
    }

    public func closePreviewWindow() {
        previewWindowController?.close()
        previewWindowController = nil
        isPreviewWindowOpen = false
    }

    public func moveCursorToVirtualDisplay(normalizedX: CGFloat, normalizedY: CGFloat) {
        guard isActive, displayID != kCGNullDirectDisplay else { return }
        let bounds = CGDisplayBounds(displayID)
        let localX = normalizedX * bounds.width
        let localY = normalizedY * bounds.height
        CGDisplayMoveCursorToPoint(displayID, CGPoint(x: localX, y: localY))
    }

    public func virtualDisplayBounds() -> CGRect? {
        guard isActive, displayID != kCGNullDirectDisplay else { return nil }
        let bounds = CGDisplayBounds(displayID)
        return bounds.isEmpty ? nil : bounds
    }

    public func openSystemDisplaySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    private func handleExternalTermination() {
        closePreviewWindow()
        stopMouseTracking()
        bridge = nil
        displayID = kCGNullDirectDisplay
        isActive = false
        isCursorOnVirtualDisplay = false
        statusMessage = "Virtual Display terminated by macOS"
    }

    private func setupScreenParameterObserver() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: NSApplication.shared,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshScreenParameters()
            }
        }
    }

    private func refreshScreenParameters() {
        guard isActive, displayID != kCGNullDirectDisplay else { return }
        if let screen = NSScreen.screens.first(where: { $0.continuityDisplayID == displayID }) {
            currentResolution = screen.frame.size
            currentScaleFactor = screen.backingScaleFactor
        }
    }

    private func startMouseTracking() {
        stopMouseTracking()
        mouseTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isActive, self.displayID != kCGNullDirectDisplay else { return }
                let mouseLocation = NSEvent.mouseLocation
                let activeScreen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
                let within = activeScreen?.continuityDisplayID == self.displayID
                if self.isCursorOnVirtualDisplay != within {
                    self.isCursorOnVirtualDisplay = within
                    self.previewWindowController?.updateHighlight(isActive: within)
                }
            }
        }
    }

    private func stopMouseTracking() {
        mouseTimer?.invalidate()
        mouseTimer = nil
    }
}

/// DeskPad-style floating preview window showing the live virtual display right on your Mac,
/// highlighting the titlebar when your cursor enters the virtual monitor and supporting click-to-teleport.
@MainActor
public final class VirtualDisplayPreviewWindowController: NSWindowController, NSWindowDelegate {
    public var onClose: (() -> Void)?

    public init() {
        let initialSize = VirtualDisplayEngine.shared.currentResolution
        let aspect = initialSize.height > 0 ? (initialSize.width / initialSize.height) : (16.0 / 9.0)
        let windowWidth: CGFloat = 800
        let windowHeight: CGFloat = windowWidth / aspect

        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DeskPad Virtual Display Preview"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentAspectRatio = NSSize(width: aspect, height: 1.0)
        window.backgroundColor = NSColor.windowBackgroundColor
        window.contentView = NSHostingView(rootView: VirtualDisplayPreviewView())

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func updateHighlight(isActive: Bool) {
        window?.backgroundColor = isActive ? NSColor.systemBlue.withAlphaComponent(0.85) : NSColor.windowBackgroundColor
        window?.title = isActive ? "DeskPad Virtual Display — Cursor Active" : "DeskPad Virtual Display Preview"
        if isActive {
            window?.orderFrontRegardless()
        }
    }

    public func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}

private struct VirtualDisplayPreviewView: View {
    @ObservedObject var virtualDisplay = VirtualDisplayEngine.shared
    @ObservedObject var extManager = ExtendedDisplayManager.shared

    var body: some View {
        ZStack {
            Color.black

            if let previewImg = extManager.latestPreviewImage {
                GeometryReader { geo in
                    Image(nsImage: previewImg)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            let nx = max(0, min(1, location.x / max(1, geo.size.width)))
                            let ny = max(0, min(1, location.y / max(1, geo.size.height)))
                            virtualDisplay.moveCursorToVirtualDisplay(normalizedX: nx, normalizedY: ny)
                        }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "display.2")
                        .font(.system(size: 44))
                        .foregroundColor(.blue)
                    Text("Virtual Display Active (\(Int(virtualDisplay.currentResolution.width))×\(Int(virtualDisplay.currentResolution.height)))")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("Start Streaming or click below to view live frames.\nDrag any macOS window past your screen edge onto this virtual monitor.")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Button("Start Live Preview Capture") {
                        extManager.startCaptureOnly()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if virtualDisplay.isCursorOnVirtualDisplay {
                VStack {
                    HStack {
                        Label("Cursor inside Virtual Display", systemImage: "cursorarrow.motionlines")
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.85))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        Spacer()
                    }
                    .padding(10)
                    Spacer()
                }
            }
        }
    }
}
