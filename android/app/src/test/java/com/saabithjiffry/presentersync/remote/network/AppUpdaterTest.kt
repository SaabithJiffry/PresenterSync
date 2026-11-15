package com.saabithjiffry.presentersync.remote.network

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okio.Buffer
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.io.IOException
import java.security.MessageDigest

class AppUpdaterTest {

    @get:Rule
    val tempFolder = TemporaryFolder()

    @Test
    fun comparesSemVerVersionsAccurately() {
        assertTrue(AppUpdater.compareSemVer("v6.2.0", "6.1.0") > 0)
        assertTrue(AppUpdater.compareSemVer("4.10.0", "4.9.1") > 0)
        assertTrue(AppUpdater.compareSemVer("4.9.0", "5.0.0") < 0)
        assertEquals(0, AppUpdater.compareSemVer("v6.1.0", "6.1.0"))
    }

    @Test
    fun parsesGitHubReleaseJsonAndExtractsApkAssetAndChecksums() {
        val sampleJson = """
            {
              "tag_name": "v6.2.0",
              "html_url": "https://github.com/SaabithJiffry/PresenterSync/releases/tag/v6.2.0",
              "body": "## Highlights\n- Host Bridge 2.0",
              "assets": [
                {
                  "name": "PresenterSync.exe",
                  "size": 1234567,
                  "browser_download_url": "https://github.com/SaabithJiffry/PresenterSync/releases/download/v6.2.0/PresenterSync.exe"
                },
                {
                  "name": "PresenterSync_Remote.apk",
                  "size": 9876543,
                  "browser_download_url": "https://github.com/SaabithJiffry/PresenterSync/releases/download/v6.2.0/PresenterSync_Remote.apk"
                },
                {
                  "name": "SHA256SUMS.txt",
                  "size": 256,
                  "browser_download_url": "https://github.com/SaabithJiffry/PresenterSync/releases/download/v6.2.0/SHA256SUMS.txt"
                }
              ]
            }
        """.trimIndent()

        val update = AppUpdater.parseLatestReleaseJson(sampleJson, currentVersion = "6.1.0")
        assertTrue(update.updateAvailable)
        assertEquals("6.2.0", update.latestVersion)
        assertEquals("PresenterSync_Remote.apk", update.apkAssetName)
        assertEquals(9876543L, update.apkSizeBytes)
        assertEquals(
            "https://github.com/SaabithJiffry/PresenterSync/releases/download/v6.2.0/PresenterSync_Remote.apk",
            update.apkDownloadUrl
        )
        assertEquals(
            "https://github.com/SaabithJiffry/PresenterSync/releases/download/v6.2.0/SHA256SUMS.txt",
            update.sha256SumsUrl
        )

        val current = AppUpdater.parseLatestReleaseJson(sampleJson, currentVersion = "6.2.0")
        assertFalse(current.updateAvailable)
    }

    @Test
    fun parsesSha256SumsFormatsAccurately() {
        val digestApk = "A".repeat(64)
        val digestExe = "b".repeat(64)
        val sums = """
            $digestExe  PresenterSync.exe
            $digestApk *release-upload/PresenterSync_Remote.apk
        """.trimIndent()

        assertEquals(
            digestApk.lowercase(),
            AppUpdater.parseSha256Sums(sums, "PresenterSync_Remote.apk")
        )
        assertEquals(
            digestExe,
            AppUpdater.parseSha256Sums(sums, "PresenterSync.exe")
        )
        assertNull(AppUpdater.parseSha256Sums(sums, "Missing.apk"))
    }

    @Test
    fun rejectsMismatchedPackageAndNonNewerVersionCode() {
        val wrongPkg = ApkSelfInstaller.validateApkArchiveMetadata(
            archivePackageName = "com.evil.other",
            archiveVersionCode = 70000L,
            expectedPackageName = "com.saabithjiffry.presentersync.remote",
            currentVersionCode = 60100L
        )
        assertNotNull(wrongPkg)
        assertTrue(wrongPkg!!.contains("Package mismatch"))

        val downgrade = ApkSelfInstaller.validateApkArchiveMetadata(
            archivePackageName = "com.saabithjiffry.presentersync.remote",
            archiveVersionCode = 60100L,
            expectedPackageName = "com.saabithjiffry.presentersync.remote",
            currentVersionCode = 60100L
        )
        assertNotNull(downgrade)
        assertTrue(downgrade!!.contains("not newer"))

        val valid = ApkSelfInstaller.validateApkArchiveMetadata(
            archivePackageName = "com.saabithjiffry.presentersync.remote",
            archiveVersionCode = 60200L,
            expectedPackageName = "com.saabithjiffry.presentersync.remote",
            currentVersionCode = 60100L
        )
        assertNull(valid)
    }

    @Test
    fun downloadsAndVerifiesSha256ViaMockWebServer() = runBlocking {
        val payload = ByteArray(64 * 1024) { idx -> (idx % 251).toByte() }
        val expectedSha = MessageDigest.getInstance("SHA-256")
            .digest(payload)
            .joinToString("") { "%02x".format(it) }

        val server = MockWebServer()
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setBody(Buffer().write(payload))
        )
        server.start()
        try {
            val target = File(tempFolder.root, "verified.apk.tmp")
            var lastPct = -1
            val verified = ApkSelfInstaller.downloadAndVerifyPayloadToFile(
                client = OkHttpClient(),
                url = server.url("/PresenterSync_Remote.apk").toString(),
                userAgent = "UnitTest/6.1.0",
                targetFile = target,
                expectedSizeBytes = payload.size.toLong(),
                expectedSha256 = expectedSha,
                onProgress = { _, _, pct -> lastPct = pct }
            )
            assertTrue(verified)
            assertEquals(100, lastPct)
            assertTrue(target.exists())
            assertArrayEquals(payload, target.readBytes())
        } finally {
            server.shutdown()
        }
    }

    @Test
    fun deletesPartialFileAndFailsOnSha256MismatchOrSizeMismatch() {
        val payload = "mock-apk-payload-bytes".toByteArray()
        val server = MockWebServer()
        server.enqueue(MockResponse().setResponseCode(200).setBody(Buffer().write(payload)))
        server.enqueue(MockResponse().setResponseCode(200).setBody(Buffer().write(payload)))
        server.enqueue(MockResponse().setResponseCode(200).setBody(Buffer().write(payload)))
        server.start()
        try {
            val targetBadSha = File(tempFolder.root, "bad_sha.apk.tmp")
            var badShaMsg: String? = null
            try {
                ApkSelfInstaller.downloadAndVerifyPayloadToFile(
                    client = OkHttpClient(),
                    url = server.url("/apk1").toString(),
                    userAgent = "UnitTest/6.1.0",
                    targetFile = targetBadSha,
                    expectedSizeBytes = payload.size.toLong(),
                    expectedSha256 = "0".repeat(64)
                )
            } catch (e: IOException) {
                badShaMsg = e.message
            }
            assertNotNull(badShaMsg)
            assertTrue(badShaMsg!!.contains("SHA-256"))
            assertFalse(targetBadSha.exists())

            val targetBadSize = File(tempFolder.root, "bad_size.apk.tmp")
            var badSizeMsg: String? = null
            try {
                ApkSelfInstaller.downloadAndVerifyPayloadToFile(
                    client = OkHttpClient(),
                    url = server.url("/apk2").toString(),
                    userAgent = "UnitTest/6.1.0",
                    targetFile = targetBadSize,
                    expectedSizeBytes = payload.size.toLong() + 99L,
                    expectedSha256 = null
                )
            } catch (e: IOException) {
                badSizeMsg = e.message
            }
            assertNotNull(badSizeMsg)
            assertTrue(badSizeMsg!!.contains("size mismatch"))
            assertFalse(targetBadSize.exists())

            val targetCancelled = File(tempFolder.root, "cancelled.apk.tmp")
            var cancelled = false
            try {
                ApkSelfInstaller.downloadAndVerifyPayloadToFile(
                    client = OkHttpClient(),
                    url = server.url("/apk3").toString(),
                    userAgent = "UnitTest/6.1.0",
                    targetFile = targetCancelled,
                    expectedSizeBytes = payload.size.toLong(),
                    expectedSha256 = null,
                    isCancelRequested = { true }
                )
            } catch (_: CancellationException) {
                cancelled = true
            }
            assertTrue(cancelled)
            assertFalse(targetCancelled.exists())
        } finally {
            server.shutdown()
        }
    }

    @Test
    fun checkLatestReleaseFromMockWebServerParsesAssetsAndNotes() = runBlocking {
        val server = MockWebServer()
        server.start()
        try {
            val json = """
                {
                  "tag_name": "v6.3.0",
                  "html_url": "https://github.com/SaabithJiffry/PresenterSync/releases/tag/v6.3.0",
                  "body": "Classroom QoL",
                  "assets": [
                    {
                      "name": "PresenterSync_Remote.apk",
                      "size": 5551234,
                      "browser_download_url": "${server.url("/dl/PresenterSync_Remote.apk")}"
                    },
                    {
                      "name": "SHA256SUMS.txt",
                      "size": 120,
                      "browser_download_url": "${server.url("/dl/SHA256SUMS.txt")}"
                    }
                  ]
                }
            """.trimIndent()
            server.enqueue(MockResponse().setResponseCode(200).setBody(json))
            val res = AppUpdater.checkLatestRelease(
                httpClient = OkHttpClient(),
                currentVersion = "6.1.0",
                apiUrl = server.url("/releases/latest").toString()
            )
            assertNull(res.errorMessage)
            assertTrue(res.updateAvailable)
            assertEquals("6.3.0", res.latestVersion)
            assertEquals(5551234L, res.apkSizeBytes)
            assertEquals(server.url("/dl/SHA256SUMS.txt").toString(), res.sha256SumsUrl)
        } finally {
            server.shutdown()
        }
    }
}
