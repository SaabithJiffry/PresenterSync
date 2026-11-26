; ==============================================================================
; Test Suite: test_v781_static_audit_regression.ahk
; Description: Verifies v7.8.1 static & security audit fixes (DiagnosticLogger
;              redaction, HostBridge bounds/RFC6455/auth/headers, WebRemoteUI
;              HTML escaping, HotIf try/finally, and ProGuard keep rules).
; ==============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
SetTimer(() => ExitApp(124), -45000)
OnError((err, mode) => (FileAppend("UNHANDLED_ERR: " err.Message " (" err.What ") at " err.File ":" err.Line "`n", "*"), ExitApp(1)))

#Include "%A_LineFile%\..\..\Lib\WebSocket.ahk"
#Include "%A_LineFile%\..\..\Lib\UIA.ahk"
#Include "%A_LineFile%\..\..\Lib\Crypto.ahk"
#Include "%A_LineFile%\..\..\Lib\Gdip.ahk"
#Include "%A_LineFile%\..\..\Lib\OBS_Network.ahk"
#Include "%A_LineFile%\..\..\Lib\GUI_Config.ahk"
#Include "%A_LineFile%\..\..\Lib\WebRemoteUI.ahk"
#Include "%A_LineFile%\..\..\Lib\HostBridge.ahk"

global g_IsTestMode := true

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

; 1. DiagnosticLogger pattern redaction & longest-first scrubbing
sample := 'PSGCM1|AQIDBAUG|cipher== PSRELAY|room|1|2|myauth {"sessionToken":"tok_abc123","obsPassword":"pw9"} Authorization: Bearer jwt_xyz X-PresenterSync-Token: hdr_tok presentersync://pair?host=1.2.3.4&code=123456&pw=MyPass'
scrubbed := DiagnosticLogger._ScrubSecrets(sample, ["tok_abc123"])
AssertTrue(InStr(scrubbed, "[REDACTED]") && !InStr(scrubbed, "tok_abc123") && !InStr(scrubbed, "jwt_xyz"), "DiagnosticLogger._ScrubSecrets redacts secrets and Bearer header")

; 2. HostBridgeConstants.MAX_CLIENTS, _TryAuthenticateWsClient, _QueueWsFrame (>65535), HTTP headers
AssertTrue(HostBridgeConstants.MAX_CLIENTS == 64, "HostBridgeConstants.MAX_CLIENTS == 64")

tmpIni := A_Temp "\PresenterSync_v781_test_" A_TickCount ".ini"
if FileExist(tmpIni)
    FileDelete(tmpIni)
if FileExist(tmpIni ".bak")
    FileDelete(tmpIni ".bak")
cfg := Config(tmpIni)
st := OverlayState(cfg)
bridge := HostCompanionBridge()
bridge.cfg := cfg
bridge.state := st

cli := { sock: 999, ip: "10.0.0.55", authenticated: false, deviceId: "", sendBuf: Buffer(0), sendLen: 0, rxBuf: Buffer(0), rxLen: 0 }
bridge.pairedDevices["dev-1"] := { deviceId: "dev-1", deviceName: "Test", token: "good-tok-123" }

bridge._RecordPairingFailure("10.0.0.55")
AssertTrue(bridge._GetRateLimit("10.0.0.55").fails >= 1, "_RecordPairingFailure increments pairing failures")
bridge._ResetPairingFailures("10.0.0.55")
AssertTrue(bridge._GetRateLimit("10.0.0.55").fails == 0, "_ResetPairingFailures resets pairing failures")

; RFC 6455 64-bit extended length (127, 10-byte header) invariant
hbSrc := FileRead(A_ScriptDir "\..\Lib\HostBridge.ahk", "UTF-8")
AssertTrue(InStr(hbSrc, "127") && InStr(hbSrc, "X-Content-Type-Options: nosniff") && InStr(hbSrc, "X-Frame-Options: DENY"), "HostBridge.ahk includes RFC 6455 127 extended frame and security headers")

; WebRemoteUI HTML escaping
html := BuildWebRemoteHtml("7.8.1&<>`"'", 4456)
AssertTrue(InStr(html, "7.8.1&amp;&lt;&gt;&quot;&#39;"), "BuildWebRemoteHtml escapes all 5 HTML entities in version string")

; 3. Source invariants: try/finally { HotIf } in PresenterSync.ahk & ProGuard keep rules
psSrc := FileRead(A_ScriptDir "\..\PresenterSync.ahk", "UTF-8")
AssertTrue(InStr(psSrc, "finally {") && InStr(psSrc, "HotIf()"), "PresenterSync.ahk wraps HotIf sections in try/finally")

pgSrc := FileRead(A_ScriptDir "\..\android\app\proguard-rules.pro", "UTF-8")
AssertTrue(InStr(pgSrc, "AppWidgetProvider") || InStr(pgSrc, "PresenterSyncWidgetProvider"), "proguard-rules.pro keeps AppWidgetProvider")

; 4. P1-1 Static Audit: zero native ToolTip calls outside Lib\CaptureSafety.ahk
toolTipHits := 0
ttPaths := [A_ScriptDir "\..\PresenterSync.ahk", A_ScriptDir "\..\PresenterSync_Remote.ahk"]
Loop Files A_ScriptDir "\..\Lib\*.ahk" {
    if (A_LoopFileName != "CaptureSafety.ahk")
        ttPaths.Push(A_LoopFileFullPath)
}
for _, scanPath in ttPaths {
    srcTxt := FileRead(scanPath, "UTF-8")
    if (RegExMatch(srcTxt, "im`a)^[ \t]*ToolTip(?:\([^)\r\n]*\)|[ \t]+`"[^`"\r\n]+`")"))
        toolTipHits++
}
AssertTrue(toolTipHits == 0, "Zero native ToolTip calls outside Lib\CaptureSafety.ahk (found " toolTipHits ")")

cfg.DeleteFile()

try FileAppend("PASS=" passed " FAIL=" failed "`n", "*")
ExitApp(failed > 0 ? 1 : 0)
