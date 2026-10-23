package com.continuity.ecosystem.notifications

import android.app.Notification
import android.app.RemoteInput
import android.content.Intent
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import com.continuity.ecosystem.core.ContinuityEnvelope
import com.continuity.ecosystem.core.NotificationAction
import com.continuity.ecosystem.core.NotificationEvent

class ContinuityNotificationListenerService : NotificationListenerService() {

    companion object {
        var instance: ContinuityNotificationListenerService? = null
        var onSendNotification: ((ContinuityEnvelope) -> Unit)? = null
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        instance = this
        Log.d("NotifListener", "Continuity NotificationListener connected")
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        instance = null
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        if (sbn == null || sbn.isOngoing) return

        val pkg = sbn.packageName
        if (pkg == packageName) return // Don't mirror own notifications

        val extras = sbn.notification.extras
        val title = extras.getString(Notification.EXTRA_TITLE) ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""

        if (title.isEmpty() && text.isEmpty()) return

        // Sensitive 2FA / OTP filter: don't forward banking OTPs automatically without explicit toggle
        if (isOtpOrSensitive(title, text)) {
            Log.d("NotifListener", "Skipped sensitive notification from $pkg")
            return
        }

        val appName = try {
            val pm = packageManager
            val info = pm.getApplicationInfo(pkg, 0)
            pm.getApplicationLabel(info).toString()
        } catch (e: Exception) {
            pkg
        }

        // Check for RemoteInput reply action
        var hasReply = false
        val actions = sbn.notification.actions ?: emptyArray()
        for (action in actions) {
            if (action.remoteInputs != null && action.remoteInputs.isNotEmpty()) {
                hasReply = true
                break
            }
        }

        val notifEvent = NotificationEvent(
            notificationId = sbn.key,
            packageName = pkg,
            appDisplayName = appName,
            title = title,
            text = text,
            postTimeMs = sbn.postTime,
            isClearable = sbn.isClearable,
            hasReplyAction = hasReply
        )

        onSendNotification?.invoke(ContinuityEnvelope(
            senderDeviceId = "android",
            notificationEvent = notifEvent
        ))
    }

    fun handleRemoteReply(action: NotificationAction) {
        val activeNotifs = activeNotifications ?: return
        val target = activeNotifs.find { it.key == action.notificationId } ?: return
        val notifActions = target.notification.actions ?: return

        for (act in notifActions) {
            val remoteInputs = act.remoteInputs ?: continue
            for (ri in remoteInputs) {
                val intent = Intent()
                val bundle = Bundle()
                bundle.putCharSequence(ri.resultKey, action.replyText)
                RemoteInput.addResultsToIntent(remoteInputs, intent, bundle)
                try {
                    act.actionIntent.send(this, 0, intent)
                    Log.d("NotifListener", "Remote reply sent successfully to ${target.packageName}")
                    return
                } catch (e: Exception) {
                    Log.e("NotifListener", "Failed to send remote reply: ${e.message}")
                }
            }
        }
    }

    private fun isOtpOrSensitive(title: String, text: String): Boolean {
        val combined = "$title $text".lowercase()
        return combined.contains("otp") ||
               combined.contains("verification code") ||
               combined.contains("security code") ||
               combined.contains("do not share")
    }
}
