package com.saabithjiffry.presentersync.remote.network

import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONArray
import org.json.JSONObject

data class BridgeTelemetryState(
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
)

interface HostBridgeCallbacks {
    fun onBridgeConnected(hostName: String)
    fun onBridgeHostUuidReceived(hostUuid: String) {}
    fun onBridgeSessionTokenRefreshed(sessionToken: String) {}
    fun onBridgeFrameReceived() {}
    fun onBridgeAuthFailed(reason: String)
    fun onMuteStateChanged(isMuted: Boolean, routingMode: Int, targetMicName: String)
    fun onTelemetryChanged(telemetry: BridgeTelemetryState) {}
    fun onStageNudgeReceived(message: String, sender: String, accentHex: String) {}
    fun onSyncResync(reason: String, hostUuid: String) {}
    fun onCloseRemoteSignal()
    fun onBridgeDisconnected(reason: String)
}

class HostBridgeClient(
    private val httpClient: OkHttpClient,
    private val wsBaseUrl: String,
    private val sessionToken: String,
    private val sessionCode: String,
    private val deviceId: String,
    private val deviceName: String,
    private val callbacks: HostBridgeCallbacks
) {
    @Volatile
    private var webSocket: WebSocket? = null

    @Volatile
    private var closedByCaller = false

    @Volatile
    private var authenticated = false

    private val connSeq = java.util.concurrent.atomic.AtomicInteger(0)

    fun connect() {
        closedByCaller = false
        authenticated = false
        val mySeq = connSeq.incrementAndGet()

        val httpEquivalent = wsBaseUrl
            .replaceFirst("ws://", "http://")
            .replaceFirst("wss://", "https://")
        val parsed = httpEquivalent.toHttpUrlOrNull()
        val finalUrl = if (parsed != null) {
            val builder = parsed.newBuilder()
                .addQueryParameter("deviceId", deviceId)
                .addQueryParameter("deviceName", deviceName)
                .addQueryParameter("platform", "Android")
            if (sessionToken.isNotBlank()) builder.addQueryParameter("token", sessionToken)
            if (sessionCode.isNotBlank()) builder.addQueryParameter("code", SessionPairingClient.normalizeCode(sessionCode))
            val rebuilt = builder.build().toString()
            if (wsBaseUrl.startsWith("wss://")) rebuilt.replaceFirst("https://", "wss://")
            else rebuilt.replaceFirst("http://", "ws://")
        } else {
            wsBaseUrl
        }

        val req = Request.Builder().url(finalUrl).build()
        this.webSocket = httpClient.newWebSocket(req, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                if (closedByCaller || mySeq != connSeq.get()) return
                this@HostBridgeClient.webSocket = webSocket
                if (sessionToken.isBlank() && sessionCode.isBlank()) {
                    sendAuthFrame(webSocket)
                }
            }

            override fun onMessage(webSocket: WebSocket, bytes: okio.ByteString) {
                if (closedByCaller || mySeq != connSeq.get()) return
                callbacks.onBridgeFrameReceived()
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                if (closedByCaller || mySeq != connSeq.get()) return
                callbacks.onBridgeFrameReceived()
                val obj = try {
                    JSONObject(text)
                } catch (_: Exception) {
                    return
                }
                when (obj.optString("type", "").lowercase()) {
                    "auth_ok" -> {
                        authenticated = true
                        val hostName = obj.optString("hostName", "Primary Host")
                        val hostUuid = obj.optString("hostUuid", "").trim()
                        if (hostUuid.isNotEmpty()) {
                            callbacks.onBridgeHostUuidReceived(hostUuid)
                        }
                        val refreshedToken = obj.optString("sessionToken", "").trim()
                        if (refreshedToken.isNotEmpty()) {
                            callbacks.onBridgeSessionTokenRefreshed(refreshedToken)
                        }
                        callbacks.onBridgeConnected(hostName)
                    }
                    "auth_error" -> {
                        val err = obj.optString("error", "Bridge authentication failed")
                        callbacks.onBridgeAuthFailed(err)
                    }
                    "mute_state", "sync_resync" -> {
                        val msgKind = obj.optString("type", "").lowercase()
                        val muted = obj.optBoolean("isMuted", false)
                        val mode = obj.optInt("routingMode", 0)
                        val mic = obj.optString("targetMicName", "")
                        val scenesList = buildList {
                            val arr = obj.optJSONArray("scenes") ?: JSONArray()
                            for (idx in 0 until arr.length()) {
                                val s = arr.optString(idx, "").trim()
                                if (s.isNotEmpty()) add(s)
                            }
                        }
                        val quickNudgesList = buildList {
                            val arr = obj.optJSONArray("quickNudges")
                            if (arr != null) {
                                for (i in 0 until arr.length()) {
                                    val q = arr.optString(i).trim()
                                    if (q.isNotEmpty()) add(q)
                                }
                            }
                        }
                        val telemetry = BridgeTelemetryState(
                            recState = obj.optInt("recState", 0),
                            recSeconds = obj.optInt("recSeconds", 0).coerceAtLeast(0),
                            streamDropWarn = obj.optBoolean("streamDropWarn", false),
                            voiceWhileMuted = obj.optBoolean("voiceWhileMuted", false),
                            osMicMutedDrift = obj.optBoolean("osMicMutedDrift", false),
                            lowDiskWarnLevel = obj.optInt("lowDiskWarnLevel", 0),
                            lowDiskMb = obj.optInt("lowDiskMb", -1),
                            deadMicWarn = obj.optBoolean("deadMicWarn", false),
                            activeScene = obj.optString("activeScene", "Scene").ifBlank { "Scene" },
                            scenes = scenesList,
                            quickNudges = quickNudgesList,
                            isStandby = obj.optBoolean("isStandby", false),
                            standbyScene = obj.optString("standbyScene", "BRB").ifBlank { "BRB" },
                            timerState = obj.optString("timerState", "stopped").ifBlank { "stopped" },
                            timerRemainingSec = obj.optInt("timerRemainingSec", 600),
                            timerPresetSec = obj.optInt("timerPresetSec", 600).coerceAtLeast(60),
                            slideIndex = obj.optInt("slideIndex", 0).coerceAtLeast(0),
                            slideTotal = obj.optInt("slideTotal", 0).coerceAtLeast(0),
                            slideTitle = obj.optString("slideTitle", ""),
                            slideNotes = obj.optString("slideNotes", "")
                        )
                        callbacks.onMuteStateChanged(muted, mode, mic)
                        callbacks.onTelemetryChanged(telemetry)
                        if (msgKind == "sync_resync") {
                            callbacks.onSyncResync(
                                obj.optString("reason", "resync"),
                                obj.optString("hostUuid", "").trim()
                            )
                        }
                    }
                    "stage_nudge" -> {
                        val nMsg = obj.optString("message", "").trim()
                        val nSender = obj.optString("sender", "Stage").ifBlank { "Stage" }
                        val nAccent = obj.optString("accentHex", "F59E0B").ifBlank { "F59E0B" }
                        if (nMsg.isNotEmpty()) {
                            callbacks.onStageNudgeReceived(nMsg, nSender, nAccent)
                        }
                    }
                    "close_remote" -> {
                        callbacks.onCloseRemoteSignal()
                    }
                    "pong" -> Unit
                }
            }

            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                if (closedByCaller || mySeq != connSeq.get()) return
                webSocket.close(1000, "ack")
                callbacks.onBridgeDisconnected(reason.ifBlank { "Closed ($code)" })
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                if (closedByCaller || mySeq != connSeq.get()) return
                callbacks.onBridgeDisconnected(reason.ifBlank { "Closed ($code)" })
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                if (closedByCaller || mySeq != connSeq.get()) return
                callbacks.onBridgeDisconnected(t.message ?: "Bridge connection failed")
            }
        })
    }

    private fun sendAuthFrame(ws: WebSocket) {
        val payload = JSONObject().apply {
            put("type", "auth")
            put("token", sessionToken)
            put("code", SessionPairingClient.normalizeCode(sessionCode))
            put("deviceId", deviceId)
            put("deviceName", deviceName)
            put("platform", "Android")
        }.toString()
        ws.send(payload)
    }

    fun sendToggleMute(source: String = "clicker"): Boolean = sendDeviceAction("toggle_mute", source)

    fun sendPptNext(source: String = "quick_menu"): Boolean = sendDeviceAction("ppt_next", source)

    fun sendPptPrev(source: String = "quick_menu"): Boolean = sendDeviceAction("ppt_prev", source)

    fun sendStartSlideshow(source: String = "podium"): Boolean = sendDeviceAction("slide_start", source)

    fun sendToggleRecord(source: String = "quick_menu"): Boolean = sendDeviceAction("toggle_record", source)

    fun sendPauseRecord(source: String = "quick_menu"): Boolean = sendDeviceAction("pause_record", source)

    fun sendSplitRecord(source: String = "quick_menu"): Boolean = sendDeviceAction("split_record", source)

    fun sendToggleStandby(source: String = "quick_menu"): Boolean = sendDeviceAction("toggle_standby", source)

    fun sendTransitionScene(source: String = "director"): Boolean = sendDeviceAction("transition_scene", source)

    fun sendSwitchScene(sceneName: String, source: String = "director"): Boolean {
        val clean = sceneName.trim()
        if (!authenticated || clean.isEmpty()) return false
        val ws = webSocket ?: return false
        val payload = JSONObject().apply {
            put("type", "switch_scene")
            put("sceneName", clean)
            put("deviceId", deviceId)
            put("source", source)
        }.toString()
        return ws.send(payload)
    }

    fun sendTimerCommand(action: String, durationSec: Int = 0, source: String = "director"): Boolean {
        if (!authenticated) return false
        val ws = webSocket ?: return false
        val payload = JSONObject().apply {
            put("type", action)
            if (durationSec > 0) put("durationSec", durationSec)
            put("deviceId", deviceId)
            put("source", source)
        }.toString()
        return ws.send(payload)
    }

    fun sendStageNudge(message: String, sender: String = deviceName, accentHex: String = "F59E0B"): Boolean {
        val clean = message.trim()
        if (!authenticated || clean.isEmpty()) return false
        val ws = webSocket ?: return false
        val payload = JSONObject().apply {
            put("type", "stage_nudge")
            put("message", clean.take(140))
            put("sender", sender.ifBlank { deviceName })
            put("accentHex", accentHex)
            put("deviceId", deviceId)
        }.toString()
        return ws.send(payload)
    }

    private fun sendDeviceAction(type: String, source: String): Boolean {
        if (!authenticated) return false
        val ws = webSocket ?: return false
        val payload = JSONObject().apply {
            put("type", type)
            put("deviceId", deviceId)
            put("source", source)
        }.toString()
        return ws.send(payload)
    }

    fun sendSetMute(isMuted: Boolean): Boolean {
        if (!authenticated) return false
        val ws = webSocket ?: return false
        val payload = JSONObject().apply {
            put("type", "set_mute")
            put("isMuted", isMuted)
            put("deviceId", deviceId)
        }.toString()
        return ws.send(payload)
    }

    fun sendSyncRequest(): Boolean {
        if (!authenticated) return false
        val ws = webSocket ?: return false
        return ws.send("""{"type":"sync_req"}""")
    }

    fun sendPing(): Boolean {
        if (!authenticated) return false
        val ws = webSocket ?: return false
        return try {
            ws.send("""{"type":"ping"}""")
        } catch (_: Exception) {
            false
        }
    }

    fun closeDead() {
        closedByCaller = true
        authenticated = false
        val ws = webSocket
        webSocket = null
        try {
            ws?.cancel()
        } catch (_: Exception) {
        }
    }

    fun close() {
        closedByCaller = true
        authenticated = false
        val ws = webSocket
        webSocket = null
        try {
            ws?.close(1000, "Client closing")
        } catch (_: Exception) {
        }
    }
}
