package com.saabithjiffry.presentersync.remote.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import com.saabithjiffry.presentersync.remote.PresenterSyncRemoteApp
import com.saabithjiffry.presentersync.remote.R
import com.saabithjiffry.presentersync.remote.network.ConnectionUiState
import com.saabithjiffry.presentersync.remote.ui.screens.MainActivity

data class WidgetRenderModel(
    val label: String,
    val badge: String,
    val bgColorArgb: Int,
    val subtitle: String
)

object WidgetStateFormatter {
    const val COLOR_LIVE_ARGB: Int = 0xFF107C10.toInt()
    const val COLOR_MUTED_ARGB: Int = 0xFFC42B1C.toInt()
    const val COLOR_OFFLINE_ARGB: Int = 0xFF334155.toInt()

    fun format(connState: ConnectionUiState): WidgetRenderModel {
        val badge = when {
            connState.recState == 1 -> "REC"
            connState.recState == 2 -> "PAUSED"
            connState.isStandby -> "BRB"
            else -> ""
        }
        return when {
            !connState.connected -> WidgetRenderModel(
                label = "OFFLINE",
                badge = "",
                bgColorArgb = COLOR_OFFLINE_ARGB,
                subtitle = "Tap to open PresenterSync"
            )
            connState.isMuted -> WidgetRenderModel(
                label = "MUTED",
                badge = badge,
                bgColorArgb = COLOR_MUTED_ARGB,
                subtitle = "Tap to unmute • ${connState.activeScene}"
            )
            else -> WidgetRenderModel(
                label = "LIVE",
                badge = badge,
                bgColorArgb = COLOR_LIVE_ARGB,
                subtitle = "Tap to mute • ${connState.activeScene}"
            )
        }
    }
}

class PresenterSyncWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        val conn = (context.applicationContext as? PresenterSyncRemoteApp)?.connectionManager?.uiState?.value
            ?: ConnectionUiState()
        val model = WidgetStateFormatter.format(conn)
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_presentersync_2x1).apply {
                setTextViewText(R.id.widget_status_label, model.label)
                setTextViewText(R.id.widget_badge_text, model.badge)
                setTextViewText(R.id.widget_subtitle, model.subtitle)
                setInt(R.id.widget_root, "setBackgroundColor", model.bgColorArgb)

                val intent = Intent(context, PresenterSyncWidgetProvider::class.java).apply {
                    action = ACTION_WIDGET_TOGGLE_MUTE
                }
                val pi = PendingIntent.getBroadcast(
                    context,
                    0,
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                setOnClickPendingIntent(R.id.widget_root, pi)
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_WIDGET_TOGGLE_MUTE) {
            val app = context.applicationContext as? PresenterSyncRemoteApp
            val conn = app?.connectionManager?.uiState?.value
            if (conn != null && conn.connected) {
                app.connectionManager.toggleMuteFromHud()
                requestUpdate(context)
            } else {
                val launch = Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                }
                context.startActivity(launch)
            }
        }
    }

    companion object {
        const val ACTION_WIDGET_TOGGLE_MUTE = "com.saabithjiffry.presentersync.remote.ACTION_WIDGET_TOGGLE_MUTE"

        fun requestUpdate(context: Context) {
            val mgr = AppWidgetManager.getInstance(context)
            val cn = ComponentName(context, PresenterSyncWidgetProvider::class.java)
            val ids = mgr.getAppWidgetIds(cn)
            if (ids.isNotEmpty()) {
                val intent = Intent(context, PresenterSyncWidgetProvider::class.java).apply {
                    action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                }
                context.sendBroadcast(intent)
            }
        }
    }
}
