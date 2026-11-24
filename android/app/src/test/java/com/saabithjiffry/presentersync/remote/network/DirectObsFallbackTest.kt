package com.saabithjiffry.presentersync.remote.network

import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import com.saabithjiffry.presentersync.remote.config.RemoteConfigStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.util.concurrent.atomic.AtomicLong

class DirectObsFallbackTest {
    private lateinit var manager: ConnectionManager
    private lateinit var configStore: RemoteConfigStore
    private lateinit var clockMs: AtomicLong

    @Before
    fun setUp() {
        clockMs = AtomicLong(10_000L)
        val fakeContext = InMemoryPrefsContext()
        configStore = RemoteConfigStore(fakeContext)
        manager = ConnectionManager(
            context = fakeContext,
            configStore = configStore,
            clockMs = { clockMs.get() }
        )
    }

    @Test
    fun bridgeConnectTimeoutIs1800MsAndChannelEnumIncludesDirectObs() {
        assertEquals(1800L, ConnectionManager.BRIDGE_CONNECT_TIMEOUT_MS)
        assertEquals(ChannelType.DIRECT_OBS, ConnectionChannel.DIRECT_OBS)
    }

    @Test
    fun localTimerCommandsWorkInDirectObsFallbackMode() {
        assertTrue(manager.executeLocalTimerCommand("timer_start", 300))
        assertEquals("running", manager.uiState.value.timerState)
        assertEquals(300, manager.uiState.value.timerRemainingSec)

        assertTrue(manager.executeLocalTimerCommand("timer_pause", 0))
        assertEquals("paused", manager.uiState.value.timerState)

        assertTrue(manager.executeLocalTimerCommand("timer_reset", 480))
        assertEquals("stopped", manager.uiState.value.timerState)
        assertEquals(480, manager.uiState.value.timerRemainingSec)
    }

    @Test
    fun localStandbyToggleSnapshotsAndRestoresSceneAndMuteState() {
        assertTrue(manager.executeLocalObsStandbyToggle())
        assertTrue(manager.uiState.value.isStandby)
        assertTrue(manager.uiState.value.isMuted)

        assertTrue(manager.executeLocalObsStandbyToggle())
        assertFalse(manager.uiState.value.isStandby)
        assertFalse(manager.uiState.value.isMuted)
    }

    @Test
    fun resolveNonStudioTransitionTargetPrioritizesPreviewThenPrevProgramThenScenesCycle() {
        assertEquals(
            "Slides",
            ConnectionManager.resolveNonStudioTransitionTarget(
                ConnectionUiState(activeScene = "Main", previewScene = "Slides", previousProgramScene = "Intro", scenes = listOf("Main", "Intro", "Closing"))
            )
        )
        assertEquals(
            "Intro",
            ConnectionManager.resolveNonStudioTransitionTarget(
                ConnectionUiState(activeScene = "Main", previewScene = "Main", previousProgramScene = "Intro", scenes = listOf("Main", "Closing"))
            )
        )
        assertEquals(
            "Closing",
            ConnectionManager.resolveNonStudioTransitionTarget(
                ConnectionUiState(activeScene = "Main", previewScene = "", previousProgramScene = "", scenes = listOf("Intro", "Main", "Closing"))
            )
        )
        assertEquals(
            "",
            ConnectionManager.resolveNonStudioTransitionTarget(
                ConnectionUiState(activeScene = "Main", previewScene = "", previousProgramScene = "", scenes = listOf("Main"))
            )
        )
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
