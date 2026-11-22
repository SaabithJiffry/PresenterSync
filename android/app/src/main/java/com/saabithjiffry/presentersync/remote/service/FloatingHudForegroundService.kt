package com.saabithjiffry.presentersync.remote.service

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.content.res.Configuration
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.view.KeyEvent
import android.widget.Toast
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleService
import androidx.lifecycle.lifecycleScope
import com.saabithjiffry.presentersync.remote.PresenterSyncRemoteApp
import com.saabithjiffry.presentersync.remote.R
import com.saabithjiffry.presentersync.remote.audio.AudioCuePlayer
import com.saabithjiffry.presentersync.remote.config.RemoteConfig
import com.saabithjiffry.presentersync.remote.input.BubbleGestureAction
import com.saabithjiffry.presentersync.remote.input.ClickerDecision
import com.saabithjiffry.presentersync.remote.input.ClickerMuteController
import com.saabithjiffry.presentersync.remote.input.KeyAction
import com.saabithjiffry.presentersync.remote.network.ConnStatus
import com.saabithjiffry.presentersync.remote.network.ConnectionUiState
import com.saabithjiffry.presentersync.remote.network.RemoteEvent
import com.saabithjiffry.presentersync.remote.ui.arcade.ArcadeOverlayHost
import com.saabithjiffry.presentersync.remote.ui.arcade.ArcadeVaultManager
import com.saabithjiffry.presentersync.remote.ui.overlay.FloatingMicOverlayManager
import com.saabithjiffry.presentersync.remote.ui.overlay.FloatingToastBannerManager
import com.saabithjiffry.presentersync.remote.ui.overlay.HudSnakeOverlayManager
import com.saabithjiffry.presentersync.remote.ui.screens.MainActivity
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch

class FloatingHudForegroundService : LifecycleService() {
    private lateinit var app: PresenterSyncRemoteApp
    private lateinit var overlayManager: FloatingMicOverlayManager
    private lateinit var hudSnakeOverlayManager: HudSnakeOverlayManager
    private lateinit var arcadeOverlayHost: ArcadeOverlayHost
    private val overlayMuteController = ClickerMuteController()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val vaultLockListener: () -> Unit = {
        mainHandler.post {
            if (::hudSnakeOverlayManager.isInitialized) {
                hudSnakeOverlayManager.stop()
            }
            if (::arcadeOverlayHost.isInitialized) {
                arcadeOverlayHost.stop()
            }
        }
    }
    private lateinit var toastBannerManager: FloatingToastBannerManager
    private lateinit var audioCuePlayer: AudioCuePlayer
    private lateinit var hapticAlertPlayer: HapticAlertPlayer
    private lateinit var backgroundMediaClickerController: BackgroundMediaClickerController
    private var warned2mThisRun = false
    private var warnedOvertimeThisRun = false
    private var prevVoiceWhileMuted = false
    private var wifiLock: WifiManager.WifiLock? = null
    private var wakeReceiverRegistered = false

    private val wakeReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            overlayManager.onDisplayConfigurationChanged()
            if (::hudSnakeOverlayManager.isInitialized) {
                hudSnakeOverlayManager.onDisplayConfigurationChanged()
            }
            if (::arcadeOverlayHost.isInitialized) {
                arcadeOverlayHost.onDisplayConfigurationChanged()
            }
            app.connectionManager.onScreenWakeOrNetworkChanged()
        }
    }

    private fun syncPillVisibilityForArcade() {
        if (!::overlayManager.isInitialized) return
        val anyArcade = (::hudSnakeOverlayManager.isInitialized && hudSnakeOverlayManager.isActive) ||
            (::arcadeOverlayHost.isInitialized && arcadeOverlayHost.isActive)
        overlayManager.setHiddenForEasterEgg(anyArcade)
    }

    private fun handleOverlayMuteKeyEvent(event: KeyEvent): Boolean {
        val cfg = app.configStore.current
        val action = if (event.action == KeyEvent.ACTION_DOWN) KeyAction.DOWN else KeyAction.UP
        val keyName = KeyEvent.keyCodeToString(event.keyCode)
        val decision = overlayMuteController.onKeyEvent(
            keyCodeName = keyName,
            action = action,
            isCtrl = event.isCtrlPressed,
            isAlt = event.isAltPressed,
            isShift = event.isShiftPressed,
            repeatCount = event.repeatCount,
            config = cfg,
            isMuted = app.connectionManager.uiState.value.isMuted
        )
        return when (decision) {
            ClickerDecision.CONSUME_TOGGLE,
            ClickerDecision.TRIGGER_TOGGLE_SHORTCUT -> {
                app.connectionManager.toggleMuteFromClicker()
                true
            }
            ClickerDecision.CONSUME_COUGH_HOLD_MUTE,
            ClickerDecision.CONSUME_PTT_RELEASE_MUTE -> {
                app.connectionManager.setMuteFromClicker(true)
                true
            }
            ClickerDecision.CONSUME_COUGH_RELEASE_UNMUTE,
            ClickerDecision.CONSUME_PTT_HOLD_UNMUTE -> {
                app.connectionManager.setMuteFromClicker(false)
                true
            }
            ClickerDecision.TRIGGER_EXIT_SHORTCUT -> {
                stopRemoteCleanly()
                true
            }
            ClickerDecision.CONSUME_NOOP -> true
            ClickerDecision.PASS_THROUGH -> false
        }
    }

    private fun launchArcadeGameById(gameId: String) {
        if (!ArcadeVaultManager.isUnlocked.value) return
        val rect = overlayManager.currentPillRectPx()
        val cfg = app.configStore.current
        val isMuted = app.connectionManager.uiState.value.isMuted
        when (gameId.trim().lowercase()) {
            "snake" -> {
                if (::arcadeOverlayHost.isInitialized) arcadeOverlayHost.stop()
                hudSnakeOverlayManager.start(
                    cfg = cfg,
                    isMuted = isMuted,
                    pillLeftScreenPx = rect.left,
                    pillTopScreenPx = rect.top,
                    pillWidthPx = rect.width(),
                    pillHeightPx = rect.height()
                )
            }
            else -> {
                if (::hudSnakeOverlayManager.isInitialized) hudSnakeOverlayManager.stop()
                arcadeOverlayHost.startGame(
                    gameId = gameId,
                    cfg = cfg,
                    isMuted = isMuted,
                    pillRectPx = rect
                )
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        app = application as PresenterSyncRemoteApp
        ArcadeVaultManager.registerLockListener(vaultLockListener)
        hudSnakeOverlayManager = HudSnakeOverlayManager(this, app.configStore) { _ ->
            syncPillVisibilityForArcade()
        }
        arcadeOverlayHost = ArcadeOverlayHost(
            context = this,
            configStore = app.configStore,
            onActiveChanged = { _ -> syncPillVisibilityForArcade() },
            onMuteKeyEvent = { ev -> handleOverlayMuteKeyEvent(ev) }
        )
        overlayManager = FloatingMicOverlayManager(
            context = this,
            configStore = app.configStore,
            connectionManager = app.connectionManager,
            onLaunchEasterSnake = { launchArcadeGameById("snake") },
            onLaunchArcadeGame = { gameId -> launchArcadeGameById(gameId) }
        )
        toastBannerManager = FloatingToastBannerManager(this)
        audioCuePlayer = AudioCuePlayer()
        hapticAlertPlayer = HapticAlertPlayer(this)
        backgroundMediaClickerController = BackgroundMediaClickerController(this) { action ->
            when (action) {
                BubbleGestureAction.TOGGLE_MUTE -> app.connectionManager.toggleMuteFromHud()
                BubbleGestureAction.MUTE_ONLY -> app.connectionManager.setMuteFromHud(true)
                BubbleGestureAction.UNMUTE_ONLY -> app.connectionManager.setMuteFromHud(false)
                BubbleGestureAction.TRANSITION_SCENE -> app.connectionManager.sendTransitionScene("media_clicker")
                BubbleGestureAction.SLIDE_NEXT -> app.connectionManager.sendPptNext("media_clicker")
                BubbleGestureAction.SLIDE_PREV -> app.connectionManager.sendPptPrev("media_clicker")
                else -> Unit
            }
        }
        acquireWifiLock()
        registerWakeReceiver()
        app.configStore.setHudWasActive(true)
        promoteToForeground(buildNotification(app.configStore.current, app.connectionManager.uiState.value))

        app.connectionManager.start()

        lifecycleScope.launch {
            combine(app.configStore.config, app.connectionManager.uiState) { cfg, conn ->
                cfg to conn
            }.collect { (cfg, conn) ->
                overlayManager.showOrUpdate(cfg, conn)
                hudSnakeOverlayManager.updateConfig(cfg)
                arcadeOverlayHost.updateState(cfg, conn.isMuted)
                backgroundMediaClickerController.update(cfg)
                updateNotification(cfg, conn)
                QuickToggleTileService.requestRefresh(this@FloatingHudForegroundService)

                if (conn.timerState == "stopped") {
                    warned2mThisRun = false
                    warnedOvertimeThisRun = false
                } else if (conn.connected && (conn.timerState == "running" || conn.timerState == "overtime")) {
                    if (conn.timerRemainingSec > 120 && conn.timerState == "running") {
                        warned2mThisRun = false
                        warnedOvertimeThisRun = false
                    }
                    if (conn.timerRemainingSec <= 0 || conn.timerState == "overtime") {
                        if (!warnedOvertimeThisRun) {
                            warnedOvertimeThisRun = true
                            warned2mThisRun = true
                            hapticAlertPlayer.play(HapticAlertType.TIMER_OVERTIME, cfg)
                        }
                    } else if (conn.timerRemainingSec <= 120) {
                        if (!warned2mThisRun) {
                            warned2mThisRun = true
                            hapticAlertPlayer.play(HapticAlertType.TIMER_WARNING_2M, cfg)
                        }
                    }
                }
                if (conn.voiceWhileMuted && !prevVoiceWhileMuted) {
                    hapticAlertPlayer.play(HapticAlertType.SPEAKING_WHILE_MUTED, cfg)
                }
                prevVoiceWhileMuted = conn.voiceWhileMuted
            }
        }

        lifecycleScope.launch {
            app.connectionManager.events.collect { ev ->
                val cfg = app.configStore.current
                when (ev) {
                    is RemoteEvent.MuteChanged -> {
                        overlayManager.playMuteTransition(ev.isMuted)
                        hapticAlertPlayer.play(if (ev.isMuted) HapticAlertType.MUTE else HapticAlertType.UNMUTE, cfg)
                        if (cfg.enableAudioCue) {
                            audioCuePlayer.playMuteCue(ev.isMuted)
                        }
                        if (cfg.enableMuteToast) {
                            val (anchor, pillH) = overlayManager.currentAnchorForToast()
                            toastBannerManager.showMuteToast(ev.isMuted, cfg, anchor.x, anchor.y, pillH)
                        }
                    }
                    is RemoteEvent.ToastMessage -> {
                        Toast.makeText(applicationContext, ev.message, Toast.LENGTH_SHORT).show()
                    }
                    is RemoteEvent.StageNudge -> {
                        hapticAlertPlayer.play(HapticAlertType.STAGE_NUDGE, cfg)
                        val (anchor, pillH) = overlayManager.currentAnchorForToast()
                        val accentCol = runCatching {
                            val h = com.saabithjiffry.presentersync.remote.config.HudColorPalettes.normalizeColorHex(ev.accentHex, "#F59E0B")
                            android.graphics.Color.parseColor(h)
                        }.getOrDefault(android.graphics.Color.parseColor("#F59E0B"))
                        toastBannerManager.showAlertToast(
                            message = "${ev.sender}: ${ev.message}",
                            accentDotColor = accentCol,
                            cfg = cfg,
                            anchorX = anchor.x,
                            anchorY = anchor.y,
                            pillHeightPx = pillH,
                            durationMs = 4500L
                        )
                    }
                    RemoteEvent.VoiceWhileMutedAlert -> {
                        if (cfg.enableVoiceWhileMutedAlert) {
                            val (anchor, pillH) = overlayManager.currentAnchorForToast()
                            toastBannerManager.showAlertToast(
                                message = "You're on mute — mic signal detected",
                                accentDotColor = android.graphics.Color.parseColor("#F59E0B"),
                                cfg = cfg,
                                anchorX = anchor.x,
                                anchorY = anchor.y,
                                pillHeightPx = pillH
                            )
                        }
                    }
                    RemoteEvent.CloseRemoteRequested -> {
                        stopRemoteCleanly()
                    }
                }
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        super.onStartCommand(intent, flags, startId)
        when (intent?.action) {
            ACTION_TOGGLE_MUTE -> app.connectionManager.toggleMuteFromHud()
            ACTION_TOGGLE_INDICATOR -> {
                app.configStore.update { it.copy(showIndicator = !it.showIndicator) }
            }
            ACTION_DISABLE_CLICK_THROUGH -> {
                app.configStore.update { it.copy(hudClickThrough = false) }
            }
            ACTION_LAUNCH_ARCADE -> {
                val gameId = intent.getStringExtra(EXTRA_ARCADE_GAME_ID) ?: "snake"
                launchArcadeGameById(gameId)
            }
            ACTION_RECONNECT -> app.connectionManager.reconnectNow()
            ACTION_STOP -> stopRemoteCleanly()
        }
        return START_STICKY
    }

    private fun stopRemoteCleanly() {
        unregisterWakeReceiver()
        app.configStore.setHudWasActive(false)
        ArcadeVaultManager.lock()
        if (::hudSnakeOverlayManager.isInitialized) {
            hudSnakeOverlayManager.stop()
        }
        if (::arcadeOverlayHost.isInitialized) {
            arcadeOverlayHost.stop()
        }
        toastBannerManager.hide()
        overlayManager.hide()
        audioCuePlayer.release()
        hapticAlertPlayer.cancel()
        if (::backgroundMediaClickerController.isInitialized) {
            backgroundMediaClickerController.release()
        }
        app.connectionManager.stop()
        releaseWifiLock()
        QuickToggleTileService.requestRefresh(this)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        if (::overlayManager.isInitialized) {
            overlayManager.onDisplayConfigurationChanged()
        }
        if (::hudSnakeOverlayManager.isInitialized) {
            hudSnakeOverlayManager.onDisplayConfigurationChanged()
        }
        if (::arcadeOverlayHost.isInitialized) {
            arcadeOverlayHost.onDisplayConfigurationChanged()
        }
    }

    override fun onDestroy() {
        unregisterWakeReceiver()
        ArcadeVaultManager.unregisterLockListener(vaultLockListener)
        if (::hudSnakeOverlayManager.isInitialized) {
            hudSnakeOverlayManager.stop()
        }
        if (::arcadeOverlayHost.isInitialized) {
            arcadeOverlayHost.destroy()
        }
        toastBannerManager.hide()
        overlayManager.hide()
        audioCuePlayer.release()
        hapticAlertPlayer.cancel()
        if (::backgroundMediaClickerController.isInitialized) {
            backgroundMediaClickerController.release()
        }
        app.connectionManager.stop()
        releaseWifiLock()
        QuickToggleTileService.requestRefresh(this)
        super.onDestroy()
    }

    private fun registerWakeReceiver() {
        if (wakeReceiverRegistered) return
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_USER_PRESENT)
        }
        try {
            ContextCompat.registerReceiver(
                this,
                wakeReceiver,
                filter,
                ContextCompat.RECEIVER_NOT_EXPORTED
            )
            wakeReceiverRegistered = true
        } catch (_: Exception) {
        }
    }

    private fun unregisterWakeReceiver() {
        if (!wakeReceiverRegistered) return
        try {
            unregisterReceiver(wakeReceiver)
        } catch (_: Exception) {
        }
        wakeReceiverRegistered = false
    }

    override fun onBind(intent: Intent): IBinder? {
        return super.onBind(intent)
    }

    private fun promoteToForeground(notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun updateNotification(cfg: RemoteConfig, conn: ConnectionUiState) {
        try {
            com.saabithjiffry.presentersync.remote.widget.PresenterSyncWidgetProvider.requestUpdate(this)
        } catch (_: Throwable) {
        }
        val mgr = getSystemService(NotificationManager::class.java) ?: return
        mgr.notify(NOTIFICATION_ID, buildNotification(cfg, conn))
    }

    private fun buildNotification(cfg: RemoteConfig, conn: ConnectionUiState): Notification {
        val baseStatus = when {
            conn.connStatus == ConnStatus.AUTH_FAILED -> "✕ Auth Failed (Check Password)"
            conn.connected && conn.connStatus == ConnStatus.MIC_ERROR ->
                "⚠ Mic '${cfg.targetMicName}' Not Found: ${conn.activeHost}"
            conn.connected -> {
                val base = "● Connected: ${conn.activeHost} (${if (conn.isMuted) "MUTED" else "LIVE"})"
                val parts = mutableListOf(base)
                if (conn.isStandby) parts += "STANDBY"
                if (conn.recState == 1) parts += "REC ${conn.formattedRecElapsed()}"
                else if (conn.recState == 2) parts += "PAUSED ${conn.formattedRecElapsed()}"
                if (conn.timerState != "stopped") parts += "${if (conn.timerState == "overtime") "OT" else "TMR"} ${conn.formattedCountdown()}"
                if (conn.streamDropWarn) parts += "⚠ STREAM WARN"
                if (conn.voiceWhileMuted && conn.isMuted) parts += "⚠ MIC SIGNAL"
                parts.joinToString(" • ")
            }
            else -> "○ Searching for OBS Host..."
        }
        val statusText = if (cfg.hudClickThrough) "$baseStatus • Click-Through ON" else baseStatus

        val openPending = PendingIntent.getActivity(
            this,
            10,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val mutePending = PendingIntent.getService(
            this,
            11,
            Intent(this, FloatingHudForegroundService::class.java).setAction(ACTION_TOGGLE_MUTE),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val middleLabel = if (cfg.hudClickThrough) {
            "Unlock Clicks"
        } else if (cfg.showIndicator) {
            "Hide Pill"
        } else {
            "Show Pill"
        }
        val middleAction = if (cfg.hudClickThrough) ACTION_DISABLE_CLICK_THROUGH else ACTION_TOGGLE_INDICATOR
        val middlePending = PendingIntent.getService(
            this,
            12,
            Intent(this, FloatingHudForegroundService::class.java).setAction(middleAction),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val stopPending = PendingIntent.getService(
            this,
            13,
            Intent(this, FloatingHudForegroundService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, PresenterSyncRemoteApp.HUD_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_mic)
            .setContentTitle("PresenterSync Remote")
            .setContentText(statusText)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(openPending)
            .addAction(0, if (conn.isMuted) "Unmute" else "Mute", mutePending)
            .addAction(0, middleLabel, middlePending)
            .addAction(0, "Stop", stopPending)
            .build()
    }

    private fun acquireWifiLock() {
        try {
            val wifiMgr = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager ?: return
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                WifiManager.WIFI_MODE_FULL_LOW_LATENCY
            } else {
                @Suppress("DEPRECATION")
                WifiManager.WIFI_MODE_FULL_HIGH_PERF
            }
            wifiLock = wifiMgr.createWifiLock(mode, "PresenterSyncRemote:WifiLock").apply {
                setReferenceCounted(false)
                acquire()
            }
        } catch (_: Exception) {
        }
    }

    private fun releaseWifiLock() {
        try {
            if (wifiLock?.isHeld == true) wifiLock?.release()
        } catch (_: Exception) {
        }
        wifiLock = null
    }

    companion object {
        const val NOTIFICATION_ID = 4455
        const val ACTION_START = "com.saabithjiffry.presentersync.remote.START"
        const val ACTION_STOP = "com.saabithjiffry.presentersync.remote.STOP"
        const val ACTION_TOGGLE_MUTE = "com.saabithjiffry.presentersync.remote.TOGGLE_MUTE"
        const val ACTION_TOGGLE_INDICATOR = "com.saabithjiffry.presentersync.remote.TOGGLE_INDICATOR"
        const val ACTION_DISABLE_CLICK_THROUGH = "com.saabithjiffry.presentersync.remote.DISABLE_CLICK_THROUGH"
        const val ACTION_LAUNCH_ARCADE = "com.saabithjiffry.presentersync.remote.LAUNCH_ARCADE"
        const val EXTRA_ARCADE_GAME_ID = "arcade_game_id"
        const val ACTION_RECONNECT = "com.saabithjiffry.presentersync.remote.RECONNECT"

        fun launchArcadeGame(context: Context, gameId: String): Boolean {
            val intent = Intent(context, FloatingHudForegroundService::class.java)
                .setAction(ACTION_LAUNCH_ARCADE)
                .putExtra(EXTRA_ARCADE_GAME_ID, gameId)
            return try {
                context.startForegroundService(intent)
                true
            } catch (_: Exception) {
                false
            }
        }

        fun startService(context: Context, action: String = ACTION_START): Boolean {
            val intent = Intent(context, FloatingHudForegroundService::class.java).setAction(action)
            return try {
                context.startForegroundService(intent)
                true
            } catch (_: Exception) {
                false
            }
        }

        fun stopService(context: Context) {
            val intent = Intent(context, FloatingHudForegroundService::class.java).setAction(ACTION_STOP)
            runCatching { context.startService(intent) }
        }
    }
}
