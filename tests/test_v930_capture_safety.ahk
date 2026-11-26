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

    ; 5. M3.2 Capture-Excluded GDI+ Micro-Toast & Zero-ToolTip() Audit
    Gdip.Startup()
    anchorGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000")
    anchorGui.Show("x120 y120 w120 h40 NoActivate")
    toastOk := ShowCaptureSafeMicroToast("M3.2 Capture-Safe Toast", 500, anchorGui.Hwnd, true)
    AssertTrue(toastOk, "ShowCaptureSafeMicroToast should render cleanly")
    AssertTrue(IsObject(CaptureSafety._MicroToastGui), "_MicroToastGui should be created")
    AssertTrue(CaptureSafety.ProtectedWindows.Has(CaptureSafety._MicroToastGui.Hwnd), "_MicroToastGui must be capture-protected")
    toastVer := CaptureSafety.VerifyHudProtection([CaptureSafety._MicroToastGui.Hwnd], true)
    AssertEq(toastVer.okCount, 1, "_MicroToastGui must have active WDA capture protection")
    HideCaptureSafeMicroToast()
    anchorGui.Destroy()
    Gdip.Shutdown()

    for _, relPath in ["PresenterSync.ahk", "PresenterSync_Remote.ahk", "Lib\HudRenderer.ahk", "Lib\OBS_Network.ahk", "Lib\ArcadeVault.ahk"] {
        srcText := FileRead(relPath, "UTF-8")
        hasToolTip := RegExMatch(srcText, "m)(?:^|[^A-Za-z0-9_])ToolTip\(")
        AssertEq(hasToolTip, 0, relPath " must contain zero native ToolTip() calls")
    }

    ; 6. M3.3 0px Flush Corner Docking, WxH Readout, Visibility Modes & Capture Banner
    m33Cfg := {
        ShowIndicator: true,
        HudVisibilityMode: "MutedOrAlert",
        savedX: 0,
        savedY: 0,
        Write: (this, s, k, v) => true
    }
    m33State := {
        isMuted: false,
        baseWidth: 120,
        baseHeight: 40,
        savedX: 0,
        savedY: 0
    }
    AssertEq(ShouldHideForMutedOrAlertMode(m33Cfg, m33State), true, "MutedOrAlert should hide when live and no alert")
    m33State.isMuted := true
    AssertEq(ShouldHideForMutedOrAlertMode(m33Cfg, m33State), false, "MutedOrAlert must show when muted")
    m33State.isMuted := false
    m33State.voiceWhileMuted := true
    AssertEq(ShouldHideForMutedOrAlertMode(m33Cfg, m33State), false, "MutedOrAlert must show on active alert")

    m33Cfg.HudVisibilityMode := "CornerTallyDot"
    m33State.voiceWhileMuted := false
    AssertEq(IsCornerTallyDotActive(m33Cfg, m33State), true, "CornerTallyDot active when live and no alert")
    m33State.isMuted := true
    AssertEq(IsCornerTallyDotActive(m33Cfg, m33State), false, "CornerTallyDot expands when muted")

    dockRes := SnapHudToCorner(m33Cfg, m33State, "BR", 0)
    AssertEq(dockRes.w, 120, "SnapHudToCorner width=120")
    AssertEq(dockRes.h, 40, "SnapHudToCorner height=40")
    AssertTrue(m33Cfg.HasOwnProp("savedXRatio") && m33Cfg.savedXRatio != "" && m33Cfg.HasOwnProp("savedYRatio") && m33Cfg.savedYRatio != "", "P2-5: SnapHudToCorner updates savedXRatio/savedYRatio cleanly")
    snapIni := A_Temp "\ps_snap_ini_" A_TickCount ".ini"
    try FileDelete(snapIni)
    snapCfg := Config(snapIni)
    SnapHudToCorner(snapCfg, m33State, "TL", 0)
    AssertTrue(IniRead(snapIni, "Position", "XRatio", "") != "" && IniRead(snapIni, "Position", "YRatio", "") != "", "P2-5: SnapHudToCorner writes XRatio/YRatio to INI")
    try FileDelete(snapIni)
    readout := GetHudPixelReadout(m33Cfg, m33State)
    AssertTrue(InStr(readout, "120×40 px @ (") > 0, "GetHudPixelReadout formats WxH px @ (X, Y)")

    banner19041 := CaptureSafety.GetCaptureSafetyBannerText(true, 22631)
    AssertTrue(InStr(banner19041, "WDA_EXCLUDEFROMCAPTURE") > 0 && InStr(banner19041, "NDI") > 0, "Banner mentions 19041+ and NDI tip")
    bannerLegacy := CaptureSafety.GetCaptureSafetyBannerText(true, 18363)
    AssertTrue(InStr(bannerLegacy, "WDA_MONITOR") > 0, "Banner mentions WDA_MONITOR for pre-19041")

    ; v10.1.0 V2-M2 regressions (P0-5, P1-7, P1-8, P2-4, #1, #6)
    pinBox := { calls: 0 }
    pinOk := OpenSetClearKioskPinDialog(m33Cfg, m33State, (p, t, a := false) => (pinBox.calls += 1, { Result: "OK", Value: "4829" }))
    AssertTrue(pinOk && m33Cfg.KioskPin = "4829" && pinBox.calls == 1, "P0-5: OpenSetClearKioskPinDialog sets KioskPin cleanly")
    clrOk := OpenSetClearKioskPinDialog(m33Cfg, m33State, (p, t, a := false) => (InStr(p, "current") ? { Result: "OK", Value: "4829" } : { Result: "OK", Value: "" }))
    AssertTrue(clrOk && m33Cfg.KioskPin = "", "P0-5: OpenSetClearKioskPinDialog verifies current PIN before clearing")

    ccSrc := FileRead(A_ScriptDir "\..\Lib\ControlCenter.ahk", "UTF-8")
    AssertTrue(InStr(ccSrc, "PromptKioskPinModal(") > 0 && !InStr(ccSrc, 'InputBox("Enter Kiosk PIN'), "P0-5: ControlCenter uses capture-excluded PromptKioskPinModal instead of native InputBox")

    dlSrc := FileRead(A_ScriptDir "\..\Lib\DiagnosticLogger.ahk", "UTF-8")
    AssertTrue(InStr(dlSrc, 'WindowFit.Show(vGui, "w804 h518 Center")') > 0, "P2-4: DiagnosticLogger uses WindowFit.Show")

    hrSrc := FileRead(A_ScriptDir "\..\Lib\HudRenderer.ahk", "UTF-8")
    AssertTrue(InStr(hrSrc, "IsCornerTallyDotActive(cfg, state)") > 0 && InStr(hrSrc, "dotSz") > 0 && InStr(hrSrc, 'UpdateHudVisibility(cfg, state)') > 0, "P1-7: HudRenderer wires CornerTallyDot compact mode and SyncUIState visibility updates")
    AssertTrue(InStr(hrSrc, "sceneHoldProgress") > 0 && InStr(hrSrc, "ExecuteHostResetActiveScene(cfg, state)") > 0 && InStr(hrSrc, "0xFF06B6D4") > 0, "#1: Primary SceneGui renders cyan hold ring and triggers ExecuteHostResetActiveScene")

    remSrc := FileRead(A_ScriptDir "\..\PresenterSync_Remote.ahk", "UTF-8")
    AssertTrue(InStr(remSrc, "ShowSceneIndicator") > 0 && InStr(remSrc, "ScenePosition") > 0 && InStr(remSrc, "ApplyRemoteSceneAppearance") > 0 && InStr(remSrc, "SendRemoteResetActiveScene") > 0 && InStr(remSrc, "ShowRemoteSceneSwitcherMenu") > 0, "#6: Windows Remote implements standalone toggleable Scene HUD with marquee, hold reset, and scene switcher menu")
    AssertTrue(InStr(remSrc, 'ev.kind = "session_reset"') > 0 && InStr(remSrc, '"no_target_scene"') > 0 && InStr(remSrc, "state.usingBridge") > 0 && InStr(remSrc, "PromptKioskPinModal(") > 0, "P1-2/P1-8/P0-5: Windows Remote handles session_reset, full NACK toasts, real Tracer props, and PromptKioskPinModal")

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
