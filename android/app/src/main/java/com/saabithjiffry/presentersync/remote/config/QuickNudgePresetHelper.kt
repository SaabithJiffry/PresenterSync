package com.saabithjiffry.presentersync.remote.config

object QuickNudgePresetHelper {
    val DEFAULT_PRESETS: List<String> = listOf("2 min left", "Wrap up", "Check Mic", "Q&A")

    fun resolve(customRaw: String, hostPresets: List<String>, maxCount: Int = 6): List<String> {
        val trimmedCustom = customRaw.trim()
        if (trimmedCustom.isNotEmpty()) {
            val parsed = trimmedCustom.split('|', ',')
                .map { it.trim() }
                .filter { it.isNotEmpty() }
                .distinct()
                .take(maxCount)
            if (parsed.isNotEmpty()) return parsed
        }
        val hostClean = hostPresets
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .distinct()
            .take(maxCount)
        if (hostClean.isNotEmpty()) return hostClean
        return DEFAULT_PRESETS.take(maxCount)
    }
}
