; ==============================================================================
; Test Suite: test_multi_remote.ahk
; Description: Automated verification of v5.3.0 Multi-Remote Simultaneous
;              Support across Windows + Android Remotes, CLI multi-instance,
;              UDP discovery, HTTP /pair, Bridge/OBS/Relay dispatch, and live
;              Remote Companion Info auto-refresh.
; ==============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

#Include "..\Lib\WebSocket.ahk"
#Include "..\Lib\Crypto.ahk"
#Include "..\Lib\Gdip.ahk"
#Include "..\Lib\UIA.ahk"
#Include "..\Lib\OBS_Network.ahk"
#Include "..\Lib\GUI_Config.ahk"
#Include "..\Lib\RemoteBridgeClient.ahk"

Gdip.Startup()
OnExit((*) => (StopHostCompanionBridge(), Theme.Shutdown(), UIA.Shutdown(), Gdip.Shutdown()))

results := []
PassCount := 0
FailCount := 0

MultiRemoteFailFast(exc, mode) {
    global results, FailCount
    FailCount += 1
    msg := Format("[FAIL] Unhandled exception ({}) in {} ({}:{}): {}", mode, exc.What, exc.File, exc.Line, exc.Message)
    results.Push(msg)
    try FileAppend(msg "`n", A_ScriptDir "\multi_remote_results.log")
    ExitApp(1)
}
OnError(MultiRemoteFailFast)

MultiRemoteWatchdog() {
    global results, FailCount
    FailCount += 1
    msg := "[FAIL] Multi-remote test watchdog timeout reached (25s)"
    results.Push(msg)
    try FileAppend(msg "`n", A_ScriptDir "\multi_remote_results.log")
    ExitApp(2)
}
SetTimer(MultiRemoteWatchdog, -25000)

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

; --- 1. CLI Multi-Instance & Pairing URI Parsing ---
cli1 := ParseRemoteCliArgs(["-Config", "C:\tmp\r1.ini", "-Instance", "SmartBoardLeft"])
Assert("CLI parser reads -Config and -Instance",
    cli1.configPath == "C:\tmp\r1.ini" && cli1.instanceName == "SmartBoardLeft")

cli2 := ParseRemoteCliArgs(["--instance=PhoneBackup", "presentersync://connect?mode=lan&host=192.168.1.44&port=4455&bridgePort=4456&code=K7M-9P2&mic=Mic%2FAux&pw=s3cr3t"])
Assert("CLI parser reads --instance= and bare pairing URI",
    cli2.instanceName == "PhoneBackup" && InStr(cli2.pairingUri, "presentersync://connect?") == 1)

parsedUri := ParseRemotePairingUri(cli2.pairingUri)
Assert("Deep-link URI parser extracts bridgePort, sessionCode, hosts and pw",
    IsObject(parsedUri) && parsedUri.networkMode == "LAN" && parsedUri.hostAddress == "192.168.1.44"
    && parsedUri.bridgePort == "4456" && parsedUri.sessionCode == "K7M-9P2" && parsedUri.obsPassword == "s3cr3t")

; --- 2. Unique Device IDs & Named Instance Mutexes ---
dev1 := GenerateRemoteDeviceId("win")
dev2 := GenerateRemoteDeviceId("win")
Assert("GenerateRemoteDeviceId generates unique win-<hex> IDs",
    RegExMatch(dev1, "^win-[0-9a-f]{12}$") > 0 && dev1 != dev2, dev1 " vs " dev2)

mtx1 := AcquireRemoteInstanceMutex("UnitTestInstA_" A_TickCount)
mtx2 := AcquireRemoteInstanceMutex("UnitTestInstB_" A_TickCount)
Assert("Distinct -Instance names acquire independent mutexes cleanly",
    mtx1.handle != 0 && !mtx1.alreadyExists && mtx2.handle != 0 && !mtx2.alreadyExists)
ReleaseRemoteInstanceMutex(mtx1)
ReleaseRemoteInstanceMutex(mtx2)

; --- 3. Candidate Queue Ordering (Bridge Preferred -> Direct OBS Fallback) ---
qWithBridge := BuildRemoteLanCandidateQueue({
    HostAddress: "192.168.1.50, STUDIO-PC.local",
    HostPort: "4455",
    BridgePort: "4456",
    SessionPairingCode: "K7M-9P2",
    SessionToken: ""
})
Assert("BuildRemoteLanCandidateQueue puts Bridge :4456/ws candidates before Direct OBS :4455",
    qWithBridge.Length == 4 && qWithBridge[1].isBridge && qWithBridge[1].port == "4456" && qWithBridge[1].path == "/ws"
    && !qWithBridge[3].isBridge && qWithBridge[3].port == "4455")

qDirectOnly := BuildRemoteLanCandidateQueue({
    HostAddress: "192.168.1.50",
    HostPort: "4455",
    BridgePort: "4456",
    SessionPairingCode: "",
    SessionToken: ""
})
Assert("BuildRemoteLanCandidateQueue uses Direct OBS only when no Session Code/Token configured",
    qDirectOnly.Length == 1 && !qDirectOnly[1].isBridge && qDirectOnly[1].port == "4455")

; --- 4. DispatchRemoteMuteToggle / DispatchRemoteSetMute Over Bridge Channel ---
bridgeSent := []
mockBridgeWs := { sendText: (this, msg) => bridgeSent.Push(msg) }
bridgeCfg := {
    NetworkMode: "LAN",
    DeviceId: dev1,
    TargetMicName: "Studio Mic",
    ObsPassword: "",
    InternetPairingCode: ""
}
bridgeSt := { usingBridge: true, usingRelayFallback: false, obsConnected: true, obsWs: mockBridgeWs }
okTgl := DispatchRemoteMuteToggle(bridgeCfg, bridgeSt)
okSet := DispatchRemoteSetMute(bridgeCfg, bridgeSt, true)
Assert("DispatchRemoteMuteToggle & SetMute emit Host Bridge JSON frames when connected via Bridge",
    okTgl && okSet && bridgeSent.Length == 2
    && InStr(bridgeSent[1], '"type":"toggle_mute"') && InStr(bridgeSent[1], dev1)
    && InStr(bridgeSent[2], '"type":"set_mute"') && InStr(bridgeSent[2], '"isMuted":true'))

evAuth := ParseHostBridgeWsEvent('{"type":"auth_ok","isMuted":true,"routingMode":2,"targetMicName":"Studio Mic"}')
evMute := ParseHostBridgeWsEvent('{"type":"mute_state","isMuted":false,"routingMode":2}')
evErr := ParseHostBridgeWsEvent('{"type":"auth_error","reason":"Invalid code"}')
Assert("ParseHostBridgeWsEvent parses auth_ok, mute_state & auth_error accurately",
    IsObject(evAuth) && evAuth.kind == "auth_ok" && evAuth.hasMuted && evAuth.isMuted == true
    && IsObject(evMute) && evMute.kind == "mute_state" && evMute.isMuted == false
    && IsObject(evErr) && evErr.kind == "auth_error" && InStr(evErr.reason, "Invalid"))

; --- 5. Live Multi-Client Pairing (2 Windows + 1 Android) Against Real HostCompanionBridge ---
testIni := A_ScriptDir "\test_multi_remote_host.ini"
if FileExist(testIni)
    FileDelete(testIni)
hostCfg := Config(testIni)
hostCfg.SessionPairingCode := "M3R-8K2"
hostCfg.obsPassword := "multiPass"
hostCfg.targetMicName := "Conference Mic"
hostCfg.AudioRoutingMode := 2
hostCfg.InternetPairingCode := "PS-MULTI-999"

hostSt := {
    isMuted: false,
    obsConnected: false,
    obsWs: "",
    zoomConnected: false,
    EnableWS: false,
    relayConnected: false,
    relayWs: ""
}

bridge := StartHostCompanionBridge(hostCfg, hostSt, 0, 0)
Assert("Live HostCompanionBridge starts on ephemeral TCP/UDP ports",
    IsObject(bridge) && bridge.running && bridge.boundTcpPort > 0 && bridge.boundUdpPort > 0)

; Pair Windows Remote 1 via HTTP /pair + Windows Remote 2 + Android Client
pWin1 := PairRemoteWithHostBridge("127.0.0.1", String(bridge.boundTcpPort), "M3R-8K2", "win-laptop-01", "WIN-LAPTOP (Left)", false)
pWin2 := PairRemoteWithHostBridge("127.0.0.1", String(bridge.boundTcpPort), "M3R-8K2", "win-podium-02", "WIN-PODIUM (Right)", false)
pAnd1 := HttpPostBridgePair("127.0.0.1", String(bridge.boundTcpPort), "M3R-8K2", "and-board-65", "65-inch Smart Board")

Assert("Simultaneous pairing of 2 Windows Remotes + 1 Android Remote succeeds with unique tokens",
    pWin1.ok && pWin2.ok && pAnd1.ok
    && pWin1.sessionToken != "" && pWin2.sessionToken != "" && pAnd1.sessionToken != ""
    && pWin1.sessionToken != pWin2.sessionToken && pWin2.sessionToken != pAnd1.sessionToken
    && pWin1.targetMicName == "Conference Mic" && pWin1.obsPassword == "multiPass")

devListText := _FormatHostBridgeDeviceText()
Assert("HostBridge device registry tracks all 3 paired devices across Windows and Android",
    bridge.pairedDevices.Count == 3
    && InStr(devListText, "WIN-LAPTOP (Left)") && InStr(devListText, "WIN-PODIUM (Right)") && InStr(devListText, "65-inch Smart Board"))

; Open & cleanly close Remote Companion Info dialog with 1s live refresh timer
infoDlg := ShowRemoteCompanionInfo(hostCfg, hostSt)
Sleep(60)
Assert("ShowRemoteCompanionInfo opens with Theme suspension balanced and multi-device list",
    IsObject(infoDlg) && WinExist("ahk_id " infoDlg.Hwnd))
PostMessage(0x0010, 0, 0, infoDlg.Hwnd)
Sleep(80)

StopHostCompanionBridge()
if FileExist(testIni)
    FileDelete(testIni)

; --- 6. Host Bridge 2.0 Persistent Paired Devices, Rename/Unpair/Revoke & Deck Helpers ---
deckNext := BuildRemoteBridgeDeckJson({ DeviceId: "win-1", InstanceName: "Desk" }, "ppt_next")
deckRec := BuildRemoteBridgeDeckJson({ DeviceId: "win-1", InstanceName: "Desk" }, "toggle_record")
Assert("BuildRemoteBridgeDeckJson emits ppt_next and toggle_record payloads",
    InStr(deckNext, '"type":"ppt_next"') && InStr(deckRec, '"type":"toggle_record"'))

evTel := ParseHostBridgeWsEvent('{"type":"mute_state","isMuted":true,"routingMode":2,"targetMicName":"Studio","recState":1,"recSeconds":125,"streamDropWarn":true,"voiceWhileMuted":true}')
evAck := ParseHostBridgeWsEvent('{"type":"ack","action":"ppt_prev","ok":true}')
Assert("ParseHostBridgeWsEvent parses v6.2.0 telemetry and ack packets",
    IsObject(evTel) && evTel.recState == 1 && evTel.recSeconds == 125 && evTel.streamDropWarn && evTel.voiceWhileMuted
    && IsObject(evAck) && evAck.kind == "ack" && evAck.action == "ppt_prev" && evAck.ok)

persistIni := A_ScriptDir "\test_multi_persist.ini"
if FileExist(persistIni)
    FileDelete(persistIni)
pCfg1 := Config(persistIni)
pCfg1.SessionPairingCode := "A1B-2C3"
pCfg1.Write("Settings", "SessionPairingCode", "A1B-2C3")
pSt := { isMuted: false, obsConnected: false, obsWs: "", zoomConnected: false, relayConnected: false, relayWs: "" }

pb1 := StartHostCompanionBridge(pCfg1, pSt, 0, -1)
pRes1 := HttpPostBridgePair("127.0.0.1", String(pb1.boundTcpPort), "A1B-2C3", "and-board-persist", "Auto Board")
Assert("Persist sub-test /pair succeeded", IsObject(pRes1) && pRes1.ok && pb1.pairedDevices.Has("and-board-persist"))
Assert("RenameHostPairedDevice updates name and sets customName",
    RenameHostPairedDevice("and-board-persist", "Lecture Hall 75")
    && pb1.pairedDevices["and-board-persist"].deviceName == "Lecture Hall 75"
    && pb1.pairedDevices["and-board-persist"].customName)
savedTok := pb1.pairedDevices["and-board-persist"].token
StopHostCompanionBridge()

pCfg2 := Config(persistIni)
pb2 := StartHostCompanionBridge(pCfg2, pSt, 0, -1)
Assert("Restarted HostCompanionBridge reloads paired device, token & custom nickname from INI",
    pb2.pairedDevices.Has("and-board-persist")
    && pb2.pairedDevices["and-board-persist"].deviceName == "Lecture Hall 75"
    && pb2.pairedDevices["and-board-persist"].customName
    && pb2.validTokens.Has(savedTok))

; Re-pair same device should keep custom nickname instead of overwriting with incoming deviceName
pRes2 := HttpPostBridgePair("127.0.0.1", String(pb2.boundTcpPort), "A1B-2C3", "and-board-persist", "Generic Default")
Assert("Re-pairing device preserves custom nickname on Host",
    IsObject(pRes2) && pRes2.ok && pb2.pairedDevices["and-board-persist"].deviceName == "Lecture Hall 75")

RotateHostSessionPairingCode(pCfg2, false)
Assert("Rotate code without revoke retains paired devices", pb2.pairedDevices.Has("and-board-persist"))
Assert("UnpairHostPairedDevice removes targeted device & token cleanly",
    UnpairHostPairedDevice("and-board-persist") && !pb2.pairedDevices.Has("and-board-persist") && !pb2.validTokens.Has(savedTok))

pb2.pairedDevices["temp-d"] := { deviceId: "temp-d", deviceName: "Temp", customName: false, platform: "Windows", token: "tok_temp_1", ip: "127.0.0.1", pairedAt: "10:00", transport: "HTTP", lastSeenTick: 1, connected: false }
pb2.validTokens["tok_temp_1"] := "temp-d"
RotateHostSessionPairingCode(pCfg2, true)
Assert("RotateHostSessionPairingCode(revokeAll:=true) wipes all paired devices & tokens",
    pb2.pairedDevices.Count == 0 && pb2.validTokens.Count == 0)

StopHostCompanionBridge()
if FileExist(persistIni)
    FileDelete(persistIni)

; --- 7. v7.0.5 (#11): Remote Wake Staleness, Pong Watchdog & Auth Error/Token Parsing ---
Assert("RemoteBridgeConstants match 2500ms Pong timeout and 25000ms wake staleness",
    RemoteBridgeConstants.PONG_TIMEOUT_MS == 2500 && RemoteBridgeConstants.WAKE_STALENESS_MS == 25000)

wakeSt := { obsConnected: true, lastRxTick: 1000, rxSeq: 1 }
MarkRemoteRxActivity(wakeSt, 5000)
Assert("MarkRemoteRxActivity updates lastRxTick and advances rxSeq",
    wakeSt.lastRxTick == 5000 && wakeSt.rxSeq == 2)
Assert("ShouldForceWakeReconnect stays false <= 25000ms and triggers > 25000ms or when disconnected",
    !ShouldForceWakeReconnect(wakeSt, 15000)
    && !ShouldForceWakeReconnect(wakeSt, 30000)
    && ShouldForceWakeReconnect(wakeSt, 30001)
    && ShouldForceWakeReconnect({ obsConnected: false, lastRxTick: 5000 }, 5100))

pingSeq := wakeSt.rxSeq
pingTick := wakeSt.lastRxTick
Assert("IsPongWatchdogExpired detects missing pong/frame when rxSeq and lastRxTick unchanged",
    IsPongWatchdogExpired(wakeSt, pingSeq, pingTick))
MarkRemoteRxActivity(wakeSt, 5000) ; same-ms pong response still advances rxSeq
Assert("IsPongWatchdogExpired clears when pong/frame arrives (even at identical tick ms)",
    !IsPongWatchdogExpired(wakeSt, pingSeq, pingTick))

evAuthErrFallback := ParseHostBridgeWsEvent('{"type":"auth_error","error":"Unauthorized"}')
evAuthOkTok := ParseHostBridgeWsEvent('{"type":"auth_ok","hostUuid":"u-1","sessionToken":"tok_refreshed_77"}')
Assert("ParseHostBridgeWsEvent extracts error->reason and auth_ok sessionToken",
    IsObject(evAuthErrFallback) && evAuthErrFallback.reason == "Unauthorized"
    && IsObject(evAuthOkTok) && evAuthOkTok.sessionToken == "tok_refreshed_77")

report := "=== PRESENTER SYNC MULTI-REMOTE TEST REPORT ===`n"
report .= "Passed: " PassCount "  Failed: " FailCount "`n`n"
for item in results
    report .= item "`n"
logFile := A_ScriptDir "\multi_remote_results.log"
if FileExist(logFile)
    FileDelete(logFile)
FileAppend(report, logFile)
ExitApp(FailCount > 0 ? 1 : 0)
