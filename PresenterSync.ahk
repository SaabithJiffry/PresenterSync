; ==============================================================================
; Script: PresenterSync
; Description: OBS WebSocket and PowerPoint synchronization tool with system tray UI
; Version: 7.6.1
; Author: Saabith Jiffry
; License: MIT
; ==============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Off
;@Ahk2Exe-SetMainIcon assets\PresenterSync.ico
;@Ahk2Exe-SetProductName PresenterSync
;@Ahk2Exe-SetDescription PresenterSync - OBS WebSocket & Zoom + PowerPoint Controller
;@Ahk2Exe-SetVersion 7.6.1.0
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
                try ProcessClose(pid)
                Sleep(150)
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
RegisterSelfUpdateBeforeRelaunch((*) => ((IsSet(AppState) && IsObject(AppState)) ? (UpdateAutoProfileTimer("", AppState), UpdateCoreAudioWatchdogTimer("", AppState), UpdateSafetyWatchdogTimer("", AppState), (AppState.HasOwnProp("presenterTimerFn") && AppState.presenterTimerFn) ? SetTimer(AppState.presenterTimerFn, 0) : 0, UnregisterHostWtsNotification(AppState)) : 0, SessionTimeline.ClearAutosave(), StopHostCompanionBridge(), HudSnake.Stop(), AudioMeter.Shutdown(), UIA.Shutdown(), Theme.Shutdown(), Gdip.Shutdown()))
OnExit((*) => ((IsSet(AppState) && IsObject(AppState)) ? (UpdateAutoProfileTimer("", AppState), UpdateCoreAudioWatchdogTimer("", AppState), UpdateSafetyWatchdogTimer("", AppState), (AppState.HasOwnProp("presenterTimerFn") && AppState.presenterTimerFn) ? SetTimer(AppState.presenterTimerFn, 0) : 0, UnregisterHostWtsNotification(AppState)) : 0, SessionTimeline.ClearAutosave(), StopHostCompanionBridge(), HudSnake.Stop(), AudioMeter.Shutdown(), UIA.Shutdown(), Theme.Shutdown(), Gdip.Shutdown()))

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
BuildTrayMenu(cfg, state) {
    Theme.ApplyMenuTheme()
    A_TrayMenu.Delete()

    ; 1. POINTER CONTROLS (LIVE PRESENTATION)
    A_TrayMenu.Add("Enable Full Pointer Controls (PPT + Mute)", TogglePPT.Bind(cfg, state))
    if (cfg.EnablePPT)
        A_TrayMenu.Check("Enable Full Pointer Controls (PPT + Mute)")

    A_TrayMenu.Add("Enable Pointer Mute Only", ToggleMicOnly.Bind(cfg, state))
    if (cfg.EnableMicOnly)
        A_TrayMenu.Check("Enable Pointer Mute Only")

    A_TrayMenu.Add("Enable Pointer OBS Scene Transition", TogglePointerTransition.Bind(cfg, state))
    if (cfg.EnablePointerTransition)
        A_TrayMenu.Check("Enable Pointer OBS Scene Transition")

    A_TrayMenu.Add()

    ; 2. LIVE SYNC & MONITORING MODES
    A_TrayMenu.Add("Enable OBS WebSocket Sync", ToggleWS.Bind(cfg, state))
    if (cfg.EnableWS)
        A_TrayMenu.Check("Enable OBS WebSocket Sync")

    A_TrayMenu.Add("Enable Zoom Monitoring", ToggleZoom.Bind(cfg, state))
    if (cfg.EnableZoom)
        A_TrayMenu.Check("Enable Zoom Monitoring")

    A_TrayMenu.Add()

    ; 3. HUD OVERLAY & APPEARANCE
    A_TrayMenu.Add("Show Mute Indicator", ToggleIndicator.Bind(cfg, state))
    if (cfg.ShowIndicator)
        A_TrayMenu.Check("Show Mute Indicator")

    A_TrayMenu.Add("Show Extra HUDs", ToggleExtraHuds.Bind(cfg, state))
    if (cfg.ShowExtraHuds)
        A_TrayMenu.Check("Show Extra HUDs")

    A_TrayMenu.Add("Show Secondary Mic Pill (Mic-Only)", ToggleSecondaryMicLive.Bind(cfg, state))
    if (cfg.ShowSecondaryMicHud)
        A_TrayMenu.Check("Show Secondary Mic Pill (Mic-Only)")

    AppearanceMenu := Menu()
    AppearanceMenu.Add("Show Text Label", ToggleText.Bind(cfg, state))
    if (cfg.ShowText)
        AppearanceMenu.Check("Show Text Label")

    AppearanceMenu.Add("Use Monochromatic Icon", ToggleMono.Bind(cfg, state))
    if (cfg.MonoIcon)
        AppearanceMenu.Check("Use Monochromatic Icon")

    AppearanceMenu.Add("Use Sleek Corners", ToggleCorners.Bind(cfg, state))
    if (cfg.SleekCorners)
        AppearanceMenu.Check("Use Sleek Corners")

    AppearanceMenu.Add("Aggressive Mute Pulse", TogglePulse.Bind(cfg, state))
    if (cfg.AggressivePulse)
        AppearanceMenu.Check("Aggressive Mute Pulse")

    AppearanceMenu.Add("Mute Audio Cue (Beep)", ToggleAudioCue.Bind(cfg, state))
    if (cfg.EnableAudioCue)
        AppearanceMenu.Check("Mute Audio Cue (Beep)")

    AppearanceMenu.Add("Mute Status Toast", ToggleMuteToast.Bind(cfg, state))
    if (cfg.EnableMuteToast)
        AppearanceMenu.Check("Mute Status Toast")

    AppearanceMenu.Add("Voice-While-Muted Alert", (*) => (ToggleBoolSetting(cfg, state, "EnableVoiceWhileMutedAlert"), UpdateMutedVoiceMonitorTimer(cfg, state)))
    if (cfg.EnableVoiceWhileMutedAlert)
        AppearanceMenu.Check("Voice-While-Muted Alert")

    AppearanceMenu.Add("Show Live Voice Activity Bar", ToggleVoiceMeter.Bind(cfg, state))
    if (cfg.ShowVoiceMeter)
        AppearanceMenu.Check("Show Live Voice Activity Bar")

    AppearanceMenu.Add("Show Recording Elapsed Timer", ToggleRecTimer.Bind(cfg, state))
    if (cfg.ShowRecTimer)
        AppearanceMenu.Check("Show Recording Elapsed Timer")

    AppearanceMenu.Add("Show Stream && VCam HUD", ToggleStreamHud.Bind(cfg, state))
    if (cfg.ShowStreamHud)
        AppearanceMenu.Check("Show Stream && VCam HUD")

    AppearanceMenu.Add("Show Recording && Chat HUD (Row 2)", (*) => ToggleHudOptionAndRebuild(cfg, state, "ShowRow2RecChatHud", "Settings", RefreshHudAppearance, BuildTrayMenu, NotifyHelpRefresh))
    if (cfg.ShowRow2RecChatHud)
        AppearanceMenu.Check("Show Recording && Chat HUD (Row 2)")

    AppearanceMenu.Add("Show Studio && Scene HUD (Row 3)", (*) => ToggleHudOptionAndRebuild(cfg, state, "ShowRow3StudioSceneHud", "Settings", RefreshHudAppearance, BuildTrayMenu, NotifyHelpRefresh))
    if (cfg.ShowRow3StudioSceneHud)
        AppearanceMenu.Check("Show Studio && Scene HUD (Row 3)")

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

    AppearanceMenu.Add("Hide HUD from Screen Share / Capture", (*) => ToggleHudOptionAndRebuild(cfg, state, "ExcludeFromCapture", "Settings", RefreshHudAppearance, BuildTrayMenu, NotifyHelpRefresh))
    if (cfg.ExcludeFromCapture)
        AppearanceMenu.Check("Hide HUD from Screen Share / Capture")

    AppearanceMenu.Add("Hide Secondary Pill from Capture", (*) => ToggleHudOptionAndRebuild(cfg, state, "ExcludeSecondaryFromCapture", "Settings", RefreshHudAppearance, BuildTrayMenu, NotifyHelpRefresh))
    if (cfg.ExcludeSecondaryFromCapture)
        AppearanceMenu.Check("Hide Secondary Pill from Capture")

    AppearanceMenu.Add()

    BuildSharedAppearanceSubmenus(
        AppearanceMenu, cfg, state,
        SetPrimaryOpacityLive.Bind(cfg, state),
        ApplyScaleLive.Bind(cfg, state),
        ApplyThemeLive.Bind(cfg, state)
    )

    AppearanceMenu.Add()
    AppearanceMenu.Add("Reset Indicator Position", ApplyResetPositionLive.Bind(cfg, state))
    AppearanceMenu.Add("Reset Secondary Pill Position", ApplyResetSecondaryPositionLive.Bind(cfg, state))
    AppearanceMenu.Add("Restore Default Appearance", ApplyResetAppearanceLive.Bind(cfg, state))

    A_TrayMenu.Add("Indicator Appearance", AppearanceMenu)

    DirectorMenu := Menu()
    DirectorMenu.Add("Toggle Standby / `"BRB`" Curtain", (*) => ExecuteHostToggleStandby(cfg, state))
    if (IsObject(state) && state.HasOwnProp("isStandby") && state.isStandby)
        DirectorMenu.Check("Toggle Standby / `"BRB`" Curtain")
    SceneSwitchMenu := Menu()
    if (IsObject(state) && state.HasOwnProp("sceneList") && IsObject(state.sceneList) && state.sceneList.Length > 0) {
        for scName in state.sceneList {
            SceneSwitchMenu.Add(scName, ((s, *) => ExecuteHostSwitchScene(cfg, state, s)).Bind(scName))
            if (state.HasOwnProp("currentSceneName") && state.currentSceneName == scName)
                SceneSwitchMenu.Check(scName)
        }
    } else {
        SceneSwitchMenu.Add("Connect OBS for scenes", (*) => 0)
        SceneSwitchMenu.Disable("Connect OBS for scenes")
    }
    DirectorMenu.Add("Switch OBS Scene", SceneSwitchMenu)
    DirectorMenu.Add("Pause / Resume Recording", (*) => ExecuteHostPauseRecord(cfg, state))
    DirectorMenu.Add("Split Recording Chapter", (*) => ExecuteHostSplitRecord(cfg, state))
    DirectorMenu.Add()
    DirectorMenu.Add("Presenter Countdown Timer", BuildSharedPresenterTimerSubmenu(state, (sec, *) => StartHostPresenterTimer(cfg, state, sec), (*) => PauseHostPresenterTimer(cfg, state), (sec, *) => ResetHostPresenterTimer(cfg, state, sec)))
    DirectorMenu.Add("Send Stage Nudge...", (*) => PromptSendStageNudgeUI((msg) => BroadcastHostStageNudge(cfg, state, msg, "Primary Host")))
    DirectorMenu.Add("View && Export Session Timeline...", (*) => SessionTimeline.ShowTimelineWindow(cfg, state))
    DirectorMenu.Add("Remote Companion Setup && QR Info...", (*) => ShowRemoteCompanionInfo(cfg, state))
    A_TrayMenu.Add("OBS Director && Standby", DirectorMenu)

    A_TrayMenu.Add()

    ; 4. SETTINGS & CONFIGURATION SUBMENU
    SettingsMenu := Menu()
    SettingsMenu.Add("Control Center (All Settings)...", ShowControlCenterWindow.Bind(cfg, state))
    SettingsMenu.Add()
    RoutingMenu := Menu()
    RoutingModes := [{ label: "1: Pro OBS Setup (VB-Cable)", mode: 1 }, { label: "2: Standard Direct Mic (Zoom-Only)", mode: 2 }, { label: "3: Dual App Sync (OBS + Zoom)", mode: 3 }
    ]
    for rm in RoutingModes {
        RoutingMenu.Add(rm.label, SetRoutingMode.Bind(cfg, rm.mode))
        if (cfg.AudioRoutingMode == rm.mode)
            RoutingMenu.Check(rm.label)
    }
    SettingsMenu.Add("Audio Routing Mode", RoutingMenu)
    SettingsMenu.Add("Guided Setup Wizard (4-Step Check)...", (*) => ShowGuidedSetupWizard(cfg, state))
    SettingsMenu.Add("Run Audio Setup Wizard...", (*) => PromptForSetup(cfg, false))

    ConfMenu := Menu()
    for cApp in GetConferencingAppNames() {
        ConfMenu.Add(cApp, SetConferencingApp.Bind(cfg, state, cApp))
        if (NormalizeConferencingApp(cfg.ConferencingApp) = cApp)
            ConfMenu.Check(cApp)
    }
    SettingsMenu.Add("Conferencing Platform", ConfMenu)

    ProfileMenu := Menu()
    for pName in cfg.GetProfileNames() {
        ProfileMenu.Add(pName, SwitchProfileAction.Bind(cfg, state, pName))
        if (StrLower(cfg.ActiveProfile) = StrLower(pName))
            ProfileMenu.Check(pName)
    }
    ProfileMenu.Add()
    ProfileMenu.Add("Auto-Switch by Active App", ToggleAutoProfileSwitch.Bind(cfg, state))
    if (cfg.HasOwnProp("EnableAutoProfileSwitch") && cfg.EnableAutoProfileSwitch)
        ProfileMenu.Check("Auto-Switch by Active App")
    ProfileMenu.Add("Save Current as New Profile...", (*) => ShowProfileManagerUI(cfg, state))
    ProfileMenu.Add("Manage Profiles && Auto Rules...", (*) => ShowProfileManagerUI(cfg, state))
    SettingsMenu.Add("Configuration Profiles", ProfileMenu)

    SettingsMenu.Add()
    SettingsMenu.Add("Change OBS Settings", ChangeObsSettingsUI.Bind(cfg))
    SettingsMenu.Add("Change Zoom Shortcuts", ChangeZoomShortcutsUI.Bind(cfg))
    SettingsMenu.Add()
    RemoteNetMenu := Menu()
    RemoteNetMenu.Add("Same Router (LAN)", SetRemoteNetworkMode.Bind(cfg, state, "LAN"))
    RemoteNetMenu.Add("Different Networks (Internet)", SetRemoteNetworkMode.Bind(cfg, state, "Internet"))
    if (cfg.RemoteNetworkMode = "Internet")
        RemoteNetMenu.Check("Different Networks (Internet)")
    else
        RemoteNetMenu.Check("Same Router (LAN)")
    SettingsMenu.Add("Remote Network Mode", RemoteNetMenu)
    SettingsMenu.Add("Remote Companion Info...", (*) => ShowRemoteCompanionInfo(cfg, state))
    SettingsMenu.Add("Close Remote Companion...", PromptCloseRemoteCompanion.Bind(cfg, state))
    SettingsMenu.Add()
    SettingsMenu.Add("Change Pointer Mute Button", ChangeHwMuteHotkeyUI.Bind(cfg))
    SettingsMenu.Add("Change Pointer OBS Transition Button...", ChangeHwTransitionHotkeyUI.Bind(cfg, state))
    SettingsMenu.Add("Enable Cough / Push-to-Mute (Hold)", TogglePushToMute.Bind(cfg, state))
    if (cfg.EnablePushToMute)
        SettingsMenu.Check("Enable Cough / Push-to-Mute (Hold)")
    SettingsMenu.Add("Enable Push-to-Talk (Hold to Unmute)", TogglePushToTalk.Bind(cfg, state))
    if (cfg.HasOwnProp("EnablePushToTalk") && cfg.EnablePushToTalk)
        SettingsMenu.Check("Enable Push-to-Talk (Hold to Unmute)")
    SettingsMenu.Add("Configure Pointer Intercepts", ConfigurePointerKeysUI.Bind(cfg))
    SettingsMenu.Add("Launch Clicker Tester", ShowPointerTester)
    SettingsMenu.Add()
    SettingsMenu.Add("Change App Shortcuts", ChangeAppHotkeysUI.Bind(cfg))
    SettingsMenu.Add()
    SettingsMenu.Add("Start with Windows", ToggleStartWithWindows.Bind(cfg, state))
    if (cfg.StartWithWindows)
        SettingsMenu.Check("Start with Windows")
    SettingsMenu.Add("Check for Updates...", (*) => CheckForUpdates(UIConstants.APP_VERSION, "", false, "PresenterSync.exe", cfg))

    A_TrayMenu.Add("Control Center...", ShowControlCenterWindow.Bind(cfg, state))
    A_TrayMenu.Add("Settings", SettingsMenu)

    ; 5. HELP, SAFETY & EXIT
    A_TrayMenu.Add("Guided Setup Wizard...", (*) => ShowGuidedSetupWizard(cfg, state))
    A_TrayMenu.Add("Help && Shortcuts", ShowHelpWindow.Bind(cfg, state))
    A_TrayMenu.Add("View Error && Diagnostic Log...", (*) => DiagnosticLogger.ShowLogViewerWindow(cfg, state))
    A_TrayMenu.Add("Export Sanitized Diagnostics...", (*) => ExportSanitizedDiagnostics(cfg, state, "", true))
    A_TrayMenu.Add("About PresenterSync", ShowAboutWindow.Bind(cfg, state))
    A_TrayMenu.Add("Check for Updates...", (*) => CheckForUpdates(UIConstants.APP_VERSION, "", false, "PresenterSync.exe", cfg))
    A_TrayMenu.Add()
    A_TrayMenu.Add("Suspend All Hotkeys", ToggleSuspend)
    if (Theme.SuspendLockCount > 0 ? Theme.WasSuspendedBeforeDialogs : A_IsSuspended)
        A_TrayMenu.Check("Suspend All Hotkeys")
    A_TrayMenu.Add("Remote Companion Setup && QR Info...", (*) => ShowRemoteCompanionInfo(cfg, state))
    A_TrayMenu.Add("Cut Off All Remote Connections (Standalone Mode)", ToggleRemoteConnectionsCutoff.Bind(cfg, state))
    if (!cfg.EnableRemoteConnections)
        A_TrayMenu.Check("Cut Off All Remote Connections (Standalone Mode)")
    A_TrayMenu.Add("Close Remote Companion...", PromptCloseRemoteCompanion.Bind(cfg, state))
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
        SetTrayCheck("Cut Off All Remote Connections (Standalone Mode)", true)
        ToolTip("Standalone Mode: All Remote Connections Cut Off")
    } else {
        if (IsObject(state)) {
            StartHostCompanionBridge(cfg, state, cfg.BridgePort)
            UpdateHostInternetRelay(cfg, state)
        }
        SetTrayCheck("Cut Off All Remote Connections (Standalone Mode)", false)
        ToolTip("Remote Companion Connections: Enabled")
    }
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
        SetTrayCheck("Enable Pointer Mute Only", false)
        SetTrayCheck("Enable Full Pointer Controls (PPT + Mute)", true)
        ToolTip "Pointer Mode: Full PPT + Mute"
    } else {
        SetTrayCheck("Enable Full Pointer Controls (PPT + Mute)", false)
        ToolTip "Pointer Mode: OFF"
    }

    cfg.WriteBool("Settings", "EnablePPT", cfg.EnablePPT)
    NotifyHelpRefresh(state)
    SetTimer RemoveToolTip, -UIConstants.TOOLTIP_DURATION_MS
}

ToggleMicOnly(cfg, state := "", *) {
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
    NotifyHelpRefresh(state)
    SetTimer RemoveToolTip, -UIConstants.TOOLTIP_DURATION_MS
}

TogglePointerTransition(cfg, state := "", *) {
    ToolTip()
    cfg.EnablePointerTransition := !cfg.EnablePointerTransition
    cfg.WriteBool("Settings", "EnablePointerTransition", cfg.EnablePointerTransition)
    SetTrayCheck("Enable Pointer OBS Scene Transition", cfg.EnablePointerTransition)
    if (IsObject(state) && state.HasOwnProp("rebindHotkeysFn") && state.rebindHotkeysFn)
        try state.rebindHotkeysFn.Call()
    ToolTip("Pointer OBS Scene Transition: " (cfg.EnablePointerTransition ? "ON" : "OFF"))
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

    NotifyHelpRefresh(state)
    SetTimer RemoveToolTip, -UIConstants.TOOLTIP_DURATION_MS
}

ToggleWS(cfg, state, *) {
    ToolTip()

    cfg.EnableWS := !cfg.EnableWS

    if (cfg.EnableWS) {
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
        SetTrayCheck("Enable Zoom Monitoring", true)
        ToolTip "Zoom Monitoring: ON"
    } else {
        cfg.WriteBool("Settings", "EnableZoom", false)
        SetTrayCheck("Enable Zoom Monitoring", false)
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
    NotifyHelpRefresh(state)
    SetTimer RemoveToolTip, -UIConstants.TOOLTIP_DURATION_MS
}

ToggleIndicator(cfg, state, *) {
    cfg.ShowIndicator := !cfg.ShowIndicator
    cfg.WriteBool("Settings", "ShowIndicator", cfg.ShowIndicator)

    SetTrayCheck("Show Mute Indicator", cfg.ShowIndicator)
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

    SetTrayCheck("Show Extra HUDs", cfg.ShowExtraHuds)
    RefreshHudAppearance(cfg, state)
    NotifyHelpRefresh(state)
    ToolTip(cfg.ShowExtraHuds ? "Extra HUDs: ON" : "Extra HUDs: OFF")
    SetTimer RemoveToolTip, -UIConstants.TOOLTIP_DURATION_MS
}

ToggleSecondaryMicLive(cfg, state, *) {
    ToolTip()
    ToggleSecondaryMicHud(cfg, state)
    SetTrayCheck("Show Secondary Mic Pill (Mic-Only)", cfg.ShowSecondaryMicHud)
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

BindSystemHotkeys(cfg, state) {
    global BoundSystemHotkeys
    HotIf()
    for oldHk in BoundSystemHotkeys {
        try Hotkey(oldHk, "Off")
    }
    BoundSystemHotkeys := []
    if (cfg.PptHotkey != "" && cfg.PptHotkey != "None") {
        try Hotkey(cfg.PptHotkey, (*) => CyclePointerMode(cfg, state), "On")
        BoundSystemHotkeys.Push(cfg.PptHotkey)
    }
    if (cfg.WsHotkey != "" && cfg.WsHotkey != "None") {
        try Hotkey(cfg.WsHotkey, (*) => ToggleWS(cfg, state), "On")
        BoundSystemHotkeys.Push(cfg.WsHotkey)
    }
    if (cfg.ZoomHotkey != "" && cfg.ZoomHotkey != "None") {
        try Hotkey(cfg.ZoomHotkey, (*) => ToggleZoom(cfg, state), "On")
        BoundSystemHotkeys.Push(cfg.ZoomHotkey)
    }
    if (cfg.IndHotkey != "" && cfg.IndHotkey != "None") {
        try Hotkey(cfg.IndHotkey, (*) => ToggleIndicator(cfg, state), "On")
        BoundSystemHotkeys.Push(cfg.IndHotkey)
    }
    if (cfg.SuspendHotkey != "" && cfg.SuspendHotkey != "None") {
        try Hotkey(cfg.SuspendHotkey, (*) => ToggleSuspend(), "S")
        try Hotkey(cfg.SuspendHotkey, "On")
        BoundSystemHotkeys.Push(cfg.SuspendHotkey)
    }
    if (cfg.ExitHotkey != "" && cfg.ExitHotkey != "None") {
        try Hotkey(cfg.ExitHotkey, (*) => ExitTrayApp(), "On")
        BoundSystemHotkeys.Push(cfg.ExitHotkey)
    }
    if (cfg.RemoteInfoHotkey != "" && cfg.RemoteInfoHotkey != "None") {
        try Hotkey(cfg.RemoteInfoHotkey, (*) => ShowRemoteCompanionInfo(cfg, state), "On")
        BoundSystemHotkeys.Push(cfg.RemoteInfoHotkey)
    }
    ; Secret Easter Egg hotkey (intentionally undocumented in Tray / Control Center)
    try {
        Hotkey("!^+s", (*) => HudSnake.Toggle(cfg, state), "On")
        BoundSystemHotkeys.Push("!^+s")
    }
}
BindSystemHotkeys(AppConfig, AppState)

RemoveToolTip() {
    ToolTip
}

; --- POWERPOINT CONTROLS (PRE-COMPUTED DYNAMIC INTERCEPTION) ---
IsPptInterceptActive(cfg, ThisHotkey := "") {
    return cfg.EnablePPT && !HudSnake.IsActive && (Theme.OpenWindows.Count == 0 || !Theme.OpenWindows.Has(WinExist("A")))
}

IsPptKeyNotMute(cfg, pptKey) {
    return IsPptKeyAllowed(cfg, pptKey)
}

PptCondFn := IsPptInterceptActive.Bind(AppConfig)

BindPptInterceptHotkeys(cfg, state := "") {
    global BoundPptHotkeys, PptCondFn
    HotIf PptCondFn
    for oldHk in BoundPptHotkeys {
        try Hotkey(oldHk, "Off")
    }
    BoundPptHotkeys := []

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
    HotIf
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
    }
    else if WinExist("PowerPoint Presenter View ahk_exe POWERPNT.EXE") {
        try ControlSend Key, , "PowerPoint Presenter View ahk_exe POWERPNT.EXE"
    }
    else if WinExist("ahk_class PPTFrameClass ahk_exe POWERPNT.EXE") {
        try ControlSend Key, , "ahk_class PPTFrameClass ahk_exe POWERPNT.EXE"
    }
    else if WinExist("ahk_exe POWERPNT.EXE") {
        try ControlSend Key, , "ahk_exe POWERPNT.EXE"
    }
    else {
        dir := (Key = "{Up}" || Key = "{Left}" || Key = "{PgUp}") ? "prev" : "next"
        fb := TryDispatchFallbackSlideKey(dir)
        if (!fb.handled)
            SoundPlay "*16"
    }
    DiagnosticLogger.CheckLatency("Input", "SendToPPT", t0, 120, Key)
}

; --- DYNAMIC HARDWARE MUTE & SCENE TRANSITION TRIGGERS ---
CheckPointerEnable(cfg, ThisHotkey) {
    return !HudSnake.IsActive && (cfg.EnablePPT || cfg.EnableMicOnly) && (Theme.OpenWindows.Count == 0 || !Theme.OpenWindows.Has(WinExist("A")))
}

PointerCondFn := CheckPointerEnable.Bind(AppConfig)

BindHwMuteHotkey(cfg, state) {
    global BoundHwMuteHotkey, PointerCondFn
    HotIf PointerCondFn
    if (BoundHwMuteHotkey != "") {
        try Hotkey(BoundHwMuteHotkey, "Off")
        BoundHwMuteHotkey := ""
    }
    if (cfg.HwMuteHotkey != "" && cfg.HwMuteHotkey != "None") {
        try Hotkey(cfg.HwMuteHotkey, (*) => TriggerMute(cfg, state), "On")
        BoundHwMuteHotkey := cfg.HwMuteHotkey
    }
    HotIf
}
BindHwMuteHotkey(AppConfig, AppState)

CheckTransitionEnable(cfg, ThisHotkey := "") {
    return !HudSnake.IsActive && cfg.EnablePointerTransition && (Theme.OpenWindows.Count == 0 || !Theme.OpenWindows.Has(WinExist("A")))
}

TransitionCondFn := CheckTransitionEnable.Bind(AppConfig)

BindHwTransitionHotkey(cfg, state) {
    global BoundHwTransitionHotkey, TransitionCondFn
    HotIf TransitionCondFn
    if (BoundHwTransitionHotkey != "") {
        try Hotkey(BoundHwTransitionHotkey, "Off")
        BoundHwTransitionHotkey := ""
    }
    if (cfg.HwTransitionHotkey != "" && cfg.HwTransitionHotkey != "None") {
        try Hotkey(cfg.HwTransitionHotkey, (*) => TriggerObsSceneTransition(cfg, state), "On")
        BoundHwTransitionHotkey := cfg.HwTransitionHotkey
    }
    HotIf
}
BindHwTransitionHotkey(AppConfig, AppState)

; --- MUTE & TRANSITION PASSTHROUGH CONTROL ---
RegisterPassthroughHooks(cfg, state) {
    global BoundPassthroughHooks
    HotIf
    for oldHook in BoundPassthroughHooks {
        try Hotkey(oldHook, "Off")
    }
    BoundPassthroughHooks := []

    if ((cfg.AudioRoutingMode == 1 || cfg.AudioRoutingMode == 3) && cfg.ObsMuteHotkey != "None" && cfg.ObsMuteHotkey != "") {
        hk := FormatPassthroughHook(cfg.ObsMuteHotkey)
        try Hotkey(hk, LaptopKeyboardMute.Bind(cfg, state), "On")
        BoundPassthroughHooks.Push(hk)
    }
    if (cfg.ObsTransitionHotkey != "None" && cfg.ObsTransitionHotkey != "") {
        hk := FormatPassthroughHook(cfg.ObsTransitionHotkey)
        try Hotkey(hk, LaptopObsTransitionPassthrough.Bind(cfg, state), "On")
        BoundPassthroughHooks.Push(hk)
    }
    if ((cfg.AudioRoutingMode == 2 || cfg.AudioRoutingMode == 3)) {
        confMuteHk := GetActiveConferencingMuteHotkey(cfg)
        if (confMuteHk != "None" && confMuteHk != "") {
            hk := FormatPassthroughHook(confMuteHk)
            try Hotkey(hk, LaptopKeyboardMute.Bind(cfg, state), "On")
            BoundPassthroughHooks.Push(hk)
        }
    }

    obsRecHook := (cfg.ObsRecHotkey != "" && cfg.ObsRecHotkey != "None") ? FormatPassthroughHook(cfg.ObsRecHotkey) : ""
    zoomRecHook := (cfg.ZoomRecHotkey != "" && cfg.ZoomRecHotkey != "None") ? FormatPassthroughHook(cfg.ZoomRecHotkey) : ""
    if (obsRecHook != "" && obsRecHook = zoomRecHook) {
        try Hotkey(obsRecHook, LaptopCombinedRecToggle.Bind(cfg, state), "On")
        BoundPassthroughHooks.Push(obsRecHook)
    } else {
        if (obsRecHook != "") {
            try Hotkey(obsRecHook, LaptopObsRecToggle.Bind(cfg, state), "On")
            BoundPassthroughHooks.Push(obsRecHook)
        }
        if (zoomRecHook != "") {
            try Hotkey(zoomRecHook, LaptopZoomRecToggle.Bind(cfg, state), "On")
            BoundPassthroughHooks.Push(zoomRecHook)
        }
    }

    obsPauseHook := (cfg.ObsPauseHotkey != "" && cfg.ObsPauseHotkey != "None") ? FormatPassthroughHook(cfg.ObsPauseHotkey) : ""
    zoomPauseHook := (cfg.ZoomPauseHotkey != "" && cfg.ZoomPauseHotkey != "None") ? FormatPassthroughHook(cfg.ZoomPauseHotkey) : ""
    if (obsPauseHook != "" && obsPauseHook = zoomPauseHook) {
        try Hotkey(obsPauseHook, LaptopCombinedPauseToggle.Bind(cfg, state), "On")
        BoundPassthroughHooks.Push(obsPauseHook)
    } else {
        if (obsPauseHook != "") {
            try Hotkey(obsPauseHook, LaptopObsPauseToggle.Bind(cfg, state), "On")
            BoundPassthroughHooks.Push(obsPauseHook)
        }
        if (zoomPauseHook != "") {
            try Hotkey(zoomPauseHook, LaptopZoomPauseToggle.Bind(cfg, state), "On")
            BoundPassthroughHooks.Push(zoomPauseHook)
        }
    }
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