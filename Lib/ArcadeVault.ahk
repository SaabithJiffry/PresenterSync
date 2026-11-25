; ==============================================================================
; Module: ArcadeVault.ahk
; Description: Confidential Master Arcade Vault (RAM-only unlock, INSERT COIN
;              passcode normalization, Ctrl+Alt+Shift+Z trigger/instant relock,
;              Sector Z clues, and About Vault drawer).
;              NEVER persists unlock state to INI, Registry, or disk.
; ==============================================================================

#Include "%A_LineFile%\..\HudArcadeBase.ahk"

class ArcadeVault {
    static IsUnlocked := false
    static _games := Map()
    static _gameOrder := []
    static _boundChords := []
    static _vaultHotkeyBound := false
    static _cfg := ""
    static _state := ""
    static _clueIdx := 0
    static _aboutContext := ""

    static NormalizePasscode(raw) {
        return StrUpper(RegExReplace(String(raw), "\s+", ""))
    }

    static ValidatePasscode(raw) {
        return this.NormalizePasscode(raw) == "INSERTCOIN"
    }

    static RegisterGame(id, title, chord, chordDisp, launchFn, stopFn := "") {
        gid := String(id)
        if (!this._games.Has(gid))
            this._gameOrder.Push(gid)
        this._games[gid] := {
            id: gid,
            title: String(title),
            chord: String(chord),
            chordDisp: String(chordDisp),
            launchFn: launchFn,
            stopFn: stopFn
        }
        if (this.IsUnlocked && IsObject(this._cfg))
            this._RebindGameHotkeys(this._cfg, this._state)
    }

    static GetRegisteredGames() {
        list := []
        for _, gid in this._gameOrder {
            if (this._games.Has(gid))
                list.Push(this._games[gid])
        }
        return list
    }

    static _MakeLauncherClosure(gid, cfg, state) {
        OnChord(*) {
            ArcadeVault.ToggleGame(gid, cfg, state)
        }
        return OnChord
    }

    static _UnbindGameHotkeys() {
        if (this._boundChords.Length == 0)
            return
        HotIf()
        try {
            for _, ch in this._boundChords {
                try Hotkey(ch, "Off")
            }
        } finally {
            HotIf
        }
        this._boundChords := []
    }

    static _RebindGameHotkeys(cfg, state) {
        this._UnbindGameHotkeys()
        if (!this.IsUnlocked)
            return
        HotIf()
        try {
            for _, gid in this._gameOrder {
                g := this._games[gid]
                if (g.chord = "")
                    continue
                try {
                    Hotkey(g.chord, this._MakeLauncherClosure(gid, cfg, state), "On")
                    this._boundChords.Push(g.chord)
                }
            }
        } finally {
            HotIf
        }
    }

    static BindVaultHotkey(cfg, state) {
        this._cfg := cfg
        this._state := state
        HotIf()
        try {
            Hotkey("!^+z", (*) => ArcadeVault.ToggleOrPrompt(cfg, state), "On")
            this._vaultHotkeyBound := true
        } finally {
            HotIf
        }
        if (this.IsUnlocked)
            this._RebindGameHotkeys(cfg, state)
    }

    static ToggleOrPrompt(cfg := "", state := "") {
        c := IsObject(cfg) ? cfg : this._cfg
        s := IsObject(state) ? state : this._state
        if (this.IsUnlocked) {
            this.Lock(c, s, true)
        } else {
            this.ShowPasscodeDialog(c, s)
        }
    }

    static Unlock(cfg := "", state := "", notify := true) {
        c := IsObject(cfg) ? cfg : this._cfg
        s := IsObject(state) ? state : this._state
        if (IsObject(c))
            this._cfg := c
        if (IsObject(s))
            this._state := s
        this.IsUnlocked := true
        this._RebindGameHotkeys(this._cfg, this._state)
        if (notify && (!IsSet(g_IsTestMode) || !g_IsTestMode)) {
            if (IsSet(ShowCaptureSafeMicroToast))
                ShowCaptureSafeMicroToast("ACCESS GRANTED // 99 CREDITS", 2200)
        }
        this._RefreshOpenAboutWindow()
        return true
    }

    static Lock(cfg := "", state := "", notify := true) {
        this.IsUnlocked := false
        HudArcadeBase.StopActiveGame()
        this._UnbindGameHotkeys()
        if (notify && (!IsSet(g_IsTestMode) || !g_IsTestMode)) {
            if (IsSet(ShowCaptureSafeMicroToast))
                ShowCaptureSafeMicroToast("VAULT LOCKED // 0 CREDITS", 1600)
        }
        this._RefreshOpenAboutWindow()
        return true
    }

    static ToggleGame(gameId, cfg := "", state := "") {
        gid := String(gameId)
        if (!this.IsUnlocked || !this._games.Has(gid))
            return false
        c := IsObject(cfg) ? cfg : this._cfg
        s := IsObject(state) ? state : this._state
        if (gid = "snake" && IsSet(HudSnake) && HudSnake.IsActive) {
            try HudSnake.Stop()
            return true
        }
        if (HudArcadeBase.ActiveGameId = gid) {
            HudArcadeBase.StopActiveGame()
            return true
        }
        HudArcadeBase.StopActiveGame()
        return this._games[gid].launchFn.Call(c, s)
    }

    static GetNextLockedClue() {
        this._clueIdx := Mod(this._clueIdx, 3) + 1
        switch this._clueIdx {
            case 1:
                return "ACCESS DENIED // CLEARANCE REQUIRED [0 CREDITS]"
            case 2:
                return "SLOT PROTOCOL: TWO CLASSIC WORDS REQUIRED AT SECTOR Z"
            default:
                return "HINT: WHAT DOES EVERY 1980s ARCADE CABINET ASK BEFORE PLAYER 1 STARTS?"
        }
    }

    static ShowPasscodeDialog(cfg := "", state := "") {
        c := IsObject(cfg) ? cfg : this._cfg
        s := IsObject(state) ? state : this._state
        existing := Theme.FocusExistingWindow("SectorZTerminal")
        if IsObject(existing)
            return existing

        dlg := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "SECTOR Z // TERMINAL")
        dlg._closed := false
        dlg.MarginX := 20
        dlg.MarginY := 16
        dlg.BackColor := "090B10"
        Theme.NamedWindows["SectorZTerminal"] := dlg
        if (IsSet(ProtectWindowFromCapture)) {
            try ProtectWindowFromCapture(dlg.Hwnd, true)
        } else if (IsSet(ApplyWindowCaptureAffinity)) {
            try ApplyWindowCaptureAffinity(dlg.Hwnd, true)
        } else {
            try DllCall("SetWindowDisplayAffinity", "Ptr", dlg.Hwnd, "UInt", 0x11, "Int")
        }

        dlg.SetFont("s10 w700", "Consolas")
        hdr := dlg.Add("Text", "xm w380 c38BDF8", "// PRESENTER SYNC :: SECTOR Z TERMINAL")
        dlg.SetFont("s9 w400", "Consolas")
        dlg.Add("Text", "xm w380 y+6 c94A3B8", "Clearance check active. Enter the two classic arcade words:")

        dlg.SetFont("s11 w700", "Consolas")
        dlg.Add("Text", "xm w120 y+14 cF59E0B", "PASSCODE >")
        edPass := dlg.Add("Edit", "x+6 yp-2 w254 h26 Background111622 c34D399")

        dlg.SetFont("s9 w600", "Consolas")
        lblStatus := dlg.Add("Text", "xm w380 y+12 c64748B", "CABINET STANDBY [0 CREDITS]  •  ESC TO ABORT")

        dlg.SetFont("s9 w700", "Consolas")
        btnAuth := dlg.Add("Button", "xm w186 h30 y+12 Default", "ENGAGE [ENTER]")
        btnAbort := dlg.Add("Button", "x+8 yp w186 h30", "ABORT [ESC]")

        CloseTerm(*) {
            if (dlg._closed)
                return
            dlg._closed := true
            Theme.UnregisterWindow(dlg, "SectorZTerminal")
            try dlg.Destroy()
        }

        TryUnlock(*) {
            if (dlg._closed)
                return
            val := edPass.Value
            if (ArcadeVault.ValidatePasscode(val)) {
                lblStatus.SetFont("c10B981")
                lblStatus.Value := "ACCESS GRANTED // 99 CREDITS"
                ArcadeVault.Unlock(c, s, false)
                SetTimer(CloseTerm, -350)
            } else {
                lblStatus.SetFont("cEF4444")
                lblStatus.Value := "ACCESS DENIED // INVALID PASSCODE"
                edPass.Value := ""
                edPass.Focus()
            }
        }

        btnAuth.OnEvent("Click", TryUnlock)
        btnAbort.OnEvent("Click", CloseTerm)
        dlg.OnEvent("Close", CloseTerm)
        dlg.OnEvent("Escape", CloseTerm)

        dlg.Show("AutoSize Center")
        edPass.Focus()
        return dlg
    }

    static AttachAboutVaultSection(aboutGui, cfg, state, x, y, w, isRemote := false, onRefreshFn := "") {
        this._aboutContext := { gui: aboutGui, cfg: cfg, state: state, isRemote: isRemote, refreshFn: onRefreshFn }
        if (!this.IsUnlocked) {
            aboutGui.SetFont("s8 w600", "Consolas")
            footerTxt := aboutGui.Add("Text", Format("x{} y{} w{} h22 Center", x, y, w), "ARCADE SUBSYSTEM: LOCKED [0 CREDITS]  •  SECTOR Z STANDBY")
            Theme.RegisterControl(aboutGui, footerTxt, "Text", "muted")
            OnFooterClick(*) {
                footerTxt.Value := ArcadeVault.GetNextLockedClue()
            }
            footerTxt.OnEvent("Click", OnFooterClick)
            footerTxt.OnEvent("DoubleClick", (*) => ArcadeVault.ShowPasscodeDialog(cfg, state))
            return 28
        }

        aboutGui.SetFont("s8.5 w700", "Consolas")
        hdr := aboutGui.Add("Text", Format("x{} y{} w{} h20 Center", x, y, w), "ARCADE VAULT: UNLOCKED [99 CREDITS]")
        Theme.RegisterControl(aboutGui, hdr, "Text", "accent")

        games := this.GetRegisteredGames()
        aboutGui.SetFont("s8.5 w600", Theme.UiFont)
        curY := y + 24
        colW := (w - 8) // 2
        rowIdx := 0
        for idx, g in games {
            col := Mod(idx - 1, 2)
            row := (idx - 1) // 2
            bx := x + col * (colW + 8)
            by := curY + row * 32
            b := aboutGui.Add("Button", Format("x{} y{} w{} h26", bx, by, colW), g.title " (" StrReplace(g.chordDisp, "Ctrl+Alt+Shift+", "^!+") ")")
            Theme.RegisterControl(aboutGui, b, "Button", "tabButton")
            b.OnEvent("Click", ((gid, c, s, *) => ArcadeVault.ToggleGame(gid, c, s)).Bind(g.id, cfg, state))
            rowIdx := row + 1
        }
        lockY := curY + Max(1, rowIdx) * 32 + 4
        btnLock := aboutGui.Add("Button", Format("x{} y{} w{} h26", x, lockY, w), "Lock Vault (Relock Now)")
        Theme.RegisterControl(aboutGui, btnLock, "Button")
        btnLock.OnEvent("Click", (*) => ArcadeVault.Lock(cfg, state))
        return (lockY + 32) - y
    }

    static _RefreshOpenAboutWindow() {
        ctx := this._aboutContext
        if (!IsObject(ctx) || !IsObject(ctx.gui))
            return
        try {
            if (!WinExist("ahk_id " ctx.gui.Hwnd))
                return
            winName := ctx.isRemote ? "AboutRemoteWindow" : "AboutWindow"
            Theme.UnregisterWindow(ctx.gui, winName)
            ctx.gui.Destroy()
            if (IsObject(ctx.refreshFn))
                ctx.refreshFn.Call(ctx.cfg, ctx.state)
            else if (ctx.isRemote && IsSet(ShowRemoteAboutUI))
                ShowRemoteAboutUI(ctx.cfg, ctx.state)
            else if (!ctx.isRemote && IsSet(ShowAboutWindow))
                ShowAboutWindow(ctx.cfg, ctx.state)
        }
    }
}
