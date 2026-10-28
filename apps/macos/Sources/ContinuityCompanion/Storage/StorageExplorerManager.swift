import Foundation
import AppKit
import ContinuityProtocol

@MainActor
public final class StorageExplorerManager: ObservableObject {
    public static let shared = StorageExplorerManager()

    @Published public var currentPath: String = "/storage/emulated/0"
    @Published public var items: [StorageItem] = []
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil

    private init() {}

    public func navigateTo(path: String, session: ContinuityNetworkSession?) {
        let activeSession = session ?? ConnectionAgent.shared.activeSession
        if let s = activeSession {
            isLoading = true
            errorMessage = nil
            self.currentPath = path

            var env = ContinuityEnvelope(senderDeviceId: "macos-companion")
            env.storageListRequest = StorageListRequest(path: path)
            s.send(envelope: env)
            ConnectionAgent.shared.debugLog("Requested directory listing via Wi-Fi for: \(path)")
        } else if AdvancedHostManager.shared.isAdbAvailable && !AdvancedHostManager.shared.connectedAdbDevices.isEmpty {
            loadDirectoryViaAdb(path: path)
        } else {
            errorMessage = "No active connection to device. Connect via Wi-Fi or Wireless ADB."
        }
    }

    public func navigateUp(session: ContinuityNetworkSession?) {
        let parent = (currentPath as NSString).deletingLastPathComponent
        if !parent.isEmpty && parent != "/" && parent != currentPath {
            navigateTo(path: parent, session: session)
        }
    }

    public func refresh(session: ContinuityNetworkSession?) {
        navigateTo(path: currentPath, session: session)
    }

    public func handleStorageListResponse(_ response: StorageListResponse) {
        self.isLoading = false
        self.currentPath = response.path
        self.items = response.items
        ConnectionAgent.shared.debugLog("Received \(response.items.count) items for path: \(response.path)")
    }

    public func loadDirectoryViaAdb(path: String) {
        isLoading = true
        errorMessage = nil
        self.currentPath = path

        let adbPath = AdvancedHostManager.shared.adbPath
        let env = AdvancedHostManager.shared.buildProcessEnvironment()
        let target = AdvancedHostManager.shared.resolveActiveDevice()

        Task.detached {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: adbPath)
            proc.environment = env
            var args = ["shell", "ls", "-la", path]
            if let t = target, !t.isEmpty {
                args = ["-s", t] + args
            }
            proc.arguments = args

            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe
            do {
                try proc.run()
                proc.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                var parsedItems: [StorageItem] = []
                for line in output.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty || trimmed.hasPrefix("total") { continue }
                    let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                    guard parts.count >= 8 else { continue }
                    let perms = parts[0]
                    let isDir = perms.hasPrefix("d")
                    let size = Int64(parts[4]) ?? 0
                    let name = parts.dropFirst(7).joined(separator: " ")
                    if name == "." || name == ".." { continue }
                    if name.hasPrefix(".") && name != ".ContinuitySync" { continue }

                    parsedItems.append(StorageItem(
                        name: name,
                        isDirectory: isDir,
                        sizeBytes: isDir ? 0 : size,
                        modifiedTimeMs: Int64(Date().timeIntervalSince1970 * 1000)
                    ))
                }

                parsedItems.sort { a, b in
                    if a.isDirectory != b.isDirectory {
                        return a.isDirectory && !b.isDirectory
                    }
                    return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                }

                let finalItems = parsedItems
                await MainActor.run {
                    self.items = finalItems
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    public func downloadFile(item: StorageItem) {
        guard !item.isDirectory else { return }
        let fileName = item.name
        let remoteFilePath = (currentPath as NSString).appendingPathComponent(fileName)
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let continuityDir = downloads.appendingPathComponent("Continuity", isDirectory: true)
        if !FileManager.default.fileExists(atPath: continuityDir.path) {
            try? FileManager.default.createDirectory(at: continuityDir, withIntermediateDirectories: true)
        }
        let localDestURL = continuityDir.appendingPathComponent(fileName)

        if AdvancedHostManager.shared.isAdbAvailable && !AdvancedHostManager.shared.connectedAdbDevices.isEmpty {
            let adbPath = AdvancedHostManager.shared.adbPath
            let env = AdvancedHostManager.shared.buildProcessEnvironment()
            let target = AdvancedHostManager.shared.resolveActiveDevice()

            Task.detached {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: adbPath)
                proc.environment = env
                var args = ["pull", remoteFilePath, localDestURL.path]
                if let t = target, !t.isEmpty {
                    args = ["-s", t] + args
                }
                proc.arguments = args
                try? proc.run()
                proc.waitUntilExit()

                if proc.terminationStatus == 0 {
                    await MainActor.run {
                        NSWorkspace.shared.activateFileViewerSelecting([localDestURL])
                    }
                }
            }
        }
    }

    public func uploadFile(fileURL: URL, to targetDir: String) {
        let fileName = fileURL.lastPathComponent
        let remoteDestPath = (targetDir as NSString).appendingPathComponent(fileName)

        if AdvancedHostManager.shared.isAdbAvailable && !AdvancedHostManager.shared.connectedAdbDevices.isEmpty {
            let adbPath = AdvancedHostManager.shared.adbPath
            let env = AdvancedHostManager.shared.buildProcessEnvironment()
            let target = AdvancedHostManager.shared.resolveActiveDevice()

            Task.detached {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: adbPath)
                proc.environment = env
                var args = ["push", fileURL.path, remoteDestPath]
                if let t = target, !t.isEmpty {
                    args = ["-s", t] + args
                }
                proc.arguments = args
                try? proc.run()
                proc.waitUntilExit()

                // Trigger media scanner
                let scanProc = Process()
                scanProc.executableURL = URL(fileURLWithPath: adbPath)
                scanProc.environment = env
                var scanArgs = ["shell", "am", "broadcast", "-a", "android.intent.action.MEDIA_SCANNER_SCAN_FILE", "-d", "file://\(remoteDestPath)"]
                if let t = target, !t.isEmpty {
                    scanArgs = ["-s", t] + scanArgs
                }
                scanProc.arguments = scanArgs
                try? scanProc.run()

                await MainActor.run {
                    self.refresh(session: nil)
                }
            }
        } else if let session = ConnectionAgent.shared.activeSession {
            FileTransferEngine.shared.queueOutgoingTransfer(fileURL: fileURL, session: session)
        }
    }
}
