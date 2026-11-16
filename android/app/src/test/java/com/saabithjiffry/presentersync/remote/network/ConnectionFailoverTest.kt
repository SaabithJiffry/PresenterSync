package com.saabithjiffry.presentersync.remote.network

import com.saabithjiffry.presentersync.remote.config.NetworkMode
import com.saabithjiffry.presentersync.remote.config.RemoteConfig
import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.ServerSocket
import java.util.concurrent.TimeUnit

class ConnectionFailoverTest {

    @Test
    fun failoverPolicyBoundsLanBudgetWithin6SecondsAndAllowsWanRepromotion() {
        val cfgReady = RemoteConfig(
            networkMode = NetworkMode.LAN,
            enableRelayFallback = true,
            internetPairingCode = "PS-1234-5678",
            hostAddress = "192.168.1.50"
        )
        assertFalse(FailoverPolicy.shouldFallbackToWan(cfgReady, elapsedLanMs = 1200L, budgetMs = 5500L))
        assertTrue(FailoverPolicy.shouldFallbackToWan(cfgReady, elapsedLanMs = 5500L, budgetMs = 5500L))

        val cfgNoFallback = cfgReady.copy(enableRelayFallback = false)
        assertFalse(FailoverPolicy.shouldFallbackToWan(cfgNoFallback, elapsedLanMs = 9000L, budgetMs = 5500L))

        assertEquals(3500L, FailoverPolicy.perCandidateBudgetRemainingMs(1000L, 3000L, 5500L))
        assertEquals(0L, FailoverPolicy.perCandidateBudgetRemainingMs(1000L, 9000L, 5500L))

        assertTrue(FailoverPolicy.canRepromoteToLan(cfgReady, usingRelayFallback = true))
        assertFalse(FailoverPolicy.canRepromoteToLan(cfgReady, usingRelayFallback = false))
        assertFalse(FailoverPolicy.canRepromoteToLan(cfgReady.copy(hostAddress = "", pairedHostUuid = ""), usingRelayFallback = true))
    }

    @Test
    fun probeHostBridgeHealthVerifiesExpectedHostUuidStrictly() {
        val server = ServerSocket(0)
        val port = server.localPort
        val worker = Thread {
            repeat(2) {
                runCatching {
                    server.accept().use { sock ->
                        val reader = BufferedReader(InputStreamReader(sock.getInputStream()))
                        while (true) {
                            val line = reader.readLine() ?: break
                            if (line.isEmpty()) break
                        }
                        val body = """{"ok":true,"hostUuid":"uuid-classroom-1","hostName":"Room101","bridgePort":$port}"""
                        val resp = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: ${body.length}\r\nConnection: close\r\n\r\n$body"
                        sock.getOutputStream().write(resp.toByteArray(Charsets.UTF_8))
                        sock.getOutputStream().flush()
                    }
                }
            }
        }
        worker.start()

        try {
            val client = OkHttpClient.Builder()
                .connectTimeout(1, TimeUnit.SECONDS)
                .build()
            val okMatch = runBlocking {
                UdpHostDiscoveryClient.probeHostBridgeHealth(client, "127.0.0.1", port, expectedHostUuid = "uuid-classroom-1")
            }
            val okMismatch = runBlocking {
                UdpHostDiscoveryClient.probeHostBridgeHealth(client, "127.0.0.1", port, expectedHostUuid = "uuid-other-host")
            }
            assertTrue("Matching hostUuid health probe must succeed", okMatch)
            assertFalse("Mismatched hostUuid health probe must reject wrong host", okMismatch)
        } finally {
            runCatching { server.close() }
            worker.join(1500)
        }
    }
}
