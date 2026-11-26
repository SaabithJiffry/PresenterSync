package com.saabithjiffry.presentersync.remote.network

import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

interface ObsSessionCallbacks {
    fun onIdentified()
    fun onFrameReceived() {}
    fun onAuthFailed()
    fun onMuteStateChanged(muted: Boolean)
    fun onRecordStateChanged(recState: Int, recSeconds: Int = -1) {}
    fun onStreamStateChanged(active: Boolean, reconnecting: Boolean = false, dropWarn: Boolean = false) {}
    fun onStudioModeStateChanged(enabled: Boolean) {}
    fun onProgramSceneChanged(sceneName: String) {}
    fun onPreviewSceneChanged(sceneName: String) {}
    fun onSceneListChanged(scenes: List<String>) {}
    fun onSceneTransitionError(requestId: String, code: Int, comment: String) {}
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
    private val resetScheduler = Executors.newSingleThreadScheduledExecutor { r ->
        Thread(r, "ObsResetSceneWorker").apply { isDaemon = true }
    }

    fun connect() {
        val request = Request.Builder().url(wsUrl).build()
        webSocket = httpClient.newWebSocket(request, object : WebSocketListener() {
            override fun onMessage(webSocket: WebSocket, text: String) {
                if (closed.get()) return
                callbacks.onFrameReceived()
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
                sendGetInputMute()
                sendGetRecordStatus()
                sendGetStreamStatus("InitRemoteStream")
                sendGetStudioModeEnabled()
                sendGetCurrentProgramScene()
                sendGetCurrentPreviewScene()
                sendGetSceneList()
            }
            5 -> {
                val eventType = d.optString("eventType", "")
                val eventData = d.optJSONObject("eventData") ?: JSONObject()
                when (eventType) {
                    "InputMuteStateChanged" -> {
                        val inputName = eventData.optString("inputName", "")
                        if (inputName == targetMicName && eventData.has("inputMuted")) {
                            callbacks.onMicRecovered()
                            callbacks.onMuteStateChanged(eventData.optBoolean("inputMuted", false))
                        }
                    }
                    "RecordStateChanged" -> {
                        val outputState = eventData.optString("outputState", "")
                        val outputActive = eventData.optBoolean("outputActive", false)
                        val nextRecState = when (outputState) {
                            "OBS_WEBSOCKET_OUTPUT_STARTED", "OBS_WEBSOCKET_OUTPUT_RESUMED" -> 1
                            "OBS_WEBSOCKET_OUTPUT_PAUSED" -> 2
                            "OBS_WEBSOCKET_OUTPUT_STOPPED" -> 0
                            else -> if (outputActive) 1 else 0
                        }
                        callbacks.onRecordStateChanged(nextRecState, if (nextRecState == 0) 0 else -1)
                        if (nextRecState == 1 || nextRecState == 2) {
                            sendRequest("GetRecordStatus", "SyncRemoteRec", null)
                        }
                    }
                    "StreamStateChanged" -> {
                        val outputActive = eventData.optBoolean("outputActive", false)
                        val outputState = eventData.optString("outputState", "")
                        val reconnecting = outputState.contains("RECONNECTING", ignoreCase = true)
                        callbacks.onStreamStateChanged(outputActive, reconnecting, reconnecting)
                    }
                    "StudioModeStateChanged" -> {
                        val enabled = eventData.optBoolean("studioModeEnabled", false)
                        callbacks.onStudioModeStateChanged(enabled)
                        if (enabled) {
                            sendGetCurrentPreviewScene()
                        }
                    }
                    "CurrentProgramSceneChanged" -> {
                        val sceneName = eventData.optString(
                            "sceneName",
                            eventData.optString("currentProgramSceneName", "")
                        ).trim()
                        if (sceneName.isNotEmpty()) {
                            callbacks.onProgramSceneChanged(sceneName)
                        }
                    }
                    "CurrentPreviewSceneChanged" -> {
                        val sceneName = eventData.optString(
                            "sceneName",
                            eventData.optString("currentPreviewSceneName", "")
                        ).trim()
                        if (sceneName.isNotEmpty()) {
                            callbacks.onPreviewSceneChanged(sceneName)
                        }
                    }
                    "SceneListChanged" -> {
                        val parsed = parseSceneList(eventData.optJSONArray("scenes"))
                        if (parsed.isNotEmpty()) {
                            callbacks.onSceneListChanged(parsed)
                        } else {
                            sendGetSceneList()
                        }
                    }
                    "CustomEvent" -> {
                        val cmd = eventData.optString("command", "")
                        val action = eventData.optString("presenterSyncAction", "")
                        if (cmd == "CloseRemote" || action == "CloseRemote") {
                            callbacks.onCloseRemoteSignal()
                        }
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
                    "RemoteClickerMute", "RemoteClickerSetMute" -> {
                        if (!resultOk) {
                            callbacks.onMicError()
                        } else {
                            callbacks.onMicRecovered()
                        }
                    }
                    "InitRemoteRec", "SyncRemoteRec" -> {
                        if (resultOk && respData != null) {
                            val active = respData.optBoolean("outputActive", false)
                            val paused = respData.optBoolean("outputPaused", false)
                            val durMs = respData.optLong("outputDuration", -1L)
                            val durSec = if (durMs >= 0L) (durMs / 1000L).toInt() else 0
                            val st = if (!active) 0 else if (paused) 2 else 1
                            callbacks.onRecordStateChanged(st, durSec)
                        }
                    }
                    "InitRemoteStream", "PollRemoteStream" -> {
                        if (resultOk && respData != null) {
                            val active = respData.optBoolean("outputActive", false)
                            val reconnecting = respData.optBoolean("outputReconnecting", false)
                            val congestion = respData.optDouble("outputCongestion", 0.0)
                            val warn = reconnecting || (active && !congestion.isNaN() && congestion >= 0.35)
                            callbacks.onStreamStateChanged(active, reconnecting, warn)
                        }
                    }
                    "InitRemoteStudio" -> {
                        if (resultOk && respData != null && respData.has("studioModeEnabled")) {
                            val enabled = respData.optBoolean("studioModeEnabled", false)
                            callbacks.onStudioModeStateChanged(enabled)
                            if (enabled) {
                                sendGetCurrentPreviewScene()
                            }
                        }
                    }
                    "InitRemoteScene" -> {
                        if (resultOk && respData != null) {
                            val sceneName = respData.optString(
                                "currentProgramSceneName",
                                respData.optString("sceneName", "")
                            ).trim()
                            if (sceneName.isNotEmpty()) {
                                callbacks.onProgramSceneChanged(sceneName)
                            }
                        }
                    }
                    "InitRemotePreviewScene" -> {
                        if (resultOk && respData != null) {
                            val sceneName = respData.optString(
                                "currentPreviewSceneName",
                                respData.optString("sceneName", "")
                            ).trim()
                            if (sceneName.isNotEmpty()) {
                                callbacks.onPreviewSceneChanged(sceneName)
                            }
                        }
                    }
                    "InitRemoteSceneList" -> {
                        if (resultOk && respData != null) {
                            val scenes = parseSceneList(respData.optJSONArray("scenes"))
                            if (scenes.isNotEmpty()) {
                                callbacks.onSceneListChanged(scenes)
                            }
                            val curProg = respData.optString("currentProgramSceneName", "").trim()
                            if (curProg.isNotEmpty()) {
                                callbacks.onProgramSceneChanged(curProg)
                            }
                            val curPrev = respData.optString("currentPreviewSceneName", "").trim()
                            if (curPrev.isNotEmpty()) {
                                callbacks.onPreviewSceneChanged(curPrev)
                            }
                        }
                    }
                    "RemoteSceneTransition", "RemoteSwitchScene" -> {
                        if (!resultOk) {
                            val errCode = reqStatus?.optInt("code", -1) ?: -1
                            val errComment = reqStatus?.optString("comment", "").orEmpty()
                            callbacks.onSceneTransitionError(reqId, errCode, errComment)
                        }
                    }
                    else -> if (reqId.startsWith("ResetSceneList:")) {
                        if (resultOk && respData != null) {
                            val sceneName = reqId.removePrefix("ResetSceneList:").trim()
                            val items = respData.optJSONArray("sceneItems") ?: JSONArray()
                            val enabledIds = ArrayList<Int>(items.length())
                            for (i in 0 until items.length()) {
                                val obj = items.optJSONObject(i) ?: continue
                                val id = obj.optInt("sceneItemId", -1)
                                if (id >= 0 && obj.optBoolean("sceneItemEnabled", true)) {
                                    enabledIds.add(id)
                                }
                            }
                            if (sceneName.isNotEmpty() && enabledIds.isNotEmpty()) {
                                for (id in enabledIds) {
                                    sendRequest(
                                        "SetSceneItemEnabled",
                                        "ResetOff_$id",
                                        JSONObject().apply {
                                            put("sceneName", sceneName)
                                            put("sceneItemId", id)
                                            put("sceneItemEnabled", false)
                                        }
                                    )
                                }
                                resetScheduler.schedule({
                                    if (!closed.get()) {
                                        for (id in enabledIds) {
                                            sendRequest(
                                                "SetSceneItemEnabled",
                                                "ResetOn_$id",
                                                JSONObject().apply {
                                                    put("sceneName", sceneName)
                                                    put("sceneItemId", id)
                                                    put("sceneItemEnabled", true)
                                                }
                                            )
                                        }
                                    }
                                }, 250L, TimeUnit.MILLISECONDS)
                            }
                        }
                    }
                }
            }
        }
    }

    internal fun parseSceneList(arr: JSONArray?): List<String> {
        if (arr == null || arr.length() == 0) return emptyList()
        val rawNames = ArrayList<String>(arr.length())
        var firstIndex = -1
        var lastIndex = -1
        for (i in 0 until arr.length()) {
            val obj = arr.optJSONObject(i)
            val name = if (obj != null) {
                if (obj.has("sceneIndex")) {
                    val idxVal = obj.optInt("sceneIndex", -1)
                    if (firstIndex == -1) firstIndex = idxVal
                    lastIndex = idxVal
                }
                obj.optString("sceneName", "").trim()
            } else {
                arr.optString(i, "").trim()
            }
            if (name.isNotEmpty() && !rawNames.contains(name)) {
                rawNames.add(name)
            }
        }
        return if (rawNames.size > 1 && firstIndex >= 0 && lastIndex > firstIndex) {
            rawNames.asReversed()
        } else {
            rawNames
        }
    }

    fun sendGetInputMute(): Boolean {
        return sendRequest("GetInputMute", "InitRemoteMute", JSONObject().apply {
            put("inputName", targetMicName)
        })
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

    fun sendGetRecordStatus(): Boolean =
        sendRequest("GetRecordStatus", "InitRemoteRec", null)

    fun sendToggleRecord(): Boolean =
        sendRequest("ToggleRecord", "RemoteToggleRec", null)

    fun sendToggleRecordPause(): Boolean =
        sendRequest("ToggleRecordPause", "RemotePauseRec", null)

    fun sendSplitRecordFile(): Boolean =
        sendRequest("SplitRecordFile", "RemoteSplitRec", null)

    fun sendGetStreamStatus(requestId: String = "PollRemoteStream"): Boolean =
        sendRequest("GetStreamStatus", requestId, null)

    fun sendGetStudioModeEnabled(): Boolean =
        sendRequest("GetStudioModeEnabled", "InitRemoteStudio", null)

    fun sendTriggerStudioModeTransition(): Boolean =
        sendRequest("TriggerStudioModeTransition", "RemoteSceneTransition", null)

    fun sendGetCurrentProgramScene(): Boolean =
        sendRequest("GetCurrentProgramScene", "InitRemoteScene", null)

    fun sendGetCurrentPreviewScene(): Boolean =
        sendRequest("GetCurrentPreviewScene", "InitRemotePreviewScene", null)

    fun sendSetCurrentProgramScene(sceneName: String): Boolean {
        val clean = sceneName.trim()
        if (clean.isEmpty()) return false
        return sendRequest("SetCurrentProgramScene", "RemoteSwitchScene", JSONObject().apply {
            put("sceneName", clean)
        })
    }

    fun sendGetSceneList(): Boolean =
        sendRequest("GetSceneList", "InitRemoteSceneList", null)

    fun sendResetSceneSources(sceneName: String): Boolean {
        val clean = sceneName.trim()
        if (clean.isEmpty()) return false
        return sendRequest("GetSceneItemList", "ResetSceneList:$clean", JSONObject().apply {
            put("sceneName", clean)
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

    fun closeDead() {
        if (closed.getAndSet(true)) return
        try {
            webSocket?.cancel()
        } catch (_: Exception) {
        }
        webSocket = null
        runCatching { resetScheduler.shutdownNow() }
    }

    fun close() {
        if (closed.getAndSet(true)) return
        try {
            webSocket?.close(1000, "Client shutdown")
        } catch (_: Exception) {
        }
        webSocket = null
        runCatching { resetScheduler.shutdownNow() }
    }
}
