package com.continuity.ecosystem.telephony

import com.continuity.ecosystem.core.ContinuityEnvelope
import com.continuity.ecosystem.core.TelephonyAction
import com.continuity.ecosystem.core.TelephonyEvent
import org.junit.Assert.*
import org.junit.Test

class CallRelayServiceTest {

    @Test
    fun testTelephonyEventIncomingCall() {
        val event = TelephonyEvent(
            callId = "call-12345",
            callerName = "Sarah Connor",
            callerNumber = "+1-555-0199",
            state = "RINGING",
            isVideo = false
        )

        val env = ContinuityEnvelope(
            senderDeviceId = "phone-001",
            telephonyEvent = event
        )

        assertNotNull(env.telephonyEvent)
        assertEquals("Sarah Connor", env.telephonyEvent?.callerName)
        assertEquals("+1-555-0199", env.telephonyEvent?.callerNumber)
        assertEquals("RINGING", env.telephonyEvent?.state)
        assertFalse(env.telephonyEvent?.isVideo ?: true)
    }

    @Test
    fun testTelephonyActionAcceptAndReject() {
        val acceptAction = TelephonyAction(callId = "call-12345", action = "ACCEPT")
        val rejectAction = TelephonyAction(callId = "call-12345", action = "REJECT")
        val muteAction = TelephonyAction(callId = "call-12345", action = "MUTE")

        assertEquals("ACCEPT", acceptAction.action)
        assertEquals("REJECT", rejectAction.action)
        assertEquals("MUTE", muteAction.action)

        val allowedActions = setOf("ACCEPT", "REJECT", "MUTE")
        assertTrue(allowedActions.contains(acceptAction.action))
        assertTrue(allowedActions.contains(rejectAction.action))
        assertTrue(allowedActions.contains(muteAction.action))
    }
}
