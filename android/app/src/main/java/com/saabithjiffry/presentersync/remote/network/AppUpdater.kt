package com.saabithjiffry.presentersync.remote.network

import com.saabithjiffry.presentersync.remote.config.AppConstants
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject

data class UpdateCheckResult(
    val currentVersion: String,
    val latestVersion: String?,
    val updateAvailable: Boolean,
    val releaseNotes: String,
    val releaseHtmlUrl: String,
    val apkDownloadUrl: String?,
    val apkAssetName: String? = null,
    val apkSizeBytes: Long = -1L,
    val sha256SumsUrl: String? = null,
    val errorMessage: String? = null
)

object AppUpdater {

    suspend fun checkLatestRelease(
        httpClient: OkHttpClient,
        currentVersion: String = AppConstants.APP_VERSION,
        apiUrl: String = AppConstants.GITHUB_RELEASES_API
    ): UpdateCheckResult = withContext(Dispatchers.IO) {
        try {
            val req = Request.Builder()
                .url(apiUrl)
                .header("Accept", "application/vnd.github+json")
                .header("User-Agent", "PresenterSync-Remote-Android/$currentVersion")
                .build()
            httpClient.newCall(req).execute().use { resp ->
                val body = resp.body?.string().orEmpty()
                if (!resp.isSuccessful) {
                    return@withContext UpdateCheckResult(
                        currentVersion = currentVersion,
                        latestVersion = null,
                        updateAvailable = false,
                        releaseNotes = "",
                        releaseHtmlUrl = AppConstants.GITHUB_RELEASES_URL,
                        apkDownloadUrl = null,
                        errorMessage = "GitHub HTTP ${resp.code}"
                    )
                }
                parseLatestReleaseJson(body, currentVersion)
            }
        } catch (t: Throwable) {
            UpdateCheckResult(
                currentVersion = currentVersion,
                latestVersion = null,
                updateAvailable = false,
                releaseNotes = "",
                releaseHtmlUrl = AppConstants.GITHUB_RELEASES_URL,
                apkDownloadUrl = null,
                errorMessage = t.message ?: "Network error checking updates"
            )
        }
    }

    fun parseLatestReleaseJson(jsonText: String, currentVersion: String): UpdateCheckResult {
        val json = JSONObject(jsonText)
        val rawTag = json.optString("tag_name", "").trim()
        val latest = rawTag.removePrefix("v").removePrefix("V").ifBlank { null }
        val notes = json.optString("body", "").trim()
        val htmlUrl = json.optString("html_url", AppConstants.GITHUB_RELEASES_URL).ifBlank {
            AppConstants.GITHUB_RELEASES_URL
        }

        var apkUrl: String? = null
        var apkName: String? = null
        var apkSize = -1L
        var shaUrl: String? = null
        val assets = json.optJSONArray("assets")
        if (assets != null) {
            for (i in 0 until assets.length()) {
                val asset = assets.optJSONObject(i) ?: continue
                val name = asset.optString("name", "").trim()
                val dl = asset.optString("browser_download_url", "").trim()
                if (dl.isBlank()) continue
                if (name.equals("SHA256SUMS.txt", ignoreCase = true)) {
                    shaUrl = dl
                } else if (name.endsWith(".apk", ignoreCase = true)) {
                    val isPreferred = name.contains("PresenterSync_Remote", ignoreCase = true)
                    if (apkUrl == null || isPreferred) {
                        apkUrl = dl
                        apkName = name
                        apkSize = asset.optLong("size", -1L)
                    }
                }
            }
        }

        val isNewer = if (latest != null) compareSemVer(latest, currentVersion) > 0 else false
        return UpdateCheckResult(
            currentVersion = currentVersion,
            latestVersion = latest,
            updateAvailable = isNewer,
            releaseNotes = notes,
            releaseHtmlUrl = htmlUrl,
            apkDownloadUrl = apkUrl,
            apkAssetName = apkName,
            apkSizeBytes = apkSize,
            sha256SumsUrl = shaUrl,
            errorMessage = null
        )
    }

    /**
     * Parses a GNU coreutils SHA256SUMS.txt manifest (`<hex>  <filename>`) for the matching artifact.
     */
    fun parseSha256Sums(sumsText: String, targetFileName: String = "PresenterSync_Remote.apk"): String? {
        val wanted = targetFileName.trim().lowercase()
        val regex = Regex("""^\s*([0-9a-fA-F]{64})\s+[* ]?(.+?)\s*$""")
        for (line in sumsText.lineSequence()) {
            val match = regex.matchEntire(line) ?: continue
            val digest = match.groupValues[1].lowercase()
            val rawName = match.groupValues[2].trim().substringAfterLast('/').substringAfterLast('\\').lowercase()
            if (rawName == wanted) {
                return digest
            }
        }
        return null
    }

    /**
     * Returns > 0 if versionA > versionB, < 0 if versionA < versionB, 0 if equal.
     */
    fun compareSemVer(versionA: String, versionB: String): Int {
        fun parseParts(v: String): List<Int> {
            val core = v.trim().removePrefix("v").removePrefix("V").substringBefore("-")
            return core.split(".").map { seg -> seg.toIntOrNull() ?: 0 }
        }
        val a = parseParts(versionA)
        val b = parseParts(versionB)
        val maxLen = maxOf(a.size, b.size, 3)
        for (i in 0 until maxLen) {
            val av = a.getOrElse(i) { 0 }
            val bv = b.getOrElse(i) { 0 }
            if (av != bv) return av.compareTo(bv)
        }
        return 0
    }
}
