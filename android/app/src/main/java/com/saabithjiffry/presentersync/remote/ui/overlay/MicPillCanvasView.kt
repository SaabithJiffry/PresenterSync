package com.saabithjiffry.presentersync.remote.ui.overlay

import android.animation.ArgbEvaluator
import android.content.Context
import android.graphics.PathMeasure
import com.saabithjiffry.presentersync.remote.input.BubbleHoldStage
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import android.view.View
import com.saabithjiffry.presentersync.remote.config.AppConstants
import com.saabithjiffry.presentersync.remote.config.HudColorPalette
import com.saabithjiffry.presentersync.remote.config.HudColorPalettes
import com.saabithjiffry.presentersync.remote.config.RemoteConfig
import com.saabithjiffry.presentersync.remote.network.ConnStatus
import com.saabithjiffry.presentersync.remote.network.ConnectionUiState
import kotlin.math.min
import kotlin.math.roundToInt

class MicPillCanvasView(context: Context) : View(context) {
    private val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
    private val contentPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val strokeIconPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
    }

    private val pillRect = RectF()
    private val micBodyRect = RectF()
    private val micArcRect = RectF()
    private val micArcPath = Path()

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
        return ScreenBoundsCalculator.computeBoundedPillScale(
            requestedScale = config.indicatorScale,
            showText = config.showText,
            safeWidthPx = boundWidth,
            density = resources.displayMetrics.density
        )
    }

    fun computeTargetWidthPx(safeWidthPx: Int = maxContainerWidthPx): Int {
        val baseDp = if (config.showText) AppConstants.BASE_WIDTH_TEXT else AppConstants.BASE_WIDTH_ICON
        return dpToPx(baseDp * effectiveScale(safeWidthPx)).coerceAtLeast(16)
    }

    fun computeTargetHeightPx(safeWidthPx: Int = maxContainerWidthPx): Int {
        return dpToPx(AppConstants.BASE_HEIGHT * effectiveScale(safeWidthPx)).coerceAtLeast(12)
    }

    private fun dpToPx(dp: Float): Int {
        return (dp * resources.displayMetrics.density).roundToInt()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val w = computeTargetWidthPx()
        val h = computeTargetHeightPx()
        setMeasuredDimension(w, h)
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val w = width.toFloat()
        val h = height.toFloat()
        if (w <= 0f || h <= 0f) return

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

        val scale = (h / dpToPx(AppConstants.BASE_HEIGHT.toFloat()).coerceAtLeast(1).toFloat())
            .coerceAtLeast(0.25f)
        val strokeW = (1.5f * resources.displayMetrics.density * scale).coerceAtLeast(1f)
        val halfStroke = strokeW / 2f
        pillRect.set(halfStroke, halfStroke, w - halfStroke, h - halfStroke)

        val cornerRadius = if (config.sleekCorners) {
            h / 2f
        } else {
            min(dpToPx(AppConstants.CORNER_RADIUS_DEFAULT * config.indicatorScale).toFloat(), h / 2f)
        }

        val alphaScale = currentAlpha / 255f
        bgPaint.color = bgColor
        bgPaint.alpha = (255 * alphaScale).roundToInt().coerceIn(0, 255)
        canvas.drawRoundRect(pillRect, cornerRadius, cornerRadius, bgPaint)

        borderPaint.strokeWidth = strokeW
        borderPaint.color = borderColor
        borderPaint.alpha = (255 * alphaScale).roundToInt().coerceIn(0, 255)
        canvas.drawRoundRect(pillRect, cornerRadius, cornerRadius, borderPaint)

        val contentAlpha = (255 * alphaScale).roundToInt().coerceIn(0, 255)
        contentPaint.color = iconHexColor
        contentPaint.alpha = contentAlpha
        strokeIconPaint.color = iconHexColor
        strokeIconPaint.alpha = contentAlpha
        textPaint.color = iconHexColor
        textPaint.alpha = contentAlpha

        val iconCenterX: Float
        if (config.showText) {
            val iconZoneLeft = w * 0.11f
            val iconZoneWidth = w * 0.18f
            iconCenterX = iconZoneLeft + iconZoneWidth / 2f
            val textX = w * 0.34f
            textPaint.textSize = (h * 0.44f).coerceAtLeast(8f)
            val fm = textPaint.fontMetrics
            val textBaseline = h / 2f - (fm.ascent + fm.descent) / 2f
            canvas.drawText(label, textX, textBaseline, textPaint)
        } else {
            iconCenterX = w / 2f
        }

        drawMicrophoneGlyph(canvas, iconCenterX, h / 2f, h * 0.56f, showSlash)
        drawHoldProgressRing(canvas, cornerRadius, strokeW)
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

    private fun drawHoldProgressRing(canvas: Canvas, cornerRadius: Float, baseStrokeW: Float) {
        if (holdStage == BubbleHoldStage.IDLE || holdProgress <= 0f) return
        val ringStroke = (baseStrokeW * 1.9f).coerceAtLeast(3f)
        holdPaint.strokeWidth = ringStroke
        holdPaint.color = when (holdStage) {
            BubbleHoldStage.PROGRESS_LONG -> Color.parseColor("#F59E0B")
            BubbleHoldStage.REACHED_LONG -> Color.parseColor("#FBBF24")
            BubbleHoldStage.PROGRESS_VERY_LONG -> Color.parseColor("#38BDF8")
            BubbleHoldStage.REACHED_VERY_LONG -> Color.parseColor("#60CDFF")
            BubbleHoldStage.IDLE -> return
        }
        holdOutlinePath.reset()
        holdOutlinePath.addRoundRect(pillRect, cornerRadius, cornerRadius, Path.Direction.CW)
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

    private fun drawMicrophoneGlyph(
        canvas: Canvas,
        cx: Float,
        cy: Float,
        size: Float,
        mutedSlash: Boolean
    ) {
        val stroke = (size * 0.105f).coerceAtLeast(1.4f)
        strokeIconPaint.strokeWidth = stroke

        val capsuleW = size * 0.30f
        val capsuleH = size * 0.50f
        val capsuleTop = cy - size * 0.38f
        micBodyRect.set(
            cx - capsuleW / 2f,
            capsuleTop,
            cx + capsuleW / 2f,
            capsuleTop + capsuleH
        )
        canvas.drawRoundRect(micBodyRect, capsuleW / 2f, capsuleW / 2f, contentPaint)

        val arcW = size * 0.56f
        val arcTop = cy - size * 0.24f
        val arcBottom = cy + size * 0.24f
        micArcRect.set(cx - arcW / 2f, arcTop, cx + arcW / 2f, arcBottom)
        micArcPath.reset()
        micArcPath.addArc(micArcRect, 0f, 180f)
        canvas.drawPath(micArcPath, strokeIconPaint)

        val stemTop = arcBottom
        val stemBottom = cy + size * 0.39f
        canvas.drawLine(cx, stemTop, cx, stemBottom, strokeIconPaint)
        canvas.drawLine(cx - size * 0.18f, stemBottom, cx + size * 0.18f, stemBottom, strokeIconPaint)

        if (mutedSlash) {
            val pad = size * 0.40f
            canvas.drawLine(cx - pad, cy - pad, cx + pad, cy + pad, strokeIconPaint)
        }
    }
}
