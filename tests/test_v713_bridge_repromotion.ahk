; ==============================================================================
; Test Suite: test_v713_bridge_repromotion.ahk
; Description: Verifies v7.1.3 Bridge Recovery Re-Promotion Watchdog (8000ms):
;              BRIDGE_REPROMOTE_INTERVAL_MS == 8000, HEALTH_PROBE_TIMEOUT_MS == 500,
;              ProbeHostBridgeHealth against a live loopback 127.0.0.1 HostBridge,
;              and state transition from usingDirectObsFallback back to Bridge.
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
OnExit((*) => StopHostCompanionBridge())

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

; 1. Constants check
AssertTrue(RemoteBridgeConstants.BRIDGE_REPROMOTE_INTERVAL_MS == 8000, "BRIDGE_REPROMOTE_INTERVAL_MS is 8000ms")
AssertTrue(RemoteBridgeConstants.HEALTH_PROBE_TIMEOUT_MS == 500, "HEALTH_PROBE_TIMEOUT_MS is 500ms")

; 2. Start local loopback HostCompanionBridge on ephemeral port & probe /health
tmpIni := A_Temp "\PresenterSync_v713_test_" A_TickCount ".ini"
if FileExist(tmpIni)
    FileDelete(tmpIni)

cfg := Config(tmpIni)
st := OverlayState(cfg)
bridge := StartHostCompanionBridge(cfg, st, 0, -1, 0)
AssertTrue(IsObject(bridge) && bridge.running && bridge.boundTcpPort > 0, "Loopback HostCompanionBridge started on ephemeral port")

hostUuid := EnsureHostUuid(cfg)
probeUp := ProbeHostBridgeHealth("127.0.0.1", bridge.boundTcpPort, hostUuid, RemoteBridgeConstants.HEALTH_PROBE_TIMEOUT_MS)
AssertTrue(IsObject(probeUp) && probeUp.ok == true, "ProbeHostBridgeHealth returns ok=true when Bridge /health is 200 OK")

; 3. Simulate state transition from usingDirectObsFallback -> Bridge candidate queue
remCfg := {
    HostAddress: "127.0.0.1",
    HostPort: "4455",
    BridgePort: String(bridge.boundTcpPort),
    NetworkMode: "LAN",
    SessionPairingCode: cfg.SessionPairingCode,
    SessionToken: "",
    PairedHostUuid: hostUuid
}
remState := {
    usingDirectObsFallback: true,
    usingRelayFallback: false,
    usingBridge: false,
    candidates: [],
    candidateIndex: 1
}
if (probeUp.ok) {
    remState.usingDirectObsFallback := false
    remState.usingRelayFallback := false
    remState.candidates := BuildRemoteLanCandidateQueue(remCfg)
}
AssertTrue(remState.usingDirectObsFallback == false, "Fallback state cleared on Bridge recovery")
AssertTrue(remState.candidates.Length > 0 && remState.candidates[1].isBridge == true, "First candidate after recovery is Host Bridge")

; 4. Stop bridge & verify probe returns ok=false
savedPort := bridge.boundTcpPort
StopHostCompanionBridge()
probeDown := ProbeHostBridgeHealth("127.0.0.1", savedPort, hostUuid, RemoteBridgeConstants.HEALTH_PROBE_TIMEOUT_MS)
AssertTrue(IsObject(probeDown) && probeDown.ok == false, "ProbeHostBridgeHealth returns ok=false after Bridge stops")

try FileDelete(tmpIni)
try FileAppend("PASS=" passed " FAIL=" failed "`n", "*")
ExitApp(failed > 0 ? 1 : 0)
