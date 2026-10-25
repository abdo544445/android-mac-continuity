import Foundation
import AppKit
import CryptoKit
import ContinuityProtocol

@MainActor
public final class FolderSyncEngine: ObservableObject {
    public static let shared = FolderSyncEngine()

    @Published public var isSyncing: Bool = false
    @Published public var syncStatusMessage: String = "Idle"
    @Published public var localSyncPath: URL
    @Published public var syncedFilesCount: Int = 0

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let syncDir = home.appendingPathComponent("ContinuitySync", isDirectory: true)
        self.localSyncPath = syncDir

        if !FileManager.default.fileExists(atPath: syncDir.path) {
            try? FileManager.default.createDirectory(at: syncDir, withIntermediateDirectories: true)
        }
    }

    public func startSync(session: ContinuityNetworkSession?) {
        guard let activeSession = session ?? ConnectionAgent.shared.activeSession else {
            syncStatusMessage = "Cannot sync: No connected device"
            return
        }

        isSyncing = true
        syncStatusMessage = "Scanning local folder..."
        let root = self.localSyncPath

        Task.detached {
            let manifest = self.generateLocalManifest(root: root)
            await MainActor.run {
                self.syncStatusMessage = "Manifest generated (\(manifest.files.count) files). Sending to device..."
                var env = ContinuityEnvelope(senderDeviceId: "macos-companion")
                env.folderSyncManifest = manifest
                activeSession.send(envelope: env)
                self.syncedFilesCount = manifest.files.count
                self.isSyncing = false
                self.syncStatusMessage = "Up to date (\(manifest.files.count) files synced)"
                ConnectionAgent.shared.debugLog("Sent FolderSyncManifest to device (\(manifest.files.count) files)")
            }
        }
    }

    public func handleRemoteManifest(_ manifest: FolderSyncManifest, session: ContinuityNetworkSession?) {
        ConnectionAgent.shared.debugLog("Received remote FolderSyncManifest: \(manifest.files.count) files in \(manifest.folderName)")
        self.syncStatusMessage = "Received device manifest (\(manifest.files.count) files). Synchronizing..."
        let root = self.localSyncPath

        Task.detached {
            let localManifest = self.generateLocalManifest(root: root)
            let localMap = Dictionary(uniqueKeysWithValues: localManifest.files.map { ($0.path, $0) })

            // Find local files missing on remote or newer, and send them
            for localFile in localManifest.files {
                let remoteFile = manifest.files.first { $0.path == localFile.path }
                if remoteFile == nil || remoteFile?.sha256 != localFile.sha256 {
                    let fileUrl = root.appendingPathComponent(localFile.path)
                    if FileManager.default.fileExists(atPath: fileUrl.path) {
                        await MainActor.run {
                            FileTransferEngine.shared.queueOutgoingTransfer(fileURL: fileUrl, session: session)
                        }
                    }
                }
            }

            await MainActor.run {
                self.syncStatusMessage = "Sync complete"
            }
        }
    }

    private nonisolated func generateLocalManifest(root: URL) -> FolderSyncManifest {
        var entries: [SyncFileEntry] = []
        let fm = FileManager.default

        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]) else {
            return FolderSyncManifest(folderName: "ContinuitySync", files: [])
        }

        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                  resourceValues.isRegularFile == true else {
                continue
            }

            let relativePath = fileURL.path.replacingOccurrences(of: root.path + "/", with: "")
            let size = Int64(resourceValues.fileSize ?? 0)
            let modDate = resourceValues.contentModificationDate ?? Date()
            let modTimeMs = Int64(modDate.timeIntervalSince1970 * 1000)

            // SHA256
            var shaHex = ""
            if let fileData = try? Data(contentsOf: fileURL) {
                let digest = SHA256.hash(data: fileData)
                shaHex = digest.map { String(format: "%02x", $0) }.joined()
            }

            entries.append(SyncFileEntry(path: relativePath, sizeBytes: size, sha256: shaHex, modifiedTimeMs: modTimeMs))
        }

        return FolderSyncManifest(folderName: "ContinuitySync", files: entries)
    }
}
