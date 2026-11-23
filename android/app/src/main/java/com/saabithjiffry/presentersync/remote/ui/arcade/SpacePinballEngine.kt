package com.saabithjiffry.presentersync.remote.ui.arcade

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

enum class SpacePinballPhase {
    IDLE, PLAYING, PAUSED, GAME_OVER
}

data class PinballWall(val x1: Float, val y1: Float, val x2: Float, val y2: Float, val e: Float)
data class PinballBumper(val x: Float, val y: Float, val r: Float, var level: Int = 1, var flash: Float = 0f)
data class PinballDropTarget(val x: Float, val y: Float, val w: Float, val h: Float, var down: Boolean = false, var flash: Float = 0f)
data class PinballRollover(val x: Float, val y: Float, val r: Float, val label: String, var lit: Boolean = false, var inside: Boolean = false)
data class PinballSling(
    val ax: Float, val ay: Float,
    val bx: Float, val by: Float,
    val cx: Float, val cy: Float,
    val nx: Float, val ny: Float,
    var flash: Float = 0f
)
data class PinballPopup(val text: String, var timer: Float, val maxTimer: Float, val argb: Int)
data class PinballTrailPt(val x: Float, val y: Float)

class SpacePinballEngine(
    private val onNewHighScore: (Int) -> Unit = {}
) {
    companion object {
        const val TW = 420f
        const val TH = 720f
        const val BALL_R = 9.5f
        const val GRAVITY = 780f
        const val SUBSTEPS = 4
        const val MAX_SPEED = 1450f
        val RANKS = listOf("Cadet", "Ensign", "Lieutenant", "Captain", "Commander", "Commodore", "Admiral")
    }

    var phase: SpacePinballPhase = SpacePinballPhase.IDLE
        private set
    var widthPx: Int = 1080
        private set
    var heightPx: Int = 1920
        private set
    var density: Float = 2f
        private set

    var score: Int = 0
        private set
    var highScore: Int = 0
        private set
    var ballsLeft: Int = 3
        private set
    var ballNum: Int = 1
        private set
    var multiplier: Int = 1
        private set
    var rankIdx: Int = 0
        private set
    var missionHits: Int = 0
        private set
    var missionTarget: Int = 6
        private set

    var ballX: Float = 378f
        private set
    var ballY: Float = 655f
        private set
    var ballVx: Float = 0f
        private set
    var ballVy: Float = 0f
        private set
    var ballInShooter: Boolean = true
        private set

    var plungerCharge: Float = 0f
        private set
    private var plungerHeld: Boolean = false

    var leftFlipperDown: Boolean = false
        private set
    var rightFlipperDown: Boolean = false
    var leftFlipperAngle: Float = 0.46f
        private set
    var rightFlipperAngle: Float = PI.toFloat() - 0.46f
        private set
    private var leftFlipperOmega: Float = 0f
    private var rightFlipperOmega: Float = 0f

    var ballSaveTimer: Float = 12f
        private set
    var tiltHeat: Float = 0f
        private set
    var tiltStrikes: Int = 0
        private set
    var tilted: Boolean = false
        private set
    var nudgeShake: Float = 0f
        private set
    private var orbitCd: Float = 0f
    private var nudgeToggle: Int = 0

    val walls = mutableListOf<PinballWall>()
    val slings = mutableListOf<PinballSling>()
    val bumpers = mutableListOf<PinballBumper>()
    val dropTargets = mutableListOf<PinballDropTarget>()
    val rollovers = mutableListOf<PinballRollover>()
    val popups = mutableListOf<PinballPopup>()
    val ballTrail = mutableListOf<PinballTrailPt>()

    fun startNewSession(widthPx: Int, heightPx: Int, screenDensity: Float, initialHighScore: Int) {
        this.widthPx = max(240, widthPx)
        this.heightPx = max(320, heightPx)
        this.density = screenDensity.coerceIn(0.75f, 5f)
        this.highScore = max(0, initialHighScore)
        buildGeometry()
        resetMatch()
    }

    fun updateDisplayMetrics(widthPx: Int, heightPx: Int, screenDensity: Float) {
        this.widthPx = max(240, widthPx)
        this.heightPx = max(320, heightPx)
        this.density = screenDensity.coerceIn(0.75f, 5f)
    }

    fun stop() {
        phase = SpacePinballPhase.IDLE
    }

    fun togglePause() {
        phase = when (phase) {
            SpacePinballPhase.PLAYING -> SpacePinballPhase.PAUSED
            SpacePinballPhase.PAUSED -> SpacePinballPhase.PLAYING
            else -> phase
        }
    }

    fun resetMatch() {
        score = 0
        ballsLeft = 3
        ballNum = 1
        multiplier = 1
        rankIdx = 0
        missionHits = 0
        missionTarget = 6
        popups.clear()

        bumpers.clear()
        bumpers.add(PinballBumper(142f, 230f, 20f))
        bumpers.add(PinballBumper(242f, 230f, 20f))
        bumpers.add(PinballBumper(192f, 300f, 20f))

        dropTargets.clear()
        dropTargets.add(PinballDropTarget(46f, 255f, 10f, 26f))
        dropTargets.add(PinballDropTarget(46f, 292f, 10f, 26f))
        dropTargets.add(PinballDropTarget(46f, 329f, 10f, 26f))

        rollovers.clear()
        rollovers.add(PinballRollover(136f, 112f, 12f, "L"))
        rollovers.add(PinballRollover(192f, 112f, 12f, "A"))
        rollovers.add(PinballRollover(248f, 112f, 12f, "U"))

        spawnBallInShooter()
        phase = SpacePinballPhase.PLAYING
    }

    private fun buildGeometry() {
        walls.clear()
        walls.add(PinballWall(24f, 150f, 24f, 610f, 0.55f))
        walls.add(PinballWall(396f, 150f, 396f, 685f, 0.55f))
        walls.add(PinballWall(360f, 155f, 360f, 685f, 0.50f))
        walls.add(PinballWall(360f, 685f, 396f, 685f, 0.25f))

        val archPts = 12
        var prevX = 24f
        var prevY = 150f
        for (i in 1..archPts) {
            val t = i.toFloat() / archPts.toFloat()
            val ang = PI.toFloat() * (1f - t)
            val nx = 210f + 186f * cos(ang)
            val ny = 150f - 122f * sin(ang)
            walls.add(PinballWall(prevX, prevY, nx, ny, 0.55f))
            prevX = nx
            prevY = ny
        }

        walls.add(PinballWall(24f, 610f, 112f, 668f, 0.40f))
        walls.add(PinballWall(360f, 610f, 272f, 668f, 0.40f))
        walls.add(PinballWall(64f, 495f, 64f, 572f, 0.45f))
        walls.add(PinballWall(64f, 572f, 120f, 628f, 0.35f))
        walls.add(PinballWall(320f, 495f, 320f, 572f, 0.45f))
        walls.add(PinballWall(320f, 572f, 264f, 628f, 0.35f))
        walls.add(PinballWall(164f, 88f, 164f, 136f, 0.50f))
        walls.add(PinballWall(220f, 88f, 220f, 136f, 0.50f))

        slings.clear()
        slings.add(PinballSling(64f, 495f, 112f, 578f, 64f, 568f, 0.86f, -0.50f))
        slings.add(PinballSling(320f, 495f, 272f, 578f, 320f, 568f, -0.86f, -0.50f))
    }

    private fun spawnBallInShooter() {
        ballX = 378f
        ballY = 655f
        ballVx = 0f
        ballVy = 0f
        ballInShooter = true
        ballTrail.clear()
        plungerCharge = 0f
        plungerHeld = false
        ballSaveTimer = 12f
        tiltHeat = 0f
        tiltStrikes = 0
        tilted = false
        nudgeShake = 0f
        orbitCd = 0f
    }

    fun setFlippers(leftDown: Boolean, rightDown: Boolean) {
        if (tilted) {
            leftFlipperDown = false
            rightFlipperDown = false
        } else {
            leftFlipperDown = leftDown
            rightFlipperDown = rightDown
        }
    }

    fun setPlungerHeld(held: Boolean) {
        if (phase != SpacePinballPhase.PLAYING) return
        if (held) {
            plungerHeld = true
        } else if (plungerHeld) {
            plungerHeld = false
            releasePlunger()
        }
    }

    fun releasePlunger(overrideCharge: Float? = null) {
        if (phase != SpacePinballPhase.PLAYING) return
        val ch = overrideCharge?.coerceIn(0.05f, 1f) ?: plungerCharge
        if (ballInShooter && ballY > 560f) {
            val spd = 720f + 680f * max(0.15f, ch)
            ballVy = -spd
            ballVx = -14f
            addPopup("LAUNCH!", 0xFF38BDF8.toInt())
        }
        plungerCharge = 0f
    }

    fun nudge(): Boolean {
        if (phase != SpacePinballPhase.PLAYING || tilted || ballInShooter) return false
        nudgeShake = 0.22f
        tiltHeat += 1f
        tiltStrikes += 1
        ballVy -= 95f
        nudgeToggle = (nudgeToggle + 1) % 2
        ballVx += if (nudgeToggle == 0) 55f else -55f
        if (tiltStrikes >= 3 || tiltHeat >= 2.6f) {
            tilted = true
            leftFlipperDown = false
            rightFlipperDown = false
            addPopup("TILT! FLIPPERS LOCKED", 0xFFEF4444.toInt())
        } else {
            addPopup("WARNING! NUDGE $tiltStrikes/3", 0xFFF59E0B.toInt())
        }
        return true
    }

    fun setBallForTest(x: Float, y: Float, vx: Float = 0f, vy: Float = 0f, inShooter: Boolean = false) {
        ballX = x
        ballY = y
        ballVx = vx
        ballVy = vy
        ballInShooter = inShooter
    }

    fun advanceMissionForTest(hits: Int) = advanceMission(hits)

    fun rankName(): String = RANKS[rankIdx.coerceIn(0, RANKS.lastIndex)]

    private fun addScore(pts: Int) {
        val add = (pts * multiplier)
        score += add
        if (score > highScore) {
            highScore = score
            onNewHighScore(highScore)
        }
    }

    private fun addPopup(text: String, argb: Int) {
        popups.add(PinballPopup(text, 1.2f, 1.2f, argb))
        if (popups.size > 4) popups.removeAt(0)
    }

    private fun advanceMission(hits: Int) {
        missionHits += hits
        if (missionHits >= missionTarget) {
            missionHits = 0
            missionTarget = min(12, missionTarget + 2)
            if (rankIdx < RANKS.lastIndex) rankIdx += 1
            addScore(2500 * (rankIdx + 1))
            addPopup("RANK UP: ${rankName().uppercase()}", 0xFFA855F7.toInt())
        }
    }

    fun step(dtSec: Float) {
        if (phase != SpacePinballPhase.PLAYING) return
        val dt = dtSec.coerceIn(0.001f, 0.033f)

        if (plungerHeld && ballInShooter) {
            plungerCharge = min(1f, plungerCharge + dt * 1.15f)
        }
        if (!ballInShooter && ballSaveTimer > 0f) {
            ballSaveTimer = max(0f, ballSaveTimer - dt)
        }
        if (tiltHeat > 0f) {
            tiltHeat = max(0f, tiltHeat - dt * 0.35f)
            if (tiltHeat <= 0.05f && !tilted) tiltStrikes = 0
        }
        if (nudgeShake > 0f) nudgeShake = max(0f, nudgeShake - dt)
        if (orbitCd > 0f) orbitCd = max(0f, orbitCd - dt)

        for (b in bumpers) if (b.flash > 0f) b.flash = max(0f, b.flash - dt)
        for (s in slings) if (s.flash > 0f) s.flash = max(0f, s.flash - dt)
        for (d in dropTargets) if (d.flash > 0f) d.flash = max(0f, d.flash - dt)

        val it = popups.iterator()
        while (it.hasNext()) {
            val p = it.next()
            p.timer -= dt
            if (p.timer <= 0f) it.remove()
        }

        val subDt = dt / SUBSTEPS.toFloat()
        for (i in 0 until SUBSTEPS) {
            subStep(subDt)
            if (phase != SpacePinballPhase.PLAYING) break
        }

        ballTrail.add(PinballTrailPt(ballX, ballY))
        if (ballTrail.size > 10) ballTrail.removeAt(0)
    }

    private fun subStep(subDt: Float) {
        val lTarget = if (!tilted && leftFlipperDown) -0.54f else 0.46f
        val rTarget = if (!tilted && rightFlipperDown) (PI.toFloat() + 0.54f) else (PI.toFloat() - 0.46f)
        val lPrev = leftFlipperAngle
        val rPrev = rightFlipperAngle

        leftFlipperAngle = moveAngleToward(lPrev, lTarget, 22f * subDt)
        rightFlipperAngle = moveAngleToward(rPrev, rTarget, 22f * subDt)
        leftFlipperOmega = (leftFlipperAngle - lPrev) / subDt
        rightFlipperOmega = (rightFlipperAngle - rPrev) / subDt

        ballVy += GRAVITY * subDt
        val damp = max(0f, 1f - 0.12f * subDt)
        ballVx *= damp
        ballVy *= damp

        val spd = sqrt(ballVx * ballVx + ballVy * ballVy)
        if (spd > MAX_SPEED) {
            val f = MAX_SPEED / spd
            ballVx *= f
            ballVy *= f
        }

        ballX += ballVx * subDt
        ballY += ballVy * subDt

        if (ballInShooter && ballX < 350f) ballInShooter = false
        if (!ballInShooter) {
            collideSegment(360f, 80f, 360f, 155f, 0.50f)
        }

        for (w in walls) collideSegment(w.x1, w.y1, w.x2, w.y2, w.e)

        for (s in slings) {
            val hit = collideSegment(s.ax, s.ay, s.bx, s.by, 0.65f)
            if (hit && !tilted) {
                ballVx += s.nx * 410f
                ballVy += s.ny * 410f
                s.flash = 0.16f
                addScore(100)
            }
            collideSegment(s.bx, s.by, s.cx, s.cy, 0.45f)
            collideSegment(s.cx, s.cy, s.ax, s.ay, 0.45f)
        }

        collideFlipper(120f, 628f, 58f, 6.5f, lPrev, leftFlipperAngle, leftFlipperOmega)
        collideFlipper(264f, 628f, 58f, 6.5f, rPrev, rightFlipperAngle, rightFlipperOmega)

        var allUpgraded = true
        for (b in bumpers) {
            val dx = ballX - b.x
            val dy = ballY - b.y
            val dist = sqrt(dx * dx + dy * dy)
            val minD = BALL_R + b.r
            if (dist < minD && dist > 0.0001f) {
                val nx = dx / dist
                val ny = dy / dist
                ballX = b.x + nx * minD
                ballY = b.y + ny * minD
                if (!tilted) {
                    val vn = ballVx * nx + ballVy * ny
                    if (vn < 0f) {
                        ballVx -= 1.85f * vn * nx
                        ballVy -= 1.85f * vn * ny
                    }
                    val curS = sqrt(ballVx * ballVx + ballVy * ballVy)
                    if (curS < 460f) {
                        ballVx = nx * 460f
                        ballVy = ny * 460f
                    }
                    b.flash = 0.18f
                    addScore(150 * b.level)
                    advanceMission(1)
                } else {
                    reflectNormal(nx, ny, 0.45f)
                }
            }
            if (b.level < 3) allUpgraded = false
        }

        var allDown = true
        for (d in dropTargets) {
            if (!d.down) {
                if (collideRect(d.x, d.y, d.w, d.h, 0.70f)) {
                    if (!tilted) {
                        d.down = true
                        d.flash = 0.25f
                        addScore(500)
                        advanceMission(1)
                    }
                }
            }
            if (!d.down) allDown = false
        }
        if (allDown) {
            for (d in dropTargets) d.down = false
            multiplier = min(10, multiplier + 1)
            addScore(1500)
            addPopup("DROP BANK! ${multiplier}x MULTIPLIER", 0xFF22C55E.toInt())
            if (!allUpgraded) {
                for (b in bumpers) b.level = min(3, b.level + 1)
            }
        }

        var allLit = true
        for (r in rollovers) {
            val dx = ballX - r.x
            val dy = ballY - r.y
            val inZone = (dx * dx + dy * dy) <= (r.r + BALL_R) * (r.r + BALL_R)
            if (inZone && !r.inside && !tilted) {
                r.lit = !r.lit
                addScore(250)
            }
            r.inside = inZone
            if (!r.lit) allLit = false
        }
        if (allLit) {
            for (r in rollovers) r.lit = false
            ballSaveTimer = max(ballSaveTimer, 10f)
            advanceMission(3)
            addPopup("ROLLOVERS! BALL SAVE + RANK+", 0xFFFACC15.toInt())
        }

        if (!ballInShooter && orbitCd <= 0f && ballY < 170f && (ballX < 70f || ballX > 310f)) {
            if (sqrt(ballVx * ballVx + ballVy * ballVy) > 380f) {
                orbitCd = 1.4f
                addScore(1000)
                advanceMission(1)
                addPopup("ORBIT LOOP! +1000", 0xFF38BDF8.toInt())
            }
        }

        if (ballY > TH - 12f && !ballInShooter) {
            if (ballSaveTimer > 0f && !tilted) {
                addPopup("BALL SAVED!", 0xFF22C55E.toInt())
                spawnBallInShooter()
                ballSaveTimer = 0f
            } else {
                ballsLeft -= 1
                if (ballsLeft <= 0) {
                    phase = SpacePinballPhase.GAME_OVER
                    if (score > highScore) {
                        highScore = score
                        onNewHighScore(highScore)
                    }
                } else {
                    ballNum += 1
                    multiplier = 1
                    spawnBallInShooter()
                }
            }
        }
    }

    private fun moveAngleToward(cur: Float, target: Float, maxDelta: Float): Float {
        val diff = target - cur
        return if (abs(diff) <= maxDelta) target else cur + if (diff > 0f) maxDelta else -maxDelta
    }

    private fun reflectNormal(nx: Float, ny: Float, e: Float) {
        val vn = ballVx * nx + ballVy * ny
        if (vn < 0f) {
            ballVx -= (1f + e) * vn * nx
            ballVy -= (1f + e) * vn * ny
        }
    }

    private fun collideSegment(x1: Float, y1: Float, x2: Float, y2: Float, e: Float): Boolean {
        val abx = x2 - x1
        val aby = y2 - y1
        val lenSq = abx * abx + aby * aby
        if (lenSq < 0.0001f) return false
        val t = (((ballX - x1) * abx + (ballY - y1) * aby) / lenSq).coerceIn(0f, 1f)
        val cx = x1 + t * abx
        val cy = y1 + t * aby
        val dx = ballX - cx
        val dy = ballY - cy
        val distSq = dx * dx + dy * dy
        if (distSq >= BALL_R * BALL_R || distSq < 0.000001f) return false
        val dist = sqrt(distSq)
        val nx = dx / dist
        val ny = dy / dist
        ballX = cx + nx * BALL_R
        ballY = cy + ny * BALL_R
        reflectNormal(nx, ny, e)
        return true
    }

    private fun collideRect(rx: Float, ry: Float, rw: Float, rh: Float, e: Float): Boolean {
        val cx = ballX.coerceIn(rx, rx + rw)
        val cy = ballY.coerceIn(ry, ry + rh)
        val dx = ballX - cx
        val dy = ballY - cy
        val distSq = dx * dx + dy * dy
        if (distSq >= BALL_R * BALL_R) return false
        val dist = sqrt(distSq)
        val nx: Float
        val ny: Float
        if (dist < 0.0001f) {
            nx = 1f
            ny = 0f
        } else {
            nx = dx / dist
            ny = dy / dist
        }
        ballX = cx + nx * BALL_R
        ballY = cy + ny * BALL_R
        reflectNormal(nx, ny, e)
        return true
    }

    private fun collideFlipper(px: Float, py: Float, len: Float, capR: Float, prevAng: Float, curAng: Float, omega: Float): Boolean {
        val angles = floatArrayOf((prevAng + curAng) * 0.5f, curAng)
        for (ang in angles) {
            val tx = px + cos(ang) * len
            val ty = py + sin(ang) * len
            val abx = tx - px
            val aby = ty - py
            val lenSq = abx * abx + aby * aby
            val t = (((ballX - px) * abx + (ballY - py) * aby) / lenSq).coerceIn(0f, 1f)
            val cx = px + t * abx
            val cy = py + t * aby
            val dx = ballX - cx
            val dy = ballY - cy
            val distSq = dx * dx + dy * dy
            val minR = BALL_R + capR
            if (distSq < minR * minR && distSq > 0.000001f) {
                val dist = sqrt(distSq)
                val nx = dx / dist
                val ny = dy / dist
                ballX = cx + nx * minR
                ballY = cy + ny * minR
                val rx = cx - px
                val ry = cy - py
                val surfVx = -omega * ry
                val surfVy = omega * rx
                val relVx = ballVx - surfVx
                val relVy = ballVy - surfVy
                val vn = relVx * nx + relVy * ny
                if (vn < 0f) {
                    val e = 0.55f
                    ballVx -= (1f + e) * vn * nx
                    ballVy -= (1f + e) * vn * ny
                }
                return true
            }
        }
        return false
    }
}
