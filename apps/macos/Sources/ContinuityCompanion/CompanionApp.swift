import SwiftUI
import AppKit
import ContinuityProtocol

@main
struct CompanionApp: App {
    @StateObject private var agent = ConnectionAgent.shared
    @StateObject private var registry = DeviceRegistry.shared
    @State private var selectedTab: String = "Dashboard"

    init() {
        ConnectionAgent.shared.start()
        ClipboardBridge.shared.startMonitoring(session: nil)
    }

    var body: some Scene {
        WindowGroup("Continuity") {
            NavigationSplitView {
                List(selection: $selectedTab) {
                    Section("Connected Workspace") {
                        NavigationLink(value: "Dashboard") {
                            Label("Dashboard", systemImage: "macbook.and.iphone")
                        }
                        NavigationLink(value: "Transfers") {
                            Label("File Transfers", systemImage: "arrow.up.arrow.down")
                        }
                        NavigationLink(value: "Notifications") {
                            Label("Notifications", systemImage: "bell.badge")
                        }
                        NavigationLink(value: "Mirroring") {
                            Label("Screen Mirror", systemImage: "rectangle.inset.filled.and.cursorarrow")
                        }
                        NavigationLink(value: "Camera") {
                            Label("Webcam Stream", systemImage: "camera")
                        }
                        NavigationLink(value: "BackupSync") {
                            Label("Backup & Sync", systemImage: "photo.stack")
                        }
                    }

                    Section("Management") {
                        NavigationLink(value: "Devices") {
                            Label("Paired Devices", systemImage: "qrcode")
                        }
                        NavigationLink(value: "Settings") {
                            Label("Settings", systemImage: "gearshape")
                        }
                    }
                }
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
            } detail: {
                detailView(for: selectedTab)
            }
            .frame(minWidth: 880, minHeight: 580)
            .onChange(of: agent.shouldNavigateToMirror) { newVal in
                if newVal {
                    selectedTab = "Mirroring"
                    agent.shouldNavigateToMirror = false
                }
            }
            .sheet(item: $agent.pendingPairProposal) { proposal in
                BluetoothPinConfirmSheet(proposal: proposal)
            }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)

        MenuBarExtra {
            MenuBarView()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "iphone.gen3")
                if let dev = registry.activeDevice, dev.isConnected {
                    Text("\(dev.batteryLevel)%")
                }
            }
        }
        .menuBarExtraStyle(.window)
    }

    @ViewBuilder
    private func detailView(for tab: String) -> some View {
        switch tab {
        case "Dashboard":
            DashboardView(selectedTab: $selectedTab)
        case "Transfers":
            TransfersView()
        case "Notifications":
            NotificationsView()
        case "Mirroring":
            MirroringView()
        case "Camera":
            CameraView()
        case "BackupSync":
            BackupSyncView()
        case "Devices":
            DevicesView()
        case "Settings":
            SettingsView()
        default:
            DashboardView(selectedTab: $selectedTab)
        }
    }
}

struct BluetoothPinConfirmSheet: View {
    let proposal: PendingPairProposal
    @ObservedObject var agent = ConnectionAgent.shared

    var formattedPin: String {
        if proposal.pin.count == 6 {
            let prefix = proposal.pin.prefix(3)
            let suffix = proposal.pin.suffix(3)
            return "\(prefix) \(suffix)"
        }
        return proposal.pin
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.line.dotted.person.fill")
                .font(.system(size: 46))
                .foregroundColor(.blue)

            Text("Bluetooth-Style Pairing Request")
                .font(.title2)
                .fontWeight(.bold)

            Text("Confirm that this 6-digit PIN matches the code displayed on **\(proposal.deviceName)**:")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Text(formattedPin)
                .font(.system(size: 40, weight: .heavy, design: .monospaced))
                .tracking(6)
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
                .background(Color.blue.opacity(0.12))
                .foregroundColor(.primary)
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.blue.opacity(0.4), lineWidth: 1.5)
                )

            Text("You can confirm this pairing from either your Mac or your Android device.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Button(role: .cancel) {
                    agent.declinePendingPairing()
                } label: {
                    Text("Decline")
                        .frame(width: 120)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    agent.confirmPendingPairing()
                } label: {
                    Text("Accept & Pair")
                        .fontWeight(.semibold)
                        .frame(width: 150)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.top, 8)
        }
        .padding(32)
        .frame(width: 440)
    }
}
