; ==============================================================================
; Test Suite: test_v1020_responsive_windowfit.ahk
; Description: Verifies v10.2.0 M3 (#3) Win32 Responsive WindowFit Engine:
;              ComputeAnchoredRect math, DeferWindowPos resize scaling, Tab2
;              header recalc, Finding B scroll preservation below designMinH,
;              Close state cleanup (AUDIT-P1-06), and OperatorConsole Dark Mode
;              + responsive anchors (AUDIT-P2-04).
; ==============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
SetTimer(() => ExitApp(124), -45000)
OnError((err, mode) => (FileAppend("UNHANDLED_ERR: " err.Message " (" err.What ") at " err.File ":" err.Line "`n", "*"), ExitApp(1)))

#Include "%A_LineFile%\..\..\Lib\WebSocket.ahk"
#Include "%A_LineFile%\..\..\Lib\Crypto.ahk"
#Include "%A_LineFile%\..\..\Lib\Gdip.ahk"
#Include "%A_LineFile%\..\..\Lib\UIA.ahk"
#Include "%A_LineFile%\..\..\Lib\QrCode.ahk"
#Include "%A_LineFile%\..\..\Lib\WindowFit.ahk"
#Include "%A_LineFile%\..\..\Lib\OBS_Network.ahk"
#Include "%A_LineFile%\..\..\Lib\GUI_Config.ahk"
#Include "%A_LineFile%\..\..\Lib\OperatorConsole.ahk"

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

; 1. Pure ComputeAnchoredRect math
rStretch := WindowFit.ComputeAnchoredRect({x: 12, y: 10, w: 500, h: 200}, 600, 420, 900, 620, {W: 1, H: 1})
AssertTrue(rStretch.x == 12 && rStretch.y == 10 && rStretch.w == 800 && rStretch.h == 400, "W:1 H:1 stretches width & height accurately")

rCorner := WindowFit.ComputeAnchoredRect({x: 480, y: 370, w: 100, h: 32}, 600, 420, 900, 620, {R: 1, B: 1})
AssertTrue(rCorner.x == 780 && rCorner.y == 570 && rCorner.w == 100 && rCorner.h == 32, "R:1 B:1 pins control to bottom-right")

rCol2 := WindowFit.ComputeAnchoredRect({x: 310, y: 370, w: 280, h: 32}, 600, 420, 800, 420, {FX: 0.5, FW: 0.5, B: 1})
AssertTrue(rCol2.x == 410 && rCol2.w == 380 && rCol2.y == 370, "FX:0.5 FW:0.5 proportional column math")

rCenter := WindowFit.ComputeAnchoredRect({x: 200, y: 50, w: 200, h: 100}, 600, 400, 800, 400, {CX: 1})
AssertTrue(rCenter.x == 300 && rCenter.w == 200, "CX:1 horizontally centers control on grow")

; 2. Live GUI resize + Tab2 recalculation + Finding B floor + Close cleanup
g := Gui("+AlwaysOnTop +MaximizeBox", "M3 Responsive Test")
Theme.ApplyToWindow(g)
edSearch := g.Add("Edit", "x14 y12 w480 h26", "Search")
btnClear := g.Add("Button", "x502 y12 w84 h26", "Clear")
tabs := g.Add("Tab2", "x14 y46 w572 h300 +0x0400 -0x0200", ["General", "Advanced", "Logs"])
Theme.RegisterControl(g, tabs, "Tab")
tabs.UseTab(1)
lv := g.Add("ListView", "x26 y90 w548 h236 Grid", ["Col A", "Col B"])
tabs.UseTab()
btnLeft := g.Add("Button", "x14 y360 w180 h32", "Action 1")
btnMid := g.Add("Button", "x206 y360 w180 h32", "Action 2")
btnClose := g.Add("Button", "x398 y360 w188 h32", "Close")

WindowFit.RegisterAnchor(g, edSearch, {W: 1})
WindowFit.RegisterAnchor(g, btnClear, {R: 1})
WindowFit.RegisterAnchor(g, tabs, {W: 1, H: 1})
WindowFit.RegisterAnchor(g, lv, {W: 1, H: 1})
WindowFit.RegisterAnchor(g, btnLeft, {FX: 0.0, FW: 0.333, B: 1})
WindowFit.RegisterAnchor(g, btnMid, {FX: 0.333, FW: 0.334, B: 1})
WindowFit.RegisterAnchor(g, btnClose, {FX: 0.667, FW: 0.333, B: 1})

WindowFit.Show(g, "w600 h410 Center")
hwnd := g.Hwnd
AssertTrue(WindowFit._states.Has(hwnd), "WindowFit tracks responsive dialog")
tabs.GetPos(, , &tabW0, &tabH0)
btnClose.GetPos(&btnCloseX0, &btnCloseY0, &btnCloseW0)

; Grow window + trigger layout
g.Move(, , 880, 610)
Sleep(80)
WindowFit.ApplyResponsiveLayout(hwnd)
tabs.GetPos(, , &tabW1, &tabH1)
btnClear.GetPos(&clrX1)
btnClose.GetPos(&btnCloseX1, &btnCloseY1, &btnCloseW1)
AssertTrue(tabW1 > tabW0 + 180 && tabH1 > tabH0 + 120, "Tab2 expands both width (" tabW0 "->" tabW1 ") and height (" tabH0 "->" tabH1 ")")
AssertTrue(btnCloseY1 > btnCloseY0 + 120 && btnCloseW1 > btnCloseW0 + 40, "Footer button anchors bottom and scales proportionally")
AssertTrue(clrX1 > 650, "Top-right button tracks right edge (" clrX1 ")")
AssertTrue(Theme.RecalcTabHeaderSizes(tabs), "Theme.RecalcTabHeaderSizes succeeds on live Tab2")

; Minimize guard must not corrupt layout
WindowFit._OnSize(g, -1, 0, 0)
tabs.GetPos(, , &tabWMin)
AssertTrue(tabWMin == tabW1, "Minimize event (-1) does not collapse layout")

; Finding B shrink test: shrink below designH -> controls keep designH floor & scrollbar activates
st := WindowFit._states[hwnd]
st.designW := 600
st.designH := 600
g.Move(, , 600, 320)
Sleep(60)
WindowFit.ApplyResponsiveLayout(hwnd)
WindowFit._Refresh(hwnd)
AssertTrue(st.contentH > WindowFit._ViewH(hwnd), "Finding B vertical scrollbar activates when viewport shrinks below designH")

; Close cleanup test (AUDIT-P1-06)
WindowFit._OnCloseCleanup(g)
g.Destroy()
AssertTrue(!WindowFit._states.Has(hwnd), "WindowFit._states releases closed HWND (no leak)")

; 3. OperatorConsole Dark Theme & Responsive Anchors (AUDIT-P2-04)
tmpIni := A_Temp "\ps_v1020_m3_" A_TickCount ".ini"
if FileExist(tmpIni)
    FileDelete(tmpIni)
cfg := Config(tmpIni)
stOp := OverlayState(cfg)
stOp.suppressNudgeBanners := true
AssertTrue(OperatorConsole.Show(cfg, stOp), "OperatorConsole.Show opens")
opHwnd := OperatorConsole._gui.Hwnd
AssertTrue(OperatorConsole._gui.HasOwnProp("_isDark"), "OperatorConsole applies Theme.ApplyToWindow")
AssertTrue(WindowFit._states.Has(opHwnd) && WindowFit._states[opHwnd].responsive, "OperatorConsole enables responsive WindowFit")
OperatorConsole.Close()
AssertTrue(!WindowFit._states.Has(opHwnd) || !WinExist("ahk_id " opHwnd), "OperatorConsole closes cleanly")

try FileDelete(tmpIni)
FileAppend("PASS=" passed " FAIL=" failed "`n", "*")
ExitApp(failed > 0 ? 1 : 0)
