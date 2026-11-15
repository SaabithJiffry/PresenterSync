package com.saabithjiffry.presentersync.remote.service

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Settings
import com.saabithjiffry.presentersync.remote.config.RemoteConfigStore

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

        val cfg = RemoteConfigStore(context.applicationContext).current
        if (!cfg.startOnBoot) return
        if (!Settings.canDrawOverlays(context)) return

        runCatching {
            FloatingHudForegroundService.startService(context.applicationContext)
        }
    }

    companion object {
        private const val ACTION_QUICKBOOT_POWERON = "android.intent.action.QUICKBOOT_POWERON"
    }
}
