package com.saabithjiffry.presentersync.remote.ui.overlay

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ScreenBoundsCalculatorTest {

    private val bounds = SafeRectPx(left = 20, top = 40, right = 1900, bottom = 1040)

    @Test
    fun snapsWithinThresholdToEdgesAndCenters() {
        // Near top-left edge (within 14px)
        val tl = ScreenBoundsCalculator.computeMagneticSnap(
            rawX = 28,
            rawY = 50,
            viewWidthPx = 200,
            viewHeightPx = 80,
            bounds = bounds,
            thresholdPx = 14
        )
        assertEquals(20, tl.x)
        assertEquals(40, tl.y)
        assertTrue(tl.snappedX)
        assertTrue(tl.snappedY)

        // Near horizontal center (minX=20, maxX=1700 -> centerX=860)
        val mid = ScreenBoundsCalculator.computeMagneticSnap(
            rawX = 852,
            rawY = 512, // centerY = (40 + 960)/2 = 500
            viewWidthPx = 200,
            viewHeightPx = 80,
            bounds = bounds,
            thresholdPx = 14
        )
        assertEquals(860, mid.x)
        assertEquals(500, mid.y)
        assertTrue(mid.snappedX)
        assertTrue(mid.snappedY)

        // Outside threshold leaves clamped coordinates untouched
        val free = ScreenBoundsCalculator.computeMagneticSnap(
            rawX = 300,
            rawY = 300,
            viewWidthPx = 200,
            viewHeightPx = 80,
            bounds = bounds,
            thresholdPx = 14
        )
        assertEquals(300, free.x)
        assertEquals(300, free.y)
        assertFalse(free.snappedX)
        assertFalse(free.snappedY)
    }

    @Test
    fun ratioPreservesCornerAcrossPhonePortraitAndLandscapeRotation() {
        val portraitBounds = SafeRectPx(left = 10, top = 60, right = 710, bottom = 1540)
        val landscapeBounds = SafeRectPx(left = 60, top = 10, right = 1540, bottom = 710)
        val pillW = 160
        val pillH = 80

        // Dock pill at bottom-right in portrait
        val (rx, ry) = ScreenBoundsCalculator.computePositionRatios(
            x = portraitBounds.right - pillW,
            y = portraitBounds.bottom - pillH,
            bounds = portraitBounds,
            viewWidthPx = pillW,
            viewHeightPx = pillH
        )
        assertEquals(1.0f, rx, 0.001f)
        assertEquals(1.0f, ry, 0.001f)

        // Resolve on rotated landscape phone
        val rotatedPos = ScreenBoundsCalculator.resolvePosition(
            savedX = portraitBounds.right - pillW,
            savedY = portraitBounds.bottom - pillH,
            bounds = landscapeBounds,
            viewWidthPx = pillW,
            viewHeightPx = pillH,
            marginXPx = 20,
            marginYPx = 20,
            savedXRatio = rx,
            savedYRatio = ry
        )
        assertEquals(landscapeBounds.right - pillW, rotatedPos.x)
        assertEquals(landscapeBounds.bottom - pillH, rotatedPos.y)
    }

    @Test
    fun zeroMarginCornerDockAndPixelReadoutWorkOnAllCorners() {
        val b = SafeRectPx(left = 0, top = 0, right = 1920, bottom = 1080)
        assertEquals(OverlayPointPx(0, 0), ScreenBoundsCalculator.computeZeroMarginCornerDock("TL", 120, 40, b))
        assertEquals(OverlayPointPx(1800, 0), ScreenBoundsCalculator.computeZeroMarginCornerDock("TR", 120, 40, b))
        assertEquals(OverlayPointPx(0, 1040), ScreenBoundsCalculator.computeZeroMarginCornerDock("BL", 120, 40, b))
        assertEquals(OverlayPointPx(1800, 1040), ScreenBoundsCalculator.computeZeroMarginCornerDock("BR", 120, 40, b))
        assertEquals("120×40 px @ (1800, 1040)", ScreenBoundsCalculator.formatPixelReadout(1800, 1040, 120, 40))
    }

    @Test
    fun oppositeCornerFlipAndPalmDetectionWorkForSmartBoard() {
        val b = SafeRectPx(left = 0, top = 0, right = 1920, bottom = 1080)
        assertEquals(OverlayPointPx(1800, 1040), ScreenBoundsCalculator.computeOppositeCornerFlip(10, 10, 120, 40, b))
        assertEquals(OverlayPointPx(0, 0), ScreenBoundsCalculator.computeOppositeCornerFlip(1800, 1040, 120, 40, b))
        assertTrue(ScreenBoundsCalculator.isPalmTouch(5, 10f))
        assertTrue(ScreenBoundsCalculator.isPalmTouch(android.view.MotionEvent.TOOL_TYPE_FINGER, 95f, 85f))
        assertFalse(ScreenBoundsCalculator.isPalmTouch(android.view.MotionEvent.TOOL_TYPE_STYLUS, 12f, 85f))
    }

    @Test
    fun boundedPillScalePreventsOverflowOnNarrowPhonesAndAllows5xOnSmartBoard() {
        // Galaxy A07 portrait: 720px @ 2.0x density = 360dp; 168dp * 5.0x would exceed viewport
        val phoneBounded = ScreenBoundsCalculator.computeBoundedPillScale(
            requestedScale = 5.0f,
            showText = true,
            safeWidthPx = 700,
            density = 2.0f
        )
        assertTrue("Expected phone scale clamped < 2.5x, was $phoneBounded", phoneBounded < 2.5f)
        assertTrue(168f * phoneBounded * 2.0f <= 700f)

        // 65" Smart Board: 1920px @ 1.5x density supports full 5.0x pill cleanly
        val boardScale = ScreenBoundsCalculator.computeBoundedPillScale(
            requestedScale = 5.0f,
            showText = true,
            safeWidthPx = 1900,
            density = 1.5f
        )
        assertEquals(5.0f, boardScale, 0.001f)
    }
}
