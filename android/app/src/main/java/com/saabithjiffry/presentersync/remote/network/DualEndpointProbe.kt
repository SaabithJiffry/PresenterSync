package com.saabithjiffry.presentersync.remote.network

import java.net.HttpURLConnection
import java.net.InetSocketAddress
import java.net.Socket
import java.net.URL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

data class DualProbeResult(
    val bridgeOk: Boolean,
    val bridgeDetail: String,
    val obsOk: Boolean,
    val obsDetail: String
) {
    fun formatSummary(): String = "$bridgeDetail | $obsDetail"
}

object DualEndpointProbe {
    suspend fun probe(
        host: String,
        bridgePort: Int = 4456,
        obsPort: Int = 4455,
        timeoutMs: Int = 1200
    ): DualProbeResult = withContext(Dispatchers.IO) {
        val cleanHost = host.trim()
        val bPort = bridgePort.coerceIn(1, 65535)
        val oPort = obsPort.coerceIn(1, 65535)
        if (cleanHost.isEmpty()) {
            return@withContext DualProbeResult(
                bridgeOk = false,
                bridgeDetail = "Host Bridge (:$bPort): UNREACHABLE",
                obsOk = false,
                obsDetail = "Direct OBS (:$oPort): UNREACHABLE"
            )
        }

        val bridgeOk = runCatching {
            val url = URL("http://$cleanHost:$bPort/health")
            val conn = (url.openConnection() as HttpURLConnection).apply {
                connectTimeout = timeoutMs
                readTimeout = timeoutMs
                requestMethod = "GET"
            }
            try {
                conn.responseCode == HttpURLConnection.HTTP_OK
            } finally {
                conn.disconnect()
            }
        }.getOrDefault(false)

        val obsOk = runCatching {
            Socket().use { sock ->
                sock.connect(InetSocketAddress(cleanHost, oPort), timeoutMs)
                true
            }
        }.getOrDefault(false)

        DualProbeResult(
            bridgeOk = bridgeOk,
            bridgeDetail = "Host Bridge (:$bPort): ${if (bridgeOk) "OK" else "UNREACHABLE"}",
            obsOk = obsOk,
            obsDetail = "Direct OBS (:$oPort): ${if (obsOk) "OK" else "UNREACHABLE"}"
        )
    }
}
