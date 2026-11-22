package com.saabithjiffry.presentersync.remote.ui.arcade

import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.random.Random

// ============================================================================
// SECTOR Z-06: NEON LIGHT CYCLES (TRON) ENGINE
// ============================================================================

enum class LightCyclesPhase {
    RUNNING,
    PAUSED,
    ROUND_WON,
    GAME_OVER
}

data class GridCell(val col: Int, val row: Int)

data class CycleParticle(
    var x: Float,
    var y: Float,
    var vx: Float,
    var vy: Float,
    var lifeSec: Float,
    val maxLifeSec: Float,
    val isPlayerColor: Boolean
)

/**
 * Pure Kotlin simulation engine for Sector Z-06: Neon Light Cycles (TRON).
 * Zero dependencies on android.graphics.RectF so JVM unit tests run without Robolectric.
 */
class LightCyclesEngine(
    private val onNewHighScore: (Int) -> Unit = {},
    private val random: Random = Random.Default
) {
    var cols: Int = 64
        private set
    var rows: Int = 40
        private set

    var viewportWidthPx: Int = 1280
        private set
    var viewportHeightPx: Int = 720
        private set
    var density: Float = 2f
        private set

    var phase: LightCyclesPhase = LightCyclesPhase.RUNNING
        private set

    var score: Int = 0
        private set
    var highScore: Int = 0
        private set
    var roundStreak: Int = 0
        private set

    var playerCol: Int = 12
        private set
    var playerRow: Int = 20
        private set
    var playerDx: Int = 1
        private set
    var playerDy: Int = 0
        private set
    private var queuedDx: Int = 1
    private var queuedDy: Int = 0

    var aiCol: Int = 51
        private set
    var aiRow: Int = 20
        private set
    var aiDx: Int = -1
        private set
    var aiDy: Int = 0
        private set

    var boostActive: Boolean = false
        private set
    var boostEnergy: Float = 100f
        private set

    // 0 = empty, 1 = player trail, 2 = AI trail
    private var grid: IntArray = IntArray(cols * rows)
    val playerTrail: MutableList<GridCell> = mutableListOf()
    val aiTrail: MutableList<GridCell> = mutableListOf()
    val particles: MutableList<CycleParticle> = mutableListOf()

    private var playerStepAccumSec: Float = 0f
    private var aiStepAccumSec: Float = 0f
    private var roundTransitionTimerSec: Float = 0f

    companion object {
        const val BASE_STEP_INTERVAL_SEC = 0.055f
        const val BOOST_DRAIN_PER_SEC = 42f
        const val BOOST_RECHARGE_PER_SEC = 18f
        const val MIN_BOOST_TO_ACTIVATE = 12f
    }

    fun startNewSession(
        widthPx: Int,
        heightPx: Int,
        screenDensity: Float,
        initialHighScore: Int,
        gridCols: Int = 64,
        gridRows: Int = 40
    ) {
        viewportWidthPx = max(320, widthPx)
        viewportHeightPx = max(320, heightPx)
        density = screenDensity.coerceIn(0.75f, 5f)
        cols = gridCols.coerceIn(24, 120)
        rows = gridRows.coerceIn(18, 80)
        highScore = max(highScore, initialHighScore)
        score = 0
        roundStreak = 0
        particles.clear()
        resetArenaForRound(keepPhaseRunning = true)
    }

    fun resetArenaForRound(keepPhaseRunning: Boolean = true) {
        grid = IntArray(cols * rows)
        playerTrail.clear()
        aiTrail.clear()

        playerCol = cols / 4
        playerRow = rows / 2
        playerDx = 1
        playerDy = 0
        queuedDx = 1
        queuedDy = 0

        aiCol = (cols * 3) / 4
        aiRow = rows / 2
        aiDx = -1
        aiDy = 0

        setCell(playerCol, playerRow, 1)
        playerTrail.add(GridCell(playerCol, playerRow))
        setCell(aiCol, aiRow, 2)
        aiTrail.add(GridCell(aiCol, aiRow))

        boostActive = false
        boostEnergy = 100f
        playerStepAccumSec = 0f
        aiStepAccumSec = 0f
        roundTransitionTimerSec = 0f
        if (keepPhaseRunning) {
            phase = LightCyclesPhase.RUNNING
        }
    }

    fun updateDisplayMetrics(widthPx: Int, heightPx: Int, screenDensity: Float) {
        viewportWidthPx = max(320, widthPx)
        viewportHeightPx = max(320, heightPx)
        density = screenDensity.coerceIn(0.75f, 5f)
    }

    fun stop() {
        phase = LightCyclesPhase.PAUSED
        boostActive = false
    }

    fun togglePause() {
        phase = when (phase) {
            LightCyclesPhase.RUNNING -> LightCyclesPhase.PAUSED
            LightCyclesPhase.PAUSED -> LightCyclesPhase.RUNNING
            else -> phase
        }
    }

    fun setBoost(active: Boolean) {
        if (active && boostEnergy >= MIN_BOOST_TO_ACTIVATE && phase == LightCyclesPhase.RUNNING) {
            boostActive = true
        } else if (!active) {
            boostActive = false
        }
    }

    fun toggleBoost() {
        setBoost(!boostActive)
    }

    /**
     * Queues a 90-degree turn; 180-degree self-reversal is rejected.
     */
    fun steer(dx: Int, dy: Int): Boolean {
        if (dx == 0 && dy == 0) return false
        if (dx != 0 && dy != 0) return false
        val normDx = dx.coerceIn(-1, 1)
        val normDy = dy.coerceIn(-1, 1)
        // Reject 180-degree reversal against current travel direction
        if (normDx == -playerDx && normDy == -playerDy) return false
        queuedDx = normDx
        queuedDy = normDy
        return true
    }

    fun getCell(col: Int, row: Int): Int {
        if (col !in 0 until cols || row !in 0 until rows) return -1
        return grid[row * cols + col]
    }

    private fun setCell(col: Int, row: Int, value: Int) {
        if (col in 0 until cols && row in 0 until rows) {
            grid[row * cols + col] = value
        }
    }

    fun isCellOccupied(col: Int, row: Int): Boolean {
        if (col !in 0 until cols || row !in 0 until rows) return true
        return grid[row * cols + col] != 0
    }

    fun step(dtSec: Float) {
        val clampedDt = dtSec.coerceIn(0.001f, 0.1f)
        stepParticles(clampedDt)

        if (phase == LightCyclesPhase.ROUND_WON) {
            roundTransitionTimerSec -= clampedDt
            if (roundTransitionTimerSec <= 0f) {
                resetArenaForRound(keepPhaseRunning = true)
            }
            return
        }
        if (phase != LightCyclesPhase.RUNNING) return

        // Update Turbo Boost energy
        if (boostActive) {
            boostEnergy = (boostEnergy - BOOST_DRAIN_PER_SEC * clampedDt).coerceAtLeast(0f)
            if (boostEnergy <= 0f) {
                boostActive = false
            }
        } else {
            boostEnergy = (boostEnergy + BOOST_RECHARGE_PER_SEC * clampedDt).coerceAtMost(100f)
        }

        val speedFactor = (1f + roundStreak * 0.05f).coerceAtMost(1.45f)
        val baseInterval = BASE_STEP_INTERVAL_SEC / speedFactor
        val playerInterval = if (boostActive) baseInterval * 0.5f else baseInterval

        playerStepAccumSec += clampedDt
        aiStepAccumSec += clampedDt

        while (playerStepAccumSec >= playerInterval && phase == LightCyclesPhase.RUNNING) {
            playerStepAccumSec -= playerInterval
            advancePlayerOneCell()
        }

        while (aiStepAccumSec >= baseInterval && phase == LightCyclesPhase.RUNNING) {
            aiStepAccumSec -= baseInterval
            advanceAiOneCell()
        }
    }

    private fun advancePlayerOneCell() {
        if (queuedDx != -playerDx || queuedDy != -playerDy) {
            playerDx = queuedDx
            playerDy = queuedDy
        }
        val nextCol = playerCol + playerDx
        val nextRow = playerRow + playerDy
        if (isCellOccupied(nextCol, nextRow)) {
            spawnCrashParticles(playerCol, playerRow, isPlayer = true)
            phase = LightCyclesPhase.GAME_OVER
            boostActive = false
            return
        }
        playerCol = nextCol
        playerRow = nextRow
        setCell(playerCol, playerRow, 1)
        playerTrail.add(GridCell(playerCol, playerRow))
        addScore(if (boostActive) 4 else 2)
    }

    private fun advanceAiOneCell() {
        val chosen = chooseAiDirection(aiCol, aiRow, aiDx, aiDy)
        aiDx = chosen.first
        aiDy = chosen.second
        val nextCol = aiCol + aiDx
        val nextRow = aiRow + aiDy
        if (isCellOccupied(nextCol, nextRow)) {
            spawnCrashParticles(aiCol, aiRow, isPlayer = false)
            roundStreak += 1
            addScore(250 + roundStreak * 50)
            phase = LightCyclesPhase.ROUND_WON
            roundTransitionTimerSec = 1.15f
            boostActive = false
            return
        }
        aiCol = nextCol
        aiRow = nextRow
        setCell(aiCol, aiRow, 2)
        aiTrail.add(GridCell(aiCol, aiRow))
    }

    /**
     * Flood-fill / open-corridor evaluator for the AI cycle so it avoids dead-ends and walls.
     */
    fun chooseAiDirection(fromCol: Int, fromRow: Int, curDx: Int, curDy: Int): Pair<Int, Int> {
        val dirs = listOf(
            curDx to curDy,
            -curDy to curDx,
            curDy to -curDx
        )
        var bestDir = curDx to curDy
        var bestScore = -1
        for (dir in dirs) {
            val nc = fromCol + dir.first
            val nr = fromRow + dir.second
            if (isCellOccupied(nc, nr)) continue
            val reach = floodFillReachableCount(nc, nr, maxBudget = 180)
            val runway = measureStraightRunway(fromCol, fromRow, dir.first, dir.second)
            val forwardBonus = if (dir.first == curDx && dir.second == curDy) 4 else 0
            val totalScore = reach * 4 + runway * 2 + forwardBonus
            if (totalScore > bestScore) {
                bestScore = totalScore
                bestDir = dir
            }
        }
        return bestDir
    }

    fun floodFillReachableCount(startCol: Int, startRow: Int, maxBudget: Int = 180): Int {
        if (isCellOccupied(startCol, startRow)) return 0
        val visited = BooleanArray(cols * rows)
        val queue = IntArray(maxBudget + 4)
        var head = 0
        var tail = 0
        val startIdx = startRow * cols + startCol
        visited[startIdx] = true
        queue[tail++] = startIdx

        val dCols = intArrayOf(1, -1, 0, 0)
        val dRows = intArrayOf(0, 0, 1, -1)

        while (head < tail && tail < maxBudget) {
            val curr = queue[head++]
            val cr = curr / cols
            val cc = curr % cols
            for (i in 0 until 4) {
                val nc = cc + dCols[i]
                val nr = cr + dRows[i]
                if (nc !in 0 until cols || nr !in 0 until rows) continue
                val nIdx = nr * cols + nc
                if (!visited[nIdx] && grid[nIdx] == 0) {
                    visited[nIdx] = true
                    queue[tail++] = nIdx
                    if (tail >= maxBudget) break
                }
            }
        }
        return tail
    }

    private fun measureStraightRunway(fromCol: Int, fromRow: Int, dx: Int, dy: Int): Int {
        var steps = 0
        var c = fromCol + dx
        var r = fromRow + dy
        while (!isCellOccupied(c, r) && steps < 25) {
            steps++
            c += dx
            r += dy
        }
        return steps
    }

    private fun addScore(points: Int) {
        if (points <= 0) return
        score += points
        if (score > highScore) {
            highScore = score
            onNewHighScore(highScore)
        }
    }

    private fun spawnCrashParticles(col: Int, row: Int, isPlayer: Boolean) {
        val nx = (col + 0.5f) / cols.toFloat()
        val ny = (row + 0.5f) / rows.toFloat()
        for (i in 0 until 20) {
            val angle = (i / 20f) * (Math.PI.toFloat() * 2f) + random.nextFloat() * 0.25f
            val speed = 0.12f + random.nextFloat() * 0.25f
            particles.add(
                CycleParticle(
                    x = nx,
                    y = ny,
                    vx = cos(angle) * speed,
                    vy = sin(angle) * speed,
                    lifeSec = 0.65f,
                    maxLifeSec = 0.65f,
                    isPlayerColor = isPlayer
                )
            )
        }
    }

    private fun stepParticles(dtSec: Float) {
        val it = particles.iterator()
        while (it.hasNext()) {
            val p = it.next()
            p.x += p.vx * dtSec
            p.y += p.vy * dtSec
            p.lifeSec -= dtSec
            if (p.lifeSec <= 0f) {
                it.remove()
            }
        }
    }

    fun forceSetPositionsForTest(
        pCol: Int,
        pRow: Int,
        pDx: Int,
        pDy: Int,
        aCol: Int = aiCol,
        aRow: Int = aiRow,
        aDx: Int = aiDx,
        aDy: Int = aiDy
    ) {
        playerCol = pCol
        playerRow = pRow
        playerDx = pDx
        playerDy = pDy
        queuedDx = pDx
        queuedDy = pDy
        aiCol = aCol
        aiRow = aRow
        aiDx = aDx
        aiDy = aDy
    }

    fun forceSetTrailCellForTest(col: Int, row: Int, owner: Int = 1) {
        setCell(col, row, owner)
    }
}

// ============================================================================
// SECTOR Z-07: AUTHENTIC NEON PAC-GRID ENGINE
// ============================================================================

enum class PacGridPhase {
    RUNNING,
    PAUSED,
    GAME_OVER
}

enum class ChaserPersonality {
    BLINKY, // Shadow (Red): targets runner's exact tile
    PINKY,  // Speedy (Pink): ambushes 4 tiles ahead of runner
    INKY,   // Bashful (Cyan): vector reflection from Blinky through 2 tiles ahead of runner
    CLYDE   // Pokey (Orange): targets runner when dist > 8 tiles, else bottom-left scatter corner
}

enum class ChaserWaveMode {
    SCATTER,
    CHASE
}

enum class ChaserState {
    NORMAL,
    FRIGHTENED,
    EYES
}

data class PacChaser(
    val personality: ChaserPersonality,
    var col: Float,
    var row: Float,
    var dx: Int,
    var dy: Int,
    var state: ChaserState = ChaserState.NORMAL,
    var lastDecisionCol: Int = -1,
    var lastDecisionRow: Int = -1
)

data class BonusFruit(
    val points: Int,
    val label: String,
    var remainingSec: Float,
    val col: Int = PacGridEngine.PEN_EXIT_COL,
    val row: Int = 17
)

/**
 * Pure Kotlin simulation engine for Sector Z-07: Authentic Neon Pac-Grid.
 * Implements a 28x31 symmetric arcade maze, standard pellets (+10), 4 corner Power Orbs (+50),
 * 7.0s Frightened Mode with 200->400->800->1600 combos, returning EYES state to the ghost pen,
 * 4 classic chaser target personalities, timed Scatter/Chase wave scheduler, left/right warp
 * tunnel wrap, bonus fruits at 70 & 170 dots, and queued intersection turn buffering.
 */
class PacGridEngine(
    private val onNewHighScore: (Int) -> Unit = {}
) {
    companion object {
        const val MAZE_COLS = 28
        const val MAZE_ROWS = 31

        const val TILE_EMPTY = 0
        const val TILE_WALL = 1
        const val TILE_PELLET = 2
        const val TILE_POWER_ORB = 3
        const val TILE_GHOST_GATE = 4

        const val PEN_COL = 13
        const val PEN_ROW = 14
        const val PEN_EXIT_COL = 13
        const val PEN_EXIT_ROW = 11
        const val TUNNEL_ROW = 14

        const val RUNNER_START_COL = 13
        const val RUNNER_START_ROW = 23

        const val FRIGHTENED_DURATION_SEC = 7.0f
        const val FRUIT_DURATION_SEC = 9.5f

        // Classic 28x31 symmetric layout:
        // '#' = wall, '.' = pellet, 'o' = power orb, '-' = ghost gate, ' ' = empty/tunnel/pen
        val MAZE_TEMPLATE: List<String> = listOf(
            "############################",
            "#............##............#",
            "#.####.#####.##.#####.####.#",
            "#o####.#####.##.#####.####o#",
            "#.####.#####.##.#####.####.#",
            "#..........................#",
            "#.####.##.########.##.####.#",
            "#.####.##.########.##.####.#",
            "#......##....##....##......#",
            "######.##### ## #####.######",
            "     #.##### ## #####.#     ",
            "     #.##          ##.#     ",
            "     #.## ###--### ##.#     ",
            "######.## #      # ##.######",
            "      .   #      #   .      ",
            "######.## #      # ##.######",
            "     #.## ######## ##.#     ",
            "     #.##          ##.#     ",
            "     #.## ######## ##.#     ",
            "######.## ######## ##.######",
            "#............##............#",
            "#.####.#####.##.#####.####.#",
            "#.####.#####.##.#####.####.#",
            "#o..##.......  .......##..o#",
            "###.##.##.########.##.##.###",
            "###.##.##.########.##.##.###",
            "#......##....##....##......#",
            "#.##########.##.##########.#",
            "#.##########.##.##########.#",
            "#..........................#",
            "############################"
        )

        val FRUIT_TABLE: List<Pair<String, Int>> = listOf(
            "CHERRY" to 100,
            "STRAWBERRY" to 300,
            "PEACH" to 500,
            "APPLE" to 700,
            "GRAPES" to 1000,
            "GALAXIAN" to 2000,
            "BELL" to 3000,
            "KEY" to 5000
        )

        // Timed Scatter (7s/5s) <-> Chase (20s) wave schedule
        val WAVE_DURATIONS_SEC: FloatArray = floatArrayOf(
            7f, 20f, 7f, 20f, 5f, 20f, 5f
        )
    }

    var viewportWidthPx: Int = 1080
        private set
    var viewportHeightPx: Int = 1920
        private set
    var density: Float = 2f
        private set

    var phase: PacGridPhase = PacGridPhase.RUNNING
        private set

    var score: Int = 0
        private set
    var highScore: Int = 0
        private set
    var lives: Int = 3
        private set
    var level: Int = 1
        private set

    var runnerCol: Float = RUNNER_START_COL.toFloat()
        private set
    var runnerRow: Float = RUNNER_START_ROW.toFloat()
        private set
    var runnerDx: Int = -1
        private set
    var runnerDy: Int = 0
        private set
    var queuedDx: Int = -1
        private set
    var queuedDy: Int = 0
        private set

    var dotsEatenThisLevel: Int = 0
        private set
    var remainingDots: Int = 0
        private set
    private var spawnedFruit70: Boolean = false
    private var spawnedFruit170: Boolean = false
    var activeFruit: BonusFruit? = null
        private set

    var frightenedTimerSec: Float = 0f
        private set
    var frightenedComboCount: Int = 0
        private set

    var waveMode: ChaserWaveMode = ChaserWaveMode.SCATTER
        private set
    private var waveIndex: Int = 0
    private var waveTimerSec: Float = 0f

    var showTouchDpad: Boolean = true
        private set

    private val tiles: IntArray = IntArray(MAZE_COLS * MAZE_ROWS)
    val chasers: MutableList<PacChaser> = mutableListOf()

    fun startNewSession(
        widthPx: Int,
        heightPx: Int,
        screenDensity: Float,
        initialHighScore: Int
    ) {
        viewportWidthPx = max(320, widthPx)
        viewportHeightPx = max(320, heightPx)
        density = screenDensity.coerceIn(0.75f, 5f)
        highScore = max(highScore, initialHighScore)
        score = 0
        lives = 3
        level = 1
        phase = PacGridPhase.RUNNING
        loadLevelMaze()
        resetActorPositions()
    }

    fun updateDisplayMetrics(widthPx: Int, heightPx: Int, screenDensity: Float) {
        viewportWidthPx = max(320, widthPx)
        viewportHeightPx = max(320, heightPx)
        density = screenDensity.coerceIn(0.75f, 5f)
    }

    fun stop() {
        phase = PacGridPhase.PAUSED
    }

    fun togglePause() {
        phase = when (phase) {
            PacGridPhase.RUNNING -> PacGridPhase.PAUSED
            PacGridPhase.PAUSED -> PacGridPhase.RUNNING
            else -> phase
        }
    }

    fun toggleTouchDpad() {
        showTouchDpad = !showTouchDpad
    }

    fun queueDirection(dx: Int, dy: Int): Boolean {
        if (dx == 0 && dy == 0) return false
        if (dx != 0 && dy != 0) return false
        queuedDx = dx.coerceIn(-1, 1)
        queuedDy = dy.coerceIn(-1, 1)
        // Allow immediate 180-degree reversal along current corridor
        if (queuedDx == -runnerDx && queuedDy == -runnerDy) {
            runnerDx = queuedDx
            runnerDy = queuedDy
        }
        return true
    }

    private fun loadLevelMaze() {
        remainingDots = 0
        dotsEatenThisLevel = 0
        spawnedFruit70 = false
        spawnedFruit170 = false
        activeFruit = null

        for (r in 0 until MAZE_ROWS) {
            val line = MAZE_TEMPLATE[r]
            for (c in 0 until MAZE_COLS) {
                val ch = if (c < line.length) line[c] else ' '
                val type = when (ch) {
                    '#' -> TILE_WALL
                    '.' -> {
                        remainingDots++
                        TILE_PELLET
                    }
                    'o' -> {
                        remainingDots++
                        TILE_POWER_ORB
                    }
                    '-' -> TILE_GHOST_GATE
                    else -> TILE_EMPTY
                }
                tiles[r * MAZE_COLS + c] = type
            }
        }
    }

    private fun resetActorPositions() {
        runnerCol = RUNNER_START_COL.toFloat()
        runnerRow = RUNNER_START_ROW.toFloat()
        runnerDx = -1
        runnerDy = 0
        queuedDx = -1
        queuedDy = 0

        frightenedTimerSec = 0f
        frightenedComboCount = 0
        waveIndex = 0
        waveTimerSec = 0f
        waveMode = ChaserWaveMode.SCATTER

        chasers.clear()
        chasers.add(PacChaser(ChaserPersonality.BLINKY, col = 13f, row = 11f, dx = -1, dy = 0))
        chasers.add(PacChaser(ChaserPersonality.PINKY, col = 14f, row = 11f, dx = 1, dy = 0))
        chasers.add(PacChaser(ChaserPersonality.INKY, col = 12f, row = 11f, dx = -1, dy = 0))
        chasers.add(PacChaser(ChaserPersonality.CLYDE, col = 15f, row = 11f, dx = 1, dy = 0))
    }

    fun getTile(col: Int, row: Int): Int {
        if (row !in 0 until MAZE_ROWS) return TILE_WALL
        val wrappedCol = wrapCol(col, row)
        if (wrappedCol !in 0 until MAZE_COLS) return TILE_WALL
        return tiles[row * MAZE_COLS + wrappedCol]
    }

    fun setTileForTest(col: Int, row: Int, tileType: Int) {
        if (col in 0 until MAZE_COLS && row in 0 until MAZE_ROWS) {
            tiles[row * MAZE_COLS + col] = tileType
        }
    }

    private fun wrapCol(col: Int, row: Int): Int {
        if (row == TUNNEL_ROW) {
            if (col < 0) return (col % MAZE_COLS + MAZE_COLS) % MAZE_COLS
            if (col >= MAZE_COLS) return col % MAZE_COLS
        }
        return col
    }

    fun isWalkableForRunner(col: Int, row: Int): Boolean {
        val t = getTile(col, row)
        return t != TILE_WALL && t != TILE_GHOST_GATE
    }

    fun isWalkableForChaser(col: Int, row: Int, state: ChaserState): Boolean {
        val t = getTile(col, row)
        if (t == TILE_WALL) return false
        if (t == TILE_GHOST_GATE) {
            return state == ChaserState.EYES || row >= PEN_ROW - 1
        }
        return true
    }

    fun step(dtSec: Float) {
        if (phase != PacGridPhase.RUNNING) return
        val clampedDt = dtSec.coerceIn(0.001f, 0.1f)

        // Sub-step so fast actors never skip an intersection center
        val maxStep = 0.02f
        var rem = clampedDt
        while (rem > 0f && phase == PacGridPhase.RUNNING) {
            val slice = min(rem, maxStep)
            rem -= slice
            stepSingleSlice(slice)
        }
    }

    private fun stepSingleSlice(dt: Float) {
        updateWaveAndTimers(dt)
        stepRunner(dt)
        consumeCurrentTileIfApplicable()
        stepChasers(dt)
        checkChaserCollisions()
    }

    private fun updateWaveAndTimers(dt: Float) {
        activeFruit?.let { fruit ->
            fruit.remainingSec -= dt
            if (fruit.remainingSec <= 0f) {
                activeFruit = null
            }
        }

        if (frightenedTimerSec > 0f) {
            frightenedTimerSec = (frightenedTimerSec - dt).coerceAtLeast(0f)
            if (frightenedTimerSec == 0f) {
                frightenedComboCount = 0
                for (c in chasers) {
                    if (c.state == ChaserState.FRIGHTENED) {
                        c.state = ChaserState.NORMAL
                    }
                }
            }
        } else {
            // Advance Scatter <-> Chase wave clock only while not Frightened
            waveTimerSec += dt
            if (waveIndex < WAVE_DURATIONS_SEC.size && waveTimerSec >= WAVE_DURATIONS_SEC[waveIndex]) {
                waveTimerSec -= WAVE_DURATIONS_SEC[waveIndex]
                waveIndex++
                val nextMode = if (waveIndex % 2 == 0) ChaserWaveMode.SCATTER else ChaserWaveMode.CHASE
                if (nextMode != waveMode) {
                    waveMode = nextMode
                    // Classic arcade rule: chasers reverse direction on wave transition
                    for (c in chasers) {
                        if (c.state == ChaserState.NORMAL) {
                            c.dx = -c.dx
                            c.dy = -c.dy
                            c.lastDecisionCol = -1
                            c.lastDecisionRow = -1
                        }
                    }
                }
            }
        }
    }

    private fun stepRunner(dt: Float) {
        val speedTilesPerSec = (7.6f + (level - 1) * 0.35f).coerceAtMost(10.5f)
        val dist = speedTilesPerSec * dt

        val nearestCol = kotlin.math.round(runnerCol).toInt()
        val nearestRow = kotlin.math.round(runnerRow).toInt()
        val distToCenter = abs(runnerCol - nearestCol) + abs(runnerRow - nearestRow)

        // Apply buffered 90-degree turn when near tile intersection center
        if ((queuedDx != runnerDx || queuedDy != runnerDy) && distToCenter <= 0.28f) {
            if (isWalkableForRunner(nearestCol + queuedDx, nearestRow + queuedDy)) {
                runnerCol = nearestCol.toFloat()
                runnerRow = nearestRow.toFloat()
                runnerDx = queuedDx
                runnerDy = queuedDy
            }
        }

        val nextX = runnerCol + runnerDx * dist
        val nextY = runnerRow + runnerDy * dist

        val aheadCol = nearestCol + runnerDx
        val aheadRow = nearestRow + runnerDy
        val movingAwayOrTowardWalkable = isWalkableForRunner(aheadCol, aheadRow)

        if (movingAwayOrTowardWalkable) {
            runnerCol = nextX
            runnerRow = nextY
            // Keep perpendicular coordinate snapped to corridor center
            if (runnerDx != 0) runnerRow = nearestRow.toFloat()
            if (runnerDy != 0) runnerCol = nearestCol.toFloat()
        } else {
            // Clamp at center of current tile if blocked ahead
            runnerCol = if (runnerDx > 0) min(nextX, nearestCol.toFloat())
            else if (runnerDx < 0) max(nextX, nearestCol.toFloat())
            else nearestCol.toFloat()

            runnerRow = if (runnerDy > 0) min(nextY, nearestRow.toFloat())
            else if (runnerDy < 0) max(nextY, nearestRow.toFloat())
            else nearestRow.toFloat()
        }

        // Warp tunnel wrap on row 14
        if (kotlin.math.round(runnerRow).toInt() == TUNNEL_ROW) {
            if (runnerCol < -0.4f) {
                runnerCol += MAZE_COLS.toFloat()
            } else if (runnerCol >= MAZE_COLS - 0.6f) {
                runnerCol -= MAZE_COLS.toFloat()
            }
        }
    }

    private fun consumeCurrentTileIfApplicable() {
        val c = kotlin.math.round(runnerCol).toInt().coerceIn(0, MAZE_COLS - 1)
        val r = kotlin.math.round(runnerRow).toInt().coerceIn(0, MAZE_ROWS - 1)
        val idx = r * MAZE_COLS + c
        when (tiles[idx]) {
            TILE_PELLET -> {
                tiles[idx] = TILE_EMPTY
                addScore(10)
                onDotConsumed()
            }
            TILE_POWER_ORB -> {
                tiles[idx] = TILE_EMPTY
                addScore(50)
                triggerFrightenedMode()
                onDotConsumed()
            }
        }

        activeFruit?.let { fruit ->
            if (c == fruit.col && r == fruit.row) {
                addScore(fruit.points)
                activeFruit = null
            }
        }
    }

    private fun onDotConsumed() {
        dotsEatenThisLevel++
        remainingDots = (remainingDots - 1).coerceAtLeast(0)

        if (dotsEatenThisLevel == 70 && !spawnedFruit70) {
            spawnedFruit70 = true
            spawnBonusFruit()
        } else if (dotsEatenThisLevel == 170 && !spawnedFruit170) {
            spawnedFruit170 = true
            spawnBonusFruit()
        }

        if (remainingDots == 0) {
            level++
            loadLevelMaze()
            resetActorPositions()
        }
    }

    private fun spawnBonusFruit() {
        val entry = FRUIT_TABLE[(level - 1).coerceIn(0, FRUIT_TABLE.lastIndex)]
        activeFruit = BonusFruit(
            points = entry.second,
            label = entry.first,
            remainingSec = FRUIT_DURATION_SEC
        )
    }

    fun triggerFrightenedMode() {
        frightenedTimerSec = FRIGHTENED_DURATION_SEC
        frightenedComboCount = 0
        for (chaser in chasers) {
            if (chaser.state != ChaserState.EYES) {
                chaser.state = ChaserState.FRIGHTENED
                chaser.dx = -chaser.dx
                chaser.dy = -chaser.dy
                chaser.lastDecisionCol = -1
                chaser.lastDecisionRow = -1
            }
        }
    }

    private fun stepChasers(dt: Float) {
        val baseSpeed = (6.8f + (level - 1) * 0.3f).coerceAtMost(9.8f)
        for (chaser in chasers) {
            val nearestCol = kotlin.math.round(chaser.col).toInt()
            val nearestRow = kotlin.math.round(chaser.row).toInt()
            val inTunnel = nearestRow == TUNNEL_ROW && (nearestCol <= 4 || nearestCol >= MAZE_COLS - 5)

            val speed = when {
                chaser.state == ChaserState.EYES -> baseSpeed * 1.85f
                chaser.state == ChaserState.FRIGHTENED -> baseSpeed * 0.58f
                inTunnel -> baseSpeed * 0.55f
                else -> baseSpeed
            }

            // Regenerate returning EYES once they reach the ghost pen
            if (chaser.state == ChaserState.EYES) {
                val distToPen = abs(chaser.col - PEN_COL) + abs(chaser.row - PEN_ROW)
                if (distToPen <= 0.65f) {
                    chaser.col = PEN_EXIT_COL.toFloat()
                    chaser.row = PEN_EXIT_ROW.toFloat()
                    chaser.state = ChaserState.NORMAL
                    chaser.dx = -1
                    chaser.dy = 0
                    chaser.lastDecisionCol = -1
                    chaser.lastDecisionRow = -1
                    continue
                }
            }

            val distToCenter = abs(chaser.col - nearestCol) + abs(chaser.row - nearestRow)
            if (distToCenter <= 0.24f && (chaser.lastDecisionCol != nearestCol || chaser.lastDecisionRow != nearestRow)) {
                chaser.col = nearestCol.toFloat()
                chaser.row = nearestRow.toFloat()
                chaser.lastDecisionCol = nearestCol
                chaser.lastDecisionRow = nearestRow

                val target = computeChaserTargetTile(chaser)
                val nextDir = chooseChaserDirectionAtTile(
                    col = nearestCol,
                    row = nearestRow,
                    curDx = chaser.dx,
                    curDy = chaser.dy,
                    targetCol = target.col,
                    targetRow = target.row,
                    state = chaser.state
                )
                chaser.dx = nextDir.first
                chaser.dy = nextDir.second
            }

            chaser.col += chaser.dx * speed * dt
            chaser.row += chaser.dy * speed * dt

            if (nearestRow == TUNNEL_ROW) {
                if (chaser.col < -0.4f) chaser.col += MAZE_COLS.toFloat()
                else if (chaser.col >= MAZE_COLS - 0.6f) chaser.col -= MAZE_COLS.toFloat()
            }
        }
    }

    /**
     * Computes target tile for each of the 4 classic chaser personalities:
     * - BLINKY: runner's current tile (or top-right scatter corner)
     * - PINKY: 4 tiles ahead of runner (or top-left scatter corner)
     * - INKY: vector reflection from Blinky through 2 tiles ahead of runner (or bottom-right scatter)
     * - CLYDE: runner's tile when Euclidean distance > 8 tiles, else bottom-left scatter corner
     */
    fun computeChaserTargetTile(chaser: PacChaser): GridCell {
        if (chaser.state == ChaserState.EYES) {
            return GridCell(PEN_COL, PEN_ROW)
        }
        if (chaser.state == ChaserState.FRIGHTENED) {
            // Deterministic pseudo-scatter away from runner
            return GridCell(MAZE_COLS - 1 - kotlin.math.round(runnerCol).toInt(), MAZE_ROWS - 1 - kotlin.math.round(runnerRow).toInt())
        }
        if (waveMode == ChaserWaveMode.SCATTER) {
            return scatterCornerFor(chaser.personality)
        }

        val rCol = kotlin.math.round(runnerCol).toInt()
        val rRow = kotlin.math.round(runnerRow).toInt()

        return when (chaser.personality) {
            ChaserPersonality.BLINKY -> GridCell(rCol, rRow)
            ChaserPersonality.PINKY -> GridCell(rCol + runnerDx * 4, rRow + runnerDy * 4)
            ChaserPersonality.INKY -> {
                val pivotCol = rCol + runnerDx * 2
                val pivotRow = rRow + runnerDy * 2
                val blinky = chasers.firstOrNull { it.personality == ChaserPersonality.BLINKY }
                val bCol = blinky?.let { kotlin.math.round(it.col).toInt() } ?: rCol
                val bRow = blinky?.let { kotlin.math.round(it.row).toInt() } ?: rRow
                GridCell(pivotCol + (pivotCol - bCol), pivotRow + (pivotRow - bRow))
            }
            ChaserPersonality.CLYDE -> {
                val dx = chaser.col - runnerCol
                val dy = chaser.row - runnerRow
                val dist = sqrt(dx * dx + dy * dy)
                if (dist > 8f) {
                    GridCell(rCol, rRow)
                } else {
                    scatterCornerFor(ChaserPersonality.CLYDE)
                }
            }
        }
    }

    fun scatterCornerFor(personality: ChaserPersonality): GridCell {
        return when (personality) {
            ChaserPersonality.BLINKY -> GridCell(MAZE_COLS - 3, 0)
            ChaserPersonality.PINKY -> GridCell(2, 0)
            ChaserPersonality.INKY -> GridCell(MAZE_COLS - 1, MAZE_ROWS - 1)
            ChaserPersonality.CLYDE -> GridCell(0, MAZE_ROWS - 1)
        }
    }

    private fun chooseChaserDirectionAtTile(
        col: Int,
        row: Int,
        curDx: Int,
        curDy: Int,
        targetCol: Int,
        targetRow: Int,
        state: ChaserState
    ): Pair<Int, Int> {
        // Classic priority order: UP, LEFT, DOWN, RIGHT (excluding reverse unless dead-end)
        val candidates = listOf(
            0 to -1,
            -1 to 0,
            0 to 1,
            1 to 0
        )
        var bestDir: Pair<Int, Int>? = null
        var bestDistSq = Int.MAX_VALUE

        for (dir in candidates) {
            if (dir.first == -curDx && dir.second == -curDy) continue
            val nc = wrapCol(col + dir.first, row + dir.second)
            val nr = row + dir.second
            if (!isWalkableForChaser(nc, nr, state)) continue
            val dCol = nc - targetCol
            val dRow = nr - targetRow
            val distSq = dCol * dCol + dRow * dRow
            if (distSq < bestDistSq) {
                bestDistSq = distSq
                bestDir = dir
            }
        }

        if (bestDir != null) return bestDir
        // Fallback: reverse if trapped
        if (isWalkableForChaser(wrapCol(col - curDx, row - curDy), row - curDy, state)) {
            return -curDx to -curDy
        }
        return curDx to curDy
    }

    private fun checkChaserCollisions() {
        for (chaser in chasers) {
            val dx = abs(chaser.col - runnerCol)
            val dy = abs(chaser.row - runnerRow)
            if (dx <= 0.55f && dy <= 0.55f) {
                when (chaser.state) {
                    ChaserState.FRIGHTENED -> {
                        chaser.state = ChaserState.EYES
                        frightenedComboCount = (frightenedComboCount + 1).coerceAtMost(4)
                        val comboPts = 200 shl (frightenedComboCount - 1) // 200, 400, 800, 1600
                        addScore(comboPts)
                    }
                    ChaserState.NORMAL -> {
                        lives--
                        if (lives <= 0) {
                            phase = PacGridPhase.GAME_OVER
                        } else {
                            resetActorPositions()
                        }
                        return
                    }
                    ChaserState.EYES -> {
                        // Returning eyes are harmless
                    }
                }
            }
        }
    }

    private fun addScore(points: Int) {
        if (points <= 0) return
        score += points
        if (score > highScore) {
            highScore = score
            onNewHighScore(highScore)
        }
    }

    fun forceSetRunnerForTest(col: Float, row: Float, dx: Int, dy: Int) {
        runnerCol = col
        runnerRow = row
        runnerDx = dx
        runnerDy = dy
        queuedDx = dx
        queuedDy = dy
    }

    fun forceSetChaserForTest(
        personality: ChaserPersonality,
        col: Float,
        row: Float,
        dx: Int = -1,
        dy: Int = 0,
        state: ChaserState = ChaserState.NORMAL
    ) {
        val chaser = chasers.firstOrNull { it.personality == personality } ?: return
        chaser.col = col
        chaser.row = row
        chaser.dx = dx
        chaser.dy = dy
        chaser.state = state
        chaser.lastDecisionCol = -1
        chaser.lastDecisionRow = -1
    }

    fun forceSetWaveModeForTest(mode: ChaserWaveMode) {
        waveMode = mode
    }

    fun forceSetDotsCountForTest(eaten: Int, remaining: Int) {
        dotsEatenThisLevel = eaten
        remainingDots = remaining
    }
}
