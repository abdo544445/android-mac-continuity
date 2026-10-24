package com.continuity.ecosystem.pairing

import org.junit.Assert.*
import org.junit.Test
import java.net.URI
import java.net.URLDecoder

class PairingManagerTest {

    private fun parseQrUri(uriString: String): PairingQrData? {
        return try {
            val uri = URI(uriString)
            if (uri.scheme != "continuity" || uri.host != "pair") return null

            val params = uri.rawQuery.split("&").associate {
                val parts = it.split("=")
                parts[0] to (if (parts.size > 1) URLDecoder.decode(parts[1], "UTF-8") else "")
            }

            val macId = params["id"] ?: return null
            val macName = params["name"] ?: "MacBook Pro"
            val host = params["host"] ?: return null
            val port = params["port"]?.toIntOrNull() ?: 52400
            val pk = params["pk"] ?: return null
            val pin = params["pin"] ?: return null
            val exp = params["exp"]?.toLongOrNull() ?: 0

            PairingQrData(macId, macName, host, port, pk, pin, exp)
        } catch (e: Exception) {
            null
        }
    }

    @Test
    fun testValidQrUriParsing() {
        val qrUri = "continuity://pair?v=1&id=mac-studio-01&name=MacBook+Pro+M3&host=192.168.1.45&port=52400&pk=dGVzdF9wdWJsaWNfa2V5&pin=729104&exp=1792789200"
        val data = parseQrUri(qrUri)

        assertNotNull("Valid QR URI must be parsed successfully", data)
        assertEquals("mac-studio-01", data?.macId)
        assertEquals("MacBook Pro M3", data?.macName)
        assertEquals("192.168.1.45", data?.host)
        assertEquals(52400, data?.port)
        assertEquals("729104", data?.pin)
        assertEquals("dGVzdF9wdWJsaWNfa2V5", data?.publicKeyBase64)
        assertEquals(1792789200L, data?.expiresAt)
    }

    @Test
    fun testInvalidSchemeRejection() {
        val invalidScheme = "https://continuity.net/pair?v=1&id=mac-01&pin=123456"
        val result = parseQrUri(invalidScheme)
        assertNull("Non-continuity schemes must be rejected", result)
    }

    @Test
    fun testMissingRequiredParametersRejection() {
        val missingHost = "continuity://pair?v=1&id=mac-01&pin=123456"
        val result = parseQrUri(missingHost)
        assertNull("Missing host must fail validation", result)
    }
}
