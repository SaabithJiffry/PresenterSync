package com.saabithjiffry.presentersync.remote.ui.overlay

import com.saabithjiffry.presentersync.remote.config.RemoteConfig
import com.saabithjiffry.presentersync.remote.ui.screens.STOP_RECORD_CONFIRM_WINDOW_MS
import com.saabithjiffry.presentersync.remote.ui.screens.evaluateStopRecordTap
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class StopRecordGuardTest {

    @Test
    fun remoteConfigDefaultsConfirmBeforeStopRecordingToTrue() {
        val cfg = RemoteConfig()
        assertTrue(cfg.confirmBeforeStopRecording)
        val disabled = cfg.copy(confirmBeforeStopRecording = false)
        assertFalse(disabled.confirmBeforeStopRecording)
    }

    @Test
    fun evaluateStopRecordTapEnforces3000MsConfirmWindow() {
        assertEquals(3000L, STOP_RECORD_CONFIRM_WINDOW_MS)

        // 1st tap while recording -> arms 3000ms window, does NOT stop
        val first = evaluateStopRecordTap(
            isRecording = true,
            confirmEnabled = true,
            pendingUntilMs = 0L,
            nowMs = 10_000L
        )
        assertFalse(first.shouldExecuteStop)
        assertEquals(13_000L, first.nextPendingUntilMs)

        // 2nd tap within 3000ms -> confirms stop
        val second = evaluateStopRecordTap(
            isRecording = true,
            confirmEnabled = true,
            pendingUntilMs = first.nextPendingUntilMs,
            nowMs = 12_500L
        )
        assertTrue(second.shouldExecuteStop)
        assertEquals(0L, second.nextPendingUntilMs)

        // Tap after >= 3000ms -> expired, re-arms window
        val expired = evaluateStopRecordTap(
            isRecording = true,
            confirmEnabled = true,
            pendingUntilMs = first.nextPendingUntilMs,
            nowMs = 13_000L
        )
        assertFalse(expired.shouldExecuteStop)
        assertEquals(16_000L, expired.nextPendingUntilMs)
    }

    @Test
    fun evaluateStopRecordTapStopsImmediatelyWhenDisabledOrNotRecording() {
        val disabled = evaluateStopRecordTap(
            isRecording = true,
            confirmEnabled = false,
            pendingUntilMs = 0L,
            nowMs = 10_000L
        )
        assertTrue(disabled.shouldExecuteStop)

        val idle = evaluateStopRecordTap(
            isRecording = false,
            confirmEnabled = true,
            pendingUntilMs = 0L,
            nowMs = 10_000L
        )
        assertTrue(idle.shouldExecuteStop)
    }
}
