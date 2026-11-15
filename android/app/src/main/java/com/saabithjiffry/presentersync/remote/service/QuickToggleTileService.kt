package com.saabithjiffry.presentersync.remote.service

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import com.saabithjiffry.presentersync.remote.PresenterSyncRemoteApp
import com.saabithjiffry.presentersync.remote.ui.screens.MainActivity

/**
 * Quick Settings Tile for rapid mute toggle, HUD start, or emergency Click-Through unlock.
 */
class QuickToggleTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        refreshTile()
    }

    override fun onClick() {
        super.onClick()
        val app = application as? PresenterSyncRemoteApp ?: return
        val cfg = app.configStore.current
        val conn = app.connectionManager.uiState.value

        if (cfg.hudClickThrough) {
            app.configStore.update { it.copy(hudClickThrough = false) }
            refreshTile()
            return
        }

        if (conn.connected) {
            app.connectionManager.toggleMuteFromHud()
            refreshTile()
            return
        }

        if (Settings.canDrawOverlays(this)) {
            val started = FloatingHudForegroundService.startService(this)
            if (!started) {
                openMainForHudStart()
            } else {
                refreshTile()
            }
        } else {
            openMainForHudStart()
        }
    }

    private fun openMainForHudStart() {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(MainActivity.EXTRA_AUTO_START_HUD, true)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val pi = android.app.PendingIntent.getActivity(
                this,
                41,
                intent,
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
            )
            startActivityAndCollapse(pi)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }

    private fun refreshTile() {
        val tile = qsTile ?: return
        val app = application as? PresenterSyncRemoteApp ?: return
        val cfg = app.configStore.current
        val conn = app.connectionManager.uiState.value

        tile.label = getString(com.saabithjiffry.presentersync.remote.R.string.qs_tile_label)
        val subtitleText: String
        val tileState: Int

        when {
            cfg.hudClickThrough -> {
                tileState = Tile.STATE_ACTIVE
                subtitleText = "Click-Thru (Tap Unlock)"
            }
            conn.connected && conn.isMuted -> {
                tileState = Tile.STATE_ACTIVE
                subtitleText = "MUTED"
            }
            conn.connected -> {
                tileState = Tile.STATE_ACTIVE
                subtitleText = "LIVE"
            }
            else -> {
                tileState = Tile.STATE_INACTIVE
                subtitleText = "Tap to Start HUD"
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = subtitleText
        }
        tile.state = tileState
        tile.updateTile()
    }

    companion object {
        fun requestRefresh(context: Context) {
            runCatching {
                requestListeningState(
                    context.applicationContext,
                    ComponentName(context.applicationContext, QuickToggleTileService::class.java)
                )
            }
        }
    }
}
