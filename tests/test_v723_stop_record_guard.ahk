; ==============================================================================
; Test Suite: test_v723_stop_record_guard.ahk
; Description: Verifies v7.2.3 3,000ms Hold/Confirm-to-Stop Recording Guard:
;              STOP_RECORD_CONFIRM_WINDOW_MS == 3000, ConfirmBeforeStopRecording
;              Config/Profile persistence & ApplyControlCenterSettings,
;              TryConfirmStopRecording, and TryConfirmRemoteStopRecording.
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

; 1. Constant check
AssertTrue(UIConstants.STOP_RECORD_CONFIRM_WINDOW_MS == 3000, "STOP_RECORD_CONFIRM_WINDOW_MS is 3000ms")

; 2. Config persistence, GetProfileFieldSpecs, and ApplyControlCenterSettings
tmpIni := A_Temp "\PresenterSync_v723_test_" A_TickCount ".ini"
if FileExist(tmpIni)
    FileDelete(tmpIni)

cfg := Config(tmpIni)
AssertTrue(cfg.ConfirmBeforeStopRecording == true, "ConfirmBeforeStopRecording defaults to true")

cfg.ConfirmBeforeStopRecording := false
cfg.WriteBool("Settings", "ConfirmBeforeStopRecording", false)
cfgReloaded := Config(tmpIni)
AssertTrue(cfgReloaded.ConfirmBeforeStopRecording == false, "Config persists ConfirmBeforeStopRecording=false")

specs := cfg.GetProfileFieldSpecs()
specKeys := Map()
for _, sp in specs
    specKeys[sp.prop] := true
AssertTrue(specKeys.Has("ConfirmBeforeStopRecording"), "GetProfileFieldSpecs includes ConfirmBeforeStopRecording")

st := OverlayState(cfg)
okCC := ApplyControlCenterSettings(cfg, st, { ConfirmBeforeStopRecording: true }, false)
AssertTrue(okCC == true && cfg.ConfirmBeforeStopRecording == true, "ApplyControlCenterSettings updates ConfirmBeforeStopRecording=true")

; 3. TryConfirmStopRecording state machine
st.recState := 1
st.obsRecState := 1
st.stopRecConfirmUntil := 0

; 1st tap arms -> false
AssertTrue(TryConfirmStopRecording(cfg, st, 10000) == false, "1st tap while recording arms confirm window and returns false")
AssertTrue(st.stopRecConfirmUntil == 13000, "1st tap sets stopRecConfirmUntil = now + 3000")

; 2nd tap < 3000ms -> true
AssertTrue(TryConfirmStopRecording(cfg, st, 12500) == true, "2nd tap within 3000ms confirms stop and returns true")
AssertTrue(st.stopRecConfirmUntil == 0, "Confirmed 2nd tap clears stopRecConfirmUntil")

; Expired >= 3000ms -> re-arms -> false
AssertTrue(TryConfirmStopRecording(cfg, st, 20000) == false, "Fresh tap arms at t=20000")
AssertTrue(TryConfirmStopRecording(cfg, st, 23000) == false, "Tap at >= 3000ms expires window, re-arms, and returns false")
AssertTrue(st.stopRecConfirmUntil == 26000, "Expired tap re-arms window to 26000")

; Disabled -> immediate true
cfg.ConfirmBeforeStopRecording := false
AssertTrue(TryConfirmStopRecording(cfg, st, 30000) == true, "Disabled ConfirmBeforeStopRecording returns true immediately")

; 4. TryConfirmRemoteStopRecording state machine
remCfg := { ConfirmBeforeStopRecording: true }
remSt := { recState: 1, stopRecConfirmUntil: 0 }
AssertTrue(TryConfirmRemoteStopRecording(remCfg, remSt, 50000) == false, "Remote 1st tap arms and returns false")
AssertTrue(remSt.stopRecConfirmUntil == 53000, "Remote 1st tap sets stopRecConfirmUntil = 53000")
AssertTrue(TryConfirmRemoteStopRecording(remCfg, remSt, 51500) == true, "Remote 2nd tap within 3000ms returns true")
AssertTrue(TryConfirmRemoteStopRecording(remCfg, remSt, 60000) == false, "Remote fresh tap arms at 60000")
AssertTrue(TryConfirmRemoteStopRecording(remCfg, remSt, 63500) == false, "Remote expired tap >= 3000ms re-arms and returns false")
remCfg.ConfirmBeforeStopRecording := false
AssertTrue(TryConfirmRemoteStopRecording(remCfg, remSt, 70000) == true, "Remote disabled ConfirmBeforeStopRecording returns true immediately")

; 5. ExecuteHostToggleRecord respects ConfirmBeforeStopRecording when requireStopConfirm=true
cfg.ConfirmBeforeStopRecording := true
cfg.EnableWS := false
st.recState := 1
st.obsRecState := 1
st.stopRecConfirmUntil := 0
AssertTrue(ExecuteHostToggleRecord(cfg, st, true) == false && st.recState == 1 && st.stopRecConfirmUntil > 0, "ExecuteHostToggleRecord requireStopConfirm=true arms 1st tap without stopping")
AssertTrue(ExecuteHostToggleRecord(cfg, st, true) == true && st.recState == 0, "ExecuteHostToggleRecord requireStopConfirm=true confirms stop on 2nd tap")

try FileDelete(tmpIni)
try FileAppend("PASS=" passed " FAIL=" failed "`n", "*")
ExitApp(failed > 0 ? 1 : 0)
