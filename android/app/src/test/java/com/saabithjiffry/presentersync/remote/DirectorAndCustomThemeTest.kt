package com.saabithjiffry.presentersync.remote

import com.saabithjiffry.presentersync.remote.config.DeepLinkParser
import com.saabithjiffry.presentersync.remote.config.RemoteConfig
import com.saabithjiffry.presentersync.remote.input.ClickerDecision
import com.saabithjiffry.presentersync.remote.input.ClickerMuteController
import com.saabithjiffry.presentersync.remote.input.KeyAction
import com.saabithjiffry.presentersync.remote.network.BridgeTelemetryState
import com.saabithjiffry.presentersync.remote.network.ConnectionUiState
import com.saabithjiffry.presentersync.remote.network.HostBridgeCallbacks
import com.saabithjiffry.presentersync.remote.network.HostBridgeClient
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
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

class DirectorAndCustomThemeTest {
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
    fun deepLinkParserExtractsCustomThemeColors() {
        val uri = "presentersync://connect?hosts=192.168.1.25&port=4455&bp=4456&code=K7M-9P2&preset=Custom&clh=0EA5E9&cmh=F43F5E"
        val parsed = DeepLinkParser.parse(uri)
        assertNotNull(parsed)
        assertEquals("Custom", parsed!!.hudColorPreset)
        assertEquals("0EA5E9", parsed.customLiveHex)
        assertEquals("F43F5E", parsed.customMutedHex)
    }

    @Test
    fun clickerPushToTalkUnmutesOnDownAndRemutesOnRelease() {
        var clock = 1000L
        val ctrl = ClickerMuteController { clock }
        val cfg = RemoteConfig(
            enablePointerMute = true,
            enablePushToTalk = true,
            enablePushToMute = false,
            hwMuteHotkey = "KEYCODE_B"
        )
        assertEquals(
            ClickerDecision.CONSUME_PTT_HOLD_UNMUTE,
            ctrl.onKeyEvent("KEYCODE_B", KeyAction.DOWN, false, false, false, 0, cfg)
        )
        clock += 50L
        assertEquals(
            ClickerDecision.CONSUME_PTT_RELEASE_MUTE,
            ctrl.onKeyEvent("KEYCODE_B", KeyAction.UP, false, false, false, 0, cfg)
        )
    }

    @Test
    fun hostBridgeClientParsesDirectorTelemetryNudgeAndSendsCommands() {
        val telemetryLatch = CountDownLatch(1)
        val nudgeLatch = CountDownLatch(1)
        val cmdLatch = CountDownLatch(6)
        val recTel = AtomicReference<BridgeTelemetryState>()
        val recNudge = AtomicReference<Pair<String, String>>()
        val sentPayloads = CopyOnWriteArrayList<JSONObject>()

        server.enqueue(MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                webSocket.send("""{"type":"auth_ok","hostName":"HALL-PC","hostUuid":"uuid-m7"}""")
                webSocket.send(
                    JSONObject()
                        .put("type", "mute_state")
                        .put("isMuted", true)
                        .put("activeScene", "Slides")
                        .put("scenes", JSONArray(listOf("Main", "Slides", "BRB")))
                        .put("isStandby", true)
                        .put("standbyScene", "BRB")
                        .put("timerState", "running")
                        .put("timerRemainingSec", 118)
                        .put("timerPresetSec", 600)
                        .toString()
                )
                webSocket.send("""{"type":"stage_nudge","message":"2 minutes left","sender":"Director","accentHex":"F59E0B"}""")
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                val obj = JSONObject(text)
                val t = obj.optString("type")
                if (t in setOf("switch_scene", "pause_record", "split_record", "toggle_standby", "timer_start", "stage_nudge")) {
                    sentPayloads.add(obj)
                    cmdLatch.countDown()
                }
            }
        }))

        val client = HostBridgeClient(
            httpClient = httpClient,
            wsBaseUrl = "ws://127.0.0.1:${server.port}/ws",
            sessionToken = "tok-m7",
            sessionCode = "K7M-9P2",
            deviceId = "dev-m7",
            deviceName = "Pixel Board",
            callbacks = object : HostBridgeCallbacks {
                override fun onBridgeConnected(hostName: String) = Unit
                override fun onBridgeAuthFailed(reason: String) = Unit
                override fun onMuteStateChanged(isMuted: Boolean, routingMode: Int, targetMicName: String) = Unit
                override fun onTelemetryChanged(telemetry: BridgeTelemetryState) {
                    if (telemetry.isStandby && telemetry.scenes.size == 3) {
                        recTel.set(telemetry)
                        telemetryLatch.countDown()
                    }
                }
                override fun onStageNudgeReceived(message: String, sender: String, accentHex: String) {
                    recNudge.set(sender to message)
                    nudgeLatch.countDown()
                }
                override fun onCloseRemoteSignal() = Unit
                override fun onBridgeDisconnected(reason: String) = Unit
            }
        )

        client.connect()
        assertTrue(telemetryLatch.await(3, TimeUnit.SECONDS))
        assertTrue(nudgeLatch.await(3, TimeUnit.SECONDS))
        val t = recTel.get()
        assertEquals("Slides", t.activeScene)
        assertEquals(listOf("Main", "Slides", "BRB"), t.scenes)
        assertTrue(t.isStandby)
        assertEquals("running", t.timerState)
        assertEquals(118, t.timerRemainingSec)
        assertEquals("Director" to "2 minutes left", recNudge.get())

        assertTrue(client.sendSwitchScene("Main"))
        assertTrue(client.sendPauseRecord())
        assertTrue(client.sendSplitRecord())
        assertTrue(client.sendToggleStandby())
        assertTrue(client.sendTimerCommand("timer_start", 300))
        assertTrue(client.sendStageNudge("Check chat"))
        assertTrue(cmdLatch.await(3, TimeUnit.SECONDS))
        assertEquals("Main", sentPayloads.first { it.getString("type") == "switch_scene" }.getString("sceneName"))
        assertEquals(300, sentPayloads.first { it.getString("type") == "timer_start" }.getInt("durationSec"))
        client.close()
    }

    @Test
    fun relayClientParsesDirectorPacketsAndCountdownFormatting() {
        val dirLatch = CountDownLatch(1)
        val nudgeLatch = CountDownLatch(1)
        val captured = AtomicReference<String>()
        val nudgeCaptured = AtomicReference<String>()
        val code = "PS-M7-UNIT"
        val pw = "pwM7"
        val auth = RelayCrypto.getInternetRelayAuthToken(code, pw)

        val relay = RelayClient(
            httpClient = httpClient,
            pairingCode = code,
            password = pw,
            callbacks = object : RelaySessionCallbacks {
                override fun onRelayConnected() = Unit
                override fun onRelayAuthFailed() = Unit
                override fun onRelayMuteState(muted: Boolean) = Unit
                override fun onRelayDirectorState(
                    isStandby: Boolean,
                    recState: Int,
                    timerState: String,
                    timerRemainingSec: Int,
                    timerPresetSec: Int,
                    activeScene: String
                ) {
                    captured.set("$isStandby|$recState|$timerState|$timerRemainingSec|$activeScene")
                    dirLatch.countDown()
                }
                override fun onStageNudgeReceived(message: String, sender: String, accentHex: String) {
                    nudgeCaptured.set("$sender:$message")
                    nudgeLatch.countDown()
                }
                override fun onCloseRemoteSignal() = Unit
                override fun onRelayDisconnected(reason: String) = Unit
            }
        )

        val dirPkt = RelayCrypto.formatRelayPacket("host", "dir_state", "1;2;running;115;600;BRB", auth)
        val nudgePkt = RelayCrypto.formatRelayPacket("host", "nudge", "Host;Wrap up now", auth)
        relay.handleRawMessage(dirPkt)
        relay.handleRawMessage(nudgePkt)
        assertTrue(dirLatch.await(2, TimeUnit.SECONDS))
        assertTrue(nudgeLatch.await(2, TimeUnit.SECONDS))
        assertEquals("true|2|running|115|BRB", captured.get())
        assertEquals("Host:Wrap up now", nudgeCaptured.get())

        assertEquals("-00:15", ConnectionUiState(timerRemainingSec = -15).formattedCountdown())
        assertEquals("02:00", ConnectionUiState(timerRemainingSec = 120).formattedCountdown())
        relay.close()
    }
}
