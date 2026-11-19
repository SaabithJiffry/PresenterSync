package com.saabithjiffry.presentersync.remote

import com.saabithjiffry.presentersync.remote.config.RemoteConfig
import com.saabithjiffry.presentersync.remote.service.HapticAlertType
import com.saabithjiffry.presentersync.remote.service.HapticPatterns
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HapticAlertPlayerTest {

    @Test
    fun allAlertTypes_haveDistinctNonEmptyPatternsWithMatchingLengths() {
        val signatures = mutableSetOf<String>()
        for (type in HapticAlertType.entries) {
            val wf = HapticPatterns.patternFor(type)
            assertTrue("Pattern timings empty for $type", wf.timings.isNotEmpty())
            assertEquals("Timings/amplitudes length mismatch for $type", wf.timings.size, wf.amplitudes.size)
            assertTrue("Expected at least one non-zero amplitude for $type", wf.amplitudes.any { it > 0 })
            signatures += wf.timings.joinToString(",")
        }
        assertEquals("Expected all 6 HapticAlertType patterns to have distinct timing signatures", HapticAlertType.entries.size, signatures.size)
    }

    @Test
    fun scaleAmplitudes_preservesZeroGapsAndClampsNonZeroTo1_255() {
        val raw = intArrayOf(0, 100, 0, 255, 1)

        val low = HapticPatterns.scaleAmplitudes(raw, 0.0f)
        assertEquals(0, low[0])
        assertEquals(0, low[2])
        assertTrue(low[1] in 1..255)
        assertTrue(low[3] in 1..255)
        assertEquals(1, low[4])

        val mid = HapticPatterns.scaleAmplitudes(raw, 0.2f)
        assertEquals(0, mid[0])
        assertEquals(20, mid[1])
        assertEquals(51, mid[3])
        assertEquals(1, mid[4])

        val high = HapticPatterns.scaleAmplitudes(raw, 1.5f)
        assertEquals(0, high[0])
        assertEquals(255, high[3])
        assertTrue(high[1] in 1..255)
    }

    @Test
    fun remoteConfig_hapticDefaultsAreEnabledAt80Percent() {
        val cfg = RemoteConfig()
        assertTrue(cfg.enableHapticAlerts)
        assertEquals(0.8f, cfg.hapticIntensity, 0.0001f)
    }
}
