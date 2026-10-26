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

                Button(action: {
                    clipboardBridge.sendCurrentClipboard(session: agent.activeSession, triggerPaste: true)
                }) {
                    Label("Paste Mac Clipboard (Text / Image)", systemImage: "doc.on.clipboard.fill")
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

            // Floating Navigation Control Bar
            HStack(spacing: 32) {
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
}
