; ==============================================================================
; Test Suite: test_v860_missile_defense.ahk
; Description: Automated verification for Milestone M6.1:
;              - GameMissileDefense interactiveMouse=true (IDC_CROSS = 32515)
;              - Interceptor flight -> shockwave blast ring -> meteor kill +
;                escalating chain-kill multipliers (x1, x2, x3)
;              - Splitter meteor splitting mid-air into 2 child meteors
;              - Pylon hit reducing active pylons (4 -> 3) & 0 pylons -> gameover
;              - Wave completion bonus (+100 per surviving pylon)
;              - [ArcadeHighScores] "missile_defense" INI persistence
;              - ArcadeVault !^+m registration in PresenterSync.ahk & Remote
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
#Include "%A_LineFile%\..\..\Lib\Arcade\GameMissileDefense.ahk"

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

tmpIni := A_Temp "\PresenterSync_v860_missile_" A_TickCount ".ini"
if FileExist(tmpIni)
    FileDelete(tmpIni)

cfg := Config(tmpIni)
st := OverlayState(cfg)

; 1. Start headless & verify surface config
ok := GameMissileDefense.Start(cfg, st, true)
snap := GameMissileDefense.GetStateSnapshot()
AssertTrue(ok && GameMissileDefense.IsActive && snap.phase = "playing", "GameMissileDefense starts cleanly in headless mode")
AssertTrue(snap.interactiveMouse == true && snap.cursorId == 32515, "interactiveMouse == true with IDC_CROSS (32515)", "cursorId=" snap.cursorId)
AssertTrue(snap.pylonsAlive == 4 && snap.totalPylons == 4, "Starts with 4/4 active neon shield pylons")

; 2. Clear wave queue for deterministic physics tests, test interceptor -> shockwave -> chain kill
GameMissileDefense._wavePending := 0
GameMissileDefense._meteors := []
GameMissileDefense.SpawnMeteorForTest(500.0, 220.0, 0.0, 10.0, false)
GameMissileDefense.SpawnMeteorForTest(518.0, 225.0, 0.0, 10.0, false)
GameMissileDefense.FireInterceptorForTest(508.0, 225.0)
AssertTrue(GameMissileDefense.GetStateSnapshot().interceptorsCount == 1, "FireInterceptorForTest queues interceptor")

; Step enough for interceptor to reach target and detonate shockwave
GameMissileDefense.StepForTest(1.2)
snap := GameMissileDefense.GetStateSnapshot()
; Wave 2 only starts once both Wave 1 meteors are destroyed (on shorter screens, Wave 2 may already spawn its first meteor before 1.2s elapses)
AssertTrue(snap.score == 475 && snap.combo >= 2 && snap.wave == 2,
    "Shockwave blast destroys 2 meteors with chain-kill multiplier (25*1+25*2=75) + 400 wave bonus",
    "score=" snap.score " combo=" snap.combo " wave=" snap.wave " meteors=" snap.meteorsCount)

; 3. Splitter meteor forks into 2 child meteors mid-descent
GameMissileDefense._wavePending := 0
GameMissileDefense._meteors := []
GameMissileDefense._blasts := []
sp := GameMissileDefense.SpawnMeteorForTest(400.0, GameMissileDefense._surf.H * 0.40, 0.0, 120.0, true)
GameMissileDefense.StepForTest(0.25)
AssertTrue(GameMissileDefense.GetStateSnapshot().meteorsCount == 2,
    "Splitter meteor forks into 2 child meteors mid-air",
    "meteors=" GameMissileDefense.GetStateSnapshot().meteorsCount)

; 4. Meteor hitting pylon reduces active pylons (4 -> 3) and 0 pylons -> gameover
GameMissileDefense._meteors := []
p1 := GameMissileDefense._pylons[1]
GameMissileDefense.SpawnMeteorForTest(p1.x, p1.y - 8.0, 0.0, 180.0, false)
GameMissileDefense.StepForTest(0.15)
AssertTrue(GameMissileDefense.GetStateSnapshot().pylonsAlive == 3,
    "Meteor hitting pylon reduces active pylons 4 -> 3",
    "alive=" GameMissileDefense.GetStateSnapshot().pylonsAlive)

for idx, p in GameMissileDefense._pylons {
    if (p.alive) {
        GameMissileDefense.SpawnMeteorForTest(p.x, p.y - 6.0, 0.0, 200.0, false)
    }
}
GameMissileDefense.StepForTest(0.15)
snap := GameMissileDefense.GetStateSnapshot()
AssertTrue(snap.pylonsAlive == 0 && snap.phase = "gameover",
    "Losing all pylons transitions to gameover",
    "alive=" snap.pylonsAlive " phase=" snap.phase)

; 5. [ArcadeHighScores] persistence
savedHi := Integer(IniRead(tmpIni, "ArcadeHighScores", "missile_defense", "0"))
AssertTrue(savedHi >= 475, "[ArcadeHighScores] persists missile_defense high score", "savedHi=" savedHi)

GameMissileDefense.Stop()
AssertTrue(!GameMissileDefense.IsActive, "Stop() cleanly deactivates GameMissileDefense")

; 6. ArcadeVault !^+m registration in PresenterSync.ahk & PresenterSync_Remote.ahk
hostSrc := FileRead(A_ScriptDir "\..\PresenterSync.ahk", "UTF-8")
remSrc := FileRead(A_ScriptDir "\..\PresenterSync_Remote.ahk", "UTF-8")
AssertTrue(InStr(hostSrc, 'ArcadeVault.RegisterGame("missile_defense"') && InStr(hostSrc, '"!^+m"'),
    "PresenterSync.ahk registers missile_defense on !^+m")
AssertTrue(InStr(remSrc, 'ArcadeVault.RegisterGame("missile_defense"') && InStr(remSrc, '"!^+m"'),
    "PresenterSync_Remote.ahk registers missile_defense on !^+m")

if FileExist(tmpIni)
    FileDelete(tmpIni)

Gdip.Shutdown()
FileAppend("RESULT: PASS=" passed " FAIL=" failed "`n", "*")
ExitApp(failed > 0 ? 1 : 0)
