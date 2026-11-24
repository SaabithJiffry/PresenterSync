; ==============================================================================
; Test Suite: test_v901_runtime_audit.ahk
; Description: Automated v9.0.1 real-object runtime & render audit covering:
;   - HudArcadeBase.ResolveDarkMode / ResolveMicMuted / PauseHostPolling / RestoreHostPolling
;   - ComputeSecondaryMicLayout with zeroed baseWidth (no BASE_WIDTH_ONLY regression)
;   - Real Config + OverlayState (Dark & Light) AND strict RemoteConfig/RemoteState shape
;   - Non-headless Start + _RenderFrame + TogglePause + mode toggles + Stop + GDI delta
;     across ALL 10 Windows arcade games (zero PropertyError / UnsetError)
;   - InitHUD -> HandleHudPillClick -> cleanup + ControlCenter / About / Help / Capture dialogs
;   - Static sweep guaranteeing removed invalid properties/constants never return
; ==============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
SetTimer(() => ExitApp(124), -45000)

global g_IsTestMode := true
passed := 0
failed := 0
logFile := A_ScriptDir "\v901_runtime_audit_results.log"
try FileDelete(logFile)

AuditFailFast(exc, mode) {
    global failed, logFile
    failed += 1
    msg := Format("[FAIL] Unhandled exception ({}) in {} ({}:{}): {}", mode, exc.What, exc.File, exc.Line, exc.Message)
    try FileAppend(msg "`n", logFile, "UTF-8")
    try FileAppend(msg "`n", "*")
    ExitApp(1)
}
OnError(AuditFailFast)

#Include "%A_LineFile%\..\..\Lib\WebSocket.ahk"
#Include "%A_LineFile%\..\..\Lib\UIA.ahk"
#Include "%A_LineFile%\..\..\Lib\Crypto.ahk"
#Include "%A_LineFile%\..\..\Lib\RemoteBridgeClient.ahk"
#Include "%A_LineFile%\..\..\Lib\Gdip.ahk"
#Include "%A_LineFile%\..\..\Lib\OBS_Network.ahk"
#Include "%A_LineFile%\..\..\Lib\GUI_Config.ahk"
#Include "%A_LineFile%\..\..\Lib\HudSnakeGame.ahk"
#Include "%A_LineFile%\..\..\Lib\HudArcadeBase.ahk"
#Include "%A_LineFile%\..\..\Lib\ArcadeVault.ahk"
#Include "%A_LineFile%\..\..\Lib\Arcade\GameAsteroids.ahk"
#Include "%A_LineFile%\..\..\Lib\Arcade\GamePaddlePack.ahk"
#Include "%A_LineFile%\..\..\Lib\Arcade\GameClickerFlappy.ahk"
#Include "%A_LineFile%\..\..\Lib\Arcade\GameGridMazePack.ahk"
#Include "%A_LineFile%\..\..\Lib\Arcade\GameMissileDefense.ahk"
#Include "%A_LineFile%\..\..\Lib\Arcade\GameBlockDrop.ahk"
#Include "%A_LineFile%\..\..\Lib\Arcade\GameSpacePinball.ahk"

AssertTrue(cond, label, detail := "") {
    global passed, failed, logFile
    if (cond) {
        passed++
    } else {
        failed++
        msg := "[FAIL] " label (detail != "" ? " [" detail "]" : "") "`n"
        try FileAppend(msg, logFile, "UTF-8")
        try FileAppend(msg, "*")
    }
}

GetGdiCount() {
    return DllCall("GetGuiResources", "Ptr", DllCall("GetCurrentProcess", "Ptr"), "UInt", 0, "UInt")
}

Gdip.Startup()

tmpIni := A_Temp "\PresenterSync_v901_audit_" A_TickCount ".ini"
for _, p in [tmpIni, tmpIni ".bak"] {
    if FileExist(p)
        try FileDelete(p)
}

OnExit((*) => (
    HudSnake.Stop(),
    GameAsteroids.Stop(),
    GameBrickBreaker.Stop(),
    GameCyberPong.Stop(),
    GameClickerFlappy.Stop(),
    GameLightCycles.Stop(),
    GamePacGrid.Stop(),
    GameMissileDefense.Stop(),
    GameBlockDrop.Stop(),
    GameSpacePinball.Stop(),
    Theme.Shutdown(),
    UIA.Shutdown(),
    Gdip.Shutdown(),
    (FileExist(tmpIni) ? FileDelete(tmpIni) : 0),
    (FileExist(tmpIni ".bak") ? FileDelete(tmpIni ".bak") : 0)
))

cfg := Config(tmpIni)
cfg.EnableWS := false
cfg.EnableZoom := false
cfg.ShowSecondaryMicHud := false
st := OverlayState(cfg)
st.suppressNudgeBanners := true

; Strict Remote-shape mirror matching PresenterSync_Remote.ahk properties
; (deliberately omits IsDarkMode, HudTheme, obsMuted, RecGui, obsTimerFn)
remoteCfg := {
    ThemeMode: "Dark",
    OpacityLevel: 220,
    ShowIndicator: true,
    ShowText: false,
    ExcludeFromCapture: false,
    EnableHudClickActions: true,
    EnableMagneticSnap: true,
    HudAutoDodge: false,
    EnableVoiceWhileMutedAlert: false,
    HeartbeatSeconds: 30,
    IsMuted: true,
    HwMuteHotkey: "PgDn",
    HwTransitionHotkey: "F8"
}
remoteSt := {
    isMuted: true,
    obsConnected: false,
    obsWs: "",
    reconnectTimerFn: (*) => 0,
    heartbeatTimerFn: (*) => 0,
    voiceMeterTimerFn: (*) => 0,
    autoDodgeTimerFn: (*) => 0
}

; 1. ResolveDarkMode & ResolveMicMuted helpers
cfg.ThemeMode := "Dark"
Theme.SetMode("Dark")
AssertTrue(HudArcadeBase.ResolveDarkMode(cfg) == true, "ResolveDarkMode handles real Config Dark mode")
cfg.ThemeMode := "Light"
Theme.SetMode("Light")
AssertTrue(HudArcadeBase.ResolveDarkMode(cfg) == false, "ResolveDarkMode handles real Config Light mode")
cfg.ThemeMode := "Dark"
Theme.SetMode("Dark")
st.isMuted := true
AssertTrue(HudArcadeBase.ResolveMicMuted(st) == 1, "ResolveMicMuted reads OverlayState.isMuted == true -> 1")
st.isMuted := false
AssertTrue(HudArcadeBase.ResolveMicMuted(st) == 0, "ResolveMicMuted reads OverlayState.isMuted == false -> 0")
AssertTrue(HudArcadeBase.ResolveMicMuted(remoteSt) == 1, "ResolveMicMuted reads Remote-shape isMuted == true -> 1")

; 2. PauseHostPolling / RestoreHostPolling (no OBS_POLL_INTERVAL_MS / PropertyError)
cfg.EnableWS := true
st.obsConnected := false
st.streamState := 1
st.recState := 1
savedPrim := HudArcadeBase.PauseHostPolling(st)
AssertTrue(savedPrim.Has("obsTimerFn") && savedPrim.Has("voiceMeterTimerFn") && savedPrim.Has("mutedVoiceTimerFn"),
    "PauseHostPolling captures Primary timers cleanly")
HudArcadeBase.RestoreHostPolling(cfg, st, savedPrim)
for _, fnProp in ["obsTimerFn", "streamTimerFn", "recTimerFn", "zoomTimerFn", "autoDodgeTimerFn", "voiceMeterTimerFn", "mutedVoiceTimerFn", "relayTimerFn"] {
    if (st.HasOwnProp(fnProp) && IsObject(st.%fnProp%))
        try SetTimer(st.%fnProp%, 0)
}
cfg.EnableWS := false
st.streamState := 0
st.recState := 0

savedRem := HudArcadeBase.PauseHostPolling(remoteSt)
AssertTrue(savedRem.Has("reconnectTimerFn") && savedRem.Has("heartbeatTimerFn"),
    "PauseHostPolling captures Remote reconnect & heartbeat timers")
HudArcadeBase.RestoreHostPolling(remoteCfg, remoteSt, savedRem)
try SetTimer(remoteSt.reconnectTimerFn, 0)
try SetTimer(remoteSt.heartbeatTimerFn, 0)
AssertTrue(true, "RestoreHostPolling completes cleanly for both Primary and Remote shapes")

; 3. ComputeSecondaryMicLayout zero baseWidth fallback (fixed BASE_WIDTH_ONLY)
cfg.ShowText := false
layIcon := ComputeSecondaryMicLayout(cfg, { baseWidth: 0, baseHeight: 0 })
AssertTrue(layIcon.w == UIConstants.BASE_WIDTH_ICON && layIcon.h == UIConstants.BASE_HEIGHT,
    "ComputeSecondaryMicLayout falls back to BASE_WIDTH_ICON when ShowText=false")
cfg.ShowText := true
layText := ComputeSecondaryMicLayout(cfg, { baseWidth: 0, baseHeight: 0 })
AssertTrue(layText.w == UIConstants.BASE_WIDTH_TEXT && layText.h == UIConstants.BASE_HEIGHT,
    "ComputeSecondaryMicLayout falls back to BASE_WIDTH_TEXT when ShowText=true")
cfg.ShowText := false

; 4. Real non-headless Start + _RenderFrame + mode toggles + Stop across ALL 10 Windows games
RunGameCycle(name, clsObj, testCfg, testSt, toggleFn := "", isDarkLightCheck := false) {
    gdiBefore := GetGdiCount()
    started := clsObj.Start(testCfg, testSt, false)
    AssertTrue(started && clsObj.IsActive, name " starts non-headless cleanly")
    clsObj._RenderFrame()
    if (toggleFn != "") {
        toggleFn.Call()
        clsObj._RenderFrame()
    }
    clsObj.TogglePause()
    clsObj._RenderFrame()
    if (isDarkLightCheck) {
        oldMode := testCfg.ThemeMode
        testCfg.ThemeMode := "Light"
        Theme.SetMode("Light")
        clsObj._RenderFrame()
        testCfg.ThemeMode := oldMode
        Theme.SetMode(oldMode)
    }
    clsObj.Stop()
    AssertTrue(!clsObj.IsActive, name " stops cleanly")
    Sleep(10)
    gdiAfter := GetGdiCount()
    AssertTrue((gdiAfter - gdiBefore) <= 12, name " non-headless GDI delta bounded", Format("before={} after={}", gdiBefore, gdiAfter))
}

RunGameCycle("HudSnake", HudSnake, cfg, st, (*) => HudSnake.ToggleEdgeMode())
RunGameCycle("GameAsteroids", GameAsteroids, cfg, st, (*) => GameAsteroids.ToggleBlasterMode(), true)
; Confirm Blaster returns to asteroids on second toggle when restarted
GameAsteroids.Start(cfg, st, false)
if (GameAsteroids.GetStateSnapshot().blasterMode = "alien")
    GameAsteroids.ToggleBlasterMode()
AssertTrue(GameAsteroids.GetStateSnapshot().blasterMode = "asteroids", "GameAsteroids resets back to asteroids on toggle")
GameAsteroids._RenderFrame()
GameAsteroids.ToggleBlasterMode()
AssertTrue(GameAsteroids.GetStateSnapshot().blasterMode = "alien", "GameAsteroids switches to alien on ToggleBlasterMode")
GameAsteroids._RenderFrame()
GameAsteroids.Stop()

RunGameCycle("GameBrickBreaker", GameBrickBreaker, cfg, st)
RunGameCycle("GameCyberPong", GameCyberPong, cfg, st, (*) => GameCyberPong.ToggleTwoPlayerMode())
RunGameCycle("GameClickerFlappy", GameClickerFlappy, cfg, st, (*) => GameClickerFlappy.ToggleMode())
RunGameCycle("GameLightCycles", GameLightCycles, cfg, st)
RunGameCycle("GamePacGrid", GamePacGrid, cfg, st, (*) => GamePacGrid.ToggleViewMode())
RunGameCycle("GameMissileDefense", GameMissileDefense, cfg, st)
RunGameCycle("GameBlockDrop", GameBlockDrop, cfg, st, "", true)
RunGameCycle("GameSpacePinball (Primary Dark/Light)", GameSpacePinball, cfg, st, "", true)

; Also exercise GameSpacePinball + GameBlockDrop directly with strict Remote-shape config/state!
RunGameCycle("GameSpacePinball (Remote-shape)", GameSpacePinball, remoteCfg, remoteSt, "", true)
RunGameCycle("GameBlockDrop (Remote-shape)", GameBlockDrop, remoteCfg, remoteSt, "", true)

; 5. Real InitHUD -> HandleHudPillClick across HUD pills -> clean GUI teardown
InitHUD(cfg, st, false)
AssertTrue(IsObject(st.MicGui) && IsObject(st.RecGui) && IsObject(st.StudioGui) && IsObject(st.SceneGui) && IsObject(st.StreamGui),
    "InitHUD initializes Primary HUD GUIs with real Config & OverlayState")
AssertTrue(HandleHudPillClick(cfg, st, st.MicGui.Hwnd) == "mic", "HandleHudPillClick MicGui succeeds")
AssertTrue(HandleHudPillClick(cfg, st, st.RecGui.Hwnd) != false, "HandleHudPillClick RecGui succeeds")
AssertTrue(HandleHudPillClick(cfg, st, st.StudioGui.Hwnd) == "studio", "HandleHudPillClick StudioGui succeeds")
AssertTrue(HandleHudPillClick(cfg, st, st.SceneGui.Hwnd) == "scene", "HandleHudPillClick SceneGui succeeds")
AssertTrue(HandleHudPillClick(cfg, st, st.StreamGui.Hwnd) == "stream_readonly", "HandleHudPillClick StreamGui succeeds")
for _, fnProp in ["dragTimerFn", "breathTimerFn", "voiceMeterTimerFn", "mutedVoiceTimerFn", "autoDodgeTimerFn", "idleDimTimerFn", "sceneMarqueeTimerFn", "recTimerFn"] {
    if (st.HasOwnProp(fnProp) && IsObject(st.%fnProp%))
        try SetTimer(st.%fnProp%, 0)
}
for _, prop in _GetHudGuiPropNames(true) {
    if (st.HasOwnProp(prop) && IsObject(st.%prop%)) {
        try st.%prop%.Destroy()
        st.%prop% := ""
    }
}

; 6. Control Center, About, Help & OpenShortcutCaptureDialog lifecycle
suspBefore := Theme.SuspendLockCount
cc := ShowControlCenterWindow(cfg, st)
AssertTrue(IsObject(cc) && WinExist("ahk_id " cc.Hwnd), "ShowControlCenterWindow renders with real Config & OverlayState")
try WinClose("ahk_id " cc.Hwnd)

ab := ShowAboutWindow(cfg, st)
AssertTrue(IsObject(ab) && WinExist("ahk_id " ab.Hwnd), "ShowAboutWindow renders with real Config & OverlayState")
try WinClose("ahk_id " ab.Hwnd)

hp := ShowHelpWindow(cfg, st)
AssertTrue(IsObject(hp) && WinExist("ahk_id " hp.Hwnd), "ShowHelpWindow renders with real Config & OverlayState")
try WinClose("ahk_id " hp.Hwnd)

cap := OpenShortcutCaptureDialog("F8", (*) => "")
AssertTrue(IsObject(cap) && WinExist("ahk_id " cap.Hwnd), "OpenShortcutCaptureDialog opens cleanly")
try WinClose("ahk_id " cap.Hwnd)
Sleep(30)
AssertTrue(Theme.SuspendLockCount == suspBefore, "OpenShortcutCaptureDialog releases Theme suspend count on close")

; 7. Static source sweep across PresenterSync.ahk, PresenterSync_Remote.ahk, Lib\*.ahk, Lib\Arcade\*.ahk
rootDir := A_ScriptDir "\.."
scanFiles := [rootDir "\PresenterSync.ahk", rootDir "\PresenterSync_Remote.ahk"]
Loop Files, rootDir "\Lib\*.ahk"
    scanFiles.Push(A_LoopFileFullPath)
Loop Files, rootDir "\Lib\Arcade\*.ahk"
    scanFiles.Push(A_LoopFileFullPath)

badTokens := [".HudTheme", ".obsMuted", "BASE_WIDTH_ONLY", "OBS_POLL_INTERVAL_MS"]
for _, fPath in scanFiles {
    txt := FileRead(fPath, "UTF-8")
    AssertTrue(!RegExMatch(txt, "(?i)(?<!Theme|this)\.IsDarkMode\b"), "No invalid .IsDarkMode property access in " fPath)
    for _, tok in badTokens
        AssertTrue(!InStr(txt, tok), "No forbidden property/constant '" tok "' in " fPath)
}
remTxt := FileRead(rootDir "\PresenterSync_Remote.ahk", "UTF-8")
AssertTrue(InStr(remTxt, "remoteDeckHotIfFn :="), "PresenterSync_Remote.ahk RemoteState declares remoteDeckHotIfFn")
astTxt := FileRead(rootDir "\Lib\Arcade\GameAsteroids.ahk", "UTF-8")
AssertTrue(InStr(astTxt, "M → Alien Blaster") && InStr(astTxt, "M → Asteroid Blaster"),
    "GameAsteroids.ahk includes clear M-key Blaster mode-switch hints")

summary := Format("v9.0.1 Runtime Audit: Passed={}, Failed={}`n", passed, failed)
try FileAppend(summary, "*")
if (failed > 0)
    ExitApp(1)
ExitApp(0)
