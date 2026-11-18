; ==============================================================================
; Test Suite: test_v702_obs_transition.ahk
; Description: Verifies v7.0.2 Pointer OBS Scene Transition Engine,
;              PPT key collision shield (IsPptKeyAllowed), 25ms bounce filter,
;              ControlCenter validation, and HostBridge "transition_scene".
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

tmpIni := A_Temp "\PresenterSync_v702_test_" A_TickCount ".ini"
if FileExist(tmpIni)
    FileDelete(tmpIni)

; (a) Config & GetProfileFieldSpecs() persistence
cfg := Config(tmpIni)
cfg.EnablePointerTransition := true
cfg.HwTransitionHotkey := "F8"
cfg.ObsTransitionHotkey := "^+t"
cfg.WriteBool("Settings", "EnablePointerTransition", true)
cfg.Write("Settings", "HwTransitionHotkey", "F8")
cfg.Write("Settings", "ObsTransitionHotkey", "^+t")

cfgReloaded := Config(tmpIni)
AssertTrue(cfgReloaded.EnablePointerTransition == true, "Config persists EnablePointerTransition=true")
AssertTrue(cfgReloaded.HwTransitionHotkey = "F8", "Config persists HwTransitionHotkey=F8")
AssertTrue(cfgReloaded.ObsTransitionHotkey = "^+t", "Config persists ObsTransitionHotkey=^+t")

specs := cfg.GetProfileFieldSpecs()
specKeys := Map()
for _, sp in specs
    specKeys[sp.prop] := true
AssertTrue(specKeys.Has("EnablePointerTransition"), "GetProfileFieldSpecs includes EnablePointerTransition")
AssertTrue(specKeys.Has("HwTransitionHotkey"), "GetProfileFieldSpecs includes HwTransitionHotkey")
AssertTrue(specKeys.Has("ObsTransitionHotkey"), "GetProfileFieldSpecs includes ObsTransitionHotkey")

; (b) IsPptKeyAllowed(cfg, "PgDn") returns false when HwTransitionHotkey or ObsTransitionHotkey is PgDn
cfgColl := Config(tmpIni)
cfgColl.CatchPg := true
cfgColl.HwMuteHotkey := "None"
cfgColl.ObsMuteHotkey := "None"
cfgColl.HwTransitionHotkey := "None"
cfgColl.ObsTransitionHotkey := "None"
AssertTrue(IsPptKeyAllowed(cfgColl, "PgDn") == true, "PgDn allowed when no collision")

cfgColl.HwTransitionHotkey := "PgDn"
AssertTrue(IsPptKeyAllowed(cfgColl, "PgDn") == false, "PgDn blocked when HwTransitionHotkey=PgDn")

cfgColl.HwTransitionHotkey := "None"
cfgColl.ObsTransitionHotkey := "PgDn"
AssertTrue(IsPptKeyAllowed(cfgColl, "PgDn") == false, "PgDn blocked when ObsTransitionHotkey=PgDn")

; (c) TriggerObsSceneTransition sends TriggerStudioModeTransition (Studio Mode ON) & SetCurrentProgramScene (Studio Mode OFF)
wsMock := MockObsWs()
st := OverlayState(cfg)
st.obsConnected := true
st.obsWs := wsMock
st.studioModeActive := true
st.currentSceneName := "Main Cam"
st.previewSceneName := "Slides"
st.previousProgramScene := "Intro"

okStudio := TriggerObsSceneTransition(cfg, st, true)
AssertTrue(okStudio == true && wsMock.sent.Length == 1 && InStr(wsMock.sent[1], "TriggerStudioModeTransition"), "Studio Mode ON sends TriggerStudioModeTransition")

Sleep(35)
st.studioModeActive := false
okSwap := TriggerObsSceneTransition(cfg, st, true)
AssertTrue(okSwap == true && wsMock.sent.Length == 2 && InStr(wsMock.sent[2], "SetCurrentProgramScene") && InStr(wsMock.sent[2], '"sceneName":"Slides"'), "Studio Mode OFF sends SetCurrentProgramScene to previewSceneName")

; (d) 5 rapid repeated transitions spaced 35ms apart all fire (0 dropped), while < 25ms bounce is filtered
Sleep(35)
wsMock.sent := []
okFirst := TriggerObsSceneTransition(cfg, st, false)
okBounce := TriggerObsSceneTransition(cfg, st, false)
AssertTrue(okFirst == true && okBounce == false, "Immediate <25ms repeat is filtered as contact bounce")

rapidFired := 0
Loop 5 {
    Sleep(35)
    if (TriggerObsSceneTransition(cfg, st, false))
        rapidFired++
}
AssertTrue(rapidFired == 5, "5 rapid repeated transitions spaced 35ms apart all fire (0 dropped)")

; (e) ApplyControlCenterSettings updates & validates all 3 settings
invalidKeys := []
okCC := ApplyControlCenterSettings(cfg, st, {
    EnablePointerTransition: false,
    HwTransitionHotkey: "F9",
    ObsTransitionHotkey: "^!t"
}, false, invalidKeys)
AssertTrue(okCC == true && invalidKeys.Length == 0, "ApplyControlCenterSettings accepts valid transition settings")
AssertTrue(cfg.EnablePointerTransition == false && cfg.HwTransitionHotkey = "F9" && cfg.ObsTransitionHotkey = "^!t", "ApplyControlCenterSettings updates all 3 transition fields")

invalidKeysBad := []
okBad := ApplyControlCenterSettings(cfg, st, {
    HwTransitionHotkey: "NotAValidKeySpec!!!"
}, false, invalidKeysBad)
AssertTrue(okBad == false && invalidKeysBad.Length == 1, "ApplyControlCenterSettings rejects invalid HwTransitionHotkey")

; (f) HostBridge "transition_scene" invokes state.triggerTransitionFn
bridge := HostCompanionBridge()
bridge.cfg := cfg
bridge.state := st
transitionBox := { count: 0 }
st.triggerTransitionFn := (*) => (transitionBox.count += 1, true)
fakeClient := { kind: "ws", authenticated: true, writeBuf: [], sendBlocked: false, sock: 0, lastRxTick: 0, closeAfterSend: false, deviceId: "test-dev", sendBuf: Buffer(0), sendLen: 0, key: "fake-1" }
bridge._HandleBridgeMessage(fakeClient, '{"type":"transition_scene"}')
AssertTrue(transitionBox.count == 1, "HostBridge transition_scene invokes state.triggerTransitionFn")

try FileDelete(tmpIni)
try FileAppend("PASS=" passed " FAIL=" failed "`n", "*")
ExitApp(failed > 0 ? 1 : 0)
