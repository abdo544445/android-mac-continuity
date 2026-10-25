import Foundation

public enum FramingError: Error, LocalizedError {
    case invalidMagic
    case payloadTooLarge(UInt32)
    case incompleteFrame
    case decryptionFailed
    case encodingFailed(String)
    case decodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidMagic:
            return "Invalid frame magic bytes (expected 'CNT1')"
        case .payloadTooLarge(let size):
            return "Frame payload size (\(size) bytes) exceeds maximum limit (16MB)"
        case .incompleteFrame:
            return "Buffer does not contain a full frame"
        case .decryptionFailed:
            return "Failed to decrypt frame payload"
        case .encodingFailed(let msg):
            return "Failed to encode frame: \(msg)"
        case .decodingFailed(let msg):
            return "Failed to decode frame: \(msg)"
        }
    }
}

public struct RawBinaryChunk: Sendable, Equatable {
    public let transferId: String
    public let chunkIndex: UInt32
    public let chunkTotal: UInt32
    public let data: Data

    public init(transferId: String, chunkIndex: UInt32, chunkTotal: UInt32, data: Data) {
        self.transferId = transferId
        self.chunkIndex = chunkIndex
        self.chunkTotal = chunkTotal
        self.data = data
    }
}

public enum DecodedFrame: Sendable {
    case envelope(ContinuityEnvelope)
    case binaryChunk(RawBinaryChunk)
}

public struct FrameHeader {
    public static let magic: [UInt8] = [0x43, 0x4E, 0x54, 0x31] // "CNT1"
    public static let headerSize = 12 // 4 magic + 1 flags + 1 encMode + 2 reserved + 4 length = 12 bytes
    public static let maxPayloadSize: UInt32 = 16 * 1024 * 1024 // 16 MB

    public static let flagJsonEnvelope: UInt8 = 0x00
    public static let flagBinaryChunk: UInt8 = 0x01

    public var flags: UInt8
    public var encryptionMode: UInt8 // 0x00: Plain, 0x01: AES-256-GCM
    public var payloadLength: UInt32

    public init(flags: UInt8 = 0, encryptionMode: UInt8 = 0, payloadLength: UInt32) {
        self.flags = flags
        self.encryptionMode = encryptionMode
        self.payloadLength = payloadLength
    }
}

public final class FrameEncoder: @unchecked Sendable {
    private let jsonEncoder: JSONEncoder

    public init() {
        self.jsonEncoder = JSONEncoder()
        self.jsonEncoder.outputFormatting = []
    }

    public func encode(envelope: ContinuityEnvelope) throws -> Data {
        let payloadData: Data
        do {
            payloadData = try jsonEncoder.encode(envelope)
        } catch {
            throw FramingError.encodingFailed(error.localizedDescription)
        }

        var frame = Data()
        frame.append(contentsOf: FrameHeader.magic)
        frame.append(FrameHeader.flagJsonEnvelope) // flags: 0x00
        frame.append(0x00) // encryptionMode: 0x00 (Plain text JSON envelope)
        frame.append(contentsOf: [0x00, 0x00]) // reserved

        var bigEndianLength = UInt32(payloadData.count).bigEndian
        frame.append(Data(bytes: &bigEndianLength, count: 4))
        frame.append(payloadData)

        return frame
    }

    public func encode(binaryChunk: RawBinaryChunk) -> Data {
        // Construct binary chunk payload: 36 bytes ID + 4 bytes chunkIndex + 4 bytes chunkTotal + data
        var idBytes = [UInt8](repeating: 0, count: 36)
        let utf8 = Array(binaryChunk.transferId.utf8)
        let count = min(utf8.count, 36)
        for i in 0..<count {
            idBytes[i] = utf8[i]
        }

        var payload = Data()
        payload.append(contentsOf: idBytes)

        var idxBE = binaryChunk.chunkIndex.bigEndian
        payload.append(Data(bytes: &idxBE, count: 4))

        var totBE = binaryChunk.chunkTotal.bigEndian
        payload.append(Data(bytes: &totBE, count: 4))

        payload.append(binaryChunk.data)

        var frame = Data()
        frame.append(contentsOf: FrameHeader.magic)
        frame.append(FrameHeader.flagBinaryChunk) // flags: 0x01
        frame.append(0x00) // encMode: 0x00
        frame.append(contentsOf: [0x00, 0x00]) // reserved

        var bigEndianLength = UInt32(payload.count).bigEndian
        frame.append(Data(bytes: &bigEndianLength, count: 4))
        frame.append(payload)

        return frame
    }
}

public final class FrameDecoder: @unchecked Sendable {
    private var buffer = Data()
    private let jsonDecoder: JSONDecoder

    public init() {
        self.jsonDecoder = JSONDecoder()
    }

    public func append(data: Data) {
        buffer.append(data)
    }

    public func nextFrame() throws -> DecodedFrame? {
        while buffer.count >= FrameHeader.headerSize {
            // Find magic bytes
            guard buffer[0] == FrameHeader.magic[0],
                  buffer[1] == FrameHeader.magic[1],
                  buffer[2] == FrameHeader.magic[2],
                  buffer[3] == FrameHeader.magic[3] else {
                buffer.removeFirst(1)
                continue
            }

            let flags = buffer[4]
            let lengthData = buffer.subdata(in: 8..<12)
            let length = lengthData.withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian

            guard length <= FrameHeader.maxPayloadSize else {
                throw FramingError.payloadTooLarge(length)
            }

            let totalFrameSize = 12 + Int(length)
            guard buffer.count >= totalFrameSize else {
                return nil
            }

            let payloadData = buffer.subdata(in: 12..<totalFrameSize)
            buffer.removeSubrange(0..<totalFrameSize)

            if flags == FrameHeader.flagBinaryChunk {
                guard payloadData.count >= 44 else {
                    throw FramingError.decodingFailed("Binary chunk payload too short (\(payloadData.count) < 44 bytes)")
                }
                let idData = payloadData.subdata(in: 0..<36)
                let idString = String(data: idData, encoding: .utf8)?.trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")) ?? ""
                let chunkIdx = payloadData.subdata(in: 36..<40).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
                let chunkTot = payloadData.subdata(in: 40..<44).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
                let rawData = payloadData.subdata(in: 44..<payloadData.count)

                return .binaryChunk(RawBinaryChunk(
                    transferId: idString,
                    chunkIndex: chunkIdx,
                    chunkTotal: chunkTot,
                    data: rawData
                ))
            } else {
                do {
                    let envelope = try jsonDecoder.decode(ContinuityEnvelope.self, from: payloadData)
                    return .envelope(envelope)
                } catch {
                    throw FramingError.decodingFailed(error.localizedDescription)
                }
            }
        }

        return nil
    }

    public func nextEnvelope() throws -> ContinuityEnvelope? {
        while let frame = try nextFrame() {
            switch frame {
            case .envelope(let envelope):
                return envelope
            case .binaryChunk:
                continue
            }
        }
        return nil
    }

    public func reset() {
        buffer.removeAll()
    }
}
