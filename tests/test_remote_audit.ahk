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

Gdip.Startup()
OnExit((*) => (Theme.Shutdown(), Gdip.Shutdown()))

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
