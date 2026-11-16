package com.saabithjiffry.presentersync.remote

import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.provider.Settings
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.saabithjiffry.presentersync.remote.network.ConnStatus
import com.saabithjiffry.presentersync.remote.network.ConnectionUiState
import com.saabithjiffry.presentersync.remote.ui.overlay.FloatingMicOverlayManager
import com.saabithjiffry.presentersync.remote.ui.overlay.FloatingToastBannerManager
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.atomic.AtomicReference

@RunWith(AndroidJUnit4::class)
class DirectorDeckInstrumentationTest {

    private fun ensureOverlayPermission(app: PresenterSyncRemoteApp) {
        if (Settings.canDrawOverlays(app)) return
        val cmd = "appops set ${app.packageName} SYSTEM_ALERT_WINDOW allow"
        val pfd: ParcelFileDescriptor = InstrumentationRegistry.getInstrumentation()
            .uiAutomation
            .executeShellCommand(cmd)
        ParcelFileDescriptor.AutoCloseInputStream(pfd).use { it.readBytes() }
        val deadline = SystemClock.uptimeMillis() + 2000L
        while (!Settings.canDrawOverlays(app) && SystemClock.uptimeMillis() < deadline) {
            Thread.sleep(50L)
        }
        assertTrue("SYSTEM_ALERT_WINDOW permission must be granted", Settings.canDrawOverlays(app))
    }

    @Test
    fun pushToTalkPillTouchAndStageNudgeToastOverlayWorkCleanly() {
        val app = ApplicationProvider.getApplicationContext<PresenterSyncRemoteApp>()
        ensureOverlayPermission(app)
        val instr = InstrumentationRegistry.getInstrumentation()
        val prevCfg = app.configStore.current
        val mgrRef = AtomicReference<FloatingMicOverlayManager?>(null)
        val toastRef = AtomicReference<FloatingToastBannerManager?>(null)

        try {
            app.configStore.update {
                it.copy(
                    showIndicator = true,
                    enableHudClickActions = true,
                    enablePushToTalk = true,
                    enablePushToMute = false,
                    hudColorPreset = "Custom",
                    customLiveHex = "#0EA5E9",
                    customMutedHex = "#FDE047",
                    firstRun = false
                )
            }

            instr.runOnMainSync {
                val mgr = FloatingMicOverlayManager(app, app.configStore, app.connectionManager)
                mgrRef.set(mgr)
                mgr.showOrUpdate(
                    app.configStore.current,
                    ConnectionUiState(
                        connected = true,
                        connStatus = ConnStatus.CONNECTED,
                        usingBridge = true,
                        isMuted = true,
                        activeScene = "Slides",
                        scenes = listOf("Main", "Slides", "BRB"),
                        isStandby = true,
                        timerState = "running",
                        timerRemainingSec = 95
                    )
                )

                val pill = mgr.currentPillViewForTesting()
                assertNotNull("Pill view must attach cleanly", pill)
                val now = SystemClock.uptimeMillis()
                val evDown = MotionEvent.obtain(now, now, MotionEvent.ACTION_DOWN, 12f, 12f, 0)
                pill!!.dispatchTouchEvent(evDown)
                evDown.recycle()

                val evUp = MotionEvent.obtain(now, now + 80L, MotionEvent.ACTION_UP, 12f, 12f, 0)
                pill.dispatchTouchEvent(evUp)
                evUp.recycle()

                val menu = mgr.openQuickMenuForTesting()
                assertNotNull("Quick Menu with Standby/Split/Timer banner must attach", menu)
                val collectedText = mutableListOf<String>()
                fun collectTexts(v: View?) {
                    if (v is TextView) collectedText += v.text?.toString().orEmpty()
                    if (v is ViewGroup) {
                        for (i in 0 until v.childCount) collectTexts(v.getChildAt(i))
                    }
                }
                collectTexts(menu)
                val joined = collectedText.joinToString(" | ")
                assertTrue("Quick Menu should display Standby & Timer telemetry ($joined)", joined.contains("BRB") && joined.contains("TMR 01:35"))
                assertTrue("Quick Menu should show Pause/Resume & Split deck buttons ($joined)", joined.contains("Pause") && joined.contains("Split"))
                mgr.dismissQuickMenuForTesting()

                val toaster = FloatingToastBannerManager(app)
                toastRef.set(toaster)
                val (anchor, pillH) = mgr.currentAnchorForToast()
                toaster.showAlertToast(
                    message = "Director: 2:00 Remaining",
                    accentDotColor = android.graphics.Color.parseColor("#F59E0B"),
                    cfg = app.configStore.current,
                    anchorX = anchor.x,
                    anchorY = anchor.y,
                    pillHeightPx = pillH,
                    durationMs = 1500L
                )
            }
            assertTrue("Floating pill stayed attached after PTT + Nudge banner", mgrRef.get()!!.isPillAttachedForTesting())
        } finally {
            instr.runOnMainSync {
                toastRef.get()?.hide()
                mgrRef.get()?.hide()
            }
            app.configStore.update { prevCfg }
        }
    }
}
