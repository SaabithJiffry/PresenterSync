package com.saabithjiffry.presentersync.remote.ui.screens

import android.Manifest
import com.saabithjiffry.presentersync.remote.util.DiagnosticLogger
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.widget.Toast
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.material.icons.automirrored.filled.HelpOutline
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Search
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
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.TabRowDefaults
import androidx.compose.material3.TabRowDefaults.tabIndicatorOffset
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.SecureFlagPolicy
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.saabithjiffry.presentersync.remote.PresenterSyncRemoteApp
import com.saabithjiffry.presentersync.remote.config.AppConstants
import com.saabithjiffry.presentersync.remote.config.rememberFormFactor
import com.saabithjiffry.presentersync.remote.ui.theme.CompactExplorerButtonPadding
import com.saabithjiffry.presentersync.remote.ui.theme.ExplorerCard

private data class HudCalloutItem(
    val id: Int,
    val tag: String,
    val title: String,
    val subtitle: String,
    val details: String
)

private val REMOTE_HUD_CALLOUTS = listOf(
    HudCalloutItem(
        id = 1,
        tag = "[1] LIVE / MUTED",
        title = "1-Tier Mic Pill (LIVE / MUTED / OFFLINE)",
        subtitle = "Displays real-time mute status from Primary PC over LAN Bridge (:4456), OBS (:4455), or WAN Relay.",
        details = "• Green LIVE: Microphone open.\n• Red MUTED (Pulses): Muted on host; gently or aggressively breathes so you never talk into a muted mic.\n• Slate OFFLINE / AUTH ERR: Reconnecting or wrong OBS password."
    ),
    HudCalloutItem(
        id = 2,
        tag = "[2] Bubble Gestures",
        title = "Customizable Single / Double / Long / Very Long Press",
        subtitle = "Safe by default on Smart Boards: Single Tap ignores accidental touches; Long Press toggles Mute; Double Tap opens Quick Menu.",
        details = "• Open HUD Style -> Floating Bubble Multi-Gestures to map Single Tap, Double Tap, Long Press, and Very Long Press to Toggle Mute, Mute Only, Unmute Only, Open Quick Menu, Open Settings, Reconnect Host, or Hide Floating Pill.\n• Hold shows a glowing amber → blue progress arc with haptic feedback."
    ),
    HudCalloutItem(
        id = 3,
        tag = "[3] Drag & 14dp Snap",
        title = "Touchscreen Drag, Position Lock & 0.25x–5.0x Scale",
        subtitle = "Drag smoothly with finger or stylus, or enable 'Lock Pill Position' so sleeves/touches cannot knock it away.",
        details = "• 14dp Magnetic Snap aligns cleanly to Smart Board edges and screen centers, preserving aspect position across rotation.\n• Sizes scale up to 5.0x Gigantic for 65\"–86\" classroom 4K panels."
    ),
    HudCalloutItem(
        id = 4,
        tag = "[4] Menu & Host Deck",
        title = "Double-Tap Quick Menu, Host Deck & Screen Safety",
        subtitle = "Control Mute, Slide Deck, Host Recording, Lock Position, and Smart Board Screen-Awake directly from the overlay.",
        details = "• Double-tap the floating pill (default) for the Explorer Quick Context Menu with one-tap Mute, Lock Position, Prev/Next Slide, and Record controls.\n• Enable Click-Through, Idle Auto-Dim, Keep Screen Awake, or Hover Auto-Dodge in HUD Style; unlock Click-Through anytime via Foreground Notification or Android Quick Tile."
    )
)

private data class HelpTopic(
    val category: String,
    val title: String,
    val summary: String,
    val steps: String
)

private val HELP_TOPICS = listOf(
    HelpTopic(
        "Connection",
        "QR Code Instant Pairing",
        "Scan the QR in Windows Primary Host -> Settings -> Remote Companion Info.",
        "Open Connection Settings -> tap 'Scan QR'. CameraX + ZXing decodes offline with zero Google Play Services, auto-filling host IPs, OBS port, bridge port 4456, OBS password, and pairing code."
    ),
    HelpTopic(
        "Connection",
        "Session Pairing Code (XXX-XXX) for No-Camera Boards",
        "Connect any Android Smart Board over LAN even without a webcam.",
        "Read the 6-character code (e.g. K9P-4X7) shown in Windows Remote Companion Info -> enter it in 'Session Code' inside Connection Settings -> tap 'Pair Code'. Also works over OBS Bridge port 4456 for Mode 2 Zoom/Teams hosts!"
    ),
    HelpTopic(
        "Connection",
        "WAN Internet Relay Pairing (PS-XXXX-XXXX)",
        "Use across campus VLANs, separate routers, or mobile hotspots.",
        "Switch Network Mode to 'Different Networks (Internet)' on both Primary Windows app and Android Remote, then enter the PS-XXXX-XXXX code."
    ),
    HelpTopic(
        "Connection",
        "Simultaneous Multi-Remote Sync (Smart Board + Phone + PC)",
        "Run PresenterSync Remote on a Smart Board, presenter phone, and Windows PC together.",
        "Pair each device via QR Code or the 6-char Session Code (XXX-XXX). All connected Android and Windows remotes share live mute updates over Host Bridge (:4456), and you can watch connected devices live in Windows -> Remote Companion Info."
    ),
    HelpTopic(
        "Connection",
        "Adaptive Smart Board & Mobile Phone Profiles (Android 12+)",
        "Optimized layouts for both 65\"+ Smart Boards and compact phones.",
        "Select Auto, Smart Board, or Mobile Phone in Connection -> Device Form Factor Profile to tune dialog spacing and control sizing between Redmi Note 12 / Galaxy A07 phones and 65\" classroom Smart Boards."
    ),
    HelpTopic(
        "Floating HUD",
        "Floating Pill Over Whiteboards & Apps",
        "Stays visible above Smart Board note-taking, browser, or OPS screens.",
        "Requires 'Display over other apps' (SYSTEM_ALERT_WINDOW) plus persistent Foreground Service notification."
    ),
    HelpTopic(
        "Floating HUD",
        "Click-Through Mode & Emergency Unlock",
        "Passes all touches directly underneath the pill to your whiteboard ink.",
        "Turn ON 'Click-Through Pill Mode' in HUD Style or the Long-Press Quick Menu. To re-enable dragging/tapping later, tap 'Unlock Clicks' on the persistent notification or tap the Android Quick Settings Tile."
    ),
    HelpTopic(
        "Floating HUD",
        "Color Presets, Acoustic Chimes & 2s Banner",
        "5 Windows-matched color schemes + synthesized audio tones.",
        "Open HUD Style tab to switch between Standard, Colorblind Safe, OLED Stealth, Broadcast Tally, and Cyber Ocean, plus 880Hz↔520Hz chimes and the 2-second Mic: MUTED/LIVE banner."
    ),
    HelpTopic(
        "Floating HUD",
        "Floating Bubble Multi-Gestures & Position Lock",
        "Customize Single Tap, Double Tap, Long Press, and Very Long Press independently.",
        "Open HUD Style -> Floating Bubble Multi-Gestures. By default Single Tap is None (to avoid accidental board touches), Double Tap opens the Quick Menu, and Long Press (600ms) toggles mute. You can also set Long Press = Mute Only and Very Long Press = Unmute Only, and toggle 'Lock Pill Position' so touches never drag the bubble."
    ),
    HelpTopic(
        "Floating HUD",
        "Sector Z Subsystem — Locked [0 Credits]",
        "Dormant diagnostic channel on the floating badge and About hardware info.",
        "PresenterSync contains an unadvertised Sector Z subsystem that stays strictly locked (0 Credits) during classes and Smart Board sessions. Single taps inside the Quick Menu intentionally do nothing mid-lecture; curious operators sometimes inspect the About dialog header & telemetry pulse for diagnostic prompts."
    ),
    HelpTopic(
        "Pointer & Clicker",
        "Play Protect-Safe Smart Board & Phone Control",
        "Zero Accessibility permissions required — install directly with Play Protect enabled.",
        "PresenterSync Remote intentionally omits background Accessibility services so sideloaded APK installs aren't blocked. Keep your presenter clicker dongle plugged into the Primary Windows PC (which syncs live to Android) and control mute from Android using Floating Bubble Gestures (Long Press / Double Tap)."
    ),
    HelpTopic(
        "Pointer & Clicker",
        "Focused-Window Clicker & Keyboard Tester",
        "Test clicker keycodes or trigger shortcuts while PresenterSync Remote is open.",
        "Open Pointer & Keys tab to test USB/BT presenter keycodes in-app or configure focused-window mute & cough-hold keys."
    ),
    HelpTopic(
        "Connection",
        "Zero-Config Classroom UDP Discovery (:4457) & LAN/WAN Failover",
        "Auto-discover classroom hosts without typing IPs and auto-follow DHCP IP shifts.",
        "Tap 'Scan Classroom' in Guided Setup Wizard or Connection Setup to detect PresenterSync Host beacons broadcast on UDP :4457. Paired hostUuid lets Remotes automatically follow IP changes or switch smoothly between LAN and WAN Relay (PS-XXXX-XXXX)."
    ),
    HelpTopic(
        "Connection",
        "Guided First-Run Setup Wizard",
        "Step-by-step checklist for permissions, Classroom pairing & HUD verification.",
        "Automatically greets new installs on Status & HUD (or open anytime via 'Guided Setup Wizard' button). Verifies Display Over Other Apps, API 33+ Notifications, Classroom LAN scan / QR pairing, and 1-tap Floating HUD test."
    ),
    HelpTopic(
        "Director Deck",
        "OBS Scenes, Split Chapter, Standby BRB, Countdown Timer & Stage Nudge",
        "Control scene transitions, split recording markers, standby curtain & presenter countdowns.",
        "Use the Director Deck card on Status & HUD (or Long-Press / Double-Tap Quick Menu) to switch OBS scenes, Pause or Split recording, toggle Standby BRB, start 5/10/15/45m synchronized timers, or send unobtrusive Stage Nudges to the host."
    ),
    HelpTopic(
        "Floating HUD",
        "Push-to-Talk Mode & Custom Hex Theme Colors",
        "Hold pill to speak while muted by default, and customize #RRGGBB live/muted colors.",
        "Enable Push-to-Talk in Pointer & Keys so your mic stays MUTED until holding down the floating pill (or clicker hotkey) >= 300ms. Open HUD Style to customize Custom Live Hex & Custom Muted Hex colors with automatic contrast."
    ),
    HelpTopic(
        "Troubleshooting",
        "Session Locked After 5 Wrong Codes / Wrong Password",
        "Primary Host protects Session Codes with a 30s rate limit.",
        "If 5 incorrect codes are submitted within 30s, wait 30 seconds or click 'New' in Windows Host -> Remote Companion Info to rotate the Session Code & QR immediately."
    ),
    HelpTopic(
        "Floating HUD",
        "Smart Board High-DPI Canvas & Pill Mini-Badges",
        "Crisp 0.5x–5.0x optical stroke scaling with Timer, BRB, REC & Voice Alert badges.",
        "MicPillCanvasView scales borders sub-linearly (<= 3.0dp) with tonal sheen and knockout mute slash. Enable 'Show Pill Mini-Badges' in HUD Style to display active Timer (MM:SS / -MM:SS), BRB, REC, and amber speaking-while-muted border alerts."
    ),
    HelpTopic(
        "Director Deck",
        "Full-Screen OLED Podium Deck & 2x1 Home Screen Widget",
        "Pure #000000 lectern controller with Speaker Notes + 1-tap Home Screen Widget.",
        "Tap 'Podium Deck (Full-Screen OLED Mode)' on Status & HUD for a keep-screen-on lectern view with oversized Mute/Unmute, OBS Transition, Prev/Next/F5 Slides + Speaker Notes, Timer, BRB, and Quick-Nudge chips. Add the 2x1 PresenterSync widget to your Android Home Screen for instant LIVE/MUTED/REC status & 1-tap mute."
    ),
    HelpTopic(
        "Pointer & Keys",
        "Background BT Media Clicker & Silent Haptic Alerts",
        "Control mute/slides with BT media buttons (screen off) and feel silent vibration cues.",
        "Enable 'Background Bluetooth Media Clicker' in Pointer & Keys to capture Play/Pause, Next, Previous, and Volume buttons via MediaSession even with the screen off. Enable 'Silent Haptic / Vibration Alerts' in HUD Style for distinct waveform patterns on Mute, Unmute, 2m Warning, Overtime, Voice-While-Muted, and Stage Nudge."
    ),
    HelpTopic(
        "Connection",
        "AES-256-GCM WAN Relay, Direct OBS Failover & Browser Web Remote",
        "Encrypted WAN Relay, automatic :4455 fallback / :4456 re-promotion, and browser UI.",
        "WAN Relay payloads are encrypted end-to-end with AES-256-GCM (96-bit IV + 128-bit tag) and support a custom self-hosted Relay Base URL. If Host Bridge (:4456) drops, Android falls back to Direct OBS (:4455) within 1.8s and auto-re-promotes every 8s. Any browser (iPad/Mac/Linux) can also open http://<host-ip>:4456/ for the zero-install Web Remote."
    ),
    HelpTopic(
        "Troubleshooting",
        "Battery Optimization, Share Pairing QR, Dual Probe & Error Log",
        "Keep background HUD/BT clicker alive, share host QR, and export diagnostics.",
        "In Connection Settings, use the Battery Optimization banner if Android restricts background networking, tap 'Share Pairing QR' to pair a second device, or tap 'Test Connection' for a unified :4456/health + :4455 probe. Open Diagnostics in Help Center to search, copy, or clear the persistent Error Log."
    ),
    HelpTopic(
        "Connection",
        "Web Remote Tap-to-Mute, Clean Disconnect & Direct OBS :4455 Fallback",
        "Full browser companion resilience with branding, About drawer, and automatic failover.",
        "Open http://<host-ip>:4456/ in any browser for tap-to-mute control, branding & About drawer, Clean Disconnect (clears session token cleanly), automatic reconnect, and Direct OBS :4455 fallback when Host Bridge is unavailable. Windows Host also supports 1.25x HUD scale, Capture Keystroke buttons, True OBS Recording timer sync, and perimeter hold bars on Mic, Rec, and Studio pills."
    )
)

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun HelpCenterDialog(
    app: PresenterSyncRemoteApp,
    onDismiss: () -> Unit
) {
    val context = LocalContext.current
    val cfg by app.configStore.config.collectAsStateWithLifecycle()
    val conn by app.connectionManager.uiState.collectAsStateWithLifecycle()
    val formFactor = rememberFormFactor(cfg.deviceProfileMode)

    var tabIdx by remember { mutableIntStateOf(0) }
    var selectedCalloutId by remember { mutableIntStateOf(1) }
    var searchQuery by remember { mutableStateOf("") }
    var selectedCat by remember { mutableStateOf("All") }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false, securePolicy = SecureFlagPolicy.SecureOn)
    ) {
        Surface(
            modifier = Modifier
                .widthIn(max = formFactor.dialogMaxWidthDp)
                .fillMaxWidth(formFactor.dialogWidthFraction)
                .heightIn(max = (formFactor.heightDp * formFactor.dialogMaxHeightFraction).dp)
                .padding(vertical = if (formFactor.isCompactHeight) 6.dp else 12.dp),
            shape = RoundedCornerShape(8.dp),
            color = MaterialTheme.colorScheme.background,
            border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)
        ) {
            Column(modifier = Modifier.fillMaxWidth()) {
                // Header
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(MaterialTheme.colorScheme.surface)
                        .padding(horizontal = 18.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                        modifier = Modifier.weight(1f)
                    ) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.HelpOutline,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary
                        )
                        Column {
                            Text(
                                text = "PresenterSync Help & Smart Board Diagnostics",
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.SemiBold
                            )
                            Text(
                                text = "1-Tier Android Companion v${AppConstants.APP_VERSION}",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                    IconButton(onClick = onDismiss) {
                        Icon(Icons.Default.Close, contentDescription = "Close Help")
                    }
                }
                HorizontalDivider(color = MaterialTheme.colorScheme.outline)

                TabRow(
                    selectedTabIndex = tabIdx,
                    containerColor = MaterialTheme.colorScheme.surface,
                    contentColor = MaterialTheme.colorScheme.primary,
                    divider = { HorizontalDivider(color = MaterialTheme.colorScheme.outline) },
                    indicator = { positions ->
                        if (tabIdx < positions.size) {
                            TabRowDefaults.SecondaryIndicator(
                                modifier = Modifier.tabIndicatorOffset(positions[tabIdx]),
                                height = 2.dp,
                                color = MaterialTheme.colorScheme.primary
                            )
                        }
                    }
                ) {
                    val tabLabels = if (formFactor.isTightWidth) {
                        listOf("Overview", "Search", "Status")
                    } else {
                        listOf("Overview & Diagram", "Search Help", "Live Status")
                    }
                    tabLabels.forEachIndexed { idx, title ->
                        Tab(
                            selected = tabIdx == idx,
                            onClick = { tabIdx = idx },
                            text = {
                                Text(
                                    title,
                                    maxLines = 1,
                                    softWrap = false,
                                    overflow = TextOverflow.Ellipsis,
                                    fontWeight = FontWeight.Medium
                                )
                            }
                        )
                    }
                }

                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f, fill = false)
                        .verticalScroll(rememberScrollState())
                        .padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    when (tabIdx) {
                        0 -> HelpOverviewTab(
                            selectedId = selectedCalloutId,
                            onSelectId = { selectedCalloutId = it }
                        )
                        1 -> HelpSearchTab(
                            query = searchQuery,
                            onQueryChange = { searchQuery = it },
                            selectedCat = selectedCat,
                            onSelectCat = { selectedCat = it }
                        )
                        else -> HelpDiagnosticsTab(
                            context = context,
                            cfg = cfg,
                            conn = conn,
                            onRunTrace = { app.connectionManager.traceConnectionSteps() }
                        )
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun HelpOverviewTab(
    selectedId: Int,
    onSelectId: (Int) -> Unit
) {
    val selected = REMOTE_HUD_CALLOUTS.firstOrNull { it.id == selectedId } ?: REMOTE_HUD_CALLOUTS.first()

    ExplorerCard(contentPadding = 16) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(
                text = "Interactive 1-Tier Floating Mic HUD Anatomy",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold
            )

            // Schematic Canvas showing the 1-tier floating pill + gesture callout markers
            Surface(
                shape = RoundedCornerShape(6.dp),
                color = Color(0xFF1A1D24),
                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline),
                modifier = Modifier
                    .fillMaxWidth()
                    .height(110.dp)
            ) {
                Canvas(modifier = Modifier.fillMaxWidth().height(110.dp)) {
                    val pillW = size.width * 0.42f
                    val pillH = 44.dp.toPx()
                    val left = (size.width - pillW) / 2f
                    val top = (size.height - pillH) / 2f

                    val pillColor = when (selectedId) {
                        2 -> Color(0xFFEF4444)
                        else -> Color(0xFF22C55E)
                    }
                    drawRoundRect(
                        color = pillColor.copy(alpha = if (selectedId == 4) 0.35f else 1f),
                        topLeft = Offset(left, top),
                        size = Size(pillW, pillH),
                        cornerRadius = CornerRadius(10.dp.toPx(), 10.dp.toPx())
                    )
                    drawRoundRect(
                        color = Color(0xFF60CDFF),
                        topLeft = Offset(left - 2.dp.toPx(), top - 2.dp.toPx()),
                        size = Size(pillW + 4.dp.toPx(), pillH + 4.dp.toPx()),
                        cornerRadius = CornerRadius(12.dp.toPx(), 12.dp.toPx()),
                        style = Stroke(width = 2.dp.toPx())
                    )
                    // 4 Callout dots [1]..[4] around the schematic pill
                    val markers = listOf(
                        1 to Offset(left + 14.dp.toPx(), top + pillH / 2f),
                        2 to Offset(left + pillW / 2f, top + pillH / 2f),
                        3 to Offset(left + pillW - 14.dp.toPx(), top + pillH / 2f),
                        4 to Offset(left + pillW + 20.dp.toPx(), top + 8.dp.toPx())
                    )
                    markers.forEach { (id, pt) ->
                        val active = id == selectedId
                        drawCircle(
                            color = if (active) Color(0xFF60CDFF) else Color(0xFFFFFFFF),
                            radius = if (active) 7.dp.toPx() else 5.dp.toPx(),
                            center = pt
                        )
                    }
                }
            }

            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                REMOTE_HUD_CALLOUTS.forEach { item ->
                    FilterChip(
                        selected = item.id == selectedId,
                        onClick = { onSelectId(item.id) },
                        label = { Text(item.tag) }
                    )
                }
            }

            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
            Text(selected.title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            Text(selected.subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(selected.details, style = MaterialTheme.typography.bodySmall)
        }
    }

    ExplorerCard(contentPadding = 16) {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text("3-Step Smart Board Quick Setup", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            Text(
                text = "1. On Windows Host PC, open Tray -> Settings -> Remote Companion Info...\n" +
                    "2. In Android Remote, tap Settings -> Scan QR (or enter the 6-char Session Code / Manual IP).\n" +
                    "3. Grant Display Over Other Apps (and Notifications on Android 13+) — no Accessibility permission required.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun HelpSearchTab(
    query: String,
    onQueryChange: (String) -> Unit,
    selectedCat: String,
    onSelectCat: (String) -> Unit
) {
    val cats = listOf("All", "Connection", "Floating HUD", "Pointer & Clicker", "Troubleshooting")
    OutlinedTextField(
        value = query,
        onValueChange = onQueryChange,
        label = { Text("Search Help Topics (e.g. QR, 4456, Click-Through, Restricted)") },
        leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
        singleLine = true,
        modifier = Modifier.fillMaxWidth()
    )
    FlowRow(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        cats.forEach { cat ->
            FilterChip(
                selected = selectedCat == cat,
                onClick = { onSelectCat(cat) },
                label = { Text(cat) }
            )
        }
    }
    val q = query.trim().lowercase()
    val matches = HELP_TOPICS.filter { topic ->
        val catOk = selectedCat == "All" || topic.category == selectedCat
        val qOk = q.isEmpty() ||
            topic.title.lowercase().contains(q) ||
            topic.summary.lowercase().contains(q) ||
            topic.steps.lowercase().contains(q)
        catOk && qOk
    }
    if (matches.isEmpty()) {
        ExplorerCard(contentPadding = 16) {
            Text("No topics matched \"$query\".", style = MaterialTheme.typography.bodyMedium)
        }
    } else {
        matches.forEach { item ->
            ExplorerCard(contentPadding = 14) {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        text = "${item.category.uppercase()} • ${item.title}",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(item.summary, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary)
                    Text(item.steps, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

@Composable
private fun HelpDiagnosticsTab(
    context: Context,
    cfg: com.saabithjiffry.presentersync.remote.config.RemoteConfig,
    conn: com.saabithjiffry.presentersync.remote.network.ConnectionUiState,
    onRunTrace: () -> List<String> = { emptyList() }
) {
    var traceSteps by remember { mutableStateOf<List<String>>(emptyList()) }
    val overlayOk = Settings.canDrawOverlays(context)
    val notifOk = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    } else {
        true
    }

    ExplorerCard(contentPadding = 16) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("Permissions Readiness", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

            DiagnosticStatusRow("Overlay (SYSTEM_ALERT_WINDOW)", overlayOk) {
                runCatching {
                    context.startActivity(
                        Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:${context.packageName}"))
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                }
            }
            DiagnosticStatusRow("Notifications Permission", notifOk) {
                runCatching {
                    context.startActivity(
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${context.packageName}"))
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                }
            }
            DiagnosticStatusRow("Play Protect-Safe (No Accessibility)", true) {}
        }
    }

    ExplorerCard(contentPadding = 16) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("Live Connection & Configuration Snapshot", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
            ProfileLine("App Version", "v${AppConstants.APP_VERSION}")
            ProfileLine("Android API", "API ${Build.VERSION.SDK_INT} (${Build.MODEL})")
            ProfileLine("Transport", if (conn.connected) "${conn.transportName} -> ${conn.activeHost}" else conn.connStatus.name)
            ProfileLine("Mic State", if (conn.isMuted) "MUTED" else "LIVE")
            ProfileLine("Session Code", cfg.sessionPairingCode.ifBlank { "Not paired yet" })
            ProfileLine("Bridge / OBS Ports", "${cfg.bridgePort} / ${cfg.hostPort}")
            ProfileLine("Audio Source", cfg.targetMicName)
            ProfileLine("Clicker Key", "${cfg.hwMuteHotkey} (Cough=${cfg.enablePushToMute})")
            ProfileLine("HUD Style", "${cfg.hudColorPreset} • ${cfg.indicatorScale}x • ClickThru=${cfg.hudClickThrough}")

            Spacer(Modifier.height(4.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                OutlinedButton(
                    onClick = { traceSteps = onRunTrace() },
                    contentPadding = CompactExplorerButtonPadding,
                    modifier = Modifier.weight(1f)
                ) {
                    Text("5-Step Trace", maxLines = 1, softWrap = false, overflow = TextOverflow.Ellipsis)
                }
                OutlinedButton(
                    onClick = {
                        val tail = DiagnosticLogger.getRecentLogTail(12000).ifBlank { "(No diagnostic log entries yet)" }
                        val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
                        cm?.setPrimaryClip(ClipData.newPlainText("PresenterSync Log Tail", tail))
                        Toast.makeText(context, "Recent log tail copied", Toast.LENGTH_SHORT).show()
                    },
                    contentPadding = CompactExplorerButtonPadding,
                    modifier = Modifier.weight(1f)
                ) {
                    Text("Copy Log Tail", maxLines = 1, softWrap = false, overflow = TextOverflow.Ellipsis)
                }
            }
            if (traceSteps.isNotEmpty()) {
                Text(
                    text = traceSteps.joinToString("\n"),
                    style = MaterialTheme.typography.bodySmall,
                    fontFamily = FontFamily.Monospace,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Button(
                onClick = {
                    val summary = buildString {
                        appendLine("PresenterSync Remote v${AppConstants.APP_VERSION} (API ${Build.VERSION.SDK_INT} / ${Build.MODEL})")
                        appendLine("Overlay=$overlayOk | Notif=$notifOk | PlayProtectSafe=true")
                        appendLine("Status=${conn.connStatus} | Connected=${conn.connected} | Host=${conn.activeHost} | Transport=${conn.transportName}")
                        appendLine("Mic=${if (conn.isMuted) "MUTED" else "LIVE"} | Source=${cfg.targetMicName} | Mode=${cfg.networkMode}")
                        appendLine("Key=${cfg.hwMuteHotkey} | PointerMute=${cfg.enablePointerMute} | Cough=${cfg.enablePushToMute}")
                    }
                    val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
                    cm?.setPrimaryClip(ClipData.newPlainText("PresenterSync Diagnostics", summary))
                    Toast.makeText(context, "Diagnostics copied to clipboard", Toast.LENGTH_SHORT).show()
                },
                modifier = Modifier.fillMaxWidth()
            ) {
                Icon(Icons.Default.ContentCopy, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text("Copy Diagnostic Summary")
            }
        }
    }
}

@Composable
private fun DiagnosticStatusRow(
    title: String,
    ok: Boolean,
    onAction: () -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.weight(1f)
        ) {
            Icon(
                imageVector = if (ok) Icons.Default.CheckCircle else Icons.Default.Warning,
                contentDescription = null,
                tint = if (ok) Color(0xFF10B981) else Color(0xFFD97706),
                modifier = Modifier.size(18.dp)
            )
            Column {
                Text(title, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
                Text(
                    text = if (ok) "Ready" else "Action needed",
                    style = MaterialTheme.typography.bodySmall,
                    color = if (ok) Color(0xFF10B981) else Color(0xFFD97706)
                )
            }
        }
        OutlinedButton(onClick = onAction, contentPadding = CompactExplorerButtonPadding) {
            Text(if (ok) "Open" else "Fix", style = MaterialTheme.typography.labelMedium, maxLines = 1)
        }
    }
}
