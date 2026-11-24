package com.saabithjiffry.presentersync.remote.network

import okhttp3.OkHttpClient
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

class ObsWebSocketClientTest {

    private lateinit var server: MockWebServer
    private lateinit var httpClient: OkHttpClient

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
        httpClient = OkHttpClient.Builder().build()
    }

    @After
    fun tearDown() {
        httpClient.dispatcher.executorService.shutdown()
        httpClient.connectionPool.evictAll()
        runCatching { server.shutdown() }
    }

    @Test
    fun authenticatesSyncsMuteTogglesAndHandlesCloseRemote() {
        val password = "testPassword"
        val salt = "testSalt123"
        val challenge = "testChal456"
        val expectedAuth = RelayCrypto.computeObsAuthResponse(password, salt, challenge)

        val identifiedLatch = CountDownLatch(1)
        val mutedTrueLatch = CountDownLatch(1)
        val mutedFalseLatch = CountDownLatch(1)
        val closeSignalLatch = CountDownLatch(1)
        val seenToggleReq = AtomicBoolean(false)
        val serverWsRef = AtomicReference<WebSocket>()

        server.enqueue(MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                serverWsRef.set(webSocket)
                val hello = JSONObject().put("op", 0).put(
                    "d",
                    JSONObject().put("obsWebSocketVersion", "5.3.0").put(
                        "authentication",
                        JSONObject().put("salt", salt).put("challenge", challenge)
                    )
                )
                webSocket.send(hello.toString())
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                val msg = JSONObject(text)
                when (msg.optInt("op")) {
                    1 -> {
                        val auth = msg.getJSONObject("d").optString("authentication")
                        assertEquals(expectedAuth, auth)
                        webSocket.send(
                            JSONObject().put("op", 2)
                                .put("d", JSONObject().put("negotiatedRpcVersion", 1))
                                .toString()
                        )
                    }
                    6 -> {
                        val d = msg.getJSONObject("d")
                        when (d.optString("requestType")) {
                            "GetInputMute" -> {
                                val resp = JSONObject().put("op", 7).put(
                                    "d",
                                    JSONObject()
                                        .put("requestType", "GetInputMute")
                                        .put("requestId", d.getString("requestId"))
                                        .put("requestStatus", JSONObject().put("result", true).put("code", 100))
                                        .put("responseData", JSONObject().put("inputMuted", true))
                                )
                                webSocket.send(resp.toString())
                            }
                            "ToggleInputMute" -> {
                                seenToggleReq.set(true)
                                webSocket.send(
                                    JSONObject().put("op", 7).put(
                                        "d",
                                        JSONObject()
                                            .put("requestType", "ToggleInputMute")
                                            .put("requestId", d.getString("requestId"))
                                            .put("requestStatus", JSONObject().put("result", true).put("code", 100))
                                    ).toString()
                                )
                                webSocket.send(
                                    JSONObject().put("op", 5).put(
                                        "d",
                                        JSONObject()
                                            .put("eventType", "InputMuteStateChanged")
                                            .put(
                                                "eventData",
                                                JSONObject()
                                                    .put("inputName", "Mic/Aux")
                                                    .put("inputMuted", false)
                                            )
                                    ).toString()
                                )
                                webSocket.send(
                                    JSONObject().put("op", 5).put(
                                        "d",
                                        JSONObject()
                                            .put("eventType", "CustomEvent")
                                            .put("eventData", JSONObject().put("command", "CloseRemote"))
                                    ).toString()
                                )
                            }
                        }
                    }
                }
            }
        }))

        val clientRef = AtomicReference<ObsWebSocketClient>()
        val client = ObsWebSocketClient(
            httpClient = httpClient,
            wsUrl = "ws://${server.hostName}:${server.port}/",
            password = password,
            targetMicName = "Mic/Aux",
            callbacks = object : ObsSessionCallbacks {
                override fun onIdentified() { identifiedLatch.countDown() }
                override fun onAuthFailed() {}
                override fun onMuteStateChanged(muted: Boolean) {
                    if (muted) mutedTrueLatch.countDown() else mutedFalseLatch.countDown()
                }
                override fun onMicError() {}
                override fun onMicRecovered() {}
                override fun onCloseRemoteSignal() { closeSignalLatch.countDown() }
                override fun onDisconnected(reason: String) {}
            }
        )
        clientRef.set(client)
        client.connect()

        assertTrue(identifiedLatch.await(3, TimeUnit.SECONDS))
        assertTrue(mutedTrueLatch.await(3, TimeUnit.SECONDS))
        assertTrue(client.sendToggleInputMute())
        assertTrue(mutedFalseLatch.await(3, TimeUnit.SECONDS))
        assertTrue(seenToggleReq.get())
        assertTrue(closeSignalLatch.await(3, TimeUnit.SECONDS))

        serverWsRef.get()?.close(1000, "test done")
        client.close()
    }

    @Test
    fun reportsAuthFailedOn4009Close() {
        val authFailLatch = CountDownLatch(1)
        server.enqueue(MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                webSocket.send(
                    JSONObject().put("op", 0).put(
                        "d",
                        JSONObject().put(
                            "authentication",
                            JSONObject().put("salt", "s").put("challenge", "c")
                        )
                    ).toString()
                )
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                webSocket.close(4009, "Authentication failed.")
            }
        }))

        val client = ObsWebSocketClient(
            httpClient = httpClient,
            wsUrl = "ws://${server.hostName}:${server.port}/",
            password = "wrong",
            targetMicName = "Mic/Aux",
            callbacks = object : ObsSessionCallbacks {
                override fun onIdentified() {}
                override fun onAuthFailed() { authFailLatch.countDown() }
                override fun onMuteStateChanged(muted: Boolean) {}
                override fun onMicError() {}
                override fun onMicRecovered() {}
                override fun onCloseRemoteSignal() {}
                override fun onDisconnected(reason: String) {}
            }
        )
        client.connect()

        assertTrue(authFailLatch.await(3, TimeUnit.SECONDS))
        client.close()
    }

    @Test
    fun reportsMicErrorWhenTargetInputNotFound() {
        val micErrLatch = CountDownLatch(1)
        val client = ObsWebSocketClient(
            httpClient = httpClient,
            wsUrl = "ws://127.0.0.1:1/",
            password = "",
            targetMicName = "MissingMic",
            callbacks = object : ObsSessionCallbacks {
                override fun onIdentified() {}
                override fun onAuthFailed() {}
                override fun onMuteStateChanged(muted: Boolean) {}
                override fun onMicError() { micErrLatch.countDown() }
                override fun onMicRecovered() {}
                override fun onCloseRemoteSignal() {}
                override fun onDisconnected(reason: String) {}
            }
        )

        client.handleRawMessage(
            null,
            JSONObject().put("op", 7).put(
                "d",
                JSONObject()
                    .put("requestId", "InitRemoteMute")
                    .put("requestStatus", JSONObject().put("result", false).put("code", 600))
            ).toString()
        )
        assertTrue(micErrLatch.await(1, TimeUnit.SECONDS))
    }

    @Test
    fun reportsSceneTransitionErrorWhenTransitionRequestFails() {
        val sceneErrLatch = CountDownLatch(1)
        val errInfo = AtomicReference<Triple<String, Int, String>>()
        val client = ObsWebSocketClient(
            httpClient = httpClient,
            wsUrl = "ws://127.0.0.1:1/",
            password = "",
            targetMicName = "Mic/Aux",
            callbacks = object : ObsSessionCallbacks {
                override fun onIdentified() {}
                override fun onAuthFailed() {}
                override fun onMuteStateChanged(muted: Boolean) {}
                override fun onMicError() {}
                override fun onMicRecovered() {}
                override fun onCloseRemoteSignal() {}
                override fun onDisconnected(reason: String) {}
                override fun onSceneTransitionError(requestId: String, code: Int, comment: String) {
                    errInfo.set(Triple(requestId, code, comment))
                    sceneErrLatch.countDown()
                }
            }
        )

        client.handleRawMessage(
            null,
            JSONObject().put("op", 7).put(
                "d",
                JSONObject()
                    .put("requestId", "RemoteSceneTransition")
                    .put("requestStatus", JSONObject().put("result", false).put("code", 507).put("comment", "Studio mode disabled"))
            ).toString()
        )
        assertTrue(sceneErrLatch.await(1, TimeUnit.SECONDS))
        assertEquals(Triple("RemoteSceneTransition", 507, "Studio mode disabled"), errInfo.get())
    }
}
