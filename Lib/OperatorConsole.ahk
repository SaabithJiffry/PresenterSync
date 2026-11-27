#Requires AutoHotkey v2.0
; ============================================================================
; OperatorConsole.ahk - M8.1 Non-Suspending Primary Live Operator Console
; - Dockable, capture-excluded (ProtectWindowFromCapture), work-area-clamped
;   (WindowFit.Show), and NEVER calls Theme.AcquireSuspend() so hotkeys and
;   HUDs stay 100% live while operating.
; ============================================================================

class OperatorConsole {
    static _gui := ""
    static _cfg := ""
    static _state := ""
    static _timerFn := ""
    static _ctrls := Map()
    static _rosterIds := []
    static _lastRosterFp := ""
    static _lastSceneFp := Map()

    static IsOpen() {
        return IsObject(this._gui) && this._gui.Hwnd && WinExist("ahk_id " this._gui.Hwnd)
    }

    static Toggle(cfg, state) {
        if (this.IsOpen()) {
            this.Close()
            return false
        }
        return this.Show(cfg, state)
    }

    static Close(*) {
        if (IsObject(this._timerFn))
            try SetTimer(this._timerFn, 0)
        if (IsObject(this._gui)) {
            if (IsSet(Theme))
                try Theme.UnregisterWindow(this._gui, "PresenterSync - Live Operator Console")
            try this._gui.Destroy()
        }
        this._gui := ""
        this._ctrls := Map()
        this._rosterIds := []
        this._lastRosterFp := ""
        this._lastSceneFp := Map()
    }

    static Show(cfg, state) {
        this._cfg := cfg
        this._state := state
        if (this.IsOpen()) {
            try this._gui.Show()
            this.Refresh()
            return true
        }

        g := Gui("+Resize +MaximizeBox +MinSize540x420", "PresenterSync - Live Operator Console")
        g.MarginX := 12
        g.MarginY := 10
        if (IsSet(Theme)) {
            Theme.ApplyToWindow(g)
            Theme.NamedWindows["PresenterSync - Live Operator Console"] := g
        }
        g.SetFont("s9", "Segoe UI")
        this._gui := g
        c := Map()
        this._ctrls := c

        ; 1. Broadcast Telemetry Strip
        g.SetFont("s10 Bold")
        c["hdrStatus"] := g.AddText("xm w640", "MIC: --  |  REC: IDLE  |  STREAM: OFF  |  OBS: --")
        g.SetFont("s9 Norm")
        c["obsStats"] := g.AddText("xm y+4 w640 c666666", "OBS Stats: -- fps | Render -- ms | Skipped 0")

        ; 2. Scene & Transition Row
        gbScenes := g.AddGroupBox("xm y+10 w640 h78", "Scenes & Studio Transition")
        g.AddText("xp+12 yp+24 w65", "Program:")
        c["progDrop"] := g.AddDropDownList("x+6 yp-3 w175")
        g.AddText("x+12 yp+3 w55", "Preview:")
        c["prevDrop"] := g.AddDropDownList("x+6 yp-3 w175")
        c["btnTrans"] := g.AddButton("x+10 yp-1 w110 h26", "Transition")
        c["btnTrans"].OnEvent("Click", (*) => (IsSet(TriggerObsSceneTransition) ? TriggerObsSceneTransition(this._cfg, this._state, true) : 0, this.Refresh()))
        c["progDrop"].OnEvent("Change", (ctrl, *) => (ctrl.Text != "" && IsSet(ExecuteHostSwitchScene) ? ExecuteHostSwitchScene(this._cfg, this._state, ctrl.Text) : 0, this.Refresh()))
        c["prevDrop"].OnEvent("Change", (ctrl, *) => (ctrl.Text != "" && IsSet(ExecuteHostSetPreviewScene) ? ExecuteHostSetPreviewScene(this._cfg, this._state, ctrl.Text) : 0, this.Refresh()))

        ; 3. Audio, Timer, BRB & Panic Row
        gbLive := g.AddGroupBox("xm y+18 w640 h78", "Live Controls, Timer & Safety")
        c["btnMic"] := g.AddButton("xm+12 yp+24 w110 h28", "Toggle Mic")
        c["btnMic"].OnEvent("Click", (*) => (IsSet(ExecuteHostRemoteToggleMute) ? ExecuteHostRemoteToggleMute(this._cfg, this._state) : 0, this.Refresh()))
        c["btnRec"] := g.AddButton("x+8 yp w95 h28", "Rec / Stop")
        c["btnRec"].OnEvent("Click", (*) => (IsSet(ExecuteHostToggleRecord) ? ExecuteHostToggleRecord(this._cfg, this._state) : 0, this.Refresh()))
        c["btnBrb"] := g.AddButton("x+8 yp w85 h28", "BRB")
        c["btnBrb"].OnEvent("Click", (*) => (IsSet(ExecuteHostToggleStandby) ? ExecuteHostToggleStandby(this._cfg, this._state) : 0, this.Refresh()))
        c["btnPanic"] := g.AddButton("x+8 yp w105 h28", "PANIC")
        c["btnPanic"].OnEvent("Click", (*) => (IsSet(ExecuteHostEmergencyPanic) ? ExecuteHostEmergencyPanic(this._cfg, this._state) : 0, this.Refresh()))
        c["tmrLbl"] := g.AddText("x+14 yp+6 w90", "10:00")
        c["btnTmr"] := g.AddButton("x+4 yp-6 w85 h28", "Start/Pause")
        c["btnTmr"].OnEvent("Click", (*) => (IsSet(PauseHostPresenterTimer) ? PauseHostPresenterTimer(this._cfg, this._state) : 0, this.Refresh()))

        ; 4. Stage Intercom & Quick Nudges
        gbNudge := g.AddGroupBox("xm y+18 w640 h110", "Stage Intercom & Quick Nudges")
        c["nudgeIn"] := g.AddEdit("xm+12 yp+22 w490 h24")
        c["btnNudge"] := g.AddButton("x+8 yp-1 w115 h26", "Send Nudge")
        c["btnNudge"].OnEvent("Click", (*) => this._SendNudge())
        c["inbox"] := g.AddEdit("xm+12 y+8 w615 h44 ReadOnly -WantReturn", "")

        ; 5. Device Roster
        gbRoster := g.AddGroupBox("xm y+16 w640 h145", "Connected Remotes & Role Roster")
        c["roster"] := g.AddListView("xm+12 yp+20 w615 h82 Grid -Multi", ["Device", "Role", "Trust", "OBS FB", "State"])
        c["btnFlash"] := g.AddButton("xm+12 y+6 w95 h25", "Flash Pill")
        c["btnPauseDev"] := g.AddButton("x+8 yp w105 h25", "Pause Input")
        c["btnRole"] := g.AddButton("x+8 yp w115 h25", "Cycle Role")
        c["btnObsFb"] := g.AddButton("x+8 yp w135 h25", "Toggle OBS Fallback")
        c["btnFlash"].OnEvent("Click", (*) => this._RosterAction("flash"))
        c["btnPauseDev"].OnEvent("Click", (*) => this._RosterAction("pause"))
        c["btnRole"].OnEvent("Click", (*) => this._RosterAction("role"))
        c["btnObsFb"].OnEvent("Click", (*) => this._RosterAction("obsfb"))

        ; Footer
        c["btnBookmark"] := g.AddButton("xm y+14 w125 h28", "Bookmark Moment")
        c["btnBookmark"].OnEvent("Click", (*) => (IsSet(SessionTimeline) ? SessionTimeline.AddBookmark("Live Bookmark", this._state, "Operator") : 0, this.Refresh()))
        c["btnFocusConf"] := g.AddButton("x+8 yp w125 h28", "Focus Meet/Zoom")
        c["btnFocusConf"].OnEvent("Click", (*) => (IsSet(FocusConferencingWindow) ? FocusConferencingWindow(this._cfg) : 0))
        c["btnTurnover"] := g.AddButton("x+8 yp w175 h28", "End Session / Next Class")
        c["btnTurnover"].OnEvent("Click", (*) => (IsSet(ExecuteHostSessionTurnover) ? ExecuteHostSessionTurnover(this._cfg, this._state, true) : 0, this.Refresh()))
        c["btnClose"] := g.AddButton("x+8 yp w100 h28", "Close")
        c["btnClose"].OnEvent("Click", (*) => this.Close())

        if (IsSet(Theme)) {
            Theme.RegisterControl(g, c["hdrStatus"], "Text")
            Theme.RegisterControl(g, c["obsStats"], "Text", "muted")
            Theme.RegisterControl(g, c["progDrop"], "DropDownList")
            Theme.RegisterControl(g, c["prevDrop"], "DropDownList")
            Theme.RegisterControl(g, c["nudgeIn"], "Edit")
            Theme.RegisterControl(g, c["inbox"], "Edit")
            Theme.RegisterControl(g, c["roster"], "ListView")
            for _, bk in ["btnTrans", "btnMic", "btnRec", "btnBrb", "btnPanic", "btnTmr", "btnNudge", "btnFlash", "btnPauseDev", "btnRole", "btnObsFb", "btnBookmark", "btnFocusConf", "btnTurnover", "btnClose"]
                Theme.RegisterControl(g, c[bk], "Button")
        }

        if (IsSet(WindowFit)) {
            WindowFit.RegisterAnchor(g, c["hdrStatus"], {W: 1})
            WindowFit.RegisterAnchor(g, c["obsStats"], {W: 1})
            WindowFit.RegisterAnchor(g, gbScenes, {W: 1})
            WindowFit.RegisterAnchor(g, c["btnTrans"], {R: 1})
            WindowFit.RegisterAnchor(g, gbLive, {W: 1})
            WindowFit.RegisterAnchor(g, gbNudge, {W: 1})
            WindowFit.RegisterAnchor(g, c["nudgeIn"], {W: 1})
            WindowFit.RegisterAnchor(g, c["btnNudge"], {R: 1})
            WindowFit.RegisterAnchor(g, c["inbox"], {W: 1})
            WindowFit.RegisterAnchor(g, gbRoster, {W: 1, H: 1})
            WindowFit.RegisterAnchor(g, c["roster"], {W: 1, H: 1})
            WindowFit.RegisterAnchor(g, c["btnFlash"], {B: 1})
            WindowFit.RegisterAnchor(g, c["btnPauseDev"], {B: 1})
            WindowFit.RegisterAnchor(g, c["btnRole"], {B: 1})
            WindowFit.RegisterAnchor(g, c["btnObsFb"], {B: 1})
            WindowFit.RegisterAnchor(g, c["btnBookmark"], {FX: 0.0, FW: 0.25, B: 1})
            WindowFit.RegisterAnchor(g, c["btnFocusConf"], {FX: 0.25, FW: 0.25, B: 1})
            WindowFit.RegisterAnchor(g, c["btnTurnover"], {FX: 0.50, FW: 0.30, B: 1})
            WindowFit.RegisterAnchor(g, c["btnClose"], {FX: 0.80, FW: 0.20, B: 1})
        }

        g.OnEvent("Close", (*) => (this.Close(), 0))
        g.OnEvent("Escape", (*) => this.Close())
        if (IsSet(ProtectWindowFromCapture))
            try ProtectWindowFromCapture(g.Hwnd)

        if (IsSet(WindowFit))
            WindowFit.Show(g, "AutoSize Center")
        else
            g.Show("AutoSize Center")

        this.Refresh()
        this._timerFn := this.Refresh.Bind(this)
        SetTimer(this._timerFn, 1000)
        return true
    }

    static _SendNudge() {
        if (!this._ctrls.Has("nudgeIn"))
            return
        txt := Trim(this._ctrls["nudgeIn"].Value)
        if (txt != "" && IsSet(BroadcastHostStageNudge)) {
            BroadcastHostStageNudge(this._cfg, this._state, txt, "Operator")
            this._ctrls["nudgeIn"].Value := ""
            this.Refresh()
        }
    }

    static _RosterAction(kind) {
        global g_HostCompanionBridge
        if (!IsSet(g_HostCompanionBridge) || !IsObject(g_HostCompanionBridge) || !this._ctrls.Has("roster"))
            return
        lv := this._ctrls["roster"]
        row := lv.GetNext(0, "Focused")
        if (row <= 0)
            row := lv.GetNext(0)
        if (row <= 0)
            return
        targetId := (row <= this._rosterIds.Length) ? this._rosterIds[row] : ""
        if (targetId = "" || !g_HostCompanionBridge.pairedDevices.Has(targetId)) {
            devName := lv.GetText(row, 1)
            targetId := ""
            for devId, d in g_HostCompanionBridge.pairedDevices {
                lbl := (d.HasOwnProp("deviceName") && d.deviceName != "") ? d.deviceName : ((d.HasOwnProp("name") && d.name != "") ? d.name : devId)
                if (lbl = devName || devId = devName) {
                    targetId := devId
                    break
                }
            }
        }
        if (targetId = "" || !g_HostCompanionBridge.pairedDevices.Has(targetId))
            return
        if (kind = "flash")
            g_HostCompanionBridge.FlashDevicePill(targetId)
        else if (kind = "pause") {
            cur := g_HostCompanionBridge.pairedDevices[targetId].HasOwnProp("paused") ? !!g_HostCompanionBridge.pairedDevices[targetId].paused : false
            g_HostCompanionBridge.SetDevicePaused(targetId, !cur)
        } else if (kind = "role") {
            curR := g_HostCompanionBridge.pairedDevices[targetId].HasOwnProp("role") ? g_HostCompanionBridge.pairedDevices[targetId].role : "Presenter"
            nxt := (curR = "Tally-Only") ? "Presenter" : ((curR = "Presenter") ? "Director" : "Tally-Only")
            g_HostCompanionBridge.SetDeviceRole(targetId, nxt)
        } else if (kind = "obsfb") {
            curFb := g_HostCompanionBridge.pairedDevices[targetId].HasOwnProp("allowDirectObsFallback") ? !!g_HostCompanionBridge.pairedDevices[targetId].allowDirectObsFallback : false
            g_HostCompanionBridge.SetDeviceDirectObsFallback(targetId, !curFb)
        }
        this._lastRosterFp := ""
        this.Refresh()
    }

    static Refresh(*) {
        if (!this.IsOpen() || !IsObject(this._state))
            return
        st := this._state
        c := this._ctrls
        micTxt := (st.HasOwnProp("isMuted") && st.isMuted) ? "MUTED" : "LIVE"
        recTxt := (st.HasOwnProp("recState") && st.recState == 1) ? "REC" : ((st.HasOwnProp("recState") && st.recState == 2) ? "PAUSED" : "IDLE")
        strmTxt := (st.HasOwnProp("streamState") && st.streamState == 1) ? "LIVE" : ((st.HasOwnProp("streamState") && st.streamState == 2) ? "RECONN" : "OFF")
        obsTxt := (st.HasOwnProp("obsConnected") && st.obsConnected) ? "CONN" : "OFFLINE"
        c["hdrStatus"].Text := "MIC: " micTxt "  |  REC: " recTxt "  |  STREAM: " strmTxt "  |  OBS: " obsTxt (st.HasOwnProp("isStandby") && st.isStandby ? "  [BRB]" : "") (st.HasOwnProp("isPanic") && st.isPanic ? "  [PANIC]" : "")

        fps := st.HasOwnProp("obsActiveFps") ? Round(Float(st.obsActiveFps), 1) : 0.0
        avgMs := st.HasOwnProp("obsAvgRenderMs") ? Round(Float(st.obsAvgRenderMs), 1) : 0.0
        rSk := st.HasOwnProp("obsRenderSkipped") ? Integer(st.obsRenderSkipped) : 0
        oSk := st.HasOwnProp("obsOutputSkipped") ? Integer(st.obsOutputSkipped) : 0
        c["obsStats"].Text := "OBS Stats: " fps " fps | Render " avgMs " ms | Skipped " (rSk + oSk)

        tRem := st.HasOwnProp("timerRemainingSec") ? Integer(st.timerRemainingSec) : 600
        tSt := st.HasOwnProp("timerState") ? st.timerState : "stopped"
        if (IsSet(FormatCountdownClock))
            c["tmrLbl"].Text := FormatCountdownClock(tRem) " (" SubStr(tSt, 1, 3) ")"

        if (st.HasOwnProp("sceneList") && IsObject(st.sceneList) && st.sceneList.Length > 0) {
            curProg := st.HasOwnProp("currentSceneName") ? st.currentSceneName : ""
            curPrev := st.HasOwnProp("previewSceneName") ? st.previewSceneName : ""
            this._SyncSceneDrop(c["progDrop"], st.sceneList, curProg, "prog")
            this._SyncSceneDrop(c["prevDrop"], st.sceneList, curPrev, "prev")
        }

        if (IsSet(GetStageNudgeHistory)) {
            hist := GetStageNudgeHistory()
            lines := ""
            for idx, item in hist {
                if (idx > 3)
                    break
                lines .= (idx > 1 ? "`r`n" : "") "[" item.sender "] " item.message
            }
            if (lines != c["inbox"].Value)
                c["inbox"].Value := lines
        }

        global g_HostCompanionBridge
        if (IsSet(g_HostCompanionBridge) && IsObject(g_HostCompanionBridge)) {
            lv := c["roster"]
            fp := ""
            rows := []
            for devId, d in g_HostCompanionBridge.pairedDevices {
                lbl := (d.HasOwnProp("deviceName") && d.deviceName != "") ? d.deviceName : ((d.HasOwnProp("name") && d.name != "") ? d.name : devId)
                role := d.HasOwnProp("role") ? d.role : "Presenter"
                trust := d.HasOwnProp("trustTier") ? d.trustTier : "Guest"
                fb := (d.HasOwnProp("allowDirectObsFallback") && d.allowDirectObsFallback) ? "Yes" : "No"
                paused := (d.HasOwnProp("paused") && d.paused) ? "Paused" : "Active"
                fp .= devId "|" lbl "|" role "|" trust "|" fb "|" paused "`n"
                rows.Push({ id: devId, lbl: lbl, role: role, trust: trust, fb: fb, paused: paused })
            }
            if (fp != this._lastRosterFp) {
                selRow := lv.GetNext(0, "Focused")
                if (selRow <= 0)
                    selRow := lv.GetNext(0)
                selDevId := (selRow > 0 && selRow <= this._rosterIds.Length) ? this._rosterIds[selRow] : ""
                lv.Delete()
                this._rosterIds := []
                newSelRow := 0
                for idx, r in rows {
                    lv.Add("", r.lbl, r.role, r.trust, r.fb, r.paused)
                    this._rosterIds.Push(r.id)
                    if (selDevId != "" && r.id = selDevId)
                        newSelRow := idx
                }
                if (newSelRow > 0)
                    try lv.Modify(newSelRow, "Select Focus Vis")
                this._lastRosterFp := fp
            }
        }
    }

    static _SyncSceneDrop(ctrl, scenes, selected, key := "prog") {
        try {
            fp := ""
            for idx, s in scenes
                fp .= (idx > 1 ? "|" : "") s
            if (!this._lastSceneFp.Has(key) || this._lastSceneFp[key] != fp) {
                ctrl.Delete()
                ctrl.Add(scenes)
                this._lastSceneFp[key] := fp
            }
            if (selected != "" && !SendMessage(0x0157, 0, 0, ctrl.Hwnd)) {
                if (ctrl.Text != selected)
                    ctrl.Text := selected
            }
        }
    }
}
