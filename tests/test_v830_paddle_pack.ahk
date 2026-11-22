; ==============================================================================
; Test Suite: test_v830_paddle_pack.ahk
; Description: Automated verification for Milestone M3 (v8.2.1 -> v8.3.0):
;              - PaddlePhysicsCore 2D elastic circle-vs-rect & paddle spin bounce
;              - GameBrickBreaker ("brick_breaker", ^!+b): headless launch,
;                multi-hit armored bricks (hp 3 -> 2 -> 1 -> 0), MULTIBALL split,
;                WIDE PADDLE expansion, LASER fire & brick destruction,
;                wave progression, [ArcadeHighScores] persistence
;              - GameCyberPong ("cyber_pong", ^!+h): headless launch, velocity
;                spin transfer & Magnus trajectory curve, adaptive 1P AI
;                tracking, 2P mode toggle, rally streak counter, first-to-7 win
;              - ArcadeVault registration & IsAnyGameActive() arbitration
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

tmpIni := A_Temp "\PresenterSync_v830_paddle_" A_TickCount ".ini"
if FileExist(tmpIni)
    FileDelete(tmpIni)

cfg := Config(tmpIni)
st := OverlayState(cfg)

; 1. ArcadeVault registration & locked/unlocked chord gating for Brick Breaker & Cyber Pong
ArcadeVault.Lock(cfg, st, false)
ArcadeVault.RegisterGame("brick_breaker", "Brick Breaker", "^!+F22", "Ctrl+Alt+Shift+B", (c, s) => GameBrickBreaker.Toggle(c, s), () => GameBrickBreaker.Stop())
ArcadeVault.RegisterGame("cyber_pong", "Cyber Pong", "^!+F23", "Ctrl+Alt+Shift+H", (c, s) => GameCyberPong.Toggle(c, s), () => GameCyberPong.Stop())

AssertTrue(!ArcadeVault.ToggleGame("brick_breaker", cfg, st) && !ArcadeVault.ToggleGame("cyber_pong", cfg, st),
    "Locked ArcadeVault blocks Brick Breaker & Cyber Pong launch")

regGames := ArcadeVault.GetRegisteredGames()
AssertTrue(regGames.Length >= 2, "ArcadeVault registers Brick Breaker & Cyber Pong")

; 2. GameBrickBreaker headless startup & active game registration
GameBrickBreaker.Start(cfg, st, true)
snap0 := GameBrickBreaker.GetStateSnapshot()
AssertTrue(snap0.active && snap0.phase = "playing" && snap0.brickCount >= 40 && snap0.ballCount == 1 && HudArcadeBase.IsAnyGameActive() && HudArcadeBase.ActiveGameId = "brick_breaker",
    "GameBrickBreaker initializes headless, spawns Wave 1 bricks & sets ActiveGameId='brick_breaker'")

; 3. Multi-hit armored brick (hp=3 -> 2 -> 1 -> destroyed)
GameBrickBreaker._bricks := []
GameBrickBreaker.SpawnBrickForTest(300.0, 200.0, 80.0, 24.0, 3, "MULTIBALL")
GameBrickBreaker.SetBallForTest(340.0, 232.0, 0.0, -450.0, false)
GameBrickBreaker.StepForTest(0.02)
snapHit1 := GameBrickBreaker.GetStateSnapshot()
AssertTrue(snapHit1.brickCount == 1 && snapHit1.bricks[1].hp == 2 && snapHit1.balls[1].vy > 0.0,
    "Armored brick hp=3 decrements to hp=2 and reflects ball downward", "hp=" (snapHit1.brickCount ? snapHit1.bricks[1].hp : -1))

GameBrickBreaker.SetBallForTest(340.0, 232.0, 0.0, -450.0, false)
GameBrickBreaker.StepForTest(0.02)
snapHit2 := GameBrickBreaker.GetStateSnapshot()
AssertTrue(snapHit2.brickCount == 1 && snapHit2.bricks[1].hp == 1,
    "Armored brick hp=2 decrements to hp=1 on second hit")

; Keep another dummy brick so wave doesn't immediately reset on 3rd hit
GameBrickBreaker.SpawnBrickForTest(700.0, 200.0, 80.0, 24.0, 1, "")
GameBrickBreaker.SetBallForTest(340.0, 232.0, 0.0, -450.0, false)
GameBrickBreaker.StepForTest(0.02)
snapHit3 := GameBrickBreaker.GetStateSnapshot()
AssertTrue(snapHit3.brickCount == 1 && snapHit3.dropCount == 1 && snapHit3.score >= 120,
    "Armored brick shatters on 3rd hit, awards 3x points, and drops MULTIBALL pill",
    "bricks=" snapHit3.brickCount " drops=" snapHit3.dropCount " score=" snapHit3.score)

; 4. Catch MULTIBALL, WIDE PADDLE, and LASER drops
padX := snapHit3.paddleX, padY := snapHit3.paddleY, padW := snapHit3.paddleW
GameBrickBreaker._drops := []
GameBrickBreaker.SpawnDropForTest(padX + padW * 0.5, padY - 2.0, "MULTIBALL")
GameBrickBreaker.StepForTest(0.02)
snapMulti := GameBrickBreaker.GetStateSnapshot()
AssertTrue(snapMulti.ballCount == 3, "MULTIBALL pill splits active ball into 3 balls", "balls=" snapMulti.ballCount)

baseW := snapMulti.paddleW
GameBrickBreaker.SpawnDropForTest(padX + padW * 0.5, padY - 2.0, "WIDE PADDLE")
GameBrickBreaker.StepForTest(0.02)
snapWide := GameBrickBreaker.GetStateSnapshot()
AssertTrue(snapWide.wideMs > 0.0 && snapWide.paddleW > baseW * 1.4,
    "WIDE PADDLE pill expands paddle width", "baseW=" baseW " newW=" snapWide.paddleW)

GameBrickBreaker.SpawnDropForTest(padX + padW * 0.5, padY - 2.0, "LASER")
GameBrickBreaker.StepForTest(0.02)
snapLaser := GameBrickBreaker.GetStateSnapshot()
AssertTrue(snapLaser.laserMs > 0.0, "LASER pill activates paddle laser cannons")

; 5. Fire laser to destroy remaining brick and trigger wave advance (Wave 1 -> Wave 2)
GameBrickBreaker._bricks := []
GameBrickBreaker.SetPaddleForTest(300.0, 0.0)
GameBrickBreaker.SpawnBrickForTest(295.0, padY - 70.0, 180.0, 24.0, 1, "")
GameBrickBreaker.LaunchOrFire()
AssertTrue(GameBrickBreaker.GetStateSnapshot().laserCount == 2, "LaunchOrFire emits dual laser bolts when LASER is active")
Loop 12
    GameBrickBreaker.StepForTest(0.016)
snapWave2 := GameBrickBreaker.GetStateSnapshot()
AssertTrue(snapWave2.wave == 2 && snapWave2.brickCount >= 50 && HudArcadeBase.LoadHighScore(cfg, "brick_breaker") == snapWave2.highScore,
    "Laser destroys final brick, advances to Wave 2, and persists [ArcadeHighScores] brick_breaker",
    "wave=" snapWave2.wave " bricks=" snapWave2.brickCount)

GameBrickBreaker.Stop()
AssertTrue(!GameBrickBreaker.IsActive && !HudArcadeBase.IsAnyGameActive(), "GameBrickBreaker.Stop cleans up active state")

; 6. GameCyberPong headless startup, velocity spin transfer & Magnus curve
GameCyberPong.Start(cfg, st, true)
pSnap0 := GameCyberPong.GetStateSnapshot()
AssertTrue(pSnap0.active && pSnap0.phase = "playing" && !pSnap0.twoPlayer && HudArcadeBase.IsAnyGameActive() && HudArcadeBase.ActiveGameId = "cyber_pong",
    "GameCyberPong starts in 1P vs AI mode & registers ActiveGameId='cyber_pong'")

; Place puck moving left into fast upward-moving Left Paddle -> transfers spin & curves trajectory
lp := pSnap0.leftPaddle
GameCyberPong.SetPaddlesForTest(300.0, 300.0, -480.0, 0.0)
GameCyberPong.SetPuckForTest(lp.x + lp.w + 12.0, 358.0, -520.0, 0.0, 0.0)
GameCyberPong.StepForTest(0.025)
pSnapHit := GameCyberPong.GetStateSnapshot()
AssertTrue(pSnapHit.puck.vx > 0.0 && Abs(pSnapHit.puck.spin) > 100.0 && pSnapHit.rally == 1,
    "Left paddle deflects puck rightward, increments rally streak, and imparts velocity spin",
    "vx=" pSnapHit.puck.vx " spin=" pSnapHit.puck.spin " rally=" pSnapHit.rally)

vyBeforeCurve := pSnapHit.puck.vy
Loop 8
    GameCyberPong.StepForTest(0.016)
pSnapCurve := GameCyberPong.GetStateSnapshot()
AssertTrue(Abs(pSnapCurve.puck.vy - vyBeforeCurve) > 10.0,
    "Magnus spin curves puck vertical velocity mid-flight",
    "vy0=" vyBeforeCurve " vy1=" pSnapCurve.puck.vy)

; 7. Adaptive 1P AI tracking moves right paddle toward incoming puck Y
rpStartY := GameCyberPong.GetStateSnapshot().rightPaddle.y
GameCyberPong.SetPuckForTest(500.0, rpStartY + 220.0, 520.0, 0.0, 0.0)
Loop 10
    GameCyberPong.StepForTest(0.02)
rpAfterY := GameCyberPong.GetStateSnapshot().rightPaddle.y
AssertTrue(rpAfterY > rpStartY + 25.0,
    "1P Adaptive AI tracks incoming puck downward", "startY=" rpStartY " afterY=" rpAfterY)

; 8. Toggle 2P mode & verify first-to-7 win state machine
AssertTrue(GameCyberPong.ToggleTwoPlayerMode() == true && GameCyberPong.GetStateSnapshot().twoPlayer == true,
    "ToggleTwoPlayerMode switches Cyber Pong to 2P split keyboard mode")

GameCyberPong._leftScore := 6
W := Float(GameCyberPong._surf.W)
GameCyberPong.SetPuckForTest(W - 4.0, 260.0, 620.0, 0.0, 0.0)
GameCyberPong.StepForTest(0.025)
pWin := GameCyberPong.GetStateSnapshot()
AssertTrue(pWin.leftScore == 7 && pWin.phase = "gameover" && pWin.winner = "PLAYER 1" && HudArcadeBase.LoadHighScore(cfg, "cyber_pong") >= 450,
    "Scoring 7th point wins the set (First to 7), enters gameover phase & saves cyber_pong high score",
    "leftScore=" pWin.leftScore " phase=" pWin.phase " winner=" pWin.winner)

GameCyberPong.Stop()
AssertTrue(!GameCyberPong.IsActive && !HudArcadeBase.IsAnyGameActive(), "GameCyberPong.Stop cleans up active state")

; Verify zero vault unlock persistence in INI
iniText := FileExist(tmpIni) ? FileRead(tmpIni, "UTF-8") : ""
AssertTrue(InStr(iniText, "brick_breaker=") && InStr(iniText, "cyber_pong=") && !InStr(iniText, "IsUnlocked") && !InStr(iniText, "INSERTCOIN"),
    "INI stores only [ArcadeHighScores] brick_breaker & cyber_pong with zero Vault state")

try FileDelete(tmpIni)
try FileAppend("PASS=" passed " FAIL=" failed "`n", "*")
ExitApp(failed > 0 ? 1 : 0)
