; ==============================================================================
; Test Suite: test_v870_block_drop.ahk
; Description: Automated verification for Milestone M7.1:
;              - GameBlockDrop interactiveMouse=false (+E0x20 click-through)
;              - 7-bag randomizer contains all 7 unique kinds in every 7 draws
;              - SRS wall-kick succeeds when rotating against left/right wall
;                (I and T pieces)
;              - Hold swaps piece and blocks double-hold until lock
;              - Ghost Y lands strictly at lowest valid row
;              - Hard Drop locks and clears 1-line & 4-line Tetris with
;                level/score increase
;              - [ArcadeHighScores] "block_drop" INI persistence
;              - ArcadeVault !^+d registration in PresenterSync.ahk & Remote
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
#Include "%A_LineFile%\..\..\Lib\Arcade\GameBlockDrop.ahk"

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

tmpIni := A_Temp "\PresenterSync_v870_blockdrop_" A_TickCount ".ini"
if FileExist(tmpIni)
    FileDelete(tmpIni)

cfg := Config(tmpIni)
st := OverlayState(cfg)

; 1. Start headless & verify surface config
ok := GameBlockDrop.Start(cfg, st, true)
snap := GameBlockDrop.GetStateSnapshot()
AssertTrue(ok && GameBlockDrop.IsActive && snap.phase = "playing", "GameBlockDrop starts cleanly in headless mode")
AssertTrue(snap.interactiveMouse == false, "interactiveMouse == false (+E0x20 click-through)")
AssertTrue(snap.next3.Length == 3 && snap.next3[1] != "" && snap.next3[2] != "" && snap.next3[3] != "", "Next 3 preview populated")

; 2. 7-bag randomizer: every 7 draws from a fresh bag yields all 7 unique kinds
GameBlockDrop._bag := []
Loop 2 {
    seen := Map()
    Loop 7 {
        k := GameBlockDrop.DrawBagForTest()
        seen[k] := true
    }
    AssertTrue(seen.Count == 7, "7-bag draw #" A_Index " contains all 7 unique tetrominoes", "count=" seen.Count)
}

; 3. SRS Wall-Kick: I piece rotating against left & right wall, T piece against left wall
GameBlockDrop.SpawnPieceForTest("I", -2, 5, 1) ; vertical I at col 0
okKickIL := GameBlockDrop.RotateForTest(-1)     ; 1 -> 0 kicks (+2, 0) to x=0
snap := GameBlockDrop.GetStateSnapshot()
AssertTrue(okKickIL && snap.curRot == 0 && snap.curX == 0,
    "SRS wall-kick succeeds for I piece against left wall (1->0)",
    "ok=" okKickIL " rot=" snap.curRot " x=" snap.curX)

GameBlockDrop.SpawnPieceForTest("I", 8, 5, 3)  ; vertical I at col 9
okKickIR := GameBlockDrop.RotateForTest(-1)     ; 3 -> 2 kicks (-2, 0) to x=6
snap := GameBlockDrop.GetStateSnapshot()
AssertTrue(okKickIR && snap.curRot == 2 && snap.curX == 6,
    "SRS wall-kick succeeds for I piece against right wall (3->2)",
    "ok=" okKickIR " rot=" snap.curRot " x=" snap.curX)

GameBlockDrop.SpawnPieceForTest("T", -1, 5, 1) ; T at left wall (cells at col 0,1)
okKickTL := GameBlockDrop.RotateForTest(-1)     ; 1 -> 0 kicks (+1, 0) to x=0
snap := GameBlockDrop.GetStateSnapshot()
AssertTrue(okKickTL && snap.curRot == 0 && snap.curX == 0,
    "SRS wall-kick succeeds for T piece against left wall (1->0)",
    "ok=" okKickTL " rot=" snap.curRot " x=" snap.curX)

; 4. Hold swaps piece and blocks double-hold until lock
GameBlockDrop._ResetMatch()
firstKind := GameBlockDrop.GetStateSnapshot().curKind
nextKind := GameBlockDrop.GetStateSnapshot().next3[1]
okHold1 := GameBlockDrop.HoldForTest()
snap := GameBlockDrop.GetStateSnapshot()
AssertTrue(okHold1 && snap.holdKind = firstKind && snap.curKind = nextKind && snap.holdUsed,
    "Hold stores current piece and spawns next piece")
okHold2 := GameBlockDrop.HoldForTest()
AssertTrue(!okHold2 && GameBlockDrop.GetStateSnapshot().curKind = nextKind,
    "Double-hold is blocked until piece locks")

; 5. Ghost Y lands strictly at lowest valid row
GameBlockDrop._ResetMatch()
GameBlockDrop.SpawnPieceForTest("O", 4, 0, 0) ; O cells at row +0 and +1 -> lowest valid y is 18
gy := GameBlockDrop.ComputeGhostYForTest()
AssertTrue(gy == 18, "Ghost Y lands strictly at lowest valid row (18 for O on empty board)", "ghostY=" gy)

; 6. Hard Drop locks and clears 1-line & 4-line Tetris with level/score increase
GameBlockDrop._ResetMatch()
GameBlockDrop.FillRowForTest(19, 0)
GameBlockDrop.SpawnPieceForTest("I", -2, 0, 1) ; vertical I at col 0; cell (2,3) reaches row 19 at y=16 -> Wait: I at rot=1 has cells (2,0..3), so at x=-2 col=0, rows 16..19 when y=16
; Let's fill rows 16..19 leaving col 0 empty for a clean 4-line Tetris!
GameBlockDrop.FillRowForTest(18, 0)
GameBlockDrop.FillRowForTest(17, 0)
GameBlockDrop.FillRowForTest(16, 0)
GameBlockDrop.HardDropForTest()
snap := GameBlockDrop.GetStateSnapshot()
AssertTrue(snap.lines == 4 && snap.score >= 800,
    "Hard Drop vertical I into 4-row gap scores 4-line Tetris",
    "lines=" snap.lines " score=" snap.score)

; Clear 6 more single lines to reach 10 lines -> Level 2
Loop 6 {
    col := A_Index
    GameBlockDrop.FillRowForTest(19, col)
    GameBlockDrop.SpawnPieceForTest("I", col - 2, 0, 1)
    GameBlockDrop.HardDropForTest()
}
snap := GameBlockDrop.GetStateSnapshot()
AssertTrue(snap.lines >= 10 && snap.level >= 2,
    "Clearing 10+ lines advances to Level 2",
    "lines=" snap.lines " level=" snap.level)

; 7. [ArcadeHighScores] persistence (save on gameover)
GameBlockDrop._TriggerGameOver()
savedHi := Integer(IniRead(tmpIni, "ArcadeHighScores", "block_drop", "0"))
AssertTrue(savedHi >= 800, "[ArcadeHighScores] persists block_drop high score", "savedHi=" savedHi)

GameBlockDrop.Stop()
AssertTrue(!GameBlockDrop.IsActive, "Stop() cleanly deactivates GameBlockDrop")

; 8. ArcadeVault !^+d registration in PresenterSync.ahk & PresenterSync_Remote.ahk
hostSrc := FileRead(A_ScriptDir "\..\PresenterSync.ahk", "UTF-8")
remSrc := FileRead(A_ScriptDir "\..\PresenterSync_Remote.ahk", "UTF-8")
AssertTrue(InStr(hostSrc, 'ArcadeVault.RegisterGame("block_drop"') && InStr(hostSrc, '"!^+d"'),
    "PresenterSync.ahk registers block_drop on !^+d")
AssertTrue(InStr(remSrc, 'ArcadeVault.RegisterGame("block_drop"') && InStr(remSrc, '"!^+d"'),
    "PresenterSync_Remote.ahk registers block_drop on !^+d")

if FileExist(tmpIni)
    FileDelete(tmpIni)

Gdip.Shutdown()
FileAppend("RESULT: PASS=" passed " FAIL=" failed "`n", "*")
ExitApp(failed > 0 ? 1 : 0)
