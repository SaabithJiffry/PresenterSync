package com.saabithjiffry.presentersync.remote.network

import com.saabithjiffry.presentersync.remote.config.AppConstants
import com.saabithjiffry.presentersync.remote.config.UpdateChannel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest

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
    val errorMessage: String? = null,
    val channel: UpdateChannel = UpdateChannel.STABLE,
    val statusHeadline: String = "",
    val isCaughtUpToStable: Boolean = false,
    val isSameVersionStableHandoff: Boolean = false,
    val isAheadOfStable: Boolean = false,
    val isNightlyUpToDate: Boolean = false,
    val nightlyCommitSha: String? = null,
    val stableVersion: String? = null,
    val rollbackApkUrl: String? = null,
    val rollbackSha256SumsUrl: String? = null,
    val rollbackAssetName: String? = null,
    val rollbackSizeBytes: Long = -1L
)

data class NightlyMetaInfo(
    val version: String,
    val androidVersionCode: Long,
    val builtAtUtc: String
)

data class CommitInfo(
    val sha: String,
    val shortSha: String,
    val htmlUrl: String
)

object AppUpdater {

    private const val GITHUB_COMMIT_MAIN_API =
        "https://api.github.com/repos/SaabithJiffry/PresenterSync/commits/main"
    private const val RAW_BASE_TEMPLATE =
        "https://raw.githubusercontent.com/SaabithJiffry/PresenterSync/%s/dist"
    private const val DEFAULT_APK_NAME = "PresenterSync_Remote.apk"

    suspend fun checkLatestRelease(
        httpClient: OkHttpClient,
        currentVersion: String = AppConstants.APP_VERSION,
        apiUrl: String = AppConstants.GITHUB_RELEASES_API
    ): UpdateCheckResult = checkUpdates(
        httpClient = httpClient,
        channel = UpdateChannel.STABLE,
        currentVersion = currentVersion,
        installedApkSha256 = null,
        customUpdateUrl = if (apiUrl != AppConstants.GITHUB_RELEASES_API) apiUrl else ""
    )

    suspend fun checkUpdates(
        httpClient: OkHttpClient,
        channel: UpdateChannel = UpdateChannel.STABLE,
        currentVersion: String = AppConstants.APP_VERSION,
        installedApkSha256: String? = null,
        customUpdateUrl: String = ""
    ): UpdateCheckResult = withContext(Dispatchers.IO) {
        if (channel == UpdateChannel.NIGHTLY) {
            checkNightlyChannel(httpClient, currentVersion, installedApkSha256)
        } else {
            val apiUrl = customUpdateUrl.trim().ifBlank { AppConstants.GITHUB_RELEASES_API }
            checkStableChannel(httpClient, currentVersion, installedApkSha256, apiUrl)
        }
    }

    private fun checkStableChannel(
        httpClient: OkHttpClient,
        currentVersion: String,
        installedApkSha256: String?,
        apiUrl: String
    ): UpdateCheckResult {
        return try {
            val relResp = fetchText(httpClient, apiUrl, currentVersion, acceptGithubJson = true)
            if (!relResp.ok) {
                val msg = if (relResp.code == 403 || relResp.code == 429) {
                    "GitHub API rate limit reached (HTTP ${relResp.code}). Try again later."
                } else {
                    "GitHub HTTP ${relResp.code}"
                }
                return errorResult(currentVersion, UpdateChannel.STABLE, msg)
            }
            val parsed = parseLatestReleaseJson(relResp.body, currentVersion)
            val stableSha = if (
                parsed.latestVersion != null &&
                compareSemVer(parsed.latestVersion, currentVersion) == 0 &&
                !installedApkSha256.isNullOrBlank() &&
                !parsed.sha256SumsUrl.isNullOrBlank()
            ) {
                val sumsResp = fetchText(httpClient, parsed.sha256SumsUrl, currentVersion, acceptGithubJson = false)
                if (sumsResp.ok) parseSha256Sums(sumsResp.body, parsed.apkAssetName ?: DEFAULT_APK_NAME) else null
            } else {
                null
            }
            evaluateStableResult(parsed, currentVersion, installedApkSha256, stableSha)
        } catch (t: Throwable) {
            errorResult(currentVersion, UpdateChannel.STABLE, t.message ?: "Network error checking updates")
        }
    }

    private fun checkNightlyChannel(
        httpClient: OkHttpClient,
        currentVersion: String,
        installedApkSha256: String?
    ): UpdateCheckResult {
        return try {
            val commitResp = fetchText(httpClient, GITHUB_COMMIT_MAIN_API, currentVersion, acceptGithubJson = true)
            if (!commitResp.ok) {
                val msg = if (commitResp.code == 403 || commitResp.code == 429) {
                    "GitHub API rate limit reached (HTTP ${commitResp.code}). Try again later."
                } else {
                    "GitHub HTTP ${commitResp.code}"
                }
                return errorResult(currentVersion, UpdateChannel.NIGHTLY, msg)
            }
            val commit = parseCommitDetailsJson(commitResp.body)
                ?: return errorResult(currentVersion, UpdateChannel.NIGHTLY, "Could not parse main commit SHA")

            val rawBase = String.format(RAW_BASE_TEMPLATE, commit.sha)
            val metaUrl = "$rawBase/nightly_meta.json"
            val sumsUrl = "$rawBase/SHA256SUMS.txt"
            val apkUrl = "$rawBase/$DEFAULT_APK_NAME"

            val metaResp = fetchText(httpClient, metaUrl, currentVersion, acceptGithubJson = false)
            val sumsResp = fetchText(httpClient, sumsUrl, currentVersion, acceptGithubJson = false)
            val meta = if (metaResp.ok) parseNightlyMetaJson(metaResp.body) else null
            val nightlySha = if (sumsResp.ok) parseSha256Sums(sumsResp.body, DEFAULT_APK_NAME) else null
            if (meta == null || nightlySha.isNullOrBlank()) {
                return errorResult(
                    currentVersion,
                    UpdateChannel.NIGHTLY,
                    "Nightly build artifacts not found on commit ${commit.shortSha}"
                )
            }

            // Query Stable release for parity / caught-up comparison
            val stableResp = fetchText(httpClient, AppConstants.GITHUB_RELEASES_API, currentVersion, acceptGithubJson = true)
            val stableParsed = if (stableResp.ok) {
                runCatching { parseLatestReleaseJson(stableResp.body, currentVersion) }.getOrNull()
            } else {
                null
            }
            val stableSha = if (
                stableParsed?.latestVersion != null &&
                compareSemVer(meta.version, stableParsed.latestVersion) == 0 &&
                !stableParsed.sha256SumsUrl.isNullOrBlank()
            ) {
                val stSums = fetchText(httpClient, stableParsed.sha256SumsUrl, currentVersion, acceptGithubJson = false)
                if (stSums.ok) parseSha256Sums(stSums.body, stableParsed.apkAssetName ?: DEFAULT_APK_NAME) else null
            } else {
                null
            }

            evaluateNightlyResult(
                currentVersion = currentVersion,
                installedApkSha256 = installedApkSha256,
                commit = commit,
                meta = meta,
                nightlySha256 = nightlySha,
                nightlyApkUrl = apkUrl,
                nightlySumsUrl = sumsUrl,
                stableParsed = stableParsed,
                stableSha256 = stableSha
            )
        } catch (t: Throwable) {
            errorResult(currentVersion, UpdateChannel.NIGHTLY, t.message ?: "Network error checking Nightly updates")
        }
    }

    internal fun evaluateStableResult(
        parsed: UpdateCheckResult,
        currentVersion: String,
        installedApkSha256: String?,
        stableAssetSha256: String?
    ): UpdateCheckResult {
        val stableVer = parsed.latestVersion ?: return parsed.copy(
            channel = UpdateChannel.STABLE,
            statusHeadline = "Unable to determine latest Stable version"
        )
        val cmp = compareSemVer(stableVer, currentVersion)
        return when {
            cmp > 0 -> parsed.copy(
                channel = UpdateChannel.STABLE,
                updateAvailable = true,
                stableVersion = stableVer,
                statusHeadline = "Stable update available: v$stableVer"
            )
            cmp == 0 && !installedApkSha256.isNullOrBlank() && !stableAssetSha256.isNullOrBlank() &&
                !installedApkSha256.equals(stableAssetSha256, ignoreCase = true) -> parsed.copy(
                channel = UpdateChannel.STABLE,
                updateAvailable = true,
                isSameVersionStableHandoff = true,
                stableVersion = stableVer,
                statusHeadline = "Install Stable v$stableVer (replaces Nightly build)"
            )
            cmp < 0 -> parsed.copy(
                channel = UpdateChannel.STABLE,
                updateAvailable = false,
                isAheadOfStable = true,
                stableVersion = stableVer,
                rollbackApkUrl = parsed.apkDownloadUrl,
                rollbackSha256SumsUrl = parsed.sha256SumsUrl,
                rollbackAssetName = parsed.apkAssetName ?: DEFAULT_APK_NAME,
                rollbackSizeBytes = parsed.apkSizeBytes,
                statusHeadline = "Running Nightly v$currentVersion (ahead of Stable v$stableVer)"
            )
            else -> parsed.copy(
                channel = UpdateChannel.STABLE,
                updateAvailable = false,
                stableVersion = stableVer,
                statusHeadline = "You are on the latest Stable release (v$stableVer)."
            )
        }
    }

    internal fun evaluateNightlyResult(
        currentVersion: String,
        installedApkSha256: String?,
        commit: CommitInfo,
        meta: NightlyMetaInfo,
        nightlySha256: String,
        nightlyApkUrl: String,
        nightlySumsUrl: String,
        stableParsed: UpdateCheckResult?,
        stableSha256: String?
    ): UpdateCheckResult {
        val stableVer = stableParsed?.latestVersion
        val caughtUp = stableVer != null &&
            compareSemVer(meta.version, stableVer) == 0 &&
            !stableSha256.isNullOrBlank() &&
            nightlySha256.equals(stableSha256, ignoreCase = true)

        if (caughtUp) {
            return UpdateCheckResult(
                currentVersion = currentVersion,
                latestVersion = meta.version,
                updateAvailable = false,
                releaseNotes = "Nightly has caught up to Stable (v$stableVer).",
                releaseHtmlUrl = commit.htmlUrl,
                apkDownloadUrl = nightlyApkUrl,
                apkAssetName = DEFAULT_APK_NAME,
                sha256SumsUrl = nightlySumsUrl,
                channel = UpdateChannel.NIGHTLY,
                statusHeadline = "Nightly has caught up to Stable (v$stableVer)",
                isCaughtUpToStable = true,
                nightlyCommitSha = commit.shortSha,
                stableVersion = stableVer
            )
        }

        val matchesRunning = !installedApkSha256.isNullOrBlank() &&
            installedApkSha256.equals(nightlySha256, ignoreCase = true)

        if (matchesRunning) {
            return UpdateCheckResult(
                currentVersion = currentVersion,
                latestVersion = meta.version,
                updateAvailable = false,
                releaseNotes = "Installed APK matches latest Nightly commit ${commit.shortSha}.",
                releaseHtmlUrl = commit.htmlUrl,
                apkDownloadUrl = nightlyApkUrl,
                apkAssetName = DEFAULT_APK_NAME,
                sha256SumsUrl = nightlySumsUrl,
                channel = UpdateChannel.NIGHTLY,
                statusHeadline = "Up to date on latest Nightly (v${meta.version} @ ${commit.shortSha})",
                isNightlyUpToDate = true,
                nightlyCommitSha = commit.shortSha,
                stableVersion = stableVer
            )
        }

        val stableSuffix = if (stableVer != null) " (Stable: v$stableVer)" else ""
        return UpdateCheckResult(
            currentVersion = currentVersion,
            latestVersion = meta.version,
            updateAvailable = true,
            releaseNotes = "Immutable Nightly build pinned to commit ${commit.sha}\nBuilt UTC: ${meta.builtAtUtc}",
            releaseHtmlUrl = commit.htmlUrl,
            apkDownloadUrl = nightlyApkUrl,
            apkAssetName = DEFAULT_APK_NAME,
            sha256SumsUrl = nightlySumsUrl,
            channel = UpdateChannel.NIGHTLY,
            statusHeadline = "Nightly available: v${meta.version} @ ${commit.shortSha}$stableSuffix",
            nightlyCommitSha = commit.shortSha,
            stableVersion = stableVer
        )
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

    fun parseCommitDetailsJson(jsonText: String): CommitInfo? {
        val json = runCatching { JSONObject(jsonText) }.getOrNull() ?: return null
        val sha = json.optString("sha", "").trim().lowercase()
        if (sha.length < 7) return null
        val htmlUrl = json.optString("html_url", "https://github.com/SaabithJiffry/PresenterSync/commit/$sha")
        return CommitInfo(sha = sha, shortSha = sha.take(7), htmlUrl = htmlUrl)
    }

    fun parseNightlyMetaJson(jsonText: String): NightlyMetaInfo? {
        val json = runCatching { JSONObject(jsonText) }.getOrNull() ?: return null
        val ver = json.optString("version", "").trim().removePrefix("v").removePrefix("V")
        if (ver.isBlank()) return null
        val vc = json.optLong("androidVersionCode", 0L)
        val builtAt = json.optString("builtAtUtc", "").trim()
        return NightlyMetaInfo(version = ver, androidVersionCode = vc, builtAtUtc = builtAt)
    }

    fun computeFileSha256(filePath: String): String? {
        val file = File(filePath)
        if (!file.exists() || !file.isFile) return null
        return runCatching {
            val md = MessageDigest.getInstance("SHA-256")
            FileInputStream(file).use { input ->
                val buf = ByteArray(16 * 1024)
                while (true) {
                    val n = input.read(buf)
                    if (n <= 0) break
                    md.update(buf, 0, n)
                }
            }
            md.digest().joinToString("") { "%02x".format(it) }
        }.getOrNull()
    }

    fun parseSha256Sums(sumsText: String, targetFileName: String = DEFAULT_APK_NAME): String? {
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

    private data class HttpTextResp(val ok: Boolean, val code: Int, val body: String)

    private fun fetchText(
        httpClient: OkHttpClient,
        url: String,
        currentVersion: String,
        acceptGithubJson: Boolean
    ): HttpTextResp {
        val reqB = Request.Builder()
            .url(url)
            .header("User-Agent", "PresenterSync-Remote-Android/$currentVersion")
        if (acceptGithubJson) {
            reqB.header("Accept", "application/vnd.github+json")
        }
        httpClient.newCall(reqB.build()).execute().use { resp ->
            return HttpTextResp(resp.isSuccessful, resp.code, resp.body?.string().orEmpty())
        }
    }

    private fun errorResult(currentVersion: String, channel: UpdateChannel, message: String) = UpdateCheckResult(
        currentVersion = currentVersion,
        latestVersion = null,
        updateAvailable = false,
        releaseNotes = "",
        releaseHtmlUrl = AppConstants.GITHUB_RELEASES_URL,
        apkDownloadUrl = null,
        errorMessage = message,
        channel = channel,
        statusHeadline = message
    )
}
