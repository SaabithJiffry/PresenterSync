package com.saabithjiffry.presentersync.remote.ui.overlay

import android.view.KeyEvent
import com.saabithjiffry.presentersync.remote.config.FormFactorClass
import com.saabithjiffry.presentersync.remote.config.ResolvedFormFactor
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.random.Random

enum class SnakePhase {
    IDLE,
    MORPH,
    PLAYING,
    PAUSED,
    GAME_OVER
}

enum class SnakeFoodKind(val pts: Int, val ttlMs: Long) {
    NORMAL(10, 0L),
    BONUS(30, 9000L)
}

enum class SnakeDeathReason(val label: String) {
    NONE(""),
    WALL("Hit Screen Edge"),
    SELF("Self-Collision")
}

sealed interface SnakeInputCommand {
    data class Direction(val dx: Int, val dy: Int) : SnakeInputCommand
    data object TogglePause : SnakeInputCommand
    data object ToggleEdgeMode : SnakeInputCommand
    data object Restart : SnakeInputCommand
    data object PauseOrRestart : SnakeInputCommand
    data object Exit : SnakeInputCommand
}

data class SnakeCell(val col: Int, val row: Int)
data class SnakePointF(val x: Float, val y: Float)

data class SnakeMorphSeed(
    val x: Float,
    val y: Float,
    val w: Float,
    val h: Float,
    val colorArgb: Int,
    val targetCol: Int,
    val targetRow: Int
)

data class SnakeGridMetrics(
    val workW: Int,
    val workH: Int,
    val density: Float,
    val cellPx: Int,
    val cols: Int,
    val rows: Int,
    val gridOffX: Int,
    val gridOffY: Int,
    val sbColsHalf: Int,
    val sbSafeRows: Int,
    val isCompactScoreboard: Boolean
)

data class SnakeFood(
    val col: Int,
    val row: Int,
    val kind: SnakeFoodKind,
    val bornNs: Long
)

data class SnakeEatEffect(
    val col: Int,
    val row: Int,
    val kind: SnakeFoodKind,
    val bornNs: Long
)

data class SnakePopup(
    val xPx: Float,
    val yPx: Float,
    val text: String,
    val kind: SnakeFoodKind,
    val bornNs: Long
)

data class SnakeUiSnapshot(
    val phase: SnakePhase,
    val score: Int,
    val highScore: Int,
    val bestBeaten: Boolean,
    val length: Int,
    val stepMs: Int,
    val edgeWrap: Boolean,
    val deathReason: SnakeDeathReason,
    val dirX: Int,
    val dirY: Int,
    val snake: List<SnakeCell>,
    val food: SnakeFood?,
    val isCompactScoreboard: Boolean
)

class HudSnakeEngine(
    private val random: Random = Random.Default,
    private val onNewHighScore: (Int) -> Unit = {}
) {
    var phase: SnakePhase = SnakePhase.IDLE
        private set
    var grid: SnakeGridMetrics = SnakeGridMetrics(
        workW = 1080,
        workH = 1920,
        density = 2f,
        cellPx = 48,
        cols = 20,
        rows = 36,
        gridOffX = 60,
        gridOffY = 96,
        sbColsHalf = 6,
        sbSafeRows = 3,
        isCompactScoreboard = true
    )
        private set

    var snake: MutableList<SnakeCell> = mutableListOf()
        private set
    var prevSnake: MutableList<SnakeCell> = mutableListOf()
        private set
    var morphSeeds: List<SnakeMorphSeed> = emptyList()
        private set

    var dirX: Int = -1
        private set
    var dirY: Int = 0
        private set
    var crashDirX: Int = 0
        private set
    var crashDirY: Int = 0
        private set

    private val dirQueue: ArrayDeque<Pair<Int, Int>> = ArrayDeque()
    private var growPending: Int = 0
    private var stepGrew: Boolean = false

    var food: SnakeFood? = null
        private set
    val eatEffects: MutableList<SnakeEatEffect> = mutableListOf()
    val popups: MutableList<SnakePopup> = mutableListOf()

    var score: Int = 0
        private set
    var highScore: Int = 0
        private set
    var bestBeaten: Boolean = false
        private set
    var eatenCount: Int = 0
        private set
    var edgeWrap: Boolean = false
        private set
    var deathReason: SnakeDeathReason = SnakeDeathReason.NONE
        private set

    var stepMs: Int = BASE_STEP_MS
        private set
    var morphStartNs: Long = 0L
        private set
    var stepStartNs: Long = 0L
        private set
    var frozenInterp: Float = 0f
        private set

    private var pillSeedX: Float = 0f
    private var pillSeedY: Float = 0f
    private var pillSeedW: Float = 160f
    private var pillSeedH: Float = 80f
    private var pillSeedColor: Int = 0xFF22C55E.toInt()

    fun start(
        workWidthPx: Int,
        workHeightPx: Int,
        density: Float,
        formFactor: ResolvedFormFactor,
        hudScale: Float,
        initialHighScore: Int,
        pillLeftPx: Float,
        pillTopPx: Float,
        pillWidthPx: Float,
        pillHeightPx: Float,
        pillColorArgb: Int,
        nowNs: Long,
        skipMorph: Boolean = false
    ) {
        grid = computeGridMetrics(workWidthPx, workHeightPx, density, formFactor, hudScale)
        pillSeedX = pillLeftPx
        pillSeedY = pillTopPx
        pillSeedW = pillWidthPx.coerceAtLeast(24f)
        pillSeedH = pillHeightPx.coerceAtLeast(20f)
        pillSeedColor = pillColorArgb

        highScore = initialHighScore.coerceAtLeast(0)
        bestBeaten = false
        score = 0
        eatenCount = 0
        edgeWrap = false
        deathReason = SnakeDeathReason.NONE
        crashDirX = 0
        crashDirY = 0
        growPending = 0
        stepGrew = false
        stepMs = BASE_STEP_MS
        frozenInterp = 0f
        dirQueue.clear()
        eatEffects.clear()
        popups.clear()

        spawnFromSeed()
        prevSnake = snake.mapTo(mutableListOf()) { it.copy() }
        spawnFood(SnakeFoodKind.NORMAL, nowNs)

        phase = if (skipMorph) SnakePhase.PLAYING else SnakePhase.MORPH
        morphStartNs = nowNs
        stepStartNs = nowNs
    }

    fun updateDisplayLayout(
        workWidthPx: Int,
        workHeightPx: Int,
        density: Float,
        formFactor: ResolvedFormFactor,
        hudScale: Float
    ) {
        if (phase == SnakePhase.IDLE) return
        grid = computeGridMetrics(workWidthPx, workHeightPx, density, formFactor, hudScale)
        snake = snake.mapTo(mutableListOf()) { seg ->
            SnakeCell(seg.col.coerceIn(0, grid.cols - 1), seg.row.coerceIn(0, grid.rows - 1))
        }
        prevSnake = snake.mapTo(mutableListOf()) { it.copy() }
        food?.let { f ->
            if (f.col >= grid.cols || f.row >= grid.rows) {
                spawnFood(f.kind, f.bornNs)
            }
        }
    }

    fun stop() {
        phase = SnakePhase.IDLE
        snake.clear()
        prevSnake.clear()
        morphSeeds = emptyList()
        dirQueue.clear()
        eatEffects.clear()
        popups.clear()
        food = null
        crashDirX = 0
        crashDirY = 0
    }

    fun restart(nowNs: Long, skipMorph: Boolean = false) {
        if (phase == SnakePhase.IDLE) return
        bestBeaten = false
        score = 0
        eatenCount = 0
        deathReason = SnakeDeathReason.NONE
        crashDirX = 0
        crashDirY = 0
        growPending = 0
        stepGrew = false
        stepMs = BASE_STEP_MS
        frozenInterp = 0f
        dirQueue.clear()
        eatEffects.clear()
        popups.clear()

        spawnFromSeed()
        prevSnake = snake.mapTo(mutableListOf()) { it.copy() }
        spawnFood(SnakeFoodKind.NORMAL, nowNs)

        phase = if (skipMorph) SnakePhase.PLAYING else SnakePhase.MORPH
        morphStartNs = nowNs
        stepStartNs = nowNs
    }

    fun togglePause(nowNs: Long) {
        when (phase) {
            SnakePhase.PLAYING -> {
                val stepNs = stepMs * 1_000_000.0
                frozenInterp = ((nowNs - stepStartNs) / stepNs).toFloat().coerceIn(0f, 1f)
                phase = SnakePhase.PAUSED
            }
            SnakePhase.PAUSED -> {
                phase = SnakePhase.PLAYING
                val stepNs = stepMs * 1_000_000L
                stepStartNs = nowNs - (frozenInterp * stepNs).roundToInt().toLong()
            }
            SnakePhase.GAME_OVER -> restart(nowNs)
            else -> {}
        }
    }

    fun toggleEdgeMode() {
        if (phase == SnakePhase.IDLE) return
        edgeWrap = !edgeWrap
    }

    fun queueDirection(dx: Int, dy: Int): Boolean {
        if (phase != SnakePhase.PLAYING && phase != SnakePhase.MORPH) return false
        if (abs(dx) + abs(dy) != 1) return false

        val ref = dirQueue.lastOrNull() ?: (dirX to dirY)
        if ((dx == ref.first && dy == ref.second) || (dx == -ref.first && dy == -ref.second)) {
            return false
        }
        if (dirQueue.size >= 2) return false
        dirQueue.addLast(dx to dy)
        return true
    }

    fun handleInputCommand(cmd: SnakeInputCommand, nowNs: Long): Boolean {
        return when (cmd) {
            is SnakeInputCommand.Direction -> queueDirection(cmd.dx, cmd.dy)
            SnakeInputCommand.TogglePause -> {
                if (phase == SnakePhase.PLAYING || phase == SnakePhase.PAUSED) {
                    togglePause(nowNs)
                    true
                } else {
                    false
                }
            }
            SnakeInputCommand.ToggleEdgeMode -> {
                toggleEdgeMode()
                true
            }
            SnakeInputCommand.Restart -> {
                if (phase == SnakePhase.GAME_OVER) {
                    restart(nowNs)
                    true
                } else {
                    false
                }
            }
            SnakeInputCommand.PauseOrRestart -> {
                togglePause(nowNs)
                true
            }
            SnakeInputCommand.Exit -> {
                stop()
                true
            }
        }
    }

    fun tick(nowNs: Long): Boolean {
        when (phase) {
            SnakePhase.IDLE -> return false
            SnakePhase.MORPH -> {
                val elapsedNs = nowNs - morphStartNs
                if (elapsedNs >= MORPH_DURATION_MS * 1_000_000L) {
                    phase = SnakePhase.PLAYING
                    stepStartNs = nowNs
                    stepSimulation(nowNs)
                }
                return true
            }
            SnakePhase.PLAYING -> {
                val stepNs = stepMs * 1_000_000L
                val elapsedNs = nowNs - stepStartNs
                if (elapsedNs >= stepNs) {
                    var stepsDue = (elapsedNs / stepNs).toInt()
                    if (stepsDue > 2) {
                        stepStartNs = nowNs
                        stepsDue = 1
                    } else {
                        stepStartNs += stepsDue * stepNs
                    }
                    repeat(stepsDue) {
                        if (phase != SnakePhase.PLAYING) return@repeat
                        stepSimulation(nowNs)
                    }
                }
                cullTimedEffects(nowNs)
                return true
            }
            SnakePhase.PAUSED -> return false
            SnakePhase.GAME_OVER -> {
                val hadTransient = popups.isNotEmpty() || eatEffects.isNotEmpty()
                cullTimedEffects(nowNs)
                return hadTransient || popups.isNotEmpty() || eatEffects.isNotEmpty()
            }
        }
    }

    private fun cullTimedEffects(nowNs: Long) {
        eatEffects.removeAll { (nowNs - it.bornNs) >= 380_000_000L }
        popups.removeAll { (nowNs - it.bornNs) >= 750_000_000L }
    }

    fun stepSimulation(nowNs: Long) {
        if (phase != SnakePhase.PLAYING || snake.isEmpty()) return
        if (dirQueue.isNotEmpty()) {
            val next = dirQueue.removeFirst()
            dirX = next.first
            dirY = next.second
        }

        val head = snake[0]
        var nextCol = head.col + dirX
        var nextRow = head.row + dirY

        if (nextCol < 0 || nextCol >= grid.cols || nextRow < 0 || nextRow >= grid.rows) {
            if (edgeWrap) {
                nextCol = ((nextCol % grid.cols) + grid.cols) % grid.cols
                nextRow = ((nextRow % grid.rows) + grid.rows) % grid.rows
            } else {
                triggerGameOver(SnakeDeathReason.WALL)
                return
            }
        }

        val activeFood = food
        if (activeFood != null && activeFood.kind.ttlMs > 0L) {
            if ((nowNs - activeFood.bornNs) >= activeFood.kind.ttlMs * 1_000_000L) {
                spawnFood(SnakeFoodKind.NORMAL, nowNs)
            }
        }

        val currentFood = food
        val willEat = currentFood != null && currentFood.col == nextCol && currentFood.row == nextRow
        val checkLimit = if (growPending == 0 && !willEat) snake.size - 1 else snake.size
        for (i in 0 until checkLimit) {
            val seg = snake[i]
            if (seg.col == nextCol && seg.row == nextRow) {
                triggerGameOver(SnakeDeathReason.SELF)
                return
            }
        }

        prevSnake = snake.mapTo(mutableListOf()) { it.copy() }

        var nextKind = SnakeFoodKind.NORMAL
        if (willEat && currentFood != null) {
            score += currentFood.kind.pts
            eatenCount += 1
            growPending += if (currentFood.kind == SnakeFoodKind.BONUS) 2 else 1
            if (score > highScore) {
                highScore = score
                bestBeaten = true
                onNewHighScore(highScore)
            }

            val popX = grid.gridOffX + (nextCol + 0.5f) * grid.cellPx
            val popY = grid.gridOffY + (nextRow + 0.5f) * grid.cellPx - 6f * grid.density
            popups.add(SnakePopup(popX, popY, "+${currentFood.kind.pts}", currentFood.kind, nowNs))
            eatEffects.add(SnakeEatEffect(nextCol, nextRow, currentFood.kind, nowNs))

            stepMs = max(MIN_STEP_MS, BASE_STEP_MS - min(64, eatenCount * 3))
            nextKind = if (eatenCount % 5 == 0) SnakeFoodKind.BONUS else SnakeFoodKind.NORMAL
            food = null
        }

        snake.add(0, SnakeCell(nextCol, nextRow))
        if (growPending > 0) {
            growPending -= 1
            stepGrew = true
        } else {
            snake.removeAt(snake.lastIndex)
            stepGrew = false
        }

        if (willEat) {
            spawnFood(nextKind, nowNs)
        }
    }

    private fun triggerGameOver(reason: SnakeDeathReason) {
        phase = SnakePhase.GAME_OVER
        deathReason = reason
        crashDirX = dirX
        crashDirY = dirY
        prevSnake = snake.mapTo(mutableListOf()) { it.copy() }
        stepGrew = false
        frozenInterp = 0.34f
    }

    fun currentInterpFraction(nowNs: Long): Float {
        return when (phase) {
            SnakePhase.PLAYING -> ((nowNs - stepStartNs) / (stepMs * 1_000_000.0)).toFloat().coerceIn(0f, 1f)
            SnakePhase.PAUSED, SnakePhase.GAME_OVER -> frozenInterp
            else -> 1f
        }
    }

    fun buildInterpolatedPieces(interp: Float): List<List<SnakePointF>> {
        val lenC = snake.size
        val lenP = prevSnake.size
        if (lenC == 0) return emptyList()

        val pieces = mutableListOf<MutableList<SnakePointF>>()
        var extraTailPiece: MutableList<SnakePointF>? = null
        val cHead = snake[0]
        val pHead = if (lenP > 0) prevSnake[0] else cHead
        val dhc = abs(cHead.col - pHead.col) + abs(cHead.row - pHead.row)
        var skipIdx2Split = false

        if (dhc == 0) {
            val hx = cHead.col + crashDirX * interp
            val hy = cHead.row + crashDirY * interp
            val pts = mutableListOf(SnakePointF(hx, hy))
            if (abs(hx - cHead.col) > 0.001f || abs(hy - cHead.row) > 0.001f) {
                pts.add(SnakePointF(cHead.col.toFloat(), cHead.row.toFloat()))
            }
            pieces.add(pts)
        } else if (dhc == 1) {
            val hx = pHead.col + (cHead.col - pHead.col) * interp
            val hy = pHead.row + (cHead.row - pHead.row) * interp
            pieces.add(mutableListOf(SnakePointF(hx, hy)))
        } else {
            val hStepX = when {
                cHead.col == 0 && pHead.col == grid.cols - 1 -> 1
                cHead.col == grid.cols - 1 && pHead.col == 0 -> -1
                else -> 0
            }
            val hStepY = when {
                cHead.row == 0 && pHead.row == grid.rows - 1 -> 1
                cHead.row == grid.rows - 1 && pHead.row == 0 -> -1
                else -> 0
            }
            if (interp < 0.5f) {
                pieces.add(mutableListOf(SnakePointF(pHead.col + hStepX * interp, pHead.row + hStepY * interp)))
            } else {
                val hxIn = cHead.col - hStepX * (1f - interp)
                val hyIn = cHead.row - hStepY * (1f - interp)
                val edgeInX = cHead.col - hStepX * 0.50f
                val edgeInY = cHead.row - hStepY * 0.50f
                pieces.add(mutableListOf(SnakePointF(hxIn, hyIn), SnakePointF(edgeInX, edgeInY)))
                pieces.add(mutableListOf(SnakePointF(pHead.col + hStepX * 0.50f, pHead.row + hStepY * 0.50f)))
            }
            skipIdx2Split = true
        }

        for (idx in 1 until lenC) {
            val cur = snake[idx]
            val isLast = (idx == lenC - 1)
            if (isLast && !stepGrew && lenP >= 2) break

            val prevSeg = snake[idx - 1]
            val curPiece = pieces.last()
            val jmp = abs(cur.col - prevSeg.col) + abs(cur.row - prevSeg.row)
            if (jmp <= 1 || (idx == 1 && skipIdx2Split)) {
                curPiece.add(SnakePointF(cur.col.toFloat(), cur.row.toFloat()))
            } else {
                val jStepX = when {
                    cur.col == 0 && prevSeg.col == grid.cols - 1 -> -1
                    cur.col == grid.cols - 1 && prevSeg.col == 0 -> 1
                    else -> 0
                }
                val jStepY = when {
                    cur.row == 0 && prevSeg.row == grid.rows - 1 -> -1
                    cur.row == grid.rows - 1 && prevSeg.row == 0 -> 1
                    else -> 0
                }
                curPiece.add(SnakePointF(prevSeg.col - jStepX * 0.50f, prevSeg.row - jStepY * 0.50f))
                pieces.add(
                    mutableListOf(
                        SnakePointF(cur.col + jStepX * 0.50f, cur.row + jStepY * 0.50f),
                        SnakePointF(cur.col.toFloat(), cur.row.toFloat())
                    )
                )
            }
        }

        if (!stepGrew && lenP >= 2 && lenC >= 2) {
            val pTail = prevSnake[lenP - 1]
            val cTail = snake[lenC - 1]
            val prevBeforeTail = snake[lenC - 2]
            var curPiece = pieces.last()

            val tailJump = abs(cTail.col - prevBeforeTail.col) + abs(cTail.row - prevBeforeTail.row)
            if (tailJump > 1) {
                val bStepX = when {
                    cTail.col == 0 && prevBeforeTail.col == grid.cols - 1 -> -1
                    cTail.col == grid.cols - 1 && prevBeforeTail.col == 0 -> 1
                    else -> 0
                }
                val bStepY = when {
                    cTail.row == 0 && prevBeforeTail.row == grid.rows - 1 -> -1
                    cTail.row == grid.rows - 1 && prevBeforeTail.row == 0 -> 1
                    else -> 0
                }
                curPiece.add(SnakePointF(prevBeforeTail.col - bStepX * 0.50f, prevBeforeTail.row - bStepY * 0.50f))
                curPiece = mutableListOf(SnakePointF(cTail.col + bStepX * 0.50f, cTail.row + bStepY * 0.50f))
                pieces.add(curPiece)
            }

            val dtc = abs(cTail.col - pTail.col) + abs(cTail.row - pTail.row)
            if (dtc <= 1) {
                curPiece.add(SnakePointF(cTail.col.toFloat(), cTail.row.toFloat()))
                val tx = pTail.col + (cTail.col - pTail.col) * interp
                val ty = pTail.row + (cTail.row - pTail.row) * interp
                curPiece.add(SnakePointF(tx, ty))
            } else {
                val tStepX = when {
                    cTail.col == 0 && pTail.col == grid.cols - 1 -> 1
                    cTail.col == grid.cols - 1 && pTail.col == 0 -> -1
                    else -> 0
                }
                val tStepY = when {
                    cTail.row == 0 && pTail.row == grid.rows - 1 -> 1
                    cTail.row == grid.rows - 1 && pTail.row == 0 -> -1
                    else -> 0
                }
                curPiece.add(SnakePointF(cTail.col.toFloat(), cTail.row.toFloat()))
                if (interp < 0.5f) {
                    curPiece.add(SnakePointF(cTail.col - tStepX * 0.50f, cTail.row - tStepY * 0.50f))
                    extraTailPiece = mutableListOf(
                        SnakePointF(pTail.col + tStepX * 0.50f, pTail.row + tStepY * 0.50f),
                        SnakePointF(pTail.col + tStepX * interp, pTail.row + tStepY * interp)
                    )
                } else {
                    curPiece.add(
                        SnakePointF(
                            cTail.col - tStepX * (1f - interp),
                            cTail.row - tStepY * (1f - interp)
                        )
                    )
                }
            }
        }
        if (extraTailPiece != null) {
            pieces.add(extraTailPiece)
        }
        return pieces
    }

    fun snapshot(): SnakeUiSnapshot = SnakeUiSnapshot(
        phase = phase,
        score = score,
        highScore = highScore,
        bestBeaten = bestBeaten,
        length = snake.size,
        stepMs = stepMs,
        edgeWrap = edgeWrap,
        deathReason = deathReason,
        dirX = dirX,
        dirY = dirY,
        snake = snake.toList(),
        food = food,
        isCompactScoreboard = grid.isCompactScoreboard
    )

    internal fun forceSnakeForTest(cells: List<SnakeCell>, dx: Int, dy: Int, targetFood: SnakeFood? = null) {
        snake = cells.toMutableList()
        prevSnake = cells.mapTo(mutableListOf()) { it.copy() }
        dirX = dx
        dirY = dy
        dirQueue.clear()
        if (targetFood != null) {
            food = targetFood
        }
        phase = SnakePhase.PLAYING
    }

    private fun spawnFromSeed() {
        val rawCol = floor(((pillSeedX + pillSeedW / 2f) - grid.gridOffX) / grid.cellPx).toInt()
        val rawRow = floor(((pillSeedY + pillSeedH / 2f) - grid.gridOffY) / grid.cellPx).toInt()

        val initLen = INITIAL_LENGTH
        val minStartCol = min(grid.cols - 1, initLen + 1)
        val maxStartCol = max(minStartCol, grid.cols - initLen - 2)
        val startCol = rawCol.coerceIn(minStartCol, maxStartCol)

        val minStartRow = min(grid.rows - 2, grid.sbSafeRows + 1)
        val maxStartRow = max(minStartRow, grid.rows - 3)
        val startRow = rawRow.coerceIn(minStartRow, maxStartRow)

        dirX = if (startCol >= grid.cols / 2) -1 else 1
        dirY = 0

        val newSnake = mutableListOf<SnakeCell>()
        val newSeeds = mutableListOf<SnakeMorphSeed>()
        for (i in 0 until initLen) {
            val segCol = (startCol - i * dirX).coerceIn(0, grid.cols - 1)
            newSnake.add(SnakeCell(segCol, startRow))
            newSeeds.add(
                SnakeMorphSeed(
                    x = pillSeedX,
                    y = pillSeedY,
                    w = pillSeedW,
                    h = pillSeedH,
                    colorArgb = pillSeedColor,
                    targetCol = segCol,
                    targetRow = startRow
                )
            )
        }
        snake = newSnake
        morphSeeds = newSeeds
    }

    private fun spawnFood(kind: SnakeFoodKind, nowNs: Long) {
        val occupied = HashSet<SnakeCell>(snake.size + 4)
        occupied.addAll(snake)

        val midCol = grid.cols / 2
        val candidates = ArrayList<SnakeCell>(grid.cols * grid.rows)
        val minC = 1.coerceAtMost(grid.cols - 1)
        val maxC = (grid.cols - 2).coerceAtLeast(minC)
        val minR = 1.coerceAtMost(grid.rows - 1)
        val maxR = (grid.rows - 2).coerceAtLeast(minR)

        for (c in minC..maxC) {
            for (r in minR..maxR) {
                val underScoreboard = (r <= grid.sbSafeRows && abs(c - midCol) <= grid.sbColsHalf)
                if (!underScoreboard && !occupied.contains(SnakeCell(c, r))) {
                    candidates.add(SnakeCell(c, r))
                }
            }
        }
        if (candidates.isEmpty()) {
            for (c in 0 until grid.cols) {
                for (r in 0 until grid.rows) {
                    val cell = SnakeCell(c, r)
                    if (!occupied.contains(cell)) candidates.add(cell)
                }
            }
        }
        val picked = if (candidates.isNotEmpty()) {
            candidates[random.nextInt(candidates.size)]
        } else {
            SnakeCell(grid.cols / 2, grid.rows / 2)
        }
        food = SnakeFood(picked.col, picked.row, kind, nowNs)
    }

    companion object {
        const val INITIAL_LENGTH = 5
        const val BASE_STEP_MS = 132
        const val MIN_STEP_MS = 68
        const val MORPH_DURATION_MS = 360L

        fun computeGridMetrics(
            workWidthPx: Int,
            workHeightPx: Int,
            density: Float,
            formFactor: ResolvedFormFactor,
            hudScale: Float
        ): SnakeGridMetrics {
            val safeD = density.coerceAtLeast(0.75f)
            val safeW = workWidthPx.coerceAtLeast((240 * safeD).roundToInt())
            val safeH = workHeightPx.coerceAtLeast((320 * safeD).roundToInt())
            val scaleMod = (1f + (hudScale - 1f) * 0.10f).coerceIn(0.88f, 1.32f)

            val minTargetCols = if (formFactor.isPhone && !formFactor.isLandscape) 12 else 16
            val minTargetRows = if (formFactor.isPhone && !formFactor.isLandscape) 16 else 12
            val baseCellDp = when {
                formFactor.isLargeBoard -> 30f
                formFactor.deviceClass == FormFactorClass.TABLET -> 26f
                min(formFactor.widthDp, formFactor.heightDp) < 360 -> 21f
                else -> 24f
            }

            var cellPx = max(
                (18f * safeD).roundToInt(),
                (baseCellDp * safeD * scaleMod).roundToInt()
            )
            val horizPad = (14f * safeD).roundToInt()
            val vertPad = (16f * safeD).roundToInt()
            val maxCellForCols = max(14, (safeW - horizPad) / minTargetCols)
            val maxCellForRows = max(14, (safeH - vertPad) / minTargetRows)
            cellPx = min(cellPx, min(maxCellForCols, maxCellForRows)).coerceAtLeast((14f * safeD).roundToInt())

            val cols = max(10, (safeW - horizPad) / cellPx)
            val rows = max(12, (safeH - vertPad) / cellPx)
            val gridOffX = (safeW - cols * cellPx) / 2
            val gridOffY = (safeH - rows * cellPx) / 2

            val isCompactScoreboard = formFactor.isTightWidth || formFactor.widthDp < 580
            val sbWidthPx = if (isCompactScoreboard) {
                safeW - (16f * safeD).roundToInt()
            } else {
                min((616f * safeD).roundToInt(), safeW - (32f * safeD).roundToInt())
            }
            val sbHeightDp = if (isCompactScoreboard) 92f else 56f
            val sbColsHalf = max(4, ceil((sbWidthPx / 2f) / cellPx).toInt() + 1)
            val sbSafeRows = max(2, ceil((sbHeightDp * safeD) / cellPx).toInt())

            return SnakeGridMetrics(
                workW = safeW,
                workH = safeH,
                density = safeD,
                cellPx = cellPx,
                cols = cols,
                rows = rows,
                gridOffX = gridOffX,
                gridOffY = gridOffY,
                sbColsHalf = sbColsHalf,
                sbSafeRows = sbSafeRows,
                isCompactScoreboard = isCompactScoreboard
            )
        }

        fun decodeSwipeDirection(dxPx: Float, dyPx: Float, minSwipePx: Float): Pair<Int, Int>? {
            if (hypot(dxPx, dyPx) < minSwipePx) return null
            return if (abs(dxPx) >= abs(dyPx)) {
                if (dxPx >= 0f) 1 to 0 else -1 to 0
            } else {
                if (dyPx >= 0f) 0 to 1 else 0 to -1
            }
        }

        fun decodeJoystickAxis(
            axisX: Float,
            axisY: Float,
            hatX: Float,
            hatY: Float,
            deadzone: Float = 0.45f
        ): Pair<Int, Int>? {
            if (abs(hatX) >= 0.5f || abs(hatY) >= 0.5f) {
                return if (abs(hatX) >= abs(hatY)) {
                    (if (hatX > 0f) 1 else -1) to 0
                } else {
                    0 to (if (hatY > 0f) 1 else -1)
                }
            }
            if (abs(axisX) >= deadzone || abs(axisY) >= deadzone) {
                return if (abs(axisX) >= abs(axisY)) {
                    (if (axisX > 0f) 1 else -1) to 0
                } else {
                    0 to (if (axisY > 0f) 1 else -1)
                }
            }
            return null
        }

        fun mapKeyCodeToCommand(keyCode: Int): SnakeInputCommand? {
            return when (keyCode) {
                KeyEvent.KEYCODE_DPAD_UP,
                KeyEvent.KEYCODE_W,
                KeyEvent.KEYCODE_NUMPAD_8 -> SnakeInputCommand.Direction(0, -1)

                KeyEvent.KEYCODE_DPAD_DOWN,
                KeyEvent.KEYCODE_S,
                KeyEvent.KEYCODE_NUMPAD_2 -> SnakeInputCommand.Direction(0, 1)

                KeyEvent.KEYCODE_DPAD_LEFT,
                KeyEvent.KEYCODE_A,
                KeyEvent.KEYCODE_NUMPAD_4 -> SnakeInputCommand.Direction(-1, 0)

                KeyEvent.KEYCODE_DPAD_RIGHT,
                KeyEvent.KEYCODE_D,
                KeyEvent.KEYCODE_NUMPAD_6 -> SnakeInputCommand.Direction(1, 0)

                KeyEvent.KEYCODE_P,
                KeyEvent.KEYCODE_SPACE -> SnakeInputCommand.PauseOrRestart

                KeyEvent.KEYCODE_E,
                KeyEvent.KEYCODE_BUTTON_X,
                KeyEvent.KEYCODE_BUTTON_Y -> SnakeInputCommand.ToggleEdgeMode

                KeyEvent.KEYCODE_R -> SnakeInputCommand.Restart

                KeyEvent.KEYCODE_ENTER,
                KeyEvent.KEYCODE_NUMPAD_ENTER,
                KeyEvent.KEYCODE_DPAD_CENTER,
                KeyEvent.KEYCODE_BUTTON_A,
                KeyEvent.KEYCODE_BUTTON_START -> SnakeInputCommand.PauseOrRestart

                KeyEvent.KEYCODE_ESCAPE,
                KeyEvent.KEYCODE_BACK,
                KeyEvent.KEYCODE_BUTTON_B,
                KeyEvent.KEYCODE_BUTTON_SELECT -> SnakeInputCommand.Exit

                else -> null
            }
        }
    }
}
