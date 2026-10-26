package com.continuity.ecosystem.connection

import com.continuity.ecosystem.core.ContinuityEnvelope
import com.continuity.ecosystem.core.Heartbeat
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
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

        val fragmentedStream = object : InputStream() {
            private var index = 0
            override fun read(): Int {
                return if (index < frameBytes.size) frameBytes[index++].toInt() and 0xFF else -1
            }

            override fun read(b: ByteArray, off: Int, len: Int): Int {
                if (index >= frameBytes.size) return -1
                val bytesToRead = minOf(2, len, frameBytes.size - index)
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

    @Test
    fun testSampleEnvelopesFixtureContract() {
        val candidatePaths = listOf(
            File("../../../shared/protocol/fixtures/sample_envelopes.json"),
            File("../../shared/protocol/fixtures/sample_envelopes.json"),
            File("shared/protocol/fixtures/sample_envelopes.json")
        )
        val fixtureFile = candidatePaths.firstOrNull { it.exists() }
        assertNotNull("sample_envelopes.json fixture file must exist", fixtureFile)

        val rootJson = JsonParser.parseString(fixtureFile!!.readText()).asJsonObject
        val testCases = rootJson.getAsJsonArray("test_cases")
        assertTrue("Fixture must contain test cases", testCases.size() > 0)

        for (caseElement in testCases) {
            val caseObj = caseElement.asJsonObject
            val caseName = caseObj.get("name").asString
            val envelopeJson = caseObj.get("envelope").toString()

            val envelope = ProtocolFraming.gson.fromJson(envelopeJson, ContinuityEnvelope::class.java)
            assertNotNull("Failed to parse fixture envelope for $caseName", envelope)
            assertEquals("Protocol version must be 1 for $caseName", 1L, envelope.version)
            assertTrue("Request ID must not be empty for $caseName", envelope.requestId.isNotEmpty())

            // Round-trip through framing encoder and decoder
            val out = ByteArrayOutputStream()
            ProtocolFraming.writeEnvelope(out, envelope)

            val frameBytes = out.toByteArray()
            assertTrue("Frame bytes must be valid", frameBytes.size > 12)

            val input = ByteArrayInputStream(frameBytes)
            val roundTripped = ProtocolFraming.readEnvelope(input)

            assertNotNull("Round-tripped envelope must not be null for $caseName", roundTripped)
            assertEquals(envelope.requestId, roundTripped?.requestId)
            assertEquals(envelope.senderDeviceId, roundTripped?.senderDeviceId)

            when (caseName) {
                "PairRequest_Valid" -> {
                    assertNotNull("pairRequest payload expected", roundTripped?.pairRequest)
                    assertEquals("849201", roundTripped?.pairRequest?.pairingPin)
                    assertEquals("Alex's Pixel 9 Pro", roundTripped?.pairRequest?.deviceName)
                }
                "TransferOffer_Valid" -> {
                    assertNotNull("transferOffer payload expected", roundTripped?.transferOffer)
                    assertEquals("presentation_notes.pdf", roundTripped?.transferOffer?.fileName)
                    assertEquals(1048576L, roundTripped?.transferOffer?.fileSizeBytes)
                }
                "DeviceStatus_Valid" -> {
                    assertNotNull("deviceStatus payload expected", roundTripped?.deviceStatus)
                    assertEquals(88, roundTripped?.deviceStatus?.batteryPercentage)
                    assertTrue(roundTripped?.deviceStatus?.isCharging == true)
                    assertEquals("Home-5G", roundTripped?.deviceStatus?.wifiSsid)
                }
            }
        }
    }

    @Test
    fun testFeaturesCatalogContract() {
        val candidatePaths = listOf(
            File("../../../shared/protocol/capabilities/features.json"),
            File("../../shared/protocol/capabilities/features.json"),
            File("shared/protocol/capabilities/features.json")
        )
        val fixtureFile = candidatePaths.firstOrNull { it.exists() }
        assertNotNull("features.json fixture file must exist", fixtureFile)

        val rootJson = JsonParser.parseString(fixtureFile!!.readText()).asJsonObject
        assertEquals("ContinuityCapabilityCatalog", rootJson.get("name").asString)
        val editions = rootJson.getAsJsonObject("editions")
        assertNotNull(editions.getAsJsonObject("public"))
        assertNotNull(editions.getAsJsonObject("advanced"))
    }
}
