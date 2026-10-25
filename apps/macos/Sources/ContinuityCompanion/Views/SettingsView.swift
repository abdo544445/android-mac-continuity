import SwiftUI
import ContinuityProtocol

public struct SettingsView: View {
    @ObservedObject var advancedHost = AdvancedHostManager.shared
    @ObservedObject var clipboardBridge = ClipboardBridge.shared
    @AppStorage("autoStartAtLogin") private var autoStartAtLogin = true
    @AppStorage("bonjourPort") private var bonjourPort = 52400

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Settings & Preferences")
                    .font(.title2)
                    .fontWeight(.bold)

                // General
                VStack(alignment: .leading, spacing: 14) {
                    Text("General")
                        .font(.headline)

                    Toggle("Launch Continuity at Mac login", isOn: $autoStartAtLogin)
                    Toggle("Keep running in menu bar when window is closed", isOn: .constant(true))
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)

                // Privacy
                VStack(alignment: .leading, spacing: 14) {
                    Text("Privacy & Security")
                        .font(.headline)

                    Toggle("Automatically sync clipboard changes", isOn: $clipboardBridge.autoSyncEnabled)
                    Toggle("Filter sensitive clipboard contents (passwords, tokens)", isOn: $clipboardBridge.filterSensitiveData)
                    Toggle("Require explicit Mac confirmation before accepting files", isOn: .constant(false))
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)

                // Advanced Personal Edition Helper
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Advanced Personal Edition (scrcpy & ADB)")
                            .font(.headline)
                        Spacer()
                        Text(advancedHost.isAdbAvailable ? "Detected" : "Not Found")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(advancedHost.isAdbAvailable ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                            .foregroundColor(advancedHost.isAdbAvailable ? .green : .orange)
                            .cornerRadius(6)
                    }

                    Text("Enables ultra-low latency screen mirroring (< 35ms), direct keyboard and mouse navigation, and automated workflows.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("ADB Path:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(advancedHost.adbPath.isEmpty ? "Missing (install via `brew install android-platform-tools`)" : advancedHost.adbPath)
                                .font(.system(size: 12, design: .monospaced))
                        }

                        HStack {
                            Text("scrcpy Path:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(advancedHost.scrcpyPath.isEmpty ? "Missing (install via `brew install scrcpy`)" : advancedHost.scrcpyPath)
                                .font(.system(size: 12, design: .monospaced))
                        }
                    }

                    HStack(spacing: 12) {
                        Button("Re-detect Tools") {
                            advancedHost.detectTooling()
                        }
                        .buttonStyle(.bordered)

                        if !advancedHost.isAdbAvailable || !advancedHost.isScrcpyAvailable {
                            Button(action: {
                                advancedHost.installDependenciesViaBrew()
                            }) {
                                Label("Install Dependencies (1-Click)", systemImage: "arrow.down.circle.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(advancedHost.isInstallingDependencies)
                        }
                    }

                    if advancedHost.isInstallingDependencies {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                            Text(advancedHost.dependencyInstallMessage)
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    } else if !advancedHost.dependencyInstallMessage.isEmpty {
                        Text(advancedHost.dependencyInstallMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
            }
            .padding(24)
        }
    }
}
