package com.saabithjiffry.presentersync.remote.ui.overlay

import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import com.saabithjiffry.presentersync.remote.config.AppConstants
import com.saabithjiffry.presentersync.remote.config.RemoteConfig
import com.saabithjiffry.presentersync.remote.config.RemoteConfigStore
import com.saabithjiffry.presentersync.remote.config.ThemeMode
import com.saabithjiffry.presentersync.remote.input.BubbleHoldStage
import com.saabithjiffry.presentersync.remote.input.GestureScheduler
import com.saabithjiffry.presentersync.remote.network.ConnectionManager
import com.saabithjiffry.presentersync.remote.network.ConnectionUiState
import com.saabithjiffry.presentersync.remote.ui.screens.MainActivity
import kotlin.math.abs
import kotlin.math.roundToInt

internal enum class ScenePillReleaseOutcome {
    TAP_TRANSITION,
    STAGE1_QUICK_MENU,
    STAGE2_ALREADY_TRIGGERED
}

/**
 * Pure two-stage press/hold recognizer for the standalone Scene HUD pill:
 * - Short release (<600ms) -> Transition Scene
 * - Hold 600ms..1399ms (Stage 1 Amber) -> release opens Scene-Only Quick Menu
 * - Hold >= 1400ms (Stage 2 Cyan) -> fires Reset Active Scene immediately, release is consumed
 */
internal class ScenePillHoldController(
    private val scheduler: GestureScheduler,
    private val stage1Ms: Long = STAGE1_HOLD_MS,
    private val stage2Ms: Long = STAGE2_HOLD_MS,
    private val onTapTransition: () -> Unit,
    private val onOpenSceneMenu: () -> Unit,
    private val onResetActiveScene: () -> Unit,
    private val onHoldStageUpdate: (BubbleHoldStage, Float) -> Unit
) {
    private var stage1Token: Any? = null
    private var stage2Token: Any? = null
    private var downActive = false
    private var reachedStage1 = false
    private var triggeredStage2 = false

    fun onDown() {
        cancelTimers()
        downActive = true
        reachedStage1 = false
        triggeredStage2 = false
        onHoldStageUpdate(BubbleHoldStage.IDLE, 0f)

        stage1Token = scheduler.schedule(stage1Ms) {
            stage1Token = null
            if (!downActive || triggeredStage2) return@schedule
            reachedStage1 = true
            onHoldStageUpdate(BubbleHoldStage.REACHED_LONG, 0.5f)
        }
        stage2Token = scheduler.schedule(stage2Ms) {
            stage2Token = null
            if (!downActive) return@schedule
            triggeredStage2 = true
            reachedStage1 = true
            onHoldStageUpdate(BubbleHoldStage.REACHED_VERY_LONG, 1f)
            onResetActiveScene()
        }
    }

    fun onDragCancelled() {
        cancelTimers()
        downActive = false
        reachedStage1 = false
        triggeredStage2 = false
        onHoldStageUpdate(BubbleHoldStage.IDLE, 0f)
    }

    fun onUp(): ScenePillReleaseOutcome {
        val wasStage1 = reachedStage1
        val wasStage2 = triggeredStage2
        val wasDown = downActive
        cancelTimers()
        downActive = false
        reachedStage1 = false
        triggeredStage2 = false
        onHoldStageUpdate(BubbleHoldStage.IDLE, 0f)
        if (!wasDown || wasStage2) {
            return ScenePillReleaseOutcome.STAGE2_ALREADY_TRIGGERED
        }
        return if (wasStage1) {
            onOpenSceneMenu()
            ScenePillReleaseOutcome.STAGE1_QUICK_MENU
        } else {
            onTapTransition()
            ScenePillReleaseOutcome.TAP_TRANSITION
        }
    }

    fun onCancel() = onDragCancelled()

    private fun cancelTimers() {
        stage1Token?.let { scheduler.cancel(it) }
        stage2Token?.let { scheduler.cancel(it) }
        stage1Token = null
        stage2Token = null
    }

    companion object {
        const val STAGE1_HOLD_MS = 600L
        const val STAGE2_HOLD_MS = 1400L
    }
}

class FloatingSceneOverlayManager(
    private val context: Context,
    private val configStore: RemoteConfigStore,
    private val connectionManager: ConnectionManager
) {
    private val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private val handler = Handler(Looper.getMainLooper())

    private var sceneView: ScenePillCanvasView? = null
    private var layoutParams: WindowManager.LayoutParams? = null
    private var quickMenuView: View? = null
    private var quickMenuParams: WindowManager.LayoutParams? = null
    private var attached = false
    private var hiddenForEasterEgg = false
    private var suppressedForPodium = false
    private val isOverlaySuppressed: Boolean
        get() = hiddenForEasterEgg || suppressedForPodium
    @Volatile
    private var isTouchActive = false
    private var isDragging = false

    private var currentConfig: RemoteConfig = configStore.current
    private var currentConn: ConnectionUiState = connectionManager.uiState.value
    private var activeHoldController: ScenePillHoldController? = null

    fun setHiddenForEasterEgg(hidden: Boolean) {
        if (hiddenForEasterEgg == hidden) return
        hiddenForEasterEgg = hidden
        applyOverlaySuppressionState()
    }

    fun setSuppressedForPodium(suppressed: Boolean) {
        if (suppressedForPodium == suppressed) return
        suppressedForPodium = suppressed
        applyOverlaySuppressionState()
    }

    private fun applyOverlaySuppressionState() {
        if (isOverlaySuppressed) {
            dismissQuickMenu()
            activeHoldController?.onCancel()
            sceneView?.visibility = if (suppressedForPodium) View.GONE else View.INVISIBLE
        } else {
            sceneView?.visibility = View.VISIBLE
            if (attached && currentConfig.showSceneIndicator) {
                showOrUpdate(currentConfig, currentConn)
            }
        }
    }

    fun onDisplayConfigurationChanged() {
        handler.post {
            if (attached) {
                updateDimensionsAndPosition()
            }
        }
    }

    fun reattachForDisplayRecovery() {
        handler.post {
            if (attached && currentConfig.showSceneIndicator) {
                hide()
                showOrUpdate(currentConfig, currentConn)
            }
        }
    }

    fun showOrUpdate(cfg: RemoteConfig, conn: ConnectionUiState) {
        currentConfig = cfg
        currentConn = conn

        if (!Settings.canDrawOverlays(context) || !cfg.showSceneIndicator) {
            hide()
            return
        }

        if (!attached) {
            attachView()
        } else {
            updateDimensionsAndPosition()
        }

        if (isOverlaySuppressed) {
            sceneView?.visibility = if (suppressedForPodium) View.GONE else View.INVISIBLE
            return
        }
        sceneView?.visibility = View.VISIBLE

        syncFlags()
        val bounds = ScreenBoundsCalculator.getSafeBoundsPx(context, windowManager)
        sceneView?.updateRenderState(cfg, conn, cfg.opacityLevel, bounds.width)
    }

    fun hide() {
        activeHoldController?.onCancel()
        activeHoldController = null
        isTouchActive = false
        isDragging = false
        dismissQuickMenu()
        if (attached && sceneView != null) {
            runCatching { windowManager.removeViewImmediate(sceneView) }
        }
        sceneView = null
        layoutParams = null
        attached = false
    }

    private fun resolveScenePosition(bounds: SafeRectPx, w: Int, h: Int, density: Float): OverlayPointPx {
        val marginXPx = (AppConstants.SCREEN_MARGIN_X * density).roundToInt()
        val marginYPx = (AppConstants.SCREEN_MARGIN_Y * density).roundToInt()
        if (currentConfig.sceneSavedX < 0 && currentConfig.sceneSavedY < 0 &&
            (currentConfig.sceneSavedXRatio < 0f || currentConfig.sceneSavedYRatio < 0f)
        ) {
            // Default Top-Start corner so Scene HUD never collides with Bottom-Right Mic Pill
            val x = (bounds.left + marginXPx).coerceIn(bounds.left, (bounds.right - w).coerceAtLeast(bounds.left))
            val y = (bounds.top + marginYPx).coerceIn(bounds.top, (bounds.bottom - h).coerceAtLeast(bounds.top))
            return OverlayPointPx(x, y)
        }
        return ScreenBoundsCalculator.resolvePosition(
            savedX = currentConfig.sceneSavedX,
            savedY = currentConfig.sceneSavedY,
            bounds = bounds,
            viewWidthPx = w,
            viewHeightPx = h,
            marginXPx = marginXPx,
            marginYPx = marginYPx,
            savedXRatio = currentConfig.sceneSavedXRatio,
            savedYRatio = currentConfig.sceneSavedYRatio
        )
    }

    private fun attachView() {
        val view = ScenePillCanvasView(context)
        val density = context.resources.displayMetrics.density
        val bounds = ScreenBoundsCalculator.getSafeBoundsPx(context, windowManager)
        view.updateRenderState(currentConfig, currentConn, currentConfig.opacityLevel, bounds.width)
        val w = view.computeTargetWidthPx(bounds.width)
        val h = view.computeTargetHeightPx(bounds.width)
        val pos = resolveScenePosition(bounds, w, h, density)

        val baseFlags = FloatingMicOverlayManager.computeOverlayFlags(
            baseFlags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            wantPassThrough = false,
            wantKeepScreenOn = currentConfig.keepScreenOn,
            hideFromScreenCapture = currentConfig.hideFromScreenCapture
        )

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
            alpha = 1.0f
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                layoutInDisplayCutoutMode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
                } else {
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
                }
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                fitInsetsTypes = 0
            }
        }

        setupTouchHandling(view, params)
        runCatching {
            windowManager.addView(view, params)
            sceneView = view
            layoutParams = params
            attached = true
        }
    }

    private fun syncFlags() {
        val view = sceneView ?: return
        val params = layoutParams ?: return
        if (!attached) return
        val desired = FloatingMicOverlayManager.computeOverlayFlags(
            baseFlags = params.flags,
            wantPassThrough = false,
            wantKeepScreenOn = currentConfig.keepScreenOn,
            hideFromScreenCapture = currentConfig.hideFromScreenCapture
        )
        if (desired != params.flags) {
            params.flags = desired
            runCatching { windowManager.updateViewLayout(view, params) }
        }
    }

    private fun updateDimensionsAndPosition() {
        val view = sceneView ?: return
        val params = layoutParams ?: return
        val density = context.resources.displayMetrics.density
        val bounds = ScreenBoundsCalculator.getSafeBoundsPx(context, windowManager)
        view.updateRenderState(currentConfig, currentConn, currentConfig.opacityLevel, bounds.width)
        val newW = view.computeTargetWidthPx(bounds.width)
        val newH = view.computeTargetHeightPx(bounds.width)

        var changed = false
        if (params.width != newW || params.height != newH) {
            params.width = newW
            params.height = newH
            changed = true
        }

        val target = resolveScenePosition(bounds, newW, newH, density)
        if (!isTouchActive && !isDragging && (params.x != target.x || params.y != target.y)) {
            params.x = target.x
            params.y = target.y
            changed = true
        }

        if (changed && attached) {
            runCatching { windowManager.updateViewLayout(view, params) }
        }
    }

    private fun setupTouchHandling(view: ScenePillCanvasView, params: WindowManager.LayoutParams) {
        val density = context.resources.displayMetrics.density
        val slopPx = (AppConstants.SHORT_TAP_MAX_SLOP_DP * density).coerceAtLeast(
            ViewConfiguration.get(context).scaledTouchSlop * 1.5f
        )
        val lockCancelSlopPx = (56f * density).coerceAtLeast(slopPx * 2.5f)
        var downRawX = 0f
        var downRawY = 0f
        var startParamX = 0
        var startParamY = 0
        var movedPastSlop = false
        var holdTickRunnable: Runnable? = null

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

        fun stopHoldTick() {
            holdTickRunnable?.let { handler.removeCallbacks(it) }
            holdTickRunnable = null
            view.setHoldVisualState(BubbleHoldStage.IDLE, 0f)
        }

        val holdCtrl = ScenePillHoldController(
            scheduler = scheduler,
            onTapTransition = {
                view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                connectionManager.sendTransitionScene("scene_hud")
            },
            onOpenSceneMenu = {
                view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                showSceneQuickMenu()
            },
            onResetActiveScene = {
                view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
                if (connectionManager.sendResetActiveScene("scene_hud")) {
                    Toast.makeText(context, "Resetting active scene sources...", Toast.LENGTH_SHORT).show()
                }
            },
            onHoldStageUpdate = { st, prog -> view.setHoldVisualState(st, prog) }
        )
        activeHoldController = holdCtrl

        fun startHoldTick() {
            stopHoldTick()
            val holdStartedMs = SystemClock.uptimeMillis()
            val ticker = object : Runnable {
                override fun run() {
                    if (!isTouchActive || isDragging) {
                        stopHoldTick()
                        return
                    }
                    val elapsed = (SystemClock.uptimeMillis() - holdStartedMs).coerceAtLeast(0L)
                    if (elapsed >= ScenePillHoldController.STAGE2_HOLD_MS) {
                        view.setHoldVisualState(BubbleHoldStage.REACHED_VERY_LONG, 1f)
                        return
                    }
                    val stage = if (elapsed >= ScenePillHoldController.STAGE1_HOLD_MS) {
                        BubbleHoldStage.PROGRESS_VERY_LONG
                    } else {
                        BubbleHoldStage.PROGRESS_LONG
                    }
                    val frac = if (elapsed < ScenePillHoldController.STAGE1_HOLD_MS) {
                        elapsed.toFloat() / ScenePillHoldController.STAGE1_HOLD_MS.toFloat()
                    } else {
                        (elapsed - ScenePillHoldController.STAGE1_HOLD_MS).toFloat() /
                            (ScenePillHoldController.STAGE2_HOLD_MS - ScenePillHoldController.STAGE1_HOLD_MS).toFloat()
                    }
                    view.setHoldVisualState(stage, frac.coerceIn(0f, 1f))
                    handler.postDelayed(this, 40L)
                }
            }
            holdTickRunnable = ticker
            handler.postDelayed(ticker, 48L)
        }

        view.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    val formFactor = ScreenBoundsCalculator.resolveFormFactor(context, currentConfig.deviceProfileMode).deviceClass
                    if (ScreenBoundsCalculator.isPalmTouchForDevice(event.getToolType(0), event.touchMajor, density, formFactor)) {
                        return@setOnTouchListener false
                    }
                    isTouchActive = true
                    dismissQuickMenu()
                    downRawX = event.rawX
                    downRawY = event.rawY
                    startParamX = params.x
                    startParamY = params.y
                    movedPastSlop = false
                    holdCtrl.onDown()
                    startHoldTick()
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - downRawX
                    val dy = event.rawY - downRawY
                    if (currentConfig.lockHudPosition) {
                        if (!movedPastSlop && (abs(dx) > lockCancelSlopPx || abs(dy) > lockCancelSlopPx)) {
                            movedPastSlop = true
                            stopHoldTick()
                            holdCtrl.onDragCancelled()
                        }
                        return@setOnTouchListener true
                    }
                    if (!movedPastSlop && (abs(dx) > slopPx || abs(dy) > slopPx)) {
                        movedPastSlop = true
                        isDragging = true
                        stopHoldTick()
                        holdCtrl.onDragCancelled()
                    }
                    if (movedPastSlop) {
                        val bounds = ScreenBoundsCalculator.getSafeBoundsPx(context, windowManager)
                        val minX = bounds.left
                        val maxX = (bounds.right - params.width).coerceAtLeast(minX)
                        val minY = bounds.top
                        val maxY = (bounds.bottom - params.height).coerceAtLeast(minY)
                        params.x = (startParamX + dx.roundToInt()).coerceIn(minX, maxX)
                        params.y = (startParamY + dy.roundToInt()).coerceIn(minY, maxY)
                        runCatching { windowManager.updateViewLayout(view, params) }
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    isTouchActive = false
                    stopHoldTick()
                    if (isDragging) {
                        isDragging = false
                        val bounds = ScreenBoundsCalculator.getSafeBoundsPx(context, windowManager)
                        if (currentConfig.enableMagneticSnap) {
                            val snapped = ScreenBoundsCalculator.computeMagneticSnap(
                                rawX = params.x,
                                rawY = params.y,
                                viewWidthPx = params.width,
                                viewHeightPx = params.height,
                                bounds = bounds,
                                thresholdPx = (AppConstants.SNAP_THRESHOLD_DP * density).roundToInt()
                            )
                            params.x = snapped.x
                            params.y = snapped.y
                            runCatching { windowManager.updateViewLayout(view, params) }
                        }
                        val (rx, ry) = ScreenBoundsCalculator.computePositionRatios(
                            x = params.x,
                            y = params.y,
                            bounds = bounds,
                            viewWidthPx = params.width,
                            viewHeightPx = params.height
                        )
                        configStore.update {
                            it.copy(
                                sceneSavedX = params.x,
                                sceneSavedY = params.y,
                                sceneSavedXRatio = rx,
                                sceneSavedYRatio = ry
                            )
                        }
                        holdCtrl.onDragCancelled()
                    } else {
                        holdCtrl.onUp()
                    }
                    true
                }
                MotionEvent.ACTION_CANCEL -> {
                    isTouchActive = false
                    stopHoldTick()
                    isDragging = false
                    holdCtrl.onCancel()
                    true
                }
                else -> false
            }
        }
    }

    private fun showSceneQuickMenu() {
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
        val accentColor = if (isDark) Color.parseColor("#38BDF8") else Color.parseColor("#0067C0")

        val container = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            val pad = (6 * density).roundToInt()
            setPadding(pad, pad, pad, pad)
        }

        val header = TextView(context).apply {
            text = "Scene Quick Menu • ${currentConn.activeScene}"
            setTextColor(accentColor)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            setPadding((10 * density).roundToInt(), (6 * density).roundToInt(), (10 * density).roundToInt(), (6 * density).roundToInt())
        }
        container.addView(header)

        fun addMenuRow(label: String, onClick: () -> Unit) {
            val div = View(context).apply { setBackgroundColor(dividerColor) }
            container.addView(div, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 1))
            val row = TextView(context).apply {
                text = label
                setTextColor(textColor)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 13.5f)
                setPadding((12 * density).roundToInt(), (10 * density).roundToInt(), (12 * density).roundToInt(), (10 * density).roundToInt())
                isClickable = true
                setOnClickListener {
                    dismissQuickMenu()
                    onClick()
                }
            }
            container.addView(row, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
        }

        if (!currentConn.isTallyOnly) {
            addMenuRow("⇄ Transition Scene (Preview ↔ Program)") {
                connectionManager.sendTransitionScene("scene_quick_menu")
            }
            addMenuRow("↺ Reset Active Scene Sources") {
                connectionManager.sendResetActiveScene("scene_quick_menu")
            }
            for (sceneName in currentConn.scenes) {
                val prefix = if (sceneName == currentConn.activeScene) "● " else ""
                addMenuRow("${prefix}Switch to: $sceneName") {
                    connectionManager.sendSwitchScene(sceneName, "scene_quick_menu")
                }
            }
        } else {
            addMenuRow("Read-Only Tally Mode (Controls Locked)") { }
        }
        addMenuRow("Flip Opposite Corner") {
            val lp = layoutParams ?: return@addMenuRow
            val sv = sceneView ?: return@addMenuRow
            val bounds = ScreenBoundsCalculator.getSafeBoundsPx(context, windowManager)
            val flipped = ScreenBoundsCalculator.computeOppositeCornerFlip(lp.x, lp.y, lp.width, lp.height, bounds)
            lp.x = flipped.x
            lp.y = flipped.y
            runCatching { windowManager.updateViewLayout(sv, lp) }
            val (rx, ry) = ScreenBoundsCalculator.computePositionRatios(lp.x, lp.y, bounds, lp.width, lp.height)
            configStore.update { it.copy(sceneSavedX = lp.x, sceneSavedY = lp.y, sceneSavedXRatio = rx, sceneSavedYRatio = ry) }
        }
        addMenuRow("Hide Scene Pill") {
            configStore.update { it.copy(showSceneIndicator = false) }
        }
        addMenuRow("Open Full Settings...") {
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            context.startActivity(intent)
        }

        val bounds = ScreenBoundsCalculator.getSafeBoundsPx(context, windowManager)
        val menuW = (248 * density).roundToInt().coerceAtMost((bounds.width - (16 * density).roundToInt()).coerceAtLeast((180 * density).roundToInt()))
        container.measure(
            View.MeasureSpec.makeMeasureSpec(menuW, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
        )
        val maxH = (bounds.height - (16 * density).roundToInt()).coerceAtLeast((160 * density).roundToInt())
        val menuH = container.measuredHeight.coerceIn((140 * density).roundToInt().coerceAtMost(maxH), maxH)

        val menuRoot = ScrollView(context).apply {
            isVerticalScrollBarEnabled = true
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = 8f * density
                setColor(surfaceBg)
                setStroke((1f * density).roundToInt().coerceAtLeast(1), borderStroke)
            }
            addView(container, android.view.ViewGroup.LayoutParams(android.view.ViewGroup.LayoutParams.MATCH_PARENT, android.view.ViewGroup.LayoutParams.WRAP_CONTENT))
        }

        val lp = layoutParams
        val anchorX = lp?.x ?: bounds.left
        val anchorY = lp?.y ?: bounds.top
        val anchorH = lp?.height ?: 48
        val gap = (8 * density).roundToInt()
        val preferBelow = anchorY + anchorH + gap
        val targetY = if (preferBelow + menuH <= bounds.bottom) preferBelow else (anchorY - menuH - gap).coerceIn(bounds.top, (bounds.bottom - menuH).coerceAtLeast(bounds.top))
        val targetX = anchorX.coerceIn(bounds.left, (bounds.right - menuW).coerceAtLeast(bounds.left))

        val menuParams = WindowManager.LayoutParams(
            menuW,
            menuH,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                (if (currentConfig.hideFromScreenCapture) WindowManager.LayoutParams.FLAG_SECURE else 0),
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = targetX
            y = targetY
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                layoutInDisplayCutoutMode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
                } else {
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
                }
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                fitInsetsTypes = 0
            }
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
            quickMenuParams = menuParams
        }
    }

    private fun dismissQuickMenu() {
        val mv = quickMenuView ?: return
        quickMenuView = null
        quickMenuParams = null
        runCatching { windowManager.removeViewImmediate(mv) }
    }
}
