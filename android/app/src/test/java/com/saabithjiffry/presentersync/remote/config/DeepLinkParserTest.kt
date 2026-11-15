package com.saabithjiffry.presentersync.remote.config

import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.MultiFormatReader
import com.google.zxing.RGBLuminanceSource
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.common.HybridBinarizer
import com.google.zxing.qrcode.QRCodeWriter
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class DeepLinkParserTest {

    @Test
    fun parsesPresentersyncDeepLinkUri() {
        val uri = "presentersync://connect?hosts=STUDIO-PC.local,192.168.1.50&port=4455&bp=4456&code=k9p4x7&mic=Mic%2FAux&mode=lan&pw=Pass%20123&rc=ps-12ab-34cd"
        val parsed = DeepLinkParser.parse(uri)
        assertNotNull(parsed)
        assertEquals("STUDIO-PC.local,192.168.1.50", parsed!!.hostsCsv)
        assertEquals(4455, parsed.obsPort)
        assertEquals(4456, parsed.bridgePort)
        assertEquals("K9P-4X7", parsed.sessionCode)
        assertEquals("Mic/Aux", parsed.targetMicName)
        assertEquals(NetworkMode.LAN, parsed.networkMode)
        assertEquals("Pass 123", parsed.obsPassword)
        assertEquals("PS-12AB-34CD", parsed.internetPairingCode)
    }

    @Test
    fun parsesJsonAndRejectsInvalidSchemes() {
        val json = """{"hosts":"10.0.0.5","port":4455,"bp":4456,"code":"ABC-DEF","mode":"internet","rc":"PS-9999-1111"}"""
        val parsed = DeepLinkParser.parse(json)
        assertNotNull(parsed)
        assertEquals(NetworkMode.INTERNET, parsed!!.networkMode)
        assertEquals("ABC-DEF", parsed.sessionCode)

        assertNull(DeepLinkParser.parse("https://example.com/not-presentersync"))
        assertNull(DeepLinkParser.parse("   "))
    }

    @Test
    fun zxingRoundTripsDeepLinkQrBitmap() {
        val uri = "presentersync://connect?hosts=192.168.1.50,HOST.local&port=4455&bp=4456&code=K9P-4X7&mic=Mic%2FAux&mode=lan"
        val matrix = QRCodeWriter().encode(
            uri,
            BarcodeFormat.QR_CODE,
            240,
            240,
            mapOf(EncodeHintType.MARGIN to 2)
        )
        val pixels = IntArray(matrix.width * matrix.height) { idx ->
            val x = idx % matrix.width
            val y = idx / matrix.width
            if (matrix.get(x, y)) 0xFF000000.toInt() else 0xFFFFFFFF.toInt()
        }
        val source = RGBLuminanceSource(matrix.width, matrix.height, pixels)
        val decoded = MultiFormatReader().decode(
            BinaryBitmap(HybridBinarizer(source)),
            mapOf(DecodeHintType.POSSIBLE_FORMATS to listOf(BarcodeFormat.QR_CODE))
        )
        val parsed = DeepLinkParser.parse(decoded.text)
        assertNotNull(parsed)
        assertEquals("K9P-4X7", parsed!!.sessionCode)
        assertEquals("192.168.1.50,HOST.local", parsed.hostsCsv)
    }
}
