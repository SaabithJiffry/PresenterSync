package com.saabithjiffry.presentersync.remote

import com.saabithjiffry.presentersync.remote.util.DiagnosticLogger
import org.junit.Assert.assertFalse
import org.junit.Test

class StaticAuditRegressionTest {

    @Test
    fun diagnosticLogger_scrubsPatternsAndSecrets() {
        val raw = """PSGCM1|AQIDBAUG|cipher== PSRELAY|room|1|2|myauth {"sessionToken":"tok_abc123","obsPassword":"pw9"} Authorization: Bearer jwt_xyz presentersync://pair?host=1.2.3.4&code=123456&pw=MyPass"""
        val scrubbed = DiagnosticLogger.scrubSecrets(raw, listOf("tok_abc123"))
        assertFalse(scrubbed.contains("cipher=="))
        assertFalse(scrubbed.contains("tok_abc123"))
        assertFalse(scrubbed.contains("pw9"))
        assertFalse(scrubbed.contains("jwt_xyz"))
        assertFalse(scrubbed.contains("MyPass"))
    }
}
