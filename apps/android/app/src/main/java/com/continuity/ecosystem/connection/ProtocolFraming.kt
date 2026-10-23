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

    fun readEnvelope(input: InputStream): ContinuityEnvelope? {
        val magicBuf = ByteArray(4)
        var read = 0
        while (read < 4) {
            val r = input.read(magicBuf, read, 4 - read)
            if (r == -1) return null
            read += r
        }

        if (!magicBuf.contentEquals(MAGIC)) {
            return null
        }

        // Read 4 header bytes (flags, encMode, 2 reserved)
        val headerBuf = ByteArray(4)
        input.read(headerBuf)

        // Read 4 bytes length
        val lengthBuf = ByteArray(4)
        input.read(lengthBuf)
        val length = ByteBuffer.wrap(lengthBuf).order(ByteOrder.BIG_ENDIAN).int

        if (length <= 0 || length > 16 * 1024 * 1024) {
            return null
        }

        val payload = ByteArray(length)
        var totalRead = 0
        while (totalRead < length) {
            val r = input.read(payload, totalRead, length - totalRead)
            if (r == -1) return null
            totalRead += r
        }

        val jsonStr = String(payload, Charsets.UTF_8)
        return gson.fromJson(jsonStr, ContinuityEnvelope::class.java)
    }
}
