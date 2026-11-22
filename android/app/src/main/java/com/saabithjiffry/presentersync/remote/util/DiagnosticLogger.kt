package com.saabithjiffry.presentersync.remote.util

import java.io.File
import java.text.SimpleDateFormat
import java.util.ArrayDeque
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Persistent error, latency, and 5-section diagnostic snapshot logger for
 * PresenterSync Remote (Android) with rolling 5 MB file rotation and a
 * 50-event circular pre-error breadcrumb buffer.
 */
object DiagnosticLogger {
    const val MAX_BREADCRUMBS = 50
    const val MAX_LOG_BYTES = 5L * 1024L * 1024L // 5 MB
    const val LOG_FILE_NAME = "PresenterSyncRemote_ErrorLog.log"
    const val LOG_BACKUP_NAME = "PresenterSyncRemote_ErrorLog.1.log"
    const val JSONL_FILE_NAME = "PresenterSyncRemote_ErrorLog.jsonl"
    const val JSONL_BACKUP_NAME = "PresenterSyncRemote_ErrorLog.1.jsonl"

    data class Breadcrumb(
        val tickMs: Long,
        val time: String,
        val category: String,
        val action: String,
        val detail: String
    )

    data class AppStateSnapshot(
        val connected: Boolean = false,
        val isMuted: Boolean = false,
        val recState: Int = 0,
        val streamState: Int = 0,
        val currentScene: String = "",
        val networkMode: String = "LAN",
        val usingBridge: Boolean = false
    )

    private val lock = Any()
    private val breadcrumbs = ArrayDeque<Breadcrumb>(MAX_BREADCRUMBS)
    @Volatile
    private var logDir: File? = null
    @Volatile
    private var appVersionProvider: () -> String = { "unknown" }
    @Volatile
    private var stateProvider: () -> AppStateSnapshot = { AppStateSnapshot() }
    @Volatile
    private var configProvider: () -> Map<String, Any?> = { emptyMap() }
    @Volatile
    private var secretValuesProvider: () -> List<String> = { emptyList() }

    private val secretKeys = setOf(
        "obsPassword", "ObsPassword", "InternetPairingCode",
        "SessionPairingCode", "SessionToken", "password", "token", "pairingCode"
    )

    fun init(
        directory: File,
        appVersion: () -> String = { "unknown" },
        state: () -> AppStateSnapshot = { AppStateSnapshot() },
        config: () -> Map<String, Any?> = { emptyMap() },
        secrets: () -> List<String> = { emptyList() }
    ) {
        synchronized(lock) {
            logDir = directory
            appVersionProvider = appVersion
            stateProvider = state
            configProvider = config
            secretValuesProvider = secrets
        }
    }

    fun recordBreadcrumb(category: String, action: String, detail: String = "") {
        val nowMs = System.currentTimeMillis()
        val timeStr = SimpleDateFormat("HH:mm:ss", Locale.US).format(Date(nowMs))
        synchronized(lock) {
            if (breadcrumbs.size >= MAX_BREADCRUMBS) {
                breadcrumbs.removeFirst()
            }
            breadcrumbs.addLast(Breadcrumb(nowMs, timeStr, category, action, detail))
        }
    }

    fun getBreadcrumbsSnapshot(): List<Breadcrumb> = synchronized(lock) {
        breadcrumbs.toList()
    }

    fun clearBreadcrumbs() = synchronized(lock) {
        breadcrumbs.clear()
    }

    fun checkLatency(
        category: String,
        action: String,
        startMs: Long,
        thresholdMs: Long = 120L,
        detail: String = ""
    ): Long {
        val elapsed = (System.currentTimeMillis() - startMs).coerceAtLeast(0L)
        val bcDetail = if (detail.isNotEmpty()) "elapsed=${elapsed}ms | $detail" else "elapsed=${elapsed}ms"
        recordBreadcrumb(category, action, bcDetail)
        if (elapsed > thresholdMs) {
            logIssue(
                severity = "PERF_LAG",
                subsystem = category,
                message = "$action took ${elapsed}ms (threshold ${thresholdMs}ms)",
                howItHappenedRemark = "Operation exceeded ${thresholdMs}ms latency budget." +
                    if (detail.isNotEmpty()) " $detail" else ""
            )
        }
        return elapsed
    }

    fun logIssue(
        severity: String,
        subsystem: String,
        message: String,
        howItHappenedRemark: String = "",
        throwable: Throwable? = null
    ): Boolean {
        val dir = logDir ?: return false
        return synchronized(lock) {
            try {
                if (!dir.exists()) {
                    dir.mkdirs()
                }
                val logFile = File(dir, LOG_FILE_NAME)
                val backupLogFile = File(dir, LOG_BACKUP_NAME)
                val jsonlFile = File(dir, JSONL_FILE_NAME)
                val backupJsonlFile = File(dir, JSONL_BACKUP_NAME)

                rotateIfNeeded(logFile, backupLogFile)
                rotateIfNeeded(jsonlFile, backupJsonlFile)

                val now = Date()
                val localFmt = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US)
                val utcFmt = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).apply {
                    timeZone = TimeZone.getTimeZone("UTC")
                }
                val localTs = localFmt.format(now)
                val utcTs = "${utcFmt.format(now)} UTC"
                val sev = severity.trim().uppercase(Locale.US).ifEmpty { "ERROR" }

                val secrets = collectSecrets()
                val formatted = formatEntry(
                    localTs = localTs,
                    utcTs = utcTs,
                    nowMs = now.time,
                    severity = sev,
                    subsystem = subsystem,
                    message = message,
                    howItHappenedRemark = howItHappenedRemark,
                    throwable = throwable,
                    secrets = secrets
                )

                logFile.appendText(formatted, Charsets.UTF_8)

                val jsonLine = buildString {
                    append("{")
                    append("\"timestampLocal\":\"").append(jsonEscape(localTs)).append("\",")
                    append("\"timestampUtc\":\"").append(jsonEscape(utcTs)).append("\",")
                    append("\"severity\":\"").append(jsonEscape(sev)).append("\",")
                    append("\"subsystem\":\"").append(jsonEscape(subsystem)).append("\",")
                    append("\"message\":\"").append(jsonEscape(message)).append("\",")
                    append("\"remark\":\"").append(jsonEscape(howItHappenedRemark)).append("\",")
                    append("\"appVersion\":\"").append(jsonEscape(appVersionProvider())).append("\",")
                    append("\"breadcrumbsCount\":").append(breadcrumbs.size)
                    append("}\n")
                }
                jsonlFile.appendText(scrubSecrets(jsonLine, secrets), Charsets.UTF_8)
                true
            } catch (_: Throwable) {
                false
            }
        }
    }

    fun getRecentLogTail(maxChars: Int = 12000): String {
        val dir = logDir ?: return "(no persistent error log entries recorded)"
        val logFile = File(dir, LOG_FILE_NAME)
        if (!logFile.exists()) return "(no persistent error log entries recorded)"
        return try {
            val content = logFile.readText(Charsets.UTF_8)
            if (content.isBlank()) {
                "(no persistent error log entries recorded)"
            } else if (content.length > maxChars) {
                "...(truncated to last $maxChars chars)...\n" +
                    content.substring(content.length - maxChars)
            } else {
                content
            }
        } catch (_: Throwable) {
            "(unable to read persistent error log)"
        }
    }

    private fun rotateIfNeeded(target: File, backup: File) {
        if (target.exists() && target.length() >= MAX_LOG_BYTES) {
            if (backup.exists()) {
                backup.delete()
            }
            if (!target.renameTo(backup)) {
                runCatching { target.writeText("", Charsets.UTF_8) }
            }
        }
    }

    private fun formatEntry(
        localTs: String,
        utcTs: String,
        nowMs: Long,
        severity: String,
        subsystem: String,
        message: String,
        howItHappenedRemark: String,
        throwable: Throwable?,
        secrets: List<String>
    ): String {
        val sb = StringBuilder()
        sb.append("==============================================================================\n")
        sb.append("[1. ERROR & CAUSAL REMARK]\n")
        sb.append("  Local Time      : ").append(localTs).append('\n')
        sb.append("  UTC Time        : ").append(utcTs).append('\n')
        sb.append("  Severity        : ").append(severity).append('\n')
        sb.append("  Subsystem       : ").append(subsystem).append('\n')
        sb.append("  Message         : ").append(message).append('\n')
        sb.append("  How It Happened : ").append(howItHappenedRemark.ifEmpty { "(none provided)" }).append('\n')
        if (throwable != null) {
            sb.append("  Exception       : ").append(throwable::class.java.simpleName)
                .append(": ").append(throwable.message ?: "").append('\n')
            sb.append("  StackTrace      : ")
                .append(throwable.stackTraceToString().replace('\n', ' ').take(1500)).append('\n')
        }

        val rt = Runtime.getRuntime()
        val usedMemKb = (rt.totalMemory() - rt.freeMemory()) / 1024L
        sb.append("[2. SYSTEM DETAILS SNAPSHOT]\n")
        sb.append("  OS / Arch       : ").append(System.getProperty("os.name") ?: "Android")
            .append(" / ").append(System.getProperty("os.arch") ?: "unknown").append('\n')
        sb.append("  JVM Heap Used   : ").append(usedMemKb).append(" KB\n")

        val st = try { stateProvider() } catch (_: Throwable) { AppStateSnapshot() }
        sb.append("[3. PROGRAM & LIVE STATE SNAPSHOT]\n")
        sb.append("  App Version     : ").append(appVersionProvider()).append('\n')
        sb.append("  Connected       : ").append(st.connected).append('\n')
        sb.append("  Muted           : ").append(st.isMuted).append('\n')
        sb.append("  Rec / Stream    : ").append(st.recState).append(" / ").append(st.streamState).append('\n')
        sb.append("  Scene           : ").append(st.currentScene.ifEmpty { "(none)" }).append('\n')
        sb.append("  NetworkMode     : ").append(st.networkMode).append(" (bridge=").append(st.usingBridge).append(")\n")

        val cfg = try { configProvider() } catch (_: Throwable) { emptyMap() }
        sb.append("[4. SANITIZED SETTINGS SNAPSHOT]\n")
        if (cfg.isEmpty()) {
            sb.append("  (no settings bound)\n")
        } else {
            for ((k, v) in cfg) {
                val displayVal = if (k in secretKeys || k.contains("password", ignoreCase = true) || k.contains("token", ignoreCase = true) || k.contains("pairingCode", ignoreCase = true)) {
                    if (v?.toString()?.isNotBlank() == true) "[REDACTED]" else "(empty)"
                } else {
                    v?.toString() ?: "null"
                }
                sb.append("  ").append(k.padEnd(20)).append(": ").append(displayVal).append('\n')
            }
        }

        sb.append("[5. PRE-ERROR BREADCRUMB TRAIL (LAST ").append(MAX_BREADCRUMBS).append(" EVENTS)]\n")
        if (breadcrumbs.isEmpty()) {
            sb.append("  (no breadcrumbs recorded)\n")
        } else {
            for (bc in breadcrumbs) {
                val delta = (nowMs - bc.tickMs).coerceAtLeast(0L)
                sb.append("  T-").append(delta).append(" ms (").append(bc.time).append(") | [")
                    .append(bc.category).append("] ").append(bc.action)
                if (bc.detail.isNotEmpty()) {
                    sb.append(" | ").append(bc.detail)
                }
                sb.append('\n')
            }
        }
        sb.append("==============================================================================\n\n")
        return scrubSecrets(sb.toString(), secrets)
    }

    private fun collectSecrets(): List<String> {
        val result = mutableListOf<String>()
        try {
            val cfg = configProvider()
            for ((k, v) in cfg) {
                if (k in secretKeys || k.contains("password", ignoreCase = true) || k.contains("token", ignoreCase = true) || k.contains("pairingCode", ignoreCase = true)) {
                    val s = v?.toString()?.trim().orEmpty()
                    if (s.length >= 4) result.add(s)
                }
            }
        } catch (_: Throwable) {
        }
        try {
            for (s in secretValuesProvider()) {
                val trimmed = s.trim()
                if (trimmed.length >= 4) result.add(trimmed)
            }
        } catch (_: Throwable) {
        }
        return result.distinct().sortedByDescending { it.length }
    }

    private val gcmEnvelopeRegex = Regex("""PSGCM1\|[A-Za-z0-9+/=]+\|[A-Za-z0-9+/=]+""")
    private val legacyRelayAuthRegex = Regex("""(PSRELAY\|[^|\r\n"]+\|[^|\r\n"]+\|[^|\r\n"]*\|)[^|\r\n\s"}]+""")
    private val jsonSecretFieldRegex = Regex(
        """(\\?"?(?:obsPassword|password|sessionToken|token|internetPairingCode|sessionPairingCode|code|auth)\\?"?\s*:\s*\\?")[^"\r\n]+""",
        RegexOption.IGNORE_CASE
    )
    private val tokenHeaderRegex = Regex("""(X-PresenterSync-Token\s*:\s*)[^\r\n\s]+""", RegexOption.IGNORE_CASE)
    private val bearerHeaderRegex = Regex("""(Authorization\s*:\s*Bearer\s+)[^\r\n\s]+""", RegexOption.IGNORE_CASE)
    private val uriSecretParamRegex = Regex("""([?&](?:pw|password|token|code|pair)=)[^&\s"'<>]+""", RegexOption.IGNORE_CASE)

    internal fun scrubSecrets(input: String, secrets: List<String> = emptyList()): String {
        var out = input
        for (sec in secrets) {
            out = out.replace(sec, "[REDACTED]")
        }
        out = gcmEnvelopeRegex.replace(out, "PSGCM1|[REDACTED]")
        out = legacyRelayAuthRegex.replace(out, "$1[REDACTED]")
        out = jsonSecretFieldRegex.replace(out, "$1[REDACTED]")
        out = tokenHeaderRegex.replace(out, "$1[REDACTED]")
        out = bearerHeaderRegex.replace(out, "$1[REDACTED]")
        out = uriSecretParamRegex.replace(out, "$1[REDACTED]")
        return out
    }

    private fun jsonEscape(s: String): String = buildString(s.length + 8) {
        for (ch in s) {
            when (ch) {
                '\\' -> append("\\\\")
                '"' -> append("\\\"")
                '\n' -> append("\\n")
                '\r' -> append("\\r")
                '\t' -> append("\\t")
                else -> append(ch)
            }
        }
    }
}
