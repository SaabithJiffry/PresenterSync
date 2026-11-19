package com.saabithjiffry.presentersync.remote

import com.saabithjiffry.presentersync.remote.network.ConnectionUiState
import com.saabithjiffry.presentersync.remote.widget.WidgetStateFormatter
import org.junit.Assert.assertEquals
import org.junit.Test

class PodiumAndWidgetTest {

    @Test
    fun widgetStateFormatter_formatsLiveMutedOfflineAndRecBadge() {
        val offline = WidgetStateFormatter.format(ConnectionUiState(connected = false, isMuted = false, recState = 1))
        assertEquals("OFFLINE", offline.label)
        assertEquals("", offline.badge)
        assertEquals(WidgetStateFormatter.COLOR_OFFLINE_ARGB, offline.bgColorArgb)

        val live = WidgetStateFormatter.format(ConnectionUiState(connected = true, isMuted = false, recState = 0, activeScene = "Main"))
        assertEquals("LIVE", live.label)
        assertEquals("", live.badge)
        assertEquals(WidgetStateFormatter.COLOR_LIVE_ARGB, live.bgColorArgb)

        val mutedRec = WidgetStateFormatter.format(ConnectionUiState(connected = true, isMuted = true, recState = 1, activeScene = "Slides"))
        assertEquals("MUTED", mutedRec.label)
        assertEquals("REC", mutedRec.badge)
        assertEquals(WidgetStateFormatter.COLOR_MUTED_ARGB, mutedRec.bgColorArgb)
    }

    @Test
    fun connectionUiState_slideTelemetryDefaultsAndCopy() {
        val def = ConnectionUiState()
        assertEquals(0, def.slideIndex)
        assertEquals(0, def.slideTotal)
        assertEquals("", def.slideTitle)
        assertEquals("", def.slideNotes)

        val active = def.copy(
            slideIndex = 4,
            slideTotal = 22,
            slideTitle = "Live Demo",
            slideNotes = "Remember to unmute before demo."
        )
        assertEquals(4, active.slideIndex)
        assertEquals(22, active.slideTotal)
        assertEquals("Live Demo", active.slideTitle)
        assertEquals("Remember to unmute before demo.", active.slideNotes)
    }
}
