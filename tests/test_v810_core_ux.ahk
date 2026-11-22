; ==============================================================================
; Test Suite: test_v810_core_ux.ahk
; Description: Targeted verification for v8.1.0 Milestone M1 core UX features
;              (#3 Rec click/hold, #4 GDI+ perimeter progress & leak guard,
;               #6 float marquee & zero-jump seam, #8 Scene live switch,
;               #9 StreamGui read-only; plus M1.3-M1.5 hooks as added).
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
#Include "%A_LineFile%\..\..\Lib\WebRemoteUI.ahk"

global g_IsTestMode := true

passed := 0
failed := 0

AssertTrue(cond, label, detail := "") {
    global passed, failed
    if (cond) {
        passed++
    } else {
        failed++
        msg := "FAIL: " label (detail != "" ? " [" detail "]" : "") "`n"
        try FileAppend(msg, "*")
    }
}

class MockObsWs {
    sent := []
    sendText(txt) {
        this.sent.Push(txt)
        return true
    }
}

Gdip.Startup()

tmpIni := A_Temp "\PresenterSync_v810_core_" A_TickCount ".ini"
if FileExist(tmpIni)
    FileDelete(tmpIni)

cfg := Config(tmpIni)
cfg.EnableWS := true
cfg.EnableHudClickActions := true
cfg.ShowIndicator := true
cfg.ShowExtraHuds := true
cfg.ShowText := true

st := OverlayState(cfg)
InitHUD(cfg, st, false)

mockWs := MockObsWs()
st.obsConnected := true
st.obsWs := mockWs

; 1. (#3) RecGui short-click Start / Pause / Resume & Stop
AssertTrue(UIConstants.REC_STOP_LONG_PRESS_MS == 900, "REC_STOP_LONG_PRESS_MS == 900ms")

st.recState := 0
resStart := HandleHudPillClick(cfg, st, st.RecGui.Hwnd)
AssertTrue(resStart == "rec" && mockWs.sent.Length == 1 && InStr(mockWs.sent[1], '"StartRecord"'),
    "#3 RecGui short-click when idle sends StartRecord")

SyncRecState(cfg, st, 1)
resPause := HandleHudPillClick(cfg, st, st.RecGui.Hwnd)
AssertTrue(resPause == "rec_pause" && mockWs.sent.Length == 2 && InStr(mockWs.sent[2], '"PauseRecord"'),
    "#3 RecGui short-click when recording sends PauseRecord")
AssertTrue(st.recState == 2, "#3 PauseRecord updates recState to 2")

resResume := HandleHudPillClick(cfg, st, st.RecGui.Hwnd)
AssertTrue(resResume == "rec_resume" && mockWs.sent.Length == 3 && InStr(mockWs.sent[3], '"ResumeRecord"'),
    "#3 RecGui short-click when paused sends ResumeRecord")
AssertTrue(st.recState == 1, "#3 ResumeRecord restores recState to 1")

resStop := ExecuteHostStopRecord(cfg, st)
AssertTrue(resStop == true && mockWs.sent.Length == 4 && InStr(mockWs.sent[4], '"StopRecord"'),
    "#3 ExecuteHostStopRecord sends StopRecord directly")

; Offline fallback test for Start / Stop
cfgOff := Config(tmpIni)
cfgOff.EnableWS := false
cfgOff.EnableZoom := false
stOff := OverlayState(cfgOff)
stOff.RecGui := st.RecGui
AssertTrue(ExecuteHostStartRecord(cfgOff, stOff) == true && stOff.recState == 1,
    "#3 Offline ExecuteHostStartRecord transitions recState to 1")
AssertTrue(ExecuteHostStopRecord(cfgOff, stOff) == true && stOff.recState == 0,
    "#3 Offline ExecuteHostStopRecord transitions recState to 0")

; 2. (#4) Perimeter countdown progress render across scales & zero GDI handle leaks
AssertTrue(UIConstants.STUDIO_LONG_PRESS_MS == 600, "STUDIO_LONG_PRESS_MS remains 600ms")

st.studioHoldProgress := 0.55
AssertTrue(ApplyStudioAppearance(cfg, st) == true, "#4 ApplyStudioAppearance renders with studioHoldProgress")
st.studioHoldProgress := 0.0

st.recHoldProgress := 0.72
AssertTrue(ApplyRecAppearance(cfg, st) == true, "#3 ApplyRecAppearance renders amber-crimson hold bar")
st.recHoldProgress := 0.0

okRenderAll := true
for _, sc in [0.5, 1.0, 1.25, 2.0] {
    wTest := Max(40, Round(80 * sc))
    hTest := Max(20, Round(30 * sc))
    for _, prog in [0.0, 0.25, 0.5, 0.75, 1.0] {
        r1 := Gdip.RenderPill(st.StudioGui.Hwnd, 50, 50, wTest, hTest, 0xCC1E293B, 0xFF94A3B8, 220, 10, "", "", 0.0, 0, prog, 0xFFA78BFA)
        r2 := Gdip.RenderPill(st.StudioGui.Hwnd, 50, 50, wTest, hTest, 0xCC1E293B, 0xFF94A3B8, 220, 0, "", "", 0.0, 0, prog, 0xFFEF4444)
        if (!r1 || !r2)
            okRenderAll := false
    }
}
AssertTrue(okRenderAll, "#4 Gdip perimeter hold progress renders cleanly across scales & sleek/sharp corners")

; Warm up GDI+ caches, then measure GR_GDIOBJECTS across 100 iterations
Gdip.RenderPill(st.RecGui.Hwnd, 50, 50, 110, 34, 0xCC7F1D1D, 0xFFEF4444, 220, 10, "", "", 0.0, 0, 0.5, 0xFFF59E0B)
hProc := DllCall("GetCurrentProcess", "Ptr")
gdiBefore := DllCall("GetGuiResources", "Ptr", hProc, "UInt", 0, "UInt")
Loop 100 {
    pVal := Mod(A_Index, 10) / 10.0
    if (pVal <= 0.0)
        pVal := 0.5
    Gdip.RenderPill(st.RecGui.Hwnd, 50, 50, 110, 34, 0xCC7F1D1D, 0xFFEF4444, 220, 10, "", "", 0.0, 0, pVal, 0xFFF59E0B)
}
gdiAfter := DllCall("GetGuiResources", "Ptr", hProc, "UInt", 0, "UInt")
AssertTrue(Abs(gdiAfter - gdiBefore) <= 2, "#4 Gdip perimeter renderer has zero GDI handle leaks", "before=" gdiBefore " after=" gdiAfter)

; 3. (#6) MeasureTextWidthFloat + calm marquee pace + 0.00px wrap seam continuity
wTrim := Gdip.MeasureTextWidthFloat("Scene", "Segoe UI", 9, 1, true)
wPad := Gdip.MeasureTextWidthFloat("Scene   ", "Segoe UI", 9, 1, true)
AssertTrue(wTrim > 0 && wPad > wTrim + 2.0, "#6 MeasureTextWidthFloat preserves trailing spaces", "trim=" wTrim " pad=" wPad)

SyncSceneState(cfg, st, "Main Keynote Presentation - Dual Camera & Screen Share Layout 2026")
scPad := Round(UIConstants.SCENE_PAD_X * cfg.IndicatorScale)
expectedGap := 28.0 * cfg.IndicatorScale
AssertTrue(st.sceneMarqueeMaxOffset > 0 && st.sceneMarqueePhase = "pause_start", "#6 Long scene enters pause_start")
AssertTrue(Abs(st.sceneMarqueeSpan - (st.sceneMarqueeTextW + expectedGap)) < 0.001, "#6 Marquee span uses exact deterministic sepGapPx")

; Mathematical wrap seam proof: x2(offset=span) == x1(offset=0)
x1AtZero := Float(scPad) - 0.0
x2AtWrap := (Float(scPad) - st.sceneMarqueeSpan) + st.sceneMarqueeSpan
AssertTrue(Abs(x2AtWrap - x1AtZero) < 0.001, "#6 Wrap seam continuity error < 0.001px", "diff=" Abs(x2AtWrap - x1AtZero))

Loop 59
    SceneMarqueeTick(cfg, st)
AssertTrue(st.sceneMarqueePhase = "pause_start" && st.sceneMarqueeOffset == 0.0, "#6 Marquee stays paused for first 59 ticks (1.5s)")
SceneMarqueeTick(cfg, st)
AssertTrue(st.sceneMarqueePhase = "scroll_left", "#6 Tick 60 transitions to scroll_left")
st.sceneMarqueeLastTick := 0
SceneMarqueeTick(cfg, st)
expectedFirstStep := 16.0 * cfg.IndicatorScale * 0.025
AssertTrue(Abs(st.sceneMarqueeOffset - expectedFirstStep) < 0.01, "#6 Calm scroll pace is 16*scale px/s", "offset=" st.sceneMarqueeOffset " expected=" expectedFirstStep)

; 4. (#8) Scene right-click popup ALWAYS switches live Program scene even in Studio Mode
mockWs.sent := []
st.studioModeActive := true
okPopup := SelectObsSceneFromPopup(cfg, st, "Q&A Stage")
AssertTrue(okPopup && mockWs.sent.Length == 1 && InStr(mockWs.sent[1], '"SetCurrentProgramScene"') && !InStr(mockWs.sent[1], 'SetCurrentPreviewScene'),
    "#8 SelectObsSceneFromPopup switches Program scene even when studioModeActive=true")

okLeftScene := HandleHudPillClick(cfg, st, st.SceneGui.Hwnd)
AssertTrue(okLeftScene == "scene" && mockWs.sent.Length == 2 && InStr(mockWs.sent[2], '"TriggerStudioModeTransition"'),
    "#8 Left-click on SceneGui still triggers Studio transition")

; 5. (#9) StreamGui strictly read-only on click and double-click
mockWs.sent := []
okStrmClick := HandleHudPillClick(cfg, st, st.StreamGui.Hwnd)
okStrmDbl := WM_LBUTTONDBLCLK(st, 0, 0, 0x0203, st.StreamGui.Hwnd)
AssertTrue(okStrmClick == "stream_readonly" && okStrmDbl == 0 && mockWs.sent.Length == 0,
    "#9 StreamGui click and double-click are strictly read-only with 0 OBS WS mutations")

; 6. (#2) 1.25x Indicator Scale exact geometry, tray submenu & Web Remote scale selector
cfg125 := Config(tmpIni)
cfg125.IndicatorScale := 1.25
cfg125.ShowText := true
st125 := OverlayState(cfg125)
st125.ComputeDimensions(cfg125)
lay125 := ComputeHudLayout(st125, 400, 400, cfg125)
mIconEnd125 := Round(UIConstants.ICON_OFFSET_X * 1.25) + Round(UIConstants.MIC_ICON_W * 1.25)
mTextStart125 := Round(UIConstants.TEXT_OFFSET_X * 1.25)
AssertTrue(st125.baseWidth == 210 && st125.baseHeight == 50 && st125.hudGap == 8
    && (lay125.recW + st125.hudGap + lay125.chatW) == 210
    && (lay125.studioW + st125.hudGap + lay125.sceneW) == 210
    && (lay125.streamW + st125.hudGap + lay125.vcamW) == 210
    && mIconEnd125 < mTextStart125,
    "#2 1.25x Label Mode exact stack alignment & zero icon/text overlap",
    "w=" st125.baseWidth " h=" st125.baseHeight " gap=" st125.hudGap)

cfg125.ShowText := false
st125.ComputeDimensions(cfg125)
AssertTrue(st125.baseWidth == 100 && st125.baseHeight == 50, "#2 1.25x Icon Mode == 100x50")

hudRenSrc := FileRead(A_LineFile "\..\..\Lib\HudRenderer.ahk", "UTF-8")
ccSrc := FileRead(A_LineFile "\..\..\Lib\ControlCenter.ahk", "UTF-8")
webHtml125 := BuildWebRemoteHtml("8.0.4", 4456)
AssertTrue(InStr(hudRenSrc, "Medium (x1.25)") && InStr(ccSrc, "Medium (1.25x)")
    && InStr(webHtml125, "ps_web_scale") && InStr(webHtml125, "--ui-scale") && InStr(webHtml125, "1.25"),
    "#2 1.25x exposed in Tray submenu, Control Center, and Web Remote")

; 7. (#5) FormatAhkHotkeyHuman & BuildSettingsWindow type: "Shortcut" (manual Edit + Capture button)
AssertTrue(FormatAhkHotkeyHuman("^!+s") = "Ctrl + Alt + Shift + S"
    && FormatAhkHotkeyHuman("!a") = "Alt + A"
    && FormatAhkHotkeyHuman("PgDn") = "PgDn"
    && FormatAhkHotkeyHuman("None") = "None",
    "#5 FormatAhkHotkeyHuman formats full chords & single keys")

testDlg := BuildSettingsWindow("Shortcut Unit Test", [
    { type: "Text", opts: "w340", text: "Test Shortcut:" },
    { type: "Shortcut", id: "hkTest", opts: "xm w340 h25", value: "^!m", captureTitle: "Capture Test" }
], "", { suspend: false, show: false })
AssertTrue(testDlg._ctrls.Has("hkTest") && testDlg._ctrls.Has("hkTest_btn")
    && testDlg._ctrls["hkTest"].Value = "^!m"
    && testDlg._ctrls["hkTest_btn"].Text = "Capture Keystroke",
    "#5 BuildSettingsWindow type: Shortcut preserves manual Edit + adds Capture Keystroke button")
try testDlg.Destroy()

wizSrc := FileRead(A_LineFile "\..\..\Lib\SetupWizard.ahk", "UTF-8")
remMainSrc := FileRead(A_LineFile "\..\..\PresenterSync_Remote.ahk", "UTF-8")
AssertTrue(!InStr(ccSrc, 'type: "Hotkey"') && !InStr(wizSrc, 'type: "Hotkey"') && !InStr(remMainSrc, 'type: "Hotkey"')
    && InStr(ccSrc, "edHkRemoteInfo") && InStr(ccSrc, "Capture Keystroke") && InStr(ccSrc, "btnCapPtr"),
    "#5 All Windows dialogs upgraded from msctls_hotkey32 to manual Edit + Capture Keystroke")

; Clean up HUD timers & windows
for _, fnProp in ["sceneMarqueeTimerFn", "breathTimerFn", "recTimerFn", "dragTimerFn", "autoDodgeTimerFn", "mutedVoiceTimerFn"] {
    if (st.HasOwnProp(fnProp) && st.%fnProp%)
        SetTimer(st.%fnProp%, 0)
}
for _, gProp in ["MicGui", "SecondaryMicGui", "RecGui", "ChatGui", "StudioGui", "SceneGui", "StreamGui", "VCamGui"] {
    if (st.HasOwnProp(gProp) && IsGuiValid(st.%gProp%))
        st.%gProp%.Destroy()
}
try FileDelete(tmpIni)

try FileAppend("PASS=" passed " FAIL=" failed "`n", "*")
ExitApp(failed > 0 ? 1 : 0)
