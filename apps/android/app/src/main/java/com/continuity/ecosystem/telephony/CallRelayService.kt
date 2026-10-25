package com.continuity.ecosystem.telephony

import android.content.Context
import android.media.AudioManager
import android.os.Build
import android.telecom.TelecomManager
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import android.util.Log
import com.continuity.ecosystem.connection.ConnectionService
import com.continuity.ecosystem.core.ContinuityEnvelope
import com.continuity.ecosystem.core.TelephonyAction
import com.continuity.ecosystem.core.TelephonyEvent

class CallRelayService(private val context: Context) {

    private val telephonyManager = context.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
    private var activeCallId: String? = null

    fun startListening(service: ConnectionService) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                telephonyManager.registerTelephonyCallback(
                    context.mainExecutor,
                    object : TelephonyCallback(), TelephonyCallback.CallStateListener {
                        override fun onCallStateChanged(state: Int) {
                            handleCallState(state, "", service)
                        }
                    }
                )
            } else {
                @Suppress("DEPRECATION")
                telephonyManager.listen(object : PhoneStateListener() {
                    @Deprecated("Deprecated in Java")
                    override fun onCallStateChanged(state: Int, phoneNumber: String?) {
                        handleCallState(state, phoneNumber ?: "", service)
                    }
                }, PhoneStateListener.LISTEN_CALL_STATE)
            }
        } catch (e: SecurityException) {
            Log.w("ContinuityDebug", "READ_PHONE_STATE permission not granted for Call Relay: ${e.message}")
        }
    }

    private fun handleCallState(state: Int, incomingNumber: String, service: ConnectionService) {
        val stateString = when (state) {
            TelephonyManager.CALL_STATE_RINGING -> "RINGING"
            TelephonyManager.CALL_STATE_OFFHOOK -> "ANSWERED"
            TelephonyManager.CALL_STATE_IDLE -> "DISCONNECTED"
            else -> "UNKNOWN"
        }

        Log.d("ContinuityDebug", "Telephony call state changed: $stateString ($incomingNumber)")

        val event = TelephonyEvent(
            callerName = if (incomingNumber.isNotEmpty()) incomingNumber else "Incoming Call",
            callerNumber = incomingNumber,
            state = stateString
        )
        activeCallId = event.callId

        service.sendEnvelope(
            ContinuityEnvelope(
                senderDeviceId = "android",
                telephonyEvent = event
            )
        )
    }

    fun handleTelephonyAction(action: TelephonyAction) {
        Log.d("ContinuityDebug", "Received telephony action from Mac: ${action.action}")
        try {
            when (action.action) {
                "REJECT" -> {
                    val telecomManager = context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        try {
                            telecomManager?.endCall()
                        } catch (se: SecurityException) {
                            Log.w("ContinuityDebug", "Cannot end call without ANSWER_PHONE_CALLS permission: ${se.message}")
                        }
                    }
                }
                "MUTE" -> {
                    val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                    audioManager?.ringerMode = AudioManager.RINGER_MODE_SILENT
                }
            }
        } catch (e: Exception) {
            Log.e("ContinuityDebug", "Error executing telephony action: ${e.message}")
        }
    }
}
