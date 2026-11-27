package com.saabithjiffry.presentersync.remote.config

import java.net.URLEncoder
import java.nio.charset.StandardCharsets

object PairingUriBuilder {
    private fun encode(value: String): String =
        URLEncoder.encode(value, StandardCharsets.UTF_8.name()).replace("+", "%20")

    fun build(cfg: RemoteConfig): String {
        val sb = StringBuilder("presentersync://pair?")
        sb.append("host=").append(encode(cfg.hostAddress.trim()))
        if (cfg.bridgePort.coerceIn(1, 65535) != AppConstants.DEFAULT_BRIDGE_PORT) {
            sb.append("&bp=").append(cfg.bridgePort.coerceIn(1, 65535))
        }
        if (cfg.sessionPairingCode.isNotBlank()) {
            sb.append("&code=").append(encode(cfg.sessionPairingCode.trim()))
        }
        sb.append("&obsPort=").append(cfg.hostPort.coerceIn(1, 65535))
        sb.append("&mode=").append(if (cfg.networkMode == NetworkMode.INTERNET) "internet" else "lan")
        if (cfg.internetPairingCode.isNotBlank()) {
            sb.append("&wan=").append(encode(cfg.internetPairingCode.trim()))
        }
        val cleanRelay = cfg.relayBaseUrl.trim().trimEnd('/')
        if (cleanRelay.isNotEmpty() && !cleanRelay.equals("https://ntfy.sh", ignoreCase = true)) {
            sb.append("&relay=").append(encode(cleanRelay))
        }
        if (cfg.obsPassword.isNotEmpty()) {
            sb.append("&rpw=1")
        }
        return sb.toString()
    }
}
