# Verification & Testing Plan
**Android + macOS Continuity Ecosystem**
*Version 1.0.4 — Test Strategy & Test Suites*

---

## 1. Multi-Platform Device Matrix

| Manufacturer | Hardware Model | OS Version | Test Coverage |
| :--- | :--- | :--- | :--- |
| **Google** | Pixel 8 / Pixel 9 Pro | Android 14 / 15 | MediaProjection, SAF, WorkManager, Notification Listener |
| **Samsung** | Galaxy S23 / S24 Ultra | One UI 6.1 (Android 14) | Aggressive OEM battery optimization, Knox restrictions |
| **Xiaomi** | Xiaomi 13 / 14 | HyperOS / MIUI | Auto-start permissions, floating notifications |
| **Motorola** | Edge 50 Pro | Android 14 | Stock Android baseline behavior |
| **Apple** | MacBook Pro (M1 Pro / M3 Max) | macOS 14 (Sonoma) / 15 (Sequoia) | Apple Silicon native execution, CMIO virtual camera |
| **Apple** | Mac mini (Intel Core i7) | macOS 14 (Sonoma) | x86_64 architecture fallback & Rosetta 2 testing |

---

## 2. Testing Levels & Automated Suites

### 2.1 Android Unit Test Matrix (`apps/android/app/src/test/`)
Comprehensive JUnit test suite verified via `./gradlew testDebugUnitTest`:

1. **`connection/ProtocolFramingTest.kt`**: Validates 12-byte `CNT1` binary framing, fragmented stream reassembly, raw binary chunk slicing, and contract test verification of `shared/protocol/fixtures/sample_envelopes.json` & `shared/protocol/capabilities/features.json`.
2. **`security/CryptoManagerTest.kt`**: Validates ECDH P-256 keypair generation (raw 64B uncompressed coordinates), RFC 5869 HKDF-SHA256 test vector, mutual key derivation, HMAC-SHA256 auth tag, AES-256-GCM authenticated encryption/decryption, and 6-digit PIN parsing.
3. **`pairing/PairingManagerTest.kt`**: Validates QR URI parsing (`continuity://pair?...`), 6-digit visual PIN extraction, IP/port resolution, and rejection of invalid schemes.
4. **`filetransfer/FileTransferManagerTest.kt`**: Validates chunk boundary sizing (512KB), adaptive chunk calculation, and directory traversal sanitization (`../../etc/hosts` -> `hosts`).
5. **`notifications/NotificationFilterTest.kt`**: Validates 2FA and bank OTP regex redaction without false positives on personal or work messages.
6. **`clipboard/ClipboardSyncManagerTest.kt`**: Validates clipboard sync payload creation, ignore-empty guard, and circular loop prevention.
7. **`sync/FolderSyncManagerTest.kt`**: Validates local file metadata scanning, SHA-256 fingerprinting, and sync state tracking.
8. **`handoff/HandoffManagerTest.kt`**: Validates active activity state capture, URL handoff payload packaging, and receipt dispatch.
9. **`telephony/CallRelayServiceTest.kt`**: Validates incoming call detection, state transitions (Ringing, Offhook, Idle), and remote answer/decline action triggers.
10. **`storage/StorageExplorerServiceTest.kt`**: Validates remote storage directory listing, permission checks, and tree traversal serialization.
11. **`ExampleUnitTest.kt`**: Baseline environment and assertion sanity check.

### 2.2 macOS Automated Test Suite (`apps/macos/`)
Verified via `swift test` and `swift run ContinuityCLI test`:
- **`ContinuityTestSuite`**:
  - Test 1: Length-prefixed binary framing round-trip encode/decode (`CNT1`).
  - Test 2: Ephemeral ECDH P-256 + HKDF-SHA256 mutual key agreement and HMAC-SHA256 auth tag matching.
  - Test 3: SHA-256 chunk integrity verification and Merkle root calculation.
  - Test 4: `TransferOffer` serialization and deserialization with snake_case and default values.
  - Test 5: Raw binary chunk line-rate round-trip through `FrameEncoder` and `FrameDecoder`.
  - Test 6: Fixture contract test — parses and round-trips all envelopes in `shared/protocol/fixtures/sample_envelopes.json`.
  - Test 7: Capability contract test — verifies `shared/protocol/capabilities/features.json` schema.

### 2.3 Integration & Acceptance Testing (`tests/integration/` & `tests/android/`)
- **`tests/android/run_android_tests.py`**: Fast local test runner verifying Android protocol framing, crypto, pairing, file transfer, and notification redaction (34/34 passing).
- **`tests/integration/run_e2e_test.py`**: End-to-end integration test orchestrating live local TCP sockets between simulated Host Mac and Android Client across 6 acceptance criteria:
  - Secure pairing handshake with PIN validation.
  - Device telemetry HUD reporting (battery, charging, SSID).
  - Bidirectional chunked file transfer with SHA-256 validation.
  - Real-time clipboard synchronization.
  - Notification forwarding and remote inline reply.
  - Sockets disconnect and token-based auto-reconnect lifecycle.

---

## 3. Security & Boundary Audits
- Fuzzing protocol parser with arbitrary random byte buffers.
- Replay attack simulations with captured pairing payloads.
- Validating that revoked device keys immediately terminate active sessions.
- Gatekeeper validation ensuring `.zip` and `.dmg` extract cleanly without malware warnings when guided by `How to Open.html`.
