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
            try this._gui.Destroy()
        }
        this._gui := ""
        this._ctrls := Map()
    }

    static Show(cfg, state) {
        this._cfg := cfg
        this._state := state
        if (this.IsOpen()) {
            try this._gui.Show()
            this.Refresh()
            return true
        }

        g := Gui("+Resize +MinSize540x420", "PresenterSync - Live Operator Console")
        g.MarginX := 12
        g.MarginY := 10
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
        g.AddGroupBox("xm y+10 w640 h78", "Scenes & Studio Transition")
        g.AddText("xp+12 yp+24 w65", "Program:")
        c["progDrop"] := g.AddDropDownList("x+6 yp-3 w175")
        g.AddText("x+12 yp+3 w55", "Preview:")
        c["prevDrop"] := g.AddDropDownList("x+6 yp-3 w175")
        c["btnTrans"] := g.AddButton("x+10 yp-1 w110 h26", "Transition")
        c["btnTrans"].OnEvent("Click", (*) => (IsSet(TriggerObsSceneTransition) ? TriggerObsSceneTransition(this._cfg, this._state, true) : 0, this.Refresh()))
        c["progDrop"].OnEvent("Change", (ctrl, *) => (ctrl.Text != "" && IsSet(ExecuteHostSwitchScene) ? ExecuteHostSwitchScene(this._cfg, this._state, ctrl.Text) : 0, this.Refresh()))
        c["prevDrop"].OnEvent("Change", (ctrl, *) => (ctrl.Text != "" && IsSet(ExecuteHostSetPreviewScene) ? ExecuteHostSetPreviewScene(this._cfg, this._state, ctrl.Text) : 0, this.Refresh()))

        ; 3. Audio, Timer, BRB & Panic Row
        g.AddGroupBox("xm y+18 w640 h78", "Live Controls, Timer & Safety")
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
        g.AddGroupBox("xm y+18 w640 h110", "Stage Intercom & Quick Nudges")
        c["nudgeIn"] := g.AddEdit("xm+12 yp+22 w490 h24")
        c["btnNudge"] := g.AddButton("x+8 yp-1 w115 h26", "Send Nudge")
        c["btnNudge"].OnEvent("Click", (*) => this._SendNudge())
        c["inbox"] := g.AddEdit("xm+12 y+8 w615 h44 ReadOnly -WantReturn", "")

        ; 5. Device Roster
        g.AddGroupBox("xm y+16 w640 h145", "Connected Remotes & Role Roster")
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
        c["btnClose"] := g.AddButton("xm y+14 w100 h28", "Close")
        c["btnClose"].OnEvent("Click", (*) => this.Close())

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
        if (!IsSet(g_HostBridge) || !IsObject(g_HostBridge) || !this._ctrls.Has("roster"))
            return
        lv := this._ctrls["roster"]
        row := lv.GetNext(0, "Focused")
        if (row <= 0)
            row := lv.GetNext(0)
        if (row <= 0)
            return
        devName := lv.GetText(row, 1)
        targetId := ""
        for devId, d in g_HostBridge.pairedDevices {
            lbl := (d.HasOwnProp("name") && d.name != "") ? d.name : devId
            if (lbl = devName || devId = devName) {
                targetId := devId
                break
            }
        }
        if (targetId = "")
            return
        if (kind = "flash")
            g_HostBridge.FlashDevicePill(targetId)
        else if (kind = "pause") {
            cur := g_HostBridge.pairedDevices[targetId].HasOwnProp("paused") ? !!g_HostBridge.pairedDevices[targetId].paused : false
            g_HostBridge.SetDevicePaused(targetId, !cur)
        } else if (kind = "role") {
            curR := g_HostBridge.pairedDevices[targetId].HasOwnProp("role") ? g_HostBridge.pairedDevices[targetId].role : "Presenter"
            nxt := (curR = "Tally-Only") ? "Presenter" : ((curR = "Presenter") ? "Director" : "Tally-Only")
            g_HostBridge.SetDeviceRole(targetId, nxt)
        } else if (kind = "obsfb") {
            curFb := g_HostBridge.pairedDevices[targetId].HasOwnProp("allowDirectObsFallback") ? !!g_HostBridge.pairedDevices[targetId].allowDirectObsFallback : false
            g_HostBridge.SetDeviceObsFallbackAllowed(targetId, !curFb)
        }
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
            this._SyncSceneDrop(c["progDrop"], st.sceneList, curProg)
            this._SyncSceneDrop(c["prevDrop"], st.sceneList, curPrev)
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

        if (IsSet(g_HostBridge) && IsObject(g_HostBridge)) {
            lv := c["roster"]
            lv.Delete()
            for devId, d in g_HostBridge.pairedDevices {
                lbl := (d.HasOwnProp("name") && d.name != "") ? d.name : devId
                role := d.HasOwnProp("role") ? d.role : "Presenter"
                trust := d.HasOwnProp("trustTier") ? d.trustTier : "Guest"
                fb := (d.HasOwnProp("allowDirectObsFallback") && d.allowDirectObsFallback) ? "Yes" : "No"
                paused := (d.HasOwnProp("paused") && d.paused) ? "Paused" : "Active"
                lv.Add("", lbl, role, trust, fb, paused)
            }
        }
    }

    static _SyncSceneDrop(ctrl, scenes, selected) {
        try {
            ctrl.Delete()
            ctrl.Add(scenes)
            if (selected != "")
                ctrl.Text := selected
        }
    }
}
