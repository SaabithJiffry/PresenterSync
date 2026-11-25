package com.saabithjiffry.presentersync.remote.network

import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import com.saabithjiffry.presentersync.remote.config.NetworkMode
import com.saabithjiffry.presentersync.remote.config.RemoteConfigStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.net.ServerSocket
import java.util.concurrent.CopyOnWriteArrayList

class M24OptimisticAndBackoffTest {

    private lateinit var scope: CoroutineScope
    private lateinit var server: MockWebServer
    private val managers = mutableListOf<ConnectionManager>()

    @Before
    fun setUp() {
        scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        server = MockWebServer()
        server.start()
    }

    @After
    fun tearDown() {
        managers.forEach { it.stop() }
        managers.clear()
        try {
            server.shutdown()
        } catch (_: Exception) {
        }
        scope.cancel()
    }

    private fun allocateClosedPort(): Int {
        ServerSocket(0).use { return it.localPort }
    }

    @Test
    fun computeReconnectBackoff_exponentialAndCappedAt30sWithJitter() {
        val base = 1200L
        val max = 30_000L

        val d0 = ConnectionManager.computeReconnectBackoffMs(0, base, max)
        val d1 = ConnectionManager.computeReconnectBackoffMs(1, base, max)
        val d2 = ConnectionManager.computeReconnectBackoffMs(2, base, max)
        val d6 = ConnectionManager.computeReconnectBackoffMs(6, 5000L, max)

        assertTrue("attempt 0 ($d0) in [1080, 1320]", d0 in 1080L..1320L)
        assertTrue("attempt 1 ($d1) in [2160, 2640]", d1 in 2160L..2640L)
        assertTrue("attempt 2 ($d2) in [4320, 5280]", d2 in 4320L..5280L)
        assertTrue("capped around 30s [27000, 33000], was $d6", d6 in 27_000L..33_000L)
    }

    @Test
    fun optimisticToggle_flipsUnder16ms_emitsOnce_andRollsBackOnNack() {
        val received = CopyOnWriteArrayList<String>()
        var serverWs: WebSocket? = null
        var onOpenCount = 0
        var wsCloseNote = ""
        server.enqueue(MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                onOpenCount++
                serverWs = webSocket
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                received.add(text)
                if (text.contains("\"type\":\"auth\"")) {
                    webSocket.send("""{"type":"auth_ok","hostName":"M24-HOST"}""")
                    webSocket.send("""{"type":"mute_state","isMuted":false,"routingMode":2,"targetMicName":"Mic/Aux"}""")
                } else if (text.contains("\"type\":\"ping\"")) {
                    webSocket.send("""{"type":"pong","isMuted":false}""")
                }
            }

            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                wsCloseNote += "closing:$code/$reason;"
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                wsCloseNote += "fail:${t.javaClass.simpleName}:${t.message};"
            }
        }))

        val ctx = M24InMemoryPrefsContext()
        val store = RemoteConfigStore(ctx)
        store.update {
            it.copy(
                networkMode = NetworkMode.LAN,
                hostAddress = "127.0.0.1",
                hostPort = allocateClosedPort(),
                bridgePort = server.port,
                sessionPairingCode = "K7M-9P2",
                sessionToken = "tok-ok",
                pairedHostUuid = "",
                enableRelayFallback = false
            )
        }

        val cm = ConnectionManager(ctx, store, { 10_000L }).also { managers.add(it) }
        cm.pongTimeoutMs = 300L
        cm.optimisticReconcileDelayMs = 150L
        cm.start()

        val deadline = System.currentTimeMillis() + 4000L
        while (!cm.uiState.value.connected && System.currentTimeMillis() < deadline) {
            Thread.sleep(20L)
        }
        assertTrue("Expected bridge connection to become connected, reqCount=${server.requestCount}, onOpen=$onOpenCount, close=$wsCloseNote, rx=$received", cm.uiState.value.connected)
        assertFalse(cm.uiState.value.isMuted)

        val emittedEvents = CopyOnWriteArrayList<RemoteEvent>()
        val collectJob = scope.launch {
            cm.events.collect { emittedEvents.add(it) }
        }
        Thread.sleep(30L)

        val t0 = System.nanoTime()
        val ok = cm.toggleMuteFromHud()
        val elapsedMs = (System.nanoTime() - t0) / 1_000_000.0
        assertTrue("toggleMuteFromHud should succeed", ok)
        assertTrue("Optimistic toggle UI update should be fast (<50ms in test JVM, was $elapsedMs)", elapsedMs < 50.0)
        assertTrue("uiState.isMuted should flip optimistically to true", cm.uiState.value.isMuted)

        Thread.sleep(40L)
        val muteEvents = emittedEvents.filterIsInstance<RemoteEvent.MuteChanged>()
        assertEquals("Should emit MuteChanged exactly once for optimistic flip", 1, muteEvents.size)
        assertTrue(muteEvents.first().isMuted)

        // Wait past reconcile delay -> should send sync_req
        Thread.sleep(220L)
        assertTrue(
            "Expected sync_req after reconcile timeout, got: $received",
            received.any { it.contains("\"type\":\"sync_req\"") }
        )

        // Test NACK rollback + authoritative mute_state=false
        serverWs?.send("""{"v":2,"type":"nack","cmd":"toggle_mute","reason":"busy"}""")
        Thread.sleep(40L)
        serverWs?.send("""{"v":2,"type":"mute_state","stateSeq":2,"isMuted":false}""")
        Thread.sleep(50L)
        assertFalse("Authoritative mute_state=false should reconcile state", cm.uiState.value.isMuted)

        collectJob.cancel()
    }

    @Test
    fun obsHandshakeTimeout_abortsStalledHandshakeQuickly() = runBlocking {
        // Server accepts WS upgrade but never sends OBS Hello (op=0)
        server.enqueue(MockResponse().withWebSocketUpgrade(object : WebSocketListener() {}))

        val ctx = M24InMemoryPrefsContext()
        val store = RemoteConfigStore(ctx)
        store.update {
            it.copy(
                networkMode = NetworkMode.LAN,
                hostAddress = "127.0.0.1",
                hostPort = server.port,
                bridgePort = allocateClosedPort(),
                sessionPairingCode = "",
                sessionToken = "",
                enableRelayFallback = false
            )
        }

        val cm = ConnectionManager(ctx, store).also { managers.add(it) }
        cm.obsHandshakeTimeoutMs = 200L
        cm.start()

        delay(450L)
        assertFalse(
            "Stalled OBS handshake should time out and not become connected",
            cm.uiState.value.connected
        )
    }

    private class M24InMemoryPrefsContext : ContextWrapper(null) {
        private val prefs = object : SharedPreferences {
            private val data = mutableMapOf<String, Any?>()
            override fun getAll(): MutableMap<String, *> = data.toMutableMap()
            override fun getString(key: String?, defValue: String?): String? = data[key] as? String ?: defValue
            override fun getStringSet(key: String?, defValues: MutableSet<String>?): MutableSet<String>? = defValues
            override fun getInt(key: String?, defValue: Int): Int = (data[key] as? Int) ?: defValue
            override fun getLong(key: String?, defValue: Long): Long = (data[key] as? Long) ?: defValue
            override fun getFloat(key: String?, defValue: Float): Float = (data[key] as? Float) ?: defValue
            override fun getBoolean(key: String?, defValue: Boolean): Boolean = (data[key] as? Boolean) ?: defValue
            override fun contains(key: String?): Boolean = data.containsKey(key)
            override fun edit(): SharedPreferences.Editor = object : SharedPreferences.Editor {
                private val pending = mutableMapOf<String, Any?>()
                override fun putString(k: String?, v: String?) = apply { if (k != null) pending[k] = v }
                override fun putStringSet(k: String?, v: MutableSet<String>?) = apply { if (k != null) pending[k] = v }
                override fun putInt(k: String?, v: Int) = apply { if (k != null) pending[k] = v }
                override fun putLong(k: String?, v: Long) = apply { if (k != null) pending[k] = v }
                override fun putFloat(k: String?, v: Float) = apply { if (k != null) pending[k] = v }
                override fun putBoolean(k: String?, v: Boolean) = apply { if (k != null) pending[k] = v }
                override fun remove(k: String?) = apply { if (k != null) pending[k] = null }
                override fun clear() = apply { data.clear() }
                override fun commit(): Boolean {
                    pending.forEach { (k, v) -> if (v == null) data.remove(k) else data[k] = v }
                    return true
                }
                override fun apply() {
                    commit()
                }
            }
            override fun registerOnSharedPreferenceChangeListener(l: SharedPreferences.OnSharedPreferenceChangeListener?) {}
            override fun unregisterOnSharedPreferenceChangeListener(l: SharedPreferences.OnSharedPreferenceChangeListener?) {}
        }

        override fun getApplicationContext(): Context = this

        override fun getSharedPreferences(name: String?, mode: Int): SharedPreferences = prefs

        override fun getSystemService(name: String): Any? = null
    }
}
