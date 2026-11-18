package com.saabithjiffry.presentersync.remote.ui.overlay

import android.content.Context
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import com.saabithjiffry.presentersync.remote.config.AppConstants
import com.saabithjiffry.presentersync.remote.config.RemoteConfig
import com.saabithjiffry.presentersync.remote.config.ThemeMode
import kotlin.math.roundToInt

/**
 * Displays a non-focusable, non-touchable Windows 11 Explorer-styled floating banner
 * ("Mic: MUTED" / "Mic: LIVE") above or below the floating HUD pill for 2 seconds when mute changes.
 */
class FloatingToastBannerManager(
    private val context: Context
) {
    private val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private val handler = Handler(Looper.getMainLooper())

    private var bannerView: LinearLayout? = null
    private var attached = false

    private val dismissRunnable = Runnable { hide() }

    fun showMuteToast(isMuted: Boolean, cfg: RemoteConfig, anchorX: Int, anchorY: Int, pillHeightPx: Int) {
        val text = if (isMuted) "Mic: MUTED" else "Mic: LIVE"
        val dotColor = if (isMuted) Color.parseColor("#EF4444") else Color.parseColor("#22C55E")
        showBanner(text, dotColor, cfg, anchorX, anchorY, pillHeightPx, AppConstants.TOOLTIP_DURATION_MS)
    }

    fun showAlertToast(
        message: String,
        accentDotColor: Int,
        cfg: RemoteConfig,
        anchorX: Int,
        anchorY: Int,
        pillHeightPx: Int,
        durationMs: Long = 3200L
    ) {
        showBanner(message, accentDotColor, cfg, anchorX, anchorY, pillHeightPx, durationMs)
    }

    private fun showBanner(
        message: String,
        dotColor: Int,
        cfg: RemoteConfig,
        anchorX: Int,
        anchorY: Int,
        pillHeightPx: Int,
        durationMs: Long
    ) {
        if (!Settings.canDrawOverlays(context)) return
        handler.post {
            hideInternal()

            val density = context.resources.displayMetrics.density
            val isDark = when (cfg.themeMode) {
                ThemeMode.DARK -> true
                ThemeMode.LIGHT -> false
                ThemeMode.SYSTEM -> {
                    val night = context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
                    night != Configuration.UI_MODE_NIGHT_NO
                }
            }

            val surfaceColor = if (isDark) Color.parseColor("#2C2C2C") else Color.parseColor("#FFFFFF")
            val borderColor = if (isDark) Color.parseColor("#3D3D3D") else Color.parseColor("#E5E5E5")
            val textColor = if (isDark) Color.WHITE else Color.parseColor("#1A1A1A")

            val container = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                val hPad = (12 * density).roundToInt()
                val vPad = (7 * density).roundToInt()
                setPadding(hPad, vPad, hPad, vPad)
                background = GradientDrawable().apply {
                    shape = GradientDrawable.RECTANGLE
                    cornerRadius = 8f * density
                    setColor(surfaceColor)
                    setStroke((1f * density).roundToInt().coerceAtLeast(1), borderColor)
                }
            }

            val dotSize = (9 * density).roundToInt()
            val dotView = android.view.View(context).apply {
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(dotColor)
                }
            }
            container.addView(dotView, LinearLayout.LayoutParams(dotSize, dotSize).apply {
                marginEnd = (8 * density).roundToInt()
            })

            val label = TextView(context).apply {
                text = message
                setTextColor(textColor)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 12.5f)
                typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            }
            container.addView(label)

            val widthSpec = android.view.View.MeasureSpec.makeMeasureSpec(0, android.view.View.MeasureSpec.UNSPECIFIED)
            val heightSpec = android.view.View.MeasureSpec.makeMeasureSpec(0, android.view.View.MeasureSpec.UNSPECIFIED)
            container.measure(widthSpec, heightSpec)
            val bannerW = container.measuredWidth.coerceAtLeast((110 * density).roundToInt())
            val bannerH = container.measuredHeight.coerceAtLeast((32 * density).roundToInt())

            val bounds = ScreenBoundsCalculator.getSafeBoundsPx(context, windowManager)
            val gap = (8 * density).roundToInt()
            val preferAboveY = anchorY - bannerH - gap
            val rawY = if (preferAboveY >= bounds.top) preferAboveY else (anchorY + pillHeightPx + gap)
            val targetX = anchorX.coerceIn(bounds.left, (bounds.right - bannerW).coerceAtLeast(bounds.left))
            val targetY = rawY.coerceIn(bounds.top, (bounds.bottom - bannerH).coerceAtLeast(bounds.top))

            val params = WindowManager.LayoutParams(
                bannerW,
                bannerH,
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    (if (cfg.hideFromScreenCapture) WindowManager.LayoutParams.FLAG_SECURE else 0),
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.TOP or Gravity.START
                x = targetX
                y = targetY
            }

            runCatching {
                windowManager.addView(container, params)
                bannerView = container
                attached = true
                handler.postDelayed(dismissRunnable, durationMs)
            }
        }
    }

    fun hide() {
        handler.post { hideInternal() }
    }

    private fun hideInternal() {
        handler.removeCallbacks(dismissRunnable)
        if (attached && bannerView != null) {
            runCatching { windowManager.removeViewImmediate(bannerView) }
        }
        bannerView = null
        attached = false
    }
}
