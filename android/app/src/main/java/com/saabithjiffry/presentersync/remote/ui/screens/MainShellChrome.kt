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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun RemoteDashboardScreen(
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

    LaunchedEffect(cfg.keepScreenOn) {
        val win = (context as? android.app.Activity)?.window ?: return@LaunchedEffect
        val flag = android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
        if (cfg.keepScreenOn) win.addFlags(flag) else win.clearFlags(flag)
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

    var showSetupWizard by rememberSaveable { mutableStateOf(cfg.firstRun) }
    var showConnectionDialog by rememberSaveable { mutableStateOf(false) }
    var showKioskPinPrompt by rememberSaveable { mutableStateOf(false) }
    var kioskPinInput by rememberSaveable { mutableStateOf("") }
    var kioskPinError by rememberSaveable { mutableStateOf(false) }
    fun requestOpenConnectionSettings() {
        if (cfg.kioskPin.isNotBlank()) {
            kioskPinInput = ""
            kioskPinError = false
            showKioskPinPrompt = true
        } else {
            showConnectionDialog = true
        }
    }
    var showQuickQrScanner by rememberSaveable { mutableStateOf(false) }
    var showHelpDialog by rememberSaveable { mutableStateOf(false) }
    var showAboutDialog by rememberSaveable { mutableStateOf(false) }
    var showPodiumMode by rememberSaveable { mutableStateOf(false) }
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

    if (showPodiumMode) {
        PodiumDeckScreen(
            app = app,
            onExitPodium = { showPodiumMode = false }
        )
        return
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
                        IconButton(onClick = { requestOpenConnectionSettings() }, modifier = iconBtnMod) {
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
                    Button(
                        onClick = { showPodiumMode = true },
                        modifier = Modifier.fillMaxWidth().height(48.dp),
                        shape = RoundedCornerShape(10.dp)
                    ) {
                        Text("Podium Deck (Full-Screen OLED Mode)", fontWeight = FontWeight.Bold)
                    }

                    UpdateReadyInlineBanner(app = app)

                    if (showSetupWizard) {
                        OnboardingWizardCard(
                            cfg = cfg,
                            conn = conn,
                            hasOverlayPerm = hasOverlayPerm,
                            hasNotifPerm = hasNotifPerm,
                            formFactor = formFactor,
                            onRequestOverlayPermission = onRequestOverlayPermission,
                            onRequestNotificationPermission = {
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                                    notifLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                                } else {
                                    hasNotifPerm = true
                                }
                            },
                            onScanClassroomHosts = { app.connectionManager.scanClassroomHosts(1400L) },
                            onSelectDiscoveredHost = { host ->
                                app.configStore.update { prev ->
                                    prev.copy(
                                        networkMode = NetworkMode.LAN,
                                        hostAddress = host.hostIp,
                                        bridgePort = host.bridgePort,
                                        hostPort = host.obsPort,
                                        pairedHostUuid = host.hostUuid,
                                        firstRun = false
                                    )
                                }
                                app.connectionManager.reconnectNow()
                                Toast.makeText(
                                    context,
                                    "Selected ${host.deviceName} (${host.hostIp}:${host.bridgePort}).",
                                    Toast.LENGTH_SHORT
                                ).show()
                                showConnectionDialog = true
                            },
                            onOpenQrScanner = { showQuickQrScanner = true },
                            onOpenConnectionSetup = { showConnectionDialog = true },
                            onTestFloatingHud = {
                                if (!Settings.canDrawOverlays(context)) {
                                    onRequestOverlayPermission()
                                } else {
                                    FloatingHudForegroundService.startService(context)
                                }
                            },
                            onCompleteWizard = {
                                app.configStore.update { it.copy(firstRun = false) }
                                showSetupWizard = false
                            },
                            onDismissWizard = {
                                if (cfg.firstRun) {
                                    app.configStore.update { it.copy(firstRun = false) }
                                }
                                showSetupWizard = false
                            }
                        )
                    }

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
                                    onOpenAbout = { showAboutDialog = true },
                                    onOpenSetupWizard = { showSetupWizard = true },
                                    onPptPrev = { app.connectionManager.sendPptPrev("status_card") },
                                    onPptNext = { app.connectionManager.sendPptNext("status_card") },
                                    onToggleRecord = { app.connectionManager.sendToggleRecord("status_card") },
                                    onSelectProfile = { pid ->
                                        if (app.configStore.switchToProfile(pid) != null) {
                                            if (conn.serviceRunning) {
                                                FloatingHudForegroundService.startService(
                                                    context,
                                                    FloatingHudForegroundService.ACTION_RECONNECT
                                                )
                                            } else {
                                                app.connectionManager.reconnectNow()
                                            }
                                        }
                                    }
                                )

                                DirectorDeckAndTimerCard(
                                    conn = conn,
                                    formFactor = formFactor,
                                    onPauseRecord = { app.connectionManager.sendPauseRecord("dashboard") },
                                    onSplitRecord = { app.connectionManager.sendSplitRecord("dashboard") },
                                    onToggleStandby = { app.connectionManager.sendToggleStandby("dashboard") },
                                    onSwitchScene = { s -> app.connectionManager.sendSwitchScene(s, "dashboard") },
                                    onTimerCommand = { act, dur -> app.connectionManager.sendTimerCommand(act, dur, "dashboard") },
                                    onSendNudge = { msg -> app.connectionManager.sendStageNudge(msg) },
                                    onToggleRecord = { app.connectionManager.sendToggleRecord("dashboard") },
                                    confirmBeforeStopRecording = cfg.confirmBeforeStopRecording,
                                    onEmergencyPanic = { app.connectionManager.sendEmergencyPanic(null, "dashboard") },
                                    onSetPreviewScene = { sc -> app.connectionManager.sendSetPreviewScene(sc, "dashboard") },
                                    onAudioHandoff = { md -> app.connectionManager.sendAudioHandoff(md, "dashboard") },
                                    onSaveReplayBuffer = { app.connectionManager.sendSaveReplayBuffer("dashboard") },
                                    onAddBookmark = { lbl -> app.connectionManager.sendAddBookmark(lbl, "dashboard") },
                                    onSessionReset = { app.connectionManager.sendSessionReset(true, "dashboard") },
                                    onSendPresenterSignal = { msg -> app.connectionManager.sendPresenterSignal(msg, "sticky") },
                                    onAckNudge = { nid -> app.connectionManager.sendNudgeAck(nid) }
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
                            onOpenAbout = { showAboutDialog = true },
                            onOpenSetupWizard = { showSetupWizard = true },
                            onPptPrev = { app.connectionManager.sendPptPrev("status_card") },
                            onPptNext = { app.connectionManager.sendPptNext("status_card") },
                            onToggleRecord = { app.connectionManager.sendToggleRecord("status_card") },
                            onSelectProfile = { pid ->
                                if (app.configStore.switchToProfile(pid) != null) {
                                    if (conn.serviceRunning) {
                                        FloatingHudForegroundService.startService(
                                            context,
                                            FloatingHudForegroundService.ACTION_RECONNECT
                                        )
                                    } else {
                                        app.connectionManager.reconnectNow()
                                    }
                                }
                            }
                        )

                        DirectorDeckAndTimerCard(
                            conn = conn,
                            formFactor = formFactor,
                            onPauseRecord = { app.connectionManager.sendPauseRecord("dashboard") },
                            onSplitRecord = { app.connectionManager.sendSplitRecord("dashboard") },
                            onToggleStandby = { app.connectionManager.sendToggleStandby("dashboard") },
                            onSwitchScene = { s -> app.connectionManager.sendSwitchScene(s, "dashboard") },
                            onTimerCommand = { act, dur -> app.connectionManager.sendTimerCommand(act, dur, "dashboard") },
                            onSendNudge = { msg -> app.connectionManager.sendStageNudge(msg) },
                            onToggleRecord = { app.connectionManager.sendToggleRecord("dashboard") },
                            confirmBeforeStopRecording = cfg.confirmBeforeStopRecording,
                            onEmergencyPanic = { app.connectionManager.sendEmergencyPanic(null, "dashboard") },
                            onSetPreviewScene = { sc -> app.connectionManager.sendSetPreviewScene(sc, "dashboard") },
                            onAudioHandoff = { md -> app.connectionManager.sendAudioHandoff(md, "dashboard") },
                            onSaveReplayBuffer = { app.connectionManager.sendSaveReplayBuffer("dashboard") },
                            onAddBookmark = { lbl -> app.connectionManager.sendAddBookmark(lbl, "dashboard") },
                            onSessionReset = { app.connectionManager.sendSessionReset(true, "dashboard") },
                            onSendPresenterSignal = { msg -> app.connectionManager.sendPresenterSignal(msg, "sticky") },
                            onAckNudge = { nid -> app.connectionManager.sendNudgeAck(nid) }
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

    if (showKioskPinPrompt) {
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { showKioskPinPrompt = false },
            properties = androidx.compose.ui.window.DialogProperties(securePolicy = androidx.compose.ui.window.SecureFlagPolicy.SecureOn),
            title = { Text("Kiosk PIN Required") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    androidx.compose.material3.OutlinedTextField(
                        value = kioskPinInput,
                        onValueChange = { kioskPinInput = it; kioskPinError = false },
                        label = { Text("Enter Kiosk PIN") },
                        singleLine = true
                    )
                    if (kioskPinError) {
                        Text("Incorrect PIN", color = Color(0xFFDC2626))
                    }
                }
            },
            confirmButton = {
                Button(onClick = {
                    if (kioskPinInput.trim() == cfg.kioskPin.trim()) {
                        showKioskPinPrompt = false
                        showConnectionDialog = true
                    } else {
                        kioskPinError = true
                    }
                }) { Text("Unlock") }
            },
            dismissButton = {
                OutlinedButton(onClick = { showKioskPinPrompt = false }) { Text("Cancel") }
            }
        )
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

