package com.saabithjiffry.presentersync.remote.ui.arcade

import android.content.Context
import android.graphics.PixelFormat
import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.Choreographer
import android.view.Gravity
import android.view.KeyEvent
import android.view.WindowManager
import com.saabithjiffry.presentersync.remote.config.FormFactorResolver
import com.saabithjiffry.presentersync.remote.config.RemoteConfig
import com.saabithjiffry.presentersync.remote.config.RemoteConfigStore
import com.saabithjiffry.presentersync.remote.config.ResolvedFormFactor
import com.saabithjiffry.presentersync.remote.ui.overlay.ScreenBoundsCalculator
import kotlin.math.roundToInt

/**
 * Shared overlay window host for all Sector Z games on Android (excluding legacy HUD Snake manager
 * which retains its own morph animation while sharing FLAG_SECURE logic via computeWindowFlags).
 */
class ArcadeOverlayHost(
    private val context: Context,
    private val configStore: RemoteConfigStore,
    private val onActiveChanged: (Boolean) -> Unit = {},
    private val onMuteKeyEvent: (KeyEvent) -> Boolean = { false }
) {
    private val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private val choreographer = Choreographer.getInstance()
    private val mainHandler = Handler(Looper.getMainLooper())

    private var activeGameId: String? = null
    private var activeView: ArcadeCanvasBaseView? = null
    private var frameStepper: ((Float) -> Unit)? = null
    private var resizeHandler: ((Int, Int, Float, ArcadeRectF?) -> Unit)? = null
    private var stopHandler: (() -> Unit)? = null
    private var attached = false
    private var currentConfig: RemoteConfig = configStore.current
    private var currentMuted: Boolean = false
    private var currentPillRect: ArcadeRectF? = null
    private var lastFrameNs: Long = 0L

    val isActive: Boolean
        get() = attached && activeView != null

    private val lockListener: () -> Unit = {
        mainHandler.post { stop() }
    }

    init {
        ArcadeVaultManager.registerLockListener(lockListener)
    }

    private val frameCallback = object : Choreographer.FrameCallback {
        override fun doFrame(frameTimeNanos: Long) {
            val view = activeView
            if (!attached || view == null) return
            val dtSec = if (lastFrameNs == 0L) 0.016f else ((frameTimeNanos - lastFrameNs) / 1_000_000_000f).coerceIn(0.001f, 0.05f)
            lastFrameNs = frameTimeNanos

            frameStepper?.invoke(dtSec)
            view.updateSharedState(currentConfig, resolveFormFactor(), currentMuted, currentPillRect, frameTimeNanos)
            choreographer.postFrameCallback(this)
        }
    }

    fun startGame(
        gameId: String,
        cfg: RemoteConfig,
        isMuted: Boolean,
        pillRectPx: Rect?
    ): Boolean {
        if (!ArcadeVaultManager.isUnlocked.value) return false
        if (!Settings.canDrawOverlays(context)) return false

        val cleanId = gameId.trim().lowercase()
        if (cleanId != "asteroids" && cleanId != "brick_breaker" && cleanId != "cyber_pong" && cleanId != "flappy") return false

        if (attached) {
            stop()
        }

        currentConfig = cfg
        currentMuted = isMuted
        val bounds = ScreenBoundsCalculator.getSafeBoundsPx(context, windowManager)
        val density = context.resources.displayMetrics.density.coerceIn(0.75f, 5f)
        val localBumper = pillRectPx?.let {
            ArcadeRectF(
                (it.left - bounds.left).toFloat(),
                (it.top - bounds.top).toFloat(),
                (it.right - bounds.left).toFloat(),
                (it.bottom - bounds.top).toFloat()
            )
        }
        currentPillRect = localBumper

        val formFactor = resolveFormFactor()
        val view: ArcadeCanvasBaseView
        val stepper: (Float) -> Unit
        val resizer: (Int, Int, Float, ArcadeRectF?) -> Unit
        val stopper: () -> Unit

        when (cleanId) {
            "asteroids" -> {
                val eng = AsteroidsEngine(
                    onNewHighScore = { newBest -> configStore.updateArcadeHighScore("asteroids", newBest) }
                )
                eng.startNewSession(
                    widthPx = bounds.width,
                    heightPx = bounds.height,
                    screenDensity = density,
                    initialHighScore = cfg.arcadeHighScores["asteroids"] ?: 0,
                    bumperRect = localBumper
                )
                view = AsteroidsOverlayView(
                    context = context,
                    engine = eng,
                    onExitRequested = { stop() },
                    onStateInteracted = { },
                    onMuteKeyEvent = onMuteKeyEvent
                )
                stepper = { dt -> eng.step(dt) }
                resizer = { w, h, d, b -> eng.updateDisplayMetrics(w, h, d, b) }
                stopper = { eng.stop() }
            }
            "brick_breaker" -> {
                val eng = BrickBreakerEngine(
                    onNewHighScore = { newBest -> configStore.updateArcadeHighScore("brick_breaker", newBest) }
                )
                eng.startNewSession(
                    widthPx = bounds.width,
                    heightPx = bounds.height,
                    screenDensity = density,
                    initialHighScore = cfg.arcadeHighScores["brick_breaker"] ?: 0,
                    bumperRect = localBumper
                )
                view = BrickBreakerOverlayView(
                    context = context,
                    engine = eng,
                    onExitRequested = { stop() },
                    onStateInteracted = { },
                    onMuteKeyEvent = onMuteKeyEvent
                )
                stepper = { dt -> eng.step(dt) }
                resizer = { w, h, d, b -> eng.updateDisplayMetrics(w, h, d, b) }
                stopper = { eng.stop() }
            }
            "cyber_pong" -> {
                val eng = CyberPongEngine(
                    onNewHighScore = { newBest -> configStore.updateArcadeHighScore("cyber_pong", newBest) }
                )
                eng.startNewSession(
                    widthPx = bounds.width,
                    heightPx = bounds.height,
                    screenDensity = density,
                    initialHighScore = cfg.arcadeHighScores["cyber_pong"] ?: 0
                )
                view = CyberPongOverlayView(
                    context = context,
                    engine = eng,
                    onExitRequested = { stop() },
                    onStateInteracted = { },
                    onMuteKeyEvent = onMuteKeyEvent
                )
                stepper = { dt -> eng.step(dt) }
                resizer = { w, h, d, _ -> eng.updateDisplayMetrics(w, h, d) }
                stopper = { eng.stop() }
            }
            else -> {
                val eng = FlappyWaveEngine(
                    onNewHighScore = { newBest -> configStore.updateArcadeHighScore("flappy", newBest) }
                )
                eng.startNewSession(
                    widthPx = bounds.width,
                    heightPx = bounds.height,
                    screenDensity = density,
                    initialHighScore = cfg.arcadeHighScores["flappy"] ?: 0,
                    bumperRect = localBumper
                )
                view = FlappyWaveOverlayView(
                    context = context,
                    engine = eng,
                    onExitRequested = { stop() },
                    onStateInteracted = { },
                    onMuteKeyEvent = onMuteKeyEvent
                )
                stepper = { dt -> eng.step(dt) }
                resizer = { w, h, d, b -> eng.updateDisplayMetrics(w, h, d, b) }
                stopper = { eng.stop() }
            }
        }

        val flags = computeWindowFlags(cfg.hideFromScreenCapture, cfg.keepScreenOn)
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
            frameStepper = stepper
            resizeHandler = resizer
            stopHandler = stopper
            activeGameId = cleanId
            activeView = view
            attached = true
            lastFrameNs = System.nanoTime()
            view.updateSharedState(cfg, formFactor, isMuted, localBumper, lastFrameNs)
            view.requestFocus()
            onActiveChanged(true)
            choreographer.removeFrameCallback(frameCallback)
            choreographer.postFrameCallback(frameCallback)
            true
        } catch (_: Exception) {
            stopper()
            false
        }
    }

    fun updateState(cfg: RemoteConfig, isMuted: Boolean) {
        val prevHide = currentConfig.hideFromScreenCapture
        val prevKeep = currentConfig.keepScreenOn
        currentConfig = cfg
        currentMuted = isMuted
        if (!attached) return
        val view = activeView ?: return
        if (prevHide != cfg.hideFromScreenCapture || prevKeep != cfg.keepScreenOn) {
            val lp = (view.layoutParams as? WindowManager.LayoutParams)
            if (lp != null) {
                lp.flags = computeWindowFlags(cfg.hideFromScreenCapture, cfg.keepScreenOn)
                runCatching { windowManager.updateViewLayout(view, lp) }
            }
        }
        view.updateSharedState(cfg, resolveFormFactor(), isMuted, currentPillRect, System.nanoTime())
    }

    fun onDisplayConfigurationChanged() {
        if (!attached) return
        val view = activeView ?: return
        val bounds = ScreenBoundsCalculator.getSafeBoundsPx(context, windowManager)
        val density = context.resources.displayMetrics.density.coerceIn(0.75f, 5f)
        val lp = (view.layoutParams as? WindowManager.LayoutParams) ?: return
        lp.width = bounds.width
        lp.height = bounds.height
        lp.x = bounds.left
        lp.y = bounds.top
        runCatching { windowManager.updateViewLayout(view, lp) }
        resizeHandler?.invoke(bounds.width, bounds.height, density, currentPillRect)
        view.updateSharedState(currentConfig, resolveFormFactor(), currentMuted, currentPillRect, System.nanoTime())
    }

    fun stop() {
        choreographer.removeFrameCallback(frameCallback)
        stopHandler?.invoke()
        stopHandler = null
        frameStepper = null
        resizeHandler = null
        activeGameId = null
        val v = activeView
        activeView = null
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

    fun destroy() {
        ArcadeVaultManager.unregisterLockListener(lockListener)
        stop()
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

    companion object {
        fun computeWindowFlags(hideFromScreenCapture: Boolean, keepScreenOn: Boolean): Int {
            var flags = WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
            if (hideFromScreenCapture) {
                flags = flags or WindowManager.LayoutParams.FLAG_SECURE
            }
            if (keepScreenOn) {
                flags = flags or WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            }
            return flags
        }
    }
}
