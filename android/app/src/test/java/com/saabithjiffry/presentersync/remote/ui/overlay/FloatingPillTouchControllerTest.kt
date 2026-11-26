package com.saabithjiffry.presentersync.remote.ui.overlay

import com.saabithjiffry.presentersync.remote.config.RemoteConfig
import com.saabithjiffry.presentersync.remote.input.BubbleGestureAction
import com.saabithjiffry.presentersync.remote.input.BubbleHoldStage
import com.saabithjiffry.presentersync.remote.input.GestureScheduler
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

private class TestPillScheduler(
    private val clockMs: () -> Long,
    private val setClockMs: (Long) -> Unit
) : GestureScheduler {
    private data class Task(
        val runAtMs: Long,
        val block: () -> Unit,
        var cancelled: Boolean = false
    )

    private val tasks = mutableListOf<Task>()

    override fun schedule(delayMs: Long, task: () -> Unit): Any {
        val entry = Task(clockMs() + delayMs, task)
        tasks.add(entry)
        return entry
    }

    override fun cancel(token: Any) {
        (token as? Task)?.cancelled = true
    }

    fun advanceBy(deltaMs: Long) {
        val target = clockMs() + deltaMs
        while (true) {
            val next = tasks.filter { !it.cancelled && it.runAtMs <= target }.minByOrNull { it.runAtMs } ?: break
            next.cancelled = true
            setClockMs(next.runAtMs)
            next.block()
        }
        setClockMs(target)
    }
}

class FloatingPillTouchControllerTest {

    @Test
    fun doubleTapAndSingleTapWorkUnderPushToTalkWhenReleasedBefore300ms() {
        var now = 1000L
        val scheduler = TestPillScheduler({ now }, { now = it })
        val actions = mutableListOf<Pair<String, BubbleGestureAction>>()
        var pttActivated = 0
        var pttReleased = 0

        val ctrl = FloatingPillTouchController(
            scheduler = scheduler,
            clockMs = { now },
            onGestureAction = { label, action -> actions.add(label to action) },
            onHoldStageUpdate = { _, _ -> },
            onPttActivated = { pttActivated++ },
            onPttReleased = { pttReleased++ }
        )

        val cfg = RemoteConfig(
            enablePushToTalk = true,
            enableHudClickActions = true,
            singleTapAction = BubbleGestureAction.TOGGLE_MUTE,
            doubleTapAction = BubbleGestureAction.OPEN_QUICK_MENU,
            longPressAction = BubbleGestureAction.OPEN_SETTINGS
        )

        // Double tap (<300ms each) while muted -> triggers Double Tap without triggering PTT
        ctrl.onDown(cfg, isMuted = true)
        scheduler.advanceBy(70L)
        ctrl.onUp()
        scheduler.advanceBy(100L)
        ctrl.onDown(cfg, isMuted = true)
        scheduler.advanceBy(60L)
        ctrl.onUp()

        assertEquals(listOf("Double Tap" to BubbleGestureAction.OPEN_QUICK_MENU), actions)
        assertEquals(0, pttActivated)
        assertEquals(0, pttReleased)

        // Single tap (<300ms) -> waits out double tap window (320ms) and triggers Single Tap
        actions.clear()
        ctrl.onDown(cfg, isMuted = true)
        scheduler.advanceBy(80L)
        ctrl.onUp()
        scheduler.advanceBy(330L)

        assertEquals(listOf("Single Tap" to BubbleGestureAction.TOGGLE_MUTE), actions)
        assertEquals(0, pttActivated)
        assertEquals(0, pttReleased)
    }

    @Test
    fun holdPast300msWhenMutedActivatesPttAndConsumesReleaseWithoutTriggeringLongPress() {
        var now = 2000L
        val scheduler = TestPillScheduler({ now }, { now = it })
        val actions = mutableListOf<BubbleGestureAction>()
        var pttActivated = 0
        var pttReleased = 0

        val ctrl = FloatingPillTouchController(
            scheduler = scheduler,
            clockMs = { now },
            onGestureAction = { _, action -> actions.add(action) },
            onHoldStageUpdate = { _, _ -> },
            onPttActivated = { pttActivated++ },
            onPttReleased = { pttReleased++ }
        )

        val cfg = RemoteConfig(
            enablePushToTalk = true,
            enableHudClickActions = true,
            singleTapAction = BubbleGestureAction.TOGGLE_MUTE,
            doubleTapAction = BubbleGestureAction.OPEN_QUICK_MENU,
            longPressAction = BubbleGestureAction.TOGGLE_MUTE,
            longPressDurationMs = 300
        )

        ctrl.onDown(cfg, isMuted = true)
        scheduler.advanceBy(300L)
        assertTrue(ctrl.isPttActive)
        assertEquals(1, pttActivated)
        assertEquals(0, pttReleased)
        assertTrue("Long press must not collide when PTT activates at 300ms", actions.isEmpty())

        scheduler.advanceBy(500L)
        ctrl.onUp()
        scheduler.advanceBy(300L)
        assertFalse(ctrl.isPttActive)
        assertEquals(1, pttActivated)
        assertEquals(1, pttReleased)
        assertTrue(actions.isEmpty())
    }

    @Test
    fun holdWhenAlreadyLiveNeverActivatesPttAndDragBefore300msCancelsPtt() {
        var now = 3000L
        val scheduler = TestPillScheduler({ now }, { now = it })
        val actions = mutableListOf<BubbleGestureAction>()
        var pttActivated = 0
        var pttReleased = 0

        val ctrl = FloatingPillTouchController(
            scheduler = scheduler,
            clockMs = { now },
            onGestureAction = { _, action -> actions.add(action) },
            onHoldStageUpdate = { _, _ -> },
            onPttActivated = { pttActivated++ },
            onPttReleased = { pttReleased++ }
        )

        val cfg = RemoteConfig(
            enablePushToTalk = true,
            enableHudClickActions = true,
            singleTapAction = BubbleGestureAction.NONE,
            doubleTapAction = BubbleGestureAction.OPEN_QUICK_MENU,
            longPressAction = BubbleGestureAction.NONE
        )

        // When LIVE (isMuted = false), holding past 300ms must NEVER activate PTT or mute on release
        ctrl.onDown(cfg, isMuted = false)
        scheduler.advanceBy(500L)
        ctrl.onUp()
        assertEquals(0, pttActivated)
        assertEquals(0, pttReleased)
        assertTrue(actions.isEmpty())

        // Dragging before 300ms cancels pending PTT cleanly even when muted
        ctrl.onDown(cfg, isMuted = true)
        scheduler.advanceBy(150L)
        ctrl.onDragCancelled()
        scheduler.advanceBy(400L)
        ctrl.onUp()
        assertEquals(0, pttActivated)
        assertEquals(0, pttReleased)
    }

    @Test
    fun muteTransitionPulseScaleFollowsSmooth100To105To100Curve() {
        assertEquals(1.0f, FloatingMicOverlayManager.computeMuteTransitionPulseScale(0.0f), 0.0001f)
        assertEquals(1.05f, FloatingMicOverlayManager.computeMuteTransitionPulseScale(0.5f), 0.0001f)
        assertEquals(1.0f, FloatingMicOverlayManager.computeMuteTransitionPulseScale(1.0f), 0.0001f)
    }
}
