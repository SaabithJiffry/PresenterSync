package com.saabithjiffry.presentersync.remote.ui.overlay

import android.content.Context
import android.hardware.display.DisplayManager
import android.os.Build
import android.view.WindowInsets
import android.view.WindowManager
import com.saabithjiffry.presentersync.remote.config.AppConstants
import com.saabithjiffry.presentersync.remote.config.DeviceProfileMode
import com.saabithjiffry.presentersync.remote.config.FormFactorClass
import com.saabithjiffry.presentersync.remote.config.FormFactorResolver
import com.saabithjiffry.presentersync.remote.config.ResolvedFormFactor
import kotlin.math.roundToInt

data class SafeRectPx(
    val left: Int,
    val top: Int,
    val right: Int,
    val bottom: Int
) {
    val width: Int get() = (right - left).coerceAtLeast(0)
    val height: Int get() = (bottom - top).coerceAtLeast(0)
}

data class OverlayPointPx(
    val x: Int,
    val y: Int
)

data class MagneticSnapResult(
    val x: Int,
    val y: Int,
    val snappedX: Boolean,
    val snappedY: Boolean
)

object ScreenBoundsCalculator {

    fun computeMagneticSnap(
        rawX: Int,
        rawY: Int,
        viewWidthPx: Int,
        viewHeightPx: Int,
        bounds: SafeRectPx,
        thresholdPx: Int
    ): MagneticSnapResult {
        val minX = bounds.left
        val maxX = (bounds.right - viewWidthPx).coerceAtLeast(minX)
        val minY = bounds.top
        val maxY = (bounds.bottom - viewHeightPx).coerceAtLeast(minY)

        val clampedX = rawX.coerceIn(minX, maxX)
        val clampedY = rawY.coerceIn(minY, maxY)

        val centerX = (minX + maxX) / 2
        val centerY = (minY + maxY) / 2
        val xTargets = listOf(minX, centerX, maxX)
        val yTargets = listOf(minY, centerY, maxY)

        var bestX = clampedX
        var bestDx = thresholdPx + 1
        var snappedX = false
        for (tx in xTargets) {
            val dx = kotlin.math.abs(tx - clampedX)
            if (dx <= thresholdPx && dx < bestDx) {
                bestDx = dx
                bestX = tx
                snappedX = true
            }
        }

        var bestY = clampedY
        var bestDy = thresholdPx + 1
        var snappedY = false
        for (ty in yTargets) {
            val dy = kotlin.math.abs(ty - clampedY)
            if (dy <= thresholdPx && dy < bestDy) {
                bestDy = dy
                bestY = ty
                snappedY = true
            }
        }

        return MagneticSnapResult(
            x = bestX.coerceIn(minX, maxX),
            y = bestY.coerceIn(minY, maxY),
            snappedX = snappedX,
            snappedY = snappedY
        )
    }

    fun computeDefaultPosition(
        bounds: SafeRectPx,
        viewWidthPx: Int,
        viewHeightPx: Int,
        marginXPx: Int,
        marginYPx: Int
    ): OverlayPointPx {
        val minX = bounds.left
        val maxX = (bounds.right - viewWidthPx).coerceAtLeast(minX)
        val minY = bounds.top
        val maxY = (bounds.bottom - viewHeightPx).coerceAtLeast(minY)
        val x = (bounds.right - viewWidthPx - marginXPx).coerceIn(minX, maxX)
        val y = (bounds.bottom - viewHeightPx - marginYPx).coerceIn(minY, maxY)
        return OverlayPointPx(x, y)
    }

    fun computePositionRatios(
        x: Int,
        y: Int,
        bounds: SafeRectPx,
        viewWidthPx: Int,
        viewHeightPx: Int
    ): Pair<Float, Float> {
        val minX = bounds.left
        val maxX = (bounds.right - viewWidthPx).coerceAtLeast(minX)
        val minY = bounds.top
        val maxY = (bounds.bottom - viewHeightPx).coerceAtLeast(minY)
        val spanX = (maxX - minX).coerceAtLeast(1)
        val spanY = (maxY - minY).coerceAtLeast(1)
        val rx = ((x.coerceIn(minX, maxX) - minX).toFloat() / spanX.toFloat()).coerceIn(0f, 1f)
        val ry = ((y.coerceIn(minY, maxY) - minY).toFloat() / spanY.toFloat()).coerceIn(0f, 1f)
        return rx to ry
    }

    fun computeBoundedPillScale(
        requestedScale: Float,
        showText: Boolean,
        safeWidthPx: Int,
        density: Float
    ): Float {
        val baseWidthDp = if (showText) AppConstants.BASE_WIDTH_TEXT else AppConstants.BASE_WIDTH_ICON
        val safeDensity = density.coerceAtLeast(0.5f)
        val maxWidthPx = (safeWidthPx * AppConstants.PILL_MAX_VIEWPORT_WIDTH_FRACTION).coerceAtLeast(16f)
        val maxScale = (maxWidthPx / (baseWidthDp * safeDensity)).coerceAtLeast(0.25f)
        return requestedScale.coerceIn(0.25f, maxScale)
    }

    fun resolvePosition(
        savedX: Int,
        savedY: Int,
        bounds: SafeRectPx,
        viewWidthPx: Int,
        viewHeightPx: Int,
        marginXPx: Int,
        marginYPx: Int,
        savedXRatio: Float = -1f,
        savedYRatio: Float = -1f
    ): OverlayPointPx {
        val minX = bounds.left
        val maxX = (bounds.right - viewWidthPx).coerceAtLeast(minX)
        val minY = bounds.top
        val maxY = (bounds.bottom - viewHeightPx).coerceAtLeast(minY)

        if (savedXRatio in 0f..1f && savedYRatio in 0f..1f) {
            val mappedX = minX + ((maxX - minX) * savedXRatio).roundToInt()
            val mappedY = minY + ((maxY - minY) * savedYRatio).roundToInt()
            return OverlayPointPx(
                x = mappedX.coerceIn(minX, maxX),
                y = mappedY.coerceIn(minY, maxY)
            )
        }

        if (savedX < 0 || savedY < 0) {
            return computeDefaultPosition(bounds, viewWidthPx, viewHeightPx, marginXPx, marginYPx)
        }
        return OverlayPointPx(
            x = savedX.coerceIn(minX, maxX),
            y = savedY.coerceIn(minY, maxY)
        )
    }

    fun getSafeBoundsPx(context: Context, windowManager: WindowManager): SafeRectPx {
        val density = context.resources.displayMetrics.density
        val pad = (AppConstants.SCREEN_MIN_PAD * density).roundToInt()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val metrics = windowManager.currentWindowMetrics
            val b = metrics.bounds
            val insets = metrics.windowInsets.getInsetsIgnoringVisibility(
                WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout()
            )
            val left = b.left + insets.left.coerceAtLeast(pad / 2)
            val top = b.top + insets.top.coerceAtLeast(pad / 2)
            val right = (b.right - insets.right.coerceAtLeast(pad / 2)).coerceAtLeast(left + 1)
            val bottom = (b.bottom - insets.bottom.coerceAtLeast(pad / 2)).coerceAtLeast(top + 1)
            return SafeRectPx(left = left, top = top, right = right, bottom = bottom)
        }

        val dm = context.resources.displayMetrics
        return SafeRectPx(
            left = pad / 2,
            top = pad / 2,
            right = (dm.widthPixels - pad / 2).coerceAtLeast(1),
            bottom = (dm.heightPixels - pad / 2).coerceAtLeast(1)
        )
    }

    fun computeZeroMarginCornerDock(
        corner: String,
        viewWidthPx: Int,
        viewHeightPx: Int,
        bounds: SafeRectPx
    ): OverlayPointPx {
        val minX = bounds.left
        val maxX = (bounds.right - viewWidthPx).coerceAtLeast(minX)
        val minY = bounds.top
        val maxY = (bounds.bottom - viewHeightPx).coerceAtLeast(minY)
        return when (corner.trim().uppercase()) {
            "TL" -> OverlayPointPx(minX, minY)
            "TR" -> OverlayPointPx(maxX, minY)
            "BL" -> OverlayPointPx(minX, maxY)
            else -> OverlayPointPx(maxX, maxY)
        }
    }

    fun formatPixelReadout(x: Int, y: Int, widthPx: Int, heightPx: Int): String =
        "${widthPx}×${heightPx} px @ ($x, $y)"

    fun computeOppositeCornerFlip(
        currentX: Int,
        currentY: Int,
        viewWidthPx: Int,
        viewHeightPx: Int,
        bounds: SafeRectPx
    ): OverlayPointPx {
        val midX = (bounds.left + bounds.right - viewWidthPx) / 2
        val midY = (bounds.top + bounds.bottom - viewHeightPx) / 2
        val isLeft = currentX <= midX
        val isTop = currentY <= midY
        val targetCorner = when {
            isLeft && isTop -> "BR"
            !isLeft && isTop -> "BL"
            isLeft && !isTop -> "TR"
            else -> "TL"
        }
        return computeZeroMarginCornerDock(targetCorner, viewWidthPx, viewHeightPx, bounds)
    }

    fun isPalmTouch(toolType: Int, touchMajorPx: Float, thresholdPx: Float = 85f): Boolean {
        if (toolType == 5) return true // MotionEvent.TOOL_TYPE_PALM
        return touchMajorPx > thresholdPx
    }

    fun isPalmTouchForDevice(
        toolType: Int,
        touchMajorPx: Float,
        density: Float,
        formFactor: FormFactorClass
    ): Boolean {
        if (toolType == 5) return true // MotionEvent.TOOL_TYPE_PALM
        if (formFactor == FormFactorClass.COMPACT_PHONE) return false
        val thresholdPx = maxOf(160f * density, 240f)
        return touchMajorPx > thresholdPx
    }

    fun resolveFormFactor(context: Context, mode: DeviceProfileMode): ResolvedFormFactor {
        val dm = context.resources.displayMetrics
        val density = dm.density.coerceAtLeast(0.75f)
        val widthDp = (dm.widthPixels / density).roundToInt()
        val heightDp = (dm.heightPixels / density).roundToInt()
        val swDp = minOf(widthDp, heightDp)
        return FormFactorResolver.resolve(mode = mode, widthDp = widthDp, heightDp = heightDp, smallestWidthDp = swDp)
    }

    fun getDisplayCount(context: Context): Int {
        val dm = context.getSystemService(Context.DISPLAY_SERVICE) as? DisplayManager ?: return 1
        return dm.displays.size.coerceAtLeast(1)
    }

    fun hasExternalDisplay(context: Context): Boolean = getDisplayCount(context) > 1
}
