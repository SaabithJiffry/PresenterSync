package com.saabithjiffry.presentersync.remote.ui.screens

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.view.WindowManager
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.saabithjiffry.presentersync.remote.PresenterSyncRemoteApp

private fun Context.findHostActivity(): Activity? {
    var ctx: Context = this
    while (ctx is ContextWrapper) {
        if (ctx is Activity) return ctx
        ctx = ctx.baseContext
    }
    return null
}

@Composable
fun PodiumDeckScreen(
    app: PresenterSyncRemoteApp,
    onExitPodium: () -> Unit
) {
    val conn by app.connectionManager.uiState.collectAsStateWithLifecycle()
    val context = LocalContext.current

    BackHandler(onBack = onExitPodium)

    DisposableEffect(Unit) {
        val window = context.findHostActivity()?.window
        window?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        onDispose {
            window?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    val oledBlack = Color(0xFF000000)
    val oledCard = Color(0xFF0D0D0F)
    val oledBorder = Color(0xFF26262A)
    val liveEmerald = Color(0xFF107C10)
    val mutedCrimson = Color(0xFFC42B1C)
    val amberAlert = Color(0xFFF59E0B)

    val muteCardBg = when {
        !conn.connected -> Color(0xFF1F2937)
        conn.isMuted -> mutedCrimson
        else -> liveEmerald
    }
    val muteBorder = if (conn.connected && conn.isMuted && conn.voiceWhileMuted) {
        amberAlert
    } else {
        Color.White.copy(alpha = 0.22f)
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(oledBlack)
            .safeDrawingPadding()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        // Top Bar: Status + REC/BRB Badge + Exit Podium
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "PODIUM DECK",
                    color = Color(0xFF94A3B8),
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = 1.2.sp
                )
                val statusSummary = buildString {
                    append(if (conn.connected) conn.transportName else "Disconnected")
                    if (conn.recState == 1) append("  •  ● REC ${conn.formattedRecElapsed()}")
                    else if (conn.recState == 2) append("  •  ❚❚ PAUSED ${conn.formattedRecElapsed()}")
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

        Column(
            modifier = Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            // High-Contrast Oversized MUTE / UNMUTE Touch Surface
            Surface(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(148.dp)
                    .clip(RoundedCornerShape(18.dp))
                    .clickable { app.connectionManager.toggleMuteFromHud() },
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

            // OBS Scene Transition (Preview <-> Program)
            Button(
                onClick = { app.connectionManager.sendTransitionScene("podium") },
                enabled = conn.connected,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(52.dp),
                shape = RoundedCornerShape(12.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = Color(0xFF0067C0),
                    contentColor = Color.White
                )
            ) {
                Text(
                    text = "⇄ OBS Transition (Preview ↔ Program) • ${conn.activeScene}",
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }

            // Slides & Speaker Notes Section
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(14.dp),
                color = oledCard,
                border = BorderStroke(1.dp, oledBorder)
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
                            onClick = { app.connectionManager.sendPptPrev("podium") },
                            enabled = conn.connected && conn.usingBridge,
                            modifier = Modifier.weight(1f).height(48.dp)
                        ) {
                            Text("◀ Prev", fontWeight = FontWeight.Bold)
                        }
                        FilledTonalButton(
                            onClick = { app.connectionManager.sendPptNext("podium") },
                            enabled = conn.connected && conn.usingBridge,
                            modifier = Modifier.weight(1f).height(48.dp)
                        ) {
                            Text("Next ▶", fontWeight = FontWeight.Bold)
                        }
                    }

                    OutlinedButton(
                        onClick = { app.connectionManager.sendStartSlideshow("podium") },
                        enabled = conn.connected && conn.usingBridge,
                        modifier = Modifier.fillMaxWidth(),
                        border = BorderStroke(1.dp, oledBorder),
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

            // Countdown Timer & Standby (BRB) Controls
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(14.dp),
                color = oledCard,
                border = BorderStroke(1.dp, oledBorder)
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
                            fontWeight = FontWeight.Bold
                        )
                        Button(
                            onClick = { app.connectionManager.sendToggleStandby("podium") },
                            enabled = conn.connected,
                            colors = ButtonDefaults.buttonColors(
                                containerColor = if (conn.isStandby) amberAlert else Color(0xFF1E293B),
                                contentColor = Color.White
                            )
                        ) {
                            Text(if (conn.isStandby) "Exit BRB" else "BRB", fontWeight = FontWeight.Bold)
                        }
                    }

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        for ((lbl, sec) in listOf("5m" to 300, "10m" to 600, "15m" to 900)) {
                            OutlinedButton(
                                onClick = { app.connectionManager.sendTimerCommand("timer_start", sec, "podium") },
                                enabled = conn.connected,
                                modifier = Modifier.weight(1f),
                                border = BorderStroke(1.dp, oledBorder),
                                colors = ButtonDefaults.outlinedButtonColors(contentColor = Color.White)
                            ) {
                                Text(lbl, fontWeight = FontWeight.Bold)
                            }
                        }
                        OutlinedButton(
                            onClick = { app.connectionManager.sendTimerCommand("timer_pause", 0, "podium") },
                            enabled = conn.connected,
                            modifier = Modifier.weight(1f),
                            border = BorderStroke(1.dp, oledBorder),
                            colors = ButtonDefaults.outlinedButtonColors(contentColor = Color.White)
                        ) {
                            Text(if (conn.timerState == "paused") "▶" else "❚❚", fontWeight = FontWeight.Bold)
                        }
                        OutlinedButton(
                            onClick = { app.connectionManager.sendTimerCommand("timer_reset", 0, "podium") },
                            enabled = conn.connected,
                            modifier = Modifier.weight(1f),
                            border = BorderStroke(1.dp, oledBorder),
                            colors = ButtonDefaults.outlinedButtonColors(contentColor = Color.White)
                        ) {
                            Text("↺", fontWeight = FontWeight.Bold)
                        }
                    }
                }
            }

            // Quick Stage Nudge Chips
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(14.dp),
                color = oledCard,
                border = BorderStroke(1.dp, oledBorder)
            ) {
                Column(
                    modifier = Modifier.padding(14.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text(
                        text = "Quick Stage Nudge",
                        color = Color(0xFF94A3B8),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold
                    )
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .horizontalScroll(rememberScrollState()),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        for (nudge in listOf("2 min left", "Wrap up", "Q&A")) {
                            FilledTonalButton(
                                onClick = { app.connectionManager.sendStageNudge(nudge) },
                                enabled = conn.connected && (conn.usingBridge || conn.usingRelayFallback)
                            ) {
                                Text(nudge, fontWeight = FontWeight.SemiBold)
                            }
                        }
                    }
                }
            }
        }
    }
}
