package com.saabithjiffry.presentersync.remote.network

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.SystemClock
import android.util.Log
import com.saabithjiffry.presentersync.remote.config.AppConstants
import com.saabithjiffry.presentersync.remote.config.HudColorPalettes
import com.saabithjiffry.presentersync.remote.config.NetworkMode
import com.saabithjiffry.presentersync.remote.config.ParsedConnectionPayload
import com.saabithjiffry.presentersync.remote.config.RemoteConfig
import com.saabithjiffry.presentersync.remote.config.RemoteConfigStore
import com.saabithjiffry.presentersync.remote.util.DiagnosticLogger
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
import java.util.concurrent.atomic.AtomicLong

enum class ConnStatus {
    SEARCHING,
    CONNECTED,
    AUTH_FAILED,
    MIC_ERROR
}

enum class ChannelType {
    NONE,
    HOST_BRIDGE,
    DIRECT_OBS,
    WAN_RELAY
}

typealias ConnectionChannel = ChannelType

data class PresenterTimerState(
    val timerState: String = "stopped",
    val timerRemainingSec: Int = 600,
    val timerPresetSec: Int = 600
)

data class ConnectionUiState(
    val connected: Boolean = false,
    val connStatus: ConnStatus = ConnStatus.SEARCHING,
    val activeHost: String = "",
    val usingRelayFallback: Boolean = false,
    val usingBridge: Boolean = false,
    val usingDirectObsFallback: Boolean = false,
    val studioModeActive: Boolean = false,
    val previewScene: String = "",
    val previousProgramScene: String = "",
    val isMuted: Boolean = false,
    val serviceRunning: Boolean = false,
    val recState: Int = 0,
    val recSeconds: Int = 0,
    val streamDropWarn: Boolean = false,
    val voiceWhileMuted: Boolean = false,
    val osMicMutedDrift: Boolean = false,
    val lowDiskWarnLevel: Int = 0,
    val lowDiskMb: Int = -1,
    val deadMicWarn: Boolean = false,
    val activeScene: String = "Scene",
    val scenes: List<String> = emptyList(),
    val quickNudges: List<String> = emptyList(),
    val isStandby: Boolean = false,
    val standbyScene: String = "BRB",
    val timerState: String = "stopped",
    val timerRemainingSec: Int = 600,
    val timerPresetSec: Int = 600,
    val slideIndex: Int = 0,
    val slideTotal: Int = 0,
    val slideTitle: String = "",
    val slideNotes: String = ""
) {
    val currentSceneName: String
        get() = activeScene

    val previewSceneName: String
        get() = previewScene

    val channelType: ChannelType
        get() = when {
            !connected -> ChannelType.NONE
            usingBridge -> ChannelType.HOST_BRIDGE
            usingRelayFallback -> ChannelType.WAN_RELAY
            else -> ChannelType.DIRECT_OBS
        }

    val transportName: String
        get() = when {
            usingBridge -> "Host Bridge"
            usingRelayFallback -> "WAN Relay"
            usingDirectObsFallback -> "Direct OBS Fallback"
            else -> "OBS WebSocket"
        }

    val isRecordingActive: Boolean
        get() = recState == 1 || recState == 2

    fun formattedRecElapsed(): String {
        val total = recSeconds.coerceAtLeast(0)
        val hrs = total / 3600
        val mins = (total % 3600) / 60
        val secs = total % 60
        return if (hrs > 0) String.format("%d:%02d:%02d", hrs, mins, secs)
        else String.format("%02d:%02d", mins, secs)
    }

    fun formattedCountdown(): String {
        val neg = timerRemainingSec < 0
        val absSec = kotlin.math.abs(timerRemainingSec)
        val hrs = absSec / 3600
        val mins = (absSec % 3600) / 60
        val secs = absSec % 60
        val core = if (hrs > 0) String.format("%d:%02d:%02d", hrs, mins, secs)
        else String.format("%02d:%02d", mins, secs)
        return if (neg) "-$core" else core
    }
}

sealed interface RemoteEvent {
    data class MuteChanged(val isMuted: Boolean) : RemoteEvent
    data class ToastMessage(val message: String) : RemoteEvent
    data class StageNudge(val message: String, val sender: String, val accentHex: String = "F59E0B") : RemoteEvent
    data object VoiceWhileMutedAlert : RemoteEvent
    data object CloseRemoteRequested : RemoteEvent
}

class ConnectionManager(
    private val context: Context,
    private val configStore: RemoteConfigStore,
    private val clockMs: () -> Long = { SystemClock.elapsedRealtime() }
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val mdnsResolver = MdnsResolver(context)

    private val httpClient: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(AppConstants.WS_CONNECT_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        .readTimeout(0, TimeUnit.MILLISECONDS)
        .pingInterval(20, TimeUnit.SECONDS)
        .build()

    val sharedHttpClient: OkHttpClient
        get() = httpClient

    private val _uiState = MutableStateFlow(
        ConnectionUiState(isMuted = configStore.current.isMuted)
    )
    val uiState: StateFlow<ConnectionUiState> = _uiState.asStateFlow()

    private val _events = MutableSharedFlow<RemoteEvent>(extraBufferCapacity = 32)
    val events: SharedFlow<RemoteEvent> = _events.asSharedFlow()

    private val generation = AtomicInteger(0)
    private var bridgeClient: HostBridgeClient? = null
    private var obsClient: ObsWebSocketClient? = null
    private var relayClient: RelayClient? = null
    private var connectLoopJob: Job? = null
    private var heartbeatJob: Job? = null
    private var pongWatchdogJob: Job? = null
    private var recTickerJob: Job? = null
    private var presenterTimerJob: Job? = null
    private var networkDebounceJob: Job? = null
    private var lanRepromoteJob: Job? = null
    private var networkCallbackRegistered = false
    @Volatile
    internal var lastRxAtMs: Long = -1L
        private set
    private val rxSeq = AtomicLong(0L)
    @Volatile
    private var lastWakeReconnectAtMs: Long = Long.MIN_VALUE
    internal var pongTimeoutMs: Long = PONG_TIMEOUT_MS
    internal var wakeStalenessMs: Long = WAKE_STALENESS_MS
    internal var bridgeConnectTimeoutMs: Long = BRIDGE_CONNECT_TIMEOUT_MS
    internal var discoverPortOverride: Int = AppConstants.DEFAULT_DISCOVERY_PORT
    internal var failoverBudgetMs: Long = AppConstants.LAN_FAILOVER_DEADLINE_MS
    internal var repromoteIntervalMs: Long = BRIDGE_REPROMOTE_INTERVAL_MS

    internal data class LocalStandbySnapshot(
        val previousScene: String,
        val wasMuted: Boolean,
        val recWasActive: Boolean = false
    )

    @Volatile
    internal var localStandbySnapshot: LocalStandbySnapshot? = null

    private val connectivityManager = runCatching {
        context.applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
    }.getOrNull()

    private fun logInfo(msg: String) {
        runCatching { Log.i("PresenterSync", msg) }
    }

    private fun logWarn(msg: String) {
        runCatching { Log.w("PresenterSync", msg) }
    }

    internal fun markRxActivity() {
        lastRxAtMs = clockMs()
        rxSeq.incrementAndGet()
        pongWatchdogJob?.cancel()
        pongWatchdogJob = null
    }

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
            onScreenWakeOrNetworkChanged()
        }
    }

    fun onScreenWakeOrNetworkChanged() {
        val st = _uiState.value
        if (!st.serviceRunning || st.connStatus == ConnStatus.AUTH_FAILED) return
        if (st.usingRelayFallback) {
            val activeGen = generation.get()
            scope.launch { checkAndPromoteLanIfHealthy(activeGen) }
            return
        }
        val nowMs = clockMs()
        if (!st.connected) {
            val recentWakeReconnect = connectLoopJob?.isActive == true &&
                lastWakeReconnectAtMs != Long.MIN_VALUE &&
                (nowMs - lastWakeReconnectAtMs) in 0L until 800L
            if (!recentWakeReconnect) {
                lastWakeReconnectAtMs = nowMs
                reconnectNow()
            }
            return
        }
        if (FailoverPolicy.isWakeConnectionStale(lastRxAtMs, nowMs, wakeStalenessMs)) {
            logInfo("Screen wake / network change detected stale connection (idle=${nowMs - lastRxAtMs}ms > ${wakeStalenessMs}ms); forcing reconnectNow()")
            lastWakeReconnectAtMs = nowMs
            markSocketDeadAndClose()
            reconnectNow()
            return
        }
        sendPingWithPongWatchdog(generation.get())
    }

    fun verifyOrReconnect() {
        onScreenWakeOrNetworkChanged()
    }

    suspend fun scanClassroomHosts(timeoutMs: Long = 900L): List<DiscoveredPublicHost> {
        return UdpHostDiscoveryClient.scanClassroomHosts(
            context = context,
            discoverPort = discoverPortOverride,
            timeoutMs = timeoutMs
        )
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
        cancelSessionJobs(
            includeConnectLoop = true,
            includeNetworkDebounce = true,
            includePresenterTimer = true
        )
        lastRxAtMs = -1L
        closeActiveClients()
        unregisterNetworkCallback()
        transitionToDisconnected(clearSessionTelemetry = true, stopService = true)
    }

    fun reconnectNow() {
        val gen = generation.incrementAndGet()
        cancelSessionJobs(includeConnectLoop = true)
        lastRxAtMs = -1L
        closeActiveClients()
        transitionToDisconnected()
        connectLoopJob = scope.launch {
            runConnectLoop(gen)
        }
    }

    private fun cancelSessionJobs(
        includeConnectLoop: Boolean = false,
        includeNetworkDebounce: Boolean = false,
        includePresenterTimer: Boolean = false,
        includeRecTicker: Boolean = true,
        includeRepromote: Boolean = true
    ) {
        if (includeNetworkDebounce) networkDebounceJob?.cancel()
        if (includeConnectLoop) connectLoopJob?.cancel()
        heartbeatJob?.cancel()
        pongWatchdogJob?.cancel()
        pongWatchdogJob = null
        if (includeRecTicker) recTickerJob?.cancel()
        if (includePresenterTimer) presenterTimerJob?.cancel()
        if (includeRepromote) lanRepromoteJob?.cancel()
    }

    private fun transitionToConnected(
        channel: ChannelType,
        activeHost: String,
        isFallback: Boolean = false
    ) {
        _uiState.value = _uiState.value.copy(
            connected = true,
            connStatus = ConnStatus.CONNECTED,
            activeHost = activeHost,
            usingBridge = channel == ChannelType.HOST_BRIDGE,
            usingDirectObsFallback = channel == ChannelType.DIRECT_OBS && isFallback,
            usingRelayFallback = channel == ChannelType.WAN_RELAY && isFallback
        )
    }

    private fun transitionToDisconnected(
        clearSessionTelemetry: Boolean = false,
        stopService: Boolean = false,
        preserveAuthFailed: Boolean = false
    ) {
        val cur = _uiState.value
        if (preserveAuthFailed && cur.connStatus == ConnStatus.AUTH_FAILED) return
        _uiState.value = cur.copy(
            connected = false,
            connStatus = ConnStatus.SEARCHING,
            activeHost = "",
            usingRelayFallback = false,
            usingBridge = false,
            usingDirectObsFallback = false,
            studioModeActive = if (stopService) false else cur.studioModeActive,
            previewScene = if (stopService) "" else cur.previewScene,
            serviceRunning = if (stopService) false else cur.serviceRunning,
            recState = 0,
            recSeconds = 0,
            streamDropWarn = false,
            voiceWhileMuted = false,
            osMicMutedDrift = false,
            lowDiskWarnLevel = 0,
            lowDiskMb = -1,
            deadMicWarn = false,
            isStandby = if (clearSessionTelemetry) false else cur.isStandby,
            standbyScene = if (clearSessionTelemetry) "BRB" else cur.standbyScene,
            timerState = if (clearSessionTelemetry) "stopped" else cur.timerState,
            scenes = if (clearSessionTelemetry) emptyList() else cur.scenes,
            quickNudges = emptyList(),
            slideIndex = 0,
            slideTotal = 0,
            slideTitle = "",
            slideNotes = ""
        )
    }

    private fun transitionToAuthFailed(toastMessage: String? = null) {
        _uiState.value = _uiState.value.copy(
            connected = false,
            connStatus = ConnStatus.AUTH_FAILED,
            activeHost = "",
            usingRelayFallback = false,
            usingBridge = false,
            usingDirectObsFallback = false
        )
        if (!toastMessage.isNullOrEmpty()) {
            _events.tryEmit(RemoteEvent.ToastMessage(toastMessage))
        }
    }

    private fun updateProgramSceneState(sceneName: String) {
        val cur = _uiState.value
        val prevProg = if (cur.activeScene.isNotBlank() && cur.activeScene != "Scene" && cur.activeScene != sceneName) {
            cur.activeScene
        } else {
            cur.previousProgramScene
        }
        _uiState.value = cur.copy(
            previousProgramScene = prevProg,
            activeScene = sceneName
        )
    }

    private fun teardownAllTransports(forceDead: Boolean) {
        if (forceDead) {
            bridgeClient?.closeDead()
            obsClient?.closeDead()
            relayClient?.closeDead()
        } else {
            bridgeClient?.close()
            obsClient?.close()
            relayClient?.close()
        }
        bridgeClient = null
        obsClient = null
        relayClient = null
    }

    private fun closeActiveClients() = teardownAllTransports(forceDead = false)

    private fun markSocketDeadAndClose() {
        pongWatchdogJob?.cancel()
        pongWatchdogJob = null
        teardownAllTransports(forceDead = true)
    }

    internal fun sendPingWithPongWatchdog(expectedGen: Int = generation.get()): Boolean {
        val st = _uiState.value
        if (!st.serviceRunning || !st.connected || expectedGen != generation.get()) return false

        bridgeClient?.let { bridge ->
            return dispatchPingWithWatchdog(expectedGen, "Host Bridge ping") { bridge.sendPing() }
        }
        obsClient?.let { obs ->
            return dispatchPingWithWatchdog(expectedGen, "OBS WebSocket heartbeat") { obs.sendHeartbeat() }
        }
        relayClient?.let { relay ->
            relay.sendSyncRequest()
            return true
        }

        reconnectNow()
        return false
    }

    private fun dispatchPingWithWatchdog(
        expectedGen: Int,
        transportLabel: String,
        sendProbe: () -> Boolean
    ): Boolean {
        val rxSeqBefore = rxSeq.get()
        val rxAtBefore = lastRxAtMs
        if (!sendProbe()) {
            logWarn("$transportLabel send failed; closing dead socket and reconnecting")
            markSocketDeadAndClose()
            reconnectNow()
            return false
        }
        schedulePongWatchdog(expectedGen, rxSeqBefore, rxAtBefore)
        return true
    }

    private fun schedulePongWatchdog(expectedGen: Int, rxSeqBefore: Long, rxAtBefore: Long) {
        if (rxSeq.get() > rxSeqBefore || lastRxAtMs > rxAtBefore) return
        pongWatchdogJob?.cancel()
        pongWatchdogJob = scope.launch {
            delay(pongTimeoutMs)
            if (expectedGen != generation.get()) return@launch
            val cur = _uiState.value
            if (!cur.serviceRunning || !cur.connected) return@launch
            if (rxSeq.get() <= rxSeqBefore && lastRxAtMs <= rxAtBefore) {
                logWarn("Pong watchdog expired after ${pongTimeoutMs}ms without frame/pong; marking socket dead and reconnecting")
                markSocketDeadAndClose()
                reconnectNow()
            }
        }
    }

    private suspend fun refreshConfigForHostUuidShift(cfg: RemoteConfig, logShift: Boolean): RemoteConfig {
        if (cfg.pairedHostUuid.isBlank()) return cfg
        val beacons = UdpHostDiscoveryClient.scanClassroomHosts(
            context = context,
            discoverPort = discoverPortOverride,
            timeoutMs = 450L
        )
        val shift = UdpHostDiscoveryClient.followHostUuidIpShift(
            currentHostsCsv = cfg.hostAddress,
            pairedHostUuid = cfg.pairedHostUuid,
            beacons = beacons,
            currentBridgePort = cfg.bridgePort
        ) ?: return cfg
        configStore.update { prev ->
            prev.copy(hostAddress = shift.first, bridgePort = shift.second)
        }
        if (logShift) {
            logInfo("Auto-followed HostUuid DHCP shift -> ${shift.first}:${shift.second}")
        }
        return configStore.current
    }

    private suspend fun resolveCandidateHost(host: String, mdnsTimeoutMs: Long?): String {
        if (!host.endsWith(".local", ignoreCase = true)) return host
        return if (mdnsTimeoutMs != null) {
            withTimeoutOrNull(mdnsTimeoutMs) { mdnsResolver.resolveHost(host) } ?: host
        } else {
            mdnsResolver.resolveHost(host)
        }
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

            // Auto-follow DHCP IP shift on paired HostUuid before cycling LAN endpoints
            val lanCycleStartMs = System.currentTimeMillis()
            var effectiveCfg = refreshConfigForHostUuidShift(cfg, logShift = true)

            // LAN Multi-candidate failover loop (bounded <= failoverBudgetMs when WAN Relay fallback is ready)
            val hasWanFallback = FailoverPolicy.hasWanFallbackConfigured(effectiveCfg)
            val candidates = EndpointParser.parseCandidateEndpoints(effectiveCfg.hostAddress, effectiveCfg.hostPort)
            var stopConnectLoop = false

            for (cand in candidates) {
                if (gen != generation.get()) return
                val elapsedMs = System.currentTimeMillis() - lanCycleStartMs
                if (hasWanFallback && FailoverPolicy.shouldFallbackToWan(effectiveCfg, elapsedMs, failoverBudgetMs)) {
                    logInfo("LAN probe budget (${elapsedMs}ms) reached; switching to WAN Relay")
                    break
                }

                val step = attemptLanCandidate(gen, effectiveCfg, cand, lanCycleStartMs, hasWanFallback)
                effectiveCfg = step.updatedConfig
                when (step.outcome) {
                    LanCandidateOutcome.STOP_LOOP -> {
                        stopConnectLoop = true
                        break
                    }
                    LanCandidateOutcome.SWITCH_TO_WAN -> break
                    LanCandidateOutcome.NEXT_CANDIDATE -> Unit
                }
            }

            if (stopConnectLoop || gen != generation.get()) return

            // Fallback to Internet Relay if configured (matching ShouldRemoteFallbackToRelay)
            if (FailoverPolicy.hasWanFallbackConfigured(effectiveCfg)) {
                val relayOutcome = attemptRelaySession(gen, effectiveCfg, isFallback = true)
                if (relayOutcome == SessionOutcome.AUTH_FAILED || gen != generation.get()) return
            }

            delay(AppConstants.RECONNECT_DELAY_MS)
        }
    }

    private enum class LanCandidateOutcome { NEXT_CANDIDATE, SWITCH_TO_WAN, STOP_LOOP }

    private data class LanCandidateStep(
        val outcome: LanCandidateOutcome,
        val updatedConfig: RemoteConfig
    )

    private suspend fun attemptLanCandidate(
        gen: Int,
        initialCfg: RemoteConfig,
        cand: CandidateEndpoint,
        lanCycleStartMs: Long,
        hasWanFallback: Boolean
    ): LanCandidateStep {
        var effectiveCfg = initialCfg
        val remBudgetMs = FailoverPolicy.perCandidateBudgetRemainingMs(
            lanCycleStartMs,
            System.currentTimeMillis(),
            failoverBudgetMs
        )
        val resolvedHost = resolveCandidateHost(cand.host, minOf(1100L, remBudgetMs.coerceAtLeast(350L)))

        // Prefer Primary Host Companion Bridge (4456) when Session Code or Token is present
        var bridgeAuthRejected = false
        if (FailoverPolicy.hasBridgeCredentials(effectiveCfg)) {
            val bridgeUrl = "ws://$resolvedHost:${effectiveCfg.bridgePort}/ws"
            logInfo("Attempting Host Bridge WebSocket: $bridgeUrl (hasToken=${effectiveCfg.sessionToken.isNotBlank()})")
            var bridgeAttempt = attemptBridgeSession(gen, effectiveCfg, "${cand.host}:${effectiveCfg.bridgePort}", bridgeUrl)
            if (bridgeAttempt.outcome == SessionOutcome.AUTH_FAILED &&
                gen == generation.get() &&
                shouldRetryBridgeAuthWithPairingCode(effectiveCfg, bridgeAttempt.authErrorReason)
            ) {
                logInfo("Host Bridge rejected stale sessionToken (${bridgeAttempt.authErrorReason}); retrying auth with saved sessionPairingCode")
                configStore.update { prev -> prev.copy(sessionToken = "") }
                effectiveCfg = configStore.current
                bridgeAttempt = attemptBridgeSession(gen, effectiveCfg, "${cand.host}:${effectiveCfg.bridgePort}", bridgeUrl)
            }
            when (bridgeAttempt.outcome) {
                SessionOutcome.CANCELLED -> return LanCandidateStep(LanCandidateOutcome.STOP_LOOP, effectiveCfg)
                SessionOutcome.AUTH_FAILED -> bridgeAuthRejected = true
                SessionOutcome.DISCONNECTED -> {
                    DiagnosticLogger.recordBreadcrumb(
                        "Failover",
                        "BridgeToDirectObsFallback",
                        "Bridge ${cand.host}:${effectiveCfg.bridgePort} unreachable/closed -> falling back to Direct OBS :${cand.port}"
                    )
                }
            }
        }
        if (gen != generation.get()) return LanCandidateStep(LanCandidateOutcome.STOP_LOOP, effectiveCfg)
        if (hasWanFallback && FailoverPolicy.shouldFallbackToWan(
                effectiveCfg,
                System.currentTimeMillis() - lanCycleStartMs,
                failoverBudgetMs
            )
        ) {
            return LanCandidateStep(LanCandidateOutcome.SWITCH_TO_WAN, effectiveCfg)
        }

        // Direct OBS :4455 WebSocket fallback
        val effectiveUrl = "${cand.scheme}://$resolvedHost:${cand.port}${cand.path}"
        return when (attemptObsSession(gen, effectiveCfg, cand.raw, effectiveUrl, isBridgeFallback = true)) {
            SessionOutcome.AUTH_FAILED,
            SessionOutcome.CANCELLED -> LanCandidateStep(LanCandidateOutcome.STOP_LOOP, effectiveCfg)
            SessionOutcome.DISCONNECTED -> {
                if (bridgeAuthRejected && effectiveCfg.obsPassword.isBlank()) {
                    transitionToAuthFailed()
                    LanCandidateStep(LanCandidateOutcome.STOP_LOOP, effectiveCfg)
                } else {
                    LanCandidateStep(LanCandidateOutcome.NEXT_CANDIDATE, effectiveCfg)
                }
            }
        }
    }

    private enum class SessionOutcome { DISCONNECTED, AUTH_FAILED, CANCELLED }

    private data class BridgeAttemptResult(
        val outcome: SessionOutcome,
        val authErrorReason: String = ""
    )

    internal fun isExplicitBridgeRevocation(reason: String): Boolean =
        FailoverPolicy.isExplicitBridgeRevocation(reason)

    internal fun shouldRetryBridgeAuthWithPairingCode(cfg: RemoteConfig, reason: String): Boolean =
        FailoverPolicy.shouldRetryBridgeAuthWithPairingCode(cfg, reason)

    private suspend fun attemptBridgeSession(
        gen: Int,
        cfg: RemoteConfig,
        displayRaw: String,
        wsUrl: String
    ): BridgeAttemptResult {
        val done = kotlinx.coroutines.CompletableDeferred<BridgeAttemptResult>()
        val devId = SessionPairingClient.getOrCreateDeviceId(context)
        val devName = android.os.Build.MODEL.orEmpty().trim().ifEmpty { "Smart Board" }
        val timeoutMs = bridgeConnectTimeoutMs.coerceAtLeast(300L)
        val bridgeHttp = httpClient.newBuilder()
            .connectTimeout(timeoutMs, TimeUnit.MILLISECONDS)
            .build()
        var handshakeTimeoutJob: Job? = null
        val client = HostBridgeClient(
            httpClient = bridgeHttp,
            wsBaseUrl = wsUrl,
            sessionToken = cfg.sessionToken,
            sessionCode = cfg.sessionPairingCode,
            deviceId = devId,
            deviceName = devName,
            callbacks = object : HostBridgeCallbacks {
                override fun onBridgeConnected(hostName: String) {
                    if (gen != generation.get()) return
                    handshakeTimeoutJob?.cancel()
                    markRxActivity()
                    transitionToConnected(ChannelType.HOST_BRIDGE, "$hostName ($displayRaw)")
                    DiagnosticLogger.recordBreadcrumb("Connection", "HostBridgeConnected", "$hostName ($displayRaw)")
                    startHeartbeat(gen, cfg.heartbeatSeconds)
                }

                override fun onBridgeFrameReceived() {
                    if (gen == generation.get()) {
                        markRxActivity()
                    }
                }

                override fun onBridgeSessionTokenRefreshed(sessionToken: String) {
                    if (gen != generation.get() || sessionToken.isBlank()) return
                    if (configStore.current.sessionToken != sessionToken) {
                        configStore.update { it.copy(sessionToken = sessionToken) }
                    }
                }

                override fun onBridgeHostUuidReceived(hostUuid: String) {
                    if (gen != generation.get() || hostUuid.isBlank()) return
                    if (!configStore.current.pairedHostUuid.equals(hostUuid, ignoreCase = true)) {
                        configStore.update { it.copy(pairedHostUuid = hostUuid) }
                    }
                }

                override fun onSyncResync(reason: String, hostUuid: String) {
                    if (gen != generation.get()) return
                    if (hostUuid.isNotBlank() && !configStore.current.pairedHostUuid.equals(hostUuid, ignoreCase = true)) {
                        configStore.update { it.copy(pairedHostUuid = hostUuid) }
                    }
                    logInfo("Received host sync_resync ($reason)")
                }

                override fun onBridgeAuthFailed(reason: String) {
                    handshakeTimeoutJob?.cancel()
                    if (gen == generation.get() && !shouldRetryBridgeAuthWithPairingCode(cfg, reason)) {
                        _events.tryEmit(RemoteEvent.ToastMessage("Host Bridge auth failed: $reason"))
                    }
                    done.complete(BridgeAttemptResult(SessionOutcome.AUTH_FAILED, reason))
                }

                override fun onMuteStateChanged(isMuted: Boolean, routingMode: Int, targetMicName: String) {
                    if (gen != generation.get()) return
                    applyNewMuteState(isMuted)
                }

                override fun onTelemetryChanged(telemetry: BridgeTelemetryState) {
                    if (gen != generation.get()) return
                    applyBridgeTelemetry(gen, telemetry)
                }

                override fun onStageNudgeReceived(message: String, sender: String, accentHex: String) {
                    if (gen != generation.get()) return
                    _events.tryEmit(RemoteEvent.StageNudge(message, sender, accentHex))
                }

                override fun onCloseRemoteSignal() {
                    if (gen != generation.get()) return
                    _events.tryEmit(RemoteEvent.CloseRemoteRequested)
                }

                override fun onBridgeDisconnected(reason: String) {
                    handshakeTimeoutJob?.cancel()
                    logWarn("Host Bridge disconnected ($wsUrl): $reason")
                    DiagnosticLogger.recordBreadcrumb("Connection", "HostBridgeDisconnected", "$wsUrl | $reason")
                    cancelSessionJobs(includePresenterTimer = true, includeRepromote = false)
                    if (gen == generation.get()) {
                        transitionToDisconnected(clearSessionTelemetry = true, preserveAuthFailed = true)
                    }
                    done.complete(BridgeAttemptResult(SessionOutcome.DISCONNECTED))
                }
            }
        )
        bridgeClient = client
        client.connect()
        val timeoutJob = scope.launch {
            delay(timeoutMs)
            if (!done.isCompleted && (!_uiState.value.connected || !_uiState.value.usingBridge)) {
                logWarn("Host Bridge connect timeout (${timeoutMs}ms) on $wsUrl; failing over to Direct OBS :4455")
                DiagnosticLogger.recordBreadcrumb("Failover", "BridgeConnectTimeout", "${timeoutMs}ms on $wsUrl")
                client.closeDead()
                done.complete(BridgeAttemptResult(SessionOutcome.DISCONNECTED, "timeout"))
            }
        }
        handshakeTimeoutJob = timeoutJob

        return try {
            done.await()
        } finally {
            timeoutJob.cancel()
            cancelSessionJobs(includeRecTicker = false, includeRepromote = false)
            client.close()
            if (bridgeClient === client) bridgeClient = null
        }
    }

    private suspend fun attemptObsSession(
        gen: Int,
        cfg: RemoteConfig,
        displayRaw: String,
        wsUrl: String,
        isBridgeFallback: Boolean = true
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
                    markRxActivity()
                    transitionToConnected(ChannelType.DIRECT_OBS, displayRaw, isFallback = isBridgeFallback)
                    DiagnosticLogger.recordBreadcrumb(
                        "Failover",
                        "DirectObsFallbackConnected",
                        "host=$displayRaw | fallback=$isBridgeFallback"
                    )
                    startHeartbeat(gen, cfg.heartbeatSeconds)
                    if (FailoverPolicy.hasBridgeCredentials(cfg)) {
                        startLanRepromotionMonitor(gen)
                    }
                }

                override fun onFrameReceived() {
                    if (gen == generation.get()) {
                        markRxActivity()
                    }
                }

                override fun onAuthFailed() {
                    if (gen == generation.get()) {
                        transitionToAuthFailed("OBS authentication failed (4009). Check password.")
                    }
                    done.complete(SessionOutcome.AUTH_FAILED)
                }

                override fun onMuteStateChanged(muted: Boolean) {
                    if (gen != generation.get()) return
                    applyNewMuteState(muted)
                }

                override fun onRecordStateChanged(recState: Int, recSeconds: Int) {
                    if (gen != generation.get()) return
                    val prev = _uiState.value
                    val nextSec = if (recSeconds >= 0) recSeconds else if (recState == 0) 0 else prev.recSeconds
                    _uiState.value = prev.copy(recState = recState, recSeconds = nextSec)
                    updateLocalRecTicker(gen, recState)
                }

                override fun onStreamStateChanged(active: Boolean, reconnecting: Boolean, dropWarn: Boolean) {
                    if (gen != generation.get()) return
                    _uiState.value = _uiState.value.copy(streamDropWarn = dropWarn || reconnecting)
                }

                override fun onStudioModeStateChanged(enabled: Boolean) {
                    if (gen != generation.get()) return
                    _uiState.value = _uiState.value.copy(studioModeActive = enabled)
                }

                override fun onProgramSceneChanged(sceneName: String) {
                    if (gen != generation.get() || sceneName.isBlank()) return
                    updateProgramSceneState(sceneName)
                }

                override fun onPreviewSceneChanged(sceneName: String) {
                    if (gen != generation.get() || sceneName.isBlank()) return
                    _uiState.value = _uiState.value.copy(previewScene = sceneName)
                }

                override fun onSceneListChanged(scenes: List<String>) {
                    if (gen != generation.get() || scenes.isEmpty()) return
                    _uiState.value = _uiState.value.copy(scenes = scenes)
                }

                override fun onSceneTransitionError(requestId: String, code: Int, comment: String) {
                    if (gen != generation.get()) return
                    DiagnosticLogger.recordBreadcrumb(
                        "OBS",
                        "SceneTransitionError",
                        "$requestId code=$code $comment".trim()
                    )
                    _events.tryEmit(
                        RemoteEvent.ToastMessage("OBS scene transition failed (check Studio Mode / scenes)")
                    )
                    obsClient?.sendGetCurrentProgramScene()
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
                    cancelSessionJobs()
                    if (gen == generation.get()) {
                        transitionToDisconnected(preserveAuthFailed = true)
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
            cancelSessionJobs(includeRecTicker = false)
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
            httpBaseUrl = cfg.relayBaseUrl,
            enableEncryption = cfg.enableRelayEncryption,
            callbacks = object : RelaySessionCallbacks {
                override fun onRelayConnected() {
                    if (gen != generation.get()) return
                    markRxActivity()
                    transitionToConnected(ChannelType.WAN_RELAY, display, isFallback = isFallback)
                    startHeartbeat(gen, cfg.heartbeatSeconds)
                    if (FailoverPolicy.canRepromoteToLan(cfg, isFallback)) {
                        startLanRepromotionMonitor(gen)
                    }
                }

                override fun onFrameReceived() {
                    if (gen == generation.get()) {
                        markRxActivity()
                    }
                }

                override fun onRelayAuthFailed() {
                    if (gen == generation.get()) {
                        transitionToAuthFailed("Internet Relay authentication failed. Check password.")
                    }
                    done.complete(SessionOutcome.AUTH_FAILED)
                }

                override fun onRelayMuteState(muted: Boolean) {
                    if (gen != generation.get()) return
                    if (!_uiState.value.connected) {
                        transitionToConnected(ChannelType.WAN_RELAY, display, isFallback = isFallback)
                    }
                    applyNewMuteState(muted)
                }

                override fun onRelayTelemetryState(telemetry: RelayTelemetryState) {
                    if (gen != generation.get()) return
                    applyBridgeTelemetry(
                        gen,
                        BridgeTelemetryState(
                            recState = telemetry.recState,
                            recSeconds = telemetry.recSeconds,
                            streamDropWarn = telemetry.streamDropWarn,
                            voiceWhileMuted = telemetry.voiceWhileMuted,
                            osMicMutedDrift = _uiState.value.osMicMutedDrift,
                            lowDiskWarnLevel = _uiState.value.lowDiskWarnLevel,
                            lowDiskMb = _uiState.value.lowDiskMb,
                            deadMicWarn = _uiState.value.deadMicWarn,
                            activeScene = telemetry.activeScene.ifBlank { _uiState.value.activeScene },
                            scenes = telemetry.scenes.ifEmpty { _uiState.value.scenes },
                            isStandby = telemetry.isStandby,
                            standbyScene = _uiState.value.standbyScene,
                            timerState = telemetry.timerState,
                            timerRemainingSec = telemetry.timerRemainingSec,
                            timerPresetSec = telemetry.timerPresetSec
                        )
                    )
                }

                override fun onStageNudgeReceived(message: String, sender: String, accentHex: String) {
                    if (gen != generation.get()) return
                    _events.tryEmit(RemoteEvent.StageNudge(message, sender, accentHex))
                }

                override fun onCloseRemoteSignal() {
                    if (gen != generation.get()) return
                    _events.tryEmit(RemoteEvent.CloseRemoteRequested)
                }

                override fun onRelayDisconnected(reason: String) {
                    cancelSessionJobs(includePresenterTimer = true, includeRecTicker = false, includeRepromote = false)
                    if (gen == generation.get()) {
                        transitionToDisconnected(clearSessionTelemetry = true, preserveAuthFailed = true)
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
            cancelSessionJobs(includeRecTicker = false)
            client.close()
            if (relayClient === client) relayClient = null
        }
    }

    private fun startLanRepromotionMonitor(gen: Int) {
        lanRepromoteJob?.cancel()
        lanRepromoteJob = scope.launch {
            while (gen == generation.get() && (_uiState.value.usingRelayFallback || _uiState.value.usingDirectObsFallback)) {
                delay(repromoteIntervalMs.coerceAtLeast(1500L))
                if (gen != generation.get() || (!_uiState.value.usingRelayFallback && !_uiState.value.usingDirectObsFallback)) break
                if (checkAndPromoteLanIfHealthy(gen)) break
            }
        }
    }

    internal suspend fun checkAndPromoteLanIfHealthy(gen: Int): Boolean {
        if (gen != generation.get()) return false
        var cfg = configStore.current
        if (!FailoverPolicy.canRepromoteFromFallback(cfg, _uiState.value)) {
            return false
        }
        cfg = refreshConfigForHostUuidShift(cfg, logShift = false)
        val candidates = EndpointParser.parseCandidateEndpoints(cfg.hostAddress, cfg.hostPort)
        for (cand in candidates) {
            if (gen != generation.get()) return false
            val host = resolveCandidateHost(cand.host, 900L)
            val healthy = UdpHostDiscoveryClient.probeHostBridgeHealth(
                httpClient = httpClient,
                host = host,
                bridgePort = cfg.bridgePort,
                expectedHostUuid = cfg.pairedHostUuid
            )
            if (healthy && gen == generation.get()) {
                DiagnosticLogger.recordBreadcrumb("Bridge", "RepromoteHealthy", "host=$host:${cfg.bridgePort}")
                logInfo("LAN Host Bridge recovered ($host:${cfg.bridgePort}); promoting back to HOST_BRIDGE")
                reconnectNow()
                return true
            }
        }
        return false
    }

    internal var heartbeatIntervalOverrideMs: Long = 0L

    private fun startHeartbeat(gen: Int, heartbeatSeconds: Int) {
        heartbeatJob?.cancel()
        val intervalMs = if (heartbeatIntervalOverrideMs > 0L) {
            heartbeatIntervalOverrideMs
        } else {
            (heartbeatSeconds.coerceIn(10, 3600) * 1000L)
        }
        heartbeatJob = scope.launch {
            while (gen == generation.get()) {
                delay(intervalMs)
                if (gen != generation.get()) break
                sendPingWithPongWatchdog(gen)
            }
        }
    }

    private fun applyBridgeTelemetry(gen: Int, telemetry: BridgeTelemetryState) {
        val prev = _uiState.value
        val activeVoiceWarn = prev.isMuted && telemetry.voiceWhileMuted
        _uiState.value = prev.copy(
            recState = telemetry.recState,
            recSeconds = telemetry.recSeconds,
            streamDropWarn = telemetry.streamDropWarn,
            voiceWhileMuted = activeVoiceWarn,
            osMicMutedDrift = telemetry.osMicMutedDrift,
            lowDiskWarnLevel = telemetry.lowDiskWarnLevel,
            lowDiskMb = telemetry.lowDiskMb,
            deadMicWarn = telemetry.deadMicWarn,
            activeScene = telemetry.activeScene,
            scenes = if (telemetry.scenes.isNotEmpty()) telemetry.scenes else prev.scenes,
            quickNudges = if (telemetry.quickNudges.isNotEmpty()) telemetry.quickNudges else prev.quickNudges,
            isStandby = telemetry.isStandby,
            standbyScene = telemetry.standbyScene,
            timerState = telemetry.timerState,
            timerRemainingSec = telemetry.timerRemainingSec,
            timerPresetSec = telemetry.timerPresetSec,
            slideIndex = telemetry.slideIndex,
            slideTotal = telemetry.slideTotal,
            slideTitle = telemetry.slideTitle,
            slideNotes = telemetry.slideNotes
        )
        if (activeVoiceWarn && !prev.voiceWhileMuted && configStore.current.enableVoiceWhileMutedAlert) {
            _events.tryEmit(RemoteEvent.VoiceWhileMutedAlert)
        }
        updateLocalRecTicker(gen, telemetry.recState)
        updateLocalPresenterTimerTicker(gen, telemetry.timerState)
    }

    private fun updateLocalRecTicker(gen: Int, recState: Int) {
        if (recState == 1) {
            if (recTickerJob?.isActive != true) {
                recTickerJob = scope.launch {
                    var obsResyncTicks = 0
                    while (gen == generation.get() && _uiState.value.connected && _uiState.value.recState == 1) {
                        delay(1000L)
                        val cur = _uiState.value
                        if (gen == generation.get() && cur.connected && cur.recState == 1) {
                            _uiState.value = cur.copy(recSeconds = cur.recSeconds + 1)
                            obsResyncTicks++
                            if (obsResyncTicks >= 15) {
                                obsResyncTicks = 0
                                obsClient?.sendGetRecordStatus()
                            }
                        }
                    }
                }
            }
        } else {
            recTickerJob?.cancel()
        }
    }

    private fun updateLocalPresenterTimerTicker(gen: Int, timerState: String) {
        if (timerState == "running" || timerState == "overtime") {
            if (presenterTimerJob?.isActive != true) {
                presenterTimerJob = scope.launch {
                    while (gen == generation.get() &&
                        (_uiState.value.timerState == "running" || _uiState.value.timerState == "overtime")
                    ) {
                        delay(1000L)
                        if (gen == generation.get()) {
                            stepLocalPresenterTimerTick()
                        }
                    }
                }
            }
        } else {
            presenterTimerJob?.cancel()
        }
    }

    internal fun stepLocalPresenterTimerTick(): Boolean {
        val cur = _uiState.value
        if (cur.timerState != "running" && cur.timerState != "overtime") return false
        val prevRem = cur.timerRemainingSec
        val nextSec = prevRem - 1
        val enteredOvertime = (nextSec <= 0 && cur.timerState == "running")
        val nextState = if (nextSec <= 0) "overtime" else cur.timerState
        val updated = cur.copy(timerRemainingSec = nextSec, timerState = nextState)
        _uiState.value = updated
        if (enteredOvertime) {
            _events.tryEmit(
                RemoteEvent.StageNudge(
                    message = "Time Up — Overtime (${updated.formattedCountdown()})",
                    sender = "Timer",
                    accentHex = "EF4444"
                )
            )
        } else if (prevRem == 121 && nextSec == 120) {
            _events.tryEmit(
                RemoteEvent.StageNudge(
                    message = "2:00 Remaining",
                    sender = "Timer",
                    accentHex = "F59E0B"
                )
            )
        }
        return true
    }

    internal fun executeLocalTimerCommand(action: String, durationSec: Int = 0): Boolean {
        val cur = _uiState.value
        val activeGen = generation.get()
        return when (action.lowercase()) {
            "timer_start" -> {
                val preset: Int
                val rem: Int
                if (durationSec > 0) {
                    preset = durationSec
                    rem = durationSec
                } else if (cur.timerState == "stopped") {
                    preset = if (cur.timerPresetSec > 0) cur.timerPresetSec else 600
                    rem = preset
                } else {
                    preset = if (cur.timerPresetSec > 0) cur.timerPresetSec else 600
                    rem = cur.timerRemainingSec
                }
                val nextState = if (rem <= 0) "overtime" else "running"
                _uiState.value = cur.copy(
                    timerState = nextState,
                    timerRemainingSec = rem,
                    timerPresetSec = preset
                )
                DiagnosticLogger.recordBreadcrumb("Timer", "LocalTimerStart", "rem=${rem}s | preset=${preset}s")
                updateLocalPresenterTimerTicker(activeGen, nextState)
                true
            }
            "timer_pause" -> {
                if (cur.timerState == "stopped") {
                    return executeLocalTimerCommand("timer_start", 0)
                }
                if (cur.timerState == "running" || cur.timerState == "overtime") {
                    presenterTimerJob?.cancel()
                    _uiState.value = cur.copy(timerState = "paused")
                    DiagnosticLogger.recordBreadcrumb("Timer", "LocalTimerPause", "rem=${cur.timerRemainingSec}s")
                } else if (cur.timerState == "paused") {
                    val nextState = if (cur.timerRemainingSec <= 0) "overtime" else "running"
                    _uiState.value = cur.copy(timerState = nextState)
                    DiagnosticLogger.recordBreadcrumb("Timer", "LocalTimerResume", "rem=${cur.timerRemainingSec}s")
                    updateLocalPresenterTimerTicker(activeGen, nextState)
                }
                true
            }
            "timer_reset" -> {
                presenterTimerJob?.cancel()
                val preset = if (durationSec > 0) durationSec else if (cur.timerPresetSec > 0) cur.timerPresetSec else 600
                _uiState.value = cur.copy(
                    timerState = "stopped",
                    timerRemainingSec = preset,
                    timerPresetSec = preset
                )
                DiagnosticLogger.recordBreadcrumb("Timer", "LocalTimerReset", "preset=${preset}s")
                true
            }
            else -> false
        }
    }

    internal fun executeLocalObsStandbyToggle(enterStandby: Boolean? = null): Boolean {
        val cur = _uiState.value
        val obs = obsClient
        val wantStandby = enterStandby ?: !cur.isStandby
        if (wantStandby == cur.isStandby) return true
        val brbScene = cur.standbyScene.trim().ifBlank { "BRB" }

        if (wantStandby) {
            localStandbySnapshot = LocalStandbySnapshot(
                previousScene = cur.activeScene,
                wasMuted = cur.isMuted,
                recWasActive = (cur.recState == 1)
            )
            if (!cur.isMuted) {
                obs?.sendSetInputMute(true)
                applyNewMuteState(true)
            }
            obs?.sendSetCurrentProgramScene(brbScene)
            val prevProg = if (cur.activeScene.isNotBlank() && cur.activeScene != brbScene) cur.activeScene else cur.previousProgramScene
            _uiState.value = _uiState.value.copy(
                isStandby = true,
                previousProgramScene = prevProg,
                activeScene = brbScene
            )
            DiagnosticLogger.recordBreadcrumb(
                "Director",
                "LocalObsStandbyEnter",
                "scene=$brbScene | prev=${cur.activeScene} | wasMuted=${cur.isMuted}"
            )
        } else {
            val snap = localStandbySnapshot
            localStandbySnapshot = null
            var restoredScene = _uiState.value.activeScene
            if (snap != null) {
                if (snap.previousScene.isNotBlank() && snap.previousScene != "Scene") {
                    obs?.sendSetCurrentProgramScene(snap.previousScene)
                    restoredScene = snap.previousScene
                }
                obs?.sendSetInputMute(snap.wasMuted)
                applyNewMuteState(snap.wasMuted)
            }
            _uiState.value = _uiState.value.copy(
                isStandby = false,
                activeScene = restoredScene
            )
            DiagnosticLogger.recordBreadcrumb(
                "Director",
                "LocalObsStandbyExit",
                "restoredScene=$restoredScene"
            )
        }
        return true
    }

    private fun applyNewMuteState(muted: Boolean) {
        val prev = _uiState.value.isMuted
        configStore.update { it.copy(isMuted = muted) }
        _uiState.value = _uiState.value.copy(
            isMuted = muted,
            voiceWhileMuted = if (muted) _uiState.value.voiceWhileMuted else false
        )
        if (prev != muted) {
            _events.tryEmit(RemoteEvent.MuteChanged(muted))
        }
    }

    fun sendPptNext(source: String = "quick_menu"): Boolean =
        sendBridgeDeckAction { it.sendPptNext(source) }

    fun sendPptPrev(source: String = "quick_menu"): Boolean =
        sendBridgeDeckAction { it.sendPptPrev(source) }

    fun sendStartSlideshow(source: String = "podium"): Boolean =
        sendBridgeDeckAction { it.sendStartSlideshow(source) }

    fun sendToggleRecord(source: String = "quick_menu"): Boolean =
        sendDirectorAction(
            bridgeAction = { it.sendToggleRecord(source) },
            obsAction = { it.sendToggleRecord() },
            relayAction = { it.sendToggleRecord() }
        )

    fun sendPauseRecord(source: String = "quick_menu"): Boolean =
        sendDirectorAction(
            bridgeAction = { it.sendPauseRecord(source) },
            obsAction = { obs ->
                val ok = obs.sendToggleRecordPause()
                val cur = _uiState.value
                if (ok && (cur.recState == 1 || cur.recState == 2)) {
                    val nextSt = if (cur.recState == 1) 2 else 1
                    _uiState.value = cur.copy(recState = nextSt)
                    updateLocalRecTicker(generation.get(), nextSt)
                }
                ok
            },
            relayAction = { it.sendPauseRecord() }
        )

    fun sendSplitRecord(source: String = "quick_menu"): Boolean =
        sendDirectorAction(
            bridgeAction = { it.sendSplitRecord(source) },
            obsAction = { it.sendSplitRecordFile() },
            relayAction = { it.sendSplitRecord() }
        )

    fun sendToggleStandby(source: String = "quick_menu"): Boolean =
        sendDirectorAction(
            bridgeAction = { it.sendToggleStandby(source) },
            obsAction = { executeLocalObsStandbyToggle() },
            relayAction = { it.sendToggleStandby() }
        )

    fun sendSwitchScene(sceneName: String, source: String = "director"): Boolean =
        sendDirectorAction(
            bridgeAction = { it.sendSwitchScene(sceneName, source) },
            obsAction = { obs ->
                val clean = sceneName.trim()
                obs.sendSetCurrentProgramScene(clean)
            },
            relayAction = { it.sendSwitchScene(sceneName) }
        )

    fun sendTransitionScene(source: String = "director"): Boolean =
        sendDirectorAction(
            bridgeAction = { it.sendTransitionScene(source) },
            obsAction = { obs ->
                val cur = _uiState.value
                if (cur.studioModeActive) {
                    obs.sendTriggerStudioModeTransition()
                } else {
                    val target = resolveNonStudioTransitionTarget(cur)
                    if (target.isNotBlank()) {
                        obs.sendSetCurrentProgramScene(target)
                    } else {
                        false
                    }
                }
            },
            relayAction = { it.sendTransitionScene() }
        )

    fun sendTimerCommand(action: String, durationSec: Int = 0, source: String = "director"): Boolean {
        val st = _uiState.value
        val bridge = bridgeClient
        if (st.connected && bridge != null && st.usingBridge) {
            return bridge.sendTimerCommand(action, durationSec, source)
        }
        val relay = relayClient
        if (st.connected && relay != null && !st.usingDirectObsFallback) {
            return relay.sendTimerCommand(action, durationSec)
        }
        if (st.usingDirectObsFallback || obsClient != null) {
            return executeLocalTimerCommand(action, durationSec)
        }
        _events.tryEmit(RemoteEvent.ToastMessage("Director controls require an active Host Bridge, Direct OBS, or Relay connection."))
        return false
    }

    fun sendStageNudge(message: String, accentHex: String = "F59E0B"): Boolean =
        sendDirectorAction(
            bridgeAction = { it.sendStageNudge(message, accentHex = accentHex) },
            obsAction = null,
            relayAction = { it.sendStageNudge(message) }
        )

    private fun sendBridgeDeckAction(action: (HostBridgeClient) -> Boolean): Boolean {
        val st = _uiState.value
        val bridge = bridgeClient
        if (!st.connected || bridge == null || !st.usingBridge) {
            _events.tryEmit(RemoteEvent.ToastMessage("Deck controls require Primary Host Bridge connection."))
            return false
        }
        return action(bridge)
    }

    private fun sendDirectorAction(
        bridgeAction: (HostBridgeClient) -> Boolean,
        obsAction: ((ObsWebSocketClient) -> Boolean)? = null,
        relayAction: (RelayClient) -> Boolean
    ): Boolean {
        val st = _uiState.value
        val bridge = bridgeClient
        if (st.connected && bridge != null && st.usingBridge) {
            return bridgeAction(bridge)
        }
        val obs = obsClient
        if (obsAction != null && (st.usingDirectObsFallback || (st.connected && obs != null))) {
            if (obs != null) {
                return obsAction(obs)
            } else if (st.usingDirectObsFallback) {
                return executeLocalObsStandbyToggle()
            }
        }
        val relay = relayClient
        if (st.connected && relay != null) {
            return relayAction(relay)
        }
        _events.tryEmit(RemoteEvent.ToastMessage("Director controls require an active Primary Host Bridge, Direct OBS, or Relay connection."))
        return false
    }

    fun toggleMuteFromHud(): Boolean = toggleMuteInternal("hud")

    fun toggleMuteFromClicker(): Boolean = toggleMuteInternal("clicker")

    private fun toggleMuteInternal(source: String): Boolean = dispatchMuteCommand(
        bridgeSend = { it.sendToggleMute(source) },
        obsSend = { it.sendToggleInputMute() },
        relaySend = { it.sendToggleMute() }
    )

    fun setMuteFromHud(targetMuted: Boolean): Boolean = setMuteInternal(targetMuted)

    fun setMuteFromClicker(targetMuted: Boolean): Boolean = setMuteInternal(targetMuted)

    private fun setMuteInternal(targetMuted: Boolean): Boolean = dispatchMuteCommand(
        bridgeSend = { it.sendSetMute(targetMuted) },
        obsSend = { it.sendSetInputMute(targetMuted) },
        relaySend = { it.sendSetMute(targetMuted) }
    )

    private fun dispatchMuteCommand(
        bridgeSend: (HostBridgeClient) -> Boolean,
        obsSend: (ObsWebSocketClient) -> Boolean,
        relaySend: (RelayClient) -> Boolean
    ): Boolean {
        if (!_uiState.value.connected) {
            _events.tryEmit(RemoteEvent.ToastMessage("PresenterSync Remote: Not connected to OBS host"))
            return false
        }
        val bridge = bridgeClient
        if (bridge != null && bridgeSend(bridge)) return true
        obsClient?.let { return obsSend(it) }
        relayClient?.let { return relaySend(it) }
        return false
    }

    suspend fun pairByCode(
        codeInput: String,
        fallbackHostInput: String,
        bridgePortInput: Int = AppConstants.DEFAULT_BRIDGE_PORT,
        forceWanRelay: Boolean? = null,
        onProgress: (String) -> Unit
    ): String {
        val cleanCode = codeInput.trim()
        if (cleanCode.isEmpty()) return "Error: Enter a Session Code (e.g. K7M-9P2) or Internet Pairing Code (PS-...)."

        val useWan = forceWanRelay ?: SessionPairingClient.isWanRelayCode(cleanCode)
        if (useWan) {
            configStore.update { prev ->
                prev.copy(
                    networkMode = NetworkMode.INTERNET,
                    internetPairingCode = cleanCode,
                    firstRun = false
                )
            }
            reconnectNow()
            return "✓ Configured Internet Relay code $cleanCode. Connecting..."
        }

        val devId = SessionPairingClient.getOrCreateDeviceId(context)
        return when (val res = SessionPairingClient.discoverAndPairLan(
            context = context,
            httpClient = httpClient,
            mdnsResolver = mdnsResolver,
            sessionCode = cleanCode,
            fallbackHostCandidates = fallbackHostInput,
            bridgePort = bridgePortInput,
            deviceId = devId,
            onProgress = onProgress
        )) {
            is PairingResult.Success -> {
                val b = res.bundle
                val candidates = SessionPairingClient.buildCandidateAddressList(b.pairedIp, b)
                    .ifBlank { fallbackHostInput.trim().ifBlank { b.pairedIp } }
                configStore.update { prev ->
                    prev.copy(
                        networkMode = NetworkMode.LAN,
                        sessionPairingCode = cleanCode.uppercase(),
                        sessionToken = b.sessionToken,
                        pairedHostUuid = b.hostUuid.ifBlank { prev.pairedHostUuid },
                        hostAddress = candidates,
                        hostPort = b.obsPort,
                        bridgePort = b.bridgePort,
                        obsPassword = b.obsPassword,
                        targetMicName = b.targetMicName,
                        internetPairingCode = b.internetPairingCode.ifBlank { prev.internetPairingCode },
                        isMuted = b.isMuted,
                        firstRun = false
                    )
                }
                reconnectNow()
                "✓ Paired with ${b.hostName} (${b.pairedIp})! Connected via Bridge :${b.bridgePort}."
            }
            is PairingResult.Error -> "✕ ${res.message}"
        }
    }

    fun applyDeepLinkAsync(payload: ParsedConnectionPayload) {
        scope.launch {
            val msg = applyDeepLinkPayload(payload)
            logInfo("Deep link applied: $msg")
            _events.tryEmit(RemoteEvent.ToastMessage(msg))
        }
    }

    suspend fun applyDeepLinkPayload(
        payload: ParsedConnectionPayload,
        onProgress: (String) -> Unit = {}
    ): String {
        configStore.update { prev ->
            prev.copy(
                networkMode = payload.networkMode,
                hostAddress = payload.hostsCsv.ifBlank { prev.hostAddress },
                hostPort = payload.obsPort,
                bridgePort = payload.bridgePort,
                obsPassword = payload.obsPassword.ifEmpty { prev.obsPassword },
                targetMicName = payload.targetMicName.ifBlank { prev.targetMicName },
                sessionPairingCode = payload.sessionCode.ifBlank { prev.sessionPairingCode },
                internetPairingCode = payload.internetPairingCode.ifBlank { prev.internetPairingCode },
                pairedHostUuid = payload.hostUuid.ifBlank { prev.pairedHostUuid },
                hudColorPreset = if (payload.hudColorPreset.isNotBlank()) {
                    HudColorPalettes.normalize(payload.hudColorPreset)
                } else {
                    prev.hudColorPreset
                },
                customLiveHex = if (payload.customLiveHex.isNotBlank()) {
                    HudColorPalettes.normalizeColorHex(payload.customLiveHex, prev.customLiveHex)
                } else {
                    prev.customLiveHex
                },
                customMutedHex = if (payload.customMutedHex.isNotBlank()) {
                    HudColorPalettes.normalizeColorHex(payload.customMutedHex, prev.customMutedHex)
                } else {
                    prev.customMutedHex
                },
                firstRun = false
            )
        }
        if (payload.networkMode == NetworkMode.LAN && payload.sessionCode.isNotBlank()) {
            val res = pairByCode(
                codeInput = payload.sessionCode,
                fallbackHostInput = payload.hostsCsv,
                bridgePortInput = payload.bridgePort,
                forceWanRelay = false,
                onProgress = onProgress
            )
            if (res.startsWith("✓")) {
                return res
            }
            reconnectNow()
            val detail = res.removePrefix("✕ ").trim()
            return "✓ Loaded QR host profile (${payload.hostsCsv}); connecting directly ($detail)."
        }
        reconnectNow()
        return if (payload.networkMode == NetworkMode.INTERNET) {
            "✓ Loaded Internet Relay profile (${payload.internetPairingCode}). Connecting..."
        } else {
            "✓ Loaded host profile (${payload.hostsCsv}:${payload.obsPort}). Connecting..."
        }
    }

    suspend fun testConnection(
        networkMode: NetworkMode,
        hostAddress: String,
        portStr: String,
        password: String,
        pairingCode: String,
        onProgress: (String) -> Unit,
        relayBaseUrl: String = configStore.current.relayBaseUrl
    ): String = withContext(Dispatchers.IO) {
        if (networkMode == NetworkMode.INTERNET) {
            val cleanPair = pairingCode.trim()
            if (cleanPair.isEmpty()) return@withContext "Error: Please enter your Internet Pairing Code."
            val normBase = RelayCrypto.normalizeRelayBaseUrl(relayBaseUrl)
            onProgress("Testing Internet Relay ($cleanPair)...")
            val topic = RelayCrypto.getInternetRelayTopic(cleanPair)
            val expectedTok = RelayCrypto.getInternetRelayAuthToken(cleanPair, password)
            val wsUrl = RelayCrypto.buildRelayWsUrl(normBase, topic)
            val pubUrl = RelayCrypto.buildRelayPublishUrl(normBase, topic)
            val result = kotlinx.coroutines.CompletableDeferred<String>()
            var testWs: WebSocket? = null
            try {
                testWs = httpClient.newWebSocket(Request.Builder().url(wsUrl).build(), object : WebSocketListener() {
                    override fun onOpen(webSocket: WebSocket, response: Response) {
                        val pkt = RelayCrypto.formatEncryptedRelayPacket(
                            src = "remote",
                            cmd = "sync_req",
                            data = "0",
                            pairingCode = cleanPair,
                            password = password,
                            seq = 1L,
                            ts = System.currentTimeMillis() / 1000L,
                            sid = RelayCrypto.generateSessionId()
                        )
                        val req = Request.Builder()
                            .url(pubUrl)
                            .header("Cache-Control", "no-cache")
                            .post(pkt.toRequestBodyCompat())
                            .build()
                        try {
                            httpClient.newCall(req).execute().close()
                        } catch (_: Exception) {
                        }
                    }

                    override fun onMessage(webSocket: WebSocket, text: String) {
                        val pkt = RelayCrypto.parseRelayEnvelope(
                            rawMsg = text,
                            pairingCode = cleanPair,
                            password = password,
                            replayGuard = null,
                            allowLegacy = true
                        )
                        if (pkt != null) {
                            if (!pkt.ok) {
                                if (pkt.authError) {
                                    result.complete("✕ Auth/Encryption mismatch on Internet Relay (Check OBS Password)")
                                }
                                return
                            }
                            if (pkt.src == "host") {
                                if (pkt.cmd == "auth_error" || pkt.auth != expectedTok) {
                                    result.complete("✕ Auth failed on Internet Relay (Check OBS Password)")
                                } else if (pkt.cmd == "state") {
                                    result.complete("✓ Connected to Primary Host via Internet Relay ($cleanPair)!")
                                }
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
            val resolved = resolveCandidateHost(cand.host, mdnsTimeoutMs = null)
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

    companion object {
        const val BRIDGE_CONNECT_TIMEOUT_MS = 1800L
        const val BRIDGE_REPROMOTE_INTERVAL_MS = 8000L
        const val HEALTH_PROBE_TIMEOUT_MS = 500L
        const val PONG_TIMEOUT_MS = 2500L
        const val WAKE_STALENESS_MS = 25_000L

        internal fun resolveNonStudioTransitionTarget(state: ConnectionUiState): String {
            val active = state.activeScene.trim()
            val preview = state.previewScene.trim()
            if (preview.isNotBlank() && preview != active) return preview
            val prevProg = state.previousProgramScene.trim()
            if (prevProg.isNotBlank() && prevProg != active) return prevProg
            val scenes = state.scenes
            if (scenes.size >= 2) {
                val curIdx = scenes.indexOfFirst { it == active }
                val nextIdx = if (curIdx >= 0) (curIdx + 1) % scenes.size else 0
                var candidate = scenes[nextIdx].trim()
                if (candidate == active) {
                    candidate = scenes[(nextIdx + 1) % scenes.size].trim()
                }
                if (candidate.isNotBlank() && candidate != active) return candidate
            }
            return ""
        }
    }
}
