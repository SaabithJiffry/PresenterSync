package com.saabithjiffry.presentersync.remote.ui.theme

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.saabithjiffry.presentersync.remote.config.ThemeMode

private val DarkPalette = darkColorScheme(
    primary = Color(0xFF60CDFF),
    onPrimary = Color(0xFF002438),
    primaryContainer = Color(0xFF1E3A4C),
    onPrimaryContainer = Color(0xFFBDE8FF),
    background = Color(0xFF202020),
    onBackground = Color(0xFFFFFFFF),
    surface = Color(0xFF2C2C2C),
    onSurface = Color(0xFFFFFFFF),
    surfaceVariant = Color(0xFF272727),
    onSurfaceVariant = Color(0xFFC5C5C5),
    outline = Color(0xFF3D3D3D),
    outlineVariant = Color(0xFF353535),
    error = Color(0xFFEF4444),
    errorContainer = Color(0xFF3F1D1D),
    onErrorContainer = Color(0xFFFCA5A5)
)

private val LightPalette = lightColorScheme(
    primary = Color(0xFF0067C0),
    onPrimary = Color(0xFFFFFFFF),
    primaryContainer = Color(0xFFE6F2FC),
    onPrimaryContainer = Color(0xFF003D75),
    background = Color(0xFFF3F3F3),
    onBackground = Color(0xFF1A1A1A),
    surface = Color(0xFFFFFFFF),
    onSurface = Color(0xFF1A1A1A),
    surfaceVariant = Color(0xFFF9F9F9),
    onSurfaceVariant = Color(0xFF5C5C5C),
    outline = Color(0xFFE1E1E1),
    outlineVariant = Color(0xFFEBEBEB),
    error = Color(0xFFDC2626),
    errorContainer = Color(0xFFFEF2F2),
    onErrorContainer = Color(0xFF991B1B)
)

private val Win11Shapes = Shapes(
    extraSmall = RoundedCornerShape(4.dp),
    small = RoundedCornerShape(6.dp),
    medium = RoundedCornerShape(8.dp),
    large = RoundedCornerShape(8.dp),
    extraLarge = RoundedCornerShape(10.dp)
)

@Composable
fun PresenterSyncTheme(
    themeMode: ThemeMode,
    content: @Composable () -> Unit
) {
    val dark = when (themeMode) {
        ThemeMode.DARK -> true
        ThemeMode.LIGHT -> false
        ThemeMode.SYSTEM -> isSystemInDarkTheme()
    }
    MaterialTheme(
        colorScheme = if (dark) DarkPalette else LightPalette,
        shapes = Win11Shapes,
        content = content
    )
}

/**
 * Windows 11 Fluent / Explorer layered card surface with crisp 1dp border and zero fuzzy shadow.
 */
@Composable
fun ExplorerCard(
    modifier: Modifier = Modifier,
    containerColor: Color = MaterialTheme.colorScheme.surface,
    borderColor: Color = MaterialTheme.colorScheme.outline,
    contentPadding: Int = 16,
    content: @Composable ColumnScope.() -> Unit
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(8.dp),
        colors = CardDefaults.cardColors(containerColor = containerColor),
        border = BorderStroke(1.dp, borderColor),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(contentPadding.dp),
            content = content
        )
    }
}

val CompactExplorerButtonPadding = PaddingValues(horizontal = 12.dp, vertical = 10.dp)

/**
 * Responsive label + action row that stacks cleanly on compact Android phone widths
 * (360dp-412dp) instead of squeezing text to a few characters wide.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ResponsiveExplorerActionRow(
    title: String,
    subtitle: String? = null,
    isTightWidth: Boolean,
    titleColor: Color = Color.Unspecified,
    subtitleColor: Color = MaterialTheme.colorScheme.onSurfaceVariant,
    action: @Composable () -> Unit
) {
    if (isTightWidth) {
        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    text = title,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                    color = titleColor
                )
                if (!subtitle.isNullOrBlank()) {
                    Text(
                        text = subtitle,
                        style = MaterialTheme.typography.bodySmall,
                        color = subtitleColor
                    )
                }
            }
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                action()
            }
        }
    } else {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Column(
                modifier = Modifier
                    .weight(1f)
                    .padding(end = 12.dp),
                verticalArrangement = Arrangement.spacedBy(2.dp)
            ) {
                Text(
                    text = title,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                    color = titleColor
                )
                if (!subtitle.isNullOrBlank()) {
                    Text(
                        text = subtitle,
                        style = MaterialTheme.typography.bodySmall,
                        color = subtitleColor
                    )
                }
            }
            action()
        }
    }
}
