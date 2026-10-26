package com.continuity.ecosystem.security

import org.junit.Assert.*
import org.junit.Test

class CryptoManagerTest {

    @Test
    fun testKeyPairGenerationAndRawEncoding() {
        val kp = CryptoManager.generateKeyPair()
        assertNotNull(kp.privateKey)
        assertNotNull(kp.publicKey)
        assertTrue(kp.publicKeyBase64.isNotEmpty())

        val rawPub = CryptoManager.encodeRawPublicKey(kp.publicKey)
        assertEquals("Raw public key must be exactly 64 bytes (ANSI X9.63 X||Y)", 64, rawPub.size)

        val decodedPub = CryptoManager.decodePublicKey(rawPub)
        assertNotNull(decodedPub)
        assertEquals("EC", decodedPub.algorithm)
    }

    @Test
    fun testHkdfVectors() {
        val ikm = "test_ikm_shared_secret_32bytes!!".toByteArray(Charsets.UTF_8)
        val salt = "test_salt_1234567890123456789012".toByteArray(Charsets.UTF_8)
        val info = "continuity-v1-session-key".toByteArray(Charsets.UTF_8)

        val derived = CryptoManager.hkdf(salt, ikm, info, 32)
        assertEquals(32, derived.size)

        val hex = derived.joinToString("") { "%02x".format(it) }
        // Matches exact CryptoKit and Python RFC 5869 test vector
        assertEquals("ab259755a1415c63ac54eae605386efaad242dccc73627bb64c36d17b448fdd7", hex)
    }

    @Test
    fun testMutualKeyDerivationAndAuthTag() {
        val alice = CryptoManager.generateKeyPair()
        val bob = CryptoManager.generateKeyPair()
        val pin = "849201"

        val aliceDerived = CryptoManager.deriveSessionKey(
            localPrivateKey = alice.privateKey,
            remotePublicKeyBase64 = bob.publicKeyBase64,
            pin = pin
        )

        val bobDerived = CryptoManager.deriveSessionKey(
            localPrivateKey = bob.privateKey,
            remotePublicKeyBase64 = alice.publicKeyBase64,
            pin = pin
        )

        assertArrayEquals("Both peers must derive identical 32-byte session key", aliceDerived, bobDerived)

        val challenge = "device-auth-challenge-12345"
        val tagAlice = CryptoManager.computeAuthTag(aliceDerived, challenge)
        assertTrue(tagAlice.isNotEmpty())

        val isValidBob = CryptoManager.verifyAuthTag(bobDerived, challenge, tagAlice)
        assertTrue("Bob must verify Alice's auth tag with derived session key", isValidBob)

        val isInvalid = CryptoManager.verifyAuthTag(bobDerived, "tampered-challenge", tagAlice)
        assertFalse("Auth tag verification must reject tampered challenge", isInvalid)
    }

    @Test
    fun testAesGcmEncryptionDecryptionRoundTrip() {
        val key = ByteArray(32) { (it * 7).toByte() }
        val plaintext = "Hello Continuity Secure Transport!".toByteArray(Charsets.UTF_8)

        val combined = CryptoManager.encrypt(plaintext, key)
        assertTrue("Ciphertext must include 12 bytes IV + data + 16 bytes tag", combined.size >= plaintext.size + 28)

        val decrypted = CryptoManager.decrypt(combined, key)
        assertArrayEquals(plaintext, decrypted)
        assertEquals("Hello Continuity Secure Transport!", String(decrypted, Charsets.UTF_8))
    }

    @Test
    fun testSha256Hex() {
        val input = "The quick brown fox jumps over the lazy dog".toByteArray(Charsets.UTF_8)
        val expected = "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592"
        assertEquals(expected, CryptoManager.sha256Hex(input))
    }

    @Test
    fun testPairingPinGeneration() {
        for (i in 0 until 50) {
            val pin = CryptoManager.generatePairingPin()
            assertEquals(6, pin.length)
            val num = pin.toIntOrNull()
            assertNotNull(num)
            assertTrue(num!! in 100000..999999)
        }
    }
}
