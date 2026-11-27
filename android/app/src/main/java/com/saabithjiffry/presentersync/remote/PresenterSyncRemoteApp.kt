package com.saabithjiffry.presentersync.remote

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.RestrictionsManager
import android.os.Bundle
import com.saabithjiffry.presentersync.remote.config.AppConstants
import com.saabithjiffry.presentersync.remote.config.DeviceProfileMode
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
        applyManagedRestrictions()
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
                    cfg.internetPairingCode,
                    cfg.kioskPin
                ).filter { it.isNotBlank() }
            }
        )
        apkSelfInstaller = ApkSelfInstaller(this, configStore, connectionManager.sharedHttpClient)
        apkSelfInstaller.clearStaleUpdateCache()
        createNotificationChannel()
    }

    private fun applyManagedRestrictions() {
        try {
            val rm = getSystemService(Context.RESTRICTIONS_SERVICE) as? RestrictionsManager ?: return
            applyManagedRestrictionsBundle(rm.applicationRestrictions)
        } catch (_: Exception) {
        }
    }

    internal fun applyManagedRestrictionsBundle(bundle: Bundle?) {
        if (bundle == null) return
        try {
            applyManagedRestrictionsToStore(
                store = configStore,
                hostAddress = bundle.getString("host_address"),
                bridgePort = bundle.getInt("bridge_port", 0),
                kioskPin = bundle.getString("kiosk_pin"),
                defaultRole = bundle.getString("default_role"),
                sessionPairingCode = bundle.getString("session_pairing_code"),
                deviceProfileMode = bundle.getString("device_profile_mode")
            )
        } catch (_: Exception) {
        }
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

        internal fun applyManagedRestrictionsToStore(
            store: RemoteConfigStore,
            hostAddress: String?,
            bridgePort: Int,
            kioskPin: String?,
            defaultRole: String?,
            sessionPairingCode: String?,
            deviceProfileMode: String?
        ) {
            val mdmHost = hostAddress.orEmpty().trim()
            val mdmPin = kioskPin.orEmpty().trim()
            val mdmRole = defaultRole.orEmpty().trim()
            val mdmSessionCode = sessionPairingCode.orEmpty().trim().uppercase()
            val mdmProfileRaw = deviceProfileMode.orEmpty().trim()
            val mdmProfile = if (mdmProfileRaw.isNotEmpty()) DeviceProfileMode.fromRaw(mdmProfileRaw) else null
            if (mdmHost.isNotEmpty() || bridgePort in 1..65535 || mdmPin.isNotEmpty() ||
                mdmRole.isNotEmpty() || mdmSessionCode.isNotEmpty() || mdmProfile != null
            ) {
                store.update { cur ->
                    cur.copy(
                        hostAddress = mdmHost.ifEmpty { cur.hostAddress },
                        bridgePort = if (bridgePort in 1..65535) bridgePort else cur.bridgePort,
                        kioskPin = mdmPin.ifEmpty { cur.kioskPin },
                        defaultRole = mdmRole.ifEmpty { cur.defaultRole },
                        sessionPairingCode = mdmSessionCode.ifEmpty { cur.sessionPairingCode },
                        deviceProfileMode = mdmProfile ?: cur.deviceProfileMode
                    )
                }
            }
        }
    }
}
