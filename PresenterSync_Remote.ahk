; ==============================================================================
; Script: PresenterSync_Remote
; Description: Standalone companion client for Smart Boards & secondary devices.
;              Provides a single-pill remote mute HUD and transmits clicker
;              mute keystrokes back to OBS Studio over the local network.
; Version: 4.1.1
; Author: Saabith Jiffry
; License: MIT
; ==============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
;@Ahk2Exe-SetMainIcon PresenterSyncRemote.ico
;@Ahk2Exe-SetProductName PresenterSync Remote
;@Ahk2Exe-SetDescription PresenterSync Remote - Smart Board Companion Client
;@Ahk2Exe-SetVersion 4.1.1.0
ProcessSetPriority "High"

#Include <WebSocket>
#Include <Crypto>
#Include <Gdip>
#Include <OBS_Network>
#Include <GUI_Config>

Gdip.Startup()
OnExit((*) => (Theme.Shutdown(), Gdip.Shutdown()))

if (!A_IsCompiled && FileExist(A_ScriptDir "\PresenterSyncRemote.ico"))
    try TraySetIcon(A_ScriptDir "\PresenterSyncRemote.ico")
A_IconTip := "PresenterSync Remote v" UIConstants.APP_VERSION

; === CONFIGURATION & STATE ===
class RemoteConfig {
    ConfigFile := ""
    NetworkMode := "LAN"
    EnableRelayFallback := true
    InternetPairingCode := ""
    HostAddress := "127.0.0.1"
    HostPort := "4455"
    ObsPassword := ""
    TargetMicName := "Mic/Aux"
    HeartbeatSeconds := 30

    HwMuteHotkey := "b"
    EnablePointerMute := true
    EnablePushToMute := false
    PptHotkey := "^F12"
    ExitHotkey := "!+F12"

    ShowIndicator := true
    ThemeMode := "System"
    HudColorPreset := "Standard"
    ShowText := false
    MonoIcon := false
    SleekCorners := false
    AggressivePulse := false
    EnableAudioCue := false
    EnableMuteToast := false
    EnableHudClickActions := true
    EnableMagneticSnap := true
    HudClickThrough := false
    HudAutoDodge := false
    OpacityLevel := 220
    IndicatorScale := 1.0
    FirstRun := true
    IsMuted := false
    StartWithWindows := false

    savedX := "Default"
    savedY := "Default"

    __New(filePath := "") {
        this.ConfigFile := (filePath != "") ? filePath : A_ScriptDir "\PresenterSync_Remote.ini"
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
        rawNetMode := StrLower(Trim(this.Read("Connection", "NetworkMode", "LAN")))
        this.NetworkMode := (rawNetMode = "internet") ? "Internet" : "LAN"
        this.EnableRelayFallback := this.ReadBool("Connection", "EnableRelayFallback", 1)
        this.InternetPairingCode := Trim(this.Read("Connection", "InternetPairingCode", ""))
        this.HostAddress := this.Read("Connection", "HostAddress", "127.0.0.1")
        rawPort := Trim(this.Read("Connection", "HostPort", "4455"))
        this.HostPort := (IsInteger(rawPort) && Integer(rawPort) >= 1 && Integer(rawPort) <= 65535) ? String(Integer(rawPort)) : "4455"
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

        this.ShowText := this.ReadBool("Appearance", "ShowText", 0)
        this.MonoIcon := this.ReadBool("Appearance", "MonoIcon", 0)
        this.SleekCorners := this.ReadBool("Appearance", "SleekCorners", 0)
        this.AggressivePulse := this.ReadBool("Appearance", "AggressivePulse", 0)
        this.EnableAudioCue := this.ReadBool("Appearance", "EnableAudioCue", 0)
        this.EnableMuteToast := this.ReadBool("Appearance", "EnableMuteToast", 0)
        this.EnableHudClickActions := this.ReadBool("Appearance", "EnableHudClickActions", 1)
        this.EnableMagneticSnap := this.ReadBool("Appearance", "EnableMagneticSnap", 1)
        this.HudClickThrough := this.ReadBool("Appearance", "HudClickThrough", 0)
        this.HudAutoDodge := this.ReadBool("Appearance", "HudAutoDodge", 0)
        this.OpacityLevel := this.ReadInt("Appearance", "OpacityLevel", UIConstants.OPACITY_FROSTED)
        if (this.OpacityLevel < 1 || this.OpacityLevel > 255)
            this.OpacityLevel := UIConstants.OPACITY_FROSTED

        this.IndicatorScale := this.ReadFloat("Appearance", "IndicatorScale", 1.0)
        if (this.IndicatorScale <= 0.0 || this.IndicatorScale > 10.0)
            this.IndicatorScale := 1.0

        this.FirstRun := this.ReadBool("Settings", "FirstRun", 1)
        this.IsMuted := this.ReadBool("Settings", "IsMuted", 0)
        this.StartWithWindows := this.ReadBool("Settings", "StartWithWindows", 0)

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
        this.OpacityLevel := UIConstants.OPACITY_FROSTED
        this.IndicatorScale := 1.0
        this.ThemeMode := "System"
        this.HudColorPreset := "Standard"
        Theme.SetMode("System")

        this.WriteBool("Appearance", "ShowText", false)
        this.WriteBool("Appearance", "MonoIcon", false)
        this.WriteBool("Appearance", "SleekCorners", false)
        this.WriteBool("Appearance", "AggressivePulse", false)
        this.WriteBool("Appearance", "EnableAudioCue", false)
        this.WriteBool("Appearance", "EnableMuteToast", false)
        this.WriteBool("Appearance", "EnableHudClickActions", true)
        this.WriteBool("Appearance", "EnableMagneticSnap", true)
        this.WriteBool("Appearance", "HudClickThrough", false)
        this.WriteBool("Appearance", "HudAutoDodge", false)
        this.Write("Appearance", "OpacityLevel", this.OpacityLevel)
        this.Write("Appearance", "IndicatorScale", this.IndicatorScale)
        this.Write("Appearance", "ThemeMode", this.ThemeMode)
        this.Write("Appearance", "HudColorPreset", this.HudColorPreset)
    }
}

class RemoteState {
    obsWs := ""
    obsConnected := false
    connStatus := "searching"
    activeHost := ""
    candidateIndex := 1
    candidates := []
    usingRelayFallback := false

    isMuted := false
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
    rebuildTrayFn := ""
    refreshHelpFn := ""
    refreshHudFn := ""
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
        this.pointerHotIfFn := CheckRemotePointerEnable.Bind(cfg)

        this.ComputeDimensions(cfg)
    }

    ComputeDimensions(cfg) {
        this.colors := UIConstants.GetColorPalette(cfg.HasOwnProp("HudColorPreset") ? cfg.HudColorPreset : "Standard")
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
AppState.rebuildTrayFn := BuildRemoteTrayMenu.Bind(AppConfig, AppState)
AppState.refreshHudFn := RefreshRemoteHudAppearance.Bind(AppConfig, AppState)

; === INITIALIZE HUD & HOTKEYS ===
InitRemoteHUD(AppConfig, AppState)
BuildRemoteTrayMenu(AppConfig, AppState)
RegisterRemotePointerHotkey(AppConfig, AppState)
RegisterRemoteAppHotkeys(AppConfig, AppState)

; === FIRST-RUN / CONNECTION PROMPT ===
if (AppConfig.FirstRun || (AppConfig.NetworkMode = "Internet" ? (AppConfig.InternetPairingCode = "") : (AppConfig.HostAddress = ""))) {
    ShowRemoteConnectionUI(AppConfig, AppState, true)
} else {
    ; Start network connection
    SetTimer AppState.reconnectTimerFn, -100
}

; --- REMOTE NETWORKING ENGINE ---

GetRemoteEffectiveAlpha(state) {
    return state.obsConnected ? state.baseAlpha : Max(60, Round(state.baseAlpha * 0.4))
}

ConnectToRemoteOBS(cfg, state) {
    SetTimer state.reconnectTimerFn, 0
    SetTimer state.heartbeatTimerFn, 0

    if (state.obsConnected)
        return

    state.connStatus := "searching"
    state.activeHost := ""

    if IsObject(state.obsWs) {
        try state.obsWs.shutdown()
        state.obsWs := ""
    }

    if (IsRemoteUsingInternetChannel(cfg, state)) {
        pairCode := Trim(cfg.InternetPairingCode)
        if (pairCode = "") {
            if (IsObject(state.rebuildTrayFn))
                try state.rebuildTrayFn.Call()
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
            keepAliveMs := Max(10000, cfg.HeartbeatSeconds * 1000)
            SetTimer state.heartbeatTimerFn, keepAliveMs
            state.currentAlpha := state.baseAlpha
            if IsObject(state.MicGui)
                ApplyMicAppearance(cfg, state)
            if (state.isMuted && cfg.ShowIndicator) {
                state.breathDir := cfg.AggressivePulse ? -UIConstants.PULSE_STEP_AGGRESSIVE : -UIConstants.PULSE_STEP_NORMAL
                SetTimer state.breathTimerFn, (cfg.AggressivePulse ? UIConstants.PULSE_INTERVAL_AGGRESSIVE : UIConstants.PULSE_INTERVAL_NORMAL)
            }
            authTok := GetInternetRelayAuthToken(pairCode, cfg.ObsPassword)
            mockWs := (state.HasOwnProp("relayMockWs") && IsObject(state.relayMockWs)) ? state.relayMockWs : ""
            PublishInternetRelayPacket(topic, FormatRelayPacket("remote", "sync_req", "0", authTok), "https://ntfy.sh", mockWs)
            if (IsObject(state.rebuildTrayFn))
                try state.rebuildTrayFn.Call()
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

    if (state.candidates.Length == 0 || state.candidateIndex > state.candidates.Length) {
        state.candidates := ParseCandidateEndpoints(cfg.HostAddress, cfg.HostPort)
        state.candidateIndex := 1
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

    try {
        state.obsWs := WebSocket(wsUrl, {
            message: HandleRemoteObsMessage.Bind(cfg, state, candidate),
            close: HandleRemoteObsClose.Bind(cfg, state, candidate)
        }, true, "", 2000) ; 2000ms connection timeout for fast failover
    } catch {
        state.obsWs := ""
        SetTimer state.breathTimerFn, 0
        if (IsObject(state.MicGui)) {
            state.currentAlpha := GetRemoteEffectiveAlpha(state)
            ApplyMicAppearance(cfg, state)
        }
        FailoverToNextCandidate(cfg, state)
    }
}

FailoverToNextCandidate(cfg, state) {
    if (cfg.NetworkMode = "Internet") {
        state.usingRelayFallback := false
        SetTimer state.reconnectTimerFn, -2500
        if (IsObject(state.rebuildTrayFn))
            try state.rebuildTrayFn.Call()
        return
    }
    if (state.HasOwnProp("usingRelayFallback") && state.usingRelayFallback) {
        state.usingRelayFallback := false
        state.candidateIndex := 1
        SetTimer state.reconnectTimerFn, -2500
        if (IsObject(state.rebuildTrayFn))
            try state.rebuildTrayFn.Call()
        return
    }
    state.candidateIndex += 1
    if (state.candidateIndex <= state.candidates.Length) {
        ; Probe next candidate immediately
        SetTimer state.reconnectTimerFn, -50
    } else {
        ; All LAN candidates exhausted: seamlessly bridge via Internet Relay if configured (e.g., Mode 2 Host without OBS)
        state.candidateIndex := 1
        if (ShouldRemoteFallbackToRelay(cfg, state)) {
            state.usingRelayFallback := true
            SetTimer state.reconnectTimerFn, -100
        } else {
            SetTimer state.reconnectTimerFn, -2500
        }
    }
    if (IsObject(state.rebuildTrayFn))
        try state.rebuildTrayFn.Call()
}

HandleRemoteObsClose(cfg, state, candidate, ws, status, reason) {
    if IsObject(ws)
        try ws.shutdown()
    if (IsObject(ws) && IsObject(state.obsWs) && state.obsWs != ws)
        return
    if (state.obsWs == ws)
        state.obsWs := ""

    wasConnected := state.obsConnected
    state.obsConnected := false
    state.activeHost := ""
    SetTimer state.heartbeatTimerFn, 0
    SetTimer state.breathTimerFn, 0
    state.animSeq += 1

    ; Visual feedback on HUD: Dim while disconnected
    if (IsObject(state.MicGui)) {
        state.currentAlpha := GetRemoteEffectiveAlpha(state)
        ApplyMicAppearance(cfg, state)
    }

    if (!wasConnected && status == 4009) {
        state.connStatus := "auth_failed"
        SetTimer state.reconnectTimerFn, 0
        if (IsObject(state.rebuildTrayFn))
            try state.rebuildTrayFn.Call()
        TrayTip("OBS WebSocket authentication failed. Check password in Change OBS Connection.", "PresenterSync Remote", 3)
        return
    }

    state.connStatus := "searching"
    if (IsObject(state.rebuildTrayFn))
        try state.rebuildTrayFn.Call()

    FailoverToNextCandidate(cfg, state)
}

HandleRemoteObsMessage(cfg, state, candidate, ws, rawMsg) {
    if (IsObject(ws) && IsObject(state.obsWs) && ws != state.obsWs)
        return
    msg := (Type(rawMsg) == "Buffer") ? StrGet(rawMsg, "UTF-8") : String(rawMsg)

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
                try ws.shutdown()
            if (state.obsWs == ws)
                state.obsWs := ""
            if (IsObject(state.MicGui)) {
                state.currentAlpha := GetRemoteEffectiveAlpha(state)
                ApplyMicAppearance(cfg, state)
            }
            if (IsObject(state.rebuildTrayFn))
                try state.rebuildTrayFn.Call()
            TrayTip("Internet Relay authentication failed. Check password in Change OBS Connection.", "PresenterSync Remote", 3)
            return
        }
        if (pkt.cmd = "state") {
            if (!state.obsConnected || state.connStatus != "connected") {
                state.obsConnected := true
                state.connStatus := "connected"
                state.activeHost := candidate.raw
                state.currentAlpha := state.baseAlpha
                if IsObject(state.MicGui)
                    ApplyMicAppearance(cfg, state)
                if (IsObject(state.rebuildTrayFn))
                    try state.rebuildTrayFn.Call()
            }
            SyncRemoteMuteState(cfg, state, (pkt.data = "1" || pkt.data = "true"))
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
            salt := matchSalt[1]
            challenge := matchChallenge[1]

            secret := HashSHA256_Base64(cfg.ObsPassword . salt)
            authResponse := HashSHA256_Base64(secret . challenge)
            authString := ',"authentication":"' authResponse '"'
        }

        ; Identify for standard events (excluding 20Hz volume meters)
        identifyJson := '{"op":1,"d":{"rpcVersion":1,"eventSubscriptions":2047' authString '}}'
        TrySendWsText(ws, identifyJson)
    }
    else if (opCode == 2) {
        ; Op 2: Identified - Connection and Auth Succeeded!
        SetTimer state.reconnectTimerFn, 0
        state.obsConnected := true
        state.connStatus := "connected"
        state.activeHost := candidate.raw

        ; Start keep-alive heartbeat timer (prevents Wi-Fi radio sleep / router conntrack drops)
        keepAliveMs := Max(10000, cfg.HeartbeatSeconds * 1000)
        SetTimer state.heartbeatTimerFn, keepAliveMs

        ; Restore base alpha & query initial mic mute status
        state.currentAlpha := state.baseAlpha
        if IsObject(state.MicGui)
            ApplyMicAppearance(cfg, state)
        escMic := EscapeJsonStr(cfg.TargetMicName)
        SendObsRequest(ws, "GetInputMute", "InitRemoteMute", '{"inputName":"' escMic '"}')

        if (IsObject(state.rebuildTrayFn))
            try state.rebuildTrayFn.Call()
    }
    else if (opCode == 5) {
        ; Op 5: Event payload
        if (RegExMatch(msg, '"eventType"\s*:\s*"InputMuteStateChanged"')) {
            if (RegExMatch(msg, '"inputName"\s*:\s*"((?:[^"\\]|\\.)*)"', &matchInput) && UnescapeJsonStr(matchInput[1]) == cfg.TargetMicName) {
                if (RegExMatch(msg, '"inputMuted"\s*:\s*(true|false)', &matchMuted)) {
                    if (state.connStatus = "mic_error") {
                        state.connStatus := "connected"
                        if (IsObject(state.rebuildTrayFn))
                            try state.rebuildTrayFn.Call()
                    }
                    isMutedNow := (matchMuted[1] == "true")
                    SyncRemoteMuteState(cfg, state, isMutedNow)
                }
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
        ; Op 7: Request Response
        if (InStr(msg, '"requestId":"InitRemoteMute"') || InStr(msg, '"requestId": "InitRemoteMute"')) {
            if (RegExMatch(msg, '"result"\s*:\s*false')) {
                state.connStatus := "mic_error"
                SetTimer state.breathTimerFn, 0
                state.currentAlpha := state.baseAlpha
                ApplyMicAppearance(cfg, state)
                if (IsObject(state.rebuildTrayFn))
                    try state.rebuildTrayFn.Call()
                TrayTip("Audio source '" cfg.TargetMicName "' was not found in OBS Studio.", "PresenterSync Remote", 2)
            } else if (RegExMatch(msg, '"inputMuted"\s*:\s*(true|false)', &matchMuted)) {
                state.connStatus := "connected"
                isMutedNow := (matchMuted[1] == "true")
                state.isMuted := isMutedNow
                cfg.IsMuted := isMutedNow
                cfg.WriteBool("Settings", "IsMuted", isMutedNow)
                state.currentAlpha := state.baseAlpha
                ApplyMicAppearance(cfg, state)
                if (state.isMuted && cfg.ShowIndicator) {
                    state.breathDir := cfg.AggressivePulse ? -UIConstants.PULSE_STEP_AGGRESSIVE : -UIConstants.PULSE_STEP_NORMAL
                    SetTimer state.breathTimerFn, (cfg.AggressivePulse ? UIConstants.PULSE_INTERVAL_AGGRESSIVE : UIConstants.PULSE_INTERVAL_NORMAL)
                } else {
                    SetTimer state.breathTimerFn, 0
                }
                if (IsObject(state.rebuildTrayFn))
                    try state.rebuildTrayFn.Call()
            }
        }
        else if (InStr(msg, '"requestId":"RemoteClickerMute"') || InStr(msg, '"requestId": "RemoteClickerMute"')) {
            if (RegExMatch(msg, '"result"\s*:\s*false')) {
                if (state.connStatus != "mic_error") {
                    state.connStatus := "mic_error"
                    if (IsObject(state.rebuildTrayFn))
                        try state.rebuildTrayFn.Call()
                }
                ToolTip "PresenterSync Remote: Audio source '" cfg.TargetMicName "' not found in OBS"
                SetTimer RemoveToolTip, -2500
            } else if (state.connStatus = "mic_error" && RegExMatch(msg, '"result"\s*:\s*true')) {
                state.connStatus := "connected"
                if (IsObject(state.rebuildTrayFn))
                    try state.rebuildTrayFn.Call()
            }
        }
    }
}

RemoteHeartbeatTick(cfg, state) {
    if (!state.obsConnected || !IsObject(state.obsWs))
        return
    if (IsRemoteUsingInternetChannel(cfg, state)) {
        topic := GetInternetRelayTopic(cfg.InternetPairingCode)
        authTok := GetInternetRelayAuthToken(cfg.InternetPairingCode, cfg.ObsPassword)
        mockWs := (state.HasOwnProp("relayMockWs") && IsObject(state.relayMockWs)) ? state.relayMockWs : ""
        PublishInternetRelayPacket(topic, FormatRelayPacket("remote", "sync_req", "0", authTok), "https://ntfy.sh", mockWs)
        return
    }
    ; Lightweight request to keep TCP session alive
    SendObsRequest(state.obsWs, "GetVersion", "KeepAlive")
}

SyncRemoteMuteState(cfg, state, newMuted) {
    if (state.isMuted != newMuted) {
        state.isMuted := newMuted
        cfg.IsMuted := newMuted
        cfg.WriteBool("Settings", "IsMuted", newMuted)
        PlayMuteAnimation(cfg, state)
        if (cfg.HasOwnProp("EnableAudioCue") && cfg.EnableAudioCue)
            PlayMuteAudioCue(newMuted)
        if (cfg.HasOwnProp("EnableMuteToast") && cfg.EnableMuteToast)
            ShowMuteToast(newMuted)
    }
}

; --- REMOTE CLICKER MUTE TRANSMISSION ---

RemoveToolTip() {
    ToolTip()
}

OnRemoteClickerMute(cfg, state, *) {
    if (!cfg.EnablePointerMute)
        return

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
        if (DispatchRemoteMuteToggle(cfg, state)) {
            if (WaitPushToMuteRelease(cfg, cfg.HwMuteHotkey, state.HasOwnProp("keyWaitFn") ? state.keyWaitFn : "")) {
                DispatchRemoteMuteToggle(cfg, state)
                lastTick := A_TickCount
            }
        }
    } finally {
        inHold := false
    }
}

CheckRemotePointerEnable(cfg, ThisHotkey) {
    return cfg.EnablePointerMute && (Theme.OpenWindows.Count == 0 || !Theme.OpenWindows.Has(WinExist("A")))
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
    state.MicGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000 -DPIScale")
    ApplyMicAppearance(cfg, state)

    if (cfg.ShowIndicator) {
        state.MicGui.Show(Format("NoActivate x{} y{} w{} h{}", state.savedX, state.savedY, state.baseWidth, state.baseHeight))
        if (state.isMuted && state.obsConnected)
            SetTimer state.breathTimerFn, (cfg.AggressivePulse ? UIConstants.PULSE_INTERVAL_AGGRESSIVE : UIConstants.PULSE_INTERVAL_NORMAL)
    }
    ApplyHudClickThroughStyle(cfg, state)
    UpdateAutoDodgeTimer(cfg, state)

    OnMessage(0x0201, WM_REMOTE_LBUTTONDOWN.Bind(cfg, state))
    OnMessage(0x0205, WM_REMOTE_RBUTTONUP.Bind(state))
    OnMessage(0x02E0, WM_REMOTE_DPICHANGED.Bind(cfg, state))
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
    OnRemoteClickerMute(cfg, state)
    return true
}

WM_REMOTE_RBUTTONUP(state, wParam, lParam, msg, hwnd) {
    if (IsObject(state.MicGui) && hwnd == state.MicGui.Hwnd)
        A_TrayMenu.Show()
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
    UpdateAutoDodgeTimer(cfg, state)
}

; --- TRAY MENU & COSMETIC ACTIONS ---

BuildRemoteTrayMenu(cfg, state) {
    Theme.ApplyMenuTheme()
    A_TrayMenu.Delete()

    ; 1. STATUS LINE
    if (state.connStatus = "auth_failed")
        statusText := "✕ Auth Failed (Check Password)"
    else if (state.obsConnected && state.connStatus = "mic_error")
        statusText := "⚠ Connected (Mic Not Found): " state.activeHost
    else if (state.obsConnected)
        statusText := "● Connected: " state.activeHost
    else
        statusText := "○ Searching for OBS Host..."
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

    AppearanceMenu.Add()

    OpacityMenu := Menu()
    OpacityMenu.Add("Solid (100%)", SetRemoteOpacity.Bind(cfg, state, UIConstants.OPACITY_SOLID))
    OpacityMenu.Add("Frosted (85%)", SetRemoteOpacity.Bind(cfg, state, UIConstants.OPACITY_FROSTED))
    OpacityMenu.Add("Ghost (50%)", SetRemoteOpacity.Bind(cfg, state, UIConstants.OPACITY_GHOST))
    if (cfg.OpacityLevel == UIConstants.OPACITY_SOLID)
        OpacityMenu.Check("Solid (100%)")
    else if (cfg.OpacityLevel == UIConstants.OPACITY_FROSTED)
        OpacityMenu.Check("Frosted (85%)")
    else if (cfg.OpacityLevel == UIConstants.OPACITY_GHOST)
        OpacityMenu.Check("Ghost (50%)")
    AppearanceMenu.Add("Transparency Level", OpacityMenu)

    ScaleMenu := Menu()
    ScaleOptions := [
        {label: "Tiny (x0.25)", val: 0.25},
        {label: "Small (x0.5)", val: 0.5},
        {label: "Normal (x1.0)", val: 1.0},
        {label: "Large (x1.5)", val: 1.5},
        {label: "Huge (x2.0)", val: 2.0},
        {label: "Massive (x2.5)", val: 2.5},
        {label: "Colossal (x3.0)", val: 3.0},
        {label: "Gigantic (x5.0)", val: 5.0}
    ]
    for opt in ScaleOptions {
        ScaleMenu.Add(opt.label, SetRemoteScale.Bind(cfg, state, opt.val))
        if (Abs(cfg.IndicatorScale - opt.val) < 0.001)
            ScaleMenu.Check(opt.label)
    }
    AppearanceMenu.Add("Indicator Scale", ScaleMenu)

    ThemeMenu := Menu()
    ThemeMenu.Add("Follow System", SetRemoteTheme.Bind(cfg, state, "System"))
    ThemeMenu.Add("Dark Mode", SetRemoteTheme.Bind(cfg, state, "Dark"))
    ThemeMenu.Add("Light Mode", SetRemoteTheme.Bind(cfg, state, "Light"))
    if (cfg.ThemeMode = "Dark")
        ThemeMenu.Check("Dark Mode")
    else if (cfg.ThemeMode = "Light")
        ThemeMenu.Check("Light Mode")
    else
        ThemeMenu.Check("Follow System")
    AppearanceMenu.Add("App Theme", ThemeMenu)

    PresetMenu := Menu()
    for pName in GetHudColorPresetNames() {
        PresetMenu.Add(pName, SetHudColorPreset.Bind(cfg, state, pName))
        if (cfg.HudColorPreset = pName)
            PresetMenu.Check(pName)
    }
    AppearanceMenu.Add("HUD Color Preset", PresetMenu)

    AppearanceMenu.Add()
    AppearanceMenu.Add("Reset Indicator Position", ResetRemotePositionAction.Bind(cfg, state))
    AppearanceMenu.Add("Restore Default Appearance", ResetRemoteAppearanceAction.Bind(cfg, state))

    A_TrayMenu.Add("Indicator Appearance", AppearanceMenu)
    A_TrayMenu.Add()

    ; 4. POINTER & CONNECTION SETTINGS
    PointerMenu := Menu()
    PointerMenu.Add("Enable Pointer Mute", ToggleRemotePointerMute.Bind(cfg, state))
    if (cfg.EnablePointerMute)
        PointerMenu.Check("Enable Pointer Mute")
    PointerMenu.Add("Enable Cough / Push-to-Mute (Hold)", TogglePushToMute.Bind(cfg, state))
    if (cfg.EnablePushToMute)
        PointerMenu.Check("Enable Cough / Push-to-Mute (Hold)")
    PointerMenu.Add("Change Pointer Mute Button...", (*) => ChangeRemotePointerKeyUI(cfg, state))
    PointerMenu.Add("Launch Clicker Tester...", (*) => ShowPointerTester())
    A_TrayMenu.Add("Pointer Controls", PointerMenu)

    A_TrayMenu.Add("Change OBS Connection...", (*) => ShowRemoteConnectionUI(cfg, state, false))
    A_TrayMenu.Add("Change App Shortcuts...", (*) => ChangeRemoteAppHotkeysUI(cfg, state))
    A_TrayMenu.Add("Start with Windows", ToggleStartWithWindows.Bind(cfg, state))
    if (cfg.StartWithWindows)
        A_TrayMenu.Check("Start with Windows")
    A_TrayMenu.Add()

    ; 5. HELP, SAFETY & EXIT
    A_TrayMenu.Add("Help && Setup Guide...", (*) => ShowRemoteHelpUI(cfg, state))
    A_TrayMenu.Add("About PresenterSync Remote...", (*) => ShowRemoteAboutUI(cfg, state))
    A_TrayMenu.Add("Check for Updates...", (*) => CheckForUpdates(UIConstants.APP_VERSION, "", false))
    A_TrayMenu.Add("Suspend All Hotkeys", ToggleRemoteSuspend)
    if (Theme.SuspendLockCount > 0 ? Theme.WasSuspendedBeforeDialogs : A_IsSuspended)
        A_TrayMenu.Check("Suspend All Hotkeys")
    A_TrayMenu.Add("Exit PresenterSync Remote", ExitRemoteApp)

    if (IsObject(state) && state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn)
        try state.refreshHelpFn.Call()
}

ToggleRemoteIndicator(cfg, state, *) {
    cfg.ShowIndicator := !cfg.ShowIndicator
    cfg.WriteBool("Appearance", "ShowIndicator", cfg.ShowIndicator)
    RefreshRemoteHudAppearance(cfg, state)
    BuildRemoteTrayMenu(cfg, state)
}

ToggleRemoteText(cfg, state, *) {
    cfg.ShowText := !cfg.ShowText
    cfg.WriteBool("Appearance", "ShowText", cfg.ShowText)
    RefreshRemoteHudAppearance(cfg, state)
    BuildRemoteTrayMenu(cfg, state)
}

ToggleRemoteMono(cfg, state, *) {
    cfg.MonoIcon := !cfg.MonoIcon
    cfg.WriteBool("Appearance", "MonoIcon", cfg.MonoIcon)
    RefreshRemoteHudAppearance(cfg, state)
    BuildRemoteTrayMenu(cfg, state)
}

ToggleRemoteCorners(cfg, state, *) {
    cfg.SleekCorners := !cfg.SleekCorners
    cfg.WriteBool("Appearance", "SleekCorners", cfg.SleekCorners)
    RefreshRemoteHudAppearance(cfg, state)
    BuildRemoteTrayMenu(cfg, state)
}

ToggleRemotePulse(cfg, state, *) {
    cfg.AggressivePulse := !cfg.AggressivePulse
    cfg.WriteBool("Appearance", "AggressivePulse", cfg.AggressivePulse)
    RefreshRemoteHudAppearance(cfg, state)
    BuildRemoteTrayMenu(cfg, state)
}

SetRemoteOpacity(cfg, state, val, *) {
    cfg.OpacityLevel := val
    cfg.Write("Appearance", "OpacityLevel", val)
    state.baseAlpha := val
    state.currentAlpha := val
    RefreshRemoteHudAppearance(cfg, state)
    BuildRemoteTrayMenu(cfg, state)
}

SetRemoteScale(cfg, state, val, *) {
    cfg.IndicatorScale := val
    cfg.Write("Appearance", "IndicatorScale", val)
    RefreshRemoteHudAppearance(cfg, state)
    BuildRemoteTrayMenu(cfg, state)
}

SetRemoteTheme(cfg, state, mode, *) {
    cfg.ThemeMode := mode
    cfg.Write("Appearance", "ThemeMode", mode)
    Theme.SetMode(mode)
    Theme.ApplyMenuTheme()
    BuildRemoteTrayMenu(cfg, state)
}

ResetRemotePositionAction(cfg, state, *) {
    cfg.ResetPosition()
    RefreshRemoteHudAppearance(cfg, state)
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
    connState := (state.connStatus = "auth_failed") ? "Auth Failed (Check Password)"
        : ((state.obsConnected && state.connStatus = "mic_error") ? ("Connected - Mic '" cfg.TargetMicName "' Not Found")
        : (state.obsConnected ? ("Connected to " state.activeHost) : "Searching / Disconnected"))
    clickerText := FormatHK(cfg.HwMuteHotkey) (cfg.EnablePointerMute ? "" : " (Disabled)")
    hostText := IsRemoteUsingInternetChannel(cfg, state)
        ? (((state.HasOwnProp("usingRelayFallback") && state.usingRelayFallback) ? "Relay Bridge (" : "Internet (") (cfg.InternetPairingCode != "" ? cfg.InternetPairingCode : "Not Set") ")")
        : ((cfg.HostAddress != "" ? cfg.HostAddress : "(Not Set)") ":" cfg.HostPort)
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

    iconSource := A_IsCompiled ? A_ScriptFullPath : (FileExist(A_ScriptDir "\PresenterSyncRemote.ico") ? A_ScriptDir "\PresenterSyncRemote.ico" : A_ScriptDir "\..\PresenterSyncRemote.ico")
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
        . "• Dual Network Failover: Same Router (LAN mDNS + multi-IP failover) or Different Networks (Internet Pairing Code PS-XXXX-XXXX) with safe heartbeat.`r`n"
        . "• Secondary Clicker Control: Assign mute button, Cough Hold (>= 350ms), local Clicker Tester & Ctrl+F12 arming toggle.`r`n"
        . "• Large-Board Visuals: 0.25x-5.0x scale, Dark/Light/System theme, 5 color palettes, text label, monochrome icons, pulse, cue & toast.`r`n"
        . "• Smart Ergonomics & System: 14px Magnetic Snap, Auto-Dodge hover ghost, Click-Through (hold Alt), Startup (OFF by default) & Updates.`r`n`r`n"
        . "STREAMLINED BY DESIGN (HOST-ONLY MODULES OMITTED):`r`n"
        . "• Omits multi-tier overlay panels, CoreAudio voice bar, UIA meeting monitoring, Control Center, Setup Wizard, and PowerPoint forwarding."
    AddHelpGuideEdit(aboutGui, 20, 214, 430, 214, remCapsText)

    aboutGui.SetFont("s9 w400 norm", Theme.UiFont)
    gitBtn := aboutGui.Add("Button", "x20 y440 w208 h30", "GitHub Repo")
    Theme.RegisterControl(aboutGui, gitBtn, "Button")
    gitBtn.OnEvent("Click", (*) => Run("https://github.com/SaabithJiffry/PresenterSync/"))

    updBtn := aboutGui.Add("Button", "x242 y440 w208 h30", "Check for Updates")
    Theme.RegisterControl(aboutGui, updBtn, "Button")
    updBtn.OnEvent("Click", (*) => CheckForUpdates(UIConstants.APP_VERSION, "", false))

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
    lblPair := dlg.Add("Text", "xm w360 y+10", "Internet Pairing Code (Optional Fallback / WAN):")
    Theme.RegisterControl(dlg, lblPair, "Text")
    dlg.SetFont("s9 w400", Theme.UiFont)
    editPair := dlg.Add("Edit", "xm w360", cfg.InternetPairingCode)
    Theme.RegisterControl(dlg, editPair, "Edit")

    dlg.SetFont("s9 w600", Theme.UiFont)
    lblHost := dlg.Add("Text", "xm w360 y+8", "LAN Host Address (e.g. STUDIO-PC.local, 192.168.1.50):")
    Theme.RegisterControl(dlg, lblHost, "Text")
    dlg.SetFont("s9 w400", Theme.UiFont)
    editHost := dlg.Add("Edit", "xm w360", cfg.HostAddress)
    Theme.RegisterControl(dlg, editHost, "Edit")

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
        lblPair.Enabled := true
        editPair.Enabled := true
        lblHost.Enabled := !isInternet
        editHost.Enabled := !isInternet
        lblPort.Enabled := !isInternet
        editPort.Enabled := !isInternet
    }
    ddlNetMode.OnEvent("Change", UpdateModeFields)
    UpdateModeFields()

    statusTxt := dlg.Add("Text", "xm w360 y+10 Center", "Status: Ready to test or connect")
    Theme.RegisterControl(dlg, statusTxt, "Text", "muted")

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
            try dlg._testWs.shutdown()
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
            if (h = "" || p = "") {
                dlg.Opt("+OwnDialogs")
                MsgBox("Host Address, Port, and Audio Source cannot be empty.", "Error", "Icon!")
                return
            }
            if (!IsInteger(p) || Integer(p) < 1 || Integer(p) > 65535) {
                dlg.Opt("+OwnDialogs")
                MsgBox("OBS WebSocket Port must be a number between 1 and 65535.", "Error", "Icon!")
                return
            }
        }

        cfg.NetworkMode := selMode
        cfg.InternetPairingCode := pairVal
        cfg.HostAddress := h
        cfg.HostPort := String(Integer(p))
        cfg.ObsPassword := editPw.Value
        cfg.TargetMicName := m
        cfg.FirstRun := false

        cfg.Write("Connection", "NetworkMode", cfg.NetworkMode)
        cfg.Write("Connection", "InternetPairingCode", cfg.InternetPairingCode)
        cfg.Write("Connection", "HostAddress", cfg.HostAddress)
        cfg.Write("Connection", "HostPort", cfg.HostPort)
        cfg.Write("Connection", "ObsPassword", cfg.ObsPassword)
        cfg.Write("Connection", "TargetMicName", cfg.TargetMicName)
        cfg.WriteBool("Settings", "FirstRun", false)

        CleanupDialog(false)

        ; Disconnect existing and trigger fresh failover connection
        SetTimer state.reconnectTimerFn, 0
        SetTimer state.heartbeatTimerFn, 0
        SetTimer state.breathTimerFn, 0
        state.animSeq += 1
        if IsObject(state.obsWs) {
            try state.obsWs.shutdown()
            state.obsWs := ""
        }
        state.obsConnected := false
        state.connStatus := "searching"
        state.activeHost := ""
        state.candidateIndex := 1
        state.usingRelayFallback := false
        state.candidates := []
        if (IsObject(state.MicGui)) {
            state.currentAlpha := GetRemoteEffectiveAlpha(state)
            ApplyMicAppearance(cfg, state)
        }
        if (IsObject(state.rebuildTrayFn))
            try state.rebuildTrayFn.Call()
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
        try dlg._testWs.shutdown()
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
            try dlg._testWs.shutdown()
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
                try ws.shutdown()
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
                try dlg._testWs.shutdown()
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
                    try ws.shutdown()
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
                    try dlg._testWs.shutdown()
                    dlg._testWs := ""
                }
                if (st == 4009) {
                    FinishTest("✕ Auth failed on " target.raw " (Wrong OBS password)")
                    return
                }
                currentIndex += 1
                TryNextCandidate()
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
