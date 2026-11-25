package com.saabithjiffry.presentersync.remote

import com.saabithjiffry.presentersync.remote.network.RelayClient
import com.saabithjiffry.presentersync.remote.network.RelayCrypto
import com.saabithjiffry.presentersync.remote.network.RelayReplayGuard
import com.saabithjiffry.presentersync.remote.network.RelaySessionCallbacks
import com.saabithjiffry.presentersync.remote.network.RelayTelemetryState
import okhttp3.OkHttpClient
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Base64
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

class AesGcmRelayCryptoTest {

    companion object {
        // Shared deterministic vector verified byte-for-byte against Lib\Crypto.ahk (Win32 bcrypt.dll)
        private const val VECTOR_CODE = "PS-TEST-7620"
        private const val VECTOR_SALT = "ObsPass#762"
        private const val VECTOR_PLAIN = """{"v":1,"cmd":"state","isMuted":true,"scenes":["Intro","Slides"]}"""
        private val VECTOR_IV = ByteArray(12) { (it + 1).toByte() }
        private const val EXPECTED_VECTOR_ENVELOPE =
            "PSGCM1|AQIDBAUGBwgJCgsM|xm/rr4vlvT59lkdEHjQ+P3tWFW56lxVwSKJdXy8O2FfPGMxM/Dw1yPpLzed7CPasWvSBETWV7hXK0Z+6I0r53ydmSMcV6nLWy/c/7mu8lUk="
        private const val EXPECTED_VECTOR_ENVELOPE_V2 =
            "PSGCM2|AQIDBAUGBwgJCgsM|A50jQz/upMirKVGolj9r2QcU7BnA4P3spHJsyqbW5/oVZfmkkl6dbkH5ZDeFvSCz4YxnPCCQ/roAdtcByzVTdVARwZnOOudwdZKIPIaMb1Y="
    }

    @Test
    fun deterministicCrossLanguageVectorMatchesAhkBcryptByteForByte() {
        val key1 = RelayCrypto.deriveAesGcmKey32(VECTOR_CODE, VECTOR_SALT)
        val key2 = RelayCrypto.deriveAesGcmKey32("  $VECTOR_CODE ", " $VECTOR_SALT  ")
        assertEquals(32, key1.size)
        assertTrue(key1.contentEquals(key2))

        val envV2 = RelayCrypto.encryptRelayPayload(VECTOR_PLAIN, VECTOR_CODE, VECTOR_SALT, VECTOR_IV)
        assertEquals(EXPECTED_VECTOR_ENVELOPE_V2, envV2)
        assertEquals(VECTOR_PLAIN, RelayCrypto.decryptRelayPayload(envV2, VECTOR_CODE, VECTOR_SALT))
        assertNull(RelayCrypto.decryptRelayPayload(envV2, "WRONG-AAD-CODE", VECTOR_SALT))

        val envelopeV1 = RelayCrypto.encryptRelayPayloadV1(VECTOR_PLAIN, VECTOR_CODE, VECTOR_SALT, VECTOR_IV)
        assertEquals(EXPECTED_VECTOR_ENVELOPE, envelopeV1)
        val envelope = envelopeV1

        val decrypted = RelayCrypto.decryptRelayPayload(envelope, VECTOR_CODE, VECTOR_SALT)
        assertEquals(VECTOR_PLAIN, decrypted)

        // Wrapped inside ntfy WebSocket JSON envelope
        val ntfyJson = """{"id":"m1","event":"message","topic":"psync_test","message":"$envV2"}"""
        assertEquals(VECTOR_PLAIN, RelayCrypto.decryptRelayPayload(ntfyJson, VECTOR_CODE, VECTOR_SALT))
    }

    @Test
    fun randomIvRoundtripAndTamperedCiphertextTagIvRejection() {
        val utfPlain = """{"v":1,"cmd":"nudge","data":"Host;Wrap up — 2 min left ✓"}"""
        val env1 = RelayCrypto.encryptRelayPayload(utfPlain, VECTOR_CODE, VECTOR_SALT)
        val env2 = RelayCrypto.encryptRelayPayload(utfPlain, VECTOR_CODE, VECTOR_SALT)
        assertTrue(env1.startsWith("PSGCM2|"))
        assertTrue(env2.startsWith("PSGCM2|"))
        assertNotEquals(env1, env2)
        assertEquals(utfPlain, RelayCrypto.decryptRelayPayload(env1, VECTOR_CODE, VECTOR_SALT))
        assertEquals(utfPlain, RelayCrypto.decryptRelayPayload(env2, VECTOR_CODE, VECTOR_SALT))

        val parts = EXPECTED_VECTOR_ENVELOPE_V2.split("|")
        val b64Iv = parts[1]
        val ctAndTag = Base64.getDecoder().decode(parts[2])

        // Tamper ciphertext byte 0
        val badCt = ctAndTag.copyOf()
        badCt[0] = (badCt[0].toInt() xor 0x01).toByte()
        assertNull(
            RelayCrypto.decryptRelayPayload(
                "PSGCM2|$b64Iv|${Base64.getEncoder().encodeToString(badCt)}",
                VECTOR_CODE,
                VECTOR_SALT
            )
        )

        // Tamper trailing GCM authentication tag byte
        val badTag = ctAndTag.copyOf()
        badTag[badTag.lastIndex] = (badTag[badTag.lastIndex].toInt() xor 0x80).toByte()
        assertNull(
            RelayCrypto.decryptRelayPayload(
                "PSGCM2|$b64Iv|${Base64.getEncoder().encodeToString(badTag)}",
                VECTOR_CODE,
                VECTOR_SALT
            )
        )

        // Tamper IV
        val badIv = VECTOR_IV.copyOf()
        badIv[0] = (badIv[0].toInt() xor 0xFF).toByte()
        assertNull(
            RelayCrypto.decryptRelayPayload(
                "PSGCM2|${Base64.getEncoder().encodeToString(badIv)}|${parts[2]}",
                VECTOR_CODE,
                VECTOR_SALT
            )
        )

        // Wrong secretSalt / password
        assertNull(RelayCrypto.decryptRelayPayload(EXPECTED_VECTOR_ENVELOPE_V2, VECTOR_CODE, "WrongPass"))
    }

    @Test
    fun replayGuardRejectsDuplicateOutOfOrderAndStaleSeq() {
        val guard = RelayReplayGuard(maxSkewSec = 300L)
        val now = 1732210000L

        assertTrue(guard.accept("host:s1", 1L, now, now))
        assertFalse(guard.accept("host:s1", 1L, now, now))
        assertFalse(guard.accept("host:s1", 0L, now, now))
        assertTrue(guard.accept("host:s1", 5L, now, now))
        assertFalse(guard.accept("host:s1", 4L, now, now))
        assertTrue(guard.accept("host:s2", 1L, now, now))
        assertFalse(guard.accept("host:s1", 6L, now - 600L, now))
    }

    @Test
    fun customRelayBaseUrlNormalizationAndWsUrlBuilding() {
        assertEquals("https://ntfy.sh", RelayCrypto.normalizeRelayBaseUrl(""))
        assertEquals("https://ntfy.sh", RelayCrypto.normalizeRelayBaseUrl("   "))
        assertEquals("https://ntfy.school.edu", RelayCrypto.normalizeRelayBaseUrl("https://ntfy.school.edu/"))
        assertEquals("http://10.0.0.5:8080", RelayCrypto.normalizeRelayBaseUrl("http://10.0.0.5:8080/"))
        assertEquals("https://ntfy.internal:8443", RelayCrypto.normalizeRelayBaseUrl("ntfy.internal:8443"))
        assertEquals("https://ntfy.school.edu", RelayCrypto.normalizeRelayBaseUrl("wss://ntfy.school.edu/"))
        assertEquals("http://192.168.1.10:2586", RelayCrypto.normalizeRelayBaseUrl("ws://192.168.1.10:2586"))
        assertEquals("https://ntfy.sh", RelayCrypto.normalizeRelayBaseUrl("invalid url with spaces"))

        assertEquals(
            "wss://ntfy.school.edu/psync_abc123/ws",
            RelayCrypto.buildRelayWsUrl("https://ntfy.school.edu/", "psync_abc123")
        )
        assertEquals(
            "ws://10.0.0.5:8080/psync_abc123/ws",
            RelayCrypto.buildRelayWsUrl("http://10.0.0.5:8080/", "psync_abc123")
        )
        assertEquals(
            "http://10.0.0.5:8080/psync_abc123",
            RelayCrypto.buildRelayPublishUrl("http://10.0.0.5:8080/", "psync_abc123")
        )

        val httpClient = OkHttpClient.Builder().build()
        try {
            val customClient = RelayClient(
                httpClient = httpClient,
                pairingCode = VECTOR_CODE,
                password = VECTOR_SALT,
                httpBaseUrl = "http://10.0.0.5:8080/",
                callbacks = object : RelaySessionCallbacks {
                    override fun onRelayConnected() = Unit
                    override fun onRelayAuthFailed() = Unit
                    override fun onRelayMuteState(muted: Boolean) = Unit
                    override fun onCloseRemoteSignal() = Unit
                    override fun onRelayDisconnected(reason: String) = Unit
                }
            )
            val topic = RelayCrypto.getInternetRelayTopic(VECTOR_CODE)
            assertEquals("ws://10.0.0.5:8080/$topic/ws", customClient.resolveWsUrl())
            assertEquals("http://10.0.0.5:8080/$topic", customClient.resolvePublishUrl())
        } finally {
            httpClient.dispatcher.executorService.shutdown()
            httpClient.connectionPool.evictAll()
        }
    }

    @Test
    fun relayClientParsesEncryptedWanTelemetryParityAndRejectsReplayAndTampering() {
        val code = "PS-V762-9999"
        val pass = "HostSecret762"
        val auth = RelayCrypto.getInternetRelayAuthToken(code, pass)

        val muteCalls = AtomicInteger(0)
        val telemetryCalls = AtomicInteger(0)
        val lastTelemetry = AtomicReference<RelayTelemetryState>()
        val lastMuted = AtomicReference<Boolean>()

        val warnings = mutableListOf<Pair<String, String>>()
        val httpClient = OkHttpClient.Builder().build()
        try {
            val client = RelayClient(
                httpClient = httpClient,
                pairingCode = code,
                password = pass,
                callbacks = object : RelaySessionCallbacks {
                    override fun onRelayConnected() = Unit
                    override fun onRelayAuthFailed() = Unit
                    override fun onRelayMuteState(muted: Boolean) {
                        muteCalls.incrementAndGet()
                        lastMuted.set(muted)
                    }

                    override fun onRelayTelemetryState(telemetry: RelayTelemetryState) {
                        telemetryCalls.incrementAndGet()
                        lastTelemetry.set(telemetry)
                    }

                    override fun onRelayWarning(code: String, message: String) {
                        warnings.add(code to message)
                    }

                    override fun onCloseRemoteSignal() = Unit
                    override fun onRelayDisconnected(reason: String) = Unit
                }
            )

            val nowSec = System.currentTimeMillis() / 1000L
            val hostJson = JSONObject()
                .put("v", 2)
                .put("src", "host")
                .put("cmd", "state")
                .put("data", "1")
                .put("seq", 1L)
                .put("ts", nowSec)
                .put("sid", "host762")
                .put("auth", auth)
                .put("isMuted", true)
                .put("isStandby", true)
                .put("recState", 1)
                .put("recSeconds", 187)
                .put("streamDropWarn", true)
                .put("voiceWhileMuted", true)
                .put("osMicMutedDrift", true)
                .put("lowDiskWarnLevel", 1)
                .put("lowDiskMb", 1900)
                .put("deadMicWarn", true)
                .put("slideIndex", 3)
                .put("slideTotal", 15)
                .put("slideTitle", "Intro Slide")
                .put("timerState", "running")
                .put("timerRemainingSec", 245)
                .put("timerPresetSec", 600)
                .put("activeScene", "Main Slides")
                .put("scenes", JSONArray(listOf("Intro", "Main Slides", "Webcam Full", "BRB")))
                .toString()

            val encryptedEnv = RelayCrypto.encryptRelayPayload(hostJson, code, pass)
            assertTrue(encryptedEnv.startsWith("PSGCM2|"))
            val ntfyFrame = """{"event":"message","message":"$encryptedEnv"}"""

            // First delivery accepted with full WAN telemetry parity + watchdog & slide fields
            client.handleRawMessage(ntfyFrame)
            assertEquals(1, muteCalls.get())
            assertEquals(1, telemetryCalls.get())
            assertEquals(true, lastMuted.get())
            val tel = lastTelemetry.get()
            assertNotNull(tel)
            assertEquals(1, tel.recState)
            assertEquals(187, tel.recSeconds)
            assertTrue(tel.streamDropWarn)
            assertTrue(tel.voiceWhileMuted)
            assertTrue(tel.osMicMutedDrift)
            assertEquals(1, tel.lowDiskWarnLevel)
            assertEquals(1900, tel.lowDiskMb)
            assertTrue(tel.deadMicWarn)
            assertEquals(3, tel.slideIndex)
            assertEquals(15, tel.slideTotal)
            assertEquals("Intro Slide", tel.slideTitle)
            assertTrue(tel.isStandby)
            assertEquals("running", tel.timerState)
            assertEquals(245, tel.timerRemainingSec)
            assertEquals(600, tel.timerPresetSec)
            assertEquals("Main Slides", tel.activeScene)
            assertEquals(listOf("Intro", "Main Slides", "Webcam Full", "BRB"), tel.scenes)

            // Exact replay must be rejected!
            client.handleRawMessage(ntfyFrame)
            assertEquals(1, muteCalls.get())
            assertEquals(1, telemetryCalls.get())

            // Clock skew (>300s) emits clock_skew warning callback!
            val skewedJson = JSONObject(hostJson).put("seq", 9L).put("ts", nowSec - 900L).toString()
            val skewedEnv = RelayCrypto.encryptRelayPayload(skewedJson, code, pass)
            client.handleRawMessage("""{"event":"message","message":"$skewedEnv"}""")
            assertTrue(warnings.any { it.first == "clock_skew" })
            assertEquals(1, telemetryCalls.get())

            // Tampered GCM tag must be rejected!
            val envParts = encryptedEnv.split("|")
            val tamperedBytes = Base64.getDecoder().decode(envParts[2])
            tamperedBytes[tamperedBytes.lastIndex] = (tamperedBytes[tamperedBytes.lastIndex].toInt() xor 0x01).toByte()
            val tamperedFrame = """{"event":"message","message":"PSGCM2|${envParts[1]}|${Base64.getEncoder().encodeToString(tamperedBytes)}"}"""
            client.handleRawMessage(tamperedFrame)
            assertEquals(1, muteCalls.get())
            assertEquals(1, telemetryCalls.get())

            // Default allowLegacyPlaintext=false must reject plaintext PSRELAY
            val legacyExtended = RelayCrypto.formatRelayPacket(
                "host",
                "dir_state",
                "0;1;paused;120;600;Camera;95;1;1;Intro,Camera,Outro",
                auth
            )
            client.handleRawMessage(legacyExtended)
            assertEquals(1, telemetryCalls.get())

            // Opt-in allowLegacyPlaintext=true parses extended legacy dir_state telemetry cleanly
            val optInClient = RelayClient(
                httpClient = httpClient,
                pairingCode = code,
                password = pass,
                allowLegacyPlaintext = true,
                callbacks = object : RelaySessionCallbacks {
                    override fun onRelayConnected() = Unit
                    override fun onRelayAuthFailed() = Unit
                    override fun onRelayMuteState(muted: Boolean) = Unit
                    override fun onRelayTelemetryState(telemetry: RelayTelemetryState) {
                        telemetryCalls.incrementAndGet()
                        lastTelemetry.set(telemetry)
                    }
                    override fun onCloseRemoteSignal() = Unit
                    override fun onRelayDisconnected(reason: String) = Unit
                }
            )
            optInClient.handleRawMessage(legacyExtended)
            assertEquals(2, telemetryCalls.get())
            val tel2 = lastTelemetry.get()
            assertEquals(95, tel2.recSeconds)
            assertTrue(tel2.streamDropWarn)
            assertTrue(tel2.voiceWhileMuted)
            assertEquals(listOf("Intro", "Camera", "Outro"), tel2.scenes)
        } finally {
            httpClient.dispatcher.executorService.shutdown()
            httpClient.connectionPool.evictAll()
        }
    }
}
