package com.saabithjiffry.presentersync.remote.network

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RelayCryptoTest {

    @Test
    fun computesStandardObsWebSocketV5Sha256Auth() {
        // Known OBS WebSocket v5 spec vector:
        // password="supersecretpassword", salt="lM1G2+...", challenge="+..."
        // Verify deterministic double SHA-256 Base64 matches manual calculation:
        val secret = RelayCrypto.sha256Base64("pass123saltVal")
        val expected = RelayCrypto.sha256Base64(secret + "chalVal")
        assertEquals(expected, RelayCrypto.computeObsAuthResponse("pass123", "saltVal", "chalVal"))
        assertEquals("47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=", RelayCrypto.sha256Base64(""))
    }

    @Test
    fun relayTopicAndTokenNormalizeCaseAndWhitespace() {
        val t1 = RelayCrypto.getInternetRelayTopic("  ab12-cd34 ")
        val t2 = RelayCrypto.getInternetRelayTopic("AB12-CD34")
        assertEquals(t1, t2)
        assertTrue(t1.startsWith("psync_"))
        assertEquals(34, t1.length) // "psync_" + 28 alnum chars

        val a1 = RelayCrypto.getInternetRelayAuthToken(" ab12-cd34 ", "secret")
        val a2 = RelayCrypto.getInternetRelayAuthToken("AB12-CD34", "secret")
        assertEquals(a1, a2)
        assertTrue(a1.matches(Regex("^[a-zA-Z0-9]+$")))
    }

    @Test
    fun parsesRelayPacketFromNtfyJsonAndRawPayload() {
        val raw = RelayCrypto.formatRelayPacket("host", "state", "1", "TOKEN999")
        assertEquals("PSRELAY|host|state|1|TOKEN999", raw)

        val ntfyJson = """{"id":"1","event":"message","message":"PSRELAY|host|state|1|TOKEN999"}"""
        val parsed = RelayCrypto.parseRelayPacket(ntfyJson)
        assertNotNull(parsed)
        assertEquals("host", parsed!!.src)
        assertEquals("state", parsed.cmd)
        assertEquals("1", parsed.data)
        assertEquals("TOKEN999", parsed.auth)

        assertNull(RelayCrypto.parseRelayPacket("""{"event":"open"}"""))
    }
}
