# Verification & Testing Plan
**Android + macOS Continuity Ecosystem**
*Version 1.0 — Test Strategy & Test Suites*

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

### 2.1 Protocol & Unit Tests (`tests/protocol/`)
- Envelope binary serialization & deserialization.
- Frame boundary parsing under TCP fragmentation / packet slicing.
- HKDF key derivation correctness against RFC test vectors.
- AES-256-GCM encryption/decryption with synthetic corruptions.
- File chunking and SHA-256 calculation tests.

### 2.2 Integration Tests (`tests/integration/`)
- **Simulated Node Handshake**: Launch automated headless node to verify discovery, QR pairing, key agreement, and capability negotiation.
- **Bidirectional File Transfer**: Transfer files from 1 KB to 2 GB with synthetic packet drops, verifying hash matching and resume offsets.
- **Session Lifecycle**: Simulate network drops during active screen mirroring, verifying clean socket recovery without orphan processes.

### 2.3 Performance & Stress Testing (`tests/performance/`)
- Small file transfer latency (< 2.0s from accept to finish).
- Memory profile under 50 MB on Android and macOS during idle state.
- Screen mirroring latency target < 40ms over 5GHz Wi-Fi.
- CPU utilization < 8% on phone during camera streaming using hardware H.264 encoder.

---

## 3. Security & Boundary Audits
- Fuzzing protocol parser with arbitrary random byte buffers.
- Replay attack simulations with captured pairing payloads.
- Validating that revoked device keys immediately terminate active sessions.
