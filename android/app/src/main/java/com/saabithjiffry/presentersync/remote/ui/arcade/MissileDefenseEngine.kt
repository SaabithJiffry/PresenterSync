package com.saabithjiffry.presentersync.remote.ui.arcade

import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.random.Random

enum class MissileDefensePhase {
    PLAYING,
    PAUSED,
    GAME_OVER
}

data class ShieldPylon(
    var x: Float,
    var y: Float,
    var alive: Boolean = true,
    var radius: Float = 24f
)

data class IncomingMeteor(
    var x: Float,
    var y: Float,
    var vx: Float,
    var vy: Float,
    var radius: Float,
    var isSplitter: Boolean,
    var splitDone: Boolean,
    var splitY: Float,
    val trailX: MutableList<Float> = mutableListOf(),
    val trailY: MutableList<Float> = mutableListOf()
)

data class InterceptorMissile(
    val sx: Float,
    val sy: Float,
    var x: Float,
    var y: Float,
    val tx: Float,
    val ty: Float,
    val vx: Float,
    val vy: Float,
    val speed: Float
)

data class ShockwaveBlast(
    val x: Float,
    val y: Float,
    var r: Float,
    val maxR: Float,
    var ageSec: Float = 0f,
    val lifeSec: Float = 0.86f,
    var kills: Int = 0
)

data class DefenseParticle(
    var x: Float,
    var y: Float,
    val vx: Float,
    val vy: Float,
    var lifeSec: Float,
    val color: Int
)

data class DefensePopup(
    val x: Float,
    var y: Float,
    val text: String,
    val color: Int,
    var lifeSec: Float = 0.85f
)

/**
 * Pure-Kotlin Missile Command / Meteor Defense engine (no android.graphics.RectF dependencies).
 */
class MissileDefenseEngine(
    private val random: Random = Random.Default,
    private val onNewHighScore: (Int) -> Unit = {}
) {
    var phase: MissileDefensePhase = MissileDefensePhase.PLAYING
        private set

    var widthPx: Float = 1080f
        private set
    var heightPx: Float = 1920f
        private set
    var density: Float = 2f
        private set

    var score: Int = 0
        private set
    var highScore: Int = 0
        private set
    var wave: Int = 1
        private set
    var combo: Int = 0
        private set

    var siloX: Float = 540f
        private set
    var siloY: Float = 1860f
        private set

    var reticleX: Float = 540f
    var reticleY: Float = 860f
    var inputLeft: Boolean = false
    var inputRight: Boolean = false
    var inputUp: Boolean = false
    var inputDown: Boolean = false

    val pylons: MutableList<ShieldPylon> = mutableListOf()
    val meteors: MutableList<IncomingMeteor> = mutableListOf()
    val interceptors: MutableList<InterceptorMissile> = mutableListOf()
    val blasts: MutableList<ShockwaveBlast> = mutableListOf()
    val particles: MutableList<DefenseParticle> = mutableListOf()
    val popups: MutableList<DefensePopup> = mutableListOf()

    var wavePending: Int = 0
    private var spawnCdSec: Float = 0f
    private var waveDelaySec: Float = 0f
    private var fireCdSec: Float = 0f
    private var comboTimerSec: Float = 0f

    val pylonsAlive: Int
        get() = pylons.count { it.alive }

    fun startNewSession(
        widthPx: Int,
        heightPx: Int,
        screenDensity: Float,
        initialHighScore: Int,
        clearInitialWave: Boolean = false
    ) {
        this.widthPx = max(320f, widthPx.toFloat())
        this.heightPx = max(320f, heightPx.toFloat())
        this.density = screenDensity.coerceIn(0.75f, 5f)
        this.highScore = max(0, initialHighScore)

        score = 0
        wave = 1
        combo = 0
        comboTimerSec = 0f
        fireCdSec = 0f
        waveDelaySec = 0f
        siloX = this.widthPx * 0.5f
        siloY = this.heightPx - 32f * this.density
        reticleX = this.widthPx * 0.5f
        reticleY = this.heightPx * 0.45f

        pylons.clear()
        val pylonY = this.heightPx - 38f * this.density
        val pylonR = 20f * this.density
        val ratios = floatArrayOf(0.16f, 0.34f, 0.66f, 0.84f)
        for (ratio in ratios) {
            pylons.add(ShieldPylon(x = this.widthPx * ratio, y = pylonY, alive = true, radius = pylonR))
        }

        meteors.clear()
        interceptors.clear()
        blasts.clear()
        particles.clear()
        popups.clear()

        if (clearInitialWave) {
            wavePending = 0
            spawnCdSec = 0f
        } else {
            startWave(1)
        }
        phase = MissileDefensePhase.PLAYING
    }

    fun updateDisplayMetrics(widthPx: Int, heightPx: Int, screenDensity: Float) {
        this.widthPx = max(320f, widthPx.toFloat())
        this.heightPx = max(320f, heightPx.toFloat())
        this.density = screenDensity.coerceIn(0.75f, 5f)
        siloX = this.widthPx * 0.5f
        siloY = this.heightPx - 32f * this.density
        val pylonY = this.heightPx - 38f * this.density
        val pylonR = 20f * this.density
        val ratios = floatArrayOf(0.16f, 0.34f, 0.66f, 0.84f)
        for (i in pylons.indices) {
            if (i < ratios.size) {
                pylons[i].x = this.widthPx * ratios[i]
                pylons[i].y = pylonY
                pylons[i].radius = pylonR
            }
        }
    }

    fun togglePause() {
        phase = when (phase) {
            MissileDefensePhase.PLAYING -> MissileDefensePhase.PAUSED
            MissileDefensePhase.PAUSED -> MissileDefensePhase.PLAYING
            MissileDefensePhase.GAME_OVER -> MissileDefensePhase.GAME_OVER
        }
    }

    fun stop() {
        meteors.clear()
        interceptors.clear()
        blasts.clear()
        particles.clear()
        popups.clear()
    }

    fun spawnMeteor(x: Float, y: Float, vx: Float, vy: Float, isSplitter: Boolean = false): IncomingMeteor {
        val m = IncomingMeteor(
            x = x,
            y = y,
            vx = vx,
            vy = vy,
            radius = (if (isSplitter) 9f else 7f) * density,
            isSplitter = isSplitter,
            splitDone = false,
            splitY = heightPx * 0.42f
        )
        meteors.add(m)
        return m
    }

    fun fireInterceptor(tx: Float, ty: Float, bypassCooldown: Boolean = false): Boolean {
        if (phase != MissileDefensePhase.PLAYING) return false
        if (!bypassCooldown && fireCdSec > 0f) return false

        val clampedX = tx.coerceIn(20f * density, widthPx - 20f * density)
        val clampedY = ty.coerceIn(56f * density, heightPx - 56f * density)
        val (ox, oy) = pickLauncherOrigin(clampedX)
        val dx = clampedX - ox
        val dy = clampedY - oy
        val dist = max(1f, sqrt(dx * dx + dy * dy))
        val spd = 680f * density

        interceptors.add(
            InterceptorMissile(
                sx = ox,
                sy = oy,
                x = ox,
                y = oy,
                tx = clampedX,
                ty = clampedY,
                vx = (dx / dist) * spd,
                vy = (dy / dist) * spd,
                speed = spd
            )
        )
        fireCdSec = 0.08f
        return true
    }

    private fun pickLauncherOrigin(tx: Float): Pair<Float, Float> {
        var bestX = siloX
        var bestY = siloY
        var bestDist = abs(tx - siloX)
        for (p in pylons) {
            if (!p.alive) continue
            val d = abs(tx - p.x)
            if (d < bestDist) {
                bestDist = d
                bestX = p.x
                bestY = p.y - 8f * density
            }
        }
        return bestX to bestY
    }

    private fun startWave(waveNum: Int) {
        wave = waveNum
        wavePending = 5 + waveNum * 3
        spawnCdSec = 0.42f
    }

    fun step(dtSec: Float) {
        if (phase != MissileDefensePhase.PLAYING) return
        var rem = max(0f, dtSec)
        while (rem > 0f) {
            val stepDt = min(0.025f, rem)
            stepInternal(stepDt)
            rem -= stepDt
        }
    }

    private fun stepInternal(dt: Float) {
        fireCdSec = max(0f, fireCdSec - dt)
        if (comboTimerSec > 0f) {
            comboTimerSec -= dt
            if (comboTimerSec <= 0f) combo = 0
        }

        val ix = (if (inputRight) 1f else 0f) - (if (inputLeft) 1f else 0f)
        val iy = (if (inputDown) 1f else 0f) - (if (inputUp) 1f else 0f)
        if (ix != 0f || iy != 0f) {
            val norm = if (ix != 0f && iy != 0f) 0.70710678f else 1f
            reticleX = (reticleX + ix * norm * 420f * density * dt).coerceIn(20f * density, widthPx - 20f * density)
            reticleY = (reticleY + iy * norm * 420f * density * dt).coerceIn(56f * density, heightPx - 56f * density)
        }

        if (waveDelaySec > 0f) {
            waveDelaySec -= dt
            if (waveDelaySec <= 0f) startWave(wave)
        } else if (wavePending > 0) {
            spawnCdSec -= dt
            if (spawnCdSec <= 0f) {
                spawnWaveMeteor()
                wavePending -= 1
                spawnCdSec = max(0.28f, 0.92f - wave * 0.065f)
            }
        }

        // Move interceptors
        var i = interceptors.size - 1
        while (i >= 0) {
            val ic = interceptors[i]
            val dx = ic.tx - ic.x
            val dy = ic.ty - ic.y
            val remDist = sqrt(dx * dx + dy * dy)
            val stepDist = ic.speed * dt
            if (remDist <= stepDist + 2f * density) {
                addBlast(ic.tx, ic.ty)
                interceptors.removeAt(i)
            } else {
                ic.x += ic.vx * dt
                ic.y += ic.vy * dt
            }
            i -= 1
        }

        // Expand shockwave blast rings
        var bIdx = blasts.size - 1
        while (bIdx >= 0) {
            val b = blasts[bIdx]
            b.ageSec += dt
            if (b.ageSec >= b.lifeSec) {
                blasts.removeAt(bIdx)
            } else {
                val frac = min(1f, b.ageSec / 0.42f)
                val inv = 1f - frac
                b.r = 8f * density + (b.maxR - 8f * density) * (1f - inv * inv)
            }
            bIdx -= 1
        }

        // Move meteors, handle splitters, blast kills & pylon hits
        var mIdx = meteors.size - 1
        while (mIdx >= 0) {
            val m = meteors[mIdx]
            m.trailX.add(m.x)
            m.trailY.add(m.y)
            if (m.trailX.size > 8) {
                m.trailX.removeAt(0)
                m.trailY.removeAt(0)
            }
            m.x += m.vx * dt
            m.y += m.vy * dt

            if (m.isSplitter && !m.splitDone && m.y >= m.splitY) {
                m.splitDone = true
                m.isSplitter = false
                val childSpd = max(70f * density, sqrt(m.vx * m.vx + m.vy * m.vy))
                meteors.add(
                    IncomingMeteor(
                        x = m.x - 6f * density,
                        y = m.y,
                        vx = m.vx - childSpd * 0.28f,
                        vy = max(65f * density, m.vy * 0.96f),
                        radius = 7f * density,
                        isSplitter = false,
                        splitDone = true,
                        splitY = heightPx
                    )
                )
                meteors.add(
                    IncomingMeteor(
                        x = m.x + 6f * density,
                        y = m.y,
                        vx = m.vx + childSpd * 0.28f,
                        vy = max(65f * density, m.vy * 0.96f),
                        radius = 7f * density,
                        isSplitter = false,
                        splitDone = true,
                        splitY = heightPx
                    )
                )
                spawnParticles(m.x, m.y, 0xFFF59E0B.toInt())
                meteors.removeAt(mIdx)
                mIdx -= 1
                continue
            }

            var killedBy: ShockwaveBlast? = null
            for (b in blasts) {
                val dx = m.x - b.x
                val dy = m.y - b.y
                val hitR = b.r + m.radius
                if (dx * dx + dy * dy <= hitR * hitR) {
                    killedBy = b
                    break
                }
            }
            if (killedBy != null) {
                killedBy.kills += 1
                combo = min(4, max(combo + 1, killedBy.kills))
                comboTimerSec = 1.5f
                val mult = min(4, max(1, killedBy.kills))
                val basePts = if (m.isSplitter) 40 else 25
                val pts = basePts * mult
                awardScore(pts)
                spawnParticles(m.x, m.y, if (mult >= 2) 0xFFF59E0B.toInt() else 0xFF38BDF8.toInt())
                val label = if (mult > 1) "+$pts x$mult!" else "+$pts"
                popups.add(DefensePopup(m.x, m.y - 10f * density, label, if (mult > 1) 0xFFFBBF24.toInt() else 0xFF34D399.toInt()))
                meteors.removeAt(mIdx)
                mIdx -= 1
                continue
            }

            var hitPylon = false
            for (p in pylons) {
                if (!p.alive) continue
                val dx = m.x - p.x
                val dy = m.y - p.y
                val hitR = p.radius + m.radius
                if (dx * dx + dy * dy <= hitR * hitR) {
                    p.alive = false
                    hitPylon = true
                    spawnParticles(p.x, p.y, 0xFFEF4444.toInt())
                    popups.add(DefensePopup(p.x, p.y - 24f * density, "PYLON LOST!", 0xFFEF4444.toInt()))
                    break
                }
            }
            if (hitPylon || m.y >= heightPx - 24f * density || m.x < -30f * density || m.x > widthPx + 30f * density) {
                if (hitPylon) {
                    combo = 0
                    if (pylonsAlive == 0) {
                        phase = MissileDefensePhase.GAME_OVER
                        if (score > highScore) {
                            highScore = score
                            onNewHighScore(highScore)
                        }
                    }
                }
                meteors.removeAt(mIdx)
            }
            mIdx -= 1
        }

        // Wave completion check
        if (phase == MissileDefensePhase.PLAYING && wavePending <= 0 && meteors.isEmpty() && waveDelaySec <= 0f) {
            val alive = pylonsAlive
            val bonus = alive * 100
            if (bonus > 0) {
                awardScore(bonus)
                popups.add(DefensePopup(widthPx * 0.5f, heightPx * 0.35f, "WAVE $wave CLEAR +$bonus", 0xFF38BDF8.toInt()))
            }
            if (wave % 3 == 0 && alive < pylons.size) {
                for (p in pylons) {
                    if (!p.alive) {
                        p.alive = true
                        popups.add(DefensePopup(p.x, p.y - 24f * density, "PYLON RESTORED!", 0xFF10B981.toInt()))
                        break
                    }
                }
            }
            wave += 1
            waveDelaySec = 1.2f
        }

        // Particles & popups
        var pIdx = particles.size - 1
        while (pIdx >= 0) {
            val pt = particles[pIdx]
            pt.lifeSec -= dt
            pt.x += pt.vx * dt
            pt.y += pt.vy * dt
            if (pt.lifeSec <= 0f) particles.removeAt(pIdx)
            pIdx -= 1
        }
        var ppIdx = popups.size - 1
        while (ppIdx >= 0) {
            val pp = popups[ppIdx]
            pp.lifeSec -= dt
            pp.y -= 28f * density * dt
            if (pp.lifeSec <= 0f) popups.removeAt(ppIdx)
            ppIdx -= 1
        }
    }

    private fun spawnWaveMeteor() {
        val sx = (36f * density) + random.nextFloat() * max(40f, widthPx - 72f * density)
        val sy = 56f * density
        val aliveList = pylons.filter { it.alive }
        val targetX = if (aliveList.isNotEmpty()) {
            aliveList[random.nextInt(aliveList.size)].x
        } else {
            widthPx * 0.5f
        } + (random.nextFloat() - 0.5f) * 48f * density
        val targetY = heightPx - 38f * density

        val dx = targetX - sx
        val dy = max(60f * density, targetY - sy)
        val dist = max(1f, sqrt(dx * dx + dy * dy))
        val spd = (78f + wave * 14f + random.nextFloat() * 24f) * density
        val isSplit = wave >= 2 && random.nextInt(100) < min(40, 14 + wave * 4)

        meteors.add(
            IncomingMeteor(
                x = sx,
                y = sy,
                vx = (dx / dist) * spd,
                vy = (dy / dist) * spd,
                radius = (if (isSplit) 9f else 7f) * density,
                isSplitter = isSplit,
                splitDone = false,
                splitY = heightPx * (0.30f + random.nextFloat() * 0.18f)
            )
        )
    }

    private fun addBlast(x: Float, y: Float) {
        blasts.add(
            ShockwaveBlast(
                x = x,
                y = y,
                r = 8f * density,
                maxR = 64f * density
            )
        )
        spawnParticles(x, y, 0xFF38BDF8.toInt())
    }

    private fun spawnParticles(x: Float, y: Float, color: Int) {
        for (i in 0 until 8) {
            val ang = random.nextFloat() * 6.2831853f
            val spd = (40f + random.nextFloat() * 110f) * density
            particles.add(
                DefenseParticle(
                    x = x,
                    y = y,
                    vx = cos(ang) * spd,
                    vy = sin(ang) * spd,
                    lifeSec = 0.40f,
                    color = color
                )
            )
        }
    }

    private fun awardScore(pts: Int) {
        score += pts
        if (score > highScore) {
            highScore = score
            onNewHighScore(highScore)
        }
    }
}
