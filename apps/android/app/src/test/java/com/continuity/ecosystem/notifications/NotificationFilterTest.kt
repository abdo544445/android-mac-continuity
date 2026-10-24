package com.continuity.ecosystem.notifications

import org.junit.Assert.*
import org.junit.Test

class NotificationFilterTest {

    private fun isOtpOrSensitive(title: String, text: String): Boolean {
        val combined = "$title $text".lowercase()
        return combined.contains("otp") ||
               combined.contains("verification code") ||
               combined.contains("security code") ||
               combined.contains("do not share")
    }

    @Test
    fun testSensitiveOtpNotificationsRedacted() {
        assertTrue(isOtpOrSensitive("Bank Alert", "Your verification code is 482910. Do not share."))
        assertTrue(isOtpOrSensitive("Google", "123456 is your Google verification code."))
        assertTrue(isOtpOrSensitive("SMS", "Your login OTP is 998822."))
        assertTrue(isOtpOrSensitive("Security", "Use security code 445566 to reset your password."))
    }

    @Test
    fun testNonSensitiveNotificationsAllowed() {
        assertFalse(isOtpOrSensitive("Sarah", "Hey, are you free for lunch?"))
        assertFalse(isOtpOrSensitive("Calendar", "Product Architecture meeting in 15 mins"))
        assertFalse(isOtpOrSensitive("Slack", "New pull request ready for review"))
        assertFalse(isOtpOrSensitive("GitHub", "Build succeeded on main branch"))
    }
}
