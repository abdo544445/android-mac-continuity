package com.continuity.ecosystem.core

import org.junit.Assert.*
import org.junit.Test
import java.security.KeyPairGenerator
import java.security.MessageDigest
import java.security.SecureRandom
import java.security.spec.ECGenParameterSpec
import javax.crypto.Cipher
import javax.crypto.KeyAgreement
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

class DeviceIdentityTest {

    @Test
    fun testSha256Checksum() {
        val testString = "The quick brown fox jumps over the lazy dog"
        val expected = "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592"

        val md = MessageDigest.getInstance("SHA-256")
        val digest = md.digest(testString.toByteArray(Charsets.UTF_8))
        val actual = digest.joinToString("") { "%02x".format(it) }

        assertEquals(expected, actual)
    }

    @Test
    fun testEcdhKeyAgreementAndAuthTag() {
        val kpg = KeyPairGenerator.getInstance("EC")
        kpg.initialize(ECGenParameterSpec("secp256r1"))

        val aliceKeyPair = kpg.generateKeyPair()
        val bobKeyPair = kpg.generateKeyPair()
        val pin = "849201"

        // Alice derives secret using Bob's public key
        val aliceKa = KeyAgreement.getInstance("ECDH")
        aliceKa.init(aliceKeyPair.private)
        aliceKa.doPhase(bobKeyPair.public, true)
        val aliceSharedSecret = aliceKa.generateSecret()

        // Bob derives secret using Alice's public key
        val bobKa = KeyAgreement.getInstance("ECDH")
        bobKa.init(bobKeyPair.private)
        bobKa.doPhase(aliceKeyPair.public, true)
        val bobSharedSecret = bobKa.generateSecret()

        assertArrayEquals("ECDH shared secrets must match exactly", aliceSharedSecret, bobSharedSecret)

        // Derive session key using PIN as salt
        val md = MessageDigest.getInstance("SHA-256")
        val salt = md.digest(pin.toByteArray(Charsets.UTF_8))

        val aliceMac = Mac.getInstance("HmacSHA256").apply {
            init(SecretKeySpec(salt, "HmacSHA256"))
        }
        val aliceSessionKey = aliceMac.doFinal(aliceSharedSecret)

        val bobMac = Mac.getInstance("HmacSHA256").apply {
            init(SecretKeySpec(salt, "HmacSHA256"))
        }
        val bobSessionKey = bobMac.doFinal(bobSharedSecret)

        assertArrayEquals("Derived session keys must match", aliceSessionKey, bobSessionKey)

        // Verify mutual authentication tag
        val challenge = "verify-challenge-token"
        val aliceAuthMac = Mac.getInstance("HmacSHA256").apply {
            init(SecretKeySpec(aliceSessionKey, "HmacSHA256"))
        }
        val tag = aliceAuthMac.doFinal(challenge.toByteArray(Charsets.UTF_8))

        val bobAuthMac = Mac.getInstance("HmacSHA256").apply {
            init(SecretKeySpec(bobSessionKey, "HmacSHA256"))
        }
        val bobTag = bobAuthMac.doFinal(challenge.toByteArray(Charsets.UTF_8))

        assertArrayEquals("Auth tags must be identical across peers", tag, bobTag)
    }

    @Test
    fun testAesGcmEncryptionDecryption() {
        val key = ByteArray(32).also { SecureRandom().nextBytes(it) }
        val plaintext = "Continuity payload secret string for cross-device transport".toByteArray(Charsets.UTF_8)
        val iv = ByteArray(12).also { SecureRandom().nextBytes(it) }

        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, iv))
        val ciphertext = cipher.doFinal(plaintext)

        assertFalse(plaintext.contentEquals(ciphertext))

        val decryptCipher = Cipher.getInstance("AES/GCM/NoPadding")
        decryptCipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, iv))
        val decrypted = decryptCipher.doFinal(ciphertext)

        assertArrayEquals(plaintext, decrypted)
    }
}
