package com.saabithjiffry.presentersync.remote

import com.saabithjiffry.presentersync.remote.config.QuickNudgePresetHelper
import com.saabithjiffry.presentersync.remote.config.RemoteConfig
import com.saabithjiffry.presentersync.remote.network.ConnectionUiState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PreFlightAndNudgePresetsTest {

    @Test
    fun quickNudgePresetHelper_resolvesCustomHostAndDefaultPrecedence() {
        val custom = QuickNudgePresetHelper.resolve(
            customRaw = " 1m Left | Wrap Now , Check Audio | 1m Left ",
            hostPresets = listOf("Host 1", "Host 2")
        )
        assertEquals(listOf("1m Left", "Wrap Now", "Check Audio"), custom)

        val fromHost = QuickNudgePresetHelper.resolve(
            customRaw = "   ",
            hostPresets = listOf("Host A", "Host B", "")
        )
        assertEquals(listOf("Host A", "Host B"), fromHost)

        val fallback = QuickNudgePresetHelper.resolve(
            customRaw = "",
            hostPresets = emptyList()
        )
        assertEquals(QuickNudgePresetHelper.DEFAULT_PRESETS, fallback)
    }

    @Test
    fun remoteConfig_andConnectionUiState_quickNudgeFields() {
        val cfg = RemoteConfig()
        assertEquals("", cfg.quickNudgePresets)
        val updated = cfg.copy(quickNudgePresets = "A|B|C")
        assertEquals("A|B|C", updated.quickNudgePresets)

        val conn = ConnectionUiState()
        assertTrue(conn.quickNudges.isEmpty())
        val withHost = conn.copy(quickNudges = listOf("Hold", "Go"))
        assertEquals(listOf("Hold", "Go"), withHost.quickNudges)
    }
}
