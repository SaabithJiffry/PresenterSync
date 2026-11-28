package com.saabithjiffry.presentersync.remote.network

import android.content.Context
import com.saabithjiffry.presentersync.remote.config.RemoteConfig
import com.saabithjiffry.presentersync.remote.config.RemoteConfigStore
import com.saabithjiffry.presentersync.remote.config.UpdateChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DualChannelUpdaterTest {

    @Test
    fun updateChannelEnumAndRollbackFilenameNormalizeSafely() {
        assertEquals(UpdateChannel.STABLE, UpdateChannel.fromRaw(null))
        assertEquals(UpdateChannel.STABLE, UpdateChannel.fromRaw("stable"))
        assertEquals(UpdateChannel.NIGHTLY, UpdateChannel.fromRaw("Nightly"))
        assertEquals(UpdateChannel.NIGHTLY, UpdateChannel.fromRaw("  nightly  "))
        assertEquals(
            "PresenterSync_Remote_v10.1.1.apk",
            ApkSelfInstaller.buildRollbackApkFileName("v10.1.1")
        )
    }

    @Test
    fun nightlyCaughtUpToStableDetectsMatchingVersionAndSha() {
        val sha = "a".repeat(64)
        val commit = CommitInfo(sha = "1234567890abcdef", shortSha = "1234567", htmlUrl = "https://example.com/c")
        val meta = NightlyMetaInfo(version = "10.2.0", androidVersionCode = 100200L, builtAtUtc = "2026-11-28T00:00:00Z")
        val stable = UpdateCheckResult(
            currentVersion = "10.2.0",
            latestVersion = "10.2.0",
            updateAvailable = false,
            releaseNotes = "",
            releaseHtmlUrl = "https://example.com/r",
            apkDownloadUrl = "https://example.com/app.apk",
            sha256SumsUrl = "https://example.com/SHA256SUMS.txt"
        )
        val res = AppUpdater.evaluateNightlyResult(
            currentVersion = "10.2.0",
            installedApkSha256 = "b".repeat(64),
            commit = commit,
            meta = meta,
            nightlySha256 = sha,
            nightlyApkUrl = "https://raw.githubusercontent.com/SaabithJiffry/PresenterSync/1234567890abcdef/dist/PresenterSync_Remote.apk",
            nightlySumsUrl = "https://raw.githubusercontent.com/SaabithJiffry/PresenterSync/1234567890abcdef/dist/SHA256SUMS.txt",
            stableParsed = stable,
            stableSha256 = sha
        )
        assertFalse(res.updateAvailable)
        assertTrue(res.isCaughtUpToStable)
        assertEquals("Nightly has caught up to Stable (v10.2.0)", res.statusHeadline)
    }

    @Test
    fun nightlySameShaAsInstalledPreventsRedownloadLoop() {
        val nightlySha = "c".repeat(64)
        val stableSha = "d".repeat(64)
        val commit = CommitInfo(sha = "abcdef1234567890", shortSha = "abcdef1", htmlUrl = "https://example.com/c")
        val meta = NightlyMetaInfo(version = "10.2.0", androidVersionCode = 100200L, builtAtUtc = "2026-11-28T00:00:00Z")
        val stable = UpdateCheckResult(
            currentVersion = "10.2.0",
            latestVersion = "10.1.1",
            updateAvailable = false,
            releaseNotes = "",
            releaseHtmlUrl = "https://example.com/r",
            apkDownloadUrl = "https://example.com/app.apk"
        )
        val upToDate = AppUpdater.evaluateNightlyResult(
            currentVersion = "10.2.0",
            installedApkSha256 = nightlySha,
            commit = commit,
            meta = meta,
            nightlySha256 = nightlySha,
            nightlyApkUrl = "https://example.com/n.apk",
            nightlySumsUrl = "https://example.com/SHA256SUMS.txt",
            stableParsed = stable,
            stableSha256 = stableSha
        )
        assertFalse(upToDate.updateAvailable)
        assertTrue(upToDate.isNightlyUpToDate)
        assertEquals("Up to date on latest Nightly (v10.2.0 @ abcdef1)", upToDate.statusHeadline)

        val newerAvailable = AppUpdater.evaluateNightlyResult(
            currentVersion = "10.2.0",
            installedApkSha256 = "e".repeat(64),
            commit = commit,
            meta = meta,
            nightlySha256 = nightlySha,
            nightlyApkUrl = "https://example.com/n.apk",
            nightlySumsUrl = "https://example.com/SHA256SUMS.txt",
            stableParsed = stable,
            stableSha256 = stableSha
        )
        assertTrue(newerAvailable.updateAvailable)
        assertEquals("Nightly available: v10.2.0 @ abcdef1 (Stable: v10.1.1)", newerAvailable.statusHeadline)
    }

    @Test
    fun stableSameVersionHandoffAndAheadOfStableRollbackWorkCleanly() {
        val stableParsedSame = UpdateCheckResult(
            currentVersion = "10.2.0",
            latestVersion = "10.2.0",
            updateAvailable = false,
            releaseNotes = "Final 10.2.0",
            releaseHtmlUrl = "https://example.com/r",
            apkDownloadUrl = "https://example.com/stable.apk",
            apkAssetName = "PresenterSync_Remote.apk",
            apkSizeBytes = 1000L,
            sha256SumsUrl = "https://example.com/SHA256SUMS.txt"
        )
        val handoff = AppUpdater.evaluateStableResult(
            parsed = stableParsedSame,
            currentVersion = "10.2.0",
            installedApkSha256 = "1".repeat(64),
            stableAssetSha256 = "2".repeat(64)
        )
        assertTrue(handoff.updateAvailable)
        assertTrue(handoff.isSameVersionStableHandoff)
        assertEquals("Install Stable v10.2.0 (replaces Nightly build)", handoff.statusHeadline)
        assertNull(
            ApkSelfInstaller.validateApkArchiveMetadata(
                archivePackageName = "com.pkg",
                archiveVersionCode = 100200L,
                expectedPackageName = "com.pkg",
                currentVersionCode = 100200L,
                allowSameVersionCode = true
            )
        )
        assertNotNull(
            ApkSelfInstaller.validateApkArchiveMetadata(
                archivePackageName = "com.pkg",
                archiveVersionCode = 100200L,
                expectedPackageName = "com.pkg",
                currentVersionCode = 100200L,
                allowSameVersionCode = false
            )
        )

        val stableOlder = stableParsedSame.copy(latestVersion = "10.1.1")
        val ahead = AppUpdater.evaluateStableResult(
            parsed = stableOlder,
            currentVersion = "10.2.0",
            installedApkSha256 = "1".repeat(64),
            stableAssetSha256 = null
        )
        assertFalse(ahead.updateAvailable)
        assertTrue(ahead.isAheadOfStable)
        assertEquals("10.1.1", ahead.stableVersion)
        assertEquals("https://example.com/stable.apk", ahead.rollbackApkUrl)
        assertEquals("Running Nightly v10.2.0 (ahead of Stable v10.1.1)", ahead.statusHeadline)
    }

    @Test
    fun parseNightlyMetaAndCommitDetailsHandleValidAndInvalidJson() {
        val commit = AppUpdater.parseCommitDetailsJson("""{"sha":"ABCDEF1234567890","html_url":"https://github.com/a/b"}""")
        assertNotNull(commit)
        assertEquals("abcdef1", commit!!.shortSha)

        val meta = AppUpdater.parseNightlyMetaJson("""{"version":"10.2.0","androidVersionCode":100200,"builtAtUtc":"2026-11-28T00:00:00Z"}""")
        assertNotNull(meta)
        assertEquals("10.2.0", meta!!.version)
        assertEquals(100200L, meta.androidVersionCode)

        assertNull(AppUpdater.parseNightlyMetaJson("{}"))
        assertNull(AppUpdater.parseCommitDetailsJson("{}"))
    }

    @Test
    fun postStableCommitFilterAndNightlySelectorResolveCleanly() {
        val rawCommitsJson = """
            [
              {"sha":"aaa1111000000000","html_url":"https://github.com/c/1","commit":{"message":"feat: latest nightly\n\ndetails","committer":{"date":"2026-11-28T05:00:00Z"}}},
              {"sha":"bbb2222000000000","html_url":"https://github.com/c/2","commit":{"message":"fix: older post-stable","committer":{"date":"2026-11-27T12:00:00Z"}}},
              {"sha":"ccc3333000000000","html_url":"https://github.com/c/3","commit":{"message":"chore: stable release","committer":{"date":"2026-11-26T10:00:00Z"}}},
              {"sha":"ddd4444000000000","html_url":"https://github.com/c/4","commit":{"message":"old pre-stable","committer":{"date":"2026-11-25T10:00:00Z"}}}
            ]
        """.trimIndent()
        val parsed = AppUpdater.parseCommitListJson(rawCommitsJson)
        assertEquals(4, parsed.size)

        val builds = AppUpdater.filterPostStableNightlyCommits(
            commits = parsed,
            stableCommitSha = "ccc3333000000000",
            stableCommitDate = "2026-11-26T10:00:00Z"
        )
        assertEquals(2, builds.size)
        assertTrue(builds[0].isLatest)
        assertTrue(builds[0].label.startsWith("Nightly (Latest)"))
        assertFalse(builds[1].isLatest)
        assertTrue(builds[1].label.contains("bbb2222"))

        // Empty when HEAD == stable
        val caughtUpBuilds = AppUpdater.filterPostStableNightlyCommits(
            commits = parsed,
            stableCommitSha = "aaa1111000000000",
            stableCommitDate = "2026-11-28T05:00:00Z"
        )
        assertTrue(caughtUpBuilds.isEmpty())

        // Older post-stable Nightly without nightly_meta.json still resolves when SHA256SUMS.txt exists
        val stableStub = UpdateCheckResult(
            currentVersion = "10.2.0",
            latestVersion = "10.1.1",
            updateAvailable = false,
            releaseNotes = "",
            releaseHtmlUrl = "https://github.com/r",
            apkDownloadUrl = null
        )
        val olderRes = AppUpdater.resolveNightlyBuild(
            build = builds[1],
            allBuilds = builds,
            currentVersion = "10.2.0",
            installedApkSha256 = "f".repeat(64),
            meta = null,
            nightlySha256 = "9".repeat(64),
            stableParsed = stableStub,
            stableSha256 = null
        )
        assertTrue(olderRes.updateAvailable)
        assertEquals("Nightly-bbb2222", olderRes.latestVersion)
        assertEquals("bbb2222", olderRes.nightlyCommitSha)
        assertTrue(olderRes.statusHeadline.startsWith("Selected Nightly:"))

        // Same SHA -> Already Installed
        val sameRes = AppUpdater.resolveNightlyBuild(
            build = builds[1],
            allBuilds = builds,
            currentVersion = "10.2.0",
            installedApkSha256 = "9".repeat(64),
            meta = null,
            nightlySha256 = "9".repeat(64),
            stableParsed = stableStub,
            stableSha256 = null
        )
        assertFalse(sameRes.updateAvailable)
        assertTrue(sameRes.isNightlyUpToDate)
        assertEquals("Already Installed (bbb2222)", sameRes.statusHeadline)

        // Downgrade auto-route helper + nightly rollback filename
        assertTrue(ApkSelfInstaller.shouldAutoRouteNightlyDowngradeToGuidedRollback(UpdateChannel.NIGHTLY, 100101L, 100200L))
        assertFalse(ApkSelfInstaller.shouldAutoRouteNightlyDowngradeToGuidedRollback(UpdateChannel.NIGHTLY, 100200L, 100200L))
        assertFalse(ApkSelfInstaller.shouldAutoRouteNightlyDowngradeToGuidedRollback(UpdateChannel.STABLE, 100101L, 100200L))
        assertEquals("PresenterSync_Remote_nightly_bbb2222.apk", ApkSelfInstaller.buildNightlyRollbackApkFileName("bbb2222"))
    }
}
