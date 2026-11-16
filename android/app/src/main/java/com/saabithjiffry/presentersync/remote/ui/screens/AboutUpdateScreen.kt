package com.saabithjiffry.presentersync.remote.ui.screens

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.OpenInBrowser
import androidx.compose.material.icons.filled.Security
import androidx.compose.material.icons.filled.SystemUpdate
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.saabithjiffry.presentersync.remote.PresenterSyncRemoteApp
import com.saabithjiffry.presentersync.remote.config.AppConstants
import com.saabithjiffry.presentersync.remote.config.DeviceProfileMode
import com.saabithjiffry.presentersync.remote.config.rememberFormFactor
import com.saabithjiffry.presentersync.remote.network.UpdateCheckResult
import com.saabithjiffry.presentersync.remote.network.UpdateInstallState
import com.saabithjiffry.presentersync.remote.ui.theme.CompactExplorerButtonPadding
import com.saabithjiffry.presentersync.remote.ui.theme.ExplorerCard
import kotlinx.coroutines.launch
import java.util.Locale

internal fun formatUpdateByteProgress(downloaded: Long, total: Long, percent: Int): String {
    fun mb(bytes: Long): String = String.format(Locale.US, "%.1f MB", bytes / (1024.0 * 1024.0))
    return if (total > 0L) {
        "${mb(downloaded)} / ${mb(total)} ($percent%)"
    } else {
        "${mb(downloaded)} downloaded..."
    }
}

@Composable
fun AboutUpdateDialog(
    app: PresenterSyncRemoteApp,
    onDismiss: () -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val formFactor = rememberFormFactor(DeviceProfileMode.AUTO)
    val cfg by app.configStore.config.collectAsStateWithLifecycle()
    val result by app.apkSelfInstaller.latestCheck.collectAsStateWithLifecycle()
    val installState by app.apkSelfInstaller.installState.collectAsStateWithLifecycle()

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Surface(
            modifier = Modifier
                .widthIn(max = 580.dp)
                .fillMaxWidth(formFactor.dialogWidthFraction)
                .heightIn(max = (formFactor.heightDp * formFactor.dialogMaxHeightFraction).dp)
                .padding(vertical = if (formFactor.isCompactHeight) 6.dp else 14.dp),
            shape = RoundedCornerShape(8.dp),
            color = MaterialTheme.colorScheme.background,
            border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)
        ) {
            Column(modifier = Modifier.fillMaxWidth()) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(MaterialTheme.colorScheme.surface)
                        .padding(horizontal = 18.dp, vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                        modifier = Modifier.weight(1f)
                    ) {
                        Icon(
                            imageVector = Icons.Default.Info,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary
                        )
                        Column {
                            Text(
                                text = "About PresenterSync Remote",
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.SemiBold
                            )
                            Text(
                                text = "Version ${AppConstants.APP_VERSION} • Smart Board Companion",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.primary,
                                fontWeight = FontWeight.Medium
                            )
                        }
                    }
                    IconButton(onClick = onDismiss) {
                        Icon(Icons.Default.Close, contentDescription = "Close About")
                    }
                }
                HorizontalDivider(color = MaterialTheme.colorScheme.outline)

                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .verticalScroll(rememberScrollState())
                        .padding(18.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    ExplorerCard(contentPadding = 16) {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(
                                text = "Created by Saabith Jiffry",
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.SemiBold
                            )
                            Text(
                                text = "Strict 1-Tier Android Smart Board & Phone Mic Companion featuring Classroom UDP Discovery (:4457), LAN ↔ WAN failover, Wireless OBS Director Deck, Synchronized Presenter Countdown Timer, Silent Stage Nudge, Push-to-Talk Mode, Custom Hex Themes, Guided Onboarding Wizard, CameraX + ZXing QR pairing, and SHA-256 self-updater.",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }

                    ExplorerCard(contentPadding = 16) {
                        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text(
                                    text = "1-Tap In-App Self-Updater",
                                    style = MaterialTheme.typography.titleSmall,
                                    fontWeight = FontWeight.SemiBold
                                )
                                Icon(
                                    imageVector = Icons.Default.Security,
                                    contentDescription = null,
                                    tint = Color(0xFF10B981),
                                    modifier = Modifier.size(18.dp)
                                )
                            }
                            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text(
                                    text = "Auto-check updates daily on startup",
                                    style = MaterialTheme.typography.bodySmall,
                                    modifier = Modifier.weight(1f)
                                )
                                Switch(
                                    checked = cfg.autoCheckUpdates,
                                    onCheckedChange = { enabled ->
                                        app.configStore.update { it.copy(autoCheckUpdates = enabled) }
                                    }
                                )
                            }

                            if (installState !is UpdateInstallState.Idle) {
                                UpdateInstallProgressBody(
                                    app = app,
                                    installState = installState,
                                    result = result
                                )
                            } else {
                                    val res = result
                                    if (res != null) {
                                        if (res.errorMessage != null) {
                                            Text(
                                                text = "Could not reach GitHub (${res.errorMessage}).",
                                                style = MaterialTheme.typography.bodySmall,
                                                color = Color(0xFFD97706)
                                            )
                                        } else if (res.updateAvailable) {
                                            Text(
                                                text = "New Version Available: v${res.latestVersion} (Current: v${res.currentVersion})",
                                                style = MaterialTheme.typography.bodyMedium,
                                                fontWeight = FontWeight.SemiBold,
                                                color = MaterialTheme.colorScheme.primary
                                            )
                                            if (res.releaseNotes.isNotBlank()) {
                                                Text(
                                                    text = res.releaseNotes.take(500),
                                                    style = MaterialTheme.typography.bodySmall,
                                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                                )
                                            }
                                            if (res.apkDownloadUrl != null) {
                                                Button(
                                                    onClick = { app.apkSelfInstaller.startDownloadAndInstall(res) },
                                                    modifier = Modifier.fillMaxWidth()
                                                ) {
                                                    Icon(Icons.Default.Download, contentDescription = null)
                                                    Spacer(Modifier.width(8.dp))
                                                    Text("Download & Install v${res.latestVersion}")
                                                }
                                            } else {
                                                Button(
                                                    onClick = {
                                                        runCatching {
                                                            context.startActivity(
                                                                Intent(Intent.ACTION_VIEW, Uri.parse(res.releaseHtmlUrl))
                                                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                                            )
                                                        }
                                                    },
                                                    modifier = Modifier.fillMaxWidth()
                                                ) {
                                                    Text("Open Release Page")
                                                }
                                            }
                                        } else {
                                            Text(
                                                text = "✓ You are on the latest release (v${res.latestVersion ?: res.currentVersion}).",
                                                style = MaterialTheme.typography.bodySmall,
                                                color = Color(0xFF10B981),
                                                fontWeight = FontWeight.Medium
                                            )
                                        }
                                    } else {
                                        Text(
                                            text = "Downloads, SHA-256 verifies, and installs signed updates from SaabithJiffry/PresenterSync without leaving the app.",
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant
                                        )
                                    }
                            }

                            val busy = installState is UpdateInstallState.Checking ||
                                installState is UpdateInstallState.Downloading ||
                                installState is UpdateInstallState.Verifying

                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                Button(
                                    onClick = {
                                        scope.launch {
                                            app.apkSelfInstaller.clearError()
                                            app.apkSelfInstaller.checkForUpdates(manual = true)
                                        }
                                    },
                                    enabled = !busy,
                                    contentPadding = CompactExplorerButtonPadding,
                                    modifier = Modifier.weight(1f)
                                ) {
                                    Icon(Icons.Default.SystemUpdate, contentDescription = null, modifier = Modifier.size(18.dp))
                                    Spacer(Modifier.width(6.dp))
                                    Text(
                                        if (formFactor.isTightWidth) "Updates" else "Check for Updates",
                                        maxLines = 1,
                                        softWrap = false,
                                        overflow = TextOverflow.Ellipsis
                                    )
                                }
                                OutlinedButton(
                                    onClick = {
                                        runCatching {
                                            context.startActivity(
                                                Intent(Intent.ACTION_VIEW, Uri.parse(AppConstants.GITHUB_REPO_URL))
                                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                            )
                                        }
                                    },
                                    contentPadding = CompactExplorerButtonPadding,
                                    modifier = Modifier.weight(1f)
                                ) {
                                    Icon(Icons.Default.OpenInBrowser, contentDescription = null, modifier = Modifier.size(18.dp))
                                    Spacer(Modifier.width(6.dp))
                                    Text(
                                        "GitHub Repo",
                                        maxLines = 1,
                                        softWrap = false,
                                        overflow = TextOverflow.Ellipsis
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
internal fun UpdateInstallProgressBody(
    app: PresenterSyncRemoteApp,
    installState: UpdateInstallState,
    result: UpdateCheckResult?
) {
    when (installState) {
        UpdateInstallState.Checking -> {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                Text(
                    "Checking GitHub Releases for updates...",
                    style = MaterialTheme.typography.bodySmall
                )
            }
        }
        is UpdateInstallState.Downloading -> {
            Text(
                text = "Downloading v${installState.version}...",
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold
            )
            if (installState.totalBytes > 0L) {
                LinearProgressIndicator(
                    progress = { installState.percent / 100f },
                    modifier = Modifier.fillMaxWidth()
                )
            } else {
                LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
            }
            Text(
                text = formatUpdateByteProgress(
                    installState.bytesDownloaded,
                    installState.totalBytes,
                    installState.percent
                ),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            OutlinedButton(
                onClick = { app.apkSelfInstaller.cancelDownload() },
                modifier = Modifier.fillMaxWidth()
            ) {
                Text("Cancel Download")
            }
        }
        is UpdateInstallState.Verifying -> {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                Text(
                    "Verifying SHA-256 & APK package integrity...",
                    style = MaterialTheme.typography.bodySmall
                )
            }
        }
        is UpdateInstallState.NeedsUnknownSourcesPermission -> {
            Text(
                text = "Verified v${installState.version} is ready! Grant 'Install unknown apps' permission once so PresenterSync Remote can start the Android installer.",
                style = MaterialTheme.typography.bodySmall,
                color = Color(0xFFD97706)
            )
            Button(
                onClick = { app.apkSelfInstaller.openUnknownAppSourcesSettings() },
                modifier = Modifier.fillMaxWidth()
            ) {
                Text("Allow App Updates & Install")
            }
        }
        is UpdateInstallState.ReadyToInstall -> {
            Text(
                text = if (installState.sha256Verified) {
                    "✓ SHA-256 & package verified for v${installState.version}."
                } else {
                    "✓ Package verified for v${installState.version}."
                },
                style = MaterialTheme.typography.bodySmall,
                color = Color(0xFF10B981),
                fontWeight = FontWeight.Medium
            )
            Button(
                onClick = {
                    app.apkSelfInstaller.launchInstaller(
                        installState.apkFile,
                        installState.version,
                        installState.sha256Verified
                    )
                },
                modifier = Modifier.fillMaxWidth()
            ) {
                Text("Install v${installState.version} Now")
            }
        }
        is UpdateInstallState.LaunchedInstaller -> {
            Text(
                text = "✓ Android updater launched for v${installState.version}${if (installState.sha256Verified) " (SHA-256 verified)" else ""}. Confirm Update on the system prompt — your active HUD restores automatically afterward.",
                style = MaterialTheme.typography.bodySmall,
                color = Color(0xFF10B981),
                fontWeight = FontWeight.Medium
            )
        }
        is UpdateInstallState.Error -> {
            Text(
                text = "Update error: ${installState.message}",
                style = MaterialTheme.typography.bodySmall,
                color = Color(0xFFDC2626)
            )
            if (result?.updateAvailable == true && result.apkDownloadUrl != null) {
                Button(
                    onClick = {
                        app.apkSelfInstaller.clearError()
                        app.apkSelfInstaller.startDownloadAndInstall(result)
                    },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("Retry Download & Install")
                }
            }
        }
        UpdateInstallState.Idle -> Unit
    }
}
