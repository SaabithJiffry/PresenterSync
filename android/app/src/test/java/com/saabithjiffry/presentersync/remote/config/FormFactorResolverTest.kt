package com.saabithjiffry.presentersync.remote.config

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FormFactorResolverTest {

    @Test
    fun classifies65InchSmartBoardPortraitAndLandscapeProperly() {
        // 65" 1080p Smart Board @ 240dpi = 1280dp x 720dp (sw = 720dp)
        val board = FormFactorResolver.resolve(
            mode = DeviceProfileMode.AUTO,
            widthDp = 1280,
            heightDp = 720,
            smallestWidthDp = 720
        )
        assertEquals(FormFactorClass.LARGE_BOARD, board.deviceClass)
        assertTrue(board.isLargeBoard)
        assertTrue(board.isWideTwoColumn)
        assertFalse(board.isPhone)
        assertFalse(board.isTightWidth)
        assertEquals(2.0f, board.recommendedScale, 0.001f)
    }

    @Test
    fun classifiesGalaxyA07AndPocoM3AsPhonesInPortraitAndLandscape() {
        // Samsung Galaxy A07 (720x1600 @ xhdpi 320dpi -> 360x800dp)
        val a07Portrait = FormFactorResolver.resolve(
            mode = DeviceProfileMode.AUTO,
            widthDp = 360,
            heightDp = 800,
            smallestWidthDp = 360
        )
        assertEquals(FormFactorClass.COMPACT_PHONE, a07Portrait.deviceClass)
        assertTrue(a07Portrait.isPhone)
        assertTrue(a07Portrait.isTightWidth)
        assertFalse(a07Portrait.isWideTwoColumn)
        assertEquals(1.0f, a07Portrait.recommendedScale, 0.001f)

        // Galaxy A07 rotated to landscape (800x360dp, sw stays 360dp)
        val a07Land = FormFactorResolver.resolve(
            mode = DeviceProfileMode.AUTO,
            widthDp = 800,
            heightDp = 360,
            smallestWidthDp = 360
        )
        assertEquals(FormFactorClass.COMPACT_PHONE, a07Land.deviceClass)
        assertTrue(a07Land.isPhone)
        assertTrue(a07Land.isCompactHeight)
        assertFalse(a07Land.isWideTwoColumn)

        // Xiaomi Poco M3 / Redmi Note 12 (1080x2400 @ 440dpi -> 392x872dp)
        val redmiPortrait = FormFactorResolver.resolve(
            mode = FormFactorModeHelper.auto,
            widthDp = 392,
            heightDp = 872,
            smallestWidthDp = 392
        )
        assertEquals(FormFactorClass.COMPACT_PHONE, redmiPortrait.deviceClass)
        assertTrue(redmiPortrait.isTightWidth)
    }

    @Test
    fun manualOverrideTakesPrecedence() {
        val forcedBoard = FormFactorResolver.resolve(
            mode = DeviceProfileMode.SMART_BOARD,
            widthDp = 360,
            heightDp = 800,
            smallestWidthDp = 360
        )
        assertEquals(FormFactorClass.LARGE_BOARD, forcedBoard.deviceClass)
        assertTrue(forcedBoard.isLargeBoard)
    }
}

private object FormFactorModeHelper {
    val auto = DeviceProfileMode.AUTO
}
