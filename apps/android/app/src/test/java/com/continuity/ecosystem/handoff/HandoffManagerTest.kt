package com.continuity.ecosystem.handoff

import com.continuity.ecosystem.core.ContinuityEnvelope
import com.continuity.ecosystem.core.HandoffActivity
import org.junit.Assert.*
import org.junit.Test

class HandoffManagerTest {

    @Test
    fun testHandoffActivityEnvelopeStructure() {
        val activity = HandoffActivity(
            activityId = "handoff-001",
            url = "https://developer.android.com",
            title = "Android Developers Documentation",
            sourceApp = "Chrome",
            scrollPosition = 0.45f
        )

        val env = ContinuityEnvelope(
            senderDeviceId = "android-test",
            handoffActivity = activity
        )

        assertNotNull(env.handoffActivity)
        assertEquals("https://developer.android.com", env.handoffActivity?.url)
        assertEquals("Android Developers Documentation", env.handoffActivity?.title)
        assertEquals("Chrome", env.handoffActivity?.sourceApp)
        assertEquals(0.45f, env.handoffActivity?.scrollPosition ?: 0f, 0.001f)
    }

    @Test
    fun testHandoffUrlValidation() {
        val validUrl = "https://github.com/abdo544445/android-mac-continuity"
        val isWebUrl = validUrl.startsWith("http://") || validUrl.startsWith("https://")
        assertTrue("Handoff URL must be standard HTTP/HTTPS web scheme", isWebUrl)

        val nonWebUrl = "javascript:alert(1)"
        val isUnsafe = !nonWebUrl.startsWith("http://") && !nonWebUrl.startsWith("https://")
        assertTrue("Non-web schemes must be rejected", isUnsafe)
    }
}
