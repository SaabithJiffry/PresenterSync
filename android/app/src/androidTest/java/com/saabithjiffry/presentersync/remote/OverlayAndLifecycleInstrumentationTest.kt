package com.saabithjiffry.presentersync.remote

import android.content.Context
import android.view.WindowManager
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.saabithjiffry.presentersync.remote.service.FloatingHudForegroundService
import com.saabithjiffry.presentersync.remote.ui.overlay.ScreenBoundsCalculator
import com.saabithjiffry.presentersync.remote.ui.screens.MainActivity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class OverlayAndLifecycleInstrumentationTest {

    @Test
    fun configStorePersistsAndResetsCleanly() {
        val app = ApplicationProvider.getApplicationContext<PresenterSyncRemoteApp>()
        app.configStore.update {
            it.copy(savedX = 420, savedY = 310, showText = true, firstRun = false)
        }
        assertEquals(420, app.configStore.current.savedX)
        assertEquals(true, app.configStore.current.showText)

        app.configStore.resetPosition()
        assertEquals(-1, app.configStore.current.savedX)
        assertEquals(-1, app.configStore.current.savedY)
    }

    @Test
    fun safeBoundsRespectDisplayMetrics() {
        val ctx = ApplicationProvider.getApplicationContext<Context>()
        val wm = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val bounds = ScreenBoundsCalculator.getSafeBoundsPx(ctx, wm)
        assertTrue("Expected positive safe width", bounds.width > 100)
        assertTrue("Expected positive safe height", bounds.height > 100)
    }

    @Test
    fun foregroundServiceStartsAndStopsCleanlyWithoutSecurityException() {
        val app = ApplicationProvider.getApplicationContext<PresenterSyncRemoteApp>()
        ActivityScenario.launch(MainActivity::class.java).use {
            FloatingHudForegroundService.startService(app)

            val deadline = System.currentTimeMillis() + 5000L
            while (!app.connectionManager.uiState.value.serviceRunning && System.currentTimeMillis() < deadline) {
                Thread.sleep(100)
            }
            assertTrue("Service should report running", app.connectionManager.uiState.value.serviceRunning)

            FloatingHudForegroundService.stopService(app)
            val stopDeadline = System.currentTimeMillis() + 5000L
            while (app.connectionManager.uiState.value.serviceRunning && System.currentTimeMillis() < stopDeadline) {
                Thread.sleep(100)
            }
            assertFalse("Service should stop cleanly", app.connectionManager.uiState.value.serviceRunning)
        }
    }
}
