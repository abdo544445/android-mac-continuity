package com.continuity.ecosystem.core

import android.content.Context
import android.os.Build
import android.util.Base64
import java.security.*
import java.security.spec.ECGenParameterSpec
import java.security.spec.X509EncodedKeySpec
import javax.crypto.Cipher
import javax.crypto.KeyAgreement
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

class DeviceIdentity(private val context: Context) {

    val deviceId: String by lazy {
        val prefs = context.getSharedPreferences("continuity_identity", Context.MODE_PRIVATE)
        var id = prefs.getString("device_id", null)
        if (id == null) {
            id = "android-" + java.util.UUID.randomUUID().toString().take(8)
            prefs.edit().putString("device_id", id).apply()
        }
        id
    }

    val deviceName: String
        get() = "${Build.MANUFACTURER.replaceFirstChar { it.uppercase() }} ${Build.MODEL}"

    private var ephemeralKeyPair: KeyPair = generateEphemeralKeyPair()

    fun getPublicKeyBase64(): String {
        return Base64.encodeToString(ephemeralKeyPair.public.encoded, Base64.NO_WRAP)
    }

    fun regenerateEphemeralKeys(): String {
        ephemeralKeyPair = generateEphemeralKeyPair()
        return getPublicKeyBase64()
    }

    private fun generateEphemeralKeyPair(): KeyPair {
        val kpg = KeyPairGenerator.getInstance("EC")
        kpg.initialize(ECGenParameterSpec("secp256r1"))
        return kpg.generateKeyPair()
    }

    fun deriveSessionKey(remotePublicKeyBase64: String, pin: String): ByteArray {
        val remoteBytes = Base64.decode(remotePublicKeyBase64, Base64.NO_WRAP)
        val kf = KeyFactory.getInstance("EC")
        val remotePublicKey = kf.generatePublic(X509EncodedKeySpec(remoteBytes))

        val ka = KeyAgreement.getInstance("ECDH")
        ka.init(ephemeralKeyPair.private)
        ka.doPhase(remotePublicKey, true)
        val sharedSecret = ka.generateSecret()

        // Salt with SHA-256 of PIN
        val md = MessageDigest.getInstance("SHA-256")
        val salt = md.digest(pin.toByteArray(Charsets.UTF_8))

        // Simple HKDF extract/expand simulation for 256-bit AES key
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(salt, "HmacSHA256"))
        return mac.doFinal(sharedSecret)
    }

    fun computeAuthTag(sessionKey: ByteArray, challenge: String): String {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(sessionKey, "HmacSHA256"))
        val tag = mac.doFinal(challenge.toByteArray(Charsets.UTF_8))
        return Base64.encodeToString(tag, Base64.NO_WRAP)
    }

    fun sha256Hex(data: ByteArray): String {
        val md = MessageDigest.getInstance("SHA-256")
        val digest = md.digest(data)
        return digest.joinToString("") { "%02x".format(it) }
    }

    fun encryptAesGcm(plaintext: ByteArray, keyBytes: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        val iv = ByteArray(12).also { SecureRandom().nextBytes(it) }
        val key = SecretKeySpec(keyBytes, "AES")
        val spec = GCMParameterSpec(128, iv)
        cipher.init(Cipher.ENCRYPT_MODE, key, spec)
        val ciphertext = cipher.doFinal(plaintext)
        return iv + ciphertext
    }

    fun decryptAesGcm(combined: ByteArray, keyBytes: ByteArray): ByteArray {
        val iv = combined.copyOfRange(0, 12)
        val ciphertext = combined.copyOfRange(12, combined.size)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        val key = SecretKeySpec(keyBytes, "AES")
        val spec = GCMParameterSpec(128, iv)
        cipher.init(Cipher.DECRYPT_MODE, key, spec)
        return cipher.doFinal(ciphertext)
    }
}
