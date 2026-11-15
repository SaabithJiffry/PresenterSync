package com.saabithjiffry.presentersync.remote.config

import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlin.math.max
import kotlin.math.min

enum class DeviceProfileMode(
    val rawValue: String,
    val label: String,
    val shortLabel: String
) {
    AUTO("Auto", "Auto-Detect Screen", "Auto"),
    SMART_BOARD("SmartBoard", "65\" Smart Board (Panel)", "Smart Board"),
    PHONE("Phone", "Mobile Phone (Compact)", "Phone");

    companion object {
        fun fromRaw(raw: String?): DeviceProfileMode {
            val norm = raw?.trim()?.lowercase().orEmpty()
            return when {
                norm.contains("board") || norm == "panel" || norm == "tv" -> SMART_BOARD
                norm.contains("phone") || norm == "mobile" -> PHONE
                else -> AUTO
            }
        }
    }
}

enum class FormFactorClass(val label: String) {
    COMPACT_PHONE("Mobile Phone"),
    TABLET("Tablet"),
    LARGE_BOARD("65\" Smart Board")
}

data class ResolvedFormFactor(
    val selectedMode: DeviceProfileMode,
    val deviceClass: FormFactorClass,
    val widthDp: Int,
    val heightDp: Int,
    val smallestWidthDp: Int,
    val isLandscape: Boolean,
    val isPhone: Boolean,
    val isLargeBoard: Boolean,
    val isWideTwoColumn: Boolean,
    val isTightWidth: Boolean,
    val isCompactHeight: Boolean,
    val recommendedScale: Float,
    val recommendedShowText: Boolean,
    val recommendedSleekCorners: Boolean,
    val badgeText: String,
    val recommendationHint: String,
    val outerPaddingDp: Int,
    val cardPaddingDp: Int,
    val dialogMaxWidthDp: Dp,
    val dialogWidthFraction: Float,
    val dialogMaxHeightFraction: Float,
    val previewMaxScale: Float
)

object FormFactorResolver {
    fun resolve(
        mode: DeviceProfileMode,
        widthDp: Int,
        heightDp: Int,
        smallestWidthDp: Int
    ): ResolvedFormFactor {
        val safeW = widthDp.coerceAtLeast(320)
        val safeH = heightDp.coerceAtLeast(320)
        val safeSw = smallestWidthDp.coerceAtLeast(320)
        val isLandscape = safeW > safeH
        val maxDim = max(safeW, safeH)
        val minDim = min(safeW, safeH)

        val autoClass = when {
            safeSw < 600 || minDim < 600 -> FormFactorClass.COMPACT_PHONE
            safeSw >= 720 || maxDim >= 1000 -> FormFactorClass.LARGE_BOARD
            else -> FormFactorClass.TABLET
        }

        val resolvedClass = when (mode) {
            DeviceProfileMode.SMART_BOARD -> FormFactorClass.LARGE_BOARD
            DeviceProfileMode.PHONE -> FormFactorClass.COMPACT_PHONE
            DeviceProfileMode.AUTO -> autoClass
        }

        val isPhone = resolvedClass == FormFactorClass.COMPACT_PHONE
        val isLargeBoard = resolvedClass == FormFactorClass.LARGE_BOARD
        val isWideTwoColumn = safeW >= 840 && !isPhone
        val isTightWidth = safeW < 420
        val isCompactHeight = safeH < 520

        val recScale = when (resolvedClass) {
            FormFactorClass.COMPACT_PHONE -> 1.0f
            FormFactorClass.TABLET -> 1.5f
            FormFactorClass.LARGE_BOARD -> 2.0f
        }
        val recShowText = !isPhone
        val recSleek = isPhone

        val orientSuffix = if (isLandscape) "Landscape" else "Portrait"
        val badgeText = "${resolvedClass.label} ($orientSuffix • ${safeW}×${safeH}dp)"
        val hint = when (resolvedClass) {
            FormFactorClass.LARGE_BOARD ->
                "Smart Board preset applies 2.0x pill visibility, LIVE/MUTED text label, hover auto-dodge, and wide 2-column classroom layout."
            FormFactorClass.TABLET ->
                "Tablet preset applies 1.5x pill scale, LIVE/MUTED label, and balanced Explorer spacing."
            FormFactorClass.COMPACT_PHONE ->
                "Phone preset (Poco M3 / Redmi Note 12 / Galaxy A07) applies 1.0x sleek pill, compact portrait buttons, and rotation-safe corner lock."
        }

        val outerPad = if (isTightWidth) 12 else 16
        val cardPad = if (isTightWidth) 14 else 18
        val dialogMaxW = if (isPhone) 560.dp else 740.dp
        val dialogFrac = if (isPhone) 0.96f else 0.90f
        val dialogMaxHFrac = if (isCompactHeight) 0.94f else 0.88f
        val previewMaxScale = if (isTightWidth) 1.55f else if (isPhone) 1.85f else 2.4f

        return ResolvedFormFactor(
            selectedMode = mode,
            deviceClass = resolvedClass,
            widthDp = safeW,
            heightDp = safeH,
            smallestWidthDp = safeSw,
            isLandscape = isLandscape,
            isPhone = isPhone,
            isLargeBoard = isLargeBoard,
            isWideTwoColumn = isWideTwoColumn,
            isTightWidth = isTightWidth,
            isCompactHeight = isCompactHeight,
            recommendedScale = recScale,
            recommendedShowText = recShowText,
            recommendedSleekCorners = recSleek,
            badgeText = badgeText,
            recommendationHint = hint,
            outerPaddingDp = outerPad,
            cardPaddingDp = cardPad,
            dialogMaxWidthDp = dialogMaxW,
            dialogWidthFraction = dialogFrac,
            dialogMaxHeightFraction = dialogMaxHFrac,
            previewMaxScale = previewMaxScale
        )
    }
}

@Composable
fun rememberFormFactor(profileMode: DeviceProfileMode): ResolvedFormFactor {
    val cfg = LocalConfiguration.current
    return FormFactorResolver.resolve(
        mode = profileMode,
        widthDp = cfg.screenWidthDp,
        heightDp = cfg.screenHeightDp,
        smallestWidthDp = cfg.smallestScreenWidthDp
    )
}
