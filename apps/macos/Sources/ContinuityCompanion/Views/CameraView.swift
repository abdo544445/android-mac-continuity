import SwiftUI
import ContinuityProtocol

public struct CameraView: View {
    @ObservedObject var agent = ConnectionAgent.shared
    @ObservedObject var cameraManager = CameraStreamManager.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                Text("Phone Camera as Mac Webcam")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()

                if cameraManager.isStreaming {
                    Text(String(format: "%.1f FPS", cameraManager.fps))
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.2))
                        .foregroundColor(.green)
                        .cornerRadius(6)
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(cameraManager.isStreaming ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text("CoreMediaIO Virtual Camera: \(cameraManager.isStreaming ? "Active" : "Ready")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)

                Button(action: { cameraManager.toggleStreaming(session: agent.activeSession) }) {
                    Label(cameraManager.isStreaming ? "Stop Camera" : "Start Camera", systemImage: cameraManager.isStreaming ? "video.slash.fill" : "video.fill")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Video Preview Canvas
            ZStack {
                Color.black

                if let camImg = cameraManager.currentFrame ?? agent.liveCameraFrame {
                    Image(nsImage: camImg)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "camera.circle.fill")
                            .font(.system(size: 64))
                            .foregroundColor(cameraManager.isStreaming ? .green : .gray)

                        Text(cameraManager.isStreaming ? "Connecting to Device Camera..." : "Camera Ready")
                            .font(.headline)
                            .foregroundColor(.white)

                        Text("Use your Android device camera as a crystal-clear high-definition webcam for macOS.")
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
                Picker("Lens", selection: $cameraManager.selectedLens) {
                    Text("Rear Camera (Ultra HD)").tag("BACK")
                    Text("Front Camera (Selfie)").tag("FRONT")
                }
                .frame(width: 220)

                Picker("Resolution", selection: $cameraManager.selectedResolution) {
                    Text("1080p (Full HD)").tag("1080p")
                    Text("720p (HD)").tag("720p")
                }
                .frame(width: 160)

                Toggle("Torch / Flash", isOn: $cameraManager.isTorchOn)
                    .toggleStyle(.switch)
                    .disabled(cameraManager.selectedLens == "FRONT")
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }
}
