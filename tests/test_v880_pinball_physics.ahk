; ==============================================================================
; Test Suite: test_v880_pinball_physics.ahk
; Description: Automated verification for Milestone M8.1:
;              - GameSpacePinball interactiveMouse=true & 4x sub-stepping (240Hz)
;              - Plunger launch & one-way shooter gate
;              - Swept angular capsule-vs-circle flipper collision (zero tunneling)
;              - Attack Pop Bumpers, 3-bank Drop Targets, Multiplier & Rank Up
;              - 3-strike TILT nudge lockout
;              - [ArcadeHighScores] "pinball" INI persistence
;              - ArcadeVault !^+p registration in PresenterSync.ahk & Remote
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
#Include "%A_LineFile%\..\..\Lib\Arcade\GameSpacePinball.ahk"

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

tmpIni := A_Temp "\PresenterSync_v880_pinball_" A_TickCount ".ini"
if FileExist(tmpIni)
    FileDelete(tmpIni)

cfg := Config(tmpIni)
st := OverlayState(cfg)

; 1. Headless start & surface config
ok := GameSpacePinball.Start(cfg, st, true)
snap := GameSpacePinball.GetStateSnapshot()
AssertTrue(ok && GameSpacePinball.IsActive && snap.phase = "playing", "GameSpacePinball starts cleanly in headless mode")
AssertTrue(snap.interactiveMouse == true && snap.cursorId == 32512, "interactiveMouse == true and cursorId == 32512")
AssertTrue(GameSpacePinball.SUBSTEPS == 4, "4x sub-stepped 240Hz physics enabled")

; 2. Plunger launch & one-way shooter gate
GameSpacePinball.TriggerPlungerForTest(1.0)
GameSpacePinball.StepForTest(0.65)
snap := GameSpacePinball.GetStateSnapshot()
AssertTrue(!snap.ballInShooter, "Plunger launches ball over arch out of shooter lane", "x=" snap.ballX " y=" snap.ballY)

; Verify one-way gate blocks re-entry into shooter lane (x=360)
GameSpacePinball.SetBallForTest(346.0, 118.0, 520.0, 0.0, false)
GameSpacePinball.StepForTest(0.05)
snap := GameSpacePinball.GetStateSnapshot()
AssertTrue(snap.ballX <= 360.0 && snap.ballVx < 0.0, "One-way shooter gate blocks re-entry into shooter lane", "x=" snap.ballX " vx=" snap.ballVx)

; 3. Zero swept-flipper tunneling
GameSpacePinball.SetFlippersForTest(false, false)
GameSpacePinball.StepForTest(0.15)
GameSpacePinball.SetBallForTest(155.0, 616.0, 0.0, 880.0, false)
GameSpacePinball.SetFlippersForTest(true, false)
GameSpacePinball.StepForTest(0.06)
snap := GameSpacePinball.GetStateSnapshot()
AssertTrue(snap.ballVy < 0.0 && snap.ballY < 645.0, "Swept flipper capsule prevents tunneling on fast-falling ball", "y=" snap.ballY " vy=" snap.ballVy)
GameSpacePinball.SetFlippersForTest(false, false)

; 4. Attack Pop Bumper hit & score + Mission/Rank progression
scoreBefore := snap.score
GameSpacePinball.SetBallForTest(142.0, 204.0, 0.0, 250.0, false)
GameSpacePinball.StepForTest(0.04)
snap := GameSpacePinball.GetStateSnapshot()
AssertTrue(snap.score > scoreBefore, "Pop bumper collision awards score", "before=" scoreBefore " after=" snap.score)

; Trigger enough mission hits to rank up from Cadet (1) -> Ensign (2)
GameSpacePinball._AdvanceMission(6)
snap := GameSpacePinball.GetStateSnapshot()
AssertTrue(snap.rankIdx >= 2 && snap.rankName = "Ensign", "Mission progression promotes Cadet -> Ensign", "rank=" snap.rankName)

; 5. 3-bank Drop Targets reset & Multiplier increase
multBefore := snap.multiplier
GameSpacePinball.SetBallForTest(62.0, 268.0, -240.0, 0.0, false)
GameSpacePinball.StepForTest(0.04)
GameSpacePinball.SetBallForTest(62.0, 305.0, -240.0, 0.0, false)
GameSpacePinball.StepForTest(0.04)
GameSpacePinball.SetBallForTest(62.0, 342.0, -240.0, 0.0, false)
GameSpacePinball.StepForTest(0.04)
snap := GameSpacePinball.GetStateSnapshot()
AssertTrue(snap.multiplier > multBefore && snap.downDrops == 0, "Clearing 3-bank drop targets increments multiplier and resets bank", "mult=" snap.multiplier " down=" snap.downDrops)

; 6. 3-strike TILT lockout
GameSpacePinball.SetBallForTest(200.0, 350.0, 0.0, 0.0, false)
GameSpacePinball.NudgeForTest()
GameSpacePinball.NudgeForTest()
snap := GameSpacePinball.GetStateSnapshot()
AssertTrue(!snap.tilted && snap.tiltStrikes == 2, "2 nudges warn without TILT lockout", "strikes=" snap.tiltStrikes)
GameSpacePinball.NudgeForTest()
snap := GameSpacePinball.GetStateSnapshot()
AssertTrue(snap.tilted && snap.tiltStrikes >= 3, "3rd nudge triggers TILT lockout", "tilted=" snap.tilted)

; 7. High score INI persistence
savedHi := HudArcadeBase.LoadHighScore(cfg, "pinball")
AssertTrue(savedHi > 0 && savedHi == snap.highScore, "[ArcadeHighScores] pinball persisted to INI", "hi=" savedHi)

GameSpacePinball.Stop()
AssertTrue(!GameSpacePinball.IsActive && !HudArcadeBase.IsAnyGameActive(), "GameSpacePinball stops cleanly and clears active game")

; 8. Verify registration in PresenterSync.ahk & PresenterSync_Remote.ahk
hostSrc := FileRead(A_ScriptDir "\..\PresenterSync.ahk")
remSrc := FileRead(A_ScriptDir "\..\PresenterSync_Remote.ahk")
AssertTrue(InStr(hostSrc, '#Include <Arcade\GameSpacePinball>') && InStr(hostSrc, '"!^+p"'), "PresenterSync.ahk registers GameSpacePinball (!^+p)")
AssertTrue(InStr(remSrc, '#Include <Arcade\GameSpacePinball>') && InStr(remSrc, '"!^+p"'), "PresenterSync_Remote.ahk registers GameSpacePinball (!^+p)")

if FileExist(tmpIni)
    FileDelete(tmpIni)
Gdip.Shutdown()

FileAppend("test_v880_pinball_physics: PASS=" passed " FAIL=" failed "`n", "*")
ExitApp(failed > 0 ? 1 : 0)
