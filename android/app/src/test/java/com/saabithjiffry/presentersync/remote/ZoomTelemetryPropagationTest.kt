package com.saabithjiffry.presentersync.remote

import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import com.saabithjiffry.presentersync.remote.config.RemoteConfigStore
import com.saabithjiffry.presentersync.remote.network.ConnectionManager
import com.saabithjiffry.presentersync.remote.network.ConnectionUiState
import com.saabithjiffry.presentersync.remote.network.HostBridgeCallbacks
import com.saabithjiffry.presentersync.remote.network.HostBridgeClient
import com.saabithjiffry.presentersync.remote.network.RelayCrypto
import com.saabithjiffry.presentersync.remote.ui.overlay.MicPillMetricsCalculator
import okhttp3.OkHttpClient
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

class ZoomTelemetryPropagationTest {

    @Test
    fun hostBridgeClient_parsesUnreadChatCountAndRecSourceTag() {
        val server = MockWebServer()
        server.start()
        val client = OkHttpClient.Builder().build()
        val latch = CountDownLatch(1)
        val seenChat = AtomicInteger(0)
        val seenSrc = AtomicReference("")

        try {
            server.enqueue(MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
                override fun onMessage(webSocket: WebSocket, text: String) {
                    val obj = JSONObject(text)
                    if (obj.optString("type") == "auth") {
                        webSocket.send("""{"type":"auth_ok","protocolVersion":2,"hostBootId":"boot-z","stateSeq":1,"hostName":"PC","version":"10.2.0"}""")
                        webSocket.send("""{"type":"mute_state","stateSeq":2,"isMuted":false,"recState":1,"recSeconds":42,"recSourceTag":"conf","unreadChatCount":6,"studioModeActive":true,"previewSceneName":"Slides"}""")
                    }
                }
            }))
            val wsUrl = server.url("/ws").toString().replaceFirst("http://", "ws://")
            val bridge = HostBridgeClient(
                httpClient = client,
                wsBaseUrl = wsUrl,
                sessionToken = "tok",
                sessionCode = "123-456",
                deviceId = "d1",
                deviceName = "Android",
                callbacks = object : HostBridgeCallbacks {
                    override fun onBridgeConnected(hostName: String) {}
                    override fun onBridgeAuthFailed(reason: String) {}
                    override fun onMuteStateChanged(isMuted: Boolean, routingMode: Int, targetMicName: String) {}
                    override fun onTelemetryChanged(telemetry: com.saabithjiffry.presentersync.remote.network.BridgeTelemetryState) {
                        seenChat.set(telemetry.unreadChatCount)
                        seenSrc.set(telemetry.recSourceTag)
                        if (telemetry.unreadChatCount == 6 && telemetry.recSourceTag == "conf") {
                            latch.countDown()
                        }
                    }
                    override fun onCloseRemoteSignal() {}
                    override fun onBridgeDisconnected(reason: String) {}
                }
            )
            bridge.connect()
            assertTrue(latch.await(3, TimeUnit.SECONDS))
            assertEquals(6, seenChat.get())
            assertEquals("conf", seenSrc.get())
            bridge.close()
        } finally {
            client.dispatcher.executorService.shutdown()
            client.connectionPool.evictAll()
            runCatching { server.shutdown() }
        }
    }

    @Test
    fun relayCrypto_roundTripsUnreadChatCountAndRecSourceTag() {
        val code = "PS-M2RM-1020"
        val nowSec = System.currentTimeMillis() / 1000L
        val plain = JSONObject()
            .put("v", 2)
            .put("src", "host")
            .put("cmd", "state")
            .put("data", "0")
            .put("seq", 10L)
            .put("ts", nowSec)
            .put("sid", "s1")
            .put("auth", RelayCrypto.getInternetRelayAuthToken(code, ""))
            .put("recState", 1)
            .put("recSeconds", 15)
            .put("recSourceTag", "obs")
            .put("unreadChatCount", 4)
            .toString()
        val encrypted = RelayCrypto.encryptRelayPayload(plain, code, "")
        val parsed = RelayCrypto.parseRelayEnvelope(encrypted, code, "", nowEpochSec = nowSec)
        assertTrue(parsed != null && parsed.ok)
        assertEquals(4, parsed?.telemetry?.unreadChatCount)
        assertEquals("obs", parsed?.telemetry?.recSourceTag)
    }

    @Test
    fun micPillMiniBadgeAndDisconnectReset_reflectChatAndRecSource() {
        val badge = MicPillMetricsCalculator.formatPillMiniBadgeText(
            ConnectionUiState(recState = 1, recSourceTag = "conf", unreadChatCount = 3),
            showBadges = true
        )
        assertTrue(badge.contains("CONF REC"))
        assertTrue(badge.contains("💬3"))

        val fakeCtx = object : ContextWrapper(null) {
            private val prefs = object : SharedPreferences {
                private val m = linkedMapOf<String, Any?>()
                override fun getAll() = m.toMutableMap()
                override fun getString(k: String?, d: String?) = m[k] as? String ?: d
                @Suppress("UNCHECKED_CAST")
                override fun getStringSet(k: String?, d: MutableSet<String>?) = (m[k] as? MutableSet<String>) ?: d
                override fun getInt(k: String?, d: Int) = m[k] as? Int ?: d
                override fun getLong(k: String?, d: Long) = m[k] as? Long ?: d
                override fun getFloat(k: String?, d: Float) = m[k] as? Float ?: d
                override fun getBoolean(k: String?, d: Boolean) = m[k] as? Boolean ?: d
                override fun contains(k: String?) = m.containsKey(k)
                override fun edit() = object : SharedPreferences.Editor {
                    private val p = linkedMapOf<String, Any?>()
                    override fun putString(k: String?, v: String?) = apply { if (k != null) p[k] = v }
                    override fun putStringSet(k: String?, v: MutableSet<String>?) = this
                    override fun putInt(k: String?, v: Int) = apply { if (k != null) p[k] = v }
                    override fun putLong(k: String?, v: Long) = apply { if (k != null) p[k] = v }
                    override fun putFloat(k: String?, v: Float) = apply { if (k != null) p[k] = v }
                    override fun putBoolean(k: String?, v: Boolean) = apply { if (k != null) p[k] = v }
                    override fun remove(k: String?) = apply { if (k != null) p[k] = null }
                    override fun clear() = this
                    override fun commit() = run { apply(); true }
                    override fun apply() { p.forEach { (k, v) -> if (v == null) m.remove(k) else m[k] = v } }
                }
                override fun registerOnSharedPreferenceChangeListener(l: SharedPreferences.OnSharedPreferenceChangeListener?) {}
                override fun unregisterOnSharedPreferenceChangeListener(l: SharedPreferences.OnSharedPreferenceChangeListener?) {}
            }
            override fun getApplicationContext(): Context = this
            override fun getSharedPreferences(name: String?, mode: Int): SharedPreferences = prefs
        }
        val mgr = ConnectionManager(context = fakeCtx, configStore = RemoteConfigStore(fakeCtx))
        mgr.stop()
        assertEquals("", mgr.uiState.value.recSourceTag)
        assertEquals(0, mgr.uiState.value.unreadChatCount)
    }
}
