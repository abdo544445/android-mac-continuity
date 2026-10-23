package com.continuity.ecosystem.camera

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder
import android.util.Log

class CameraStreamingService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForegroundNotification()
        Log.d("CameraStreaming", "Camera streaming service started")
        return START_NOT_STICKY
    }

    private fun startForegroundNotification() {
        val channelId = "continuity_camera"
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(channelId, "Webcam Stream", NotificationManager.IMPORTANCE_LOW)
        nm.createNotificationChannel(channel)

        val notification = Notification.Builder(this, channelId)
            .setContentTitle("Continuity Camera Active")
            .setContentText("Streaming camera to Mac webcam input")
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .build()

        startForeground(1003, notification)
    }
}
