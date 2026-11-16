package com.saabithjiffry.presentersync.remote.config

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class HudColorPaletteTest {

    @Test
    fun resolvesAllSixWindowsPresetsCaseInsensitively() {
        assertEquals(6, HudColorPalettes.presetNames.size)
        for (name in HudColorPalettes.presetNames) {
            val lower = name.lowercase()
            val palette = HudColorPalettes.get(lower)
            assertEquals(name, palette.name)
            assertNotEquals(palette.liveBg, palette.mutedBg)
        }
        assertEquals("Standard", HudColorPalettes.get("nonexistent").name)
    }

    @Test
    fun customPaletteNormalizesHexAndPicksContrastSafeIcon() {
        assertEquals("#0EA5E9", HudColorPalettes.normalizeColorHex("0ea5e9"))
        assertEquals("#107C10", HudColorPalettes.normalizeColorHex("nothex", "#107C10"))
        val custom = HudColorPalettes.get("Custom", "#FEF08A", "#0F2E22")
        assertEquals("Custom", custom.name)
        assertEquals(0xFF111827.toInt(), custom.liveIcon)
        assertEquals(0xFFFFFFFF.toInt(), custom.mutedIcon)
    }
}
