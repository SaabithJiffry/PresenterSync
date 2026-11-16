package com.saabithjiffry.presentersync.remote.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.SystemUpdate
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.saabithjiffry.presentersync.remote.PresenterSyncRemoteApp
import com.saabithjiffry.presentersync.remote.config.AppConstants
import com.saabithjiffry.presentersync.remote.network.UpdateInstallState
import com.saabithjiffry.presentersync.remote.ui.theme.CompactExplorerButtonPadding
import com.saabithjiffry.presentersync.remote.ui.theme.ExplorerCard

@Composable
fun UpdateReadyInlineBanner(app: PresenterSyncRemoteApp) {
    val cfg by app.configStore.config.collectAsStateWithLifecycle()
    val result by app.apkSelfInstaller.latestCheck.collectAsStateWithLifecycle()
    val installState by app.apkSelfInstaller.installState.collectAsStateWithLifecycle()
    val bannerDismissed by app.apkSelfInstaller.bannerDismissed.collectAsStateWithLifecycle()

    val showActiveInstall = installState !is UpdateInstallState.Idle && installState !is UpdateInstallState.Checking
    val res = result
    val ver = res?.latestVersion
    val showAvailableBanner = installState is UpdateInstallState.Idle &&
        !bannerDismissed &&
        res != null &&
        res.updateAvailable &&
        !ver.isNullOrBlank() &&
        ver != cfg.skippedUpdateVersion &&
        res.apkDownloadUrl != null

    if (!showActiveInstall && !showAvailableBanner) return

    ExplorerCard(
        containerColor = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.45f),
        borderColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.45f),
        contentPadding = 14
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Icon(
                        imageVector = Icons.Default.SystemUpdate,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(18.dp)
                    )
                    Text(
                        text = if (ver != null && res.updateAvailable) {
                            "Update Ready: v$ver"
                        } else {
                            "App Self-Updater"
                        },
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.primary
                    )
                }
                if (installState is UpdateInstallState.Error || installState is UpdateInstallState.LaunchedInstaller) {
                    IconButton(
                        onClick = { app.apkSelfInstaller.clearError() },
                        modifier = Modifier.size(24.dp)
                    ) {
                        Icon(Icons.Default.Close, contentDescription = "Dismiss", modifier = Modifier.size(16.dp))
                    }
                }
            }

            if (showActiveInstall) {
                UpdateInstallProgressBody(
                    app = app,
                    installState = installState,
                    result = res
                )
            } else if (res != null && ver != null) {
                Text(
                    text = "PresenterSync Remote v$ver is available (installed: v${AppConstants.APP_VERSION}). Download, SHA-256 verify, and upgrade in-place.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurface
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Button(
                        onClick = { app.apkSelfInstaller.startDownloadAndInstall(res) },
                        contentPadding = CompactExplorerButtonPadding,
                        modifier = Modifier.weight(1f)
                    ) {
                        Icon(Icons.Default.Download, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("Update Now", maxLines = 1, softWrap = false, overflow = TextOverflow.Ellipsis)
                    }
                    OutlinedButton(
                        onClick = { app.apkSelfInstaller.dismissBannerForSession() },
                        contentPadding = CompactExplorerButtonPadding
                    ) {
                        Text("Later", maxLines = 1, softWrap = false)
                    }
                    TextButton(
                        onClick = {
                            app.configStore.update { it.copy(skippedUpdateVersion = ver) }
                            app.apkSelfInstaller.dismissBannerForSession()
                        },
                        contentPadding = CompactExplorerButtonPadding
                    ) {
                        Text("Skip v$ver", maxLines = 1, softWrap = false)
                    }
                }
            }
        }
    }
}
