package com.saabithjiffry.presentersync.remote.ui.overlay

import android.content.Context
import android.graphics.PixelFormat
import android.provider.Settings
import android.view.Choreographer
import android.view.Gravity
import android.view.WindowManager
import com.saabithjiffry.presentersync.remote.config.FormFactorResolver
import com.saabithjiffry.presentersync.remote.config.HudColorPalettes
import com.saabithjiffry.presentersync.remote.config.RemoteConfig
import com.saabithjiffry.presentersync.remote.config.RemoteConfigStore
import com.saabithjiffry.presentersync.remote.config.ResolvedFormFactor
import com.saabithjiffry.presentersync.remote.ui.arcade.ArcadeOverlayHost
import kotlin.math.roundToInt

class HudSnakeOverlayManager(
    private val context: Context,
    private val configStore: RemoteConfigStore,
    private val onActiveChanged: (Boolean) -> Unit = {}
) {
    private val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private val choreographer = Choreographer.getInstance()

    val engine = HudSnakeEngine(
        onNewHighScore = { newBest ->
            configStore.updateSnakeHighScore(newBest)
        }
    )

    private var overlayView: HudSnakeOverlayView? = null
    private var attached = false
    private var currentConfig: RemoteConfig = configStore.current

    val isActive: Boolean
        get() = attached && engine.phase != SnakePhase.IDLE

    private val frameCallback = object : Choreographer.FrameCallback {
        override fun doFrame(frameTimeNanos: Long) {
            if (!attached || engine.phase == SnakePhase.IDLE) return
            engine.tick(frameTimeNanos)
            overlayView?.updateFrameState(currentConfig, resolveFormFactor(), frameTimeNanos)
            if (engine.phase == SnakePhase.MORPH ||
                engine.phase == SnakePhase.PLAYING ||
                (engine.phase == SnakePhase.GAME_OVER &&
                    (engine.popups.isNotEmpty() || engine.eatEffects.isNotEmpty()))
            ) {
                choreographer.postFrameCallback(this)
            }
        }
    }

    fun start(
        cfg: RemoteConfig,
        isMuted: Boolean,
        pillLeftScreenPx: Int,
        pillTopScreenPx: Int,
        pillWidthPx: Int,
        pillHeightPx: Int,
        skipMorph: Boolean = false
    ): Boolean {
        currentConfig = cfg
        if (!Settings.canDrawOverlays(context)) return false
        if (attached) {
            stop()
        }

        val bounds = ScreenBoundsCalculator.getSafeBoundsPx(context, windowManager)
        val density = context.resources.displayMetrics.density.coerceAtLeast(0.75f)
        val formFactor = resolveFormFactor()
        val pal = HudColorPalettes.get(cfg.hudColorPreset, cfg.customLiveHex, cfg.customMutedHex)
        val pillCol = if (isMuted) pal.mutedBg else pal.liveBg
        val nowNs = System.nanoTime()

        engine.start(
            workWidthPx = bounds.width,
            workHeightPx = bounds.height,
            density = density,
            formFactor = formFactor,
            hudScale = cfg.indicatorScale,
            initialHighScore = cfg.snakeHighScore,
            pillLeftPx = (pillLeftScreenPx - bounds.left).toFloat(),
            pillTopPx = (pillTopScreenPx - bounds.top).toFloat(),
            pillWidthPx = pillWidthPx.toFloat(),
            pillHeightPx = pillHeightPx.toFloat(),
            pillColorArgb = pillCol,
            nowNs = nowNs,
            skipMorph = skipMorph
        )

        val view = HudSnakeOverlayView(
            context = context,
            engine = engine,
            onExitRequested = { stop() },
            onStateInteracted = { scheduleFrameLoop() }
        )

        // Focusable (FLAG_NOT_FOCUSABLE intentionally omitted) while active so external Keyboard / D-Pad / Back key deliver directly
        val flags = ArcadeOverlayHost.computeWindowFlags(cfg.hideFromScreenCapture, cfg.keepScreenOn)

        val params = WindowManager.LayoutParams(
            bounds.width,
            bounds.height,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            flags,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = bounds.left
            y = bounds.top
        }

        return try {
            windowManager.addView(view, params)
            overlayView = view
            attached = true
            view.updateFrameState(cfg, formFactor, nowNs)
            view.requestFocus()
            onActiveChanged(true)
            scheduleFrameLoop()
            true
        } catch (_: Exception) {
            engine.stop()
            false
        }
    }

    fun updateConfig(cfg: RemoteConfig) {
        val prevHide = currentConfig.hideFromScreenCapture
        val prevKeep = currentConfig.keepScreenOn
        currentConfig = cfg
        if (!attached) return
        if (prevHide != cfg.hideFromScreenCapture || prevKeep != cfg.keepScreenOn) {
            val view = overlayView
            val lp = (view?.layoutParams as? WindowManager.LayoutParams)
            if (lp != null) {
                lp.flags = ArcadeOverlayHost.computeWindowFlags(cfg.hideFromScreenCapture, cfg.keepScreenOn)
                runCatching { windowManager.updateViewLayout(view, lp) }
            }
        }
        val bounds = ScreenBoundsCalculator.getSafeBoundsPx(context, windowManager)
        val density = context.resources.displayMetrics.density.coerceAtLeast(0.75f)
        val formFactor = resolveFormFactor()
        engine.updateDisplayLayout(bounds.width, bounds.height, density, formFactor, cfg.indicatorScale)
        overlayView?.updateFrameState(cfg, formFactor, System.nanoTime())
    }

    fun onDisplayConfigurationChanged() {
        if (!attached) return
        val bounds = ScreenBoundsCalculator.getSafeBoundsPx(context, windowManager)
        val density = context.resources.displayMetrics.density.coerceAtLeast(0.75f)
        val formFactor = resolveFormFactor()
        val view = overlayView ?: return
        val lp = (view.layoutParams as? WindowManager.LayoutParams) ?: return
        lp.width = bounds.width
        lp.height = bounds.height
        lp.x = bounds.left
        lp.y = bounds.top
        runCatching { windowManager.updateViewLayout(view, lp) }
        engine.updateDisplayLayout(bounds.width, bounds.height, density, formFactor, currentConfig.indicatorScale)
        view.updateFrameState(currentConfig, formFactor, System.nanoTime())
    }

    fun stop() {
        choreographer.removeFrameCallback(frameCallback)
        engine.stop()
        val v = overlayView
        overlayView = null
        val wasAttached = attached
        attached = false
        if (v != null) {
            v.releaseResources()
            runCatching { windowManager.removeViewImmediate(v) }
        }
        if (wasAttached) {
            onActiveChanged(false)
        }
    }

    internal fun viewForTesting(): HudSnakeOverlayView? = overlayView

    private fun scheduleFrameLoop() {
        choreographer.removeFrameCallback(frameCallback)
        if (attached && engine.phase != SnakePhase.IDLE) {
            choreographer.postFrameCallback(frameCallback)
        }
    }

    private fun resolveFormFactor(): ResolvedFormFactor {
        val bounds = ScreenBoundsCalculator.getSafeBoundsPx(context, windowManager)
        val density = context.resources.displayMetrics.density.coerceAtLeast(0.75f)
        val wDp = (bounds.width / density).roundToInt().coerceAtLeast(320)
        val hDp = (bounds.height / density).roundToInt().coerceAtLeast(320)
        val cfgMetrics = context.resources.configuration
        val swDp = if (cfgMetrics.smallestScreenWidthDp > 0) cfgMetrics.smallestScreenWidthDp else minOf(wDp, hDp)
        return FormFactorResolver.resolve(currentConfig.deviceProfileMode, wDp, hDp, swDp)
    }
}
