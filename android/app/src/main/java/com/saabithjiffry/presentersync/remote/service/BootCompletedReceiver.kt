package com.saabithjiffry.presentersync.remote.service

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Settings
import androidx.core.app.NotificationCompat
import com.saabithjiffry.presentersync.remote.PresenterSyncRemoteApp
import com.saabithjiffry.presentersync.remote.R
import com.saabithjiffry.presentersync.remote.config.RemoteConfigStore
import com.saabithjiffry.presentersync.remote.ui.screens.MainActivity

/**
 * Starts the floating HUD service automatically after device reboot ONLY if the user
 * explicitly enabled Start on Boot in settings (strictly OFF by default).
 */
class BootCompletedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != ACTION_QUICKBOOT_POWERON &&
            action != Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            return
        }

        val appCtx = context.applicationContext
        val store = RemoteConfigStore(appCtx)
        val cfg = store.current
        val shouldRestoreAfterUpdate = action == Intent.ACTION_MY_PACKAGE_REPLACED && store.wasHudActive()
        if (!cfg.startOnBoot && !shouldRestoreAfterUpdate) return
        if (!Settings.canDrawOverlays(appCtx)) return

        val started = FloatingHudForegroundService.startService(appCtx)
        if (!started) {
            val launchIntent = Intent(appCtx, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra(MainActivity.EXTRA_AUTO_START_HUD, true)
            }
            val pi = PendingIntent.getActivity(
                appCtx,
                42,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val notif = NotificationCompat.Builder(appCtx, PresenterSyncRemoteApp.HUD_CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_stat_mic)
                .setContentTitle("PresenterSync Remote Ready")
                .setContentText("Tap to launch the floating Mic HUD on Android 12+")
                .setAutoCancel(true)
                .setContentIntent(pi)
                .build()
            runCatching {
                appCtx.getSystemService(NotificationManager::class.java)
                    ?.notify(FloatingHudForegroundService.NOTIFICATION_ID + 1, notif)
            }
        }
    }

    companion object {
        private const val ACTION_QUICKBOOT_POWERON = "android.intent.action.QUICKBOOT_POWERON"
    }
}
