package com.saabithjiffry.presentersync.remote

import com.saabithjiffry.presentersync.remote.config.RemoteConfig
import com.saabithjiffry.presentersync.remote.input.BubbleGestureAction
import com.saabithjiffry.presentersync.remote.network.ConnectionUiState
import com.saabithjiffry.presentersync.remote.ui.overlay.MicPillMetricsCalculator
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class QuickMenuAndMiniBadgesTest {

    @Test
    fun transitionSceneAction_roundTripsByKeyAndLabel() {
        val action = BubbleGestureAction.TRANSITION_SCENE
        assertEquals("transition_scene", action.rawValue)
        assertEquals("OBS Transition", action.label)
        assertEquals(action, BubbleGestureAction.fromRaw("transition_scene"))
    }

    @Test
    fun formatPillMiniBadgeText_formatsTimerBrbRecAndRespectsToggle() {
        val countdown = ConnectionUiState(timerState = "running", timerRemainingSec = 120)
        assertEquals("02:00", MicPillMetricsCalculator.formatPillMiniBadgeText(countdown, true))

        val overtime = ConnectionUiState(timerState = "overtime", timerRemainingSec = -15)
        assertEquals("-00:15", MicPillMetricsCalculator.formatPillMiniBadgeText(overtime, true))

        val brbRec = ConnectionUiState(timerState = "stopped", isStandby = true, recState = 1)
        val brbRecText = MicPillMetricsCalculator.formatPillMiniBadgeText(brbRec, true)
        assertTrue(brbRecText.contains("BRB"))
        assertTrue(brbRecText.contains("REC"))

        assertEquals("", MicPillMetricsCalculator.formatPillMiniBadgeText(countdown, false))
        assertEquals("", MicPillMetricsCalculator.formatPillMiniBadgeText(brbRec, false))
    }

    @Test
    fun shouldShowAmberAlertBorder_checksVoiceWhileMutedAndShowBadges() {
        assertEquals(0xFFF59E0B.toInt(), MicPillMetricsCalculator.AMBER_ALERT_BORDER_ARGB)
        assertTrue(MicPillMetricsCalculator.shouldShowAmberAlertBorder(ConnectionUiState(voiceWhileMuted = true), true))
        assertFalse(MicPillMetricsCalculator.shouldShowAmberAlertBorder(ConnectionUiState(voiceWhileMuted = true), false))
        assertFalse(MicPillMetricsCalculator.shouldShowAmberAlertBorder(ConnectionUiState(voiceWhileMuted = false), true))
        assertFalse(MicPillMetricsCalculator.shouldShowAmberAlertBorder(ConnectionUiState(voiceWhileMuted = false), false))
    }

    @Test
    fun remoteConfig_showPillMiniBadgesDefaultsTrueAndCopies() {
        val def = RemoteConfig()
        assertTrue(def.showPillMiniBadges)
        val disabled = def.copy(showPillMiniBadges = false)
        assertFalse(disabled.showPillMiniBadges)
    }
}
