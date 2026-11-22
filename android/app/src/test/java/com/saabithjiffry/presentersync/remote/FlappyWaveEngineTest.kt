package com.saabithjiffry.presentersync.remote

import com.saabithjiffry.presentersync.remote.ui.arcade.ArcadeVaultManager
import com.saabithjiffry.presentersync.remote.ui.arcade.FlappyBonusKind
import com.saabithjiffry.presentersync.remote.ui.arcade.FlappyMode
import com.saabithjiffry.presentersync.remote.ui.arcade.FlappyPhase
import com.saabithjiffry.presentersync.remote.ui.arcade.FlappyWaveEngine
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

class FlappyWaveEngineTest {

    @Test
    fun vaultCatalog_registersClickerFlappyInSectorZ05() {
        val flappyEntry = ArcadeVaultManager.games.firstOrNull { it.id == "flappy" }
        assertTrue("Expected 'flappy' in ArcadeVaultManager.games", flappyEntry != null)
        assertEquals("Clicker Flappy / Wave", flappyEntry!!.title)
        assertEquals("SECTOR Z-05", flappyEntry.badge)
    }

    @Test
    fun isClickerKeyAllowed_strictlyExcludesConfiguredHwMuteHotkey() {
        // 1. When hwMuteHotkey is KEYCODE_PAGE_DOWN (or "PgDn"), Page Down is excluded while Page Up & Space remain allowed
        assertFalse(FlappyWaveEngine.isClickerKeyAllowed("KEYCODE_PAGE_DOWN", "KEYCODE_PAGE_DOWN"))
        assertFalse(FlappyWaveEngine.isClickerKeyAllowed("PgDn", "KEYCODE_PAGE_DOWN"))
        assertFalse(FlappyWaveEngine.isClickerKeyAllowed("KEYCODE_PAGE_DOWN", "PgDn"))
        assertTrue(FlappyWaveEngine.isClickerKeyAllowed("KEYCODE_PAGE_UP", "KEYCODE_PAGE_DOWN"))
        assertTrue(FlappyWaveEngine.isClickerKeyAllowed("KEYCODE_SPACE", "KEYCODE_PAGE_DOWN"))
        assertTrue(FlappyWaveEngine.isClickerKeyAllowed("KEYCODE_DPAD_RIGHT", "KEYCODE_PAGE_DOWN"))

        val allowedWhenPgDnMuted = FlappyWaveEngine.buildAllowedClickerKeys("KEYCODE_PAGE_DOWN")
        assertFalse(allowedWhenPgDnMuted.contains("KEYCODE_PAGE_DOWN"))
        assertTrue(allowedWhenPgDnMuted.contains("KEYCODE_PAGE_UP"))

        // 2. When hwMuteHotkey is KEYCODE_B (or "b"), B is never allowed while Page Down & Page Up are allowed
        assertFalse(FlappyWaveEngine.isClickerKeyAllowed("KEYCODE_B", "KEYCODE_B"))
        assertFalse(FlappyWaveEngine.isClickerKeyAllowed("b", "b"))
        assertTrue(FlappyWaveEngine.isClickerKeyAllowed("KEYCODE_PAGE_DOWN", "KEYCODE_B"))
        assertTrue(FlappyWaveEngine.isClickerKeyAllowed("KEYCODE_PAGE_UP", "b"))

        // 3. When hwMuteHotkey is KEYCODE_DPAD_RIGHT (or "Right"), Dpad Right is excluded
        assertFalse(FlappyWaveEngine.isClickerKeyAllowed("KEYCODE_DPAD_RIGHT", "Right"))
        assertTrue(FlappyWaveEngine.isClickerKeyAllowed("KEYCODE_PAGE_DOWN", "Right"))
    }

    @Test
    fun classicFlap_andGravityWavePhysics_gateScoring_shield_andCollision() {
        var bestScore = 0
        val eng = FlappyWaveEngine(random = Random(77)) { newBest -> bestScore = newBest }
        eng.startNewSession(
            widthPx = 1080,
            heightPx = 1920,
            screenDensity = 2f,
            initialHighScore = 0,
            initialMode = FlappyMode.CLASSIC_FLAP
        )
        assertEquals(FlappyPhase.PLAYING, eng.phase)
        assertEquals(FlappyMode.CLASSIC_FLAP, eng.mode)

        // 1. Classic Flap impulse & gravity arc
        eng.clearGatesForTest()
        eng.setCraftForTest(260f, 900f, 0f)
        assertTrue(eng.flapOrHold(true))
        val vyAfterFlap = eng.craftVy
        assertTrue("Expected strong upward velocity impulse < -500, got $vyAfterFlap", vyAfterFlap < -500f)

        eng.step(0.03f)
        assertTrue("Craft should rise after flap", eng.craftY < 900f)
        assertTrue("Gravity should decelerate upward velocity", eng.craftVy > vyAfterFlap)

        eng.flapOrHold(false)
        repeat(25) { eng.step(0.025f) }
        assertTrue("Gravity should pull craft downward after apex", eng.craftVy > 200f)

        // 2. Gravity Wave mode: hold-to-climb upward thrust & release-to-dive downward glide + ribbon trail
        assertEquals(FlappyMode.GRAVITY_WAVE, eng.toggleMode())
        eng.setCraftForTest(260f, 960f, 60f)
        eng.flapOrHold(true)
        repeat(12) { eng.step(0.02f) }
        assertTrue(eng.isHolding)
        assertTrue("Expected upward climb vy < -300, got ${eng.craftVy}", eng.craftVy < -300f)
        assertTrue("Craft should climb upward while holding", eng.craftY < 940f)
        assertTrue("Ribbon trail history should record points", eng.trail.size >= 5)

        val climbY = eng.craftY
        eng.flapOrHold(false)
        repeat(14) { eng.step(0.02f) }
        assertFalse(eng.isHolding)
        assertTrue("Expected downward dive vy > 250, got ${eng.craftVy}", eng.craftVy > 250f)
        assertTrue("Craft should dive below climbY", eng.craftY > climbY)

        // 3. Gate pass scoring & highScore callback
        eng.clearGatesForTest()
        eng.setMode(FlappyMode.CLASSIC_FLAP)
        eng.setCraftForTest(260f, 800f, -60f)
        eng.spawnGate(x = 240f, gapY = 800f, gapH = 360f, w = 80f)
        repeat(6) { eng.step(0.02f) }
        assertEquals(FlappyPhase.PLAYING, eng.phase)
        assertTrue(eng.score >= 1)
        assertEquals(eng.highScore, bestScore)

        // 4. SHIELD bonus ring absorption protects against 1 pillar impact, unshielded collision triggers GAME_OVER
        eng.clearGatesForTest()
        eng.setCraftForTest(260f, 800f, 0f)
        eng.spawnBonusRing(265f, 800f, FlappyBonusKind.SHIELD)
        eng.step(0.02f)
        assertTrue("Expected shieldTimerSec > 5f, got ${eng.shieldTimerSec}", eng.shieldTimerSec > 5f)

        // Collide with top pillar while shielded -> shield absorbs impact
        eng.spawnGate(x = 240f, gapY = 1350f, gapH = 220f, w = 90f)
        eng.setCraftForTest(260f, 500f, 0f)
        eng.step(0.02f)
        assertEquals(FlappyPhase.PLAYING, eng.phase)
        assertEquals(0f, eng.shieldTimerSec, 0.001f)

        // Collide with pillar without shield -> GAME_OVER
        eng.spawnGate(x = 240f, gapY = 1350f, gapH = 220f, w = 90f)
        eng.setCraftForTest(260f, 500f, 0f)
        eng.step(0.02f)
        assertEquals(FlappyPhase.GAME_OVER, eng.phase)
    }
}
