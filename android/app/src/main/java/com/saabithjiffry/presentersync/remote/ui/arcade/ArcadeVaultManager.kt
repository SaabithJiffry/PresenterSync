package com.saabithjiffry.presentersync.remote.ui.arcade

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.Locale
import java.util.concurrent.CopyOnWriteArrayList

data class ArcadeGameEntry(
    val id: String,
    val title: String,
    val subtitle: String,
    val badge: String
)

/**
 * Process-scoped RAM-only vault controller ("Sector Z").
 * Intentionally never writes unlock state to SharedPreferences or any file so the vault
 * always relocks cleanly on cold start, explicit Lock action, or host disconnect.
 */
object ArcadeVaultManager {
    private const val VAULT_TOKEN = "INSERTCOIN"

    val games: List<ArcadeGameEntry> = listOf(
        ArcadeGameEntry(
            id = "snake",
            title = "HUD Snake",
            subtitle = "Glowing matte-glass ribbon over Smart Board & Phone overlays",
            badge = "SECTOR Z-01"
        ),
        ArcadeGameEntry(
            id = "asteroids",
            title = "Asteroid Blaster",
            subtitle = "Vector thruster shooter with UFO saucers, power-ups & Mic Pill bumper",
            badge = "SECTOR Z-02"
        ),
        ArcadeGameEntry(
            id = "brick_breaker",
            title = "Brick Breaker",
            subtitle = "Neon bottom-edge paddle, armored multi-hit bricks & HUD-pill drops",
            badge = "SECTOR Z-03"
        ),
        ArcadeGameEntry(
            id = "cyber_pong",
            title = "Cyber Pong",
            subtitle = "Velocity-spin energy puck duel with 1P Adaptive AI & 2P Split-Screen Touch",
            badge = "SECTOR Z-04"
        ),
        ArcadeGameEntry(
            id = "flappy",
            title = "Clicker Flappy / Wave",
            subtitle = "Classic Flap & Gravity Wave ribbon flight with safe Clicker Slide nav & live Mic Mute",
            badge = "SECTOR Z-05"
        ),
        ArcadeGameEntry(
            id = "tron",
            title = "Neon Light Cycles (TRON)",
            subtitle = "Flood-fill AI light wall arena with rechargeable Turbo Boost & swipe/D-pad steering",
            badge = "SECTOR Z-06"
        ),
        ArcadeGameEntry(
            id = "pac_grid",
            title = "Neon Pac-Grid",
            subtitle = "Authentic 28x31 neon maze with 4 chaser personalities, Scatter/Chase waves & warp tunnel",
            badge = "SECTOR Z-07"
        ),
        ArcadeGameEntry(
            id = "missile_defense",
            title = "Missile Defense",
            subtitle = "Multi-tap interceptor defense with 4 neon shield pylons, splitters & shockwave chains",
            badge = "SECTOR Z-08"
        ),
        ArcadeGameEntry(
            id = "block_drop",
            title = "Neon Block Drop",
            subtitle = "10x20 translucent neon-glass well with 7-bag, SRS wall kicks, Ghost guide & Hold",
            badge = "SECTOR Z-09"
        ),
        ArcadeGameEntry(
            id = "pinball",
            title = "Space Cadet Pinball",
            subtitle = "240Hz sub-stepped physics table with bumpers, drop targets, rank LEDs & TILT",
            badge = "SECTOR Z-10"
        )
    )

    private val clues = listOf(
        "SECTOR Z // CLEARANCE REQUIRED — Cabinet Bus at 0 Credits.",
        "Inspect the About screen header icon or build telemetry pulse.",
        "Coin-op legend: classic twin-word cabinet start command.",
        "Desktop hosts listen for the Sector Z chord when no dialog is focused."
    )

    private val _isUnlocked = MutableStateFlow(false)
    val isUnlocked: StateFlow<Boolean> = _isUnlocked.asStateFlow()

    private val lockListeners = CopyOnWriteArrayList<() -> Unit>()
    private var clueCursor = 0

    fun normalizePasscode(raw: String): String {
        return raw.uppercase(Locale.US).replace(Regex("[^A-Z0-9]"), "")
    }

    fun validatePasscode(raw: String): Boolean {
        return normalizePasscode(raw) == VAULT_TOKEN
    }

    fun tryUnlock(raw: String): Boolean {
        if (!validatePasscode(raw)) return false
        _isUnlocked.value = true
        return true
    }

    fun lock() {
        _isUnlocked.value = false
        for (listener in lockListeners) {
            runCatching { listener() }
        }
    }

    fun registerLockListener(listener: () -> Unit) {
        if (!lockListeners.contains(listener)) {
            lockListeners.add(listener)
        }
    }

    fun unregisterLockListener(listener: () -> Unit) {
        lockListeners.remove(listener)
    }

    @Synchronized
    fun nextClue(): String {
        val text = clues[clueCursor % clues.size]
        clueCursor = (clueCursor + 1) % clues.size
        return text
    }
}
