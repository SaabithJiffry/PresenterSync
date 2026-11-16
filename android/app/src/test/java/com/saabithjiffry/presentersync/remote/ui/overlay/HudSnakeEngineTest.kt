package com.saabithjiffry.presentersync.remote.ui.overlay

import android.view.KeyEvent
import com.saabithjiffry.presentersync.remote.config.DeviceProfileMode
import com.saabithjiffry.presentersync.remote.config.FormFactorClass
import com.saabithjiffry.presentersync.remote.config.FormFactorResolver
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

class HudSnakeEngineTest {

    private fun phoneFormFactor() = FormFactorResolver.resolve(
        mode = DeviceProfileMode.AUTO,
        widthDp = 360,
        heightDp = 800,
        smallestWidthDp = 360
    )

    private fun smallPhoneFormFactor() = FormFactorResolver.resolve(
        mode = DeviceProfileMode.PHONE,
        widthDp = 320,
        heightDp = 640,
        smallestWidthDp = 320
    )

    private fun smartBoardFormFactor() = FormFactorResolver.resolve(
        mode = DeviceProfileMode.SMART_BOARD,
        widthDp = 1920,
        heightDp = 1080,
        smallestWidthDp = 1080
    )

    @Test
    fun responsiveGridScalesCleanlyBetweenPhoneAndSmartBoard() {
        val phoneGrid = HudSnakeEngine.computeGridMetrics(
            workWidthPx = 720,
            workHeightPx = 1480,
            density = 2.0f,
            formFactor = phoneFormFactor(),
            hudScale = 1.0f
        )
        val tinyPhoneGrid = HudSnakeEngine.computeGridMetrics(
            workWidthPx = 640,
            workHeightPx = 1180,
            density = 2.0f,
            formFactor = smallPhoneFormFactor(),
            hudScale = 1.0f
        )
        val boardGrid = HudSnakeEngine.computeGridMetrics(
            workWidthPx = 3840,
            workHeightPx = 2160,
            density = 2.0f,
            formFactor = smartBoardFormFactor(),
            hudScale = 2.5f
        )

        assertTrue("Phone portrait should use compact 2-row scoreboard", phoneGrid.isCompactScoreboard)
        assertTrue("Tiny phone must still fit >= 11 cols & >= 14 rows", tinyPhoneGrid.cols >= 11 && tinyPhoneGrid.rows >= 14)
        assertFalse("Smart board should use wide single-row scoreboard", boardGrid.isCompactScoreboard)
        assertTrue(
            "Smart board cells (${boardGrid.cellPx}) should exceed compact phone cells (${tinyPhoneGrid.cellPx})",
            boardGrid.cellPx > tinyPhoneGrid.cellPx
        )
        assertTrue(boardGrid.cols >= 16 && boardGrid.rows >= 12)
    }

    @Test
    fun swipeKeyboardAndDpadInputsMapAccurately() {
        assertEquals(1 to 0, HudSnakeEngine.decodeSwipeDirection(80f, 15f, 48f))
        assertEquals(-1 to 0, HudSnakeEngine.decodeSwipeDirection(-90f, 20f, 48f))
        assertEquals(0 to 1, HudSnakeEngine.decodeSwipeDirection(10f, 75f, 48f))
        assertEquals(0 to -1, HudSnakeEngine.decodeSwipeDirection(-12f, -64f, 48f))
        assertNull("Below min swipe threshold must ignore jitter", HudSnakeEngine.decodeSwipeDirection(20f, 15f, 48f))

        assertEquals(SnakeInputCommand.Direction(0, -1), HudSnakeEngine.mapKeyCodeToCommand(KeyEvent.KEYCODE_DPAD_UP))
        assertEquals(SnakeInputCommand.Direction(0, 1), HudSnakeEngine.mapKeyCodeToCommand(KeyEvent.KEYCODE_S))
        assertEquals(SnakeInputCommand.Direction(-1, 0), HudSnakeEngine.mapKeyCodeToCommand(KeyEvent.KEYCODE_A))
        assertEquals(SnakeInputCommand.Direction(1, 0), HudSnakeEngine.mapKeyCodeToCommand(KeyEvent.KEYCODE_D))
        assertEquals(SnakeInputCommand.ToggleEdgeMode, HudSnakeEngine.mapKeyCodeToCommand(KeyEvent.KEYCODE_E))
        assertEquals(SnakeInputCommand.ToggleEdgeMode, HudSnakeEngine.mapKeyCodeToCommand(KeyEvent.KEYCODE_BUTTON_Y))
        assertEquals(SnakeInputCommand.PauseOrRestart, HudSnakeEngine.mapKeyCodeToCommand(KeyEvent.KEYCODE_BUTTON_A))
        assertEquals(SnakeInputCommand.Exit, HudSnakeEngine.mapKeyCodeToCommand(KeyEvent.KEYCODE_BUTTON_B))
        assertEquals(SnakeInputCommand.Exit, HudSnakeEngine.mapKeyCodeToCommand(KeyEvent.KEYCODE_BACK))

        assertEquals(1 to 0, HudSnakeEngine.decodeJoystickAxis(0.1f, 0f, 1.0f, 0f))
        assertEquals(0 to -1, HudSnakeEngine.decodeJoystickAxis(0f, -0.8f, 0f, 0f))
        assertNull(HudSnakeEngine.decodeJoystickAxis(0.15f, -0.20f, 0f, 0f))
    }

    @Test
    fun morphTransitionDirectionQueueEatingAndBestScorePersist() {
        var persistedBest = 0
        val engine = HudSnakeEngine(random = Random(42)) { newBest -> persistedBest = newBest }
        val ff = phoneFormFactor()

        engine.start(
            workWidthPx = 1080,
            workHeightPx = 2160,
            density = 3.0f,
            formFactor = ff,
            hudScale = 1.0f,
            initialHighScore = 20,
            pillLeftPx = 800f,
            pillTopPx = 1800f,
            pillWidthPx = 220f,
            pillHeightPx = 120f,
            pillColorArgb = 0xFF22C55E.toInt(),
            nowNs = 1_000_000_000L,
            skipMorph = false
        )
        assertEquals(SnakePhase.MORPH, engine.phase)
        assertEquals(HudSnakeEngine.INITIAL_LENGTH, engine.morphSeeds.size)
        assertEquals(HudSnakeEngine.INITIAL_LENGTH, engine.snake.size)

        // Advance past 360ms morph
        engine.tick(1_400_000_000L)
        assertEquals(SnakePhase.PLAYING, engine.phase)

        // Force deterministic board layout for eat -> growth -> high score -> wrap/wall tests
        engine.forceSnakeForTest(
            cells = listOf(
                SnakeCell(6, 10),
                SnakeCell(5, 10),
                SnakeCell(4, 10),
                SnakeCell(3, 10),
                SnakeCell(2, 10)
            ),
            dx = 1,
            dy = 0,
            targetFood = SnakeFood(7, 10, SnakeFoodKind.BONUS, bornNs = 2_000_000_000L)
        )

        // Reject immediate 180-degree reversal, accept valid 90-degree turn queue
        assertFalse(engine.queueDirection(-1, 0))
        engine.stepSimulation(2_100_000_000L)
        assertEquals(30, engine.score)
        assertEquals(30, engine.highScore)
        assertEquals(30, persistedBest)
        assertTrue(engine.bestBeaten)
        assertEquals(20, engine.highScore.coerceAtMost(20)) // sanity check compilation
        assertEquals(SnakeCell(7, 10), engine.snake.first())
        assertTrue(engine.popups.isNotEmpty())
        assertTrue(engine.eatEffects.isNotEmpty())

        // Turn down, step, verify pause & resume preserve phase cleanly
        assertTrue(engine.queueDirection(0, 1))
        engine.stepSimulation(2_300_000_000L)
        assertEquals(SnakeCell(7, 11), engine.snake.first())

        engine.togglePause(2_350_000_000L)
        assertEquals(SnakePhase.PAUSED, engine.phase)
        engine.togglePause(2_500_000_000L)
        assertEquals(SnakePhase.PLAYING, engine.phase)

        // Toroidal wrap mode vs wall collision mode
        engine.toggleEdgeMode()
        assertTrue(engine.edgeWrap)
        val g = engine.grid
        engine.forceSnakeForTest(
            cells = listOf(
                SnakeCell(g.cols - 1, 8),
                SnakeCell(g.cols - 2, 8),
                SnakeCell(g.cols - 3, 8)
            ),
            dx = 1,
            dy = 0,
            targetFood = SnakeFood(4, 4, SnakeFoodKind.NORMAL, 3_000_000_000L)
        )
        engine.stepSimulation(3_100_000_000L)
        assertEquals(SnakePhase.PLAYING, engine.phase)
        assertEquals(0, engine.snake.first().col)
        val pieces = engine.buildInterpolatedPieces(0.7f)
        assertTrue("Toroidal edge crossing should split ribbon cleanly across wall", pieces.size >= 2)

        // Disable wrap -> hitting edge triggers GAME_OVER cleanly
        engine.toggleEdgeMode()
        assertFalse(engine.edgeWrap)
        engine.forceSnakeForTest(
            cells = listOf(
                SnakeCell(0, 8),
                SnakeCell(1, 8),
                SnakeCell(2, 8)
            ),
            dx = -1,
            dy = 0
        )
        engine.stepSimulation(3_200_000_000L)
        assertEquals(SnakePhase.GAME_OVER, engine.phase)
        assertEquals(SnakeDeathReason.WALL, engine.deathReason)

        // Check FormFactor enum coverage
        assertEquals(FormFactorClass.LARGE_BOARD, smartBoardFormFactor().deviceClass)
    }
}
