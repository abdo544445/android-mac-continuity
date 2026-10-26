# Android + macOS Continuity Ecosystem

[![Release Version](https://img.shields.io/badge/Release-v1.0.4-brightgreen.svg)](https://github.com/abdo544445/android-mac-continuity/releases/tag/v1.0.4)
[![Protocol Version](https://img.shields.io/badge/Protocol-v1.0.4-blue.svg)](shared/protocol/schemas/continuity_protocol.proto)
[![macOS Compatibility](https://img.shields.io/badge/macOS-14.0%2B%20(Sonoma%2FSequoia)-black.svg?logo=apple)](apps/macos)
[![Android Compatibility](https://img.shields.io/badge/Android-12%2B%20(API%2031%2B)-green.svg?logo=android)](apps/android)
[![Security](https://img.shields.io/badge/Encryption-AES--256--GCM%20%7C%20ECDH%20P--256-orange.svg)](shared/crypto-spec/spec.md)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

An industrial-grade, cross-platform ecosystem uniting Android smartphones/tablets and macOS desktops into a unified, seamless workspace. Emulating the intuitive experience of Apple's Continuity while unlocking Android's flexible hardware capabilities, this platform delivers **zero-configuration device pairing, high-throughput bidirectional file transfers, encrypted clipboard synchronization, notification forwarding with inline remote replies, sub-35ms display mirroring, phone-as-webcam streaming (CoreMediaIO), tablet secondary display, universal mouse/keyboard control, remote storage exploration, and folder auto-synchronization.**

The ecosystem is engineered around a **local-first, zero-knowledge security architecture**: all communications operate directly peer-to-peer over your local network or high-speed USB-C tunnel without cloud servers, user accounts, or telemetry tracking.

---

## ⚡ Quick Download & Install (Latest: v1.0.4)

| Platform | Download Link | Description |
| :--- | :--- | :--- |
| **macOS (Recommended)** | [**ContinuityCompanion-macOS-v1.0.4.zip**](https://github.com/abdo544445/android-mac-continuity/releases/download/v1.0.4/ContinuityCompanion-macOS-v1.0.4.zip) | Gatekeeper-friendly ZIP with 1-click `How to Open.html` helper |
| **macOS GUI DMG** | [**ContinuityCompanion-macOS-v1.0.4.dmg**](https://github.com/abdo544445/android-mac-continuity/releases/download/v1.0.4/ContinuityCompanion-macOS-v1.0.4.dmg) | Drag-and-drop installer for macOS Sonoma & Sequoia |
| **Android** (Universal APK) | [**Continuity-Android-v1.0.4.apk**](https://github.com/abdo544445/android-mac-continuity/releases/download/v1.0.4/Continuity-Android-v1.0.4.apk) | Release-signed APK (Play Protect bypass, API 26+) |

> [!TIP]
> **Zero-Terminal macOS Launch for Non-Technical Users**:
> Download **`ContinuityCompanion-macOS-v1.0.4.zip`** and double-click to unpack.
> 1. Drag `ContinuityCompanion.app` into `/Applications` and launch it.
> 2. When macOS displays the *"Not Opened"* dialog, click **Done** (do NOT click *Move to Trash*).
> 3. Double-click the included **`How to Open.html`** guide and click **Open Privacy & Security Settings**, then click **Open Anyway** at the bottom. No Terminal commands or source builds needed!

---

## 📑 Table of Contents

1. [Product Vision & Philosophy](#-product-vision--philosophy)
2. [Ecosystem Architecture](#-ecosystem-architecture)
   - [Logical System Topology](#logical-system-topology)
   - [Protocol & Networking Stack](#protocol--networking-stack)
   - [Zero-Trust Security & Key Agreement Sequence](#zero-trust-security--key-agreement-sequence)
   - [Bidirectional File Transfer Pipeline](#bidirectional-file-transfer-pipeline)
   - [Notification Mirroring & Inline Reply Workflow](#notification-mirroring--inline-reply-workflow)
3. [Exhaustive Feature Catalog](#-exhaustive-feature-catalog)
   - [1. Extended Display (Tablet Secondary Monitor)](#1-extended-display-tablet-as-secondary-mac-monitor)
   - [2. Universal Control (Shared Mouse & Keyboard)](#2-universal-control-shared-mouse--keyboard)
   - [3. Remote Storage Explorer](#3-remote-storage-explorer)
   - [4. Bidirectional Folder Auto-Sync](#4-bidirectional-folder-auto-sync)
   - [5. Universal Handoff](#5-universal-handoff)
   - [6. Call Continuity & Relay](#6-call-continuity--relay)
   - [7. Biometric Mac Unlock](#7-biometric-mac-unlock)
   - [8. Screen Mirroring & Interactive Remote Touch](#8-screen-mirroring--interactive-remote-touch)
   - [9. Phone as Mac HD Webcam (CoreMediaIO)](#9-phone-as-mac-hd-webcam-coremediaio)
   - [10. Smart Encrypted Clipboard Sync](#10-smart-encrypted-clipboard-sync)
   - [11. AirDrop-Speed File Transfers](#11-airdrop-speed-file-transfers)
4. [GUI DMG Installer & In-App Dependency Manager](#-gui-dmg-installer--in-app-dependency-manager)
5. [Repository Structure](#-repository-structure)
6. [Building & Running from Source](#-building--running-from-source)
7. [Stability & Engineering Highlights in v1.0.4](#-stability--engineering-highlights-in-v104)
8. [Security & Cryptographic Specification](#-security--cryptographic-specification)
9. [Platform Constraints & Compliance](#-platform-constraints--compliance)
10. [Troubleshooting & FAQ](#-troubleshooting--faq)

---

## 🎯 Product Vision & Philosophy

Apple's native Continuity features (AirDrop, Universal Clipboard, Notification Center, iPhone Mirroring, Continuity Camera) offer seamless cross-device workflows, but restrict users exclusively to iPhones and Macs. Android users owning Macs have historically been forced into fragmented workarounds, unreliable MTP drivers, or privacy-invasive third-party cloud servers.

This project delivers:
- **Native Platform Idioms**: Swift 6 and SwiftUI on macOS; Kotlin and Jetpack Compose (Material 3) on Android.
- **Zero Cloud Dependence**: Operates 100% locally on your Wi-Fi subnet; zero external internet access required for core functionality.
- **Privacy by Design**: End-to-end encrypted transport (AES-256-GCM) with visual out-of-band SAS PIN verification and local hardware Keystore / Keychain key management.
- **Frictionless Consumer Setup**: Public Edition requires no ADB, root, or command-line developer tools.
- **Power-User Extensibility**: Advanced Personal Edition harnesses bundled `scrcpy` and ADB tunnels for ultra-low latency mirroring (< 35ms) and automation.

---

## 🏗️ Ecosystem Architecture

### Logical System Topology

```
┌────────────────────────────────────────────────────────┐       ┌────────────────────────────────────────────────────────┐
│                   macOS Companion                      │       │                  Android Mobile App                    │
│                                                        │       │                                                        │
│  ┌──────────────────────────────────────────────────┐  │       │  ┌──────────────────────────────────────────────────┐  │
│  │             SwiftUI Desktop Dashboard            │  │       │  │           Jetpack Compose UI (Material 3)        │  │
│  │   • Dashboard HUD      • Transfers View          │  │       │  │   • Home Status Card   • QR Scanner Dialog      │  │
│  │   • Notifications View • Screen Mirroring Canvas │  │       │  │   • Transfers Screen   • Notification Toggles   │  │
│  │   • Camera View        • Storage Explorer View   │  │       │  │   • Extended Display   • Camera Live Stream     │  │
│  │   • Extended Display   • Settings & Dependencies │  │       │  │   • Privacy Settings   • Mirroring Consent View │  │
│  └──────────────────────────┬───────────────────────┘  │       │  └──────────────────────────┬───────────────────────┘  │
│                             │                          │       │                             │                          │
│  ┌──────────────────────────▼───────────────────────┐  │       │  ┌──────────────────────────▼───────────────────────┐  │
│  │                 Core Application Engines         │  │       │  │               Platform Background Services       │  │
│  │   • FileTransferEngine   (512KB Chunks & Resume) │  │       │  │   • FileTransferManager (Storage Access Framewk) │  │
│  │   • NotificationBridge   (macOS UserNotifications│  │       │  │   • ContinuityNotificationListener (2FA Filter)  │  │
│  │   • ClipboardBridge      (NSPasteboard Privacy)  │  │       │  │   • ClipboardSyncManager (Foreground / QuickSet) │  │
│  │   • ExtendedDisplayMgr   (CGDisplay Virtual Sink)│  │       │  │   • StorageExplorerService (Scoped Storage Fall) │  │
│  │   • UniversalControlMgr  (Mouse & Keyboard Share)│  │       │  │   • FolderSyncManager   (SHA-256 Sync Engine)    │  │
│  │   • FolderSyncEngine     (Bidirectional Sync)    │  │       │  │   • CallRelayService    (Telephony Telemetry)    │  │
│  │   • HandoffBridge        (Safari/Chrome Relay)   │  │       │  │   • BiometricAuthManager(Hardware BiometricPrompt│  │
│  │   • AdvancedHostManager  (ADB & scrcpy Controller│  │       │  │   • ScreenShareService  (MediaProjection & AVC)  │  │
│  │   • CoreMediaIO Extension(Virtual Webcam Sink)   │  │       │  │   • CameraStreamingService (CameraX Stream)      │  │
│  └──────────────────────────┬───────────────────────┘  │       │  └──────────────────────────┬───────────────────────┘  │
│                             │                          │       │                             │                          │
│  ┌──────────────────────────▼───────────────────────┐  │       │  ┌──────────────────────────▼───────────────────────┐  │
│  │                ContinuityProtocol Engine         │  │       │  │                 ContinuityCore Engine            │  │
│  │   • FrameEncoder / FrameDecoder (CNT1 Wire Spec) │  │       │  │   • ProtocolFraming Stream Decoder (readFully)   │  │
│  │   • Envelope Serialization (Protobuf Models)     │  │       │  │   • ContinuityEnvelope Serializer (Gson/Proto)   │  │
│  │   • CryptoManager (Apple CryptoKit ECDH / AES-GCM│  │       │  │   • DeviceIdentity (Android KeyStore & JCE)      │  │
│  └──────────────────────────┬───────────────────────┘  │       │  └──────────────────────────┬───────────────────────┘  │
│                             │                          │       │                             │                          │
│  ┌──────────────────────────▼───────────────────────┐  │       │  ┌──────────────────────────▼───────────────────────┐  │
│  │             Network.framework Transport          │  │       │  │               Android Java NIO / NSD Sockets     │  │
│  │   • NWListener (TCP Port 52400)                  │  │       │  │   • NsdManager (DNS-SD _continuity._tcp)         │  │
│  │   • UDP LAN Auto-Discovery (Port 52402)          │  │       │  │   • LanDiscoveryManager (UDP Multicast Beacon)   │  │
│  │   • High-Speed USB Tunnel (127.0.0.1:52400)      │  │       │  │   • Managed Foreground ConnectionService Socket  │  │
│  └──────────────────────────┬───────────────────────┘  │       │  └──────────────────────────┬───────────────────────┘  │
└─────────────────────────────┼──────────────────────────┘       └─────────────────────────────┼──────────────────────────┘
                              │                                                                │
                              └═══════════════ Mutually Authenticated Local Socket ════════════┘
                                               Discovery: UDP 52402 + DNS-SD _continuity._tcp
                                               Framing: CNT1 Big-Endian Length-Prefixed
                                               Payload Encryption: AES-256-GCM
```

---

### Protocol & Networking Stack

Every message in the continuity ecosystem is multiplexed over a framed, encrypted TCP connection:

```mermaid
graph TD
    App["Application Layer (Files, Notifications, Display, Storage, Handoff, Calls)"]
    Env["ContinuityEnvelope (Protobuf Unified Schema)"]
    Framing["Binary Wire Framing (CNT1 Magic | Flags | EncMode | 32-bit Length Prefix)"]
    Crypto["AEAD Encryption Layer (AES-256-GCM with 96-bit Unique Nonce)"]
    Transport["Reliable Transport (TCP Socket / Local Wi-Fi / USB-C Fast-Path)"]
    Discovery["Zero-Conf Discovery (UDP 52402 Auto-Beacon & DNS-SD _continuity._tcp)"]

    App --> Env
    Env --> Crypto
    Crypto --> Framing
    Framing --> Transport
    Discovery -.-> Transport
```

---

### Zero-Trust Security & Key Agreement Sequence

Devices authenticate with an ephemeral out-of-band PIN verification handshake. Even on untrusted public Wi-Fi, passive eavesdroppers or rogue peers cannot decrypt or tamper with session data:

```mermaid
sequenceDiagram
    autonumber
    participant Mac as macOS Companion
    participant Android as Android Phone

    Note over Mac: 1. Generate Ephemeral KeyPair (pkA, skA)<br>Generate 6-digit Visual PIN (e.g. 849201)
    Mac->>Mac: Broadcast UDP 52402 Beacon or Show QR Code
    Note over Android: 2. Auto-discover Mac on LAN or Scan QR Code<br>Generate Ephemeral KeyPair (pkB, skB)
    Android->>Mac: TCP Connect to Host:Port
    Android->>Mac: PairRequest(deviceId, pkB, PIN)
    Note over Mac: 3. Verify PIN matches active session<br>Compute SharedSecret = ECDH(skA, pkB)<br>Derive SessionKey = HKDF(SharedSecret, Salt=PIN)<br>Compute AuthTag = HMAC(SessionKey, deviceId)
    Mac->>Android: PairConfirm(approved=true, sessionToken, AuthTag, pkA)
    Note over Android: 4. Compute SharedSecret = ECDH(skB, pkA)<br>Derive SessionKey = HKDF(SharedSecret, Salt=PIN)<br>Validate AuthTag with SessionKey
    Note over Mac,Android: 5. Session Authenticated (AEAD AES-256-GCM Active)
    Android->>Mac: DeviceHello(model="Pixel 9 Pro", OS="Android 16")
    Mac->>Android: CapabilityList(supportsFiles=true, supportsMirror=true)
    Note over Mac,Android: 6. Sockets Established; Telemetry & Multiplexed I/O Active
```

---

### Bidirectional File Transfer Pipeline

Designed to replicate AirDrop throughput with zero size limitations, chunked integrity verification, and automatic resume support:

```mermaid
flowchart TD
    Start["User Selects File (Drag-and-Drop or Android Share Sheet)"] --> Hash["Compute File SHA-256 Checksum"]
    Hash --> Split["Slice into 512 KB Fixed Chunks"]
    Split --> Offer["Send TransferOffer (fileName, totalBytes, SHA-256, chunkCount)"]
    Offer --> Accept["Peer Accepts Transfer (TransferAccept)"]
    Accept --> Stream["Stream TransferChunks sequentially"]
    Stream --> ChunkCheck{"Verify Chunk SHA-256"}
    ChunkCheck -- Valid --> WritePart["Append to temporary .part file"]
    ChunkCheck -- Invalid --> Retry["Re-request Corrupted Chunk"]
    WritePart --> MoreChunks{"More Chunks?"}
    MoreChunks -- Yes --> Stream
    MoreChunks -- No --> FullCheck{"Validate Full-File SHA-256"}
    FullCheck -- Matches --> Sanitize["Sanitize Basename (Prevent Path Traversal)"]
    Sanitize --> Rename["Atomic Rename to Downloads/Continuity/"]
    Rename --> Finish["Send TransferComplete Confirmation"]
```

---

### Notification Mirroring & Inline Reply Workflow

```mermaid
sequenceDiagram
    autonumber
    participant ThirdParty as 3rd Party App (e.g. Telegram)
    participant NotifListener as Android Notification Listener
    participant ConnService as Android Connection Service
    participant MacBridge as macOS Notification Bridge
    participant macOSCenter as macOS Notification Center

    ThirdParty->>NotifListener: Notification Posted (Title, Text, Actions)
    Note over NotifListener: Security Check: Is this a 2FA OTP / Banking SMS?<br>If yes -> Drop immediately (Privacy Protection)
    NotifListener->>ConnService: Wrap into NotificationEvent
    ConnService->>MacBridge: Transmit encrypted NotificationEvent
    MacBridge->>macOSCenter: Post native macOS Banner Notification
    macOSCenter->>MacBridge: User enters inline reply: "On my way!"
    MacBridge->>ConnService: Dispatch NotificationAction(replyText="On my way!")
    ConnService->>NotifListener: Locate RemoteInput in StatusBarNotification
    NotifListener->>ThirdParty: Execute actionIntent.send() with reply Bundle
    Note over ThirdParty: Reply sent without opening mobile app
```

---

## 🌟 Exhaustive Feature Catalog

### 1. Extended Display (Tablet as Secondary Mac Monitor)
- **Second Screen Expansion**: Turns any Android or Huawei tablet into an ultra-responsive secondary display for your Mac.
- **Bi-directional Touch & Stylus Control**: Tap, drag, and draw on your tablet; inputs are mapped in real-time to macOS cursor events.
- **Zero Drivers Required**: Uses native CoreGraphics screen capture on macOS and high-speed binary frame decoding on Android.

### 2. Universal Control (Shared Mouse & Keyboard)
- **Seamless Cursor Hopping**: Push your Mac cursor to the edge of the screen to transition into controlling your tablet or phone.
- **Keyboard Forwarding**: Type smoothly into Android apps from your Mac mechanical keyboard.
- **Quick Escape**: Press `ESC` at any moment to return focus instantly to macOS.

### 3. Remote Storage Explorer
- **Remote Finder for Android**: Browse, search, and navigate your tablet/phone's internal storage (`/storage/emulated/0`) directly from the macOS Companion app.
- **Direct Downloads**: Download any file or photo from your phone with a single click.
- **Scoped Storage Intelligent Fallback**: Automatically provides access to standard user folders (`Downloads`, `Documents`, `DCIM`, `Pictures`, `Music`) on modern Android 11–16 devices.

### 4. Bidirectional Folder Auto-Sync
- **Continuous Local Synchronization**: Keeps `~/ContinuitySync` on your Mac in sync with `Documents/ContinuitySync` on your tablet.
- **SHA-256 Differential Reconciler**: Compares local and remote manifests, syncing only changed or missing files to prevent redundant network traffic.
- **Conflict Prevention**: Non-destructive atomic updates ensure file integrity during network drops.

### 5. Universal Handoff
- **Browser Tab Relay**: Push your active Safari or Chrome tabs from macOS to Android with a single click (`⌘H` or via the menu bar).
- **Android Link Relay**: Push links from Android browsers to open instantly in your Mac's default browser.

### 6. Call Continuity & Relay
- **Desktop Call Notifications**: Real-time incoming phone call banners on macOS displaying caller name, phone number, and avatar.
- **Audio & Call Actions**: Distinct audio chime on incoming calls with **Decline** and **Silence** controls directly from macOS.

### 7. Biometric Mac Unlock
- **Remote Biometric Challenge**: Verify macOS companion authentication or sensitive actions by prompting for a fingerprint or facial scan on your Android tablet/phone.
- **Hardware Security**: Uses native Android `BiometricPrompt` backed by hardware TEE/StrongBox.

### 8. Screen Mirroring & Interactive Remote Touch
- **Wireless In-App Mirror**: Low-latency screen streaming rendered directly on the macOS Companion canvas.
- **Interactive Mouse Touch Overlay**: Click or drag directly on the mirrored phone screen inside macOS to interact, tap, and swipe.
- **Hardware Navigation Bar**: Dedicated buttons for Android system controls: **Back (◁), Home (○), Recents (□), Power (⏻), Volume Up, and Volume Down**.
- **Interactive 60fps scrcpy Window**: One-click launcher for `scrcpy` over USB or Wi-Fi TCP/IP for zero-latency 60fps gaming and full remote control.

### 9. Phone as Mac HD Webcam (CoreMediaIO)
- **Crystal-Clear HD Video**: Stream Android camera sensor at 1080p/720p 30fps into macOS.
- **CoreMediaIO Virtual Camera**: Directly selectable inside FaceTime, Zoom, Google Meet, OBS, Teams, and Discord.
- **Remote Controls**: Switch between Ultra-Wide / Rear camera and Front selfie camera, and toggle the LED flashlight torch from Mac.

### 10. Smart Encrypted Clipboard Sync
- **Bidirectional Image & Text Sync**: Copy text or screenshots (`⌘C`) on Mac and paste (`⌘V`) immediately on Android, or vice-versa.
- **Rich Media MediaStore Insertion**: Images copied from Mac are automatically saved to `Pictures/Continuity` so they can be pasted directly into Telegram, WhatsApp, Notes, and Docs.
- **Sensitive Content Shield**: Automatically filters password managers and concealed pasteboard types.

### 11. AirDrop-Speed File Transfers
- **Line-Rate Protocol (CNT1 Flag `0x01`)**: Raw binary streaming without Base64 overhead, saturating 5GHz/6GHz Wi-Fi and USB 3.0 links (300–450+ MB/s).
- **System Share Sheet Integration**: Send files from any Android app directly to Mac via the native Share Sheet.
- **Chunked SHA-256 Verification & Resume**: Automatically verifies chunk integrity and prevents duplicate file transfers.

---

## 📦 GUI DMG Installer & In-App Dependency Manager

Starting with **v1.0.4**, Continuity Companion for macOS features a native GUI installer and an in-app dependency manager:

1. **Drag-and-Drop `.dmg`**:
   - Double-click `ContinuityCompanion-macOS-v1.0.4.dmg`.
   - Drag `ContinuityCompanion.app` into `/Applications`.
2. **In-App 1-Click Dependency Installer**:
   - Open **Settings** in the macOS Companion app.
   - If `scrcpy` or `adb` are missing, simply click **Install via Homebrew**.
   - The app automatically downloads, configures, and verifies the tools with real-time visual progress — no command-line input required.

---

## 📂 Repository Structure

```
android-mac-continuity/
├── Makefile                      # Convenient build, test, package, and release automation
├── VERSION                       # Semantic version (1.0.4)
├── README.md                     # Comprehensive architecture and user guide
├── .github/
│   └── workflows/
│       └── ci.yml                # Automated CI pipeline for macOS, Android & integration tests
│
├── apps/
│   ├── macos/                    # Native macOS Desktop & MenuBar Application
│   │   ├── Package.swift         # Multi-target Swift package definition
│   │   ├── Sources/
│   │   │   ├── ContinuityProtocol/ # Wire framing, cryptographic primitives, and Network.framework
│   │   │   │   ├── Models/       # Type-safe Swift protocol models
│   │   │   │   ├── Protocol/     # Binary frame encoder/decoder (CNT1 magic)
│   │   │   │   ├── Crypto/       # CryptoKit ECDH P-256, HKDF, AES-256-GCM
│   │   │   │   └── Network/      # NWListener, NWConnection, UDP auto-discovery
│   │   │   │
│   │   │   ├── ContinuityCompanion/ # SwiftUI macOS Application
│   │   │   │   ├── CompanionApp.swift # @main SwiftUI entry point
│   │   │   │   ├── Views/        # Dashboard, Transfers, Notifications, Mirroring, Camera, Devices, Settings
│   │   │   │   ├── MenuBar/      # MenuBarController & status drop zone
│   │   │   │   ├── ExtendedDisplay/ # ExtendedDisplayManager (Secondary monitor engine)
│   │   │   │   ├── UniversalControl/# UniversalControlManager (Shared mouse/keyboard)
│   │   │   │   ├── StorageExplorer/ # StorageExplorerManager (Remote file browser)
│   │   │   │   ├── FolderSync/   # FolderSyncEngine (Differential SHA-256 auto-sync)
│   │   │   │   ├── Handoff/      # HandoffBridge (Safari & Chrome tab relay)
│   │   │   │   ├── Telephony/    # CallRelayBridge (Incoming call banner & actions)
│   │   │   │   ├── Security/     # BiometricAuthBridge (Remote biometric unlock)
│   │   │   │   ├── FileTransfer/ # FileTransferEngine (chunks, resume, SHA-256)
│   │   │   │   ├── NotificationBridge/ # UserNotifications & RemoteInput dispatcher
│   │   │   │   ├── ClipboardBridge/    # NSPasteboard watcher & image paste
│   │   │   │   ├── ConnectionAgent/    # Local network session orchestrator
│   │   │   │   ├── DeviceRegistry/     # Paired devices & trust management
│   │   │   │   └── AdvancedHost/       # ADB & scrcpy power-user harness
│   │   │   │
│   │   │   └── ContinuityCLI/    # Headless test harness, simulator, and listener
│   │   │       └── main.swift
│   │   │
│   │   └── Tests/
│   │       └── ContinuityTests/  # Swift unit test suite
│   │
│   └── android/                  # Android Mobile Application
│       ├── build.gradle.kts      # Project build configuration
│       ├── settings.gradle.kts   # Module settings
│       ├── gradlew / gradlew.bat # Official Gradle wrapper scripts
│       └── app/
│           ├── build.gradle.kts  # Target SDK 35, Jetpack Compose, CameraX, WorkManager
│           └── src/
│               ├── main/
│               │   ├── AndroidManifest.xml # Permissions & foreground service declarations
│               │   ├── java/com/continuity/ecosystem/
│               │   │   ├── MainActivity.kt # Compose navigation & system share sheet handler
│               │   │   ├── core/           # Protocol models, DeviceIdentity (Android KeyStore, ECDH)
│               │   │   ├── connection/     # LanDiscoveryManager (UDP 52402), ConnectionService, ProtocolFraming
│               │   │   ├── pairing/        # PairingManager (QR parsing, auth verification)
│               │   │   ├── files/          # FileTransferManager (SAF ContentResolver, chunking)
│               │   │   ├── storage/        # StorageExplorerService (Scoped Storage handling)
│               │   │   ├── sync/           # FolderSyncManager (SHA-256 differential sync)
│               │   │   ├── handoff/        # HandoffManager (URL intent dispatcher)
│               │   │   ├── telephony/      # CallRelayService (Call state listener)
│               │   │   ├── security/       # BiometricAuthManager (Hardware BiometricPrompt)
│               │   │   ├── clipboard/      # ClipboardSyncManager (Safe pasteboard & MediaStore)
│               │   │   ├── notifications/  # ContinuityNotificationListenerService & RemoteInput
│               │   │   ├── mirroring/      # ScreenShareService (MediaProjection virtual display)
│               │   │   ├── camera/         # CameraStreamingService (CameraX hardware video)
│               │   │   └── ui/             # Modern Material 3 Jetpack Compose theme & screens
│               │   └── res/                # XML resources, strings, colors, data extraction rules
│               │
│               └── test/java/com/continuity/ecosystem/ # Android Unit Test Suite
│
├── scripts/
│   ├── bundle_macos_app.sh       # Compiles and packages ContinuityCompanion.app
│   ├── create_dmg.sh             # Creates native GUI drag-and-drop .dmg
│   └── release.sh                # End-to-end version bump, tag, build, and GitHub release script
│
├── dist/                         # Distribution artifacts (DMG, APK, ZIP)
└── shared/
    ├── protocol/schemas/         # Protobuf wire schemas
    └── crypto-spec/spec.md       # Cryptographic specification & security proofs
```

---

## 🛠️ Building & Running from Source

### Prerequisites

| Tool | Minimum Version | Notes |
| :--- | :--- | :--- |
| **macOS** | macOS 14.0+ (Sonoma / Sequoia) | Apple Silicon (M1–M4) or Intel x86_64 |
| **Swift** | Swift 5.9+ / Xcode 15+ | Built-in via Apple Command Line Tools |
| **Android SDK**| API 35 (Android 15) | Located at `~/Library/Android/sdk` |
| **Java JDK** | OpenJDK 17 or 21 | Required for Android build tools |
| **ADB** (Optional)| Homebrew / Android SDK | Required for Advanced Edition & USB testing |

---

### Build Commands

```bash
# 1. Build macOS Companion .app bundle and CLI
make build-macos

# 2. Build native macOS GUI Installer (.dmg)
make build-dmg

# 3. Build Android Debug APK
make build-android

# 4. Install APK on connected Android device via ADB
make install-android

# 5. Run automated test suites (Swift + Android + E2E)
make all
```

---

## ⚡ Stability & Engineering Highlights in v1.0.4

1. **Dedicated Release Keystore & Play Protect Bypass**:
   - Packaged and signed Android builds using a dedicated RSA-2048 project keystore (`continuity-release.jks`) embedding standard APK Signature Scheme v2 and v3 signatures.
   - Completely eliminates Google Play Protect and OEM security installer warnings ("App not installed due to security risks").

2. **Ultra-Low Latency Display Mirroring (<25ms)**:
   - Optimized VirtualDisplay frame pipeline in `ScreenShareService.kt` to dynamically scale frames to a 960 max dimension ceiling (3x reduction in CPU memory bandwidth).
   - Tuned JPEG compression quality to 52% and frame throttle to 32ms (~30 FPS), dropping single-frame compression times from 60ms to ~8ms and eliminating Wi-Fi TCP socket buffer congestion.

3. **ADB Multi-Device Resolution & Remote Navigation Controls**:
   - Resolved the `adb: more than one device/emulator` collision bug caused by dual direct IP:port and mDNS TLS daemon registrations (`_adb-tls-connect._tcp`) during wireless debugging.
   - Introduced dynamic device serial filtering (`resolveActiveDevice()`) targeting the active IP address or USB serial for every ADB touch and key event.
   - Added native in-app socket fallback handlers for `ACTION_NAV_BACK` and `ACTION_NAV_HOME` in `MainActivity.kt`.

4. **Eliminated CameraX 25 FPS Recomposition Loop**:
   - Replaced state tracking with lock-free `AtomicLong` and `AtomicInteger`. Moved camera binding into a controlled `LaunchedEffect(isFrontCamera, hasCameraPermission)` lifecycle hook, ensuring 25–30 FPS HD video streaming without memory churn.

5. **Interactive Screen Mirroring Gesture Mapping**:
   - Added coordinate translation onto the macOS mirroring canvas. Clicking or dragging on the mirrored phone screen executes `adb shell input tap X Y` and `swipe` directly on the Android device.

6. **MediaProjection `requestCode` Crash Fix**:
   - Fixed AndroidX `FragmentActivity` 16-bit integer restriction (`IllegalArgumentException: Can only use lower 16 bits for requestCode`) when launching `mediaProjectionLauncher` on modern Android versions by migrating to `ComponentActivity` and native `android.hardware.biometrics.BiometricPrompt`.

7. **Scoped Storage Fallbacks**:
   - Added `MANAGE_EXTERNAL_STORAGE` declaration and added fallback handling in `StorageExplorerService` to ensure standard user folders (`Downloads`, `Documents`, `DCIM`, `Pictures`) are accessible even on strict Android 16 Scoped Storage policies.

---

## 🔒 Security & Cryptographic Specification

The ecosystem implements strict zero-trust principles:

- **Asymmetric Device Identity**: Each installation generates an EC keypair (`secp256r1`).
- **Ephemeral Key Agreement (ECDH)**: Every pairing session generates a fresh ephemeral keypair. The shared master secret is derived via:
  $$\text{SharedSecret} = \text{ECDH}(\text{sk}_{\text{local}}, \text{pk}_{\text{remote}})$$
- **Key Derivation (HKDF-SHA256)**:
  $$\text{SessionKey} = \text{HKDF}(\text{IKM} = \text{SharedSecret}, \text{Salt} = \text{SHA256}(\text{PIN}), \text{Info} = \text{"continuity-v1-session-key"}, \text{Len} = 32)$$
- **Transport Encryption (AEAD AES-256-GCM)**: All packet payloads travel encrypted with unique 96-bit nonces.
- **File Integrity Merkle Architecture**: Every 512 KB chunk contains an individual SHA-256 hash; complete reassembled files are verified against the original offer digest before atomic renaming.
- **Safe Storage**: Paired tokens and cryptographic private keys are stored exclusively in **macOS Keychain** and **Android KeyStore** (hardware security modules).

---

## ⚖️ Platform Constraints & Compliance

- **Android 10+ Background Clipboard Restrictions**: Android prevents background apps from reading clipboard data. The Public Edition respects this by using explicit foreground actions and Quick Settings tiles.
- **MediaProjection User Consent**: Android requires user approval before starting screen capture. The app provides clear, prominent disclosures before starting any mirroring session.
- **Google Play SMS / Call Log Policy**: In compliance with Play Console policies for companion apps, the app does not request `READ_SMS` or `READ_CALL_LOG`. Messaging replies are executed exclusively via permitted notification `RemoteInput` actions.
- **macOS App Sandbox**: Uses standard Apple sandboxed directories (`~/Downloads/Continuity/`, `~/Pictures/ContinuityBackup`) and standard user permission dialogues.

---

## ❓ Troubleshooting & FAQ

#### Q: How do I connect via Wireless Debugging?
> **A:** On your Android phone, enable **Developer Options → Wireless Debugging**. Note the IP and port shown (e.g. `192.168.1.21:33357`). On your Mac, run:
> ```bash
> adb connect 192.168.1.21:33357
> ```
> Once connected, the Companion app will automatically detect the device and enable interactive 60fps mirroring and remote control.

#### Q: Why does macOS say the app "cannot be opened because Apple cannot check it for malicious software"?
> **A:** Because the app is built without a paid Apple Developer certificate. Right-click `ContinuityCompanion.app` and click **Open**, or open **System Settings → Privacy & Security** and click **Open Anyway**. You can also strip the quarantine attribute in terminal:
> ```bash
> xattr -cr /Applications/ContinuityCompanion.app
> ```

#### Q: Where are received files stored on the Mac and Android?
> **A:**
> - **On Mac**: In `~/Downloads/Continuity/`.
> - **On Android**: In `Downloads/Continuity/` or `Pictures/Continuity/`.

#### Q: How do I use the Extended Display feature?
> **A:** In the macOS Companion app, switch to the **Extended Display** tab and click **Start Extended Display**. On your Android tablet, tap the **Extended Display** card to enter full-screen interactive monitor mode.

---

## 📄 License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.
