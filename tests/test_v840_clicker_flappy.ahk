; ==============================================================================
; Test Suite: test_v840_clicker_flappy.ahk
; Description: Automated verification for Milestone M4 (v8.3.1 -> v8.4.0):
;              - BuildAllowedControlKeys(cfg) strictly excludes HwMuteHotkey
;                and HwTransitionHotkey across all clicker configurations
;                ("PgDn", "b", "Right", RemoteNextSlideKey/RemotePrevSlideKey
;                collisions, and "$key up" edge bindings)
;              - HudArcadeBase.IsAnyGameActive() == true while GameClickerFlappy
;                is running (isolating PPT & Remote slide forwarding) while
;                IsReservedAudioKey(cfg, cfg.HwMuteHotkey) == true
;              - Classic Flap ("flap"): discrete upward velocity impulse +
;                gravity arc
;              - Gravity Wave ("wave"): hold-to-climb upward thrust &
;                release-to-dive downward glide + ribbon wave trail history
;              - Gate pass scoring, [ArcadeHighScores] "flappy" persistence,
;                SHIELD / SLOW-MO bonus rings, pillar collision -> gameover,
;                and ArcadeVault registration for "!^+f"
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
#Include "%A_LineFile%\..\..\Lib\Arcade\GameAsteroids.ahk"
#Include "%A_LineFile%\..\..\Lib\Arcade\GamePaddlePack.ahk"
#Include "%A_LineFile%\..\..\Lib\Arcade\GameClickerFlappy.ahk"

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

HasKeyInList(arr, targetKey) {
    t := StrLower(Trim(String(targetKey)))
    for _, k in arr {
        if (StrLower(Trim(String(k))) = t)
            return true
    }
    return false
}

Gdip.Startup()

tmpIni := A_Temp "\PresenterSync_v840_flappy_" A_TickCount ".ini"
if FileExist(tmpIni)
    FileDelete(tmpIni)

cfg := Config(tmpIni)
st := OverlayState(cfg)

; 1. Strict HwMuteHotkey & HwTransitionHotkey exclusion in BuildAllowedControlKeys(cfg)
cfg.HwMuteHotkey := "PgDn"
cfg.HwTransitionHotkey := "PgUp"
keysPgDn := GameClickerFlappy.BuildAllowedControlKeys(cfg)
AssertTrue(!HasKeyInList(keysPgDn, "PgDn") && !HasKeyInList(keysPgDn, "PgUp") && HasKeyInList(keysPgDn, "Right") && HasKeyInList(keysPgDn, "Space"),
    "When HwMuteHotkey='PgDn' and HwTransitionHotkey='PgUp', neither is in BuildAllowedControlKeys while Right & Space remain allowed")

cfg.HwMuteHotkey := "b"
cfg.HwTransitionHotkey := "None"
keysB := GameClickerFlappy.BuildAllowedControlKeys(cfg)
AssertTrue(!HasKeyInList(keysB, "b") && HasKeyInList(keysB, "PgDn") && HasKeyInList(keysB, "PgUp") && HasKeyInList(keysB, "Right"),
    "When HwMuteHotkey='b', b is never in BuildAllowedControlKeys while PgDn/PgUp/Right are allowed")

cfg.HwMuteHotkey := "Right"
keysRight := GameClickerFlappy.BuildAllowedControlKeys(cfg)
AssertTrue(!HasKeyInList(keysRight, "Right") && HasKeyInList(keysRight, "PgDn") && HasKeyInList(keysRight, "Up"),
    "When HwMuteHotkey='Right', Right is strictly excluded from BuildAllowedControlKeys")

; Remote custom slide key collision with HwMuteHotkey
remoteMockCfg := {
    HwMuteHotkey: "F9",
    HwTransitionHotkey: "F10",
    RemoteNextSlideKey: "F9",
    RemotePrevSlideKey: "F8"
}
keysRemote := GameClickerFlappy.BuildAllowedControlKeys(remoteMockCfg)
AssertTrue(!HasKeyInList(keysRemote, "F9") && !HasKeyInList(keysRemote, "F10") && HasKeyInList(keysRemote, "F8"),
    "When RemoteNextSlideKey collides with HwMuteHotkey ('F9'), F9 is excluded while non-colliding RemotePrevSlideKey ('F8') is included")

; Verify IsReservedAudioKey also catches "$key" and "$key up" edge bindings
cfg.HwMuteHotkey := "PgDn"
AssertTrue(HudArcadeBase.IsReservedAudioKey(cfg, "PgDn") && HudArcadeBase.IsReservedAudioKey(cfg, "$PgDn") && HudArcadeBase.IsReservedAudioKey(cfg, "$PgDn up"),
    "HudArcadeBase.IsReservedAudioKey catches 'PgDn', '$PgDn', and '$PgDn up' when HwMuteHotkey='PgDn'")

; 2. ArcadeVault registration & chord gating for Clicker Flappy ("flappy", !^+f)
ArcadeVault.Lock(cfg, st, false)
ArcadeVault.RegisterGame("flappy", "Clicker Flappy / Wave", "!^+f", "Ctrl+Alt+Shift+F", (c, s) => GameClickerFlappy.Toggle(c, s), () => GameClickerFlappy.Stop())
AssertTrue(!ArcadeVault.ToggleGame("flappy", cfg, st),
    "Locked ArcadeVault blocks Clicker Flappy launch")

foundFlappyReg := false
for _, g in ArcadeVault.GetRegisteredGames() {
    if (g.id = "flappy" && g.chord = "!^+f")
        foundFlappyReg := true
}
AssertTrue(foundFlappyReg, "ArcadeVault registers 'flappy' with chord '!^+f'")

; 3. Headless startup, IsAnyGameActive() slide isolation & live audio reservation
cfg.HwMuteHotkey := "PgDn"
GameClickerFlappy.Start(cfg, st, true)
snap0 := GameClickerFlappy.GetStateSnapshot()
AssertTrue(snap0.active && snap0.phase = "playing" && snap0.mode = "flap" && HudArcadeBase.IsAnyGameActive() && HudArcadeBase.ActiveGameId = "flappy",
    "GameClickerFlappy starts headless in Classic Flap mode and sets IsAnyGameActive()==true (isolating PPT/Remote slide forwarding)")
AssertTrue(HudArcadeBase.IsReservedAudioKey(cfg, cfg.HwMuteHotkey) && !HasKeyInList(snap0.allowedKeys, "PgDn"),
    "Active GameClickerFlappy keeps HwMuteHotkey ('PgDn') reserved for live mic mute and excluded from game allowedKeys")

; 4. Classic Flap physics: discrete upward impulse on FlapOrHoldForTest(true) + gravity arc
GameClickerFlappy.ClearGatesForTest()
GameClickerFlappy.SetCraftForTest(240.0, 350.0, 0.0)
GameClickerFlappy.FlapOrHoldForTest(true)
snapFlap := GameClickerFlappy.GetStateSnapshot()
AssertTrue(snapFlap.craftVy < -350.0,
    "Classic Flap tap imparts strong upward velocity impulse", "vy=" snapFlap.craftVy)

GameClickerFlappy.StepForTest(0.03)
snapFlapStep := GameClickerFlappy.GetStateSnapshot()
AssertTrue(snapFlapStep.craftY < 350.0 && snapFlapStep.craftVy > snapFlap.craftVy,
    "Classic Flap moves craft upward while gravity decelerates vertical velocity",
    "y=" snapFlapStep.craftY " vy=" snapFlapStep.craftVy)

GameClickerFlappy.FlapOrHoldForTest(false)
Loop 25
    GameClickerFlappy.StepForTest(0.025)
snapFlapFall := GameClickerFlappy.GetStateSnapshot()
AssertTrue(snapFlapFall.craftVy > 150.0,
    "Classic Flap gravity pulls craft downward after impulse apex", "vy=" snapFlapFall.craftVy)

; 5. Gravity Wave physics: hold-to-climb upward thrust & release-to-dive downward glide + ribbon trail
AssertTrue(GameClickerFlappy.SetModeForTest("wave") = "wave" && GameClickerFlappy.GetStateSnapshot().mode = "wave",
    "SetModeForTest switches GameClickerFlappy to Gravity Wave mode")

GameClickerFlappy.SetCraftForTest(240.0, 380.0, 40.0)
GameClickerFlappy.FlapOrHoldForTest(true)
Loop 12
    GameClickerFlappy.StepForTest(0.02)
snapWaveClimb := GameClickerFlappy.GetStateSnapshot()
AssertTrue(snapWaveClimb.isHolding && snapWaveClimb.craftVy < -180.0 && snapWaveClimb.craftY < 370.0 && snapWaveClimb.trailCount >= 5,
    "Gravity Wave hold-to-climb accelerates craft upward and appends glowing ribbon trail points",
    "y=" snapWaveClimb.craftY " vy=" snapWaveClimb.craftVy " trail=" snapWaveClimb.trailCount)

climbY := snapWaveClimb.craftY
GameClickerFlappy.FlapOrHoldForTest(false)
Loop 16
    GameClickerFlappy.StepForTest(0.02)
snapWaveDive := GameClickerFlappy.GetStateSnapshot()
AssertTrue(!snapWaveDive.isHolding && snapWaveDive.craftVy > 180.0 && snapWaveDive.craftY > climbY,
    "Gravity Wave release-to-dive accelerates craft downward smoothly",
    "climbY=" climbY " diveY=" snapWaveDive.craftY " vy=" snapWaveDive.craftVy)

; 6. Gate pass scoring & [ArcadeHighScores] "flappy" persistence
GameClickerFlappy.ClearGatesForTest()
GameClickerFlappy.SetModeForTest("flap")
GameClickerFlappy.SetCraftForTest(240.0, 320.0, -50.0)
; Place gate centered vertically at craftY (320) just ahead of craft so scrolling passes the gap cleanly
GameClickerFlappy.SpawnGateForTest(225.0, 320.0, 220.0, 50.0)
Loop 6
    GameClickerFlappy.StepForTest(0.02)
snapPass := GameClickerFlappy.GetStateSnapshot()
AssertTrue(snapPass.score >= 1 && snapPass.highScore >= 1 && HudArcadeBase.LoadHighScore(cfg, "flappy") == snapPass.highScore && snapPass.phase = "playing",
    "Passing through gate gap increments score and persists [ArcadeHighScores] flappy",
    "score=" snapPass.score " hi=" snapPass.highScore)

; 7. Bonus Ring (SHIELD) absorption & pillar collision protection -> then unshielded pillar collision -> gameover
GameClickerFlappy.ClearGatesForTest()
GameClickerFlappy.SetCraftForTest(240.0, 320.0, 0.0)
GameClickerFlappy.SpawnBonusRingForTest(244.0, 320.0, "SHIELD")
GameClickerFlappy.StepForTest(0.02)
snapShield := GameClickerFlappy.GetStateSnapshot()
AssertTrue(snapShield.shieldMs > 5000.0, "Collecting SHIELD bonus ring activates craft shield")

; Collide with top pillar while shielded -> shield absorbs impact and game continues
GameClickerFlappy.SpawnGateForTest(225.0, 520.0, 140.0, 64.0)
GameClickerFlappy.SetCraftForTest(240.0, 200.0, 0.0)
GameClickerFlappy.StepForTest(0.02)
snapShieldBreak := GameClickerFlappy.GetStateSnapshot()
AssertTrue(snapShieldBreak.phase = "playing" && snapShieldBreak.shieldMs == 0.0,
    "Active shield absorbs gate pillar impact and keeps phase='playing'")

; Collide with gate pillar without shield -> gameover
GameClickerFlappy.SpawnGateForTest(225.0, 520.0, 140.0, 64.0)
GameClickerFlappy.SetCraftForTest(240.0, 200.0, 0.0)
GameClickerFlappy.StepForTest(0.02)
snapGameOver := GameClickerFlappy.GetStateSnapshot()
AssertTrue(snapGameOver.phase = "gameover",
    "Unshielded pillar collision transitions GameClickerFlappy to 'gameover'")

GameClickerFlappy.Stop()
AssertTrue(!GameClickerFlappy.IsActive && !HudArcadeBase.IsAnyGameActive(),
    "GameClickerFlappy.Stop cleans up surface and clears active game state")

; 8. Verify INI stores only [ArcadeHighScores] flappy with zero Vault unlock persistence
iniText := FileExist(tmpIni) ? FileRead(tmpIni, "UTF-8") : ""
AssertTrue(InStr(iniText, "flappy=") && !InStr(iniText, "IsUnlocked") && !InStr(iniText, "INSERTCOIN"),
    "INI persists only [ArcadeHighScores] flappy with zero Vault unlock state")

try FileDelete(tmpIni)
try FileAppend("PASS=" passed " FAIL=" failed "`n", "*")
ExitApp(failed > 0 ? 1 : 0)
