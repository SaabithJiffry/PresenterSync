package com.saabithjiffry.presentersync.remote.network

import org.junit.Assert.assertEquals
import org.junit.Test

class EndpointParserTest {

    @Test
    fun parsesMultiCandidateListWithSchemesPortsPathsAndIpv6() {
        val raw = "192.168.1.50, pc.local:4460; wss://stream.example.com/obs ; [::1]:4456 ; 192.168.1.50"
        val res = EndpointParser.parseCandidateEndpoints(raw, 4455)

        assertEquals(4, res.size)

        assertEquals("192.168.1.50", res[0].host)
        assertEquals(4455, res[0].port)
        assertEquals("ws", res[0].scheme)
        assertEquals("/", res[0].path)
        assertEquals("ws://192.168.1.50:4455/", res[0].url)
        assertEquals("192.168.1.50:4455", res[0].raw)

        assertEquals("pc.local", res[1].host)
        assertEquals(4460, res[1].port)
        assertEquals("pc.local:4460", res[1].raw)

        assertEquals("stream.example.com", res[2].host)
        assertEquals(443, res[2].port)
        assertEquals("wss", res[2].scheme)
        assertEquals("/obs", res[2].path)
        assertEquals("wss://stream.example.com:443/obs", res[2].url)

        assertEquals("::1", res[3].host)
        assertEquals(4456, res[3].port)
        assertEquals("ws://[::1]:4456/", res[3].url)
    }

    @Test
    fun emptyOrInvalidInputFallsBackToLoopback() {
        val res = EndpointParser.parseCandidateEndpoints("  , ; ws:// ", 4455)
        assertEquals(1, res.size)
        assertEquals("127.0.0.1", res[0].host)
        assertEquals(4455, res[0].port)
        assertEquals("ws://127.0.0.1:4455/", res[0].url)
    }
}
