# Product Requirements Document (PRD)
**Android + macOS Continuity Ecosystem**
*Version 1.0 — Public Application + Advanced Personal Edition*

---

## 1. Executive Summary & Vision

The **Android + macOS Continuity Ecosystem** delivers a cohesive, low-latency, and privacy-preserving bridge between Android smartphones and macOS desktop environments. Designed to approximate Apple's native Continuity workflows, the platform provides seamless cross-device synchronization (files, clipboard, notifications, screen mirroring, and virtual camera integration) while adhering to Android platform constraints and offering power-user extensions.

### Core Objectives
1. **Frictionless Native Integration**: Native Swift/SwiftUI on macOS and Kotlin/Jetpack Compose on Android with platform-idiomatic UX.
2. **Zero-Configuration Consumer Path**: No root, ADB, or terminal commands required for the Public Edition.
3. **Advanced Power-User Harness**: Modular scrcpy and ADB integration for ultra-low latency display mirroring and input automation in the Advanced Edition.
4. **Local-First & Offline**: Direct Wi-Fi / mDNS connectivity without cloud dependency, user accounts, or forced subscriptions.
5. **End-to-End Security**: Authenticated key exchange (ECDH), AES-256-GCM transport, and sandboxed storage access.

---

## 2. Product Editions & Scope

| Attribute | Public Edition | Advanced Personal Edition |
| :--- | :--- | :--- |
| **Distribution** | Google Play Store + Signed macOS App | Direct APK / GitHub + Mac Helper Daemon |
| **Permissions** | Standard Android user permissions (SAF, Notifications) | Developer options (USB / Wireless ADB) |
| **Setup Barrier** | Instant QR code scan | One-time ADB authorization |
| **Screen Mirroring** | Android MediaProjection API (User consent prompt) | Bundled `scrcpy` over TCP/IP or USB (< 35ms latency) |
| **Remote Control** | Read-only status & notification actions | Full hardware keyboard/mouse injection |
| **Clipboard** | Explicit foreground / Quick Settings share | Seamless background synchronization |

---

## 3. Detailed Feature Breakdown & Prioritization

### P0: Core & Connectivity (MVP Baseline)
- **SEC-01 Secure Pairing**: Ephemeral QR code generation, SAS 6-digit confirmation pin, mutual authentication, and pairing token caching.
- **NET-01 Discovery**: Local Bonjour / mDNS zero-conf announcement (`_continuity._tcp`) with manual IP fallback.
- **NET-02 Encrypted Transport**: Authenticated framing with AES-256-GCM and keepalive heartbeats every 10 seconds.
- **STAT-01 Device Telemetry**: Real-time reporting of phone battery percentage, charging state, Wi-Fi SSID, and storage space.
- **FILE-01 Bidirectional File Transfer**: Drag-and-drop file sending from Mac to Android; Android system share sheet to Mac. Chunked transfer with SHA-256 integrity verification.
- **CLIP-01 Explicit Clipboard**: Foreground clipboard sending from Mac to phone, and Android Quick Settings tile / share-sheet to Mac.

### P1: Media, Sync & Notifications
- **NOTIF-01 Notification Mirroring**: Forwarding permitted Android notifications to macOS Notification Center.
- **NOTIF-02 Quick Replies**: In-line reply support via Android `RemoteInput` actions.
- **SCR-01 MediaProjection Mirroring**: Real-time screen streaming via H.264 over local Wi-Fi.
- **CAM-01 Phone as Mac Webcam**: High-resolution camera streaming integrated with macOS CoreMediaIO virtual camera extension.
- **SYNC-01 Photo Backup**: Background incremental backup of camera roll to a designated Mac directory.

### P2: Advanced & Ecosystem Expansion
- **SCR-02 scrcpy Integration**: High-framerate, low-latency display control for authorized ADB users.
- **HAND-01 Universal URL Handoff**: Open current mobile browser tab on Mac default browser.
- **RELAY-01 Remote Tunnel**: Encrypted WebSocket relay fallback for devices on different subnets.

---

## 4. Platform Constraints & Compliance Rules

1. **Android Background Clipboard (Android 10+)**: Background apps cannot read clipboard events silently. The public app relies on user-initiated Quick Settings tiles, share targets, or foreground app paste.
2. **MediaProjection Consent**: User consent cannot be bypassed or cached permanently in the public edition; a consent prompt must appear per session.
3. **Google Play SMS & Call Log Policy**: Companions must not declare `READ_SMS` or `READ_CALL_LOG` unless operating as a default phone/SMS handler. Public release avoids these permissions; messaging is handled purely via notification action replies.
4. **macOS Sandboxing & System Extensions**: Core companion app adheres to App Sandbox guidelines; camera extensions utilize modern `CMIOExtension` APIs; advanced ADB helper is packaged as a standalone launchd daemon.
