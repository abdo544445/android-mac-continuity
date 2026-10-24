package com.continuity.ecosystem.connection

import com.continuity.ecosystem.core.ContinuityEnvelope
import com.continuity.ecosystem.core.Heartbeat
import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.InputStream

class ProtocolFramingTest {

    @Test
    fun testEnvelopeFramingRoundTrip() {
        val originalEnvelope = ContinuityEnvelope(
            senderDeviceId = "android-test-device",
            heartbeat = Heartbeat(sequenceNumber = 42, timestampMs = 1729000000000L)
        )

        val output = ByteArrayOutputStream()
        ProtocolFraming.writeEnvelope(output, originalEnvelope)

        val frameBytes = output.toByteArray()
        assertTrue("Frame must be at least 12 bytes header + payload", frameBytes.size > 12)

        // Check magic bytes "CNT1"
        assertEquals(0x43.toByte(), frameBytes[0]) // 'C'
        assertEquals(0x4E.toByte(), frameBytes[1]) // 'N'
        assertEquals(0x54.toByte(), frameBytes[2]) // 'T'
        assertEquals(0x31.toByte(), frameBytes[3]) // '1'

        val input = ByteArrayInputStream(frameBytes)
        val decodedEnvelope = ProtocolFraming.readEnvelope(input)

        assertNotNull(decodedEnvelope)
        assertEquals("android-test-device", decodedEnvelope?.senderDeviceId)
        assertEquals(42L, decodedEnvelope?.heartbeat?.sequenceNumber)
    }

    @Test
    fun testSlicedStreamReadingWithReadFully() {
        val originalEnvelope = ContinuityEnvelope(
            senderDeviceId = "sliced-stream-device",
            heartbeat = Heartbeat(sequenceNumber = 99)
        )

        val output = ByteArrayOutputStream()
        ProtocolFraming.writeEnvelope(output, originalEnvelope)
        val frameBytes = output.toByteArray()

        // Sliced input stream that yields 1 or 2 bytes at a time (simulating TCP fragmentation)
        val fragmentedStream = object : InputStream() {
            private var index = 0
            override fun read(): Int {
                return if (index < frameBytes.size) frameBytes[index++].toInt() and 0xFF else -1
            }

            override fun read(b: ByteArray, off: Int, len: Int): Int {
                if (index >= frameBytes.size) return -1
                val bytesToRead = minOf(2, len, frameBytes.size - index) // max 2 bytes per read call
                System.arraycopy(frameBytes, index, b, off, bytesToRead)
                index += bytesToRead
                return bytesToRead
            }
        }

        val decodedEnvelope = ProtocolFraming.readEnvelope(fragmentedStream)
        assertNotNull("readFully must assemble fragmented TCP stream", decodedEnvelope)
        assertEquals("sliced-stream-device", decodedEnvelope?.senderDeviceId)
        assertEquals(99L, decodedEnvelope?.heartbeat?.sequenceNumber)
    }

    @Test
    fun testInvalidMagicRejection() {
        val corruptedBytes = byteArrayOf(0x00, 0x01, 0x02, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x05, 0x7B, 0x7D)
        val input = ByteArrayInputStream(corruptedBytes)
        val result = ProtocolFraming.readEnvelope(input)
        assertNull("Decoder must reject frames with non-matching magic bytes", result)
    }
}
