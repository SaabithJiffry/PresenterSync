; ==============================================================================
; Module: GameAsteroids.ahk
; Description: Game 2 — Asteroid / Alien Blaster (Ctrl+Alt+Shift+A)
;              Built on HudArcadeBase (interactiveMouse := true, IDC_CROSS).
;              Splitting Large->Medium->Small wireframe asteroids, roaming
;              alien saucers, HUD-pill power-ups (RAPID, SPREAD, SHIELD), and
;              optional live Mic Pill Bumper elastic deflection.
; ==============================================================================

#Include "%A_LineFile%\..\..\HudArcadeBase.ahk"

class GameAsteroids {
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

    static _ship := ""
    static _asteroids := []
    static _aliens := []
    static _bullets := []
    static _powerups := []
    static _particles := []
    static _popups := []
    static _saucer := ""

    static _blasterMode := "asteroids" ; "asteroids" | "alien"
    static _weaponTier := 1            ; 1..5 in Alien Blaster mode
    static _beamActive := false
    static _beamHoldMs := 0.0
    static _beamDmgCdMs := 0.0
    static _alienTimeSec := 0.0
    static _waveDelayMs := 0.0

    static _score := 0
    static _highScore := 0
    static _wave := 1
    static _lives := 3
    static _autoFire := true
    static _micBumper := true
    static _saucerTimerMs := 9000.0
    static _mouseX := 0.0
    static _mouseY := 0.0
    static _mouseActive := false
    static _mouseDown := false
    static _testMicRect := ""

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
            cursorId: 32515,
            title: "PresenterSyncAsteroids",
            onMouseEvent: this._OnMouse.Bind(this),
            headless: this._headless
        })
        if (!IsObject(this._surf))
            return false

        this.IsActive := true
        HudArcadeBase.RegisterActiveGame(this, "asteroids")
        this._highScore := HudArcadeBase.LoadHighScore(cfg, "asteroids")
        this._testMicRect := ""
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
        HudArcadeBase.ClearActiveGame("asteroids")
    }

    static _BindKeys(cfg) {
        condFn := (*) => GameAsteroids.IsActive
        noop(*) {
        }
        bindings := [
            { key: "$Up", fn: noop },
            { key: "$Down", fn: noop },
            { key: "$Left", fn: noop },
            { key: "$Right", fn: noop },
            { key: "$w", fn: noop },
            { key: "$a", fn: noop },
            { key: "$s", fn: noop },
            { key: "$d", fn: noop },
            { key: "$Space", fn: (*) => GameAsteroids.FireBullet(true) },
            { key: "$f", fn: (*) => (GameAsteroids._autoFire := !GameAsteroids._autoFire) },
            { key: "$b", fn: (*) => (GameAsteroids._micBumper := !GameAsteroids._micBumper) },
            { key: "$m", fn: (*) => GameAsteroids.ToggleBlasterMode() },
            { key: "$+m", fn: (*) => GameAsteroids.ToggleBlasterMode() },
            { key: "$p", fn: (*) => GameAsteroids.TogglePause() },
            { key: "$r", fn: (*) => (GameAsteroids.Phase = "gameover" ? GameAsteroids._ResetRun() : 0) },
            { key: "$Escape", fn: (*) => GameAsteroids.Stop() }
        ]
        HudArcadeBase.BindKeysSafe(cfg, bindings, this._boundHotkeys, condFn)
    }

    static _OnMouse(msg, x, y, wp) {
        if (!this.IsActive)
            return
        this._mouseX := Float(x)
        this._mouseY := Float(y)
        this._mouseActive := true
        if (msg == 0x0201 || msg == 0x0203) {
            this._mouseDown := true
            if (this.Phase = "gameover")
                this._ResetRun()
            else
                this.FireBullet(true)
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

    static ToggleBlasterMode() {
        if (!this.IsActive)
            return this._blasterMode
        this._blasterMode := (this._blasterMode = "asteroids") ? "alien" : "asteroids"
        this._ResetRun()
        return this._blasterMode
    }

    static SetModeForTest(mode) {
        this._blasterMode := (StrLower(mode) = "alien") ? "alien" : "asteroids"
        if (this.IsActive)
            this._ResetRun()
        return this._blasterMode
    }

    static UpgradeWeaponForTest() {
        this._weaponTier := Min(5, this._weaponTier + 1)
        return this._weaponTier
    }

    static SpawnAlienForTest(x, y, kind := "scout", hp := 1, vy := 45.0) {
        r := (kind = "cruiser") ? 22.0 : ((kind = "raider") ? 16.0 : 14.0)
        alien := {
            x: Float(x),
            y: Float(y),
            baseX: Float(x),
            vx: 0.0,
            vy: Float(vy),
            kind: kind,
            hp: Max(1, Integer(hp)),
            maxHp: Max(1, Integer(hp)),
            radius: r,
            phase: 0.0,
            amp: (kind = "raider") ? 48.0 : 0.0,
            freq: (kind = "raider") ? 2.4 : 0.0,
            fireCdMs: 1400.0
        }
        this._aliens.Push(alien)
        return alien
    }

    static _ResetRun() {
        W := this._surf.W, H := this._surf.H
        this._score := 0
        this._wave := 1
        this._lives := 3
        this._weaponTier := 1
        this._beamActive := false
        this._beamHoldMs := 0.0
        this._beamDmgCdMs := 0.0
        this._alienTimeSec := 0.0
        this._waveDelayMs := 0.0
        this._mouseActive := false
        this._mouseDown := false
        this._asteroids := []
        this._aliens := []
        this._bullets := []
        this._powerups := []
        this._particles := []
        this._popups := []
        this._saucer := { active: false, x: 0.0, y: 0.0, vx: 0.0, vy: 0.0, radius: 16.0, fireCdMs: 1400.0 }
        this._saucerTimerMs := 9000.0
        this._RespawnShip(true)
        if (this._blasterMode = "alien")
            this._SpawnAlienWave(1)
        else
            this._SpawnWave(1)
        this.Phase := "playing"
    }

    static _RespawnShip(initial := false) {
        W := this._surf.W, H := this._surf.H
        isAlien := (this._blasterMode = "alien")
        this._ship := {
            x: Float(W) / 2.0,
            y: isAlien ? (Float(H) * 0.80) : (Float(H) / 2.0),
            vx: 0.0,
            vy: 0.0,
            angle: -1.57079632679,
            radius: 13.0,
            thrusting: false,
            shieldMs: initial ? 0.0 : 2400.0,
            rapidMs: 0.0,
            spreadMs: 0.0,
            invulnMs: 2200.0,
            fireCdMs: 0.0
        }
    }

    static _SpawnAlienWave(waveNum) {
        this._aliens := []
        W := Float(this._surf.W)
        cx := W / 2.0
        ; 1. V-wedge scouts
        scoutCount := Min(7, 3 + waveNum)
        half := (scoutCount - 1) / 2.0
        Loop scoutCount {
            idx := A_Index - 1
            off := idx - half
            ax := Max(48.0, Min(W - 48.0, cx + off * 62.0))
            ay := 84.0 + Abs(off) * 26.0
            this._aliens.Push({
                x: ax, y: ay, baseX: ax, vx: 0.0, vy: 42.0 + waveNum * 6.0,
                kind: "scout", hp: 1, maxHp: 1, radius: 14.0,
                phase: idx * 0.6, amp: 14.0, freq: 1.4,
                fireCdMs: 1100.0 + Random(0, 900)
            })
        }
        ; 2. Sine-wave raiders
        raiderCount := Min(5, 1 + waveNum)
        Loop raiderCount {
            idx := A_Index
            ax := Max(72.0, Min(W - 72.0, (W / (raiderCount + 1)) * idx))
            ay := 56.0 - (idx * 18.0)
            rHp := (waveNum >= 3) ? 2 : 1
            this._aliens.Push({
                x: ax, y: ay, baseX: ax, vx: 0.0, vy: 50.0 + waveNum * 5.0,
                kind: "raider", hp: rHp, maxHp: rHp, radius: 16.0,
                phase: idx * 1.3, amp: 58.0, freq: 2.3,
                fireCdMs: 950.0 + Random(0, 800)
            })
        }
        ; 3. Armored multi-HP cruisers
        cruiserCount := Min(3, 1 + Floor((waveNum - 1) / 2))
        Loop cruiserCount {
            idx := A_Index
            ax := Max(80.0, Min(W - 80.0, (W / (cruiserCount + 1)) * idx))
            ay := 42.0
            cHp := 3 + Floor((waveNum - 1) / 2)
            this._aliens.Push({
                x: ax, y: ay, baseX: ax, vx: 0.0, vy: 28.0 + waveNum * 3.0,
                kind: "cruiser", hp: cHp, maxHp: cHp, radius: 22.0,
                phase: idx * 0.9, amp: 26.0, freq: 1.0,
                fireCdMs: 1300.0 + Random(0, 700)
            })
        }
    }

    static _SpawnWave(waveNum) {
        this._asteroids := []
        count := Min(12, 4 + waveNum)
        W := Float(this._surf.W), H := Float(this._surf.H)
        sx := Float(this._ship.x), sy := Float(this._ship.y)
        Loop count {
            ax := 0.0, ay := 0.0
            Loop 10 {
                ax := Float(Random(30, Integer(W - 30)))
                ay := Float(Random(70, Integer(H - 30)))
                if (Sqrt((ax - sx) ** 2 + (ay - sy) ** 2) >= 160.0)
                    break
            }
            ang := Float(Random(0, 628)) / 100.0
            spd := (65.0 + waveNum * 12.0) * (Float(Random(80, 125)) / 100.0)
            this.SpawnAsteroid(ax, ay, Cos(ang) * spd, Sin(ang) * spd, 3)
        }
    }

    static SpawnAsteroid(x, y, vx, vy, sizeTier := 3) {
        r := (sizeTier == 3) ? 36.0 : ((sizeTier == 2) ? 22.0 : 12.0)
        verts := []
        Loop 9 {
            th := (A_Index - 1) * (6.28318530718 / 9.0)
            jit := Float(Random(76, 114)) / 100.0
            verts.Push({ c: Cos(th) * r * jit, s: Sin(th) * r * jit })
        }
        ast := {
            x: Float(x),
            y: Float(y),
            vx: Float(vx),
            vy: Float(vy),
            rot: 0.0,
            rotSpd: (Float(Random(-180, 180)) / 100.0),
            size: sizeTier,
            radius: r,
            verts: verts
        }
        this._asteroids.Push(ast)
        return ast
    }

    static SpawnSaucer(leftToRight := true) {
        W := Float(this._surf.W), H := Float(this._surf.H)
        sy := Float(Random(90, Max(120, Integer(H - 90))))
        this._saucer := {
            active: true,
            x: leftToRight ? -20.0 : (W + 20.0),
            y: sy,
            vx: leftToRight ? (130.0 + this._wave * 10.0) : -(130.0 + this._wave * 10.0),
            vy: 0.0,
            radius: 16.0,
            fireCdMs: 1100.0
        }
        return this._saucer
    }

    static SpawnPowerUp(x, y, kind := "") {
        if (kind = "") {
            if (this._blasterMode = "alien")
                k := (Random(1, 100) <= 75) ? "WEAPON_UP" : "SHIELD"
            else {
                kinds := ["RAPID", "SPREAD", "SHIELD"]
                k := kinds[Random(1, 3)]
            }
        } else {
            k := kind
        }
        vx := (this._blasterMode = "alien") ? 0.0 : Float(Random(-30, 30))
        vy := (this._blasterMode = "alien") ? 72.0 : 28.0
        pu := { x: Float(x), y: Float(y), vx: vx, vy: vy, kind: k, radius: 16.0, ttlMs: 9000.0 }
        this._powerups.Push(pu)
        return pu
    }

    static SetTestMicPillRect(rect) {
        this._testMicRect := rect
    }

    static FireBullet(manualBurst := false) {
        if (!this.IsActive || this.Phase != "playing")
            return false
        s := this._ship
        if (this._blasterMode = "alien") {
            if (this._weaponTier >= 5) {
                this._beamActive := true
                this._beamHoldMs := 360.0
                return true
            }
            if (!manualBurst && s.fireCdMs > 0.0)
                return false
            if (manualBurst && s.fireCdMs > 70.0)
                return false
            tier := this._weaponTier
            spd := 640.0
            if (tier == 1) {
                s.fireCdMs := 210.0
                this._bullets.Push({ x: s.x, y: s.y - s.radius - 4.0, vx: 0.0, vy: -spd, ttlMs: 1200.0, isEnemy: false })
            } else if (tier == 2) {
                s.fireCdMs := 190.0
                this._bullets.Push({ x: s.x - 9.0, y: s.y - s.radius - 2.0, vx: 0.0, vy: -spd, ttlMs: 1200.0, isEnemy: false })
                this._bullets.Push({ x: s.x + 9.0, y: s.y - s.radius - 2.0, vx: 0.0, vy: -spd, ttlMs: 1200.0, isEnemy: false })
            } else if (tier == 3) {
                s.fireCdMs := 175.0
                for _, off in [-0.18, 0.0, 0.18] {
                    a := -1.57079632679 + off
                    this._bullets.Push({ x: s.x + Cos(a) * (s.radius + 4.0), y: s.y + Sin(a) * (s.radius + 4.0), vx: Cos(a) * spd, vy: Sin(a) * spd, ttlMs: 1200.0, isEnemy: false })
                }
            } else {
                s.fireCdMs := 125.0
                for _, off in [-0.28, -0.14, 0.0, 0.14, 0.28] {
                    a := -1.57079632679 + off
                    this._bullets.Push({ x: s.x + Cos(a) * (s.radius + 4.0), y: s.y + Sin(a) * (s.radius + 4.0), vx: Cos(a) * (spd * 1.06), vy: Sin(a) * (spd * 1.06), ttlMs: 1200.0, isEnemy: false })
                }
            }
            return true
        }

        if (!manualBurst && s.fireCdMs > 0.0)
            return false
        if (manualBurst && s.fireCdMs > 90.0)
            return false

        s.fireCdMs := (s.rapidMs > 0.0) ? 90.0 : 210.0
        offsets := (s.spreadMs > 0.0) ? [-0.22, 0.0, 0.22] : [0.0]
        spd := 560.0
        for _, off in offsets {
            a := s.angle + off
            this._bullets.Push({
                x: s.x + Cos(a) * (s.radius + 4.0),
                y: s.y + Sin(a) * (s.radius + 4.0),
                vx: Cos(a) * spd + s.vx * 0.25,
                vy: Sin(a) * spd + s.vy * 0.25,
                ttlMs: 1150.0,
                isEnemy: false
            })
        }
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

    static StepSimulation(dtSec, readHardwareInput := false) {
        if (!this.IsActive || this.Phase != "playing")
            return
        dt := Min(0.05, Max(0.0001, Float(dtSec)))
        dtMs := dt * 1000.0
        W := Float(this._surf.W), H := Float(this._surf.H)
        s := this._ship

        if (s.invulnMs > 0.0)
            s.invulnMs := Max(0.0, s.invulnMs - dtMs)
        if (s.shieldMs > 0.0)
            s.shieldMs := Max(0.0, s.shieldMs - dtMs)
        if (s.rapidMs > 0.0)
            s.rapidMs := Max(0.0, s.rapidMs - dtMs)
        if (s.spreadMs > 0.0)
            s.spreadMs := Max(0.0, s.spreadMs - dtMs)
        if (s.fireCdMs > 0.0)
            s.fireCdMs := Max(0.0, s.fireCdMs - dtMs)

        if (this._blasterMode = "alien") {
            this._StepAlienSimulation(dt, dtMs, W, H, readHardwareInput)
            return
        }

        s.thrusting := false
        if (readHardwareInput) {
            rotL := GetKeyState("Left", "P") || GetKeyState("a", "P")
            rotR := GetKeyState("Right", "P") || GetKeyState("d", "P")
            thUp := GetKeyState("Up", "P") || GetKeyState("w", "P")
            fireNow := GetKeyState("Space", "P") || this._mouseDown || this._autoFire

            gp := HudArcadeBase.PollXInput()
            if (IsObject(gp)) {
                if ((gp.btn & 0x0004) || gp.lx < -9000)
                    rotL := true
                if ((gp.btn & 0x0008) || gp.lx > 9000)
                    rotR := true
                if ((gp.btn & 0x0001) || gp.ly > 9000)
                    thUp := true
                if (gp.btn & 0x1000)
                    fireNow := true
            }
            if (rotL || rotR || thUp)
                this._mouseActive := false

            if (this._mouseActive) {
                dx := this._mouseX - s.x
                dy := this._mouseY - s.y
                dist := Sqrt(dx * dx + dy * dy)
                if (dist > 4.0)
                    s.angle := DllCall("msvcrt\atan2", "Double", dy, "Double", dx, "Double")
                if (dist > 70.0 && this._mouseDown)
                    s.thrusting := true
            } else {
                if (rotL)
                    s.angle -= 3.8 * dt
                if (rotR)
                    s.angle += 3.8 * dt
                if (thUp)
                    s.thrusting := true
            }

            if (s.thrusting) {
                s.vx += Cos(s.angle) * 320.0 * dt
                s.vy += Sin(s.angle) * 320.0 * dt
                if (Random(1, 2) == 1)
                    this._particles.Push({ x: s.x - Cos(s.angle) * 14.0, y: s.y - Sin(s.angle) * 14.0, vx: -Cos(s.angle) * 90.0 + Random(-30, 30), vy: -Sin(s.angle) * 90.0 + Random(-30, 30), ttlMs: 260.0, col: 0xFFF59E0B })
            }
            if (fireNow)
                this.FireBullet(false)
        }

        ; Ship velocity damping + toroidal wrap
        s.vx *= (1.0 - Min(0.9, 0.55 * dt))
        s.vy *= (1.0 - Min(0.9, 0.55 * dt))
        s.x := Mod(s.x + s.vx * dt + W, W)
        s.y := Mod(s.y + s.vy * dt + H, H)

        ; Bullets move & wrap
        idx := this._bullets.Length
        while (idx >= 1) {
            b := this._bullets[idx]
            b.ttlMs -= dtMs
            if (b.ttlMs <= 0.0) {
                this._bullets.RemoveAt(idx)
                idx -= 1
                continue
            }
            b.x := Mod(b.x + b.vx * dt + W, W)
            b.y := Mod(b.y + b.vy * dt + H, H)
            idx -= 1
        }

        ; Live Mic Pill rect (optional Mic Pill Bumper mode)
        micRect := this._micBumper ? (IsObject(this._testMicRect) ? this._testMicRect : HudArcadeBase.GetLiveMicPillRect(this._cfg, this._state)) : ""

        ; Asteroids move, bumper bounce & bullet/ship collisions
        aIdx := this._asteroids.Length
        while (aIdx >= 1) {
            a := this._asteroids[aIdx]
            a.x := Mod(a.x + a.vx * dt + W, W)
            a.y := Mod(a.y + a.vy * dt + H, H)
            a.rot += a.rotSpd * dt

            if (IsObject(micRect))
                this._ResolveMicPillBounce(a, micRect)

            hitByBullet := false
            bIdx := this._bullets.Length
            while (bIdx >= 1) {
                b := this._bullets[bIdx]
                if (!b.isEnemy && ((b.x - a.x) ** 2 + (b.y - a.y) ** 2) <= (a.radius + 3.0) ** 2) {
                    this._bullets.RemoveAt(bIdx)
                    hitByBullet := true
                    break
                }
                bIdx -= 1
            }

            if (hitByBullet) {
                this._DestroyAsteroid(aIdx)
                aIdx -= 1
                continue
            }

            if (s.invulnMs <= 0.0 && s.shieldMs <= 0.0 && ((s.x - a.x) ** 2 + (s.y - a.y) ** 2) <= (a.radius + s.radius - 3.0) ** 2) {
                this._DamageShip()
                if (this.Phase = "gameover")
                    return
            }
            aIdx -= 1
        }

        ; Alien Saucer lifecycle & plasma bolts
        if (!this._saucer.active) {
            this._saucerTimerMs -= dtMs
            if (this._saucerTimerMs <= 0.0) {
                this.SpawnSaucer(Random(0, 1) == 1)
                this._saucerTimerMs := Max(5500.0, 12000.0 - this._wave * 700.0)
            }
        } else {
            sc := this._saucer
            sc.x += sc.vx * dt
            sc.y += Sin(HudArcadeBase.NowUs() / 320000.0) * 45.0 * dt
            sc.fireCdMs -= dtMs
            if (sc.fireCdMs <= 0.0) {
                sc.fireCdMs := Max(900.0, 1750.0 - this._wave * 80.0)
                ang := DllCall("msvcrt\atan2", "Double", s.y - sc.y, "Double", s.x - sc.x, "Double")
                this._bullets.Push({ x: sc.x, y: sc.y, vx: Cos(ang) * 320.0, vy: Sin(ang) * 320.0, ttlMs: 1800.0, isEnemy: true })
            }
            if (sc.x < -50.0 || sc.x > W + 50.0)
                sc.active := false
            else {
                bIdx := this._bullets.Length
                while (bIdx >= 1) {
                    b := this._bullets[bIdx]
                    if (!b.isEnemy && ((b.x - sc.x) ** 2 + (b.y - sc.y) ** 2) <= (sc.radius + 4.0) ** 2) {
                        this._bullets.RemoveAt(bIdx)
                        sc.active := false
                        this._AddScore(250, sc.x, sc.y, 0xFF38BDF8)
                        this._SpawnExplosion(sc.x, sc.y, 0xFF38BDF8, 12)
                        this.SpawnPowerUp(sc.x, sc.y)
                        break
                    }
                    bIdx -= 1
                }
            }
        }

        ; Enemy bullets hitting ship
        bIdx := this._bullets.Length
        while (bIdx >= 1) {
            b := this._bullets[bIdx]
            if (b.isEnemy && s.invulnMs <= 0.0 && s.shieldMs <= 0.0 && ((b.x - s.x) ** 2 + (b.y - s.y) ** 2) <= (s.radius + 4.0) ** 2) {
                this._bullets.RemoveAt(bIdx)
                this._DamageShip()
                if (this.Phase = "gameover")
                    return
            }
            bIdx -= 1
        }

        ; Powerups move & ship pickup
        pIdx := this._powerups.Length
        while (pIdx >= 1) {
            pu := this._powerups[pIdx]
            pu.ttlMs -= dtMs
            if (pu.ttlMs <= 0.0) {
                this._powerups.RemoveAt(pIdx)
                pIdx -= 1
                continue
            }
            pu.x := Mod(pu.x + pu.vx * dt + W, W)
            pu.y := Mod(pu.y + pu.vy * dt + H, H)
            if (((pu.x - s.x) ** 2 + (pu.y - s.y) ** 2) <= (s.radius + pu.radius) ** 2) {
                if (pu.kind = "RAPID")
                    s.rapidMs := 10000.0
                else if (pu.kind = "SPREAD")
                    s.spreadMs := 10000.0
                else
                    s.shieldMs := 10000.0
                this._popups.Push({ x: pu.x, y: pu.y, text: pu.kind, ttlMs: 900.0, col: 0xFF34D399 })
                this._powerups.RemoveAt(pIdx)
            }
            pIdx -= 1
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

        ; Advance wave when all asteroids cleared
        if (this._asteroids.Length == 0) {
            this._wave += 1
            this._SpawnWave(this._wave)
        }
    }

    static _StepAlienSimulation(dt, dtMs, W, H, readHardwareInput) {
        s := this._ship
        s.angle := -1.57079632679 ; Fixed forward-facing ship (NEVER rotates)
        this._alienTimeSec += dt
        if (this._beamHoldMs > 0.0)
            this._beamHoldMs := Max(0.0, this._beamHoldMs - dtMs)
        if (this._beamDmgCdMs > 0.0)
            this._beamDmgCdMs := Max(0.0, this._beamDmgCdMs - dtMs)

        fireNow := false
        if (readHardwareInput) {
            mvL := GetKeyState("Left", "P") || GetKeyState("a", "P")
            mvR := GetKeyState("Right", "P") || GetKeyState("d", "P")
            mvU := GetKeyState("Up", "P") || GetKeyState("w", "P")
            mvD := GetKeyState("Down", "P") || GetKeyState("s", "P")
            fireNow := GetKeyState("Space", "P") || this._mouseDown || this._autoFire

            gp := HudArcadeBase.PollXInput()
            if (IsObject(gp)) {
                if ((gp.btn & 0x0004) || gp.lx < -9000)
                    mvL := true
                if ((gp.btn & 0x0008) || gp.lx > 9000)
                    mvR := true
                if ((gp.btn & 0x0001) || gp.ly > 9000)
                    mvU := true
                if ((gp.btn & 0x0002) || gp.ly < -9000)
                    mvD := true
                if (gp.btn & 0x1000)
                    fireNow := true
            }
            if (mvL || mvR || mvU || mvD)
                this._mouseActive := false

            moveSpd := 380.0
            if (this._mouseActive) {
                dx := this._mouseX - s.x
                dy := this._mouseY - s.y
                s.vx := Max(-520.0, Min(520.0, dx * 9.0))
                s.vy := Max(-520.0, Min(520.0, dy * 9.0))
            } else {
                ix := (mvR ? 1.0 : 0.0) - (mvL ? 1.0 : 0.0)
                iy := (mvD ? 1.0 : 0.0) - (mvU ? 1.0 : 0.0)
                if (ix != 0.0 && iy != 0.0) {
                    ix *= 0.70710678
                    iy *= 0.70710678
                }
                s.vx := ix * moveSpd
                s.vy := iy * moveSpd
            }
            s.thrusting := (Abs(s.vx) > 20.0 || Abs(s.vy) > 20.0)
        } else {
            s.thrusting := (Abs(s.vx) > 20.0 || Abs(s.vy) > 20.0)
        }

        ; Full 2D ship movement clamped cleanly inside the arena
        s.x := Max(24.0, Min(W - 24.0, s.x + s.vx * dt))
        s.y := Max(76.0, Min(H - 24.0, s.y + s.vy * dt))
        s.angle := -1.57079632679

        if (this._weaponTier >= 5) {
            this._beamActive := (fireNow || this._beamHoldMs > 0.0)
            if (this._beamActive && this._beamDmgCdMs <= 0.0) {
                this._beamDmgCdMs := 80.0
                aIdx := this._aliens.Length
                while (aIdx >= 1) {
                    al := this._aliens[aIdx]
                    if (al.y < s.y && Abs(al.x - s.x) <= (al.radius + 15.0)) {
                        this._DamageAlien(aIdx, 1)
                    }
                    aIdx -= 1
                }
            }
        } else {
            this._beamActive := false
            if (fireNow)
                this.FireBullet(false)
        }

        ; Bullets move (non-wrapping in Alien Blaster mode)
        idx := this._bullets.Length
        while (idx >= 1) {
            b := this._bullets[idx]
            b.ttlMs -= dtMs
            b.x += b.vx * dt
            b.y += b.vy * dt
            if (b.ttlMs <= 0.0 || b.x < -30.0 || b.x > W + 30.0 || b.y < 30.0 || b.y > H + 30.0) {
                this._bullets.RemoveAt(idx)
            }
            idx -= 1
        }

        ; Update oncoming Alien ships, enemy plasma bolts, and bullet/ship collisions
        aIdx := this._aliens.Length
        while (aIdx >= 1) {
            al := this._aliens[aIdx]
            al.y += al.vy * dt
            if (al.amp > 0.0 && al.freq > 0.0) {
                al.x := Max(28.0, Min(W - 28.0, al.baseX + Sin(this._alienTimeSec * al.freq + al.phase) * al.amp))
            }
            if (al.y > H + 30.0) {
                al.y := 58.0
            }
            al.fireCdMs -= dtMs
            if (al.fireCdMs <= 0.0 && al.y > 70.0 && al.y < H - 80.0) {
                al.fireCdMs := Max(850.0, ((al.kind = "cruiser") ? 1300.0 : 1800.0) - this._wave * 70.0)
                bSpd := 260.0 + this._wave * 14.0
                this._bullets.Push({ x: al.x, y: al.y + al.radius, vx: 0.0, vy: bSpd, ttlMs: 2600.0, isEnemy: true })
            }

            hitByBullet := false
            bIdx := this._bullets.Length
            while (bIdx >= 1) {
                b := this._bullets[bIdx]
                if (!b.isEnemy && ((b.x - al.x) ** 2 + (b.y - al.y) ** 2) <= (al.radius + 5.0) ** 2) {
                    this._bullets.RemoveAt(bIdx)
                    hitByBullet := true
                    break
                }
                bIdx -= 1
            }
            if (hitByBullet) {
                this._DamageAlien(aIdx, 1)
                aIdx -= 1
                continue
            }

            if (s.invulnMs <= 0.0 && ((s.x - al.x) ** 2 + (s.y - al.y) ** 2) <= (al.radius + s.radius - 2.0) ** 2) {
                if (s.shieldMs > 0.0) {
                    s.shieldMs := 0.0
                    s.invulnMs := 1200.0
                    this._popups.Push({ x: s.x, y: s.y - 16.0, text: "SHIELD", ttlMs: 800.0, col: 0xFF38BDF8 })
                    this._DamageAlien(aIdx, al.hp)
                } else {
                    this._DamageShip()
                    if (this.Phase = "gameover")
                        return
                }
            }
            aIdx -= 1
        }

        ; Enemy plasma bolts hitting ship
        bIdx := this._bullets.Length
        while (bIdx >= 1) {
            b := this._bullets[bIdx]
            if (b.isEnemy && s.invulnMs <= 0.0 && ((b.x - s.x) ** 2 + (b.y - s.y) ** 2) <= (s.radius + 4.0) ** 2) {
                this._bullets.RemoveAt(bIdx)
                if (s.shieldMs > 0.0) {
                    s.shieldMs := 0.0
                    s.invulnMs := 1200.0
                    this._popups.Push({ x: s.x, y: s.y - 16.0, text: "SHIELD", ttlMs: 800.0, col: 0xFF38BDF8 })
                } else {
                    this._DamageShip()
                    if (this.Phase = "gameover")
                        return
                }
            }
            bIdx -= 1
        }

        ; Power-up drops (WEAPON_UP & SHIELD)
        pIdx := this._powerups.Length
        while (pIdx >= 1) {
            pu := this._powerups[pIdx]
            pu.ttlMs -= dtMs
            pu.x := Max(24.0, Min(W - 24.0, pu.x + pu.vx * dt))
            pu.y += pu.vy * dt
            if (pu.ttlMs <= 0.0 || pu.y > H + 24.0) {
                this._powerups.RemoveAt(pIdx)
                pIdx -= 1
                continue
            }
            if (((pu.x - s.x) ** 2 + (pu.y - s.y) ** 2) <= (s.radius + pu.radius + 4.0) ** 2) {
                if (pu.kind = "WEAPON_UP") {
                    if (this._weaponTier < 5) {
                        this._weaponTier += 1
                        lbl := (this._weaponTier == 5) ? "BEAM LASER!" : ("WPN TIER " this._weaponTier)
                        this._popups.Push({ x: pu.x, y: pu.y, text: lbl, ttlMs: 1100.0, col: 0xFF38BDF8 })
                    } else {
                        this._AddScore(150, pu.x, pu.y, 0xFF38BDF8)
                    }
                } else {
                    s.shieldMs := 12000.0
                    this._popups.Push({ x: pu.x, y: pu.y, text: "SHIELD", ttlMs: 900.0, col: 0xFF34D399 })
                }
                this._powerups.RemoveAt(pIdx)
            }
            pIdx -= 1
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

        ; Advance Alien wave when cleared
        if (this._aliens.Length == 0) {
            this._waveDelayMs += dtMs
            if (this._waveDelayMs >= 900.0) {
                this._waveDelayMs := 0.0
                this._wave += 1
                this._SpawnAlienWave(this._wave)
            }
        }
    }

    static _DamageAlien(idx, dmg := 1) {
        if (idx < 1 || idx > this._aliens.Length)
            return
        al := this._aliens[idx]
        al.hp -= dmg
        if (al.hp > 0) {
            this._SpawnExplosion(al.x, al.y, 0xFFF59E0B, 4)
            return
        }
        this._aliens.RemoveAt(idx)
        pts := (al.kind = "cruiser") ? 180 : ((al.kind = "raider") ? 90 : 50)
        col := (al.kind = "cruiser") ? 0xFFF59E0B : ((al.kind = "raider") ? 0xFFE879F9 : 0xFF38BDF8)
        this._AddScore(pts, al.x, al.y, col)
        this._SpawnExplosion(al.x, al.y, col, (al.kind = "cruiser") ? 14 : 8)
        dropChance := (al.kind = "cruiser") ? 85 : ((al.kind = "raider") ? 35 : 22)
        if (Random(1, 100) <= dropChance)
            this.SpawnPowerUp(al.x, al.y)
    }

    static _ResolveMicPillBounce(a, rect) {
        cx := Max(Float(rect.x), Min(a.x, Float(rect.x + rect.w)))
        cy := Max(Float(rect.y), Min(a.y, Float(rect.y + rect.h)))
        dx := a.x - cx
        dy := a.y - cy
        d2 := dx * dx + dy * dy
        if (d2 > a.radius * a.radius)
            return
        if (Abs(dx) >= Abs(dy)) {
            if (dx >= 0.0) {
                a.x := Float(rect.x + rect.w) + a.radius + 1.0
                a.vx := Abs(a.vx)
            } else {
                a.x := Float(rect.x) - a.radius - 1.0
                a.vx := -Abs(a.vx)
            }
        } else {
            if (dy >= 0.0) {
                a.y := Float(rect.y + rect.h) + a.radius + 1.0
                a.vy := Abs(a.vy)
            } else {
                a.y := Float(rect.y) - a.radius - 1.0
                a.vy := -Abs(a.vy)
            }
        }
    }

    static _DestroyAsteroid(idx) {
        a := this._asteroids[idx]
        this._asteroids.RemoveAt(idx)
        pts := (a.size == 3) ? 20 : ((a.size == 2) ? 50 : 100)
        this._AddScore(pts, a.x, a.y, 0xFF34D399)
        this._SpawnExplosion(a.x, a.y, 0xFF94A3B8, 6 + a.size * 2)

        if (a.size > 1) {
            nextSize := a.size - 1
            baseAng := DllCall("msvcrt\atan2", "Double", a.vy, "Double", a.vx, "Double")
            spd := Max(85.0, Sqrt(a.vx * a.vx + a.vy * a.vy) * 1.28)
            for _, off in [-0.65, 0.65] {
                na := baseAng + off
                this.SpawnAsteroid(a.x, a.y, Cos(na) * spd, Sin(na) * spd, nextSize)
            }
        } else if (Random(1, 100) <= 22) {
            this.SpawnPowerUp(a.x, a.y)
        }
    }

    static _DamageShip() {
        this._SpawnExplosion(this._ship.x, this._ship.y, 0xFFEF4444, 14)
        this._lives -= 1
        if (this._lives <= 0) {
            this.Phase := "gameover"
        } else {
            this._RespawnShip(false)
        }
    }

    static _AddScore(pts, x, y, col) {
        this._score += pts
        if (this._score > this._highScore) {
            this._highScore := this._score
            HudArcadeBase.SaveHighScore(this._cfg, "asteroids", this._highScore)
        }
        this._popups.Push({ x: x, y: y, text: "+" pts, ttlMs: 700.0, col: col })
    }

    static _SpawnExplosion(x, y, col, count) {
        Loop count {
            ang := Float(Random(0, 628)) / 100.0
            spd := Float(Random(40, 170))
            this._particles.Push({ x: x, y: y, vx: Cos(ang) * spd, vy: Sin(ang) * spd, ttlMs: 420.0, col: col })
        }
    }

    static GetSnapshot() {
        return {
            active: this.IsActive,
            phase: this.Phase,
            blasterMode: this._blasterMode,
            weaponTier: this._weaponTier,
            alienCount: this._aliens.Length,
            beamActive: this._beamActive,
            score: this._score,
            highScore: this._highScore,
            wave: this._wave,
            lives: this._lives,
            asteroidCount: this._asteroids.Length,
            bulletCount: this._bullets.Length,
            powerupCount: this._powerups.Length,
            saucerActive: IsObject(this._saucer) ? this._saucer.active : false,
            ship: this._ship
        }
    }

    static GetStateSnapshot() {
        return this.GetSnapshot()
    }

    static _RenderFrame() {
        if (!IsObject(this._surf) || !this._surf.pGraphics)
            return
        HudArcadeBase.BeginFrame(this._surf)
        g := this._surf.pGraphics
        W := this._surf.W, H := this._surf.H

        ; Optional Mic Pill Bumper halo highlight when enabled (Asteroid Blaster mode)
        if (this._blasterMode = "asteroids" && this._micBumper) {
            mr := HudArcadeBase.GetLiveMicPillRect(this._cfg, this._state)
            if (IsObject(mr))
                HudArcadeBase.StrokeRoundedRect(g, mr.x - 3, mr.y - 3, mr.w + 6, mr.h + 6, 12.0, 0x9938BDF8, 2.0)
        }

        ; Draw wireframe asteroids
        pAstPen := 0
        DllCall("gdiplus\GdipCreatePen1", "UInt", 0xFFE2E8F0, "Float", 1.8, "Int", 2, "Ptr*", &pAstPen)
        try {
            if (pAstPen) {
                for _, a in this._asteroids {
                    n := a.verts.Length
                    ptBuf := Buffer(n * 8, 0)
                    ca := Cos(a.rot), sa := Sin(a.rot)
                    for i, v in a.verts {
                        px := a.x + (v.c * ca - v.s * sa)
                        py := a.y + (v.c * sa + v.s * ca)
                        NumPut("Float", px, "Float", py, ptBuf, (i - 1) * 8)
                    }
                    DllCall("gdiplus\GdipDrawPolygon", "Ptr", g, "Ptr", pAstPen, "Ptr", ptBuf, "Int", n)
                }
            }
        } finally {
            if (pAstPen)
                DllCall("gdiplus\GdipDeletePen", "Ptr", pAstPen)
        }

        ; Draw Saucer
        if (this._saucer.active) {
            sc := this._saucer
            HudArcadeBase.FillRoundedRect(g, sc.x - 16.0, sc.y - 7.0, 32.0, 14.0, 7.0, 0xD80EA5E9)
            HudArcadeBase.StrokeRoundedRect(g, sc.x - 9.0, sc.y - 12.0, 18.0, 9.0, 5.0, 0xFFBAE6FD, 1.5)
        }

        ; Draw Alien Blaster enemies & Tier 5 Neon Beam Laser
        if (this._blasterMode = "alien") {
            if (this._beamActive && this._weaponTier >= 5 && this._lives > 0) {
                s := this._ship
                beamTop := 54.0
                beamH := Max(0.0, s.y - s.radius - beamTop)
                if (beamH > 0.0) {
                    HudArcadeBase.FillRoundedRect(g, s.x - 14.0, beamTop, 28.0, beamH, 8.0, 0x4438BDF8)
                    HudArcadeBase.FillRoundedRect(g, s.x - 7.0, beamTop, 14.0, beamH, 5.0, 0xCC06B6D4)
                    HudArcadeBase.FillRoundedRect(g, s.x - 2.5, beamTop, 5.0, beamH, 2.0, 0xFFFFFFFF)
                }
            }
            for _, al in this._aliens {
                col := (al.kind = "cruiser") ? 0xFFF59E0B : ((al.kind = "raider") ? 0xFFE879F9 : 0xFF38BDF8)
                pAlPen := 0
                DllCall("gdiplus\GdipCreatePen1", "UInt", col, "Float", 2.0, "Int", 2, "Ptr*", &pAlPen)
                try {
                    if (pAlPen) {
                        r := al.radius
                        if (al.kind = "cruiser") {
                            HudArcadeBase.FillRoundedRect(g, al.x - r, al.y - r * 0.55, r * 2.0, r * 1.1, 6.0, 0x55F59E0B)
                            HudArcadeBase.StrokeRoundedRect(g, al.x - r, al.y - r * 0.55, r * 2.0, r * 1.1, 6.0, col, 2.0)
                            if (al.maxHp > 1)
                                Gdip.DrawText(g, "x" al.hp, "Segoe UI", 7.5, 1, 0xFFFFFFFF, al.x - 16.0, al.y - 8.0, 32.0, 16.0, 1, 1, 0, false)
                        } else {
                            alBuf := Buffer(32, 0)
                            NumPut("Float", al.x, "Float", al.y + r, "Float", al.x - r, "Float", al.y - r * 0.7, "Float", al.x, "Float", al.y - r * 0.2, "Float", al.x + r, "Float", al.y - r * 0.7, alBuf, 0)
                            DllCall("gdiplus\GdipDrawPolygon", "Ptr", g, "Ptr", pAlPen, "Ptr", alBuf, "Int", 4)
                        }
                    }
                } finally {
                    if (pAlPen)
                        DllCall("gdiplus\GdipDeletePen", "Ptr", pAlPen)
                }
            }
        }

        ; Draw Power-Up HUD pills
        for _, pu in this._powerups {
            col := (pu.kind = "WEAPON_UP") ? 0xCC0EA5E9 : ((pu.kind = "RAPID") ? 0xCCF59E0B : ((pu.kind = "SPREAD") ? 0xCC10B981 : 0xCC3B82F6))
            HudArcadeBase.FillRoundedRect(g, pu.x - 22.0, pu.y - 10.0, 44.0, 20.0, 8.0, col)
            HudArcadeBase.StrokeRoundedRect(g, pu.x - 22.0, pu.y - 10.0, 44.0, 20.0, 8.0, 0xFFFFFFFF, 1.2)
            lbl := (pu.kind = "WEAPON_UP") ? "WPN+" : ((pu.kind = "RAPID") ? "RPD" : ((pu.kind = "SPREAD") ? "SPR" : "SHD"))
            Gdip.DrawText(g, lbl, "Segoe UI", 7.5, 1, 0xFFFFFFFF, pu.x - 22.0, pu.y - 10.0, 44.0, 20.0, 1, 1, 0, false)
        }

        ; Draw Bullets & Particles
        pBullBrush := 0, pEnmBrush := 0, pPartBrush := 0
        DllCall("gdiplus\GdipCreateSolidFill", "UInt", 0xFF34D399, "Ptr*", &pBullBrush)
        DllCall("gdiplus\GdipCreateSolidFill", "UInt", 0xFFFB7185, "Ptr*", &pEnmBrush)
        try {
            for _, b in this._bullets {
                br := b.isEnemy ? pEnmBrush : pBullBrush
                if (br)
                    DllCall("gdiplus\GdipFillEllipse", "Ptr", g, "Ptr", br, "Float", b.x - 3.0, "Float", b.y - 3.0, "Float", 6.0, "Float", 6.0)
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
            if (pBullBrush)
                DllCall("gdiplus\GdipDeleteBrush", "Ptr", pBullBrush)
            if (pEnmBrush)
                DllCall("gdiplus\GdipDeleteBrush", "Ptr", pEnmBrush)
        }

        ; Draw Ship (vector triangle + shield ring)
        s := this._ship
        blinkHide := (s.invulnMs > 0.0 && Mod(Integer(s.invulnMs / 80.0), 2) == 1)
        if (!blinkHide) {
            shipBuf := Buffer(24, 0)
            noseX := s.x + Cos(s.angle) * 16.0, noseY := s.y + Sin(s.angle) * 16.0
            lwX := s.x + Cos(s.angle + 2.45) * 14.0, lwY := s.y + Sin(s.angle + 2.45) * 14.0
            rwX := s.x + Cos(s.angle - 2.45) * 14.0, rwY := s.y + Sin(s.angle - 2.45) * 14.0
            NumPut("Float", noseX, "Float", noseY, "Float", lwX, "Float", lwY, "Float", rwX, "Float", rwY, shipBuf, 0)
            pShipPen := 0
            DllCall("gdiplus\GdipCreatePen1", "UInt", (s.shieldMs > 0.0) ? 0xFF38BDF8 : 0xFF10B981, "Float", 2.2, "Int", 2, "Ptr*", &pShipPen)
            try {
                if (pShipPen)
                    DllCall("gdiplus\GdipDrawPolygon", "Ptr", g, "Ptr", pShipPen, "Ptr", shipBuf, "Int", 3)
                if (s.shieldMs > 0.0 && pShipPen)
                    DllCall("gdiplus\GdipDrawEllipse", "Ptr", g, "Ptr", pShipPen, "Float", s.x - 20.0, "Float", s.y - 20.0, "Float", 40.0, "Float", 40.0)
            } finally {
                if (pShipPen)
                    DllCall("gdiplus\GdipDeletePen", "Ptr", pShipPen)
            }
        }

        ; Score popups
        for _, pp in this._popups
            Gdip.DrawText(g, pp.text, "Segoe UI", 9.0, 1, pp.col, pp.x - 36.0, pp.y - 12.0, 72.0, 24.0, 1, 1, 0, false)

        isDark := HudArcadeBase.ResolveDarkMode(this._cfg)
        micMuted := HudArcadeBase.ResolveMicMuted(this._state)
        if (this._blasterMode = "alien") {
            wpnTxt := (this._weaponTier >= 5) ? "WPN T5 BEAM" : ("WPN T" this._weaponTier)
            stats := Format("SCORE {}  •  BEST {}  •  WAVE {}  •  LIVES {}  •  {}  •  MODE: ALIEN [M]", this._score, this._highScore, this._wave, this._lives, wpnTxt)
            hints := "M → Asteroid Blaster  •  Arrows / WASD / Mouse: 2D Move  •  Space / Click: Fire  •  P: Pause  •  Esc: Exit"
            HudArcadeBase.DrawScoreboardPill(g, W, "ALIEN BLASTER", stats, hints, isDark, micMuted)
        } else {
            stats := Format("SCORE {}  •  BEST {}  •  WAVE {}  •  LIVES {}  •  MODE: ASTEROIDS [M]", this._score, this._highScore, this._wave, this._lives)
            hints := "M → Alien Blaster  •  Mouse / Arrows: Steer  •  Space / Click: Fire  •  B: Bumper (" (this._micBumper ? "ON" : "OFF") ")  •  P: Pause  •  Esc: Exit"
            HudArcadeBase.DrawScoreboardPill(g, W, "ASTEROID BLASTER", stats, hints, isDark, micMuted)
        }

        if (this.Phase = "paused") {
            curLbl := (this._blasterMode = "alien") ? "Alien Blaster" : "Asteroid Blaster"
            nextLbl := (this._blasterMode = "alien") ? "Asteroid Blaster" : "Alien Blaster"
            HudArcadeBase.DrawOverlayCard(g, W, H, "PAUSED", "Score: " this._score "  |  Wave: " this._wave "  |  Mode: " curLbl, "Press P: Resume  •  M → " nextLbl "  •  Esc: Exit", 0xFF38BDF8, isDark)
        } else if (this.Phase = "gameover") {
            nextLbl := (this._blasterMode = "alien") ? "Asteroid Blaster" : "Alien Blaster"
            HudArcadeBase.DrawOverlayCard(g, W, H, "GAME OVER", "Final Score: " this._score "  (Best: " this._highScore ")", "Press R or Left-Click to Retry  •  M → " nextLbl "  •  Esc to Exit", 0xFFEF4444, isDark)
        }

        alpha := (IsObject(this._cfg) && this._cfg.HasOwnProp("OpacityLevel")) ? this._cfg.OpacityLevel : 235
        HudArcadeBase.PresentFrame(this._surf, alpha)
    }
}
