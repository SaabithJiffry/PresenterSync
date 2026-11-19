; ==============================================================================
; Script: PresenterSync_Remote
; Description: Standalone companion client for Smart Boards & secondary devices.
;              Provides a single-pill remote mute HUD and transmits clicker
;              mute keystrokes back to OBS Studio over the local network.
; Version: 7.4.0
; Author: Saabith Jiffry
; License: MIT
; ==============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Off
;@Ahk2Exe-SetMainIcon assets\PresenterSyncRemote.ico
;@Ahk2Exe-SetProductName PresenterSync Remote
;@Ahk2Exe-SetDescription PresenterSync Remote - Smart Board Companion Client
;@Ahk2Exe-SetVersion 7.4.0.0
ProcessSetPriority "High"

#Include <WebSocket>
#Include <Crypto>
#Include <RemoteBridgeClient>
#Include <Gdip>
#Include <OBS_Network>
#Include <GUI_Config>
#Include <HudSnakeGame>

g_RemoteCli := ParseRemoteCliArgs(A_Args)
g_RemoteMutex := AcquireRemoteInstanceMutex(g_RemoteCli.instanceName)
if (g_RemoteMutex.alreadyExists) {
    TrayTip("PresenterSync Remote" (g_RemoteCli.instanceName != "" ? " [" g_RemoteCli.instanceName "]" : "") " is already running. Use -Instance <name> to run another remote.", "PresenterSync Remote", 2)
    Sleep(350)
    ExitApp(0)
}

global AppState := ""
DiagnosticLogger.Init("PresenterSync_Remote")

Gdip.Startup()
ProcessSelfUpdateStartupCleanup(A_Args)
RegisterSelfUpdateBeforeRelaunch((*) => ((IsSet(AppState) && IsObject(AppState)) ? ((AppState.HasOwnProp("presenterTickFn") && AppState.presenterTickFn ? SetTimer(AppState.presenterTickFn, 0) : 0), (AppState.HasOwnProp("recTickFn") && AppState.recTickFn ? SetTimer(AppState.recTickFn, 0) : 0)) : 0, HudSnake.Stop(), ReleaseRemoteInstanceMutex(g_RemoteMutex), Theme.Shutdown(), Gdip.Shutdown()))
OnExit((*) => ((IsSet(AppState) && IsObject(AppState)) ? ((AppState.HasOwnProp("presenterTickFn") && AppState.presenterTickFn ? SetTimer(AppState.presenterTickFn, 0) : 0), (AppState.HasOwnProp("recTickFn") && AppState.recTickFn ? SetTimer(AppState.recTickFn, 0) : 0)) : 0, HudSnake.Stop(), ReleaseRemoteInstanceMutex(g_RemoteMutex), Theme.Shutdown(), Gdip.Shutdown()))

if (!A_IsCompiled && FileExist(A_ScriptDir "\assets\PresenterSyncRemote.ico"))
    try TraySetIcon(A_ScriptDir "\assets\PresenterSyncRemote.ico")
A_IconTip := "PresenterSync Remote v" UIConstants.APP_VERSION (g_RemoteCli.instanceName != "" ? " [" g_RemoteCli.instanceName "]" : "")

; === CONFIGURATION & STATE ===
class RemoteConfig {
    ConfigFile := ""
    NetworkMode := "LAN"
    EnableRelayFallback := true
    InternetPairingCode := ""
    HostAddress := "127.0.0.1"
    HostPort := "4455"
    BridgePort := "4456"
    SessionPairingCode := ""
    SessionToken := ""
    PairedHostUuid := ""
    DeviceId := ""
    InstanceName := ""
    ObsPassword := ""
    TargetMicName := "Mic/Aux"
    HeartbeatSeconds := 30

    HwMuteHotkey := "b"
    EnablePointerMute := true
    EnablePushToMute := false
    EnablePushToTalk := false
    PptHotkey := "^F12"
    ExitHotkey := "!+F12"

    ShowIndicator := true
    ThemeMode := "System"
    HudColorPreset := "Standard"
    CustomLiveHex := "107C10"
    CustomMutedHex := "C42B1C"
    ShowText := false
    MonoIcon := false
    SleekCorners := false
    AggressivePulse := false
    EnableAudioCue := false
    EnableMuteToast := false
    EnableVoiceWhileMutedAlert := true
    EnableHudClickActions := true
    EnableMagneticSnap := true
    HudClickThrough := false
    HudAutoDodge := false
    ExcludeFromCapture := true
    ConfirmBeforeStopRecording := true
    OpacityLevel := 220
    IndicatorScale := 1.0
    FirstRun := true
    IsMuted := false
    StartWithWindows := false
    AutoCheckUpdates := true
    LastUpdateCheckEpoch := 0
    SkippedUpdateVersion := ""

    savedX := "Default"
    savedY := "Default"

    __New(filePath := "") {
        global g_RemoteCli
        if (filePath != "")
            this.ConfigFile := filePath
        else if (IsObject(g_RemoteCli) && g_RemoteCli.configPath != "")
            this.ConfigFile := g_RemoteCli.configPath
        else if (IsObject(g_RemoteCli) && g_RemoteCli.instanceName != "")
            this.ConfigFile := A_ScriptDir "\PresenterSync_Remote_" SanitizeInstanceFileSlug(g_RemoteCli.instanceName) ".ini"
        else
            this.ConfigFile := A_ScriptDir "\PresenterSync_Remote.ini"
        this.Load()
    }

    Read(section, key, defaultVal := "") {
        return IniRead(this.ConfigFile, section, key, defaultVal)
    }

    Write(section, key, val) {
        IniWrite(val, this.ConfigFile, section, key)
    }

    ReadBool(section, key, defaultValue := 0) {
        value := IniRead(this.ConfigFile, section, key, defaultValue)
        switch (StrLower(String(value))) {
            case "1", "true", "yes", "on":
                return true
            case "0", "false", "no", "off", "":
                return false
            default:
                try return !!Integer(value)
                catch
                    return !!defaultValue
        }
    }

    ReadInt(section, key, defaultValue := 0) {
        value := IniRead(this.ConfigFile, section, key, defaultValue)
        try return Integer(value)
        catch
            return defaultValue
    }

    ReadFloat(section, key, defaultValue := 1.0) {
        value := IniRead(this.ConfigFile, section, key, defaultValue)
        try return Float(value)
        catch
            return defaultValue
    }

    WriteBool(section, key, value) {
        IniWrite(value ? 1 : 0, this.ConfigFile, section, key)
    }

    Load() {
        global g_RemoteCli
        rawNetMode := StrLower(Trim(this.Read("Connection", "NetworkMode", "LAN")))
        this.NetworkMode := (rawNetMode = "internet") ? "Internet" : "LAN"
        this.EnableRelayFallback := this.ReadBool("Connection", "EnableRelayFallback", 1)
        this.InternetPairingCode := Trim(this.Read("Connection", "InternetPairingCode", ""))
        this.HostAddress := this.Read("Connection", "HostAddress", "127.0.0.1")
        rawPort := Trim(this.Read("Connection", "HostPort", "4455"))
        this.HostPort := (IsInteger(rawPort) && Integer(rawPort) >= 1 && Integer(rawPort) <= 65535) ? String(Integer(rawPort)) : "4455"
        rawBPort := Trim(this.Read("Connection", "BridgePort", "4456"))
        this.BridgePort := (IsInteger(rawBPort) && Integer(rawBPort) >= 1 && Integer(rawBPort) <= 65535) ? String(Integer(rawBPort)) : "4456"
        this.SessionPairingCode := Trim(this.Read("Connection", "SessionPairingCode", ""))
        this.SessionToken := Trim(this.Read("Connection", "SessionToken", ""))
        this.PairedHostUuid := Trim(this.Read("Connection", "PairedHostUuid", ""))
        this.DeviceId := Trim(this.Read("Connection", "DeviceId", ""))
        if (this.DeviceId = "") {
            this.DeviceId := GenerateRemoteDeviceId("win")
            this.Write("Connection", "DeviceId", this.DeviceId)
        }
        cliInst := IsObject(g_RemoteCli) ? Trim(g_RemoteCli.instanceName) : ""
        this.InstanceName := (cliInst != "") ? cliInst : Trim(this.Read("Connection", "InstanceName", ""))
        this.ObsPassword := this.Read("Connection", "ObsPassword", "")
        this.TargetMicName := Trim(this.Read("Connection", "TargetMicName", "Mic/Aux"))
        if (this.TargetMicName = "")
            this.TargetMicName := "Mic/Aux"
        this.HeartbeatSeconds := this.ReadInt("Connection", "HeartbeatSeconds", 30)
        if (this.HeartbeatSeconds < 10 || this.HeartbeatSeconds > 3600)
            this.HeartbeatSeconds := 30

        this.HwMuteHotkey := this.Read("Pointer", "HwMuteHotkey", "b")
        this.EnablePointerMute := this.ReadBool("Pointer", "EnablePointerMute", 1)
        this.EnablePushToMute := this.ReadBool("Pointer", "EnablePushToMute", 0)
        this.EnablePushToTalk := this.ReadBool("Pointer", "EnablePushToTalk", 0)
        if (this.EnablePushToTalk && this.EnablePushToMute) {
            this.EnablePushToMute := false
            this.WriteBool("Pointer", "EnablePushToMute", 0)
        }

        this.PptHotkey := this.Read("Shortcuts", "PptHotkey", "^F12")
        if (this.PptHotkey = "")
            this.PptHotkey := "^F12"
        this.ExitHotkey := this.Read("Shortcuts", "ExitHotkey", "!+F12")
        if (this.ExitHotkey = "")
            this.ExitHotkey := "!+F12"

        this.ShowIndicator := this.ReadBool("Appearance", "ShowIndicator", 1)
        rawTheme := StrLower(Trim(this.Read("Appearance", "ThemeMode", "System")))
        this.ThemeMode := (rawTheme = "dark") ? "Dark" : ((rawTheme = "light") ? "Light" : "System")
        Theme.SetMode(this.ThemeMode)
        this.HudColorPreset := NormalizeHudColorPreset(this.Read("Appearance", "HudColorPreset", "Standard"))
        this.CustomLiveHex := NormalizeColorHex(this.Read("Appearance", "CustomLiveHex", "107C10"), "107C10")
        this.CustomMutedHex := NormalizeColorHex(this.Read("Appearance", "CustomMutedHex", "C42B1C"), "C42B1C")

        this.ShowText := this.ReadBool("Appearance", "ShowText", 0)
        this.MonoIcon := this.ReadBool("Appearance", "MonoIcon", 0)
        this.SleekCorners := this.ReadBool("Appearance", "SleekCorners", 0)
        this.AggressivePulse := this.ReadBool("Appearance", "AggressivePulse", 0)
        this.EnableAudioCue := this.ReadBool("Appearance", "EnableAudioCue", 0)
        this.EnableMuteToast := this.ReadBool("Appearance", "EnableMuteToast", 0)
        this.EnableVoiceWhileMutedAlert := this.ReadBool("Appearance", "EnableVoiceWhileMutedAlert", 1)
        this.EnableHudClickActions := this.ReadBool("Appearance", "EnableHudClickActions", 1)
        this.EnableMagneticSnap := this.ReadBool("Appearance", "EnableMagneticSnap", 1)
        this.HudClickThrough := this.ReadBool("Appearance", "HudClickThrough", 0)
        this.HudAutoDodge := this.ReadBool("Appearance", "HudAutoDodge", 0)
        this.ExcludeFromCapture := this.ReadBool("Appearance", "ExcludeFromCapture", 1)
        this.ConfirmBeforeStopRecording := this.ReadBool("Settings", "ConfirmBeforeStopRecording", 1)
        this.OpacityLevel := this.ReadInt("Appearance", "OpacityLevel", UIConstants.OPACITY_FROSTED)
        if (this.OpacityLevel < 1 || this.OpacityLevel > 255)
            this.OpacityLevel := UIConstants.OPACITY_FROSTED

        this.IndicatorScale := this.ReadFloat("Appearance", "IndicatorScale", 1.0)
        if (this.IndicatorScale <= 0.0 || this.IndicatorScale > 10.0)
            this.IndicatorScale := 1.0

        this.FirstRun := this.ReadBool("Settings", "FirstRun", 1)
        this.IsMuted := this.ReadBool("Settings", "IsMuted", 0)
        this.StartWithWindows := this.ReadBool("Settings", "StartWithWindows", 0)
        this.AutoCheckUpdates := this.ReadBool("Settings", "AutoCheckUpdates", 1)
        lastUpd := Trim(this.Read("Settings", "LastUpdateCheckEpoch", "0"))
        this.LastUpdateCheckEpoch := IsInteger(lastUpd) ? Integer(lastUpd) : 0
        this.SkippedUpdateVersion := Trim(this.Read("Settings", "SkippedUpdateVersion", ""))

        this.savedX := this.Read("Position", "X", "Default")
        this.savedY := this.Read("Position", "Y", "Default")
    }

    ResetPosition() {
        this.savedX := "Default"
        this.savedY := "Default"
        this.Write("Position", "X", "Default")
        this.Write("Position", "Y", "Default")
    }

    ResetAppearance() {
        this.ShowText := false
        this.MonoIcon := false
        this.SleekCorners := false
        this.AggressivePulse := false
        this.EnableAudioCue := false
        this.EnableMuteToast := false
        this.EnableHudClickActions := true
        this.EnableMagneticSnap := true
        this.HudClickThrough := false
        this.HudAutoDodge := false
        this.ExcludeFromCapture := true
        this.OpacityLevel := UIConstants.OPACITY_FROSTED
        this.IndicatorScale := 1.0
        this.ThemeMode := "System"
        this.HudColorPreset := "Standard"
        this.CustomLiveHex := "107C10"
        this.CustomMutedHex := "C42B1C"
        Theme.SetMode("System")

        this.WriteBool("Appearance", "ShowText", false)
        this.WriteBool("Appearance", "MonoIcon", false)
        this.WriteBool("Appearance", "SleekCorners", false)
        this.WriteBool("Appearance", "AggressivePulse", false)
        this.WriteBool("Appearance", "EnableAudioCue", false)
        this.WriteBool("Appearance", "EnableMuteToast", false)
        this.WriteBool("Appearance", "EnableVoiceWhileMutedAlert", true)
        this.WriteBool("Appearance", "EnableHudClickActions", true)
        this.WriteBool("Appearance", "EnableMagneticSnap", true)
        this.WriteBool("Appearance", "HudClickThrough", false)
        this.WriteBool("Appearance", "HudAutoDodge", false)
        this.WriteBool("Appearance", "ExcludeFromCapture", true)
        this.Write("Appearance", "OpacityLevel", this.OpacityLevel)
        this.Write("Appearance", "IndicatorScale", this.IndicatorScale)
        this.Write("Appearance", "ThemeMode", this.ThemeMode)
        this.Write("Appearance", "HudColorPreset", this.HudColorPreset)
        this.Write("Appearance", "CustomLiveHex", this.CustomLiveHex)
        this.Write("Appearance", "CustomMutedHex", this.CustomMutedHex)
    }
}

class RemoteState {
    obsWs := ""
    obsConnected := false
    connStatus := "searching"
    _sawAuthChallenge := false
    activeHost := ""
    candidateIndex := 1
    candidates := []
    usingRelayFallback := false
    usingBridge := false
    usingDirectObsFallback := false

    isMuted := false
    recState := 0
    recSeconds := 0
    stopRecConfirmUntil := 0
    streamDropWarn := false
    voiceWhileMuted := false
    osMicMutedDrift := false
    lowDiskWarnLevel := 0
    lowDiskMb := -1
    deadMicWarn := false
    studioModeActive := false
    activeScene := "Scene"
    previewScene := ""
    previousProgramScene := ""
    scenes := []
    isStandby := false
    standbyScene := "BRB"
    standbySnapshot := ""
    timerState := "stopped"
    timerRemainingSec := 600
    timerPresetSec := 600
    _lastVoiceWarnTick := 0
    presenterTickFn := ""
    recTickFn := ""
    _bridgeHandshakeTimerFn := ""
    baseAlpha := 220
    currentAlpha := 220
    breathDir := -5
    animSeq := 0
    isDraggingHud := false
    isAutoDodged := false

    dragTimerFn := ""
    breathTimerFn := ""
    autoDodgeTimerFn := ""
    reconnectTimerFn := ""
    heartbeatTimerFn := ""
    lanRepromoteTimerFn := ""
    _pongWatchdogTimerFn := ""
    lastRxTick := -1
    rxSeq := 0
    connGen := 0
    _lastWakeReconnectTick := 0
    isSystemSuspending := false
    lanFailoverBudgetMs := 5500
    lanRepromoteIntervalMs := 8000
    discoverPort := 4457
    _lanCycleStartTick := 0
    _didUdpShiftFollow := false
    rebuildTrayFn := ""
    syncTrayStatusFn := ""
    refreshHelpFn := ""
    refreshHudFn := ""
    _lastTrayStatusText := ""
    _trayMenuOpen := false
    _trayMenuCloseUntil := 0
    _pendingTrayRebuild := false
    pointerHotIfFn := ""
    activePointerKey := ""
    activeToggleMuteHk := ""
    activeExitHk := ""
    onRemoteCloseSignal := ""

    MicGui := ""
    IconFont := ""

    baseWidth := 80
    baseHeight := 40
    hudGap := 6
    recHeight := 34
    recW := 40
    chatW := 34
    row3Height := 30
    studioW := 28
    sceneW := 46
    iconSize := 18
    textSize := 13
    savedX := 0
    savedY := 0

    colors := {
        live: UIConstants.COLOR_LIVE,
        muted: UIConstants.COLOR_MUTED,
        borderLive: UIConstants.BORDER_LIVE,
        borderMuted: UIConstants.BORDER_MUTED,
        iconLive: UIConstants.ICON_LIVE,
        iconMuted: UIConstants.ICON_MUTED
    }

    __New(cfg) {
        this.isMuted := cfg.IsMuted
        this.baseAlpha := cfg.OpacityLevel
        this.currentAlpha := cfg.OpacityLevel
        this.breathDir := cfg.AggressivePulse ? -UIConstants.PULSE_STEP_AGGRESSIVE : -UIConstants.PULSE_STEP_NORMAL

        osBuild := Integer(StrSplit(A_OSVersion, ".")[3])
        this.IconFont := (osBuild >= 22000) ? "Segoe Fluent Icons" : "Segoe MDL2 Assets"

        this.breathTimerFn := BreathingAnimation.Bind(cfg, this)
        this.autoDodgeTimerFn := AutoDodgeTick.Bind(cfg, this)
        this.reconnectTimerFn := ConnectToRemoteOBS.Bind(cfg, this)
        this.heartbeatTimerFn := RemoteHeartbeatTick.Bind(cfg, this)
        this.lanRepromoteTimerFn := TryPromoteRemoteWanToLan.Bind(cfg, this)
        this.presenterTickFn := RemoteTimerTick.Bind(cfg, this)
        this.recTickFn := RemoteLocalRecTick.Bind(cfg, this)
        this.pointerHotIfFn := CheckRemotePointerEnable.Bind(cfg)

        this.ComputeDimensions(cfg)
    }

    NotifyTrayStatus() {
        try {
            if (IsObject(this.syncTrayStatusFn))
                this.syncTrayStatusFn.Call()
            else if (IsObject(this.rebuildTrayFn))
                this.rebuildTrayFn.Call()
        }
    }

    ComputeDimensions(cfg) {
        cLive := (IsObject(cfg) && cfg.HasOwnProp("CustomLiveHex")) ? cfg.CustomLiveHex : "107C10"
        cMuted := (IsObject(cfg) && cfg.HasOwnProp("CustomMutedHex")) ? cfg.CustomMutedHex : "C42B1C"
        this.colors := UIConstants.GetColorPalette(cfg.HasOwnProp("HudColorPreset") ? cfg.HudColorPreset : "Standard", cLive, cMuted)
        this.baseWidth := Round((cfg.ShowText ? UIConstants.BASE_WIDTH_TEXT : UIConstants.BASE_WIDTH_ICON) * cfg.IndicatorScale)
        this.baseHeight := Round(UIConstants.BASE_HEIGHT * cfg.IndicatorScale)
        this.iconSize := Max(1, Round(UIConstants.MIC_ICON_SIZE * cfg.IndicatorScale))
        this.textSize := Max(1, Round(UIConstants.MIC_TEXT_SIZE * cfg.IndicatorScale))

        rawX := cfg.savedX
        rawY := cfg.savedY
        if (rawX = "Default" || rawY = "Default" || !IsInteger(rawX) || !IsInteger(rawY)) {
            MonitorGetWorkArea(1, &Left, &Top, &Right, &Bottom)
            this.savedX := Max(Left + UIConstants.SCREEN_MIN_PAD, Right - this.baseWidth - UIConstants.SCREEN_MARGIN_X)
            this.savedY := Max(Top + UIConstants.SCREEN_MIN_PAD, Bottom - this.baseHeight - UIConstants.SCREEN_MARGIN_Y)
        } else {
            sx := Integer(rawX), sy := Integer(rawY)
            vLeft := SysGet(76), vTop := SysGet(77)
            vRight := vLeft + SysGet(78), vBottom := vTop + SysGet(79)
            this.savedX := Max(vLeft, Min(sx, vRight - this.baseWidth))
            this.savedY := Max(vTop, Min(sy, vBottom - this.baseHeight))
        }
    }
}

AppConfig := RemoteConfig()
Theme.Init(AppConfig.ThemeMode)
AppState := RemoteState(AppConfig)
DiagnosticLogger.BindContext(AppConfig, AppState)
AppState.rebuildTrayFn := BuildRemoteTrayMenu.Bind(AppConfig, AppState)
AppState.syncTrayStatusFn := SyncRemoteTrayStatus.Bind(AppConfig, AppState)
AppState.refreshHudFn := RefreshRemoteHudAppearance.Bind(AppConfig, AppState)

; === INITIALIZE HUD & HOTKEYS ===
InitRemoteHUD(AppConfig, AppState)
BuildRemoteTrayMenu(AppConfig, AppState)
RegisterRemotePointerHotkey(AppConfig, AppState)
RegisterRemoteAppHotkeys(AppConfig, AppState)
OnMessage(0x0218, OnRemotePowerBroadcast.Bind(AppConfig, AppState))
try Hotkey("!^+s", (*) => HudSnake.Toggle(AppConfig, AppState), "On")
StartBackgroundUpdateChecker(AppConfig, "PresenterSync_Remote.exe")

; === FIRST-RUN / CONNECTION PROMPT ===
if (g_RemoteCli.pairingUri != "") {
    parsedUri := ParseRemotePairingUri(g_RemoteCli.pairingUri)
    if IsObject(parsedUri) {
        AppConfig.NetworkMode := parsedUri.networkMode
        if (parsedUri.hostAddress != "")
            AppConfig.HostAddress := parsedUri.hostAddress
        AppConfig.HostPort := parsedUri.hostPort
        AppConfig.BridgePort := parsedUri.bridgePort
        if (parsedUri.sessionCode != "")
            AppConfig.SessionPairingCode := parsedUri.sessionCode
        if (parsedUri.obsPassword != "")
            AppConfig.ObsPassword := parsedUri.obsPassword
        if (parsedUri.targetMicName != "")
            AppConfig.TargetMicName := parsedUri.targetMicName
        if (parsedUri.internetPairingCode != "")
            AppConfig.InternetPairingCode := parsedUri.internetPairingCode
        if (parsedUri.HasOwnProp("hostUuid") && parsedUri.hostUuid != "")
            AppConfig.PairedHostUuid := parsedUri.hostUuid
        if (parsedUri.HasOwnProp("hudColorPreset") && parsedUri.hudColorPreset != "") {
            AppConfig.HudColorPreset := NormalizeHudColorPreset(parsedUri.hudColorPreset)
            AppConfig.Write("Appearance", "HudColorPreset", AppConfig.HudColorPreset)
        }
        if (parsedUri.HasOwnProp("customLiveHex") && parsedUri.customLiveHex != "") {
            AppConfig.CustomLiveHex := NormalizeColorHex(parsedUri.customLiveHex, AppConfig.CustomLiveHex)
            AppConfig.Write("Appearance", "CustomLiveHex", AppConfig.CustomLiveHex)
        }
        if (parsedUri.HasOwnProp("customMutedHex") && parsedUri.customMutedHex != "") {
            AppConfig.CustomMutedHex := NormalizeColorHex(parsedUri.customMutedHex, AppConfig.CustomMutedHex)
            AppConfig.Write("Appearance", "CustomMutedHex", AppConfig.CustomMutedHex)
        }
        AppState.ComputeDimensions(AppConfig)
        ApplyMicAppearance(AppConfig, AppState)
        if (AppConfig.SessionPairingCode != "" && AppConfig.NetworkMode = "LAN") {
            pairRes := PairRemoteWithHostBridge(AppConfig.HostAddress, AppConfig.BridgePort, AppConfig.SessionPairingCode, AppConfig.DeviceId, GetRemoteDisplayDeviceName(AppConfig))
            if (pairRes.ok)
                ApplyBridgePairResultToConfig(AppConfig, pairRes)
        }
        AppConfig.FirstRun := false
        SaveRemoteConnectionSettingsToIni(AppConfig)
    }
}

if (AppConfig.FirstRun || (AppConfig.NetworkMode = "Internet" ? (AppConfig.InternetPairingCode = "") : (AppConfig.HostAddress = "" && AppConfig.SessionPairingCode = "" && AppConfig.SessionToken = ""))) {
    ShowRemoteConnectionUI(AppConfig, AppState, true)
} else {
    ; Start network connection
    SetTimer AppState.reconnectTimerFn, -100
}

; --- REMOTE NETWORKING ENGINE ---

GetRemoteEffectiveAlpha(state) {
    if (IsObject(state) && state.HasOwnProp("isAutoDodged") && state.isAutoDodged)
        return Min(state.baseAlpha, UIConstants.DODGE_ALPHA)
    return state.baseAlpha
}

ConnectToRemoteOBS(cfg, state) {
    SetTimer state.reconnectTimerFn, 0
    SetTimer state.heartbeatTimerFn, 0
    CancelRemotePongWatchdog(state)
    CancelRemoteBridgeHandshakeWatchdog(state)
    if (state.HasOwnProp("lanRepromoteTimerFn") && IsObject(state.lanRepromoteTimerFn))
        SetTimer state.lanRepromoteTimerFn, 0

    if (state.obsConnected)
        return

    if ((state.HasOwnProp("_trayMenuOpen") && state._trayMenuOpen) || (state.HasOwnProp("_trayMenuCloseUntil") && A_TickCount < state._trayMenuCloseUntil)) {
        SetTimer state.reconnectTimerFn, -400
        return
    }

    state.connGen += 1
    state.connStatus := "searching"
    state._sawAuthChallenge := false
    state.activeHost := ""
    state.usingBridge := false
    state.usingDirectObsFallback := false

    if IsObject(state.obsWs) {
        oldWs := state.obsWs
        state.obsWs := ""
        oldWs._psClosed := true
        try oldWs.shutdown()
    }

    if (IsRemoteUsingInternetChannel(cfg, state)) {
        pairCode := Trim(cfg.InternetPairingCode)
        if (pairCode = "") {
            state.NotifyTrayStatus()
            return
        }
        topic := GetInternetRelayTopic(pairCode)
        wsUrl := "wss://ntfy.sh/" topic "/ws"
        relayPrefix := (state.HasOwnProp("usingRelayFallback") && state.usingRelayFallback) ? "Relay Bridge (" : "Internet ("
        candidate := {
            host: "ntfy.sh",
            port: "443",
            scheme: "wss",
            path: "/" topic "/ws",
            url: wsUrl,
            raw: relayPrefix pairCode ")"
        }
        try {
            state.obsWs := WebSocket(wsUrl, {
                message: HandleRemoteObsMessage.Bind(cfg, state, candidate),
                close: HandleRemoteObsClose.Bind(cfg, state, candidate)
            }, true, "", 3500)
            state.obsConnected := true
            state.connStatus := "connected"
            state.activeHost := candidate.raw
            MarkRemoteRxActivity(state)
            keepAliveMs := Max(10000, cfg.HeartbeatSeconds * 1000)
            SetTimer state.heartbeatTimerFn, keepAliveMs
            if (state.HasOwnProp("usingRelayFallback") && state.usingRelayFallback
                && state.HasOwnProp("lanRepromoteTimerFn") && IsObject(state.lanRepromoteTimerFn)
                && (Trim(cfg.HostAddress) != "" || (cfg.HasOwnProp("PairedHostUuid") && Trim(cfg.PairedHostUuid) != ""))) {
                repromoteMs := state.HasOwnProp("lanRepromoteIntervalMs") ? Max(1500, Integer(state.lanRepromoteIntervalMs)) : 12000
                SetTimer state.lanRepromoteTimerFn, repromoteMs
            }
            state.currentAlpha := GetRemoteEffectiveAlpha(state)
            if IsObject(state.MicGui)
                ApplyMicAppearance(cfg, state)
            if (state.isMuted && cfg.ShowIndicator) {
                state.breathDir := cfg.AggressivePulse ? -UIConstants.PULSE_STEP_AGGRESSIVE : -UIConstants.PULSE_STEP_NORMAL
                SetTimer state.breathTimerFn, (cfg.AggressivePulse ? UIConstants.PULSE_INTERVAL_AGGRESSIVE : UIConstants.PULSE_INTERVAL_NORMAL)
            }
            authTok := GetInternetRelayAuthToken(pairCode, cfg.ObsPassword)
            mockWs := (state.HasOwnProp("relayMockWs") && IsObject(state.relayMockWs)) ? state.relayMockWs : ""
            PublishInternetRelayPacket(topic, FormatRelayPacket("remote", "sync_req", "0", authTok), "https://ntfy.sh", mockWs)
            state.NotifyTrayStatus()
        } catch {
            state.obsWs := ""
            state.obsConnected := false
            SetTimer state.breathTimerFn, 0
            if (IsObject(state.MicGui)) {
                state.currentAlpha := GetRemoteEffectiveAlpha(state)
                ApplyMicAppearance(cfg, state)
            }
            FailoverToNextCandidate(cfg, state)
        }
        return
    }

    if (!state.HasOwnProp("_lanCycleStartTick") || state._lanCycleStartTick <= 0 || state.candidateIndex <= 1) {
        state._lanCycleStartTick := A_TickCount
        state._didUdpShiftFollow := false
    }
    if (state.candidates.Length == 0 || state.candidateIndex > state.candidates.Length) {
        state.candidates := BuildRemoteLanCandidateQueue(cfg)
        state.candidateIndex := 1
    }
    if (state.candidates.Length == 0) {
        FailoverToNextCandidate(cfg, state)
        return
    }

    candidate := state.candidates[state.candidateIndex]
    if (IsLoopbackHost(candidate.host) && !IsLocalTcpPortListening(candidate.port)) {
        SetTimer state.breathTimerFn, 0
        if (IsObject(state.MicGui)) {
            state.currentAlpha := GetRemoteEffectiveAlpha(state)
            ApplyMicAppearance(cfg, state)
        }
        FailoverToNextCandidate(cfg, state)
        return
    }
    wsUrl := (candidate.HasOwnProp("url") && candidate.url != "") ? candidate.url : ("ws://" candidate.host ":" candidate.port)
    isBridgeCand := candidate.HasOwnProp("isBridge") && candidate.isBridge
    bridgeTimeoutMs := IsSet(RemoteBridgeConstants) ? RemoteBridgeConstants.BRIDGE_CONNECT_TIMEOUT_MS : 1800

    try {
        state.obsWs := WebSocket(wsUrl, {
            message: HandleRemoteObsMessage.Bind(cfg, state, candidate),
            close: HandleRemoteObsClose.Bind(cfg, state, candidate)
        }, true, "", isBridgeCand ? bridgeTimeoutMs : 2000) ; 1,800ms Bridge connect timeout for fast Direct OBS :4455 fallback
        if (isBridgeCand) {
            if (!TrySendWsText(state.obsWs, BuildRemoteBridgeAuthJson(cfg)))
                Throw Error("Failed to send Bridge auth payload")
            StartRemoteBridgeHandshakeWatchdog(cfg, state, candidate, state.connGen, bridgeTimeoutMs)
        }
    } catch {
        CancelRemoteBridgeHandshakeWatchdog(state)
        state.obsWs := ""
        SetTimer state.breathTimerFn, 0
        if (IsObject(state.MicGui)) {
            state.currentAlpha := GetRemoteEffectiveAlpha(state)
            ApplyMicAppearance(cfg, state)
        }
        FailoverToNextCandidate(cfg, state, candidate)
    }
}

ShouldStopLanFailoverForWan(elapsedMs, budgetMs := 5500, canFallbackToRelay := true) {
    return canFallbackToRelay && (elapsedMs >= Max(500, budgetMs))
}

TryPromoteRemoteWanToLan(cfg, state) {
    if (!IsObject(cfg) || !IsObject(state))
        return false
    canPromoteFromRelay := (state.HasOwnProp("usingRelayFallback") && state.usingRelayFallback && cfg.NetworkMode != "Internet")
    canPromoteFromDirectObs := (state.HasOwnProp("usingDirectObsFallback") && state.usingDirectObsFallback && ((cfg.HasOwnProp("SessionPairingCode") && Trim(cfg.SessionPairingCode) != "") || (cfg.HasOwnProp("SessionToken") && Trim(cfg.SessionToken) != "")))
    if (!canPromoteFromRelay && !canPromoteFromDirectObs)
        return false
    if ((state.HasOwnProp("_trayMenuOpen") && state._trayMenuOpen) || (state.HasOwnProp("_trayMenuCloseUntil") && A_TickCount < state._trayMenuCloseUntil))
        return false

    dPort := state.HasOwnProp("discoverPort") ? Integer(state.discoverPort) : 4457
    if (cfg.HasOwnProp("PairedHostUuid") && Trim(cfg.PairedHostUuid) != "") {
        beacons := DiscoverPublicHostsUdp(dPort, 360)
        FollowPairedHostIpShift(cfg, beacons)
    }

    bPort := (cfg.HasOwnProp("BridgePort") && IsInteger(cfg.BridgePort)) ? String(Integer(cfg.BridgePort)) : "4456"
    expectedUuid := cfg.HasOwnProp("PairedHostUuid") ? Trim(cfg.PairedHostUuid) : ""
    for _, ep in ParseCandidateEndpoints(cfg.HostAddress, cfg.HostPort) {
        probe := ProbeHostBridgeHealth(ep.host, bPort, expectedUuid, RemoteBridgeConstants.HEALTH_PROBE_TIMEOUT_MS)
        if (IsObject(probe) && probe.ok) {
            if (state.HasOwnProp("lanRepromoteTimerFn") && IsObject(state.lanRepromoteTimerFn))
                SetTimer state.lanRepromoteTimerFn, 0
            state.usingRelayFallback := false
            state.usingDirectObsFallback := false
            state._lanCycleStartTick := 0
            state.candidates := BuildRemoteLanCandidateQueue(cfg)
            state.candidateIndex := 1
            if IsObject(state.obsWs) {
                oldWs := state.obsWs
                state.obsWs := ""
                oldWs._psClosed := true
                try oldWs.shutdown()
            }
            state.obsConnected := false
            state.NotifyTrayStatus()
            SetTimer state.reconnectTimerFn, -30
            return true
        }
    }
    return false
}

FailoverToNextCandidate(cfg, state, failedCandidate := "") {
    if (IsObject(failedCandidate) && failedCandidate.HasOwnProp("isBridge") && failedCandidate.isBridge) {
        if (IsSet(DiagnosticLogger))
            try DiagnosticLogger.RecordBreadcrumb("Failover", "BridgeToDirectObsFallback", "Bridge " failedCandidate.raw " failed -> seeking Direct OBS :4455")
        ; If a matching Direct OBS :4455 candidate exists for the same host, jump directly to it on live Bridge crash
        if (state.HasOwnProp("candidates") && IsObject(state.candidates)) {
            Loop state.candidates.Length {
                idx := A_Index
                cand := state.candidates[idx]
                if (idx > state.candidateIndex && (!cand.HasOwnProp("isBridge") || !cand.isBridge) && StrLower(cand.host) == StrLower(failedCandidate.host)) {
                    state.candidateIndex := idx
                    SetTimer state.reconnectTimerFn, -30
                    state.NotifyTrayStatus()
                    return
                }
            }
        }
    }
    if (cfg.NetworkMode = "Internet") {
        state.usingRelayFallback := false
        if (state.HasOwnProp("lanRepromoteTimerFn") && IsObject(state.lanRepromoteTimerFn))
            SetTimer state.lanRepromoteTimerFn, 0
        SetTimer state.reconnectTimerFn, -2500
        state.NotifyTrayStatus()
        return
    }
    if (state.HasOwnProp("usingRelayFallback") && state.usingRelayFallback) {
        state.usingRelayFallback := false
        if (state.HasOwnProp("lanRepromoteTimerFn") && IsObject(state.lanRepromoteTimerFn))
            SetTimer state.lanRepromoteTimerFn, 0
        state.candidateIndex := 1
        state._lanCycleStartTick := 0
        SetTimer state.reconnectTimerFn, -2500
        state.NotifyTrayStatus()
        return
    }

    canFallback := ShouldRemoteFallbackToRelay(cfg, state)
    elapsedMs := (state.HasOwnProp("_lanCycleStartTick") && state._lanCycleStartTick > 0) ? (A_TickCount - state._lanCycleStartTick) : 0
    budgetMs := state.HasOwnProp("lanFailoverBudgetMs") ? Integer(state.lanFailoverBudgetMs) : 5500

    if (ShouldStopLanFailoverForWan(elapsedMs, budgetMs, canFallback)) {
        state.candidateIndex := 1
        state._lanCycleStartTick := 0
        state.usingRelayFallback := true
        SetTimer state.reconnectTimerFn, -50
        state.NotifyTrayStatus()
        return
    }

    state.candidateIndex += 1
    if (state.candidateIndex <= state.candidates.Length) {
        ; Probe next candidate immediately
        SetTimer state.reconnectTimerFn, -50
    } else {
        ; If we have a paired HostUuid, perform one fast UDP PS_DISCOVER_V1 scan before falling back to WAN
        if (cfg.HasOwnProp("PairedHostUuid") && Trim(cfg.PairedHostUuid) != ""
            && (!state.HasOwnProp("_didUdpShiftFollow") || !state._didUdpShiftFollow)) {
            state._didUdpShiftFollow := true
            dPort := state.HasOwnProp("discoverPort") ? Integer(state.discoverPort) : 4457
            beacons := DiscoverPublicHostsUdp(dPort, 360)
            shiftRes := FollowPairedHostIpShift(cfg, beacons)
            if (IsObject(shiftRes) && shiftRes.shifted) {
                state.candidates := BuildRemoteLanCandidateQueue(cfg)
                state.candidateIndex := 1
                SetTimer state.reconnectTimerFn, -30
                state.NotifyTrayStatus()
                return
            }
        }
        ; All LAN candidates exhausted: seamlessly bridge via Internet Relay if configured (e.g., Mode 2 Host without OBS)
        state.candidateIndex := 1
        state._lanCycleStartTick := 0
        if (canFallback) {
            state.usingRelayFallback := true
            SetTimer state.reconnectTimerFn, -100
        } else {
            SetTimer state.reconnectTimerFn, -2500
        }
    }
    state.NotifyTrayStatus()
}

HandleRemoteObsClose(cfg, state, candidate, ws, status, reason) {
    if (IsObject(ws) && ws.HasOwnProp("_psClosed") && ws._psClosed)
        return
    if IsObject(ws)
        try ws.shutdown()
    if (IsObject(ws) && IsObject(state.obsWs) && state.obsWs != ws)
        return
    if (state.obsWs == ws)
        state.obsWs := ""

    CancelRemotePongWatchdog(state)
    CancelRemoteBridgeHandshakeWatchdog(state)
    state.connGen += 1
    wasConnected := state.obsConnected
    state.obsConnected := false
    state.usingBridge := false
    state.usingDirectObsFallback := false
    state.activeHost := ""
    state.recState := 0
    state.recSeconds := 0
    state.streamDropWarn := false
    state.voiceWhileMuted := false
    state.isStandby := false
    state.timerState := "stopped"
    state.scenes := []
    if (state.HasOwnProp("presenterTickFn") && IsObject(state.presenterTickFn))
        SetTimer state.presenterTickFn, 0
    if (state.HasOwnProp("recTickFn") && IsObject(state.recTickFn))
        SetTimer state.recTickFn, 0
    SetTimer state.heartbeatTimerFn, 0
    if (state.HasOwnProp("lanRepromoteTimerFn") && IsObject(state.lanRepromoteTimerFn))
        SetTimer state.lanRepromoteTimerFn, 0
    SetTimer state.breathTimerFn, 0
    state.animSeq += 1

    ; Visual feedback on HUD: Dim while disconnected
    if (!wasConnected && status == 4009) {
        isMissingPw := (cfg.ObsPassword = "" && (!state.HasOwnProp("_sawAuthChallenge") || state._sawAuthChallenge))
        state._sawAuthChallenge := false
        state.connStatus := isMissingPw ? "pw_required" : "auth_failed"
        if (IsObject(state.MicGui)) {
            state.currentAlpha := GetRemoteEffectiveAlpha(state)
            ApplyMicAppearance(cfg, state)
        }
        SetTimer state.reconnectTimerFn, 0
        state.NotifyTrayStatus()
        TrayTip(isMissingPw ? "OBS WebSocket requires a password. Enter it in Change OBS Connection." : "OBS WebSocket authentication failed. Check password in Change OBS Connection.", "PresenterSync Remote", 3)
        return
    }

    state._sawAuthChallenge := false
    state.connStatus := "searching"
    if (IsObject(state.MicGui)) {
        state.currentAlpha := GetRemoteEffectiveAlpha(state)
        ApplyMicAppearance(cfg, state)
    }
    state.NotifyTrayStatus()

    FailoverToNextCandidate(cfg, state, candidate)
}

HandleRemoteObsMessage(cfg, state, candidate, ws, rawMsg) {
    if (IsObject(ws) && ws.HasOwnProp("_psClosed") && ws._psClosed)
        return
    if (IsObject(ws) && IsObject(state.obsWs) && ws != state.obsWs)
        return
    MarkRemoteRxActivity(state)
    CancelRemotePongWatchdog(state)
    msg := (Type(rawMsg) == "Buffer") ? StrGet(rawMsg, "UTF-8") : String(rawMsg)

    if (IsObject(candidate) && candidate.HasOwnProp("isBridge") && candidate.isBridge) {
        ev := ParseHostBridgeWsEvent(msg)
        if (!IsObject(ev))
            return
        if (ev.kind = "auth_ok") {
            SetTimer state.reconnectTimerFn, 0
            CancelRemoteBridgeHandshakeWatchdog(state)
            state._lanCycleStartTick := 0
            if (ev.HasOwnProp("hostUuid") && ev.hostUuid != "" && (!cfg.HasOwnProp("PairedHostUuid") || cfg.PairedHostUuid != ev.hostUuid)) {
                cfg.PairedHostUuid := ev.hostUuid
                try cfg.Write("Connection", "PairedHostUuid", ev.hostUuid)
            }
            if (ev.HasOwnProp("sessionToken") && ev.sessionToken != "" && cfg.SessionToken != ev.sessionToken) {
                cfg.SessionToken := ev.sessionToken
                try cfg.Write("Connection", "SessionToken", ev.sessionToken)
            }
            state.obsConnected := true
            state.usingBridge := true
            state.usingDirectObsFallback := false
            state._sawAuthChallenge := false
            state.connStatus := "connected"
            state.activeHost := candidate.raw
            keepAliveMs := Max(10000, cfg.HeartbeatSeconds * 1000)
            SetTimer state.heartbeatTimerFn, keepAliveMs
            state.currentAlpha := GetRemoteEffectiveAlpha(state)
            if (ev.hasMuted) {
                state.isMuted := ev.isMuted
                cfg.IsMuted := ev.isMuted
                cfg.WriteBool("Settings", "IsMuted", ev.isMuted)
            }
            if IsObject(state.MicGui)
                ApplyMicAppearance(cfg, state)
            if (state.isMuted && cfg.ShowIndicator) {
                state.breathDir := cfg.AggressivePulse ? -UIConstants.PULSE_STEP_AGGRESSIVE : -UIConstants.PULSE_STEP_NORMAL
                SetTimer state.breathTimerFn, (cfg.AggressivePulse ? UIConstants.PULSE_INTERVAL_AGGRESSIVE : UIConstants.PULSE_INTERVAL_NORMAL)
            } else {
                SetTimer state.breathTimerFn, 0
            }
            state.NotifyTrayStatus()
        } else if (ev.kind = "auth_error") {
            CancelRemoteBridgeHandshakeWatchdog(state)
            reasonLow := StrLower(ev.reason)
            isExplicitRevoke := (InStr(reasonLow, "unpaired") || InStr(reasonLow, "revoked"))
            if (!isExplicitRevoke && cfg.SessionToken != "" && cfg.SessionPairingCode != "") {
                cfg.SessionToken := ""
                try cfg.Write("Connection", "SessionToken", "")
                if (IsSet(DiagnosticLogger))
                    try DiagnosticLogger.RecordBreadcrumb("Remote", "BridgeStaleTokenFallback", "Retrying auth with saved SessionPairingCode")
                state._sawAuthChallenge := false
                state.obsConnected := false
                state.usingBridge := false
                SetTimer state.heartbeatTimerFn, 0
                if IsObject(ws) {
                    ws._psClosed := true
                    SafeCloseWebSocketDeferred(ws)
                }
                if (state.obsWs == ws)
                    state.obsWs := ""
                SetTimer state.reconnectTimerFn, -100
                return
            }
            isMissingPw := (cfg.ObsPassword = "" && InStr(reasonLow, "password"))
            state.connStatus := isMissingPw ? "pw_required" : "auth_failed"
            state._sawAuthChallenge := false
            state.obsConnected := false
            state.usingBridge := false
            SetTimer state.reconnectTimerFn, 0
            SetTimer state.heartbeatTimerFn, 0
            SetTimer state.breathTimerFn, 0
            if IsObject(ws) {
                ws._psClosed := true
                SafeCloseWebSocketDeferred(ws)
            }
            if (state.obsWs == ws)
                state.obsWs := ""
            if (IsObject(state.MicGui)) {
                state.currentAlpha := GetRemoteEffectiveAlpha(state)
                ApplyMicAppearance(cfg, state)
            }
            state.NotifyTrayStatus()
            TrayTip("Host Bridge authentication failed (" (ev.reason != "" ? ev.reason : "Invalid code/token") "). Re-pair in Change OBS Connection.", "PresenterSync Remote", 3)
        } else if (ev.kind = "mute_state" || ev.kind = "sync_resync") {
            CancelRemoteBridgeHandshakeWatchdog(state)
            if (ev.HasOwnProp("hostUuid") && ev.hostUuid != "" && (!cfg.HasOwnProp("PairedHostUuid") || cfg.PairedHostUuid != ev.hostUuid)) {
                cfg.PairedHostUuid := ev.hostUuid
                try cfg.Write("Connection", "PairedHostUuid", ev.hostUuid)
            }
            if (!state.obsConnected || state.connStatus != "connected") {
                state.obsConnected := true
                state.usingBridge := true
                state.usingDirectObsFallback := false
                state.connStatus := "connected"
                state.activeHost := candidate.raw
                state.currentAlpha := GetRemoteEffectiveAlpha(state)
                if IsObject(state.MicGui)
                    ApplyMicAppearance(cfg, state)
                state.NotifyTrayStatus()
            }
            SyncRemoteMuteState(cfg, state, ev.isMuted)
            SyncRemoteBridgeTelemetry(cfg, state, ev)
        } else if (ev.kind = "stage_nudge") {
            if (!state.HasOwnProp("suppressNudgeBanners") || !state.suppressNudgeBanners)
                ShowStageNudgeBanner(ev.message, (ev.accentHex != "" ? ev.accentHex : "F59E0B"), 4500, ev.sender)
        } else if (ev.kind = "close_remote") {
            if (state.HasOwnProp("onRemoteCloseSignal") && IsObject(state.onRemoteCloseSignal))
                state.onRemoteCloseSignal.Call()
            else
                ExitApp()
        }
        return
    }

    pkt := ParseRelayPacket(msg)
    if IsObject(pkt) {
        if (pkt.src != "host")
            return
        expectedTok := GetInternetRelayAuthToken(cfg.InternetPairingCode, cfg.ObsPassword)
        if (pkt.cmd = "auth_error" || pkt.auth != expectedTok) {
            state.connStatus := "auth_failed"
            state.obsConnected := false
            SetTimer state.reconnectTimerFn, 0
            SetTimer state.heartbeatTimerFn, 0
            SetTimer state.breathTimerFn, 0
            if IsObject(ws)
                SafeCloseWebSocketDeferred(ws)
            if (state.obsWs == ws)
                state.obsWs := ""
            if (IsObject(state.MicGui)) {
                state.currentAlpha := GetRemoteEffectiveAlpha(state)
                ApplyMicAppearance(cfg, state)
            }
            state.NotifyTrayStatus()
            TrayTip("Internet Relay authentication failed. Check password in Change OBS Connection.", "PresenterSync Remote", 3)
            return
        }
        if (pkt.cmd = "state") {
            if (!state.obsConnected || state.connStatus != "connected") {
                state.obsConnected := true
                state.connStatus := "connected"
                state.activeHost := candidate.raw
                state.currentAlpha := GetRemoteEffectiveAlpha(state)
                if IsObject(state.MicGui)
                    ApplyMicAppearance(cfg, state)
                state.NotifyTrayStatus()
            }
            SyncRemoteMuteState(cfg, state, (pkt.data = "1" || pkt.data = "true"))
        } else if (pkt.cmd = "dir_state") {
            dParts := StrSplit(pkt.data, ";")
            if (dParts.Length >= 5) {
                SyncRemoteBridgeTelemetry(cfg, state, {
                    recState: IsInteger(dParts[2]) ? Integer(dParts[2]) : state.recState,
                    recSeconds: state.recSeconds,
                    streamDropWarn: state.streamDropWarn,
                    voiceWhileMuted: state.voiceWhileMuted,
                    osMicMutedDrift: state.osMicMutedDrift,
                    lowDiskWarnLevel: state.lowDiskWarnLevel,
                    lowDiskMb: state.lowDiskMb,
                    deadMicWarn: state.deadMicWarn,
                    isStandby: (dParts[1] = "1" || dParts[1] = "true"),
                    timerState: dParts[3],
                    timerRemainingSec: IsInteger(dParts[4]) ? Integer(dParts[4]) : state.timerRemainingSec,
                    timerPresetSec: IsInteger(dParts[5]) ? Integer(dParts[5]) : state.timerPresetSec,
                    activeScene: (dParts.Length >= 6 && dParts[6] != "") ? dParts[6] : state.activeScene
                })
            }
        } else if (pkt.cmd = "nudge") {
            nSep := InStr(pkt.data, ";")
            nSender := nSep > 0 ? SubStr(pkt.data, 1, nSep - 1) : "Host"
            nMsg := nSep > 0 ? SubStr(pkt.data, nSep + 1) : pkt.data
            if (!state.HasOwnProp("suppressNudgeBanners") || !state.suppressNudgeBanners)
                ShowStageNudgeBanner(nMsg, "F59E0B", 4500, nSender)
        } else if (pkt.cmd = "close_remote") {
            if (state.HasOwnProp("onRemoteCloseSignal") && IsObject(state.onRemoteCloseSignal))
                state.onRemoteCloseSignal.Call()
            else
                ExitApp()
        }
        return
    }
    if (IsRemoteUsingInternetChannel(cfg, state)) {
        if RegExMatch(msg, '"event"\s*:\s*"open"') {
            topic := GetInternetRelayTopic(cfg.InternetPairingCode)
            authTok := GetInternetRelayAuthToken(cfg.InternetPairingCode, cfg.ObsPassword)
            mockWs := (state.HasOwnProp("relayMockWs") && IsObject(state.relayMockWs)) ? state.relayMockWs : ""
            PublishInternetRelayPacket(topic, FormatRelayPacket("remote", "sync_req", "0", authTok), "https://ntfy.sh", mockWs)
        }
        return
    }

    if (!RegExMatch(msg, '"op"\s*:\s*(\d+)', &matchOp))
        return
    opCode := Integer(matchOp[1])

    if (opCode == 0) {
        ; Op 0: Hello - Handle SHA256 base64 auth challenge if required
        authString := ""
        if (RegExMatch(msg, '"salt"\s*:\s*"([^"]+)"', &matchSalt) && RegExMatch(msg, '"challenge"\s*:\s*"([^"]+)"', &matchChallenge)) {
            state._sawAuthChallenge := true
            salt := matchSalt[1]
            challenge := matchChallenge[1]

            secret := HashSHA256_Base64(cfg.ObsPassword . salt)
            authResponse := HashSHA256_Base64(secret . challenge)
            authString := ',"authentication":"' authResponse '"'
        } else {
            state._sawAuthChallenge := false
        }

        ; Identify for standard events (excluding 20Hz volume meters)
        identifyJson := '{"op":1,"d":{"rpcVersion":1,"eventSubscriptions":2047' authString '}}'
        TrySendWsText(ws, identifyJson)
    }
    else if (opCode == 2) {
        ; Op 2: Identified - Direct OBS :4455 Connection and Auth Succeeded!
        SetTimer state.reconnectTimerFn, 0
        CancelRemoteBridgeHandshakeWatchdog(state)
        state.obsConnected := true
        state.usingBridge := false
        state.usingRelayFallback := false
        state.usingDirectObsFallback := true
        state._sawAuthChallenge := false
        state.connStatus := "connected"
        state.activeHost := candidate.raw
        if (IsSet(DiagnosticLogger))
            try DiagnosticLogger.RecordBreadcrumb("Failover", "DirectObsFallbackConnected", "host=" candidate.raw)

        ; Start keep-alive heartbeat timer (prevents Wi-Fi radio sleep / router conntrack drops)
        keepAliveMs := Max(10000, cfg.HeartbeatSeconds * 1000)
        SetTimer state.heartbeatTimerFn, keepAliveMs

        ; If Bridge pairing is configured, periodically probe Primary Host Bridge :4456 to auto-repromote when PresenterSync.exe restarts
        if (((cfg.HasOwnProp("SessionPairingCode") && Trim(cfg.SessionPairingCode) != "") || (cfg.HasOwnProp("SessionToken") && Trim(cfg.SessionToken) != ""))
            && state.HasOwnProp("lanRepromoteTimerFn") && IsObject(state.lanRepromoteTimerFn)) {
            repromoteMs := state.HasOwnProp("lanRepromoteIntervalMs") ? Max(1500, Integer(state.lanRepromoteIntervalMs)) : 12000
            SetTimer state.lanRepromoteTimerFn, repromoteMs
        }

        ; Restore base alpha & query initial mic mute + full Director state directly from OBS :4455
        state.currentAlpha := GetRemoteEffectiveAlpha(state)
        if IsObject(state.MicGui)
            ApplyMicAppearance(cfg, state)
        escMic := EscapeJsonStr(cfg.TargetMicName)
        SendObsRequest(ws, "GetInputMute", "InitRemoteMute", '{"inputName":"' escMic '"}')
        SendObsRequest(ws, "GetRecordStatus", "InitRemoteRec")
        SendObsRequest(ws, "GetStreamStatus", "InitRemoteStream")
        SendObsRequest(ws, "GetStudioModeEnabled", "InitRemoteStudio")
        SendObsRequest(ws, "GetCurrentProgramScene", "InitRemoteScene")
        SendObsRequest(ws, "GetCurrentPreviewScene", "InitRemotePreviewScene")
        SendObsRequest(ws, "GetSceneList", "InitRemoteSceneList")

        state.NotifyTrayStatus()
    }
    else if (opCode == 5) {
        ; Op 5: Event payload from Direct OBS :4455
        if (RegExMatch(msg, '"eventType"\s*:\s*"InputMuteStateChanged"')) {
            if (RegExMatch(msg, '"inputName"\s*:\s*"((?:[^"\\]|\\.)*)"', &matchInput) && UnescapeJsonStr(matchInput[1]) == cfg.TargetMicName) {
                if (RegExMatch(msg, '"inputMuted"\s*:\s*(true|false)', &matchMuted)) {
                    if (state.connStatus = "mic_error") {
                        state.connStatus := "connected"
                        state.NotifyTrayStatus()
                    }
                    isMutedNow := (matchMuted[1] == "true")
                    SyncRemoteMuteState(cfg, state, isMutedNow)
                }
            }
        } else if (InStr(msg, '"eventType":"RecordStateChanged"') || InStr(msg, '"eventType": "RecordStateChanged"')) {
            if (RegExMatch(msg, '"outputState"\s*:\s*"([^"]+)"', &mRecOut)) {
                outSt := mRecOut[1]
                if (outSt = "OBS_WEBSOCKET_OUTPUT_STARTED" || outSt = "OBS_WEBSOCKET_OUTPUT_RESUMED") {
                    if (state.recState == 0)
                        state.recSeconds := 0
                    state.recState := 1
                } else if (outSt = "OBS_WEBSOCKET_OUTPUT_PAUSED") {
                    state.recState := 2
                } else if (outSt = "OBS_WEBSOCKET_OUTPUT_STOPPED") {
                    state.recState := 0
                    state.recSeconds := 0
                }
                UpdateRemoteLocalRecTimer(state)
                state.NotifyTrayStatus()
            }
        } else if (InStr(msg, '"eventType":"StreamStateChanged"') || InStr(msg, '"eventType": "StreamStateChanged"')) {
            state.streamDropWarn := (InStr(msg, "OBS_WEBSOCKET_OUTPUT_RECONNECTING") != 0)
            state.NotifyTrayStatus()
        } else if (InStr(msg, '"eventType":"StudioModeStateChanged"') || InStr(msg, '"eventType": "StudioModeStateChanged"')) {
            if (RegExMatch(msg, '"studioModeEnabled"\s*:\s*(true|false)', &mStudio)) {
                state.studioModeActive := (mStudio[1] == "true")
                if (state.studioModeActive && IsObject(ws))
                    SendObsRequest(ws, "GetCurrentPreviewScene", "InitRemotePreviewScene")
            }
        } else if (InStr(msg, '"eventType":"CurrentProgramSceneChanged"') || InStr(msg, '"eventType": "CurrentProgramSceneChanged"')) {
            if (RegExMatch(msg, '"sceneName"\s*:\s*"((?:[^"\\]|\\.)*)"', &mScene) || RegExMatch(msg, '"currentProgramSceneName"\s*:\s*"((?:[^"\\]|\\.)*)"', &mScene)) {
                newSc := UnescapeJsonStr(mScene[1])
                if (newSc != "" && state.activeScene != newSc) {
                    if (state.activeScene != "" && state.activeScene != "Scene")
                        state.previousProgramScene := state.activeScene
                    state.activeScene := newSc
                    state.NotifyTrayStatus()
                }
            }
        } else if (InStr(msg, '"eventType":"CurrentPreviewSceneChanged"') || InStr(msg, '"eventType": "CurrentPreviewSceneChanged"')) {
            if (RegExMatch(msg, '"currentPreviewSceneName"\s*:\s*"((?:[^"\\]|\\.)*)"', &mPrev) || RegExMatch(msg, '"sceneName"\s*:\s*"((?:[^"\\]|\\.)*)"', &mPrev)) {
                state.previewScene := UnescapeJsonStr(mPrev[1])
            }
        } else if (InStr(msg, '"eventType":"SceneListChanged"') || InStr(msg, '"eventType": "SceneListChanged"')) {
            parsedScenes := ParseObsSceneList(msg)
            if (parsedScenes.Length > 0) {
                state.scenes := parsedScenes
                if (IsObject(state.rebuildTrayFn))
                    try state.rebuildTrayFn.Call()
            } else if (IsObject(ws)) {
                SendObsRequest(ws, "GetSceneList", "InitRemoteSceneList")
            }
        } else if (RegExMatch(msg, '"eventType"\s*:\s*"CustomEvent"')) {
            if (RegExMatch(msg, '"(?:command|presenterSyncAction)"\s*:\s*"CloseRemote"')) {
                if (state.HasOwnProp("onRemoteCloseSignal") && IsObject(state.onRemoteCloseSignal))
                    state.onRemoteCloseSignal.Call()
                else
                    ExitApp()
            }
        }
    }
    else if (opCode == 7) {
        ; Op 7: Request Response from Direct OBS :4455
        if (InStr(msg, '"requestId":"InitRemoteMute"') || InStr(msg, '"requestId": "InitRemoteMute"')) {
            if (RegExMatch(msg, '"result"\s*:\s*false')) {
                state.connStatus := "mic_error"
                SetTimer state.breathTimerFn, 0
                state.currentAlpha := GetRemoteEffectiveAlpha(state)
                ApplyMicAppearance(cfg, state)
                state.NotifyTrayStatus()
                TrayTip("Audio source '" cfg.TargetMicName "' was not found in OBS Studio.", "PresenterSync Remote", 2)
            } else if (RegExMatch(msg, '"inputMuted"\s*:\s*(true|false)', &matchMuted)) {
                state.connStatus := "connected"
                isMutedNow := (matchMuted[1] == "true")
                state.isMuted := isMutedNow
                cfg.IsMuted := isMutedNow
                cfg.WriteBool("Settings", "IsMuted", isMutedNow)
                state.currentAlpha := GetRemoteEffectiveAlpha(state)
                ApplyMicAppearance(cfg, state)
                if (state.isMuted && cfg.ShowIndicator) {
                    state.breathDir := cfg.AggressivePulse ? -UIConstants.PULSE_STEP_AGGRESSIVE : -UIConstants.PULSE_STEP_NORMAL
                    SetTimer state.breathTimerFn, (cfg.AggressivePulse ? UIConstants.PULSE_INTERVAL_AGGRESSIVE : UIConstants.PULSE_INTERVAL_NORMAL)
                } else {
                    SetTimer state.breathTimerFn, 0
                }
                state.NotifyTrayStatus()
            }
        }
        else if (InStr(msg, '"requestId":"RemoteClickerMute"') || InStr(msg, '"requestId": "RemoteClickerMute"')
            || InStr(msg, '"requestId":"RemoteClickerSetMute"') || InStr(msg, '"requestId": "RemoteClickerSetMute"')) {
            if (RegExMatch(msg, '"result"\s*:\s*false')) {
                if (state.connStatus != "mic_error") {
                    state.connStatus := "mic_error"
                    state.NotifyTrayStatus()
                }
                ToolTip "PresenterSync Remote: Audio source '" cfg.TargetMicName "' not found in OBS"
                SetTimer RemoveToolTip, -2500
            } else if (state.connStatus = "mic_error" && RegExMatch(msg, '"result"\s*:\s*true')) {
                state.connStatus := "connected"
                state.NotifyTrayStatus()
            }
        }
        else if (InStr(msg, '"requestId":"InitRemoteRec"') || InStr(msg, '"requestId": "InitRemoteRec"')) {
            if (RegExMatch(msg, '"outputActive"\s*:\s*(true|false)', &mAct)) {
                act := (mAct[1] == "true")
                pau := (RegExMatch(msg, '"outputPaused"\s*:\s*(true|false)', &mPau) && mPau[1] == "true")
                if (RegExMatch(msg, '"outputDuration"\s*:\s*(\d+)', &mDur))
                    state.recSeconds := Max(0, Integer(mDur[1]) // 1000)
                else if (!act)
                    state.recSeconds := 0
                state.recState := act ? (pau ? 2 : 1) : 0
                UpdateRemoteLocalRecTimer(state)
                state.NotifyTrayStatus()
            }
        }
        else if (InStr(msg, '"requestId":"InitRemoteStream"') || InStr(msg, '"requestId": "InitRemoteStream"')) {
            reconn := (RegExMatch(msg, '"outputReconnecting"\s*:\s*(true|false)', &mRecn) && mRecn[1] == "true")
            cong := (RegExMatch(msg, '"outputCongestion"\s*:\s*([0-9.]+)', &mCong)) ? Float(mCong[1]) : 0.0
            state.streamDropWarn := (reconn || cong >= UIConstants.STREAM_CONGESTION_WARN)
            state.NotifyTrayStatus()
        }
        else if (InStr(msg, '"requestId":"InitRemoteStudio"') || InStr(msg, '"requestId": "InitRemoteStudio"')) {
            if (RegExMatch(msg, '"studioModeEnabled"\s*:\s*(true|false)', &mSt)) {
                state.studioModeActive := (mSt[1] == "true")
                if (state.studioModeActive && IsObject(ws))
                    SendObsRequest(ws, "GetCurrentPreviewScene", "InitRemotePreviewScene")
            }
        }
        else if (InStr(msg, '"requestId":"InitRemoteScene"') || InStr(msg, '"requestId": "InitRemoteScene"')) {
            if (RegExMatch(msg, '"currentProgramSceneName"\s*:\s*"((?:[^"\\]|\\.)*)"', &mSc) || RegExMatch(msg, '"sceneName"\s*:\s*"((?:[^"\\]|\\.)*)"', &mSc)) {
                newSc := UnescapeJsonStr(mSc[1])
                if (newSc != "") {
                    if (state.activeScene != "" && state.activeScene != "Scene" && state.activeScene != newSc)
                        state.previousProgramScene := state.activeScene
                    state.activeScene := newSc
                    state.NotifyTrayStatus()
                }
            }
        }
        else if (InStr(msg, '"requestId":"InitRemotePreviewScene"') || InStr(msg, '"requestId": "InitRemotePreviewScene"')) {
            if (RegExMatch(msg, '"currentPreviewSceneName"\s*:\s*"((?:[^"\\]|\\.)*)"', &mPrev) || RegExMatch(msg, '"sceneName"\s*:\s*"((?:[^"\\]|\\.)*)"', &mPrev)) {
                state.previewScene := UnescapeJsonStr(mPrev[1])
            }
        }
        else if (InStr(msg, '"requestId":"InitRemoteSceneList"') || InStr(msg, '"requestId": "InitRemoteSceneList"')) {
            parsedScenes := ParseObsSceneList(msg)
            if (parsedScenes.Length > 0) {
                state.scenes := parsedScenes
                if (IsObject(state.rebuildTrayFn)) {
                    try state.rebuildTrayFn.Call()
                } else {
                    state.NotifyTrayStatus()
                }
            }
        }
    }
}

CancelRemotePongWatchdog(state) {
    if (IsObject(state) && state.HasOwnProp("_pongWatchdogTimerFn") && IsObject(state._pongWatchdogTimerFn)) {
        try SetTimer(state._pongWatchdogTimerFn, 0)
        state._pongWatchdogTimerFn := ""
    }
}

CancelRemoteBridgeHandshakeWatchdog(state) {
    if (IsObject(state) && state.HasOwnProp("_bridgeHandshakeTimerFn") && IsObject(state._bridgeHandshakeTimerFn)) {
        try SetTimer(state._bridgeHandshakeTimerFn, 0)
        state._bridgeHandshakeTimerFn := ""
    }
}

StartRemoteBridgeHandshakeWatchdog(cfg, state, candidate, expectedGen, timeoutMs := 1800) {
    if (!IsObject(state))
        return
    CancelRemoteBridgeHandshakeWatchdog(state)
    state._bridgeHandshakeTimerFn := OnRemoteBridgeHandshakeTimeout.Bind(cfg, state, candidate, expectedGen)
    SetTimer state._bridgeHandshakeTimerFn, -Max(300, Integer(timeoutMs))
}

OnRemoteBridgeHandshakeTimeout(cfg, state, candidate, expectedGen) {
    if (!IsObject(state))
        return
    state._bridgeHandshakeTimerFn := ""
    if (state.connGen != expectedGen || (state.obsConnected && state.usingBridge))
        return
    if (IsSet(DiagnosticLogger))
        try DiagnosticLogger.RecordBreadcrumb("Failover", "BridgeConnectTimeout", "1800ms exceeded on " candidate.raw " -> falling back to Direct OBS :4455")
    if IsObject(state.obsWs) {
        oldWs := state.obsWs
        state.obsWs := ""
        oldWs._psClosed := true
        try oldWs.shutdown()
    }
    state.obsConnected := false
    state.usingBridge := false
    FailoverToNextCandidate(cfg, state, candidate)
}

ForceRemoteReconnectNow(cfg, state, reason := "wake") {
    if (!IsObject(cfg) || !IsObject(state))
        return
    if (IsSet(DiagnosticLogger))
        try DiagnosticLogger.RecordBreadcrumb("Remote", "ForceReconnectNow", "reason=" reason)
    SetTimer state.reconnectTimerFn, 0
    SetTimer state.heartbeatTimerFn, 0
    CancelRemotePongWatchdog(state)
    CancelRemoteBridgeHandshakeWatchdog(state)
    if (state.HasOwnProp("lanRepromoteTimerFn") && IsObject(state.lanRepromoteTimerFn))
        SetTimer state.lanRepromoteTimerFn, 0
    if (state.HasOwnProp("presenterTickFn") && IsObject(state.presenterTickFn))
        SetTimer state.presenterTickFn, 0
    if (state.HasOwnProp("recTickFn") && IsObject(state.recTickFn))
        SetTimer state.recTickFn, 0
    SetTimer state.breathTimerFn, 0
    state.animSeq += 1
    state.connGen += 1
    state._lastWakeReconnectTick := A_TickCount

    if IsObject(state.obsWs) {
        oldWs := state.obsWs
        state.obsWs := ""
        oldWs._psClosed := true
        try oldWs.shutdown()
    }
    state.obsConnected := false
    state.usingBridge := false
    state.usingDirectObsFallback := false
    state.usingRelayFallback := false
    state.activeHost := ""
    state.connStatus := "searching"
    state.candidateIndex := 1
    state._lanCycleStartTick := 0
    if (IsObject(state.MicGui)) {
        state.currentAlpha := GetRemoteEffectiveAlpha(state)
        ApplyMicAppearance(cfg, state)
    }
    state.NotifyTrayStatus()
    SetTimer state.reconnectTimerFn, -30
}

OnRemotePongWatchdogTimeout(cfg, state, expectedGen, pingRxSeq, pingRxTick) {
    if (!IsObject(state))
        return
    state._pongWatchdogTimerFn := ""
    if (!state.obsConnected || state.connGen != expectedGen)
        return
    if (IsPongWatchdogExpired(state, pingRxSeq, pingRxTick)) {
        if (IsSet(DiagnosticLogger))
            try DiagnosticLogger.RecordBreadcrumb("Remote", "PongWatchdogTimeout", "idle=" (A_TickCount - state.lastRxTick) "ms")
        ForceRemoteReconnectNow(cfg, state, "pong_timeout")
    }
}

SendRemotePingWithWatchdog(cfg, state, channelKind := "bridge") {
    if (!state.obsConnected || !IsObject(state.obsWs))
        return false
    expectedGen := state.connGen
    pingRxSeq := state.rxSeq
    pingRxTick := state.lastRxTick
    ok := (channelKind = "bridge")
        ? TrySendWsText(state.obsWs, BuildRemoteBridgePingJson())
        : SendObsRequest(state.obsWs, "GetVersion", "KeepAlive")
    if (!ok) {
        ForceRemoteReconnectNow(cfg, state, "ping_send_failed")
        return false
    }
    CancelRemotePongWatchdog(state)
    state._pongWatchdogTimerFn := OnRemotePongWatchdogTimeout.Bind(cfg, state, expectedGen, pingRxSeq, pingRxTick)
    SetTimer state._pongWatchdogTimerFn, -RemoteBridgeConstants.PONG_TIMEOUT_MS
    return true
}

VerifyOrReconnectRemote(cfg, state, reason := "wake") {
    if (!IsObject(cfg) || !IsObject(state))
        return
    if (state.connStatus = "auth_failed" || state.connStatus = "pw_required")
        return
    if (!state.obsConnected || !IsObject(state.obsWs)) {
        if ((A_TickCount - state._lastWakeReconnectTick) >= 800)
            ForceRemoteReconnectNow(cfg, state, reason)
        return
    }
    if (ShouldForceWakeReconnect(state)) {
        ForceRemoteReconnectNow(cfg, state, reason "_stale")
        return
    }
    if (IsRemoteUsingBridgeChannel(cfg, state)) {
        SendRemotePingWithWatchdog(cfg, state, "bridge")
    } else if (IsRemoteUsingInternetChannel(cfg, state)) {
        topic := GetInternetRelayTopic(cfg.InternetPairingCode)
        authTok := GetInternetRelayAuthToken(cfg.InternetPairingCode, cfg.ObsPassword)
        mockWs := (state.HasOwnProp("relayMockWs") && IsObject(state.relayMockWs)) ? state.relayMockWs : ""
        PublishInternetRelayPacket(topic, FormatRelayPacket("remote", "sync_req", "0", authTok), "https://ntfy.sh", mockWs)
    } else {
        SendRemotePingWithWatchdog(cfg, state, "obs")
    }
}

HandleRemotePowerEvent(cfg, state, wParam, lParam := 0) {
    wp := Integer(wParam)
    if (wp == 4) { ; PBT_APMSUSPEND
        if (IsObject(state))
            state.isSystemSuspending := true
        return "suspend"
    }
    if (wp == 7 || wp == 18) { ; PBT_APMRESUMESUSPEND / PBT_APMRESUMEAUTOMATIC
        if (IsObject(state))
            state.isSystemSuspending := false
        VerifyOrReconnectRemote(cfg, state, wp == 18 ? "power_resume_auto" : "power_resume")
        return "resume"
    }
    return ""
}

OnRemotePowerBroadcast(cfg, state, wParam, lParam, msg, hwnd) {
    HandleRemotePowerEvent(cfg, state, wParam, lParam)
}

RemoteHeartbeatTick(cfg, state) {
    if (!state.obsConnected || !IsObject(state.obsWs))
        return
    if (IsRemoteUsingBridgeChannel(cfg, state)) {
        SendRemotePingWithWatchdog(cfg, state, "bridge")
        return
    }
    if (IsRemoteUsingInternetChannel(cfg, state)) {
        topic := GetInternetRelayTopic(cfg.InternetPairingCode)
        authTok := GetInternetRelayAuthToken(cfg.InternetPairingCode, cfg.ObsPassword)
        mockWs := (state.HasOwnProp("relayMockWs") && IsObject(state.relayMockWs)) ? state.relayMockWs : ""
        PublishInternetRelayPacket(topic, FormatRelayPacket("remote", "sync_req", "0", authTok), "https://ntfy.sh", mockWs)
        return
    }
    ; Lightweight request to keep TCP session alive + verify response within 2500ms
    SendRemotePingWithWatchdog(cfg, state, "obs")
}

SyncRemoteMuteState(cfg, state, newMuted) {
    if (state.isMuted != newMuted) {
        state.isMuted := newMuted
        cfg.IsMuted := newMuted
        cfg.WriteBool("Settings", "IsMuted", newMuted)
        if (!newMuted)
            state.voiceWhileMuted := false
        PlayMuteAnimation(cfg, state)
        if (cfg.HasOwnProp("EnableAudioCue") && cfg.EnableAudioCue)
            PlayMuteAudioCue(newMuted)
        if (cfg.HasOwnProp("EnableMuteToast") && cfg.EnableMuteToast)
            ShowMuteToast(newMuted)
    }
}

RemoteLocalTimerTick(cfg, state) {
    return RemoteTimerTick(cfg, state)
}

SyncRemoteBridgeTelemetry(cfg, state, ev) {
    if (!IsObject(state) || !IsObject(ev))
        return
    prevRec := state.recState
    prevWarn := state.streamDropWarn
    prevVoiceWarn := state.voiceWhileMuted
    prevOsDrift := state.HasOwnProp("osMicMutedDrift") ? !!state.osMicMutedDrift : false
    prevDiskLvl := state.lowDiskWarnLevel
    prevDeadMic := state.deadMicWarn
    state.lowDiskWarnLevel := (ev.HasOwnProp("lowDiskWarnLevel") && IsNumber(ev.lowDiskWarnLevel)) ? Integer(ev.lowDiskWarnLevel) : 0
    state.lowDiskMb := (ev.HasOwnProp("lowDiskMb") && IsNumber(ev.lowDiskMb)) ? Integer(ev.lowDiskMb) : -1
    state.deadMicWarn := ev.HasOwnProp("deadMicWarn") ? !!ev.deadMicWarn : false
    if (state.lowDiskWarnLevel > prevDiskLvl && state.lowDiskWarnLevel > 0) {
        try TrayTip("Low disk space on Host recording drive: " state.lowDiskMb " MB free", "PresenterSync Remote", state.lowDiskWarnLevel >= 2 ? 0x3 : 0x2)
    }
    if (state.deadMicWarn && !prevDeadMic) {
        try TrayTip("Host mic is LIVE but no audio detected - check hardware switch or input", "PresenterSync Remote", 0x2)
    }
    state.osMicMutedDrift := ev.HasOwnProp("osMicMutedDrift") ? !!ev.osMicMutedDrift : false
    if (state.osMicMutedDrift && !prevOsDrift) {
        try TrayTip("OS Mic Muted - Windows hardware/privacy switch is muting the host mic while LIVE", "PresenterSync Remote", 0x2)
    }
    prevStandby := state.HasOwnProp("isStandby") ? !!state.isStandby : false
    prevTimerSt := state.HasOwnProp("timerState") ? state.timerState : "stopped"
    prevTimerRem := state.HasOwnProp("timerRemainingSec") ? state.timerRemainingSec : 600
    prevScene := state.HasOwnProp("activeScene") ? state.activeScene : "Scene"

    state.recState := ev.HasOwnProp("recState") ? ev.recState : 0
    state.recSeconds := ev.HasOwnProp("recSeconds") ? Max(0, ev.recSeconds) : 0
    state.streamDropWarn := ev.HasOwnProp("streamDropWarn") ? !!ev.streamDropWarn : false
    state.voiceWhileMuted := (state.isMuted && ev.HasOwnProp("voiceWhileMuted")) ? !!ev.voiceWhileMuted : false
    if (ev.HasOwnProp("activeScene") && ev.activeScene != "")
        state.activeScene := ev.activeScene
    if (ev.HasOwnProp("scenes") && IsObject(ev.scenes) && ev.scenes.Length > 0)
        state.scenes := ev.scenes
    if (ev.HasOwnProp("isStandby"))
        state.isStandby := !!ev.isStandby
    if (ev.HasOwnProp("standbyScene") && ev.standbyScene != "")
        state.standbyScene := ev.standbyScene
    if (ev.HasOwnProp("timerState") && ev.timerState != "")
        state.timerState := ev.timerState
    if (ev.HasOwnProp("timerRemainingSec"))
        state.timerRemainingSec := Integer(ev.timerRemainingSec)
    if (ev.HasOwnProp("timerPresetSec") && Integer(ev.timerPresetSec) > 0)
        state.timerPresetSec := Integer(ev.timerPresetSec)

    if (state.HasOwnProp("presenterTickFn") && IsObject(state.presenterTickFn)) {
        if (state.timerState = "running" || state.timerState = "overtime")
            SetTimer state.presenterTickFn, 1000
        else
            SetTimer state.presenterTickFn, 0
    }

    if (state.voiceWhileMuted && !prevVoiceWarn && (!cfg.HasOwnProp("EnableVoiceWhileMutedAlert") || cfg.EnableVoiceWhileMutedAlert)) {
        if ((A_TickCount - state._lastVoiceWarnTick) >= 5000) {
            state._lastVoiceWarnTick := A_TickCount
            ToolTip("⚠ You're on mute — mic signal detected on Host")
            SetTimer(RemoveToolTip, -2800)
        }
    }

    changed := (prevRec != state.recState || prevDiskLvl != state.lowDiskWarnLevel || prevDeadMic != state.deadMicWarn || prevOsDrift != state.osMicMutedDrift || prevWarn != state.streamDropWarn || prevVoiceWarn != state.voiceWhileMuted
        || prevStandby != state.isStandby || prevTimerSt != state.timerState || prevTimerRem != state.timerRemainingSec
        || prevScene != state.activeScene || state.recState > 0)
    if (changed) {
        if (prevStandby != state.isStandby && IsObject(state.rebuildTrayFn)) {
            try state.rebuildTrayFn.Call()
        } else {
            state.NotifyTrayStatus()
        }
    }
}

_SendRemoteRelayAction(cfg, state, cmd, data := "1") {
    if (!IsRemoteUsingInternetChannel(cfg, state))
        return false
    topic := GetInternetRelayTopic(cfg.InternetPairingCode)
    authTok := GetInternetRelayAuthToken(cfg.InternetPairingCode, cfg.ObsPassword)
    mockWs := (state.HasOwnProp("relayMockWs") && IsObject(state.relayMockWs)) ? state.relayMockWs : ""
    return PublishInternetRelayPacket(topic, FormatRelayPacket("remote", cmd, data, authTok), "https://ntfy.sh", mockWs)
}

SendRemoteBridgeDeckCommand(cfg, state, actionType) {
    actLow := StrLower(Trim(String(actionType)))
    if (actLow = "toggle_record" || actLow = "stop_record") {
        if (!TryConfirmRemoteStopRecording(cfg, state))
            return false
    }
    if (IsRemoteUsingInternetChannel(cfg, state))
        return _SendRemoteRelayAction(cfg, state, actionType, "1")
    if (IsRemoteUsingBridgeChannel(cfg, state)) {
        payload := BuildRemoteBridgeDeckJson(cfg, actionType)
        return TrySendWsText(state.obsWs, payload)
    }
    if (IsRemoteUsingDirectObsChannel(cfg, state) || (IsObject(state) && state.HasOwnProp("usingDirectObsFallback") && state.usingDirectObsFallback)) {
        actLow := StrLower(Trim(String(actionType)))
        if (actLow = "toggle_record")
            return SendObsRequest(state.obsWs, "ToggleRecord", "RemoteToggleRec")
        if (actLow = "pause_record") {
            ok := SendObsRequest(state.obsWs, "ToggleRecordPause", "RemotePauseRec")
            if (ok && (state.recState == 1 || state.recState == 2)) {
                state.recState := (state.recState == 1) ? 2 : 1
                UpdateRemoteLocalRecTimer(state)
                state.NotifyTrayStatus()
            }
            return ok
        }
        if (actLow = "split_record")
            return SendObsRequest(state.obsWs, "SplitRecordFile", "RemoteSplitRec")
        if (actLow = "toggle_standby")
            return ExecuteRemoteLocalStandbyToggle(cfg, state)
        if (actLow = "transition_scene")
            return ExecuteRemoteDirectObsTransition(cfg, state)
    }
    TrayTip("Director commands require an active Primary Host Bridge, Direct OBS, or Relay connection.", "PresenterSync Remote", 2)
    return false
}

SendRemoteSwitchScene(cfg, state, sceneName) {
    clean := Trim(String(sceneName))
    if (clean = "")
        return false
    if (IsRemoteUsingInternetChannel(cfg, state))
        return _SendRemoteRelayAction(cfg, state, "switch_scene", clean)
    if (IsRemoteUsingBridgeChannel(cfg, state))
        return TrySendWsText(state.obsWs, BuildRemoteBridgeSceneJson(cfg, clean))
    if (IsObject(state) && state.obsConnected && IsObject(state.obsWs)) {
        ok := SendObsRequest(state.obsWs, "SetCurrentProgramScene", "RemoteSwitchScene", '{"sceneName":"' EscapeJsonStr(clean) '"}')
        if (ok) {
            if (state.HasOwnProp("activeScene") && state.activeScene != "" && state.activeScene != "Scene" && state.activeScene != clean)
                state.previousProgramScene := state.activeScene
            state.activeScene := clean
            if (state.HasMethod("NotifyTrayStatus"))
                state.NotifyTrayStatus()
        }
        return ok
    }
    return false
}

SendRemoteTransitionScene(cfg, state) {
    return SendRemoteBridgeDeckCommand(cfg, state, "transition_scene")
}

SendRemoteTimerCommand(cfg, state, action, durationSec := 0) {
    if (IsRemoteUsingInternetChannel(cfg, state))
        return _SendRemoteRelayAction(cfg, state, action, String(Integer(durationSec)))
    if (IsRemoteUsingBridgeChannel(cfg, state))
        return TrySendWsText(state.obsWs, BuildRemoteBridgeTimerJson(cfg, action, durationSec))
    if (IsRemoteUsingDirectObsChannel(cfg, state) || (IsObject(state) && state.HasOwnProp("usingDirectObsFallback") && state.usingDirectObsFallback))
        return ExecuteRemoteLocalTimerCommand(cfg, state, action, durationSec)
    TrayTip("Presenter timer requires a Primary Host Bridge, Direct OBS, or Relay connection.", "PresenterSync Remote", 2)
    return false
}

SendRemoteStageNudge(cfg, state, message) {
    clean := Trim(String(message))
    if (clean = "")
        return false
    if (IsRemoteUsingInternetChannel(cfg, state))
        return _SendRemoteRelayAction(cfg, state, "stage_nudge", StrReplace(StrReplace(GetRemoteDisplayDeviceName(cfg), "|", "/"), ";", ",") ";" StrReplace(StrReplace(clean, "|", "/"), ";", ","))
    if (!IsRemoteUsingBridgeChannel(cfg, state)) {
        TrayTip("Stage nudges require a Primary Host Bridge or Relay connection.", "PresenterSync Remote", 2)
        return false
    }
    return TrySendWsText(state.obsWs, BuildRemoteBridgeNudgeJson(cfg, clean))
}

; --- REMOTE CLICKER MUTE TRANSMISSION ---

RemoveToolTip() {
    ToolTip()
}

OnRemoteClickerMute(cfg, state, thisHotkeyOrFromHud := "", *) {
    if (!cfg.EnablePointerMute || (IsSet(HudSnake) && HudSnake.IsActive))
        return

    fromHudClick := (thisHotkeyOrFromHud == true)
    static lastTick := 0
    static inHold := false
    if (inHold)
        return
    now := A_TickCount
    if (now - lastTick < 150) ; 150ms hardware debounce shield
        return
    lastTick := now

    if (!state.obsConnected || !IsObject(state.obsWs)) {
        ToolTip "PresenterSync Remote: Not connected to OBS host"
        SetTimer RemoveToolTip, -2000
        return
    }

    inHold := true
    try {
        if (!fromHudClick && cfg.HasOwnProp("EnablePushToTalk") && cfg.EnablePushToTalk) {
            ExecutePushToTalkHoldCycle(cfg, state, (m) => DispatchRemoteSetMute(cfg, state, m), cfg.HwMuteHotkey, state.HasOwnProp("keyWaitFn") ? state.keyWaitFn : "")
            lastTick := A_TickCount
        } else if (DispatchRemoteMuteToggle(cfg, state)) {
            if (!fromHudClick && WaitPushToMuteRelease(cfg, cfg.HwMuteHotkey, state.HasOwnProp("keyWaitFn") ? state.keyWaitFn : "")) {
                DispatchRemoteMuteToggle(cfg, state)
                lastTick := A_TickCount
            }
        }
    } finally {
        inHold := false
    }
}

CheckRemotePointerEnable(cfg, ThisHotkey) {
    return cfg.EnablePointerMute && !(IsSet(HudSnake) && HudSnake.IsActive) && (Theme.OpenWindows.Count == 0 || !Theme.OpenWindows.Has(WinExist("A")))
}

RegisterRemotePointerHotkey(cfg, state) {
    UnregisterRemotePointerHotkey(cfg, state)
    if (!cfg.EnablePointerMute || cfg.HwMuteHotkey = "" || cfg.HwMuteHotkey = "None")
        return
    try {
        HotIf state.pointerHotIfFn
        Hotkey cfg.HwMuteHotkey, OnRemoteClickerMute.Bind(cfg, state), "On"
        state.activePointerKey := cfg.HwMuteHotkey
        HotIf
    } catch {
        HotIf
    }
}

UnregisterRemotePointerHotkey(cfg, state) {
    keyToClear := (state.activePointerKey != "") ? state.activePointerKey : cfg.HwMuteHotkey
    if (keyToClear != "" && keyToClear != "None") {
        try {
            HotIf state.pointerHotIfFn
            Hotkey keyToClear, "Off"
            HotIf
        } catch {
            HotIf
        }
    }
    state.activePointerKey := ""
}

ExitRemoteApp(*) {
    ExitApp()
}

RegisterRemoteAppHotkeys(cfg, state) {
    UnregisterRemoteAppHotkeys(cfg, state)
    if (cfg.PptHotkey != "" && cfg.PptHotkey != "None") {
        try {
            Hotkey cfg.PptHotkey, ToggleRemotePointerMute.Bind(cfg, state), "On"
            state.activeToggleMuteHk := cfg.PptHotkey
        }
    }
    if (cfg.ExitHotkey != "" && cfg.ExitHotkey != "None") {
        try {
            Hotkey cfg.ExitHotkey, ExitRemoteApp, "On"
            state.activeExitHk := cfg.ExitHotkey
        }
    }
}

UnregisterRemoteAppHotkeys(cfg, state) {
    hkToggle := (state.activeToggleMuteHk != "") ? state.activeToggleMuteHk : cfg.PptHotkey
    if (hkToggle != "" && hkToggle != "None") {
        try Hotkey hkToggle, "Off"
    }
    state.activeToggleMuteHk := ""

    hkExit := (state.activeExitHk != "") ? state.activeExitHk : cfg.ExitHotkey
    if (hkExit != "" && hkExit != "None") {
        try Hotkey hkExit, "Off"
    }
    state.activeExitHk := ""
}

; --- SINGLE-PILL HUD CREATION & DRAGGING ---

InitRemoteHUD(cfg, state) {
    state.ComputeDimensions(cfg)
    state.currentAlpha := GetRemoteEffectiveAlpha(state)

    ; Only create a single layered GDI+ window for the Mic HUD
    hudTitle := "PresenterSync Remote HUD" (cfg.HasOwnProp("InstanceName") && cfg.InstanceName != "" ? " [" cfg.InstanceName "]" : "")
    state.MicGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000 -DPIScale", hudTitle)
    ApplyWindowCaptureAffinity(state.MicGui.Hwnd, cfg.HasOwnProp("ExcludeFromCapture") ? cfg.ExcludeFromCapture : true)
    ApplyMicAppearance(cfg, state)

    if (cfg.ShowIndicator) {
        state.MicGui.Show(Format("NoActivate x{} y{} w{} h{}", state.savedX, state.savedY, state.baseWidth, state.baseHeight))
        if (state.isMuted && state.obsConnected)
            SetTimer state.breathTimerFn, (cfg.AggressivePulse ? UIConstants.PULSE_INTERVAL_AGGRESSIVE : UIConstants.PULSE_INTERVAL_NORMAL)
    }
    ApplyHudClickThroughStyle(cfg, state)
    ApplyWindowCaptureAffinity(state.MicGui.Hwnd, cfg.HasOwnProp("ExcludeFromCapture") ? cfg.ExcludeFromCapture : true)
    UpdateAutoDodgeTimer(cfg, state)

    OnMessage(0x0201, WM_REMOTE_LBUTTONDOWN.Bind(cfg, state))
    OnMessage(0x0205, WM_REMOTE_RBUTTONUP.Bind(state))
    OnMessage(0x02E0, WM_REMOTE_DPICHANGED.Bind(cfg, state))
    OnMessage(0x0211, OnRemoteMenuLoop.Bind(state, true))
    OnMessage(0x0212, OnRemoteMenuLoop.Bind(state, false))
}

WM_REMOTE_LBUTTONDOWN(cfg, state, wParam, lParam, msg, hwnd) {
    if (!IsObject(state.MicGui) || hwnd != state.MicGui.Hwnd)
        return

    prevX := state.savedX
    prevY := state.savedY
    prevMouseMode := A_CoordModeMouse
    CoordMode("Mouse", "Screen")
    MouseGetPos(&startMX, &startMY)
    downTick := A_TickCount

    state.animSeq += 1
    SetTimer state.breathTimerFn, 0
    state.isDraggingHud := true
    PostMessage(0xA1, 2,,, "ahk_id " hwnd) ; Native Windows drag (HTCAPTION)
    KeyWait "LButton"
    state.isDraggingHud := false

    MouseGetPos(&endMX, &endMY)
    CoordMode("Mouse", prevMouseMode)
    isShortClick := (Abs(endMX - startMX) <= 3 && Abs(endMY - startMY) <= 3 && (A_TickCount - downTick) < 400)

    if (isShortClick) {
        state.savedX := prevX
        state.savedY := prevY
        state.MicGui.Move(prevX, prevY, state.baseWidth, state.baseHeight)
    } else {
        WinGetPos(&X, &Y,,, "ahk_id " hwnd)
        if (!cfg.HasOwnProp("EnableMagneticSnap") || cfg.EnableMagneticSnap) {
            snap := ComputeMagneticSnap(X, Y, state.baseWidth, state.baseHeight, 0, UIConstants.SNAP_THRESHOLD_PX, GetCandidateSnapWindowRects(state))
            X := snap.x, Y := snap.y
        }
        state.savedX := X
        state.savedY := Y
        state.MicGui.Move(X, Y, state.baseWidth, state.baseHeight)
        if (X != prevX || Y != prevY) {
            cfg.savedX := X
            cfg.savedY := Y
            cfg.Write("Position", "X", X)
            cfg.Write("Position", "Y", Y)
        }
    }
    state.currentAlpha := GetRemoteEffectiveAlpha(state)
    ApplyMicAppearance(cfg, state)
    ApplyHudClickThroughStyle(cfg, state)
    if (cfg.ShowIndicator && state.obsConnected && state.isMuted)
        SetTimer state.breathTimerFn, (cfg.AggressivePulse ? UIConstants.PULSE_INTERVAL_AGGRESSIVE : UIConstants.PULSE_INTERVAL_NORMAL)

    if (isShortClick)
        HandleRemoteHudClick(cfg, state)
}

HandleRemoteHudClick(cfg, state) {
    if (!IsObject(cfg) || !IsObject(state))
        return false
    if (cfg.HasOwnProp("EnableHudClickActions") && !cfg.EnableHudClickActions)
        return false
    if (!cfg.EnablePointerMute) {
        ToolTip("PresenterSync Remote: Pointer mute control is OFF")
        SetTimer(() => ToolTip(), -1500)
        return false
    }
    OnRemoteClickerMute(cfg, state, true)
    return true
}

WM_REMOTE_RBUTTONUP(state, wParam, lParam, msg, hwnd) {
    if (IsObject(state.MicGui) && hwnd == state.MicGui.Hwnd)
        A_TrayMenu.Show()
}

OnRemoteMenuLoop(state, isEnter, wParam, lParam, msg, hwnd) {
    if (!IsObject(state))
        return
    if (isEnter) {
        state._trayMenuOpen := true
        state._trayMenuCloseUntil := 0
    } else {
        state._trayMenuOpen := false
        state._trayMenuCloseUntil := A_TickCount + 300
        if (state.HasOwnProp("_pendingTrayRebuild") && state._pendingTrayRebuild) {
            state._pendingTrayRebuild := false
            if (IsObject(state.rebuildTrayFn))
                SetTimer state.rebuildTrayFn, -350
        }
    }
}

WM_REMOTE_DPICHANGED(cfg, state, wParam, lParam, msg, hwnd) {
    if (!IsObject(state.MicGui) || hwnd != state.MicGui.Hwnd)
        return
    newLeft := NumGet(lParam, 0, "Int")
    newTop := NumGet(lParam, 4, "Int")
    state.savedX := newLeft
    state.savedY := newTop
    state.MicGui.Move(newLeft, newTop, state.baseWidth, state.baseHeight)
    ApplyMicAppearance(cfg, state)
}

RefreshRemoteHudAppearance(cfg, state) {
    state.animSeq += 1
    state.baseAlpha := cfg.OpacityLevel
    state.breathDir := cfg.AggressivePulse ? -UIConstants.PULSE_STEP_AGGRESSIVE : -UIConstants.PULSE_STEP_NORMAL
    state.ComputeDimensions(cfg)
    state.currentAlpha := GetRemoteEffectiveAlpha(state)
    ApplyMicAppearance(cfg, state)
    if (cfg.ShowIndicator) {
        state.MicGui.Move(state.savedX, state.savedY, state.baseWidth, state.baseHeight)
        state.MicGui.Show(Format("NoActivate x{} y{} w{} h{}", state.savedX, state.savedY, state.baseWidth, state.baseHeight))
        if (state.isMuted && state.obsConnected) {
            SetTimer state.breathTimerFn, (cfg.AggressivePulse ? UIConstants.PULSE_INTERVAL_AGGRESSIVE : UIConstants.PULSE_INTERVAL_NORMAL)
        } else {
            SetTimer state.breathTimerFn, 0
        }
    } else {
        state.MicGui.Hide()
        SetTimer state.breathTimerFn, 0
    }
    ApplyHudClickThroughStyle(cfg, state)
    ApplyWindowCaptureAffinity(state.MicGui.Hwnd, cfg.HasOwnProp("ExcludeFromCapture") ? cfg.ExcludeFromCapture : true)
    UpdateAutoDodgeTimer(cfg, state)
}

; --- TRAY MENU & COSMETIC ACTIONS ---

GetRemoteTrayStatusText(state) {
    if (state.connStatus = "pw_required")
        return "🔒 OBS Password Required (Check Connection)"
    else if (state.connStatus = "auth_failed")
        return "✕ Auth Failed (Check Password)"
    else if (state.obsConnected && state.connStatus = "mic_error")
        return "⚠ Connected (Mic Not Found): " state.activeHost
    else if (state.obsConnected) {
        isDirectObs := (state.HasOwnProp("usingDirectObsFallback") && state.usingDirectObsFallback)
        txt := isDirectObs ? FormatRemoteDirectObsStatus(state.activeHost) : ("● Connected: " state.activeHost)
        if (state.HasOwnProp("isStandby") && state.isStandby)
            txt .= " | STANDBY"
        if (state.recState == 1)
            txt .= " | REC " FormatElapsedShort(state.recSeconds)
        else if (state.recState == 2)
            txt .= " | PAUSED " FormatElapsedShort(state.recSeconds)
        if (state.HasOwnProp("timerState") && state.timerState != "stopped")
            txt .= " | " (state.timerState = "overtime" ? "OT " : "TMR ") FormatCountdownClock(state.timerRemainingSec)
        if (state.streamDropWarn)
            txt .= " | ⚠ STREAM WARN"
        if (state.osMicMutedDrift)
            txt .= " | OS MIC MUTED"
        if (state.lowDiskWarnLevel > 0)
            txt .= (state.lowDiskWarnLevel >= 2 ? " | LOW DISK CRITICAL " : " | LOW DISK ") state.lowDiskMb "MB"
        if (state.deadMicWarn)
            txt .= " | DEAD MIC"
        if (state.voiceWhileMuted && state.isMuted)
            txt .= " | ⚠ MIC SIGNAL"
        return txt
    }
    return "○ Searching for OBS Host..."
}

SyncRemoteTrayStatus(cfg, state) {
    instTag := (IsObject(cfg) && cfg.HasOwnProp("InstanceName") && cfg.InstanceName != "") ? (" [" cfg.InstanceName "]") : ""
    fbTag := (IsObject(state) && state.HasOwnProp("usingDirectObsFallback") && state.usingDirectObsFallback) ? " | Fallback: DIRECT OBS :4455" : ""
    A_IconTip := "PresenterSync Remote v" UIConstants.APP_VERSION instTag fbTag
    newStatus := GetRemoteTrayStatusText(state)
    if (state.HasOwnProp("_lastTrayStatusText") && state._lastTrayStatusText == newStatus)
        return
    state._lastTrayStatusText := newStatus
    if (IsObject(state) && state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn)
        try state.refreshHelpFn.Call()
    ; Rename status row 1 in-place so A_TrayMenu handles/submenus & command IDs stay intact
    try {
        A_TrayMenu.Rename("1&", newStatus)
        A_TrayMenu.Disable("1&")
        return
    }
    BuildRemoteTrayMenu(cfg, state)
}

BuildRemoteTrayMenu(cfg, state) {
    if (IsObject(state) && state.HasOwnProp("_trayMenuOpen") && state._trayMenuOpen) {
        state._pendingTrayRebuild := true
        return
    }
    if (IsObject(state))
        state._pendingTrayRebuild := false
    Theme.ApplyMenuTheme()
    A_TrayMenu.Delete()

    ; 1. STATUS LINE
    statusText := GetRemoteTrayStatusText(state)
    if (IsObject(state))
        state._lastTrayStatusText := statusText
    A_TrayMenu.Add(statusText, (*) => 0)
    A_TrayMenu.Disable(statusText)
    A_TrayMenu.Add()

    ; 2. INDICATOR VISIBILITY
    A_TrayMenu.Add("Show Mute Indicator", ToggleRemoteIndicator.Bind(cfg, state))
    if (cfg.ShowIndicator)
        A_TrayMenu.Check("Show Mute Indicator")

    ; 3. COSMETIC APPEARANCE SUBMENU
    AppearanceMenu := Menu()
    AppearanceMenu.Add("Show Text Label", ToggleRemoteText.Bind(cfg, state))
    if (cfg.ShowText)
        AppearanceMenu.Check("Show Text Label")

    AppearanceMenu.Add("Use Monochromatic Icon", ToggleRemoteMono.Bind(cfg, state))
    if (cfg.MonoIcon)
        AppearanceMenu.Check("Use Monochromatic Icon")

    AppearanceMenu.Add("Use Sleek Corners", ToggleRemoteCorners.Bind(cfg, state))
    if (cfg.SleekCorners)
        AppearanceMenu.Check("Use Sleek Corners")

    AppearanceMenu.Add("Aggressive Mute Pulse", ToggleRemotePulse.Bind(cfg, state))
    if (cfg.AggressivePulse)
        AppearanceMenu.Check("Aggressive Mute Pulse")

    AppearanceMenu.Add("Mute Audio Cue (Beep)", ToggleAudioCue.Bind(cfg, state))
    if (cfg.EnableAudioCue)
        AppearanceMenu.Check("Mute Audio Cue (Beep)")

    AppearanceMenu.Add("Mute Status Toast", ToggleMuteToast.Bind(cfg, state))
    if (cfg.EnableMuteToast)
        AppearanceMenu.Check("Mute Status Toast")

    AppearanceMenu.Add("Voice-While-Muted Alert", (*) => ToggleBoolSetting(cfg, state, "EnableVoiceWhileMutedAlert"))
    if (cfg.EnableVoiceWhileMutedAlert)
        AppearanceMenu.Check("Voice-While-Muted Alert")

    AppearanceMenu.Add("Interactive HUD Click Actions", (*) => ToggleBoolSetting(cfg, state, "EnableHudClickActions"))
    if (cfg.EnableHudClickActions)
        AppearanceMenu.Check("Interactive HUD Click Actions")

    AppearanceMenu.Add("Magnetic Edge/Window Snap", ToggleMagneticSnap.Bind(cfg, state))
    if (cfg.EnableMagneticSnap)
        AppearanceMenu.Check("Magnetic Edge/Window Snap")

    AppearanceMenu.Add("Click-Through HUD (Hold Alt)", ToggleHudClickThrough.Bind(cfg, state))
    if (cfg.HudClickThrough)
        AppearanceMenu.Check("Click-Through HUD (Hold Alt)")

    AppearanceMenu.Add("Auto-Dodge HUD on Hover", ToggleHudAutoDodge.Bind(cfg, state))
    if (cfg.HudAutoDodge)
        AppearanceMenu.Check("Auto-Dodge HUD on Hover")

    AppearanceMenu.Add("Hide HUD from Screen Share / Capture", (*) => ToggleHudOptionAndRebuild(cfg, state, "ExcludeFromCapture", "Appearance", RefreshRemoteHudAppearance, BuildRemoteTrayMenu))
    if (cfg.ExcludeFromCapture)
        AppearanceMenu.Check("Hide HUD from Screen Share / Capture")

    AppearanceMenu.Add()

    BuildSharedAppearanceSubmenus(
        AppearanceMenu, cfg, state,
        SetRemoteOpacity.Bind(cfg, state),
        SetRemoteScale.Bind(cfg, state),
        SetRemoteTheme.Bind(cfg, state)
    )

    AppearanceMenu.Add()
    AppearanceMenu.Add("Reset Indicator Position", ResetRemotePositionAction.Bind(cfg, state))
    AppearanceMenu.Add("Restore Default Appearance", ResetRemoteAppearanceAction.Bind(cfg, state))

    A_TrayMenu.Add("Indicator Appearance", AppearanceMenu)
    DeckMenu := Menu()
    DeckMenu.Add("Next Slide (Host PowerPoint)", (*) => SendRemoteBridgeDeckCommand(cfg, state, "ppt_next"))
    DeckMenu.Add("Previous Slide (Host PowerPoint)", (*) => SendRemoteBridgeDeckCommand(cfg, state, "ppt_prev"))
    DeckMenu.Add()
    DeckSceneMenu := Menu()
    if (IsObject(state) && state.HasOwnProp("scenes") && IsObject(state.scenes) && state.scenes.Length > 0) {
        for scItem in state.scenes {
            DeckSceneMenu.Add(scItem, ((s, *) => SendRemoteSwitchScene(cfg, state, s)).Bind(scItem))
            if (state.HasOwnProp("activeScene") && state.activeScene == scItem)
                DeckSceneMenu.Check(scItem)
        }
    } else {
        DeckSceneMenu.Add("Connect Primary Bridge for scenes", (*) => 0)
        DeckSceneMenu.Disable("Connect Primary Bridge for scenes")
    }
    DeckMenu.Add("Transition OBS Scene (Preview <-> Program)", (*) => SendRemoteBridgeDeckCommand(cfg, state, "transition_scene"))
    DeckMenu.Add("Switch Host Scene", DeckSceneMenu)
    DeckMenu.Add("Toggle Standby / `"BRB`" Curtain", (*) => SendRemoteBridgeDeckCommand(cfg, state, "toggle_standby"))
    if (IsObject(state) && state.HasOwnProp("isStandby") && state.isStandby)
        DeckMenu.Check("Toggle Standby / `"BRB`" Curtain")
    DeckMenu.Add("Start / Stop Host Recording", (*) => SendRemoteBridgeDeckCommand(cfg, state, "toggle_record"))
    DeckMenu.Add("Pause / Resume Host Recording", (*) => SendRemoteBridgeDeckCommand(cfg, state, "pause_record"))
    DeckMenu.Add("Split Host Recording Chapter", (*) => SendRemoteBridgeDeckCommand(cfg, state, "split_record"))
    DeckMenu.Add()
    DeckMenu.Add("Presenter Countdown Timer", BuildSharedPresenterTimerSubmenu(state, (sec, *) => SendRemoteTimerCommand(cfg, state, "timer_start", sec), (*) => SendRemoteTimerCommand(cfg, state, "timer_pause", 0), (sec, *) => SendRemoteTimerCommand(cfg, state, "timer_reset", sec)))
    DeckMenu.Add("Send Stage Nudge to Host...", (*) => PromptSendStageNudgeUI((msg) => SendRemoteStageNudge(cfg, state, msg)))
    deckLabel := (IsObject(state) && state.HasOwnProp("usingDirectObsFallback") && state.usingDirectObsFallback) ? "Host Deck Control (DIRECT OBS :4455)" : "Host Deck Control (Bridge)"
    A_TrayMenu.Add(deckLabel, DeckMenu)
    A_TrayMenu.Add()

    ; 4. POINTER & CONNECTION SETTINGS
    PointerMenu := Menu()
    PointerMenu.Add("Enable Pointer Mute", ToggleRemotePointerMute.Bind(cfg, state))
    if (cfg.EnablePointerMute)
        PointerMenu.Check("Enable Pointer Mute")
    PointerMenu.Add("Enable Cough / Push-to-Mute (Hold)", TogglePushToMute.Bind(cfg, state))
    if (cfg.EnablePushToMute)
        PointerMenu.Check("Enable Cough / Push-to-Mute (Hold)")
    PointerMenu.Add("Enable Push-to-Talk (Hold to Unmute)", TogglePushToTalk.Bind(cfg, state))
    if (cfg.HasOwnProp("EnablePushToTalk") && cfg.EnablePushToTalk)
        PointerMenu.Check("Enable Push-to-Talk (Hold to Unmute)")
    PointerMenu.Add("Change Pointer Mute Button...", (*) => ChangeRemotePointerKeyUI(cfg, state))
    PointerMenu.Add("Launch Clicker Tester...", (*) => ShowPointerTester())
    A_TrayMenu.Add("Pointer Controls", PointerMenu)

    A_TrayMenu.Add("Change OBS Connection...", (*) => ShowRemoteConnectionUI(cfg, state, false))
    A_TrayMenu.Add("Change App Shortcuts...", (*) => ChangeRemoteAppHotkeysUI(cfg, state))
    A_TrayMenu.Add("Start with Windows", ToggleStartWithWindows.Bind(cfg, state))
    if (cfg.StartWithWindows)
        A_TrayMenu.Check("Start with Windows")
    A_TrayMenu.Add("Create Desktop Shortcut for Instance...", (*) => ShowCreateRemoteShortcutUI(cfg, state))
    A_TrayMenu.Add()

    ; 5. HELP, SAFETY & EXIT
    A_TrayMenu.Add("Help && Setup Guide...", (*) => ShowRemoteHelpUI(cfg, state))
    A_TrayMenu.Add("View Error && Diagnostic Log...", (*) => DiagnosticLogger.ShowLogViewerWindow(cfg, state))
    A_TrayMenu.Add("About PresenterSync Remote...", (*) => ShowRemoteAboutUI(cfg, state))
    A_TrayMenu.Add("Check for Updates...", (*) => CheckForUpdates(UIConstants.APP_VERSION, "", false, "PresenterSync_Remote.exe", cfg))
    A_TrayMenu.Add("Suspend All Hotkeys", ToggleRemoteSuspend)
    if (Theme.SuspendLockCount > 0 ? Theme.WasSuspendedBeforeDialogs : A_IsSuspended)
        A_TrayMenu.Check("Suspend All Hotkeys")
    A_TrayMenu.Add("Exit PresenterSync Remote", ExitRemoteApp)

    if (IsObject(state) && state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn)
        try state.refreshHelpFn.Call()
}

ToggleRemoteIndicator(cfg, state, *) => ToggleHudOptionAndRebuild(cfg, state, "ShowIndicator", "Appearance", RefreshRemoteHudAppearance, BuildRemoteTrayMenu)
ToggleRemoteText(cfg, state, *) => ToggleHudOptionAndRebuild(cfg, state, "ShowText", "Appearance", RefreshRemoteHudAppearance, BuildRemoteTrayMenu)
ToggleRemoteMono(cfg, state, *) => ToggleHudOptionAndRebuild(cfg, state, "MonoIcon", "Appearance", RefreshRemoteHudAppearance, BuildRemoteTrayMenu)
ToggleRemoteCorners(cfg, state, *) => ToggleHudOptionAndRebuild(cfg, state, "SleekCorners", "Appearance", RefreshRemoteHudAppearance, BuildRemoteTrayMenu)
ToggleRemotePulse(cfg, state, *) => ToggleHudOptionAndRebuild(cfg, state, "AggressivePulse", "Appearance", RefreshRemoteHudAppearance, BuildRemoteTrayMenu)
SetRemoteOpacity(cfg, state, val, *) => SetHudOpacityAndRebuild(cfg, state, val, "Appearance", RefreshRemoteHudAppearance, BuildRemoteTrayMenu, GetRemoteEffectiveAlpha)

SetRemoteScale(cfg, state, val, *) {
    cfg.IndicatorScale := val
    cfg.Write("Appearance", "IndicatorScale", val)
    RefreshRemoteHudAppearance(cfg, state)
    BuildRemoteTrayMenu(cfg, state)
}

SetRemoteTheme(cfg, state, themeMenu, mode, *) {
    SetThemeMode(cfg, themeMenu, mode)
    Theme.ApplyMenuTheme()
    BuildRemoteTrayMenu(cfg, state)
}

ShowCreateRemoteShortcutUI(cfg, state := "", *) {
    existing := Theme.FocusExistingWindow("Create Remote Instance Shortcut")
    if IsObject(existing)
        return existing

    Theme.AcquireSuspend()

    dlg := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "Create Remote Instance Shortcut")
    dlg._closed := false
    dlg.MarginX := 20
    dlg.MarginY := 16
    Theme.ApplyToWindow(dlg)
    Theme.NamedWindows["Create Remote Instance Shortcut"] := dlg

    dlg.SetFont("s10 w600", Theme.UiFont)
    Theme.RegisterControl(dlg, dlg.Add("Text", "xm w360", "Quick-Launch Desktop Shortcut"), "Text")
    dlg.SetFont("s9 w400", Theme.UiFont)
    Theme.RegisterControl(dlg, dlg.Add("Text", "xm w360 h32 y+4", "Creates a Desktop .lnk launching PresenterSync Remote for a dedicated Smart Board or classroom instance."), "Text", "muted")

    curInst := (IsObject(cfg) && cfg.HasOwnProp("InstanceName")) ? cfg.InstanceName : ""
    dlg.SetFont("s9 w600", Theme.UiFont)
    Theme.RegisterControl(dlg, dlg.Add("Text", "xm w360 y+10", "Instance Name (Optional, e.g. SmartBoard-101):"), "Text")
    dlg.SetFont("s9 w400", Theme.UiFont)
    edInst := dlg.Add("Edit", "xm w360 y+4", curInst)
    Theme.RegisterControl(dlg, edInst, "Edit")
    DllCall("SendMessage", "Ptr", edInst.Hwnd, "UInt", 0x1501, "Ptr", 1, "WStr", "SmartBoard-Room101 (leave blank for Default)")

    dlg.SetFont("s9 w600", Theme.UiFont)
    Theme.RegisterControl(dlg, dlg.Add("Text", "xm w360 y+10", "Desktop Shortcut Filename:"), "Text")
    dlg.SetFont("s9 w400", Theme.UiFont)
    defaultLnkName := RegExReplace(GetDefaultRemoteShortcutFilename(curInst), "i)\.lnk$", "")
    edLnkName := dlg.Add("Edit", "xm w360 y+4", defaultLnkName)
    Theme.RegisterControl(dlg, edLnkName, "Edit")

    chkPinIni := dlg.Add("Checkbox", "xm w360 y+10", "Include explicit -Config INI path in shortcut")
    Theme.RegisterControl(dlg, chkPinIni, "Checkbox")

    initSpec := BuildRemoteShortcutLaunchSpec(curInst, "")
    lblPreview := dlg.Add("Text", "xm w360 h34 y+8", "Args: " (initSpec.args != "" ? initSpec.args : "(default instance)"))
    Theme.RegisterControl(dlg, lblPreview, "Text", "muted")

    userEditedLnk := false
    UpdatePreview(*) {
        instNow := Trim(edInst.Value)
        if (!userEditedLnk)
            edLnkName.Value := RegExReplace(GetDefaultRemoteShortcutFilename(instNow), "i)\.lnk$", "")
        cfgArg := (chkPinIni.Value && IsObject(cfg) && cfg.HasOwnProp("ConfigFile")) ? cfg.ConfigFile : ""
        spec := BuildRemoteShortcutLaunchSpec(instNow, cfgArg)
        lblPreview.Value := "Args: " (spec.args != "" ? spec.args : "(default instance)")
    }
    edInst.OnEvent("Change", UpdatePreview)
    edLnkName.OnEvent("Change", (*) => (userEditedLnk := true))
    chkPinIni.OnEvent("Click", UpdatePreview)

    btnCreate := dlg.Add("Button", "xm w174 h32 y+14 Default", "Create Shortcut")
    btnCancel := dlg.Add("Button", "x+12 yp w174 h32", "Cancel")
    Theme.RegisterControl(dlg, btnCreate, "Button", "accent")
    Theme.RegisterControl(dlg, btnCancel, "Button")

    CloseDlg(*) {
        if (dlg._closed)
            return
        dlg._closed := true
        Theme.UnregisterWindow(dlg, "Create Remote Instance Shortcut")
        Theme.ReleaseSuspend()
        dlg.Destroy()
    }

    OnCreateClick(*) {
        res := CreateRemoteInstanceDesktopShortcut(cfg, Trim(edInst.Value), "", Trim(edLnkName.Value), !!chkPinIni.Value)
        if (res.ok) {
            CloseDlg()
            TrayTip("Created Desktop shortcut: " res.lnkPath, "PresenterSync Remote", 1)
        } else {
            dlg.Opt("+OwnDialogs")
            MsgBox("Failed to create Desktop shortcut:`n`n" res.error, "Shortcut Error", "Icon!")
        }
    }

    btnCreate.OnEvent("Click", OnCreateClick)
    btnCancel.OnEvent("Click", CloseDlg)
    dlg.OnEvent("Close", CloseDlg)
    dlg.OnEvent("Escape", CloseDlg)
    dlg.Show()
    return dlg
}

ResetRemotePositionAction(cfg, state, *) {
    cfg.ResetPosition()
    RefreshRemoteHudAppearance(cfg, state)
    if (IsObject(state) && state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn)
        try state.refreshHelpFn.Call()
}

ResetRemoteAppearanceAction(cfg, state, *) {
    cfg.ResetAppearance()
    RefreshRemoteHudAppearance(cfg, state)
    BuildRemoteTrayMenu(cfg, state)
}

ToggleRemotePointerMute(cfg, state, *) {
    ToolTip()
    cfg.EnablePointerMute := !cfg.EnablePointerMute
    cfg.WriteBool("Pointer", "EnablePointerMute", cfg.EnablePointerMute)
    if (cfg.EnablePointerMute) {
        RegisterRemotePointerHotkey(cfg, state)
        ToolTip "Pointer Mute Control: ON"
    } else {
        UnregisterRemotePointerHotkey(cfg, state)
        ToolTip "Pointer Mute Control: OFF"
    }
    BuildRemoteTrayMenu(cfg, state)
    SetTimer RemoveToolTip, -UIConstants.TOOLTIP_DURATION_MS
}

ToggleRemoteSuspend(*) {
    if (Theme.SuspendLockCount > 0) {
        Theme.WasSuspendedBeforeDialogs := !Theme.WasSuspendedBeforeDialogs
        if (Theme.WasSuspendedBeforeDialogs)
            A_TrayMenu.Check("Suspend All Hotkeys")
        else
            A_TrayMenu.Uncheck("Suspend All Hotkeys")
        TrayTip(Theme.WasSuspendedBeforeDialogs ? "Hotkeys will remain suspended after dialog closes." : "Hotkeys will resume after dialog closes.", "PresenterSync Remote", 1)
        return
    }
    Suspend(-1)
    Theme.WasSuspendedBeforeDialogs := A_IsSuspended
    if A_IsSuspended {
        A_TrayMenu.Check("Suspend All Hotkeys")
        TrayTip("All hotkeys suspended.", "PresenterSync Remote", 1)
    } else {
        A_TrayMenu.Uncheck("Suspend All Hotkeys")
        TrayTip("Hotkeys active.", "PresenterSync Remote", 1)
    }
}

; --- SETTINGS DIALOGS ---

ChangeRemotePointerKeyUI(cfg, state, *) {
    return OpenPointerKeyCaptureDialog(cfg.HwMuteHotkey, "Save & Apply", (val) => (
        UnregisterRemotePointerHotkey(cfg, state),
        cfg.HwMuteHotkey := val,
        cfg.Write("Pointer", "HwMuteHotkey", val),
        RegisterRemotePointerHotkey(cfg, state),
        BuildRemoteTrayMenu(cfg, state),
        TrayTip(cfg.EnablePointerMute ? ("Mute button registered: " val) : ("Mute button saved (Pointer Mute disabled): " val), "Pointer Mute", 1)
    ))
}

ChangeRemoteAppHotkeysUI(cfg, state, *) {
    SaveRemoteAppHk(values, ctrls, dlg) {
        UnregisterRemoteAppHotkeys(cfg, state)
        cfg.PptHotkey := values["ppt"]
        cfg.ExitHotkey := values["exit"]
        cfg.Write("Shortcuts", "PptHotkey", cfg.PptHotkey)
        cfg.Write("Shortcuts", "ExitHotkey", cfg.ExitHotkey)
        if dlg.HasOwnProp("_releaseState")
            dlg._releaseState.Call()
        dlg.Destroy()
        RegisterRemoteAppHotkeys(cfg, state)
        BuildRemoteTrayMenu(cfg, state)
        TrayTip("Remote app shortcuts updated (" FormatHK(cfg.PptHotkey) " / " FormatHK(cfg.ExitHotkey) ").", "PresenterSync Remote", 1)
    }

    elements := [
        {type: "Text", opts: "xm w170 h25 +0x200", text: "Toggle Pointer Mute:"},
        {type: "Hotkey", id: "ppt", opts: "x+10 yp w130 h25", value: cfg.PptHotkey, required: true, errorMsg: "Shortcuts cannot be left blank."},
        {type: "Text", opts: "xm y+8 w170 h25 +0x200", text: "Exit PresenterSync Remote:"},
        {type: "Hotkey", id: "exit", opts: "x+10 yp w130 h25", value: cfg.ExitHotkey, required: true, errorMsg: "Shortcuts cannot be left blank."}
    ]

    return BuildSettingsWindow("Edit Remote App Shortcuts", elements, SaveRemoteAppHk, {
        saveBtnText: "Save & Apply",
        saveBtnOpts: "xm w310 h32 Default y+16"
    })
}

BuildRemoteHelpStatusLine(cfg, state) {
    connState := (state.connStatus = "pw_required") ? "OBS Password Required (Set in Connection)"
        : ((state.connStatus = "auth_failed") ? "Auth Failed (Check Password)"
        : ((state.obsConnected && state.connStatus = "mic_error") ? ("Connected - Mic '" cfg.TargetMicName "' Not Found")
        : (state.obsConnected ? ("Connected to " state.activeHost) : "Searching / Disconnected")))
    clickerText := FormatHK(cfg.HwMuteHotkey) (cfg.EnablePointerMute ? "" : " (Disabled)")
    hostText := IsRemoteUsingInternetChannel(cfg, state)
        ? (((state.HasOwnProp("usingRelayFallback") && state.usingRelayFallback) ? "Relay Bridge (" : "Internet (") (cfg.InternetPairingCode != "" ? cfg.InternetPairingCode : "Not Set") ")")
        : (IsRemoteUsingBridgeChannel(cfg, state)
            ? ("Host Bridge (" (cfg.SessionPairingCode != "" ? cfg.SessionPairingCode " @ " : "") state.activeHost ")")
            : ((cfg.HostAddress != "" ? cfg.HostAddress : "(Not Set)") ":" cfg.HostPort))
    scText := "Toggle Mute: " FormatHK(cfg.PptHotkey) "  |  Exit: " FormatHK(cfg.ExitHotkey)
    return "Current Status: " connState "  |  Clicker Key: " clickerText "  |  Host: " hostText "  |  " scText
}

ShowRemoteHelpUI(cfg, state, *) {
    existing := Theme.FocusExistingWindow("RemoteHelpWindow")
    if IsObject(existing) {
        if (IsObject(state) && state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn)
            try state.refreshHelpFn.Call()
        return existing
    }

    helpGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "PresenterSync Remote v" UIConstants.APP_VERSION " - Setup & Help Guide")
    Theme.ApplyToWindow(helpGui)
    Theme.NamedWindows["RemoteHelpWindow"] := helpGui

    ; --- Persistent Top Search Bar ---
    helpGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(helpGui, helpGui.Add("Text", "x14 y15 w84 h22", "Search Help:"), "Text")
    helpGui.SetFont("s9 w400 norm", Theme.UiFont)
    edRemSearch := helpGui.Add("Edit", "x102 y12 w416 h26")
    Theme.RegisterControl(helpGui, edRemSearch, "Edit")
    DllCall("SendMessage", "Ptr", edRemSearch.Hwnd, "UInt", 0x1501, "Ptr", 1, "WStr", "Search Remote HUD, Pointer Controls, Pairing Code, Tray menus...")
    btnRemClear := helpGui.Add("Button", "x526 y12 w68 h26", "Clear")
    Theme.RegisterControl(helpGui, btnRemClear, "Button")
    Theme.RegisterControl(helpGui, helpGui.Add("Text", "x602 y15 w124 h22 Right", "Type to search"), "Text", "muted")

    tabNames := ["Mic HUD Guide", "Setup Guide", "Help Search"]
    helpGui.SetFont("s9 w600 norm", Theme.UiFont)
    tabs := helpGui.Add("Tab2", "x14 y48 w712 h436 +0x0400 -0x0200", tabNames)
    tabs._tabNames := tabNames
    Theme.RegisterControl(helpGui, tabs, "Tab")

    ; --- TAB 1: REMOTE 1-TIER MIC HUD ANATOMY ---
    tabs.UseTab(1)
    helpGui.SetFont("s10 w700 norm", Theme.UiFont)
    Theme.RegisterControl(helpGui, helpGui.Add("Text", "x30 y94 w680 h22", "Interactive Remote 1-Tier Mic HUD Guide - Click any state or callout [1]-[4]:"), "Text", "tabText")
    helpGui.SetFont("s9 w400 norm", Theme.UiFont)

    remAnatomy := GetRemoteHudAnatomyItems()
    selectedRemIdx := 1
    picRemHud := helpGui.Add("Picture", "x30 y120 w680 h194", "HBITMAP:" BuildRemoteHudDiagramBitmap(cfg, selectedRemIdx, 680, 194))

    remBtns := []
    for i, item in remAnatomy {
        bx := 30 + (i - 1) * 172
        bCtrl := helpGui.Add("Button", Format("x{} y322 w164 h28", bx), StrReplace(item.tag, "&", "&&"))
        Theme.RegisterControl(helpGui, bCtrl, "Button", "tabButton")
        remBtns.Push(bCtrl)
    }

    edRemHudDetail := AddHelpGuideEdit(helpGui, 30, 356, 680, 114, "")
    SelectRemHudItem(idx, redraw := true) {
        if (idx < 1 || idx > remAnatomy.Length)
            return
        selectedRemIdx := idx
        it := remAnatomy[idx]
        edRemHudDetail.Value := it.tag "  " it.pillTitle "`r`n"
            . "SUMMARY: " it.summary "`r`n`r`n"
            . "STATES:`r`n" it.states "`r`n`r`n"
            . "HOW TO USE:`r`n" it.actions "`r`n`r`n"
            . "WHERE TO CONFIGURE:`r`n" it.configWhere
        if (redraw && WinExist("ahk_id " helpGui.Hwnd))
            ApplyDiagramBitmap(picRemHud, BuildRemoteHudDiagramBitmap(cfg, selectedRemIdx, 680, 194))
    }
    SelectRemHudItem(selectedRemIdx, false)

    for idx, bCtrl in remBtns {
        localIdx := idx
        bCtrl.OnEvent("Click", ((k, *) => SelectRemHudItem(k, true)).Bind(localIdx))
    }

    OnRemoteDiagramClick(ctrl, *) {
        pt := Buffer(8, 0), rc := Buffer(16, 0)
        DllCall("GetCursorPos", "Ptr", pt)
        DllCall("ScreenToClient", "Ptr", ctrl.Hwnd, "Ptr", pt)
        DllCall("GetClientRect", "Ptr", ctrl.Hwnd, "Ptr", rc)
        cw := Max(1, NumGet(rc, 8, "Int")), ch := Max(1, NumGet(rc, 12, "Int"))
        relX := NumGet(pt, 0, "Int") * (680.0 / cw)
        relY := NumGet(pt, 4, "Int") * (194.0 / ch)
        hitId := HitTestRemoteHudDiagram(relX, relY)
        if (hitId >= 1 && hitId <= 4)
            SelectRemHudItem(hitId, true)
    }
    picRemHud.OnEvent("Click", OnRemoteDiagramClick)

    ; --- TAB 2: SETUP GUIDE & CONNECTION STATUS ---
    tabs.UseTab(2)
    statusCtrl := helpGui.Add("Text", "x30 y94 w680 h36", BuildRemoteHelpStatusLine(cfg, state))
    Theme.RegisterControl(helpGui, statusCtrl, "Text", "tabMuted")

    RefreshRemoteHelp(*) {
        if WinExist("ahk_id " helpGui.Hwnd) {
            statusCtrl.Value := BuildRemoteHelpStatusLine(cfg, state)
            if (helpGui.HasOwnProp("_onThemeRefresh") && helpGui._onThemeRefresh)
                try helpGui._onThemeRefresh.Call()
        }
    }
    if IsObject(state)
        state.refreshHelpFn := RefreshRemoteHelp

    AddHelpGuideEdit(helpGui, 30, 136, 680, 334, GetRemoteSetupGuideText())

    ; --- TAB 3: SEARCHABLE REMOTE TRAY & HELP TOPICS ---
    tabs.UseTab(3)
    helpGui.SetFont("s10 w700 norm", Theme.UiFont)
    Theme.RegisterControl(helpGui, helpGui.Add("Text", "x30 y94 w470 h22", "Remote Tray Menus, LAN/WAN Relay & HUD Reference:"), "Text", "tabText")
    helpGui.SetFont("s9 w400 norm", Theme.UiFont)
    lblRemCount := helpGui.Add("Text", "x510 y94 w200 h22 Right", "")
    Theme.RegisterControl(helpGui, lblRemCount, "Text", "tabMuted")

    ddlRemScope := helpGui.Add("DropDownList", "x30 y122 w230 Choose1", ["All Remote Help", "HUD", "Tray", "Remote", "Features", "Shortcuts"])
    Theme.RegisterControl(helpGui, ddlRemScope, "DropDownList")
    btnQuickConn := helpGui.Add("Button", "x272 y121 w138 h26", "Connection")
    btnQuickPtr := helpGui.Add("Button", "x420 y121 w138 h26", "Mute / Cough")
    btnQuickHud := helpGui.Add("Button", "x568 y121 w142 h26", "HUD Look")
    for bq in [btnQuickConn, btnQuickPtr, btnQuickHud]
        Theme.RegisterControl(helpGui, bq, "Button", "tabButton")

    lbRemItems := helpGui.Add("ListBox", "x30 y156 w270 h314 +0x0100")
    Theme.RegisterControl(helpGui, lbRemItems, "ListBox")
    edRemTopicDetail := AddHelpGuideEdit(helpGui, 312, 156, 398, 314, "")

    remResults := []
    ShowRemSearchSelection(*) {
        idx := lbRemItems.Value
        if (idx >= 1 && idx <= remResults.Length)
            edRemTopicDetail.Value := BuildHelpEntryDetailText(remResults[idx])
        else
            edRemTopicDetail.Value := "No Remote help topics matched '" edRemSearch.Value "'. Clear the filter or try 'remote', 'pairing', 'cough', 'snap', 'dodge', or 'tray'."
    }

    RunRemoteHelpSearch(*) {
        catArg := (ddlRemScope.Text = "All Remote Help") ? "All" : ddlRemScope.Text
        remResults := SearchHelpEntries(edRemSearch.Value, catArg, true)
        lblRemCount.Value := remResults.Length (remResults.Length = 1 ? " match" : " matches")
        PopulateHelpListBox(lbRemItems, remResults, true)
        ShowRemSearchSelection()
    }

    OnRemoteSearchChange(*) {
        if (Trim(edRemSearch.Value) != "" && tabs.Value != 3)
            tabs.Choose(3)
        RunRemoteHelpSearch()
    }
    edRemSearch.OnEvent("Change", OnRemoteSearchChange)
    ddlRemScope.OnEvent("Change", RunRemoteHelpSearch)
    lbRemItems.OnEvent("Change", ShowRemSearchSelection)
    btnRemClear.OnEvent("Click", (*) => (edRemSearch.Value := "", ddlRemScope.Choose(1), RunRemoteHelpSearch()))
    btnQuickConn.OnEvent("Click", (*) => (edRemSearch.Value := "connect", ddlRemScope.Choose(1), RunRemoteHelpSearch()))
    btnQuickPtr.OnEvent("Click", (*) => (edRemSearch.Value := "cough", ddlRemScope.Choose(1), RunRemoteHelpSearch()))
    btnQuickHud.OnEvent("Click", (*) => (edRemSearch.Value := "appearance", ddlRemScope.Choose(1), RunRemoteHelpSearch()))
    RunRemoteHelpSearch()

    tabs.UseTab()

    helpGui._onThemeRefresh := (*) => (
        WinExist("ahk_id " helpGui.Hwnd) ? ApplyDiagramBitmap(picRemHud, BuildRemoteHudDiagramBitmap(cfg, selectedRemIdx, 680, 194)) : 0
    )

    helpGui.SetFont("s9 w400 norm", Theme.UiFont)
    btnConn := helpGui.Add("Button", "x14 y494 w172 h34", "Change Connection...")
    btnKey := helpGui.Add("Button", "x198 y494 w164 h34", "Change Mute Key...")
    btnSc := helpGui.Add("Button", "x374 y494 w174 h34", "Edit App Shortcuts...")
    btnClose := helpGui.Add("Button", "x590 y494 w136 h34 Default", "Close")
    Theme.RegisterControl(helpGui, btnConn, "Button", "accent")
    Theme.RegisterControl(helpGui, btnKey, "Button")
    Theme.RegisterControl(helpGui, btnSc, "Button")
    Theme.RegisterControl(helpGui, btnClose, "Button")

    CloseRemoteHelp(*) {
        if (IsObject(state) && state.HasOwnProp("refreshHelpFn"))
            state.refreshHelpFn := ""
        helpGui._onThemeRefresh := ""
        Theme.UnregisterWindow(helpGui, "RemoteHelpWindow")
        helpGui.Destroy()
    }
    btnConn.OnEvent("Click", (*) => ShowRemoteConnectionUI(cfg, state, false))
    btnKey.OnEvent("Click", (*) => ChangeRemotePointerKeyUI(cfg, state))
    btnSc.OnEvent("Click", (*) => ChangeRemoteAppHotkeysUI(cfg, state))
    btnClose.OnEvent("Click", CloseRemoteHelp)
    helpGui.OnEvent("Close", CloseRemoteHelp)
    helpGui.OnEvent("Escape", CloseRemoteHelp)

    helpGui.Show("w740 h540 Center")
    btnClose.Focus()
    return helpGui
}

ShowRemoteAboutUI(cfg := "", state := "", *) {
    existing := Theme.FocusExistingWindow("AboutRemoteWindow")
    if IsObject(existing)
        return existing

    aboutGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "About PresenterSync Remote")
    aboutGui.MarginX := 18
    aboutGui.MarginY := 16
    Theme.ApplyToWindow(aboutGui)
    Theme.NamedWindows["AboutRemoteWindow"] := aboutGui

    iconSource := A_IsCompiled ? A_ScriptFullPath : (FileExist(A_ScriptDir "\assets\PresenterSyncRemote.ico") ? A_ScriptDir "\assets\PresenterSyncRemote.ico" : A_ScriptDir "\..\assets\PresenterSyncRemote.ico")
    if FileExist(iconSource)
        aboutGui.Add("Picture", "x203 y16 w64 h64", iconSource)

    aboutGui.SetFont("s16 w700 norm", Theme.UiFont)
    Theme.RegisterControl(aboutGui, aboutGui.Add("Text", "x20 y88 w430 h30 Center", "PresenterSync Remote"), "Text")

    aboutGui.SetFont("s10 w700 norm", Theme.UiFont)
    Theme.RegisterControl(aboutGui, aboutGui.Add("Text", "x20 y120 w430 h20 Center", "Version " UIConstants.APP_VERSION "  -  Remote Companion Edition"), "Text", "accent")

    aboutGui.SetFont("s9 w400 norm", Theme.UiFont)
    Theme.RegisterControl(aboutGui, aboutGui.Add("Text", "x20 y142 w430 h20 Center", "Lightweight 1-Tier Mic Companion for Smart Boards & Secondary PCs"), "Text", "muted")

    aboutGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(aboutGui, aboutGui.Add("Text", "x20 y164 w430 h18 Center", "Created by Saabith Jiffry"), "Text")

    aboutGui.SetFont("s9 w700 norm", Theme.UiFont)
    Theme.RegisterControl(aboutGui, aboutGui.Add("Text", "x20 y192 w430 h18", "Included Remote Companion Capabilities & Scope:"), "Text")

    aboutGui.SetFont("s9 w400 norm", Theme.UiFont)
    remCapsText := "Streamlined companion engineered strictly for Smart Boards & secondary PCs.`r`n`r`n"
        . "WHAT REMOTE INCLUDES:`r`n"
        . "• Dedicated 1-Tier LIVE / MUTED Mic HUD: Syncs via OBS WebSocket v5 (Port 4455) OR Mode 2 Host Relay Bridge (Conferencing-Only setup).`r`n"
        . "• Host Deck Control (Bridge): Remote Scene switching, Standby / `"BRB`" Curtain, Host Recording controls, Countdown Timer & Stage Nudge.`r`n"
        . "• Zero-Config LAN & WAN Discovery: Scan Classroom LAN (UDP :4457 + mDNS failover) or Internet Pairing Code PS-XXXX-XXXX with safe heartbeat.`r`n"
        . "• Clicker & Mic Modes: Assign mute button, Cough Hold (Push-to-Mute >= 350ms), Push-to-Talk (hold to unmute), Clicker Tester & Ctrl+F12.`r`n"
        . "• Large-Board Visuals & Themes: 0.25x-5.0x scale, Dark/Light/System theme, 5 palettes + Custom Hex colors, monochrome icons, pulse & toast.`r`n"
        . "• Smart Ergonomics & System: 14px Magnetic Snap, Auto-Dodge hover ghost, Click-Through (hold Alt), Startup (OFF by default) & SHA-256 Updates.`r`n`r`n"
        . "STREAMLINED BY DESIGN (HOST-ONLY MODULES OMITTED):`r`n"
        . "• Omits multi-tier overlay panels, secondary desktop pills, CoreAudio voice bar, UIA meeting monitoring, Control Center, Setup Wizard, and PowerPoint forwarding."
    AddHelpGuideEdit(aboutGui, 20, 214, 430, 214, remCapsText)

    aboutGui.SetFont("s9 w400 norm", Theme.UiFont)
    gitBtn := aboutGui.Add("Button", "x20 y440 w208 h30", "GitHub Repo")
    Theme.RegisterControl(aboutGui, gitBtn, "Button")
    gitBtn.OnEvent("Click", (*) => Run("https://github.com/SaabithJiffry/PresenterSync/"))

    updBtn := aboutGui.Add("Button", "x242 y440 w208 h30", "Check for Updates")
    Theme.RegisterControl(aboutGui, updBtn, "Button")
    updBtn.OnEvent("Click", (*) => CheckForUpdates(UIConstants.APP_VERSION, "", false, "PresenterSync_Remote.exe", cfg))

    helpBtn := aboutGui.Add("Button", "x20 y478 w208 h30", "Open Help Guide")
    Theme.RegisterControl(aboutGui, helpBtn, "Button")
    CloseAbout(*) {
        Theme.UnregisterWindow(aboutGui, "AboutRemoteWindow")
        aboutGui.Destroy()
    }
    if IsObject(cfg)
        helpBtn.OnEvent("Click", (*) => (CloseAbout(), ShowRemoteHelpUI(cfg, state)))
    else
        helpBtn.Enabled := false

    closeBtn := aboutGui.Add("Button", "x242 y478 w208 h30 Default", "Close")
    Theme.RegisterControl(aboutGui, closeBtn, "Button")
    closeBtn.OnEvent("Click", CloseAbout)
    aboutGui.OnEvent("Close", CloseAbout)
    aboutGui.OnEvent("Escape", CloseAbout)

    aboutGui.Show("w470 h524 Center")
    closeBtn.Focus()
    return aboutGui
}

ShowRemoteConnectionUI(cfg, state, isInitialBoot := false) {
    existing := Theme.FocusExistingWindow("OBS Remote Connection")
    if IsObject(existing)
        return existing

    Theme.AcquireSuspend()

    dlg := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "OBS Remote Connection")
    dlg._closed := false
    dlg._testSeq := 0
    dlg._testWs := ""
    dlg._testTimer := ""
    dlg.MarginX := 20
    dlg.MarginY := 16
    Theme.ApplyToWindow(dlg)
    Theme.NamedWindows["OBS Remote Connection"] := dlg

    dlg.SetFont("s10 w600", Theme.UiFont)
    Theme.RegisterControl(dlg, dlg.Add("Text", "xm w360", "Connect to Primary Streaming Host"), "Text")
    dlg.SetFont("s9 w400", Theme.UiFont)
    Theme.RegisterControl(dlg, dlg.Add("Text", "xm w360 y+4", "Choose Same Router (LAN) or Different Networks (Over the Internet):"), "Text", "muted")

    dlg.SetFont("s9 w600", Theme.UiFont)
    Theme.RegisterControl(dlg, dlg.Add("Text", "xm w360 y+10", "Network Mode:"), "Text")
    dlg.SetFont("s9 w400", Theme.UiFont)
    netChoice := (cfg.NetworkMode = "Internet") ? 2 : 1
    ddlNetMode := dlg.Add("DropDownList", "xm w360 Choose" netChoice, [
        "1: Same Router / Local Wi-Fi or Ethernet (LAN - Default)",
        "2: Different Networks / Over the Internet (WAN Relay)"
    ])
    Theme.RegisterControl(dlg, ddlNetMode, "DropDownList")

    dlg.SetFont("s9 w600", Theme.UiFont)
    lblSession := dlg.Add("Text", "xm w360 y+10", "Host Bridge Session Code (Multi-Remote / Auto-Find):")
    Theme.RegisterControl(dlg, lblSession, "Text")
    dlg.SetFont("s9 w400", Theme.UiFont)
    editSession := dlg.Add("Edit", "xm w170", cfg.SessionPairingCode)
    Theme.RegisterControl(dlg, editSession, "Edit")
    DllCall("SendMessage", "Ptr", editSession.Hwnd, "UInt", 0x1501, "Ptr", 1, "WStr", "e.g. K7M-9P2")
    editBridgePort := dlg.Add("Edit", "x+8 yp w54", cfg.BridgePort)
    Theme.RegisterControl(dlg, editBridgePort, "Edit")
    btnPairCode := dlg.Add("Button", "x+8 yp w120 h24", "Pair by Code")
    Theme.RegisterControl(dlg, btnPairCode, "Button")
    dlg._pairedToken := cfg.SessionToken
    dlg._pairedCode := cfg.SessionPairingCode
    dlg._pairedHostUuid := cfg.HasOwnProp("PairedHostUuid") ? cfg.PairedHostUuid : ""

    dlg.SetFont("s9 w600", Theme.UiFont)
    lblPair := dlg.Add("Text", "xm w360 y+10", "Internet Pairing Code (Optional Fallback / WAN):")
    Theme.RegisterControl(dlg, lblPair, "Text")
    dlg.SetFont("s9 w400", Theme.UiFont)
    editPair := dlg.Add("Edit", "xm w360", cfg.InternetPairingCode)
    Theme.RegisterControl(dlg, editPair, "Edit")

    dlg.SetFont("s9 w600", Theme.UiFont)
    lblHost := dlg.Add("Text", "xm w360 y+8", "LAN Host Address (e.g. STUDIO-PC.local, 192.168.1.50):")
    Theme.RegisterControl(dlg, lblHost, "Text")
    dlg.SetFont("s9 w400", Theme.UiFont)
    editHost := dlg.Add("Edit", "xm w270", cfg.HostAddress)
    Theme.RegisterControl(dlg, editHost, "Edit")
    btnScanLan := dlg.Add("Button", "x+8 yp w82 h24", "Scan LAN")
    Theme.RegisterControl(dlg, btnScanLan, "Button")

    lblPort := dlg.Add("Text", "xm w360 y+8", "OBS WebSocket Port:")
    Theme.RegisterControl(dlg, lblPort, "Text")
    editPort := dlg.Add("Edit", "xm w360", cfg.HostPort)
    Theme.RegisterControl(dlg, editPort, "Edit")

    Theme.RegisterControl(dlg, dlg.Add("Text", "xm w360 y+8", "OBS WebSocket Password (Optional):"), "Text")
    editPw := dlg.Add("Edit", "xm w360 Password", cfg.ObsPassword)
    Theme.RegisterControl(dlg, editPw, "Edit")

    Theme.RegisterControl(dlg, dlg.Add("Text", "xm w360 y+8", "Exact Audio Source Name:"), "Text")
    editMic := dlg.Add("Edit", "xm w360", cfg.TargetMicName)
    Theme.RegisterControl(dlg, editMic, "Edit")

    UpdateModeFields(*) {
        isInternet := (ddlNetMode.Value == 2)
        lblSession.Enabled := !isInternet
        editSession.Enabled := !isInternet
        editBridgePort.Enabled := !isInternet
        btnPairCode.Enabled := !isInternet
        lblPair.Enabled := true
        editPair.Enabled := true
        lblHost.Enabled := !isInternet
        editHost.Enabled := !isInternet
        btnScanLan.Enabled := !isInternet
        lblPort.Enabled := !isInternet
        editPort.Enabled := !isInternet
    }
    ddlNetMode.OnEvent("Change", UpdateModeFields)
    UpdateModeFields()

    statusTxt := dlg.Add("Text", "xm w360 y+10 Center", "Status: Ready to pair, test, or connect")
    Theme.RegisterControl(dlg, statusTxt, "Text", "muted")

    ApplyPairResultToDialog(pairRes) {
        if (pairRes.HasOwnProp("hostsCsv") && pairRes.hostsCsv != "")
            editHost.Value := pairRes.hostsCsv
        editBridgePort.Value := pairRes.bridgePort
        if (pairRes.obsPort != "")
            editPort.Value := pairRes.obsPort
        if (pairRes.obsPassword != "")
            editPw.Value := pairRes.obsPassword
        if (pairRes.targetMicName != "")
            editMic.Value := pairRes.targetMicName
        if (pairRes.internetPairingCode != "")
            editPair.Value := pairRes.internetPairingCode
        editSession.Value := pairRes.sessionCode
        dlg._pairedToken := pairRes.sessionToken
        dlg._pairedCode := pairRes.sessionCode
        if (pairRes.HasOwnProp("hostUuid") && pairRes.hostUuid != "")
            dlg._pairedHostUuid := pairRes.hostUuid
    }

    ApplyDiscoveredBeacon(b) {
        editHost.Value := b.senderIp
        editBridgePort.Value := b.bridgePort
        editPort.Value := b.obsPort
        dlg._pairedHostUuid := b.hostUuid
        ddlNetMode.Choose(1)
        UpdateModeFields()
        statusTxt.Value := "✓ Selected " b.deviceName " • :" b.bridgePort " (" b.senderIp ")"
    }

    ScanClassroomAction(*) {
        btnScanLan.Enabled := false
        statusTxt.Value := "Scanning classroom LAN (:4457)..."
        beacons := DiscoverPublicHostsUdp(4457, 650)
        btnScanLan.Enabled := true
        if (beacons.Length == 0) {
            statusTxt.Value := "No classroom hosts found on LAN (:4457). Enter IP or Pair by Code."
            return
        }
        if (beacons.Length == 1) {
            ApplyDiscoveredBeacon(beacons[1])
            return
        }
        pickMenu := Menu()
        for _, b in beacons {
            picked := b
            pickMenu.Add(picked.deviceName " • :" picked.bridgePort " (" picked.senderIp ")", ((item, *) => ApplyDiscoveredBeacon(item)).Bind(picked))
        }
        pickMenu.Show()
        statusTxt.Value := "Found " beacons.Length " host(s) on classroom LAN"
    }
    btnScanLan.OnEvent("Click", ScanClassroomAction)

    PairByCodeAction(*) {
        bpIn := Trim(editBridgePort.Value)
        if (!IsInteger(bpIn) || Integer(bpIn) < 1 || Integer(bpIn) > 65535)
            bpIn := "4456"
        btnPairCode.Enabled := false
        statusTxt.Value := "Discovering Primary Host & pairing..."
        pairRes := PairRemoteWithHostBridge(Trim(editHost.Value), bpIn, Trim(editSession.Value), cfg.DeviceId, GetRemoteDisplayDeviceName(cfg))
        btnPairCode.Enabled := true
        if (!pairRes.ok) {
            statusTxt.Value := "✕ " pairRes.error
            return
        }
        ApplyPairResultToDialog(pairRes)
        ddlNetMode.Choose(1)
        UpdateModeFields()
        statusTxt.Value := "✓ Paired to " (pairRes.hostName != "" ? pairRes.hostName : pairRes.host) " (" pairRes.host ":" pairRes.bridgePort ")!"
    }
    btnPairCode.OnEvent("Click", PairByCodeAction)

    btnTest := dlg.Add("Button", "xm w230 h30 y+8", "Test Connection")
    btnGuide := dlg.Add("Button", "x+10 yp w120 h30", "Setup Guide")
    Theme.RegisterControl(dlg, btnTest, "Button")
    Theme.RegisterControl(dlg, btnGuide, "Button")

    btnTest.OnEvent("Click", (*) => TestConnectionAction(dlg, btnTest, editHost.Value, editPort.Value, editPw.Value, statusTxt, (ddlNetMode.Value == 2 ? "Internet" : "LAN"), editPair.Value))
    btnGuide.OnEvent("Click", (*) => ShowRemoteHelpUI(cfg, state))

    btnSave := dlg.Add("Button", "xm w360 h32 y+12 Default", isInitialBoot ? "Connect & Start" : "Save & Reconnect")
    Theme.RegisterControl(dlg, btnSave, "Button", "accent")

    CleanupDialog(exitIfInitial := false, *) {
        if (dlg._closed)
            return
        dlg._closed := true
        dlg._testSeq += 1
        if IsObject(dlg._testTimer) {
            SetTimer dlg._testTimer, 0
            dlg._testTimer := ""
        }
        if IsObject(dlg._testWs) {
            SafeCloseWebSocketDeferred(dlg._testWs)
            dlg._testWs := ""
        }
        Theme.UnregisterWindow(dlg, "OBS Remote Connection")
        Theme.ReleaseSuspend()
        dlg.Destroy()
        if (exitIfInitial)
            ExitApp()
    }

    SaveAndConnect(*) {
        selMode := (ddlNetMode.Value == 2) ? "Internet" : "LAN"
        sessVal := Trim(editSession.Value)
        bpVal := Trim(editBridgePort.Value)
        if (!IsInteger(bpVal) || Integer(bpVal) < 1 || Integer(bpVal) > 65535)
            bpVal := "4456"
        pairVal := Trim(editPair.Value)
        h := Trim(editHost.Value)
        p := Trim(editPort.Value)
        m := Trim(editMic.Value)

        if (m = "") {
            dlg.Opt("+OwnDialogs")
            MsgBox("Exact Audio Source Name cannot be empty.", "Error", "Icon!")
            return
        }
        if (selMode = "Internet") {
            if (pairVal = "") {
                dlg.Opt("+OwnDialogs")
                MsgBox("Please enter the Internet Pairing Code from your Primary Host (Settings -> Remote Companion Info).", "Error", "Icon!")
                return
            }
            if (h = "")
                h := "127.0.0.1"
            if (!IsInteger(p) || Integer(p) < 1 || Integer(p) > 65535)
                p := "4455"
        } else {
            if (sessVal != "" && (h = "" || NormalizePairingCode(sessVal) != NormalizePairingCode(dlg._pairedCode) || dlg._pairedToken = "")) {
                statusTxt.Value := "Pairing with Primary Host (" sessVal ")..."
                autoPair := PairRemoteWithHostBridge(h, bpVal, sessVal, cfg.DeviceId, GetRemoteDisplayDeviceName(cfg))
                if (autoPair.ok) {
                    ApplyPairResultToDialog(autoPair)
                    h := Trim(editHost.Value)
                    bpVal := Trim(editBridgePort.Value)
                    p := Trim(editPort.Value)
                    m := Trim(editMic.Value)
                    pairVal := Trim(editPair.Value)
                    sessVal := Trim(editSession.Value)
                } else if (h = "") {
                    dlg.Opt("+OwnDialogs")
                    MsgBox("Session Code pairing failed: " autoPair.error "`n`nVerify the code from Primary Host -> Remote Companion Info, or enter a LAN Host Address.", "Pairing Failed", "Icon!")
                    return
                }
            }
            if (h = "" || p = "") {
                dlg.Opt("+OwnDialogs")
                MsgBox("Please enter a Host Bridge Session Code or LAN Host Address.", "Error", "Icon!")
                return
            }
            if (!IsInteger(p) || Integer(p) < 1 || Integer(p) > 65535) {
                dlg.Opt("+OwnDialogs")
                MsgBox("OBS WebSocket Port must be a number between 1 and 65535.", "Error", "Icon!")
                return
            }
        }

        cfg.NetworkMode := selMode
        cfg.SessionPairingCode := sessVal
        cfg.BridgePort := String(Integer(bpVal))
        cfg.SessionToken := (sessVal = "") ? "" : ((NormalizePairingCode(sessVal) = NormalizePairingCode(dlg._pairedCode)) ? dlg._pairedToken : "")
        cfg.PairedHostUuid := dlg._pairedHostUuid
        cfg.InternetPairingCode := pairVal
        cfg.HostAddress := h
        cfg.HostPort := String(Integer(p))
        cfg.ObsPassword := editPw.Value
        cfg.TargetMicName := m
        cfg.FirstRun := false

        SaveRemoteConnectionSettingsToIni(cfg)

        CleanupDialog(false)

        ; Disconnect existing and trigger fresh failover connection
        SetTimer state.reconnectTimerFn, 0
        SetTimer state.heartbeatTimerFn, 0
        CancelRemotePongWatchdog(state)
        CancelRemoteBridgeHandshakeWatchdog(state)
        if (state.HasOwnProp("recTickFn") && IsObject(state.recTickFn))
            SetTimer state.recTickFn, 0
        SetTimer state.breathTimerFn, 0
        state.animSeq += 1
        state.connGen += 1
        if IsObject(state.obsWs) {
            oldWs := state.obsWs
            state.obsWs := ""
            oldWs._psClosed := true
            try oldWs.shutdown()
        }
        state.obsConnected := false
        state.usingBridge := false
        state.usingDirectObsFallback := false
        state.connStatus := "searching"
        state.activeHost := ""
        state.candidateIndex := 1
        state.usingRelayFallback := false
        state.candidates := []
        if (IsObject(state.MicGui)) {
            state.currentAlpha := GetRemoteEffectiveAlpha(state)
            ApplyMicAppearance(cfg, state)
        }
        state.NotifyTrayStatus()
        SetTimer state.reconnectTimerFn, -20
    }

    btnSave.OnEvent("Click", SaveAndConnect)

    dlg.OnEvent("Close", (*) => CleanupDialog(isInitialBoot))
    dlg.OnEvent("Escape", (*) => CleanupDialog(isInitialBoot))

    dlg.Show("AutoSize Center")
    return dlg
}

TestConnectionAction(dlg, btnTest, hostStr, portStr, pwStr, statusLabel, netMode := "LAN", pairingCode := "") {
    if (dlg._closed || !WinExist("ahk_id " dlg.Hwnd))
        return

    dlg._testSeq += 1
    mySeq := dlg._testSeq
    if IsObject(dlg._testTimer) {
        SetTimer dlg._testTimer, 0
        dlg._testTimer := ""
    }
    if IsObject(dlg._testWs) {
        SafeCloseWebSocketDeferred(dlg._testWs)
        dlg._testWs := ""
    }

    IsCancelled() {
        return dlg._closed || dlg._testSeq != mySeq || !WinExist("ahk_id " dlg.Hwnd)
    }

    ClearProbeTimer() {
        if IsObject(dlg._testTimer) {
            SetTimer dlg._testTimer, 0
            dlg._testTimer := ""
        }
    }

    FinishTest(msg) {
        ClearProbeTimer()
        if IsObject(dlg._testWs) {
            SafeCloseWebSocketDeferred(dlg._testWs)
            dlg._testWs := ""
        }
        if (IsCancelled())
            return
        statusLabel.Value := msg
        btnTest.Enabled := true
    }

    if (StrLower(Trim(netMode)) = "internet") {
        pairClean := Trim(pairingCode)
        if (pairClean = "") {
            statusLabel.Value := "Error: Please enter your Internet Pairing Code."
            return
        }
        btnTest.Enabled := false
        statusLabel.Value := "Testing Internet Relay (" pairClean ")..."
        topic := GetInternetRelayTopic(pairClean)
        wsUrl := "wss://ntfy.sh/" topic "/ws"
        expectedTok := GetInternetRelayAuthToken(pairClean, pwStr)

        OnRelayTimeout() {
            FinishTest("✓ Connected to Internet Relay (" pairClean ") - Waiting for Host response")
        }

        OnRelayTestMsg(ws, raw) {
            if (IsCancelled() || (IsObject(dlg._testWs) && ws != dlg._testWs)) {
                SafeCloseWebSocketDeferred(ws)
                return
            }
            msg := (Type(raw) == "Buffer") ? StrGet(raw, "UTF-8") : String(raw)
            pkt := ParseRelayPacket(msg)
            if IsObject(pkt) && pkt.src = "host" {
                if (pkt.cmd = "auth_error" || pkt.auth != expectedTok) {
                    FinishTest("✕ Auth failed on Internet Relay (Check OBS Password)")
                } else if (pkt.cmd = "state") {
                    FinishTest("✓ Connected to Primary Host via Internet Relay (" pairClean ")!")
                }
            }
        }

        OnRelayTestClose(ws, st, re) {
            if (IsCancelled() || (IsObject(dlg._testWs) && ws != dlg._testWs))
                return
            FinishTest("✕ Internet Relay connection closed (Check internet access)")
        }

        try {
            dlg._testTimer := OnRelayTimeout
            SetTimer dlg._testTimer, -2500
            dlg._testWs := WebSocket(wsUrl, {
                message: OnRelayTestMsg,
                close: OnRelayTestClose
            }, true, "", 3000)
            PublishInternetRelayPacket(topic, FormatRelayPacket("remote", "sync_req", "0", expectedTok))
        } catch {
            FinishTest("✕ Could not reach Internet Relay (Check internet / HTTPS firewall)")
        }
        return
    }

    portClean := Trim(portStr)
    if (!IsInteger(portClean) || Integer(portClean) < 1 || Integer(portClean) > 65535) {
        statusLabel.Value := "Error: Port must be between 1 and 65535."
        return
    }

    if (Trim(hostStr) = "") {
        statusLabel.Value := "Error: No valid host address provided."
        return
    }

    endpoints := ParseCandidateEndpoints(hostStr, portClean)
    if (endpoints.Length == 0) {
        statusLabel.Value := "Error: No valid host address provided."
        return
    }

    currentIndex := 1
    testSuccess := false
    btnTest.Enabled := false

    TryNextCandidate() {
        ClearProbeTimer()
        if (IsCancelled() || testSuccess)
            return
        if (currentIndex > endpoints.Length) {
            FinishTest("✕ All " endpoints.Length " candidate(s) unreachable (Check IP, Port & Firewall)")
            return
        }

        target := endpoints[currentIndex]
        statusLabel.Value := "Testing " target.raw " (" currentIndex "/" endpoints.Length ")..."
        SetTimer RunCurrentProbe, -15

        OnCandidateTimeout() {
            if (IsCancelled() || testSuccess)
                return
            if IsObject(dlg._testWs) {
                SafeCloseWebSocketDeferred(dlg._testWs)
                dlg._testWs := ""
            }
            currentIndex += 1
            TryNextCandidate()
        }

        RunCurrentProbe() {
            if (IsCancelled() || testSuccess)
                return
            probeWs := ""

            OnTestMsg(ws, raw) {
                if (IsCancelled() || (IsObject(dlg._testWs) && ws != dlg._testWs)) {
                    SafeCloseWebSocketDeferred(ws)
                    return
                }
                msg := (Type(raw) == "Buffer") ? StrGet(raw, "UTF-8") : String(raw)
                if RegExMatch(msg, '"op"\s*:\s*0') {
                    authStr := ""
                    if (RegExMatch(msg, '"salt"\s*:\s*"([^"]+)"', &mSalt) && RegExMatch(msg, '"challenge"\s*:\s*"([^"]+)"', &mChal)) {
                        secret := HashSHA256_Base64(pwStr . mSalt[1])
                        authResponse := HashSHA256_Base64(secret . mChal[1])
                        authStr := ',"authentication":"' authResponse '"'
                    }
                    TrySendWsText(ws, '{"op":1,"d":{"rpcVersion":1,"eventSubscriptions":0' authStr '}}')
                } else if RegExMatch(msg, '"op"\s*:\s*2') {
                    testSuccess := true
                    FinishTest("✓ Connected to " target.raw " (" currentIndex "/" endpoints.Length ")!")
                }
            }

            OnTestClose(ws, st, re) {
                if (IsCancelled() || testSuccess || (IsObject(dlg._testWs) && ws != dlg._testWs))
                    return
                ClearProbeTimer()
                if IsObject(dlg._testWs) {
                    SafeCloseWebSocketDeferred(dlg._testWs)
                    dlg._testWs := ""
                }
                if (st == 4009) {
                    FinishTest("✕ Auth failed on " target.raw " (Wrong OBS password)")
                    return
                }
                currentIndex += 1
                TryNextCandidate()
            }

            if ((!target.HasOwnProp("url") || target.url = "") && target.HasOwnProp("host") && target.HasOwnProp("port")
                && IsLoopbackHost(target.host) && !IsLocalTcpPortListening(target.port)) {
                currentIndex += 1
                TryNextCandidate()
                return
            }

            try {
                dlg._testTimer := OnCandidateTimeout
                SetTimer dlg._testTimer, -3000
                wsProbeUrl := (target.HasOwnProp("url") && target.url != "") ? target.url : ("ws://" target.host ":" target.port)
                probeWs := WebSocket(wsProbeUrl, {
                    message: OnTestMsg,
                    close: OnTestClose
                }, true, "", 2000)
                dlg._testWs := probeWs
            } catch {
                ClearProbeTimer()
                dlg._testWs := ""
                if (IsCancelled())
                    return
                currentIndex += 1
                TryNextCandidate()
            }
        }
    }

    TryNextCandidate()
}
