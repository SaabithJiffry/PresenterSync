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
import org.junit.Assert.assertFalse
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

        val seenAuth = java.util.concurrent.atomic.AtomicReference<JSONObject>()
        server.enqueue(MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
            override fun onMessage(webSocket: WebSocket, text: String) {
                val obj = JSONObject(text)
                when (obj.optString("type")) {
                    "auth" -> {
                        seenAuth.set(obj)
                        webSocket.send("""{"type":"auth_ok","protocolVersion":2,"hostBootId":"boot-1","stateSeq":5,"hostName":"HALL-PC","version":"9.2.0"}""")
                        webSocket.send("""{"type":"mute_state","stateSeq":6,"isMuted":false,"routingMode":2,"targetMicName":"Mic/Aux"}""")
                    }
                    "toggle_mute" -> {
                        seenToggle.set(true)
                        // First send a stale stateSeq=4 packet (should be ignored) then fresh seq=7
                        webSocket.send("""{"type":"mute_state","stateSeq":4,"isMuted":false,"routingMode":2,"targetMicName":"Mic/Aux"}""")
                        webSocket.send("""{"type":"mute_state","stateSeq":7,"isMuted":true,"routingMode":2,"targetMicName":"Mic/Aux"}""")
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
        assertFalse(recordedUpgrade?.path?.contains("token=") == true)
        assertFalse(recordedUpgrade?.path?.contains("code=") == true)
        assertEquals(2, seenAuth.get()?.optInt("protocolVersion"))
        assertEquals("tok-abc", seenAuth.get()?.optString("token"))
        assertEquals("K7M9P2", seenAuth.get()?.optString("code"))
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

    @Test
    fun emitsCmdIdForExplicitSettersAndDeliversCommandNack() {
        val connectedLatch = CountDownLatch(1)
        val nackLatch = CountDownLatch(1)
        val commandsLatch = CountDownLatch(2)
        val seenPayloads = java.util.concurrent.CopyOnWriteArrayList<JSONObject>()
        val nackInfo = java.util.concurrent.atomic.AtomicReference<Triple<String, String, String>>()

        server.enqueue(MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
            override fun onMessage(webSocket: WebSocket, text: String) {
                val obj = JSONObject(text)
                when (obj.optString("type")) {
                    "auth" -> webSocket.send("""{"type":"auth_ok","protocolVersion":2,"hostBootId":"b2","stateSeq":1,"hostName":"HALL-PC"}""")
                    "set_record" -> {
                        seenPayloads.add(obj)
                        commandsLatch.countDown()
                        webSocket.send("""{"type":"nack","action":"set_record","code":"confirm_required","reason":"Confirm stop","cmdId":"${obj.optString("cmdId")}"}""")
                    }
                    "set_standby" -> {
                        seenPayloads.add(obj)
                        commandsLatch.countDown()
                    }
                }
            }
        }))

        val client = HostBridgeClient(
            httpClient = httpClient,
            wsBaseUrl = "ws://127.0.0.1:${server.port}/ws",
            sessionToken = "tok-v2",
            sessionCode = "",
            deviceId = "dev-v2",
            deviceName = "Board",
            callbacks = object : HostBridgeCallbacks {
                override fun onBridgeConnected(hostName: String) {
                    connectedLatch.countDown()
                }
                override fun onBridgeAuthFailed(reason: String) = Unit
                override fun onMuteStateChanged(isMuted: Boolean, routingMode: Int, targetMicName: String) = Unit
                override fun onCommandNack(action: String, code: String, reason: String, cmdId: String) {
                    nackInfo.set(Triple(action, code, cmdId))
                    nackLatch.countDown()
                }
                override fun onCloseRemoteSignal() = Unit
                override fun onBridgeDisconnected(reason: String) = Unit
            }
        )

        client.connect()
        assertTrue(connectedLatch.await(3, TimeUnit.SECONDS))
        assertTrue(client.sendSetRecord(recording = false, confirmed = false))
        assertTrue(client.sendSetStandby(isStandby = true))
        assertTrue(commandsLatch.await(3, TimeUnit.SECONDS))
        assertTrue(nackLatch.await(3, TimeUnit.SECONDS))

        val recObj = seenPayloads.first { it.getString("type") == "set_record" }
        val brbObj = seenPayloads.first { it.getString("type") == "set_standby" }
        assertTrue(recObj.optString("cmdId").startsWith("dev-v2-"))
        assertFalse(recObj.getBoolean("confirmed"))
        assertTrue(brbObj.getBoolean("isStandby"))
        assertEquals("set_record", nackInfo.get().first)
        assertEquals("confirm_required", nackInfo.get().second)
        assertEquals(recObj.getString("cmdId"), nackInfo.get().third)
        client.close()
    }

    @Test
    fun enforcesTopLevelAllowDirectObsFallbackWhenObsFallbackOmittedAndPropagatesResyncRole() {
        val connectedLatch = CountDownLatch(1)
        val fallbackRevokedLatch = CountDownLatch(2)
        val tallyRoleLatch = CountDownLatch(1)
        val observedRoles = java.util.concurrent.CopyOnWriteArrayList<String>()
        val observedFallback = java.util.concurrent.CopyOnWriteArrayList<Pair<String, Boolean>>()

        server.enqueue(MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
            override fun onMessage(webSocket: WebSocket, text: String) {
                val obj = JSONObject(text)
                if (obj.optString("type") == "auth") {
                    webSocket.send(
                        """{"type":"auth_ok","protocolVersion":2,"hostBootId":"b3","stateSeq":1,"hostName":"HALL-PC","role":"Presenter","allowDirectObsFallback":false}"""
                    )
                    webSocket.send(
                        """{"type":"obs_fallback_update","protocolVersion":2,"allowDirectObsFallback":false}"""
                    )
                    webSocket.send(
                        """{"type":"sync_resync","reason":"role_change","stateSeq":2,"role":"Tally-Only","isMuted":false}"""
                    )
                }
            }
        }))

        val client = HostBridgeClient(
            httpClient = httpClient,
            wsBaseUrl = "ws://127.0.0.1:${server.port}/ws",
            sessionToken = "tok-v3",
            sessionCode = "",
            deviceId = "dev-v3",
            deviceName = "Board",
            callbacks = object : HostBridgeCallbacks {
                override fun onBridgeConnected(hostName: String) {
                    connectedLatch.countDown()
                }
                override fun onBridgeAuthFailed(reason: String) = Unit
                override fun onBridgeRoleAssigned(role: String) {
                    observedRoles.add(role)
                    if (role == "Tally-Only") tallyRoleLatch.countDown()
                }
                override fun onObsFallbackUpdated(port: Int, targetMic: String, password: String, directObsAllowed: Boolean) {
                    observedFallback.add(password to directObsAllowed)
                    if (password.isEmpty() && !directObsAllowed) {
                        fallbackRevokedLatch.countDown()
                    }
                }
                override fun onMuteStateChanged(isMuted: Boolean, routingMode: Int, targetMicName: String) = Unit
                override fun onCloseRemoteSignal() = Unit
                override fun onBridgeDisconnected(reason: String) = Unit
            }
        )

        client.connect()
        assertTrue(connectedLatch.await(3, TimeUnit.SECONDS))
        assertTrue(fallbackRevokedLatch.await(3, TimeUnit.SECONDS))
        assertTrue(tallyRoleLatch.await(3, TimeUnit.SECONDS))
        assertTrue(observedRoles.contains("Presenter"))
        assertTrue(observedRoles.contains("Tally-Only"))
        assertEquals(2, observedFallback.count { it.first == "" && !it.second })
        client.close()
    }
}
