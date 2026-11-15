package com.saabithjiffry.presentersync.remote.input

enum class BubbleGestureAction(
    val rawValue: String,
    val label: String,
    val shortDesc: String
) {
    NONE("none", "None (Ignore)", "Do nothing when this gesture happens"),
    TOGGLE_MUTE("toggle_mute", "Toggle Mute", "Flip between MUTED and LIVE"),
    MUTE_ONLY("mute_only", "Mute Mic Only", "Explicitly mute the host microphone"),
    UNMUTE_ONLY("unmute_only", "Unmute Mic Only", "Explicitly unmute the host microphone"),
    OPEN_QUICK_MENU("open_quick_menu", "Open Quick Menu", "Show the floating Explorer Quick Menu"),
    OPEN_SETTINGS("open_settings", "Open Settings", "Bring PresenterSync Remote window to front"),
    RECONNECT("reconnect", "Reconnect Host", "Restart LAN/Bridge/Relay connection"),
    HIDE_PILL("hide_pill", "Hide Floating Pill", "Hide floating indicator until reopened from tile/notification");

    companion object {
        fun fromRaw(raw: String?): BubbleGestureAction {
            val clean = raw?.trim()?.lowercase().orEmpty()
            return entries.firstOrNull { it.rawValue == clean || it.name.lowercase() == clean } ?: NONE
        }
    }
}

enum class BubbleHoldStage {
    IDLE,
    PROGRESS_LONG,
    REACHED_LONG,
    PROGRESS_VERY_LONG,
    REACHED_VERY_LONG
}

data class BubbleGestureConfig(
    val enabled: Boolean = true,
    val lockPosition: Boolean = false,
    val singleTapAction: BubbleGestureAction = BubbleGestureAction.NONE,
    val doubleTapAction: BubbleGestureAction = BubbleGestureAction.OPEN_QUICK_MENU,
    val longPressAction: BubbleGestureAction = BubbleGestureAction.TOGGLE_MUTE,
    val veryLongPressAction: BubbleGestureAction = BubbleGestureAction.NONE,
    val longPressDurationMs: Long = 600L,
    val veryLongPressDurationMs: Long = 1400L,
    val doubleTapTimeoutMs: Long = 260L
) {
    fun clampedLongMs(): Long = longPressDurationMs.coerceIn(300L, 2000L)

    fun clampedVeryLongMs(): Long {
        val longMs = clampedLongMs()
        return veryLongPressDurationMs.coerceIn(longMs + 300L, 4000L)
    }
}

interface GestureScheduler {
    fun schedule(delayMs: Long, task: () -> Unit): Any
    fun cancel(token: Any)
}

/**
 * Pure-JVM multi-gesture state machine for the floating mic pill:
 * supports customizable Single Tap, Double Tap, Long Press, and Very Long Press
 * with drag isolation and position-lock protection.
 */
class BubbleGestureRecognizer(
    private val scheduler: GestureScheduler,
    private val clockMs: () -> Long,
    private val listener: Listener
) {
    interface Listener {
        fun onActionTriggered(gestureLabel: String, action: BubbleGestureAction)
        fun onHoldStageChanged(stage: BubbleHoldStage, progressFraction: Float)
    }

    private var config = BubbleGestureConfig()
    private var isDown = false
    private var downAtMs = 0L
    private var movedPastSlop = false
    private var longPressReached = false
    private var terminalHoldTriggered = false
    private var awaitingSecondTap = false
    private var inSecondTap = false

    private var longTaskToken: Any? = null
    private var veryLongTaskToken: Any? = null
    private var doubleTapExpireToken: Any? = null

    fun onDown(cfg: BubbleGestureConfig) {
        config = cfg
        cancelHoldTimers()

        if (awaitingSecondTap) {
            cancelDoubleTapTimer()
            awaitingSecondTap = false
            inSecondTap = true
        } else {
            inSecondTap = false
        }

        isDown = true
        downAtMs = clockMs()
        movedPastSlop = false
        longPressReached = false
        terminalHoldTriggered = false

        if (!cfg.enabled) {
            listener.onHoldStageChanged(BubbleHoldStage.IDLE, 0f)
            return
        }

        val hasLong = cfg.longPressAction != BubbleGestureAction.NONE
        val hasVeryLong = cfg.veryLongPressAction != BubbleGestureAction.NONE
        val longMs = cfg.clampedLongMs()
        val veryLongMs = cfg.clampedVeryLongMs()

        if (hasLong || hasVeryLong) {
            longTaskToken = scheduler.schedule(longMs) {
                longTaskToken = null
                if (!isDown || movedPastSlop || terminalHoldTriggered) return@schedule
                longPressReached = true
                if (!hasVeryLong && hasLong) {
                    terminalHoldTriggered = true
                    listener.onHoldStageChanged(BubbleHoldStage.REACHED_LONG, 1f)
                    listener.onActionTriggered("Long Press", config.longPressAction)
                } else {
                    listener.onHoldStageChanged(BubbleHoldStage.REACHED_LONG, 1f)
                }
            }
        }

        if (hasVeryLong) {
            veryLongTaskToken = scheduler.schedule(veryLongMs) {
                veryLongTaskToken = null
                if (!isDown || movedPastSlop || terminalHoldTriggered) return@schedule
                terminalHoldTriggered = true
                listener.onHoldStageChanged(BubbleHoldStage.REACHED_VERY_LONG, 1f)
                listener.onActionTriggered("Very Long Press", config.veryLongPressAction)
            }
        }
    }

    fun onDragCancelledGesture() {
        cancelHoldTimers()
        cancelDoubleTapTimer()
        movedPastSlop = true
        awaitingSecondTap = false
        inSecondTap = false
        listener.onHoldStageChanged(BubbleHoldStage.IDLE, 0f)
    }

    fun onUp() {
        cancelHoldTimers()
        listener.onHoldStageChanged(BubbleHoldStage.IDLE, 0f)

        if (!isDown) return
        isDown = false

        if (movedPastSlop || terminalHoldTriggered || !config.enabled) {
            inSecondTap = false
            return
        }

        if (longPressReached) {
            inSecondTap = false
            if (config.longPressAction != BubbleGestureAction.NONE) {
                listener.onActionTriggered("Long Press", config.longPressAction)
            }
            return
        }

        val elapsed = (clockMs() - downAtMs).coerceAtLeast(0L)
        if (elapsed >= config.clampedLongMs() &&
            (config.longPressAction != BubbleGestureAction.NONE || config.veryLongPressAction != BubbleGestureAction.NONE)
        ) {
            inSecondTap = false
            return
        }

        if (inSecondTap) {
            inSecondTap = false
            if (config.doubleTapAction != BubbleGestureAction.NONE) {
                listener.onActionTriggered("Double Tap", config.doubleTapAction)
            } else if (config.singleTapAction != BubbleGestureAction.NONE) {
                listener.onActionTriggered("Single Tap", config.singleTapAction)
            }
            return
        }

        if (config.doubleTapAction == BubbleGestureAction.NONE) {
            if (config.singleTapAction != BubbleGestureAction.NONE) {
                listener.onActionTriggered("Single Tap", config.singleTapAction)
            }
            return
        }

        awaitingSecondTap = true
        doubleTapExpireToken = scheduler.schedule(config.doubleTapTimeoutMs.coerceIn(140L, 600L)) {
            doubleTapExpireToken = null
            val wasWaiting = awaitingSecondTap
            awaitingSecondTap = false
            if (wasWaiting && config.singleTapAction != BubbleGestureAction.NONE) {
                listener.onActionTriggered("Single Tap", config.singleTapAction)
            }
        }
    }

    fun onCancel() {
        cancelHoldTimers()
        cancelDoubleTapTimer()
        isDown = false
        movedPastSlop = false
        longPressReached = false
        terminalHoldTriggered = false
        awaitingSecondTap = false
        inSecondTap = false
        listener.onHoldStageChanged(BubbleHoldStage.IDLE, 0f)
    }

    fun currentVisualHoldState(nowMs: Long = clockMs()): Pair<BubbleHoldStage, Float> {
        if (!isDown || movedPastSlop || !config.enabled) {
            return BubbleHoldStage.IDLE to 0f
        }
        val hasLong = config.longPressAction != BubbleGestureAction.NONE
        val hasVeryLong = config.veryLongPressAction != BubbleGestureAction.NONE
        if (!hasLong && !hasVeryLong) {
            return BubbleHoldStage.IDLE to 0f
        }

        val elapsed = (nowMs - downAtMs).coerceAtLeast(0L)
        val longMs = config.clampedLongMs()
        val veryLongMs = config.clampedVeryLongMs()

        return when {
            terminalHoldTriggered && hasVeryLong -> BubbleHoldStage.REACHED_VERY_LONG to 1f
            terminalHoldTriggered -> BubbleHoldStage.REACHED_LONG to 1f
            hasVeryLong && elapsed >= longMs -> {
                val frac = ((elapsed - longMs).toFloat() / (veryLongMs - longMs).coerceAtLeast(1L)).coerceIn(0f, 1f)
                if (frac <= 0.05f) BubbleHoldStage.REACHED_LONG to 1f
                else BubbleHoldStage.PROGRESS_VERY_LONG to frac
            }
            elapsed < longMs -> {
                val targetMs = if (hasLong) longMs else veryLongMs
                val frac = (elapsed.toFloat() / targetMs.coerceAtLeast(1L)).coerceIn(0f, 1f)
                // Only show the radial arc after a subtle 110ms touch settle delay so quick taps don't flicker.
                if (elapsed < 110L) BubbleHoldStage.IDLE to 0f
                else if (hasLong) BubbleHoldStage.PROGRESS_LONG to frac
                else BubbleHoldStage.PROGRESS_VERY_LONG to frac
            }
            else -> BubbleHoldStage.REACHED_LONG to 1f
        }
    }

    private fun cancelHoldTimers() {
        longTaskToken?.let { scheduler.cancel(it) }
        longTaskToken = null
        veryLongTaskToken?.let { scheduler.cancel(it) }
        veryLongTaskToken = null
    }

    private fun cancelDoubleTapTimer() {
        doubleTapExpireToken?.let { scheduler.cancel(it) }
        doubleTapExpireToken = null
    }
}
