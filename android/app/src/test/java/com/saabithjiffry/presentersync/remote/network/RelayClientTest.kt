package com.saabithjiffry.presentersync.remote.network

import okhttp3.OkHttpClient
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

class RelayClientTest {

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
    fun syncsMuteTogglesAndHandlesCloseRemoteOverMockRelay() {
        val code = "PAIR42"
        val pass = "pw99"
        val topic = RelayCrypto.getInternetRelayTopic(code)
        val auth = RelayCrypto.getInternetRelayAuthToken(code, pass)

        val connectedLatch = CountDownLatch(1)
        val syncPostLatch = CountDownLatch(1)
        val togglePostLatch = CountDownLatch(1)
        val setMuteTrueLatch = CountDownLatch(1)
        val muteTrueLatch = CountDownLatch(1)
        val closeRemoteLatch = CountDownLatch(1)
        val wsRef = AtomicReference<WebSocket>()

        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse {
                val path = request.path.orEmpty()
                if (path == "/$topic/ws") {
                    return MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
                        override fun onOpen(webSocket: WebSocket, response: Response) {
                            wsRef.set(webSocket)
                            webSocket.send("""{"event":"open"}""")
                        }
                    })
                }
                if (path == "/$topic" && request.method == "POST") {
                    val body = request.body.readUtf8()
                    val pkt = RelayCrypto.parseRelayPacket(body)
                    if (pkt != null && pkt.auth == auth) {
                        if (pkt.cmd == "sync_req") {
                            syncPostLatch.countDown()
                            val reply = RelayCrypto.formatRelayPacket("host", "state", "1", auth)
                            wsRef.get()?.send("""{"event":"message","message":"$reply"}""")
                        } else if (pkt.cmd == "toggle_mute") {
                            togglePostLatch.countDown()
                            val closePkt = RelayCrypto.formatRelayPacket("host", "close_remote", "1", auth)
                            wsRef.get()?.send("""{"event":"message","message":"$closePkt"}""")
                        } else if (pkt.cmd == "set_mute" && pkt.data == "1") {
                            setMuteTrueLatch.countDown()
                        }
                    }
                    return MockResponse().setResponseCode(200).setBody("""{"id":"ok"}""")
                }
                return MockResponse().setResponseCode(404)
            }
        }

        val baseHttp = "http://${server.hostName}:${server.port}"
        val baseWs = "ws://${server.hostName}:${server.port}"

        val client = RelayClient(
            httpClient = httpClient,
            pairingCode = code,
            password = pass,
            httpBaseUrl = baseHttp,
            wsBaseUrl = baseWs,
            callbacks = object : RelaySessionCallbacks {
                override fun onRelayConnected() { connectedLatch.countDown() }
                override fun onRelayAuthFailed() {}
                override fun onRelayMuteState(muted: Boolean) {
                    if (muted) muteTrueLatch.countDown()
                }
                override fun onCloseRemoteSignal() { closeRemoteLatch.countDown() }
                override fun onRelayDisconnected(reason: String) {}
            }
        )
        client.connect()

        assertTrue(connectedLatch.await(3, TimeUnit.SECONDS))
        assertTrue(syncPostLatch.await(3, TimeUnit.SECONDS))
        assertTrue(muteTrueLatch.await(3, TimeUnit.SECONDS))
        assertTrue(client.sendToggleMute())
        assertTrue(togglePostLatch.await(3, TimeUnit.SECONDS))
        assertTrue(client.sendSetMute(true))
        assertTrue(setMuteTrueLatch.await(3, TimeUnit.SECONDS))
        assertTrue(closeRemoteLatch.await(3, TimeUnit.SECONDS))
        wsRef.get()?.close(1000, "test done")
        client.close()
    }

    @Test
    fun rejectsBadAuthTokenAndEmitsAuthFailed() {
        val code = "PAIR42"
        val authFailLatch = CountDownLatch(1)
        val client = RelayClient(
            httpClient = httpClient,
            pairingCode = code,
            password = "right",
            httpBaseUrl = "http://127.0.0.1:1",
            wsBaseUrl = "ws://127.0.0.1:1",
            callbacks = object : RelaySessionCallbacks {
                override fun onRelayConnected() {}
                override fun onRelayAuthFailed() { authFailLatch.countDown() }
                override fun onRelayMuteState(muted: Boolean) {}
                override fun onCloseRemoteSignal() {}
                override fun onRelayDisconnected(reason: String) {}
            }
        )

        val badPacket = RelayCrypto.formatRelayPacket("host", "state", "0", "WRONGTOKEN")
        client.handleRawMessage("""{"event":"message","message":"$badPacket"}""")
        assertTrue(authFailLatch.await(1, TimeUnit.SECONDS))
    }
}
