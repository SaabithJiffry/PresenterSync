package com.saabithjiffry.presentersync.remote.config

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class HudColorPaletteTest {

    @Test
    fun resolvesAllFiveWindowsPresetsCaseInsensitively() {
        assertEquals(5, HudColorPalettes.presetNames.size)
        for (name in HudColorPalettes.presetNames) {
            val lower = name.lowercase()
            val palette = HudColorPalettes.get(lower)
            assertEquals(name, palette.name)
            assertNotEquals(palette.liveBg, palette.mutedBg)
        }
        assertEquals("Standard", HudColorPalettes.get("nonexistent").name)
    }
}
