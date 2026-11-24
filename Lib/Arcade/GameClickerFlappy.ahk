; ==============================================================================
; Module: GameClickerFlappy.ahk
; Description: Milestone M4 — Clicker Arcade: Clicker Flappy / Gravity Wave
;              - GameClickerFlappy (^!+f, "flappy"):
;                * Leak-proof interactiveMouse := true (0x01000000 catch-alpha
;                  + IDC_ARROW cursor 32512) so left-click flap/thrust never
;                  leaks clicks to underlying OBS, Zoom, or desktop windows.
;                * Dual Physics Modes (toggle via M key or Right-Click):
;                  1) Classic Flap ("flap"): discrete upward velocity impulse
;                     on tap/click + gravity arc.
;                  2) Gravity Wave ("wave"): hold-to-climb upward thrust,
;                     release-to-dive downward glide with glowing ribbon trail.
;                * Strict Audio Safety: BuildAllowedControlKeys(cfg) filters
;                  every candidate clicker/keyboard key (PgDn, PgUp, Right,
;                  Down, Up, Space, w, plus cfg.RemoteNextSlideKey and
;                  cfg.RemotePrevSlideKey) through
;                  !HudArcadeBase.IsReservedAudioKey(cfg, key) so HwMuteHotkey
;                  and HwTransitionHotkey are NEVER bound to Flap and remain
;                  100% live for emergency mic mute/unmute during gameplay.
; ==============================================================================

#Include "%A_LineFile%\..\..\HudArcadeBase.ahk"

class GameClickerFlappy {
    static IsActive := false
    static Phase := "idle" ; "idle" | "playing" | "paused" | "gameover"
    static _surf := ""
    static _cfg := ""
    static _state := ""
    static _savedPolling := ""
    static _boundHotkeys := []
    static _allowedKeys := []
    static _tickFn := ""
    static _lastUs := 0.0
    static _headless := false

    static _mode := "flap" ; "flap" | "wave"
    static _craftX := 240.0
    static _craftY := 360.0
    static _craftVy := 0.0
    static _craftRadius := 14.0
    static _isHolding := false
    static _mouseDown := false

    static _gates := []
    static _rings := []
    static _trail := []
    static _particles := []
    static _popups := []

    static _score := 0
    static _highScore := 0
    static _scrollSpeed := 270.0
    static _spawnTimerSec := 0.0
    static _animTimeSec := 0.0
    static _shieldMs := 0.0
    static _slowMoMs := 0.0

    static BuildAllowedControlKeys(cfg) {
        candidates := ["PgDn", "PgUp", "Right", "Down", "Up", "Space", "w"]
        if (IsObject(cfg)) {
            if (cfg.HasOwnProp("RemoteNextSlideKey")) {
                nk := Trim(String(cfg.RemoteNextSlideKey))
                if (nk != "" && StrLower(nk) != "none")
                    candidates.Push(nk)
            }
            if (cfg.HasOwnProp("RemotePrevSlideKey")) {
                pk := Trim(String(cfg.RemotePrevSlideKey))
                if (pk != "" && StrLower(pk) != "none")
                    candidates.Push(pk)
            }
        }
        allowed := []
        seen := Map()
        for _, rawKey in candidates {
            cleanKey := RegExReplace(Trim(String(rawKey)), "^[~*$]+")
            if (cleanKey = "" || StrLower(cleanKey) = "none")
                continue
            low := StrLower(cleanKey)
            if (seen.Has(low))
                continue
            if (HudArcadeBase.IsReservedAudioKey(cfg, cleanKey))
                continue
            seen[low] := true
            allowed.Push(cleanKey)
        }
        return allowed
    }

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
            title: "PresenterSyncClickerFlappy",
            onMouseEvent: this._OnMouse.Bind(this),
            headless: this._headless
        })
        if (!IsObject(this._surf))
            return false

        this.IsActive := true
        HudArcadeBase.RegisterActiveGame(this, "flappy")
        this._highScore := HudArcadeBase.LoadHighScore(cfg, "flappy")
        this._allowedKeys := this.BuildAllowedControlKeys(cfg)
        this._mode := "flap"
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
        this._isHolding := false
        this._mouseDown := false
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
        HudArcadeBase.ClearActiveGame("flappy")
    }

    static _BindKeys(cfg) {
        condFn := (*) => GameClickerFlappy.IsActive
        this._allowedKeys := this.BuildAllowedControlKeys(cfg)
        bindings := []
        for _, k in this._allowedKeys {
            cleanK := RegExReplace(Trim(String(k)), "^[~*$]+")
            if (cleanK = "" || HudArcadeBase.IsReservedAudioKey(cfg, cleanK))
                continue
            bindings.Push({ key: "$" cleanK, fn: (*) => GameClickerFlappy.FlapOrHold(true) })
            bindings.Push({ key: "$" cleanK " up", fn: (*) => GameClickerFlappy.FlapOrHold(false) })
        }
        bindings.Push({ key: "$m", fn: (*) => GameClickerFlappy.ToggleMode() })
        bindings.Push({ key: "$p", fn: (*) => GameClickerFlappy.TogglePause() })
        bindings.Push({ key: "$r", fn: (*) => (GameClickerFlappy.Phase = "gameover" ? GameClickerFlappy._ResetRun() : 0) })
        bindings.Push({ key: "$Escape", fn: (*) => GameClickerFlappy.Stop() })
        HudArcadeBase.BindKeysSafe(cfg, bindings, this._boundHotkeys, condFn)
    }

    static _OnMouse(msg, x, y, wp) {
        if (!this.IsActive)
            return
        if (msg == 0x0201 || msg == 0x0203) {
            this._mouseDown := true
            if (this.Phase = "gameover") {
                this._ResetRun()
            } else {
                this.FlapOrHold(true)
            }
        } else if (msg == 0x0202) {
            this._mouseDown := false
            this.FlapOrHold(false)
        } else if (msg == 0x0204) {
            this.ToggleMode()
        }
    }

    static ToggleMode() {
        this._mode := (this._mode = "wave") ? "flap" : "wave"
        if (IsObject(this._surf)) {
            lbl := (this._mode = "wave") ? "MODE: GRAVITY WAVE" : "MODE: CLASSIC FLAP"
            this._popups.Push({ x: this._craftX + 30.0, y: Max(90.0, this._craftY - 28.0), text: lbl, ttlMs: 850.0, col: 0xFF38BDF8 })
        }
        return this._mode
    }

    static TogglePause() {
        if (!this.IsActive)
            return
        if (this.Phase = "playing") {
            this.Phase := "paused"
            this._isHolding := false
        } else if (this.Phase = "paused") {
            this.Phase := "playing"
            this._lastUs := HudArcadeBase.NowUs()
        }
    }

    static FlapOrHold(isDown) {
        if (!this.IsActive)
            return false
        if (this.Phase = "gameover") {
            if (isDown)
                this._ResetRun()
            return true
        }
        if (this.Phase != "playing")
            return false

        down := !!isDown
        wasHolding := this._isHolding
        this._isHolding := down

        if (down) {
            if (this._mode = "flap") {
                if (!wasHolding) {
                    this._craftVy := -420.0
                    this._SpawnSparks(this._craftX - 10.0, this._craftY + 6.0, 0xFF38BDF8, 5)
                }
            } else {
                if (!wasHolding && this._craftVy > 60.0)
                    this._craftVy := 30.0
            }
        } else {
            if (this._mode = "wave" && wasHolding && this._craftVy < -60.0)
                this._craftVy := -30.0
        }
        return true
    }

    static _ResetRun() {
        W := IsObject(this._surf) ? Float(this._surf.W) : 1280.0
        H := IsObject(this._surf) ? Float(this._surf.H) : 720.0
        this._score := 0
        this._scrollSpeed := 270.0
        this._spawnTimerSec := 0.0
        this._animTimeSec := 0.0
        this._shieldMs := 0.0
        this._slowMoMs := 0.0
        this._isHolding := false
        this._mouseDown := false

        this._craftX := Max(160.0, W * 0.24)
        this._craftY := H * 0.48
        this._craftVy := 0.0
        this._craftRadius := 14.0

        this._gates := []
        this._rings := []
        this._trail := [{ x: this._craftX, y: this._craftY }]
        this._particles := []
        this._popups := []

        ; Spawn initial procedural horizon gates well ahead of craft
        firstX := Max(this._craftX + 360.0, W * 0.56)
        Loop 3 {
            gx := firstX + (A_Index - 1) * 340.0
            gy := this._ComputeNextGapY(H, A_Index)
            this.SpawnGateForTest(gx, gy, 178.0, 64.0)
        }
        this.Phase := "playing"
    }

    static _ComputeNextGapY(H, seedIdx := 0) {
        minGapY := 175.0
        maxGapY := Max(minGapY + 60.0, Float(H) - 155.0)
        return Float(Random(Integer(minGapY), Integer(maxGapY)))
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
        W := IsObject(this._surf) ? Float(this._surf.W) : 1280.0
        H := IsObject(this._surf) ? Float(this._surf.H) : 720.0
        this._animTimeSec += dt

        if (this._shieldMs > 0.0)
            this._shieldMs := Max(0.0, this._shieldMs - dtMs)
        if (this._slowMoMs > 0.0)
            this._slowMoMs := Max(0.0, this._slowMoMs - dtMs)

        if (readHardwareInput) {
            gpHold := false
            gp := HudArcadeBase.PollXInput()
            if (IsObject(gp)) {
                if ((gp.btn & 0x1000) || (gp.btn & 0x0001) || gp.ly > 10000)
                    gpHold := true
            }
            if (gpHold && !this._isHolding)
                this.FlapOrHold(true)
        }

        ; Difficulty & speed scaling with slow-mo support
        baseSpd := Min(490.0, 270.0 + Float(this._score) * 7.5)
        timeScale := (this._slowMoMs > 0.0) ? 0.65 : 1.0
        this._scrollSpeed := baseSpd * timeScale
        effDt := dt * timeScale

        ; Craft vertical physics: Classic Flap vs Gravity Wave
        if (this._mode = "wave") {
            if (this._isHolding) {
                this._craftVy := Max(-440.0, this._craftVy - 1600.0 * effDt)
            } else {
                this._craftVy := Min(460.0, this._craftVy + 1550.0 * effDt)
            }
        } else {
            this._craftVy := Min(680.0, this._craftVy + 1150.0 * effDt)
        }
        this._craftY += this._craftVy * effDt

        ; Scroll & record ribbon wave trail
        tIdx := this._trail.Length
        while (tIdx >= 1) {
            tp := this._trail[tIdx]
            tp.x -= this._scrollSpeed * dt
            if (tp.x < 20.0)
                this._trail.RemoveAt(tIdx)
            tIdx -= 1
        }
        this._trail.Push({ x: this._craftX, y: this._craftY })
        while (this._trail.Length > 52)
            this._trail.RemoveAt(1)

        ; Ceiling & floor bounds check
        minY := 68.0
        maxY := H - 24.0
        if (this._craftY - this._craftRadius < minY) {
            this._craftY := minY + this._craftRadius
            if (this._craftVy < 0.0)
                this._craftVy := 0.0
        }
        if (this._craftY + this._craftRadius > maxY) {
            if (this._shieldMs > 0.0) {
                this._shieldMs := 0.0
                this._craftY := maxY - this._craftRadius - 4.0
                this._craftVy := -320.0
                this._popups.Push({ x: this._craftX, y: this._craftY - 18.0, text: "SHIELD SAVED!", ttlMs: 800.0, col: 0xFF34D399 })
            } else {
                this._craftY := maxY - this._craftRadius
                this.Phase := "gameover"
                return
            }
        }

        ; Update gates: scroll, score pass, and pillar collision
        gIdx := this._gates.Length
        rightmostX := 0.0
        while (gIdx >= 1) {
            gt := this._gates[gIdx]
            gt.x -= this._scrollSpeed * dt
            gt.pulsePhase += dt * 3.2
            if (gt.x > rightmostX)
                rightmostX := gt.x

            ; Gate pass scoring
            if (!gt.passed && (gt.x + gt.w * 0.5) < this._craftX) {
                gt.passed := true
                this._AddScore(1, this._craftX, this._craftY - 22.0, 0xFF34D399)
                this._SpawnSparks(this._craftX, this._craftY, 0xFF34D399, 6)
            }

            ; Pillar collision check
            if ((this._craftX + this._craftRadius) > gt.x && (this._craftX - this._craftRadius) < (gt.x + gt.w)) {
                gapTop := gt.gapY - gt.gapH * 0.5
                gapBot := gt.gapY + gt.gapH * 0.5
                if ((this._craftY - this._craftRadius) < gapTop || (this._craftY + this._craftRadius) > gapBot) {
                    if (this._shieldMs > 0.0) {
                        this._shieldMs := 0.0
                        gt.passed := true
                        this._gates.RemoveAt(gIdx)
                        this._popups.Push({ x: this._craftX, y: this._craftY - 18.0, text: "SHIELD BREAK!", ttlMs: 850.0, col: 0xFFF59E0B })
                        this._SpawnSparks(this._craftX, this._craftY, 0xFFF59E0B, 10)
                        gIdx -= 1
                        continue
                    } else {
                        this._SpawnSparks(this._craftX, this._craftY, 0xFFEF4444, 14)
                        this.Phase := "gameover"
                        return
                    }
                }
            }

            if (gt.x + gt.w < -40.0)
                this._gates.RemoveAt(gIdx)
            gIdx -= 1
        }

        ; Procedural gate spawning when horizon clears
        if (this._gates.Length > 0 && rightmostX < W - 180.0) {
            gapH := Max(134.0, 178.0 - Float(this._score) * 1.4)
            nextX := Max(W + 40.0, rightmostX + 335.0)
            nextGapY := this._ComputeNextGapY(H, this._score)
            this.SpawnGateForTest(nextX, nextGapY, gapH, 64.0)
            if (Mod(this._score + this._gates.Length, 4) == 0) {
                rKind := (Mod(this._score, 2) == 0) ? "SHIELD" : "SLOW-MO"
                this.SpawnBonusRingForTest(nextX + 165.0, nextGapY, rKind)
            }
        }

        ; Update bonus rings (SHIELD / SLOW-MO)
        rIdx := this._rings.Length
        while (rIdx >= 1) {
            rg := this._rings[rIdx]
            rg.x -= this._scrollSpeed * dt
            dx := this._craftX - rg.x
            dy := this._craftY - rg.y
            sumR := this._craftRadius + rg.radius
            if ((dx * dx + dy * dy) <= (sumR * sumR)) {
                if (rg.kind = "SHIELD") {
                    this._shieldMs := 8000.0
                    this._popups.Push({ x: rg.x, y: rg.y - 14.0, text: "SHIELD", ttlMs: 850.0, col: 0xFF38BDF8 })
                } else {
                    this._slowMoMs := 6000.0
                    this._popups.Push({ x: rg.x, y: rg.y - 14.0, text: "SLOW-MO", ttlMs: 850.0, col: 0xFFA855F7 })
                }
                this._AddScore(2, rg.x, rg.y, 0xFF38BDF8)
                this._rings.RemoveAt(rIdx)
                rIdx -= 1
                continue
            }
            if (rg.x + rg.radius < -30.0)
                this._rings.RemoveAt(rIdx)
            rIdx -= 1
        }

        ; Update particles & floating popups
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
                pp.y -= 28.0 * dt
            idx -= 1
        }
    }

    static _AddScore(pts, x, y, col) {
        this._score += pts
        if (this._score > this._highScore) {
            this._highScore := this._score
            HudArcadeBase.SaveHighScore(this._cfg, "flappy", this._highScore)
        }
        this._popups.Push({ x: x, y: y, text: "+" pts, ttlMs: 720.0, col: col })
    }

    static _SpawnSparks(x, y, col, count) {
        Loop count {
            ang := Float(Random(0, 628)) / 100.0
            spd := Float(Random(45, 165))
            this._particles.Push({ x: x, y: y, vx: Cos(ang) * spd, vy: Sin(ang) * spd, ttlMs: 360.0, col: col })
        }
    }

    ; --- Headless Test Helpers ---
    static SetModeForTest(mode) {
        m := StrLower(Trim(String(mode)))
        if (InStr(m, "wave") || InStr(m, "gravity"))
            this._mode := "wave"
        else
            this._mode := "flap"
        return this._mode
    }

    static FlapOrHoldForTest(isDown) {
        return this.FlapOrHold(isDown)
    }

    static ClearGatesForTest() {
        this._gates := []
        this._rings := []
    }

    static SpawnGateForTest(x, gapY, gapH := 170.0, w := 64.0) {
        gt := {
            x: Float(x),
            w: Float(w),
            gapY: Float(gapY),
            gapH: Float(gapH),
            passed: false,
            pulsePhase: 0.0
        }
        this._gates.Push(gt)
        return gt
    }

    static SpawnBonusRingForTest(x, y, kind := "SHIELD") {
        rg := {
            x: Float(x),
            y: Float(y),
            radius: 18.0,
            kind: StrUpper(Trim(String(kind)))
        }
        this._rings.Push(rg)
        return rg
    }

    static SetCraftForTest(x, y, vy := 0.0) {
        this._craftX := Float(x)
        this._craftY := Float(y)
        this._craftVy := Float(vy)
    }

    static GetSnapshot() {
        return this.GetStateSnapshot()
    }

    static GetStateSnapshot() {
        return {
            active: this.IsActive,
            phase: this.Phase,
            mode: this._mode,
            score: this._score,
            highScore: this._highScore,
            craftX: this._craftX,
            craftY: this._craftY,
            craftVy: this._craftVy,
            craftRadius: this._craftRadius,
            isHolding: this._isHolding,
            gateCount: this._gates.Length,
            gates: this._gates,
            ringCount: this._rings.Length,
            trailCount: this._trail.Length,
            shieldMs: this._shieldMs,
            slowMoMs: this._slowMoMs,
            allowedKeys: this._allowedKeys
        }
    }

    static _RenderFrame() {
        if (!IsObject(this._surf) || !this._surf.pGraphics)
            return
        HudArcadeBase.BeginFrame(this._surf)
        g := this._surf.pGraphics
        W := Float(this._surf.W), H := Float(this._surf.H)

        ; Draw neon gate pillars with pulsing gap clearance caps
        minY := 68.0
        maxY := H - 24.0
        for _, gt in this._gates {
            gapTop := gt.gapY - gt.gapH * 0.5
            gapBot := gt.gapY + gt.gapH * 0.5
            topH := Max(0.0, gapTop - minY)
            botH := Max(0.0, maxY - gapBot)
            fillCol := (this._mode = "wave") ? 0xD00F172A : 0xD0111827
            brdCol := (this._mode = "wave") ? 0xFF38BDF8 : 0xFF10B981
            capCol := (this._mode = "wave") ? 0xFF0EA5E9 : 0xFF34D399

            if (topH > 4.0) {
                HudArcadeBase.FillRoundedRect(g, gt.x, minY, gt.w, topH, 8.0, fillCol)
                HudArcadeBase.StrokeRoundedRect(g, gt.x, minY, gt.w, topH, 8.0, brdCol, 1.8)
                capH := Min(12.0, topH)
                HudArcadeBase.FillRoundedRect(g, gt.x - 3.0, gapTop - capH, gt.w + 6.0, capH, 4.0, capCol)
            }
            if (botH > 4.0) {
                HudArcadeBase.FillRoundedRect(g, gt.x, gapBot, gt.w, botH, 8.0, fillCol)
                HudArcadeBase.StrokeRoundedRect(g, gt.x, gapBot, gt.w, botH, 8.0, brdCol, 1.8)
                capH := Min(12.0, botH)
                HudArcadeBase.FillRoundedRect(g, gt.x - 3.0, gapBot, gt.w + 6.0, capH, 4.0, capCol)
            }
        }

        ; Draw bonus rings
        for _, rg in this._rings {
            col := (rg.kind = "SHIELD") ? 0xFF38BDF8 : 0xFFA855F7
            r := rg.radius
            HudArcadeBase.StrokeRoundedRect(g, rg.x - r, rg.y - r, r * 2.0, r * 2.0, r, col, 2.4)
        }

        ; Draw glowing ribbon trail behind craft
        if (this._trail.Length >= 2) {
            pTrailPen := 0, pGlowPen := 0
            trailCol := (this._mode = "wave") ? 0xE038BDF8 : 0xB834D399
            glowCol := (this._mode = "wave") ? 0x550EA5E9 : 0x4410B981
            DllCall("gdiplus\GdipCreatePen1", "UInt", glowCol, "Float", 7.0, "Int", 2, "Ptr*", &pGlowPen)
            DllCall("gdiplus\GdipCreatePen1", "UInt", trailCol, "Float", 2.8, "Int", 2, "Ptr*", &pTrailPen)
            try {
                Loop (this._trail.Length - 1) {
                    p1 := this._trail[A_Index]
                    p2 := this._trail[A_Index + 1]
                    if (pGlowPen)
                        DllCall("gdiplus\GdipDrawLine", "Ptr", g, "Ptr", pGlowPen, "Float", p1.x, "Float", p1.y, "Float", p2.x, "Float", p2.y)
                    if (pTrailPen)
                        DllCall("gdiplus\GdipDrawLine", "Ptr", g, "Ptr", pTrailPen, "Float", p1.x, "Float", p1.y, "Float", p2.x, "Float", p2.y)
                }
            } finally {
                if (pTrailPen)
                    DllCall("gdiplus\GdipDeletePen", "Ptr", pTrailPen)
                if (pGlowPen)
                    DllCall("gdiplus\GdipDeletePen", "Ptr", pGlowPen)
            }
        }

        ; Draw craft & particles
        r := this._craftRadius
        craftCol := (this._mode = "wave") ? (this._isHolding ? 0xFF38BDF8 : 0xFF818CF8) : 0xFF34D399
        HudArcadeBase.FillRoundedRect(g, this._craftX - r, this._craftY - r * 0.78, r * 2.0, r * 1.56, 8.0, craftCol)
        HudArcadeBase.StrokeRoundedRect(g, this._craftX - r, this._craftY - r * 0.78, r * 2.0, r * 1.56, 8.0, 0xFFF8FAFC, 1.8)
        if (this._shieldMs > 0.0) {
            sr := r + 6.0
            HudArcadeBase.StrokeRoundedRect(g, this._craftX - sr, this._craftY - sr, sr * 2.0, sr * 2.0, sr, 0xFF38BDF8, 2.2)
        }

        pPartBrush := 0
        try {
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
        }

        for _, pp in this._popups
            Gdip.DrawText(g, pp.text, "Segoe UI", 9.0, 1, pp.col, pp.x - 56.0, pp.y - 12.0, 112.0, 24.0, 1, 1, 0, false)

        isDark := HudArcadeBase.ResolveDarkMode(this._cfg)
        micMuted := HudArcadeBase.ResolveMicMuted(this._state)
        titleTxt := (this._mode = "wave") ? "GRAVITY WAVE" : "CLICKER FLAPPY"
        modeChip := (this._mode = "wave") ? "WAVE (M → Flap)" : "FLAP (M → Wave)"
        stats := Format("SCORE {}  •  BEST {}  •  MODE: {}", this._score, this._highScore, modeChip)
        hint := "Clicker Slide / Space / Up / Click: Flap or Hold  •  M / Right-Click: Switch Mode  •  P: Pause  •  Esc: Exit"
        HudArcadeBase.DrawScoreboardPill(g, W, titleTxt, stats, hint, isDark, micMuted)

        if (this.Phase = "paused") {
            switchHint := (this._mode = "wave") ? "Press P: Resume   •   M: Classic Flap   •   Esc: Exit" : "Press P: Resume   •   M: Gravity Wave   •   Esc: Exit"
            HudArcadeBase.DrawOverlayCard(g, W, H, "PAUSED",
                Format("Score: {}   •   Best: {}   •   Mode: {}", this._score, this._highScore, (this._mode = "wave") ? "Gravity Wave" : "Classic Flap"),
                switchHint, 0xFF38BDF8, isDark)
        } else if (this.Phase = "gameover") {
            HudArcadeBase.DrawOverlayCard(g, W, H, "GATE COLLISION",
                Format("Final Score: {}   •   High Score: {}", this._score, this._highScore),
                "Press R, Space, or Click: Fly Again   •   M: Switch Mode   •   Esc: Exit", 0xFFEF4444, isDark)
        }

        HudArcadeBase.PresentFrame(this._surf)
    }
}
