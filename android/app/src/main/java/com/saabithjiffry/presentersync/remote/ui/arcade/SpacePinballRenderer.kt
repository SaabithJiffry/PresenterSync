package com.saabithjiffry.presentersync.remote.ui.arcade

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.view.HapticFeedbackConstants
import android.view.KeyEvent
import android.view.MotionEvent
import com.saabithjiffry.presentersync.remote.config.HudColorPalette
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin

// ============================================================================
// SECTOR Z-10: NEON SPACE CADET PINBALL OVERLAY VIEW
// ============================================================================

class SpacePinballOverlayView(
    context: Context,
    private val engine: SpacePinballEngine,
    onExitRequested: () -> Unit,
    onStateInteracted: () -> Unit = {},
    onMuteKeyEvent: (KeyEvent) -> Boolean = { false }
) : ArcadeCanvasBaseView(context, onExitRequested, onStateInteracted, onMuteKeyEvent) {

    private val cabRect = RectF()
    private val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
    }
    private val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textAlign = Paint.Align.CENTER
        isFakeBoldText = true
    }

    private var kbLeftDown = false
    private var kbRightDown = false
    private var touchLeftDown = false
    private var touchRightDown = false
    private var plungerPointerId = -1

    override fun buildScoreboardBadge(): String = "SPACE CADET PINBALL"

    override fun buildScoreboardStats(): String =
        "Score ${engine.score} · Ball ${engine.ballNum}/3 · ${engine.rankName()} (${engine.multiplier}x) · Best ${engine.highScore}"

    override fun buildExtraChipLabel(): String = "Nudge"

    override fun buildPauseTitle(): String = "PINBALL PAUSED"

    override fun buildPauseSubtitle(): String =
        "Tap L/R screen for Flippers · Pull Shooter Lane to Launch · Nudge carefully"

    override fun buildGameOverSubtitle(): String =
        "Final Score ${engine.score} · Best ${engine.highScore} · Rank: ${engine.rankName()}"

    override fun isGamePaused(): Boolean = engine.phase == SpacePinballPhase.PAUSED

    override fun isGameOver(): Boolean = engine.phase == SpacePinballPhase.GAME_OVER

    override fun onExtraTopAction() {
        if (engine.nudge()) {
            performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
        }
    }

    override fun onTogglePause() {
        engine.togglePause()
    }

    override fun onRestartGame() {
        engine.resetMatch()
    }

    private fun syncFlippers() {
        engine.setFlippers(kbLeftDown || touchLeftDown, kbRightDown || touchRightDown)
    }

    override fun onGameKey(keyCode: Int, isDown: Boolean, event: KeyEvent): Boolean {
        when (keyCode) {
            KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_Z, KeyEvent.KEYCODE_SHIFT_LEFT -> {
                kbLeftDown = isDown
                syncFlippers()
                return true
            }
            KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.KEYCODE_SLASH, KeyEvent.KEYCODE_SHIFT_RIGHT -> {
                kbRightDown = isDown
                syncFlippers()
                return true
            }
            KeyEvent.KEYCODE_SPACE, KeyEvent.KEYCODE_DPAD_DOWN -> {
                engine.setPlungerHeld(isDown)
                return true
            }
            KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_X -> {
                if (isDown) engine.nudge()
                return true
            }
            KeyEvent.KEYCODE_P -> {
                if (isDown) engine.togglePause()
                return true
            }
            KeyEvent.KEYCODE_R -> {
                if (isDown) engine.resetMatch()
                return true
            }
        }
        return false
    }

    private fun computeTableTransform(): Triple<Float, Float, Float> {
        val d = density
        val sc = min((width - 24f * d) / SpacePinballEngine.TW, (height - 128f * d) / SpacePinballEngine.TH).coerceAtLeast(0.4f)
        val ox = (width - SpacePinballEngine.TW * sc) * 0.5f
        val oy = 86f * d + (height - 112f * d - SpacePinballEngine.TH * sc) * 0.5f
        return Triple(ox, oy, sc)
    }

    override fun onGameTouch(event: MotionEvent): Boolean {
        if (engine.phase != SpacePinballPhase.PLAYING) return false
        val (ox, oy, sc) = computeTableTransform()
        val action = event.actionMasked

        when (action) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                val idx = event.actionIndex
                val pid = event.getPointerId(idx)
                val x = event.getX(idx)
                val y = event.getY(idx)
                val tx = (x - ox) / sc
                val ty = (y - oy) / sc
                if (engine.ballInShooter && tx >= 340f && ty >= 460f) {
                    plungerPointerId = pid
                    engine.setPlungerHeld(true)
                    return true
                }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP, MotionEvent.ACTION_CANCEL -> {
                val idx = event.actionIndex
                val pid = event.getPointerId(idx)
                if (pid == plungerPointerId) {
                    plungerPointerId = -1
                    engine.setPlungerHeld(false)
                }
            }
        }

        var lDown = false
        var rDown = false
        for (i in 0 until event.pointerCount) {
            if (action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_POINTER_UP) {
                if (i == event.actionIndex) continue
            }
            val pid = event.getPointerId(i)
            if (pid == plungerPointerId) continue
            if (event.getX(i) < width * 0.5f) lDown = true else rDown = true
        }
        touchLeftDown = lDown
        touchRightDown = rDown
        syncFlippers()
        return true
    }

    override fun onGameFrameRender(
        canvas: Canvas,
        palette: HudColorPalette,
        isDark: Boolean,
        opacity: Int
    ) {
        val d = density
        val (baseOx, baseOy, sc) = computeTableTransform()
        var ox = baseOx
        var oy = baseOy
        if (engine.nudgeShake > 0f) {
            ox += sin(engine.nudgeShake * 90f) * 5f * d
            oy += cos(engine.nudgeShake * 70f) * 3f * d
        }

        val cabW = SpacePinballEngine.TW * sc
        val cabH = SpacePinballEngine.TH * sc
        cabRect.set(ox - 6f * d, oy - 6f * d, ox + cabW + 6f * d, oy + cabH + 6f * d)
        fillPaint.color = 0xE6090D18.toInt()
        canvas.drawRoundRect(cabRect, 16f * d, 16f * d, fillPaint)
        linePaint.color = if (engine.tilted) 0xFFEF4444.toInt() else 0xFF38BDF8.toInt()
        linePaint.strokeWidth = 2f * d
        canvas.drawRoundRect(cabRect, 16f * d, 16f * d, linePaint)

        // Walls
        linePaint.color = 0xFF38BDF8.toInt()
        linePaint.strokeWidth = 2f * d
        for (w in engine.walls) {
            canvas.drawLine(ox + w.x1 * sc, oy + w.y1 * sc, ox + w.x2 * sc, oy + w.y2 * sc, linePaint)
        }

        // One-way gate
        linePaint.color = if (engine.ballInShooter) 0x66FACC15 else 0xFFEF4444.toInt()
        canvas.drawLine(ox + 360f * sc, oy + 80f * sc, ox + 360f * sc, oy + 155f * sc, linePaint)

        // Plunger
        val pTop = 665f + engine.plungerCharge * 16f
        linePaint.color = 0xFFF59E0B.toInt()
        linePaint.strokeWidth = 6f * sc
        canvas.drawLine(ox + 378f * sc, oy + pTop * sc, ox + 378f * sc, oy + 684f * sc, linePaint)

        // Rollovers
        labelPaint.textSize = 9f * sc
        for (r in engine.rollovers) {
            fillPaint.color = if (r.lit) 0x55FACC15 else 0x220F172A
            canvas.drawCircle(ox + r.x * sc, oy + r.y * sc, r.r * sc, fillPaint)
            linePaint.color = if (r.lit) 0xFFFACC15.toInt() else 0x5594A3B8
            linePaint.strokeWidth = 1.5f * d
            canvas.drawCircle(ox + r.x * sc, oy + r.y * sc, r.r * sc, linePaint)
            labelPaint.color = if (r.lit) 0xFFFEF08A.toInt() else 0xFF94A3B8.toInt()
            canvas.drawText(r.label, ox + r.x * sc, oy + (r.y + 3.5f) * sc, labelPaint)
        }

        // Drop targets
        for (dTgt in engine.dropTargets) {
            fillPaint.color = when {
                dTgt.down -> 0x33475569
                dTgt.flash > 0f -> 0xFFFFFFFF.toInt()
                else -> 0xFF22C55E.toInt()
            }
            canvas.drawRect(ox + dTgt.x * sc, oy + dTgt.y * sc, ox + (dTgt.x + dTgt.w) * sc, oy + (dTgt.y + dTgt.h) * sc, fillPaint)
        }

        // Slingshots
        for (s in engine.slings) {
            linePaint.color = if (s.flash > 0f) 0xFFFDE047.toInt() else 0xFFA855F7.toInt()
            linePaint.strokeWidth = 2.8f * d
            canvas.drawLine(ox + s.ax * sc, oy + s.ay * sc, ox + s.bx * sc, oy + s.by * sc, linePaint)
            linePaint.color = 0xFF64748B.toInt()
            linePaint.strokeWidth = 1.8f * d
            canvas.drawLine(ox + s.bx * sc, oy + s.by * sc, ox + s.cx * sc, oy + s.cy * sc, linePaint)
            canvas.drawLine(ox + s.cx * sc, oy + s.cy * sc, ox + s.ax * sc, oy + s.ay * sc, linePaint)
        }

        // Bumpers
        for (b in engine.bumpers) {
            val baseCol = when (b.level) {
                1 -> 0xFF06B6D4.toInt()
                2 -> 0xFFF59E0B.toInt()
                else -> 0xFFEC4899.toInt()
            }
            fillPaint.color = if (b.flash > 0f) 0xCCFFFFFF.toInt() else ((baseCol and 0x00FFFFFF) or 0x55000000)
            canvas.drawCircle(ox + b.x * sc, oy + b.y * sc, b.r * sc, fillPaint)
            linePaint.color = baseCol
            linePaint.strokeWidth = 2.2f * d
            canvas.drawCircle(ox + b.x * sc, oy + b.y * sc, b.r * sc, linePaint)
        }

        // Center Rank / Ball Save
        labelPaint.textSize = 11f * sc
        labelPaint.color = 0xFFC084FC.toInt()
        canvas.drawText("${engine.rankName().uppercase()} (${engine.multiplier}x)", ox + 192f * sc, oy + 380f * sc, labelPaint)
        if (engine.ballSaveTimer > 0f) {
            labelPaint.color = 0xFF22C55E.toInt()
            canvas.drawText("BALL SAVE", ox + 192f * sc, oy + 610f * sc, labelPaint)
        }

        // Flippers
        val ltx = 120f + cos(engine.leftFlipperAngle) * 58f
        val lty = 628f + sin(engine.leftFlipperAngle) * 58f
        val rtx = 264f + cos(engine.rightFlipperAngle) * 58f
        val rty = 628f + sin(engine.rightFlipperAngle) * 58f
        linePaint.color = if (engine.tilted) 0xFF64748B.toInt() else 0xFF38BDF8.toInt()
        linePaint.strokeWidth = 11f * sc
        canvas.drawLine(ox + 120f * sc, oy + 628f * sc, ox + ltx * sc, oy + lty * sc, linePaint)
        canvas.drawLine(ox + 264f * sc, oy + 628f * sc, ox + rtx * sc, oy + rty * sc, linePaint)

        // Ball trail & ball
        for ((idx, pt) in engine.ballTrail.withIndex()) {
            fillPaint.color = (((idx + 1) * 18) shl 24) or 0x38BDF8
            canvas.drawCircle(ox + pt.x * sc, oy + pt.y * sc, SpacePinballEngine.BALL_R * 0.65f * sc, fillPaint)
        }
        fillPaint.color = 0xFFF8FAFC.toInt()
        canvas.drawCircle(ox + engine.ballX * sc, oy + engine.ballY * sc, SpacePinballEngine.BALL_R * sc, fillPaint)
        linePaint.color = 0xFF38BDF8.toInt()
        linePaint.strokeWidth = 1.8f * d
        canvas.drawCircle(ox + engine.ballX * sc, oy + engine.ballY * sc, SpacePinballEngine.BALL_R * sc, linePaint)

        // Popups
        var py = oy + 420f * sc
        labelPaint.textSize = 12f * sc
        for (p in engine.popups) {
            labelPaint.color = p.argb
            canvas.drawText(p.text, ox + 192f * sc, py, labelPaint)
            py += 20f * sc
        }
    }
}
