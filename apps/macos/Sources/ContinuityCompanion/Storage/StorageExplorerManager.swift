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
        guard let activeSession = session ?? ConnectionAgent.shared.activeSession else {
            errorMessage = "No active connection to device."
            return
        }

        isLoading = true
        errorMessage = nil
        self.currentPath = path

        var env = ContinuityEnvelope(senderDeviceId: "macos-companion")
        env.storageListRequest = StorageListRequest(path: path)
        activeSession.send(envelope: env)
        ConnectionAgent.shared.debugLog("Requested directory listing for: \(path)")
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
}
