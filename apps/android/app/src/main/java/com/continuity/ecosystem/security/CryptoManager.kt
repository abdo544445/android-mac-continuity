package com.continuity.ecosystem.security

import java.math.BigInteger
import java.security.*
import java.security.interfaces.ECPublicKey
import java.security.spec.*
import javax.crypto.Cipher
import javax.crypto.KeyAgreement
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

data class KeyPairWrapper(
    val privateKey: PrivateKey,
    val publicKey: PublicKey,
    val publicKeyBase64: String
)

object CryptoManager {

    private val ecParameterSpec: ECParameterSpec by lazy {
        val kpg = KeyPairGenerator.getInstance("EC")
        kpg.initialize(ECGenParameterSpec("secp256r1"))
        val kp = kpg.generateKeyPair()
        (kp.public as ECPublicKey).params
    }

    private fun base64Encode(bytes: ByteArray): String {
        return java.util.Base64.getEncoder().encodeToString(bytes)
    }

    private fun base64Decode(str: String): ByteArray {
        return java.util.Base64.getDecoder().decode(str.trim())
    }

    /**
     * Generates a new ephemeral ECDH P-256 (secp256r1) keypair.
     */
    fun generateKeyPair(): KeyPairWrapper {
        val kpg = KeyPairGenerator.getInstance("EC")
        kpg.initialize(ECGenParameterSpec("secp256r1"))
        val kp = kpg.generateKeyPair()
        val rawPub = encodeRawPublicKey(kp.public)
        val pubB64 = base64Encode(rawPub)
        return KeyPairWrapper(kp.private, kp.public, pubB64)
    }

    /**
     * Encodes EC public key as 64-byte raw X || Y coordinates (ANSI X9.63 uncompressed without 0x04 header).
     */
    fun encodeRawPublicKey(publicKey: PublicKey): ByteArray {
        if (publicKey is ECPublicKey) {
            val x = publicKey.w.affineX.toByteArray()
            val y = publicKey.w.affineY.toByteArray()
            val out = ByteArray(64)

            val xSrcOffset = if (x.size > 32) x.size - 32 else 0
            val xDestOffset = if (x.size < 32) 32 - x.size else 0
            val xLen = minOf(32, x.size - xSrcOffset)
            System.arraycopy(x, xSrcOffset, out, xDestOffset, xLen)

            val ySrcOffset = if (y.size > 32) y.size - 32 else 0
            val yDestOffset = if (y.size < 32) 32 + (32 - y.size) else 32
            val yLen = minOf(32, y.size - ySrcOffset)
            System.arraycopy(y, ySrcOffset, out, yDestOffset, yLen)

            return out
        }
        return publicKey.encoded
    }

    /**
     * Decodes an EC P-256 public key from 64-byte raw coordinates, 65-byte uncompressed X9.62, or X.509 DER bytes.
     */
    fun decodePublicKey(bytes: ByteArray): PublicKey {
        val kf = KeyFactory.getInstance("EC")
        return when {
            bytes.size == 64 -> {
                val x = BigInteger(1, bytes.copyOfRange(0, 32))
                val y = BigInteger(1, bytes.copyOfRange(32, 64))
                val point = ECPoint(x, y)
                val spec = ECPublicKeySpec(point, ecParameterSpec)
                kf.generatePublic(spec)
            }
            bytes.size == 65 && bytes[0] == 0x04.toByte() -> {
                val x = BigInteger(1, bytes.copyOfRange(1, 33))
                val y = BigInteger(1, bytes.copyOfRange(33, 65))
                val point = ECPoint(x, y)
                val spec = ECPublicKeySpec(point, ecParameterSpec)
                kf.generatePublic(spec)
            }
            else -> {
                kf.generatePublic(X509EncodedKeySpec(bytes))
            }
        }
    }

    /**
     * Derives a 32-byte (256-bit) AES-GCM session key using ECDH P-256 + HKDF-SHA256 (RFC 5869).
     */
    fun deriveSessionKey(
        localPrivateKey: PrivateKey,
        remotePublicKeyBase64: String,
        pin: String
    ): ByteArray {
        val remoteBytes = base64Decode(remotePublicKeyBase64)
        val remotePublicKey = decodePublicKey(remoteBytes)

        val ka = KeyAgreement.getInstance("ECDH")
        ka.init(localPrivateKey)
        ka.doPhase(remotePublicKey, true)
        val sharedSecret = ka.generateSecret()

        // Salt with SHA-256 of visual PIN
        val md = MessageDigest.getInstance("SHA-256")
        val pinSalt = md.digest(pin.toByteArray(Charsets.UTF_8))
        val info = "continuity-v1-session-key".toByteArray(Charsets.UTF_8)

        return hkdf(salt = pinSalt, ikm = sharedSecret, info = info, length = 32)
    }

    /**
     * Computes RFC 5869 HKDF-SHA256 key material.
     */
    fun hkdf(salt: ByteArray, ikm: ByteArray, info: ByteArray, length: Int = 32): ByteArray {
        val prk = hkdfExtract(salt, ikm)
        return hkdfExpand(prk, info, length)
    }

    fun hkdfExtract(salt: ByteArray, ikm: ByteArray): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(salt, "HmacSHA256"))
        return mac.doFinal(ikm)
    }

    fun hkdfExpand(prk: ByteArray, info: ByteArray, length: Int): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(prk, "HmacSHA256"))
        mac.update(info)
        mac.update(0x01.toByte())
        val t1 = mac.doFinal()
        return t1.copyOfRange(0, length)
    }

    /**
     * Calculates HMAC-SHA256 authentication tag confirming key derivation.
     */
    fun computeAuthTag(sessionKey: ByteArray, challenge: String): String {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(sessionKey, "HmacSHA256"))
        val tag = mac.doFinal(challenge.toByteArray(Charsets.UTF_8))
        return base64Encode(tag)
    }

    /**
     * Verifies HMAC-SHA256 authentication tag.
     */
    fun verifyAuthTag(sessionKey: ByteArray, challenge: String, expectedTagBase64: String): Boolean {
        val computed = computeAuthTag(sessionKey, challenge)
        return MessageDigest.isEqual(
            base64Decode(computed),
            base64Decode(expectedTagBase64)
        )
    }

    /**
     * Computes lowercase hex-encoded SHA-256 digest.
     */
    fun sha256Hex(data: ByteArray): String {
        val md = MessageDigest.getInstance("SHA-256")
        val digest = md.digest(data)
        return digest.joinToString("") { "%02x".format(it) }
    }

    /**
     * Generates a cryptographically random 6-digit numeric pairing PIN.
     */
    fun generatePairingPin(): String {
        val secureRandom = SecureRandom()
        val pin = 100000 + secureRandom.nextInt(900000)
        return pin.toString()
    }

    /**
     * Encrypts plaintext using AES-256-GCM, prepending 12-byte IV (matches CryptoKit SealedBox.combined).
     */
    fun encrypt(plaintext: ByteArray, sessionKey: ByteArray): ByteArray {
        val iv = ByteArray(12).also { SecureRandom().nextBytes(it) }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        val spec = GCMParameterSpec(128, iv)
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(sessionKey, "AES"), spec)
        val ciphertextAndTag = cipher.doFinal(plaintext)
        return iv + ciphertextAndTag
    }

    /**
     * Decrypts combined IV (12 bytes) + Ciphertext + Tag (16 bytes) using AES-256-GCM.
     */
    fun decrypt(combined: ByteArray, sessionKey: ByteArray): ByteArray {
        require(combined.size >= 28) { "Ciphertext buffer too short (< 28 bytes)" }
        val iv = combined.copyOfRange(0, 12)
        val ciphertextAndTag = combined.copyOfRange(12, combined.size)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        val spec = GCMParameterSpec(128, iv)
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(sessionKey, "AES"), spec)
        return cipher.doFinal(ciphertextAndTag)
    }
}
