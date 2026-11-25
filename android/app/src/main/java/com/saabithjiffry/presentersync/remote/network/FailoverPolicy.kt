package com.saabithjiffry.presentersync.remote.network

import com.saabithjiffry.presentersync.remote.config.AppConstants
import com.saabithjiffry.presentersync.remote.config.NetworkMode
import com.saabithjiffry.presentersync.remote.config.RemoteConfig

object FailoverPolicy {

    const val REPROMOTE_REQUIRED_CONSECUTIVE_PROBES = 2

    fun hasBridgeCredentials(cfg: RemoteConfig): Boolean =
        cfg.sessionToken.isNotBlank() || cfg.sessionPairingCode.isNotBlank()

    fun hasWanFallbackConfigured(cfg: RemoteConfig): Boolean =
        cfg.networkMode == NetworkMode.LAN &&
            cfg.enableRelayFallback &&
            cfg.internetPairingCode.isNotBlank()

    fun shouldFallbackToWan(
        cfg: RemoteConfig,
        elapsedLanMs: Long,
        budgetMs: Long = AppConstants.LAN_FAILOVER_DEADLINE_MS
    ): Boolean {
        if (!hasWanFallbackConfigured(cfg)) return false
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

    fun canRepromoteFromFallback(cfg: RemoteConfig, state: ConnectionUiState): Boolean =
        canRepromoteToLan(
            cfg,
            usingRelayFallback = state.usingRelayFallback ||
                state.usingDirectObsFallback ||
                cfg.networkMode == NetworkMode.LAN
        )

    fun isExplicitBridgeRevocation(reason: String): Boolean {
        val low = reason.lowercase()
        return low.contains("unpaired") || low.contains("revoked")
    }

    fun shouldRetryBridgeAuthWithPairingCode(cfg: RemoteConfig, reason: String): Boolean =
        cfg.sessionToken.isNotBlank() &&
            cfg.sessionPairingCode.isNotBlank() &&
            !isExplicitBridgeRevocation(reason)

    fun isWakeConnectionStale(lastRxAtMs: Long, nowMs: Long, wakeStalenessMs: Long): Boolean =
        lastRxAtMs >= 0L && (nowMs - lastRxAtMs) > wakeStalenessMs
}
