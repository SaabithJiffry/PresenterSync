package com.saabithjiffry.presentersync.remote.input

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.concurrent.atomic.AtomicBoolean

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
    val timestampMs: Long,
    val isCtrl: Boolean = false,
    val isAlt: Boolean = false,
    val isShift: Boolean = false,
    val shortcutString: String = keyCodeName.removePrefix("KEYCODE_")
)

/**
 * In-memory state holder for focused-window key capture and live key tester
 * events (Play Protect-safe: requires zero Accessibility permissions).
 */
object InAppKeyMonitor {
    val captureNextKeyMode = AtomicBoolean(false)
    val testerMode = AtomicBoolean(false)

    private val _lastCapturedKey = MutableStateFlow<CapturedKeyEvent?>(null)
    val lastCapturedKey: StateFlow<CapturedKeyEvent?> = _lastCapturedKey.asStateFlow()

    private val _testerEvents = MutableStateFlow<List<CapturedKeyEvent>>(emptyList())
    val testerEvents: StateFlow<List<CapturedKeyEvent>> = _testerEvents.asStateFlow()

    fun clearTesterEvents() {
        _testerEvents.value = emptyList()
    }

    fun recordUiCapturedEvent(event: CapturedKeyEvent) {
        _lastCapturedKey.value = event
        _testerEvents.value = (listOf(event) + _testerEvents.value).take(12)
    }
}
