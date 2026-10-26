# System Architecture Document
**Android + macOS Continuity Ecosystem**
*Version 1.0.4 — Architectural Blueprint & Subsystem Reference*

---

## 1. High-Level Architecture Overview

The system operates on a decentralized, peer-to-peer model over the local area network. Devices advertise availability via mDNS/Bonjour and UDP broadcast, establish mutual ECDH P-256 / AES-256-GCM encrypted transport sockets, and multiplex application-level messages across a single length-prefixed framing layer (`CNT1`).

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
│  │  • FileTransferEngine / Sync     │  │       │  │  • FileTransferManager (SAF)     │  │
│  │  • NotificationBridge            │  │       │  │  • ContinuityNotificationListener│  │
│  │  • ClipboardBridge               │  │       │  │  • ClipboardSyncManager          │  │
│  │  • CameraStreamManager           │  │       │  │  • CameraStreamingService        │  │
│  │  • MirroringManager              │  │       │  │  • ScreenShareService / MediaProj│  │
│  │  • PhotoBackupManager            │  │       │  │  • PhotoBackupWorker (WorkMgr)   │  │
│  │  • PairingManager                │  │       │  │  • PairingManager                │  │
│  │  • AdvancedHost (ADB/scrcpy)     │  │       │  │  • HostControlHandler            │  │
│  └──────────────────┬───────────────┘  │       │  └──────────────────┬───────────────┘  │
│                     │                  │       │                     │                  │
│  ┌──────────────────▼───────────────┐  │       │  ┌──────────────────▼───────────────┐  │
│  │    ContinuityProtocol Engine     │  │       │  │    ContinuityCore Engine         │  │
│  │  • Length-Prefixed Binary Framing│  │       │  │  • Binary Framing Stream Decoder │  │
│  │  • JSON/Protobuf Serialization   │  │       │  │  • JSON/Protobuf Serialization   │  │
│  │  • CryptoKit (AES-256-GCM / ECDH)│  │       │  │  • CryptoManager (AES-GCM / ECDH)│  │
│  └──────────────────┬───────────────┘  │       │  └──────────────────┬───────────────┘  │
│                     │                  │       │                     │                  │
│  ┌──────────────────▼───────────────┐  │       │  ┌──────────────────▼───────────────┐  │
│  │   Network.framework (NWListener/ │  │       │  │   Java NIO / SecureSocket / NSD  │  │
│  │   NWConnection) & LanDiscovery   │  │       │  │   & LanDiscoveryManager (UDP+NSD)│  │
│  └──────────────────┬───────────────┘  │       │  └──────────────────┬───────────────┘  │
└─────────────────────┼──────────────────┘       └─────────────────────┼──────────────────┘
                      │                                                │
                      └═══════════ Encrypted Local TCP Socket ═════════┘
                                   Bonjour: _continuity._tcp
                                   Ports: 52400-52401 (TCP), 52402 (UDP)
```

---

## 2. Component Breakdown

### 2.1 macOS Subsystems
- **CompanionApp / MenuBar**: Provides real-time status menu, drop zone for immediate file dispatch, battery HUD, and settings dashboard.
- **ConnectionAgent & LanDiscoveryService**: Encapsulates `Network.framework` `NWListener`, `NWBrowser`, and UDP broadcast probing on port 52402. Discovers and reconnects Android nodes on the local Wi-Fi subnet.
- **PairingManager**: Manages pairing sessions, visual 6-digit PIN challenges, QR token generation (`continuity://pair?...`), session key commitment, and trust state transitions within `DeviceRegistry`.
- **FileTransferEngine**: Manages asynchronous file sending and receiving queues. Implements 512KB chunked streaming, SHA-256 chunk validation, automatic resume offset negotiation, and write sandboxing into `~/Downloads/Continuity/`.
- **PhotoBackupManager**: Incremental media backup receiver on macOS. Organizes received photos into `~/Pictures/ContinuityBackup/YYYY/MM/`, performs SHA-256 deduplication against existing local assets, and tracks sync telemetry.
- **CameraStreamManager**: Dedicated observable camera receiver. Handles frame buffer ingestion, H.264/JPEG decoding, FPS calculation, resolution negotiation, and CoreMediaIO virtual camera relaying.
- **MirroringManager**: Dedicated observable screen mirroring manager. Manages low-latency display frame rendering, latency telemetry, remote touch/mouse coordinate translation, and stream lifecycle state.
- **NotificationBridge**: Receives incoming Android notifications, converts them into macOS `UNUserNotificationCenter` requests, and forwards user inline replies back to Android.
- **ClipboardBridge**: Monitors `NSPasteboard.general` with privacy filters (skipping sensitive password fields) and transmits updates on user action.
- **AdvancedHost**: Manages local `scrcpy` and ADB binaries, establishing reverse ADB port forwarding and low-latency input capture.

### 2.2 Android Subsystems
- **CryptoManager & DeviceIdentity**: Manages device UUID, persistent ECDH P-256 keypairs in `AndroidKeyStore`, RFC 5869 HKDF key derivation, HMAC-SHA256 authentication tags, and AES-256-GCM encryption/decryption matching Apple `CryptoKit.AES.GCM.SealedBox.combined`.
- **LanDiscoveryManager & ConnectionService**: Android Network Service Discovery (NSD) combined with UDP broadcast discovery (port 52402) for zero-config mDNS resolution and background connection lifecycle management.
- **PairingManager**: Manages camera-based QR code scanning, visual 6-digit PIN verification, mutual key derivation, and device trust persistence.
- **HostControlHandler**: Handles remote pointer moves, mouse clicks, keyboard text input, and hardware navigation key codes (Home, Back, Recent Apps, Volume).
- **FileTransferManager**: Interacts with Android Storage Access Framework (`DocumentsContract`) and `MediaStore` to stream files without requesting broad external storage permissions.
- **NotificationListenerService**: Reads permitted status-bar notifications and intercepts `RemoteInput` reply actions to execute replies sent from macOS.
- **ScreenShareService**: Manages user-granted `MediaProjection` captures, feeding video frames into Android's hardware `MediaCodec` (AVC/H.264).
- **CameraStreamingService**: Leverages `CameraX` to capture camera frames and stream them with minimal latency.
- **PhotoBackupWorker**: Uses Android `WorkManager` with battery and Wi-Fi network constraints to backup incremental media.

---

## 3. Communication & Multiplexing

All protocol communication travels over a single encrypted TCP connection per paired device pair, multiplexed via message headers in the `ContinuityEnvelope`:
- **Channel 0 (High Priority / Control)**: Heartbeats, Pair Requests, Capability queries, Input events.
- **Channel 1 (Data / Interactive)**: Clipboard payloads, Notification events, Remote replies.
- **Channel 2 (Bulk Streaming)**: File transfer chunks.
- **Channel 3 (Media Stream)**: Screen mirroring and camera video frames.

This logical channel architecture prevents large file transfers from starving critical heartbeat or notification packets.
