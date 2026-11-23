; ==============================================================================
; Module: GameBlockDrop.ahk
; Description: Milestone M7.1 — Puzzle Arcade: Neon Block Drop (v8.6.1, ^!+d)
;              * InteractiveMouse := false (+E0x20 click-through translucent
;                10x20 neon-glass well over live desktop).
;              * Wireframe/neon-glass I, O, T, S, Z, J, L tetrominoes.
;              * 7-bag randomizer (shuffled permutation of all 7 pieces).
;              * Authentic SRS rotation + JLSTZ and I wall-kick offset tables.
;              * Ghost-piece landing guide, Hold (C/Shift, once per drop),
;                Next 3 preview, 500ms lock-delay grace (15 move-reset cap),
;                Soft Drop (Down/S) & Hard Drop (Space).
;              * Line-clear shockwaves, T-Spin & Back-to-Back bonuses, level
;                speed curve, and [ArcadeHighScores] "block_drop" persistence.
; ==============================================================================

#Include "%A_LineFile%\..\..\HudArcadeBase.ahk"

class GameBlockDrop {
    static IsActive := false
    static Phase := "idle" ; "idle" | "playing" | "paused" | "gameover"
    static COLS := 10
    static ROWS := 20
    static LOCK_DELAY_SEC := 0.50
    static MAX_LOCK_RESETS := 15

    static _surf := ""
    static _cfg := ""
    static _state := ""
    static _savedPolling := ""
    static _boundHotkeys := []
    static _tickFn := ""
    static _lastUs := 0.0
    static _headless := false

    static _board := [] ; 20 rows x 10 cols ("" or kind string)
    static _bag := []
    static _queue := []

    static _curKind := ""
    static _curX := 3
    static _curY := 0
    static _curRot := 0
    static _holdKind := ""
    static _holdUsed := false

    static _score := 0
    static _highScore := 0
    static _lines := 0
    static _level := 1
    static _b2b := false
    static _combo := -1

    static _gravAccum := 0.0
    static _lockTimer := 0.0
    static _lockResets := 0
    static _softDrop := false
    static _lastWasRotate := false
    static _lastKickIdx := 0

    static _shockwaves := [] ; { row, timer, maxTimer, argb }
    static _popups := []     ; { text, timer, maxTimer, argb }
    static _gpPrevBtn := 0
    static _gpMoveCooldown := 0.0

    ; Piece colors: { fill, glow, wire }
    static _COLORS := Map(
        "I", { fill: 0xAA06B6D4, glow: 0x5522D3EE, wire: 0xFF67E8F9 },
        "O", { fill: 0xAAEAB308, glow: 0x55FACC15, wire: 0xFFFEF08A },
        "T", { fill: 0xAAA855F7, glow: 0x55C084FC, wire: 0xFFE9D5FF },
        "S", { fill: 0xAA22C55E, glow: 0x554ADE80, wire: 0xFFBBF7D0 },
        "Z", { fill: 0xAAEF4444, glow: 0x55F87171, wire: 0xFFFECACA },
        "J", { fill: 0xAA3B82F6, glow: 0x5560A5FA, wire: 0xFFBFDBFE },
        "L", { fill: 0xAAF97316, glow: 0x55FB923C, wire: 0xFFFED7AA }
    )

    ; SRS shapes in local bounding box (4 rotations each: 0, 1, 2, 3)
    static _SHAPES := Map(
        "I", [
            [[0,1],[1,1],[2,1],[3,1]],
            [[2,0],[2,1],[2,2],[2,3]],
            [[0,2],[1,2],[2,2],[3,2]],
            [[1,0],[1,1],[1,2],[1,3]]
        ],
        "O", [
            [[1,0],[2,0],[1,1],[2,1]],
            [[1,0],[2,0],[1,1],[2,1]],
            [[1,0],[2,0],[1,1],[2,1]],
            [[1,0],[2,0],[1,1],[2,1]]
        ],
        "T", [
            [[1,0],[0,1],[1,1],[2,1]],
            [[1,0],[1,1],[2,1],[1,2]],
            [[0,1],[1,1],[2,1],[1,2]],
            [[1,0],[0,1],[1,1],[1,2]]
        ],
        "S", [
            [[1,0],[2,0],[0,1],[1,1]],
            [[1,0],[1,1],[2,1],[2,2]],
            [[1,1],[2,1],[0,2],[1,2]],
            [[0,0],[0,1],[1,1],[1,2]]
        ],
        "Z", [
            [[0,0],[1,0],[1,1],[2,1]],
            [[2,0],[1,1],[2,1],[1,2]],
            [[0,1],[1,1],[1,2],[2,2]],
            [[1,0],[0,1],[1,1],[0,2]]
        ],
        "J", [
            [[0,0],[0,1],[1,1],[2,1]],
            [[1,0],[2,0],[1,1],[1,2]],
            [[0,1],[1,1],[2,1],[2,2]],
            [[1,0],[1,1],[0,2],[1,2]]
        ],
        "L", [
            [[2,0],[0,1],[1,1],[2,1]],
            [[1,0],[1,1],[1,2],[2,2]],
            [[0,1],[1,1],[2,1],[0,2]],
            [[0,0],[1,0],[1,1],[1,2]]
        ]
    )

    ; SRS Wall Kick Offset Tables (screen coords: +x right, +y down)
    static _KICKS_JLSTZ := Map(
        "0>1", [[0,0],[-1,0],[-1,-1],[0,2],[-1,2]],
        "1>0", [[0,0],[1,0],[1,1],[0,-2],[1,-2]],
        "1>2", [[0,0],[1,0],[1,1],[0,-2],[1,-2]],
        "2>1", [[0,0],[-1,0],[-1,-1],[0,2],[-1,2]],
        "2>3", [[0,0],[1,0],[1,-1],[0,2],[1,2]],
        "3>2", [[0,0],[-1,0],[-1,1],[0,-2],[-1,-2]],
        "3>0", [[0,0],[-1,0],[-1,1],[0,-2],[-1,-2]],
        "0>3", [[0,0],[1,0],[1,-1],[0,2],[1,2]]
    )

    static _KICKS_I := Map(
        "0>1", [[0,0],[-2,0],[1,0],[-2,1],[1,-2]],
        "1>0", [[0,0],[2,0],[-1,0],[2,-1],[-1,2]],
        "1>2", [[0,0],[-1,0],[2,0],[-1,-2],[2,1]],
        "2>1", [[0,0],[1,0],[-2,0],[1,2],[-2,-1]],
        "2>3", [[0,0],[2,0],[-1,0],[2,-1],[-1,2]],
        "3>2", [[0,0],[-2,0],[1,0],[-2,1],[1,-2]],
        "3>0", [[0,0],[1,0],[-2,0],[1,2],[-2,-1]],
        "0>3", [[0,0],[-1,0],[2,0],[-1,-2],[2,1]]
    )

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
            interactiveMouse: false,
            title: "PresenterSyncBlockDrop",
            headless: this._headless
        })
        if (!IsObject(this._surf))
            return false

        this.IsActive := true
        HudArcadeBase.RegisterActiveGame(this, "block_drop")
        this._highScore := HudArcadeBase.LoadHighScore(cfg, "block_drop")
        this._ResetMatch()

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
        this._softDrop := false
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
        HudArcadeBase.ClearActiveGame("block_drop")
    }

    static _BindKeys(cfg) {
        condFn := (*) => GameBlockDrop.IsActive
        bindings := [
            { key: "$Left", fn: (*) => GameBlockDrop.Move(-1) },
            { key: "$Right", fn: (*) => GameBlockDrop.Move(1) },
            { key: "$a", fn: (*) => GameBlockDrop.Move(-1) },
            { key: "$d", fn: (*) => GameBlockDrop.Move(1) },
            { key: "$Down", fn: (*) => GameBlockDrop.SetSoftDrop(true) },
            { key: "$Down up", fn: (*) => GameBlockDrop.SetSoftDrop(false) },
            { key: "$s", fn: (*) => GameBlockDrop.SetSoftDrop(true) },
            { key: "$s up", fn: (*) => GameBlockDrop.SetSoftDrop(false) },
            { key: "$Up", fn: (*) => GameBlockDrop.Rotate(1) },
            { key: "$x", fn: (*) => GameBlockDrop.Rotate(1) },
            { key: "$w", fn: (*) => GameBlockDrop.Rotate(1) },
            { key: "$z", fn: (*) => GameBlockDrop.Rotate(-1) },
            { key: "$LCtrl", fn: (*) => GameBlockDrop.Rotate(-1) },
            { key: "$RCtrl", fn: (*) => GameBlockDrop.Rotate(-1) },
            { key: "$Space", fn: (*) => GameBlockDrop.HardDrop() },
            { key: "$c", fn: (*) => GameBlockDrop.Hold() },
            { key: "$LShift", fn: (*) => GameBlockDrop.Hold() },
            { key: "$RShift", fn: (*) => GameBlockDrop.Hold() },
            { key: "$p", fn: (*) => GameBlockDrop.TogglePause() },
            { key: "$r", fn: (*) => GameBlockDrop.Restart() },
            { key: "$Escape", fn: (*) => GameBlockDrop.Stop() }
        ]
        HudArcadeBase.BindKeysSafe(cfg, bindings, this._boundHotkeys, condFn)
    }

    static _ResetMatch() {
        this.Phase := "playing"
        this._board := []
        Loop this.ROWS {
            rowArr := []
            Loop this.COLS
                rowArr.Push("")
            this._board.Push(rowArr)
        }
        this._bag := []
        this._queue := []
        this._holdKind := ""
        this._holdUsed := false
        this._score := 0
        this._lines := 0
        this._level := 1
        this._b2b := false
        this._combo := -1
        this._gravAccum := 0.0
        this._lockTimer := 0.0
        this._lockResets := 0
        this._softDrop := false
        this._lastWasRotate := false
        this._lastKickIdx := 0
        this._shockwaves := []
        this._popups := []
        this._gpPrevBtn := 0
        this._gpMoveCooldown := 0.0

        this._EnsureQueue()
        this._SpawnNextPiece()
    }

    static Restart() {
        if (!this.IsActive)
            return
        this._ResetMatch()
    }

    static TogglePause() {
        if (!this.IsActive || this.Phase = "gameover")
            return
        this.Phase := (this.Phase = "paused") ? "playing" : "paused"
    }

    static SetSoftDrop(on) {
        this._softDrop := !!on
    }

    static _RefillBag() {
        pieces := ["I", "O", "T", "S", "Z", "J", "L"]
        i := pieces.Length
        while (i > 1) {
            j := Random(1, i)
            tmp := pieces[i]
            pieces[i] := pieces[j]
            pieces[j] := tmp
            i--
        }
        for _, p in pieces
            this._bag.Push(p)
    }

    static _DrawFromBag() {
        if (this._bag.Length == 0)
            this._RefillBag()
        return this._bag.RemoveAt(1)
    }

    static _EnsureQueue() {
        while (this._queue.Length < 4)
            this._queue.Push(this._DrawFromBag())
    }

    static _SpawnNextPiece() {
        this._EnsureQueue()
        kind := this._queue.RemoveAt(1)
        this._EnsureQueue()
        this._SpawnKind(kind)
    }

    static _SpawnKind(kind) {
        this._curKind := kind
        this._curRot := 0
        this._curX := 3
        this._curY := (kind = "I") ? -1 : 0
        this._gravAccum := 0.0
        this._lockTimer := 0.0
        this._lockResets := 0
        this._lastWasRotate := false
        this._lastKickIdx := 0
        if (!this._Fits(this._curKind, this._curX, this._curY, this._curRot)) {
            this._TriggerGameOver()
        }
    }

    static _TriggerGameOver() {
        this.Phase := "gameover"
        if (this._score > this._highScore) {
            this._highScore := this._score
            HudArcadeBase.SaveHighScore(this._cfg, "block_drop", this._highScore)
        }
    }

    static _Fits(kind, px, py, rot) {
        cells := this._SHAPES[kind][(rot & 3) + 1]
        for _, c in cells {
            bx := px + c[1]
            by := py + c[2]
            if (bx < 0 || bx >= this.COLS || by >= this.ROWS)
                return false
            if (by >= 0 && this._board[by + 1][bx + 1] != "")
                return false
        }
        return true
    }

    static _IsGrounded() {
        return !this._Fits(this._curKind, this._curX, this._curY + 1, this._curRot)
    }

    static _ResetLockIfGrounded() {
        if (this._IsGrounded() && this._lockResets < this.MAX_LOCK_RESETS) {
            this._lockTimer := 0.0
            this._lockResets++
        }
    }

    static Move(dx) {
        if (!this.IsActive || this.Phase != "playing")
            return false
        if (this._Fits(this._curKind, this._curX + dx, this._curY, this._curRot)) {
            this._curX += dx
            this._lastWasRotate := false
            this._ResetLockIfGrounded()
            return true
        }
        return false
    }

    static Rotate(dir) {
        if (!this.IsActive || this.Phase != "playing")
            return false
        if (this._curKind = "O")
            return true
        oldRot := this._curRot & 3
        newRot := (oldRot + (dir > 0 ? 1 : 3)) & 3
        key := oldRot ">" newRot
        kicks := (this._curKind = "I") ? this._KICKS_I[key] : this._KICKS_JLSTZ[key]
        for idx, off in kicks {
            nx := this._curX + off[1]
            ny := this._curY + off[2]
            if (this._Fits(this._curKind, nx, ny, newRot)) {
                this._curX := nx
                this._curY := ny
                this._curRot := newRot
                this._lastWasRotate := true
                this._lastKickIdx := idx
                this._ResetLockIfGrounded()
                return true
            }
        }
        return false
    }

    static Hold() {
        if (!this.IsActive || this.Phase != "playing" || this._holdUsed)
            return false
        prevHold := this._holdKind
        this._holdKind := this._curKind
        this._holdUsed := true
        if (prevHold = "")
            this._SpawnNextPiece()
        else
            this._SpawnKind(prevHold)
        return true
    }

    static HardDrop() {
        if (!this.IsActive || this.Phase != "playing")
            return 0
        dropped := 0
        while (this._Fits(this._curKind, this._curX, this._curY + 1, this._curRot)) {
            this._curY++
            dropped++
        }
        if (dropped > 0) {
            this._score += dropped * 2
            this._lastWasRotate := false
        }
        this._LockCurrentPiece()
        return dropped
    }

    static _ComputeGhostY() {
        gy := this._curY
        while (this._Fits(this._curKind, this._curX, gy + 1, this._curRot))
            gy++
        return gy
    }

    static _DetectTSpin() {
        if (this._curKind != "T" || !this._lastWasRotate)
            return ""
        ; 4 corners of 3x3 T bounding box
        cx := this._curX
        cy := this._curY
        corners := [[cx, cy], [cx + 2, cy], [cx, cy + 2], [cx + 2, cy + 2]]
        occ := 0
        for _, pt in corners {
            px := pt[1], py := pt[2]
            if (px < 0 || px >= this.COLS || py < 0 || py >= this.ROWS || this._board[py + 1][px + 1] != "")
                occ++
        }
        if (occ < 3)
            return ""
        return (this._lastKickIdx == 5) ? "full" : "full"
    }

    static _LockCurrentPiece() {
        cells := this._SHAPES[this._curKind][(this._curRot & 3) + 1]
        aboveTop := false
        for _, c in cells {
            bx := this._curX + c[1]
            by := this._curY + c[2]
            if (by < 0) {
                aboveTop := true
                continue
            }
            if (bx >= 0 && bx < this.COLS && by < this.ROWS)
                this._board[by + 1][bx + 1] := this._curKind
        }

        tspin := this._DetectTSpin()
        clearedRows := []
        r := this.ROWS
        while (r >= 1) {
            full := true
            for _, cell in this._board[r] {
                if (cell = "") {
                    full := false
                    break
                }
            }
            if (full) {
                clearedRows.Push(r - 1)
                this._board.RemoveAt(r)
                newRow := []
                Loop this.COLS
                    newRow.Push("")
                this._board.InsertAt(1, newRow)
            } else {
                r--
            }
        }

        n := clearedRows.Length
        if (n > 0) {
            this._combo++
            this._lines += n
            this._level := 1 + Floor(this._lines / 10)
            base := 0
            label := ""
            if (tspin != "") {
                base := (n == 1) ? 800 : (n == 2) ? 1200 : 1600
                label := (n == 1) ? "T-SPIN SINGLE" : (n == 2) ? "T-SPIN DOUBLE" : "T-SPIN TRIPLE"
            } else {
                base := (n == 1) ? 100 : (n == 2) ? 300 : (n == 3) ? 500 : 800
                label := (n == 1) ? "SINGLE" : (n == 2) ? "DOUBLE" : (n == 3) ? "TRIPLE" : "TETRIS!"
            }
            isDifficult := (n == 4 || tspin != "")
            mult := (isDifficult && this._b2b) ? 1.5 : 1.0
            pts := Round(base * mult * this._level)
            if (this._combo > 0)
                pts += 50 * this._combo * this._level
            this._score += pts
            this._b2b := isDifficult

            waveCol := (n == 4 || tspin != "") ? 0xFFFACC15 : 0xFF38BDF8
            for _, cr in clearedRows
                this._shockwaves.Push({ row: cr, timer: 0.35, maxTimer: 0.35, argb: waveCol })
            popTxt := (mult > 1.0 ? "B2B " : "") label " +" pts
            this._popups.Push({ text: popTxt, timer: 1.0, maxTimer: 1.0, argb: waveCol })
        } else {
            this._combo := -1
            if (tspin != "") {
                pts := 400 * this._level
                this._score += pts
                this._popups.Push({ text: "T-SPIN +" pts, timer: 0.9, maxTimer: 0.9, argb: 0xFFC084FC })
            }
        }

        if (this._score > this._highScore) {
            this._highScore := this._score
            HudArcadeBase.SaveHighScore(this._cfg, "block_drop", this._highScore)
        }

        if (aboveTop) {
            this._TriggerGameOver()
            return
        }

        this._holdUsed := false
        this._SpawnNextPiece()
    }

    static _Step(dt) {
        if (!this.IsActive || this.Phase != "playing")
            return

        ; Update visual FX timers
        i := this._shockwaves.Length
        while (i >= 1) {
            this._shockwaves[i].timer -= dt
            if (this._shockwaves[i].timer <= 0.0)
                this._shockwaves.RemoveAt(i)
            i--
        }
        i := this._popups.Length
        while (i >= 1) {
            this._popups[i].timer -= dt
            if (this._popups[i].timer <= 0.0)
                this._popups.RemoveAt(i)
            i--
        }

        ; Gamepad polling (non-headless)
        if (!this._headless) {
            this._PollGamepad(dt)
        }

        fallInterval := Max(0.055, 0.80 * (0.85 ** (this._level - 1)))
        if (this._softDrop)
            fallInterval := Min(fallInterval, 0.045)

        this._gravAccum += dt
        while (this._gravAccum >= fallInterval) {
            this._gravAccum -= fallInterval
            if (this._Fits(this._curKind, this._curX, this._curY + 1, this._curRot)) {
                this._curY++
                this._lockTimer := 0.0
                this._lastWasRotate := false
                if (this._softDrop)
                    this._score += 1
            } else {
                this._gravAccum := 0.0
                break
            }
        }

        if (this._IsGrounded()) {
            this._lockTimer += dt
            if (this._lockTimer >= this.LOCK_DELAY_SEC) {
                this._LockCurrentPiece()
            }
        } else {
            this._lockTimer := 0.0
        }
    }

    static _PollGamepad(dt) {
        gp := HudArcadeBase.PollXInput()
        if (!IsObject(gp))
            return
        btn := gp.btn
        newlyPressed := btn & ~this._gpPrevBtn
        this._gpPrevBtn := btn

        if (newlyPressed & 0x0010) ; Start -> Pause
            this.TogglePause()
        if (newlyPressed & 0x1000) ; A -> Rotate CW
            this.Rotate(1)
        if (newlyPressed & 0x2000) ; B -> Rotate CCW
            this.Rotate(-1)
        if (newlyPressed & 0x4000) ; X -> Hold
            this.Hold()
        if (newlyPressed & 0x8000) ; Y -> Hard Drop
            this.HardDrop()
        if (newlyPressed & 0x0001) ; D-Pad Up -> Hard Drop
            this.HardDrop()

        this._gpMoveCooldown := Max(0.0, this._gpMoveCooldown - dt)
        if ((newlyPressed & 0x0004) || ((btn & 0x0004) && this._gpMoveCooldown <= 0.0)) {
            this.Move(-1)
            this._gpMoveCooldown := (newlyPressed & 0x0004) ? 0.16 : 0.06
        } else if ((newlyPressed & 0x0008) || ((btn & 0x0008) && this._gpMoveCooldown <= 0.0)) {
            this.Move(1)
            this._gpMoveCooldown := (newlyPressed & 0x0008) ? 0.16 : 0.06
        }
        this._softDrop := this._softDrop || ((btn & 0x0002) != 0)
    }

    static _FrameTick() {
        if (!this.IsActive)
            return
        nowUs := HudArcadeBase.NowUs()
        dt := Min(0.05, Max(0.001, (nowUs - this._lastUs) / 1000000.0))
        this._lastUs := nowUs
        this._Step(dt)
        this._RenderFrame()
    }

    static _RenderFrame() {
        if (!IsObject(this._surf) || !this._surf.pGraphics)
            return
        g := this._surf.pGraphics
        W := Float(this._surf.W)
        H := Float(this._surf.H)
        HudArcadeBase.BeginFrame(this._surf)

        isDark := (IsObject(this._cfg) && this._cfg.HasOwnProp("HudTheme")) ? (this._cfg.HudTheme != "light") : true
        micMuted := (IsObject(this._state) && this._state.HasOwnProp("obsMuted")) ? (this._state.obsMuted ? 1 : 0) : -1

        stats := "SCORE " this._score "   BEST " this._highScore "   LVL " this._level "   LINES " this._lines
        hints := "Arrows/WASD Move  •  Up/X/Z Rotate  •  Space Hard Drop  •  C/Shift Hold  •  P Pause  •  Esc Exit"
        HudArcadeBase.DrawScoreboardPill(g, W, "NEON BLOCK DROP", stats, hints, isDark, micMuted)

        ; Well layout centered over desktop below scoreboard
        topMargin := 82.0
        botMargin := 28.0
        availH := Max(260.0, H - topMargin - botMargin)
        cellSz := Floor(Min(availH / Float(this.ROWS), (W - 280.0) / Float(this.COLS)))
        cellSz := Max(16.0, Min(36.0, cellSz))
        wellW := cellSz * Float(this.COLS)
        wellH := cellSz * Float(this.ROWS)
        wellX := (W - wellW) / 2.0
        wellY := topMargin + (availH - wellH) / 2.0

        ; Translucent neon-glass well backdrop
        HudArcadeBase.FillRoundedRect(g, wellX - 6.0, wellY - 6.0, wellW + 12.0, wellH + 12.0, 12.0, 0xCC090D16)
        HudArcadeBase.StrokeRoundedRect(g, wellX - 6.0, wellY - 6.0, wellW + 12.0, wellH + 12.0, 12.0, 0xAA38BDF8, 2.0)

        ; Subtle grid lines
        pGridPen := 0
        DllCall("gdiplus\GdipCreatePen1", "UInt", 0x1E94A3B8, "Float", 1.0, "Int", 2, "Ptr*", &pGridPen)
        try {
            if (pGridPen) {
                Loop this.COLS - 1 {
                    gx := wellX + Float(A_Index) * cellSz
                    DllCall("gdiplus\GdipDrawLine", "Ptr", g, "Ptr", pGridPen, "Float", gx, "Float", wellY, "Float", gx, "Float", wellY + wellH)
                }
                Loop this.ROWS - 1 {
                    gy := wellY + Float(A_Index) * cellSz
                    DllCall("gdiplus\GdipDrawLine", "Ptr", g, "Ptr", pGridPen, "Float", wellX, "Float", gy, "Float", wellX + wellW, "Float", gy)
                }
            }
        } finally {
            if (pGridPen)
                DllCall("gdiplus\GdipDeletePen", "Ptr", pGridPen)
        }

        ; Locked blocks
        Loop this.ROWS {
            rIdx := A_Index
            Loop this.COLS {
                cIdx := A_Index
                k := this._board[rIdx][cIdx]
                if (k != "") {
                    this._DrawBlockCell(g, wellX + Float(cIdx - 1) * cellSz, wellY + Float(rIdx - 1) * cellSz, cellSz, k, false)
                }
            }
        }

        ; Ghost & Active Piece
        if (this.Phase = "playing" || this.Phase = "paused") {
            ghostY := this._ComputeGhostY()
            cells := this._SHAPES[this._curKind][(this._curRot & 3) + 1]
            if (ghostY > this._curY) {
                for _, c in cells {
                    bx := this._curX + c[1]
                    by := ghostY + c[2]
                    if (by >= 0 && by < this.ROWS && bx >= 0 && bx < this.COLS)
                        this._DrawBlockCell(g, wellX + Float(bx) * cellSz, wellY + Float(by) * cellSz, cellSz, this._curKind, true)
                }
            }
            for _, c in cells {
                bx := this._curX + c[1]
                by := this._curY + c[2]
                if (by >= 0 && by < this.ROWS && bx >= 0 && bx < this.COLS)
                    this._DrawBlockCell(g, wellX + Float(bx) * cellSz, wellY + Float(by) * cellSz, cellSz, this._curKind, false)
            }
        }

        ; Line-clear shockwaves
        for _, sw in this._shockwaves {
            t := Max(0.0, Min(1.0, sw.timer / sw.maxTimer))
            alpha := Integer(Round(t * 210.0))
            col := (alpha << 24) | (sw.argb & 0x00FFFFFF)
            sy := wellY + Float(sw.row) * cellSz
            HudArcadeBase.FillRoundedRect(g, wellX - 4.0, sy, wellW + 8.0, cellSz, 4.0, col)
        }

        ; Side panels: HOLD (left) and NEXT 3 (right)
        sideW := 112.0
        holdX := wellX - sideW - 18.0
        nextX := wellX + wellW + 18.0
        if (holdX >= 10.0)
            this._DrawPreviewPanel(g, holdX, wellY, sideW, 96.0, "HOLD", this._holdKind != "" ? [this._holdKind] : [], this._holdUsed)
        if (nextX + sideW <= W - 10.0)
            this._DrawPreviewPanel(g, nextX, wellY, sideW, 240.0, "NEXT", [this._queue[1], this._queue[2], this._queue[3]], false)

        ; Floating score popups
        for idx, pop in this._popups {
            t := pop.timer / pop.maxTimer
            py := wellY + wellH * 0.35 - (1.0 - t) * 32.0 - Float(idx - 1) * 22.0
            Gdip.DrawText(g, pop.text, "Segoe UI", 11.0, 1, pop.argb, wellX, py, wellW, 24.0, 1, 1, 0, true)
        }

        if (this.Phase = "paused") {
            HudArcadeBase.DrawOverlayCard(g, W, H, "PAUSED", "Score: " this._score "  •  Level " this._level, "Press P to Resume  •  R to Restart  •  Esc to Exit", 0xFF38BDF8, isDark)
        } else if (this.Phase = "gameover") {
            HudArcadeBase.DrawOverlayCard(g, W, H, "TOP OUT — GAME OVER", "Score: " this._score "  •  Best: " this._highScore, "Press R to Play Again  •  Esc to Exit", 0xFFEF4444, isDark)
        }

        if (!this._headless)
            HudArcadeBase.PresentFrame(this._surf)
    }

    static _DrawBlockCell(g, x, y, sz, kind, isGhost) {
        c := this._COLORS[kind]
        pad := 1.5
        rx := x + pad
        ry := y + pad
        rw := Max(4.0, sz - pad * 2.0)
        rh := rw
        if (isGhost) {
            HudArcadeBase.StrokeRoundedRect(g, rx, ry, rw, rh, 3.0, (0x66 << 24) | (c.wire & 0x00FFFFFF), 1.5)
            return
        }
        HudArcadeBase.FillRoundedRect(g, rx, ry, rw, rh, 3.5, c.fill)
        HudArcadeBase.StrokeRoundedRect(g, rx, ry, rw, rh, 3.5, c.wire, 1.4)
    }

    static _DrawPreviewPanel(g, x, y, w, h, title, kinds, dimmed := false) {
        HudArcadeBase.FillRoundedRect(g, x, y, w, h, 10.0, 0xCC090D16)
        HudArcadeBase.StrokeRoundedRect(g, x, y, w, h, 10.0, dimmed ? 0x4464748B : 0x8838BDF8, 1.5)
        Gdip.DrawText(g, title, "Segoe UI", 8.5, 1, 0xFF94A3B8, x, y + 6.0, w, 18.0, 1, 1, 0, false)
        mini := 16.0
        for idx, k in kinds {
            if (k = "")
                continue
            cells := this._SHAPES[k][1]
            minX := 9, maxX := -1, minY := 9, maxY := -1
            for _, c in cells {
                minX := Min(minX, c[1]), maxX := Max(maxX, c[1])
                minY := Min(minY, c[2]), maxY := Max(maxY, c[2])
            }
            pw := Float(maxX - minX + 1) * mini
            ph := Float(maxY - minY + 1) * mini
            ox := x + (w - pw) / 2.0 - Float(minX) * mini
            oy := y + 32.0 + Float(idx - 1) * 66.0 + (48.0 - ph) / 2.0 - Float(minY) * mini
            for _, c in cells
                this._DrawBlockCell(g, ox + Float(c[1]) * mini, oy + Float(c[2]) * mini, mini, k, dimmed)
        }
    }

    ; --- Headless Test Helpers ---
    static StepForTest(dtSec) {
        rem := Float(dtSec)
        while (rem > 0.0) {
            step := Min(0.016, rem)
            this._Step(step)
            rem -= step
        }
    }

    static MoveForTest(dx) => this.Move(dx)
    static RotateForTest(dir) => this.Rotate(dir)
    static HoldForTest() => this.Hold()
    static HardDropForTest() => this.HardDrop()
    static ComputeGhostYForTest() => this._ComputeGhostY()

    static FillRowForTest(row, skipCol := 0) {
        r := Integer(row)
        if (r < 0 || r >= this.ROWS)
            return false
        Loop this.COLS {
            c := A_Index - 1
            this._board[r + 1][c + 1] := (c == Integer(skipCol)) ? "" : "I"
        }
        return true
    }

    static SpawnPieceForTest(kind, x, y, rot := 0) {
        this._curKind := String(kind)
        this._curX := Integer(x)
        this._curY := Integer(y)
        this._curRot := Integer(rot) & 3
        this._gravAccum := 0.0
        this._lockTimer := 0.0
        this._lockResets := 0
        this._lastWasRotate := false
        this._lastKickIdx := 0
        return true
    }

    static DrawBagForTest() {
        return this._DrawFromBag()
    }

    static GetStateSnapshot() {
        filled := 0
        Loop this.ROWS {
            r := A_Index
            Loop this.COLS {
                if (this._board[r][A_Index] != "")
                    filled++
            }
        }
        return {
            active: this.IsActive,
            phase: this.Phase,
            score: this._score,
            highScore: this._highScore,
            level: this._level,
            lines: this._lines,
            b2b: this._b2b,
            combo: this._combo,
            curKind: this._curKind,
            curX: this._curX,
            curY: this._curY,
            curRot: this._curRot,
            ghostY: this._ComputeGhostY(),
            holdKind: this._holdKind,
            holdUsed: this._holdUsed,
            next3: [this._queue[1], this._queue[2], this._queue[3]],
            boardFilledCount: filled,
            interactiveMouse: IsObject(this._surf) ? this._surf.interactiveMouse : false,
            lockTimer: this._lockTimer
        }
    }
}
