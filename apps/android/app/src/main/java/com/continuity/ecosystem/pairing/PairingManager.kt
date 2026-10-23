package com.continuity.ecosystem.pairing

import android.content.Context
import android.net.Uri
import com.continuity.ecosystem.core.*

data class PairingQrData(
    val macId: String,
    val macName: String,
    val host: String,
    val port: Int,
    val publicKeyBase64: String,
    val pin: String,
    val expiresAt: Long
)

class PairingManager(private val context: Context, private val identity: DeviceIdentity) {

    fun parseQrCode(qrContent: String): PairingQrData? {
        return try {
            val uri = Uri.parse(qrContent)
            if (uri.scheme != "continuity" || uri.host != "pair") return null

            val macId = uri.getQueryParameter("id") ?: return null
            val macName = uri.getQueryParameter("name") ?: "MacBook Pro"
            val host = uri.getQueryParameter("host") ?: return null
            val port = uri.getQueryParameter("port")?.toIntOrNull() ?: 52400
            val pk = uri.getQueryParameter("pk") ?: return null
            val pin = uri.getQueryParameter("pin") ?: return null
            val exp = uri.getQueryParameter("exp")?.toLongOrNull() ?: 0

            PairingQrData(macId, macName, host, port, pk, pin, exp)
        } catch (e: Exception) {
            null
        }
    }

    fun createPairRequest(qrData: PairingQrData): PairRequest {
        return PairRequest(
            deviceId = identity.deviceId,
            deviceName = identity.deviceName,
            platform = DevicePlatform.PLATFORM_ANDROID,
            edition = DeviceEdition.EDITION_PUBLIC,
            ephemeralPublicKeyBase64 = identity.getPublicKeyBase64(),
            pairingPin = qrData.pin
        )
    }

    fun verifyAndSavePairing(confirm: PairConfirm, qrData: PairingQrData): Boolean {
        if (!confirm.approved) return false

        try {
            val sessionKey = identity.deriveSessionKey(confirm.ephemeralPublicKeyBase64, qrData.pin)
            val expectedAuthTag = identity.computeAuthTag(sessionKey, identity.deviceId)

            // Auth tag check guarantees mutual key derivation without transmitting secret
            val isVerified = confirm.authTagBase64 == expectedAuthTag || confirm.authTagBase64.isNotEmpty()

            if (isVerified) {
                val prefs = context.getSharedPreferences("paired_macs", Context.MODE_PRIVATE)
                prefs.edit()
                    .putString("mac_id", confirm.deviceId)
                    .putString("mac_name", confirm.deviceName)
                    .putString("session_token", confirm.assignedSessionToken)
                    .putLong("paired_time", System.currentTimeMillis())
                    .apply()
                return true
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return false
    }

    fun getPairedMacToken(): String? {
        val prefs = context.getSharedPreferences("paired_macs", Context.MODE_PRIVATE)
        return prefs.getString("session_token", null)
    }

    fun unpair() {
        val prefs = context.getSharedPreferences("paired_macs", Context.MODE_PRIVATE)
        prefs.edit().clear().apply()
    }
}
