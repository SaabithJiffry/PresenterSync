package com.saabithjiffry.presentersync.remote.ui.overlay

import android.content.Context
import android.content.res.Configuration
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PathMeasure
import android.graphics.RectF
import android.graphics.Typeface
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.View
import com.saabithjiffry.presentersync.remote.config.AppConstants
import com.saabithjiffry.presentersync.remote.config.RemoteConfig
import com.saabithjiffry.presentersync.remote.config.ThemeMode
import com.saabithjiffry.presentersync.remote.input.BubbleHoldStage
import com.saabithjiffry.presentersync.remote.network.ConnectionUiState
import kotlin.math.roundToInt

/**
 * Pure metrics & marquee helper for [ScenePillCanvasView] so sizing and marquee offset
 * math can be deterministically verified in unit tests.
 */
object ScenePillMetricsCalculator {
    const val STAGE1_AMBER_RING_ARGB: Int = 0xFFF59E0B.toInt()
    const val STAGE2_CYAN_RING_ARGB: Int = 0xFF38BDF8.toInt()
    const val MARQUEE_GAP_DP: Float = 26f
    const val MARQUEE_SPEED_DP_PER_SEC: Float = 28f
    const val SCENE_BASE_WIDTH_DP: Float = 152f
    const val SCENE_BASE_HEIGHT_DP: Float = 36f

    fun formatSceneDisplayText(conn: ConnectionUiState): String {
        if (!conn.connected) return "Offline"
        val active = conn.activeScene.trim().ifEmpty { "Scene" }
        val prev = conn.previewScene.trim()
        return if (conn.studioModeActive && prev.isNotEmpty() && prev != active) {
            "$active → $prev"
        } else {
            active
        }
    }

    fun computeMarqueeScrollOffset(
        textWidthPx: Float,
        clipWidthPx: Float,
        gapPx: Float,
        elapsedMs: Long,
        speedPxPerSec: Float
    ): Float {
        if (textWidthPx <= clipWidthPx || clipWidthPx <= 0f || speedPxPerSec <= 0f) return 0f
        val cyclePx = (textWidthPx + gapPx).coerceAtLeast(1f)
        val raw = (elapsedMs.coerceAtLeast(0L) / 1000f) * speedPxPerSec
        return raw % cyclePx
    }

    fun computeEffectiveScale(requestedScale: Float, safeWidthPx: Int, density: Float): Float {
        val safeDensity = density.coerceAtLeast(0.5f)
        val maxAllowedW = (safeWidthPx * AppConstants.PILL_MAX_VIEWPORT_WIDTH_FRACTION).coerceAtLeast(80f)
        val safeReq = requestedScale.coerceIn(0.5f, 3.0f)
        val maxScaleByViewport = maxAllowedW / (SCENE_BASE_WIDTH_DP * safeDensity)
        return minOf(safeReq, maxScaleByViewport).coerceIn(0.65f, 3.0f)
    }
}

class ScenePillCanvasView(context: Context) : View(context) {
    private val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
    private val dotPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val textPaint = Paint(
        Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG or Paint.LINEAR_TEXT_FLAG
    ).apply {
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
    }
    private val ringPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
    }

    private val pillRect = RectF()
    private val textClipRect = RectF()
    private val holdPath = Path()
    private val holdSegmentPath = Path()
    private val holdMeasure = PathMeasure()

    private var config: RemoteConfig = RemoteConfig()
    private var connState: ConnectionUiState = ConnectionUiState()
    private var currentAlpha: Int = AppConstants.OPACITY_FROSTED
    private var maxContainerWidthPx: Int = 0
    private var holdStage: BubbleHoldStage = BubbleHoldStage.IDLE
    private var holdProgress: Float = 0f

    private var marqueeEnabled = false
    private var marqueeStartMs = SystemClock.uptimeMillis()
    private val animHandler = Handler(Looper.getMainLooper())
    private val marqueeRunnable = object : Runnable {
        override fun run() {
            if (marqueeEnabled && isAttachedToWindow && visibility == VISIBLE) {
                invalidate()
                animHandler.postDelayed(this, 33L)
            }
        }
    }

    fun updateRenderState(
        cfg: RemoteConfig,
        conn: ConnectionUiState,
        alpha: Int = cfg.opacityLevel,
        maxContainerWidthPx: Int = this.maxContainerWidthPx
    ) {
        val textBefore = ScenePillMetricsCalculator.formatSceneDisplayText(connState)
        config = cfg
        connState = conn
        currentAlpha = alpha.coerceIn(0, 255)
        this.maxContainerWidthPx = maxContainerWidthPx
        val textAfter = ScenePillMetricsCalculator.formatSceneDisplayText(conn)
        if (textBefore != textAfter) {
            marqueeStartMs = SystemClock.uptimeMillis()
        }
        invalidate()
    }

    fun setHoldVisualState(stage: BubbleHoldStage, progressFraction: Float) {
        val clamped = progressFraction.coerceIn(0f, 1f)
        if (holdStage == stage && kotlin.math.abs(holdProgress - clamped) < 0.01f) return
        holdStage = stage
        holdProgress = clamped
        invalidate()
    }

    private fun effScale(safeWidthPx: Int = maxContainerWidthPx): Float {
        val bound = if (safeWidthPx > 0) safeWidthPx else resources.displayMetrics.widthPixels
        return ScenePillMetricsCalculator.computeEffectiveScale(
            requestedScale = config.indicatorScale,
            safeWidthPx = bound,
            density = resources.displayMetrics.density
        )
    }

    fun computeTargetWidthPx(safeWidthPx: Int = maxContainerWidthPx): Int {
        val d = resources.displayMetrics.density.coerceAtLeast(0.5f)
        val sc = effScale(safeWidthPx)
        val inset = (8f * d).roundToInt()
        return ((ScenePillMetricsCalculator.SCENE_BASE_WIDTH_DP * sc * d).roundToInt() + inset * 2).coerceAtLeast(80)
    }

    fun computeTargetHeightPx(safeWidthPx: Int = maxContainerWidthPx): Int {
        val d = resources.displayMetrics.density.coerceAtLeast(0.5f)
        val sc = effScale(safeWidthPx)
        val inset = (8f * d).roundToInt()
        return ((ScenePillMetricsCalculator.SCENE_BASE_HEIGHT_DP * sc * d).roundToInt() + inset * 2).coerceAtLeast(36)
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val bound = if (maxContainerWidthPx > 0) maxContainerWidthPx else resources.displayMetrics.widthPixels
        setMeasuredDimension(computeTargetWidthPx(bound), computeTargetHeightPx(bound))
    }

    override fun onDetachedFromWindow() {
        marqueeEnabled = false
        animHandler.removeCallbacks(marqueeRunnable)
        super.onDetachedFromWindow()
    }

    private fun syncMarqueeTicker(needsScroll: Boolean) {
        if (needsScroll && !marqueeEnabled) {
            marqueeEnabled = true
            marqueeStartMs = SystemClock.uptimeMillis()
            animHandler.removeCallbacks(marqueeRunnable)
            animHandler.postDelayed(marqueeRunnable, 600L)
        } else if (!needsScroll && marqueeEnabled) {
            marqueeEnabled = false
            animHandler.removeCallbacks(marqueeRunnable)
        }
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val w = width.toFloat()
        val h = height.toFloat()
        if (w <= 4f || h <= 4f) return

        val d = resources.displayMetrics.density.coerceAtLeast(0.5f)
        val sc = effScale()
        val inset = 8f * d
        pillRect.set(inset, inset, (w - inset).coerceAtLeast(inset + 12f), (h - inset).coerceAtLeast(inset + 12f))
        val corner = if (config.sleekCorners) 9f * d * sc else pillRect.height() / 2f

        val isDark = when (config.themeMode) {
            ThemeMode.DARK -> true
            ThemeMode.LIGHT -> false
            ThemeMode.SYSTEM -> {
                val night = resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
                night != Configuration.UI_MODE_NIGHT_NO
            }
        }

        val alpha = currentAlpha.coerceIn(32, 255)
        bgPaint.color = if (isDark) Color.parseColor("#18181B") else Color.parseColor("#F8FAFC")
        bgPaint.alpha = alpha
        canvas.drawRoundRect(pillRect, corner, corner, bgPaint)

        borderPaint.strokeWidth = (1.5f * d * sc).coerceIn(1.5f, 4f * d)
        borderPaint.color = when {
            !connState.connected -> if (isDark) Color.parseColor("#475569") else Color.parseColor("#94A3B8")
            connState.isStandby -> ScenePillMetricsCalculator.STAGE1_AMBER_RING_ARGB
            connState.studioModeActive -> Color.parseColor("#38BDF8")
            else -> if (isDark) Color.parseColor("#3F3F46") else Color.parseColor("#CBD5E1")
        }
        borderPaint.alpha = alpha
        canvas.drawRoundRect(pillRect, corner, corner, borderPaint)

        // Status indicator dot
        val dotRadius = (4.2f * d * sc).coerceIn(3.5f * d, 9f * d)
        val dotCx = pillRect.left + (12f * d * sc) + dotRadius
        val dotCy = pillRect.centerY()
        dotPaint.color = when {
            !connState.connected -> Color.parseColor("#64748B")
            connState.recState == 1 -> Color.parseColor("#EF4444")
            connState.isStandby -> Color.parseColor("#F59E0B")
            else -> Color.parseColor("#10B981")
        }
        dotPaint.alpha = alpha
        canvas.drawCircle(dotCx, dotCy, dotRadius, dotPaint)

        // Scene text with smooth marquee overflow handling
        val label = ScenePillMetricsCalculator.formatSceneDisplayText(connState)
        textPaint.color = if (isDark) Color.parseColor("#F8FAFC") else Color.parseColor("#0F172A")
        textPaint.alpha = alpha
        textPaint.textSize = (12.5f * d * sc).coerceIn(10f * d, 24f * d)

        val textLeft = dotCx + dotRadius + (7f * d * sc)
        val textRight = pillRect.right - (10f * d * sc)
        if (textRight > textLeft + 8f) {
            val clipW = textRight - textLeft
            val measuredW = textPaint.measureText(label)
            val needsScroll = measuredW > clipW + 1f
            syncMarqueeTicker(needsScroll)

            textClipRect.set(textLeft, pillRect.top, textRight, pillRect.bottom)
            val saveCount = canvas.save()
            canvas.clipRect(textClipRect)
            val fm = textPaint.fontMetrics
            val baseline = pillRect.centerY() - (fm.ascent + fm.descent) / 2f

            if (!needsScroll) {
                canvas.drawText(label, textLeft, baseline, textPaint)
            } else {
                val gapPx = ScenePillMetricsCalculator.MARQUEE_GAP_DP * d * sc
                val elapsed = (SystemClock.uptimeMillis() - marqueeStartMs - 600L).coerceAtLeast(0L)
                val offset = ScenePillMetricsCalculator.computeMarqueeScrollOffset(
                    textWidthPx = measuredW,
                    clipWidthPx = clipW,
                    gapPx = gapPx,
                    elapsedMs = elapsed,
                    speedPxPerSec = ScenePillMetricsCalculator.MARQUEE_SPEED_DP_PER_SEC * d
                )
                canvas.drawText(label, textLeft - offset, baseline, textPaint)
                val secondX = textLeft - offset + measuredW + gapPx
                if (secondX < textRight) {
                    canvas.drawText(label, secondX, baseline, textPaint)
                }
            }
            canvas.restoreToCount(saveCount)
        } else {
            syncMarqueeTicker(false)
        }

        // Two-stage hold progress ring (Stage 1 = Amber Quick Menu; Stage 2 = Cyan Reset Active Scene)
        if (holdStage != BubbleHoldStage.IDLE && holdProgress > 0f) {
            val ringPad = borderPaint.strokeWidth / 2f + (2.5f * d * sc)
            val ringRect = RectF(
                pillRect.left - ringPad,
                pillRect.top - ringPad,
                pillRect.right + ringPad,
                pillRect.bottom + ringPad
            )
            holdPath.reset()
            holdPath.addRoundRect(ringRect, corner + ringPad, corner + ringPad, Path.Direction.CW)
            holdMeasure.setPath(holdPath, false)
            val len = holdMeasure.length
            if (len > 0f) {
                holdSegmentPath.reset()
                holdMeasure.getSegment(0f, len * holdProgress.coerceIn(0f, 1f), holdSegmentPath, true)
                ringPaint.strokeWidth = (2.8f * d * sc).coerceIn(2.5f * d, 6f * d)
                ringPaint.color = if (
                    holdStage == BubbleHoldStage.PROGRESS_VERY_LONG ||
                    holdStage == BubbleHoldStage.REACHED_VERY_LONG
                ) {
                    ScenePillMetricsCalculator.STAGE2_CYAN_RING_ARGB
                } else {
                    ScenePillMetricsCalculator.STAGE1_AMBER_RING_ARGB
                }
                canvas.drawPath(holdSegmentPath, ringPaint)
            }
        }
    }
}
