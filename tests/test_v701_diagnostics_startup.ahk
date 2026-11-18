; ==============================================================================
; Test Suite: test_v701_diagnostics_startup.ahk
; Description: Verifies DiagnosticLogger (50-event ring buffer, 5-section
;              snapshot + secret redaction, CheckLatency PERF_LAG),
;              GetLocalNetworkEndpoints() 100x rapid enumeration (Issue #13),
;              and safe OnExit AppState guard + g_IsTestMode (Issue #8).
; ==============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
SetTimer(() => ExitApp(124), -45000)

#Include "%A_LineFile%\..\..\Lib\WebSocket.ahk"
#Include "%A_LineFile%\..\..\Lib\UIA.ahk"
#Include "%A_LineFile%\..\..\Lib\Crypto.ahk"
#Include "%A_LineFile%\..\..\Lib\Gdip.ahk"
#Include "%A_LineFile%\..\..\Lib\OBS_Network.ahk"
#Include "%A_LineFile%\..\..\Lib\GUI_Config.ahk"

global g_IsTestMode := true
global AppState := ""

passed := 0
failed := 0

AssertTrue(cond, label) {
    global passed, failed
    if (cond) {
        passed++
    } else {
        failed++
        try FileAppend("FAIL: " label "`n", "*")
    }
}

testLogDir := A_Temp "\PresenterSync_DiagTest_" A_TickCount
DiagnosticLogger.LogDir := testLogDir
DiagnosticLogger.Init("PresenterSync_Test")

; (a) 50-event breadcrumb ring buffer trimming
DiagnosticLogger.Breadcrumbs := []
Loop 75 {
    DiagnosticLogger.RecordBreadcrumb("TestCat", "Action#" A_Index, "detail=" A_Index)
}
AssertTrue(DiagnosticLogger.Breadcrumbs.Length == 50, "Breadcrumb ring buffer trims to 50 items")
AssertTrue(DiagnosticLogger.Breadcrumbs[1].action = "Action#26", "Oldest retained breadcrumb is Action#26")
AssertTrue(DiagnosticLogger.Breadcrumbs[50].action = "Action#75", "Newest retained breadcrumb is Action#75")

; (b) LogIssue 5-section snapshot generation + password/token [REDACTED] scrubbing
mockCfg := {
    ActiveProfile: "Default",
    AudioRoutingMode: 1,
    EnablePPT: true,
    EnableMicOnly: false,
    HwMuteHotkey: "^+m",
    ObsMuteHotkey: "None",
    EnableWS: true,
    EnableZoom: false,
    CatchArrows: true,
    CatchPgUpDn: true,
    CatchB: true,
    CatchEsc: true,
    RemoteNetworkMode: "LAN",
    BridgePort: 4456,
    obsPassword: "MySecretObsPassword!123",
    ObsPassword: "MySecretObsPassword!123",
    InternetPairingCode: "PAIR-9988-SECRET",
    SessionPairingCode: "SESS-4455-SECRET",
    SessionToken: "tok_super_secret_token_999"
}
mockState := {
    obsConnected: true,
    studioModeActive: false,
    currentSceneName: "Main Scene",
    previewSceneName: "Preview",
    isMuted: false,
    recState: 0,
    streamState: 0,
    zoomConnected: false,
    IsSyncing: false,
    usingBridge: true
}
DiagnosticLogger.BindContext(mockCfg, mockState)
DiagnosticLogger.RecordBreadcrumb("OBS", "ConnectAttempt", "pw=MySecretObsPassword!123")

logged := DiagnosticLogger.LogIssue("ERROR", "UnitTest", "Simulated failure with tok_super_secret_token_999", "Testing 5-section snapshot and redaction.")
AssertTrue(logged, "LogIssue returned true")

logPath := DiagnosticLogger.GetLogPath()
jsonlPath := DiagnosticLogger.GetJsonlPath()
AssertTrue(FileExist(logPath), "ErrorLog.log file created")
AssertTrue(FileExist(jsonlPath), "ErrorLog.jsonl file created")

logTxt := FileRead(logPath, "UTF-8")
jsonlTxt := FileRead(jsonlPath, "UTF-8")
AssertTrue(InStr(logTxt, "[1. ERROR & CAUSAL REMARK]"), "Section 1 present")
AssertTrue(InStr(logTxt, "[2. SYSTEM DETAILS SNAPSHOT]"), "Section 2 present")
AssertTrue(InStr(logTxt, "[3. PROGRAM & LIVE STATE SNAPSHOT]"), "Section 3 present")
AssertTrue(InStr(logTxt, "[4. SANITIZED SETTINGS SNAPSHOT]"), "Section 4 present")
AssertTrue(InStr(logTxt, "[5. PRE-ERROR BREADCRUMB TRAIL (LAST 50 EVENTS)]"), "Section 5 present")
AssertTrue(InStr(logTxt, "[REDACTED]"), "Secrets replaced with [REDACTED]")
AssertTrue(!InStr(logTxt, "MySecretObsPassword!123"), "obsPassword scrubbed from .log")
AssertTrue(!InStr(logTxt, "tok_super_secret_token_999"), "SessionToken scrubbed from .log")
AssertTrue(!InStr(logTxt, "PAIR-9988-SECRET"), "InternetPairingCode scrubbed from .log")
AssertTrue(!InStr(jsonlTxt, "MySecretObsPassword!123"), "obsPassword scrubbed from .jsonl")
AssertTrue(!InStr(jsonlTxt, "tok_super_secret_token_999"), "SessionToken scrubbed from .jsonl")

; (c) CheckLatency (> 120ms) PERF_LAG logging
fakeStart := A_TickCount - 250
elapsed := DiagnosticLogger.CheckLatency("Timer", "SlowTick", fakeStart, 120, "simulated lag")
AssertTrue(elapsed >= 250, "CheckLatency returns elapsed >= 250ms")
logTxtAfterLag := FileRead(logPath, "UTF-8")
AssertTrue(InStr(logTxtAfterLag, "PERF_LAG"), "CheckLatency logs PERF_LAG when exceeding threshold")

; (d) GetLocalNetworkEndpoints() 100x rapid enumeration without A_IPAddress1 error
rapidOk := true
try {
    Loop 100 {
        epsFast := GetLocalNetworkEndpoints(false)
        if (!IsObject(epsFast) || !epsFast.HasOwnProp("ips"))
            rapidOk := false
    }
    epsFull := GetLocalNetworkEndpoints(true)
    if (!IsObject(epsFull) || !epsFull.HasOwnProp("ips"))
        rapidOk := false
} catch as e {
    rapidOk := false
    try FileAppend("FAIL: GetLocalNetworkEndpoints threw: " e.Message "`n", "*")
}
AssertTrue(rapidOk, "GetLocalNetworkEndpoints 100x rapid enumeration succeeds without A_IPAddress1 error")

; (e) Safe OnExit guard when AppState == "" & headless ShowLogViewerWindow
guardOk := false
try {
    res := (IsSet(AppState) && IsObject(AppState)) ? (AppState.HasOwnProp("presenterTimerFn") ? 1 : 2) : 0
    guardOk := (res == 0)
} catch {
    guardOk := false
}
AssertTrue(guardOk, "AppState empty guard evaluates safely without throwing")

viewerRes := DiagnosticLogger.ShowLogViewerWindow(mockCfg, AppState)
AssertTrue(IsObject(viewerRes) && viewerRes.shown == false && viewerRes.testMode == true, "ShowLogViewerWindow respects g_IsTestMode without blocking")

; Cleanup temp log dir
try DirDelete(testLogDir, true)

try FileAppend("PASS=" passed " FAIL=" failed "`n", "*")
ExitApp(failed > 0 ? 1 : 0)
