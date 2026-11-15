package com.saabithjiffry.presentersync.remote.config

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SavedHostProfileCodecTest {

    @Test
    fun roundTripsMultipleProfilesWithAllFieldsIntact() {
        val input = listOf(
            SavedHostProfile(
                id = "prof-1",
                name = "Hall 201 SmartBoard",
                networkMode = NetworkMode.LAN,
                hostAddress = "192.168.10.20, HALL201.local",
                hostPort = 4455,
                bridgePort = 4456,
                obsPassword = "pw-201",
                internetPairingCode = "PS-HALL-201",
                sessionToken = "tok-abc-123",
                sessionPairingCode = "H2M-9K4",
                targetMicName = "Rode Wireless",
                heartbeatSeconds = 25
            ),
            SavedHostProfile(
                id = "prof-2",
                name = "Auditorium Relay",
                networkMode = NetworkMode.INTERNET,
                hostAddress = "10.0.0.5",
                hostPort = 4455,
                bridgePort = 4458,
                obsPassword = "",
                internetPairingCode = "PS-AUDI-777",
                sessionToken = "",
                sessionPairingCode = "",
                targetMicName = "Mic/Aux",
                heartbeatSeconds = 45
            )
        )

        val encoded = SavedHostProfileCodec.toJsonString(input)
        val decoded = SavedHostProfileCodec.fromJsonString(encoded)
        assertEquals(input, decoded)
    }

    @Test
    fun ignoresInvalidJsonAndClampsOutOfRangePorts() {
        assertTrue(SavedHostProfileCodec.fromJsonString("").isEmpty())
        assertTrue(SavedHostProfileCodec.fromJsonString("{not_an_array").isEmpty())

        val malformed = """
            [
              {"id":"","name":"SkipBlankId"},
              {"id":"p1","name":"ValidRoom","hostPort":99999,"bridgePort":0,"heartbeatSeconds":3}
            ]
        """.trimIndent()
        val parsed = SavedHostProfileCodec.fromJsonString(malformed)
        assertEquals(1, parsed.size)
        assertEquals("ValidRoom", parsed[0].name)
        assertEquals(AppConstants.DEFAULT_OBS_PORT, parsed[0].hostPort)
        assertEquals(AppConstants.DEFAULT_BRIDGE_PORT, parsed[0].bridgePort)
        assertEquals(AppConstants.DEFAULT_HEARTBEAT_SECONDS, parsed[0].heartbeatSeconds)
    }

    @Test
    fun remoteConfigDefaultsAreSmartBoardSafe() {
        val def = RemoteConfig()
        assertFalse(def.keepScreenOn)
        assertEquals(0, def.idleDimAfterSec)
        assertTrue(def.savedProfiles.isEmpty())
        assertEquals("", def.activeProfileId)
        assertEquals(600, def.longPressDurationMs)
        assertEquals(1400, def.veryLongPressDurationMs)
    }
}
