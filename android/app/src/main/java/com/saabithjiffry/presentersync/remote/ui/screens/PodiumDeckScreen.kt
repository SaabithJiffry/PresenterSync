package com.saabithjiffry.presentersync.remote.ui.screens

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.os.SystemClock
import android.view.WindowManager
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.basicMarquee
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.SecureFlagPolicy
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.saabithjiffry.presentersync.remote.PresenterSyncRemoteApp
import com.saabithjiffry.presentersync.remote.config.QuickNudgePresetHelper
import com.saabithjiffry.presentersync.remote.network.ConnectionUiState

private val PodiumOledBlack = Color(0xFF000000)
private val PodiumOledCard = Color(0xFF0D0D0F)
private val PodiumOledBorder = Color(0xFF26262A)
private val PodiumLiveEmerald = Color(0xFF107C10)
private val PodiumMutedCrimson = Color(0xFFC42B1C)
private val PodiumAmberAlert = Color(0xFFF59E0B)

private inline fun podiumRunWithCooldown(lastTapMs: LongArray, cooldownMs: Long, block: () -> Unit) {
    val now = SystemClock.elapsedRealtime()
    if (now - lastTapMs[0] < cooldownMs) return
    lastTapMs[0] = now
    block()
}

private fun Context.findHostActivity(): Activity? {
    var ctx: Context = this
    while (ctx is ContextWrapper) {
        if (ctx is Activity) return ctx
        ctx = ctx.baseContext
    }
    return null
}

internal data class PodiumSceneChipModel(
    val name: String,
    val isLive: Boolean,
    val isPreview: Boolean
)

internal fun buildPodiumSceneChipModels(
    scenes: List<String>,
    activeScene: String,
    previewScene: String,
    studioModeActive: Boolean
): List<PodiumSceneChipModel> {
    val seen = LinkedHashSet<String>()
    val result = ArrayList<PodiumSceneChipModel>(scenes.size)
    for (raw in scenes) {
        val scene = raw.trim()
        if (scene.isEmpty() || !seen.add(scene)) continue
        result.add(
            PodiumSceneChipModel(
                name = scene,
                isLive = scene == activeScene,
                isPreview = studioModeActive && scene == previewScene
            )
        )
    }
    return result
}

internal fun resolvePodiumScenePickerSecurePolicy(hideFromScreenCapture: Boolean): SecureFlagPolicy =
    if (hideFromScreenCapture) SecureFlagPolicy.SecureOn else SecureFlagPolicy.Inherit

@Composable
fun PodiumDeckScreen(
    app: PresenterSyncRemoteApp,
    onExitPodium: () -> Unit
) {
    val conn by app.connectionManager.uiState.collectAsStateWithLifecycle()
    val cfg by app.configStore.config.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val haptic = LocalHapticFeedback.current
    val muteTapGate = remember { LongArray(1) }
    val deckTapGate = remember { LongArray(1) }
    var showScenePickerDialog by rememberSaveable { mutableStateOf(false) }

    val canControl = conn.connected && !conn.isTallyOnly
    val canDeckControl = canControl && conn.usingBridge
    val canRelayOrBridge = canControl && (conn.usingBridge || conn.usingRelayFallback)

    BackHandler(onBack = onExitPodium)

    DisposableEffect(lifecycleOwner, cfg.keepScreenOn) {
        val window = context.findHostActivity()?.window
        window?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        app.setPodiumForegroundActive(
            lifecycleOwner.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)
        )
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_RESUME -> app.setPodiumForegroundActive(true)
                Lifecycle.Event.ON_PAUSE,
                Lifecycle.Event.ON_STOP -> app.setPodiumForegroundActive(false)
                else -> Unit
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
            app.setPodiumForegroundActive(false)
            if (!cfg.keepScreenOn) {
                window?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }
        }
    }

    if (showScenePickerDialog) {
        PodiumScenePickerDialog(
            conn = conn,
            canControl = canControl,
            hideFromScreenCapture = cfg.hideFromScreenCapture,
            onSelectScene = { scene ->
                podiumRunWithCooldown(deckTapGate, 200L) {
                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                    app.connectionManager.sendSwitchScene(scene, "podium")
                    showScenePickerDialog = false
                }
            },
            onDismiss = { showScenePickerDialog = false }
        )
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(PodiumOledBlack)
            .safeDrawingPadding()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        PodiumTopBar(conn = conn, onExitPodium = onExitPodium)

        Column(
            modifier = Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            PodiumMuteTouchSurface(
                conn = conn,
                canControl = !conn.connected || !conn.isTallyOnly,
                onToggleMute = {
                    if (!conn.isTallyOnly) {
                        podiumRunWithCooldown(muteTapGate, 80L) { app.connectionManager.toggleMuteFromHud() }
                    }
                }
            )

            PodiumActiveSceneCard(
                conn = conn,
                canControl = canControl,
                onSwitchScene = { scene ->
                    podiumRunWithCooldown(deckTapGate, 200L) {
                        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                        app.connectionManager.sendSwitchScene(scene, "podium")
                    }
                },
                onOpenAllScenes = { showScenePickerDialog = true }
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Button(
                    onClick = { podiumRunWithCooldown(deckTapGate, 200L) { app.connectionManager.sendTransitionScene("podium") } },
                    enabled = canControl,
                    modifier = Modifier
                        .weight(1f)
                        .height(52.dp),
                    shape = RoundedCornerShape(12.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = Color(0xFF0067C0),
                        contentColor = Color.White
                    )
                ) {
                    Text(
                        text = "⇄ OBS Transition",
                        fontWeight = FontWeight.Bold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                OutlinedButton(
                    onClick = { podiumRunWithCooldown(deckTapGate, 250L) { app.connectionManager.sendResetActiveScene("podium") } },
                    enabled = canControl,
                    modifier = Modifier.height(52.dp),
                    shape = RoundedCornerShape(12.dp),
                    border = BorderStroke(1.dp, Color(0xFF38BDF8).copy(alpha = 0.65f)),
                    colors = ButtonDefaults.outlinedButtonColors(contentColor = Color(0xFF38BDF8))
                ) {
                    Text("↺ Reset Scene", fontWeight = FontWeight.Bold, maxLines = 1, softWrap = false)
                }
            }

            PodiumSlidesAndNotesCard(
                conn = conn,
                canControlSlides = canDeckControl,
                onPrevSlide = { podiumRunWithCooldown(deckTapGate, 200L) { app.connectionManager.sendPptPrev("podium") } },
                onNextSlide = { podiumRunWithCooldown(deckTapGate, 200L) { app.connectionManager.sendPptNext("podium") } },
                onStartSlideshow = { podiumRunWithCooldown(deckTapGate, 200L) { app.connectionManager.sendStartSlideshow("podium") } }
            )

            PodiumTimerAndStandbyCard(
                conn = conn,
                canControl = canControl,
                onToggleStandby = { podiumRunWithCooldown(deckTapGate, 200L) { app.connectionManager.sendToggleStandby("podium") } },
                onTogglePanic = { podiumRunWithCooldown(deckTapGate, 200L) { app.connectionManager.sendEmergencyPanic(null, "podium") } },
                onTimerCommand = { action, sec -> podiumRunWithCooldown(deckTapGate, 200L) { app.connectionManager.sendTimerCommand(action, sec, "podium") } }
            )

            PodiumQuickNudgeCard(
                conn = conn,
                canRelayOrBridge = canRelayOrBridge,
                quickNudgePresets = cfg.quickNudgePresets,
                onSendNudge = { nudge -> podiumRunWithCooldown(deckTapGate, 200L) { app.connectionManager.sendStageNudge(nudge) } },
                onSignalHost = { podiumRunWithCooldown(deckTapGate, 200L) { app.connectionManager.sendPresenterSignal("Need Assistance", "sticky") } },
                onAckNudge = {
                    podiumRunWithCooldown(deckTapGate, 200L) {
                        app.connectionManager.sendNudgeAck(conn.lastNudgeId.ifBlank { "latest" })
                    }
                }
            )
        }
    }
}

@Composable
private fun PodiumTopBar(
    conn: ConnectionUiState,
    onExitPodium: () -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    text = "PODIUM DECK",
                    color = Color(0xFF94A3B8),
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = 1.2.sp
                )
                if (conn.connected && conn.isTallyOnly) {
                    Surface(
                        shape = RoundedCornerShape(4.dp),
                        color = PodiumAmberAlert.copy(alpha = 0.2f),
                        border = BorderStroke(1.dp, PodiumAmberAlert.copy(alpha = 0.6f))
                    ) {
                        Text(
                            text = "TALLY-ONLY",
                            color = PodiumAmberAlert,
                            fontSize = 9.5.sp,
                            fontWeight = FontWeight.Bold,
                            modifier = Modifier.padding(horizontal = 6.dp, vertical = 1.dp)
                        )
                    }
                }
            }
            val statusSummary = buildString {
                append(if (conn.connected) conn.transportName else "Disconnected")
                val recPrefix = if (conn.recSourceTag.isNotBlank()) "${conn.recSourceTag.uppercase()} " else ""
                if (conn.recState == 1) append("  •  ● ${recPrefix}REC ${conn.formattedRecElapsed()}")
                else if (conn.recState == 2) append("  •  ❚❚ ${recPrefix}PAUSED ${conn.formattedRecElapsed()}")
                if (conn.unreadChatCount > 0) append("  •  💬 ${conn.unreadChatCount}")
                if (conn.isStandby) append("  •  BRB ON")
            }
            Text(
                text = statusSummary,
                color = if (conn.recState == 1) Color(0xFFFCA5A5) else Color(0xFFE2E8F0),
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
        Spacer(Modifier.width(8.dp))
        OutlinedButton(
            onClick = onExitPodium,
            border = BorderStroke(1.dp, Color(0xFF475569)),
            colors = ButtonDefaults.outlinedButtonColors(contentColor = Color.White)
        ) {
            Text("Exit Podium", fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
private fun PodiumMuteTouchSurface(
    conn: ConnectionUiState,
    canControl: Boolean,
    onToggleMute: () -> Unit
) {
    val muteCardBg = when {
        !conn.connected -> Color(0xFF1F2937)
        conn.isMuted -> PodiumMutedCrimson
        else -> PodiumLiveEmerald
    }
    val muteBorder = if (conn.connected && conn.isMuted && conn.voiceWhileMuted) {
        PodiumAmberAlert
    } else {
        Color.White.copy(alpha = 0.22f)
    }

    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .height(148.dp)
            .clip(RoundedCornerShape(18.dp))
            .clickable(enabled = canControl, onClick = onToggleMute),
        shape = RoundedCornerShape(18.dp),
        color = muteCardBg,
        border = BorderStroke(2.dp, muteBorder)
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            Text(
                text = when {
                    !conn.connected -> "OFFLINE"
                    conn.isMuted -> "MIC MUTED"
                    else -> "MIC LIVE"
                },
                color = Color.White,
                fontSize = 34.sp,
                fontWeight = FontWeight.ExtraBold,
                letterSpacing = 1.5.sp
            )
            Spacer(Modifier.height(4.dp))
            Text(
                text = when {
                    !conn.connected -> "Tap to attempt toggle / reconnect from Dashboard"
                    conn.isTallyOnly -> "Read-Only Tally mode (controls locked)"
                    conn.isMuted && conn.voiceWhileMuted -> "⚠ MIC SIGNAL DETECTED WHILE MUTED — Tap to UNMUTE"
                    conn.isMuted -> "Tap anywhere here to UNMUTE"
                    else -> "Tap anywhere here to MUTE"
                },
                color = Color.White.copy(alpha = 0.90f),
                fontSize = 13.sp,
                fontWeight = FontWeight.Medium
            )
        }
    }
}

@Composable
private fun PodiumSlidesAndNotesCard(
    conn: ConnectionUiState,
    canControlSlides: Boolean,
    onPrevSlide: () -> Unit,
    onNextSlide: () -> Unit,
    onStartSlideshow: () -> Unit
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(14.dp),
        color = PodiumOledCard,
        border = BorderStroke(1.dp, PodiumOledBorder)
    ) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                val slideLabel = if (conn.slideIndex > 0) {
                    "Slide ${conn.slideIndex}" + (if (conn.slideTotal > 0) " / ${conn.slideTotal}" else "")
                } else {
                    "Slideshow"
                }
                Text(
                    text = slideLabel,
                    color = Color(0xFF60CDFF),
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Bold
                )
                if (conn.slideTitle.isNotBlank()) {
                    Text(
                        text = conn.slideTitle,
                        color = Color(0xFFCBD5E1),
                        fontSize = 13.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.padding(start = 10.dp)
                    )
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                FilledTonalButton(
                    onClick = onPrevSlide,
                    enabled = canControlSlides,
                    modifier = Modifier.weight(1f).height(48.dp)
                ) {
                    Text("◀ Prev", fontWeight = FontWeight.Bold)
                }
                FilledTonalButton(
                    onClick = onNextSlide,
                    enabled = canControlSlides,
                    modifier = Modifier.weight(1f).height(48.dp)
                ) {
                    Text("Next ▶", fontWeight = FontWeight.Bold)
                }
            }

            OutlinedButton(
                onClick = onStartSlideshow,
                enabled = canControlSlides,
                modifier = Modifier.fillMaxWidth(),
                border = BorderStroke(1.dp, PodiumOledBorder),
                colors = ButtonDefaults.outlinedButtonColors(contentColor = Color(0xFFE2E8F0))
            ) {
                Text("Start Slideshow (F5)", fontWeight = FontWeight.SemiBold)
            }

            Surface(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 76.dp, max = 160.dp),
                shape = RoundedCornerShape(10.dp),
                color = Color(0xFF050507),
                border = BorderStroke(1.dp, Color(0xFF1E293B))
            ) {
                val notesScroll = rememberScrollState()
                Text(
                    text = conn.slideNotes.ifBlank { "No speaker notes for current slide." },
                    color = if (conn.slideNotes.isBlank()) Color(0xFF64748B) else Color(0xFFF1F5F9),
                    fontSize = 14.sp,
                    lineHeight = 20.sp,
                    modifier = Modifier
                        .verticalScroll(notesScroll)
                        .padding(10.dp)
                )
            }
        }
    }
}

@Composable
private fun PodiumTimerAndStandbyCard(
    conn: ConnectionUiState,
    canControl: Boolean,
    onToggleStandby: () -> Unit,
    onTogglePanic: () -> Unit,
    onTimerCommand: (String, Int) -> Unit
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(14.dp),
        color = PodiumOledCard,
        border = BorderStroke(1.dp, PodiumOledBorder)
    ) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                val timerColor = when (conn.timerState) {
                    "overtime" -> Color(0xFFEF4444)
                    "running" -> Color(0xFF34D399)
                    "paused" -> Color(0xFFFBBF24)
                    else -> Color(0xFF94A3B8)
                }
                Text(
                    text = "Timer: ${conn.formattedCountdown()} (${conn.timerState})",
                    color = timerColor,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.weight(1f)
                )
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Button(
                        onClick = onToggleStandby,
                        enabled = canControl,
                        colors = ButtonDefaults.buttonColors(
                            containerColor = if (conn.isStandby) PodiumAmberAlert else Color(0xFF1E293B),
                            contentColor = Color.White
                        )
                    ) {
                        Text(if (conn.isStandby) "Exit BRB" else "BRB", fontWeight = FontWeight.Bold)
                    }
                    Button(
                        onClick = onTogglePanic,
                        enabled = canControl,
                        colors = ButtonDefaults.buttonColors(
                            containerColor = if (conn.isPanic) Color(0xFF991B1B) else Color(0xFF7F1D1D),
                            contentColor = Color.White
                        )
                    ) {
                        Text(if (conn.isPanic) "PANIC ON" else "PANIC", fontWeight = FontWeight.Bold)
                    }
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                for ((lbl, sec) in listOf("5m" to 300, "10m" to 600, "15m" to 900, "45m" to 2700)) {
                    OutlinedButton(
                        onClick = { onTimerCommand("timer_start", sec) },
                        enabled = canControl,
                        modifier = Modifier.weight(1f),
                        border = BorderStroke(1.dp, PodiumOledBorder),
                        colors = ButtonDefaults.outlinedButtonColors(contentColor = Color.White)
                    ) {
                        Text(lbl, fontWeight = FontWeight.Bold, maxLines = 1, softWrap = false)
                    }
                }
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                OutlinedButton(
                    onClick = {
                        if (conn.timerState == "stopped") {
                            onTimerCommand("timer_start", conn.timerPresetSec.coerceAtLeast(60))
                        } else {
                            onTimerCommand("timer_pause", 0)
                        }
                    },
                    enabled = canControl,
                    modifier = Modifier.weight(1f),
                    border = BorderStroke(1.dp, PodiumOledBorder),
                    colors = ButtonDefaults.outlinedButtonColors(contentColor = Color.White)
                ) {
                    Text(
                        when (conn.timerState) {
                            "running", "overtime" -> "❚❚ Pause Timer"
                            "paused" -> "▶ Resume Timer"
                            else -> "▶ Start Timer"
                        },
                        fontWeight = FontWeight.Bold,
                        maxLines = 1,
                        softWrap = false
                    )
                }
                OutlinedButton(
                    onClick = { onTimerCommand("timer_reset", conn.timerPresetSec) },
                    enabled = canControl,
                    modifier = Modifier.weight(1f),
                    border = BorderStroke(1.dp, PodiumOledBorder),
                    colors = ButtonDefaults.outlinedButtonColors(contentColor = Color.White)
                ) {
                    Text("↺ Reset Timer", fontWeight = FontWeight.Bold, maxLines = 1, softWrap = false)
                }
            }
        }
    }
}

@Composable
private fun PodiumQuickNudgeCard(
    conn: ConnectionUiState,
    canRelayOrBridge: Boolean,
    quickNudgePresets: String = "",
    onSendNudge: (String) -> Unit,
    onSignalHost: () -> Unit = {},
    onAckNudge: () -> Unit = {}
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(14.dp),
        color = PodiumOledCard,
        border = BorderStroke(1.dp, PodiumOledBorder)
    ) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "Quick Stage Nudge",
                    color = Color(0xFF94A3B8),
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold
                )
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    FilledTonalButton(
                        onClick = onAckNudge,
                        enabled = conn.connected && conn.usingBridge
                    ) {
                        Text("Got It ✓", fontWeight = FontWeight.Bold)
                    }
                    OutlinedButton(
                        onClick = onSignalHost,
                        enabled = canRelayOrBridge && conn.usingBridge,
                        border = BorderStroke(1.dp, PodiumOledBorder),
                        colors = ButtonDefaults.outlinedButtonColors(contentColor = Color.White)
                    ) {
                        Text("Signal Host", fontWeight = FontWeight.SemiBold)
                    }
                }
            }
            if (conn.lastNudgeMessage.isNotBlank()) {
                Surface(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(8.dp),
                    color = PodiumAmberAlert.copy(alpha = 0.14f),
                    border = BorderStroke(1.dp, PodiumAmberAlert.copy(alpha = 0.45f))
                ) {
                    Text(
                        text = "${conn.lastNudgeSender.ifBlank { "Stage" }}: ${conn.lastNudgeMessage}",
                        color = Color(0xFFFDE68A),
                        fontSize = 13.sp,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp)
                    )
                }
            }
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                for (nudge in QuickNudgePresetHelper.resolve(quickNudgePresets, conn.quickNudges, 4)) {
                    FilledTonalButton(
                        onClick = { onSendNudge(nudge) },
                        enabled = canRelayOrBridge
                    ) {
                        Text(nudge, fontWeight = FontWeight.SemiBold)
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun PodiumActiveSceneCard(
    conn: ConnectionUiState,
    canControl: Boolean,
    onSwitchScene: (String) -> Unit,
    onOpenAllScenes: () -> Unit
) {
    val chips = remember(conn.scenes, conn.activeScene, conn.previewScene, conn.studioModeActive) {
        buildPodiumSceneChipModels(conn.scenes, conn.activeScene, conn.previewScene, conn.studioModeActive)
    }

    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(14.dp),
        color = PodiumOledCard,
        border = BorderStroke(1.dp, PodiumOledBorder)
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 14.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Text(
                        text = "ACTIVE PROGRAM SCENE",
                        color = Color(0xFF94A3B8),
                        fontSize = 10.5.sp,
                        fontWeight = FontWeight.Bold,
                        letterSpacing = 1.1.sp
                    )
                    Surface(
                        shape = RoundedCornerShape(4.dp),
                        color = Color(0xFF107C10).copy(alpha = 0.28f),
                        border = BorderStroke(1.dp, Color(0xFF34D399).copy(alpha = 0.65f))
                    ) {
                        Text(
                            text = "LIVE",
                            color = Color(0xFF34D399),
                            fontSize = 9.5.sp,
                            fontWeight = FontWeight.ExtraBold,
                            modifier = Modifier.padding(horizontal = 5.dp, vertical = 1.dp)
                        )
                    }
                    if (conn.studioModeActive && conn.previewScene.isNotBlank()) {
                        Surface(
                            shape = RoundedCornerShape(4.dp),
                            color = Color(0xFF0284C7).copy(alpha = 0.24f),
                            border = BorderStroke(1.dp, Color(0xFF38BDF8).copy(alpha = 0.65f))
                        ) {
                            Text(
                                text = "PREVIEW",
                                color = Color(0xFF38BDF8),
                                fontSize = 9.5.sp,
                                fontWeight = FontWeight.ExtraBold,
                                modifier = Modifier.padding(horizontal = 5.dp, vertical = 1.dp)
                            )
                        }
                    }
                }
                if (chips.isNotEmpty()) {
                    OutlinedButton(
                        onClick = onOpenAllScenes,
                        enabled = canControl,
                        modifier = Modifier.heightIn(min = 36.dp),
                        shape = RoundedCornerShape(8.dp),
                        border = BorderStroke(1.dp, Color(0xFF334155)),
                        colors = ButtonDefaults.outlinedButtonColors(contentColor = Color(0xFFE2E8F0))
                    ) {
                        Text("All Scenes (${chips.size})", fontSize = 11.5.sp, fontWeight = FontWeight.Bold, maxLines = 1, softWrap = false)
                    }
                }
            }
            Text(
                text = conn.activeScene.ifBlank { "Scene" },
                color = Color(0xFF34D399),
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 1,
                modifier = Modifier
                    .fillMaxWidth()
                    .basicMarquee()
            )
            if (conn.studioModeActive && conn.previewScene.isNotBlank()) {
                Text(
                    text = "Preview Next: ${conn.previewScene}",
                    color = Color(0xFF38BDF8),
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Medium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            if (chips.isNotEmpty()) {
                LazyRow(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    items(chips, key = { it.name }) { chip ->
                        val chipBg = when {
                            chip.isLive -> Color(0xFF064E3B)
                            chip.isPreview -> Color(0xFF0C4A6E)
                            else -> Color(0xFF141820)
                        }
                        val chipBorder = when {
                            chip.isLive -> Color(0xFF34D399)
                            chip.isPreview -> Color(0xFF38BDF8)
                            else -> PodiumOledBorder
                        }
                        Surface(
                            modifier = Modifier
                                .heightIn(min = 48.dp)
                                .clip(RoundedCornerShape(10.dp))
                                .clickable(enabled = canControl) { onSwitchScene(chip.name) },
                            shape = RoundedCornerShape(10.dp),
                            color = chipBg,
                            border = BorderStroke(1.dp, chipBorder)
                        ) {
                            Row(
                                modifier = Modifier.padding(horizontal = 14.dp, vertical = 12.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(6.dp)
                            ) {
                                if (chip.isLive) {
                                    Text("●", color = Color(0xFF34D399), fontSize = 11.sp, fontWeight = FontWeight.ExtraBold)
                                } else if (chip.isPreview) {
                                    Text("NEXT", color = Color(0xFF38BDF8), fontSize = 10.sp, fontWeight = FontWeight.ExtraBold)
                                }
                                Text(
                                    text = chip.name,
                                    color = if (canControl) Color.White else Color(0xFF64748B),
                                    fontSize = 13.5.sp,
                                    fontWeight = if (chip.isLive || chip.isPreview) FontWeight.Bold else FontWeight.SemiBold,
                                    maxLines = 1,
                                    softWrap = false
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun PodiumScenePickerDialog(
    conn: ConnectionUiState,
    canControl: Boolean,
    hideFromScreenCapture: Boolean,
    onSelectScene: (String) -> Unit,
    onDismiss: () -> Unit
) {
    val chips = remember(conn.scenes, conn.activeScene, conn.previewScene, conn.studioModeActive) {
        buildPodiumSceneChipModels(conn.scenes, conn.activeScene, conn.previewScene, conn.studioModeActive)
    }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(
            usePlatformDefaultWidth = false,
            securePolicy = resolvePodiumScenePickerSecurePolicy(hideFromScreenCapture)
        )
    ) {
        Surface(
            modifier = Modifier
                .fillMaxWidth(0.92f)
                .heightIn(max = 520.dp),
            shape = RoundedCornerShape(16.dp),
            color = PodiumOledBlack,
            border = BorderStroke(1.dp, PodiumOledBorder)
        ) {
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "Select OBS Scene",
                        color = Color.White,
                        fontSize = 17.sp,
                        fontWeight = FontWeight.Bold
                    )
                    OutlinedButton(
                        onClick = onDismiss,
                        border = BorderStroke(1.dp, Color(0xFF475569)),
                        colors = ButtonDefaults.outlinedButtonColors(contentColor = Color.White)
                    ) {
                        Text("Close", fontWeight = FontWeight.SemiBold)
                    }
                }
                HorizontalDivider(color = PodiumOledBorder)
                if (chips.isEmpty()) {
                    Text(
                        text = "No OBS scenes available.",
                        color = Color(0xFF94A3B8),
                        fontSize = 14.sp,
                        modifier = Modifier.padding(vertical = 12.dp)
                    )
                } else {
                    LazyColumn(
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        items(chips, key = { it.name }) { chip ->
                            val rowBg = when {
                                chip.isLive -> Color(0xFF064E3B)
                                chip.isPreview -> Color(0xFF0C4A6E)
                                else -> PodiumOledCard
                            }
                            val rowBorder = when {
                                chip.isLive -> Color(0xFF34D399)
                                chip.isPreview -> Color(0xFF38BDF8)
                                else -> PodiumOledBorder
                            }
                            Surface(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .heightIn(min = 52.dp)
                                    .clip(RoundedCornerShape(10.dp))
                                    .clickable(enabled = canControl) { onSelectScene(chip.name) },
                                shape = RoundedCornerShape(10.dp),
                                color = rowBg,
                                border = BorderStroke(1.dp, rowBorder)
                            ) {
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(horizontal = 14.dp, vertical = 12.dp),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Text(
                                        text = chip.name,
                                        color = if (canControl) Color.White else Color(0xFF64748B),
                                        fontSize = 15.sp,
                                        fontWeight = if (chip.isLive) FontWeight.Bold else FontWeight.SemiBold,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                        modifier = Modifier.weight(1f)
                                    )
                                    if (chip.isLive) {
                                        Text("LIVE", color = Color(0xFF34D399), fontSize = 11.sp, fontWeight = FontWeight.ExtraBold)
                                    } else if (chip.isPreview) {
                                        Text("PREVIEW", color = Color(0xFF38BDF8), fontSize = 11.sp, fontWeight = FontWeight.ExtraBold)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
