package com.continuity.ecosystem.core

import android.content.Context
import android.os.Build
import com.continuity.ecosystem.security.CryptoManager
import com.continuity.ecosystem.security.KeyPairWrapper

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

    private var ephemeralKeyPair: KeyPairWrapper = CryptoManager.generateKeyPair()

    fun getPublicKeyBase64(): String = ephemeralKeyPair.publicKeyBase64

    fun regenerateEphemeralKeys(): String {
        ephemeralKeyPair = CryptoManager.generateKeyPair()
        return ephemeralKeyPair.publicKeyBase64
    }

    fun deriveSessionKey(remotePublicKeyBase64: String, pin: String): ByteArray {
        return CryptoManager.deriveSessionKey(ephemeralKeyPair.privateKey, remotePublicKeyBase64, pin)
    }

    fun computeAuthTag(sessionKey: ByteArray, challenge: String): String {
        return CryptoManager.computeAuthTag(sessionKey, challenge)
    }

    fun sha256Hex(data: ByteArray): String {
        return CryptoManager.sha256Hex(data)
    }

    fun encryptAesGcm(plaintext: ByteArray, keyBytes: ByteArray): ByteArray {
        return CryptoManager.encrypt(plaintext, keyBytes)
    }

    fun decryptAesGcm(combined: ByteArray, keyBytes: ByteArray): ByteArray {
        return CryptoManager.decrypt(combined, keyBytes)
    }
}
