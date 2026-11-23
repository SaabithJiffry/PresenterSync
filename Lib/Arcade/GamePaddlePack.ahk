; ==============================================================================
; Module: GamePaddlePack.ahk
; Description: Milestone M3 — Paddle & Ball Physics Pack
;              - PaddlePhysicsCore: Shared 2D elastic circle-vs-rect collision,
;                paddle velocity spin transfer, Magnus spin curve, & angle clamp
;              - GameBrickBreaker (^!+b, "brick_breaker"): Neon bottom-edge
;                paddle, armored multi-hit bricks (hp 1..3), falling HUD-pill
;                drops (MULTIBALL, WIDE PADDLE, LASER), progressive waves
;              - GameCyberPong (^!+h, "cyber_pong"): Opposing neon paddles,
;                curving velocity-spin energy puck, adaptive 1P AI + 2P mode,
;                rally streak counter, first-to-7 sets
; ==============================================================================

#Include "%A_LineFile%\..\..\HudArcadeBase.ahk"

class PaddlePhysicsCore {
    static Clamp(val, lo, hi) {
        return HudArcadeBase.Clamp(Float(val), Float(lo), Float(hi))
    }

    static CollideCircleRect(ball, rx, ry, rw, rh) {
        bx := Float(ball.x), by := Float(ball.y), br := Float(ball.radius)
        left := Float(rx), top := Float(ry), right := left + Float(rw), bottom := top + Float(rh)
        cx := Max(left, Min(bx, right))
        cy := Max(top, Min(by, bottom))
        dx := bx - cx
        dy := by - cy
        d2 := dx * dx + dy * dy
        if (d2 > br * br)
            return false

        ; Determine dominant overlap axis and separate cleanly
        midX := left + Float(rw) * 0.5
        midY := top + Float(rh) * 0.5
        overlapX := (Float(rw) * 0.5 + br) - Abs(bx - midX)
        overlapY := (Float(rh) * 0.5 + br) - Abs(by - midY)

        if (overlapX < overlapY) {
            if (bx < midX) {
                ball.x := left - br - 0.5
                ball.vx := -Abs(Float(ball.vx))
            } else {
                ball.x := right + br + 0.5
                ball.vx := Abs(Float(ball.vx))
            }
        } else {
            if (by < midY) {
                ball.y := top - br - 0.5
                ball.vy := -Abs(Float(ball.vy))
            } else {
                ball.y := bottom + br + 0.5
                ball.vy := Abs(Float(ball.vy))
            }
        }
        return true
    }

    static BounceHorizontalPaddle(ball, px, py, pw, ph, padVx := 0.0, minSpeed := 420.0, maxSpeed := 780.0) {
        bx := Float(ball.x), by := Float(ball.y), br := Float(ball.radius)
        left := Float(px), top := Float(py), right := left + Float(pw), bottom := top + Float(ph)
        if (bx + br < left || bx - br > right || by + br < top || by - br > bottom)
            return false
        if (Float(ball.vy) <= 0.0)
            return false

        rel := ((bx - (left + Float(pw) * 0.5)) / Max(1.0, Float(pw) * 0.5))
        rel := this.Clamp(rel, -1.0, 1.0)
        spd := Sqrt(Float(ball.vx) * Float(ball.vx) + Float(ball.vy) * Float(ball.vy))
        spd := this.Clamp(spd * 1.015, minSpeed, maxSpeed)

        ; Deflection angle from vertical (-62 deg .. +62 deg) + paddle velocity spin transfer
        ang := rel * 1.08
        vx := Sin(ang) * spd + Float(padVx) * 0.35
        vy := -Max(minSpeed * 0.45, Abs(Cos(ang) * spd))

        ; Re-normalize speed within bounds & enforce anti-flat vertical ratio
        newSpd := Sqrt(vx * vx + vy * vy)
        targetSpd := this.Clamp(newSpd, minSpeed, maxSpeed)
        if (newSpd > 1.0) {
            vx := (vx / newSpd) * targetSpd
            vy := (vy / newSpd) * targetSpd
        }
        if (Abs(vy) < targetSpd * 0.32) {
            vy := -targetSpd * 0.32
            sgn := (vx < 0.0) ? -1.0 : 1.0
            vx := sgn * Sqrt(Max(1.0, targetSpd * targetSpd - vy * vy))
        }

        ball.y := top - br - 1.0
        ball.vx := vx
        ball.vy := vy
        if (ball.HasOwnProp("spin"))
            ball.spin := this.Clamp(Float(ball.spin) * 0.5 + Float(padVx) * 0.85, -520.0, 520.0)
        return true
    }

    static BounceVerticalPaddle(puck, px, py, pw, ph, padVy := 0.0, isLeft := true, minSpeed := 480.0, maxSpeed := 980.0) {
        bx := Float(puck.x), by := Float(puck.y), br := Float(puck.radius)
        left := Float(px), top := Float(py), right := left + Float(pw), bottom := top + Float(ph)
        if (bx + br < left || bx - br > right || by + br < top || by - br > bottom)
            return false
        if (isLeft && Float(puck.vx) >= 0.0)
            return false
        if (!isLeft && Float(puck.vx) <= 0.0)
            return false

        rel := ((by - (top + Float(ph) * 0.5)) / Max(1.0, Float(ph) * 0.5))
        rel := this.Clamp(rel, -1.0, 1.0)
        spd := Sqrt(Float(puck.vx) * Float(puck.vx) + Float(puck.vy) * Float(puck.vy))
        spd := this.Clamp(spd * 1.045, minSpeed, maxSpeed)

        ang := rel * 0.98
        dirX := isLeft ? 1.0 : -1.0
        vx := dirX * Max(minSpeed * 0.52, Abs(Cos(ang) * spd))
        vy := Sin(ang) * spd + Float(padVy) * 0.42

        newSpd := Sqrt(vx * vx + vy * vy)
        targetSpd := this.Clamp(newSpd, minSpeed, maxSpeed)
        if (newSpd > 1.0) {
            vx := (vx / newSpd) * targetSpd
            vy := (vy / newSpd) * targetSpd
        }
        if (Abs(vx) < targetSpd * 0.42) {
            vx := dirX * targetSpd * 0.42
            sgnY := (vy < 0.0) ? -1.0 : 1.0
            vy := sgnY * Sqrt(Max(1.0, targetSpd * targetSpd - vx * vx))
        }

        puck.x := isLeft ? (right + br + 1.0) : (left - br - 1.0)
        puck.vx := vx
        puck.vy := vy
        ; Spin transfer from paddle vertical velocity + hit offset
        puck.spin := this.Clamp(Float(padVy) * 1.35 + rel * 180.0, -720.0, 720.0)
        return true
    }
}

; ==============================================================================
; Game 3: Desktop Brick Breaker (Ctrl+Alt+Shift+B)
; ==============================================================================
class GameBrickBreaker {
    static IsActive := false
    static Phase := "idle" ; "idle" | "playing" | "paused" | "gameover"
    static _surf := ""
    static _cfg := ""
    static _state := ""
    static _savedPolling := ""
    static _boundHotkeys := []
    static _tickFn := ""
    static _lastUs := 0.0
    static _headless := false

    static _paddle := ""
    static _balls := []
    static _bricks := []
    static _drops := []
    static _lasers := []
    static _particles := []
    static _popups := []

    static _score := 0
    static _highScore := 0
    static _wave := 1
    static _lives := 3
    static _wideMs := 0.0
    static _laserMs := 0.0
    static _laserCdMs := 0.0
    static _mouseX := 0.0
    static _mouseActive := false
    static _mouseDown := false

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
            title: "PresenterSyncBrickBreaker",
            onMouseEvent: this._OnMouse.Bind(this),
            headless: this._headless
        })
        if (!IsObject(this._surf))
            return false

        this.IsActive := true
        HudArcadeBase.RegisterActiveGame(this, "brick_breaker")
        this._highScore := HudArcadeBase.LoadHighScore(cfg, "brick_breaker")
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
        HudArcadeBase.ClearActiveGame("brick_breaker")
    }

    static _BindKeys(cfg) {
        condFn := (*) => GameBrickBreaker.IsActive
        noop(*) {
        }
        bindings := [
            { key: "$Left", fn: noop },
            { key: "$Right", fn: noop },
            { key: "$a", fn: noop },
            { key: "$d", fn: noop },
            { key: "$Space", fn: (*) => GameBrickBreaker.LaunchOrFire() },
            { key: "$p", fn: (*) => GameBrickBreaker.TogglePause() },
            { key: "$r", fn: (*) => (GameBrickBreaker.Phase = "gameover" ? GameBrickBreaker._ResetRun() : 0) },
            { key: "$Escape", fn: (*) => GameBrickBreaker.Stop() }
        ]
        HudArcadeBase.BindKeysSafe(cfg, bindings, this._boundHotkeys, condFn)
    }

    static _OnMouse(msg, x, y, wp) {
        if (!this.IsActive)
            return
        this._mouseX := Float(x)
        this._mouseActive := true
        if (msg == 0x0201 || msg == 0x0203) {
            this._mouseDown := true
            if (this.Phase = "gameover")
                this._ResetRun()
            else
                this.LaunchOrFire()
        } else if (msg == 0x0202) {
            this._mouseDown := false
        } else if (msg == 0x0204) {
            this.TogglePause()
        } else if (msg == 0x0200) {
            this._mouseDown := ((wp & 1) != 0)
        }
    }

    static TogglePause() {
        if (!this.IsActive)
            return
        if (this.Phase = "playing")
            this.Phase := "paused"
        else if (this.Phase = "paused") {
            this.Phase := "playing"
            this._lastUs := HudArcadeBase.NowUs()
        }
    }

    static _ResetRun() {
        W := Float(this._surf.W), H := Float(this._surf.H)
        this._score := 0
        this._wave := 1
        this._lives := 3
        this._wideMs := 0.0
        this._laserMs := 0.0
        this._laserCdMs := 0.0
        this._mouseActive := false
        this._mouseDown := false
        this._drops := []
        this._lasers := []
        this._particles := []
        this._popups := []
        this._paddle := {
            x: (W - 132.0) * 0.5,
            y: H - 46.0,
            w: 132.0,
            baseW: 132.0,
            h: 16.0,
            vx: 0.0
        }
        this._ResetBallOnPaddle()
        this._SpawnWave(1)
        this.Phase := "playing"
    }

    static _ResetBallOnPaddle() {
        p := this._paddle
        this._balls := [{
            x: p.x + p.w * 0.5,
            y: p.y - 10.0,
            vx: 210.0,
            vy: -440.0,
            radius: 8.5,
            spin: 0.0,
            stuck: true
        }]
    }

    static _SpawnWave(waveNum) {
        this._bricks := []
        W := Float(this._surf.W)
        cols := 10
        rows := Min(7, 3 + waveNum)
        marginX := Max(60.0, W * 0.10)
        availW := W - marginX * 2.0
        gap := 8.0
        bw := Max(44.0, (availW - gap * (cols - 1)) / cols)
        bh := 24.0
        startY := 92.0

        Loop rows {
            r := A_Index
            ; Top rows have multi-hit armor (hp 2..3), lower rows hp 1..2
            hp := (r == 1 && waveNum >= 2) ? 3 : ((r <= 2) ? Min(3, 1 + ((waveNum + 1) // 2)) : 1)
            Loop cols {
                c := A_Index
                bx := marginX + (c - 1) * (bw + gap)
                by := startY + (r - 1) * (bh + gap)
                this._bricks.Push({
                    x: bx,
                    y: by,
                    w: bw,
                    h: bh,
                    hp: hp,
                    maxHp: hp,
                    dropKind: ""
                })
            }
        }
    }

    static LaunchOrFire() {
        if (!this.IsActive || this.Phase != "playing")
            return false
        launched := false
        for _, b in this._balls {
            if (b.stuck) {
                b.stuck := false
                if (Abs(b.vy) < 200.0)
                    b.vy := -450.0
                if (Abs(b.vx) < 40.0)
                    b.vx := 180.0
                launched := true
            }
        }
        if (this._laserMs > 0.0 && this._laserCdMs <= 0.0) {
            this.FireLaser()
            return true
        }
        return launched
    }

    static FireLaser() {
        if (!this.IsActive || this.Phase != "playing")
            return false
        p := this._paddle
        this._laserCdMs := 220.0
        this._lasers.Push({ x: p.x + 14.0, y: p.y - 6.0, vy: -760.0, w: 4.0, h: 16.0 })
        this._lasers.Push({ x: p.x + p.w - 18.0, y: p.y - 6.0, vy: -760.0, w: 4.0, h: 16.0 })
        return true
    }

    static _FrameTick() {
        if (!this.IsActive)
            return
        nowUs := HudArcadeBase.NowUs()
        dtSec := Min(0.05, Max(0.001, (nowUs - this._lastUs) / 1000000.0))
        this._lastUs := nowUs
        this.StepSimulation(dtSec, true)
        this._RenderFrame()
    }

    static StepForTest(dtSec, readHardwareInput := false) {
        this.StepSimulation(dtSec, readHardwareInput)
    }

    static StepSimulation(dtSec, readHardwareInput := false) {
        if (!this.IsActive || this.Phase != "playing")
            return
        dt := Min(0.05, Max(0.0001, Float(dtSec)))
        dtMs := dt * 1000.0
        W := Float(this._surf.W), H := Float(this._surf.H)
        p := this._paddle

        ; Power-up timers
        if (this._wideMs > 0.0) {
            this._wideMs := Max(0.0, this._wideMs - dtMs)
        }
        targetW := (this._wideMs > 0.0) ? (p.baseW * 1.55) : p.baseW
        if (Abs(p.w - targetW) > 0.5) {
            center := p.x + p.w * 0.5
            p.w := targetW
            p.x := PaddlePhysicsCore.Clamp(center - p.w * 0.5, 16.0, W - p.w - 16.0)
        }

        if (this._laserMs > 0.0)
            this._laserMs := Max(0.0, this._laserMs - dtMs)
        if (this._laserCdMs > 0.0)
            this._laserCdMs := Max(0.0, this._laserCdMs - dtMs)

        prevPx := p.x
        if (readHardwareInput) {
            mvL := GetKeyState("Left", "P") || GetKeyState("a", "P")
            mvR := GetKeyState("Right", "P") || GetKeyState("d", "P")
            fireKey := GetKeyState("Space", "P") || this._mouseDown

            gp := HudArcadeBase.PollXInput()
            if (IsObject(gp)) {
                if ((gp.btn & 0x0004) || gp.lx < -8500)
                    mvL := true
                if ((gp.btn & 0x0008) || gp.lx > 8500)
                    mvR := true
                if (gp.btn & 0x1000)
                    fireKey := true
            }
            if (mvL || mvR)
                this._mouseActive := false

            if (this._mouseActive) {
                targetX := PaddlePhysicsCore.Clamp(this._mouseX - p.w * 0.5, 16.0, W - p.w - 16.0)
                p.x := targetX
            } else {
                padSpd := 680.0
                if (mvL)
                    p.x -= padSpd * dt
                if (mvR)
                    p.x += padSpd * dt
                p.x := PaddlePhysicsCore.Clamp(p.x, 16.0, W - p.w - 16.0)
            }
            p.vx := (p.x - prevPx) / Max(0.001, dt)
            if (fireKey)
                this.LaunchOrFire()
        }

        ; Update balls
        bIdx := this._balls.Length
        while (bIdx >= 1) {
            b := this._balls[bIdx]
            if (b.stuck) {
                b.x := p.x + p.w * 0.5
                b.y := p.y - b.radius - 1.5
                bIdx -= 1
                continue
            }

            ; Slight lateral spin curve
            if (Abs(b.spin) > 1.0) {
                b.vx += b.spin * 0.22 * dt
                b.spin *= (1.0 - Min(0.9, 1.8 * dt))
            }

            b.x += b.vx * dt
            b.y += b.vy * dt

            ; Wall reflections (left, right, top)
            if (b.x - b.radius < 12.0) {
                b.x := 12.0 + b.radius
                b.vx := Abs(b.vx)
            } else if (b.x + b.radius > W - 12.0) {
                b.x := W - 12.0 - b.radius
                b.vx := -Abs(b.vx)
            }
            if (b.y - b.radius < 64.0) {
                b.y := 64.0 + b.radius
                b.vy := Abs(b.vy)
            }

            ; Paddle bounce
            PaddlePhysicsCore.BounceHorizontalPaddle(b, p.x, p.y, p.w, p.h, p.vx)

            ; Brick collisions
            kIdx := this._bricks.Length
            while (kIdx >= 1) {
                br := this._bricks[kIdx]
                if (PaddlePhysicsCore.CollideCircleRect(b, br.x, br.y, br.w, br.h)) {
                    this._DamageBrick(kIdx)
                    break
                }
                kIdx -= 1
            }

            ; Bottom drain
            if (b.y - b.radius > H + 12.0) {
                this._balls.RemoveAt(bIdx)
            }
            bIdx -= 1
        }

        ; Lose life only when all active balls drain
        if (this._balls.Length == 0) {
            this._lives -= 1
            if (this._lives <= 0) {
                this.Phase := "gameover"
                return
            } else {
                this._wideMs := 0.0
                this._laserMs := 0.0
                this._ResetBallOnPaddle()
            }
        }

        ; Update laser bolts
        lIdx := this._lasers.Length
        while (lIdx >= 1) {
            ls := this._lasers[lIdx]
            ls.y += ls.vy * dt
            if (ls.y < 60.0) {
                this._lasers.RemoveAt(lIdx)
                lIdx -= 1
                continue
            }
            hitBrick := false
            kIdx := this._bricks.Length
            while (kIdx >= 1) {
                br := this._bricks[kIdx]
                if (ls.x + ls.w >= br.x && ls.x <= br.x + br.w && ls.y <= br.y + br.h && ls.y + ls.h >= br.y) {
                    this._DamageBrick(kIdx)
                    hitBrick := true
                    break
                }
                kIdx -= 1
            }
            if (hitBrick)
                this._lasers.RemoveAt(lIdx)
            lIdx -= 1
        }

        ; Update falling HUD-pill drops
        dIdx := this._drops.Length
        while (dIdx >= 1) {
            dr := this._drops[dIdx]
            dr.y += dr.vy * dt
            if (dr.y > H + 24.0) {
                this._drops.RemoveAt(dIdx)
                dIdx -= 1
                continue
            }
            ; Paddle catch check
            if (dr.x + dr.w * 0.5 >= p.x && dr.x - dr.w * 0.5 <= p.x + p.w && dr.y + dr.h * 0.5 >= p.y && dr.y - dr.h * 0.5 <= p.y + p.h) {
                this._ApplyDrop(dr.kind, dr.x, dr.y)
                this._drops.RemoveAt(dIdx)
            }
            dIdx -= 1
        }

        ; Update particles & score popups
        idx := this._particles.Length
        while (idx >= 1) {
            pt := this._particles[idx]
            pt.ttlMs -= dtMs
            if (pt.ttlMs <= 0.0)
                this._particles.RemoveAt(idx)
            else {
                pt.x += pt.vx * dt
                pt.y += pt.vy * dt
            }
            idx -= 1
        }
        idx := this._popups.Length
        while (idx >= 1) {
            pp := this._popups[idx]
            pp.ttlMs -= dtMs
            if (pp.ttlMs <= 0.0)
                this._popups.RemoveAt(idx)
            else
                pp.y -= 26.0 * dt
            idx -= 1
        }

        ; Wave clear progression
        if (this._bricks.Length == 0) {
            this._wave += 1
            this._AddScore(200, W * 0.5, H * 0.45, 0xFF38BDF8)
            this._SpawnWave(this._wave)
            this._ResetBallOnPaddle()
        }
    }

    static _DamageBrick(idx) {
        if (idx < 1 || idx > this._bricks.Length)
            return
        br := this._bricks[idx]
        br.hp -= 1
        cx := br.x + br.w * 0.5
        cy := br.y + br.h * 0.5
        if (br.hp > 0) {
            this._AddScore(15, cx, cy, 0xFFF59E0B)
            this._SpawnSparks(cx, cy, 0xFFF59E0B, 5)
            return
        }
        this._bricks.RemoveAt(idx)
        pts := 30 * Max(1, br.maxHp)
        this._AddScore(pts, cx, cy, 0xFF34D399)
        this._SpawnSparks(cx, cy, 0xFF38BDF8, 9)

        if (br.dropKind != "") {
            this.SpawnDropForTest(cx, cy, br.dropKind)
        } else if (Random(1, 100) <= 24) {
            kinds := ["MULTIBALL", "WIDE PADDLE", "LASER"]
            this.SpawnDropForTest(cx, cy, kinds[Random(1, 3)])
        }
    }

    static _ApplyDrop(kind, x, y) {
        k := StrUpper(Trim(String(kind)))
        this._AddScore(50, x, y, 0xFF38BDF8)
        this._popups.Push({ x: x, y: y - 10.0, text: k, ttlMs: 900.0, col: 0xFF38BDF8 })
        if (k = "MULTIBALL") {
            if (this._balls.Length == 0)
                this._ResetBallOnPaddle()
            src := this._balls[1]
            src.stuck := false
            baseSpd := Max(430.0, Sqrt(src.vx * src.vx + src.vy * src.vy))
            for _, ang in [-0.48, 0.48] {
                if (this._balls.Length >= 6)
                    break
                this._balls.Push({
                    x: src.x,
                    y: src.y,
                    vx: Sin(ang) * baseSpd,
                    vy: -Abs(Cos(ang) * baseSpd),
                    radius: src.radius,
                    spin: 0.0,
                    stuck: false
                })
            }
        } else if (k = "WIDE PADDLE" || k = "WIDE") {
            this._wideMs := 12000.0
            this._paddle.w := this._paddle.baseW * 1.55
        } else if (k = "LASER") {
            this._laserMs := 10000.0
            this._laserCdMs := 0.0
        }
    }

    static _AddScore(pts, x, y, col) {
        this._score += pts
        if (this._score > this._highScore) {
            this._highScore := this._score
            HudArcadeBase.SaveHighScore(this._cfg, "brick_breaker", this._highScore)
        }
        this._popups.Push({ x: x, y: y, text: "+" pts, ttlMs: 700.0, col: col })
    }

    static _SpawnSparks(x, y, col, count) {
        Loop count {
            ang := Float(Random(0, 628)) / 100.0
            spd := Float(Random(45, 165))
            this._particles.Push({ x: x, y: y, vx: Cos(ang) * spd, vy: Sin(ang) * spd, ttlMs: 360.0, col: col })
        }
    }

    ; --- Headless Test Helpers ---
    static SpawnBrickForTest(x, y, w := 68.0, h := 24.0, hp := 1, dropKind := "") {
        br := {
            x: Float(x),
            y: Float(y),
            w: Float(w),
            h: Float(h),
            hp: Max(1, Integer(hp)),
            maxHp: Max(1, Integer(hp)),
            dropKind: String(dropKind)
        }
        this._bricks.Push(br)
        return br
    }

    static SpawnDropForTest(x, y, kind := "MULTIBALL") {
        dr := {
            x: Float(x),
            y: Float(y),
            w: 64.0,
            h: 22.0,
            vy: 175.0,
            kind: String(kind)
        }
        this._drops.Push(dr)
        return dr
    }

    static SetBallForTest(x, y, vx, vy, stuck := false, spin := 0.0) {
        b := {
            x: Float(x),
            y: Float(y),
            vx: Float(vx),
            vy: Float(vy),
            radius: 8.5,
            spin: Float(spin),
            stuck: !!stuck
        }
        this._balls := [b]
        return b
    }

    static SetPaddleForTest(x, vx := 0.0) {
        if (IsObject(this._paddle)) {
            this._paddle.x := Float(x)
            this._paddle.vx := Float(vx)
        }
    }

    static GetSnapshot() {
        return this.GetStateSnapshot()
    }

    static GetStateSnapshot() {
        return {
            active: this.IsActive,
            phase: this.Phase,
            score: this._score,
            highScore: this._highScore,
            wave: this._wave,
            lives: this._lives,
            brickCount: this._bricks.Length,
            ballCount: this._balls.Length,
            dropCount: this._drops.Length,
            laserCount: this._lasers.Length,
            paddleX: IsObject(this._paddle) ? this._paddle.x : 0.0,
            paddleY: IsObject(this._paddle) ? this._paddle.y : 0.0,
            paddleW: IsObject(this._paddle) ? this._paddle.w : 0.0,
            wideMs: this._wideMs,
            laserMs: this._laserMs,
            balls: this._balls,
            bricks: this._bricks
        }
    }

    static _RenderFrame() {
        if (!IsObject(this._surf) || !this._surf.pGraphics)
            return
        HudArcadeBase.BeginFrame(this._surf)
        g := this._surf.pGraphics
        W := this._surf.W, H := this._surf.H

        ; Draw multi-hit armored bricks
        for _, br in this._bricks {
            fillCol := (br.hp >= 3) ? 0xD8F59E0B : ((br.hp == 2) ? 0xD838BDF8 : 0xD810B981)
            brdCol := (br.hp >= 3) ? 0xFFFDE68A : ((br.hp == 2) ? 0xFFBAE6FD : 0xFFA7F3D0)
            HudArcadeBase.FillRoundedRect(g, br.x, br.y, br.w, br.h, 6.0, fillCol)
            HudArcadeBase.StrokeRoundedRect(g, br.x, br.y, br.w, br.h, 6.0, brdCol, (br.hp >= 2) ? 2.0 : 1.2)
            if (br.hp >= 2)
                Gdip.DrawText(g, "x" br.hp, "Segoe UI", 8.0, 1, 0xFF0F172A, br.x, br.y, br.w, br.h, 1, 1, 0, false)
        }

        ; Draw falling HUD-pill drops
        for _, dr in this._drops {
            col := (dr.kind = "MULTIBALL") ? 0xE038BDF8 : ((InStr(dr.kind, "WIDE")) ? 0xE010B981 : 0xE0F43F5E)
            HudArcadeBase.FillRoundedRect(g, dr.x - dr.w * 0.5, dr.y - dr.h * 0.5, dr.w, dr.h, 9.0, col)
            HudArcadeBase.StrokeRoundedRect(g, dr.x - dr.w * 0.5, dr.y - dr.h * 0.5, dr.w, dr.h, 9.0, 0xFFFFFFFF, 1.2)
            lbl := (dr.kind = "MULTIBALL") ? "MULTI" : ((InStr(dr.kind, "WIDE")) ? "WIDE" : "LASER")
            Gdip.DrawText(g, lbl, "Segoe UI", 7.5, 1, 0xFFFFFFFF, dr.x - dr.w * 0.5, dr.y - dr.h * 0.5, dr.w, dr.h, 1, 1, 0, false)
        }

        ; Draw laser bolts
        for _, ls in this._lasers {
            HudArcadeBase.FillRoundedRect(g, ls.x, ls.y, ls.w, ls.h, 2.0, 0xFFFB7185)
        }

        ; Draw neon bottom-edge paddle
        p := this._paddle
        padFill := (this._laserMs > 0.0) ? 0xE6F43F5E : ((this._wideMs > 0.0) ? 0xE610B981 : 0xE60EA5E9)
        HudArcadeBase.FillRoundedRect(g, p.x, p.y, p.w, p.h, 8.0, padFill)
        HudArcadeBase.StrokeRoundedRect(g, p.x, p.y, p.w, p.h, 8.0, 0xFFE0F2FE, 1.8)

        ; Draw energy balls & particles
        pBallBrush := 0, pGlowBrush := 0, pPartBrush := 0
        DllCall("gdiplus\GdipCreateSolidFill", "UInt", 0xFFF8FAFC, "Ptr*", &pBallBrush)
        DllCall("gdiplus\GdipCreateSolidFill", "UInt", 0x6638BDF8, "Ptr*", &pGlowBrush)
        try {
            for _, b in this._balls {
                r := b.radius
                if (pGlowBrush)
                    DllCall("gdiplus\GdipFillEllipse", "Ptr", g, "Ptr", pGlowBrush, "Float", b.x - r - 3.0, "Float", b.y - r - 3.0, "Float", (r + 3.0) * 2.0, "Float", (r + 3.0) * 2.0)
                if (pBallBrush)
                    DllCall("gdiplus\GdipFillEllipse", "Ptr", g, "Ptr", pBallBrush, "Float", b.x - r, "Float", b.y - r, "Float", r * 2.0, "Float", r * 2.0)
            }
            for _, pt in this._particles {
                DllCall("gdiplus\GdipCreateSolidFill", "UInt", pt.col, "Ptr*", &pPartBrush)
                if (pPartBrush) {
                    DllCall("gdiplus\GdipFillEllipse", "Ptr", g, "Ptr", pPartBrush, "Float", pt.x - 2.0, "Float", pt.y - 2.0, "Float", 4.0, "Float", 4.0)
                    DllCall("gdiplus\GdipDeleteBrush", "Ptr", pPartBrush)
                    pPartBrush := 0
                }
            }
        } finally {
            if (pPartBrush)
                DllCall("gdiplus\GdipDeleteBrush", "Ptr", pPartBrush)
            if (pGlowBrush)
                DllCall("gdiplus\GdipDeleteBrush", "Ptr", pGlowBrush)
            if (pBallBrush)
                DllCall("gdiplus\GdipDeleteBrush", "Ptr", pBallBrush)
        }

        for _, pp in this._popups
            Gdip.DrawText(g, pp.text, "Segoe UI", 9.0, 1, pp.col, pp.x - 42.0, pp.y - 12.0, 84.0, 24.0, 1, 1, 0, false)

        isDark := IsSet(Theme) ? Theme.IsDarkMode() : true
        micMuted := (IsObject(this._state) && this._state.HasOwnProp("isMuted")) ? (this._state.isMuted ? 1 : 0) : -1
        stats := Format("SCORE {}  •  BEST {}  •  WAVE {}  •  LIVES {}", this._score, this._highScore, this._wave, this._lives)
        hints := "MOUSE/ARROWS/A-D MOVE • CLICK/SPACE LAUNCH & LASER • P PAUSE • ESC EXIT"
        HudArcadeBase.DrawScoreboardPill(g, W, "BRICK BREAKER", stats, hints, isDark, micMuted)

        if (this.Phase = "paused")
            HudArcadeBase.DrawOverlayCard(g, W, H, "PAUSED", "Score: " this._score "  |  Wave: " this._wave, "Press P to Resume or Esc to Exit", 0xFF38BDF8, isDark)
        else if (this.Phase = "gameover")
            HudArcadeBase.DrawOverlayCard(g, W, H, "GAME OVER", "Final Score: " this._score "  (Best: " this._highScore ")", "Press R or Left-Click to Retry  •  Esc to Exit", 0xFFEF4444, isDark)

        alpha := (IsObject(this._cfg) && this._cfg.HasOwnProp("OpacityLevel")) ? this._cfg.OpacityLevel : 235
        HudArcadeBase.PresentFrame(this._surf, alpha)
    }
}

; ==============================================================================
; Game 4: Desktop Cyber Pong / Air Hockey (Ctrl+Alt+Shift+H)
; ==============================================================================
class GameCyberPong {
    static TARGET_SCORE := 7
    static IsActive := false
    static Phase := "idle" ; "idle" | "playing" | "paused" | "gameover"
    static _surf := ""
    static _cfg := ""
    static _state := ""
    static _savedPolling := ""
    static _boundHotkeys := []
    static _tickFn := ""
    static _lastUs := 0.0
    static _headless := false

    static _leftPaddle := ""
    static _rightPaddle := ""
    static _puck := ""
    static _particles := []
    static _popups := []

    static _score := 0
    static _highScore := 0
    static _leftScore := 0
    static _rightScore := 0
    static _rally := 0
    static _bestRally := 0
    static _twoPlayer := false
    static _winner := ""
    static _mouseY := 0.0
    static _mouseActive := false

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
            title: "PresenterSyncCyberPong",
            onMouseEvent: this._OnMouse.Bind(this),
            headless: this._headless
        })
        if (!IsObject(this._surf))
            return false

        this.IsActive := true
        HudArcadeBase.RegisterActiveGame(this, "cyber_pong")
        this._highScore := HudArcadeBase.LoadHighScore(cfg, "cyber_pong")
        this._twoPlayer := false
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
        HudArcadeBase.ClearActiveGame("cyber_pong")
    }

    static _BindKeys(cfg) {
        condFn := (*) => GameCyberPong.IsActive
        noop(*) {
        }
        bindings := [
            { key: "$Up", fn: noop },
            { key: "$Down", fn: noop },
            { key: "$w", fn: noop },
            { key: "$s", fn: noop },
            { key: "$2", fn: (*) => GameCyberPong.ToggleTwoPlayerMode() },
            { key: "$p", fn: (*) => GameCyberPong.TogglePause() },
            { key: "$r", fn: (*) => (GameCyberPong.Phase = "gameover" ? GameCyberPong._ResetRun() : 0) },
            { key: "$Escape", fn: (*) => GameCyberPong.Stop() }
        ]
        HudArcadeBase.BindKeysSafe(cfg, bindings, this._boundHotkeys, condFn)
    }

    static _OnMouse(msg, x, y, wp) {
        if (!this.IsActive)
            return
        this._mouseY := Float(y)
        this._mouseActive := true
        if (msg == 0x0201 || msg == 0x0203) {
            if (this.Phase = "gameover")
                this._ResetRun()
        } else if (msg == 0x0204) {
            this.TogglePause()
        }
    }

    static ToggleTwoPlayerMode() {
        this._twoPlayer := !this._twoPlayer
        return this._twoPlayer
    }

    static TogglePause() {
        if (!this.IsActive)
            return
        if (this.Phase = "playing")
            this.Phase := "paused"
        else if (this.Phase = "paused") {
            this.Phase := "playing"
            this._lastUs := HudArcadeBase.NowUs()
        }
    }

    static _ResetRun() {
        W := Float(this._surf.W), H := Float(this._surf.H)
        this._score := 0
        this._leftScore := 0
        this._rightScore := 0
        this._rally := 0
        this._bestRally := 0
        this._winner := ""
        this._mouseActive := false
        this._particles := []
        this._popups := []

        padH := 116.0
        padW := 16.0
        this._leftPaddle := {
            x: 28.0,
            y: (H - padH) * 0.5,
            w: padW,
            h: padH,
            vy: 0.0
        }
        this._rightPaddle := {
            x: W - 28.0 - padW,
            y: (H - padH) * 0.5,
            w: padW,
            h: padH,
            vy: 0.0
        }
        this._ServePuck(1)
        this.Phase := "playing"
    }

    static _ServePuck(dirX := 1) {
        W := Float(this._surf.W), H := Float(this._surf.H)
        d := (dirX >= 0) ? 1.0 : -1.0
        this._rally := 0
        this._puck := {
            x: W * 0.5,
            y: H * 0.5,
            vx: d * 520.0,
            vy: Float(Random(-180, 180)),
            radius: 10.5,
            spin: 0.0
        }
        if (Abs(this._puck.vy) < 60.0)
            this._puck.vy := 110.0
    }

    static _FrameTick() {
        if (!this.IsActive)
            return
        nowUs := HudArcadeBase.NowUs()
        dtSec := Min(0.05, Max(0.001, (nowUs - this._lastUs) / 1000000.0))
        this._lastUs := nowUs
        this.StepSimulation(dtSec, true)
        this._RenderFrame()
    }

    static StepForTest(dtSec, readHardwareInput := false) {
        this.StepSimulation(dtSec, readHardwareInput)
    }

    static StepSimulation(dtSec, readHardwareInput := false) {
        if (!this.IsActive || this.Phase != "playing")
            return
        dt := Min(0.05, Max(0.0001, Float(dtSec)))
        dtMs := dt * 1000.0
        W := Float(this._surf.W), H := Float(this._surf.H)
        lp := this._leftPaddle
        rp := this._rightPaddle
        pk := this._puck
        topBound := 68.0
        botBound := H - 16.0

        prevLy := lp.y
        prevRy := rp.y

        if (readHardwareInput) {
            wDown := GetKeyState("w", "P")
            sDown := GetKeyState("s", "P")
            upDown := GetKeyState("Up", "P")
            dnDown := GetKeyState("Down", "P")

            p1Up := this._twoPlayer ? wDown : (wDown || upDown)
            p1Dn := this._twoPlayer ? sDown : (sDown || dnDown)

            gp := HudArcadeBase.PollXInput()
            if (IsObject(gp)) {
                if ((gp.btn & 0x0001) || gp.ly > 8500)
                    p1Up := true
                if ((gp.btn & 0x0002) || gp.ly < -8500)
                    p1Dn := true
            }
            if (p1Up || p1Dn)
                this._mouseActive := false

            padSpd := 690.0
            if (this._mouseActive) {
                lp.y := PaddlePhysicsCore.Clamp(this._mouseY - lp.h * 0.5, topBound, botBound - lp.h)
            } else {
                if (p1Up)
                    lp.y -= padSpd * dt
                if (p1Dn)
                    lp.y += padSpd * dt
                lp.y := PaddlePhysicsCore.Clamp(lp.y, topBound, botBound - lp.h)
            }
            lp.vy := (lp.y - prevLy) / Max(0.001, dt)

            if (this._twoPlayer) {
                if (upDown)
                    rp.y -= padSpd * dt
                if (dnDown)
                    rp.y += padSpd * dt
                rp.y := PaddlePhysicsCore.Clamp(rp.y, topBound, botBound - rp.h)
                rp.vy := (rp.y - prevRy) / Max(0.001, dt)
            }
        }

        ; Adaptive 1P AI tracking when not in 2P mode
        if (!this._twoPlayer) {
            targetY := (pk.vx > 0.0) ? (pk.y + pk.spin * 0.14) : (H * 0.5)
            centerR := rp.y + rp.h * 0.5
            diff := targetY - centerR
            aiSpd := 560.0 + Min(220.0, this._rally * 18.0)
            step := PaddlePhysicsCore.Clamp(diff, -aiSpd * dt, aiSpd * dt)
            rp.y := PaddlePhysicsCore.Clamp(rp.y + step, topBound, botBound - rp.h)
            rp.vy := (rp.y - prevRy) / Max(0.001, dt)
        }

        ; Curving Magnus velocity-spin physics on energy puck
        if (Abs(pk.spin) > 0.5) {
            pk.vy += pk.spin * dt
            pk.spin *= (1.0 - Min(0.85, 0.95 * dt))
        }

        pk.x += pk.vx * dt
        pk.y += pk.vy * dt

        ; Top & bottom rail reflections
        if (pk.y - pk.radius < topBound) {
            pk.y := topBound + pk.radius
            pk.vy := Abs(pk.vy)
            pk.spin := -pk.spin * 0.65
        } else if (pk.y + pk.radius > botBound) {
            pk.y := botBound - pk.radius
            pk.vy := -Abs(pk.vy)
            pk.spin := -pk.spin * 0.65
        }

        ; Left & Right paddle deflections with spin transfer
        if (PaddlePhysicsCore.BounceVerticalPaddle(pk, lp.x, lp.y, lp.w, lp.h, lp.vy, true)) {
            this._OnRallyHit(pk.x, pk.y, true)
        } else if (PaddlePhysicsCore.BounceVerticalPaddle(pk, rp.x, rp.y, rp.w, rp.h, rp.vy, false)) {
            this._OnRallyHit(pk.x, pk.y, false)
        }

        ; Goal scoring checks
        if (pk.x + pk.radius < 0.0) {
            this._rightScore += 1
            this._SpawnSparks(32.0, pk.y, 0xFFFB7185, 14)
            if (this._rightScore >= this.TARGET_SCORE) {
                this._winner := this._twoPlayer ? "PLAYER 2" : "CYBER AI"
                this.Phase := "gameover"
                return
            }
            this._ServePuck(-1)
        } else if (pk.x - pk.radius > W) {
            this._leftScore += 1
            pts := 100 + this._rally * 15
            this._AddScore(pts, W - 48.0, pk.y, 0xFF34D399)
            this._SpawnSparks(W - 32.0, pk.y, 0xFF34D399, 14)
            if (this._leftScore >= this.TARGET_SCORE) {
                this._winner := "PLAYER 1"
                this._AddScore(350, W * 0.5, H * 0.5, 0xFF38BDF8)
                this.Phase := "gameover"
                return
            }
            this._ServePuck(1)
        }

        ; Particles & popups
        idx := this._particles.Length
        while (idx >= 1) {
            pt := this._particles[idx]
            pt.ttlMs -= dtMs
            if (pt.ttlMs <= 0.0)
                this._particles.RemoveAt(idx)
            else {
                pt.x += pt.vx * dt
                pt.y += pt.vy * dt
            }
            idx -= 1
        }
        idx := this._popups.Length
        while (idx >= 1) {
            pp := this._popups[idx]
            pp.ttlMs -= dtMs
            if (pp.ttlMs <= 0.0)
                this._popups.RemoveAt(idx)
            else
                pp.y -= 24.0 * dt
            idx -= 1
        }
    }

    static _OnRallyHit(x, y, isLeft) {
        this._rally += 1
        if (this._rally > this._bestRally)
            this._bestRally := this._rally
        if (isLeft)
            this._AddScore(10 + this._rally * 2, x + 18.0, y, 0xFF38BDF8)
        this._SpawnSparks(x, y, isLeft ? 0xFF38BDF8 : 0xFFF43F5E, 8)
    }

    static _AddScore(pts, x, y, col) {
        this._score += pts
        if (this._score > this._highScore) {
            this._highScore := this._score
            HudArcadeBase.SaveHighScore(this._cfg, "cyber_pong", this._highScore)
        }
        this._popups.Push({ x: x, y: y, text: "+" pts, ttlMs: 650.0, col: col })
    }

    static _SpawnSparks(x, y, col, count) {
        Loop count {
            ang := Float(Random(0, 628)) / 100.0
            spd := Float(Random(50, 175))
            this._particles.Push({ x: x, y: y, vx: Cos(ang) * spd, vy: Sin(ang) * spd, ttlMs: 340.0, col: col })
        }
    }

    ; --- Headless Test Helpers ---
    static SetPuckForTest(x, y, vx, vy, spin := 0.0) {
        if (!IsObject(this._puck))
            this._puck := { x: 0.0, y: 0.0, vx: 0.0, vy: 0.0, radius: 10.5, spin: 0.0 }
        this._puck.x := Float(x)
        this._puck.y := Float(y)
        this._puck.vx := Float(vx)
        this._puck.vy := Float(vy)
        this._puck.spin := Float(spin)
        return this._puck
    }

    static SetPaddlesForTest(leftY, rightY := -1.0, leftVy := 0.0, rightVy := 0.0) {
        if (IsObject(this._leftPaddle)) {
            this._leftPaddle.y := Float(leftY)
            this._leftPaddle.vy := Float(leftVy)
        }
        if (IsObject(this._rightPaddle)) {
            if (rightY >= 0.0)
                this._rightPaddle.y := Float(rightY)
            this._rightPaddle.vy := Float(rightVy)
        }
    }

    static GetSnapshot() {
        return this.GetStateSnapshot()
    }

    static GetStateSnapshot() {
        return {
            active: this.IsActive,
            phase: this.Phase,
            score: this._score,
            highScore: this._highScore,
            leftScore: this._leftScore,
            rightScore: this._rightScore,
            rally: this._rally,
            bestRally: this._bestRally,
            twoPlayer: this._twoPlayer,
            winner: this._winner,
            puck: this._puck,
            leftPaddle: this._leftPaddle,
            rightPaddle: this._rightPaddle
        }
    }

    static _RenderFrame() {
        if (!IsObject(this._surf) || !this._surf.pGraphics)
            return
        HudArcadeBase.BeginFrame(this._surf)
        g := this._surf.pGraphics
        W := this._surf.W, H := this._surf.H

        ; Center cyber court line & circle
        HudArcadeBase.StrokeRoundedRect(g, W * 0.5 - 1.0, 72.0, 2.0, H - 92.0, 1.0, 0x4438BDF8, 1.5)
        pCourtPen := 0
        DllCall("gdiplus\GdipCreatePen1", "UInt", 0x4438BDF8, "Float", 1.6, "Int", 2, "Ptr*", &pCourtPen)
        try {
            if (pCourtPen)
                DllCall("gdiplus\GdipDrawEllipse", "Ptr", g, "Ptr", pCourtPen, "Float", W * 0.5 - 58.0, "Float", H * 0.5 - 58.0, "Float", 116.0, "Float", 116.0)
        } finally {
            if (pCourtPen)
                DllCall("gdiplus\GdipDeletePen", "Ptr", pCourtPen)
        }

        ; Draw Left & Right neon paddles
        lp := this._leftPaddle, rp := this._rightPaddle
        HudArcadeBase.FillRoundedRect(g, lp.x, lp.y, lp.w, lp.h, 8.0, 0xE60EA5E9)
        HudArcadeBase.StrokeRoundedRect(g, lp.x, lp.y, lp.w, lp.h, 8.0, 0xFFBAE6FD, 1.8)

        HudArcadeBase.FillRoundedRect(g, rp.x, rp.y, rp.w, rp.h, 8.0, 0xE6F43F5E)
        HudArcadeBase.StrokeRoundedRect(g, rp.x, rp.y, rp.w, rp.h, 8.0, 0xFFFECDD3, 1.8)

        ; Draw energy puck & particles
        pk := this._puck
        pPuckBrush := 0, pGlowBrush := 0, pPartBrush := 0
        glowCol := (Abs(pk.spin) > 80.0) ? 0x77F59E0B : 0x6638BDF8
        DllCall("gdiplus\GdipCreateSolidFill", "UInt", 0xFFF8FAFC, "Ptr*", &pPuckBrush)
        DllCall("gdiplus\GdipCreateSolidFill", "UInt", glowCol, "Ptr*", &pGlowBrush)
        try {
            r := pk.radius
            if (pGlowBrush)
                DllCall("gdiplus\GdipFillEllipse", "Ptr", g, "Ptr", pGlowBrush, "Float", pk.x - r - 4.0, "Float", pk.y - r - 4.0, "Float", (r + 4.0) * 2.0, "Float", (r + 4.0) * 2.0)
            if (pPuckBrush)
                DllCall("gdiplus\GdipFillEllipse", "Ptr", g, "Ptr", pPuckBrush, "Float", pk.x - r, "Float", pk.y - r, "Float", r * 2.0, "Float", r * 2.0)

            for _, pt in this._particles {
                DllCall("gdiplus\GdipCreateSolidFill", "UInt", pt.col, "Ptr*", &pPartBrush)
                if (pPartBrush) {
                    DllCall("gdiplus\GdipFillEllipse", "Ptr", g, "Ptr", pPartBrush, "Float", pt.x - 2.0, "Float", pt.y - 2.0, "Float", 4.0, "Float", 4.0)
                    DllCall("gdiplus\GdipDeleteBrush", "Ptr", pPartBrush)
                    pPartBrush := 0
                }
            }
        } finally {
            if (pPartBrush)
                DllCall("gdiplus\GdipDeleteBrush", "Ptr", pPartBrush)
            if (pGlowBrush)
                DllCall("gdiplus\GdipDeleteBrush", "Ptr", pGlowBrush)
            if (pPuckBrush)
                DllCall("gdiplus\GdipDeleteBrush", "Ptr", pPuckBrush)
        }

        for _, pp in this._popups
            Gdip.DrawText(g, pp.text, "Segoe UI", 9.0, 1, pp.col, pp.x - 40.0, pp.y - 12.0, 80.0, 24.0, 1, 1, 0, false)

        isDark := IsSet(Theme) ? Theme.IsDarkMode() : true
        micMuted := (IsObject(this._state) && this._state.HasOwnProp("isMuted")) ? (this._state.isMuted ? 1 : 0) : -1
        modeLbl := this._twoPlayer ? "2P DUEL" : "1P vs AI"
        stats := Format("P1 {} : {} {}  •  RALLY {}  •  SCORE {} (BEST {})  •  {}", this._leftScore, this._rightScore, this._twoPlayer ? "P2" : "AI", this._rally, this._score, this._highScore, modeLbl)
        hints := "MOUSE/W-S/ARROWS MOVE • 2 TOGGLE 1P/2P • FIRST TO 7 • P PAUSE • ESC EXIT"
        HudArcadeBase.DrawScoreboardPill(g, W, "CYBER PONG", stats, hints, isDark, micMuted)

        if (this.Phase = "paused")
            HudArcadeBase.DrawOverlayCard(g, W, H, "PAUSED", "Set: " this._leftScore " - " this._rightScore "  |  Rally: " this._rally, "Press P to Resume  •  2 Toggle 1P/2P  •  Esc to Exit", 0xFF38BDF8, isDark)
        else if (this.Phase = "gameover")
            HudArcadeBase.DrawOverlayCard(g, W, H, this._winner " WINS SET!", "Final Set: " this._leftScore " - " this._rightScore "  |  Score: " this._score " (Best: " this._highScore ")", "Press R or Left-Click for Next Set  •  Esc to Exit", 0xFF10B981, isDark)

        alpha := (IsObject(this._cfg) && this._cfg.HasOwnProp("OpacityLevel")) ? this._cfg.OpacityLevel : 235
        HudArcadeBase.PresentFrame(this._surf, alpha)
    }
}
