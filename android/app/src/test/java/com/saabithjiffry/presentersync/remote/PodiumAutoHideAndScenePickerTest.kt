package com.saabithjiffry.presentersync.remote

import androidx.compose.ui.window.SecureFlagPolicy
import com.saabithjiffry.presentersync.remote.network.ConnectionUiState
import com.saabithjiffry.presentersync.remote.service.FloatingHudVisibilityResolver
import com.saabithjiffry.presentersync.remote.ui.screens.buildPodiumSceneChipModels
import com.saabithjiffry.presentersync.remote.ui.screens.resolvePodiumScenePickerSecurePolicy
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PodiumAutoHideAndScenePickerTest {

    @Test
    fun visibilityResolverSuppressesHudOnlyWhenActiveOrArcadeAndRestoresCleanly() {
        val visibleBoth = FloatingHudVisibilityResolver.resolve(
            showIndicator = true,
            showSceneIndicator = true,
            hiddenForArcade = false,
            podiumForegroundActive = false
        )
        assertTrue(visibleBoth.micOverlayVisible)
        assertTrue(visibleBoth.sceneOverlayVisible)

        val suppressedPodium = FloatingHudVisibilityResolver.resolve(
            showIndicator = true,
            showSceneIndicator = true,
            hiddenForArcade = false,
            podiumForegroundActive = true
        )
        assertFalse(suppressedPodium.micOverlayVisible)
        assertFalse(suppressedPodium.sceneOverlayVisible)

        val micOnlyAfterExit = FloatingHudVisibilityResolver.resolve(
            showIndicator = true,
            showSceneIndicator = false,
            hiddenForArcade = false,
            podiumForegroundActive = false
        )
        assertTrue(micOnlyAfterExit.micOverlayVisible)
        assertFalse(micOnlyAfterExit.sceneOverlayVisible)

        val disabledPrefsStayDisabled = FloatingHudVisibilityResolver.resolve(
            showIndicator = false,
            showSceneIndicator = false,
            hiddenForArcade = false,
            podiumForegroundActive = false
        )
        assertFalse(disabledPrefsStayDisabled.micOverlayVisible)
        assertFalse(disabledPrefsStayDisabled.sceneOverlayVisible)
    }

    @Test
    fun rbacRoleHelpersClassifyTallyOnlyPresenterAndDirector() {
        val tallyFull = ConnectionUiState(connected = true, remoteRole = "Tally-Only")
        val tallyShort = ConnectionUiState(connected = true, remoteRole = "tally")
        val presenter = ConnectionUiState(connected = true, remoteRole = "Presenter")
        val director = ConnectionUiState(connected = true, remoteRole = "Director")

        assertTrue(tallyFull.isTallyOnly)
        assertFalse(tallyFull.canControlObs)
        assertTrue(tallyShort.isTallyOnly)
        assertFalse(tallyShort.canControlObs)

        assertFalse(presenter.isTallyOnly)
        assertTrue(presenter.canControlObs)
        assertFalse(presenter.isDirector)

        assertFalse(director.isTallyOnly)
        assertTrue(director.canControlObs)
        assertTrue(director.isDirector)
    }

    @Test
    fun sceneChipBuilderMarksLiveAndPreviewDeduplicatesAndHonorsSecurePolicy() {
        val chips = buildPodiumSceneChipModels(
            scenes = listOf("Main Cam", "Slides", "Main Cam", "BRB", " "),
            activeScene = "Main Cam",
            previewScene = "Slides",
            studioModeActive = true
        )
        assertEquals(3, chips.size)
        assertEquals("Main Cam", chips[0].name)
        assertTrue(chips[0].isLive)
        assertFalse(chips[0].isPreview)

        assertEquals("Slides", chips[1].name)
        assertFalse(chips[1].isLive)
        assertTrue(chips[1].isPreview)

        assertEquals("BRB", chips[2].name)
        assertFalse(chips[2].isLive)
        assertFalse(chips[2].isPreview)

        assertEquals(SecureFlagPolicy.SecureOn, resolvePodiumScenePickerSecurePolicy(true))
        assertEquals(SecureFlagPolicy.Inherit, resolvePodiumScenePickerSecurePolicy(false))
    }
}
