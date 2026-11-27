package com.saabithjiffry.presentersync.remote

import android.os.Build
import android.view.WindowManager
import com.saabithjiffry.presentersync.remote.input.BubbleHoldStage
import com.saabithjiffry.presentersync.remote.input.GestureScheduler
import com.saabithjiffry.presentersync.remote.ui.overlay.FloatingMicOverlayManager
import com.saabithjiffry.presentersync.remote.ui.overlay.FloatingHudStackLayout
import com.saabithjiffry.presentersync.remote.ui.overlay.SafeRectPx
import com.saabithjiffry.presentersync.remote.ui.overlay.ScenePillHoldController
import com.saabithjiffry.presentersync.remote.ui.overlay.ScenePillReleaseOutcome
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GroupedHudStackTest {

    @Test
    fun stackLayoutCentersSceneAboveMicNearBottomAndAutoFlipsNearTop() {
        val bounds = SafeRectPx(left = 0, top = 40, right = 1080, bottom = 2240)
        // Normal bottom-right dock -> Scene stacked above Mic with 12px gap
        val bottom = FloatingHudStackLayout.computeLayout(
            micW = 240,
            micH = 88,
            sceneW = 320,
            sceneH = 64,
            showScene = true,
            gapPx = 12,
            bounds = bounds,
            anchorX = 720,
            anchorY = 1800
        )
        assertTrue(bottom.sceneAboveMic)
        assertEquals(320, bottom.totalWidthPx)
        assertEquals(88 + 12 + 64, bottom.totalHeightPx)
        assertEquals(0, bottom.sceneOffsetY)
        assertEquals(64 + 12, bottom.micOffsetY)
        assertEquals(40, bottom.micOffsetX)
        assertEquals(0, bottom.sceneOffsetX)

        // Dragged into top 18% safe zone -> Scene flips below Mic
        val nearTop = FloatingHudStackLayout.computeLayout(
            micW = 240,
            micH = 88,
            sceneW = 320,
            sceneH = 64,
            showScene = true,
            gapPx = 12,
            bounds = bounds,
            anchorX = 400,
            anchorY = 120
        )
        assertFalse(nearTop.sceneAboveMic)
        assertEquals(0, nearTop.micOffsetY)
        assertEquals(88 + 12, nearTop.sceneOffsetY)
        assertTrue(nearTop.y >= bounds.top)

        // When showScene is false, collapses tightly to Mic pill dimensions
        val micOnly = FloatingHudStackLayout.computeLayout(
            micW = 240,
            micH = 88,
            sceneW = 320,
            sceneH = 64,
            showScene = false,
            gapPx = 12,
            bounds = bounds,
            anchorX = 720,
            anchorY = 1800
        )
        assertEquals(240, micOnly.totalWidthPx)
        assertEquals(88, micOnly.totalHeightPx)
        assertEquals(0, micOnly.gapPx)
    }

    @Test
    fun groupedScenePillPreservesAllThreeGesturesAndOverlayFlags() {
        var now = 0L
        val scheduler = object : GestureScheduler {
            private val tasks = mutableListOf<Triple<Long, () -> Unit, BooleanArray>>()
            override fun schedule(delayMs: Long, task: () -> Unit): Any {
                val cancelled = booleanArrayOf(false)
                tasks.add(Triple(now + delayMs, task, cancelled))
                return cancelled
            }
            override fun cancel(token: Any) {
                (token as? BooleanArray)?.set(0, true)
            }
            fun advance(ms: Long) {
                now += ms
                val ready = tasks.filter { !it.third[0] && it.first <= now }.sortedBy { it.first }
                ready.forEach { it.third[0] = true; it.second() }
            }
        }

        var transitions = 0
        var quickMenus = 0
        var resets = 0
        val holdStages = mutableListOf<BubbleHoldStage>()

        val ctrl = ScenePillHoldController(
            scheduler = scheduler,
            onTapTransition = { transitions++ },
            onOpenSceneMenu = { quickMenus++ },
            onResetActiveScene = { resets++ },
            onHoldStageUpdate = { st, _ -> holdStages.add(st) }
        )

        // 1. Tap (< 600ms) -> OBS Transition
        ctrl.onDown()
        scheduler.advance(150L)
        assertEquals(ScenePillReleaseOutcome.TAP_TRANSITION, ctrl.onUp())
        assertEquals(1, transitions)

        // 2. Stage 1 hold (>= 600ms, < 1400ms) -> Amber REACHED_LONG -> Quick Menu on release
        ctrl.onDown()
        scheduler.advance(650L)
        assertEquals(ScenePillReleaseOutcome.STAGE1_QUICK_MENU, ctrl.onUp())
        assertTrue(holdStages.contains(BubbleHoldStage.REACHED_LONG))
        assertEquals(1, quickMenus)

        // 3. Stage 2 hold (>= 1400ms) -> REACHED_VERY_LONG -> Source-Level Scene Reset
        ctrl.onDown()
        scheduler.advance(1450L)
        assertEquals(ScenePillReleaseOutcome.STAGE2_ALREADY_TRIGGERED, ctrl.onUp())
        assertTrue(holdStages.contains(BubbleHoldStage.REACHED_VERY_LONG))
        assertEquals(1, resets)

        // C4: FLAG_SECURE / FLAG_NOT_TOUCHABLE propagation on overlay flags
        val secureFlags = FloatingMicOverlayManager.computeOverlayFlags(
            baseFlags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            wantPassThrough = true,
            wantKeepScreenOn = true,
            hideFromScreenCapture = true
        )
        assertTrue((secureFlags and WindowManager.LayoutParams.FLAG_SECURE) != 0)
        assertTrue((secureFlags and WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE) != 0)
        assertTrue((secureFlags and WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) != 0)

        // Verify cutout mode constant mapping compiles cleanly on API 30+ and API 28-29
        assertTrue(WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES != 0)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            assertTrue(WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS != 0)
        }
    }
}
