package com.saabithjiffry.presentersync.remote.ui.screens

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.provider.Settings
import android.view.KeyEvent
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.HelpOutline
import androidx.compose.material.icons.filled.Checklist
import androidx.compose.material.icons.filled.Devices
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Keyboard
import androidx.compose.material.icons.filled.Layers
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MicOff
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.TabRowDefaults
import androidx.compose.material3.TabRowDefaults.tabIndicatorOffset
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.saabithjiffry.presentersync.remote.PresenterSyncRemoteApp
import com.saabithjiffry.presentersync.remote.config.AppConstants
import com.saabithjiffry.presentersync.remote.config.DeepLinkParser
import com.saabithjiffry.presentersync.remote.config.DeviceProfileMode
import com.saabithjiffry.presentersync.remote.config.NetworkMode
import com.saabithjiffry.presentersync.remote.config.QuickNudgePresetHelper
import com.saabithjiffry.presentersync.remote.config.RemoteConfig
import com.saabithjiffry.presentersync.remote.config.ResolvedFormFactor
import com.saabithjiffry.presentersync.remote.config.rememberFormFactor
import com.saabithjiffry.presentersync.remote.input.CapturedKeyEvent
import com.saabithjiffry.presentersync.remote.input.ClickerDecision
import com.saabithjiffry.presentersync.remote.input.ClickerMuteController
import com.saabithjiffry.presentersync.remote.input.InAppKeyMonitor
import com.saabithjiffry.presentersync.remote.input.KeyAction
import com.saabithjiffry.presentersync.remote.network.ConnStatus
import com.saabithjiffry.presentersync.remote.network.ConnectionUiState
import com.saabithjiffry.presentersync.remote.service.FloatingHudForegroundService
import com.saabithjiffry.presentersync.remote.ui.theme.CompactExplorerButtonPadding
import com.saabithjiffry.presentersync.remote.ui.theme.ExplorerCard
import com.saabithjiffry.presentersync.remote.ui.theme.PresenterSyncTheme
import com.saabithjiffry.presentersync.remote.ui.theme.ResponsiveExplorerActionRow
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

internal const val STOP_RECORD_CONFIRM_WINDOW_MS = 3000L

private inline fun directorRunWithCooldown(lastTapMs: LongArray, cooldownMs: Long = 200L, block: () -> Unit) {
    val now = SystemClock.elapsedRealtime()
    if (now - lastTapMs[0] < cooldownMs) return
    lastTapMs[0] = now
    block()
}

internal data class StopRecordTapResult(
    val shouldExecuteStop: Boolean,
    val nextPendingUntilMs: Long
)

internal fun evaluateStopRecordTap(
    isRecording: Boolean,
    confirmEnabled: Boolean,
    pendingUntilMs: Long,
    nowMs: Long,
    windowMs: Long = STOP_RECORD_CONFIRM_WINDOW_MS
): StopRecordTapResult {
    if (!isRecording || !confirmEnabled) {
        return StopRecordTapResult(shouldExecuteStop = true, nextPendingUntilMs = 0L)
    }
    return if (pendingUntilMs > 0L && nowMs < pendingUntilMs) {
        StopRecordTapResult(shouldExecuteStop = true, nextPendingUntilMs = 0L)
    } else {
        StopRecordTapResult(shouldExecuteStop = false, nextPendingUntilMs = nowMs + windowMs)
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun DirectorDeckAndTimerCard(
    conn: ConnectionUiState,
    formFactor: ResolvedFormFactor,
    onPauseRecord: () -> Unit,
    onSplitRecord: () -> Unit,
    onToggleStandby: () -> Unit,
    onSwitchScene: (String) -> Unit,
    onTimerCommand: (String, Int) -> Unit,
    onSendNudge: (String) -> Unit,
    onToggleRecord: () -> Unit = {},
    confirmBeforeStopRecording: Boolean = true,
    onEmergencyPanic: () -> Unit = {},
    onSetPreviewScene: (String) -> Unit = {},
    onAudioHandoff: (String) -> Unit = {},
    onSaveReplayBuffer: () -> Unit = {},
    onAddBookmark: (String) -> Unit = {},
    onSessionReset: () -> Unit = {},
    onSendPresenterSignal: (String) -> Unit = {},
    onAckNudge: (String) -> Unit = {},
    onResetActiveScene: () -> Unit = {},
    quickNudgePresets: String = ""
) {
    val isDirectObsFallback = conn.usingDirectObsFallback ||
        conn.channelType == com.saabithjiffry.presentersync.remote.network.ChannelType.DIRECT_OBS
    val bridgeOnlyEnabled = conn.usingBridge
    if (!conn.connected || (!conn.usingBridge && !conn.usingRelayFallback && !isDirectObsFallback)) return

    var nudgeDraft by remember { mutableStateOf("") }
    var customMinDraft by remember { mutableStateOf("12") }
    var pendingStopRecordUntilMs by remember { mutableStateOf(0L) }
    val deckTapGate = remember { LongArray(1) }
    val isRecording = conn.recState != 0
    val isConfirmingStop = isRecording && pendingStopRecordUntilMs > 0L

    LaunchedEffect(pendingStopRecordUntilMs, conn.recState) {
        if (conn.recState == 0) {
            pendingStopRecordUntilMs = 0L
        } else if (pendingStopRecordUntilMs > 0L) {
            val remaining = (pendingStopRecordUntilMs - System.currentTimeMillis()).coerceAtLeast(0L)
            delay(remaining)
            pendingStopRecordUntilMs = 0L
        }
    }
    val timerWarningAmber = conn.timerState == "running" && conn.timerRemainingSec in 1..120
    val timerOvertimeRed = conn.timerState == "overtime" || (conn.timerState == "running" && conn.timerRemainingSec <= 0)
    val timerColor = when {
        timerOvertimeRed -> Color(0xFFDC2626)
        timerWarningAmber -> Color(0xFFD97706)
        conn.timerState == "running" -> Color(0xFF10B981)
        else -> MaterialTheme.colorScheme.onSurface
    }

    ExplorerCard(contentPadding = formFactor.cardPaddingDp) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Text(
                            text = "OBS Director & Presenter Timer",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold
                        )
                        if (isDirectObsFallback) {
                            Surface(
                                shape = RoundedCornerShape(6.dp),
                                color = Color(0xFFD97706).copy(alpha = 0.16f),
                                border = BorderStroke(1.dp, Color(0xFFD97706).copy(alpha = 0.5f))
                            ) {
                                Text(
                                    text = "DIRECT OBS :4455",
                                    modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                                    style = MaterialTheme.typography.labelSmall,
                                    fontWeight = FontWeight.Bold,
                                    color = Color(0xFFD97706)
                                )
                            }
                        }
                    }
                    Text(
                        text = if (conn.isStandby) {
                            "Standby Active (${conn.standbyScene}) • Mic Muted"
                        } else {
                            "Live Scene: ${conn.activeScene}"
                        },
                        style = MaterialTheme.typography.bodySmall,
                        color = if (conn.isStandby) Color(0xFFD97706) else MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Button(
                    onClick = { directorRunWithCooldown(deckTapGate) { onToggleStandby() } },
                    contentPadding = CompactExplorerButtonPadding,
                    colors = ButtonDefaults.buttonColors(
                        containerColor = if (conn.isStandby) Color(0xFFD97706) else MaterialTheme.colorScheme.secondary
                    )
                ) {
                    Text(if (conn.isStandby) "Exit BRB" else "Standby BRB", maxLines = 1, softWrap = false)
                }
            }

            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Button(
                    onClick = { directorRunWithCooldown(deckTapGate) { onEmergencyPanic() } },
                    contentPadding = CompactExplorerButtonPadding,
                    colors = ButtonDefaults.buttonColors(
                        containerColor = if (conn.isPanic) Color(0xFF991B1B) else Color(0xFF7F1D1D)
                    )
                ) {
                    Text(if (conn.isPanic) "PANIC ON" else "PANIC", maxLines = 1, softWrap = false)
                }
                OutlinedButton(
                    onClick = { directorRunWithCooldown(deckTapGate) { onResetActiveScene() } },
                    contentPadding = CompactExplorerButtonPadding
                ) {
                    Text("↺ Reset Scene", maxLines = 1, softWrap = false)
                }
                OutlinedButton(
                    onClick = { directorRunWithCooldown(deckTapGate) { onSaveReplayBuffer() } },
                    enabled = bridgeOnlyEnabled,
                    contentPadding = CompactExplorerButtonPadding
                ) {
                    Text("Replay", maxLines = 1, softWrap = false)
                }
                OutlinedButton(
                    onClick = { directorRunWithCooldown(deckTapGate) { onAddBookmark("Marked from Android") } },
                    enabled = bridgeOnlyEnabled,
                    contentPadding = CompactExplorerButtonPadding
                ) {
                    Text("Bookmark", maxLines = 1, softWrap = false)
                }
                OutlinedButton(
                    onClick = { directorRunWithCooldown(deckTapGate) { onAudioHandoff("solo_a") } },
                    enabled = bridgeOnlyEnabled,
                    contentPadding = CompactExplorerButtonPadding
                ) {
                    Text("Mic -> Host", maxLines = 1, softWrap = false)
                }
                OutlinedButton(
                    onClick = { directorRunWithCooldown(deckTapGate) { onAudioHandoff("solo_b") } },
                    enabled = bridgeOnlyEnabled,
                    contentPadding = CompactExplorerButtonPadding
                ) {
                    Text("Mic -> Remote", maxLines = 1, softWrap = false)
                }
                OutlinedButton(
                    onClick = { directorRunWithCooldown(deckTapGate) { onAudioHandoff("both") } },
                    enabled = bridgeOnlyEnabled,
                    contentPadding = CompactExplorerButtonPadding
                ) {
                    Text("Mic -> Both", maxLines = 1, softWrap = false)
                }
                OutlinedButton(
                    onClick = { directorRunWithCooldown(deckTapGate) { onSessionReset() } },
                    enabled = bridgeOnlyEnabled,
                    contentPadding = CompactExplorerButtonPadding
                ) {
                    Text("Reset Session", maxLines = 1, softWrap = false)
                }
            }

            Button(
                onClick = {
                    val res = evaluateStopRecordTap(
                        isRecording = isRecording,
                        confirmEnabled = confirmBeforeStopRecording,
                        pendingUntilMs = pendingStopRecordUntilMs,
                        nowMs = System.currentTimeMillis()
                    )
                    pendingStopRecordUntilMs = res.nextPendingUntilMs
                    if (res.shouldExecuteStop) {
                        onToggleRecord()
                    }
                },
                contentPadding = CompactExplorerButtonPadding,
                colors = ButtonDefaults.buttonColors(
                    containerColor = when {
                        isConfirmingStop -> Color(0xFFD97706)
                        isRecording -> Color(0xFFDC2626)
                        else -> MaterialTheme.colorScheme.primary
                    }
                ),
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(
                    when {
                        isConfirmingStop -> "Tap Again to Stop (3s)"
                        isRecording -> "Stop Recording"
                        else -> "Start Recording"
                    },
                    maxLines = 1,
                    softWrap = false,
                    overflow = TextOverflow.Ellipsis
                )
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                OutlinedButton(
                    onClick = { directorRunWithCooldown(deckTapGate) { onPauseRecord() } },
                    contentPadding = CompactExplorerButtonPadding,
                    modifier = Modifier.weight(1f)
                ) {
                    Text(
                        if (conn.recState == 2) "Resume Rec" else "Pause Rec",
                        maxLines = 1,
                        softWrap = false,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                OutlinedButton(
                    onClick = { directorRunWithCooldown(deckTapGate) { onSplitRecord() } },
                    contentPadding = CompactExplorerButtonPadding,
                    modifier = Modifier.weight(1f)
                ) {
                    Text("Split Chapter", maxLines = 1, softWrap = false, overflow = TextOverflow.Ellipsis)
                }
            }

            if (conn.scenes.isNotEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        text = "Switch OBS Scene",
                        style = MaterialTheme.typography.labelLarge,
                        fontWeight = FontWeight.Medium
                    )
                    FlowRow(
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        conn.scenes.forEach { sceneName ->
                            val selected = sceneName == conn.activeScene
                            FilterChip(
                                selected = selected,
                                onClick = { directorRunWithCooldown(deckTapGate) { onSwitchScene(sceneName) } },
                                label = { Text(sceneName, maxLines = 1, softWrap = false) }
                            )
                        }
                    }
                    if (conn.studioModeActive && bridgeOnlyEnabled) {
                        Text(
                            text = "Set Preview Scene (Studio Mode)",
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(top = 6.dp)
                        )
                        FlowRow(
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            conn.scenes.forEach { sceneName ->
                                val selected = sceneName == conn.previewScene
                                FilterChip(
                                    selected = selected,
                                    onClick = { directorRunWithCooldown(deckTapGate) { onSetPreviewScene(sceneName) } },
                                    label = { Text(sceneName, maxLines = 1, softWrap = false) }
                                )
                            }
                        }
                    }
                }
            }

            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text(
                        text = "Presenter Countdown",
                        style = MaterialTheme.typography.labelLarge,
                        fontWeight = FontWeight.Medium
                    )
                    Text(
                        text = conn.timerState.uppercase(),
                        style = MaterialTheme.typography.labelSmall,
                        color = timerColor
                    )
                }
                Text(
                    text = conn.formattedCountdown(),
                    style = MaterialTheme.typography.headlineMedium,
                    fontWeight = FontWeight.Bold,
                    color = timerColor
                )
            }

            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                listOf(5, 10, 15, 45).forEach { mins ->
                    FilterChip(
                        selected = conn.timerPresetSec == mins * 60 && conn.timerState != "stopped",
                        onClick = { directorRunWithCooldown(deckTapGate) { onTimerCommand("timer_start", mins * 60) } },
                        label = { Text("${mins}m") }
                    )
                }
                OutlinedButton(
                    onClick = {
                        directorRunWithCooldown(deckTapGate) {
                            if (conn.timerState == "stopped") {
                                val sec = (customMinDraft.trim().toIntOrNull()?.coerceIn(1, 240) ?: 10) * 60
                                onTimerCommand("timer_start", sec)
                            } else {
                                onTimerCommand("timer_pause", 0)
                            }
                        }
                    },
                    contentPadding = CompactExplorerButtonPadding
                ) {
                    Text(
                        when (conn.timerState) {
                            "running", "overtime" -> "Pause"
                            "paused" -> "Resume"
                            else -> "Start"
                        }
                    )
                }
                OutlinedButton(
                    onClick = { directorRunWithCooldown(deckTapGate) { onTimerCommand("timer_reset", conn.timerPresetSec) } },
                    contentPadding = CompactExplorerButtonPadding
                ) {
                    Text("Reset")
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                OutlinedTextField(
                    value = customMinDraft,
                    onValueChange = { v -> customMinDraft = v.filter { ch -> ch.isDigit() }.take(3) },
                    label = { Text("Custom (min)") },
                    singleLine = true,
                    modifier = Modifier.weight(1f)
                )
                OutlinedButton(
                    onClick = {
                        directorRunWithCooldown(deckTapGate) {
                            val sec = (customMinDraft.trim().toIntOrNull()?.coerceIn(1, 240) ?: 10) * 60
                            onTimerCommand("timer_start", sec)
                        }
                    },
                    contentPadding = CompactExplorerButtonPadding
                ) {
                    Text("Set & Go")
                }
            }

            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

            Text(
                text = "Silent Stage Nudge",
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.Medium
            )
            if (conn.lastNudgeMessage.isNotBlank()) {
                Surface(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(8.dp),
                    color = Color(0xFFF59E0B).copy(alpha = 0.14f),
                    border = BorderStroke(1.dp, Color(0xFFF59E0B).copy(alpha = 0.45f))
                ) {
                    Text(
                        text = "${conn.lastNudgeSender.ifBlank { "Stage" }}: ${conn.lastNudgeMessage}",
                        style = MaterialTheme.typography.bodySmall,
                        fontWeight = FontWeight.Medium,
                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp)
                    )
                }
            }
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                QuickNudgePresetHelper.resolve(quickNudgePresets, conn.quickNudges, 6).forEach { quick ->
                    OutlinedButton(
                        onClick = { directorRunWithCooldown(deckTapGate) { onSendNudge(quick) } },
                        contentPadding = CompactExplorerButtonPadding
                    ) {
                        Text(quick, maxLines = 1, softWrap = false)
                    }
                }
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                OutlinedTextField(
                    value = nudgeDraft,
                    onValueChange = { nudgeDraft = it.take(140) },
                    label = { Text("Send whisper toast...") },
                    singleLine = true,
                    modifier = Modifier.weight(1f)
                )
                Button(
                    onClick = {
                        directorRunWithCooldown(deckTapGate) {
                            val clean = nudgeDraft.trim()
                            if (clean.isNotEmpty()) {
                                onSendNudge(clean)
                                nudgeDraft = ""
                            }
                        }
                    },
                    contentPadding = CompactExplorerButtonPadding
                ) {
                    Text("Send")
                }
            }

            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Button(
                    onClick = { directorRunWithCooldown(deckTapGate) { onAckNudge(conn.lastNudgeId.ifBlank { "latest" }) } },
                    enabled = bridgeOnlyEnabled,
                    contentPadding = CompactExplorerButtonPadding
                ) {
                    Text("Got It ✓", maxLines = 1, softWrap = false)
                }
                OutlinedButton(
                    onClick = { directorRunWithCooldown(deckTapGate) { onSendPresenterSignal("Need Assistance") } },
                    enabled = bridgeOnlyEnabled,
                    contentPadding = CompactExplorerButtonPadding
                ) {
                    Text("Signal Host", maxLines = 1, softWrap = false)
                }
            }
        }
    }
}

