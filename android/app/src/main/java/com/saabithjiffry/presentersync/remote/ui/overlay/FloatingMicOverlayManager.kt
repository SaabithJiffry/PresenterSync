package com.saabithjiffry.presentersync.remote.ui.overlay

import android.content.Context
import android.view.HapticFeedbackConstants
import android.widget.ScrollView
import android.widget.Toast
import com.saabithjiffry.presentersync.remote.input.BubbleGestureAction
import com.saabithjiffry.presentersync.remote.input.BubbleGestureRecognizer
import com.saabithjiffry.presentersync.remote.input.BubbleHoldStage
import com.saabithjiffry.presentersync.remote.input.GestureScheduler
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import com.saabithjiffry.presentersync.remote.config.AppConstants
import com.saabithjiffry.presentersync.remote.config.RemoteConfig
import com.saabithjiffry.presentersync.remote.config.RemoteConfigStore
import com.saabithjiffry.presentersync.remote.config.ThemeMode
import com.saabithjiffry.presentersync.remote.network.ConnectionManager
import com.saabithjiffry.presentersync.remote.network.ConnectionUiState
import com.saabithjiffry.presentersync.remote.ui.screens.MainActivity
import kotlin.math.abs
import kotlin.math.min
import kotlin.math.roundToInt

class FloatingMicOverlayManager(
    private val context: Context,
    private val configStore: RemoteConfigStore,
    private val connectionManager: ConnectionManager
) {
    private val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private val handler = Handler(Looper.getMainLooper())

    private var pillView: MicPillCanvasView? = null
    private var layoutParams: WindowManager.LayoutParams? = null
    private var quickMenuView: View? = null
    private var attached = false
    private var isDragging = false
    private var isAutoDodged = false
    private var isIdleDimmed = false
    private var lastIdleWakeKey = ""

    private var currentConfig: RemoteConfig = configStore.current
    private var currentConn: ConnectionUiState = connectionManager.uiState.value

    private var currentAlpha: Int = currentConfig.opacityLevel
    private var breathDir: Int = -AppConstants.PULSE_STEP_NORMAL
    private var animSeq = 0

    private val idleDimRunnable = Runnable {
        if (attached && currentConfig.showIndicator && currentConfig.idleDimAfterSec > 0 && !isDragging) {
            isIdleDimmed = true
            stopBreathing()
            syncOverlayFlagsAndRender()
        }
    }

    private fun resetIdleDimTimer(wakeNow: Boolean = true) {
        handler.removeCallbacks(idleDimRunnable)
        if (wakeNow && isIdleDimmed) {
            isIdleDimmed = false
            currentAlpha = currentConfig.opacityLevel
            syncOverlayFlagsAndRender()
            if (currentConn.connected && currentConn.isMuted && !isDragging && !isAutoDodged) {
                startBreathing()
            }
        }
        if (attached && currentConfig.showIndicator && currentConfig.idleDimAfterSec > 0) {
            handler.postDelayed(idleDimRunnable, currentConfig.idleDimAfterSec.coerceAtLeast(1) * 1000L)
        }
    }

    private val restoreDodgeRunnable = Runnable {
        if (attached && isAutoDodged) {
            isAutoDodged = false
            currentAlpha = currentConfig.opacityLevel
            syncOverlayFlagsAndRender()
            if (currentConn.connected && currentConn.isMuted) {
                startBreathing()
            }
        }
    }

    private val breathRunnable = object : Runnable {
        override fun run() {
            if (!attached || isDragging || isAutoDodged || isIdleDimmed || !currentConfig.showIndicator || !currentConn.connected || !currentConn.isMuted) {
                return
            }
            val minRatio = if (currentConfig.aggressivePulse) {
                AppConstants.PULSE_MIN_RATIO_AGGRESSIVE
            } else {
                AppConstants.PULSE_MIN_RATIO_NORMAL
            }
            val minAlpha = (currentConfig.opacityLevel * minRatio).roundToInt().coerceAtLeast(10)
            val stepMag = if (currentConfig.aggressivePulse) {
                AppConstants.PULSE_STEP_AGGRESSIVE
            } else {
                AppConstants.PULSE_STEP_NORMAL
            }
            currentAlpha += breathDir
            if (currentAlpha <= minAlpha) {
                currentAlpha = minAlpha
                breathDir = stepMag
            } else if (currentAlpha >= currentConfig.opacityLevel) {
                currentAlpha = currentConfig.opacityLevel
                breathDir = -stepMag
            }
            pillView?.updateRenderState(currentConfig, currentConn, currentAlpha)
            val interval = if (currentConfig.aggressivePulse) {
                AppConstants.PULSE_INTERVAL_AGGRESSIVE_MS
            } else {
                AppConstants.PULSE_INTERVAL_NORMAL_MS
            }
            handler.postDelayed(this, interval)
        }
    }

    fun currentAnchorForToast(): Pair<OverlayPointPx, Int> {
        val density = context.resources.displayMetrics.density
        val bounds = ScreenBoundsCalculator.getSafeBoundsPx(context, windowManager)
        val view = pillView
        val w = view?.computeTargetWidthPx() ?: layoutParams?.width ?: 200
        val h = view?.computeTargetHeightPx() ?: layoutParams?.height ?: 80
        val pos = layoutParams?.let { OverlayPointPx(it.x, it.y) }
            ?: ScreenBoundsCalculator.resolvePosition(
                savedX = currentConfig.savedX,
                savedY = currentConfig.savedY,
                bounds = bounds,
                viewWidthPx = w,
                viewHeightPx = h,
                marginXPx = (AppConstants.SCREEN_MARGIN_X * density).roundToInt(),
                marginYPx = (AppConstants.SCREEN_MARGIN_Y * density).roundToInt()
            )
        return pos to h
    }

    fun showOrUpdate(cfg: RemoteConfig, conn: ConnectionUiState) {
        currentConfig = cfg
        currentConn = conn

        if (!Settings.canDrawOverlays(context) || !cfg.showIndicator) {
            hide()
            return
        }

        if (!cfg.hudAutoDodge && isAutoDodged) {
            isAutoDodged = false
            handler.removeCallbacks(restoreDodgeRunnable)
        }

        val wasAttached = attached
        if (!attached) {
            attachView()
        } else {
            updateDimensionsAndPosition()
        }

        val wakeKey = "${conn.connected}|${conn.isMuted}|${conn.connStatus}|${conn.streamDropWarn}|${conn.voiceWhileMuted}|${cfg.idleDimAfterSec}|${cfg.showIndicator}"
        if (cfg.idleDimAfterSec <= 0) {
            lastIdleWakeKey = wakeKey
            resetIdleDimTimer(wakeNow = true)
        } else if (!wasAttached || wakeKey != lastIdleWakeKey) {
            lastIdleWakeKey = wakeKey
            resetIdleDimTimer(wakeNow = wasAttached)
        }

        syncTouchableFlag()
        val safeW = ScreenBoundsCalculator.getSafeBoundsPx(context, windowManager).width

        if (!isDragging) {
            if (isAutoDodged) {
                stopBreathing()
                currentAlpha = min(cfg.opacityLevel, AppConstants.DODGE_ALPHA)
                pillView?.updateRenderState(cfg, conn, currentAlpha, maxContainerWidthPx = safeW)
            } else if (isIdleDimmed) {
                stopBreathing()
                pillView?.updateRenderState(cfg, conn, currentAlpha, maxContainerWidthPx = safeW)
            } else if (!conn.connected || !conn.isMuted) {
                stopBreathing()
                currentAlpha = cfg.opacityLevel
                pillView?.updateRenderState(cfg, conn, currentAlpha, maxContainerWidthPx = safeW)
            } else {
                pillView?.updateRenderState(cfg, conn, currentAlpha, maxContainerWidthPx = safeW)
                startBreathing()
            }
        }
    }

    fun playMuteTransition(newMuted: Boolean) {
        if (!attached || !currentConfig.showIndicator || isAutoDodged) return
        stopBreathing()
        val seq = ++animSeq
        val baseAlpha = currentConfig.opacityLevel
        val prevMuted = !newMuted
        val steps = AppConstants.FADE_STEPS
        val fadeStep = (baseAlpha.toFloat() / steps).coerceAtLeast(1f)

        var tick = 0
        val animRunnable = object : Runnable {
            override fun run() {
                if (!attached || isDragging || isAutoDodged || animSeq != seq || !currentConfig.showIndicator) {
                    pillView?.scaleX = 1f
                    pillView?.scaleY = 1f
                    return
                }
                tick++
                if (tick <= steps) {
                    val frac = tick.toFloat() / steps
                    val s = 1f - 0.08f * frac
                    val a = (baseAlpha - tick * fadeStep).roundToInt().coerceIn(0, baseAlpha)
                    currentAlpha = a
                    pillView?.scaleX = s
                    pillView?.scaleY = s
                    pillView?.updateRenderState(currentConfig, currentConn, a, prevMuted)
                    handler.postDelayed(this, AppConstants.FADE_SLEEP_MS)
                } else if (tick <= steps * 2) {
                    val step2 = tick - steps
                    val frac = step2.toFloat() / steps
                    val s = 0.92f + 0.08f * frac
                    val a = (step2 * fadeStep).roundToInt().coerceIn(0, baseAlpha)
                    currentAlpha = a
                    pillView?.scaleX = s
                    pillView?.scaleY = s
                    pillView?.updateRenderState(currentConfig, currentConn, a, newMuted)
                    handler.postDelayed(this, AppConstants.FADE_SLEEP_MS)
                } else {
                    pillView?.scaleX = 1f
                    pillView?.scaleY = 1f
                    currentAlpha = baseAlpha
                    pillView?.updateRenderState(currentConfig, currentConn, baseAlpha)
                    if (currentConn.connected && currentConn.isMuted) {
                        startBreathing()
                    }
                }
            }
        }
        handler.post(animRunnable)
    }

    fun hide() {
        stopBreathing()
        handler.removeCallbacks(restoreDodgeRunnable)
        handler.removeCallbacks(idleDimRunnable)
        isAutoDodged = false
        isIdleDimmed = false
        lastIdleWakeKey = ""
        animSeq++
        dismissQuickMenu()
        if (attached && pillView != null) {
            try {
                windowManager.removeViewImmediate(pillView)
            } catch (_: Exception) {
            }
        }
        pillView = null
        layoutParams = null
        attached = false
    }

    private fun computeWindowAlpha(wantPassThrough: Boolean): Float {
        if (!wantPassThrough) return if (isIdleDimmed) 0.35f else 1.0f
        // Android 12+ (API 31+) blocks touches passing through TYPE_APPLICATION_OVERLAY if window alpha > 0.80
        val effective = if (isAutoDodged || isIdleDimmed) {
            min(currentAlpha, AppConstants.DODGE_ALPHA)
        } else {
            currentAlpha
        }
        val base = (effective / 255f).coerceIn(0.10f, AppConstants.MAX_PASS_THROUGH_ALPHA)
        return if (isIdleDimmed) min(base, 0.35f) else base
    }

    private fun attachView() {
        val view = MicPillCanvasView(context)
        val density = context.resources.displayMetrics.density
        val bounds = ScreenBoundsCalculator.getSafeBoundsPx(context, windowManager)
        view.updateRenderState(currentConfig, currentConn, currentAlpha, maxContainerWidthPx = bounds.width)
        val w = view.computeTargetWidthPx(bounds.width)
        val h = view.computeTargetHeightPx(bounds.width)

        val pos = ScreenBoundsCalculator.resolvePosition(
            savedX = currentConfig.savedX,
            savedY = currentConfig.savedY,
            bounds = bounds,
            viewWidthPx = w,
            viewHeightPx = h,
            marginXPx = (AppConstants.SCREEN_MARGIN_X * density).roundToInt(),
            marginYPx = (AppConstants.SCREEN_MARGIN_Y * density).roundToInt(),
            savedXRatio = currentConfig.savedXRatio,
            savedYRatio = currentConfig.savedYRatio
        )

        val wantPassThrough = currentConfig.hudClickThrough || isAutoDodged
        var baseFlags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
        if (wantPassThrough) {
            baseFlags = baseFlags or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
        }
        if (currentConfig.keepScreenOn) {
            baseFlags = baseFlags or WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
        }

        val params = WindowManager.LayoutParams(
            w,
            h,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            baseFlags,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = pos.x
            y = pos.y
            alpha = computeWindowAlpha(wantPassThrough)
        }

        setupTouchHandling(view, params)
        setupHoverDodgeHandling(view)
        view.updateRenderState(currentConfig, currentConn, currentConfig.opacityLevel, maxContainerWidthPx = bounds.width)

        try {
            windowManager.addView(view, params)
            pillView = view
            layoutParams = params
            attached = true
            resetIdleDimTimer(wakeNow = false)
        } catch (_: Exception) {
        }
    }

    private fun syncTouchableFlag() {
        val view = pillView ?: return
        val params = layoutParams ?: return
        if (!attached) return

        val wantPassThrough = currentConfig.hudClickThrough || isAutoDodged
        val wantKeepScreenOn = currentConfig.keepScreenOn
        val desiredWinAlpha = computeWindowAlpha(wantPassThrough)
        val hasTouchFlag = (params.flags and WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE) != 0
        val hasKeepScreenFlag = (params.flags and WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) != 0
        val alphaChanged = abs(params.alpha - desiredWinAlpha) > 0.01f
        if (wantPassThrough != hasTouchFlag || wantKeepScreenOn != hasKeepScreenFlag || alphaChanged) {
            params.flags = if (wantPassThrough) {
                params.flags or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
            } else {
                params.flags and WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE.inv()
            }
            params.flags = if (wantKeepScreenOn) {
                params.flags or WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            } else {
                params.flags and WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON.inv()
            }
            params.alpha = desiredWinAlpha
            runCatching { windowManager.updateViewLayout(view, params) }
        }
    }

    private fun syncOverlayFlagsAndRender() {
        val safeW = ScreenBoundsCalculator.getSafeBoundsPx(context, windowManager).width
        syncTouchableFlag()
        pillView?.updateRenderState(currentConfig, currentConn, currentAlpha, maxContainerWidthPx = safeW)
    }

    private fun setupHoverDodgeHandling(view: MicPillCanvasView) {
        view.setOnHoverListener { _, event ->
            if (!currentConfig.hudAutoDodge || currentConfig.hudClickThrough || isDragging) {
                return@setOnHoverListener false
            }
            when (event.actionMasked) {
                MotionEvent.ACTION_HOVER_ENTER,
                MotionEvent.ACTION_HOVER_MOVE -> {
                    engageAutoDodge()
                    true
                }
                else -> false
            }
        }
    }

    private fun engageAutoDodge() {
        dismissQuickMenu()
        resetIdleDimTimer(wakeNow = true)
        if (!isAutoDodged) {
            isAutoDodged = true
            stopBreathing()
            currentAlpha = min(currentConfig.opacityLevel, AppConstants.DODGE_ALPHA)
            syncOverlayFlagsAndRender()
        }
        handler.removeCallbacks(restoreDodgeRunnable)
        handler.postDelayed(restoreDodgeRunnable, AppConstants.AUTO_DODGE_RESTORE_MS)
    }

    fun onDisplayConfigurationChanged() {
        handler.post {
            if (attached) {
                updateDimensionsAndPosition()
            }
        }
    }

    private fun updateDimensionsAndPosition() {
        val view = pillView ?: return
        val params = layoutParams ?: return
        val density = context.resources.displayMetrics.density
        val bounds = ScreenBoundsCalculator.getSafeBoundsPx(context, windowManager)
        view.updateRenderState(currentConfig, currentConn, currentAlpha, maxContainerWidthPx = bounds.width)
        val newW = view.computeTargetWidthPx(bounds.width)
        val newH = view.computeTargetHeightPx(bounds.width)

        var changed = false
        if (params.width != newW || params.height != newH) {
            params.width = newW
            params.height = newH
            changed = true
        }

        val target = ScreenBoundsCalculator.resolvePosition(
            savedX = currentConfig.savedX,
            savedY = currentConfig.savedY,
            bounds = bounds,
            viewWidthPx = newW,
            viewHeightPx = newH,
            marginXPx = (AppConstants.SCREEN_MARGIN_X * density).roundToInt(),
            marginYPx = (AppConstants.SCREEN_MARGIN_Y * density).roundToInt(),
            savedXRatio = currentConfig.savedXRatio,
            savedYRatio = currentConfig.savedYRatio
        )

        if (!isDragging && (params.x != target.x || params.y != target.y)) {
            params.x = target.x
            params.y = target.y
            changed = true
        }

        if (changed && attached) {
            try {
                windowManager.updateViewLayout(view, params)
            } catch (_: Exception) {
            }
        }
    }

    private var activeGestureRecognizer: BubbleGestureRecognizer? = null

    private fun setupTouchHandling(view: MicPillCanvasView, params: WindowManager.LayoutParams) {
        val density = context.resources.displayMetrics.density
        val slopPx = (AppConstants.SHORT_TAP_MAX_SLOP_DP * density).coerceAtLeast(
            ViewConfiguration.get(context).scaledTouchSlop.toFloat()
        )
        val lockCancelSlopPx = (56f * density).coerceAtLeast(slopPx * 2.5f)
        var downRawX = 0f
        var downRawY = 0f
        var startParamX = 0
        var startParamY = 0
        var movedPastSlop = false
        var lastStage = BubbleHoldStage.IDLE

        val scheduler = object : GestureScheduler {
            override fun schedule(delayMs: Long, task: () -> Unit): Any {
                val r = Runnable { task() }
                handler.postDelayed(r, delayMs)
                return r
            }

            override fun cancel(token: Any) {
                (token as? Runnable)?.let { handler.removeCallbacks(it) }
            }
        }

        var holdVisualTickRunnable: Runnable? = null
        fun stopHoldVisualTick() {
            holdVisualTickRunnable?.let { handler.removeCallbacks(it) }
            holdVisualTickRunnable = null
            view.setGestureFeedback(BubbleHoldStage.IDLE, 0f)
        }

        val recognizer = BubbleGestureRecognizer(
            scheduler = scheduler,
            clockMs = { System.currentTimeMillis() },
            listener = object : BubbleGestureRecognizer.Listener {
                override fun onActionTriggered(gestureLabel: String, action: BubbleGestureAction) {
                    if (action != BubbleGestureAction.NONE) {
                        runCatching { view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP) }
                    }
                    executeBubbleAction(action)
                }

                override fun onHoldStageChanged(stage: BubbleHoldStage, progressFraction: Float) {
                    if (stage != lastStage) {
                        when (stage) {
                            BubbleHoldStage.REACHED_LONG -> {
                                runCatching { view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK) }
                            }
                            BubbleHoldStage.REACHED_VERY_LONG -> {
                                runCatching { view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS) }
                            }
                            else -> Unit
                        }
                        lastStage = stage
                    }
                    view.setGestureFeedback(stage, progressFraction)
                    if (stage == BubbleHoldStage.IDLE) {
                        stopHoldVisualTick()
                    }
                }
            }
        )
        activeGestureRecognizer = recognizer

        fun startHoldVisualTick() {
            stopHoldVisualTick()
            val ticker = object : Runnable {
                override fun run() {
                    val (stage, frac) = recognizer.currentVisualHoldState()
                    if (stage != lastStage) {
                        when (stage) {
                            BubbleHoldStage.REACHED_LONG -> {
                                runCatching { view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK) }
                            }
                            BubbleHoldStage.REACHED_VERY_LONG -> {
                                runCatching { view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS) }
                            }
                            else -> Unit
                        }
                        lastStage = stage
                    }
                    view.setGestureFeedback(stage, frac)
                    if (holdVisualTickRunnable === this) {
                        handler.postDelayed(this, 32L)
                    }
                }
            }
            holdVisualTickRunnable = ticker
            handler.postDelayed(ticker, 48L)
        }

        view.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    dismissQuickMenu()
                    resetIdleDimTimer(wakeNow = true)
                    downRawX = event.rawX
                    downRawY = event.rawY
                    startParamX = params.x
                    startParamY = params.y
                    movedPastSlop = false
                    lastStage = BubbleHoldStage.IDLE
                    val gestureCfg = currentConfig.toBubbleGestureConfig()
                    recognizer.onDown(gestureCfg)
                    if (gestureCfg.enabled &&
                        (gestureCfg.longPressAction != BubbleGestureAction.NONE ||
                            gestureCfg.veryLongPressAction != BubbleGestureAction.NONE)
                    ) {
                        startHoldVisualTick()
                    }
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - downRawX
                    val dy = event.rawY - downRawY
                    if (currentConfig.lockHudPosition) {
                        if (!movedPastSlop && (abs(dx) > lockCancelSlopPx || abs(dy) > lockCancelSlopPx)) {
                            movedPastSlop = true
                            stopHoldVisualTick()
                            recognizer.onDragCancelledGesture()
                        }
                        return@setOnTouchListener true
                    }
                    if (!movedPastSlop && (abs(dx) > slopPx || abs(dy) > slopPx)) {
                        movedPastSlop = true
                        isDragging = true
                        stopHoldVisualTick()
                        recognizer.onDragCancelledGesture()
                        stopBreathing()
                    }
                    if (movedPastSlop) {
                        val bounds = ScreenBoundsCalculator.getSafeBoundsPx(context, windowManager)
                        val minX = bounds.left
                        val maxX = (bounds.right - params.width).coerceAtLeast(minX)
                        val minY = bounds.top
                        val maxY = (bounds.bottom - params.height).coerceAtLeast(minY)
                        val rawX = (startParamX + dx.roundToInt()).coerceIn(minX, maxX)
                        val rawY = (startParamY + dy.roundToInt()).coerceIn(minY, maxY)
                        if (currentConfig.enableMagneticSnap) {
                            val snapped = ScreenBoundsCalculator.computeMagneticSnap(
                                rawX = rawX,
                                rawY = rawY,
                                viewWidthPx = params.width,
                                viewHeightPx = params.height,
                                bounds = bounds,
                                thresholdPx = (AppConstants.SNAP_THRESHOLD_DP * density).roundToInt()
                            )
                            params.x = snapped.x
                            params.y = snapped.y
                        } else {
                            params.x = rawX
                            params.y = rawY
                        }
                        try {
                            windowManager.updateViewLayout(view, params)
                        } catch (_: Exception) {
                        }
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    stopHoldVisualTick()
                    resetIdleDimTimer(wakeNow = true)
                    if (isDragging) {
                        isDragging = false
                        val bounds = ScreenBoundsCalculator.getSafeBoundsPx(context, windowManager)
                        val (rx, ry) = ScreenBoundsCalculator.computePositionRatios(
                            x = params.x,
                            y = params.y,
                            bounds = bounds,
                            viewWidthPx = params.width,
                            viewHeightPx = params.height
                        )
                        configStore.update {
                            it.copy(
                                savedX = params.x,
                                savedY = params.y,
                                savedXRatio = rx,
                                savedYRatio = ry
                            )
                        }
                        recognizer.onUp()
                        if (currentConn.connected && currentConn.isMuted) {
                            startBreathing()
                        }
                    } else {
                        recognizer.onUp()
                    }
                    true
                }
                MotionEvent.ACTION_CANCEL -> {
                    stopHoldVisualTick()
                    recognizer.onCancel()
                    isDragging = false
                    if (currentConn.connected && currentConn.isMuted) {
                        startBreathing()
                    }
                    true
                }
                else -> false
            }
        }
    }

    private fun executeBubbleAction(action: BubbleGestureAction) {
        when (action) {
            BubbleGestureAction.NONE -> Unit
            BubbleGestureAction.TOGGLE_MUTE -> connectionManager.toggleMuteFromHud()
            BubbleGestureAction.MUTE_ONLY -> connectionManager.setMuteFromHud(true)
            BubbleGestureAction.UNMUTE_ONLY -> connectionManager.setMuteFromHud(false)
            BubbleGestureAction.OPEN_QUICK_MENU -> showQuickMenu()
            BubbleGestureAction.OPEN_SETTINGS -> openSettingsActivity()
            BubbleGestureAction.RECONNECT -> {
                connectionManager.reconnectNow()
                Toast.makeText(context, "Reconnecting PresenterSync...", Toast.LENGTH_SHORT).show()
            }
            BubbleGestureAction.HIDE_PILL -> {
                configStore.update { it.copy(showIndicator = false) }
            }
        }
    }

    private fun showQuickMenu() {
        dismissQuickMenu()
        if (!attached || !Settings.canDrawOverlays(context)) return

        val density = context.resources.displayMetrics.density
        val isDark = when (currentConfig.themeMode) {
            ThemeMode.DARK -> true
            ThemeMode.LIGHT -> false
            ThemeMode.SYSTEM -> {
                val night = context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
                night != Configuration.UI_MODE_NIGHT_NO
            }
        }

        val surfaceBg = if (isDark) Color.parseColor("#2C2C2C") else Color.parseColor("#FFFFFF")
        val borderStroke = if (isDark) Color.parseColor("#3D3D3D") else Color.parseColor("#E5E5E5")
        val dividerColor = if (isDark) Color.parseColor("#383838") else Color.parseColor("#EAEAEA")
        val textColor = if (isDark) Color.WHITE else Color.parseColor("#1A1A1A")
        val accentColor = if (isDark) Color.parseColor("#60CDFF") else Color.parseColor("#0067C0")

        val container = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            val pad = (6 * density).roundToInt()
            setPadding(pad, pad, pad, pad)
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = 8f * density
                setColor(surfaceBg)
                setStroke((1f * density).roundToInt().coerceAtLeast(1), borderStroke)
            }
        }

        val header = TextView(context).apply {
            text = "PresenterSync Quick Menu"
            setTextColor(accentColor)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11.5f)
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            val hp = (10 * density).roundToInt()
            val vp = (6 * density).roundToInt()
            setPadding(hp, vp, hp, (2 * density).roundToInt())
        }
        container.addView(header)

        if (currentConn.connected) {
            val recLabel = when (currentConn.recState) {
                1 -> "● REC ${currentConn.formattedRecElapsed()}"
                2 -> "❚❚ PAUSED ${currentConn.formattedRecElapsed()}"
                else -> "REC: OFF"
            }
            val streamLabel = if (currentConn.streamDropWarn) "⚠ STREAM DROP" else "Stream OK"
            val warnExtra = if (currentConn.voiceWhileMuted && currentConn.isMuted) "\n⚠ Mic signal detected while muted" else ""
            val telemetryBanner = TextView(context).apply {
                text = "$recLabel • $streamLabel$warnExtra"
                setTextColor(
                    when {
                        currentConn.voiceWhileMuted && currentConn.isMuted -> Color.parseColor("#F59E0B")
                        currentConn.streamDropWarn -> Color.parseColor("#EF4444")
                        currentConn.recState == 1 -> Color.parseColor("#EF4444")
                        else -> if (isDark) Color.parseColor("#CBD5E1") else Color.parseColor("#475569")
                    }
                )
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
                val hp = (10 * density).roundToInt()
                setPadding(hp, 0, hp, (6 * density).roundToInt())
            }
            container.addView(telemetryBanner)
        }

        if (currentConn.connected && currentConn.usingBridge) {
            val deckDivider = View(context).apply { setBackgroundColor(dividerColor) }
            container.addView(deckDivider, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 1))

            val deckRow = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                val pad = (6 * density).roundToInt()
                setPadding(pad, pad, pad, pad)
            }
            val btnSurface = if (isDark) Color.parseColor("#383838") else Color.parseColor("#F1F5F9")
            val recSurface = if (currentConn.recState == 1) Color.parseColor("#DC2626") else btnSurface
            val recTextCol = if (currentConn.recState == 1) Color.WHITE else textColor

            fun addDeckButton(label: String, bgCol: Int, fgCol: Int, closeAfter: Boolean, onTap: () -> Unit) {
                val tv = TextView(context).apply {
                    text = label
                    gravity = Gravity.CENTER
                    setTextColor(fgCol)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                    typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
                    val vp = (8 * density).roundToInt()
                    setPadding((4 * density).roundToInt(), vp, (4 * density).roundToInt(), vp)
                    background = GradientDrawable().apply {
                        shape = GradientDrawable.RECTANGLE
                        cornerRadius = 6f * density
                        setColor(bgCol)
                    }
                    isClickable = true
                    isFocusable = false
                    setOnClickListener {
                        performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                        onTap()
                        if (closeAfter) dismissQuickMenu()
                    }
                }
                val lp = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
                    marginStart = (3 * density).roundToInt()
                    marginEnd = (3 * density).roundToInt()
                }
                deckRow.addView(tv, lp)
            }

            addDeckButton("◀ Prev", btnSurface, textColor, closeAfter = false) {
                connectionManager.sendPptPrev("quick_menu")
            }
            addDeckButton(
                label = if (currentConn.recState == 1) "⏹ Stop" else "⏺ Rec",
                bgCol = recSurface,
                fgCol = recTextCol,
                closeAfter = true
            ) {
                connectionManager.sendToggleRecord("quick_menu")
            }
            addDeckButton("Next ▶", btnSurface, textColor, closeAfter = false) {
                connectionManager.sendPptNext("quick_menu")
            }
            container.addView(deckRow, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
        }

        fun addMenuRow(label: String, onClick: () -> Unit) {
            val divider = View(context).apply { setBackgroundColor(dividerColor) }
            container.addView(divider, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 1))

            val row = TextView(context).apply {
                text = label
                setTextColor(textColor)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 13.5f)
                val hp = (12 * density).roundToInt()
                val vp = (10 * density).roundToInt()
                setPadding(hp, vp, hp, vp)
                isClickable = true
                isFocusable = false
                setOnClickListener {
                    dismissQuickMenu()
                    onClick()
                }
            }
            container.addView(row, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
        }

        addMenuRow(if (currentConn.isMuted) "Unmute Mic (Currently MUTED)" else "Mute Mic (Currently LIVE)") {
            connectionManager.toggleMuteFromHud()
        }
        addMenuRow("Lock Pill Position: ${if (currentConfig.lockHudPosition) "LOCKED" else "UNLOCKED"}") {
            configStore.update { it.copy(lockHudPosition = !it.lockHudPosition) }
        }
        addMenuRow("Show Text Label: ${if (currentConfig.showText) "ON" else "OFF"}") {
            configStore.update { it.copy(showText = !it.showText) }
        }
        addMenuRow("Enable Click-Through Mode") {
            configStore.update { it.copy(hudClickThrough = true) }
        }
        addMenuRow("Hide Floating Pill") {
            configStore.update { it.copy(showIndicator = false) }
        }
        addMenuRow("Open Full Settings...") {
            openSettingsActivity()
        }

        val bounds = ScreenBoundsCalculator.getSafeBoundsPx(context, windowManager)
        val maxMenuW = (bounds.width - (16 * density).roundToInt()).coerceAtLeast((180 * density).roundToInt())
        val menuW = (248 * density).roundToInt().coerceAtMost(maxMenuW)
        container.measure(
            View.MeasureSpec.makeMeasureSpec(menuW, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
        )
        val maxMenuH = (bounds.height - (16 * density).roundToInt()).coerceAtLeast((160 * density).roundToInt())
        val menuH = container.measuredHeight.coerceIn((160 * density).roundToInt().coerceAtMost(maxMenuH), maxMenuH)

        val outerBg = container.background
        container.background = null
        val menuRoot = ScrollView(context).apply {
            isVerticalScrollBarEnabled = true
            background = outerBg
            addView(
                container,
                android.view.ViewGroup.LayoutParams(
                    android.view.ViewGroup.LayoutParams.MATCH_PARENT,
                    android.view.ViewGroup.LayoutParams.WRAP_CONTENT
                )
            )
        }

        val (anchor, pillH) = currentAnchorForToast()
        val gap = (8 * density).roundToInt()
        val targetX = anchor.x.coerceIn(bounds.left, (bounds.right - menuW).coerceAtLeast(bounds.left))
        val preferAbove = anchor.y - menuH - gap
        val rawY = if (preferAbove >= bounds.top) preferAbove else (anchor.y + pillH + gap)
        val targetY = rawY.coerceIn(bounds.top, (bounds.bottom - menuH).coerceAtLeast(bounds.top))

        val menuParams = WindowManager.LayoutParams(
            menuW,
            menuH,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = targetX
            y = targetY
        }

        menuRoot.setOnTouchListener { _, ev ->
            if (ev.actionMasked == MotionEvent.ACTION_OUTSIDE) {
                dismissQuickMenu()
                true
            } else {
                false
            }
        }

        runCatching {
            windowManager.addView(menuRoot, menuParams)
            quickMenuView = menuRoot
        }
    }

    private fun dismissQuickMenu() {
        val mv = quickMenuView ?: return
        quickMenuView = null
        runCatching { windowManager.removeViewImmediate(mv) }
    }

    private fun openSettingsActivity() {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        context.startActivity(intent)
    }

    private fun startBreathing() {
        handler.removeCallbacks(breathRunnable)
        breathDir = if (currentConfig.aggressivePulse) {
            -AppConstants.PULSE_STEP_AGGRESSIVE
        } else {
            -AppConstants.PULSE_STEP_NORMAL
        }
        val interval = if (currentConfig.aggressivePulse) {
            AppConstants.PULSE_INTERVAL_AGGRESSIVE_MS
        } else {
            AppConstants.PULSE_INTERVAL_NORMAL_MS
        }
        handler.postDelayed(breathRunnable, interval)
    }

    private fun stopBreathing() {
        handler.removeCallbacks(breathRunnable)
    }
}
