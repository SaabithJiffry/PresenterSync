package com.saabithjiffry.presentersync.remote

import com.saabithjiffry.presentersync.remote.config.AppConstants
import com.saabithjiffry.presentersync.remote.config.NetworkMode
import com.saabithjiffry.presentersync.remote.config.RemoteConfig
import com.saabithjiffry.presentersync.remote.network.ConnStatus
import com.saabithjiffry.presentersync.remote.network.ConnectionUiState
import com.saabithjiffry.presentersync.remote.ui.screens.evaluateOnboardingReadiness
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class OnboardingAndVersionTest {

    @Test
    fun activeAppVersionMatchesMilestone11Release() {
        assertEquals("7.6.0", AppConstants.APP_VERSION)
    }

    @Test
    fun onboardingReadinessTracksPermissionsPairingAndHudProgressively() {
        val initial = evaluateOnboardingReadiness(
            hasOverlayPerm = false,
            hasNotifPerm = false,
            notificationsRequired = true,
            cfg = RemoteConfig(firstRun = true, hostAddress = "127.0.0.1"),
            conn = ConnectionUiState(connected = false, serviceRunning = false),
            discoveredCount = 0
        )
        assertEquals(0, initial.completedCount)
        assertEquals(4, initial.totalSteps)
        assertFalse(initial.allReady)

        val permAndDiscovered = evaluateOnboardingReadiness(
            hasOverlayPerm = true,
            hasNotifPerm = false,
            notificationsRequired = false, // pre-API 33
            cfg = RemoteConfig(firstRun = true, hostAddress = "127.0.0.1"),
            conn = ConnectionUiState(connected = false, serviceRunning = false),
            discoveredCount = 2
        )
        assertTrue(permAndDiscovered.overlayReady)
        assertTrue(permAndDiscovered.notificationsReady)
        assertFalse(permAndDiscovered.pairingReady)
        assertEquals(2, permAndDiscovered.completedCount)
        assertTrue(permAndDiscovered.steps[2].detail.contains("2 classroom host(s)"))

        val allSet = evaluateOnboardingReadiness(
            hasOverlayPerm = true,
            hasNotifPerm = true,
            notificationsRequired = true,
            cfg = RemoteConfig(
                firstRun = false,
                networkMode = NetworkMode.LAN,
                hostAddress = "192.168.1.44",
                sessionToken = "tok-123"
            ),
            conn = ConnectionUiState(
                connected = true,
                connStatus = ConnStatus.CONNECTED,
                serviceRunning = true
            ),
            discoveredCount = 1
        )
        assertTrue(allSet.allReady)
        assertEquals(4, allSet.completedCount)
    }
}
