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
}
