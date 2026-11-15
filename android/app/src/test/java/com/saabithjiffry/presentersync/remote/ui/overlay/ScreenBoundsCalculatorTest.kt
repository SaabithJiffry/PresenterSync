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
}
