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
