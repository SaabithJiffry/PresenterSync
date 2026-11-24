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
logFile := A_ScriptDir "\host_bridge_results.log"
if FileExist(logFile)
    try FileDelete(logFile)

BridgeTestFailFast(exc, mode) {
    global results, FailCount, logFile
    FailCount += 1
    msg := Format("[FAIL] Unhandled exception ({}) in {} ({}:{}): {}", mode, exc.What, exc.File, exc.Line, exc.Message)
    results.Push(msg)
    try FileAppend(msg "`n", logFile, "UTF-8")
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
if FileExist(testIni ".bak")
    FileDelete(testIni ".bak")
cfg := Config(testIni)
cfg.SessionPairingCode := "K7M-9P2"
cfg.obsPassword := "bridgePass123"
cfg.targetMicName := "Studio Mic"
cfg.AudioRoutingMode := 2
cfg.ConferencingApp := "Zoom"
cfg.InternetPairingCode := "PS-BRDG-777"

mockObsSent := []
mockPptEvents := []
st := {
    isMuted: false,
    obsConnected: false,
    obsWs: { sendText: (this, pkt) => mockObsSent.Push(pkt) },
    zoomConnected: false,
    EnableWS: false,
    relayConnected: false,
    relayWs: "",
    recState: 0,
    recElapsedSec: 0,
    streamState: 0,
    voiceWhileMuted: false,
    currentSceneName: "Main",
    sceneList: ["Main", "Slides", "BRB"],
    isStandby: false,
    timerState: "stopped",
    timerRemainingSec: 600,
    timerPresetSec: 600,
    suppressNudgeBanners: true,
    pptNextFn: (*) => (mockPptEvents.Push("next"), true),
    pptPrevFn: (*) => (mockPptEvents.Push("prev"), true)
}

if (serveMode) {
    SetTimer(BridgeTestWatchdog, 0)
    Persistent(true)
    ; Expose small HTTP/OBS switch test setup on ephemeral port 0
    bridge := StartHostCompanionBridge(cfg, st, 0, 0)
    if (!IsObject(bridge) || !bridge.running) {
        FileAppend('{"ok":false}', readyPath, "UTF-8")
        ExitApp(3)
    }
    if FileExist(readyPath)
        FileDelete(readyPath)
    infoJson := '{"ok":true,"tcpPort":' bridge.boundTcpPort ',"udpPort":' bridge.boundUdpPort ',"discoverPort":' bridge.boundDiscoverPort ',"hostUuid":"' EnsureHostUuid(cfg) '","sessionCode":"' cfg.SessionPairingCode '"}'
    FileAppend(infoJson, readyPath, "UTF-8")

    ; Poll trigger command file if Python wants to test Host-initiated CloseRemote or Mode 1 OBS toggle
    cmdFile := readyPath ".cmd"
    _PollTestCmd() {
        if (!FileExist(cmdFile))
            return
        cmd := ""
        try cmd := Trim(FileRead(cmdFile, "UTF-8"))
        if (cmd = "")
            return
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
        } else if (cmd = "OBS_REC_MODE") {
            cfg.EnableWS := true
            cfg.EnablePPT := true
            st.obsConnected := true
            mockObsSent.Length := 0
            mockPptEvents.Length := 0
            FileAppend("ok", readyPath ".rec_ready", "UTF-8")
        } else if (cmd = "EMIT_NUDGE") {
            BroadcastHostStageNudge(cfg, st, "2 minutes remaining", "Director", "F59E0B")
        } else if (cmd = "EMIT_TELEMETRY") {
            st.recState := 1
            st.recElapsedSec := 95
            st.streamState := 2
            st.voiceWhileMuted := true
            HostBridgeBroadcastMuteState(cfg, st)
        } else if (cmd = "POWER_SUSPEND") {
            HandleHostPowerEvent(cfg, st, 4)
            FileAppend("suspended", readyPath ".power", "UTF-8")
        } else if (cmd = "POWER_RESUME") {
            try FileDelete(readyPath ".power")
            HandleHostPowerEvent(cfg, st, 7)
            FileAppend("resumed:" bridge.boundTcpPort ":" bridge.boundDiscoverPort, readyPath ".power", "UTF-8")
        } else if (cmd = "DUMP_EVENTS") {
            hasRec := false
            hasSwitchScene := false
            hasPauseRec := false
            hasSplitRec := false
            for pkt in mockObsSent {
                if (InStr(pkt, "ToggleRecordPause"))
                    hasPauseRec := true
                else if (InStr(pkt, "ToggleRecord"))
                    hasRec := true
                if (InStr(pkt, "SetCurrentProgramScene"))
                    hasSwitchScene := true
                if (InStr(pkt, "SplitRecordFile"))
                    hasSplitRec := true
            }
            pptStr := ""
            for idx, ev in mockPptEvents
                pptStr .= (idx > 1 ? "," : "") ev
            try FileDelete(readyPath ".events")
            FileAppend('{"ppt":"' pptStr '","obsCount":' mockObsSent.Length ',"hasToggleRecord":' (hasRec ? "true" : "false") ',"hasSwitchScene":' (hasSwitchScene ? "true" : "false") ',"hasPauseRec":' (hasPauseRec ? "true" : "false") ',"hasSplitRec":' (hasSplitRec ? "true" : "false") ',"activeScene":"' st.currentSceneName '","isStandby":' (st.isStandby ? "true" : "false") ',"timerState":"' st.timerState '"}', readyPath ".events", "UTF-8")
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
b := StartHostCompanionBridge(cfg, st, 0, 0, 0)
Assert("HostCompanionBridge starts on ephemeral TCP, UDP & PS_DISCOVER_V1 ports",
    IsObject(b) && b.running && b.boundTcpPort > 0 && b.boundUdpPort > 0 && b.boundDiscoverPort > 0,
    "TCP=" b.boundTcpPort " UDP=" b.boundUdpPort " DISC=" b.boundDiscoverPort)

sum := GetHostBridgeStatusSummary()
Assert("GetHostBridgeStatusSummary reports running state, discoverPort & hostUuid",
    sum.running && sum.tcpPort == b.boundTcpPort && sum.discoverPort == b.boundDiscoverPort && StrLen(sum.hostUuid) == 36)

refOk := b.RefreshNetworkListeners("wake_test")
Assert("RefreshNetworkListeners rebinds TCP/UDP/Discovery sockets cleanly",
    refOk && b.boundTcpPort > 0 && b.boundUdpPort > 0 && b.boundDiscoverPort > 0 && b.lastWakeRefreshTick > 0)

serDev := _HB_SerializePairedDevice({ deviceId: "and-1", deviceName: "Hall, Main|Board", customName: true, platform: "Android", token: "tok_abc123", ip: "10.0.0.5", transport: "WS", pairedAt: "1700000" })
parDev := _HB_ParsePairedDevice("and-1", serDev)
Assert("_HB_SerializePairedDevice/_HB_ParsePairedDevice round-trips customName and escaped delimiter",
    IsObject(parDev) && parDev.customName && parDev.deviceName == "Hall, Main|Board" && parDev.token == "tok_abc123" && parDev.transport == "WS")

dlg := ShowRemoteCompanionInfo(cfg, st)
dlg.GetClientPos(, , &cw, &ch)
Assert("ShowRemoteCompanionInfo renders Session Code & Bridge status cleanly", cw >= 360 && ch >= 320, cw "x" ch)
WinClose("ahk_id " dlg.Hwnd)

; 4. v7.0.5 (#11): Dead client timeout, _OnMaintenanceTick reaping, duplicate deviceId eviction, and post-restart re-bind
Assert("HostBridgeConstants.DEAD_CLIENT_TIMEOUT_MS is 55000ms", HostBridgeConstants.DEAD_CLIENT_TIMEOUT_MS == 55000)

PumpUntil(predFn, timeoutMs := 2500) {
    deadline := A_TickCount + timeoutMs
    while (A_TickCount < deadline) {
        if (predFn())
            return true
        Sleep(15)
    }
    return predFn()
}

_TestWsOpen(port, path) {
    sock := DllCall("ws2_32\socket", "Int", 2, "Int", 1, "Int", 6, "Ptr")
    if (sock = -1)
        throw Error("socket failed")
    nonBlk := Buffer(4, 0)
    NumPut("UInt", 1, nonBlk, 0)
    DllCall("ws2_32\ioctlsocket", "Ptr", sock, "UInt", 0x8004667E, "Ptr", nonBlk.Ptr, "Int")

    addr := Buffer(16, 0)
    NumPut("UShort", 2, addr, 0)
    NumPut("UShort", ((port & 0xFF) << 8) | ((port >> 8) & 0xFF), addr, 2)
    NumPut("UInt", DllCall("ws2_32\inet_addr", "AStr", "127.0.0.1", "UInt"), addr, 4)
    DllCall("ws2_32\connect", "Ptr", sock, "Ptr", addr.Ptr, "Int", 16, "Int")

    req := "GET " path " HTTP/1.1`r`nHost: 127.0.0.1:" port "`r`nUpgrade: websocket`r`nConnection: Upgrade`r`nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==`r`nSec-WebSocket-Version: 13`r`n`r`n"
    reqLen := StrPut(req, "UTF-8") - 1
    reqBuf := Buffer(reqLen + 1, 0)
    StrPut(req, reqBuf, "UTF-8")
    sentOk := false
    deadline := A_TickCount + 2000
    while (A_TickCount < deadline) {
        rc := DllCall("ws2_32\send", "Ptr", sock, "Ptr", reqBuf.Ptr, "Int", reqLen, "Int", 0, "Int")
        if (rc == reqLen) {
            sentOk := true
            break
        }
        Sleep(15)
    }
    if (!sentOk) {
        DllCall("ws2_32\closesocket", "Ptr", sock)
        throw Error("WS upgrade send failed")
    }

    rx := Buffer(8192, 0)
    acc := Buffer(16384, 0)
    accLen := 0
    decodedFrames := ""
    hdrEnd := 0
    pos := 0
    deadline := A_TickCount + 2000
    while (A_TickCount < deadline) {
        n := DllCall("ws2_32\recv", "Ptr", sock, "Ptr", rx.Ptr, "Int", 8192, "Int", 0, "Int")
        if (n > 0) {
            if (accLen + n > acc.Size)
                acc.Size := accLen + n + 4096
            DllCall("ntdll\RtlMoveMemory", "Ptr", acc.Ptr + accLen, "Ptr", rx.Ptr, "UPtr", n)
            accLen += n

            if (!hdrEnd && accLen >= 4) {
                Loop (accLen - 3) {
                    i := A_Index - 1
                    if (NumGet(acc, i, "UChar") = 13 && NumGet(acc, i + 1, "UChar") = 10
                        && NumGet(acc, i + 2, "UChar") = 13 && NumGet(acc, i + 3, "UChar") = 10) {
                        hdrEnd := i + 4
                        pos := hdrEnd
                        break
                    }
                }
            }
            if (hdrEnd) {
                while (pos + 2 <= accLen) {
                    b1 := NumGet(acc, pos + 1, "UChar") & 0x7F
                    off := 2
                    pLen := b1
                    if (b1 = 126) {
                        if (pos + 4 > accLen)
                            break
                        pLen := (NumGet(acc, pos + 2, "UChar") << 8) | NumGet(acc, pos + 3, "UChar")
                        off := 4
                    }
                    if (pos + off + pLen > accLen)
                        break
                    if (pLen > 0)
                        decodedFrames .= StrGet(acc.Ptr + pos + off, pLen, "UTF-8") "`n"
                    pos += off + pLen
                }
                if (InStr(decodedFrames, '"type":"auth_ok"'))
                    break
            }
        }
        Sleep(15)
    }
    return { sock: sock, raw: decodedFrames }
}

_TestWsClose(wsObj) {
    if (IsObject(wsObj) && wsObj.sock != -1) {
        try DllCall("ws2_32\closesocket", "Ptr", wsObj.sock)
        wsObj.sock := -1
    }
}

ws1 := _TestWsOpen(b.boundTcpPort, "/ws?code=" cfg.SessionPairingCode "&deviceId=sb-sleep-test&deviceName=Board75&platform=Android")
PumpUntil(() => b.clients.Count >= 1 && InStr(ws1.raw, '"type":"auth_ok"'))

sleepCliKey := ""
sleepCli := ""
for k, cli in b.clients {
    if (cli.deviceId = "sb-sleep-test") {
        sleepCliKey := k
        sleepCli := cli
        break
    }
}
Assert("Authenticated Bridge WS client registered for dead-client reap test", IsObject(sleepCli) && sleepCli.authenticated && InStr(ws1.raw, '"type":"auth_ok"'))

prevBcCount := DiagnosticLogger.Breadcrumbs.Length
sleepCli.lastRxTick := A_TickCount - (HostBridgeConstants.DEAD_CLIENT_TIMEOUT_MS + 1500)
b._OnMaintenanceTick()
hasReapBc := false
if (DiagnosticLogger.Breadcrumbs.Length > prevBcCount) {
    Loop (DiagnosticLogger.Breadcrumbs.Length - prevBcCount) {
        bc := DiagnosticLogger.Breadcrumbs[prevBcCount + A_Index]
        if (bc.category = "Bridge" && bc.action = "ReapDeadClient") {
            hasReapBc := true
            break
        }
    }
}
Assert("_OnMaintenanceTick reaps silent client > 55s, marks disconnected, and records ReapDeadClient breadcrumb",
    !b.clients.Has(sleepCliKey) && b.pairedDevices.Has("sb-sleep-test") && !b.pairedDevices["sb-sleep-test"].connected && hasReapBc)
_TestWsClose(ws1)

; Duplicate socket eviction on _TryAuthenticateWsClient
wsOld := _TestWsOpen(b.boundTcpPort, "/ws?code=" cfg.SessionPairingCode "&deviceId=sb-evict-1&deviceName=BoardEvict&platform=Android")
PumpUntil(() => InStr(wsOld.raw, '"type":"auth_ok"') && b.pairedDevices.Has("sb-evict-1"))
oldSockKey := ""
for k, cli in b.clients {
    if (cli.deviceId = "sb-evict-1") {
        oldSockKey := k
        break
    }
}
savedEvictTok := b.pairedDevices["sb-evict-1"].token
Assert("First socket for sb-evict-1 issued persisted sessionToken", oldSockKey != "" && savedEvictTok != "")

wsNew := _TestWsOpen(b.boundTcpPort, "/ws?token=" savedEvictTok "&deviceId=sb-evict-1&deviceName=BoardEvict&platform=Android")
PumpUntil(() => InStr(wsNew.raw, '"type":"auth_ok"') && !b.clients.Has(oldSockKey))
Assert("_TryAuthenticateWsClient evicts older socket for same deviceId while keeping new socket live",
    oldSockKey != "" && !b.clients.Has(oldSockKey) && b.GetConnectedClientCount() == 1 && b.pairedDevices["sb-evict-1"].connected)
_TestWsClose(wsOld)
_TestWsClose(wsNew)

; Restart HostCompanionBridge -> verify re-bind via persisted token AND via saved sessionPairingCode (with stale token)
StopHostCompanionBridge()
cfgRestart := Config(testIni)
bRestart := StartHostCompanionBridge(cfgRestart, st, 0, 0, 0)
Assert("Restarted HostCompanionBridge loads persisted sessionToken from [HostBridgePairedDevices]",
    bRestart.validTokens.Has(savedEvictTok) && bRestart.pairedDevices.Has("sb-evict-1"))

wsTok := _TestWsOpen(bRestart.boundTcpPort, "/ws?token=" savedEvictTok "&deviceId=sb-evict-1")
Assert("Re-bind after Host restart succeeds with persisted sessionToken",
    InStr(wsTok.raw, '"type":"auth_ok"'))
_TestWsClose(wsTok)

wsCode := _TestWsOpen(bRestart.boundTcpPort, "/ws?token=stale_token_xyz&code=" cfgRestart.SessionPairingCode "&deviceId=sb-rebind-code&deviceName=BoardCodeWake")
Assert("Re-bind after Host restart accepts saved sessionPairingCode when token is stale",
    InStr(wsCode.raw, '"type":"auth_ok"') && bRestart.pairedDevices.Has("sb-rebind-code") && bRestart.pairedDevices["sb-rebind-code"].token != "")
_TestWsClose(wsCode)

StopHostCompanionBridge()
Assert("StopHostCompanionBridge shuts down cleanly", !IsObject(g_HostCompanionBridge) && !GetHostBridgeStatusSummary().running)

if FileExist(testIni)
    FileDelete(testIni)
if FileExist(testIni ".bak")
    FileDelete(testIni ".bak")

report := "=== PRESENTER SYNC HOST BRIDGE UNIT REPORT ===`nPassed: " PassCount " | Failed: " FailCount "`n`n"
for r in results
    report .= r "`n"

logFile := A_ScriptDir "\host_bridge_results.log"
if FileExist(logFile)
    FileDelete(logFile)
FileAppend(report, logFile, "UTF-8")
try FileAppend(report, "*")
ExitApp(FailCount > 0 ? 1 : 0)
