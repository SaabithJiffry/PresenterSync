#Requires AutoHotkey v2.0
#SingleInstance Off
SetWorkingDir A_ScriptDir "\.."

#Include ..\Lib\WebSocket.ahk
#Include ..\Lib\UIA.ahk
#Include ..\Lib\Crypto.ahk
#Include ..\Lib\JsonCodec.ahk
#Include ..\Lib\RemoteBridgeClient.ahk
#Include ..\Lib\Gdip.ahk
#Include ..\Lib\DiagnosticLogger.ahk
#Include ..\Lib\SessionTimeline.ahk
#Include ..\Lib\OBS_Network.ahk
#Include ..\Lib\GUI_Config.ahk
#Include ..\Lib\HostBridge.ahk
#Include ..\Lib\HudRenderer.ahk
#Include ..\Lib\OperatorConsole.ahk

global g_Passed := 0, g_Failed := 0, g_FailMessages := []
AssertTrue(cond, msg) {
    global g_Passed, g_Failed, g_FailMessages
    if (cond)
        g_Passed++
    else {
        g_Failed++
        g_FailMessages.Push("FAIL: " msg)
    }
}

try {
    pIni := A_Temp "\ps_m81_" A_TickCount ".ini"
    try FileDelete(pIni)
    cfg := Config(pIni)
    st := OverlayState(cfg)
    st.obsConnected := true
    st.studioModeActive := true
    st.previewSceneName := "SlidesPreview"
    st.streamState := 1
    st.vcamActive := true
    st.unreadChatCount := 2
    st.voicePeak := 0.42
    st.sceneList := ["Main", "SlidesPreview", "BRB"]

    hb := HostCompanionBridge()
    hb.cfg := cfg
    hb.state := st
    j := hb._BuildMuteStateJson()
    AssertTrue(InStr(j, '"studioModeActive":true'), "M8.1: Bridge JSON includes studioModeActive")
    AssertTrue(InStr(j, '"previewSceneName":"SlidesPreview"'), "M8.1: Bridge JSON includes previewSceneName")
    AssertTrue(InStr(j, '"streamState":1'), "M8.1: Bridge JSON includes streamState")
    AssertTrue(InStr(j, '"vcamActive":true'), "M8.1: Bridge JSON includes vcamActive")
    AssertTrue(InStr(j, '"unreadChatCount":2'), "M8.1: Bridge JSON includes unreadChatCount")
    AssertTrue(InStr(j, '"voicePeak":0.42'), "M8.1: Bridge JSON includes quantized voicePeak")

    okOpen := OperatorConsole.Show(cfg, st)
    AssertTrue(okOpen && OperatorConsole.IsOpen(), "M8.1: OperatorConsole opens cleanly")
    AssertTrue(!A_IsSuspended, "M8.1: OperatorConsole NEVER suspends hotkeys (A_IsSuspended == false)")
    AssertTrue(WindowFit._states.Has(OperatorConsole._gui.Hwnd), "M8.1: OperatorConsole uses WindowFit")
    OperatorConsole.Close()
    AssertTrue(!OperatorConsole.IsOpen(), "M8.1: OperatorConsole closes cleanly")

    ; ---- M8.2: Preview, SceneItemEnabled, InputVolume, AudioHandoff, ReplayBuffer, Custom Host/Port ----
    mWs := { sent: [] }
    mWs.DefineProp("sendText", { Call: (this, t) => (this.sent.Push(t), true) })
    st.obsWs := mWs
    cfg.EnableWS := true
    cfg.targetMicName := "MicA"
    cfg.SecondaryAudioSources := "MicB"
    cfg.ObsWsHost := "192.168.1.50"
    cfg.ObsWsPort := 4466
    AssertTrue(ExecuteHostSetPreviewScene(cfg, st, "SlidesPreview"), "M8.2: SetPreviewScene succeeds")
    AssertTrue(ExecuteHostSetSceneItemEnabled(cfg, st, "Main", 7, false), "M8.2: SetSceneItemEnabled succeeds")
    AssertTrue(ExecuteHostSetInputVolume(cfg, st, "MicA", 0.85), "M8.2: SetInputVolume succeeds")
    AssertTrue(ExecuteHostAudioHandoff(cfg, st, "solo_b"), "M8.2: AudioHandoff solo_b succeeds")
    AssertTrue(ExecuteHostSaveReplayBuffer(cfg, st), "M8.2: SaveReplayBuffer succeeds")
    all82 := ""
    for _, s in mWs.sent
        all82 .= s "`n"
    AssertTrue(InStr(all82, "SetCurrentPreviewScene") && InStr(all82, "SetSceneItemEnabled") && InStr(all82, "SetInputVolume") && InStr(all82, "SaveReplayBuffer"), "M8.2: All OBS requests dispatched")

    ; ---- M8.3: AddBookmark, AutoExportSidecars, ArchiveActiveSession, SessionTurnover ----
    tmpArch := A_Temp "\ps_m83_rec_" A_TickCount
    DirCreate(tmpArch)
    st.recordDirectory := tmpArch
    st.recElapsedSec := 42
    st.isPanic := false
    st.isStandby := false
    SessionTimeline.Entries := []
    SessionTimeline.AddBookmark("Key Concept", st, "Director")
    AssertTrue(SessionTimeline.Entries.Length >= 1, "M8.3: AddBookmark records event")
    AssertTrue(SessionTimeline.AutoExportSidecars(st, tmpArch), "M8.3: AutoExportSidecars writes csv/txt/md")
    AssertTrue(ExecuteHostSessionTurnover(cfg, st, true), "M8.3: ExecuteHostSessionTurnover succeeds")
    AssertTrue(st.isMuted && !st.isStandby && !st.isPanic && st.unreadChatCount == 0, "M8.3: Turnover resets state & safely mutes")

    ; ---- P0-2 Regression: g_HostCompanionBridge Roster, Guest Revoke & SessionReset ----
    global g_HostCompanionBridge := hb
    hb.pairedDevices["guest-1"] := { deviceId: "guest-1", deviceName: "GuestBoard", role: "Presenter", trustTier: "Ephemeral Guest", allowDirectObsFallback: false, paused: false }
    hb.pairedDevices["pin-1"] := { deviceId: "pin-1", deviceName: "PinnedRoom", role: "Director", trustTier: "Pinned Room", allowDirectObsFallback: true, paused: false }
    OperatorConsole.Show(cfg, st)
    AssertTrue(OperatorConsole._ctrls["roster"].GetCount() >= 2, "P0-2: OperatorConsole Roster populates via g_HostCompanionBridge")
    OperatorConsole.Close()
    ExecuteHostSessionTurnover(cfg, st, true)
    AssertTrue(!hb.pairedDevices.Has("guest-1") && hb.pairedDevices.Has("pin-1"), "P0-2: SessionTurnover revokes Ephemeral Guest while keeping Pinned Room")
    g_HostCompanionBridge := ""
    try DirDelete(tmpArch, true)
    try FileDelete(pIni)
} catch as err {
    g_Failed++
    g_FailMessages.Push("UNCAUGHT EXCEPTION: " err.Message " (" err.File ":" err.Line ")")
}

if (g_Failed > 0) {
    for _, m in g_FailMessages
        FileAppend(m "`n", "*")
    FileAppend("M8.1 Console Summary: " g_Passed " passed, " g_Failed " failed.`n", "*")
    ExitApp(1)
}
FileAppend("M8.1 Console Summary: " g_Passed " passed, 0 failed.`n", "*")
ExitApp(0)
