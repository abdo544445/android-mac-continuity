package com.continuity.ecosystem.clipboard

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.util.Base64
import android.widget.Toast
import com.continuity.ecosystem.connection.ConnectionService
import com.continuity.ecosystem.core.ClipboardPayload
import com.continuity.ecosystem.core.ContinuityEnvelope
import java.util.UUID

class ClipboardSyncManager(private val context: Context) {
    private val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager

    fun sendCurrentClipboard(service: ConnectionService) {
        val primaryClip = clipboard.primaryClip
        if (primaryClip != null && primaryClip.itemCount > 0) {
            val text = primaryClip.getItemAt(0).text?.toString()
            if (!text.isNullOrEmpty()) {
                val payload = ClipboardPayload(
                    clipId = UUID.randomUUID().toString(),
                    dataBase64 = Base64.encodeToString(text.toByteArray(Charsets.UTF_8), Base64.NO_WRAP),
                    mimeType = "text/plain"
                )
                service.sendEnvelope(ContinuityEnvelope(
                    senderDeviceId = "android",
                    clipboardPayload = payload
                ))
                Toast.makeText(context, "Clipboard sent to Mac", Toast.LENGTH_SHORT).show()
            }
        }
    }

    fun handleIncomingClipboard(payload: ClipboardPayload) {
        val bytes = Base64.decode(payload.dataBase64, Base64.NO_WRAP)
        val text = String(bytes, Charsets.UTF_8)
        val clip = ClipData.newPlainText("Continuity", text)
        clipboard.setPrimaryClip(clip)
        Toast.makeText(context, "Copied from Mac: ${text.take(30)}...", Toast.LENGTH_SHORT).show()
    }
}
