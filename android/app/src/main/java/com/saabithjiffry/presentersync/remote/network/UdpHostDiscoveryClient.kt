package com.saabithjiffry.presentersync.remote.network

import android.content.Context
import android.net.wifi.WifiManager
import com.saabithjiffry.presentersync.remote.config.AppConstants
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.NetworkInterface
import java.net.SocketTimeoutException
import java.util.concurrent.TimeUnit

data class DiscoveredPublicHost(
    val hostUuid: String,
    val deviceName: String,
    val hostIp: String,
    val bridgePort: Int,
    val obsPort: Int,
    val networkMode: String,
    val audioRoutingMode: Int,
    val version: String
) {
    val displayTitle: String
        get() = "$deviceName • :$bridgePort"
}

object UdpHostDiscoveryClient {

    fun parsePublicBeaconJson(rawJson: String, sourceIp: String): DiscoveredPublicHost? {
        val cleanIp = sourceIp.trim()
        if (cleanIp.isEmpty() || rawJson.isBlank()) return null
        val obj = runCatching { JSONObject(rawJson) }.getOrNull() ?: return null
        if (!obj.optString("proto", "").equals(AppConstants.UDP_DISCOVER_V1_PROBE, ignoreCase = false)) {
            return null
        }
        val uuid = obj.optString("hostUuid", "").trim()
        val bPort = obj.optInt("bridgePort", 0)
        if (uuid.isEmpty() || bPort !in 1..65535) {
            return null
        }
        val obsPort = obj.optInt("obsPort", AppConstants.DEFAULT_OBS_PORT)
            .let { if (it in 1..65535) it else AppConstants.DEFAULT_OBS_PORT }
        val devName = obj.optString("deviceName", "").trim().ifEmpty { cleanIp }
        return DiscoveredPublicHost(
            hostUuid = uuid,
            deviceName = devName,
            hostIp = cleanIp,
            bridgePort = bPort,
            obsPort = obsPort,
            networkMode = obj.optString("networkMode", "LAN"),
            audioRoutingMode = obj.optInt("audioRoutingMode", 1),
            version = obj.optString("version", "")
        )
    }

    fun followHostUuidIpShift(
        currentHostsCsv: String,
        pairedHostUuid: String,
        beacons: List<DiscoveredPublicHost>,
        currentBridgePort: Int = AppConstants.DEFAULT_BRIDGE_PORT
    ): Pair<String, Int>? {
        val targetUuid = pairedHostUuid.trim()
        if (targetUuid.isEmpty() || beacons.isEmpty()) return null
        val matched = beacons.firstOrNull {
            it.hostUuid.equals(targetUuid, ignoreCase = true) && it.hostIp.isNotBlank()
        } ?: return null

        val existing = EndpointParser.parseCandidateEndpoints(currentHostsCsv, AppConstants.DEFAULT_OBS_PORT)
        val currentFirst = existing.firstOrNull()?.host?.trim().orEmpty()
        if (currentFirst.equals(matched.hostIp, ignoreCase = true) && currentBridgePort == matched.bridgePort) {
            return null
        }

        val merged = linkedSetOf<String>()
        merged.add(matched.hostIp.trim())
        for (ep in existing) {
            if (merged.size >= 12) break
            val h = ep.host.trim()
            if (h.isNotEmpty() && merged.none { it.equals(h, ignoreCase = true) }) {
                merged.add(h)
            }
        }
        return merged.joinToString(", ") to matched.bridgePort
    }

    suspend fun scanClassroomHosts(
        context: Context?,
        discoverPort: Int = AppConstants.DEFAULT_DISCOVERY_PORT,
        timeoutMs: Long = 900L,
        extraTargets: List<String> = emptyList()
    ): List<DiscoveredPublicHost> = withContext(Dispatchers.IO) {
        if (discoverPort !in 1..65535) return@withContext emptyList()

        val wifiMgr = context?.applicationContext?.getSystemService(Context.WIFI_SERVICE) as? WifiManager
        val lock = try {
            wifiMgr?.createMulticastLock("PresenterSyncPublicDiscovery")?.apply {
                setReferenceCounted(false)
                acquire()
            }
        } catch (_: Exception) {
            null
        }

        var socket: DatagramSocket? = null
        val found = LinkedHashMap<String, DiscoveredPublicHost>()
        try {
            socket = DatagramSocket().apply {
                broadcast = true
                soTimeout = 200
            }

            val probeBytes = AppConstants.UDP_DISCOVER_V1_PROBE.toByteArray(Charsets.UTF_8)
            val targets = linkedSetOf<InetAddress>()
            extraTargets.forEach { raw ->
                val clean = raw.trim()
                if (clean.isNotEmpty()) {
                    runCatching { InetAddress.getByName(clean) }.getOrNull()?.let { targets.add(it) }
                }
            }
            runCatching {
                val ifaces = NetworkInterface.getNetworkInterfaces()
                while (ifaces != null && ifaces.hasMoreElements()) {
                    val iface = ifaces.nextElement()
                    if (!iface.isUp || iface.isLoopback) continue
                    for (ifAddr in iface.interfaceAddresses) {
                        ifAddr.broadcast?.let { targets.add(it) }
                    }
                }
            }
            runCatching { InetAddress.getByName("255.255.255.255") }.getOrNull()?.let { targets.add(it) }

            for (addr in targets) {
                runCatching {
                    socket.send(DatagramPacket(probeBytes, probeBytes.size, addr, discoverPort))
                }
            }

            val deadline = System.currentTimeMillis() + timeoutMs.coerceAtLeast(150L)
            val rxBuf = ByteArray(2048)
            while (System.currentTimeMillis() < deadline) {
                val pkt = DatagramPacket(rxBuf, rxBuf.size)
                try {
                    socket.receive(pkt)
                    val json = String(pkt.data, pkt.offset, pkt.length, Charsets.UTF_8)
                    val srcIp = pkt.address?.hostAddress.orEmpty()
                    val parsed = parsePublicBeaconJson(json, srcIp)
                    if (parsed != null) {
                        found[parsed.hostUuid.lowercase()] = parsed
                    }
                } catch (_: SocketTimeoutException) {
                    // Continue collecting beacons until discovery window completes
                }
            }
        } catch (_: Exception) {
        } finally {
            runCatching { socket?.close() }
            runCatching {
                if (lock != null && lock.isHeld) lock.release()
            }
        }

        found.values.sortedWith(
            compareBy<DiscoveredPublicHost> { it.deviceName.lowercase() }.thenBy { it.hostIp }
        )
    }

    suspend fun probeHostBridgeHealth(
        httpClient: OkHttpClient,
        host: String,
        bridgePort: Int,
        expectedHostUuid: String = "",
        timeoutMs: Long = AppConstants.LAN_REPROMOTE_PROBE_TIMEOUT_MS
    ): Boolean = withContext(Dispatchers.IO) {
        val cleanHost = host.trim()
        if (cleanHost.isEmpty() || bridgePort !in 1..65535) return@withContext false
        val probeClient = httpClient.newBuilder()
            .connectTimeout(timeoutMs, TimeUnit.MILLISECONDS)
            .readTimeout(timeoutMs, TimeUnit.MILLISECONDS)
            .callTimeout(timeoutMs + 300L, TimeUnit.MILLISECONDS)
            .build()
        val req = Request.Builder()
            .url("http://$cleanHost:$bridgePort/health")
            .get()
            .build()
        runCatching {
            probeClient.newCall(req).execute().use { resp ->
                if (!resp.isSuccessful) return@use false
                val body = resp.body?.string().orEmpty()
                val obj = JSONObject(body)
                if (!obj.optBoolean("ok", false)) return@use false
                val gotUuid = obj.optString("hostUuid", "").trim()
                if (expectedHostUuid.isNotBlank() && gotUuid.isNotEmpty() &&
                    !gotUuid.equals(expectedHostUuid.trim(), ignoreCase = true)
                ) {
                    return@use false
                }
                true
            }
        }.getOrDefault(false)
    }

    fun bridgeFallbackSweepPorts(preferredPort: Int = AppConstants.DEFAULT_BRIDGE_PORT): List<Int> {
        val pref = if (preferredPort in 1..65535) preferredPort else AppConstants.DEFAULT_BRIDGE_PORT
        val out = linkedSetOf<Int>()
        out.add(pref)
        out.add(AppConstants.DEFAULT_BRIDGE_PORT)
        for (p in 4458..4465) {
            out.add(p)
        }
        return out.toList()
    }

    suspend fun sweepHostBridgePort(
        httpClient: OkHttpClient,
        host: String,
        preferredPort: Int,
        expectedHostUuid: String = "",
        timeoutMs: Long = AppConstants.LAN_REPROMOTE_PROBE_TIMEOUT_MS
    ): Int? {
        val ports = if (preferredPort in 4456..4465) bridgeFallbackSweepPorts(preferredPort) else listOf(preferredPort)
        for (port in ports) {
            if (probeHostBridgeHealth(httpClient, host, port, expectedHostUuid, timeoutMs)) {
                return port
            }
        }
        return null
    }
}
