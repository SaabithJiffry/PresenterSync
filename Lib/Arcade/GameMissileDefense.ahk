; ==============================================================================
; Module: GameMissileDefense.ahk
; Description: Game 8 — Missile Command / Meteor Defense (Ctrl+Alt+Shift+M)
;              Built on HudArcadeBase (interactiveMouse := true, IDC_CROSS).
;              4 bottom-edge neon shield pylons + central launcher silo,
;              diagonal incoming meteors & mid-air splitters, mouse/KB reticle
;              interceptor launches, expanding neon shockwave blast rings,
;              escalating chain-kill multipliers, and wave survival bonuses.
; ==============================================================================

#Include "%A_LineFile%\..\..\HudArcadeBase.ahk"

class GameMissileDefense {
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

    static _pylons := []
    static _siloX := 0.0
    static _siloY := 0.0
    static _meteors := []
    static _interceptors := []
    static _blasts := []
    static _particles := []
    static _popups := []

    static _score := 0
    static _highScore := 0
    static _wave := 1
    static _combo := 0
    static _comboTimerMs := 0.0
    static _wavePending := 0
    static _spawnCdMs := 0.0
    static _waveDelayMs := 0.0
    static _reticleX := 0.0
    static _reticleY := 0.0
    static _fireCdMs := 0.0

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
            title: "PresenterSyncMissileDefense",
            onMouseEvent: this._OnMouse.Bind(this),
            headless: this._headless
        })
        if (!IsObject(this._surf))
            return false

        this.IsActive := true
        HudArcadeBase.RegisterActiveGame(this, "missile_defense")
        this._highScore := HudArcadeBase.LoadHighScore(cfg, "missile_defense")
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
        HudArcadeBase.ClearActiveGame("missile_defense")
    }

    static _BindKeys(cfg) {
        condFn := (*) => GameMissileDefense.IsActive
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
            { key: "$Space", fn: (*) => GameMissileDefense._OnFireKey() },
            { key: "$Enter", fn: (*) => GameMissileDefense._OnFireKey() },
            { key: "$p", fn: (*) => GameMissileDefense.TogglePause() },
            { key: "$r", fn: (*) => GameMissileDefense.RestartIfGameOver() },
            { key: "$Escape", fn: (*) => GameMissileDefense.Stop() }
        ]
        HudArcadeBase.BindKeysSafe(cfg, bindings, this._boundHotkeys, condFn)
    }

    static _OnFireKey() {
        if (!this.IsActive)
            return
        if (this.Phase = "gameover") {
            this._ResetRun()
            return
        }
        if (this.Phase = "playing")
            this.FireInterceptor(this._reticleX, this._reticleY)
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

    static _OnMouse(msg, x, y, wp) {
        if (!this.IsActive || !IsObject(this._surf))
            return
        W := Float(this._surf.W), H := Float(this._surf.H)
        cx := Max(24.0, Min(W - 24.0, Float(x)))
        cy := Max(64.0, Min(H - 56.0, Float(y)))
        this._reticleX := cx
        this._reticleY := cy
        if (msg == 0x0201) { ; WM_LBUTTONDOWN
            if (this.Phase = "gameover") {
                this._ResetRun()
                return
            }
            if (this.Phase = "playing")
                this.FireInterceptor(cx, cy)
        }
    }

    static StepForTest(dtSec) {
        if (!this.IsActive)
            return
        rem := Max(0.0, Float(dtSec))
        while (rem > 0.0) {
            stepDt := Min(0.025, rem)
            this._Step(stepDt)
            rem -= stepDt
        }
    }

    static SpawnMeteorForTest(x, y, vx, vy, isSplitter := false) {
        if (!this.IsActive || !IsObject(this._surf))
            return ""
        H := Float(this._surf.H)
        m := {
            x: Float(x),
            y: Float(y),
            vx: Float(vx),
            vy: Float(vy),
            radius: isSplitter ? 9.0 : 7.0,
            isSplitter: !!isSplitter,
            splitDone: false,
            splitY: H * 0.42,
            trail: []
        }
        this._meteors.Push(m)
        return m
    }

    static FireInterceptorForTest(tx, ty) {
        return this.FireInterceptor(tx, ty, true)
    }

    static GetStateSnapshot() {
        alive := this._CountAlivePylons()
        return {
            phase: this.Phase,
            score: this._score,
            highScore: this._highScore,
            wave: this._wave,
            pylonsAlive: alive,
            totalPylons: this._pylons.Length,
            combo: this._combo,
            meteorsCount: this._meteors.Length,
            interceptorsCount: this._interceptors.Length,
            blastsCount: this._blasts.Length,
            interactiveMouse: IsObject(this._surf) ? this._surf.interactiveMouse : false,
            cursorId: IsObject(this._surf) ? this._surf.cursorId : 0
        }
    }

    static _ResetRun() {
        W := Float(this._surf.W), H := Float(this._surf.H)
        this._score := 0
        this._wave := 1
        this._combo := 0
        this._comboTimerMs := 0.0
        this._waveDelayMs := 0.0
        this._fireCdMs := 0.0
        this._siloX := W * 0.5
        this._siloY := H - 28.0
        this._reticleX := W * 0.5
        this._reticleY := H * 0.45

        this._pylons := [
            { x: W * 0.16, y: H - 34.0, alive: true, radius: 22.0 },
            { x: W * 0.34, y: H - 34.0, alive: true, radius: 22.0 },
            { x: W * 0.66, y: H - 34.0, alive: true, radius: 22.0 },
            { x: W * 0.84, y: H - 34.0, alive: true, radius: 22.0 }
        ]
        this._meteors := []
        this._interceptors := []
        this._blasts := []
        this._particles := []
        this._popups := []
        this._StartWave(1)
        this.Phase := "playing"
    }

    static _StartWave(waveNum) {
        this._wave := waveNum
        this._wavePending := 5 + waveNum * 3
        this._spawnCdMs := 450.0
    }

    static _CountAlivePylons() {
        cnt := 0
        for _, p in this._pylons {
            if (p.alive)
                cnt += 1
        }
        return cnt
    }

    static _PickLauncherOrigin(tx) {
        bestX := this._siloX
        bestY := this._siloY
        bestDist := Abs(tx - this._siloX)
        for _, p in this._pylons {
            if (!p.alive)
                continue
            d := Abs(tx - p.x)
            if (d < bestDist) {
                bestDist := d
                bestX := p.x
                bestY := p.y - 10.0
            }
        }
        return { x: bestX, y: bestY }
    }

    static FireInterceptor(tx, ty, bypassCd := false) {
        if (!this.IsActive || this.Phase != "playing" || !IsObject(this._surf))
            return false
        if (!bypassCd && this._fireCdMs > 0.0)
            return false
        W := Float(this._surf.W), H := Float(this._surf.H)
        clampedX := Max(20.0, Min(W - 20.0, Float(tx)))
        clampedY := Max(60.0, Min(H - 54.0, Float(ty)))
        orig := this._PickLauncherOrigin(clampedX)
        dx := clampedX - orig.x
        dy := clampedY - orig.y
        dist := Sqrt(dx * dx + dy * dy)
        if (dist < 1.0)
            dist := 1.0
        spd := 720.0
        this._interceptors.Push({
            sx: orig.x,
            sy: orig.y,
            x: orig.x,
            y: orig.y,
            tx: clampedX,
            ty: clampedY,
            vx: (dx / dist) * spd,
            vy: (dy / dist) * spd,
            speed: spd,
            trail: []
        })
        this._fireCdMs := 110.0
        return true
    }

    static _SpawnWaveMeteor() {
        W := Float(this._surf.W), H := Float(this._surf.H)
        sx := Float(Random(36, Integer(Max(40.0, W - 36.0))))
        sy := 54.0

        ; Aim toward a random alive pylon (or center)
        aliveList := []
        for _, p in this._pylons {
            if (p.alive)
                aliveList.Push(p)
        }
        targetX := (aliveList.Length > 0) ? aliveList[Random(1, aliveList.Length)].x : (W * 0.5)
        targetX += Float(Random(-28, 28))
        targetY := H - 34.0

        dx := targetX - sx
        dy := Max(60.0, targetY - sy)
        dist := Sqrt(dx * dx + dy * dy)
        spd := 78.0 + Float(this._wave) * 14.0 + Float(Random(0, 26))
        isSplit := (this._wave >= 2) && (Random(1, 100) <= Min(40, 14 + this._wave * 4))
        this._meteors.Push({
            x: sx,
            y: sy,
            vx: (dx / dist) * spd,
            vy: (dy / dist) * spd,
            radius: isSplit ? 9.0 : 7.0,
            isSplitter: isSplit,
            splitDone: false,
            splitY: H * (0.30 + Float(Random(0, 18)) / 100.0),
            trail: []
        })
    }

    static _AddBlast(x, y) {
        this._blasts.Push({
            x: Float(x),
            y: Float(y),
            r: 8.0,
            maxR: 64.0,
            ageMs: 0.0,
            lifeMs: 860.0,
            kills: 0
        })
        Loop 10 {
            ang := Float(Random(0, 628)) / 100.0
            spd := Float(Random(40, 160))
            this._particles.Push({
                x: Float(x),
                y: Float(y),
                vx: Cos(ang) * spd,
                vy: Sin(ang) * spd,
                lifeMs: 420.0,
                col: (Mod(A_Index, 2) == 0) ? 0xFF38BDF8 : 0xFF34D399
            })
        }
    }

    static _SpawnHitParticles(x, y, col) {
        Loop 8 {
            ang := Float(Random(0, 628)) / 100.0
            spd := Float(Random(40, 140))
            this._particles.Push({
                x: Float(x),
                y: Float(y),
                vx: Cos(ang) * spd,
                vy: Sin(ang) * spd,
                lifeMs: 380.0,
                col: col
            })
        }
    }

    static _AddPopup(x, y, txt, col) {
        this._popups.Push({ x: Float(x), y: Float(y), text: txt, col: col, lifeMs: 850.0 })
    }

    static _AwardScore(pts) {
        this._score += pts
        if (this._score > this._highScore) {
            this._highScore := this._score
            HudArcadeBase.SaveHighScore(this._cfg, "missile_defense", this._highScore)
        }
    }

    static _FrameTick() {
        if (!this.IsActive)
            return
        nowUs := HudArcadeBase.NowUs()
        dt := (nowUs - this._lastUs) / 1000000.0
        this._lastUs := nowUs
        dt := Max(0.001, Min(0.05, dt))
        if (this.Phase = "playing")
            this._Step(dt)
        this._RenderFrame()
    }

    static _Step(dt) {
        if (this.Phase != "playing")
            return
        W := Float(this._surf.W), H := Float(this._surf.H)
        dtMs := dt * 1000.0

        this._fireCdMs := Max(0.0, this._fireCdMs - dtMs)
        if (this._comboTimerMs > 0.0) {
            this._comboTimerMs -= dtMs
            if (this._comboTimerMs <= 0.0)
                this._combo := 0
        }

        ; Keyboard reticle movement
        if (!this._headless) {
            mvL := GetKeyState("Left", "P") || GetKeyState("a", "P")
            mvR := GetKeyState("Right", "P") || GetKeyState("d", "P")
            mvU := GetKeyState("Up", "P") || GetKeyState("w", "P")
            mvD := GetKeyState("Down", "P") || GetKeyState("s", "P")
            ix := (mvR ? 1.0 : 0.0) - (mvL ? 1.0 : 0.0)
            iy := (mvD ? 1.0 : 0.0) - (mvU ? 1.0 : 0.0)
            if (ix != 0.0 || iy != 0.0) {
                if (ix != 0.0 && iy != 0.0) {
                    ix *= 0.70710678
                    iy *= 0.70710678
                }
                this._reticleX := Max(24.0, Min(W - 24.0, this._reticleX + ix * 440.0 * dt))
                this._reticleY := Max(64.0, Min(H - 56.0, this._reticleY + iy * 440.0 * dt))
            }
        }

        ; Wave delay / spawning
        if (this._waveDelayMs > 0.0) {
            this._waveDelayMs -= dtMs
            if (this._waveDelayMs <= 0.0)
                this._StartWave(this._wave + 1)
        } else if (this._wavePending > 0) {
            this._spawnCdMs -= dtMs
            if (this._spawnCdMs <= 0.0) {
                this._SpawnWaveMeteor()
                this._wavePending -= 1
                this._spawnCdMs := Max(280.0, 920.0 - Float(this._wave) * 65.0)
            }
        }

        ; Move interceptors & detonate at target
        iIdx := this._interceptors.Length
        while (iIdx >= 1) {
            ic := this._interceptors[iIdx]
            ic.trail.Push({ x: ic.x, y: ic.y })
            if (ic.trail.Length > 7)
                ic.trail.RemoveAt(1)
            dx := ic.tx - ic.x
            dy := ic.ty - ic.y
            remDist := Sqrt(dx * dx + dy * dy)
            stepDist := ic.speed * dt
            if (remDist <= stepDist + 2.0) {
                this._AddBlast(ic.tx, ic.ty)
                this._interceptors.RemoveAt(iIdx)
            } else {
                ic.x += ic.vx * dt
                ic.y += ic.vy * dt
            }
            iIdx -= 1
        }

        ; Expand & fade shockwave blast rings
        bIdx := this._blasts.Length
        while (bIdx >= 1) {
            b := this._blasts[bIdx]
            b.ageMs += dtMs
            if (b.ageMs >= b.lifeMs) {
                this._blasts.RemoveAt(bIdx)
            } else {
                expandFrac := Min(1.0, b.ageMs / 420.0)
                b.r := 8.0 + (b.maxR - 8.0) * (1.0 - (1.0 - expandFrac) ** 2)
            }
            bIdx -= 1
        }

        ; Move meteors, handle mid-air splitters, blast kills, and pylon impacts
        mIdx := this._meteors.Length
        while (mIdx >= 1) {
            m := this._meteors[mIdx]
            m.trail.Push({ x: m.x, y: m.y })
            if (m.trail.Length > 8)
                m.trail.RemoveAt(1)
            m.x += m.vx * dt
            m.y += m.vy * dt

            ; Splitter fork mid-descent
            if (m.isSplitter && !m.splitDone && m.y >= m.splitY) {
                m.splitDone := true
                m.isSplitter := false
                m.radius := 7.0
                childSpd := Max(70.0, Sqrt(m.vx * m.vx + m.vy * m.vy))
                this._meteors.Push({
                    x: m.x - 6.0, y: m.y,
                    vx: m.vx - childSpd * 0.28, vy: Max(65.0, m.vy * 0.96),
                    radius: 7.0, isSplitter: false, splitDone: true, splitY: H, trail: []
                })
                this._meteors.Push({
                    x: m.x + 6.0, y: m.y,
                    vx: m.vx + childSpd * 0.28, vy: Max(65.0, m.vy * 0.96),
                    radius: 7.0, isSplitter: false, splitDone: true, splitY: H, trail: []
                })
                this._SpawnHitParticles(m.x, m.y, 0xFFF59E0B)
                this._meteors.RemoveAt(mIdx)
                mIdx -= 1
                continue
            }

            ; Check collision against active shockwave blasts
            killedBy := ""
            for _, b in this._blasts {
                dx := m.x - b.x
                dy := m.y - b.y
                if ((dx * dx + dy * dy) <= (b.r + m.radius) ** 2) {
                    killedBy := b
                    break
                }
            }
            if (IsObject(killedBy)) {
                killedBy.kills += 1
                this._combo := Min(4, Max(this._combo + 1, killedBy.kills))
                this._comboTimerMs := 1500.0
                mult := Min(4, Max(1, killedBy.kills))
                basePts := m.isSplitter ? 40 : 25
                pts := basePts * mult
                this._AwardScore(pts)
                this._SpawnHitParticles(m.x, m.y, (mult >= 2) ? 0xFFF59E0B : 0xFF38BDF8)
                this._AddPopup(m.x, m.y - 10.0, (mult > 1) ? ("+" pts " x" mult "!") : ("+" pts), (mult > 1) ? 0xFFFBBF24 : 0xFF34D399)
                this._meteors.RemoveAt(mIdx)
                mIdx -= 1
                continue
            }

            ; Check pylon collision or ground impact
            hitPylon := false
            for _, p in this._pylons {
                if (!p.alive)
                    continue
                dx := m.x - p.x
                dy := m.y - p.y
                if ((dx * dx + dy * dy) <= (p.radius + m.radius) ** 2) {
                    p.alive := false
                    hitPylon := true
                    this._SpawnHitParticles(p.x, p.y, 0xFFEF4444)
                    this._AddPopup(p.x, p.y - 24.0, "PYLON LOST!", 0xFFEF4444)
                    break
                }
            }
            if (hitPylon || m.y >= H - 24.0 || m.x < -30.0 || m.x > W + 30.0) {
                if (hitPylon) {
                    this._combo := 0
                    if (this._CountAlivePylons() == 0) {
                        this.Phase := "gameover"
                        HudArcadeBase.SaveHighScore(this._cfg, "missile_defense", this._highScore)
                    }
                }
                this._meteors.RemoveAt(mIdx)
            }
            mIdx -= 1
        }

        ; Wave completion check
        if (this.Phase = "playing" && this._wavePending <= 0 && this._meteors.Length == 0 && this._waveDelayMs <= 0.0) {
            alive := this._CountAlivePylons()
            bonus := alive * 100
            if (bonus > 0) {
                this._AwardScore(bonus)
                this._AddPopup(W * 0.5, H * 0.35, "WAVE " this._wave " CLEAR +" bonus, 0xFF38BDF8)
            }
            if (Mod(this._wave, 3) == 0 && alive < this._pylons.Length) {
                for _, p in this._pylons {
                    if (!p.alive) {
                        p.alive := true
                        this._AddPopup(p.x, p.y - 26.0, "PYLON RESTORED!", 0xFF10B981)
                        break
                    }
                }
            }
            if (this._headless)
                this._StartWave(this._wave + 1)
            else
                this._waveDelayMs := 1200.0
        }

        ; Update particles & popups
        pIdx := this._particles.Length
        while (pIdx >= 1) {
            pt := this._particles[pIdx]
            pt.lifeMs -= dtMs
            pt.x += pt.vx * dt
            pt.y += pt.vy * dt
            if (pt.lifeMs <= 0.0)
                this._particles.RemoveAt(pIdx)
            pIdx -= 1
        }
        ppIdx := this._popups.Length
        while (ppIdx >= 1) {
            pp := this._popups[ppIdx]
            pp.lifeMs -= dtMs
            pp.y -= 28.0 * dt
            if (pp.lifeMs <= 0.0)
                this._popups.RemoveAt(ppIdx)
            ppIdx -= 1
        }
    }

    static _RenderFrame() {
        if (!this.IsActive || !IsObject(this._surf))
            return
        HudArcadeBase.BeginFrame(this._surf)
        g := this._surf.pGraphics
        W := Float(this._surf.W), H := Float(this._surf.H)

        ; Ground baseline
        pBasePen := 0
        DllCall("gdiplus\GdipCreatePen1", "UInt", 0x6638BDF8, "Float", 2.0, "Int", 2, "Ptr*", &pBasePen)
        try {
            if (pBasePen)
                DllCall("gdiplus\GdipDrawLine", "Ptr", g, "Ptr", pBasePen, "Float", 20.0, "Float", H - 18.0, "Float", W - 20.0, "Float", H - 18.0)
        } finally {
            if (pBasePen)
                DllCall("gdiplus\GdipDeletePen", "Ptr", pBasePen)
        }

        ; Draw 4 neon shield pylons + central silo
        for _, p in this._pylons {
            if (p.alive) {
                HudArcadeBase.FillRoundedRect(g, p.x - 20.0, p.y - 10.0, 40.0, 20.0, 6.0, 0xCC0EA5E9)
                HudArcadeBase.StrokeRoundedRect(g, p.x - 20.0, p.y - 10.0, 40.0, 20.0, 6.0, 0xFF7DD3FC, 1.8)
            } else {
                HudArcadeBase.FillRoundedRect(g, p.x - 18.0, p.y + 2.0, 36.0, 8.0, 3.0, 0x66EF4444)
            }
        }
        HudArcadeBase.FillRoundedRect(g, this._siloX - 16.0, this._siloY - 12.0, 32.0, 22.0, 8.0, 0xCC10B981)
        HudArcadeBase.StrokeRoundedRect(g, this._siloX - 16.0, this._siloY - 12.0, 32.0, 22.0, 8.0, 0xFF6EE7B7, 1.8)

        ; Draw incoming meteors + trails
        pTrailPen := 0, pSplitPen := 0, pMeteorBrush := 0, pSplitBrush := 0
        DllCall("gdiplus\GdipCreatePen1", "UInt", 0x99FB7185, "Float", 2.0, "Int", 2, "Ptr*", &pTrailPen)
        DllCall("gdiplus\GdipCreatePen1", "UInt", 0xBBF59E0B, "Float", 2.4, "Int", 2, "Ptr*", &pSplitPen)
        DllCall("gdiplus\GdipCreateSolidFill", "UInt", 0xFFF43F5E, "Ptr*", &pMeteorBrush)
        DllCall("gdiplus\GdipCreateSolidFill", "UInt", 0xFFF59E0B, "Ptr*", &pSplitBrush)
        try {
            for _, m in this._meteors {
                pen := m.isSplitter ? pSplitPen : pTrailPen
                br := m.isSplitter ? pSplitBrush : pMeteorBrush
                if (pen && m.trail.Length >= 1) {
                    first := m.trail[1]
                    DllCall("gdiplus\GdipDrawLine", "Ptr", g, "Ptr", pen, "Float", first.x, "Float", first.y, "Float", m.x, "Float", m.y)
                }
                if (br)
                    DllCall("gdiplus\GdipFillEllipse", "Ptr", g, "Ptr", br, "Float", m.x - m.radius, "Float", m.y - m.radius, "Float", m.radius * 2.0, "Float", m.radius * 2.0)
            }
        } finally {
            if (pTrailPen)
                DllCall("gdiplus\GdipDeletePen", "Ptr", pTrailPen)
            if (pSplitPen)
                DllCall("gdiplus\GdipDeletePen", "Ptr", pSplitPen)
            if (pMeteorBrush)
                DllCall("gdiplus\GdipDeleteBrush", "Ptr", pMeteorBrush)
            if (pSplitBrush)
                DllCall("gdiplus\GdipDeleteBrush", "Ptr", pSplitBrush)
        }

        ; Draw interceptors + target markers
        pIntPen := 0, pIntBrush := 0
        DllCall("gdiplus\GdipCreatePen1", "UInt", 0xAA34D399, "Float", 2.0, "Int", 2, "Ptr*", &pIntPen)
        DllCall("gdiplus\GdipCreateSolidFill", "UInt", 0xFF6EE7B7, "Ptr*", &pIntBrush)
        try {
            for _, ic in this._interceptors {
                if (pIntPen)
                    DllCall("gdiplus\GdipDrawLine", "Ptr", g, "Ptr", pIntPen, "Float", ic.sx, "Float", ic.sy, "Float", ic.x, "Float", ic.y)
                if (pIntBrush)
                    DllCall("gdiplus\GdipFillEllipse", "Ptr", g, "Ptr", pIntBrush, "Float", ic.x - 3.0, "Float", ic.y - 3.0, "Float", 6.0, "Float", 6.0)
                if (pIntPen) {
                    DllCall("gdiplus\GdipDrawLine", "Ptr", g, "Ptr", pIntPen, "Float", ic.tx - 5.0, "Float", ic.ty - 5.0, "Float", ic.tx + 5.0, "Float", ic.ty + 5.0)
                    DllCall("gdiplus\GdipDrawLine", "Ptr", g, "Ptr", pIntPen, "Float", ic.tx + 5.0, "Float", ic.ty - 5.0, "Float", ic.tx - 5.0, "Float", ic.ty + 5.0)
                }
            }
        } finally {
            if (pIntPen)
                DllCall("gdiplus\GdipDeletePen", "Ptr", pIntPen)
            if (pIntBrush)
                DllCall("gdiplus\GdipDeleteBrush", "Ptr", pIntBrush)
        }

        ; Draw expanding neon shockwave blast rings
        for _, b in this._blasts {
            frac := Max(0.0, Min(1.0, 1.0 - (b.ageMs / b.lifeMs)))
            aFill := Integer(frac * 95.0)
            aRing := Integer(frac * 240.0)
            colFill := (aFill << 24) | 0x38BDF8
            colRing := (aRing << 24) | 0x7DD3FC
            pBBrush := 0, pBPen := 0
            DllCall("gdiplus\GdipCreateSolidFill", "UInt", colFill, "Ptr*", &pBBrush)
            DllCall("gdiplus\GdipCreatePen1", "UInt", colRing, "Float", 2.4, "Int", 2, "Ptr*", &pBPen)
            try {
                if (pBBrush)
                    DllCall("gdiplus\GdipFillEllipse", "Ptr", g, "Ptr", pBBrush, "Float", b.x - b.r, "Float", b.y - b.r, "Float", b.r * 2.0, "Float", b.r * 2.0)
                if (pBPen)
                    DllCall("gdiplus\GdipDrawEllipse", "Ptr", g, "Ptr", pBPen, "Float", b.x - b.r, "Float", b.y - b.r, "Float", b.r * 2.0, "Float", b.r * 2.0)
            } finally {
                if (pBBrush)
                    DllCall("gdiplus\GdipDeleteBrush", "Ptr", pBBrush)
                if (pBPen)
                    DllCall("gdiplus\GdipDeletePen", "Ptr", pBPen)
            }
        }

        ; Draw particles
        for _, pt in this._particles {
            pPtBrush := 0
            DllCall("gdiplus\GdipCreateSolidFill", "UInt", pt.col, "Ptr*", &pPtBrush)
            try {
                if (pPtBrush)
                    DllCall("gdiplus\GdipFillEllipse", "Ptr", g, "Ptr", pPtBrush, "Float", pt.x - 2.0, "Float", pt.y - 2.0, "Float", 4.0, "Float", 4.0)
            } finally {
                if (pPtBrush)
                    DllCall("gdiplus\GdipDeleteBrush", "Ptr", pPtBrush)
            }
        }

        ; Draw aiming reticle
        pRetPen := 0
        DllCall("gdiplus\GdipCreatePen1", "UInt", 0xCC38BDF8, "Float", 1.6, "Int", 2, "Ptr*", &pRetPen)
        try {
            if (pRetPen) {
                DllCall("gdiplus\GdipDrawEllipse", "Ptr", g, "Ptr", pRetPen, "Float", this._reticleX - 10.0, "Float", this._reticleY - 10.0, "Float", 20.0, "Float", 20.0)
                DllCall("gdiplus\GdipDrawLine", "Ptr", g, "Ptr", pRetPen, "Float", this._reticleX - 14.0, "Float", this._reticleY, "Float", this._reticleX + 14.0, "Float", this._reticleY)
                DllCall("gdiplus\GdipDrawLine", "Ptr", g, "Ptr", pRetPen, "Float", this._reticleX, "Float", this._reticleY - 14.0, "Float", this._reticleX, "Float", this._reticleY + 14.0)
            }
        } finally {
            if (pRetPen)
                DllCall("gdiplus\GdipDeletePen", "Ptr", pRetPen)
        }

        ; Popups
        for _, pp in this._popups
            Gdip.DrawText(g, pp.text, "Segoe UI", 9.0, 1, pp.col, pp.x - 56.0, pp.y - 12.0, 112.0, 24.0, 1, 1, 0, false)

        isDark := IsSet(Theme) ? Theme.IsDarkMode() : true
        micMuted := (IsObject(this._state) && this._state.HasOwnProp("isMuted")) ? (this._state.isMuted ? 1 : 0) : -1
        alive := this._CountAlivePylons()
        comboStr := (this._combo > 1) ? ("x" this._combo) : "x1"
        stats := Format("SCORE {}  •  BEST {}  •  WAVE {}  •  PYLONS {}/4  •  COMBO {}", this._score, this._highScore, this._wave, alive, comboStr)
        hints := "CLICK / ARROWS+SPACE FIRE INTERCEPTOR  •  P PAUSE  •  ESC EXIT"
        HudArcadeBase.DrawScoreboardPill(g, W, "MISSILE DEFENSE", stats, hints, isDark, micMuted)

        if (this.Phase = "paused")
            HudArcadeBase.DrawOverlayCard(g, W, H, "PAUSED", "Score: " this._score "  |  Wave: " this._wave, "Press P to Resume or Esc to Exit", 0xFF38BDF8, isDark)
        else if (this.Phase = "gameover")
            HudArcadeBase.DrawOverlayCard(g, W, H, "GAME OVER", "Final Score: " this._score "  (Best: " this._highScore ")", "Press R or Left-Click to Retry  •  Esc to Exit", 0xFFEF4444, isDark)

        alpha := (IsObject(this._cfg) && this._cfg.HasOwnProp("OpacityLevel")) ? this._cfg.OpacityLevel : 235
        HudArcadeBase.PresentFrame(this._surf, alpha)
    }
}
