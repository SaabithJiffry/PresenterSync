package com.saabithjiffry.presentersync.remote.ui.arcade

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SpacePinballEngineTest {
    private fun stepFor(engine: SpacePinballEngine, totalSec: Float) {
        var rem = totalSec
        while (rem > 0f) {
            val dt = minOf(0.0166667f, rem)
            engine.step(dt)
            rem -= dt
        }
    }

    @Test
    fun plungerLaunchAndOneWayGateBlockReEntry() {
        val eng = SpacePinballEngine()
        eng.startNewSession(1080, 1920, 2f, 0)
        assertTrue(eng.ballInShooter)

        eng.releasePlunger(1f)
        stepFor(eng, 0.65f)
        assertFalse("Ball should exit shooter lane over top arch", eng.ballInShooter)

        eng.setBallForTest(346f, 118f, 520f, 0f, inShooter = false)
        stepFor(eng, 0.05f)
        assertTrue("One-way gate should block re-entry", eng.ballX <= 360f && eng.ballVx < 0f)
    }

    @Test
    fun sweptFlipperPreventsTunneling() {
        val eng = SpacePinballEngine()
        eng.startNewSession(1080, 1920, 2f, 0)
        eng.setFlippers(leftDown = false, rightDown = false)
        stepFor(eng, 0.15f)

        eng.setBallForTest(155f, 616f, 0f, 880f, inShooter = false)
        eng.setFlippers(leftDown = true, rightDown = false)
        stepFor(eng, 0.06f)
        assertTrue("Ball must bounce upward off swept flipper", eng.ballVy < 0f && eng.ballY < 645f)
    }

    @Test
    fun bumpersDropTargetsRankAndTiltWork() {
        var latestHi = 0
        val eng = SpacePinballEngine(onNewHighScore = { latestHi = it })
        eng.startNewSession(1080, 1920, 2f, 0)

        eng.setBallForTest(142f, 204f, 0f, 250f, inShooter = false)
        stepFor(eng, 0.04f)
        assertTrue("Bumper hit awards score", eng.score > 0 && latestHi == eng.score)

        eng.advanceMissionForTest(6)
        assertEquals("Ensign", eng.rankName())

        val multBefore = eng.multiplier
        eng.setBallForTest(62f, 268f, -240f, 0f, inShooter = false)
        stepFor(eng, 0.04f)
        eng.setBallForTest(62f, 305f, -240f, 0f, inShooter = false)
        stepFor(eng, 0.04f)
        eng.setBallForTest(62f, 342f, -240f, 0f, inShooter = false)
        stepFor(eng, 0.04f)
        assertTrue("Clearing 3-bank drop targets increments multiplier", eng.multiplier > multBefore)

        eng.setBallForTest(200f, 350f, 0f, 0f, inShooter = false)
        assertTrue(eng.nudge())
        assertTrue(eng.nudge())
        assertFalse(eng.tilted)
        assertTrue(eng.nudge())
        assertTrue("3rd nudge triggers TILT lockout", eng.tilted)
    }

    @Test
    fun vaultRegistersSectorZ10Pinball() {
        assertTrue(ArcadeVaultManager.games.any { it.id == "pinball" && it.badge == "SECTOR Z-10" })
    }
}
