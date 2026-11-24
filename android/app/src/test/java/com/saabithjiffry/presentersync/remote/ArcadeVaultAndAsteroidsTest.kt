package com.saabithjiffry.presentersync.remote

import android.view.WindowManager
import com.saabithjiffry.presentersync.remote.config.ArcadeHighScoresCodec
import com.saabithjiffry.presentersync.remote.config.RemoteConfig
import com.saabithjiffry.presentersync.remote.ui.arcade.AlienShipKind
import com.saabithjiffry.presentersync.remote.ui.arcade.ArcadeOverlayHost
import com.saabithjiffry.presentersync.remote.ui.arcade.ArcadeRectF
import com.saabithjiffry.presentersync.remote.ui.arcade.ArcadeVaultManager
import com.saabithjiffry.presentersync.remote.ui.arcade.AsteroidsEngine
import com.saabithjiffry.presentersync.remote.ui.arcade.AsteroidsPowerUpKind
import com.saabithjiffry.presentersync.remote.ui.arcade.BlasterMode
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

    @Test
    fun alienBlasterMode_fixedUpwardShip_2dMovement_alienWaves_weaponTiers1To5_andBeamKill() {
        val eng = AsteroidsEngine(random = Random(77))
        eng.startNewSession(
            widthPx = 1080,
            heightPx = 1920,
            screenDensity = 2f,
            initialHighScore = 0
        )
        assertEquals(BlasterMode.ASTEROIDS, eng.mode)

        // Toggle into Alien Blaster mode -> spawns alien wave, clears rocks, resets weaponTier = 1
        assertEquals(BlasterMode.ALIEN_BLASTER, eng.toggleMode())
        assertEquals(1, eng.weaponTier)
        assertTrue("Expected alien wave spawned", eng.aliens.size >= 5)
        assertTrue("Expected zero asteroids in Alien mode", eng.rocks.isEmpty())

        // Fixed forward angle (-PI/2) + full 2D movement (right + up, then left + down)
        eng.aliens.clear()
        eng.bolts.clear()
        val x0 = eng.shipX
        val y0 = eng.shipY
        eng.shipAngleRad = 0.75f // must be locked back to -PI/2
        eng.inputTurnRight = true
        eng.inputThrust = true
        repeat(5) { eng.step(0.02f) }
        assertEquals((-Math.PI / 2.0).toFloat(), eng.shipAngleRad, 0.001f)
        assertTrue("Expected ship moved right (+X)", eng.shipX > x0)
        assertTrue("Expected ship moved forward/up (-Y)", eng.shipY < y0)

        val x1 = eng.shipX
        val y1 = eng.shipY
        eng.inputTurnRight = false
        eng.inputThrust = false
        eng.inputTurnLeft = true
        eng.inputMoveDown = true
        repeat(5) { eng.step(0.02f) }
        assertEquals((-Math.PI / 2.0).toFloat(), eng.shipAngleRad, 0.001f)
        assertTrue("Expected ship moved left (-X)", eng.shipX < x1)
        assertTrue("Expected ship moved backward/down (+Y)", eng.shipY > y1)
        eng.inputTurnLeft = false
        eng.inputMoveDown = false

        // Escalating weapon tiers 1 -> 2 -> 3 -> 4 (5-spread) -> 5 (Beam Laser)
        eng.bolts.clear()
        eng.firePlayerBolt(ignoreCooldown = true)
        assertEquals(1, eng.bolts.size)

        eng.upgradeWeaponTier()
        eng.bolts.clear()
        eng.firePlayerBolt(ignoreCooldown = true)
        assertEquals(2, eng.bolts.size)

        eng.upgradeWeaponTier()
        eng.bolts.clear()
        eng.firePlayerBolt(ignoreCooldown = true)
        assertEquals(3, eng.bolts.size)

        eng.upgradeWeaponTier()
        eng.bolts.clear()
        eng.firePlayerBolt(ignoreCooldown = true)
        assertEquals(5, eng.bolts.size)

        assertEquals(5, eng.upgradeWeaponTier())

        // Tier 5 Neon Beam Laser vaporizes alien cruiser & awards score
        eng.aliens.clear()
        eng.bolts.clear()
        eng.spawnAlien(eng.shipX, eng.shipY - 220f, AlienShipKind.CRUISER, hp = 2, vy = 0f)
        eng.firePlayerBolt(ignoreCooldown = true)
        repeat(8) { eng.step(0.04f) }
        assertTrue("Expected Tier 5 beam active", eng.beamActive)
        assertTrue("Expected cruiser vaporized by Beam Laser", eng.aliens.isEmpty())
        assertTrue("Expected cruiser kill score >= 180", eng.score >= 180)
    }

    @Test
    fun asteroidsEngine_updateDisplayMetrics_rescalesAliensAndPowerUps() {
        val eng = AsteroidsEngine(random = Random(77))
        eng.mode = BlasterMode.ALIEN_BLASTER
        eng.startNewSession(
            widthPx = 1000,
            heightPx = 2000,
            screenDensity = 2f,
            clearInitialRocks = true
        )
        val alien = eng.spawnAlien(x = 400f, y = 600f, kind = AlienShipKind.RAIDER, hp = 2, vy = 0f)
        eng.powerUps.add(
            com.saabithjiffry.presentersync.remote.ui.arcade.AsteroidsPowerUp(
                kind = AsteroidsPowerUpKind.WEAPON_UP,
                x = 250f,
                y = 500f,
                vx = 0f,
                vy = 0f,
                ttlSec = 10f
            )
        )

        eng.updateDisplayMetrics(widthPx = 2000, heightPx = 1000, screenDensity = 2f)

        assertEquals(800f, alien.x, 0.01f)
        assertEquals(300f, alien.y, 0.01f)
        assertEquals(800f, alien.baseX, 0.01f)
        assertEquals(500f, eng.powerUps[0].x, 0.01f)
        assertEquals(250f, eng.powerUps[0].y, 0.01f)
    }
}
