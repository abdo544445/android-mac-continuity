import SwiftUI
import ContinuityProtocol

public struct ExtendedDisplayHostView: View {
    @ObservedObject var extManager = ExtendedDisplayManager.shared
    @ObservedObject var agent = ConnectionAgent.shared
    @ObservedObject var universalControl = UniversalControlManager.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 24) {
            // Header Info
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mac Extended Display & Universal Control")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Use your Huawei / Android tablet as a high-speed secondary monitor or share your Mac mouse & keyboard.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top)

            Divider()

            // Extended Display Card
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    Image(systemName: "display.2")
                        .font(.system(size: 40))
                        .foregroundColor(.blue)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tablet Secondary Display")
                            .font(.headline)
                        Text(extManager.isStreaming ? "Streaming desktop to tablet at \(extManager.fps) FPS" : "Tablet is not actively streaming")
                            .font(.subheadline)
                            .foregroundColor(extManager.isStreaming ? .green : .secondary)
                    }

                    Spacer()

                    Button(action: {
                        extManager.toggleExtendedDisplay(session: agent.activeSession)
                    }) {
                        Label(
                            extManager.isStreaming ? "Stop Display Stream" : "Start Display Stream",
                            systemImage: extManager.isStreaming ? "stop.fill" : "play.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(extManager.isStreaming ? .red : .blue)
                }

                if extManager.isStreaming {
                    HStack(spacing: 20) {
                        Picker("Framerate", selection: $extManager.fps) {
                            Text("30 FPS").tag(30)
                            Text("60 FPS").tag(60)
                        }
                        .frame(width: 140)

                        Slider(value: $extManager.quality, in: 0.5...0.95, step: 0.05) {
                            Text("Quality: \(Int(extManager.quality * 100))%")
                        }
                        Text("\(Int(extManager.quality * 100))% Quality")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .padding(.horizontal)

            // Universal Control Card
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    Image(systemName: "keyboard.badge.ellipsis")
                        .font(.system(size: 40))
                        .foregroundColor(.purple)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Universal Control (Mouse & Keyboard Sharing)")
                            .font(.headline)
                        Text(universalControl.isControlActive ? "Mac keyboard & pointer are actively forwarded to Android" : "Move seamlessly between Mac and tablet")
                            .font(.subheadline)
                            .foregroundColor(universalControl.isControlActive ? .green : .secondary)
                    }

                    Spacer()

                    Button(action: {
                        universalControl.toggleControl(session: agent.activeSession)
                    }) {
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
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .padding(.horizontal)

            Spacer()
        }
    }
}
