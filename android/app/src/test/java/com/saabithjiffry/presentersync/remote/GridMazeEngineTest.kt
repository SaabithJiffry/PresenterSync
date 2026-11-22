package com.saabithjiffry.presentersync.remote

import com.saabithjiffry.presentersync.remote.ui.arcade.ChaserPersonality
import com.saabithjiffry.presentersync.remote.ui.arcade.ChaserState
import com.saabithjiffry.presentersync.remote.ui.arcade.ChaserWaveMode
import com.saabithjiffry.presentersync.remote.ui.arcade.LightCyclesEngine
import com.saabithjiffry.presentersync.remote.ui.arcade.LightCyclesPhase
import com.saabithjiffry.presentersync.remote.ui.arcade.PacGridEngine
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class GridMazeEngineTest {

    // ========================================================================
    // SECTOR Z-06: LightCyclesEngine Tests
    // ========================================================================

    @Test
    fun `LightCyclesEngine rejects 180-degree self-reversal and accepts 90-degree turns`() {
        val engine = LightCyclesEngine()
        engine.startNewSession(widthPx = 1280, heightPx = 720, screenDensity = 2f, initialHighScore = 0)

        // Initially moving right (+1, 0)
        assertEquals(1, engine.playerDx)
        assertEquals(0, engine.playerDy)

        // 180-degree reversal (-1, 0) is rejected
        assertFalse(engine.steer(-1, 0))

        // 90-degree turn up (0, -1) is accepted
        assertTrue(engine.steer(0, -1))
        engine.step(0.06f)
        assertEquals(0, engine.playerDx)
        assertEquals(-1, engine.playerDy)
    }

    @Test
    fun `LightCyclesEngine Turbo Boost doubles step speed and drains then recharges energy`() {
        val normalEngine = LightCyclesEngine()
        normalEngine.startNewSession(1280, 720, 2f, 0)
        val startColNormal = normalEngine.playerCol
        normalEngine.step(0.06f)
        val normalSteps = normalEngine.playerCol - startColNormal

        val boostEngine = LightCyclesEngine()
        boostEngine.startNewSession(1280, 720, 2f, 0)
        val startColBoost = boostEngine.playerCol
        boostEngine.setBoost(true)
        assertTrue(boostEngine.boostActive)
        boostEngine.step(0.06f)
        val boostSteps = boostEngine.playerCol - startColBoost

        assertTrue("Turbo boost should advance further than normal speed", boostSteps > normalSteps)
        assertTrue("Boost energy should drain while active", boostEngine.boostEnergy < 100f)

        val drainedEnergy = boostEngine.boostEnergy
        boostEngine.setBoost(false)
        boostEngine.step(0.1f)
        assertTrue("Boost energy should recharge when inactive", boostEngine.boostEnergy > drainedEnergy)
    }

    @Test
    fun `LightCyclesEngine flood-fill AI steers away from blocked wall ahead`() {
        val engine = LightCyclesEngine()
        engine.startNewSession(1280, 720, 2f, 0, gridCols = 40, gridRows = 30)

        // Place AI at (10, 15) heading left (-1, 0), and block cell (9, 15) directly ahead
        engine.forceSetPositionsForTest(
            pCol = 5, pRow = 5, pDx = 1, pDy = 0,
            aCol = 10, aRow = 15, aDx = -1, aDy = 0
        )
        engine.forceSetTrailCellForTest(9, 15, owner = 1)

        val chosen = engine.chooseAiDirection(10, 15, -1, 0)
        assertFalse("AI must not drive into blocked cell (-1, 0)", chosen.first == -1 && chosen.second == 0)
        assertEquals("AI should turn perpendicular into open space", 0, chosen.first)
        assertTrue(chosen.second == 1 || chosen.second == -1)
    }

    @Test
    fun `LightCyclesEngine detects trail collision and enters GAME_OVER`() {
        val engine = LightCyclesEngine()
        engine.startNewSession(1280, 720, 2f, 0)
        val blockedCol = engine.playerCol + 1
        val blockedRow = engine.playerRow
        engine.forceSetTrailCellForTest(blockedCol, blockedRow, owner = 2)

        engine.step(0.06f)
        assertEquals(LightCyclesPhase.GAME_OVER, engine.phase)
        assertTrue("Crash should emit particles", engine.particles.isNotEmpty())
    }

    // ========================================================================
    // SECTOR Z-07: PacGridEngine Tests
    // ========================================================================

    @Test
    fun `PacGridEngine consumes standard pellet (+10) and Power Orb (+50) triggering 7s Frightened Mode`() {
        var savedHighScore = 0
        val engine = PacGridEngine(onNewHighScore = { savedHighScore = it })
        engine.startNewSession(1080, 1920, 2f, 0)

        // Place runner on a known pellet tile (1, 1)
        engine.forceSetRunnerForTest(col = 1f, row = 1f, dx = 1, dy = 0)
        engine.step(0.02f)
        assertTrue(engine.score >= 10)
        assertEquals(engine.score, savedHighScore)

        // Place runner on top-left corner Power Orb (1, 3)
        val preOrbScore = engine.score
        engine.forceSetRunnerForTest(col = 1f, row = 3f, dx = 0, dy = -1)
        engine.step(0.02f)
        assertTrue("Power Orb should award +50 points", engine.score >= preOrbScore + 50)
        assertTrue("Frightened timer should activate (~7.0s)", engine.frightenedTimerSec > 6.5f)
        assertTrue(engine.chasers.all { it.state == ChaserState.FRIGHTENED })
    }

    @Test
    fun `PacGridEngine awards escalating Frightened combos 200-400-800-1600 and regenerates EYES at ghost pen`() {
        val engine = PacGridEngine()
        engine.startNewSession(1080, 1920, 2f, 0)
        engine.setTileForTest(13, 23, PacGridEngine.TILE_EMPTY)
        engine.forceSetRunnerForTest(13f, 23f, dx = 0, dy = 0)
        engine.triggerFrightenedMode()

        val expectedRewards = listOf(200, 400, 800, 1600)
        val personalities = ChaserPersonality.values()

        for (i in personalities.indices) {
            val before = engine.score
            engine.forceSetChaserForTest(
                personality = personalities[i],
                col = 13f,
                row = 23f,
                state = ChaserState.FRIGHTENED
            )
            engine.step(0.01f)
            val delta = engine.score - before
            assertEquals("Chaser #${i + 1} combo mismatch", expectedRewards[i], delta)
            val chaser = engine.chasers.first { it.personality == personalities[i] }
            assertEquals("Eaten chaser must turn into returning EYES", ChaserState.EYES, chaser.state)
        }

        // Move returning EYES chaser into ghost pen (13, 14) and verify regeneration to NORMAL
        engine.forceSetChaserForTest(
            personality = ChaserPersonality.BLINKY,
            col = PacGridEngine.PEN_COL.toFloat(),
            row = PacGridEngine.PEN_ROW.toFloat(),
            state = ChaserState.EYES
        )
        engine.step(0.02f)
        val blinky = engine.chasers.first { it.personality == ChaserPersonality.BLINKY }
        assertEquals("EYES reaching ghost pen must regenerate to NORMAL", ChaserState.NORMAL, blinky.state)
    }

    @Test
    fun `PacGridEngine computes distinct target tiles for Blinky, Pinky, Inky, and Clyde`() {
        val engine = PacGridEngine()
        engine.startNewSession(1080, 1920, 2f, 0)
        engine.forceSetWaveModeForTest(ChaserWaveMode.CHASE)
        engine.forceSetRunnerForTest(col = 10f, row = 15f, dx = 1, dy = 0)
        engine.forceSetChaserForTest(ChaserPersonality.BLINKY, col = 8f, row = 15f)

        val blinky = engine.chasers.first { it.personality == ChaserPersonality.BLINKY }
        val pinky = engine.chasers.first { it.personality == ChaserPersonality.PINKY }
        val inky = engine.chasers.first { it.personality == ChaserPersonality.INKY }
        val clyde = engine.chasers.first { it.personality == ChaserPersonality.CLYDE }

        // Blinky: direct runner tile (10, 15)
        val blinkyTarget = engine.computeChaserTargetTile(blinky)
        assertEquals(10, blinkyTarget.col)
        assertEquals(15, blinkyTarget.row)

        // Pinky: 4 tiles ahead of runner -> (14, 15)
        val pinkyTarget = engine.computeChaserTargetTile(pinky)
        assertEquals(14, pinkyTarget.col)
        assertEquals(15, pinkyTarget.row)

        // Inky: pivot 2 tiles ahead (12, 15), vector from Blinky (8, 15) doubled -> (16, 15)
        val inkyTarget = engine.computeChaserTargetTile(inky)
        assertEquals(16, inkyTarget.col)
        assertEquals(15, inkyTarget.row)

        // Clyde far (> 8 tiles away): targets runner (10, 15)
        engine.forceSetChaserForTest(ChaserPersonality.CLYDE, col = 1f, row = 1f)
        val clydeFarTarget = engine.computeChaserTargetTile(clyde)
        assertEquals(10, clydeFarTarget.col)
        assertEquals(15, clydeFarTarget.row)

        // Clyde near (<= 8 tiles away): retreats to bottom-left scatter corner
        engine.forceSetChaserForTest(ChaserPersonality.CLYDE, col = 11f, row = 15f)
        val clydeNearTarget = engine.computeChaserTargetTile(clyde)
        assertEquals(engine.scatterCornerFor(ChaserPersonality.CLYDE), clydeNearTarget)
    }

    @Test
    fun `PacGridEngine transitions from Scatter to Chase wave after 7 seconds and wraps warp tunnel`() {
        val engine = PacGridEngine()
        engine.startNewSession(1080, 1920, 2f, 0)
        assertEquals(ChaserWaveMode.SCATTER, engine.waveMode)

        // Step past 7.0s initial Scatter wave (keep runner safe in empty tunnel tile)
        for (i in 0 until 75) {
            engine.forceSetRunnerForTest(6f, 14f, dx = 0, dy = 0)
            engine.step(0.1f)
        }
        assertEquals(ChaserWaveMode.CHASE, engine.waveMode)

        // Test left-to-right warp tunnel wrap on row 14
        engine.forceSetRunnerForTest(col = 0.05f, row = 14f, dx = -1, dy = 0)
        engine.step(0.1f)
        assertTrue("Runner exiting left tunnel should wrap to right side", engine.runnerCol > 25f)
    }

    @Test
    fun `PacGridEngine spawns Bonus Neon Fruit at 70 dots and buffers queued intersection turns`() {
        val engine = PacGridEngine()
        engine.startNewSession(1080, 1920, 2f, 0)

        // Set 69 dots eaten, then eat 70th pellet at (1, 1)
        engine.forceSetDotsCountForTest(eaten = 69, remaining = 100)
        engine.setTileForTest(1, 1, PacGridEngine.TILE_PELLET)
        engine.forceSetRunnerForTest(1f, 1f, dx = 1, dy = 0)
        engine.step(0.02f)

        assertEquals(70, engine.dotsEatenThisLevel)
        assertNotNull("Bonus fruit must spawn at 70 dots", engine.activeFruit)

        // Queued turn buffering: moving right toward intersection at (6, 5), queue DOWN (0, 1)
        engine.forceSetRunnerForTest(col = 5.85f, row = 5f, dx = 1, dy = 0)
        engine.queueDirection(0, 1)
        engine.step(0.04f)
        assertEquals("Buffered turn should engage down corridor at intersection", 0, engine.runnerDx)
        assertEquals(1, engine.runnerDy)
    }
}
