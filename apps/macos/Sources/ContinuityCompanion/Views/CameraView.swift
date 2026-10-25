import SwiftUI
import ContinuityProtocol

public struct CameraView: View {
    @ObservedObject var agent = ConnectionAgent.shared
    @State private var isStreaming = false
    @State private var selectedLens = "BACK"
    @State private var selectedResolution = "1080p"
    @State private var isTorchOn = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                Text("Phone Camera as Mac Webcam")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()

                HStack(spacing: 6) {
                    Circle()
                        .fill(isStreaming ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text("CoreMediaIO Virtual Camera: \(isStreaming ? "Active" : "Ready")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)

                Button(action: { toggleStreaming() }) {
                    Label(isStreaming ? "Stop Camera" : "Start Camera", systemImage: isStreaming ? "video.slash.fill" : "video.fill")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Video Preview Canvas
            ZStack {
                Color.black

                if let camImg = agent.liveCameraFrame {
                    Image(nsImage: camImg)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "camera.circle.fill")
                            .font(.system(size: 64))
                            .foregroundColor(isStreaming ? .green : .gray)

                        Text(isStreaming ? "Connecting to Device Camera..." : "Camera Ready")
                            .font(.headline)
                            .foregroundColor(.white)

                        Text("Use your Huawei / Android device camera as a crystal-clear high-definition webcam for macOS.")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 420)
                    }
                    .padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Camera Controls Bar
            HStack(spacing: 24) {
                Picker("Lens", selection: $selectedLens) {
                    Text("Rear Camera (Ultra HD)").tag("BACK")
                    Text("Front Camera (Selfie)").tag("FRONT")
                }
                .frame(width: 220)

                Picker("Resolution", selection: $selectedResolution) {
                    Text("1080p (Full HD)").tag("1080p")
                    Text("720p (HD)").tag("720p")
                }
                .frame(width: 160)

                Toggle("Torch / Flash", isOn: $isTorchOn)
                    .toggleStyle(.switch)
                    .disabled(selectedLens == "FRONT")
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }

    private func toggleStreaming() {
        isStreaming.toggle()
        if isStreaming {
            var env = ContinuityEnvelope(senderDeviceId: "macos-companion")
            env.sessionRequest = SessionRequest(
                type: .cameraStream,
                width: selectedResolution == "1080p" ? 1920 : 1280,
                height: selectedResolution == "1080p" ? 1080 : 720,
                targetFps: 30,
                codec: "H264",
                cameraLens: selectedLens
            )
            agent.activeSession?.send(envelope: env)
        } else {
            agent.liveCameraFrame = nil
            var env = ContinuityEnvelope(senderDeviceId: "macos-companion")
            env.sessionStop = SessionStop(sessionId: "camera", reason: "User stopped")
            agent.activeSession?.send(envelope: env)
        }
    }
}
