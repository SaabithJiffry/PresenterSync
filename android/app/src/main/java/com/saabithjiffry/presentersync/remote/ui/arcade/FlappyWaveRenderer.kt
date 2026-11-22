package com.saabithjiffry.presentersync.remote.ui.arcade

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.view.KeyEvent
import android.view.MotionEvent
import com.saabithjiffry.presentersync.remote.config.HudColorPalette
import kotlin.math.max
import kotlin.math.min

/**
 * Sector Z-05: Android Clicker Flappy / Gravity Wave overlay renderer.
 */
class FlappyWaveOverlayView(
    context: Context,
    private val engine: FlappyWaveEngine,
    onExitRequested: () -> Unit,
    onStateInteracted: () -> Unit = {},
    onMuteKeyEvent: (KeyEvent) -> Boolean = { false }
) : ArcadeCanvasBaseView(context, onExitRequested, onStateInteracted, onMuteKeyEvent) {

    override fun buildScoreboardBadge(): String {
        return if (engine.mode == FlappyMode.GRAVITY_WAVE) "GRAVITY WAVE" else "CLICKER FLAPPY"
    }

    override fun buildScoreboardStats(): String {
        val perks = buildString {
            if (engine.shieldTimerSec > 0f) append(" · SHIELD")
            if (engine.slowMoTimerSec > 0f) append(" · SLOW-MO")
        }
        return "Score ${engine.score} · Best ${engine.highScore}$perks"
    }

    override fun buildExtraChipLabel(): String {
        return if (engine.mode == FlappyMode.GRAVITY_WAVE) "Mode: Wave" else "Mode: Flap"
    }

    override fun buildPauseTitle(): String = "CLICKER FLAPPY PAUSED"

    override fun buildPauseSubtitle(): String = "Tap/Hold screen or press Clicker Slide / Space / Up"

    override fun buildGameOverSubtitle(): String = "Score ${engine.score} · Best ${engine.highScore}"

    override fun isGamePaused(): Boolean = engine.phase == FlappyPhase.PAUSED

    override fun isGameOver(): Boolean = engine.phase == FlappyPhase.GAME_OVER

    override fun onExtraTopAction() {
        engine.toggleMode()
    }

    override fun onTogglePause() {
        engine.togglePause()
    }

    override fun onRestartGame() {
        engine.startNewSession(
            widthPx = width.coerceAtLeast(320),
            heightPx = height.coerceAtLeast(320),
            screenDensity = density,
            initialHighScore = maxOf(engine.highScore, config.arcadeHighScores["flappy"] ?: 0),
            bumperRect = pillRectPx,
            initialMode = engine.mode
        )
    }

    override fun onGameKey(keyCode: Int, isDown: Boolean, event: KeyEvent): Boolean {
        if (isConfiguredMuteKey(event)) return false

        when (keyCode) {
            KeyEvent.KEYCODE_M, KeyEvent.KEYCODE_BUTTON_Y -> {
                if (isDown && event.repeatCount == 0) {
                    engine.toggleMode()
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
                if (isDown && engine.phase == FlappyPhase.GAME_OVER) {
                    onRestartGame()
                }
                return true
            }
        }

        val keyName = KeyEvent.keyCodeToString(keyCode)
        if (FlappyWaveEngine.isClickerKeyAllowed(keyName, config.hwMuteHotkey)) {
            if (isDown && engine.phase == FlappyPhase.GAME_OVER) {
                onRestartGame()
                return true
            }
            if (!isDown || event.repeatCount == 0) {
                engine.flapOrHold(isDown)
            }
            return true
        }
        return false
    }

    override fun onGameTouch(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                if (engine.phase == FlappyPhase.GAME_OVER) {
                    onRestartGame()
                } else {
                    engine.flapOrHold(true)
                }
                onStateInteracted()
                invalidate()
                return true
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                engine.flapOrHold(false)
                invalidate()
                return true
            }
            MotionEvent.ACTION_MOVE -> {
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

        val minY = engine.topBound()
        val maxY = engine.bottomBound()
        val isWave = (engine.mode == FlappyMode.GRAVITY_WAVE)

        // Scrolling neon gate pillars with clearance caps
        val fillRgb = if (isWave) 0x0F172A else 0x111827
        val strokeRgb = if (isWave) 0x38BDF8 else 0x10B981
        val capRgb = if (isWave) 0x0EA5E9 else 0x34D399
        val rad = 7f * d

        for (gt in engine.gates) {
            val gapTop = gt.gapY - gt.gapH * 0.5f
            val gapBot = gt.gapY + gt.gapH * 0.5f
            val topH = max(0f, gapTop - minY)
            val botH = max(0f, maxY - gapBot)

            if (topH > 4f * d) {
                workRect.set(gt.x, minY, gt.x + gt.w, minY + topH)
                fillPaint.color = withAlpha(fillRgb, 210)
                canvas.drawRoundRect(workRect, rad, rad, fillPaint)
                strokePaint.color = withAlpha(strokeRgb, 240)
                strokePaint.strokeWidth = 1.8f * d
                canvas.drawRoundRect(workRect, rad, rad, strokePaint)

                val capH = min(10f * d, topH)
                workRect.set(gt.x - 3f * d, gapTop - capH, gt.x + gt.w + 3f * d, gapTop)
                fillPaint.color = withAlpha(capRgb, 245)
                canvas.drawRoundRect(workRect, 4f * d, 4f * d, fillPaint)
            }

            if (botH > 4f * d) {
                workRect.set(gt.x, gapBot, gt.x + gt.w, gapBot + botH)
                fillPaint.color = withAlpha(fillRgb, 210)
                canvas.drawRoundRect(workRect, rad, rad, fillPaint)
                strokePaint.color = withAlpha(strokeRgb, 240)
                strokePaint.strokeWidth = 1.8f * d
                canvas.drawRoundRect(workRect, rad, rad, strokePaint)

                val capH = min(10f * d, botH)
                workRect.set(gt.x - 3f * d, gapBot, gt.x + gt.w + 3f * d, gapBot + capH)
                fillPaint.color = withAlpha(capRgb, 245)
                canvas.drawRoundRect(workRect, 4f * d, 4f * d, fillPaint)
            }
        }

        // Bonus rings (SHIELD / SLOW-MO)
        for (rg in engine.rings) {
            val ringRgb = if (rg.kind == FlappyBonusKind.SHIELD) 0x38BDF8 else 0xA855F7
            strokePaint.color = withAlpha(ringRgb, 245)
            strokePaint.strokeWidth = 2.4f * d
            canvas.drawCircle(rg.x, rg.y, rg.radius, strokePaint)
        }

        // Glowing ribbon trail behind craft
        val trail = engine.trail
        if (trail.size >= 2) {
            val glowRgb = if (isWave) 0x0EA5E9 else 0x10B981
            val lineRgb = if (isWave) 0x38BDF8 else 0x34D399
            for (i in 0 until trail.size - 1) {
                val p1 = trail[i]
                val p2 = trail[i + 1]
                strokePaint.color = withAlpha(glowRgb, 85)
                strokePaint.strokeWidth = 6.5f * d
                canvas.drawLine(p1.x, p1.y, p2.x, p2.y, strokePaint)
                strokePaint.color = withAlpha(lineRgb, 225)
                strokePaint.strokeWidth = 2.5f * d
                canvas.drawLine(p1.x, p1.y, p2.x, p2.y, strokePaint)
            }
        }

        // Craft & Shield aura
        val r = engine.craftRadius
        val craftRgb = if (isWave) {
            if (engine.isHolding) 0x38BDF8 else 0x818CF8
        } else {
            0x34D399
        }
        workRect.set(engine.craftX - r, engine.craftY - r * 0.78f, engine.craftX + r, engine.craftY + r * 0.78f)
        fillPaint.color = withAlpha(craftRgb, 242)
        canvas.drawRoundRect(workRect, 7f * d, 7f * d, fillPaint)
        strokePaint.color = withAlpha(0xF8FAFC, 250)
        strokePaint.strokeWidth = 1.8f * d
        canvas.drawRoundRect(workRect, 7f * d, 7f * d, strokePaint)

        if (engine.shieldTimerSec > 0f) {
            strokePaint.color = withAlpha(0x38BDF8, 240)
            strokePaint.strokeWidth = 2.2f * d
            canvas.drawCircle(engine.craftX, engine.craftY, r + 5f * d, strokePaint)
        }

        // Particles & Floating Popups
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
