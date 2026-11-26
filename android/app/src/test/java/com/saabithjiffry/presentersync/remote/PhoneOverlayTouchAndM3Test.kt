package com.saabithjiffry.presentersync.remote

import android.content.ContextWrapper
import android.content.SharedPreferences
import android.view.MotionEvent
import com.saabithjiffry.presentersync.remote.config.AppConstants
import com.saabithjiffry.presentersync.remote.config.FormFactorClass
import com.saabithjiffry.presentersync.remote.config.PairingUriBuilder
import com.saabithjiffry.presentersync.remote.config.RemoteConfig
import com.saabithjiffry.presentersync.remote.config.RemoteConfigStore
import com.saabithjiffry.presentersync.remote.input.BubbleGestureConfig
import com.saabithjiffry.presentersync.remote.network.ApkSelfInstaller
import com.saabithjiffry.presentersync.remote.network.HostBridgeCallbacks
import com.saabithjiffry.presentersync.remote.network.HostBridgeClient
import com.saabithjiffry.presentersync.remote.ui.overlay.ScreenBoundsCalculator
import com.saabithjiffry.presentersync.remote.util.DiagnosticLogger
import okhttp3.OkHttpClient
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

class PhoneOverlayTouchAndM3Test {

    @Test
    fun phoneGestureDefaultsAndPalmFilterPreventDroppedPhoneTaps() {
        assertEquals(14f, AppConstants.SHORT_TAP_MAX_SLOP_DP, 0.01f)
        assertEquals(320L, BubbleGestureConfig().doubleTapTimeoutMs)

        // Finger resting at 130px on phone must NEVER be rejected as palm (#4)
        assertFalse(
            ScreenBoundsCalculator.isPalmTouchForDevice(
                toolType = MotionEvent.TOOL_TYPE_FINGER,
                touchMajorPx = 130f,
                density = 2.5f,
                formFactor = FormFactorClass.COMPACT_PHONE
            )
        )
        // Explicit TOOL_TYPE_PALM (5) is still rejected everywhere
        assertTrue(
            ScreenBoundsCalculator.isPalmTouchForDevice(
                toolType = 5,
                touchMajorPx = 20f,
                density = 2.5f,
                formFactor = FormFactorClass.COMPACT_PHONE
            )
        )
        // Large board still blocks genuine > 160dp palm contact
        assertTrue(
            ScreenBoundsCalculator.isPalmTouchForDevice(
                toolType = MotionEvent.TOOL_TYPE_FINGER,
                touchMajorPx = 300f,
                density = 1.5f,
                formFactor = FormFactorClass.LARGE_BOARD
            )
        )
    }

    @Test
    fun pairingUriOmitsObsPassAndLoggerRedactsGcmV2AndKioskPin() {
        val uri = PairingUriBuilder.build(
            RemoteConfig(
                hostAddress = "10.0.0.5",
                bridgePort = 4456,
                sessionPairingCode = "ABC-123",
                obsPassword = "SuperSecretObsPassword!"
            )
        )
        assertFalse(uri.contains("obsPass="))
        assertFalse(uri.contains("SuperSecretObsPassword"))

        val redacted = DiagnosticLogger.scrubSecrets(
            """{"kioskPin":"9988","gcm":"PSGCM2|ABCDEFGH1234==|ZYXWVUTSRQPO9876=="}"""
        )
        assertFalse(redacted.contains("9988"))
        assertFalse(redacted.contains("ABCDEFGH1234"))
        assertTrue(redacted.contains("PSGCM2|[REDACTED]"))
        assertTrue(redacted.contains("[REDACTED]"))
    }

    @Test
    fun remoteConfigPersistsDefaultRoleAndDirectObsPolicyFlag() {
        val ctx = InMemoryContext()
        val store = RemoteConfigStore(ctx)
        store.update {
            it.copy(defaultRole = "Director", directObsFallbackAllowed = false)
        }
        val reloaded = RemoteConfigStore(ctx).current
        assertEquals("Director", reloaded.defaultRole)
        assertFalse(reloaded.directObsFallbackAllowed)
    }

    @Test
    fun apkSelfInstallerFailsClosedWhenSha256SumsUrlIsMissing() {
        var threwNull = false
        try {
            ApkSelfInstaller.requireSha256SumsUrl(null)
        } catch (_: IOException) {
            threwNull = true
        }
        assertTrue(threwNull)

        var threwBlank = false
        try {
            ApkSelfInstaller.requireSha256SumsUrl("   ")
        } catch (_: IOException) {
            threwBlank = true
        }
        assertTrue(threwBlank)

        assertEquals(
            "https://example.com/SHA256SUMS.txt",
            ApkSelfInstaller.requireSha256SumsUrl("https://example.com/SHA256SUMS.txt")
        )
    }

    @Test
    fun hostBridgeClientParsesNudgeMetadataFlashPillSessionResetAndSendsResetScene() {
        val server = MockWebServer()
        val authReceived = AtomicReference("")
        val resetReceived = AtomicReference("")
        val serverDone = CountDownLatch(2)
        server.enqueue(MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
            override fun onMessage(webSocket: WebSocket, text: String) {
                if (text.contains("\"type\":\"auth\"")) {
                    authReceived.set(text)
                    serverDone.countDown()
                    webSocket.send(
                        """{"type":"auth_ok","hostName":"TestHost","role":"Director","obsFallback":{"port":4455,"targetMic":"Mic/Aux","password":"","directObsAllowed":false}}"""
                    )
                    webSocket.send("""{"type":"flash_pill","durationMs":1500}""")
                    webSocket.send(
                        """{"type":"stage_nudge","nudgeId":"ndg-42","message":"Wrap up","sender":"Desk","urgency":"urgent","requiresAck":true}"""
                    )
                    webSocket.send("""{"type":"session_reset"}""")
                } else if (text.contains("\"type\":\"reset_active_scene\"")) {
                    resetReceived.set(text)
                    serverDone.countDown()
                }
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {}
        }))
        server.start()
        val clientHttp = OkHttpClient()
        var clientRef: HostBridgeClient? = null
        try {
            val callbackLatch = CountDownLatch(5)
            val gotDirectObsAllowed = AtomicReference(true)
            val gotFlashDur = AtomicReference(0L)
            val gotReset = AtomicReference(false)
            val gotNudgeId = AtomicReference("")
            val gotRequiresAck = AtomicReference(false)

            val client = HostBridgeClient(
                httpClient = clientHttp,
                wsBaseUrl = "ws://127.0.0.1:${server.port}/ws",
                sessionToken = "tok-1",
                sessionCode = "AAA-111",
                deviceId = "dev-test",
                deviceName = "Pixel",
                requestedRole = "Presenter",
                callbacks = object : HostBridgeCallbacks {
                    override fun onBridgeConnected(hostName: String) {
                        clientRef?.sendResetActiveScene("test")
                        callbackLatch.countDown()
                    }
                    override fun onObsFallbackUpdated(port: Int, targetMic: String, password: String, directObsAllowed: Boolean) {
                        gotDirectObsAllowed.set(directObsAllowed)
                        callbackLatch.countDown()
                    }
                    override fun onBridgeFlashPill(durationMs: Long) {
                        gotFlashDur.set(durationMs)
                        callbackLatch.countDown()
                    }
                    override fun onStageNudgeReceived(
                        message: String,
                        sender: String,
                        accentHex: String,
                        nudgeId: String,
                        urgency: String,
                        requiresAck: Boolean
                    ) {
                        gotNudgeId.set(nudgeId)
                        gotRequiresAck.set(requiresAck)
                        callbackLatch.countDown()
                    }
                    override fun onBridgeSessionReset() {
                        gotReset.set(true)
                        callbackLatch.countDown()
                    }
                    override fun onBridgeAuthFailed(reason: String) {}
                    override fun onMuteStateChanged(isMuted: Boolean, routingMode: Int, targetMicName: String) {}
                    override fun onCloseRemoteSignal() {}
                    override fun onBridgeDisconnected(reason: String) {}
                }
            )
            clientRef = client
            client.connect()

            assertTrue(callbackLatch.await(5, TimeUnit.SECONDS))
            assertTrue(serverDone.await(5, TimeUnit.SECONDS))
            assertTrue(authReceived.get().contains("\"requestedRole\":\"Presenter\""))
            assertTrue(resetReceived.get().contains("\"type\":\"reset_active_scene\""))
            assertFalse(gotDirectObsAllowed.get())
            assertEquals(1500L, gotFlashDur.get())
            assertEquals("ndg-42", gotNudgeId.get())
            assertTrue(gotRequiresAck.get())
            assertTrue(gotReset.get())
            client.close()
        } finally {
            clientHttp.dispatcher.executorService.shutdown()
            clientHttp.connectionPool.evictAll()
            runCatching { server.shutdown() }
        }
    }

    private class InMemoryContext : ContextWrapper(null) {
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
