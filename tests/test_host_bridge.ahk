; ==============================================================================
; Test Suite: test_host_bridge.ahk
; Description: Automated unit + live loopback harness for Crypto SHA1/SessionCode
;              and non-blocking HostCompanionBridge (WSAAsyncSelect)
;              Supports optional "--serve <readyFile>" mode for external Python
;              UDP / HTTP / RFC6455 WebSocket E2E verification.
; ==============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

#Include "..\Lib\WebSocket.ahk"
#Include "..\Lib\Crypto.ahk"
#Include "..\Lib\Gdip.ahk"
#Include "..\Lib\UIA.ahk"
#Include "..\Lib\OBS_Network.ahk"
#Include "..\Lib\GUI_Config.ahk"

Gdip.Startup()
OnExit((*) => (StopHostCompanionBridge(), Theme.Shutdown(), UIA.Shutdown(), Gdip.Shutdown()))

results := []
PassCount := 0
FailCount := 0

BridgeTestFailFast(exc, mode) {
    global results, FailCount
    FailCount += 1
    msg := Format("[FAIL] Unhandled exception ({}) in {} ({}:{}): {}", mode, exc.What, exc.File, exc.Line, exc.Message)
    results.Push(msg)
    try FileAppend(msg "`n", A_ScriptDir "\host_bridge_results.log")
    ExitApp(1)
}
OnError(BridgeTestFailFast)

BridgeTestWatchdog() {
    global results, FailCount
    FailCount += 1
    msg := "[FAIL] HostBridge test watchdog timeout reached (25s)"
    results.Push(msg)
    try FileAppend(msg "`n", A_ScriptDir "\host_bridge_results.log")
    ExitApp(2)
}
SetTimer(BridgeTestWatchdog, -25000)

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

; --- Check serve mode (--serve <infoJsonPath>) ---
serveMode := false
readyPath := ""
if (A_Args.Length >= 2 && A_Args[1] = "--serve") {
    serveMode := true
    readyPath := A_Args[2]
}

testIni := A_ScriptDir "\test_host_bridge_cfg.ini"
if FileExist(testIni)
    FileDelete(testIni)
cfg := Config(testIni)
cfg.SessionPairingCode := "K7M-9P2"
cfg.obsPassword := "bridgePass123"
cfg.targetMicName := "Studio Mic"
cfg.AudioRoutingMode := 2
cfg.ConferencingApp := "Zoom"
cfg.InternetPairingCode := "PS-BRDG-777"

mockObsSent := []
st := {
    isMuted: false,
    obsConnected: false,
    obsWs: { sendText: (this, pkt) => mockObsSent.Push(pkt) },
    zoomConnected: false,
    EnableWS: false,
    relayConnected: false,
    relayWs: ""
}

if (serveMode) {
    Persistent(true)
    ; Expose small HTTP/OBS switch test setup on ephemeral port 0
    bridge := StartHostCompanionBridge(cfg, st, 0, 0)
    if (!IsObject(bridge) || !bridge.running) {
        FileAppend('{"ok":false}', readyPath, "UTF-8")
        ExitApp(3)
    }
    if FileExist(readyPath)
        FileDelete(readyPath)
    infoJson := '{"ok":true,"tcpPort":' bridge.boundTcpPort ',"udpPort":' bridge.boundUdpPort ',"sessionCode":"' cfg.SessionPairingCode '"}'
    FileAppend(infoJson, readyPath, "UTF-8")

    ; Poll trigger command file if Python wants to test Host-initiated CloseRemote or Mode 1 OBS toggle
    cmdFile := readyPath ".cmd"
    _PollTestCmd() {
        if (!FileExist(cmdFile))
            return
        cmd := Trim(FileRead(cmdFile, "UTF-8"))
        try FileDelete(cmdFile)
        if (cmd = "CLOSE_REMOTE") {
            SendCloseRemoteSignal(cfg, st)
        } else if (cmd = "ROTATE_CODE") {
            RotateHostSessionPairingCode(cfg)
            FileAppend(cfg.SessionPairingCode, readyPath ".rotated", "UTF-8")
        } else if (cmd = "MODE1_OBS") {
            cfg.AudioRoutingMode := 1
            st.obsConnected := true
            mockObsSent.Length := 0
        } else if (cmd = "BROADCAST_OBS_MUTE_TRUE") {
            SyncUIState(cfg, st, true)
        } else if (cmd = "MODE3_DUAL") {
            cfg.AudioRoutingMode := 3
            st.obsConnected := true
            mockObsSent.Length := 0
        } else if (cmd = "STOP") {
            ExitApp(0)
        }
    }
    SetTimer(_PollTestCmd, 50)
    return
}

; --- STANDALONE UNIT ASSERTIONS ---
; 1. RFC 6455 exact SHA-1 WebSocket-Accept test vector
rfcAccept := HashSHA1_Base64("dGhlIHNhbXBsZSBub25jZQ==258EAFA5-E914-47DA-95CA-C5AB0DC85B11")
Assert("RFC 6455 Sec-WebSocket-Accept exact vector", rfcAccept == "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", "got=" rfcAccept)

; 2. Session pairing code generation & normalization
code1 := GenerateSessionPairingCode()
code2 := GenerateSessionPairingCode()
Assert("GenerateSessionPairingCode format XXX-XXX", RegExMatch(code1, "^[A-HJ-NP-Z2-9]{3}-[A-HJ-NP-Z2-9]{3}$") > 0, code1)
Assert("NormalizePairingCode strips spaces/dashes and uppercases", NormalizePairingCode(" k7m - 9p2 ") == "K7M9P2")
Assert("SHA256 hex length is 64 chars", StrLen(HashSHA256_Hex("abc")) == 64)

; 3. HostCompanionBridge ephemeral port start/stop & ShowRemoteCompanionInfo geometry
b := StartHostCompanionBridge(cfg, st, 0, 0)
Assert("HostCompanionBridge starts on ephemeral TCP & UDP ports",
    IsObject(b) && b.running && b.boundTcpPort > 0 && b.boundUdpPort > 0,
    "TCP=" b.boundTcpPort " UDP=" b.boundUdpPort)

sum := GetHostBridgeStatusSummary()
Assert("GetHostBridgeStatusSummary reports running state", sum.running && sum.tcpPort == b.boundTcpPort)

dlg := ShowRemoteCompanionInfo(cfg, st)
dlg.GetClientPos(, , &cw, &ch)
Assert("ShowRemoteCompanionInfo renders Session Code & Bridge status cleanly", cw >= 360 && ch >= 320, cw "x" ch)
WinClose("ahk_id " dlg.Hwnd)

StopHostCompanionBridge()
Assert("StopHostCompanionBridge shuts down cleanly", !IsObject(g_HostCompanionBridge) && !GetHostBridgeStatusSummary().running)

if FileExist(testIni)
    FileDelete(testIni)

report := "=== PRESENTER SYNC HOST BRIDGE UNIT REPORT ===`nPassed: " PassCount " | Failed: " FailCount "`n`n"
for r in results
    report .= r "`n"

logFile := A_ScriptDir "\host_bridge_results.log"
if FileExist(logFile)
    FileDelete(logFile)
FileAppend(report, logFile, "UTF-8")
try FileAppend(report, "*")
ExitApp(FailCount > 0 ? 1 : 0)
