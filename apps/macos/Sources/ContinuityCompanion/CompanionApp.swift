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
