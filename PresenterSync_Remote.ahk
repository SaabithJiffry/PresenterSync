; ==============================================================================
; Script: PresenterSync_Remote
; Description: Standalone companion client for Smart Boards & secondary devices.
;              Provides a single-pill remote mute HUD and transmits clicker
;              mute keystrokes back to OBS Studio over the local network.
; Version: 2.2.2
; Author: Saabith Jiffry
; License: MIT
; ==============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
ProcessSetPriority "High"

#Include <WebSocket>
#Include <Crypto>
#Include <Gdip>
#Include <GUI_Config>

Gdip.Startup()
OnExit((*) => (Theme.Shutdown(), Gdip.Shutdown()))

if (!A_IsCompiled && FileExist(A_ScriptDir "\PresenterSync.ico"))
    try TraySetIcon(A_ScriptDir "\PresenterSync.ico")
A_IconTip := "PresenterSync Remote v" UIConstants.APP_VERSION

; === CONFIGURATION & STATE ===
class RemoteConfig {
    ConfigFile := ""
    HostAddress := "127.0.0.1"
    HostPort := "4455"
    ObsPassword := ""
    TargetMicName := "Mic/Aux"
    HeartbeatSeconds := 30

    HwMuteHotkey := "b"
    EnablePointerMute := true

    ShowIndicator := true
    ThemeMode := "System"
    ShowText := false
    MonoIcon := false
    SleekCorners := false
    AggressivePulse := false
    OpacityLevel := 220
    IndicatorScale := 1.0
    FirstRun := true
    IsMuted := false

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
        this.HostAddress := this.Read("Connection", "HostAddress", "127.0.0.1")
        rawPort := Trim(this.Read("Connection", "HostPort", "4455"))
        this.HostPort := (IsInteger(rawPort) && Integer(rawPort) >= 1 && Integer(rawPort) <= 65535) ? String(Integer(rawPort)) : "4455"
        this.ObsPassword := this.Read("Connection", "ObsPassword", "")
        this.TargetMicName := this.Read("Connection", "TargetMicName", "Mic/Aux")
        this.HeartbeatSeconds := this.ReadInt("Connection", "HeartbeatSeconds", 30)

        this.HwMuteHotkey := this.Read("Pointer", "HwMuteHotkey", "b")
        this.EnablePointerMute := this.ReadBool("Pointer", "EnablePointerMute", 1)

        this.ShowIndicator := this.ReadBool("Appearance", "ShowIndicator", 1)
        rawTheme := StrLower(Trim(this.Read("Appearance", "ThemeMode", "System")))
        this.ThemeMode := (rawTheme = "dark") ? "Dark" : ((rawTheme = "light") ? "Light" : "System")
        Theme.SetMode(this.ThemeMode)

        this.ShowText := this.ReadBool("Appearance", "ShowText", 0)
        this.MonoIcon := this.ReadBool("Appearance", "MonoIcon", 0)
        this.SleekCorners := this.ReadBool("Appearance", "SleekCorners", 0)
        this.AggressivePulse := this.ReadBool("Appearance", "AggressivePulse", 0)
        this.OpacityLevel := this.ReadInt("Appearance", "OpacityLevel", UIConstants.OPACITY_FROSTED)
        if (this.OpacityLevel < 1 || this.OpacityLevel > 255)
            this.OpacityLevel := UIConstants.OPACITY_FROSTED

        this.IndicatorScale := this.ReadFloat("Appearance", "IndicatorScale", 1.0)
        if (this.IndicatorScale <= 0.0 || this.IndicatorScale > 10.0)
            this.IndicatorScale := 1.0

        this.FirstRun := this.ReadBool("Settings", "FirstRun", 1)
        this.IsMuted := this.ReadBool("Settings", "IsMuted", 0)

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
        this.OpacityLevel := UIConstants.OPACITY_FROSTED
        this.IndicatorScale := 1.0
        this.ThemeMode := "System"
        Theme.SetMode("System")

        this.WriteBool("Appearance", "ShowText", false)
        this.WriteBool("Appearance", "MonoIcon", false)
        this.WriteBool("Appearance", "SleekCorners", false)
        this.WriteBool("Appearance", "AggressivePulse", false)
        this.Write("Appearance", "OpacityLevel", this.OpacityLevel)
        this.Write("Appearance", "IndicatorScale", this.IndicatorScale)
        this.Write("Appearance", "ThemeMode", this.ThemeMode)
    }
}

class RemoteState {
    obsWs := ""
    obsConnected := false
    connStatus := "searching"
    activeHost := ""
    candidateIndex := 1
    candidates := []

    isMuted := false
    baseAlpha := 220
    currentAlpha := 220
    breathDir := -5
    animSeq := 0
    isDraggingHud := false

    dragTimerFn := ""
    breathTimerFn := ""
    reconnectTimerFn := ""
    heartbeatTimerFn := ""
    rebuildTrayFn := ""
    pointerHotIfFn := ""
    activePointerKey := ""

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
        this.reconnectTimerFn := ConnectToRemoteOBS.Bind(cfg, this)
        this.heartbeatTimerFn := RemoteHeartbeatTick.Bind(cfg, this)
        this.pointerHotIfFn := CheckRemotePointerEnable.Bind(cfg)

        this.ComputeDimensions(cfg)
    }

    ComputeDimensions(cfg) {
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
AppState := RemoteState(AppConfig)
AppState.rebuildTrayFn := BuildRemoteTrayMenu.Bind(AppConfig, AppState)

; === INITIALIZE HUD & HOTKEYS ===
InitRemoteHUD(AppConfig, AppState)
BuildRemoteTrayMenu(AppConfig, AppState)
RegisterRemotePointerHotkey(AppConfig, AppState)

; === FIRST-RUN / CONNECTION PROMPT ===
if (AppConfig.FirstRun || AppConfig.HostAddress = "") {
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

    if (state.candidates.Length == 0 || state.candidateIndex > state.candidates.Length) {
        state.candidates := ParseCandidateEndpoints(cfg.HostAddress, cfg.HostPort)
        state.candidateIndex := 1
    }

    candidate := state.candidates[state.candidateIndex]
    wsUrl := "ws://" candidate.host ":" candidate.port

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
    state.candidateIndex += 1
    if (state.candidateIndex <= state.candidates.Length) {
        ; Probe next candidate immediately
        SetTimer state.reconnectTimerFn, -50
    } else {
        ; All candidates exhausted, wait reconnect interval before retrying from first
        state.candidateIndex := 1
        SetTimer state.reconnectTimerFn, -2500
    }
    if (IsObject(state.rebuildTrayFn))
        try state.rebuildTrayFn.Call()
}

HandleRemoteObsClose(cfg, state, candidate, ws, status, reason) {
    if IsObject(ws)
        try ws.shutdown()
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
        TrayTip("PresenterSync Remote", "OBS WebSocket authentication failed. Check password in Change OBS Connection.", 3)
        return
    }

    state.connStatus := "searching"
    if (IsObject(state.rebuildTrayFn))
        try state.rebuildTrayFn.Call()

    FailoverToNextCandidate(cfg, state)
}

HandleRemoteObsMessage(cfg, state, candidate, ws, rawMsg) {
    msg := (Type(rawMsg) == "Buffer") ? StrGet(rawMsg, "UTF-8") : String(rawMsg)

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
        escMic := EscapeJsonStr(cfg.TargetMicName)
        SendObsRequest(ws, "GetInputMute", "InitRemoteMute", '{"inputName":"' escMic '"}')

        if (IsObject(state.rebuildTrayFn))
            try state.rebuildTrayFn.Call()
    }
    else if (opCode == 5) {
        ; Op 5: Event payload
        if (InStr(msg, '"eventType":"InputMuteStateChanged"') || InStr(msg, '"eventType": "InputMuteStateChanged"')) {
            escMic := EscapeJsonStr(cfg.TargetMicName)
            if (InStr(msg, '"inputName":"' escMic '"') || InStr(msg, '"inputName": "' escMic '"')) {
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
                TrayTip("PresenterSync Remote", "Audio source '" cfg.TargetMicName "' was not found in OBS Studio.", 2)
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
            }
        }
        else if (InStr(msg, '"requestId":"RemoteClickerMute"') || InStr(msg, '"requestId": "RemoteClickerMute"')) {
            if (RegExMatch(msg, '"result"\s*:\s*false')) {
                ToolTip "PresenterSync Remote: Audio source '" cfg.TargetMicName "' not found in OBS"
                SetTimer RemoveToolTip, -2500
            }
        }
    }
}

RemoteHeartbeatTick(cfg, state) {
    if (!state.obsConnected || !IsObject(state.obsWs))
        return
    ; Lightweight request to keep TCP session alive
    SendObsRequest(state.obsWs, "GetVersion", "KeepAlive")
}

SyncRemoteMuteState(cfg, state, newMuted) {
    if (state.isMuted != newMuted) {
        state.isMuted := newMuted
        cfg.IsMuted := newMuted
        cfg.WriteBool("Settings", "IsMuted", newMuted)
        PlayMuteAnimation(cfg, state)
    }
}

; --- REMOTE CLICKER MUTE TRANSMISSION ---

RemoveToolTip() {
    ToolTip()
}

OnRemoteClickerMute(cfg, state, *) {
    static lastTick := 0
    now := A_TickCount
    if (now - lastTick < 150) ; 150ms hardware debounce shield
        return
    lastTick := now

    if (!state.obsConnected || !IsObject(state.obsWs)) {
        ToolTip "PresenterSync Remote: Not connected to OBS host"
        SetTimer RemoveToolTip, -2000
        return
    }

    if (!SendObsToggleInputMute(state.obsWs, cfg.TargetMicName, "RemoteClickerMute")) {
        ToolTip "PresenterSync Remote: Not connected to OBS host"
        SetTimer RemoveToolTip, -2000
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

    OnMessage(0x0201, WM_REMOTE_LBUTTONDOWN.Bind(cfg, state))
    OnMessage(0x0205, WM_REMOTE_RBUTTONUP.Bind(state))
}

WM_REMOTE_LBUTTONDOWN(cfg, state, wParam, lParam, msg, hwnd) {
    if (!IsObject(state.MicGui) || hwnd != state.MicGui.Hwnd)
        return

    state.isDraggingHud := true
    PostMessage(0xA1, 2,,, "ahk_id " hwnd) ; Native Windows drag (HTCAPTION)
    KeyWait "LButton"
    state.isDraggingHud := false

    WinGetPos(&X, &Y,,, "ahk_id " hwnd)
    if (X != state.savedX || Y != state.savedY) {
        state.savedX := X
        state.savedY := Y
        cfg.savedX := X
        cfg.savedY := Y
        cfg.Write("Position", "X", X)
        cfg.Write("Position", "Y", Y)
    }
    state.currentAlpha := GetRemoteEffectiveAlpha(state)
    ApplyMicAppearance(cfg, state)
    if (cfg.ShowIndicator && state.obsConnected && state.isMuted)
        SetTimer state.breathTimerFn, (cfg.AggressivePulse ? UIConstants.PULSE_INTERVAL_AGGRESSIVE : UIConstants.PULSE_INTERVAL_NORMAL)
}

WM_REMOTE_RBUTTONUP(state, wParam, lParam, msg, hwnd) {
    if (IsObject(state.MicGui) && hwnd == state.MicGui.Hwnd)
        A_TrayMenu.Show()
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
    PointerMenu.Add("Change Pointer Mute Button...", (*) => ChangeRemotePointerKeyUI(cfg, state))
    PointerMenu.Add("Launch Clicker Tester...", (*) => ShowPointerTester())
    A_TrayMenu.Add("Pointer Controls", PointerMenu)

    A_TrayMenu.Add("Change OBS Connection...", (*) => ShowRemoteConnectionUI(cfg, state, false))
    A_TrayMenu.Add()

    ; 5. HELP, SAFETY & EXIT
    A_TrayMenu.Add("Help && Setup Guide...", (*) => ShowRemoteHelpUI(cfg, state))
    A_TrayMenu.Add("About PresenterSync Remote...", (*) => ShowRemoteAboutUI())
    A_TrayMenu.Add("Suspend All Hotkeys", ToggleRemoteSuspend)
    if A_IsSuspended
        A_TrayMenu.Check("Suspend All Hotkeys")
    A_TrayMenu.Add("Exit PresenterSync Remote", (*) => ExitApp())
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
    cfg.EnablePointerMute := !cfg.EnablePointerMute
    cfg.WriteBool("Pointer", "EnablePointerMute", cfg.EnablePointerMute)
    if (cfg.EnablePointerMute)
        RegisterRemotePointerHotkey(cfg, state)
    else
        UnregisterRemotePointerHotkey(cfg, state)
    BuildRemoteTrayMenu(cfg, state)
}

ToggleRemoteSuspend(*) {
    Suspend(-1)
    Theme.WasSuspendedBeforeDialogs := A_IsSuspended
    if A_IsSuspended {
        A_TrayMenu.Check("Suspend All Hotkeys")
        TrayTip("PresenterSync Remote", "All hotkeys suspended.", 1)
    } else {
        A_TrayMenu.Uncheck("Suspend All Hotkeys")
        TrayTip("PresenterSync Remote", "Hotkeys active.", 1)
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
        TrayTip("Pointer Mute", cfg.EnablePointerMute ? ("Mute button registered: " val) : ("Mute button saved (Pointer Mute disabled): " val), 1)
    ))
}

ShowRemoteHelpUI(cfg, state, *) {
    existing := Theme.FocusExistingWindow("RemoteHelpWindow")
    if IsObject(existing)
        return existing

    helpGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "PresenterSync Remote v" UIConstants.APP_VERSION " - Setup & Help Guide")
    Theme.ApplyToWindow(helpGui)
    Theme.NamedWindows["RemoteHelpWindow"] := helpGui

    helpGui.SetFont("s11 w700 norm", Theme.UiFont)
    Theme.RegisterControl(helpGui, helpGui.Add("Text", "x18 y16 w580", "Smart Board & Remote Companion Setup Guide"), "Text")

    connState := (state.connStatus = "auth_failed") ? "Auth Failed (Check Password)"
        : ((state.obsConnected && state.connStatus = "mic_error") ? ("Connected - Mic '" cfg.TargetMicName "' Not Found")
        : (state.obsConnected ? ("Connected to " state.activeHost) : "Searching / Disconnected"))
    helpGui.SetFont("s9 w400 norm", Theme.UiFont)
    Theme.RegisterControl(helpGui, helpGui.Add("Text", "x18 y40 w580", "Current Status: " connState "  |  Clicker Key: " FormatHK(cfg.HwMuteHotkey) "  |  Host: " (cfg.HostAddress != "" ? cfg.HostAddress : "(Not Set)") ":" cfg.HostPort), "Text", "muted")

    ed := AddHelpGuideEdit(helpGui, 18, 66, 580, 340, GetRemoteSetupGuideText())

    btnConn := helpGui.Add("Button", "x18 y418 w186 h32", "Change OBS Connection...")
    btnKey := helpGui.Add("Button", "x215 y418 w186 h32", "Change Mute Button...")
    btnClose := helpGui.Add("Button", "x412 y418 w186 h32 Default", "Close")
    Theme.RegisterControl(helpGui, btnConn, "Button", "accent")
    Theme.RegisterControl(helpGui, btnKey, "Button")
    Theme.RegisterControl(helpGui, btnClose, "Button")

    CloseRemoteHelp(*) {
        Theme.UnregisterWindow(helpGui, "RemoteHelpWindow")
        helpGui.Destroy()
    }
    btnConn.OnEvent("Click", (*) => ShowRemoteConnectionUI(cfg, state, false))
    btnKey.OnEvent("Click", (*) => ChangeRemotePointerKeyUI(cfg, state))
    btnClose.OnEvent("Click", CloseRemoteHelp)
    helpGui.OnEvent("Close", CloseRemoteHelp)
    helpGui.OnEvent("Escape", CloseRemoteHelp)

    helpGui.Show("w616 h466 Center")
    btnClose.Focus()
    return helpGui
}

ShowRemoteAboutUI(*) {
    existing := Theme.FocusExistingWindow("AboutRemoteWindow")
    if IsObject(existing)
        return existing

    aboutGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "About PresenterSync Remote")
    Theme.ApplyToWindow(aboutGui)
    Theme.NamedWindows["AboutRemoteWindow"] := aboutGui

    iconSource := A_IsCompiled ? A_ScriptFullPath : A_ScriptDir "\PresenterSync.ico"
    if FileExist(iconSource)
        aboutGui.Add("Picture", "x158 y15 w64 h64", iconSource)

    aboutGui.SetFont("s16 w700 norm", Theme.UiFont)
    Theme.RegisterControl(aboutGui, aboutGui.Add("Text", "x10 w360 Center y+12", "PresenterSync Remote"), "Text")

    aboutGui.SetFont("s10 w700 norm", Theme.UiFont)
    Theme.RegisterControl(aboutGui, aboutGui.Add("Text", "x10 w360 Center y+4", "Version " UIConstants.APP_VERSION), "Text", "accent")

    aboutGui.SetFont("s9 w400 norm", Theme.UiFont)
    Theme.RegisterControl(aboutGui, aboutGui.Add("Text", "x20 w340 Center y+8", "Smart Board & Secondary Presenter Mute Companion for OBS Studio"), "Text", "muted")

    aboutGui.SetFont("s10 w400 norm", Theme.UiFont)
    Theme.RegisterControl(aboutGui, aboutGui.Add("Text", "x10 w360 Center y+12", "Created by Saabith Jiffry"), "Text")

    gitBtn := aboutGui.Add("Button", "w120 x60 y+20 h32", "GitHub Repo")
    Theme.RegisterControl(aboutGui, gitBtn, "Button")
    gitBtn.OnEvent("Click", (*) => Run("https://github.com/SaabithJiffry/PresenterSync/"))

    closeBtn := aboutGui.Add("Button", "w120 x+20 h32 Default", "Close")
    Theme.RegisterControl(aboutGui, closeBtn, "Button")
    CloseAbout(*) {
        Theme.UnregisterWindow(aboutGui, "AboutRemoteWindow")
        aboutGui.Destroy()
    }
    closeBtn.OnEvent("Click", CloseAbout)
    aboutGui.OnEvent("Close", CloseAbout)
    aboutGui.OnEvent("Escape", CloseAbout)

    aboutGui.Show("AutoSize Center")
    return aboutGui
}

ShowRemoteConnectionUI(cfg, state, isInitialBoot := false) {
    existing := Theme.FocusExistingWindow("OBS Remote Connection")
    if IsObject(existing)
        return existing

    dlg := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "OBS Remote Connection")
    dlg._closed := false
    dlg._testSeq := 0
    dlg._testWs := ""
    Theme.ApplyToWindow(dlg)
    Theme.NamedWindows["OBS Remote Connection"] := dlg

    dlg.SetFont("s10 w600", Theme.UiFont)
    Theme.RegisterControl(dlg, dlg.Add("Text", "w360", "Connect to Primary Streaming Host"), "Text")
    dlg.SetFont("s9 w400", Theme.UiFont)
    Theme.RegisterControl(dlg, dlg.Add("Text", "w360 y+4", "Enter Host IP / Computer Name (Supports comma-separated failover candidates):"), "Text", "muted")

    dlg.SetFont("s9 w600", Theme.UiFont)
    Theme.RegisterControl(dlg, dlg.Add("Text", "w360 y+12", "Host Address (e.g. STUDIO-PC.local, 192.168.1.50):"), "Text")
    dlg.SetFont("s9 w400", Theme.UiFont)
    editHost := dlg.Add("Edit", "w360", cfg.HostAddress)
    Theme.RegisterControl(dlg, editHost, "Edit")

    Theme.RegisterControl(dlg, dlg.Add("Text", "w360 y+8", "OBS WebSocket Port:"), "Text")
    editPort := dlg.Add("Edit", "w360", cfg.HostPort)
    Theme.RegisterControl(dlg, editPort, "Edit")

    Theme.RegisterControl(dlg, dlg.Add("Text", "w360 y+8", "OBS WebSocket Password (Optional):"), "Text")
    editPw := dlg.Add("Edit", "w360 Password", cfg.ObsPassword)
    Theme.RegisterControl(dlg, editPw, "Edit")

    Theme.RegisterControl(dlg, dlg.Add("Text", "w360 y+8", "Exact Audio Source Name:"), "Text")
    editMic := dlg.Add("Edit", "w360", cfg.TargetMicName)
    Theme.RegisterControl(dlg, editMic, "Edit")

    statusTxt := dlg.Add("Text", "w360 y+10 Center", "Status: Ready to test or connect")
    Theme.RegisterControl(dlg, statusTxt, "Text", "muted")

    btnTest := dlg.Add("Button", "w230 h30 y+8", "Test Connection")
    btnGuide := dlg.Add("Button", "x+10 w120 h30", "Setup Guide")
    Theme.RegisterControl(dlg, btnTest, "Button")
    Theme.RegisterControl(dlg, btnGuide, "Button")

    btnTest.OnEvent("Click", (*) => TestConnectionAction(dlg, btnTest, editHost.Value, editPort.Value, editPw.Value, statusTxt))
    btnGuide.OnEvent("Click", (*) => ShowRemoteHelpUI(cfg, state))

    btnSave := dlg.Add("Button", "x16 w360 h32 y+12 Default", isInitialBoot ? "Connect & Start" : "Save & Reconnect")
    Theme.RegisterControl(dlg, btnSave, "Button", "accent")

    CleanupDialog(exitIfInitial := false, *) {
        if (dlg._closed)
            return
        dlg._closed := true
        dlg._testSeq += 1
        if IsObject(dlg._testWs) {
            try dlg._testWs.shutdown()
            dlg._testWs := ""
        }
        Theme.UnregisterWindow(dlg, "OBS Remote Connection")
        dlg.Destroy()
        if (exitIfInitial)
            ExitApp()
    }

    SaveAndConnect(*) {
        h := Trim(editHost.Value)
        p := Trim(editPort.Value)
        m := Trim(editMic.Value)
        if (h = "" || p = "" || m = "") {
            dlg.Opt("+OwnDialogs")
            MsgBox("Host Address, Port, and Audio Source cannot be empty.", "Error", "Icon!")
            return
        }
        if (!IsInteger(p) || Integer(p) < 1 || Integer(p) > 65535) {
            dlg.Opt("+OwnDialogs")
            MsgBox("OBS WebSocket Port must be a number between 1 and 65535.", "Error", "Icon!")
            return
        }
        cfg.HostAddress := h
        cfg.HostPort := String(Integer(p))
        cfg.ObsPassword := editPw.Value
        cfg.TargetMicName := m
        cfg.FirstRun := false

        cfg.Write("Connection", "HostAddress", cfg.HostAddress)
        cfg.Write("Connection", "HostPort", cfg.HostPort)
        cfg.Write("Connection", "ObsPassword", cfg.ObsPassword)
        cfg.Write("Connection", "TargetMicName", cfg.TargetMicName)
        cfg.WriteBool("Settings", "FirstRun", false)

        CleanupDialog(false)

        ; Disconnect existing and trigger fresh failover connection
        SetTimer state.reconnectTimerFn, 0
        SetTimer state.heartbeatTimerFn, 0
        state.obsConnected := false
        state.connStatus := "searching"
        state.activeHost := ""
        state.candidateIndex := 1
        state.candidates := []
        if (IsObject(state.rebuildTrayFn))
            try state.rebuildTrayFn.Call()
        ConnectToRemoteOBS(cfg, state)
    }

    btnSave.OnEvent("Click", SaveAndConnect)

    dlg.OnEvent("Close", (*) => CleanupDialog(isInitialBoot))
    dlg.OnEvent("Escape", (*) => CleanupDialog(isInitialBoot))

    dlg.Show("AutoSize Center")
    return dlg
}

TestConnectionAction(dlg, btnTest, hostStr, portStr, pwStr, statusLabel) {
    if (dlg._closed || !WinExist("ahk_id " dlg.Hwnd))
        return

    portClean := Trim(portStr)
    if (!IsInteger(portClean) || Integer(portClean) < 1 || Integer(portClean) > 65535) {
        statusLabel.Value := "Error: Port must be between 1 and 65535."
        return
    }

    endpoints := ParseCandidateEndpoints(hostStr, portClean)
    if (endpoints.Length == 0) {
        statusLabel.Value := "Error: No valid host address provided."
        return
    }

    dlg._testSeq += 1
    mySeq := dlg._testSeq
    if IsObject(dlg._testWs) {
        try dlg._testWs.shutdown()
        dlg._testWs := ""
    }

    currentIndex := 1
    testSuccess := false
    btnTest.Enabled := false

    IsCancelled() {
        return dlg._closed || dlg._testSeq != mySeq || !WinExist("ahk_id " dlg.Hwnd)
    }

    FinishTest(msg) {
        if IsObject(dlg._testWs) {
            try dlg._testWs.shutdown()
            dlg._testWs := ""
        }
        if (IsCancelled())
            return
        statusLabel.Value := msg
        btnTest.Enabled := true
    }

    TryNextCandidate() {
        if (IsCancelled() || testSuccess)
            return
        if (currentIndex > endpoints.Length) {
            FinishTest("✕ All " endpoints.Length " candidate(s) unreachable (Check IP, Port & Firewall)")
            return
        }

        target := endpoints[currentIndex]
        statusLabel.Value := "Testing " target.raw " (" currentIndex "/" endpoints.Length ")..."
        SetTimer RunCurrentProbe, -15

        RunCurrentProbe() {
            if (IsCancelled() || testSuccess)
                return

            OnTestMsg(ws, raw) {
                if (IsCancelled()) {
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
                if (IsCancelled() || testSuccess)
                    return
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
                dlg._testWs := WebSocket("ws://" target.host ":" target.port, {
                    message: OnTestMsg,
                    close: OnTestClose
                }, true, "", 2000)
            } catch {
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
