package com.saabithjiffry.presentersync.remote.network

import com.saabithjiffry.presentersync.remote.config.AppConstants
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONObject
import java.io.IOException
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

interface RelaySessionCallbacks {
    fun onRelayConnected()
    fun onFrameReceived() {}
    fun onRelayAuthFailed()
    fun onRelayMuteState(muted: Boolean)
    fun onRelayDirectorState(
        isStandby: Boolean,
        recState: Int,
        timerState: String,
        timerRemainingSec: Int,
        timerPresetSec: Int,
        activeScene: String
    ) {}
    fun onRelayTelemetryState(telemetry: RelayTelemetryState) {}
    fun onStageNudgeReceived(message: String, sender: String, accentHex: String) {}
    fun onCloseRemoteSignal()
    fun onRelayDisconnected(reason: String)
}

class RelayClient(
    private val httpClient: OkHttpClient,
    private val pairingCode: String,
    private val password: String,
    private val callbacks: RelaySessionCallbacks,
    private val httpBaseUrl: String = AppConstants.NTFY_BASE_URL,
    private val wsBaseUrl: String? = null,
    private val enableEncryption: Boolean = true
) {
    private val topic = RelayCrypto.getInternetRelayTopic(pairingCode)
    private val authToken = RelayCrypto.getInternetRelayAuthToken(pairingCode, password)
    private val normalizedHttpBase = RelayCrypto.normalizeRelayBaseUrl(httpBaseUrl)
    private val closed = AtomicBoolean(false)
    private val peerLegacy = AtomicBoolean(false)
    private val outSeq = AtomicLong(0L)
    private val sessionId = RelayCrypto.generateSessionId()
    private val replayGuard = RelayReplayGuard()
    private var webSocket: WebSocket? = null

    fun resolveWsUrl(): String {
        if (topic.isEmpty()) return ""
        return if (!wsBaseUrl.isNullOrBlank()) {
            "${wsBaseUrl.trimEnd('/')}/$topic/ws"
        } else {
            RelayCrypto.buildRelayWsUrl(normalizedHttpBase, topic)
        }
    }

    fun resolvePublishUrl(): String {
        if (topic.isEmpty()) return ""
        return RelayCrypto.buildRelayPublishUrl(normalizedHttpBase, topic)
    }

    fun connect() {
        if (topic.isEmpty()) {
            callbacks.onRelayDisconnected("empty_topic")
            return
        }
        replayGuard.reset()
        val wsUrl = resolveWsUrl()
        val req = Request.Builder().url(wsUrl).build()
        webSocket = httpClient.newWebSocket(req, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                if (closed.get()) return
                callbacks.onRelayConnected()
                sendSyncRequest()
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                if (closed.get()) return
                callbacks.onFrameReceived()
                handleRawMessage(text)
            }

            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                if (closed.getAndSet(true)) return
                webSocket.close(code, reason)
                callbacks.onRelayDisconnected("closing:$code")
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                if (closed.getAndSet(true)) return
                callbacks.onRelayDisconnected("closed:$code")
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                if (closed.getAndSet(true)) return
                callbacks.onRelayDisconnected(t.message ?: "failure")
            }
        })
    }

    internal fun handleRawMessage(rawMsg: String) {
        val env = RelayCrypto.parseRelayEnvelope(
            rawMsg = rawMsg,
            pairingCode = pairingCode,
            password = password,
            replayGuard = replayGuard,
            allowLegacy = true
        )
        if (env != null) {
            if (!env.ok) {
                // Reject tampered ciphertext/tag or replayed sequence silently without corrupting state
                return
            }
            if (env.src != "host") return
            if (env.cmd == "auth_error" || env.auth != authToken) {
                close()
                callbacks.onRelayAuthFailed()
                return
            }
            peerLegacy.set(!env.encrypted)
            when (env.cmd) {
                "state" -> {
                    val muted = env.telemetry?.isMuted
                        ?: (env.data == "1" || env.data.equals("true", ignoreCase = true))
                    callbacks.onRelayMuteState(muted)
                    env.telemetry?.let { dispatchRelayTelemetry(it.copy(isMuted = muted)) }
                }
                "dir_state" -> {
                    val tel = env.telemetry ?: RelayCrypto.parseDirStatePayload(env.data)
                    if (tel != null) {
                        if (tel.isMuted != null) {
                            callbacks.onRelayMuteState(tel.isMuted)
                        }
                        dispatchRelayTelemetry(tel)
                    }
                }
                "nudge" -> {
                    val idx = env.data.indexOf(';')
                    val sender = if (idx > 0) env.data.substring(0, idx).ifBlank { "Host" } else "Host"
                    val msg = if (idx >= 0) env.data.substring(idx + 1).trim() else env.data.trim()
                    if (msg.isNotEmpty()) {
                        callbacks.onStageNudgeReceived(msg, sender, "F59E0B")
                    }
                }
                "close_remote" -> {
                    callbacks.onCloseRemoteSignal()
                }
            }
            return
        }

        // ntfy open event JSON
        try {
            val obj = JSONObject(rawMsg)
            if (obj.optString("event") == "open") {
                sendSyncRequest()
            }
        } catch (_: Exception) {
        }
    }

    fun sendSyncRequest() {
        publishPacket("sync_req", "0")
    }

    fun sendToggleMute(): Boolean {
        return publishPacket("toggle_mute", "1")
    }

    fun sendSetMute(isMuted: Boolean): Boolean {
        return publishPacket("set_mute", if (isMuted) "1" else "0")
    }

    fun sendToggleRecord(): Boolean = publishPacket("toggle_record", "1")

    fun sendPauseRecord(): Boolean = publishPacket("pause_record", "1")

    fun sendSplitRecord(): Boolean = publishPacket("split_record", "1")

    fun sendToggleStandby(): Boolean = publishPacket("toggle_standby", "1")

    fun sendTransitionScene(): Boolean = publishPacket("transition_scene", "1")

    fun sendSwitchScene(sceneName: String): Boolean {
        val clean = sceneName.trim().replace("|", "/")
        return if (clean.isNotEmpty()) publishPacket("switch_scene", clean) else false
    }

    fun sendTimerCommand(action: String, durationSec: Int = 0): Boolean =
        publishPacket(action, durationSec.toString())

    fun sendStageNudge(message: String, sender: String = "Android"): Boolean {
        val clean = message.trim().replace("|", "/").replace(";", ",").take(140)
        return if (clean.isNotEmpty()) {
            publishPacket("stage_nudge", "${sender.replace("|", "/").replace(";", ",")};$clean")
        } else {
            false
        }
    }

    private fun publishPacket(cmd: String, data: String): Boolean {
        if (topic.isEmpty() || closed.get()) return false
        val pktStr = if (enableEncryption && !peerLegacy.get()) {
            RelayCrypto.formatEncryptedRelayPacket(
                src = "remote",
                cmd = cmd,
                data = data,
                pairingCode = pairingCode,
                password = password,
                seq = outSeq.incrementAndGet(),
                ts = System.currentTimeMillis() / 1000L,
                sid = sessionId
            )
        } else {
            RelayCrypto.formatRelayPacket("remote", cmd, data, authToken)
        }
        val url = resolvePublishUrl()
        val req = Request.Builder()
            .url(url)
            .header("Cache-Control", "no-cache")
            .post(pktStr.toRequestBody("text/plain; charset=utf-8".toMediaType()))
            .build()
        return try {
            httpClient.newCall(req).enqueue(object : Callback {
                override fun onFailure(call: Call, e: IOException) {}
                override fun onResponse(call: Call, response: Response) {
                    response.close()
                }
            })
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun dispatchRelayTelemetry(tel: RelayTelemetryState) {
        callbacks.onRelayDirectorState(
            tel.isStandby,
            tel.recState,
            tel.timerState,
            tel.timerRemainingSec,
            tel.timerPresetSec,
            tel.activeScene
        )
        callbacks.onRelayTelemetryState(tel)
    }

    fun closeDead() = shutdownSocket(forceCancel = true)

    fun close() = shutdownSocket(forceCancel = false)

    private fun shutdownSocket(forceCancel: Boolean) {
        if (closed.getAndSet(true)) return
        try {
            if (forceCancel) {
                webSocket?.cancel()
            } else {
                webSocket?.close(1000, "Relay shutdown")
            }
        } catch (_: Exception) {
        }
        webSocket = null
    }
}
