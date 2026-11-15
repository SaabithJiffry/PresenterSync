package com.saabithjiffry.presentersync.remote.network

import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONObject

interface HostBridgeCallbacks {
    fun onBridgeConnected(hostName: String)
    fun onBridgeAuthFailed(reason: String)
    fun onMuteStateChanged(isMuted: Boolean, routingMode: Int, targetMicName: String)
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

            override fun onMessage(webSocket: WebSocket, text: String) {
                if (closedByCaller || mySeq != connSeq.get()) return
                val obj = try {
                    JSONObject(text)
                } catch (_: Exception) {
                    return
                }
                when (obj.optString("type", "").lowercase()) {
                    "auth_ok" -> {
                        authenticated = true
                        val hostName = obj.optString("hostName", "Primary Host")
                        callbacks.onBridgeConnected(hostName)
                    }
                    "auth_error" -> {
                        val err = obj.optString("error", "Bridge authentication failed")
                        callbacks.onBridgeAuthFailed(err)
                    }
                    "mute_state" -> {
                        val muted = obj.optBoolean("isMuted", false)
                        val mode = obj.optInt("routingMode", 0)
                        val mic = obj.optString("targetMicName", "")
                        callbacks.onMuteStateChanged(muted, mode, mic)
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

    fun sendToggleMute(source: String = "clicker"): Boolean {
        if (!authenticated) return false
        val ws = webSocket ?: return false
        val payload = JSONObject().apply {
            put("type", "toggle_mute")
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
        return ws.send("""{"type":"ping"}""")
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
