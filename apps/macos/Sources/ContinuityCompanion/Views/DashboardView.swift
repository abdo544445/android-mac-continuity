import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ContinuityProtocol

public struct DashboardView: View {
    @ObservedObject var registry = DeviceRegistry.shared
    @ObservedObject var agent = ConnectionAgent.shared
    @ObservedObject var discovery = LanDiscoveryService.shared
    @ObservedObject var transferEngine = FileTransferEngine.shared
    @ObservedObject var clipboardBridge = ClipboardBridge.shared
    @ObservedObject var callRelay = CallRelayBridge.shared
    @ObservedObject var biometricBridge = BiometricAuthBridge.shared
    @ObservedObject var handoffBridge = HandoffBridge.shared
    @ObservedObject var folderSync = FolderSyncEngine.shared
    @ObservedObject var extDisplay = ExtendedDisplayManager.shared
    @ObservedObject var universalControl = UniversalControlManager.shared
    @Binding var selectedTab: String
    @State private var isDropTargeted = false

    public init(selectedTab: Binding<String>) {
        self._selectedTab = selectedTab
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Status Card
                if let device = registry.activeDevice, device.isConnected {
                    connectedDeviceCard(device: device)
                } else {
                    disconnectedCard()
                }

                // Incoming Call Banner
                if let call = callRelay.activeCall {
                    HStack(spacing: 16) {
                        Image(systemName: "phone.arrow.down.left.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.green)
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Incoming Call from Device")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(call.callerName)
                                .font(.headline)
                            if !call.callerNumber.isEmpty && call.callerNumber != call.callerName {
                                Text(call.callerNumber)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        Button("Silence") {
                            callRelay.respondToCall(callId: call.callId, action: "MUTE", session: agent.activeSession)
                        }
                        .buttonStyle(.bordered)

                        Button("Decline") {
                            callRelay.respondToCall(callId: call.callId, action: "REJECT", session: agent.activeSession)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                    .padding()
                    .background(Color.green.opacity(0.12))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.green, lineWidth: 1.5)
                    )
                }

                // Auto-Discovered Nearby Devices on Local Network
                if !discovery.discoveredPeers.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("Nearby Devices on Local Network", systemImage: "dot.radiowaves.left.and.right")
                                .font(.headline)
                                .foregroundColor(.blue)
                            Spacer()
                            Text("Auto-detected via Wi-Fi / LAN")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        ForEach(discovery.discoveredPeers) { peer in
                            HStack(spacing: 14) {
                                Image(systemName: "ipad.and.iphone")
                                    .font(.system(size: 26))
                                    .foregroundColor(.blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(peer.deviceName)
                                        .font(.system(size: 15, weight: .semibold))
                                    Text("IP: \(peer.ip) • Ready to Pair")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button {
                                    agent.initiatePairingWithDiscoveredPeer(peer)
                                } label: {
                                    Label("Pair with PIN", systemImage: "checkmark.shield.fill")
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .padding(14)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.blue.opacity(0.25), lineWidth: 1)
                            )
                        }
                    }
                }

                // Quick Actions Grid
                Text("Quick Actions")
                    .font(.headline)
                    .foregroundColor(.secondary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    actionButton(title: "Send File", icon: "paperplane.fill", color: .blue) {
                        selectAndSendFile()
                    }
                    actionButton(title: "Push Clipboard", icon: "doc.on.clipboard.fill", color: .green) {
                        clipboardBridge.sendCurrentClipboard(session: agent.activeSession)
                    }
                    actionButton(title: "Mirror Screen", icon: "rectangle.inset.filled.and.cursorarrow", color: .purple) {
                        selectedTab = "Mirroring"
                    }
                    actionButton(title: "Extended Display", icon: "display.2", color: .indigo) {
                        selectedTab = "ExtendedDisplay"
                    }
                    actionButton(title: "Handoff Active Tab", icon: "safari.fill", color: .cyan) {
                        handoffBridge.pushCurrentMacBrowserTab(session: agent.activeSession)
                    }
                    actionButton(title: "Biometric Unlock", icon: "touchid", color: .pink) {
                        biometricBridge.requestBiometricUnlock(session: agent.activeSession)
                    }
                    actionButton(title: "Folder Sync", icon: "arrow.triangle.2.circlepath", color: .teal) {
                        folderSync.startSync(session: agent.activeSession)
                    }
                    actionButton(title: "Device Storage", icon: "folder.badge.gearshape", color: .orange) {
                        selectedTab = "Storage"
                    }
                }

                // Recent Transfers Preview
                HStack {
                    Text("Recent Transfers")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("View All (\(transferEngine.transfers.count))") {
                        selectedTab = "Transfers"
                    }
                    .buttonStyle(.link)
                }

                if transferEngine.transfers.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.up.arrow.down.circle")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text("No recent transfers. Drag files here to send.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(30)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                } else {
                    VStack(spacing: 8) {
                        ForEach(transferEngine.transfers.prefix(3)) { item in
                            HStack {
                                Image(systemName: item.direction == .outgoing ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                                    .foregroundColor(item.direction == .outgoing ? .blue : .green)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.fileName)
                                        .font(.system(size: 13, weight: .medium))
                                    Text("\(ByteCountFormatter.string(fromByteCount: item.bytesTransferred, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: item.fileSizeBytes, countStyle: .file))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                StatusBadge(status: item.status)
                            }
                            .padding(10)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                        }
                    }
                }
            }
            .padding(24)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isDropTargeted ? Color.blue : Color.clear, lineWidth: 3)
                .padding(8)
        )
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            for provider in providers {
                if provider.canLoadObject(ofClass: URL.self) {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        if let fileURL = url {
                            Task { @MainActor in
                                transferEngine.queueOutgoingTransfer(fileURL: fileURL, session: agent.activeSession)
                                selectedTab = "Transfers"
                            }
                        }
                    }
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
                                transferEngine.queueOutgoingTransfer(fileURL: fileURL, session: agent.activeSession)
                                selectedTab = "Transfers"
                            }
                        }
                    }
                }
            }
            return true
        }
    }

    private func connectedDeviceCard(device: PairedDevice) -> some View {
        HStack(spacing: 20) {
            Image(systemName: "iphone.gen3")
                .font(.system(size: 48))
                .foregroundColor(.green)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(device.name)
                        .font(.title2)
                        .fontWeight(.bold)
                    Circle()
                        .fill(Color.green)
                        .frame(width: 10, height: 10)
                    Text("Connected via Wi-Fi")
                        .font(.caption)
                        .foregroundColor(.green)
                }

                HStack(spacing: 16) {
                    Label("\(device.batteryLevel)% \(device.isCharging ? "⚡️" : "")", systemImage: batteryIcon(for: device.batteryLevel))
                        .foregroundColor(.primary)
                    Label(device.wifiSsid, systemImage: "wifi")
                        .foregroundColor(.secondary)
                    Label("Direct P2P", systemImage: "lock.shield.fill")
                        .foregroundColor(.secondary)
                }
                .font(.subheadline)
            }
            Spacer()
        }
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
    }

    private func disconnectedCard() -> some View {
        HStack(spacing: 20) {
            Image(systemName: "iphone.slash")
                .font(.system(size: 44))
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("No Phone Connected")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Ensure your Android phone has Continuity open on the same Wi-Fi network.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Pair Phone") {
                selectedTab = "Devices"
                agent.isPairingSheetVisible = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }

    private func actionButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    private func selectAndSendFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            transferEngine.queueOutgoingTransfer(fileURL: url, session: agent.activeSession)
            selectedTab = "Transfers"
        }
    }

    private func batteryIcon(for level: Int) -> String {
        switch level {
        case 0...20: return "battery.25"
        case 21...50: return "battery.50"
        case 51...80: return "battery.75"
        default: return "battery.100"
        }
    }
}

public struct StatusBadge: View {
    public let status: TransferStatus

    public var body: some View {
        Text(status.rawValue.capitalized)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor.opacity(0.15))
            .foregroundColor(backgroundColor)
            .cornerRadius(6)
    }

    private var backgroundColor: Color {
        switch status {
        case .completed: return .green
        case .inProgress: return .blue
        case .pending: return .orange
        case .failed: return .red
        case .cancelled: return .gray
        }
    }
}
