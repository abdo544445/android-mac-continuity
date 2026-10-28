import SwiftUI
import ContinuityProtocol

public struct CameraView: View {
    @ObservedObject var agent = ConnectionAgent.shared
    @ObservedObject var cameraManager = CameraStreamManager.shared
    @State private var snapshotNotification: String? = nil

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Phone Camera as Mac Webcam")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Hardware Continuity Pro Camera • Sub-40ms HD Stream")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if cameraManager.isStreaming {
                    Text(String(format: "%.1f FPS", cameraManager.fps))
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.2))
                        .foregroundColor(.green)
                        .cornerRadius(6)
                }

                // Shutter Button
                Button(action: {
                    if let url = cameraManager.takeSnapshot() {
                        snapshotNotification = "Saved: \(url.lastPathComponent)"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            snapshotNotification = nil
                        }
                    }
                }) {
                    Label("Take Photo", systemImage: "camera.shutter.button.fill")
                }
                .buttonStyle(.bordered)
                .disabled(!cameraManager.isStreaming && cameraManager.currentFrame == nil && agent.liveCameraFrame == nil)

                Button(action: { cameraManager.toggleStreaming(session: agent.activeSession) }) {
                    Label(cameraManager.isStreaming ? "Stop Camera" : "Start Camera", systemImage: cameraManager.isStreaming ? "video.slash.fill" : "video.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(cameraManager.isStreaming ? .red : .blue)
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

                    // Rule of Thirds Grid Overlay
                    if cameraManager.showGridOverlay {
                        GeometryReader { geo in
                            Path { path in
                                let w = geo.size.width
                                let h = geo.size.height
                                // Vertical lines
                                path.move(to: CGPoint(x: w / 3, y: 0))
                                path.addLine(to: CGPoint(x: w / 3, y: h))
                                path.move(to: CGPoint(x: 2 * w / 3, y: 0))
                                path.addLine(to: CGPoint(x: 2 * w / 3, y: h))
                                // Horizontal lines
                                path.move(to: CGPoint(x: 0, y: h / 3))
                                path.addLine(to: CGPoint(x: w, y: h / 3))
                                path.move(to: CGPoint(x: 0, y: 2 * h / 3))
                                path.addLine(to: CGPoint(x: w, y: 2 * h / 3))
                            }
                            .stroke(Color.white.opacity(0.35), lineWidth: 1)
                        }
                    }

                    // Live Pro HUD Overlays
                    VStack {
                        HStack {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 8, height: 8)
                                Text("REC")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                                Text("\(cameraManager.selectedResolution) • \(cameraManager.selectedLens)")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.8))
                                if cameraManager.zoomRatio > 1.0 {
                                    Text(String(format: "%.1fx", cameraManager.zoomRatio))
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundColor(.yellow)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(16)

                            Spacer()

                            if let notification = snapshotNotification {
                                Text(notification)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 5)
                                    .background(Color.blue.opacity(0.85))
                                    .cornerRadius(14)
                            }
                        }
                        .padding(16)

                        Spacer()
                    }
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

                        if agent.activeSession == nil {
                            Text("⚠️ No device currently connected via Wi-Fi Continuity. Connect your phone on the Dashboard first.")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    .padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Pro Camera Controller Deck
            VStack(spacing: 12) {
                // Row 1: Hardware & Optics Controls
                HStack(spacing: 20) {
                    Picker("Lens", selection: $cameraManager.selectedLens) {
                        Text("Rear Main (4K/HD)").tag("BACK")
                        Text("Front Selfie").tag("FRONT")
                        Text("Ultra-Wide").tag("ULTRA_WIDE")
                    }
                    .frame(width: 220)
                    .onChange(of: cameraManager.selectedLens) { newLens in
                        cameraManager.setLens(lens: newLens, session: agent.activeSession)
                    }

                    Picker("Format", selection: $cameraManager.selectedResolution) {
                        Text("1080p (Full HD)").tag("1080p")
                        Text("720p (HD)").tag("720p")
                    }
                    .frame(width: 170)

                    // Flashlight / Torch Toggle
                    Button(action: {
                        let newTorch = !cameraManager.isTorchOn
                        cameraManager.setTorch(enabled: newTorch, session: agent.activeSession)
                    }) {
                        Label(
                            cameraManager.isTorchOn ? "Flash: ON" : "Flash: OFF",
                            systemImage: cameraManager.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill"
                        )
                    }
                    .buttonStyle(.bordered)
                    .tint(cameraManager.isTorchOn ? .yellow : .primary)
                    .disabled(cameraManager.selectedLens == "FRONT")

                    // Grid Toggle
                    Button(action: {
                        cameraManager.showGridOverlay.toggle()
                    }) {
                        Label("Grid", systemImage: cameraManager.showGridOverlay ? "grid.circle.fill" : "grid.circle")
                    }
                    .buttonStyle(.bordered)
                    .tint(cameraManager.showGridOverlay ? .blue : .primary)

                    Spacer()
                }

                // Row 2: Pro Exposure, Zoom & White Balance Controls
                HStack(spacing: 20) {
                    // Zoom Control
                    HStack(spacing: 8) {
                        Label("Zoom", systemImage: "magnifyingglass")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Slider(value: Binding(
                            get: { cameraManager.zoomRatio },
                            set: { cameraManager.setZoom(zoom: $0, session: agent.activeSession) }
                        ), in: 1.0...8.0, step: 0.1)
                        .frame(width: 120)

                        HStack(spacing: 4) {
                            ForEach([1.0, 2.0, 5.0], id: \.self) { z in
                                Button(String(format: "%.0fx", z)) {
                                    cameraManager.setZoom(zoom: Float(z), session: agent.activeSession)
                                }
                                .buttonStyle(.borderless)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(cameraManager.zoomRatio == Float(z) ? Color.blue.opacity(0.3) : Color.clear)
                                .cornerRadius(4)
                            }
                        }
                    }

                    Divider().frame(height: 20)

                    // Exposure Compensation (EV)
                    HStack(spacing: 8) {
                        Label("EV", systemImage: "plusminus.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Slider(value: Binding(
                            get: { Float(cameraManager.exposureCompensation) },
                            set: { cameraManager.setExposure(ev: Int32($0.rounded()), session: agent.activeSession) }
                        ), in: -4.0...4.0, step: 1.0)
                        .frame(width: 100)

                        Text(String(format: "%+d EV", cameraManager.exposureCompensation))
                            .font(.system(.caption, design: .monospaced))
                            .frame(width: 48)

                        if cameraManager.exposureCompensation != 0 {
                            Button("Reset") {
                                cameraManager.setExposure(ev: 0, session: agent.activeSession)
                            }
                            .buttonStyle(.borderless)
                            .font(.caption2)
                            .foregroundColor(.blue)
                        }
                    }

                    Divider().frame(height: 20)

                    // White Balance Presets
                    Picker("WB", selection: Binding(
                        get: { cameraManager.whiteBalance },
                        set: { cameraManager.setWhiteBalance(wb: $0, session: agent.activeSession) }
                    )) {
                        Text("Auto").tag("AUTO")
                        Text("Daylight ☀️").tag("DAYLIGHT")
                        Text("Cloudy ☁️").tag("CLOUDY")
                        Text("Fluorescent 💡").tag("FLUORESCENT")
                        Text("Tungsten 🕯️").tag("INCANDESCENT")
                    }
                    .frame(width: 150)

                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }
}
