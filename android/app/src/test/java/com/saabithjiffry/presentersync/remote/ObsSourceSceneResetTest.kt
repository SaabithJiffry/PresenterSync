package com.saabithjiffry.presentersync.remote

import com.saabithjiffry.presentersync.remote.network.ObsSessionCallbacks
import com.saabithjiffry.presentersync.remote.network.ObsWebSocketClient
import com.saabithjiffry.presentersync.remote.network.RelayClient
import com.saabithjiffry.presentersync.remote.network.RelayCrypto
import com.saabithjiffry.presentersync.remote.network.RelaySessionCallbacks
import okhttp3.OkHttpClient
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class ObsSourceSceneResetTest {

    @Test
    fun classificationAndAudioProtection_excludeMicsAndDetectMediaCameraBrowser() {
        assertTrue(ObsWebSocketClient.isProtectedAudioSource("Any", "wasapi_input_capture", "Mic/Aux"))
        assertTrue(ObsWebSocketClient.isProtectedAudioSource("Host Mic", "ffmpeg_source", "Host Mic"))
        assertFalse(ObsWebSocketClient.isProtectedAudioSource("Sony FX3", "dshow_input", "Host Mic"))
        assertEquals("dshow", ObsWebSocketClient.classifyResetKind("dshow_input"))
        assertEquals("browser", ObsWebSocketClient.classifyResetKind("browser_source"))
        assertEquals("media", ObsWebSocketClient.classifyResetKind("ffmpeg_source"))
        assertEquals("media", ObsWebSocketClient.classifyResetKind("vlc_source"))
    }

    @Test
    fun sendResetSceneSources_recursesGroupsNestedSkipsDisabledAndSelfHealsDshow() {
        val server = MockWebServer()
        server.start()
        val client = OkHttpClient.Builder().build()
        val identifiedLatch = CountDownLatch(1)
        val selfHealLatch = CountDownLatch(1)
        val sentRequests = Collections.synchronizedList(ArrayList<JSONObject>())

        try {
            server.enqueue(MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
                override fun onOpen(webSocket: WebSocket, response: Response) {
                    webSocket.send("""{"op":0,"d":{"obsWebSocketVersion":"5.3.0"}}""")
                }

                override fun onMessage(webSocket: WebSocket, text: String) {
                    val obj = JSONObject(text)
                    val op = obj.optInt("op", -1)
                    if (op == 1) {
                        webSocket.send("""{"op":2,"d":{"negotiatedRpcVersion":1}}""")
                        return
                    }
                    if (op != 6) return
                    val d = obj.optJSONObject("d") ?: return
                    val reqType = d.optString("requestType")
                    val reqId = d.optString("requestId")
                    val reqData = d.optJSONObject("requestData")
                    sentRequests.add(d)

                    fun reply(data: JSONObject = JSONObject()) {
                        val resp = JSONObject().put("op", 7).put(
                            "d",
                            JSONObject()
                                .put("requestType", reqType)
                                .put("requestId", reqId)
                                .put("requestStatus", JSONObject().put("result", true).put("code", 100))
                                .put("responseData", data)
                        )
                        webSocket.send(resp.toString())
                    }

                    when (reqType) {
                        "GetSceneItemList" -> {
                            val sc = reqData?.optString("sceneName").orEmpty()
                            val arr = JSONArray()
                            if (sc == "Lecture") {
                                arr.put(JSONObject().put("sceneItemId", 1).put("sourceName", "CamGroup").put("isGroup", true).put("sceneItemEnabled", true))
                                arr.put(JSONObject().put("sceneItemId", 2).put("sourceName", "NestedScene").put("sourceType", "OBS_SOURCE_TYPE_SCENE").put("sceneItemEnabled", true))
                                arr.put(JSONObject().put("sceneItemId", 3).put("sourceName", "HiddenItem").put("inputKind", "dshow_input").put("sceneItemEnabled", false))
                                arr.put(JSONObject().put("sceneItemId", 4).put("sourceName", "BrowserWidget").put("inputKind", "browser_source").put("sceneItemEnabled", true))
                                arr.put(JSONObject().put("sceneItemId", 5).put("sourceName", "BumperClip").put("inputKind", "vlc_source").put("sceneItemEnabled", true))
                                arr.put(JSONObject().put("sceneItemId", 6).put("sourceName", "Mic/Aux").put("inputKind", "wasapi_input_capture").put("sceneItemEnabled", true))
                            } else if (sc == "NestedScene") {
                                arr.put(JSONObject().put("sceneItemId", 20).put("sourceName", "SlideCapture").put("inputKind", "window_capture").put("sceneItemEnabled", true))
                            }
                            reply(JSONObject().put("sceneItems", arr))
                        }
                        "GetGroupSceneItemList" -> {
                            val arr = JSONArray()
                            arr.put(JSONObject().put("sceneItemId", 10).put("sourceName", "PodiumCam").put("inputKind", "dshow_input").put("sceneItemEnabled", true))
                            reply(JSONObject().put("sceneItems", arr))
                        }
                        "GetInputSettings" -> {
                            val isVerify = reqId.startsWith("ResetVerifyDshow:")
                            val activeVal = !isVerify
                            reply(JSONObject().put("inputSettings", JSONObject().put("active", activeVal)))
                        }
                        "PressInputPropertiesButton" -> {
                            if (reqId == "ResetDshowSelfHeal") {
                                selfHealLatch.countDown()
                            }
                            reply()
                        }
                        else -> reply()
                    }
                }
            }))

            val wsUrl = server.url("/").toString().replaceFirst("http://", "ws://")
            val obs = ObsWebSocketClient(
                httpClient = client,
                wsUrl = wsUrl,
                password = "",
                targetMicName = "Mic/Aux",
                callbacks = object : ObsSessionCallbacks {
                    override fun onIdentified() { identifiedLatch.countDown() }
                    override fun onAuthFailed() {}
                    override fun onMuteStateChanged(muted: Boolean) {}
                    override fun onMicError() {}
                    override fun onMicRecovered() {}
                    override fun onCloseRemoteSignal() {}
                    override fun onDisconnected(reason: String) {}
                }
            )
            obs.connect()
            assertTrue(identifiedLatch.await(3, TimeUnit.SECONDS))
            assertTrue(obs.sendResetSceneSources("Lecture"))
            assertFalse(obs.sendResetSceneSources("Lecture")) // re-entry mutex active
            assertTrue(selfHealLatch.await(5, TimeUnit.SECONDS))

            val reqList = ArrayList(sentRequests)
            assertTrue(reqList.any { it.optString("requestType") == "GetGroupSceneItemList" })
            assertTrue(reqList.any { it.optString("requestType") == "PressInputPropertiesButton" && it.optJSONObject("requestData")?.optString("propertyName") == "refreshnocache" })
            assertTrue(reqList.any { it.optString("requestType") == "TriggerMediaInputAction" && it.optJSONObject("requestData")?.optString("mediaAction") == "OBS_WEBSOCKET_MEDIA_INPUT_ACTION_RESTART" })
            assertTrue(reqList.any { it.optString("requestId") == "ResetOff_10" && it.optJSONObject("requestData")?.optBoolean("sceneItemEnabled") == false })
            assertTrue(reqList.any { it.optString("requestId") == "ResetOn_10" && it.optJSONObject("requestData")?.optBoolean("sceneItemEnabled") == true })
            assertTrue(reqList.any { it.optString("requestId") == "ResetOff_20" })
            assertTrue(reqList.any { it.optString("requestId") == "ResetOn_20" })
            assertFalse(reqList.any { it.optJSONObject("requestData")?.optInt("sceneItemId", -1) == 3 })
            assertFalse(reqList.any {
                it.optString("requestType") != "GetInputMute" &&
                    it.optJSONObject("requestData")?.optString("inputName") == "Mic/Aux"
            })
            obs.close()
        } finally {
            client.dispatcher.executorService.shutdown()
            client.connectionPool.evictAll()
            runCatching { server.shutdown() }
        }
    }

    @Test
    fun relayClient_publishesResetActiveSceneCommand() {
        val server = MockWebServer()
        server.start()
        val client = OkHttpClient.Builder().build()
        val code = "PS-RST4-1020"
        val baseUrl = server.url("").toString().trimEnd('/')
        server.enqueue(MockResponse().setResponseCode(200))

        try {
            val relay = RelayClient(
                httpClient = client,
                pairingCode = code,
                password = "",
                callbacks = object : RelaySessionCallbacks {
                    override fun onRelayConnected() {}
                    override fun onRelayAuthFailed() {}
                    override fun onRelayMuteState(muted: Boolean) {}
                    override fun onCloseRemoteSignal() {}
                    override fun onRelayDisconnected(reason: String) {}
                },
                httpBaseUrl = baseUrl
            )
            assertTrue(relay.sendResetActiveScene())
            val recorded = server.takeRequest(3, TimeUnit.SECONDS)!!
            val parsed = RelayCrypto.parseRelayEnvelope(recorded.body.readUtf8(), code, "")
            assertEquals("reset_active_scene", parsed?.cmd)
            assertEquals("1", parsed?.data)
        } finally {
            client.dispatcher.executorService.shutdown()
            client.connectionPool.evictAll()
            runCatching { server.shutdown() }
        }
    }
}
