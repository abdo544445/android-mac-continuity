import Foundation
import ContinuityProtocol

public enum TransferDirection: String, Codable, Sendable {
    case incoming
    case outgoing
}

public enum TransferStatus: String, Codable, Sendable {
    case pending
    case inProgress
    case completed
    case failed
    case cancelled
}

public struct ActiveTransfer: Identifiable, Sendable {
    public let id: String
    public let fileName: String
    public let fileSizeBytes: Int64
    public var bytesTransferred: Int64
    public var direction: TransferDirection
    public var status: TransferStatus
    public var progress: Double {
        fileSizeBytes > 0 ? Double(bytesTransferred) / Double(fileSizeBytes) : 0.0
    }
    public var localURL: URL?
    public var errorMessage: String?
    public var startTime: Date
}

@MainActor
public final class FileTransferEngine: ObservableObject {
    public static let shared = FileTransferEngine()

    @Published public var transfers: [ActiveTransfer] = []

    public let downloadsDirectory: URL
    private let chunkSize: Int = 512 * 1024 // 512 KB

    public init() {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let continuityDir = downloads.appendingPathComponent("Continuity", isDirectory: true)
        if !FileManager.default.fileExists(atPath: continuityDir.path) {
            try? FileManager.default.createDirectory(at: continuityDir, withIntermediateDirectories: true)
        }
        self.downloadsDirectory = continuityDir
    }

    public func queueOutgoingTransfer(fileURL: URL, session: ContinuityNetworkSession?) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let fileSize = attributes[.size] as? Int64 else {
            return
        }

        let transferId = UUID().uuidString
        let fileName = fileURL.lastPathComponent

        let transfer = ActiveTransfer(
            id: transferId,
            fileName: fileName,
            fileSizeBytes: fileSize,
            bytesTransferred: 0,
            direction: .outgoing,
            status: .inProgress,
            localURL: fileURL,
            startTime: Date()
        )
        transfers.insert(transfer, at: 0)

        // Asynchronously process and send
        Task.detached {
            guard let fileData = try? Data(contentsOf: fileURL) else {
                await self.updateStatus(transferId: transferId, status: .failed, error: "Failed to read file")
                return
            }

            let checksum = CryptoManager.shared.sha256Hex(data: fileData)
            let totalChunks = Int32((fileData.count + self.chunkSize - 1) / self.chunkSize)

            let offer = TransferOffer(
                transferId: transferId,
                fileName: fileName,
                fileSizeBytes: fileSize,
                sha256Checksum: checksum,
                totalChunks: totalChunks,
                chunkSizeBytes: Int64(self.chunkSize)
            )

            var offerEnvelope = ContinuityEnvelope(senderDeviceId: "macos-companion")
            offerEnvelope.transferOffer = offer
            session?.send(envelope: offerEnvelope)

            // Send chunks
            var offset = 0
            var chunkIdx: Int32 = 0

            while offset < fileData.count {
                let thisChunkSize = min(self.chunkSize, fileData.count - offset)
                let chunkBytes = fileData.subdata(in: offset..<(offset + thisChunkSize))
                let chunkHash = CryptoManager.shared.sha256Hex(data: chunkBytes)

                let chunkMsg = TransferChunk(
                    transferId: transferId,
                    chunkIndex: chunkIdx,
                    dataBase64: chunkBytes.base64EncodedString(),
                    chunkSha256: chunkHash
                )

                var chunkEnvelope = ContinuityEnvelope(senderDeviceId: "macos-companion")
                chunkEnvelope.transferChunk = chunkMsg
                session?.send(envelope: chunkEnvelope)

                offset += thisChunkSize
                chunkIdx += 1

                let transferred = Int64(offset)
                await self.updateProgress(transferId: transferId, bytesTransferred: transferred)
                try? await Task.sleep(nanoseconds: 2_000_000) // 2ms throttle to prevent buffer starvation
            }

            let complete = TransferComplete(
                transferId: transferId,
                verified: true,
                finalPathBasename: fileName,
                bytesWritten: fileSize
            )
            var completeEnvelope = ContinuityEnvelope(senderDeviceId: "macos-companion")
            completeEnvelope.transferComplete = complete
            session?.send(envelope: completeEnvelope)

            await self.updateStatus(transferId: transferId, status: .completed)
        }
    }

    public func handleIncomingOffer(_ offer: TransferOffer, session: ContinuityNetworkSession?) {
        let transfer = ActiveTransfer(
            id: offer.transferId,
            fileName: offer.fileName,
            fileSizeBytes: offer.fileSizeBytes,
            bytesTransferred: 0,
            direction: .incoming,
            status: .inProgress,
            startTime: Date()
        )
        transfers.insert(transfer, at: 0)

        // Accept the offer immediately
        let accept = TransferAccept(transferId: offer.transferId, resumeChunkIndex: 0)
        var env = ContinuityEnvelope(senderDeviceId: "macos-companion")
        env.transferAccept = accept
        session?.send(envelope: env)
    }

    public func handleIncomingChunk(_ chunk: TransferChunk, session: ContinuityNetworkSession?) {
        guard let chunkData = Data(base64Encoded: chunk.dataBase64) else { return }

        // Verify chunk hash
        let computed = CryptoManager.shared.sha256Hex(data: chunkData)
        guard computed == chunk.chunkSha256 else {
            updateStatus(transferId: chunk.transferId, status: .failed, error: "Chunk checksum mismatch")
            return
        }

        let tempURL = downloadsDirectory.appendingPathComponent("\(chunk.transferId).part")
        if let handle = try? FileHandle(forWritingTo: tempURL) {
            handle.seekToEndOfFile()
            handle.write(chunkData)
            try? handle.close()
        } else {
            try? chunkData.write(to: tempURL)
        }

        if let idx = transfers.firstIndex(where: { $0.id == chunk.transferId }) {
            transfers[idx].bytesTransferred += Int64(chunkData.count)
        }
    }

    public func handleIncomingComplete(_ complete: TransferComplete) {
        guard let idx = transfers.firstIndex(where: { $0.id == complete.transferId }) else { return }
        let rawName = (complete.finalPathBasename as NSString).lastPathComponent
        let fileName = rawName.isEmpty ? "file.bin" : rawName
        let tempURL = downloadsDirectory.appendingPathComponent("\(complete.transferId).part")

        var destinationURL = downloadsDirectory.appendingPathComponent(fileName)
        var counter = 1
        let nameWithoutExt = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension

        while FileManager.default.fileExists(atPath: destinationURL.path) {
            let newName = ext.isEmpty ? "\(nameWithoutExt) (\(counter))" : "\(nameWithoutExt) (\(counter)).\(ext)"
            destinationURL = downloadsDirectory.appendingPathComponent(newName)
            counter += 1
        }

        try? FileManager.default.moveItem(at: tempURL, to: destinationURL)

        transfers[idx].status = .completed
        transfers[idx].localURL = destinationURL
        transfers[idx].bytesTransferred = complete.bytesWritten
    }

    public func cancelTransfer(id: String) {
        if let idx = transfers.firstIndex(where: { $0.id == id }) {
            transfers[idx].status = .cancelled
            let tempURL = downloadsDirectory.appendingPathComponent("\(id).part")
            try? FileManager.default.removeItem(at: tempURL)
        }
    }

    private func updateProgress(transferId: String, bytesTransferred: Int64) {
        if let idx = transfers.firstIndex(where: { $0.id == transferId }) {
            transfers[idx].bytesTransferred = bytesTransferred
        }
    }

    private func updateStatus(transferId: String, status: TransferStatus, error: String? = nil) {
        if let idx = transfers.firstIndex(where: { $0.id == transferId }) {
            transfers[idx].status = status
            transfers[idx].errorMessage = error
        }
    }
}
