package com.saabithjiffry.presentersync.remote.ui.screens

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccessibilityNew
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Keyboard
import androidx.compose.material.icons.filled.PauseCircle
import androidx.compose.material.icons.filled.Security
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.saabithjiffry.presentersync.remote.PresenterSyncRemoteApp
import com.saabithjiffry.presentersync.remote.config.ResolvedFormFactor
import com.saabithjiffry.presentersync.remote.config.rememberFormFactor
import com.saabithjiffry.presentersync.remote.input.ClickerMuteController
import com.saabithjiffry.presentersync.remote.service.CapturedKeyEvent
import com.saabithjiffry.presentersync.remote.service.ClickerAccessibilityService
import com.saabithjiffry.presentersync.remote.ui.theme.CompactExplorerButtonPadding
import com.saabithjiffry.presentersync.remote.ui.theme.ExplorerCard
import com.saabithjiffry.presentersync.remote.ui.theme.ResponsiveExplorerActionRow

private val QUICK_CLICKER_KEYS = listOf(
    "KEYCODE_B" to "B (Logitech Black Screen)",
    "KEYCODE_F5" to "F5",
    "KEYCODE_PAGE_DOWN" to "PgDn",
    "KEYCODE_PAGE_UP" to "PgUp",
    "KEYCODE_ESCAPE" to "Esc",
    "KEYCODE_VOLUME_DOWN" to "Volume Down",
    "KEYCODE_VOLUME_UP" to "Volume Up",
    "KEYCODE_MEDIA_PLAY_PAUSE" to "Media Play/Pause",
    "KEYCODE_M" to "M"
)

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun PointerSettingsScreen(
    app: PresenterSyncRemoteApp
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val cfg by app.configStore.config.collectAsStateWithLifecycle()
    val formFactor = rememberFormFactor(cfg.deviceProfileMode)

    val serviceConnectedFlow by ClickerAccessibilityService.serviceActive.collectAsStateWithLifecycle()
    val testerEvents by ClickerAccessibilityService.testerEvents.collectAsStateWithLifecycle()
    val lastCapturedKey by ClickerAccessibilityService.lastCapturedKey.collectAsStateWithLifecycle()

    var a11yEnabled by remember {
        mutableStateOf(serviceConnectedFlow || ClickerAccessibilityService.isServiceEnabled(context))
    }
    var showCaptureDialog by remember { mutableStateOf(false) }
    var showRestrictedGuideDialog by remember { mutableStateOf(false) }
    var testerOpen by remember { mutableStateOf(false) }
    var showShortcutDialog by remember { mutableStateOf(false) }

    LaunchedEffect(serviceConnectedFlow) {
        a11yEnabled = serviceConnectedFlow || ClickerAccessibilityService.isServiceEnabled(context)
    }

    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                a11yEnabled = ClickerAccessibilityService.isServiceEnabled(context)
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
            ClickerAccessibilityService.testerMode.set(false)
            ClickerAccessibilityService.captureNextKeyMode.set(false)
        }
    }

    Column(
        modifier = Modifier
            .widthIn(max = if (formFactor.isWideTwoColumn) 980.dp else 760.dp)
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(formFactor.outerPaddingDp.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        // 1. Hardware Pointer Global Service Status Card
        val badgeColor = if (a11yEnabled) Color(0xFF10B981) else Color(0xFFD97706)
        ExplorerCard(
            contentPadding = formFactor.cardPaddingDp,
            borderColor = if (a11yEnabled) MaterialTheme.colorScheme.outline else badgeColor.copy(alpha = 0.55f)
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Box(
                        modifier = Modifier
                            .size(42.dp)
                            .clip(RoundedCornerShape(8.dp))
                            .background(badgeColor.copy(alpha = 0.14f)),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = if (a11yEnabled) Icons.Default.CheckCircle else Icons.Default.AccessibilityNew,
                            contentDescription = null,
                            tint = badgeColor
                        )
                    }
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = if (a11yEnabled) {
                                "Hardware Clicker Service Active"
                            } else {
                                "Enable Hardware Clicker Service"
                            },
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                            color = if (a11yEnabled) MaterialTheme.colorScheme.onSurface else badgeColor
                        )
                        Text(
                            text = if (a11yEnabled) {
                                "Global key filter captures only your mute button; slide keys pass through cleanly."
                            } else {
                                "Required so USB/Bluetooth presenter clickers work globally over slides, PDFs & whiteboards."
                            },
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }

                FlowRow(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Button(
                        onClick = {
                            runCatching {
                                context.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                            }
                        },
                        contentPadding = CompactExplorerButtonPadding
                    ) {
                        Icon(Icons.Default.AccessibilityNew, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text(
                            if (a11yEnabled) "Accessibility Settings" else "Enable Service",
                            maxLines = 1,
                            softWrap = false,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                    OutlinedButton(
                        onClick = { showRestrictedGuideDialog = true },
                        contentPadding = CompactExplorerButtonPadding
                    ) {
                        Icon(Icons.Default.Security, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text(
                            "Android 13+ Guide",
                            maxLines = 1,
                            softWrap = false,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                }
            }
        }

        // 2. Clicker Behavior & Mute Button Configuration Card
        ExplorerCard(contentPadding = formFactor.cardPaddingDp) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(
                    text = "Hardware Clicker Controls",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold
                )
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Column(modifier = Modifier.weight(1f).padding(end = 12.dp)) {
                        Text(
                            "Enable Hardware Pointer Keystroke Intercept",
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.SemiBold
                        )
                        Text(
                            "Intercept presenter clicker keys when USB/Bluetooth receiver is paired to this Android device. Turn OFF if the receiver is plugged into the Windows PC.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    Switch(
                        checked = cfg.enablePointerIntercept,
                        onCheckedChange = { enabled ->
                            app.configStore.update { it.copy(enablePointerIntercept = enabled) }
                        }
                    )
                }
                if (!cfg.enablePointerIntercept) {
                    Text(
                        text = "Pointer key interception is OFF — clicker keys pass cleanly to Android apps. Use Floating Bubble Gestures (Long Press / Double Tap) in HUD Style to mute/unmute anytime.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.primary
                    )
                }
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Column(modifier = Modifier.weight(1f).padding(end = 12.dp)) {
                        Text("Enable Pointer Mute Button", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
                        Text(
                            "Allow assigned clicker mute button to toggle OBS/Host mic",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    Switch(
                        checked = cfg.enablePointerMute,
                        enabled = cfg.enablePointerIntercept,
                        onCheckedChange = { enabled ->
                            app.configStore.update { it.copy(enablePointerMute = enabled) }
                        }
                    )
                }
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Column(modifier = Modifier.weight(1f).padding(end = 12.dp)) {
                        Text("Push-to-Mute (Cough Hold)", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
                        Text(
                            "Short tap (<350ms) toggles; holding ≥350ms mutes while held and unmutes on release",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    Switch(
                        checked = cfg.enablePushToMute,
                        enabled = cfg.enablePointerIntercept,
                        onCheckedChange = { enabled ->
                            app.configStore.update { it.copy(enablePushToMute = enabled) }
                        }
                    )
                }
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Column(modifier = Modifier.weight(1f).padding(end = 12.dp)) {
                        Text("Suspend All Hotkeys & Clicker", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
                        Text(
                            "Temporarily pause hardware mute keys & shortcuts without disconnecting HUD",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    Switch(
                        checked = cfg.hotkeysSuspended,
                        onCheckedChange = { suspended ->
                            app.configStore.update { it.copy(hotkeysSuspended = suspended) }
                        }
                    )
                }
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

                // Assigned Button Row
                ResponsiveExplorerActionRow(
                    title = "Pointer Mute Button",
                    subtitle = "${ClickerMuteController.friendlyKeyLabel(cfg.hwMuteHotkey)} (${cfg.hwMuteHotkey})",
                    subtitleColor = MaterialTheme.colorScheme.primary,
                    isTightWidth = formFactor.isTightWidth
                ) {
                    OutlinedButton(
                        onClick = { showCaptureDialog = true },
                        contentPadding = CompactExplorerButtonPadding
                    ) {
                        Icon(Icons.Default.Keyboard, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("Change Button", maxLines = 1, softWrap = false)
                    }
                }
            }
        }

        // 3. Global Shortcuts Card
        ExplorerCard(contentPadding = formFactor.cardPaddingDp) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                ResponsiveExplorerActionRow(
                    title = "Keyboard Shortcuts (USB/BT Keyboard)",
                    subtitle = "Active globally when Accessibility Service is enabled and not suspended.",
                    isTightWidth = formFactor.isTightWidth
                ) {
                    OutlinedButton(
                        onClick = { showShortcutDialog = true },
                        contentPadding = CompactExplorerButtonPadding
                    ) {
                        Icon(Icons.Default.Edit, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("Edit", maxLines = 1, softWrap = false)
                    }
                }
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                ProfileLine("Toggle Mute Shortcut", cfg.toggleMuteShortcut)
                ProfileLine("Stop Floating HUD Shortcut", cfg.exitShortcut)
                if (cfg.hotkeysSuspended) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Icon(Icons.Default.PauseCircle, contentDescription = null, tint = Color(0xFFD97706), modifier = Modifier.size(16.dp))
                        Text(
                            text = "Hotkeys are currently SUSPENDED.",
                            style = MaterialTheme.typography.bodySmall,
                            color = Color(0xFFD97706),
                            fontWeight = FontWeight.Medium
                        )
                    }
                }
            }
        }

        // 4. Live Clicker Tester Diagnostic Card
        ExplorerCard(contentPadding = formFactor.cardPaddingDp) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                ResponsiveExplorerActionRow(
                    title = "Live Clicker Diagnostic Tester",
                    subtitle = if (testerOpen) {
                        "Listening... Press any presenter clicker button to inspect Android KeyCode & filtering."
                    } else {
                        "Verify your USB/Bluetooth presenter buttons before presenting."
                    },
                    isTightWidth = formFactor.isTightWidth
                ) {
                    Button(
                        onClick = {
                            testerOpen = !testerOpen
                            ClickerAccessibilityService.testerMode.set(testerOpen)
                            if (testerOpen) {
                                ClickerAccessibilityService.clearTesterEvents()
                            }
                        },
                        contentPadding = CompactExplorerButtonPadding
                    ) {
                        Text(
                            if (testerOpen) "Stop Tester" else "Launch Clicker Tester",
                            maxLines = 1,
                            softWrap = false
                        )
                    }
                }

                if (testerOpen) {
                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                    if (!a11yEnabled) {
                        Text(
                            text = "Note: Global Accessibility capture is currently OFF — only Activity focus keys or enabled Accessibility Service will appear.",
                            style = MaterialTheme.typography.bodySmall,
                            color = Color(0xFFD97706)
                        )
                    }
                    Surface(
                        shape = RoundedCornerShape(6.dp),
                        color = MaterialTheme.colorScheme.surfaceVariant,
                        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Column(
                            modifier = Modifier.padding(12.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            if (testerEvents.isEmpty()) {
                                Text(
                                    text = "Waiting for clicker key press (Configured: ${cfg.hwMuteHotkey})...",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            } else {
                                testerEvents.forEach { ev ->
                                    Row(
                                        modifier = Modifier.fillMaxWidth(),
                                        horizontalArrangement = Arrangement.SpaceBetween,
                                        verticalAlignment = Alignment.CenterVertically
                                    ) {
                                        Column(modifier = Modifier.weight(1f)) {
                                            Text(
                                                text = "${ev.keyCodeName} (${ev.displayName}) • ${ev.action}",
                                                style = MaterialTheme.typography.labelMedium,
                                                fontFamily = FontFamily.Monospace,
                                                fontWeight = FontWeight.Bold
                                            )
                                            Text(
                                                text = "${ev.decisionLabel} • ${ev.deviceName} (scan=${ev.scanCode})",
                                                style = MaterialTheme.typography.bodySmall,
                                                color = if (ev.consumed) Color(0xFF10B981) else MaterialTheme.colorScheme.onSurfaceVariant
                                            )
                                        }
                                    }
                                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    if (showCaptureDialog) {
        CaptureClickerButtonDialog(
            currentKey = cfg.hwMuteHotkey,
            lastCaptured = lastCapturedKey,
            onKeySelected = { keyCodeName ->
                ClickerAccessibilityService.captureNextKeyMode.set(false)
                app.configStore.update { it.copy(hwMuteHotkey = keyCodeName) }
                showCaptureDialog = false
            },
            onDismiss = {
                ClickerAccessibilityService.captureNextKeyMode.set(false)
                showCaptureDialog = false
            }
        )
    }

    if (showRestrictedGuideDialog) {
        RestrictedSettingsGuideDialog(
            packageName = context.packageName,
            onOpenAppInfo = {
                runCatching {
                    val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = Uri.parse("package:${context.packageName}")
                    }
                    context.startActivity(intent)
                }
            },
            onOpenAccessibility = {
                runCatching {
                    context.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                }
            },
            onDismiss = { showRestrictedGuideDialog = false }
        )
    }

    if (showShortcutDialog) {
        EditShortcutsDialog(
            initialToggle = cfg.toggleMuteShortcut,
            initialExit = cfg.exitShortcut,
            formFactor = formFactor,
            onSave = { t, e ->
                app.configStore.update {
                    it.copy(
                        toggleMuteShortcut = t.ifBlank { "Ctrl+F12" },
                        exitShortcut = e.ifBlank { "Alt+Shift+F12" }
                    )
                }
                showShortcutDialog = false
            },
            onDismiss = { showShortcutDialog = false }
        )
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun CaptureClickerButtonDialog(
    currentKey: String,
    lastCaptured: CapturedKeyEvent?,
    onKeySelected: (String) -> Unit,
    onDismiss: () -> Unit
) {
    val startSeq = remember { lastCaptured?.seq ?: 0L }

    DisposableEffect(Unit) {
        ClickerAccessibilityService.captureNextKeyMode.set(true)
        onDispose {
            ClickerAccessibilityService.captureNextKeyMode.set(false)
        }
    }

    LaunchedEffect(lastCaptured?.seq) {
        if (lastCaptured != null && lastCaptured.seq > startSeq) {
            onKeySelected(lastCaptured.keyCodeName)
        }
    }

    val formFactor = rememberFormFactor(com.saabithjiffry.presentersync.remote.config.DeviceProfileMode.AUTO)
    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Surface(
            modifier = Modifier
                .widthIn(max = 580.dp)
                .fillMaxWidth(formFactor.dialogWidthFraction)
                .heightIn(max = (formFactor.heightDp * formFactor.dialogMaxHeightFraction).dp)
                .padding(vertical = if (formFactor.isCompactHeight) 6.dp else 14.dp),
            shape = RoundedCornerShape(8.dp),
            color = MaterialTheme.colorScheme.surface,
            border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)
        ) {
            Column(modifier = Modifier.fillMaxWidth()) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 20.dp, vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = "Change Pointer Mute Button",
                            style = MaterialTheme.typography.titleLarge,
                            fontWeight = FontWeight.Bold
                        )
                        Text(
                            text = "Press the clicker button you want to dedicate to Muting, or choose below.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    IconButton(onClick = onDismiss) {
                        Icon(Icons.Default.Close, contentDescription = "Close")
                    }
                }
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

                Column(
                    modifier = Modifier
                        .weight(1f, fill = false)
                        .fillMaxWidth()
                        .verticalScroll(rememberScrollState())
                        .padding(horizontal = 20.dp, vertical = 14.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Surface(
                        shape = RoundedCornerShape(6.dp),
                        color = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.45f),
                        border = BorderStroke(1.dp, MaterialTheme.colorScheme.primary.copy(alpha = 0.5f)),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Row(
                            modifier = Modifier.padding(12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(10.dp)
                        ) {
                            Icon(Icons.Default.Keyboard, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                            Column {
                                Text(
                                    text = "Listening for Hardware Clicker Key Press...",
                                    style = MaterialTheme.typography.bodyMedium,
                                    fontWeight = FontWeight.SemiBold
                                )
                                Text(
                                    text = "Current button: ${ClickerMuteController.friendlyKeyLabel(currentKey)} ($currentKey)",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                    }

                    Text("Common Presenter Clicker Buttons", style = MaterialTheme.typography.labelLarge)
                    FlowRow(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        QUICK_CLICKER_KEYS.forEach { (keyName, label) ->
                            FilterChip(
                                selected = ClickerMuteController.normalizeKeyCodeName(currentKey) == keyName,
                                onClick = { onKeySelected(keyName) },
                                label = { Text(label) }
                            )
                        }
                    }
                }

                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 20.dp, vertical = 12.dp),
                    horizontalArrangement = Arrangement.End
                ) {
                    OutlinedButton(onClick = onDismiss) {
                        Text("Cancel")
                    }
                }
            }
        }
    }
}

@Composable
private fun RestrictedSettingsGuideDialog(
    packageName: String,
    onOpenAppInfo: () -> Unit,
    onOpenAccessibility: () -> Unit,
    onDismiss: () -> Unit
) {
    val formFactor = rememberFormFactor(com.saabithjiffry.presentersync.remote.config.DeviceProfileMode.AUTO)
    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Surface(
            modifier = Modifier
                .widthIn(max = 580.dp)
                .fillMaxWidth(formFactor.dialogWidthFraction)
                .heightIn(max = (formFactor.heightDp * formFactor.dialogMaxHeightFraction).dp)
                .padding(vertical = if (formFactor.isCompactHeight) 6.dp else 14.dp),
            shape = RoundedCornerShape(8.dp),
            color = MaterialTheme.colorScheme.surface,
            border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)
        ) {
            Column(modifier = Modifier.fillMaxWidth()) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 20.dp, vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        modifier = Modifier.weight(1f)
                    ) {
                        Icon(Icons.Default.Info, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                        Text(
                            text = "Android 13/14+ Accessibility Setup",
                            style = MaterialTheme.typography.titleLarge,
                            fontWeight = FontWeight.Bold
                        )
                    }
                    IconButton(onClick = onDismiss) {
                        Icon(Icons.Default.Close, contentDescription = "Close")
                    }
                }
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

                Column(
                    modifier = Modifier
                        .weight(1f, fill = false)
                        .fillMaxWidth()
                        .verticalScroll(rememberScrollState())
                        .padding(horizontal = 20.dp, vertical = 14.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Text(
                        text = "When installing via sideloaded APK on Android 13, 14, or 15, Android locks Accessibility Services with \"Restricted setting\" until unlocked once:",
                        style = MaterialTheme.typography.bodyMedium
                    )
                    Surface(
                        shape = RoundedCornerShape(6.dp),
                        color = MaterialTheme.colorScheme.surfaceVariant,
                        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Column(
                            modifier = Modifier.padding(12.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            Text("1. Tap \"Open App Info\" below.", style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.Medium)
                            Text("2. Tap the 3-dots menu (⋮) in the top-right corner.", style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.Medium)
                            Text("3. Select \"Allow restricted settings\" and confirm.", style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.Medium)
                            Text("4. Return and tap \"Open Accessibility\" -> Enable \"PresenterSync Hardware Clicker Filter\".", style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.Medium)
                        }
                    }
                    Text(
                        text = "IT / MDM Note: Or grant once over USB ADB: appops set $packageName ACCESS_RESTRICTED_SETTINGS allow",
                        style = MaterialTheme.typography.bodySmall,
                        fontFamily = FontFamily.Monospace,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }

                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 20.dp, vertical = 12.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    OutlinedButton(onClick = onOpenAppInfo, modifier = Modifier.weight(1f)) {
                        Text("1. Open App Info")
                    }
                    Button(onClick = onOpenAccessibility, modifier = Modifier.weight(1f)) {
                        Text("2. Open Accessibility")
                    }
                }
            }
        }
    }
}

@Composable
private fun EditShortcutsDialog(
    initialToggle: String,
    initialExit: String,
    formFactor: ResolvedFormFactor,
    onSave: (String, String) -> Unit,
    onDismiss: () -> Unit
) {
    var toggleTxt by remember { mutableStateOf(initialToggle) }
    var exitTxt by remember { mutableStateOf(initialExit) }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Surface(
            modifier = Modifier
                .widthIn(max = 520.dp)
                .fillMaxWidth(formFactor.dialogWidthFraction)
                .heightIn(max = (formFactor.heightDp * 0.92f).dp)
                .padding(vertical = 12.dp),
            shape = RoundedCornerShape(8.dp),
            color = MaterialTheme.colorScheme.surface,
            border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)
        ) {
            Column(modifier = Modifier.fillMaxWidth()) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 20.dp, vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        text = "Keyboard Shortcuts",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold
                    )
                    IconButton(onClick = onDismiss) {
                        Icon(Icons.Default.Close, contentDescription = "Close")
                    }
                }
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                Column(
                    modifier = Modifier
                        .weight(1f, fill = false)
                        .verticalScroll(rememberScrollState())
                        .padding(horizontal = 20.dp, vertical = 14.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    OutlinedTextField(
                        value = toggleTxt,
                        onValueChange = { toggleTxt = it },
                        label = { Text("Global Toggle Mute Shortcut") },
                        placeholder = { Text("Ctrl+F12") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                    OutlinedTextField(
                        value = exitTxt,
                        onValueChange = { exitTxt = it },
                        label = { Text("Stop Floating HUD Shortcut") },
                        placeholder = { Text("Alt+Shift+F12") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 20.dp, vertical = 12.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    OutlinedButton(onClick = onDismiss, modifier = Modifier.weight(1f)) {
                        Text("Cancel")
                    }
                    Button(onClick = { onSave(toggleTxt.trim(), exitTxt.trim()) }, modifier = Modifier.weight(1f)) {
                        Text("Save Shortcuts")
                    }
                }
            }
        }
    }
}
