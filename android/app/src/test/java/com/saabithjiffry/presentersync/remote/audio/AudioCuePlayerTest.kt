package com.saabithjiffry.presentersync.remote.audio

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AudioCuePlayerTest {

    @Test
    fun computesDistinctAscendingAndDescendingTonesForLiveAndMuted() {
        val (m1, m2) = AudioCuePlayer.computeTones(isMuted = true)
        assertEquals(880, m1.frequencyHz)
        assertEquals(65, m1.durationMs)
        assertEquals(520, m2.frequencyHz)
        assertEquals(95, m2.durationMs)

        val (l1, l2) = AudioCuePlayer.computeTones(isMuted = false)
        assertEquals(520, l1.frequencyHz)
        assertEquals(880, l2.frequencyHz)
    }

    @Test
    fun generatesNonZeroEnvelopeBoundedPcmBuffer() {
        val pcm = AudioCuePlayer.generateDualTonePcm(
            sampleRate = AudioCuePlayer.SAMPLE_RATE,
            f1Hz = 880,
            d1Ms = 65,
            f2Hz = 520,
            d2Ms = 95
        )
        assertTrue(pcm.size > 6000)
        // First & last samples should start/end near zero thanks to cosine fade envelope
        assertEquals(0, pcm.first().toInt())
        assertTrue(kotlin.math.abs(pcm.last().toInt()) < 400)
        val peak = pcm.maxOf { kotlin.math.abs(it.toInt()) }
        assertTrue("Expected audible PCM peak > 5000, got $peak", peak > 5000)
    }
}
