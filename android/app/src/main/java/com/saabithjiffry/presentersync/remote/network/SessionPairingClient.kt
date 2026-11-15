package com.saabithjiffry.presentersync.remote.network

import android.content.Context
import android.net.wifi.WifiManager
import android.os.Build
import android.util.Log
import com.saabithjiffry.presentersync.remote.config.AppConstants
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.NetworkInterface
import java.net.SocketTimeoutException
import java.util.UUID

data class DiscoveredHost(
    val hostIp: String,
    val hostName: String,
    val tcpPort: Int,
    val obsPort: Int,
    val version: String,
    val routingMode: Int
)

data class PairedHostBundle(
    val pairedIp: String,
    val hostName: String,
    val version: String,
    val bridgePort: Int,
    val obsPort: Int,
    val obsPassword: String,
    val targetMicName: String,
    val routingMode: Int,
    val conferencingApp: String,
    val isMuted: Boolean,
    val internetPairingCode: String,
    val sessionToken: String,
    val ips: List<String>,
    val mdns: String
)

sealed interface PairingResult {
    data class Success(val bundle: PairedHostBundle) : PairingResult
    data class Error(val message: String) : PairingResult
}

object SessionPairingClient {
    private val JSON_MEDIA = "application/json; charset=utf-8".toMediaType()

    fun normalizeCode(raw: String): String {
        return raw.trim().replace("-", "").replace(" ", "").uppercase()
    }

    fun isWanRelayCode(raw: String): Boolean {
        return raw.trim().uppercase().startsWith("PS-")
    }

    fun buildCandidateAddressList(pairedIp: String, bundle: PairedHostBundle): String {
        val ordered = linkedSetOf<String>()
        if (pairedIp.isNotBlank()) ordered.add(pairedIp.trim())
        bundle.ips.forEach { ip ->
            if (ip.isNotBlank()) ordered.add(ip.trim())
        }
        if (bundle.mdns.isNotBlank()) ordered.add(bundle.mdns.trim())
        return ordered.joinToString(", ")
    }

    fun getOrCreateDeviceId(context: Context): String {
        val prefs = context.applicationContext.getSharedPreferences("presentersync_remote_prefs", Context.MODE_PRIVATE)
        val existing = prefs.getString("deviceId", null)?.trim()
        if (!existing.isNullOrEmpty()) return existing
        val generated = "sb-" + UUID.randomUUID().toString().take(12)
        prefs.edit().putString("deviceId", generated).apply()
        return generated
    }

    fun parseOfferPacket(raw: String, sourceIp: String): DiscoveredHost? {
        val parts = raw.trim().split("|")
        if (parts.size < 4 || parts[0] != "PSYNC_OFFER") return null
        val hostName = parts[1].ifBlank { sourceIp }
        val tcpPort = parts[2].toIntOrNull()?.takeIf { it in 1..65535 } ?: AppConstants.DEFAULT_BRIDGE_PORT
        val obsPort = parts[3].toIntOrNull()?.takeIf { it in 1..65535 } ?: AppConstants.DEFAULT_OBS_PORT
        val version = parts.getOrNull(4).orEmpty()
        val mode = parts.getOrNull(5)?.toIntOrNull() ?: 0
        return DiscoveredHost(
            hostIp = sourceIp,
            hostName = hostName,
            tcpPort = tcpPort,
            obsPort = obsPort,
            version = version,
            routingMode = mode
        )
    }

    fun parsePairResponse(pairedIp: String, statusCode: Int, jsonBody: String): PairingResult {
        val obj = try {
            JSONObject(jsonBody)
        } catch (_: Exception) {
            null
        }
        if (statusCode == 200 && obj != null && obj.optBoolean("ok", false)) {
            val ipsArr = obj.optJSONArray("ips")
            val ips = buildList {
                if (ipsArr != null) {
                    for (i in 0 until ipsArr.length()) {
                        val ip = ipsArr.optString(i, "").trim()
                        if (ip.isNotEmpty()) add(ip)
                    }
                }
            }
            return PairingResult.Success(
                PairedHostBundle(
                    pairedIp = pairedIp,
                    hostName = obj.optString("hostName", pairedIp),
                    version = obj.optString("version", ""),
                    bridgePort = obj.optInt("bridgePort", AppConstants.DEFAULT_BRIDGE_PORT),
                    obsPort = obj.optInt("obsPort", AppConstants.DEFAULT_OBS_PORT),
                    obsPassword = obj.optString("obsPassword", ""),
                    targetMicName = obj.optString("targetMicName", AppConstants.DEFAULT_MIC_NAME)
                        .ifBlank { AppConstants.DEFAULT_MIC_NAME },
                    routingMode = obj.optInt("routingMode", 0),
                    conferencingApp = obj.optString("conferencingApp", "Zoom"),
                    isMuted = obj.optBoolean("isMuted", false),
                    internetPairingCode = obj.optString("internetPairingCode", ""),
                    sessionToken = obj.optString("sessionToken", ""),
                    ips = ips,
                    mdns = obj.optString("mdns", "")
                )
            )
        }
        val err = obj?.optString("error", "").orEmpty().ifBlank {
            when (statusCode) {
                401 -> "Invalid Session Code. Check the code shown on the Primary Host."
                429 -> "Too many invalid attempts. Wait 30s or click New Code on the Primary Host."
                else -> "Pairing failed (HTTP $statusCode)"
            }
        }
        return PairingResult.Error(err)
    }

    suspend fun discoverHostOnLan(
        context: Context?,
        sessionCode: String,
        udpPort: Int = AppConstants.DEFAULT_BRIDGE_PORT,
        timeoutMs: Long = 1600L,
        extraTargets: List<String> = emptyList(),
        deviceId: String = "android-board",
        deviceName: String = defaultDeviceName()
    ): DiscoveredHost? = withContext(Dispatchers.IO) {
        val norm = normalizeCode(sessionCode)
        if (norm.isEmpty()) return@withContext null

        val wifiMgr = context?.applicationContext?.getSystemService(Context.WIFI_SERVICE) as? WifiManager
        val lock = try {
            wifiMgr?.createMulticastLock("PresenterSyncDiscovery")?.apply {
                setReferenceCounted(false)
                acquire()
            }
        } catch (_: Exception) {
            null
        }

        var socket: DatagramSocket? = null
        try {
            socket = DatagramSocket().apply {
                broadcast = true
                soTimeout = 250
            }

            val payload = "PSYNC_DISCOVER|$norm|$deviceId|$deviceName".toByteArray(Charsets.UTF_8)
            val targets = linkedSetOf<InetAddress>()

            extraTargets.forEach { rawHost ->
                val clean = rawHost.trim()
                if (clean.isNotEmpty()) {
                    try {
                        targets.add(InetAddress.getByName(clean))
                    } catch (_: Exception) {
                    }
                }
            }

            try {
                val ifaces = NetworkInterface.getNetworkInterfaces()
                while (ifaces != null && ifaces.hasMoreElements()) {
                    val iface = ifaces.nextElement()
                    if (!iface.isUp || iface.isLoopback) continue
                    for (ifAddr in iface.interfaceAddresses) {
                        ifAddr.broadcast?.let { targets.add(it) }
                    }
                }
            } catch (_: Exception) {
            }

            try {
                targets.add(InetAddress.getByName("255.255.255.255"))
            } catch (_: Exception) {
            }

            for (addr in targets) {
                try {
                    socket.send(DatagramPacket(payload, payload.size, addr, udpPort))
                } catch (_: Exception) {
                }
            }

            val deadline = System.currentTimeMillis() + timeoutMs
            val recvBuf = ByteArray(1024)
            while (System.currentTimeMillis() < deadline) {
                val pkt = DatagramPacket(recvBuf, recvBuf.size)
                try {
                    socket.receive(pkt)
                    val text = String(pkt.data, pkt.offset, pkt.length, Charsets.UTF_8)
                    val srcIp = pkt.address?.hostAddress.orEmpty()
                    val parsed = parseOfferPacket(text, srcIp)
                    if (parsed != null) {
                        return@withContext parsed
                    }
                } catch (_: SocketTimeoutException) {
                    // continue polling until deadline
                } catch (_: Exception) {
                    break
                }
            }
            null
        } catch (_: Exception) {
            null
        } finally {
            try { socket?.close() } catch (_: Exception) {}
            try { lock?.release() } catch (_: Exception) {}
        }
    }

    suspend fun pairWithHost(
        httpClient: OkHttpClient,
        hostIp: String,
        bridgePort: Int,
        sessionCode: String,
        deviceId: String,
        deviceName: String = defaultDeviceName()
    ): PairingResult = withContext(Dispatchers.IO) {
        val bodyJson = JSONObject().apply {
            put("code", normalizeCode(sessionCode))
            put("deviceId", deviceId)
            put("deviceName", deviceName)
            put("platform", "Android")
        }.toString()

        val req = Request.Builder()
            .url("http://$hostIp:$bridgePort/pair")
            .post(bodyJson.toRequestBody(JSON_MEDIA))
            .build()

        return@withContext try {
            httpClient.newCall(req).execute().use { resp ->
                val text = resp.body?.string().orEmpty()
                runCatching { Log.i("PresenterSync", "POST $hostIp:$bridgePort/pair -> HTTP ${resp.code}") }
                parsePairResponse(hostIp, resp.code, text)
            }
        } catch (e: Exception) {
            runCatching { Log.w("PresenterSync", "POST $hostIp:$bridgePort/pair failed: ${e.message}") }
            PairingResult.Error("Unreachable $hostIp:$bridgePort (${e.message ?: "network error"})")
        }
    }

    suspend fun discoverAndPairLan(
        context: Context?,
        httpClient: OkHttpClient,
        mdnsResolver: MdnsResolver?,
        sessionCode: String,
        fallbackHostCandidates: String,
        bridgePort: Int = AppConstants.DEFAULT_BRIDGE_PORT,
        deviceId: String,
        deviceName: String = defaultDeviceName(),
        onProgress: (String) -> Unit = {}
    ): PairingResult {
        val norm = normalizeCode(sessionCode)
        if (norm.isEmpty()) {
            return PairingResult.Error("Enter the Session Code displayed on your Primary Host PC.")
        }

        val parsedFallback = EndpointParser.parseCandidateEndpoints(fallbackHostCandidates, bridgePort)
            .map { cand ->
                if (cand.host.endsWith(".local", ignoreCase = true) && mdnsResolver != null) {
                    mdnsResolver.resolveHost(cand.host)
                } else {
                    cand.host
                }
            }
            .filter { it.isNotBlank() }

        onProgress("Searching LAN for PresenterSync Host ($sessionCode)...")
        val discovered = discoverHostOnLan(
            context = context,
            sessionCode = norm,
            udpPort = bridgePort,
            extraTargets = parsedFallback,
            deviceId = deviceId,
            deviceName = deviceName
        )

        if (discovered != null) {
            onProgress("Found ${discovered.hostName} (${discovered.hostIp}). Authenticating...")
            return pairWithHost(
                httpClient = httpClient,
                hostIp = discovered.hostIp,
                bridgePort = discovered.tcpPort,
                sessionCode = norm,
                deviceId = deviceId,
                deviceName = deviceName
            )
        }

        // Fallback to direct HTTP /pair against any configured host IPs (handles blocked UDP broadcast / VLANs / 10.0.2.2)
        val directHosts = parsedFallback.distinct()
        var lastErr: String? = null
        for (h in directHosts) {
            onProgress("Trying direct Host Bridge $h:$bridgePort...")
            when (val res = pairWithHost(httpClient, h, bridgePort, norm, deviceId, deviceName)) {
                is PairingResult.Success -> return res
                is PairingResult.Error -> lastErr = res.message
            }
        }

        return PairingResult.Error(
            lastErr ?: "No PresenterSync Host responded for Session Code '$sessionCode'. Check Wi-Fi or enter Host IP."
        )
    }

    private fun defaultDeviceName(): String {
        val model = Build.MODEL.orEmpty().trim()
        return model.ifEmpty { "Smart Board" }
    }
}
