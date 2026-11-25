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
#Include "%A_LineFile%\..\..\Lib\SetupWizard.ahk"

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

; 5. M2.2: 2-probe repromotion hysteresis
AssertTrue(RemoteBridgeConstants.BRIDGE_REPROMOTE_REQUIRED_PROBES == 2, "BRIDGE_REPROMOTE_REQUIRED_PROBES == 2")
hystSt := {}
AssertTrue(StepBridgeRepromoteHysteresis(hystSt, true) == false, "1st healthy probe arms hysteresis without immediate promotion")
AssertTrue(hystSt._repromoteHealthyStreak == 1, "Streak increments to 1 on 1st healthy probe")
AssertTrue(StepBridgeRepromoteHysteresis(hystSt, false) == false && hystSt._repromoteHealthyStreak == 0, "Failed probe resets hysteresis streak to 0")
AssertTrue(StepBridgeRepromoteHysteresis(hystSt, true) == false, "1st healthy probe after failure re-arms streak=1")
AssertTrue(StepBridgeRepromoteHysteresis(hystSt, true) == true && hystSt._repromoteHealthyStreak == 0, "2nd consecutive healthy probe promotes & resets streak")

; 6. M2.2: Bridge fallback port sweep list & SweepHostBridgeFallbackPort (skips UDP :4457)
sweepList := GetRemoteBridgeSweepPorts(4456)
AssertTrue(sweepList.Length == 9 && sweepList[1] == 4456 && sweepList[2] == 4458 && sweepList[9] == 4465, "GetRemoteBridgeSweepPorts returns [4456, 4458..4465]")
has4457 := false
for _, sp in sweepList {
    if (sp == 4457)
        has4457 := true
}
AssertTrue(!has4457, "GetRemoteBridgeSweepPorts skips UDP discovery port 4457")
sweepHit := SweepHostBridgeFallbackPort("127.0.0.1", 4456, "", 200, (h, p, u, t) => (p == 4459 ? {ok: true, port: 4459} : {ok: false}))
AssertTrue(sweepHit.ok && sweepHit.port = "4459", "SweepHostBridgeFallbackPort discovers Bridge shifted to :4459")

; 7. M2.2: Hostname / .local mDNS IPv4 resolution
AssertTrue(ResolveHostIpv4("127.0.0.1") != 0, "ResolveHostIpv4 handles dotted IPv4")
AssertTrue(ResolveHostIpv4("localhost") != 0, "ResolveHostIpv4 resolves localhost via GetAddrInfoW/normalize")
AssertTrue(ResolveHostIpv4(A_ComputerName) != 0, "ResolveHostIpv4 resolves local computer hostname via GetAddrInfoW")

; 8. M2.2: Virtual/VPN adapter classifier & BuildHostPairingUri > 4 IPs
for _, badName in ["Hyper-V Virtual Ethernet Adapter", "vEthernet (WSL)", "WireGuard Tunnel", "Tailscale Tunnel", "ZeroTier One", "Wintun Userspace Tunnel", "NordLynx Tunnel", "Cisco AnyConnect VPN", "VirtualBox Host-Only Ethernet Adapter", "DockerNAT"] {
    AssertTrue(IsVirtualOrVpnAdapterName(badName), "IsVirtualOrVpnAdapterName flags '" badName "'")
}
AssertTrue(!IsVirtualOrVpnAdapterName("Intel(R) Wi-Fi 6 AX200 160MHz"), "Physical Wi-Fi adapter is not flagged virtual")
uriMany := BuildHostPairingUri(cfg, ["192.168.1.10", "192.168.1.11", "10.0.0.12", "10.0.0.13", "172.16.5.14"])
AssertTrue(InStr(uriMany, "172.16.5.14") > 0, "BuildHostPairingUri lifts 4-IP cap and preserves 5th candidate")

; 9. M2.2: Direct OBS fallback state snapshot & HostBridge _ReconcileClientFallbackState + BroadcastObsFallbackUpdate
fbRemSt := {
    isStandby: true,
    standbyScene: "BRB",
    standbySnapshot: { scene: "Slides", muted: false },
    timerState: "running",
    timerRemainingSec: 245,
    timerPresetSec: 300
}
fbJson := BuildRemoteFallbackStateJson(fbRemSt)
authJsonFb := BuildRemoteBridgeAuthJson(remCfg, fbJson)
AssertTrue(InStr(authJsonFb, '"clientFallbackState"') && InStr(authJsonFb, '"previousScene":"Slides"'), "BuildRemoteBridgeAuthJson embeds clientFallbackState")

cfgRec := Config(tmpIni)
cfgRec.SessionPairingCode := "M22-REC"
cfgRec.EnableWS := true
cfgRec.obsPassword := "NewObsPw99!"
cfgRec.targetMicName := "LavMic"
stRec := OverlayState(cfgRec)
stRec.currentSceneName := "Scene"
stRec.isStandby := false
stRec.timerState := "stopped"
stRec.timerRemainingSec := 600
bridgeRec := StartHostCompanionBridge(cfgRec, stRec, 0, -1, 0)
parsedFbMap := JsonCodec.Parse(fbJson)
changedRec := bridgeRec._ReconcileClientFallbackState({ deviceId: "win-1" }, parsedFbMap)
AssertTrue(changedRec && stRec.isStandby == true && IsObject(stRec.standbySnapshot) && stRec.standbySnapshot.scene = "Slides", "Host reconciles Direct OBS standbySnapshot scene=Slides on Bridge re-promotion")
AssertTrue(stRec.timerState = "running" && stRec.timerRemainingSec == 245 && stRec.timerPresetSec == 300, "Host reconciles active timerRemainingSec=245 on Bridge re-promotion")
sentObsFb := bridgeRec.BroadcastObsFallbackUpdate(cfgRec)
AssertTrue(sentObsFb == 0, "BroadcastObsFallbackUpdate succeeds cleanly with 0 connected clients")
StopHostCompanionBridge()

; 10. M2.2: HandleRemoteWtsSessionChange lock/unlock + monotonic clocks
wtsTrack := { called: 0 }
wtsSt := { isSessionLocked: false }
AssertTrue(HandleRemoteWtsSessionChange(0x7, remCfg, wtsSt, (*) => (wtsTrack.called += 1)) = "lock" && wtsSt.isSessionLocked == true && wtsTrack.called == 0, "WTS_SESSION_LOCK sets isSessionLocked without reconnect")
AssertTrue(HandleRemoteWtsSessionChange(0x8, remCfg, wtsSt, (*) => (wtsTrack.called += 1)) = "unlock" && wtsSt.isSessionLocked == false && wtsTrack.called == 1, "WTS_SESSION_UNLOCK clears lock & invokes wake verification")

clkSt := { recState: 1, recSeconds: 10, timerState: "running", timerRemainingSec: 125, timerPresetSec: 300, suppressNudgeBanners: true }
AnchorRemoteRecClock(clkSt, 10, 10000)
RemoteLocalRecTick(remCfg, clkSt, 15200)
AssertTrue(clkSt.recSeconds == 15, "Monotonic RemoteLocalRecTick advances 5s across 5200ms timer stall")
AnchorRemotePresenterClock(clkSt, 125, 10000)
RemoteTimerTick(remCfg, clkSt, 16100)
AssertTrue(clkSt.timerRemainingSec == 119, "Monotonic RemoteTimerTick decrements 6s across 6100ms stall without drift")

try FileDelete(tmpIni)
try FileAppend("PASS=" passed " FAIL=" failed "`n", "*")
ExitApp(failed > 0 ? 1 : 0)
