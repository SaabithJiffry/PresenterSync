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
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.saabithjiffry.presentersync.remote.PresenterSyncRemoteApp
import com.saabithjiffry.presentersync.remote.config.AppConstants
import com.saabithjiffry.presentersync.remote.config.DeepLinkParser
import com.saabithjiffry.presentersync.remote.config.NetworkMode
import com.saabithjiffry.presentersync.remote.input.ClickerMuteController
import com.saabithjiffry.presentersync.remote.network.ConnStatus
import com.saabithjiffry.presentersync.remote.service.CapturedKeyEvent
import com.saabithjiffry.presentersync.remote.service.ClickerAccessibilityService
import com.saabithjiffry.presentersync.remote.service.FloatingHudForegroundService
import com.saabithjiffry.presentersync.remote.ui.theme.ExplorerCard
import com.saabithjiffry.presentersync.remote.ui.theme.PresenterSyncTheme
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {

    private var pendingDeepLink by mutableStateOf<Pair<Long, String>?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        captureDeepLink(intent)
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

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val keyName = KeyEvent.keyCodeToString(event.keyCode)
        val navIgnored = event.keyCode == KeyEvent.KEYCODE_BACK ||
            event.keyCode == KeyEvent.KEYCODE_HOME ||
            event.keyCode == KeyEvent.KEYCODE_POWER
        if (!navIgnored && event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
            if (ClickerAccessibilityService.captureNextKeyMode.getAndSet(false)) {
                ClickerAccessibilityService.recordUiCapturedEvent(
                    CapturedKeyEvent(
                        seq = System.nanoTime(),
                        keyCode = event.keyCode,
                        keyCodeName = keyName,
                        displayName = ClickerMuteController.friendlyKeyLabel(keyName),
                        scanCode = event.scanCode,
                        deviceName = event.device?.name ?: "Focused Window",
                        action = "DOWN",
                        decisionLabel = "Captured New Mute Key (Window)",
                        consumed = true,
                        timestampMs = System.currentTimeMillis()
                    )
                )
                return true
            }
            if (ClickerAccessibilityService.testerMode.get()) {
                val cfg = (application as PresenterSyncRemoteApp).configStore.current
                val matched = ClickerMuteController.normalizeKeyCodeName(cfg.hwMuteHotkey) ==
                    ClickerMuteController.normalizeKeyCodeName(keyName)
                ClickerAccessibilityService.recordUiCapturedEvent(
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
        }
        return super.dispatchKeyEvent(event)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun RemoteDashboardScreen(
    app: PresenterSyncRemoteApp,
    pendingDeepLink: Pair<Long, String>? = null,
    onConsumeDeepLink: () -> Unit = {},
    onRequestOverlayPermission: () -> Unit
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val scope = rememberCoroutineScope()

    val cfg by app.configStore.config.collectAsStateWithLifecycle()
    val conn by app.connectionManager.uiState.collectAsStateWithLifecycle()

    var hasOverlayPerm by remember { mutableStateOf(Settings.canDrawOverlays(context)) }
    var hasNotifPerm by remember {
        mutableStateOf(
            Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                ContextCompat.checkSelfPermission(
                    context,
                    Manifest.permission.POST_NOTIFICATIONS
                ) == PackageManager.PERMISSION_GRANTED
        )
    }

    val notifLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        hasNotifPerm = granted || Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU
    }

    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                hasOverlayPerm = Settings.canDrawOverlays(context)
                hasNotifPerm = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                    ContextCompat.checkSelfPermission(
                        context,
                        Manifest.permission.POST_NOTIFICATIONS
                    ) == PackageManager.PERMISSION_GRANTED
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    var showConnectionDialog by rememberSaveable { mutableStateOf(cfg.firstRun) }
    var showQuickQrScanner by rememberSaveable { mutableStateOf(false) }
    var showHelpDialog by rememberSaveable { mutableStateOf(false) }
    var showAboutDialog by rememberSaveable { mutableStateOf(false) }
    var selectedTabIndex by rememberSaveable { mutableStateOf(0) }

    LaunchedEffect(pendingDeepLink) {
        val incoming = pendingDeepLink ?: return@LaunchedEffect
        val parsed = DeepLinkParser.parse(incoming.second)
        onConsumeDeepLink()
        if (parsed == null) {
            Toast.makeText(
                context,
                "PresenterSync: Unrecognized pairing URI.",
                Toast.LENGTH_SHORT
            ).show()
            return@LaunchedEffect
        }
        showConnectionDialog = false
        app.connectionManager.applyDeepLinkAsync(parsed)
    }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            Column {
                TopAppBar(
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = MaterialTheme.colorScheme.surface,
                        titleContentColor = MaterialTheme.colorScheme.onSurface
                    ),
                    title = {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("PresenterSync Remote", fontWeight = FontWeight.SemiBold)
                            Spacer(Modifier.width(10.dp))
                            Surface(
                                shape = RoundedCornerShape(4.dp),
                                color = MaterialTheme.colorScheme.surfaceVariant,
                                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)
                            ) {
                                Text(
                                    text = "v${AppConstants.APP_VERSION}",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier.padding(horizontal = 7.dp, vertical = 2.dp)
                                )
                            }
                        }
                    },
                    actions = {
                        IconButton(onClick = { showQuickQrScanner = true }) {
                            Icon(Icons.Default.QrCodeScanner, contentDescription = "Scan Host QR")
                        }
                        IconButton(onClick = { showHelpDialog = true }) {
                            Icon(Icons.AutoMirrored.Filled.HelpOutline, contentDescription = "Help & Diagnostics")
                        }
                        IconButton(onClick = { showAboutDialog = true }) {
                            Icon(Icons.Default.Info, contentDescription = "About & Updates")
                        }
                        IconButton(onClick = { showConnectionDialog = true }) {
                            Icon(Icons.Default.Settings, contentDescription = "Connection Settings")
                        }
                    }
                )
                TabRow(
                    selectedTabIndex = selectedTabIndex,
                    containerColor = MaterialTheme.colorScheme.surface,
                    contentColor = MaterialTheme.colorScheme.primary,
                    divider = { HorizontalDivider(color = MaterialTheme.colorScheme.outline) },
                    indicator = { tabPositions ->
                        if (selectedTabIndex < tabPositions.size) {
                            TabRowDefaults.SecondaryIndicator(
                                modifier = Modifier.tabIndicatorOffset(tabPositions[selectedTabIndex]),
                                height = 2.dp,
                                color = MaterialTheme.colorScheme.primary
                            )
                        }
                    }
                ) {
                    Tab(
                        selected = selectedTabIndex == 0,
                        onClick = { selectedTabIndex = 0 },
                        text = {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(6.dp)
                            ) {
                                Icon(Icons.Default.Mic, contentDescription = null, modifier = Modifier.size(16.dp))
                                Text("Status & HUD", maxLines = 1, fontWeight = FontWeight.Medium)
                            }
                        }
                    )
                    Tab(
                        selected = selectedTabIndex == 1,
                        onClick = { selectedTabIndex = 1 },
                        text = {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(6.dp)
                            ) {
                                Icon(Icons.Default.Layers, contentDescription = null, modifier = Modifier.size(16.dp))
                                Text("HUD Style", maxLines = 1, fontWeight = FontWeight.Medium)
                            }
                        }
                    )
                    Tab(
                        selected = selectedTabIndex == 2,
                        onClick = { selectedTabIndex = 2 },
                        text = {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(6.dp)
                            ) {
                                Icon(Icons.Default.Keyboard, contentDescription = null, modifier = Modifier.size(16.dp))
                                Text("Pointer & Keys", maxLines = 1, fontWeight = FontWeight.Medium)
                            }
                        }
                    )
                }
            }
        }
    ) { innerPadding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
            contentAlignment = Alignment.TopCenter
        ) {
            if (selectedTabIndex == 1) {
                HudAppearanceScreen(app = app)
            } else if (selectedTabIndex == 2) {
                PointerSettingsScreen(app = app)
            } else {
            Column(
                modifier = Modifier
                    .widthIn(max = 760.dp)
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                if (!hasOverlayPerm) {
                    PermissionWarningCard(
                        icon = Icons.Default.Layers,
                        title = "Display Over Other Apps Required",
                        description = "Enable overlay permission so the floating Mic pill stays visible over smart board apps and slides.",
                        actionLabel = "Grant Overlay",
                        onClick = onRequestOverlayPermission
                    )
                }

                if (!hasNotifPerm && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    PermissionWarningCard(
                        icon = Icons.Default.Notifications,
                        title = "Notification Permission Recommended",
                        description = "Allows persistent background status & one-tap Mute/Stop actions while PresenterSync Remote runs.",
                        actionLabel = "Allow Notifications",
                        onClick = { notifLauncher.launch(Manifest.permission.POST_NOTIFICATIONS) }
                    )
                }

                // Live status & Floating Service Card
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

                ExplorerCard(contentPadding = 18) {
                    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
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

                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(10.dp)
                        ) {
                            if (!conn.serviceRunning) {
                                Button(
                                    onClick = {
                                        if (!Settings.canDrawOverlays(context)) {
                                            onRequestOverlayPermission()
                                        } else {
                                            FloatingHudForegroundService.startService(context)
                                        }
                                    },
                                    modifier = Modifier.weight(1f)
                                ) {
                                    Icon(Icons.Default.PlayArrow, contentDescription = null)
                                    Spacer(Modifier.width(6.dp))
                                    Text("Start Floating HUD")
                                }
                            } else {
                                Button(
                                    onClick = { app.connectionManager.toggleMuteFromHud() },
                                    colors = ButtonDefaults.buttonColors(
                                        containerColor = if (conn.isMuted) Color(0xFFDC2626) else Color(0xFF10B981)
                                    ),
                                    modifier = Modifier.weight(1f)
                                ) {
                                    Icon(
                                        if (conn.isMuted) Icons.Default.MicOff else Icons.Default.Mic,
                                        contentDescription = null
                                    )
                                    Spacer(Modifier.width(6.dp))
                                    Text(if (conn.isMuted) "Unmute Mic" else "Mute Mic")
                                }

                                OutlinedButton(
                                    onClick = { FloatingHudForegroundService.stopService(context) },
                                    modifier = Modifier.weight(1f)
                                ) {
                                    Icon(Icons.Default.Stop, contentDescription = null)
                                    Spacer(Modifier.width(6.dp))
                                    Text("Stop HUD")
                                }
                            }
                        }

                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(10.dp)
                        ) {
                            OutlinedButton(
                                onClick = { showConnectionDialog = true },
                                modifier = Modifier.weight(1f)
                            ) {
                                Icon(Icons.Default.Settings, contentDescription = null)
                                Spacer(Modifier.width(6.dp))
                                Text("Connection Setup")
                            }
                            OutlinedButton(
                                onClick = {
                                    if (conn.serviceRunning) {
                                        FloatingHudForegroundService.startService(
                                            context,
                                            FloatingHudForegroundService.ACTION_RECONNECT
                                        )
                                    } else {
                                        app.connectionManager.reconnectNow()
                                    }
                                },
                                modifier = Modifier.weight(1f)
                            ) {
                                Icon(Icons.Default.Refresh, contentDescription = null)
                                Spacer(Modifier.width(6.dp))
                                Text("Reconnect")
                            }
                        }

                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(10.dp)
                        ) {
                            OutlinedButton(
                                onClick = { showQuickQrScanner = true },
                                modifier = Modifier.weight(1f)
                            ) {
                                Icon(Icons.Default.QrCodeScanner, contentDescription = null)
                                Spacer(Modifier.width(6.dp))
                                Text("Scan QR")
                            }
                            OutlinedButton(
                                onClick = { showHelpDialog = true },
                                modifier = Modifier.weight(1f)
                            ) {
                                Icon(Icons.AutoMirrored.Filled.HelpOutline, contentDescription = null)
                                Spacer(Modifier.width(6.dp))
                                Text("Help")
                            }
                            OutlinedButton(
                                onClick = { showAboutDialog = true },
                                modifier = Modifier.weight(1f)
                            ) {
                                Icon(Icons.Default.Info, contentDescription = null)
                                Spacer(Modifier.width(6.dp))
                                Text("About")
                            }
                        }
                    }
                }

                // Quick HUD toggles card (Windows 11 Settings Expander style)
                ExplorerCard(contentPadding = 18) {
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
                            Text("Show Floating Indicator", style = MaterialTheme.typography.bodyMedium)
                            Switch(
                                checked = cfg.showIndicator,
                                onCheckedChange = { enabled ->
                                    app.configStore.update { it.copy(showIndicator = enabled) }
                                }
                            )
                        }
                        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Text("Show Status Text (LIVE / MUTED)", style = MaterialTheme.typography.bodyMedium)
                            Switch(
                                checked = cfg.showText,
                                onCheckedChange = { enabled ->
                                    app.configStore.update { it.copy(showText = enabled) }
                                }
                            )
                        }
                        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                text = if (cfg.savedX < 0) "Position: Bottom-Right Default"
                                else "Position: (${cfg.savedX}, ${cfg.savedY})",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                            OutlinedButton(onClick = { app.configStore.resetPosition() }) {
                                Text("Reset Position")
                            }
                        }
                    }
                }

                // Active Profile Summary Card
                ExplorerCard(contentPadding = 18) {
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(
                            text = "Current Connection Profile",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold
                        )
                        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                        Spacer(Modifier.height(2.dp))
                        ProfileLine("Mode", cfg.networkMode.label)
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
            } // end Status & HUD tab
        }
    }

    if (showConnectionDialog) {
        ConnectionSettingsDialog(
            initialConfig = cfg,
            configStore = app.configStore,
            connectionManager = app.connectionManager,
            onDismiss = {
                if (cfg.firstRun) {
                    app.configStore.update { it.copy(firstRun = false) }
                }
                showConnectionDialog = false
            },
            onSaved = { showConnectionDialog = false }
        )
    }

    if (showQuickQrScanner) {
        QrScannerDialog(
            onPayloadScanned = { payload ->
                showQuickQrScanner = false
                scope.launch {
                    val msg = app.connectionManager.applyDeepLinkPayload(payload)
                    Toast.makeText(context, msg, Toast.LENGTH_LONG).show()
                }
            },
            onDismiss = { showQuickQrScanner = false }
        )
    }

    if (showHelpDialog) {
        HelpCenterDialog(
            app = app,
            onDismiss = { showHelpDialog = false }
        )
    }

    if (showAboutDialog) {
        AboutUpdateDialog(
            httpClient = app.connectionManager.sharedHttpClient,
            onDismiss = { showAboutDialog = false }
        )
    }
}

@Composable
private fun PermissionWarningCard(
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
