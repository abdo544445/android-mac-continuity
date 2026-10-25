import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ContinuityProtocol

public struct MirroringView: View {
    @ObservedObject var agent = ConnectionAgent.shared
    @ObservedObject var advancedHost = AdvancedHostManager.shared
    @ObservedObject var clipboardBridge = ClipboardBridge.shared
    @State private var isMirroringActive = false
    @State private var selectedResolution = "1080p"
    @State private var isDropTargeted = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 12) {
                Text("Screen Mirroring")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()

                Toggle("Auto-Paste Mac Copies", isOn: $clipboardBridge.autoPasteOnMirror)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help("Automatically paste copied Mac text & images into your mirrored Android/Huawei device")

                Button(action: {
                    clipboardBridge.sendCurrentClipboard(session: agent.activeSession, triggerPaste: true)
                }) {
                    Label("Paste Mac Clipboard (Text / Image)", systemImage: "doc.on.clipboard.fill")
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("v", modifiers: [.command, .shift])
                .help("Push current Mac clipboard (text or screenshot/image) and paste into Android (⇧⌘V)")

                Picker("Resolution", selection: $selectedResolution) {
                    Text("1080p").tag("1080p")
                    Text("720p").tag("720p")
                }
                .frame(width: 110)

                if agent.liveMirrorFrame != nil {
                    Button(action: {
                        agent.liveMirrorFrame = nil
                        var env = ContinuityEnvelope(senderDeviceId: "macos-companion")
                        env.sessionStop = SessionStop(sessionId: "mirror", reason: "User stopped")
                        agent.activeSession?.send(envelope: env)
                    }) {
                        Label("Stop Wireless Mirror", systemImage: "stop.circle.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
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

            // Display Canvas + Drag-and-Drop Image/Text Paste Target
            ZStack {
                Color.black

                if let mirrorImg = agent.liveMirrorFrame {
                    Image(nsImage: mirrorImg)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 18) {
                        Image(systemName: isDropTargeted ? "photo.badge.plus.fill" : "ipad.and.iphone")
                            .font(.system(size: 60))
                            .foregroundColor(isDropTargeted ? .blue : .gray)

                        Text(advancedHost.isMirroringActive ? "scrcpy Interactive 60fps Window Active" : "Android / Huawei Mirror & Paste Hub")
                            .font(.headline)
                            .foregroundColor(.white)

                        if !advancedHost.statusMessage.isEmpty {
                            Text(advancedHost.statusMessage)
                                .font(.caption)
                                .foregroundColor(.orange)
                        }

                        Text("Copy any **Text** or **Image / Screenshot** on your Mac (`⌘C`) and it automatically syncs to your Huawei/Android clipboard — or drag & drop an image right here to paste it directly into the mirrored app!")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 480)

                        HStack(spacing: 14) {
                            Button("Start Wireless Mirror") {
                                requestPublicMirror()
                            }
                            .buttonStyle(.borderedProminent)

                            if advancedHost.isScrcpyAvailable && !advancedHost.isMirroringActive {
                                Button("Launch Interactive USB/ADB Window (scrcpy)") {
                                    advancedHost.startScrcpy()
                                }
                                .buttonStyle(.bordered)
                            }

                            Button {
                                clipboardBridge.sendCurrentClipboard(session: agent.activeSession, triggerPaste: true)
                            } label: {
                                Label("Paste Mac Clipboard to Tablet Now", systemImage: "sparkles.rectangle.stack.fill")
                            }
                            .buttonStyle(.bordered)
                        }

                        if let img = clipboardBridge.lastSharedImage {
                            HStack(spacing: 10) {
                                Image(nsImage: img)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 44, height: 44)
                                    .cornerRadius(6)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Last Synced Clipboard: \(clipboardBridge.lastSharedType)")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                    Text("Ready to paste in Huawei Notes, Telegram, Docs, etc.")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                            }
                            .padding(10)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(10)
                        }
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

            // Floating Navigation Control Bar
            HStack(spacing: 32) {
                navButton(icon: "arrow.uturn.backward", label: "Back") {
                    sendInput(action: .navBack)
                }
                navButton(icon: "circle", label: "Home") {
                    sendInput(action: .navHome)
                }
                navButton(icon: "square", label: "Recents") {
                    sendInput(action: .navRecents)
                }
                Divider().frame(height: 24)
                navButton(icon: "doc.on.clipboard", label: "Paste (⌘V)") {
                    clipboardBridge.sendCurrentClipboard(session: agent.activeSession, triggerPaste: true)
                }
                Divider().frame(height: 24)
                navButton(icon: "power", label: "Power") {
                    sendKey(code: 26) // KEYCODE_POWER
                }
                navButton(icon: "speaker.wave.2", label: "Vol+") {
                    sendKey(code: 24) // KEYCODE_VOLUME_UP
                }
                navButton(icon: "speaker.wave.1", label: "Vol-") {
                    sendKey(code: 25) // KEYCODE_VOLUME_DOWN
                }
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    if let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        Task { @MainActor in
                            clipboardBridge.sendDroppedImageFile(url: url, session: agent.activeSession, triggerPaste: true)
                        }
                    }
                }
                return true
            }
        }
        return false
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

    private func requestPublicMirror() {
        var env = ContinuityEnvelope(senderDeviceId: "macos-companion")
        env.sessionRequest = SessionRequest(
            type: .screenMirror,
            width: selectedResolution == "1080p" ? 1920 : 1280,
            height: selectedResolution == "1080p" ? 1080 : 720,
            targetFps: 30,
            codec: "H264"
        )
        agent.activeSession?.send(envelope: env)
    }

    private func sendInput(action: InputAction) {
        var env = ContinuityEnvelope(senderDeviceId: "macos-companion")
        env.inputEvent = InputEvent(sessionId: "mirror", action: action)
        agent.activeSession?.send(envelope: env)

        let keycode: Int?
        switch action {
        case .navBack: keycode = 4
        case .navHome: keycode = 3
        case .navRecents: keycode = 187
        default: keycode = nil
        }
        if let kc = keycode {
            advancedHost.executeAdbCommand(args: ["shell", "input", "keyevent", "\(kc)"])
        }
    }

    private func sendKey(code: Int32) {
        var env = ContinuityEnvelope(senderDeviceId: "macos-companion")
        env.inputEvent = InputEvent(sessionId: "mirror", action: .keyDown, keyCode: code)
        agent.activeSession?.send(envelope: env)
        advancedHost.executeAdbCommand(args: ["shell", "input", "keyevent", "\(code)"])
    }
}
