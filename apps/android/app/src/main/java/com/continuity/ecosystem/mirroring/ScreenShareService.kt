package com.continuity.ecosystem.mirroring

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.IBinder
import android.util.Log

class ScreenShareService : Service() {

    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var mediaCodec: MediaCodec? = null

    companion object {
        var resultCode: Int = 0
        var resultData: Intent? = null
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForegroundNotification()

        val mpManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        if (resultData != null) {
            mediaProjection = mpManager.getMediaProjection(resultCode, resultData!!)
            startCapture(1280, 720, 30)
        }

        return START_NOT_STICKY
    }

    private fun startCapture(width: Int, height: Int, fps: Int) {
        try {
            val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
                setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
                setInteger(MediaFormat.KEY_BIT_RATE, 3_000_000)
                setInteger(MediaFormat.KEY_FRAME_RATE, fps)
                setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
            }

            mediaCodec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC).apply {
                configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                val inputSurface = createInputSurface()
                start()

                virtualDisplay = mediaProjection?.createVirtualDisplay(
                    "ContinuityScreenMirror",
                    width,
                    height,
                    320,
                    DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                    inputSurface,
                    null,
                    null
                )
            }
            Log.d("ScreenShare", "Screen capture started: ${width}x${height} @ ${fps}fps")
        } catch (e: Exception) {
            Log.e("ScreenShare", "Failed to start capture: ${e.message}")
        }
    }

    private fun stopCapture() {
        virtualDisplay?.release()
        virtualDisplay = null
        mediaCodec?.stop()
        mediaCodec?.release()
        mediaCodec = null
        mediaProjection?.stop()
        mediaProjection = null
    }

    private fun startForegroundNotification() {
        val channelId = "continuity_screen"
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(channelId, "Screen Mirroring", NotificationManager.IMPORTANCE_LOW)
        nm.createNotificationChannel(channel)

        val notification = Notification.Builder(this, channelId)
            .setContentTitle("Screen Mirroring Active")
            .setContentText("Broadcasting display to macOS Companion")
            .setSmallIcon(android.R.drawable.presence_video_online)
            .build()

        startForeground(1002, notification)
    }

    override fun onDestroy() {
        super.onDestroy()
        stopCapture()
    }
}
