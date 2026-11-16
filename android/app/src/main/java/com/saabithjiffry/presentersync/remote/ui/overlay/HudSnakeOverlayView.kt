package com.saabithjiffry.presentersync.remote.ui.overlay

import android.content.Context
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.DashPathEffect
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Typeface
import android.view.HapticFeedbackConstants
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import com.saabithjiffry.presentersync.remote.config.HudColorPalette
import com.saabithjiffry.presentersync.remote.config.HudColorPalettes
import com.saabithjiffry.presentersync.remote.config.RemoteConfig
import com.saabithjiffry.presentersync.remote.config.ResolvedFormFactor
import com.saabithjiffry.presentersync.remote.config.ThemeMode
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt

class HudSnakeOverlayView(
    context: Context,
    private val engine: HudSnakeEngine,
    private val onExitRequested: () -> Unit,
    private val onStateInteracted: () -> Unit = {}
) : View(context) {

    private var config: RemoteConfig = RemoteConfig()
    private var formFactor: ResolvedFormFactor? = null
    private var nowNs: Long = System.nanoTime()

    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
    private val dashEdgePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.NORMAL)
    }
    private val boldPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
    }

    private val snakeRimPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    private val snakeFillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    private val layerBlitPaint = Paint(Paint.FILTER_BITMAP_FLAG)

    private val workRect = RectF()
    private val workClipPath = Path()
    private val snakePath = Path()
    private val dashEffectCache = mutableMapOf<Float, DashPathEffect>()

    private var snakeLayerBitmap: Bitmap? = null
    private var snakeLayerCanvas: Canvas? = null
    private var prevDirtyBounds: Rect? = null

    private enum class ActionButtonId {
        SB_MODE,
        SB_PAUSE,
        SB_EXIT,
        BANNER_PRIMARY,
        BANNER_EDGE,
        BANNER_EXIT
    }

    private val buttonRects = mutableMapOf<ActionButtonId, RectF>()
    private var pressedBtn: ActionButtonId? = null
    private var swipeRefX = 0f
    private var swipeRefY = 0f
    private var lastStickDir: Pair<Int, Int>? = null

    init {
        isFocusable = true
        isFocusableInTouchMode = true
        contentDescription = "PresenterSync HUD Snake Overlay"
    }

    fun updateFrameState(cfg: RemoteConfig, resolvedFormFactor: ResolvedFormFactor, frameTimeNs: Long) {
        config = cfg
        formFactor = resolvedFormFactor
        nowNs = frameTimeNs
        invalidate()
    }

    fun releaseResources() {
        snakeLayerCanvas = null
        snakeLayerBitmap?.recycle()
        snakeLayerBitmap = null
        prevDirtyBounds = null
        buttonRects.clear()
    }

    override fun onDetachedFromWindow() {
        releaseResources()
        super.onDetachedFromWindow()
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        val cmd = HudSnakeEngine.mapKeyCodeToCommand(keyCode) ?: return super.onKeyDown(keyCode, event)
        if (cmd is SnakeInputCommand.Exit) {
            engine.stop()
            onExitRequested()
            return true
        }
        val frameNs = System.nanoTime()
        engine.handleInputCommand(cmd, frameNs)
        nowNs = frameNs
        onStateInteracted()
        invalidate()
        return true
    }

    override fun onGenericMotionEvent(event: MotionEvent): Boolean {
        val isJoystick = (event.source and InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK ||
            (event.source and InputDevice.SOURCE_GAMEPAD) == InputDevice.SOURCE_GAMEPAD ||
            (event.source and InputDevice.SOURCE_DPAD) == InputDevice.SOURCE_DPAD
        if (!isJoystick || event.actionMasked != MotionEvent.ACTION_MOVE) {
            return super.onGenericMotionEvent(event)
        }
        val dir = HudSnakeEngine.decodeJoystickAxis(
            axisX = event.getAxisValue(MotionEvent.AXIS_X),
            axisY = event.getAxisValue(MotionEvent.AXIS_Y),
            hatX = event.getAxisValue(MotionEvent.AXIS_HAT_X),
            hatY = event.getAxisValue(MotionEvent.AXIS_HAT_Y)
        )
        if (dir != null) {
            if (dir != lastStickDir) {
                lastStickDir = dir
                if (engine.queueDirection(dir.first, dir.second)) {
                    onStateInteracted()
                    invalidate()
                }
            }
        } else {
            lastStickDir = null
        }
        return true
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        val g = engine.grid
        val d = g.density
        val hitSlop = 10f * d

        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                val matched = buttonRects.entries.firstOrNull { (_, r) ->
                    r.containsExpanded(event.x, event.y, hitSlop)
                }?.key
                pressedBtn = matched
                swipeRefX = event.x
                swipeRefY = event.y
                if (matched != null) {
                    invalidate()
                }
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                if (pressedBtn == null && (engine.phase == SnakePhase.PLAYING || engine.phase == SnakePhase.MORPH)) {
                    val minSwipePx = max(22f * d, g.cellPx * 0.68f)
                    val swipeDir = HudSnakeEngine.decodeSwipeDirection(
                        dxPx = event.x - swipeRefX,
                        dyPx = event.y - swipeRefY,
                        minSwipePx = minSwipePx
                    )
                    if (swipeDir != null) {
                        engine.queueDirection(swipeDir.first, swipeDir.second)
                        swipeRefX = event.x
                        swipeRefY = event.y
                        onStateInteracted()
                        invalidate()
                    }
                }
                return true
            }
            MotionEvent.ACTION_UP -> {
                val activeBtn = pressedBtn
                pressedBtn = null
                if (activeBtn != null) {
                    val targetRect = buttonRects[activeBtn]
                    if (targetRect != null && targetRect.containsExpanded(event.x, event.y, hitSlop)) {
                        performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                        triggerActionButton(activeBtn)
                    } else {
                        invalidate()
                    }
                }
                return true
            }
            MotionEvent.ACTION_CANCEL -> {
                if (pressedBtn != null) {
                    pressedBtn = null
                    invalidate()
                }
                return true
            }
        }
        return super.onTouchEvent(event)
    }

    private fun triggerActionButton(btn: ActionButtonId) {
        val frameNs = System.nanoTime()
        when (btn) {
            ActionButtonId.SB_MODE, ActionButtonId.BANNER_EDGE -> engine.toggleEdgeMode()
            ActionButtonId.SB_PAUSE, ActionButtonId.BANNER_PRIMARY -> engine.togglePause(frameNs)
            ActionButtonId.SB_EXIT, ActionButtonId.BANNER_EXIT -> {
                engine.stop()
                onExitRequested()
                return
            }
        }
        nowNs = frameNs
        onStateInteracted()
        invalidate()
    }

    private fun RectF.containsExpanded(x: Float, y: Float, pad: Float): Boolean {
        return x >= (left - pad) && x <= (right + pad) && y >= (top - pad) && y <= (bottom + pad)
    }

    private fun isDarkMode(): Boolean {
        return when (config.themeMode) {
            ThemeMode.DARK -> true
            ThemeMode.LIGHT -> false
            ThemeMode.SYSTEM -> {
                val night = resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
                night != Configuration.UI_MODE_NIGHT_NO
            }
        }
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (width <= 0 || height <= 0 || engine.phase == SnakePhase.IDLE) return

        val palette = HudColorPalettes.get(config.hudColorPreset, config.customLiveHex, config.customMutedHex)
        val isDark = isDarkMode()
        val g = engine.grid
        val opacity = config.opacityLevel.coerceIn(72, 255)
        buttonRects.clear()

        // 1. Minimalist Play-Area Perimeter Border (Solid for WALLS, Dashed for WRAP)
        drawEdgeHints(canvas, palette, isDark, g, opacity)

        // 2. Eat Rings & Food (Normal Squircle + Timed Bonus Star)
        if (engine.phase != SnakePhase.MORPH) {
            drawEatEffects(canvas, palette, g, opacity)
            engine.food?.let { drawFood(canvas, it, palette, isDark, g, opacity) }
        }

        // 3. Seamless Unified Matte-Glass Snake Ribbon (or Morphing Pills)
        if (engine.phase == SnakePhase.MORPH) {
            drawMorphTransition(canvas, palette, isDark, g, opacity)
        } else {
            drawContinuousSnake(canvas, palette, isDark, g, opacity)
        }

        // 4. Floating Eat Score Popups (+10 / +30)
        drawPopups(canvas, g)

        // 5. Top-Center Win11 Explorer Scoreboard Pill (wraps cleanly on Phone Portrait)
        drawScoreboard(canvas, palette, isDark, g, opacity)

        // 6. Pause / Game Over Matte Card with Touch Chips & Keycap Hints
        if (engine.phase == SnakePhase.PAUSED || engine.phase == SnakePhase.GAME_OVER) {
            drawStatusBanner(canvas, palette, isDark, g, opacity)
        }
    }

    private fun drawEdgeHints(
        canvas: Canvas,
        palette: HudColorPalette,
        isDark: Boolean,
        g: SnakeGridMetrics,
        opacity: Int
    ) {
        val d = g.density
        val left = g.gridOffX.toFloat()
        val top = g.gridOffY.toFloat()
        val w = (g.cols * g.cellPx).toFloat()
        val h = (g.rows * g.cellPx).toFloat()
        val isDeadWall = (engine.phase == SnakePhase.GAME_OVER && engine.deathReason == SnakeDeathReason.WALL)

        val borderAlpha = if (isDeadWall) 225 else max(68, (opacity * 0.42f).roundToInt())
        val baseRgb = when {
            isDeadWall -> palette.mutedBg
            engine.edgeWrap -> if (isDark) 0xFF60CDFF.toInt() else 0xFF0067C0.toInt()
            isDark -> 0xFF94A3B8.toInt()
            else -> 0xFF475569.toInt()
        }
        val colorArgb = withAlpha(baseRgb, borderAlpha)
        val strokeW = (if (isDeadWall) 2.2f else 1.2f) * d
        val cornerR = if (config.sleekCorners) 14f * d else 6f * d

        workRect.set(left, top, left + w, top + h)
        if (engine.edgeWrap) {
            val dashKey = 8f * d
            val effect = dashEffectCache.getOrPut(dashKey) {
                DashPathEffect(floatArrayOf(dashKey, 6f * d), 0f)
            }
            dashEdgePaint.color = colorArgb
            dashEdgePaint.strokeWidth = strokeW
            dashEdgePaint.pathEffect = effect
            canvas.drawRoundRect(workRect, cornerR, cornerR, dashEdgePaint)
        } else {
            strokePaint.color = colorArgb
            strokePaint.strokeWidth = strokeW
            strokePaint.pathEffect = null
            canvas.drawRoundRect(workRect, cornerR, cornerR, strokePaint)
        }
    }

    private fun drawFood(
        canvas: Canvas,
        food: SnakeFood,
        palette: HudColorPalette,
        isDark: Boolean,
        g: SnakeGridMetrics,
        opacity: Int
    ) {
        val d = g.density
        val cx = g.gridOffX + (food.col + 0.5f) * g.cellPx
        val cy = g.gridOffY + (food.row + 0.5f) * g.cellPx
        val isBonus = (food.kind == SnakeFoodKind.BONUS)

        val sz = g.cellPx * (if (isBonus) 1.42f else 0.70f)
        val foodX = cx - sz / 2f
        val foodY = cy - sz / 2f
        val rad = if (config.sleekCorners) sz / 2f else min((if (isBonus) 13f else 7.5f) * d, sz * 0.34f)

        val bodyRgb: Int
        val monoSrc: Int
        if (isBonus) {
            bodyRgb = palette.recPausedBg
            monoSrc = palette.recPausedIcon
        } else {
            val prefRgb = if ((palette.mutedBg and 0xFFFFFF) != (palette.liveBg and 0xFFFFFF)) {
                palette.chatAlertBg
            } else {
                palette.mutedBg
            }
            bodyRgb = if ((prefRgb and 0xFFFFFF) == (palette.liveBg and 0xFFFFFF)) palette.mutedBg else prefRgb
            monoSrc = if ((bodyRgb and 0xFFFFFF) == (palette.chatAlertBg and 0xFFFFFF)) {
                palette.chatAlertIcon
            } else {
                palette.mutedIcon
            }
        }

        val rimRgb = lightenRgb(bodyRgb, 0.25f)
        val pipRgb = pickBadgeContentRgb(bodyRgb, monoSrc, config.monoIcon, isDark, opacity)

        if (isBonus) {
            val haloPad = 2.4f * d
            val haloRad = if (config.sleekCorners) (sz + haloPad * 2f) / 2f else rad + haloPad * 0.6f
            workRect.set(foodX - haloPad, foodY - haloPad, foodX + sz + haloPad, foodY + sz + haloPad)
            strokePaint.color = withAlpha(rimRgb, max(75, (opacity * 0.45f).roundToInt()))
            strokePaint.strokeWidth = 1.6f * d
            canvas.drawRoundRect(workRect, haloRad, haloRad, strokePaint)
        }

        workRect.set(foodX, foodY, foodX + sz, foodY + sz)
        fillPaint.color = withAlpha(bodyRgb, opacity)
        canvas.drawRoundRect(workRect, rad, rad, fillPaint)

        val barH = if (isBonus) max(3.2f, 4.4f * d) else 0f
        if (isBonus && food.kind.ttlMs > 0L) {
            val remFrac = (1f - (nowNs - food.bornNs).toFloat() / (food.kind.ttlMs * 1_000_000f)).coerceIn(0f, 1f)
            if (remFrac > 0.01f) {
                canvas.save()
                workClipPath.reset()
                workClipPath.addRoundRect(workRect, rad, rad, Path.Direction.CW)
                canvas.clipPath(workClipPath)
                fillPaint.color = 0xEBFFFFFF.toInt()
                val barW = max(3f, (sz - 2f) * remFrac)
                canvas.drawRect(
                    foodX + 1f,
                    foodY + sz - barH - 0.5f,
                    foodX + 1f + barW,
                    foodY + sz,
                    fillPaint
                )
                canvas.restore()
            }
        }

        strokePaint.color = withAlpha(rimRgb, min(255, opacity + 30))
        strokePaint.strokeWidth = (if (isBonus) 1.8f else 1.4f) * d
        canvas.drawRoundRect(workRect, rad, rad, strokePaint)

        val pipArgb = withAlpha(pipRgb, opacity.coerceIn(180, 245))
        if (isBonus) {
            boldPaint.color = pipArgb
            boldPaint.textAlign = Paint.Align.CENTER
            boldPaint.textSize = max(14f * d, sz * 0.44f)
            val fm = boldPaint.fontMetrics
            val centerY = foodY + (sz - barH) / 2f - (fm.ascent + fm.descent) / 2f
            canvas.drawText("★", cx, centerY, boldPaint)
        } else {
            val dotR = max(2f, sz * 0.14f)
            fillPaint.color = pipArgb
            canvas.drawCircle(cx, cy, dotR, fillPaint)
        }
    }

    private fun drawEatEffects(canvas: Canvas, palette: HudColorPalette, g: SnakeGridMetrics, opacity: Int) {
        val d = g.density
        for (eff in engine.eatEffects) {
            val frac = ((nowNs - eff.bornNs) / 380_000_000f).coerceIn(0f, 1f)
            if (frac >= 1f) continue
            val ease = 1f - (1f - frac).pow(2f)
            val sz = g.cellPx * (0.76f + 0.55f * ease)
            val cx = g.gridOffX + (eff.col + 0.5f) * g.cellPx
            val cy = g.gridOffY + (eff.row + 0.5f) * g.cellPx
            val rad = if (config.sleekCorners) sz / 2f else min(8f * d, sz * 0.35f)
            val rgb = if (eff.kind == SnakeFoodKind.BONUS) palette.recPausedBg else palette.liveBg
            val alpha = max(1, (opacity * 0.65f * (1f - frac)).roundToInt())
            workRect.set(cx - sz / 2f, cy - sz / 2f, cx + sz / 2f, cy + sz / 2f)
            strokePaint.color = withAlpha(rgb, alpha)
            strokePaint.strokeWidth = max(1.2f, 2.2f * d * (1f - frac * 0.5f))
            canvas.drawRoundRect(workRect, rad, rad, strokePaint)
        }
    }

    private fun drawMorphTransition(
        canvas: Canvas,
        palette: HudColorPalette,
        isDark: Boolean,
        g: SnakeGridMetrics,
        opacity: Int
    ) {
        val d = g.density
        val lin = ((nowNs - engine.morphStartNs).toFloat() / (HudSnakeEngine.MORPH_DURATION_MS * 1_000_000f))
            .coerceIn(0f, 1f)
        val morphFrac = 1f - (1f - lin).pow(3f)
        val tubeW = g.cellPx * 0.70f
        val radTarget = if (config.sleekCorners) tubeW / 2f else min(8f * d, tubeW * 0.42f)

        val liveBody = palette.liveBg
        val rimRgb = lightenRgb(liveBody, 0.22f)

        if (lin < 0.85f) {
            val seedAlpha = max(40, (opacity * (1f - lin * 0.22f)).roundToInt())
            for (seed in engine.morphSeeds) {
                val tx = g.gridOffX + (seed.targetCol + 0.5f) * g.cellPx - tubeW / 2f
                val ty = g.gridOffY + (seed.targetRow + 0.5f) * g.cellPx - tubeW / 2f
                val sx = seed.x + (tx - seed.x) * morphFrac
                val sy = seed.y + (ty - seed.y) * morphFrac
                val sw = seed.w + (tubeW - seed.w) * morphFrac
                val sh = seed.h + (tubeW - seed.h) * morphFrac
                val radStart = min(sh / 2f, if (config.sleekCorners) sh / 2f else 8f * d)
                val rad = radStart + (radTarget - radStart) * morphFrac

                workRect.set(sx, sy, sx + sw, sy + sh)
                fillPaint.color = withAlpha(seed.colorArgb, seedAlpha)
                canvas.drawRoundRect(workRect, rad, rad, fillPaint)
                strokePaint.color = withAlpha(rimRgb, min(255, seedAlpha + 25))
                strokePaint.strokeWidth = 1.4f * d
                canvas.drawRoundRect(workRect, rad, rad, strokePaint)
            }
        }

        if (lin > 0.78f) {
            val blendIn = ((lin - 0.78f) / 0.22f).coerceIn(0f, 1f)
            val ribbonAlpha = max(25, (opacity * blendIn).roundToInt())
            drawContinuousSnake(canvas, palette, isDark, g, ribbonAlpha)
        }
    }

    private fun resolveSnakeColors(palette: HudColorPalette, isDark: Boolean, opacity: Int): Triple<Int, Int, Int> {
        val isStealth = config.hudColorPreset.equals("OLED Stealth", ignoreCase = true)
        return if (engine.phase == SnakePhase.GAME_OVER) {
            val fill = palette.mutedBg
            val rim = if (isStealth) palette.mutedIcon else lightenRgb(fill, 0.22f)
            val eye = pickBadgeContentRgb(fill, palette.mutedIcon, isStealth || config.monoIcon, isDark, opacity)
            Triple(fill, rim, eye)
        } else {
            val fill = palette.liveBg
            val rim = if (isStealth) palette.liveIcon else lightenRgb(fill, 0.20f)
            val eye = pickBadgeContentRgb(fill, palette.liveIcon, isStealth || config.monoIcon, isDark, opacity)
            Triple(fill, rim, eye)
        }
    }

    private fun ensureSnakeLayer(w: Int, h: Int): Boolean {
        val existing = snakeLayerBitmap
        if (existing != null && !existing.isRecycled && existing.width == w && existing.height == h) {
            return true
        }
        existing?.recycle()
        val created = runCatching { Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888) }.getOrNull()
        snakeLayerBitmap = created
        snakeLayerCanvas = created?.let { Canvas(it) }
        prevDirtyBounds = null
        return snakeLayerCanvas != null
    }

    private fun drawContinuousSnake(
        canvas: Canvas,
        palette: HudColorPalette,
        isDark: Boolean,
        g: SnakeGridMetrics,
        useAlpha: Int
    ) {
        if (engine.snake.isEmpty()) return
        val interp = engine.currentInterpFraction(nowNs)
        val pieces = engine.buildInterpolatedPieces(interp)
        if (pieces.isEmpty()) return

        val (fillRgb, rimRgb, eyeRgb) = resolveSnakeColors(palette, isDark, useAlpha)
        val d = g.density
        val tubeW = g.cellPx * 0.68f
        val rimW = 1.4f * d

        snakePath.reset()
        var minX = Float.MAX_VALUE
        var minY = Float.MAX_VALUE
        var maxX = -Float.MAX_VALUE
        var maxY = -Float.MAX_VALUE
        var headPxX = 0f
        var headPxY = 0f
        var hasHeadPx = false

        for ((pIdx, pts) in pieces.withIndex()) {
            if (pts.isEmpty()) continue
            val first = pts[0]
            val fx = g.gridOffX + (first.x + 0.5f) * g.cellPx
            val fy = g.gridOffY + (first.y + 0.5f) * g.cellPx
            minX = min(minX, fx); maxX = max(maxX, fx)
            minY = min(minY, fy); maxY = max(maxY, fy)
            if (pIdx == 0) {
                headPxX = fx
                headPxY = fy
                hasHeadPx = true
            }
            snakePath.moveTo(fx, fy)
            if (pts.size == 1) {
                snakePath.lineTo(fx + 0.01f, fy)
            } else {
                for (i in 1 until pts.size) {
                    val px = g.gridOffX + (pts[i].x + 0.5f) * g.cellPx
                    val py = g.gridOffY + (pts[i].y + 0.5f) * g.cellPx
                    minX = min(minX, px); maxX = max(maxX, px)
                    minY = min(minY, py); maxY = max(maxY, py)
                    snakePath.lineTo(px, py)
                }
            }
        }
        if (minX > maxX || minY > maxY) return

        snakeRimPaint.strokeWidth = tubeW + rimW * 2f
        snakeRimPaint.color = withAlpha(rimRgb, 255)
        snakeFillPaint.strokeWidth = tubeW
        snakeFillPaint.color = withAlpha(fillRgb, 255)

        val clipLeft = g.gridOffX.toFloat()
        val clipTop = g.gridOffY.toFloat()
        val clipRight = (g.gridOffX + g.cols * g.cellPx).toFloat()
        val clipBottom = (g.gridOffY + g.rows * g.cellPx).toFloat()

        canvas.save()
        canvas.clipRect(clipLeft, clipTop, clipRight, clipBottom)

        if (ensureSnakeLayer(width, height)) {
            val lCanvas = snakeLayerCanvas!!
            val lBitmap = snakeLayerBitmap!!
            prevDirtyBounds?.let { prev ->
                lBitmap.eraseColor(Color.TRANSPARENT)
                // Clean dirty reset ensures zero lingering alpha across frames
                prevDirtyBounds = null
            } ?: lBitmap.eraseColor(Color.TRANSPARENT)

            val pad = tubeW / 2f + rimW + 6f * d
            val bx = max(0, floor(minX - pad).toInt())
            val by = max(0, floor(minY - pad).toInt())
            val br = min(width, ceil(maxX + pad).toInt())
            val bb = min(height, ceil(maxY + pad).toInt())
            val dirty = Rect(bx, by, max(bx + 1, br), max(by + 1, bb))
            prevDirtyBounds = dirty

            lCanvas.save()
            lCanvas.clipRect(dirty)
            lCanvas.drawPath(snakePath, snakeRimPaint)
            lCanvas.drawPath(snakePath, snakeFillPaint)
            lCanvas.restore()

            layerBlitPaint.alpha = useAlpha.coerceIn(0, 255)
            canvas.drawBitmap(lBitmap, dirty, dirty, layerBlitPaint)
        } else {
            snakeRimPaint.alpha = useAlpha
            snakeFillPaint.alpha = useAlpha
            canvas.drawPath(snakePath, snakeRimPaint)
            canvas.drawPath(snakePath, snakeFillPaint)
        }

        if (hasHeadPx) {
            drawMinimalHeadEyes(canvas, headPxX, headPxY, tubeW, withAlpha(eyeRgb, useAlpha))
        }
        canvas.restore()
    }

    private fun drawMinimalHeadEyes(canvas: Canvas, hx: Float, hy: Float, tubeW: Float, eyeArgb: Int) {
        val dirX = engine.dirX.toFloat()
        val dirY = engine.dirY.toFloat()
        val perpX = -dirY
        val perpY = dirX
        val fwd = tubeW * 0.14f
        val side = tubeW * 0.21f
        val dotR = max(2.6f, tubeW * 0.16f) / 2f

        val ex1 = hx + dirX * fwd + perpX * side
        val ey1 = hy + dirY * fwd + perpY * side
        val ex2 = hx + dirX * fwd - perpX * side
        val ey2 = hy + dirY * fwd - perpY * side

        fillPaint.color = eyeArgb
        canvas.drawCircle(ex1, ey1, dotR, fillPaint)
        canvas.drawCircle(ex2, ey2, dotR, fillPaint)
    }

    private fun drawPopups(canvas: Canvas, g: SnakeGridMetrics) {
        val d = g.density
        for (pop in engine.popups) {
            val frac = ((nowNs - pop.bornNs) / 750_000_000f).coerceIn(0f, 1f)
            if (frac >= 1f) continue
            val y = pop.yPx - frac * 22f * d
            val alpha = max(1, (240 * (1f - frac)).roundToInt())
            val colRgb = if (pop.kind == SnakeFoodKind.BONUS) 0xFBBF24 else 0xFFFFFF
            boldPaint.textSize = 11.5f * d
            boldPaint.textAlign = Paint.Align.CENTER
            boldPaint.color = withAlpha(0x000000, (alpha * 0.65f).roundToInt())
            canvas.drawText(pop.text, pop.xPx + 1f * d, y + 1f * d, boldPaint)
            boldPaint.color = withAlpha(colRgb, alpha)
            canvas.drawText(pop.text, pop.xPx, y, boldPaint)
        }
    }

    private fun drawScoreboard(
        canvas: Canvas,
        palette: HudColorPalette,
        isDark: Boolean,
        g: SnakeGridMetrics,
        opacity: Int
    ) {
        val d = g.density
        val surfAlpha = max(170, min(246, opacity + 38))
        val pillAlpha = max(196, opacity)
        val bgArgb = if (isDark) withAlpha(0x2C2C2C, surfAlpha) else withAlpha(0xFFFFFF, min(250, surfAlpha + 6))
        val brdArgb = if (isDark) 0xFF454545.toInt() else 0xFFDCDCDC.toInt()
        val txtArgb = if (isDark) 0xFFFFFFFF.toInt() else 0xFF1F2328.toInt()
        val divArgb = if (isDark) 0xFF454545.toInt() else 0xFFE2E2E2.toInt()

        val (pillRgb, pillMonoRgb) = when (engine.phase) {
            SnakePhase.GAME_OVER -> palette.mutedBg to palette.mutedIcon
            SnakePhase.PAUSED -> palette.chatAlertBg to palette.chatAlertIcon
            else -> palette.liveBg to palette.liveIcon
        }
        val pillTxtRgb = pickBadgeContentRgb(pillRgb, pillMonoRgb, config.monoIcon, isDark, pillAlpha)

        val modeLabel = if (engine.edgeWrap) "WRAP" else "WALLS"
        val pauseLabel = when (engine.phase) {
            SnakePhase.PAUSED -> "Resume"
            SnakePhase.GAME_OVER -> "Retry"
            else -> "Pause"
        }
        val speedMult = String.format(java.util.Locale.US, "%.1fx", 132f / max(68, engine.stepMs))

        if (g.isCompactScoreboard) {
            // Two-row compact Fluent Win11 card for portrait Phones
            val cardW = (width - 16f * d).coerceAtLeast(200f * d)
            val cardX = (width - cardW) / 2f
            val cardY = 8f * d
            val row1H = 38f * d
            val row2H = 42f * d
            val cardH = row1H + row2H
            val cardRad = if (config.sleekCorners) 18f * d else 10f * d

            workRect.set(cardX, cardY, cardX + cardW, cardY + cardH)
            fillPaint.color = bgArgb
            canvas.drawRoundRect(workRect, cardRad, cardRad, fillPaint)
            strokePaint.color = brdArgb
            strokePaint.strokeWidth = 1.2f * d
            canvas.drawRoundRect(workRect, cardRad, cardRad, strokePaint)

            // Left status badge inside Row 1
            val pad = 6f * d
            val badgeH = row1H - 10f * d
            boldPaint.textSize = 10f * d
            val badgeTxt = "HUD SNAKE"
            val badgeW = max(78f * d, boldPaint.measureText(badgeTxt) + 16f * d)
            val badgeRad = if (config.sleekCorners) badgeH / 2f else 6f * d
            workRect.set(cardX + pad, cardY + 5f * d, cardX + pad + badgeW, cardY + 5f * d + badgeH)
            fillPaint.color = withAlpha(pillRgb, pillAlpha)
            canvas.drawRoundRect(workRect, badgeRad, badgeRad, fillPaint)
            strokePaint.color = withAlpha(lightenRgb(pillRgb, 0.18f), min(255, pillAlpha + 25))
            strokePaint.strokeWidth = 1f * d
            canvas.drawRoundRect(workRect, badgeRad, badgeRad, strokePaint)

            boldPaint.color = withAlpha(pillTxtRgb, 255)
            boldPaint.textAlign = Paint.Align.CENTER
            val bFm = boldPaint.fontMetrics
            canvas.drawText(badgeTxt, workRect.centerX(), workRect.centerY() - (bFm.ascent + bFm.descent) / 2f, boldPaint)

            val statsTxt = "Score ${engine.score} · Best ${engine.highScore} · $speedMult"
            val statsLeft = cardX + pad + badgeW + 8f * d
            val statsAvail = (cardX + cardW - pad - statsLeft).coerceAtLeast(40f)
            boldPaint.textSize = 11.5f * d
            while (boldPaint.measureText(statsTxt) > statsAvail && boldPaint.textSize > 8.5f * d) {
                boldPaint.textSize -= 0.5f * d
            }
            boldPaint.color = txtArgb
            boldPaint.textAlign = Paint.Align.RIGHT
            val sFm = boldPaint.fontMetrics
            canvas.drawText(statsTxt, cardX + cardW - pad - 2f * d, cardY + row1H / 2f - (sFm.ascent + sFm.descent) / 2f, boldPaint)

            // Subtle divider
            fillPaint.color = divArgb
            canvas.drawRect(cardX + pad, cardY + row1H, cardX + cardW - pad, cardY + row1H + 1f * d, fillPaint)

            // Row 2: 3 equal touch-friendly chips (WALLS/WRAP, Pause/Resume, Exit)
            val gap = 6f * d
            val chipTop = cardY + row1H + 4f * d
            val chipH = row2H - 9f * d
            val chipW = (cardW - pad * 2f - gap * 2f) / 3f
            drawChipButton(
                canvas,
                ActionButtonId.SB_MODE,
                cardX + pad,
                chipTop,
                chipW,
                chipH,
                modeLabel,
                isDark,
                accented = engine.edgeWrap,
                accentColor = if (isDark) 0xFF60CDFF.toInt() else 0xFF0067C0.toInt(),
                d = d
            )
            drawChipButton(
                canvas,
                ActionButtonId.SB_PAUSE,
                cardX + pad + chipW + gap,
                chipTop,
                chipW,
                chipH,
                pauseLabel,
                isDark,
                accented = false,
                accentColor = 0,
                d = d
            )
            drawChipButton(
                canvas,
                ActionButtonId.SB_EXIT,
                cardX + pad + (chipW + gap) * 2f,
                chipTop,
                chipW,
                chipH,
                "Exit",
                isDark,
                accented = false,
                accentColor = 0,
                d = d
            )
        } else {
            // Single-row Win11 Explorer bar for Smart Board / Tablet / Landscape
            val sbH = 44f * d
            val badgeH = sbH - 10f * d
            boldPaint.textSize = 11f * d
            val badgeTxt = "HUD SNAKE"
            val badgeW = max(96f * d, boldPaint.measureText(badgeTxt) + 22f * d)

            val statsTxt = "Score ${engine.score}   ·   Best ${engine.highScore}   ·   Len ${engine.snake.size}   ·   $speedMult"
            boldPaint.textSize = 12f * d
            val statsW = boldPaint.measureText(statsTxt)

            val btnH = 30f * d
            val modeW = 68f * d
            val pauseW = 72f * d
            val exitW = 58f * d
            val rightW = modeW + pauseW + exitW + 24f * d
            val minSbW = 6f * d + badgeW + 18f * d + statsW + 18f * d + rightW + 10f * d
            val sbW = min(width - 28f * d, max(540f * d, minSbW))
            val sbX = (width - sbW) / 2f
            val sbY = 8f * d
            val sbRad = if (config.sleekCorners) sbH / 2f else 8f * d

            workRect.set(sbX, sbY, sbX + sbW, sbY + sbH)
            fillPaint.color = bgArgb
            canvas.drawRoundRect(workRect, sbRad, sbRad, fillPaint)
            strokePaint.color = brdArgb
            strokePaint.strokeWidth = 1.2f * d
            canvas.drawRoundRect(workRect, sbRad, sbRad, strokePaint)

            // Status pill on left
            val badgeRad = if (config.sleekCorners) badgeH / 2f else 6f * d
            workRect.set(sbX + 5f * d, sbY + 5f * d, sbX + 5f * d + badgeW, sbY + 5f * d + badgeH)
            fillPaint.color = withAlpha(pillRgb, pillAlpha)
            canvas.drawRoundRect(workRect, badgeRad, badgeRad, fillPaint)
            strokePaint.color = withAlpha(lightenRgb(pillRgb, 0.18f), min(255, pillAlpha + 25))
            strokePaint.strokeWidth = 1f * d
            canvas.drawRoundRect(workRect, badgeRad, badgeRad, strokePaint)

            boldPaint.textSize = 11f * d
            boldPaint.color = withAlpha(pillTxtRgb, 255)
            boldPaint.textAlign = Paint.Align.CENTER
            val bFm = boldPaint.fontMetrics
            canvas.drawText(badgeTxt, workRect.centerX(), workRect.centerY() - (bFm.ascent + bFm.descent) / 2f, boldPaint)

            // Center stats
            val rightStart = sbX + sbW - rightW
            val statsCenterX = (sbX + 5f * d + badgeW + rightStart) / 2f
            boldPaint.textSize = 12f * d
            boldPaint.color = txtArgb
            boldPaint.textAlign = Paint.Align.CENTER
            val sFm = boldPaint.fontMetrics
            canvas.drawText(statsTxt, statsCenterX, sbY + sbH / 2f - (sFm.ascent + sFm.descent) / 2f, boldPaint)

            // Divider before chips
            fillPaint.color = divArgb
            canvas.drawRect(rightStart - 6f * d, sbY + 9f * d, rightStart - 5f * d, sbY + sbH - 9f * d, fillPaint)

            val btnY = sbY + (sbH - btnH) / 2f
            drawChipButton(
                canvas,
                ActionButtonId.SB_MODE,
                rightStart + 2f * d,
                btnY,
                modeW,
                btnH,
                modeLabel,
                isDark,
                accented = engine.edgeWrap,
                accentColor = if (isDark) 0xFF60CDFF.toInt() else 0xFF0067C0.toInt(),
                d = d
            )
            drawChipButton(
                canvas,
                ActionButtonId.SB_PAUSE,
                rightStart + 8f * d + modeW,
                btnY,
                pauseW,
                btnH,
                pauseLabel,
                isDark,
                accented = false,
                accentColor = 0,
                d = d
            )
            drawChipButton(
                canvas,
                ActionButtonId.SB_EXIT,
                rightStart + 14f * d + modeW + pauseW,
                btnY,
                exitW,
                btnH,
                "Exit",
                isDark,
                accented = false,
                accentColor = 0,
                d = d
            )
        }
    }

    private fun drawStatusBanner(
        canvas: Canvas,
        palette: HudColorPalette,
        isDark: Boolean,
        g: SnakeGridMetrics,
        opacity: Int
    ) {
        val d = g.density
        val isDead = engine.phase == SnakePhase.GAME_OVER
        val isCompact = g.isCompactScoreboard
        val surfAlpha = max(188, min(250, opacity + 44))
        val pillAlpha = max(206, opacity)
        val bgArgb = if (isDark) withAlpha(0x2C2C2C, surfAlpha) else withAlpha(0xFFFFFF, min(252, surfAlpha + 6))
        val brdArgb = if (isDark) 0xFF454545.toInt() else 0xFFDCDCDC.toInt()
        val txtArgb = if (isDark) 0xFFFFFFFF.toInt() else 0xFF1F2328.toInt()
        val subArgb = if (isDark) 0xFFB5BAC4.toInt() else 0xFF5F5F5F.toInt()
        val divArgb = if (isDark) 0xFF454545.toInt() else 0xFFE5E5E5.toInt()

        val accentRgb = if (isDead) palette.mutedBg else (if (isDark) 0x60CDFF else 0x0067C0)
        val (pillRgb, pillMonoRgb) = if (isDead) palette.mutedBg to palette.mutedIcon else palette.chatAlertBg to palette.chatAlertIcon
        val pillTxtRgb = pickBadgeContentRgb(pillRgb, pillMonoRgb, config.monoIcon, isDark, pillAlpha)

        val maxCardW = (width - 24f * d).coerceAtLeast(240f * d)
        val banW = if (isCompact) min(maxCardW, 350f * d) else min(maxCardW, 500f * d)
        val banH = if (isCompact) 142f * d else 112f * d
        val banX = (width - banW) / 2f
        val topClear = (if (isCompact) 96f else 62f) * d
        val banY = max(topClear, (height - banH) / 2f - 28f * d)
        val banRad = if (config.sleekCorners) 14f * d else 10f * d

        workRect.set(banX, banY, banX + banW, banY + banH)
        fillPaint.color = bgArgb
        canvas.drawRoundRect(workRect, banRad, banRad, fillPaint)
        strokePaint.color = brdArgb
        strokePaint.strokeWidth = 1.2f * d
        canvas.drawRoundRect(workRect, banRad, banRad, strokePaint)

        // Fluent bottom accent strip inside clipped card
        canvas.save()
        workClipPath.reset()
        workClipPath.addRoundRect(workRect, banRad, banRad, Path.Direction.CW)
        canvas.clipPath(workClipPath)
        fillPaint.color = withAlpha(accentRgb, 235)
        canvas.drawRect(banX, banY + banH - 3.2f * d, banX + banW, banY + banH, fillPaint)
        canvas.restore()

        val statusTag = if (isDead) "GAME OVER" else "PAUSED"
        val midTitle = if (isDead) engine.deathReason.label else "HUD Snake Paused"
        val scoreStr = "Score ${engine.score}"
        val showNewBest = isDead && engine.bestBeaten

        val pad = 12f * d
        val tagH = 24f * d
        boldPaint.textSize = 10.5f * d
        val tagW = boldPaint.measureText(statusTag) + 18f * d
        val tagRad = if (config.sleekCorners) tagH / 2f else 6f * d

        // Header line inside card
        val row1Y = banY + 14f * d
        workRect.set(banX + pad, row1Y, banX + pad + tagW, row1Y + tagH)
        fillPaint.color = withAlpha(pillRgb, pillAlpha)
        canvas.drawRoundRect(workRect, tagRad, tagRad, fillPaint)
        strokePaint.color = withAlpha(lightenRgb(pillRgb, 0.20f), min(255, pillAlpha + 25))
        strokePaint.strokeWidth = 1.1f * d
        canvas.drawRoundRect(workRect, tagRad, tagRad, strokePaint)

        boldPaint.color = withAlpha(pillTxtRgb, 255)
        boldPaint.textAlign = Paint.Align.CENTER
        val tFm = boldPaint.fontMetrics
        canvas.drawText(statusTag, workRect.centerX(), workRect.centerY() - (tFm.ascent + tFm.descent) / 2f, boldPaint)

        boldPaint.textSize = 13f * d
        boldPaint.color = txtArgb
        boldPaint.textAlign = Paint.Align.LEFT
        val mFm = boldPaint.fontMetrics
        canvas.drawText(midTitle, banX + pad + tagW + 10f * d, row1Y + tagH / 2f - (mFm.ascent + mFm.descent) / 2f, boldPaint)

        // Score / New Best right aligned
        boldPaint.textSize = 11f * d
        val scW = boldPaint.measureText(scoreStr) + 16f * d
        val scX = banX + banW - pad - scW
        workRect.set(scX, row1Y, scX + scW, row1Y + tagH)
        fillPaint.color = if (isDark) 0xFF333333.toInt() else 0xFFF3F3F3.toInt()
        canvas.drawRoundRect(workRect, tagRad, tagRad, fillPaint)
        strokePaint.color = if (isDark) 0xFF4B4B4B.toInt() else 0xFFD8D8D8.toInt()
        strokePaint.strokeWidth = 1.1f * d
        canvas.drawRoundRect(workRect, tagRad, tagRad, strokePaint)
        boldPaint.color = txtArgb
        boldPaint.textAlign = Paint.Align.CENTER
        val scFm = boldPaint.fontMetrics
        canvas.drawText(scoreStr, workRect.centerX(), workRect.centerY() - (scFm.ascent + scFm.descent) / 2f, boldPaint)

        if (showNewBest) {
            val nbTxt = "★ New Best"
            val nbW = boldPaint.measureText(nbTxt) + 16f * d
            val nbY = row1Y + tagH + 6f * d
            val nbX = banX + banW - pad - nbW
            workRect.set(nbX, nbY, nbX + nbW, nbY + 21f * d)
            fillPaint.color = withAlpha(palette.recPausedBg, pillAlpha)
            canvas.drawRoundRect(workRect, tagRad, tagRad, fillPaint)
            val nbCol = pickBadgeContentRgb(palette.recPausedBg, palette.recPausedIcon, config.monoIcon, isDark, pillAlpha)
            boldPaint.color = withAlpha(nbCol, 255)
            val nbFm = boldPaint.fontMetrics
            canvas.drawText(nbTxt, workRect.centerX(), workRect.centerY() - (nbFm.ascent + nbFm.descent) / 2f, boldPaint)
        }

        // Control hint line
        textPaint.textSize = 10.5f * d
        textPaint.color = subArgb
        textPaint.textAlign = Paint.Align.LEFT
        canvas.drawText("Swipe · Arrows / WASD · D-Pad", banX + pad, row1Y + tagH + 20f * d, textPaint)

        // Divider above action chips
        val btnY = banY + banH - (if (isCompact) 54f else 50f) * d
        fillPaint.color = divArgb
        canvas.drawRect(banX + pad, btnY - 8f * d, banX + banW - pad, btnY - 7f * d, fillPaint)

        val btnH = 40f * d
        val btnGap = 8f * d
        val innerW = banW - pad * 2f - btnGap * 2f
        val primaryW = innerW * 0.40f
        val edgeW = innerW * 0.34f
        val exitW = innerW * 0.26f

        val primaryLabel = if (isDead) "Play Again" else "Resume"
        val edgeLabel = if (engine.edgeWrap) "Wrap Edge" else "Wall Edge"
        drawChipButton(
            canvas,
            ActionButtonId.BANNER_PRIMARY,
            banX + pad,
            btnY,
            primaryW,
            btnH,
            primaryLabel,
            isDark,
            accented = true,
            accentColor = accentRgb,
            d = d
        )
        drawChipButton(
            canvas,
            ActionButtonId.BANNER_EDGE,
            banX + pad + primaryW + btnGap,
            btnY,
            edgeW,
            btnH,
            edgeLabel,
            isDark,
            accented = false,
            accentColor = 0,
            d = d
        )
        drawChipButton(
            canvas,
            ActionButtonId.BANNER_EXIT,
            banX + pad + primaryW + btnGap + edgeW + btnGap,
            btnY,
            exitW,
            btnH,
            "Exit",
            isDark,
            accented = false,
            accentColor = 0,
            d = d
        )
    }

    private fun drawChipButton(
        canvas: Canvas,
        id: ActionButtonId,
        x: Float,
        y: Float,
        w: Float,
        h: Float,
        label: String,
        isDark: Boolean,
        accented: Boolean,
        accentColor: Int,
        d: Float
    ) {
        val rect = RectF(x, y, x + w, y + h)
        buttonRects[id] = rect
        val pressed = (pressedBtn == id)
        val rad = if (config.sleekCorners) h / 2f else 6f * d

        val fillCol = when {
            accented -> withAlpha(accentColor, if (pressed) 245 else 210)
            pressed -> if (isDark) 0xFF474747.toInt() else 0xFFE5E7EB.toInt()
            else -> if (isDark) 0xFF333333.toInt() else 0xFFFBFBFB.toInt()
        }
        val strokeCol = when {
            accented -> withAlpha(lightenRgb(accentColor, 0.22f), 255)
            else -> if (isDark) 0xFF4A4A4A.toInt() else 0xFFDCDCDC.toInt()
        }
        val textCol = if (accented) {
            withAlpha(pickBadgeContentRgb(accentColor, accentColor, useMono = false, isDark = isDark, alpha = 230), 255)
        } else if (isDark) {
            0xFFF3F4F6.toInt()
        } else {
            0xFF1F2328.toInt()
        }

        fillPaint.color = fillCol
        canvas.drawRoundRect(rect, rad, rad, fillPaint)
        strokePaint.color = strokeCol
        strokePaint.strokeWidth = 1f * d
        canvas.drawRoundRect(rect, rad, rad, strokePaint)

        boldPaint.textSize = 11.5f * d
        while (boldPaint.measureText(label) > w - 10f * d && boldPaint.textSize > 8.5f * d) {
            boldPaint.textSize -= 0.5f * d
        }
        boldPaint.color = textCol
        boldPaint.textAlign = Paint.Align.CENTER
        val fm = boldPaint.fontMetrics
        canvas.drawText(label, rect.centerX(), rect.centerY() - (fm.ascent + fm.descent) / 2f, boldPaint)
    }

    companion object {
        private fun withAlpha(rgbOrArgb: Int, alpha: Int): Int {
            return (alpha.coerceIn(0, 255) shl 24) or (rgbOrArgb and 0xFFFFFF)
        }

        private fun lightenRgb(rgb: Int, amount: Float): Int {
            val r = (rgb ushr 16) and 0xFF
            val g = (rgb ushr 8) and 0xFF
            val b = rgb and 0xFF
            val nr = min(255, (r + (255 - r) * amount).roundToInt())
            val ng = min(255, (g + (255 - g) * amount).roundToInt())
            val nb = min(255, (b + (255 - b) * amount).roundToInt())
            return (nr shl 16) or (ng shl 8) or nb
        }

        private fun rgbLuminance(rgb: Int): Float {
            val r = ((rgb ushr 16) and 0xFF) / 255f
            val g = ((rgb ushr 8) and 0xFF) / 255f
            val b = (rgb and 0xFF) / 255f
            return 0.2126f * r + 0.7152f * g + 0.0722f * b
        }

        private fun pickBadgeContentRgb(
            fillRgb: Int,
            monoRgb: Int,
            useMono: Boolean,
            isDark: Boolean,
            alpha: Int
        ): Int {
            val a = (alpha / 255f).coerceIn(0.25f, 1f)
            val bg = if (isDark) 44f else 255f
            val effR = ((fillRgb ushr 16) and 0xFF) * a + bg * (1f - a)
            val effG = ((fillRgb ushr 8) and 0xFF) * a + bg * (1f - a)
            val effB = (fillRgb and 0xFF) * a + bg * (1f - a)
            val lumBg = (0.2126f * effR + 0.7152f * effG + 0.0722f * effB) / 255f
            if (useMono) {
                val lumMono = rgbLuminance(monoRgb)
                val ratio = (max(lumBg, lumMono) + 0.05f) / (min(lumBg, lumMono) + 0.05f)
                if (ratio >= 2.6f) return monoRgb and 0xFFFFFF
            }
            return if (lumBg > 0.68f) 0x111827 else 0xFFFFFF
        }
    }
}
