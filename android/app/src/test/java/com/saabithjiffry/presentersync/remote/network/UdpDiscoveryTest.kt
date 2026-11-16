package com.saabithjiffry.presentersync.remote.network

import com.saabithjiffry.presentersync.remote.config.AppConstants
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.util.concurrent.atomic.AtomicBoolean

class UdpDiscoveryTest {

    @Test
    fun parsePublicBeaconJsonRejectsMalformedOrNonV1Payloads() {
        assertNull(UdpHostDiscoveryClient.parsePublicBeaconJson("PSYNC_OFFER|PC|4456|4455|6.6.0|1", "192.168.1.20"))
        assertNull(UdpHostDiscoveryClient.parsePublicBeaconJson("""{"proto":"PS_DISCOVER_V1","hostUuid":"","bridgePort":4456}""", "192.168.1.20"))
        assertNull(UdpHostDiscoveryClient.parsePublicBeaconJson("""{"proto":"PS_DISCOVER_V1","hostUuid":"uuid-1","bridgePort":0}""", "192.168.1.20"))

        val beacon = """{"proto":"PS_DISCOVER_V1","hostUuid":"uuid-room-42","deviceName":"Lecture-PC","bridgePort":4456,"obsPort":4455,"networkMode":"LAN","audioRoutingMode":1,"version":"6.6.0"}"""
        val parsed = UdpHostDiscoveryClient.parsePublicBeaconJson(beacon, "192.168.1.88")
        assertNotNull(parsed)
        assertEquals("uuid-room-42", parsed!!.hostUuid)
        assertEquals("Lecture-PC", parsed.deviceName)
        assertEquals("192.168.1.88", parsed.hostIp)
        assertEquals(4456, parsed.bridgePort)
        assertEquals(4455, parsed.obsPort)
        assertEquals("Lecture-PC • :4456", parsed.displayTitle)
    }

    @Test
    fun scanClassroomHostsDiscoversLocalhostUdpResponderWithoutSecrets() {
        val stop = AtomicBoolean(false)
        val serverSock = DatagramSocket(0, java.net.InetAddress.getByName("127.0.0.1")).apply { soTimeout = 1200 }
        val port = serverSock.localPort
        val responder = Thread {
            val buf = ByteArray(512)
            while (!stop.get()) {
                try {
                    val pkt = DatagramPacket(buf, buf.size)
                    serverSock.receive(pkt)
                    val msg = String(pkt.data, pkt.offset, pkt.length, Charsets.UTF_8).trim()
                    if (msg == AppConstants.UDP_DISCOVER_V1_PROBE) {
                        val json = """{"proto":"PS_DISCOVER_V1","hostUuid":"uuid-lab-101","deviceName":"LabHost","bridgePort":4456,"obsPort":4455,"networkMode":"LAN","audioRoutingMode":1,"version":"6.6.0"}"""
                        assertFalse(json.contains("obsPassword", ignoreCase = true))
                        assertFalse(json.contains("sessionToken", ignoreCase = true))
                        assertFalse(json.contains("sessionPairingCode", ignoreCase = true))
                        val replyBytes = json.toByteArray(Charsets.UTF_8)
                        serverSock.send(DatagramPacket(replyBytes, replyBytes.size, pkt.address, pkt.port))
                    }
                } catch (_: Exception) {
                }
            }
        }
        responder.start()

        try {
            val found = kotlinx.coroutines.runBlocking {
                UdpHostDiscoveryClient.scanClassroomHosts(
                    context = null,
                    discoverPort = port,
                    timeoutMs = 500L,
                    extraTargets = listOf("127.0.0.1")
                )
            }
            assertEquals(1, found.size)
            assertEquals("uuid-lab-101", found[0].hostUuid)
            assertEquals("LabHost", found[0].deviceName)
            assertEquals("127.0.0.1", found[0].hostIp)
        } finally {
            stop.set(true)
            runCatching { serverSock.close() }
            responder.join(1000)
        }
    }

    @Test
    fun followHostUuidIpShiftPrependsNewIpAndDeduplicatesUpToFour() {
        val beacons = listOf(
            DiscoveredPublicHost("other-uuid", "OtherRoom", "192.168.1.10", 4456, 4455, "LAN", 1, "6.6.0"),
            DiscoveredPublicHost("UUID-TARGET-99", "MainLaptop", "10.0.4.77", 4458, 4455, "LAN", 1, "6.6.0")
        )
        val noChange = UdpHostDiscoveryClient.followHostUuidIpShift(
            currentHostsCsv = "10.0.4.77, STUDIO.local",
            pairedHostUuid = "uuid-target-99",
            beacons = beacons,
            currentBridgePort = 4458
        )
        assertNull("Identical first host and bridge port should not churn config", noChange)

        val shifted = UdpHostDiscoveryClient.followHostUuidIpShift(
            currentHostsCsv = "192.168.1.42, 10.0.4.77, h3.local, h4.local, h5.local",
            pairedHostUuid = "uuid-target-99",
            beacons = beacons,
            currentBridgePort = 4456
        )
        assertNotNull(shifted)
        assertEquals("10.0.4.77, 192.168.1.42, h3.local, h4.local", shifted!!.first)
        assertEquals(4458, shifted.second)
    }
}
