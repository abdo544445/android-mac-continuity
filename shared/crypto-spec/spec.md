# Cryptographic Specification & Security Architecture
**Android + macOS Continuity Ecosystem**
*Version 1.0 — Security Specification*

---

## 1. Overview and Security Goals

The Continuity Ecosystem connects macOS and Android devices across unencrypted or untrusted local networks (such as public Wi-Fi) as well as optional remote relay endpoints. The security architecture provides:

1. **Mutual Authentication**: Devices verify each other's cryptographic identity before establishing trust.
2. **Confidentiality & Integrity**: All payload messages, files, clipboard data, notifications, and media streams are encrypted and authenticated.
3. **Forward Secrecy**: Ephemeral key exchange ensures that compromise of long-term identity keys does not compromise past communication sessions.
4. **Replay & MitM Protection**: Short-lived pairing sessions, visual out-of-band verification PINs, monotonicity in heartbeat counters, and cryptographically bound request IDs.
5. **Zero Trust Local Network**: No unauthenticated API endpoints, no cleartext broadcasts, and no static shared secrets.

---

## 2. Key Primitives & Algorithms

| Function | Algorithm / Primitive | Standard / RFC |
| :--- | :--- | :--- |
| **Identity Key Pairs** | Ed25519 or NIST P-256 | RFC 8032 / FIPS 186-4 |
| **Ephemeral Key Agreement** | X25519 or ECDH (P-256) | RFC 7748 / NIST SP 800-56A |
| **Key Derivation Function** | HKDF-SHA256 | RFC 5869 |
| **Symmetric Payload Cipher** | AES-256-GCM / ChaCha20-Poly1305 | RFC 5116 / RFC 8439 |
| **Integrity & Checksumming**| SHA-256 | FIPS 180-4 |
| **Out-of-Band Verification**| 6-digit numeric SAS (Short Authentication String) | Visual confirmation |

---

## 3. Pairing Protocol & Handshake Workflow

### 3.1 QR Code Pairing Payload Format

When the Mac initiates pairing, it generates a transient pairing session and displays a QR code containing an authenticated URI:

```
continuity://pair?v=1&id=<device_uuid>&name=<url_encoded_name>&host=<local_ip>&port=<listen_port>&pk=<base64_ephemeral_pubkey>&pin=<6_digit_pin>&exp=<unix_timestamp_seconds>
```

- `v`: Protocol version (`1`).
- `id`: Unique UUID of the initiating device.
- `name`: Human-readable device name.
- `host`: Local IPv4 or IPv6 address.
- `port`: Listening TCP port.
- `pk`: Base64-encoded ephemeral public key (32 bytes).
- `pin`: Out-of-band 6-digit numeric confirmation token.
- `exp`: Expiration timestamp (strictly valid for 180 seconds).

### 3.2 Handshake Sequence Diagram

```
Android (Client)                                  macOS (Host)
      │                                                │
      │ 1. Scan QR Code (Extract Host, Port, pkA, PIN) │
      │───────────────────────────────────────────────>│
      │                                                │
      │ 2. TCP Connect + TLS / Frame Channel           │
      │───────────────────────────────────────────────>│
      │                                                │
      │ 3. PairRequest:                                │
      │    - device_id, name, platform                 │
      │    - pkB (Android ephemeral public key)        │
      │    - pin (Visual 6-digit PIN)                  │
      │───────────────────────────────────────────────>│
      │                                                │
      │                                4. Verify PIN & │
      │                                   Display Prompt│
      │                                   Derive Shared│
      │                                   Secret (KDF) │
      │                                                │
      │ 5. PairConfirm:                                │
      │    - approved: true/false                      │
      │    - assigned_session_token                    │
      │    - auth_tag = HMAC-SHA256(K, "CONFIRM" || pk)│
      │<───────────────────────────────────────────────│
      │                                                │
      │ 6. Verify auth_tag                             │
      │    Derive Session Keys (K_enc, K_mac)          │
      │                                                │
      │ 7. DeviceHello & CapabilityList Exchange       │
      │<══════════════════════════════════════════════>│
      │                                                │
      │ 8. Secure Transport Active (AES-256-GCM)       │
```

### 3.3 Key Derivation Details

1. **Shared Secret Calculation**:
   $$\text{SharedSecret} = \text{ECDH}(\text{PrivateKey}_{\text{local}}, \text{PublicKey}_{\text{remote}})$$

2. **Master Key Derivation (HKDF-Extract)**:
   $$\text{PRK} = \text{HKDF-Extract}(\text{salt} = \text{SHA256}(\text{pin}), \text{IKM} = \text{SharedSecret})$$

3. **Session Keys Expansion (HKDF-Expand)**:
   - Client-to-Server Encryption Key:
     $$\text{Key}_{\text{C2S}} = \text{HKDF-Expand}(\text{PRK}, \text{"continuity-v1-c2s-aes256gcm"}, 32)$$
   - Server-to-Client Encryption Key:
     $$\text{Key}_{\text{S2C}} = \text{HKDF-Expand}(\text{PRK}, \text{"continuity-v1-s2c-aes256gcm"}, 32)$$
   - Confirmation Tag:
     $$\text{Tag}_{\text{Auth}} = \text{HMAC-SHA256}(\text{PRK}, \text{"continuity-v1-confirm"})$$

---

## 4. Binary Framing & Transport Protocol

Every message over the TCP socket uses a 8-byte binary framing header:

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|       Magic Bytes ('C', 'N', 'T', '1')        | Flags | Encr. |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                       Payload Length (32-bit)                 |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                    Initialization Vector (12 bytes)           |
|                                                               |
|                                                               |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                      Encrypted Payload Data ...               |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                      GCM Auth Tag (16 bytes)                  |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

- **Magic**: `0x43 0x4E 0x54 0x31` ("CNT1").
- **Flags**: Bitfield (Bit 0: Is Compressed, Bit 1: Is Heartbeat, Bit 2: Priority).
- **Encr**: Encryption flag (`0x00`: Unencrypted Handshake, `0x01`: AES-256-GCM).
- **Payload Length**: 32-bit big-endian integer describing byte length.
- **IV**: 12-byte unique nonce incremented per message to prevent nonce reuse.
- **Auth Tag**: 16-byte Poly1305 / GCM tag guaranteeing integrity.

---

## 5. File Transfer Integrity & Resume Protocol

1. **Offer Stage**: Sender computes the SHA-256 hash of the complete file and divides the file into fixed-size chunks (default: $512\text{ KB} = 524,288\text{ bytes}$).
2. **Chunk Transmission**: Each `TransferChunk` contains:
   - `transfer_id`: UUID
   - `chunk_index`: 0-based index
   - `chunk_sha256`: SHA-256 of the current chunk data
   - `data`: Raw binary bytes
3. **Receipt Validation**: Receiver writes data to a `.tmp` file (e.g. `incoming_file.bin.part`) and verifies each chunk's individual hash.
4. **Completion**: Upon receiving the final chunk, receiver calculates the full SHA-256 of the assembled file and verifies it against `TransferOffer.sha256_checksum`.
5. **Atomic Rename**: Only after verification succeeds is the `.tmp` file renamed to its final destination name (with collision avoidance: `file (1).ext`).
6. **Resuming**: If disconnected, receiver returns `resume_chunk_index` in `TransferAccept`, resuming from the last confirmed written byte.

---

## 6. Device Key Storage & Revocation

- **macOS**: Long-term identity keys and paired device credentials are saved in Apple's encrypted **macOS Keychain Services** (`kSecClassGenericPassword`, accessible only by the Continuity Companion application).
- **Android**: Long-term keys are generated inside the **Android Keystore Provider** (`KeyProperties.PURPOSE_SIGN | KeyProperties.PURPOSE_VERIFY`), protected by hardware security modules (TEE / StrongBox) where available.
- **Revocation**: Either device can permanently unpair by sending a signed `PairStatus(STATUS_REVOKED)` message or deleting the local key record. A revoked device ID is immediately blacklisted and cannot reconnect without a new QR pairing sequence.
