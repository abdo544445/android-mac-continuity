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
            val trimmed = qrContent.trim()
            val uri = Uri.parse(trimmed)
            if (uri.scheme != "continuity" || uri.host != "pair") return null

            val macId = uri.getQueryParameter("id") ?: "mac-host"
            val macName = uri.getQueryParameter("name") ?: "Mac"
            val host = uri.getQueryParameter("host") ?: return null
            val port = uri.getQueryParameter("port")?.toIntOrNull() ?: 52400
            // Restore '+' if it was decoded as space by Uri.getQueryParameter
            val pk = (uri.getQueryParameter("pk") ?: "").replace(" ", "+")
            val pin = uri.getQueryParameter("pin") ?: "000000"
            val exp = uri.getQueryParameter("exp")?.toLongOrNull() ?: 0

            if (pk.isEmpty()) return null

            PairingQrData(macId, macName, host, port, pk, pin, exp)
        } catch (e: Exception) {
            null
        }
    }

    /**
     * Parses either a full `continuity://pair?...` QR URI or a manual `host[:port]` IP string.
     */
    fun parseInputOrIp(input: String): PairingQrData? {
        val trimmed = input.trim()
        if (trimmed.startsWith("continuity://")) {
            return parseQrCode(trimmed)
        }

        // Support manual IP or host:port entry (e.g., "192.168.1.41" or "192.168.1.41:52400")
        val parts = trimmed.split(":")
        val host = parts[0].trim()
        if (host.isEmpty() || host.contains("/")) return null
        val port = if (parts.size > 1) parts[1].trim().toIntOrNull() ?: 52400 else 52400

        return PairingQrData(
            macId = "mac-$host",
            macName = "Mac ($host)",
            host = host,
            port = port,
            publicKeyBase64 = identity.getPublicKeyBase64(),
            pin = "000000",
            expiresAt = System.currentTimeMillis() / 1000 + 300
        )
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
            savePairedMacInfo(
                macId = confirm.deviceId.ifEmpty { qrData.macId },
                macName = confirm.deviceName.ifEmpty { qrData.macName },
                host = qrData.host,
                port = qrData.port,
                sessionToken = confirm.assignedSessionToken
            )
            return true
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return false
    }

    fun savePairedMacInfo(
        macId: String,
        macName: String,
        host: String,
        port: Int,
        sessionToken: String
    ) {
        val prefs = context.getSharedPreferences("paired_macs", Context.MODE_PRIVATE)
        val editor = prefs.edit()
            .putString("mac_id", macId)
            .putString("mac_name", macName)
            .putString("mac_host", host)
            .putInt("mac_port", port)
            .putLong("paired_time", System.currentTimeMillis())
        if (sessionToken.isNotEmpty()) {
            editor.putString("session_token", sessionToken)
        }
        editor.apply()
    }

    fun getPairedMacName(): String {
        val prefs = context.getSharedPreferences("paired_macs", Context.MODE_PRIVATE)
        return prefs.getString("mac_name", "") ?: ""
    }

    fun getPairedMacHost(): String? {
        val prefs = context.getSharedPreferences("paired_macs", Context.MODE_PRIVATE)
        return prefs.getString("mac_host", null)
    }

    fun getPairedMacPort(): Int {
        val prefs = context.getSharedPreferences("paired_macs", Context.MODE_PRIVATE)
        return prefs.getInt("mac_port", 52400)
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
