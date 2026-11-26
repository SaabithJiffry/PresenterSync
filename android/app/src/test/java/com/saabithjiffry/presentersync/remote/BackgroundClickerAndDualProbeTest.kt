package com.saabithjiffry.presentersync.remote

import android.view.KeyEvent
import com.saabithjiffry.presentersync.remote.config.PairingUriBuilder
import com.saabithjiffry.presentersync.remote.config.RemoteConfig
import com.saabithjiffry.presentersync.remote.input.BubbleGestureAction
import com.saabithjiffry.presentersync.remote.network.DualProbeResult
import com.saabithjiffry.presentersync.remote.service.BackgroundMediaActionDebouncer
import com.saabithjiffry.presentersync.remote.service.BackgroundMediaKeyMapper
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BackgroundClickerAndDualProbeTest {

    @Test
    fun backgroundMediaKeyMapper_resolvesMediaKeysAndVolumeSteps() {
        val muteCfg = RemoteConfig(
            enableBackgroundMediaClicker = true,
            backgroundMediaPrimaryAction = BubbleGestureAction.TOGGLE_MUTE
        )
        assertEquals(
            BubbleGestureAction.TOGGLE_MUTE,
            BackgroundMediaKeyMapper.resolveKeyAction(KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, muteCfg)
        )
        assertEquals(
            BubbleGestureAction.TOGGLE_MUTE,
            BackgroundMediaKeyMapper.resolveKeyAction(KeyEvent.KEYCODE_HEADSETHOOK, muteCfg)
        )
        assertEquals(
            BubbleGestureAction.SLIDE_NEXT,
            BackgroundMediaKeyMapper.resolveKeyAction(KeyEvent.KEYCODE_MEDIA_NEXT, muteCfg)
        )
        assertEquals(
            BubbleGestureAction.SLIDE_PREV,
            BackgroundMediaKeyMapper.resolveKeyAction(KeyEvent.KEYCODE_MEDIA_PREVIOUS, muteCfg)
        )

        val transCfg = muteCfg.copy(backgroundMediaPrimaryAction = BubbleGestureAction.TRANSITION_SCENE)
        assertEquals(
            BubbleGestureAction.TRANSITION_SCENE,
            BackgroundMediaKeyMapper.resolveKeyAction(KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, transCfg)
        )
        assertEquals(
            BubbleGestureAction.TRANSITION_SCENE,
            BackgroundMediaKeyMapper.resolveKeyAction(KeyEvent.KEYCODE_HEADSETHOOK, transCfg)
        )

        assertEquals(BubbleGestureAction.SLIDE_NEXT, BackgroundMediaKeyMapper.resolveVolumeStepAction(1, muteCfg))
        assertEquals(BubbleGestureAction.SLIDE_PREV, BackgroundMediaKeyMapper.resolveVolumeStepAction(-1, muteCfg))
    }

    @Test
    fun pairingUriBuilder_buildsAndUrlEncodesFields() {
        val cfg = RemoteConfig(
            hostAddress = "192.168.1.50",
            bridgePort = 4458,
            sessionPairingCode = "K7M-9P2",
            hostPort = 4455,
            obsPassword = "My Pass!&1",
            internetPairingCode = "WAN-123"
        )
        val uri = PairingUriBuilder.build(cfg)
        assertTrue(uri.startsWith("presentersync://pair?"))
        assertTrue(uri.contains("host=192.168.1.50"))
        assertTrue(uri.contains("bp=4458"))
        assertTrue(uri.contains("code=K7M-9P2"))
        assertTrue(uri.contains("obsPort=4455"))
        assertFalse(uri.contains("obsPass="))
        assertTrue(uri.contains("wan=WAN-123"))
    }

    @Test
    fun dualProbeResult_formatsAllFourCombinations() {
        assertEquals(
            "Host Bridge (:4456): OK | Direct OBS (:4455): OK",
            DualProbeResult(true, "Host Bridge (:4456): OK", true, "Direct OBS (:4455): OK").formatSummary()
        )
        assertEquals(
            "Host Bridge (:4456): UNREACHABLE | Direct OBS (:4455): OK",
            DualProbeResult(false, "Host Bridge (:4456): UNREACHABLE", true, "Direct OBS (:4455): OK").formatSummary()
        )
        assertEquals(
            "Host Bridge (:4456): OK | Direct OBS (:4455): UNREACHABLE",
            DualProbeResult(true, "Host Bridge (:4456): OK", false, "Direct OBS (:4455): UNREACHABLE").formatSummary()
        )
        assertEquals(
            "Host Bridge (:4456): UNREACHABLE | Direct OBS (:4455): UNREACHABLE",
            DualProbeResult(false, "Host Bridge (:4456): UNREACHABLE", false, "Direct OBS (:4455): UNREACHABLE").formatSummary()
        )
    }

    @Test
    fun backgroundMediaActionDebouncer_blocksDuplicateBurstWithinWindowAndAllowsDistinctOrExpired() {
        var now = 1000L
        val debouncer = BackgroundMediaActionDebouncer(debounceMs = 150L, clockMs = { now })

        assertTrue(debouncer.shouldDispatch(BubbleGestureAction.TOGGLE_MUTE))
        now += 40L
        assertFalse(debouncer.shouldDispatch(BubbleGestureAction.TOGGLE_MUTE))
        assertTrue(debouncer.shouldDispatch(BubbleGestureAction.SLIDE_NEXT))
        now += 155L
        assertTrue(debouncer.shouldDispatch(BubbleGestureAction.SLIDE_NEXT))
    }
}
