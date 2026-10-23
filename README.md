# Android + macOS Continuity Ecosystem

[![CI Status](https://github.com/continuity-ecosystem/continuity/workflows/CI/badge.svg)](.github/workflows/ci.yml)
[![Protocol Version](https://img.shields.io/badge/Protocol-v1.0-blue.svg)](shared/protocol/schemas/continuity_protocol.proto)
[![macOS Compatibility](https://img.shields.io/badge/macOS-14.0%2B-black.svg?logo=apple)](apps/macos)
[![Android Compatibility](https://img.shields.io/badge/Android-12%2B%20(API%2031%2B)-green.svg?logo=android)](apps/android)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

A complete, high-performance, cross-platform ecosystem connecting Android devices and macOS into a unified workspace. Approximating the seamlessness of Apple's Continuity while leveraging Android-specific capabilities, the platform provides **bidirectional file transfers, clipboard synchronization, notification forwarding with inline replies, low-latency screen mirroring, phone-as-webcam streaming, and automated non-destructive photo backup.**

---

## 🏗️ System Architecture

```
┌────────────────────────────────────────┐       ┌────────────────────────────────────────┐
│            macOS Companion             │       │          Android Mobile App            │
│                                        │       │                                        │
│  ┌──────────────────────────────────┐  │       │  ┌──────────────────────────────────┐  │
│  │   SwiftUI Desktop & MenuBar UI   │  │       │  │    Jetpack Compose UI (M3)       │  │
│  └──────────────────┬───────────────┘  │       │  └──────────────────┬───────────────┘  │
│                     │                  │       │                     │                  │
│  ┌──────────────────▼───────────────┐  │       │  ┌──────────────────▼───────────────┐  │
│  │     Application Managers         │  │       │  │     Application Services         │  │
│  │  • FileTransferEngine            │  │       │  │  • FileTransferManager (SAF)     │  │
│  │  • NotificationBridge            │  │       │  │  • ContinuityNotificationListener│  │
│  │  • ClipboardBridge               │  │       │  │  • ClipboardSyncManager          │  │
│  │  • ScreenViewer / CameraReceiver │  │       │  │  • MediaProjection / CameraX     │  │
│  │  • AdvancedHost (ADB/scrcpy)     │  │       │  │  • WorkManager PhotoBackupWorker │  │
│  └──────────────────┬───────────────┘  │       │  └──────────────────┬───────────────┘  │
│                     │                  │       │                     │                  │
│  ┌──────────────────▼───────────────┐  │       │  ┌──────────────────▼───────────────┐  │
│  │    ContinuityProtocol Engine     │  │       │  │    ContinuityCore Engine         │  │
│  │  • Length-Prefixed Binary Framing│  │       │  │  • Binary Framing Stream Decoder │  │
│  │  • Protobuf Envelope Serializer  │  │       │  │  • Protobuf Envelope Serializer  │  │
│  │  • CryptoKit (AES-256-GCM / ECDH)│  │       │  │  • Keystore / AES-GCM / ECDH     │  │
│  └──────────────────┬───────────────┘  │       │  └──────────────────┬───────────────┘  │
│                     │                  │       │                     │                  │
│  ┌──────────────────▼───────────────┐  │       │  ┌──────────────────▼───────────────┐  │
│  │   Network.framework (NWListener/ │  │       │  │   Java NIO / SecureSocket / NSD  │  │
│  │   NWConnection) & Bonjour        │  │       │  │   (mDNS discovery & TLS socket)  │  │
│  └──────────────────┬───────────────┘  │       │  └──────────────────┬───────────────┘  │
└─────────────────────┼──────────────────┘       └─────────────────────┼──────────────────┘
                      │                                                │
                      └═══════════ Encrypted Local TCP Socket ═════════┘
                                   Bonjour: _continuity._tcp
                                   Port: 52400 (Dynamic)
```

---

## 🌟 Key Features & Editions

| Feature | Public Edition | Advanced Personal Edition |
| :--- | :--- | :--- |
| **Target Distribution** | Google Play Store + Developer ID Signed Mac App | Direct APK / GitHub + Mac Helper Daemon |
| **Developer Options** | **Not Required** (No ADB, No Root) | Optional authorized USB or Wireless ADB |
| **Device Pairing** | Short-lived QR Code + 6-digit visual PIN | Automatic loopback / ADB authorized pairing |
| **File Transfer** | Bidirectional chunked transfer with SHA-256 validation | Fast transfer + ADB push acceleration |
| **Clipboard** | Explicit foreground / Quick Settings share | Seamless background synchronization |
| **Notifications** | Notification listener with inline `RemoteInput` replies | Same + historical SQLite audit log |
| **Screen Mirroring** | MediaProjection (One-time session consent prompt) | Bundled `scrcpy` (< 35ms latency, up to 60fps) |
| **Webcam Mode** | CameraX 1080p stream to CoreMediaIO virtual camera | Same + hardware bitrate tuning |
| **Photo Backup** | WorkManager non-destructive incremental media sync | Scheduled folder synchronization |

---

## 📂 Repository Layout

```
├── apps/
│   ├── android/                  # Android Jetpack Compose application
│   │   ├── app/src/main/java/    # Clean architecture services & UI
│   │   ├── build.gradle.kts      # Gradle build configuration
│   │   └── AndroidManifest.xml   # Permission & service declarations
│   └── macos/                    # Native macOS application
│       ├── Package.swift         # Multi-target Swift package
│       ├── Sources/
│       │   ├── ContinuityProtocol/ # Shared wire protocol, crypto & transport
│       │   ├── ContinuityCompanion/# SwiftUI companion & MenuBar app
│       │   └── ContinuityCLI/      # Test harness and simulator
├── shared/
│   ├── protocol/
│   │   ├── schemas/              # Protocol Buffers (.proto) definitions
│   │   ├── capabilities/         # Machine-readable feature flags
│   │   └── fixtures/             # Compliance test vectors
│   └── crypto-spec/              # Cryptographic spec (ECDH, HKDF, AES-GCM)
├── services/
│   └── optional-relay/           # E2E encrypted remote WebSocket relay
├── tests/
│   ├── protocol/                 # Protocol unit tests
│   └── integration/              # Python end-to-end integration test suite
├── docs/
│   ├── product-requirements.md   # Comprehensive PRD
│   ├── system-architecture.md    # System architecture specification
│   ├── permissions-matrix.md     # Platform permission & policy mapping
│   ├── security-threat-model.md  # STRIDE threat model & mitigations
│   ├── api-protocol.md           # Wire protocol documentation
│   ├── testing-plan.md           # Multi-device hardware test plan
│   └── release-checklist.md      # Google Play & Apple notarization checklist
├── .github/workflows/ci.yml      # GitHub Actions CI workflow
├── Makefile                      # Convenient development commands
└── README.md
```

---

## ⚡ Quick Start

### 1. Build and Test macOS Targets
```bash
# Build SwiftUI Companion and CLI test harness
make build-macos

# Run Swift unit and protocol verification suite
make test-macos
```

### 2. Run End-to-End Integration Suite
```bash
# Verifies pairing, telemetry, chunked file transfer, clipboard, and notifications
make test-e2e
```

### 3. Run Simulated Android Peer
```bash
# In terminal 1 (starts companion listener or runs CLI simulation):
cd apps/macos && swift run ContinuityCLI simulate-android
```

### 4. Launch macOS Desktop App
```bash
make run-companion
```

---

## 🔒 Security & Privacy Architecture

- **Mutual Cryptographic Identity**: Every device generates a dedicated EC keypair. Pairing uses ephemeral ECDH (P-256) with out-of-band visual SAS PIN confirmation.
- **AEAD Encryption**: All post-handshake traffic is encrypted with AES-256-GCM.
- **Zero-Knowledge Local Operation**: No accounts, no cloud relays required. All traffic stays strictly on the local Wi-Fi subnet.
- **Sandboxed File Access**: Uses Android Storage Access Framework and macOS Downloads sandboxing; never accesses unrelated files.
- **Privacy Protections**: Sensitive 2FA verification codes (OTPs) and password manager clipboards are automatically filtered and redacted.
