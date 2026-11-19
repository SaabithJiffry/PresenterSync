; ==============================================================================
; Test Suite: test_v731_multimic_inputs.ahk
; Description: Verifies v7.3.1 OBS GetInputList auto-discovery, multi-mic
;              group mute/toggle, and SecondaryAudioSources persistence.
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
    readyState := 1
    sendText(txt) {
        this.sent.Push(txt)
        return true
    }
}

tmpIni := A_Temp "\PresenterSync_v731_test_" A_TickCount ".ini"
if FileExist(tmpIni)
    FileDelete(tmpIni)
if FileExist(tmpIni ".bak")
    FileDelete(tmpIni ".bak")

; 1. IsObsAudioInputKind & ParseObsInputList
AssertTrue(IsObsAudioInputKind("wasapi_input_capture") == true, "wasapi_input_capture recognized as audio input")
AssertTrue(IsObsAudioInputKind("dshow_input") == true, "dshow_input recognized as audio input")
AssertTrue(IsObsAudioInputKind("browser_source") == false, "browser_source is not an audio input kind")

rawInputResp := '{"op":7,"d":{"requestType":"GetInputList","requestId":"InitInputList","requestStatus":{"result":true,"code":100},"responseData":{"inputs":[{"inputName":"Shure MV7","inputKind":"wasapi_input_capture"},{"inputName":"Slides Capture","inputKind":"window_capture"},{"inputName":"Co-Host Lapel","inputKind":"wasapi_input_capture"},{"inputName":"Desktop Audio","inputKind":"wasapi_output_capture"}]}}}'
parsed := ParseObsInputList(rawInputResp)
AssertTrue(parsed.all.Length == 4, "ParseObsInputList collects all 4 OBS inputs")
AssertTrue(parsed.audio.Length == 3 && parsed.audio[1] = "Shure MV7" && parsed.audio[2] = "Co-Host Lapel" && parsed.audio[3] = "Desktop Audio", "ParseObsInputList filters 3 audio inputs")

; 2. HandleObsMessage opCode == 7 ("InitInputList") populates state & fires refreshInputsFn
cfg := Config(tmpIni)
st := OverlayState(cfg)
cbCalls := 0
cbAudioLen := 0
cbAllLen := 0
OnRefreshInputs(aud, all) {
    global cbCalls, cbAudioLen, cbAllLen
    cbCalls += 1
    cbAudioLen := aud.Length
    cbAllLen := all.Length
}
st.refreshInputsFn := OnRefreshInputs
ws := MockObsWs()
st.obsWs := ws
HandleObsMessage(cfg, st, ws, rawInputResp)
AssertTrue(st.obsInputs.Length == 4 && st.obsAudioInputs.Length == 3, "HandleObsMessage InitInputList populates obsInputs & obsAudioInputs")
AssertTrue(cbCalls == 1 && cbAudioLen == 3 && cbAllLen == 4, "HandleObsMessage InitInputList invokes state.refreshInputsFn")

; 3. GetAllMutedAudioSources trimming, empty-entry skip, deduplication
cfg.targetMicName := "Shure MV7"
cfg.SecondaryAudioSources := " , Co-Host Lapel , Shure MV7 , Backup USB ,  "
grp := GetAllMutedAudioSources(cfg)
AssertTrue(grp.Length == 3 && grp[1] = "Shure MV7" && grp[2] = "Co-Host Lapel" && grp[3] = "Backup USB", "GetAllMutedAudioSources trims, skips empties, and deduplicates")

; 4. SendObsSetInputMuteGroup & SendObsToggleInputMuteGroup
ws.sent := []
okSet := SendObsSetInputMuteGroup(cfg, ws, true, "TestGroupSet")
AssertTrue(okSet == true && ws.sent.Length == 3, "SendObsSetInputMuteGroup sends 3 SetInputMute requests")
AssertTrue(InStr(ws.sent[1], '"Shure MV7"') && InStr(ws.sent[1], '"inputMuted":true')
    && InStr(ws.sent[2], '"Co-Host Lapel"') && InStr(ws.sent[3], '"Backup USB"'), "SendObsSetInputMuteGroup targets all 3 sources")

ws.sent := []
st.isMuted := true
okTog := SendObsToggleInputMuteGroup(cfg, st, ws, "TestGroupToggle")
AssertTrue(okTog == true && ws.sent.Length == 3 && InStr(ws.sent[1], '"inputMuted":false') && InStr(ws.sent[3], '"Backup USB"'), "SendObsToggleInputMuteGroup unmutes all 3 sources when currently muted")

; 5. Config.SecondaryAudioSources save/load roundtrip & ApplyControlCenterSettings
okCC := ApplyControlCenterSettings(cfg, st, { targetMicName: "Rode NT1", SecondaryAudioSources: "Guest 1, Guest 2" }, false)
AssertTrue(okCC == true && cfg.targetMicName = "Rode NT1" && cfg.SecondaryAudioSources = "Guest 1, Guest 2", "ApplyControlCenterSettings updates targetMicName and SecondaryAudioSources")
reloaded := Config(tmpIni)
AssertTrue(reloaded.targetMicName = "Rode NT1" && reloaded.SecondaryAudioSources = "Guest 1, Guest 2", "SecondaryAudioSources persists across Config reload")
reloaded.DeleteFile()

try FileAppend("PASS=" passed " FAIL=" failed "`n", "*")
ExitApp(failed > 0 ? 1 : 0)
