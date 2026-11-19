package com.saabithjiffry.presentersync.remote.ui.overlay

import com.saabithjiffry.presentersync.remote.config.AppConstants
import com.saabithjiffry.presentersync.remote.network.ConnectionUiState
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sqrt

/**
 * Pure, zero-allocation geometry & optical layout metrics for [MicPillCanvasView].
 * Shared between the live Smart Board overlay, the Settings preview card, and JVM unit tests.
 */
data class MicPillRenderMetrics(
    val effectiveScale: Float,
    val density: Float,
    val showText: Boolean,
    val sleekCorners: Boolean,
    val label: String,
    val safeOuterInsetPx: Float,
    val innerWidthPx: Float,
    val innerHeightPx: Float,
    val totalViewWidthPx: Int,
    val totalViewHeightPx: Int,
    val pillLeft: Float,
    val pillTop: Float,
    val pillRight: Float,
    val pillBottom: Float,
    val strokeWidthPx: Float,
    val specularStrokeWidthPx: Float,
    val holdRingStrokeWidthPx: Float,
    val haloSpreadPx: Float,
    val haloOffsetYPx: Float,
    val cornerRadiusPx: Float,
    val specularCornerRadiusPx: Float,
    val innerPadXPx: Float,
    val iconSizePx: Float,
    val iconLeftPx: Float,
    val iconRightPx: Float,
    val iconCenterXPx: Float,
    val iconCenterYPx: Float,
    val iconTextGapPx: Float,
    val maxTextWidthPx: Float,
    val textSizePx: Float,
    val measuredTextWidthPx: Float,
    val textStartXPx: Float,
    val textEndXPx: Float
) {
    val leftContentMarginPx: Float get() = iconLeftPx - pillLeft
    val rightContentMarginPx: Float get() = if (showText) (pillRight - textEndXPx) else (pillRight - iconRightPx)
}

/**
 * Normalized 24x24 viewport microphone vector specification (Fluent / Material balanced proportions).
 */
object MicVectorSpec24 {
    const val VIEWPORT_SIZE = 24f

    // Balanced pill capsule
    const val CAPSULE_LEFT = 8.5f
    const val CAPSULE_TOP = 2.0f
    const val CAPSULE_RIGHT = 15.5f
    const val CAPSULE_BOTTOM = 14.0f
    const val CAPSULE_RADIUS = 3.5f

    // Tapered U-cradle arc & short vertical arms
    const val CRADLE_LEFT = 5.25f
    const val CRADLE_TOP = 4.5f
    const val CRADLE_RIGHT = 18.75f
    const val CRADLE_BOTTOM = 18.0f
    const val CRADLE_ARM_TOP_Y = 10.25f
    const val CRADLE_ARM_JOIN_Y = 11.25f

    // Stem & stand base
    const val CENTER_X = 12.0f
    const val STEM_TOP_Y = 18.0f
    const val STEM_BOTTOM_Y = 21.5f
    const val BASE_LEFT_X = 8.25f
    const val BASE_RIGHT_X = 15.75f

    // Stroke weights in 24x24 space
    const val GLYPH_STROKE = 2.0f
    const val SLASH_START_X = 3.2f
    const val SLASH_START_Y = 3.2f
    const val SLASH_END_X = 20.8f
    const val SLASH_END_Y = 20.8f
    const val SLASH_MASK_MULTIPLIER = 2.45f
    const val SLASH_FG_MULTIPLIER = 1.05f
}

object MicPillMetricsCalculator {
    const val MAX_STROKE_DP = 3.0f
    const val BASE_STROKE_DP = 1.25f
    const val SPECULAR_RIM_DP = 1.0f
    const val MAX_SPECULAR_RIM_DP = 1.5f
    const val TEXT_LETTER_SPACING = 0.045f
    const val BASE_TEXT_HEIGHT_RATIO = 0.43f
    const val ICON_HEIGHT_RATIO = 0.56f
    const val INNER_PAD_X_RATIO = 0.26f
    const val ICON_TEXT_GAP_RATIO = 0.20f
    const val MIN_TEXT_SIZE_PX = 7.0f
    const val TONAL_HIGHLIGHT_FRACTION = 0.06f
    const val TONAL_DEPTH_FRACTION = 0.06f

    /**
     * Sub-linear optical border stroke capped strictly at <= 3.0dp so 3.0x-5.0x Smart Board
     * indicators remain razor-crisp rather than inflating into bulky 7.5dp walls.
     */
    fun computeOpticalStrokePx(effectiveScale: Float, density: Float): Float {
        val safeDensity = density.coerceAtLeast(0.5f)
        val safeScale = effectiveScale.coerceAtLeast(0.25f)
        return (BASE_STROKE_DP * safeDensity * sqrt(safeScale))
            .coerceAtMost(MAX_STROKE_DP * safeDensity)
            .coerceAtLeast(1.0f)
    }

    /**
     * Crisp 1px-1.5dp inner specular rim stroke.
     */
    fun computeSpecularRimStrokePx(density: Float): Float {
        val safeDensity = density.coerceAtLeast(0.5f)
        return (SPECULAR_RIM_DP * safeDensity).coerceIn(1.0f, MAX_SPECULAR_RIM_DP * safeDensity)
    }

    fun computeHoldRingStrokePx(strokeWidthPx: Float, density: Float): Float {
        val safeDensity = density.coerceAtLeast(0.5f)
        return (strokeWidthPx * 1.85f)
            .coerceAtLeast(3.0f)
            .coerceAtMost(5.5f * safeDensity)
    }

    fun computeHaloMetricsPx(effectiveScale: Float, density: Float): Pair<Float, Float> {
        val safeDensity = density.coerceAtLeast(0.5f)
        val safeScale = effectiveScale.coerceAtLeast(0.25f)
        val spread = (2.5f * safeDensity * sqrt(safeScale))
            .coerceIn(2.0f * safeDensity, 5.0f * safeDensity)
        val offsetY = (0.9f * safeDensity * sqrt(safeScale))
            .coerceIn(0.5f * safeDensity, 2.0f * safeDensity)
        return spread to offsetY
    }

    /**
     * Safe symmetric outer inset around the pill so outer elevation halos and hold-progress
     * rings never clip against the View / WindowManager bounds.
     */
    fun computeSafeOuterInsetPx(effectiveScale: Float, density: Float): Float {
        val strokeW = computeOpticalStrokePx(effectiveScale, density)
        val holdRingW = computeHoldRingStrokePx(strokeW, density)
        val (haloSpread, haloOffsetY) = computeHaloMetricsPx(effectiveScale, density)
        val requiredForHalo = haloSpread + haloOffsetY
        val requiredForHoldRing = holdRingW / 2f + 1.0f
        val requiredForBorder = strokeW / 2f + 1.0f
        return ceil(max(requiredForHalo, max(requiredForHoldRing, requiredForBorder)))
    }

    /**
     * Computes the effective bounded pill scale accounting for both viewport width fraction
     * and safe outer inset padding so total view width never overflows [safeWidthPx].
     */
    fun computeEffectiveScale(
        requestedScale: Float,
        showText: Boolean,
        safeWidthPx: Int,
        density: Float
    ): Float {
        val safeDensity = density.coerceAtLeast(0.5f)
        val baseBounded = ScreenBoundsCalculator.computeBoundedPillScale(
            requestedScale = requestedScale,
            showText = showText,
            safeWidthPx = safeWidthPx,
            density = safeDensity
        )
        if (safeWidthPx <= 0) return baseBounded

        val baseWidthDp = if (showText) AppConstants.BASE_WIDTH_TEXT else AppConstants.BASE_WIDTH_ICON
        val inset = computeSafeOuterInsetPx(baseBounded, safeDensity)
        val projectedTotal = (baseWidthDp * baseBounded * safeDensity).roundToInt() + (inset * 2f).roundToInt()
        if (projectedTotal <= safeWidthPx) return baseBounded

        val availInnerPx = (safeWidthPx - inset * 2f).coerceAtLeast(16f)
        val maxScale = (availInnerPx / (baseWidthDp * safeDensity)).coerceAtLeast(0.25f)
        return baseBounded.coerceAtMost(maxScale)
    }

    /**
     * Deterministic JVM-safe text width estimator used as default for pure unit tests
     * when Android Paint font metrics are unavailable.
     */
    fun estimateBoldLabelWidthPx(label: String, textSizePx: Float, letterSpacing: Float = TEXT_LETTER_SPACING): Float {
        if (label.isEmpty() || textSizePx <= 0f) return 0f
        var units = 0f
        for (ch in label) {
            units += when (ch) {
                'I', '1', '!', '|' -> 0.34f
                ' ' -> 0.32f
                'M', 'W' -> 0.84f
                'L', 'F', 'T', 'J' -> 0.56f
                else -> 0.66f
            }
        }
        val tracking = if (label.length > 1) (label.length - 1) * letterSpacing else 0f
        return (units + tracking) * textSizePx
    }

    /**
     * Computes full layout metrics from configuration & viewport bounds.
     */
    fun computeForTargetSize(
        requestedScale: Float,
        showText: Boolean,
        sleekCorners: Boolean,
        label: String,
        safeWidthPx: Int,
        density: Float,
        measureTextWidth: (text: String, textSizePx: Float) -> Float = { t, sz -> estimateBoldLabelWidthPx(t, sz) }
    ): MicPillRenderMetrics {
        val safeDensity = density.coerceAtLeast(0.5f)
        val effScale = computeEffectiveScale(requestedScale, showText, safeWidthPx, safeDensity)
        val baseWidthDp = if (showText) AppConstants.BASE_WIDTH_TEXT else AppConstants.BASE_WIDTH_ICON
        val innerW = (baseWidthDp * effScale * safeDensity).roundToInt().coerceAtLeast(16)
        val innerH = (AppConstants.BASE_HEIGHT * effScale * safeDensity).roundToInt().coerceAtLeast(12)
        val safeInset = computeSafeOuterInsetPx(effScale, safeDensity)
        val totalW = innerW + (safeInset * 2f).roundToInt()
        val totalH = innerH + (safeInset * 2f).roundToInt()

        return computeForCanvasBounds(
            canvasWidthPx = totalW.toFloat(),
            canvasHeightPx = totalH.toFloat(),
            effectiveScale = effScale,
            showText = showText,
            sleekCorners = sleekCorners,
            label = label,
            density = safeDensity,
            measureTextWidth = measureTextWidth
        )
    }

    /**
     * Computes full layout metrics for an actual measured canvas `(canvasWidthPx, canvasHeightPx)`.
     */
    fun computeForCanvasBounds(
        canvasWidthPx: Float,
        canvasHeightPx: Float,
        effectiveScale: Float,
        showText: Boolean,
        sleekCorners: Boolean,
        label: String,
        density: Float,
        measureTextWidth: (text: String, textSizePx: Float) -> Float = { t, sz -> estimateBoldLabelWidthPx(t, sz) }
    ): MicPillRenderMetrics {
        val safeDensity = density.coerceAtLeast(0.5f)
        val safeScale = effectiveScale.coerceAtLeast(0.25f)
        val rawInset = computeSafeOuterInsetPx(safeScale, safeDensity)
        val maxAllowedInset = (min(canvasWidthPx, canvasHeightPx) * 0.22f).coerceAtLeast(1f)
        val safeInset = min(rawInset, maxAllowedInset)

        val strokeW = computeOpticalStrokePx(safeScale, safeDensity)
        val specularW = computeSpecularRimStrokePx(safeDensity)
        val holdRingW = computeHoldRingStrokePx(strokeW, safeDensity)
        val (haloSpread, haloOffsetY) = computeHaloMetricsPx(safeScale, safeDensity)

        val pillLeft = safeInset
        val pillTop = safeInset
        val pillRight = (canvasWidthPx - safeInset).coerceAtLeast(pillLeft + 8f)
        val pillBottom = (canvasHeightPx - safeInset).coerceAtLeast(pillTop + 8f)
        val innerW = pillRight - pillLeft
        val innerH = pillBottom - pillTop

        // Strictly bounded corner radius derived from effectiveScale (never unbounded indicatorScale)
        val cornerRadius = if (sleekCorners) {
            innerH / 2f
        } else {
            min(AppConstants.CORNER_RADIUS_DEFAULT * safeScale * safeDensity, innerH / 2f)
        }
        val specularRadius = (cornerRadius - strokeW / 2f - specularW / 2f).coerceAtLeast(1.0f)

        val innerPadX = (innerH * INNER_PAD_X_RATIO).coerceAtLeast(strokeW + 4f * safeDensity)
        val iconSize = (innerH * ICON_HEIGHT_RATIO).coerceAtLeast(6f)
        val iconGap = (innerH * ICON_TEXT_GAP_RATIO).coerceAtLeast(4f * safeDensity)
        val centerY = pillTop + innerH / 2f

        val iconLeft: Float
        val iconRight: Float
        val iconCenterX: Float
        val maxTextW: Float
        val finalTextSize: Float
        val measuredTextW: Float
        val textStartX: Float
        val textEndX: Float

        if (showText) {
            maxTextW = (innerW - 2f * innerPadX - iconSize - iconGap).coerceAtLeast(8f)
            val desiredSize = (innerH * BASE_TEXT_HEIGHT_RATIO).coerceAtLeast(8f)
            var tSize = desiredSize
            var tWidth = measureTextWidth(label, tSize).coerceAtLeast(0f)
            if (tWidth > maxTextW && tWidth > 0f) {
                val shrink = (maxTextW / tWidth).coerceIn(0.35f, 1.0f)
                tSize = (desiredSize * shrink).coerceAtLeast(MIN_TEXT_SIZE_PX)
                tWidth = measureTextWidth(label, tSize).coerceAtLeast(0f)
                if (tWidth > maxTextW && tWidth > 0f) {
                    tSize = (tSize * (maxTextW / tWidth)).coerceAtLeast(MIN_TEXT_SIZE_PX)
                    tWidth = measureTextWidth(label, tSize).coerceAtLeast(0f)
                }
            }
            finalTextSize = tSize
            measuredTextW = min(tWidth, maxTextW)

            val groupW = iconSize + iconGap + measuredTextW
            val minGroupLeft = pillLeft + innerPadX
            val maxGroupLeft = (pillRight - innerPadX - groupW).coerceAtLeast(minGroupLeft)
            val groupLeft = (pillLeft + (innerW - groupW) / 2f).coerceIn(minGroupLeft, maxGroupLeft)

            iconLeft = groupLeft
            iconRight = iconLeft + iconSize
            iconCenterX = iconLeft + iconSize / 2f
            textStartX = iconRight + iconGap
            textEndX = textStartX + measuredTextW
        } else {
            maxTextW = 0f
            finalTextSize = 0f
            measuredTextW = 0f
            iconCenterX = pillLeft + innerW / 2f
            iconLeft = iconCenterX - iconSize / 2f
            iconRight = iconCenterX + iconSize / 2f
            textStartX = iconRight
            textEndX = iconRight
        }

        return MicPillRenderMetrics(
            effectiveScale = safeScale,
            density = safeDensity,
            showText = showText,
            sleekCorners = sleekCorners,
            label = label,
            safeOuterInsetPx = safeInset,
            innerWidthPx = innerW,
            innerHeightPx = innerH,
            totalViewWidthPx = canvasWidthPx.roundToInt(),
            totalViewHeightPx = canvasHeightPx.roundToInt(),
            pillLeft = pillLeft,
            pillTop = pillTop,
            pillRight = pillRight,
            pillBottom = pillBottom,
            strokeWidthPx = strokeW,
            specularStrokeWidthPx = specularW,
            holdRingStrokeWidthPx = holdRingW,
            haloSpreadPx = haloSpread,
            haloOffsetYPx = haloOffsetY,
            cornerRadiusPx = cornerRadius,
            specularCornerRadiusPx = specularRadius,
            innerPadXPx = innerPadX,
            iconSizePx = iconSize,
            iconLeftPx = iconLeft,
            iconRightPx = iconRight,
            iconCenterXPx = iconCenterX,
            iconCenterYPx = centerY,
            iconTextGapPx = iconGap,
            maxTextWidthPx = maxTextW,
            textSizePx = finalTextSize,
            measuredTextWidthPx = measuredTextW,
            textStartXPx = textStartX,
            textEndXPx = textEndX
        )
    }

    /**
     * +6% top highlight color for subtle high-DPI vertical tonal gradient sheen.
     */
    fun computeTonalTopColor(baseColor: Int): Int {
        val a = (baseColor ushr 24) and 0xFF
        val r = (baseColor ushr 16) and 0xFF
        val g = (baseColor ushr 8) and 0xFF
        val b = baseColor and 0xFF
        val nr = (r + (255 - r) * TONAL_HIGHLIGHT_FRACTION).roundToInt().coerceIn(0, 255)
        val ng = (g + (255 - g) * TONAL_HIGHLIGHT_FRACTION).roundToInt().coerceIn(0, 255)
        val nb = (b + (255 - b) * TONAL_HIGHLIGHT_FRACTION).roundToInt().coerceIn(0, 255)
        return (a shl 24) or (nr shl 16) or (ng shl 8) or nb
    }

    /**
     * -6% bottom depth color for subtle high-DPI vertical tonal gradient sheen.
     */
    fun computeTonalBottomColor(baseColor: Int): Int {
        val a = (baseColor ushr 24) and 0xFF
        val r = (baseColor ushr 16) and 0xFF
        val g = (baseColor ushr 8) and 0xFF
        val b = baseColor and 0xFF
        val factor = 1.0f - TONAL_DEPTH_FRACTION
        val nr = (r * factor).roundToInt().coerceIn(0, 255)
        val ng = (g * factor).roundToInt().coerceIn(0, 255)
        val nb = (b * factor).roundToInt().coerceIn(0, 255)
        return (a shl 24) or (nr shl 16) or (ng shl 8) or nb
    }

    const val AMBER_ALERT_BORDER_ARGB: Int = 0xFFF59E0B.toInt()

    fun formatPillMiniBadgeText(connState: ConnectionUiState, showBadges: Boolean): String {
        if (!showBadges) return ""
        val parts = ArrayList<String>(3)
        if (connState.timerState != "stopped") {
            val rem = connState.timerRemainingSec
            val prefix = if (rem < 0 || connState.timerState == "overtime") "-" else ""
            val absSec = abs(rem)
            val m = absSec / 60
            val s = absSec % 60
            parts.add(String.format(java.util.Locale.US, "%s%02d:%02d", prefix, m, s))
        }
        if (connState.isStandby) parts.add("BRB")
        if (connState.recState == 1) parts.add("REC")
        else if (connState.recState == 2) parts.add("PAUSE")
        return parts.joinToString(" • ")
    }

    fun shouldShowAmberAlertBorder(connState: ConnectionUiState, showBadges: Boolean): Boolean {
        return showBadges && connState.voiceWhileMuted
    }
}
