import Foundation
import AppKit
import ContinuityProtocol

@MainActor
public final class PhotoBackupManager: ObservableObject {
    public static let shared = PhotoBackupManager()

    @Published public var backupDirectory: URL
    @Published public var backedUpCount: Int = 0
    @Published public var lastBackupDate: String = "Never"
    @Published public var isBackingUp: Bool = false
    @Published public var statusMessage: String = "Ready"

    private let fileManager = FileManager.default

    public init() {
        let pictures = fileManager.urls(for: .picturesDirectory, in: .userDomainMask).first!
        let dir = pictures.appendingPathComponent("ContinuityBackup", isDirectory: true)
        self.backupDirectory = dir

        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        refreshStatistics()
    }

    public func refreshStatistics() {
        guard let files = try? fileManager.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles) else {
            return
        }
        self.backedUpCount = files.count
        if let latest = files.compactMap({ (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate }).max() {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            self.lastBackupDate = formatter.string(from: latest)
        }
    }

    public func setBackupDirectory(_ url: URL) {
        self.backupDirectory = url
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        refreshStatistics()
    }

    /// Ingests a photo or video payload, deduplicating via SHA-256.
    public func ingestPhoto(fileName: String, data: Data, expectedSha256: String) -> (saved: Bool, path: URL) {
        let destination = backupDirectory.appendingPathComponent(fileName)

        // Check deduplication
        if fileManager.fileExists(atPath: destination.path) {
            if let existingData = try? Data(contentsOf: destination) {
                let existingHash = CryptoManager.shared.sha256Hex(data: existingData)
                if existingHash.lowercased() == expectedSha256.lowercased() {
                    ConnectionAgent.shared.debugLog("Photo \(fileName) already exists with identical SHA-256. Skipping.")
                    return (false, destination)
                }
            }
        }

        do {
            try data.write(to: destination, options: .atomic)
            self.backedUpCount += 1
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            self.lastBackupDate = formatter.string(from: Date())
            self.statusMessage = "Backed up \(fileName)"
            ConnectionAgent.shared.debugLog("Successfully saved photo backup: \(fileName) (\(data.count) bytes)")
            return (true, destination)
        } catch {
            ConnectionAgent.shared.debugLog("Failed saving photo backup: \(error)")
            return (false, destination)
        }
    }

    /// Handles a photo backup manifest and returns paths of files needing transfer
    public func resolveNeededPhotos(manifest: FolderSyncManifest) -> [String] {
        var needed: [String] = []
        for file in manifest.files {
            let dest = backupDirectory.appendingPathComponent(file.path)
            if !fileManager.fileExists(atPath: dest.path) {
                needed.append(file.path)
            } else if let existingData = try? Data(contentsOf: dest) {
                let existingHash = CryptoManager.shared.sha256Hex(data: existingData)
                if existingHash.lowercased() != file.sha256.lowercased() {
                    needed.append(file.path)
                }
            }
        }
        return needed
    }
}
