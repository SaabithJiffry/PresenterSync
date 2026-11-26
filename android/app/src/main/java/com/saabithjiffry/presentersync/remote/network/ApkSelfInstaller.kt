package com.saabithjiffry.presentersync.remote.network

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import androidx.core.content.pm.PackageInfoCompat
import com.saabithjiffry.presentersync.remote.config.RemoteConfigStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import okhttp3.Call
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.security.MessageDigest
import java.util.concurrent.TimeUnit
import kotlin.coroutines.cancellation.CancellationException

sealed class UpdateInstallState {
    object Idle : UpdateInstallState()
    object Checking : UpdateInstallState()
    data class Downloading(
        val version: String,
        val bytesDownloaded: Long,
        val totalBytes: Long,
        val percent: Int
    ) : UpdateInstallState()
    data class Verifying(val version: String) : UpdateInstallState()
    data class NeedsUnknownSourcesPermission(
        val apkFile: File,
        val version: String,
        val sha256Verified: Boolean
    ) : UpdateInstallState()
    data class ReadyToInstall(
        val apkFile: File,
        val version: String,
        val sha256Verified: Boolean
    ) : UpdateInstallState()
    data class LaunchedInstaller(val version: String, val sha256Verified: Boolean) : UpdateInstallState()
    data class Error(val message: String) : UpdateInstallState()
}

/**
 * Handles in-app release checking, streaming APK download with byte progress,
 * SHA-256 verification against SHA256SUMS.txt, archive integrity verification,
 * and PackageInstaller handoff via FileProvider.
 */
class ApkSelfInstaller(
    private val context: Context,
    private val configStore: RemoteConfigStore,
    private val httpClient: OkHttpClient
) {
    private val appContext = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val _latestCheck = MutableStateFlow<UpdateCheckResult?>(null)
    val latestCheck: StateFlow<UpdateCheckResult?> = _latestCheck.asStateFlow()

    private val _installState = MutableStateFlow<UpdateInstallState>(UpdateInstallState.Idle)
    val installState: StateFlow<UpdateInstallState> = _installState.asStateFlow()

    private val _bannerDismissed = MutableStateFlow(false)
    val bannerDismissed: StateFlow<Boolean> = _bannerDismissed.asStateFlow()

    @Volatile
    private var activeCall: Call? = null
    @Volatile
    private var cancelRequested = false
    private var downloadJob: Job? = null

    fun clearStaleUpdateCache() {
        val dir = updatesDir()
        if (dir.exists()) {
            dir.listFiles()?.forEach { f ->
                runCatching { f.delete() }
            }
        }
    }

    fun dismissBannerForSession() {
        _bannerDismissed.value = true
    }

    fun isBannerVisible(skippedVersion: String): Boolean {
        if (_bannerDismissed.value) return false
        val res = _latestCheck.value ?: return false
        val ver = res.latestVersion ?: return false
        return res.updateAvailable && ver != skippedVersion
    }

    suspend fun checkForUpdates(manual: Boolean): UpdateCheckResult {
        if (!manual && !configStore.current.autoCheckUpdates) {
            return _latestCheck.value ?: UpdateCheckResult(
                currentVersion = configStore.current.let { com.saabithjiffry.presentersync.remote.config.AppConstants.APP_VERSION },
                latestVersion = null,
                updateAvailable = false,
                releaseNotes = "",
                releaseHtmlUrl = com.saabithjiffry.presentersync.remote.config.AppConstants.GITHUB_RELEASES_URL,
                apkDownloadUrl = null
            )
        }
        val now = System.currentTimeMillis()
        if (!manual && (now - configStore.current.lastUpdateCheckMs) < AUTO_CHECK_INTERVAL_MS) {
            return _latestCheck.value ?: UpdateCheckResult(
                currentVersion = com.saabithjiffry.presentersync.remote.config.AppConstants.APP_VERSION,
                latestVersion = null,
                updateAvailable = false,
                releaseNotes = "",
                releaseHtmlUrl = com.saabithjiffry.presentersync.remote.config.AppConstants.GITHUB_RELEASES_URL,
                apkDownloadUrl = null
            )
        }

        if (manual) {
            _bannerDismissed.value = false
            _installState.value = UpdateInstallState.Checking
        }
        val customFeed = configStore.config.value.customUpdateUrl.trim()
        val apiUrl = if (customFeed.isNotBlank()) customFeed else com.saabithjiffry.presentersync.remote.config.AppConstants.GITHUB_RELEASES_API
        val res = AppUpdater.checkLatestRelease(httpClient, apiUrl = apiUrl)
        if (res.errorMessage == null) {
            configStore.update { it.copy(lastUpdateCheckMs = now) }
            _latestCheck.value = res
        } else if (manual) {
            _latestCheck.value = res
        }
        if (manual && _installState.value is UpdateInstallState.Checking) {
            _installState.value = UpdateInstallState.Idle
        }
        return res
    }

    fun startThrottledStartupCheck() {
        scope.launch {
            checkForUpdates(manual = false)
        }
    }

    fun startDownloadAndInstall(result: UpdateCheckResult) {
        val url = result.apkDownloadUrl
        val ver = result.latestVersion
        if (url.isNullOrBlank() || ver.isNullOrBlank()) {
            _installState.value = UpdateInstallState.Error("Release asset PresenterSync_Remote.apk was not found.")
            return
        }
        if (downloadJob?.isActive == true) return

        cancelRequested = false
        downloadJob = scope.launch {
            val dir = updatesDir().apply { mkdirs() }
            val tmpFile = File(dir, "PresenterSync_Remote.apk.tmp")
            val finalFile = File(dir, "PresenterSync_Remote.apk")
            runCatching { tmpFile.delete() }
            runCatching { finalFile.delete() }

            try {
                val dlClient = httpClient.newBuilder()
                    .readTimeout(35, TimeUnit.SECONDS)
                    .callTimeout(240, TimeUnit.SECONDS)
                    .build()

                val expectedSha = if (!result.sha256SumsUrl.isNullOrBlank()) {
                    _installState.value = UpdateInstallState.Downloading(ver, 0L, result.apkSizeBytes, 0)
                    fetchExpectedSha256(dlClient, result.sha256SumsUrl, result.apkAssetName ?: "PresenterSync_Remote.apk")
                } else {
                    null
                }
                if (!result.sha256SumsUrl.isNullOrBlank() && expectedSha == null) {
                    throw IOException("SHA256SUMS.txt does not list ${result.apkAssetName ?: "PresenterSync_Remote.apk"}")
                }

                val shaVerified = downloadAndVerifyPayloadToFile(
                    client = dlClient,
                    url = url,
                    userAgent = "PresenterSync-Remote-Android/${result.currentVersion}",
                    targetFile = tmpFile,
                    expectedSizeBytes = result.apkSizeBytes,
                    expectedSha256 = expectedSha,
                    onVerifying = { _installState.value = UpdateInstallState.Verifying(ver) },
                    onProgress = { downloaded, total, pct ->
                        _installState.value = UpdateInstallState.Downloading(
                            version = ver,
                            bytesDownloaded = downloaded,
                            totalBytes = total,
                            percent = pct
                        )
                    },
                    onCallStarted = { activeCall = it },
                    isCancelRequested = { cancelRequested }
                )
                activeCall = null

                if (!tmpFile.renameTo(finalFile)) {
                    tmpFile.copyTo(finalFile, overwrite = true)
                    tmpFile.delete()
                }

                val currentVerCode = getInstalledVersionCode(appContext)
                val archiveErr = verifyDownloadedApkArchive(appContext, finalFile, currentVerCode)
                if (archiveErr != null) {
                    throw IOException(archiveErr)
                }

                proceedToInstallOrRequestPermission(finalFile, ver, shaVerified)
            } catch (_: CancellationException) {
                activeCall = null
                runCatching { tmpFile.delete() }
                runCatching { finalFile.delete() }
                _installState.value = UpdateInstallState.Idle
            } catch (t: Throwable) {
                activeCall = null
                runCatching { tmpFile.delete() }
                runCatching { finalFile.delete() }
                _installState.value = UpdateInstallState.Error(t.message ?: "Update download failed")
            }
        }
    }

    fun cancelDownload() {
        cancelRequested = true
        runCatching { activeCall?.cancel() }
        downloadJob?.cancel()
        if (_installState.value is UpdateInstallState.Downloading || _installState.value is UpdateInstallState.Verifying) {
            _installState.value = UpdateInstallState.Idle
        }
    }

    fun clearError() {
        if (_installState.value is UpdateInstallState.Error || _installState.value is UpdateInstallState.LaunchedInstaller) {
            _installState.value = UpdateInstallState.Idle
        }
    }

    fun resumeAfterUnknownSourcesCheck() {
        val state = _installState.value
        if (state is UpdateInstallState.NeedsUnknownSourcesPermission &&
            appContext.packageManager.canRequestPackageInstalls() &&
            state.apkFile.exists()
        ) {
            launchInstaller(state.apkFile, state.version, state.sha256Verified)
        }
    }

    fun openUnknownAppSourcesSettings() {
        val intent = Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:${appContext.packageName}")
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        appContext.startActivity(intent)
    }

    fun launchInstaller(apkFile: File, version: String, sha256Verified: Boolean) {
        if (!appContext.packageManager.canRequestPackageInstalls()) {
            _installState.value = UpdateInstallState.NeedsUnknownSourcesPermission(apkFile, version, sha256Verified)
            openUnknownAppSourcesSettings()
            return
        }
        val uri = FileProvider.getUriForFile(
            appContext,
            "${appContext.packageName}.fileprovider",
            apkFile
        )
        val installIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        runCatching {
            appContext.startActivity(installIntent)
            _installState.value = UpdateInstallState.LaunchedInstaller(version, sha256Verified)
        }.onFailure { err ->
            _installState.value = UpdateInstallState.Error(err.message ?: "Could not open Android package installer")
        }
    }

    private fun proceedToInstallOrRequestPermission(apkFile: File, version: String, shaVerified: Boolean) {
        if (!appContext.packageManager.canRequestPackageInstalls()) {
            _installState.value = UpdateInstallState.NeedsUnknownSourcesPermission(apkFile, version, shaVerified)
        } else {
            _installState.value = UpdateInstallState.ReadyToInstall(apkFile, version, shaVerified)
            launchInstaller(apkFile, version, shaVerified)
        }
    }

    private fun updatesDir(): File = File(appContext.cacheDir, "updates")

    internal fun fetchExpectedSha256(client: OkHttpClient, sumsUrl: String, assetName: String): String? {
        val req = Request.Builder()
            .url(sumsUrl)
            .header("User-Agent", "PresenterSync-Remote-Android")
            .build()
        client.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) throw IOException("Failed to fetch SHA256SUMS.txt (HTTP ${resp.code})")
            val text = resp.body?.string().orEmpty()
            return AppUpdater.parseSha256Sums(text, assetName)
        }
    }

    @Suppress("DEPRECATION")
    private fun getInstalledVersionCode(ctx: Context): Long {
        val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ctx.packageManager.getPackageInfo(ctx.packageName, PackageManager.PackageInfoFlags.of(0))
        } else {
            ctx.packageManager.getPackageInfo(ctx.packageName, 0)
        }
        return PackageInfoCompat.getLongVersionCode(info)
    }

    @Suppress("DEPRECATION")
    private fun verifyDownloadedApkArchive(ctx: Context, apkFile: File, currentVersionCode: Long): String? {
        val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ctx.packageManager.getPackageArchiveInfo(apkFile.absolutePath, PackageManager.PackageInfoFlags.of(0))
        } else {
            ctx.packageManager.getPackageArchiveInfo(apkFile.absolutePath, 0)
        } ?: return "Downloaded file is not a valid Android APK package."

        val archiveVer = PackageInfoCompat.getLongVersionCode(info)
        return validateApkArchiveMetadata(
            archivePackageName = info.packageName,
            archiveVersionCode = archiveVer,
            expectedPackageName = ctx.packageName,
            currentVersionCode = currentVersionCode
        )
    }

    companion object {
        const val AUTO_CHECK_INTERVAL_MS = 24L * 3600L * 1000L

        /**
         * Streams an HTTP download into [targetFile], verifies Content-Length / [expectedSizeBytes],
         * and checks SHA-256 against [expectedSha256] when provided. Deletes partial files on failure.
         */
        internal fun downloadAndVerifyPayloadToFile(
            client: OkHttpClient,
            url: String,
            userAgent: String,
            targetFile: File,
            expectedSizeBytes: Long,
            expectedSha256: String?,
            onVerifying: () -> Unit = {},
            onProgress: (bytesDownloaded: Long, totalBytes: Long, percent: Int) -> Unit = { _, _, _ -> },
            onCallStarted: (Call) -> Unit = {},
            isCancelRequested: () -> Boolean = { false }
        ): Boolean {
            val req = Request.Builder()
                .url(url)
                .header("User-Agent", userAgent)
                .build()
            val call = client.newCall(req)
            onCallStarted(call)

            var bytesReadTotal = 0L
            val md = MessageDigest.getInstance("SHA-256")

            try {
                call.execute().use { resp ->
                    if (!resp.isSuccessful) {
                        throw IOException("Download failed with HTTP ${resp.code}")
                    }
                    val body = resp.body ?: throw IOException("Empty download response")
                    val total = body.contentLength().let { cl ->
                        if (cl > 0L) cl else expectedSizeBytes
                    }

                    body.byteStream().use { input ->
                        FileOutputStream(targetFile).use { output ->
                            val buf = ByteArray(16 * 1024)
                            var lastEmitMs = 0L
                            var lastPct = -1
                            while (true) {
                                if (isCancelRequested()) throw CancellationException("User cancelled download")
                                val n = input.read(buf)
                                if (n == -1) break
                                output.write(buf, 0, n)
                                md.update(buf, 0, n)
                                bytesReadTotal += n
                                val pct = if (total > 0L) ((bytesReadTotal * 100L) / total).toInt().coerceIn(0, 100) else 0
                                val now = System.currentTimeMillis()
                                if (pct != lastPct || now - lastEmitMs >= 100L) {
                                    lastPct = pct
                                    lastEmitMs = now
                                    onProgress(bytesReadTotal, total, pct)
                                }
                            }
                            output.flush()
                        }
                    }
                }

                onVerifying()
                if (expectedSizeBytes > 0L && bytesReadTotal != expectedSizeBytes) {
                    throw IOException("Downloaded size mismatch ($bytesReadTotal != $expectedSizeBytes bytes)")
                }
                val actualSha = md.digest().joinToString("") { "%02x".format(it) }
                return if (expectedSha256 != null) {
                    if (!actualSha.equals(expectedSha256, ignoreCase = true)) {
                        throw IOException("SHA-256 verification failed! Expected $expectedSha256, got $actualSha")
                    }
                    true
                } else {
                    false
                }
            } catch (t: Throwable) {
                runCatching { targetFile.delete() }
                throw t
            }
        }

        fun validateApkArchiveMetadata(
            archivePackageName: String?,
            archiveVersionCode: Long,
            expectedPackageName: String,
            currentVersionCode: Long
        ): String? {
            if (archivePackageName != expectedPackageName) {
                return "Package mismatch ($archivePackageName != $expectedPackageName)."
            }
            if (archiveVersionCode <= currentVersionCode) {
                return "Downloaded APK versionCode ($archiveVersionCode) is not newer than current ($currentVersionCode)."
            }
            return null
        }
    }
}
