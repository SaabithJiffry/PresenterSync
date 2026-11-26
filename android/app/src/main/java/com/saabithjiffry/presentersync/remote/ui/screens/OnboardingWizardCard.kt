package com.saabithjiffry.presentersync.remote.ui.screens

import android.os.Build
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Layers
import androidx.compose.material.icons.filled.NotificationsActive
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Wifi
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.saabithjiffry.presentersync.remote.config.RemoteConfig
import com.saabithjiffry.presentersync.remote.config.ResolvedFormFactor
import com.saabithjiffry.presentersync.remote.network.ConnectionUiState
import com.saabithjiffry.presentersync.remote.network.DiscoveredPublicHost
import com.saabithjiffry.presentersync.remote.ui.theme.CompactExplorerButtonPadding
import kotlinx.coroutines.launch

data class OnboardingStepStatus(
    val index: Int,
    val title: String,
    val detail: String,
    val ready: Boolean
)

data class OnboardingChecklistState(
    val overlayReady: Boolean,
    val notificationsReady: Boolean,
    val pairingReady: Boolean,
    val hudReady: Boolean,
    val discoveredCount: Int,
    val steps: List<OnboardingStepStatus>
) {
    val completedCount: Int get() = steps.count { it.ready }
    val totalSteps: Int get() = steps.size
    val allReady: Boolean get() = completedCount == totalSteps
}

fun evaluateOnboardingReadiness(
    hasOverlayPerm: Boolean,
    hasNotifPerm: Boolean,
    notificationsRequired: Boolean,
    cfg: RemoteConfig,
    conn: ConnectionUiState,
    discoveredCount: Int = 0
): OnboardingChecklistState {
    val overlayOk = hasOverlayPerm
    val notifOk = !notificationsRequired || hasNotifPerm
    val cleanHost = cfg.hostAddress.trim()
    val pairingOk = conn.connected ||
        cfg.internetPairingCode.isNotBlank() ||
        cfg.sessionToken.isNotBlank() ||
        (cleanHost.isNotEmpty() && cleanHost != "127.0.0.1")
    val hudOk = conn.serviceRunning || (!cfg.firstRun && pairingOk)

    val step1 = OnboardingStepStatus(
        index = 1,
        title = "Display Over Other Apps",
        detail = if (overlayOk) {
            "Overlay permission granted — floating mic pill can sit on top of slides."
        } else {
            "Required so the floating mic indicator stays visible above PowerPoint and apps."
        },
        ready = overlayOk
    )
    val step2 = OnboardingStepStatus(
        index = 2,
        title = "Foreground Service Notifications",
        detail = if (!notificationsRequired) {
            "Handled automatically by Android on this OS version."
        } else if (notifOk) {
            "Notification permission granted so Android keeps the floating HUD alive."
        } else {
            "Recommended on Android 13+ so PresenterSync can show active HUD controls."
        },
        ready = notifOk
    )
    val step3 = OnboardingStepStatus(
        index = 3,
        title = "Pair PresenterSync Host",
        detail = when {
            conn.connected -> "Connected to ${cfg.hostAddress.ifBlank { "Host Bridge" }}."
            pairingOk -> "Host configured (${cfg.networkMode.label}: ${cfg.hostAddress.ifBlank { cfg.internetPairingCode }})."
            discoveredCount > 0 -> "$discoveredCount classroom host(s) found below — tap one to pair."
            else -> "Scan classroom LAN (:4457), scan the Windows QR code, or enter a pairing code."
        },
        ready = pairingOk
    )
    val step4 = OnboardingStepStatus(
        index = 4,
        title = "Verify Live Floating Pill",
        detail = if (conn.serviceRunning) {
            "Floating HUD is active on screen. Drag, double-tap, or mute to confirm."
        } else {
            "Launch the floating HUD pill once to verify position and gesture controls."
        },
        ready = hudOk
    )

    return OnboardingChecklistState(
        overlayReady = overlayOk,
        notificationsReady = notifOk,
        pairingReady = pairingOk,
        hudReady = hudOk,
        discoveredCount = discoveredCount,
        steps = listOf(step1, step2, step3, step4)
    )
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun OnboardingWizardCard(
    cfg: RemoteConfig,
    conn: ConnectionUiState,
    hasOverlayPerm: Boolean,
    hasNotifPerm: Boolean,
    formFactor: ResolvedFormFactor,
    onRequestOverlayPermission: () -> Unit,
    onRequestNotificationPermission: () -> Unit,
    onScanClassroomHosts: suspend () -> List<DiscoveredPublicHost>,
    onSelectDiscoveredHost: (DiscoveredPublicHost) -> Unit,
    onOpenQrScanner: () -> Unit,
    onOpenConnectionSetup: () -> Unit,
    onTestFloatingHud: () -> Unit,
    onCompleteWizard: () -> Unit,
    onDismissWizard: () -> Unit,
    batteryOptimizationExempt: Boolean = true,
    onRequestBatteryUnrestricted: () -> Unit = {}
) {
    val scope = rememberCoroutineScope()
    var scanningLan by remember { mutableStateOf(false) }
    var discoveredHosts by remember { mutableStateOf<List<DiscoveredPublicHost>>(emptyList()) }
    var scanMessage by remember { mutableStateOf<String?>(null) }

    val notificationsRequired = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
    val checklist = evaluateOnboardingReadiness(
        hasOverlayPerm = hasOverlayPerm,
        hasNotifPerm = hasNotifPerm,
        notificationsRequired = notificationsRequired,
        cfg = cfg,
        conn = conn,
        discoveredCount = discoveredHosts.size
    )

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .testTag("onboarding_wizard_card"),
        shape = RoundedCornerShape(12.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        border = BorderStroke(1.5.dp, MaterialTheme.colorScheme.primary.copy(alpha = 0.55f))
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = "Guided Setup Wizard",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold
                    )
                    Text(
                        text = "Checklist (${checklist.completedCount}/${checklist.totalSteps} ready) — " +
                            if (checklist.allReady) "All set for presenting!" else "Complete steps below for reliable sync.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                TextButton(
                    onClick = onDismissWizard,
                    contentPadding = CompactExplorerButtonPadding
                ) {
                    Text(if (cfg.firstRun) "Skip" else "Close")
                }
            }

            LinearProgressIndicator(
                progress = { checklist.completedCount.toFloat() / checklist.totalSteps.toFloat() },
                modifier = Modifier.fillMaxWidth()
            )

            // Step 1: Display Over Other Apps
            OnboardingStepRow(
                step = checklist.steps[0],
                tag = "onboarding_step_1"
            ) {
                if (!checklist.overlayReady) {
                    Button(
                        onClick = onRequestOverlayPermission,
                        contentPadding = CompactExplorerButtonPadding
                    ) {
                        Icon(Icons.Default.Layers, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("Grant Overlay", maxLines = 1, softWrap = false)
                    }
                }
            }

            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

            // Step 2: Notifications (Android 13+)
            OnboardingStepRow(
                step = checklist.steps[1],
                tag = "onboarding_step_2"
            ) {
                if (notificationsRequired && !checklist.notificationsReady) {
                    OutlinedButton(
                        onClick = onRequestNotificationPermission,
                        contentPadding = CompactExplorerButtonPadding
                    ) {
                        Icon(
                            Icons.Default.NotificationsActive,
                            contentDescription = null,
                            modifier = Modifier.size(16.dp)
                        )
                        Spacer(Modifier.width(6.dp))
                        Text("Allow Notifications", maxLines = 1, softWrap = false)
                    }
                }
            }

            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

            // Step 3: Classroom Host Discovery / QR / Connection Setup
            OnboardingStepRow(
                step = checklist.steps[2],
                tag = "onboarding_step_3"
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    FlowRow(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        OutlinedButton(
                            onClick = {
                                if (scanningLan) return@OutlinedButton
                                scanningLan = true
                                scanMessage = "Scanning classroom LAN (:4457)..."
                                scope.launch {
                                    val found = runCatching { onScanClassroomHosts() }.getOrDefault(emptyList())
                                    discoveredHosts = found
                                    scanningLan = false
                                    scanMessage = if (found.isEmpty()) {
                                        "No classroom hosts found on UDP :4457. Try QR or Connection Setup."
                                    } else {
                                        "Found ${found.size} classroom host(s). Tap one below to fill & connect:"
                                    }
                                }
                            },
                            enabled = !scanningLan,
                            contentPadding = CompactExplorerButtonPadding,
                            modifier = Modifier.testTag("onboarding_scan_lan_btn")
                        ) {
                            if (scanningLan) {
                                CircularProgressIndicator(modifier = Modifier.size(14.dp), strokeWidth = 2.dp)
                            } else {
                                Icon(Icons.Default.Wifi, contentDescription = null, modifier = Modifier.size(16.dp))
                            }
                            Spacer(Modifier.width(6.dp))
                            Text(
                                if (formFactor.isTightWidth) "Scan LAN" else "Scan Classroom",
                                maxLines = 1,
                                softWrap = false
                            )
                        }

                        OutlinedButton(
                            onClick = onOpenQrScanner,
                            contentPadding = CompactExplorerButtonPadding
                        ) {
                            Icon(
                                Icons.Default.QrCodeScanner,
                                contentDescription = null,
                                modifier = Modifier.size(16.dp)
                            )
                            Spacer(Modifier.width(6.dp))
                            Text("Scan QR", maxLines = 1, softWrap = false)
                        }

                        OutlinedButton(
                            onClick = onOpenConnectionSetup,
                            contentPadding = CompactExplorerButtonPadding
                        ) {
                            Icon(Icons.Default.Settings, contentDescription = null, modifier = Modifier.size(16.dp))
                            Spacer(Modifier.width(6.dp))
                            Text("Connection Setup", maxLines = 1, softWrap = false)
                        }
                    }

                    if (!scanMessage.isNullOrBlank()) {
                        Text(
                            text = scanMessage.orEmpty(),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }

                    if (discoveredHosts.isNotEmpty()) {
                        FlowRow(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            discoveredHosts.forEach { host ->
                                FilterChip(
                                    selected = cfg.hostAddress == host.hostIp && cfg.bridgePort == host.bridgePort,
                                    onClick = { onSelectDiscoveredHost(host) },
                                    label = {
                                        Text(
                                            "${host.deviceName} (${host.hostIp}:${host.bridgePort})",
                                            maxLines = 1,
                                            softWrap = false
                                        )
                                    }
                                )
                            }
                        }
                    }
                }
            }

            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

            // Step 4: Test Live Floating Pill
            OnboardingStepRow(
                step = checklist.steps[3],
                tag = "onboarding_step_4"
            ) {
                OutlinedButton(
                    onClick = onTestFloatingHud,
                    contentPadding = CompactExplorerButtonPadding,
                    modifier = Modifier.testTag("onboarding_test_hud_btn")
                ) {
                    Icon(Icons.Default.PlayArrow, contentDescription = null, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(6.dp))
                    Text(
                        if (conn.serviceRunning) "HUD Active" else "Test Floating HUD",
                        maxLines = 1,
                        softWrap = false
                    )
                }
            }

            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End),
                verticalAlignment = Alignment.CenterVertically
            ) {
                if (cfg.firstRun) {
                    TextButton(
                        onClick = onDismissWizard,
                        contentPadding = CompactExplorerButtonPadding
                    ) {
                        Text("Skip for Now")
                    }
                }
                Button(
                    onClick = onCompleteWizard,
                    contentPadding = CompactExplorerButtonPadding,
                    modifier = Modifier.testTag("onboarding_finish_btn")
                ) {
                    Text(if (checklist.allReady) "Finish Setup" else "Mark Setup Done")
                }
            }
        }
    }
}

@Composable
private fun OnboardingStepRow(
    step: OnboardingStepStatus,
    tag: String,
    actions: @Composable () -> Unit = {}
) {
    val badgeColor = if (step.ready) Color(0xFF10B981) else Color(0xFFD97706)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .testTag(tag),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Icon(
                imageVector = if (step.ready) Icons.Default.CheckCircle else Icons.Default.RadioButtonUnchecked,
                contentDescription = null,
                tint = badgeColor,
                modifier = Modifier.size(18.dp)
            )
            Text(
                text = "${step.index}. ${step.title}",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.weight(1f)
            )
            Surface(
                shape = RoundedCornerShape(6.dp),
                color = badgeColor.copy(alpha = 0.12f)
            ) {
                Text(
                    text = if (step.ready) "READY" else "TODO",
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.Bold,
                    color = badgeColor,
                    modifier = Modifier.padding(horizontal = 7.dp, vertical = 2.dp)
                )
            }
        }
        Text(
            text = step.detail,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        actions()
    }
}
