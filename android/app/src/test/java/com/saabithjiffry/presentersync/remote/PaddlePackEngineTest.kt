package com.saabithjiffry.presentersync.remote

import com.saabithjiffry.presentersync.remote.ui.arcade.ArcadeVaultManager
import com.saabithjiffry.presentersync.remote.ui.arcade.BrickBreakerEngine
import com.saabithjiffry.presentersync.remote.ui.arcade.BrickDropKind
import com.saabithjiffry.presentersync.remote.ui.arcade.BrickOrb
import com.saabithjiffry.presentersync.remote.ui.arcade.CyberPongEngine
import com.saabithjiffry.presentersync.remote.ui.arcade.PaddleGamePhase
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs
import kotlin.random.Random

class PaddlePackEngineTest {

    @Test
    fun vaultCatalog_registersBrickBreakerAndCyberPong() {
        val ids = ArcadeVaultManager.games.map { it.id }
        assertTrue(ids.contains("brick_breaker"))
        assertTrue(ids.contains("cyber_pong"))
        val bb = ArcadeVaultManager.games.first { it.id == "brick_breaker" }
        val cp = ArcadeVaultManager.games.first { it.id == "cyber_pong" }
        assertEquals("SECTOR Z-03", bb.badge)
        assertEquals("SECTOR Z-04", cp.badge)
    }

    @Test
    fun brickBreaker_armoredBricks_multiball_widePaddle_laser_andWaveAdvance() {
        var bestScore = 0
        val eng = BrickBreakerEngine(random = Random(42)) { newBest -> bestScore = newBest }
        eng.startNewSession(
            widthPx = 1080,
            heightPx = 1920,
            screenDensity = 2f,
            initialHighScore = 0,
            clearInitialBricks = true
        )
        assertEquals(PaddleGamePhase.PLAYING, eng.phase)
        assertEquals(1, eng.orbs.size)
        assertTrue(eng.orbs.first().stuck)

        // 1. Armored brick hp=3 -> 2 -> 1 -> shatter + guaranteed MULTIBALL drop
        eng.spawnBrick(380f, 360f, 120f, 40f, hp = 3, guaranteedDrop = BrickDropKind.MULTIBALL)
        eng.spawnBrick(820f, 360f, 120f, 40f, hp = 1) // keep second brick so wave stays at 1

        eng.orbs[0] = BrickOrb(440f, 412f, 0f, -500f, eng.orbs[0].radius, stuck = false)
        eng.step(0.02f)
        assertEquals(2, eng.bricks.first().hp)
        assertTrue("Orb should bounce downward off brick", eng.orbs[0].vy > 0f)

        eng.orbs[0] = BrickOrb(440f, 412f, 0f, -500f, eng.orbs[0].radius, stuck = false)
        eng.step(0.02f)
        assertEquals(1, eng.bricks.first().hp)

        eng.orbs[0] = BrickOrb(440f, 412f, 0f, -500f, eng.orbs[0].radius, stuck = false)
        eng.step(0.02f)
        assertEquals(1, eng.bricks.size)
        assertEquals(1, eng.drops.size)
        assertEquals(BrickDropKind.MULTIBALL, eng.drops.first().kind)
        assertTrue(eng.score >= 120)

        // 2. Catch MULTIBALL -> splits 1 orb into 3 orbs
        val padCenterX = eng.paddleX + eng.paddleW * 0.5f
        eng.drops.clear()
        eng.spawnDrop(BrickDropKind.MULTIBALL, padCenterX, eng.paddleY)
        eng.step(0.02f)
        assertEquals(3, eng.orbs.size)

        // 3. Catch WIDE_PADDLE -> expands paddle width
        val baseW = eng.paddleW
        eng.spawnDrop(BrickDropKind.WIDE_PADDLE, padCenterX, eng.paddleY)
        eng.step(0.02f)
        assertTrue(eng.wideTimerSec > 5f)
        assertTrue(eng.paddleW > baseW * 1.4f)

        // 4. Catch LASER -> fire laser bolts -> destroy last brick -> advance to Wave 2
        eng.spawnDrop(BrickDropKind.LASER, padCenterX, eng.paddleY)
        eng.step(0.02f)
        assertTrue(eng.laserTimerSec > 5f)

        eng.bricks.clear()
        eng.spawnBrick(eng.paddleX, eng.paddleY - 90f, eng.paddleW, 36f, hp = 1)
        assertTrue(eng.launchOrFire())
        assertEquals(2, eng.lasers.size)
        repeat(10) { eng.step(0.016f) }
        assertEquals(2, eng.wave)
        assertTrue(eng.bricks.size >= 30)
        assertEquals(eng.highScore, bestScore)
    }

    @Test
    fun cyberPong_spinCurve_adaptiveAi_twoPlayerSplit_andFirstToSevenWin() {
        var bestScore = 0
        val eng = CyberPongEngine(random = Random(99)) { newBest -> bestScore = newBest }
        eng.startNewSession(
            widthPx = 1920,
            heightPx = 1080,
            screenDensity = 2f,
            initialHighScore = 0,
            preserveTwoPlayer = false
        )
        assertEquals(PaddleGamePhase.PLAYING, eng.phase)
        assertFalse(eng.twoPlayerMode)

        // 1. Left paddle bounce transfers spin and curves puck vertically via Magnus effect
        eng.leftPaddleY = 400f
        eng.leftTouchActive = true
        eng.leftTouchTargetY = 320f // moving rapidly upward
        eng.puck = BrickOrb(
            x = eng.leftPaddleX + eng.paddleW + eng.puck.radius - 2f,
            y = 420f,
            vx = -650f,
            vy = 0f,
            radius = eng.puck.radius,
            spin = 0f
        )
        eng.step(0.025f)
        assertTrue(eng.puck.vx > 0f)
        assertEquals(1, eng.rally)
        assertTrue("Expected non-zero spin transfer, got ${eng.puck.spin}", abs(eng.puck.spin) > 80f)

        val vy0 = eng.puck.vy
        repeat(8) { eng.step(0.016f) }
        assertTrue("Magnus spin should curve puck vy", abs(eng.puck.vy - vy0) > 12f)

        // 2. Adaptive 1P AI tracks incoming puck downward
        val startRightY = eng.rightPaddleY
        eng.puck = BrickOrb(960f, startRightY + 340f, 680f, 0f, eng.puck.radius)
        repeat(10) { eng.step(0.02f) }
        assertTrue("1P AI should move right paddle downward toward puck", eng.rightPaddleY > startRightY + 30f)

        // 3. Toggle 2P Split-Screen Touch mode & verify simultaneous left/right touch tracking
        assertTrue(eng.toggleTwoPlayerMode())
        assertTrue(eng.twoPlayerMode)
        eng.leftTouchActive = true
        eng.leftTouchTargetY = 260f
        eng.rightTouchActive = true
        eng.rightTouchTargetY = 820f
        eng.step(0.02f)
        assertEquals(260f, eng.leftPaddleY + eng.paddleH * 0.5f, 2f)
        assertEquals(820f, eng.rightPaddleY + eng.paddleH * 0.5f, 2f)

        // 4. First to 7 wins the set
        eng.leftScore = 6
        eng.puck = BrickOrb(eng.worldWidth + eng.puck.radius - 2f, 540f, 700f, 0f, eng.puck.radius)
        eng.step(0.025f)
        assertEquals(7, eng.leftScore)
        assertEquals(PaddleGamePhase.GAME_OVER, eng.phase)
        assertEquals("PLAYER 1", eng.winnerLabel)
        assertTrue(bestScore >= 450)
    }
}
