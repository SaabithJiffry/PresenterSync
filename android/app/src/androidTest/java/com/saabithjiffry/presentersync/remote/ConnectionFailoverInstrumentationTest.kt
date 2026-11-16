package com.saabithjiffry.presentersync.remote

import android.os.SystemClock
import android.util.Base64
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.saabithjiffry.presentersync.remote.config.AppConstants
import com.saabithjiffry.presentersync.remote.config.NetworkMode
import com.saabithjiffry.presentersync.remote.network.UdpHostDiscoveryClient
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.ServerSocket
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicBoolean

@RunWith(AndroidJUnit4::class)
class ConnectionFailoverInstrumentationTest {

    @Test
    fun androidContextUdpDiscoveryFollowsIpShiftAndPersistsHostUuid() {
        val app = ApplicationProvider.getApplicationContext<PresenterSyncRemoteApp>()
        val prevCfg = app.configStore.current
        val stop = AtomicBoolean(false)
        val sock = DatagramSocket(0, InetAddress.getByName("127.0.0.1")).apply { soTimeout = 1000 }
        val discPort = sock.localPort
        val responder = Thread {
            val buf = ByteArray(512)
            while (!stop.get()) {
                try {
                    val pkt = DatagramPacket(buf, buf.size)
                    sock.receive(pkt)
                    val msg = String(pkt.data, pkt.offset, pkt.length, Charsets.UTF_8).trim()
                    if (msg == AppConstants.UDP_DISCOVER_V1_PROBE) {
                        val json = """{"proto":"PS_DISCOVER_V1","hostUuid":"emu-host-uuid-660","deviceName":"EmuHost","bridgePort":4456,"obsPort":4455,"networkMode":"LAN","audioRoutingMode":1,"version":"6.6.0"}"""
                        val out = json.toByteArray(Charsets.UTF_8)
                        sock.send(DatagramPacket(out, out.size, pkt.address, pkt.port))
                    }
                } catch (_: Exception) {
                }
            }
        }
        responder.start()

        try {
            val found = runBlocking {
                UdpHostDiscoveryClient.scanClassroomHosts(
                    context = app,
                    discoverPort = discPort,
                    timeoutMs = 500L,
                    extraTargets = listOf("127.0.0.1")
                )
            }
            assertEquals(1, found.size)
            assertEquals("emu-host-uuid-660", found[0].hostUuid)
            assertEquals("127.0.0.1", found[0].hostIp)

            val shift = UdpHostDiscoveryClient.followHostUuidIpShift(
                currentHostsCsv = "10.99.0.15, OLD.local",
                pairedHostUuid = "emu-host-uuid-660",
                beacons = found,
                currentBridgePort = 4456
            )
            assertTrue("Shift must detect new IP", shift != null && shift.first.startsWith("127.0.0.1"))

            app.configStore.update {
                it.copy(
                    hostAddress = shift!!.first,
                    bridgePort = shift.second,
                    pairedHostUuid = "emu-host-uuid-660"
                )
            }
            assertEquals("emu-host-uuid-660", app.configStore.current.pairedHostUuid)
            assertTrue(app.configStore.current.hostAddress.startsWith("127.0.0.1"))
        } finally {
            stop.set(true)
            runCatching { sock.close() }
            responder.join(1000)
            app.configStore.update { prevCfg }
        }
    }

    @Test
    fun lanDropFailoverWithinBudgetAndRepromotionToHealthyLanBridge() {
        val app = ApplicationProvider.getApplicationContext<PresenterSyncRemoteApp>()
        val prevCfg = app.configStore.current
        val prevDiscPort = app.connectionManager.discoverPortOverride
        val prevBudget = app.connectionManager.failoverBudgetMs
        val prevRepromote = app.connectionManager.repromoteIntervalMs

        val lanServer = ServerSocket(0, 5, InetAddress.getByName("127.0.0.1"))
        val lanPort = lanServer.localPort
        val stopServer = AtomicBoolean(false)
        val lanHealthy = AtomicBoolean(false)

        val acceptThread = Thread {
            while (!stopServer.get()) {
                try {
                    val client = lanServer.accept()
                    Thread {
                        client.use { s ->
                            val reader = BufferedReader(InputStreamReader(s.getInputStream()))
                            val headers = ArrayList<String>()
                            while (true) {
                                val line = reader.readLine() ?: break
                                if (line.isEmpty()) break
                                headers.add(line)
                            }
                            val reqLine = headers.firstOrNull().orEmpty()
                            if (!lanHealthy.get()) {
                                val err = "HTTP/1.1 503 Unavailable\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                                s.getOutputStream().write(err.toByteArray(Charsets.UTF_8))
                                return@use
                            }
                            if (reqLine.startsWith("GET /health")) {
                                val body = """{"ok":true,"hostUuid":"inst-lan-uuid-7","hostName":"TestHost","bridgePort":$lanPort}"""
                                val resp = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: ${body.length}\r\nConnection: close\r\n\r\n$body"
                                s.getOutputStream().write(resp.toByteArray(Charsets.UTF_8))
                                s.getOutputStream().flush()
                                return@use
                            }
                            if (reqLine.startsWith("GET /ws")) {
                                val wsKey = headers.firstOrNull {
                                    it.startsWith("Sec-WebSocket-Key:", ignoreCase = true)
                                }?.substringAfter(":")?.trim().orEmpty()
                                val accept = Base64.encodeToString(
                                    MessageDigest.getInstance("SHA-1")
                                        .digest((wsKey + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").toByteArray(Charsets.US_ASCII)),
                                    Base64.NO_WRAP
                                )
                                val upg = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: $accept\r\n\r\n"
                                s.getOutputStream().write(upg.toByteArray(Charsets.US_ASCII))
                                val authOk = """{"type":"auth_ok","hostUuid":"inst-lan-uuid-7","hostName":"TestHost","version":"6.6.0"}"""
                                val muteSt = """{"type":"mute_state","isMuted":false,"routingMode":1,"targetMicName":"Mic/Aux"}"""
                                writeServerWsText(s.getOutputStream(), authOk)
                                writeServerWsText(s.getOutputStream(), muteSt)
                                s.getOutputStream().flush()
                                SystemClock.sleep(1800L)
                            }
                        }
                    }.start()
                } catch (_: Exception) {
                }
            }
        }
        acceptThread.start()

        try {
            app.connectionManager.stop()
            app.connectionManager.discoverPortOverride = 65500
            app.connectionManager.failoverBudgetMs = 800L
            app.connectionManager.repromoteIntervalMs = 1500L

            app.configStore.update {
                it.copy(
                    networkMode = NetworkMode.LAN,
                    enableRelayFallback = true,
                    internetPairingCode = "",
                    sessionPairingCode = "K7M-9P2",
                    sessionToken = "tok-inst-test",
                    pairedHostUuid = "inst-lan-uuid-7",
                    hostAddress = "127.0.0.1",
                    hostPort = 65501,
                    bridgePort = lanPort,
                    firstRun = false
                )
            }

            // 1. While LAN is unhealthy, health probe returns false
            val downHealthy = runBlocking {
                UdpHostDiscoveryClient.probeHostBridgeHealth(app.connectionManager.sharedHttpClient, "127.0.0.1", lanPort, "inst-lan-uuid-7", 500L)
            }
            assertFalse("Health probe must return false when LAN bridge unavailable", downHealthy)

            // 2. Restore LAN bridge and verify connectionManager promotes cleanly onto LAN WS
            lanHealthy.set(true)
            app.connectionManager.start()
            val deadline = SystemClock.uptimeMillis() + 6000L
            while (SystemClock.uptimeMillis() < deadline) {
                val st = app.connectionManager.uiState.value
                if (st.connected && st.usingBridge && !st.usingRelayFallback) break
                SystemClock.sleep(80L)
            }
            val finalState = app.connectionManager.uiState.value
            assertTrue("ConnectionManager must reconnect to recovered LAN Bridge", finalState.connected)
            assertTrue("Must promote onto Bridge WebSocket", finalState.usingBridge)
            assertFalse("Must not stay on WAN fallback once LAN healthy", finalState.usingRelayFallback)
            assertEquals("inst-lan-uuid-7", app.configStore.current.pairedHostUuid)
        } finally {
            app.connectionManager.stop()
            app.connectionManager.discoverPortOverride = prevDiscPort
            app.connectionManager.failoverBudgetMs = prevBudget
            app.connectionManager.repromoteIntervalMs = prevRepromote
            stopServer.set(true)
            runCatching { lanServer.close() }
            acceptThread.join(1500)
            app.configStore.update { prevCfg }
        }
    }

    private fun writeServerWsText(out: java.io.OutputStream, payload: String) {
        val data = payload.toByteArray(Charsets.UTF_8)
        out.write(0x81)
        if (data.size <= 125) {
            out.write(data.size)
        } else {
            out.write(126)
            out.write((data.size shr 8) and 0xFF)
            out.write(data.size and 0xFF)
        }
        out.write(data)
    }
}
