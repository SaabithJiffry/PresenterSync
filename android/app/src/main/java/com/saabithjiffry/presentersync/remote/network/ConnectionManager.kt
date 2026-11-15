package com.saabithjiffry.presentersync.remote.network

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import com.saabithjiffry.presentersync.remote.config.AppConstants
import com.saabithjiffry.presentersync.remote.config.NetworkMode
import com.saabithjiffry.presentersync.remote.config.RemoteConfig
import com.saabithjiffry.presentersync.remote.config.RemoteConfigStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONObject
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

enum class ConnStatus {
    SEARCHING,
    CONNECTED,
    AUTH_FAILED,
    MIC_ERROR
}

data class ConnectionUiState(
    val connected: Boolean = false,
    val connStatus: ConnStatus = ConnStatus.SEARCHING,
    val activeHost: String = "",
    val usingRelayFallback: Boolean = false,
    val isMuted: Boolean = false,
    val serviceRunning: Boolean = false
)

sealed interface RemoteEvent {
    data class MuteChanged(val isMuted: Boolean) : RemoteEvent
    data class ToastMessage(val message: String) : RemoteEvent
    data object CloseRemoteRequested : RemoteEvent
}

class ConnectionManager(
    private val context: Context,
    private val configStore: RemoteConfigStore
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val mdnsResolver = MdnsResolver(context)

    private val httpClient: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(AppConstants.WS_CONNECT_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        .readTimeout(0, TimeUnit.MILLISECONDS)
        .pingInterval(20, TimeUnit.SECONDS)
        .build()

    private val _uiState = MutableStateFlow(
        ConnectionUiState(isMuted = configStore.current.isMuted)
    )
    val uiState: StateFlow<ConnectionUiState> = _uiState.asStateFlow()

    private val _events = MutableSharedFlow<RemoteEvent>(extraBufferCapacity = 32)
    val events: SharedFlow<RemoteEvent> = _events.asSharedFlow()

    private val generation = AtomicInteger(0)
    private var obsClient: ObsWebSocketClient? = null
    private var relayClient: RelayClient? = null
    private var connectLoopJob: Job? = null
    private var heartbeatJob: Job? = null
    private var networkDebounceJob: Job? = null
    private var networkCallbackRegistered = false

    private val connectivityManager =
        context.applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager

    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            scheduleNetworkReconnect()
        }

        override fun onLost(network: Network) {
            scheduleNetworkReconnect()
        }

        override fun onCapabilitiesChanged(network: Network, networkCapabilities: NetworkCapabilities) {
            val st = _uiState.value
            if (st.serviceRunning && !st.connected && st.connStatus != ConnStatus.AUTH_FAILED) {
                scheduleNetworkReconnect()
            }
        }
    }

    private fun scheduleNetworkReconnect() {
        val st = _uiState.value
        if (!st.serviceRunning || st.connStatus == ConnStatus.AUTH_FAILED) return
        networkDebounceJob?.cancel()
        networkDebounceJob = scope.launch {
            delay(350L)
            verifyOrReconnect()
        }
    }

    fun verifyOrReconnect() {
        val st = _uiState.value
        if (!st.serviceRunning || st.connStatus == ConnStatus.AUTH_FAILED) return
        if (!st.connected) {
            reconnectNow()
        } else {
            // Probe live socket immediately; dead sockets fail fast instead of stalling until heartbeat
            val ok = obsClient?.sendHeartbeat() == true || relayClient != null
            if (!ok) {
                reconnectNow()
            }
        }
    }

    fun start() {
        registerNetworkCallback()
        _uiState.value = _uiState.value.copy(
            serviceRunning = true,
            isMuted = configStore.current.isMuted
        )
        reconnectNow()
    }

    fun stop() {
        generation.incrementAndGet()
        networkDebounceJob?.cancel()
        connectLoopJob?.cancel()
        heartbeatJob?.cancel()
        closeActiveClients()
        unregisterNetworkCallback()
        _uiState.value = _uiState.value.copy(
            connected = false,
            connStatus = ConnStatus.SEARCHING,
            activeHost = "",
            usingRelayFallback = false,
            serviceRunning = false
        )
    }

    fun reconnectNow() {
        val gen = generation.incrementAndGet()
        connectLoopJob?.cancel()
        heartbeatJob?.cancel()
        closeActiveClients()
        _uiState.value = _uiState.value.copy(
            connected = false,
            connStatus = ConnStatus.SEARCHING,
            activeHost = "",
            usingRelayFallback = false
        )
        connectLoopJob = scope.launch {
            runConnectLoop(gen)
        }
    }

    private fun closeActiveClients() {
        obsClient?.close()
        obsClient = null
        relayClient?.close()
        relayClient = null
    }

    private suspend fun runConnectLoop(gen: Int) {
        while (gen == generation.get()) {
            val cfg = configStore.current
            if (cfg.networkMode == NetworkMode.INTERNET) {
                if (cfg.internetPairingCode.isBlank()) {
                    delay(AppConstants.RECONNECT_DELAY_MS)
                    continue
                }
                val result = attemptRelaySession(gen, cfg, isFallback = false)
                if (result == SessionOutcome.AUTH_FAILED || gen != generation.get()) return
                delay(AppConstants.RECONNECT_DELAY_MS)
                continue
            }

            // LAN Multi-candidate failover loop
            val candidates = EndpointParser.parseCandidateEndpoints(cfg.hostAddress, cfg.hostPort)
            var authFailed = false
            var succeededOrStopped = false

            for (cand in candidates) {
                if (gen != generation.get()) return
                val resolvedHost = if (cand.host.endsWith(".local", ignoreCase = true)) {
                    mdnsResolver.resolveHost(cand.host)
                } else {
                    cand.host
                }
                val effectiveUrl = "${cand.scheme}://$resolvedHost:${cand.port}${cand.path}"
                val outcome = attemptObsSession(gen, cfg, cand.raw, effectiveUrl)
                when (outcome) {
                    SessionOutcome.AUTH_FAILED -> {
                        authFailed = true
                        break
                    }
                    SessionOutcome.CANCELLED -> {
                        succeededOrStopped = true
                        break
                    }
                    SessionOutcome.DISCONNECTED -> Unit
                }
            }

            if (authFailed || succeededOrStopped || gen != generation.get()) return

            // Fallback to Internet Relay if configured (matching ShouldRemoteFallbackToRelay)
            if (cfg.enableRelayFallback && cfg.internetPairingCode.isNotBlank()) {
                val relayOutcome = attemptRelaySession(gen, cfg, isFallback = true)
                if (relayOutcome == SessionOutcome.AUTH_FAILED || gen != generation.get()) return
            }

            delay(AppConstants.RECONNECT_DELAY_MS)
        }
    }

    private enum class SessionOutcome { DISCONNECTED, AUTH_FAILED, CANCELLED }

    private suspend fun attemptObsSession(
        gen: Int,
        cfg: RemoteConfig,
        displayRaw: String,
        wsUrl: String
    ): SessionOutcome {
        val done = kotlinx.coroutines.CompletableDeferred<SessionOutcome>()
        val client = ObsWebSocketClient(
            httpClient = httpClient,
            wsUrl = wsUrl,
            password = cfg.obsPassword,
            targetMicName = cfg.targetMicName,
            callbacks = object : ObsSessionCallbacks {
                override fun onIdentified() {
                    if (gen != generation.get()) return
                    _uiState.value = _uiState.value.copy(
                        connected = true,
                        connStatus = ConnStatus.CONNECTED,
                        activeHost = displayRaw,
                        usingRelayFallback = false
                    )
                    startHeartbeat(gen, cfg.heartbeatSeconds)
                }

                override fun onAuthFailed() {
                    if (gen == generation.get()) {
                        _uiState.value = _uiState.value.copy(
                            connected = false,
                            connStatus = ConnStatus.AUTH_FAILED,
                            activeHost = "",
                            usingRelayFallback = false
                        )
                        _events.tryEmit(RemoteEvent.ToastMessage("OBS authentication failed (4009). Check password."))
                    }
                    done.complete(SessionOutcome.AUTH_FAILED)
                }

                override fun onMuteStateChanged(muted: Boolean) {
                    if (gen != generation.get()) return
                    applyNewMuteState(muted)
                }

                override fun onMicError() {
                    if (gen != generation.get()) return
                    _uiState.value = _uiState.value.copy(connStatus = ConnStatus.MIC_ERROR)
                    _events.tryEmit(
                        RemoteEvent.ToastMessage("Audio source '${cfg.targetMicName}' was not found in OBS Studio.")
                    )
                }

                override fun onMicRecovered() {
                    if (gen != generation.get()) return
                    if (_uiState.value.connStatus == ConnStatus.MIC_ERROR) {
                        _uiState.value = _uiState.value.copy(connStatus = ConnStatus.CONNECTED)
                    }
                }

                override fun onCloseRemoteSignal() {
                    if (gen != generation.get()) return
                    _events.tryEmit(RemoteEvent.CloseRemoteRequested)
                }

                override fun onDisconnected(reason: String) {
                    heartbeatJob?.cancel()
                    if (gen == generation.get()) {
                        val st = _uiState.value
                        if (st.connStatus != ConnStatus.AUTH_FAILED) {
                            _uiState.value = st.copy(
                                connected = false,
                                connStatus = ConnStatus.SEARCHING,
                                activeHost = ""
                            )
                        }
                    }
                    done.complete(SessionOutcome.DISCONNECTED)
                }
            }
        )
        obsClient = client
        client.connect()

        return try {
            done.await()
        } finally {
            heartbeatJob?.cancel()
            client.close()
            if (obsClient === client) obsClient = null
        }
    }

    private suspend fun attemptRelaySession(
        gen: Int,
        cfg: RemoteConfig,
        isFallback: Boolean
    ): SessionOutcome {
        val done = kotlinx.coroutines.CompletableDeferred<SessionOutcome>()
        val prefix = if (isFallback) "Relay Bridge" else "Internet"
        val display = "$prefix (${cfg.internetPairingCode})"
        val client = RelayClient(
            httpClient = httpClient,
            pairingCode = cfg.internetPairingCode,
            password = cfg.obsPassword,
            callbacks = object : RelaySessionCallbacks {
                override fun onRelayConnected() {
                    if (gen != generation.get()) return
                    _uiState.value = _uiState.value.copy(
                        connected = true,
                        connStatus = ConnStatus.CONNECTED,
                        activeHost = display,
                        usingRelayFallback = isFallback
                    )
                    startHeartbeat(gen, cfg.heartbeatSeconds)
                }

                override fun onRelayAuthFailed() {
                    if (gen == generation.get()) {
                        _uiState.value = _uiState.value.copy(
                            connected = false,
                            connStatus = ConnStatus.AUTH_FAILED,
                            activeHost = "",
                            usingRelayFallback = false
                        )
                        _events.tryEmit(RemoteEvent.ToastMessage("Internet Relay authentication failed. Check password."))
                    }
                    done.complete(SessionOutcome.AUTH_FAILED)
                }

                override fun onRelayMuteState(muted: Boolean) {
                    if (gen != generation.get()) return
                    if (!_uiState.value.connected) {
                        _uiState.value = _uiState.value.copy(
                            connected = true,
                            connStatus = ConnStatus.CONNECTED,
                            activeHost = display,
                            usingRelayFallback = isFallback
                        )
                    }
                    applyNewMuteState(muted)
                }

                override fun onCloseRemoteSignal() {
                    if (gen != generation.get()) return
                    _events.tryEmit(RemoteEvent.CloseRemoteRequested)
                }

                override fun onRelayDisconnected(reason: String) {
                    heartbeatJob?.cancel()
                    if (gen == generation.get() && _uiState.value.connStatus != ConnStatus.AUTH_FAILED) {
                        _uiState.value = _uiState.value.copy(
                            connected = false,
                            connStatus = ConnStatus.SEARCHING,
                            activeHost = "",
                            usingRelayFallback = false
                        )
                    }
                    done.complete(SessionOutcome.DISCONNECTED)
                }
            }
        )
        relayClient = client
        client.connect()

        return try {
            done.await()
        } finally {
            heartbeatJob?.cancel()
            client.close()
            if (relayClient === client) relayClient = null
        }
    }

    private fun startHeartbeat(gen: Int, heartbeatSeconds: Int) {
        heartbeatJob?.cancel()
        val intervalMs = (heartbeatSeconds.coerceIn(10, 3600) * 1000L)
        heartbeatJob = scope.launch {
            while (gen == generation.get()) {
                delay(intervalMs)
                if (gen != generation.get()) break
                obsClient?.sendHeartbeat()
                relayClient?.sendSyncRequest()
            }
        }
    }

    private fun applyNewMuteState(muted: Boolean) {
        val prev = _uiState.value.isMuted
        configStore.update { it.copy(isMuted = muted) }
        _uiState.value = _uiState.value.copy(isMuted = muted)
        if (prev != muted) {
            _events.tryEmit(RemoteEvent.MuteChanged(muted))
        }
    }

    fun toggleMuteFromHud(): Boolean {
        val st = _uiState.value
        if (!st.connected) {
            _events.tryEmit(RemoteEvent.ToastMessage("PresenterSync Remote: Not connected to OBS host"))
            return false
        }
        val obs = obsClient
        if (obs != null) {
            return obs.sendToggleInputMute()
        }
        val relay = relayClient
        if (relay != null) {
            return relay.sendToggleMute()
        }
        return false
    }

    suspend fun testConnection(
        networkMode: NetworkMode,
        hostAddress: String,
        portStr: String,
        password: String,
        pairingCode: String,
        onProgress: (String) -> Unit
    ): String = withContext(Dispatchers.IO) {
        if (networkMode == NetworkMode.INTERNET) {
            val cleanPair = pairingCode.trim()
            if (cleanPair.isEmpty()) return@withContext "Error: Please enter your Internet Pairing Code."
            onProgress("Testing Internet Relay ($cleanPair)...")
            val topic = RelayCrypto.getInternetRelayTopic(cleanPair)
            val expectedTok = RelayCrypto.getInternetRelayAuthToken(cleanPair, password)
            val wsUrl = "${AppConstants.NTFY_WS_BASE_URL}/$topic/ws"
            val result = kotlinx.coroutines.CompletableDeferred<String>()
            var testWs: WebSocket? = null
            try {
                testWs = httpClient.newWebSocket(Request.Builder().url(wsUrl).build(), object : WebSocketListener() {
                    override fun onOpen(webSocket: WebSocket, response: Response) {
                        val pkt = RelayCrypto.formatRelayPacket("remote", "sync_req", "0", expectedTok)
                        val req = Request.Builder()
                            .url("${AppConstants.NTFY_BASE_URL}/$topic")
                            .header("Cache-Control", "no-cache")
                            .post(pkt.toRequestBodyCompat())
                            .build()
                        try {
                            httpClient.newCall(req).execute().close()
                        } catch (_: Exception) {
                        }
                    }

                    override fun onMessage(webSocket: WebSocket, text: String) {
                        val pkt = RelayCrypto.parseRelayPacket(text)
                        if (pkt != null && pkt.src == "host") {
                            if (pkt.cmd == "auth_error" || pkt.auth != expectedTok) {
                                result.complete("✕ Auth failed on Internet Relay (Check OBS Password)")
                            } else if (pkt.cmd == "state") {
                                result.complete("✓ Connected to Primary Host via Internet Relay ($cleanPair)!")
                            }
                        }
                    }

                    override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                        result.complete("✕ Could not reach Internet Relay (${t.message ?: "check internet"})")
                    }
                })
                val res = withTimeoutOrNull(2800L) { result.await() }
                    ?: "✓ Connected to Internet Relay ($cleanPair) - Waiting for Host response"
                return@withContext res
            } finally {
                try { testWs?.close(1000, "test complete") } catch (_: Exception) {}
            }
        }

        val port = portStr.trim().toIntOrNull()
        if (port == null || port !in 1..65535) {
            return@withContext "Error: Port must be between 1 and 65535."
        }
        if (hostAddress.trim().isEmpty()) {
            return@withContext "Error: No valid host address provided."
        }

        val endpoints = EndpointParser.parseCandidateEndpoints(hostAddress, port)
        endpoints.forEachIndexed { idx, cand ->
            onProgress("Testing ${cand.raw} (${idx + 1}/${endpoints.size})...")
            val resolved = if (cand.host.endsWith(".local", ignoreCase = true)) {
                mdnsResolver.resolveHost(cand.host)
            } else {
                cand.host
            }
            val url = "${cand.scheme}://$resolved:${cand.port}${cand.path}"
            val probe = probeObsCandidate(url, password, cand.raw, idx + 1, endpoints.size)
            if (probe != null) return@withContext probe
        }
        "✕ All ${endpoints.size} candidate(s) unreachable (Check IP, Port & Firewall)"
    }

    private suspend fun probeObsCandidate(
        wsUrl: String,
        password: String,
        rawLabel: String,
        idx: Int,
        total: Int
    ): String? {
        val deferred = kotlinx.coroutines.CompletableDeferred<String?>()
        var wsRef: WebSocket? = null
        try {
            wsRef = httpClient.newWebSocket(Request.Builder().url(wsUrl).build(), object : WebSocketListener() {
                override fun onMessage(webSocket: WebSocket, text: String) {
                    val root = try { JSONObject(text) } catch (_: Exception) { return }
                    when (root.optInt("op", -1)) {
                        0 -> {
                            val d = root.optJSONObject("d")
                            val authObj = d?.optJSONObject("authentication")
                            val auth = if (authObj != null) {
                                val salt = authObj.optString("salt", "")
                                val chal = authObj.optString("challenge", "")
                                if (salt.isNotEmpty() && chal.isNotEmpty()) {
                                    RelayCrypto.computeObsAuthResponse(password, salt, chal)
                                } else null
                            } else null
                            val identify = JSONObject().apply {
                                put("op", 1)
                                put("d", JSONObject().apply {
                                    put("rpcVersion", 1)
                                    put("eventSubscriptions", 0)
                                    if (!auth.isNullOrEmpty()) put("authentication", auth)
                                })
                            }
                            webSocket.send(identify.toString())
                        }
                        2 -> deferred.complete("✓ Connected to $rawLabel ($idx/$total)!")
                    }
                }

                override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                    if (code == 4009) {
                        deferred.complete("✕ Auth failed on $rawLabel (Wrong OBS password)")
                    } else {
                        deferred.complete(null)
                    }
                }

                override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                    deferred.complete(null)
                }
            })
            return withTimeoutOrNull(3000L) { deferred.await() }
        } finally {
            try { wsRef?.close(1000, "probe done") } catch (_: Exception) {}
        }
    }

    private fun String.toRequestBodyCompat() =
        this.toRequestBody("text/plain; charset=utf-8".toMediaType())

    private fun registerNetworkCallback() {
        if (networkCallbackRegistered) return
        try {
            val req = NetworkRequest.Builder()
                .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .build()
            connectivityManager?.registerNetworkCallback(req, networkCallback)
            networkCallbackRegistered = true
        } catch (_: Exception) {
        }
    }

    private fun unregisterNetworkCallback() {
        if (!networkCallbackRegistered) return
        try {
            connectivityManager?.unregisterNetworkCallback(networkCallback)
        } catch (_: Exception) {
        }
        networkCallbackRegistered = false
    }
}
