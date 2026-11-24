package com.saabithjiffry.presentersync.remote.ui.arcade

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.view.KeyEvent
import android.view.MotionEvent
import com.saabithjiffry.presentersync.remote.config.HudColorPalette
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

// ============================================================================
// SECTOR Z-06: NEON LIGHT CYCLES (TRON) OVERLAY VIEW
// ============================================================================

class LightCyclesOverlayView(
    context: Context,
    private val engine: LightCyclesEngine,
    onExitRequested: () -> Unit,
    onStateInteracted: () -> Unit = {},
    onMuteKeyEvent: (KeyEvent) -> Boolean = { false }
) : ArcadeCanvasBaseView(context, onExitRequested, onStateInteracted, onMuteKeyEvent) {

    private val gridLinePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 1f
        color = 0x1A38BDF8
    }

    private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
    }

    private val trailPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }

    private val glowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }

    private val hudBarPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }

    private val tempRect = RectF()
    private var touchStartX = 0f
    private var touchStartY = 0f
    private var swipedDuringGesture = false

    override fun buildScoreboardBadge(): String = "NEON LIGHT CYCLES"

    override fun buildScoreboardStats(): String {
        val boostPct = engine.boostEnergy.roundToInt()
        return "Score ${engine.score} · Best ${engine.highScore} · Wins ${engine.roundStreak} · Boost $boostPct%"
    }

    override fun buildExtraChipLabel(): String {
        return if (engine.boostActive) "Turbo: ON" else "Turbo: OFF"
    }

    override fun buildPauseTitle(): String = "LIGHT CYCLES PAUSED"

    override fun buildPauseSubtitle(): String = "Swipe or press Arrows/WASD to steer · Hold/Tap Turbo to boost"

    override fun buildGameOverSubtitle(): String =
        "Score ${engine.score} · Best ${engine.highScore} · Round Streak ${engine.roundStreak}"

    override fun isGamePaused(): Boolean = engine.phase == LightCyclesPhase.PAUSED

    override fun isGameOver(): Boolean = engine.phase == LightCyclesPhase.GAME_OVER

    override fun onExtraTopAction() {
        engine.toggleBoost()
    }

    override fun onTogglePause() {
        engine.togglePause()
    }

    override fun onRestartGame() {
        engine.startNewSession(
            widthPx = width.coerceAtLeast(320),
            heightPx = height.coerceAtLeast(320),
            screenDensity = density,
            initialHighScore = maxOf(engine.highScore, config.arcadeHighScores["tron"] ?: 0)
        )
    }

    override fun onGameKey(keyCode: Int, isDown: Boolean, event: KeyEvent): Boolean {
        if (isConfiguredMuteKey(event)) return false

        when (keyCode) {
            KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_W -> {
                if (isDown) engine.steer(0, -1)
                return true
            }
            KeyEvent.KEYCODE_DPAD_DOWN, KeyEvent.KEYCODE_S -> {
                if (isDown) engine.steer(0, 1)
                return true
            }
            KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_A -> {
                if (isDown) engine.steer(-1, 0)
                return true
            }
            KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.KEYCODE_D -> {
                if (isDown) engine.steer(1, 0)
                return true
            }
            KeyEvent.KEYCODE_SPACE, KeyEvent.KEYCODE_SHIFT_LEFT, KeyEvent.KEYCODE_SHIFT_RIGHT,
            KeyEvent.KEYCODE_BUTTON_A -> {
                if (isDown && engine.phase == LightCyclesPhase.GAME_OVER) {
                    onRestartGame()
                } else {
                    engine.setBoost(isDown)
                }
                return true
            }
            KeyEvent.KEYCODE_P -> {
                if (isDown && event.repeatCount == 0) engine.togglePause()
                return true
            }
            KeyEvent.KEYCODE_R -> {
                if (isDown && engine.phase == LightCyclesPhase.GAME_OVER) onRestartGame()
                return true
            }
        }
        return false
    }

    override fun onGameTouch(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                touchStartX = event.x
                touchStartY = event.y
                swipedDuringGesture = false
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                val dx = event.x - touchStartX
                val dy = event.y - touchStartY
                val threshold = 18f * density
                if (abs(dx) >= threshold || abs(dy) >= threshold) {
                    if (abs(dx) > abs(dy)) {
                        engine.steer(if (dx > 0f) 1 else -1, 0)
                    } else {
                        engine.steer(0, if (dy > 0f) 1 else -1)
                    }
                    touchStartX = event.x
                    touchStartY = event.y
                    swipedDuringGesture = true
                }
                return true
            }
            MotionEvent.ACTION_UP -> {
                if (!swipedDuringGesture) {
                    val cx = width * 0.5f
                    val cy = height * 0.5f
                    val tapDx = event.x - cx
                    val tapDy = event.y - cy
                    if (engine.playerDx != 0) {
                        engine.steer(0, if (tapDy >= 0f) 1 else -1)
                    } else {
                        engine.steer(if (tapDx >= 0f) 1 else -1, 0)
                    }
                }
                return true
            }
        }
        return false
    }

    override fun onGameFrameRender(
        canvas: Canvas,
        palette: HudColorPalette,
        isDark: Boolean,
        opacity: Int
    ) {
        val w = width.toFloat().coerceAtLeast(320f)
        val h = height.toFloat().coerceAtLeast(320f)
        fillPaint.color = withAlpha(if (isDark) 0x070B14 else 0x0F172A, if (isDark) 144 else 124)
        canvas.drawRect(0f, 0f, w, h, fillPaint)

        val topInset = 78f * density
        val bottomInset = 36f * density
        val sideInset = 18f * density
        val availW = (w - sideInset * 2f).coerceAtLeast(160f)
        val availH = (h - topInset - bottomInset).coerceAtLeast(160f)

        val cellSize = min(availW / engine.cols.toFloat(), availH / engine.rows.toFloat())
        val arenaW = cellSize * engine.cols
        val arenaH = cellSize * engine.rows
        val left = (w - arenaW) * 0.5f
        val top = topInset + (availH - arenaH) * 0.5f

        val playerRgb = if (isMicMuted) palette.mutedBg else palette.liveBg
        val aiRgb = 0xF97316

        // Subtle perspective grid lines
        gridLinePaint.strokeWidth = max(1f, 0.75f * density)
        for (c in 0..engine.cols step 4) {
            val gx = left + c * cellSize
            canvas.drawLine(gx, top, gx, top + arenaH, gridLinePaint)
        }
        for (r in 0..engine.rows step 4) {
            val gy = top + r * cellSize
            canvas.drawLine(left, gy, left + arenaW, gy, gridLinePaint)
        }

        // Neon arena border
        borderPaint.strokeWidth = 2f * density
        borderPaint.color = withAlpha(playerRgb, 190)
        tempRect.set(left, top, left + arenaW, top + arenaH)
        canvas.drawRoundRect(tempRect, 6f * density, 6f * density, borderPaint)

        drawLightTrail(canvas, engine.playerTrail, left, top, cellSize, playerRgb)
        drawLightTrail(canvas, engine.aiTrail, left, top, cellSize, aiRgb)

        // Cycle heads with outer glow
        drawCycleHead(canvas, engine.playerCol, engine.playerRow, left, top, cellSize, playerRgb, engine.boostActive)
        drawCycleHead(canvas, engine.aiCol, engine.aiRow, left, top, cellSize, aiRgb, false)

        // Crash / boost sparks
        for (p in engine.particles) {
            val alpha = ((p.lifeSec / p.maxLifeSec).coerceIn(0f, 1f) * 240f).toInt()
            trailPaint.color = withAlpha(if (p.isPlayerColor) playerRgb else aiRgb, alpha)
            canvas.drawCircle(left + p.x * arenaW, top + p.y * arenaH, 3f * density, trailPaint)
        }

        // Bottom turbo energy gauge
        val barW = min(arenaW * 0.45f, 220f * density)
        val barH = 6f * density
        val barLeft = (w - barW) * 0.5f
        val barTop = top + arenaH + 12f * density
        hudBarPaint.color = 0x33FFFFFF
        tempRect.set(barLeft, barTop, barLeft + barW, barTop + barH)
        canvas.drawRoundRect(tempRect, barH, barH, hudBarPaint)

        val fillW = barW * (engine.boostEnergy / 100f).coerceIn(0f, 1f)
        hudBarPaint.color = if (engine.boostActive) 0xFF38BDF8.toInt() else withAlpha(playerRgb, 210)
        tempRect.set(barLeft, barTop, barLeft + fillW, barTop + barH)
        canvas.drawRoundRect(tempRect, barH, barH, hudBarPaint)
    }

    private fun drawLightTrail(
        canvas: Canvas,
        trail: List<GridCell>,
        left: Float,
        top: Float,
        cellSize: Float,
        colorRgb: Int
    ) {
        glowPaint.color = withAlpha(colorRgb, 75)
        trailPaint.color = withAlpha(colorRgb, 235)
        val pad = cellSize * 0.08f
        val glowExpand = cellSize * 0.25f

        for (cell in trail) {
            val cl = left + cell.col * cellSize
            val ct = top + cell.row * cellSize
            canvas.drawRect(cl - glowExpand, ct - glowExpand, cl + cellSize + glowExpand, ct + cellSize + glowExpand, glowPaint)
            canvas.drawRect(cl + pad, ct + pad, cl + cellSize - pad, ct + cellSize - pad, trailPaint)
        }
    }

    private fun drawCycleHead(
        canvas: Canvas,
        col: Int,
        row: Int,
        left: Float,
        top: Float,
        cellSize: Float,
        colorRgb: Int,
        boosted: Boolean
    ) {
        val cx = left + (col + 0.5f) * cellSize
        val cy = top + (row + 0.5f) * cellSize
        glowPaint.color = withAlpha(colorRgb, if (boosted) 150 else 100)
        canvas.drawCircle(cx, cy, cellSize * (if (boosted) 1.35f else 0.95f), glowPaint)
        trailPaint.color = 0xFFFFFFFF.toInt()
        canvas.drawCircle(cx, cy, cellSize * 0.42f, trailPaint)
    }
}

// ============================================================================
// SECTOR Z-07: AUTHENTIC NEON PAC-GRID OVERLAY VIEW
// ============================================================================

class PacGridOverlayView(
    context: Context,
    private val engine: PacGridEngine,
    onExitRequested: () -> Unit,
    onStateInteracted: () -> Unit = {},
    onMuteKeyEvent: (KeyEvent) -> Boolean = { false }
) : ArcadeCanvasBaseView(context, onExitRequested, onStateInteracted, onMuteKeyEvent) {

    private val wallPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }
    private val gatePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
    }
    private val pelletPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }
    private val actorPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }
    private val dpadPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }
    private val dpadBorderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
    }
    private val tempRect = RectF()
    private val dpadCenter = FloatArray(2)

    private var touchStartX = 0f
    private var touchStartY = 0f

    var expandedView: Boolean = false

    data class MazeLayout(
        val left: Float,
        val top: Float,
        val cellW: Float,
        val cellH: Float,
        val boardW: Float,
        val boardH: Float
    )

    companion object {
        fun computeMazeLayout(
            widthPx: Float,
            heightPx: Float,
            density: Float,
            cols: Int,
            rows: Int,
            expanded: Boolean,
            showTouchDpad: Boolean = false
        ): MazeLayout {
            val w = widthPx.coerceAtLeast(320f)
            val h = heightPx.coerceAtLeast(320f)
            if (expanded) {
                val topInset = 68f * density
                val sideInset = 10f * density
                val bottomInset = if (showTouchDpad) 128f * density else 12f * density
                val availW = (w - sideInset * 2f).coerceAtLeast(160f)
                val availH = (h - topInset - bottomInset).coerceAtLeast(160f)
                val cellW = availW / cols.toFloat()
                val cellH = availH / rows.toFloat()
                return MazeLayout(
                    left = sideInset,
                    top = topInset,
                    cellW = cellW,
                    cellH = cellH,
                    boardW = cellW * cols,
                    boardH = cellH * rows
                )
            }
            val topInset = 78f * density
            val bottomInset = if (showTouchDpad) 136f * density else 28f * density
            val sideInset = 14f * density
            val availW = (w - sideInset * 2f).coerceAtLeast(160f)
            val availH = (h - topInset - bottomInset).coerceAtLeast(160f)
            val tileSize = min(availW / cols.toFloat(), availH / rows.toFloat())
            val boardW = tileSize * cols
            val boardH = tileSize * rows
            val left = (w - boardW) * 0.5f
            val top = topInset + (availH - boardH) * 0.5f
            return MazeLayout(
                left = left,
                top = top,
                cellW = tileSize,
                cellH = tileSize,
                boardW = boardW,
                boardH = boardH
            )
        }
    }

    override fun buildScoreboardBadge(): String = "NEON PAC-GRID · LVL ${engine.level}"

    override fun buildScoreboardStats(): String {
        val modeTag = if (engine.frightenedTimerSec > 0f) {
            "PWR ${engine.frightenedTimerSec.roundToInt()}s"
        } else {
            engine.waveMode.name
        }
        return "Score ${engine.score} · Best ${engine.highScore} · Lives ${engine.lives} · $modeTag"
    }

    override fun buildExtraChipLabel(): String {
        return if (expandedView) "Full (F→Center)" else "Center (F→Full)"
    }

    override fun buildPauseTitle(): String = "NEON PAC-GRID PAUSED"

    override fun buildPauseSubtitle(): String = "Swipe, tap on-screen D-Pad, or use Arrows/WASD to buffer turns · F: Center/Full View"

    override fun buildGameOverSubtitle(): String =
        "Score ${engine.score} · Best ${engine.highScore} · Level ${engine.level}"

    override fun isGamePaused(): Boolean = engine.phase == PacGridPhase.PAUSED

    override fun isGameOver(): Boolean = engine.phase == PacGridPhase.GAME_OVER

    override fun onExtraTopAction() {
        expandedView = !expandedView
        invalidate()
    }

    override fun onTogglePause() {
        engine.togglePause()
    }

    override fun onRestartGame() {
        engine.startNewSession(
            widthPx = width.coerceAtLeast(320),
            heightPx = height.coerceAtLeast(320),
            screenDensity = density,
            initialHighScore = maxOf(engine.highScore, config.arcadeHighScores["pac_grid"] ?: 0)
        )
    }

    override fun onGameKey(keyCode: Int, isDown: Boolean, event: KeyEvent): Boolean {
        if (isConfiguredMuteKey(event)) return false
        if (!isDown) return false

        when (keyCode) {
            KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_W -> {
                engine.queueDirection(0, -1)
                return true
            }
            KeyEvent.KEYCODE_DPAD_DOWN, KeyEvent.KEYCODE_S -> {
                engine.queueDirection(0, 1)
                return true
            }
            KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_A -> {
                engine.queueDirection(-1, 0)
                return true
            }
            KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.KEYCODE_D -> {
                engine.queueDirection(1, 0)
                return true
            }
            KeyEvent.KEYCODE_P -> {
                if (event.repeatCount == 0) engine.togglePause()
                return true
            }
            KeyEvent.KEYCODE_F, KeyEvent.KEYCODE_BUTTON_Y -> {
                if (event.repeatCount == 0) {
                    expandedView = !expandedView
                    invalidate()
                }
                return true
            }
            KeyEvent.KEYCODE_R -> {
                if (engine.phase == PacGridPhase.GAME_OVER) onRestartGame()
                return true
            }
        }
        return false
    }

    override fun onGameTouch(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                touchStartX = event.x
                touchStartY = event.y
                if (engine.showTouchDpad && handleDpadTap(event.x, event.y)) {
                    return true
                }
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                val dx = event.x - touchStartX
                val dy = event.y - touchStartY
                val threshold = 16f * density
                if (abs(dx) >= threshold || abs(dy) >= threshold) {
                    if (abs(dx) > abs(dy)) {
                        engine.queueDirection(if (dx > 0f) 1 else -1, 0)
                    } else {
                        engine.queueDirection(0, if (dy > 0f) 1 else -1)
                    }
                    touchStartX = event.x
                    touchStartY = event.y
                }
                return true
            }
        }
        return false
    }

    private fun handleDpadTap(x: Float, y: Float): Boolean {
        val cx = dpadCenter[0]
        val cy = dpadCenter[1]
        val radius = 64f * density
        val dx = x - cx
        val dy = y - cy
        if (abs(dx) > radius * 1.25f || abs(dy) > radius * 1.25f) return false
        if (abs(dx) > abs(dy)) {
            engine.queueDirection(if (dx > 0f) 1 else -1, 0)
        } else {
            engine.queueDirection(0, if (dy > 0f) 1 else -1)
        }
        return true
    }

    override fun onGameFrameRender(
        canvas: Canvas,
        palette: HudColorPalette,
        isDark: Boolean,
        opacity: Int
    ) {
        val w = width.toFloat().coerceAtLeast(320f)
        val h = height.toFloat().coerceAtLeast(320f)
        fillPaint.color = withAlpha(if (isDark) 0x070B14 else 0x0F172A, if (isDark) 144 else 124)
        canvas.drawRect(0f, 0f, w, h, fillPaint)

        val layout = computeMazeLayout(
            widthPx = w,
            heightPx = h,
            density = density,
            cols = PacGridEngine.MAZE_COLS,
            rows = PacGridEngine.MAZE_ROWS,
            expanded = expandedView,
            showTouchDpad = engine.showTouchDpad
        )
        val left = layout.left
        val top = layout.top
        val cellW = layout.cellW
        val cellH = layout.cellH
        val tileSize = min(cellW, cellH)
        val boardH = layout.boardH

        val pulse = ((nowNs / 120_000_000L) % 2L == 0L)
        val wallRgb = if (isMicMuted) palette.mutedBg else palette.liveBg
        wallPaint.color = withAlpha(wallRgb, 175)
        gatePaint.strokeWidth = max(2f, 2f * density)
        gatePaint.color = 0xFFF472B6.toInt()

        // Render 28x31 maze walls, pellets, and corner Power Orbs
        for (r in 0 until PacGridEngine.MAZE_ROWS) {
            for (c in 0 until PacGridEngine.MAZE_COLS) {
                val tl = left + c * cellW
                val tt = top + r * cellH
                val cx = tl + cellW * 0.5f
                val cy = tt + cellH * 0.5f

                when (engine.getTile(c, r)) {
                    PacGridEngine.TILE_WALL -> {
                        val padX = cellW * 0.08f
                        val padY = cellH * 0.08f
                        tempRect.set(tl + padX, tt + padY, tl + cellW - padX, tt + cellH - padY)
                        canvas.drawRoundRect(tempRect, tileSize * 0.22f, tileSize * 0.22f, wallPaint)
                    }
                    PacGridEngine.TILE_GHOST_GATE -> {
                        canvas.drawLine(tl, cy, tl + cellW, cy, gatePaint)
                    }
                    PacGridEngine.TILE_PELLET -> {
                        pelletPaint.color = 0xFFFDE68A.toInt()
                        canvas.drawCircle(cx, cy, max(1.8f, tileSize * 0.14f), pelletPaint)
                    }
                    PacGridEngine.TILE_POWER_ORB -> {
                        pelletPaint.color = if (pulse) 0xFF38BDF8.toInt() else 0xFFE0F2FE.toInt()
                        val orbR = tileSize * (if (pulse) 0.36f else 0.28f)
                        canvas.drawCircle(cx, cy, orbR, pelletPaint)
                    }
                }
            }
        }

        // Bonus Neon Fruit
        engine.activeFruit?.let { fruit ->
            val fx = left + (fruit.col + 0.5f) * cellW
            val fy = top + (fruit.row + 0.5f) * cellH
            actorPaint.color = 0xFFEC4899.toInt()
            canvas.drawCircle(fx, fy, tileSize * 0.44f, actorPaint)
        }

        // Neon Runner
        val rx = left + (engine.runnerCol + 0.5f) * cellW
        val ry = top + (engine.runnerRow + 0.5f) * cellH
        actorPaint.color = 0xFFFACC15.toInt()
        canvas.drawCircle(rx, ry, tileSize * 0.48f, actorPaint)

        // 4 Chasers (Blinky, Pinky, Inky, Clyde)
        for (chaser in engine.chasers) {
            val gx = left + (chaser.col + 0.5f) * cellW
            val gy = top + (chaser.row + 0.5f) * cellH
            when (chaser.state) {
                ChaserState.EYES -> {
                    actorPaint.color = 0xFFFFFFFF.toInt()
                    canvas.drawCircle(gx - tileSize * 0.16f, gy, tileSize * 0.16f, actorPaint)
                    canvas.drawCircle(gx + tileSize * 0.16f, gy, tileSize * 0.16f, actorPaint)
                }
                ChaserState.FRIGHTENED -> {
                    val flash = engine.frightenedTimerSec < 2.0f && pulse
                    actorPaint.color = if (flash) 0xFFE2E8F0.toInt() else 0xFF2563EB.toInt()
                    canvas.drawCircle(gx, gy, tileSize * 0.46f, actorPaint)
                }
                ChaserState.NORMAL -> {
                    actorPaint.color = when (chaser.personality) {
                        ChaserPersonality.BLINKY -> 0xFFEF4444.toInt()
                        ChaserPersonality.PINKY -> 0xFFF472B6.toInt()
                        ChaserPersonality.INKY -> 0xFF22D3EE.toInt()
                        ChaserPersonality.CLYDE -> 0xFFFB923C.toInt()
                    }
                    canvas.drawCircle(gx, gy, tileSize * 0.48f, actorPaint)
                }
            }
        }

        // Optional On-Screen Touch D-Pad for Phones & Smart Boards
        if (engine.showTouchDpad) {
            val dpadRadius = 52f * density
            val dpadCx = w * 0.5f
            val dpadCy = (h - 68f * density).coerceAtLeast(top + boardH + dpadRadius)
            dpadCenter[0] = dpadCx
            dpadCenter[1] = dpadCy

            dpadPaint.color = 0x260F172A
            dpadBorderPaint.strokeWidth = 1.5f * density
            dpadBorderPaint.color = withAlpha(wallRgb, 130)
            canvas.drawCircle(dpadCx, dpadCy, dpadRadius, dpadPaint)
            canvas.drawCircle(dpadCx, dpadCy, dpadRadius, dpadBorderPaint)

            val arm = dpadRadius * 0.58f
            canvas.drawCircle(dpadCx, dpadCy - arm, 10f * density, dpadBorderPaint)
            canvas.drawCircle(dpadCx, dpadCy + arm, 10f * density, dpadBorderPaint)
            canvas.drawCircle(dpadCx - arm, dpadCy, 10f * density, dpadBorderPaint)
            canvas.drawCircle(dpadCx + arm, dpadCy, 10f * density, dpadBorderPaint)
        }
    }
}
