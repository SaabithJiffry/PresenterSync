package com.saabithjiffry.presentersync.remote.config

import com.saabithjiffry.presentersync.remote.input.BubbleGestureAction
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class RemoteConfigPttMutualExclusionTest {

    @get:Rule
    val tempFolder = TemporaryFolder()

    @Test
    fun enablingPushToTalkClearsLongPressVeryLongPressAndPushToMute() {
        val prev = RemoteConfig(
            enablePushToTalk = false,
            enablePushToMute = true,
            longPressAction = BubbleGestureAction.TOGGLE_MUTE,
            veryLongPressAction = BubbleGestureAction.OPEN_QUICK_MENU
        )

        val next = prev.copy(enablePushToTalk = true)
            .withNormalizedPttMutualExclusion(prev)

        assertTrue(next.enablePushToTalk)
        assertFalse(next.enablePushToMute)
        assertEquals(BubbleGestureAction.NONE, next.longPressAction)
        assertEquals(BubbleGestureAction.NONE, next.veryLongPressAction)
    }

    @Test
    fun selectingLongPressOrVeryLongPressDisablesPushToTalk() {
        val prev = RemoteConfig(
            enablePushToTalk = true,
            enablePushToMute = false,
            longPressAction = BubbleGestureAction.NONE,
            veryLongPressAction = BubbleGestureAction.NONE
        )

        val afterLongPress = prev.copy(longPressAction = BubbleGestureAction.TOGGLE_MUTE)
            .withNormalizedPttMutualExclusion(prev)
        assertFalse(afterLongPress.enablePushToTalk)
        assertEquals(BubbleGestureAction.TOGGLE_MUTE, afterLongPress.longPressAction)

        val afterVeryLongPress = prev.copy(veryLongPressAction = BubbleGestureAction.UNMUTE_ONLY)
            .withNormalizedPttMutualExclusion(prev)
        assertFalse(afterVeryLongPress.enablePushToTalk)
        assertEquals(BubbleGestureAction.UNMUTE_ONLY, afterVeryLongPress.veryLongPressAction)
    }

    @Test
    fun enablingPushToMuteWhilePttActiveDisablesPushToTalk() {
        val prev = RemoteConfig(
            enablePushToTalk = true,
            enablePushToMute = false,
            longPressAction = BubbleGestureAction.NONE,
            veryLongPressAction = BubbleGestureAction.NONE
        )

        val next = prev.copy(enablePushToMute = true)
            .withNormalizedPttMutualExclusion(prev)

        assertTrue(next.enablePushToMute)
        assertFalse(next.enablePushToTalk)
    }
}
