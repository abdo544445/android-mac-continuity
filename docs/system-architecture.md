# System Architecture Document
**Android + macOS Continuity Ecosystem**
*Version 1.0 — Architectural Blueprint*

---

## 1. High-Level Architecture Overview

The system operates on a decentralized, peer-to-peer model over the local area network. Devices advertise availability via mDNS/Bonjour, establish mutual TLS / AES-GCM encrypted transport sockets, and multiplex application-level messages across a single framing layer.

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

## 2. Component Breakdown

### 2.1 macOS Subsystems
- **CompanionApp / MenuBar**: Provides real-time status menu, drop zone for immediate file dispatch, battery HUD, and full settings dashboard.
- **ConnectionAgent**: Encapsulates `Network.framework` `NWListener` and `NWBrowser`. Automatically discovers Android nodes on the local Wi-Fi subnet.
- **FileTransferEngine**: Manages asynchronous file sending and receiving queues. Implements 512KB chunked streaming, SHA-256 chunk validation, automatic resume offset negotiation, and write sandboxing into `~/Downloads/Continuity/`.
- **NotificationBridge**: Receives incoming Android notifications, converts them into macOS `UNUserNotificationCenter` requests, and forwards user inline replies back to Android.
- **ClipboardBridge**: Monitors `NSPasteboard.general` with privacy filters (skipping sensitive password fields) and transmits updates on user action.
- **ScreenViewer & CameraExtension**: Decodes incoming H.264 video streams. CameraExtension registers as a macOS `CMIOExtension` virtual camera.
- **AdvancedHost**: Manages local `scrcpy` and ADB binaries, establishing reverse ADB port forwarding and low-latency input capture.

### 2.2 Android Subsystems
- **DeviceManager & SecurityManager**: Manages device UUID and asymmetric key pairs generated via `AndroidKeyStore`. Persists paired Mac certificates securely.
- **NetworkDiscovery & ConnectionService**: Android Network Service Discovery (NSD) for zero-config mDNS resolution and background connection lifecycle management.
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
