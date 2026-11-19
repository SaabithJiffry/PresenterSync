package com.saabithjiffry.presentersync.remote.ui.screens

import android.widget.Toast
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
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
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.RestartAlt
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.saabithjiffry.presentersync.remote.PresenterSyncRemoteApp
import com.saabithjiffry.presentersync.remote.config.AppConstants
import com.saabithjiffry.presentersync.remote.config.HudColorPalettes
import com.saabithjiffry.presentersync.remote.config.ThemeMode
import com.saabithjiffry.presentersync.remote.config.rememberFormFactor
import com.saabithjiffry.presentersync.remote.input.BubbleGestureAction
import com.saabithjiffry.presentersync.remote.network.ConnStatus
import com.saabithjiffry.presentersync.remote.network.ConnectionUiState
import com.saabithjiffry.presentersync.remote.ui.overlay.MicPillCanvasView
import com.saabithjiffry.presentersync.remote.ui.theme.CompactExplorerButtonPadding
import com.saabithjiffry.presentersync.remote.ui.theme.ExplorerCard
import com.saabithjiffry.presentersync.remote.ui.theme.ResponsiveExplorerActionRow

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
    val formFactor = rememberFormFactor(cfg.deviceProfileMode)
    var previewStateIdx by remember { mutableIntStateOf(0) } // 0 = LIVE, 1 = MUTED, 2 = OFFLINE

    Column(
        modifier = Modifier
            .widthIn(max = if (formFactor.isWideTwoColumn) 980.dp else 760.dp)
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(formFactor.outerPaddingDp.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        // 1. Live Floating Pill Preview & Windows 11 App Theme Card
        ExplorerCard(contentPadding = formFactor.cardPaddingDp) {
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
                        val previewCfg = remember(cfg, formFactor.previewMaxScale) {
                            cfg.copy(indicatorScale = cfg.indicatorScale.coerceAtMost(formFactor.previewMaxScale))
                        }
                        val previewConn = remember(previewStateIdx) {
                            when (previewStateIdx) {
                                1 -> ConnectionUiState(connStatus = ConnStatus.CONNECTED, connected = true, isMuted = true)
                                2 -> ConnectionUiState(connStatus = ConnStatus.SEARCHING, connected = false, isMuted = false)
                                3 -> ConnectionUiState(connStatus = ConnStatus.AUTH_FAILED, connected = false, isMuted = false)
                                else -> ConnectionUiState(connStatus = ConnStatus.CONNECTED, connected = true, isMuted = false)
                            }
                        }
                        val previewOverride: Boolean? = when (previewStateIdx) {
                            1 -> true
                            2, 3 -> null
                            else -> false
                        }

                        val density = LocalDensity.current
                        BoxWithConstraints(
                            modifier = Modifier.fillMaxWidth(),
                            contentAlignment = Alignment.Center
                        ) {
                            val maxPreviewWidthPx = with(density) { maxWidth.roundToPx().coerceAtLeast(120) }
                            AndroidView(
                                factory = { ctx -> MicPillCanvasView(ctx) },
                                update = { view ->
                                    view.updateRenderState(
                                        cfg = previewCfg,
                                        conn = previewConn,
                                        alpha = cfg.opacityLevel,
                                        mutedOverride = previewOverride,
                                        maxContainerWidthPx = maxPreviewWidthPx
                                    )
                                    view.requestLayout()
                                }
                            )
                        }

                        if (cfg.indicatorScale > formFactor.previewMaxScale) {
                            Text(
                                text = "Preview scaled to ${formFactor.previewMaxScale}x inside card; overlay pill uses up to ${cfg.indicatorScale}x within screen bounds.",
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
                    listOf(
                        0 to "Preview LIVE",
                        1 to "Preview MUTED",
                        2 to "Preview OFFLINE",
                        3 to "Preview AUTH ERR"
                    ).forEach { (idx, title) ->
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
                        val pal = remember(name, cfg.customLiveHex, cfg.customMutedHex) {
                            HudColorPalettes.get(name, cfg.customLiveHex, cfg.customMutedHex)
                        }
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

                if (cfg.hudColorPreset.equals("Custom", ignoreCase = true)) {
                    var liveHexDraft by remember(cfg.customLiveHex) { mutableStateOf(cfg.customLiveHex) }
                    var mutedHexDraft by remember(cfg.customMutedHex) { mutableStateOf(cfg.customMutedHex) }
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        OutlinedTextField(
                            value = liveHexDraft,
                            onValueChange = { v ->
                                liveHexDraft = v.take(7)
                                val clean = v.trim().removePrefix("#").removePrefix("0x")
                                if (clean.matches(Regex("^[0-9A-Fa-f]{6}$"))) {
                                    app.configStore.update { it.copy(customLiveHex = "#${clean.uppercase()}") }
                                }
                            },
                            label = { Text("Live Hex") },
                            singleLine = true,
                            modifier = Modifier.weight(1f)
                        )
                        OutlinedTextField(
                            value = mutedHexDraft,
                            onValueChange = { v ->
                                mutedHexDraft = v.take(7)
                                val clean = v.trim().removePrefix("#").removePrefix("0x")
                                if (clean.matches(Regex("^[0-9A-Fa-f]{6}$"))) {
                                    app.configStore.update { it.copy(customMutedHex = "#${clean.uppercase()}") }
                                }
                            },
                            label = { Text("Muted Hex") },
                            singleLine = true,
                            modifier = Modifier.weight(1f)
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
                    text = if (formFactor.isPhone) {
                        "Indicator Scale (Auto-Bounded to Phone Width)"
                    } else {
                        "Indicator Scale (Smart Board 65\"–86\" Ready)"
                    },
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

        // 3. Customizable Floating Bubble Multi-Gestures Card
        ExplorerCard(contentPadding = formFactor.cardPaddingDp) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(
                    text = "Floating Bubble Multi-Gestures",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    text = "Prevent accidental smartboard taps by mapping Single Tap, Double Tap, Long Press, and Very Long Press independently.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

                ExplorerSettingToggleRow(
                    title = "Enable Bubble Tap & Hold Gestures",
                    subtitle = "Master switch for all touchscreen gestures on the floating pill (dragging still works unless locked)",
                    checked = cfg.enableHudClickActions,
                    onCheckedChange = { v -> app.configStore.update { it.copy(enableHudClickActions = v) } }
                )
                ExplorerSettingToggleRow(
                    title = "Lock Pill Position (Prevent Drag)",
                    subtitle = "Anchor the bubble in place so casual touches or whiteboard sleeves cannot move it",
                    checked = cfg.lockHudPosition,
                    onCheckedChange = { v -> app.configStore.update { it.copy(lockHudPosition = v) } }
                )
                ExplorerSettingToggleRow(
                    title = "Hide HUD from Screen Share / Capture",
                    subtitle = "Apply FLAG_SECURE so screen sharing, OBS capture, and screenshots exclude the floating HUD",
                    checked = cfg.hideFromScreenCapture,
                    onCheckedChange = { v -> app.configStore.update { it.copy(hideFromScreenCapture = v) } }
                )
                ExplorerSettingToggleRow(
                    title = "Require 2nd-Tap Confirm (3s) Before Stopping Recording",
                    subtitle = "Prevents accidental taps from stopping an active OBS recording (1st tap arms 3s amber confirmation)",
                    checked = cfg.confirmBeforeStopRecording,
                    onCheckedChange = { v -> app.configStore.update { it.copy(confirmBeforeStopRecording = v) } }
                )
                ExplorerSettingToggleRow(
                    title = "Show Pill Mini-Badges (Timer / BRB / REC / Voice Alert)",
                    subtitle = "Display compact timer, BRB, REC badges and amber voice-while-muted border on the floating pill",
                    checked = cfg.showPillMiniBadges,
                    onCheckedChange = { v -> app.configStore.update { it.copy(showPillMiniBadges = v) } }
                )
                ExplorerSettingToggleRow(
                    title = "Push-to-Talk Mode (Hold Pill to Unmute)",
                    subtitle = "Press and hold floating pill to unmute; releasing immediately mutes mic again. Enabling Push-to-Talk disables Long-Press, Very-Long-Press, and Push-to-Mute (and vice versa).",
                    checked = cfg.enablePushToTalk,
                    onCheckedChange = { v ->
                        app.configStore.update {
                            it.copy(
                                enablePushToTalk = v,
                                enablePushToMute = if (v) false else it.enablePushToMute,
                                longPressAction = if (v) BubbleGestureAction.NONE else it.longPressAction,
                                veryLongPressAction = if (v) BubbleGestureAction.NONE else it.veryLongPressAction
                            )
                        }
                    }
                )

                Text(
                    text = "Quick Gesture Presets",
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.primary
                )
                val isSafeDefault = cfg.singleTapAction == BubbleGestureAction.NONE &&
                    cfg.doubleTapAction == BubbleGestureAction.OPEN_QUICK_MENU &&
                    cfg.longPressAction == BubbleGestureAction.TOGGLE_MUTE &&
                    cfg.veryLongPressAction == BubbleGestureAction.NONE
                val isHoldSplit = cfg.singleTapAction == BubbleGestureAction.NONE &&
                    cfg.longPressAction == BubbleGestureAction.MUTE_ONLY &&
                    cfg.veryLongPressAction == BubbleGestureAction.UNMUTE_ONLY
                val isClassicTap = cfg.singleTapAction == BubbleGestureAction.TOGGLE_MUTE &&
                    cfg.doubleTapAction == BubbleGestureAction.NONE &&
                    cfg.longPressAction == BubbleGestureAction.OPEN_QUICK_MENU

                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    FilterChip(
                        selected = isSafeDefault,
                        onClick = { app.configStore.applyGesturePreset("smartboard_safe") },
                        label = { Text("Smart Board Safe") }
                    )
                    FilterChip(
                        selected = isHoldSplit,
                        onClick = { app.configStore.applyGesturePreset("hold_mute_unmute") },
                        label = { Text("Separate Hold Mute / Unmute") }
                    )
                    FilterChip(
                        selected = isClassicTap,
                        onClick = { app.configStore.applyGesturePreset("classic_tap") },
                        label = { Text("Classic Quick Tap") }
                    )
                }

                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

                BubbleGestureSlotRow(
                    title = "Single Tap",
                    subtitle = "Keep as None on busy touch panels so accidental touches never toggle mute",
                    currentAction = cfg.singleTapAction,
                    enabled = cfg.enableHudClickActions,
                    isTightWidth = formFactor.isTightWidth,
                    onSelect = { act -> app.configStore.update { it.copy(singleTapAction = act) } }
                )
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                BubbleGestureSlotRow(
                    title = "Double Tap",
                    subtitle = "Quick double tap on the floating pill (default: Open Quick Menu)",
                    currentAction = cfg.doubleTapAction,
                    enabled = cfg.enableHudClickActions,
                    isTightWidth = formFactor.isTightWidth,
                    onSelect = { act -> app.configStore.update { it.copy(doubleTapAction = act) } }
                )
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                BubbleGestureSlotRow(
                    title = "Long Press (${cfg.longPressDurationMs} ms)",
                    subtitle = "Hold until amber arc completes & buzzes; lift before Very Long threshold (selecting an action disables Push-to-Talk)",
                    currentAction = cfg.longPressAction,
                    enabled = cfg.enableHudClickActions,
                    isTightWidth = formFactor.isTightWidth,
                    onSelect = { act ->
                        app.configStore.update {
                            it.copy(
                                longPressAction = act,
                                enablePushToTalk = if (act != BubbleGestureAction.NONE) false else it.enablePushToTalk
                            )
                        }
                    }
                )
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                BubbleGestureSlotRow(
                    title = "Very Long Press (${cfg.veryLongPressDurationMs} ms)",
                    subtitle = "Keep holding past amber buzz until blue arc completes & triggers immediately (selecting an action disables Push-to-Talk)",
                    currentAction = cfg.veryLongPressAction,
                    enabled = cfg.enableHudClickActions,
                    isTightWidth = formFactor.isTightWidth,
                    onSelect = { act ->
                        app.configStore.update {
                            it.copy(
                                veryLongPressAction = act,
                                enablePushToTalk = if (act != BubbleGestureAction.NONE) false else it.enablePushToTalk
                            )
                        }
                    }
                )

                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    val longSliderVal = cfg.longPressDurationMs.coerceIn(350, 1200)
                    Text(
                        text = "Long Press Hold Duration: $longSliderVal ms",
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.Medium
                    )
                    Slider(
                        value = longSliderVal.toFloat(),
                        onValueChange = { v ->
                            val snapped = ((v / 25f).toInt() * 25).coerceIn(350, 1200)
                            app.configStore.update { prev ->
                                prev.copy(
                                    longPressDurationMs = snapped,
                                    veryLongPressDurationMs = prev.veryLongPressDurationMs.coerceAtLeast(snapped + 300)
                                )
                            }
                        },
                        valueRange = 350f..1200f,
                        enabled = cfg.enableHudClickActions
                    )
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        listOf(350, 600, 900, 1200).forEach { ms ->
                            FilterChip(
                                selected = longSliderVal == ms,
                                enabled = cfg.enableHudClickActions,
                                onClick = {
                                    app.configStore.update { prev ->
                                        prev.copy(
                                            longPressDurationMs = ms,
                                            veryLongPressDurationMs = prev.veryLongPressDurationMs.coerceAtLeast(ms + 300)
                                        )
                                    }
                                },
                                label = { Text("${ms}ms") }
                            )
                        }
                    }
                }

                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    val minVeryLong = (cfg.longPressDurationMs + 300).coerceIn(900, 2500)
                    val veryLongSliderVal = cfg.veryLongPressDurationMs.coerceIn(minVeryLong, 2500)
                    Text(
                        text = "Very Long Press Hold Duration: $veryLongSliderVal ms",
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.Medium
                    )
                    Slider(
                        value = veryLongSliderVal.toFloat(),
                        onValueChange = { v ->
                            val snapped = ((v / 50f).toInt() * 50).coerceIn(minVeryLong, 2500)
                            app.configStore.update { it.copy(veryLongPressDurationMs = snapped) }
                        },
                        valueRange = minVeryLong.toFloat()..2500f,
                        enabled = cfg.enableHudClickActions
                    )
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        listOf(900, 1400, 1900, 2500).filter { it >= minVeryLong }.forEach { ms ->
                            FilterChip(
                                selected = veryLongSliderVal == ms,
                                enabled = cfg.enableHudClickActions,
                                onClick = {
                                    app.configStore.update { it.copy(veryLongPressDurationMs = ms) }
                                },
                                label = { Text("${ms}ms") }
                            )
                        }
                    }
                }
            }
        }

        // 4. Smart Board Ergonomics, Audio/Toast Feedback & Reset Card
        ExplorerCard(contentPadding = formFactor.cardPaddingDp) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(
                    text = "Smart Board Ergonomics, Feedback & Startup",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold
                )
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

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
                    title = "Voice-While-Muted Alert",
                    subtitle = "Alert subtly when Host microphone picks up speech for 1.5s while muted",
                    checked = cfg.enableVoiceWhileMutedAlert,
                    onCheckedChange = { v -> app.configStore.update { it.copy(enableVoiceWhileMutedAlert = v) } }
                )
                ExplorerSettingToggleRow(
                    title = "Keep Screen Awake (Smart Board / Phone)",
                    subtitle = "Keep screen on while dashboard or floating HUD is active during sessions",
                    checked = cfg.keepScreenOn,
                    onCheckedChange = { v -> app.configStore.update { it.copy(keepScreenOn = v) } }
                )
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(
                        text = "Idle HUD Auto-Dim",
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.Medium
                    )
                    Text(
                        text = "Softly dim floating pill when idle and wake instantly on touch, hover, or mute changes",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    FlowRow(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        listOf(0 to "Off", 15 to "15s", 30 to "30s", 60 to "60s", 120 to "120s").forEach { (sec, label) ->
                            FilterChip(
                                selected = cfg.idleDimAfterSec == sec,
                                onClick = { app.configStore.update { it.copy(idleDimAfterSec = sec) } },
                                label = { Text(label) }
                            )
                        }
                    }
                }
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                ExplorerSettingToggleRow(
                    title = "Start HUD Automatically on Boot",
                    subtitle = "Auto-start PresenterSync Remote when Android powers on (OFF by default)",
                    checked = cfg.startOnBoot,
                    showDivider = false,
                    onCheckedChange = { v -> app.configStore.update { it.copy(startOnBoot = v) } }
                )

                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

                FlowRow(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    OutlinedButton(
                        onClick = {
                            app.configStore.resetPosition()
                            Toast.makeText(context, "Pill position reset to bottom-right", Toast.LENGTH_SHORT).show()
                        },
                        contentPadding = CompactExplorerButtonPadding
                    ) {
                        Icon(Icons.Default.Refresh, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("Reset Position", maxLines = 1, softWrap = false, overflow = TextOverflow.Ellipsis)
                    }
                    OutlinedButton(
                        onClick = {
                            app.configStore.resetAppearance()
                            Toast.makeText(context, "HUD appearance reset to defaults", Toast.LENGTH_SHORT).show()
                        },
                        contentPadding = CompactExplorerButtonPadding
                    ) {
                        Icon(Icons.Default.RestartAlt, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("Reset Appearance", maxLines = 1, softWrap = false, overflow = TextOverflow.Ellipsis)
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

@Composable
private fun BubbleGestureSlotRow(
    title: String,
    subtitle: String,
    currentAction: BubbleGestureAction,
    enabled: Boolean,
    isTightWidth: Boolean,
    onSelect: (BubbleGestureAction) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }

    ResponsiveExplorerActionRow(
        title = title,
        subtitle = "$subtitle\nCurrent: ${currentAction.label}",
        subtitleColor = if (enabled) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
        isTightWidth = isTightWidth
    ) {
        Box {
            OutlinedButton(
                onClick = { expanded = true },
                enabled = enabled,
                contentPadding = CompactExplorerButtonPadding
            ) {
                Text(
                    text = currentAction.label,
                    maxLines = 1,
                    softWrap = false,
                    overflow = TextOverflow.Ellipsis
                )
                Spacer(Modifier.width(4.dp))
                Icon(Icons.Default.ArrowDropDown, contentDescription = null, modifier = Modifier.size(18.dp))
            }
            DropdownMenu(
                expanded = expanded,
                onDismissRequest = { expanded = false }
            ) {
                BubbleGestureAction.entries.forEach { act ->
                    DropdownMenuItem(
                        text = {
                            Column {
                                Text(act.label, fontWeight = if (act == currentAction) FontWeight.Bold else FontWeight.Normal)
                                Text(
                                    act.shortDesc,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        },
                        leadingIcon = if (act == currentAction) {
                            { Icon(Icons.Default.Check, contentDescription = null, modifier = Modifier.size(16.dp)) }
                        } else null,
                        onClick = {
                            expanded = false
                            onSelect(act)
                        }
                    )
                }
            }
        }
    }
}
