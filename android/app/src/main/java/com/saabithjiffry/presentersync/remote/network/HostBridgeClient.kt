package com.saabithjiffry.presentersync.remote.network

import com.saabithjiffry.presentersync.remote.config.AppConstants
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong

data class BridgeTelemetryState(
    val recState: Int = 0,
    val recSeconds: Int = 0,
    val streamState: Int = 0,
    val vcamActive: Boolean = false,
    val studioModeActive: Boolean = false,
    val previewSceneName: String = "",
    val unreadChatCount: Int = 0,
    val streamDropWarn: Boolean = false,
    val voiceWhileMuted: Boolean = false,
    val osMicMutedDrift: Boolean = false,
    val lowDiskWarnLevel: Int = 0,
    val lowDiskMb: Int = -1,
    val deadMicWarn: Boolean = false,
    val recStallWarn: Boolean = false,
    val encoderOverloadWarn: Boolean = false,
    val obsCrashedRecWarn: Boolean = false,
    val activeScene: String = "Scene",
    val scenes: List<String> = emptyList(),
    val quickNudges: List<String> = emptyList(),
    val isStandby: Boolean = false,
    val isPanic: Boolean = false,
    val panicUnmuteLocked: Boolean = false,
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
    fun onBridgeRoleAssigned(role: String) {}
    fun onBridgeFlashPill(durationMs: Long) {}
    fun onBridgeHostUuidReceived(hostUuid: String) {}
    fun onBridgeSessionTokenRefreshed(sessionToken: String) {}
    fun onBridgeFrameReceived() {}
    fun onBridgeAuthFailed(reason: String)
    fun onMuteStateChanged(isMuted: Boolean, routingMode: Int, targetMicName: String)
    fun onTelemetryChanged(telemetry: BridgeTelemetryState) {}
    fun onStageNudgeReceived(message: String, sender: String, accentHex: String) {}
    fun onSyncResync(reason: String, hostUuid: String) {}
    fun onObsFallbackUpdated(port: Int, targetMic: String, password: String) {}
    fun onCommandNack(action: String, code: String, reason: String, cmdId: String) {}
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
    private val callbacks: HostBridgeCallbacks,
    private val clientFallbackState: JSONObject? = null
) {
    @Volatile
    private var webSocket: WebSocket? = null

    @Volatile
    private var closedByCaller = false

    @Volatile
    private var authenticated = false

    private val connSeq = AtomicInteger(0)
    private val cmdSeq = AtomicLong(0L)
    private val lastStateSeq = AtomicLong(0L)

    @Volatile
    private var lastHostBootId: String = ""

    private fun nextCmdId(): String = "$deviceId-${cmdSeq.incrementAndGet()}"

    fun connect() {
        closedByCaller = false
        authenticated = false
        lastHostBootId = ""
        lastStateSeq.set(0L)
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
                sendAuthFrame(webSocket)
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
                        val bootId = obj.optString("hostBootId", "").trim()
                        if (bootId.isNotEmpty() && bootId != lastHostBootId) {
                            lastHostBootId = bootId
                            lastStateSeq.set(0L)
                        }
                        val seq = obj.optLong("stateSeq", 0L)
                        if (seq > 0L) {
                            lastStateSeq.set(seq)
                        }
                        val hostName = obj.optString("hostName", "Primary Host")
                        val assignedRole = obj.optString("role", "Presenter").trim().ifEmpty { "Presenter" }
                        callbacks.onBridgeRoleAssigned(assignedRole)
                        val hostUuid = obj.optString("hostUuid", "").trim()
                        if (hostUuid.isNotEmpty()) {
                            callbacks.onBridgeHostUuidReceived(hostUuid)
                        }
                        val refreshedToken = obj.optString("sessionToken", "").trim()
                        if (refreshedToken.isNotEmpty()) {
                            callbacks.onBridgeSessionTokenRefreshed(refreshedToken)
                        }
                        val obsFb = obj.optJSONObject("obsFallback")
                        if (obsFb != null) {
                            callbacks.onObsFallbackUpdated(
                                port = obsFb.optInt("port", AppConstants.DEFAULT_OBS_PORT),
                                targetMic = obsFb.optString("targetMic", ""),
                                password = obsFb.optString("password", "")
                            )
                        }
                        callbacks.onBridgeConnected(hostName)
                    }
                    "obs_fallback_update" -> {
                        val obsFb = obj.optJSONObject("obsFallback")
                        if (obsFb != null) {
                            callbacks.onObsFallbackUpdated(
                                port = obsFb.optInt("port", AppConstants.DEFAULT_OBS_PORT),
                                targetMic = obsFb.optString("targetMic", ""),
                                password = obsFb.optString("password", "")
                            )
                        }
                    }
                    "auth_error" -> {
                        val err = obj.optString("error", "Bridge authentication failed")
                        callbacks.onBridgeAuthFailed(err)
                    }
                    "mute_state", "sync_resync" -> {
                        val msgKind = obj.optString("type", "").lowercase()
                        val bootId = obj.optString("hostBootId", "").trim()
                        if (bootId.isNotEmpty() && bootId != lastHostBootId) {
                            lastHostBootId = bootId
                            lastStateSeq.set(0L)
                        }
                        val seq = obj.optLong("stateSeq", 0L)
                        val prevSeq = lastStateSeq.get()
                        if (msgKind == "mute_state" && seq > 0L && prevSeq > 0L && seq < prevSeq) {
                            return
                        }
                        if (seq > 0L) {
                            lastStateSeq.set(seq)
                        }
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
                            streamState = obj.optInt("streamState", 0),
                            vcamActive = obj.optBoolean("vcamActive", false),
                            studioModeActive = obj.optBoolean("studioModeActive", false),
                            previewSceneName = obj.optString("previewSceneName", ""),
                            unreadChatCount = obj.optInt("unreadChatCount", 0),
                            streamDropWarn = obj.optBoolean("streamDropWarn", false),
                            voiceWhileMuted = obj.optBoolean("voiceWhileMuted", false),
                            osMicMutedDrift = obj.optBoolean("osMicMutedDrift", false),
                            lowDiskWarnLevel = obj.optInt("lowDiskWarnLevel", 0),
                            lowDiskMb = obj.optInt("lowDiskMb", -1),
                            deadMicWarn = obj.optBoolean("deadMicWarn", false),
            recStallWarn = obj.optBoolean("recStallWarn", false),
            encoderOverloadWarn = obj.optBoolean("encoderOverloadWarn", false),
            obsCrashedRecWarn = obj.optBoolean("obsCrashedRecWarn", false),
                            activeScene = obj.optString("activeScene", "Scene").ifBlank { "Scene" },
                            scenes = scenesList,
                            quickNudges = quickNudgesList,
                            isStandby = obj.optBoolean("isStandby", false),
            isPanic = obj.optBoolean("isPanic", false),
            panicUnmuteLocked = obj.optBoolean("panicUnmuteLocked", false),
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
                        val nId = obj.optString("nudgeId", "").trim()
                        if (nId.isNotEmpty() && !recordSeenNudgeId(nId)) {
                            return
                        }
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
                    "nack" -> {
                        callbacks.onCommandNack(
                            action = obj.optString("action", ""),
                            code = obj.optString("code", ""),
                            reason = obj.optString("reason", obj.optString("error", "")),
                            cmdId = obj.optString("cmdId", "")
                        )
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
            put("protocolVersion", 2)
            put("appVersion", AppConstants.APP_VERSION)
            put("capabilities", JSONArray(listOf("protocol_v2", "cmd_dedup", "set_state", "ack_nack")))
            put("token", sessionToken)
            put("code", SessionPairingClient.normalizeCode(sessionCode))
            put("deviceId", deviceId)
            put("deviceName", deviceName)
            put("platform", "Android")
            if (clientFallbackState != null) {
                put("clientFallbackState", clientFallbackState)
            }
        }.toString()
        ws.send(payload)
    }

    fun sendToggleMute(source: String = "clicker"): Boolean = sendDeviceAction("toggle_mute", source)

    fun sendPptNext(source: String = "quick_menu"): Boolean = sendDeviceAction("ppt_next", source)

    fun sendPptPrev(source: String = "quick_menu"): Boolean = sendDeviceAction("ppt_prev", source)

    fun sendStartSlideshow(source: String = "podium"): Boolean = sendDeviceAction("slide_start", source)

    fun sendToggleRecord(source: String = "quick_menu"): Boolean = sendDeviceAction("toggle_record", source)

    fun sendSetRecord(recording: Boolean, confirmed: Boolean = true, source: String = "quick_menu"): Boolean {
        if (!authenticated) return false
        val ws = webSocket ?: return false
        val payload = JSONObject().apply {
            put("type", "set_record")
            put("cmdId", nextCmdId())
            put("recording", recording)
            put("confirmed", confirmed)
            put("deviceId", deviceId)
            put("source", source)
        }.toString()
        return ws.send(payload)
    }

    fun sendPauseRecord(source: String = "quick_menu"): Boolean = sendDeviceAction("pause_record", source)

    fun sendSplitRecord(source: String = "quick_menu"): Boolean = sendDeviceAction("split_record", source)

    fun sendToggleStandby(source: String = "quick_menu"): Boolean = sendDeviceAction("toggle_standby", source)

    fun sendSetPreviewScene(sceneName: String, source: String = "director"): Boolean {
        if (!authenticated) return false
        val ws = webSocket ?: return false
        val clean = sceneName.trim()
        if (clean.isEmpty()) return false
        val payload = JSONObject().apply {
            put("type", "set_preview_scene")
            put("cmdId", nextCmdId())
            put("sceneName", clean)
            put("deviceId", deviceId)
            put("source", source)
        }.toString()
        return ws.send(payload)
    }

    fun sendAudioHandoff(mode: String, source: String = "director"): Boolean {
        if (!authenticated) return false
        val ws = webSocket ?: return false
        val payload = JSONObject().apply {
            put("type", "audio_handoff")
            put("cmdId", nextCmdId())
            put("mode", mode)
            put("deviceId", deviceId)
            put("source", source)
        }.toString()
        return ws.send(payload)
    }

    fun sendSaveReplayBuffer(source: String = "director"): Boolean = sendDeviceAction("save_replay_buffer", source)

    fun sendEmergencyPanic(active: Boolean? = null, source: String = "quick_menu"): Boolean {
        if (!authenticated) return false
        val ws = webSocket ?: return false
        val payload = JSONObject().apply {
            put("type", "emergency_panic")
            put("cmdId", nextCmdId())
            if (active != null) put("active", active)
            put("deviceId", deviceId)
            put("source", source)
        }.toString()
        return ws.send(payload)
    }

    fun sendSetStandby(isStandby: Boolean, source: String = "quick_menu"): Boolean {
        if (!authenticated) return false
        val ws = webSocket ?: return false
        val payload = JSONObject().apply {
            put("type", "set_standby")
            put("cmdId", nextCmdId())
            put("isStandby", isStandby)
            put("deviceId", deviceId)
            put("source", source)
        }.toString()
        return ws.send(payload)
    }

    fun sendTransitionScene(source: String = "director"): Boolean = sendDeviceAction("transition_scene", source)

    fun sendSwitchScene(sceneName: String, source: String = "director"): Boolean {
        val clean = sceneName.trim()
        if (!authenticated || clean.isEmpty()) return false
        val ws = webSocket ?: return false
        val payload = JSONObject().apply {
            put("type", "switch_scene")
            put("cmdId", nextCmdId())
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
            put("cmdId", nextCmdId())
            if (durationSec > 0) put("durationSec", durationSec)
            put("deviceId", deviceId)
            put("source", source)
        }.toString()
        return ws.send(payload)
    }

    private val seenNudgeIds = LinkedHashSet<String>()

    private fun recordSeenNudgeId(nudgeId: String): Boolean {
        synchronized(seenNudgeIds) {
            if (!seenNudgeIds.add(nudgeId)) return false
            if (seenNudgeIds.size > 64) {
                val it = seenNudgeIds.iterator()
                if (it.hasNext()) {
                    it.next()
                    it.remove()
                }
            }
            return true
        }
    }

    fun sendNudgeAck(nudgeId: String): Boolean {
        val clean = nudgeId.trim()
        if (!authenticated || clean.isEmpty()) return false
        val ws = webSocket ?: return false
        val payload = JSONObject().apply {
            put("type", "nudge_ack")
            put("cmdId", nextCmdId())
            put("nudgeId", clean)
            put("status", "got_it")
            put("deviceId", deviceId)
        }
        return ws.send(payload.toString())
    }

    fun sendPresenterSignal(message: String, urgency: String = "sticky"): Boolean {
        val clean = message.trim()
        if (!authenticated || clean.isEmpty()) return false
        val ws = webSocket ?: return false
        val payload = JSONObject().apply {
            put("type", "stage_nudge")
            put("cmdId", nextCmdId())
            put("direction", "stage_back")
            put("urgency", urgency)
            put("message", clean.take(140))
            put("sender", deviceName)
            put("deviceId", deviceId)
        }
        return ws.send(payload.toString())
    }

    fun sendStageNudge(message: String, sender: String = deviceName, accentHex: String = "F59E0B"): Boolean {
        val clean = message.trim()
        if (!authenticated || clean.isEmpty()) return false
        val ws = webSocket ?: return false
        val payload = JSONObject().apply {
            put("type", "stage_nudge")
            put("cmdId", nextCmdId())
            put("message", clean.take(140))
            put("sender", sender.ifBlank { deviceName })
            put("accentHex", accentHex)
            put("deviceId", deviceId)
        }.toString()
        return ws.send(payload)
    }

    fun sendDisconnect(source: String = "remote"): Boolean = sendDeviceAction("disconnect", source)

    fun sendUnpair(source: String = "remote"): Boolean = sendDeviceAction("unpair", source)

    private fun sendDeviceAction(type: String, source: String): Boolean {
        if (!authenticated) return false
        val ws = webSocket ?: return false
        val payload = JSONObject().apply {
            put("type", type)
            put("cmdId", nextCmdId())
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
            put("cmdId", nextCmdId())
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
