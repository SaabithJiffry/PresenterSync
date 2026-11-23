package com.saabithjiffry.presentersync.remote

import com.saabithjiffry.presentersync.remote.ui.arcade.ArcadeVaultManager
import com.saabithjiffry.presentersync.remote.ui.arcade.MissileDefenseEngine
import com.saabithjiffry.presentersync.remote.ui.arcade.MissileDefensePhase
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

class MissileDefenseEngineTest {

    @Test
    fun interceptorShockwave_destroysMultipleMeteors_withChainMultiplier() {
        var latestBest = 0
        val eng = MissileDefenseEngine(random = Random(42)) { latestBest = it }
        eng.startNewSession(
            widthPx = 1080,
            heightPx = 1920,
            screenDensity = 2f,
            initialHighScore = 0,
            clearInitialWave = true
        )

        assertEquals(4, eng.pylonsAlive)
        assertEquals(MissileDefensePhase.PLAYING, eng.phase)

        eng.spawnMeteor(540f, 700f, 0f, 10f, isSplitter = false)
        eng.spawnMeteor(565f, 705f, 0f, 10f, isSplitter = false)
        assertTrue(eng.fireInterceptor(552f, 702f, bypassCooldown = true))

        eng.step(1.4f)

        assertEquals(0, eng.meteors.size)
        // 25*1 + 25*2 = 75 kill score + 400 wave clear bonus (4 pylons * 100)
        assertEquals(475, eng.score)
        assertEquals(475, latestBest)
        assertEquals(2, eng.wave)
        assertTrue(eng.combo >= 2)
    }

    @Test
    fun splitterMeteor_forksIntoTwoChildrenMidAir() {
        val eng = MissileDefenseEngine(random = Random(7))
        eng.startNewSession(1080, 1920, 2f, 0, clearInitialWave = true)

        eng.spawnMeteor(500f, 1920f * 0.41f, 0f, 200f, isSplitter = true)
        eng.step(0.25f)

        assertEquals(2, eng.meteors.size)
    }

    @Test
    fun pylonImpact_reducesPylons_andZeroPylonsTriggersGameOver() {
        val eng = MissileDefenseEngine(random = Random(9))
        eng.startNewSession(1080, 1920, 2f, 0, clearInitialWave = true)

        val p0 = eng.pylons[0]
        eng.spawnMeteor(p0.x, p0.y - 10f, 0f, 200f)
        eng.step(0.15f)
        assertEquals(3, eng.pylonsAlive)
        assertEquals(MissileDefensePhase.PLAYING, eng.phase)

        for (i in 1..3) {
            val p = eng.pylons[i]
            eng.spawnMeteor(p.x, p.y - 10f, 0f, 200f)
        }
        eng.step(0.15f)
        assertEquals(0, eng.pylonsAlive)
        assertEquals(MissileDefensePhase.GAME_OVER, eng.phase)
    }

    @Test
    fun vault_registersMissileDefense_sectorZ08() {
        val entry = ArcadeVaultManager.games.firstOrNull { it.id == "missile_defense" }
        assertTrue(entry != null && entry.badge == "SECTOR Z-08" && entry.title == "Missile Defense")
    }
}
