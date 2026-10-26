import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ContinuityProtocol

public struct TransfersView: View {
    @ObservedObject var engine = FileTransferEngine.shared
    @ObservedObject var agent = ConnectionAgent.shared
    @State private var isDropTargeted = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("File Transfers")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("Open Downloads Folder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: engine.downloadsDirectory.path)
                }
                Button("Send File...") {
                    selectAndSendFile()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            ZStack {
                if engine.transfers.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 48))
                            .foregroundColor(isDropTargeted ? .blue : .secondary)
                        Text(isDropTargeted ? "Drop Files to Send Now" : "No file transfers yet")
                            .font(.headline)
                        Text("Drag and drop any files or photos here to instantly transfer them to your phone.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 360)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(engine.transfers) { item in
                            transferRow(item: item)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isDropTargeted ? Color.blue : Color.clear, lineWidth: 3)
                    .padding(8)
            )
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers: providers)
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let fileURL = url {
                        Task { @MainActor in
                            engine.queueOutgoingTransfer(fileURL: fileURL, session: agent.activeSession)
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
                            engine.queueOutgoingTransfer(fileURL: fileURL, session: agent.activeSession)
                        }
                    }
                }
            }
        }
        return true
    }

    private func transferRow(item: ActiveTransfer) -> some View {
        HStack(spacing: 14) {
            Image(systemName: item.direction == .outgoing ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .font(.system(size: 28))
                .foregroundColor(item.direction == .outgoing ? .blue : .green)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.fileName)
                    .font(.system(size: 14, weight: .semibold))

                if item.status == .inProgress {
                    ProgressView(value: item.progress)
                        .progressViewStyle(.linear)
                }

                HStack {
                    Text("\(ByteCountFormatter.string(fromByteCount: item.bytesTransferred, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: item.fileSizeBytes, countStyle: .file))")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let err = item.errorMessage {
                        Text("• \(err)")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }

            Spacer()

            StatusBadge(status: item.status)

            if item.status == .completed, let localURL = item.localURL {
                Button("Reveal") {
                    NSWorkspace.shared.activateFileViewerSelecting([localURL])
                }
                .buttonStyle(.borderless)
            } else if item.status == .inProgress {
                Button("Cancel") {
                    engine.cancelTransfer(id: item.id)
                }
                .buttonStyle(.borderless)
                .foregroundColor(.red)
            }
        }
        .padding(.vertical, 6)
    }

    private func selectAndSendFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            engine.queueOutgoingTransfer(fileURL: url, session: agent.activeSession)
        }
    }
}
