package com.saabithjiffry.presentersync.remote.ui.screens

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
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
import kotlinx.coroutines.launch

@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun StatusAndActionsCard(
    cfg: RemoteConfig,
    conn: ConnectionUiState,
    formFactor: ResolvedFormFactor,
    onStartHud: () -> Unit,
    onStopHud: () -> Unit,
    onToggleMute: () -> Unit,
    onOpenConnection: () -> Unit,
    onReconnect: () -> Unit,
    onOpenQr: () -> Unit,
    onOpenHelp: () -> Unit,
    onOpenAbout: () -> Unit,
    onOpenSetupWizard: () -> Unit = {},
    onPptPrev: () -> Unit = {},
    onPptNext: () -> Unit = {},
    onToggleRecord: () -> Unit = {},
    onSelectProfile: (String) -> Unit = {}
) {
    val statusColor = when {
        conn.connStatus == ConnStatus.AUTH_FAILED -> Color(0xFFDC2626)
        conn.connected && conn.connStatus == ConnStatus.MIC_ERROR -> Color(0xFFD97706)
        conn.connected && conn.isMuted -> Color(0xFFDC2626)
        conn.connected -> Color(0xFF10B981)
        else -> Color(0xFF6B7280)
    }

    val statusHeading = when {
        !conn.serviceRunning -> "Floating HUD Stopped"
        conn.connStatus == ConnStatus.AUTH_FAILED -> "Auth Failed (Check OBS Password)"
        conn.connected && conn.connStatus == ConnStatus.MIC_ERROR ->
            "Mic '${cfg.targetMicName}' Not Found"
        conn.connected && conn.isMuted -> "MIC MUTED"
        conn.connected -> "MIC LIVE"
        else -> "Searching for OBS Host..."
    }

    val statusSub = when {
        !conn.serviceRunning -> "Tap Start Floating HUD to show the always-on-top Mic pill."
        conn.connected && conn.usingRelayFallback ->
            "Connected via Internet Relay fallback (${conn.activeHost})"
        conn.connected && conn.usingBridge ->
            "Paired via Primary Host Bridge (${conn.activeHost})"
        conn.connected -> "Connected to ${conn.activeHost}"
        cfg.networkMode == NetworkMode.INTERNET ->
            "Relay Pairing Code: ${cfg.internetPairingCode.ifBlank { "(not set)" }}"
        else -> "Target: ${cfg.hostAddress}:${cfg.hostPort}"
    }

    ExplorerCard(contentPadding = formFactor.cardPaddingDp) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Box(
                    modifier = Modifier
                        .size(44.dp)
                        .clip(RoundedCornerShape(8.dp))
                        .background(statusColor.copy(alpha = 0.14f)),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = when {
                            conn.connStatus == ConnStatus.AUTH_FAILED ||
                                conn.connStatus == ConnStatus.MIC_ERROR -> Icons.Default.Warning
                            conn.isMuted -> Icons.Default.MicOff
                            else -> Icons.Default.Mic
                        },
                        contentDescription = null,
                        tint = statusColor
                    )
                }
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = statusHeading,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        color = statusColor
                    )
                    Text(
                        text = statusSub,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            if (conn.connected) {
                val recText = when (conn.recState) {
                    1 -> "● REC ${conn.formattedRecElapsed()}"
                    2 -> "❚❚ PAUSED ${conn.formattedRecElapsed()}"
                    else -> "REC: OFF"
                }
                val recTint = when (conn.recState) {
                    1 -> Color(0xFFDC2626)
                    2 -> Color(0xFFD97706)
                    else -> MaterialTheme.colorScheme.onSurfaceVariant
                }
                val streamText = if (conn.streamDropWarn) "⚠ STREAM DROP WARN" else "Stream OK"
                val streamTint = if (conn.streamDropWarn) Color(0xFFDC2626) else Color(0xFF10B981)

                Surface(
                    shape = RoundedCornerShape(8.dp),
                    color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f),
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant)
                ) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 10.dp, vertical = 8.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                text = recText,
                                style = MaterialTheme.typography.labelMedium,
                                fontWeight = FontWeight.SemiBold,
                                color = recTint
                            )
                            Text(
                                text = streamText,
                                style = MaterialTheme.typography.labelMedium,
                                fontWeight = FontWeight.SemiBold,
                                color = streamTint
                            )
                        }
                        if (conn.voiceWhileMuted && conn.isMuted) {
                            Text(
                                text = "⚠ You're on mute — mic signal detected on Host",
                                style = MaterialTheme.typography.labelMedium,
                                fontWeight = FontWeight.SemiBold,
                                color = Color(0xFFD97706)
                            )
                        }
                    }
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                if (!conn.serviceRunning) {
                    Button(
                        onClick = onStartHud,
                        contentPadding = CompactExplorerButtonPadding,
                        modifier = Modifier.weight(1f)
                    ) {
                        Icon(Icons.Default.PlayArrow, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("Start Floating HUD", maxLines = 1, softWrap = false, overflow = TextOverflow.Ellipsis)
                    }
                } else {
                    Button(
                        onClick = onToggleMute,
                        contentPadding = CompactExplorerButtonPadding,
                        colors = ButtonDefaults.buttonColors(
                            containerColor = if (conn.isMuted) Color(0xFFDC2626) else Color(0xFF10B981)
                        ),
                        modifier = Modifier.weight(1f)
                    ) {
                        Icon(
                            if (conn.isMuted) Icons.Default.MicOff else Icons.Default.Mic,
                            contentDescription = null,
                            modifier = Modifier.size(18.dp)
                        )
                        Spacer(Modifier.width(6.dp))
                        Text(
                            if (conn.isMuted) "Unmute Mic" else "Mute Mic",
                            maxLines = 1,
                            softWrap = false,
                            overflow = TextOverflow.Ellipsis
                        )
                    }

                    OutlinedButton(
                        onClick = onStopHud,
                        contentPadding = CompactExplorerButtonPadding,
                        modifier = Modifier.weight(1f)
                    ) {
                        Icon(Icons.Default.Stop, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("Stop HUD", maxLines = 1, softWrap = false, overflow = TextOverflow.Ellipsis)
                    }
                }
            }

            if (conn.connected && conn.usingBridge) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    OutlinedButton(
                        onClick = onPptPrev,
                        contentPadding = CompactExplorerButtonPadding,
                        modifier = Modifier.weight(1f)
                    ) {
                        Text("◀ Prev", maxLines = 1, softWrap = false, overflow = TextOverflow.Ellipsis)
                    }
                    OutlinedButton(
                        onClick = onToggleRecord,
                        contentPadding = CompactExplorerButtonPadding,
                        modifier = Modifier.weight(1f)
                    ) {
                        Text(
                            if (conn.recState == 1) "⏹ Stop Rec" else "⏺ Rec",
                            maxLines = 1,
                            softWrap = false,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                    OutlinedButton(
                        onClick = onPptNext,
                        contentPadding = CompactExplorerButtonPadding,
                        modifier = Modifier.weight(1f)
                    ) {
                        Text("Next ▶", maxLines = 1, softWrap = false, overflow = TextOverflow.Ellipsis)
                    }
                }
            }

            if (cfg.savedProfiles.isNotEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        text = "Saved Rooms / Host Profiles",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    FlowRow(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        cfg.savedProfiles.forEach { prof ->
                            FilterChip(
                                selected = cfg.activeProfileId == prof.id,
                                onClick = { onSelectProfile(prof.id) },
                                label = { Text(prof.name, maxLines = 1, softWrap = false) }
                            )
                        }
                    }
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                OutlinedButton(
                    onClick = onOpenConnection,
                    contentPadding = CompactExplorerButtonPadding,
                    modifier = Modifier.weight(1f)
                ) {
                    Icon(Icons.Default.Settings, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(6.dp))
                    Text(
                        if (formFactor.isTightWidth) "Connect Setup" else "Connection Setup",
                        maxLines = 1,
                        softWrap = false,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                OutlinedButton(
                    onClick = onReconnect,
                    contentPadding = CompactExplorerButtonPadding,
                    modifier = Modifier.weight(1f)
                ) {
                    Icon(Icons.Default.Refresh, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(6.dp))
                    Text("Reconnect", maxLines = 1, softWrap = false, overflow = TextOverflow.Ellipsis)
                }
            }

            if (formFactor.isTightWidth) {
                FlowRow(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    OutlinedButton(
                        onClick = onOpenQr,
                        contentPadding = CompactExplorerButtonPadding
                    ) {
                        Icon(Icons.Default.QrCodeScanner, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.width(5.dp))
                        Text("Scan QR", maxLines = 1, softWrap = false)
                    }
                    OutlinedButton(
                        onClick = onOpenHelp,
                        contentPadding = CompactExplorerButtonPadding
                    ) {
                        Icon(Icons.AutoMirrored.Filled.HelpOutline, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.width(5.dp))
                        Text("Help", maxLines = 1, softWrap = false)
                    }
                    OutlinedButton(
                        onClick = onOpenAbout,
                        contentPadding = CompactExplorerButtonPadding
                    ) {
                        Icon(Icons.Default.Info, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.width(5.dp))
                        Text("About", maxLines = 1, softWrap = false)
                    }
                }
            } else {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    OutlinedButton(
                        onClick = onOpenQr,
                        contentPadding = CompactExplorerButtonPadding,
                        modifier = Modifier.weight(1f)
                    ) {
                        Icon(Icons.Default.QrCodeScanner, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("Scan QR", maxLines = 1, softWrap = false, overflow = TextOverflow.Ellipsis)
                    }
                    OutlinedButton(
                        onClick = onOpenHelp,
                        contentPadding = CompactExplorerButtonPadding,
                        modifier = Modifier.weight(1f)
                    ) {
                        Icon(Icons.AutoMirrored.Filled.HelpOutline, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("Help", maxLines = 1, softWrap = false, overflow = TextOverflow.Ellipsis)
                    }
                    OutlinedButton(
                        onClick = onOpenAbout,
                        contentPadding = CompactExplorerButtonPadding,
                        modifier = Modifier.weight(1f)
                    ) {
                        Icon(Icons.Default.Info, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("About", maxLines = 1, softWrap = false, overflow = TextOverflow.Ellipsis)
                    }
                }
            }

            OutlinedButton(
                onClick = onOpenSetupWizard,
                contentPadding = CompactExplorerButtonPadding,
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("open_setup_wizard_btn")
            ) {
                Icon(Icons.Default.Checklist, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(6.dp))
                Text("Guided Setup Wizard", maxLines = 1, softWrap = false, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun FormFactorOptimizationCard(
    cfg: RemoteConfig,
    formFactor: ResolvedFormFactor,
    onSelectMode: (DeviceProfileMode) -> Unit,
    onApplyPreset: () -> Unit
) {
    ExplorerCard(contentPadding = formFactor.cardPaddingDp) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Icon(
                    imageVector = Icons.Default.Devices,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(20.dp)
                )
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = "Screen & Device Optimization",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = formFactor.badgeText,
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.primary
                    )
                }
            }
            Text(
                text = formFactor.recommendationHint,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                DeviceProfileMode.entries.forEach { mode ->
                    FilterChip(
                        selected = cfg.deviceProfileMode == mode,
                        onClick = { onSelectMode(mode) },
                        label = { Text(mode.shortLabel) }
                    )
                }
            }
            OutlinedButton(
                onClick = onApplyPreset,
                contentPadding = CompactExplorerButtonPadding,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(
                    text = "Apply ${formFactor.deviceClass.label} Preset (${formFactor.recommendedScale}x)",
                    maxLines = 1,
                    softWrap = false,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
    }
}

@Composable
internal fun FloatingPillQuickCard(
    cfg: RemoteConfig,
    formFactor: ResolvedFormFactor,
    onToggleIndicator: (Boolean) -> Unit,
    onToggleText: (Boolean) -> Unit,
    onResetPosition: () -> Unit
) {
    ExplorerCard(contentPadding = formFactor.cardPaddingDp) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(
                text = "Floating Mic Pill",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    "Show Floating Indicator",
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.weight(1f).padding(end = 12.dp)
                )
                Switch(checked = cfg.showIndicator, onCheckedChange = onToggleIndicator)
            }
            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    "Show Status Text (LIVE / MUTED)",
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.weight(1f).padding(end = 12.dp)
                )
                Switch(checked = cfg.showText, onCheckedChange = onToggleText)
            }
            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

            ResponsiveExplorerActionRow(
                title = "Floating Pill Position",
                subtitle = if (cfg.savedX < 0 && cfg.savedXRatio < 0f) {
                    "Bottom-Right Default"
                } else if (cfg.savedXRatio in 0f..1f) {
                    "Saved (${(cfg.savedXRatio * 100).toInt()}%, ${(cfg.savedYRatio * 100).toInt()}% • Rotation-safe)"
                } else {
                    "(${cfg.savedX}, ${cfg.savedY})"
                },
                isTightWidth = formFactor.isTightWidth
            ) {
                OutlinedButton(
                    onClick = onResetPosition,
                    contentPadding = CompactExplorerButtonPadding
                ) {
                    Text("Reset Position", maxLines = 1, softWrap = false)
                }
            }
        }
    }
}

@Composable
internal fun CurrentProfileSummaryCard(
    cfg: RemoteConfig,
    formFactor: ResolvedFormFactor
) {
    ExplorerCard(contentPadding = formFactor.cardPaddingDp) {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(
                text = "Current Connection Profile",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
            Spacer(Modifier.height(2.dp))
            ProfileLine("Mode", cfg.networkMode.label)
            ProfileLine("Device Profile", "${cfg.deviceProfileMode.shortLabel} (${formFactor.deviceClass.label})")
            ProfileLine("Host Candidates", cfg.hostAddress)
            ProfileLine("OBS / Bridge Ports", "${cfg.hostPort} / ${cfg.bridgePort}")
            ProfileLine("Target Mic", cfg.targetMicName)
            ProfileLine("Pointer Mute Key", if (cfg.enablePointerMute) cfg.hwMuteHotkey else "Disabled")
            ProfileLine("Heartbeat", "${cfg.heartbeatSeconds}s")
            ProfileLine("Auto Relay Fallback", if (cfg.enableRelayFallback) "Enabled" else "Disabled")
            if (cfg.sessionPairingCode.isNotEmpty()) {
                ProfileLine("Session Code", cfg.sessionPairingCode)
            }
            if (cfg.internetPairingCode.isNotEmpty()) {
                ProfileLine("Internet Relay Code", cfg.internetPairingCode)
            }
        }
    }
}

@Composable
internal fun PermissionWarningCard(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    description: String,
    actionLabel: String,
    onClick: () -> Unit
) {
    ExplorerCard(
        containerColor = MaterialTheme.colorScheme.errorContainer,
        borderColor = MaterialTheme.colorScheme.error.copy(alpha = 0.5f),
        contentPadding = 16
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.onErrorContainer)
                Text(
                    text = title,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onErrorContainer
                )
            }
            Text(
                text = description,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onErrorContainer
            )
            Button(
                onClick = onClick,
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.error,
                    contentColor = MaterialTheme.colorScheme.onError
                )
            ) {
                Text(actionLabel)
            }
        }
    }
}

@Composable
internal fun ProfileLine(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(Modifier.width(12.dp))
        Text(
            text = value,
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.Medium
        )
    }
}

