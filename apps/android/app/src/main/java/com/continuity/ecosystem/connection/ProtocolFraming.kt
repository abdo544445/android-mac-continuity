package com.continuity.ecosystem.connection

import com.continuity.ecosystem.core.ContinuityEnvelope
import com.google.gson.Gson
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

const val FLAG_JSON_ENVELOPE: Byte = 0x00
const val FLAG_BINARY_CHUNK: Byte = 0x01

data class RawBinaryChunk(
    val transferId: String,
    val chunkIndex: Int,
    val chunkTotal: Int,
    val data: ByteArray
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false
        other as RawBinaryChunk
        return transferId == other.transferId &&
                chunkIndex == other.chunkIndex &&
                chunkTotal == other.chunkTotal &&
                data.contentEquals(other.data)
    }

    override fun hashCode(): Int {
        var result = transferId.hashCode()
        result = 31 * result + chunkIndex
        result = 31 * result + chunkTotal
        result = 31 * result + data.contentHashCode()
        return result
    }
}

sealed class DecodedFrame {
    data class Envelope(val envelope: ContinuityEnvelope) : DecodedFrame()
    data class BinaryChunk(val chunk: RawBinaryChunk) : DecodedFrame()
}

object ProtocolFraming {
    private val MAGIC = byteArrayOf(0x43.toByte(), 0x4E.toByte(), 0x54.toByte(), 0x31.toByte()) // "CNT1"
    private val gson = Gson()

    fun writeEnvelope(output: OutputStream, envelope: ContinuityEnvelope) {
        val jsonBytes = gson.toJson(envelope).toByteArray(Charsets.UTF_8)
        val frame = ByteArrayOutputStream()

        frame.write(MAGIC)
        frame.write(FLAG_JSON_ENVELOPE.toInt()) // flags: 0x00
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

    fun writeBinaryChunk(output: OutputStream, chunk: RawBinaryChunk) {
        val idBytes = ByteArray(36)
        val srcBytes = chunk.transferId.toByteArray(Charsets.UTF_8)
        System.arraycopy(srcBytes, 0, idBytes, 0, minOf(srcBytes.size, 36))

        val payloadLen = 36 + 4 + 4 + chunk.data.size
        val headerBuf = ByteBuffer.allocate(12).order(ByteOrder.BIG_ENDIAN)
        headerBuf.put(MAGIC)
        headerBuf.put(FLAG_BINARY_CHUNK)
        headerBuf.put(0x00.toByte()) // encMode
        headerBuf.putShort(0.toShort()) // reserved
        headerBuf.putInt(payloadLen)

        val metaBuf = ByteBuffer.allocate(44).order(ByteOrder.BIG_ENDIAN)
        metaBuf.put(idBytes)
        metaBuf.putInt(chunk.chunkIndex)
        metaBuf.putInt(chunk.chunkTotal)

        output.write(headerBuf.array())
        output.write(metaBuf.array())
        output.write(chunk.data)
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

    fun readFrame(input: InputStream): DecodedFrame? {
        val magicBuf = ByteArray(4)
        if (!readFully(input, magicBuf)) return null
        if (!magicBuf.contentEquals(MAGIC)) return null

        val headerBuf = ByteArray(4)
        if (!readFully(input, headerBuf)) return null
        val flags = headerBuf[0]

        val lengthBuf = ByteArray(4)
        if (!readFully(input, lengthBuf)) return null
        val length = ByteBuffer.wrap(lengthBuf).order(ByteOrder.BIG_ENDIAN).int

        if (length <= 0 || length > 16 * 1024 * 1024) {
            return null
        }

        if (flags == FLAG_BINARY_CHUNK) {
            if (length < 44) return null
            val metaBuf = ByteArray(44)
            if (!readFully(input, metaBuf)) return null

            val idStr = String(metaBuf, 0, 36, Charsets.UTF_8).trim('\u0000', ' ')
            val metaWrap = ByteBuffer.wrap(metaBuf).order(ByteOrder.BIG_ENDIAN)
            metaWrap.position(36)
            val chunkIdx = metaWrap.int
            val chunkTot = metaWrap.int

            val dataLen = length - 44
            val dataBuf = ByteArray(dataLen)
            if (!readFully(input, dataBuf)) return null

            return DecodedFrame.BinaryChunk(RawBinaryChunk(idStr, chunkIdx, chunkTot, dataBuf))
        } else {
            val payload = ByteArray(length)
            if (!readFully(input, payload)) return null
            val jsonStr = String(payload, Charsets.UTF_8)
            val env = gson.fromJson(jsonStr, ContinuityEnvelope::class.java)
            return DecodedFrame.Envelope(env)
        }
    }

    fun readEnvelope(input: InputStream): ContinuityEnvelope? {
        return when (val frame = readFrame(input)) {
            is DecodedFrame.Envelope -> frame.envelope
            else -> null
        }
    }
}
