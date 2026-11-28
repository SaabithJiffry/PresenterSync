package com.saabithjiffry.presentersync.remote.network

import com.saabithjiffry.presentersync.remote.config.AppConstants
import com.saabithjiffry.presentersync.remote.config.UpdateChannel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream
import java.net.URLEncoder
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
    val rollbackSizeBytes: Long = -1L,
    val nightlyBuilds: List<NightlyBuildEntry> = emptyList(),
    val selectedNightlySha: String? = null,
    val isNightlySelectorMode: Boolean = false
)

data class NightlyMetaInfo(
    val version: String,
    val androidVersionCode: Long,
    val builtAtUtc: String
)

data class CommitInfo(
    val sha: String,
    val shortSha: String,
    val htmlUrl: String,
    val dateIso: String = ""
)

data class CommitListEntry(
    val sha: String,
    val shortSha: String,
    val dateIso: String,
    val dateShort: String,
    val subject: String,
    val htmlUrl: String
)

data class NightlyBuildEntry(
    val sha: String,
    val shortSha: String,
    val dateIso: String,
    val dateShort: String,
    val subject: String,
    val htmlUrl: String,
    val label: String,
    val apkUrl: String,
    val sha256SumsUrl: String,
    val metaUrl: String,
    val isLatest: Boolean
)

object AppUpdater {

    private const val GITHUB_COMMIT_BY_REF_TEMPLATE =
        "https://api.github.com/repos/SaabithJiffry/PresenterSync/commits/%s"
    private const val GITHUB_COMMITS_BINARY_LIST_API =
        "https://api.github.com/repos/SaabithJiffry/PresenterSync/commits?sha=main&path=dist/PresenterSync_Remote.apk&per_page=20"
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
            // 1. Query Stable release + tag commit SHA/date for post-Stable cutoff
            val stableResp = fetchText(httpClient, AppConstants.GITHUB_RELEASES_API, currentVersion, acceptGithubJson = true)
            val stableParsed = if (stableResp.ok) {
                runCatching { parseLatestReleaseJson(stableResp.body, currentVersion) }.getOrNull()
            } else {
                null
            }
            val stableTag = if (stableResp.ok) {
                runCatching { JSONObject(stableResp.body).optString("tag_name", "").trim() }.getOrDefault("")
            } else {
                ""
            }
            val stableCommit = if (stableTag.isNotBlank()) {
                val encodedTag = URLEncoder.encode(stableTag, "UTF-8").replace("+", "%20")
                val tagResp = fetchText(
                    httpClient,
                    String.format(GITHUB_COMMIT_BY_REF_TEMPLATE, encodedTag),
                    currentVersion,
                    acceptGithubJson = true
                )
                if (tagResp.ok) parseCommitDetailsJson(tagResp.body) else null
            } else {
                null
            }

            // 2. Fetch recent commits on main touching dist/PresenterSync_Remote.apk
            val listResp = fetchText(httpClient, GITHUB_COMMITS_BINARY_LIST_API, currentVersion, acceptGithubJson = true)
            if (!listResp.ok) {
                val msg = if (listResp.code == 403 || listResp.code == 429) {
                    "GitHub API rate limit reached (HTTP ${listResp.code}). Try again later."
                } else {
                    "GitHub HTTP ${listResp.code}"
                }
                return errorResult(currentVersion, UpdateChannel.NIGHTLY, msg)
            }

            val rawCommits = parseCommitListJson(listResp.body)
            val builds = filterPostStableNightlyCommits(
                commits = rawCommits,
                stableCommitSha = stableCommit?.sha.orEmpty(),
                stableCommitDate = stableCommit?.dateIso.orEmpty()
            )
            if (builds.isEmpty()) {
                val stableVer = stableParsed?.latestVersion
                val headline = if (stableVer != null) {
                    "Nightly has caught up to Stable (v$stableVer)"
                } else {
                    "No post-Stable Nightly builds found"
                }
                return UpdateCheckResult(
                    currentVersion = currentVersion,
                    latestVersion = stableVer ?: currentVersion,
                    updateAvailable = false,
                    releaseNotes = headline,
                    releaseHtmlUrl = stableParsed?.releaseHtmlUrl ?: AppConstants.GITHUB_RELEASES_URL,
                    apkDownloadUrl = null,
                    channel = UpdateChannel.NIGHTLY,
                    statusHeadline = headline,
                    isCaughtUpToStable = true,
                    stableVersion = stableVer,
                    nightlyBuilds = emptyList(),
                    isNightlySelectorMode = true
                )
            }

            val latestBuild = builds.first()
            val metaResp = fetchText(httpClient, latestBuild.metaUrl, currentVersion, acceptGithubJson = false)
            val sumsResp = fetchText(httpClient, latestBuild.sha256SumsUrl, currentVersion, acceptGithubJson = false)
            val meta = if (metaResp.ok) parseNightlyMetaJson(metaResp.body) else null
            val nightlySha = if (sumsResp.ok) parseSha256Sums(sumsResp.body, DEFAULT_APK_NAME) else null

            val stableSha = if (
                stableParsed?.latestVersion != null &&
                !stableParsed.sha256SumsUrl.isNullOrBlank() &&
                (meta == null || compareSemVer(meta.version, stableParsed.latestVersion) == 0)
            ) {
                val stSums = fetchText(httpClient, stableParsed.sha256SumsUrl, currentVersion, acceptGithubJson = false)
                if (stSums.ok) parseSha256Sums(stSums.body, stableParsed.apkAssetName ?: DEFAULT_APK_NAME) else null
            } else {
                null
            }

            resolveNightlyBuild(
                build = latestBuild,
                allBuilds = builds,
                currentVersion = currentVersion,
                installedApkSha256 = installedApkSha256,
                meta = meta,
                nightlySha256 = nightlySha,
                stableParsed = stableParsed,
                stableSha256 = stableSha
            )
        } catch (t: Throwable) {
            errorResult(currentVersion, UpdateChannel.NIGHTLY, t.message ?: "Network error checking Nightly updates")
        }
    }

    internal fun resolveNightlyBuild(
        build: NightlyBuildEntry,
        allBuilds: List<NightlyBuildEntry>,
        currentVersion: String,
        installedApkSha256: String?,
        meta: NightlyMetaInfo?,
        nightlySha256: String?,
        stableParsed: UpdateCheckResult?,
        stableSha256: String?
    ): UpdateCheckResult {
        val stableVer = stableParsed?.latestVersion
        if (nightlySha256.isNullOrBlank()) {
            return UpdateCheckResult(
                currentVersion = currentVersion,
                latestVersion = meta?.version ?: "Nightly-${build.shortSha}",
                updateAvailable = false,
                releaseNotes = "",
                releaseHtmlUrl = build.htmlUrl,
                apkDownloadUrl = null,
                channel = UpdateChannel.NIGHTLY,
                errorMessage = "SHA256SUMS.txt does not list $DEFAULT_APK_NAME on commit ${build.shortSha}",
                nightlyCommitSha = build.shortSha,
                stableVersion = stableVer,
                nightlyBuilds = allBuilds,
                selectedNightlySha = build.sha,
                isNightlySelectorMode = true
            )
        }

        val displayVer = meta?.version ?: "Nightly-${build.shortSha}"
        val caughtUp = build.isLatest &&
            stableVer != null &&
            !stableSha256.isNullOrBlank() &&
            nightlySha256.equals(stableSha256, ignoreCase = true) &&
            (meta == null || compareSemVer(meta.version, stableVer) == 0)

        if (caughtUp) {
            return UpdateCheckResult(
                currentVersion = currentVersion,
                latestVersion = displayVer,
                updateAvailable = false,
                releaseNotes = "Nightly has caught up to Stable (v$stableVer).",
                releaseHtmlUrl = build.htmlUrl,
                apkDownloadUrl = build.apkUrl,
                apkAssetName = DEFAULT_APK_NAME,
                sha256SumsUrl = build.sha256SumsUrl,
                channel = UpdateChannel.NIGHTLY,
                statusHeadline = "Nightly has caught up to Stable (v$stableVer)",
                isCaughtUpToStable = true,
                nightlyCommitSha = build.shortSha,
                stableVersion = stableVer,
                nightlyBuilds = allBuilds,
                selectedNightlySha = build.sha,
                isNightlySelectorMode = true
            )
        }

        val matchesRunning = !installedApkSha256.isNullOrBlank() &&
            installedApkSha256.equals(nightlySha256, ignoreCase = true)

        if (matchesRunning) {
            return UpdateCheckResult(
                currentVersion = currentVersion,
                latestVersion = displayVer,
                updateAvailable = false,
                releaseNotes = "Installed APK matches Nightly commit ${build.shortSha} (${build.dateShort}).",
                releaseHtmlUrl = build.htmlUrl,
                apkDownloadUrl = build.apkUrl,
                apkAssetName = DEFAULT_APK_NAME,
                sha256SumsUrl = build.sha256SumsUrl,
                channel = UpdateChannel.NIGHTLY,
                statusHeadline = "Already Installed (${build.shortSha})",
                isNightlyUpToDate = true,
                nightlyCommitSha = build.shortSha,
                stableVersion = stableVer,
                nightlyBuilds = allBuilds,
                selectedNightlySha = build.sha,
                isNightlySelectorMode = true
            )
        }

        val stableSuffix = if (stableVer != null) " (Stable: v$stableVer)" else ""
        val headline = if (build.isLatest) {
            "Nightly (Latest): $displayVer @ ${build.shortSha}$stableSuffix"
        } else {
            "Selected Nightly: $displayVer @ ${build.shortSha}$stableSuffix"
        }
        val notesLines = buildList {
            if (build.subject.isNotBlank()) add(build.subject)
            add("Commit: ${build.sha}")
            if (build.dateIso.isNotBlank()) add("Committed: ${build.dateIso}")
            if (meta?.builtAtUtc?.isNotBlank() == true) add("Built UTC: ${meta.builtAtUtc}")
        }.joinToString("\n")

        return UpdateCheckResult(
            currentVersion = currentVersion,
            latestVersion = displayVer,
            updateAvailable = true,
            releaseNotes = notesLines,
            releaseHtmlUrl = build.htmlUrl,
            apkDownloadUrl = build.apkUrl,
            apkAssetName = DEFAULT_APK_NAME,
            sha256SumsUrl = build.sha256SumsUrl,
            channel = UpdateChannel.NIGHTLY,
            statusHeadline = headline,
            nightlyCommitSha = build.shortSha,
            stableVersion = stableVer,
            nightlyBuilds = allBuilds,
            selectedNightlySha = build.sha,
            isNightlySelectorMode = true
        )
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
        val commitObj = json.optJSONObject("commit")
        val dateIso = commitObj?.optJSONObject("committer")?.optString("date", "")?.trim().orEmpty()
            .ifBlank { commitObj?.optJSONObject("author")?.optString("date", "")?.trim().orEmpty() }
        return CommitInfo(sha = sha, shortSha = sha.take(7), htmlUrl = htmlUrl, dateIso = dateIso)
    }

    fun parseCommitListJson(jsonText: String): List<CommitListEntry> {
        val arr = runCatching { JSONArray(jsonText) }.getOrNull() ?: return emptyList()
        val out = mutableListOf<CommitListEntry>()
        for (i in 0 until arr.length()) {
            val item = arr.optJSONObject(i) ?: continue
            val sha = item.optString("sha", "").trim().lowercase()
            if (sha.length < 7) continue
            val shortSha = sha.take(7)
            val htmlUrl = item.optString("html_url", "https://github.com/SaabithJiffry/PresenterSync/commit/$sha")
            val commitObj = item.optJSONObject("commit")
            val dateIso = commitObj?.optJSONObject("committer")?.optString("date", "")?.trim().orEmpty()
                .ifBlank { commitObj?.optJSONObject("author")?.optString("date", "")?.trim().orEmpty() }
            val dateShort = if (dateIso.length >= 10) dateIso.substring(0, 10) else ""
            val rawMsg = commitObj?.optString("message", "")?.trim().orEmpty()
            val firstLine = rawMsg.lineSequence().firstOrNull()?.trim().orEmpty()
            val subject = if (firstLine.length > 60) firstLine.take(57) + "..." else firstLine
            out += CommitListEntry(
                sha = sha,
                shortSha = shortSha,
                dateIso = dateIso,
                dateShort = dateShort,
                subject = subject,
                htmlUrl = htmlUrl
            )
        }
        return out
    }

    fun filterPostStableNightlyCommits(
        commits: List<CommitListEntry>,
        stableCommitSha: String = "",
        stableCommitDate: String = "",
        rawBaseOverride: String = ""
    ): List<NightlyBuildEntry> {
        val cleanStableSha = stableCommitSha.trim().lowercase()
        val cleanStableDate = stableCommitDate.trim()
        val filtered = mutableListOf<CommitListEntry>()
        for (c in commits) {
            if (cleanStableSha.isNotEmpty() && c.sha.equals(cleanStableSha, ignoreCase = true)) {
                break
            }
            if (cleanStableDate.isNotEmpty() && c.dateIso.isNotEmpty() && c.dateIso <= cleanStableDate) {
                break
            }
            filtered += c
        }
        return filtered.mapIndexed { idx, c ->
            val isLatest = idx == 0
            val base = rawBaseOverride.ifBlank { String.format(RAW_BASE_TEMPLATE, c.sha) }
            val label = if (isLatest) {
                listOf("Nightly (Latest)", c.shortSha, c.dateShort).filter { it.isNotBlank() }.joinToString(" · ")
            } else {
                listOf(c.shortSha, c.dateShort, c.subject).filter { it.isNotBlank() }.joinToString(" · ")
            }
            NightlyBuildEntry(
                sha = c.sha,
                shortSha = c.shortSha,
                dateIso = c.dateIso,
                dateShort = c.dateShort,
                subject = c.subject,
                htmlUrl = c.htmlUrl,
                label = label,
                apkUrl = "$base/$DEFAULT_APK_NAME",
                sha256SumsUrl = "$base/SHA256SUMS.txt",
                metaUrl = "$base/nightly_meta.json",
                isLatest = isLatest
            )
        }
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

    internal data class HttpTextResp(val ok: Boolean, val code: Int, val body: String)

    internal fun fetchText(
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
