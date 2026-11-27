package com.saabithjiffry.presentersync.remote.config

import android.content.Context
import android.content.SharedPreferences
import com.saabithjiffry.presentersync.remote.input.BubbleGestureAction
import com.saabithjiffry.presentersync.remote.input.BubbleGestureConfig
import com.saabithjiffry.presentersync.remote.network.RelayCrypto
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONArray
import org.json.JSONObject

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

data class SavedHostProfile(
    val id: String,
    val name: String,
    val networkMode: NetworkMode = NetworkMode.LAN,
    val hostAddress: String = "127.0.0.1",
    val hostPort: Int = AppConstants.DEFAULT_OBS_PORT,
    val bridgePort: Int = AppConstants.DEFAULT_BRIDGE_PORT,
    val obsPassword: String = "",
    val internetPairingCode: String = "",
    val relayBaseUrl: String = AppConstants.NTFY_BASE_URL,
    val quickNudgePresets: String = "",
    val sessionToken: String = "",
    val sessionPairingCode: String = "",
    val pairedHostUuid: String = "",
    val targetMicName: String = AppConstants.DEFAULT_MIC_NAME,
    val heartbeatSeconds: Int = AppConstants.DEFAULT_HEARTBEAT_SECONDS
)

object SavedHostProfileCodec {
    fun toJsonString(profiles: List<SavedHostProfile>): String {
        val arr = JSONArray()
        for (p in profiles) {
            val obj = JSONObject()
                .put("id", p.id)
                .put("name", p.name)
                .put("networkMode", p.networkMode.label)
                .put("hostAddress", p.hostAddress)
                .put("hostPort", p.hostPort)
                .put("bridgePort", p.bridgePort)
                .put("obsPassword", p.obsPassword)
                .put("internetPairingCode", p.internetPairingCode)
                .put("relayBaseUrl", RelayCrypto.normalizeRelayBaseUrl(p.relayBaseUrl))
                .put("quickNudgePresets", p.quickNudgePresets)
                .put("sessionToken", p.sessionToken)
                .put("sessionPairingCode", p.sessionPairingCode)
                .put("pairedHostUuid", p.pairedHostUuid)
                .put("targetMicName", p.targetMicName)
                .put("heartbeatSeconds", p.heartbeatSeconds)
            arr.put(obj)
        }
        return arr.toString()
    }

    fun fromJsonString(raw: String): List<SavedHostProfile> {
        if (raw.isBlank()) return emptyList()
        return runCatching {
            val arr = JSONArray(raw)
            val list = ArrayList<SavedHostProfile>(arr.length())
            for (i in 0 until arr.length()) {
                val obj = arr.optJSONObject(i) ?: continue
                val id = obj.optString("id", "").trim()
                val name = obj.optString("name", "").trim()
                if (id.isEmpty() || name.isEmpty()) continue
                val hPort = obj.optInt("hostPort", AppConstants.DEFAULT_OBS_PORT)
                    .let { if (it in 1..65535) it else AppConstants.DEFAULT_OBS_PORT }
                val bPort = obj.optInt("bridgePort", AppConstants.DEFAULT_BRIDGE_PORT)
                    .let { if (it in 1..65535) it else AppConstants.DEFAULT_BRIDGE_PORT }
                val hb = obj.optInt("heartbeatSeconds", AppConstants.DEFAULT_HEARTBEAT_SECONDS)
                    .let { if (it in 10..3600) it else AppConstants.DEFAULT_HEARTBEAT_SECONDS }
                list.add(
                    SavedHostProfile(
                        id = id,
                        name = name,
                        networkMode = NetworkMode.fromRaw(obj.optString("networkMode", "LAN")),
                        hostAddress = obj.optString("hostAddress", "127.0.0.1"),
                        hostPort = hPort,
                        bridgePort = bPort,
                        obsPassword = obj.optString("obsPassword", ""),
                        internetPairingCode = obj.optString("internetPairingCode", "").trim(),
                        relayBaseUrl = RelayCrypto.normalizeRelayBaseUrl(obj.optString("relayBaseUrl", AppConstants.NTFY_BASE_URL)),
                        quickNudgePresets = obj.optString("quickNudgePresets", "").trim(),
                        sessionToken = obj.optString("sessionToken", "").trim(),
                        sessionPairingCode = obj.optString("sessionPairingCode", "").trim(),
                        pairedHostUuid = obj.optString("pairedHostUuid", "").trim(),
                        targetMicName = obj.optString("targetMicName", AppConstants.DEFAULT_MIC_NAME)
                            .trim().ifEmpty { AppConstants.DEFAULT_MIC_NAME },
                        heartbeatSeconds = hb
                    )
                )
            }
            list
        }.getOrDefault(emptyList())
    }
}

data class RemoteConfig(
    val networkMode: NetworkMode = NetworkMode.LAN,
    val enableRelayFallback: Boolean = true,
    val internetPairingCode: String = "",
    val relayBaseUrl: String = AppConstants.NTFY_BASE_URL,
    val quickNudgePresets: String = "",
    val enableRelayEncryption: Boolean = true,
    val allowLegacyPlaintextRelay: Boolean = false,
    val sessionPairingCode: String = "",
    val sessionToken: String = "",
    val pairedHostUuid: String = "",
    val hostAddress: String = "127.0.0.1",
    val hostPort: Int = AppConstants.DEFAULT_OBS_PORT,
    val bridgePort: Int = AppConstants.DEFAULT_BRIDGE_PORT,
    val obsPassword: String = "",
    val targetMicName: String = AppConstants.DEFAULT_MIC_NAME,
    val heartbeatSeconds: Int = AppConstants.DEFAULT_HEARTBEAT_SECONDS,

    val hwMuteHotkey: String = "KEYCODE_B",
    val enablePointerMute: Boolean = true,
    val enablePushToMute: Boolean = false,
    val enablePushToTalk: Boolean = false,
    val toggleMuteShortcut: String = "Ctrl+F12",
    val exitShortcut: String = "Alt+Shift+F12",
    val hotkeysSuspended: Boolean = false,

    val showIndicator: Boolean = true,
    val showSceneIndicator: Boolean = false,
    val groupSceneWithMicHud: Boolean = true,
    val themeMode: ThemeMode = ThemeMode.SYSTEM,
    val hudColorPreset: String = "Standard",
    val customLiveHex: String = "#107C10",
    val customMutedHex: String = "#C42B1C",
    val showText: Boolean = false,
    val monoIcon: Boolean = false,
    val sleekCorners: Boolean = false,
    val aggressivePulse: Boolean = false,
    val enableAudioCue: Boolean = false,
    val enableMuteToast: Boolean = false,
    val enableVoiceWhileMutedAlert: Boolean = true,
    val enableHapticAlerts: Boolean = true,
    val hapticIntensity: Float = 0.8f,
    val showPillMiniBadges: Boolean = true,
    val enableBackgroundMediaClicker: Boolean = false,
    val backgroundMediaPrimaryAction: BubbleGestureAction = BubbleGestureAction.TOGGLE_MUTE,
    val enableHudClickActions: Boolean = true,
    val lockHudPosition: Boolean = false,
    val singleTapAction: BubbleGestureAction = BubbleGestureAction.NONE,
    val doubleTapAction: BubbleGestureAction = BubbleGestureAction.OPEN_QUICK_MENU,
    val longPressAction: BubbleGestureAction = BubbleGestureAction.TOGGLE_MUTE,
    val veryLongPressAction: BubbleGestureAction = BubbleGestureAction.NONE,
    val longPressDurationMs: Int = 600,
    val veryLongPressDurationMs: Int = 1400,
    val enableMagneticSnap: Boolean = true,
    val hudClickThrough: Boolean = false,
    val hdmiHdcpRecoveryEnabled: Boolean = false,
    val hudAutoDodge: Boolean = false,
    val hideFromScreenCapture: Boolean = true,
    val confirmBeforeStopRecording: Boolean = true,
    val opacityLevel: Int = AppConstants.OPACITY_FROSTED,
    val indicatorScale: Float = 1.0f,

    val firstRun: Boolean = true,
    val isMuted: Boolean = false,
    val startOnBoot: Boolean = false,
    val autoCheckUpdates: Boolean = true,
    val lastUpdateCheckMs: Long = 0L,
    val skippedUpdateVersion: String = "",
    val customUpdateUrl: String = "",
    val kioskPin: String = "",
    val defaultRole: String = "",
    val directObsFallbackAllowed: Boolean = true,
    val deviceProfileMode: DeviceProfileMode = DeviceProfileMode.AUTO,
    val keepScreenOn: Boolean = false,
    val idleDimAfterSec: Int = 0,
    val savedProfiles: List<SavedHostProfile> = emptyList(),
    val activeProfileId: String = "",
    val savedX: Int = -1,
    val savedY: Int = -1,
    val savedXRatio: Float = -1f,
    val savedYRatio: Float = -1f,
    val sceneSavedX: Int = -1,
    val sceneSavedY: Int = -1,
    val sceneSavedXRatio: Float = -1f,
    val sceneSavedYRatio: Float = -1f,
    val snakeHighScore: Int = 0,
    val arcadeHighScores: Map<String, Int> = emptyMap()
) {
    fun toBubbleGestureConfig(): BubbleGestureConfig = BubbleGestureConfig(
        enabled = enableHudClickActions,
        lockPosition = lockHudPosition,
        singleTapAction = singleTapAction,
        doubleTapAction = doubleTapAction,
        longPressAction = longPressAction,
        veryLongPressAction = veryLongPressAction,
        longPressDurationMs = longPressDurationMs.toLong(),
        veryLongPressDurationMs = veryLongPressDurationMs.toLong()
    )

    fun withNormalizedPttMutualExclusion(prev: RemoteConfig = this): RemoteConfig {
        if (!enablePushToTalk) return this
        val turnedOnPtt = !prev.enablePushToTalk
        val pickedGesture = (longPressAction != BubbleGestureAction.NONE || veryLongPressAction != BubbleGestureAction.NONE)
        val turnedOnPtm = !prev.enablePushToMute && enablePushToMute
        return if (turnedOnPtt || (prev === this)) {
            copy(
                enablePushToMute = false,
                longPressAction = BubbleGestureAction.NONE,
                veryLongPressAction = BubbleGestureAction.NONE
            )
        } else if (pickedGesture || turnedOnPtm) {
            copy(enablePushToTalk = false)
        } else {
            copy(enablePushToMute = false)
        }
    }
}

class RemoteConfigStore private constructor(
    private val prefs: SharedPreferences,
    private val secretVault: SecretVault
) {
    constructor(context: Context) : this(
        prefs = context.applicationContext.getSharedPreferences("presentersync_remote_prefs", Context.MODE_PRIVATE),
        secretVault = SecretVault(
            context.applicationContext,
            context.applicationContext.getSharedPreferences("presentersync_remote_prefs", Context.MODE_PRIVATE)
        )
    )

    internal constructor(
        context: Context,
        cipher: SecretCipher
    ) : this(
        prefs = context.applicationContext.getSharedPreferences("presentersync_remote_prefs", Context.MODE_PRIVATE),
        secretVault = SecretVault(
            vaultPrefs = context.applicationContext.getSharedPreferences(SecretVault.VAULT_PREFS_NAME, Context.MODE_PRIVATE),
            legacyPrefs = context.applicationContext.getSharedPreferences("presentersync_remote_prefs", Context.MODE_PRIVATE),
            cipher = cipher
        )
    )

    val vault: SecretVault
        get() = secretVault

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

        val longMs = prefs.getInt("longPressDurationMs", 600).coerceIn(300, 2000)
        val veryLongMs = prefs.getInt("veryLongPressDurationMs", 1400).coerceIn(longMs + 300, 4000)
        val singleTap = prefs.getString("singleTapAction", null)?.let { BubbleGestureAction.fromRaw(it) }
            ?: BubbleGestureAction.NONE
        val doubleTap = prefs.getString("doubleTapAction", null)?.let { BubbleGestureAction.fromRaw(it) }
            ?: BubbleGestureAction.OPEN_QUICK_MENU
        val longPress = prefs.getString("longPressAction", null)?.let { BubbleGestureAction.fromRaw(it) }
            ?: BubbleGestureAction.TOGGLE_MUTE
        val veryLongPress = prefs.getString("veryLongPressAction", null)?.let { BubbleGestureAction.fromRaw(it) }
            ?: BubbleGestureAction.NONE

        val rawPtm = prefs.getBoolean("enablePushToMute", false)
        val rawPtt = prefs.getBoolean("enablePushToTalk", false)
        return RemoteConfig(
            networkMode = NetworkMode.fromRaw(prefs.getString("networkMode", "LAN")),
            enableRelayFallback = prefs.getBoolean("enableRelayFallback", true),
            internetPairingCode = secretVault.getSecret("internetPairingCode").trim(),
            relayBaseUrl = RelayCrypto.normalizeRelayBaseUrl(prefs.getString("relayBaseUrl", AppConstants.NTFY_BASE_URL)),
            quickNudgePresets = prefs.getString("quickNudgePresets", "").orEmpty().trim(),
            enableRelayEncryption = prefs.getBoolean("enableRelayEncryption", true),
            allowLegacyPlaintextRelay = prefs.getBoolean("allowLegacyPlaintextRelay", false),
            sessionPairingCode = secretVault.getSecret("sessionPairingCode").trim(),
            sessionToken = secretVault.getSecret("sessionToken").trim(),
            pairedHostUuid = prefs.getString("pairedHostUuid", "").orEmpty().trim(),
            hostAddress = prefs.getString("hostAddress", "127.0.0.1").orEmpty(),
            hostPort = validPort,
            bridgePort = validBridgePort,
            obsPassword = secretVault.getSecret("obsPassword"),
            kioskPin = secretVault.getSecret("kioskPin").trim(),
            defaultRole = prefs.getString("defaultRole", "").orEmpty().trim(),
            directObsFallbackAllowed = prefs.getBoolean("directObsFallbackAllowed", true),
            targetMicName = mic,
            heartbeatSeconds = validHb,
            hwMuteHotkey = prefs.getString("hwMuteHotkey", "KEYCODE_B").orEmpty().ifBlank { "KEYCODE_B" },
            enablePointerMute = prefs.getBoolean("enablePointerMute", true),
            enablePushToMute = if (rawPtt) false else rawPtm,
            enablePushToTalk = rawPtt,
            toggleMuteShortcut = prefs.getString("toggleMuteShortcut", "Ctrl+F12").orEmpty().ifBlank { "Ctrl+F12" },
            exitShortcut = prefs.getString("exitShortcut", "Alt+Shift+F12").orEmpty().ifBlank { "Alt+Shift+F12" },
            hotkeysSuspended = prefs.getBoolean("hotkeysSuspended", false),
            showIndicator = prefs.getBoolean("showIndicator", true),
            showSceneIndicator = prefs.getBoolean("showSceneIndicator", false),
            groupSceneWithMicHud = prefs.getBoolean("groupSceneWithMicHud", true),
            themeMode = ThemeMode.fromRaw(prefs.getString("themeMode", "System")),
            hudColorPreset = HudColorPalettes.normalize(prefs.getString("hudColorPreset", "Standard").orEmpty()),
            customLiveHex = HudColorPalettes.normalizeColorHex(prefs.getString("customLiveHex", "#107C10").orEmpty(), "#107C10"),
            customMutedHex = HudColorPalettes.normalizeColorHex(prefs.getString("customMutedHex", "#C42B1C").orEmpty(), "#C42B1C"),
            showText = prefs.getBoolean("showText", false),
            monoIcon = prefs.getBoolean("monoIcon", false),
            sleekCorners = prefs.getBoolean("sleekCorners", false),
            aggressivePulse = prefs.getBoolean("aggressivePulse", false),
            enableAudioCue = prefs.getBoolean("enableAudioCue", false),
            enableMuteToast = prefs.getBoolean("enableMuteToast", false),
            enableVoiceWhileMutedAlert = prefs.getBoolean("enableVoiceWhileMutedAlert", true),
            enableHapticAlerts = prefs.getBoolean("enableHapticAlerts", true),
            hapticIntensity = prefs.getFloat("hapticIntensity", 0.8f).coerceIn(0.2f, 1.0f),
            showPillMiniBadges = prefs.getBoolean("showPillMiniBadges", true),
            enableBackgroundMediaClicker = prefs.getBoolean("enableBackgroundMediaClicker", false),
            backgroundMediaPrimaryAction = prefs.getString("backgroundMediaPrimaryAction", null)
                ?.let { BubbleGestureAction.fromRaw(it) }
                ?.takeIf { it == BubbleGestureAction.TOGGLE_MUTE || it == BubbleGestureAction.TRANSITION_SCENE }
                ?: BubbleGestureAction.TOGGLE_MUTE,
            enableHudClickActions = prefs.getBoolean("enableHudClickActions", true),
            lockHudPosition = prefs.getBoolean("lockHudPosition", false),
            singleTapAction = singleTap,
            doubleTapAction = doubleTap,
            longPressAction = if (rawPtt) BubbleGestureAction.NONE else longPress,
            veryLongPressAction = if (rawPtt) BubbleGestureAction.NONE else veryLongPress,
            longPressDurationMs = longMs,
            veryLongPressDurationMs = veryLongMs,
            enableMagneticSnap = prefs.getBoolean("enableMagneticSnap", true),
            hudClickThrough = prefs.getBoolean("hudClickThrough", false),
            hdmiHdcpRecoveryEnabled = prefs.getBoolean("hdmiHdcpRecoveryEnabled", false),
            hudAutoDodge = prefs.getBoolean("hudAutoDodge", false),
            hideFromScreenCapture = prefs.getBoolean("hideFromScreenCapture", true),
            confirmBeforeStopRecording = prefs.getBoolean("confirmBeforeStopRecording", true),
            opacityLevel = rawOpacity,
            indicatorScale = rawScale,
            firstRun = prefs.getBoolean("firstRun", true),
            isMuted = prefs.getBoolean("isMuted", false),
            startOnBoot = prefs.getBoolean("startOnBoot", false),
            autoCheckUpdates = prefs.getBoolean("autoCheckUpdates", true),
            lastUpdateCheckMs = prefs.getLong("lastUpdateCheckMs", 0L).coerceAtLeast(0L),
            skippedUpdateVersion = prefs.getString("skippedUpdateVersion", "").orEmpty().trim(),
            customUpdateUrl = prefs.getString("customUpdateUrl", "").orEmpty().trim(),
            deviceProfileMode = DeviceProfileMode.fromRaw(prefs.getString("deviceProfileMode", "Auto")),
            keepScreenOn = prefs.getBoolean("keepScreenOn", false),
            idleDimAfterSec = prefs.getInt("idleDimAfterSec", 0).coerceIn(0, 600),
            savedProfiles = SavedHostProfileCodec.fromJsonString(secretVault.getSecret("savedProfilesJson")),
            activeProfileId = prefs.getString("activeProfileId", "").orEmpty().trim(),
            savedX = prefs.getInt("savedX", -1),
            savedY = prefs.getInt("savedY", -1),
            savedXRatio = prefs.getFloat("savedXRatio", -1f).let { if (it in 0f..1f) it else -1f },
            savedYRatio = prefs.getFloat("savedYRatio", -1f).let { if (it in 0f..1f) it else -1f },
            sceneSavedX = prefs.getInt("sceneSavedX", -1),
            sceneSavedY = prefs.getInt("sceneSavedY", -1),
            sceneSavedXRatio = prefs.getFloat("sceneSavedXRatio", -1f).let { if (it in 0f..1f) it else -1f },
            sceneSavedYRatio = prefs.getFloat("sceneSavedYRatio", -1f).let { if (it in 0f..1f) it else -1f },
            snakeHighScore = prefs.getInt("snakeHighScore", 0).coerceAtLeast(0),
            arcadeHighScores = ArcadeHighScoresCodec.fromJsonString(prefs.getString("arcadeHighScoresJson", null))
        )
    }

    @Synchronized
    fun update(transform: (RemoteConfig) -> RemoteConfig): RemoteConfig {
        val prev = _config.value
        val next = transform(prev).withNormalizedPttMutualExclusion(prev)
        saveToPrefs(next)
        _config.value = next
        return next
    }

    fun resetPosition() = update {
        it.copy(savedX = -1, savedY = -1, savedXRatio = -1f, savedYRatio = -1f)
    }

    fun resetScenePosition() = update {
        it.copy(sceneSavedX = -1, sceneSavedY = -1, sceneSavedXRatio = -1f, sceneSavedYRatio = -1f)
    }

    fun updateSnakeHighScore(score: Int): RemoteConfig = updateArcadeHighScore("snake", score)

    fun updateArcadeHighScore(gameId: String, score: Int): RemoteConfig = update { prev ->
        val cleanId = gameId.trim().lowercase()
        if (cleanId.isEmpty() || score <= 0) return@update prev
        val existing = prev.arcadeHighScores[cleanId] ?: 0
        val nextScore = maxOf(existing, score)
        val nextSnake = if (cleanId == "snake") maxOf(prev.snakeHighScore, nextScore) else prev.snakeHighScore
        if (nextScore == existing && nextSnake == prev.snakeHighScore) {
            prev
        } else {
            val nextMap = prev.arcadeHighScores.toMutableMap().apply { put(cleanId, nextScore) }
            prev.copy(snakeHighScore = nextSnake, arcadeHighScores = nextMap)
        }
    }

    fun setHudWasActive(active: Boolean) {
        prefs.edit().putBoolean("hudWasActive", active).apply()
    }

    fun wasHudActive(): Boolean = prefs.getBoolean("hudWasActive", false)

    fun applyFormFactorPreset(targetClass: FormFactorClass) = update { prev ->
        when (targetClass) {
            FormFactorClass.LARGE_BOARD -> prev.copy(
                indicatorScale = 2.0f,
                showText = true,
                sleekCorners = false,
                hudAutoDodge = true,
                enableMagneticSnap = true
            )
            FormFactorClass.TABLET -> prev.copy(
                indicatorScale = 1.5f,
                showText = true,
                sleekCorners = false,
                enableMagneticSnap = true
            )
            FormFactorClass.COMPACT_PHONE -> prev.copy(
                indicatorScale = 1.0f,
                showText = false,
                sleekCorners = true,
                enableMagneticSnap = true
            )
        }
    }

    fun applyGesturePreset(presetId: String) = update { prev ->
        when (presetId) {
            "hold_mute_unmute" -> prev.copy(
                enableHudClickActions = true,
                singleTapAction = BubbleGestureAction.NONE,
                doubleTapAction = BubbleGestureAction.OPEN_QUICK_MENU,
                longPressAction = BubbleGestureAction.MUTE_ONLY,
                veryLongPressAction = BubbleGestureAction.UNMUTE_ONLY,
                longPressDurationMs = 600,
                veryLongPressDurationMs = 1400
            )
            "classic_tap" -> prev.copy(
                enableHudClickActions = true,
                singleTapAction = BubbleGestureAction.TOGGLE_MUTE,
                doubleTapAction = BubbleGestureAction.NONE,
                longPressAction = BubbleGestureAction.OPEN_QUICK_MENU,
                veryLongPressAction = BubbleGestureAction.OPEN_SETTINGS,
                longPressDurationMs = 550,
                veryLongPressDurationMs = 1400
            )
            else -> prev.copy(
                enableHudClickActions = true,
                singleTapAction = BubbleGestureAction.NONE,
                doubleTapAction = BubbleGestureAction.OPEN_QUICK_MENU,
                longPressAction = BubbleGestureAction.TOGGLE_MUTE,
                veryLongPressAction = BubbleGestureAction.NONE,
                longPressDurationMs = 600,
                veryLongPressDurationMs = 1400
            )
        }
    }

    fun resetAppearance() = update {
        it.copy(
            showText = false,
            monoIcon = false,
            sleekCorners = false,
            aggressivePulse = false,
            enableAudioCue = false,
            enableMuteToast = false,
            enableVoiceWhileMutedAlert = true,
            enableHudClickActions = true,
            lockHudPosition = false,
            singleTapAction = BubbleGestureAction.NONE,
            doubleTapAction = BubbleGestureAction.OPEN_QUICK_MENU,
            longPressAction = BubbleGestureAction.TOGGLE_MUTE,
            veryLongPressAction = BubbleGestureAction.NONE,
            longPressDurationMs = 600,
            veryLongPressDurationMs = 1400,
            enableMagneticSnap = true,
            hudClickThrough = false,
            hudAutoDodge = false,
            keepScreenOn = false,
            idleDimAfterSec = 0,
            opacityLevel = AppConstants.OPACITY_FROSTED,
            indicatorScale = 1.0f,
            themeMode = ThemeMode.SYSTEM,
            hudColorPreset = "Standard",
            customLiveHex = "#107C10",
            customMutedHex = "#C42B1C"
        )
    }

    @Synchronized
    fun saveCurrentAsProfile(profileName: String): SavedHostProfile {
        val prev = current
        val fallbackName = prev.hostAddress
            .split(",", ";")
            .firstOrNull { it.isNotBlank() }
            ?.trim()
            ?: "Room ${prev.savedProfiles.size + 1}"
        val cleanName = profileName.trim().ifEmpty { fallbackName }
        val existing = prev.savedProfiles.firstOrNull {
            (prev.activeProfileId.isNotEmpty() && it.id == prev.activeProfileId && it.name.equals(cleanName, ignoreCase = true)) ||
                it.name.equals(cleanName, ignoreCase = true)
        }
        val profileId = existing?.id ?: "prof-${System.currentTimeMillis()}-${java.util.UUID.randomUUID().toString().take(6)}"
        val entry = SavedHostProfile(
            id = profileId,
            name = cleanName,
            networkMode = prev.networkMode,
            hostAddress = prev.hostAddress,
            hostPort = prev.hostPort,
            bridgePort = prev.bridgePort,
            obsPassword = prev.obsPassword,
            internetPairingCode = prev.internetPairingCode,
            relayBaseUrl = RelayCrypto.normalizeRelayBaseUrl(prev.relayBaseUrl),
            quickNudgePresets = prev.quickNudgePresets,
            sessionToken = prev.sessionToken,
            sessionPairingCode = prev.sessionPairingCode,
            pairedHostUuid = prev.pairedHostUuid,
            targetMicName = prev.targetMicName,
            heartbeatSeconds = prev.heartbeatSeconds
        )
        val updatedList = prev.savedProfiles.filterNot { it.id == profileId } + entry
        update {
            it.copy(
                savedProfiles = updatedList,
                activeProfileId = profileId
            )
        }
        return entry
    }

    @Synchronized
    fun switchToProfile(profileId: String): SavedHostProfile? {
        val target = current.savedProfiles.firstOrNull { it.id == profileId } ?: return null
        update {
            it.copy(
                networkMode = target.networkMode,
                hostAddress = target.hostAddress,
                hostPort = target.hostPort,
                bridgePort = target.bridgePort,
                obsPassword = target.obsPassword,
                internetPairingCode = target.internetPairingCode,
                relayBaseUrl = RelayCrypto.normalizeRelayBaseUrl(target.relayBaseUrl),
                quickNudgePresets = target.quickNudgePresets.ifBlank { it.quickNudgePresets },
                sessionToken = target.sessionToken,
                sessionPairingCode = target.sessionPairingCode,
                pairedHostUuid = target.pairedHostUuid,
                targetMicName = target.targetMicName,
                heartbeatSeconds = target.heartbeatSeconds,
                activeProfileId = target.id,
                firstRun = false
            )
        }
        return target
    }

    @Synchronized
    fun deleteSavedProfile(profileId: String) {
        update { prev ->
            prev.copy(
                savedProfiles = prev.savedProfiles.filterNot { it.id == profileId },
                activeProfileId = if (prev.activeProfileId == profileId) "" else prev.activeProfileId
            )
        }
    }

    private fun saveToPrefs(c: RemoteConfig) {
        secretVault.putSecret("internetPairingCode", c.internetPairingCode)
        secretVault.putSecret("sessionPairingCode", c.sessionPairingCode)
        secretVault.putSecret("sessionToken", c.sessionToken)
        secretVault.putSecret("obsPassword", c.obsPassword)
        secretVault.putSecret("kioskPin", c.kioskPin)
        secretVault.putSecret("savedProfilesJson", SavedHostProfileCodec.toJsonString(c.savedProfiles))

        prefs.edit()
            .putString("networkMode", c.networkMode.label)
            .putBoolean("enableRelayFallback", c.enableRelayFallback)
            .putString("relayBaseUrl", RelayCrypto.normalizeRelayBaseUrl(c.relayBaseUrl))
            .putString("quickNudgePresets", c.quickNudgePresets)
            .putBoolean("enableRelayEncryption", c.enableRelayEncryption)
            .putBoolean("allowLegacyPlaintextRelay", c.allowLegacyPlaintextRelay)
            .putString("pairedHostUuid", c.pairedHostUuid)
            .putString("hostAddress", c.hostAddress)
            .putInt("hostPort", c.hostPort)
            .putInt("bridgePort", c.bridgePort)
            .putString("targetMicName", c.targetMicName)
            .putInt("heartbeatSeconds", c.heartbeatSeconds)
            .putString("hwMuteHotkey", c.hwMuteHotkey)
            .putBoolean("enablePointerMute", c.enablePointerMute)
            .putBoolean("enablePushToMute", c.enablePushToMute)
            .putBoolean("enablePushToTalk", c.enablePushToTalk)
            .putString("toggleMuteShortcut", c.toggleMuteShortcut)
            .putString("exitShortcut", c.exitShortcut)
            .putBoolean("hotkeysSuspended", c.hotkeysSuspended)
            .putBoolean("showIndicator", c.showIndicator)
            .putBoolean("showSceneIndicator", c.showSceneIndicator)
            .putBoolean("groupSceneWithMicHud", c.groupSceneWithMicHud)
            .putString("themeMode", c.themeMode.label)
            .putString("hudColorPreset", c.hudColorPreset)
            .putString("customLiveHex", HudColorPalettes.normalizeColorHex(c.customLiveHex, "#107C10"))
            .putString("customMutedHex", HudColorPalettes.normalizeColorHex(c.customMutedHex, "#C42B1C"))
            .putBoolean("showText", c.showText)
            .putBoolean("monoIcon", c.monoIcon)
            .putBoolean("sleekCorners", c.sleekCorners)
            .putBoolean("aggressivePulse", c.aggressivePulse)
            .putBoolean("enableAudioCue", c.enableAudioCue)
            .putBoolean("enableMuteToast", c.enableMuteToast)
            .putBoolean("hideFromScreenCapture", c.hideFromScreenCapture)
            .putBoolean("confirmBeforeStopRecording", c.confirmBeforeStopRecording)
            .putBoolean("enableVoiceWhileMutedAlert", c.enableVoiceWhileMutedAlert)
            .putBoolean("enableHapticAlerts", c.enableHapticAlerts)
            .putFloat("hapticIntensity", c.hapticIntensity.coerceIn(0.2f, 1.0f))
            .putBoolean("showPillMiniBadges", c.showPillMiniBadges)
            .putBoolean("enableBackgroundMediaClicker", c.enableBackgroundMediaClicker)
            .putString(
                "backgroundMediaPrimaryAction",
                if (c.backgroundMediaPrimaryAction == BubbleGestureAction.TRANSITION_SCENE) {
                    BubbleGestureAction.TRANSITION_SCENE.rawValue
                } else {
                    BubbleGestureAction.TOGGLE_MUTE.rawValue
                }
            )
            .putBoolean("enableHudClickActions", c.enableHudClickActions)
            .putBoolean("lockHudPosition", c.lockHudPosition)
            .putString("singleTapAction", c.singleTapAction.rawValue)
            .putString("doubleTapAction", c.doubleTapAction.rawValue)
            .putString("longPressAction", c.longPressAction.rawValue)
            .putString("veryLongPressAction", c.veryLongPressAction.rawValue)
            .putInt("longPressDurationMs", c.longPressDurationMs)
            .putInt("veryLongPressDurationMs", c.veryLongPressDurationMs)
            .putBoolean("enableMagneticSnap", c.enableMagneticSnap)
            .putBoolean("hudClickThrough", c.hudClickThrough)
            .putBoolean("hdmiHdcpRecoveryEnabled", c.hdmiHdcpRecoveryEnabled)
            .putBoolean("hudAutoDodge", c.hudAutoDodge)
            .putInt("opacityLevel", c.opacityLevel)
            .putFloat("indicatorScale", c.indicatorScale)
            .putBoolean("firstRun", c.firstRun)
            .putBoolean("isMuted", c.isMuted)
            .putBoolean("startOnBoot", c.startOnBoot)
            .putBoolean("autoCheckUpdates", c.autoCheckUpdates)
            .putLong("lastUpdateCheckMs", c.lastUpdateCheckMs)
            .putString("skippedUpdateVersion", c.skippedUpdateVersion)
            .putString("customUpdateUrl", c.customUpdateUrl)
            .putString("defaultRole", c.defaultRole.trim())
            .putBoolean("directObsFallbackAllowed", c.directObsFallbackAllowed)
            .putString("deviceProfileMode", c.deviceProfileMode.rawValue)
            .putBoolean("keepScreenOn", c.keepScreenOn)
            .putInt("idleDimAfterSec", c.idleDimAfterSec)
            .putString("activeProfileId", c.activeProfileId)
            .putInt("savedX", c.savedX)
            .putInt("savedY", c.savedY)
            .putFloat("savedXRatio", c.savedXRatio)
            .putFloat("savedYRatio", c.savedYRatio)
            .putInt("sceneSavedX", c.sceneSavedX)
            .putInt("sceneSavedY", c.sceneSavedY)
            .putFloat("sceneSavedXRatio", c.sceneSavedXRatio)
            .putFloat("sceneSavedYRatio", c.sceneSavedYRatio)
            .putInt("snakeHighScore", c.snakeHighScore)
            .putString("arcadeHighScoresJson", ArcadeHighScoresCodec.toJsonString(c.arcadeHighScores))
            .apply()
    }
}

internal object ArcadeHighScoresCodec {
    fun fromJsonString(raw: String?): Map<String, Int> {
        if (raw.isNullOrBlank()) return emptyMap()
        return try {
            val obj = JSONObject(raw)
            val result = linkedMapOf<String, Int>()
            val keys = obj.keys()
            while (keys.hasNext()) {
                val k = keys.next().trim().lowercase()
                if (k.isNotEmpty()) {
                    val v = obj.optInt(k, 0)
                    if (v > 0) result[k] = v
                }
            }
            result
        } catch (_: Exception) {
            emptyMap()
        }
    }

    fun toJsonString(scores: Map<String, Int>): String {
        if (scores.isEmpty()) return "{}"
        val obj = JSONObject()
        for ((k, v) in scores) {
            val clean = k.trim().lowercase()
            if (clean.isNotEmpty() && v > 0) {
                obj.put(clean, v)
            }
        }
        return obj.toString()
    }
}
