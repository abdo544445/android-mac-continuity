import SwiftUI
import AppKit
import ContinuityProtocol

public struct MenuBarView: View {
    @ObservedObject var registry = DeviceRegistry.shared
    @ObservedObject var agent = ConnectionAgent.shared
    @ObservedObject var transferEngine = FileTransferEngine.shared
    @ObservedObject var clipboardBridge = ClipboardBridge.shared

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Device Status Row
            if let device = registry.activeDevice, device.isConnected {
                HStack {
                    Circle().fill(Color.green).frame(width: 8, height: 8)
                    Text(device.name).fontWeight(.semibold)
                    Spacer()
                    Text("\(device.batteryLevel)% \(device.isCharging ? "⚡️" : "")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                HStack {
                    Circle().fill(Color.orange).frame(width: 8, height: 8)
                    Text("No Phone Connected")
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Quick Actions
            Button("Send File to Phone...") {
                let panel = NSOpenPanel()
                panel.canChooseFiles = true
                if panel.runModal() == .OK, let url = panel.url {
                    transferEngine.queueOutgoingTransfer(fileURL: url, session: agent.activeSession)
                }
            }

            Button("Send Clipboard to Phone") {
                clipboardBridge.sendCurrentClipboard(session: agent.activeSession)
            }

            Divider()

            Button("Open Continuity Dashboard") {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first(where: { $0.title == "Continuity" || $0.canBecomeMain }) {
                    window.makeKeyAndOrderFront(nil)
                }
            }

            Divider()

            Button("Quit Continuity") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 240)
    }
}
