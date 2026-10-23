# Permissions & Compliance Matrix
**Android + macOS Continuity Ecosystem**
*Version 1.0 — Regulatory & Capability Mapping*

---

## 1. Android Permission Matrix

| Permission | Public Edition | Advanced Edition | User Prompt Type | Google Play Compliance Justification | Fallback Strategy |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `INTERNET` | Yes | Yes | Install time | Required for local TCP/IP socket communication. | None (Essential) |
| `ACCESS_NETWORK_STATE` | Yes | Yes | Install time | Network interface monitoring & Wi-Fi state detection. | None |
| `ACCESS_WIFI_STATE` | Yes | Yes | Install time | Reads Wi-Fi SSID to display connected network status. | Shows "Wi-Fi" without SSID |
| `CHANGE_WIFI_MULTICAST_STATE` | Yes | Yes | Install time | Required for mDNS / Bonjour network service discovery. | Manual IP entry |
| `POST_NOTIFICATIONS` | Yes | Yes | Runtime prompt | Notifies user of connection status, file transfers, and pairing requests. | Silent transfers without status bar HUD |
| `FOREGROUND_SERVICE` | Yes | Yes | Install time | Maintains active transfer and media streaming sessions. | Transfers stop on backgrounding |
| `BIND_NOTIFICATION_LISTENER_SERVICE` | Yes | Yes | Special Access Settings | Reads notifications from permitted apps to forward to macOS. | Feature disabled until granted |
| `CAMERA` | Yes | Yes | Runtime prompt | 1. Scanning pairing QR codes.<br>2. Streaming camera video as Mac webcam. | Manual PIN pairing; Webcam disabled |
| `READ_MEDIA_IMAGES` / `READ_MEDIA_VIDEO` | Yes | Yes | Runtime prompt | Required for automated background photo backup. | Manual SAF file picking |
| `MANAGE_EXTERNAL_STORAGE` | **NO** | Optional | Prohibited in Play | Violates Google Play All Files Access policy. | Storage Access Framework (SAF) |
| `READ_SMS` / `READ_CALL_LOG` | **NO** | No | Prohibited in Play | Prohibited unless designated as default SMS/Phone app. | Notification reply actions only |
| `BIND_ACCESSIBILITY_SERVICE` | **NO** | Optional | Special Access Settings | Banned on Google Play for remote control without disability justification. | scrcpy via ADB in Advanced Edition |

---

## 2. macOS Entitlements & Permissions Matrix

| Entitlement / Permission | Sandboxed App | Advanced Helper Daemon | Purpose |
| :--- | :--- | :--- | :--- |
| `com.apple.security.network.client` | Yes | Yes | Outgoing TCP connections to Android device. |
| `com.apple.security.network.server` | Yes | Yes | Incoming TCP listener for Bonjour discovery and file transfers. |
| `com.apple.security.files.user-selected.read-write` | Yes | Yes | User drag-and-drop file transfers. |
| `com.apple.security.files.downloads.read-write` | Yes | Yes | Saving received files into `~/Downloads/Continuity/`. |
| `NSAppleEventsUsageDescription` | Optional | Yes | Automations and Shortcuts integration. |
| `NSCameraUsageDescription` | Yes | Yes | Local preview and CoreMediaIO camera sink. |
| `NSUserNotificationUsageDescription` | Yes | Yes | Displaying mirrored Android notifications in Notification Center. |
| `com.apple.security.device.usb` | No | Yes | Advanced Edition USB ADB connection management. |
