; ==============================================================================
; Test Suite: test_v820_arcade_vault.ahk
; Description: Automated verification for Milestone M2:
;              - ArcadeVault RAM-only lock, INSERT COIN normalization, zero INI
;                persistence, chord bind/unbind on Unlock/Lock, snake gating
;              - HudArcadeBase dual click-routing (0x01000000 catch-alpha +
;                WM_MOUSEACTIVATE => 3 + HWND mouse capture vs +E0x20 pass-thru),
;                GDI handle leak check, and IsReservedAudioKey collision guard
;              - Zero spoiler leakage in HelpCenter, ControlCenter, and README
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
#Include "%A_LineFile%\..\..\Lib\HudSnakeGame.ahk"
#Include "%A_LineFile%\..\..\Lib\HudArcadeBase.ahk"
#Include "%A_LineFile%\..\..\Lib\ArcadeVault.ahk"

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

Gdip.Startup()

tmpIni := A_Temp "\PresenterSync_v820_vault_" A_TickCount ".ini"
if FileExist(tmpIni)
    FileDelete(tmpIni)

cfg := Config(tmpIni)
cfg.HwMuteHotkey := "PgDn"
cfg.HwTransitionHotkey := "F8"
st := OverlayState(cfg)

; 1. Vault starts strictly locked & normalizes INSERT COIN variants
AssertTrue(ArcadeVault.IsUnlocked == false, "ArcadeVault starts strictly locked at launch")
AssertTrue(ArcadeVault.ValidatePasscode("INSERT COIN")
    && ArcadeVault.ValidatePasscode("insert coin")
    && ArcadeVault.ValidatePasscode("  InSeRt   CoIn  ")
    && ArcadeVault.ValidatePasscode("INSERTCOIN"),
    "ValidatePasscode accepts whitespace/case variations of INSERT COIN")
AssertTrue(!ArcadeVault.ValidatePasscode("") && !ArcadeVault.ValidatePasscode("WRONG") && !ArcadeVault.ValidatePasscode("INSERT"),
    "ValidatePasscode rejects invalid passcodes")

; 2. Register snake, enforce locked denial, unlock -> bind, relock -> clean unbind + zero INI persistence
mockStats := { toggled: 0, stopped: 0 }
ArcadeVault.RegisterGame("snake", "HUD Snake", "^!+F24", "Ctrl+Alt+Shift+F24", (c, s) => (mockStats.toggled += 1, HudArcadeBase.RegisterActiveGame({ Stop: (*) => (mockStats.stopped += 1, HudArcadeBase.ClearActiveGame("snake")) }, "snake"), true), (*) => (mockStats.stopped += 1))
AssertTrue(ArcadeVault.ToggleGame("snake", cfg, st) == false && mockStats.toggled == 0,
    "Locked Vault refuses ToggleGame launch")

ArcadeVault.Unlock(cfg, st, false)
AssertTrue(ArcadeVault.IsUnlocked == true && ArcadeVault._boundChords.Length == 1,
    "Unlock sets IsUnlocked=true & binds registered chords")
ArcadeVault.ToggleGame("snake", cfg, st)
AssertTrue(mockStats.toggled == 1 && HudArcadeBase.IsAnyGameActive(),
    "Unlocked Vault launches registered game & IsAnyGameActive() == true")

ArcadeVault.Lock(cfg, st, false)
AssertTrue(ArcadeVault.IsUnlocked == false && ArcadeVault._boundChords.Length == 0 && mockStats.stopped >= 1 && !HudArcadeBase.IsAnyGameActive(),
    "Instant Lock unbinds chords, stops active game & sets IsUnlocked=false")

; Confirm ZERO unlock/vault tokens written to INI
cfg.Write("Settings", "ShowIndicator", 1)
iniText := FileExist(tmpIni) ? FileRead(tmpIni, "UTF-8") : ""
AssertTrue(!InStr(iniText, "IsUnlocked") && !InStr(iniText, "ArcadeVault") && !InStr(iniText, "INSERTCOIN"),
    "Zero Vault unlock state ever persisted to INI")

; 3. Clues cycle cleanly
c1 := ArcadeVault.GetNextLockedClue()
c2 := ArcadeVault.GetNextLockedClue()
c3 := ArcadeVault.GetNextLockedClue()
AssertTrue(InStr(c1, "ACCESS DENIED") && InStr(c2, "TWO CLASSIC WORDS") && InStr(c3, "1980s ARCADE CABINET"),
    "Locked About footer cycles all 3 Sector Z clues")

; 4. HudArcadeBase dual click-routing (0x00000000 +E0x20 vs 0x01000000 + WS_EX_NOACTIVATE + WM_MOUSEACTIVATE => 3)
surfPass := HudArcadeBase.CreateSurface({ interactiveMouse: false, headless: false, title: "TestPassThru" })
AssertTrue(IsObject(surfPass) && surfPass.clearArgb == 0x00000000 && ((surfPass.exStyle & 0x20) != 0),
    "interactiveMouse=false uses +E0x20 and 0x00000000 transparent clear")
HudArcadeBase.DestroySurface(surfPass)

mouseClicks := []
surfCatch := HudArcadeBase.CreateSurface({
    interactiveMouse: true,
    cursorId: 32515,
    headless: false,
    title: "TestClickCatch",
    onMouseEvent: (msg, x, y, wp) => mouseClicks.Push({ msg: msg, x: x, y: y })
})
AssertTrue(IsObject(surfCatch)
    && surfCatch.clearArgb == 0x01000000
    && ((surfCatch.exStyle & 0x20) == 0)
    && ((surfCatch.exStyle & 0x08000000) != 0),
    "interactiveMouse=true removes +E0x20, sets WS_EX_NOACTIVATE and 0x01000000 catch-alpha")

maRes := surfCatch._mouseActFn.Call(0, 0, 0x0021, surfCatch.hwnd)
clickRes := surfCatch._mouseEvtFn.Call(0, (120 << 16) | 75, 0x0201, surfCatch.hwnd)
otherHwndRes := surfCatch._mouseActFn.Call(0, 0, 0x0021, surfCatch.hwnd + 1)
AssertTrue(maRes == 3 && clickRes == 0 && otherHwndRes = "" && mouseClicks.Length == 1 && mouseClicks[1].x == 75 && mouseClicks[1].y == 120,
    "WM_MOUSEACTIVATE returns 3 (MA_NOACTIVATE), consumes WM_LBUTTONDOWN -> 0 & delivers exact coords")

; 60-frame GDI handle leak guard on HudArcadeBase surface
hProc := DllCall("GetCurrentProcess", "Ptr")
HudArcadeBase.BeginFrame(surfCatch)
HudArcadeBase.DrawScoreboardPill(surfCatch.pGraphics, surfCatch.W, "TEST", "SCORE 100", "ESC", true, 0)
HudArcadeBase.PresentFrame(surfCatch, 220)
gdi0 := DllCall("GetGuiResources", "Ptr", hProc, "UInt", 0, "UInt")
Loop 60 {
    HudArcadeBase.BeginFrame(surfCatch)
    HudArcadeBase.DrawScoreboardPill(surfCatch.pGraphics, surfCatch.W, "TEST", "SCORE " A_Index, "ESC", true, Mod(A_Index, 2))
    HudArcadeBase.PresentFrame(surfCatch, 220)
}
gdi1 := DllCall("GetGuiResources", "Ptr", hProc, "UInt", 0, "UInt")
HudArcadeBase.DestroySurface(surfCatch)
AssertTrue(Abs(gdi1 - gdi0) <= 2, "HudArcadeBase renders 60 frames with zero GDI leaks", "before=" gdi0 " after=" gdi1)

; 5. Audio-safety reservation (HwMuteHotkey incl. aliases + HwTransitionHotkey)
AssertTrue(HudArcadeBase.IsReservedAudioKey(cfg, "PgDn")
    && HudArcadeBase.IsReservedAudioKey(cfg, "PageDown")
    && HudArcadeBase.IsReservedAudioKey(cfg, "F8")
    && !HudArcadeBase.IsReservedAudioKey(cfg, "Space"),
    "IsReservedAudioKey protects HwMuteHotkey (and aliases) + HwTransitionHotkey")

; 6. High score INI write is score-only
HudArcadeBase.SaveHighScore(cfg, "asteroids", 4250)
AssertTrue(HudArcadeBase.LoadHighScore(cfg, "asteroids") == 4250, "High score persists cleanly in [ArcadeHighScores]")

; 7. Zero chord spoiler leaks remain in HelpCenter, ControlCenter, README
helpSrc := FileRead(A_LineFile "\..\..\Lib\HelpCenter.ahk", "UTF-8")
ccSrc := FileRead(A_LineFile "\..\..\Lib\ControlCenter.ahk", "UTF-8")
readmeSrc := FileRead(A_LineFile "\..\..\README.md", "UTF-8")
remSrc := FileRead(A_LineFile "\..\..\PresenterSync_Remote.ahk", "UTF-8")
AssertTrue(!InStr(helpSrc, "Alt + Ctrl + Shift + S") && !InStr(helpSrc, "Alt+Ctrl+Shift+S")
    && !InStr(ccSrc, "Alt + Ctrl + Shift + S")
    && !InStr(readmeSrc, "Alt + Ctrl + Shift + S"),
    "All explicit Snake chord spoilers scrubbed from Help, Control Center & README")
AssertTrue(InStr(remSrc, "remoteDeckHotIfFn") && InStr(remSrc, "HudArcadeBase.IsAnyGameActive()"),
    "PresenterSync_Remote protects RemoteNextSlideKey/Prev/Transition with !HudArcadeBase.IsAnyGameActive()")

try FileDelete(tmpIni)
try FileAppend("PASS=" passed " FAIL=" failed "`n", "*")
ExitApp(failed > 0 ? 1 : 0)
