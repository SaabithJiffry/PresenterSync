; ==============================================================================
; Test Suite: test_v761_preresume_hotkey_audit.ahk
; Description: Automated audit for v7.6.1 Pre-Resume Hotkey, SetKeyDelay,
;              IsPptKeyAllowed, TriggerObsSceneTransition, & Graceful IPC Exit
; ==============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

global g_IsTestMode := true
SetTimer(() => ExitApp(124), -45000)

#Include "..\Lib\WebSocket.ahk"
#Include "..\Lib\Crypto.ahk"
#Include "..\Lib\Gdip.ahk"
#Include "..\Lib\UIA.ahk"
#Include "..\Lib\OBS_Network.ahk"
#Include "..\Lib\GUI_Config.ahk"

Gdip.Startup()
OnExit((*) => (Theme.Shutdown(), UIA.Shutdown(), Gdip.Shutdown()))

PassCount := 0
FailCount := 0

OnError((exc, mode) => (FileAppend("[ERROR] " exc.What " (" exc.File ":" exc.Line "): " exc.Message "`n", "*"), ExitApp(1)))

Assert(name, cond, detail := "") {
    global PassCount, FailCount
    if (cond) {
        PassCount += 1
        FileAppend("[PASS] " name (detail != "" ? " - " detail : "") "`n", "*")
    } else {
        FailCount += 1
        FileAppend("[FAIL] " name (detail != "" ? " - " detail : "") "`n", "*")
    }
}

rootDir := A_ScriptDir "\.."
hostSrc := FileRead(rootDir "\PresenterSync.ahk", "UTF-8")
obsNetSrc := FileRead(rootDir "\Lib\OBS_Network.ahk", "UTF-8")
remoteSrc := FileRead(rootDir "\PresenterSync_Remote.ahk", "UTF-8")

; 1. Zero SetKeyDelay 50, 50 in PresenterSync.ahk & Lib\OBS_Network.ahk
Assert("Zero SetKeyDelay 50,50 in PresenterSync.ahk", !RegExMatch(hostSrc, "i)SetKeyDelay\s+50\s*,\s*50"))
Assert("Zero SetKeyDelay 50,50 in Lib\OBS_Network.ahk", !RegExMatch(obsNetSrc, "i)SetKeyDelay\s+50\s*,\s*50"))

; 2. Zero A_IPAddress in PresenterSync.ahk, PresenterSync_Remote.ahk, and Lib\*.ahk
Assert("Zero A_IPAddress in PresenterSync.ahk", !InStr(hostSrc, "A_IPAddress"))
Assert("Zero A_IPAddress in PresenterSync_Remote.ahk", !InStr(remoteSrc, "A_IPAddress"))
ipHits := 0
Loop Files, rootDir "\Lib\*.ahk" {
    libTxt := FileRead(A_LoopFileFullPath, "UTF-8")
    if (InStr(libTxt, "A_IPAddress"))
        ipHits += 1
}
Assert("Zero A_IPAddress across Lib\*.ahk", ipHits = 0, "hits=" ipHits)

; 3. IsPptKeyAllowed blocks collisions across all 11 hotkey props
allProps := [
    "HwMuteHotkey", "ObsMuteHotkey", "HwTransitionHotkey", "ObsTransitionHotkey",
    "ZoomMuteHotkey", "TeamsMuteHotkey", "MeetMuteHotkey",
    "ObsRecHotkey", "ZoomRecHotkey", "ObsPauseHotkey", "ZoomPauseHotkey"
]
for _, prop in allProps {
    mockCfg := {
        CatchArrows: true, CatchPg: true, CatchSpace: true,
        CatchEnter: true, CatchTab: true, CatchEsc: true
    }
    mockCfg.%prop% := "PgDn"
    Assert("IsPptKeyAllowed blocks collision with " prop, !IsPptKeyAllowed(mockCfg, "PgDn"))
}
cleanCfg := {
    CatchArrows: true, CatchPg: true, CatchSpace: true,
    CatchEnter: true, CatchTab: true, CatchEsc: true,
    HwMuteHotkey: "b", ObsMuteHotkey: "F9", HwTransitionHotkey: "None", ObsTransitionHotkey: "None",
    ZoomMuteHotkey: "!a", TeamsMuteHotkey: "^+m", MeetMuteHotkey: "^d",
    ObsRecHotkey: "^F9", ZoomRecHotkey: "!r", ObsPauseHotkey: "^F10", ZoomPauseHotkey: "!p"
}
Assert("IsPptKeyAllowed allows non-colliding PgDn", IsPptKeyAllowed(cleanCfg, "PgDn"))

; 4. TriggerObsSceneTransition fallback & mock OBS WS dispatch
Assert("TriggerObsSceneTransition uses 'if (!dispatched && WinExist' fallback",
    InStr(obsNetSrc, 'if (!dispatched && WinExist("ahk_exe obs64.exe")') > 0 && !InStr(obsNetSrc, 'else if (WinExist("ahk_exe obs64.exe")'))

sentReqs := []
mockWs := { sendText: (this, txt) => sentReqs.Push(txt) }
tCfg := { EnablePointerTransition: true, ObsTransitionHotkey: "F11" }

stStudio := { obsConnected: true, obsWs: mockWs, studioModeActive: true, previewSceneName: "", currentSceneName: "Main", previousProgramScene: "" }
Assert("TriggerObsSceneTransition Studio Mode ON dispatches TriggerStudioModeTransition",
    TriggerObsSceneTransition(tCfg, stStudio, true) && sentReqs.Length = 1 && InStr(sentReqs[1], "TriggerStudioModeTransition") > 0)

Sleep 35
sentReqs := []
stPreview := { obsConnected: true, obsWs: mockWs, studioModeActive: false, previewSceneName: "Slides", currentSceneName: "Main", previousProgramScene: "" }
Assert("TriggerObsSceneTransition Studio Mode OFF w/ preview dispatches SetCurrentProgramScene",
    TriggerObsSceneTransition(tCfg, stPreview, true) && sentReqs.Length = 1 && InStr(sentReqs[1], "SetCurrentProgramScene") > 0)

Sleep 35
sentReqs := []
stEmpty := { obsConnected: true, obsWs: mockWs, studioModeActive: false, previewSceneName: "", currentSceneName: "Main", previousProgramScene: "" }
resEmpty := TriggerObsSceneTransition(tCfg, stEmpty, true)
Assert("TriggerObsSceneTransition Studio Mode OFF w/ empty preview does not send WS request", sentReqs.Length = 0)

; 5. Source invariants in PresenterSync.ahk
Assert("BindPptInterceptHotkeys checks !cfg.EnablePPT", InStr(hostSrc, "if (!cfg.EnablePPT)") > 0)
Assert("BindHwMuteHotkey binds with $ prefix and checks enable flags",
    InStr(hostSrc, "if (!(cfg.EnablePPT || cfg.EnableMicOnly)") > 0 && InStr(hostSrc, 'hk := "$" RegExReplace(Trim(cfg.HwMuteHotkey)') > 0)
Assert("BindHwTransitionHotkey binds with $ prefix and checks EnablePointerTransition",
    InStr(hostSrc, "if (!cfg.EnablePointerTransition") > 0 && InStr(hostSrc, 'hk := "$" RegExReplace(Trim(cfg.HwTransitionHotkey)') > 0)
Assert("TogglePPT/ToggleMicOnly/CyclePointerMode call RebindAllHostHotkeys",
    RegExMatch(hostSrc, "s)TogglePPT.*?RebindAllHostHotkeys.*?ToggleMicOnly.*?RebindAllHostHotkeys.*?CyclePointerMode.*?RebindAllHostHotkeys"))
Assert("EnforceHostSingleInstance attempts __exit__ graceful shutdown before ProcessClose",
    InStr(hostSrc, '"__exit__"') > 0 && InStr(hostSrc, "ProcessClose(pid)") > InStr(hostSrc, '"__exit__"'))

; 6. DispatchCliCommandString("__exit__", cfg, st) invokes cliExitFn & returns true
stCli := { called: false }
stCli.cliExitFn := (*) => (stCli.called := true)
okExit := DispatchCliCommandString("__exit__", cleanCfg, stCli)
Assert("DispatchCliCommandString('__exit__') returns true and invokes cliExitFn", okExit && stCli.called)

FileAppend("PASS=" PassCount " FAIL=" FailCount "`n", "*")
ExitApp(FailCount > 0 ? 1 : 0)
