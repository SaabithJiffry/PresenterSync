package com.saabithjiffry.presentersync.remote.ui.arcade

import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.random.Random

enum class BlockDropPhase {
    IDLE,
    PLAYING,
    PAUSED,
    GAME_OVER
}

enum class BlockKind(val fillArgb: Int, val wireArgb: Int) {
    I(0xAA06B6D4.toInt(), 0xFF67E8F9.toInt()),
    O(0xAAEAB308.toInt(), 0xFFFEF08A.toInt()),
    T(0xAAA855F7.toInt(), 0xFFE9D5FF.toInt()),
    S(0xAA22C55E.toInt(), 0xFFBBF7D0.toInt()),
    Z(0xAAEF4444.toInt(), 0xFFFECACA.toInt()),
    J(0xAA3B82F6.toInt(), 0xFFBFDBFE.toInt()),
    L(0xAAF97316.toInt(), 0xFFFED7AA.toInt())
}

data class BlockShockwave(
    val row: Int,
    var timer: Float,
    val maxTimer: Float,
    val argb: Int
)

data class BlockScorePopup(
    val text: String,
    var timer: Float,
    val maxTimer: Float,
    val argb: Int
)

/**
 * Pure Kotlin Neon Block Drop engine (zero Android framework dependencies).
 * Implements 7-bag randomizer, authentic SRS rotation + JLSTZ/I wall-kick tables,
 * Ghost landing guide, Hold, Next 3 preview, 500ms lock-delay grace, and T-Spin/Tetris scoring.
 */
class BlockDropEngine(
    private val random: Random = Random.Default,
    private val onNewHighScore: (Int) -> Unit = {}
) {
    companion object {
        const val COLS = 10
        const val ROWS = 20
        const val LOCK_DELAY_SEC = 0.50f
        const val MAX_LOCK_RESETS = 15

        private val SHAPES: Map<BlockKind, Array<Array<IntArray>>> = mapOf(
            BlockKind.I to arrayOf(
                arrayOf(intArrayOf(0, 1), intArrayOf(1, 1), intArrayOf(2, 1), intArrayOf(3, 1)),
                arrayOf(intArrayOf(2, 0), intArrayOf(2, 1), intArrayOf(2, 2), intArrayOf(2, 3)),
                arrayOf(intArrayOf(0, 2), intArrayOf(1, 2), intArrayOf(2, 2), intArrayOf(3, 2)),
                arrayOf(intArrayOf(1, 0), intArrayOf(1, 1), intArrayOf(1, 2), intArrayOf(1, 3))
            ),
            BlockKind.O to arrayOf(
                arrayOf(intArrayOf(1, 0), intArrayOf(2, 0), intArrayOf(1, 1), intArrayOf(2, 1)),
                arrayOf(intArrayOf(1, 0), intArrayOf(2, 0), intArrayOf(1, 1), intArrayOf(2, 1)),
                arrayOf(intArrayOf(1, 0), intArrayOf(2, 0), intArrayOf(1, 1), intArrayOf(2, 1)),
                arrayOf(intArrayOf(1, 0), intArrayOf(2, 0), intArrayOf(1, 1), intArrayOf(2, 1))
            ),
            BlockKind.T to arrayOf(
                arrayOf(intArrayOf(1, 0), intArrayOf(0, 1), intArrayOf(1, 1), intArrayOf(2, 1)),
                arrayOf(intArrayOf(1, 0), intArrayOf(1, 1), intArrayOf(2, 1), intArrayOf(1, 2)),
                arrayOf(intArrayOf(0, 1), intArrayOf(1, 1), intArrayOf(2, 1), intArrayOf(1, 2)),
                arrayOf(intArrayOf(1, 0), intArrayOf(0, 1), intArrayOf(1, 1), intArrayOf(1, 2))
            ),
            BlockKind.S to arrayOf(
                arrayOf(intArrayOf(1, 0), intArrayOf(2, 0), intArrayOf(0, 1), intArrayOf(1, 1)),
                arrayOf(intArrayOf(1, 0), intArrayOf(1, 1), intArrayOf(2, 1), intArrayOf(2, 2)),
                arrayOf(intArrayOf(1, 1), intArrayOf(2, 1), intArrayOf(0, 2), intArrayOf(1, 2)),
                arrayOf(intArrayOf(0, 0), intArrayOf(0, 1), intArrayOf(1, 1), intArrayOf(1, 2))
            ),
            BlockKind.Z to arrayOf(
                arrayOf(intArrayOf(0, 0), intArrayOf(1, 0), intArrayOf(1, 1), intArrayOf(2, 1)),
                arrayOf(intArrayOf(2, 0), intArrayOf(1, 1), intArrayOf(2, 1), intArrayOf(1, 2)),
                arrayOf(intArrayOf(0, 1), intArrayOf(1, 1), intArrayOf(1, 2), intArrayOf(2, 2)),
                arrayOf(intArrayOf(1, 0), intArrayOf(0, 1), intArrayOf(1, 1), intArrayOf(0, 2))
            ),
            BlockKind.J to arrayOf(
                arrayOf(intArrayOf(0, 0), intArrayOf(0, 1), intArrayOf(1, 1), intArrayOf(2, 1)),
                arrayOf(intArrayOf(1, 0), intArrayOf(2, 0), intArrayOf(1, 1), intArrayOf(1, 2)),
                arrayOf(intArrayOf(0, 1), intArrayOf(1, 1), intArrayOf(2, 1), intArrayOf(2, 2)),
                arrayOf(intArrayOf(1, 0), intArrayOf(1, 1), intArrayOf(0, 2), intArrayOf(1, 2))
            ),
            BlockKind.L to arrayOf(
                arrayOf(intArrayOf(2, 0), intArrayOf(0, 1), intArrayOf(1, 1), intArrayOf(2, 1)),
                arrayOf(intArrayOf(1, 0), intArrayOf(1, 1), intArrayOf(1, 2), intArrayOf(2, 2)),
                arrayOf(intArrayOf(0, 1), intArrayOf(1, 1), intArrayOf(2, 1), intArrayOf(0, 2)),
                arrayOf(intArrayOf(0, 0), intArrayOf(1, 0), intArrayOf(1, 1), intArrayOf(1, 2))
            )
        )

        private val KICKS_JLSTZ: Map<String, Array<IntArray>> = mapOf(
            "0>1" to arrayOf(intArrayOf(0, 0), intArrayOf(-1, 0), intArrayOf(-1, -1), intArrayOf(0, 2), intArrayOf(-1, 2)),
            "1>0" to arrayOf(intArrayOf(0, 0), intArrayOf(1, 0), intArrayOf(1, 1), intArrayOf(0, -2), intArrayOf(1, -2)),
            "1>2" to arrayOf(intArrayOf(0, 0), intArrayOf(1, 0), intArrayOf(1, 1), intArrayOf(0, -2), intArrayOf(1, -2)),
            "2>1" to arrayOf(intArrayOf(0, 0), intArrayOf(-1, 0), intArrayOf(-1, -1), intArrayOf(0, 2), intArrayOf(-1, 2)),
            "2>3" to arrayOf(intArrayOf(0, 0), intArrayOf(1, 0), intArrayOf(1, -1), intArrayOf(0, 2), intArrayOf(1, 2)),
            "3>2" to arrayOf(intArrayOf(0, 0), intArrayOf(-1, 0), intArrayOf(-1, 1), intArrayOf(0, -2), intArrayOf(-1, -2)),
            "3>0" to arrayOf(intArrayOf(0, 0), intArrayOf(-1, 0), intArrayOf(-1, 1), intArrayOf(0, -2), intArrayOf(-1, -2)),
            "0>3" to arrayOf(intArrayOf(0, 0), intArrayOf(1, 0), intArrayOf(1, -1), intArrayOf(0, 2), intArrayOf(1, 2))
        )

        private val KICKS_I: Map<String, Array<IntArray>> = mapOf(
            "0>1" to arrayOf(intArrayOf(0, 0), intArrayOf(-2, 0), intArrayOf(1, 0), intArrayOf(-2, 1), intArrayOf(1, -2)),
            "1>0" to arrayOf(intArrayOf(0, 0), intArrayOf(2, 0), intArrayOf(-1, 0), intArrayOf(2, -1), intArrayOf(-1, 2)),
            "1>2" to arrayOf(intArrayOf(0, 0), intArrayOf(-1, 0), intArrayOf(2, 0), intArrayOf(-1, -2), intArrayOf(2, 1)),
            "2>1" to arrayOf(intArrayOf(0, 0), intArrayOf(1, 0), intArrayOf(-2, 0), intArrayOf(1, 2), intArrayOf(-2, -1)),
            "2>3" to arrayOf(intArrayOf(0, 0), intArrayOf(2, 0), intArrayOf(-1, 0), intArrayOf(2, -1), intArrayOf(-1, 2)),
            "3>2" to arrayOf(intArrayOf(0, 0), intArrayOf(-2, 0), intArrayOf(1, 0), intArrayOf(-2, 1), intArrayOf(1, -2)),
            "3>0" to arrayOf(intArrayOf(0, 0), intArrayOf(1, 0), intArrayOf(-2, 0), intArrayOf(1, 2), intArrayOf(-2, -1)),
            "0>3" to arrayOf(intArrayOf(0, 0), intArrayOf(-1, 0), intArrayOf(2, 0), intArrayOf(-1, -2), intArrayOf(2, 1))
        )

        fun cellsFor(kind: BlockKind, rot: Int): Array<IntArray> {
            return SHAPES.getValue(kind)[rot and 3]
        }
    }

    var phase: BlockDropPhase = BlockDropPhase.IDLE
        private set
    var score: Int = 0
        private set
    var highScore: Int = 0
        private set
    var lines: Int = 0
        private set
    var level: Int = 1
        private set
    var b2b: Boolean = false
        private set
    var combo: Int = -1
        private set

    var curKind: BlockKind = BlockKind.T
        private set
    var curX: Int = 3
        private set
    var curY: Int = 0
        private set
    var curRot: Int = 0
        private set
    var holdKind: BlockKind? = null
        private set
    var holdUsed: Boolean = false
        private set

    var widthPx: Int = 1080
        private set
    var heightPx: Int = 1920
        private set
    var density: Float = 2f
        private set

    val board: Array<Array<BlockKind?>> = Array(ROWS) { arrayOfNulls<BlockKind?>(COLS) }
    val shockwaves: MutableList<BlockShockwave> = mutableListOf()
    val popups: MutableList<BlockScorePopup> = mutableListOf()

    private val bag: MutableList<BlockKind> = mutableListOf()
    private val queue: MutableList<BlockKind> = mutableListOf()

    private var gravAccum: Float = 0f
    private var lockTimer: Float = 0f
    private var lockResets: Int = 0
    private var softDrop: Boolean = false
    private var lastWasRotate: Boolean = false
    private var lastKickIdx: Int = 0

    fun startNewSession(
        widthPx: Int,
        heightPx: Int,
        screenDensity: Float,
        initialHighScore: Int
    ) {
        this.widthPx = max(320, widthPx)
        this.heightPx = max(480, heightPx)
        this.density = screenDensity.coerceIn(0.75f, 5f)
        this.highScore = max(0, initialHighScore)
        resetMatch()
    }

    fun updateDisplayMetrics(widthPx: Int, heightPx: Int, screenDensity: Float) {
        this.widthPx = max(320, widthPx)
        this.heightPx = max(480, heightPx)
        this.density = screenDensity.coerceIn(0.75f, 5f)
    }

    fun stop() {
        phase = BlockDropPhase.IDLE
        softDrop = false
    }

    fun resetMatch() {
        phase = BlockDropPhase.PLAYING
        for (r in 0 until ROWS) {
            for (c in 0 until COLS) {
                board[r][c] = null
            }
        }
        bag.clear()
        queue.clear()
        holdKind = null
        holdUsed = false
        score = 0
        lines = 0
        level = 1
        b2b = false
        combo = -1
        gravAccum = 0f
        lockTimer = 0f
        lockResets = 0
        softDrop = false
        lastWasRotate = false
        lastKickIdx = 0
        shockwaves.clear()
        popups.clear()
        ensureQueue()
        spawnNextPiece()
    }

    fun togglePause() {
        if (phase == BlockDropPhase.PLAYING) {
            phase = BlockDropPhase.PAUSED
        } else if (phase == BlockDropPhase.PAUSED) {
            phase = BlockDropPhase.PLAYING
        }
    }

    fun setSoftDrop(on: Boolean) {
        softDrop = on
    }

    fun nextPreview(count: Int = 3): List<BlockKind> {
        ensureQueue()
        return queue.take(count)
    }

    fun drawBagForTest(): BlockKind {
        return drawFromBag()
    }

    fun clearBagForTest() {
        bag.clear()
    }

    fun spawnPieceForTest(kind: BlockKind, x: Int, y: Int, rot: Int = 0) {
        curKind = kind
        curX = x
        curY = y
        curRot = rot and 3
        gravAccum = 0f
        lockTimer = 0f
        lockResets = 0
        lastWasRotate = false
        lastKickIdx = 0
    }

    fun fillRowForTest(row: Int, skipCol: Int = 0, kind: BlockKind = BlockKind.I) {
        if (row !in 0 until ROWS) return
        for (c in 0 until COLS) {
            board[row][c] = if (c == skipCol) null else kind
        }
    }

    private fun refillBag() {
        val list = BlockKind.entries.toMutableList()
        for (i in list.size - 1 downTo 1) {
            val j = random.nextInt(i + 1)
            val tmp = list[i]
            list[i] = list[j]
            list[j] = tmp
        }
        bag.addAll(list)
    }

    private fun drawFromBag(): BlockKind {
        if (bag.isEmpty()) refillBag()
        return bag.removeAt(0)
    }

    private fun ensureQueue() {
        while (queue.size < 4) {
            queue.add(drawFromBag())
        }
    }

    private fun spawnNextPiece() {
        ensureQueue()
        val kind = queue.removeAt(0)
        ensureQueue()
        spawnKind(kind)
    }

    private fun spawnKind(kind: BlockKind) {
        curKind = kind
        curRot = 0
        curX = 3
        curY = if (kind == BlockKind.I) -1 else 0
        gravAccum = 0f
        lockTimer = 0f
        lockResets = 0
        lastWasRotate = false
        lastKickIdx = 0
        if (!fits(curKind, curX, curY, curRot)) {
            triggerGameOver()
        }
    }

    private fun triggerGameOver() {
        phase = BlockDropPhase.GAME_OVER
        if (score > highScore) {
            highScore = score
            onNewHighScore(highScore)
        }
    }

    private fun fits(kind: BlockKind, px: Int, py: Int, rot: Int): Boolean {
        val cells = cellsFor(kind, rot)
        for (c in cells) {
            val bx = px + c[0]
            val by = py + c[1]
            if (bx < 0 || bx >= COLS || by >= ROWS) return false
            if (by >= 0 && board[by][bx] != null) return false
        }
        return true
    }

    private fun isGrounded(): Boolean = !fits(curKind, curX, curY + 1, curRot)

    private fun resetLockIfGrounded() {
        if (isGrounded() && lockResets < MAX_LOCK_RESETS) {
            lockTimer = 0f
            lockResets++
        }
    }

    fun move(dx: Int): Boolean {
        if (phase != BlockDropPhase.PLAYING) return false
        if (fits(curKind, curX + dx, curY, curRot)) {
            curX += dx
            lastWasRotate = false
            resetLockIfGrounded()
            return true
        }
        return false
    }

    fun rotate(dir: Int): Boolean {
        if (phase != BlockDropPhase.PLAYING) return false
        if (curKind == BlockKind.O) return true
        val oldRot = curRot and 3
        val newRot = (oldRot + if (dir > 0) 1 else 3) and 3
        val key = "$oldRot>$newRot"
        val kicks = if (curKind == BlockKind.I) KICKS_I.getValue(key) else KICKS_JLSTZ.getValue(key)
        for ((idx, off) in kicks.withIndex()) {
            val nx = curX + off[0]
            val ny = curY + off[1]
            if (fits(curKind, nx, ny, newRot)) {
                curX = nx
                curY = ny
                curRot = newRot
                lastWasRotate = true
                lastKickIdx = idx
                resetLockIfGrounded()
                return true
            }
        }
        return false
    }

    fun hold(): Boolean {
        if (phase != BlockDropPhase.PLAYING || holdUsed) return false
        val prev = holdKind
        holdKind = curKind
        holdUsed = true
        if (prev == null) {
            spawnNextPiece()
        } else {
            spawnKind(prev)
        }
        return true
    }

    fun hardDrop(): Int {
        if (phase != BlockDropPhase.PLAYING) return 0
        var dropped = 0
        while (fits(curKind, curX, curY + 1, curRot)) {
            curY++
            dropped++
        }
        if (dropped > 0) {
            score += dropped * 2
            lastWasRotate = false
        }
        lockCurrentPiece()
        return dropped
    }

    fun computeGhostY(): Int {
        var gy = curY
        while (fits(curKind, curX, gy + 1, curRot)) {
            gy++
        }
        return gy
    }

    private fun detectTSpin(): Boolean {
        if (curKind != BlockKind.T || !lastWasRotate) return false
        val corners = arrayOf(
            intArrayOf(curX, curY),
            intArrayOf(curX + 2, curY),
            intArrayOf(curX, curY + 2),
            intArrayOf(curX + 2, curY + 2)
        )
        var occ = 0
        for (pt in corners) {
            val px = pt[0]
            val py = pt[1]
            if (px < 0 || px >= COLS || py < 0 || py >= ROWS || board[py][px] != null) {
                occ++
            }
        }
        return occ >= 3
    }

    private fun lockCurrentPiece() {
        val cells = cellsFor(curKind, curRot)
        var aboveTop = false
        for (c in cells) {
            val bx = curX + c[0]
            val by = curY + c[1]
            if (by < 0) {
                aboveTop = true
                continue
            }
            if (bx in 0 until COLS && by in 0 until ROWS) {
                board[by][bx] = curKind
            }
        }

        val tspin = detectTSpin()
        val clearedRows = mutableListOf<Int>()
        var r = ROWS - 1
        while (r >= 0) {
            var full = true
            for (c in 0 until COLS) {
                if (board[r][c] == null) {
                    full = false
                    break
                }
            }
            if (full) {
                clearedRows.add(r)
                for (shift in r downTo 1) {
                    for (c in 0 until COLS) {
                        board[shift][c] = board[shift - 1][c]
                    }
                }
                for (c in 0 until COLS) {
                    board[0][c] = null
                }
            } else {
                r--
            }
        }

        val n = clearedRows.size
        if (n > 0) {
            combo++
            lines += n
            level = 1 + (lines / 10)
            val base: Int
            val label: String
            if (tspin) {
                base = when (n) {
                    1 -> 800
                    2 -> 1200
                    else -> 1600
                }
                label = when (n) {
                    1 -> "T-SPIN SINGLE"
                    2 -> "T-SPIN DOUBLE"
                    else -> "T-SPIN TRIPLE"
                }
            } else {
                base = when (n) {
                    1 -> 100
                    2 -> 300
                    3 -> 500
                    else -> 800
                }
                label = when (n) {
                    1 -> "SINGLE"
                    2 -> "DOUBLE"
                    3 -> "TRIPLE"
                    else -> "TETRIS!"
                }
            }
            val isDifficult = (n == 4 || tspin)
            val mult = if (isDifficult && b2b) 1.5f else 1.0f
            var pts = (base * mult * level).roundToInt()
            if (combo > 0) {
                pts += 50 * combo * level
            }
            score += pts
            b2b = isDifficult

            val waveCol = if (isDifficult) 0xFFFACC15.toInt() else 0xFF38BDF8.toInt()
            for (cr in clearedRows) {
                shockwaves.add(BlockShockwave(cr, 0.35f, 0.35f, waveCol))
            }
            val popTxt = (if (mult > 1f) "B2B " else "") + "$label +$pts"
            popups.add(BlockScorePopup(popTxt, 1.0f, 1.0f, waveCol))
        } else {
            combo = -1
            if (tspin) {
                val pts = 400 * level
                score += pts
                popups.add(BlockScorePopup("T-SPIN +$pts", 0.9f, 0.9f, 0xFFC084FC.toInt()))
            }
        }

        if (score > highScore) {
            highScore = score
            onNewHighScore(highScore)
        }

        if (aboveTop) {
            triggerGameOver()
            return
        }

        holdUsed = false
        spawnNextPiece()
    }

    fun step(dtSec: Float) {
        if (phase != BlockDropPhase.PLAYING) return
        val dt = dtSec.coerceIn(0f, 0.05f)

        val swIter = shockwaves.iterator()
        while (swIter.hasNext()) {
            val sw = swIter.next()
            sw.timer -= dt
            if (sw.timer <= 0f) swIter.remove()
        }
        val popIter = popups.iterator()
        while (popIter.hasNext()) {
            val p = popIter.next()
            p.timer -= dt
            if (p.timer <= 0f) popIter.remove()
        }

        var fallInterval = 0.80f
        for (i in 1 until level) {
            fallInterval *= 0.85f
        }
        fallInterval = max(0.055f, fallInterval)
        if (softDrop) {
            fallInterval = min(fallInterval, 0.045f)
        }

        gravAccum += dt
        while (gravAccum >= fallInterval) {
            gravAccum -= fallInterval
            if (fits(curKind, curX, curY + 1, curRot)) {
                curY++
                lockTimer = 0f
                lastWasRotate = false
                if (softDrop) score += 1
            } else {
                gravAccum = 0f
                break
            }
        }

        if (isGrounded()) {
            lockTimer += dt
            if (lockTimer >= LOCK_DELAY_SEC) {
                lockCurrentPiece()
            }
        } else {
            lockTimer = 0f
        }
    }
}
