package com.saabithjiffry.presentersync.remote

import android.view.WindowManager
import com.saabithjiffry.presentersync.remote.config.ArcadeHighScoresCodec
import com.saabithjiffry.presentersync.remote.config.RemoteConfig
import com.saabithjiffry.presentersync.remote.ui.arcade.ArcadeOverlayHost
import com.saabithjiffry.presentersync.remote.ui.arcade.ArcadeRectF
import com.saabithjiffry.presentersync.remote.ui.arcade.ArcadeVaultManager
import com.saabithjiffry.presentersync.remote.ui.arcade.AsteroidsEngine
import com.saabithjiffry.presentersync.remote.ui.arcade.AsteroidsPowerUpKind
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import kotlin.random.Random

class ArcadeVaultAndAsteroidsTest {

    @Before
    fun setUp() {
        ArcadeVaultManager.lock()
    }

    @After
    fun tearDown() {
        ArcadeVaultManager.lock()
    }

    @Test
    fun vault_startsLocked_normalizesInsertCoin_andLockNotifiesListeners() {
        assertFalse(ArcadeVaultManager.isUnlocked.value)
        assertEquals("INSERTCOIN", ArcadeVaultManager.normalizePasscode("insert coin"))
        assertEquals("INSERTCOIN", ArcadeVaultManager.normalizePasscode("Insert-Coin!"))
        assertTrue(ArcadeVaultManager.validatePasscode("INSERT COIN"))
        assertFalse(ArcadeVaultManager.validatePasscode("FREEPLAY"))

        var lockCallbacks = 0
        val listener: () -> Unit = { lockCallbacks += 1 }
        ArcadeVaultManager.registerLockListener(listener)
        try {
            assertFalse(ArcadeVaultManager.tryUnlock("WRONG"))
            assertFalse(ArcadeVaultManager.isUnlocked.value)

            assertTrue(ArcadeVaultManager.tryUnlock("insert coin"))
            assertTrue(ArcadeVaultManager.isUnlocked.value)

            ArcadeVaultManager.lock()
            assertFalse(ArcadeVaultManager.isUnlocked.value)
            assertEquals(1, lockCallbacks)
        } finally {
            ArcadeVaultManager.unregisterLockListener(listener)
        }
    }

    @Test
    fun highScoresCodec_persistsOnlyScoresWithoutUnlockState() {
        val cfg = RemoteConfig()
        assertTrue(cfg.arcadeHighScores.isEmpty())

        val json = ArcadeHighScoresCodec.toJsonString(mapOf("snake" to 210, "asteroids" to 420))
        assertFalse(json.contains("unlocked", ignoreCase = true))
        val parsed = ArcadeHighScoresCodec.fromJsonString(json)
        assertEquals(210, parsed["snake"])
        assertEquals(420, parsed["asteroids"])
    }

    @Test
    fun overlayFlags_respectHideFromScreenCaptureAndKeepScreenOn() {
        val secured = ArcadeOverlayHost.computeWindowFlags(hideFromScreenCapture = true, keepScreenOn = true)
        assertTrue((secured and WindowManager.LayoutParams.FLAG_SECURE) != 0)
        assertTrue((secured and WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) != 0)
        assertTrue((secured and WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE) == 0)

        val open = ArcadeOverlayHost.computeWindowFlags(hideFromScreenCapture = false, keepScreenOn = false)
        assertTrue((open and WindowManager.LayoutParams.FLAG_SECURE) == 0)
        assertTrue((open and WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) == 0)
    }

    @Test
    fun asteroidsEngine_splitsRocks_hitsSaucer_collectsPowerUps_andDeflectsFromMicBumper() {
        var latestBest = 0
        val eng = AsteroidsEngine(random = Random(123)) { best -> latestBest = best }
        eng.startNewSession(
            widthPx = 1080,
            heightPx = 1920,
            screenDensity = 2f,
            initialHighScore = 0,
            clearInitialRocks = true
        )

        // 1. Large -> Medium -> Small splitting + exact scoring
        eng.shipAngleRad = (-Math.PI / 2.0).toFloat()
        eng.spawnRock(eng.shipX, eng.shipY - 120f, 0f, 0f, size = 3)
        assertTrue(eng.firePlayerBolt(ignoreCooldown = true))
        repeat(20) { eng.step(0.02f) }
        assertEquals(20, eng.score)
        assertEquals(2, eng.rocks.size)
        assertTrue(eng.rocks.all { it.size == 2 })

        // Clear spawned mediums & verify direct medium->small split +50 and small +100
        eng.rocks.clear()
        eng.bolts.clear()
        eng.spawnRock(eng.shipX, eng.shipY - 110f, 0f, 0f, size = 2)
        assertTrue(eng.firePlayerBolt(ignoreCooldown = true))
        repeat(20) { eng.step(0.02f) }
        assertEquals(70, eng.score)
        assertEquals(2, eng.rocks.size)
        assertTrue(eng.rocks.all { it.size == 1 })

        eng.rocks.clear()
        eng.bolts.clear()
        eng.spawnRock(eng.shipX, eng.shipY - 100f, 0f, 0f, size = 1)
        assertTrue(eng.firePlayerBolt(ignoreCooldown = true))
        repeat(20) { eng.step(0.02f) }
        assertEquals(170, eng.score)
        assertTrue(eng.rocks.isEmpty())

        // 2. Saucer kill (+250)
        eng.bolts.clear()
        val ufo = eng.spawnSaucer(fromLeft = true)
        ufo.x = eng.shipX
        ufo.y = eng.shipY - 130f
        ufo.vx = 0f
        ufo.vy = 0f
        assertTrue(eng.firePlayerBolt(ignoreCooldown = true))
        repeat(20) { eng.step(0.02f) }
        assertNull(eng.saucer)
        assertEquals(420, eng.score)
        assertEquals(420, latestBest)

        // 3. Power-ups activation (RAPID / SPREAD / SHIELD)
        eng.powerUps.clear()
        eng.spawnPowerUp(AsteroidsPowerUpKind.RAPID, eng.shipX, eng.shipY)
        eng.spawnPowerUp(AsteroidsPowerUpKind.SPREAD, eng.shipX, eng.shipY)
        eng.spawnPowerUp(AsteroidsPowerUpKind.SHIELD, eng.shipX, eng.shipY)
        eng.step(0.016f)
        assertTrue(eng.rapidTimerSec > 5f)
        assertTrue(eng.spreadTimerSec > 5f)
        assertTrue(eng.shieldTimerSec > 5f)

        // 4. Mic Pill Bumper elastic velocity reversal
        eng.rocks.clear()
        eng.pillBumper = ArcadeRectF(400f, 400f, 680f, 480f)
        val rock = eng.spawnRock(540f, 385f, 0f, 160f, size = 1)
        assertNotNull(rock)
        repeat(15) { eng.step(0.016f) }
        assertTrue("Expected bumper deflection vy < 0, got ${rock.vy}", rock.vy < 0f)
    }
}
