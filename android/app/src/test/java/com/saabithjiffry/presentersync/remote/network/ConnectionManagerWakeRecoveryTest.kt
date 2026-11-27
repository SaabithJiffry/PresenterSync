package com.saabithjiffry.presentersync.remote.network

import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import com.saabithjiffry.presentersync.remote.config.NetworkMode
import com.saabithjiffry.presentersync.remote.config.RemoteConfigStore
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.net.ServerSocket
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

class ConnectionManagerWakeRecoveryTest {
    private lateinit var server: MockWebServer
    private lateinit var manager: ConnectionManager
    private lateinit var configStore: RemoteConfigStore
    private lateinit var clockMs: AtomicLong
    private var closedObsPort: Int = 0

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
        closedObsPort = ServerSocket(0).use { it.localPort }
        clockMs = AtomicLong(10_000L)
        val fakeContext = InMemoryPrefsContext()
        configStore = RemoteConfigStore(fakeContext)
        manager = ConnectionManager(
            context = fakeContext,
            configStore = configStore,
            clockMs = { clockMs.get() }
        )
        manager.discoverPortOverride = 0
    }

    @After
    fun tearDown() {
        manager.stop()
        runCatching { server.shutdown() }
    }

    @Test
    fun tracksLastRxAtMsOnFramesAndPong() {
        val pongSeenLatch = CountDownLatch(1)
        val connectedLatch = CountDownLatch(1)
        server.enqueue(MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                webSocket.send("""{"type":"auth_ok","hostName":"ROOM-101"}""")
                webSocket.send("""{"type":"mute_state","isMuted":false,"routingMode":2,"targetMicName":"Mic/Aux"}""")
                connectedLatch.countDown()
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                if (JSONObject(text).optString("type") == "ping") {
                    clockMs.set(15_000L)
                    webSocket.send("""{"type":"pong","isMuted":false}""")
                    pongSeenLatch.countDown()
                }
            }
        }))

        configStore.update {
            it.copy(
                networkMode = NetworkMode.LAN,
                hostAddress = "127.0.0.1",
                hostPort = closedObsPort,
                bridgePort = server.port,
                sessionPairingCode = "K7M-9P2",
                sessionToken = "tok-ok",
                pairedHostUuid = "",
                enableRelayFallback = false
            )
        }
        manager.pongTimeoutMs = 300L
        manager.start()

        assertTrue(awaitCondition(4_000L) { manager.uiState.value.connected })
        assertTrue(connectedLatch.await(2, TimeUnit.SECONDS))
        assertEquals(10_000L, manager.lastRxAtMs)

        // Brief wake <= 25s sends ping and updates lastRxAtMs when pong arrives without dropping socket
        clockMs.set(14_500L)
        manager.onScreenWakeOrNetworkChanged()
        assertTrue(pongSeenLatch.await(3, TimeUnit.SECONDS))
        assertTrue(awaitCondition(2_000L) { manager.lastRxAtMs == 15_000L })

        Thread.sleep(450L)
        assertTrue("Healthy pong should keep connection alive", manager.uiState.value.connected)
        assertEquals(1, server.requestCount)
    }

    @Test
    fun pongWatchdogMarksDeadSocketAndReconnectsOnTimeout() {
        val pingReceived = CountDownLatch(1)
        val reconnectedLatch = CountDownLatch(1)

        server.enqueue(MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                webSocket.send("""{"type":"auth_ok","hostName":"STALE-PC"}""")
                webSocket.send("""{"type":"mute_state","isMuted":false,"routingMode":2,"targetMicName":"Mic/Aux"}""")
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                if (JSONObject(text).optString("type") == "ping") {
                    // Deliberately drop pong to simulate half-open zombie socket
                    pingReceived.countDown()
                }
            }
        }))
        server.enqueue(MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                webSocket.send("""{"type":"auth_ok","hostName":"RECOVERED-PC"}""")
                webSocket.send("""{"type":"mute_state","isMuted":true,"routingMode":2,"targetMicName":"Mic/Aux"}""")
                reconnectedLatch.countDown()
            }
        }))

        configStore.update {
            it.copy(
                networkMode = NetworkMode.LAN,
                hostAddress = "127.0.0.1",
                hostPort = closedObsPort,
                bridgePort = server.port,
                sessionPairingCode = "K7M-9P2",
                sessionToken = "tok-ok",
                pairedHostUuid = "",
                enableRelayFallback = false
            )
        }
        manager.pongTimeoutMs = 180L
        manager.start()

        assertTrue(awaitCondition(4_000L) { manager.uiState.value.activeHost.contains("STALE-PC") })

        clockMs.set(12_000L)
        manager.verifyOrReconnect()
        assertTrue(pingReceived.await(3, TimeUnit.SECONDS))
        assertTrue(reconnectedLatch.await(12, TimeUnit.SECONDS))
        assertTrue(
            awaitCondition(5_000L) {
                manager.uiState.value.connected && manager.uiState.value.activeHost.contains("RECOVERED-PC")
            }
        )
    }

    @Test
    fun screenWakeOver25SecondsStaleForcesImmediateReconnectWithoutPing() {
        val firstSocketMsgs = CopyOnWriteArrayList<String>()
        val reconnectedLatch = CountDownLatch(1)

        server.enqueue(MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                webSocket.send("""{"type":"auth_ok","hostName":"PRE-SLEEP-PC"}""")
                webSocket.send("""{"type":"mute_state","isMuted":false,"routingMode":2,"targetMicName":"Mic/Aux"}""")
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                firstSocketMsgs.add(text)
            }
        }))
        server.enqueue(MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                webSocket.send("""{"type":"auth_ok","hostName":"WAKE-FRESH-PC"}""")
                webSocket.send("""{"type":"mute_state","isMuted":false,"routingMode":2,"targetMicName":"Mic/Aux"}""")
                reconnectedLatch.countDown()
            }
        }))

        configStore.update {
            it.copy(
                networkMode = NetworkMode.LAN,
                hostAddress = "127.0.0.1",
                hostPort = closedObsPort,
                bridgePort = server.port,
                sessionPairingCode = "K7M-9P2",
                sessionToken = "tok-ok",
                pairedHostUuid = "",
                enableRelayFallback = false
            )
        }
        manager.start()
        assertTrue(awaitCondition(4_000L) { manager.uiState.value.connected && manager.lastRxAtMs == 10_000L })

        // Simulate > 25,000ms Smart Board sleep
        clockMs.set(10_000L + ConnectionManager.WAKE_STALENESS_MS + 1_000L)
        manager.onScreenWakeOrNetworkChanged()

        assertTrue(reconnectedLatch.await(4, TimeUnit.SECONDS))
        assertTrue(
            awaitCondition(3_000L) {
                manager.uiState.value.connected && manager.uiState.value.activeHost.contains("WAKE-FRESH-PC")
            }
        )
        assertTrue(
            "Stale wake > 25s must force reconnect instead of sending ping",
            firstSocketMsgs.none { JSONObject(it).optString("type") == "ping" }
        )
    }

    @Test
    fun authErrorWithStaleTokenRetriesAutomaticallyWithSessionPairingCode() {
        val retryConnected = CountDownLatch(1)

        val firstAuth = java.util.concurrent.atomic.AtomicReference<JSONObject>()
        val secondAuth = java.util.concurrent.atomic.AtomicReference<JSONObject>()
        server.enqueue(MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
            override fun onMessage(webSocket: WebSocket, text: String) {
                val obj = JSONObject(text)
                if (obj.optString("type") == "auth") {
                    firstAuth.set(obj)
                    webSocket.send("""{"type":"auth_error","error":"Unauthorized"}""")
                    webSocket.close(1000, "stale")
                }
            }
        }))
        server.enqueue(MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
            override fun onMessage(webSocket: WebSocket, text: String) {
                val obj = JSONObject(text)
                if (obj.optString("type") == "auth") {
                    secondAuth.set(obj)
                    webSocket.send("""{"type":"auth_ok","protocolVersion":2,"hostBootId":"boot-1","stateSeq":1,"hostName":"REBOUND-PC","sessionToken":"fresh-tok-888"}""")
                    webSocket.send("""{"type":"mute_state","stateSeq":2,"isMuted":true,"routingMode":2,"targetMicName":"Mic/Aux"}""")
                    retryConnected.countDown()
                }
            }
        }))

        configStore.update {
            it.copy(
                networkMode = NetworkMode.LAN,
                hostAddress = "127.0.0.1",
                hostPort = closedObsPort,
                bridgePort = server.port,
                sessionPairingCode = "K7M-9P2",
                sessionToken = "stale-tok-123",
                pairedHostUuid = "",
                enableRelayFallback = false
            )
        }
        manager.start()

        assertTrue(retryConnected.await(5, TimeUnit.SECONDS))
        assertTrue(
            awaitCondition(3_000L) {
                manager.uiState.value.connected &&
                    manager.uiState.value.connStatus == ConnStatus.CONNECTED &&
                    manager.uiState.value.activeHost.contains("REBOUND-PC")
            }
        )
        assertEquals("fresh-tok-888", configStore.current.sessionToken)

        val firstReq = server.takeRequest(2, TimeUnit.SECONDS)
        val secondReq = server.takeRequest(2, TimeUnit.SECONDS)
        assertFalse(firstReq?.path?.contains("token=") == true)
        assertFalse(firstReq?.path?.contains("code=") == true)
        assertFalse(secondReq?.path?.contains("token=") == true)
        assertFalse(secondReq?.path?.contains("code=") == true)
        assertEquals("stale-tok-123", firstAuth.get()?.optString("token"))
        assertEquals("", secondAuth.get()?.optString("token"))
        assertEquals("K7M9P2", secondAuth.get()?.optString("code"))
    }

    @Test
    fun explicitHostRevocationDoesNotAutoRetryWithPairingCode() {
        server.enqueue(MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                webSocket.send("""{"type":"auth_error","error":"Device unpaired by host"}""")
                webSocket.close(1000, "unpaired")
            }
        }))

        configStore.update {
            it.copy(
                networkMode = NetworkMode.LAN,
                hostAddress = "127.0.0.1",
                hostPort = closedObsPort,
                bridgePort = server.port,
                obsPassword = "",
                sessionPairingCode = "K7M-9P2",
                sessionToken = "tok-unpaired",
                pairedHostUuid = "",
                enableRelayFallback = false
            )
        }
        assertFalse(manager.shouldRetryBridgeAuthWithPairingCode(configStore.current, "Device unpaired by host"))
        assertTrue(manager.shouldRetryBridgeAuthWithPairingCode(configStore.current, "Unauthorized"))

        manager.start()
        assertTrue(awaitCondition(4_000L) { manager.uiState.value.connStatus == ConnStatus.AUTH_FAILED })
        assertEquals(1, server.requestCount)
    }

    private fun awaitCondition(timeoutMs: Long, pred: () -> Boolean): Boolean {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            if (pred()) return true
            Thread.sleep(20)
        }
        return pred()
    }

    private class InMemoryPrefsContext : ContextWrapper(null) {
        private val prefs = InMemorySharedPreferences()
        override fun getApplicationContext(): Context = this
        override fun getSharedPreferences(name: String?, mode: Int): SharedPreferences = prefs
        override fun getSystemService(name: String): Any? = null
    }

    private class InMemorySharedPreferences : SharedPreferences {
        private val data = LinkedHashMap<String, Any?>()
        override fun getAll(): MutableMap<String, *> = HashMap(data)
        override fun getString(key: String?, defValue: String?): String? = (data[key] as? String) ?: defValue
        override fun getStringSet(key: String?, defValues: MutableSet<String>?): MutableSet<String>? = defValues
        override fun getInt(key: String?, defValue: Int): Int = (data[key] as? Int) ?: defValue
        override fun getLong(key: String?, defValue: Long): Long = (data[key] as? Long) ?: defValue
        override fun getFloat(key: String?, defValue: Float): Float = (data[key] as? Float) ?: defValue
        override fun getBoolean(key: String?, defValue: Boolean): Boolean = (data[key] as? Boolean) ?: defValue
        override fun contains(key: String?): Boolean = data.containsKey(key)
        override fun edit(): SharedPreferences.Editor = object : SharedPreferences.Editor {
            private val pending = LinkedHashMap<String, Any?>()
            private var clearAll = false
            override fun putString(key: String?, value: String?) = apply { if (key != null) pending[key] = value }
            override fun putStringSet(key: String?, values: MutableSet<String>?) = apply { }
            override fun putInt(key: String?, value: Int) = apply { if (key != null) pending[key] = value }
            override fun putLong(key: String?, value: Long) = apply { if (key != null) pending[key] = value }
            override fun putFloat(key: String?, value: Float) = apply { if (key != null) pending[key] = value }
            override fun putBoolean(key: String?, value: Boolean) = apply { if (key != null) pending[key] = value }
            override fun remove(key: String?) = apply { if (key != null) pending[key] = null }
            override fun clear() = apply { clearAll = true }
            override fun commit(): Boolean {
                apply()
                return true
            }
            override fun apply() {
                if (clearAll) data.clear()
                pending.forEach { (k, v) -> if (v == null) data.remove(k) else data[k] = v }
            }
        }
        override fun registerOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener?) = Unit
        override fun unregisterOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener?) = Unit
    }
}
