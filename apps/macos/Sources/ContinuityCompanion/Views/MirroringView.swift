import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ContinuityProtocol

public struct MirroringView: View {
    @ObservedObject var agent = ConnectionAgent.shared
    @ObservedObject var advancedHost = AdvancedHostManager.shared
    @ObservedObject var clipboardBridge = ClipboardBridge.shared
    @ObservedObject var mirrorManager = MirroringManager.shared
    @State private var isDropTargeted = false
    @State private var showAdbSetupSheet = false
    @State private var adbPhoneIp = "192.168.1.28"
    @State private var adbPairPort = ""
    @State private var adbPairCode = ""
    @State private var adbConnectPort = ""
    @State private var setupTab: String = "qr"

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 12) {
                Text("Screen Mirroring")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()

                if mirrorManager.isMirroringActive {
                    Text(String(format: "%.1f FPS", mirrorManager.fps))
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.2))
                        .foregroundColor(.blue)
                        .cornerRadius(6)
                }

                Toggle("Auto-Paste Mac Copies", isOn: $clipboardBridge.autoPasteOnMirror)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help("Automatically paste copied Mac text & images into your mirrored Android device")

                Toggle("Audio to Mac", isOn: $advancedHost.isAudioForwardingEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help("Stream phone audio directly through Mac speakers during 60 FPS mirror")

                Button(action: {
                    Task {
                        if let screenshotURL = await advancedHost.capturePhoneScreenshot() {
                            NSWorkspace.shared.activateFileViewerSelecting([screenshotURL])
                        }
                    }
                }) {
                    Label("Capture Screen", systemImage: "camera.viewfinder")
                }
                .buttonStyle(.bordered)
                .help("Take a high-resolution phone screenshot and save to Mac Downloads folder")

                Button(action: {
                    clipboardBridge.sendCurrentClipboard(session: agent.activeSession, triggerPaste: true)
                }) {
                    Label("Paste Mac Clipboard", systemImage: "doc.on.clipboard.fill")
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("v", modifiers: [.command, .shift])
                .help("Push current Mac clipboard (text or screenshot/image) and paste into Android (⇧⌘V)")

                Picker("Resolution", selection: $mirrorManager.selectedResolution) {
                    Text("1080p").tag("1080p")
                    Text("720p").tag("720p")
                }
                .frame(width: 110)

                if mirrorManager.isMirroringActive || agent.liveMirrorFrame != nil {
                    Button(action: {
                        mirrorManager.stopMirroring(session: agent.activeSession)
                    }) {
                        Label("Stop Wireless Mirror", systemImage: "stop.circle.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                } else {
                    Button(action: {
                        mirrorManager.startMirroring(session: agent.activeSession)
                    }) {
                        Label("Start Wireless Mirror", systemImage: "play.circle.fill")
                    }
                    .buttonStyle(.bordered)
                }

                if advancedHost.isScrcpyAvailable {
                    Button(action: {
                        if advancedHost.isMirroringActive {
                            advancedHost.stopScrcpy()
                        } else {
                            advancedHost.startScrcpy()
                        }
                    }) {
                        Label(
                            advancedHost.isMirroringActive ? "Stop Mirror (60fps)" : "Launch Mirror (60fps)",
                            systemImage: advancedHost.isMirroringActive ? "stop.fill" : "play.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // ADB Connectivity HUD Banner
            if advancedHost.connectedAdbDevices.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "bolt.horizontal.circle")
                        .foregroundColor(.orange)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("60 FPS Ultra-Fast Mirror: Device Not Connected via ADB")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(advancedHost.statusMessage.isEmpty ? "Plug in via USB or pair using phone's Wireless Debugging" : advancedHost.statusMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Wireless ADB Setup") {
                        if let ip = LanDiscoveryService.shared.discoveredPeers.first?.ip, !ip.isEmpty {
                            adbPhoneIp = ip
                        }
                        showAdbSetupSheet = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(10)
                .background(Color.orange.opacity(0.12))
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("60 FPS Ultra-Fast Mirror Ready (\(advancedHost.connectedAdbDevices.joined(separator: ", ")))")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                    Spacer()
                    Button("Lock Port 5555 (via USB)") {
                        advancedHost.lockToPermanentPort5555()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .help("Lock phone to port 5555 so you can unplug USB and keep wireless mirror permanently")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.1))
            }

            Divider()

            // Display Canvas + Drag-and-Drop Image/Text Paste Target
            ZStack {
                Color.black

                if let mirrorImg = mirrorManager.currentFrame ?? agent.liveMirrorFrame {
                    GeometryReader { geo in
                        Image(nsImage: mirrorImg)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onEnded { value in
                                        let imgW = mirrorImg.size.width
                                        let imgH = mirrorImg.size.height
                                        guard geo.size.width > 0, geo.size.height > 0, imgW > 0, imgH > 0 else { return }

                                        let scale = min(geo.size.width / imgW, geo.size.height / imgH)
                                        let displayedW = imgW * scale
                                        let displayedH = imgH * scale
                                        let originX = (geo.size.width - displayedW) / 2
                                        let originY = (geo.size.height - displayedH) / 2

                                        let clickX = value.location.x - originX
                                        let clickY = value.location.y - originY

                                        if clickX >= 0 && clickX <= displayedW && clickY >= 0 && clickY <= displayedH {
                                            let normX = Float(clickX / displayedW)
                                            let normY = Float(clickY / displayedH)
                                            mirrorManager.handleTap(normX: normX, normY: normY, session: agent.activeSession)
                                        }
                                    }
                            )
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "ipad.and.iphone")
                            .font(.system(size: 64))
                            .foregroundColor(.gray)

                        Text("Screen Mirroring Standby")
                            .font(.headline)
                            .foregroundColor(.white)

                        Text("Click 'Start Wireless Mirror' or 'Launch Mirror (60fps)' to begin low-latency screen control.")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 420)
                    }
                    .padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isDropTargeted ? Color.blue : Color.clear, lineWidth: 3)
                    .padding(8)
            )
            .onDrop(of: [.fileURL, .png, .tiff, .utf8PlainText], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers: providers)
            }

            Divider()

            // Floating Navigation & Quick App Control Bar
            HStack(spacing: 24) {
                navButton(icon: "arrow.uturn.backward", label: "Back") {
                    mirrorManager.sendInput(action: .navBack, session: agent.activeSession)
                }
                navButton(icon: "circle", label: "Home") {
                    mirrorManager.sendInput(action: .navHome, session: agent.activeSession)
                }
                navButton(icon: "square", label: "Recents") {
                    mirrorManager.sendInput(action: .navRecents, session: agent.activeSession)
                }
                Divider().frame(height: 24)
                navButton(icon: "doc.on.clipboard", label: "Paste (⌘V)") {
                    clipboardBridge.sendCurrentClipboard(session: agent.activeSession, triggerPaste: true)
                }
                Divider().frame(height: 24)
                navButton(icon: "power", label: "Power") {
                    mirrorManager.sendKey(code: 26, session: agent.activeSession) // KEYCODE_POWER
                }
                navButton(icon: "speaker.wave.2", label: "Vol+") {
                    mirrorManager.sendKey(code: 24, session: agent.activeSession) // KEYCODE_VOLUME_UP
                }
                navButton(icon: "speaker.wave.1", label: "Vol-") {
                    mirrorManager.sendKey(code: 25, session: agent.activeSession) // KEYCODE_VOLUME_DOWN
                }
                Divider().frame(height: 24)
                navButton(icon: "message.fill", label: "WhatsApp") {
                    advancedHost.launchApp(packageName: "com.whatsapp")
                }
                navButton(icon: "play.rectangle.fill", label: "YouTube") {
                    advancedHost.launchApp(packageName: "com.google.android.youtube")
                }
                navButton(icon: "globe", label: "Browser") {
                    advancedHost.launchApp(packageName: "com.android.chrome")
                }
                navButton(icon: "gearshape.fill", label: "Settings") {
                    advancedHost.executeAdbCommand(args: ["shell", "am", "start", "-a", "android.settings.SETTINGS"])
                }
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .sheet(isPresented: $showAdbSetupSheet) {
            adbSetupSheetView()
        }
    }

    private func adbSetupSheetView() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("⚡ Wireless ADB & 60 FPS Setup")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    showAdbSetupSheet = false
                }
            }

            Picker("Setup Method", selection: $setupTab) {
                Label("Scan QR Code", systemImage: "qrcode").tag("qr")
                Label("Manual PIN / Port", systemImage: "keyboard").tag("manual")
                Label("Lock Port 5555 (USB)", systemImage: "cable.connector").tag("usb")
            }
            .pickerStyle(.segmented)

            Divider()

            if setupTab == "qr" {
                qrSetupView()
            } else if setupTab == "manual" {
                manualSetupView()
            } else {
                permanentUsbView()
            }

            if !advancedHost.statusMessage.isEmpty {
                Text(advancedHost.statusMessage)
                    .font(.caption)
                    .foregroundColor(.blue)
                    .padding(6)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(6)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onAppear {
            if advancedHost.isAdbAvailable {
                advancedHost.startQrPairing()
            }
        }
        .onDisappear {
            advancedHost.stopQrPairing()
        }
    }

    private func qrSetupView() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 20) {
                // QR Code
                VStack(spacing: 8) {
                    if let qr = advancedHost.qrImage {
                        Image(nsImage: qr)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 190, height: 190)
                            .padding(10)
                            .background(Color.white)
                            .cornerRadius(12)
                            .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 2)
                    } else {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.1))
                            .frame(width: 190, height: 190)
                            .cornerRadius(12)
                            .overlay(ProgressView())
                    }

                    Button(action: {
                        advancedHost.generateNewQrPairing()
                    }) {
                        Label("Regenerate Code", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }

                // Instructions
                VStack(alignment: .leading, spacing: 10) {
                    Text("Pair in 3 Seconds (Android 11+)")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 6) {
                            Text("1.").fontWeight(.bold).foregroundColor(.blue)
                            Text("On phone: Settings > Developer options > Wireless debugging")
                                .font(.caption)
                        }
                        HStack(alignment: .top, spacing: 6) {
                            Text("2.").fontWeight(.bold).foregroundColor(.blue)
                            Text("Turn Wireless debugging ON")
                                .font(.caption)
                        }
                        HStack(alignment: .top, spacing: 6) {
                            Text("3.").fontWeight(.bold).foregroundColor(.blue)
                            Text("Tap 'Pair device with QR code' and scan the code on the left!")
                                .font(.caption)
                        }
                    }
                    .foregroundColor(.secondary)

                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Service:").font(.caption2).foregroundColor(.secondary)
                            Text(advancedHost.qrServiceName).font(.system(.caption2, design: .monospaced))
                        }
                        HStack {
                            Text("Pair Code:").font(.caption2).foregroundColor(.secondary)
                            Text(advancedHost.qrPairingCode).font(.system(.caption2, design: .monospaced)).foregroundColor(.blue)
                        }
                    }
                }
            }

            // Status message / Live progress
            HStack(spacing: 8) {
                if !advancedHost.connectedAdbDevices.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Device Connected (\(advancedHost.connectedAdbDevices.first ?? ""))! 60 FPS Mirror is ready.")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                } else if advancedHost.isQrPairingActive {
                    ProgressView()
                        .controlSize(.small)
                    Text(advancedHost.qrStatusMessage.isEmpty ? "Ready. Point phone camera at QR code..." : advancedHost.qrStatusMessage)
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.blue.opacity(0.08))
            .cornerRadius(8)
        }
    }

    private func manualSetupView() -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Manual Numeric Pairing")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("On phone: Settings > Developer options > Wireless debugging > 'Pair device with pairing code'")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Phone IP:").font(.caption)
                    TextField("192.168.1.X", text: $adbPhoneIp)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                }
                GridRow {
                    Text("Pairing Port:").font(.caption)
                    TextField("Port (e.g. 38475)", text: $adbPairPort)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                }
                GridRow {
                    Text("6-digit Code:").font(.caption)
                    TextField("Code (e.g. 123456)", text: $adbPairCode)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                }
                GridRow {
                    Text("Connect Port:").font(.caption)
                    TextField("Optional (if different)", text: $adbConnectPort)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                }
            }

            HStack {
                Button(action: {
                    advancedHost.pairWirelessAdb(
                        ip: adbPhoneIp,
                        pairPort: adbPairPort,
                        code: adbPairCode,
                        connectPort: adbConnectPort
                    )
                }) {
                    Label("Pair & Connect", systemImage: "link")
                }
                .buttonStyle(.borderedProminent)
                .disabled(adbPhoneIp.isEmpty || adbPairPort.isEmpty || adbPairCode.isEmpty)

                Button(action: {
                    let port = adbConnectPort.isEmpty ? adbPairPort : adbConnectPort
                    advancedHost.connectWirelessAdb(ip: adbPhoneIp, port: port)
                }) {
                    Text("Direct Connect (Already Paired)")
                }
                .buttonStyle(.bordered)
                .disabled(adbPhoneIp.isEmpty || (adbConnectPort.isEmpty && adbPairPort.isEmpty))
            }
        }
    }

    private func permanentUsbView() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Lock Permanent Wireless Mode (Recommended)")
                .font(.subheadline)
                .fontWeight(.semibold)
            Text("Connect phone via USB once, then click below. You can then unplug the cable and wireless 60fps mirror will stay permanently active on port 5555!")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Button(action: {
                    advancedHost.lockToPermanentPort5555()
                }) {
                    Label("Lock to Port 5555 via USB", systemImage: "cable.connector")
                }
                .buttonStyle(.bordered)

                Toggle("Auto-Reconnect Keep-Alive", isOn: $advancedHost.isKeepAliveEnabled)
                    .toggleStyle(.checkbox)
                    .font(.caption)
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let fileURL = url {
                        Task { @MainActor in
                            self.processDroppedURL(fileURL)
                        }
                    }
                }
                return true
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    var targetURL: URL?
                    if let u = item as? URL {
                        targetURL = u
                    } else if let ns = item as? NSURL {
                        targetURL = ns as URL
                    } else if let data = item as? Data {
                        if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !str.isEmpty {
                            targetURL = str.hasPrefix("file://") ? URL(string: str) : URL(fileURLWithPath: str)
                        } else {
                            targetURL = URL(dataRepresentation: data, relativeTo: nil)
                        }
                    }
                    if let fileURL = targetURL {
                        Task { @MainActor in
                            self.processDroppedURL(fileURL)
                        }
                    }
                }
                return true
            }
        }
        return false
    }

    private func processDroppedURL(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        if ext == "apk" {
            FileTransferEngine.shared.queueOutgoingTransfer(fileURL: url, session: agent.activeSession)
        } else if ["png", "jpg", "jpeg", "heic", "webp", "gif"].contains(ext) {
            clipboardBridge.sendDroppedImageFile(url: url, session: agent.activeSession, triggerPaste: true)
        } else {
            FileTransferEngine.shared.queueOutgoingTransfer(fileURL: url, session: agent.activeSession)
        }
    }

    private func navButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                Text(label)
                    .font(.caption2)
            }
        }
        .buttonStyle(.plain)
        .foregroundColor(.primary)
    }
}
