; ==============================================================================
; Test Suite: test_v850_pacgrid_tron.ahk
; Description: Automated headless verification for Milestone M5.1 (v8.4.1):
;              - GameLightCycles (^!+t, "tron"):
;                * Grid movement & 180-degree self-reversal rejection
;                * Turbo Boost speed multiplication & charge drain/recharge
;                * Flood-fill / longest-corridor AI avoiding blocked cells
;                * Trail collision -> game over & round win progression
;                * [ArcadeHighScores] "tron" persistence
;              - GamePacGrid (^!+c, "pac_grid"):
;                * 28x31 maze pellet (+10) & Power Orb (+50) consumption
;                * Frightened Mode (7.0s) escalating combos 200 -> 400 -> 800 -> 1600
;                * Eaten chaser transitioning to "eyes" & regenerating at ghost pen
;                * All 4 distinct chaser target calculations (blinky, pinky, inky, clyde)
;                * Scatter <-> Chase wave transitions (7s -> 20s -> 7s -> 20s)
;                * Left/right warp tunnel wrap (col 0 <-> 27) & chaser tunnel slowdown
;                * Timed Bonus Neon Fruit spawn at 70 & 170 dots eaten
;                * Smooth queued turn buffering (_nextDir applied at valid intersection)
;                * [ArcadeHighScores] "pac_grid" persistence
;              - ArcadeVault registration for !^+t and !^+c
; ==============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

global g_IsTestMode := true

#Include "%A_ScriptDir%\..\Lib\GUI_Config.ahk"
#Include "%A_ScriptDir%\..\Lib\HudArcadeBase.ahk"
#Include "%A_ScriptDir%\..\Lib\ArcadeVault.ahk"
#Include "%A_ScriptDir%\..\Lib\Arcade\GameGridMazePack.ahk"

class MockArcadeConfig {
    HwMuteHotkey := "F8"
    HwTransitionHotkey := "F9"
    _store := Map()

    Read(section, key, defaultVal := 0) {
        k := section ":" key
        return this._store.Has(k) ? this._store[k] : defaultVal
    }

    Write(section, key, val) {
        this._store[section ":" key] := val
        return true
    }
}

global g_Pass := 0
global g_Fail := 0
global g_Log := ""

AssertEq(actual, expected, label) {
    global g_Pass, g_Fail, g_Log
    if (actual == expected) {
        g_Pass += 1
        g_Log .= "[PASS] " label "`n"
    } else {
        g_Fail += 1
        g_Log .= "[FAIL] " label " (expected=" String(expected) ", actual=" String(actual) ")`n"
    }
}

AssertTrue(cond, label) {
    AssertEq(!!cond, true, label)
}

cfg := MockArcadeConfig()
state := { isMuted: true }

; --- 0. Version Check ---
AssertEq(UIConstants.APP_VERSION, "8.5.0", "UIConstants.APP_VERSION is 8.5.0")

; ==============================================================================
; 1. NEON LIGHT CYCLES (TRON) TESTS
; ==============================================================================
AssertTrue(GameLightCycles.Start(cfg, state, true), "GameLightCycles headless Start succeeds")
snap0 := GameLightCycles.GetStateSnapshot()
AssertEq(snap0.active, true, "TRON active after Start")
AssertEq(snap0.phase, "playing", "TRON phase is playing")
AssertEq(snap0.cols, 80, "TRON grid cols == 80")
AssertEq(snap0.rows, 48, "TRON grid rows == 48")
startCol := snap0.playerCol
startRow := snap0.playerRow

; 1a. Grid movement & 180-degree self-reversal protection
AssertEq(GameLightCycles.QueueTurnForTest(-1, 0), false, "TRON rejects 180-degree self-reversal against +X heading")
GameLightCycles.StepForTest(0.10)
snap1 := GameLightCycles.GetStateSnapshot()
AssertTrue(snap1.playerCol > startCol, "TRON player moves forward along +X grid")
AssertEq(snap1.playerRow, startRow, "TRON player stays on initial row before turn")

; Queue vertical turn (0, -1) and step
AssertEq(GameLightCycles.QueueTurnForTest(0, -1), true, "TRON accepts 90-degree turn (0, -1)")
GameLightCycles.StepForTest(0.10)
snapTurn := GameLightCycles.GetStateSnapshot()
AssertTrue(snapTurn.playerRow < startRow, "TRON player moves upward after queued turn")

; 1b. Turbo Boost speed multiplication & charge drain/recharge
GameLightCycles.Stop()
GameLightCycles.Start(cfg, state, true)
cBeforeNormal := GameLightCycles.GetStateSnapshot().playerCol
GameLightCycles.StepForTest(0.10)
normalDelta := GameLightCycles.GetStateSnapshot().playerCol - cBeforeNormal

GameLightCycles.Stop()
GameLightCycles.Start(cfg, state, true)
cBeforeBoost := GameLightCycles.GetStateSnapshot().playerCol
AssertTrue(GameLightCycles.SetBoostForTest(true), "TRON SetBoostForTest(true) activates boost")
GameLightCycles.StepForTest(0.10)
snapBoost := GameLightCycles.GetStateSnapshot()
boostDelta := snapBoost.playerCol - cBeforeBoost
AssertTrue(boostDelta > normalDelta, "TRON Turbo Boost multiplies step speed (" boostDelta " > " normalDelta ")")
AssertTrue(snapBoost.boostCharge < 100.0, "TRON Turbo Boost drains boost charge while active")

drainedCharge := snapBoost.boostCharge
GameLightCycles.SetBoostForTest(false)
GameLightCycles.StepForTest(0.10)
snapRecharge := GameLightCycles.GetStateSnapshot()
AssertTrue(snapRecharge.boostCharge > drainedCharge, "TRON Turbo Boost recharges when released")

; 1c. Flood-fill AI avoiding blocked cells
GameLightCycles.SetCyclesForTest(10, 20, 1, 0, 50, 20, -1, 0)
; Block straight ahead of AI at (49, 20) and above AI at (50, 19), leaving down (50, 21) open
GameLightCycles.ForceOccupiedForTest(49, 20, 1)
GameLightCycles.ForceOccupiedForTest(50, 19, 1)
aiChoice := GameLightCycles.ChooseAiDirForTest()
AssertEq(aiChoice.dx, 0, "TRON flood-fill AI avoids blocked straight cell (dx=0)")
AssertEq(aiChoice.dy, 1, "TRON flood-fill AI steers into open downward corridor (dy=1)")
AssertTrue(aiChoice.freeCells > 10, "TRON flood-fill AI evaluates reachable free cells")

; 1d. Trail collision -> game over & [ArcadeHighScores] "tron" persistence
savedTronBest := cfg.Read("ArcadeHighScores", "tron", 0)
AssertTrue(savedTronBest > 0, "TRON saves high score to [ArcadeHighScores] tron")
pNow := GameLightCycles.GetStateSnapshot()
GameLightCycles.ForceOccupiedForTest(pNow.playerCol + pNow.playerDx, pNow.playerRow + pNow.playerDy, 2)
GameLightCycles.StepForTest(0.10)
AssertEq(GameLightCycles.GetStateSnapshot().phase, "gameover", "TRON trail collision triggers gameover phase")
GameLightCycles.Stop()

; ==============================================================================
; 2. NEON PAC-GRID (AUTHENTIC PAC-MAN MECHANICS) TESTS
; ==============================================================================
AssertTrue(GamePacGrid.Start(cfg, state, true), "GamePacGrid headless Start succeeds")
ps0 := GamePacGrid.GetStateSnapshot()
AssertEq(ps0.active, true, "Pac-Grid active after Start")
AssertEq(ps0.cols, 28, "Pac-Grid maze cols == 28")
AssertEq(ps0.rows, 31, "Pac-Grid maze rows == 31")
AssertEq(ps0.lives, 3, "Pac-Grid starts with 3 lives")
AssertTrue(ps0.totalLevelDots > 180, "Pac-Grid 28x31 symmetric maze has > 180 pellets/orbs")

; 2a. Standard pellet (+10) consumption
GamePacGrid.SetRunnerForTest(2, 1, 1, 0)
scoreBeforePellet := GamePacGrid.GetStateSnapshot().score
dotsBeforePellet := GamePacGrid.GetStateSnapshot().dotsEaten
GamePacGrid.StepForTest(0.12)
psPellet := GamePacGrid.GetStateSnapshot()
AssertTrue(psPellet.score >= scoreBeforePellet + 10, "Pac-Grid pellet consumption adds +10 points")
AssertTrue(psPellet.dotsEaten > dotsBeforePellet, "Pac-Grid pellet consumption increments dotsEaten")

; 2b. Power Orb (+50), Frightened Mode (7.0s), escalating chaser combos (200 -> 400 -> 800 -> 1600)
frightSec := GamePacGrid.EatPowerOrbForTest()
AssertEq(Round(frightSec), 7, "Pac-Grid Power Orb triggers 7.0s Frightened Mode")
psFright := GamePacGrid.GetStateSnapshot()
AssertEq(psFright.chasers[1].state, "frightened", "Pac-Grid chaser 1 enters frightened state")

c1Pts := GamePacGrid.EatChaserForTest(1)
c2Pts := GamePacGrid.EatChaserForTest(2)
c3Pts := GamePacGrid.EatChaserForTest(3)
c4Pts := GamePacGrid.EatChaserForTest(4)
AssertEq(c1Pts, 200, "Pac-Grid 1st eaten chaser awards 200 points")
AssertEq(c2Pts, 400, "Pac-Grid 2nd eaten chaser awards 400 points")
AssertEq(c3Pts, 800, "Pac-Grid 3rd eaten chaser awards 800 points")
AssertEq(c4Pts, 1600, "Pac-Grid 4th eaten chaser awards 1600 points")

; 2c. Eaten chaser transitions to "eyes" and regenerates at central ghost pen (col=13..14, row=14)
psEyes := GamePacGrid.GetStateSnapshot()
AssertEq(psEyes.chasers[1].state, "eyes", "Pac-Grid eaten chaser transitions to returning eyes state")
GamePacGrid.SetChaserForTest(1, 13, 14, 0, 1, "eyes")
GamePacGrid.StepForTest(0.12)
psRegen := GamePacGrid.GetStateSnapshot()
AssertTrue(psRegen.chasers[1].state != "eyes", "Pac-Grid returning eyes regenerate at central ghost pen (13, 14)")

; 2d. All 4 distinct chaser target calculations (blinky, pinky, inky, clyde)
GamePacGrid.SetRunnerForTest(10, 15, 1, 0)
GamePacGrid.SetChaserForTest(1, 8, 15, 1, 0, "chase") ; Blinky at (8, 15)

tBlinky := GamePacGrid.ComputeChaserTargetForTest("blinky")
AssertEq(tBlinky.col, 10, "Blinky targets runner exact col (10)")
AssertEq(tBlinky.row, 15, "Blinky targets runner exact row (15)")

tPinky := GamePacGrid.ComputeChaserTargetForTest("pinky")
AssertEq(tPinky.col, 14, "Pinky targets 4 tiles ahead of runner col (10 + 4 = 14)")
AssertEq(tPinky.row, 15, "Pinky targets 4 tiles ahead of runner row (15)")

tInky := GamePacGrid.ComputeChaserTargetForTest("inky")
; Pivot is 2 tiles ahead of runner: (12, 15). Vector from Blinky (8, 15) doubled: 2*12 - 8 = 16, 2*15 - 15 = 15
AssertEq(tInky.col, 16, "Inky reflects Blinky through 2 tiles ahead of runner (2*12 - 8 = 16)")
AssertEq(tInky.row, 15, "Inky target row matches reflected vector (15)")

; Clyde when Euclidean distance > 8 tiles -> targets runner (10, 15)
GamePacGrid.SetChaserForTest(4, 1, 1, 1, 0, "chase")
tClydeFar := GamePacGrid.ComputeChaserTargetForTest("clyde")
AssertEq(tClydeFar.col, 10, "Clyde targets runner col when distance > 8 tiles")
AssertEq(tClydeFar.row, 15, "Clyde targets runner row when distance > 8 tiles")

; Clyde when Euclidean distance <= 8 tiles -> targets bottom-left scatter corner (0, 30)
GamePacGrid.SetChaserForTest(4, 12, 15, -1, 0, "chase")
tClydeNear := GamePacGrid.ComputeChaserTargetForTest("clyde")
AssertEq(tClydeNear.col, 0, "Clyde targets bottom-left scatter corner col (0) when distance <= 8")
AssertEq(tClydeNear.row, 30, "Clyde targets bottom-left scatter corner row (30) when distance <= 8")

; 2e. Timed Scatter <-> Chase wave transitions (7s Scatter -> 20s Chase -> 7s Scatter)
GamePacGrid.Stop()
GamePacGrid.Start(cfg, state, true)
AssertEq(GamePacGrid.GetStateSnapshot().waveMode, "scatter", "Pac-Grid begins in 7s Scatter wave phase")
; Advance 7.2s (in 0.5s steps) to cross 7.0s Scatter -> Chase boundary
Loop 15
    GamePacGrid.StepForTest(0.5)
psWave2 := GamePacGrid.GetStateSnapshot()
AssertEq(psWave2.waveMode, "chase", "Pac-Grid transitions from Scatter to Chase after 7s")
AssertTrue(psWave2.waveTransitions >= 1, "Pac-Grid records Scatter -> Chase wave transition")

; 2f. Left/right wrap-around warp tunnels (col 0 <-> 27) & chaser tunnel slowdown
wLeft := GamePacGrid.WrapTunnelForTest(0, 14, -1)
AssertEq(wLeft.col, 27, "Pac-Grid left warp tunnel wraps col 0 (-1) -> col 27")
AssertEq(wLeft.isTunnel, true, "Pac-Grid identifies col 27 on row 14 as warp tunnel")
AssertTrue(wLeft.speedScale < 1.0, "Pac-Grid applies chaser speed slowdown inside warp tunnel")

wRight := GamePacGrid.WrapTunnelForTest(27, 14, 1)
AssertEq(wRight.col, 0, "Pac-Grid right warp tunnel wraps col 27 (+1) -> col 0")

; 2g. Timed Bonus Neon Fruits at 70 & 170 dots eaten
GamePacGrid.Stop()
GamePacGrid.Start(cfg, state, true)
f70 := GamePacGrid.SetDotsEatenForTest(70)
AssertEq(f70.fruitActive, true, "Pac-Grid spawns Bonus Neon Fruit at 70 dots eaten")
AssertEq(f70.fruit70Spawned, true, "Pac-Grid marks 70-dot fruit threshold triggered")
AssertEq(f70.fruitPoints, 100, "Pac-Grid level 1 Bonus Fruit is worth 100 points")

; Consume fruit by placing runner on fruit tile (13, 17)
GamePacGrid.SetRunnerForTest(12, 17, 1, 0)
GamePacGrid.StepForTest(0.12)
AssertEq(GamePacGrid.GetStateSnapshot().fruitActive, false, "Pac-Grid runner consumes active Bonus Fruit at (13, 17)")

f170 := GamePacGrid.SetDotsEatenForTest(170)
AssertEq(f170.fruitActive, true, "Pac-Grid spawns second Bonus Neon Fruit at 170 dots eaten")
AssertEq(f170.fruit170Spawned, true, "Pac-Grid marks 170-dot fruit threshold triggered")

; 2h. Queued directional turn buffering (_nextDir applied at next valid corridor intersection)
; On row 5, col 4 is moving right toward col 6 (where row 4 is open upward at col 6, while (4,4) and (5,4) are walls)
GamePacGrid.SetRunnerForTest(4, 5, 1, 0)
GamePacGrid.QueueDirForTest(0, -1) ; Buffer upward turn while (4, 4) is a wall (#)
psBuffered := GamePacGrid.GetStateSnapshot()
AssertEq(psBuffered.runnerDx, 1, "Pac-Grid runner keeps moving right while upward wall blocks buffered turn")
AssertEq(psBuffered.nextDir.dy, -1, "Pac-Grid buffers upward turn in _nextDir")
; Step forward along row 5 until col 6 where upward corridor (6, 4) opens
Loop 4
    GamePacGrid.StepForTest(0.11)
psTurned := GamePacGrid.GetStateSnapshot()
AssertEq(psTurned.runnerDy, -1, "Pac-Grid automatically applies buffered upward turn at valid intersection")

savedPacBest := cfg.Read("ArcadeHighScores", "pac_grid", 0)
AssertTrue(savedPacBest > 0, "Pac-Grid saves high score to [ArcadeHighScores] pac_grid")

; 2i. Adaptation #3: Toggleable Centered / Expanded Full-Work-Area Mode
AssertEq(GamePacGrid.GetStateSnapshot().expandedMode, false, "Pac-Grid starts in Centered square mode (expandedMode=false)")
mCenter := GamePacGrid._GetMazeMetrics()
AssertEq(mCenter.expanded, false, "Pac-Grid Centered metrics report expanded=false")
AssertEq(mCenter.cellX, mCenter.cellY, "Pac-Grid Centered mode keeps uniform square cells (cellX == cellY)")

AssertEq(GamePacGrid.ToggleViewMode(), true, "Pac-Grid ToggleViewMode() switches to Expanded Full-Work-Area mode")
AssertEq(GamePacGrid.GetStateSnapshot().expandedMode, true, "Pac-Grid GetStateSnapshot exposes expandedMode=true")
mFull := GamePacGrid._GetMazeMetrics()
AssertEq(mFull.expanded, true, "Pac-Grid Expanded metrics report expanded=true")
AssertTrue(mFull.boardW >= mFull.W * 0.85, "Pac-Grid Expanded boardW fills >= 85% of work area width")
AssertTrue(mFull.boardH >= mFull.H * 0.78, "Pac-Grid Expanded boardH fills >= 78% of work area height")
AssertEq(GamePacGrid.ToggleViewMode(), false, "Pac-Grid ToggleViewMode() switches back to Centered mode")
GamePacGrid.Stop()

; ==============================================================================
; 3. ARCADE VAULT REGISTRATION (!^+t & !^+c)
; ==============================================================================
ArcadeVault.RegisterGame("tron", "Neon Light Cycles (TRON)", "!^+t", "Ctrl+Alt+Shift+T", (c, s) => GameLightCycles.Toggle(c, s), () => GameLightCycles.Stop())
ArcadeVault.RegisterGame("pac_grid", "Neon Pac-Grid", "!^+c", "Ctrl+Alt+Shift+C", (c, s) => GamePacGrid.Toggle(c, s), () => GamePacGrid.Stop())

foundTron := false
foundPac := false
for _, g in ArcadeVault.GetRegisteredGames() {
    if (g.id = "tron" && g.chord = "!^+t")
        foundTron := true
    if (g.id = "pac_grid" && g.chord = "!^+c")
        foundPac := true
}
AssertTrue(foundTron, "ArcadeVault registers Neon Light Cycles (TRON) on !^+t")
AssertTrue(foundPac, "ArcadeVault registers Neon Pac-Grid on !^+c")

summary := "PASS=" g_Pass " FAIL=" g_Fail "`n" g_Log
FileOpen(A_ScriptDir "\test_v850_pacgrid_tron.log", "w", "UTF-8").Write(summary)
FileAppend(summary, "*", "UTF-8")
ExitApp(g_Fail == 0 ? 0 : 1)
