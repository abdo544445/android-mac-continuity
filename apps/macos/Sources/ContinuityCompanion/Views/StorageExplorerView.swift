import SwiftUI
import ContinuityProtocol

public struct StorageExplorerView: View {
    @ObservedObject var storageManager = StorageExplorerManager.shared
    @ObservedObject var agent = ConnectionAgent.shared
    @State private var searchFilter: String = ""

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header Path Bar
            HStack(spacing: 12) {
                Button(action: {
                    storageManager.navigateUp(session: agent.activeSession)
                }) {
                    Label("Back", systemImage: "arrow.up")
                }
                .disabled(storageManager.currentPath == "/storage/emulated/0" || storageManager.currentPath == "/")

                Button(action: {
                    storageManager.refresh(session: agent.activeSession)
                }) {
                    Image(systemName: "arrow.clockwise")
                }

                TextField("Path", text: .constant(storageManager.currentPath))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                Spacer()

                Button(action: {
                    uploadFileToDevice()
                }) {
                    Label("Upload File", systemImage: "arrow.up.doc")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // File Listing Table
            if storageManager.isLoading {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                    Text("Fetching device files...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else if storageManager.items.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "folder")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No files found or folder is empty.")
                        .foregroundColor(.secondary)
                    Button("Load Root Storage") {
                        storageManager.navigateTo(path: "/storage/emulated/0", session: agent.activeSession)
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
            } else {
                List {
                    ForEach(filteredItems, id: \.name) { item in
                        HStack(spacing: 12) {
                            Image(systemName: item.isDirectory ? "folder.fill" : fileIcon(for: item.name))
                                .foregroundColor(item.isDirectory ? .blue : .secondary)
                                .font(.system(size: 18))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.system(size: 14, weight: item.isDirectory ? .medium : .regular))
                                HStack(spacing: 12) {
                                    if !item.isDirectory {
                                        Text(ByteCountFormatter.string(fromByteCount: item.sizeBytes, countStyle: .file))
                                    }
                                    let date = Date(timeIntervalSince1970: Double(item.modifiedTimeMs) / 1000.0)
                                    Text(date.formatted(date: .abbreviated, time: .shortened))
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }

                            Spacer()

                            if item.isDirectory {
                                Button("Open") {
                                    let newPath = (storageManager.currentPath as NSString).appendingPathComponent(item.name)
                                    storageManager.navigateTo(path: newPath, session: agent.activeSession)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .onAppear {
            if storageManager.items.isEmpty {
                storageManager.navigateTo(path: "/storage/emulated/0", session: agent.activeSession)
            }
        }
    }

    private var filteredItems: [StorageItem] {
        if searchFilter.isEmpty {
            return storageManager.items
        }
        return storageManager.items.filter { $0.name.localizedCaseInsensitiveContains(searchFilter) }
    }

    private func fileIcon(for name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "webp", "gif": return "photo"
        case "mp4", "mkv", "mov": return "film"
        case "mp3", "m4a", "flac": return "music.note"
        case "pdf": return "doc.richtext"
        case "zip", "tar", "gz": return "doc.zipper"
        default: return "doc"
        }
    }

    private func uploadFileToDevice() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            FileTransferEngine.shared.queueOutgoingTransfer(fileURL: url, session: agent.activeSession)
        }
    }
}
