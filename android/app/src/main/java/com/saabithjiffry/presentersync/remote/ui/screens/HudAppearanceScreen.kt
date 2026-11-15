package com.saabithjiffry.presentersync.remote.ui.screens

import android.widget.Toast
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.RestartAlt
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.saabithjiffry.presentersync.remote.PresenterSyncRemoteApp
import com.saabithjiffry.presentersync.remote.config.AppConstants
import com.saabithjiffry.presentersync.remote.config.HudColorPalettes
import com.saabithjiffry.presentersync.remote.config.ThemeMode
import com.saabithjiffry.presentersync.remote.network.ConnStatus
import com.saabithjiffry.presentersync.remote.network.ConnectionUiState
import com.saabithjiffry.presentersync.remote.ui.overlay.MicPillCanvasView
import com.saabithjiffry.presentersync.remote.ui.theme.ExplorerCard

private val SCALE_OPTIONS = listOf(
    0.25f to "0.25x Micro",
    0.5f to "0.5x Mini",
    0.75f to "0.75x Small",
    1.0f to "1.0x Normal",
    1.5f to "1.5x Medium",
    2.0f to "2.0x Large",
    3.0f to "3.0x XL",
    5.0f to "5.0x Gigantic"
)

private val OPACITY_OPTIONS = listOf(
    AppConstants.OPACITY_SOLID to "Solid (100%)",
    AppConstants.OPACITY_FROSTED to "Frosted (86%)",
    AppConstants.OPACITY_GHOST to "Ghost (50%)"
)

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun HudAppearanceScreen(
    app: PresenterSyncRemoteApp
) {
    val context = LocalContext.current
    val cfg by app.configStore.config.collectAsStateWithLifecycle()
    var previewStateIdx by remember { mutableIntStateOf(0) } // 0 = LIVE, 1 = MUTED, 2 = OFFLINE

    Column(
        modifier = Modifier
            .widthIn(max = 760.dp)
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        // 1. Live Floating Pill Preview & Windows 11 App Theme Card
        ExplorerCard(contentPadding = 18) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Column(modifier = Modifier.weight(1f).padding(end = 12.dp)) {
                        Text(
                            text = "Floating Mic Pill Preview",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold
                        )
                        Text(
                            text = "Preset: ${cfg.hudColorPreset} • Scale: ${cfg.indicatorScale}x • Alpha: ${cfg.opacityLevel}/255",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            text = if (cfg.showIndicator) "Shown" else "Hidden",
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        Spacer(Modifier.width(8.dp))
                        Switch(
                            checked = cfg.showIndicator,
                            onCheckedChange = { shown ->
                                app.configStore.update { it.copy(showIndicator = shown) }
                            }
                        )
                    }
                }

                // Live Canvas Preview Surface
                val previewSurfaceColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.55f)
                Surface(
                    shape = RoundedCornerShape(6.dp),
                    color = previewSurfaceColor,
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 16.dp, horizontal = 12.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        val previewCfg = remember(cfg) {
                            cfg.copy(indicatorScale = cfg.indicatorScale.coerceAtMost(2.2f))
                        }
                        val previewConn = remember(previewStateIdx) {
                            when (previewStateIdx) {
                                1 -> ConnectionUiState(connStatus = ConnStatus.CONNECTED, connected = true, isMuted = true)
                                2 -> ConnectionUiState(connStatus = ConnStatus.SEARCHING, connected = false, isMuted = false)
                                else -> ConnectionUiState(connStatus = ConnStatus.CONNECTED, connected = true, isMuted = false)
                            }
                        }
                        val previewOverride: Boolean? = when (previewStateIdx) {
                            1 -> true
                            2 -> null
                            else -> false
                        }

                        AndroidView(
                            factory = { ctx -> MicPillCanvasView(ctx) },
                            update = { view ->
                                view.updateRenderState(
                                    cfg = previewCfg,
                                    conn = previewConn,
                                    alpha = cfg.opacityLevel,
                                    mutedOverride = previewOverride
                                )
                                view.requestLayout()
                            }
                        )

                        if (cfg.indicatorScale > 2.2f) {
                            Text(
                                text = "Preview scaled down to fit card; actual floating pill uses full ${cfg.indicatorScale}x size.",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                }

                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    listOf(0 to "Preview LIVE", 1 to "Preview MUTED", 2 to "Preview OFFLINE").forEach { (idx, title) ->
                        FilterChip(
                            selected = previewStateIdx == idx,
                            onClick = { previewStateIdx = idx },
                            label = { Text(title) }
                        )
                    }
                }

                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

                Text(
                    text = "Control App Theme (Windows 11 / Explorer Palette)",
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.Medium
                )
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    ThemeMode.entries.forEach { mode ->
                        val selected = cfg.themeMode == mode
                        FilterChip(
                            selected = selected,
                            onClick = { app.configStore.update { it.copy(themeMode = mode) } },
                            leadingIcon = if (selected) {
                                { Icon(Icons.Default.Check, contentDescription = null, modifier = Modifier.size(16.dp)) }
                            } else {
                                null
                            },
                            label = { Text(mode.label) }
                        )
                    }
                }
            }
        }

        // 2. HUD Color Palette, Opacity & Scale Card
        ExplorerCard(contentPadding = 18) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(
                    text = "HUD Color Palette & Tally Styling",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold
                )
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    HudColorPalettes.presetNames.forEach { name ->
                        val pal = remember(name) { HudColorPalettes.get(name) }
                        val selected = cfg.hudColorPreset.equals(name, ignoreCase = true)
                        FilterChip(
                            selected = selected,
                            onClick = { app.configStore.update { it.copy(hudColorPreset = name) } },
                            leadingIcon = {
                                Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                                    Box(
                                        modifier = Modifier
                                            .size(10.dp)
                                            .clip(CircleShape)
                                            .background(Color(pal.liveBg))
                                            .border(0.5.dp, Color.White.copy(alpha = 0.4f), CircleShape)
                                    )
                                    Box(
                                        modifier = Modifier
                                            .size(10.dp)
                                            .clip(CircleShape)
                                            .background(Color(pal.mutedBg))
                                            .border(0.5.dp, Color.White.copy(alpha = 0.4f), CircleShape)
                                    )
                                }
                            },
                            label = { Text(name) }
                        )
                    }
                }

                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

                Text(
                    text = "Transparency Level",
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.Medium
                )
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    OPACITY_OPTIONS.forEach { (alphaVal, label) ->
                        FilterChip(
                            selected = cfg.opacityLevel == alphaVal,
                            onClick = { app.configStore.update { it.copy(opacityLevel = alphaVal) } },
                            label = { Text(label) }
                        )
                    }
                }

                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

                Text(
                    text = "Indicator Scale (Smart Board 65\"–86\" Ready)",
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.Medium
                )
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    SCALE_OPTIONS.forEach { (scaleVal, label) ->
                        val selected = kotlin.math.abs(cfg.indicatorScale - scaleVal) < 0.01f
                        FilterChip(
                            selected = selected,
                            onClick = { app.configStore.update { it.copy(indicatorScale = scaleVal) } },
                            label = { Text(label) }
                        )
                    }
                }

                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

                ExplorerSettingToggleRow(
                    title = "Show Text Label (\"LIVE\" / \"MUTED\")",
                    subtitle = "Switch between compact icon-only pill and text badge",
                    checked = cfg.showText,
                    onCheckedChange = { v -> app.configStore.update { it.copy(showText = v) } }
                )
                ExplorerSettingToggleRow(
                    title = "Monochrome Contrast Icon",
                    subtitle = "Render dark-tinted microphone glyph matching the active color preset",
                    checked = cfg.monoIcon,
                    onCheckedChange = { v -> app.configStore.update { it.copy(monoIcon = v) } }
                )
                ExplorerSettingToggleRow(
                    title = "Sleek Capsule Corners",
                    subtitle = "Use fully rounded capsule corners instead of standard 8dp Fluent radius",
                    checked = cfg.sleekCorners,
                    onCheckedChange = { v -> app.configStore.update { it.copy(sleekCorners = v) } }
                )
                ExplorerSettingToggleRow(
                    title = "Aggressive Muted Pulse",
                    subtitle = "Faster, deeper warning pulse animation while the microphone is muted",
                    checked = cfg.aggressivePulse,
                    showDivider = false,
                    onCheckedChange = { v -> app.configStore.update { it.copy(aggressivePulse = v) } }
                )
            }
        }

        // 3. Smart Board Ergonomics, Audio/Toast Feedback & Reset Card
        ExplorerCard(contentPadding = 18) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(
                    text = "Smart Board Ergonomics, Feedback & Startup",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold
                )
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

                ExplorerSettingToggleRow(
                    title = "Interactive Pill Tap Actions",
                    subtitle = "Tap the floating pill directly on touchscreen to mute/unmute host mic",
                    checked = cfg.enableHudClickActions,
                    onCheckedChange = { v -> app.configStore.update { it.copy(enableHudClickActions = v) } }
                )
                ExplorerSettingToggleRow(
                    title = "Magnetic Edge & Center Snap (14dp)",
                    subtitle = "Snap cleanly to screen safe-area borders and centerlines while dragging",
                    checked = cfg.enableMagneticSnap,
                    onCheckedChange = { v -> app.configStore.update { it.copy(enableMagneticSnap = v) } }
                )
                ExplorerSettingToggleRow(
                    title = "Auto-Dodge on Hover",
                    subtitle = "Temporarily fade pill to ghost pass-through when stylus/pointer hovers",
                    checked = cfg.hudAutoDodge,
                    onCheckedChange = { v -> app.configStore.update { it.copy(hudAutoDodge = v) } }
                )
                ExplorerSettingToggleRow(
                    title = "Click-Through Pill Mode",
                    subtitle = "Touches pass through pill to whiteboard underneath; unlock via Notification or Quick Tile",
                    checked = cfg.hudClickThrough,
                    onCheckedChange = { v -> app.configStore.update { it.copy(hudClickThrough = v) } }
                )
                ExplorerSettingToggleRow(
                    title = "Two-Tone Acoustic Audio Chime",
                    subtitle = "Synthesized 880Hz↔520Hz tone chime on mic mute state change",
                    checked = cfg.enableAudioCue,
                    onCheckedChange = { v -> app.configStore.update { it.copy(enableAudioCue = v) } }
                )
                ExplorerSettingToggleRow(
                    title = "Show 2s Floating Mute Toast",
                    subtitle = "Display brief 'Mic: MUTED' / 'Mic: LIVE' Explorer badge near the pill",
                    checked = cfg.enableMuteToast,
                    onCheckedChange = { v -> app.configStore.update { it.copy(enableMuteToast = v) } }
                )
                ExplorerSettingToggleRow(
                    title = "Start HUD Automatically on Boot",
                    subtitle = "Auto-start PresenterSync Remote when Android powers on (OFF by default)",
                    checked = cfg.startOnBoot,
                    showDivider = false,
                    onCheckedChange = { v -> app.configStore.update { it.copy(startOnBoot = v) } }
                )

                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    OutlinedButton(
                        onClick = {
                            app.configStore.resetPosition()
                            Toast.makeText(context, "Pill position reset to bottom-right", Toast.LENGTH_SHORT).show()
                        },
                        modifier = Modifier.weight(1f)
                    ) {
                        Icon(Icons.Default.Refresh, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("Reset Position")
                    }
                    OutlinedButton(
                        onClick = {
                            app.configStore.resetAppearance()
                            Toast.makeText(context, "HUD appearance reset to defaults", Toast.LENGTH_SHORT).show()
                        },
                        modifier = Modifier.weight(1f)
                    ) {
                        Icon(Icons.Default.RestartAlt, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("Reset Appearance")
                    }
                }
            }
        }
    }
}

@Composable
internal fun ExplorerSettingToggleRow(
    title: String,
    subtitle: String,
    checked: Boolean,
    showDivider: Boolean = true,
    onCheckedChange: (Boolean) -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Column(modifier = Modifier.weight(1f).padding(end = 12.dp)) {
            Text(title, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
            Text(
                text = subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange
        )
    }
    if (showDivider) {
        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
    }
}
