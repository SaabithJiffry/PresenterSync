package com.saabithjiffry.presentersync.remote.service

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.provider.Settings
import android.view.KeyEvent
import android.view.accessibility.AccessibilityEvent
import com.saabithjiffry.presentersync.remote.PresenterSyncRemoteApp
import com.saabithjiffry.presentersync.remote.input.ClickerDecision
import com.saabithjiffry.presentersync.remote.input.ClickerMuteController
import com.saabithjiffry.presentersync.remote.input.KeyAction
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

data class CapturedKeyEvent(
    val seq: Long,
    val keyCode: Int,
    val keyCodeName: String,
    val displayName: String,
    val scanCode: Int,
    val deviceName: String,
    val action: String,
    val decisionLabel: String,
    val consumed: Boolean,
    val timestampMs: Long
)

class ClickerAccessibilityService : AccessibilityService() {
    private val controller = ClickerMuteController()

    override fun onServiceConnected() {
        super.onServiceConnected()
        _serviceActive.value = true
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Window content inspection is disabled; this service exclusively filters key events.
    }

    override fun onInterrupt() {
        controller.resetHoldState()
    }

    override fun onUnbind(intent: android.content.Intent?): Boolean {
        _serviceActive.value = false
        controller.resetHoldState()
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        _serviceActive.value = false
        controller.resetHoldState()
        super.onDestroy()
    }

    override fun onKeyEvent(event: KeyEvent): Boolean {
        val app = application as? PresenterSyncRemoteApp ?: return super.onKeyEvent(event)
        val cfg = app.configStore.current
        val keyName = KeyEvent.keyCodeToString(event.keyCode)
        val deviceName = event.device?.name?.takeIf { it.isNotBlank() } ?: "Input Device"
        val actionLabel = if (event.action == KeyEvent.ACTION_DOWN) "DOWN" else "UP"

        if (captureNextKeyMode.get()) {
            if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0 && !isNavigationOnlyKey(event.keyCode)) {
                captureNextKeyMode.set(false)
                val captured = CapturedKeyEvent(
                    seq = eventSeq.incrementAndGet(),
                    keyCode = event.keyCode,
                    keyCodeName = keyName,
                    displayName = ClickerMuteController.friendlyKeyLabel(keyName),
                    scanCode = event.scanCode,
                    deviceName = deviceName,
                    action = actionLabel,
                    decisionLabel = "Captured New Mute Key",
                    consumed = true,
                    timestampMs = System.currentTimeMillis()
                )
                _lastCapturedKey.value = captured
                appendTesterEvent(captured)
                return true
            }
            return if (event.action == KeyEvent.ACTION_UP && !isNavigationOnlyKey(event.keyCode)) true else super.onKeyEvent(event)
        }

        val action = when (event.action) {
            KeyEvent.ACTION_DOWN -> KeyAction.DOWN
            KeyEvent.ACTION_UP -> KeyAction.UP
            else -> return super.onKeyEvent(event)
        }

        val decision = controller.onKeyEvent(
            keyCodeName = keyName,
            action = action,
            isCtrl = event.isCtrlPressed,
            isAlt = event.isAltPressed,
            isShift = event.isShiftPressed,
            repeatCount = event.repeatCount,
            config = cfg
        )

        val consumed = when (decision) {
            ClickerDecision.CONSUME_TOGGLE -> {
                app.connectionManager.toggleMuteFromClicker()
                true
            }
            ClickerDecision.CONSUME_COUGH_HOLD_MUTE -> {
                app.connectionManager.setMuteFromClicker(true)
                true
            }
            ClickerDecision.CONSUME_COUGH_RELEASE_UNMUTE -> {
                app.connectionManager.setMuteFromClicker(false)
                true
            }
            ClickerDecision.TRIGGER_TOGGLE_SHORTCUT -> {
                app.connectionManager.toggleMuteFromClicker()
                true
            }
            ClickerDecision.TRIGGER_EXIT_SHORTCUT -> {
                FloatingHudForegroundService.startService(this, FloatingHudForegroundService.ACTION_STOP)
                true
            }
            ClickerDecision.CONSUME_NOOP -> true
            ClickerDecision.PASS_THROUGH -> false
        }

        if (testerMode.get() && event.repeatCount == 0) {
            val label = when (decision) {
                ClickerDecision.CONSUME_TOGGLE -> "Matched Mute Button -> Toggle Mute"
                ClickerDecision.CONSUME_COUGH_HOLD_MUTE -> "Cough Hold Press -> Muted"
                ClickerDecision.CONSUME_COUGH_RELEASE_UNMUTE -> "Cough Hold Release -> Unmuted"
                ClickerDecision.TRIGGER_TOGGLE_SHORTCUT -> "Shortcut -> Toggle Mute"
                ClickerDecision.TRIGGER_EXIT_SHORTCUT -> "Shortcut -> Stop HUD"
                ClickerDecision.CONSUME_NOOP -> "Consumed ($actionLabel / debounce)"
                ClickerDecision.PASS_THROUGH -> if (!cfg.enablePointerIntercept) {
                    "Passed Through (Pointer Intercept OFF)"
                } else {
                    "Passed Through to Slide App"
                }
            }
            val diag = CapturedKeyEvent(
                seq = eventSeq.incrementAndGet(),
                keyCode = event.keyCode,
                keyCodeName = keyName,
                displayName = ClickerMuteController.friendlyKeyLabel(keyName),
                scanCode = event.scanCode,
                deviceName = deviceName,
                action = actionLabel,
                decisionLabel = label,
                consumed = consumed,
                timestampMs = System.currentTimeMillis()
            )
            _lastCapturedKey.value = diag
            appendTesterEvent(diag)
        }

        return if (consumed) true else super.onKeyEvent(event)
    }

    private fun isNavigationOnlyKey(keyCode: Int): Boolean {
        return keyCode == KeyEvent.KEYCODE_HOME ||
            keyCode == KeyEvent.KEYCODE_POWER ||
            keyCode == KeyEvent.KEYCODE_BACK
    }

    companion object {
        private val eventSeq = AtomicLong(0L)
        val captureNextKeyMode = AtomicBoolean(false)
        val testerMode = AtomicBoolean(false)

        private val _serviceActive = MutableStateFlow(false)
        val serviceActive: StateFlow<Boolean> = _serviceActive.asStateFlow()

        private val _lastCapturedKey = MutableStateFlow<CapturedKeyEvent?>(null)
        val lastCapturedKey: StateFlow<CapturedKeyEvent?> = _lastCapturedKey.asStateFlow()

        private val _testerEvents = MutableStateFlow<List<CapturedKeyEvent>>(emptyList())
        val testerEvents: StateFlow<List<CapturedKeyEvent>> = _testerEvents.asStateFlow()

        fun clearTesterEvents() {
            _testerEvents.value = emptyList()
        }

        fun recordUiCapturedEvent(event: CapturedKeyEvent) {
            _lastCapturedKey.value = event
            appendTesterEvent(event)
        }

        private fun appendTesterEvent(ev: CapturedKeyEvent) {
            val current = _testerEvents.value
            val updated = (listOf(ev) + current).take(12)
            _testerEvents.value = updated
        }

        fun isServiceEnabled(context: Context): Boolean {
            if (_serviceActive.value) return true
            val enabled = Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            ).orEmpty()
            val fullId = "${context.packageName}/${ClickerAccessibilityService::class.java.name}"
            val shortId = "${context.packageName}/.service.ClickerAccessibilityService"
            return enabled.contains(fullId, ignoreCase = true) ||
                enabled.contains(shortId, ignoreCase = true)
        }
    }
}
