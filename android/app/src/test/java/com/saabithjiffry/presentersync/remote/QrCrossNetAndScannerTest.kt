package com.saabithjiffry.presentersync.remote

import com.saabithjiffry.presentersync.remote.config.DeepLinkParser
import com.saabithjiffry.presentersync.remote.config.NetworkMode
import com.saabithjiffry.presentersync.remote.config.PairingUriBuilder
import com.saabithjiffry.presentersync.remote.config.QrGalleryStorage
import com.saabithjiffry.presentersync.remote.config.QrImageDecoder
import com.saabithjiffry.presentersync.remote.config.RemoteConfig
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.ByteBuffer

class QrCrossNetAndScannerTest {

    @Test
    fun deepLinkParserSupportsCrossNetworkRelayAndHttpUrls() {
        val wanUri = "presentersync://connect?hosts=192.168.1.50,10.0.0.5&code=K9P-4X7&mode=internet&rc=PS-12AB-34CD&relay=https%3A%2F%2Frelay.custom.org&rpw=1"
        val parsedWan = DeepLinkParser.parse(wanUri)
        assertNotNull(parsedWan)
        assertEquals(NetworkMode.INTERNET, parsedWan!!.networkMode)
        assertEquals("PS-12AB-34CD", parsedWan.internetPairingCode)
        assertEquals("https://relay.custom.org", parsedWan.relayBaseUrl)
        assertTrue(parsedWan.requiresRelayPassword)
        assertEquals("", parsedWan.obsPassword)

        val httpUrl = "http://192.168.1.99:4456/?code=ABC-123&rc=PS-9900-AA11&mode=internet&rpw=1"
        val parsedHttp = DeepLinkParser.parse(httpUrl)
        assertNotNull(parsedHttp)
        assertEquals("192.168.1.99", parsedHttp!!.hostsCsv)
        assertEquals("ABC-123", parsedHttp.sessionCode)
        assertEquals("PS-9900-AA11", parsedHttp.internetPairingCode)
        assertEquals(NetworkMode.INTERNET, parsedHttp.networkMode)
        assertTrue(parsedHttp.requiresRelayPassword)

        val bareWan = DeepLinkParser.parse("ps-7788-zz99")
        assertNotNull(bareWan)
        assertEquals(NetworkMode.INTERNET, bareWan!!.networkMode)
        assertEquals("PS-7788-ZZ99", bareWan.internetPairingCode)

        assertNull(DeepLinkParser.parse("https://example.com/not-presentersync"))
    }

    @Test
    fun pairingUriBuilderNeverEmbedsObsPasswordC3AndEmitsRpwFlag() {
        val cfg = RemoteConfig(
            networkMode = NetworkMode.INTERNET,
            hostAddress = "192.168.1.50",
            hostPort = 4455,
            bridgePort = 4456,
            sessionPairingCode = "K9P-4X7",
            internetPairingCode = "PS-12AB-34CD",
            relayBaseUrl = "https://relay.custom.org",
            obsPassword = "MyTopSecretPassword!",
            targetMicName = "Mic/Aux"
        )
        val built = PairingUriBuilder.build(cfg)
        assertFalse("C3 violation: obsPassword leaked into URI", built.contains("MyTopSecretPassword"))
        assertFalse("C3 violation: pw= parameter present in URI", built.contains("&pw=") || built.contains("?pw="))
        assertTrue(built.contains("mode=internet"))
        assertTrue(built.contains("wan=PS-12AB-34CD"))
        assertTrue(built.contains("rpw=1"))
        assertTrue(built.contains("relay="))
        // Compact URI omits default bridge port and default relay while keeping explicit obsPort
        assertTrue(built.contains("obsPort=4455"))
        assertFalse(built.contains("bp=4456"))
        val roundTrip = DeepLinkParser.parse(built)
        assertNotNull(roundTrip)
        assertEquals("PS-12AB-34CD", roundTrip!!.internetPairingCode)
        assertEquals(NetworkMode.INTERNET, roundTrip.networkMode)
        assertTrue(roundTrip.requiresRelayPassword)
    }

    @Test
    fun yPlaneExtractorHandlesPaddedRowStrideAndPixelStrideSafely() {
        // Width 4, Height 3, rowStride 6 (2 padding bytes per row), pixelStride 1
        val width = 4
        val height = 3
        val rowStride = 6
        val buf = ByteBuffer.allocateDirect(rowStride * height)
        for (r in 0 until height) {
            for (c in 0 until width) {
                buf.put(r * rowStride + c, (r * 10 + c + 1).toByte())
            }
            buf.put(r * rowStride + 4, 0x7F.toByte())
            buf.put(r * rowStride + 5, 0x7F.toByte())
        }
        val tight = QrImageDecoder.extractTightYPlane(buf, width, height, rowStride, 1)
        assertNotNull(tight)
        assertEquals(width * height, tight!!.size)
        val expected = byteArrayOf(
            1, 2, 3, 4,
            11, 12, 13, 14,
            21, 22, 23, 24
        )
        assertArrayEquals(expected, tight)

        // Width 3, Height 2, pixelStride 2, rowStride 8
        val psBuf = ByteBuffer.allocateDirect(8 * 2)
        for (r in 0 until 2) {
            for (c in 0 until 3) {
                psBuf.put(r * 8 + c * 2, (r * 10 + c + 5).toByte())
                psBuf.put(r * 8 + c * 2 + 1, 0x55.toByte())
            }
        }
        val tightPs = QrImageDecoder.extractTightYPlane(psBuf, 3, 2, 8, 2)
        assertNotNull(tightPs)
        assertArrayEquals(byteArrayOf(5, 6, 7, 15, 16, 17), tightPs)
    }

    @Test
    fun galleryStorageConstantsMatchIsoQuietZoneAndHighResSpec() {
        assertEquals(1024, QrGalleryStorage.DEFAULT_QR_SIZE_PX)
        assertEquals(4, QrGalleryStorage.ISO_QUIET_ZONE_MODULES)
    }
}
