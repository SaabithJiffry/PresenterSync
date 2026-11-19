package com.saabithjiffry.presentersync.remote

import com.saabithjiffry.presentersync.remote.config.AppConstants
import com.saabithjiffry.presentersync.remote.ui.overlay.MicPillMetricsCalculator
import com.saabithjiffry.presentersync.remote.ui.overlay.MicVectorSpec24
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs
import kotlin.math.min

class MicPillRenderingMetricsTest {

    private val scales = listOf(0.75f, 1.0f, 2.0f, 3.0f, 5.0f)
    private val labels = listOf("LIVE", "MUTED", "AUTH ERR", "OFFLINE")
    private val densities = listOf(1.5f, 2.0f, 3.0f)

    @Test
    fun opticalBorderStrokeIsSubLinearAndCappedAt3dpAcrossAllScalesAndDensities() {
        for (density in densities) {
            var prevStroke = 0f
            for (scale in scales + listOf(8.0f)) {
                val strokePx = MicPillMetricsCalculator.computeOpticalStrokePx(scale, density)
                val maxAllowedPx = 3.0f * density
                assertTrue(
                    "Stroke $strokePx px must be >= 1px at scale=$scale density=$density",
                    strokePx >= 1.0f
                )
                assertTrue(
                    "Stroke $strokePx px exceeded 3.0dp cap ($maxAllowedPx px) at scale=$scale density=$density",
                    strokePx <= maxAllowedPx + 0.001f
                )
                assertTrue(
                    "Stroke must be monotonically non-decreasing with scale",
                    strokePx >= prevStroke - 0.001f
                )
                prevStroke = strokePx

                // Specular rim stays crisp between 1px and 1.5dp
                val specularPx = MicPillMetricsCalculator.computeSpecularRimStrokePx(density)
                assertTrue(specularPx >= 1.0f && specularPx <= 1.5f * density + 0.001f)
            }
            // Verify 5.0x is dramatically slimmer than old naive 1.5dp * 5.0 = 7.5dp border
            val stroke5xDp = MicPillMetricsCalculator.computeOpticalStrokePx(5.0f, density) / density
            assertTrue("5.0x stroke ($stroke5xDp dp) must remain <= 3.0dp", stroke5xDp <= 3.0f)
        }
    }

    @Test
    fun safeOuterInsetsPreventHaloAndHoldRingClippingAtAllScales() {
        // 4K / 1080p Smart Board viewport
        val smartBoardSafeWidth = 3840
        for (density in densities) {
            for (scale in scales) {
                for (showText in listOf(true, false)) {
                    val m = MicPillMetricsCalculator.computeForTargetSize(
                        requestedScale = scale,
                        showText = showText,
                        sleekCorners = false,
                        label = "MUTED",
                        safeWidthPx = smartBoardSafeWidth,
                        density = density
                    )
                    // Hold progress ring stays strictly inside [0, totalW] x [0, totalH]
                    val halfHold = m.holdRingStrokeWidthPx / 2f
                    assertTrue(
                        "Hold ring clips left at scale=$scale density=$density",
                        m.pillLeft - halfHold >= 0f
                    )
                    assertTrue(
                        "Hold ring clips top at scale=$scale density=$density",
                        m.pillTop - halfHold >= 0f
                    )
                    assertTrue(
                        "Hold ring clips right at scale=$scale density=$density",
                        m.pillRight + halfHold <= m.totalViewWidthPx.toFloat() + 0.5f
                    )
                    assertTrue(
                        "Hold ring clips bottom at scale=$scale density=$density",
                        m.pillBottom + halfHold <= m.totalViewHeightPx.toFloat() + 0.5f
                    )

                    // Outer elevation halo stays strictly inside safe outer inset padding
                    assertTrue(
                        "Halo spread + offset exceeds safeOuterInsetPx at scale=$scale",
                        m.haloSpreadPx + m.haloOffsetYPx <= m.safeOuterInsetPx + 0.001f
                    )
                    assertTrue(
                        "Total view width must stay within viewport",
                        m.totalViewWidthPx <= smartBoardSafeWidth
                    )
                }
            }
        }
    }

    @Test
    fun cornerRadiusUsesBoundedEffectiveScaleNeverUnboundedIndicatorScale() {
        // Narrow phone (720px @ 2.0x density): requesting 5.0x gets bounded well below 5.0x
        val narrowPhoneWidth = 700
        val density = 2.0f
        val m = MicPillMetricsCalculator.computeForTargetSize(
            requestedScale = 5.0f,
            showText = true,
            sleekCorners = false,
            label = "LIVE",
            safeWidthPx = narrowPhoneWidth,
            density = density
        )
        assertTrue("Scale must be bounded on narrow phone", m.effectiveScale < 2.5f)
        val expectedRadius = min(AppConstants.CORNER_RADIUS_DEFAULT * m.effectiveScale * density, m.innerHeightPx / 2f)
        assertEquals(expectedRadius, m.cornerRadiusPx, 0.01f)
        // Old bug used requestedScale (5.0x * 8dp = 40dp * 2 = 80px) which collapsed non-sleek to capsule (innerH/2)
        assertTrue(
            "Non-sleek cornerRadius (${m.cornerRadiusPx}) must remain strictly smaller than capsule radius (${m.innerHeightPx / 2f})",
            m.cornerRadiusPx < m.innerHeightPx / 2f
        )

        // Sleek capsule mode always equals innerHeightPx / 2f
        val sleek = MicPillMetricsCalculator.computeForTargetSize(
            requestedScale = 5.0f,
            showText = true,
            sleekCorners = true,
            label = "LIVE",
            safeWidthPx = narrowPhoneWidth,
            density = density
        )
        assertEquals(sleek.innerHeightPx / 2f, sleek.cornerRadiusPx, 0.01f)
    }

    @Test
    fun iconTextNonOverlapAutoFitContainmentAndOpticalCenteringAcrossScalesAndLabels() {
        val smartBoardSafeWidth = 3840
        val density = 2.0f
        for (scale in scales) {
            for (label in labels) {
                val m = MicPillMetricsCalculator.computeForTargetSize(
                    requestedScale = scale,
                    showText = true,
                    sleekCorners = false,
                    label = label,
                    safeWidthPx = smartBoardSafeWidth,
                    density = density
                )
                // 1. Icon and text must never overlap and must maintain positive optical gap
                val actualGap = m.textStartXPx - m.iconRightPx
                assertTrue(
                    "Icon and text overlapped for '$label' at ${scale}x (gap=$actualGap)",
                    actualGap >= m.iconTextGapPx - 0.01f && actualGap > 0f
                )

                // 2. Auto-fit width containment: zero clipping on left or right
                assertTrue(
                    "Text width (${m.measuredTextWidthPx}) exceeded maxTextWidth (${m.maxTextWidthPx}) for '$label' at ${scale}x",
                    m.measuredTextWidthPx <= m.maxTextWidthPx + 0.01f
                )
                assertTrue(
                    "Icon clips left inner padding for '$label' at ${scale}x",
                    m.iconLeftPx >= m.pillLeft + m.innerPadXPx - 0.01f
                )
                assertTrue(
                    "Label clips right inner padding for '$label' at ${scale}x",
                    m.textEndXPx <= m.pillRight - m.innerPadXPx + 0.01f
                )

                // 3. Optical horizontal centering of [icon + gap + label] group
                val centeringDelta = abs(m.leftContentMarginPx - m.rightContentMarginPx)
                assertTrue(
                    "Optical centering drift ($centeringDelta px) too large for '$label' at ${scale}x",
                    centeringDelta <= 1.0f
                )
            }
        }
    }

    @Test
    fun iconOnlyModeCentersMicrophoneOpticallyAndAutoFitShrinksLongLabels() {
        val iconOnly = MicPillMetricsCalculator.computeForTargetSize(
            requestedScale = 3.0f,
            showText = false,
            sleekCorners = true,
            label = "LIVE",
            safeWidthPx = 1920,
            density = 1.5f
        )
        val expectedCenterX = iconOnly.pillLeft + iconOnly.innerWidthPx / 2f
        assertEquals(expectedCenterX, iconOnly.iconCenterXPx, 0.01f)
        assertEquals(iconOnly.leftContentMarginPx, iconOnly.rightContentMarginPx, 0.01f)

        // Compare LIVE vs AUTH ERR at identical 3.0x scale: AUTH ERR auto-fits without exceeding maxTextWidthPx
        val liveM = MicPillMetricsCalculator.computeForTargetSize(3.0f, true, false, "LIVE", 1920, 1.5f)
        val authErrM = MicPillMetricsCalculator.computeForTargetSize(3.0f, true, false, "AUTH ERR", 1920, 1.5f)
        assertTrue(authErrM.textSizePx <= liveM.textSizePx)
        assertTrue(authErrM.measuredTextWidthPx <= authErrM.maxTextWidthPx + 0.01f)
    }

    @Test
    fun tonalGradientSheenAndVectorSpecInvariantsHold() {
        val baseGreen = 0xFF22C55E.toInt()
        val topColor = MicPillMetricsCalculator.computeTonalTopColor(baseGreen)
        val bottomColor = MicPillMetricsCalculator.computeTonalBottomColor(baseGreen)

        // Alpha channel preserved
        assertEquals(0xFF, (topColor ushr 24) and 0xFF)
        assertEquals(0xFF, (bottomColor ushr 24) and 0xFF)

        // Top highlight strictly lighter, bottom depth strictly darker
        val baseG = (baseGreen ushr 8) and 0xFF
        val topG = (topColor ushr 8) and 0xFF
        val botG = (bottomColor ushr 8) and 0xFF
        assertTrue("Top highlight ($topG) must exceed base ($baseG)", topG > baseG)
        assertTrue("Bottom depth ($botG) must be darker than base ($baseG)", botG < baseG)

        // 24x24 vector mic proportions and dual-pass knockout multiplier
        assertEquals(24f, MicVectorSpec24.VIEWPORT_SIZE, 0.001f)
        assertEquals(12f, (MicVectorSpec24.CAPSULE_LEFT + MicVectorSpec24.CAPSULE_RIGHT) / 2f, 0.001f)
        assertEquals(12f, (MicVectorSpec24.CRADLE_LEFT + MicVectorSpec24.CRADLE_RIGHT) / 2f, 0.001f)
        assertTrue(MicVectorSpec24.SLASH_MASK_MULTIPLIER >= 2.0f)
    }
}
