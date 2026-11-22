; ==============================================================================
; Test Suite: test_v772_remote_refactor_audit.ahk
; Description: Verifies v7.7.2 Windows Remote refactor invariants, socket teardown,
;              timer lifecycle cleanup, telemetry reset, and WinSock/WinHttp safety.
; ==============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
SetTimer(() => ExitApp(124), -45000)
OnError((err, mode) => (FileAppend("UNHANDLED_ERR: " err.Message " (" err.What ") at " err.File ":" err.Line "`n", "*"), ExitApp(1)))

#Include "%A_LineFile%\..\..\Lib\WebSocket.ahk"
#Include "%A_LineFile%\..\..\Lib\UIA.ahk"
#Include "%A_LineFile%\..\..\Lib\Crypto.ahk"
#Include "%A_LineFile%\..\..\Lib\RemoteBridgeClient.ahk"
#Include "%A_LineFile%\..\..\Lib\Gdip.ahk"
#Include "%A_LineFile%\..\..\Lib\OBS_Network.ahk"
#Include "%A_LineFile%\..\..\Lib\GUI_Config.ahk"

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

class MockCloseableWs {
    _psClosed := false
    shutdownCalls := 0
    shutdown() {
        this.shutdownCalls += 1
    }
}

class MockNotifiableState {
    activeScene := "Camera A"
    currentSceneName := "Camera A"
    previousProgramScene := ""
    notifyCalls := 0
    NotifyTrayStatus() {
        this.notifyCalls += 1
    }
}

; ==============================================================================
; 1. CloseRemoteWebSocket & CloseRemoteSocketRef
; ==============================================================================
CloseRemoteWebSocket("", false)
CloseRemoteWebSocket({ other: 1 }, false)
stStale := { obsWs: "stale-string" }
CloseRemoteWebSocket(stStale, false)
AssertTrue(stStale.obsWs == "", "CloseRemoteWebSocket clears non-object stale obsWs value cleanly")

CloseRemoteSocketRef("", "", false)
AssertTrue(true, "CloseRemoteSocketRef is null-safe on empty arguments")

wsImm := MockCloseableWs()
stImm := { obsWs: wsImm }
CloseRemoteWebSocket(stImm, false)
AssertTrue(stImm.obsWs == "" && wsImm._psClosed == true && wsImm.shutdownCalls == 1, "CloseRemoteWebSocket immediate marks _psClosed, clears state.obsWs, and invokes shutdown()")

wsOther := MockCloseableWs()
wsActive := MockCloseableWs()
stKeep := { obsWs: wsActive }
CloseRemoteSocketRef(wsOther, stKeep, false)
AssertTrue(stKeep.obsWs == wsActive && wsOther._psClosed == true && wsOther.shutdownCalls == 1 && wsActive.shutdownCalls == 0, "CloseRemoteSocketRef closes non-matching ws without clobbering active state.obsWs")

wsDef := MockCloseableWs()
stDef := { obsWs: wsDef }
CloseRemoteWebSocket(stDef, true)
AssertTrue(stDef.obsWs == "" && wsDef._psClosed == true, "CloseRemoteWebSocket deferred marks _psClosed and clears state.obsWs immediately")
Sleep(140)
AssertTrue(wsDef.shutdownCalls == 1, "CloseRemoteWebSocket deferred completes ws.shutdown() asynchronously")

; ==============================================================================
; 2. IsRemoteDirectObsReady
; ==============================================================================
AssertTrue(!IsRemoteDirectObsReady({}, ""), "IsRemoteDirectObsReady returns false on non-object state")
AssertTrue(!IsRemoteDirectObsReady({ NetworkMode: "LAN" }, { usingDirectObsFallback: true, obsConnected: false, obsWs: MockCloseableWs() }), "IsRemoteDirectObsReady returns false when disconnected")
AssertTrue(!IsRemoteDirectObsReady({ NetworkMode: "LAN" }, { usingDirectObsFallback: true, obsConnected: true, obsWs: "" }), "IsRemoteDirectObsReady returns false when obsWs is empty")
AssertTrue(!IsRemoteDirectObsReady({ NetworkMode: "LAN" }, { usingBridge: true, usingDirectObsFallback: false, obsConnected: true, obsWs: MockCloseableWs() }), "IsRemoteDirectObsReady returns false while using Host Bridge")
AssertTrue(!IsRemoteDirectObsReady({ NetworkMode: "Internet" }, { usingBridge: false, usingRelayFallback: false, usingDirectObsFallback: false, obsConnected: true, obsWs: MockCloseableWs() }), "IsRemoteDirectObsReady returns false in Internet Relay mode")
AssertTrue(IsRemoteDirectObsReady({ NetworkMode: "LAN" }, { usingBridge: false, usingRelayFallback: false, usingDirectObsFallback: true, obsConnected: true, obsWs: MockCloseableWs() }), "IsRemoteDirectObsReady returns true when direct OBS fallback is connected with live socket")
AssertTrue(IsRemoteDirectObsReady({ NetworkMode: "LAN" }, { usingBridge: false, usingRelayFallback: false, usingDirectObsFallback: false, obsConnected: true, obsWs: MockCloseableWs() }), "IsRemoteDirectObsReady returns true when direct OBS LAN channel is active")

; ==============================================================================
; 3. CommitRemoteSceneChange
; ==============================================================================
stSc := MockNotifiableState()
CommitRemoteSceneChange(stSc, "   ", true)
AssertTrue(stSc.activeScene == "Camera A" && stSc.previousProgramScene == "" && stSc.notifyCalls == 0, "CommitRemoteSceneChange ignores blank scene names")

CommitRemoteSceneChange(stSc, "Slides", true)
AssertTrue(stSc.activeScene == "Slides" && stSc.currentSceneName == "Slides" && stSc.previousProgramScene == "Camera A" && stSc.notifyCalls == 1, "CommitRemoteSceneChange updates activeScene, currentSceneName, previousProgramScene, and notifies tray")

CommitRemoteSceneChange(stSc, "Slides", false)
AssertTrue(stSc.previousProgramScene == "Camera A" && stSc.notifyCalls == 1, "CommitRemoteSceneChange preserves previousProgramScene on same-scene re-commit and respects notify=false")

stInit := MockNotifiableState()
stInit.activeScene := "Scene"
stInit.currentSceneName := "Scene"
CommitRemoteSceneChange(stInit, "Intro", true)
AssertTrue(stInit.activeScene == "Intro" && stInit.previousProgramScene == "", "CommitRemoteSceneChange does not record placeholder 'Scene' as previousProgramScene")

; ==============================================================================
; 4. ResetRemoteConnectionTelemetry
; ==============================================================================
ResetRemoteConnectionTelemetry("", true)
stTel := {
    obsConnected: true,
    usingBridge: true,
    usingDirectObsFallback: true,
    usingRelayFallback: true,
    activeHost: "192.168.1.10:4456",
    recState: 1,
    recSeconds: 95,
    streamDropWarn: true,
    voiceWhileMuted: true,
    isStandby: true,
    timerState: "running",
    scenes: ["Cam", "Slides"]
}
ResetRemoteConnectionTelemetry(stTel, false)
AssertTrue(!stTel.obsConnected && !stTel.usingBridge && !stTel.usingDirectObsFallback && stTel.usingRelayFallback == true
    && stTel.activeHost == "" && stTel.recState == 0 && stTel.recSeconds == 0
    && !stTel.streamDropWarn && !stTel.voiceWhileMuted && !stTel.isStandby
    && stTel.timerState == "stopped" && stTel.scenes.Length == 0,
    "ResetRemoteConnectionTelemetry clears session telemetry while preserving usingRelayFallback when resetFallback=false")

ResetRemoteConnectionTelemetry(stTel, true)
AssertTrue(!stTel.usingRelayFallback, "ResetRemoteConnectionTelemetry clears usingRelayFallback when resetFallback=true")

; ==============================================================================
; 5. StopRemoteSessionTimers & StopAllRemoteTimers
; ==============================================================================
AssertTrue(StopRemoteSessionTimers("", true) == 0 && StopAllRemoteTimers("") == 0, "Timer stop helpers are null-safe")

timerHits := Map()
MakeProbeTimer(name) {
    return () => (timerHits[name] := (timerHits.Has(name) ? timerHits[name] + 1 : 1))
}

stSess := {
    reconnectTimerFn: MakeProbeTimer("reconnect"),
    heartbeatTimerFn: MakeProbeTimer("heartbeat"),
    lanRepromoteTimerFn: MakeProbeTimer("lanRepromote"),
    presenterTickFn: MakeProbeTimer("presenter"),
    recTickFn: MakeProbeTimer("rec"),
    breathTimerFn: MakeProbeTimer("breath"),
    _pongWatchdogTimerFn: MakeProbeTimer("pong"),
    _bridgeHandshakeTimerFn: MakeProbeTimer("handshake")
}
for _, k in ["reconnectTimerFn", "heartbeatTimerFn", "lanRepromoteTimerFn", "presenterTickFn", "recTickFn", "breathTimerFn", "_pongWatchdogTimerFn", "_bridgeHandshakeTimerFn"]
    SetTimer(stSess.%k%, 80)

stoppedNoRec := StopRemoteSessionTimers(stSess, false)
AssertTrue(stoppedNoRec == 7 && stSess._pongWatchdogTimerFn == "" && stSess._bridgeHandshakeTimerFn == "", "StopRemoteSessionTimers(false) stops 7 session/watchdog timers and clears watchdog refs")
stoppedWithRec := StopRemoteSessionTimers(stSess, true)
AssertTrue(stoppedWithRec == 6, "StopRemoteSessionTimers(true) stops reconnect + 5 persistent session timer bindings")
Sleep(150)
AssertTrue(timerHits.Count == 0, "Zero session timer callbacks fired after StopRemoteSessionTimers(true)")

timerHits.Clear()
stAll := {
    dragTimerFn: MakeProbeTimer("drag"),
    breathTimerFn: MakeProbeTimer("breath"),
    autoDodgeTimerFn: MakeProbeTimer("autoDodge"),
    idleDimTimerFn: MakeProbeTimer("idleDim"),
    reconnectTimerFn: MakeProbeTimer("reconnect"),
    heartbeatTimerFn: MakeProbeTimer("heartbeat"),
    lanRepromoteTimerFn: MakeProbeTimer("lanRepromote"),
    presenterTickFn: MakeProbeTimer("presenter"),
    recTickFn: MakeProbeTimer("rec"),
    rebuildTrayFn: MakeProbeTimer("rebuildTray"),
    _pongWatchdogTimerFn: MakeProbeTimer("pong"),
    _bridgeHandshakeTimerFn: MakeProbeTimer("handshake")
}
for _, k in ["dragTimerFn", "breathTimerFn", "autoDodgeTimerFn", "idleDimTimerFn", "reconnectTimerFn", "heartbeatTimerFn", "lanRepromoteTimerFn", "presenterTickFn", "recTickFn", "rebuildTrayFn", "_pongWatchdogTimerFn", "_bridgeHandshakeTimerFn"]
    SetTimer(stAll.%k%, 70)

stoppedAll := StopAllRemoteTimers(stAll)
AssertTrue(stoppedAll == 12 && stAll._pongWatchdogTimerFn == "" && stAll._bridgeHandshakeTimerFn == "", "StopAllRemoteTimers cancels all 12 remote timers and clears watchdog properties")
Sleep(150)
AssertTrue(timerHits.Count == 0, "Zero callbacks fired after StopAllRemoteTimers")

; ==============================================================================
; 6. Source Invariants (WinSock closesocket/WSACleanup, WinHttp finally, ShutdownRemoteApp)
; ==============================================================================
rbcSrc := FileRead(A_ScriptDir "\..\Lib\RemoteBridgeClient.ahk", "UTF-8")
remoteSrc := FileRead(A_ScriptDir "\..\PresenterSync_Remote.ahk", "UTF-8")

AssertTrue(RegExMatch(rbcSrc, "s)_RBC_OpenBroadcastUdpSocket\(\)\s*\{.*?WSAStartup.*?WSACleanup.*?_RBC_CloseUdpSocket\(sock\)"),
    "RemoteBridgeClient _RBC_OpenBroadcastUdpSocket cleans up WSAStartup/socket on error paths")
AssertTrue(RegExMatch(rbcSrc, "s)_RBC_CloseUdpSocket\(sock\)\s*\{.*?ws2_32\\closesocket.*?ws2_32\\WSACleanup"),
    "RemoteBridgeClient _RBC_CloseUdpSocket balances closesocket + WSACleanup")
AssertTrue(RegExMatch(rbcSrc, "s)DiscoverHostBridgeUdp\(.*?finally\s*\{\s*_RBC_CloseUdpSocket\(sock\)"),
    "DiscoverHostBridgeUdp closes UDP socket & WSA in finally")
AssertTrue(RegExMatch(rbcSrc, "s)DiscoverPublicHostsUdp\(.*?finally\s*\{\s*_RBC_CloseUdpSocket\(sock\)"),
    "DiscoverPublicHostsUdp closes UDP socket & WSA in finally")
AssertTrue(RegExMatch(rbcSrc, "s)ProbeRemoteTcpPort\(.*?finally\s*\{.*?ws2_32\\closesocket.*?ws2_32\\WSACleanup"),
    "ProbeRemoteTcpPort closes TCP socket & balances WSACleanup in finally")
AssertTrue(RegExMatch(rbcSrc, 's)ProbeHostBridgeHealth\(.*?finally\s*\{\s*whr\s*:=\s*""'),
    "ProbeHostBridgeHealth clears WinHttp COM ref in finally")
AssertTrue(RegExMatch(rbcSrc, 's)HttpPostBridgePair\(.*?finally\s*\{\s*whr\s*:=\s*""'),
    "HttpPostBridgePair clears WinHttp COM ref in finally")

AssertTrue(RegExMatch(remoteSrc, "s)StopAllTimers\(\)\s*\{\s*return\s+StopAllRemoteTimers\(this\)"),
    "RemoteState.StopAllTimers delegates to StopAllRemoteTimers(this)")
AssertTrue(RegExMatch(remoteSrc, "s)ShutdownRemoteApp\(\*\)\s*\{.*?AppState\.StopAllTimers\(\).*?CloseRemoteWebSocket\(AppState,\s*false\).*?ReleaseRemoteInstanceMutex\(g_RemoteMutex\).*?Theme\.Shutdown\(\).*?Gdip\.Shutdown\(\)"),
    "ShutdownRemoteApp stops all timers, closes WebSocket, releases mutex, and shuts down Theme/Gdip")
AssertTrue(InStr(remoteSrc, "RegisterSelfUpdateBeforeRelaunch(ShutdownRemoteApp)") && InStr(remoteSrc, "OnExit(ShutdownRemoteApp)"),
    "ShutdownRemoteApp is wired to both RegisterSelfUpdateBeforeRelaunch and OnExit")
AssertTrue(!RegExMatch(remoteSrc, "(?m)^\s*pairRes\s*:="),
    "PresenterSync_Remote.ahk has zero local-shadows-global pairRes assignments")

try FileAppend("PASS=" passed " FAIL=" failed "`n", "*")
ExitApp(failed > 0 ? 1 : 0)
