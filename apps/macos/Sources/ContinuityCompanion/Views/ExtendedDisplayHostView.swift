import SwiftUI
import AppKit
import CoreImage.CIFilterBuiltins
import ContinuityProtocol

public struct ExtendedDisplayHostView: View {
    @ObservedObject var extManager = ExtendedDisplayManager.shared
    @ObservedObject var virtualDisplay = VirtualDisplayEngine.shared
    @ObservedObject var webHost = DeskreenWebHost.shared
    @ObservedObject var agent = ConnectionAgent.shared
    @ObservedObject var universalControl = UniversalControlManager.shared

    @State private var copiedURL = false

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 10) {
                            Text("Extended Display & Universal Web Screen")
                                .font(.title2)
                                .fontWeight(.bold)
                            if extManager.isCaptureActive {
                                Text(String(format: "LIVE • %.0f FPS", extManager.liveFps))
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.green.opacity(0.2))
                                    .foregroundColor(.green)
                                    .cornerRadius(6)
                            }
                        }
                        Text("Powered by DeskPad (native macOS Virtual Display) & Deskreen (any browser / single-window streaming).")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 16)

                Divider()

                // 1. DeskPad Virtual Monitor Card
                deskPadVirtualMonitorCard

                // 2. Deskreen Capture Source Selector (Virtual Display / Screen / Single App Window)
                captureSourceCard

                // 3. Deskreen Universal Web Display Server Card (QR Code + Any Browser + Approval Queue)
                deskreenWebHostCard

                // 4. Native Android Continuity App Stream Card
                androidNativeStreamCard

                // 5. Universal Control Card
                universalControlCard
            }
            .padding(.bottom, 28)
        }
        .onAppear {
            Task {
                await extManager.refreshShareableSources()
            }
        }
    }

    // MARK: - 1. DeskPad Virtual Monitor Card

    private var deskPadVirtualMonitorCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                Image(systemName: virtualDisplay.isActive ? "display.2" : "display")
                    .font(.system(size: 36))
                    .foregroundColor(virtualDisplay.isActive ? .blue : .secondary)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Virtual Secondary Monitor (DeskPad)")
                            .font(.headline)
                        if virtualDisplay.isActive {
                            Text("ACTIVE")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.2))
                                .foregroundColor(.blue)
                                .cornerRadius(4)
                        }
                        if virtualDisplay.isCursorOnVirtualDisplay {
                            Label("Cursor Inside", systemImage: "cursorarrow.motionlines")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.2))
                                .foregroundColor(.green)
                                .cornerRadius(4)
                        }
                    }
                    Text(virtualDisplay.statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    if virtualDisplay.isActive {
                        virtualDisplay.destroyVirtualDisplay()
                    } else {
                        _ = virtualDisplay.createVirtualDisplay()
                        Task {
                            try? await Task.sleep(nanoseconds: 450_000_000)
                            await extManager.refreshShareableSources()
                        }
                    }
                } label: {
                    Label(
                        virtualDisplay.isActive ? "Remove Virtual Display" : "Create Virtual Display",
                        systemImage: virtualDisplay.isActive ? "minus.rectangle.fill" : "plus.rectangle.on.rectangle"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(virtualDisplay.isActive ? .orange : .blue)
                .disabled(!virtualDisplay.isSupported)
            }

            HStack(spacing: 16) {
                Picker("Resolution", selection: Binding(
                    get: { virtualDisplay.selectedPreset },
                    set: { preset in
                        virtualDisplay.applyPreset(preset)
                        if extManager.isCaptureActive && extManager.sourceMode == .virtualDisplay {
                            Task {
                                try? await Task.sleep(nanoseconds: 400_000_000)
                                await extManager.restartCapturePipeline()
                            }
                        }
                    }
                )) {
                    ForEach(VirtualDisplayPreset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .frame(width: 260)

                Toggle("Retina HiDPI", isOn: Binding(
                    get: { virtualDisplay.hiDPI },
                    set: { virtualDisplay.applyPreset(virtualDisplay.selectedPreset, hiDPI: $0) }
                ))
                .toggleStyle(.switch)

                Spacer()

                Button {
                    if virtualDisplay.isPreviewWindowOpen {
                        virtualDisplay.closePreviewWindow()
                    } else {
                        virtualDisplay.openPreviewWindow()
                        extManager.startCaptureOnly()
                    }
                } label: {
                    Label(
                        virtualDisplay.isPreviewWindowOpen ? "Close Preview" : "DeskPad Preview",
                        systemImage: "macwindow"
                    )
                }
                .buttonStyle(.bordered)

                Button {
                    virtualDisplay.openSystemDisplaySettings()
                } label: {
                    Label("Arrange Displays", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(virtualDisplay.isActive ? Color.blue.opacity(0.35) : Color.clear, lineWidth: 1)
        )
        .padding(.horizontal)
    }

    // MARK: - 2. Capture Source Selector Card (Deskreen-style)

    private var captureSourceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("What to Share (Deskreen Source Selector)", systemImage: "rectangle.on.rectangle.angled")
                    .font(.headline)
                Spacer()
                Text(extManager.captureStatus)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button {
                    Task { await extManager.refreshShareableSources() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Picker("Source Mode", selection: Binding(
                get: { extManager.sourceMode },
                set: { extManager.switchSourceMode($0) }
            )) {
                ForEach(DisplaySourceMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if extManager.sourceMode == .entireScreen {
                Picker("Display", selection: Binding(
                    get: { extManager.selectedDisplayID },
                    set: { newID in
                        extManager.selectedDisplayID = newID
                        if extManager.isCaptureActive {
                            Task { await extManager.restartCapturePipeline() }
                        }
                    }
                )) {
                    ForEach(extManager.availableDisplays) { disp in
                        Text(disp.title).tag(disp.id)
                    }
                }
                .frame(maxWidth: 420)
            } else if extManager.sourceMode == .singleWindow {
                if extManager.availableWindows.isEmpty {
                    Text("No shareable application windows detected. Open an app window and click Refresh.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Picker("App Window", selection: Binding(
                        get: { extManager.selectedWindowID ?? extManager.availableWindows.first?.id ?? 0 },
                        set: { newWin in
                            extManager.selectedWindowID = newWin
                            if extManager.isCaptureActive {
                                Task { await extManager.restartCapturePipeline() }
                            }
                        }
                    )) {
                        ForEach(extManager.availableWindows) { win in
                            Text(win.displayLabel).tag(win.id)
                        }
                    }
                    .frame(maxWidth: 520)
                }
            } else {
                Text("Shares your independent DeskPad Virtual Monitor — drag any macOS app window onto it to extend your workspace without mirroring your main screen.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            HStack(spacing: 20) {
                Picker("Framerate", selection: Binding(
                    get: { extManager.fps },
                    set: { extManager.updateFPS($0) }
                )) {
                    Text("15 FPS (Low BW)").tag(15)
                    Text("30 FPS (Balanced)").tag(30)
                    Text("60 FPS (Ultra Smooth)").tag(60)
                }
                .frame(width: 210)

                HStack(spacing: 8) {
                    Text("Quality")
                        .font(.subheadline)
                    Slider(value: Binding(
                        get: { extManager.quality },
                        set: { extManager.setQuality($0) }
                    ), in: 0.4...0.98, step: 0.02)
                    .frame(width: 150)
                    Text("\(Int(extManager.quality * 100))%")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 38)
                }

                Toggle("Hardware H.264", isOn: $extManager.useHardwareH264)
                    .toggleStyle(.switch)
                    .help("Uses Apple VideoToolbox hardware H.264 + Android MediaCodec for crisp 60 FPS Display P3 streaming")

                Spacer()
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    // MARK: - 3. Deskreen Universal Web Display Server Card

    private var deskreenWebHostCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                Image(systemName: "globe.badge.chevron.backward")
                    .font(.system(size: 36))
                    .foregroundColor(.indigo)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Universal Web Display (Deskreen Engine)")
                            .font(.headline)
                        if webHost.isRunning {
                            Text("LIVE • \(webHost.activeStreamCount) VIEWER\(webHost.activeStreamCount == 1 ? "" : "S")")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.2))
                                .foregroundColor(.green)
                                .cornerRadius(4)
                        }
                    }
                    Text("Turn ANY device with a web browser (iPad, Huawei/Android tablet, Windows PC, Smart TV) into a secondary screen — zero app install required.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    if webHost.isRunning {
                        webHost.stop()
                    } else {
                        webHost.start()
                        extManager.startCaptureOnly()
                    }
                } label: {
                    Label(
                        webHost.isRunning ? "Stop Web Display" : "Start Web Display",
                        systemImage: webHost.isRunning ? "stop.circle.fill" : "play.circle.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(webHost.isRunning ? .red : .indigo)
            }

            if webHost.isRunning {
                Divider()

                HStack(alignment: .top, spacing: 20) {
                    // QR Code
                    if let qrImage = generateQRCode(from: webHost.shareURL) {
                        VStack(spacing: 6) {
                            Image(nsImage: qrImage)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 132, height: 132)
                                .padding(8)
                                .background(Color.white)
                                .cornerRadius(10)
                            Text("Scan with any camera")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Open this URL on any device on your Wi-Fi:")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        HStack {
                            Text(webHost.shareURL)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(NSColor.textBackgroundColor))
                                .cornerRadius(6)

                            Button {
                                webHost.copyShareURL()
                                copiedURL = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    copiedURL = false
                                }
                            } label: {
                                Label(copiedURL ? "Copied!" : "Copy", systemImage: copiedURL ? "checkmark" : "doc.on.doc")
                            }
                            .buttonStyle(.bordered)

                            Button {
                                webHost.openInLocalBrowser()
                            } label: {
                                Label("Test in Browser", systemImage: "safari")
                            }
                            .buttonStyle(.bordered)
                        }

                        HStack(spacing: 18) {
                            Toggle("Auto-Approve Local Wi-Fi Devices", isOn: $webHost.autoApproveLAN)
                                .toggleStyle(.switch)
                            Toggle("Allow Remote Touch / Mouse", isOn: $webHost.allowBrowserTouchInput)
                                .toggleStyle(.switch)
                        }
                        .font(.caption)

                        // Connected Web Viewers Approval Queue
                        if !webHost.connectedViewers.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Connected Browser Viewers")
                                    .font(.caption.bold())
                                    .foregroundColor(.secondary)

                                ForEach(webHost.connectedViewers) { viewer in
                                    HStack {
                                        Image(systemName: "laptopcomputer.and.iphone")
                                            .foregroundColor(viewer.status == .approved ? .green : (viewer.status == .pending ? .orange : .red))
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(viewer.deviceLabel)
                                                .font(.caption.bold())
                                            Text("\(viewer.ipAddress) • \(viewer.status.rawValue)")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        if viewer.status == .pending {
                                            Button("Allow") {
                                                webHost.approveViewer(id: viewer.id)
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .tint(.green)
                                            .controlSize(.small)

                                            Button("Deny") {
                                                webHost.denyViewer(id: viewer.id)
                                            }
                                            .buttonStyle(.bordered)
                                            .tint(.red)
                                            .controlSize(.small)
                                        } else {
                                            Button("Disconnect") {
                                                webHost.disconnectViewer(id: viewer.id)
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                        }
                                    }
                                    .padding(8)
                                    .background(Color(NSColor.textBackgroundColor).opacity(0.6))
                                    .cornerRadius(8)
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(webHost.isRunning ? Color.indigo.opacity(0.35) : Color.clear, lineWidth: 1)
        )
        .padding(.horizontal)
    }

    // MARK: - 4. Native Android Continuity App Stream Card

    private var androidNativeStreamCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                Image(systemName: "ipad.landscape")
                    .font(.system(size: 36))
                    .foregroundColor(.green)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Native Android Continuity App Stream")
                        .font(.headline)
                    Text(extManager.isStreaming
                         ? "Streaming \(extManager.activeSourceDescription) directly to Android at \(extManager.fps) FPS"
                         : (agent.activeSession == nil
                            ? "Connect your Android device on the Dashboard to stream directly into the Continuity Android app"
                            : "Ready to push \(extManager.activeSourceDescription) directly to your connected Android device"))
                        .font(.caption)
                        .foregroundColor(extManager.isStreaming ? .green : .secondary)
                }

                Spacer()

                Button {
                    extManager.toggleExtendedDisplay(session: agent.activeSession)
                } label: {
                    Label(
                        extManager.isStreaming ? "Stop Android Stream" : "Stream to Android App",
                        systemImage: extManager.isStreaming ? "stop.fill" : "play.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(extManager.isStreaming ? .red : .green)
                .disabled(!extManager.isStreaming && agent.activeSession == nil)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    // MARK: - 5. Universal Control Card

    private var universalControlCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                Image(systemName: "keyboard.badge.ellipsis")
                    .font(.system(size: 36))
                    .foregroundColor(.purple)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Universal Control (Mouse & Keyboard Sharing)")
                        .font(.headline)
                    Text(universalControl.isControlActive ? "Mac keyboard & pointer are actively forwarded to Android" : "Move seamlessly between Mac and tablet")
                        .font(.caption)
                        .foregroundColor(universalControl.isControlActive ? .green : .secondary)
                }

                Spacer()

                Button {
                    universalControl.toggleControl(session: agent.activeSession)
                } label: {
                    Label(
                        universalControl.isControlActive ? "Disable Control" : "Enable Control",
                        systemImage: universalControl.isControlActive ? "checkmark.circle.fill" : "cursorarrow.rays"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(universalControl.isControlActive ? .green : .purple)
            }

            if universalControl.isControlActive {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                    Text("Press **ESC** at any time on your Mac to release Universal Control back to macOS.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private func generateQRCode(from string: String) -> NSImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage else { return nil }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cgImg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImg, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
    }
}
