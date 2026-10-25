package com.continuity.ecosystem.mirroring

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.util.Log
import com.continuity.ecosystem.connection.ConnectionService
import com.continuity.ecosystem.connection.RawBinaryChunk
import com.continuity.ecosystem.core.ContinuityEnvelope
import com.continuity.ecosystem.core.SessionRequest
import com.continuity.ecosystem.core.SessionStop
import com.continuity.ecosystem.core.SessionType
import java.io.ByteArrayOutputStream

class ScreenShareService : Service() {

    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var captureThread: HandlerThread? = null
    private var captureHandler: Handler? = null
    private var lastFrameSentMs: Long = 0L
    private var frameCounter: Int = 0

    companion object {
        const val MIRROR_TRANSFER_ID = "00000000-0000-0000-0000-000000MIRROR"
        var resultCode: Int = 0
        var resultData: Intent? = null
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForegroundNotification()

        val mpManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val data = resultData
        if (data != null) {
            try {
                stopCapture()
                mediaProjection = mpManager.getMediaProjection(resultCode, data)
                startCapture(1280, 800)
            } catch (e: Exception) {
                Log.e("ContinuityDebug", "MediaProjection start failed: ${e.message}", e)
            }
        }

        return START_NOT_STICKY
    }

    private fun startCapture(width: Int, height: Int) {
        try {
            val thread = HandlerThread("ContinuityMirrorThread").also { it.start() }
            val handler = Handler(thread.looper)
            captureThread = thread
            captureHandler = handler

            // Required on Android 12/14/HarmonyOS before creating VirtualDisplay
            mediaProjection?.registerCallback(object : MediaProjection.Callback() {
                override fun onStop() {
                    stopSelf()
                }
            }, handler)

            val reader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)
            imageReader = reader

            // Notify Mac to switch to Screen Mirror tab
            ConnectionService.activeInstance?.sendEnvelope(
                ContinuityEnvelope(
                    senderDeviceId = "android-mirror",
                    sessionRequest = SessionRequest(
                        type = SessionType.SESSION_SCREEN_MIRROR,
                        width = width,
                        height = height,
                        targetFps = 20,
                        codec = "JPEG"
                    )
                )
            )

            reader.setOnImageAvailableListener({ imgReader ->
                val image = try {
                    imgReader.acquireLatestImage()
                } catch (_: Exception) {
                    null
                } ?: return@setOnImageAvailableListener

                try {
                    val now = System.currentTimeMillis()
                    // Cap at ~18-20 FPS so Wi-Fi socket never backs up
                    if (now - lastFrameSentMs < 50L) {
                        return@setOnImageAvailableListener
                    }
                    lastFrameSentMs = now

                    val plane = image.planes[0]
                    val buffer = plane.buffer
                    val pixelStride = plane.pixelStride
                    val rowStride = plane.rowStride
                    val rowPadding = rowStride - pixelStride * width

                    val bitmapWidth = width + rowPadding / pixelStride
                    val rawBitmap = Bitmap.createBitmap(bitmapWidth, height, Bitmap.Config.ARGB_8888)
                    rawBitmap.copyPixelsFromBuffer(buffer)

                    val croppedBitmap = if (rowPadding > 0) {
                        Bitmap.createBitmap(rawBitmap, 0, 0, width, height)
                    } else {
                        rawBitmap
                    }

                    val out = ByteArrayOutputStream(65536)
                    croppedBitmap.compress(Bitmap.CompressFormat.JPEG, 68, out)
                    if (croppedBitmap !== rawBitmap) {
                        croppedBitmap.recycle()
                    }
                    rawBitmap.recycle()

                    val jpegBytes = out.toByteArray()
                    val chunk = RawBinaryChunk(
                        transferId = MIRROR_TRANSFER_ID,
                        chunkIndex = frameCounter++,
                        chunkTotal = 1,
                        data = jpegBytes
                    )
                    ConnectionService.activeInstance?.sendBinaryChunk(chunk)
                } catch (e: Exception) {
                    Log.w("ContinuityDebug", "Frame encode error: ${e.message}")
                } finally {
                    try {
                        image.close()
                    } catch (_: Exception) {}
                }
            }, handler)

            virtualDisplay = mediaProjection?.createVirtualDisplay(
                "ContinuityScreenMirror",
                width,
                height,
                240,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                reader.surface,
                null,
                handler
            )
            Log.w("ContinuityDebug", "Live Wireless Screen Mirroring started (${width}x${height})")
        } catch (e: Exception) {
            Log.e("ContinuityDebug", "Failed to start screen capture: ${e.message}", e)
        }
    }

    private fun stopCapture() {
        try {
            virtualDisplay?.release()
        } catch (_: Exception) {}
        virtualDisplay = null

        try {
            imageReader?.close()
        } catch (_: Exception) {}
        imageReader = null

        try {
            mediaProjection?.stop()
        } catch (_: Exception) {}
        mediaProjection = null

        try {
            captureThread?.quitSafely()
        } catch (_: Exception) {}
        captureThread = null
        captureHandler = null

        ConnectionService.activeInstance?.sendEnvelope(
            ContinuityEnvelope(
                senderDeviceId = "android-mirror",
                sessionStop = SessionStop(sessionId = "mirror", reason = "Mirror stopped")
            )
        )
    }

    private fun startForegroundNotification() {
        val channelId = "continuity_screen"
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(channelId, "Screen Mirroring", NotificationManager.IMPORTANCE_LOW)
        nm.createNotificationChannel(channel)

        val notification = Notification.Builder(this, channelId)
            .setContentTitle("Screen Mirroring Active")
            .setContentText("Streaming display to macOS Companion")
            .setSmallIcon(android.R.drawable.presence_video_online)
            .build()

        startForeground(1002, notification)
    }

    override fun onDestroy() {
        super.onDestroy()
        stopCapture()
    }
}
