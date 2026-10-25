package com.continuity.ecosystem.handoff

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import android.widget.Toast
import com.continuity.ecosystem.connection.ConnectionService
import com.continuity.ecosystem.core.ContinuityEnvelope
import com.continuity.ecosystem.core.HandoffActivity

class HandoffManager(private val context: Context) {

    fun handleIncomingHandoff(activity: HandoffActivity) {
        Log.w("ContinuityDebug", "Received Handoff from Mac: ${activity.url} ('${activity.title}')")
        try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(activity.url)).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            Toast.makeText(context, "Handoff: Opening ${activity.title.ifEmpty { activity.url }}", Toast.LENGTH_LONG).show()
        } catch (e: Exception) {
            Log.e("ContinuityDebug", "Failed to open handoff URL: ${e.message}")
        }
    }

    fun pushWebLink(url: String, title: String, service: ConnectionService) {
        val activity = HandoffActivity(
            url = url,
            title = title,
            sourceApp = "Android"
        )
        service.sendEnvelope(
            ContinuityEnvelope(
                senderDeviceId = "android",
                handoffActivity = activity
            )
        )
        Toast.makeText(context, "Sent link to Mac Handoff", Toast.LENGTH_SHORT).show()
    }
}
