; ==============================================================================
; Test Suite: test_v741_remote_power_probe.ahk
; Description: Verifies v7.4.1 Windows Remote WM_POWERBROADCAST recovery,
;              WM_DISPLAYCHANGE monitor clamping, and dual :4456/:4455 probe.
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

; 1. HandleRemotePowerBroadcast (0x4 suspend, 0x7 / 0x12 resume)
st := {
    isSystemSuspending: false,
    lastSuspendTick: 0,
    lastRxTick: 999999,
    reconnecting: true,
    obsConnected: true,
    obsWs: ""
}
reconnCalls := 0
OnReconn(s) {
    global reconnCalls
    reconnCalls += 1
}

resSusp := HandleRemotePowerBroadcast(0x4, st, OnReconn)
AssertTrue(resSusp = "suspend" && st.isSystemSuspending == true && st.lastSuspendTick > 0 && reconnCalls == 0, "0x4 PBT_APMSUSPEND marks suspending without reconnecting")

resRes1 := HandleRemotePowerBroadcast(0x7, st, OnReconn)
AssertTrue(resRes1 = "resume" && st.isSystemSuspending == false && st.lastRxTick == 0 && st.reconnecting == false && st.obsConnected == false && reconnCalls == 1, "0x7 PBT_APMRESUMESUSPEND clears stale flags and triggers reconnect")

st.lastRxTick := 55555
st.reconnecting := true
resRes2 := HandleRemotePowerBroadcast(0x12, st, OnReconn)
AssertTrue(resRes2 = "resume" && st.lastRxTick == 0 && st.reconnecting == false && reconnCalls == 2, "0x12 PBT_APMRESUMEAUTOMATIC clears stale flags and triggers reconnect")

; 2. ClampRemotePositionToBounds
cRight := ClampRemotePositionToBounds(2500, 300, 120, 44, 0, 0, 1920, 1040)
AssertTrue(cRight.x == 1800 && cRight.y == 300, "ClampRemotePositionToBounds clamps off-screen right X to 1800")

cLeftTop := ClampRemotePositionToBounds(-400, -120, 120, 44, 0, 0, 1920, 1040)
AssertTrue(cLeftTop.x == 0 && cLeftTop.y == 0, "ClampRemotePositionToBounds clamps negative X/Y to 0,0")

cBot := ClampRemotePositionToBounds(500, 1400, 120, 44, 0, 0, 1920, 1040)
AssertTrue(cBot.x == 500 && cBot.y == 996, "ClampRemotePositionToBounds clamps off-screen bottom Y to 996")

cSecMon := ClampRemotePositionToBounds(-2200, 50, 120, 44, -1920, 0, 0, 1080)
AssertTrue(cSecMon.x == -1920 && cSecMon.y == 50, "ClampRemotePositionToBounds supports negative-origin secondary monitor")

; 3. ProbeRemoteDualEndpoints across all 4 combinations
pBothOk := ProbeRemoteDualEndpoints("192.168.1.50", 4456, 4455, (h, b, o) => { bridgeOk: true, obsOk: true })
AssertTrue(pBothOk.bridgeOk && pBothOk.obsOk && InStr(pBothOk.summary, "Host Bridge (:4456): OK | Direct OBS (:4455): OK"), "Dual probe reports both OK")

pBridgeFail := ProbeRemoteDualEndpoints("192.168.1.50", 4456, 4455, (h, b, o) => { bridgeOk: false, obsOk: true })
AssertTrue(!pBridgeFail.bridgeOk && pBridgeFail.obsOk && InStr(pBridgeFail.summary, "Host Bridge (:4456): UNREACHABLE | Direct OBS (:4455): OK"), "Dual probe reports Bridge fail + OBS OK")

pObsFail := ProbeRemoteDualEndpoints("192.168.1.50", 4456, 4455, (h, b, o) => { bridgeOk: true, obsOk: false })
AssertTrue(pObsFail.bridgeOk && !pObsFail.obsOk && InStr(pObsFail.summary, "Host Bridge (:4456): OK | Direct OBS (:4455): UNREACHABLE"), "Dual probe reports Bridge OK + OBS fail")

pBothFail := ProbeRemoteDualEndpoints("192.168.1.50", 4458, 4455, (h, b, o) => { bridgeOk: false, obsOk: false })
AssertTrue(!pBothFail.bridgeOk && !pBothFail.obsOk && InStr(pBothFail.summary, "Host Bridge (:4458): UNREACHABLE | Direct OBS (:4455): UNREACHABLE"), "Dual probe reports both UNREACHABLE with custom port")

try FileAppend("PASS=" passed " FAIL=" failed "`n", "*")
ExitApp(failed > 0 ? 1 : 0)
