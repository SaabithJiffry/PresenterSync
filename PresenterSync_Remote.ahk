; ==============================================================================
; Script: PresenterSync_Remote
; Description: Standalone companion client for Smart Boards & secondary devices.
;              Provides a single-pill remote mute HUD and transmits clicker
;              mute keystrokes back to OBS Studio over the local network.
; Version: 2.0.0
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
        this.HostPort := this.Read("Connection", "HostPort", "4455")
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

    MicGui := ""
    IconFont := ""

    baseWidth := 80
    baseHeight := 40
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

; === FIRST-RUN / CONNECTION PROMPT ===
if (AppConfig.FirstRun || AppConfig.HostAddress = "") {
    ShowRemoteConnectionUI(AppConfig, AppState, true)
}

; === INITIALIZE HUD & HOTKEYS ===
InitRemoteHUD(AppConfig, AppState)
BuildRemoteTrayMenu(AppConfig, AppState)
RegisterRemotePointerHotkey(AppConfig, AppState)

; Start network connection
SetTimer AppState.reconnectTimerFn, -100

; --- REMOTE NETWORKING ENGINE ---

ParseCandidateEndpoints(rawStr, defaultPort := "4455") {
    endpoints := []
    seen := Map()
    for item in StrSplit(rawStr, [",", ";"]) {
        clean := Trim(item)
        if (clean = "")
            continue
        clean := RegExReplace(clean, "^wss?://", "")
        host := clean
        port := defaultPort
        if RegExMatch(clean, "^(.*?):(\d+)$", &m) {
            host := m[1]
            port := m[2]
        }
        key := host ":" port
        if (!seen.Has(key)) {
            seen[key] := true
            endpoints.Push({host: host, port: port, raw: key})
        }
    }
    if (endpoints.Length == 0)
        endpoints.Push({host: "127.0.0.1", port: defaultPort, raw: "127.0.0.1:" defaultPort})
    return endpoints
}

ConnectToRemoteOBS(cfg, state) {
    SetTimer state.reconnectTimerFn, 0

    if (state.obsConnected)
        return

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

    state.obsConnected := false
    state.activeHost := ""
    SetTimer state.heartbeatTimerFn, 0

    ; Visual feedback on HUD: Dim slightly while reconnecting
    if (IsObject(state.MicGui)) {
        state.currentAlpha := Max(60, Round(state.baseAlpha * 0.4))
        ApplyMicAppearance(cfg, state)
    }

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
        ws.sendText(identifyJson)
    }
    else if (opCode == 2) {
        ; Op 2: Identified - Connection and Auth Succeeded!
        SetTimer state.reconnectTimerFn, 0
        state.obsConnected := true
        state.activeHost := candidate.raw

        ; Start keep-alive heartbeat timer (prevents Wi-Fi radio sleep / router conntrack drops)
        keepAliveMs := Max(10000, cfg.HeartbeatSeconds * 1000)
        SetTimer state.heartbeatTimerFn, keepAliveMs

        ; Restore base alpha & query initial mic mute status
        state.currentAlpha := state.baseAlpha
        stateJson := '{"op":6,"d":{"requestType":"GetInputMute","requestId":"InitRemoteMute","requestData":{"inputName":"' cfg.TargetMicName '"}}}'
        ws.sendText(stateJson)

        if (IsObject(state.rebuildTrayFn))
            try state.rebuildTrayFn.Call()
    }
    else if (opCode == 5) {
        ; Op 5: Event payload
        if (InStr(msg, '"eventType":"InputMuteStateChanged"') || InStr(msg, '"eventType": "InputMuteStateChanged"')) {
            if (InStr(msg, '"inputName":"' cfg.TargetMicName '"') || InStr(msg, '"inputName": "' cfg.TargetMicName '"')) {
                if (RegExMatch(msg, '"inputMuted"\s*:\s*(true|false)', &matchMuted)) {
                    isMutedNow := (matchMuted[1] == "true")
                    SyncRemoteMuteState(cfg, state, isMutedNow)
                }
            }
        }
    }
    else if (opCode == 7) {
        ; Op 7: Request Response
        if (InStr(msg, '"requestId":"InitRemoteMute"') || InStr(msg, '"requestId": "InitRemoteMute"')) {
            if (RegExMatch(msg, '"inputMuted"\s*:\s*(true|false)', &matchMuted)) {
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
    }
}

RemoteHeartbeatTick(cfg, state) {
    if (!state.obsConnected || !IsObject(state.obsWs))
        return
    try {
        ; Lightweight request to keep TCP session alive
        hbJson := '{"op":6,"d":{"requestType":"GetVersion","requestId":"KeepAlive"}}'
        state.obsWs.sendText(hbJson)
    }
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

    req := '{"op":6,"d":{"requestType":"ToggleInputMute","requestId":"RemoteClickerMute","requestData":{"inputName":"' cfg.TargetMicName '"}}}'
    try state.obsWs.sendText(req)
}

RegisterRemotePointerHotkey(cfg, state) {
    if (!cfg.EnablePointerMute || cfg.HwMuteHotkey = "" || cfg.HwMuteHotkey = "None")
        return
    try {
        Hotkey cfg.HwMuteHotkey, OnRemoteClickerMute.Bind(cfg, state), "On"
    }
}

UnregisterRemotePointerHotkey(cfg) {
    if (cfg.HwMuteHotkey != "" && cfg.HwMuteHotkey != "None") {
        try Hotkey cfg.HwMuteHotkey, "Off"
    }
}

; --- SINGLE-PILL HUD CREATION & DRAGGING ---

InitRemoteHUD(cfg, state) {
    state.ComputeDimensions(cfg)

    ; Only create a single layered GDI+ window for the Mic HUD
    state.MicGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000 -DPIScale")
    ApplyMicAppearance(cfg, state)

    if (cfg.ShowIndicator) {
        state.MicGui.Show(Format("NoActivate x{} y{} w{} h{}", state.savedX, state.savedY, state.baseWidth, state.baseHeight))
        if (state.isMuted)
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
}

WM_REMOTE_RBUTTONUP(state, wParam, lParam, msg, hwnd) {
    if (IsObject(state.MicGui) && hwnd == state.MicGui.Hwnd)
        A_TrayMenu.Show()
}

RefreshRemoteHudAppearance(cfg, state) {
    state.ComputeDimensions(cfg)
    state.currentAlpha := state.baseAlpha
    ApplyMicAppearance(cfg, state)
    if (cfg.ShowIndicator) {
        state.MicGui.Show(Format("NoActivate x{} y{} w{} h{}", state.savedX, state.savedY, state.baseWidth, state.baseHeight))
        if (state.isMuted) {
            state.breathDir := cfg.AggressivePulse ? -UIConstants.PULSE_STEP_AGGRESSIVE : -UIConstants.PULSE_STEP_NORMAL
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
    statusText := state.obsConnected ? ("● Connected: " state.activeHost) : "○ Searching for OBS Host..."
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
    else
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

    ; 5. SAFETY & EXIT
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
        UnregisterRemotePointerHotkey(cfg)
    BuildRemoteTrayMenu(cfg, state)
}

ToggleRemoteSuspend(*) {
    Suspend(-1)
    if A_IsSuspended
        TrayTip("PresenterSync Remote", "All hotkeys suspended.", 1)
    else
        TrayTip("PresenterSync Remote", "Hotkeys active.", 1)
}

; --- SETTINGS DIALOGS ---

ChangeRemotePointerKeyUI(cfg, state, *) {
    SaveKey(values, ctrls, dlg) {
        UnregisterRemotePointerHotkey(cfg)
        cfg.HwMuteHotkey := values["hwMute"]
        cfg.Write("Pointer", "HwMuteHotkey", cfg.HwMuteHotkey)
        RegisterRemotePointerHotkey(cfg, state)
        dlg.Destroy()
        BuildRemoteTrayMenu(cfg, state)
    }

    elements := [
        {type: "Text", opts: "w260", text: "Focus the box below and press the button on your presentation clicker:"},
        {type: "Hotkey", id: "hwMute", opts: "w260", value: cfg.HwMuteHotkey, required: true, errorMsg: "Please press a button to register it."}
    ]

    BuildSettingsWindow("Edit Pointer Mute Button", elements, SaveKey, {
        saveBtnText: "Save & Apply",
        saveBtnOpts: "w260 h32 Default y+15"
    })
}

ShowRemoteConnectionUI(cfg, state, isInitialBoot := false) {
    existing := Theme.FocusExistingWindow("OBS Remote Connection")
    if IsObject(existing)
        return existing

    dlg := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "OBS Remote Connection")
    dlg._closed := false
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

    btnTest := dlg.Add("Button", "w360 h30 y+8", "Test Connection")
    Theme.RegisterControl(dlg, btnTest, "Button")

    btnTest.OnEvent("Click", (*) => TestConnectionAction(editHost.Value, editPort.Value, editPw.Value, statusTxt))

    btnSave := dlg.Add("Button", "w360 h32 y+12 Default", isInitialBoot ? "Connect & Start" : "Save & Reconnect")
    Theme.RegisterControl(dlg, btnSave, "Button", "accent")

    SaveAndConnect(*) {
        h := Trim(editHost.Value)
        p := Trim(editPort.Value)
        m := Trim(editMic.Value)
        if (h = "" || p = "" || m = "") {
            MsgBox("Host Address, Port, and Audio Source cannot be empty.", "Error", "Icon!")
            return
        }
        cfg.HostAddress := h
        cfg.HostPort := p
        cfg.ObsPassword := editPw.Value
        cfg.TargetMicName := m
        cfg.FirstRun := false

        cfg.Write("Connection", "HostAddress", cfg.HostAddress)
        cfg.Write("Connection", "HostPort", cfg.HostPort)
        cfg.Write("Connection", "ObsPassword", cfg.ObsPassword)
        cfg.Write("Connection", "TargetMicName", cfg.TargetMicName)
        cfg.WriteBool("Settings", "FirstRun", false)

        dlg.Destroy()

        ; Disconnect existing and trigger fresh failover connection
        state.obsConnected := false
        state.candidateIndex := 1
        state.candidates := []
        ConnectToRemoteOBS(cfg, state)
    }

    btnSave.OnEvent("Click", SaveAndConnect)

    dlg.OnEvent("Close", (*) => (isInitialBoot ? ExitApp() : dlg.Destroy()))
    dlg.OnEvent("Escape", (*) => (isInitialBoot ? ExitApp() : dlg.Destroy()))

    dlg.Show("AutoSize Center")
    return dlg
}

TestConnectionAction(hostStr, portStr, pwStr, statusLabel) {
    statusLabel.Value := "Testing connection..."
    endpoints := ParseCandidateEndpoints(hostStr, portStr)
    if (endpoints.Length == 0) {
        statusLabel.Value := "Error: No valid host address provided."
        return
    }

    testWs := ""
    testSuccess := false
    target := endpoints[1]

    OnTestMsg(ws, raw) {
        msg := (Type(raw) == "Buffer") ? StrGet(raw, "UTF-8") : String(raw)
        if RegExMatch(msg, '"op"\s*:\s*0') {
            authStr := ""
            if (RegExMatch(msg, '"salt"\s*:\s*"([^"]+)"', &mSalt) && RegExMatch(msg, '"challenge"\s*:\s*"([^"]+)"', &mChal)) {
                secret := HashSHA256_Base64(pwStr . mSalt[1])
                authResponse := HashSHA256_Base64(secret . mChal[1])
                authStr := ',"authentication":"' authResponse '"'
            }
            ws.sendText('{"op":1,"d":{"rpcVersion":1,"eventSubscriptions":0' authStr '}}')
        } else if RegExMatch(msg, '"op"\s*:\s*2') {
            testSuccess := true
            statusLabel.Value := "✓ Successfully connected to " target.raw "!"
            try ws.shutdown()
        }
    }

    OnTestClose(ws, st, re) {
        if (!testSuccess)
            statusLabel.Value := "✕ Connection failed to " target.raw " (Check IP, Port & Firewall)"
    }

    try {
        testWs := WebSocket("ws://" target.host ":" target.port, {
            message: OnTestMsg,
            close: OnTestClose
        }, true, "", 2500)
    } catch {
        statusLabel.Value := "✕ Host unreachable (Ensure primary device is online & port 4455 is open)"
    }
}
