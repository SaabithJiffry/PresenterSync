package com.saabithjiffry.presentersync.remote.ui.overlay

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ScreenBoundsCalculatorTest {

    @Test
    fun defaultBottomRightAnchorStaysWithinLandscapeAndPortraitSafeBounds() {
        val landscapeBounds = SafeRectPx(left = 10, top = 48, right = 1910, bottom = 1016)
        val pt = ScreenBoundsCalculator.resolvePosition(
            savedX = -1,
            savedY = -1,
            bounds = landscapeBounds,
            viewWidthPx = 252,
            viewHeightPx = 60,
            marginXPx = 30,
            marginYPx = 30
        )
        assertEquals(1910 - 252 - 30, pt.x)
        assertEquals(1016 - 60 - 30, pt.y)
    }

    @Test
    fun clampsSavedLandscapeCoordinatesWhenRotatedToPortraitWithTaskbarInsets() {
        val portraitBounds = SafeRectPx(left = 8, top = 64, right = 1072, bottom = 1820)
        val clamped = ScreenBoundsCalculator.resolvePosition(
            savedX = 1800,
            savedY = 950,
            bounds = portraitBounds,
            viewWidthPx = 252,
            viewHeightPx = 60,
            marginXPx = 30,
            marginYPx = 30
        )
        assertEquals(1072 - 252, clamped.x)
        assertEquals(950, clamped.y)
        assertTrue(clamped.x >= portraitBounds.left)
        assertTrue(clamped.y in portraitBounds.top..(portraitBounds.bottom - 60))
    }

    @Test
    fun clampsNegativeOffscreenOrTopCutoutViolationInsideSafeRect() {
        val bounds = SafeRectPx(left = 24, top = 80, right = 3816, bottom = 2080)
        val clamped = ScreenBoundsCalculator.resolvePosition(
            savedX = 2,
            savedY = 10,
            bounds = bounds,
            viewWidthPx = 600,
            viewHeightPx = 200,
            marginXPx = 40,
            marginYPx = 40
        )
        assertEquals(24, clamped.x)
        assertEquals(80, clamped.y)
    }
}
