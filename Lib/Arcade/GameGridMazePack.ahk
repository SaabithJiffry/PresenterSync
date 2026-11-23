; ==============================================================================
; Module: GameGridMazePack.ahk
; Description: Milestone M5.1 — Grid & Maze Arcade Pack (v8.4.1)
;              1) GameLightCycles (^!+t, "tron"):
;                 * Head-to-head neon laser trail duel on an 80x48 grid over the
;                   live desktop against a lookahead flood-fill / longest-corridor
;                   AI opponent.
;                 * Rechargeable Turbo Boost (Space / Shift — 2x step speed while
;                   charge > 0, recharges when released), round-win streak
;                   counter, per-round speed escalation, crash spark particles,
;                   and [ArcadeHighScores] "tron" persistence.
;              2) GamePacGrid (^!+c, "pac_grid"):
;                 * Full Authentic Pac-Man Mechanics in a translucent 28x31
;                   symmetric neon wireframe maze over the desktop.
;                 * Standard pellets (+10), 4 pulsing corner Power Orbs (+50),
;                   7.0s Frightened Mode with escalating chaser-eat combos
;                   (200 -> 400 -> 800 -> 1600) + floating score popups.
;                 * Eaten chasers turn into returning eyes ("eyes") that path
;                   back to the central ghost pen (col=13..14, row=14) to
;                   regenerate ("chase" / "scatter").
;                 * 4 distinct chaser personalities: Blinky (Red Pursuer),
;                   Pinky (Pink Ambusher, +4 tiles ahead), Inky (Cyan Flanker,
;                   vector reflection from Blinky through +2 tiles ahead), and
;                   Clyde (Amber Roamer, chases when dist > 8 else bottom-left).
;                 * Timed Scatter <-> Chase wave phase timer (7s -> 20s -> 7s ->
;                   20s -> Chase) with direction reversal on transitions.
;                 * Left/right wrap-around warp tunnels (col < 0 <-> col = 27)
;                   with chaser tunnel speed slowdown.
;                 * Timed Bonus Neon Fruits below ghost pen at 70 & 170 dots
;                   (100 -> 300 -> 500 -> 700 -> 1000 -> 2000 -> 3000 -> 5000).
;                 * Smooth queued directional turn buffering (_nextDir applied
;                   at the next valid corridor intersection), 3 lives, level
;                   progression, and [ArcadeHighScores] "pac_grid" persistence.
; ==============================================================================

#Include "%A_LineFile%\..\..\HudArcadeBase.ahk"

class GameLightCycles {
    static IsActive := false
    static Phase := "idle" ; "idle" | "playing" | "paused" | "gameover"
    static COLS := 80
    static ROWS := 48

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
    static _round := 1
    static _streak := 0
    static _baseStepRate := 15.0 ; steps per second
    static _playerStepAccum := 0.0
    static _aiStepAccum := 0.0

    static _playerCol := 18
    static _playerRow := 24
    static _playerDx := 1
    static _playerDy := 0
    static _queuedDx := 1
    static _queuedDy := 0

    static _aiCol := 61
    static _aiRow := 24
    static _aiDx := -1
    static _aiDy := 0

    static _boostWanted := false
    static _boostActive := false
    static _boostCharge := 100.0

    static _occupied := Map() ; "col,row" -> 1 (player) or 2 (ai)
    static _playerTrail := []
    static _aiTrail := []
    static _particles := []
    static _popups := []

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
            title: "PresenterSyncLightCycles",
            headless: this._headless
        })
        if (!IsObject(this._surf))
            return false

        this.IsActive := true
        HudArcadeBase.RegisterActiveGame(this, "tron")
        this._highScore := HudArcadeBase.LoadHighScore(cfg, "tron")
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
        this._boostWanted := false
        this._boostActive := false
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
        HudArcadeBase.ClearActiveGame("tron")
    }

    static _BindKeys(cfg) {
        condFn := (*) => GameLightCycles.IsActive
        bindings := [
            { key: "$Up", fn: (*) => GameLightCycles.QueueTurn(0, -1) },
            { key: "$Down", fn: (*) => GameLightCycles.QueueTurn(0, 1) },
            { key: "$Left", fn: (*) => GameLightCycles.QueueTurn(-1, 0) },
            { key: "$Right", fn: (*) => GameLightCycles.QueueTurn(1, 0) },
            { key: "$w", fn: (*) => GameLightCycles.QueueTurn(0, -1) },
            { key: "$s", fn: (*) => GameLightCycles.QueueTurn(0, 1) },
            { key: "$a", fn: (*) => GameLightCycles.QueueTurn(-1, 0) },
            { key: "$d", fn: (*) => GameLightCycles.QueueTurn(1, 0) },
            { key: "$Space", fn: (*) => GameLightCycles.SetBoost(true) },
            { key: "$Space up", fn: (*) => GameLightCycles.SetBoost(false) },
            { key: "$LShift", fn: (*) => GameLightCycles.SetBoost(true) },
            { key: "$LShift up", fn: (*) => GameLightCycles.SetBoost(false) },
            { key: "$RShift", fn: (*) => GameLightCycles.SetBoost(true) },
            { key: "$RShift up", fn: (*) => GameLightCycles.SetBoost(false) },
            { key: "$p", fn: (*) => GameLightCycles.TogglePause() },
            { key: "$r", fn: (*) => (GameLightCycles.Phase = "gameover" ? GameLightCycles._ResetMatch() : 0) },
            { key: "$Escape", fn: (*) => GameLightCycles.Stop() }
        ]
        HudArcadeBase.BindKeysSafe(cfg, bindings, this._boundHotkeys, condFn)
    }

    static TogglePause() {
        if (!this.IsActive)
            return
        if (this.Phase = "playing") {
            this.Phase := "paused"
            this._boostWanted := false
            this._boostActive := false
        } else if (this.Phase = "paused") {
            this.Phase := "playing"
            this._lastUs := HudArcadeBase.NowUs()
        }
    }

    static QueueTurn(dx, dy) {
        ndx := Integer(dx)
        ndy := Integer(dy)
        if ((ndx == 0 && ndy == 0) || (ndx != 0 && ndy != 0))
            return false
        ; Disallow 180-degree self-reversal against current heading
        if (ndx == -this._playerDx && ndy == -this._playerDy)
            return false
        this._queuedDx := ndx
        this._queuedDy := ndy
        return true
    }

    static SetBoost(on) {
        this._boostWanted := !!on
        if (this._boostWanted && this._boostCharge > 0.0 && this.Phase = "playing")
            this._boostActive := true
        else if (!this._boostWanted)
            this._boostActive := false
        return this._boostActive
    }

    static _ResetMatch() {
        this._score := 0
        this._round := 1
        this._streak := 0
        this._boostCharge := 100.0
        this._boostWanted := false
        this._boostActive := false
        this._particles := []
        this._popups := []
        this._SetupRound(1)
        this.Phase := "playing"
    }

    static _SetupRound(roundNum) {
        this._round := Max(1, Integer(roundNum))
        this._baseStepRate := Min(28.0, 15.0 + Float(this._round - 1) * 1.6)
        this._playerStepAccum := 0.0
        this._aiStepAccum := 0.0

        this._occupied := Map()
        this._playerTrail := []
        this._aiTrail := []

        midRow := this.ROWS // 2
        this._playerCol := 16
        this._playerRow := midRow
        this._playerDx := 1
        this._playerDy := 0
        this._queuedDx := 1
        this._queuedDy := 0

        this._aiCol := this.COLS - 17
        this._aiRow := midRow
        this._aiDx := -1
        this._aiDy := 0

        this._MarkOccupied(this._playerCol, this._playerRow, 1)
        this._playerTrail.Push({ col: this._playerCol, row: this._playerRow })
        this._MarkOccupied(this._aiCol, this._aiRow, 2)
        this._aiTrail.Push({ col: this._aiCol, row: this._aiRow })
    }

    static _CellKey(col, row) {
        return Integer(col) "," Integer(row)
    }

    static _IsOutOfBounds(col, row) {
        return (col < 0 || col >= this.COLS || row < 0 || row >= this.ROWS)
    }

    static _IsBlocked(col, row) {
        if (this._IsOutOfBounds(col, row))
            return true
        return this._occupied.Has(this._CellKey(col, row))
    }

    static _MarkOccupied(col, row, owner := 1) {
        if (!this._IsOutOfBounds(col, row))
            this._occupied[this._CellKey(col, row)] := owner
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
        dt := Min(0.1, Max(0.0001, Float(dtSec)))
        dtMs := dt * 1000.0

        if (readHardwareInput) {
            gp := HudArcadeBase.PollXInput()
            if (IsObject(gp)) {
                if ((gp.btn & 0x0001) || gp.ly > 14000)
                    this.QueueTurn(0, -1)
                else if ((gp.btn & 0x0002) || gp.ly < -14000)
                    this.QueueTurn(0, 1)
                else if ((gp.btn & 0x0004) || gp.lx < -14000)
                    this.QueueTurn(-1, 0)
                else if ((gp.btn & 0x0008) || gp.lx > 14000)
                    this.QueueTurn(1, 0)
                if (gp.btn & 0x1000)
                    this.SetBoost(true)
            }
        }

        ; Update Turbo Boost drain & recharge
        if (this._boostWanted && this._boostCharge > 0.0) {
            this._boostActive := true
            this._boostCharge := Max(0.0, this._boostCharge - 45.0 * dt)
            if (this._boostCharge <= 0.0) {
                this._boostCharge := 0.0
                this._boostActive := false
            }
        } else {
            this._boostActive := false
            this._boostCharge := Min(100.0, this._boostCharge + 28.0 * dt)
        }

        playerMult := this._boostActive ? 2.0 : 1.0
        playerRate := this._baseStepRate * playerMult
        aiRate := this._baseStepRate * Min(1.25, 0.98 + Float(this._round - 1) * 0.03)

        this._playerStepAccum += playerRate * dt
        this._aiStepAccum += aiRate * dt

        while (this._playerStepAccum >= 1.0 && this.Phase = "playing") {
            this._playerStepAccum -= 1.0
            this._StepPlayerOnce()
        }

        while (this._aiStepAccum >= 1.0 && this.Phase = "playing") {
            this._aiStepAccum -= 1.0
            this._StepAiOnce()
        }

        ; Update particles & floating popups
        pIdx := this._particles.Length
        while (pIdx >= 1) {
            pt := this._particles[pIdx]
            pt.ttlMs -= dtMs
            if (pt.ttlMs <= 0.0)
                this._particles.RemoveAt(pIdx)
            else {
                pt.x += pt.vx * dt
                pt.y += pt.vy * dt
            }
            pIdx -= 1
        }

        ppIdx := this._popups.Length
        while (ppIdx >= 1) {
            pp := this._popups[ppIdx]
            pp.ttlMs -= dtMs
            if (pp.ttlMs <= 0.0)
                this._popups.RemoveAt(ppIdx)
            else
                pp.y -= 24.0 * dt
            ppIdx -= 1
        }
    }

    static _StepPlayerOnce() {
        if (!(this._queuedDx == -this._playerDx && this._queuedDy == -this._playerDy)) {
            this._playerDx := this._queuedDx
            this._playerDy := this._queuedDy
        }
        nextCol := this._playerCol + this._playerDx
        nextRow := this._playerRow + this._playerDy

        if (this._IsBlocked(nextCol, nextRow)) {
            this._playerCol := nextCol
            this._playerRow := nextRow
            this._SpawnGridSparks(nextCol, nextRow, 0xFF38BDF8, 18)
            this.Phase := "gameover"
            this._boostActive := false
            return
        }

        this._playerCol := nextCol
        this._playerRow := nextRow
        this._MarkOccupied(nextCol, nextRow, 1)
        this._playerTrail.Push({ col: nextCol, row: nextRow })
        this._AddScore(this._boostActive ? 10 : 5)
    }

    static _StepAiOnce() {
        choice := this._ChooseAiNextDir()
        this._aiDx := choice.dx
        this._aiDy := choice.dy
        nextCol := this._aiCol + this._aiDx
        nextRow := this._aiRow + this._aiDy

        if (this._IsBlocked(nextCol, nextRow)) {
            ; AI crashed into laser wall or arena boundary -> Player wins the round!
            this._SpawnGridSparks(nextCol, nextRow, 0xFFF43F5E, 18)
            this._streak += 1
            roundBonus := 250 + this._streak * 50
            this._AddScore(roundBonus)
            this._SetupRound(this._round + 1)
            return
        }

        this._aiCol := nextCol
        this._aiRow := nextRow
        this._MarkOccupied(nextCol, nextRow, 2)
        this._aiTrail.Push({ col: nextCol, row: nextRow })
    }

    static _ChooseAiNextDir() {
        cx := this._aiCol
        cy := this._aiRow
        cdx := this._aiDx
        cdy := this._aiDy

        ; Candidate turns: straight, left turn, right turn (never 180 reversal)
        candidates := [
            { dx: cdx, dy: cdy, bias: 2.5 },
            { dx: -cdy, dy: cdx, bias: 0.0 },
            { dx: cdy, dy: -cdx, bias: 0.0 }
        ]

        bestDir := { dx: cdx, dy: cdy, freeCells: 0, corridor: 0, score: -999999.0 }
        for _, cand in candidates {
            nx := cx + cand.dx
            ny := cy + cand.dy
            if (this._IsBlocked(nx, ny))
                continue

            area := this._FloodFillCount(nx, ny, 140)
            corridor := this._CorridorLength(nx, ny, cand.dx, cand.dy, 28)
            openNeighbors := this._CountOpenNeighbors(nx, ny)
            totalScore := Float(area) * 4.0 + Float(corridor) * 3.0 + Float(openNeighbors) * 2.0 + cand.bias
            if (totalScore > bestDir.score) {
                bestDir := {
                    dx: cand.dx,
                    dy: cand.dy,
                    freeCells: area,
                    corridor: corridor,
                    score: totalScore
                }
            }
        }
        return bestDir
    }

    static _CountOpenNeighbors(col, row) {
        cnt := 0
        for _, d in [{ dx: 1, dy: 0 }, { dx: -1, dy: 0 }, { dx: 0, dy: 1 }, { dx: 0, dy: -1 }] {
            if (!this._IsBlocked(col + d.dx, row + d.dy))
                cnt += 1
        }
        return cnt
    }

    static _CorridorLength(startCol, startRow, dx, dy, maxDist := 28) {
        dist := 0
        c := startCol
        r := startRow
        while (dist < maxDist && !this._IsBlocked(c, r)) {
            dist += 1
            c += dx
            r += dy
        }
        return dist
    }

    static _FloodFillCount(startCol, startRow, maxNodes := 140) {
        if (this._IsBlocked(startCol, startRow))
            return 0
        visited := Map()
        startKey := this._CellKey(startCol, startRow)
        visited[startKey] := true
        queue := [{ col: startCol, row: startRow }]
        head := 1
        count := 0
        dirs := [{ dx: 1, dy: 0 }, { dx: -1, dy: 0 }, { dx: 0, dy: 1 }, { dx: 0, dy: -1 }]

        while (head <= queue.Length && count < maxNodes) {
            cur := queue[head]
            head += 1
            count += 1
            for _, d in dirs {
                nc := cur.col + d.dx
                nr := cur.row + d.dy
                if (this._IsBlocked(nc, nr))
                    continue
                k := this._CellKey(nc, nr)
                if (visited.Has(k))
                    continue
                visited[k] := true
                queue.Push({ col: nc, row: nr })
            }
        }
        return count
    }

    static _AddScore(pts) {
        this._score += Integer(pts)
        if (this._score > this._highScore) {
            this._highScore := this._score
            HudArcadeBase.SaveHighScore(this._cfg, "tron", this._highScore)
        }
    }

    static _GetGridMetrics() {
        W := IsObject(this._surf) ? Float(this._surf.W) : 1280.0
        H := IsObject(this._surf) ? Float(this._surf.H) : 720.0
        padX := 48.0
        topY := 78.0
        botPad := 32.0
        availW := Max(320.0, W - padX * 2.0)
        availH := Max(200.0, H - topY - botPad)
        cell := Floor(Min(availW / Float(this.COLS), availH / Float(this.ROWS)))
        cell := Max(6.0, cell)
        boardW := cell * Float(this.COLS)
        boardH := cell * Float(this.ROWS)
        ox := (W - boardW) * 0.5
        oy := topY + (availH - boardH) * 0.5
        return { W: W, H: H, ox: ox, oy: oy, cell: cell, boardW: boardW, boardH: boardH }
    }

    static _SpawnGridSparks(col, row, colArgb, count := 14) {
        m := this._GetGridMetrics()
        px := m.ox + (Float(col) + 0.5) * m.cell
        py := m.oy + (Float(row) + 0.5) * m.cell
        Loop count {
            ang := Float(Random(0, 628)) / 100.0
            spd := Float(Random(50, 190))
            this._particles.Push({
                x: px,
                y: py,
                vx: Cos(ang) * spd,
                vy: Sin(ang) * spd,
                ttlMs: 420.0,
                col: colArgb
            })
        }
    }

    ; --- Headless Test Helpers ---
    static QueueTurnForTest(dx, dy) {
        return this.QueueTurn(dx, dy)
    }

    static SetBoostForTest(on) {
        return this.SetBoost(on)
    }

    static ChooseAiDirForTest() {
        choice := this._ChooseAiNextDir()
        this._aiDx := choice.dx
        this._aiDy := choice.dy
        return choice
    }

    static ForceOccupiedForTest(col, row, owner := 1) {
        this._MarkOccupied(Integer(col), Integer(row), Integer(owner))
        return this._IsBlocked(Integer(col), Integer(row))
    }

    static SetCyclesForTest(pCol, pRow, pDx, pDy, aiCol := "", aiRow := "", aiDx := "", aiDy := "") {
        this._playerCol := Integer(pCol)
        this._playerRow := Integer(pRow)
        this._playerDx := Integer(pDx)
        this._playerDy := Integer(pDy)
        this._queuedDx := Integer(pDx)
        this._queuedDy := Integer(pDy)
        this._MarkOccupied(this._playerCol, this._playerRow, 1)
        if (aiCol != "") {
            this._aiCol := Integer(aiCol)
            this._aiRow := Integer(aiRow)
            this._aiDx := Integer(aiDx)
            this._aiDy := Integer(aiDy)
            this._MarkOccupied(this._aiCol, this._aiRow, 2)
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
            round: this._round,
            streak: this._streak,
            cols: this.COLS,
            rows: this.ROWS,
            playerCol: this._playerCol,
            playerRow: this._playerRow,
            playerDx: this._playerDx,
            playerDy: this._playerDy,
            aiCol: this._aiCol,
            aiRow: this._aiRow,
            aiDx: this._aiDx,
            aiDy: this._aiDy,
            boostWanted: this._boostWanted,
            boostActive: this._boostActive,
            boostCharge: this._boostCharge,
            baseStepRate: this._baseStepRate,
            playerTrailCount: this._playerTrail.Length,
            aiTrailCount: this._aiTrail.Length,
            occupiedCount: this._occupied.Count
        }
    }

    static _RenderFrame() {
        if (!IsObject(this._surf) || !this._surf.pGraphics)
            return
        HudArcadeBase.BeginFrame(this._surf)
        g := this._surf.pGraphics
        m := this._GetGridMetrics()

        ; Translucent neon grid arena frame
        HudArcadeBase.FillRoundedRect(g, m.ox - 6.0, m.oy - 6.0, m.boardW + 12.0, m.boardH + 12.0, 12.0, 0x88090D16)
        HudArcadeBase.StrokeRoundedRect(g, m.ox - 6.0, m.oy - 6.0, m.boardW + 12.0, m.boardH + 12.0, 12.0, 0xCC38BDF8, 2.0)

        ; Subtle neon grid lines every 4 cells
        pGridPen := 0
        DllCall("gdiplus\GdipCreatePen1", "UInt", 0x2438BDF8, "Float", 1.0, "Int", 2, "Ptr*", &pGridPen)
        if (pGridPen) {
            try {
                c := 4
                while (c < this.COLS) {
                    gx := m.ox + Float(c) * m.cell
                    DllCall("gdiplus\GdipDrawLine", "Ptr", g, "Ptr", pGridPen, "Float", gx, "Float", m.oy, "Float", gx, "Float", m.oy + m.boardH)
                    c += 4
                }
                r := 4
                while (r < this.ROWS) {
                    gy := m.oy + Float(r) * m.cell
                    DllCall("gdiplus\GdipDrawLine", "Ptr", g, "Ptr", pGridPen, "Float", m.ox, "Float", gy, "Float", m.ox + m.boardW, "Float", gy)
                    r += 4
                }
            } finally {
                DllCall("gdiplus\GdipDeletePen", "Ptr", pGridPen)
            }
        }

        ; Draw player cyan laser trail and AI crimson/orange laser trail
        this._DrawLaserTrail(g, this._playerTrail, m, 0x550EA5E9, 0xFF38BDF8)
        this._DrawLaserTrail(g, this._aiTrail, m, 0x55F43F5E, 0xFFFB7185)

        ; Draw cycle heads
        px := m.ox + Float(this._playerCol) * m.cell
        py := m.oy + Float(this._playerRow) * m.cell
        ax := m.ox + Float(this._aiCol) * m.cell
        ay := m.oy + Float(this._aiRow) * m.cell
        HudArcadeBase.FillRoundedRect(g, px - 2.0, py - 2.0, m.cell + 4.0, m.cell + 4.0, 4.0, this._boostActive ? 0xFFFACC15 : 0xFFE0F2FE)
        HudArcadeBase.FillRoundedRect(g, ax - 2.0, ay - 2.0, m.cell + 4.0, m.cell + 4.0, 4.0, 0xFFFDA4AF)

        ; Draw crash particles
        pBrush := 0
        try {
            for _, pt in this._particles {
                DllCall("gdiplus\GdipCreateSolidFill", "UInt", pt.col, "Ptr*", &pBrush)
                if (pBrush) {
                    DllCall("gdiplus\GdipFillEllipse", "Ptr", g, "Ptr", pBrush, "Float", pt.x - 2.5, "Float", pt.y - 2.5, "Float", 5.0, "Float", 5.0)
                    DllCall("gdiplus\GdipDeleteBrush", "Ptr", pBrush)
                    pBrush := 0
                }
            }
        } finally {
            if (pBrush)
                DllCall("gdiplus\GdipDeleteBrush", "Ptr", pBrush)
        }

        isDark := IsSet(Theme) ? Theme.IsDarkMode() : true
        micMuted := (IsObject(this._state) && this._state.HasOwnProp("isMuted")) ? (this._state.isMuted ? 1 : 0) : -1
        stats := Format("SCORE {}  •  BEST {}  •  ROUND {} (STREAK {})  •  BOOST {}%",
            this._score, this._highScore, this._round, this._streak, Round(this._boostCharge))
        hint := "Arrows / WASD: Steer  •  Space / Shift: Turbo Boost  •  P: Pause  •  R: Retry  •  Esc: Exit"
        HudArcadeBase.DrawScoreboardPill(g, m.W, "LIGHT CYCLES", stats, hint, isDark, micMuted)

        if (this.Phase = "paused") {
            HudArcadeBase.DrawOverlayCard(g, m.W, m.H, "LIGHT CYCLES PAUSED",
                Format("Score: {}   •   Best: {}   •   Round: {}   •   Streak: {}", this._score, this._highScore, this._round, this._streak),
                "Press P to Resume   •   Esc to Exit", 0xFF38BDF8, isDark)
        } else if (this.Phase = "gameover") {
            HudArcadeBase.DrawOverlayCard(g, m.W, m.H, "DEREZZED — TRAIL IMPACT",
                Format("Final Score: {}   •   Best: {}   •   Win Streak: {}", this._score, this._highScore, this._streak),
                "Press R to Launch New Grid Duel   •   Esc to Exit", 0xFFEF4444, isDark)
        }

        HudArcadeBase.PresentFrame(this._surf)
    }

    static _DrawLaserTrail(g, trailArr, m, glowArgb, coreArgb) {
        if (trailArr.Length < 2)
            return
        pGlow := 0, pCore := 0
        DllCall("gdiplus\GdipCreatePen1", "UInt", glowArgb, "Float", Max(4.0, m.cell * 0.95), "Int", 2, "Ptr*", &pGlow)
        DllCall("gdiplus\GdipCreatePen1", "UInt", coreArgb, "Float", Max(2.0, m.cell * 0.48), "Int", 2, "Ptr*", &pCore)
        try {
            Loop (trailArr.Length - 1) {
                a := trailArr[A_Index]
                b := trailArr[A_Index + 1]
                x1 := m.ox + (Float(a.col) + 0.5) * m.cell
                y1 := m.oy + (Float(a.row) + 0.5) * m.cell
                x2 := m.ox + (Float(b.col) + 0.5) * m.cell
                y2 := m.oy + (Float(b.row) + 0.5) * m.cell
                if (pGlow)
                    DllCall("gdiplus\GdipDrawLine", "Ptr", g, "Ptr", pGlow, "Float", x1, "Float", y1, "Float", x2, "Float", y2)
                if (pCore)
                    DllCall("gdiplus\GdipDrawLine", "Ptr", g, "Ptr", pCore, "Float", x1, "Float", y1, "Float", x2, "Float", y2)
            }
        } finally {
            if (pCore)
                DllCall("gdiplus\GdipDeletePen", "Ptr", pCore)
            if (pGlow)
                DllCall("gdiplus\GdipDeletePen", "Ptr", pGlow)
        }
    }
}

class GamePacGrid {
    static IsActive := false
    static Phase := "idle" ; "idle" | "playing" | "paused" | "gameover"
    static COLS := 28
    static ROWS := 31
    static TUNNEL_ROW := 14
    static PEN_COL_L := 13
    static PEN_COL_R := 14
    static PEN_ROW := 14
    static FRUIT_COL := 13
    static FRUIT_ROW := 17

    static _MAZE_TEMPLATE := [
        "############################",
        "#............##............#",
        "#.####.#####.##.#####.####.#",
        "#o####.#####.##.#####.####o#",
        "#.####.#####.##.#####.####.#",
        "#..........................#",
        "#.####.##.########.##.####.#",
        "#.####.##.########.##.####.#",
        "#......##....##....##......#",
        "######.##### ## #####.######",
        "######.##### ## #####.######",
        "######.##          ##.######",
        "######.## ###--### ##.######",
        "######.## #      # ##.######",
        "          #      #          ",
        "######.## #      # ##.######",
        "######.## ######## ##.######",
        "######.##          ##.######",
        "######.## ######## ##.######",
        "######.## ######## ##.######",
        "#............##............#",
        "#.####.#####.##.#####.####.#",
        "#.####.#####.##.#####.####.#",
        "#o..##................##..o#",
        "###.##.##.########.##.##.###",
        "###.##.##.########.##.##.###",
        "#......##....##....##......#",
        "#.##########.##.##########.#",
        "#.##########.##.##########.#",
        "#..........................#",
        "############################"
    ]

    static _WAVE_SCHEDULE := [
        { mode: "scatter", dur: 7.0 },
        { mode: "chase", dur: 20.0 },
        { mode: "scatter", dur: 7.0 },
        { mode: "chase", dur: 20.0 },
        { mode: "chase", dur: 999999.0 }
    ]

    static _FRUIT_TABLE := [100, 300, 500, 700, 1000, 2000, 3000, 5000]

    static _surf := ""
    static _cfg := ""
    static _state := ""
    static _savedPolling := ""
    static _boundHotkeys := []
    static _tickFn := ""
    static _lastUs := 0.0
    static _headless := false

    static _grid := [] ; 31 rows of 28 ints: 0=empty, 1=wall, 2=pellet, 3=powerOrb, 4=penDoor
    static _score := 0
    static _highScore := 0
    static _lives := 3
    static _level := 1
    static _dotsEaten := 0
    static _dotsRemaining := 0
    static _totalLevelDots := 0

    static _runnerCol := 13
    static _runnerRow := 23
    static _runnerDx := -1
    static _runnerDy := 0
    static _nextDir := { dx: -1, dy: 0 }
    static _runnerStepAccum := 0.0
    static _animTimeSec := 0.0

    static _frightenedSec := 0.0
    static _frightCombo := 0
    static _waveIdx := 1
    static _waveTimerSec := 0.0
    static _waveMode := "scatter"
    static _waveTransitions := 0

    static _fruitActive := false
    static _fruitCol := 13
    static _fruitRow := 17
    static _fruitTimerSec := 0.0
    static _fruitPoints := 100
    static _fruit70Spawned := false
    static _fruit170Spawned := false

    static _chasers := []
    static _popups := []
    static _expandedMode := false

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
            title: "PresenterSyncPacGrid",
            headless: this._headless
        })
        if (!IsObject(this._surf))
            return false

        this.IsActive := true
        HudArcadeBase.RegisterActiveGame(this, "pac_grid")
        this._highScore := HudArcadeBase.LoadHighScore(cfg, "pac_grid")
        this._ResetGame()

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
        HudArcadeBase.ClearActiveGame("pac_grid")
    }

    static _BindKeys(cfg) {
        condFn := (*) => GamePacGrid.IsActive
        bindings := [
            { key: "$Up", fn: (*) => GamePacGrid.QueueDir(0, -1) },
            { key: "$Down", fn: (*) => GamePacGrid.QueueDir(0, 1) },
            { key: "$Left", fn: (*) => GamePacGrid.QueueDir(-1, 0) },
            { key: "$Right", fn: (*) => GamePacGrid.QueueDir(1, 0) },
            { key: "$w", fn: (*) => GamePacGrid.QueueDir(0, -1) },
            { key: "$s", fn: (*) => GamePacGrid.QueueDir(0, 1) },
            { key: "$a", fn: (*) => GamePacGrid.QueueDir(-1, 0) },
            { key: "$d", fn: (*) => GamePacGrid.QueueDir(1, 0) },
            { key: "$p", fn: (*) => GamePacGrid.TogglePause() },
            { key: "$f", fn: (*) => GamePacGrid.ToggleViewMode() },
            { key: "$+f", fn: (*) => GamePacGrid.ToggleViewMode() },
            { key: "$r", fn: (*) => (GamePacGrid.Phase = "gameover" ? GamePacGrid._ResetGame() : 0) },
            { key: "$Escape", fn: (*) => GamePacGrid.Stop() }
        ]
        HudArcadeBase.BindKeysSafe(cfg, bindings, this._boundHotkeys, condFn)
    }

    static ToggleViewMode() {
        this._expandedMode := !this._expandedMode
        if (this.IsActive && !this._headless)
            this._RenderFrame()
        return this._expandedMode
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

    static QueueDir(dx, dy) {
        ndx := Integer(dx)
        ndy := Integer(dy)
        if ((ndx == 0 && ndy == 0) || (ndx != 0 && ndy != 0))
            return false
        this._nextDir := { dx: ndx, dy: ndy }
        ; Apply immediately if tile in queued direction is already passable
        if (this._CanRunnerEnter(this._runnerCol + ndx, this._runnerRow + ndy)) {
            this._runnerDx := ndx
            this._runnerDy := ndy
        }
        return true
    }

    static _ResetGame() {
        this._score := 0
        this._lives := 3
        this._level := 1
        this._popups := []
        this._LoadMazeLevel(1)
        this.Phase := "playing"
    }

    static _LoadMazeLevel(lvl) {
        this._level := Max(1, Integer(lvl))
        this._grid := []
        this._dotsEaten := 0
        this._dotsRemaining := 0
        this._totalLevelDots := 0

        Loop this.ROWS {
            rIdx := A_Index
            line := this._MAZE_TEMPLATE[rIdx]
            rowArr := []
            Loop this.COLS {
                cIdx := A_Index
                ch := SubStr(line, cIdx, 1)
                cellVal := 0
                if (ch = "#")
                    cellVal := 1
                else if (ch = ".") {
                    cellVal := 2
                    this._dotsRemaining += 1
                    this._totalLevelDots += 1
                } else if (ch = "o") {
                    cellVal := 3
                    this._dotsRemaining += 1
                    this._totalLevelDots += 1
                } else if (ch = "-")
                    cellVal := 4
                rowArr.Push(cellVal)
            }
            this._grid.Push(rowArr)
        }

        this._fruitActive := false
        this._fruitTimerSec := 0.0
        this._fruitPoints := this._GetLevelFruitPoints(this._level)
        this._fruit70Spawned := false
        this._fruit170Spawned := false

        this._waveIdx := 1
        this._waveTimerSec := 0.0
        this._waveMode := "scatter"
        this._waveTransitions := 0
        this._frightenedSec := 0.0
        this._frightCombo := 0

        this._ResetActors()
        ; Consume starting tile pellet if any
        this._ConsumeRunnerTile(this._runnerCol, this._runnerRow)
    }

    static _ResetActors() {
        this._runnerCol := 13
        this._runnerRow := 23
        this._runnerDx := -1
        this._runnerDy := 0
        this._nextDir := { dx: -1, dy: 0 }
        this._runnerStepAccum := 0.0

        baseState := (this._frightenedSec > 0.0) ? "frightened" : this._waveMode
        this._chasers := [
            {
                name: "blinky",
                col: 13,
                row: 11,
                dx: -1,
                dy: 0,
                state: baseState,
                scatterCol: 25,
                scatterRow: 0,
                color: 0xFFEF4444,
                stepAccum: 0.0
            },
            {
                name: "pinky",
                col: 14,
                row: 11,
                dx: 1,
                dy: 0,
                state: baseState,
                scatterCol: 2,
                scatterRow: 0,
                color: 0xFFF472B6,
                stepAccum: 0.0
            },
            {
                name: "inky",
                col: 12,
                row: 14,
                dx: 0,
                dy: -1,
                state: baseState,
                scatterCol: 27,
                scatterRow: 30,
                color: 0xFF38BDF8,
                stepAccum: 0.0
            },
            {
                name: "clyde",
                col: 15,
                row: 14,
                dx: 0,
                dy: -1,
                state: baseState,
                scatterCol: 0,
                scatterRow: 30,
                color: 0xFFF59E0B,
                stepAccum: 0.0
            }
        ]
    }

    static _GetLevelFruitPoints(lvl) {
        idx := Min(this._FRUIT_TABLE.Length, Max(1, Integer(lvl)))
        return this._FRUIT_TABLE[idx]
    }

    static _GetCell(col, row) {
        if (row < 0 || row >= this.ROWS)
            return 1
        if (col < 0 || col >= this.COLS)
            return (row == this.TUNNEL_ROW) ? 0 : 1
        return this._grid[row + 1][col + 1]
    }

    static _SetCell(col, row, val) {
        if (row >= 0 && row < this.ROWS && col >= 0 && col < this.COLS)
            this._grid[row + 1][col + 1] := val
    }

    static _CanRunnerEnter(col, row) {
        if (row == this.TUNNEL_ROW && (col < 0 || col >= this.COLS))
            return true
        cell := this._GetCell(col, row)
        return (cell != 1 && cell != 4)
    }

    static _CanChaserEnter(col, row, chaserState := "chase") {
        if (row == this.TUNNEL_ROW && (col < 0 || col >= this.COLS))
            return true
        cell := this._GetCell(col, row)
        if (cell == 1)
            return false
        return true
    }

    static _WrapTunnel(col, row, dx := 0) {
        c := Integer(col)
        r := Integer(row)
        d := Integer(dx)
        if (r == this.TUNNEL_ROW) {
            if (c < 0 || (c == 0 && d < 0))
                c := this.COLS - 1
            else if (c >= this.COLS || (c == this.COLS - 1 && d > 0))
                c := 0
        } else {
            c := Max(0, Min(this.COLS - 1, c))
        }
        inTunnel := (r == this.TUNNEL_ROW && (c <= 4 || c >= 23))
        return {
            col: c,
            row: r,
            isTunnel: inTunnel,
            speedScale: inTunnel ? 0.55 : 1.0
        }
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
        dt := Min(0.5, Max(0.0001, Float(dtSec)))
        dtMs := dt * 1000.0
        this._animTimeSec += dt

        if (readHardwareInput) {
            gp := HudArcadeBase.PollXInput()
            if (IsObject(gp)) {
                if ((gp.btn & 0x0001) || gp.ly > 14000)
                    this.QueueDir(0, -1)
                else if ((gp.btn & 0x0002) || gp.ly < -14000)
                    this.QueueDir(0, 1)
                else if ((gp.btn & 0x0004) || gp.lx < -14000)
                    this.QueueDir(-1, 0)
                else if ((gp.btn & 0x0008) || gp.lx > 14000)
                    this.QueueDir(1, 0)
            }
        }

        ; Update Frightened Mode timer or Scatter <-> Chase wave timer
        if (this._frightenedSec > 0.0) {
            this._frightenedSec := Max(0.0, this._frightenedSec - dt)
            if (this._frightenedSec <= 0.0) {
                this._frightCombo := 0
                for _, ch in this._chasers {
                    if (ch.state = "frightened")
                        ch.state := this._waveMode
                }
            }
        } else {
            this._AdvanceWaveTimer(dt)
        }

        ; Update Bonus Neon Fruit timer
        if (this._fruitActive) {
            this._fruitTimerSec := Max(0.0, this._fruitTimerSec - dt)
            if (this._fruitTimerSec <= 0.0)
                this._fruitActive := false
        }

        ; Runner step progression
        runnerRate := Min(14.0, 9.5 + Float(this._level - 1) * 0.45)
        this._runnerStepAccum += runnerRate * dt
        while (this._runnerStepAccum >= 1.0 && this.Phase = "playing") {
            this._runnerStepAccum -= 1.0
            this._StepRunnerOnce()
        }

        ; Chaser step progression
        baseChaserRate := Min(13.2, 8.8 + Float(this._level - 1) * 0.42)
        for idx, ch in this._chasers {
            rateMult := 1.0
            if (ch.state = "eyes")
                rateMult := 2.1
            else if (ch.state = "frightened")
                rateMult := 0.62
            else if (ch.row == this.TUNNEL_ROW && (ch.col <= 4 || ch.col >= 23))
                rateMult := 0.55

            ch.stepAccum += baseChaserRate * rateMult * dt
            while (ch.stepAccum >= 1.0 && this.Phase = "playing") {
                ch.stepAccum -= 1.0
                this._StepChaserOnce(idx)
            }
        }

        ; Update floating score popups
        pIdx := this._popups.Length
        while (pIdx >= 1) {
            pp := this._popups[pIdx]
            pp.ttlMs -= dtMs
            if (pp.ttlMs <= 0.0)
                this._popups.RemoveAt(pIdx)
            else
                pp.y -= 22.0 * dt
            pIdx -= 1
        }
    }

    static _AdvanceWaveTimer(dt) {
        this._waveTimerSec += dt
        while (this._waveIdx < this._WAVE_SCHEDULE.Length) {
            curWave := this._WAVE_SCHEDULE[this._waveIdx]
            if (this._waveTimerSec < curWave.dur)
                break
            this._waveTimerSec -= curWave.dur
            this._waveIdx += 1
            nextMode := this._WAVE_SCHEDULE[this._waveIdx].mode
            if (nextMode != this._waveMode) {
                this._waveMode := nextMode
                this._waveTransitions += 1
                ; Authentic Pac-Man reverses active chasers on wave phase transitions
                for _, ch in this._chasers {
                    if (ch.state != "eyes") {
                        ch.dx := -ch.dx
                        ch.dy := -ch.dy
                        if (ch.state != "frightened")
                            ch.state := this._waveMode
                    }
                }
            }
        }
    }

    static _StepRunnerOnce() {
        ; Try applying buffered turn (_nextDir) at current corridor intersection
        qd := this._nextDir
        if (this._CanRunnerEnter(this._runnerCol + qd.dx, this._runnerRow + qd.dy)) {
            this._runnerDx := qd.dx
            this._runnerDy := qd.dy
        }

        rawCol := this._runnerCol + this._runnerDx
        rawRow := this._runnerRow + this._runnerDy

        if (rawRow == this.TUNNEL_ROW && (rawCol < 0 || rawCol >= this.COLS)) {
            wrapped := this._WrapTunnel(rawCol, rawRow, 0)
            this._runnerCol := wrapped.col
            this._runnerRow := wrapped.row
        } else if (this._CanRunnerEnter(rawCol, rawRow)) {
            this._runnerCol := rawCol
            this._runnerRow := rawRow
        }

        this._ConsumeRunnerTile(this._runnerCol, this._runnerRow)
        this._CheckChaserCollisions()
    }

    static _ConsumeRunnerTile(col, row) {
        cell := this._GetCell(col, row)
        if (cell == 2) {
            this._SetCell(col, row, 0)
            this._dotsEaten += 1
            this._dotsRemaining := Max(0, this._dotsRemaining - 1)
            this._AddScore(10, col, row, 0xFFF8FAFC, false)
            this._CheckFruitSpawnTriggers()
        } else if (cell == 3) {
            this._SetCell(col, row, 0)
            this._dotsEaten += 1
            this._dotsRemaining := Max(0, this._dotsRemaining - 1)
            this._TriggerPowerOrb(col, row)
            this._CheckFruitSpawnTriggers()
        }

        if (this._fruitActive && col == this._fruitCol && row == this._fruitRow) {
            this._fruitActive := false
            this._AddScore(this._fruitPoints, col, row, 0xFF34D399, true)
        }

        if (this._dotsRemaining <= 0 && this._totalLevelDots > 0) {
            this._LoadMazeLevel(this._level + 1)
        }
    }

    static _TriggerPowerOrb(col, row) {
        this._AddScore(50, col, row, 0xFF38BDF8, true)
        this._frightenedSec := 7.0
        this._frightCombo := 0
        for _, ch in this._chasers {
            if (ch.state != "eyes") {
                ch.state := "frightened"
                ch.dx := -ch.dx
                ch.dy := -ch.dy
            }
        }
    }

    static _CheckFruitSpawnTriggers() {
        if (!this._fruit70Spawned && this._dotsEaten >= 70) {
            this._fruit70Spawned := true
            this._SpawnBonusFruit()
        }
        if (!this._fruit170Spawned && this._dotsEaten >= 170) {
            this._fruit170Spawned := true
            this._SpawnBonusFruit()
        }
    }

    static _SpawnBonusFruit() {
        this._fruitActive := true
        this._fruitCol := this.FRUIT_COL
        this._fruitRow := this.FRUIT_ROW
        this._fruitTimerSec := 9.5
        this._fruitPoints := this._GetLevelFruitPoints(this._level)
    }

    static _StepChaserOnce(chaserIdx) {
        if (chaserIdx < 1 || chaserIdx > this._chasers.Length)
            return
        ch := this._chasers[chaserIdx]

        ; Returning eyes inside or adjacent to central ghost pen regenerate immediately
        if (ch.state = "eyes") {
            if ((ch.col == this.PEN_COL_L || ch.col == this.PEN_COL_R) && ch.row == this.PEN_ROW) {
                ch.state := (this._frightenedSec > 0.0) ? "frightened" : this._waveMode
                return
            }
        }

        target := this._GetChaserTargetTile(ch)
        bestDir := this._ChooseChaserStepDir(ch, target.col, target.row)
        ch.dx := bestDir.dx
        ch.dy := bestDir.dy

        rawCol := ch.col + ch.dx
        rawRow := ch.row + ch.dy
        if (rawRow == this.TUNNEL_ROW && (rawCol < 0 || rawCol >= this.COLS)) {
            wrapped := this._WrapTunnel(rawCol, rawRow, 0)
            ch.col := wrapped.col
            ch.row := wrapped.row
        } else if (this._CanChaserEnter(rawCol, rawRow, ch.state)) {
            ch.col := rawCol
            ch.row := rawRow
        }

        if (ch.state = "eyes") {
            if ((ch.col == this.PEN_COL_L || ch.col == this.PEN_COL_R) && ch.row == this.PEN_ROW) {
                ch.state := (this._frightenedSec > 0.0) ? "frightened" : this._waveMode
            }
        }

        this._CheckChaserCollisions()
    }

    static _GetChaserTargetTile(ch) {
        if (ch.state = "eyes")
            return { col: this.PEN_COL_L, row: this.PEN_ROW }
        if (ch.state = "scatter")
            return { col: ch.scatterCol, row: ch.scatterRow }
        if (ch.state = "frightened")
            return { col: ch.scatterCol, row: ch.scatterRow }
        return this.ComputePersonalityChaseTarget(ch.name)
    }

    static ComputePersonalityChaseTarget(personality) {
        p := StrLower(Trim(String(personality)))
        rc := this._runnerCol
        rr := this._runnerRow
        rdx := this._runnerDx
        rdy := this._runnerDy

        if (p = "blinky") {
            return { col: rc, row: rr, personality: "blinky", scatterCol: 25, scatterRow: 0 }
        }
        if (p = "pinky") {
            return {
                col: rc + rdx * 4,
                row: rr + rdy * 4,
                personality: "pinky",
                scatterCol: 2,
                scatterRow: 0
            }
        }
        if (p = "inky") {
            blinkyCol := (this._chasers.Length >= 1) ? this._chasers[1].col : 13
            blinkyRow := (this._chasers.Length >= 1) ? this._chasers[1].row : 11
            pivotCol := rc + rdx * 2
            pivotRow := rr + rdy * 2
            return {
                col: pivotCol * 2 - blinkyCol,
                row: pivotRow * 2 - blinkyRow,
                personality: "inky",
                pivotCol: pivotCol,
                pivotRow: pivotRow,
                scatterCol: 27,
                scatterRow: 30
            }
        }
        ; Clyde (Amber Roamer): targets runner when Euclidean distance > 8 tiles, else bottom-left scatter corner (0, 30)
        clydeCol := (this._chasers.Length >= 4) ? this._chasers[4].col : 0
        clydeRow := (this._chasers.Length >= 4) ? this._chasers[4].row : 30
        ddx := Float(clydeCol - rc)
        ddy := Float(clydeRow - rr)
        dist := Sqrt(ddx * ddx + ddy * ddy)
        if (dist > 8.0) {
            return { col: rc, row: rr, personality: "clyde", dist: dist, mode: "chase", scatterCol: 0, scatterRow: 30 }
        }
        return { col: 0, row: 30, personality: "clyde", dist: dist, mode: "scatter", scatterCol: 0, scatterRow: 30 }
    }

    static _ChooseChaserStepDir(ch, targetCol, targetRow) {
        ; Classic Pac-Man priority order: Up, Left, Down, Right (no 180 reversal unless dead-end)
        dirs := [
            { dx: 0, dy: -1 },
            { dx: -1, dy: 0 },
            { dx: 0, dy: 1 },
            { dx: 1, dy: 0 }
        ]

        ; If inside pen and not eyes, guide upward through pen door (13..14, 11)
        if (ch.state != "eyes" && ch.row >= 13 && ch.row <= 15 && ch.col >= 11 && ch.col <= 16) {
            targetCol := 13
            targetRow := 11
        }

        best := ""
        bestDistSq := 999999999.0
        fallback := { dx: -ch.dx, dy: -ch.dy }

        for _, d in dirs {
            if (d.dx == -ch.dx && d.dy == -ch.dy)
                continue
            nc := ch.col + d.dx
            nr := ch.row + d.dy
            if (!this._CanChaserEnter(nc, nr, ch.state))
                continue
            ; Prevent non-eyes chasers from re-entering pen door downward
            if (ch.state != "eyes" && this._GetCell(nc, nr) == 4 && d.dy > 0)
                continue
            distSq := Float((nc - targetCol) * (nc - targetCol) + (nr - targetRow) * (nr - targetRow))
            if (distSq < bestDistSq) {
                bestDistSq := distSq
                best := d
            }
        }
        return IsObject(best) ? best : fallback
    }

    static _CheckChaserCollisions() {
        for idx, ch in this._chasers {
            if (ch.col == this._runnerCol && ch.row == this._runnerRow) {
                if (ch.state = "frightened") {
                    this._ConsumeFrightenedChaser(idx)
                } else if (ch.state != "eyes") {
                    this._lives -= 1
                    if (this._lives <= 0) {
                        this._lives := 0
                        this.Phase := "gameover"
                        return
                    }
                    this._ResetActors()
                    return
                }
            }
        }
    }

    static _ConsumeFrightenedChaser(chaserIdx) {
        if (chaserIdx < 1 || chaserIdx > this._chasers.Length)
            return 0
        ch := this._chasers[chaserIdx]
        this._frightCombo += 1
        shift := Min(3, Max(0, this._frightCombo - 1))
        pts := 200 * (1 << shift) ; 200 -> 400 -> 800 -> 1600
        ch.state := "eyes"
        this._AddScore(pts, ch.col, ch.row, 0xFF38BDF8, true)
        return pts
    }

    static _AddScore(pts, col, row, colArgb, showPopup := true) {
        this._score += Integer(pts)
        if (this._score > this._highScore) {
            this._highScore := this._score
            HudArcadeBase.SaveHighScore(this._cfg, "pac_grid", this._highScore)
        }
        if (showPopup) {
            m := this._GetMazeMetrics()
            px := m.ox + (Float(col) + 0.5) * m.cellX
            py := m.oy + (Float(row) + 0.5) * m.cellY
            this._popups.Push({ x: px, y: py, text: "+" Integer(pts), ttlMs: 850.0, col: colArgb })
        }
    }

    static _GetMazeMetrics() {
        W := IsObject(this._surf) ? Float(this._surf.W) : 1280.0
        H := IsObject(this._surf) ? Float(this._surf.H) : 720.0
        if (this._expandedMode) {
            topY := 68.0
            padX := 16.0
            padBot := 14.0
            availW := Max(320.0, W - padX * 2.0)
            availH := Max(240.0, H - topY - padBot)
            cellX := availW / Float(this.COLS)
            cellY := availH / Float(this.ROWS)
            cell := Min(cellX, cellY)
            boardW := cellX * Float(this.COLS)
            boardH := cellY * Float(this.ROWS)
            ox := padX
            oy := topY
            return { W: W, H: H, ox: ox, oy: oy, cellX: cellX, cellY: cellY, cell: cell, boardW: boardW, boardH: boardH, expanded: true }
        }
        topY := 76.0
        botPad := 28.0
        availH := Max(240.0, H - topY - botPad)
        availW := Max(320.0, W - 80.0)
        cell := Floor(Min(availW / Float(this.COLS), availH / Float(this.ROWS)))
        cell := Max(8.0, cell)
        boardW := cell * Float(this.COLS)
        boardH := cell * Float(this.ROWS)
        ox := (W - boardW) * 0.5
        oy := topY + (availH - boardH) * 0.5
        return { W: W, H: H, ox: ox, oy: oy, cellX: cell, cellY: cell, cell: cell, boardW: boardW, boardH: boardH, expanded: false }
    }

    ; --- Headless Test Helpers ---
    static QueueDirForTest(dx, dy) {
        return this.QueueDir(dx, dy)
    }

    static EatPowerOrbForTest() {
        this._dotsEaten += 1
        this._dotsRemaining := Max(0, this._dotsRemaining - 1)
        this._TriggerPowerOrb(this._runnerCol, this._runnerRow)
        this._CheckFruitSpawnTriggers()
        return this._frightenedSec
    }

    static EatChaserForTest(chaserIdx := 1) {
        idx := Max(1, Min(this._chasers.Length, Integer(chaserIdx)))
        return this._ConsumeFrightenedChaser(idx)
    }

    static ComputeChaserTargetForTest(personality) {
        return this.ComputePersonalityChaseTarget(personality)
    }

    static SetDotsEatenForTest(count) {
        this._dotsEaten := Max(0, Integer(count))
        this._CheckFruitSpawnTriggers()
        return {
            dotsEaten: this._dotsEaten,
            fruitActive: this._fruitActive,
            fruitPoints: this._fruitPoints,
            fruit70Spawned: this._fruit70Spawned,
            fruit170Spawned: this._fruit170Spawned
        }
    }

    static WrapTunnelForTest(col, row, dx := 0) {
        return this._WrapTunnel(col, row, dx)
    }

    static SetRunnerForTest(col, row, dx := -1, dy := 0) {
        this._runnerCol := Integer(col)
        this._runnerRow := Integer(row)
        this._runnerDx := Integer(dx)
        this._runnerDy := Integer(dy)
        this._nextDir := { dx: Integer(dx), dy: Integer(dy) }
    }

    static SetChaserForTest(chaserIdx, col, row, dx := 0, dy := -1, state := "") {
        idx := Max(1, Min(this._chasers.Length, Integer(chaserIdx)))
        ch := this._chasers[idx]
        ch.col := Integer(col)
        ch.row := Integer(row)
        ch.dx := Integer(dx)
        ch.dy := Integer(dy)
        if (state != "")
            ch.state := String(state)
        return ch
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
            lives: this._lives,
            level: this._level,
            cols: this.COLS,
            rows: this.ROWS,
            dotsEaten: this._dotsEaten,
            dotsRemaining: this._dotsRemaining,
            totalLevelDots: this._totalLevelDots,
            runnerCol: this._runnerCol,
            runnerRow: this._runnerRow,
            runnerDx: this._runnerDx,
            runnerDy: this._runnerDy,
            nextDir: this._nextDir,
            frightenedSec: this._frightenedSec,
            frightCombo: this._frightCombo,
            waveMode: this._waveMode,
            waveIdx: this._waveIdx,
            waveTransitions: this._waveTransitions,
            fruitActive: this._fruitActive,
            fruitCol: this._fruitCol,
            fruitRow: this._fruitRow,
            fruitPoints: this._fruitPoints,
            fruit70Spawned: this._fruit70Spawned,
            fruit170Spawned: this._fruit170Spawned,
            chasers: this._chasers,
            popupCount: this._popups.Length,
            expandedMode: this._expandedMode
        }
    }

    static _RenderFrame() {
        if (!IsObject(this._surf) || !this._surf.pGraphics)
            return
        HudArcadeBase.BeginFrame(this._surf)
        g := this._surf.pGraphics
        m := this._GetMazeMetrics()

        ; Translucent board backdrop
        HudArcadeBase.FillRoundedRect(g, m.ox - 8.0, m.oy - 8.0, m.boardW + 16.0, m.boardH + 16.0, 14.0, 0x8C090D16)
        HudArcadeBase.StrokeRoundedRect(g, m.ox - 8.0, m.oy - 8.0, m.boardW + 16.0, m.boardH + 16.0, 14.0, 0xCC2563EB, 2.0)

        pPelletBrush := 0, pOrbBrush := 0
        DllCall("gdiplus\GdipCreateSolidFill", "UInt", 0xFFFDE68A, "Ptr*", &pPelletBrush)
        orbPulse := (Mod(Round(this._animTimeSec * 6.0), 2) == 0) ? 0xFF38BDF8 : 0xFFFACC15
        DllCall("gdiplus\GdipCreateSolidFill", "UInt", orbPulse, "Ptr*", &pOrbBrush)

        try {
            Loop this.ROWS {
                r := A_Index - 1
                rowArr := this._grid[A_Index]
                gy := m.oy + Float(r) * m.cellY
                Loop this.COLS {
                    c := A_Index - 1
                    cellVal := rowArr[A_Index]
                    gx := m.ox + Float(c) * m.cellX
                    if (cellVal == 1) {
                        HudArcadeBase.FillRoundedRect(g, gx + 1.0, gy + 1.0, Max(2.0, m.cellX - 2.0), Max(2.0, m.cellY - 2.0), 3.0, 0x441E3A8A)
                        HudArcadeBase.StrokeRoundedRect(g, gx + 1.0, gy + 1.0, Max(2.0, m.cellX - 2.0), Max(2.0, m.cellY - 2.0), 3.0, 0xCC3B82F6, 1.2)
                    } else if (cellVal == 2 && pPelletBrush) {
                        pr := Max(2.2, m.cell * 0.14)
                        DllCall("gdiplus\GdipFillEllipse", "Ptr", g, "Ptr", pPelletBrush, "Float", gx + m.cellX * 0.5 - pr, "Float", gy + m.cellY * 0.5 - pr, "Float", pr * 2.0, "Float", pr * 2.0)
                    } else if (cellVal == 3 && pOrbBrush) {
                        orad := Max(4.5, m.cell * 0.34)
                        DllCall("gdiplus\GdipFillEllipse", "Ptr", g, "Ptr", pOrbBrush, "Float", gx + m.cellX * 0.5 - orad, "Float", gy + m.cellY * 0.5 - orad, "Float", orad * 2.0, "Float", orad * 2.0)
                    } else if (cellVal == 4) {
                        HudArcadeBase.FillRoundedRect(g, gx, gy + m.cellY * 0.4, m.cellX, Max(2.5, m.cell * 0.2), 1.0, 0xFFF472B6)
                    }
                }
            }
        } finally {
            if (pOrbBrush)
                DllCall("gdiplus\GdipDeleteBrush", "Ptr", pOrbBrush)
            if (pPelletBrush)
                DllCall("gdiplus\GdipDeleteBrush", "Ptr", pPelletBrush)
        }

        ; Draw active Bonus Neon Fruit below ghost pen
        if (this._fruitActive) {
            fr := Max(4.0, (m.cell - 4.0) * 0.5)
            fcx := m.ox + (Float(this._fruitCol) + 0.5) * m.cellX
            fcy := m.oy + (Float(this._fruitRow) + 0.5) * m.cellY
            HudArcadeBase.FillRoundedRect(g, fcx - fr, fcy - fr, fr * 2.0, fr * 2.0, fr * 0.8, 0xFF10B981)
            HudArcadeBase.StrokeRoundedRect(g, fcx - fr, fcy - fr, fr * 2.0, fr * 2.0, fr * 0.8, 0xFFA7F3D0, 1.5)
        }

        ; Draw Pac-Runner
        rr := Max(4.0, (m.cell - 2.0) * 0.5)
        rcx := m.ox + (Float(this._runnerCol) + 0.5) * m.cellX
        rcy := m.oy + (Float(this._runnerRow) + 0.5) * m.cellY
        HudArcadeBase.FillRoundedRect(g, rcx - rr, rcy - rr, rr * 2.0, rr * 2.0, rr, 0xFFFACC15)
        HudArcadeBase.StrokeRoundedRect(g, rcx - rr, rcy - rr, rr * 2.0, rr * 2.0, rr, 0xFFFEF08A, 1.5)

        ; Draw 4 Chasers (normal / frightened blue-flash / returning eyes)
        for _, ch in this._chasers {
            ccx := m.ox + (Float(ch.col) + 0.5) * m.cellX
            ccy := m.oy + (Float(ch.row) + 0.5) * m.cellY
            cr := Max(4.0, (m.cell - 2.0) * 0.5)
            if (ch.state = "eyes") {
                HudArcadeBase.FillRoundedRect(g, ccx - cr * 0.68, ccy - cr * 0.42, cr * 0.56, cr * 0.78, 3.0, 0xFFF8FAFC)
                HudArcadeBase.FillRoundedRect(g, ccx + cr * 0.12, ccy - cr * 0.42, cr * 0.56, cr * 0.78, 3.0, 0xFFF8FAFC)
            } else {
                bodyCol := ch.color
                if (ch.state = "frightened") {
                    flashing := (this._frightenedSec < 2.0 && Mod(Round(this._animTimeSec * 8.0), 2) == 0)
                    bodyCol := flashing ? 0xFFF8FAFC : 0xFF2563EB
                }
                HudArcadeBase.FillRoundedRect(g, ccx - cr, ccy - cr, cr * 2.0, cr * 2.0, 5.0, bodyCol)
                HudArcadeBase.StrokeRoundedRect(g, ccx - cr, ccy - cr, cr * 2.0, cr * 2.0, 5.0, 0xFFF8FAFC, 1.2)
            }
        }

        for _, pp in this._popups
            Gdip.DrawText(g, pp.text, "Segoe UI", 9.0, 1, pp.col, pp.x - 42.0, pp.y - 10.0, 84.0, 20.0, 1, 1, 0, false)

        isDark := IsSet(Theme) ? Theme.IsDarkMode() : true
        micMuted := (IsObject(this._state) && this._state.HasOwnProp("isMuted")) ? (this._state.isMuted ? 1 : 0) : -1
        modeLabel := (this._frightenedSec > 0.0) ? Format("FRIGHT ({:.1f}s)", this._frightenedSec) : StrUpper(this._waveMode)
        viewLabel := this._expandedMode ? "[F] View: Full" : "[F] View: Center"
        stats := Format("SCORE {}  •  BEST {}  •  LIVES {}  •  LVL {}  •  MODE: {}  •  {}",
            this._score, this._highScore, this._lives, this._level, modeLabel, viewLabel)
        hint := "Arrows / WASD: Buffered Turn  •  F: Center/Full View  •  P: Pause  •  R: Retry  •  Esc: Exit"
        HudArcadeBase.DrawScoreboardPill(g, m.W, "NEON PAC-GRID", stats, hint, isDark, micMuted)

        if (this.Phase = "paused") {
            HudArcadeBase.DrawOverlayCard(g, m.W, m.H, "PAC-GRID PAUSED",
                Format("Score: {}   •   Best: {}   •   Lives: {}   •   Level: {}", this._score, this._highScore, this._lives, this._level),
                "Press P to Resume   •   Esc to Exit", 0xFF38BDF8, isDark)
        } else if (this.Phase = "gameover") {
            HudArcadeBase.DrawOverlayCard(g, m.W, m.H, "GAME OVER — CAUGHT IN THE GRID",
                Format("Final Score: {}   •   High Score: {}   •   Level: {}", this._score, this._highScore, this._level),
                "Press R to Insert Coin & Retry   •   Esc to Exit", 0xFFEF4444, isDark)
        }

        HudArcadeBase.PresentFrame(this._surf)
    }
}
