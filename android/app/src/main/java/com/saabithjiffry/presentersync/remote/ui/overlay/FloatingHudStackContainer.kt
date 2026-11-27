package com.saabithjiffry.presentersync.remote.ui.overlay

import android.content.Context
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import kotlin.math.roundToInt

data class FloatingHudStackGeometry(
    val totalWidthPx: Int,
    val totalHeightPx: Int,
    val sceneAboveMic: Boolean,
    val gapPx: Int,
    val micOffsetX: Int,
    val micOffsetY: Int,
    val sceneOffsetX: Int,
    val sceneOffsetY: Int,
    val x: Int,
    val y: Int
)

object FloatingHudStackLayout {
    const val DEFAULT_GAP_DP = 6f
    const val TOP_FLIP_FRACTION = 0.18f

    fun computeLayout(
        micW: Int,
        micH: Int,
        sceneW: Int,
        sceneH: Int,
        showScene: Boolean,
        gapPx: Int,
        bounds: SafeRectPx,
        anchorX: Int,
        anchorY: Int
    ): FloatingHudStackGeometry {
        val safeGap = if (showScene) gapPx.coerceAtLeast(0) else 0
        val totalW = if (showScene) maxOf(micW, sceneW) else micW
        val totalH = if (showScene) micH + safeGap + sceneH else micH
        val clampedX = anchorX.coerceIn(bounds.left, (bounds.right - totalW).coerceAtLeast(bounds.left))
        val clampedY = anchorY.coerceIn(bounds.top, (bounds.bottom - totalH).coerceAtLeast(bounds.top))
        val topFlipLimitY = bounds.top + (bounds.height * TOP_FLIP_FRACTION).roundToInt()
        val sceneAbove = showScene && (clampedY > topFlipLimitY)
        val micOffsetX = ((totalW - micW) / 2).coerceAtLeast(0)
        val sceneOffsetX = ((totalW - sceneW) / 2).coerceAtLeast(0)
        val (sceneOffsetY, micOffsetY) = if (!showScene) {
            0 to 0
        } else if (sceneAbove) {
            0 to (sceneH + safeGap)
        } else {
            (micH + safeGap) to 0
        }
        return FloatingHudStackGeometry(
            totalWidthPx = totalW,
            totalHeightPx = totalH,
            sceneAboveMic = sceneAbove,
            gapPx = safeGap,
            micOffsetX = micOffsetX,
            micOffsetY = micOffsetY,
            sceneOffsetX = sceneOffsetX,
            sceneOffsetY = sceneOffsetY,
            x = clampedX,
            y = clampedY
        )
    }
}

internal class FloatingHudStackContainer(
    context: Context,
    val micView: MicPillCanvasView,
    val sceneView: ScenePillCanvasView
) : LinearLayout(context) {

    private val spacerView = View(context)
    private var lastSceneAbove: Boolean? = null
    private var lastShowScene: Boolean? = null

    init {
        orientation = VERTICAL
        gravity = Gravity.CENTER_HORIZONTAL
        clipChildren = false
        clipToPadding = false
    }

    fun applyArrangement(
        showScene: Boolean,
        sceneAboveMic: Boolean,
        gapPx: Int,
        micW: Int,
        micH: Int,
        sceneW: Int,
        sceneH: Int
    ) {
        if (lastShowScene != showScene || lastSceneAbove != sceneAboveMic || childCount == 0) {
            removeAllViews()
            if (showScene) {
                if (sceneAboveMic) {
                    addView(sceneView, LayoutParams(sceneW, sceneH))
                    addView(spacerView, LayoutParams(1, gapPx))
                    addView(micView, LayoutParams(micW, micH))
                } else {
                    addView(micView, LayoutParams(micW, micH))
                    addView(spacerView, LayoutParams(1, gapPx))
                    addView(sceneView, LayoutParams(sceneW, sceneH))
                }
            } else {
                addView(micView, LayoutParams(micW, micH))
            }
            lastShowScene = showScene
            lastSceneAbove = sceneAboveMic
        } else {
            (micView.layoutParams as? LayoutParams)?.let { lp ->
                if (lp.width != micW || lp.height != micH) {
                    lp.width = micW
                    lp.height = micH
                    micView.layoutParams = lp
                }
            }
            if (showScene) {
                (sceneView.layoutParams as? LayoutParams)?.let { lp ->
                    if (lp.width != sceneW || lp.height != sceneH) {
                        lp.width = sceneW
                        lp.height = sceneH
                        sceneView.layoutParams = lp
                    }
                }
                (spacerView.layoutParams as? LayoutParams)?.let { lp ->
                    if (lp.height != gapPx) {
                        lp.height = gapPx
                        spacerView.layoutParams = lp
                    }
                }
            }
        }
        sceneView.visibility = if (showScene) View.VISIBLE else View.GONE
        spacerView.visibility = if (showScene) View.VISIBLE else View.GONE
    }
}
