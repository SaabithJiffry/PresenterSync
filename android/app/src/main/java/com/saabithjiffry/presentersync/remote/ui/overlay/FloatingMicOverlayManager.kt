package com.saabithjiffry.presentersync.remote.ui.overlay

import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.ViewConfiguration
import android.view.WindowManager
import com.saabithjiffry.presentersync.remote.config.AppConstants
import com.saabithjiffry.presentersync.remote.config.RemoteConfig
import com.saabithjiffry.presentersync.remote.config.RemoteConfigStore
import com.saabithjiffry.presentersync.remote.network.ConnectionManager
import com.saabithjiffry.presentersync.remote.network.ConnectionUiState
import com.saabithjiffry.presentersync.remote.ui.screens.MainActivity
import kotlin.math.abs
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
    private var attached = false
    private var isDragging = false

    private var currentConfig: RemoteConfig = configStore.current
    private var currentConn: ConnectionUiState = connectionManager.uiState.value

    private var currentAlpha: Int = currentConfig.opacityLevel
    private var breathDir: Int = -AppConstants.PULSE_STEP_NORMAL
    private var animSeq = 0

    private val breathRunnable = object : Runnable {
        override fun run() {
            if (!attached || isDragging || !currentConfig.showIndicator || !currentConn.connected || !currentConn.isMuted) {
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

    fun showOrUpdate(cfg: RemoteConfig, conn: ConnectionUiState) {
        currentConfig = cfg
        currentConn = conn

        if (!Settings.canDrawOverlays(context) || !cfg.showIndicator) {
            hide()
            return
        }

        if (!attached) {
            attachView()
        } else {
            updateDimensionsAndPosition()
        }

        if (!isDragging) {
            if (!conn.connected || !conn.isMuted) {
                stopBreathing()
                currentAlpha = cfg.opacityLevel
            }
            pillView?.updateRenderState(cfg, conn, currentAlpha)
            if (conn.connected && conn.isMuted) {
                startBreathing()
            }
        }
    }

    fun playMuteTransition(newMuted: Boolean) {
        if (!attached || !currentConfig.showIndicator) return
        stopBreathing()
        val seq = ++animSeq
        val baseAlpha = currentConfig.opacityLevel
        val prevMuted = !newMuted
        val steps = AppConstants.FADE_STEPS
        val fadeStep = (baseAlpha.toFloat() / steps).coerceAtLeast(1f)

        var tick = 0
        val animRunnable = object : Runnable {
            override fun run() {
                if (!attached || isDragging || animSeq != seq || !currentConfig.showIndicator) return
                tick++
                if (tick <= steps) {
                    val a = (baseAlpha - tick * fadeStep).roundToInt().coerceIn(0, baseAlpha)
                    currentAlpha = a
                    pillView?.updateRenderState(currentConfig, currentConn, a, prevMuted)
                    handler.postDelayed(this, AppConstants.FADE_SLEEP_MS)
                } else if (tick <= steps * 2) {
                    val step2 = tick - steps
                    val a = (step2 * fadeStep).roundToInt().coerceIn(0, baseAlpha)
                    currentAlpha = a
                    pillView?.updateRenderState(currentConfig, currentConn, a, newMuted)
                    handler.postDelayed(this, AppConstants.FADE_SLEEP_MS)
                } else {
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
        animSeq++
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

    private fun attachView() {
        val view = MicPillCanvasView(context)
        val density = context.resources.displayMetrics.density
        val w = view.computeTargetWidthPx()
        val h = view.computeTargetHeightPx()

        val screen = getScreenSizePx()
        val defaultX = (screen.first - w - (AppConstants.SCREEN_MARGIN_X * density).roundToInt()).coerceAtLeast(0)
        val defaultY = (screen.second - h - (AppConstants.SCREEN_MARGIN_Y * density).roundToInt()).coerceAtLeast(0)

        val startX = if (currentConfig.savedX >= 0) {
            currentConfig.savedX.coerceIn(0, (screen.first - w).coerceAtLeast(0))
        } else defaultX
        val startY = if (currentConfig.savedY >= 0) {
            currentConfig.savedY.coerceIn(0, (screen.second - h).coerceAtLeast(0))
        } else defaultY

        val params = WindowManager.LayoutParams(
            w,
            h,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = startX
            y = startY
        }

        setupTouchHandling(view, params)
        view.updateRenderState(currentConfig, currentConn, currentConfig.opacityLevel)

        try {
            windowManager.addView(view, params)
            pillView = view
            layoutParams = params
            attached = true
        } catch (_: Exception) {
        }
    }

    private fun updateDimensionsAndPosition() {
        val view = pillView ?: return
        val params = layoutParams ?: return
        view.updateRenderState(currentConfig, currentConn, currentAlpha)
        val newW = view.computeTargetWidthPx()
        val newH = view.computeTargetHeightPx()
        val screen = getScreenSizePx()

        var changed = false
        if (params.width != newW || params.height != newH) {
            params.width = newW
            params.height = newH
            changed = true
        }

        val targetX = if (currentConfig.savedX >= 0) {
            currentConfig.savedX.coerceIn(0, (screen.first - newW).coerceAtLeast(0))
        } else {
            val density = context.resources.displayMetrics.density
            (screen.first - newW - (AppConstants.SCREEN_MARGIN_X * density).roundToInt()).coerceAtLeast(0)
        }
        val targetY = if (currentConfig.savedY >= 0) {
            currentConfig.savedY.coerceIn(0, (screen.second - newH).coerceAtLeast(0))
        } else {
            val density = context.resources.displayMetrics.density
            (screen.second - newH - (AppConstants.SCREEN_MARGIN_Y * density).roundToInt()).coerceAtLeast(0)
        }

        if (!isDragging && (params.x != targetX || params.y != targetY)) {
            params.x = targetX
            params.y = targetY
            changed = true
        }

        if (changed && attached) {
            try {
                windowManager.updateViewLayout(view, params)
            } catch (_: Exception) {
            }
        }
    }

    private fun setupTouchHandling(view: MicPillCanvasView, params: WindowManager.LayoutParams) {
        val density = context.resources.displayMetrics.density
        val slopPx = (AppConstants.SHORT_TAP_MAX_SLOP_DP * density).coerceAtLeast(
            ViewConfiguration.get(context).scaledTouchSlop.toFloat()
        )
        var downRawX = 0f
        var downRawY = 0f
        var startParamX = 0
        var startParamY = 0
        var downTime = 0L
        var movedPastSlop = false
        var longPressTriggered = false

        val longPressRunnable = Runnable {
            if (!movedPastSlop && isDragging.not()) {
                longPressTriggered = true
                openSettingsActivity()
            }
        }

        view.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downRawX = event.rawX
                    downRawY = event.rawY
                    startParamX = params.x
                    startParamY = params.y
                    downTime = System.currentTimeMillis()
                    movedPastSlop = false
                    longPressTriggered = false
                    handler.postDelayed(longPressRunnable, 550L)
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - downRawX
                    val dy = event.rawY - downRawY
                    if (!movedPastSlop && (abs(dx) > slopPx || abs(dy) > slopPx)) {
                        movedPastSlop = true
                        isDragging = true
                        handler.removeCallbacks(longPressRunnable)
                        stopBreathing()
                    }
                    if (movedPastSlop) {
                        val screen = getScreenSizePx()
                        params.x = (startParamX + dx.roundToInt()).coerceIn(0, (screen.first - params.width).coerceAtLeast(0))
                        params.y = (startParamY + dy.roundToInt()).coerceIn(0, (screen.second - params.height).coerceAtLeast(0))
                        try {
                            windowManager.updateViewLayout(view, params)
                        } catch (_: Exception) {
                        }
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    handler.removeCallbacks(longPressRunnable)
                    val elapsed = System.currentTimeMillis() - downTime
                    if (movedPastSlop) {
                        isDragging = false
                        configStore.update { it.copy(savedX = params.x, savedY = params.y) }
                        if (currentConn.connected && currentConn.isMuted) {
                            startBreathing()
                        }
                    } else if (!longPressTriggered && elapsed < AppConstants.SHORT_TAP_MAX_MS) {
                        if (currentConfig.enableHudClickActions) {
                            connectionManager.toggleMuteFromHud()
                        }
                    }
                    true
                }
                MotionEvent.ACTION_CANCEL -> {
                    handler.removeCallbacks(longPressRunnable)
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

    private fun openSettingsActivity() {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        context.startActivity(intent)
    }

    private fun getScreenSizePx(): Pair<Int, Int> {
        val dm = context.resources.displayMetrics
        return dm.widthPixels to dm.heightPixels
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
