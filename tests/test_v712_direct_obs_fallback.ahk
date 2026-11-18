; ==============================================================================
; Test Suite: test_v712_direct_obs_fallback.ahk
; Description: Verifies v7.1.2 Direct OBS :4455 Fallback when Primary Host
;              Bridge (:4456) is offline: 1800ms connect timeout, channel detection,
;              Local Standby (BRB) snapshot/restore, Direct OBS transition,
;              Local Presenter Countdown Timer, and "DIRECT OBS :4455" status.
; ==============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
SetTimer(() => ExitApp(124), -45000)
OnError((err, mode) => (FileAppend("UNHANDLED_ERR: " err.Message " (" err.What ") at " err.File ":" err.Line "`n", "*"), ExitApp(1)))

#Include "%A_LineFile%\..\..\Lib\WebSocket.ahk"
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

class MockObsWs {
    sent := []
    sendText(txt) {
        this.sent.Push(txt)
        return true
    }
}

; 1. RemoteBridgeConstants.BRIDGE_CONNECT_TIMEOUT_MS == 1800
AssertTrue(RemoteBridgeConstants.BRIDGE_CONNECT_TIMEOUT_MS == 1800, "RemoteBridgeConstants.BRIDGE_CONNECT_TIMEOUT_MS is 1800ms")

; 2. IsRemoteUsingDirectObsChannel
cfg := { TargetMicName: "Mic/Aux", NetworkMode: "LAN" }
wsMock := MockObsWs()
st := {
    obsConnected: true,
    obsWs: wsMock,
    usingBridge: false,
    usingRelayFallback: false,
    usingDirectObsFallback: true,
    activeHost: "192.168.1.25:4455",
    activeScene: "Main Cam",
    currentSceneName: "Main Cam",
    previewScene: "Slides",
    previousProgramScene: "Intro",
    standbyScene: "BRB",
    isMuted: false,
    isStandby: false,
    studioModeActive: true,
    timerState: "stopped",
    timerRemainingSec: 600,
    timerPresetSec: 600,
    NotifyTrayStatus: (*) => 0
}
AssertTrue(IsRemoteUsingDirectObsChannel(cfg, st) == true, "IsRemoteUsingDirectObsChannel returns true when obsConnected & !usingBridge")

stBridge := { obsConnected: true, obsWs: wsMock, usingBridge: true, usingRelayFallback: false }
AssertTrue(IsRemoteUsingDirectObsChannel(cfg, stBridge) == false, "IsRemoteUsingDirectObsChannel returns false when usingBridge=true")

; 3. ExecuteRemoteLocalStandbyToggle (snapshot scene+mute -> BRB + SetInputMute(true) -> restore on 2nd toggle)
wsMock.sent := []
okEnter := ExecuteRemoteLocalStandbyToggle(cfg, st)
AssertTrue(okEnter == true && st.isStandby == true && st.isMuted == true && st.activeScene = "BRB", "Standby enter sets isStandby=true, isMuted=true, activeScene=BRB")
enterJoined := ""
for _, m in wsMock.sent
    enterJoined .= m "`n"
AssertTrue(InStr(enterJoined, '"SetInputMute"') && InStr(enterJoined, '"inputMuted":true'), "Standby enter sends SetInputMute(true)")
AssertTrue(InStr(enterJoined, '"SetCurrentProgramScene"') && InStr(enterJoined, '"sceneName":"BRB"'), "Standby enter switches to BRB scene")

wsMock.sent := []
okExit := ExecuteRemoteLocalStandbyToggle(cfg, st)
AssertTrue(okExit == true && st.isStandby == false && st.isMuted == false && st.activeScene = "Main Cam", "Standby exit restores original scene (Main Cam) and unmuted state")
exitJoined := ""
for _, m in wsMock.sent
    exitJoined .= m "`n"
AssertTrue(InStr(exitJoined, '"SetCurrentProgramScene"') && InStr(exitJoined, '"sceneName":"Main Cam"'), "Standby exit restores Main Cam")
AssertTrue(InStr(exitJoined, '"SetInputMute"') && InStr(exitJoined, '"inputMuted":false'), "Standby exit restores SetInputMute(false)")

; 4. ExecuteRemoteDirectObsTransition (Studio ON -> TriggerStudioModeTransition, Studio OFF -> SetCurrentProgramScene)
wsMock.sent := []
st.studioModeActive := true
okStudioTrans := ExecuteRemoteDirectObsTransition(cfg, st)
AssertTrue(okStudioTrans == true && wsMock.sent.Length == 1 && InStr(wsMock.sent[1], '"TriggerStudioModeTransition"'), "Direct OBS transition in Studio Mode sends TriggerStudioModeTransition")

wsMock.sent := []
st.studioModeActive := false
st.activeScene := "Main Cam"
st.previewScene := "Slides"
okSwapTrans := ExecuteRemoteDirectObsTransition(cfg, st)
AssertTrue(okSwapTrans == true && wsMock.sent.Length == 1 && InStr(wsMock.sent[1], '"SetCurrentProgramScene"') && InStr(wsMock.sent[1], '"sceneName":"Slides"'), "Direct OBS transition without Studio Mode swaps to previewScene")

; 5. ExecuteRemoteLocalTimerCommand (start / pause / reset)
AssertTrue(ExecuteRemoteLocalTimerCommand(cfg, st, "timer_start", 300) == true && st.timerState = "running" && st.timerRemainingSec == 300, "Local timer start sets running & 300s")
AssertTrue(ExecuteRemoteLocalTimerCommand(cfg, st, "timer_pause", 0) == true && st.timerState = "paused", "Local timer pause sets paused")
AssertTrue(ExecuteRemoteLocalTimerCommand(cfg, st, "timer_reset", 450) == true && st.timerState = "stopped" && st.timerRemainingSec == 450, "Local timer reset sets stopped & 450s")

; 6. "DIRECT OBS :4455" status formatting
statusTxt := FormatRemoteDirectObsStatus("192.168.1.25:4455")
AssertTrue(InStr(statusTxt, "DIRECT OBS :4455") && InStr(statusTxt, "192.168.1.25:4455"), "FormatRemoteDirectObsStatus includes DIRECT OBS :4455 and host")

try FileAppend("PASS=" passed " FAIL=" failed "`n", "*")
ExitApp(failed > 0 ? 1 : 0)
