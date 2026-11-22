package com.saabithjiffry.presentersync.remote.ui.arcade

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.random.Random

enum class PaddleGamePhase {
    IDLE,
    PLAYING,
    PAUSED,
    GAME_OVER
}

enum class BrickDropKind(val label: String) {
    MULTIBALL("MULTI"),
    WIDE_PADDLE("WIDE"),
    LASER("LASER")
}

data class BrickOrb(
    var x: Float,
    var y: Float,
    var vx: Float,
    var vy: Float,
    val radius: Float,
    var spin: Float = 0f,
    var stuck: Boolean = false
)

data class ArmoredBrick(
    var x: Float,
    var y: Float,
    val w: Float,
    val h: Float,
    var hp: Int,
    val maxHp: Int,
    val guaranteedDrop: BrickDropKind? = null
)

data class FallingPillDrop(
    val kind: BrickDropKind,
    var x: Float,
    var y: Float,
    val w: Float,
    val h: Float,
    var vy: Float
)

data class PaddleLaserBolt(
    var x: Float,
    var y: Float,
    val w: Float,
    val h: Float,
    val vy: Float
)

data class PaddleParticle(
    var x: Float,
    var y: Float,
    var vx: Float,
    var vy: Float,
    var lifeSec: Float,
    val maxLifeSec: Float,
    val colorRgb: Int
)

data class PaddleScorePopup(
    var x: Float,
    var y: Float,
    val text: String,
    var lifeSec: Float,
    val maxLifeSec: Float,
    val colorRgb: Int
)

/**
 * Pure Kotlin 2D elastic circle-vs-AABB and velocity-spin paddle physics core.
 * Zero Android framework imports so unit tests execute natively on the JVM without Robolectric.
 */
object PaddlePhysicsMath {
    fun collideOrbWithRect(
        orb: BrickOrb,
        rx: Float,
        ry: Float,
        rw: Float,
        rh: Float
    ): Boolean {
        val left = rx
        val top = ry
        val right = rx + rw
        val bottom = ry + rh
        val cx = orb.x.coerceIn(left, right)
        val cy = orb.y.coerceIn(top, bottom)
        val dx = orb.x - cx
        val dy = orb.y - cy
        if (dx * dx + dy * dy > orb.radius * orb.radius) return false

        val midX = left + rw * 0.5f
        val midY = top + rh * 0.5f
        val overlapX = (rw * 0.5f + orb.radius) - abs(orb.x - midX)
        val overlapY = (rh * 0.5f + orb.radius) - abs(orb.y - midY)

        if (overlapX < overlapY) {
            if (orb.x < midX) {
                orb.x = left - orb.radius - 0.5f
                orb.vx = -abs(orb.vx)
            } else {
                orb.x = right + orb.radius + 0.5f
                orb.vx = abs(orb.vx)
            }
        } else {
            if (orb.y < midY) {
                orb.y = top - orb.radius - 0.5f
                orb.vy = -abs(orb.vy)
            } else {
                orb.y = bottom + orb.radius + 0.5f
                orb.vy = abs(orb.vy)
            }
        }
        return true
    }

    fun bounceOffHorizontalPaddle(
        orb: BrickOrb,
        px: Float,
        py: Float,
        pw: Float,
        ph: Float,
        padVx: Float,
        minSpeed: Float,
        maxSpeed: Float
    ): Boolean {
        val left = px
        val top = py
        val right = px + pw
        val bottom = py + ph
        if (orb.x + orb.radius < left || orb.x - orb.radius > right ||
            orb.y + orb.radius < top || orb.y - orb.radius > bottom
        ) {
            return false
        }
        if (orb.vy <= 0f) return false

        val rel = ((orb.x - (left + pw * 0.5f)) / max(1f, pw * 0.5f)).coerceIn(-1f, 1f)
        val curSpd = hypot(orb.vx, orb.vy)
        val spd = (curSpd * 1.02f).coerceIn(minSpeed, maxSpeed)
        val ang = rel * 1.06f

        var vx = sin(ang) * spd + padVx * 0.35f
        var vy = -max(minSpeed * 0.45f, abs(cos(ang) * spd))

        val newSpd = hypot(vx, vy)
        val targetSpd = newSpd.coerceIn(minSpeed, maxSpeed)
        if (newSpd > 1f) {
            vx = (vx / newSpd) * targetSpd
            vy = (vy / newSpd) * targetSpd
        }
        if (abs(vy) < targetSpd * 0.32f) {
            vy = -targetSpd * 0.32f
            val sgn = if (vx < 0f) -1f else 1f
            vx = sgn * sqrt(max(1f, targetSpd * targetSpd - vy * vy))
        }

        orb.y = top - orb.radius - 1f
        orb.vx = vx
        orb.vy = vy
        orb.spin = (orb.spin * 0.5f + padVx * 0.85f).coerceIn(-520f, 520f)
        return true
    }

    fun bounceOffVerticalPaddle(
        puck: BrickOrb,
        px: Float,
        py: Float,
        pw: Float,
        ph: Float,
        padVy: Float,
        isLeftPaddle: Boolean,
        minSpeed: Float,
        maxSpeed: Float
    ): Boolean {
        val left = px
        val top = py
        val right = px + pw
        val bottom = py + ph
        if (puck.x + puck.radius < left || puck.x - puck.radius > right ||
            puck.y + puck.radius < top || puck.y - puck.radius > bottom
        ) {
            return false
        }
        if (isLeftPaddle && puck.vx >= 0f) return false
        if (!isLeftPaddle && puck.vx <= 0f) return false

        val rel = ((puck.y - (top + ph * 0.5f)) / max(1f, ph * 0.5f)).coerceIn(-1f, 1f)
        val curSpd = hypot(puck.vx, puck.vy)
        val spd = (curSpd * 1.045f).coerceIn(minSpeed, maxSpeed)
        val ang = rel * 0.96f
        val dirX = if (isLeftPaddle) 1f else -1f

        var vx = dirX * max(minSpeed * 0.52f, abs(cos(ang) * spd))
        var vy = sin(ang) * spd + padVy * 0.42f

        val newSpd = hypot(vx, vy)
        val targetSpd = newSpd.coerceIn(minSpeed, maxSpeed)
        if (newSpd > 1f) {
            vx = (vx / newSpd) * targetSpd
            vy = (vy / newSpd) * targetSpd
        }
        if (abs(vx) < targetSpd * 0.42f) {
            vx = dirX * targetSpd * 0.42f
            val sgnY = if (vy < 0f) -1f else 1f
            vy = sgnY * sqrt(max(1f, targetSpd * targetSpd - vx * vx))
        }

        puck.x = if (isLeftPaddle) (right + puck.radius + 1f) else (left - puck.radius - 1f)
        puck.vx = vx
        puck.vy = vy
        puck.spin = (padVy * 1.35f + rel * 180f).coerceIn(-720f, 720f)
        return true
    }
}

/**
 * Sector Z-03: Android Brick Breaker Engine.
 */
class BrickBreakerEngine(
    private val random: Random = Random.Default,
    private val onNewHighScore: (Int) -> Unit = {}
) {
    var phase: PaddleGamePhase = PaddleGamePhase.IDLE
        private set
    var worldWidth: Float = 1080f
        private set
    var worldHeight: Float = 1920f
        private set
    var density: Float = 2f
        private set
    var pillBumper: ArcadeRectF? = null

    var score: Int = 0
        private set
    var highScore: Int = 0
        private set
    var wave: Int = 1
        private set
    var lives: Int = 3
        private set

    var paddleX: Float = 420f
    var paddleY: Float = 1800f
    var paddleW: Float = 240f
    var basePaddleW: Float = 240f
    var paddleH: Float = 28f
    var paddleVx: Float = 0f

    var wideTimerSec: Float = 0f
    var laserTimerSec: Float = 0f
    var laserCooldownSec: Float = 0f

    var inputLeft: Boolean = false
    var inputRight: Boolean = false
    var touchDragActive: Boolean = false
    var touchTargetX: Float = 0f

    val orbs: MutableList<BrickOrb> = mutableListOf()
    val bricks: MutableList<ArmoredBrick> = mutableListOf()
    val drops: MutableList<FallingPillDrop> = mutableListOf()
    val lasers: MutableList<PaddleLaserBolt> = mutableListOf()
    val particles: MutableList<PaddleParticle> = mutableListOf()
    val popups: MutableList<PaddleScorePopup> = mutableListOf()

    fun startNewSession(
        widthPx: Int,
        heightPx: Int,
        screenDensity: Float,
        initialHighScore: Int = 0,
        bumperRect: ArcadeRectF? = null,
        clearInitialBricks: Boolean = false
    ) {
        worldWidth = max(320f, widthPx.toFloat())
        worldHeight = max(320f, heightPx.toFloat())
        density = screenDensity.coerceIn(0.75f, 5f)
        pillBumper = bumperRect
        highScore = max(highScore, initialHighScore)

        score = 0
        wave = 1
        lives = 3
        wideTimerSec = 0f
        laserTimerSec = 0f
        laserCooldownSec = 0f
        inputLeft = false
        inputRight = false
        touchDragActive = false

        basePaddleW = (118f * density).coerceIn(110f, worldWidth * 0.42f)
        paddleW = basePaddleW
        paddleH = 15f * density
        paddleX = (worldWidth - paddleW) * 0.5f
        paddleY = worldHeight - 44f * density
        paddleVx = 0f

        orbs.clear()
        bricks.clear()
        drops.clear()
        lasers.clear()
        particles.clear()
        popups.clear()

        resetOrbOnPaddle()
        phase = PaddleGamePhase.PLAYING
        if (!clearInitialBricks) {
            spawnWave(wave)
        }
    }

    fun updateDisplayMetrics(widthPx: Int, heightPx: Int, screenDensity: Float, bumperRect: ArcadeRectF? = null) {
        val newW = max(320f, widthPx.toFloat())
        val newH = max(320f, heightPx.toFloat())
        if (worldWidth > 0f && worldHeight > 0f) {
            val sx = newW / worldWidth
            val sy = newH / worldHeight
            paddleX *= sx
            paddleY = newH - 44f * screenDensity.coerceIn(0.75f, 5f)
            for (o in orbs) {
                o.x *= sx
                o.y *= sy
            }
            for (b in bricks) {
                b.x *= sx
                b.y *= sy
            }
        }
        worldWidth = newW
        worldHeight = newH
        density = screenDensity.coerceIn(0.75f, 5f)
        basePaddleW = (118f * density).coerceIn(110f, worldWidth * 0.42f)
        paddleW = if (wideTimerSec > 0f) basePaddleW * 1.55f else basePaddleW
        paddleH = 15f * density
        if (bumperRect != null) pillBumper = bumperRect
    }

    fun togglePause() {
        phase = when (phase) {
            PaddleGamePhase.PLAYING -> PaddleGamePhase.PAUSED
            PaddleGamePhase.PAUSED -> PaddleGamePhase.PLAYING
            else -> phase
        }
    }

    fun stop() {
        phase = PaddleGamePhase.IDLE
        orbs.clear()
        bricks.clear()
        drops.clear()
        lasers.clear()
        particles.clear()
        popups.clear()
    }

    fun resetOrbOnPaddle() {
        orbs.clear()
        val r = 8f * density
        orbs.add(
            BrickOrb(
                x = paddleX + paddleW * 0.5f,
                y = paddleY - r - 2f,
                vx = 185f * density,
                vy = -390f * density,
                radius = r,
                spin = 0f,
                stuck = true
            )
        )
    }

    fun launchOrFire(): Boolean {
        if (phase != PaddleGamePhase.PLAYING) return false
        var acted = false
        for (o in orbs) {
            if (o.stuck) {
                o.stuck = false
                if (abs(o.vy) < 150f * density) o.vy = -390f * density
                if (abs(o.vx) < 30f * density) o.vx = 165f * density
                acted = true
            }
        }
        if (laserTimerSec > 0f && laserCooldownSec <= 0f) {
            fireLaserBolts()
            acted = true
        }
        return acted
    }

    fun fireLaserBolts(): Boolean {
        if (phase != PaddleGamePhase.PLAYING) return false
        laserCooldownSec = 0.22f
        val lw = 3.5f * density
        val lh = 15f * density
        val lvy = -660f * density
        lasers.add(PaddleLaserBolt(paddleX + 10f * density, paddleY - lh, lw, lh, lvy))
        lasers.add(PaddleLaserBolt(paddleX + paddleW - 10f * density - lw, paddleY - lh, lw, lh, lvy))
        return true
    }

    fun spawnBrick(
        x: Float,
        y: Float,
        w: Float,
        h: Float,
        hp: Int = 1,
        guaranteedDrop: BrickDropKind? = null
    ): ArmoredBrick {
        val cleanHp = hp.coerceIn(1, 3)
        val br = ArmoredBrick(x, y, w, h, cleanHp, cleanHp, guaranteedDrop)
        bricks.add(br)
        return br
    }

    fun spawnDrop(kind: BrickDropKind, x: Float, y: Float): FallingPillDrop {
        val dr = FallingPillDrop(
            kind = kind,
            x = x,
            y = y,
            w = 56f * density,
            h = 20f * density,
            vy = 155f * density
        )
        drops.add(dr)
        return dr
    }

    fun step(dtSecRaw: Float) {
        if (phase != PaddleGamePhase.PLAYING) return
        val dt = dtSecRaw.coerceIn(0.001f, 0.05f)

        wideTimerSec = max(0f, wideTimerSec - dt)
        laserTimerSec = max(0f, laserTimerSec - dt)
        laserCooldownSec = max(0f, laserCooldownSec - dt)

        val targetW = if (wideTimerSec > 0f) min(worldWidth * 0.65f, basePaddleW * 1.55f) else basePaddleW
        if (abs(paddleW - targetW) > 0.5f) {
            val center = paddleX + paddleW * 0.5f
            paddleW = targetW
            paddleX = (center - paddleW * 0.5f).coerceIn(12f * density, worldWidth - paddleW - 12f * density)
        }

        val prevPx = paddleX
        val padMargin = 12f * density
        if (touchDragActive) {
            paddleX = (touchTargetX - paddleW * 0.5f).coerceIn(padMargin, worldWidth - paddleW - padMargin)
        } else {
            val padSpeed = 580f * density
            if (inputLeft) paddleX -= padSpeed * dt
            if (inputRight) paddleX += padSpeed * dt
            paddleX = paddleX.coerceIn(padMargin, worldWidth - paddleW - padMargin)
        }
        paddleVx = (paddleX - prevPx) / max(0.001f, dt)

        val minOrbSpd = 340f * density
        val maxOrbSpd = 680f * density
        val topWall = 62f * density
        val sideWall = 10f * density

        val orbIter = orbs.iterator()
        while (orbIter.hasNext()) {
            val o = orbIter.next()
            if (o.stuck) {
                o.x = paddleX + paddleW * 0.5f
                o.y = paddleY - o.radius - 2f
                continue
            }

            if (abs(o.spin) > 1f) {
                o.vx += o.spin * 0.22f * dt
                o.spin *= max(0.1f, 1f - 1.8f * dt)
            }

            o.x += o.vx * dt
            o.y += o.vy * dt

            if (o.x - o.radius < sideWall) {
                o.x = sideWall + o.radius
                o.vx = abs(o.vx)
            } else if (o.x + o.radius > worldWidth - sideWall) {
                o.x = worldWidth - sideWall - o.radius
                o.vx = -abs(o.vx)
            }
            if (o.y - o.radius < topWall) {
                o.y = topWall + o.radius
                o.vy = abs(o.vy)
            }

            PaddlePhysicsMath.bounceOffHorizontalPaddle(
                orb = o,
                px = paddleX,
                py = paddleY,
                pw = paddleW,
                ph = paddleH,
                padVx = paddleVx,
                minSpeed = minOrbSpd,
                maxSpeed = maxOrbSpd
            )

            pillBumper?.let { b ->
                PaddlePhysicsMath.collideOrbWithRect(o, b.left, b.top, b.right - b.left, b.bottom - b.top)
            }

            var hitIdx = -1
            for (i in bricks.indices) {
                val br = bricks[i]
                if (PaddlePhysicsMath.collideOrbWithRect(o, br.x, br.y, br.w, br.h)) {
                    hitIdx = i
                    break
                }
            }
            if (hitIdx >= 0) {
                damageBrickAt(hitIdx)
            }

            if (o.y - o.radius > worldHeight + 16f * density) {
                orbIter.remove()
            }
        }

        if (orbs.isEmpty()) {
            lives -= 1
            if (lives <= 0) {
                lives = 0
                phase = PaddleGamePhase.GAME_OVER
                return
            } else {
                wideTimerSec = 0f
                laserTimerSec = 0f
                resetOrbOnPaddle()
            }
        }

        // Advance laser bolts
        val laserIter = lasers.iterator()
        while (laserIter.hasNext()) {
            val ls = laserIter.next()
            ls.y += ls.vy * dt
            if (ls.y < topWall) {
                laserIter.remove()
                continue
            }
            var hitIdx = -1
            for (i in bricks.indices) {
                val br = bricks[i]
                if (ls.x + ls.w >= br.x && ls.x <= br.x + br.w &&
                    ls.y <= br.y + br.h && ls.y + ls.h >= br.y
                ) {
                    hitIdx = i
                    break
                }
            }
            if (hitIdx >= 0) {
                damageBrickAt(hitIdx)
                laserIter.remove()
            }
        }

        // Advance falling HUD-pill drops
        val dropIter = drops.iterator()
        while (dropIter.hasNext()) {
            val dr = dropIter.next()
            dr.y += dr.vy * dt
            if (dr.y - dr.h * 0.5f > worldHeight + 20f) {
                dropIter.remove()
                continue
            }
            if (dr.x + dr.w * 0.5f >= paddleX && dr.x - dr.w * 0.5f <= paddleX + paddleW &&
                dr.y + dr.h * 0.5f >= paddleY && dr.y - dr.h * 0.5f <= paddleY + paddleH
            ) {
                applyDrop(dr.kind, dr.x, dr.y)
                dropIter.remove()
            }
        }

        // Decay particles & popups
        val pIter = particles.iterator()
        while (pIter.hasNext()) {
            val pt = pIter.next()
            pt.x += pt.vx * dt
            pt.y += pt.vy * dt
            pt.lifeSec -= dt
            if (pt.lifeSec <= 0f) pIter.remove()
        }
        val popIter = popups.iterator()
        while (popIter.hasNext()) {
            val pp = popIter.next()
            pp.y -= 24f * density * dt
            pp.lifeSec -= dt
            if (pp.lifeSec <= 0f) popIter.remove()
        }

        if (bricks.isEmpty() && phase == PaddleGamePhase.PLAYING) {
            wave += 1
            awardScore(200, worldWidth * 0.5f, worldHeight * 0.45f, 0xFF38BDF8.toInt())
            spawnWave(wave)
            resetOrbOnPaddle()
        }
    }

    private fun damageBrickAt(index: Int) {
        if (index !in bricks.indices) return
        val br = bricks[index]
        br.hp -= 1
        val cx = br.x + br.w * 0.5f
        val cy = br.y + br.h * 0.5f
        if (br.hp > 0) {
            awardScore(15, cx, cy, 0xFFF59E0B.toInt())
            spawnBurst(cx, cy, 5, 0xFFF59E0B.toInt())
            return
        }
        bricks.removeAt(index)
        val pts = 30 * max(1, br.maxHp)
        awardScore(pts, cx, cy, 0xFF34D399.toInt())
        spawnBurst(cx, cy, 9, 0xFF38BDF8.toInt())

        val forced = br.guaranteedDrop
        if (forced != null) {
            spawnDrop(forced, cx, cy)
        } else if (random.nextFloat() < 0.24f) {
            val kinds = BrickDropKind.entries
            spawnDrop(kinds[random.nextInt(kinds.size)], cx, cy)
        }
    }

    private fun applyDrop(kind: BrickDropKind, x: Float, y: Float) {
        awardScore(50, x, y, 0xFF38BDF8.toInt())
        popups.add(PaddleScorePopup(x, y - 10f * density, kind.label, 0.9f, 0.9f, 0xFF38BDF8.toInt()))
        when (kind) {
            BrickDropKind.MULTIBALL -> {
                if (orbs.isEmpty()) resetOrbOnPaddle()
                val src = orbs.first()
                src.stuck = false
                val spd = max(380f * density, hypot(src.vx, src.vy))
                for (ang in floatArrayOf(-0.48f, 0.48f)) {
                    if (orbs.size >= 6) break
                    orbs.add(
                        BrickOrb(
                            x = src.x,
                            y = src.y,
                            vx = sin(ang) * spd,
                            vy = -abs(cos(ang) * spd),
                            radius = src.radius,
                            spin = 0f,
                            stuck = false
                        )
                    )
                }
            }
            BrickDropKind.WIDE_PADDLE -> {
                wideTimerSec = 12f
                paddleW = min(worldWidth * 0.65f, basePaddleW * 1.55f)
            }
            BrickDropKind.LASER -> {
                laserTimerSec = 10f
                laserCooldownSec = 0f
            }
        }
    }

    private fun spawnWave(waveNum: Int) {
        bricks.clear()
        val cols = 8
        val rows = min(7, 3 + waveNum)
        val marginX = max(20f * density, worldWidth * 0.07f)
        val gap = 6f * density
        val availW = worldWidth - marginX * 2f
        val bw = max(28f * density, (availW - gap * (cols - 1)) / cols)
        val bh = 20f * density
        val startY = 86f * density

        for (r in 0 until rows) {
            val hp = when {
                r == 0 && waveNum >= 2 -> 3
                r <= 1 -> min(3, 1 + ((waveNum + 1) / 2))
                else -> 1
            }
            for (c in 0 until cols) {
                val bx = marginX + c * (bw + gap)
                val by = startY + r * (bh + gap)
                spawnBrick(bx, by, bw, bh, hp)
            }
        }
    }

    private fun awardScore(pts: Int, x: Float, y: Float, colorRgb: Int) {
        score += pts
        if (score > highScore) {
            highScore = score
            onNewHighScore(highScore)
        }
        popups.add(PaddleScorePopup(x, y, "+$pts", 0.75f, 0.75f, colorRgb))
    }

    private fun spawnBurst(x: Float, y: Float, count: Int, colorRgb: Int) {
        repeat(count) {
            val ang = random.nextFloat() * (2f * PI.toFloat())
            val spd = (40f + random.nextFloat() * 110f) * density
            particles.add(PaddleParticle(x, y, cos(ang) * spd, sin(ang) * spd, 0.35f, 0.35f, colorRgb))
        }
    }
}

/**
 * Sector Z-04: Android Cyber Pong / Air Hockey Engine (1P vs Adaptive AI + 2P Split-Screen Touch).
 */
class CyberPongEngine(
    private val random: Random = Random.Default,
    private val onNewHighScore: (Int) -> Unit = {}
) {
    companion object {
        const val TARGET_SET_SCORE = 7
    }

    var phase: PaddleGamePhase = PaddleGamePhase.IDLE
        private set
    var worldWidth: Float = 1920f
        private set
    var worldHeight: Float = 1080f
        private set
    var density: Float = 2f
        private set

    var twoPlayerMode: Boolean = false
    var score: Int = 0
        private set
    var highScore: Int = 0
        private set
    var leftScore: Int = 0
    var rightScore: Int = 0
    var rally: Int = 0
        private set
    var bestRally: Int = 0
        private set
    var winnerLabel: String = ""
        private set

    var paddleW: Float = 24f
    var paddleH: Float = 160f
    var leftPaddleX: Float = 36f
    var leftPaddleY: Float = 460f
    var leftPaddleVy: Float = 0f

    var rightPaddleX: Float = 1860f
    var rightPaddleY: Float = 460f
    var rightPaddleVy: Float = 0f

    var puck: BrickOrb = BrickOrb(960f, 540f, 500f, 120f, 16f, 0f, false)

    // Keyboard & multi-touch inputs for Left (P1) and Right (P2) paddles
    var p1InputUp: Boolean = false
    var p1InputDown: Boolean = false
    var p2InputUp: Boolean = false
    var p2InputDown: Boolean = false

    var leftTouchActive: Boolean = false
    var leftTouchTargetY: Float = 0f
    var rightTouchActive: Boolean = false
    var rightTouchTargetY: Float = 0f

    val particles: MutableList<PaddleParticle> = mutableListOf()
    val popups: MutableList<PaddleScorePopup> = mutableListOf()

    fun startNewSession(
        widthPx: Int,
        heightPx: Int,
        screenDensity: Float,
        initialHighScore: Int = 0,
        preserveTwoPlayer: Boolean = true
    ) {
        worldWidth = max(320f, widthPx.toFloat())
        worldHeight = max(320f, heightPx.toFloat())
        density = screenDensity.coerceIn(0.75f, 5f)
        highScore = max(highScore, initialHighScore)
        if (!preserveTwoPlayer) twoPlayerMode = false

        score = 0
        leftScore = 0
        rightScore = 0
        rally = 0
        bestRally = 0
        winnerLabel = ""
        p1InputUp = false
        p1InputDown = false
        p2InputUp = false
        p2InputDown = false
        leftTouchActive = false
        rightTouchActive = false
        particles.clear()
        popups.clear()

        paddleW = 14f * density
        paddleH = (96f * density).coerceIn(80f, worldHeight * 0.34f)
        leftPaddleX = 22f * density
        rightPaddleX = worldWidth - 22f * density - paddleW
        leftPaddleY = (worldHeight - paddleH) * 0.5f
        rightPaddleY = (worldHeight - paddleH) * 0.5f
        leftPaddleVy = 0f
        rightPaddleVy = 0f

        servePuck(directionX = 1)
        phase = PaddleGamePhase.PLAYING
    }

    fun updateDisplayMetrics(widthPx: Int, heightPx: Int, screenDensity: Float) {
        val newW = max(320f, widthPx.toFloat())
        val newH = max(320f, heightPx.toFloat())
        if (worldWidth > 0f && worldHeight > 0f) {
            val sx = newW / worldWidth
            val sy = newH / worldHeight
            leftPaddleY *= sy
            rightPaddleY *= sy
            puck.x *= sx
            puck.y *= sy
        }
        worldWidth = newW
        worldHeight = newH
        density = screenDensity.coerceIn(0.75f, 5f)
        paddleW = 14f * density
        paddleH = (96f * density).coerceIn(80f, worldHeight * 0.34f)
        leftPaddleX = 22f * density
        rightPaddleX = worldWidth - 22f * density - paddleW
    }

    fun toggleTwoPlayerMode(): Boolean {
        twoPlayerMode = !twoPlayerMode
        rightTouchActive = false
        return twoPlayerMode
    }

    fun togglePause() {
        phase = when (phase) {
            PaddleGamePhase.PLAYING -> PaddleGamePhase.PAUSED
            PaddleGamePhase.PAUSED -> PaddleGamePhase.PLAYING
            else -> phase
        }
    }

    fun stop() {
        phase = PaddleGamePhase.IDLE
        particles.clear()
        popups.clear()
    }

    fun servePuck(directionX: Int = 1) {
        val dir = if (directionX >= 0) 1f else -1f
        rally = 0
        val vyRaw = (random.nextFloat() - 0.5f) * 260f * density
        val vy = if (abs(vyRaw) < 55f * density) 95f * density else vyRaw
        puck = BrickOrb(
            x = worldWidth * 0.5f,
            y = worldHeight * 0.5f,
            vx = dir * 430f * density,
            vy = vy,
            radius = 9.5f * density,
            spin = 0f,
            stuck = false
        )
    }

    fun step(dtSecRaw: Float) {
        if (phase != PaddleGamePhase.PLAYING) return
        val dt = dtSecRaw.coerceIn(0.001f, 0.05f)
        val topBound = 64f * density
        val botBound = worldHeight - 14f * density
        val padSpeed = 590f * density

        val prevLy = leftPaddleY
        val prevRy = rightPaddleY

        if (leftTouchActive) {
            leftPaddleY = (leftTouchTargetY - paddleH * 0.5f).coerceIn(topBound, botBound - paddleH)
        } else {
            val moveUp = if (twoPlayerMode) p1InputUp else (p1InputUp || p2InputUp)
            val moveDn = if (twoPlayerMode) p1InputDown else (p1InputDown || p2InputDown)
            if (moveUp) leftPaddleY -= padSpeed * dt
            if (moveDn) leftPaddleY += padSpeed * dt
            leftPaddleY = leftPaddleY.coerceIn(topBound, botBound - paddleH)
        }
        leftPaddleVy = (leftPaddleY - prevLy) / max(0.001f, dt)

        if (twoPlayerMode) {
            if (rightTouchActive) {
                rightPaddleY = (rightTouchTargetY - paddleH * 0.5f).coerceIn(topBound, botBound - paddleH)
            } else {
                if (p2InputUp) rightPaddleY -= padSpeed * dt
                if (p2InputDown) rightPaddleY += padSpeed * dt
                rightPaddleY = rightPaddleY.coerceIn(topBound, botBound - paddleH)
            }
            rightPaddleVy = (rightPaddleY - prevRy) / max(0.001f, dt)
        } else {
            val targetY = if (puck.vx > 0f) (puck.y + puck.spin * 0.14f) else (worldHeight * 0.5f)
            val centerR = rightPaddleY + paddleH * 0.5f
            val diff = targetY - centerR
            val aiSpeed = (470f + min(190f, rally * 15f)) * density
            val stepY = diff.coerceIn(-aiSpeed * dt, aiSpeed * dt)
            rightPaddleY = (rightPaddleY + stepY).coerceIn(topBound, botBound - paddleH)
            rightPaddleVy = (rightPaddleY - prevRy) / max(0.001f, dt)
        }

        // Magnus velocity-spin curve
        if (abs(puck.spin) > 0.5f) {
            puck.vy += puck.spin * dt
            puck.spin *= max(0.15f, 1f - 0.95f * dt)
        }

        puck.x += puck.vx * dt
        puck.y += puck.vy * dt

        if (puck.y - puck.radius < topBound) {
            puck.y = topBound + puck.radius
            puck.vy = abs(puck.vy)
            puck.spin = -puck.spin * 0.65f
        } else if (puck.y + puck.radius > botBound) {
            puck.y = botBound - puck.radius
            puck.vy = -abs(puck.vy)
            puck.spin = -puck.spin * 0.65f
        }

        val minSpd = 400f * density
        val maxSpd = 840f * density
        if (PaddlePhysicsMath.bounceOffVerticalPaddle(
                puck = puck,
                px = leftPaddleX,
                py = leftPaddleY,
                pw = paddleW,
                ph = paddleH,
                padVy = leftPaddleVy,
                isLeftPaddle = true,
                minSpeed = minSpd,
                maxSpeed = maxSpd
            )
        ) {
            onRallyDeflection(isLeft = true)
        } else if (PaddlePhysicsMath.bounceOffVerticalPaddle(
                puck = puck,
                px = rightPaddleX,
                py = rightPaddleY,
                pw = paddleW,
                ph = paddleH,
                padVy = rightPaddleVy,
                isLeftPaddle = false,
                minSpeed = minSpd,
                maxSpeed = maxSpd
            )
        ) {
            onRallyDeflection(isLeft = false)
        }

        // Goal checks
        if (puck.x + puck.radius < 0f) {
            rightScore += 1
            spawnBurst(24f * density, puck.y, 12, 0xFFFB7185.toInt())
            if (rightScore >= TARGET_SET_SCORE) {
                winnerLabel = if (twoPlayerMode) "PLAYER 2" else "CYBER AI"
                phase = PaddleGamePhase.GAME_OVER
                return
            }
            servePuck(directionX = -1)
        } else if (puck.x - puck.radius > worldWidth) {
            leftScore += 1
            awardScore(100 + rally * 15, worldWidth - 36f * density, puck.y, 0xFF34D399.toInt())
            spawnBurst(worldWidth - 24f * density, puck.y, 12, 0xFF34D399.toInt())
            if (leftScore >= TARGET_SET_SCORE) {
                winnerLabel = "PLAYER 1"
                awardScore(350, worldWidth * 0.5f, worldHeight * 0.5f, 0xFF38BDF8.toInt())
                phase = PaddleGamePhase.GAME_OVER
                return
            }
            servePuck(directionX = 1)
        }

        // Particles & popups
        val pIter = particles.iterator()
        while (pIter.hasNext()) {
            val pt = pIter.next()
            pt.x += pt.vx * dt
            pt.y += pt.vy * dt
            pt.lifeSec -= dt
            if (pt.lifeSec <= 0f) pIter.remove()
        }
        val popIter = popups.iterator()
        while (popIter.hasNext()) {
            val pp = popIter.next()
            pp.y -= 22f * density * dt
            pp.lifeSec -= dt
            if (pp.lifeSec <= 0f) popIter.remove()
        }
    }

    private fun onRallyDeflection(isLeft: Boolean) {
        rally += 1
        if (rally > bestRally) bestRally = rally
        if (isLeft) {
            awardScore(10 + rally * 2, puck.x + 14f * density, puck.y, 0xFF38BDF8.toInt())
        }
        spawnBurst(puck.x, puck.y, 7, if (isLeft) 0xFF38BDF8.toInt() else 0xFFF43F5E.toInt())
    }

    private fun awardScore(pts: Int, x: Float, y: Float, colorRgb: Int) {
        score += pts
        if (score > highScore) {
            highScore = score
            onNewHighScore(highScore)
        }
        popups.add(PaddleScorePopup(x, y, "+$pts", 0.7f, 0.7f, colorRgb))
    }

    private fun spawnBurst(x: Float, y: Float, count: Int, colorRgb: Int) {
        repeat(count) {
            val ang = random.nextFloat() * (2f * PI.toFloat())
            val spd = (45f + random.nextFloat() * 115f) * density
            particles.add(PaddleParticle(x, y, cos(ang) * spd, sin(ang) * spd, 0.32f, 0.32f, colorRgb))
        }
    }
}
