package com.continuity.ecosystem.clipboard

import com.continuity.ecosystem.core.ClipboardDataType
import com.continuity.ecosystem.core.ClipboardOffer
import com.continuity.ecosystem.core.ClipboardPayload
import org.junit.Assert.*
import org.junit.Test
import java.util.Base64

class ClipboardSyncManagerTest {

    @Test
    fun testTextClipboardPayloadEncoding() {
        val testString = "Hello from Android to Mac!"
        val encoded = Base64.getEncoder().encodeToString(testString.toByteArray(Charsets.UTF_8))

        val payload = ClipboardPayload(
            clipId = "clip-001",
            dataBase64 = encoded,
            mimeType = "text/plain"
        )

        assertEquals("clip-001", payload.clipId)
        assertEquals("text/plain", payload.mimeType)

        val decodedBytes = Base64.getDecoder().decode(payload.dataBase64)
        val decodedString = String(decodedBytes, Charsets.UTF_8)
        assertEquals(testString, decodedString)
    }

    @Test
    fun testImageClipboardPayloadMimeType() {
        val fakePngBytes = byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
        val encoded = Base64.getEncoder().encodeToString(fakePngBytes)

        val payload = ClipboardPayload(
            clipId = "clip-img-002",
            dataBase64 = encoded,
            mimeType = "image/png"
        )

        assertTrue(payload.mimeType.startsWith("image/"))
        val decoded = Base64.getDecoder().decode(payload.dataBase64)
        assertArrayEquals(fakePngBytes, decoded)
    }

    @Test
    fun testClipboardOfferMetadata() {
        val offer = ClipboardOffer(
            clipId = "offer-123",
            dataType = ClipboardDataType.CLIP_TEXT,
            contentLength = 42L,
            isSensitive = false,
            textPreview = "Top Secret"
        )

        assertEquals("offer-123", offer.clipId)
        assertEquals(ClipboardDataType.CLIP_TEXT, offer.dataType)
        assertEquals(42L, offer.contentLength)
        assertFalse(offer.isSensitive)
    }
}
