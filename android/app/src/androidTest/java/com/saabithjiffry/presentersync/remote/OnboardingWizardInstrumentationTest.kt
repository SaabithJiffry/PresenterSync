package com.saabithjiffry.presentersync.remote

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.saabithjiffry.presentersync.remote.config.DeviceProfileMode
import com.saabithjiffry.presentersync.remote.config.FormFactorResolver
import com.saabithjiffry.presentersync.remote.config.RemoteConfig
import com.saabithjiffry.presentersync.remote.config.ThemeMode
import com.saabithjiffry.presentersync.remote.network.ConnectionUiState
import com.saabithjiffry.presentersync.remote.network.DiscoveredPublicHost
import com.saabithjiffry.presentersync.remote.ui.screens.OnboardingWizardCard
import com.saabithjiffry.presentersync.remote.ui.theme.PresenterSyncTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

@RunWith(AndroidJUnit4::class)
class OnboardingWizardInstrumentationTest {

    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun onboardingWizardRendersStepsDiscoversLanHostAndCompletes() {
        val selectedHost = AtomicReference<DiscoveredPublicHost?>(null)
        val testedHud = AtomicBoolean(false)
        val completed = AtomicBoolean(false)

        val mockHost = DiscoveredPublicHost(
            hostUuid = "host-room-101",
            deviceName = "LectureHall-PC",
            hostIp = "192.168.10.22",
            bridgePort = 4456,
            obsPort = 4455,
            networkMode = "LAN",
            audioRoutingMode = 2,
            version = "6.8.0"
        )

        val ff = FormFactorResolver.resolve(DeviceProfileMode.PHONE, 412, 892, 412)
        composeRule.setContent {
            PresenterSyncTheme(themeMode = ThemeMode.DARK) {
                Column(modifier = Modifier.verticalScroll(rememberScrollState())) {
                    OnboardingWizardCard(
                        cfg = RemoteConfig(firstRun = true, hostAddress = "127.0.0.1"),
                        conn = ConnectionUiState(connected = false, serviceRunning = false),
                        hasOverlayPerm = false,
                        hasNotifPerm = true,
                        formFactor = ff,
                        onRequestOverlayPermission = {},
                        onRequestNotificationPermission = {},
                        onScanClassroomHosts = { listOf(mockHost) },
                        onSelectDiscoveredHost = { selectedHost.set(it) },
                        onOpenQrScanner = {},
                        onOpenConnectionSetup = {},
                        onTestFloatingHud = { testedHud.set(true) },
                        onCompleteWizard = { completed.set(true) },
                        onDismissWizard = {}
                    )
                }
            }
        }

        composeRule.onNodeWithTag("onboarding_wizard_card").assertIsDisplayed()
        composeRule.onNodeWithTag("onboarding_step_1").performScrollTo().assertIsDisplayed()
        composeRule.onNodeWithTag("onboarding_step_3").performScrollTo().assertIsDisplayed()

        composeRule.onNodeWithTag("onboarding_scan_lan_btn").performScrollTo().performClick()
        composeRule.waitForIdle()

        composeRule.onNodeWithText("LectureHall-PC (192.168.10.22:4456)").performScrollTo().assertIsDisplayed()
        composeRule.onNodeWithText("LectureHall-PC (192.168.10.22:4456)").performClick()
        assertEquals("192.168.10.22", selectedHost.get()?.hostIp)

        composeRule.onNodeWithTag("onboarding_test_hud_btn").performScrollTo().performClick()
        assertTrue(testedHud.get())

        composeRule.onNodeWithTag("onboarding_finish_btn").performScrollTo().performClick()
        assertTrue(completed.get())
    }
}
