; ==============================================================================
; Script: PresenterSync
; Description: OBS WebSocket and PowerPoint synchronization tool with system tray UI
; Version: 1.3.0
; Author: Saabith Jiffry
; License: MIT 
; ==============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
ProcessSetPriority "High"
SetKeyDelay 50, 50

#Include <WebSocket>
#Include <UIA>
#Include <Crypto>
#Include <Gdip>
#Include <OBS_Network>
#Include <GUI_Config>

Gdip.Startup()
OnExit((*) => Gdip.Shutdown())

if (!A_IsCompiled && FileExist(A_ScriptDir "\PresenterSync.ico"))
    try TraySetIcon(A_ScriptDir "\PresenterSync.ico")

; === CONFIGURATION & STATE ===
AppConfig := Config(A_ScriptDir "\MicOverlay_Config.ini")

; 1. First-run / missing shortcut setup: Audio Routing Mode + shortcuts
if (AppConfig.AudioRoutingMode == 0
    || ((AppConfig.AudioRoutingMode == 1 || AppConfig.AudioRoutingMode == 3) && (AppConfig.ObsMuteHotkey = "None" || AppConfig.ObsMuteHotkey = ""))
    || ((AppConfig.AudioRoutingMode == 2 || AppConfig.AudioRoutingMode == 3) && AppConfig.ZoomMuteHotkey = "")) {
    PromptForSetup(AppConfig)
}

; 2. Boot-up check: If WS is enabled but password is missing, ask for it
if (AppConfig.EnableWS && AppConfig.obsPassword = "") {
    AppConfig.obsPassword := PromptForPassword()
    if (AppConfig.obsPassword != "") {
        AppConfig.Write("Settings", "ObsPassword", AppConfig.obsPassword)
    } else {
        AppConfig.EnableWS := false
        AppConfig.WriteBool("Settings", "EnableWS", false)
    }
}

; 3. Show Help screen on very first launch
if (AppConfig.FirstRun) {
    AppConfig.FirstRun := false
    AppConfig.WriteBool("Settings", "FirstRun", false)
    ShowHelpWindow(AppConfig)
}

AppState := OverlayState(AppConfig)

if (AppConfig.EnableWS)
    SetTimer AppState.obsTimerFn, -UIConstants.OBS_INIT_DELAY_MS

UpdateZoomMonitorTimer(AppConfig, AppState)

; --- CUSTOM TRAY MENU ---
BuildTrayMenu(cfg, state) {
    A_TrayMenu.Delete()

    ; MODULE CONTROLS
    A_TrayMenu.Add("Enable Full Pointer Controls (PPT + Mute)", TogglePPT.Bind(cfg))
    if (cfg.EnablePPT)
        A_TrayMenu.Check("Enable Full Pointer Controls (PPT + Mute)")

    A_TrayMenu.Add("Enable Pointer Mute Only", ToggleMicOnly.Bind(cfg))
    if (cfg.EnableMicOnly)
        A_TrayMenu.Check("Enable Pointer Mute Only")

    A_TrayMenu.Add()

    A_TrayMenu.Add("Enable OBS WebSocket Sync", ToggleWS.Bind(cfg, state))
    if (cfg.EnableWS)
        A_TrayMenu.Check("Enable OBS WebSocket Sync")

    A_TrayMenu.Add("Enable Zoom Monitoring", ToggleZoom.Bind(cfg, state))
    if (cfg.EnableZoom)
        A_TrayMenu.Check("Enable Zoom Monitoring")

    ; MAIN UI TOGGLES
    A_TrayMenu.Add("Show Mute Indicator", ToggleIndicator.Bind(cfg, state))
    if (cfg.ShowIndicator)
        A_TrayMenu.Check("Show Mute Indicator")

    A_TrayMenu.Add("Show Extra HUDs", ToggleExtraHuds.Bind(cfg, state))
    if (cfg.ShowExtraHuds)
        A_TrayMenu.Check("Show Extra HUDs")

    ; APPEARANCE SUBMENU
    AppearanceMenu := Menu()
    AppearanceMenu.Add("Show Text Label", ToggleText.Bind(cfg))
    if (cfg.ShowText)
        AppearanceMenu.Check("Show Text Label")

    AppearanceMenu.Add("Use Monochromatic Icon", ToggleMono.Bind(cfg))
    if (cfg.MonoIcon)
        AppearanceMenu.Check("Use Monochromatic Icon")

    AppearanceMenu.Add("Use Sleek Corners", ToggleCorners.Bind(cfg))
    if (cfg.SleekCorners)
        AppearanceMenu.Check("Use Sleek Corners")

    AppearanceMenu.Add("Aggressive Mute Pulse", TogglePulse.Bind(cfg, state))
    if (cfg.AggressivePulse)
        AppearanceMenu.Check("Aggressive Mute Pulse")

    OpacityMenu := Menu()
    OpacityMenu.Add("Solid (100%)", SetSolid.Bind(cfg))
    OpacityMenu.Add("Frosted (85%)", SetFrosted.Bind(cfg))
    OpacityMenu.Add("Ghost (50%)", SetGhost.Bind(cfg))
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
        ScaleMenu.Add(opt.label, SetScale.Bind(cfg, opt.val))
        if (Abs(cfg.IndicatorScale - opt.val) < 0.001)
            ScaleMenu.Check(opt.label)
    }

    AppearanceMenu.Add("Indicator Scale", ScaleMenu)

    AppearanceMenu.Add()
    AppearanceMenu.Add("Restore Default Appearance", ResetAppearance.Bind(cfg))

    A_TrayMenu.Add("Indicator Appearance", AppearanceMenu)

    A_TrayMenu.Add()

    ; SETTINGS SUBMENU
    SettingsMenu := Menu()
    RoutingMenu := Menu()
    RoutingModes := [
        {label: "1: Pro OBS Setup (VB-Cable)", mode: 1},
        {label: "2: Standard Direct Mic (Zoom-Only)", mode: 2},
        {label: "3: Dual App Sync (OBS + Zoom)", mode: 3}
    ]
    for rm in RoutingModes {
        RoutingMenu.Add(rm.label, SetRoutingMode.Bind(cfg, rm.mode))
        if (cfg.AudioRoutingMode == rm.mode)
            RoutingMenu.Check(rm.label)
    }
    SettingsMenu.Add("Audio Routing Mode", RoutingMenu)
    SettingsMenu.Add("Launch Clicker Tester", ShowPointerTester)
    SettingsMenu.Add("Change App Shortcuts", ChangeAppHotkeysUI.Bind(cfg))
    SettingsMenu.Add("Configure Pointer Intercepts", ConfigurePointerKeysUI.Bind(cfg))
    SettingsMenu.Add("Change Pointer Mute Button", ChangeHwMuteHotkeyUI.Bind(cfg))
    SettingsMenu.Add("Change OBS Settings", ChangeObsSettingsUI.Bind(cfg))
    SettingsMenu.Add("Change Zoom Shortcuts", ChangeZoomShortcutsUI.Bind(cfg))
    SettingsMenu.Add("Reset Indicator Position", ResetTrayPosition.Bind(cfg))

    A_TrayMenu.Add("Settings", SettingsMenu)
    A_TrayMenu.Add("Help && Shortcuts", ShowHelpWindow.Bind(cfg))
    A_TrayMenu.Add("About PresenterSync", ShowAboutWindow)

    A_TrayMenu.Add("Suspend All Hotkeys", ToggleSuspend)
    A_TrayMenu.Add()
    A_TrayMenu.Add("Exit PresenterSync", ExitTrayApp)
}
BuildTrayMenu(AppConfig, AppState)

ToggleSuspend(*) {
    Suspend(-1)
    if A_IsSuspended {
        A_TrayMenu.Check("Suspend All Hotkeys")
        TrayTip("PresenterSync", "All hotkeys suspended.", 1)
    } else {
        A_TrayMenu.Uncheck("Suspend All Hotkeys")
        TrayTip("PresenterSync", "Hotkeys active.", 1)
    }
}

TogglePPT(cfg, *) {
    ToolTip()

    cfg.EnablePPT := !cfg.EnablePPT

    if (cfg.EnablePPT) {
        cfg.EnableMicOnly := false
        cfg.WriteBool("Settings", "EnableMicOnly", false)
        SetTrayCheck("Enable Pointer Mute Only", false)
        SetTrayCheck("Enable Full Pointer Controls (PPT + Mute)", true)
        ToolTip "Pointer Mode: Full PPT + Mute"
    } else {
        SetTrayCheck("Enable Full Pointer Controls (PPT + Mute)", false)
        ToolTip "Pointer Mode: OFF"
    }

    cfg.WriteBool("Settings", "EnablePPT", cfg.EnablePPT)
    SetTimer RemoveToolTip, -UIConstants.TOOLTIP_DURATION_MS
}

ToggleMicOnly(cfg, *) {
    ToolTip()

    cfg.EnableMicOnly := !cfg.EnableMicOnly

    if (cfg.EnableMicOnly) {
        cfg.EnablePPT := false
        cfg.WriteBool("Settings", "EnablePPT", false)
        SetTrayCheck("Enable Full Pointer Controls (PPT + Mute)", false)
        SetTrayCheck("Enable Pointer Mute Only", true)
        ToolTip "Pointer Mode: Mute Only"
    } else {
        SetTrayCheck("Enable Pointer Mute Only", false)
        ToolTip "Pointer Mode: OFF"
    }

    cfg.WriteBool("Settings", "EnableMicOnly", cfg.EnableMicOnly)
    SetTimer RemoveToolTip, -UIConstants.TOOLTIP_DURATION_MS
}

CyclePointerMode(cfg, *) {
    ToolTip()

    if (cfg.EnablePPT) {
        cfg.EnablePPT := false
        cfg.EnableMicOnly := true
        cfg.WriteBool("Settings", "EnablePPT", false)
        cfg.WriteBool("Settings", "EnableMicOnly", true)
        SetTrayCheck("Enable Full Pointer Controls (PPT + Mute)", false)
        SetTrayCheck("Enable Pointer Mute Only", true)
        ToolTip "Pointer Mode: Mute Only"
    } else if (cfg.EnableMicOnly) {
        cfg.EnableMicOnly := false
        cfg.WriteBool("Settings", "EnableMicOnly", false)
        SetTrayCheck("Enable Pointer Mute Only", false)
        ToolTip "Pointer Mode: OFF"
    } else {
        cfg.EnablePPT := true
        cfg.WriteBool("Settings", "EnablePPT", true)
        SetTrayCheck("Enable Full Pointer Controls (PPT + Mute)", true)
        ToolTip "Pointer Mode: Full PPT + Mute"
    }

    SetTimer RemoveToolTip, -UIConstants.TOOLTIP_DURATION_MS
}

ToggleWS(cfg, state, *) {
    ToolTip()

    cfg.EnableWS := !cfg.EnableWS

    if (cfg.EnableWS) {
        if (cfg.obsPassword = "") {
            cfg.obsPassword := PromptForPassword()
            if (cfg.obsPassword = "") {
                cfg.EnableWS := false
                return
            }
            cfg.Write("Settings", "ObsPassword", cfg.obsPassword)
        }

        if (cfg.EnableZoom) {
            cfg.EnableZoom := false
            state.zoomConnected := false
            state.zoomLastMuted := -1
            state.zoomRecGraceUntil := 0
            state.zoomSawRecControl := false
            cfg.WriteBool("Settings", "EnableZoom", false)
            SetTrayCheck("Enable Zoom Monitoring", false)
        }

        cfg.WriteBool("Settings", "EnableWS", true)
        SetTrayCheck("Enable OBS WebSocket Sync", true)
        ToolTip "WebSocket Sync: ON"
        SetTimer state.obsTimerFn, -UIConstants.OBS_INIT_DELAY_MS
    } else {
        cfg.WriteBool("Settings", "EnableWS", false)
        SetTrayCheck("Enable OBS WebSocket Sync", false)
        ToolTip "WebSocket Sync: OFF"
        SetTimer state.obsTimerFn, 0
        state.obsConnected := false
        state.zoomConnected := false
        state.zoomLastMuted := -1
        state.zoomRecGraceUntil := 0
        state.zoomSawRecControl := false
        if (state.obsWs) {
            state.obsWs.shutdown()
            state.obsWs := ""
        }
        SyncRecState(cfg, state, 0)
        SyncChatState(cfg, state, 0)
        SyncStudioState(cfg, state, false)
        SyncSceneState(cfg, state, "Scene")
    }

    UpdateZoomMonitorTimer(cfg, state)
    UpdateHudVisibility(cfg, state)
    SetTimer RemoveToolTip, -UIConstants.TOOLTIP_DURATION_MS
}

ToggleZoom(cfg, state, *) {
    ToolTip()

    cfg.EnableZoom := !cfg.EnableZoom

    if (cfg.EnableZoom) {
        if (cfg.EnableWS) {
            cfg.EnableWS := false
            cfg.WriteBool("Settings", "EnableWS", false)
            SetTrayCheck("Enable OBS WebSocket Sync", false)
            SetTimer state.obsTimerFn, 0
            state.obsConnected := false
            if (state.obsWs) {
                state.obsWs.shutdown()
                state.obsWs := ""
            }
            SyncRecState(cfg, state, 0)
            SyncStudioState(cfg, state, false)
            SyncSceneState(cfg, state, "Scene")
        }

        state.zoomRecGraceUntil := 0
        state.zoomSawRecControl := false
        cfg.WriteBool("Settings", "EnableZoom", true)
        SetTrayCheck("Enable Zoom Monitoring", true)
        ToolTip "Zoom Monitoring: ON"
    } else {
        cfg.WriteBool("Settings", "EnableZoom", false)
        SetTrayCheck("Enable Zoom Monitoring", false)
        state.zoomConnected := false
        state.zoomLastMuted := -1
        state.zoomRecGraceUntil := 0
        state.zoomSawRecControl := false
        SyncRecState(cfg, state, 0)
        SyncChatState(cfg, state, 0)
        ToolTip "Zoom Monitoring: OFF"
    }

    UpdateZoomMonitorTimer(cfg, state)
    UpdateHudVisibility(cfg, state)
    SetTimer RemoveToolTip, -UIConstants.TOOLTIP_DURATION_MS
}

ToggleIndicator(cfg, state, *) {
    cfg.ShowIndicator := !cfg.ShowIndicator
    cfg.WriteBool("Settings", "ShowIndicator", cfg.ShowIndicator)

    SetTrayCheck("Show Mute Indicator", cfg.ShowIndicator)
    UpdateHudVisibility(cfg, state)
    if (cfg.ShowIndicator && state.isMuted)
        SetTimer state.breathTimerFn, (cfg.AggressivePulse ? UIConstants.PULSE_INTERVAL_AGGRESSIVE : UIConstants.PULSE_INTERVAL_NORMAL)
    else if (!cfg.ShowIndicator)
        SetTimer state.breathTimerFn, 0
}

ToggleExtraHuds(cfg, state, *) {
    ToolTip()
    cfg.ShowExtraHuds := !cfg.ShowExtraHuds
    cfg.WriteBool("Settings", "ShowExtraHuds", cfg.ShowExtraHuds)

    SetTrayCheck("Show Extra HUDs", cfg.ShowExtraHuds)
    UpdateHudVisibility(cfg, state)
    ToolTip(cfg.ShowExtraHuds ? "Extra HUDs: ON" : "Extra HUDs: OFF")
    SetTimer RemoveToolTip, -UIConstants.TOOLTIP_DURATION_MS
}

ToggleText(cfg, *) {
    cfg.WriteBool("Settings", "ShowText", !cfg.ShowText)
    Reload()
}

ToggleMono(cfg, *) {
    cfg.WriteBool("Settings", "MonoIcon", !cfg.MonoIcon)
    Reload()
}

ToggleCorners(cfg, *) {
    cfg.WriteBool("Settings", "SleekCorners", !cfg.SleekCorners)
    Reload()
}

TogglePulse(cfg, state, *) {
    cfg.AggressivePulse := !cfg.AggressivePulse
    cfg.WriteBool("Settings", "AggressivePulse", cfg.AggressivePulse)
    SetTrayCheck("Aggressive Mute Pulse", cfg.AggressivePulse)

    if (state.isMuted) {
        state.breathDir := cfg.AggressivePulse ? -UIConstants.PULSE_STEP_AGGRESSIVE : -UIConstants.PULSE_STEP_NORMAL
        SetTimer state.breathTimerFn, (cfg.AggressivePulse ? UIConstants.PULSE_INTERVAL_AGGRESSIVE : UIConstants.PULSE_INTERVAL_NORMAL)
    }
}

SetSolid(cfg, *) {
    cfg.Write("Settings", "OpacityLevel", UIConstants.OPACITY_SOLID)
    Reload()
}

SetFrosted(cfg, *) {
    cfg.Write("Settings", "OpacityLevel", UIConstants.OPACITY_FROSTED)
    Reload()
}

SetGhost(cfg, *) {
    cfg.Write("Settings", "OpacityLevel", UIConstants.OPACITY_GHOST)
    Reload()
}

ExitTrayApp(*) {
    ExitApp()
}

InitHUD(AppConfig, AppState)

; --- SYSTEM HOTKEYS ---
try Hotkey(AppConfig.PptHotkey, (*) => CyclePointerMode(AppConfig))
try Hotkey(AppConfig.WsHotkey, (*) => ToggleWS(AppConfig, AppState))
try Hotkey(AppConfig.ZoomHotkey, (*) => ToggleZoom(AppConfig, AppState))
try Hotkey(AppConfig.IndHotkey, (*) => ToggleIndicator(AppConfig, AppState))
try Hotkey(AppConfig.SuspendHotkey, (*) => ToggleSuspend())
try Hotkey(AppConfig.ExitHotkey, (*) => ExitTrayApp())

RemoveToolTip() {
    ToolTip
}

; --- POWERPOINT CONTROLS (OMNI-CATCH) ---

#HotIf AppConfig.EnablePPT && AppConfig.CatchArrows
$Down::SendToPPT(AppConfig, "{Down}")
$Up::SendToPPT(AppConfig, "{Up}")
$Left::SendToPPT(AppConfig, "{Left}")
$Right::SendToPPT(AppConfig, "{Right}")

#HotIf AppConfig.EnablePPT && AppConfig.CatchPg
$PgDn::SendToPPT(AppConfig, "{PgDn}")
$PgUp::SendToPPT(AppConfig, "{PgUp}")

#HotIf AppConfig.EnablePPT && AppConfig.CatchSpace
$Space::SendToPPT(AppConfig, "{Space}")

#HotIf AppConfig.EnablePPT && AppConfig.CatchEnter
$Enter::SendToPPT(AppConfig, "{Enter}")

#HotIf AppConfig.EnablePPT && AppConfig.CatchTab
$Tab::SendToPPT(AppConfig, "{Tab}")

#HotIf AppConfig.EnablePPT && AppConfig.CatchEsc
$Esc::SendToPPT(AppConfig, "{Esc}")

#HotIf AppConfig.EnablePPT
$+F5::SendToPPT(AppConfig, "{Blind}{F5}") ; Always intercepted if PPT mode is active

#HotIf ; Reset directive

SendToPPT(cfg, Key) {
    static LastSignal := 0

    if (!cfg.EnablePPT) {
        return
    }

    if (A_TickCount - LastSignal < UIConstants.PPT_DEBOUNCE_MS) {
        return
    }
    LastSignal := A_TickCount

    if WinExist("ahk_class screenClass ahk_exe POWERPNT.EXE") {
        comHandled := false
        if (Key = "{Down}" || Key = "{Right}" || Key = "{PgDn}" || Key = "{Space}") {
            try {
                ComObjActive("PowerPoint.Application").SlideShowWindows(1).View.Next()
                comHandled := true
            }
        } else if (Key = "{Up}" || Key = "{Left}" || Key = "{PgUp}") {
            try {
                ComObjActive("PowerPoint.Application").SlideShowWindows(1).View.Previous()
                comHandled := true
            }
        }
        if (!comHandled) {
            try ControlSend Key,, "ahk_class screenClass ahk_exe POWERPNT.EXE"
        }
    }
    else if WinExist("PowerPoint Presenter View ahk_exe POWERPNT.EXE") {
        try ControlSend Key,, "PowerPoint Presenter View ahk_exe POWERPNT.EXE"
    }
    else if WinExist("ahk_class PPTFrameClass ahk_exe POWERPNT.EXE") {
        try ControlSend Key,, "ahk_class PPTFrameClass ahk_exe POWERPNT.EXE"
    }
    else if WinExist("ahk_exe POWERPNT.EXE") {
        try ControlSend Key,, "ahk_exe POWERPNT.EXE"
    }
    else {
        SoundPlay "*16"
    }
}

; --- DYNAMIC HARDWARE MUTE TRIGGER ---
CheckPointerEnable(cfg, ThisHotkey) {
    return (cfg.EnablePPT || cfg.EnableMicOnly)
}

HotIf CheckPointerEnable.Bind(AppConfig)
if (AppConfig.HwMuteHotkey != "") {
    try Hotkey(AppConfig.HwMuteHotkey, (*) => TriggerMute(AppConfig, AppState), "On")
}
HotIf

; --- MUTE CONTROL ---
FormatPassthroughHook(hk) {
    return "~$" RegExReplace(hk, "^[~*$]+")
}

RegisterPassthroughHooks(cfg, state) {
    if ((cfg.AudioRoutingMode == 1 || cfg.AudioRoutingMode == 3) && cfg.ObsMuteHotkey != "None" && cfg.ObsMuteHotkey != "")
        try Hotkey(FormatPassthroughHook(cfg.ObsMuteHotkey), LaptopKeyboardMute.Bind(cfg, state))
    if ((cfg.AudioRoutingMode == 2 || cfg.AudioRoutingMode == 3) && cfg.ZoomMuteHotkey != "")
        try Hotkey(FormatPassthroughHook(cfg.ZoomMuteHotkey), LaptopKeyboardMute.Bind(cfg, state))

    obsRecHook := (cfg.ObsRecHotkey != "") ? FormatPassthroughHook(cfg.ObsRecHotkey) : ""
    zoomRecHook := (cfg.ZoomRecHotkey != "") ? FormatPassthroughHook(cfg.ZoomRecHotkey) : ""
    if (obsRecHook != "" && obsRecHook = zoomRecHook) {
        try Hotkey(obsRecHook, LaptopCombinedRecToggle.Bind(cfg, state))
    } else {
        if (obsRecHook != "")
            try Hotkey(obsRecHook, LaptopObsRecToggle.Bind(cfg, state))
        if (zoomRecHook != "")
            try Hotkey(zoomRecHook, LaptopZoomRecToggle.Bind(cfg, state))
    }

    obsPauseHook := (cfg.ObsPauseHotkey != "") ? FormatPassthroughHook(cfg.ObsPauseHotkey) : ""
    zoomPauseHook := (cfg.ZoomPauseHotkey != "") ? FormatPassthroughHook(cfg.ZoomPauseHotkey) : ""
    if (obsPauseHook != "" && obsPauseHook = zoomPauseHook) {
        try Hotkey(obsPauseHook, LaptopCombinedPauseToggle.Bind(cfg, state))
    } else {
        if (obsPauseHook != "")
            try Hotkey(obsPauseHook, LaptopObsPauseToggle.Bind(cfg, state))
        if (zoomPauseHook != "")
            try Hotkey(zoomPauseHook, LaptopZoomPauseToggle.Bind(cfg, state))
    }
}
RegisterPassthroughHooks(AppConfig, AppState)

LaptopCombinedRecToggle(cfg, state, ThisHotkey) {
    LaptopObsRecToggle(cfg, state, ThisHotkey)
    LaptopZoomRecToggle(cfg, state, ThisHotkey)
}

LaptopCombinedPauseToggle(cfg, state, ThisHotkey) {
    LaptopObsPauseToggle(cfg, state, ThisHotkey)
    LaptopZoomPauseToggle(cfg, state, ThisHotkey)
}

LaptopObsRecToggle(cfg, state, ThisHotkey) {
    if (!state.obsConnected && cfg.EnableWS)
        SyncRecState(cfg, state, state.recState == 0 ? 1 : 0)
}

LaptopObsPauseToggle(cfg, state, ThisHotkey) {
    if (!state.obsConnected && cfg.EnableWS && state.recState != 0)
        SyncRecState(cfg, state, state.recState == 1 ? 2 : 1)
}

LaptopZoomRecToggle(cfg, state, ThisHotkey) {
    if (cfg.EnableZoom && !cfg.EnableWS) {
        state.zoomRecGraceUntil := A_TickCount + UIConstants.ZOOM_REC_GRACE_MS
        SyncRecState(cfg, state, state.recState == 0 ? 1 : 0)
    }
}

LaptopZoomPauseToggle(cfg, state, ThisHotkey) {
    if (cfg.EnableZoom && !cfg.EnableWS && state.recState != 0) {
        state.zoomRecGraceUntil := A_TickCount + UIConstants.ZOOM_REC_GRACE_MS
        SyncRecState(cfg, state, state.recState == 1 ? 2 : 1)
    }
}

LaptopKeyboardMute(cfg, state, ThisHotkey) {
    if (!state.obsConnected && !state.zoomConnected) {
        SyncUIState(cfg, state, !state.isMuted)
    }
}

TriggerMute(cfg, state) {
    if !(cfg.EnablePPT || cfg.EnableMicOnly) {
        return
    }

    obsOpen := WinExist("ahk_exe obs64.exe")
    zoomOpen := WinExist("ahk_exe Zoom.exe")

    if (cfg.AudioRoutingMode == 1) {
        if !obsOpen {
            SoundPlay "*16"
            return
        }
        SetKeyDelay -1, 30
        try ControlSend FormatSendKey(cfg.ObsMuteHotkey),, "ahk_exe obs64.exe"
        SetKeyDelay 50, 50
    } else if (cfg.AudioRoutingMode == 2) {
        if !zoomOpen {
            SoundPlay "*16"
            return
        }
        SetKeyDelay -1, 30
        try ControlSend FormatSendKey(cfg.ZoomMuteHotkey),, "ahk_exe Zoom.exe"
        SetKeyDelay 50, 50
    } else if (cfg.AudioRoutingMode == 3) {
        if (!obsOpen && !zoomOpen) {
            SoundPlay "*16"
            return
        }
        state.IsSyncing := true
        SetKeyDelay -1, 30
        if (obsOpen && cfg.ObsMuteHotkey != "None" && cfg.ObsMuteHotkey != "")
            try ControlSend FormatSendKey(cfg.ObsMuteHotkey),, "ahk_exe obs64.exe"
        if (zoomOpen && cfg.ZoomMuteHotkey != "")
            try ControlSend FormatSendKey(cfg.ZoomMuteHotkey),, "ahk_exe Zoom.exe"
        SetKeyDelay 50, 50
        SetTimer state.releaseSyncTimerFn, -UIConstants.SYNC_LOCK_TIMEOUT_MS
    }

    if (!state.obsConnected && !state.zoomConnected) {
        SyncUIState(cfg, state, !state.isMuted)
    }
}
