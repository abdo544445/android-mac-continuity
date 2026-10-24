package com.continuity.ecosystem.connection

import com.continuity.ecosystem.core.ContinuityEnvelope
import com.google.gson.Gson
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

object ProtocolFraming {
    private val MAGIC = byteArrayOf(0x43.toByte(), 0x4E.toByte(), 0x54.toByte(), 0x31.toByte()) // "CNT1"
    private val gson = Gson()

    fun writeEnvelope(output: OutputStream, envelope: ContinuityEnvelope) {
        val jsonBytes = gson.toJson(envelope).toByteArray(Charsets.UTF_8)
        val frame = ByteArrayOutputStream()

        frame.write(MAGIC)
        frame.write(0x00) // flags
        frame.write(0x00) // encMode: Plain JSON
        frame.write(0x00) // reserved 1
        frame.write(0x00) // reserved 2

        val lengthBuf = ByteBuffer.allocate(4).order(ByteOrder.BIG_ENDIAN)
        lengthBuf.putInt(jsonBytes.size)
        frame.write(lengthBuf.array())

        frame.write(jsonBytes)
        output.write(frame.toByteArray())
        output.flush()
    }

    private fun readFully(input: InputStream, buffer: ByteArray): Boolean {
        var offset = 0
        while (offset < buffer.size) {
            val bytesRead = input.read(buffer, offset, buffer.size - offset)
            if (bytesRead == -1) return false
            offset += bytesRead
        }
        return true
    }

    fun readEnvelope(input: InputStream): ContinuityEnvelope? {
        val magicBuf = ByteArray(4)
        if (!readFully(input, magicBuf)) return null
        if (!magicBuf.contentEquals(MAGIC)) return null

        // Read 4 header bytes (flags, encMode, 2 reserved)
        val headerBuf = ByteArray(4)
        if (!readFully(input, headerBuf)) return null

        // Read 4 bytes length
        val lengthBuf = ByteArray(4)
        if (!readFully(input, lengthBuf)) return null
        val length = ByteBuffer.wrap(lengthBuf).order(ByteOrder.BIG_ENDIAN).int

        if (length <= 0 || length > 16 * 1024 * 1024) {
            return null
        }

        val payload = ByteArray(length)
        if (!readFully(input, payload)) return null

        val jsonStr = String(payload, Charsets.UTF_8)
        return gson.fromJson(jsonStr, ContinuityEnvelope::class.java)
    }
}
