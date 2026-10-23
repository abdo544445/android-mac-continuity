import SwiftUI
import ContinuityProtocol

public struct MirroringView: View {
    @ObservedObject var agent = ConnectionAgent.shared
    @ObservedObject var advancedHost = AdvancedHostManager.shared
    @State private var isMirroringActive = false
    @State private var selectedResolution = "1080p"

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                Text("Screen Mirroring")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()

                Picker("Resolution", selection: $selectedResolution) {
                    Text("1080p").tag("1080p")
                    Text("720p").tag("720p")
                }
                .frame(width: 120)

                if advancedHost.isScrcpyAvailable {
                    Button(action: {
                        if advancedHost.isMirroringActive {
                            advancedHost.stopScrcpy()
                        } else {
                            advancedHost.startScrcpy()
                        }
                    }) {
                        Label(
                            advancedHost.isMirroringActive ? "Stop scrcpy (60fps)" : "Launch scrcpy (60fps)",
                            systemImage: advancedHost.isMirroringActive ? "stop.fill" : "play.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Display Canvas
            ZStack {
                Color.black

                VStack(spacing: 16) {
                    Image(systemName: "iphone")
                        .font(.system(size: 64))
                        .foregroundColor(.gray)

                    Text(advancedHost.isMirroringActive ? "scrcpy Ultra-Low Latency Mirror Active" : "Android Mirror Canvas Ready")
                        .font(.headline)
                        .foregroundColor(.white)

                    Text(advancedHost.isScrcpyAvailable
                         ? "Direct hardware H.264 stream connected via TCP/IP or USB with sub-35ms response time."
                         : "Public Edition: Android user must grant one-time MediaProjection consent to start stream.")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)

                    if !advancedHost.isMirroringActive {
                        Button("Request Mirror Session") {
                            requestPublicMirror()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Floating Navigation Control Bar
            HStack(spacing: 36) {
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
    }

    private func sendKey(code: Int32) {
        var env = ContinuityEnvelope(senderDeviceId: "macos-companion")
        env.inputEvent = InputEvent(sessionId: "mirror", action: .keyDown, keyCode: code)
        agent.activeSession?.send(envelope: env)
    }
}
