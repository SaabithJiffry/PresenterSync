package com.saabithjiffry.presentersync.remote

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import com.saabithjiffry.presentersync.remote.config.RemoteConfigStore
import com.saabithjiffry.presentersync.remote.network.ConnectionManager

class PresenterSyncRemoteApp : Application() {
    lateinit var configStore: RemoteConfigStore
        private set
    lateinit var connectionManager: ConnectionManager
        private set

    override fun onCreate() {
        super.onCreate()
        configStore = RemoteConfigStore(this)
        connectionManager = ConnectionManager(this, configStore)
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
