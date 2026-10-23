# API Protocol & Message Specification
**Android + macOS Continuity Ecosystem**
*Version 1.0 — Wire Protocol Reference*

---

## 1. Transport Layer Framing

All TCP traffic uses length-prefixed binary framing:

```
[4 Bytes Magic: "CNT1"]
[1 Byte Flags: bitfield]
[1 Byte Encryption Mode: 0x00=Plain, 0x01=AES-256-GCM]
[2 Bytes Reserved]
[4 Bytes Payload Length: Big-Endian uint32]
[12 Bytes Nonce / IV: Big-Endian uint96 (only if encrypted)]
[N Bytes Payload: Protobuf serialized ContinuityEnvelope]
[16 Bytes Auth Tag: GCM Tag (only if encrypted)]
```

### Encryption Modes:
- `0x00`: Unencrypted. Used strictly for initial ephemeral handshake messages (`PairRequest`, `PairConfirm`).
- `0x01`: AES-256-GCM. Used for all post-handshake envelopes (`Heartbeat`, `TransferOffer`, `NotificationEvent`, etc.).

---

## 2. Handshake & Session Establishment State Machine

```
   [DISCONNECTED]
         │ (mDNS Discovery / User Connect)
         ▼
    [CONNECTING] ───(TCP Handshake)───► [CONNECTED_UNAUTH]
                                                │
                               (PairRequest / PairConfirm)
                                                ▼
                                         [AUTHENTICATING]
                                                │
                           (Derive Keys & Verify Confirmation Tag)
                                                ▼
                                         [SESSION_READY]
                                         (DeviceHello / Capabilities)
                                                │
                                                ▼
                                         [ACTIVE_SYNC]
                                         (Multiplexed I/O)
```

---

## 3. Message Catalog Summary

| Message | Field IDs | Sender | Receiver | Description |
| :--- | :--- | :--- | :--- | :--- |
| `PairRequest` | 10 | Initiator | Responder | Initiates pairing with ephemeral public key and visual PIN. |
| `PairConfirm` | 11 | Responder | Initiator | Confirms pairing approval, session token, and auth tag. |
| `DeviceHello` | 13 | Both | Both | Exchanging OS, model, and application versions. |
| `CapabilityList`| 14 | Both | Both | Advertises supported features (media codecs, chunk sizes). |
| `Heartbeat` | 20 | Both | Both | Keepalive ping/pong transmitted every 10s. |
| `DeviceStatus` | 21 | Android | macOS | Battery level, charging status, Wi-Fi SSID, storage. |
| `TransferOffer`| 30 | Sender | Receiver | Offers file with name, size, MIME type, and SHA-256. |
| `TransferAccept`| 31 | Receiver | Sender | Accepts file with resume chunk index offset. |
| `TransferChunk`| 33 | Sender | Receiver | Carries binary chunk payload and chunk SHA-256. |
| `TransferComplete`| 34 | Receiver | Sender | Final verification notification after total SHA-256 check. |
| `ClipboardOffer`| 40 | Sender | Receiver | Notifies peer of new clipboard content with preview. |
| `ClipboardPayload`| 41 | Sender | Receiver | Delivers actual clipboard text or binary image. |
| `NotificationEvent`| 50 | Android | macOS | Forwards status bar notification with actions. |
| `NotificationAction`| 51 | macOS | Android | Dispatches action click or text reply to Android notification. |
| `SessionRequest`| 60 | macOS | Android | Requests screen mirroring or camera streaming session. |
| `SessionStop` | 61 | Both | Both | Gracefully terminates an active streaming session. |
| `ErrorResponse`| 99 | Both | Both | Standardized error code and message. |

---

## 4. Error Codes & Recovery

| Code | Name | Description | Recovery Action |
| :--- | :--- | :--- | :--- |
| 1 | `ERROR_BAD_REQUEST` | Malformed message or schema mismatch. | Drop connection and re-handshake. |
| 2 | `ERROR_UNAUTHORIZED` | Invalid or missing session token. | Re-run QR pairing. |
| 3 | `ERROR_FORBIDDEN` | Feature disabled by user privacy policy. | Prompt user to grant permission. |
| 4 | `ERROR_NOT_FOUND` | Referenced transfer or session ID not found. | Abort transfer and remove partial file. |
| 5 | `ERROR_SESSION_EXPIRED`| Ephemeral session timed out. | Reconnect with cached session token. |
| 6 | `ERROR_IO_FAILURE` | Disk write error or storage exhausted. | Clear space and retry transfer. |
| 7 | `ERROR_CHECKSUM_MISMATCH`| SHA-256 integrity check failed. | Re-request corrupted chunks or entire file. |
