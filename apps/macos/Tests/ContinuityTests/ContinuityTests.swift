import XCTest
@testable import ContinuityProtocol

final class ContinuityTests: XCTestCase {

    func testFramingRoundTrip() throws {
        let encoder = FrameEncoder()
        let decoder = FrameDecoder()

        var env = ContinuityEnvelope(senderDeviceId: "test-sender")
        env.heartbeat = Heartbeat(sequenceNumber: 42)

        let frameData = try encoder.encode(envelope: env)
        XCTAssertGreaterThan(frameData.count, 12)

        // Pass frame data to decoder
        decoder.append(data: frameData)
        let decodedEnv = try decoder.nextEnvelope()

        XCTAssertNotNil(decodedEnv)
        XCTAssertEqual(decodedEnv?.senderDeviceId, "test-sender")
        XCTAssertEqual(decodedEnv?.heartbeat?.sequenceNumber, 42)
    }

    func testCryptoKeyAgreementAndDerivation() throws {
        let crypto = CryptoManager.shared
        let aliceKeyPair = crypto.generateKeyPair()
        let bobKeyPair = crypto.generateKeyPair()
        let pin = "849201"

        // Alice derives key using Bob's public key
        let aliceKey = try crypto.deriveSessionKey(
            localPrivateKey: aliceKeyPair.privateKey,
            remotePublicKeyBase64: bobKeyPair.publicKeyBase64,
            pin: pin
        )

        // Bob derives key using Alice's public key
        let bobKey = try crypto.deriveSessionKey(
            localPrivateKey: bobKeyPair.privateKey,
            remotePublicKeyBase64: aliceKeyPair.publicKeyBase64,
            pin: pin
        )

        // Test auth tag verification
        let challenge = "device-verification-challenge"
        let tag = crypto.computeAuthTag(sessionKey: aliceKey, challenge: challenge)
        let isValid = crypto.verifyAuthTag(sessionKey: bobKey, challenge: challenge, expectedTagBase64: tag)

        XCTAssertTrue(isValid, "Bob should successfully verify Alice's auth tag with symmetric derived key")
    }

    func testSha256ChecksumVerification() {
        let crypto = CryptoManager.shared
        let testData = Data("The quick brown fox jumps over the lazy dog".utf8)
        let expectedHash = "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592"

        let computedHash = crypto.sha256Hex(data: testData)
        XCTAssertEqual(computedHash, expectedHash)
    }

    func testTransferOfferModel() throws {
        let offer = TransferOffer(
            transferId: "tx-123",
            fileName: "video.mp4",
            fileSizeBytes: 104857600,
            mimeType: "video/mp4",
            sha256Checksum: "abcd1234",
            totalChunks: 200,
            chunkSizeBytes: 524288
        )

        var env = ContinuityEnvelope(senderDeviceId: "mac-01")
        env.transferOffer = offer

        let encoder = JSONEncoder()
        let data = try encoder.encode(env)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ContinuityEnvelope.self, from: data)

        XCTAssertEqual(decoded.transferOffer?.fileName, "video.mp4")
        XCTAssertEqual(decoded.transferOffer?.fileSizeBytes, 104857600)
    }
}
