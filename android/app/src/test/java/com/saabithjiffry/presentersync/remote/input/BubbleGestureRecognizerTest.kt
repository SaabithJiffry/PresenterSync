package com.saabithjiffry.presentersync.remote.input

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

private class FakeGestureScheduler(
    private val clockMs: () -> Long,
    private val setClockMs: (Long) -> Unit
) : GestureScheduler {
    private data class ScheduledTask(
        val id: Int,
        val runAtMs: Long,
        val action: () -> Unit,
        var cancelled: Boolean = false
    )

    private val queue = mutableListOf<ScheduledTask>()
    private var nextId = 1

    override fun schedule(delayMs: Long, task: () -> Unit): Any {
        val entry = ScheduledTask(nextId++, clockMs() + delayMs, task)
        queue.add(entry)
        return entry
    }

    override fun cancel(token: Any) {
        (token as? ScheduledTask)?.cancelled = true
    }

    fun advanceBy(deltaMs: Long) {
        val target = clockMs() + deltaMs
        while (true) {
            val next = queue
                .filter { !it.cancelled && it.runAtMs <= target }
                .minByOrNull { it.runAtMs } ?: break
            next.cancelled = true
            setClockMs(next.runAtMs)
            next.action()
        }
        setClockMs(target)
    }
}

class BubbleGestureRecognizerTest {

    @Test
    fun defaultSmartBoardConfigIgnoresSingleTapOpensQuickMenuOnDoubleTapAndTogglesOnLongPress() {
        var now = 1000L
        val scheduler = FakeGestureScheduler({ now }, { now = it })
        val actions = mutableListOf<Pair<String, BubbleGestureAction>>()
        val stages = mutableListOf<BubbleHoldStage>()
        val recognizer = BubbleGestureRecognizer(
            scheduler = scheduler,
            clockMs = { now },
            listener = object : BubbleGestureRecognizer.Listener {
                override fun onActionTriggered(gestureLabel: String, action: BubbleGestureAction) {
                    actions.add(gestureLabel to action)
                }

                override fun onHoldStageChanged(stage: BubbleHoldStage, progressFraction: Float) {
                    stages.add(stage)
                }
            }
        )

        val defaultCfg = BubbleGestureConfig()

        // 1. Single tap must be ignored so smartboard touches never misfire
        recognizer.onDown(defaultCfg)
        scheduler.advanceBy(80L)
        recognizer.onUp()
        scheduler.advanceBy(300L)
        assertTrue(actions.isEmpty())

        // 2. Quick double tap triggers Quick Menu on 2nd release
        recognizer.onDown(defaultCfg)
        scheduler.advanceBy(60L)
        recognizer.onUp()
        scheduler.advanceBy(110L)
        recognizer.onDown(defaultCfg)
        scheduler.advanceBy(50L)
        recognizer.onUp()
        assertEquals(listOf("Double Tap" to BubbleGestureAction.OPEN_QUICK_MENU), actions)
        actions.clear()

        // 3. Long press (600ms) toggles mute immediately when no Very Long Press is mapped
        recognizer.onDown(defaultCfg)
        scheduler.advanceBy(600L)
        assertEquals(listOf("Long Press" to BubbleGestureAction.TOGGLE_MUTE), actions)
        assertTrue(stages.contains(BubbleHoldStage.REACHED_LONG))
        recognizer.onUp()
        assertEquals(1, actions.size)
    }

    @Test
    fun separateMuteOnLongAndUnmuteOnVeryLongFiresWithoutDuplicateTriggers() {
        var now = 2000L
        val scheduler = FakeGestureScheduler({ now }, { now = it })
        val actions = mutableListOf<BubbleGestureAction>()
        val stages = mutableListOf<BubbleHoldStage>()
        val recognizer = BubbleGestureRecognizer(
            scheduler = scheduler,
            clockMs = { now },
            listener = object : BubbleGestureRecognizer.Listener {
                override fun onActionTriggered(gestureLabel: String, action: BubbleGestureAction) {
                    actions.add(action)
                }

                override fun onHoldStageChanged(stage: BubbleHoldStage, progressFraction: Float) {
                    stages.add(stage)
                }
            }
        )

        val splitCfg = BubbleGestureConfig(
            singleTapAction = BubbleGestureAction.NONE,
            doubleTapAction = BubbleGestureAction.OPEN_QUICK_MENU,
            longPressAction = BubbleGestureAction.MUTE_ONLY,
            veryLongPressAction = BubbleGestureAction.UNMUTE_ONLY,
            longPressDurationMs = 600L,
            veryLongPressDurationMs = 1400L
        )

        // Hold 750ms -> reaches Long Press, lifting fires MUTE_ONLY once
        recognizer.onDown(splitCfg)
        assertEquals(BubbleHoldStage.IDLE, recognizer.currentVisualHoldState().first)
        scheduler.advanceBy(300L)
        assertEquals(BubbleHoldStage.PROGRESS_LONG, recognizer.currentVisualHoldState().first)
        scheduler.advanceBy(450L)
        assertTrue(stages.contains(BubbleHoldStage.REACHED_LONG))
        assertTrue(actions.isEmpty())
        assertEquals(BubbleHoldStage.PROGRESS_VERY_LONG, recognizer.currentVisualHoldState().first)
        recognizer.onUp()
        assertEquals(listOf(BubbleGestureAction.MUTE_ONLY), actions)
        actions.clear()

        // Hold past 1400ms -> fires UNMUTE_ONLY immediately, release does nothing extra
        recognizer.onDown(splitCfg)
        scheduler.advanceBy(1400L)
        assertEquals(listOf(BubbleGestureAction.UNMUTE_ONLY), actions)
        assertTrue(stages.contains(BubbleHoldStage.REACHED_VERY_LONG))
        recognizer.onUp()
        assertEquals(listOf(BubbleGestureAction.UNMUTE_ONLY), actions)
    }

    @Test
    fun classicTapFiresImmediatelyAndDragOrDisabledSuppressesGestures() {
        var now = 3000L
        val scheduler = FakeGestureScheduler({ now }, { now = it })
        val actions = mutableListOf<BubbleGestureAction>()
        val recognizer = BubbleGestureRecognizer(
            scheduler = scheduler,
            clockMs = { now },
            listener = object : BubbleGestureRecognizer.Listener {
                override fun onActionTriggered(gestureLabel: String, action: BubbleGestureAction) {
                    actions.add(action)
                }

                override fun onHoldStageChanged(stage: BubbleHoldStage, progressFraction: Float) {}
            }
        )

        val classicCfg = BubbleGestureConfig(
            enabled = true,
            singleTapAction = BubbleGestureAction.TOGGLE_MUTE,
            doubleTapAction = BubbleGestureAction.NONE
        )

        // Instant trigger on UP when double tap is NONE
        recognizer.onDown(classicCfg)
        scheduler.advanceBy(50L)
        recognizer.onUp()
        assertEquals(listOf(BubbleGestureAction.TOGGLE_MUTE), actions)
        actions.clear()

        // Drag cancels hold/tap
        recognizer.onDown(classicCfg)
        scheduler.advanceBy(40L)
        recognizer.onDragCancelledGesture()
        scheduler.advanceBy(800L)
        recognizer.onUp()
        assertTrue(actions.isEmpty())

        // Master gesture toggle OFF ignores all gestures
        val disabledCfg = classicCfg.copy(enabled = false, longPressAction = BubbleGestureAction.OPEN_SETTINGS)
        recognizer.onDown(disabledCfg)
        scheduler.advanceBy(1000L)
        recognizer.onUp()
        assertTrue(actions.isEmpty())
    }

    @Test
    fun fastSingleTapBypassFiresImmediatelyAndLateLiftStillDispatchesLongPress() {
        var now = 4000L
        val scheduler = FakeGestureScheduler({ now }, { now = it })
        val actions = mutableListOf<Pair<String, BubbleGestureAction>>()
        val recognizer = BubbleGestureRecognizer(
            scheduler = scheduler,
            clockMs = { now },
            listener = object : BubbleGestureRecognizer.Listener {
                override fun onActionTriggered(gestureLabel: String, action: BubbleGestureAction) {
                    actions.add(gestureLabel to action)
                }

                override fun onHoldStageChanged(stage: BubbleHoldStage, progressFraction: Float) {}
            }
        )

        val bypassCfg = BubbleGestureConfig(
            enabled = true,
            singleTapAction = BubbleGestureAction.TOGGLE_MUTE,
            doubleTapAction = BubbleGestureAction.OPEN_QUICK_MENU,
            fastSingleTapBypass = true
        )
        recognizer.onDown(bypassCfg)
        scheduler.advanceBy(45L)
        recognizer.onUp()
        assertEquals(listOf("Single Tap" to BubbleGestureAction.TOGGLE_MUTE), actions)
        actions.clear()

        // Simulate main looper starvation where longPress scheduler didn't run before UP at 650ms
        val unscheduledHoldCfg = BubbleGestureConfig(
            enabled = true,
            singleTapAction = BubbleGestureAction.NONE,
            doubleTapAction = BubbleGestureAction.NONE,
            longPressAction = BubbleGestureAction.TOGGLE_MUTE,
            longPressDurationMs = 600L
        )
        recognizer.onDown(unscheduledHoldCfg)
        now += 650L
        recognizer.onUp()
        assertEquals(listOf("Long Press" to BubbleGestureAction.TOGGLE_MUTE), actions)
    }
}
