import SwiftUI
import AppKit
import ContinuityProtocol

public struct TransfersView: View {
    @ObservedObject var engine = FileTransferEngine.shared
    @ObservedObject var agent = ConnectionAgent.shared

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

            if engine.transfers.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No file transfers yet")
                        .font(.headline)
                    Text("Send photos, documents, and videos directly to your Android device with zero size limits.")
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
