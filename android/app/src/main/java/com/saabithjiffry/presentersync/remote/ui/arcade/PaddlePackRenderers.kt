package com.saabithjiffry.presentersync.remote.ui.arcade

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.view.KeyEvent
import android.view.MotionEvent
import com.saabithjiffry.presentersync.remote.config.HudColorPalette
import kotlin.math.abs

/**
 * Sector Z-03: Android Brick Breaker overlay renderer.
 */
class BrickBreakerOverlayView(
    context: Context,
    private val engine: BrickBreakerEngine,
    onExitRequested: () -> Unit,
    onStateInteracted: () -> Unit = {},
    onMuteKeyEvent: (KeyEvent) -> Boolean = { false }
) : ArcadeCanvasBaseView(context, onExitRequested, onStateInteracted, onMuteKeyEvent) {

    override fun buildScoreboardBadge(): String = "BRICK BREAKER"

    override fun buildScoreboardStats(): String {
        val perks = buildString {
            if (engine.wideTimerSec > 0f) append(" · WIDE")
            if (engine.laserTimerSec > 0f) append(" · LASER")
        }
        return "Score ${engine.score} · Best ${engine.highScore} · W${engine.wave} · ${"♥".repeat(engine.lives.coerceAtLeast(0))}$perks"
    }

    override fun buildExtraChipLabel(): String = "Launch / Fire"

    override fun buildPauseTitle(): String = "BRICK BREAKER PAUSED"

    override fun buildPauseSubtitle(): String = "Drag paddle horizontally or use Arrows / A-D + Space"

    override fun buildGameOverSubtitle(): String = "Wave ${engine.wave} · Score ${engine.score} · Best ${engine.highScore}"

    override fun isGamePaused(): Boolean = engine.phase == PaddleGamePhase.PAUSED

    override fun isGameOver(): Boolean = engine.phase == PaddleGamePhase.GAME_OVER

    override fun onExtraTopAction() {
        engine.launchOrFire()
    }

    override fun onTogglePause() {
        engine.togglePause()
    }

    override fun onRestartGame() {
        engine.startNewSession(
            widthPx = width.coerceAtLeast(320),
            heightPx = height.coerceAtLeast(320),
            screenDensity = density,
            initialHighScore = maxOf(engine.highScore, config.arcadeHighScores["brick_breaker"] ?: 0),
            bumperRect = pillRectPx
        )
    }

    override fun onGameKey(keyCode: Int, isDown: Boolean, event: KeyEvent): Boolean {
        when (keyCode) {
            KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_A -> {
                engine.touchDragActive = false
                engine.inputLeft = isDown
                return true
            }
            KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.KEYCODE_D -> {
                engine.touchDragActive = false
                engine.inputRight = isDown
                return true
            }
            KeyEvent.KEYCODE_SPACE, KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_BUTTON_A -> {
                if (isDown) {
                    if (engine.phase == PaddleGamePhase.GAME_OVER) {
                        onRestartGame()
                    } else {
                        engine.launchOrFire()
                    }
                }
                return true
            }
            KeyEvent.KEYCODE_P -> {
                if (isDown && event.repeatCount == 0) {
                    engine.togglePause()
                }
                return true
            }
            KeyEvent.KEYCODE_R -> {
                if (isDown && engine.phase == PaddleGamePhase.GAME_OVER) {
                    onRestartGame()
                }
                return true
            }
        }
        return false
    }

    override fun onGameTouch(event: MotionEvent): Boolean {
        if (engine.phase != PaddleGamePhase.PLAYING) return true
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_MOVE -> {
                engine.touchDragActive = true
                engine.touchTargetX = event.x
                if (event.actionMasked == MotionEvent.ACTION_DOWN) {
                    engine.launchOrFire()
                }
                onStateInteracted()
                return true
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                engine.touchDragActive = false
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
        fillPaint.color = withAlpha(if (isDark) 0x070B14 else 0x0F172A, if (isDark) 136 else 116)
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), fillPaint)

        // Mic Pill Bumper
        engine.pillBumper?.let { b ->
            val bumperColor = if (isMicMuted) palette.mutedBg else palette.liveBg
            workRect.set(b.left, b.top, b.right, b.bottom)
            val rad = (b.bottom - b.top) / 2f
            fillPaint.color = withAlpha(bumperColor, 34)
            canvas.drawRoundRect(workRect, rad, rad, fillPaint)
            strokePaint.color = withAlpha(bumperColor, 175)
            strokePaint.strokeWidth = 1.8f * d
            canvas.drawRoundRect(workRect, rad, rad, strokePaint)
        }

        // Armored Bricks
        for (br in engine.bricks) {
            val fillRgb = when {
                br.hp >= 3 -> 0xF59E0B
                br.hp == 2 -> 0x38BDF8
                else -> 0x10B981
            }
            val strokeRgb = when {
                br.hp >= 3 -> 0xFDE68A
                br.hp == 2 -> 0xBAE6FD
                else -> 0xA7F3D0
            }
            workRect.set(br.x, br.y, br.x + br.w, br.y + br.h)
            val rad = 5.5f * d
            fillPaint.color = withAlpha(fillRgb, 212)
            canvas.drawRoundRect(workRect, rad, rad, fillPaint)
            strokePaint.color = withAlpha(strokeRgb, 245)
            strokePaint.strokeWidth = (if (br.hp >= 2) 1.9f else 1.2f) * d
            canvas.drawRoundRect(workRect, rad, rad, strokePaint)

            if (br.hp >= 2) {
                boldPaint.textSize = 9.5f * d
                boldPaint.color = withAlpha(0x0F172A, 240)
                boldPaint.textAlign = Paint.Align.CENTER
                val fm = boldPaint.fontMetrics
                canvas.drawText("x${br.hp}", workRect.centerX(), workRect.centerY() - (fm.ascent + fm.descent) / 2f, boldPaint)
            }
        }

        // Falling HUD-pill drops
        for (dr in engine.drops) {
            val rgb = when (dr.kind) {
                BrickDropKind.MULTIBALL -> 0x38BDF8
                BrickDropKind.WIDE_PADDLE -> 0x10B981
                BrickDropKind.LASER -> 0xF43F5E
            }
            workRect.set(dr.x - dr.w / 2f, dr.y - dr.h / 2f, dr.x + dr.w / 2f, dr.y + dr.h / 2f)
            fillPaint.color = withAlpha(rgb, 215)
            canvas.drawRoundRect(workRect, dr.h / 2f, dr.h / 2f, fillPaint)
            strokePaint.color = withAlpha(0xFFFFFF, 245)
            strokePaint.strokeWidth = 1.3f * d
            canvas.drawRoundRect(workRect, dr.h / 2f, dr.h / 2f, strokePaint)

            boldPaint.textSize = 9.5f * d
            boldPaint.color = withAlpha(0xFFFFFF, 250)
            boldPaint.textAlign = Paint.Align.CENTER
            val fm = boldPaint.fontMetrics
            canvas.drawText(dr.kind.label, workRect.centerX(), workRect.centerY() - (fm.ascent + fm.descent) / 2f, boldPaint)
        }

        // Laser bolts
        for (ls in engine.lasers) {
            workRect.set(ls.x, ls.y, ls.x + ls.w, ls.y + ls.h)
            fillPaint.color = withAlpha(0xFB7185, 250)
            canvas.drawRoundRect(workRect, 2f * d, 2f * d, fillPaint)
        }

        // Neon Bottom-Edge Paddle
        val padColor = when {
            engine.laserTimerSec > 0f -> 0xF43F5E
            engine.wideTimerSec > 0f -> 0x10B981
            else -> 0x0EA5E9
        }
        workRect.set(engine.paddleX, engine.paddleY, engine.paddleX + engine.paddleW, engine.paddleY + engine.paddleH)
        fillPaint.color = withAlpha(padColor, 232)
        canvas.drawRoundRect(workRect, engine.paddleH / 2f, engine.paddleH / 2f, fillPaint)
        strokePaint.color = withAlpha(0xE0F2FE, 250)
        strokePaint.strokeWidth = 1.8f * d
        canvas.drawRoundRect(workRect, engine.paddleH / 2f, engine.paddleH / 2f, strokePaint)

        // Energy Orbs
        for (o in engine.orbs) {
            fillPaint.color = withAlpha(0x38BDF8, 92)
            canvas.drawCircle(o.x, o.y, o.radius + 3.5f * d, fillPaint)
            fillPaint.color = withAlpha(0xF8FAFC, 252)
            canvas.drawCircle(o.x, o.y, o.radius, fillPaint)
        }

        // Particles & Popups
        for (p in engine.particles) {
            val alpha = ((p.lifeSec / p.maxLifeSec).coerceIn(0f, 1f) * 230).toInt()
            fillPaint.color = withAlpha(p.colorRgb, alpha)
            canvas.drawCircle(p.x, p.y, 2.2f * d, fillPaint)
        }
        for (pp in engine.popups) {
            val alpha = ((pp.lifeSec / pp.maxLifeSec).coerceIn(0f, 1f) * 245).toInt()
            boldPaint.textSize = 12f * d
            boldPaint.color = withAlpha(pp.colorRgb, alpha)
            boldPaint.textAlign = Paint.Align.CENTER
            canvas.drawText(pp.text, pp.x, pp.y, boldPaint)
        }
    }
}

/**
 * Sector Z-04: Android Cyber Pong / Air Hockey overlay renderer.
 * Supports 1P vs Adaptive AI and 2P Split-Screen Multi-Touch (simultaneous left/right half dragging).
 */
class CyberPongOverlayView(
    context: Context,
    private val engine: CyberPongEngine,
    onExitRequested: () -> Unit,
    onStateInteracted: () -> Unit = {},
    onMuteKeyEvent: (KeyEvent) -> Boolean = { false }
) : ArcadeCanvasBaseView(context, onExitRequested, onStateInteracted, onMuteKeyEvent) {

    override fun buildScoreboardBadge(): String = "CYBER PONG"

    override fun buildScoreboardStats(): String {
        val rhs = if (engine.twoPlayerMode) "P2" else "AI"
        return "P1 ${engine.leftScore} : ${engine.rightScore} $rhs · Rally ${engine.rally} · Best ${engine.highScore}"
    }

    override fun buildExtraChipLabel(): String {
        return if (engine.twoPlayerMode) "Mode: 2P Split" else "Mode: 1P AI"
    }

    override fun buildPauseTitle(): String = "CYBER PONG PAUSED"

    override fun buildPauseSubtitle(): String = "Drag paddle (or both halves in 2P Split) · First to 7"

    override fun buildGameOverSubtitle(): String {
        val win = if (engine.winnerLabel.isNotEmpty()) "${engine.winnerLabel} WINS! · " else ""
        return "${win}Set ${engine.leftScore}-${engine.rightScore} · Score ${engine.score} · Best ${engine.highScore}"
    }

    override fun isGamePaused(): Boolean = engine.phase == PaddleGamePhase.PAUSED

    override fun isGameOver(): Boolean = engine.phase == PaddleGamePhase.GAME_OVER

    override fun onExtraTopAction() {
        engine.toggleTwoPlayerMode()
    }

    override fun onTogglePause() {
        engine.togglePause()
    }

    override fun onRestartGame() {
        engine.startNewSession(
            widthPx = width.coerceAtLeast(320),
            heightPx = height.coerceAtLeast(320),
            screenDensity = density,
            initialHighScore = maxOf(engine.highScore, config.arcadeHighScores["cyber_pong"] ?: 0),
            preserveTwoPlayer = true
        )
    }

    override fun onGameKey(keyCode: Int, isDown: Boolean, event: KeyEvent): Boolean {
        when (keyCode) {
            KeyEvent.KEYCODE_W -> {
                engine.leftTouchActive = false
                engine.p1InputUp = isDown
                return true
            }
            KeyEvent.KEYCODE_S -> {
                engine.leftTouchActive = false
                engine.p1InputDown = isDown
                return true
            }
            KeyEvent.KEYCODE_DPAD_UP -> {
                if (engine.twoPlayerMode) engine.rightTouchActive = false else engine.leftTouchActive = false
                engine.p2InputUp = isDown
                return true
            }
            KeyEvent.KEYCODE_DPAD_DOWN -> {
                if (engine.twoPlayerMode) engine.rightTouchActive = false else engine.leftTouchActive = false
                engine.p2InputDown = isDown
                return true
            }
            KeyEvent.KEYCODE_2, KeyEvent.KEYCODE_BUTTON_Y -> {
                if (isDown && event.repeatCount == 0) {
                    engine.toggleTwoPlayerMode()
                }
                return true
            }
            KeyEvent.KEYCODE_P -> {
                if (isDown && event.repeatCount == 0) {
                    engine.togglePause()
                }
                return true
            }
            KeyEvent.KEYCODE_R, KeyEvent.KEYCODE_SPACE, KeyEvent.KEYCODE_ENTER -> {
                if (isDown && engine.phase == PaddleGamePhase.GAME_OVER) {
                    onRestartGame()
                }
                return true
            }
        }
        return false
    }

    override fun onGameTouch(event: MotionEvent): Boolean {
        if (engine.phase != PaddleGamePhase.PLAYING) return true
        val masked = event.actionMasked
        if (masked == MotionEvent.ACTION_CANCEL) {
            engine.leftTouchActive = false
            engine.rightTouchActive = false
            return true
        }

        val liftingIndex = if (masked == MotionEvent.ACTION_UP || masked == MotionEvent.ACTION_POINTER_UP) {
            event.actionIndex
        } else {
            -1
        }

        val midX = width * 0.5f
        var sawLeft = false
        var sawRight = false
        var leftY = 0f
        var rightY = 0f

        for (i in 0 until event.pointerCount) {
            if (i == liftingIndex) continue
            val px = event.getX(i)
            val py = event.getY(i)
            if (!engine.twoPlayerMode || px < midX) {
                sawLeft = true
                leftY = py
            } else {
                sawRight = true
                rightY = py
            }
        }

        engine.leftTouchActive = sawLeft
        if (sawLeft) {
            engine.leftTouchTargetY = leftY
        }

        if (engine.twoPlayerMode) {
            engine.rightTouchActive = sawRight
            if (sawRight) {
                engine.rightTouchTargetY = rightY
            }
        } else {
            engine.rightTouchActive = false
        }

        onStateInteracted()
        return true
    }

    override fun onGameFrameRender(
        canvas: Canvas,
        palette: HudColorPalette,
        isDark: Boolean,
        opacity: Int
    ) {
        val d = density
        fillPaint.color = withAlpha(if (isDark) 0x070B14 else 0x0F172A, if (isDark) 136 else 116)
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), fillPaint)

        // Cyber court center line & circle
        val midX = width * 0.5f
        val midY = height * 0.5f
        strokePaint.color = withAlpha(0x38BDF8, 72)
        strokePaint.strokeWidth = 2f * d
        canvas.drawLine(midX, 64f * d, midX, height - 16f * d, strokePaint)
        canvas.drawCircle(midX, midY, 54f * d, strokePaint)

        // Left & Right Neon Paddles
        workRect.set(
            engine.leftPaddleX,
            engine.leftPaddleY,
            engine.leftPaddleX + engine.paddleW,
            engine.leftPaddleY + engine.paddleH
        )
        fillPaint.color = withAlpha(0x0EA5E9, 232)
        canvas.drawRoundRect(workRect, engine.paddleW / 2f, engine.paddleW / 2f, fillPaint)
        strokePaint.color = withAlpha(0xBAE6FD, 250)
        strokePaint.strokeWidth = 1.8f * d
        canvas.drawRoundRect(workRect, engine.paddleW / 2f, engine.paddleW / 2f, strokePaint)

        workRect.set(
            engine.rightPaddleX,
            engine.rightPaddleY,
            engine.rightPaddleX + engine.paddleW,
            engine.rightPaddleY + engine.paddleH
        )
        fillPaint.color = withAlpha(0xF43F5E, 232)
        canvas.drawRoundRect(workRect, engine.paddleW / 2f, engine.paddleW / 2f, fillPaint)
        strokePaint.color = withAlpha(0xFECDD3, 250)
        strokePaint.strokeWidth = 1.8f * d
        canvas.drawRoundRect(workRect, engine.paddleW / 2f, engine.paddleW / 2f, strokePaint)

        // Velocity-Spin Energy Puck
        val pk = engine.puck
        val glowRgb = if (abs(pk.spin) > 75f) 0xF59E0B else 0x38BDF8
        fillPaint.color = withAlpha(glowRgb, 102)
        canvas.drawCircle(pk.x, pk.y, pk.radius + 4f * d, fillPaint)
        fillPaint.color = withAlpha(0xF8FAFC, 252)
        canvas.drawCircle(pk.x, pk.y, pk.radius, fillPaint)

        // Particles & Popups
        for (p in engine.particles) {
            val alpha = ((p.lifeSec / p.maxLifeSec).coerceIn(0f, 1f) * 230).toInt()
            fillPaint.color = withAlpha(p.colorRgb, alpha)
            canvas.drawCircle(p.x, p.y, 2.2f * d, fillPaint)
        }
        for (pp in engine.popups) {
            val alpha = ((pp.lifeSec / pp.maxLifeSec).coerceIn(0f, 1f) * 245).toInt()
            boldPaint.textSize = 12f * d
            boldPaint.color = withAlpha(pp.colorRgb, alpha)
            boldPaint.textAlign = Paint.Align.CENTER
            canvas.drawText(pp.text, pp.x, pp.y, boldPaint)
        }
    }
}
