package com.saabithjiffry.presentersync.remote.config

import org.json.JSONObject
import java.net.URI
import java.net.URLDecoder

data class ParsedConnectionPayload(
    val hostsCsv: String,
    val obsPort: Int = AppConstants.DEFAULT_OBS_PORT,
    val bridgePort: Int = AppConstants.DEFAULT_BRIDGE_PORT,
    val obsPassword: String = "",
    val sessionCode: String = "",
    val targetMicName: String = AppConstants.DEFAULT_MIC_NAME,
    val networkMode: NetworkMode = NetworkMode.LAN,
    val internetPairingCode: String = ""
)

object DeepLinkParser {

    fun parse(rawInput: String): ParsedConnectionPayload? {
        val raw = rawInput.trim()
        if (raw.isEmpty()) return null

        if (raw.startsWith("{")) {
            return parseJsonPayload(raw)
        }

        if (!raw.startsWith("presentersync://", ignoreCase = true)) {
            return null
        }

        val uri = runCatching { URI(raw) }.getOrNull() ?: return null
        val action = (uri.host ?: uri.authority).orEmpty().lowercase()
        if (action.isNotEmpty() && action != "connect" && action != "pair") {
            return null
        }

        val queryParams = parseQueryString(uri.rawQuery.orEmpty())
        val hosts = queryParams["hosts"].orEmpty()
            .ifBlank { queryParams["host"].orEmpty() }
            .trim()
        val sessionCode = SessionPairingCodeNormalizer.normalize(queryParams["code"].orEmpty())
        val internetCode = queryParams["rc"].orEmpty()
            .ifBlank { queryParams["relayCode"].orEmpty() }
            .trim()
            .uppercase()

        if (hosts.isEmpty() && sessionCode.isEmpty() && internetCode.isEmpty()) {
            return null
        }

        val obsPort = queryParams["port"]?.toIntOrNull()?.takeIf { it in 1..65535 }
            ?: AppConstants.DEFAULT_OBS_PORT
        val bridgePort = queryParams["bp"]?.toIntOrNull()?.takeIf { it in 1..65535 }
            ?: queryParams["bridgePort"]?.toIntOrNull()?.takeIf { it in 1..65535 }
            ?: AppConstants.DEFAULT_BRIDGE_PORT
        val obsPw = queryParams["pw"].orEmpty().ifEmpty { queryParams["password"].orEmpty() }
        val mic = queryParams["mic"].orEmpty().trim().ifEmpty { AppConstants.DEFAULT_MIC_NAME }
        val mode = if (queryParams["mode"].equals("internet", ignoreCase = true)) {
            NetworkMode.INTERNET
        } else {
            NetworkMode.LAN
        }

        return ParsedConnectionPayload(
            hostsCsv = hosts,
            obsPort = obsPort,
            bridgePort = bridgePort,
            obsPassword = obsPw,
            sessionCode = sessionCode,
            targetMicName = mic,
            networkMode = mode,
            internetPairingCode = internetCode
        )
    }

    private fun parseJsonPayload(rawJson: String): ParsedConnectionPayload? {
        return runCatching {
            val json = JSONObject(rawJson)
            val hosts = json.optString("hosts", json.optString("host", "")).trim()
            val code = SessionPairingCodeNormalizer.normalize(json.optString("code", ""))
            val rc = json.optString("rc", json.optString("relayCode", "")).trim().uppercase()
            if (hosts.isEmpty() && code.isEmpty() && rc.isEmpty()) return null
            val obsPort = json.optInt("port", AppConstants.DEFAULT_OBS_PORT).takeIf { it in 1..65535 }
                ?: AppConstants.DEFAULT_OBS_PORT
            val bp = json.optInt("bp", json.optInt("bridgePort", AppConstants.DEFAULT_BRIDGE_PORT))
                .takeIf { it in 1..65535 } ?: AppConstants.DEFAULT_BRIDGE_PORT
            val pw = json.optString("pw", json.optString("password", ""))
            val mic = json.optString("mic", AppConstants.DEFAULT_MIC_NAME).trim().ifEmpty { AppConstants.DEFAULT_MIC_NAME }
            val mode = if (json.optString("mode", "lan").equals("internet", ignoreCase = true)) {
                NetworkMode.INTERNET
            } else {
                NetworkMode.LAN
            }
            ParsedConnectionPayload(
                hostsCsv = hosts,
                obsPort = obsPort,
                bridgePort = bp,
                obsPassword = pw,
                sessionCode = code,
                targetMicName = mic,
                networkMode = mode,
                internetPairingCode = rc
            )
        }.getOrNull()
    }

    private fun parseQueryString(rawQuery: String): Map<String, String> {
        if (rawQuery.isBlank()) return emptyMap()
        val out = LinkedHashMap<String, String>()
        for (pair in rawQuery.split("&")) {
            if (pair.isEmpty()) continue
            val eqIdx = pair.indexOf('=')
            val rawKey = if (eqIdx >= 0) pair.substring(0, eqIdx) else pair
            val rawVal = if (eqIdx >= 0) pair.substring(eqIdx + 1) else ""
            val key = decodePart(rawKey)
            val value = decodePart(rawVal)
            if (key.isNotEmpty()) {
                out[key] = value
            }
        }
        return out
    }

    private fun decodePart(part: String): String {
        return runCatching { URLDecoder.decode(part, "UTF-8") }.getOrDefault(part)
    }
}

private object SessionPairingCodeNormalizer {
    fun normalize(raw: String): String {
        val compact = raw.uppercase().replace("-", "").replace(" ", "")
        if (compact.length == 6 && compact.all { it.isLetterOrDigit() }) {
            return "${compact.substring(0, 3)}-${compact.substring(3, 6)}"
        }
        return raw.trim().uppercase()
    }
}
