package com.saabithjiffry.presentersync.remote.network

import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONObject
import java.util.concurrent.atomic.AtomicBoolean

interface ObsSessionCallbacks {
    fun onIdentified()
    fun onAuthFailed()
    fun onMuteStateChanged(muted: Boolean)
    fun onMicError()
    fun onMicRecovered()
    fun onCloseRemoteSignal()
    fun onDisconnected(reason: String)
}

class ObsWebSocketClient(
    private val httpClient: OkHttpClient,
    private val wsUrl: String,
    private val password: String,
    private val targetMicName: String,
    private val callbacks: ObsSessionCallbacks
) {
    private var webSocket: WebSocket? = null
    private val closed = AtomicBoolean(false)
    private val identified = AtomicBoolean(false)

    fun connect() {
        val request = Request.Builder().url(wsUrl).build()
        webSocket = httpClient.newWebSocket(request, object : WebSocketListener() {
            override fun onMessage(webSocket: WebSocket, text: String) {
                if (closed.get()) return
                handleRawMessage(webSocket, text)
            }

            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                if (closed.getAndSet(true)) return
                webSocket.close(code, reason)
                if (!identified.get() && code == 4009) {
                    callbacks.onAuthFailed()
                } else {
                    callbacks.onDisconnected("closing:$code")
                }
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                if (closed.getAndSet(true)) return
                if (!identified.get() && code == 4009) {
                    callbacks.onAuthFailed()
                } else {
                    callbacks.onDisconnected("closed:$code")
                }
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                if (closed.getAndSet(true)) return
                callbacks.onDisconnected(t.message ?: "failure")
            }
        })
    }

    internal fun handleRawMessage(ws: WebSocket?, rawMsg: String) {
        val root = try {
            JSONObject(rawMsg)
        } catch (_: Exception) {
            return
        }
        val op = root.optInt("op", -1)
        val d = root.optJSONObject("d") ?: JSONObject()

        when (op) {
            0 -> {
                val authObj = d.optJSONObject("authentication")
                val authString = if (authObj != null) {
                    val salt = authObj.optString("salt", "")
                    val challenge = authObj.optString("challenge", "")
                    if (salt.isNotEmpty() && challenge.isNotEmpty()) {
                        RelayCrypto.computeObsAuthResponse(password, salt, challenge)
                    } else null
                } else null

                val identifyD = JSONObject().apply {
                    put("rpcVersion", 1)
                    put("eventSubscriptions", 2047)
                    if (!authString.isNullOrEmpty()) {
                        put("authentication", authString)
                    }
                }
                val identifyPayload = JSONObject().apply {
                    put("op", 1)
                    put("d", identifyD)
                }
                ws?.send(identifyPayload.toString())
            }
            2 -> {
                identified.set(true)
                callbacks.onIdentified()
                sendRequest("GetInputMute", "InitRemoteMute", JSONObject().apply {
                    put("inputName", targetMicName)
                })
            }
            5 -> {
                val eventType = d.optString("eventType", "")
                val eventData = d.optJSONObject("eventData") ?: JSONObject()
                if (eventType == "InputMuteStateChanged") {
                    val inputName = eventData.optString("inputName", "")
                    if (inputName == targetMicName && eventData.has("inputMuted")) {
                        callbacks.onMicRecovered()
                        callbacks.onMuteStateChanged(eventData.optBoolean("inputMuted", false))
                    }
                } else if (eventType == "CustomEvent") {
                    val cmd = eventData.optString("command", "")
                    val action = eventData.optString("presenterSyncAction", "")
                    if (cmd == "CloseRemote" || action == "CloseRemote") {
                        callbacks.onCloseRemoteSignal()
                    }
                }
            }
            7 -> {
                val reqId = d.optString("requestId", "")
                val reqStatus = d.optJSONObject("requestStatus")
                val resultOk = reqStatus?.optBoolean("result", true) ?: true
                val respData = d.optJSONObject("responseData")
                when (reqId) {
                    "InitRemoteMute" -> {
                        if (!resultOk) {
                            callbacks.onMicError()
                        } else if (respData != null && respData.has("inputMuted")) {
                            callbacks.onMicRecovered()
                            callbacks.onMuteStateChanged(respData.optBoolean("inputMuted", false))
                        }
                    }
                    "RemoteClickerMute" -> {
                        if (!resultOk) {
                            callbacks.onMicError()
                        } else {
                            callbacks.onMicRecovered()
                        }
                    }
                }
            }
        }
    }

    fun sendToggleInputMute(): Boolean {
        return sendRequest("ToggleInputMute", "RemoteClickerMute", JSONObject().apply {
            put("inputName", targetMicName)
        })
    }

    fun sendSetInputMute(muted: Boolean): Boolean {
        return sendRequest("SetInputMute", "RemoteClickerSetMute", JSONObject().apply {
            put("inputName", targetMicName)
            put("inputMuted", muted)
        })
    }

    fun sendHeartbeat(): Boolean {
        return sendRequest("GetVersion", "KeepAlive", null)
    }

    fun sendRequest(requestType: String, requestId: String, requestData: JSONObject?): Boolean {
        val ws = webSocket ?: return false
        if (closed.get()) return false
        val d = JSONObject().apply {
            put("requestType", requestType)
            put("requestId", requestId)
            if (requestData != null) {
                put("requestData", requestData)
            }
        }
        val root = JSONObject().apply {
            put("op", 6)
            put("d", d)
        }
        return try {
            ws.send(root.toString())
        } catch (_: Exception) {
            false
        }
    }

    fun close() {
        if (closed.getAndSet(true)) return
        try {
            webSocket?.close(1000, "Client shutdown")
        } catch (_: Exception) {
        }
        webSocket = null
    }
}
