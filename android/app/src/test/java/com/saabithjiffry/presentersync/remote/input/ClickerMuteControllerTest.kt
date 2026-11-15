package com.saabithjiffry.presentersync.remote.input

import com.saabithjiffry.presentersync.remote.config.RemoteConfig
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ClickerMuteControllerTest {

    @Test
    fun debouncesRapidClicksAndPassesThroughSlideKeys() {
        var now = 1000L
        val controller = ClickerMuteController { now }
        val cfg = RemoteConfig(hwMuteHotkey = "KEYCODE_B", enablePointerMute = true, enablePushToMute = false)

        // Slide key must pass through uninterrupted
        assertEquals(
            ClickerDecision.PASS_THROUGH,
            controller.onKeyEvent("KEYCODE_DPAD_RIGHT", KeyAction.DOWN, false, false, false, 0, cfg)
        )

        // Press 1 toggles
        assertEquals(
            ClickerDecision.CONSUME_TOGGLE,
            controller.onKeyEvent("KEYCODE_B", KeyAction.DOWN, false, false, false, 0, cfg)
        )
        // OS key repeat consumed without duplicate toggle
        assertEquals(
            ClickerDecision.CONSUME_NOOP,
            controller.onKeyEvent("KEYCODE_B", KeyAction.DOWN, false, false, false, 1, cfg)
        )
        assertEquals(
            ClickerDecision.CONSUME_NOOP,
            controller.onKeyEvent("KEYCODE_B", KeyAction.UP, false, false, false, 0, cfg)
        )

        // Bounce within 50ms blocked
        now += 50L
        assertEquals(
            ClickerDecision.CONSUME_NOOP,
            controller.onKeyEvent("KEYCODE_B", KeyAction.DOWN, false, false, false, 0, cfg)
        )
        assertEquals(
            ClickerDecision.CONSUME_NOOP,
            controller.onKeyEvent("KEYCODE_B", KeyAction.UP, false, false, false, 0, cfg)
        )

        // After 150ms debounce expires -> toggles cleanly again
        now += 160L
        assertEquals(
            ClickerDecision.CONSUME_TOGGLE,
            controller.onKeyEvent("KEYCODE_B", KeyAction.DOWN, false, false, false, 0, cfg)
        )
    }

    @Test
    fun pushToMuteCoughHoldMutesOnPressAndUnmutesAfter350msHold() {
        var now = 5000L
        val controller = ClickerMuteController { now }
        val cfg = RemoteConfig(hwMuteHotkey = "b", enablePointerMute = true, enablePushToMute = true)

        // Short tap (<350ms) stays muted (does not release-unmute)
        assertEquals(
            ClickerDecision.CONSUME_COUGH_HOLD_MUTE,
            controller.onKeyEvent("KEYCODE_B", KeyAction.DOWN, false, false, false, 0, cfg)
        )
        now += 120L
        assertEquals(
            ClickerDecision.CONSUME_NOOP,
            controller.onKeyEvent("KEYCODE_B", KeyAction.UP, false, false, false, 0, cfg)
        )

        // Wait past debounce, then hold >= 350ms -> cough release unmutes
        now += 250L
        assertEquals(
            ClickerDecision.CONSUME_COUGH_HOLD_MUTE,
            controller.onKeyEvent("KEYCODE_B", KeyAction.DOWN, false, false, false, 0, cfg)
        )
        now += 400L
        assertEquals(
            ClickerDecision.CONSUME_COUGH_RELEASE_UNMUTE,
            controller.onKeyEvent("KEYCODE_B", KeyAction.UP, false, false, false, 0, cfg)
        )
    }

    @Test
    fun honorsSuspendAndGlobalShortcutsAndKeyAliases() {
        var now = 2000L
        val controller = ClickerMuteController { now }
        val cfg = RemoteConfig(
            hwMuteHotkey = "PgDn",
            enablePointerMute = true,
            toggleMuteShortcut = "Ctrl+F12",
            exitShortcut = "Alt+Shift+F12",
            hotkeysSuspended = false
        )

        assertEquals(
            ClickerDecision.CONSUME_TOGGLE,
            controller.onKeyEvent("KEYCODE_PAGE_DOWN", KeyAction.DOWN, false, false, false, 0, cfg)
        )

        now += 300L
        assertEquals(
            ClickerDecision.TRIGGER_TOGGLE_SHORTCUT,
            controller.onKeyEvent("KEYCODE_F12", KeyAction.DOWN, isCtrl = true, isAlt = false, isShift = false, 0, cfg)
        )

        assertEquals(
            ClickerDecision.TRIGGER_EXIT_SHORTCUT,
            controller.onKeyEvent("KEYCODE_F12", KeyAction.DOWN, isCtrl = false, isAlt = true, isShift = true, 0, cfg)
        )

        // When suspended, neither clicker nor shortcuts consume or fire
        val suspendedCfg = cfg.copy(hotkeysSuspended = true)
        assertEquals(
            ClickerDecision.PASS_THROUGH,
            controller.onKeyEvent("KEYCODE_PAGE_DOWN", KeyAction.DOWN, false, false, false, 0, suspendedCfg)
        )
        assertEquals(
            ClickerDecision.PASS_THROUGH,
            controller.onKeyEvent("KEYCODE_F12", KeyAction.DOWN, isCtrl = true, isAlt = false, isShift = false, 0, suspendedCfg)
        )

        assertTrue(ClickerMuteController.matchesShortcut("^!F12", "KEYCODE_F12", isCtrl = true, isAlt = true, isShift = false))
        assertFalse(ClickerMuteController.matchesShortcut("^!F12", "KEYCODE_F12", isCtrl = true, isAlt = false, isShift = false))
    }
}
