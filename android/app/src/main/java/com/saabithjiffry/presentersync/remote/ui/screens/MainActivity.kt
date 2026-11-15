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

class MainActivity : ComponentActivity() {

    private var pendingDeepLink by mutableStateOf<Pair<Long, String>?>(null)
    private val focusedKeyController = ClickerMuteController()

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        captureDeepLink(intent)
        handleAutoStartIntent(intent)
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
        handleAutoStartIntent(intent)
    }

    private fun handleAutoStartIntent(intent: Intent?) {
        if (intent?.getBooleanExtra(EXTRA_AUTO_START_HUD, false) == true) {
            intent.removeExtra(EXTRA_AUTO_START_HUD)
            if (Settings.canDrawOverlays(this)) {
                FloatingHudForegroundService.startService(this)
            }
        }
    }

    companion object {
        const val EXTRA_AUTO_START_HUD = "com.saabithjiffry.presentersync.remote.EXTRA_AUTO_START_HUD"
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
        val app = application as PresenterSyncRemoteApp
        val cfg = app.configStore.current
        if (!navIgnored && (event.action == KeyEvent.ACTION_DOWN || event.action == KeyEvent.ACTION_UP)) {
            if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0 && InAppKeyMonitor.captureNextKeyMode.getAndSet(false)) {
                InAppKeyMonitor.recordUiCapturedEvent(
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
            if (InAppKeyMonitor.testerMode.get() && event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                val matched = ClickerMuteController.normalizeKeyCodeName(cfg.hwMuteHotkey) ==
                    ClickerMuteController.normalizeKeyCodeName(keyName)
                InAppKeyMonitor.recordUiCapturedEvent(
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
            } else {
                val action = if (event.action == KeyEvent.ACTION_DOWN) KeyAction.DOWN else KeyAction.UP
                val decision = focusedKeyController.onKeyEvent(
                    keyCodeName = keyName,
                    action = action,
                    isCtrl = event.isCtrlPressed,
                    isAlt = event.isAltPressed,
                    isShift = event.isShiftPressed,
                    repeatCount = event.repeatCount,
                    config = cfg
                )
                when (decision) {
                    ClickerDecision.CONSUME_TOGGLE,
                    ClickerDecision.TRIGGER_TOGGLE_SHORTCUT -> {
                        app.connectionManager.toggleMuteFromClicker()
                        return true
                    }
                    ClickerDecision.CONSUME_COUGH_HOLD_MUTE -> {
                        app.connectionManager.setMuteFromClicker(true)
                        return true
                    }
                    ClickerDecision.CONSUME_COUGH_RELEASE_UNMUTE -> {
                        app.connectionManager.setMuteFromClicker(false)
                        return true
                    }
                    ClickerDecision.TRIGGER_EXIT_SHORTCUT -> {
                        FloatingHudForegroundService.startService(this, FloatingHudForegroundService.ACTION_STOP)
                        return true
                    }
                    ClickerDecision.CONSUME_NOOP -> return true
                    ClickerDecision.PASS_THROUGH -> Unit
                }
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
    val formFactor = rememberFormFactor(cfg.deviceProfileMode)

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

    LaunchedEffect(Unit) {
        app.apkSelfInstaller.startThrottledStartupCheck()
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
                app.apkSelfInstaller.resumeAfterUnknownSourcesCheck()
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
                            Text(
                                text = if (formFactor.isTightWidth) "PresenterSync" else "PresenterSync Remote",
                                fontWeight = FontWeight.SemiBold,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                            Spacer(Modifier.width(if (formFactor.isTightWidth) 6.dp else 10.dp))
                            Surface(
                                shape = RoundedCornerShape(4.dp),
                                color = MaterialTheme.colorScheme.surfaceVariant,
                                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)
                            ) {
                                Text(
                                    text = "v${AppConstants.APP_VERSION}",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                                    maxLines = 1
                                )
                            }
                        }
                    },
                    actions = {
                        val iconBtnMod = if (formFactor.isTightWidth) Modifier.size(38.dp) else Modifier
                        IconButton(onClick = { showQuickQrScanner = true }, modifier = iconBtnMod) {
                            Icon(Icons.Default.QrCodeScanner, contentDescription = "Scan Host QR")
                        }
                        IconButton(onClick = { showHelpDialog = true }, modifier = iconBtnMod) {
                            Icon(Icons.AutoMirrored.Filled.HelpOutline, contentDescription = "Help & Diagnostics")
                        }
                        IconButton(onClick = { showAboutDialog = true }, modifier = iconBtnMod) {
                            Icon(Icons.Default.Info, contentDescription = "About & Updates")
                        }
                        IconButton(onClick = { showConnectionDialog = true }, modifier = iconBtnMod) {
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
                                horizontalArrangement = Arrangement.spacedBy(5.dp)
                            ) {
                                Icon(Icons.Default.Mic, contentDescription = null, modifier = Modifier.size(16.dp))
                                Text(
                                    text = if (formFactor.isTightWidth) "Status" else "Status & HUD",
                                    maxLines = 1,
                                    softWrap = false,
                                    overflow = TextOverflow.Ellipsis,
                                    fontWeight = FontWeight.Medium
                                )
                            }
                        }
                    )
                    Tab(
                        selected = selectedTabIndex == 1,
                        onClick = { selectedTabIndex = 1 },
                        text = {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(5.dp)
                            ) {
                                Icon(Icons.Default.Layers, contentDescription = null, modifier = Modifier.size(16.dp))
                                Text(
                                    text = "HUD Style",
                                    maxLines = 1,
                                    softWrap = false,
                                    overflow = TextOverflow.Ellipsis,
                                    fontWeight = FontWeight.Medium
                                )
                            }
                        }
                    )
                    Tab(
                        selected = selectedTabIndex == 2,
                        onClick = { selectedTabIndex = 2 },
                        text = {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(5.dp)
                            ) {
                                Icon(Icons.Default.Keyboard, contentDescription = null, modifier = Modifier.size(16.dp))
                                Text(
                                    text = if (formFactor.isTightWidth) "Pointer" else "Pointer & Keys",
                                    maxLines = 1,
                                    softWrap = false,
                                    overflow = TextOverflow.Ellipsis,
                                    fontWeight = FontWeight.Medium
                                )
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
                PointerSettingsScreen(
                    app = app,
                    onOpenHudStyle = { selectedTabIndex = 1 }
                )
            } else {
                val maxContainerWidth = if (formFactor.isWideTwoColumn) 1140.dp else 760.dp
                Column(
                    modifier = Modifier
                        .widthIn(max = maxContainerWidth)
                        .fillMaxWidth()
                        .verticalScroll(rememberScrollState())
                        .padding(formFactor.outerPaddingDp.dp),
                    verticalArrangement = Arrangement.spacedBy(14.dp)
                ) {
                    UpdateReadyInlineBanner(app = app)

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

                    if (formFactor.isWideTwoColumn) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(16.dp),
                            verticalAlignment = Alignment.Top
                        ) {
                            Column(
                                modifier = Modifier.weight(1f),
                                verticalArrangement = Arrangement.spacedBy(14.dp)
                            ) {
                                StatusAndActionsCard(
                                    cfg = cfg,
                                    conn = conn,
                                    formFactor = formFactor,
                                    onStartHud = {
                                        if (!Settings.canDrawOverlays(context)) {
                                            onRequestOverlayPermission()
                                        } else {
                                            FloatingHudForegroundService.startService(context)
                                        }
                                    },
                                    onStopHud = { FloatingHudForegroundService.stopService(context) },
                                    onToggleMute = { app.connectionManager.toggleMuteFromHud() },
                                    onOpenConnection = { showConnectionDialog = true },
                                    onReconnect = {
                                        if (conn.serviceRunning) {
                                            FloatingHudForegroundService.startService(
                                                context,
                                                FloatingHudForegroundService.ACTION_RECONNECT
                                            )
                                        } else {
                                            app.connectionManager.reconnectNow()
                                        }
                                    },
                                    onOpenQr = { showQuickQrScanner = true },
                                    onOpenHelp = { showHelpDialog = true },
                                    onOpenAbout = { showAboutDialog = true }
                                )

                                FormFactorOptimizationCard(
                                    cfg = cfg,
                                    formFactor = formFactor,
                                    onSelectMode = { mode ->
                                        app.configStore.update { it.copy(deviceProfileMode = mode) }
                                    },
                                    onApplyPreset = {
                                        app.configStore.applyFormFactorPreset(formFactor.deviceClass)
                                        Toast.makeText(
                                            context,
                                            "Applied ${formFactor.deviceClass.label} preset (${formFactor.recommendedScale}x)",
                                            Toast.LENGTH_SHORT
                                        ).show()
                                    }
                                )
                            }

                            Column(
                                modifier = Modifier.weight(1f),
                                verticalArrangement = Arrangement.spacedBy(14.dp)
                            ) {
                                FloatingPillQuickCard(
                                    cfg = cfg,
                                    formFactor = formFactor,
                                    onToggleIndicator = { v -> app.configStore.update { it.copy(showIndicator = v) } },
                                    onToggleText = { v -> app.configStore.update { it.copy(showText = v) } },
                                    onResetPosition = { app.configStore.resetPosition() }
                                )

                                CurrentProfileSummaryCard(cfg = cfg, formFactor = formFactor)
                            }
                        }
                    } else {
                        StatusAndActionsCard(
                            cfg = cfg,
                            conn = conn,
                            formFactor = formFactor,
                            onStartHud = {
                                if (!Settings.canDrawOverlays(context)) {
                                    onRequestOverlayPermission()
                                } else {
                                    FloatingHudForegroundService.startService(context)
                                }
                            },
                            onStopHud = { FloatingHudForegroundService.stopService(context) },
                            onToggleMute = { app.connectionManager.toggleMuteFromHud() },
                            onOpenConnection = { showConnectionDialog = true },
                            onReconnect = {
                                if (conn.serviceRunning) {
                                    FloatingHudForegroundService.startService(
                                        context,
                                        FloatingHudForegroundService.ACTION_RECONNECT
                                    )
                                } else {
                                    app.connectionManager.reconnectNow()
                                }
                            },
                            onOpenQr = { showQuickQrScanner = true },
                            onOpenHelp = { showHelpDialog = true },
                            onOpenAbout = { showAboutDialog = true }
                        )

                        FormFactorOptimizationCard(
                            cfg = cfg,
                            formFactor = formFactor,
                            onSelectMode = { mode ->
                                app.configStore.update { it.copy(deviceProfileMode = mode) }
                            },
                            onApplyPreset = {
                                app.configStore.applyFormFactorPreset(formFactor.deviceClass)
                                Toast.makeText(
                                    context,
                                    "Applied ${formFactor.deviceClass.label} preset (${formFactor.recommendedScale}x)",
                                    Toast.LENGTH_SHORT
                                ).show()
                            }
                        )

                        FloatingPillQuickCard(
                            cfg = cfg,
                            formFactor = formFactor,
                            onToggleIndicator = { v -> app.configStore.update { it.copy(showIndicator = v) } },
                            onToggleText = { v -> app.configStore.update { it.copy(showText = v) } },
                            onResetPosition = { app.configStore.resetPosition() }
                        )

                        CurrentProfileSummaryCard(cfg = cfg, formFactor = formFactor)
                    }
                }
            }
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
            app = app,
            onDismiss = { showAboutDialog = false }
        )
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun StatusAndActionsCard(
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
    onOpenAbout: () -> Unit
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
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun FormFactorOptimizationCard(
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
private fun FloatingPillQuickCard(
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
private fun CurrentProfileSummaryCard(
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
