#Requires AutoHotkey v2.0
#SingleInstance Off
; ============================================================================
; test_v930_capture_safety.ahk - M3.1 Capture Safety & C1 Extended-Display Preservation
; ============================================================================

SetWorkingDir A_ScriptDir "\.."

#Include ..\Lib\WebSocket.ahk
#Include ..\Lib\UIA.ahk
#Include ..\Lib\Crypto.ahk
#Include ..\Lib\JsonCodec.ahk
#Include ..\Lib\RemoteBridgeClient.ahk
#Include ..\Lib\Gdip.ahk
#Include ..\Lib\OBS_Network.ahk
#Include ..\Lib\GUI_Config.ahk
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

try {
    ; 1. ProtectWindow + VerifyHudProtection on live GUI windows
    g1 := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000")
    g1.Show("x-32000 y-32000 w100 h40 NoActivate")
    g2 := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000")
    g2.Show("x-32000 y-32000 w100 h40 NoActivate")

    ok1 := CaptureSafety.ProtectWindow(g1.Hwnd, true)
    ok2 := CaptureSafety.ProtectWindow(g2.Hwnd, true)
    AssertTrue(ok1 && ok2, "ProtectWindow should succeed for layered HUD GUIs")
    AssertTrue(CaptureSafety.ProtectedWindows.Has(g1.Hwnd), "ProtectedWindows should track g1")

    ver := CaptureSafety.VerifyHudProtection([g1.Hwnd, g2.Hwnd], true)
    AssertEq(ver.total, 2, "VerifyHudProtection total=2")
    AssertEq(ver.okCount, 2, "VerifyHudProtection okCount=2")
    AssertEq(ver.mismatchedCount, 0, "VerifyHudProtection mismatchedCount=0")

    ; Unprotect g2 -> removed from ProtectedWindows & verified as WDA_NONE
    CaptureSafety.ProtectWindow(g2.Hwnd, false)
    AssertTrue(!CaptureSafety.ProtectedWindows.Has(g2.Hwnd), "Unprotecting should remove from ProtectedWindows")
    verOff := CaptureSafety.VerifyHudProtection([g2.Hwnd], false)
    AssertEq(verOff.okCount, 1, "VerifyHudProtection(false) should confirm WDA_NONE")

    g1.Destroy()
    g2.Destroy()

    ; 2. C1 Extended-Display MicGui Placement Preservation
    dualRight := [
        { left: 0, top: 0, right: 1920, bottom: 1080 },
        { left: 1920, top: 0, right: 3840, bottom: 1080 }
    ]
    resExt := CaptureSafety.ClampRectToMonitors(2050, 120, 120, 40, dualRight)
    AssertEq(resExt.clamped, false, "C1: Extended Monitor 2 placement must NOT be clamped")
    AssertEq(resExt.x, 2050, "C1: Extended Monitor 2 X preserved")
    AssertEq(resExt.y, 120, "C1: Extended Monitor 2 Y preserved")

    dualLeft := [
        { left: -1920, top: 0, right: 0, bottom: 1080 },
        { left: 0, top: 0, right: 1920, bottom: 1080 }
    ]
    resNeg := CaptureSafety.ClampRectToMonitors(-1200, 100, 120, 40, dualLeft)
    AssertEq(resNeg.clamped, false, "C1: Negative-X Extended Monitor 2 placement must NOT be clamped")
    AssertEq(resNeg.x, -1200, "C1: Negative-X preserved")

    ; 3. L-shaped dead corner clamps to nearest monitor (Monitor 2), not Primary
    lShape := [
        { left: 0, top: 0, right: 1920, bottom: 1080 },
        { left: 1920, top: 0, right: 3840, bottom: 720 }
    ]
    resDead := CaptureSafety.ClampRectToMonitors(2100, 900, 120, 40, lShape)
    AssertEq(resDead.clamped, true, "L-shaped dead corner should clamp onto Monitor 2")
    AssertEq(resDead.x, 2100, "L-shaped clamp keeps X on Monitor 2")
    AssertEq(resDead.y, 680, "L-shaped clamp snaps Y to 720 - 40 = 680")

    ; 4. Unplugged Monitor 2 recovers onto Monitor 1
    singleMon := [{ left: 0, top: 0, right: 1920, bottom: 1080 }]
    resUnplug := CaptureSafety.ClampRectToMonitors(2050, 120, 120, 40, singleMon)
    AssertEq(resUnplug.clamped, true, "Unplugged Monitor 2 should recover to Monitor 1")
    AssertEq(resUnplug.x, 1800, "Unplugged Monitor 2 clamps X to 1920 - 120 = 1800")
    AssertEq(resUnplug.y, 120, "Unplugged Monitor 2 keeps valid Y=120")

} catch as err {
    g_Failed++
    g_FailMessages.Push("UNCAUGHT EXCEPTION: " err.Message " (" err.File ":" err.Line ")")
}

if (g_Failed > 0) {
    for _, m in g_FailMessages
        FileAppend(m "`n", "*")
    FileAppend("M3.1 Capture Safety Summary: " g_Passed " passed, " g_Failed " failed.`n", "*")
    ExitApp(1)
}

FileAppend("M3.1 Capture Safety Summary: " g_Passed " passed, 0 failed.`n", "*")
ExitApp(0)
