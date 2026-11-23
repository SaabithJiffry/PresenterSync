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
#Include "%A_LineFile%\..\..\Lib\Arcade\GameAsteroids.ahk"

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

; 8. GameAsteroids simulation, splitting, powerups, saucer, Mic Pill Bumper & score persistence
GameAsteroids.Start(cfg, st, true)
snap0 := GameAsteroids.GetSnapshot()
AssertTrue(snap0.active && snap0.phase = "playing" && snap0.asteroidCount >= 5 && HudArcadeBase.ActiveGameId = "asteroids",
    "GameAsteroids initializes cleanly in headless mode & registers active game")

; Clear asteroids, place one Large directly ahead of ship, fire & step until hit
GameAsteroids._asteroids := []
shipSnap := GameAsteroids.GetSnapshot().ship
GameAsteroids.SpawnAsteroid(shipSnap.x, shipSnap.y - 60.0, 0.0, 0.0, 3)
GameAsteroids.FireBullet(true)
Loop 20
    GameAsteroids.StepSimulation(0.016, false)
snapSplit := GameAsteroids.GetSnapshot()
AssertTrue(snapSplit.score >= 20 && snapSplit.asteroidCount == 2 && snapSplit.highScore >= 20,
    "GameAsteroids bullet splits Large asteroid -> 2 Medium asteroids and awards score",
    "score=" snapSplit.score " cnt=" snapSplit.asteroidCount)

; Saucer hit (clear asteroids first so bullet hits saucer cleanly)
GameAsteroids._asteroids := []
GameAsteroids._bullets := []
GameAsteroids._ship.angle := -1.57079632679
sc := GameAsteroids.SpawnSaucer(true)
sc.x := shipSnap.x
sc.y := shipSnap.y - 50.0
sc.vx := 0.0
GameAsteroids._ship.fireCdMs := 0.0
GameAsteroids.FireBullet(true)
Loop 15
    GameAsteroids.StepSimulation(0.016, false)
snapSaucer := GameAsteroids.GetSnapshot()
AssertTrue(!snapSaucer.saucerActive && snapSaucer.score >= 270,
    "GameAsteroids destroys Alien Saucer (+250) and spawns power-up",
    "score=" snapSaucer.score " saucer=" snapSaucer.saucerActive)

; Mic Pill Bumper bounce
GameAsteroids._asteroids := []
GameAsteroids._saucer.active := false
GameAsteroids._saucerTimerMs := 99999.0
GameAsteroids._micBumper := true
GameAsteroids.SetTestMicPillRect({ x: 200, y: 200, w: 120, h: 40 })
bumperAst := GameAsteroids.SpawnAsteroid(192.0, 220.0, 80.0, 0.0, 1)
GameAsteroids.StepSimulation(0.05, false)
AssertTrue(bumperAst.vx < 0.0, "Mic Pill Bumper elastically deflects asteroid away from Mic pill", "vx=" bumperAst.vx)

; 9. M5A.2 Alien Blaster mode: mode toggle, fixed upward angle (-PI/2), 2D X+Y movement, alien waves, weapon escalation 1..5 (Beam Laser), alien kill scoring
GameAsteroids.ToggleBlasterMode()
alienSnap0 := GameAsteroids.GetStateSnapshot()
AssertTrue(alienSnap0.blasterMode = "alien" && alienSnap0.weaponTier == 1 && alienSnap0.alienCount >= 5 && alienSnap0.asteroidCount == 0,
    "ToggleBlasterMode switches cleanly to Alien Blaster mode and spawns alien wave",
    "mode=" alienSnap0.blasterMode " tier=" alienSnap0.weaponTier " aliens=" alienSnap0.alienCount)

; Fixed upward angle (-PI/2) + full 2D X+Y movement
GameAsteroids._aliens := []
GameAsteroids._bullets := []
startX := GameAsteroids._ship.x
startY := GameAsteroids._ship.y
GameAsteroids._ship.angle := 0.85 ; attempt to rotate — must be snapped back to -PI/2
GameAsteroids._ship.vx := 200.0
GameAsteroids._ship.vy := -150.0
GameAsteroids.StepSimulation(0.05, false)
movedShip := GameAsteroids.GetStateSnapshot().ship
AssertTrue(Abs(movedShip.angle - (-1.57079632679)) < 0.001 && movedShip.x > startX && movedShip.y < startY,
    "Alien Blaster ship stays fixed forward (-PI/2) while moving freely in 2D X+Y",
    "ang=" movedShip.angle " dx=" (movedShip.x - startX) " dy=" (movedShip.y - startY))
GameAsteroids._ship.vx := 0.0
GameAsteroids._ship.vy := 0.0

; Escalating weapon tiers 1 -> 2 -> 3 -> 4 -> 5 (Beam Laser)
GameAsteroids._bullets := []
GameAsteroids._ship.fireCdMs := 0.0
GameAsteroids.FireBullet(true)
bT1 := GameAsteroids._bullets.Length
GameAsteroids.UpgradeWeaponForTest()
GameAsteroids._bullets := []
GameAsteroids._ship.fireCdMs := 0.0
GameAsteroids.FireBullet(true)
bT2 := GameAsteroids._bullets.Length
GameAsteroids.UpgradeWeaponForTest()
GameAsteroids._bullets := []
GameAsteroids._ship.fireCdMs := 0.0
GameAsteroids.FireBullet(true)
bT3 := GameAsteroids._bullets.Length
GameAsteroids.UpgradeWeaponForTest()
GameAsteroids._bullets := []
GameAsteroids._ship.fireCdMs := 0.0
GameAsteroids.FireBullet(true)
bT4 := GameAsteroids._bullets.Length
GameAsteroids.UpgradeWeaponForTest()
t5 := GameAsteroids.GetStateSnapshot().weaponTier
AssertTrue(bT1 == 1 && bT2 == 2 && bT3 == 3 && bT4 == 5 && t5 == 5,
    "Alien Blaster weapon tiers escalate cleanly 1->2->3->5 spread->Tier 5 Beam",
    "t1=" bT1 " t2=" bT2 " t3=" bT3 " t4=" bT4 " t5=" t5)

; Tier 5 Neon Beam Laser vaporizes alien ship & awards score
GameAsteroids._aliens := []
GameAsteroids._bullets := []
GameAsteroids._score := 0
GameAsteroids.SpawnAlienForTest(GameAsteroids._ship.x, GameAsteroids._ship.y - 140.0, "cruiser", 2, 0.0)
GameAsteroids.FireBullet(true)
Loop 6
    GameAsteroids.StepSimulation(0.05, false)
beamSnap := GameAsteroids.GetStateSnapshot()
AssertTrue(beamSnap.beamActive && beamSnap.alienCount == 0 && beamSnap.score >= 180,
    "Alien Blaster Tier 5 Neon Beam Laser vaporizes alien cruiser and awards score",
    "beam=" beamSnap.beamActive " aliens=" beamSnap.alienCount " score=" beamSnap.score)

; Toggle back to Asteroid mode cleanly
GameAsteroids.ToggleBlasterMode()
backSnap := GameAsteroids.GetStateSnapshot()
AssertTrue(backSnap.blasterMode = "asteroids" && backSnap.asteroidCount >= 5 && backSnap.alienCount == 0,
    "ToggleBlasterMode switches back cleanly to Asteroid Blaster mode")

GameAsteroids.Stop()
AssertTrue(!GameAsteroids.IsActive && !HudArcadeBase.IsAnyGameActive(), "GameAsteroids.Stop clears active game cleanly")

try FileDelete(tmpIni)
try FileAppend("PASS=" passed " FAIL=" failed "`n", "*")
ExitApp(failed > 0 ? 1 : 0)
