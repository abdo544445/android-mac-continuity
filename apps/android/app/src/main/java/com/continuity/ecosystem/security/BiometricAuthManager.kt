package com.continuity.ecosystem.security

import android.app.Activity
import android.content.Context
import android.content.DialogInterface
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.CancellationSignal
import android.util.Log
import androidx.core.content.ContextCompat
import com.continuity.ecosystem.connection.ConnectionService
import com.continuity.ecosystem.core.BiometricChallenge
import com.continuity.ecosystem.core.BiometricResponse
import com.continuity.ecosystem.core.ContinuityEnvelope

class BiometricAuthManager(private val context: Context) {

    private var currentActivity: Activity? = null

    fun attachActivity(activity: Activity) {
        this.currentActivity = activity
    }

    fun detachActivity() {
        this.currentActivity = null
    }

    fun handleBiometricChallenge(challenge: BiometricChallenge, service: ConnectionService) {
        Log.d("ContinuityDebug", "Biometric challenge received: ${challenge.promptTitle}")

        val act = currentActivity
        if (act != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            act.runOnUiThread {
                launchPrompt(act, challenge, service)
            }
        } else {
            Log.w("ContinuityDebug", "Biometric challenge received but no active Activity attached or API < 28.")
            service.sendEnvelope(
                ContinuityEnvelope(
                    senderDeviceId = "android",
                    biometricResponse = BiometricResponse(
                        challengeId = challenge.challengeId,
                        approved = false
                    )
                )
            )
        }
    }

    private fun launchPrompt(activity: Activity, challenge: BiometricChallenge, service: ConnectionService) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return

        val executor = ContextCompat.getMainExecutor(activity)
        val prompt = BiometricPrompt.Builder(activity)
            .setTitle(challenge.promptTitle.ifEmpty { "Unlock Mac Companion" })
            .setSubtitle("Confirm your identity on device")
            .setNegativeButton("Cancel", executor, DialogInterface.OnClickListener { _, _ ->
                service.sendEnvelope(
                    ContinuityEnvelope(
                        senderDeviceId = "android",
                        biometricResponse = BiometricResponse(
                            challengeId = challenge.challengeId,
                            approved = false
                        )
                    )
                )
            })
            .build()

        prompt.authenticate(
            CancellationSignal(),
            executor,
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult?) {
                    super.onAuthenticationSucceeded(result)
                    Log.i("ContinuityDebug", "Biometric authentication succeeded!")
                    service.sendEnvelope(
                        ContinuityEnvelope(
                            senderDeviceId = "android",
                            biometricResponse = BiometricResponse(
                                challengeId = challenge.challengeId,
                                approved = true,
                                biometricType = "BIOMETRIC_APPROVED"
                            )
                        )
                    )
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence?) {
                    super.onAuthenticationError(errorCode, errString)
                    Log.w("ContinuityDebug", "Biometric auth error: $errorCode - $errString")
                    service.sendEnvelope(
                        ContinuityEnvelope(
                            senderDeviceId = "android",
                            biometricResponse = BiometricResponse(
                                challengeId = challenge.challengeId,
                                approved = false
                            )
                        )
                    )
                }

                override fun onAuthenticationFailed() {
                    super.onAuthenticationFailed()
                    Log.w("ContinuityDebug", "Biometric authentication failed")
                }
            }
        )
    }
}
