package com.saabithjiffry.presentersync.remote.config

object AppConstants {
    const val APP_VERSION = "5.3.0"

    // Base HUD dimensions & layout ratios (matching GUI_Config.ahk UIConstants)
    const val BASE_WIDTH_TEXT = 168
    const val BASE_WIDTH_ICON = 80
    const val BASE_HEIGHT = 40
    const val MIC_ICON_SIZE = 18
    const val MIC_TEXT_SIZE = 13
    const val CORNER_RADIUS_DEFAULT = 8f
    const val SCREEN_MARGIN_X = 20
    const val SCREEN_MARGIN_Y = 20
    const val SCREEN_MIN_PAD = 10
    const val SNAP_THRESHOLD_DP = 14

    // Animation & timing constants
    const val FADE_STEPS = 10
    const val FADE_SLEEP_MS = 10L
    const val POP_WIDTH_INC_TEXT = 1.5f
    const val POP_WIDTH_INC_ICON = 1.0f
    const val POP_HEIGHT_INC = 0.5f
    const val PULSE_STEP_AGGRESSIVE = 20
    const val PULSE_STEP_NORMAL = 5
    const val PULSE_INTERVAL_AGGRESSIVE_MS = 15L
    const val PULSE_INTERVAL_NORMAL_MS = 40L
    const val PULSE_MIN_RATIO_AGGRESSIVE = 0.2f
    const val PULSE_MIN_RATIO_NORMAL = 0.6f

    const val CLICKER_DEBOUNCE_MS = 150L
    const val PUSH_TO_MUTE_HOLD_MS = 350L
    const val SHORT_TAP_MAX_MS = 400L
    const val SHORT_TAP_MAX_SLOP_DP = 6f
    const val DODGE_ALPHA = 45
    const val AUTO_DODGE_RESTORE_MS = 2200L
    const val TOOLTIP_DURATION_MS = 2000L

    // Opacity presets
    const val OPACITY_SOLID = 255
    const val OPACITY_FROSTED = 220
    const val OPACITY_GHOST = 127

    // Networking defaults
    const val DEFAULT_OBS_PORT = 4455
    const val DEFAULT_BRIDGE_PORT = 4456
    const val DEFAULT_MIC_NAME = "Mic/Aux"
    const val DEFAULT_HEARTBEAT_SECONDS = 30
    const val WS_CONNECT_TIMEOUT_MS = 2500L
    const val RECONNECT_DELAY_MS = 2500L
    const val NTFY_BASE_URL = "https://ntfy.sh"
    const val NTFY_WS_BASE_URL = "wss://ntfy.sh"
    const val GITHUB_RELEASES_API = "https://api.github.com/repos/SaabithJiffry/PresenterSync/releases/latest"
    const val GITHUB_RELEASES_URL = "https://github.com/SaabithJiffry/PresenterSync/releases"
    const val GITHUB_REPO_URL = "https://github.com/SaabithJiffry/PresenterSync/"
    const val MAX_PASS_THROUGH_ALPHA = 0.78f
    const val PILL_MAX_VIEWPORT_WIDTH_FRACTION = 0.86f
}
