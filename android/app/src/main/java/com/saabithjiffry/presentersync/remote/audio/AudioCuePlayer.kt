package com.saabithjiffry.presentersync.remote.audio

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sin

data class ToneSegment(
    val frequencyHz: Int,
    val durationMs: Int
)

/**
 * Generates and plays Windows-parity two-tone acoustic feedback chimes when the mic
 * toggles between LIVE and MUTED:
 * - Muted: 880 Hz (65 ms) -> 520 Hz (95 ms)
 * - Live:  520 Hz (65 ms) -> 880 Hz (95 ms)
 */
class AudioCuePlayer {
    private val playSeq = AtomicInteger(0)

    @Volatile
    private var activeTrack: AudioTrack? = null

    fun playMuteCue(isMuted: Boolean) {
        val seq = playSeq.incrementAndGet()
        val (first, second) = computeTones(isMuted)
        val pcm = generateDualTonePcm(
            sampleRate = SAMPLE_RATE,
            f1Hz = first.frequencyHz,
            d1Ms = first.durationMs,
            f2Hz = second.frequencyHz,
            d2Ms = second.durationMs
        )
        Thread({
            if (playSeq.get() != seq) return@Thread
            releaseActiveTrack()
            var track: AudioTrack? = null
            try {
                val attrs = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
                val format = AudioFormat.Builder()
                    .setSampleRate(SAMPLE_RATE)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build()
                val byteCount = pcm.size * 2
                track = AudioTrack.Builder()
                    .setAudioAttributes(attrs)
                    .setAudioFormat(format)
                    .setTransferMode(AudioTrack.MODE_STATIC)
                    .setBufferSizeInBytes(byteCount)
                    .build()
                if (track.state != AudioTrack.STATE_INITIALIZED || playSeq.get() != seq) {
                    runCatching { track.release() }
                    return@Thread
                }
                track.write(pcm, 0, pcm.size)
                activeTrack = track
                track.play()
                val totalMs = first.durationMs + second.durationMs + 45L
                Thread.sleep(totalMs)
            } catch (_: Throwable) {
            } finally {
                if (track != null) {
                    if (activeTrack === track) {
                        activeTrack = null
                    }
                    runCatching {
                        if (track.playState == AudioTrack.PLAYSTATE_PLAYING) {
                            track.stop()
                        }
                        track.release()
                    }
                }
            }
        }, "PresenterSync-AudioCue").apply {
            isDaemon = true
            start()
        }
    }

    fun release() {
        playSeq.incrementAndGet()
        releaseActiveTrack()
    }

    private fun releaseActiveTrack() {
        val prev = activeTrack ?: return
        activeTrack = null
        runCatching {
            if (prev.playState == AudioTrack.PLAYSTATE_PLAYING) {
                prev.stop()
            }
            prev.release()
        }
    }

    companion object {
        const val SAMPLE_RATE = 44100

        fun computeTones(isMuted: Boolean): Pair<ToneSegment, ToneSegment> {
            return if (isMuted) {
                ToneSegment(880, 65) to ToneSegment(520, 95)
            } else {
                ToneSegment(520, 65) to ToneSegment(880, 95)
            }
        }

        fun generateDualTonePcm(
            sampleRate: Int,
            f1Hz: Int,
            d1Ms: Int,
            f2Hz: Int,
            d2Ms: Int,
            amplitude: Double = 0.28
        ): ShortArray {
            val n1 = ((sampleRate.toLong() * d1Ms) / 1000L).toInt().coerceAtLeast(1)
            val gap = ((sampleRate.toLong() * 8L) / 1000L).toInt().coerceAtLeast(1)
            val n2 = ((sampleRate.toLong() * d2Ms) / 1000L).toInt().coerceAtLeast(1)
            val out = ShortArray(n1 + gap + n2)

            writeToneSegment(out, 0, n1, sampleRate, f1Hz, amplitude)
            writeToneSegment(out, n1 + gap, n2, sampleRate, f2Hz, amplitude)
            return out
        }

        private fun writeToneSegment(
            buf: ShortArray,
            offset: Int,
            count: Int,
            sampleRate: Int,
            freqHz: Int,
            amplitude: Double
        ) {
            val fadeSamples = ((sampleRate * 6) / 1000).coerceIn(1, count / 2)
            val omega = 2.0 * PI * freqHz / sampleRate.toDouble()
            for (i in 0 until count) {
                val env = when {
                    i < fadeSamples -> 0.5 * (1.0 - cos(PI * i / fadeSamples))
                    i >= count - fadeSamples -> 0.5 * (1.0 - cos(PI * (count - 1 - i) / fadeSamples))
                    else -> 1.0
                }
                val sample = sin(omega * i) * amplitude * env * Short.MAX_VALUE
                buf[offset + i] = sample.roundToInt()
                    .coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
                    .toShort()
            }
        }
    }
}
