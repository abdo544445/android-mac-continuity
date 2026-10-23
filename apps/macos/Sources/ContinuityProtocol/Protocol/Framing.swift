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

public struct FrameHeader {
    public static let magic: [UInt8] = [0x43, 0x4E, 0x54, 0x31] // "CNT1"
    public static let headerSize = 8
    public static let maxPayloadSize: UInt32 = 16 * 1024 * 1024 // 16 MB

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
        frame.append(0x00) // flags
        frame.append(0x00) // encryptionMode: 0x00 (Plain text JSON envelope)
        frame.append(contentsOf: [0x00, 0x00]) // reserved

        var bigEndianLength = UInt32(payloadData.count).bigEndian
        frame.append(Data(bytes: &bigEndianLength, count: 4))
        frame.append(payloadData)

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

    public func nextEnvelope() throws -> ContinuityEnvelope? {
        while buffer.count >= FrameHeader.headerSize {
            // Find magic bytes
            guard buffer[0] == FrameHeader.magic[0],
                  buffer[1] == FrameHeader.magic[1],
                  buffer[2] == FrameHeader.magic[2],
                  buffer[3] == FrameHeader.magic[3] else {
                // Discard invalid byte until we align with magic
                buffer.removeFirst(1)
                continue
            }

            let flags = buffer[4]
            let encMode = buffer[5]
            _ = flags
            _ = encMode

            let lengthData = buffer.subdata(in: 8..<12)
            let length = lengthData.withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian

            guard length <= FrameHeader.maxPayloadSize else {
                throw FramingError.payloadTooLarge(length)
            }

            let totalFrameSize = 12 + Int(length)
            guard buffer.count >= totalFrameSize else {
                // Need more data
                return nil
            }

            let payloadData = buffer.subdata(in: 12..<totalFrameSize)
            buffer.removeSubrange(0..<totalFrameSize)

            do {
                let envelope = try jsonDecoder.decode(ContinuityEnvelope.self, from: payloadData)
                return envelope
            } catch {
                throw FramingError.decodingFailed(error.localizedDescription)
            }
        }

        return nil
    }

    public func reset() {
        buffer.removeAll()
    }
}
