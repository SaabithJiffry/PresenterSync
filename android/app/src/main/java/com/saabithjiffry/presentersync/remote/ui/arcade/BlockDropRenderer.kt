package com.saabithjiffry.presentersync.remote.ui.arcade

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.view.HapticFeedbackConstants
import android.view.KeyEvent
import android.view.MotionEvent
import com.saabithjiffry.presentersync.remote.config.HudColorPalette
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

// ============================================================================
// SECTOR Z-09: NEON BLOCK DROP OVERLAY VIEW
// ============================================================================

class BlockDropOverlayView(
    context: Context,
    private val engine: BlockDropEngine,
    onExitRequested: () -> Unit,
    onStateInteracted: () -> Unit = {},
    onMuteKeyEvent: (KeyEvent) -> Boolean = { false }
) : ArcadeCanvasBaseView(context, onExitRequested, onStateInteracted, onMuteKeyEvent) {

    private val gridPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 1f
        color = 0x2294A3B8
    }

    private val cellRect = RectF()
    private val holdBtnRect = RectF()
    private val rotBtnRect = RectF()
    private val dropBtnRect = RectF()

    private var touchStartX = 0f
    private var touchStartY = 0f
    private var lastDragX = 0f
    private var dragMovedCols = false
    private var softDropDrag = false

    override fun buildScoreboardBadge(): String = "NEON BLOCK DROP"

    override fun buildScoreboardStats(): String =
        "Score ${engine.score} · Best ${engine.highScore} · Lvl ${engine.level} · Lines ${engine.lines}"

    override fun buildExtraChipLabel(): String = "Hold"

    override fun buildPauseTitle(): String = "BLOCK DROP PAUSED"

    override fun buildPauseSubtitle(): String =
        "Swipe L/R to move · Swipe Down to drop · Tap to rotate"

    override fun buildGameOverSubtitle(): String =
        "Score ${engine.score} · Best ${engine.highScore} · Level ${engine.level} (${engine.lines} lines)"

    override fun isGamePaused(): Boolean = engine.phase == BlockDropPhase.PAUSED

    override fun isGameOver(): Boolean = engine.phase == BlockDropPhase.GAME_OVER

    override fun onExtraTopAction() {
        engine.hold()
    }

    override fun onTogglePause() {
        engine.togglePause()
    }

    override fun onRestartGame() {
        engine.resetMatch()
    }

    override fun onGameKey(keyCode: Int, isDown: Boolean, event: KeyEvent): Boolean {
        if (keyCode == KeyEvent.KEYCODE_DPAD_DOWN || keyCode == KeyEvent.KEYCODE_S) {
            engine.setSoftDrop(isDown)
            return true
        }
        if (!isDown) return false
        return when (keyCode) {
            KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_A -> engine.move(-1)
            KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.KEYCODE_D -> engine.move(1)
            KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_W, KeyEvent.KEYCODE_X -> engine.rotate(1)
            KeyEvent.KEYCODE_Z, KeyEvent.KEYCODE_BUTTON_B -> engine.rotate(-1)
            KeyEvent.KEYCODE_SPACE, KeyEvent.KEYCODE_BUTTON_A -> {
                engine.hardDrop()
                true
            }
            KeyEvent.KEYCODE_C, KeyEvent.KEYCODE_SHIFT_LEFT, KeyEvent.KEYCODE_SHIFT_RIGHT -> engine.hold()
            KeyEvent.KEYCODE_P -> {
                engine.togglePause()
                true
            }
            KeyEvent.KEYCODE_R -> {
                engine.resetMatch()
                true
            }
            else -> false
        }
    }

    override fun onGameTouch(event: MotionEvent): Boolean {
        if (engine.phase != BlockDropPhase.PLAYING) return false
        val d = density
        val stepPx = max(24f * d, width / 14f)

        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                if (holdBtnRect.contains(event.x, event.y)) {
                    performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                    engine.hold()
                    invalidate()
                    return true
                }
                if (rotBtnRect.contains(event.x, event.y)) {
                    performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                    engine.rotate(1)
                    invalidate()
                    return true
                }
                if (dropBtnRect.contains(event.x, event.y)) {
                    performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                    engine.hardDrop()
                    invalidate()
                    return true
                }
                touchStartX = event.x
                touchStartY = event.y
                lastDragX = event.x
                dragMovedCols = false
                softDropDrag = false
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                val dxStep = event.x - lastDragX
                if (abs(dxStep) >= stepPx) {
                    val dir = if (dxStep > 0f) 1 else -1
                    engine.move(dir)
                    lastDragX += dir * stepPx
                    dragMovedCols = true
                    invalidate()
                }
                val dy = event.y - touchStartY
                if (dy > 32f * d && abs(dy) > abs(event.x - touchStartX)) {
                    softDropDrag = true
                    engine.setSoftDrop(true)
                }
                return true
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                if (softDropDrag) {
                    engine.setSoftDrop(false)
                }
                val totalDx = event.x - touchStartX
                val totalDy = event.y - touchStartY
                if (!dragMovedCols && !softDropDrag && abs(totalDx) < 18f * d && abs(totalDy) < 18f * d) {
                    engine.rotate(1)
                    invalidate()
                } else if (totalDy > 95f * d && abs(totalDy) > abs(totalDx) * 1.4f && event.actionMasked == MotionEvent.ACTION_UP) {
                    engine.hardDrop()
                    invalidate()
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
        val d = density
        val w = width.toFloat()
        val h = height.toFloat()
        val topOffset = if (w < 540f * d) 88f * d else 62f * d
        val bottomControlsH = 54f * d
        val availH = max(200f, h - topOffset - bottomControlsH - 16f * d)

        val sideReserve = if (w >= 480f * d) 144f * d else 16f * d
        val cellSz = floor(min(availH / BlockDropEngine.ROWS, (w - sideReserve) / BlockDropEngine.COLS))
            .coerceIn(10f, 44f * d)
        val wellW = cellSz * BlockDropEngine.COLS
        val wellH = cellSz * BlockDropEngine.ROWS
        val wellX = (w - wellW) / 2f
        val wellY = topOffset + (availH - wellH) / 2f

        // Neon-glass well backdrop
        workRect.set(wellX - 6f * d, wellY - 6f * d, wellX + wellW + 6f * d, wellY + wellH + 6f * d)
        fillPaint.color = 0xCC090D16.toInt()
        canvas.drawRoundRect(workRect, 10f * d, 10f * d, fillPaint)
        strokePaint.color = 0xAA38BDF8.toInt()
        strokePaint.strokeWidth = 1.8f * d
        canvas.drawRoundRect(workRect, 10f * d, 10f * d, strokePaint)

        // Subtle grid
        for (c in 1 until BlockDropEngine.COLS) {
            val gx = wellX + c * cellSz
            canvas.drawLine(gx, wellY, gx, wellY + wellH, gridPaint)
        }
        for (r in 1 until BlockDropEngine.ROWS) {
            val gy = wellY + r * cellSz
            canvas.drawLine(wellX, gy, wellX + wellW, gy, gridPaint)
        }

        // Locked cells
        for (r in 0 until BlockDropEngine.ROWS) {
            for (c in 0 until BlockDropEngine.COLS) {
                val kind = engine.board[r][c] ?: continue
                drawBlockCell(canvas, wellX + c * cellSz, wellY + r * cellSz, cellSz, kind, isGhost = false, d = d)
            }
        }

        // Ghost & active piece
        if (engine.phase == BlockDropPhase.PLAYING || engine.phase == BlockDropPhase.PAUSED) {
            val cells = BlockDropEngine.cellsFor(engine.curKind, engine.curRot)
            val ghostY = engine.computeGhostY()
            if (ghostY > engine.curY) {
                for (c in cells) {
                    val bx = engine.curX + c[0]
                    val by = ghostY + c[1]
                    if (bx in 0 until BlockDropEngine.COLS && by in 0 until BlockDropEngine.ROWS) {
                        drawBlockCell(canvas, wellX + bx * cellSz, wellY + by * cellSz, cellSz, engine.curKind, isGhost = true, d = d)
                    }
                }
            }
            for (c in cells) {
                val bx = engine.curX + c[0]
                val by = engine.curY + c[1]
                if (bx in 0 until BlockDropEngine.COLS && by in 0 until BlockDropEngine.ROWS) {
                    drawBlockCell(canvas, wellX + bx * cellSz, wellY + by * cellSz, cellSz, engine.curKind, isGhost = false, d = d)
                }
            }
        }

        // Shockwaves
        for (sw in engine.shockwaves) {
            val t = (sw.timer / sw.maxTimer).coerceIn(0f, 1f)
            val alpha = (t * 210f).roundToInt().coerceIn(0, 255)
            fillPaint.color = (alpha shl 24) or (sw.argb and 0x00FFFFFF)
            val sy = wellY + sw.row * cellSz
            cellRect.set(wellX - 4f * d, sy, wellX + wellW + 4f * d, sy + cellSz)
            canvas.drawRoundRect(cellRect, 4f * d, 4f * d, fillPaint)
        }

        // Side panels if space allows
        val sideW = 64f * d
        if (wellX - sideW - 12f * d >= 6f * d) {
            val holdList = engine.holdKind?.let { listOf(it) } ?: emptyList()
            drawMiniPanel(canvas, wellX - sideW - 10f * d, wellY, sideW, 74f * d, "HOLD", holdList, engine.holdUsed, d)
        }
        if (wellX + wellW + 10f * d + sideW <= w - 6f * d) {
            drawMiniPanel(canvas, wellX + wellW + 10f * d, wellY, sideW, 176f * d, "NEXT", engine.nextPreview(3), false, d)
        }

        // Score popups
        boldPaint.textSize = 14f * d
        boldPaint.textAlign = Paint.Align.CENTER
        for ((idx, pop) in engine.popups.withIndex()) {
            val t = (pop.timer / pop.maxTimer).coerceIn(0f, 1f)
            val py = wellY + wellH * 0.35f - (1f - t) * 28f * d - idx * 20f * d
            boldPaint.color = pop.argb
            canvas.drawText(pop.text, wellX + wellW / 2f, py, boldPaint)
        }

        // Subtle bottom touch HUD buttons (Hold / Rotate / Drop)
        val btnW = min(96f * d, (w - 36f * d) / 3f)
        val btnH = 36f * d
        val btnY = h - btnH - 12f * d
        val gap = 10f * d
        val startX = (w - (btnW * 3f + gap * 2f)) / 2f
        holdBtnRect.set(startX, btnY, startX + btnW, btnY + btnH)
        rotBtnRect.set(startX + btnW + gap, btnY, startX + btnW * 2f + gap, btnY + btnH)
        dropBtnRect.set(startX + (btnW + gap) * 2f, btnY, startX + btnW * 3f + gap * 2f, btnY + btnH)

        drawActionPill(canvas, holdBtnRect, "HOLD", d)
        drawActionPill(canvas, rotBtnRect, "ROTATE", d)
        drawActionPill(canvas, dropBtnRect, "DROP", d)
    }

    private fun drawBlockCell(canvas: Canvas, x: Float, y: Float, sz: Float, kind: BlockKind, isGhost: Boolean, d: Float) {
        val pad = max(1f, sz * 0.06f)
        cellRect.set(x + pad, y + pad, x + sz - pad, y + sz - pad)
        val rad = max(2f, sz * 0.14f)
        if (isGhost) {
            strokePaint.color = (0x66 shl 24) or (kind.wireArgb and 0x00FFFFFF)
            strokePaint.strokeWidth = 1.4f * d
            canvas.drawRoundRect(cellRect, rad, rad, strokePaint)
            return
        }
        fillPaint.color = kind.fillArgb
        canvas.drawRoundRect(cellRect, rad, rad, fillPaint)
        strokePaint.color = kind.wireArgb
        strokePaint.strokeWidth = 1.2f * d
        canvas.drawRoundRect(cellRect, rad, rad, strokePaint)
    }

    private fun drawMiniPanel(
        canvas: Canvas,
        x: Float,
        y: Float,
        w: Float,
        h: Float,
        title: String,
        kinds: List<BlockKind>,
        dimmed: Boolean,
        d: Float
    ) {
        workRect.set(x, y, x + w, y + h)
        fillPaint.color = 0xCC090D16.toInt()
        canvas.drawRoundRect(workRect, 8f * d, 8f * d, fillPaint)
        strokePaint.color = if (dimmed) 0x4464748B else 0x8838BDF8.toInt()
        strokePaint.strokeWidth = 1.2f * d
        canvas.drawRoundRect(workRect, 8f * d, 8f * d, strokePaint)

        boldPaint.textSize = 9.5f * d
        boldPaint.color = 0xFF94A3B8.toInt()
        boldPaint.textAlign = Paint.Align.CENTER
        canvas.drawText(title, x + w / 2f, y + 14f * d, boldPaint)

        val mini = 10f * d
        for ((idx, k) in kinds.withIndex()) {
            val cells = BlockDropEngine.cellsFor(k, 0)
            var minX = 9
            var maxX = -1
            var minY = 9
            var maxY = -1
            for (c in cells) {
                minX = min(minX, c[0])
                maxX = max(maxX, c[0])
                minY = min(minY, c[1])
                maxY = max(maxY, c[1])
            }
            val pw = (maxX - minX + 1) * mini
            val ph = (maxY - minY + 1) * mini
            val ox = x + (w - pw) / 2f - minX * mini
            val oy = y + 24f * d + idx * 48f * d + (36f * d - ph) / 2f - minY * mini
            for (c in cells) {
                drawBlockCell(canvas, ox + c[0] * mini, oy + c[1] * mini, mini, k, dimmed, d)
            }
        }
    }

    private fun drawActionPill(canvas: Canvas, rect: RectF, label: String, d: Float) {
        fillPaint.color = 0xCC111827.toInt()
        canvas.drawRoundRect(rect, 18f * d, 18f * d, fillPaint)
        strokePaint.color = 0x8838BDF8.toInt()
        strokePaint.strokeWidth = 1.2f * d
        canvas.drawRoundRect(rect, 18f * d, 18f * d, strokePaint)
        boldPaint.textSize = 11f * d
        boldPaint.color = 0xFFE2E8F0.toInt()
        boldPaint.textAlign = Paint.Align.CENTER
        val fm = boldPaint.fontMetrics
        canvas.drawText(label, rect.centerX(), rect.centerY() - (fm.ascent + fm.descent) / 2f, boldPaint)
    }
}
