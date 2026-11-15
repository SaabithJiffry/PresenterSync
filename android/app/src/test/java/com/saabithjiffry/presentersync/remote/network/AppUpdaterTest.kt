package com.saabithjiffry.presentersync.remote.network

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AppUpdaterTest {

    @Test
    fun comparesSemVerVersionsAccurately() {
        assertTrue(AppUpdater.compareSemVer("v5.0.0", "4.9.0") > 0)
        assertTrue(AppUpdater.compareSemVer("4.10.0", "4.9.1") > 0)
        assertTrue(AppUpdater.compareSemVer("4.9.0", "5.0.0") < 0)
        assertEquals(0, AppUpdater.compareSemVer("v4.9.0", "4.9.0"))
    }

    @Test
    fun parsesGitHubReleaseJsonAndExtractsApkAsset() {
        val sampleJson = """
            {
              "tag_name": "v5.0.0",
              "html_url": "https://github.com/SaabithJiffry/PresenterSync/releases/tag/v5.0.0",
              "body": "## Highlights\n- Smart Board Android APK + 3-binary release",
              "assets": [
                {
                  "name": "PresenterSync.exe",
                  "browser_download_url": "https://github.com/SaabithJiffry/PresenterSync/releases/download/v5.0.0/PresenterSync.exe"
                },
                {
                  "name": "PresenterSync_Remote.apk",
                  "browser_download_url": "https://github.com/SaabithJiffry/PresenterSync/releases/download/v5.0.0/PresenterSync_Remote.apk"
                }
              ]
            }
        """.trimIndent()

        val update = AppUpdater.parseLatestReleaseJson(sampleJson, currentVersion = "4.9.0")
        assertTrue(update.updateAvailable)
        assertEquals("5.0.0", update.latestVersion)
        assertEquals(
            "https://github.com/SaabithJiffry/PresenterSync/releases/download/v5.0.0/PresenterSync_Remote.apk",
            update.apkDownloadUrl
        )

        val current = AppUpdater.parseLatestReleaseJson(sampleJson, currentVersion = "5.0.0")
        assertFalse(current.updateAvailable)
    }
}
