package com.saabithjiffry.presentersync.remote.util

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class DiagnosticLoggerTest {

    @get:Rule
    val tempFolder = TemporaryFolder()

    @Test
    fun breadcrumbRingBufferTrimsAt50Events() {
        val dir = tempFolder.newFolder("logs_ring")
        DiagnosticLogger.init(dir)
        DiagnosticLogger.clearBreadcrumbs()

        for (i in 1..75) {
            DiagnosticLogger.recordBreadcrumb("UI", "Click#$i", "idx=$i")
        }

        val snap = DiagnosticLogger.getBreadcrumbsSnapshot()
        assertEquals(50, snap.size)
        assertEquals("Click#26", snap.first().action)
        assertEquals("Click#75", snap.last().action)
    }

    @Test
    fun logIssueWrites5SectionsAndRedactsSecrets() {
        val dir = tempFolder.newFolder("logs_redact")
        val secretPw = "SuperSecretObsPass99!"
        val secretToken = "tok-xyz-987654"
        DiagnosticLogger.init(
            directory = dir,
            appVersion = { "7.0.1-test" },
            state = {
                DiagnosticLogger.AppStateSnapshot(
                    connected = true,
                    isMuted = false,
                    currentScene = "Main Cam"
                )
            },
            config = {
                mapOf(
                    "HostPort" to 4455,
                    "ObsPassword" to secretPw,
                    "SessionToken" to secretToken
                )
            }
        )
        DiagnosticLogger.clearBreadcrumbs()
        DiagnosticLogger.recordBreadcrumb("NET", "Connect", "auth=$secretPw")

        val ok = DiagnosticLogger.logIssue(
            severity = "ERROR",
            subsystem = "BridgeClient",
            message = "Auth failed with token $secretToken",
            howItHappenedRemark = "Simulated test failure",
            throwable = IllegalStateException("Bad pw $secretPw")
        )
        assertTrue(ok)

        val logFile = File(dir, DiagnosticLogger.LOG_FILE_NAME)
        val jsonlFile = File(dir, DiagnosticLogger.JSONL_FILE_NAME)
        assertTrue(logFile.exists())
        assertTrue(jsonlFile.exists())

        val text = logFile.readText(Charsets.UTF_8)
        assertTrue(text.contains("[1. ERROR & CAUSAL REMARK]"))
        assertTrue(text.contains("[2. SYSTEM DETAILS SNAPSHOT]"))
        assertTrue(text.contains("[3. PROGRAM & LIVE STATE SNAPSHOT]"))
        assertTrue(text.contains("[4. SANITIZED SETTINGS SNAPSHOT]"))
        assertTrue(text.contains("[5. PRE-ERROR BREADCRUMB TRAIL (LAST 50 EVENTS)]"))
        assertTrue(text.contains("Simulated test failure"))
        assertTrue(text.contains("[REDACTED]"))
        assertFalse(text.contains(secretPw))
        assertFalse(text.contains(secretToken))

        val jsonText = jsonlFile.readText(Charsets.UTF_8)
        assertFalse(jsonText.contains(secretPw))
        assertFalse(jsonText.contains(secretToken))
    }

    @Test
    fun logIssueRotatesAt5MbLimit() {
        val dir = tempFolder.newFolder("logs_rotate")
        DiagnosticLogger.init(dir)
        val logFile = File(dir, DiagnosticLogger.LOG_FILE_NAME)
        val backupFile = File(dir, DiagnosticLogger.LOG_BACKUP_NAME)

        // Pre-fill log file to >= 5 MB
        val chunk = "X".repeat(1024 * 1024)
        logFile.outputStream().use { out ->
            repeat(5) { out.write(chunk.toByteArray(Charsets.UTF_8)) }
        }
        assertTrue(logFile.length() >= DiagnosticLogger.MAX_LOG_BYTES)

        val ok = DiagnosticLogger.logIssue("WARNING", "Test", "Trigger rotation", "File exceeded 5 MB")
        assertTrue(ok)
        assertTrue(backupFile.exists())
        assertTrue(backupFile.length() >= DiagnosticLogger.MAX_LOG_BYTES)
        assertTrue(logFile.exists())
        assertTrue(logFile.length() < DiagnosticLogger.MAX_LOG_BYTES)
    }
}
