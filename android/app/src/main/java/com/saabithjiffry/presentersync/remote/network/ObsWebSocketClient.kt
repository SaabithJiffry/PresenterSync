package com.saabithjiffry.presentersync.remote.network

import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

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
    private val resetInFlight = AtomicBoolean(false)
    private val resetWatchdogFuture = AtomicReference<ScheduledFuture<*>?>(null)
    private val resetScheduler = Executors.newSingleThreadScheduledExecutor { r ->
        Thread(r, "ObsResetSceneWorker").apply { isDaemon = true }
    }
    private val resetSeq = AtomicInteger(0)
    private val resetLock = Any()
    private var activeResetCtx: RecursiveSceneResetCtx? = null
    @Volatile
    private var pendingReenableItems: List<ReenableSceneItem> = emptyList()

    private data class ReenableSceneItem(
        val sceneName: String,
        val sceneItemId: Int,
        val isDshow: Boolean,
        val inputName: String
    )

    private class RecursiveSceneResetCtx(
        val token: String,
        val targetScene: String
    ) {
        var pending: Int = 1
        val visited = HashSet<String>().apply { add("scn:${targetScene.lowercase()}") }
        val toggleItems = ArrayList<ReenableSceneItem>()
        val dshowCandidates = ArrayList<ReenableSceneItem>()
        val dshowItems = ArrayList<ReenableSceneItem>()
        val browserInputs = LinkedHashSet<String>()
        val mediaInputs = LinkedHashSet<String>()
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
                cleanupResetScheduler()
                webSocket.close(code, reason)
                if (!identified.get() && code == 4009) {
                    callbacks.onAuthFailed()
                } else {
                    callbacks.onDisconnected("closing:$code")
                }
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                if (closed.getAndSet(true)) return
                cleanupResetScheduler()
                if (!identified.get() && code == 4009) {
                    callbacks.onAuthFailed()
                } else {
                    callbacks.onDisconnected("closed:$code")
                }
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                if (closed.getAndSet(true)) return
                cleanupResetScheduler()
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
                recoverOrphanSceneResetItems()
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
                    "RemoteSceneTransition", "RemoteSwitchScene", "RemoteSetPreviewScene" -> {
                        if (!resultOk) {
                            val errCode = reqStatus?.optInt("code", -1) ?: -1
                            val errComment = reqStatus?.optString("comment", "").orEmpty()
                            callbacks.onSceneTransitionError(reqId, errCode, errComment)
                        }
                    }
                    else -> when {
                        reqId.startsWith("ResetSceneList:") || reqId.startsWith("ResetSceneCrawl:") ||
                            reqId.startsWith("ResetCheckDshow:") || reqId.startsWith("ResetVerifyDshow:") -> {
                            handleRecursiveSceneResetResponse(reqId, resultOk, respData)
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

    fun sendSetCurrentPreviewScene(sceneName: String): Boolean {
        val clean = sceneName.trim()
        if (clean.isEmpty()) return false
        return sendRequest("SetCurrentPreviewScene", "RemoteSetPreviewScene", JSONObject().apply {
            put("sceneName", clean)
        })
    }

    fun sendGetSceneList(): Boolean =
        sendRequest("GetSceneList", "InitRemoteSceneList", null)

    fun sendResetSceneSources(sceneName: String): Boolean {
        val clean = sceneName.trim()
        if (clean.isEmpty() || !resetInFlight.compareAndSet(false, true)) return false
        val tok = resetSeq.incrementAndGet().toString()
        synchronized(resetLock) {
            activeResetCtx = RecursiveSceneResetCtx(tok, clean)
        }
        try {
            val watchdog = resetScheduler.schedule({
                synchronized(resetLock) { activeResetCtx = null }
                resetInFlight.set(false)
            }, 5000L, TimeUnit.MILLISECONDS)
            resetWatchdogFuture.getAndSet(watchdog)?.cancel(false)
        } catch (_: RejectedExecutionException) {
            synchronized(resetLock) { activeResetCtx = null }
            resetInFlight.set(false)
            return false
        }
        val ok = sendRequest("GetSceneItemList", "ResetSceneCrawl:$tok:0:$clean", JSONObject().apply {
            put("sceneName", clean)
        })
        if (!ok) {
            resetWatchdogFuture.getAndSet(null)?.cancel(false)
            synchronized(resetLock) { activeResetCtx = null }
            resetInFlight.set(false)
        }
        return ok
    }

    internal fun recoverOrphanSceneResetItems() {
        val items = pendingReenableItems
        if (items.isEmpty() || closed.get()) return
        pendingReenableItems = emptyList()
        for (it in items) {
            sendRequest("SetSceneItemEnabled", "ResetRecOn_${it.sceneItemId}", JSONObject().apply {
                put("sceneName", it.sceneName)
                put("sceneItemId", it.sceneItemId)
                put("sceneItemEnabled", true)
            })
            if (it.isDshow && it.inputName.isNotEmpty()) {
                sendRequest("PressInputPropertiesButton", "ResetRecAct", JSONObject().apply {
                    put("inputName", it.inputName)
                    put("propertyName", "activate")
                })
            }
        }
    }

    private fun handleRecursiveSceneResetResponse(reqId: String, resultOk: Boolean, respData: JSONObject?) {
        if (reqId.startsWith("ResetVerifyDshow:")) {
            if (resultOk && respData != null && !closed.get()) {
                val active = respData.optJSONObject("inputSettings")?.optBoolean("active", true) ?: true
                if (!active) {
                    val parts = reqId.removePrefix("ResetVerifyDshow:").split(":", limit = 2)
                    val inputName = parts.getOrNull(1).orEmpty().trim()
                    if (inputName.isNotEmpty()) {
                        sendRequest("PressInputPropertiesButton", "ResetDshowSelfHeal", JSONObject().apply {
                            put("inputName", inputName)
                            put("propertyName", "activate")
                        })
                    }
                }
            }
            return
        }

        if (reqId.startsWith("ResetSceneList:")) {
            // Backward-compatible direct list handler
            val sceneName = reqId.removePrefix("ResetSceneList:").trim()
            val items = respData?.optJSONArray("sceneItems") ?: JSONArray()
            val toReset = ArrayList<ReenableSceneItem>(items.length())
            for (i in 0 until items.length()) {
                val obj = items.optJSONObject(i) ?: continue
                if (!obj.optBoolean("sceneItemEnabled", true)) continue
                val id = obj.optInt("sceneItemId", -1)
                val name = obj.optString("sourceName", "").trim()
                val kind = obj.optString("inputKind", "").trim()
                if (id >= 0 && !isProtectedAudioSource(name, kind, targetMicName)) {
                    toReset.add(ReenableSceneItem(sceneName, id, classifyResetKind(kind) == "dshow", name))
                }
            }
            val legacyCtx = RecursiveSceneResetCtx("legacy", sceneName).apply {
                pending = 0
                toggleItems.addAll(toReset)
            }
            executeResetPhase1(legacyCtx)
            return
        }

        val readyCtx: RecursiveSceneResetCtx? = synchronized(resetLock) {
            val ctx = activeResetCtx ?: return@synchronized null
            if (reqId.startsWith("ResetSceneCrawl:")) {
                ctx.pending -= 1
                val parts = reqId.removePrefix("ResetSceneCrawl:").split(":", limit = 3)
                if (parts.size >= 3 && parts[0] == ctx.token && resultOk && respData != null) {
                    val depth = parts[1].toIntOrNull() ?: 0
                    val containerName = parts[2]
                    val items = respData.optJSONArray("sceneItems") ?: JSONArray()
                    for (i in 0 until items.length()) {
                        val obj = items.optJSONObject(i) ?: continue
                        if (!obj.optBoolean("sceneItemEnabled", true)) continue
                        val id = obj.optInt("sceneItemId", -1)
                        val srcName = obj.optString("sourceName", "").trim()
                        val srcType = obj.optString("sourceType", "").trim()
                        val inKind = obj.optString("inputKind", "").trim()
                        val isGrp = obj.optBoolean("isGroup", false)
                        if (isGrp && srcName.isNotEmpty()) {
                            val vk = "grp:${srcName.lowercase()}"
                            if (depth < 6 && ctx.visited.add(vk)) {
                                ctx.pending += 1
                                sendRequest("GetGroupSceneItemList", "ResetSceneCrawl:${ctx.token}:${depth + 1}:$srcName", JSONObject().put("sceneName", srcName))
                            }
                        } else if (srcType == "OBS_SOURCE_TYPE_SCENE" && srcName.isNotEmpty()) {
                            val vk = "scn:${srcName.lowercase()}"
                            if (depth < 6 && ctx.visited.add(vk)) {
                                ctx.pending += 1
                                sendRequest("GetSceneItemList", "ResetSceneCrawl:${ctx.token}:${depth + 1}:$srcName", JSONObject().put("sceneName", srcName))
                            }
                        } else if (id >= 0) {
                            if (isProtectedAudioSource(srcName, inKind, targetMicName)) continue
                            when (classifyResetKind(inKind)) {
                                "dshow" -> if (srcName.isNotEmpty()) {
                                    ctx.pending += 1
                                    val idx = ctx.dshowCandidates.size
                                    ctx.dshowCandidates.add(ReenableSceneItem(containerName, id, true, srcName))
                                    sendRequest("GetInputSettings", "ResetCheckDshow:${ctx.token}:$idx", JSONObject().put("inputName", srcName))
                                }
                                "browser" -> if (srcName.isNotEmpty()) ctx.browserInputs.add(srcName)
                                "media" -> if (srcName.isNotEmpty()) ctx.mediaInputs.add(srcName)
                                else -> ctx.toggleItems.add(ReenableSceneItem(containerName, id, false, srcName))
                            }
                        }
                    }
                }
            } else if (reqId.startsWith("ResetCheckDshow:")) {
                ctx.pending -= 1
                val parts = reqId.removePrefix("ResetCheckDshow:").split(":", limit = 2)
                val idx = parts.getOrNull(1)?.toIntOrNull()
                if (parts.getOrNull(0) == ctx.token && idx != null && idx in ctx.dshowCandidates.indices) {
                    val cand = ctx.dshowCandidates[idx]
                    val active = if (resultOk && respData != null) {
                        respData.optJSONObject("inputSettings")?.optBoolean("active", true) ?: true
                    } else true
                    if (active) ctx.dshowItems.add(cand)
                }
            }
            if (ctx.pending <= 0) {
                activeResetCtx = null
                ctx
            } else null
        }

        if (readyCtx != null) {
            executeResetPhase1(readyCtx)
        }
    }

    private fun executeResetPhase1(ctx: RecursiveSceneResetCtx) {
        val total = ctx.toggleItems.size + ctx.dshowItems.size + ctx.browserInputs.size + ctx.mediaInputs.size
        if (total == 0) {
            resetWatchdogFuture.getAndSet(null)?.cancel(false)
            resetInFlight.set(false)
            return
        }
        for (bName in ctx.browserInputs) {
            sendRequest("PressInputPropertiesButton", "ResetBrowser", JSONObject().apply {
                put("inputName", bName)
                put("propertyName", "refreshnocache")
            })
        }
        for (mName in ctx.mediaInputs) {
            sendRequest("TriggerMediaInputAction", "ResetMedia", JSONObject().apply {
                put("inputName", mName)
                put("mediaAction", "OBS_WEBSOCKET_MEDIA_INPUT_ACTION_RESTART")
            })
        }
        val reEnable = ArrayList<ReenableSceneItem>(ctx.dshowItems.size + ctx.toggleItems.size)
        for (ds in ctx.dshowItems) {
            sendRequest("PressInputPropertiesButton", "ResetDshowOff", JSONObject().apply {
                put("inputName", ds.inputName)
                put("propertyName", "activate")
            })
            sendRequest("SetSceneItemEnabled", "ResetOff_${ds.sceneItemId}", JSONObject().apply {
                put("sceneName", ds.sceneName)
                put("sceneItemId", ds.sceneItemId)
                put("sceneItemEnabled", false)
            })
            reEnable.add(ds)
        }
        for (it in ctx.toggleItems) {
            sendRequest("SetSceneItemEnabled", "ResetOff_${it.sceneItemId}", JSONObject().apply {
                put("sceneName", it.sceneName)
                put("sceneItemId", it.sceneItemId)
                put("sceneItemEnabled", false)
            })
            reEnable.add(it)
        }
        if (reEnable.isEmpty()) {
            resetWatchdogFuture.getAndSet(null)?.cancel(false)
            resetInFlight.set(false)
            return
        }
        pendingReenableItems = reEnable.toList()
        try {
            resetScheduler.schedule({
                try {
                    if (!closed.get()) {
                        for (it in ctx.toggleItems) {
                            sendRequest("SetSceneItemEnabled", "ResetOn_${it.sceneItemId}", JSONObject().apply {
                                put("sceneName", it.sceneName)
                                put("sceneItemId", it.sceneItemId)
                                put("sceneItemEnabled", true)
                            })
                        }
                        for (ds in ctx.dshowItems) {
                            sendRequest("SetSceneItemEnabled", "ResetOn_${ds.sceneItemId}", JSONObject().apply {
                                put("sceneName", ds.sceneName)
                                put("sceneItemId", ds.sceneItemId)
                                put("sceneItemEnabled", true)
                            })
                            sendRequest("PressInputPropertiesButton", "ResetDshowOn", JSONObject().apply {
                                put("inputName", ds.inputName)
                                put("propertyName", "activate")
                            })
                        }
                        pendingReenableItems = emptyList()
                        if (ctx.dshowItems.isNotEmpty()) {
                            runCatching {
                                resetScheduler.schedule({
                                    if (!closed.get()) {
                                        for (ds in ctx.dshowItems) {
                                            sendRequest("GetInputSettings", "ResetVerifyDshow:${ctx.token}:${ds.inputName}", JSONObject().apply {
                                                put("inputName", ds.inputName)
                                            })
                                        }
                                    }
                                }, 1500L, TimeUnit.MILLISECONDS)
                            }
                        }
                    }
                } finally {
                    resetWatchdogFuture.getAndSet(null)?.cancel(false)
                    resetInFlight.set(false)
                }
            }, 600L, TimeUnit.MILLISECONDS)
        } catch (_: RejectedExecutionException) {
            resetWatchdogFuture.getAndSet(null)?.cancel(false)
            resetInFlight.set(false)
        }
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

    private fun cleanupResetScheduler() {
        resetWatchdogFuture.getAndSet(null)?.cancel(false)
        resetInFlight.set(false)
        runCatching { resetScheduler.shutdownNow() }
    }

    fun closeDead() {
        if (closed.getAndSet(true)) return
        try {
            webSocket?.cancel()
        } catch (_: Exception) {
        }
        webSocket = null
        cleanupResetScheduler()
    }

    fun close() {
        if (closed.getAndSet(true)) return
        try {
            webSocket?.close(1000, "Client shutdown")
        } catch (_: Exception) {
        }
        webSocket = null
        cleanupResetScheduler()
    }

    companion object {
        private val PROTECTED_AUDIO_KINDS = setOf(
            "wasapi_input_capture",
            "wasapi_output_capture",
            "coreaudio_input_capture",
            "coreaudio_output_capture",
            "pulse_input_capture",
            "pulse_output_capture",
            "alsa_input_capture",
            "oss_input_capture",
            "jack_output_capture",
            "sndio_output_capture"
        )

        internal fun isProtectedAudioSource(
            inputName: String,
            inputKind: String,
            targetMicName: String
        ): Boolean {
            val kd = inputKind.trim().lowercase()
            if (kd.isNotEmpty() && (PROTECTED_AUDIO_KINDS.contains(kd) || kd.contains("_input_capture"))) {
                return true
            }
            val nm = inputName.trim()
            val tm = targetMicName.trim()
            return nm.isNotEmpty() && tm.isNotEmpty() && nm.equals(tm, ignoreCase = true)
        }

        internal fun classifyResetKind(inputKind: String): String {
            return when (inputKind.trim().lowercase()) {
                "dshow_input", "v4l2_input", "av_capture_input_v2", "av_capture_input" -> "dshow"
                "browser_source" -> "browser"
                "ffmpeg_source", "vlc_source" -> "media"
                else -> "toggle"
            }
        }
    }
}
