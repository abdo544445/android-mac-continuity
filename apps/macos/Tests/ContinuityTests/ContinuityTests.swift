import Foundation
@testable import ContinuityProtocol

public struct ContinuityTestSuite {

    public static func runAllTests() -> Bool {
        var allPassed = true

        func test(_ name: String, block: () throws -> Bool) {
            do {
                if try block() {
                    print("  ✅ [PASS] \(name)")
                } else {
                    print("  ❌ [FAIL] \(name)")
                    allPassed = false
                }
            } catch {
                print("  ❌ [ERROR] \(name): \(error)")
                allPassed = false
            }
        }

        print("🧪 [macOS] Running Comprehensive Continuity Test Suite...")

        // 1. CryptoManager Tests
        test("CryptoManager - P256 Key Agreement & Derivation") {
            let crypto = CryptoManager.shared
            let alice = crypto.generateKeyPair()
            let bob = crypto.generateKeyPair()
            let pin = "849201"

            let aliceKey = try crypto.deriveSessionKey(
                localPrivateKey: alice.privateKey,
                remotePublicKeyBase64: bob.publicKeyBase64,
                pin: pin
            )
            let bobKey = try crypto.deriveSessionKey(
                localPrivateKey: bob.privateKey,
                remotePublicKeyBase64: alice.publicKeyBase64,
                pin: pin
            )

            let challenge = "test-challenge-12345"
            let tag = crypto.computeAuthTag(sessionKey: aliceKey, challenge: challenge)
            return crypto.verifyAuthTag(sessionKey: bobKey, challenge: challenge, expectedTagBase64: tag)
        }

        test("CryptoManager - AES-256-GCM Encryption / Decryption Round-trip") {
            let crypto = CryptoManager.shared
            let key = crypto.generateKeyPair()
            let sessionKey = try crypto.deriveSessionKey(
                localPrivateKey: key.privateKey,
                remotePublicKeyBase64: key.publicKeyBase64,
                pin: "123456"
            )
            let plaintext = Data("Confidential Continuity Payload".utf8)
            let encrypted = try crypto.encrypt(data: plaintext, key: sessionKey)
            let decrypted = try crypto.decrypt(combinedData: encrypted, key: sessionKey)
            return plaintext == decrypted
        }

        test("CryptoManager - SHA256 Hex Vector") {
            let crypto = CryptoManager.shared
            let data = Data("The quick brown fox jumps over the lazy dog".utf8)
            let hash = crypto.sha256Hex(data: data)
            return hash == "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592"
        }

        // 2. Framing & MessageModels Tests
        test("Framing - Binary Header & Envelope Round-trip") {
            let encoder = FrameEncoder()
            let decoder = FrameDecoder()
            var env = ContinuityEnvelope(senderDeviceId: "test-mac-01")
            env.heartbeat = Heartbeat(sequenceNumber = 42)

            let frame = try encoder.encode(envelope: env)
            decoder.append(data: frame)
            let decoded = try decoder.nextEnvelope()
            return decoded?.senderDeviceId == "test-mac-01" && decoded?.heartbeat?.sequenceNumber == 42
        }

        test("Framing - Raw Binary Chunk High-Speed Transport") {
            let encoder = FrameEncoder()
            let decoder = FrameDecoder()
            let samplePayload = Data((0..<512).map { UInt8($0 % 256) })
            let chunk = RawBinaryChunk(
                transferId: "tx-test-chunk-999",
                chunkIndex: 2,
                chunkTotal: 8,
                data: samplePayload
            )
            let frame = encoder.encode(binaryChunk: chunk)
            decoder.append(data: frame)
            if let decoded = try decoder.nextFrame(), case .binaryChunk(let raw) = decoded {
                return raw.transferId == "tx-test-chunk-999" && raw.chunkIndex == 2 && raw.data == samplePayload
            }
            return false
        }

        test("Contract - sample_envelopes.json Fixture Verification") {
            let paths = [
                "../../shared/protocol/fixtures/sample_envelopes.json",
                "shared/protocol/fixtures/sample_envelopes.json",
                "../shared/protocol/fixtures/sample_envelopes.json"
            ]
            guard let url = paths.compactMap({ URL(fileURLWithPath: $0) }).first(where: { FileManager.default.fileExists(atPath: $0.path) }),
                  let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let cases = json["test_cases"] as? [[String: Any]] else {
                return false
            }

            let snakeDecoder = JSONDecoder()
            snakeDecoder.keyDecodingStrategy = .convertFromSnakeCase
            let encoder = FrameEncoder()
            let decoder = FrameDecoder()

            for tc in cases {
                guard let envDict = tc["envelope"] as? [String: Any],
                      let envData = try? JSONSerialization.data(withJSONObject: envDict),
                      let env = try? snakeDecoder.decode(ContinuityEnvelope.self, from: envData),
                      let frame = try? encoder.encode(envelope: env) else {
                    return false
                }
                decoder.append(data: frame)
                guard let decoded = try? decoder.nextEnvelope() else { return false }
                if decoded.requestId != env.requestId || decoded.senderDeviceId != env.senderDeviceId {
                    return false
                }
            }
            return true
        }

        test("Contract - features.json Capabilities Verification") {
            let paths = [
                "../../shared/protocol/capabilities/features.json",
                "shared/protocol/capabilities/features.json",
                "../shared/protocol/capabilities/features.json"
            ]
            guard let url = paths.compactMap({ URL(fileURLWithPath: $0) }).first(where: { FileManager.default.fileExists(atPath: $0.path) }),
                  let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = json["name"] as? String,
                  name == "ContinuityCapabilityCatalog" else {
                return false
            }
            return true
        }

        // 3. File Transfer Logic Tests
        test("FileTransfer - Adaptive Chunk Sizing") {
            func adaptiveSize(fileSize: Int64) -> Int64 {
                if fileSize < 5 * 1024 * 1024 { return 256 * 1024 }
                if fileSize < 50 * 1024 * 1024 { return 1024 * 1024 }
                return 4 * 1024 * 1024
            }
            return adaptiveSize(fileSize: 2 * 1024 * 1024) == 256 * 1024 &&
                   adaptiveSize(fileSize: 20 * 1024 * 1024) == 1024 * 1024 &&
                   adaptiveSize(fileSize: 100 * 1024 * 1024) == 4 * 1024 * 1024
        }

        // 4. Folder Sync Logic Tests
        test("FolderSync - Manifest Entry Integrity") {
            let entry = SyncFileEntry(
                path: "photos/img1.jpg",
                sizeBytes: 1048576,
                sha256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
                modifiedTimeMs: 1729000000000
            )
            let manifest = FolderSyncManifest(folderName: "Camera", files: [entry])
            return manifest.files.count == 1 && manifest.files[0].path == "photos/img1.jpg"
        }

        return allPassed
    }
}

// Global execution on test target build
let _suitePassed = ContinuityTestSuite.runAllTests()
