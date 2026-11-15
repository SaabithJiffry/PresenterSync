package com.saabithjiffry.presentersync.remote.service

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.widget.Toast
import androidx.core.app.NotificationCompat
import androidx.lifecycle.LifecycleService
import androidx.lifecycle.lifecycleScope
import com.saabithjiffry.presentersync.remote.PresenterSyncRemoteApp
import com.saabithjiffry.presentersync.remote.R
import com.saabithjiffry.presentersync.remote.config.RemoteConfig
import com.saabithjiffry.presentersync.remote.network.ConnStatus
import com.saabithjiffry.presentersync.remote.network.ConnectionUiState
import com.saabithjiffry.presentersync.remote.network.RemoteEvent
import com.saabithjiffry.presentersync.remote.ui.overlay.FloatingMicOverlayManager
import com.saabithjiffry.presentersync.remote.ui.screens.MainActivity
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch

class FloatingHudForegroundService : LifecycleService() {
    private lateinit var app: PresenterSyncRemoteApp
    private lateinit var overlayManager: FloatingMicOverlayManager
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onCreate() {
        super.onCreate()
        app = application as PresenterSyncRemoteApp
        overlayManager = FloatingMicOverlayManager(this, app.configStore, app.connectionManager)
        acquireWifiLock()
        promoteToForeground(buildNotification(app.configStore.current, app.connectionManager.uiState.value))

        app.connectionManager.start()

        lifecycleScope.launch {
            combine(app.configStore.config, app.connectionManager.uiState) { cfg, conn ->
                cfg to conn
            }.collect { (cfg, conn) ->
                overlayManager.showOrUpdate(cfg, conn)
                updateNotification(cfg, conn)
            }
        }

        lifecycleScope.launch {
            app.connectionManager.events.collect { ev ->
                when (ev) {
                    is RemoteEvent.MuteChanged -> overlayManager.playMuteTransition(ev.isMuted)
                    is RemoteEvent.ToastMessage -> {
                        Toast.makeText(applicationContext, ev.message, Toast.LENGTH_SHORT).show()
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
            ACTION_RECONNECT -> app.connectionManager.reconnectNow()
            ACTION_STOP -> stopRemoteCleanly()
        }
        return START_STICKY
    }

    private fun stopRemoteCleanly() {
        overlayManager.hide()
        app.connectionManager.stop()
        releaseWifiLock()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        overlayManager.hide()
        app.connectionManager.stop()
        releaseWifiLock()
        super.onDestroy()
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
        val mgr = getSystemService(NotificationManager::class.java) ?: return
        mgr.notify(NOTIFICATION_ID, buildNotification(cfg, conn))
    }

    private fun buildNotification(cfg: RemoteConfig, conn: ConnectionUiState): Notification {
        val statusText = when {
            conn.connStatus == ConnStatus.AUTH_FAILED -> "✕ Auth Failed (Check Password)"
            conn.connected && conn.connStatus == ConnStatus.MIC_ERROR ->
                "⚠ Mic '${cfg.targetMicName}' Not Found: ${conn.activeHost}"
            conn.connected -> "● Connected: ${conn.activeHost} (${if (conn.isMuted) "MUTED" else "LIVE"})"
            else -> "○ Searching for OBS Host..."
        }

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

        val toggleHudPending = PendingIntent.getService(
            this,
            12,
            Intent(this, FloatingHudForegroundService::class.java).setAction(ACTION_TOGGLE_INDICATOR),
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
            .addAction(0, if (cfg.showIndicator) "Hide Pill" else "Show Pill", toggleHudPending)
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
        const val ACTION_RECONNECT = "com.saabithjiffry.presentersync.remote.RECONNECT"

        fun startService(context: Context, action: String = ACTION_START) {
            val intent = Intent(context, FloatingHudForegroundService::class.java).setAction(action)
            context.startForegroundService(intent)
        }

        fun stopService(context: Context) {
            val intent = Intent(context, FloatingHudForegroundService::class.java).setAction(ACTION_STOP)
            context.startService(intent)
        }
    }
}
