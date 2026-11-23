package com.saabithjiffry.presentersync.remote.ui.arcade

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.view.KeyEvent
import android.view.MotionEvent
import com.saabithjiffry.presentersync.remote.config.HudColorPalette

/**
 * Missile Command / Meteor Defense overlay view with multi-tap instant interceptor aiming
 * on both ACTION_DOWN and ACTION_POINTER_DOWN.
 */
class MissileDefenseOverlayView(
    context: Context,
    private val engine: MissileDefenseEngine,
    onExitRequested: () -> Unit,
    onStateInteracted: () -> Unit = {},
    onMuteKeyEvent: (KeyEvent) -> Boolean = { false }
) : ArcadeCanvasBaseView(context, onExitRequested, onStateInteracted, onMuteKeyEvent) {

    override fun buildScoreboardBadge(): String = "MISSILE DEFENSE"

    override fun buildScoreboardStats(): String {
        val comboStr = if (engine.combo > 1) " · x${engine.combo}" else ""
        return "Score ${engine.score} · Best ${engine.highScore} · W${engine.wave} · Pylons ${engine.pylonsAlive}/4$comboStr"
    }

    override fun buildPauseTitle(): String = "MISSILE DEFENSE PAUSED"

    override fun buildPauseSubtitle(): String =
        "Tap anywhere to launch interceptors · Multi-tap supported · Space/Arrows on KB"

    override fun buildGameOverSubtitle(): String =
        "Wave ${engine.wave} · Score ${engine.score} · Best ${engine.highScore}"

    override fun isGamePaused(): Boolean = engine.phase == MissileDefensePhase.PAUSED

    override fun isGameOver(): Boolean = engine.phase == MissileDefensePhase.GAME_OVER

    override fun onTogglePause() {
        engine.togglePause()
    }

    override fun onRestartGame() {
        engine.startNewSession(
            widthPx = width.coerceAtLeast(320),
            heightPx = height.coerceAtLeast(320),
            screenDensity = density,
            initialHighScore = maxOf(engine.highScore, config.arcadeHighScores["missile_defense"] ?: 0)
        )
    }

    override fun onGameKey(keyCode: Int, isDown: Boolean, event: KeyEvent): Boolean {
        when (keyCode) {
            KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_A -> {
                engine.inputLeft = isDown
                return true
            }
            KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.KEYCODE_D -> {
                engine.inputRight = isDown
                return true
            }
            KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_W -> {
                engine.inputUp = isDown
                return true
            }
            KeyEvent.KEYCODE_DPAD_DOWN, KeyEvent.KEYCODE_S -> {
                engine.inputDown = isDown
                return true
            }
            KeyEvent.KEYCODE_SPACE, KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_BUTTON_A -> {
                if (isDown) {
                    if (engine.phase == MissileDefensePhase.GAME_OVER) {
                        onRestartGame()
                    } else {
                        engine.fireInterceptor(engine.reticleX, engine.reticleY)
                    }
                }
                return true
            }
            KeyEvent.KEYCODE_P -> {
                if (isDown && event.repeatCount == 0) engine.togglePause()
                return true
            }
            KeyEvent.KEYCODE_R -> {
                if (isDown && engine.phase == MissileDefensePhase.GAME_OVER) onRestartGame()
                return true
            }
        }
        return false
    }

    override fun onGameTouch(event: MotionEvent): Boolean {
        if (engine.phase != MissileDefensePhase.PLAYING) return true
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                val idx = event.actionIndex
                val tx = event.getX(idx)
                val ty = event.getY(idx)
                engine.reticleX = tx
                engine.reticleY = ty
                engine.fireInterceptor(tx, ty, bypassCooldown = true)
                onStateInteracted()
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                engine.reticleX = event.x
                engine.reticleY = event.y
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
        fillPaint.color = withAlpha(if (isDark) 0x070B14 else 0x0F172A, if (isDark) 136 else 112)
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), fillPaint)

        // Ground baseline
        strokePaint.color = withAlpha(0x38BDF8, 130)
        strokePaint.strokeWidth = 2f * d
        canvas.drawLine(16f * d, height - 18f * d, width - 16f * d, height - 18f * d, strokePaint)

        // 4 neon shield pylons
        for (p in engine.pylons) {
            if (p.alive) {
                workRect.set(p.x - 18f * d, p.y - 10f * d, p.x + 18f * d, p.y + 10f * d)
                fillPaint.color = withAlpha(0x0EA5E9, 210)
                canvas.drawRoundRect(workRect, 6f * d, 6f * d, fillPaint)
                strokePaint.color = 0xFF7DD3FC.toInt()
                strokePaint.strokeWidth = 1.8f * d
                canvas.drawRoundRect(workRect, 6f * d, 6f * d, strokePaint)
            } else {
                workRect.set(p.x - 16f * d, p.y + 2f * d, p.x + 16f * d, p.y + 10f * d)
                fillPaint.color = withAlpha(0xEF4444, 100)
                canvas.drawRoundRect(workRect, 3f * d, 3f * d, fillPaint)
            }
        }

        // Central silo
        workRect.set(engine.siloX - 15f * d, engine.siloY - 11f * d, engine.siloX + 15f * d, engine.siloY + 11f * d)
        fillPaint.color = withAlpha(0x10B981, 210)
        canvas.drawRoundRect(workRect, 8f * d, 8f * d, fillPaint)
        strokePaint.color = 0xFF6EE7B7.toInt()
        strokePaint.strokeWidth = 1.8f * d
        canvas.drawRoundRect(workRect, 8f * d, 8f * d, strokePaint)

        // Incoming meteors & trails
        for (m in engine.meteors) {
            if (m.trailX.isNotEmpty()) {
                strokePaint.color = withAlpha(if (m.isSplitter) 0xF59E0B else 0xFB7185, 165)
                strokePaint.strokeWidth = 2.2f * d
                canvas.drawLine(m.trailX.first(), m.trailY.first(), m.x, m.y, strokePaint)
            }
            fillPaint.color = if (m.isSplitter) 0xFFF59E0B.toInt() else 0xFFF43F5E.toInt()
            canvas.drawCircle(m.x, m.y, m.radius, fillPaint)
        }

        // Interceptors & target X
        strokePaint.color = withAlpha(0x34D399, 185)
        strokePaint.strokeWidth = 2f * d
        fillPaint.color = 0xFF6EE7B7.toInt()
        for (ic in engine.interceptors) {
            canvas.drawLine(ic.sx, ic.sy, ic.x, ic.y, strokePaint)
            canvas.drawCircle(ic.x, ic.y, 3f * d, fillPaint)
            val cs = 5f * d
            canvas.drawLine(ic.tx - cs, ic.ty - cs, ic.tx + cs, ic.ty + cs, strokePaint)
            canvas.drawLine(ic.tx + cs, ic.ty - cs, ic.tx - cs, ic.ty + cs, strokePaint)
        }

        // Shockwave blast rings
        for (b in engine.blasts) {
            val frac = (1f - (b.ageSec / b.lifeSec)).coerceIn(0f, 1f)
            fillPaint.color = withAlpha(0x38BDF8, (frac * 95f).toInt())
            canvas.drawCircle(b.x, b.y, b.r, fillPaint)
            strokePaint.color = withAlpha(0x7DD3FC, (frac * 240f).toInt())
            strokePaint.strokeWidth = 2.4f * d
            canvas.drawCircle(b.x, b.y, b.r, strokePaint)
        }

        // Particles
        for (pt in engine.particles) {
            fillPaint.color = pt.color
            canvas.drawCircle(pt.x, pt.y, 2f * d, fillPaint)
        }

        // Popups
        textPaint.textSize = 12f * d
        textPaint.textAlign = Paint.Align.CENTER
        for (pp in engine.popups) {
            textPaint.color = pp.color
            canvas.drawText(pp.text, pp.x, pp.y, textPaint)
        }
    }
}
