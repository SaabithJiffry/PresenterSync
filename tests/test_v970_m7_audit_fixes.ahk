#Requires AutoHotkey v2.0
#SingleInstance Off
; ============================================================================
; test_v970_m7_audit_fixes.ahk - M7 Live Finding A (mute rollback) & B (WindowFit)
; ============================================================================

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
#Include ..\Lib\WindowFit.ahk
#Include ..\Lib\HostBridge.ahk
#Include ..\Lib\HudRenderer.ahk

global g_Passed := 0
global g_Failed := 0
global g_FailMessages := []

AssertTrue(cond, msg) {
    global g_Passed, g_Failed, g_FailMessages
    if (cond)
        g_Passed++
    else {
        g_Failed++
        g_FailMessages.Push("FAIL: " msg)
    }
}

AssertEq(actual, expected, msg) {
    global g_Passed, g_Failed, g_FailMessages
    if (actual = expected)
        g_Passed++
    else {
        g_Failed++
        g_FailMessages.Push("FAIL: " msg " (expected='" String(expected) "', actual='" String(actual) "')")
    }
}

global MicGui := 0
global State := { isMuted: false }
global Cfg := {}

try {
    ; ---- Finding B: pure helpers ----
    r := WindowFit.ClampOuterSize(900, 1200, 1366, 728, 0.90)
    AssertEq(r.h, 655, "ClampOuterSize clamps height to 90% of 728 work height")
    AssertEq(r.w, 900, "ClampOuterSize leaves width that already fits")
    AssertTrue(r.clamped, "ClampOuterSize reports clamped")
    r2 := WindowFit.ClampOuterSize(400, 300, 1920, 1040, 0.90)
    AssertTrue(!r2.clamped, "ClampOuterSize does not clamp small windows")
    p := WindowFit.ClampPosition(1300, 700, 400, 300, 0, 0, 1366, 728)
    AssertEq(p.x, 966, "ClampPosition pulls window left inside work area")
    AssertEq(p.y, 428, "ClampPosition pulls window up inside work area")
    p2 := WindowFit.ClampPosition(-50, -20, 400, 300, 0, 0, 1366, 728)
    AssertEq(p2.x, 0, "ClampPosition clamps negative x")
    AssertEq(p2.y, 0, "ClampPosition clamps negative y")
    AssertEq(WindowFit.ClampScrollPos(5000, 1200, 600), 600, "ClampScrollPos caps at contentH - viewH")
    AssertEq(WindowFit.ClampScrollPos(-10, 1200, 600), 0, "ClampScrollPos floors at 0")
    AssertEq(WindowFit.ClampScrollPos(50, 400, 600), 0, "ClampScrollPos is 0 when content fits")

    ; ---- Finding B: real GUI, taller than any work area ----
    tg := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "WindowFit Test")
    lastBtn := 0
    Loop 60
        tg.AddEdit("x10 y" (10 + (A_Index - 1) * 40) " w300 h30", "Row " A_Index)
    lastBtn := tg.AddButton("x10 y" (10 + 60 * 40) " w120 h30", "Save")
    WindowFit.Show(tg, "AutoSize Center")
    wa := WindowFit.GetActiveWorkArea()
    tg.GetPos(&gx, &gy, &gw, &gh)
    workH := wa.b - wa.t
    AssertTrue(gh <= Floor(workH * 0.90) + 1, "Tall dialog outer height clamped to <= 90% work area (gh=" gh ", work=" workH ")")
    AssertTrue(gy >= wa.t && gy + gh <= wa.b, "Tall dialog sits fully inside work area")
    AssertTrue(WindowFit._states.Has(tg.Hwnd), "WindowFit tracks the dialog")
    st := WindowFit._states[tg.Hwnd]
    viewH := WindowFit._ViewH(tg.Hwnd)
    AssertTrue(st.contentH > viewH, "Content taller than viewport enables scrolling")
    lastBtn.GetPos(, &by0)
    WindowFit._ScrollTo(tg.Hwnd, 100000)
    lastBtn.GetPos(, &by1, , &bh1)
    AssertTrue(by1 < by0, "Scrolling to bottom moves footer button upward")
    AssertTrue(by1 + bh1 <= viewH + 4, "Footer Save button is reachable inside viewport after scroll")
    WindowFit._ScrollTo(tg.Hwnd, 0)
    lastBtn.GetPos(, &by2)
    AssertEq(by2, by0, "Scrolling back to top restores layout")
    ; short dialog stays unscrolled
    sg := Gui("+AlwaysOnTop", "WindowFit Short")
    sg.AddText(, "hello")
    WindowFit.Show(sg, "AutoSize Center")
    AssertTrue(WindowFit._states.Has(sg.Hwnd), "Short dialog tracked")
    AssertTrue(WindowFit._states[sg.Hwnd].contentH <= WindowFit._ViewH(sg.Hwnd) + 1, "Short dialog needs no scrollbar")
    tg.Destroy()
    sg.Destroy()

    ; ---- Finding A: optimistic mute rollback when OBS never confirms ----
    stt := { isMuted: true, obsConnected: false, obsWs: 0 }
    cfgObj := { obsMutedColor: "E04040", obsUnmutedColor: "40C060", writeCount: 0, IsMuted: true }
    cfgObj.DefineProp("WriteBool", { Call: (this, sec, key, val) => (this.writeCount += 1, true) })
    cfgObj.DefineProp("WriteBoolDeferred", { Call: (this, sec, key, val, delayMs := 250) => (this.writeCount += 1, true) })
    ; Remote asks to UNMUTE; host optimistically flips to live
    SyncUIState(cfgObj, stt, false, true)
    AssertEq(stt.isMuted, false, "Optimistic unmute flips indicator immediately")
    AssertEq(stt._mutePreOptimistic, true, "Pre-optimistic OBS-confirmed state remembered (muted)")
    ; OBS never confirms and is unavailable -> bounded verification rolls back
    _ReconcileHostOptimisticMute(cfgObj, stt)
    AssertEq(stt.isMuted, true, "Indicator rolls back to MUTED when OBS cannot confirm (no LIVE lie)")
    AssertTrue(!stt._optimisticMutePending, "Optimistic pending flag cleared after rollback")
    ; Explicit op:7 error path
    SyncUIState(cfgObj, stt, false, true)
    RollbackHostOptimisticMute(cfgObj, stt, "OBS returned an error")
    AssertEq(stt.isMuted, true, "op:7 failure rolls back optimistic unmute")
    ; Confirmed path leaves state alone and resets attempts
    SyncUIState(cfgObj, stt, false, true)
    SyncUIState(cfgObj, stt, false, false)
    AssertEq(stt.isMuted, false, "OBS-confirmed unmute stays LIVE")
    RollbackHostOptimisticMute(cfgObj, stt, "late timer")
    AssertEq(stt.isMuted, false, "Late rollback after confirmation is a no-op")
} catch as err {
    g_Failed++
    g_FailMessages.Push("UNCAUGHT EXCEPTION: " err.Message " (" err.File ":" err.Line ")")
}

if (g_Failed > 0) {
    for _, m in g_FailMessages
        FileAppend(m "`n", "*")
    FileAppend("M7 Audit Fixes Summary: " g_Passed " passed, " g_Failed " failed.`n", "*")
    ExitApp(1)
}

FileAppend("M7 Audit Fixes Summary: " g_Passed " passed, 0 failed.`n", "*")
ExitApp(0)
