package com.saabithjiffry.presentersync.remote.input

import com.saabithjiffry.presentersync.remote.config.AppConstants
import com.saabithjiffry.presentersync.remote.config.RemoteConfig

enum class KeyAction {
    DOWN,
    UP
}

enum class ClickerDecision {
    PASS_THROUGH,
    CONSUME_NOOP,
    CONSUME_TOGGLE,
    CONSUME_COUGH_HOLD_MUTE,
    CONSUME_COUGH_RELEASE_UNMUTE,
    TRIGGER_TOGGLE_SHORTCUT,
    TRIGGER_EXIT_SHORTCUT
}

data class ShortcutSpec(
    val ctrl: Boolean,
    val alt: Boolean,
    val shift: Boolean,
    val keyCodeName: String
)

class ClickerMuteController(
    private val clockMs: () -> Long = { System.currentTimeMillis() }
) {
    private var lastToggleAtMs: Long = -AppConstants.CLICKER_DEBOUNCE_MS
    private var isDownActive: Boolean = false
    private var downAtMs: Long = 0L
    private var coughHoldActive: Boolean = false
    private var pressedWithoutToggle: Boolean = false

    @Synchronized
    fun onKeyEvent(
        keyCodeName: String,
        action: KeyAction,
        isCtrl: Boolean,
        isAlt: Boolean,
        isShift: Boolean,
        repeatCount: Int,
        config: RemoteConfig
    ): ClickerDecision {
        val normIncoming = normalizeKeyCodeName(keyCodeName)

        if (!config.hotkeysSuspended && action == KeyAction.DOWN && repeatCount == 0) {
            if (matchesShortcut(config.exitShortcut, normIncoming, isCtrl, isAlt, isShift)) {
                return ClickerDecision.TRIGGER_EXIT_SHORTCUT
            }
            if (matchesShortcut(config.toggleMuteShortcut, normIncoming, isCtrl, isAlt, isShift)) {
                val now = clockMs()
                if (now - lastToggleAtMs >= AppConstants.CLICKER_DEBOUNCE_MS) {
                    lastToggleAtMs = now
                    return ClickerDecision.TRIGGER_TOGGLE_SHORTCUT
                }
                return ClickerDecision.CONSUME_NOOP
            }
        }

        if (!config.enablePointerIntercept || !config.enablePointerMute || config.hotkeysSuspended) {
            resetHoldState()
            return ClickerDecision.PASS_THROUGH
        }

        val targetKey = normalizeKeyCodeName(config.hwMuteHotkey)
        if (targetKey == "NONE" || targetKey != normIncoming) {
            return ClickerDecision.PASS_THROUGH
        }

        val now = clockMs()
        return when (action) {
            KeyAction.DOWN -> {
                if (repeatCount > 0 || isDownActive) {
                    return ClickerDecision.CONSUME_NOOP
                }
                isDownActive = true
                if (now - lastToggleAtMs < AppConstants.CLICKER_DEBOUNCE_MS) {
                    pressedWithoutToggle = true
                    coughHoldActive = false
                    ClickerDecision.CONSUME_NOOP
                } else {
                    lastToggleAtMs = now
                    downAtMs = now
                    pressedWithoutToggle = false
                    coughHoldActive = config.enablePushToMute
                    if (config.enablePushToMute) {
                        ClickerDecision.CONSUME_COUGH_HOLD_MUTE
                    } else {
                        ClickerDecision.CONSUME_TOGGLE
                    }
                }
            }
            KeyAction.UP -> {
                if (!isDownActive) {
                    return ClickerDecision.CONSUME_NOOP
                }
                isDownActive = false
                if (pressedWithoutToggle) {
                    pressedWithoutToggle = false
                    coughHoldActive = false
                    return ClickerDecision.CONSUME_NOOP
                }
                val heldDuration = now - downAtMs
                val wasCoughHold = coughHoldActive
                coughHoldActive = false
                if (wasCoughHold && config.enablePushToMute && heldDuration >= AppConstants.PUSH_TO_MUTE_HOLD_MS) {
                    lastToggleAtMs = now
                    ClickerDecision.CONSUME_COUGH_RELEASE_UNMUTE
                } else {
                    ClickerDecision.CONSUME_NOOP
                }
            }
        }
    }

    @Synchronized
    fun resetHoldState() {
        isDownActive = false
        coughHoldActive = false
        pressedWithoutToggle = false
    }

    companion object {
        private val KEY_ALIASES = mapOf(
            "NONE" to "NONE",
            "" to "NONE",
            "B" to "KEYCODE_B",
            "M" to "KEYCODE_M",
            "ESC" to "KEYCODE_ESCAPE",
            "ESCAPE" to "KEYCODE_ESCAPE",
            "PGDN" to "KEYCODE_PAGE_DOWN",
            "PAGEDOWN" to "KEYCODE_PAGE_DOWN",
            "NEXT" to "KEYCODE_PAGE_DOWN",
            "PGUP" to "KEYCODE_PAGE_UP",
            "PAGEUP" to "KEYCODE_PAGE_UP",
            "PRIOR" to "KEYCODE_PAGE_UP",
            "ENTER" to "KEYCODE_ENTER",
            "RETURN" to "KEYCODE_ENTER",
            "NUMPADENTER" to "KEYCODE_NUMPAD_ENTER",
            "SPACE" to "KEYCODE_SPACE",
            "TAB" to "KEYCODE_TAB",
            "LEFT" to "KEYCODE_DPAD_LEFT",
            "RIGHT" to "KEYCODE_DPAD_RIGHT",
            "UP" to "KEYCODE_DPAD_UP",
            "DOWN" to "KEYCODE_DPAD_DOWN",
            "VOLUMEUP" to "KEYCODE_VOLUME_UP",
            "VOLUME_UP" to "KEYCODE_VOLUME_UP",
            "VOLUMEDOWN" to "KEYCODE_VOLUME_DOWN",
            "VOLUME_DOWN" to "KEYCODE_VOLUME_DOWN",
            "MEDIAPLAYPAUSE" to "KEYCODE_MEDIA_PLAY_PAUSE",
            "MEDIA_PLAY_PAUSE" to "KEYCODE_MEDIA_PLAY_PAUSE"
        )

        fun normalizeKeyCodeName(raw: String): String {
            val clean = raw.trim().uppercase()
            if (clean.isEmpty()) return "NONE"
            KEY_ALIASES[clean]?.let { return it }
            if (clean.startsWith("KEYCODE_")) return clean
            val compact = clean.replace(" ", "_")
            return "KEYCODE_$compact"
        }

        fun friendlyKeyLabel(raw: String): String {
            val norm = normalizeKeyCodeName(raw)
            if (norm == "NONE") return "Disabled"
            val short = norm.removePrefix("KEYCODE_")
            return when (short) {
                "PAGE_DOWN" -> "Page Down (PgDn)"
                "PAGE_UP" -> "Page Up (PgUp)"
                "ESCAPE" -> "Escape (Esc)"
                "MEDIA_PLAY_PAUSE" -> "Media Play/Pause"
                "VOLUME_UP" -> "Volume Up"
                "VOLUME_DOWN" -> "Volume Down"
                "DPAD_LEFT" -> "Left Arrow"
                "DPAD_RIGHT" -> "Right Arrow"
                "DPAD_UP" -> "Up Arrow"
                "DPAD_DOWN" -> "Down Arrow"
                "NUMPAD_ENTER" -> "Numpad Enter"
                else -> short.replace('_', ' ').split(' ')
                    .joinToString(" ") { w -> w.lowercase().replaceFirstChar { it.uppercase() } }
                    .let { if (short.length == 1) short else it }
            }
        }

        fun parseShortcut(raw: String): ShortcutSpec? {
            val trimmed = raw.trim()
            if (trimmed.isEmpty() || trimmed.equals("None", ignoreCase = true)) return null

            // Support AHK format (^!+F12) as well as human format (Ctrl+Alt+Shift+F12)
            return if (!trimmed.contains("+") && (trimmed.startsWith("^") || trimmed.startsWith("!") || trimmed.startsWith("+"))) {
                var idx = 0
                var ctrl = false
                var alt = false
                var shift = false
                while (idx < trimmed.length) {
                    when (trimmed[idx]) {
                        '^' -> ctrl = true
                        '!' -> alt = true
                        '+' -> shift = true
                        else -> break
                    }
                    idx++
                }
                val keyPart = trimmed.substring(idx).trim()
                if (keyPart.isEmpty()) null else ShortcutSpec(ctrl, alt, shift, normalizeKeyCodeName(keyPart))
            } else {
                val parts = trimmed.split("+").map { it.trim() }.filter { it.isNotEmpty() }
                if (parts.isEmpty()) return null
                var ctrl = false
                var alt = false
                var shift = false
                var mainKey: String? = null
                for (p in parts) {
                    when (p.uppercase()) {
                        "CTRL", "CONTROL" -> ctrl = true
                        "ALT" -> alt = true
                        "SHIFT" -> shift = true
                        else -> mainKey = p
                    }
                }
                val finalKey = mainKey ?: return null
                ShortcutSpec(ctrl, alt, shift, normalizeKeyCodeName(finalKey))
            }
        }

        fun matchesShortcut(
            shortcutRaw: String,
            normalizedKeyCodeName: String,
            isCtrl: Boolean,
            isAlt: Boolean,
            isShift: Boolean
        ): Boolean {
            val spec = parseShortcut(shortcutRaw) ?: return false
            return spec.keyCodeName == normalizedKeyCodeName &&
                spec.ctrl == isCtrl &&
                spec.alt == isAlt &&
                spec.shift == isShift
        }

        fun formatShortcutForDisplay(ctrl: Boolean, alt: Boolean, shift: Boolean, keyCodeName: String): String {
            val base = friendlyKeyLabel(keyCodeName)
            return buildList {
                if (ctrl) add("Ctrl")
                if (alt) add("Alt")
                if (shift) add("Shift")
                add(base)
            }.joinToString("+")
        }
    }
}
