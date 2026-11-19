package com.saabithjiffry.presentersync.remote.service

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import com.saabithjiffry.presentersync.remote.config.RemoteConfig
import kotlin.math.roundToInt

enum class HapticAlertType {
    MUTE,
    UNMUTE,
    TIMER_WARNING_2M,
    TIMER_OVERTIME,
    SPEAKING_WHILE_MUTED,
    STAGE_NUDGE
}

data class HapticWaveform(
    val timings: LongArray,
    val amplitudes: IntArray
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is HapticWaveform) return false
        return timings.contentEquals(other.timings) && amplitudes.contentEquals(other.amplitudes)
    }

    override fun hashCode(): Int {
        var result = timings.contentHashCode()
        result = 31 * result + amplitudes.contentHashCode()
        return result
    }
}

object HapticPatterns {
    fun patternFor(type: HapticAlertType): HapticWaveform = when (type) {
        HapticAlertType.MUTE -> HapticWaveform(
            timings = longArrayOf(0L, 45L, 55L, 70L),
            amplitudes = intArrayOf(0, 180, 0, 230)
        )
        HapticAlertType.UNMUTE -> HapticWaveform(
            timings = longArrayOf(0L, 40L),
            amplitudes = intArrayOf(0, 170)
        )
        HapticAlertType.TIMER_WARNING_2M -> HapticWaveform(
            timings = longArrayOf(0L, 80L, 100L, 80L),
            amplitudes = intArrayOf(0, 190, 0, 190)
        )
        HapticAlertType.TIMER_OVERTIME -> HapticWaveform(
            timings = longArrayOf(0L, 120L, 80L, 120L, 80L, 180L),
            amplitudes = intArrayOf(0, 240, 0, 240, 0, 255)
        )
        HapticAlertType.SPEAKING_WHILE_MUTED -> HapticWaveform(
            timings = longArrayOf(0L, 60L, 50L, 60L, 50L, 90L),
            amplitudes = intArrayOf(0, 220, 0, 220, 0, 255)
        )
        HapticAlertType.STAGE_NUDGE -> HapticWaveform(
            timings = longArrayOf(0L, 50L, 70L, 110L),
            amplitudes = intArrayOf(0, 180, 0, 240)
        )
    }

    fun scaleAmplitudes(amplitudes: IntArray, intensity: Float): IntArray {
        val clampedIntensity = intensity.coerceIn(0.2f, 1.0f)
        return IntArray(amplitudes.size) { idx ->
            val raw = amplitudes[idx]
            if (raw <= 0) 0 else (raw * clampedIntensity).roundToInt().coerceIn(1, 255)
        }
    }
}

class HapticAlertPlayer(context: Context) {
    private val appContext = context.applicationContext

    private val vibrator: Vibrator? by lazy {
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val mgr = appContext.getSystemService(VibratorManager::class.java)
                mgr?.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                appContext.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            }
        }.getOrNull()
    }

    fun play(type: HapticAlertType, config: RemoteConfig) {
        if (!config.enableHapticAlerts) return
        val vib = vibrator ?: return
        try {
            if (!vib.hasVibrator()) return
            val wave = HapticPatterns.patternFor(type)
            val effect = if (vib.hasAmplitudeControl()) {
                val scaled = HapticPatterns.scaleAmplitudes(wave.amplitudes, config.hapticIntensity)
                VibrationEffect.createWaveform(wave.timings, scaled, -1)
            } else {
                VibrationEffect.createWaveform(wave.timings, -1)
            }
            vib.vibrate(effect)
        } catch (_: SecurityException) {
        } catch (_: Exception) {
        }
    }

    fun cancel() {
        try {
            vibrator?.cancel()
        } catch (_: Exception) {
        }
    }
}
