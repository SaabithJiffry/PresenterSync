package com.saabithjiffry.presentersync.remote.network

import kotlinx.coroutines.test.runTest
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.net.DatagramPacket
import java.net.DatagramSocket

class SessionPairingClientTest {
    private lateinit var server: MockWebServer
    private lateinit var httpClient: OkHttpClient

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
        httpClient = OkHttpClient.Builder().build()
    }

    @After
    fun tearDown() {
        httpClient.dispatcher.executorService.shutdown()
        httpClient.connectionPool.evictAll()
        runCatching { server.shutdown() }
    }

    @Test
    fun normalizesCodesAndDetectsWanVsLan() {
        assertEquals("K7M9P2", SessionPairingClient.normalizeCode(" k7m - 9p2 "))
        assertTrue(SessionPairingClient.isWanRelayCode("PS-ABCD-1234"))
        assertFalse(SessionPairingClient.isWanRelayCode("K7M-9P2"))
    }

    @Test
    fun discoversHostOverUdpLoopbackAndPairsOverHttp() = runTest {
        val mockUdpSocket = DatagramSocket(0)
        val udpPort = mockUdpSocket.localPort
        val responderThread = Thread {
            val buf = ByteArray(512)
            val pkt = DatagramPacket(buf, buf.size)
            mockUdpSocket.soTimeout = 3000
            runCatching {
                mockUdpSocket.receive(pkt)
                val msg = String(pkt.data, pkt.offset, pkt.length, Charsets.UTF_8)
                if (msg.startsWith("PSYNC_DISCOVER|K7M9P2|")) {
                    val offer = "PSYNC_OFFER|STUDIO-PC|${server.port}|4455|4.7.0|2".toByteArray(Charsets.UTF_8)
                    mockUdpSocket.send(DatagramPacket(offer, offer.size, pkt.address, pkt.port))
                }
            }
            mockUdpSocket.close()
        }
        responderThread.start()

        val discovered = SessionPairingClient.discoverHostOnLan(
            context = null,
            sessionCode = "K7M-9P2",
            udpPort = udpPort,
            timeoutMs = 1500L,
            extraTargets = listOf("127.0.0.1"),
            deviceId = "test-board"
        )
        responderThread.join(2000)

        assertNotNull(discovered)
        assertEquals("STUDIO-PC", discovered!!.hostName)
        assertEquals(server.port, discovered.tcpPort)

        server.enqueue(
            MockResponse().setResponseCode(200).setBody(
                """{"ok":true,"hostName":"STUDIO-PC","version":"4.7.0","bridgePort":4456,"obsPort":4455,"obsPassword":"pw","targetMicName":"Mic/Aux","routingMode":2,"conferencingApp":"Zoom","isMuted":true,"internetPairingCode":"PS-XYZ-111","sessionToken":"tok123","ips":["192.168.1.50","10.0.0.5"],"mdns":"STUDIO-PC.local"}"""
            )
        )

        val pairRes = SessionPairingClient.pairWithHost(
            httpClient = httpClient,
            hostIp = "127.0.0.1",
            bridgePort = server.port,
            sessionCode = "K7M-9P2",
            deviceId = "test-board",
            deviceName = "Board 75"
        )

        assertTrue(pairRes is PairingResult.Success)
        val b = (pairRes as PairingResult.Success).bundle
        assertEquals("tok123", b.sessionToken)
        assertEquals("pw", b.obsPassword)
        assertEquals(2, b.routingMode)
        assertEquals(true, b.isMuted)
        assertEquals(
            "127.0.0.1, 192.168.1.50, 10.0.0.5, STUDIO-PC.local",
            SessionPairingClient.buildCandidateAddressList("127.0.0.1", b)
        )
    }

    @Test
    fun parsesRateLimit429AndAuth401Cleanly() {
        val r401 = SessionPairingClient.parsePairResponse("192.168.1.5", 401, """{"ok":false}""")
        assertTrue(r401 is PairingResult.Error)
        assertTrue((r401 as PairingResult.Error).message.contains("Invalid Session Code"))

        val r429 = SessionPairingClient.parsePairResponse("192.168.1.5", 429, """{"ok":false,"error":"Too many invalid pairing attempts"}""")
        assertTrue(r429 is PairingResult.Error)
        assertTrue((r429 as PairingResult.Error).message.contains("Too many"))
    }
}
