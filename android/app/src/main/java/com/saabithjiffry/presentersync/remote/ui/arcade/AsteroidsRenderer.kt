package com.saabithjiffry.presentersync.remote.ui.arcade

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.view.KeyEvent
import android.view.MotionEvent
import com.saabithjiffry.presentersync.remote.config.HudColorPalette
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

/**
 * Vector Asteroid / Alien Blaster overlay view extending the shared Sector Z canvas host.
 */
class AsteroidsOverlayView(
    context: Context,
    private val engine: AsteroidsEngine,
    onExitRequested: () -> Unit,
    onStateInteracted: () -> Unit = {},
    onMuteKeyEvent: (KeyEvent) -> Boolean = { false }
) : ArcadeCanvasBaseView(context, onExitRequested, onStateInteracted, onMuteKeyEvent) {

    private val vectorPath = Path()

    override fun buildScoreboardBadge(): String = "ASTEROIDS"

    override fun buildScoreboardStats(): String {
        val perks = buildString {
            if (engine.rapidTimerSec > 0f) append(" · RAPID")
            if (engine.spreadTimerSec > 0f) append(" · SPREAD")
            if (engine.shieldTimerSec > 0f) append(" · SHIELD")
        }
        return "Score ${engine.score} · Best ${engine.highScore} · W${engine.wave} · ${"♥".repeat(engine.lives.coerceAtLeast(0))}$perks"
    }

    override fun buildExtraChipLabel(): String {
        return if (engine.autoFireEnabled) "Auto: ON" else "Auto: OFF"
    }

    override fun buildPauseTitle(): String = "ASTEROIDS PAUSED"

    override fun buildPauseSubtitle(): String = "Drag to steer & fire, or use WASD/Arrows + Space"

    override fun buildGameOverSubtitle(): String = "Wave ${engine.wave} · Score ${engine.score} · Best ${engine.highScore}"

    override fun isGamePaused(): Boolean = engine.phase == AsteroidsPhase.PAUSED

    override fun isGameOver(): Boolean = engine.phase == AsteroidsPhase.GAME_OVER

    override fun onExtraTopAction() {
        engine.autoFireEnabled = !engine.autoFireEnabled
    }

    override fun onTogglePause() {
        engine.togglePause()
    }

    override fun onRestartGame() {
        engine.startNewSession(
            widthPx = width.coerceAtLeast(320),
            heightPx = height.coerceAtLeast(320),
            screenDensity = density,
            initialHighScore = maxOf(engine.highScore, config.arcadeHighScores["asteroids"] ?: 0),
            bumperRect = pillRectPx
        )
    }

    override fun onGameKey(keyCode: Int, isDown: Boolean, event: KeyEvent): Boolean {
        when (keyCode) {
            KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_A -> {
                engine.inputTurnLeft = isDown
                return true
            }
            KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.KEYCODE_D -> {
                engine.inputTurnRight = isDown
                return true
            }
            KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_W -> {
                engine.inputThrust = isDown
                return true
            }
            KeyEvent.KEYCODE_SPACE, KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_BUTTON_A -> {
                if (isDown && engine.phase == AsteroidsPhase.GAME_OVER) {
                    onRestartGame()
                } else {
                    engine.inputFiring = isDown
                    if (isDown) engine.firePlayerBolt()
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
                if (isDown && engine.phase == AsteroidsPhase.GAME_OVER) {
                    onRestartGame()
                }
                return true
            }
            KeyEvent.KEYCODE_F, KeyEvent.KEYCODE_BUTTON_Y -> {
                if (isDown && event.repeatCount == 0) {
                    engine.autoFireEnabled = !engine.autoFireEnabled
                }
                return true
            }
        }
        return false
    }

    override fun onGameTouch(event: MotionEvent): Boolean {
        if (engine.phase != AsteroidsPhase.PLAYING) return true
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_MOVE -> {
                engine.touchAimActive = true
                engine.touchTargetX = event.x
                engine.touchTargetY = event.y
                if (event.actionMasked == MotionEvent.ACTION_DOWN) {
                    engine.firePlayerBolt()
                }
                onStateInteracted()
                return true
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                engine.touchAimActive = false
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

        // Soft arena dim backdrop so vector lines stand out crisp over any presentation slide
        fillPaint.color = withAlpha(if (isDark) 0x070B14 else 0x0F172A, if (isDark) 132 else 112)
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), fillPaint)

        // Mic Pill Bumper silhouette (Live/Muted color outline)
        engine.pillBumper?.let { b ->
            val bumperColor = if (isMicMuted) palette.mutedBg else palette.liveBg
            workRect.set(b.left, b.top, b.right, b.bottom)
            val rad = (b.bottom - b.top) / 2f
            fillPaint.color = withAlpha(bumperColor, 38)
            canvas.drawRoundRect(workRect, rad, rad, fillPaint)
            strokePaint.color = withAlpha(bumperColor, 180)
            strokePaint.strokeWidth = 2f * d
            canvas.drawRoundRect(workRect, rad, rad, strokePaint)

            boldPaint.textSize = 9.5f * d
            boldPaint.color = withAlpha(bumperColor, 175)
            boldPaint.textAlign = Paint.Align.CENTER
            val fm = boldPaint.fontMetrics
            canvas.drawText("MIC BUMPER", workRect.centerX(), workRect.centerY() - (fm.ascent + fm.descent) / 2f, boldPaint)
        }

        // Power-up HUD pills
        for (pu in engine.powerUps) {
            val rgb = when (pu.kind) {
                AsteroidsPowerUpKind.RAPID -> 0xF59E0B
                AsteroidsPowerUpKind.SPREAD -> 0x38BDF8
                AsteroidsPowerUpKind.SHIELD -> 0x34D399
            }
            val pw = 56f * d
            val ph = 22f * d
            workRect.set(pu.x - pw / 2f, pu.y - ph / 2f, pu.x + pw / 2f, pu.y + ph / 2f)
            fillPaint.color = withAlpha(rgb, 56)
            canvas.drawRoundRect(workRect, ph / 2f, ph / 2f, fillPaint)
            strokePaint.color = withAlpha(rgb, 240)
            strokePaint.strokeWidth = 1.6f * d
            canvas.drawRoundRect(workRect, ph / 2f, ph / 2f, strokePaint)

            boldPaint.textSize = 9.5f * d
            boldPaint.color = withAlpha(0xFFFFFF, 245)
            boldPaint.textAlign = Paint.Align.CENTER
            val fm = boldPaint.fontMetrics
            canvas.drawText(pu.kind.label, workRect.centerX(), workRect.centerY() - (fm.ascent + fm.descent) / 2f, boldPaint)
        }

        // Asteroids
        for (rock in engine.rocks) {
            vectorPath.reset()
            val n = rock.vertexOffsets.size
            for (i in 0 until n) {
                val a = rock.angleRad + (i.toFloat() / n) * (2f * PI.toFloat())
                val rad = rock.radius * rock.vertexOffsets[i]
                val px = rock.x + cos(a) * rad
                val py = rock.y + sin(a) * rad
                if (i == 0) vectorPath.moveTo(px, py) else vectorPath.lineTo(px, py)
            }
            vectorPath.close()
            fillPaint.color = withAlpha(0x334155, 115)
            canvas.drawPath(vectorPath, fillPaint)
            strokePaint.color = withAlpha(0xE2E8F0, 235)
            strokePaint.strokeWidth = 1.8f * d
            canvas.drawPath(vectorPath, strokePaint)
        }

        // Roaming UFO Saucer
        engine.saucer?.let { ufo ->
            val r = ufo.radius
            workRect.set(ufo.x - r, ufo.y - r * 0.45f, ufo.x + r, ufo.y + r * 0.45f)
            fillPaint.color = withAlpha(0xF59E0B, 65)
            canvas.drawOval(workRect, fillPaint)
            strokePaint.color = withAlpha(0xFBBF24, 245)
            strokePaint.strokeWidth = 2f * d
            canvas.drawOval(workRect, strokePaint)

            workRect.set(ufo.x - r * 0.48f, ufo.y - r * 0.78f, ufo.x + r * 0.48f, ufo.y - r * 0.1f)
            canvas.drawArc(workRect, 180f, 180f, false, strokePaint)
        }

        // Bolts
        for (bolt in engine.bolts) {
            fillPaint.color = withAlpha(if (bolt.fromSaucer) 0xF87171 else 0x38BDF8, 250)
            canvas.drawCircle(bolt.x, bolt.y, (if (bolt.fromSaucer) 3.8f else 3.1f) * d, fillPaint)
        }

        // Player vector ship
        if (engine.phase != AsteroidsPhase.IDLE && engine.lives > 0) {
            val blink = engine.invulnTimerSec > 0f && (((nowNs / 80_000_000L) % 2L) == 0L)
            if (!blink) {
                val r = engine.shipRadius
                val a = engine.shipAngleRad
                val noseX = engine.shipX + cos(a) * r * 1.25f
                val noseY = engine.shipY + sin(a) * r * 1.25f
                val leftX = engine.shipX + cos(a + 2.45f) * r
                val leftY = engine.shipY + sin(a + 2.45f) * r
                val tailX = engine.shipX - cos(a) * r * 0.45f
                val tailY = engine.shipY - sin(a) * r * 0.45f
                val rightX = engine.shipX + cos(a - 2.45f) * r
                val rightY = engine.shipY + sin(a - 2.45f) * r

                vectorPath.reset()
                vectorPath.moveTo(noseX, noseY)
                vectorPath.lineTo(leftX, leftY)
                vectorPath.lineTo(tailX, tailY)
                vectorPath.lineTo(rightX, rightY)
                vectorPath.close()

                fillPaint.color = withAlpha(palette.liveBg, 95)
                canvas.drawPath(vectorPath, fillPaint)
                strokePaint.color = withAlpha(0xFFFFFF, 250)
                strokePaint.strokeWidth = 2.1f * d
                canvas.drawPath(vectorPath, strokePaint)

                if (engine.inputThrust || engine.touchAimActive) {
                    val fX = engine.shipX - cos(a) * r * (1.2f + ((nowNs / 50_000_000L) % 2L) * 0.3f)
                    val fY = engine.shipY - sin(a) * r * (1.2f + ((nowNs / 50_000_000L) % 2L) * 0.3f)
                    strokePaint.color = withAlpha(0xF59E0B, 235)
                    strokePaint.strokeWidth = 2f * d
                    canvas.drawLine(leftX * 0.35f + tailX * 0.65f, leftY * 0.35f + tailY * 0.65f, fX, fY, strokePaint)
                    canvas.drawLine(rightX * 0.35f + tailX * 0.65f, rightY * 0.35f + tailY * 0.65f, fX, fY, strokePaint)
                }
            }

            if (engine.shieldTimerSec > 0f) {
                strokePaint.color = withAlpha(0x34D399, 210)
                strokePaint.strokeWidth = 2.2f * d
                canvas.drawCircle(engine.shipX, engine.shipY, engine.shipRadius * 1.65f, strokePaint)
            }
        }

        // Particles & Popups
        for (p in engine.particles) {
            val alpha = ((p.lifeSec / p.maxLifeSec).coerceIn(0f, 1f) * 230).toInt()
            fillPaint.color = withAlpha(p.colorRgb, alpha)
            canvas.drawCircle(p.x, p.y, 2.2f * d, fillPaint)
        }
        for (pp in engine.popups) {
            val alpha = ((pp.lifeSec / pp.maxLifeSec).coerceIn(0f, 1f) * 245).toInt()
            boldPaint.textSize = 12.5f * d
            boldPaint.color = withAlpha(pp.colorRgb, alpha)
            boldPaint.textAlign = Paint.Align.CENTER
            canvas.drawText(pp.text, pp.x, pp.y, boldPaint)
        }
    }
}
