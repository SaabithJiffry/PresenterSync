package com.saabithjiffry.presentersync.remote.ui.arcade

import android.content.Context
import android.content.res.Configuration
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.view.HapticFeedbackConstants
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import com.saabithjiffry.presentersync.remote.config.HudColorPalette
import com.saabithjiffry.presentersync.remote.config.HudColorPalettes
import com.saabithjiffry.presentersync.remote.config.RemoteConfig
import com.saabithjiffry.presentersync.remote.config.ResolvedFormFactor
import com.saabithjiffry.presentersync.remote.config.ThemeMode
import com.saabithjiffry.presentersync.remote.input.ClickerMuteController
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Shared floating overlay Canvas base for Sector Z Android games.
 * Renders the unified Win11 Explorer matte-glass scoreboard pill (with live MIC: LIVE / MIC: MUTED tally)
 * and Pause / Game Over card while leaving the presenter's hardware mute key strictly live.
 */
abstract class ArcadeCanvasBaseView(
    context: Context,
    private val onExitRequested: () -> Unit,
    protected val onStateInteracted: () -> Unit = {},
    private val onMuteKeyEvent: (KeyEvent) -> Boolean = { false }
) : View(context) {

    var config: RemoteConfig = RemoteConfig()
        protected set
    var formFactor: ResolvedFormFactor? = null
        protected set
    var isMicMuted: Boolean = false
        protected set
    var pillRectPx: ArcadeRectF? = null
        protected set
    var nowNs: Long = System.nanoTime()
        protected set
    var density: Float = context.resources.displayMetrics.density.coerceAtLeast(0.75f)
        protected set

    protected val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    protected val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
    protected val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.NORMAL)
    }
    protected val boldPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
    }
    protected val workRect = RectF()

    protected enum class HudButtonId {
        SB_EXTRA,
        SB_PAUSE,
        SB_EXIT,
        CARD_PRIMARY,
        CARD_EXIT
    }

    private val buttonRects = mutableMapOf<HudButtonId, RectF>()
    private var pressedBtn: HudButtonId? = null

    init {
        isFocusable = true
        isFocusableInTouchMode = true
        contentDescription = "PresenterSync Arcade Overlay"
    }

    open fun updateSharedState(
        cfg: RemoteConfig,
        resolvedFormFactor: ResolvedFormFactor,
        muted: Boolean,
        bumperRect: ArcadeRectF?,
        frameTimeNs: Long
    ) {
        config = cfg
        formFactor = resolvedFormFactor
        isMicMuted = muted
        pillRectPx = bumperRect
        nowNs = frameTimeNs
        density = context.resources.displayMetrics.density.coerceIn(0.75f, 5f)
        invalidate()
    }

    open fun releaseResources() {
        buttonRects.clear()
    }

    override fun onDetachedFromWindow() {
        releaseResources()
        super.onDetachedFromWindow()
    }

    protected fun isConfiguredMuteKey(event: KeyEvent): Boolean {
        val rawTarget = config.hwMuteHotkey.trim()
        if (rawTarget.isEmpty()) return false
        val targetNorm = ClickerMuteController.normalizeKeyCodeName(rawTarget)
        val incomingNorm = ClickerMuteController.normalizeKeyCodeName(KeyEvent.keyCodeToString(event.keyCode))
        return targetNorm.isNotEmpty() && targetNorm == incomingNorm
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (isConfiguredMuteKey(event)) {
            if (onMuteKeyEvent(event)) {
                return true
            }
            return false
        }
        return super.dispatchKeyEvent(event)
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (event != null && isConfiguredMuteKey(event)) {
            return onMuteKeyEvent(event)
        }
        if (keyCode == KeyEvent.KEYCODE_BACK || keyCode == KeyEvent.KEYCODE_ESCAPE || keyCode == KeyEvent.KEYCODE_BUTTON_B) {
            onExitRequested()
            return true
        }
        if (event != null && onGameKey(keyCode, isDown = true, event = event)) {
            onStateInteracted()
            invalidate()
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent?): Boolean {
        if (event != null && isConfiguredMuteKey(event)) {
            return onMuteKeyEvent(event)
        }
        if (event != null && onGameKey(keyCode, isDown = false, event = event)) {
            invalidate()
            return true
        }
        return super.onKeyUp(keyCode, event)
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        val hitSlop = 10f * density
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                val matched = buttonRects.entries.firstOrNull { (_, r) ->
                    r.containsExpanded(event.x, event.y, hitSlop)
                }?.key
                pressedBtn = matched
                if (matched != null) {
                    invalidate()
                    return true
                }
            }
            MotionEvent.ACTION_UP -> {
                val activeBtn = pressedBtn
                pressedBtn = null
                if (activeBtn != null) {
                    val targetRect = buttonRects[activeBtn]
                    if (targetRect != null && targetRect.containsExpanded(event.x, event.y, hitSlop)) {
                        performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                        triggerHudButton(activeBtn)
                    } else {
                        invalidate()
                    }
                    return true
                }
            }
            MotionEvent.ACTION_CANCEL -> {
                if (pressedBtn != null) {
                    pressedBtn = null
                    invalidate()
                    return true
                }
            }
            MotionEvent.ACTION_MOVE -> {
                if (pressedBtn != null) return true
            }
        }
        return onGameTouch(event) || super.onTouchEvent(event)
    }

    private fun triggerHudButton(btn: HudButtonId) {
        when (btn) {
            HudButtonId.SB_EXTRA -> onExtraTopAction()
            HudButtonId.SB_PAUSE -> onTogglePause()
            HudButtonId.CARD_PRIMARY -> if (isGameOver()) onRestartGame() else onTogglePause()
            HudButtonId.SB_EXIT, HudButtonId.CARD_EXIT -> {
                onExitRequested()
                return
            }
        }
        onStateInteracted()
        invalidate()
    }

    private fun RectF.containsExpanded(x: Float, y: Float, pad: Float): Boolean {
        return x >= (left - pad) && x <= (right + pad) && y >= (top - pad) && y <= (bottom + pad)
    }

    protected fun isDarkMode(): Boolean {
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
        if (width <= 0 || height <= 0) return

        val palette = HudColorPalettes.get(config.hudColorPreset, config.customLiveHex, config.customMutedHex)
        val isDark = isDarkMode()
        val opacity = config.opacityLevel.coerceIn(72, 255)
        buttonRects.clear()

        onGameFrameRender(canvas, palette, isDark, opacity)
        drawScoreboardBar(canvas, palette, isDark, opacity)
        if (isGamePaused() || isGameOver()) {
            drawOverlayCard(canvas, palette, isDark, opacity)
        }
    }

    private fun drawScoreboardBar(
        canvas: Canvas,
        palette: HudColorPalette,
        isDark: Boolean,
        opacity: Int
    ) {
        val d = density
        val glassAlpha = max(216, min(244, opacity + 18))
        val bgArgb = withAlpha(if (isDark) 0x202020 else 0xF3F3F3, glassAlpha)
        val brdArgb = withAlpha(if (isDark) 0x3D3D3D else 0xD2D2D2, min(255, glassAlpha + 10))
        val txtArgb = withAlpha(if (isDark) 0xF3F4F6 else 0x1F2328, 255)

        val pillRgb = if (isMicMuted) palette.mutedBg else palette.liveBg
        val pillIcon = if (isMicMuted) palette.mutedIcon else palette.liveIcon
        val pillTxtRgb = pickBadgeContentRgb(pillRgb, pillIcon, config.monoIcon, isDark, opacity)

        val extraLabel = buildExtraChipLabel()
        val pauseLabel = if (isGamePaused()) "Resume" else "Pause"
        val badgeTxt = "${buildScoreboardBadge()} · ${if (isMicMuted) "MIC MUTED" else "MIC LIVE"}"
        val statsTxt = buildScoreboardStats()

        val sbW = min(width - 20f * d, max(320f * d, width * 0.88f))
        val compact = sbW < 520f * d
        val sbX = (width - sbW) / 2f
        val sbY = 8f * d

        if (compact) {
            val pad = 10f * d
            val row1H = 34f * d
            val row2H = 36f * d
            val sbH = row1H + row2H + 4f * d
            val rad = if (config.sleekCorners) 16f * d else 10f * d

            workRect.set(sbX, sbY, sbX + sbW, sbY + sbH)
            fillPaint.color = bgArgb
            canvas.drawRoundRect(workRect, rad, rad, fillPaint)
            strokePaint.color = brdArgb
            strokePaint.strokeWidth = 1.2f * d
            canvas.drawRoundRect(workRect, rad, rad, strokePaint)

            boldPaint.textSize = 10.5f * d
            val bW = min(sbW * 0.45f, boldPaint.measureText(badgeTxt) + 18f * d)
            val bH = 24f * d
            workRect.set(sbX + pad, sbY + 5f * d, sbX + pad + bW, sbY + 5f * d + bH)
            fillPaint.color = withAlpha(pillRgb, opacity)
            canvas.drawRoundRect(workRect, if (config.sleekCorners) bH / 2f else 6f * d, if (config.sleekCorners) bH / 2f else 6f * d, fillPaint)

            boldPaint.color = withAlpha(pillTxtRgb, 255)
            boldPaint.textAlign = Paint.Align.CENTER
            val bFm = boldPaint.fontMetrics
            canvas.drawText(badgeTxt, workRect.centerX(), workRect.centerY() - (bFm.ascent + bFm.descent) / 2f, boldPaint)

            boldPaint.textSize = 11f * d
            boldPaint.color = txtArgb
            boldPaint.textAlign = Paint.Align.RIGHT
            val sFm = boldPaint.fontMetrics
            canvas.drawText(statsTxt, sbX + sbW - pad, sbY + row1H / 2f - (sFm.ascent + sFm.descent) / 2f, boldPaint)

            val chipCount = if (extraLabel != null) 3 else 2
            val gap = 6f * d
            val chipW = (sbW - pad * 2f - gap * (chipCount - 1)) / chipCount
            val chipY = sbY + row1H + 4f * d
            val chipH = row2H - 8f * d
            var cx = sbX + pad
            if (extraLabel != null) {
                drawChipButton(canvas, HudButtonId.SB_EXTRA, cx, chipY, chipW, chipH, extraLabel, isDark, false, 0, d)
                cx += chipW + gap
            }
            drawChipButton(canvas, HudButtonId.SB_PAUSE, cx, chipY, chipW, chipH, pauseLabel, isDark, false, 0, d)
            drawChipButton(canvas, HudButtonId.SB_EXIT, cx + chipW + gap, chipY, chipW, chipH, "Exit", isDark, false, 0, d)
        } else {
            val sbH = 44f * d
            val rad = if (config.sleekCorners) sbH / 2f else 8f * d
            workRect.set(sbX, sbY, sbX + sbW, sbY + sbH)
            fillPaint.color = bgArgb
            canvas.drawRoundRect(workRect, rad, rad, fillPaint)
            strokePaint.color = brdArgb
            strokePaint.strokeWidth = 1.2f * d
            canvas.drawRoundRect(workRect, rad, rad, strokePaint)

            boldPaint.textSize = 11f * d
            val bW = boldPaint.measureText(badgeTxt) + 20f * d
            val bH = sbH - 10f * d
            workRect.set(sbX + 5f * d, sbY + 5f * d, sbX + 5f * d + bW, sbY + 5f * d + bH)
            fillPaint.color = withAlpha(pillRgb, opacity)
            canvas.drawRoundRect(workRect, if (config.sleekCorners) bH / 2f else 6f * d, if (config.sleekCorners) bH / 2f else 6f * d, fillPaint)
            boldPaint.color = withAlpha(pillTxtRgb, 255)
            boldPaint.textAlign = Paint.Align.CENTER
            val bFm = boldPaint.fontMetrics
            canvas.drawText(badgeTxt, workRect.centerX(), workRect.centerY() - (bFm.ascent + bFm.descent) / 2f, boldPaint)

            val btnH = 30f * d
            val btnY = sbY + (sbH - btnH) / 2f
            val extraW = if (extraLabel != null) 82f * d else 0f
            val pauseW = 72f * d
            val exitW = 58f * d
            val rightW = (if (extraLabel != null) extraW + 6f * d else 0f) + pauseW + exitW + 14f * d
            val rightStart = sbX + sbW - rightW

            boldPaint.textSize = 12f * d
            boldPaint.color = txtArgb
            boldPaint.textAlign = Paint.Align.CENTER
            val sFm = boldPaint.fontMetrics
            canvas.drawText(statsTxt, (sbX + 5f * d + bW + rightStart) / 2f, sbY + sbH / 2f - (sFm.ascent + sFm.descent) / 2f, boldPaint)

            var bx = rightStart + 2f * d
            if (extraLabel != null) {
                drawChipButton(canvas, HudButtonId.SB_EXTRA, bx, btnY, extraW, btnH, extraLabel, isDark, false, 0, d)
                bx += extraW + 6f * d
            }
            drawChipButton(canvas, HudButtonId.SB_PAUSE, bx, btnY, pauseW, btnH, pauseLabel, isDark, false, 0, d)
            drawChipButton(canvas, HudButtonId.SB_EXIT, bx + pauseW + 6f * d, btnY, exitW, btnH, "Exit", isDark, false, 0, d)
        }
    }

    private fun drawOverlayCard(
        canvas: Canvas,
        palette: HudColorPalette,
        isDark: Boolean,
        opacity: Int
    ) {
        val d = density
        val isOver = isGameOver()
        val accentRgb = if (isOver) palette.mutedBg else palette.liveBg
        val banW = min(width - 28f * d, 380f * d)
        val banH = 126f * d
        val banX = (width - banW) / 2f
        val banY = (height - banH) / 2f
        val rad = if (config.sleekCorners) 16f * d else 10f * d

        workRect.set(banX, banY, banX + banW, banY + banH)
        fillPaint.color = withAlpha(if (isDark) 0x202020 else 0xFFFFFF, max(232, min(252, opacity + 22)))
        canvas.drawRoundRect(workRect, rad, rad, fillPaint)
        strokePaint.color = withAlpha(if (isOver) palette.mutedBg else (if (isDark) 0x3D3D3D else 0xCBD5E1), 240)
        strokePaint.strokeWidth = 1.6f * d
        canvas.drawRoundRect(workRect, rad, rad, strokePaint)

        boldPaint.textSize = 18f * d
        boldPaint.color = withAlpha(if (isOver) palette.mutedBg else (if (isDark) 0xFFFFFF else 0x111827), 255)
        boldPaint.textAlign = Paint.Align.CENTER
        val titleText = if (isOver) "GAME OVER" else buildPauseTitle()
        canvas.drawText(titleText, banX + banW / 2f, banY + 34f * d, boldPaint)

        textPaint.textSize = 12.5f * d
        textPaint.color = withAlpha(if (isDark) 0xCBD5E1 else 0x4B5563, 255)
        textPaint.textAlign = Paint.Align.CENTER
        val subText = if (isOver) buildGameOverSubtitle() else buildPauseSubtitle()
        canvas.drawText(subText, banX + banW / 2f, banY + 58f * d, textPaint)

        val btnH = 34f * d
        val btnY = banY + banH - btnH - 14f * d
        val gap = 10f * d
        val pad = 20f * d
        val btnW = (banW - pad * 2f - gap) / 2f
        drawChipButton(
            canvas,
            HudButtonId.CARD_PRIMARY,
            banX + pad,
            btnY,
            btnW,
            btnH,
            if (isOver) "Play Again" else "Resume",
            isDark,
            accented = true,
            accentColor = accentRgb,
            d = d
        )
        drawChipButton(
            canvas,
            HudButtonId.CARD_EXIT,
            banX + pad + btnW + gap,
            btnY,
            btnW,
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
        id: HudButtonId,
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

        fillPaint.color = when {
            accented -> withAlpha(accentColor, if (pressed) 245 else 210)
            pressed -> if (isDark) 0xFF474747.toInt() else 0xFFE5E7EB.toInt()
            else -> if (isDark) 0xFF333333.toInt() else 0xFFFBFBFB.toInt()
        }
        canvas.drawRoundRect(rect, rad, rad, fillPaint)

        strokePaint.color = when {
            accented -> withAlpha(lightenRgb(accentColor, 0.22f), 255)
            else -> if (isDark) 0xFF4A4A4A.toInt() else 0xFFDCDCDC.toInt()
        }
        strokePaint.strokeWidth = 1f * d
        canvas.drawRoundRect(rect, rad, rad, strokePaint)

        boldPaint.textSize = 11.5f * d
        while (boldPaint.measureText(label) > w - 10f * d && boldPaint.textSize > 8.5f * d) {
            boldPaint.textSize -= 0.5f * d
        }
        boldPaint.color = if (accented) {
            withAlpha(pickBadgeContentRgb(accentColor, accentColor, useMono = false, isDark = isDark, alpha = 230), 255)
        } else if (isDark) {
            0xFFF3F4F6.toInt()
        } else {
            0xFF1F2328.toInt()
        }
        boldPaint.textAlign = Paint.Align.CENTER
        val fm = boldPaint.fontMetrics
        canvas.drawText(label, rect.centerX(), rect.centerY() - (fm.ascent + fm.descent) / 2f, boldPaint)
    }

    protected fun drawGlowCircle(
        canvas: Canvas,
        cx: Float,
        cy: Float,
        radius: Float,
        fillArgb: Int = 0,
        strokeArgb: Int = 0,
        strokeWidthPx: Float = 2f * density,
        glowArgb: Int = 0,
        glowWidthPx: Float = 6f * density
    ) {
        if (glowArgb != 0) {
            strokePaint.color = glowArgb
            strokePaint.strokeWidth = glowWidthPx
            canvas.drawCircle(cx, cy, radius, strokePaint)
        }
        if (fillArgb != 0) {
            fillPaint.color = fillArgb
            canvas.drawCircle(cx, cy, radius, fillPaint)
        }
        if (strokeArgb != 0 && strokeWidthPx > 0f) {
            strokePaint.color = strokeArgb
            strokePaint.strokeWidth = strokeWidthPx
            canvas.drawCircle(cx, cy, radius, strokePaint)
        }
    }

    protected fun drawGlowLine(
        canvas: Canvas,
        x1: Float,
        y1: Float,
        x2: Float,
        y2: Float,
        coreArgb: Int,
        coreWidthPx: Float,
        glowArgb: Int = 0,
        glowWidthPx: Float = coreWidthPx * 2.4f
    ) {
        strokePaint.strokeCap = Paint.Cap.ROUND
        if (glowArgb != 0) {
            strokePaint.color = glowArgb
            strokePaint.strokeWidth = glowWidthPx
            canvas.drawLine(x1, y1, x2, y2, strokePaint)
        }
        strokePaint.color = coreArgb
        strokePaint.strokeWidth = coreWidthPx
        canvas.drawLine(x1, y1, x2, y2, strokePaint)
    }

    protected fun drawCenteredText(
        canvas: Canvas,
        text: String,
        cx: Float,
        cy: Float,
        textSizePx: Float,
        colorArgb: Int,
        bold: Boolean = true
    ) {
        val p = if (bold) boldPaint else textPaint
        p.color = colorArgb
        p.textSize = textSizePx
        p.textAlign = Paint.Align.CENTER
        val fm = p.fontMetrics
        canvas.drawText(text, cx, cy - (fm.ascent + fm.descent) / 2f, p)
    }

    protected abstract fun onGameFrameRender(canvas: Canvas, palette: HudColorPalette, isDark: Boolean, opacity: Int)
    protected abstract fun onGameKey(keyCode: Int, isDown: Boolean, event: KeyEvent): Boolean
    protected abstract fun onGameTouch(event: MotionEvent): Boolean
    protected open fun onExtraTopAction() {}
    protected abstract fun onTogglePause()
    protected abstract fun onRestartGame()
    protected abstract fun isGamePaused(): Boolean
    protected abstract fun isGameOver(): Boolean
    protected abstract fun buildScoreboardBadge(): String
    protected abstract fun buildScoreboardStats(): String
    protected open fun buildExtraChipLabel(): String? = null
    protected open fun buildPauseTitle(): String = "PAUSED"
    protected open fun buildPauseSubtitle(): String = "Tap Resume or press P to continue"
    protected open fun buildGameOverSubtitle(): String = "Try again"

    companion object {
        fun withAlpha(rgbOrArgb: Int, alpha: Int): Int {
            return (alpha.coerceIn(0, 255) shl 24) or (rgbOrArgb and 0xFFFFFF)
        }

        fun lightenRgb(rgb: Int, amount: Float): Int {
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

        fun pickBadgeContentRgb(
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
