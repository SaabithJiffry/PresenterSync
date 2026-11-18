; ==============================================================================
; Test Suite: test_v704_scene_studio_dualrec.ahk
; Description: Verifies v7.0.4 Scene/Studio Clicks & Simultaneous OBS+Zoom
;              Recording HUD (#2, #3, #7), including HostBridge state fields.
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

; 1. Simultaneous EnableWS + EnableZoom persistence & ApplyControlCenterSettings
tmpIni := A_Temp "\PresenterSync_v704_test_" A_TickCount ".ini"
if FileExist(tmpIni)
    FileDelete(tmpIni)

cfg := Config(tmpIni)
cfg.EnableWS := true
cfg.EnableZoom := true
cfg.WriteBool("Settings", "EnableWS", true)
cfg.WriteBool("Settings", "EnableZoom", true)

cfgReloaded := Config(tmpIni)
AssertTrue(cfgReloaded.EnableWS == true && cfgReloaded.EnableZoom == true, "Config.Load preserves simultaneous EnableWS + EnableZoom")

st := OverlayState(cfg)
okCC := ApplyControlCenterSettings(cfg, st, { EnableWS: true, EnableZoom: true, ShowText: true }, false)
AssertTrue(okCC == true && cfg.EnableWS == true && cfg.EnableZoom == true, "ApplyControlCenterSettings allows simultaneous EnableWS + EnableZoom")

; 2. SyncRecState "obs" / "conf" / "BOTH" precedence & GetRecLabelPrefix / GetRecBreakdownText
SyncRecState(cfg, st, 1, 5000, "obs")
AssertTrue(st.obsRecState == 1 && st.confRecState == 0 && st.recState == 1 && st.recSourceTag = "OBS", "OBS recording sets recSourceTag=OBS")
AssertTrue(GetRecLabelPrefix(cfg, st) = "OBS ", "GetRecLabelPrefix returns 'OBS ' when ShowText + dual mode")

SyncRecState(cfg, st, 1, 2000, "conf")
AssertTrue(st.obsRecState == 1 && st.confRecState == 1 && st.recState == 1 && st.recSourceTag = "BOTH", "Simultaneous OBS + Conf recording sets recSourceTag=BOTH")
AssertTrue(GetRecLabelPrefix(cfg, st) = "BOTH ", "GetRecLabelPrefix returns 'BOTH '")

SyncRecState(cfg, st, 0, -1, "obs")
AssertTrue(st.obsRecState == 0 && st.confRecState == 1 && st.recState == 1 && st.recSourceTag = "ZM", "Stopping OBS leaves Conf recording active with recSourceTag=ZM")
AssertTrue(GetRecLabelPrefix(cfg, st) = "ZM ", "GetRecLabelPrefix returns 'ZM '")

SyncRecState(cfg, st, 2, -1, "conf")
AssertTrue(st.recState == 2 && st.recSourceTag = "ZM", "Pausing Conf sets unified recState=2")
bd := GetRecBreakdownText(st)
AssertTrue(InStr(bd, "OBS idle") && InStr(bd, "Conferencing PAUSED"), "GetRecBreakdownText formats OBS/Conferencing breakdown")

SyncRecState(cfg, st, 0, -1, "conf")
AssertTrue(st.recState == 0 && st.recSourceTag = "", "Stopping Conf clears recState=0 and recSourceTag=''")

; 3. SceneGui click calling TriggerObsSceneTransition
wsMock := MockObsWs()
st.obsConnected := true
st.obsWs := wsMock
st.studioModeActive := true
st.SceneGui := { Hwnd: 999999 }
cfg.EnableHudClickActions := true
Sleep(35)
resClick := HandleHudPillClick(cfg, st, 999999)
AssertTrue(resClick = "scene" && wsMock.sent.Length == 1 && InStr(wsMock.sent[1], "TriggerStudioModeTransition"), "SceneGui left-click triggers TriggerObsSceneTransition")

; 4. UIConstants.STUDIO_LONG_PRESS_MS == 600
AssertTrue(UIConstants.STUDIO_LONG_PRESS_MS == 600, "UIConstants.STUDIO_LONG_PRESS_MS is 600ms")

; 5. HostBridge _BuildMuteStateJson() includes obsRecState, confRecState, recSourceTag
SyncRecState(cfg, st, 1, 1000, "obs")
SyncRecState(cfg, st, 2, 1000, "conf")
bridge := HostCompanionBridge()
bridge.cfg := cfg
bridge.state := st
json := bridge._BuildMuteStateJson()
AssertTrue(InStr(json, '"obsRecState":1'), "_BuildMuteStateJson includes obsRecState")
AssertTrue(InStr(json, '"confRecState":2'), "_BuildMuteStateJson includes confRecState")
AssertTrue(InStr(json, '"recSourceTag":"BOTH"'), "_BuildMuteStateJson includes recSourceTag")

try FileDelete(tmpIni)
try FileAppend("PASS=" passed " FAIL=" failed "`n", "*")
ExitApp(failed > 0 ? 1 : 0)
