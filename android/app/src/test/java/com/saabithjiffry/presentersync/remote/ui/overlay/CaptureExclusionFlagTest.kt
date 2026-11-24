package com.saabithjiffry.presentersync.remote.ui.overlay

import android.view.WindowManager
import com.saabithjiffry.presentersync.remote.config.RemoteConfig
import com.saabithjiffry.presentersync.remote.ui.screens.MainActivity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CaptureExclusionFlagTest {

    @Test
    fun remoteConfigDefaultsHideFromScreenCaptureToTrue() {
        val cfg = RemoteConfig()
        assertTrue(cfg.hideFromScreenCapture)
        val updated = cfg.copy(hideFromScreenCapture = false)
        assertFalse(updated.hideFromScreenCapture)
    }

    @Test
    fun computeOverlayFlagsAddsAndClearsFlagSecure() {
        val base = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN

        val secured = FloatingMicOverlayManager.computeOverlayFlags(
            baseFlags = base,
            wantPassThrough = false,
            wantKeepScreenOn = false,
            hideFromScreenCapture = true
        )
        assertTrue((secured and WindowManager.LayoutParams.FLAG_SECURE) != 0)
        assertEquals(0, secured and WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE)

        val unsecured = FloatingMicOverlayManager.computeOverlayFlags(
            baseFlags = secured,
            wantPassThrough = true,
            wantKeepScreenOn = true,
            hideFromScreenCapture = false
        )
        assertEquals(0, unsecured and WindowManager.LayoutParams.FLAG_SECURE)
        assertTrue((unsecured and WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE) != 0)
        assertTrue((unsecured and WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) != 0)
    }

    @Test
    fun mainActivitySecureFlagSyncTogglesAndClearsFlagSecure() {
        val base = WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
        val secured = MainActivity.computeActivitySecureFlags(base, hideFromScreenCapture = true)
        assertTrue((secured and WindowManager.LayoutParams.FLAG_SECURE) != 0)

        val cleared = MainActivity.computeActivitySecureFlags(secured, hideFromScreenCapture = false)
        assertEquals(0, cleared and WindowManager.LayoutParams.FLAG_SECURE)
        assertTrue((cleared and WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN) != 0)
    }
}
