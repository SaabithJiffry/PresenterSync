package com.saabithjiffry.presentersync.remote.ui.overlay

import android.content.Context
import android.os.Build
import android.view.WindowInsets
import android.view.WindowManager
import com.saabithjiffry.presentersync.remote.config.AppConstants
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

    fun resolvePosition(
        savedX: Int,
        savedY: Int,
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
}
