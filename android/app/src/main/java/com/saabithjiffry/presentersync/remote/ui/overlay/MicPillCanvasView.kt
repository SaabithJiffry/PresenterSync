package com.saabithjiffry.presentersync.remote.ui.overlay

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import android.view.View
import com.saabithjiffry.presentersync.remote.config.AppConstants
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

    fun updateRenderState(
        cfg: RemoteConfig,
        conn: ConnectionUiState,
        alpha: Int = cfg.opacityLevel,
        mutedOverride: Boolean? = null
    ) {
        config = cfg
        connState = conn
        currentAlpha = alpha.coerceIn(0, 255)
        overrideMuted = mutedOverride
        invalidate()
    }

    fun computeTargetWidthPx(): Int {
        val baseDp = if (config.showText) AppConstants.BASE_WIDTH_TEXT else AppConstants.BASE_WIDTH_ICON
        return dpToPx(baseDp * config.indicatorScale).coerceAtLeast(16)
    }

    fun computeTargetHeightPx(): Int {
        return dpToPx(AppConstants.BASE_HEIGHT * config.indicatorScale).coerceAtLeast(12)
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

        val palette = HudColorPalettes.get(config.hudColorPreset)
        val isOffline = overrideMuted == null && !connState.connected
        val muted = overrideMuted ?: connState.isMuted

        val bgColor: Int
        val borderColor: Int
        val iconHexColor: Int
        val showSlash: Boolean
        val label: String

        if (isOffline) {
            val isAuthErr = connState.connStatus == ConnStatus.AUTH_FAILED
            bgColor = palette.offlineBg
            borderColor = if (isAuthErr) palette.authErrBorder else palette.offlineBg
            iconHexColor = if (config.monoIcon) palette.offlineIcon else Color.parseColor("#E5E7EB")
            showSlash = true
            label = if (isAuthErr) "AUTH ERR" else "OFFLINE"
        } else {
            bgColor = if (muted) palette.mutedBg else palette.liveBg
            borderColor = bgColor
            iconHexColor = if (config.monoIcon) {
                if (muted) palette.mutedIcon else palette.liveIcon
            } else {
                Color.WHITE
            }
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
        borderPaint.color = adjustBorderColor(borderColor, isOffline && connState.connStatus == ConnStatus.AUTH_FAILED)
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
