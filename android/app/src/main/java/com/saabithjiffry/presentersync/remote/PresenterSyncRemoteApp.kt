package com.saabithjiffry.presentersync.remote

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import com.saabithjiffry.presentersync.remote.config.AppConstants
import com.saabithjiffry.presentersync.remote.config.RemoteConfigStore
import com.saabithjiffry.presentersync.remote.network.ApkSelfInstaller
import com.saabithjiffry.presentersync.remote.network.ConnectionManager
import com.saabithjiffry.presentersync.remote.util.DiagnosticLogger
import java.io.File

class PresenterSyncRemoteApp : Application() {
    lateinit var configStore: RemoteConfigStore
        private set
    lateinit var connectionManager: ConnectionManager
        private set
    lateinit var apkSelfInstaller: ApkSelfInstaller
        private set

    override fun onCreate() {
        super.onCreate()
        configStore = RemoteConfigStore(this)
        connectionManager = ConnectionManager(this, configStore)
        DiagnosticLogger.init(
            directory = File(filesDir, "logs"),
            appVersion = { AppConstants.APP_VERSION },
            state = {
                val u = connectionManager.uiState.value
                val cfg = configStore.current
                DiagnosticLogger.AppStateSnapshot(
                    connected = u.connected,
                    isMuted = u.isMuted,
                    recState = u.recState,
                    streamState = if (u.streamDropWarn) 2 else 0,
                    currentScene = u.activeScene,
                    networkMode = cfg.networkMode.name,
                    usingBridge = u.usingBridge
                )
            },
            config = {
                val cfg = configStore.current
                mapOf(
                    "networkMode" to cfg.networkMode.name,
                    "hostAddress" to cfg.hostAddress,
                    "hostPort" to cfg.hostPort,
                    "bridgePort" to cfg.bridgePort,
                    "targetMicName" to cfg.targetMicName,
                    "deviceProfileMode" to cfg.deviceProfileMode.name
                )
            },
            secrets = {
                val cfg = configStore.current
                listOf(
                    cfg.obsPassword,
                    cfg.sessionPairingCode,
                    cfg.sessionToken,
                    cfg.internetPairingCode
                ).filter { it.isNotBlank() }
            }
        )
        apkSelfInstaller = ApkSelfInstaller(this, configStore, connectionManager.sharedHttpClient)
        apkSelfInstaller.clearStaleUpdateCache()
        createNotificationChannel()
    }

    private fun createNotificationChannel() {
        val mgr = getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            HUD_CHANNEL_ID,
            getString(R.string.fgs_channel_name),
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = getString(R.string.fgs_channel_desc)
            setShowBadge(false)
        }
        mgr.createNotificationChannel(channel)
    }

    companion object {
        const val HUD_CHANNEL_ID = "presentersync_remote_hud"
    }
}
