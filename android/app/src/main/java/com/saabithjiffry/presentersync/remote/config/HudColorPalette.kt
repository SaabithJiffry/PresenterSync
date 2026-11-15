package com.saabithjiffry.presentersync.remote.config

data class HudColorPalette(
    val name: String,
    val liveBg: Int,
    val liveIcon: Int,
    val mutedBg: Int,
    val mutedIcon: Int,
    val offlineBg: Int,
    val offlineIcon: Int,
    val authErrBorder: Int
)

object HudColorPalettes {
    val presetNames: List<String> = listOf(
        "Standard",
        "Colorblind Safe",
        "OLED Stealth",
        "Broadcast Tally",
        "Cyber Ocean"
    )

    private fun rgb(hex: String): Int {
        val clean = hex.trim().removePrefix("#").removePrefix("0x")
        val value = clean.toLong(16).toInt()
        return (0xFF shl 24) or value
    }

    fun normalize(name: String): String {
        val cleaned = name.trim().lowercase()
        return presetNames.firstOrNull { it.lowercase() == cleaned } ?: "Standard"
    }

    fun get(presetName: String): HudColorPalette {
        return when (normalize(presetName)) {
            "Colorblind Safe" -> HudColorPalette(
                name = "Colorblind Safe",
                liveBg = rgb("0072B2"),
                liveIcon = rgb("002A45"),
                mutedBg = rgb("D55E00"),
                mutedIcon = rgb("4A1E00"),
                offlineBg = rgb("374151"),
                offlineIcon = rgb("9CA3AF"),
                authErrBorder = rgb("D55E00")
            )
            "OLED Stealth" -> HudColorPalette(
                name = "OLED Stealth",
                liveBg = rgb("0F2E22"),
                liveIcon = rgb("34D399"),
                mutedBg = rgb("3B0D14"),
                mutedIcon = rgb("FB7185"),
                offlineBg = rgb("141417"),
                offlineIcon = rgb("71717A"),
                authErrBorder = rgb("3B0D14")
            )
            "Broadcast Tally" -> HudColorPalette(
                name = "Broadcast Tally",
                liveBg = rgb("16A34A"),
                liveIcon = rgb("052E16"),
                mutedBg = rgb("DC2626"),
                mutedIcon = rgb("450A0A"),
                offlineBg = rgb("1F2937"),
                offlineIcon = rgb("9CA3AF"),
                authErrBorder = rgb("DC2626")
            )
            "Cyber Ocean" -> HudColorPalette(
                name = "Cyber Ocean",
                liveBg = rgb("06B6D4"),
                liveIcon = rgb("083344"),
                mutedBg = rgb("EC4899"),
                mutedIcon = rgb("500724"),
                offlineBg = rgb("1E293B"),
                offlineIcon = rgb("94A3B8"),
                authErrBorder = rgb("EC4899")
            )
            else -> HudColorPalette(
                name = "Standard",
                liveBg = rgb("22C55E"),
                liveIcon = rgb("064E3B"),
                mutedBg = rgb("EF4444"),
                mutedIcon = rgb("540808"),
                offlineBg = rgb("374151"),
                offlineIcon = rgb("9CA3AF"),
                authErrBorder = rgb("EF4444")
            )
        }
    }
}
