package com.saabithjiffry.presentersync.remote.network

import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import com.saabithjiffry.presentersync.remote.config.NetworkMode
import com.saabithjiffry.presentersync.remote.config.RemoteConfigStore
import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.util.concurrent.atomic.AtomicLong

class BridgeRepromotionTest {
    private lateinit var server: MockWebServer
    private lateinit var manager: ConnectionManager
    private lateinit var configStore: RemoteConfigStore
    private lateinit var clockMs: AtomicLong

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
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
    fun bridgeRepromoteConstantsMatch8000MsAnd500Ms() {
        assertEquals(8000L, ConnectionManager.BRIDGE_REPROMOTE_INTERVAL_MS)
        assertEquals(500L, ConnectionManager.HEALTH_PROBE_TIMEOUT_MS)
    }

    @Test
    fun checkAndPromoteLanIfHealthyPromotesWhenHealthReturns200Ok() = runBlocking {
        val hostUuid = "host-uuid-repromote-1"
        configStore.update {
            it.copy(
                networkMode = NetworkMode.LAN,
                hostAddress = "127.0.0.1",
                hostPort = 4455,
                bridgePort = server.port,
                sessionPairingCode = "K7M-9P2",
                pairedHostUuid = ""
            )
        }
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setBody("""{"ok":true,"hostUuid":"$hostUuid","bridgePort":${server.port}}""")
        )

        val promoted = manager.checkAndPromoteLanIfHealthy(0)
        assertTrue(promoted)
    }

    @Test
    fun checkAndPromoteLanIfHealthyReturnsFalseWhenHealthIs503() = runBlocking {
        configStore.update {
            it.copy(
                networkMode = NetworkMode.LAN,
                hostAddress = "127.0.0.1",
                hostPort = 4455,
                bridgePort = server.port,
                sessionPairingCode = "K7M-9P2",
                pairedHostUuid = ""
            )
        }
        server.enqueue(MockResponse().setResponseCode(503))

        val promoted = manager.checkAndPromoteLanIfHealthy(0)
        assertFalse(promoted)
    }

    private class InMemoryPrefsContext : ContextWrapper(null) {
        private val prefs = InMemorySharedPreferences()
        override fun getApplicationContext(): Context = this
        override fun getSharedPreferences(name: String?, mode: Int): SharedPreferences = prefs
    }

    private class InMemorySharedPreferences : SharedPreferences {
        private val map = linkedMapOf<String, Any?>()
        override fun getAll(): MutableMap<String, *> = map.toMutableMap()
        override fun getString(key: String?, defValue: String?): String? = map[key] as? String ?: defValue
        override fun getStringSet(key: String?, defValues: MutableSet<String>?): MutableSet<String>? = defValues
        override fun getInt(key: String?, defValue: Int): Int = map[key] as? Int ?: defValue
        override fun getLong(key: String?, defValue: Long): Long = map[key] as? Long ?: defValue
        override fun getFloat(key: String?, defValue: Float): Float = map[key] as? Float ?: defValue
        override fun getBoolean(key: String?, defValue: Boolean): Boolean = map[key] as? Boolean ?: defValue
        override fun contains(key: String?): Boolean = map.containsKey(key)
        override fun edit(): SharedPreferences.Editor = object : SharedPreferences.Editor {
            private val pending = linkedMapOf<String, Any?>()
            private var cleared = false
            override fun putString(key: String?, value: String?) = apply { if (key != null) pending[key] = value }
            override fun putStringSet(key: String?, values: MutableSet<String>?) = this
            override fun putInt(key: String?, value: Int) = apply { if (key != null) pending[key] = value }
            override fun putLong(key: String?, value: Long) = apply { if (key != null) pending[key] = value }
            override fun putFloat(key: String?, value: Float) = apply { if (key != null) pending[key] = value }
            override fun putBoolean(key: String?, value: Boolean) = apply { if (key != null) pending[key] = value }
            override fun remove(key: String?) = apply { if (key != null) pending[key] = null }
            override fun clear() = apply { cleared = true }
            override fun commit(): Boolean { apply(); return true }
            override fun apply() {
                if (cleared) map.clear()
                for ((k, v) in pending) {
                    if (v == null) map.remove(k) else map[k] = v
                }
            }
        }
        override fun registerOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener?) {}
        override fun unregisterOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener?) {}
    }
}
