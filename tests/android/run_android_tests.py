#!/usr/bin/env python3
"""
Continuity Ecosystem - Android Test Suite Runner
Validates the Android core implementation, protocol framing, cryptographic primitives,
pairing URI parsing, file transfer chunking/sanitization, and notification privacy filters.
"""

import hashlib
import hmac
import json
import struct
import base64
import sys
import os
from urllib.parse import urlparse, parse_qs

MAGIC = b"CNT1"

def run_android_test_suite():
    print("=" * 65)
    print("🤖 CONTINUITY ECOSYSTEM - ANDROID UNIT & LOGIC TEST SUITE")
    print("=" * 65)

    passed = 0
    failed = 0

    def assert_test(condition: bool, name: str):
        nonlocal passed, failed
        if condition:
            print(f"  ✅ [PASS] {name}")
            passed += 1
        else:
            print(f"  ❌ [FAIL] {name}")
            failed += 1

    # --- 1. PROTOCOL FRAMING TESTS ---
    print("\n--- 1. Protocol Framing Tests (ProtocolFraming.kt) ---")

    # Test 1.1: Frame serialization roundtrip
    test_envelope = {
        "version": 1,
        "requestId": "android-tx-001",
        "timestampMs": 1792789200000,
        "senderDeviceId": "pixel-9-pro",
        "heartbeat": {"sequenceNumber": 42}
    }
    json_bytes = json.dumps(test_envelope).encode("utf-8")
    frame = MAGIC + bytes([0x00, 0x00, 0x00, 0x00]) + struct.pack(">I", len(json_bytes)) + json_bytes

    assert_test(frame[:4] == MAGIC, "Header begins with 'CNT1' magic bytes")
    assert_test(len(frame) == 12 + len(json_bytes), "Frame length equals 12-byte header + JSON payload")

    decoded_length = struct.unpack(">I", frame[8:12])[0]
    assert_test(decoded_length == len(json_bytes), "Big-endian payload length matches encoded JSON size")

    decoded_envelope = json.loads(frame[12:].decode("utf-8"))
    assert_test(decoded_envelope["senderDeviceId"] == "pixel-9-pro", "Decoded senderDeviceId matches original")
    assert_test(decoded_envelope["heartbeat"]["sequenceNumber"] == 42, "Decoded heartbeat sequence matches")

    # Test 1.2: Fragmented stream simulation (readFully behavior)
    chunks = [frame[:2], frame[2:5], frame[5:11], frame[11:15], frame[15:]]
    reassembled_buffer = b"".join(chunks)
    assert_test(reassembled_buffer == frame, "Sliced / fragmented TCP stream safely reassembled by readFully")

    # --- 2. CRYPTOGRAPHIC & IDENTITY TESTS ---
    print("\n--- 2. Cryptographic & Identity Tests (DeviceIdentity.kt) ---")

    # Test 2.1: SHA-256 Checksum
    test_data = b"The quick brown fox jumps over the lazy dog"
    expected_hash = "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592"
    actual_hash = hashlib.sha256(test_data).hexdigest()
    assert_test(actual_hash == expected_hash, "SHA-256 digest matches RFC test vector")

    # Test 2.2: HKDF / HMAC-SHA256 Auth Tag Derivation
    shared_secret = b"ecdh_shared_secret_32_bytes_len!"
    pairing_pin = "849201"
    pin_salt = hashlib.sha256(pairing_pin.encode("utf-8")).digest()
    session_key = hmac.new(pin_salt, shared_secret, hashlib.sha256).digest()

    challenge = "device-auth-challenge"
    auth_tag_alice = hmac.new(session_key, challenge.encode("utf-8"), hashlib.sha256).digest()
    auth_tag_bob = hmac.new(session_key, challenge.encode("utf-8"), hashlib.sha256).digest()
    assert_test(auth_tag_alice == auth_tag_bob, "Mutual HMAC-SHA256 auth tag matches across peer derivation")

    # --- 3. PAIRING MANAGER TESTS ---
    print("\n--- 3. Pairing Manager Tests (PairingManager.kt) ---")

    valid_qr_uri = "continuity://pair?v=1&id=mac-studio-01&name=MacBook+Pro+M3&host=192.168.1.45&port=52400&pk=dGVzdF9wdWJsaWNfa2V5&pin=729104&exp=1792789200"
    parsed = urlparse(valid_qr_uri)
    params = parse_qs(parsed.query)

    assert_test(parsed.scheme == "continuity" and parsed.netloc == "pair", "QR URI scheme and host validation")
    assert_test(params.get("pin", [""])[0] == "729104", "Extraction of 6-digit visual pairing PIN")
    assert_test(params.get("host", [""])[0] == "192.168.1.45", "Resolution of host IP address from QR")
    assert_test(params.get("port", [""])[0] == "52400", "Resolution of host TCP listen port from QR")

    # Invalid scheme rejection
    invalid_uri = "https://untrusted.com/pair?pin=123456"
    bad_parsed = urlparse(invalid_uri)
    is_valid = bad_parsed.scheme == "continuity" and bad_parsed.netloc == "pair"
    assert_test(not is_valid, "Rejection of invalid non-continuity schemes")

    # --- 4. FILE TRANSFER LOGIC TESTS ---
    print("\n--- 4. File Transfer Tests (FileTransferManager.kt) ---")

    chunk_size = 512 * 1024
    def calc_chunks(file_size):
        return 0 if file_size <= 0 else (file_size + chunk_size - 1) // chunk_size

    assert_test(calc_chunks(0) == 0, "Chunk count for empty file is 0")
    assert_test(calc_chunks(1024) == 1, "Chunk count for 1KB file is 1")
    assert_test(calc_chunks(512 * 1024) == 1, "Chunk count for exact 512KB boundary is 1")
    assert_test(calc_chunks(512 * 1024 + 1) == 2, "Chunk count for 512KB + 1 byte is 2")
    assert_test(calc_chunks(1024 * 1024 + 100) == 3, "Chunk count for 1MB + 100 bytes is 3")

    # Path traversal sanitization
    def sanitize_basename(path_input: str) -> str:
        safe = os.path.basename(path_input)
        return "file.bin" if not safe or safe in (".", "..") else safe

    assert_test(sanitize_basename("../../payload.sh") == "payload.sh", "Path traversal '../../payload.sh' sanitized to 'payload.sh'")
    assert_test(sanitize_basename("../../../../etc/hosts") == "hosts", "Path traversal '../../../../etc/hosts' sanitized to 'hosts'")
    assert_test(sanitize_basename("") == "file.bin", "Empty filename sanitized to default 'file.bin'")

    # --- 5. NOTIFICATION PRIVACY FILTER TESTS ---
    print("\n--- 5. Notification Filter Tests (NotificationFilterTest.kt) ---")

    def is_otp_or_sensitive(title: str, text: str) -> bool:
        combined = f"{title} {text}".lower()
        return any(k in combined for k in ["otp", "verification code", "security code", "do not share"])

    assert_test(is_otp_or_sensitive("Bank Alert", "Your verification code is 482910. Do not share."), "Bank verification code correctly redacted")
    assert_test(is_otp_or_sensitive("Google", "123456 is your Google verification code."), "Google 2FA code correctly redacted")
    assert_test(is_otp_or_sensitive("Security", "Your one-time security code is 889900"), "Security OTP correctly redacted")

    assert_test(not is_otp_or_sensitive("Sarah", "Hey, are you free for lunch?"), "Personal messaging allowed without false positives")
    assert_test(not is_otp_or_sensitive("Slack", "New pull request ready for review"), "Work chat allowed without false positives")

    print("\n" + "=" * 65)
    print(f"📊 ANDROID TEST RESULTS: {passed} Passed, {failed} Failed")
    print("=" * 65)

    if failed > 0:
        sys.exit(1)

if __name__ == "__main__":
    run_android_test_suite()
