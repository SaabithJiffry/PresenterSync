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

interface RelaySessionCallbacks {
    fun onRelayConnected()
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
    private val wsBaseUrl: String = AppConstants.NTFY_WS_BASE_URL
) {
    private val topic = RelayCrypto.getInternetRelayTopic(pairingCode)
    private val authToken = RelayCrypto.getInternetRelayAuthToken(pairingCode, password)
    private val closed = AtomicBoolean(false)
    private var webSocket: WebSocket? = null

    fun connect() {
        if (topic.isEmpty()) {
            callbacks.onRelayDisconnected("empty_topic")
            return
        }
        val wsUrl = "${wsBaseUrl.trimEnd('/')}/$topic/ws"
        val req = Request.Builder().url(wsUrl).build()
        webSocket = httpClient.newWebSocket(req, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                if (closed.get()) return
                callbacks.onRelayConnected()
                sendSyncRequest()
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                if (closed.get()) return
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
        val pkt = RelayCrypto.parseRelayPacket(rawMsg)
        if (pkt != null) {
            if (pkt.src != "host") return
            if (pkt.cmd == "auth_error" || pkt.auth != authToken) {
                close()
                callbacks.onRelayAuthFailed()
                return
            }
            when (pkt.cmd) {
                "state" -> {
                    val muted = pkt.data == "1" || pkt.data.equals("true", ignoreCase = true)
                    callbacks.onRelayMuteState(muted)
                }
                "dir_state" -> {
                    val parts = pkt.data.split(";")
                    if (parts.size >= 5) {
                        val standby = parts[0] == "1" || parts[0].equals("true", ignoreCase = true)
                        val recSt = parts[1].toIntOrNull() ?: 0
                        val tState = parts[2].ifBlank { "stopped" }
                        val tRem = parts[3].toIntOrNull() ?: 600
                        val tPre = (parts[4].toIntOrNull() ?: 600).coerceAtLeast(60)
                        val scene = parts.getOrNull(5)?.takeIf { it.isNotBlank() } ?: "Scene"
                        callbacks.onRelayDirectorState(standby, recSt, tState, tRem, tPre, scene)
                    }
                }
                "nudge" -> {
                    val idx = pkt.data.indexOf(';')
                    val sender = if (idx > 0) pkt.data.substring(0, idx).ifBlank { "Host" } else "Host"
                    val msg = if (idx >= 0) pkt.data.substring(idx + 1).trim() else pkt.data.trim()
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
        val pktStr = RelayCrypto.formatRelayPacket("remote", cmd, data, authToken)
        val url = "${httpBaseUrl.trimEnd('/')}/$topic"
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

    fun close() {
        if (closed.getAndSet(true)) return
        try {
            webSocket?.close(1000, "Relay shutdown")
        } catch (_: Exception) {
        }
        webSocket = null
    }
}
