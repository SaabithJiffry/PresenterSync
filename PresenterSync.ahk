; ==============================================================================
; Script: PresenterSync
; Description: OBS WebSocket and PowerPoint synchronization tool with system tray UI
; Version: 8.5.4
; Author: Saabith Jiffry
; License: MIT
; ==============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Off
;@Ahk2Exe-SetMainIcon assets\PresenterSync.ico
;@Ahk2Exe-AddResource *10 assets\PresenterSync.ico, FAVICON_ICO
;@Ahk2Exe-SetProductName PresenterSync
;@Ahk2Exe-SetDescription PresenterSync - OBS WebSocket & Zoom + PowerPoint Controller
;@Ahk2Exe-SetVersion 8.5.4.0
ProcessSetPriority "High"
SendMode "Input"
SetKeyDelay -1, -1

#Include <WebSocket>
#Include <UIA>
#Include <Crypto>
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

if (A_Args.Length > 0) {
    cliCmd := ParseHostCliArgs(A_Args)
    if (cliCmd != "") {
        okCli := SendHostCliCopyData(cliCmd)
        ExitApp(okCli ? 0 : 1)
    }
}

EnforceHostSingleInstance() {
    prevDetect := A_DetectHiddenWindows
    DetectHiddenWindows(true)
    try {
        myPid := ProcessExist()
        for _, hwnd in WinGetList("PresenterSync_HostIpcMsg ahk_class AutoHotkeyGUI") {
            pid := WinGetPID(hwnd)
            if (pid && pid != myPid) {
                try {
                    exitCmd := "__exit__"
                    cds := Buffer(A_PtrSize * 3, 0)
                    NumPut("UPtr", 0x5053434C, cds, 0)
                    NumPut("UInt", (StrLen(exitCmd) + 1) * 2, cds, A_PtrSize)
                    NumPut("Ptr", StrPtr(exitCmd), cds, A_PtrSize * 2)
                    SendMessage(0x004A, 0, cds.Ptr, , "ahk_id " hwnd, , , , 1500)
                }
                deadline := A_TickCount + 800
                while (ProcessExist(pid) && A_TickCount < deadline) {
                    Sleep(50)
                }
                if (ProcessExist(pid)) {
                    try ProcessClose(pid)
                    Sleep(150)
                }
            }
        }
    }
    DetectHiddenWindows(prevDetect)
}
EnforceHostSingleInstance()

global AppState := ""
DiagnosticLogger.Init("PresenterSync")

Gdip.Startup()
ProcessSelfUpdateStartupCleanup(A_Args)
UnregisterHostWtsNotification(st) {
    if (IsObject(st) && st.HasOwnProp("ipcMsgGui") && IsObject(st.ipcMsgGui))
        try DllCall("Wtsapi32\WTSUnRegisterSessionNotification", "Ptr", st.ipcMsgGui.Hwnd)
}
ShutdownHostApp(*) {
    global AppState
    if (IsSet(AppState) && IsObject(AppState)) {
        try AppState.StopAllTimers()
        try UpdateAutoProfileTimer("", AppState)
        try UpdateCoreAudioWatchdogTimer("", AppState)
        try UpdateSafetyWatchdogTimer("", AppState)
        UnregisterHostWtsNotification(AppState)
        if (AppState.HasOwnProp("obsWs") && IsObject(AppState.obsWs)) {
            try AppState.obsWs.shutdown()
            AppState.obsWs := ""
        }
        if (AppState.HasOwnProp("relayWs") && IsObject(AppState.relayWs)) {
            try AppState.relayWs.shutdown()
            AppState.relayWs := ""
        }
    }
    if (IsSet(HideStageNudgeBanner))
        try HideStageNudgeBanner()
    try SessionTimeline.ClearAutosave()
    try StopHostCompanionBridge()
    try HudArcadeBase.StopActiveGame()
    try AudioMeter.Shutdown()
    try UIA.Shutdown()
    try Theme.Shutdown()
    try Gdip.Shutdown()
}
RegisterSelfUpdateBeforeRelaunch(ShutdownHostApp)
OnExit(ShutdownHostApp)

if (!A_IsCompiled && FileExist(A_ScriptDir "\assets\PresenterSync.ico"))
    try TraySetIcon(A_ScriptDir "\assets\PresenterSync.ico")
A_IconTip := "PresenterSync v" UIConstants.APP_VERSION

; === CONFIGURATION & STATE ===
AppConfig := Config(A_ScriptDir "\MicOverlay_Config.ini")
Theme.Init(AppConfig.ThemeMode)

; 1. First-run / missing shortcut setup: Audio Routing Mode + shortcuts
if (AppConfig.AudioRoutingMode == 0
    || (!AppConfig.EnableWS && (AppConfig.AudioRoutingMode == 1 || AppConfig.AudioRoutingMode == 3) && (AppConfig.ObsMuteHotkey = "None" || AppConfig.ObsMuteHotkey = ""))
    || ((AppConfig.AudioRoutingMode == 2 || AppConfig.AudioRoutingMode == 3) && AppConfig.ZoomMuteHotkey = "")) {
    PromptForSetup(AppConfig, true)
}

; 2. Initialize State, HUD, Tray Menu & Background Services
AppState := OverlayState(AppConfig)
DiagnosticLogger.BindContext(AppConfig, AppState)
recoveredTl := SessionTimeline.RecoverFromAutosave()
if (recoveredTl > 0)
    DiagnosticLogger.RecordBreadcrumb("Timeline", "RecoveredAutosave", "entries=" recoveredTl)
AppState.rebuildTrayFn := BuildTrayMenu.Bind(AppConfig, AppState)
AppState.rebindHotkeysFn := (*) => RebindAllHostHotkeys(AppConfig, AppState)
AppState.triggerMuteFn := (*) => TriggerMute(AppConfig, AppState, true)
AppState.triggerTransitionFn := (*) => TriggerObsSceneTransition(AppConfig, AppState, true)
AppState.pptNextFn := (*) => SendToPPT(AppConfig, "{Right}")
AppState.pptPrevFn := (*) => SendToPPT(AppConfig, "{Left}")
AppState.autoProfileTimerFn := PollAutoProfileTrigger.Bind(AppConfig, AppState)
BuildTrayMenu(AppConfig, AppState)
InitHUD(AppConfig, AppState)

if (AppConfig.FirstRun) {
    AppConfig.FirstRun := false
    AppConfig.WriteBool("Settings", "FirstRun", false)
    ShowGuidedSetupWizard(AppConfig, AppState)
}

if (AppConfig.EnableWS)
    SetTimer AppState.obsTimerFn, -UIConstants.OBS_INIT_DELAY_MS

UpdateZoomMonitorTimer(AppConfig, AppState)
if (AppConfig.EnableRemoteConnections)
    UpdateHostInternetRelay(AppConfig, AppState)
UpdateAutoProfileTimer(AppConfig, AppState)
UpdateCoreAudioWatchdogTimer(AppConfig, AppState)
UpdateSafetyWatchdogTimer(AppConfig, AppState)
if (AppConfig.EnableRemoteConnections)
    StartHostCompanionBridge(AppConfig, AppState, AppConfig.BridgePort)
OnMessage(0x0218, OnHostPowerBroadcast.Bind(AppConfig, AppState))
AppState.ipcMsgGui := Gui("-Caption +ToolWindow", "PresenterSync_HostIpcMsg")
try DllCall("Wtsapi32\WTSRegisterSessionNotification", "Ptr", AppState.ipcMsgGui.Hwnd, "UInt", 0)
OnMessage(0x02B1, (wParam, lParam, msg, hwnd) => HandleWtsSessionChange(wParam, lParam, AppConfig, AppState))
OnMessage(0x004A, OnHostCopyData.Bind(AppConfig, AppState))
StartBackgroundUpdateChecker(AppConfig, "PresenterSync.exe")

; --- CUSTOM TRAY MENU ---
_AddCheckedMenuItem(menuObj, label, handler, isChecked := false) {
    menuObj.Add(label, handler)
    if (isChecked)
        menuObj.Check(label)
}

BuildTrayMenu(cfg, state) {
    Theme.ApplyMenuTheme()
    A_TrayMenu.Delete()

    ; 1. ESSENTIALS (TOP-LEVEL)
    A_TrayMenu.Add("Control Center...", ShowControlCenterWindow.Bind(cfg, state))
    try A_TrayMenu.Default := "Control Center..."
    _AddCheckedMenuItem(A_TrayMenu, "Show Mute Indicator", ToggleIndicator.Bind(cfg, state), cfg.ShowIndicator)
    A_TrayMenu.Add()

    ; 2. LIVE CONTROLS (POINTER + SYNC ENGINES + REHEARSAL)
    LiveMenu := Menu()

    PointerMenu := Menu()
    _AddCheckedMenuItem(PointerMenu, "Full Pointer Controls (PPT + Mute)", TogglePPT.Bind(cfg, state), cfg.EnablePPT)
    _AddCheckedMenuItem(PointerMenu, "Pointer Mute Only", ToggleMicOnly.Bind(cfg, state), cfg.EnableMicOnly)
    _AddCheckedMenuItem(PointerMenu, "Pointer OBS Scene Transition", TogglePointerTransition.Bind(cfg, state), cfg.EnablePointerTransition)
    PointerMenu.Add()
    _AddCheckedMenuItem(PointerMenu, "Cough / Push-to-Mute (Hold)", TogglePushToMute.Bind(cfg, state), cfg.EnablePushToMute)
    _AddCheckedMenuItem(PointerMenu, "Push-to-Talk (Hold to Unmute)", TogglePushToTalk.Bind(cfg, state), cfg.HasOwnProp("EnablePushToTalk") && cfg.EnablePushToTalk)
    PointerMenu.Add()
    PointerMenu.Add("Change Pointer Mute Button...", ChangeHwMuteHotkeyUI.Bind(cfg, state))
    PointerMenu.Add("Change Pointer OBS Transition Button...", ChangeHwTransitionHotkeyUI.Bind(cfg, state))
    PointerMenu.Add("Configure Pointer Intercepts...", ConfigurePointerKeysUI.Bind(cfg, state))
    PointerMenu.Add("Launch Clicker Tester...", ShowPointerTester)
    LiveMenu.Add("Pointer && Clicker", PointerMenu)

    SyncMenu := Menu()
    _AddCheckedMenuItem(SyncMenu, "OBS WebSocket Sync", ToggleWS.Bind(cfg, state), cfg.EnableWS)
    _AddCheckedMenuItem(SyncMenu, "Conferencing Monitoring (Zoom/Teams/Meet)", ToggleZoom.Bind(cfg, state), cfg.EnableZoom)
    SyncMenu.Add()
    RoutingMenu := Menu()
    RoutingModes := [{ label: "1: Pro OBS Setup (VB-Cable)", mode: 1 }, { label: "2: Standard Direct Mic (Zoom-Only)", mode: 2 }, { label: "3: Dual App Sync (OBS + Zoom)", mode: 3 }]
    for rm in RoutingModes
        _AddCheckedMenuItem(RoutingMenu, rm.label, SetRoutingMode.Bind(cfg, rm.mode), cfg.AudioRoutingMode == rm.mode)
    SyncMenu.Add("Audio Routing Mode", RoutingMenu)

    ConfMenu := Menu()
    for cApp in GetConferencingAppNames()
        _AddCheckedMenuItem(ConfMenu, cApp, SetConferencingApp.Bind(cfg, state, cApp), NormalizeConferencingApp(cfg.ConferencingApp) = cApp)
    SyncMenu.Add("Conferencing Platform", ConfMenu)
    LiveMenu.Add("Sync Engines", SyncMenu)
    LiveMenu.Add()
    LiveMenu.Add("Go Live 10-Second Rehearsal...", (*) => ShowPreFlightRehearsalDialog(cfg, state))
    A_TrayMenu.Add("Live Controls", LiveMenu)

    ; 3. OBS DIRECTOR & STAGE
    DirectorMenu := Menu()
    isStandby := (IsObject(state) && state.HasOwnProp("isStandby") && state.isStandby)
    _AddCheckedMenuItem(DirectorMenu, "Toggle Standby / `"BRB`" Curtain", (*) => ExecuteHostToggleStandby(cfg, state), isStandby)
    SceneSwitchMenu := Menu()
    if (IsObject(state) && state.HasOwnProp("sceneList") && IsObject(state.sceneList) && state.sceneList.Length > 0) {
        for scName in state.sceneList {
            dispSc := StrReplace(scName, "&", "&&")
            _AddCheckedMenuItem(SceneSwitchMenu, dispSc, ((s, *) => ExecuteHostSwitchScene(cfg, state, s)).Bind(scName), state.HasOwnProp("currentSceneName") && state.currentSceneName == scName)
        }
    } else {
        SceneSwitchMenu.Add("Connect OBS for scenes", (*) => 0)
        SceneSwitchMenu.Disable("Connect OBS for scenes")
    }
    DirectorMenu.Add("Switch OBS Scene", SceneSwitchMenu)
    DirectorMenu.Add()
    DirectorMenu.Add("Pause / Resume Recording", (*) => ExecuteHostPauseRecord(cfg, state))
    DirectorMenu.Add("Split Recording Chapter", (*) => ExecuteHostSplitRecord(cfg, state))
    DirectorMenu.Add()
    DirectorMenu.Add("Presenter Countdown Timer", BuildSharedPresenterTimerSubmenu(state, (sec, *) => StartHostPresenterTimer(cfg, state, sec), (*) => PauseHostPresenterTimer(cfg, state), (sec, *) => ResetHostPresenterTimer(cfg, state, sec)))
    DirectorMenu.Add("Send Stage Nudge...", (*) => PromptSendStageNudgeUI((msg) => BroadcastHostStageNudge(cfg, state, msg, "Primary Host")))
    DirectorMenu.Add("View && Export Session Timeline...", (*) => SessionTimeline.ShowTimelineWindow(cfg, state))
    A_TrayMenu.Add("OBS Director && Stage", DirectorMenu)

    ; 4. HUD & APPEARANCE (CATEGORIZED SUBMENUS)
    AppearanceMenu := Menu()

    PanelsMenu := Menu()
    _AddCheckedMenuItem(PanelsMenu, "Show Mute Indicator", ToggleIndicator.Bind(cfg, state), cfg.ShowIndicator)
    _AddCheckedMenuItem(PanelsMenu, "Show Extra HUDs", ToggleExtraHuds.Bind(cfg, state), cfg.ShowExtraHuds)
    _AddCheckedMenuItem(PanelsMenu, "Show Recording && Chat HUD (Row 2)", (*) => ToggleHudOptionAndRebuild(cfg, state, "ShowRow2RecChatHud", "Settings", RefreshHudAppearance, BuildTrayMenu, NotifyHelpRefresh), cfg.ShowRow2RecChatHud)
    _AddCheckedMenuItem(PanelsMenu, "Show Studio && Scene HUD (Row 3)", (*) => ToggleHudOptionAndRebuild(cfg, state, "ShowRow3StudioSceneHud", "Settings", RefreshHudAppearance, BuildTrayMenu, NotifyHelpRefresh), cfg.ShowRow3StudioSceneHud)
    _AddCheckedMenuItem(PanelsMenu, "Show Stream && VCam HUD (Row 4)", ToggleStreamHud.Bind(cfg, state), cfg.ShowStreamHud)
    _AddCheckedMenuItem(PanelsMenu, "Show Secondary Mic Pill (Mic-Only)", ToggleSecondaryMicLive.Bind(cfg, state), cfg.ShowSecondaryMicHud)
    PanelsMenu.Add()
    _AddCheckedMenuItem(PanelsMenu, "Show Live Voice Activity Bar", ToggleVoiceMeter.Bind(cfg, state), cfg.ShowVoiceMeter)
    _AddCheckedMenuItem(PanelsMenu, "Show Recording Elapsed Timer", ToggleRecTimer.Bind(cfg, state), cfg.ShowRecTimer)
    AppearanceMenu.Add("HUD Panels && Visibility", PanelsMenu)

    StyleMenu := Menu()
    BuildSharedAppearanceSubmenus(StyleMenu, cfg, state, SetPrimaryOpacityLive.Bind(cfg, state), ApplyScaleLive.Bind(cfg, state), ApplyThemeLive.Bind(cfg, state))
    StyleMenu.Add()
    _AddCheckedMenuItem(StyleMenu, "Show Text Label", ToggleText.Bind(cfg, state), cfg.ShowText)
    _AddCheckedMenuItem(StyleMenu, "Use Monochromatic Icon", ToggleMono.Bind(cfg, state), cfg.MonoIcon)
    _AddCheckedMenuItem(StyleMenu, "Use Sleek Corners", ToggleCorners.Bind(cfg, state), cfg.SleekCorners)
    AppearanceMenu.Add("Visual Style && Sizing", StyleMenu)

    AlertsMenu := Menu()
    _AddCheckedMenuItem(AlertsMenu, "Aggressive Mute Pulse", TogglePulse.Bind(cfg, state), cfg.AggressivePulse)
    _AddCheckedMenuItem(AlertsMenu, "Mute Audio Cue (Beep)", ToggleAudioCue.Bind(cfg, state), cfg.EnableAudioCue)
    _AddCheckedMenuItem(AlertsMenu, "Mute Status Toast", ToggleMuteToast.Bind(cfg, state), cfg.EnableMuteToast)
    _AddCheckedMenuItem(AlertsMenu, "Voice-While-Muted Alert", (*) => (ToggleBoolSetting(cfg, state, "EnableVoiceWhileMutedAlert"), UpdateMutedVoiceMonitorTimer(cfg, state)), cfg.EnableVoiceWhileMutedAlert)
    AppearanceMenu.Add("Alerts && Feedback", AlertsMenu)

    BehaviorMenu := Menu()
    _AddCheckedMenuItem(BehaviorMenu, "Interactive HUD Click Actions", (*) => ToggleBoolSetting(cfg, state, "EnableHudClickActions"), cfg.EnableHudClickActions)
    _AddCheckedMenuItem(BehaviorMenu, "Magnetic Edge/Window Snap", ToggleMagneticSnap.Bind(cfg, state), cfg.EnableMagneticSnap)
    _AddCheckedMenuItem(BehaviorMenu, "Click-Through HUD (Hold Alt)", ToggleHudClickThrough.Bind(cfg, state), cfg.HudClickThrough)
    _AddCheckedMenuItem(BehaviorMenu, "Auto-Dodge HUD on Hover", ToggleHudAutoDodge.Bind(cfg, state), cfg.HudAutoDodge)
    BehaviorMenu.Add()
    _AddCheckedMenuItem(BehaviorMenu, "Hide HUD from Screen Share / Capture", (*) => ToggleHudOptionAndRebuild(cfg, state, "ExcludeFromCapture", "Settings", RefreshHudAppearance, BuildTrayMenu, NotifyHelpRefresh), cfg.ExcludeFromCapture)
    _AddCheckedMenuItem(BehaviorMenu, "Hide Secondary Pill from Capture", (*) => ToggleHudOptionAndRebuild(cfg, state, "ExcludeSecondaryFromCapture", "Settings", RefreshHudAppearance, BuildTrayMenu, NotifyHelpRefresh), cfg.ExcludeSecondaryFromCapture)
    AppearanceMenu.Add("Behavior && Capture Safety", BehaviorMenu)

    AppearanceMenu.Add()
    AppearanceMenu.Add("Reset Indicator Position", ApplyResetPositionLive.Bind(cfg, state))
    AppearanceMenu.Add("Reset Secondary Pill Position", ApplyResetSecondaryPositionLive.Bind(cfg, state))
    AppearanceMenu.Add("Restore Default Appearance", ApplyResetAppearanceLive.Bind(cfg, state))
    A_TrayMenu.Add("HUD && Appearance", AppearanceMenu)

    ; 5. REMOTE COMPANIONS
    RemoteMenu := Menu()
    RemoteMenu.Add("Remote Companion Setup && QR Info...", (*) => ShowRemoteCompanionInfo(cfg, state))
    RemoteNetMenu := Menu()
    _AddCheckedMenuItem(RemoteNetMenu, "Same Router (LAN)", SetRemoteNetworkMode.Bind(cfg, state, "LAN"), cfg.RemoteNetworkMode != "Internet")
    _AddCheckedMenuItem(RemoteNetMenu, "Different Networks (Internet)", SetRemoteNetworkMode.Bind(cfg, state, "Internet"), cfg.RemoteNetworkMode = "Internet")
    RemoteMenu.Add("Remote Network Mode", RemoteNetMenu)
    RemoteMenu.Add()
    _AddCheckedMenuItem(RemoteMenu, "Cut Off All Remote Connections (Standalone Mode)", ToggleRemoteConnectionsCutoff.Bind(cfg, state), !cfg.EnableRemoteConnections)
    RemoteMenu.Add("Close Remote Companion...", PromptCloseRemoteCompanion.Bind(cfg, state))
    A_TrayMenu.Add("Remote Companions", RemoteMenu)

    ; 6. CONFIGURATION
    ConfigMenu := Menu()
    ProfileMenu := Menu()
    for pName in cfg.GetProfileNames()
        _AddCheckedMenuItem(ProfileMenu, pName, SwitchProfileAction.Bind(cfg, state, pName), StrLower(cfg.ActiveProfile) = StrLower(pName))
    ProfileMenu.Add()
    _AddCheckedMenuItem(ProfileMenu, "Auto-Switch by Active App", ToggleAutoProfileSwitch.Bind(cfg, state), cfg.HasOwnProp("EnableAutoProfileSwitch") && cfg.EnableAutoProfileSwitch)
    ProfileMenu.Add("Save Current as New Profile...", (*) => ShowProfileManagerUI(cfg, state))
    ProfileMenu.Add("Manage Profiles && Auto Rules...", (*) => ShowProfileManagerUI(cfg, state))
    ConfigMenu.Add("Configuration Profiles", ProfileMenu)
    ConfigMenu.Add()
    ConfigMenu.Add("OBS Settings && Shortcuts...", ChangeObsSettingsUI.Bind(cfg, state))
    ConfigMenu.Add("Conferencing Shortcuts (Zoom/Teams/Meet)...", ChangeZoomShortcutsUI.Bind(cfg, state))
    ConfigMenu.Add("App Shortcuts...", ChangeAppHotkeysUI.Bind(cfg, state))
    ConfigMenu.Add()
    ConfigMenu.Add("Guided Setup Wizard (4-Step Check)...", (*) => ShowGuidedSetupWizard(cfg, state))
    ConfigMenu.Add("Audio Setup Wizard...", (*) => PromptForSetup(cfg, false))
    ConfigMenu.Add()
    _AddCheckedMenuItem(ConfigMenu, "Start with Windows", ToggleStartWithWindows.Bind(cfg, state), cfg.StartWithWindows)
    A_TrayMenu.Add("Configuration", ConfigMenu)

    ; 7. HELP & DIAGNOSTICS
    HelpMenu := Menu()
    HelpMenu.Add("Help && Shortcuts...", ShowHelpWindow.Bind(cfg, state))
    HelpMenu.Add()
    HelpMenu.Add("View Error && Diagnostic Log...", (*) => DiagnosticLogger.ShowLogViewerWindow(cfg, state))
    HelpMenu.Add("Export Sanitized Diagnostics...", (*) => ExportSanitizedDiagnostics(cfg, state, "", true))
    HelpMenu.Add()
    HelpMenu.Add("Check for Updates...", (*) => CheckForUpdates(UIConstants.APP_VERSION, "", false, "PresenterSync.exe", cfg))
    HelpMenu.Add("About PresenterSync...", ShowAboutWindow.Bind(cfg, state))
    A_TrayMenu.Add("Help && Diagnostics", HelpMenu)

    ; 8. SYSTEM SAFETY & EXIT
    A_TrayMenu.Add()
    _AddCheckedMenuItem(A_TrayMenu, "Suspend All Hotkeys", ToggleSuspend, Theme.SuspendLockCount > 0 ? Theme.WasSuspendedBeforeDialogs : A_IsSuspended)
    A_TrayMenu.Add("Exit PresenterSync", ExitTrayApp)
}

NotifyHelpRefresh(state) {
    if (IsObject(state) && state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn)
        try state.refreshHelpFn.Call()
}

ToggleRemoteConnectionsCutoff(cfg, state := "", *) {
    ToolTip()
    cfg.EnableRemoteConnections := !cfg.EnableRemoteConnections
    cfg.WriteBool("Settings", "EnableRemoteConnections", cfg.EnableRemoteConnections)
    if (!cfg.EnableRemoteConnections) {
        StopHostCompanionBridge()
        if (IsObject(state)) {
            UpdateHostInternetRelay(cfg, state)
            if (state.HasOwnProp("relayWs") && IsObject(state.relayWs)) {
                try state.relayWs.shutdown()
                state.relayWs := ""
            }
            state.relayConnected := false
        }
        ToolTip("Standalone Mode: All Remote Connections Cut Off")
    } else {
        if (IsObject(state)) {
            StartHostCompanionBridge(cfg, state, cfg.BridgePort)
            UpdateHostInternetRelay(cfg, state)
        }
        ToolTip("Remote Companion Connections: Enabled")
    }
    BuildTrayMenu(cfg, state)
    NotifyHelpRefresh(state)
    SetTimer RemoveToolTip, -UIConstants.TOOLTIP_DURATION_MS
}

ToggleSuspend(*) {
    if (Theme.SuspendLockCount > 0) {
        Theme.WasSuspendedBeforeDialogs := !Theme.WasSuspendedBeforeDialogs
        SetTrayCheck("Suspend All Hotkeys", Theme.WasSuspendedBeforeDialogs)
        TrayTip(Theme.WasSuspendedBeforeDialogs ? "Hotkeys will remain suspended after dialog closes." : "Hotkeys will resume after dialog closes.", "PresenterSync", 1)
        return
    }
    Suspend(-1)
    Theme.WasSuspendedBeforeDialogs := A_IsSuspended
    if A_IsSuspended {
        A_TrayMenu.Check("Suspend All Hotkeys")
        TrayTip("All hotkeys suspended.", "PresenterSync", 1)
    } else {
        A_TrayMenu.Uncheck("Suspend All Hotkeys")
        TrayTip("Hotkeys active.", "PresenterSync", 1)
    }
}

TogglePPT(cfg, state := "", *) {
    ToolTip()

    cfg.EnablePPT := !cfg.EnablePPT

    if (cfg.EnablePPT) {
        cfg.EnableMicOnly := false
        cfg.WriteBool("Settings", "EnableMicOnly", false)
        ToolTip "Pointer Mode: Full PPT + Mute"
    } else {
        ToolTip "Pointer Mode: OFF"
    }

    cfg.WriteBool("Settings", "EnablePPT", cfg.EnablePPT)
    RebindAllHostHotkeys(cfg, state)
    BuildTrayMenu(cfg, state)
    NotifyHelpRefresh(state)
    SetTimer RemoveToolTip, -UIConstants.TOOLTIP_DURATION_MS
}

ToggleMicOnly(cfg, state := "", *) {
    ToolTip()

    cfg.EnableMicOnly := !cfg.EnableMicOnly

    if (cfg.EnableMicOnly) {
        cfg.EnablePPT := false
        cfg.WriteBool("Settings", "EnablePPT", false)
        ToolTip "Pointer Mode: Mute Only"
    } else {
        ToolTip "Pointer Mode: OFF"
    }

    cfg.WriteBool("Settings", "EnableMicOnly", cfg.EnableMicOnly)
    RebindAllHostHotkeys(cfg, state)
    BuildTrayMenu(cfg, state)
    NotifyHelpRefresh(state)
    SetTimer RemoveToolTip, -UIConstants.TOOLTIP_DURATION_MS
}

TogglePointerTransition(cfg, state := "", *) {
    ToolTip()
    cfg.EnablePointerTransition := !cfg.EnablePointerTransition
    cfg.WriteBool("Settings", "EnablePointerTransition", cfg.EnablePointerTransition)
    if (IsObject(state) && state.HasOwnProp("rebindHotkeysFn") && state.rebindHotkeysFn)
        try state.rebindHotkeysFn.Call()
    ToolTip("Pointer OBS Scene Transition: " (cfg.EnablePointerTransition ? "ON" : "OFF"))
    BuildTrayMenu(cfg, state)
    NotifyHelpRefresh(state)
    SetTimer RemoveToolTip, -UIConstants.TOOLTIP_DURATION_MS
}

CyclePointerMode(cfg, state := "", *) {
    ToolTip()

    if (cfg.EnablePPT) {
        cfg.EnablePPT := false
        cfg.EnableMicOnly := true
        cfg.WriteBool("Settings", "EnablePPT", false)
        cfg.WriteBool("Settings", "EnableMicOnly", true)
        ToolTip "Pointer Mode: Mute Only"
    } else if (cfg.EnableMicOnly) {
        cfg.EnableMicOnly := false
        cfg.WriteBool("Settings", "EnableMicOnly", false)
        ToolTip "Pointer Mode: OFF"
    } else {
        cfg.EnablePPT := true
        cfg.WriteBool("Settings", "EnablePPT", true)
        ToolTip "Pointer Mode: Full PPT + Mute"
    }

    RebindAllHostHotkeys(cfg, state)
    BuildTrayMenu(cfg, state)
    NotifyHelpRefresh(state)
    SetTimer RemoveToolTip, -UIConstants.TOOLTIP_DURATION_MS
}

ToggleWS(cfg, state, *) {
    ToolTip()

    cfg.EnableWS := !cfg.EnableWS

    if (cfg.EnableWS) {
        cfg.WriteBool("Settings", "EnableWS", true)
        ToolTip "WebSocket Sync: ON"
        SetTimer state.obsTimerFn, -UIConstants.OBS_INIT_DELAY_MS
    } else {
        cfg.WriteBool("Settings", "EnableWS", false)
        ToolTip "WebSocket Sync: OFF"
        SetTimer state.obsTimerFn, 0
        state.obsConnected := false
        if IsObject(state.obsWs) {
            try state.obsWs.shutdown()
            state.obsWs := ""
        }
        SyncRecState(cfg, state, 0, -1, "obs")
        SyncStudioState(cfg, state, false)
        SyncSceneState(cfg, state, "Scene")
        SyncStreamState(cfg, state, 0)
        SyncVCamState(cfg, state, false)
    }

    UpdateZoomMonitorTimer(cfg, state)
    RefreshHudAppearance(cfg, state)
    BuildTrayMenu(cfg, state)
    NotifyHelpRefresh(state)
    SetTimer RemoveToolTip, -UIConstants.TOOLTIP_DURATION_MS
}

ToggleZoom(cfg, state, *) {
    ToolTip()

    cfg.EnableZoom := !cfg.EnableZoom

    if (cfg.EnableZoom) {
        state.zoomRecGraceUntil := 0
        state.zoomSawRecControl := false
        cfg.WriteBool("Settings", "EnableZoom", true)
        ToolTip "Zoom Monitoring: ON"
    } else {
        cfg.WriteBool("Settings", "EnableZoom", false)
        state.zoomConnected := false
        state.zoomLastMuted := -1
        state.zoomRecGraceUntil := 0
        state.zoomSawRecControl := false
        SyncRecState(cfg, state, 0, -1, "conf")
        SyncChatState(cfg, state, 0)
        ToolTip "Zoom Monitoring: OFF"
    }

    UpdateZoomMonitorTimer(cfg, state)
    RefreshHudAppearance(cfg, state)
    BuildTrayMenu(cfg, state)
    NotifyHelpRefresh(state)
    SetTimer RemoveToolTip, -UIConstants.TOOLTIP_DURATION_MS
}

ToggleIndicator(cfg, state, *) {
    cfg.ShowIndicator := !cfg.ShowIndicator
    cfg.WriteBool("Settings", "ShowIndicator", cfg.ShowIndicator)

    BuildTrayMenu(cfg, state)
    UpdateHudVisibility(cfg, state)
    if (IsAnyMicHudVisible(cfg) && state.isMuted)
        SetTimer state.breathTimerFn, (cfg.AggressivePulse ? UIConstants.PULSE_INTERVAL_AGGRESSIVE : UIConstants.PULSE_INTERVAL_NORMAL)
    else
        SetTimer state.breathTimerFn, 0
    NotifyHelpRefresh(state)
}

ToggleExtraHuds(cfg, state, *) {
    ToolTip()
    cfg.ShowExtraHuds := !cfg.ShowExtraHuds
    cfg.WriteBool("Settings", "ShowExtraHuds", cfg.ShowExtraHuds)

    RefreshHudAppearance(cfg, state)
    BuildTrayMenu(cfg, state)
    NotifyHelpRefresh(state)
    ToolTip(cfg.ShowExtraHuds ? "Extra HUDs: ON" : "Extra HUDs: OFF")
    SetTimer RemoveToolTip, -UIConstants.TOOLTIP_DURATION_MS
}

ToggleSecondaryMicLive(cfg, state, *) {
    ToolTip()
    ToggleSecondaryMicHud(cfg, state)
    BuildTrayMenu(cfg, state)
    NotifyHelpRefresh(state)
    ToolTip(cfg.ShowSecondaryMicHud ? "Secondary Mic Pill: ON" : "Secondary Mic Pill: OFF")
    SetTimer RemoveToolTip, -UIConstants.TOOLTIP_DURATION_MS
}

ToggleText(cfg, state, *) => ToggleHudOptionAndRebuild(cfg, state, "ShowText", "Settings", RefreshHudAppearance, BuildTrayMenu, NotifyHelpRefresh)
ToggleMono(cfg, state, *) => ToggleHudOptionAndRebuild(cfg, state, "MonoIcon", "Settings", RefreshHudAppearance, BuildTrayMenu, NotifyHelpRefresh)
ToggleCorners(cfg, state, *) => ToggleHudOptionAndRebuild(cfg, state, "SleekCorners", "Settings", RefreshHudAppearance, BuildTrayMenu, NotifyHelpRefresh)
TogglePulse(cfg, state, *) => ToggleHudOptionAndRebuild(cfg, state, "AggressivePulse", "Settings", RefreshHudAppearance, BuildTrayMenu, NotifyHelpRefresh)
SetPrimaryOpacityLive(cfg, state, val, *) => SetHudOpacityAndRebuild(cfg, state, val, "Settings", RefreshHudAppearance, BuildTrayMenu, "", NotifyHelpRefresh)

ApplyThemeLive(cfg, state, themeMenu, mode, *) {
    SetThemeMode(cfg, themeMenu, mode)
    BuildTrayMenu(cfg, state)
    NotifyHelpRefresh(state)
}

ApplyScaleLive(cfg, state, val, *) {
    SetScale(cfg, state, val)
    BuildTrayMenu(cfg, state)
    NotifyHelpRefresh(state)
}

ApplyResetPositionLive(cfg, state, *) {
    ResetTrayPosition(cfg, state)
    NotifyHelpRefresh(state)
}

ApplyResetSecondaryPositionLive(cfg, state, *) {
    ResetSecondaryTrayPosition(cfg, state)
    NotifyHelpRefresh(state)
}

ApplyResetAppearanceLive(cfg, state, *) {
    ResetAppearance(cfg, state)
    BuildTrayMenu(cfg, state)
    NotifyHelpRefresh(state)
}

ExitTrayApp(*) {
    ExitApp()
}

; --- SYSTEM HOTKEYS ---
BoundSystemHotkeys := []
BoundPptHotkeys := []
BoundHwMuteHotkey := ""
BoundHwTransitionHotkey := ""
BoundPassthroughHooks := []

_TryRegisterSystemHotkey(hk, handler) {
    global BoundSystemHotkeys
    if (hk != "" && hk != "None") {
        try Hotkey(hk, handler, "On")
        BoundSystemHotkeys.Push(hk)
    }
}

BindSystemHotkeys(cfg, state) {
    global BoundSystemHotkeys
    HotIf()
    for oldHk in BoundSystemHotkeys {
        try Hotkey(oldHk, "Off")
    }
    BoundSystemHotkeys := []
    _TryRegisterSystemHotkey(cfg.PptHotkey, (*) => CyclePointerMode(cfg, state))
    _TryRegisterSystemHotkey(cfg.WsHotkey, (*) => ToggleWS(cfg, state))
    _TryRegisterSystemHotkey(cfg.ZoomHotkey, (*) => ToggleZoom(cfg, state))
    _TryRegisterSystemHotkey(cfg.IndHotkey, (*) => ToggleIndicator(cfg, state))
    if (cfg.SuspendHotkey != "" && cfg.SuspendHotkey != "None") {
        try Hotkey(cfg.SuspendHotkey, (*) => ToggleSuspend(), "S")
        try Hotkey(cfg.SuspendHotkey, "On")
        BoundSystemHotkeys.Push(cfg.SuspendHotkey)
    }
    _TryRegisterSystemHotkey(cfg.ExitHotkey, (*) => ExitTrayApp())
    _TryRegisterSystemHotkey(cfg.RemoteInfoHotkey, (*) => ShowRemoteCompanionInfo(cfg, state))
    ArcadeVault.RegisterGame("snake", "HUD Snake", "!^+s", "Ctrl+Alt+Shift+S", (c, s) => HudSnake.Toggle(c, s), () => HudSnake.Stop())
    ArcadeVault.RegisterGame("asteroids", "Asteroid Blaster", "!^+a", "Ctrl+Alt+Shift+A", (c, s) => GameAsteroids.Toggle(c, s), () => GameAsteroids.Stop())
    ArcadeVault.RegisterGame("brick_breaker", "Brick Breaker", "!^+b", "Ctrl+Alt+Shift+B", (c, s) => GameBrickBreaker.Toggle(c, s), () => GameBrickBreaker.Stop())
    ArcadeVault.RegisterGame("cyber_pong", "Cyber Pong", "!^+h", "Ctrl+Alt+Shift+H", (c, s) => GameCyberPong.Toggle(c, s), () => GameCyberPong.Stop())
    ArcadeVault.RegisterGame("flappy", "Clicker Flappy / Wave", "!^+f", "Ctrl+Alt+Shift+F", (c, s) => GameClickerFlappy.Toggle(c, s), () => GameClickerFlappy.Stop())
    ArcadeVault.RegisterGame("tron", "Neon Light Cycles (TRON)", "!^+t", "Ctrl+Alt+Shift+T", (c, s) => GameLightCycles.Toggle(c, s), () => GameLightCycles.Stop())
    ArcadeVault.RegisterGame("pac_grid", "Neon Pac-Grid", "!^+c", "Ctrl+Alt+Shift+C", (c, s) => GamePacGrid.Toggle(c, s), () => GamePacGrid.Stop())
    ArcadeVault.RegisterGame("missile_defense", "Missile Defense", "!^+m", "Ctrl+Alt+Shift+M", (c, s) => GameMissileDefense.Toggle(c, s), () => GameMissileDefense.Stop())
    ArcadeVault.BindVaultHotkey(cfg, state)
}
BindSystemHotkeys(AppConfig, AppState)

RemoveToolTip() {
    ToolTip
}

; --- POWERPOINT CONTROLS (PRE-COMPUTED DYNAMIC INTERCEPTION) ---
IsPptInterceptActive(cfg, ThisHotkey := "") {
    return cfg.EnablePPT && !HudArcadeBase.IsAnyGameActive() && (Theme.OpenWindows.Count == 0 || !Theme.OpenWindows.Has(WinExist("A")))
}

IsPptKeyNotMute(cfg, pptKey) {
    return IsPptKeyAllowed(cfg, pptKey)
}

PptCondFn := IsPptInterceptActive.Bind(AppConfig)

BindPptInterceptHotkeys(cfg, state := "") {
    global BoundPptHotkeys, PptCondFn
    HotIf PptCondFn
    try {
        for oldHk in BoundPptHotkeys {
            try Hotkey(oldHk, "Off")
        }
        BoundPptHotkeys := []

        if (!cfg.EnablePPT)
            return

        pptBindings := [
            { key: "Down", send: "{Down}" },
            { key: "Up", send: "{Up}" },
            { key: "Left", send: "{Left}" },
            { key: "Right", send: "{Right}" },
            { key: "PgDn", send: "{PgDn}" },
            { key: "PgUp", send: "{PgUp}" },
            { key: "Space", send: "{Space}" },
            { key: "Enter", send: "{Enter}" },
            { key: "Tab", send: "{Tab}" },
            { key: "Esc", send: "{Esc}" },
            { key: "+F5", send: "{Blind}{F5}" }
        ]

        for item in pptBindings {
            if IsPptKeyAllowed(cfg, item.key) {
                hkName := "$" item.key
                sendKey := item.send
                try {
                    Hotkey(hkName, ((k, *) => SendToPPT(cfg, k)).Bind(sendKey), "On")
                    BoundPptHotkeys.Push(hkName)
                }
            }
        }
    } finally {
        HotIf
    }
}
BindPptInterceptHotkeys(AppConfig, AppState)

SendToPPT(cfg, Key) {
    static LastSignal := 0

    if (!cfg.EnablePPT) {
        return
    }

    if (A_TickCount - LastSignal < UIConstants.PPT_DEBOUNCE_MS) {
        return
    }
    LastSignal := A_TickCount
    t0 := A_TickCount
    DiagnosticLogger.RecordBreadcrumb("Input", "SendToPPT", Key)

    if WinExist("ahk_class screenClass ahk_exe POWERPNT.EXE") {
        if (IsSet(SessionTimeline))
            SessionTimeline.Record("Slide", "Slide Control", "", Key)
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
            try ControlSend Key, , "ahk_class screenClass ahk_exe POWERPNT.EXE"
        }
        try PollPowerPointSlideTelemetry(AppState)
        if (IsSet(HostBridgeBroadcastMuteState))
            try HostBridgeBroadcastMuteState(cfg, AppState)
    } else {
        sentFallbackPpt := false
        for _, winSpec in ["PowerPoint Presenter View ahk_exe POWERPNT.EXE", "ahk_class PPTFrameClass ahk_exe POWERPNT.EXE", "ahk_exe POWERPNT.EXE"] {
            if WinExist(winSpec) {
                try ControlSend Key, , winSpec
                sentFallbackPpt := true
                break
            }
        }
        if (!sentFallbackPpt) {
            dir := (Key = "{Up}" || Key = "{Left}" || Key = "{PgUp}") ? "prev" : "next"
            fb := TryDispatchFallbackSlideKey(dir)
            if (!fb.handled)
                SoundPlay "*16"
        }
    }
    DiagnosticLogger.CheckLatency("Input", "SendToPPT", t0, 120, Key)
}

; --- DYNAMIC HARDWARE MUTE & SCENE TRANSITION TRIGGERS ---
CheckPointerEnable(cfg, ThisHotkey) {
    return (cfg.EnablePPT || cfg.EnableMicOnly) && (Theme.OpenWindows.Count == 0 || !Theme.OpenWindows.Has(WinExist("A")))
}

PointerCondFn := CheckPointerEnable.Bind(AppConfig)

BindHwMuteHotkey(cfg, state) {
    global BoundHwMuteHotkey, PointerCondFn
    HotIf PointerCondFn
    try {
        if (BoundHwMuteHotkey != "") {
            try Hotkey(BoundHwMuteHotkey, "Off")
            BoundHwMuteHotkey := ""
        }
        if (!(cfg.EnablePPT || cfg.EnableMicOnly) || cfg.HwMuteHotkey = "" || cfg.HwMuteHotkey = "None")
            return
        hk := "$" RegExReplace(Trim(cfg.HwMuteHotkey), "^[~*$]+")
        try {
            Hotkey(hk, (*) => TriggerMute(cfg, state), "On")
            BoundHwMuteHotkey := hk
        }
    } finally {
        HotIf
    }
}
BindHwMuteHotkey(AppConfig, AppState)

CheckTransitionEnable(cfg, ThisHotkey := "") {
    return !HudArcadeBase.IsAnyGameActive() && cfg.EnablePointerTransition && (Theme.OpenWindows.Count == 0 || !Theme.OpenWindows.Has(WinExist("A")))
}

TransitionCondFn := CheckTransitionEnable.Bind(AppConfig)

BindHwTransitionHotkey(cfg, state) {
    global BoundHwTransitionHotkey, TransitionCondFn
    HotIf TransitionCondFn
    try {
        if (BoundHwTransitionHotkey != "") {
            try Hotkey(BoundHwTransitionHotkey, "Off")
            BoundHwTransitionHotkey := ""
        }
        if (!cfg.EnablePointerTransition || cfg.HwTransitionHotkey = "" || cfg.HwTransitionHotkey = "None")
            return
        hk := "$" RegExReplace(Trim(cfg.HwTransitionHotkey), "^[~*$]+")
        try {
            Hotkey(hk, (*) => TriggerObsSceneTransition(cfg, state), "On")
            BoundHwTransitionHotkey := hk
        }
    } finally {
        HotIf
    }
}
BindHwTransitionHotkey(AppConfig, AppState)

_RegisterSinglePassthroughHook(rawHk, handler) {
    global BoundPassthroughHooks
    if (rawHk = "" || rawHk = "None")
        return
    hk := FormatPassthroughHook(rawHk)
    try {
        Hotkey(hk, handler, "On")
        BoundPassthroughHooks.Push(hk)
    }
}

_RegisterPassthroughPair(cfg, state, rawHkA, rawHkB, combinedFn, fnA, fnB) {
    global BoundPassthroughHooks
    hookA := (rawHkA != "" && rawHkA != "None") ? FormatPassthroughHook(rawHkA) : ""
    hookB := (rawHkB != "" && rawHkB != "None") ? FormatPassthroughHook(rawHkB) : ""
    if (hookA != "" && hookA = hookB) {
        try {
            Hotkey(hookA, combinedFn.Bind(cfg, state), "On")
            BoundPassthroughHooks.Push(hookA)
        }
        return
    }
    if (hookA != "") {
        try {
            Hotkey(hookA, fnA.Bind(cfg, state), "On")
            BoundPassthroughHooks.Push(hookA)
        }
    }
    if (hookB != "") {
        try {
            Hotkey(hookB, fnB.Bind(cfg, state), "On")
            BoundPassthroughHooks.Push(hookB)
        }
    }
}

; --- MUTE & TRANSITION PASSTHROUGH CONTROL ---
RegisterPassthroughHooks(cfg, state) {
    global BoundPassthroughHooks
    HotIf
    for oldHook in BoundPassthroughHooks {
        try Hotkey(oldHook, "Off")
    }
    BoundPassthroughHooks := []

    if (cfg.AudioRoutingMode == 1 || cfg.AudioRoutingMode == 3)
        _RegisterSinglePassthroughHook(cfg.ObsMuteHotkey, LaptopKeyboardMute.Bind(cfg, state))
    _RegisterSinglePassthroughHook(cfg.ObsTransitionHotkey, LaptopObsTransitionPassthrough.Bind(cfg, state))
    if (cfg.AudioRoutingMode == 2 || cfg.AudioRoutingMode == 3)
        _RegisterSinglePassthroughHook(GetActiveConferencingMuteHotkey(cfg), LaptopKeyboardMute.Bind(cfg, state))

    _RegisterPassthroughPair(cfg, state, cfg.ObsRecHotkey, cfg.ZoomRecHotkey, LaptopCombinedRecToggle, LaptopObsRecToggle, LaptopZoomRecToggle)
    _RegisterPassthroughPair(cfg, state, cfg.ObsPauseHotkey, cfg.ZoomPauseHotkey, LaptopCombinedPauseToggle, LaptopObsPauseToggle, LaptopZoomPauseToggle)
}
RegisterPassthroughHooks(AppConfig, AppState)

RebindAllHostHotkeys(cfg, state) {
    BindSystemHotkeys(cfg, state)
    BindPptInterceptHotkeys(cfg, state)
    BindHwMuteHotkey(cfg, state)
    BindHwTransitionHotkey(cfg, state)
    RegisterPassthroughHooks(cfg, state)
}

LaptopObsTransitionPassthrough(cfg, state, ThisHotkey := "") {
    DiagnosticLogger.RecordBreadcrumb("Input", "ObsTransitionPassthrough", cfg.ObsTransitionHotkey)
}

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
    if (cfg.EnableZoom) {
        state.zoomRecGraceUntil := A_TickCount + UIConstants.ZOOM_REC_GRACE_MS
        curConf := state.HasOwnProp("confRecState") ? state.confRecState : state.recState
        SyncRecState(cfg, state, curConf == 0 ? 1 : 0, -1, "conf")
    }
}

LaptopZoomPauseToggle(cfg, state, ThisHotkey) {
    curConf := state.HasOwnProp("confRecState") ? state.confRecState : state.recState
    if (cfg.EnableZoom && curConf != 0) {
        state.zoomRecGraceUntil := A_TickCount + UIConstants.ZOOM_REC_GRACE_MS
        SyncRecState(cfg, state, curConf == 1 ? 2 : 1, -1, "conf")
    }
}

LaptopKeyboardMute(cfg, state, ThisHotkey) {
    if (ShouldOptimisticallyFlipMute(cfg, state)) {
        SyncUIState(cfg, state, !state.isMuted)
    }
}

TriggerMute(cfg, state, fromHudClick := false) {
    static lastTick := 0
    static inHold := false
    if (inHold)
        return false
    now := A_TickCount
    if (now - lastTick < 150) ; 150ms hardware debounce shield
        return false
    lastTick := now

    if (!fromHudClick && !(cfg.EnablePPT || cfg.EnableMicOnly)) {
        return
    }

    inHold := true
    try {
        if (!fromHudClick && cfg.HasOwnProp("EnablePushToTalk") && cfg.EnablePushToTalk) {
            ExecutePushToTalkHoldCycle(cfg, state, (m) => ExecuteHostRemoteSetMute(cfg, state, m), cfg.HwMuteHotkey, state.HasOwnProp("keyWaitFn") ? state.keyWaitFn : "")
            lastTick := A_TickCount
        } else if (DispatchHostMuteToggle(cfg, state)) {
            if (!fromHudClick && WaitPushToMuteRelease(cfg, cfg.HwMuteHotkey, state.HasOwnProp("keyWaitFn") ? state.keyWaitFn : "")) {
                DispatchHostMuteToggle(cfg, state)
                lastTick := A_TickCount
            }
        }
    } finally {
        inHold := false
    }
}

OnHostPowerBroadcast(cfg, state, wParam, lParam, msg, hwnd) {
    HandleHostPowerEvent(cfg, state, wParam, lParam)
}