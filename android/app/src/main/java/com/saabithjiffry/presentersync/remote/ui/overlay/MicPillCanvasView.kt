package com.saabithjiffry.presentersync.remote.ui.overlay

import android.animation.ArgbEvaluator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PathMeasure
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.view.View
import com.saabithjiffry.presentersync.remote.config.AppConstants
import com.saabithjiffry.presentersync.remote.config.HudColorPalette
import com.saabithjiffry.presentersync.remote.config.HudColorPalettes
import com.saabithjiffry.presentersync.remote.config.RemoteConfig
import com.saabithjiffry.presentersync.remote.input.BubbleHoldStage
import com.saabithjiffry.presentersync.remote.network.ConnStatus
import com.saabithjiffry.presentersync.remote.network.ConnectionUiState
import kotlin.math.roundToInt

class MicPillCanvasView(context: Context) : View(context) {
    private val haloPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val specularRimPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
    private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
    private val contentPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val strokeIconPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    private val knockoutSlashPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    private val textPaint = Paint(
        Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG or Paint.LINEAR_TEXT_FLAG
    ).apply {
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        letterSpacing = MicPillMetricsCalculator.TEXT_LETTER_SPACING
    }
    private val miniBadgeBgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        color = Color.parseColor("#E6111827")
    }
    private val miniBadgeTextPaint = Paint(
        Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG or Paint.LINEAR_TEXT_FLAG
    ).apply {
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        color = Color.parseColor("#F8FAFC")
    }

    // Reusable visual state & geometry objects (zero per-frame allocations)
    private class PillVisualState {
        var bgColor: Int = Color.BLACK
        var borderColor: Int = Color.WHITE
        var iconColor: Int = Color.WHITE
        var showSlash: Boolean = false
        var label: String = "LIVE"
        var isOffline: Boolean = false
        var alphaScale: Float = 1f
        var effectiveAlpha: Int = 255
    }

    private val visualState = PillVisualState()
    private val pillRect = RectF()
    private val specularRect = RectF()
    private val haloRect = RectF()
    private val miniBadgeRect = RectF()
    private val micBodyRect = RectF()
    private val micArcRect = RectF()
    private val micCradlePath = Path()

    // Cached shaders rebuilt only when pill vertical bounds or fill color change
    private var cachedFillShader: LinearGradient? = null
    private var cachedFillColor: Int = 0
    private var cachedFillTop: Float = Float.NaN
    private var cachedFillBottom: Float = Float.NaN

    private var cachedSpecularShader: LinearGradient? = null
    private var cachedSpecularTop: Float = Float.NaN
    private var cachedSpecularBottom: Float = Float.NaN

    private var config: RemoteConfig = RemoteConfig()
    private var connState: ConnectionUiState = ConnectionUiState()
    private var currentAlpha: Int = AppConstants.OPACITY_FROSTED
    private var overrideMuted: Boolean? = null
    private var transitionFromMuted: Boolean? = null
    private var transitionToMuted: Boolean? = null
    private var transitionFraction: Float = 1f
    private val colorEvaluator = ArgbEvaluator()

    private var maxContainerWidthPx: Int = 0

    fun setMuteTransition(fromMuted: Boolean, toMuted: Boolean, fraction: Float) {
        transitionFromMuted = fromMuted
        transitionToMuted = toMuted
        transitionFraction = fraction.coerceIn(0f, 1f)
    }

    fun clearMuteTransition() {
        transitionFromMuted = null
        transitionToMuted = null
        transitionFraction = 1f
    }

    fun updateRenderState(
        cfg: RemoteConfig,
        conn: ConnectionUiState,
        alpha: Int = cfg.opacityLevel,
        mutedOverride: Boolean? = null,
        maxContainerWidthPx: Int = this.maxContainerWidthPx
    ) {
        config = cfg
        connState = conn
        currentAlpha = alpha.coerceIn(0, 255)
        overrideMuted = mutedOverride
        this.maxContainerWidthPx = maxContainerWidthPx
        invalidate()
    }

    fun effectiveScale(safeWidthPx: Int = maxContainerWidthPx): Float {
        val boundWidth = if (safeWidthPx > 0) safeWidthPx else resources.displayMetrics.widthPixels
        return MicPillMetricsCalculator.computeEffectiveScale(
            requestedScale = config.indicatorScale,
            showText = config.showText,
            safeWidthPx = boundWidth,
            density = resources.displayMetrics.density
        )
    }

    fun computeOuterInsetPx(safeWidthPx: Int = maxContainerWidthPx): Int {
        return MicPillMetricsCalculator.computeSafeOuterInsetPx(
            effectiveScale = effectiveScale(safeWidthPx),
            density = resources.displayMetrics.density
        ).roundToInt()
    }

    fun computeTargetWidthPx(safeWidthPx: Int = maxContainerWidthPx): Int {
        val boundWidth = if (safeWidthPx > 0) safeWidthPx else resources.displayMetrics.widthPixels
        val effScale = effectiveScale(boundWidth)
        val baseDp = if (config.showText) AppConstants.BASE_WIDTH_TEXT else AppConstants.BASE_WIDTH_ICON
        val innerW = dpToPx(baseDp * effScale).coerceAtLeast(16)
        val inset = MicPillMetricsCalculator.computeSafeOuterInsetPx(effScale, resources.displayMetrics.density)
        return innerW + (inset * 2f).roundToInt()
    }

    fun computeTargetHeightPx(safeWidthPx: Int = maxContainerWidthPx): Int {
        val boundWidth = if (safeWidthPx > 0) safeWidthPx else resources.displayMetrics.widthPixels
        val effScale = effectiveScale(boundWidth)
        val innerH = dpToPx(AppConstants.BASE_HEIGHT * effScale).coerceAtLeast(12)
        val inset = MicPillMetricsCalculator.computeSafeOuterInsetPx(effScale, resources.displayMetrics.density)
        return innerH + (inset * 2f).roundToInt()
    }

    private fun dpToPx(dp: Float): Int {
        return (dp * resources.displayMetrics.density).roundToInt()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val specW = MeasureSpec.getSize(widthMeasureSpec)
        val specModeW = MeasureSpec.getMode(widthMeasureSpec)
        val effectiveBoundW = if (maxContainerWidthPx > 0) {
            if (specModeW != MeasureSpec.UNSPECIFIED && specW > 0) minOf(maxContainerWidthPx, specW) else maxContainerWidthPx
        } else if (specModeW != MeasureSpec.UNSPECIFIED && specW > 0) {
            specW
        } else {
            resources.displayMetrics.widthPixels
        }
        val w = computeTargetWidthPx(effectiveBoundW)
        val h = computeTargetHeightPx(effectiveBoundW)
        setMeasuredDimension(w, h)
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val w = width.toFloat()
        val h = height.toFloat()
        if (w <= 0f || h <= 0f) return

        resolveVisualState(visualState)
        val metrics = computeRenderMetrics(w, h, visualState.label)
        pillRect.set(metrics.pillLeft, metrics.pillTop, metrics.pillRight, metrics.pillBottom)
        if (pillRect.width() <= 0.5f || pillRect.height() <= 0.5f) return

        drawPillShellAndBorder(canvas, metrics, visualState)
        drawForegroundLabel(canvas, metrics, visualState)
        drawVectorMicrophoneWithSlash(canvas, metrics, visualState)
        drawOverlaysAndMiniBadges(canvas, metrics, visualState, h)
    }

    private fun resolveVisualState(out: PillVisualState) {
        val palette = HudColorPalettes.get(config.hudColorPreset, config.customLiveHex, config.customMutedHex)
        val isOffline = overrideMuted == null && !connState.connected
        val muted = overrideMuted ?: connState.isMuted
        val tFrom = transitionFromMuted
        val tTo = transitionToMuted

        out.isOffline = isOffline
        out.alphaScale = currentAlpha / 255f
        out.effectiveAlpha = (255 * out.alphaScale).roundToInt().coerceIn(0, 255)

        if (isOffline) {
            val isAuthErr = connState.connStatus == ConnStatus.AUTH_FAILED
            out.bgColor = palette.offlineBg
            out.borderColor = adjustBorderColor(if (isAuthErr) palette.authErrBorder else palette.offlineBg, isAuthErr)
            out.iconColor = if (config.monoIcon) palette.offlineIcon else Color.parseColor("#E5E7EB")
            out.showSlash = true
            out.label = if (isAuthErr) "AUTH ERR" else "OFFLINE"
        } else if (tFrom != null && tTo != null) {
            val (fromBg, fromBorder, fromIcon) = resolveColorsForMuted(palette, tFrom)
            val (toBg, toBorder, toIcon) = resolveColorsForMuted(palette, tTo)
            val f = transitionFraction.coerceIn(0f, 1f)
            out.bgColor = colorEvaluator.evaluate(f, fromBg, toBg) as Int
            out.borderColor = colorEvaluator.evaluate(f, fromBorder, toBorder) as Int
            out.iconColor = colorEvaluator.evaluate(f, fromIcon, toIcon) as Int
            val displayMuted = if (f < 0.5f) tFrom else tTo
            out.showSlash = displayMuted
            out.label = if (displayMuted) "MUTED" else "LIVE"
        } else {
            val (bg, border, icon) = resolveColorsForMuted(palette, muted)
            out.bgColor = bg
            out.borderColor = border
            out.iconColor = icon
            out.showSlash = muted
            out.label = if (muted) "MUTED" else "LIVE"
        }
    }

    private fun computeRenderMetrics(w: Float, h: Float, label: String): MicPillRenderMetrics {
        val density = resources.displayMetrics.density.coerceAtLeast(0.5f)
        return MicPillMetricsCalculator.computeForCanvasBounds(
            canvasWidthPx = w,
            canvasHeightPx = h,
            effectiveScale = effectiveScale(),
            showText = config.showText,
            sleekCorners = config.sleekCorners,
            label = label,
            density = density,
            measureTextWidth = { text, textSize ->
                textPaint.textSize = textSize
                textPaint.measureText(text)
            }
        )
    }

    /**
     * Draws the outer elevation halo, vertical tonal gradient background, crisp inner specular rim,
     * and optical/amber-alert border.
     */
    private fun drawPillShellAndBorder(canvas: Canvas, metrics: MicPillRenderMetrics, state: PillVisualState) {
        drawOuterElevationHalo(canvas, metrics, state.alphaScale)
        drawTonalBackgroundFill(canvas, metrics, state.bgColor, state.effectiveAlpha)
        drawInnerSpecularRim(canvas, metrics, state.effectiveAlpha)
        drawOpticalPillBorder(canvas, metrics, state)
    }

    private fun drawTonalBackgroundFill(canvas: Canvas, metrics: MicPillRenderMetrics, bgColor: Int, effectiveAlpha: Int) {
        ensureFillShader(bgColor, pillRect.top, pillRect.bottom)
        bgPaint.color = bgColor
        bgPaint.shader = cachedFillShader
        bgPaint.alpha = effectiveAlpha
        canvas.drawRoundRect(pillRect, metrics.cornerRadiusPx, metrics.cornerRadiusPx, bgPaint)
    }

    private fun drawInnerSpecularRim(canvas: Canvas, metrics: MicPillRenderMetrics, effectiveAlpha: Int) {
        val specInset = metrics.strokeWidthPx / 2f + metrics.specularStrokeWidthPx / 2f
        specularRect.set(
            pillRect.left + specInset,
            pillRect.top + specInset,
            pillRect.right - specInset,
            pillRect.bottom - specInset
        )
        if (specularRect.width() <= 2f || specularRect.height() <= 2f) return
        ensureSpecularShader(specularRect.top, specularRect.bottom)
        specularRimPaint.strokeWidth = metrics.specularStrokeWidthPx
        specularRimPaint.shader = cachedSpecularShader
        specularRimPaint.alpha = effectiveAlpha
        canvas.drawRoundRect(
            specularRect,
            metrics.specularCornerRadiusPx,
            metrics.specularCornerRadiusPx,
            specularRimPaint
        )
    }

    private fun drawOpticalPillBorder(canvas: Canvas, metrics: MicPillRenderMetrics, state: PillVisualState) {
        val amberAlert = !state.isOffline &&
            MicPillMetricsCalculator.shouldShowAmberAlertBorder(connState, config.showPillMiniBadges)
        borderPaint.strokeWidth = if (amberAlert) metrics.strokeWidthPx * 1.25f else metrics.strokeWidthPx
        borderPaint.color = if (amberAlert) MicPillMetricsCalculator.AMBER_ALERT_BORDER_ARGB else state.borderColor
        borderPaint.alpha = state.effectiveAlpha
        canvas.drawRoundRect(pillRect, metrics.cornerRadiusPx, metrics.cornerRadiusPx, borderPaint)
    }

    private fun drawForegroundLabel(canvas: Canvas, metrics: MicPillRenderMetrics, state: PillVisualState) {
        if (!config.showText) return
        textPaint.color = state.iconColor
        textPaint.alpha = state.effectiveAlpha
        textPaint.textSize = metrics.textSizePx
        val fm = textPaint.fontMetrics
        val textBaseline = metrics.iconCenterYPx - (fm.ascent + fm.descent) / 2f
        canvas.drawText(state.label, metrics.textStartXPx, textBaseline, textPaint)
    }

    private fun drawVectorMicrophoneWithSlash(canvas: Canvas, metrics: MicPillRenderMetrics, state: PillVisualState) {
        contentPaint.color = state.iconColor
        contentPaint.alpha = state.effectiveAlpha
        strokeIconPaint.color = state.iconColor
        strokeIconPaint.alpha = state.effectiveAlpha
        knockoutSlashPaint.color = state.bgColor
        knockoutSlashPaint.shader = cachedFillShader
        knockoutSlashPaint.alpha = state.effectiveAlpha

        drawPrecisionMicrophoneGlyph(
            canvas = canvas,
            iconLeft = metrics.iconLeftPx,
            iconTop = metrics.iconCenterYPx - metrics.iconSizePx / 2f,
            size = metrics.iconSizePx,
            mutedSlash = state.showSlash
        )
    }

    private fun drawOverlaysAndMiniBadges(
        canvas: Canvas,
        metrics: MicPillRenderMetrics,
        state: PillVisualState,
        canvasHeightPx: Float
    ) {
        drawHoldProgressRing(canvas, metrics)
        val badgeText = if (!state.isOffline) {
            MicPillMetricsCalculator.formatPillMiniBadgeText(connState, config.showPillMiniBadges)
        } else {
            ""
        }
        if (badgeText.isNotEmpty()) {
            drawPillMiniBadgeStrip(canvas, metrics, badgeText, state.effectiveAlpha, canvasHeightPx)
        }
    }

    private fun drawPillMiniBadgeStrip(
        canvas: Canvas,
        metrics: MicPillRenderMetrics,
        badgeText: String,
        effectiveAlpha: Int,
        canvasHeightPx: Float
    ) {
        val density = metrics.density
        val badgeTextSize = (metrics.innerHeightPx * 0.22f).coerceIn(7f * density, 10.5f * density)
        miniBadgeTextPaint.textSize = badgeTextSize
        miniBadgeTextPaint.color = when {
            connState.timerState == "overtime" -> Color.parseColor("#FCA5A5")
            connState.isStandby -> Color.parseColor("#FCD34D")
            connState.recState == 1 -> Color.parseColor("#FCA5A5")
            else -> Color.parseColor("#F8FAFC")
        }
        miniBadgeTextPaint.alpha = effectiveAlpha
        miniBadgeBgPaint.alpha = (effectiveAlpha * 0.90f).roundToInt().coerceIn(0, 255)

        val textW = miniBadgeTextPaint.measureText(badgeText)
        val padH = 5f * density
        val fm = miniBadgeTextPaint.fontMetrics
        val textH = fm.descent - fm.ascent
        val chipH = textH + 3f * density
        val maxChipW = (metrics.innerWidthPx - 4f * density).coerceAtLeast(12f * density)
        val chipW = (textW + padH * 2f).coerceAtMost(maxChipW)
        val cx = (metrics.pillLeft + metrics.pillRight) / 2f
        val bottomY = (metrics.pillBottom + chipH * 0.35f).coerceAtMost(canvasHeightPx - 1f)
        val topY = (bottomY - chipH).coerceAtLeast(metrics.pillBottom - chipH)
        miniBadgeRect.set(cx - chipW / 2f, topY, cx + chipW / 2f, bottomY)
        val chipRadius = chipH / 2f
        canvas.drawRoundRect(miniBadgeRect, chipRadius, chipRadius, miniBadgeBgPaint)

        val baseline = miniBadgeRect.centerY() - (fm.ascent + fm.descent) / 2f
        val textX = cx - minOf(textW, chipW - padH) / 2f
        canvas.drawText(badgeText, textX, baseline, miniBadgeTextPaint)
    }

    private fun ensureFillShader(bgColor: Int, top: Float, bottom: Float) {
        val safeBottom = if (bottom > top + 0.5f) bottom else top + 1f
        if (cachedFillShader != null &&
            cachedFillColor == bgColor &&
            cachedFillTop == top &&
            cachedFillBottom == safeBottom
        ) {
            return
        }
        val topColor = MicPillMetricsCalculator.computeTonalTopColor(bgColor)
        val bottomColor = MicPillMetricsCalculator.computeTonalBottomColor(bgColor)
        cachedFillShader = LinearGradient(
            0f,
            top,
            0f,
            safeBottom,
            topColor,
            bottomColor,
            Shader.TileMode.CLAMP
        )
        cachedFillColor = bgColor
        cachedFillTop = top
        cachedFillBottom = safeBottom
    }

    private fun ensureSpecularShader(top: Float, bottom: Float) {
        val safeBottom = if (bottom > top + 0.5f) bottom else top + 1f
        if (cachedSpecularShader != null &&
            cachedSpecularTop == top &&
            cachedSpecularBottom == safeBottom
        ) {
            return
        }
        cachedSpecularShader = LinearGradient(
            0f,
            top,
            0f,
            safeBottom,
            intArrayOf(0x3DFFFFFF, 0x10FFFFFF, 0x00FFFFFF),
            floatArrayOf(0f, 0.45f, 1f),
            Shader.TileMode.CLAMP
        )
        cachedSpecularTop = top
        cachedSpecularBottom = safeBottom
    }

    private fun drawOuterElevationHalo(canvas: Canvas, metrics: MicPillRenderMetrics, alphaScale: Float) {
        val baseHaloAlpha = (alphaScale * alphaScale).coerceIn(0f, 1f)
        if (baseHaloAlpha <= 0.05f) return

        // 3 soft concentric halo passes strictly bounded within safeOuterInsetPx
        val spread = metrics.haloSpreadPx.coerceAtMost(metrics.safeOuterInsetPx)
        val yShift = metrics.haloOffsetYPx.coerceAtMost((metrics.safeOuterInsetPx - spread).coerceAtLeast(0f))
        haloPaint.color = Color.BLACK

        drawHaloPass(canvas, metrics.cornerRadiusPx, baseHaloAlpha, 18, spread, spread * 0.45f, yShift, 0.75f)
        drawHaloPass(canvas, metrics.cornerRadiusPx, baseHaloAlpha, 28, spread * 0.62f, spread * 0.62f * 0.25f, yShift * 0.75f, 0.65f)
        drawHaloPass(canvas, metrics.cornerRadiusPx, baseHaloAlpha, 36, spread * 0.30f, 0f, yShift * 0.5f, 0.5f, topYShift = yShift * 0.4f)
    }

    private fun drawHaloPass(
        canvas: Canvas,
        baseCornerRadius: Float,
        baseHaloAlpha: Float,
        alphaWeight: Int,
        passSpread: Float,
        topSpread: Float,
        bottomYShift: Float,
        radiusFactor: Float,
        topYShift: Float = bottomYShift
    ) {
        haloPaint.alpha = (alphaWeight * baseHaloAlpha).roundToInt().coerceIn(0, 255)
        haloRect.set(
            pillRect.left - passSpread,
            pillRect.top - topSpread + topYShift,
            pillRect.right + passSpread,
            pillRect.bottom + passSpread + bottomYShift
        )
        val radius = baseCornerRadius + passSpread * radiusFactor
        canvas.drawRoundRect(haloRect, radius, radius, haloPaint)
    }

    private var holdStage: BubbleHoldStage = BubbleHoldStage.IDLE
    private var holdProgress: Float = 0f
    private val holdOutlinePath = Path()
    private val holdSegmentPath = Path()
    private val holdMeasure = PathMeasure()
    private val holdPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
    }

    fun setGestureFeedback(stage: BubbleHoldStage, progress: Float) {
        val clamped = progress.coerceIn(0f, 1f)
        if (holdStage == stage && kotlin.math.abs(holdProgress - clamped) < 0.01f) return
        holdStage = stage
        holdProgress = clamped
        invalidate()
    }

    private fun drawHoldProgressRing(canvas: Canvas, metrics: MicPillRenderMetrics) {
        if (holdStage == BubbleHoldStage.IDLE || holdProgress <= 0f) return
        holdPaint.strokeWidth = metrics.holdRingStrokeWidthPx
        holdPaint.color = when (holdStage) {
            BubbleHoldStage.PROGRESS_LONG -> Color.parseColor("#F59E0B")
            BubbleHoldStage.REACHED_LONG -> Color.parseColor("#FBBF24")
            BubbleHoldStage.PROGRESS_VERY_LONG -> Color.parseColor("#38BDF8")
            BubbleHoldStage.REACHED_VERY_LONG -> Color.parseColor("#60CDFF")
            BubbleHoldStage.IDLE -> return
        }
        holdOutlinePath.reset()
        holdOutlinePath.addRoundRect(pillRect, metrics.cornerRadiusPx, metrics.cornerRadiusPx, Path.Direction.CW)
        holdMeasure.setPath(holdOutlinePath, false)
        val total = holdMeasure.length
        if (total <= 0f) return
        holdSegmentPath.reset()
        holdMeasure.getSegment(0f, total * holdProgress.coerceIn(0.02f, 1f), holdSegmentPath, true)
        canvas.drawPath(holdSegmentPath, holdPaint)
    }

    private fun resolveColorsForMuted(palette: HudColorPalette, muted: Boolean): Triple<Int, Int, Int> {
        val bg = if (muted) palette.mutedBg else palette.liveBg
        val border = adjustBorderColor(bg, false)
        val icon = if (config.monoIcon) {
            if (muted) palette.mutedIcon else palette.liveIcon
        } else if (palette.name == "Custom") {
            HudColorPalettes.pickReadableIconRgb(bg)
        } else {
            Color.WHITE
        }
        return Triple(bg, border, icon)
    }

    private fun adjustBorderColor(baseColor: Int, isAuthErr: Boolean): Int {
        if (isAuthErr) return baseColor
        val r = (Color.red(baseColor) * 0.8f + 40).toInt().coerceIn(0, 255)
        val g = (Color.green(baseColor) * 0.8f + 40).toInt().coerceIn(0, 255)
        val b = (Color.blue(baseColor) * 0.8f + 40).toInt().coerceIn(0, 255)
        return Color.argb(255, r, g, b)
    }

    /**
     * Precision 24x24 normalized Fluent/Material microphone vector glyph with dual-pass
     * knockout gap behind the diagonal muted slash.
     */
    private fun drawPrecisionMicrophoneGlyph(
        canvas: Canvas,
        iconLeft: Float,
        iconTop: Float,
        size: Float,
        mutedSlash: Boolean
    ) {
        val unit = size / MicVectorSpec24.VIEWPORT_SIZE
        fun vx(x: Float) = iconLeft + x * unit
        fun vy(y: Float) = iconTop + y * unit

        val glyphStroke = (MicVectorSpec24.GLYPH_STROKE * unit).coerceAtLeast(1.4f)
        strokeIconPaint.strokeWidth = glyphStroke

        // 1. Balanced microphone capsule
        micBodyRect.set(
            vx(MicVectorSpec24.CAPSULE_LEFT),
            vy(MicVectorSpec24.CAPSULE_TOP),
            vx(MicVectorSpec24.CAPSULE_RIGHT),
            vy(MicVectorSpec24.CAPSULE_BOTTOM)
        )
        val capsuleR = MicVectorSpec24.CAPSULE_RADIUS * unit
        canvas.drawRoundRect(micBodyRect, capsuleR, capsuleR, contentPaint)

        // 2. Tapered U-cradle with vertical entry arms
        micArcRect.set(
            vx(MicVectorSpec24.CRADLE_LEFT),
            vy(MicVectorSpec24.CRADLE_TOP),
            vx(MicVectorSpec24.CRADLE_RIGHT),
            vy(MicVectorSpec24.CRADLE_BOTTOM)
        )
        micCradlePath.reset()
        micCradlePath.moveTo(vx(MicVectorSpec24.CRADLE_LEFT), vy(MicVectorSpec24.CRADLE_ARM_TOP_Y))
        micCradlePath.lineTo(vx(MicVectorSpec24.CRADLE_LEFT), vy(MicVectorSpec24.CRADLE_ARM_JOIN_Y))
        micCradlePath.arcTo(micArcRect, 180f, -180f, false)
        micCradlePath.lineTo(vx(MicVectorSpec24.CRADLE_RIGHT), vy(MicVectorSpec24.CRADLE_ARM_TOP_Y))
        canvas.drawPath(micCradlePath, strokeIconPaint)

        // 3. Stem & balanced stand base
        canvas.drawLine(
            vx(MicVectorSpec24.CENTER_X),
            vy(MicVectorSpec24.STEM_TOP_Y),
            vx(MicVectorSpec24.CENTER_X),
            vy(MicVectorSpec24.STEM_BOTTOM_Y),
            strokeIconPaint
        )
        canvas.drawLine(
            vx(MicVectorSpec24.BASE_LEFT_X),
            vy(MicVectorSpec24.STEM_BOTTOM_Y),
            vx(MicVectorSpec24.BASE_RIGHT_X),
            vy(MicVectorSpec24.STEM_BOTTOM_Y),
            strokeIconPaint
        )

        // 4. Dual-pass knockout mute slash (mask stroke in pill fill underneath foreground slash)
        if (mutedSlash) {
            drawMutedKnockoutSlash(
                canvas = canvas,
                sx = vx(MicVectorSpec24.SLASH_START_X),
                sy = vy(MicVectorSpec24.SLASH_START_Y),
                ex = vx(MicVectorSpec24.SLASH_END_X),
                ey = vy(MicVectorSpec24.SLASH_END_Y),
                glyphStroke = glyphStroke
            )
        }
    }

    private fun drawMutedKnockoutSlash(
        canvas: Canvas,
        sx: Float,
        sy: Float,
        ex: Float,
        ey: Float,
        glyphStroke: Float
    ) {
        // Pass 1: Pill-fill mask stroke creates a crisp visual knockout gap behind the slash
        knockoutSlashPaint.strokeWidth = glyphStroke * MicVectorSpec24.SLASH_MASK_MULTIPLIER
        canvas.drawLine(sx, sy, ex, ey, knockoutSlashPaint)

        // Pass 2: Crisp foreground diagonal mute slash
        strokeIconPaint.strokeWidth = glyphStroke * MicVectorSpec24.SLASH_FG_MULTIPLIER
        canvas.drawLine(sx, sy, ex, ey, strokeIconPaint)
        strokeIconPaint.strokeWidth = glyphStroke
    }
}
