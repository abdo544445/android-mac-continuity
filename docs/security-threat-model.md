# Security Threat Model (STRIDE)
**Android + macOS Continuity Ecosystem**
*Version 1.0 — Security & Threat Analysis*

---

## 1. System Scope & Assets Under Protection

The Continuity Ecosystem connects macOS and Android devices across potentially hostile local area networks (e.g. coffee shop or hotel Wi-Fi) and relays.

### Assets:
1. **User Files**: Confidential user documents and photos.
2. **Notification Content**: Potentially containing two-factor authentication (2FA) codes or private conversations.
3. **Clipboard Data**: Passwords, tokens, or personal identifiers.
4. **Display Frames & Camera Feed**: Real-time visual and audio telemetry.
5. **Device Identity Keys**: Long-term cryptographic keys that authorize device control.

---

## 2. STRIDE Threat Analysis

### 2.1 Spoofing Identity
- **Threat**: A rogue device on the local network impersonates the user's Mac or Android phone.
- **Mitigation**: Mutual cryptographic authentication. Pairing requires reading an out-of-band QR code containing an ephemeral public key and visual 6-digit confirmation PIN. Unpaired devices are rejected immediately at the protocol handshake layer.

### 2.2 Tampering with Data
- **Threat**: An adversary on the local subnet modifies file chunks or notification payloads in transit.
- **Mitigation**: Authenticated encryption with associated data (AEAD) using AES-256-GCM. Every frame contains a 16-byte authentication tag; file transfers additionally employ SHA-256 per chunk and overall Merkle verification.

### 2.3 Repudiation
- **Threat**: A malicious peer claims they did not initiate a file transfer or camera session.
- **Mitigation**: All session initiation and file transfer offers are signed using device identity keys and cryptographically logged in local audit databases.

### 2.4 Information Disclosure
- **Threat**: Passive eavesdropping on Wi-Fi broadcasts reveals clipboard contents, notifications, or camera video.
- **Mitigation**: All payload traffic is encrypted with AES-256-GCM using keys derived from an ephemeral ECDH handshake. No plaintext content or metadata is broadcast via mDNS. Sensitive Android 15+ OTP notifications are automatically filtered and redacted.

### 2.5 Denial of Service (DoS)
- **Threat**: Flooding TCP ports with garbage packets or oversized file transfer offers to exhaust memory or storage.
- **Mitigation**: Rate limiting on handshake attempts; fixed maximum frame size (1MB); mandatory user approval dialog before accepting any incoming file transfer offer; disk quota enforcement before writing received chunks.

### 2.6 Elevation of Privilege
- **Threat**: Utilizing companion app hooks to execute unauthorized commands or bypass Android security boundaries.
- **Mitigation**: Public Edition contains zero shell execution endpoints and zero accessibility input bypasses. Advanced Edition commands require explicit ADB authorization over a trusted USB or authenticated loopback interface.

---

## 3. Key Revocation & Lost Device Lifecycle

If either device is lost, stolen, or compromised:
1. The user selects **Unpair Device** in the Settings UI.
2. The local application wipes the remote device's public key and session tokens from Apple Keychain or Android Keystore.
3. A revocation notice is transmitted if connected; all future connection attempts from the revoked device ID are dropped silently without acknowledging protocol state.
