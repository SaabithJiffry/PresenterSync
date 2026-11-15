package com.saabithjiffry.presentersync.remote

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.view.WindowManager
import androidx.core.content.FileProvider
import java.io.File
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.saabithjiffry.presentersync.remote.config.RemoteConfigStore
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

    @Test
    fun fileProviderAndInstallPermissionConfigured() {
        val ctx = ApplicationProvider.getApplicationContext<Context>()
        @Suppress("DEPRECATION")
        val pkgInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ctx.packageManager.getPackageInfo(
                ctx.packageName,
                PackageManager.PackageInfoFlags.of(PackageManager.GET_PERMISSIONS.toLong())
            )
        } else {
            ctx.packageManager.getPackageInfo(ctx.packageName, PackageManager.GET_PERMISSIONS)
        }
        val perms = pkgInfo.requestedPermissions?.toList().orEmpty()
        assertTrue(
            "Manifest must declare REQUEST_INSTALL_PACKAGES",
            perms.contains(Manifest.permission.REQUEST_INSTALL_PACKAGES)
        )

        val updatesDir = File(ctx.cacheDir, "updates").apply { mkdirs() }
        val dummyApk = File(updatesDir, "test.apk").apply { writeText("test") }
        try {
            val uri = FileProvider.getUriForFile(ctx, "${ctx.packageName}.fileprovider", dummyApk)
            assertEquals("content", uri.scheme)
            assertEquals("${ctx.packageName}.fileprovider", uri.authority)
            assertTrue("Expected updates path in URI: $uri", uri.toString().contains("/updates/test.apk"))
        } finally {
            dummyApk.delete()
        }
    }

    @Test
    fun m3SmartBoardProfilesKeepScreenOnAndAutoDimPersist() {
        val ctx = ApplicationProvider.getApplicationContext<Context>()
        val store = RemoteConfigStore(ctx)

        store.update {
            it.copy(
                hostAddress = "192.168.50.10",
                targetMicName = "Hall A Mic",
                keepScreenOn = true,
                idleDimAfterSec = 30,
                longPressDurationMs = 900,
                veryLongPressDurationMs = 1900,
                firstRun = false
            )
        }
        val hallA = store.saveCurrentAsProfile("Lecture Hall A")

        store.update { it.copy(hostAddress = "192.168.60.20", targetMicName = "Lab B Mic") }
        val labB = store.saveCurrentAsProfile("Science Lab B")

        val reloaded = RemoteConfigStore(ctx)
        assertTrue(reloaded.current.keepScreenOn)
        assertEquals(30, reloaded.current.idleDimAfterSec)
        assertEquals(900, reloaded.current.longPressDurationMs)
        assertEquals(1900, reloaded.current.veryLongPressDurationMs)
        assertTrue(reloaded.current.savedProfiles.any { it.id == hallA.id && it.name == "Lecture Hall A" })
        assertTrue(reloaded.current.savedProfiles.any { it.id == labB.id && it.name == "Science Lab B" })

        val switched = reloaded.switchToProfile(hallA.id)
        assertEquals("192.168.50.10", switched?.hostAddress)
        assertEquals("192.168.50.10", reloaded.current.hostAddress)
        assertEquals("Hall A Mic", reloaded.current.targetMicName)
        assertEquals(hallA.id, reloaded.current.activeProfileId)

        reloaded.resetAppearance()
        assertFalse(reloaded.current.keepScreenOn)
        assertEquals(0, reloaded.current.idleDimAfterSec)
        assertEquals(600, reloaded.current.longPressDurationMs)
        assertEquals(1400, reloaded.current.veryLongPressDurationMs)
        assertTrue("resetAppearance must preserve saved room profiles", reloaded.current.savedProfiles.size >= 2)

        reloaded.deleteSavedProfile(hallA.id)
        reloaded.deleteSavedProfile(labB.id)
        assertFalse(reloaded.current.savedProfiles.any { it.id == hallA.id || it.id == labB.id })
    }
}
