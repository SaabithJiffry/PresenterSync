package com.saabithjiffry.presentersync.remote

import android.content.ContextWrapper
import android.content.SharedPreferences
import com.saabithjiffry.presentersync.remote.config.RemoteConfigStore
import com.saabithjiffry.presentersync.remote.input.BubbleHoldStage
import com.saabithjiffry.presentersync.remote.input.GestureScheduler
import com.saabithjiffry.presentersync.remote.network.ConnectionUiState
import com.saabithjiffry.presentersync.remote.ui.overlay.ScenePillHoldController
import com.saabithjiffry.presentersync.remote.ui.overlay.ScenePillMetricsCalculator
import com.saabithjiffry.presentersync.remote.ui.overlay.ScenePillReleaseOutcome
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SceneHudOverlayAndPodiumTest {

    @Test
    fun scenePillMetricsFormatsTextMarqueeAndBoundsScaleOnCompactPhones() {
        assertEquals("Offline", ScenePillMetricsCalculator.formatSceneDisplayText(ConnectionUiState(connected = false)))
        assertEquals(
            "Main Lecture",
            ScenePillMetricsCalculator.formatSceneDisplayText(
                ConnectionUiState(connected = true, activeScene = "Main Lecture", studioModeActive = false)
            )
        )
        assertEquals(
            "Main Cam → Slides",
            ScenePillMetricsCalculator.formatSceneDisplayText(
                ConnectionUiState(
                    connected = true,
                    activeScene = "Main Cam",
                    previewScene = "Slides",
                    studioModeActive = true
                )
            )
        )

        // No marquee scroll when text fits inside clip width
        assertEquals(0f, ScenePillMetricsCalculator.computeMarqueeScrollOffset(80f, 120f, 24f, 1000L, 40f), 0.01f)
        // Smooth positive marquee offset when overflowing
        assertTrue(ScenePillMetricsCalculator.computeMarqueeScrollOffset(220f, 120f, 26f, 1000L, 40f) > 0f)

        // Compact phone 360dp @ 2x density clamps requested 3.0x below 3.0x so it fits viewport cleanly
        val clamped = ScenePillMetricsCalculator.computeEffectiveScale(3.0f, 700, 2.0f)
        assertTrue(clamped < 2.2f)
    }

    @Test
    fun scenePillHoldControllerEnforcesTwoStageSingleActionSemantics() {
        var now = 0L
        val scheduler = FakeScheduler({ now }, { now = it })
        var taps = 0
        var menus = 0
        var resets = 0
        val stages = mutableListOf<BubbleHoldStage>()

        val ctrl = ScenePillHoldController(
            scheduler = scheduler,
            onTapTransition = { taps++ },
            onOpenSceneMenu = { menus++ },
            onResetActiveScene = { resets++ },
            onHoldStageUpdate = { st, _ -> stages.add(st) }
        )

        // 1. Short tap (<600ms) -> Transition only
        ctrl.onDown()
        scheduler.advanceBy(180L)
        assertEquals(ScenePillReleaseOutcome.TAP_TRANSITION, ctrl.onUp())
        assertEquals(1, taps)
        assertEquals(0, menus)
        assertEquals(0, resets)

        // 2. Stage 1 hold (700ms) + release before 1400ms -> Scene Quick Menu only
        ctrl.onDown()
        scheduler.advanceBy(700L)
        assertEquals(ScenePillReleaseOutcome.STAGE1_QUICK_MENU, ctrl.onUp())
        assertEquals(1, taps)
        assertEquals(1, menus)
        assertEquals(0, resets)
        assertTrue(stages.contains(BubbleHoldStage.REACHED_LONG))

        // 3. Stage 2 very-long-hold (>= 1400ms) -> Fires Reset once, trailing UP does NOT open menu or tap
        ctrl.onDown()
        scheduler.advanceBy(1450L)
        assertEquals(1, resets)
        assertEquals(ScenePillReleaseOutcome.STAGE2_ALREADY_TRIGGERED, ctrl.onUp())
        assertEquals(1, taps)
        assertEquals(1, menus)
        assertEquals(1, resets)

        // 4. Drag cancellation cancels pending timers cleanly
        ctrl.onDown()
        scheduler.advanceBy(200L)
        ctrl.onDragCancelled()
        scheduler.advanceBy(2000L)
        assertEquals(1, taps)
        assertEquals(1, menus)
        assertEquals(1, resets)
    }

    @Test
    fun remoteConfigPersistsAndResetsScenePillStateIndependently() {
        val ctx = InMemContext()
        val store = RemoteConfigStore(ctx)
        assertFalse(store.current.showSceneIndicator)

        store.update {
            it.copy(
                showSceneIndicator = true,
                sceneSavedX = 48,
                sceneSavedY = 92,
                sceneSavedXRatio = 0.25f,
                sceneSavedYRatio = 0.15f
            )
        }
        val reloaded = RemoteConfigStore(ctx).current
        assertTrue(reloaded.showSceneIndicator)
        assertEquals(48, reloaded.sceneSavedX)
        assertEquals(92, reloaded.sceneSavedY)
        assertEquals(0.25f, reloaded.sceneSavedXRatio, 0.001f)
        assertEquals(0.15f, reloaded.sceneSavedYRatio, 0.001f)

        store.resetScenePosition()
        assertEquals(-1, store.current.sceneSavedX)
        assertEquals(-1, store.current.sceneSavedY)
        assertEquals(-1f, store.current.sceneSavedXRatio, 0.001f)
    }

    private class FakeScheduler(
        private val getNow: () -> Long,
        private val setNow: (Long) -> Unit
    ) : GestureScheduler {
        private data class Entry(val runAt: Long, val task: () -> Unit, var cancelled: Boolean = false)
        private val q = ArrayList<Entry>()

        override fun schedule(delayMs: Long, task: () -> Unit): Any {
            val e = Entry(getNow() + delayMs, task)
            q.add(e)
            return e
        }

        override fun cancel(token: Any) {
            (token as? Entry)?.cancelled = true
        }

        fun advanceBy(deltaMs: Long) {
            val target = getNow() + deltaMs
            while (true) {
                val next = q.filter { !it.cancelled && it.runAt <= target }.minByOrNull { it.runAt } ?: break
                next.cancelled = true
                setNow(next.runAt)
                next.task.invoke()
            }
            setNow(target)
        }
    }

    private class InMemContext : ContextWrapper(null) {
        private val map = LinkedHashMap<String, SharedPreferences>()
        override fun getApplicationContext() = this
        override fun getSharedPreferences(name: String?, mode: Int): SharedPreferences =
            map.getOrPut(name ?: "default") { MemPrefs() }
    }

    private class MemPrefs : SharedPreferences {
        private val data = LinkedHashMap<String, Any?>()
        override fun getAll(): MutableMap<String, *> = data.toMutableMap()
        override fun getString(key: String?, defValue: String?): String? = data[key] as? String ?: defValue
        override fun getStringSet(key: String?, defValues: MutableSet<String>?): MutableSet<String>? = defValues
        override fun getInt(key: String?, defValue: Int): Int = (data[key] as? Int) ?: defValue
        override fun getLong(key: String?, defValue: Long): Long = (data[key] as? Long) ?: defValue
        override fun getFloat(key: String?, defValue: Float): Float = (data[key] as? Float) ?: defValue
        override fun getBoolean(key: String?, defValue: Boolean): Boolean = (data[key] as? Boolean) ?: defValue
        override fun contains(key: String?): Boolean = data.containsKey(key)
        override fun edit(): SharedPreferences.Editor = Ed(data)
        override fun registerOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener?) {}
        override fun unregisterOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener?) {}
        private class Ed(private val m: LinkedHashMap<String, Any?>) : SharedPreferences.Editor {
            override fun putString(k: String?, v: String?) = apply { if (k != null) { if (v == null) m.remove(k) else m[k] = v } }
            override fun putStringSet(k: String?, v: MutableSet<String>?) = this
            override fun putInt(k: String?, v: Int) = apply { if (k != null) m[k] = v }
            override fun putLong(k: String?, v: Long) = apply { if (k != null) m[k] = v }
            override fun putFloat(k: String?, v: Float) = apply { if (k != null) m[k] = v }
            override fun putBoolean(k: String?, v: Boolean) = apply { if (k != null) m[k] = v }
            override fun remove(k: String?) = apply { m.remove(k) }
            override fun clear() = apply { m.clear() }
            override fun commit(): Boolean = true
            override fun apply() {}
        }
    }
}
