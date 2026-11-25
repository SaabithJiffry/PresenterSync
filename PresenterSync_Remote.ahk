; ==============================================================================
; Script: PresenterSync_Remote
; Description: Standalone companion client for Smart Boards & secondary devices.
;              Provides a single-pill remote mute HUD and transmits clicker
;              mute keystrokes back to OBS Studio over the local network.
; Version: 9.4.0
; Author: Saabith Jiffry
; License: MIT
; ==============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Off
#MaxThreadsPerHotkey 3
;@Ahk2Exe-SetMainIcon assets\PresenterSyncRemote.ico
;@Ahk2Exe-SetProductName PresenterSync Remote
;@Ahk2Exe-SetDescription PresenterSync Remote - Smart Board Companion Client
;@Ahk2Exe-SetVersion 9.4.0.0
ProcessSetPriority "High"

#Include <WebSocket>
#Include <Crypto>
#Include <RemoteBridgeClient>
#Include <Gdip>
#Include <OBS_Network>
#Include <GUI_Config>
#Include <HudSnakeGame>
#Include <HudArcadeBase>
#Include <ArcadeVault>
#Include <Arcade\GameAsteroids>
#Include <Arcade\GamePaddlePack>
#Include <Arcade\GameClickerFlappy>
#Include <Arcade\GameGridMazePack>
#Include <Arcade\GameMissileDefense>
#Include <Arcade\GameBlockDrop>
#Include <Arcade\GameSpacePinball>

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
ShutdownRemoteApp(*) {
    global AppState, AppConfig, g_RemoteMutex
    if (IsSet(AppState) && IsObject(AppState)) {
        if (AppState.HasOwnProp("wtsMsgGui") && IsObject(AppState.wtsMsgGui)) {
            try DllCall("Wtsapi32\WTSUnRegisterSessionNotification", "Ptr", AppState.wtsMsgGui.Hwnd)
            try AppState.wtsMsgGui.Destroy()
            AppState.wtsMsgGui := ""
        }
        try AppState.StopAllTimers()
        try CloseRemoteWebSocket(AppState, false)
    }
    if (IsSet(HideStageNudgeBanner))
        try HideStageNudgeBanner()
    if (IsSet(AppConfig) && IsObject(AppConfig) && AppConfig.HasMethod("FlushDeferredWrites"))
        try AppConfig.FlushDeferredWrites()
    try HudArcadeBase.StopActiveGame()
    try ReleaseRemoteInstanceMutex(g_RemoteMutex)
    try Theme.Shutdown()
    try Gdip.Shutdown()
}

RegisterSelfUpdateBeforeRelaunch(ShutdownRemoteApp)
OnExit(ShutdownRemoteApp)

if (!A_IsCompiled && FileExist(A_ScriptDir "\assets\PresenterSyncRemote.ico"))
    try TraySetIcon(A_ScriptDir "\assets\PresenterSyncRemote.ico")
A_IconTip := "PresenterSync Remote v" UIConstants.APP_VERSION (g_RemoteCli.instanceName != "" ? " [" g_RemoteCli.instanceName "]" : "")

; === CONFIGURATION & STATE ===
class RemoteConfig {
    ConfigFile := ""
    NetworkMode := "LAN"
    EnableRelayFallback := true
    InternetPairingCode := ""
    RelayBaseUrl := "https://ntfy.sh"
    QuickNudgePresets := "2 min left|Wrap up|Check Mic|Q&A"
    EnableRelayEncryption := true
    AllowLegacyPlaintextRelay := false
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
    LockHudPosition := false
    EnableIdleAutoDim := false
    ShowPillMiniBadges := true
    ExcludeFromCapture := true
    HudVisibilityMode := "Always"
    ConfirmBeforeStopRecording := true
    OpacityLevel := 220
    IndicatorScale := 1.0
    FirstRun := true
    IsMuted := false
    StartWithWindows := false
    AutoCheckUpdates := true
    LastUpdateCheckEpoch := 0
    SkippedUpdateVersion := ""
    RemoteNextSlideKey := ""
    RemotePrevSlideKey := ""
    RemoteTransitionKey := ""

    savedX := "Default"
    savedY := "Default"
    savedXRatio := ""
    savedYRatio := ""
    _deferredWrites := Map()
    _deferredWriteTimerFn := ""

    __New(filePath := "") {
        global g_RemoteCli
        dataDir := IsSet(ConfigStore) ? ConfigStore.ResolveDataDir(A_ScriptDir) : A_ScriptDir
        if (filePath != "")
            this.ConfigFile := filePath
        else if (IsObject(g_RemoteCli) && g_RemoteCli.configPath != "")
            this.ConfigFile := g_RemoteCli.configPath
        else if (IsObject(g_RemoteCli) && g_RemoteCli.instanceName != "")
            this.ConfigFile := dataDir "\PresenterSync_Remote_" SanitizeInstanceFileSlug(g_RemoteCli.instanceName) ".ini"
        else
            this.ConfigFile := dataDir "\PresenterSync_Remote.ini"
        if (IsSet(ConfigStore))
            ConfigStore.EnsureParentDir(this.ConfigFile)
        this.Load()
    }

    Read(section, key, defaultVal := "") {
        k := section "`n" key
        if (this._deferredWrites.Has(k))
            raw := String(this._deferredWrites[k].val)
        else
            raw := IniRead(this.ConfigFile, section, key, defaultVal)
        if (IsSet(ConfigStore) && ConfigStore.IsSecretKey(section, key))
            return ConfigStore.UnprotectSecret(raw, section "." key)
        return raw
    }

    Write(section, key, val) {
        k := section "`n" key
        if (this._deferredWrites.Has(k))
            this._deferredWrites.Delete(k)
        writeVal := val
        if (IsSet(ConfigStore)) {
            ConfigStore.EnsureParentDir(this.ConfigFile)
            if (ConfigStore.IsSecretKey(section, key))
                writeVal := ConfigStore.ProtectSecret(val)
        }
        IniWrite(writeVal, this.ConfigFile, section, key)
        this._BackupDeferred(false)
    }

    _BackupDeferred(force := false) {
        static lastBak := 0
        if (!IsSet(ConfigStore))
            return false
        now := A_TickCount
        if (!force && lastBak != 0 && (now - lastBak) < 5000)
            return false
        if (ConfigStore.BackupIniFile(this.ConfigFile)) {
            lastBak := now
            return true
        }
        return false
    }

    ReadBool(section, key, defaultValue := 0) {
        k := section "`n" key
        value := this._deferredWrites.Has(k) ? this._deferredWrites[k].val : IniRead(this.ConfigFile, section, key, defaultValue)
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
        value := this.Read(section, key, defaultValue)
        try return Integer(value)
        catch
            return defaultValue
    }

    ReadFloat(section, key, defaultValue := 1.0) {
        value := this.Read(section, key, defaultValue)
        try return Float(value)
        catch
            return defaultValue
    }

    WriteBool(section, key, value) {
        k := section "`n" key
        if (this._deferredWrites.Has(k))
            this._deferredWrites.Delete(k)
        if (IsSet(ConfigStore))
            ConfigStore.EnsureParentDir(this.ConfigFile)
        IniWrite(value ? 1 : 0, this.ConfigFile, section, key)
        this._BackupDeferred(false)
    }

    WriteBoolDeferred(section, key, value, delayMs := 250) {
        k := section "`n" key
        this._deferredWrites[k] := { sec: section, key: key, val: (value ? 1 : 0) }
        if (!IsObject(this._deferredWriteTimerFn))
            this._deferredWriteTimerFn := ObjBindMethod(this, "FlushDeferredWrites")
        SetTimer(this._deferredWriteTimerFn, -Max(1, Integer(delayMs)))
    }

    FlushDeferredWrites() {
        if (IsObject(this._deferredWriteTimerFn))
            try SetTimer(this._deferredWriteTimerFn, 0)
        if (this._deferredWrites.Count == 0)
            return 0
        pending := this._deferredWrites
        this._deferredWrites := Map()
        if (IsSet(ConfigStore))
            ConfigStore.EnsureParentDir(this.ConfigFile)
        written := 0
        for _, entry in pending {
            try {
                wVal := (IsSet(ConfigStore) && ConfigStore.IsSecretKey(entry.sec, entry.key)) ? ConfigStore.ProtectSecret(entry.val) : entry.val
                IniWrite(wVal, this.ConfigFile, entry.sec, entry.key)
                written += 1
            }
        }
        if (written > 0)
            this._BackupDeferred(false)
        return written
    }

    Load() {
        global g_RemoteCli
        if (IsSet(ConfigStore)) {
            ConfigStore.RecoverIniFromBackup(this.ConfigFile)
            ConfigStore.MigrateIniSchema(this.ConfigFile, "Connection")
        }
        rawNetMode := StrLower(Trim(this.Read("Connection", "NetworkMode", "LAN")))
        this.NetworkMode := (rawNetMode = "internet") ? "Internet" : "LAN"
        this.EnableRelayFallback := this.ReadBool("Connection", "EnableRelayFallback", 1)
        this.InternetPairingCode := Trim(this.Read("Connection", "InternetPairingCode", ""))
        this.RelayBaseUrl := NormalizeRelayBaseUrl(this.Read("Connection", "RelayBaseUrl", "https://ntfy.sh"))
        this.EnableRelayEncryption := this.ReadBool("Connection", "EnableRelayEncryption", 1)
        this.AllowLegacyPlaintextRelay := this.ReadBool("Connection", "AllowLegacyPlaintextRelay", 0)
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
        this.RemoteNextSlideKey := this.Read("Shortcuts", "RemoteNextSlideKey", "")
        this.RemotePrevSlideKey := this.Read("Shortcuts", "RemotePrevSlideKey", "")
        this.RemoteTransitionKey := this.Read("Shortcuts", "RemoteTransitionKey", "")

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
        this.LockHudPosition := this.ReadBool("Appearance", "LockHudPosition", 0)
        this.EnableIdleAutoDim := this.ReadBool("Appearance", "EnableIdleAutoDim", 0)
        this.ShowPillMiniBadges := this.ReadBool("Appearance", "ShowPillMiniBadges", 1)
        this.ExcludeFromCapture := this.ReadBool("Appearance", "ExcludeFromCapture", 1)
        this.HudVisibilityMode := NormalizeHudVisibilityMode(this.Read("Appearance", "HudVisibilityMode", "Always"))
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
        this.savedXRatio := this.Read("Position", "XRatio", "")
        this.savedYRatio := this.Read("Position", "YRatio", "")
        if (IsSet(ConfigStore) && FileExist(this.ConfigFile)) {
            if (Trim(IniRead(this.ConfigFile, "ConfigMeta", "SchemaVersion", "")) = "")
                try IniWrite(ConfigStore.CURRENT_SCHEMA_VERSION, this.ConfigFile, "ConfigMeta", "SchemaVersion")
        }
        this._BackupDeferred(true)
    }

    ResetPosition() {
        this.savedX := "Default"
        this.savedY := "Default"
        this.savedXRatio := ""
        this.savedYRatio := ""
        this.Write("Position", "X", "Default")
        this.Write("Position", "Y", "Default")
        this.Write("Position", "XRatio", "")
        this.Write("Position", "YRatio", "")
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
        this.LockHudPosition := false
        this.EnableIdleAutoDim := false
        this.ShowPillMiniBadges := true
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
        this.WriteBool("Appearance", "LockHudPosition", false)
        this.WriteBool("Appearance", "EnableIdleAutoDim", false)
        this.WriteBool("Appearance", "ShowPillMiniBadges", true)
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
    relayReplayGuard := ""
    _relayOutSeq := 0
    _relaySessionId := ""
    _relayPeerLegacy := false
    hostBootId := ""
    lastStateSeq := 0

    isMuted := false
    micHoldProgress := 0.0
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
    quickNudges := []
    isStandby := false
    standbyScene := "BRB"
    standbySnapshot := ""
    timerState := "stopped"
    timerRemainingSec := 600
    timerPresetSec := 600
    slideIndex := 0
    slideTotal := 0
    slideTitle := ""
    slideNotes := ""
    meetBgTabWarn := false
    quickDeckGui := ""
    quickDeckCtrls := ""
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
    isIdleDimmed := false
    lastActivityTick := 0

    dragTimerFn := ""
    breathTimerFn := ""
    autoDodgeTimerFn := ""
    idleDimTimerFn := ""
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
    remoteDeckHotIfFn := ""
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
    activeRemoteNextSlideHk := ""
    activeRemotePrevSlideHk := ""
    activeRemoteTransitionHk := ""
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
        this.lastActivityTick := A_TickCount
        this.idleDimTimerFn := RemoteIdleDimTick.Bind(cfg, this)
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

    StopAllTimers() {
        return StopAllRemoteTimers(this)
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
        hasRatio := (cfg.HasOwnProp("savedXRatio") && cfg.HasOwnProp("savedYRatio")
            && cfg.savedXRatio != "" && cfg.savedYRatio != ""
            && IsNumber(cfg.savedXRatio) && IsNumber(cfg.savedYRatio))
        if (rawX = "Default" || rawY = "Default" || (!hasRatio && (!IsInteger(rawX) || !IsInteger(rawY)))) {
            MonitorGetWorkArea(1, &Left, &Top, &Right, &Bottom)
            this.savedX := Max(Left + UIConstants.SCREEN_MIN_PAD, Right - this.baseWidth - UIConstants.SCREEN_MARGIN_X)
            this.savedY := Max(Top + UIConstants.SCREEN_MIN_PAD, Bottom - this.baseHeight - UIConstants.SCREEN_MARGIN_Y)
        } else if (hasRatio) {
            vLeft := SysGet(76), vTop := SysGet(77)
            vRight := vLeft + SysGet(78), vBottom := vTop + SysGet(79)
            pos := ResolvePositionFromRatio(cfg.savedXRatio, cfg.savedYRatio, this.baseWidth, this.baseHeight, vLeft, vTop, vRight, vBottom)
            this.savedX := pos.x
            this.savedY := pos.y
        } else {
            sx := Integer(rawX), sy := Integer(rawY)
            if (IsSet(CaptureSafety)) {
                clamped := CaptureSafety.ClampRectToMonitors(sx, sy, this.baseWidth, this.baseHeight)
                this.savedX := clamped.x
                this.savedY := clamped.y
            } else {
                vLeft := SysGet(76), vTop := SysGet(77)
                vRight := vLeft + SysGet(78), vBottom := vTop + SysGet(79)
                this.savedX := Max(vLeft, Min(sx, vRight - this.baseWidth))
                this.savedY := Max(vTop, Min(sy, vBottom - this.baseHeight))
            }
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
AppState.wtsMsgGui := Gui("-Caption +ToolWindow", "PresenterSync_RemoteWtsMsg")
try DllCall("Wtsapi32\WTSRegisterSessionNotification", "Ptr", AppState.wtsMsgGui.Hwnd, "UInt", 0)
OnMessage(0x02B1, (wParam, lParam, msg, hwnd) => HandleRemoteWtsSessionChange(wParam, AppConfig, AppState, VerifyOrReconnectRemote.Bind(AppConfig, AppState, "unlock")))
ArcadeVault.RegisterGame("snake", "HUD Snake", "!^+s", "Ctrl+Alt+Shift+S", (c, s) => HudSnake.Toggle(c, s), () => HudSnake.Stop())
ArcadeVault.RegisterGame("asteroids", "Asteroid Blaster", "!^+a", "Ctrl+Alt+Shift+A", (c, s) => GameAsteroids.Toggle(c, s), () => GameAsteroids.Stop())
ArcadeVault.RegisterGame("brick_breaker", "Brick Breaker", "!^+b", "Ctrl+Alt+Shift+B", (c, s) => GameBrickBreaker.Toggle(c, s), () => GameBrickBreaker.Stop())
ArcadeVault.RegisterGame("cyber_pong", "Cyber Pong", "!^+h", "Ctrl+Alt+Shift+H", (c, s) => GameCyberPong.Toggle(c, s), () => GameCyberPong.Stop())
ArcadeVault.RegisterGame("flappy", "Clicker Flappy / Wave", "!^+f", "Ctrl+Alt+Shift+F", (c, s) => GameClickerFlappy.Toggle(c, s), () => GameClickerFlappy.Stop())
ArcadeVault.RegisterGame("tron", "Neon Light Cycles (TRON)", "!^+t", "Ctrl+Alt+Shift+T", (c, s) => GameLightCycles.Toggle(c, s), () => GameLightCycles.Stop())
ArcadeVault.RegisterGame("pac_grid", "Neon Pac-Grid", "!^+c", "Ctrl+Alt+Shift+C", (c, s) => GamePacGrid.Toggle(c, s), () => GamePacGrid.Stop())
ArcadeVault.RegisterGame("missile_defense", "Missile Defense", "!^+m", "Ctrl+Alt+Shift+M", (c, s) => GameMissileDefense.Toggle(c, s), () => GameMissileDefense.Stop())
ArcadeVault.RegisterGame("block_drop", "Neon Block Drop", "!^+d", "Ctrl+Alt+Shift+D", (c, s) => GameBlockDrop.Toggle(c, s), () => GameBlockDrop.Stop())
ArcadeVault.RegisterGame("pinball", "Space Cadet Pinball", "!^+p", "Ctrl+Alt+Shift+P", (c, s) => GameSpacePinball.Toggle(c, s), () => GameSpacePinball.Stop())
ArcadeVault.BindVaultHotkey(AppConfig, AppState)
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
            uriPairRes := PairRemoteWithHostBridge(AppConfig.HostAddress, AppConfig.BridgePort, AppConfig.SessionPairingCode, AppConfig.DeviceId, GetRemoteDisplayDeviceName(AppConfig))
            if (uriPairRes.ok)
                ApplyBridgePairResultToConfig(AppConfig, uriPairRes)
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
    if (IsObject(state) && state.HasOwnProp("isIdleDimmed") && state.isIdleDimmed)
        return Min(state.baseAlpha, 90)
    return state.baseAlpha
}

NotifyRemoteActivity(cfg, state) {
    if (!IsObject(state))
        return
    state.lastActivityTick := A_TickCount
    if (state.HasOwnProp("isIdleDimmed") && state.isIdleDimmed) {
        state.isIdleDimmed := false
        state.currentAlpha := GetRemoteEffectiveAlpha(state)
        if (state.HasOwnProp("MicGui") && IsGuiValid(state.MicGui))
            try Gdip.SetLayeredAlpha(state.MicGui.Hwnd, state.currentAlpha)
    }
}

UpdateRemoteIdleDimTimer(cfg, state) {
    if (!IsObject(state) || !state.HasOwnProp("idleDimTimerFn") || !state.idleDimTimerFn)
        return
    needDim := (IsObject(cfg) && cfg.HasOwnProp("ShowIndicator") && cfg.ShowIndicator
        && cfg.HasOwnProp("EnableIdleAutoDim") && cfg.EnableIdleAutoDim
        && state.HasOwnProp("MicGui") && IsGuiValid(state.MicGui))
    SetTimer(state.idleDimTimerFn, needDim ? 1000 : 0)
    if (!needDim && state.HasOwnProp("isIdleDimmed") && state.isIdleDimmed) {
        state.isIdleDimmed := false
        state.currentAlpha := GetRemoteEffectiveAlpha(state)
        if (IsGuiValid(state.MicGui))
            try Gdip.SetLayeredAlpha(state.MicGui.Hwnd, state.currentAlpha)
    }
}

RemoteIdleDimTick(cfg, state) {
    if (!IsObject(cfg) || !IsObject(state))
        return
    if (!cfg.HasOwnProp("EnableIdleAutoDim") || !cfg.EnableIdleAutoDim || !cfg.ShowIndicator)
        return
    if (!state.HasOwnProp("MicGui") || !IsGuiValid(state.MicGui) || state.isDraggingHud)
        return
    pt := Buffer(8, 0)
    if (DllCall("GetCursorPos", "Ptr", pt, "Int")) {
        mx := NumGet(pt, 0, "Int"), my := NumGet(pt, 4, "Int")
        if (mx >= state.savedX && mx <= (state.savedX + state.baseWidth)
            && my >= state.savedY && my <= (state.savedY + state.baseHeight)) {
            NotifyRemoteActivity(cfg, state)
            return
        }
    }
    if (!state.isIdleDimmed && (A_TickCount - state.lastActivityTick) >= 10000) {
        state.isIdleDimmed := true
        state.currentAlpha := GetRemoteEffectiveAlpha(state)
        try Gdip.SetLayeredAlpha(state.MicGui.Hwnd, state.currentAlpha)
    }
}

RefreshRemoteMicHudAlpha(cfg, state) {
    if (!IsObject(state) || !state.HasOwnProp("MicGui") || !IsObject(state.MicGui))
        return
    state.currentAlpha := GetRemoteEffectiveAlpha(state)
    ApplyMicAppearance(cfg, state)
}

SyncRemoteBreathTimer(cfg, state) {
    if (!IsObject(cfg) || !IsObject(state) || !state.HasOwnProp("breathTimerFn") || !state.breathTimerFn)
        return
    if (state.isMuted && cfg.ShowIndicator && state.obsConnected) {
        state.breathDir := cfg.AggressivePulse ? -UIConstants.PULSE_STEP_AGGRESSIVE : -UIConstants.PULSE_STEP_NORMAL
        SetTimer state.breathTimerFn, (cfg.AggressivePulse ? UIConstants.PULSE_INTERVAL_AGGRESSIVE : UIConstants.PULSE_INTERVAL_NORMAL)
    } else {
        SetTimer state.breathTimerFn, 0
    }
}

HandleRemoteAuthFailure(cfg, state, ws, statusCode, trayMsg) {
    state.connStatus := statusCode
    state._sawAuthChallenge := false
    state.obsConnected := false
    state.usingBridge := false
    state.usingDirectObsFallback := false
    StopRemoteSessionTimers(state, true)
    CloseRemoteSocketRef(ws, state, true)
    RefreshRemoteMicHudAlpha(cfg, state)
    state.NotifyTrayStatus()
    TrayTip(trayMsg, "PresenterSync Remote", 3)
}

ApplyRemoteRelayTelemetryPacket(cfg, state, telObj) {
    if (!IsObject(telObj))
        return
    SyncRemoteBridgeTelemetry(cfg, state, {
        recState: telObj.recState,
        recSeconds: telObj.recSeconds,
        streamDropWarn: telObj.streamDropWarn,
        voiceWhileMuted: telObj.voiceWhileMuted,
        osMicMutedDrift: telObj.HasOwnProp("osMicMutedDrift") ? !!telObj.osMicMutedDrift : state.osMicMutedDrift,
        lowDiskWarnLevel: telObj.HasOwnProp("lowDiskWarnLevel") ? Integer(telObj.lowDiskWarnLevel) : state.lowDiskWarnLevel,
        lowDiskMb: telObj.HasOwnProp("lowDiskMb") ? Integer(telObj.lowDiskMb) : state.lowDiskMb,
        deadMicWarn: telObj.HasOwnProp("deadMicWarn") ? !!telObj.deadMicWarn : state.deadMicWarn,
        slideIndex: telObj.HasOwnProp("slideIndex") ? Max(0, Integer(telObj.slideIndex)) : state.slideIndex,
        slideTotal: telObj.HasOwnProp("slideTotal") ? Max(0, Integer(telObj.slideTotal)) : state.slideTotal,
        slideTitle: telObj.HasOwnProp("slideTitle") && telObj.slideTitle != "" ? String(telObj.slideTitle) : state.slideTitle,
        isStandby: telObj.isStandby,
        timerState: (telObj.timerState != "" ? telObj.timerState : state.timerState),
        timerRemainingSec: telObj.timerRemainingSec,
        timerPresetSec: telObj.timerPresetSec,
        activeScene: (telObj.activeScene != "" ? telObj.activeScene : state.activeScene),
        scenes: telObj.scenes
    })
    UpdateRemoteLocalRecTimer(state)
}

SendRemoteRelaySyncRequest(cfg, state) {
    topic := GetInternetRelayTopic(cfg.InternetPairingCode)
    mockWs := (state.HasOwnProp("relayMockWs") && IsObject(state.relayMockWs)) ? state.relayMockWs : ""
    return PublishInternetRelayPacket(topic, BuildOutboundRelayPacket(cfg, state, "remote", "sync_req", "0"), GetEffectiveRelayBaseUrl(cfg), mockWs)
}

ConnectToRemoteOBS(cfg, state) {
    if (state.obsConnected) {
        SetTimer state.reconnectTimerFn, 0
        SetTimer state.heartbeatTimerFn, 0
        CancelRemotePongWatchdog(state)
        CancelRemoteBridgeHandshakeWatchdog(state)
        if (state.HasOwnProp("lanRepromoteTimerFn") && IsObject(state.lanRepromoteTimerFn))
            SetTimer state.lanRepromoteTimerFn, 0
        return
    }
    StopRemoteSessionTimers(state, true)

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
    CloseRemoteWebSocket(state, false)

    if (IsRemoteUsingInternetChannel(cfg, state)) {
        pairCode := Trim(cfg.InternetPairingCode)
        if (pairCode = "") {
            state.NotifyTrayStatus()
            return
        }
        topic := GetInternetRelayTopic(pairCode)
        relayBase := GetEffectiveRelayBaseUrl(cfg)
        wsUrl := BuildRelayWsUrl(relayBase, topic)
        if (wsUrl = "") {
            state.NotifyTrayStatus()
            return
        }
        state.relayReplayGuard := RelayReplayGuard()
        relayPrefix := (state.HasOwnProp("usingRelayFallback") && state.usingRelayFallback) ? "Relay Bridge (" : "Internet ("
        wsScheme := InStr(wsUrl, "ws://") == 1 ? "ws" : "wss"
        wsHost := RegExReplace(wsUrl, "i)^wss?://([^/:]+).*$", "$1")
        candidate := {
            host: wsHost,
            port: (wsScheme = "ws" ? "80" : "443"),
            scheme: wsScheme,
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
            RefreshRemoteMicHudAlpha(cfg, state)
            SyncRemoteBreathTimer(cfg, state)
            SendRemoteRelaySyncRequest(cfg, state)
            state.NotifyTrayStatus()
        } catch {
            CloseRemoteWebSocket(state, false)
            state.obsConnected := false
            SetTimer state.breathTimerFn, 0
            RefreshRemoteMicHudAlpha(cfg, state)
            FailoverToNextCandidate(cfg, state)
        }
        return
    }

    if (!state.HasOwnProp("_lanCycleStartTick") || state._lanCycleStartTick <= 0 || state.candidateIndex <= 1) {
        state._lanCycleStartTick := A_TickCount
        state._didUdpShiftFollow := false
        state._didBridgePortSweep := false
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
        RefreshRemoteMicHudAlpha(cfg, state)
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
            reconcileJson := state.HasOwnProp("_pendingFallbackReconcile") ? state._pendingFallbackReconcile : ""
            if (!TrySendWsText(state.obsWs, BuildRemoteBridgeAuthJson(cfg, reconcileJson)))
                Throw Error("Failed to send Bridge auth payload")
            StartRemoteBridgeHandshakeWatchdog(cfg, state, candidate, state.connGen, bridgeTimeoutMs)
        }
    } catch {
        CancelRemoteBridgeHandshakeWatchdog(state)
        CloseRemoteWebSocket(state, false)
        SetTimer state.breathTimerFn, 0
        RefreshRemoteMicHudAlpha(cfg, state)
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
    anyHealthy := false
    matchedPort := ""
    eps := ParseCandidateEndpoints(cfg.HostAddress, cfg.HostPort)
    for _, ep in eps {
        probe := ProbeHostBridgeHealth(ep.host, bPort, expectedUuid, RemoteBridgeConstants.HEALTH_PROBE_TIMEOUT_MS)
        if (IsObject(probe) && probe.ok) {
            anyHealthy := true
            matchedPort := bPort
            break
        }
    }
    if (!anyHealthy && Integer(bPort) >= 4456 && Integer(bPort) <= 4465) {
        for _, ep in eps {
            sweep := SweepHostBridgeFallbackPort(ep.host, bPort, expectedUuid, RemoteBridgeConstants.HEALTH_PROBE_TIMEOUT_MS)
            if (IsObject(sweep) && sweep.ok) {
                anyHealthy := true
                matchedPort := sweep.port
                break
            }
        }
    }

    if (!anyHealthy) {
        StepBridgeRepromoteHysteresis(state, false, RemoteBridgeConstants.BRIDGE_REPROMOTE_REQUIRED_PROBES)
        return false
    }

    if (!StepBridgeRepromoteHysteresis(state, true, RemoteBridgeConstants.BRIDGE_REPROMOTE_REQUIRED_PROBES)) {
        if (state.HasOwnProp("lanRepromoteTimerFn") && IsObject(state.lanRepromoteTimerFn))
            SetTimer state.lanRepromoteTimerFn, 1500
        return false
    }

    if (matchedPort != "" && matchedPort != bPort) {
        cfg.BridgePort := matchedPort
        if (cfg.HasMethod("Write"))
            try cfg.Write("Connection", "BridgePort", matchedPort)
    }
    state._pendingFallbackReconcile := (state.HasOwnProp("usingDirectObsFallback") && state.usingDirectObsFallback)
        ? BuildRemoteFallbackStateJson(state)
        : ""
    if (state.HasOwnProp("lanRepromoteTimerFn") && IsObject(state.lanRepromoteTimerFn))
        SetTimer state.lanRepromoteTimerFn, 0
    state.usingRelayFallback := false
    state.usingDirectObsFallback := false
    state._lanCycleStartTick := 0
    state.candidates := BuildRemoteLanCandidateQueue(cfg)
    state.candidateIndex := 1
    CloseRemoteWebSocket(state, false)
    state.obsConnected := false
    state.NotifyTrayStatus()
    SetTimer state.reconnectTimerFn, -30
    return true
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
        ; Sweep fallback Bridge TCP ports (4456, 4458..4465) once per LAN cycle when UDP broadcast is blocked
        hasBridgeCreds := (cfg.HasOwnProp("SessionPairingCode") && Trim(cfg.SessionPairingCode) != "")
            || (cfg.HasOwnProp("SessionToken") && Trim(cfg.SessionToken) != "")
        curBPort := (cfg.HasOwnProp("BridgePort") && IsInteger(cfg.BridgePort)) ? Integer(cfg.BridgePort) : 4456
        if (hasBridgeCreds && curBPort >= 4456 && curBPort <= 4465 && (!state.HasOwnProp("_didBridgePortSweep") || !state._didBridgePortSweep)) {
            state._didBridgePortSweep := true
            expUuid := cfg.HasOwnProp("PairedHostUuid") ? Trim(cfg.PairedHostUuid) : ""
            for _, ep in ParseCandidateEndpoints(cfg.HostAddress, cfg.HostPort) {
                sweepRes := SweepHostBridgeFallbackPort(ep.host, curBPort, expUuid, 450)
                if (IsObject(sweepRes) && sweepRes.ok && sweepRes.port != "" && sweepRes.port != String(curBPort)) {
                    cfg.BridgePort := sweepRes.port
                    if (cfg.HasMethod("Write"))
                        try cfg.Write("Connection", "BridgePort", sweepRes.port)
                    state.candidates := BuildRemoteLanCandidateQueue(cfg)
                    state.candidateIndex := 1
                    SetTimer state.reconnectTimerFn, -30
                    state.NotifyTrayStatus()
                    return
                }
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
    if IsObject(ws) {
        if (IsSet(SafeCloseWebSocketDeferred))
            SafeCloseWebSocketDeferred(ws, 40)
        else
            try ws.shutdown()
    }
    if (IsObject(ws) && IsObject(state.obsWs) && state.obsWs != ws)
        return
    if (state.obsWs == ws)
        state.obsWs := ""

    state.connGen += 1
    wasConnected := state.obsConnected
    ResetRemoteConnectionTelemetry(state, false)
    StopRemoteSessionTimers(state, false)
    state.animSeq += 1

    ; Visual feedback on HUD: Dim while disconnected
    if (!wasConnected && status == 4009) {
        isMissingPw := (cfg.ObsPassword = "" && (!state.HasOwnProp("_sawAuthChallenge") || state._sawAuthChallenge))
        HandleRemoteAuthFailure(cfg, state, "", isMissingPw ? "pw_required" : "auth_failed",
            isMissingPw ? "OBS WebSocket requires a password. Enter it in Change OBS Connection." : "OBS WebSocket authentication failed. Check password in Change OBS Connection.")
        return
    }

    state._sawAuthChallenge := false
    state.connStatus := "searching"
    RefreshRemoteMicHudAlpha(cfg, state)
    state.NotifyTrayStatus()

    FailoverToNextCandidate(cfg, state, candidate)
}

_ApplyRemoteObsFallbackCreds(cfg, ev) {
    if (!IsObject(cfg) || !IsObject(ev) || !ev.HasOwnProp("hasObsFallback") || !ev.hasObsFallback)
        return false
    changed := false
    if (ev.HasOwnProp("obsFallbackPort") && Integer(ev.obsFallbackPort) >= 1 && Integer(ev.obsFallbackPort) <= 65535) {
        newPort := String(Integer(ev.obsFallbackPort))
        if (cfg.HostPort != newPort) {
            cfg.HostPort := newPort
            if (cfg.HasMethod("Write"))
                try cfg.Write("Connection", "HostPort", newPort)
            changed := true
        }
    }
    if (ev.HasOwnProp("obsFallbackMic") && Trim(ev.obsFallbackMic) != "") {
        newMic := Trim(ev.obsFallbackMic)
        if (cfg.TargetMicName != newMic) {
            cfg.TargetMicName := newMic
            if (cfg.HasMethod("Write"))
                try cfg.Write("Connection", "TargetMicName", newMic)
            changed := true
        }
    }
    if (ev.HasOwnProp("obsFallbackPassword") && cfg.ObsPassword != ev.obsFallbackPassword) {
        cfg.ObsPassword := ev.obsFallbackPassword
        if (cfg.HasMethod("Write"))
            try cfg.Write("Connection", "ObsPassword", ev.obsFallbackPassword)
        changed := true
    }
    return changed
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
            if (ev.HasOwnProp("role") && ev.role != "")
                state.remoteRole := ev.role
            SetTimer state.reconnectTimerFn, 0
            CancelRemoteBridgeHandshakeWatchdog(state)
            state._lanCycleStartTick := 0
            state._didBridgePortSweep := false
            state._pendingFallbackReconcile := ""
            if (ev.HasOwnProp("hasObsFallback") && ev.hasObsFallback)
                _ApplyRemoteObsFallbackCreds(cfg, ev)
            if (ev.HasOwnProp("hostBootId") && ev.hostBootId != "" && ev.hostBootId != state.hostBootId) {
                state.hostBootId := ev.hostBootId
                state.lastStateSeq := 0
            }
            if (ev.HasOwnProp("stateSeq") && ev.stateSeq > 0)
                state.lastStateSeq := ev.stateSeq
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
            if (ev.hasMuted)
                _RBC_PersistRemoteMute(cfg, state, ev.isMuted)
            RefreshRemoteMicHudAlpha(cfg, state)
            SyncRemoteBreathTimer(cfg, state)
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
                CloseRemoteSocketRef(ws, state, true)
                SetTimer state.reconnectTimerFn, -100
                return
            }
            isMissingPw := (cfg.ObsPassword = "" && InStr(reasonLow, "password"))
            HandleRemoteAuthFailure(cfg, state, ws, isMissingPw ? "pw_required" : "auth_failed",
                "Host Bridge authentication failed (" (ev.reason != "" ? ev.reason : "Invalid code/token") "). Re-pair in Change OBS Connection.")
        } else if (ev.kind = "flash_pill") {
            hwnd := (state.HasOwnProp("MicGui") && IsObject(state.MicGui)) ? state.MicGui.Hwnd : 0
            ShowCaptureSafeMicroToast("Host flashed this pill!", ev.HasOwnProp("durationMs") ? ev.durationMs : 1800, hwnd)
        } else if (ev.kind = "mute_state" || ev.kind = "sync_resync") {
            CancelRemoteBridgeHandshakeWatchdog(state)
            if (ev.HasOwnProp("hostBootId") && ev.hostBootId != "" && ev.hostBootId != state.hostBootId) {
                state.hostBootId := ev.hostBootId
                state.lastStateSeq := 0
            }
            if (ev.kind = "mute_state" && ev.HasOwnProp("stateSeq") && ev.stateSeq > 0 && state.lastStateSeq > 0 && ev.stateSeq < state.lastStateSeq)
                return
            if (ev.HasOwnProp("stateSeq") && ev.stateSeq > 0)
                state.lastStateSeq := ev.stateSeq
            CancelRemoteOptimisticReconcile(state)
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
                RefreshRemoteMicHudAlpha(cfg, state)
                state.NotifyTrayStatus()
            }
            SyncRemoteMuteState(cfg, state, ev.isMuted, false)
            SyncRemoteBridgeTelemetry(cfg, state, ev)
        } else if (ev.kind = "obs_fallback_update") {
            if (ev.HasOwnProp("hasObsFallback") && ev.hasObsFallback)
                _ApplyRemoteObsFallbackCreds(cfg, ev)
        } else if (ev.kind = "stage_nudge") {
            if (!state.HasOwnProp("suppressNudgeBanners") || !state.suppressNudgeBanners)
                ShowStageNudgeBanner(ev.message, (ev.accentHex != "" ? ev.accentHex : "F59E0B"), 4500, ev.sender)
        } else if (ev.kind = "nack") {
            wasOpt := (state.HasOwnProp("_optimisticMutePending") && state._optimisticMutePending)
            CancelRemoteOptimisticReconcile(state)
            if (wasOpt && IsObject(ws))
                try TrySendWsText(ws, BuildRemoteBridgeSyncReqJson(cfg))
            if (IsSet(DiagnosticLogger))
                try DiagnosticLogger.RecordBreadcrumb("Bridge", "CommandNack", ev.action " code=" ev.code " reason=" ev.reason)
            if (ev.code = "obs_offline" || ev.code = "role_denied" || ev.code = "input_paused" || ev.code = "confirm_required")
                try TrayTip("Host declined '" ev.action "': " (ev.reason != "" ? ev.reason : ev.code), "PresenterSync Remote", 2)
        } else if (ev.kind = "close_remote") {
            if (state.HasOwnProp("onRemoteCloseSignal") && IsObject(state.onRemoteCloseSignal))
                state.onRemoteCloseSignal.Call()
            else
                ExitApp()
        }
        return
    }

    if (!state.HasOwnProp("relayReplayGuard") || !IsObject(state.relayReplayGuard))
        state.relayReplayGuard := RelayReplayGuard()
    allowLegacy := (IsObject(cfg) && cfg.HasOwnProp("AllowLegacyPlaintextRelay") && cfg.AllowLegacyPlaintextRelay) ? true : false
    pkt := ParseRelayEnvelope(msg, cfg.InternetPairingCode, cfg.ObsPassword, state.relayReplayGuard, allowLegacy)
    if IsObject(pkt) {
        if (!pkt.ok) {
            if (IsSet(DiagnosticLogger))
                try DiagnosticLogger.RecordBreadcrumb("Relay", (pkt.HasOwnProp("clockSkewRejected") && pkt.clockSkewRejected) ? "ClockSkewRejected" : (pkt.replayRejected ? "ReplayRejected" : "DecryptRejected"), pkt.error)
            if (pkt.HasOwnProp("clockSkewRejected") && pkt.clockSkewRejected && (!IsSet(g_IsTestMode) || !g_IsTestMode)) {
                if (!state.HasOwnProp("_lastSkewWarnTick") || (A_TickCount - state._lastSkewWarnTick) >= 60000) {
                    state._lastSkewWarnTick := A_TickCount
                    try TrayTip("WAN Relay message rejected (>5 min clock skew). Sync system clock on Host and Remote.", "PresenterSync Remote", 2)
                }
            }
            return
        }
        if (pkt.src != "host")
            return
        expectedTok := GetInternetRelayAuthToken(cfg.InternetPairingCode, cfg.ObsPassword)
        if (pkt.cmd = "auth_error" || pkt.auth != expectedTok) {
            HandleRemoteAuthFailure(cfg, state, ws, "auth_failed",
                "Internet Relay authentication failed. Check password in Change OBS Connection.")
            return
        }
        state._relayPeerLegacy := (allowLegacy && !pkt.encrypted)
        if (pkt.cmd = "state") {
            if (!state.obsConnected || state.connStatus != "connected") {
                state.obsConnected := true
                state.connStatus := "connected"
                state.activeHost := candidate.raw
                RefreshRemoteMicHudAlpha(cfg, state)
                state.NotifyTrayStatus()
            }
            SyncRemoteMuteState(cfg, state, pkt.hasMutedField ? !!pkt.isMuted : (pkt.data = "1" || pkt.data = "true"))
            if (pkt.hasTelemetry)
                ApplyRemoteRelayTelemetryPacket(cfg, state, pkt)
        } else if (pkt.cmd = "dir_state") {
            if (pkt.hasMutedField)
                SyncRemoteMuteState(cfg, state, !!pkt.isMuted)
            if (pkt.hasTelemetry) {
                ApplyRemoteRelayTelemetryPacket(cfg, state, pkt)
            } else {
                parsedDir := ParseDirStatePayload(pkt.data, state)
                if (IsObject(parsedDir))
                    ApplyRemoteRelayTelemetryPacket(cfg, state, parsedDir)
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
        if RegExMatch(msg, '"event"\s*:\s*"open"')
            SendRemoteRelaySyncRequest(cfg, state)
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
        RefreshRemoteMicHudAlpha(cfg, state)
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
                        AnchorRemoteRecClock(state, 0)
                    state.recState := 1
                    if (IsObject(ws))
                        SendObsRequest(ws, "GetRecordStatus", "InitRemoteRec")
                } else if (outSt = "OBS_WEBSOCKET_OUTPUT_PAUSED") {
                    state.recState := 2
                    if (IsObject(ws))
                        SendObsRequest(ws, "GetRecordStatus", "InitRemoteRec")
                } else if (outSt = "OBS_WEBSOCKET_OUTPUT_STOPPED") {
                    state.recState := 0
                    AnchorRemoteRecClock(state, 0)
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
                CancelRemoteOptimisticReconcile(state)
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
                    AnchorRemoteRecClock(state, Max(0, Integer(mDur[1]) // 1000))
                else if (!act)
                    AnchorRemoteRecClock(state, 0)
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
    CloseRemoteWebSocket(state, false)
    state.obsConnected := false
    state.usingBridge := false
    FailoverToNextCandidate(cfg, state, candidate)
}

ForceRemoteReconnectNow(cfg, state, reason := "wake") {
    if (!IsObject(cfg) || !IsObject(state))
        return
    if (IsSet(DiagnosticLogger))
        try DiagnosticLogger.RecordBreadcrumb("Remote", "ForceReconnectNow", "reason=" reason)
    StopRemoteSessionTimers(state, true)
    state.animSeq += 1
    state.connGen += 1
    state._lastWakeReconnectTick := A_TickCount

    CloseRemoteWebSocket(state, false)
    state.obsConnected := false
    state.usingBridge := false
    state.usingDirectObsFallback := false
    state.usingRelayFallback := false
    state.activeHost := ""
    state.connStatus := "searching"
    state.candidateIndex := 1
    state._lanCycleStartTick := 0
    RefreshRemoteMicHudAlpha(cfg, state)
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
        TrySendWsText(state.obsWs, BuildRemoteBridgeSyncReqJson(cfg))
    } else if (IsRemoteUsingInternetChannel(cfg, state)) {
        SendRemoteRelaySyncRequest(cfg, state)
    } else {
        SendRemotePingWithWatchdog(cfg, state, "obs")
    }
}

HandleRemotePowerEvent(cfg, state, wParam, lParam := 0) {
    wp := Integer(wParam)
    return HandleRemotePowerBroadcast(wp, state, (st) => VerifyOrReconnectRemote(cfg, st, wp == 18 ? "power_resume_auto" : "power_resume"))
}

OnRemotePowerBroadcast(cfg, state, wParam, lParam, msg, hwnd) {
    HandleRemotePowerEvent(cfg, state, wParam, lParam)
}

OnRemoteDisplayChange(cfg, state, wParam, lParam, msg, hwnd) {
    if (!IsObject(state) || !state.HasOwnProp("MicGui") || !IsObject(state.MicGui))
        return
    prevX := state.savedX
    prevY := state.savedY
    state.ComputeDimensions(cfg)
    if (IsSet(CaptureSafety)) {
        clamped := CaptureSafety.ClampRectToMonitors(state.savedX, state.savedY, state.baseWidth, state.baseHeight)
        state.savedX := clamped.x
        state.savedY := clamped.y
    } else {
        vLeft := SysGet(76), vTop := SysGet(77)
        vRight := vLeft + SysGet(78), vBottom := vTop + SysGet(79)
        clamped := ClampRemotePositionToBounds(state.savedX, state.savedY, state.baseWidth, state.baseHeight, vLeft, vTop, vRight, vBottom)
        state.savedX := clamped.x
        state.savedY := clamped.y
    }
    if (clamped.x != prevX || clamped.y != prevY) {
        try state.MicGui.Move(clamped.x, clamped.y, state.baseWidth, state.baseHeight)
        if (IsObject(cfg) && cfg.HasMethod("Write")) {
            cfg.savedX := clamped.x
            cfg.savedY := clamped.y
            try cfg.Write("Position", "X", clamped.x)
            try cfg.Write("Position", "Y", clamped.y)
        }
    }
}

RemoteHeartbeatTick(cfg, state) {
    if (!state.obsConnected || !IsObject(state.obsWs))
        return
    if (IsRemoteUsingBridgeChannel(cfg, state)) {
        SendRemotePingWithWatchdog(cfg, state, "bridge")
        return
    }
    if (IsRemoteUsingInternetChannel(cfg, state)) {
        SendRemoteRelaySyncRequest(cfg, state)
        return
    }
    ; Lightweight request to keep TCP session alive + verify response within 2500ms
    SendRemotePingWithWatchdog(cfg, state, "obs")
}

CancelRemoteOptimisticReconcile(state) {
    if (!IsObject(state))
        return
    state._optimisticMutePending := false
    if (state.HasOwnProp("_optimisticTimerFn") && IsObject(state._optimisticTimerFn))
        try SetTimer(state._optimisticTimerFn, 0)
}

_ReconcileRemoteOptimisticMute(cfg, state) {
    if (!IsObject(state) || !state.HasOwnProp("_optimisticMutePending") || !state._optimisticMutePending)
        return
    state._optimisticMutePending := false
    if (!state.HasOwnProp("obsConnected") || !state.obsConnected)
        return
    if (IsRemoteUsingInternetChannel(cfg, state)) {
        SendRemoteRelaySyncRequest(cfg, state)
    } else if (IsRemoteUsingBridgeChannel(cfg, state) && IsObject(state.obsWs)) {
        TrySendWsText(state.obsWs, BuildRemoteBridgeSyncReqJson(cfg))
    } else if (IsObject(state.obsWs)) {
        escMic := EscapeJsonStr(cfg.TargetMicName)
        SendObsRequest(state.obsWs, "GetInputMute", "InitRemoteMute", '{"inputName":"' escMic '"}')
    }
}

ApplyRemoteOptimisticMute(cfg, state, targetMuted) {
    if (!IsObject(state))
        return
    state._optimisticMutePending := true
    SyncRemoteMuteState(cfg, state, !!targetMuted, true)
    if (!state.HasOwnProp("_optimisticTimerFn") || !IsObject(state._optimisticTimerFn))
        state._optimisticTimerFn := _ReconcileRemoteOptimisticMute.Bind(cfg, state)
    try SetTimer(state._optimisticTimerFn, -300)
}

SyncRemoteMuteState(cfg, state, newMuted, isOptimistic := false) {
    if (!isOptimistic)
        CancelRemoteOptimisticReconcile(state)
    if (state.isMuted != newMuted) {
        NotifyRemoteActivity(cfg, state)
        state.isMuted := newMuted
        cfg.IsMuted := newMuted
        if (!isOptimistic) {
            if (cfg.HasMethod("WriteBoolDeferred"))
                cfg.WriteBoolDeferred("Settings", "IsMuted", newMuted, 250)
            else
                cfg.WriteBool("Settings", "IsMuted", newMuted)
        }
        if (!newMuted)
            state.voiceWhileMuted := false
        PlayMuteAnimation(cfg, state)
        UpdateRemoteTouchDeckUI(cfg, state)
        if (state.HasMethod("NotifyTrayStatus"))
            state.NotifyTrayStatus()
        if (!isOptimistic) {
            if (cfg.HasOwnProp("EnableAudioCue") && cfg.EnableAudioCue)
                PlayMuteAudioCue(newMuted)
            if (cfg.HasOwnProp("EnableMuteToast") && cfg.EnableMuteToast)
                ShowMuteToast(newMuted)
        }
    } else if (!isOptimistic) {
        cfg.IsMuted := newMuted
        if (cfg.HasMethod("WriteBoolDeferred"))
            cfg.WriteBoolDeferred("Settings", "IsMuted", newMuted, 250)
        else
            cfg.WriteBool("Settings", "IsMuted", newMuted)
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
    if (ev.HasOwnProp("recSeconds"))
        AnchorRemoteRecClock(state, Max(0, Integer(ev.recSeconds)))
    else
        state.recSeconds := 0
    state.streamDropWarn := ev.HasOwnProp("streamDropWarn") ? !!ev.streamDropWarn : false
    state.voiceWhileMuted := (state.isMuted && ev.HasOwnProp("voiceWhileMuted")) ? !!ev.voiceWhileMuted : false
    if (ev.HasOwnProp("activeScene") && ev.activeScene != "")
        state.activeScene := ev.activeScene
    if (ev.HasOwnProp("scenes") && IsObject(ev.scenes) && ev.scenes.Length > 0)
        state.scenes := ev.scenes
    if (ev.HasOwnProp("quickNudges") && IsObject(ev.quickNudges) && ev.quickNudges.Length > 0)
        state.quickNudges := ev.quickNudges
    if (ev.HasOwnProp("isStandby"))
        state.isStandby := !!ev.isStandby
    if (ev.HasOwnProp("standbyScene") && ev.standbyScene != "")
        state.standbyScene := ev.standbyScene
    if (ev.HasOwnProp("timerState") && ev.timerState != "")
        state.timerState := ev.timerState
    if (ev.HasOwnProp("timerRemainingSec"))
        AnchorRemotePresenterClock(state, Integer(ev.timerRemainingSec))
    if (ev.HasOwnProp("timerPresetSec") && Integer(ev.timerPresetSec) > 0)
        state.timerPresetSec := Integer(ev.timerPresetSec)
    if (ev.HasOwnProp("slideIndex"))
        state.slideIndex := Max(0, Integer(ev.slideIndex))
    if (ev.HasOwnProp("slideTotal"))
        state.slideTotal := Max(0, Integer(ev.slideTotal))
    if (ev.HasOwnProp("slideTitle"))
        state.slideTitle := String(ev.slideTitle)
    if (ev.HasOwnProp("slideNotes"))
        state.slideNotes := String(ev.slideNotes)
    if (ev.HasOwnProp("meetBgTabWarn"))
        state.meetBgTabWarn := !!ev.meetBgTabWarn

    if (state.HasOwnProp("presenterTickFn") && IsObject(state.presenterTickFn)) {
        if (state.timerState = "running" || state.timerState = "overtime")
            SetTimer state.presenterTickFn, 1000
        else
            SetTimer state.presenterTickFn, 0
    }

    if (state.voiceWhileMuted && !prevVoiceWarn && (!cfg.HasOwnProp("EnableVoiceWhileMutedAlert") || cfg.EnableVoiceWhileMutedAlert)) {
        if ((A_TickCount - state._lastVoiceWarnTick) >= 5000) {
            state._lastVoiceWarnTick := A_TickCount
            ShowCaptureSafeMicroToast("⚠ You're on mute — mic signal detected on Host", 2800)
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
    mockWs := (state.HasOwnProp("relayMockWs") && IsObject(state.relayMockWs)) ? state.relayMockWs : ""
    return PublishInternetRelayPacket(topic, BuildOutboundRelayPacket(cfg, state, "remote", cmd, data), GetEffectiveRelayBaseUrl(cfg), mockWs)
}

SendRemoteBridgeDeckCommand(cfg, state, actionType) {
    static lastTransTick := 0
    actLow := StrLower(Trim(String(actionType)))
    if (actLow = "transition_scene") {
        now := A_TickCount
        if (lastTransTick != 0 && (now - lastTransTick < 35))
            return false
        lastTransTick := now
    }
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
    if (IsRemoteDirectObsReady(cfg, state)) {
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
        if (ok)
            CommitRemoteSceneChange(state, clean, true)
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
    if (IsRemoteDirectObsReady(cfg, state))
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
    HideCaptureSafeMicroToast()
}

DockRemoteHudFlushCorner(cfg, state, corner := "BR") {
    return SnapHudToCorner(cfg, state, corner, 0)
}

GetRemoteHudPixelReadout(cfg, state) {
    return GetHudPixelReadout(cfg, state)
}

OnRemoteClickerMute(cfg, state, thisHotkeyOrFromHud := "", *) {
    if (!cfg.EnablePointerMute)
        return

    fromHudClick := (thisHotkeyOrFromHud == true)
    static lastTick := 0
    static inHold := false
    if (inHold)
        return
    now := A_TickCount
    if (!fromHudClick && lastTick != 0 && (now - lastTick < 35)) ; 35ms hardware bounce shield; 0ms for HUD clicks
        return
    lastTick := now

    if (!state.obsConnected || !IsObject(state.obsWs)) {
        ToolTip "PresenterSync Remote: Not connected to OBS host"
        SetTimer RemoveToolTip, -2000
        return
    }

    if (!fromHudClick && cfg.HasOwnProp("EnablePushToTalk") && cfg.EnablePushToTalk) {
        inHold := true
        try {
            ExecutePushToTalkHoldCycle(cfg, state, (m) => DispatchRemoteSetMute(cfg, state, m), cfg.HwMuteHotkey, state.HasOwnProp("keyWaitFn") ? state.keyWaitFn : "")
            lastTick := A_TickCount
        } finally {
            inHold := false
        }
    } else if (DispatchRemoteMuteToggle(cfg, state)) {
        if (!fromHudClick && cfg.HasOwnProp("EnablePushToMute") && cfg.EnablePushToMute) {
            inHold := true
            try {
                if (WaitPushToMuteRelease(cfg, cfg.HwMuteHotkey, state.HasOwnProp("keyWaitFn") ? state.keyWaitFn : "")) {
                    DispatchRemoteMuteToggle(cfg, state)
                    lastTick := A_TickCount
                }
            } finally {
                inHold := false
            }
        }
    }
}

CheckRemotePointerEnable(cfg, ThisHotkey) {
    return cfg.EnablePointerMute && (Theme.OpenWindows.Count == 0 || !Theme.OpenWindows.Has(WinExist("A")))
}

_SetRemoteHotkeyState(hk, enabled, handler := "", hotIfFn := "") {
    clean := Trim(String(hk))
    if (clean = "" || StrLower(clean) = "none")
        return false
    ok := false
    try {
        if (IsObject(hotIfFn))
            HotIf hotIfFn
        if (enabled && IsObject(handler))
            Hotkey clean, handler, "On"
        else
            Hotkey clean, "Off"
        ok := true
    } catch {
        ok := false
    } finally {
        if (IsObject(hotIfFn))
            HotIf
    }
    return ok
}

RegisterRemotePointerHotkey(cfg, state) {
    UnregisterRemotePointerHotkey(cfg, state)
    if (!cfg.EnablePointerMute)
        return
    if (_SetRemoteHotkeyState(cfg.HwMuteHotkey, true, OnRemoteClickerMute.Bind(cfg, state), state.pointerHotIfFn))
        state.activePointerKey := cfg.HwMuteHotkey
}

UnregisterRemotePointerHotkey(cfg, state) {
    keyToClear := (state.activePointerKey != "") ? state.activePointerKey : cfg.HwMuteHotkey
    _SetRemoteHotkeyState(keyToClear, false, "", state.pointerHotIfFn)
    state.activePointerKey := ""
}

ExitRemoteApp(*) {
    ExitApp()
}

RegisterRemoteAppHotkeys(cfg, state) {
    UnregisterRemoteAppHotkeys(cfg, state)
    if (!state.HasOwnProp("remoteDeckHotIfFn") || !IsObject(state.remoteDeckHotIfFn))
        state.remoteDeckHotIfFn := (*) => !HudArcadeBase.IsAnyGameActive() && (Theme.OpenWindows.Count == 0 || !Theme.OpenWindows.Has(WinExist("A")))
    if (_SetRemoteHotkeyState(cfg.PptHotkey, true, ToggleRemotePointerMute.Bind(cfg, state)))
        state.activeToggleMuteHk := cfg.PptHotkey
    if (_SetRemoteHotkeyState(cfg.ExitHotkey, true, ExitRemoteApp))
        state.activeExitHk := cfg.ExitHotkey
    for _, spec in [
        ["RemoteNextSlideKey", "activeRemoteNextSlideHk", "ppt_next"],
        ["RemotePrevSlideKey", "activeRemotePrevSlideHk", "ppt_prev"],
        ["RemoteTransitionKey", "activeRemoteTransitionHk", "transition_scene"]
    ] {
        cfgProp := spec[1], stateProp := spec[2], act := spec[3]
        hkVal := cfg.HasOwnProp(cfgProp) ? cfg.%cfgProp% : ""
        if (_SetRemoteHotkeyState(hkVal, true, ((a, *) => SendRemoteBridgeDeckCommand(cfg, state, a)).Bind(act), state.remoteDeckHotIfFn))
            state.%stateProp% := hkVal
    }
}

UnregisterRemoteAppHotkeys(cfg, state) {
    for _, spec in [
        ["PptHotkey", "activeToggleMuteHk", ""],
        ["ExitHotkey", "activeExitHk", ""],
        ["RemoteNextSlideKey", "activeRemoteNextSlideHk", "deck"],
        ["RemotePrevSlideKey", "activeRemotePrevSlideHk", "deck"],
        ["RemoteTransitionKey", "activeRemoteTransitionHk", "deck"]
    ] {
        cfgProp := spec[1], stateProp := spec[2], scope := spec[3]
        hkVal := (state.HasOwnProp(stateProp) && state.%stateProp% != "") ? state.%stateProp% : (cfg.HasOwnProp(cfgProp) ? cfg.%cfgProp% : "")
        cond := (scope = "deck" && state.HasOwnProp("remoteDeckHotIfFn") && IsObject(state.remoteDeckHotIfFn)) ? state.remoteDeckHotIfFn : ""
        _SetRemoteHotkeyState(hkVal, false, "", cond)
        state.%stateProp% := ""
    }
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
    excl := cfg.HasOwnProp("ExcludeFromCapture") ? cfg.ExcludeFromCapture : true
    ApplyWindowCaptureAffinity(state.MicGui.Hwnd, excl)
    if (state.HasOwnProp("quickDeckGui") && IsObject(state.quickDeckGui)) {
        try if (WinExist("ahk_id " state.quickDeckGui.Hwnd))
            ApplyWindowCaptureAffinity(state.quickDeckGui.Hwnd, excl)
    }
    UpdateAutoDodgeTimer(cfg, state)
    UpdateRemoteIdleDimTimer(cfg, state)

    OnMessage(0x0201, WM_REMOTE_LBUTTONDOWN.Bind(cfg, state))
    OnMessage(0x0203, (wP, lP, m, h) => (IsObject(state.MicGui) && h == state.MicGui.Hwnd) ? WM_REMOTE_LBUTTONDOWN(cfg, state, wP, lP, m, h) : 0)
    OnMessage(0x0205, WM_REMOTE_RBUTTONUP.Bind(state))
    OnMessage(0x0208, (wP, lP, m, h) => (IsObject(state.MicGui) && h == state.MicGui.Hwnd) ? ShowRemoteTouchDeckGUI(cfg, state) : 0)
    OnMessage(0x02E0, WM_REMOTE_DPICHANGED.Bind(cfg, state))
    OnMessage(0x007E, OnRemoteDisplayChange.Bind(cfg, state))
    OnMessage(0x0211, OnRemoteMenuLoop.Bind(state, true))
    OnMessage(0x0212, OnRemoteMenuLoop.Bind(state, false))
}

WM_REMOTE_LBUTTONDOWN(cfg, state, wParam, lParam, msg, hwnd) {
    if (!IsObject(state.MicGui) || hwnd != state.MicGui.Hwnd)
        return

    NotifyRemoteActivity(cfg, state)
    prevX := state.savedX
    prevY := state.savedY
    prevMouseMode := A_CoordModeMouse
    CoordMode("Mouse", "Screen")
    MouseGetPos(&startMX, &startMY)
    downTick := A_TickCount

    dragInitiated := false
    if (!cfg.HasOwnProp("EnableHudClickActions") || cfg.EnableHudClickActions) {
        UpdateRemoteMicHold(p) {
            if (p != state.micHoldProgress) {
                state.micHoldProgress := p
                ApplyMicAppearance(cfg, state)
            }
        }
        micRes := WaitPillLongPressWithProgress(startMX, startMY, downTick, UIConstants.MIC_LONG_PRESS_MS, 90, UIConstants.MIC_LONG_PRESS_MS, UpdateRemoteMicHold, (*) => HandleRemoteHudClick(cfg, state))
        if (micRes.verdict = "hold_handled") {
            CoordMode("Mouse", prevMouseMode)
            return
        }
        if (micRes.verdict = "tap" || micRes.verdict = "hold") {
            CoordMode("Mouse", prevMouseMode)
            HandleRemoteHudClick(cfg, state)
            return
        }
        if (micRes.verdict = "cancel" || (cfg.HasOwnProp("LockHudPosition") && cfg.LockHudPosition)) {
            CoordMode("Mouse", prevMouseMode)
            return
        }
        dragInitiated := true
    }

    if (cfg.HasOwnProp("LockHudPosition") && cfg.LockHudPosition) {
        KeyWait "LButton"
        MouseGetPos(&endMX, &endMY)
        CoordMode("Mouse", prevMouseMode)
        isShortClick := (Abs(endMX - startMX) <= 6 && Abs(endMY - startMY) <= 6 && (A_TickCount - downTick) < 400)
        if (isShortClick)
            HandleRemoteHudClick(cfg, state)
        return
    }

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
            vLeft := SysGet(76), vTop := SysGet(77)
            vRight := vLeft + SysGet(78), vBottom := vTop + SysGet(79)
            ratio := ComputePositionRatio(X, Y, vLeft, vTop, vRight, vBottom)
            cfg.savedXRatio := ratio.xRatio
            cfg.savedYRatio := ratio.yRatio
            cfg.Write("Position", "XRatio", ratio.xRatio)
            cfg.Write("Position", "YRatio", ratio.yRatio)
        }
    }
    state.currentAlpha := GetRemoteEffectiveAlpha(state)
    ApplyMicAppearance(cfg, state)
    ApplyHudClickThroughStyle(cfg, state)
    if (cfg.ShowIndicator && state.obsConnected && state.isMuted)
        SetTimer state.breathTimerFn, (cfg.AggressivePulse ? UIConstants.PULSE_INTERVAL_AGGRESSIVE : UIConstants.PULSE_INTERVAL_NORMAL)

    if (isShortClick && !dragInitiated)
        HandleRemoteHudClick(cfg, state)
}

HandleRemoteHudClick(cfg, state) {
    if (!IsObject(cfg) || !IsObject(state))
        return false
    if (cfg.HasOwnProp("EnableHudClickActions") && !cfg.EnableHudClickActions)
        return false
    if (!cfg.EnablePointerMute) {
        ShowCaptureSafeMicroToast("PresenterSync Remote: Pointer mute control is OFF", 1500)
        return false
    }
    OnRemoteClickerMute(cfg, state, true)
    return true
}

WM_REMOTE_RBUTTONUP(state, wParam, lParam, msg, hwnd) {
    if (IsObject(state.MicGui) && hwnd == state.MicGui.Hwnd) {
        NotifyRemoteActivity("", state)
        A_TrayMenu.Show()
    }
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
    ApplyWindowCaptureAffinity(state.MicGui.Hwnd, cfg.HasOwnProp("ExcludeFromCapture") ? cfg.ExcludeFromCapture : true)
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
        SyncRemoteBreathTimer(cfg, state)
    } else {
        state.MicGui.Hide()
        SetTimer state.breathTimerFn, 0
    }
    ApplyHudClickThroughStyle(cfg, state)
    excl := cfg.HasOwnProp("ExcludeFromCapture") ? cfg.ExcludeFromCapture : true
    ApplyWindowCaptureAffinity(state.MicGui.Hwnd, excl)
    if (state.HasOwnProp("quickDeckGui") && IsObject(state.quickDeckGui)) {
        try if (WinExist("ahk_id " state.quickDeckGui.Hwnd))
            ApplyWindowCaptureAffinity(state.quickDeckGui.Hwnd, excl)
    }
    UpdateAutoDodgeTimer(cfg, state)
    UpdateRemoteIdleDimTimer(cfg, state)
    UpdateRemoteTouchDeckUI(cfg, state)
}

UpdateRemoteTouchDeckUI(cfg, state) {
    if (!IsObject(state) || !state.HasOwnProp("quickDeckGui") || !IsObject(state.quickDeckGui))
        return
    try {
        if (!WinExist("ahk_id " state.quickDeckGui.Hwnd))
            return
    } catch {
        return
    }
    ctrls := state.quickDeckCtrls
    if (!IsObject(ctrls))
        return

    modeLbl := GetRemoteConnectionModeLabel(state)
    scName := (state.HasOwnProp("activeScene") && state.activeScene != "") ? state.activeScene : "Scene"
    recBadge := (state.recState == 1) ? ("REC " FormatElapsedShort(state.recSeconds)) : ((state.recState == 2) ? ("PAUSED " FormatElapsedShort(state.recSeconds)) : "REC OFF")
    if (state.HasOwnProp("streamDropWarn") && state.streamDropWarn)
        recBadge .= " | STREAM WARN"
    ctrls.lblHeader.Value := modeLbl "  |  Scene: " scName "  |  " recBadge

    ctrls.btnMute.Text := state.isMuted ? "UNMUTE MIC (Currently MUTED)" : "MUTE MIC (Currently LIVE)"

    sIdx := state.HasOwnProp("slideIndex") ? Integer(state.slideIndex) : 0
    sTot := state.HasOwnProp("slideTotal") ? Integer(state.slideTotal) : 0
    sTitle := (state.HasOwnProp("slideTitle") && state.slideTitle != "") ? (" - " state.slideTitle) : ""
    ctrls.lblSlide.Value := (sIdx > 0) ? ("Slide " sIdx (sTot > 0 ? (" / " sTot) : "") sTitle) : "Slide: (No active slideshow)"

    tState := state.HasOwnProp("timerState") ? state.timerState : "stopped"
    tRem := state.HasOwnProp("timerRemainingSec") ? Integer(state.timerRemainingSec) : 600
    ctrls.lblTimer.Value := "Timer: " FormatCountdownClock(tRem) " (" tState ")"
    ctrls.btnTimerPause.Text := (tState = "paused") ? "Resume" : "Pause"
    ctrls.btnStandby.Text := (state.HasOwnProp("isStandby") && state.isStandby) ? "Exit BRB" : "Standby (BRB)"

    Loop 6 {
        btn := ctrls.sceneBtns[A_Index]
        if (IsObject(state.scenes) && A_Index <= state.scenes.Length) {
            sn := String(state.scenes[A_Index])
            btn.Text := (sn == scName) ? ("[*] " sn) : sn
            btn.Visible := true
            btn.Enabled := true
        } else {
            btn.Visible := false
            btn.Enabled := false
        }
    }
}

CreateThemedRemoteDialog(winKey, title, marginX := 18, marginY := 16, suspendHotkeys := false) {
    existing := Theme.FocusExistingWindow(winKey)
    if (IsObject(existing))
        return { existing: existing, gui: "" }
    if (suspendHotkeys)
        Theme.AcquireSuspend()
    g := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", title)
    g._closed := false
    if (marginX >= 0)
        g.MarginX := marginX
    if (marginY >= 0)
        g.MarginY := marginY
    Theme.ApplyToWindow(g)
    Theme.NamedWindows[winKey] := g
    return { existing: "", gui: g }
}

AddThemedCtrl(guiObj, ctrlType, opts, textOrItems := "", themeType := "", variant := "") {
    ctrl := (textOrItems != "" || IsObject(textOrItems))
        ? guiObj.Add(ctrlType, opts, textOrItems)
        : guiObj.Add(ctrlType, opts)
    tType := (themeType != "") ? themeType : ctrlType
    if (variant != "")
        Theme.RegisterControl(guiObj, ctrl, tType, variant)
    else
        Theme.RegisterControl(guiObj, ctrl, tType)
    return ctrl
}

BindRemoteDialogClose(guiObj, winKey, releaseSuspend := false, extraCleanupFn := "", cancelBtn := "") {
    CloseFn(*) {
        if (guiObj.HasOwnProp("_closed") && guiObj._closed)
            return
        guiObj._closed := true
        if (IsObject(extraCleanupFn))
            try extraCleanupFn.Call()
        Theme.UnregisterWindow(guiObj, winKey)
        if (releaseSuspend)
            Theme.ReleaseSuspend()
        guiObj.Destroy()
    }
    if (IsObject(cancelBtn))
        cancelBtn.OnEvent("Click", CloseFn)
    guiObj.OnEvent("Close", CloseFn)
    guiObj.OnEvent("Escape", CloseFn)
    return CloseFn
}

ShowRemoteTouchDeckGUI(cfg, state, *) {
    winKey := "PresenterSync Remote Quick Deck"
    dlgRes := CreateThemedRemoteDialog(winKey, winKey, 14, 12, false)
    if (IsObject(dlgRes.existing)) {
        UpdateRemoteTouchDeckUI(cfg, state)
        return dlgRes.existing
    }
    deckGui := dlgRes.gui
    ApplyWindowCaptureAffinity(deckGui.Hwnd, (IsObject(cfg) && cfg.HasOwnProp("ExcludeFromCapture")) ? cfg.ExcludeFromCapture : true)

    deckGui.SetFont("s10 w700", Theme.UiFont)
    lblHeader := AddThemedCtrl(deckGui, "Text", "x14 y14 w592 h26", "Connecting...")

    deckGui.SetFont("s11 w700", Theme.UiFont)
    btnMute := AddThemedCtrl(deckGui, "Button", "x14 y50 w290 h52", "MUTE / UNMUTE", "Button", "accent")
    btnTrans := AddThemedCtrl(deckGui, "Button", "x316 y50 w290 h52", "OBS TRANSITION (Preview <-> Program)")
    btnMute.OnEvent("Click", (*) => (OnRemoteClickerMute(cfg, state, true), UpdateRemoteTouchDeckUI(cfg, state)))
    btnTrans.OnEvent("Click", (*) => SendRemoteBridgeDeckCommand(cfg, state, "transition_scene"))

    deckGui.SetFont("s9 w600", Theme.UiFont)
    lblSlide := AddThemedCtrl(deckGui, "Text", "x14 y114 w592 h22", "Slide: (No active slideshow)", "Text", "muted")

    btnPrevSlide := AddThemedCtrl(deckGui, "Button", "x14 y142 w190 h42", "Prev Slide")
    btnNextSlide := AddThemedCtrl(deckGui, "Button", "x215 y142 w190 h42", "Next Slide")
    btnStartSlide := AddThemedCtrl(deckGui, "Button", "x416 y142 w190 h42", "Start Slideshow (F5)")
    btnPrevSlide.OnEvent("Click", (*) => SendRemoteBridgeDeckCommand(cfg, state, "ppt_prev"))
    btnNextSlide.OnEvent("Click", (*) => SendRemoteBridgeDeckCommand(cfg, state, "ppt_next"))
    btnStartSlide.OnEvent("Click", (*) => SendRemoteBridgeDeckCommand(cfg, state, "slide_start"))

    AddThemedCtrl(deckGui, "Text", "x14 y198 w592 h20", "Scene Switcher:")

    sceneBtns := []
    Loop 6 {
        idx := A_Index
        bx := 14 + (idx - 1) * 100
        sBtn := AddThemedCtrl(deckGui, "Button", "x" bx " y222 w94 h42 Hidden", "Scene " idx)
        sBtn.OnEvent("Click", ((i, *) => (
            (IsObject(state.scenes) && i <= state.scenes.Length) ? SendRemoteSwitchScene(cfg, state, state.scenes[i]) : 0
        )).Bind(idx))
        sceneBtns.Push(sBtn)
    }

    lblTimer := AddThemedCtrl(deckGui, "Text", "x14 y278 w592 h22", "Timer: 10:00 (stopped)")

    btnStandby := AddThemedCtrl(deckGui, "Button", "x14 y304 w116 h42", "Standby (BRB)")
    btnT5 := AddThemedCtrl(deckGui, "Button", "x138 y304 w82 h42", "+5m")
    btnT10 := AddThemedCtrl(deckGui, "Button", "x228 y304 w82 h42", "+10m")
    btnT15 := AddThemedCtrl(deckGui, "Button", "x318 y304 w82 h42", "+15m")
    btnTimerPause := AddThemedCtrl(deckGui, "Button", "x408 y304 w104 h42", "Pause")
    btnTimerReset := AddThemedCtrl(deckGui, "Button", "x520 y304 w86 h42", "Reset")
    btnStandby.OnEvent("Click", (*) => (SendRemoteBridgeDeckCommand(cfg, state, "toggle_standby"), UpdateRemoteTouchDeckUI(cfg, state)))
    btnT5.OnEvent("Click", (*) => SendRemoteTimerCommand(cfg, state, "timer_start", 300))
    btnT10.OnEvent("Click", (*) => SendRemoteTimerCommand(cfg, state, "timer_start", 600))
    btnT15.OnEvent("Click", (*) => SendRemoteTimerCommand(cfg, state, "timer_start", 900))
    btnTimerPause.OnEvent("Click", (*) => SendRemoteTimerCommand(cfg, state, (state.timerState = "paused") ? "timer_start" : "timer_pause", 0))
    btnTimerReset.OnEvent("Click", (*) => SendRemoteTimerCommand(cfg, state, "timer_reset", state.timerPresetSec))

    for idx, nudgeTxt in ["2 min left", "Wrap up", "Check Mic"] {
        nx := (idx == 1) ? 14 : ((idx == 2) ? 215 : 416)
        nBtn := AddThemedCtrl(deckGui, "Button", "x" nx " y360 w190 h40", nudgeTxt)
        nBtn.OnEvent("Click", ((t, *) => SendRemoteStageNudge(cfg, state, t)).Bind(nudgeTxt))
    }

    edNudge := AddThemedCtrl(deckGui, "Edit", "x14 y412 w444 h40", "")
    btnSendNudge := AddThemedCtrl(deckGui, "Button", "x468 y412 w138 h40", "Send Nudge")
    btnSendNudge.OnEvent("Click", (*) => (
        (Trim(edNudge.Value) != "") ? (SendRemoteStageNudge(cfg, state, Trim(edNudge.Value)), edNudge.Value := "") : 0
    ))

    btnCloseDeck := AddThemedCtrl(deckGui, "Button", "x486 y466 w120 h40", "Close")
    BindRemoteDialogClose(deckGui, winKey, false, (*) => (
        IsObject(state) ? (state.quickDeckGui := "", state.quickDeckCtrls := "") : 0
    ), btnCloseDeck)

    if (IsObject(state)) {
        state.quickDeckGui := deckGui
        state.quickDeckCtrls := {
            lblHeader: lblHeader,
            btnMute: btnMute,
            lblSlide: lblSlide,
            lblTimer: lblTimer,
            btnTimerPause: btnTimerPause,
            btnStandby: btnStandby,
            sceneBtns: sceneBtns
        }
    }
    UpdateRemoteTouchDeckUI(cfg, state)
    if (!IsSet(g_IsTestMode) || !g_IsTestMode)
        deckGui.Show("w620 h520")
    return deckGui
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
    UpdateRemoteTouchDeckUI(cfg, state)
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

_AddRemoteCheckedMenuItem(menuObj, label, handler, isChecked := false) {
    menuObj.Add(label, handler)
    if (isChecked)
        menuObj.Check(label)
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

    ; 1. STATUS LINE & ESSENTIALS (8-ITEM TOP LEVEL)
    statusText := GetRemoteTrayStatusText(state)
    if (IsObject(state))
        state._lastTrayStatusText := statusText
    A_TrayMenu.Add(statusText, (*) => 0)
    A_TrayMenu.Disable(statusText)
    A_TrayMenu.Add()

    A_TrayMenu.Add("Open Quick Deck...", (*) => ShowRemoteTouchDeckGUI(cfg, state))
    try A_TrayMenu.Default := "Open Quick Deck..."
    _AddRemoteCheckedMenuItem(A_TrayMenu, "Show Mute Indicator", ToggleRemoteIndicator.Bind(cfg, state), cfg.ShowIndicator)
    A_TrayMenu.Add()

    ; 2. HOST DECK CONTROL
    DeckMenu := Menu()
    DeckMenu.Add("Next Slide (Host PowerPoint)", (*) => SendRemoteBridgeDeckCommand(cfg, state, "ppt_next"))
    DeckMenu.Add("Previous Slide (Host PowerPoint)", (*) => SendRemoteBridgeDeckCommand(cfg, state, "ppt_prev"))
    DeckMenu.Add()
    DeckSceneMenu := Menu()
    if (IsObject(state) && state.HasOwnProp("scenes") && IsObject(state.scenes) && state.scenes.Length > 0) {
        for scItem in state.scenes {
            dispSc := StrReplace(scItem, "&", "&&")
            _AddRemoteCheckedMenuItem(DeckSceneMenu, dispSc, ((s, *) => SendRemoteSwitchScene(cfg, state, s)).Bind(scItem), state.HasOwnProp("activeScene") && state.activeScene == scItem)
        }
    } else {
        DeckSceneMenu.Add("Connect Primary Bridge for scenes", (*) => 0)
        DeckSceneMenu.Disable("Connect Primary Bridge for scenes")
    }
    DeckMenu.Add("Transition OBS Scene (Preview <-> Program)", (*) => SendRemoteBridgeDeckCommand(cfg, state, "transition_scene"))
    DeckMenu.Add("Switch Host Scene", DeckSceneMenu)
    _AddRemoteCheckedMenuItem(DeckMenu, "Toggle Standby / `"BRB`" Curtain", (*) => SendRemoteBridgeDeckCommand(cfg, state, "toggle_standby"), IsObject(state) && state.HasOwnProp("isStandby") && state.isStandby)
    DeckMenu.Add("Start / Stop Host Recording", (*) => SendRemoteBridgeDeckCommand(cfg, state, "toggle_record"))
    DeckMenu.Add("Pause / Resume Host Recording", (*) => SendRemoteBridgeDeckCommand(cfg, state, "pause_record"))
    DeckMenu.Add("Split Host Recording Chapter", (*) => SendRemoteBridgeDeckCommand(cfg, state, "split_record"))
    DeckMenu.Add()
    DeckMenu.Add("Presenter Countdown Timer", BuildSharedPresenterTimerSubmenu(state, (sec, *) => SendRemoteTimerCommand(cfg, state, "timer_start", sec), (*) => SendRemoteTimerCommand(cfg, state, "timer_pause", 0), (sec, *) => SendRemoteTimerCommand(cfg, state, "timer_reset", sec)))
    DeckMenu.Add("Send Stage Nudge to Host...", (*) => PromptSendStageNudgeUI((msg) => SendRemoteStageNudge(cfg, state, msg)))
    deckLabel := (IsObject(state) && state.HasOwnProp("usingDirectObsFallback") && state.usingDirectObsFallback) ? "Host Deck Control (DIRECT OBS :4455)" : "Host Deck Control (Bridge)"
    A_TrayMenu.Add(deckLabel, DeckMenu)

    ; 3. HUD & APPEARANCE (CATEGORIZED SUBMENUS)
    AppearanceMenu := Menu()

    StyleMenu := Menu()
    BuildSharedAppearanceSubmenus(StyleMenu, cfg, state, SetRemoteOpacity.Bind(cfg, state), SetRemoteScale.Bind(cfg, state), SetRemoteTheme.Bind(cfg, state))
    StyleMenu.Add()
    _AddRemoteCheckedMenuItem(StyleMenu, "Show Text Label", ToggleRemoteText.Bind(cfg, state), cfg.ShowText)
    _AddRemoteCheckedMenuItem(StyleMenu, "Use Monochromatic Icon", ToggleRemoteMono.Bind(cfg, state), cfg.MonoIcon)
    _AddRemoteCheckedMenuItem(StyleMenu, "Use Sleek Corners", ToggleRemoteCorners.Bind(cfg, state), cfg.SleekCorners)
    _AddRemoteCheckedMenuItem(StyleMenu, "Show Pill Mini-Badges (Timer / BRB / REC)", (*) => ToggleHudOptionAndRebuild(cfg, state, "ShowPillMiniBadges", "Appearance", RefreshRemoteHudAppearance, BuildRemoteTrayMenu), cfg.ShowPillMiniBadges)
    AppearanceMenu.Add("Visual Style && Sizing", StyleMenu)

    AlertsMenu := Menu()
    _AddRemoteCheckedMenuItem(AlertsMenu, "Aggressive Mute Pulse", ToggleRemotePulse.Bind(cfg, state), cfg.AggressivePulse)
    _AddRemoteCheckedMenuItem(AlertsMenu, "Mute Audio Cue (Beep)", ToggleAudioCue.Bind(cfg, state), cfg.EnableAudioCue)
    _AddRemoteCheckedMenuItem(AlertsMenu, "Mute Status Toast", ToggleMuteToast.Bind(cfg, state), cfg.EnableMuteToast)
    _AddRemoteCheckedMenuItem(AlertsMenu, "Voice-While-Muted Alert", (*) => ToggleBoolSetting(cfg, state, "EnableVoiceWhileMutedAlert"), cfg.EnableVoiceWhileMutedAlert)
    AppearanceMenu.Add("Alerts && Feedback", AlertsMenu)

    BehaviorMenu := Menu()
    _AddRemoteCheckedMenuItem(BehaviorMenu, "Interactive HUD Click Actions", (*) => ToggleBoolSetting(cfg, state, "EnableHudClickActions"), cfg.EnableHudClickActions)
    _AddRemoteCheckedMenuItem(BehaviorMenu, "Magnetic Edge/Window Snap", ToggleMagneticSnap.Bind(cfg, state), cfg.EnableMagneticSnap)
    _AddRemoteCheckedMenuItem(BehaviorMenu, "Click-Through HUD (Hold Alt)", ToggleHudClickThrough.Bind(cfg, state), cfg.HudClickThrough)
    _AddRemoteCheckedMenuItem(BehaviorMenu, "Auto-Dodge HUD on Hover", ToggleHudAutoDodge.Bind(cfg, state), cfg.HudAutoDodge)
    _AddRemoteCheckedMenuItem(BehaviorMenu, "Auto-Dim HUD When Idle (10s)", (*) => ToggleHudOptionAndRebuild(cfg, state, "EnableIdleAutoDim", "Appearance", RefreshRemoteHudAppearance, BuildRemoteTrayMenu), cfg.EnableIdleAutoDim)
    _AddRemoteCheckedMenuItem(BehaviorMenu, "Lock Pill Position", (*) => ToggleHudOptionAndRebuild(cfg, state, "LockHudPosition", "Appearance", RefreshRemoteHudAppearance, BuildRemoteTrayMenu), cfg.LockHudPosition)
    _AddRemoteCheckedMenuItem(BehaviorMenu, "Hide HUD from Screen Share / Capture", (*) => ToggleHudOptionAndRebuild(cfg, state, "ExcludeFromCapture", "Appearance", RefreshRemoteHudAppearance, BuildRemoteTrayMenu), cfg.ExcludeFromCapture)
    AppearanceMenu.Add("Behavior && Capture Safety", BehaviorMenu)

    AppearanceMenu.Add()
    AppearanceMenu.Add("Reset Indicator Position", ResetRemotePositionAction.Bind(cfg, state))
    AppearanceMenu.Add("Restore Default Appearance", ResetRemoteAppearanceAction.Bind(cfg, state))
    A_TrayMenu.Add("HUD && Appearance", AppearanceMenu)

    ; 4. POINTER & CONNECTION
    PtrConnMenu := Menu()
    PointerMenu := Menu()
    _AddRemoteCheckedMenuItem(PointerMenu, "Enable Pointer Mute", ToggleRemotePointerMute.Bind(cfg, state), cfg.EnablePointerMute)
    _AddRemoteCheckedMenuItem(PointerMenu, "Enable Cough / Push-to-Mute (Hold)", TogglePushToMute.Bind(cfg, state), cfg.EnablePushToMute)
    _AddRemoteCheckedMenuItem(PointerMenu, "Enable Push-to-Talk (Hold to Unmute)", TogglePushToTalk.Bind(cfg, state), cfg.HasOwnProp("EnablePushToTalk") && cfg.EnablePushToTalk)
    PointerMenu.Add("Change Pointer Mute Button...", (*) => ChangeRemotePointerKeyUI(cfg, state))
    PointerMenu.Add("Launch Clicker Tester...", (*) => ShowPointerTester())
    PtrConnMenu.Add("Pointer Controls", PointerMenu)

    ProfilesMenu := Menu()
    savedProfs := LoadSavedHostProfiles(cfg)
    if (savedProfs.Length == 0) {
        ProfilesMenu.Add("(No Saved Profiles)", (*) => 0)
        ProfilesMenu.Disable("(No Saved Profiles)")
    } else {
        for _, prof in savedProfs {
            pNm := prof.name
            ProfilesMenu.Add(pNm " (" (prof.host != "" ? prof.host : prof.networkMode) ")", ((nm, *) => (ApplyHostProfile(cfg, state, nm), BuildRemoteTrayMenu(cfg, state))).Bind(pNm))
        }
    }
    PtrConnMenu.Add("Switch Room / Profile", ProfilesMenu)
    PtrConnMenu.Add()
    PtrConnMenu.Add("Change Host / OBS Connection...", (*) => ShowRemoteConnectionUI(cfg, state, false))
    PtrConnMenu.Add("Change App Shortcuts...", (*) => ChangeRemoteAppHotkeysUI(cfg, state))
    PtrConnMenu.Add("Create Desktop Shortcut for Instance...", (*) => ShowCreateRemoteShortcutUI(cfg, state))
    _AddRemoteCheckedMenuItem(PtrConnMenu, "Start with Windows", ToggleStartWithWindows.Bind(cfg, state), cfg.StartWithWindows)
    A_TrayMenu.Add("Pointer && Connection", PtrConnMenu)

    ; 5. HELP & DIAGNOSTICS
    HelpMenu := Menu()
    HelpMenu.Add("Help && Setup Guide...", (*) => ShowRemoteHelpUI(cfg, state))
    HelpMenu.Add()
    HelpMenu.Add("View Error && Diagnostic Log...", (*) => DiagnosticLogger.ShowLogViewerWindow(cfg, state))
    HelpMenu.Add("Export Sanitized Diagnostics...", (*) => ExportRemoteSanitizedDiagnostics(cfg, state))
    HelpMenu.Add()
    HelpMenu.Add("Check for Updates...", (*) => CheckForUpdates(UIConstants.APP_VERSION, "", false, "PresenterSync_Remote.exe", cfg))
    HelpMenu.Add("About PresenterSync Remote...", (*) => ShowRemoteAboutUI(cfg, state))
    A_TrayMenu.Add("Help && Diagnostics", HelpMenu)

    ; 6. SAFETY & EXIT
    A_TrayMenu.Add()
    _AddRemoteCheckedMenuItem(A_TrayMenu, "Suspend All Hotkeys", ToggleRemoteSuspend, Theme.SuspendLockCount > 0 ? Theme.WasSuspendedBeforeDialogs : A_IsSuspended)
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
    dlgRes := CreateThemedRemoteDialog("Create Remote Instance Shortcut", "Create Remote Instance Shortcut", 20, 16, true)
    if IsObject(dlgRes.existing)
        return dlgRes.existing
    dlg := dlgRes.gui

    dlg.SetFont("s10 w600", Theme.UiFont)
    AddThemedCtrl(dlg, "Text", "xm w360", "Quick-Launch Desktop Shortcut")
    dlg.SetFont("s9 w400", Theme.UiFont)
    AddThemedCtrl(dlg, "Text", "xm w360 h32 y+4", "Creates a Desktop .lnk launching PresenterSync Remote for a dedicated Smart Board or classroom instance.", "Text", "muted")

    curInst := (IsObject(cfg) && cfg.HasOwnProp("InstanceName")) ? cfg.InstanceName : ""
    dlg.SetFont("s9 w600", Theme.UiFont)
    AddThemedCtrl(dlg, "Text", "xm w360 y+10", "Instance Name (Optional, e.g. SmartBoard-101):")
    dlg.SetFont("s9 w400", Theme.UiFont)
    edInst := AddThemedCtrl(dlg, "Edit", "xm w360 y+4", curInst)
    DllCall("SendMessage", "Ptr", edInst.Hwnd, "UInt", 0x1501, "Ptr", 1, "WStr", "SmartBoard-Room101 (leave blank for Default)")

    dlg.SetFont("s9 w600", Theme.UiFont)
    AddThemedCtrl(dlg, "Text", "xm w360 y+10", "Desktop Shortcut Filename:")
    dlg.SetFont("s9 w400", Theme.UiFont)
    defaultLnkName := RegExReplace(GetDefaultRemoteShortcutFilename(curInst), "i)\.lnk$", "")
    edLnkName := AddThemedCtrl(dlg, "Edit", "xm w360 y+4", defaultLnkName)

    chkPinIni := AddThemedCtrl(dlg, "Checkbox", "xm w360 y+10", "Include explicit -Config INI path in shortcut")

    initSpec := BuildRemoteShortcutLaunchSpec(curInst, "")
    lblPreview := AddThemedCtrl(dlg, "Text", "xm w360 h34 y+8", "Args: " (initSpec.args != "" ? initSpec.args : "(default instance)"), "Text", "muted")

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

    btnCreate := AddThemedCtrl(dlg, "Button", "xm w174 h32 y+14 Default", "Create Shortcut", "Button", "accent")
    btnCancel := AddThemedCtrl(dlg, "Button", "x+12 yp w174 h32", "Cancel")
    CloseDlg := BindRemoteDialogClose(dlg, "Create Remote Instance Shortcut", true, "", btnCancel)

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
    HideCaptureSafeMicroToast()
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
        cfg.RemoteNextSlideKey := values["nextSlide"]
        cfg.RemotePrevSlideKey := values["prevSlide"]
        cfg.RemoteTransitionKey := values["transition"]
        cfg.Write("Shortcuts", "PptHotkey", cfg.PptHotkey)
        cfg.Write("Shortcuts", "ExitHotkey", cfg.ExitHotkey)
        cfg.Write("Shortcuts", "RemoteNextSlideKey", cfg.RemoteNextSlideKey)
        cfg.Write("Shortcuts", "RemotePrevSlideKey", cfg.RemotePrevSlideKey)
        cfg.Write("Shortcuts", "RemoteTransitionKey", cfg.RemoteTransitionKey)
        if dlg.HasOwnProp("_releaseState")
            dlg._releaseState.Call()
        dlg.Destroy()
        RegisterRemoteAppHotkeys(cfg, state)
        BuildRemoteTrayMenu(cfg, state)
        TrayTip("Remote app shortcuts updated (" FormatHK(cfg.PptHotkey) " / " FormatHK(cfg.ExitHotkey) ").", "PresenterSync Remote", 1)
    }

    elements := [
        {type: "Text", opts: "xm w190 h25 +0x200", text: "Toggle Pointer Mute:"},
        {type: "Shortcut", id: "ppt", opts: "x+10 yp w280 h25", value: cfg.PptHotkey, required: true, errorMsg: "Shortcuts cannot be left blank.", captureTitle: "Capture Toggle Pointer Mute"},
        {type: "Text", opts: "xm y+8 w190 h25 +0x200", text: "Exit PresenterSync Remote:"},
        {type: "Shortcut", id: "exit", opts: "x+10 yp w280 h25", value: cfg.ExitHotkey, required: true, errorMsg: "Shortcuts cannot be left blank.", captureTitle: "Capture Exit Remote"},
        {type: "Text", opts: "xm y+12 w190 h25 +0x200", text: "Next Slide (Optional):"},
        {type: "Shortcut", id: "nextSlide", opts: "x+10 yp w280 h25", value: cfg.RemoteNextSlideKey, captureTitle: "Capture Next Slide"},
        {type: "Text", opts: "xm y+8 w190 h25 +0x200", text: "Previous Slide (Optional):"},
        {type: "Shortcut", id: "prevSlide", opts: "x+10 yp w280 h25", value: cfg.RemotePrevSlideKey, captureTitle: "Capture Previous Slide"},
        {type: "Text", opts: "xm y+8 w190 h25 +0x200", text: "OBS Transition (Optional):"},
        {type: "Shortcut", id: "transition", opts: "x+10 yp w280 h25", value: cfg.RemoteTransitionKey, captureTitle: "Capture Remote OBS Transition"}
    ]

    return BuildSettingsWindow("Edit Remote App Shortcuts", elements, SaveRemoteAppHk, {
        saveBtnText: "Save & Apply",
        saveBtnOpts: "xm w480 h32 Default y+16"
    })
}

ExportRemoteSanitizedDiagnostics(cfg, state := "", *) {
    logDir := IsSet(DiagnosticLogger) ? DiagnosticLogger.LogDir : (A_ScriptDir "\logs")
    if (!DirExist(logDir))
        DirCreate(logDir)
    outPath := logDir "\PresenterSync_Remote_Diagnostics_" FormatTime(A_Now, "yyyyMMdd_HHmmss") ".txt"
    secrets := IsSet(DiagnosticLogger) ? DiagnosticLogger._CollectSecrets(cfg) : []
    if (IsObject(cfg)) {
        for _, prop in ["ObsPassword", "BridgeToken", "SessionPairingCode", "InternetPairingCode"] {
            if (cfg.HasOwnProp(prop) && cfg.%prop% != "")
                secrets.Push(String(cfg.%prop%))
        }
    }
    report := "=== PresenterSync Remote Sanitized Diagnostics ===`r`n"
        . "Timestamp: " FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") "`r`n"
        . "Version: " (IsSet(UIConstants) ? UIConstants.APP_VERSION : "") "`r`n"
        . "AHK: " A_AhkVersion " | OS: " A_OSVersion "`r`n"
    if (IsSet(DiagnosticLogger)) {
        report .= "`r`n--- Settings Snapshot ---`r`n" DiagnosticLogger._FormatSettingsSnapshot(cfg) "`r`n"
            . "`r`n--- State Snapshot ---`r`n" DiagnosticLogger._FormatStateSnapshot(state) "`r`n"
            . "`r`n--- Recent Log Tail ---`r`n" DiagnosticLogger.GetRecentLogTail(24000) "`r`n"
        report := DiagnosticLogger._ScrubSecrets(report, secrets)
    }
    try FileDelete(outPath)
    FileAppend(report, outPath, "UTF-8")
    A_Clipboard := outPath
    TrayTip("Sanitized diagnostics exported to:`n" outPath "`n(Path copied to clipboard)", "PresenterSync Remote", 1)
    return outPath
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
    dlgRes := CreateThemedRemoteDialog("RemoteHelpWindow", "PresenterSync Remote v" UIConstants.APP_VERSION " - Setup & Help Guide", -1, -1, false)
    if IsObject(dlgRes.existing) {
        if (IsObject(state) && state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn)
            try state.refreshHelpFn.Call()
        return dlgRes.existing
    }
    helpGui := dlgRes.gui

    ; --- Persistent Top Search Bar ---
    helpGui.SetFont("s9 w600 norm", Theme.UiFont)
    AddThemedCtrl(helpGui, "Text", "x14 y15 w84 h22", "Search Help:")
    helpGui.SetFont("s9 w400 norm", Theme.UiFont)
    edRemSearch := AddThemedCtrl(helpGui, "Edit", "x102 y12 w416 h26")
    DllCall("SendMessage", "Ptr", edRemSearch.Hwnd, "UInt", 0x1501, "Ptr", 1, "WStr", "Search Remote HUD, Pointer Controls, Pairing Code, Tray menus...")
    btnRemClear := AddThemedCtrl(helpGui, "Button", "x526 y12 w68 h26", "Clear")
    AddThemedCtrl(helpGui, "Text", "x602 y15 w124 h22 Right", "Type to search", "Text", "muted")

    tabNames := ["Mic HUD Guide", "Setup Guide", "Help Search"]
    helpGui.SetFont("s9 w600 norm", Theme.UiFont)
    tabs := helpGui.Add("Tab2", "x14 y48 w712 h436 +0x0400 -0x0200", tabNames)
    tabs._tabNames := tabNames
    Theme.RegisterControl(helpGui, tabs, "Tab")

    ; --- TAB 1: REMOTE 1-TIER MIC HUD ANATOMY ---
    tabs.UseTab(1)
    helpGui.SetFont("s10 w700 norm", Theme.UiFont)
    AddThemedCtrl(helpGui, "Text", "x30 y94 w680 h22", "Interactive Remote 1-Tier Mic HUD Guide - Click any state or callout [1]-[4]:", "Text", "tabText")
    helpGui.SetFont("s9 w400 norm", Theme.UiFont)

    remAnatomy := GetRemoteHudAnatomyItems()
    selectedRemIdx := 1
    picRemHud := helpGui.Add("Picture", "x30 y120 w680 h194", "HBITMAP:" BuildRemoteHudDiagramBitmap(cfg, selectedRemIdx, 680, 194))

    remBtns := []
    for i, item in remAnatomy {
        bx := 30 + (i - 1) * 172
        remBtns.Push(AddThemedCtrl(helpGui, "Button", Format("x{} y322 w164 h28", bx), StrReplace(item.tag, "&", "&&"), "Button", "tabButton"))
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
    btnConn := AddThemedCtrl(helpGui, "Button", "x14 y494 w172 h34", "Change Connection...", "Button", "accent")
    btnKey := AddThemedCtrl(helpGui, "Button", "x198 y494 w164 h34", "Change Mute Key...")
    btnSc := AddThemedCtrl(helpGui, "Button", "x374 y494 w174 h34", "Edit App Shortcuts...")
    btnClose := AddThemedCtrl(helpGui, "Button", "x590 y494 w136 h34 Default", "Close")

    btnConn.OnEvent("Click", (*) => ShowRemoteConnectionUI(cfg, state, false))
    btnKey.OnEvent("Click", (*) => ChangeRemotePointerKeyUI(cfg, state))
    btnSc.OnEvent("Click", (*) => ChangeRemoteAppHotkeysUI(cfg, state))
    BindRemoteDialogClose(helpGui, "RemoteHelpWindow", false, (*) => (
        (IsObject(state) && state.HasOwnProp("refreshHelpFn")) ? (state.refreshHelpFn := "") : 0,
        helpGui._onThemeRefresh := ""
    ), btnClose)

    helpGui.Show("w740 h540 Center")
    btnClose.Focus()
    return helpGui
}

ShowRemoteAboutUI(cfg := "", state := "", *) {
    dlgRes := CreateThemedRemoteDialog("AboutRemoteWindow", "About PresenterSync Remote", 18, 16, false)
    if IsObject(dlgRes.existing)
        return dlgRes.existing
    aboutGui := dlgRes.gui

    iconSource := A_IsCompiled ? A_ScriptFullPath : (FileExist(A_ScriptDir "\assets\PresenterSyncRemote.ico") ? A_ScriptDir "\assets\PresenterSyncRemote.ico" : A_ScriptDir "\..\assets\PresenterSyncRemote.ico")
    if FileExist(iconSource)
        aboutGui.Add("Picture", "x203 y16 w64 h64", iconSource)

    aboutGui.SetFont("s16 w700 norm", Theme.UiFont)
    AddThemedCtrl(aboutGui, "Text", "x20 y88 w430 h30 Center", "PresenterSync Remote")

    aboutGui.SetFont("s10 w700 norm", Theme.UiFont)
    AddThemedCtrl(aboutGui, "Text", "x20 y120 w430 h20 Center", "Version " UIConstants.APP_VERSION "  -  Remote Companion Edition", "Text", "accent")

    aboutGui.SetFont("s9 w400 norm", Theme.UiFont)
    AddThemedCtrl(aboutGui, "Text", "x20 y142 w430 h20 Center", "Lightweight 1-Tier Mic Companion for Smart Boards & Secondary PCs", "Text", "muted")

    aboutGui.SetFont("s9 w600 norm", Theme.UiFont)
    AddThemedCtrl(aboutGui, "Text", "x20 y164 w430 h18 Center", "Created by Saabith Jiffry")

    aboutGui.SetFont("s9 w700 norm", Theme.UiFont)
    AddThemedCtrl(aboutGui, "Text", "x20 y192 w430 h18", "Included Remote Companion Capabilities & Scope:")

    aboutGui.SetFont("s9 w400 norm", Theme.UiFont)
    remCapsText := "Streamlined companion engineered strictly for Smart Boards & secondary PCs.`r`n`r`n"
        . "WHAT REMOTE INCLUDES:`r`n"
        . "• Dedicated 1-Tier LIVE / MUTED Mic HUD: Short-click or perimeter hold toggle, synced OBS recording timer, via OBS WebSocket v5 (Port 4455) OR Mode 2 Host Bridge.`r`n"
        . "• Host Deck Control & Failover: Remote Scene switching, Standby / `"BRB`" curtain, Touch Quick Deck, Countdown Timer, Stage Nudge, & Direct OBS :4455 failover w/ :4456 auto-repromotion.`r`n"
        . "• Zero-Config LAN & WAN Discovery: Scan Classroom LAN (UDP :4457 + mDNS failover) or Internet Pairing Code PS-XXXX-XXXX with safe heartbeat.`r`n"
        . "• Clicker & Mic Modes: Assign mute button (1-click Capture Keystroke), Cough Hold (>= 350ms), Push-to-Talk (hold to unmute), Clicker Tester & Ctrl+F12.`r`n"
        . "• Large-Board Visuals & Themes: 0.25x-5.0x (incl. 1.25x) scale, Dark/Light/System theme, 5 palettes + Custom Hex colors, monochrome icons, pulse & toast.`r`n"
        . "• Smart Ergonomics & System: Reorganized Tray menu, 14px Magnetic Snap, Auto-Dodge, Click-Through (hold Alt), Startup (OFF by default) & SHA-256 Updates.`r`n`r`n"
        . "STREAMLINED BY DESIGN (HOST-ONLY MODULES OMITTED):`r`n"
        . "• Omits multi-tier overlay panels, secondary desktop pills, CoreAudio voice bar, UIA meeting monitoring, Control Center, Setup Wizard, and PowerPoint forwarding."
    AddHelpGuideEdit(aboutGui, 20, 214, 430, 214, remCapsText)

    aboutGui.SetFont("s9 w400 norm", Theme.UiFont)
    gitBtn := AddThemedCtrl(aboutGui, "Button", "x20 y440 w208 h30", "GitHub Repo")
    gitBtn.OnEvent("Click", (*) => Run("https://github.com/SaabithJiffry/PresenterSync/"))

    updBtn := AddThemedCtrl(aboutGui, "Button", "x242 y440 w208 h30", "Check for Updates")
    updBtn.OnEvent("Click", (*) => CheckForUpdates(UIConstants.APP_VERSION, "", false, "PresenterSync_Remote.exe", cfg))

    helpBtn := AddThemedCtrl(aboutGui, "Button", "x20 y478 w208 h30", "Open Help Guide")
    closeBtn := AddThemedCtrl(aboutGui, "Button", "x242 y478 w208 h30 Default", "Close")
    CloseAbout := BindRemoteDialogClose(aboutGui, "AboutRemoteWindow", false, "", closeBtn)
    if IsObject(cfg)
        helpBtn.OnEvent("Click", (*) => (CloseAbout(), ShowRemoteHelpUI(cfg, state)))
    else
        helpBtn.Enabled := false

    vaultExtraH := 0
    if (IsSet(ArcadeVault) && IsObject(cfg))
        vaultExtraH := ArcadeVault.AttachAboutVaultSection(aboutGui, cfg, state, 20, 514, 430, true)

    aboutGui.Show("w470 h" (524 + vaultExtraH) " Center")
    closeBtn.Focus()
    return aboutGui
}

ShowRemoteConnectionUI(cfg, state, isInitialBoot := false) {
    dlgRes := CreateThemedRemoteDialog("OBS Remote Connection", "OBS Remote Connection", 20, 16, true)
    if IsObject(dlgRes.existing)
        return dlgRes.existing
    dlg := dlgRes.gui
    dlg._testSeq := 0
    dlg._testWs := ""
    dlg._testTimer := ""

    dlg.SetFont("s10 w600", Theme.UiFont)
    AddThemedCtrl(dlg, "Text", "xm w360", "Connect to Primary Streaming Host")
    dlg.SetFont("s9 w400", Theme.UiFont)
    AddThemedCtrl(dlg, "Text", "xm w360 y+4", "Choose Same Router (LAN) or Different Networks (Over the Internet):", "Text", "muted")

    dlg.SetFont("s9 w600", Theme.UiFont)
    AddThemedCtrl(dlg, "Text", "xm w360 y+8", "Saved Host Profiles (Room Switching):")
    dlg.SetFont("s9 w400", Theme.UiFont)
    ddlProfiles := AddThemedCtrl(dlg, "DropDownList", "xm w210", [])
    btnSaveProf := AddThemedCtrl(dlg, "Button", "x+6 yp w72 h24", "Save Profile")
    btnDelProf := AddThemedCtrl(dlg, "Button", "x+6 yp w66 h24", "Delete")

    RefreshProfilesCombo(selectName := "") {
        ddlProfiles.Delete()
        names := []
        for _, p in LoadSavedHostProfiles(cfg)
            names.Push(p.name)
        if (names.Length > 0) {
            ddlProfiles.Add(names)
            if (selectName != "") {
                for idx, nm in names {
                    if (nm = selectName) {
                        ddlProfiles.Choose(idx)
                        break
                    }
                }
            }
        }
    }
    RefreshProfilesCombo()

    dlg.SetFont("s9 w600", Theme.UiFont)
    AddThemedCtrl(dlg, "Text", "xm w360 y+10", "Network Mode:")
    dlg.SetFont("s9 w400", Theme.UiFont)
    netChoice := (cfg.NetworkMode = "Internet") ? 2 : 1
    ddlNetMode := AddThemedCtrl(dlg, "DropDownList", "xm w360 Choose" netChoice, [
        "1: Same Router / Local Wi-Fi or Ethernet (LAN - Default)",
        "2: Different Networks / Over the Internet (WAN Relay)"
    ])

    dlg.SetFont("s9 w600", Theme.UiFont)
    lblSession := AddThemedCtrl(dlg, "Text", "xm w360 y+10", "Host Bridge Session Code (Multi-Remote / Auto-Find):")
    dlg.SetFont("s9 w400", Theme.UiFont)
    editSession := AddThemedCtrl(dlg, "Edit", "xm w170", cfg.SessionPairingCode)
    DllCall("SendMessage", "Ptr", editSession.Hwnd, "UInt", 0x1501, "Ptr", 1, "WStr", "e.g. K7M-9P2")
    editBridgePort := AddThemedCtrl(dlg, "Edit", "x+8 yp w54", cfg.BridgePort)
    btnPairCode := AddThemedCtrl(dlg, "Button", "x+8 yp w120 h24", "Pair by Code")
    dlg._pairedToken := cfg.SessionToken
    dlg._pairedCode := cfg.SessionPairingCode
    dlg._pairedHostUuid := cfg.HasOwnProp("PairedHostUuid") ? cfg.PairedHostUuid : ""

    dlg.SetFont("s9 w600", Theme.UiFont)
    lblPair := AddThemedCtrl(dlg, "Text", "xm w360 y+10", "Internet Pairing Code (Optional Fallback / WAN):")
    dlg.SetFont("s9 w400", Theme.UiFont)
    editPair := AddThemedCtrl(dlg, "Edit", "xm w360", cfg.InternetPairingCode)

    dlg.SetFont("s9 w600", Theme.UiFont)
    lblRelayUrl := AddThemedCtrl(dlg, "Text", "xm w360 y+8", "Relay Server URL (ntfy, default https://ntfy.sh):")
    dlg.SetFont("s9 w400", Theme.UiFont)
    editRelayUrl := AddThemedCtrl(dlg, "Edit", "xm w360", GetEffectiveRelayBaseUrl(cfg))
    DllCall("SendMessage", "Ptr", editRelayUrl.Hwnd, "UInt", 0x1501, "Ptr", 1, "WStr", "https://ntfy.sh")

    dlg.SetFont("s9 w600", Theme.UiFont)
    lblHost := AddThemedCtrl(dlg, "Text", "xm w360 y+8", "LAN Host Address (e.g. STUDIO-PC.local, 192.168.1.50):")
    dlg.SetFont("s9 w400", Theme.UiFont)
    editHost := AddThemedCtrl(dlg, "Edit", "xm w270", cfg.HostAddress)
    btnScanLan := AddThemedCtrl(dlg, "Button", "x+8 yp w82 h24", "Scan LAN")

    lblPort := AddThemedCtrl(dlg, "Text", "xm w360 y+8", "OBS WebSocket Port:")
    editPort := AddThemedCtrl(dlg, "Edit", "xm w360", cfg.HostPort)

    AddThemedCtrl(dlg, "Text", "xm w360 y+8", "OBS WebSocket Password (Optional):")
    editPw := AddThemedCtrl(dlg, "Edit", "xm w360 Password", cfg.ObsPassword)

    AddThemedCtrl(dlg, "Text", "xm w360 y+8", "Exact Audio Source Name:")
    editMic := AddThemedCtrl(dlg, "Edit", "xm w360", cfg.TargetMicName)

    UpdateModeFields(*) {
        isInternet := (ddlNetMode.Value == 2)
        for _, ctrl in [lblSession, editSession, editBridgePort, btnPairCode, lblHost, editHost, btnScanLan, lblPort, editPort]
            ctrl.Enabled := !isInternet
        lblPair.Enabled := true
        editPair.Enabled := true
    }
    ddlNetMode.OnEvent("Change", UpdateModeFields)
    UpdateModeFields()

    statusTxt := AddThemedCtrl(dlg, "Text", "xm w360 y+10 Center", "Status: Ready to pair, test, or connect", "Text", "muted")

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
        codePairRes := PairRemoteWithHostBridge(Trim(editHost.Value), bpIn, Trim(editSession.Value), cfg.DeviceId, GetRemoteDisplayDeviceName(cfg))
        btnPairCode.Enabled := true
        if (!codePairRes.ok) {
            statusTxt.Value := "✕ " codePairRes.error
            return
        }
        ApplyPairResultToDialog(codePairRes)
        ddlNetMode.Choose(1)
        UpdateModeFields()
        statusTxt.Value := "✓ Paired to " (codePairRes.hostName != "" ? codePairRes.hostName : codePairRes.host) " (" codePairRes.host ":" codePairRes.bridgePort ")!"
    }
    btnPairCode.OnEvent("Click", PairByCodeAction)

    btnTest := dlg.Add("Button", "xm w130 h30 y+8", "Test Connection")
    btnPasteUri := dlg.Add("Button", "x+8 yp w118 h30", "Paste Pairing URI")
    btnGuide := dlg.Add("Button", "x+8 yp w96 h30", "Setup Guide")
    Theme.RegisterControl(dlg, btnTest, "Button")
    Theme.RegisterControl(dlg, btnPasteUri, "Button")
    Theme.RegisterControl(dlg, btnGuide, "Button")

    OnProfileSelected(*) {
        profSel := ddlProfiles.Text
        for _, p in LoadSavedHostProfiles(cfg) {
            if (p.name = profSel) {
                editHost.Value := p.host
                editBridgePort.Value := p.bridgePort
                editPort.Value := p.obsPort
                editSession.Value := p.code
                editPair.Value := p.wanCode
                editPw.Value := p.obsPass
                ddlNetMode.Choose(p.networkMode = "Internet" ? 2 : 1)
                UpdateModeFields()
                statusTxt.Value := "Loaded profile '" p.name "'"
                break
            }
        }
    }
    ddlProfiles.OnEvent("Change", OnProfileSelected)

    SaveProfileAction(*) {
        defName := Trim(editHost.Value) != "" ? Trim(editHost.Value) : "Room 1"
        ib := InputBox("Enter a name for this host profile (e.g. Lecture Hall A):", "Save Host Profile", "w320 h130", defName)
        if (ib.Result != "OK" || Trim(ib.Value) = "")
            return
        ok := SaveHostProfile(cfg, Trim(ib.Value), {
            host: Trim(editHost.Value),
            bridgePort: Trim(editBridgePort.Value),
            obsPort: Trim(editPort.Value),
            code: Trim(editSession.Value),
            wanCode: Trim(editPair.Value),
            obsPass: editPw.Value,
            networkMode: (ddlNetMode.Value == 2 ? "Internet" : "LAN")
        })
        if (ok) {
            RefreshProfilesCombo(Trim(ib.Value))
            try BuildRemoteTrayMenu(cfg, state)
            statusTxt.Value := "✓ Saved profile '" Trim(ib.Value) "'"
        }
    }
    btnSaveProf.OnEvent("Click", SaveProfileAction)

    DeleteProfileAction(*) {
        sel := Trim(ddlProfiles.Text)
        if (sel = "")
            return
        if (DeleteHostProfile(cfg, sel)) {
            RefreshProfilesCombo()
            try BuildRemoteTrayMenu(cfg, state)
            statusTxt.Value := "Deleted profile '" sel "'"
        }
    }
    btnDelProf.OnEvent("Click", DeleteProfileAction)

    PastePairingUriAction(*) {
        parsed := ParsePairingUri(A_Clipboard)
        if (!parsed.ok) {
            statusTxt.Value := "✕ " parsed.error
            return
        }
        if (parsed.host != "")
            editHost.Value := parsed.host
        editBridgePort.Value := parsed.bridgePort
        editPort.Value := parsed.obsPort
        if (parsed.code != "")
            editSession.Value := parsed.code
        if (parsed.obsPass != "")
            editPw.Value := parsed.obsPass
        if (parsed.wanCode != "")
            editPair.Value := parsed.wanCode
        ddlNetMode.Choose((parsed.host = "" && parsed.wanCode != "") ? 2 : 1)
        UpdateModeFields()
        statusTxt.Value := "✓ Parsed pairing URI (" (parsed.host != "" ? parsed.host ":" parsed.bridgePort : parsed.wanCode) ")"
    }
    btnPasteUri.OnEvent("Click", PastePairingUriAction)

    btnTest.OnEvent("Click", (*) => TestConnectionAction(dlg, btnTest, editHost.Value, editPort.Value, editPw.Value, statusTxt, (ddlNetMode.Value == 2 ? "Internet" : "LAN"), editPair.Value, editRelayUrl.Value, editBridgePort.Value))
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
        cfg.RelayBaseUrl := NormalizeRelayBaseUrl(editRelayUrl.Value)
        cfg.HostAddress := h
        cfg.HostPort := String(Integer(p))
        cfg.ObsPassword := editPw.Value
        cfg.TargetMicName := m
        cfg.FirstRun := false

        SaveRemoteConnectionSettingsToIni(cfg)

        CleanupDialog(false)

        ; Disconnect existing and trigger fresh failover connection
        StopRemoteSessionTimers(state, true)
        state.animSeq += 1
        state.connGen += 1
        CloseRemoteWebSocket(state, false)
        state.obsConnected := false
        state.usingBridge := false
        state.usingDirectObsFallback := false
        state.connStatus := "searching"
        state.activeHost := ""
        state.candidateIndex := 1
        state.usingRelayFallback := false
        state.candidates := []
        RefreshRemoteMicHudAlpha(cfg, state)
        state.NotifyTrayStatus()
        SetTimer state.reconnectTimerFn, -20
    }

    btnSave.OnEvent("Click", SaveAndConnect)

    dlg.OnEvent("Close", (*) => CleanupDialog(isInitialBoot))
    dlg.OnEvent("Escape", (*) => CleanupDialog(isInitialBoot))

    dlg.Show("AutoSize Center")
    return dlg
}

TestConnectionAction(dlg, btnTest, hostStr, portStr, pwStr, statusLabel, netMode := "LAN", pairingCode := "", relayBaseUrl := "https://ntfy.sh", bridgePortStr := "4456") {
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
        normRelayBase := NormalizeRelayBaseUrl(relayBaseUrl)
        statusLabel.Value := "Testing Internet Relay (" pairClean ")..."
        topic := GetInternetRelayTopic(pairClean)
        wsUrl := BuildRelayWsUrl(normRelayBase, topic)
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
            pkt := ParseRelayEnvelope(msg, pairClean, pwStr, "", true)
            if (IsObject(pkt)) {
                if (!pkt.ok) {
                    if (pkt.authError)
                        FinishTest("✕ Auth/Encryption mismatch on Internet Relay (Check OBS Password)")
                    return
                }
                if (pkt.src = "host") {
                    if (pkt.cmd = "auth_error" || pkt.auth != expectedTok) {
                        FinishTest("✕ Auth failed on Internet Relay (Check OBS Password)")
                    } else if (pkt.cmd = "state") {
                        FinishTest("✓ Connected to Primary Host via Internet Relay (" pairClean ")!")
                    }
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
            syncPkt := FormatEncryptedRelayPacket("remote", "sync_req", "0", pairClean, pwStr)
            if (syncPkt = "")
                syncPkt := FormatRelayPacket("remote", "sync_req", "0", expectedTok)
            PublishInternetRelayPacket(topic, syncPkt, normRelayBase)
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
    firstTarget := endpoints[1]
    bpClean := Trim(String(bridgePortStr))
    bpNum := (IsInteger(bpClean) && Integer(bpClean) >= 1 && Integer(bpClean) <= 65535) ? Integer(bpClean) : 4456
    dualRes := ProbeRemoteDualEndpoints(firstTarget.host, bpNum, Integer(portClean))

    TryNextCandidate() {
        ClearProbeTimer()
        if (IsCancelled() || testSuccess)
            return
        if (currentIndex > endpoints.Length) {
            FinishTest("✕ " dualRes.summary " (Check IP, Port & Firewall)")
            return
        }

        target := endpoints[currentIndex]
        statusLabel.Value := "Testing " target.raw " (" currentIndex "/" endpoints.Length ") | " dualRes.summary
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
                    FinishTest("✓ Connected to " target.raw " | " dualRes.summary)
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
                if (IsCancelled()) {
                    SafeCloseWebSocketDeferred(probeWs)
                    return
                }
                dlg._testWs := probeWs
            } catch {
                ClearProbeTimer()
                if (IsObject(probeWs))
                    SafeCloseWebSocketDeferred(probeWs)
                if (IsObject(dlg._testWs))
                    SafeCloseWebSocketDeferred(dlg._testWs)
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
