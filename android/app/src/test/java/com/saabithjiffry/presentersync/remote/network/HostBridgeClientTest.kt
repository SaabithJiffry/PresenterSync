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

class HostBridgeClientTest {
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
    fun authenticatesTogglesMuteAndHandlesCloseRemote() {
        val connectedLatch = CountDownLatch(1)
        val mutedTrueLatch = CountDownLatch(1)
        val closeSignalLatch = CountDownLatch(1)
        val seenToggle = AtomicBoolean(false)

        server.enqueue(MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                webSocket.send("""{"type":"auth_ok","hostName":"HALL-PC","version":"4.7.0"}""")
                webSocket.send("""{"type":"mute_state","isMuted":false,"routingMode":2,"targetMicName":"Mic/Aux"}""")
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                val obj = JSONObject(text)
                when (obj.optString("type")) {
                    "toggle_mute" -> {
                        seenToggle.set(true)
                        webSocket.send("""{"type":"mute_state","isMuted":true,"routingMode":2,"targetMicName":"Mic/Aux"}""")
                    }
                    "ping" -> {
                        webSocket.send("""{"type":"pong","isMuted":true}""")
                        webSocket.send("""{"type":"close_remote","command":"CloseRemote"}""")
                    }
                }
            }
        }))

        val client = HostBridgeClient(
            httpClient = httpClient,
            wsBaseUrl = "ws://127.0.0.1:${server.port}/ws",
            sessionToken = "tok-abc",
            sessionCode = "K7M-9P2",
            deviceId = "dev-1",
            deviceName = "Board 75",
            callbacks = object : HostBridgeCallbacks {
                override fun onBridgeConnected(hostName: String) {
                    assertEquals("HALL-PC", hostName)
                    connectedLatch.countDown()
                }
                override fun onBridgeAuthFailed(reason: String) = Unit
                override fun onMuteStateChanged(isMuted: Boolean, routingMode: Int, targetMicName: String) {
                    if (isMuted) mutedTrueLatch.countDown()
                }
                override fun onCloseRemoteSignal() {
                    closeSignalLatch.countDown()
                }
                override fun onBridgeDisconnected(reason: String) = Unit
            }
        )

        client.connect()
        assertTrue(connectedLatch.await(3, TimeUnit.SECONDS))
        val recordedUpgrade = server.takeRequest(3, TimeUnit.SECONDS)
        assertTrue(recordedUpgrade?.path?.contains("token=tok-abc") == true)
        assertTrue(client.sendToggleMute("clicker"))
        assertTrue(mutedTrueLatch.await(3, TimeUnit.SECONDS))
        assertTrue(seenToggle.get())
        assertTrue(client.sendPing())
        assertTrue(closeSignalLatch.await(3, TimeUnit.SECONDS))
        client.close()
    }

    @Test
    fun emitsFrameReceivedAndRefreshedSessionTokenCallbacks() {
        val connectedLatch = CountDownLatch(1)
        val refreshedTok = java.util.concurrent.atomic.AtomicReference<String>("")
        val frameCount = java.util.concurrent.atomic.AtomicInteger(0)
        val pongLatch = CountDownLatch(1)

        server.enqueue(MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                webSocket.send("""{"type":"auth_ok","hostName":"HALL-PC","sessionToken":"fresh-tok-777"}""")
                webSocket.send("""{"type":"mute_state","isMuted":false,"routingMode":2,"targetMicName":"Mic/Aux"}""")
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                if (JSONObject(text).optString("type") == "ping") {
                    webSocket.send("""{"type":"pong","isMuted":false}""")
                }
            }
        }))

        val client = HostBridgeClient(
            httpClient = httpClient,
            wsBaseUrl = "ws://127.0.0.1:${server.port}/ws",
            sessionToken = "",
            sessionCode = "K7M-9P2",
            deviceId = "dev-wake-1",
            deviceName = "Board 75",
            callbacks = object : HostBridgeCallbacks {
                override fun onBridgeConnected(hostName: String) {
                    connectedLatch.countDown()
                }
                override fun onBridgeSessionTokenRefreshed(sessionToken: String) {
                    refreshedTok.set(sessionToken)
                }
                override fun onBridgeFrameReceived() {
                    if (frameCount.incrementAndGet() >= 3) {
                        pongLatch.countDown()
                    }
                }
                override fun onBridgeAuthFailed(reason: String) = Unit
                override fun onMuteStateChanged(isMuted: Boolean, routingMode: Int, targetMicName: String) = Unit
                override fun onCloseRemoteSignal() = Unit
                override fun onBridgeDisconnected(reason: String) = Unit
            }
        )

        client.connect()
        assertTrue(connectedLatch.await(3, TimeUnit.SECONDS))
        assertEquals("fresh-tok-777", refreshedTok.get())
        assertTrue(client.sendPing())
        assertTrue(pongLatch.await(3, TimeUnit.SECONDS))
        assertTrue(frameCount.get() >= 3)
        client.closeDead()
    }

    @Test
    fun reportsAuthFailureWhenBridgeRejectsToken() {
        val authFailLatch = CountDownLatch(1)
        server.enqueue(MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                webSocket.send("""{"type":"auth_error","error":"Invalid token"}""")
            }
        }))

        val client = HostBridgeClient(
            httpClient = httpClient,
            wsBaseUrl = "ws://127.0.0.1:${server.port}/ws",
            sessionToken = "bad-token",
            sessionCode = "",
            deviceId = "dev-1",
            deviceName = "Board 75",
            callbacks = object : HostBridgeCallbacks {
                override fun onBridgeConnected(hostName: String) = Unit
                override fun onBridgeAuthFailed(reason: String) {
                    assertTrue(reason.contains("Invalid token"))
                    authFailLatch.countDown()
                }
                override fun onMuteStateChanged(isMuted: Boolean, routingMode: Int, targetMicName: String) = Unit
                override fun onCloseRemoteSignal() = Unit
                override fun onBridgeDisconnected(reason: String) = Unit
            }
        )
        client.connect()
        assertTrue(authFailLatch.await(3, TimeUnit.SECONDS))
        client.close()
    }

    @Test
    fun parsesTelemetryAndSendsDeckActions() {
        val telemetryLatch = CountDownLatch(1)
        val deckLatch = CountDownLatch(3)
        val receivedTelemetry = java.util.concurrent.atomic.AtomicReference<BridgeTelemetryState>()
        val serverActions = java.util.concurrent.CopyOnWriteArrayList<String>()

        server.enqueue(MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                webSocket.send(JSONObject().put("type", "auth_ok").put("hostName", "HOST-PC").toString())
                webSocket.send(
                    JSONObject()
                        .put("type", "mute_state")
                        .put("isMuted", true)
                        .put("routingMode", 2)
                        .put("targetMicName", "Studio Mic")
                        .put("recState", 1)
                        .put("recSeconds", 95)
                        .put("streamDropWarn", true)
                        .put("voiceWhileMuted", true)
                        .toString()
                )
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                val obj = JSONObject(text)
                val type = obj.optString("type")
                if (type == "ppt_next" || type == "ppt_prev" || type == "toggle_record") {
                    serverActions.add(type)
                    deckLatch.countDown()
                }
            }
        }))

        val wsUrl = server.url("/ws").toString().replaceFirst("http://", "ws://")
        val client = HostBridgeClient(
            httpClient = httpClient,
            wsBaseUrl = wsUrl,
            sessionToken = "tok_test_2",
            sessionCode = "",
            deviceId = "and-test-2",
            deviceName = "Board 75",
            callbacks = object : HostBridgeCallbacks {
                override fun onBridgeConnected(hostName: String) = Unit
                override fun onBridgeAuthFailed(reason: String) = Unit
                override fun onMuteStateChanged(isMuted: Boolean, routingMode: Int, targetMicName: String) = Unit
                override fun onTelemetryChanged(telemetry: BridgeTelemetryState) {
                    if (telemetry.recState == 1 && telemetry.recSeconds == 95) {
                        receivedTelemetry.set(telemetry)
                        telemetryLatch.countDown()
                    }
                }
                override fun onCloseRemoteSignal() = Unit
                override fun onBridgeDisconnected(reason: String) = Unit
            }
        )
        client.connect()
        assertTrue(telemetryLatch.await(3, TimeUnit.SECONDS))
        val t = receivedTelemetry.get()
        assertEquals(1, t.recState)
        assertEquals(95, t.recSeconds)
        assertTrue(t.streamDropWarn)
        assertTrue(t.voiceWhileMuted)

        assertTrue(client.sendPptNext())
        assertTrue(client.sendPptPrev())
        assertTrue(client.sendToggleRecord())
        assertTrue(deckLatch.await(3, TimeUnit.SECONDS))
        assertEquals(listOf("ppt_next", "ppt_prev", "toggle_record"), serverActions.toList())
        client.close()
    }
}
