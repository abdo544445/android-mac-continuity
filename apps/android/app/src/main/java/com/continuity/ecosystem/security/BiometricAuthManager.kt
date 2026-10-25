package com.continuity.ecosystem.security

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import com.continuity.ecosystem.connection.ConnectionService
import com.continuity.ecosystem.core.BiometricChallenge
import com.continuity.ecosystem.core.BiometricResponse
import com.continuity.ecosystem.core.ContinuityEnvelope

class BiometricAuthManager(private val context: Context) {

    private var currentActivity: FragmentActivity? = null

    fun attachActivity(activity: FragmentActivity) {
        this.currentActivity = activity
    }

    fun detachActivity() {
        this.currentActivity = null
    }

    fun handleBiometricChallenge(challenge: BiometricChallenge, service: ConnectionService) {
        Log.d("ContinuityDebug", "Biometric challenge received: ${challenge.promptTitle}")

        val act = currentActivity
        if (act != null) {
            act.runOnUiThread {
                launchPrompt(act, challenge, service)
            }
        } else {
            // Activity not in foreground: fallback auto-reject or pending response
            Log.w("ContinuityDebug", "Biometric challenge received but no active FragmentActivity attached.")
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

    private fun launchPrompt(activity: FragmentActivity, challenge: BiometricChallenge, service: ConnectionService) {
        val executor = ContextCompat.getMainExecutor(activity)
        val prompt = BiometricPrompt(
            activity,
            executor,
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
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

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
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

        val promptInfo = BiometricPrompt.PromptInfo.Builder()
            .setTitle(challenge.promptTitle.ifEmpty { "Unlock Mac Companion" })
            .setSubtitle("Confirm your identity on Huawei/Android tablet")
            .setNegativeButtonText("Cancel")
            .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG or BiometricManager.Authenticators.DEVICE_CREDENTIAL)
            .build()

        prompt.authenticate(promptInfo)
    }
}
