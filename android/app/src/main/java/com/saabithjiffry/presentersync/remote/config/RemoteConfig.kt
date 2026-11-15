package com.saabithjiffry.presentersync.remote.config

import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

enum class NetworkMode(val label: String) {
    LAN("LAN"),
    INTERNET("Internet");

    companion object {
        fun fromRaw(raw: String?): NetworkMode {
            return if (raw?.trim()?.lowercase() == "internet") INTERNET else LAN
        }
    }
}

enum class ThemeMode(val label: String) {
    SYSTEM("System"),
    DARK("Dark"),
    LIGHT("Light");

    companion object {
        fun fromRaw(raw: String?): ThemeMode {
            return when (raw?.trim()?.lowercase()) {
                "dark" -> DARK
                "light" -> LIGHT
                else -> SYSTEM
            }
        }
    }
}

data class RemoteConfig(
    val networkMode: NetworkMode = NetworkMode.LAN,
    val enableRelayFallback: Boolean = true,
    val internetPairingCode: String = "",
    val sessionPairingCode: String = "",
    val hostAddress: String = "127.0.0.1",
    val hostPort: Int = AppConstants.DEFAULT_OBS_PORT,
    val bridgePort: Int = AppConstants.DEFAULT_BRIDGE_PORT,
    val obsPassword: String = "",
    val targetMicName: String = AppConstants.DEFAULT_MIC_NAME,
    val heartbeatSeconds: Int = AppConstants.DEFAULT_HEARTBEAT_SECONDS,

    val hwMuteHotkey: String = "KEYCODE_B",
    val enablePointerMute: Boolean = true,
    val enablePushToMute: Boolean = false,
    val toggleMuteShortcut: String = "Ctrl+F12",
    val exitShortcut: String = "Alt+Shift+F12",
    val hotkeysSuspended: Boolean = false,

    val showIndicator: Boolean = true,
    val themeMode: ThemeMode = ThemeMode.SYSTEM,
    val hudColorPreset: String = "Standard",
    val showText: Boolean = false,
    val monoIcon: Boolean = false,
    val sleekCorners: Boolean = false,
    val aggressivePulse: Boolean = false,
    val enableAudioCue: Boolean = false,
    val enableMuteToast: Boolean = false,
    val enableHudClickActions: Boolean = true,
    val enableMagneticSnap: Boolean = true,
    val hudClickThrough: Boolean = false,
    val hudAutoDodge: Boolean = false,
    val opacityLevel: Int = AppConstants.OPACITY_FROSTED,
    val indicatorScale: Float = 1.0f,

    val firstRun: Boolean = true,
    val isMuted: Boolean = false,
    val startOnBoot: Boolean = false,
    val savedX: Int = -1,
    val savedY: Int = -1
)

class RemoteConfigStore(context: Context) {
    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences("presentersync_remote_prefs", Context.MODE_PRIVATE)

    private val _config = MutableStateFlow(loadFromPrefs())
    val config: StateFlow<RemoteConfig> = _config.asStateFlow()

    val current: RemoteConfig
        get() = _config.value

    private fun loadFromPrefs(): RemoteConfig {
        val rawPort = prefs.getInt("hostPort", AppConstants.DEFAULT_OBS_PORT)
        val validPort = if (rawPort in 1..65535) rawPort else AppConstants.DEFAULT_OBS_PORT
        val rawBridgePort = prefs.getInt("bridgePort", AppConstants.DEFAULT_BRIDGE_PORT)
        val validBridgePort = if (rawBridgePort in 1..65535) rawBridgePort else AppConstants.DEFAULT_BRIDGE_PORT
        val rawHb = prefs.getInt("heartbeatSeconds", AppConstants.DEFAULT_HEARTBEAT_SECONDS)
        val validHb = if (rawHb in 10..3600) rawHb else AppConstants.DEFAULT_HEARTBEAT_SECONDS
        val rawOpacity = prefs.getInt("opacityLevel", AppConstants.OPACITY_FROSTED).coerceIn(1, 255)
        val rawScale = prefs.getFloat("indicatorScale", 1.0f).let {
            if (it <= 0f || it > 10f) 1.0f else it
        }
        val mic = prefs.getString("targetMicName", AppConstants.DEFAULT_MIC_NAME)?.trim().orEmpty()
            .ifEmpty { AppConstants.DEFAULT_MIC_NAME }

        return RemoteConfig(
            networkMode = NetworkMode.fromRaw(prefs.getString("networkMode", "LAN")),
            enableRelayFallback = prefs.getBoolean("enableRelayFallback", true),
            internetPairingCode = prefs.getString("internetPairingCode", "").orEmpty().trim(),
            sessionPairingCode = prefs.getString("sessionPairingCode", "").orEmpty().trim(),
            hostAddress = prefs.getString("hostAddress", "127.0.0.1").orEmpty(),
            hostPort = validPort,
            bridgePort = validBridgePort,
            obsPassword = prefs.getString("obsPassword", "").orEmpty(),
            targetMicName = mic,
            heartbeatSeconds = validHb,
            hwMuteHotkey = prefs.getString("hwMuteHotkey", "KEYCODE_B").orEmpty().ifBlank { "KEYCODE_B" },
            enablePointerMute = prefs.getBoolean("enablePointerMute", true),
            enablePushToMute = prefs.getBoolean("enablePushToMute", false),
            toggleMuteShortcut = prefs.getString("toggleMuteShortcut", "Ctrl+F12").orEmpty().ifBlank { "Ctrl+F12" },
            exitShortcut = prefs.getString("exitShortcut", "Alt+Shift+F12").orEmpty().ifBlank { "Alt+Shift+F12" },
            hotkeysSuspended = prefs.getBoolean("hotkeysSuspended", false),
            showIndicator = prefs.getBoolean("showIndicator", true),
            themeMode = ThemeMode.fromRaw(prefs.getString("themeMode", "System")),
            hudColorPreset = HudColorPalettes.normalize(prefs.getString("hudColorPreset", "Standard").orEmpty()),
            showText = prefs.getBoolean("showText", false),
            monoIcon = prefs.getBoolean("monoIcon", false),
            sleekCorners = prefs.getBoolean("sleekCorners", false),
            aggressivePulse = prefs.getBoolean("aggressivePulse", false),
            enableAudioCue = prefs.getBoolean("enableAudioCue", false),
            enableMuteToast = prefs.getBoolean("enableMuteToast", false),
            enableHudClickActions = prefs.getBoolean("enableHudClickActions", true),
            enableMagneticSnap = prefs.getBoolean("enableMagneticSnap", true),
            hudClickThrough = prefs.getBoolean("hudClickThrough", false),
            hudAutoDodge = prefs.getBoolean("hudAutoDodge", false),
            opacityLevel = rawOpacity,
            indicatorScale = rawScale,
            firstRun = prefs.getBoolean("firstRun", true),
            isMuted = prefs.getBoolean("isMuted", false),
            startOnBoot = prefs.getBoolean("startOnBoot", false),
            savedX = prefs.getInt("savedX", -1),
            savedY = prefs.getInt("savedY", -1)
        )
    }

    @Synchronized
    fun update(transform: (RemoteConfig) -> RemoteConfig): RemoteConfig {
        val next = transform(_config.value)
        saveToPrefs(next)
        _config.value = next
        return next
    }

    fun resetPosition() = update { it.copy(savedX = -1, savedY = -1) }

    fun resetAppearance() = update {
        it.copy(
            showText = false,
            monoIcon = false,
            sleekCorners = false,
            aggressivePulse = false,
            enableAudioCue = false,
            enableMuteToast = false,
            enableHudClickActions = true,
            enableMagneticSnap = true,
            hudClickThrough = false,
            hudAutoDodge = false,
            opacityLevel = AppConstants.OPACITY_FROSTED,
            indicatorScale = 1.0f,
            themeMode = ThemeMode.SYSTEM,
            hudColorPreset = "Standard"
        )
    }

    private fun saveToPrefs(c: RemoteConfig) {
        prefs.edit()
            .putString("networkMode", c.networkMode.label)
            .putBoolean("enableRelayFallback", c.enableRelayFallback)
            .putString("internetPairingCode", c.internetPairingCode)
            .putString("sessionPairingCode", c.sessionPairingCode)
            .putString("hostAddress", c.hostAddress)
            .putInt("hostPort", c.hostPort)
            .putInt("bridgePort", c.bridgePort)
            .putString("obsPassword", c.obsPassword)
            .putString("targetMicName", c.targetMicName)
            .putInt("heartbeatSeconds", c.heartbeatSeconds)
            .putString("hwMuteHotkey", c.hwMuteHotkey)
            .putBoolean("enablePointerMute", c.enablePointerMute)
            .putBoolean("enablePushToMute", c.enablePushToMute)
            .putString("toggleMuteShortcut", c.toggleMuteShortcut)
            .putString("exitShortcut", c.exitShortcut)
            .putBoolean("hotkeysSuspended", c.hotkeysSuspended)
            .putBoolean("showIndicator", c.showIndicator)
            .putString("themeMode", c.themeMode.label)
            .putString("hudColorPreset", c.hudColorPreset)
            .putBoolean("showText", c.showText)
            .putBoolean("monoIcon", c.monoIcon)
            .putBoolean("sleekCorners", c.sleekCorners)
            .putBoolean("aggressivePulse", c.aggressivePulse)
            .putBoolean("enableAudioCue", c.enableAudioCue)
            .putBoolean("enableMuteToast", c.enableMuteToast)
            .putBoolean("enableHudClickActions", c.enableHudClickActions)
            .putBoolean("enableMagneticSnap", c.enableMagneticSnap)
            .putBoolean("hudClickThrough", c.hudClickThrough)
            .putBoolean("hudAutoDodge", c.hudAutoDodge)
            .putInt("opacityLevel", c.opacityLevel)
            .putFloat("indicatorScale", c.indicatorScale)
            .putBoolean("firstRun", c.firstRun)
            .putBoolean("isMuted", c.isMuted)
            .putBoolean("startOnBoot", c.startOnBoot)
            .putInt("savedX", c.savedX)
            .putInt("savedY", c.savedY)
            .apply()
    }
}
