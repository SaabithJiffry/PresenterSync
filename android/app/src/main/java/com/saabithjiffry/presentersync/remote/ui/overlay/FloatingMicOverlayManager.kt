package com.saabithjiffry.presentersync.remote.ui.overlay

import android.content.Context
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
    private var quickMenuView: LinearLayout? = null
    private var attached = false
    private var isDragging = false
    private var isAutoDodged = false

    private var currentConfig: RemoteConfig = configStore.current
    private var currentConn: ConnectionUiState = connectionManager.uiState.value

    private var currentAlpha: Int = currentConfig.opacityLevel
    private var breathDir: Int = -AppConstants.PULSE_STEP_NORMAL
    private var animSeq = 0

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
            if (!attached || isDragging || isAutoDodged || !currentConfig.showIndicator || !currentConn.connected || !currentConn.isMuted) {
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

        if (!attached) {
            attachView()
        } else {
            updateDimensionsAndPosition()
        }

        syncTouchableFlag()

        if (!isDragging) {
            if (isAutoDodged) {
                stopBreathing()
                currentAlpha = min(cfg.opacityLevel, AppConstants.DODGE_ALPHA)
                pillView?.updateRenderState(cfg, conn, currentAlpha)
            } else if (!conn.connected || !conn.isMuted) {
                stopBreathing()
                currentAlpha = cfg.opacityLevel
                pillView?.updateRenderState(cfg, conn, currentAlpha)
            } else {
                pillView?.updateRenderState(cfg, conn, currentAlpha)
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
        isAutoDodged = false
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

    private fun attachView() {
        val view = MicPillCanvasView(context)
        val density = context.resources.displayMetrics.density
        val w = view.computeTargetWidthPx()
        val h = view.computeTargetHeightPx()

        val bounds = ScreenBoundsCalculator.getSafeBoundsPx(context, windowManager)
        val pos = ScreenBoundsCalculator.resolvePosition(
            savedX = currentConfig.savedX,
            savedY = currentConfig.savedY,
            bounds = bounds,
            viewWidthPx = w,
            viewHeightPx = h,
            marginXPx = (AppConstants.SCREEN_MARGIN_X * density).roundToInt(),
            marginYPx = (AppConstants.SCREEN_MARGIN_Y * density).roundToInt()
        )

        var baseFlags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
        if (currentConfig.hudClickThrough || isAutoDodged) {
            baseFlags = baseFlags or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
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
        }

        setupTouchHandling(view, params)
        setupHoverDodgeHandling(view)
        view.updateRenderState(currentConfig, currentConn, currentConfig.opacityLevel)

        try {
            windowManager.addView(view, params)
            pillView = view
            layoutParams = params
            attached = true
        } catch (_: Exception) {
        }
    }

    private fun syncTouchableFlag() {
        val view = pillView ?: return
        val params = layoutParams ?: return
        if (!attached) return

        val wantPassThrough = currentConfig.hudClickThrough || isAutoDodged
        val hasFlag = (params.flags and WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE) != 0
        if (wantPassThrough != hasFlag) {
            params.flags = if (wantPassThrough) {
                params.flags or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
            } else {
                params.flags and WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE.inv()
            }
            runCatching { windowManager.updateViewLayout(view, params) }
        }
    }

    private fun syncOverlayFlagsAndRender() {
        syncTouchableFlag()
        pillView?.updateRenderState(currentConfig, currentConn, currentAlpha)
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
        view.updateRenderState(currentConfig, currentConn, currentAlpha)
        val newW = view.computeTargetWidthPx()
        val newH = view.computeTargetHeightPx()
        val density = context.resources.displayMetrics.density
        val bounds = ScreenBoundsCalculator.getSafeBoundsPx(context, windowManager)

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
            marginYPx = (AppConstants.SCREEN_MARGIN_Y * density).roundToInt()
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
                showQuickMenu()
            }
        }

        view.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    dismissQuickMenu()
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
            setPadding(hp, vp, hp, vp)
        }
        container.addView(header)

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
        addMenuRow("Pointer Mute: ${if (currentConfig.enablePointerMute) "ON" else "OFF"}") {
            configStore.update { it.copy(enablePointerMute = !it.enablePointerMute) }
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

        val menuW = (240 * density).roundToInt()
        container.measure(
            View.MeasureSpec.makeMeasureSpec(menuW, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
        )
        val menuH = container.measuredHeight.coerceAtLeast((180 * density).roundToInt())

        val (anchor, pillH) = currentAnchorForToast()
        val bounds = ScreenBoundsCalculator.getSafeBoundsPx(context, windowManager)
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

        container.setOnTouchListener { _, ev ->
            if (ev.actionMasked == MotionEvent.ACTION_OUTSIDE) {
                dismissQuickMenu()
                true
            } else {
                false
            }
        }

        runCatching {
            windowManager.addView(container, menuParams)
            quickMenuView = container
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
