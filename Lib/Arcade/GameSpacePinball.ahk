; ==============================================================================
; Module: GameSpacePinball.ahk
; Description: Milestone M8.1 — Pinball Classic: Neon Space Cadet Pinball (v8.7.1, ^!+p)
;              * InteractiveMouse := true (0x01000000 catch-alpha + WM_MOUSEACTIVATE=3)
;                supporting both KB flippers/plunger & optional left/right mouse-half clicks.
;              * 4x sub-stepped 240Hz 2D rigid-body physics (gravity, slope, rolling
;                damping, restitution, swept angular capsule-vs-circle flipper collision).
;              * Spring plunger + one-way top shooter gate, 3 upgradable Attack Pop
;                Bumpers, dual triangular Slingshots, 3-bank Drop Targets, upper Orbit &
;                3 Re-Entry Rollover Lanes, Ball-Save, Space Cadet Rank & Mission LEDs
;                (Cadet -> Admiral + 2x-10x multipliers), 3-strike TILT nudge lockout,
;                3-ball arcade run, and [ArcadeHighScores] "pinball" persistence.
; ==============================================================================

#Include "%A_LineFile%\..\..\HudArcadeBase.ahk"

class GameSpacePinball {
    static IsActive := false
    static Phase := "idle" ; "idle" | "playing" | "paused" | "gameover"

    static TW := 420.0
    static TH := 720.0
    static BALL_R := 9.5
    static GRAVITY := 780.0
    static SUBSTEPS := 4
    static MAX_SPEED := 1450.0

    static RANKS := ["Cadet", "Ensign", "Lieutenant", "Captain", "Commander", "Commodore", "Admiral"]

    static _surf := ""
    static _cfg := ""
    static _state := ""
    static _savedPolling := ""
    static _boundHotkeys := []
    static _tickFn := ""
    static _lastUs := 0.0
    static _headless := false

    static _score := 0
    static _highScore := 0
    static _ballsLeft := 3
    static _ballNum := 1
    static _multiplier := 1
    static _rankIdx := 1
    static _missionHits := 0
    static _missionTarget := 6

    static _ballX := 378.0
    static _ballY := 640.0
    static _ballVx := 0.0
    static _ballVy := 0.0
    static _ballInShooter := true
    static _ballTrail := []

    static _plungerCharge := 0.0
    static _plungerHeld := false
    static _plungerMouseHeld := false

    static _leftFlipperDown := false
    static _rightFlipperDown := false
    static _leftMouseDown := false
    static _rightMouseDown := false
    static _leftFlipperAngle := 0.46
    static _rightFlipperAngle := 2.68159265 ; pi - 0.46
    static _leftFlipperOmega := 0.0
    static _rightFlipperOmega := 0.0

    static _bumpers := []
    static _dropTargets := []
    static _rollovers := []
    static _slings := []
    static _walls := []
    static _popups := []

    static _ballSaveTimer := 12.0
    static _tiltHeat := 0.0
    static _tiltStrikes := 0
    static _tilted := false
    static _nudgeShake := 0.0
    static _orbitCd := 0.0

    static Toggle(cfg, state) {
        if (this.IsActive)
            this.Stop()
        else
            this.Start(cfg, state)
        return true
    }

    static Start(cfg, state, headless := false) {
        if (this.IsActive)
            return false
        this._cfg := cfg
        this._state := state
        this._headless := !!headless
        this._surf := HudArcadeBase.CreateSurface({
            interactiveMouse: true,
            cursorId: 32512,
            title: "PresenterSyncSpacePinball",
            onMouseEvent: this._OnMouse.Bind(this),
            headless: this._headless
        })
        if (!IsObject(this._surf))
            return false

        this.IsActive := true
        HudArcadeBase.RegisterActiveGame(this, "pinball")
        this._highScore := HudArcadeBase.LoadHighScore(cfg, "pinball")
        this._BuildGeometry()
        this._ResetRun()

        if (!this._headless) {
            this._savedPolling := HudArcadeBase.PauseHostPolling(state)
            HudArcadeBase.BeginHighResTimer()
            this._BindKeys(cfg)
            this._lastUs := HudArcadeBase.NowUs()
            this._tickFn := this._FrameTick.Bind(this)
            SetTimer(this._tickFn, 16)
            this._RenderFrame()
        }
        return true
    }

    static Stop() {
        if (!this.IsActive)
            return
        this.IsActive := false
        this.Phase := "idle"
        if (IsObject(this._tickFn)) {
            try SetTimer(this._tickFn, 0)
            this._tickFn := ""
        }
        if (!this._headless) {
            HudArcadeBase.UnbindKeys(this._boundHotkeys)
            HudArcadeBase.EndHighResTimer()
            HudArcadeBase.RestoreHostPolling(this._cfg, this._state, this._savedPolling)
        }
        HudArcadeBase.DestroySurface(this._surf)
        this._surf := ""
        HudArcadeBase.ClearActiveGame("pinball")
    }

    static _BindKeys(cfg) {
        condFn := (*) => GameSpacePinball.IsActive
        noop(*) {
        }
        bindings := [
            { key: "$Left", fn: noop },
            { key: "$Right", fn: noop },
            { key: "$z", fn: noop },
            { key: "$/", fn: noop },
            { key: "$LShift", fn: noop },
            { key: "$RShift", fn: noop },
            { key: "$Space", fn: (*) => GameSpacePinball._OnSpaceDown() },
            { key: "$Space up", fn: (*) => GameSpacePinball._OnSpaceUp() },
            { key: "$Up", fn: (*) => GameSpacePinball.Nudge() },
            { key: "$x", fn: (*) => GameSpacePinball.Nudge() },
            { key: "$p", fn: (*) => GameSpacePinball.TogglePause() },
            { key: "$r", fn: (*) => GameSpacePinball.RestartIfGameOver() },
            { key: "$Escape", fn: (*) => GameSpacePinball.Stop() }
        ]
        HudArcadeBase.BindKeysSafe(cfg, bindings, this._boundHotkeys, condFn)
    }

    static _OnSpaceDown() {
        if (!this.IsActive)
            return
        if (this.Phase = "gameover") {
            this._ResetRun()
            return
        }
        if (this.Phase = "playing")
            this._plungerHeld := true
    }

    static _OnSpaceUp() {
        if (!this.IsActive)
            return
        if (this._plungerHeld) {
            this._plungerHeld := false
            this._ReleasePlunger()
        }
    }

    static TogglePause() {
        if (!this.IsActive || this.Phase = "gameover")
            return
        this.Phase := (this.Phase = "paused") ? "playing" : "paused"
        if (!this._headless)
            this._RenderFrame()
    }

    static RestartIfGameOver() {
        if (this.IsActive && this.Phase = "gameover")
            this._ResetRun()
    }

    static _GetTableTransform(&ox, &oy, &sc) {
        W := Float(this._surf.W), H := Float(this._surf.H)
        sc := Min((W - 60.0) / this.TW, (H - 110.0) / this.TH)
        sc := Max(0.35, sc)
        ox := (W - this.TW * sc) * 0.5
        oy := 68.0 + (H - 86.0 - this.TH * sc) * 0.5
    }

    static _OnMouse(msg, x, y, wp) {
        if (!this.IsActive || !IsObject(this._surf))
            return
        W := Float(this._surf.W)
        this._GetTableTransform(&ox, &oy, &sc)
        tx := (Float(x) - ox) / sc
        ty := (Float(y) - oy) / sc

        if (msg == 0x0201) { ; WM_LBUTTONDOWN
            if (this.Phase = "gameover") {
                this._ResetRun()
                return
            }
            if (this.Phase != "playing")
                return
            if (this._ballInShooter && tx >= 352.0 && ty >= 480.0) {
                this._plungerMouseHeld := true
            } else if (Float(x) < W * 0.5) {
                this._leftMouseDown := true
            } else {
                this._rightMouseDown := true
            }
        } else if (msg == 0x0202) { ; WM_LBUTTONUP
            if (this._plungerMouseHeld) {
                this._plungerMouseHeld := false
                this._ReleasePlunger()
            }
            this._leftMouseDown := false
            this._rightMouseDown := false
        } else if (msg == 0x0204) { ; WM_RBUTTONDOWN
            if (this.Phase = "playing")
                this.Nudge()
        }
    }

    ; --- Headless Test Helpers ---
    static StepForTest(dtSec) {
        if (!this.IsActive)
            return
        rem := Max(0.0, Float(dtSec))
        while (rem > 0.0) {
            stepDt := Min(0.0166667, rem)
            this._Step(stepDt)
            rem -= stepDt
        }
    }

    static SetBallForTest(x, y, vx := 0.0, vy := 0.0, inShooter := false) {
        this._ballX := Float(x)
        this._ballY := Float(y)
        this._ballVx := Float(vx)
        this._ballVy := Float(vy)
        this._ballInShooter := !!inShooter
    }

    static SetFlippersForTest(leftDown, rightDown) {
        this._leftFlipperDown := !!leftDown
        this._rightFlipperDown := !!rightDown
    }

    static TriggerPlungerForTest(charge := 1.0) {
        this._plungerCharge := Max(0.05, Min(1.0, Float(charge)))
        this._ReleasePlunger()
    }

    static NudgeForTest() {
        return this.Nudge()
    }

    static GetStateSnapshot() {
        litRollovers := 0
        for _, r in this._rollovers {
            if (r.lit)
                litRollovers += 1
        }
        downDrops := 0
        for _, d in this._dropTargets {
            if (d.down)
                downDrops += 1
        }
        return {
            phase: this.Phase,
            score: this._score,
            highScore: this._highScore,
            ballsLeft: this._ballsLeft,
            ballNum: this._ballNum,
            multiplier: this._multiplier,
            rankIdx: this._rankIdx,
            rankName: this.RANKS[this._rankIdx],
            ballX: this._ballX,
            ballY: this._ballY,
            ballVx: this._ballVx,
            ballVy: this._ballVy,
            ballInShooter: this._ballInShooter,
            leftFlipperAngle: this._leftFlipperAngle,
            rightFlipperAngle: this._rightFlipperAngle,
            bumperLevel: this._bumpers.Length > 0 ? this._bumpers[1].level : 1,
            litRollovers: litRollovers,
            downDrops: downDrops,
            ballSaveTimer: this._ballSaveTimer,
            tiltStrikes: this._tiltStrikes,
            tilted: this._tilted,
            interactiveMouse: IsObject(this._surf) ? this._surf.interactiveMouse : false,
            cursorId: IsObject(this._surf) ? this._surf.cursorId : 0
        }
    }

    static _BuildGeometry() {
        ; Static wall segments [x1, y1, x2, y2, restitution]
        this._walls := []
        ; Left & right outer rails
        this._walls.Push({ x1: 24.0, y1: 150.0, x2: 24.0, y2: 610.0, e: 0.55 })
        this._walls.Push({ x1: 396.0, y1: 150.0, x2: 396.0, y2: 685.0, e: 0.55 })
        ; Shooter lane divider & bottom floor
        this._walls.Push({ x1: 360.0, y1: 155.0, x2: 360.0, y2: 685.0, e: 0.50 })
        this._walls.Push({ x1: 360.0, y1: 685.0, x2: 396.0, y2: 685.0, e: 0.25 })
        ; Top arch (12 smooth segments from (24,150) over (210,28) to (396,150))
        archPts := 12
        prevX := 24.0, prevY := 150.0
        loop archPts {
            t := Float(A_Index) / Float(archPts)
            ang := 3.14159265 * (1.0 - t)
            nx := 210.0 + 186.0 * Cos(ang)
            ny := 150.0 - 122.0 * Sin(ang)
            this._walls.Push({ x1: prevX, y1: prevY, x2: nx, y2: ny, e: 0.55 })
            prevX := nx, prevY := ny
        }
        ; Left & right drain funnels into flippers
        this._walls.Push({ x1: 24.0, y1: 610.0, x2: 112.0, y2: 668.0, e: 0.40 })
        this._walls.Push({ x1: 360.0, y1: 610.0, x2: 272.0, y2: 668.0, e: 0.40 })
        ; Inlane guides feeding flippers
        this._walls.Push({ x1: 64.0, y1: 495.0, x2: 64.0, y2: 572.0, e: 0.45 })
        this._walls.Push({ x1: 64.0, y1: 572.0, x2: 120.0, y2: 628.0, e: 0.35 })
        this._walls.Push({ x1: 320.0, y1: 495.0, x2: 320.0, y2: 572.0, e: 0.45 })
        this._walls.Push({ x1: 320.0, y1: 572.0, x2: 264.0, y2: 628.0, e: 0.35 })
        ; Upper rollover lane dividers
        this._walls.Push({ x1: 164.0, y1: 88.0, x2: 164.0, y2: 136.0, e: 0.50 })
        this._walls.Push({ x1: 220.0, y1: 88.0, x2: 220.0, y2: 136.0, e: 0.50 })

        ; Slingshots: active kicker hypotenuse + 2 passive sides
        this._slings := [
            { ax: 64.0, ay: 495.0, bx: 112.0, by: 578.0, cx: 64.0, cy: 568.0, nx: 0.86, ny: -0.50, flash: 0.0 },
            { ax: 320.0, ay: 495.0, bx: 272.0, by: 578.0, cx: 320.0, cy: 568.0, nx: -0.86, ny: -0.50, flash: 0.0 }
        ]
    }

    static _ResetRun() {
        this._score := 0
        this._ballsLeft := 3
        this._ballNum := 1
        this._multiplier := 1
        this._rankIdx := 1
        this._missionHits := 0
        this._missionTarget := 6
        this._popups := []

        this._bumpers := [
            { x: 142.0, y: 230.0, r: 20.0, level: 1, flash: 0.0 },
            { x: 242.0, y: 230.0, r: 20.0, level: 1, flash: 0.0 },
            { x: 192.0, y: 300.0, r: 20.0, level: 1, flash: 0.0 }
        ]
        this._dropTargets := [
            { x: 46.0, y: 255.0, w: 10.0, h: 26.0, down: false, flash: 0.0 },
            { x: 46.0, y: 292.0, w: 10.0, h: 26.0, down: false, flash: 0.0 },
            { x: 46.0, y: 329.0, w: 10.0, h: 26.0, down: false, flash: 0.0 }
        ]
        this._rollovers := [
            { x: 136.0, y: 112.0, r: 12.0, lit: false, label: "L", inside: false },
            { x: 192.0, y: 112.0, r: 12.0, lit: false, label: "A", inside: false },
            { x: 248.0, y: 112.0, r: 12.0, lit: false, label: "U", inside: false }
        ]

        this._SpawnBallInShooter()
        this.Phase := "playing"
    }

    static _SpawnBallInShooter() {
        this._ballX := 378.0
        this._ballY := 655.0
        this._ballVx := 0.0
        this._ballVy := 0.0
        this._ballInShooter := true
        this._ballTrail := []
        this._plungerCharge := 0.0
        this._plungerHeld := false
        this._plungerMouseHeld := false
        this._ballSaveTimer := 12.0
        this._tiltHeat := 0.0
        this._tiltStrikes := 0
        this._tilted := false
        this._nudgeShake := 0.0
        this._orbitCd := 0.0
    }

    static _ReleasePlunger() {
        if (!this.IsActive || this.Phase != "playing")
            return
        if (this._ballInShooter && this._ballY > 560.0) {
            spd := 720.0 + 680.0 * Max(0.15, this._plungerCharge)
            this._ballVy := -spd
            this._ballVx := -14.0
            this._AddPopup("LAUNCH!", 0xFF38BDF8)
        }
        this._plungerCharge := 0.0
    }

    static Nudge() {
        if (!this.IsActive || this.Phase != "playing" || this._tilted || this._ballInShooter)
            return false
        this._nudgeShake := 0.22
        this._tiltHeat += 1.0
        this._tiltStrikes += 1
        this._ballVy -= 95.0
        this._ballVx += (Mod(A_TickCount, 2) = 0 ? 55.0 : -55.0)
        if (this._tiltStrikes >= 3 || this._tiltHeat >= 2.6) {
            this._tilted := true
            this._leftFlipperDown := false
            this._rightFlipperDown := false
            this._AddPopup("TILT! FLIPPERS LOCKED", 0xFFEF4444)
        } else {
            this._AddPopup("WARNING! NUDGE " this._tiltStrikes "/3", 0xFFF59E0B)
        }
        return true
    }

    static _AddScore(pts) {
        add := Integer(Round(pts * this._multiplier))
        this._score += add
        if (this._score > this._highScore) {
            this._highScore := this._score
            HudArcadeBase.SaveHighScore(this._cfg, "pinball", this._highScore)
        }
    }

    static _AddPopup(txt, argb := 0xFF38BDF8) {
        this._popups.Push({ text: txt, timer: 1.2, maxTimer: 1.2, argb: argb })
        if (this._popups.Length > 4)
            this._popups.RemoveAt(1)
    }

    static _AdvanceMission(hits := 1) {
        this._missionHits += hits
        if (this._missionHits >= this._missionTarget) {
            this._missionHits := 0
            this._missionTarget := Min(12, this._missionTarget + 2)
            if (this._rankIdx < this.RANKS.Length)
                this._rankIdx += 1
            this._AddScore(2500 * this._rankIdx)
            this._AddPopup("RANK UP: " StrUpper(this.RANKS[this._rankIdx]), 0xFFA855F7)
        }
    }

    static _FrameTick() {
        if (!this.IsActive)
            return
        nowUs := HudArcadeBase.NowUs()
        dtSec := Min(0.033, Max(0.001, (nowUs - this._lastUs) / 1000000.0))
        this._lastUs := nowUs
        if (this.Phase = "playing")
            this._Step(dtSec)
        this._RenderFrame()
    }

    static _PollLiveInput() {
        if (this._headless)
            return
        lDown := this._leftMouseDown || GetKeyState("Left", "P") || GetKeyState("z", "P") || GetKeyState("LShift", "P")
        rDown := this._rightMouseDown || GetKeyState("Right", "P") || GetKeyState("/", "P") || GetKeyState("RShift", "P")
        if (this._tilted) {
            this._leftFlipperDown := false
            this._rightFlipperDown := false
        } else {
            this._leftFlipperDown := lDown
            this._rightFlipperDown := rDown
        }
    }

    static _Step(dtSec) {
        this._PollLiveInput()

        if ((this._plungerHeld || this._plungerMouseHeld) && this._ballInShooter)
            this._plungerCharge := Min(1.0, this._plungerCharge + dtSec * 1.15)

        if (!this._ballInShooter && this._ballSaveTimer > 0.0)
            this._ballSaveTimer := Max(0.0, this._ballSaveTimer - dtSec)

        if (this._tiltHeat > 0.0) {
            this._tiltHeat := Max(0.0, this._tiltHeat - dtSec * 0.35)
            if (this._tiltHeat <= 0.05 && !this._tilted)
                this._tiltStrikes := 0
        }
        if (this._nudgeShake > 0.0)
            this._nudgeShake := Max(0.0, this._nudgeShake - dtSec)
        if (this._orbitCd > 0.0)
            this._orbitCd := Max(0.0, this._orbitCd - dtSec)

        for _, b in this._bumpers {
            if (b.flash > 0.0)
                b.flash := Max(0.0, b.flash - dtSec)
        }
        for _, s in this._slings {
            if (s.flash > 0.0)
                s.flash := Max(0.0, s.flash - dtSec)
        }
        for _, d in this._dropTargets {
            if (d.flash > 0.0)
                d.flash := Max(0.0, d.flash - dtSec)
        }
        i := this._popups.Length
        while (i >= 1) {
            this._popups[i].timer -= dtSec
            if (this._popups[i].timer <= 0.0)
                this._popups.RemoveAt(i)
            i -= 1
        }

        ; 4x Sub-stepped 240Hz physics
        subDt := dtSec / Float(this.SUBSTEPS)
        loop this.SUBSTEPS {
            this._SubStep(subDt)
            if (this.Phase != "playing")
                break
        }

        this._ballTrail.Push({ x: this._ballX, y: this._ballY })
        if (this._ballTrail.Length > 10)
            this._ballTrail.RemoveAt(1)
    }

    static _SubStep(subDt) {
        ; Update flippers with angular velocity tracking
        lTarget := (!this._tilted && this._leftFlipperDown) ? -0.54 : 0.46
        rTarget := (!this._tilted && this._rightFlipperDown) ? (3.14159265 + 0.54) : (3.14159265 - 0.46)
        lPrev := this._leftFlipperAngle
        rPrev := this._rightFlipperAngle

        this._leftFlipperAngle := this._MoveAngleToward(lPrev, lTarget, 22.0 * subDt)
        this._rightFlipperAngle := this._MoveAngleToward(rPrev, rTarget, 22.0 * subDt)
        this._leftFlipperOmega := (this._leftFlipperAngle - lPrev) / subDt
        this._rightFlipperOmega := (this._rightFlipperAngle - rPrev) / subDt

        ; Gravity & rolling damping
        this._ballVy += this.GRAVITY * subDt
        damp := Max(0.0, 1.0 - 0.12 * subDt)
        this._ballVx *= damp
        this._ballVy *= damp

        ; Clamp velocity
        spd := Sqrt(this._ballVx * this._ballVx + this._ballVy * this._ballVy)
        if (spd > this.MAX_SPEED) {
            f := this.MAX_SPEED / spd
            this._ballVx *= f
            this._ballVy *= f
        }

        this._ballX += this._ballVx * subDt
        this._ballY += this._ballVy * subDt

        ; Shooter lane tracking & one-way gate
        if (this._ballInShooter && this._ballX < 350.0)
            this._ballInShooter := false
        if (!this._ballInShooter) {
            ; One-way gate blocks re-entry into shooter lane (360, 80 -> 360, 155)
            this._CollideSegment(360.0, 80.0, 360.0, 155.0, 0.50)
        }

        ; Static walls
        for _, w in this._walls
            this._CollideSegment(w.x1, w.y1, w.x2, w.y2, w.e)

        ; Slingshots
        for _, s in this._slings {
            hitActive := this._CollideSegment(s.ax, s.ay, s.bx, s.by, 0.65)
            if (hitActive && !this._tilted) {
                this._ballVx += s.nx * 410.0
                this._ballVy += s.ny * 410.0
                s.flash := 0.16
                this._AddScore(100)
            }
            this._CollideSegment(s.bx, s.by, s.cx, s.cy, 0.45)
            this._CollideSegment(s.cx, s.cy, s.ax, s.ay, 0.45)
        }

        ; Swept angular capsule-vs-circle flipper collision
        this._CollideFlipper(120.0, 628.0, 58.0, 6.5, lPrev, this._leftFlipperAngle, this._leftFlipperOmega)
        this._CollideFlipper(264.0, 628.0, 58.0, 6.5, rPrev, this._rightFlipperAngle, this._rightFlipperOmega)

        ; Attack Pop Bumpers
        allUpgraded := true
        for _, b in this._bumpers {
            dx := this._ballX - b.x
            dy := this._ballY - b.y
            dist := Sqrt(dx * dx + dy * dy)
            minD := this.BALL_R + b.r
            if (dist < minD && dist > 0.0001) {
                nx := dx / dist, ny := dy / dist
                this._ballX := b.x + nx * minD
                this._ballY := b.y + ny * minD
                if (!this._tilted) {
                    vn := this._ballVx * nx + this._ballVy * ny
                    if (vn < 0.0) {
                        this._ballVx -= 1.85 * vn * nx
                        this._ballVy -= 1.85 * vn * ny
                    }
                    curS := Sqrt(this._ballVx * this._ballVx + this._ballVy * this._ballVy)
                    if (curS < 460.0) {
                        this._ballVx := nx * 460.0
                        this._ballVy := ny * 460.0
                    }
                    b.flash := 0.18
                    this._AddScore(150 * b.level)
                    this._AdvanceMission(1)
                } else {
                    this._ReflectNormal(nx, ny, 0.45)
                }
            }
            if (b.level < 3)
                allUpgraded := false
        }

        ; 3-bank Drop Targets
        allDown := true
        for _, d in this._dropTargets {
            if (!d.down) {
                if (this._CollideRect(d.x, d.y, d.w, d.h, 0.70)) {
                    if (!this._tilted) {
                        d.down := true
                        d.flash := 0.25
                        this._AddScore(500)
                        this._AdvanceMission(1)
                    }
                }
            }
            if (!d.down)
                allDown := false
        }
        if (allDown) {
            for _, d in this._dropTargets
                d.down := false
            this._multiplier := Min(10, this._multiplier + 1)
            this._AddScore(1500)
            this._AddPopup("DROP BANK! " this._multiplier "x MULTIPLIER", 0xFF22C55E)
            if (!allUpgraded) {
                for _, b in this._bumpers
                    b.level := Min(3, b.level + 1)
            }
        }

        ; 3 Re-Entry Rollover Lanes
        allLit := true
        for _, r in this._rollovers {
            dx := this._ballX - r.x, dy := this._ballY - r.y
            inZone := (dx * dx + dy * dy) <= (r.r + this.BALL_R) * (r.r + this.BALL_R)
            if (inZone && !r.inside && !this._tilted) {
                r.lit := !r.lit
                this._AddScore(250)
            }
            r.inside := inZone
            if (!r.lit)
                allLit := false
        }
        if (allLit) {
            for _, r in this._rollovers
                r.lit := false
            this._ballSaveTimer := Max(this._ballSaveTimer, 10.0)
            this._AdvanceMission(3)
            this._AddPopup("ROLLOVERS! BALL SAVE + RANK+", 0xFFFACC15)
        }

        ; Upper Orbit Sensor
        if (!this._ballInShooter && this._orbitCd <= 0.0 && this._ballY < 170.0 && (this._ballX < 70.0 || this._ballX > 310.0)) {
            if (Sqrt(this._ballVx * this._ballVx + this._ballVy * this._ballVy) > 380.0) {
                this._orbitCd := 1.4
                this._AddScore(1000)
                this._AdvanceMission(1)
                this._AddPopup("ORBIT LOOP! +1000", 0xFF38BDF8)
            }
        }

        ; Drain check
        if (this._ballY > this.TH - 12.0 && !this._ballInShooter) {
            if (this._ballSaveTimer > 0.0 && !this._tilted) {
                this._AddPopup("BALL SAVED!", 0xFF22C55E)
                this._SpawnBallInShooter()
                this._ballSaveTimer := 0.0
            } else {
                this._ballsLeft -= 1
                if (this._ballsLeft <= 0) {
                    this.Phase := "gameover"
                    if (this._score > this._highScore) {
                        this._highScore := this._score
                        HudArcadeBase.SaveHighScore(this._cfg, "pinball", this._highScore)
                    }
                } else {
                    this._ballNum += 1
                    this._multiplier := 1
                    this._SpawnBallInShooter()
                }
            }
        }
    }

    static _MoveAngleToward(cur, target, maxDelta) {
        diff := target - cur
        if (Abs(diff) <= maxDelta)
            return target
        return cur + (diff > 0 ? maxDelta : -maxDelta)
    }

    static _ReflectNormal(nx, ny, e) {
        vn := this._ballVx * nx + this._ballVy * ny
        if (vn < 0.0) {
            this._ballVx -= (1.0 + e) * vn * nx
            this._ballVy -= (1.0 + e) * vn * ny
        }
    }

    static _CollideSegment(x1, y1, x2, y2, e) {
        abx := x2 - x1, aby := y2 - y1
        lenSq := abx * abx + aby * aby
        if (lenSq < 0.0001)
            return false
        t := Max(0.0, Min(1.0, ((this._ballX - x1) * abx + (this._ballY - y1) * aby) / lenSq))
        cx := x1 + t * abx, cy := y1 + t * aby
        dx := this._ballX - cx, dy := this._ballY - cy
        distSq := dx * dx + dy * dy
        if (distSq >= this.BALL_R * this.BALL_R || distSq < 0.000001)
            return false
        dist := Sqrt(distSq)
        nx := dx / dist, ny := dy / dist
        this._ballX := cx + nx * this.BALL_R
        this._ballY := cy + ny * this.BALL_R
        this._ReflectNormal(nx, ny, e)
        return true
    }

    static _CollideRect(rx, ry, rw, rh, e) {
        cx := Max(rx, Min(rx + rw, this._ballX))
        cy := Max(ry, Min(ry + rh, this._ballY))
        dx := this._ballX - cx, dy := this._ballY - cy
        distSq := dx * dx + dy * dy
        if (distSq >= this.BALL_R * this.BALL_R)
            return false
        dist := Sqrt(distSq)
        if (dist < 0.0001) {
            nx := 1.0, ny := 0.0
        } else {
            nx := dx / dist, ny := dy / dist
        }
        this._ballX := cx + nx * this.BALL_R
        this._ballY := cy + ny * this.BALL_R
        this._ReflectNormal(nx, ny, e)
        return true
    }

    static _CollideFlipper(px, py, len, capR, prevAng, curAng, omega) {
        ; Check midpoint and current angle capsule to eliminate swept tunneling
        for _, ang in [(prevAng + curAng) * 0.5, curAng] {
            tx := px + Cos(ang) * len
            ty := py + Sin(ang) * len
            abx := tx - px, aby := ty - py
            lenSq := abx * abx + aby * aby
            t := Max(0.0, Min(1.0, ((this._ballX - px) * abx + (this._ballY - py) * aby) / lenSq))
            cx := px + t * abx, cy := py + t * aby
            dx := this._ballX - cx, dy := this._ballY - cy
            distSq := dx * dx + dy * dy
            minR := this.BALL_R + capR
            if (distSq < minR * minR && distSq > 0.000001) {
                dist := Sqrt(distSq)
                nx := dx / dist, ny := dy / dist
                this._ballX := cx + nx * minR
                this._ballY := cy + ny * minR
                ; Surface velocity at contact point due to angular rotation
                rx := cx - px, ry := cy - py
                surfVx := -omega * ry
                surfVy := omega * rx
                relVx := this._ballVx - surfVx
                relVy := this._ballVy - surfVy
                vn := relVx * nx + relVy * ny
                if (vn < 0.0) {
                    e := 0.55
                    this._ballVx -= (1.0 + e) * vn * nx
                    this._ballVy -= (1.0 + e) * vn * ny
                }
                return true
            }
        }
        return false
    }

    ; --- Rendering ---
    static _RenderFrame() {
        if (this._headless || !IsObject(this._surf))
            return
        if (!HudArcadeBase.BeginFrame(this._surf))
            return

        pG := this._surf.pGraphics
        W := Float(this._surf.W), H := Float(this._surf.H)
        isDark := HudArcadeBase.ResolveDarkMode(this._cfg)
        micMuted := HudArcadeBase.ResolveMicMuted(this._state)

        this._GetTableTransform(&ox, &oy, &sc)
        if (this._nudgeShake > 0.0) {
            ox += Sin(this._nudgeShake * 90.0) * 5.0
            oy += Cos(this._nudgeShake * 70.0) * 3.0
        }

        ; Cabinet frosted backdrop
        cabW := this.TW * sc, cabH := this.TH * sc
        HudArcadeBase.FillRoundedRect(pG, ox - 8.0, oy - 8.0, cabW + 16.0, cabH + 16.0, 20.0, 0xE6090D18)
        HudArcadeBase.StrokeRoundedRect(pG, ox - 8.0, oy - 8.0, cabW + 16.0, cabH + 16.0, 20.0, this._tilted ? 0xFFEF4444 : 0xFF38BDF8, 2.2)

        ; Draw walls
        for _, w in this._walls
            this._DrawLine(pG, ox + w.x1 * sc, oy + w.y1 * sc, ox + w.x2 * sc, oy + w.y2 * sc, 0xFF38BDF8, 2.2)

        ; One-way shooter gate (dashed amber)
        this._DrawLine(pG, ox + 360.0 * sc, oy + 80.0 * sc, ox + 360.0 * sc, oy + 155.0 * sc, this._ballInShooter ? 0x66FACC15 : 0xFFEF4444, 2.0)

        ; Plunger spring
        pTop := 665.0 + this._plungerCharge * 16.0
        this._DrawLine(pG, ox + 378.0 * sc, oy + pTop * sc, ox + 378.0 * sc, oy + 684.0 * sc, 0xFFF59E0B, 6.0 * sc)

        ; Rollover lanes
        for _, r in this._rollovers {
            col := r.lit ? 0xFFFACC15 : 0x5594A3B8
            this._DrawCircle(pG, ox + r.x * sc, oy + r.y * sc, r.r * sc, r.lit ? 0x55FACC15 : 0x220F172A, col, 1.8)
            Gdip.DrawText(pG, r.label, "Consolas", 8.0 * sc, 1, r.lit ? 0xFFFEF08A : 0xFF94A3B8, ox + (r.x - 10.0) * sc, oy + (r.y - 8.0) * sc, 20.0 * sc, 16.0 * sc, 1, 1, 0, false)
        }

        ; Drop targets
        for _, d in this._dropTargets {
            col := d.down ? 0x33475569 : (d.flash > 0.0 ? 0xFFFFFFFF : 0xFF22C55E)
            HudArcadeBase.FillRoundedRect(pG, ox + d.x * sc, oy + d.y * sc, d.w * sc, d.h * sc, 3.0, col)
        }

        ; Slingshots
        for _, s in this._slings {
            col := s.flash > 0.0 ? 0xFFFDE047 : 0xFFA855F7
            this._DrawLine(pG, ox + s.ax * sc, oy + s.ay * sc, ox + s.bx * sc, oy + s.by * sc, col, 3.0)
            this._DrawLine(pG, ox + s.bx * sc, oy + s.by * sc, ox + s.cx * sc, oy + s.cy * sc, 0xFF64748B, 2.0)
            this._DrawLine(pG, ox + s.cx * sc, oy + s.cy * sc, ox + s.ax * sc, oy + s.ay * sc, 0xFF64748B, 2.0)
        }

        ; Attack Pop Bumpers
        for _, b in this._bumpers {
            baseCol := b.level = 1 ? 0xFF06B6D4 : (b.level = 2 ? 0xFFF59E0B : 0xFFEC4899)
            fillCol := b.flash > 0.0 ? 0xCCFFFFFF : (b.level = 1 ? 0x5506B6D4 : (b.level = 2 ? 0x55F59E0B : 0x55EC4899))
            this._DrawCircle(pG, ox + b.x * sc, oy + b.y * sc, b.r * sc, fillCol, baseCol, 2.6)
        }

        ; Mission & Rank Center LED
        Gdip.DrawText(pG, StrUpper(this.RANKS[this._rankIdx]) " (" this._multiplier "x)", "Consolas", 9.0 * sc, 1, 0xFFC084FC, ox + 100.0 * sc, oy + 365.0 * sc, 184.0 * sc, 20.0 * sc, 1, 1, 0, false)
        if (this._ballSaveTimer > 0.0)
            Gdip.DrawText(pG, "BALL SAVE", "Consolas", 8.5 * sc, 1, 0xFF22C55E, ox + 132.0 * sc, oy + 595.0 * sc, 120.0 * sc, 18.0 * sc, 1, 1, 0, false)

        ; Flippers
        ltx := 120.0 + Cos(this._leftFlipperAngle) * 58.0
        lty := 628.0 + Sin(this._leftFlipperAngle) * 58.0
        rtx := 264.0 + Cos(this._rightFlipperAngle) * 58.0
        rty := 628.0 + Sin(this._rightFlipperAngle) * 58.0
        fCol := this._tilted ? 0xFF64748B : 0xFF38BDF8
        this._DrawLine(pG, ox + 120.0 * sc, oy + 628.0 * sc, ox + ltx * sc, oy + lty * sc, fCol, 11.0 * sc)
        this._DrawLine(pG, ox + 264.0 * sc, oy + 628.0 * sc, ox + rtx * sc, oy + rty * sc, fCol, 11.0 * sc)

        ; Ball trail & ball
        for idx, pt in this._ballTrail {
            alpha := Integer(Round(18.0 * idx)) << 24
            this._DrawCircle(pG, ox + pt.x * sc, oy + pt.y * sc, (this.BALL_R * 0.65) * sc, alpha | 0x38BDF8, 0, 0.0)
        }
        this._DrawCircle(pG, ox + this._ballX * sc, oy + this._ballY * sc, this.BALL_R * sc, 0xFFF8FAFC, 0xFF38BDF8, 2.0)

        ; Popups
        py := oy + 410.0 * sc
        for _, p in this._popups {
            Gdip.DrawText(pG, p.text, "Segoe UI", 10.0 * sc, 1, p.argb, ox + 40.0 * sc, py, 304.0 * sc, 22.0 * sc, 1, 1, 0, false)
            py += 20.0 * sc
        }

        ; Scoreboard Pill
        stats := "SCORE: " this._score "   |   BALL: " this._ballNum "/3   |   RANK: " this.RANKS[this._rankIdx] "   |   BEST: " this._highScore
        hint := "Flippers: Left/Right, Z//, L/RShift or Click   •   Launch: Space   •   Nudge: Up/X/RClick   •   P: Pause   •   Esc: Exit"
        HudArcadeBase.DrawScoreboardPill(pG, W, "SPACE CADET PINBALL", stats, hint, isDark, micMuted)

        if (this.Phase = "paused")
            HudArcadeBase.DrawOverlayCard(pG, W, H, "PAUSED", "Score: " this._score "  •  Rank: " this.RANKS[this._rankIdx], "Press P to resume  •  Esc to exit", 0xFF38BDF8, isDark)
        else if (this.Phase = "gameover")
            HudArcadeBase.DrawOverlayCard(pG, W, H, "GAME OVER", "Final Score: " this._score "  •  Best: " this._highScore, "Press R, Space, or Click to play again  •  Esc to exit", 0xFFEF4444, isDark)

        HudArcadeBase.PresentFrame(this._surf)
    }

    static _DrawLine(pG, x1, y1, x2, y2, argb, width) {
        HudArcadeBase.DrawLine(pG, x1, y1, x2, y2, argb, width, true)
    }

    static _DrawCircle(pG, cx, cy, r, fillArgb, strokeArgb, strokeW) {
        HudArcadeBase.DrawCircle(pG, cx, cy, r, fillArgb, strokeArgb, strokeW)
    }
}
