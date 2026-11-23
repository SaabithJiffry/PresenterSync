package com.saabithjiffry.presentersync.remote

import com.saabithjiffry.presentersync.remote.ui.arcade.ArcadeVaultManager
import com.saabithjiffry.presentersync.remote.ui.arcade.BlockDropEngine
import com.saabithjiffry.presentersync.remote.ui.arcade.BlockDropPhase
import com.saabithjiffry.presentersync.remote.ui.arcade.BlockKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

class BlockDropEngineTest {

    @Test
    fun sevenBag_producesAllSevenUniqueKindsPerBag() {
        val eng = BlockDropEngine(random = Random(42))
        eng.startNewSession(1080, 1920, 2f, 0)
        eng.clearBagForTest()

        repeat(2) {
            val seen = mutableSetOf<BlockKind>()
            repeat(7) {
                seen.add(eng.drawBagForTest())
            }
            assertEquals(7, seen.size)
        }
    }

    @Test
    fun srsWallKick_succeedsForIAndTPiecesAgainstWalls() {
        val eng = BlockDropEngine(random = Random(7))
        eng.startNewSession(1080, 1920, 2f, 0)

        // I piece against left wall: rot 1 -> 0 kicks (+2, 0) to x=0
        eng.spawnPieceForTest(BlockKind.I, -2, 5, 1)
        assertTrue(eng.rotate(-1))
        assertEquals(0, eng.curRot)
        assertEquals(0, eng.curX)

        // I piece against right wall: rot 3 -> 2 kicks (-2, 0) to x=6
        eng.spawnPieceForTest(BlockKind.I, 8, 5, 3)
        assertTrue(eng.rotate(-1))
        assertEquals(2, eng.curRot)
        assertEquals(6, eng.curX)

        // T piece against left wall: rot 1 -> 0 kicks (+1, 0) to x=0
        eng.spawnPieceForTest(BlockKind.T, -1, 5, 1)
        assertTrue(eng.rotate(-1))
        assertEquals(0, eng.curRot)
        assertEquals(0, eng.curX)
    }

    @Test
    fun hold_swapsPieceAndBlocksDoubleHoldUntilLock() {
        val eng = BlockDropEngine(random = Random(11))
        eng.startNewSession(1080, 1920, 2f, 0)

        val first = eng.curKind
        val next = eng.nextPreview(1).first()
        assertTrue(eng.hold())
        assertEquals(first, eng.holdKind)
        assertEquals(next, eng.curKind)
        assertTrue(eng.holdUsed)

        // Second hold before lock must fail
        assertFalse(eng.hold())
        assertEquals(next, eng.curKind)
    }

    @Test
    fun ghostY_landsAtLowestValidRow_andHardDropClearsTetrisAndAdvancesLevel() {
        var latestBest = 0
        val eng = BlockDropEngine(random = Random(99)) { latestBest = it }
        eng.startNewSession(1080, 1920, 2f, 0)

        eng.spawnPieceForTest(BlockKind.O, 4, 0, 0)
        assertEquals(18, eng.computeGhostY())

        // 4-line Tetris via vertical I at col 0
        for (r in 16..19) {
            eng.fillRowForTest(r, skipCol = 0)
        }
        eng.spawnPieceForTest(BlockKind.I, -2, 0, 1)
        eng.hardDrop()
        assertEquals(4, eng.lines)
        assertTrue(eng.score >= 800)
        assertEquals(eng.score, latestBest)

        // Clear 6 more single lines -> 10 lines -> Level 2
        for (i in 1..6) {
            eng.fillRowForTest(19, skipCol = i)
            eng.spawnPieceForTest(BlockKind.I, i - 2, 0, 1)
            eng.hardDrop()
        }
        assertTrue(eng.lines >= 10)
        assertTrue(eng.level >= 2)
        assertEquals(BlockDropPhase.PLAYING, eng.phase)
    }

    @Test
    fun vault_registersBlockDrop_sectorZ09() {
        val entry = ArcadeVaultManager.games.firstOrNull { it.id == "block_drop" }
        assertTrue(entry != null && entry.badge == "SECTOR Z-09" && entry.title == "Neon Block Drop")
    }
}
