package com.saabithjiffry.presentersync.remote.network

import com.saabithjiffry.presentersync.remote.config.AppConstants

data class CandidateEndpoint(
    val host: String,
    val port: Int,
    val scheme: String,
    val path: String,
    val url: String,
    val raw: String
)

object EndpointParser {
    private val schemeRegex = Regex("^(wss|ws|https|http)://(.*)$", RegexOption.IGNORE_CASE)

    fun parseCandidateEndpoints(
        rawStr: String,
        defaultPort: Int = AppConstants.DEFAULT_OBS_PORT
    ): List<CandidateEndpoint> {
        val defPort = if (defaultPort in 1..65535) defaultPort else AppConstants.DEFAULT_OBS_PORT
        val endpoints = mutableListOf<CandidateEndpoint>()
        val seen = HashSet<String>()

        for (item in rawStr.split(',', ';')) {
            var clean = item.trim()
            if (clean.isEmpty()) continue

            var scheme = "ws"
            var hasExplicitScheme = false
            val sm = schemeRegex.matchEntire(clean)
            if (sm != null) {
                val rawScheme = sm.groupValues[1].lowercase()
                scheme = if (rawScheme == "wss" || rawScheme == "https") "wss" else "ws"
                clean = sm.groupValues[2].trim()
                hasExplicitScheme = true
            }
            if (clean.isEmpty()) continue

            var path = "/"
            val slashIdx = clean.indexOf('/')
            if (slashIdx >= 0) {
                path = clean.substring(slashIdx).ifEmpty { "/" }
                clean = clean.substring(0, slashIdx)
            }

            var host = clean
            var port = if (hasExplicitScheme && scheme == "wss") 443 else defPort

            if (clean.startsWith("[")) {
                val closeIdx = clean.indexOf(']')
                if (closeIdx > 1) {
                    host = clean.substring(1, closeIdx).trim()
                    val rem = clean.substring(closeIdx + 1).trim()
                    if (rem.startsWith(":")) {
                        val p = rem.substring(1).trim().toIntOrNull()
                        if (p != null && p in 1..65535) port = p
                    }
                }
            } else {
                val colonIdx = clean.indexOf(':')
                if (colonIdx >= 0) {
                    host = clean.substring(0, colonIdx).trim()
                    val p = clean.substring(colonIdx + 1).trim().toIntOrNull()
                    if (p != null && p in 1..65535) port = p
                }
            }

            if (host.isEmpty()) continue

            val formattedHost = if (host.contains(':') && !host.startsWith("[")) "[$host]" else host
            val pathSuffix = if (path != "/") path else ""
            val rawKey = if (scheme == "wss") {
                "wss://$formattedHost:$port$pathSuffix"
            } else {
                "$formattedHost:$port$pathSuffix"
            }
            val urlStr = "$scheme://$formattedHost:$port$path"

            if (seen.add(urlStr)) {
                endpoints += CandidateEndpoint(
                    host = host,
                    port = port,
                    scheme = scheme,
                    path = path,
                    url = urlStr,
                    raw = rawKey
                )
            }
        }

        if (endpoints.isEmpty()) {
            endpoints += CandidateEndpoint(
                host = "127.0.0.1",
                port = defPort,
                scheme = "ws",
                path = "/",
                url = "ws://127.0.0.1:$defPort/",
                raw = "127.0.0.1:$defPort"
            )
        }
        return endpoints
    }
}
