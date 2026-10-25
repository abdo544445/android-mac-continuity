import Foundation
import Network
import ContinuityProtocol

@main
struct ContinuityCLI {
    static func main() async {
        let args = CommandLine.arguments.dropFirst()
        let command = args.first ?? "help"

        switch command {
        case "test":
            print("🧪 Running Continuity Protocol Automated Test Suite...")
            runTestSuite()

        case "simulate-android":
            let port = UInt16(args.dropFirst().first ?? "52400") ?? 52400
            print("🚀 Starting Simulated Android Node (Pixel 9 Pro)...")
            await runSimulatedAndroid(port: port)

        case "listen":
            let port = UInt16(args.dropFirst().first ?? "52400") ?? 52400
            print("🎧 Starting Continuity Headless Host on port \(port)...")
            await runHostListener(port: port)

        case "status":
            print("=== Continuity Ecosystem CLI ===")
            print("Local Host: \(Host.current().localizedName ?? "Mac")")
            print("Protocol Version: 1")
            print("Default Listen Port: 52400")

        default:
            print("""
            Continuity CLI - Developer & Test Harness
            Usage:
              ContinuityCLI test                     - Run unit & protocol automated test suite
              ContinuityCLI listen [port]            - Start headless host listener
              ContinuityCLI simulate-android [port]   - Run a simulated Android node to test handshake & file transfers
              ContinuityCLI status                   - Display local protocol status
            """)
        }
    }

    static func runTestSuite() {
        var passed = 0
        var failed = 0

        func assert(_ condition: Bool, _ name: String) {
            if condition {
                print("  ✅ [PASS] \(name)")
                passed += 1
            } else {
                print("  ❌ [FAIL] \(name)")
                failed += 1
            }
        }

        // Test 1: Framing Round Trip
        do {
            let encoder = FrameEncoder()
            let decoder = FrameDecoder()
            var env = ContinuityEnvelope(senderDeviceId: "cli-test-device")
            env.heartbeat = Heartbeat(sequenceNumber: 100)
            let frame = try encoder.encode(envelope: env)
            decoder.append(data: frame)
            let decoded = try decoder.nextEnvelope()
            assert(decoded?.senderDeviceId == "cli-test-device" && decoded?.heartbeat?.sequenceNumber == 100, "Binary framing round-trip encode/decode")
        } catch {
            assert(false, "Binary framing threw error: \(error)")
        }

        // Test 2: Crypto Key Agreement & Derivation
        do {
            let crypto = CryptoManager.shared
            let aliceKeyPair = crypto.generateKeyPair()
            let bobKeyPair = crypto.generateKeyPair()
            let pin = "948123"

            let aliceKey = try crypto.deriveSessionKey(
                localPrivateKey: aliceKeyPair.privateKey,
                remotePublicKeyBase64: bobKeyPair.publicKeyBase64,
                pin: pin
            )
            let bobKey = try crypto.deriveSessionKey(
                localPrivateKey: bobKeyPair.privateKey,
                remotePublicKeyBase64: aliceKeyPair.publicKeyBase64,
                pin: pin
            )

            let challenge = "device-auth-check"
            let tag = crypto.computeAuthTag(sessionKey: aliceKey, challenge: challenge)
            let valid = crypto.verifyAuthTag(sessionKey: bobKey, challenge: challenge, expectedTagBase64: tag)
            assert(valid, "ECDH P-256 + HKDF mutual key agreement & HMAC-SHA256 auth tag")
        } catch {
            assert(false, "Crypto derivation failed: \(error)")
        }

        // Test 3: SHA-256 Verification
        let crypto = CryptoManager.shared
        let testData = Data("The quick brown fox jumps over the lazy dog".utf8)
        let expected = "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592"
        let computed = crypto.sha256Hex(data: testData)
        assert(computed == expected, "SHA-256 integrity checksum verification")

        // Test 4: Complex Envelope Serialization
        do {
            let offer = TransferOffer(
                transferId: "tx-test-456",
                fileName: "document.pdf",
                fileSizeBytes: 2048,
                sha256Checksum: "abc456",
                totalChunks: 1
            )
            var env = ContinuityEnvelope(senderDeviceId: "mac-01")
            env.transferOffer = offer
            let data = try JSONEncoder().encode(env)
            let decoded = try JSONDecoder().decode(ContinuityEnvelope.self, from: data)
            assert(decoded.transferOffer?.fileName == "document.pdf", "TransferOffer payload serialization")
        } catch {
            assert(false, "Serialization failed: \(error)")
        }

        // Test 5: Raw Binary Chunk Framing & High-Speed Wire Transfer
        do {
            let rawPayload = Data((0..<1024).map { UInt8($0 % 256) })
            let testUUID = "12345678-1234-1234-1234-123456789abc"
            let rawChunk = RawBinaryChunk(
                transferId: testUUID,
                chunkIndex: 3,
                chunkTotal: 10,
                data: rawPayload
            )
            let encoder = FrameEncoder()
            let encodedBytes = encoder.encode(binaryChunk: rawChunk)

            let decoder = FrameDecoder()
            decoder.append(data: encodedBytes)
            let frame = try decoder.nextFrame()

            var verified = false
            if case .binaryChunk(let decodedChunk) = frame {
                if decodedChunk.transferId == testUUID &&
                   decodedChunk.chunkIndex == 3 &&
                   decodedChunk.chunkTotal == 10 &&
                   decodedChunk.data == rawPayload {
                    verified = true
                }
            }
            assert(verified, "Raw binary chunk encoding/decoding line-rate roundtrip")
        } catch {
            assert(false, "Binary chunk test failed: \(error)")
        }

        print("\n📊 Test Results: \(passed) Passed, \(failed) Failed")
        if failed > 0 {
            exit(1)
        }
    }

    static func runSimulatedAndroid(port: UInt16) async {
        let host = NWEndpoint.Host("127.0.0.1")
        let nwPort = NWEndpoint.Port(rawValue: port)!
        let connection = NWConnection(host: host, port: nwPort, using: .tcp)

        let session = ContinuityNetworkSession(connection: connection, id: "simulated-pixel-9")
        let simHandler = SimulatedAndroidHandler(session: session)
        session.setRetainedDelegate(simHandler)

        session.start()

        // Keep running until simulation completes
        for _ in 0..<12 {
            if simHandler.isComplete { break }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        print("🏁 Simulation finished. Result: \(simHandler.isComplete ? "SUCCESS" : "INCOMPLETE")")
        session.stop()
    }

    static func runHostListener(port: UInt16) async {
        do {
            let listener = ContinuityNetworkListener(port: port)
            let hostKeyPair = CryptoManager.shared.generateKeyPair()

            listener.onNewSession = { session in
                print("📱 [Host] Incoming connection accepted from peer!")
                let hostHandler = HeadlessHostSessionHandler(session: session, keyPair: hostKeyPair)
                session.setRetainedDelegate(hostHandler)
            }

            try listener.start()
            print("📡 [Host] Waiting for connections on port \(port)... (Press Ctrl+C to stop)")
            while true {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        } catch {
            print("❌ Failed to start listener: \(error)")
        }
    }
}

final class SimulatedAndroidHandler: NetworkSessionDelegate, @unchecked Sendable {
    let session: ContinuityNetworkSession
    var isComplete = false
    let crypto = CryptoManager.shared
    lazy var keyPair = crypto.generateKeyPair()

    init(session: ContinuityNetworkSession) {
        self.session = session
    }

    func sessionDidConnect(_ session: ContinuityNetworkSession) {
        print("📱 [Android Node] Connected to macOS Companion TCP Socket!")
        // Step 1: Send PairRequest
        let pairReq = PairRequest(
            deviceId: "pixel-9-pro-sim",
            deviceName: "Google Pixel 9 Pro",
            platform: .android,
            edition: .publicEdition,
            ephemeralPublicKeyBase64: keyPair.publicKeyBase64,
            pairingPin: "123456"
        )
        var env = ContinuityEnvelope(senderDeviceId: "pixel-9-pro-sim")
        env.pairRequest = pairReq
        print("📱 [Android Node] Sending PairRequest (Pin: 123456)...")
        session.send(envelope: env)
    }

    func sessionDidDisconnect(_ session: ContinuityNetworkSession, error: Error?) {
        print("📱 [Android Node] Disconnected. Error: \(String(describing: error))")
    }

    func session(_ session: ContinuityNetworkSession, didReceiveEnvelope envelope: ContinuityEnvelope) {
        if let confirm = envelope.pairConfirm {
            print("✅ [Android Node] Received PairConfirm from \(confirm.deviceName)! SessionToken: \(confirm.assignedSessionToken)")

            // Step 2: Send DeviceHello and Capabilities
            var helloEnv = ContinuityEnvelope(senderDeviceId: "pixel-9-pro-sim", sessionToken: confirm.assignedSessionToken)
            helloEnv.deviceHello = DeviceHello(protocolVersion: 1, appVersion: "1.0.0", osVersion: "Android 15", deviceModel: "Pixel 9 Pro")
            helloEnv.capabilities = CapabilityList(supportsFileTransfer: true, supportsClipboard: true, supportsNotifications: true)
            session.send(envelope: helloEnv)

            // Step 3: Send DeviceStatus (Battery 85%, Charging)
            var statusEnv = ContinuityEnvelope(senderDeviceId: "pixel-9-pro-sim", sessionToken: confirm.assignedSessionToken)
            statusEnv.deviceStatus = DeviceStatus(
                batteryPercentage: 85,
                isCharging: true,
                isWifiConnected: true,
                wifiSsid: "Home-5GHz",
                freeStorageBytes: 128_000_000_000,
                totalStorageBytes: 256_000_000_000
            )
            print("📱 [Android Node] Transmitting Battery (85%) & Wi-Fi Telemetry...")
            session.send(envelope: statusEnv)

            // Step 4: Send Notification Event
            var notifEnv = ContinuityEnvelope(senderDeviceId: "pixel-9-pro-sim", sessionToken: confirm.assignedSessionToken)
            notifEnv.notificationEvent = NotificationEvent(
                notificationId: "notif-001",
                packageName: "org.telegram.messenger",
                appDisplayName: "Telegram",
                title: "Sarah Connor",
                text: "Hey! Can you send me the blueprint document?",
                hasReplyAction: true
            )
            print("📱 [Android Node] Mirroring Notification: Telegram from Sarah Connor...")
            session.send(envelope: notifEnv)

            // Step 5: Send Sample File Transfer
            let sampleContent = Data("Continuity Ecosystem Verified Transfer Payload".utf8)
            let checksum = crypto.sha256Hex(data: sampleContent)
            let txId = "tx-sample-01"

            var offerEnv = ContinuityEnvelope(senderDeviceId: "pixel-9-pro-sim", sessionToken: confirm.assignedSessionToken)
            offerEnv.transferOffer = TransferOffer(
                transferId: txId,
                fileName: "sample_note.txt",
                fileSizeBytes: Int64(sampleContent.count),
                sha256Checksum: checksum,
                totalChunks: 1,
                chunkSizeBytes: 524288
            )
            print("📱 [Android Node] Offering File: sample_note.txt (\(sampleContent.count) bytes)...")
            session.send(envelope: offerEnv)

            var chunkEnv = ContinuityEnvelope(senderDeviceId: "pixel-9-pro-sim", sessionToken: confirm.assignedSessionToken)
            chunkEnv.transferChunk = TransferChunk(
                transferId: txId,
                chunkIndex: 0,
                dataBase64: sampleContent.base64EncodedString(),
                chunkSha256: checksum
            )
            session.send(envelope: chunkEnv)

            var compEnv = ContinuityEnvelope(senderDeviceId: "pixel-9-pro-sim", sessionToken: confirm.assignedSessionToken)
            compEnv.transferComplete = TransferComplete(
                transferId: txId,
                verified: true,
                finalPathBasename: "sample_note.txt",
                bytesWritten: Int64(sampleContent.count)
            )
            session.send(envelope: compEnv)
            print("📱 [Android Node] Sent File Chunk & Completion signal!")

            self.isComplete = true
        }
    }
}

final class HeadlessHostSessionHandler: NetworkSessionDelegate, @unchecked Sendable {
    let session: ContinuityNetworkSession
    let keyPair: KeyPair
    let crypto = CryptoManager.shared
    var sessionToken = "tok_headless_session"

    init(session: ContinuityNetworkSession, keyPair: KeyPair) {
        self.session = session
        self.keyPair = keyPair
    }

    func sessionDidConnect(_ session: ContinuityNetworkSession) {
        print("💻 [Host] Session connected: \(session.id)")
    }

    func sessionDidDisconnect(_ session: ContinuityNetworkSession, error: Error?) {
        print("💻 [Host] Session disconnected: \(session.id)")
    }

    func session(_ session: ContinuityNetworkSession, didReceiveEnvelope envelope: ContinuityEnvelope) {
        if let pairReq = envelope.pairRequest {
            print("💻 [Host] Received PairRequest from \(pairReq.deviceName) (PIN: \(pairReq.pairingPin))")
            var authTag = ""
            if let key = try? crypto.deriveSessionKey(
                localPrivateKey: keyPair.privateKey,
                remotePublicKeyBase64: pairReq.ephemeralPublicKeyBase64,
                pin: pairReq.pairingPin
            ) {
                authTag = crypto.computeAuthTag(sessionKey: key, challenge: pairReq.deviceId)
            }

            let confirm = PairConfirm(
                deviceId: "mac-host-cli",
                deviceName: Host.current().localizedName ?? "MacBook Pro",
                platform: .macOS,
                ephemeralPublicKeyBase64: keyPair.publicKeyBase64,
                approved: true,
                assignedSessionToken: sessionToken,
                authTagBase64: authTag
            )
            var reply = ContinuityEnvelope(senderDeviceId: "mac-host-cli", sessionToken: sessionToken)
            reply.pairConfirm = confirm
            print("💻 [Host] Sending PairConfirm...")
            session.send(envelope: reply)
        } else if let hello = envelope.deviceHello {
            print("💻 [Host] Peer Hello: \(hello.deviceModel) running \(hello.osVersion) (App v\(hello.appVersion))")
        } else if let status = envelope.deviceStatus {
            print("💻 [Host] Telemetry: Battery \(status.batteryPercentage)% (Charging: \(status.isCharging)), SSID: '\(status.wifiSsid)'")
        } else if let notif = envelope.notificationEvent {
            print("💻 [Host] Notification: [\(notif.appDisplayName)] \(notif.title): \(notif.text)")
        } else if let offer = envelope.transferOffer {
            print("💻 [Host] TransferOffer received: '\(offer.fileName)' (\(offer.fileSizeBytes) bytes, SHA256: \(offer.sha256Checksum.prefix(16))...)")
        } else if let chunk = envelope.transferChunk {
            print("💻 [Host] TransferChunk received: chunk \(chunk.chunkIndex)")
        } else if let comp = envelope.transferComplete {
            print("💻 [Host] TransferComplete verified: '\(comp.finalPathBasename)' (\(comp.bytesWritten) bytes written)")
        }
    }
}
