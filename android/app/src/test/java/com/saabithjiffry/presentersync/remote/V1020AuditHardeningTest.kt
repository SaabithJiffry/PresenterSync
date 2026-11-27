package com.saabithjiffry.presentersync.remote

import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import android.view.KeyEvent
import com.saabithjiffry.presentersync.remote.config.DeviceProfileMode
import com.saabithjiffry.presentersync.remote.config.NetworkMode
import com.saabithjiffry.presentersync.remote.config.QuickNudgePresetHelper
import com.saabithjiffry.presentersync.remote.config.RemoteConfig
import com.saabithjiffry.presentersync.remote.config.RemoteConfigStore
import com.saabithjiffry.presentersync.remote.config.SavedHostProfileCodec
import com.saabithjiffry.presentersync.remote.config.SecretCipher
import com.saabithjiffry.presentersync.remote.config.SecretVault
import com.saabithjiffry.presentersync.remote.network.BridgeTelemetryState
import com.saabithjiffry.presentersync.remote.network.ConnectionManager
import com.saabithjiffry.presentersync.remote.network.HostBridgeCallbacks
import com.saabithjiffry.presentersync.remote.network.HostBridgeClient
import com.saabithjiffry.presentersync.remote.network.ObsSessionCallbacks
import com.saabithjiffry.presentersync.remote.network.ObsWebSocketClient
import com.saabithjiffry.presentersync.remote.service.BackgroundMediaKeyMapper
import com.saabithjiffry.presentersync.remote.service.HdcpRecoveryPolicy
import com.saabithjiffry.presentersync.remote.ui.screens.buildSharePairingQrUri
import okhttp3.OkHttpClient
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

class V1020AuditHardeningTest {

    @Test
    fun managedRestrictions_appliesSessionPairingCodeAndDeviceProfileMode() {
        val ctx = InMemoryAppContext()
        val store = RemoteConfigStore(ctx)
        PresenterSyncRemoteApp.applyManagedRestrictionsToStore(
            store = store,
            hostAddress = "10.20.30.40",
            bridgePort = 4460,
            kioskPin = "4321",
            defaultRole = "podium",
            sessionPairingCode = "ab1-cd2",
            deviceProfileMode = "smartboard"
        )
        val updated = store.current
        assertEquals("10.20.30.40", updated.hostAddress)
        assertEquals(4460, updated.bridgePort)
        assertEquals("4321", updated.kioskPin)
        assertEquals("podium", updated.defaultRole)
        assertEquals("AB1-CD2", updated.sessionPairingCode)
        assertEquals(DeviceProfileMode.SMART_BOARD, updated.deviceProfileMode)
    }

    @Test
    fun quickNudgePresets_persistsAcrossReloadAndSavedProfiles() {
        val ctx = InMemoryAppContext()
        val store1 = RemoteConfigStore(ctx)
        store1.update {
            it.copy(
                hostAddress = "192.168.10.5",
                quickNudgePresets = "Check Mic | 2 Min Left | Wrap Up"
            )
        }
        val prof = store1.saveCurrentAsProfile("Room 101")
        assertEquals("Check Mic | 2 Min Left | Wrap Up", prof.quickNudgePresets)

        val store2 = RemoteConfigStore(ctx)
        assertEquals("Check Mic | 2 Min Left | Wrap Up", store2.current.quickNudgePresets)

        store2.update { it.copy(quickNudgePresets = "Temp Override") }
        val switched = store2.switchToProfile(prof.id)
        assertEquals("Check Mic | 2 Min Left | Wrap Up", switched?.quickNudgePresets)
        assertEquals("Check Mic | 2 Min Left | Wrap Up", store2.current.quickNudgePresets)

        val roundTripped = SavedHostProfileCodec.fromJsonString(SavedHostProfileCodec.toJsonString(listOf(prof)))
        assertEquals(1, roundTripped.size)
        assertEquals("Check Mic | 2 Min Left | Wrap Up", roundTripped.first().quickNudgePresets)
    }

    @Test
    fun secretVault_includesAndMigratesKioskPinOutOfPlaintextPrefs() {
        assertTrue(SecretVault.SECRET_KEYS.contains("kioskPin"))
        val legacy = MemSharedPreferences()
        val vaultPrefs = MemSharedPreferences()
        legacy.edit().putString("kioskPin", "9876").apply()

        val vault = SecretVault(
            vaultPrefs = vaultPrefs,
            legacyPrefs = legacy,
            cipher = object : SecretCipher {
                override fun encrypt(plain: String): String = "ENC:$plain"
                override fun decrypt(stored: String): String = stored.removePrefix("ENC:")
            }
        )
        assertEquals("9876", vault.getSecret("kioskPin"))
        assertFalse(legacy.contains("kioskPin"))
        assertEquals("ENC:9876", vaultPrefs.getString("kioskPin", ""))
    }

    @Test
    fun sharePairingQr_mapsSessionCodeSeparateFromWanCodeWithoutObsPassword() {
        val uri = buildSharePairingQrUri(
            initialConfig = RemoteConfig(obsPassword = "SuperSecretObsPass!"),
            networkMode = NetworkMode.INTERNET,
            hostAddress = "192.168.1.99",
            bridgePortStr = "4458",
            sessionCodeInput = "K7M-9P2",
            pairingCode = "PS-ABCD-1234",
            relayBaseUrl = "https://ntfy.sh",
            hostPortStr = "4455"
        )
        assertTrue(uri.contains("host=192.168.1.99"))
        assertTrue(uri.contains("code=K7M-9P2"))
        assertTrue(uri.contains("wan=PS-ABCD-1234"))
        assertFalse(uri.contains("obsPass"))
        assertFalse(uri.contains("SuperSecretObsPass"))
    }

    @Test
    fun backgroundMediaKeyMapper_respectsHotkeysSuspended() {
        val activeCfg = RemoteConfig(enableBackgroundMediaClicker = true, hotkeysSuspended = false)
        assertEquals(
            com.saabithjiffry.presentersync.remote.input.BubbleGestureAction.TOGGLE_MUTE,
            BackgroundMediaKeyMapper.resolveKeyAction(KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, activeCfg)
        )
        assertEquals(
            com.saabithjiffry.presentersync.remote.input.BubbleGestureAction.SLIDE_NEXT,
            BackgroundMediaKeyMapper.resolveVolumeStepAction(1, activeCfg)
        )

        val suspendedCfg = activeCfg.copy(hotkeysSuspended = true)
        assertNull(BackgroundMediaKeyMapper.resolveKeyAction(KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, suspendedCfg))
        assertNull(BackgroundMediaKeyMapper.resolveVolumeStepAction(1, suspendedCfg))
    }

    @Test
    fun hdcpRecoveryPolicy_firesOnlyWhenSettingEnabledOnScreenOrDisplayEvents() {
        val disabledCfg = RemoteConfig(hdmiHdcpRecoveryEnabled = false)
        assertFalse(HdcpRecoveryPolicy.shouldRecoverOnEvent(disabledCfg, HdcpRecoveryPolicy.EVENT_SCREEN_ON))
        assertFalse(HdcpRecoveryPolicy.shouldRecoverOnEvent(disabledCfg, HdcpRecoveryPolicy.EVENT_DISPLAY_CHANGED))

        val enabledCfg = RemoteConfig(hdmiHdcpRecoveryEnabled = true)
        assertTrue(HdcpRecoveryPolicy.shouldRecoverOnEvent(enabledCfg, HdcpRecoveryPolicy.EVENT_SCREEN_ON))
        assertTrue(HdcpRecoveryPolicy.shouldRecoverOnEvent(enabledCfg, HdcpRecoveryPolicy.EVENT_DISPLAY_CHANGED))
        assertTrue(HdcpRecoveryPolicy.shouldRecoverOnEvent(enabledCfg, HdcpRecoveryPolicy.EVENT_DISPLAY_ADDED))
        assertFalse(HdcpRecoveryPolicy.shouldRecoverOnEvent(enabledCfg, "other_event"))
    }

    @Test
    fun hostBridgeClient_firesOnBridgeDisconnectedAtMostOncePerConnection() {
        val server = MockWebServer()
        server.start()
        val client = OkHttpClient.Builder().build()
        val disconnectCount = AtomicInteger(0)
        val connectedLatch = CountDownLatch(1)
        val disconnectLatch = CountDownLatch(1)

        try {
            server.enqueue(MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
                override fun onMessage(webSocket: WebSocket, text: String) {
                    val obj = JSONObject(text)
                    if (obj.optString("type") == "auth") {
                        webSocket.send("""{"type":"auth_ok","protocolVersion":2,"hostBootId":"boot-1","stateSeq":1,"hostName":"PC","version":"10.2.0"}""")
                        webSocket.close(1000, "done")
                    }
                }
            }))

            val wsUrl = server.url("/ws").toString().replaceFirst("http://", "ws://")
            val bridge = HostBridgeClient(
                httpClient = client,
                wsBaseUrl = wsUrl,
                sessionToken = "tok",
                sessionCode = "ABC-123",
                deviceId = "dev1",
                deviceName = "Pixel",
                callbacks = object : HostBridgeCallbacks {
                    override fun onBridgeConnected(hostName: String) {
                        connectedLatch.countDown()
                    }
                    override fun onBridgeAuthFailed(reason: String) {}
                    override fun onMuteStateChanged(isMuted: Boolean, routingMode: Int, targetMicName: String) {}
                    override fun onCloseRemoteSignal() {}
                    override fun onBridgeDisconnected(reason: String) {
                        disconnectCount.incrementAndGet()
                        disconnectLatch.countDown()
                    }
                }
            )
            bridge.connect()
            assertTrue(connectedLatch.await(3, TimeUnit.SECONDS))
            assertTrue(disconnectLatch.await(3, TimeUnit.SECONDS))
            Thread.sleep(150)
            assertEquals(1, disconnectCount.get())
            bridge.close()
        } finally {
            client.dispatcher.executorService.shutdown()
            client.connectionPool.evictAll()
            runCatching { server.shutdown() }
        }
    }

    @Test
    fun obsWebSocketClient_sendsSetCurrentPreviewSceneForDirectObsFallback() {
        val server = MockWebServer()
        server.start()
        val client = OkHttpClient.Builder().build()
        val identifiedLatch = CountDownLatch(1)
        val previewReqLatch = CountDownLatch(1)
        val seenPreviewScene = AtomicReference("")

        try {
            server.enqueue(MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
                override fun onOpen(webSocket: WebSocket, response: Response) {
                    webSocket.send("""{"op":0,"d":{"obsWebSocketVersion":"5.3.0"}}""")
                }

                override fun onMessage(webSocket: WebSocket, text: String) {
                    val obj = JSONObject(text)
                    when (obj.optInt("op", -1)) {
                        1 -> {
                            webSocket.send("""{"op":2,"d":{"negotiatedRpcVersion":1}}""")
                        }
                        6 -> {
                            val d = obj.optJSONObject("d") ?: return
                            if (d.optString("requestType") == "SetCurrentPreviewScene") {
                                val scene = d.optJSONObject("requestData")?.optString("sceneName").orEmpty()
                                seenPreviewScene.set(scene)
                                previewReqLatch.countDown()
                            }
                        }
                    }
                }
            }))

            val wsUrl = server.url("/").toString().replaceFirst("http://", "ws://")
            val obs = ObsWebSocketClient(
                httpClient = client,
                wsUrl = wsUrl,
                password = "",
                targetMicName = "Mic/Aux",
                callbacks = object : ObsSessionCallbacks {
                    override fun onIdentified() {
                        identifiedLatch.countDown()
                    }
                    override fun onAuthFailed() {}
                    override fun onMuteStateChanged(muted: Boolean) {}
                    override fun onMicError() {}
                    override fun onMicRecovered() {}
                    override fun onCloseRemoteSignal() {}
                    override fun onDisconnected(reason: String) {}
                }
            )
            obs.connect()
            assertTrue(identifiedLatch.await(3, TimeUnit.SECONDS))
            assertTrue(obs.sendSetCurrentPreviewScene("Slides Deck"))
            assertTrue(previewReqLatch.await(3, TimeUnit.SECONDS))
            assertEquals("Slides Deck", seenPreviewScene.get())
            obs.close()
        } finally {
            client.dispatcher.executorService.shutdown()
            client.connectionPool.evictAll()
            runCatching { server.shutdown() }
        }
    }

    @Test
    fun connectionManager_disconnectResetsTransientTelemetryAndNudgesResolveCleanly() {
        val ctx = InMemoryAppContext()
        val store = RemoteConfigStore(ctx)
        val manager = ConnectionManager(context = ctx, configStore = store)
        manager.stop()
        val state = manager.uiState.value
        assertEquals(0, state.streamState)
        assertFalse(state.vcamActive)
        assertEquals(0, state.unreadChatCount)
        assertFalse(state.isPanic)
        assertFalse(state.panicUnmuteLocked)

        val resolved = QuickNudgePresetHelper.resolve("Custom 1 | Custom 2", listOf("Host 1"))
        assertEquals(listOf("Custom 1", "Custom 2"), resolved)
    }

    private class InMemoryAppContext : ContextWrapper(null) {
        private val prefsByName = LinkedHashMap<String, MemSharedPreferences>()
        override fun getApplicationContext(): Context = this
        override fun getSharedPreferences(name: String?, mode: Int): SharedPreferences {
            val key = name ?: "default"
            return prefsByName.getOrPut(key) { MemSharedPreferences() }
        }
    }

    private class MemSharedPreferences : SharedPreferences {
        private val store = LinkedHashMap<String, Any?>()
        override fun getAll(): MutableMap<String, *> = LinkedHashMap(store)
        override fun getString(key: String?, defValue: String?): String? = store[key] as? String ?: defValue
        @Suppress("UNCHECKED_CAST")
        override fun getStringSet(key: String?, defValues: MutableSet<String>?): MutableSet<String>? =
            (store[key] as? MutableSet<String>) ?: defValues
        override fun getInt(key: String?, defValue: Int): Int = store[key] as? Int ?: defValue
        override fun getLong(key: String?, defValue: Long): Long = store[key] as? Long ?: defValue
        override fun getFloat(key: String?, defValue: Float): Float = store[key] as? Float ?: defValue
        override fun getBoolean(key: String?, defValue: Boolean): Boolean = store[key] as? Boolean ?: defValue
        override fun contains(key: String?): Boolean = store.containsKey(key)
        override fun edit(): SharedPreferences.Editor = object : SharedPreferences.Editor {
            private val pending = LinkedHashMap<String, Any?>()
            private var clearFirst = false
            override fun putString(key: String?, value: String?) = apply { if (key != null) pending[key] = value }
            override fun putStringSet(key: String?, values: MutableSet<String>?) = apply {
                if (key != null) pending[key] = values?.toMutableSet()
            }
            override fun putInt(key: String?, value: Int) = apply { if (key != null) pending[key] = value }
            override fun putLong(key: String?, value: Long) = apply { if (key != null) pending[key] = value }
            override fun putFloat(key: String?, value: Float) = apply { if (key != null) pending[key] = value }
            override fun putBoolean(key: String?, value: Boolean) = apply { if (key != null) pending[key] = value }
            override fun remove(key: String?) = apply { if (key != null) pending[key] = null }
            override fun clear() = apply { clearFirst = true }
            override fun commit(): Boolean {
                apply()
                return true
            }
            override fun apply() {
                if (clearFirst) store.clear()
                for ((k, v) in pending) {
                    if (v == null) store.remove(k) else store[k] = v
                }
            }
        }
        override fun registerOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener?) {}
        override fun unregisterOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener?) {}
    }
}
