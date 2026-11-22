package com.saabithjiffry.presentersync.remote.ui.screens

import android.annotation.SuppressLint
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.view.KeyEvent
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.saabithjiffry.presentersync.remote.PresenterSyncRemoteApp
import com.saabithjiffry.presentersync.remote.config.RemoteConfig
import com.saabithjiffry.presentersync.remote.input.CapturedKeyEvent
import com.saabithjiffry.presentersync.remote.input.ClickerDecision
import com.saabithjiffry.presentersync.remote.input.ClickerMuteController
import com.saabithjiffry.presentersync.remote.input.InAppKeyMonitor
import com.saabithjiffry.presentersync.remote.input.KeyAction
import com.saabithjiffry.presentersync.remote.service.FloatingHudForegroundService
import com.saabithjiffry.presentersync.remote.ui.theme.PresenterSyncTheme
class MainActivity : ComponentActivity() {

    private var pendingDeepLink by mutableStateOf<Pair<Long, String>?>(null)
    private val focusedKeyController = ClickerMuteController()

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        captureDeepLink(intent)
        handleAutoStartIntent(intent)
        val app = application as PresenterSyncRemoteApp

        setContent {
            val cfg by app.configStore.config.collectAsStateWithLifecycle()

            PresenterSyncTheme(themeMode = cfg.themeMode) {
                RemoteDashboardScreen(
                    app = app,
                    pendingDeepLink = pendingDeepLink,
                    onConsumeDeepLink = { pendingDeepLink = null },
                    onRequestOverlayPermission = { openOverlayPermissionSettings() }
                )
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureDeepLink(intent)
        handleAutoStartIntent(intent)
    }

    private fun handleAutoStartIntent(intent: Intent?) {
        if (intent?.getBooleanExtra(EXTRA_AUTO_START_HUD, false) == true) {
            intent.removeExtra(EXTRA_AUTO_START_HUD)
            if (Settings.canDrawOverlays(this)) {
                FloatingHudForegroundService.startService(this)
            }
        }
    }

    companion object {
        const val EXTRA_AUTO_START_HUD = "com.saabithjiffry.presentersync.remote.EXTRA_AUTO_START_HUD"
    }

    private fun captureDeepLink(intent: Intent?) {
        if (intent?.action == Intent.ACTION_VIEW) {
            val rawUri = intent.dataString?.trim().orEmpty()
            if (rawUri.startsWith("presentersync://", ignoreCase = true)) {
                pendingDeepLink = System.nanoTime() to rawUri
            }
        }
    }

    private fun openOverlayPermissionSettings() {
        val intent = Intent(
            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
            Uri.parse("package:$packageName")
        )
        startActivity(intent)
    }

    /**
     * Intercepts hardware clicker keys before focused Compose/View widgets consume them.
     *
     * Note: android.app.Activity.dispatchKeyEvent is a public framework API; androidx.core 1.12.0's
     * ComponentActivity carries a spurious @RestrictTo(LIBRARY_GROUP_PREFIX) annotation on this
     * override (AndroidX issue b/266756585), so RestrictedApi is suppressed locally here.
     */
    @SuppressLint("RestrictedApi")
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val navIgnored = event.keyCode == KeyEvent.KEYCODE_BACK ||
            event.keyCode == KeyEvent.KEYCODE_HOME ||
            event.keyCode == KeyEvent.KEYCODE_POWER
        val isKeyEdge = event.action == KeyEvent.ACTION_DOWN || event.action == KeyEvent.ACTION_UP
        if (!navIgnored && isKeyEdge) {
            val keyName = KeyEvent.keyCodeToString(event.keyCode)
            val app = application as PresenterSyncRemoteApp
            val cfg = app.configStore.current
            if (handleCaptureNextKey(event, keyName)) return true
            if (InAppKeyMonitor.testerMode.get()) {
                handleKeyTesterPreview(event, keyName, cfg)
            } else if (handleFocusedClickerKey(event, keyName, app, cfg)) {
                return true
            }
        }
        return super.dispatchKeyEvent(event)
    }

    private fun handleCaptureNextKey(event: KeyEvent, keyName: String): Boolean {
        if (event.action != KeyEvent.ACTION_DOWN || event.repeatCount != 0) return false
        if (!InAppKeyMonitor.captureNextKeyMode.get()) return false
        val isModifierOnly = event.keyCode == KeyEvent.KEYCODE_CTRL_LEFT ||
            event.keyCode == KeyEvent.KEYCODE_CTRL_RIGHT ||
            event.keyCode == KeyEvent.KEYCODE_ALT_LEFT ||
            event.keyCode == KeyEvent.KEYCODE_ALT_RIGHT ||
            event.keyCode == KeyEvent.KEYCODE_SHIFT_LEFT ||
            event.keyCode == KeyEvent.KEYCODE_SHIFT_RIGHT ||
            event.keyCode == KeyEvent.KEYCODE_META_LEFT ||
            event.keyCode == KeyEvent.KEYCODE_META_RIGHT ||
            event.keyCode == KeyEvent.KEYCODE_SYM ||
            event.keyCode == KeyEvent.KEYCODE_FUNCTION
        if (isModifierOnly) return true
        InAppKeyMonitor.captureNextKeyMode.set(false)
        val chord = buildString {
            if (event.isCtrlPressed) append("Ctrl+")
            if (event.isAltPressed) append("Alt+")
            if (event.isShiftPressed) append("Shift+")
            append(keyName.removePrefix("KEYCODE_"))
        }
        InAppKeyMonitor.recordUiCapturedEvent(
            CapturedKeyEvent(
                seq = System.nanoTime(),
                keyCode = event.keyCode,
                keyCodeName = keyName,
                displayName = ClickerMuteController.friendlyKeyLabel(keyName),
                scanCode = event.scanCode,
                deviceName = event.device?.name ?: "Focused Window",
                action = "DOWN",
                decisionLabel = "Captured Keystroke: $chord",
                consumed = true,
                timestampMs = System.currentTimeMillis(),
                isCtrl = event.isCtrlPressed,
                isAlt = event.isAltPressed,
                isShift = event.isShiftPressed,
                shortcutString = chord
            )
        )
        return true
    }

    private fun handleKeyTesterPreview(event: KeyEvent, keyName: String, cfg: RemoteConfig) {
        if (event.action != KeyEvent.ACTION_DOWN || event.repeatCount != 0) return
        val matched = ClickerMuteController.normalizeKeyCodeName(cfg.hwMuteHotkey) ==
            ClickerMuteController.normalizeKeyCodeName(keyName)
        InAppKeyMonitor.recordUiCapturedEvent(
            CapturedKeyEvent(
                seq = System.nanoTime(),
                keyCode = event.keyCode,
                keyCodeName = keyName,
                displayName = ClickerMuteController.friendlyKeyLabel(keyName),
                scanCode = event.scanCode,
                deviceName = event.device?.name ?: "Focused Window",
                action = "DOWN",
                decisionLabel = if (matched) "Matched Mute Button (Preview)" else "Other Key (Pass Through)",
                consumed = matched,
                timestampMs = System.currentTimeMillis()
            )
        )
    }

    private fun handleFocusedClickerKey(
        event: KeyEvent,
        keyName: String,
        app: PresenterSyncRemoteApp,
        cfg: RemoteConfig
    ): Boolean {
        val action = if (event.action == KeyEvent.ACTION_DOWN) KeyAction.DOWN else KeyAction.UP
        val decision = focusedKeyController.onKeyEvent(
            keyCodeName = keyName,
            action = action,
            isCtrl = event.isCtrlPressed,
            isAlt = event.isAltPressed,
            isShift = event.isShiftPressed,
            repeatCount = event.repeatCount,
            config = cfg,
            isMuted = app.connectionManager.uiState.value.isMuted
        )
        return when (decision) {
            ClickerDecision.CONSUME_TOGGLE,
            ClickerDecision.TRIGGER_TOGGLE_SHORTCUT -> {
                app.connectionManager.toggleMuteFromClicker()
                true
            }
            ClickerDecision.CONSUME_COUGH_HOLD_MUTE,
            ClickerDecision.CONSUME_PTT_RELEASE_MUTE -> {
                app.connectionManager.setMuteFromClicker(true)
                true
            }
            ClickerDecision.CONSUME_COUGH_RELEASE_UNMUTE,
            ClickerDecision.CONSUME_PTT_HOLD_UNMUTE -> {
                app.connectionManager.setMuteFromClicker(false)
                true
            }
            ClickerDecision.TRIGGER_EXIT_SHORTCUT -> {
                FloatingHudForegroundService.startService(this, FloatingHudForegroundService.ACTION_STOP)
                true
            }
            ClickerDecision.CONSUME_NOOP -> true
            ClickerDecision.PASS_THROUGH -> false
        }
    }
}

