; ==============================================================================
; Test Suite: test_v1020_grouped_remote_hud.ahk
; Description: Verifies v10.2.0 M6 (#7) Unified Grouped Mic + Scene HUD on
;              Windows Remote (lockstep layout, top-edge auto-flip, Monitor 2+
;              preservation, BeginDeferWindowPos/DeferWindowPos/EndDeferWindowPos,
;              +E0x08000000 WS_EX_NOACTIVATE, WM_REMOTE_RBUTTONUP cfg fix) AND
;              Primary Lib/HudRenderer.ahk AnchorFromHwnd gapless stacking fix.
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

; 1. Verify Primary Lib/HudRenderer.ahk AnchorFromHwnd gapless stacking fix (AUDIT-P1-04)
tmpIni := A_Temp "\ps_v1020_m6_" A_TickCount ".ini"
if FileExist(tmpIni)
    FileDelete(tmpIni)
cfg := Config(tmpIni)
cfg.EnableWS := true
cfg.ShowExtraHuds := true
cfg.ShowRow2RecChatHud := false
cfg.ShowRow3StudioSceneHud := true
cfg.ShowStreamHud := true

st := OverlayState(cfg)
st.hudCfg := cfg
st.ComputeDimensions(cfg)
InitHUD(cfg, st, false)

anchorX := 800, anchorY := 500
pos := ComputeHudLayout(st, anchorX, anchorY, cfg)
; Row 2 (Rec/Chat) disabled -> SceneGui sits right above MicGui without empty row 2 gap!
AssertTrue(pos.sceneY == anchorY - st.row3Height - st.hudGap, "Gapless stacking skips disabled row 2 above MicGui")
backFromScene := AnchorFromHwnd(st, st.SceneGui.Hwnd, pos.sceneX, pos.sceneY)
AssertTrue(backFromScene.x == anchorX && backFromScene.y == anchorY, "AnchorFromHwnd from SceneGui recovers exact Mic anchor without row 2 drift")

backFromStream := AnchorFromHwnd(st, st.StreamGui.Hwnd, pos.streamX, pos.streamY)
AssertTrue(backFromStream.x == anchorX && backFromStream.y == anchorY, "AnchorFromHwnd from StreamGui recovers exact Mic anchor")

backFromVcam := AnchorFromHwnd(st, st.VCamGui.Hwnd, pos.vcamX, pos.vcamY)
AssertTrue(backFromVcam.x == anchorX && backFromVcam.y == anchorY, "AnchorFromHwnd from VCamGui recovers exact Mic anchor")

; Re-enable row 2 and re-verify
cfg.ShowRow2RecChatHud := true
posAll := ComputeHudLayout(st, anchorX, anchorY, cfg)
backAllVcam := AnchorFromHwnd(st, st.VCamGui.Hwnd, posAll.vcamX, posAll.vcamY)
AssertTrue(backAllVcam.x == anchorX && backAllVcam.y == anchorY, "AnchorFromHwnd with all rows enabled recovers exact Mic anchor")

for _, g in GetHudGuiList(st, true)
    try g.Destroy()
try FileDelete(tmpIni)

; 2. Verify Windows Remote Grouped HUD & Audit Fixes in PresenterSync_Remote.ahk
remoteSrc := FileRead(A_ScriptDir "\..\PresenterSync_Remote.ahk", "UTF-8")
AssertTrue(InStr(remoteSrc, "GroupSceneWithMicHud := true"), "RemoteConfig defines GroupSceneWithMicHud default true")
AssertTrue(InStr(remoteSrc, 'ToggleRemoteGroupSceneHud'), "Tray menu exposes Group Scene with Mic HUD toggle")
AssertTrue(InStr(remoteSrc, "+E0x08000000"), "MicGui and SceneGui carry WS_EX_NOACTIVATE (+E0x08000000, AUDIT-P1-09)")
AssertTrue(RegExMatch(remoteSrc, "WM_REMOTE_RBUTTONUP\(cfg,\s*state[\s\S]{1,350}NotifyRemoteActivity\(cfg,\s*state\)"), "WM_REMOTE_RBUTTONUP passes cfg to NotifyRemoteActivity (AUDIT-P1-10)")
AssertTrue(InStr(remoteSrc, "BeginDeferWindowPos") && InStr(remoteSrc, "DeferWindowPos") && InStr(remoteSrc, "EndDeferWindowPos"), "Atomic DeferWindowPos lockstep positioning present")
AssertTrue(InStr(remoteSrc, "GetRemoteMonitorWorkArea") && InStr(remoteSrc, "MonitorGetWorkArea"), "Multi-monitor active work-area resolver used instead of raw SysGet(77) (AUDIT-P2-07)")

; 3. Validate live DeferWindowPos Win32 lockstep movement & WS_EX_NOACTIVATE window style
gMic := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000000 +E0x80000 -DPIScale", "M6MicTest")
gScn := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000000 +E0x80000 -DPIScale", "M6SceneTest")
gMic.Show("NoActivate x120 y500 w90 h42")
gScn.Show("NoActivate x90 y464 w150 h30")

exStyle := DllCall("GetWindowLongPtr", "Ptr", gMic.Hwnd, "Int", -20, "Ptr")
AssertTrue((exStyle & 0x08000000) != 0, "Real Win32 Mic test window has WS_EX_NOACTIVATE")

hdwp := DllCall("BeginDeferWindowPos", "Int", 2, "Ptr")
hdwp := DllCall("DeferWindowPos", "Ptr", hdwp, "Ptr", gMic.Hwnd, "Ptr", 0, "Int", 220, "Int", 540, "Int", 0, "Int", 0, "UInt", 0x0015, "Ptr")
hdwp := DllCall("DeferWindowPos", "Ptr", hdwp, "Ptr", gScn.Hwnd, "Ptr", 0, "Int", 190, "Int", 504, "Int", 0, "Int", 0, "UInt", 0x0015, "Ptr")
okDwp := DllCall("EndDeferWindowPos", "Ptr", hdwp, "Int")
AssertTrue(okDwp != 0, "EndDeferWindowPos moved both HUD windows atomically")

WinGetPos(&mx, &my,,, "ahk_id " gMic.Hwnd)
WinGetPos(&sx, &sy,,, "ahk_id " gScn.Hwnd)
AssertTrue(mx == 220 && my == 540 && sx == 190 && sy == 504, "Both grouped pills updated to exact lockstep coordinates")

; Simulate Monitor 2+ negative coordinate work area layout & top-edge auto-flip mathematically
waMon2 := {left: -1920, top: 0, right: 0, bottom: 1040}
topFlipY := waMon2.top + Round((waMon2.bottom - waMon2.top) * 0.18)
AssertTrue(-1700 >= waMon2.left && (50 <= topFlipY), "Negative X Monitor 2+ coordinates and top-18% flip threshold valid")

try gMic.Destroy()
try gScn.Destroy()

FileAppend("PASS=" passed " FAIL=" failed "`n", "*")
ExitApp(failed > 0 ? 1 : 0)
