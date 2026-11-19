package com.saabithjiffry.presentersync.remote.config

import java.net.URLEncoder
import java.nio.charset.StandardCharsets

object PairingUriBuilder {
    private fun encode(value: String): String =
        URLEncoder.encode(value, StandardCharsets.UTF_8.name()).replace("+", "%20")

    fun build(cfg: RemoteConfig): String {
        val sb = StringBuilder("presentersync://pair?")
        sb.append("host=").append(encode(cfg.hostAddress.trim()))
        sb.append("&bp=").append(cfg.bridgePort.coerceIn(1, 65535))
        if (cfg.sessionPairingCode.isNotBlank()) {
            sb.append("&code=").append(encode(cfg.sessionPairingCode.trim()))
        }
        sb.append("&obsPort=").append(cfg.hostPort.coerceIn(1, 65535))
        if (cfg.obsPassword.isNotEmpty()) {
            sb.append("&obsPass=").append(encode(cfg.obsPassword))
        }
        if (cfg.internetPairingCode.isNotBlank()) {
            sb.append("&wan=").append(encode(cfg.internetPairingCode.trim()))
        }
        return sb.toString()
    }
}
