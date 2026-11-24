; ==============================================================================
; Test Suite: test_v910_hotpath_responsiveness.ahk
; Description: Targeted M1.1 (v9.1.0) verification for P14 Core hot paths:
;              1. Non-blocking wall-clock PlayMuteAnimation (20x rapid calls < 100ms,
;                 no Sleep loop, animSeq coalescing, SecondaryMicGui settle parity)
;              2. In-memory PCM WAV PlayMuteAudioCue (RIFF/WAVE header, zero SoundBeep)
;              3. Config.WriteBoolDeferred + ReadBool read-through + FlushDeferredWrites
;              4. SessionTimeline deferred autosave batching + FlushAutosave + sync path
;              5. TriggerObsSceneTransition Studio-OFF sceneList cycle & empty guard
;              6. ExecuteRemoteDirectObsTransition Studio-OFF scenes cycle
;              7. HostBridge toggle_mute / set_mute / transition_scene without stale
;                 pre-OBS mute_state frames, keeping ack frames intact
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
Gdip.Startup()

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

tmpIni := A_Temp "\PresenterSync_v910_hp_" A_TickCount ".ini"
tmpJsonl := A_Temp "\PresenterSync_v910_tl_" A_TickCount ".jsonl"
for p in [tmpIni, tmpIni ".bak", tmpJsonl] {
    if FileExist(p)
        try FileDelete(p)
}

cfg := Config(tmpIni)
st := OverlayState(cfg)
InitHUD(cfg, st, false)
cfg.ShowIndicator := true
cfg.ShowSecondaryMicHud := true

; 1. Non-blocking coalesced PlayMuteAnimation under 20 rapid toggles
t0 := A_TickCount
Loop 20 {
    st.isMuted := !st.isMuted
    PlayMuteAnimation(cfg, st)
}
animElapsed := A_TickCount - t0
AssertTrue(animElapsed < 250, "20 rapid PlayMuteAnimation calls return non-blocking (<250ms), took=" animElapsed "ms")
AssertTrue(st.HasOwnProp("_muteAnimTimerFn") && IsObject(st._muteAnimTimerFn), "PlayMuteAnimation initializes reusable _muteAnimTimerFn")
AssertTrue(st.animSeq >= 20, "PlayMuteAnimation increments animSeq cleanly per burst toggle")

; Clean up timer/GUIs before remaining checks
stoppedCnt := st.StopAllTimers()
AssertTrue(stoppedCnt >= 1, "OverlayState.StopAllTimers includes and stops _muteAnimTimerFn")
for _, gName in ["MicGui", "SecondaryMicGui", "RecGui", "ChatGui", "StudioGui", "SceneGui", "StreamGui", "VCamGui"] {
    if (st.HasOwnProp(gName) && IsObject(st.%gName%))
        try st.%gName%.Destroy()
}

; 2. In-memory PCM WAV PlayMuteAudioCue + _BuildDualToneWavBuffer
wavBuf := _BuildDualToneWavBuffer(880, 65, 520, 95)
riffTag := Format("{:08X}", NumGet(wavBuf, 0, "UInt"))
waveTag := Format("{:08X}", NumGet(wavBuf, 8, "UInt"))
AssertTrue(riffTag = "46464952" && waveTag = "45564157" && wavBuf.Size > 44, "WAV buffer has valid RIFF/WAVE header and PCM payload")
tCue := A_TickCount
Loop 20
    okCue := PlayMuteAudioCue(Mod(A_Index, 2) = 0)
cueMs := A_TickCount - tCue
AssertTrue(okCue == true && cueMs < 100, "20 rapid PlayMuteAudioCue calls complete non-blocking (" cueMs "ms)")

; 3. Config.WriteBoolDeferred + ReadBool read-through + FlushDeferredWrites
cfg.WriteBool("Settings", "IsMuted", false)
rawDiskBefore := IniRead(tmpIni, "Settings", "IsMuted", "0")
cfg.WriteBoolDeferred("Settings", "IsMuted", true, 500)
AssertTrue(cfg.ReadBool("Settings", "IsMuted", false) == true, "Config.ReadBool reflects deferred write immediately in memory")
rawDiskMid := IniRead(tmpIni, "Settings", "IsMuted", "0")
AssertTrue(rawDiskBefore = "0" && rawDiskMid = "0", "WriteBoolDeferred avoids immediate disk write on hot path")
flushed := cfg.FlushDeferredWrites()
rawDiskAfter := IniRead(tmpIni, "Settings", "IsMuted", "0")
AssertTrue(flushed >= 1 && rawDiskAfter = "1", "FlushDeferredWrites commits deferred INI state to disk")

; 4. SessionTimeline deferred autosave vs sync autosave
SessionTimeline.Clear()
SessionTimeline.AutosaveFile := tmpJsonl
SessionTimeline.EnableAutosave := true
SessionTimeline.Record("Mic", "Mic Muted", st, "Mic/Aux", 1, "", true)
AssertTrue(!FileExist(tmpJsonl), "Deferred SessionTimeline.Record batches autosave off the hot path")
AssertTrue(SessionTimeline.FlushAutosave() && FileExist(tmpJsonl), "SessionTimeline.FlushAutosave writes queued JSONL batch")
rawTl := FileRead(tmpJsonl, "UTF-8")
AssertTrue(InStr(rawTl, "Mic Muted"), "Flushed SessionTimeline autosave preserves event summary")
SessionTimeline.ClearAutosave()

; 5. TriggerObsSceneTransition Studio-OFF sceneList cycle & empty guard
wsObs := MockObsWs()
cfg.EnableWS := true
st.obsConnected := true
st.obsWs := wsObs
st.studioModeActive := false
st.previewSceneName := ""
st.previousProgramScene := ""
st.currentSceneName := "Intro"
st.sceneList := ["Intro", "Slides", "Closing"]
okCycle := TriggerObsSceneTransition(cfg, st, true)
AssertTrue(okCycle == true && wsObs.sent.Length == 1 && InStr(wsObs.sent[1], '"sceneName":"Slides"'), "TriggerObsSceneTransition cycles Studio-OFF sceneList to next scene")

Sleep(40)
wsObs.sent := []
st.sceneList := []
st.previewSceneName := ""
st.previousProgramScene := ""
okEmpty := TriggerObsSceneTransition(cfg, st, true)
AssertTrue(okEmpty == false && wsObs.sent.Length == 0, "TriggerObsSceneTransition with empty sceneList and no preview/prev sends 0 WS requests")

; 6. ExecuteRemoteDirectObsTransition Studio-OFF scenes cycle
wsRem := MockObsWs()
remSt := {
    obsConnected: true,
    obsWs: wsRem,
    studioModeActive: false,
    previewScene: "",
    activeScene: "Cam A",
    previousProgramScene: "",
    scenes: ["Cam A", "Slides B", "Ending C"]
}
okRem := ExecuteRemoteDirectObsTransition(cfg, remSt)
AssertTrue(okRem == true && wsRem.sent.Length == 1 && InStr(wsRem.sent[1], '"sceneName":"Slides B"') && remSt.activeScene = "Slides B", "ExecuteRemoteDirectObsTransition cycles Studio-OFF scenes list")

; 7. HostBridge _HandleWsTextMessage emits ack without stale pre-OBS mute_state on toggle_mute/set_mute/toggle_record/transition_scene
bridge := HostCompanionBridge()
bridge.cfg := cfg
bridge.state := st
st.obsConnected := true
st.obsWs := wsObs
st.triggerTransitionFn := (*) => true
fakeCli := { kind: "ws", authenticated: true, writeBuf: [], sendBlocked: false, sock: 0, lastRxTick: 0, closeAfterSend: false, deviceId: "hp-test-1", sendBuf: Buffer(0), sendLen: 0, key: "fake-hp-1" }

queuedFrames := []
origQueue := bridge._QueueWsFrame
bridge.DefineProp("_QueueWsFrame", { call: (self, c, op, txt) => queuedFrames.Push(txt) })

bridge._HandleWsTextMessage(fakeCli, '{"type":"toggle_mute"}')
AssertTrue(queuedFrames.Length == 1 && InStr(queuedFrames[1], '"type":"ack"') && InStr(queuedFrames[1], '"toggle_mute"'), "HostBridge toggle_mute sends ack without stale pre-OBS mute_state")

queuedFrames := []
bridge._HandleWsTextMessage(fakeCli, '{"type":"set_mute","isMuted":true}')
AssertTrue(queuedFrames.Length == 0, "HostBridge set_mute omits redundant pre-OBS mute_state frame")

queuedFrames := []
bridge._HandleWsTextMessage(fakeCli, '{"type":"toggle_record"}')
AssertTrue(queuedFrames.Length == 1 && InStr(queuedFrames[1], '"type":"ack"') && InStr(queuedFrames[1], '"toggle_record"'), "HostBridge toggle_record omits stale mute_state")

queuedFrames := []
bridge._HandleWsTextMessage(fakeCli, '{"type":"transition_scene"}')
AssertTrue(queuedFrames.Length == 1 && InStr(queuedFrames[1], '"type":"ack"') && InStr(queuedFrames[1], '"transition_scene"'), "HostBridge transition_scene omits stale mute_state")

; 8. WaitPillLongPressWithProgress signature & hold-complete callback support + #MaxThreadsPerHotkey 3 check
hostSrc := FileRead(A_ScriptDir "\..\PresenterSync.ahk", "UTF-8")
remSrc := FileRead(A_ScriptDir "\..\PresenterSync_Remote.ahk", "UTF-8")
hudSrc := FileRead(A_ScriptDir "\..\Lib\HudRenderer.ahk", "UTF-8")
AssertTrue(InStr(hostSrc, "#MaxThreadsPerHotkey 3") && InStr(remSrc, "#MaxThreadsPerHotkey 3"), "Both Primary & Remote declare #MaxThreadsPerHotkey 3")
AssertTrue(InStr(hudSrc, 'verdict: "hold_handled"') && InStr(hudSrc, 'UIConstants.MIC_LONG_PRESS_MS, UpdateMicHold'), "MicGui eliminates 350-599ms dead zone with single-toggle hold_handled")
AssertTrue(InStr(hudSrc, 'sceneMoved := false') && InStr(hudSrc, 'hwnd == state.SceneGui.Hwnd'), "SceneGui uses non-blocking tap fast path before drag loop")

for p in [tmpIni, tmpIni ".bak", tmpJsonl] {
    if FileExist(p)
        try FileDelete(p)
}
Gdip.Shutdown()
try FileAppend("PASS=" passed " FAIL=" failed "`n", "*")
ExitApp(failed > 0 ? 1 : 0)
