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

    public static func adaptiveChunkSize(for fileSizeBytes: Int64) -> Int {
        if fileSizeBytes < 5 * 1024 * 1024 {
            return 256 * 1024 // 256 KB
        } else if fileSizeBytes < 50 * 1024 * 1024 {
            return 1024 * 1024 // 1 MB
        } else {
            return 4 * 1024 * 1024 // 4 MB for large files & USB
        }
    }

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
        let effectiveChunkSize = Self.adaptiveChunkSize(for: fileSize)

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

        // Asynchronously stream chunk-by-chunk with TCP backpressure
        Task.detached {
            guard let readHandle = try? FileHandle(forReadingFrom: fileURL) else {
                await self.updateStatus(transferId: transferId, status: .failed, error: "Failed to read file")
                return
            }
            defer { try? readHandle.close() }

            let totalChunks = Int32((Int(fileSize) + effectiveChunkSize - 1) / max(effectiveChunkSize, 1))

            let offer = TransferOffer(
                transferId: transferId,
                fileName: fileName,
                fileSizeBytes: fileSize,
                sha256Checksum: "streamed-binary",
                totalChunks: totalChunks,
                chunkSizeBytes: Int64(effectiveChunkSize)
            )

            var offerEnvelope = ContinuityEnvelope(senderDeviceId: "macos-companion")
            offerEnvelope.transferOffer = offer
            try? await session?.sendAsync(envelope: offerEnvelope)

            var offset: Int64 = 0
            var chunkIdx: Int32 = 0

            while offset < fileSize {
                let thisChunkSize = Int(min(Int64(effectiveChunkSize), fileSize - offset))
                guard let chunkBytes = try? readHandle.read(upToCount: thisChunkSize), !chunkBytes.isEmpty else {
                    break
                }

                let rawChunk = RawBinaryChunk(
                    transferId: transferId,
                    chunkIndex: UInt32(chunkIdx),
                    chunkTotal: UInt32(totalChunks),
                    data: chunkBytes
                )

                do {
                    try await session?.sendAsync(binaryChunk: rawChunk)
                } catch {
                    await self.updateStatus(transferId: transferId, status: .failed, error: error.localizedDescription)
                    return
                }

                offset += Int64(chunkBytes.count)
                chunkIdx += 1

                await self.updateProgress(transferId: transferId, bytesTransferred: offset)
            }

            let complete = TransferComplete(
                transferId: transferId,
                verified: true,
                finalPathBasename: fileName,
                bytesWritten: fileSize
            )
            var completeEnvelope = ContinuityEnvelope(senderDeviceId: "macos-companion")
            completeEnvelope.transferComplete = complete
            try? await session?.sendAsync(envelope: completeEnvelope)

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

    public func handleIncomingBinaryChunk(_ chunk: RawBinaryChunk, session: ContinuityNetworkSession?) {
        let tempURL = downloadsDirectory.appendingPathComponent("\(chunk.transferId).part")
        if let handle = try? FileHandle(forWritingTo: tempURL) {
            handle.seekToEndOfFile()
            handle.write(chunk.data)
            try? handle.close()
        } else {
            try? chunk.data.write(to: tempURL)
        }

        if let idx = transfers.firstIndex(where: { $0.id == chunk.transferId }) {
            transfers[idx].bytesTransferred += Int64(chunk.data.count)
        }
    }

    public func handleIncomingChunk(_ chunk: TransferChunk, session: ContinuityNetworkSession?) {
        // Fallback for JSON Base64 chunks if received from legacy client
        guard let chunkData = Data(base64Encoded: chunk.dataBase64) else { return }

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
