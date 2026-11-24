; ==============================================================================
; Test Suite: test_v734_automute_cli.ahk
; Description: Verifies v7.3.4 Auto-Mute safety triggers (Lock, Meeting End,
;              First OBS Connect), CLI flag parsing, 64-bit WM_COPYDATA IPC,
;              and AutoMute* Config persistence.
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

tmpIni := A_Temp "\PresenterSync_v734_test_" A_TickCount ".ini"
if FileExist(tmpIni)
    FileDelete(tmpIni)
if FileExist(tmpIni ".bak")
    FileDelete(tmpIni ".bak")

cfg := Config(tmpIni)
st := OverlayState(cfg)
st.suppressNudgeBanners := true
cfg.EnableWS := true
cfg.EnableRemoteConnections := false
st.obsTimerFn := ""
st.zoomTimerFn := ""
cfg.AudioRoutingMode := 1
cfg.targetMicName := "Mic/Aux"

; 1. Config defaults & persistence for AutoMute* booleans
AssertTrue(cfg.AutoMuteOnLock == true && cfg.AutoMuteOnMeetingEnd == false && cfg.AutoMuteOnFirstObsConnect == false, "Config defaults for AutoMute* booleans")
okCC := ApplyControlCenterSettings(cfg, st, { AutoMuteOnLock: false, AutoMuteOnMeetingEnd: true, AutoMuteOnFirstObsConnect: true }, false)
AssertTrue(okCC == true && !cfg.AutoMuteOnLock && cfg.AutoMuteOnMeetingEnd && cfg.AutoMuteOnFirstObsConnect, "ApplyControlCenterSettings updates AutoMute* flags")
reloaded := Config(tmpIni)
AssertTrue(!reloaded.AutoMuteOnLock && reloaded.AutoMuteOnMeetingEnd && reloaded.AutoMuteOnFirstObsConnect, "AutoMute* flags persist across Config reload")

; 2. HandleWtsSessionChange (0x7 lock vs 0x8 unlock, enabled vs disabled)
ws := MockObsWs()
st.obsWs := ws
st.obsConnected := true
st.isMuted := false
cfg.AutoMuteOnLock := false
HandleWtsSessionChange(0x7, 0, cfg, st)
AssertTrue(st.isMuted == false && ws.sent.Length == 0, "HandleWtsSessionChange does nothing when AutoMuteOnLock=false")

cfg.AutoMuteOnLock := true
HandleWtsSessionChange(0x8, 0, cfg, st) ; WTS_SESSION_UNLOCK
AssertTrue(st.isMuted == false && ws.sent.Length == 0, "HandleWtsSessionChange ignores unlock (0x8)")

HandleWtsSessionChange(0x7, 0, cfg, st) ; WTS_SESSION_LOCK
AssertTrue(ws.sent.Length == 1 && InStr(ws.sent[1], '"SetInputMute"') && InStr(ws.sent[1], '"inputMuted":true'), "HandleWtsSessionChange sends SetInputMute=true on lock (0x7)")

; 3. CheckConfMeetingEndAutoMute (true -> false transition vs staying true)
ws.sent := []
st.isMuted := false
st.wasInConfMeeting := false
cfg.AutoMuteOnMeetingEnd := true
CheckConfMeetingEndAutoMute(cfg, st, true)
AssertTrue(st.wasInConfMeeting == true && ws.sent.Length == 0, "Staying in meeting keeps mic live")
CheckConfMeetingEndAutoMute(cfg, st, true)
AssertTrue(ws.sent.Length == 0, "Continued in-meeting state does not mute")
CheckConfMeetingEndAutoMute(cfg, st, false)
AssertTrue(st.wasInConfMeeting == false && ws.sent.Length == 1 && InStr(ws.sent[1], '"inputMuted":true'), "Meeting true -> false transition forces mute")

; 4. AutoMuteOnFirstObsConnect in HandleObsMessage opCode == 2
ws.sent := []
st.isMuted := false
st.hasEverConnectedObsThisRun := false
cfg.AutoMuteOnFirstObsConnect := true
HandleObsMessage(cfg, st, ws, '{"op":2,"d":{"negotiatedRpcVersion":1}}')
hasMuteTrue := false
for _, s in ws.sent
    if (InStr(s, '"SetInputMute"') && InStr(s, '"inputMuted":true'))
        hasMuteTrue := true
AssertTrue(st.hasEverConnectedObsThisRun == true && hasMuteTrue, "AutoMuteOnFirstObsConnect sends SetInputMute=true on first OBS connect")

; Second connect (reconnect) must NOT force mute again
ws.sent := []
st.isMuted := false
HandleObsMessage(cfg, st, ws, '{"op":2,"d":{"negotiatedRpcVersion":1}}')
hasMuteTrue2 := false
for _, s in ws.sent
    if (InStr(s, '"SetInputMute"') && InStr(s, '"inputMuted":true'))
        hasMuteTrue2 := true
AssertTrue(st.isMuted == false && !hasMuteTrue2, "AutoMuteOnFirstObsConnect does not re-mute on 2nd OBS reconnect")

; 5. ParseHostCliArgs for all 8 flags
AssertTrue(ParseHostCliArgs(["--mute"]) = "mute", "ParseHostCliArgs --mute")
AssertTrue(ParseHostCliArgs(["--unmute"]) = "unmute", "ParseHostCliArgs --unmute")
AssertTrue(ParseHostCliArgs(["--toggle-mute"]) = "toggle-mute", "ParseHostCliArgs --toggle-mute")
AssertTrue(ParseHostCliArgs(["--transition"]) = "transition", "ParseHostCliArgs --transition")
AssertTrue(ParseHostCliArgs(["--standby"]) = "standby", "ParseHostCliArgs --standby")
AssertTrue(ParseHostCliArgs(["--split"]) = "split", "ParseHostCliArgs --split")
AssertTrue(ParseHostCliArgs(["--nudge", "Hello World"]) = "nudge:Hello World", "ParseHostCliArgs --nudge <text>")
AssertTrue(ParseHostCliArgs(["--nudge=2m left"]) = "nudge:2m left", "ParseHostCliArgs --nudge=<text>")
AssertTrue(ParseHostCliArgs(["--scene", "Main"]) = "scene:Main", "ParseHostCliArgs --scene <name>")
AssertTrue(ParseHostCliArgs(["--scene=Slides"]) = "scene:Slides", "ParseHostCliArgs --scene=<name>")
AssertTrue(ParseHostCliArgs(["--unknown"]) = "", "ParseHostCliArgs ignores unknown flags")

; 6. Live 64-bit WM_COPYDATA roundtrip
testTitle := "PresenterSync_TestIpc_" A_TickCount
ipcGui := Gui("-Caption +ToolWindow", testTitle)
ipcGui.Show("Hide")
ws.sent := []
st.isMuted := false
copyHandler := OnHostCopyData.Bind(cfg, st)
OnMessage(0x004A, copyHandler)
try {
    okSend := SendHostCliCopyData("mute", testTitle " ahk_class AutoHotkeyGUI")
    AssertTrue(okSend == true && ws.sent.Length == 1 && InStr(ws.sent[1], '"inputMuted":true'), "64-bit WM_COPYDATA 'mute' roundtrip mutes host")

    okSend2 := SendHostCliCopyData("unmute", testTitle " ahk_class AutoHotkeyGUI")
    AssertTrue(okSend2 == true && ws.sent.Length == 2 && InStr(ws.sent[2], '"inputMuted":false'), "64-bit WM_COPYDATA 'unmute' roundtrip unmutes host")

    okSend3 := SendHostCliCopyData("scene:Camera 2", testTitle " ahk_class AutoHotkeyGUI")
    hasScene2 := false
    for _, s in ws.sent
        if (InStr(s, '"SetCurrentProgramScene"') && InStr(s, '"Camera 2"'))
            hasScene2 := true
    AssertTrue(okSend3 == true && hasScene2, "64-bit WM_COPYDATA 'scene:Camera 2' roundtrip switches scene")
} finally {
    OnMessage(0x004A, copyHandler, 0)
    try ipcGui.Destroy()
}

reloaded.DeleteFile()

try FileAppend("PASS=" passed " FAIL=" failed "`n", "*")
ExitApp(failed > 0 ? 1 : 0)
