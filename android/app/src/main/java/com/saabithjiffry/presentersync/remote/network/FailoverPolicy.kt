package com.saabithjiffry.presentersync.remote.network

import com.saabithjiffry.presentersync.remote.config.AppConstants
import com.saabithjiffry.presentersync.remote.config.NetworkMode
import com.saabithjiffry.presentersync.remote.config.RemoteConfig

object FailoverPolicy {

    fun shouldFallbackToWan(
        cfg: RemoteConfig,
        elapsedLanMs: Long,
        budgetMs: Long = AppConstants.LAN_FAILOVER_DEADLINE_MS
    ): Boolean {
        if (cfg.networkMode != NetworkMode.LAN) return false
        if (!cfg.enableRelayFallback || cfg.internetPairingCode.isBlank()) return false
        return elapsedLanMs >= budgetMs.coerceAtLeast(300L)
    }

    fun perCandidateBudgetRemainingMs(
        cycleStartMs: Long,
        nowMs: Long,
        budgetMs: Long = AppConstants.LAN_FAILOVER_DEADLINE_MS
    ): Long {
        val elapsed = (nowMs - cycleStartMs).coerceAtLeast(0L)
        return (budgetMs - elapsed).coerceAtLeast(0L)
    }

    fun canRepromoteToLan(cfg: RemoteConfig, usingRelayFallback: Boolean): Boolean {
        if (!usingRelayFallback || cfg.networkMode != NetworkMode.LAN) return false
        return cfg.hostAddress.isNotBlank() || cfg.pairedHostUuid.isNotBlank()
    }
}
