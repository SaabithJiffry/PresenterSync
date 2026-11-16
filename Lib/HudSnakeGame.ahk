; ==============================================================================
; Module: HudSnakeGame.ahk
; Description: Hidden desktop-floating Snake Easter Egg (Alt+Ctrl+Shift+S).
;              Morphs active PresenterSync HUD pills into a seamless, matte-glass
;              continuous ribbon snake at 60 FPS using QPC sub-cell rail
;              interpolation on the topmost click-through desktop layer, pausing
;              blocking network/UIA polling timers so gameplay never stutters.
; ==============================================================================

#Include "%A_LineFile%\..\Gdip.ahk"

class HudSnake {
    static IsActive := false
    static Phase := "idle" ; "idle" | "morph" | "playing" | "paused" | "gameover"

    ; Screen & Grid Geometry
    static _waLeft := 0
    static _waTop := 0
    static _W := 0
    static _H := 0
    static _dpi := 1.0
    static _cell := 28
    static _cols := 40
    static _rows := 24
    static _gridOffX := 0
    static _gridOffY := 0
    static _sbColsHalf := 10
    static _sbSafeRows := 2

    ; Game Entities & Interpolation Snapshots
    static _snake := []          ; Array of { col, row } where [1] is Head
    static _prevSnake := []      ; Snapshot right before latest logical step
    static _morphSeeds := []     ; Array of { x, y, w, h, colorHex, targetCol, targetRow }
    static _dir := { x: -1, y: 0 }
    static _crashDir := { x: 0, y: 0 }
    static _dirQueue := []
    static _growPending := 0
    static _stepGrew := false
    static _food := ""           ; { col, row, kind, bornUs, ttlMs, pts }
    static _eatEffects := []     ; Shrinking absorb visuals { col, row, kind, bornUs }
    static _score := 0
    static _highScore := 0
    static _bestBeaten := false
    static _eatenCount := 0
    static _edgeWrap := false
    static _deathReason := ""
    static _popups := []         ; Floating "+10" / "+30" HUD-style tags

    ; High-Precision Timing & Pause/Resume Restoration
    static _qpcFreq := 0
    static _stepMs := 132
    static _morphDurationMs := 360
    static _morphStartUs := 0.0
    static _stepStartUs := 0.0
    static _frozenInterp := 0.0
    static _mmTimerActive := false
    static _tickTimerFn := ""
    static _boundHotkeys := []
    static _gpLastBtnMask := 0
    static _gpLastDirKey := ""
    static _gpDllName := ""
    static _gpDllChecked := false
    static _gpBuf := Buffer(16, 0)
    static _cfg := ""
    static _state := ""
    static _headless := false

    ; Persistent Zero-Alloc GDI+ Layered Canvas + Scratch Tube Buffer
    static _gui := ""
    static _hdcMem := 0
    static _hbm := 0
    static _obm := 0
    static _pBits := 0
    static _pGraphics := 0
    static _pSnakeBmp := 0
    static _pSnakeGfx := 0
    static _pImgAttr := 0
    static _snakeColorMat := Buffer(100, 0)
    static _prevDirtyRect := ""
    static _ptWin := Buffer(8, 0)
    static _szWin := Buffer(8, 0)
    static _ptSrc := Buffer(8, 0)
    static _blend := Buffer(4, 0)

    static Toggle(cfg, state) {
        if (this.IsActive)
            this.Stop()
        else
            this.Start(cfg, state)
    }

    static Start(cfg, state, headless := false) {
        if (this.IsActive)
            return false
        if (!IsObject(cfg) || !IsObject(state))
            return false

        Gdip.Startup()
        this._InitClock()
        tickUs := this._NowUs()

        this._cfg := cfg
        this._state := state
        this._headless := headless
        this._highScore := this._LoadHighScore(cfg)
        this._bestBeaten := false
        this._score := 0
        this._eatenCount := 0
        this._deathReason := ""
        this._crashDir := { x: 0, y: 0 }
        this._growPending := 0
        this._stepGrew := false
        this._dirQueue := []
        this._eatEffects := []
        this._popups := []
        this._stepMs := 132
        this._frozenInterp := 0.0

        this._ResolveMonitorWorkArea(state)
        this._ComputeGrid()

        this.IsActive := true
        this._PauseLiveHudsAndTelemetry(cfg, state)

        this._CaptureMorphSeedsAndSpawnSnake(cfg, state)
        this._prevSnake := this._CloneSnake(this._snake)
        this._SpawnFood("normal", tickUs)

        this.Phase := headless ? "playing" : "morph"
        this._morphStartUs := tickUs
        this._stepStartUs := tickUs

        if (!headless) {
            if (!this._InitCanvas()) {
                this.Stop()
                return false
            }
            if (!this._mmTimerActive) {
                try {
                    DllCall("winmm\timeBeginPeriod", "UInt", 1, "UInt")
                    this._mmTimerActive := true
                }
            }
            this._BindGameHotkeys()
            this._RenderFrame(tickUs)
            this._tickTimerFn := ObjBindMethod(this, "_FrameTick")
            SetTimer(this._tickTimerFn, 16)
        }
        return true
    }

    static Stop() {
        if (!this.IsActive && !IsObject(this._gui))
            return

        if (this._tickTimerFn) {
            try SetTimer(this._tickTimerFn, 0)
            this._tickTimerFn := ""
        }
        if (this._mmTimerActive) {
            try DllCall("winmm\timeEndPeriod", "UInt", 1, "UInt")
            this._mmTimerActive := false
        }
        this._UnbindGameHotkeys()
        this._DestroyCanvas()

        this.IsActive := false
        this.Phase := "idle"
        this._snake := []
        this._prevSnake := []
        this._morphSeeds := []
        this._dirQueue := []
        this._eatEffects := []
        this._popups := []
        this._food := ""
        this._crashDir := { x: 0, y: 0 }
        this._gpLastBtnMask := 0
        this._gpLastDirKey := ""

        if (IsObject(this._cfg) && IsObject(this._state)) {
            try this._RestoreLiveHudsAndTelemetry(this._cfg, this._state)
        }
        this._cfg := ""
        this._state := ""
        this._headless := false
    }

    static Restart() {
        if (!this.IsActive || !IsObject(this._cfg) || !IsObject(this._state))
            return
        tickUs := this._NowUs()
        this._bestBeaten := false
        this._score := 0
        this._eatenCount := 0
        this._deathReason := ""
        this._crashDir := { x: 0, y: 0 }
        this._growPending := 0
        this._stepGrew := false
        this._dirQueue := []
        this._eatEffects := []
        this._popups := []
        this._stepMs := 132
        this._frozenInterp := 0.0
        this._CaptureMorphSeedsAndSpawnSnake(this._cfg, this._state)
        this._prevSnake := this._CloneSnake(this._snake)
        this._SpawnFood("normal", tickUs)
        this.Phase := this._headless ? "playing" : "morph"
        this._morphStartUs := tickUs
        this._stepStartUs := tickUs
        if (!this._headless)
            this._RenderFrame(tickUs)
    }

    static TogglePause() {
        if (!this.IsActive)
            return
        tickUs := this._NowUs()
        if (this.Phase = "playing") {
            stepUs := this._stepMs * 1000.0
            this._frozenInterp := Min(1.0, Max(0.0, (tickUs - this._stepStartUs) / stepUs))
            this.Phase := "paused"
            if (!this._headless)
                this._RenderFrame(tickUs)
        } else if (this.Phase = "paused") {
            this.Phase := "playing"
            stepUs := this._stepMs * 1000.0
            this._stepStartUs := tickUs - (this._frozenInterp * stepUs)
            if (!this._headless)
                this._RenderFrame(tickUs)
        } else if (this.Phase = "gameover") {
            this.Restart()
        }
    }

    static ToggleEdgeMode() {
        if (!this.IsActive)
            return
        this._edgeWrap := !this._edgeWrap
        if (!this._headless)
            this._RenderFrame()
    }

    static QueueDirection(dx, dy) {
        if (!this.IsActive || (this.Phase != "playing" && this.Phase != "morph"))
            return false
        if (Abs(dx) + Abs(dy) != 1)
            return false

        refDir := (this._dirQueue.Length > 0) ? this._dirQueue[this._dirQueue.Length] : this._dir
        if ((dx == refDir.x && dy == refDir.y) || (dx == -refDir.x && dy == -refDir.y))
            return false
        if (this._dirQueue.Length >= 2)
            return false

        this._dirQueue.Push({ x: dx, y: dy })
        return true
    }

    static StepSimulation(nowUs := -1) {
        if (!this.IsActive || this.Phase != "playing")
            return
        if (nowUs < 0)
            nowUs := this._NowUs()

        if (this._dirQueue.Length > 0)
            this._dir := this._dirQueue.RemoveAt(1)

        head := this._snake[1]
        nextCol := head.col + this._dir.x
        nextRow := head.row + this._dir.y

        ; Perimeter collision or toroidal screen wrap
        if (nextCol < 0 || nextCol >= this._cols || nextRow < 0 || nextRow >= this._rows) {
            if (this._edgeWrap) {
                nextCol := Mod(nextCol + this._cols, this._cols)
                nextRow := Mod(nextRow + this._rows, this._rows)
            } else {
                this._TriggerGameOver("wall", nowUs)
                return
            }
        }

        ; Expire timed bonus fruit cleanly
        if (IsObject(this._food) && this._food.ttlMs > 0 && ((nowUs - this._food.bornUs) >= (this._food.ttlMs * 1000.0)))
            this._SpawnFood("normal", nowUs)

        willEat := IsObject(this._food) && (nextCol == this._food.col && nextRow == this._food.row)

        ; Self-collision check (the tail tip cell vacates cleanly if not growing this tick)
        checkLimit := (this._growPending == 0 && !willEat) ? (this._snake.Length - 1) : this._snake.Length
        Loop checkLimit {
            seg := this._snake[A_Index]
            if (seg.col == nextCol && seg.row == nextRow) {
                this._TriggerGameOver("self", nowUs)
                return
            }
        }

        ; Capture exact pre-step snapshot so continuous 60fps rail interpolation glides smoothly
        this._prevSnake := this._CloneSnake(this._snake)

        nextKind := "normal"
        if (willEat) {
            this._score += this._food.pts
            this._eatenCount += 1
            growth := (this._food.kind = "bonus") ? 2 : 1
            this._growPending += growth
            if (this._score > this._highScore) {
                this._highScore := this._score
                this._bestBeaten := true
                this._SaveHighScore(this._cfg, this._highScore)
            }

            popX := this._gridOffX + (nextCol + 0.5) * this._cell
            popY := this._gridOffY + (nextRow + 0.5) * this._cell
            eatenKind := this._food.kind
            this._popups.Push({ x: popX, y: popY - 6, text: "+" this._food.pts, kind: eatenKind, bornUs: nowUs })
            this._eatEffects.Push({ col: nextCol, row: nextRow, kind: eatenKind, bornUs: nowUs })

            if (IsObject(this._cfg) && this._cfg.HasOwnProp("EnableAudioCue") && this._cfg.EnableAudioCue)
                try PlayMuteAudioCue(false)

            this._stepMs := Max(68, 132 - Min(64, this._eatenCount * 3))
            nextKind := (Mod(this._eatenCount, 5) == 0) ? "bonus" : "normal"
            this._food := ""
        }

        newHead := { col: nextCol, row: nextRow }
        this._snake.InsertAt(1, newHead)

        if (this._growPending > 0) {
            this._growPending -= 1
            this._stepGrew := true
        } else {
            this._snake.Pop()
            this._stepGrew := false
        }

        if (willEat)
            this._SpawnFood(nextKind, nowUs)
    }

    static _TriggerGameOver(reason, nowUs) {
        this.Phase := "gameover"
        this._deathReason := reason
        this._crashDir := { x: this._dir.x, y: this._dir.y }
        this._prevSnake := this._CloneSnake(this._snake)
        this._stepGrew := false
        this._frozenInterp := 0.34 ; Nudge nose gently right against impacted wall or body edge
        if (IsObject(this._cfg) && this._cfg.HasOwnProp("EnableAudioCue") && this._cfg.EnableAudioCue)
            try PlayMuteAudioCue(true)
    }

    static _FrameTick() {
        if (!this.IsActive)
            return

        tickUs := this._NowUs()
        if (!this._headless)
            this._PollGamepadInput()
        if (this.Phase = "morph") {
            if ((tickUs - this._morphStartUs) >= (this._morphDurationMs * 1000.0)) {
                this.Phase := "playing"
                this._stepStartUs := tickUs
                this.StepSimulation(tickUs)
            }
            this._RenderFrame(tickUs)
            return
        }

        if (this.Phase = "playing") {
            stepUs := this._stepMs * 1000.0
            elapsedUs := tickUs - this._stepStartUs
            if (elapsedUs >= stepUs) {
                ; Advance step timer cleanly without accumulating runaway catch-up spirals
                stepsDue := Floor(elapsedUs / stepUs)
                if (stepsDue > 2) {
                    this._stepStartUs := tickUs
                    stepsDue := 1
                } else {
                    this._stepStartUs += stepsDue * stepUs
                }
                Loop stepsDue {
                    if (this.Phase != "playing")
                        break
                    this.StepSimulation(tickUs)
                }
            }
            this._RenderFrame(tickUs)
            return
        }

        ; Minimalist food pulse & popup fade still animate smoothly while paused? Stay calm on paused; finish popups on gameover
        if (this.Phase = "gameover" && (this._popups.Length > 0 || this._eatEffects.Length > 0))
            this._RenderFrame(tickUs)
    }

    ; ==========================================================================
    ; HIGH-PRECISION CLOCK & GRID SETUP
    ; ==========================================================================

    static _InitClock() {
        if (!this._qpcFreq) {
            freq := 0
            DllCall("QueryPerformanceFrequency", "Int64*", &freq)
            this._qpcFreq := (freq > 0) ? Float(freq) : 10000000.0
        }
    }

    static _NowUs() {
        if (!this._qpcFreq)
            this._InitClock()
        cnt := 0
        DllCall("QueryPerformanceCounter", "Int64*", &cnt)
        return (Float(cnt) * 1000000.0) / this._qpcFreq
    }

    static _CloneSnake(src) {
        out := []
        for seg in src
            out.Push({ col: seg.col, row: seg.row })
        return out
    }

    static _ResolveMonitorWorkArea(state) {
        ptX := IsObject(state) && state.HasOwnProp("savedX") ? state.savedX + 40 : 100
        ptY := IsObject(state) && state.HasOwnProp("savedY") ? state.savedY + 20 : 100
        monCount := MonitorGetCount()
        targetMon := 1
        Loop monCount {
            MonitorGetWorkArea(A_Index, &l, &t, &r, &b)
            if (ptX >= l && ptX <= r && ptY >= t && ptY <= b) {
                targetMon := A_Index
                break
            }
        }
        MonitorGetWorkArea(targetMon, &wl, &wt, &wr, &wb)
        this._waLeft := wl
        this._waTop := wt
        this._W := Max(640, wr - wl)
        this._H := Max(480, wb - wt)
        this._dpi := A_ScreenDPI / 96.0
    }

    static _ComputeGrid() {
        hudScale := (IsObject(this._cfg) && this._cfg.HasOwnProp("IndicatorScale")) ? Float(this._cfg.IndicatorScale) : 1.0
        scaleMod := Max(0.85, Min(1.30, 1.0 + (hudScale - 1.0) * 0.12))
        this._cell := Max(22, Round(28 * this._dpi * scaleMod))
        this._cols := Max(16, Floor((this._W - Round(16 * this._dpi)) / this._cell))
        this._rows := Max(12, Floor((this._H - Round(16 * this._dpi)) / this._cell))
        this._gridOffX := Floor((this._W - this._cols * this._cell) / 2)
        this._gridOffY := Floor((this._H - this._rows * this._cell) / 2)
        sbW := Min(Round(616 * this._dpi), this._W - 40)
        this._sbColsHalf := Max(4, Ceil((sbW / 2) / this._cell) + 1)
        this._sbSafeRows := Max(2, Ceil(Round(58 * this._dpi) / this._cell))
    }

    static _GetHudStyle() {
        cfg := this._cfg
        pal := this._GetActivePalette()
        isDark := IsSet(Theme) ? Theme.IsDarkMode() : true
        opacity := (IsObject(cfg) && cfg.HasOwnProp("OpacityLevel")) ? Max(72, Min(255, Integer(cfg.OpacityLevel))) : 220
        sleek := (IsObject(cfg) && cfg.HasOwnProp("SleekCorners")) ? !!cfg.SleekCorners : false
        mono := (IsObject(cfg) && cfg.HasOwnProp("MonoIcon")) ? !!cfg.MonoIcon : false
        return { pal: pal, isDark: isDark, opacity: opacity, sleek: sleek, mono: mono }
    }

    static _GetActivePalette() {
        palName := (IsObject(this._cfg) && this._cfg.HasOwnProp("HudColorPreset")) ? this._cfg.HudColorPreset : "Standard"
        return UIConstants.GetColorPalette(palName)
    }

    static _ResolveSnakeColors(snakePal) {
        style := this._GetHudStyle()
        isStealth := (InStr(StrLower(snakePal.live), "0f2e22") || (IsObject(this._cfg) && this._cfg.HasOwnProp("HudColorPreset") && NormalizeHudColorPreset(this._cfg.HudColorPreset) = "OLED Stealth"))
        if (this.Phase = "gameover") {
            fillHex := snakePal.muted
            rimHex := isStealth ? snakePal.iconMuted : this._LightenHex(snakePal.muted, 0.22)
            eyeColorHex := this._PickBadgeContentHex(fillHex, snakePal.iconMuted, (isStealth || style.mono), style.isDark, style.opacity)
        } else {
            fillHex := snakePal.live
            rimHex := isStealth ? snakePal.iconLive : this._LightenHex(snakePal.live, 0.20)
            eyeColorHex := this._PickBadgeContentHex(fillHex, snakePal.iconLive, (isStealth || style.mono), style.isDark, style.opacity)
        }
        return { fillHex: fillHex, rimHex: rimHex, eyeColorHex: eyeColorHex }
    }

    static _HexLuminance(hexStr) {
        h := RegExReplace(Trim(String(hexStr)), "^(#|0x)", "")
        if (StrLen(h) != 6)
            return 0.5
        r := Integer("0x" SubStr(h, 1, 2)) / 255.0
        g := Integer("0x" SubStr(h, 3, 2)) / 255.0
        b := Integer("0x" SubStr(h, 5, 2)) / 255.0
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    static _PickBadgeContentHex(fillHex, monoHex, useMono, isDark, alpha := 220) {
        h := RegExReplace(Trim(String(fillHex)), "^(#|0x)", "")
        if (StrLen(h) != 6)
            return "FFFFFF"
        a := Max(0.25, Min(1.0, Float(alpha) / 255.0))
        bgR := isDark ? 44.0 : 255.0
        bgG := isDark ? 44.0 : 255.0
        bgB := isDark ? 44.0 : 255.0
        effR := Integer("0x" SubStr(h, 1, 2)) * a + bgR * (1.0 - a)
        effG := Integer("0x" SubStr(h, 3, 2)) * a + bgG * (1.0 - a)
        effB := Integer("0x" SubStr(h, 5, 2)) * a + bgB * (1.0 - a)
        lumBg := (0.2126 * effR + 0.7152 * effG + 0.0722 * effB) / 255.0

        if (useMono) {
            lumMono := this._HexLuminance(monoHex)
            ratio := (Max(lumBg, lumMono) + 0.05) / (Min(lumBg, lumMono) + 0.05)
            if (ratio >= 2.6)
                return monoHex
        }
        return (lumBg > 0.68) ? "111827" : "FFFFFF"
    }

    static _LightenHex(hexStr, amount := 0.2) {
        h := RegExReplace(Trim(String(hexStr)), "^(#|0x)", "")
        if (StrLen(h) != 6)
            return "FFFFFF"
        r := Integer("0x" SubStr(h, 1, 2))
        g := Integer("0x" SubStr(h, 3, 2))
        b := Integer("0x" SubStr(h, 5, 2))
        nr := Min(255, Round(r + (255 - r) * amount))
        ng := Min(255, Round(g + (255 - g) * amount))
        nb := Min(255, Round(b + (255 - b) * amount))
        return Format("{:02X}{:02X}{:02X}", nr, ng, nb)
    }

    static _CaptureMorphSeedsAndSpawnSnake(cfg, state) {
        snakePal := this._GetActivePalette()
        seeds := []

        anchorX := (IsObject(state) && state.HasOwnProp("savedX") && IsInteger(state.savedX)) ? state.savedX : (this._waLeft + this._W - 200)
        anchorY := (IsObject(state) && state.HasOwnProp("savedY") && IsInteger(state.savedY)) ? state.savedY : (this._waTop + this._H - 80)
        hasFullHostHud := IsSet(ComputeHudLayout) && IsObject(state) && state.HasOwnProp("RecGui") && IsObject(cfg) && cfg.HasOwnProp("ShowExtraHuds")
        if (hasFullHostHud) {
            pos := ComputeHudLayout(state, anchorX, anchorY)
        } else {
            micW := (IsObject(state) && state.HasOwnProp("baseWidth") && state.baseWidth > 0) ? state.baseWidth : 80
            micH := (IsObject(state) && state.HasOwnProp("baseHeight") && state.baseHeight > 0) ? state.baseHeight : 40
            pos := { micX: anchorX, micY: anchorY, micW: micW, micH: micH }
        }

        isMutedFlag := (IsObject(state) && state.HasOwnProp("isMuted")) ? !!state.isMuted : false
        ; Capture real visible HUD pills so the morph visibly collapses HUD tiles into the matte snake ribbon
        seeds.Push({ x: pos.micX - this._waLeft, y: pos.micY - this._waTop, w: pos.micW, h: pos.micH, colorHex: (isMutedFlag ? snakePal.muted : snakePal.live) })
        if (hasFullHostHud && cfg.ShowExtraHuds && (cfg.EnableWS || cfg.EnableZoom)) {
            seeds.Push({ x: pos.recX - this._waLeft, y: pos.recY - this._waTop, w: pos.recW, h: pos.recH, colorHex: snakePal.recActive })
            seeds.Push({ x: pos.chatX - this._waLeft, y: pos.chatY - this._waTop, w: pos.chatW, h: pos.chatH, colorHex: snakePal.chatAlert })
        }
        if (hasFullHostHud && cfg.ShowExtraHuds && cfg.EnableWS) {
            seeds.Push({ x: pos.studioX - this._waLeft, y: pos.studioY - this._waTop, w: pos.studioW, h: pos.studioH, colorHex: snakePal.studioOn })
            seeds.Push({ x: pos.sceneX - this._waLeft, y: pos.sceneY - this._waTop, w: pos.sceneW, h: pos.sceneH, colorHex: snakePal.scene })
            if (!cfg.HasOwnProp("ShowStreamHud") || cfg.ShowStreamHud) {
                seeds.Push({ x: pos.streamX - this._waLeft, y: pos.streamY - this._waTop, w: pos.streamW, h: pos.streamH, colorHex: snakePal.streamLive })
            }
        }

        while (seeds.Length < 5)
            seeds.Push({ x: pos.micX - this._waLeft, y: pos.micY - this._waTop, w: pos.micW, h: pos.micH, colorHex: snakePal.live })

        initLen := seeds.Length
        rawCol := Floor(((pos.micX - this._waLeft + pos.micW / 2) - this._gridOffX) / this._cell)
        rawRow := Floor(((pos.micY - this._waTop + pos.micH / 2) - this._gridOffY) / this._cell)

        startCol := Max(initLen + 1, Min(this._cols - initLen - 2, rawCol))
        startRow := Max(this._sbSafeRows + 1, Min(this._rows - 3, rawRow))
        dirX := (startCol >= (this._cols // 2)) ? -1 : 1
        this._dir := { x: dirX, y: 0 }

        snake := []
        Loop initLen {
            idx := A_Index
            segCol := startCol - (idx - 1) * dirX
            seeds[idx].targetCol := segCol
            seeds[idx].targetRow := startRow
            snake.Push({ col: segCol, row: startRow })
        }
        this._morphSeeds := seeds
        this._snake := snake
    }

    static _SpawnFood(kind := "normal", nowUs := -1) {
        if (nowUs < 0)
            nowUs := this._NowUs()

        occupied := Map()
        for seg in this._snake
            occupied[seg.col "," seg.row] := true

        midCol := this._cols // 2
        candidates := []
        cIdx := 1
        while (cIdx <= this._cols - 2) {
            rIdx := 1
            while (rIdx <= this._rows - 2) {
                if (!(rIdx <= this._sbSafeRows && Abs(cIdx - midCol) <= this._sbColsHalf)) {
                    if (!occupied.Has(cIdx "," rIdx))
                        candidates.Push({ col: cIdx, row: rIdx })
                }
                rIdx += 1
            }
            cIdx += 1
        }

        if (candidates.Length == 0) {
            cIdx := 0
            while (cIdx < this._cols) {
                rIdx := 0
                while (rIdx < this._rows) {
                    if (!occupied.Has(cIdx "," rIdx))
                        candidates.Push({ col: cIdx, row: rIdx })
                    rIdx += 1
                }
                cIdx += 1
            }
        }

        if (candidates.Length == 0)
            return

        pick := candidates[Random(1, candidates.Length)]
        this._food := {
            col: pick.col,
            row: pick.row,
            kind: kind,
            bornUs: nowUs,
            ttlMs: (kind = "bonus" ? 9000 : 0),
            pts: (kind = "bonus" ? 30 : 10)
        }
    }

    ; ==========================================================================
    ; LIVE HUD & BLOCKING NETWORK/UIA TIMER ISOLATION (ELIMINATES PERIODIC STALLS)
    ; ==========================================================================

    static _PauseLiveHudsAndTelemetry(cfg, state) {
        ; Pause all UI timers
        if (state.HasOwnProp("breathTimerFn") && state.breathTimerFn)
            SetTimer(state.breathTimerFn, 0)
        if (state.HasOwnProp("sceneMarqueeTimerFn") && state.sceneMarqueeTimerFn)
            SetTimer(state.sceneMarqueeTimerFn, 0)
        if (IsSet(UpdateVoiceMeterTimer) && IsObject(cfg) && cfg.HasOwnProp("AlertVoiceWhileMuted"))
            UpdateVoiceMeterTimer(cfg, state)
        if (IsSet(UpdateAutoDodgeTimer))
            UpdateAutoDodgeTimer(cfg, state)

        ; Pause synchronous WinHTTP WebSocket reconnects & UIA polling so main AHK thread stays 100% responsive
        for propName in ["obsTimerFn", "relayTimerFn", "zoomTimerFn", "streamTimerFn", "recTimerFn", "reconnectTimerFn", "heartbeatTimerFn"] {
            if (state.HasOwnProp(propName) && state.%propName%)
                SetTimer(state.%propName%, 0)
        }

        if (IsSet(GetHudGuiList) && state.HasOwnProp("RecGui")) {
            for g in GetHudGuiList(state)
                try g.Hide()
        } else if (state.HasOwnProp("MicGui") && IsObject(state.MicGui)) {
            try state.MicGui.Hide()
        }
    }

    static _RestoreLiveHudsAndTelemetry(cfg, state) {
        isPrimary := state.HasOwnProp("RecGui")
        if (isPrimary) {
            if (cfg.ShowIndicator && IsSet(RefreshHudAppearance))
                RefreshHudAppearance(cfg, state)
            else if (IsSet(UpdateHudVisibility))
                UpdateHudVisibility(cfg, state)
        } else {
            if (state.HasOwnProp("refreshHudFn") && IsObject(state.refreshHudFn)) {
                try state.refreshHudFn.Call()
            } else if (IsObject(cfg) && cfg.ShowIndicator && state.HasOwnProp("MicGui") && IsObject(state.MicGui)) {
                try ApplyMicAppearance(cfg, state)
                try state.MicGui.Show("NoActivate")
            }
        }
        if (IsSet(UpdateAutoDodgeTimer))
            UpdateAutoDodgeTimer(cfg, state)
        if (IsSet(UpdateVoiceMeterTimer) && IsObject(cfg) && cfg.HasOwnProp("AlertVoiceWhileMuted"))
            UpdateVoiceMeterTimer(cfg, state)

        if (isPrimary) {
            if (cfg.EnableWS && !state.obsConnected && state.HasOwnProp("obsTimerFn") && state.obsTimerFn)
                SetTimer(state.obsTimerFn, -150)
            if (cfg.EnableWS && state.obsConnected && state.streamState != 0 && state.HasOwnProp("streamTimerFn") && state.streamTimerFn)
                SetTimer(state.streamTimerFn, UIConstants.STREAM_POLL_INTERVAL_MS)
            if (state.recState == 1 && state.HasOwnProp("recTimerFn") && state.recTimerFn)
                SetTimer(state.recTimerFn, 1000)
            if (IsSet(UpdateZoomMonitorTimer))
                try UpdateZoomMonitorTimer(cfg, state)
            if (IsSet(UpdateHostInternetRelay))
                try UpdateHostInternetRelay(cfg, state)
        } else {
            if (state.HasOwnProp("obsConnected") && !state.obsConnected && state.HasOwnProp("reconnectTimerFn") && state.reconnectTimerFn)
                SetTimer(state.reconnectTimerFn, -150)
            else if (state.HasOwnProp("obsConnected") && state.obsConnected && state.HasOwnProp("heartbeatTimerFn") && state.heartbeatTimerFn) {
                hbMs := (IsObject(cfg) && cfg.HasOwnProp("HeartbeatSeconds") && cfg.HeartbeatSeconds >= 10) ? cfg.HeartbeatSeconds * 1000 : 30000
                SetTimer(state.heartbeatTimerFn, hbMs)
            }
        }
    }

    static DecodeXInputGamepadState(buttons, thumbX, thumbY, deadzone := 12000) {
        dirX := 0, dirY := 0
        if (buttons & 0x0001)
            dirY := -1
        else if (buttons & 0x0002)
            dirY := 1
        else if (buttons & 0x0004)
            dirX := -1
        else if (buttons & 0x0008)
            dirX := 1
        else if (Abs(thumbX) >= deadzone || Abs(thumbY) >= deadzone) {
            if (Abs(thumbX) >= Abs(thumbY))
                dirX := (thumbX > 0) ? 1 : -1
            else
                dirY := (thumbY > 0) ? -1 : 1
        }
        return {
            dirX: dirX,
            dirY: dirY,
            pausePressed: !!(buttons & 0x1010),
            edgePressed: !!(buttons & 0xC000),
            exitPressed: !!(buttons & 0x2020)
        }
    }

    static DecodeDirectInputPov(povVal) {
        if (!IsInteger(povVal) || povVal < 0 || povVal >= 65535)
            return { x: 0, y: 0 }
        deg := Integer(povVal)
        if (deg <= 4500 || deg >= 31500)
            return { x: 0, y: -1 }
        if (deg <= 13500)
            return { x: 1, y: 0 }
        if (deg <= 22500)
            return { x: 0, y: 1 }
        return { x: -1, y: 0 }
    }

    static _EnsureXInputDll() {
        if (this._gpDllChecked)
            return this._gpDllName
        this._gpDllChecked := true
        for dllName in ["xinput1_4.dll", "xinput9_1_0.dll", "xinput1_3.dll"] {
            hMod := DllCall("LoadLibrary", "Str", dllName, "Ptr")
            if (hMod) {
                this._gpDllName := dllName
                return dllName
            }
        }
        return ""
    }

    static _PollGamepadInput() {
        if (!this.IsActive)
            return
        decoded := ""
        dllName := this._EnsureXInputDll()
        if (dllName != "") {
            Loop 4 {
                idx := A_Index - 1
                res := DllCall(dllName "\XInputGetState", "UInt", idx, "Ptr", this._gpBuf.Ptr, "UInt")
                if (res == 0) {
                    buttons := NumGet(this._gpBuf, 4, "UShort")
                    thumbX := NumGet(this._gpBuf, 8, "Short")
                    thumbY := NumGet(this._gpBuf, 10, "Short")
                    decoded := this.DecodeXInputGamepadState(buttons, thumbX, thumbY)
                    break
                }
            }
        }
        if (!IsObject(decoded)) {
            try {
                pov := GetKeyState("1JoyPOV")
                if (pov != "" && pov >= -1) {
                    dPov := this.DecodeDirectInputPov(Round(pov))
                    btnPause := GetKeyState("1Joy1") || GetKeyState("1Joy8")
                    btnEdge := GetKeyState("1Joy3") || GetKeyState("1Joy4")
                    btnExit := GetKeyState("1Joy2") || GetKeyState("1Joy7")
                    decoded := {
                        dirX: dPov.x,
                        dirY: dPov.y,
                        pausePressed: !!btnPause,
                        edgePressed: !!btnEdge,
                        exitPressed: !!btnExit
                    }
                }
            }
        }
        if (!IsObject(decoded))
            return
        this._ApplyGamepadInput(decoded)
    }

    static _ApplyGamepadInput(decoded) {
        if (decoded.dirX != 0 || decoded.dirY != 0) {
            dirKey := decoded.dirX "," decoded.dirY
            if (dirKey != this._gpLastDirKey) {
                this._gpLastDirKey := dirKey
                this.QueueDirection(decoded.dirX, decoded.dirY)
            }
        } else {
            this._gpLastDirKey := ""
        }

        curMask := (decoded.pausePressed ? 1 : 0) | (decoded.edgePressed ? 2 : 0) | (decoded.exitPressed ? 4 : 0)
        rising := curMask & ~this._gpLastBtnMask
        this._gpLastBtnMask := curMask

        if (rising & 1) {
            if (this.Phase = "gameover")
                this.Restart()
            else
                this.TogglePause()
        } else if (rising & 2) {
            this.ToggleEdgeMode()
        } else if (rising & 4) {
            this.Stop()
        }
    }

    static _BindGameHotkeys() {
        this._UnbindGameHotkeys()
        HotIf()
        bindings := [
            ["*Up",          (*) => this.QueueDirection(0, -1)],
            ["*Down",        (*) => this.QueueDirection(0, 1)],
            ["*Left",        (*) => this.QueueDirection(-1, 0)],
            ["*Right",       (*) => this.QueueDirection(1, 0)],
            ["*NumpadUp",    (*) => this.QueueDirection(0, -1)],
            ["*NumpadDown",  (*) => this.QueueDirection(0, 1)],
            ["*NumpadLeft",  (*) => this.QueueDirection(-1, 0)],
            ["*NumpadRight", (*) => this.QueueDirection(1, 0)],
            ["*Numpad8",     (*) => this.QueueDirection(0, -1)],
            ["*Numpad2",     (*) => this.QueueDirection(0, 1)],
            ["*Numpad4",     (*) => this.QueueDirection(-1, 0)],
            ["*Numpad6",     (*) => this.QueueDirection(1, 0)],
            ["w",            (*) => this.QueueDirection(0, -1)],
            ["+w",           (*) => this.QueueDirection(0, -1)],
            ["s",            (*) => this.QueueDirection(0, 1)],
            ["+s",           (*) => this.QueueDirection(0, 1)],
            ["a",            (*) => this.QueueDirection(-1, 0)],
            ["+a",           (*) => this.QueueDirection(-1, 0)],
            ["d",            (*) => this.QueueDirection(1, 0)],
            ["+d",           (*) => this.QueueDirection(1, 0)],
            ["p",            (*) => this.TogglePause()],
            ["+p",           (*) => this.TogglePause()],
            ["Space",        (*) => this.TogglePause()],
            ["e",            (*) => this.ToggleEdgeMode()],
            ["+e",           (*) => this.ToggleEdgeMode()],
            ["r",            (*) => (this.Phase = "gameover" ? this.Restart() : 0)],
            ["+r",           (*) => (this.Phase = "gameover" ? this.Restart() : 0)],
            ["Enter",        (*) => (this.Phase = "gameover" ? this.Restart() : 0)],
            ["NumpadEnter",  (*) => (this.Phase = "gameover" ? this.Restart() : 0)],
            ["Escape",       (*) => this.Stop()]
        ]
        for pair in bindings {
            try {
                Hotkey(pair[1], pair[2], "On")
                this._boundHotkeys.Push(pair[1])
            }
        }
    }

    static _UnbindGameHotkeys() {
        HotIf()
        for hkName in this._boundHotkeys {
            try Hotkey(hkName, "Off")
        }
        this._boundHotkeys := []
    }

    static _LoadHighScore(cfg) {
        if (!IsObject(cfg))
            return 0
        try return Max(0, Integer(cfg.Read("EasterEgg", "SnakeHighScore", "0")))
        catch
            return 0
    }

    static _SaveHighScore(cfg, scoreVal) {
        if (!IsObject(cfg))
            return
        try cfg.Write("EasterEgg", "SnakeHighScore", String(scoreVal))
    }

    ; ==========================================================================
    ; ZERO-ALLOCATION PERSISTENT GDI+ LAYERED CANVAS & MATTE-GLASS RENDERING
    ; ==========================================================================

    static _InitCanvas() {
        this._DestroyCanvas()
        this._gui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000 +E0x20 -DPIScale", "PresenterSync HUD Snake")
        this._gui.Show(Format("NoActivate x{} y{} w{} h{}", this._waLeft, this._waTop, this._W, this._H))

        bi := Buffer(40, 0)
        NumPut("UInt", 40, "Int", this._W, "Int", -this._H, "UShort", 1, "UShort", 32, bi, 0)
        hdcScreen := DllCall("GetDC", "Ptr", 0, "Ptr")
        this._hdcMem := DllCall("CreateCompatibleDC", "Ptr", hdcScreen, "Ptr")
        pBits := 0
        this._hbm := DllCall("CreateDIBSection", "Ptr", hdcScreen, "Ptr", bi, "UInt", 0, "Ptr*", &pBits, "Ptr", 0, "UInt", 0, "Ptr")
        DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdcScreen)

        if (!this._hdcMem || !this._hbm || !pBits) {
            this._DestroyCanvas()
            return false
        }
        this._pBits := pBits
        this._obm := DllCall("SelectObject", "Ptr", this._hdcMem, "Ptr", this._hbm, "Ptr")
        pGfx := 0
        DllCall("gdiplus\GdipCreateFromHDC", "Ptr", this._hdcMem, "Ptr*", &pGfx)
        if (!pGfx) {
            this._DestroyCanvas()
            return false
        }
        DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", pGfx, "Int", 4)
        DllCall("gdiplus\GdipSetTextRenderingHint", "Ptr", pGfx, "Int", 4)
        this._pGraphics := pGfx

        ; Persistent offscreen ARGB scratch layer for seamless single-silhouette snake tube rendering
        pSBmp := 0
        DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", this._W, "Int", this._H, "Int", 0, "Int", 0x26200A, "Ptr", 0, "Ptr*", &pSBmp)
        if (pSBmp) {
            this._pSnakeBmp := pSBmp
            pSGfx := 0
            DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", pSBmp, "Ptr*", &pSGfx)
            if (pSGfx) {
                DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", pSGfx, "Int", 4)
                DllCall("gdiplus\GdipGraphicsClear", "Ptr", pSGfx, "UInt", 0)
                this._pSnakeGfx := pSGfx
            }
        }
        pAttr := 0
        DllCall("gdiplus\GdipCreateImageAttributes", "Ptr*", &pAttr)
        this._pImgAttr := pAttr
        this._prevDirtyRect := ""

        DllCall("ntdll\RtlZeroMemory", "Ptr", this._snakeColorMat.Ptr, "Ptr", 100)
        NumPut("Float", 1.0, this._snakeColorMat, 0)
        NumPut("Float", 1.0, this._snakeColorMat, 24)
        NumPut("Float", 1.0, this._snakeColorMat, 48)
        NumPut("Float", 1.0, this._snakeColorMat, 72)
        NumPut("Float", 1.0, this._snakeColorMat, 96)

        NumPut("Int", this._waLeft, "Int", this._waTop, this._ptWin, 0)
        NumPut("Int", this._W, "Int", this._H, this._szWin, 0)
        NumPut("Int64", 0, this._ptSrc, 0)
        NumPut("UInt", 0x01FF0000, this._blend, 0)
        return true
    }

    static _DestroyCanvas() {
        if (this._pImgAttr) {
            DllCall("gdiplus\GdipDisposeImageAttributes", "Ptr", this._pImgAttr)
            this._pImgAttr := 0
        }
        if (this._pSnakeGfx) {
            DllCall("gdiplus\GdipDeleteGraphics", "Ptr", this._pSnakeGfx)
            this._pSnakeGfx := 0
        }
        if (this._pSnakeBmp) {
            DllCall("gdiplus\GdipDisposeImage", "Ptr", this._pSnakeBmp)
            this._pSnakeBmp := 0
        }
        this._prevDirtyRect := ""
        if (this._pGraphics) {
            DllCall("gdiplus\GdipDeleteGraphics", "Ptr", this._pGraphics)
            this._pGraphics := 0
        }
        if (this._hdcMem && this._obm) {
            DllCall("SelectObject", "Ptr", this._hdcMem, "Ptr", this._obm)
            this._obm := 0
        }
        if (this._hbm) {
            DllCall("DeleteObject", "Ptr", this._hbm)
            this._hbm := 0
        }
        this._pBits := 0
        if (this._hdcMem) {
            DllCall("DeleteDC", "Ptr", this._hdcMem)
            this._hdcMem := 0
        }
        if (IsObject(this._gui)) {
            try this._gui.Destroy()
            this._gui := ""
        }
    }

    static _FillRoundedBox(pGfx, x, y, w, h, radius, fillArgb, borderArgb := 0, borderW := 1.4) {
        pPath := Gdip.CreateRoundedRectPath(x, y, w, h, radius)
        if (!pPath)
            return
        if ((fillArgb >>> 24) > 0) {
            pBrush := 0
            DllCall("gdiplus\GdipCreateSolidFill", "UInt", fillArgb, "Ptr*", &pBrush)
            if (pBrush) {
                DllCall("gdiplus\GdipFillPath", "Ptr", pGfx, "Ptr", pBrush, "Ptr", pPath)
                DllCall("gdiplus\GdipDeleteBrush", "Ptr", pBrush)
            }
        }
        if ((borderArgb >>> 24) > 0 && borderW > 0) {
            pPen := 0
            DllCall("gdiplus\GdipCreatePen1", "UInt", borderArgb, "Float", Float(borderW), "Int", 2, "Ptr*", &pPen)
            if (pPen) {
                DllCall("gdiplus\GdipDrawPath", "Ptr", pGfx, "Ptr", pPen, "Ptr", pPath)
                DllCall("gdiplus\GdipDeletePen", "Ptr", pPen)
            }
        }
        DllCall("gdiplus\GdipDeletePath", "Ptr", pPath)
    }

    static _RenderFrame(nowUs := -1) {
        if (!this._pGraphics || !this._pBits || !IsObject(this._gui))
            return
        if (nowUs < 0)
            nowUs := this._NowUs()

        pGfx := this._pGraphics
        snakePal := this._GetActivePalette()
        isDark := IsSet(Theme) ? Theme.IsDarkMode() : true

        DllCall("ntdll\RtlZeroMemory", "Ptr", this._pBits, "Ptr", this._W * this._H * 4)

        ; 1. Clean Minimalist Play-Area Perimeter Hints (solid for WALLS, dashed for WRAP)
        this._DrawEdgeHints(pGfx, snakePal, isDark)

        ; 2. Draw Matte-Glass HUD Squircle Fruits & Subtle Eat Absorb Effects
        if (this.Phase != "morph") {
            this._DrawEatEffects(pGfx, snakePal, nowUs)
            if (IsObject(this._food))
                this._DrawFood(pGfx, snakePal, isDark, nowUs)
        }

        ; 3. Draw Unified Seamless Matte-Glass Snake Ribbon (or Morphing Pills)
        if (this.Phase = "morph")
            this._DrawMorphTransition(pGfx, snakePal, nowUs)
        else
            this._DrawContinuousSnake(pGfx, snakePal, nowUs)

        ; 4. Draw Minimal Floating Eat Popups (+10 / +30)
        this._DrawPopups(pGfx, nowUs)

        ; 5. Draw Top-Center Matte Scoreboard Pill
        this._DrawScoreboard(pGfx, snakePal, isDark)

        ; 6. Draw Pause / Game Over Matte Pill Banner
        if (this.Phase = "paused" || this.Phase = "gameover")
            this._DrawStatusBanner(pGfx, snakePal, isDark)

        DllCall("UpdateLayeredWindow", "Ptr", this._gui.Hwnd, "Ptr", 0, "Ptr", this._ptWin, "Ptr", this._szWin, "Ptr", this._hdcMem, "Ptr", this._ptSrc, "UInt", 0, "Ptr", this._blend, "UInt", 2, "Int")
    }

    static _DrawEdgeHints(pGfx, snakePal, isDark) {
        gx := Float(this._gridOffX)
        gy := Float(this._gridOffY)
        gw := Float(this._cols * this._cell)
        gh := Float(this._rows * this._cell)
        style := this._GetHudStyle()
        rad := style.sleek ? Float(10.0 * this._dpi) : Float(6.0 * this._dpi)

        if (!this._edgeWrap) {
            ; Subtle matte-glass perimeter rail for WALLS mode (reads cleanly on both Light & Dark wallpapers without loud neon)
            outerGlowArgb := isDark ? 0x260F172A : 0x22FFFFFF
            wallLineArgb := Gdip.HexToArgb(isDark ? "CBD5E1" : "475569", 108)
            cornerArgb := Gdip.HexToArgb(isDark ? "E2E8F0" : "334155", 136)

            pOuter := 0
            DllCall("gdiplus\GdipCreatePen1", "UInt", outerGlowArgb, "Float", Float(4.0 * this._dpi), "Int", 2, "Ptr*", &pOuter)
            if (pOuter) {
                if (pRect := Gdip.CreateRoundedRectPath(gx + 0.5, gy + 0.5, gw - 1.0, gh - 1.0, rad)) {
                    DllCall("gdiplus\GdipDrawPath", "Ptr", pGfx, "Ptr", pOuter, "Ptr", pRect)
                    DllCall("gdiplus\GdipDeletePath", "Ptr", pRect)
                }
                DllCall("gdiplus\GdipDeletePen", "Ptr", pOuter)
            }

            pWallPen := 0
            DllCall("gdiplus\GdipCreatePen1", "UInt", wallLineArgb, "Float", Float(1.5 * this._dpi), "Int", 2, "Ptr*", &pWallPen)
            if (pWallPen) {
                if (pRect2 := Gdip.CreateRoundedRectPath(gx + 0.5, gy + 0.5, gw - 1.0, gh - 1.0, rad)) {
                    DllCall("gdiplus\GdipDrawPath", "Ptr", pGfx, "Ptr", pWallPen, "Ptr", pRect2)
                    DllCall("gdiplus\GdipDeletePath", "Ptr", pRect2)
                }
                DllCall("gdiplus\GdipDeletePen", "Ptr", pWallPen)
            }

            ; Delicate Fluent corner bracket ticks indicating active solid monitor perimeter
            tick := Float(16.0 * this._dpi)
            pTickPen := 0
            DllCall("gdiplus\GdipCreatePen1", "UInt", cornerArgb, "Float", Float(2.0 * this._dpi), "Int", 2, "Ptr*", &pTickPen)
            if (pTickPen) {
                DllCall("gdiplus\GdipSetPenStartCap", "Ptr", pTickPen, "Int", 2)
                DllCall("gdiplus\GdipSetPenEndCap", "Ptr", pTickPen, "Int", 2)
                DllCall("gdiplus\GdipDrawLine", "Ptr", pGfx, "Ptr", pTickPen, "Float", gx + 2, "Float", gy + tick, "Float", gx + 2, "Float", gy + 2)
                DllCall("gdiplus\GdipDrawLine", "Ptr", pGfx, "Ptr", pTickPen, "Float", gx + 2, "Float", gy + 2, "Float", gx + tick, "Float", gy + 2)
                DllCall("gdiplus\GdipDrawLine", "Ptr", pGfx, "Ptr", pTickPen, "Float", gx + gw - tick, "Float", gy + 2, "Float", gx + gw - 2, "Float", gy + 2)
                DllCall("gdiplus\GdipDrawLine", "Ptr", pGfx, "Ptr", pTickPen, "Float", gx + gw - 2, "Float", gy + 2, "Float", gx + gw - 2, "Float", gy + tick)
                DllCall("gdiplus\GdipDrawLine", "Ptr", pGfx, "Ptr", pTickPen, "Float", gx + 2, "Float", gy + gh - tick, "Float", gx + 2, "Float", gy + gh - 2)
                DllCall("gdiplus\GdipDrawLine", "Ptr", pGfx, "Ptr", pTickPen, "Float", gx + 2, "Float", gy + gh - 2, "Float", gx + tick, "Float", gy + gh - 2)
                DllCall("gdiplus\GdipDrawLine", "Ptr", pGfx, "Ptr", pTickPen, "Float", gx + gw - tick, "Float", gy + gh - 2, "Float", gx + gw - 2, "Float", gy + gh - 2)
                DllCall("gdiplus\GdipDrawLine", "Ptr", pGfx, "Ptr", pTickPen, "Float", gx + gw - 2, "Float", gy + gh - 2, "Float", gx + gw - 2, "Float", gy + gh - tick)
                DllCall("gdiplus\GdipDeletePen", "Ptr", pTickPen)
            }
            return
        }

        ; Open pass-through portal hint for WRAP mode
        accentHex := isDark ? "60CDFF" : "0067C0"
        fArgb := Gdip.HexToArgb(accentHex, 64)
        pFramePen := 0
        DllCall("gdiplus\GdipCreatePen1", "UInt", fArgb, "Float", Float(1.1 * this._dpi), "Int", 2, "Ptr*", &pFramePen)
        if (pFramePen) {
            DllCall("gdiplus\GdipSetPenDashStyle", "Ptr", pFramePen, "Int", 1)
            DllCall("gdiplus\GdipDrawRectangle", "Ptr", pGfx, "Ptr", pFramePen, "Float", gx + 0.5, "Float", gy + 0.5, "Float", gw - 1.0, "Float", gh - 1.0)
            DllCall("gdiplus\GdipDeletePen", "Ptr", pFramePen)
        }
    }

    static _DrawFood(pGfx, snakePal, isDark, nowUs) {
        f := this._food
        style := this._GetHudStyle()
        cellX := this._gridOffX + (f.col + 0.5) * this._cell
        cellY := this._gridOffY + (f.row + 0.5) * this._cell
        isBonus := (f.kind = "bonus")

        ; Minimal HUD pill proportions matching _GdipDrawMiniPill / RenderPill + user SleekCorners & Opacity
        ; Special bonus fruit renders 2x wider/taller (~4x area) so its timed reward stands out cleanly
        baseSz := Float(this._cell) * (isBonus ? 1.42 : 0.70)
        sz := baseSz
        foodX := cellX - sz / 2.0
        foodY := cellY - sz / 2.0
        radius := style.sleek ? (sz / 2.0) : Min((isBonus ? 13.0 : 7.5) * this._dpi, sz * 0.34)

        glassAlpha := style.opacity
        if (isBonus) {
            bodyHex := snakePal.recPaused
            rimHex := this._LightenHex(bodyHex, 0.25)
            pipHex := this._PickBadgeContentHex(bodyHex, snakePal.recIconPaused, style.mono, isDark, glassAlpha)
        } else {
            ; Harmonious matte HUD alert color matching active preset (e.g. Coral/Vermilion)
            bodyHex := (snakePal.muted != snakePal.live) ? snakePal.chatAlert : snakePal.muted
            if (StrLower(bodyHex) = StrLower(snakePal.live))
                bodyHex := snakePal.muted
            rimHex := this._LightenHex(bodyHex, 0.25)
            monoSrc := (StrLower(bodyHex) = StrLower(snakePal.chatAlert)) ? snakePal.chatIconAlert : snakePal.iconMuted
            pipHex := this._PickBadgeContentHex(bodyHex, monoSrc, style.mono, isDark, glassAlpha)
        }

        fillArgb := Gdip.HexToArgb(bodyHex, glassAlpha)
        brdArgb := Gdip.HexToArgb(rimHex, Min(255, glassAlpha + 30))
        pPath := Gdip.CreateRoundedRectPath(foodX, foodY, sz, sz, radius)
        if (!pPath)
            return

        if (isBonus) {
            ; Subtle matte outer halo ring to distinguish bonus fruit gently on busy slides/wallpapers
            haloPad := 2.4 * this._dpi
            haloRad := style.sleek ? ((sz + haloPad * 2.0) / 2.0) : (radius + haloPad * 0.6)
            if (pHaloPath := Gdip.CreateRoundedRectPath(foodX - haloPad, foodY - haloPad, sz + haloPad * 2.0, sz + haloPad * 2.0, haloRad)) {
                pHaloPen := 0
                DllCall("gdiplus\GdipCreatePen1", "UInt", Gdip.HexToArgb(rimHex, Max(75, Round(glassAlpha * 0.45))), "Float", Float(1.6 * this._dpi), "Int", 2, "Ptr*", &pHaloPen)
                if (pHaloPen) {
                    DllCall("gdiplus\GdipDrawPath", "Ptr", pGfx, "Ptr", pHaloPen, "Ptr", pHaloPath)
                    DllCall("gdiplus\GdipDeletePen", "Ptr", pHaloPen)
                }
                DllCall("gdiplus\GdipDeletePath", "Ptr", pHaloPath)
            }
        }

        pBrush := 0
        DllCall("gdiplus\GdipCreateSolidFill", "UInt", fillArgb, "Ptr*", &pBrush)
        if (pBrush) {
            DllCall("gdiplus\GdipFillPath", "Ptr", pGfx, "Ptr", pBrush, "Ptr", pPath)
            DllCall("gdiplus\GdipDeleteBrush", "Ptr", pBrush)
        }

        barH := isBonus ? Max(3.2, 4.4 * this._dpi) : 0.0
        if (isBonus && f.ttlMs > 0) {
            ; HUD-consistent bottom progress bar clipped inside the rounded pill (mirrors LIVE VU meter bar!)
            remFrac := Max(0.0, 1.0 - (nowUs - f.bornUs) / (Float(f.ttlMs) * 1000.0))
            if (remFrac > 0.01) {
                DllCall("gdiplus\GdipSetClipPath", "Ptr", pGfx, "Ptr", pPath, "Int", 0)
                pBar := 0
                DllCall("gdiplus\GdipCreateSolidFill", "UInt", 0xEBFFFFFF, "Ptr*", &pBar)
                if (pBar) {
                    DllCall("gdiplus\GdipFillRectangle", "Ptr", pGfx, "Ptr", pBar, "Float", Float(foodX + 1.0), "Float", Float(foodY + sz - barH - 0.5), "Float", Max(3.0, Float(sz - 2.0) * remFrac), "Float", Float(barH))
                    DllCall("gdiplus\GdipDeleteBrush", "Ptr", pBar)
                }
                DllCall("gdiplus\GdipResetClip", "Ptr", pGfx)
            }
        }

        pPen := 0
        DllCall("gdiplus\GdipCreatePen1", "UInt", brdArgb, "Float", Float((isBonus ? 1.8 : 1.4) * this._dpi), "Int", 2, "Ptr*", &pPen)
        if (pPen) {
            DllCall("gdiplus\GdipDrawPath", "Ptr", pGfx, "Ptr", pPen, "Ptr", pPath)
            DllCall("gdiplus\GdipDeletePen", "Ptr", pPen)
        }
        DllCall("gdiplus\GdipDeletePath", "Ptr", pPath)

        ; Minimal flat interior indicator matching HUD glyph clarity (no 3D highlights)
        pipArgb := Gdip.HexToArgb(pipHex, Min(245, Max(180, glassAlpha)))
        if (isBonus) {
            Gdip.DrawText(pGfx, Chr(0x2605), "Segoe UI Symbol", Max(14.0, sz * 0.44), 1, pipArgb, foodX, foodY - 1.0 * this._dpi, sz, sz - barH - 1.0 * this._dpi, 1, 1, 0, true)
        } else {
            dotSz := Max(4.0, sz * 0.28)
            this._FillRoundedBox(pGfx, cellX - dotSz / 2.0, cellY - dotSz / 2.0, dotSz, dotSz, dotSz * 0.35, pipArgb, 0, 0)
        }
    }

    static _DrawEatEffects(pGfx, snakePal, nowUs) {
        kept := []
        for eff in this._eatEffects {
            ageMs := (nowUs - eff.bornUs) / 1000.0
            if (ageMs < 240.0) {
                t := ageMs / 240.0
                cellX := this._gridOffX + (eff.col + 0.5) * this._cell
                cellY := this._gridOffY + (eff.row + 0.5) * this._cell
                startScale := (eff.kind = "bonus") ? 1.42 : 0.68
                sz := this._cell * (startScale + t * 0.44)
                rad := Min((eff.kind = "bonus" ? 14.0 : 7.5) * this._dpi, sz * 0.38)
                alpha := Round((1.0 - t) * 180)
                colHex := (eff.kind = "bonus") ? snakePal.recPaused : snakePal.live
                this._FillRoundedBox(pGfx, cellX - sz / 2.0, cellY - sz / 2.0, sz, sz, rad, 0x00000000, Gdip.HexToArgb(colHex, alpha), 1.4 * this._dpi)
                kept.Push(eff)
            }
        }
        this._eatEffects := kept
    }

    static _DrawMorphTransition(pGfx, snakePal, nowUs) {
        lin := Min(1.0, Max(0.0, (nowUs - this._morphStartUs) / (Float(this._morphDurationMs) * 1000.0)))
        morphFrac := 1.0 - ((1.0 - lin) ** 3) ; Smooth ease-out cubic

        style := this._GetHudStyle()
        tubeW := Float(this._cell * 0.70)
        radTarget := style.sleek ? (tubeW / 2.0) : Min(8.0 * this._dpi, tubeW * 0.42)
        glassAlpha := style.opacity

        ; Cross-fade unified snake silhouette in cleanly during the second half of the morph
        if (morphFrac >= 0.45) {
            ribbonAlpha := Round(glassAlpha * ((morphFrac - 0.45) / 0.55))
            this._DrawContinuousSnake(pGfx, snakePal, nowUs, ribbonAlpha)
        }

        ; Draw shrinking matte HUD pill tiles moving onto initial snake corridor until cross-fade finishes
        if (morphFrac < 0.85) {
            pillAlpha := Round(glassAlpha * (1.0 - Max(0.0, (morphFrac - 0.35) / 0.50)))
            for seed in this._morphSeeds {
                tx := Float(this._gridOffX + (seed.targetCol + 0.5) * this._cell - tubeW / 2.0)
                ty := Float(this._gridOffY + (seed.targetRow + 0.5) * this._cell - tubeW / 2.0)
                sx := Float(seed.x) + (tx - Float(seed.x)) * morphFrac
                sy := Float(seed.y) + (ty - Float(seed.y)) * morphFrac
                sw := Float(seed.w) + (tubeW - Float(seed.w)) * morphFrac
                sh := Float(seed.h) + (tubeW - Float(seed.h)) * morphFrac
                sr := style.sleek ? (sh / 2.0) : Min(radTarget, sh * 0.40)
                brdHex := this._LightenHex(seed.colorHex, 0.18)
                this._FillRoundedBox(pGfx, sx, sy, sw, sh, sr, Gdip.HexToArgb(seed.colorHex, pillAlpha), Gdip.HexToArgb(brdHex, pillAlpha), 1.3 * this._dpi)
            }
        }
    }

    static _BuildInterpolatedPieces(interp) {
        snake := this._snake
        prev := (IsObject(this._prevSnake) && this._prevSnake.Length >= 2) ? this._prevSnake : snake
        lenC := snake.Length
        lenP := prev.Length
        if (lenC == 0)
            return []

        pieces := []
        extraTailPiece := ""

        ; 1. Head endpoint interpolation (prev[1] -> snake[1])
        pHead := prev[1]
        cHead := snake[1]
        dhc := Abs(cHead.col - pHead.col) + Abs(cHead.row - pHead.row)
        skipIdx2Split := false

        if (dhc == 0) {
            ; Crash impact nudge or stationary frame — preserve cHead pivot so a turn right on impact stays strictly 90°
            hx := Float(cHead.col) + this._crashDir.x * interp
            hy := Float(cHead.row) + this._crashDir.y * interp
            headPts := [{ c: hx, r: hy }]
            if (Abs(hx - Float(cHead.col)) > 0.001 || Abs(hy - Float(cHead.row)) > 0.001)
                headPts.Push({ c: Float(cHead.col), r: Float(cHead.row) })
            pieces.Push(headPts)
        } else if (dhc == 1) {
            hx := Float(pHead.col) + Float(cHead.col - pHead.col) * interp
            hy := Float(pHead.row) + Float(cHead.row - pHead.row) * interp
            pieces.Push([{ c: hx, r: hy }])
        } else {
            ; Head wrapped cleanly across monitor edge (snake[2] == pHead)
            hStepX := (cHead.col == 0 && pHead.col == this._cols - 1) ? 1 : (cHead.col == this._cols - 1 && pHead.col == 0) ? -1 : 0
            hStepY := (cHead.row == 0 && pHead.row == this._rows - 1) ? 1 : (cHead.row == this._rows - 1 && pHead.row == 0) ? -1 : 0
            if (interp < 0.5) {
                pieces.Push([{ c: Float(pHead.col) + hStepX * interp, r: Float(pHead.row) + hStepY * interp }])
            } else {
                hxIn := Float(cHead.col) - hStepX * (1.0 - interp)
                hyIn := Float(cHead.row) - hStepY * (1.0 - interp)
                edgeInX := Float(cHead.col) - hStepX * 0.50
                edgeInY := Float(cHead.row) - hStepY * 0.50
                pieces.Push([{ c: hxIn, r: hyIn }, { c: edgeInX, r: edgeInY }])
                pieces.Push([{ c: Float(pHead.col) + hStepX * 0.50, r: Float(pHead.row) + hStepY * 0.50 }])
            }
            skipIdx2Split := true
        }

        ; 2. Walk interior body points [2 .. lenC] splitting cleanly across any toroidal edge jump
        idx := 2
        while (idx <= lenC) {
            cur := snake[idx]
            isLast := (idx == lenC)
            if (isLast && !this._stepGrew && lenP >= 2)
                break ; Handled cleanly by smooth Tail interpolation below

            prevSeg := snake[idx - 1]
            curPiece := pieces[pieces.Length]
            jmp := Abs(cur.col - prevSeg.col) + Abs(cur.row - prevSeg.row)
            if (jmp <= 1 || (idx == 2 && skipIdx2Split)) {
                curPiece.Push({ c: Float(cur.col), r: Float(cur.row) })
            } else {
                jStepX := (cur.col == 0 && prevSeg.col == this._cols - 1) ? -1 : (cur.col == this._cols - 1 && prevSeg.col == 0) ? 1 : 0
                jStepY := (cur.row == 0 && prevSeg.row == this._rows - 1) ? -1 : (cur.row == this._rows - 1 && prevSeg.row == 0) ? 1 : 0
                curPiece.Push({ c: Float(prevSeg.col) - jStepX * 0.50, r: Float(prevSeg.row) - jStepY * 0.50 })
                pieces.Push([{ c: Float(cur.col) + jStepX * 0.50, r: Float(cur.row) + jStepY * 0.50 }, { c: Float(cur.col), r: Float(cur.row) }])
            }
            idx += 1
        }

        ; 3. Tail tip interpolation (when not growing on this tick)
        if (!this._stepGrew && lenP >= 2 && lenC >= 2) {
            pTail := prev[lenP]
            cTail := snake[lenC]
            prevBeforeTail := snake[lenC - 1]
            curPiece := pieces[pieces.Length]

            ; Handle wrap split between snake[lenC - 1] and snake[lenC] if any
            tailJump := Abs(cTail.col - prevBeforeTail.col) + Abs(cTail.row - prevBeforeTail.row)
            if (tailJump > 1) {
                bStepX := (cTail.col == 0 && prevBeforeTail.col == this._cols - 1) ? -1 : (cTail.col == this._cols - 1 && prevBeforeTail.col == 0) ? 1 : 0
                bStepY := (cTail.row == 0 && prevBeforeTail.row == this._rows - 1) ? -1 : (cTail.row == this._rows - 1 && prevBeforeTail.row == 0) ? 1 : 0
                curPiece.Push({ c: Float(prevBeforeTail.col) - bStepX * 0.50, r: Float(prevBeforeTail.row) - bStepY * 0.50 })
                curPiece := [{ c: Float(cTail.col) + bStepX * 0.50, r: Float(cTail.row) + bStepY * 0.50 }]
                pieces.Push(curPiece)
            }

            dtc := Abs(cTail.col - pTail.col) + Abs(cTail.row - pTail.row)
            if (dtc <= 1) {
                ; Always include cTail corner pivot before the interpolated tail tip so tail bends stay strictly 90 degrees
                curPiece.Push({ c: Float(cTail.col), r: Float(cTail.row) })
                tx := Float(pTail.col) + Float(cTail.col - pTail.col) * interp
                ty := Float(pTail.row) + Float(cTail.row - pTail.row) * interp
                curPiece.Push({ c: tx, r: ty })
            } else {
                tStepX := (cTail.col == 0 && pTail.col == this._cols - 1) ? 1 : (cTail.col == this._cols - 1 && pTail.col == 0) ? -1 : 0
                tStepY := (cTail.row == 0 && pTail.row == this._rows - 1) ? 1 : (cTail.row == this._rows - 1 && pTail.row == 0) ? -1 : 0
                curPiece.Push({ c: Float(cTail.col), r: Float(cTail.row) })
                if (interp < 0.5) {
                    curPiece.Push({ c: Float(cTail.col) - tStepX * 0.50, r: Float(cTail.row) - tStepY * 0.50 })
                    extraTailPiece := [{ c: Float(pTail.col) + tStepX * 0.50, r: Float(pTail.row) + tStepY * 0.50 }, { c: Float(pTail.col) + tStepX * interp, r: Float(pTail.row) + tStepY * interp }]
                } else {
                    curPiece.Push({ c: Float(cTail.col) - tStepX * (1.0 - interp), r: Float(cTail.row) - tStepY * (1.0 - interp) })
                }
            }
            if (IsObject(extraTailPiece))
                pieces.Push(extraTailPiece)
        }

        return pieces
    }

    static _DrawContinuousSnake(pGfx, snakePal, nowUs, alphaOverride := -1) {
        if (this._snake.Length == 0)
            return

        if (this.Phase = "playing") {
            stepUs := this._stepMs * 1000.0
            interp := Min(1.0, Max(0.0, (nowUs - this._stepStartUs) / stepUs))
        } else if (this.Phase = "paused" || this.Phase = "gameover") {
            interp := this._frozenInterp
        } else {
            interp := 1.0
        }

        pieces := this._BuildInterpolatedPieces(interp)
        if (pieces.Length == 0)
            return

        cols := this._ResolveSnakeColors(snakePal)
        style := this._GetHudStyle()
        baseAlpha := style.opacity
        useAlpha := (alphaOverride >= 0) ? Max(0, Min(255, Integer(alphaOverride))) : baseAlpha
        if (useAlpha <= 0)
            return

        tubeW := Float(this._cell * 0.68)
        rimW := Float(1.4 * this._dpi)

        pxPieces := []
        headPx := ""
        minX := 999999.0, minY := 999999.0
        maxX := -999999.0, maxY := -999999.0

        for pIdx, piece in pieces {
            pxPts := []
            for pt in piece {
                px := Float(this._gridOffX + (pt.c + 0.5) * this._cell)
                py := Float(this._gridOffY + (pt.r + 0.5) * this._cell)
                if (pxPts.Length == 0) {
                    pxPts.Push({ x: px, y: py })
                } else {
                    lastPt := pxPts[pxPts.Length]
                    if (Abs(px - lastPt.x) > 0.35 || Abs(py - lastPt.y) > 0.35)
                        pxPts.Push({ x: px, y: py })
                }
                minX := Min(minX, px)
                maxX := Max(maxX, px)
                minY := Min(minY, py)
                maxY := Max(maxY, py)
            }
            if (pxPts.Length > 0) {
                if (pIdx == 1)
                    headPx := pxPts[1]
                pxPieces.Push(pxPts)
            }
        }
        if (pxPieces.Length == 0)
            return

        pCenterPath := 0
        DllCall("gdiplus\GdipCreatePath", "Int", 0, "Ptr*", &pCenterPath)
        if (!pCenterPath)
            return

        for pxPts in pxPieces {
            DllCall("gdiplus\GdipStartPathFigure", "Ptr", pCenterPath)
            if (pxPts.Length == 1) {
                ptBuf := Buffer(16, 0)
                NumPut("Float", pxPts[1].x, "Float", pxPts[1].y, "Float", pxPts[1].x + 0.01, "Float", pxPts[1].y, ptBuf, 0)
                DllCall("gdiplus\GdipAddPathLine2", "Ptr", pCenterPath, "Ptr", ptBuf, "Int", 2)
            } else {
                cnt := pxPts.Length
                ptBuf := Buffer(cnt * 8, 0)
                off := 0
                for pt in pxPts {
                    NumPut("Float", pt.x, "Float", pt.y, ptBuf, off)
                    off += 8
                }
                DllCall("gdiplus\GdipAddPathLine2", "Ptr", pCenterPath, "Ptr", ptBuf, "Int", cnt)
            }
        }

        ; Draw 100% opaque rim + 100% opaque fill onto offscreen ARGB scratch layer, then composite once at useAlpha.
        ; This eliminates GdipWidenPath 90-degree inner corner triangles AND eliminates semi-transparent joint overlaps!
        pOuterPen := 0
        pInnerPen := 0
        DllCall("gdiplus\GdipCreatePen1", "UInt", Gdip.HexToArgb(cols.rimHex, 255), "Float", tubeW + rimW * 2.0, "Int", 2, "Ptr*", &pOuterPen)
        DllCall("gdiplus\GdipCreatePen1", "UInt", Gdip.HexToArgb(cols.fillHex, 255), "Float", tubeW, "Int", 2, "Ptr*", &pInnerPen)
        for curPen in [pOuterPen, pInnerPen] {
            if (curPen) {
                DllCall("gdiplus\GdipSetPenLineJoin", "Ptr", curPen, "Int", 2) ; LineJoinRound
                DllCall("gdiplus\GdipSetPenStartCap", "Ptr", curPen, "Int", 2) ; LineCapRound
                DllCall("gdiplus\GdipSetPenEndCap", "Ptr", curPen, "Int", 2)   ; LineCapRound
            }
        }

        ; Clip main canvas to play grid so toroidal portal wraps slice cleanly flush against perimeter border
        DllCall("gdiplus\GdipSetClipRect", "Ptr", pGfx, "Float", Float(this._gridOffX), "Float", Float(this._gridOffY), "Float", Float(this._cols * this._cell), "Float", Float(this._rows * this._cell), "Int", 0)

        if (this._pSnakeGfx && this._pSnakeBmp && this._pImgAttr) {
            if (IsObject(this._prevDirtyRect)) {
                pr := this._prevDirtyRect
                DllCall("gdiplus\GdipSetClipRect", "Ptr", this._pSnakeGfx, "Float", Float(pr.x), "Float", Float(pr.y), "Float", Float(pr.w), "Float", Float(pr.h), "Int", 0)
                DllCall("gdiplus\GdipGraphicsClear", "Ptr", this._pSnakeGfx, "UInt", 0)
                DllCall("gdiplus\GdipResetClip", "Ptr", this._pSnakeGfx)
            }

            pad := (tubeW / 2.0) + rimW + 6.0
            bx := Max(0, Floor(minX - pad))
            by := Max(0, Floor(minY - pad))
            br := Min(this._W, Ceil(maxX + pad))
            bb := Min(this._H, Ceil(maxY + pad))
            bw := Max(1, br - bx)
            bh := Max(1, bb - by)
            this._prevDirtyRect := { x: bx, y: by, w: bw, h: bh }

            DllCall("gdiplus\GdipSetClipRect", "Ptr", this._pSnakeGfx, "Float", Float(bx), "Float", Float(by), "Float", Float(bw), "Float", Float(bh), "Int", 0)
            if (pOuterPen)
                DllCall("gdiplus\GdipDrawPath", "Ptr", this._pSnakeGfx, "Ptr", pOuterPen, "Ptr", pCenterPath)
            if (pInnerPen)
                DllCall("gdiplus\GdipDrawPath", "Ptr", this._pSnakeGfx, "Ptr", pInnerPen, "Ptr", pCenterPath)
            DllCall("gdiplus\GdipResetClip", "Ptr", this._pSnakeGfx)

            NumPut("Float", Float(useAlpha) / 255.0, this._snakeColorMat, 72)
            DllCall("gdiplus\GdipSetImageAttributesColorMatrix", "Ptr", this._pImgAttr, "Int", 0, "Int", 1, "Ptr", this._snakeColorMat, "Ptr", 0, "Int", 0)
            DllCall("gdiplus\GdipDrawImageRectRect", "Ptr", pGfx, "Ptr", this._pSnakeBmp, "Float", Float(bx), "Float", Float(by), "Float", Float(bw), "Float", Float(bh), "Float", Float(bx), "Float", Float(by), "Float", Float(bw), "Float", Float(bh), "Int", 2, "Ptr", this._pImgAttr, "Ptr", 0, "Ptr", 0)
        } else {
            if (pOuterPen)
                DllCall("gdiplus\GdipDrawPath", "Ptr", pGfx, "Ptr", pOuterPen, "Ptr", pCenterPath)
            if (pInnerPen)
                DllCall("gdiplus\GdipDrawPath", "Ptr", pGfx, "Ptr", pInnerPen, "Ptr", pCenterPath)
        }

        if (pOuterPen)
            DllCall("gdiplus\GdipDeletePen", "Ptr", pOuterPen)
        if (pInnerPen)
            DllCall("gdiplus\GdipDeletePen", "Ptr", pInnerPen)
        DllCall("gdiplus\GdipDeletePath", "Ptr", pCenterPath)

        ; Draw ultra-minimalist flat eye pips right on the smooth head cap
        if (IsObject(headPx))
            this._DrawMinimalHeadEyes(pGfx, headPx.x, headPx.y, tubeW, cols.eyeColorHex, useAlpha)
        DllCall("gdiplus\GdipResetClip", "Ptr", pGfx)
    }

    static _DrawMinimalHeadEyes(pGfx, headX, headY, tubeW, eyeHex, alpha) {
        dx := this._dir.x
        dy := this._dir.y
        fwd := tubeW * 0.14
        side := tubeW * 0.21
        dotSz := Max(2.6, tubeW * 0.16)

        e1x := headX + dx * fwd - dy * side
        e1y := headY + dy * fwd + dx * side
        e2x := headX + dx * fwd + dy * side
        e2y := headY + dy * fwd - dx * side

        pEyeBrush := 0
        DllCall("gdiplus\GdipCreateSolidFill", "UInt", Gdip.HexToArgb(eyeHex, Min(245, alpha)), "Ptr*", &pEyeBrush)
        if (pEyeBrush) {
            DllCall("gdiplus\GdipFillEllipse", "Ptr", pGfx, "Ptr", pEyeBrush, "Float", Float(e1x - dotSz / 2.0), "Float", Float(e1y - dotSz / 2.0), "Float", Float(dotSz), "Float", Float(dotSz))
            DllCall("gdiplus\GdipFillEllipse", "Ptr", pGfx, "Ptr", pEyeBrush, "Float", Float(e2x - dotSz / 2.0), "Float", Float(e2y - dotSz / 2.0), "Float", Float(dotSz), "Float", Float(dotSz))
            DllCall("gdiplus\GdipDeleteBrush", "Ptr", pEyeBrush)
        }
    }

    static _DrawPopups(pGfx, nowUs) {
        kept := []
        for pop in this._popups {
            ageMs := (nowUs - pop.bornUs) / 1000.0
            if (ageMs < 550.0) {
                t := ageMs / 550.0
                py := pop.y - t * (22.0 * this._dpi)
                alpha := Round((1.0 - t) * 245)
                colHex := (pop.kind = "bonus") ? "FCD34D" : "F8FAFC"
                argb := Gdip.HexToArgb(colHex, alpha)
                Gdip.DrawText(pGfx, pop.text, "Segoe UI", 9.8 * this._dpi, 1, argb, pop.x - 32, py - 14, 64, 22, 1, 1, 0, true)
                kept.Push(pop)
            }
        }
        this._popups := kept
    }

    static _DrawFluentKeyHint(pGfx, x, y, h, keyText, actionText, isDark, dpi) {
        keyW := Float(Gdip.MeasureTextWidth(keyText, "Segoe UI", 7.8 * dpi, 1) + 12.0 * dpi)
        actW := Float(Gdip.MeasureTextWidth(actionText, "Segoe UI", 8.0 * dpi, 0) + 6.0 * dpi)
        capH := Min(h, Float(Round(20 * dpi)))
        capY := y + (h - capH) / 2.0

        capFill := isDark ? 0xFF333333 : 0xFFFBFBFB
        capStroke := isDark ? 0xFF454545 : 0xFFDCDCDC
        capTxt := isDark ? 0xFFF3F4F6 : 0xFF1F2328
        lblTxt := isDark ? 0xFFB5BAC4 : 0xFF5F5F5F

        this._FillRoundedBox(pGfx, x, capY, keyW, capH, 4.0 * dpi, capFill, capStroke, 1.0)
        Gdip.DrawText(pGfx, keyText, "Segoe UI", 7.8 * dpi, 1, capTxt, x, capY, keyW, capH, 1, 1, 0, true)
        Gdip.DrawText(pGfx, actionText, "Segoe UI", 8.0 * dpi, 0, lblTxt, x + keyW + 4.0 * dpi, y, actW, h, 0, 1, 0, true)
        return keyW + 4.0 * dpi + actW
    }

    static _DrawScoreboard(pGfx, snakePal, isDark) {
        style := this._GetHudStyle()
        dpi := this._dpi
        sbH := Float(Round(40 * dpi))

        ; Windows 11 Explorer Fluent frosted surface + PresenterSync HUD pill chrome
        surfAlpha := Max(170, Min(246, style.opacity + 38))
        pillAlpha := Max(196, style.opacity)
        bgArgb := isDark ? ((surfAlpha << 24) | 0x2C2C2C) : ((Min(250, surfAlpha + 6) << 24) | 0xFFFFFF)
        brdArgb := isDark ? 0xFF454545 : 0xFFDCDCDC
        txtArgb := isDark ? 0xFFFFFFFF : 0xFF1F2328
        divArgb := isDark ? 0xFF454545 : 0xFFE2E2E2
        sbRad := style.sleek ? (sbH / 2.0) : Min(8.0 * dpi, sbH / 2.0)

        ; Left PresenterSync HUD Status Pill (dynamically measured & centered internally)
        if (this.Phase = "gameover") {
            pillHex := snakePal.muted, pillMonoHex := snakePal.iconMuted, pillGlyph := Chr(0xE7BA)
        } else if (this.Phase = "paused") {
            pillHex := snakePal.chatAlert, pillMonoHex := snakePal.chatIconAlert, pillGlyph := Chr(0xE769)
        } else {
            pillHex := snakePal.live, pillMonoHex := snakePal.iconLive, pillGlyph := Chr(0xE720)
        }
        badgeTitle := "HUD SNAKE"
        badgeLblW := Float(Gdip.MeasureTextWidth(badgeTitle, "Segoe UI", 8.6 * dpi, 1))
        icW := 13.0 * dpi
        icGap := 5.0 * dpi
        badgeInnerW := icW + icGap + badgeLblW
        badgeW := Max(Float(Round(104 * dpi)), badgeInnerW + 22.0 * dpi)
        badgeH := sbH - 10.0 * dpi

        ; Right-side Edge chip + Win11 keycap hints measured dynamically
        edgeLabel := this._edgeWrap ? "WRAP" : "WALLS"
        edgeW := Max(Float(Round(58 * dpi)), Float(Gdip.MeasureTextWidth(edgeLabel, "Segoe UI", 7.8 * dpi, 1) + 20.0 * dpi))
        edgeH := Float(Round(22 * dpi))
        hintItems := [
            { k: "P", l: "Pause" },
            { k: "E", l: "Edge" },
            { k: "Esc", l: "Exit" }
        ]
        hintsTotalW := 0.0
        for hi, it in hintItems {
            kw := Float(Gdip.MeasureTextWidth(it.k, "Segoe UI", 7.8 * dpi, 1) + 12.0 * dpi)
            aw := Float(Gdip.MeasureTextWidth(it.l, "Segoe UI", 8.0 * dpi, 0) + 6.0 * dpi)
            hintsTotalW += kw + 4.0 * dpi + aw + (hi < hintItems.Length ? 7.0 * dpi : 0.0)
        }

        speedMult := Format("{:.1f}x", 132.0 / Max(68, this._stepMs))
        statsText := Format("Score {}   ·   Best {}   ·   Len {}   ·   {}", this._score, this._highScore, this._snake.Length, speedMult)
        statsTextW := Float(Gdip.MeasureTextWidth(statsText, "Segoe UI", 9.0 * dpi, 1))
        rightClusterW := edgeW + 10.0 * dpi + 1.0 + 9.0 * dpi + hintsTotalW + 10.0 * dpi
        minSbW := 5.0 * dpi + badgeW + 16.0 * dpi + statsTextW + 16.0 * dpi + rightClusterW
        sbW := Min(Float(this._W - 32), Max(Float(Round(640 * dpi)), minSbW))
        sbX := (this._W - sbW) / 2.0
        sbY := Float(Round(8 * dpi))

        this._FillRoundedBox(pGfx, sbX, sbY, sbW, sbH, sbRad, bgArgb, brdArgb, 1.2)

        badgeX := sbX + 5.0 * dpi
        badgeY := sbY + 5.0 * dpi
        badgeRad := style.sleek ? (badgeH / 2.0) : Min(6.0 * dpi, badgeH / 2.0)
        badgeFill := Gdip.HexToArgb(pillHex, pillAlpha)
        badgeRim := Gdip.HexToArgb(this._LightenHex(pillHex, 0.18), Min(255, pillAlpha + 25))
        badgeTxtHex := this._PickBadgeContentHex(pillHex, pillMonoHex, style.mono, isDark, pillAlpha)
        badgeTxt := Gdip.HexToArgb(badgeTxtHex, 255)
        iconFont := (IsObject(this._state) && this._state.HasOwnProp("IconFont")) ? this._state.IconFont : "Segoe MDL2 Assets"

        this._FillRoundedBox(pGfx, badgeX, badgeY, badgeW, badgeH, badgeRad, badgeFill, badgeRim, 1.2)
        cX := badgeX + (badgeW - badgeInnerW) / 2.0
        Gdip.DrawText(pGfx, pillGlyph, iconFont, 8.8 * dpi, 0, badgeTxt, cX, badgeY, icW, badgeH, 1, 1, 0, true)
        Gdip.DrawText(pGfx, badgeTitle, "Segoe UI", 8.6 * dpi, 1, badgeTxt, cX + icW + icGap, badgeY, badgeLblW + 4.0 * dpi, badgeH, 0, 1, 0, true)

        hx := sbX + sbW - hintsTotalW - 10.0 * dpi
        divX := hx - 9.0 * dpi
        pDiv := 0
        DllCall("gdiplus\GdipCreatePen1", "UInt", divArgb, "Float", Float(1.0), "Int", 2, "Ptr*", &pDiv)
        if (pDiv) {
            DllCall("gdiplus\GdipDrawLine", "Ptr", pGfx, "Ptr", pDiv, "Float", divX, "Float", sbY + 8 * dpi, "Float", divX, "Float", sbY + sbH - 8 * dpi)
            DllCall("gdiplus\GdipDeletePen", "Ptr", pDiv)
        }

        curHx := hx
        for hi, it in hintItems {
            usedW := this._DrawFluentKeyHint(pGfx, curHx, sbY, sbH, it.k, it.l, isDark, dpi)
            curHx += usedW + 7.0 * dpi
        }

        edgeX := divX - edgeW - 10.0 * dpi
        edgeY := sbY + (sbH - edgeH) / 2.0
        edgeRad := style.sleek ? (edgeH / 2.0) : Min(5.5 * dpi, edgeH / 2.0)
        if (this._edgeWrap) {
            edgeFill := Gdip.HexToArgb(isDark ? "1A365D" : "EBF5FF", 235)
            edgeBrd := Gdip.HexToArgb(isDark ? "60CDFF" : "0067C0", 255)
            edgeTxt := Gdip.HexToArgb(isDark ? "60CDFF" : "0067C0", 255)
        } else {
            edgeFill := isDark ? 0xFF333333 : 0xFFF3F3F3
            edgeBrd := isDark ? 0xFF565656 : 0xFFC8C8C8
            edgeTxt := txtArgb
        }
        this._FillRoundedBox(pGfx, edgeX, edgeY, edgeW, edgeH, edgeRad, edgeFill, edgeBrd, 1.1)
        Gdip.DrawText(pGfx, edgeLabel, "Segoe UI", 7.8 * dpi, 1, edgeTxt, edgeX, edgeY, edgeW, edgeH, 1, 1, 0, true)

        ; Middle Fluent metrics strip centered symmetrically between HUD badge and Edge chip
        statX := badgeX + badgeW + 10.0 * dpi
        statW := Max(60.0, edgeX - statX - 10.0 * dpi)
        Gdip.DrawText(pGfx, statsText, "Segoe UI", 9.0 * dpi, 1, txtArgb, statX, sbY, statW, sbH, 1, 1, 0, true)
    }

    static _DrawStatusBanner(pGfx, snakePal, isDark) {
        style := this._GetHudStyle()
        dpi := this._dpi
        isDead := (this.Phase = "gameover")
        surfAlpha := Max(178, Min(248, style.opacity + 42))
        pillAlpha := Max(196, style.opacity)
        bgArgb := isDark ? ((surfAlpha << 24) | 0x2C2C2C) : ((Min(252, surfAlpha + 6) << 24) | 0xFFFFFF)
        brdArgb := isDark ? 0xFF454545 : 0xFFDCDCDC
        divArgb := isDark ? 0xFF404040 : 0xFFE6E6E6
        txtArgb := isDark ? 0xFFFFFFFF : 0xFF1F2328
        subArgb := isDark ? 0xFFC5C5C5 : 0xFF5F5F5F

        accentHex := isDead ? snakePal.muted : (isDark ? "60CDFF" : "0067C0")
        pillHex := isDead ? snakePal.muted : snakePal.chatAlert
        pillMonoHex := isDead ? snakePal.iconMuted : snakePal.chatIconAlert
        pillGlyph := isDead ? Chr(0xE7BA) : Chr(0xE769)
        iconFont := (IsObject(this._state) && this._state.HasOwnProp("IconFont")) ? this._state.IconFont : "Segoe MDL2 Assets"

        ; Measure Row 1 centered cluster: [Glyph + Status Pill]  ·  Title/Reason  [Score Chip]  [New Best Chip]
        statusTag := isDead ? "GAME OVER" : "PAUSED"
        tagTxtW := Float(Gdip.MeasureTextWidth(statusTag, "Segoe UI", 8.2 * dpi, 1))
        icSz := 12.0 * dpi
        icGap := 5.0 * dpi
        tagInnerW := icSz + icGap + tagTxtW
        tagW := tagInnerW + 18.0 * dpi
        tagH := 23.0 * dpi

        midTitle := isDead
            ? ((this._deathReason = "wall") ? "Hit Monitor Edge" : "Self-Collision")
            : "HUD Snake Paused"
        midTitleW := Float(Gdip.MeasureTextWidth(midTitle, "Segoe UI", 10.2 * dpi, 1)) + 4.0 * dpi
        dotW := 16.0 * dpi

        scTxt := "Score " this._score
        scW := Float(Gdip.MeasureTextWidth(scTxt, "Segoe UI", 8.4 * dpi, 1)) + 18.0 * dpi
        bestTxt := Chr(0x2605) " New Best"
        bestW := (isDead && this._bestBeaten) ? (Float(Gdip.MeasureTextWidth(bestTxt, "Segoe UI", 8.2 * dpi, 1)) + 18.0 * dpi) : 0.0

        row1W := tagW + dotW + midTitleW + 10.0 * dpi + scW + ((bestW > 0) ? (8.0 * dpi + bestW) : 0.0)

        ; Measure Row 2 centered Fluent Win11 Explorer keycap action hints
        actions := isDead
            ? [ { k: "R / Space", l: "Play Again" }, { k: "E", l: "Toggle Edge" }, { k: "Esc", l: "Restore HUD" } ]
            : [ { k: "P / Space", l: "Resume" },     { k: "E", l: "Toggle Edge" }, { k: "Esc", l: "Restore HUD" } ]
        actWidths := []
        row2W := 0.0
        for ai, act in actions {
            kw := Float(Gdip.MeasureTextWidth(act.k, "Segoe UI", 7.8 * dpi, 1) + 12.0 * dpi)
            aw := Float(Gdip.MeasureTextWidth(act.l, "Segoe UI", 8.0 * dpi, 0) + 6.0 * dpi)
            itemW := kw + 4.0 * dpi + aw
            actWidths.Push(itemW)
            row2W += itemW + (ai < actions.Length ? 18.0 * dpi : 0.0)
        }

        banW := Min(Float(this._W - 32), Max(Float(Round(500 * dpi)), Ceil(Max(row1W, row2W) + 52.0 * dpi)))
        banH := Float(Round(80 * dpi))
        banX := (this._W - banW) / 2.0
        banY := Float(Round(56 * dpi))
        banRad := style.sleek ? (14.0 * dpi) : (8.0 * dpi)

        this._FillRoundedBox(pGfx, banX, banY, banW, banH, banRad, bgArgb, brdArgb, 1.2)

        ; Subtle Win11 Tab/Card bottom accent strip clipped cleanly inside card bounds
        if (pCardPath := Gdip.CreateRoundedRectPath(banX, banY, banW, banH, banRad)) {
            DllCall("gdiplus\GdipSetClipPath", "Ptr", pGfx, "Ptr", pCardPath, "Int", 0)
            pAccBrush := 0
            DllCall("gdiplus\GdipCreateSolidFill", "UInt", Gdip.HexToArgb(accentHex, 235), "Ptr*", &pAccBrush)
            if (pAccBrush) {
                DllCall("gdiplus\GdipFillRectangle", "Ptr", pGfx, "Ptr", pAccBrush, "Float", banX, "Float", banY + banH - 2.8 * dpi, "Float", banW, "Float", 3.2 * dpi)
                DllCall("gdiplus\GdipDeleteBrush", "Ptr", pAccBrush)
            }
            DllCall("gdiplus\GdipResetClip", "Ptr", pGfx)
            DllCall("gdiplus\GdipDeletePath", "Ptr", pCardPath)
        }

        ; Draw centered Row 1
        row1Y := banY + 11.0 * dpi
        row1H := 25.0 * dpi
        curX := banX + (banW - row1W) / 2.0

        tagY := row1Y + (row1H - tagH) / 2.0
        tagRad := style.sleek ? (tagH / 2.0) : Min(6.0 * dpi, tagH / 2.0)
        tagTxtHex := this._PickBadgeContentHex(pillHex, pillMonoHex, style.mono, isDark, pillAlpha)
        tagTxtArgb := Gdip.HexToArgb(tagTxtHex, 255)
        this._FillRoundedBox(pGfx, curX, tagY, tagW, tagH, tagRad, Gdip.HexToArgb(pillHex, pillAlpha), Gdip.HexToArgb(this._LightenHex(pillHex, 0.20), Min(255, pillAlpha + 25)), 1.1)
        tagInnerX := curX + (tagW - tagInnerW) / 2.0
        Gdip.DrawText(pGfx, pillGlyph, iconFont, 8.6 * dpi, 0, tagTxtArgb, tagInnerX, tagY, icSz, tagH, 1, 1, 0, true)
        Gdip.DrawText(pGfx, statusTag, "Segoe UI", 8.2 * dpi, 1, tagTxtArgb, tagInnerX + icSz + icGap, tagY, tagTxtW + 4.0 * dpi, tagH, 0, 1, 0, true)
        curX += tagW

        Gdip.DrawText(pGfx, "·", "Segoe UI", 9.5 * dpi, 1, subArgb, curX, row1Y, dotW, row1H, 1, 1, 0, true)
        curX += dotW

        Gdip.DrawText(pGfx, midTitle, "Segoe UI", 10.2 * dpi, 1, txtArgb, curX, row1Y, midTitleW, row1H, 0, 1, 0, true)
        curX += midTitleW + 10.0 * dpi

        chipY := row1Y + (row1H - tagH) / 2.0
        chipRad := style.sleek ? (tagH / 2.0) : 5.5 * dpi
        this._FillRoundedBox(pGfx, curX, chipY, scW, tagH, chipRad, isDark ? 0xFF333333 : 0xFFF3F3F3, isDark ? 0xFF4B4B4B : 0xFFD8D8D8, 1.1)
        Gdip.DrawText(pGfx, scTxt, "Segoe UI", 8.4 * dpi, 1, txtArgb, curX, chipY, scW, tagH, 1, 1, 0, true)
        curX += scW

        if (bestW > 0) {
            curX += 8.0 * dpi
            bestTxtHex := this._PickBadgeContentHex(snakePal.recPaused, snakePal.recIconPaused, style.mono, isDark, pillAlpha)
            this._FillRoundedBox(pGfx, curX, chipY, bestW, tagH, chipRad, Gdip.HexToArgb(snakePal.recPaused, pillAlpha), Gdip.HexToArgb(this._LightenHex(snakePal.recPaused, 0.20), 255), 1.1)
            Gdip.DrawText(pGfx, bestTxt, "Segoe UI", 8.2 * dpi, 1, Gdip.HexToArgb(bestTxtHex, 255), curX, chipY, bestW, tagH, 1, 1, 0, true)
        }

        ; Delicate centered divider separating Row 1 header from Row 2 action keys
        pHDiv := 0
        DllCall("gdiplus\GdipCreatePen1", "UInt", divArgb, "Float", Float(1.0), "Int", 2, "Ptr*", &pHDiv)
        if (pHDiv) {
            divPad := 24.0 * dpi
            DllCall("gdiplus\GdipDrawLine", "Ptr", pGfx, "Ptr", pHDiv, "Float", banX + divPad, "Float", banY + 41.0 * dpi, "Float", banX + banW - divPad, "Float", banY + 41.0 * dpi)
            DllCall("gdiplus\GdipDeletePen", "Ptr", pHDiv)
        }

        ; Draw centered Row 2 Fluent keycap action hints
        row2Y := banY + 46.0 * dpi
        row2H := 24.0 * dpi
        ax := banX + (banW - row2W) / 2.0
        for ai, act in actions {
            usedW := this._DrawFluentKeyHint(pGfx, ax, row2Y, row2H, act.k, act.l, isDark, dpi)
            ax += usedW
            if (ai < actions.Length) {
                Gdip.DrawText(pGfx, "·", "Segoe UI", 8.5 * dpi, 0, subArgb, ax + 1.0 * dpi, row2Y, 10.0 * dpi, row2H, 1, 1, 0, true)
                ax += 18.0 * dpi
            }
        }
    }
}
