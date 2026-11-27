; ==============================================================================
; Test Suite: test_remote_audit.ahk
; Description: Comprehensive automated unit & live test for PresenterSync Remote
; ==============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

#Include "..\Lib\WebSocket.ahk"
#Include "..\Lib\Crypto.ahk"
#Include "..\Lib\RemoteBridgeClient.ahk"
#Include "..\Lib\Gdip.ahk"
#Include "..\Lib\GUI_Config.ahk"
#Include "..\Lib\HudSnakeGame.ahk"

Gdip.Startup()
OnExit((*) => (HudSnake.Stop(), Theme.Shutdown(), Gdip.Shutdown()))

results := []
PassCount := 0
FailCount := 0

RemoteAuditFailFast(exc, mode) {
    global results, FailCount
    FailCount += 1
    msg := Format("[FAIL] Unhandled exception ({}) in {} ({}:{}): {}", mode, exc.What, exc.File, exc.Line, exc.Message)
    results.Push(msg)
    try FileAppend(msg "`n", A_ScriptDir "\audit_results.log")
    ExitApp(1)
}
OnError(RemoteAuditFailFast)

RemoteAuditWatchdog() {
    global results, FailCount
    FailCount += 1
    msg := "[FAIL] Watchdog timeout reached (15s)"
    results.Push(msg)
    try FileAppend(msg "`n", A_ScriptDir "\audit_results.log")
    ExitApp(2)
}
SetTimer(RemoteAuditWatchdog, -15000)

Assert(testName, condition, detail := "") {
    global PassCount, FailCount, results
    if (condition) {
        PassCount += 1
        results.Push("[PASS] " testName (detail != "" ? " - " detail : ""))
    } else {
        FailCount += 1
        results.Push("[FAIL] " testName (detail != "" ? " - " detail : ""))
    }
}

; --- TEST 1: Network Endpoint Discovery ---
endpoints := GetLocalNetworkEndpoints()
Assert("GetLocalNetworkEndpoints returns an object", IsObject(endpoints))
Assert("GetLocalNetworkEndpoints detected at least 1 IP", endpoints.ips.Length > 0, "Detected: " endpoints.ips.Length " IPs")
Assert("mDNS Hostname resolved", A_ComputerName != "", "Host: " A_ComputerName ".local")

; --- TEST 2: Candidate Parsing ---
candidates1 := ParseCandidateEndpoints("STUDIO-PC.local, 192.168.1.50, 192.168.1.120:4456")
Assert("Multi-candidate parsing count", candidates1.Length == 3, "Parsed " candidates1.Length " items")
Assert("Candidate 1 hostname", candidates1[1].host == "STUDIO-PC.local" && candidates1[1].port == "4455")
Assert("Candidate 2 IP", candidates1[2].host == "192.168.1.50" && candidates1[2].port == "4455")
Assert("Candidate 3 Custom Port", candidates1[3].host == "192.168.1.120" && candidates1[3].port == "4456")

candidates2 := ParseCandidateEndpoints("ws://192.168.1.10:4455;10.0.0.5")
Assert("Clean protocol prefix stripping", candidates2[1].host == "192.168.1.10" && candidates2[2].host == "10.0.0.5")

; --- TEST 3: Config Loading & Defaults ---
testIni := A_ScriptDir "\test_remote_config.ini"
if FileExist(testIni)
    FileDelete(testIni)

cfg := Config(testIni)
Assert("Config initializes successfully", IsObject(cfg))
cfg.Write("Connection", "HostAddress", "STUDIO-PC.local, 192.168.1.50")
readHost := cfg.Read("Connection", "HostAddress")
Assert("Config Write/Read integrity", readHost == "STUDIO-PC.local, 192.168.1.50")

; --- TEST 4: Layout & HUD Computation at Various Scales ---
dummyState := OverlayState(cfg)
Assert("OverlayState instantiation", IsObject(dummyState))

dummyState.baseWidth := 80
dummyState.baseHeight := 40
dummyState.savedX := 100
dummyState.savedY := 100
layout := ComputeHudLayout(dummyState, 100, 100)
Assert("ComputeHudLayout execution without crash", IsObject(layout))
Assert("ComputeHudLayout mic coordinates", layout.micX == 100 && layout.micY == 100)

; Test high-scale for 4K smart board (5.0x)
cfg.IndicatorScale := 5.0
cfg.ShowText := true
dummyState.ComputeDimensions(cfg)
Assert("Dimension computation at 5.0x scale", dummyState.baseWidth > 500 && dummyState.baseHeight == 200, "BaseW: " dummyState.baseWidth " BaseH: " dummyState.baseHeight)

; --- TEST 5: SHA256 Base64 Authentication Logic ---
testPass := "supersecret"
testSalt := "dGVzdHNhbHQ="
testChallenge := "dGVzdGNoYWxsZW5nZQ=="

secret := HashSHA256_Base64(testPass . testSalt)
authResponse := HashSHA256_Base64(secret . testChallenge)
Assert("SHA256 Base64 hash execution", StrLen(authResponse) > 20, "Hash: " authResponse)

; --- TEST 6: Single-Pill Layered Window Creation & GDI+ Render ---
dummyState.MicGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000 -DPIScale")
renderOkLive := ApplyMicAppearance(cfg, dummyState, 100, 100, 140, 40, 220, false)
Assert("ApplyMicAppearance (LIVE State) renders without error", renderOkLive != false)

renderOkMuted := ApplyMicAppearance(cfg, dummyState, 100, 100, 140, 40, 220, true)
Assert("ApplyMicAppearance (MUTED State) renders without error", renderOkMuted != false)

; --- TEST 7: Distinct PW REQ vs AUTH ERR HUD Pill States & Desktop Instance Shortcuts ---
dummyState.activeHost := "127.0.0.1:4455"
dummyState.obsConnected := false
cfg.ShowText := true
dummyState.connStatus := "searching"
renderOkOff := ApplyMicAppearance(cfg, dummyState, 100, 100, 168, 40, 220, "")
dummyState.connStatus := "pw_required"
renderOkPwReq := ApplyMicAppearance(cfg, dummyState, 100, 100, 168, 40, 220, "")
dummyState.connStatus := "auth_failed"
renderOkAuthErr := ApplyMicAppearance(cfg, dummyState, 100, 100, 168, 40, 220, "")
Assert("ApplyMicAppearance renders distinct OFFLINE, PW REQ, and AUTH ERR states cleanly",
    renderOkOff != false && renderOkPwReq != false && renderOkAuthErr != false)
dummyState.MicGui.Destroy()

lnkDir := A_Temp "\ps_lnk_test_" A_TickCount
cfg.ConfigFile := lnkDir "\PresenterSync_Remote_SmartBoard-101.ini"
lnkRes := CreateRemoteInstanceDesktopShortcut(cfg, "SmartBoard-101", lnkDir, "", true)
lnkTarget := "", lnkArgs := ""
if (lnkRes.ok && FileExist(lnkRes.lnkPath)) {
    try {
        shObj := ComObject("WScript.Shell")
        scObj := shObj.CreateShortcut(lnkRes.lnkPath)
        lnkTarget := scObj.TargetPath
        lnkArgs := scObj.Arguments
    }
}
try DirDelete(lnkDir, true)
Assert("CreateRemoteInstanceDesktopShortcut builds valid .lnk with -Instance and -Config flags",
    lnkRes.ok && InStr(lnkTarget, ".exe") && InStr(lnkArgs, '-Instance "SmartBoard-101"') && InStr(lnkArgs, '-Config "'))

; --- TEST 8: Remote Single-Tier Non-Headless HUD Snake Lifecycle ---
remSnkCfg := Config(testIni)
remSnkCfg.ShowIndicator := true
remSnkGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000 -DPIScale")
remSnkGui.Show("NoActivate x120 y120 w80 h40")
remSnkSpy := { refreshed: 0 }
remSnkState := {
    savedX: 120,
    savedY: 120,
    baseWidth: 80,
    baseHeight: 40,
    isMuted: false,
    obsConnected: true,
    MicGui: remSnkGui,
    refreshHudFn: (*) => (remSnkSpy.refreshed += 1, remSnkGui.Show("NoActivate x120 y120 w80 h40")),
    heartbeatTimerFn: (*) => 0
}
hProcRemSnk := DllCall("GetCurrentProcess", "Ptr")
gdiRemBefore := DllCall("GetGuiResources", "Ptr", hProcRemSnk, "Int", 0, "UInt")
okRemLiveStart := HudSnake.Start(remSnkCfg, remSnkState, false)
Sleep(80)
remSnkHwnd := IsObject(HudSnake._gui) ? HudSnake._gui.Hwnd : 0
remSnkVis := remSnkHwnd ? DllCall("IsWindowVisible", "Ptr", remSnkHwnd, "Int") : 0
remMicHidden := !DllCall("IsWindowVisible", "Ptr", remSnkGui.Hwnd, "Int")
Sleep(400)
HudSnake._FrameTick()
remPhasePlay := HudSnake.Phase
HudSnake.Stop()
Sleep(150)
try SetTimer(remSnkState.heartbeatTimerFn, 0)
remMicRestored := DllCall("IsWindowVisible", "Ptr", remSnkGui.Hwnd, "Int")
gdiRemAfter := DllCall("GetGuiResources", "Ptr", hProcRemSnk, "Int", 0, "UInt")
try remSnkGui.Destroy()
Assert("Remote 1-tier HUD Snake morphs live canvas, hides Mic pill, enters playing, & restores pill cleanly",
    okRemLiveStart && remSnkHwnd != 0 && remSnkVis == 1 && remMicHidden && remPhasePlay == "playing"
    && remMicRestored == 1 && remSnkSpy.refreshed >= 1 && (gdiRemAfter - gdiRemBefore) == 0,
    Format("start={} vis={} hid={} play={} rest={} gdiDelta={}", okRemLiveStart, remSnkVis, remMicHidden, remPhasePlay, remMicRestored, gdiRemAfter - gdiRemBefore))

; --- ROUND 1 AUDIT FIXES: P1-A (C3 Direct OBS Policy Gate) & P2-D (KioskPin [Settings] Migration) ---
c3Cfg := {
    HostAddress: "192.168.1.50",
    HostPort: 4455,
    BridgePort: 4456,
    SessionPairingCode: "AAA-111",
    SessionToken: "tok-1",
    ObsPassword: "StaleOldPassword!",
    TargetMicName: "Mic/Aux",
    DirectObsFallbackAllowed: false
}
qBlocked := BuildRemoteLanCandidateQueue(c3Cfg)
Assert("P1-A: BuildRemoteLanCandidateQueue excludes Direct OBS :4455 when DirectObsFallbackAllowed=false",
    qBlocked.Length == 1 && qBlocked[1].isBridge == true, "len=" qBlocked.Length)
wsEvDeny := ParseHostBridgeWsEvent('{"type":"auth_ok","obsFallback":{"port":4455,"targetMic":"Mic/Aux","password":"","directObsAllowed":false}}')
Assert("P1-A: ParseHostBridgeWsEvent parses obsFallbackDirectObsAllowed=false", wsEvDeny.obsFallbackDirectObsAllowed == false)
_ApplyRemoteObsFallbackCreds(c3Cfg, wsEvDeny)
Assert("P1-A: _ApplyRemoteObsFallbackCreds clears stale ObsPassword & preserves DirectObsFallbackAllowed=false",
    c3Cfg.ObsPassword == "" && c3Cfg.DirectObsFallbackAllowed == false)
c3Cfg.DirectObsFallbackAllowed := true
qAllowed := BuildRemoteLanCandidateQueue(c3Cfg)
Assert("P1-A: BuildRemoteLanCandidateQueue includes Direct OBS :4455 when DirectObsFallbackAllowed=true",
    qAllowed.Length == 2 && qAllowed[2].isBridge == false, "len=" qAllowed.Length)
wsEvTopDeny := ParseHostBridgeWsEvent('{"type":"auth_ok","role":"Director","trustTier":"Pinned Room","allowDirectObsFallback":false}')
Assert("P1-D: ParseHostBridgeWsEvent extracts role & trustTier from auth_ok",
    wsEvTopDeny.role == "Director" && wsEvTopDeny.trustTier == "Pinned Room")
Assert("P2-3: ParseHostBridgeWsEvent parses top-level allowDirectObsFallback=false when obsFallback omitted",
    wsEvTopDeny.hasDirectObsPolicy && wsEvTopDeny.obsFallbackDirectObsAllowed == false)
Assert("P2-3: _ApplyRemoteObsFallbackCreds enforces top-level allowDirectObsFallback=false",
    _ApplyRemoteObsFallbackCreds(c3Cfg, wsEvTopDeny) && c3Cfg.DirectObsFallbackAllowed == false)
wsEvResyncRole := ParseHostBridgeWsEvent('{"type":"sync_resync","reason":"role_change","role":"Tally-Only"}')
Assert("P1-D: ParseHostBridgeWsEvent extracts role from sync_resync",
    wsEvResyncRole.role == "Tally-Only")

pinMigIni := A_Temp "\ps_v101_pin_mig.ini"
try FileDelete(pinMigIni)
IniWrite("1234", pinMigIni, "Settings", "KioskPin")
ConfigStore.MigrateIniSchema(pinMigIni, "Connection")
Assert("P2-D: ConfigStore.MigrateIniSchema encrypts KioskPin in [Settings] even when secretSection='Connection'",
    ConfigStore.IsSecretValueEncrypted(IniRead(pinMigIni, "Settings", "KioskPin", "")))
try FileDelete(pinMigIni)

; --- CLEANUP & REPORT ---
if FileExist(testIni)
    FileDelete(testIni)

report := "=== AUDIT TEST RESULTS ===`n"
report .= "Total: " (PassCount + FailCount) " | Passed: " PassCount " | Failed: " FailCount "`n`n"
for line in results
    report .= line "`n"

logFile := A_ScriptDir "\audit_results.log"
if FileExist(logFile)
    FileDelete(logFile)
FileAppend(report, logFile)
ExitApp(FailCount > 0 ? 1 : 0)
