package com.continuity.ecosystem.display

import android.media.MediaCodec
import android.media.MediaFormat
import android.os.Build
import android.util.Log
import android.view.Surface
import java.util.concurrent.Executors

/**
 * Hardware-accelerated H.264 Annex-B decoder rendering directly onto a SurfaceView Surface
 * via Android MediaCodec (zero Bitmap allocation, zero GC pauses, low-latency mode).
 */
class H264SurfaceDecoder {
    private val decodeExecutor = Executors.newSingleThreadExecutor()
    private val bufferInfo = MediaCodec.BufferInfo()

    @Volatile
    private var codec: MediaCodec? = null
    @Volatile
    private var surface: Surface? = null
    @Volatile
    private var lastSpsBytes: ByteArray? = null
    @Volatile
    private var isConfigured = false

    private var presentationTimeUs = 0L

    var onVideoSizeChanged: ((width: Int, height: Int) -> Unit)? = null

    fun attachSurface(newSurface: Surface?) {
        decodeExecutor.execute {
            if (surface === newSurface) return@execute
            releaseCodecInternal()
            surface = newSurface
            lastSpsBytes = null
            isConfigured = false
        }
    }

    fun submitFrame(annexB: ByteArray, isKeyframeHint: Boolean) {
        decodeExecutor.execute {
            val targetSurface = surface ?: return@execute
            if (!targetSurface.isValid) return@execute

            val sps = extractNal(annexB, 7)
            val pps = extractNal(annexB, 8)
            val isIdr = isKeyframeHint || extractNal(annexB, 5) != null

            if (sps != null) {
                val prev = lastSpsBytes
                if (prev == null || !prev.contentEquals(sps)) {
                    // Initial setup or Mac resolution changed — (re)configure MediaCodec cleanly
                    configureCodec(targetSurface, sps, pps)
                }
            }

            if (!isConfigured) {
                // Wait for first keyframe containing SPS before feeding delta frames
                if (!isIdr || sps == null) return@execute
            }

            val activeCodec = codec ?: return@execute
            try {
                val inIdx = activeCodec.dequeueInputBuffer(10_000)
                if (inIdx >= 0) {
                    val inBuf = activeCodec.getInputBuffer(inIdx)
                    if (inBuf != null) {
                        inBuf.clear()
                        inBuf.put(annexB)
                        presentationTimeUs += 16_667L
                        val flags = if (isIdr) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0
                        activeCodec.queueInputBuffer(inIdx, 0, annexB.size, presentationTimeUs, flags)
                    }
                }

                // Drain all decoded frames immediately to keep latency minimal
                var outIdx = activeCodec.dequeueOutputBuffer(bufferInfo, 0)
                while (outIdx >= 0 || outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    if (outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                        val fmt = activeCodec.outputFormat
                        val w = fmt.getInteger(MediaFormat.KEY_WIDTH)
                        val h = fmt.getInteger(MediaFormat.KEY_HEIGHT)
                        if (w > 0 && h > 0) {
                            onVideoSizeChanged?.invoke(w, h)
                        }
                    } else if (outIdx >= 0) {
                        activeCodec.releaseOutputBuffer(outIdx, true)
                    }
                    outIdx = activeCodec.dequeueOutputBuffer(bufferInfo, 0)
                }
            } catch (e: Exception) {
                Log.w("ContinuityH264", "Decoder frame error, resetting: ${e.message}")
                releaseCodecInternal()
                lastSpsBytes = null
                isConfigured = false
            }
        }
    }

    fun release() {
        decodeExecutor.execute {
            releaseCodecInternal()
            surface = null
            lastSpsBytes = null
            isConfigured = false
        }
    }

    private fun configureCodec(targetSurface: Surface, sps: ByteArray, pps: ByteArray?) {
        releaseCodecInternal()
        try {
            val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, 2456, 1600)
            format.setByteBuffer("csd-0", java.nio.ByteBuffer.wrap(sps))
            if (pps != null) {
                format.setByteBuffer("csd-1", java.nio.ByteBuffer.wrap(pps))
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                format.setInteger(MediaFormat.KEY_LOW_LATENCY, 1)
            }
            val dec = MediaCodec.createDecoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
            dec.configure(format, targetSurface, null, 0)
            dec.start()
            codec = dec
            lastSpsBytes = sps
            isConfigured = true
            Log.w("ContinuityH264", "MediaCodec H.264 Surface decoder started")
        } catch (e: Exception) {
            Log.e("ContinuityH264", "Failed to configure MediaCodec: ${e.message}", e)
            releaseCodecInternal()
            isConfigured = false
        }
    }

    private fun releaseCodecInternal() {
        try {
            codec?.stop()
        } catch (_: Exception) {}
        try {
            codec?.release()
        } catch (_: Exception) {}
        codec = null
        isConfigured = false
    }

    /**
     * Scans an Annex-B byte stream for the first NAL unit matching [targetNalType]
     * and returns it WITH its 4-byte 00 00 00 01 start code prefix.
     */
    private fun extractNal(data: ByteArray, targetNalType: Int): ByteArray? {
        val offsets = ArrayList<Int>(4)
        var i = 0
        while (i <= data.size - 4) {
            if (data[i] == 0.toByte() && data[i + 1] == 0.toByte() &&
                data[i + 2] == 0.toByte() && data[i + 3] == 1.toByte()
            ) {
                offsets.add(i)
                i += 4
            } else {
                i++
            }
        }
        for (idx in offsets.indices) {
            val start = offsets[idx]
            val end = if (idx + 1 < offsets.size) offsets[idx + 1] else data.size
            val nalHeaderPos = start + 4
            if (nalHeaderPos < end) {
                val nalType = data[nalHeaderPos].toInt() and 0x1F
                if (nalType == targetNalType) {
                    return data.copyOfRange(start, end)
                }
            }
        }
        return null
    }
}
