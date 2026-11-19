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

    // Reusable geometry objects (zero per-frame allocations)
    private val pillRect = RectF()
    private val specularRect = RectF()
    private val haloRect = RectF()
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

        val density = resources.displayMetrics.density.coerceAtLeast(0.5f)
        val palette = HudColorPalettes.get(config.hudColorPreset, config.customLiveHex, config.customMutedHex)
        val isOffline = overrideMuted == null && !connState.connected
        val muted = overrideMuted ?: connState.isMuted
        val tFrom = transitionFromMuted
        val tTo = transitionToMuted

        val bgColor: Int
        val borderColor: Int
        val iconHexColor: Int
        val showSlash: Boolean
        val label: String

        if (isOffline) {
            val isAuthErr = connState.connStatus == ConnStatus.AUTH_FAILED
            bgColor = palette.offlineBg
            borderColor = adjustBorderColor(if (isAuthErr) palette.authErrBorder else palette.offlineBg, isAuthErr)
            iconHexColor = if (config.monoIcon) palette.offlineIcon else Color.parseColor("#E5E7EB")
            showSlash = true
            label = if (isAuthErr) "AUTH ERR" else "OFFLINE"
        } else if (tFrom != null && tTo != null) {
            val (fromBg, fromBorder, fromIcon) = resolveColorsForMuted(palette, tFrom)
            val (toBg, toBorder, toIcon) = resolveColorsForMuted(palette, tTo)
            val f = transitionFraction.coerceIn(0f, 1f)
            bgColor = colorEvaluator.evaluate(f, fromBg, toBg) as Int
            borderColor = colorEvaluator.evaluate(f, fromBorder, toBorder) as Int
            iconHexColor = colorEvaluator.evaluate(f, fromIcon, toIcon) as Int
            val displayMuted = if (f < 0.5f) tFrom else tTo
            showSlash = displayMuted
            label = if (displayMuted) "MUTED" else "LIVE"
        } else {
            val resolved = resolveColorsForMuted(palette, muted)
            bgColor = resolved.first
            borderColor = resolved.second
            iconHexColor = resolved.third
            showSlash = muted
            label = if (muted) "MUTED" else "LIVE"
        }

        // Compute bounded optical metrics matching live canvas dimensions
        val effScale = effectiveScale()
        val metrics = MicPillMetricsCalculator.computeForCanvasBounds(
            canvasWidthPx = w,
            canvasHeightPx = h,
            effectiveScale = effScale,
            showText = config.showText,
            sleekCorners = config.sleekCorners,
            label = label,
            density = density,
            measureTextWidth = { text, textSize ->
                textPaint.textSize = textSize
                textPaint.measureText(text)
            }
        )

        pillRect.set(metrics.pillLeft, metrics.pillTop, metrics.pillRight, metrics.pillBottom)

        val alphaScale = currentAlpha / 255f
        val effectiveAlpha = (255 * alphaScale).roundToInt().coerceIn(0, 255)

        // 1. Soft outer elevation halo inside safe inset bounds (zero shadow-layer GPU penalty)
        drawOuterElevationHalo(canvas, metrics, alphaScale)

        // 2. High-DPI vertical tonal LinearGradient fill (+6% top highlight to -6% bottom depth)
        ensureFillShader(bgColor, pillRect.top, pillRect.bottom)
        bgPaint.color = bgColor
        bgPaint.shader = cachedFillShader
        bgPaint.alpha = effectiveAlpha
        canvas.drawRoundRect(pillRect, metrics.cornerRadiusPx, metrics.cornerRadiusPx, bgPaint)

        // 3. Crisp inner specular rim (1px-1.5dp) for Fluent glass depth
        val specInset = metrics.strokeWidthPx / 2f + metrics.specularStrokeWidthPx / 2f
        specularRect.set(
            pillRect.left + specInset,
            pillRect.top + specInset,
            pillRect.right - specInset,
            pillRect.bottom - specInset
        )
        if (specularRect.width() > 2f && specularRect.height() > 2f) {
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

        // 4. Optical sub-linear outer border (strictly <= 3.0dp even at 5.0x)
        borderPaint.strokeWidth = metrics.strokeWidthPx
        borderPaint.color = borderColor
        borderPaint.alpha = effectiveAlpha
        canvas.drawRoundRect(pillRect, metrics.cornerRadiusPx, metrics.cornerRadiusPx, borderPaint)

        // 5. Foreground content (precision 24x24 vector mic glyph + optically centered label)
        contentPaint.color = iconHexColor
        contentPaint.alpha = effectiveAlpha
        strokeIconPaint.color = iconHexColor
        strokeIconPaint.alpha = effectiveAlpha
        knockoutSlashPaint.color = bgColor
        knockoutSlashPaint.shader = cachedFillShader
        knockoutSlashPaint.alpha = effectiveAlpha

        if (config.showText) {
            textPaint.color = iconHexColor
            textPaint.alpha = effectiveAlpha
            textPaint.textSize = metrics.textSizePx
            val fm = textPaint.fontMetrics
            val textBaseline = metrics.iconCenterYPx - (fm.ascent + fm.descent) / 2f
            canvas.drawText(label, metrics.textStartXPx, textBaseline, textPaint)
        }

        drawPrecisionMicrophoneGlyph(
            canvas = canvas,
            iconLeft = metrics.iconLeftPx,
            iconTop = metrics.iconCenterYPx - metrics.iconSizePx / 2f,
            size = metrics.iconSizePx,
            mutedSlash = showSlash
        )

        // 6. Hold-progress ring drawn safely within outer inset padding
        drawHoldProgressRing(canvas, metrics)
    }

    private fun ensureFillShader(bgColor: Int, top: Float, bottom: Float) {
        if (cachedFillShader != null &&
            cachedFillColor == bgColor &&
            cachedFillTop == top &&
            cachedFillBottom == bottom
        ) {
            return
        }
        val topColor = MicPillMetricsCalculator.computeTonalTopColor(bgColor)
        val bottomColor = MicPillMetricsCalculator.computeTonalBottomColor(bgColor)
        cachedFillShader = LinearGradient(
            0f,
            top,
            0f,
            bottom,
            topColor,
            bottomColor,
            Shader.TileMode.CLAMP
        )
        cachedFillColor = bgColor
        cachedFillTop = top
        cachedFillBottom = bottom
    }

    private fun ensureSpecularShader(top: Float, bottom: Float) {
        if (cachedSpecularShader != null &&
            cachedSpecularTop == top &&
            cachedSpecularBottom == bottom
        ) {
            return
        }
        cachedSpecularShader = LinearGradient(
            0f,
            top,
            0f,
            bottom,
            intArrayOf(0x3DFFFFFF, 0x10FFFFFF, 0x00FFFFFF),
            floatArrayOf(0f, 0.45f, 1f),
            Shader.TileMode.CLAMP
        )
        cachedSpecularTop = top
        cachedSpecularBottom = bottom
    }

    private fun drawOuterElevationHalo(canvas: Canvas, metrics: MicPillRenderMetrics, alphaScale: Float) {
        val baseHaloAlpha = (alphaScale * alphaScale).coerceIn(0f, 1f)
        if (baseHaloAlpha <= 0.05f) return

        // 3 soft concentric halo passes strictly bounded within safeOuterInsetPx
        val spread = metrics.haloSpreadPx.coerceAtMost(metrics.safeOuterInsetPx)
        val yShift = metrics.haloOffsetYPx.coerceAtMost((metrics.safeOuterInsetPx - spread).coerceAtLeast(0f))

        // Outer soft bloom
        haloPaint.color = Color.BLACK
        haloPaint.alpha = (18 * baseHaloAlpha).roundToInt().coerceIn(0, 255)
        haloRect.set(
            pillRect.left - spread,
            pillRect.top - spread * 0.45f + yShift,
            pillRect.right + spread,
            pillRect.bottom + spread + yShift
        )
        val rOuter = metrics.cornerRadiusPx + spread * 0.75f
        canvas.drawRoundRect(haloRect, rOuter, rOuter, haloPaint)

        // Mid ambient shadow
        val midSpread = spread * 0.62f
        haloPaint.alpha = (28 * baseHaloAlpha).roundToInt().coerceIn(0, 255)
        haloRect.set(
            pillRect.left - midSpread,
            pillRect.top - midSpread * 0.25f + yShift * 0.75f,
            pillRect.right + midSpread,
            pillRect.bottom + midSpread + yShift * 0.75f
        )
        val rMid = metrics.cornerRadiusPx + midSpread * 0.65f
        canvas.drawRoundRect(haloRect, rMid, rMid, haloPaint)

        // Tight contact shadow
        val innerSpread = spread * 0.30f
        haloPaint.alpha = (36 * baseHaloAlpha).roundToInt().coerceIn(0, 255)
        haloRect.set(
            pillRect.left - innerSpread,
            pillRect.top + yShift * 0.4f,
            pillRect.right + innerSpread,
            pillRect.bottom + innerSpread + yShift * 0.5f
        )
        val rInner = metrics.cornerRadiusPx + innerSpread * 0.5f
        canvas.drawRoundRect(haloRect, rInner, rInner, haloPaint)
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
            val sx = vx(MicVectorSpec24.SLASH_START_X)
            val sy = vy(MicVectorSpec24.SLASH_START_Y)
            val ex = vx(MicVectorSpec24.SLASH_END_X)
            val ey = vy(MicVectorSpec24.SLASH_END_Y)

            // Pass 1: Pill-fill mask stroke creates a crisp visual knockout gap behind the slash
            knockoutSlashPaint.strokeWidth = glyphStroke * MicVectorSpec24.SLASH_MASK_MULTIPLIER
            canvas.drawLine(sx, sy, ex, ey, knockoutSlashPaint)

            // Pass 2: Crisp foreground diagonal mute slash
            strokeIconPaint.strokeWidth = glyphStroke * MicVectorSpec24.SLASH_FG_MULTIPLIER
            canvas.drawLine(sx, sy, ex, ey, strokeIconPaint)
            strokeIconPaint.strokeWidth = glyphStroke
        }
    }
}
