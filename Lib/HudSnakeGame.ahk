; ==============================================================================
; Module: HudSnakeGame.ahk
; Description: Hidden desktop-floating Snake Easter Egg (Alt+Ctrl+Shift+S).
;              Morphs the active PresenterSync HUD pills into a GDI+ layered
;              snake directly on the topmost click-through desktop layer without
;              interrupting underlying applications.
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

    ; Game Entities & State
    static _snake := []        ; Array of { col, row, colorHex } where [1] is Head
    static _morphSeeds := []   ; Array of { x, y, w, h, colorHex, glyph } captured from HUD
    static _morphStartTick := 0
    static _morphDurationMs := 360
    static _dir := { x: -1, y: 0 }
    static _dirQueue := []
    static _growPending := 0
    static _food := ""         ; { col, row, kind, bornTick, ttlMs, pts }
    static _score := 0
    static _highScore := 0
    static _bestBeaten := false
    static _eatenCount := 0
    static _edgeWrap := false
    static _deathReason := ""
    static _popups := []       ; Array of { x, y, text, colorHex, bornTick }
    static _ripples := []      ; Array of { x, y, colorHex, bornTick }

    ; Timing & Loops
    static _stepMs := 135
    static _lastStepTick := 0
    static _tickTimerFn := ""
    static _boundHotkeys := []
    static _cfg := ""
    static _state := ""
    static _headless := false

    ; Persistent Zero-Alloc GDI+ Layered Canvas
    static _gui := ""
    static _hdcMem := 0
    static _hbm := 0
    static _obm := 0
    static _pBits := 0
    static _pGraphics := 0
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
        this._cfg := cfg
        this._state := state
        this._headless := headless
        this._highScore := this._LoadHighScore(cfg)
        this._bestBeaten := false
        this._score := 0
        this._eatenCount := 0
        this._deathReason := ""
        this._growPending := 0
        this._dirQueue := []
        this._popups := []
        this._ripples := []
        this._stepMs := 135
        this._lastStepTick := A_TickCount

        ; Resolve target monitor work area hosting the HUD stack
        this._ResolveMonitorWorkArea(state)
        this._ComputeGrid()

        ; Hide live HUD overlays cleanly before creating overlay canvas
        this.IsActive := true
        this._PauseLiveHuds(cfg, state)

        ; Capture active HUD pill positions & colors to morph smoothly into snake segments
        this._CaptureMorphSeedsAndSpawnSnake(cfg, state)
        this._SpawnFood("normal")

        this.Phase := headless ? "playing" : "morph"
        this._morphStartTick := A_TickCount

        if (!headless) {
            if (!this._InitCanvas()) {
                this.Stop()
                return false
            }
            this._BindGameHotkeys()
            this._RenderFrame()
            this._tickTimerFn := ObjBindMethod(this, "_FrameTick")
            SetTimer(this._tickTimerFn, 32)
        } else {
            this._lastStepTick := A_TickCount
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
        this._UnbindGameHotkeys()
        this._DestroyCanvas()

        this.IsActive := false
        this.Phase := "idle"
        this._snake := []
        this._morphSeeds := []
        this._dirQueue := []
        this._popups := []
        this._ripples := []
        this._food := ""

        ; Morph / restore synchronized live HUD cleanly
        if (IsObject(this._cfg) && IsObject(this._state)) {
            try {
                if (this._cfg.ShowIndicator)
                    RefreshHudAppearance(this._cfg, this._state)
                else
                    UpdateHudVisibility(this._cfg, this._state)
                UpdateAutoDodgeTimer(this._cfg, this._state)
                UpdateVoiceMeterTimer(this._cfg, this._state)
            }
        }
        this._cfg := ""
        this._state := ""
        this._headless := false
    }

    static Restart() {
        if (!this.IsActive || !IsObject(this._cfg) || !IsObject(this._state))
            return
        this._bestBeaten := false
        this._score := 0
        this._eatenCount := 0
        this._deathReason := ""
        this._growPending := 0
        this._dirQueue := []
        this._popups := []
        this._ripples := []
        this._stepMs := 135
        this._CaptureMorphSeedsAndSpawnSnake(this._cfg, this._state)
        this._SpawnFood("normal")
        this.Phase := this._headless ? "playing" : "morph"
        this._morphStartTick := A_TickCount
        this._lastStepTick := A_TickCount
        if (!this._headless)
            this._RenderFrame()
    }

    static TogglePause() {
        if (!this.IsActive)
            return
        if (this.Phase = "playing") {
            this.Phase := "paused"
            if (!this._headless)
                this._RenderFrame()
        } else if (this.Phase = "paused") {
            this.Phase := "playing"
            this._lastStepTick := A_TickCount
            if (!this._headless)
                this._RenderFrame()
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
        ; Reject duplicates and illegal 180-degree neck reversals
        if ((dx == refDir.x && dy == refDir.y) || (dx == -refDir.x && dy == -refDir.y))
            return false
        if (this._dirQueue.Length >= 2)
            return false

        this._dirQueue.Push({ x: dx, y: dy })
        return true
    }

    static StepSimulation(nowTick := -1) {
        if (!this.IsActive || this.Phase != "playing")
            return
        if (nowTick < 0)
            nowTick := A_TickCount

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
                this._TriggerGameOver("wall", nowTick)
                return
            }
        }

        ; Expire timed bonus fruit cleanly
        if (IsObject(this._food) && this._food.ttlMs > 0 && (nowTick - this._food.bornTick >= this._food.ttlMs))
            this._SpawnFood("normal", nowTick)

        willEat := IsObject(this._food) && (nextCol == this._food.col && nextRow == this._food.row)

        ; Self-collision check (the tail tip cell vacates cleanly if not growing this tick)
        checkLimit := (this._growPending == 0 && !willEat) ? (this._snake.Length - 1) : this._snake.Length
        Loop checkLimit {
            seg := this._snake[A_Index]
            if (seg.col == nextCol && seg.row == nextRow) {
                this._TriggerGameOver("self", nowTick)
                return
            }
        }

        pal := this._GetActivePalette()
        newHeadColor := this._snake[1].colorHex
        nextTailColor := this._GetSegmentPaletteColor(this._snake.Length + 1, pal)
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
            fx := this._gridOffX + (nextCol + 0.5) * this._cell
            fy := this._gridOffY + (nextRow + 0.5) * this._cell
            this._popups.Push({ x: fx, y: fy - 6, text: "+" this._food.pts, colorHex: (this._food.kind = "bonus" ? "FCD34D" : "FFFFFF"), bornTick: nowTick })
            this._ripples.Push({ x: fx, y: fy, colorHex: (this._food.kind = "bonus" ? "F59E0B" : pal.live), bornTick: nowTick })
            if (IsObject(this._cfg) && this._cfg.HasOwnProp("EnableAudioCue") && this._cfg.EnableAudioCue)
                try PlayMuteAudioCue(false)

            ; Ramp speed progressively down to crisp arcade cap
            this._stepMs := Max(68, 135 - Min(67, this._eatenCount * 3))
            nextKind := (Mod(this._eatenCount, 5) == 0) ? "bonus" : "normal"
            this._food := ""
        }

        ; Advance segments cleanly preserving distinct pill colors along the body
        newHead := { col: nextCol, row: nextRow, colorHex: newHeadColor }
        this._snake.InsertAt(1, newHead)

        if (this._growPending > 0) {
            this._growPending -= 1
            ; Tint newly grown tail segment like the next PresenterSync HUD pill color
            if (this._snake.Length >= 2)
                this._snake[this._snake.Length].colorHex := nextTailColor
        } else {
            this._snake.Pop()
        }

        ; Keep existing per-segment body hues anchored cleanly down from head->tail
        Loop this._snake.Length {
            idx := A_Index
            this._snake[idx].colorHex := this._GetSegmentPaletteColor(idx, pal)
        }

        if (willEat)
            this._SpawnFood(nextKind, nowTick)
    }

    static _TriggerGameOver(reason, nowTick) {
        this.Phase := "gameover"
        this._deathReason := reason
        if (IsObject(this._cfg) && this._cfg.HasOwnProp("EnableAudioCue") && this._cfg.EnableAudioCue)
            try PlayMuteAudioCue(true)
        if (this._snake.Length >= 1) {
            h := this._snake[1]
            fx := this._gridOffX + (h.col + 0.5) * this._cell
            fy := this._gridOffY + (h.row + 0.5) * this._cell
            this._ripples.Push({ x: fx, y: fy, colorHex: "EF4444", bornTick: nowTick })
        }
    }

    static _FrameTick() {
        if (!this.IsActive)
            return

        now := A_TickCount
        if (this.Phase = "morph") {
            if ((now - this._morphStartTick) >= this._morphDurationMs) {
                this.Phase := "playing"
                this._lastStepTick := now
            }
            this._RenderFrame(now)
            return
        }

        if (this.Phase = "playing") {
            if ((now - this._lastStepTick) >= this._stepMs) {
                this._lastStepTick := now
                this.StepSimulation(now)
            }
            this._RenderFrame(now)
            return
        }

        if (this.Phase = "gameover" && this._ripples.Length > 0)
            this._RenderFrame(now)
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
        this._cell := Max(22, Round(28 * this._dpi))
        this._cols := Max(16, Floor((this._W - Round(16 * this._dpi)) / this._cell))
        this._rows := Max(12, Floor((this._H - Round(16 * this._dpi)) / this._cell))
        this._gridOffX := Floor((this._W - this._cols * this._cell) / 2)
        this._gridOffY := Floor((this._H - this._rows * this._cell) / 2)
        sbW := Min(Round(580 * this._dpi), this._W - 40)
        this._sbColsHalf := Max(4, Ceil((sbW / 2) / this._cell) + 1)
        this._sbSafeRows := Max(2, Ceil(Round(52 * this._dpi) / this._cell))
    }

    static _GetActivePalette() {
        palName := (IsObject(this._cfg) && this._cfg.HasOwnProp("HudColorPreset")) ? this._cfg.HudColorPreset : "Standard"
        return UIConstants.GetColorPalette(palName)
    }

    static _GetSegmentPaletteColor(idx, pal) {
        if (idx == 1)
            return pal.live
        cycle := [pal.recActive, pal.chatAlert, pal.studioOn, pal.streamLive, pal.vcamOn, pal.live]
        return cycle[Mod(idx - 2, cycle.Length) + 1]
    }

    static _CaptureMorphSeedsAndSpawnSnake(cfg, state) {
        pal := this._GetActivePalette()
        seeds := []

        anchorX := state.HasOwnProp("savedX") ? state.savedX : (this._waLeft + this._W - 200)
        anchorY := state.HasOwnProp("savedY") ? state.savedY : (this._waTop + this._H - 80)
        pos := ComputeHudLayout(state, anchorX, anchorY)

        ; Capture real visible HUD pills so morph emanates directly from their desktop rects
        seeds.Push({ x: pos.micX - this._waLeft, y: pos.micY - this._waTop, w: pos.micW, h: pos.micH, colorHex: (state.isMuted ? pal.muted : pal.live), glyph: Chr(0xE720) })
        if (cfg.ShowExtraHuds && (cfg.EnableWS || cfg.EnableZoom)) {
            seeds.Push({ x: pos.recX - this._waLeft, y: pos.recY - this._waTop, w: pos.recW, h: pos.recH, colorHex: pal.recActive, glyph: Chr(0xE7C8) })
            seeds.Push({ x: pos.chatX - this._waLeft, y: pos.chatY - this._waTop, w: pos.chatW, h: pos.chatH, colorHex: pal.chatAlert, glyph: Chr(0xE8BD) })
        } else {
            seeds.Push({ x: pos.micX - this._waLeft, y: pos.micY - this._waTop, w: pos.micW, h: pos.micH, colorHex: pal.recActive, glyph: "" })
            seeds.Push({ x: pos.micX - this._waLeft, y: pos.micY - this._waTop, w: pos.micW, h: pos.micH, colorHex: pal.chatAlert, glyph: "" })
        }
        if (cfg.ShowExtraHuds && cfg.EnableWS) {
            seeds.Push({ x: pos.studioX - this._waLeft, y: pos.studioY - this._waTop, w: pos.studioW, h: pos.studioH, colorHex: pal.studioOn, glyph: Chr(0xE7F4) })
            seeds.Push({ x: pos.sceneX - this._waLeft, y: pos.sceneY - this._waTop, w: pos.sceneW, h: pos.sceneH, colorHex: pal.scene, glyph: "" })
            if (!cfg.HasOwnProp("ShowStreamHud") || cfg.ShowStreamHud) {
                seeds.Push({ x: pos.streamX - this._waLeft, y: pos.streamY - this._waTop, w: pos.streamW, h: pos.streamH, colorHex: pal.streamLive, glyph: Chr(0xE93E) })
            }
        } else {
            seeds.Push({ x: pos.micX - this._waLeft, y: pos.micY - this._waTop, w: pos.micW, h: pos.micH, colorHex: pal.studioOn, glyph: "" })
        }

        ; Ensure comfortable starting length of at least 5 pills
        while (seeds.Length < 5)
            seeds.Push({ x: pos.micX - this._waLeft, y: pos.micY - this._waTop, w: pos.micW, h: pos.micH, colorHex: this._GetSegmentPaletteColor(seeds.Length + 1, pal), glyph: "" })

        this._morphSeeds := seeds
        initLen := seeds.Length

        ; Anchor start cell right where the live Mic HUD was hovering, aimed safely toward open center
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
            snake.Push({ col: segCol, row: startRow, colorHex: this._GetSegmentPaletteColor(idx, pal) })
        }
        this._snake := snake
    }

    static _SpawnFood(kind := "normal", nowTick := -1) {
        if (nowTick < 0)
            nowTick := A_TickCount

        occupied := Map()
        for seg in this._snake
            occupied[seg.col "," seg.row] := true

        midCol := this._cols // 2
        candidates := []
        cIdx := 1
        while (cIdx <= this._cols - 2) {
            rIdx := 1
            while (rIdx <= this._rows - 2) {
                ; Never spawn beneath top-center Scoreboard pill
                if (!(rIdx <= this._sbSafeRows && Abs(cIdx - midCol) <= this._sbColsHalf)) {
                    if (!occupied.Has(cIdx "," rIdx))
                        candidates.Push({ col: cIdx, row: rIdx })
                }
                rIdx += 1
            }
            cIdx += 1
        }

        if (candidates.Length == 0) {
            ; Fallback over entire grid except snake body
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
            bornTick: nowTick,
            ttlMs: (kind = "bonus" ? 9000 : 0),
            pts: (kind = "bonus" ? 30 : 10)
        }
    }

    static _PauseLiveHuds(cfg, state) {
        if (state.HasOwnProp("breathTimerFn") && state.breathTimerFn)
            SetTimer(state.breathTimerFn, 0)
        if (state.HasOwnProp("sceneMarqueeTimerFn") && state.sceneMarqueeTimerFn)
            SetTimer(state.sceneMarqueeTimerFn, 0)
        UpdateVoiceMeterTimer(cfg, state)
        UpdateAutoDodgeTimer(cfg, state)
        for g in GetHudGuiList(state)
            try g.Hide()
    }

    static _BindGameHotkeys() {
        this._UnbindGameHotkeys()
        HotIf()
        bindings := [
            ["*Up",    (*) => this.QueueDirection(0, -1)],
            ["*Down",  (*) => this.QueueDirection(0, 1)],
            ["*Left",  (*) => this.QueueDirection(-1, 0)],
            ["*Right", (*) => this.QueueDirection(1, 0)],
            ["w",      (*) => this.QueueDirection(0, -1)],
            ["s",      (*) => this.QueueDirection(0, 1)],
            ["a",      (*) => this.QueueDirection(-1, 0)],
            ["d",      (*) => this.QueueDirection(1, 0)],
            ["p",      (*) => this.TogglePause()],
            ["Space",  (*) => this.TogglePause()],
            ["e",      (*) => this.ToggleEdgeMode()],
            ["r",      (*) => (this.Phase = "gameover" ? this.Restart() : 0)],
            ["Enter",  (*) => (this.Phase = "gameover" ? this.Restart() : 0)],
            ["Escape", (*) => this.Stop()]
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
    ; ZERO-ALLOCATION PERSISTENT GDI+ LAYERED CANVAS & RENDERING
    ; ==========================================================================

    static _InitCanvas() {
        this._DestroyCanvas()
        ; +AlwaysOnTop +ToolWindow -Caption +E0x80000 (WS_EX_LAYERED) +E0x20 (WS_EX_TRANSPARENT click-through)
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

        NumPut("Int", this._waLeft, "Int", this._waTop, this._ptWin, 0)
        NumPut("Int", this._W, "Int", this._H, this._szWin, 0)
        NumPut("Int64", 0, this._ptSrc, 0)
        NumPut("UInt", 0x01FF0000, this._blend, 0) ; AC_SRC_OVER, Alpha 255, AC_SRC_ALPHA
        return true
    }

    static _DestroyCanvas() {
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

    static _FillRounded(pGfx, x, y, w, h, radius, fillArgb, borderArgb := 0, borderW := 1.5) {
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

    static _RenderFrame(nowTick := -1) {
        if (!this._pGraphics || !this._pBits || !IsObject(this._gui))
            return
        if (nowTick < 0)
            nowTick := A_TickCount

        pGfx := this._pGraphics
        pal := this._GetActivePalette()
        isDark := Theme.IsDarkMode()

        ; Fast transparent clear (alpha = 0 everywhere so underlying desktop shows cleanly)
        DllCall("ntdll\RtlZeroMemory", "Ptr", this._pBits, "Ptr", this._W * this._H * 4)

        ; 1. Subtle Translucent Play-Area Corner Brackets / Edge Hint (no opaque window)
        this._DrawEdgeHints(pGfx, pal)

        ; 2. Draw Expanding Ripples (Morph & Eat bursts)
        this._DrawRipples(pGfx, nowTick)

        ; 3. Draw Food Collectible
        if (IsObject(this._food) && this.Phase != "morph")
            this._DrawFood(pGfx, pal, nowTick)

        ; 4. Draw Snake Segments (Tail -> Head) with Morph Interpolation
        this._DrawSnake(pGfx, pal, nowTick)

        ; 5. Draw Floating Eat Popups (+10 / +30)
        this._DrawPopups(pGfx, nowTick)

        ; 6. Draw Top Scoreboard Pill (compact translucent PresenterSync style)
        this._DrawScoreboard(pGfx, pal, isDark)

        ; 7. Draw Pause or Game Over Floating Pill Banner
        if (this.Phase = "paused" || this.Phase = "gameover")
            this._DrawStatusBanner(pGfx, pal, isDark)

        DllCall("UpdateLayeredWindow", "Ptr", this._gui.Hwnd, "Ptr", 0, "Ptr", this._ptWin, "Ptr", this._szWin, "Ptr", this._hdcMem, "Ptr", this._ptSrc, "UInt", 0, "Ptr", this._blend, "UInt", 2, "Int")
    }

    static _DrawEdgeHints(pGfx, pal) {
        gx := Float(this._gridOffX)
        gy := Float(this._gridOffY)
        gw := Float(this._cols * this._cell)
        gh := Float(this._rows * this._cell)
        edgeColor := this._edgeWrap ? Gdip.HexToArgb("38BDF8", 115) : Gdip.HexToArgb(pal.live, 95)

        pPen := 0
        DllCall("gdiplus\GdipCreatePen1", "UInt", edgeColor, "Float", Float(1.6 * this._dpi), "Int", 2, "Ptr*", &pPen)
        if (!pPen)
            return
        if (this._edgeWrap)
            DllCall("gdiplus\GdipSetPenDashStyle", "Ptr", pPen, "Int", 1)

        cLen := Float(Max(18, Round(26 * this._dpi)))
        ; 4 crisp corner brackets + faint perimeter hairlines so boundaries are visible yet airy
        DllCall("gdiplus\GdipDrawLine", "Ptr", pGfx, "Ptr", pPen, "Float", gx, "Float", gy, "Float", gx + cLen, "Float", gy)
        DllCall("gdiplus\GdipDrawLine", "Ptr", pGfx, "Ptr", pPen, "Float", gx, "Float", gy, "Float", gx, "Float", gy + cLen)

        DllCall("gdiplus\GdipDrawLine", "Ptr", pGfx, "Ptr", pPen, "Float", gx + gw - cLen, "Float", gy, "Float", gx + gw, "Float", gy)
        DllCall("gdiplus\GdipDrawLine", "Ptr", pGfx, "Ptr", pPen, "Float", gx + gw, "Float", gy, "Float", gx + gw, "Float", gy + cLen)

        DllCall("gdiplus\GdipDrawLine", "Ptr", pGfx, "Ptr", pPen, "Float", gx, "Float", gy + gh - cLen, "Float", gx, "Float", gy + gh)
        DllCall("gdiplus\GdipDrawLine", "Ptr", pGfx, "Ptr", pPen, "Float", gx, "Float", gy + gh, "Float", gx + cLen, "Float", gy + gh)

        DllCall("gdiplus\GdipDrawLine", "Ptr", pGfx, "Ptr", pPen, "Float", gx + gw - cLen, "Float", gy + gh, "Float", gx + gw, "Float", gy + gh)
        DllCall("gdiplus\GdipDrawLine", "Ptr", pGfx, "Ptr", pPen, "Float", gx + gw, "Float", gy + gh - cLen, "Float", gx + gw, "Float", gy + gh)
        DllCall("gdiplus\GdipDeletePen", "Ptr", pPen)

        ; Very subtle perimeter frame
        fArgb := this._edgeWrap ? Gdip.HexToArgb("38BDF8", 36) : Gdip.HexToArgb(pal.live, 34)
        pFramePen := 0
        DllCall("gdiplus\GdipCreatePen1", "UInt", fArgb, "Float", 1.0, "Int", 2, "Ptr*", &pFramePen)
        if (pFramePen) {
            DllCall("gdiplus\GdipDrawRectangle", "Ptr", pGfx, "Ptr", pFramePen, "Float", gx, "Float", gy, "Float", gw, "Float", gh)
            DllCall("gdiplus\GdipDeletePen", "Ptr", pFramePen)
        }
    }

    static _DrawFood(pGfx, pal, nowTick) {
        f := this._food
        cx := this._gridOffX + (f.col + 0.5) * this._cell
        cy := this._gridOffY + (f.row + 0.5) * this._cell
        pulse := 0.5 + 0.5 * Sin(nowTick / 150.0)
        isBonus := (f.kind = "bonus")

        baseSize := this._cell * (isBonus ? 0.86 : 0.78)
        sz := baseSize + pulse * (2.5 * this._dpi)
        fx := cx - sz / 2.0
        fy := cy - sz / 2.0

        haloHex := isBonus ? "F59E0B" : "FB7185"
        bodyHex := isBonus ? "F59E0B" : "E11D48"
        rimHex := isBonus ? "FDE68A" : "FDA4AF"

        ; Soft outer halo
        haloSz := sz + (7.0 + pulse * 4.0) * this._dpi
        this._FillRounded(pGfx, cx - haloSz / 2.0, cy - haloSz / 2.0, haloSz, haloSz, haloSz / 2.0, Gdip.HexToArgb(haloHex, Round(55 + pulse * 45)), 0, 0)

        ; Fruit pill body
        this._FillRounded(pGfx, fx, fy, sz, sz, sz / 2.0, Gdip.HexToArgb(bodyHex, 245), Gdip.HexToArgb(rimHex, 255), 1.6)

        ; Cute stem / icon
        if (isBonus) {
            Gdip.DrawText(pGfx, Chr(0x2605), "Segoe UI Symbol", Max(9.0, 11.0 * this._dpi), 1, 0xFFFFFFFF, fx, fy - 0.5, sz, sz, 1, 1, 0, true)
            if (f.ttlMs > 0) {
                remFrac := Max(0.0, 1.0 - (nowTick - f.bornTick) / Float(f.ttlMs))
                barW := sz * remFrac
                this._FillRounded(pGfx, cx - sz / 2.0, fy + sz + 3, Max(2.0, barW), 3.0 * this._dpi, 1.5, Gdip.HexToArgb("FCD34D", 230), 0, 0)
            }
        } else {
            ; Leaf highlight & specular glint
            this._FillRounded(pGfx, cx - 2.0 * this._dpi, fy - 3.5 * this._dpi, 6.0 * this._dpi, 4.0 * this._dpi, 2.0 * this._dpi, Gdip.HexToArgb("34D399", 240), 0, 0)
            this._FillRounded(pGfx, fx + sz * 0.22, fy + sz * 0.20, sz * 0.26, sz * 0.18, sz * 0.09, 0xCCFFFFFF, 0, 0)
        }
    }

    static _DrawSnake(pGfx, pal, nowTick) {
        count := this._snake.Length
        if (count == 0)
            return

        morphFrac := 1.0
        if (this.Phase = "morph") {
            lin := Min(1.0, Max(0.0, (nowTick - this._morphStartTick) / Float(this._morphDurationMs)))
            morphFrac := 1.0 - ((1.0 - lin) ** 3) ; Smooth ease-out cubic
        }

        pad := Max(2.0, 2.5 * this._dpi)
        segTargetSz := this._cell - pad * 2.0

        ; Draw from Tail -> Head so Head always renders crisp on top
        idx := count
        while (idx >= 1) {
            seg := this._snake[idx]
            targetX := Float(this._gridOffX + seg.col * this._cell + pad)
            targetY := Float(this._gridOffY + seg.row * this._cell + pad)
            targetW := Float(segTargetSz)
            targetH := Float(segTargetSz)

            if (morphFrac < 1.0 && idx <= this._morphSeeds.Length) {
                seed := this._morphSeeds[idx]
                sx := Float(seed.x) + (targetX - Float(seed.x)) * morphFrac
                sy := Float(seed.y) + (targetY - Float(seed.y)) * morphFrac
                sw := Float(seed.w) + (targetW - Float(seed.w)) * morphFrac
                sh := Float(seed.h) + (targetH - Float(seed.h)) * morphFrac
                cHex := seed.colorHex
            } else {
                ; Gentle taper toward the tail tip
                taper := (idx == count && count > 3) ? 0.16 : ((idx == count - 1 && count > 4) ? 0.08 : 0.0)
                inset := targetW * taper * 0.5
                sx := targetX + inset
                sy := targetY + inset
                sw := targetW - inset * 2.0
                sh := targetH - inset * 2.0
                cHex := seg.colorHex
            }

            if (this.Phase = "gameover" && idx == 1)
                cHex := pal.muted

            ; Draw bridge between adjacent non-wrapped cells
            if (morphFrac >= 1.0 && idx > 1) {
                prev := this._snake[idx - 1]
                if (Abs(prev.col - seg.col) + Abs(prev.row - seg.row) == 1) {
                    px := Float(this._gridOffX + prev.col * this._cell + pad)
                    py := Float(this._gridOffY + prev.row * this._cell + pad)
                    jx := (sx + px) / 2.0 + (targetW * 0.12)
                    jy := (sy + py) / 2.0 + (targetH * 0.12)
                    jw := targetW * 0.76
                    this._FillRounded(pGfx, jx, jy, jw, jw, jw / 2.0, Gdip.HexToArgb(cHex, 210), 0, 0)
                }
            }

            radius := (idx == 1) ? Min(sw, sh) * 0.36 : Min(sw, sh) * 0.42
            borderCol := (idx == 1) ? 0xE6FFFFFF : Gdip.HexToArgb(cHex, 255)
            this._FillRounded(pGfx, sx, sy, sw, sh, radius, Gdip.HexToArgb(cHex, 240), borderCol, (idx == 1) ? 1.8 : 1.1)

            ; Subtle glossy pill shine on body
            this._FillRounded(pGfx, sx + sw * 0.18, sy + 2.0, sw * 0.64, Max(2.0, sh * 0.16), 2.0, 0x42FFFFFF, 0, 0)

            ; Expressive eyes & forked tongue on Head
            if (idx == 1)
                this._DrawHeadFeatures(pGfx, sx, sy, sw, sh, nowTick)

            idx -= 1
        }
    }

    static _DrawHeadFeatures(pGfx, hx, hy, hw, hh, nowTick) {
        dx := this._dir.x
        dy := this._dir.y
        cx := hx + hw / 2.0
        cy := hy + hh / 2.0
        eyeSize := Max(4.5, hw * 0.24)
        pupilSize := Max(2.2, eyeSize * 0.52)

        fwd := hw * 0.17
        side := hw * 0.21
        e1x := cx + dx * fwd - dy * side
        e1y := cy + dy * fwd + dx * side
        e2x := cx + dx * fwd + dy * side
        e2y := cy + dy * fwd - dx * side

        pWhite := 0, pDark := 0
        DllCall("gdiplus\GdipCreateSolidFill", "UInt", 0xFFF8FAFC, "Ptr*", &pWhite)
        DllCall("gdiplus\GdipCreateSolidFill", "UInt", 0xFF0F172A, "Ptr*", &pDark)
        if (pWhite && pDark) {
            DllCall("gdiplus\GdipFillEllipse", "Ptr", pGfx, "Ptr", pWhite, "Float", e1x - eyeSize / 2, "Float", e1y - eyeSize / 2, "Float", eyeSize, "Float", eyeSize)
            DllCall("gdiplus\GdipFillEllipse", "Ptr", pGfx, "Ptr", pWhite, "Float", e2x - eyeSize / 2, "Float", e2y - eyeSize / 2, "Float", eyeSize, "Float", eyeSize)
            DllCall("gdiplus\GdipFillEllipse", "Ptr", pGfx, "Ptr", pDark, "Float", e1x - pupilSize / 2 + dx * 1.1, "Float", e1y - pupilSize / 2 + dy * 1.1, "Float", pupilSize, "Float", pupilSize)
            DllCall("gdiplus\GdipFillEllipse", "Ptr", pGfx, "Ptr", pDark, "Float", e2x - pupilSize / 2 + dx * 1.1, "Float", e2y - pupilSize / 2 + dy * 1.1, "Float", pupilSize, "Float", pupilSize)
        }
        if (pWhite)
            DllCall("gdiplus\GdipDeleteBrush", "Ptr", pWhite)
        if (pDark)
            DllCall("gdiplus\GdipDeleteBrush", "Ptr", pDark)

        ; Quick periodic forked tongue while playing
        if (this.Phase = "playing" && Mod(Floor(nowTick / 180), 4) == 0) {
            tPen := 0
            DllCall("gdiplus\GdipCreatePen1", "UInt", 0xFFFB7185, "Float", Float(1.6 * this._dpi), "Int", 2, "Ptr*", &tPen)
            if (tPen) {
                tx0 := cx + dx * (hw * 0.48)
                ty0 := cy + dy * (hh * 0.48)
                tx1 := tx0 + dx * (5.5 * this._dpi)
                ty1 := ty0 + dy * (5.5 * this._dpi)
                DllCall("gdiplus\GdipDrawLine", "Ptr", pGfx, "Ptr", tPen, "Float", tx0, "Float", ty0, "Float", tx1, "Float", ty1)
                DllCall("gdiplus\GdipDrawLine", "Ptr", pGfx, "Ptr", tPen, "Float", tx1, "Float", ty1, "Float", tx1 + (dx * 3 - dy * 2.5) * this._dpi, "Float", ty1 + (dy * 3 + dx * 2.5) * this._dpi)
                DllCall("gdiplus\GdipDrawLine", "Ptr", pGfx, "Ptr", tPen, "Float", tx1, "Float", ty1, "Float", tx1 + (dx * 3 + dy * 2.5) * this._dpi, "Float", ty1 + (dy * 3 - dx * 2.5) * this._dpi)
                DllCall("gdiplus\GdipDeletePen", "Ptr", tPen)
            }
        }
    }

    static _DrawRipples(pGfx, nowTick) {
        kept := []
        for rp in this._ripples {
            age := nowTick - rp.bornTick
            if (age < 420) {
                t := age / 420.0
                r := Float(this._cell * (0.4 + t * 1.45))
                alpha := Round((1.0 - t) * 190)
                this._FillRounded(pGfx, rp.x - r, rp.y - r, r * 2.0, r * 2.0, r, 0x00000000, Gdip.HexToArgb(rp.colorHex, alpha), 2.2)
                kept.Push(rp)
            }
        }
        this._ripples := kept
    }

    static _DrawPopups(pGfx, nowTick) {
        kept := []
        for pop in this._popups {
            age := nowTick - pop.bornTick
            if (age < 650) {
                t := age / 650.0
                py := pop.y - t * (26.0 * this._dpi)
                alpha := Round((1.0 - t) * 255)
                argb := Gdip.HexToArgb(pop.colorHex, alpha)
                Gdip.DrawText(pGfx, pop.text, "Segoe UI", 10.5 * this._dpi, 1, argb, pop.x - 32, py - 14, 64, 24, 1, 1, 0, true)
                kept.Push(pop)
            }
        }
        this._popups := kept
    }

    static _DrawScoreboard(pGfx, pal, isDark) {
        sbW := Min(Float(Round(570 * this._dpi)), Float(this._W - 32))
        sbH := Float(Round(34 * this._dpi))
        sbX := (this._W - sbW) / 2.0
        sbY := Float(Round(8 * this._dpi))

        bgArgb := isDark ? 0xDE1C1E24 : 0xEBFFFFFF
        brdArgb := Gdip.HexToArgb(pal.live, 220)
        txtArgb := isDark ? 0xFFF3F4F6 : 0xFF18181B
        mutedArgb := isDark ? 0xFFB0B7C5 : 0xFF52525B

        this._FillRounded(pGfx, sbX, sbY, sbW, sbH, sbH / 2.0, bgArgb, brdArgb, 1.5)

        ; Left LIVE pill badge inside scoreboard
        badgeW := Float(Round(96 * this._dpi))
        badgeH := sbH - 8
        badgeX := sbX + 5
        badgeY := sbY + 4
        this._FillRounded(pGfx, badgeX, badgeY, badgeW, badgeH, badgeH / 2.0, Gdip.HexToArgb(pal.live, 245), 0, 0)
        Gdip.DrawText(pGfx, "HUD SNAKE", "Segoe UI", 8.5 * this._dpi, 1, 0xFFFFFFFF, badgeX, badgeY, badgeW, badgeH, 1, 1, 0, true)

        ; Center telemetry metrics
        speedMult := Format("{:.1f}x", 135.0 / Max(68, this._stepMs))
        edgeTag := this._edgeWrap ? "WRAP" : "WALLS"
        statsText := Format("SCORE {}   •   BEST {}   •   LEN {}   •   {}   •   EDGE: {}",
            this._score, this._highScore, this._snake.Length, speedMult, edgeTag)
        statX := badgeX + badgeW + 10
        hintW := Float(Round(146 * this._dpi))
        statW := Max(60.0, sbW - (statX - sbX) - hintW - 10)
        Gdip.DrawText(pGfx, statsText, "Segoe UI", 9.0 * this._dpi, 1, txtArgb, statX, sbY, statW, sbH, 0, 1, 0, true)

        ; Right compact control legend
        Gdip.DrawText(pGfx, "P Pause • E Edge • Esc Exit", "Segoe UI", 7.8 * this._dpi, 0, mutedArgb, sbX + sbW - hintW - 10, sbY, hintW, sbH, 2, 1, 0, true)
    }

    static _DrawStatusBanner(pGfx, pal, isDark) {
        banW := Min(Float(Round(500 * this._dpi)), Float(this._W - 40))
        banH := Float(Round(52 * this._dpi))
        banX := (this._W - banW) / 2.0
        banY := Float(Round(62 * this._dpi))

        isDead := (this.Phase = "gameover")
        bgArgb := isDark ? 0xEC1A1C22 : 0xF2FFFFFF
        accentHex := isDead ? pal.muted : pal.chatAlert
        txtArgb := isDark ? 0xFFF8FAFC : 0xFF18181B
        subArgb := isDark ? 0xFFCBD5E1 : 0xFF475569

        this._FillRounded(pGfx, banX, banY, banW, banH, 12.0, bgArgb, Gdip.HexToArgb(accentHex, 240), 2.0)

        if (isDead) {
            reasonTxt := (this._deathReason = "wall") ? "Hit Monitor Edge" : "Self-Collision"
            topMsg := Format("GAME OVER ({})  —  FINAL SCORE: {}{}", reasonTxt, this._score, this._bestBeaten ? "  ★ NEW BEST!" : "")
            subMsg := "Press [R] / [Space] / [Enter] to Play Again   •   Press [Esc] or [Alt+Ctrl+Shift+S] to Restore HUD"
        } else {
            topMsg := "HUD SNAKE PAUSED"
            subMsg := "Press [P] or [Space] to Resume   •   [E] Toggle Walls/Wrap   •   [Esc] Restore HUD"
        }
        Gdip.DrawText(pGfx, topMsg, "Segoe UI", 10.5 * this._dpi, 1, txtArgb, banX + 12, banY + 4, banW - 24, banH * 0.50, 1, 1, 0, true)
        Gdip.DrawText(pGfx, subMsg, "Segoe UI", 8.3 * this._dpi, 0, subArgb, banX + 12, banY + banH * 0.48, banW - 24, banH * 0.46, 1, 1, 0, true)
    }
}
