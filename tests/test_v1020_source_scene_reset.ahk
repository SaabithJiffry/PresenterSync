; ==============================================================================
; Test Suite: test_v1020_source_scene_reset.ahk
; Description: Verifies v10.2.0 M4 (#4) Recursive Source-Level OBS Scene Reset:
;              Groups + nested scenes (cycle-guarded), audio-mic exclusion,
;              dshow_input GetInputSettings pre-check -> activate/disable ->
;              600ms restore -> +1500ms self-heal verify, browser_source
;              refreshnocache, ffmpeg_source/vlc_source restart, re-entry
;              mutex, reconnect recovery, OperatorConsole Reset Scene button,
;              and WebRemoteUI recursive reset markers.
; ==============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Off
SetWorkingDir A_ScriptDir "\.."
SetTimer(() => ExitApp(124), -45000)
OnError((err, mode) => (FileAppend("UNHANDLED_ERR: " err.Message " (" err.What ") at " err.File ":" err.Line "`n", "*"), ExitApp(1)))

#Include ..\Lib\WebSocket.ahk
#Include ..\Lib\UIA.ahk
#Include ..\Lib\Crypto.ahk
#Include ..\Lib\JsonCodec.ahk
#Include ..\Lib\RemoteBridgeClient.ahk
#Include ..\Lib\Gdip.ahk
#Include ..\Lib\WindowFit.ahk
#Include ..\Lib\QrCode.ahk
#Include ..\Lib\DiagnosticLogger.ahk
#Include ..\Lib\SessionTimeline.ahk
#Include ..\Lib\OBS_Network.ahk
#Include ..\Lib\GUI_Config.ahk
#Include ..\Lib\HostBridge.ahk
#Include ..\Lib\HudRenderer.ahk
#Include ..\Lib\OperatorConsole.ahk

global g_IsTestMode := true

Gdip.Startup()
OnExit((*) => (Theme.Shutdown(), UIA.Shutdown(), Gdip.Shutdown()))

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

class MockObsResetWs {
    sent := []
    sendText(txt) {
        this.sent.Push(txt)
        return true
    }
}

; 1. Audio-mic exclusion & source classification
tmpIni := A_Temp "\ps_v1020_m4_" A_TickCount ".ini"
if FileExist(tmpIni)
    FileDelete(tmpIni)
cfg := Config(tmpIni)
cfg.EnableWS := true
cfg.ObsTargetMicName := "Host USB Mic"
cfg.SecondaryAudioSources := "Guest Lapel, Desk Condenser"

AssertTrue(IsProtectedObsAudioSource(cfg, "AnyName", "wasapi_input_capture"), "Audio kind wasapi_input_capture excluded")
AssertTrue(IsProtectedObsAudioSource(cfg, "AnyName", "coreaudio_input_capture"), "Audio kind coreaudio_input_capture excluded")
AssertTrue(IsProtectedObsAudioSource(cfg, "Host USB Mic", "ffmpeg_source"), "TargetMicName excluded")
AssertTrue(IsProtectedObsAudioSource(cfg, "Desk Condenser", "browser_source"), "SecondaryAudioSources excluded")
AssertTrue(!IsProtectedObsAudioSource(cfg, "Sony Cam", "dshow_input"), "Camera dshow_input not excluded")
AssertTrue(ClassifyObsSourceResetKind("dshow_input") = "dshow", "dshow_input classified as dshow")
AssertTrue(ClassifyObsSourceResetKind("browser_source") = "browser", "browser_source classified as browser")
AssertTrue(ClassifyObsSourceResetKind("ffmpeg_source") = "media" && ClassifyObsSourceResetKind("vlc_source") = "media", "ffmpeg/vlc classified as media")

; 2. Recursive Group + Nested Scene + Disabled skip + dshow active/inactive + browser + media
st := OverlayState(cfg)
st.suppressNudgeBanners := true
st.obsConnected := true
mockWs := MockObsResetWs()
st.obsWs := mockWs
st.currentSceneName := "MainStage"

AssertTrue(ExecuteHostResetActiveScene(cfg, st), "ExecuteHostResetActiveScene kicks off recursive crawl")
AssertTrue(!ExecuteHostResetActiveScene(cfg, st), "Re-entry mutex blocks duplicate reset")
AssertTrue(mockWs.sent.Length == 1 && RegExMatch(mockWs.sent[1], '"requestId"\s*:\s*"(ResetSceneCrawl:[^"]+)"', &mRoot), "Root GetSceneItemList sent")
tok := StrSplit(mRoot[1], ":")[2]

; Simulate root scene items: active Group, active Nested Scene, disabled hidden camera, active Browser, active Media, active Mic
mockWs.sent := []
rootResp := '{"op":7,"d":{"requestId":"' mRoot[1] '","requestStatus":{"result":true},"responseData":{"sceneItems":['
    . '{"sceneItemId":10,"sourceName":"CamGroup","isGroup":true,"sceneItemEnabled":true},'
    . '{"sceneItemId":11,"sourceName":"NestedPiP","sourceType":"OBS_SOURCE_TYPE_SCENE","sceneItemEnabled":true},'
    . '{"sceneItemId":12,"sourceName":"HiddenCam","sourceType":"OBS_SOURCE_TYPE_INPUT","inputKind":"dshow_input","sceneItemEnabled":false},'
    . '{"sceneItemId":13,"sourceName":"LiveOverlay","sourceType":"OBS_SOURCE_TYPE_INPUT","inputKind":"browser_source","sceneItemEnabled":true},'
    . '{"sceneItemId":14,"sourceName":"IntroLoop","sourceType":"OBS_SOURCE_TYPE_INPUT","inputKind":"ffmpeg_source","sceneItemEnabled":true},'
    . '{"sceneItemId":15,"sourceName":"Host USB Mic","sourceType":"OBS_SOURCE_TYPE_INPUT","inputKind":"wasapi_input_capture","sceneItemEnabled":true}'
    . ']}}}'
HandleObsMessage(cfg, st, mockWs, rootResp)

reqGrp := "", reqNest := ""
for _, msg in mockWs.sent {
    if (InStr(msg, '"requestType":"GetGroupSceneItemList"') && RegExMatch(msg, '"requestId":"([^"]+)"', &mG))
        reqGrp := mG[1]
    if (InStr(msg, '"requestType":"GetSceneItemList"') && RegExMatch(msg, '"requestId":"([^"]+)"', &mN))
        reqNest := mN[1]
}
AssertTrue(reqGrp != "" && InStr(reqGrp, ":1:CamGroup"), "Dispatched GetGroupSceneItemList for enabled Group")
AssertTrue(reqNest != "" && InStr(reqNest, ":1:NestedPiP"), "Dispatched GetSceneItemList for enabled Nested Scene")

; Respond to Group with active dshow camera "ActiveCam" + NestedPiP with inactive dshow camera "OffCam" & Window Capture & cycle back to MainStage
mockWs.sent := []
grpResp := '{"op":7,"d":{"requestId":"' reqGrp '","requestStatus":{"result":true},"responseData":{"sceneItems":['
    . '{"sceneItemId":20,"sourceName":"ActiveCam","sourceType":"OBS_SOURCE_TYPE_INPUT","inputKind":"dshow_input","sceneItemEnabled":true}'
    . ']}}}'
HandleObsMessage(cfg, st, mockWs, grpResp)
nestResp := '{"op":7,"d":{"requestId":"' reqNest '","requestStatus":{"result":true},"responseData":{"sceneItems":['
    . '{"sceneItemId":30,"sourceName":"OffCam","sourceType":"OBS_SOURCE_TYPE_INPUT","inputKind":"dshow_input","sceneItemEnabled":true},'
    . '{"sceneItemId":31,"sourceName":"SlideWin","sourceType":"OBS_SOURCE_TYPE_INPUT","inputKind":"window_capture","sceneItemEnabled":true},'
    . '{"sceneItemId":32,"sourceName":"MainStage","sourceType":"OBS_SOURCE_TYPE_SCENE","sceneItemEnabled":true}'
    . ']}}}'
HandleObsMessage(cfg, st, mockWs, nestResp)

reqChk1 := "", reqChk2 := ""
for _, msg in mockWs.sent {
    if (InStr(msg, '"requestType":"GetInputSettings"') && RegExMatch(msg, '"requestId":"(ResetCheckDshow:[^"]+)"', &mC)) {
        if (InStr(msg, '"ActiveCam"'))
            reqChk1 := mC[1]
        else if (InStr(msg, '"OffCam"'))
            reqChk2 := mC[1]
    }
    AssertTrue(!InStr(msg, '"MainStage"'), "Cycle guard prevented re-crawling root MainStage")
}
AssertTrue(reqChk1 != "" && reqChk2 != "", "Pre-checked GetInputSettings for both dshow inputs before reset")

; Reply ActiveCam=active:true and OffCam=active:false -> triggers Phase 1!
mockWs.sent := []
HandleObsMessage(cfg, st, mockWs, '{"op":7,"d":{"requestId":"' reqChk1 '","requestStatus":{"result":true},"responseData":{"inputSettings":{"active":true}}}}')
HandleObsMessage(cfg, st, mockWs, '{"op":7,"d":{"requestId":"' reqChk2 '","requestStatus":{"result":true},"responseData":{"inputSettings":{"active":false}}}}')

hasBrowser := false, hasMedia := false, hasDshowOff := false, hasWinOff := false, skippedOffCam := true, skippedMic := true, skippedHidden := true
for _, msg in mockWs.sent {
    if (InStr(msg, '"propertyName":"refreshnocache"') && InStr(msg, '"LiveOverlay"'))
        hasBrowser := true
    if (InStr(msg, '"OBS_WEBSOCKET_MEDIA_INPUT_ACTION_RESTART"') && InStr(msg, '"IntroLoop"'))
        hasMedia := true
    if (InStr(msg, '"propertyName":"activate"') && InStr(msg, '"ActiveCam"'))
        hasDshowOff := true
    if (InStr(msg, '"sceneItemId":31') && InStr(msg, '"sceneItemEnabled":false'))
        hasWinOff := true
    if (InStr(msg, '"OffCam"'))
        skippedOffCam := false
    if (InStr(msg, '"Host USB Mic"'))
        skippedMic := false
    if (InStr(msg, '"sceneItemId":12'))
        skippedHidden := false
}
AssertTrue(hasBrowser, "browser_source refreshed via refreshnocache")
AssertTrue(hasMedia, "ffmpeg_source restarted via TriggerMediaInputAction")
AssertTrue(hasDshowOff, "active dshow_input deactivated via activate property button")
AssertTrue(hasWinOff, "nested visual window_capture disabled in Phase 1")
AssertTrue(skippedOffCam, "inactive dshow_input (active:false) skipped cleanly")
AssertTrue(skippedMic, "protected audio mic untouched")
AssertTrue(skippedHidden, "disabled hidden item (sceneItemEnabled:false) untouched")

; Wait ~700ms for 600ms non-blocking restore timer to fire
mockWs.sent := []
t0 := A_TickCount
while (st.sceneResetInProgress && (A_TickCount - t0 < 1500))
    Sleep(30)
Sleep(80)
hasDshowOn := false, hasWinOn := false
for _, msg in mockWs.sent {
    if (InStr(msg, '"sceneItemId":20') && InStr(msg, '"sceneItemEnabled":true'))
        hasDshowOn := true
    if (InStr(msg, '"sceneItemId":31') && InStr(msg, '"sceneItemEnabled":true'))
        hasWinOn := true
}
AssertTrue(!st.sceneResetInProgress, "Reset unlocked cleanly after 600ms restore")
AssertTrue(hasDshowOn && hasWinOn, "Both Group dshow and Nested Scene window_capture restored after 600ms")

; 3. +1500ms Self-Heal verify test
mockWs.sent := []
HandleObsMessage(cfg, st, mockWs, '{"op":7,"d":{"requestId":"ResetVerifyDshow:' tok ':ActiveCam","requestStatus":{"result":true},"responseData":{"inputSettings":{"active":false}}}}')
AssertTrue(mockWs.sent.Length == 1 && InStr(mockWs.sent[1], '"propertyName":"activate"') && InStr(mockWs.sent[1], '"ActiveCam"'), "Self-heal re-activates stuck dshow camera")

; 4. Reconnect orphan recovery test
st._pendingSceneReenableItems := [{scene: "CamGroup", id: 20, kind: "dshow", name: "ActiveCam"}]
mockWs.sent := []
AssertTrue(_RecoverOrphanSceneResetItems(cfg, st), "Orphan scene reset items recovered on OBS reconnect")
AssertTrue(mockWs.sent.Length == 2 && InStr(mockWs.sent[1], '"sceneItemEnabled":true') && InStr(mockWs.sent[2], '"propertyName":"activate"'), "Orphan recovery re-enables item and activates camera")

; 5. OperatorConsole Reset Scene button + StopAllTimers + WebRemoteUI checks
AssertTrue(OperatorConsole.Show(cfg, st) && OperatorConsole._ctrls.Has("btnResetScene"), "OperatorConsole exposes Reset Scene button")
OperatorConsole.Close()
AssertTrue(st.StopAllTimers() >= 0, "OverlayState.StopAllTimers cleanly handles reset timers")
webHtml := BuildWebRemoteHtml("10.2.0", 4456)
AssertTrue(InStr(webHtml, "GetGroupSceneItemList") && InStr(webHtml, "refreshnocache") && InStr(webHtml, "obsRstVerify:"), "WebRemoteUI implements recursive source-level reset")

try FileDelete(tmpIni)
FileAppend("PASS=" passed " FAIL=" failed "`n", "*")
ExitApp(failed > 0 ? 1 : 0)
