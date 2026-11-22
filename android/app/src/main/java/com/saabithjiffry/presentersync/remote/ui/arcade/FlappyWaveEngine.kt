package com.saabithjiffry.presentersync.remote.ui.arcade

import com.saabithjiffry.presentersync.remote.input.ClickerMuteController
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.random.Random

enum class FlappyMode {
    CLASSIC_FLAP,
    GRAVITY_WAVE
}

enum class FlappyPhase {
    IDLE,
    PLAYING,
    PAUSED,
    GAME_OVER
}

enum class FlappyBonusKind(val label: String) {
    SHIELD("SHIELD"),
    SLOW_MO("SLOW-MO")
}

data class FlappyGate(
    var x: Float,
    val w: Float,
    var gapY: Float,
    val gapH: Float,
    var passed: Boolean = false,
    var pulsePhase: Float = 0f
)

data class FlappyBonusRing(
    var x: Float,
    var y: Float,
    val radius: Float,
    val kind: FlappyBonusKind
)

data class FlappyTrailPoint(
    var x: Float,
    var y: Float
)

data class FlappyParticle(
    var x: Float,
    var y: Float,
    var vx: Float,
    var vy: Float,
    var lifeSec: Float,
    val maxLifeSec: Float,
    val colorRgb: Int
)

data class FlappyPopup(
    var x: Float,
    var y: Float,
    val text: String,
    var lifeSec: Float,
    val maxLifeSec: Float,
    val colorRgb: Int
)

/**
 * Sector Z-05: Pure Kotlin Clicker Flappy / Gravity Wave physics engine.
 * Zero Android framework imports so unit tests execute natively on the JVM without Robolectric.
 */
class FlappyWaveEngine(
    private val random: Random = Random.Default,
    private val onNewHighScore: (Int) -> Unit = {}
) {
    var phase: FlappyPhase = FlappyPhase.IDLE
        private set
    var mode: FlappyMode = FlappyMode.CLASSIC_FLAP
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

    var craftX: Float = 240f
        private set
    var craftY: Float = 540f
        private set
    var craftVy: Float = 0f
        private set
    var craftRadius: Float = 16f
        private set
    var isHolding: Boolean = false
        private set

    var shieldTimerSec: Float = 0f
        private set
    var slowMoTimerSec: Float = 0f
        private set
    var scrollSpeed: Float = 320f
        private set

    private val _gates = mutableListOf<FlappyGate>()
    val gates: List<FlappyGate> get() = _gates

    private val _rings = mutableListOf<FlappyBonusRing>()
    val rings: List<FlappyBonusRing> get() = _rings

    private val _trail = mutableListOf<FlappyTrailPoint>()
    val trail: List<FlappyTrailPoint> get() = _trail

    private val _particles = mutableListOf<FlappyParticle>()
    val particles: List<FlappyParticle> get() = _particles

    private val _popups = mutableListOf<FlappyPopup>()
    val popups: List<FlappyPopup> get() = _popups

    fun startNewSession(
        widthPx: Int,
        heightPx: Int,
        screenDensity: Float = 2f,
        initialHighScore: Int = 0,
        bumperRect: ArcadeRectF? = null,
        initialMode: FlappyMode = this.mode
    ) {
        worldWidth = widthPx.coerceAtLeast(320).toFloat()
        worldHeight = heightPx.coerceAtLeast(320).toFloat()
        density = screenDensity.coerceIn(0.75f, 4.5f)
        pillBumper = bumperRect
        highScore = max(highScore, initialHighScore.coerceAtLeast(0))
        mode = initialMode
        resetRun()
    }

    fun updateDisplayMetrics(
        widthPx: Int,
        heightPx: Int,
        screenDensity: Float,
        bumperRect: ArcadeRectF? = pillBumper
    ) {
        worldWidth = widthPx.coerceAtLeast(320).toFloat()
        worldHeight = heightPx.coerceAtLeast(320).toFloat()
        density = screenDensity.coerceIn(0.75f, 4.5f)
        pillBumper = bumperRect
        craftRadius = 12f * density
        craftX = max(120f * density, worldWidth * 0.24f)
        craftY = craftY.coerceIn(topBound() + craftRadius, bottomBound() - craftRadius)
    }

    fun resetRun() {
        score = 0
        shieldTimerSec = 0f
        slowMoTimerSec = 0f
        isHolding = false
        craftRadius = 12f * density
        craftX = max(120f * density, worldWidth * 0.24f)
        craftY = worldHeight * 0.48f
        craftVy = 0f
        scrollSpeed = 240f * density

        _gates.clear()
        _rings.clear()
        _trail.clear()
        _particles.clear()
        _popups.clear()
        _trail.add(FlappyTrailPoint(craftX, craftY))

        val firstX = max(craftX + 260f * density, worldWidth * 0.56f)
        val spacing = 260f * density
        val gapH = 148f * density
        val gateW = 52f * density
        for (i in 0 until 3) {
            spawnGate(firstX + i * spacing, randomGapY(gapH), gapH, gateW)
        }
        phase = FlappyPhase.PLAYING
    }

    fun stop() {
        phase = FlappyPhase.IDLE
        isHolding = false
    }

    fun togglePause() {
        if (phase == FlappyPhase.PLAYING) {
            phase = FlappyPhase.PAUSED
            isHolding = false
        } else if (phase == FlappyPhase.PAUSED) {
            phase = FlappyPhase.PLAYING
        }
    }

    fun setMode(targetMode: FlappyMode): FlappyMode {
        mode = targetMode
        return mode
    }

    fun toggleMode(): FlappyMode {
        mode = if (mode == FlappyMode.CLASSIC_FLAP) FlappyMode.GRAVITY_WAVE else FlappyMode.CLASSIC_FLAP
        val label = if (mode == FlappyMode.GRAVITY_WAVE) "MODE: GRAVITY WAVE" else "MODE: CLASSIC FLAP"
        _popups.add(
            FlappyPopup(
                x = craftX + 24f * density,
                y = max(topBound() + 28f * density, craftY - 24f * density),
                text = label,
                lifeSec = 0.85f,
                maxLifeSec = 0.85f,
                colorRgb = 0x38BDF8
            )
        )
        return mode
    }

    fun flapOrHold(down: Boolean): Boolean {
        if (phase == FlappyPhase.GAME_OVER) {
            if (down) resetRun()
            return true
        }
        if (phase != FlappyPhase.PLAYING) return false

        val wasHolding = isHolding
        isHolding = down
        if (down) {
            if (mode == FlappyMode.CLASSIC_FLAP) {
                if (!wasHolding) {
                    craftVy = -340f * density
                    spawnSparks(craftX - 8f * density, craftY + 5f * density, 0x38BDF8, 5)
                }
            } else {
                if (!wasHolding && craftVy > 50f * density) {
                    craftVy = 24f * density
                }
            }
        } else {
            if (mode == FlappyMode.GRAVITY_WAVE && wasHolding && craftVy < -50f * density) {
                craftVy = -24f * density
            }
        }
        return true
    }

    fun step(dtSec: Float) {
        if (phase != FlappyPhase.PLAYING) return
        val dt = dtSec.coerceIn(0.0005f, 0.05f)

        if (shieldTimerSec > 0f) shieldTimerSec = max(0f, shieldTimerSec - dt)
        if (slowMoTimerSec > 0f) slowMoTimerSec = max(0f, slowMoTimerSec - dt)

        val timeScale = if (slowMoTimerSec > 0f) 0.65f else 1f
        val baseSpd = min(420f * density, (240f + score * 6.5f) * density)
        scrollSpeed = baseSpd * timeScale
        val effDt = dt * timeScale

        // Vertical craft physics: Classic Flap vs Gravity Wave
        if (mode == FlappyMode.GRAVITY_WAVE) {
            if (isHolding) {
                craftVy = max(-380f * density, craftVy - 1350f * density * effDt)
            } else {
                craftVy = min(390f * density, craftVy + 1300f * density * effDt)
            }
        } else {
            craftVy = min(560f * density, craftVy + 960f * density * effDt)
        }
        craftY += craftVy * effDt

        // Scroll & append ribbon trail points
        val trailIt = _trail.iterator()
        while (trailIt.hasNext()) {
            val tp = trailIt.next()
            tp.x -= scrollSpeed * dt
            if (tp.x < 12f * density) {
                trailIt.remove()
            }
        }
        _trail.add(FlappyTrailPoint(craftX, craftY))
        while (_trail.size > 52) {
            _trail.removeAt(0)
        }

        // Ceiling & floor bounds
        val minY = topBound()
        val maxY = bottomBound()
        if (craftY - craftRadius < minY) {
            craftY = minY + craftRadius
            if (craftVy < 0f) craftVy = 0f
        }
        if (craftY + craftRadius > maxY) {
            if (shieldTimerSec > 0f) {
                shieldTimerSec = 0f
                craftY = maxY - craftRadius - 4f * density
                craftVy = -260f * density
                _popups.add(FlappyPopup(craftX, craftY - 16f * density, "SHIELD SAVED!", 0.8f, 0.8f, 0x34D399))
            } else {
                craftY = maxY - craftRadius
                phase = FlappyPhase.GAME_OVER
                return
            }
        }

        // Update scrolling gates: score pass & pillar collision
        var rightmostX = 0f
        var idx = _gates.size - 1
        while (idx >= 0) {
            val gt = _gates[idx]
            gt.x -= scrollSpeed * dt
            gt.pulsePhase += dt * 3.2f
            if (gt.x > rightmostX) rightmostX = gt.x

            if (!gt.passed && (gt.x + gt.w * 0.5f) < craftX) {
                gt.passed = true
                addScore(1, craftX, craftY - 18f * density, 0x34D399)
                spawnSparks(craftX, craftY, 0x34D399, 6)
            }

            if ((craftX + craftRadius) > gt.x && (craftX - craftRadius) < (gt.x + gt.w)) {
                val gapTop = gt.gapY - gt.gapH * 0.5f
                val gapBot = gt.gapY + gt.gapH * 0.5f
                if ((craftY - craftRadius) < gapTop || (craftY + craftRadius) > gapBot) {
                    if (shieldTimerSec > 0f) {
                        shieldTimerSec = 0f
                        gt.passed = true
                        _gates.removeAt(idx)
                        _popups.add(FlappyPopup(craftX, craftY - 18f * density, "SHIELD BREAK!", 0.85f, 0.85f, 0xF59E0B))
                        spawnSparks(craftX, craftY, 0xF59E0B, 10)
                        idx--
                        continue
                    } else {
                        spawnSparks(craftX, craftY, 0xEF4444, 14)
                        phase = FlappyPhase.GAME_OVER
                        return
                    }
                }
            }

            if (gt.x + gt.w < -40f * density) {
                _gates.removeAt(idx)
            }
            idx--
        }

        // Procedural horizon gate spawning
        if (_gates.isNotEmpty() && rightmostX < worldWidth - 140f * density) {
            val gapH = max(112f * density, (148f - score * 1.15f) * density)
            val gateW = 52f * density
            val nextX = max(worldWidth + 32f * density, rightmostX + 260f * density)
            val nextGapY = randomGapY(gapH)
            spawnGate(nextX, nextGapY, gapH, gateW)
            if ((score + _gates.size) % 4 == 0) {
                val kind = if (score % 2 == 0) FlappyBonusKind.SHIELD else FlappyBonusKind.SLOW_MO
                spawnBonusRing(nextX + 130f * density, nextGapY, kind)
            }
        }

        // Update bonus rings
        var rIdx = _rings.size - 1
        while (rIdx >= 0) {
            val rg = _rings[rIdx]
            rg.x -= scrollSpeed * dt
            val dx = craftX - rg.x
            val dy = craftY - rg.y
            val sumR = craftRadius + rg.radius
            if (dx * dx + dy * dy <= sumR * sumR) {
                when (rg.kind) {
                    FlappyBonusKind.SHIELD -> {
                        shieldTimerSec = 8f
                        _popups.add(FlappyPopup(rg.x, rg.y - 12f * density, "SHIELD", 0.85f, 0.85f, 0x38BDF8))
                    }
                    FlappyBonusKind.SLOW_MO -> {
                        slowMoTimerSec = 6f
                        _popups.add(FlappyPopup(rg.x, rg.y - 12f * density, "SLOW-MO", 0.85f, 0.85f, 0xA855F7))
                    }
                }
                addScore(2, rg.x, rg.y, 0x38BDF8)
                _rings.removeAt(rIdx)
                rIdx--
                continue
            }
            if (rg.x + rg.radius < -30f * density) {
                _rings.removeAt(rIdx)
            }
            rIdx--
        }

        // Update particles & floating popups
        var pIdx = _particles.size - 1
        while (pIdx >= 0) {
            val pt = _particles[pIdx]
            pt.lifeSec -= dt
            if (pt.lifeSec <= 0f) {
                _particles.removeAt(pIdx)
            } else {
                pt.x += pt.vx * dt
                pt.y += pt.vy * dt
            }
            pIdx--
        }

        var popIdx = _popups.size - 1
        while (popIdx >= 0) {
            val pp = _popups[popIdx]
            pp.lifeSec -= dt
            if (pp.lifeSec <= 0f) {
                _popups.removeAt(popIdx)
            } else {
                pp.y -= 24f * density * dt
            }
            popIdx--
        }
    }

    fun topBound(): Float = 66f * density

    fun bottomBound(): Float = max(topBound() + 180f * density, worldHeight - 20f * density)

    private fun randomGapY(gapH: Float): Float {
        val minGapY = topBound() + gapH * 0.5f + 24f * density
        val maxGapY = max(minGapY + 20f, bottomBound() - gapH * 0.5f - 24f * density)
        return minGapY + random.nextFloat() * (maxGapY - minGapY)
    }

    private fun addScore(pts: Int, x: Float, y: Float, colorRgb: Int) {
        score += pts
        if (score > highScore) {
            highScore = score
            onNewHighScore(highScore)
        }
        _popups.add(FlappyPopup(x, y, "+$pts", 0.72f, 0.72f, colorRgb))
    }

    private fun spawnSparks(x: Float, y: Float, colorRgb: Int, count: Int) {
        for (i in 0 until count) {
            val ang = random.nextFloat() * (2f * PI.toFloat())
            val spd = (40f + random.nextFloat() * 120f) * density
            _particles.add(
                FlappyParticle(
                    x = x,
                    y = y,
                    vx = cos(ang) * spd,
                    vy = sin(ang) * spd,
                    lifeSec = 0.36f,
                    maxLifeSec = 0.36f,
                    colorRgb = colorRgb
                )
            )
        }
    }

    // --- Test & Spawn Helpers ---
    fun clearGatesForTest() {
        _gates.clear()
        _rings.clear()
    }

    fun setCraftForTest(x: Float, y: Float, vy: Float = 0f) {
        craftX = x
        craftY = y
        craftVy = vy
    }

    fun spawnGate(
        x: Float,
        gapY: Float,
        gapH: Float = 148f * density,
        w: Float = 52f * density
    ): FlappyGate {
        val gt = FlappyGate(x = x, w = w, gapY = gapY, gapH = gapH)
        _gates.add(gt)
        return gt
    }

    fun spawnBonusRing(
        x: Float,
        y: Float,
        kind: FlappyBonusKind = FlappyBonusKind.SHIELD
    ): FlappyBonusRing {
        val rg = FlappyBonusRing(x = x, y = y, radius = 15f * density, kind = kind)
        _rings.add(rg)
        return rg
    }

    companion object {
        val CANDIDATE_CLICKER_KEYS: Set<String> = setOf(
            "KEYCODE_PAGE_DOWN",
            "KEYCODE_PAGE_UP",
            "KEYCODE_DPAD_UP",
            "KEYCODE_DPAD_RIGHT",
            "KEYCODE_DPAD_DOWN",
            "KEYCODE_DPAD_CENTER",
            "KEYCODE_SPACE",
            "KEYCODE_ENTER",
            "KEYCODE_W",
            "KEYCODE_BUTTON_A"
        )

        /**
         * Returns true if and only if [incomingKeyCodeName] is an allowed Clicker Flappy / Gravity Wave
         * flap/hold key AND does NOT collide with the user's configured [configuredHwMuteHotkey].
         */
        fun isClickerKeyAllowed(
            incomingKeyCodeName: String,
            configuredHwMuteHotkey: String
        ): Boolean {
            val incomingNorm = ClickerMuteController.normalizeKeyCodeName(incomingKeyCodeName)
            if (incomingNorm == "NONE") return false
            val muteNorm = ClickerMuteController.normalizeKeyCodeName(configuredHwMuteHotkey)
            if (muteNorm != "NONE" && incomingNorm == muteNorm) {
                return false
            }
            return incomingNorm in CANDIDATE_CLICKER_KEYS
        }

        fun buildAllowedClickerKeys(configuredHwMuteHotkey: String): List<String> {
            return CANDIDATE_CLICKER_KEYS.filter { isClickerKeyAllowed(it, configuredHwMuteHotkey) }
        }
    }
}
