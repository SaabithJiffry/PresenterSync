package com.saabithjiffry.presentersync.remote.ui.arcade

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.random.Random

enum class AsteroidsPhase {
    IDLE,
    PLAYING,
    PAUSED,
    GAME_OVER
}

enum class BlasterMode {
    ASTEROIDS,
    ALIEN_BLASTER
}

enum class AlienShipKind {
    SCOUT,
    RAIDER,
    CRUISER
}

enum class AsteroidsPowerUpKind(val label: String) {
    RAPID("RAPID"),
    SPREAD("SPREAD"),
    SHIELD("SHIELD"),
    WEAPON_UP("WPN+")
}

data class AlienShip(
    val id: Int,
    var x: Float,
    var y: Float,
    var baseX: Float,
    var vx: Float,
    var vy: Float,
    val kind: AlienShipKind,
    var hp: Int,
    val maxHp: Int,
    val radius: Float,
    val phaseRad: Float,
    val swayAmp: Float,
    val swayFreq: Float,
    var fireTimerSec: Float
)

data class ArcadeRectF(
    val left: Float,
    val top: Float,
    val right: Float,
    val bottom: Float
)

data class AsteroidRock(
    val id: Int,
    var x: Float,
    var y: Float,
    var vx: Float,
    var vy: Float,
    val size: Int, // 3 = Large, 2 = Medium, 1 = Small
    val radius: Float,
    var angleRad: Float,
    val spinRadPerSec: Float,
    val vertexOffsets: FloatArray
)

data class BlasterBolt(
    var x: Float,
    var y: Float,
    var vx: Float,
    var vy: Float,
    var ttlSec: Float,
    val fromSaucer: Boolean
)

data class UfoSaucer(
    var x: Float,
    var y: Float,
    var vx: Float,
    var vy: Float,
    val radius: Float,
    var fireTimerSec: Float
)

data class AsteroidsPowerUp(
    val kind: AsteroidsPowerUpKind,
    var x: Float,
    var y: Float,
    var vx: Float,
    var vy: Float,
    var ttlSec: Float
)

data class AsteroidsParticle(
    var x: Float,
    var y: Float,
    var vx: Float,
    var vy: Float,
    var lifeSec: Float,
    val maxLifeSec: Float,
    val colorRgb: Int
)

data class AsteroidsScorePopup(
    var x: Float,
    var y: Float,
    val text: String,
    var lifeSec: Float,
    val maxLifeSec: Float,
    val colorRgb: Int
)

class AsteroidsEngine(
    private val random: Random = Random.Default,
    private val onNewHighScore: (Int) -> Unit = {}
) {
    var phase: AsteroidsPhase = AsteroidsPhase.IDLE
        private set
    var mode: BlasterMode = BlasterMode.ASTEROIDS
    var weaponTier: Int = 1
    var beamActive: Boolean = false
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

    // Ship state
    var shipX: Float = 540f
    var shipY: Float = 960f
    var shipVx: Float = 0f
    var shipVy: Float = 0f
    var shipAngleRad: Float = (-PI / 2.0).toFloat()
    var shipRadius: Float = 22f
    var invulnTimerSec: Float = 0f
    var shieldTimerSec: Float = 0f
    var rapidTimerSec: Float = 0f
    var spreadTimerSec: Float = 0f
    var fireCooldownSec: Float = 0f

    // Continuous input state
    var inputTurnLeft: Boolean = false
    var inputTurnRight: Boolean = false
    var inputThrust: Boolean = false
    var inputMoveDown: Boolean = false
    var inputFiring: Boolean = false
    var touchAimActive: Boolean = false
    var touchTargetX: Float = 0f
    var touchTargetY: Float = 0f
    var autoFireEnabled: Boolean = false

    val rocks: MutableList<AsteroidRock> = mutableListOf()
    val aliens: MutableList<AlienShip> = mutableListOf()
    val bolts: MutableList<BlasterBolt> = mutableListOf()
    var saucer: UfoSaucer? = null
    val powerUps: MutableList<AsteroidsPowerUp> = mutableListOf()
    val particles: MutableList<AsteroidsParticle> = mutableListOf()
    val popups: MutableList<AsteroidsScorePopup> = mutableListOf()

    private var nextRockId = 1
    private var nextAlienId = 1
    private var saucerSpawnTimerSec = 14f
    private var waveTransitionTimerSec = 0f
    private var beamHoldSec = 0f
    private var beamDmgCooldownSec = 0f
    private var alienTimeSec = 0f

    fun startNewSession(
        widthPx: Int,
        heightPx: Int,
        screenDensity: Float,
        initialHighScore: Int = 0,
        bumperRect: ArcadeRectF? = null,
        clearInitialRocks: Boolean = false
    ) {
        worldWidth = max(320f, widthPx.toFloat())
        worldHeight = max(320f, heightPx.toFloat())
        density = screenDensity.coerceIn(0.75f, 5f)
        pillBumper = bumperRect
        highScore = max(highScore, initialHighScore)

        score = 0
        wave = 1
        lives = 3
        weaponTier = 1
        beamActive = false
        beamHoldSec = 0f
        beamDmgCooldownSec = 0f
        alienTimeSec = 0f
        rocks.clear()
        aliens.clear()
        bolts.clear()
        saucer = null
        powerUps.clear()
        particles.clear()
        popups.clear()
        inputTurnLeft = false
        inputTurnRight = false
        inputThrust = false
        inputMoveDown = false
        inputFiring = false
        touchAimActive = false
        saucerSpawnTimerSec = 14f
        waveTransitionTimerSec = 0f

        resetShipCenter()
        phase = AsteroidsPhase.PLAYING
        if (!clearInitialRocks) {
            if (mode == BlasterMode.ALIEN_BLASTER) {
                spawnAlienWave(wave)
            } else {
                spawnWave(wave)
            }
        }
    }

    fun toggleMode(): BlasterMode {
        mode = if (mode == BlasterMode.ASTEROIDS) BlasterMode.ALIEN_BLASTER else BlasterMode.ASTEROIDS
        if (phase != AsteroidsPhase.IDLE) {
            startNewSession(
                widthPx = worldWidth.toInt(),
                heightPx = worldHeight.toInt(),
                screenDensity = density,
                initialHighScore = highScore,
                bumperRect = pillBumper
            )
        }
        return mode
    }

    fun upgradeWeaponTier(): Int {
        weaponTier = min(5, weaponTier + 1)
        return weaponTier
    }

    fun spawnAlien(
        x: Float,
        y: Float,
        kind: AlienShipKind = AlienShipKind.SCOUT,
        hp: Int = when (kind) {
            AlienShipKind.CRUISER -> 3
            AlienShipKind.RAIDER -> 1
            AlienShipKind.SCOUT -> 1
        },
        vy: Float = 45f * density
    ): AlienShip {
        val r = when (kind) {
            AlienShipKind.CRUISER -> 22f * density
            AlienShipKind.RAIDER -> 16f * density
            AlienShipKind.SCOUT -> 14f * density
        }
        val alien = AlienShip(
            id = nextAlienId++,
            x = x,
            y = y,
            baseX = x,
            vx = 0f,
            vy = vy,
            kind = kind,
            hp = max(1, hp),
            maxHp = max(1, hp),
            radius = r,
            phaseRad = 0f,
            swayAmp = if (kind == AlienShipKind.RAIDER) 48f * density else 0f,
            swayFreq = if (kind == AlienShipKind.RAIDER) 2.3f else 0f,
            fireTimerSec = 1.4f
        )
        aliens.add(alien)
        return alien
    }

    fun updateDisplayMetrics(widthPx: Int, heightPx: Int, screenDensity: Float, bumperRect: ArcadeRectF? = null) {
        val newW = max(320f, widthPx.toFloat())
        val newH = max(320f, heightPx.toFloat())
        if (worldWidth > 0f && worldHeight > 0f) {
            val sx = newW / worldWidth
            val sy = newH / worldHeight
            shipX *= sx
            shipY *= sy
            for (r in rocks) {
                r.x *= sx
                r.y *= sy
            }
            for (a in aliens) {
                a.x *= sx
                a.y *= sy
                a.baseX *= sx
            }
            for (p in powerUps) {
                p.x *= sx
                p.y *= sy
            }
            for (b in bolts) {
                b.x *= sx
                b.y *= sy
            }
            saucer?.let {
                it.x *= sx
                it.y *= sy
            }
        }
        worldWidth = newW
        worldHeight = newH
        density = screenDensity.coerceIn(0.75f, 5f)
        shipRadius = 12f * density
        if (bumperRect != null) {
            pillBumper = bumperRect
        }
    }

    fun togglePause() {
        phase = when (phase) {
            AsteroidsPhase.PLAYING -> AsteroidsPhase.PAUSED
            AsteroidsPhase.PAUSED -> AsteroidsPhase.PLAYING
            else -> phase
        }
    }

    fun stop() {
        phase = AsteroidsPhase.IDLE
        beamActive = false
        rocks.clear()
        aliens.clear()
        bolts.clear()
        saucer = null
        powerUps.clear()
        particles.clear()
        popups.clear()
    }

    fun spawnRock(x: Float, y: Float, vx: Float, vy: Float, size: Int): AsteroidRock {
        val baseRadius = when (size) {
            3 -> 34f * density
            2 -> 21f * density
            else -> 12f * density
        }
        val verts = FloatArray(10) { 0.78f + random.nextFloat() * 0.40f }
        val rock = AsteroidRock(
            id = nextRockId++,
            x = x,
            y = y,
            vx = vx,
            vy = vy,
            size = size.coerceIn(1, 3),
            radius = baseRadius,
            angleRad = random.nextFloat() * (2f * PI.toFloat()),
            spinRadPerSec = (random.nextFloat() - 0.5f) * 2.2f,
            vertexOffsets = verts
        )
        rocks.add(rock)
        return rock
    }

    fun spawnSaucer(fromLeft: Boolean = random.nextBoolean()): UfoSaucer {
        val r = 18f * density
        val y = (0.18f + random.nextFloat() * 0.64f) * worldHeight
        val speed = 95f * density
        val ufo = UfoSaucer(
            x = if (fromLeft) r else worldWidth - r,
            y = y,
            vx = if (fromLeft) speed else -speed,
            vy = (random.nextFloat() - 0.5f) * 35f * density,
            radius = r,
            fireTimerSec = 1.4f
        )
        saucer = ufo
        return ufo
    }

    fun spawnPowerUp(kind: AsteroidsPowerUpKind, x: Float, y: Float): AsteroidsPowerUp {
        val pu = AsteroidsPowerUp(
            kind = kind,
            x = x,
            y = y,
            vx = (random.nextFloat() - 0.5f) * 24f * density,
            vy = (random.nextFloat() - 0.5f) * 24f * density,
            ttlSec = 10f
        )
        powerUps.add(pu)
        return pu
    }

    fun firePlayerBolt(ignoreCooldown: Boolean = false): Boolean {
        if (phase != AsteroidsPhase.PLAYING) return false
        if (mode == BlasterMode.ALIEN_BLASTER) {
            if (weaponTier >= 5) {
                beamActive = true
                beamHoldSec = 0.36f
                return true
            }
            if (!ignoreCooldown && fireCooldownSec > 0f) return false
            val spd = 540f * density
            when (weaponTier) {
                1 -> {
                    fireCooldownSec = 0.21f
                    bolts.add(BlasterBolt(shipX, shipY - shipRadius - 4f * density, 0f, -spd, 1.2f, false))
                }
                2 -> {
                    fireCooldownSec = 0.19f
                    val offX = 9f * density
                    bolts.add(BlasterBolt(shipX - offX, shipY - shipRadius - 2f * density, 0f, -spd, 1.2f, false))
                    bolts.add(BlasterBolt(shipX + offX, shipY - shipRadius - 2f * density, 0f, -spd, 1.2f, false))
                }
                3 -> {
                    fireCooldownSec = 0.175f
                    for (dAng in floatArrayOf(-0.18f, 0f, 0.18f)) {
                        val a = (-PI / 2.0).toFloat() + dAng
                        bolts.add(BlasterBolt(shipX + cos(a) * (shipRadius + 4f * density), shipY + sin(a) * (shipRadius + 4f * density), cos(a) * spd, sin(a) * spd, 1.2f, false))
                    }
                }
                else -> {
                    fireCooldownSec = 0.125f
                    for (dAng in floatArrayOf(-0.28f, -0.14f, 0f, 0.14f, 0.28f)) {
                        val a = (-PI / 2.0).toFloat() + dAng
                        bolts.add(BlasterBolt(shipX + cos(a) * (shipRadius + 4f * density), shipY + sin(a) * (shipRadius + 4f * density), cos(a) * (spd * 1.06f), sin(a) * (spd * 1.06f), 1.2f, false))
                    }
                }
            }
            return true
        }
        if (!ignoreCooldown && fireCooldownSec > 0f) return false

        val cooldown = if (rapidTimerSec > 0f) 0.11f else 0.22f
        fireCooldownSec = cooldown
        val speed = 460f * density
        val offsets = if (spreadTimerSec > 0f) floatArrayOf(-0.18f, 0f, 0.18f) else floatArrayOf(0f)
        for (deltaAng in offsets) {
            val ang = shipAngleRad + deltaAng
            val ux = cos(ang)
            val uy = sin(ang)
            bolts.add(
                BlasterBolt(
                    x = shipX + ux * (shipRadius + 4f * density),
                    y = shipY + uy * (shipRadius + 4f * density),
                    vx = shipVx * 0.25f + ux * speed,
                    vy = shipVy * 0.25f + uy * speed,
                    ttlSec = 1.15f,
                    fromSaucer = false
                )
            )
        }
        return true
    }

    fun step(dtSecRaw: Float) {
        if (phase != AsteroidsPhase.PLAYING) return
        val dt = dtSecRaw.coerceIn(0.001f, 0.05f)

        // Timers
        invulnTimerSec = max(0f, invulnTimerSec - dt)
        shieldTimerSec = max(0f, shieldTimerSec - dt)
        rapidTimerSec = max(0f, rapidTimerSec - dt)
        spreadTimerSec = max(0f, spreadTimerSec - dt)
        fireCooldownSec = max(0f, fireCooldownSec - dt)

        if (mode == BlasterMode.ALIEN_BLASTER) {
            stepAlienBlaster(dt)
            return
        }

        // Ship steering & thrust
        val turnRate = 3.8f
        if (inputTurnLeft) shipAngleRad -= turnRate * dt
        if (inputTurnRight) shipAngleRad += turnRate * dt

        if (touchAimActive) {
            val dx = touchTargetX - shipX
            val dy = touchTargetY - shipY
            val dist = hypot(dx, dy)
            if (dist > 14f * density) {
                shipAngleRad = atan2(dy, dx)
                val thrust = 260f * density
                shipVx += cos(shipAngleRad) * thrust * dt
                shipVy += sin(shipAngleRad) * thrust * dt
            }
        } else if (inputThrust) {
            val thrust = 275f * density
            shipVx += cos(shipAngleRad) * thrust * dt
            shipVy += sin(shipAngleRad) * thrust * dt
        }

        // Damping & max speed clamp
        val drag = max(0.85f, 1f - 0.55f * dt)
        shipVx *= drag
        shipVy *= drag
        val maxSpd = 320f * density
        val spd = hypot(shipVx, shipVy)
        if (spd > maxSpd) {
            val k = maxSpd / spd
            shipVx *= k
            shipVy *= k
        }

        shipX = wrapX(shipX + shipVx * dt)
        shipY = wrapY(shipY + shipVy * dt)
        deflectFromBumper(isShip = true, radius = shipRadius)

        if (inputFiring || autoFireEnabled || touchAimActive) {
            firePlayerBolt()
        }

        // Advance bolts
        val boltIter = bolts.iterator()
        while (boltIter.hasNext()) {
            val b = boltIter.next()
            b.x += b.vx * dt
            b.y += b.vy * dt
            b.ttlSec -= dt
            if (b.ttlSec <= 0f || b.x < -30f || b.x > worldWidth + 30f || b.y < -30f || b.y > worldHeight + 30f) {
                boltIter.remove()
            }
        }

        // Advance rocks + Bumper deflection
        for (r in rocks) {
            r.x = wrapX(r.x + r.vx * dt)
            r.y = wrapY(r.y + r.vy * dt)
            r.angleRad += r.spinRadPerSec * dt
            deflectRockFromBumper(r)
        }

        // Advance UFO saucer
        val currentSaucer = saucer
        if (currentSaucer != null) {
            currentSaucer.x += currentSaucer.vx * dt
            currentSaucer.y = wrapY(currentSaucer.y + currentSaucer.vy * dt)
            currentSaucer.fireTimerSec -= dt
            if (currentSaucer.fireTimerSec <= 0f) {
                currentSaucer.fireTimerSec = 1.6f
                val aim = atan2(shipY - currentSaucer.y, shipX - currentSaucer.x) + (random.nextFloat() - 0.5f) * 0.25f
                val bSpd = 260f * density
                bolts.add(
                    BlasterBolt(
                        x = currentSaucer.x,
                        y = currentSaucer.y,
                        vx = cos(aim) * bSpd,
                        vy = sin(aim) * bSpd,
                        ttlSec = 1.8f,
                        fromSaucer = true
                    )
                )
            }
            if (currentSaucer.x < -currentSaucer.radius * 2 || currentSaucer.x > worldWidth + currentSaucer.radius * 2) {
                saucer = null
            }
        } else if (rocks.isNotEmpty()) {
            saucerSpawnTimerSec -= dt
            if (saucerSpawnTimerSec <= 0f) {
                saucerSpawnTimerSec = max(10f, 18f - wave * 1.2f)
                spawnSaucer()
            }
        }

        // Advance power-ups & check pickup
        val puIter = powerUps.iterator()
        while (puIter.hasNext()) {
            val pu = puIter.next()
            pu.x = wrapX(pu.x + pu.vx * dt)
            pu.y = wrapY(pu.y + pu.vy * dt)
            pu.ttlSec -= dt
            if (hypot(pu.x - shipX, pu.y - shipY) <= shipRadius + 16f * density) {
                applyPowerUp(pu)
                puIter.remove()
            } else if (pu.ttlSec <= 0f) {
                puIter.remove()
            }
        }

        // Collision: Player bolts vs Rocks & Saucer
        val hitRocks = mutableListOf<AsteroidRock>()
        val usedBolts = mutableSetOf<BlasterBolt>()
        for (b in bolts) {
            if (b.fromSaucer) {
                if (invulnTimerSec <= 0f && shieldTimerSec <= 0f && hypot(b.x - shipX, b.y - shipY) <= shipRadius + 3f * density) {
                    usedBolts.add(b)
                    damageShip()
                }
                continue
            }
            val ufo = saucer
            if (ufo != null && hypot(b.x - ufo.x, b.y - ufo.y) <= ufo.radius + 4f * density) {
                usedBolts.add(b)
                awardScore(250, ufo.x, ufo.y, 0xFFF59E0B.toInt())
                spawnBurst(ufo.x, ufo.y, 16, 0xFFF59E0B.toInt())
                dropPowerUp(ufo.x, ufo.y, guaranteed = true)
                saucer = null
                continue
            }
            for (r in rocks) {
                if (!hitRocks.contains(r) && hypot(b.x - r.x, b.y - r.y) <= r.radius + 3f * density) {
                    hitRocks.add(r)
                    usedBolts.add(b)
                    break
                }
            }
        }
        bolts.removeAll(usedBolts)
        for (destroyed in hitRocks) {
            destroyRock(destroyed)
        }

        // Collision: Ship vs Rocks / Saucer
        if (invulnTimerSec <= 0f && phase == AsteroidsPhase.PLAYING) {
            val ufo = saucer
            if (ufo != null && hypot(shipX - ufo.x, shipY - ufo.y) <= shipRadius + ufo.radius * 0.85f) {
                if (shieldTimerSec > 0f) {
                    shieldTimerSec = 0f
                    awardScore(250, ufo.x, ufo.y, 0xFFF59E0B.toInt())
                    spawnBurst(ufo.x, ufo.y, 14, 0xFFF59E0B.toInt())
                    saucer = null
                } else {
                    damageShip()
                }
            } else {
                val collidingRock = rocks.firstOrNull { r ->
                    hypot(shipX - r.x, shipY - r.y) <= shipRadius + r.radius * 0.82f
                }
                if (collidingRock != null) {
                    if (shieldTimerSec > 0f) {
                        shieldTimerSec = 0f
                        invulnTimerSec = 1.0f
                        destroyRock(collidingRock)
                    } else {
                        damageShip()
                    }
                }
            }
        }

        // Wave progression when cleared
        if (rocks.isEmpty() && saucer == null && phase == AsteroidsPhase.PLAYING) {
            if (waveTransitionTimerSec <= 0f) {
                waveTransitionTimerSec = 1.25f
            } else {
                waveTransitionTimerSec -= dt
                if (waveTransitionTimerSec <= 0f) {
                    wave += 1
                    spawnWave(wave)
                }
            }
        }

        // Decay visuals
        decayVisuals(dt)
    }

    private fun decayVisuals(dt: Float) {
        val partIter = particles.iterator()
        while (partIter.hasNext()) {
            val p = partIter.next()
            p.x += p.vx * dt
            p.y += p.vy * dt
            p.lifeSec -= dt
            if (p.lifeSec <= 0f) partIter.remove()
        }
        val popIter = popups.iterator()
        while (popIter.hasNext()) {
            val pp = popIter.next()
            pp.y -= 26f * density * dt
            pp.lifeSec -= dt
            if (pp.lifeSec <= 0f) popIter.remove()
        }
    }

    private fun stepAlienBlaster(dt: Float) {
        alienTimeSec += dt
        shipAngleRad = (-PI / 2.0).toFloat() // Fixed forward-facing ship (NEVER rotates)
        beamHoldSec = max(0f, beamHoldSec - dt)
        beamDmgCooldownSec = max(0f, beamDmgCooldownSec - dt)

        val moveSpd = 320f * density
        if (touchAimActive) {
            val dx = touchTargetX - shipX
            val dy = touchTargetY - shipY
            shipVx = (dx * 9f).coerceIn(-460f * density, 460f * density)
            shipVy = (dy * 9f).coerceIn(-460f * density, 460f * density)
        } else {
            var ix = (if (inputTurnRight) 1f else 0f) - (if (inputTurnLeft) 1f else 0f)
            var iy = (if (inputMoveDown) 1f else 0f) - (if (inputThrust) 1f else 0f)
            if (ix != 0f && iy != 0f) {
                ix *= 0.70710678f
                iy *= 0.70710678f
            }
            shipVx = ix * moveSpd
            shipVy = iy * moveSpd
        }

        val padX = 24f * density
        val minY = 76f * density
        val maxY = max(minY + 40f, worldHeight - 24f * density)
        shipX = (shipX + shipVx * dt).coerceIn(padX, max(padX, worldWidth - padX))
        shipY = (shipY + shipVy * dt).coerceIn(minY, maxY)
        shipAngleRad = (-PI / 2.0).toFloat()

        val wantsFire = inputFiring || autoFireEnabled || touchAimActive
        if (weaponTier >= 5) {
            beamActive = wantsFire || beamHoldSec > 0f
            if (beamActive && beamDmgCooldownSec <= 0f) {
                beamDmgCooldownSec = 0.08f
                val beamHit = aliens.filter { al ->
                    al.y < shipY && abs(al.x - shipX) <= al.radius + 15f * density
                }
                for (al in beamHit) {
                    damageAlien(al, 1)
                }
            }
        } else {
            beamActive = false
            if (wantsFire) {
                firePlayerBolt()
            }
        }

        // Advance bolts (non-wrapping)
        val boltIter = bolts.iterator()
        while (boltIter.hasNext()) {
            val b = boltIter.next()
            b.x += b.vx * dt
            b.y += b.vy * dt
            b.ttlSec -= dt
            if (b.ttlSec <= 0f || b.x < -30f || b.x > worldWidth + 30f || b.y < 30f || b.y > worldHeight + 30f) {
                boltIter.remove()
            }
        }

        // Advance oncoming alien ships & downward plasma fire
        val hitAliens = mutableListOf<AlienShip>()
        val usedBolts = mutableSetOf<BlasterBolt>()
        for (al in aliens) {
            al.y += al.vy * dt
            if (al.swayAmp > 0f && al.swayFreq > 0f) {
                al.x = (al.baseX + sin(alienTimeSec * al.swayFreq + al.phaseRad) * al.swayAmp)
                    .coerceIn(padX, max(padX, worldWidth - padX))
            }
            if (al.y > worldHeight + 30f * density) {
                al.y = 58f * density
            }
            al.fireTimerSec -= dt
            if (al.fireTimerSec <= 0f && al.y > 70f * density && al.y < worldHeight - 80f * density) {
                al.fireTimerSec = max(0.85f, (if (al.kind == AlienShipKind.CRUISER) 1.3f else 1.8f) - wave * 0.07f)
                val bSpd = (230f + wave * 12f) * density
                bolts.add(BlasterBolt(al.x, al.y + al.radius, 0f, bSpd, 2.5f, fromSaucer = true))
            }
        }

        // Collisions: bolts vs aliens & enemy bolts vs ship
        for (b in bolts) {
            if (b.fromSaucer) {
                if (invulnTimerSec <= 0f && hypot(b.x - shipX, b.y - shipY) <= shipRadius + 4f * density) {
                    usedBolts.add(b)
                    if (shieldTimerSec > 0f) {
                        shieldTimerSec = 0f
                        invulnTimerSec = 1.2f
                        popups.add(AsteroidsScorePopup(shipX, shipY - 16f * density, "SHIELD", 0.85f, 0.85f, 0xFF38BDF8.toInt()))
                    } else {
                        damageShip()
                    }
                }
                continue
            }
            for (al in aliens) {
                if (!hitAliens.contains(al) && hypot(b.x - al.x, b.y - al.y) <= al.radius + 5f * density) {
                    hitAliens.add(al)
                    usedBolts.add(b)
                    break
                }
            }
        }
        bolts.removeAll(usedBolts)
        for (al in hitAliens) {
            damageAlien(al, 1)
        }

        // Collisions: ship vs aliens
        if (invulnTimerSec <= 0f && phase == AsteroidsPhase.PLAYING) {
            val hitAl = aliens.firstOrNull { al ->
                hypot(shipX - al.x, shipY - al.y) <= shipRadius + al.radius * 0.85f
            }
            if (hitAl != null) {
                if (shieldTimerSec > 0f) {
                    shieldTimerSec = 0f
                    invulnTimerSec = 1.2f
                    damageAlien(hitAl, hitAl.hp)
                } else {
                    damageShip()
                }
            }
        }

        // Power-ups fall downward & pickup
        val puIter = powerUps.iterator()
        while (puIter.hasNext()) {
            val pu = puIter.next()
            pu.x = (pu.x + pu.vx * dt).coerceIn(padX, max(padX, worldWidth - padX))
            pu.y += pu.vy * dt
            pu.ttlSec -= dt
            if (hypot(pu.x - shipX, pu.y - shipY) <= shipRadius + 18f * density) {
                applyPowerUp(pu)
                puIter.remove()
            } else if (pu.ttlSec <= 0f || pu.y > worldHeight + 30f * density) {
                puIter.remove()
            }
        }

        // Advance wave when all aliens cleared
        if (aliens.isEmpty() && phase == AsteroidsPhase.PLAYING) {
            if (waveTransitionTimerSec <= 0f) {
                waveTransitionTimerSec = 0.9f
            } else {
                waveTransitionTimerSec -= dt
                if (waveTransitionTimerSec <= 0f) {
                    wave += 1
                    spawnAlienWave(wave)
                }
            }
        }

        decayVisuals(dt)
    }

    private fun damageAlien(al: AlienShip, dmg: Int) {
        if (!aliens.contains(al)) return
        al.hp -= dmg
        if (al.hp > 0) {
            spawnBurst(al.x, al.y, 4, 0xFFF59E0B.toInt())
            return
        }
        aliens.remove(al)
        val pts = when (al.kind) {
            AlienShipKind.CRUISER -> 180
            AlienShipKind.RAIDER -> 90
            AlienShipKind.SCOUT -> 50
        }
        val col = when (al.kind) {
            AlienShipKind.CRUISER -> 0xFFF59E0B.toInt()
            AlienShipKind.RAIDER -> 0xFFE879F9.toInt()
            AlienShipKind.SCOUT -> 0xFF38BDF8.toInt()
        }
        awardScore(pts, al.x, al.y, col)
        spawnBurst(al.x, al.y, if (al.kind == AlienShipKind.CRUISER) 14 else 8, col)
        val dropChance = when (al.kind) {
            AlienShipKind.CRUISER -> 0.85f
            AlienShipKind.RAIDER -> 0.35f
            AlienShipKind.SCOUT -> 0.22f
        }
        if (random.nextFloat() < dropChance) {
            val k = if (random.nextFloat() < 0.75f) AsteroidsPowerUpKind.WEAPON_UP else AsteroidsPowerUpKind.SHIELD
            powerUps.add(AsteroidsPowerUp(k, al.x, al.y, 0f, 68f * density, 10f))
        }
    }

    private fun spawnAlienWave(waveNum: Int) {
        aliens.clear()
        val padX = 48f * density
        val cx = worldWidth / 2f
        // 1. V-wedge scouts
        val scoutCount = min(7, 3 + waveNum)
        val half = (scoutCount - 1) / 2f
        for (i in 0 until scoutCount) {
            val off = i - half
            val ax = (cx + off * 46f * density).coerceIn(padX, max(padX, worldWidth - padX))
            val ay = (84f + abs(off) * 24f) * density
            aliens.add(
                AlienShip(
                    id = nextAlienId++,
                    x = ax, y = ay, baseX = ax, vx = 0f, vy = (40f + waveNum * 5f) * density,
                    kind = AlienShipKind.SCOUT, hp = 1, maxHp = 1, radius = 14f * density,
                    phaseRad = i * 0.6f, swayAmp = 12f * density, swayFreq = 1.4f,
                    fireTimerSec = 1.1f + random.nextFloat() * 0.9f
                )
            )
        }
        // 2. Sine-wave raiders
        val raiderCount = min(5, 1 + waveNum)
        for (i in 1..raiderCount) {
            val ax = ((worldWidth / (raiderCount + 1)) * i).coerceIn(padX, max(padX, worldWidth - padX))
            val ay = (56f - i * 16f) * density
            val rHp = if (waveNum >= 3) 2 else 1
            aliens.add(
                AlienShip(
                    id = nextAlienId++,
                    x = ax, y = ay, baseX = ax, vx = 0f, vy = (48f + waveNum * 5f) * density,
                    kind = AlienShipKind.RAIDER, hp = rHp, maxHp = rHp, radius = 16f * density,
                    phaseRad = i * 1.3f, swayAmp = 48f * density, swayFreq = 2.3f,
                    fireTimerSec = 0.95f + random.nextFloat() * 0.8f
                )
            )
        }
        // 3. Armored cruisers
        val cruiserCount = min(3, 1 + (waveNum - 1) / 2)
        for (i in 1..cruiserCount) {
            val ax = ((worldWidth / (cruiserCount + 1)) * i).coerceIn(padX, max(padX, worldWidth - padX))
            val ay = 42f * density
            val cHp = 3 + (waveNum - 1) / 2
            aliens.add(
                AlienShip(
                    id = nextAlienId++,
                    x = ax, y = ay, baseX = ax, vx = 0f, vy = (26f + waveNum * 3f) * density,
                    kind = AlienShipKind.CRUISER, hp = cHp, maxHp = cHp, radius = 22f * density,
                    phaseRad = i * 0.9f, swayAmp = 22f * density, swayFreq = 1.0f,
                    fireTimerSec = 1.3f + random.nextFloat() * 0.7f
                )
            )
        }
    }

    private fun destroyRock(rock: AsteroidRock) {
        rocks.remove(rock)
        val pts = when (rock.size) {
            3 -> 20
            2 -> 50
            else -> 100
        }
        awardScore(pts, rock.x, rock.y, 0xFF60CDFF.toInt())
        spawnBurst(rock.x, rock.y, 9, 0xFF93C5FD.toInt())

        if (rock.size > 1) {
            val nextSize = rock.size - 1
            repeat(2) {
                val ang = random.nextFloat() * (2f * PI.toFloat())
                val spd = (70f + wave * 8f + random.nextFloat() * 45f) * density
                spawnRock(
                    x = rock.x,
                    y = rock.y,
                    vx = cos(ang) * spd,
                    vy = sin(ang) * spd,
                    size = nextSize
                )
            }
        } else if (random.nextFloat() < 0.16f) {
            dropPowerUp(rock.x, rock.y, guaranteed = false)
        }
    }

    private fun dropPowerUp(x: Float, y: Float, guaranteed: Boolean) {
        if (!guaranteed && random.nextFloat() > 0.35f) return
        val values = arrayOf(AsteroidsPowerUpKind.RAPID, AsteroidsPowerUpKind.SPREAD, AsteroidsPowerUpKind.SHIELD)
        spawnPowerUp(values[random.nextInt(values.size)], x, y)
    }

    private fun applyPowerUp(pu: AsteroidsPowerUp) {
        val label = when (pu.kind) {
            AsteroidsPowerUpKind.RAPID -> {
                rapidTimerSec = 9f
                pu.kind.label
            }
            AsteroidsPowerUpKind.SPREAD -> {
                spreadTimerSec = 9f
                pu.kind.label
            }
            AsteroidsPowerUpKind.SHIELD -> {
                shieldTimerSec = 10f
                pu.kind.label
            }
            AsteroidsPowerUpKind.WEAPON_UP -> {
                if (weaponTier < 5) {
                    weaponTier += 1
                    if (weaponTier == 5) "BEAM LASER!" else "WPN T$weaponTier"
                } else {
                    awardScore(150, pu.x, pu.y, 0xFF38BDF8.toInt())
                    "MAX WPN +150"
                }
            }
        }
        popups.add(
            AsteroidsScorePopup(
                x = pu.x,
                y = pu.y,
                text = label,
                lifeSec = 1.0f,
                maxLifeSec = 1.0f,
                colorRgb = 0xFF34D399.toInt()
            )
        )
    }

    private fun awardScore(pts: Int, x: Float, y: Float, colorRgb: Int) {
        score += pts
        if (score > highScore) {
            highScore = score
            onNewHighScore(highScore)
        }
        popups.add(
            AsteroidsScorePopup(
                x = x,
                y = y,
                text = "+$pts",
                lifeSec = 0.85f,
                maxLifeSec = 0.85f,
                colorRgb = colorRgb
            )
        )
    }

    private fun damageShip() {
        spawnBurst(shipX, shipY, 18, 0xFFEF4444.toInt())
        lives -= 1
        if (lives <= 0) {
            lives = 0
            phase = AsteroidsPhase.GAME_OVER
            touchAimActive = false
        } else {
            resetShipCenter()
        }
    }

    private fun resetShipCenter() {
        shipX = worldWidth / 2f
        shipY = if (mode == BlasterMode.ALIEN_BLASTER) worldHeight * 0.80f else worldHeight / 2f
        shipVx = 0f
        shipVy = 0f
        shipAngleRad = (-PI / 2.0).toFloat()
        shipRadius = 12f * density
        invulnTimerSec = 2.2f
    }

    private fun spawnWave(waveNum: Int) {
        val count = min(9, 3 + waveNum)
        val minDist = 115f * density
        for (i in 0 until count) {
            var rx: Float
            var ry: Float
            var attempts = 0
            do {
                rx = random.nextFloat() * worldWidth
                ry = (60f * density) + random.nextFloat() * max(120f, worldHeight - 90f * density)
                attempts++
            } while (attempts < 12 && hypot(rx - shipX, ry - shipY) < minDist)

            val ang = random.nextFloat() * (2f * PI.toFloat())
            val spd = (48f + waveNum * 7f + random.nextFloat() * 34f) * density
            spawnRock(rx, ry, cos(ang) * spd, sin(ang) * spd, size = 3)
        }
    }

    private fun deflectFromBumper(isShip: Boolean, radius: Float) {
        val rect = pillBumper ?: return
        val closestX = shipX.coerceIn(rect.left, rect.right)
        val closestY = shipY.coerceIn(rect.top, rect.bottom)
        val dx = shipX - closestX
        val dy = shipY - closestY
        val dist = hypot(dx, dy)
        if (dist >= radius) return

        val nx = if (dist > 0.001f) dx / dist else 0f
        val ny = if (dist > 0.001f) dy / dist else -1f
        val overlap = radius - dist + 2f * density
        if (isShip) {
            shipX += nx * overlap
            shipY += ny * overlap
            val dot = shipVx * nx + shipVy * ny
            if (dot < 0f) {
                shipVx -= 1.8f * dot * nx
                shipVy -= 1.8f * dot * ny
            }
        }
    }

    private fun deflectRockFromBumper(r: AsteroidRock) {
        val rect = pillBumper ?: return
        val closestX = r.x.coerceIn(rect.left, rect.right)
        val closestY = r.y.coerceIn(rect.top, rect.bottom)
        val dx = r.x - closestX
        val dy = r.y - closestY
        val dist = hypot(dx, dy)
        if (dist >= r.radius) return

        val nx = if (dist > 0.001f) dx / dist else 0f
        val ny = if (dist > 0.001f) dy / dist else -1f
        val overlap = r.radius - dist + 2f * density
        r.x += nx * overlap
        r.y += ny * overlap
        val dot = r.vx * nx + r.vy * ny
        if (dot < 0f) {
            r.vx -= 2f * dot * nx
            r.vy -= 2f * dot * ny
            spawnBurst(closestX, closestY, 4, 0xFF34D399.toInt())
        }
    }

    private fun spawnBurst(x: Float, y: Float, count: Int, colorRgb: Int) {
        for (i in 0 until count) {
            val ang = random.nextFloat() * (2f * PI.toFloat())
            val spd = (40f + random.nextFloat() * 110f) * density
            val life = 0.25f + random.nextFloat() * 0.35f
            particles.add(
                AsteroidsParticle(
                    x = x,
                    y = y,
                    vx = cos(ang) * spd,
                    vy = sin(ang) * spd,
                    lifeSec = life,
                    maxLifeSec = life,
                    colorRgb = colorRgb
                )
            )
        }
    }

    private fun wrapX(x: Float): Float {
        if (x < 0f) return x + worldWidth
        if (x >= worldWidth) return x - worldWidth
        return x
    }

    private fun wrapY(y: Float): Float {
        if (y < 0f) return y + worldHeight
        if (y >= worldHeight) return y - worldHeight
        return y
    }
}
