import SwiftUI
import AppKit

public struct BackupSyncView: View {
    @State private var backupDirectory: URL = {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!
        return pictures.appendingPathComponent("ContinuityBackup", isDirectory: true)
    }()
    @State private var wifiOnly = true
    @State private var chargingOnly = true
    @State private var autoSyncOnConnect = true
    @State private var lastBackupDate = "Never"
    @State private var backedUpCount = 0

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                Text("Photo Backup & Folder Sync")
                    .font(.title2)
                    .fontWeight(.bold)

                // Backup Status Card
                HStack(spacing: 16) {
                    Image(systemName: "photo.stack.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.blue)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Incremental Photo Backup")
                            .font(.headline)
                        Text("Copies new photos and videos without overwriting or deleting existing files on your phone or Mac.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Sync Now") {
                        backedUpCount += 14
                        lastBackupDate = "Just now"
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)

                // Destination Folder
                VStack(alignment: .leading, spacing: 8) {
                    Text("Target Backup Directory")
                        .font(.headline)

                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundColor(.yellow)
                        Text(backupDirectory.path)
                            .font(.system(size: 13, design: .monospaced))
                            .lineLimit(1)
                        Spacer()
                        Button("Change...") {
                            selectBackupFolder()
                        }
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }

                // Settings & Conditions
                VStack(alignment: .leading, spacing: 14) {
                    Text("Backup Conditions")
                        .font(.headline)

                    Toggle("Sync only when phone is connected to Wi-Fi", isOn: $wifiOnly)
                    Toggle("Sync only when phone is charging", isOn: $chargingOnly)
                    Toggle("Automatically check for new media upon connection", isOn: $autoSyncOnConnect)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)

                // Stats
                HStack(spacing: 24) {
                    statBox(title: "Last Backup", value: lastBackupDate)
                    statBox(title: "Backed Up Media", value: "\(backedUpCount) items")
                    statBox(title: "Sync Mode", value: "Non-destructive")
                }
            }
            .padding(24)
        }
    }

    private func statBox(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private func selectBackupFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            backupDirectory = url
        }
    }
}
