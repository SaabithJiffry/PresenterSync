; ==============================================================================
; Module: GUI_Config.ahk
; Description: UIConstants, Config & OverlayState classes, Settings GUIs, HUD layout & animations
; ==============================================================================

#Include "%A_LineFile%\..\Gdip.ahk"
#Include "%A_LineFile%\..\OBS_Network.ahk"

class UIConstants {
    ; --- Base HUD Dimensions & Ratios ---
    static BASE_WIDTH_TEXT := 140
    static BASE_WIDTH_ICON := 80
    static BASE_HEIGHT := 40
    static HUD_GAP := 6
    static MIN_HUD_GAP := 2
    static REC_HEIGHT := 34
    static ROW3_HEIGHT := 30
    static REC_WIDTH_RATIO := 0.53
    static STUDIO_WIDTH_RATIO := 0.38
    static SCREEN_MARGIN_X := 20
    static SCREEN_MARGIN_Y := 20
    static SCREEN_MIN_PAD := 10
    static MIN_TEXT_WIDTH := 8

    ; --- Typography & Control Offsets ---
    static MIC_ICON_SIZE := 18
    static MIC_TEXT_SIZE := 13
    static SUB_ICON_SIZE := 12
    static SUB_TEXT_SIZE := 8
    static STUDIO_ICON_SIZE_TEXT := 11
    static STUDIO_ICON_SIZE_ONLY := 12
    static STUDIO_TEXT_SIZE := 8
    static MINI_TEXT_SIZE := 9

    static MIC_ICON_W := 30
    static ICON_OFFSET_X := 15
    static MIC_TEXT_W := 80
    static TEXT_OFFSET_X := 50
    static REC_ICON_W := 14
    static REC_ICON_X := 4
    static CHAT_ICON_W := 14
    static CHAT_ICON_X := 4
    static STUDIO_ICON_W := 14
    static STUDIO_ICON_X := 4
    static SCENE_PAD_X := 4
    static LABEL_GAP_X := 2

    ; --- Animation & Timing Constants ---
    static FADE_STEPS := 10
    static FADE_SLEEP_MS := 10
    static POP_WIDTH_INC_TEXT := 1.5
    static POP_WIDTH_INC_ICON := 1.0
    static POP_HEIGHT_INC := 0.5
    static PULSE_STEP_AGGRESSIVE := 20
    static PULSE_STEP_NORMAL := 5
    static PULSE_INTERVAL_AGGRESSIVE := 15
    static PULSE_INTERVAL_NORMAL := 40
    static PULSE_MIN_RATIO_AGGRESSIVE := 0.2
    static PULSE_MIN_RATIO_NORMAL := 0.6
    static DRAG_SYNC_INTERVAL_MS := 16
    static PPT_DEBOUNCE_MS := 150
    static ZOOM_POLL_INTERVAL_MS := 500
    static ZOOM_REC_GRACE_MS := 1500
    static SYNC_LOCK_TIMEOUT_MS := 1000
    static OBS_RECONNECT_MS := 5000
    static OBS_INIT_DELAY_MS := 100
    static TOOLTIP_DURATION_MS := 2000

    ; --- Opacity Presets & Corner Constants ---
    static OPACITY_SOLID := 255
    static OPACITY_FROSTED := 220
    static OPACITY_GHOST := 127
    static CORNER_RADIUS_DEFAULT := 8
    static CORNER_RADIUS_SLEEK := 18

    ; --- Color Palette (RGB Strings & Hex Integers) ---
    static COLOR_LIVE := "22C55E"
    static COLOR_MUTED := "EF4444"
    static BORDER_LIVE := 0x5EC522
    static BORDER_MUTED := 0x4444EF
    static ICON_LIVE := "064E3B"
    static ICON_MUTED := "540808"

    static COLOR_REC_OFF := "374151"
    static BORDER_REC_OFF := 0x514137
    static ICON_REC_OFF := "9CA3AF"
    static COLOR_REC_ACTIVE := "DC2626"
    static BORDER_REC_ACTIVE := 0x2626DC
    static ICON_REC_ACTIVE := "7F1D1D"
    static COLOR_REC_PAUSED := "D97706"
    static BORDER_REC_PAUSED := 0x0677D9
    static ICON_REC_PAUSED := "78350F"

    static COLOR_STUDIO_OFF := "374151"
    static BORDER_STUDIO_OFF := 0x514137
    static ICON_STUDIO_OFF := "9CA3AF"
    static COLOR_STUDIO_ON := "7C3AED"
    static BORDER_STUDIO_ON := 0xED3A7C
    static ICON_STUDIO_ON := "4C1D95"

    static COLOR_SCENE := "1E293B"
    static BORDER_SCENE := 0x3B291E

    static COLOR_CHAT_CLEAR := "374151"
    static BORDER_CHAT_CLEAR := 0x514137
    static ICON_CHAT_CLEAR := "9CA3AF"
    static COLOR_CHAT_ALERT := "2563EB"
    static BORDER_CHAT_ALERT := 0xEB6325
    static ICON_CHAT_ALERT := "1E3A8A"
}

class Config {
    ConfigFile := ""
    AudioRoutingMode := 0
    ObsMuteHotkey := "None"
    ObsRecHotkey := "^F9"
    ObsPauseHotkey := "^F10"
    ZoomMuteHotkey := "!a"
    ZoomRecHotkey := "!r"
    ZoomPauseHotkey := "!p"
    obsPassword := ""
    targetMicName := "Mic/Aux"

    EnablePPT := false
    EnableMicOnly := false
    EnableWS := false
    EnableZoom := false

    ShowIndicator := true
    ShowExtraHuds := true
    ShowText := false
    MonoIcon := false
    SleekCorners := false
    AggressivePulse := false
    OpacityLevel := 220
    IndicatorScale := 1.0
    FirstRun := true
    IsMuted := false

    CatchArrows := true
    CatchPg := true
    CatchSpace := true
    CatchEnter := true
    CatchTab := true
    CatchEsc := true

    PptHotkey := "^F12"
    WsHotkey := "!F12"
    ZoomHotkey := "^!F12"
    IndHotkey := "^+F12"
    ExitHotkey := "!+F12"
    SuspendHotkey := "^!+F12"
    HwMuteHotkey := "b"

    savedX := "Default"
    savedY := "Default"

    __New(filePath := "") {
        this.ConfigFile := (filePath != "") ? filePath : A_ScriptDir "\MicOverlay_Config.ini"
        this.Load()
    }

    Read(section, key, defaultVal := "") {
        return IniRead(this.ConfigFile, section, key, defaultVal)
    }

    Write(section, key, val) {
        IniWrite(val, this.ConfigFile, section, key)
    }

    ReadBool(section, key, defaultValue := 0) {
        value := IniRead(this.ConfigFile, section, key, defaultValue)
        switch (StrLower(String(value))) {
            case "1", "true", "yes", "on":
                return true
            case "0", "false", "no", "off", "":
                return false
            default:
                try return !!Integer(value)
                catch
                    return !!defaultValue
        }
    }

    ReadInt(section, key, defaultValue := 0) {
        value := IniRead(this.ConfigFile, section, key, defaultValue)
        try return Integer(value)
        catch
            return defaultValue
    }

    ReadFloat(section, key, defaultValue := 1.0) {
        value := IniRead(this.ConfigFile, section, key, defaultValue)
        try return Float(value)
        catch
            return defaultValue
    }

    WriteBool(section, key, value) {
        IniWrite(value ? 1 : 0, this.ConfigFile, section, key)
    }

    Load() {
        this.AudioRoutingMode := this.ReadInt("Settings", "AudioRoutingMode", 0)
        if (this.AudioRoutingMode < 0 || this.AudioRoutingMode > 3)
            this.AudioRoutingMode := 0
        this.ObsMuteHotkey := this.Read("Settings", "ObsHotkey", "None")
        this.ObsRecHotkey := this.Read("Settings", "ObsRecHotkey", "")
        if (this.ObsRecHotkey = "") {
            this.ObsRecHotkey := "^F9"
            this.Write("Settings", "ObsRecHotkey", this.ObsRecHotkey)
        }
        this.ObsPauseHotkey := this.Read("Settings", "ObsPauseHotkey", "")
        if (this.ObsPauseHotkey = "") {
            this.ObsPauseHotkey := "^F10"
            this.Write("Settings", "ObsPauseHotkey", this.ObsPauseHotkey)
        }
        this.ZoomMuteHotkey := this.Read("Settings", "ZoomMuteHotkey", "!a")
        this.ZoomRecHotkey := this.Read("Settings", "ZoomRecHotkey", "")
        if (this.ZoomRecHotkey = "") {
            this.ZoomRecHotkey := "!r"
            this.Write("Settings", "ZoomRecHotkey", this.ZoomRecHotkey)
        }
        this.ZoomPauseHotkey := this.Read("Settings", "ZoomPauseHotkey", "")
        if (this.ZoomPauseHotkey = "") {
            this.ZoomPauseHotkey := "!p"
            this.Write("Settings", "ZoomPauseHotkey", this.ZoomPauseHotkey)
        }
        this.obsPassword := this.Read("Settings", "ObsPassword", "")
        this.targetMicName := this.Read("Settings", "TargetMicName", "Mic/Aux")

        this.EnablePPT := this.ReadBool("Settings", "EnablePPT")
        this.EnableMicOnly := this.ReadBool("Settings", "EnableMicOnly")
        this.EnableWS := this.ReadBool("Settings", "EnableWS")
        this.EnableZoom := this.ReadBool("Settings", "EnableZoom")

        if (this.EnableWS && this.EnableZoom) {
            this.EnableZoom := false
            this.WriteBool("Settings", "EnableZoom", false)
        }

        this.ShowIndicator := this.ReadBool("Settings", "ShowIndicator", true)
        this.ShowExtraHuds := this.ReadBool("Settings", "ShowExtraHuds", true)
        this.ShowText := this.ReadBool("Settings", "ShowText")
        this.MonoIcon := this.ReadBool("Settings", "MonoIcon")
        this.SleekCorners := this.ReadBool("Settings", "SleekCorners")
        this.AggressivePulse := this.ReadBool("Settings", "AggressivePulse")
        this.OpacityLevel := this.ReadInt("Settings", "OpacityLevel", UIConstants.OPACITY_FROSTED)
        if (this.OpacityLevel < 1 || this.OpacityLevel > 255)
            this.OpacityLevel := UIConstants.OPACITY_FROSTED
        this.IndicatorScale := this.ReadFloat("Settings", "IndicatorScale", 1.0)
        if (this.IndicatorScale <= 0.0 || this.IndicatorScale > 10.0)
            this.IndicatorScale := 1.0
        this.FirstRun := this.ReadBool("Settings", "FirstRun", true)
        this.IsMuted := this.ReadBool("Settings", "IsMuted", false)

        this.CatchArrows := this.ReadBool("Pointer", "CatchArrows", true)
        this.CatchPg := this.ReadBool("Pointer", "CatchPg", true)
        this.CatchSpace := this.ReadBool("Pointer", "CatchSpace", true)
        this.CatchEnter := this.ReadBool("Pointer", "CatchEnter", true)
        this.CatchTab := this.ReadBool("Pointer", "CatchTab", true)
        this.CatchEsc := this.ReadBool("Pointer", "CatchEsc", true)

        this.PptHotkey := this.Read("Settings", "PptHotkey", "^F12")
        this.WsHotkey := this.Read("Settings", "WsHotkey", "!F12")
        this.ZoomHotkey := this.Read("Settings", "ZoomHotkey", "^!F12")
        this.IndHotkey := this.Read("Settings", "IndHotkey", "^+F12")
        this.ExitHotkey := this.Read("Settings", "ExitHotkey", "!+F12")
        this.SuspendHotkey := this.Read("Settings", "SuspendHotkey", "^!+F12")
        this.HwMuteHotkey := this.Read("Settings", "HwMuteHotkey", "b")

        this.savedX := this.Read("Position", "X", "Default")
        this.savedY := this.Read("Position", "Y", "Default")
    }

    ResetAppearance() {
        this.ShowExtraHuds := true
        this.ShowText := false
        this.MonoIcon := false
        this.SleekCorners := false
        this.AggressivePulse := false
        this.OpacityLevel := UIConstants.OPACITY_FROSTED
        this.IndicatorScale := 1.0
        this.Write("Settings", "ShowExtraHuds", 1)
        this.Write("Settings", "ShowText", 0)
        this.Write("Settings", "MonoIcon", 0)
        this.Write("Settings", "SleekCorners", 0)
        this.Write("Settings", "AggressivePulse", 0)
        this.Write("Settings", "OpacityLevel", UIConstants.OPACITY_FROSTED)
        this.Write("Settings", "IndicatorScale", 1.0)
    }

    ResetPosition() {
        this.savedX := "Default"
        this.savedY := "Default"
        this.Write("Position", "X", "Default")
        this.Write("Position", "Y", "Default")
    }

    DeleteFile() {
        if FileExist(this.ConfigFile)
            FileDelete(this.ConfigFile)
    }
}

class OverlayState {
    obsWs := ""
    obsConnected := false
    zoomConnected := false
    IsSyncing := false
    zoomLastMuted := -1
    zoomRecGraceUntil := 0
    zoomSawRecControl := false

    isMuted := false
    recState := 0
    studioModeActive := false
    currentSceneName := "Scene"
    unreadChatCount := 0

    baseAlpha := 220
    currentAlpha := 220
    breathDir := -5

    isDraggingHud := false
    activeDragHwnd := 0

    dragTimerFn := ""
    breathTimerFn := ""
    obsTimerFn := ""
    zoomTimerFn := ""
    releaseSyncTimerFn := ""

    MicGui := ""
    RecGui := ""
    ChatGui := ""
    StudioGui := ""
    SceneGui := ""

    IconFont := ""

    baseWidth := 80
    baseHeight := 40
    hudGap := 6
    recHeight := 34
    recW := 40
    chatW := 34
    row3Height := 30
    studioW := 28
    sceneW := 46
    iconSize := 18
    textSize := 13
    subIconSize := 12
    subTextSize := 9
    miniTextSize := 9
    savedX := 0
    savedY := 0

    colors := {
        live: UIConstants.COLOR_LIVE,
        muted: UIConstants.COLOR_MUTED,
        borderLive: UIConstants.BORDER_LIVE,
        borderMuted: UIConstants.BORDER_MUTED,
        iconLive: UIConstants.ICON_LIVE,
        iconMuted: UIConstants.ICON_MUTED,
        recOff: UIConstants.COLOR_REC_OFF,
        recBorderOff: UIConstants.BORDER_REC_OFF,
        recIconOff: UIConstants.ICON_REC_OFF,
        recActive: UIConstants.COLOR_REC_ACTIVE,
        recBorderActive: UIConstants.BORDER_REC_ACTIVE,
        recIconActive: UIConstants.ICON_REC_ACTIVE,
        recPaused: UIConstants.COLOR_REC_PAUSED,
        recBorderPaused: UIConstants.BORDER_REC_PAUSED,
        recIconPaused: UIConstants.ICON_REC_PAUSED,
        studioOff: UIConstants.COLOR_STUDIO_OFF,
        studioBorderOff: UIConstants.BORDER_STUDIO_OFF,
        studioIconOff: UIConstants.ICON_STUDIO_OFF,
        studioOn: UIConstants.COLOR_STUDIO_ON,
        studioBorderOn: UIConstants.BORDER_STUDIO_ON,
        studioIconOn: UIConstants.ICON_STUDIO_ON,
        scene: UIConstants.COLOR_SCENE,
        sceneBorder: UIConstants.BORDER_SCENE,
        chatClear: UIConstants.COLOR_CHAT_CLEAR,
        chatBorderClear: UIConstants.BORDER_CHAT_CLEAR,
        chatIconClear: UIConstants.ICON_CHAT_CLEAR,
        chatAlert: UIConstants.COLOR_CHAT_ALERT,
        chatBorderAlert: UIConstants.BORDER_CHAT_ALERT,
        chatIconAlert: UIConstants.ICON_CHAT_ALERT
    }

    __New(cfg) {
        this.isMuted := cfg.IsMuted
        this.baseAlpha := cfg.OpacityLevel
        this.currentAlpha := cfg.OpacityLevel
        this.breathDir := cfg.AggressivePulse ? -UIConstants.PULSE_STEP_AGGRESSIVE : -UIConstants.PULSE_STEP_NORMAL

        osBuild := Integer(StrSplit(A_OSVersion, ".")[3])
        this.IconFont := (osBuild >= 22000) ? "Segoe Fluent Icons" : "Segoe MDL2 Assets"

        this.dragTimerFn := DragSyncTick.Bind(this)
        this.breathTimerFn := BreathingAnimation.Bind(cfg, this)
        this.obsTimerFn := ConnectToOBS.Bind(cfg, this)
        this.zoomTimerFn := ZoomStateMonitor.Bind(cfg, this)
        this.releaseSyncTimerFn := ReleaseSyncLock.Bind(this)

        this.ComputeDimensions(cfg)
    }

    ComputeDimensions(cfg) {
        this.baseWidth := Round((cfg.ShowText ? UIConstants.BASE_WIDTH_TEXT : UIConstants.BASE_WIDTH_ICON) * cfg.IndicatorScale)
        this.baseHeight := Round(UIConstants.BASE_HEIGHT * cfg.IndicatorScale)
        this.hudGap := Max(UIConstants.MIN_HUD_GAP, Round(UIConstants.HUD_GAP * cfg.IndicatorScale))
        this.recHeight := Round(UIConstants.REC_HEIGHT * cfg.IndicatorScale)
        this.recW := Round((this.baseWidth - this.hudGap) * UIConstants.REC_WIDTH_RATIO)
        this.chatW := this.baseWidth - this.hudGap - this.recW
        this.row3Height := Round(UIConstants.ROW3_HEIGHT * cfg.IndicatorScale)

        this.iconSize := Max(1, Round(UIConstants.MIC_ICON_SIZE * cfg.IndicatorScale))
        this.textSize := Max(1, Round(UIConstants.MIC_TEXT_SIZE * cfg.IndicatorScale))
        this.subIconSize := Max(1, Round(UIConstants.SUB_ICON_SIZE * cfg.IndicatorScale))
        this.subTextSize := Max(1, Round(UIConstants.SUB_TEXT_SIZE * cfg.IndicatorScale))
        this.miniTextSize := Max(1, Round(UIConstants.MINI_TEXT_SIZE * cfg.IndicatorScale))

        minStudioW := Round((this.baseWidth - this.hudGap) * UIConstants.STUDIO_WIDTH_RATIO)
        if (cfg.ShowText) {
            stIconW := Round(UIConstants.STUDIO_ICON_W * cfg.IndicatorScale)
            stIconX := Round(UIConstants.STUDIO_ICON_X * cfg.IndicatorScale)
            stTextSize := Max(1, Round(UIConstants.STUDIO_TEXT_SIZE * cfg.IndicatorScale))
            reqStudioW := stIconX + stIconW + Gdip.MeasureTextWidth("STUDIO", "Segoe UI", stTextSize, 1) + Round(2 * UIConstants.LABEL_GAP_X * cfg.IndicatorScale)
            this.studioW := Max(minStudioW, reqStudioW)
        } else {
            this.studioW := minStudioW
        }

        minSceneW := Max(UIConstants.MIN_TEXT_WIDTH, this.baseWidth - this.hudGap - this.studioW)
        scPad := Round(UIConstants.SCENE_PAD_X * cfg.IndicatorScale)
        reqSceneW := Gdip.MeasureTextWidth(this.currentSceneName, "Segoe UI", this.miniTextSize, 1) + (2 * scPad) + Round(4 * cfg.IndicatorScale)
        this.sceneW := Max(minSceneW, reqSceneW)

        maxRowW := Max(this.baseWidth, this.studioW + this.hudGap + this.sceneW, this.recW + this.hudGap + this.chatW)
        rawX := cfg.savedX
        rawY := cfg.savedY
        if (rawX = "Default" || rawY = "Default" || !IsInteger(rawX) || !IsInteger(rawY)) {
            MonitorGetWorkArea(1, &Left, &Top, &Right, &Bottom)
            stackTopPad := UIConstants.SCREEN_MIN_PAD + this.recHeight + this.row3Height + (2 * this.hudGap)
            this.savedX := Max(Left + UIConstants.SCREEN_MIN_PAD, Right - maxRowW - UIConstants.SCREEN_MARGIN_X)
            this.savedY := Max(Top + stackTopPad, Bottom - this.baseHeight - UIConstants.SCREEN_MARGIN_Y)
        } else {
            sx := Integer(rawX)
            sy := Integer(rawY)
            vLeft := SysGet(76), vTop := SysGet(77)
            vRight := vLeft + SysGet(78), vBottom := vTop + SysGet(79)
            stackTopPad := this.recHeight + this.row3Height + (2 * this.hudGap)
            this.savedX := Max(vLeft, Min(sx, vRight - maxRowW))
            this.savedY := Max(vTop + stackTopPad, Min(sy, vBottom - this.baseHeight))
        }
    }
}

SetTrayCheck(itemText, enabled) {
    if (enabled)
        A_TrayMenu.Check(itemText)
    else
        A_TrayMenu.Uncheck(itemText)
}

; --- SETUP & SETTINGS GUIS ---
BuildSettingsWindow(title, elementsArray, onSave := "", options := "") {
    opts := IsObject(options) ? options : {}
    doSuspend := opts.HasOwnProp("suspend") ? opts.suspend : true
    doShow := opts.HasOwnProp("show") ? opts.show : true
    doWaitClose := opts.HasOwnProp("waitClose") ? opts.waitClose : false
    wasSuspended := A_IsSuspended

    if (doSuspend)
        Suspend(True)

    dlg := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", title)
    if (opts.HasOwnProp("onClose") && opts.onClose) {
        dlg.OnEvent("Close", (*) => opts.onClose.Call(dlg))
    } else {
        dlg.OnEvent("Close", (*) => ((doSuspend && !wasSuspended) ? Suspend(False) : 0, dlg.Destroy()))
    }

    ctrls := Map()
    trackedElements := []

    HandleSave(*) {
        for el in trackedElements {
            if (el.HasOwnProp("required") && el.required && ctrls[el.id].Value = "") {
                dlg.Opt("+OwnDialogs")
                errTitle := el.HasOwnProp("errorTitle") ? el.errorTitle : "Error"
                errMsg := el.HasOwnProp("errorMsg") ? el.errorMsg : "Shortcuts cannot be left blank."
                MsgBox(errMsg, errTitle, "Icon!")
                return false
            }
        }
        values := Map()
        for el in trackedElements {
            values[el.id] := ctrls[el.id].Value
        }
        if (onSave != "")
            onSave(values, ctrls, dlg)
        return true
    }

    for el in elementsArray {
        t := el.type
        cOpts := el.HasOwnProp("opts") ? el.opts : ""
        val := el.HasOwnProp("value") ? el.value : ""
        txt := el.HasOwnProp("text") ? el.text : ""

        if (t = "DropDownList") {
            ctrl := dlg.Add("DropDownList", cOpts, el.items)
        } else if (t = "Checkbox") {
            chkOpt := (val != "") ? (" Checked" val) : ""
            ctrl := dlg.Add("Checkbox", cOpts chkOpt, txt)
        } else if (t = "Text" || t = "Button") {
            ctrl := dlg.Add(t, cOpts, txt)
        } else {
            ctrl := dlg.Add(t, cOpts, val)
        }

        if (el.HasOwnProp("id") && el.id != "") {
            ctrls[el.id] := ctrl
            if (t != "Text" && t != "Button")
                trackedElements.Push(el)
        }
        if (el.HasOwnProp("onChange") && el.onChange)
            ctrl.OnEvent("Change", el.onChange.Bind(ctrls, dlg))
        if (t = "Button" && el.HasOwnProp("isSave") && el.isSave)
            ctrl.OnEvent("Click", HandleSave)
    }

    if (opts.HasOwnProp("saveBtnText") && opts.saveBtnText != "") {
        saveBtnOpts := opts.HasOwnProp("saveBtnOpts") ? opts.saveBtnOpts : "w280 Default y+15"
        saveBtn := dlg.Add("Button", saveBtnOpts, opts.saveBtnText)
        saveBtn.OnEvent("Click", HandleSave)
    }

    dlg._ctrls := ctrls
    dlg._triggerSave := HandleSave

    if (opts.HasOwnProp("onInit") && opts.onInit)
        opts.onInit.Call(ctrls, dlg)

    if (doShow) {
        dlg.Show()
        if (doWaitClose)
            WinWaitClose(dlg.Hwnd)
    }
    return dlg
}

PromptForSetup(cfg) {
    wasSuspended := A_IsSuspended
    modes := [
        "1: Pro OBS Setup (VB-Cable)",
        "2: Standard Direct Mic (Zoom-Only)",
        "3: Dual App Sync (OBS + Zoom Direct)"
    ]
    initialMode := (cfg.AudioRoutingMode >= 1 && cfg.AudioRoutingMode <= 3) ? cfg.AudioRoutingMode : 1
    obsVal := (cfg.ObsMuteHotkey != "None") ? cfg.ObsMuteHotkey : ""
    zoomVal := (cfg.ZoomMuteHotkey != "") ? cfg.ZoomMuteHotkey : "!a"

    UpdateFieldStates(ctrls, dlg, *) {
        sel := ctrls["mode"].Value
        obsEnabled := (sel == 1 || sel == 3)
        zoomEnabled := (sel == 2 || sel == 3)
        ctrls["obsLbl"].Enabled := obsEnabled
        ctrls["obsHotkey"].Enabled := obsEnabled
        ctrls["zoomLbl"].Enabled := zoomEnabled
        ctrls["zoomHotkey"].Enabled := zoomEnabled
    }

    SaveSetup(values, ctrls, dlg) {
        sel := values["mode"]
        if ((sel == 1 || sel == 3) && values["obsHotkey"] = "") {
            dlg.Opt("+OwnDialogs")
            MsgBox("Please enter your OBS Mute shortcut.", "Setup", "Icon!")
            return
        }
        if ((sel == 2 || sel == 3) && values["zoomHotkey"] = "") {
            dlg.Opt("+OwnDialogs")
            MsgBox("Please enter your Zoom Mute shortcut.", "Setup", "Icon!")
            return
        }

        cfg.AudioRoutingMode := sel
        cfg.Write("Settings", "AudioRoutingMode", cfg.AudioRoutingMode)

        if (sel == 1 || sel == 3) {
            cfg.ObsMuteHotkey := values["obsHotkey"]
            cfg.Write("Settings", "ObsHotkey", cfg.ObsMuteHotkey)
        }
        if (sel == 2 || sel == 3) {
            cfg.ZoomMuteHotkey := values["zoomHotkey"]
            cfg.Write("Settings", "ZoomMuteHotkey", cfg.ZoomMuteHotkey)
        }

        if (!wasSuspended)
            Suspend(False)
        dlg.Destroy()
    }

    elements := [
        {type: "Text", opts: "w280", text: "Select your Audio Routing Profile:"},
        {type: "DropDownList", id: "mode", opts: "w280 Choose" initialMode, items: modes, onChange: UpdateFieldStates},
        {type: "Text", id: "obsLbl", opts: "w280 y+15", text: "OBS Mute Shortcut:"},
        {type: "Hotkey", id: "obsHotkey", opts: "w280", value: obsVal},
        {type: "Text", id: "zoomLbl", opts: "w280 y+10", text: "Zoom Mute Shortcut (Default Alt+A):"},
        {type: "Hotkey", id: "zoomHotkey", opts: "w280", value: zoomVal}
    ]

    BuildSettingsWindow("PresenterSync Audio Setup", elements, SaveSetup, {
        suspend: true,
        waitClose: true,
        onClose: (*) => ExitApp(),
        onInit: UpdateFieldStates,
        saveBtnText: "Save && Start",
        saveBtnOpts: "w280 Default y+15"
    })
}

PromptForPassword() {
    savedPw := ""

    SavePw(values, ctrls, dlg) {
        savedPw := values["password"]
        dlg.Destroy()
    }

    elements := [
        {type: "Text", opts: "w250", text: "Enter your OBS WebSocket Password:"},
        {type: "Edit", id: "password", opts: "w250 Password", required: true, errorTitle: "Setup", errorMsg: "Password cannot be empty."}
    ]

    BuildSettingsWindow("WebSocket Setup", elements, SavePw, {
        suspend: false,
        waitClose: true,
        onClose: (dlg) => dlg.Destroy(),
        saveBtnText: "Save & Connect",
        saveBtnOpts: "w250 Default y+15"
    })
    return savedPw
}

FormatHK(hk) {
    str := StrReplace(hk, "+", "Shift + ")
    str := StrReplace(str, "^", "Ctrl + ")
    str := StrReplace(str, "!", "Alt + ")
    str := StrReplace(str, "#", "Win + ")
    return str
}

ShowHelpWindow(cfg, *) {
    helpGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "PresenterSync Help & Guide")
    helpGui.SetFont("s10 w400", "Segoe UI")

    tabs := helpGui.Add("Tab3", "w420 h290", ["Shortcuts", "Pointer Modes", "OBS & Zoom Sync", "Pro Tips"])

    tabs.UseTab(1)
    helpGui.SetFont("s12 w700")
    helpGui.Add("Text", "x25 y45", "Global Keyboard Shortcuts")
    helpGui.SetFont("s10 w400")
    helpGui.Add("Text", "x25 y+15", FormatHK(cfg.PptHotkey) " :  Cycle Pointer Modes")
    helpGui.Add("Text", "x25 y+10", FormatHK(cfg.WsHotkey) " :  Toggle OBS WebSocket Sync")
    helpGui.Add("Text", "x25 y+10", FormatHK(cfg.ZoomHotkey) " :  Toggle Zoom Monitoring")
    helpGui.Add("Text", "x25 y+10", FormatHK(cfg.IndHotkey) " :  Hide/Unhide Indicator")
    helpGui.Add("Text", "x25 y+10", FormatHK(cfg.SuspendHotkey) " :  Suspend All Hotkeys")
    helpGui.Add("Text", "x25 y+10", FormatHK(cfg.ExitHotkey) " :  Exit PresenterSync")

    helpGui.SetFont("s9 italic cGray")
    helpGui.Add("Text", "x25 y+15 w370", "Note: You can rebind these shortcuts in the Settings menu.")

    tabs.UseTab(2)
    helpGui.SetFont("s12 w700")
    helpGui.Add("Text", "x25 y45", "Hardware Pointer Controls")
    helpGui.SetFont("s10 w400")
    helpGui.Add("Text", "x25 y+10 w370", "1. Full PPT + Mute:`nRoutes your clicker to PowerPoint while still allowing the hardware mute button to trigger OBS.`n`n2. Pointer Mute Only:`nBypasses PowerPoint completely. Your clicker only controls the mute overlay.`n`n* If you need to type normally while presenting, go to Settings > 'Configure Pointer Intercepts' to disable specific keys (like Space or Enter).")

    tabs.UseTab(3)
    helpGui.SetFont("s12 w700")
    helpGui.Add("Text", "x25 y45", "OBS WebSocket & Zoom UIA Sync")
    helpGui.SetFont("s10 w400")
    helpGui.Add("Text", "x25 y+10 w370", "• OBS WebSocket v5: Enable in OBS (Tools > WebSocket Server Settings) for instant 2-way mic sync.`n`n• Zoom UIA Monitoring: Provides 2-way background sync with Zoom even if a host mutes you or you click Mute in Zoom.`n`n• Zoom Requirement: In Zoom Settings > Accessibility (or General), check 'Always show meeting controls' so PresenterSync can read Zoom's toolbar reliably in the background.")

    tabs.UseTab(4)
    helpGui.SetFont("s12 w700")
    helpGui.Add("Text", "x25 y45", "Customizing & Smooth Animations")
    helpGui.SetFont("s10 w400")
    helpGui.Add("Text", "x25 y+10 w370", "• Repositioning HUD: Hold Left Click on the indicator to drag it anywhere. Coordinates save automatically.`n`n• Extra HUDs & Appearance: Toggle 'Show Extra HUDs' in the tray menu to show/hide the top telemetry rows, or use 'Indicator Appearance' to customize labels, opacity, scale, or pulse.`n`n• Smooth PPT Animations: To prevent Windows from throttling background animations, capture the Slideshow in OBS using Window Capture ('Windows 10 1903+') and set POWERPNT.EXE to 'High performance' in Windows Graphics Settings.")

    tabs.UseTab()

    btn := helpGui.Add("Button", "w100 x160 y310 Default", "Got it!")
    btn.OnEvent("Click", (*) => helpGui.Destroy())

    helpGui.Show("AutoSize")
}

ShowAboutWindow(*) {
    aboutGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "About PresenterSync")

    iconSource := A_IsCompiled ? A_ScriptFullPath : A_ScriptDir "\PresenterSync.ico"

    if FileExist(iconSource) {
        aboutGui.Add("Picture", "x143 y15 w64 h64", iconSource)
    }

    aboutGui.SetFont("s16 w700", "Segoe UI")
    aboutGui.Add("Text", "x10 w330 Center y+15", "PresenterSync")

    aboutGui.SetFont("s10 w400")
    aboutGui.Add("Text", "x10 w330 Center y+5", "Version 1.3.0")
    aboutGui.Add("Text", "x10 w330 Center y+15", "Created by Saabith Jiffry")

    gitBtn := aboutGui.Add("Button", "w110 x60 y+25", "GitHub Repo")
    gitBtn.OnEvent("Click", (*) => Run("https://github.com/SaabithJiffry/PresenterSync/"))

    closeBtn := aboutGui.Add("Button", "w110 x+10 Default", "Close")
    closeBtn.OnEvent("Click", (*) => aboutGui.Destroy())

    aboutGui.Show("AutoSize")
}

ChangeAppHotkeysUI(cfg, *) {
    SaveAppHk(values, ctrls, dlg) {
        cfg.Write("Settings", "PptHotkey", values["ppt"])
        cfg.Write("Settings", "WsHotkey", values["ws"])
        cfg.Write("Settings", "ZoomHotkey", values["zoom"])
        cfg.Write("Settings", "IndHotkey", values["ind"])
        cfg.Write("Settings", "SuspendHotkey", values["susp"])
        cfg.Write("Settings", "ExitHotkey", values["exit"])
        Reload()
    }

    elements := [
        {type: "Text", opts: "w150", text: "Cycle Pointer Mode:"},
        {type: "Hotkey", id: "ppt", opts: "x+10 w120", value: cfg.PptHotkey, required: true, errorMsg: "Shortcuts cannot be left blank."},
        {type: "Text", opts: "xm w150", text: "Toggle OBS WebSocket:"},
        {type: "Hotkey", id: "ws", opts: "x+10 w120", value: cfg.WsHotkey, required: true, errorMsg: "Shortcuts cannot be left blank."},
        {type: "Text", opts: "xm w150", text: "Toggle Zoom Monitor:"},
        {type: "Hotkey", id: "zoom", opts: "x+10 w120", value: cfg.ZoomHotkey, required: true, errorMsg: "Shortcuts cannot be left blank."},
        {type: "Text", opts: "xm w150", text: "Toggle Indicator:"},
        {type: "Hotkey", id: "ind", opts: "x+10 w120", value: cfg.IndHotkey, required: true, errorMsg: "Shortcuts cannot be left blank."},
        {type: "Text", opts: "xm w150", text: "Suspend Hotkeys:"},
        {type: "Hotkey", id: "susp", opts: "x+10 w120", value: cfg.SuspendHotkey},
        {type: "Text", opts: "xm w150", text: "Exit PresenterSync:"},
        {type: "Hotkey", id: "exit", opts: "x+10 w120", value: cfg.ExitHotkey, required: true, errorMsg: "Shortcuts cannot be left blank."}
    ]

    BuildSettingsWindow("Edit App Shortcuts", elements, SaveAppHk, {
        saveBtnText: "Save && Restart",
        saveBtnOpts: "xm w280 Default y+15"
    })
}

ChangeZoomShortcutsUI(cfg, *) {
    SaveZoomHk(values, ctrls, dlg) {
        cfg.Write("Settings", "ZoomMuteHotkey", values["mute"])
        cfg.Write("Settings", "ZoomRecHotkey", values["rec"] != "" ? values["rec"] : "!r")
        cfg.Write("Settings", "ZoomPauseHotkey", values["pause"] != "" ? values["pause"] : "!p")
        Reload()
    }

    elements := [
        {type: "Text", opts: "w280", text: "Zoom Mute Shortcut (Default Alt+A):"},
        {type: "Hotkey", id: "mute", opts: "w280", value: cfg.ZoomMuteHotkey, required: true, errorMsg: "Zoom Mute shortcut cannot be empty."},
        {type: "Text", opts: "w280 y+10", text: "Start/Stop Recording Shortcut (Default Alt+R):"},
        {type: "Hotkey", id: "rec", opts: "w280", value: cfg.ZoomRecHotkey},
        {type: "Text", opts: "w280 y+10", text: "Pause/Resume Recording Shortcut (Default Alt+P):"},
        {type: "Hotkey", id: "pause", opts: "w280", value: cfg.ZoomPauseHotkey}
    ]

    BuildSettingsWindow("Edit Zoom Shortcuts", elements, SaveZoomHk, {
        saveBtnText: "Save && Restart",
        saveBtnOpts: "w280 Default y+15"
    })
}

SetRoutingMode(cfg, mode, *) {
    cfg.Write("Settings", "AudioRoutingMode", mode)
    if ((mode == 2 || mode == 3) && cfg.ZoomMuteHotkey = "")
        cfg.Write("Settings", "ZoomMuteHotkey", "!a")
    Reload()
}

ChangeObsSettingsUI(cfg, *) {
    SaveObsSettings(values, ctrls, dlg) {
        cfg.Write("Settings", "ObsHotkey", values["mute"])
        cfg.Write("Settings", "ObsRecHotkey", values["rec"] != "" ? values["rec"] : "^F9")
        cfg.Write("Settings", "ObsPauseHotkey", values["pause"] != "" ? values["pause"] : "^F10")
        cfg.Write("Settings", "TargetMicName", values["mic"])
        Reload()
    }

    elements := [
        {type: "Text", opts: "w280", text: "OBS Mute Shortcut:"},
        {type: "Hotkey", id: "mute", opts: "w280", value: (cfg.ObsMuteHotkey != "None") ? cfg.ObsMuteHotkey : "", required: true, errorMsg: "OBS Mute shortcut and Audio Source Name cannot be empty."},
        {type: "Text", opts: "w280 y+10", text: "Start/Stop Recording Shortcut:"},
        {type: "Hotkey", id: "rec", opts: "w280", value: cfg.ObsRecHotkey},
        {type: "Text", opts: "w280 y+10", text: "Pause/Resume Recording Shortcut:"},
        {type: "Hotkey", id: "pause", opts: "w280", value: cfg.ObsPauseHotkey},
        {type: "Text", opts: "w280 y+10", text: "Exact OBS Audio Source Name (e.g., Mic/Aux):"},
        {type: "Edit", id: "mic", opts: "w280", value: cfg.targetMicName, required: true, errorMsg: "OBS Mute shortcut and Audio Source Name cannot be empty."}
    ]

    BuildSettingsWindow("OBS Settings", elements, SaveObsSettings, {
        saveBtnText: "Save && Restart",
        saveBtnOpts: "w280 Default y+15"
    })
}

ChangeHwMuteHotkeyUI(cfg, *) {
    SaveHwMuteHk(values, ctrls, dlg) {
        cfg.Write("Settings", "HwMuteHotkey", values["hwMute"])
        Reload()
    }

    elements := [
        {type: "Text", opts: "w250", text: "Focus the box below and press the button on your presentation clicker:"},
        {type: "Hotkey", id: "hwMute", opts: "w250", value: cfg.HwMuteHotkey, required: true, errorMsg: "Please press a button to register it."}
    ]

    BuildSettingsWindow("Edit Pointer Mute Button", elements, SaveHwMuteHk, {
        saveBtnText: "Save && Restart",
        saveBtnOpts: "w250 Default y+15"
    })
}

ConfigurePointerKeysUI(cfg, *) {
    SavePointerKeys(values, ctrls, dlg) {
        cfg.Write("Pointer", "CatchArrows", values["arrows"])
        cfg.Write("Pointer", "CatchPg", values["pg"])
        cfg.Write("Pointer", "CatchSpace", values["space"])
        cfg.Write("Pointer", "CatchEnter", values["enter"])
        cfg.Write("Pointer", "CatchTab", values["tab"])
        cfg.Write("Pointer", "CatchEsc", values["esc"])
        Reload()
    }

    elements := [
        {type: "Text", opts: "w250", text: "Select which keys to intercept in Full PPT Mode:"},
        {type: "Checkbox", id: "arrows", opts: "w250", value: cfg.CatchArrows, text: "Arrow Keys (Up, Down, Left, Right)"},
        {type: "Checkbox", id: "pg", opts: "w250", value: cfg.CatchPg, text: "Page Keys (PgUp, PgDn)"},
        {type: "Checkbox", id: "space", opts: "w250", value: cfg.CatchSpace, text: "Spacebar"},
        {type: "Checkbox", id: "enter", opts: "w250", value: cfg.CatchEnter, text: "Enter Key"},
        {type: "Checkbox", id: "tab", opts: "w250", value: cfg.CatchTab, text: "Tab Key"},
        {type: "Checkbox", id: "esc", opts: "w250", value: cfg.CatchEsc, text: "Escape Key"}
    ]

    BuildSettingsWindow("Configure Pointer Intercepts", elements, SavePointerKeys, {
        saveBtnText: "Save && Restart",
        saveBtnOpts: "w250 Default y+15"
    })
}

ShowPointerTester(*) {
    wasSuspended := A_IsSuspended
    Suspend(True)

    testerGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "Pointer Tester")

    testerGui.SetFont("s10", "Segoe UI")
    testerGui.Add("Text", "w250 Center", "Press any button on your clicker.")

    keyDisplay := testerGui.Add("Text", "w250 Center y+15", "Listening...")
    keyDisplay.SetFont("s14 w700 c0055CC")

    btn := testerGui.Add("Button", "w100 x75 y+20 Default", "Close")

    ih := InputHook("L0 V")
    ih.KeyOpt("{All}", "N")

    ih.OnKeyDown := (ih, VK, SC) => UpdateKeyDisplay(VK, SC)

    UpdateKeyDisplay(VK, SC) {
        keyName := GetKeyName(Format("vk{:X}sc{:X}", VK, SC))
        if WinExist(testerGui.Hwnd)
            keyDisplay.Value := keyName
    }

    Cleanup(*) {
        ih.Stop()
        if (!wasSuspended)
            Suspend(False)
        testerGui.Destroy()
    }

    testerGui.OnEvent("Close", Cleanup)
    btn.OnEvent("Click", Cleanup)

    testerGui.Show("AutoSize")
    ih.Start()
}

; --- HUD STATE SYNCHRONIZATION & APPEARANCE ---
GetCornerRadius(cfg, h) {
    return cfg.SleekCorners ? (h / 2.0) : Min(UIConstants.CORNER_RADIUS_DEFAULT * cfg.IndicatorScale, h / 2.0)
}

ApplyMicAppearance(cfg, state, customX := "", customY := "", customW := "", customH := "", customAlpha := "", overrideMuted := "") {
    if (!IsObject(state.MicGui))
        return false

    pos := ComputeHudLayout(state, state.savedX, state.savedY)
    x := (customX != "") ? customX : pos.micX
    y := (customY != "") ? customY : pos.micY
    w := (customW != "") ? customW : pos.micW
    h := (customH != "") ? customH : pos.micH
    alpha := (customAlpha != "") ? customAlpha : state.currentAlpha
    mutedState := (overrideMuted != "") ? overrideMuted : state.isMuted

    bgRgb := mutedState ? state.colors.muted : state.colors.live
    brdBgr := mutedState ? state.colors.borderMuted : state.colors.borderLive
    icHex := cfg.MonoIcon ? (mutedState ? state.colors.iconMuted : state.colors.iconLive) : "FFFFFF"
    glyph := mutedState ? Chr(0xF781) : Chr(0xE720)
    lbl := mutedState ? "MUTED" : "LIVE"
    contentArgb := Gdip.HexToArgb(icHex)

    if (cfg.ShowText) {
        offsetX := Round((w - state.baseWidth) / 2)
        iconW := Round(UIConstants.MIC_ICON_W * cfg.IndicatorScale)
        iconX := offsetX + Round(UIConstants.ICON_OFFSET_X * cfg.IndicatorScale)
        textW := Round(UIConstants.MIC_TEXT_W * cfg.IndicatorScale)
        textX := offsetX + Round(UIConstants.TEXT_OFFSET_X * cfg.IndicatorScale)
        iconCfg := {text: glyph, font: state.IconFont, size: state.iconSize, color: contentArgb, x: iconX, w: iconW}
        labelCfg := {text: lbl, size: state.textSize, bold: true, color: contentArgb, x: textX, w: textW, align: 0}
    } else {
        iconCfg := {text: glyph, font: state.IconFont, size: state.iconSize, color: contentArgb, x: 0, w: w}
        labelCfg := ""
    }

    return Gdip.RenderPill(state.MicGui.Hwnd, x, y, w, h, Gdip.HexToArgb(bgRgb), Gdip.BgrToArgb(brdBgr), alpha, GetCornerRadius(cfg, h), iconCfg, labelCfg)
}

SyncChatState(cfg, state, newCount) {
    if (state.unreadChatCount != newCount) {
        state.unreadChatCount := newCount
        ApplyChatAppearance(cfg, state)
    }
}

ApplyChatAppearance(cfg, state) {
    if (!IsObject(state.ChatGui))
        return false

    pos := ComputeHudLayout(state, state.savedX, state.savedY)
    hasUnread := (state.unreadChatCount > 0)
    bg := hasUnread ? state.colors.chatAlert : state.colors.chatClear
    brd := hasUnread ? state.colors.chatBorderAlert : state.colors.chatBorderClear
    ic := cfg.MonoIcon ? (hasUnread ? state.colors.chatIconAlert : state.colors.chatIconClear) : (hasUnread ? "FFFFFF" : "D1D5DB")
    contentArgb := Gdip.HexToArgb(ic)

    if (cfg.ShowText) {
        cIconW := Round(UIConstants.CHAT_ICON_W * cfg.IndicatorScale)
        cIconX := Round(UIConstants.CHAT_ICON_X * cfg.IndicatorScale)
        cTextX := cIconX + cIconW + Round(UIConstants.LABEL_GAP_X * cfg.IndicatorScale)
        cTextW := Max(UIConstants.MIN_TEXT_WIDTH, state.chatW - cTextX - Round(UIConstants.LABEL_GAP_X * cfg.IndicatorScale))
        lbl := hasUnread ? (state.unreadChatCount " NEW") : "CHAT"
        iconCfg := {text: Chr(0xE8BD), font: state.IconFont, size: state.subIconSize, color: contentArgb, x: cIconX, w: cIconW}
        labelCfg := {text: lbl, size: state.subTextSize, bold: true, color: contentArgb, x: cTextX, w: cTextW, align: 0}
    } else if (hasUnread) {
        iconCfg := ""
        labelCfg := {text: String(state.unreadChatCount), size: state.subTextSize, bold: true, color: contentArgb, x: 0, w: pos.chatW, align: 1}
    } else {
        iconCfg := {text: Chr(0xE8BD), font: state.IconFont, size: state.subIconSize, color: contentArgb, x: 0, w: pos.chatW}
        labelCfg := ""
    }

    return Gdip.RenderPill(state.ChatGui.Hwnd, pos.chatX, pos.chatY, pos.chatW, pos.chatH, Gdip.HexToArgb(bg), Gdip.BgrToArgb(brd), state.baseAlpha, GetCornerRadius(cfg, pos.chatH), iconCfg, labelCfg)
}

SyncStudioState(cfg, state, isEnabled) {
    if (state.studioModeActive != isEnabled) {
        state.studioModeActive := isEnabled
        ApplyStudioAppearance(cfg, state)
    }
}

ApplyStudioAppearance(cfg, state) {
    if (!IsObject(state.StudioGui))
        return false

    pos := ComputeHudLayout(state, state.savedX, state.savedY)
    bg := state.studioModeActive ? state.colors.studioOn : state.colors.studioOff
    brd := state.studioModeActive ? state.colors.studioBorderOn : state.colors.studioBorderOff
    ic := cfg.MonoIcon ? (state.studioModeActive ? state.colors.studioIconOn : state.colors.studioIconOff) : (state.studioModeActive ? "FFFFFF" : "D1D5DB")
    contentArgb := Gdip.HexToArgb(ic)

    if (cfg.ShowText) {
        stIconW := Round(UIConstants.STUDIO_ICON_W * cfg.IndicatorScale)
        stIconX := Round(UIConstants.STUDIO_ICON_X * cfg.IndicatorScale)
        stTextX := stIconX + stIconW
        stTextW := Max(UIConstants.MIN_TEXT_WIDTH, state.studioW - stTextX - Round(UIConstants.LABEL_GAP_X * cfg.IndicatorScale))
        stIconSize := Max(1, Round(UIConstants.STUDIO_ICON_SIZE_TEXT * cfg.IndicatorScale))
        stTextSize := Max(1, Round(UIConstants.STUDIO_TEXT_SIZE * cfg.IndicatorScale))
        iconCfg := {text: Chr(0xE7F4), font: state.IconFont, size: stIconSize, color: contentArgb, x: stIconX, w: stIconW}
        labelCfg := {text: "STUDIO", size: stTextSize, bold: true, color: contentArgb, x: stTextX, w: stTextW, align: 0}
    } else {
        stIconSize := Max(1, Round(UIConstants.STUDIO_ICON_SIZE_ONLY * cfg.IndicatorScale))
        iconCfg := {text: Chr(0xE7F4), font: state.IconFont, size: stIconSize, color: contentArgb, x: 0, w: pos.studioW}
        labelCfg := ""
    }

    return Gdip.RenderPill(state.StudioGui.Hwnd, pos.studioX, pos.studioY, pos.studioW, pos.studioH, Gdip.HexToArgb(bg), Gdip.BgrToArgb(brd), state.baseAlpha, GetCornerRadius(cfg, pos.studioH), iconCfg, labelCfg)
}

SyncSceneState(cfg, state, sceneName) {
    if (sceneName != "" && state.currentSceneName != sceneName) {
        state.currentSceneName := sceneName
        state.ComputeDimensions(cfg)
        UpdateHudLayout(state, state.savedX, state.savedY)
        ApplyMicAppearance(cfg, state)
        ApplyRecAppearance(cfg, state)
        ApplyChatAppearance(cfg, state)
        ApplyStudioAppearance(cfg, state)
        ApplySceneAppearance(cfg, state)
    }
}

ApplySceneAppearance(cfg, state) {
    if (!IsObject(state.SceneGui))
        return false

    pos := ComputeHudLayout(state, state.savedX, state.savedY)
    scPad := Round(UIConstants.SCENE_PAD_X * cfg.IndicatorScale)
    labelCfg := {
        text: state.currentSceneName,
        size: state.miniTextSize,
        bold: true,
        color: Gdip.HexToArgb("FFFFFF"),
        x: scPad,
        w: Max(UIConstants.MIN_TEXT_WIDTH, pos.sceneW - 2 * scPad),
        align: 1
    }
    return Gdip.RenderPill(state.SceneGui.Hwnd, pos.sceneX, pos.sceneY, pos.sceneW, pos.sceneH, Gdip.HexToArgb(state.colors.scene), Gdip.BgrToArgb(state.colors.sceneBorder), state.baseAlpha, GetCornerRadius(cfg, pos.sceneH), "", labelCfg)
}

SyncRecState(cfg, state, newState) {
    if (state.recState != newState) {
        state.recState := newState
        ApplyRecAppearance(cfg, state)
    }
}

ApplyRecAppearance(cfg, state) {
    if (!IsObject(state.RecGui))
        return false

    pos := ComputeHudLayout(state, state.savedX, state.savedY)
    if (state.recState == 1) {
        bg := state.colors.recActive, brd := state.colors.recBorderActive, ic := cfg.MonoIcon ? state.colors.recIconActive : "FFFFFF"
        glyph := Chr(0xE7C8), lbl := "REC"
    } else if (state.recState == 2) {
        bg := state.colors.recPaused, brd := state.colors.recBorderPaused, ic := cfg.MonoIcon ? state.colors.recIconPaused : "FFFFFF"
        glyph := Chr(0xE769), lbl := "PAUSED"
    } else {
        bg := state.colors.recOff, brd := state.colors.recBorderOff, ic := cfg.MonoIcon ? state.colors.recIconOff : "D1D5DB"
        glyph := Chr(0xE71A), lbl := "NOT REC"
    }
    contentArgb := Gdip.HexToArgb(ic)

    if (cfg.ShowText) {
        rIconW := Round(UIConstants.REC_ICON_W * cfg.IndicatorScale)
        rIconX := Round(UIConstants.REC_ICON_X * cfg.IndicatorScale)
        rTextX := rIconX + rIconW + Round(UIConstants.LABEL_GAP_X * cfg.IndicatorScale)
        rTextW := Max(UIConstants.MIN_TEXT_WIDTH, state.recW - rTextX - Round(UIConstants.LABEL_GAP_X * cfg.IndicatorScale))
        iconCfg := {text: glyph, font: state.IconFont, size: state.subIconSize, color: contentArgb, x: rIconX, w: rIconW}
        labelCfg := {text: lbl, size: state.subTextSize, bold: true, color: contentArgb, x: rTextX, w: rTextW, align: 0}
    } else {
        iconCfg := {text: glyph, font: state.IconFont, size: state.subIconSize, color: contentArgb, x: 0, w: pos.recW}
        labelCfg := ""
    }

    return Gdip.RenderPill(state.RecGui.Hwnd, pos.recX, pos.recY, pos.recW, pos.recH, Gdip.HexToArgb(bg), Gdip.BgrToArgb(brd), state.baseAlpha, GetCornerRadius(cfg, pos.recH), iconCfg, labelCfg)
}

SyncUIState(cfg, state, obsIsMuted) {
    if (state.isMuted != obsIsMuted) {
        state.isMuted := obsIsMuted
        cfg.IsMuted := obsIsMuted
        cfg.WriteBool("Settings", "IsMuted", state.isMuted)
        PlayMuteAnimation(cfg, state)
    }
}

; --- HUD APPEARANCE & CONFIG HELPERS ---
SetScale(cfg, val, *) {
    cfg.Write("Settings", "IndicatorScale", val)
    Reload()
}

ResetAppearance(cfg, *) {
    cfg.ResetAppearance()
    Reload()
}

ResetSettings(cfg, *) {
    cfg.DeleteFile()
    Reload()
}

ResetTrayPosition(cfg, *) {
    cfg.ResetPosition()
    Reload()
}

; --- HUD CREATION, LAYOUT & STYLING ---
InitHUD(cfg, state, showWindows := true) {
    Gdip.Startup()
    state.ComputeDimensions(cfg)

    ; Create 5 GDI+ WS_EX_LAYERED (+E0x80000) HUD windows
    state.MicGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000 -DPIScale")
    state.RecGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000 -DPIScale")
    state.ChatGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000 -DPIScale")
    state.StudioGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000 -DPIScale")
    state.SceneGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000 -DPIScale")

    ApplyMicAppearance(cfg, state)
    ApplyRecAppearance(cfg, state)
    ApplyChatAppearance(cfg, state)
    ApplyStudioAppearance(cfg, state)
    ApplySceneAppearance(cfg, state)

    if (showWindows) {
        UpdateHudVisibility(cfg, state)
        if (cfg.ShowIndicator && state.isMuted)
            SetTimer state.breathTimerFn, (cfg.AggressivePulse ? UIConstants.PULSE_INTERVAL_AGGRESSIVE : UIConstants.PULSE_INTERVAL_NORMAL)
    }

    OnMessage(0x0003, WM_HUD_MOVE.Bind(state))
    OnMessage(0x0201, WM_LBUTTONDOWN.Bind(cfg, state))
    OnMessage(0x02E0, WM_DPICHANGED.Bind(state))
}

ComputeHudLayout(state, anchorX, anchorY) {
    recY := anchorY - state.recHeight - state.hudGap
    row3Y := recY - state.row3Height - state.hudGap
    return {
        micX: anchorX,
        micY: anchorY,
        micW: state.baseWidth,
        micH: state.baseHeight,
        recX: anchorX,
        recY: recY,
        recW: state.recW,
        recH: state.recHeight,
        chatX: anchorX + state.recW + state.hudGap,
        chatY: recY,
        chatW: state.chatW,
        chatH: state.recHeight,
        studioX: anchorX,
        studioY: row3Y,
        studioW: state.studioW,
        studioH: state.row3Height,
        sceneX: anchorX + state.studioW + state.hudGap,
        sceneY: row3Y,
        sceneW: state.sceneW,
        sceneH: state.row3Height
    }
}

UpdateHudLayout(state, anchorX := "", anchorY := "", skipHwnd := 0) {
    if (anchorX = "" || anchorY = "") {
        if (IsObject(state.MicGui) && DllCall("IsWindowVisible", "Ptr", state.MicGui.Hwnd))
            try WinGetPos(&anchorX, &anchorY,,, state.MicGui.Hwnd)
        if (anchorX = "" || anchorY = "")
            anchorX := state.savedX, anchorY := state.savedY
    }
    state.savedX := anchorX, state.savedY := anchorY
    pos := ComputeHudLayout(state, anchorX, anchorY)
    if (IsObject(state.MicGui) && state.MicGui.Hwnd != skipHwnd)
        state.MicGui.Move(pos.micX, pos.micY, pos.micW, pos.micH)
    if (IsObject(state.RecGui) && state.RecGui.Hwnd != skipHwnd)
        state.RecGui.Move(pos.recX, pos.recY, pos.recW, pos.recH)
    if (IsObject(state.ChatGui) && state.ChatGui.Hwnd != skipHwnd)
        state.ChatGui.Move(pos.chatX, pos.chatY, pos.chatW, pos.chatH)
    if (IsObject(state.StudioGui) && state.StudioGui.Hwnd != skipHwnd)
        state.StudioGui.Move(pos.studioX, pos.studioY, pos.studioW, pos.studioH)
    if (IsObject(state.SceneGui) && state.SceneGui.Hwnd != skipHwnd)
        state.SceneGui.Move(pos.sceneX, pos.sceneY, pos.sceneW, pos.sceneH)
}

UpdateHudVisibility(cfg, state) {
    if (!cfg.ShowIndicator) {
        if IsObject(state.MicGui)
            state.MicGui.Hide()
        if IsObject(state.RecGui)
            state.RecGui.Hide()
        if IsObject(state.ChatGui)
            state.ChatGui.Hide()
        if IsObject(state.StudioGui)
            state.StudioGui.Hide()
        if IsObject(state.SceneGui)
            state.SceneGui.Hide()
        return
    }

    state.currentAlpha := state.baseAlpha
    pos := ComputeHudLayout(state, state.savedX, state.savedY)
    state.MicGui.Show(Format("NoActivate x{} y{} w{} h{}", pos.micX, pos.micY, pos.micW, pos.micH))
    ApplyMicAppearance(cfg, state)

    if (cfg.ShowExtraHuds && (cfg.EnableWS || cfg.EnableZoom)) {
        state.RecGui.Show(Format("NoActivate x{} y{} w{} h{}", pos.recX, pos.recY, pos.recW, pos.recH))
        ApplyRecAppearance(cfg, state)
        state.ChatGui.Show(Format("NoActivate x{} y{} w{} h{}", pos.chatX, pos.chatY, pos.chatW, pos.chatH))
        ApplyChatAppearance(cfg, state)
    } else {
        state.RecGui.Hide()
        state.ChatGui.Hide()
    }

    if (cfg.ShowExtraHuds && cfg.EnableWS) {
        state.StudioGui.Show(Format("NoActivate x{} y{} w{} h{}", pos.studioX, pos.studioY, pos.studioW, pos.studioH))
        ApplyStudioAppearance(cfg, state)
        state.SceneGui.Show(Format("NoActivate x{} y{} w{} h{}", pos.sceneX, pos.sceneY, pos.sceneW, pos.sceneH))
        ApplySceneAppearance(cfg, state)
    } else {
        state.StudioGui.Hide()
        state.SceneGui.Hide()
    }
}

; --- HUD ANIMATIONS ---
PlayMuteAnimation(cfg, state) {
    if (!IsObject(state.MicGui))
        return

    if (!cfg.ShowIndicator) {
        SetTimer state.breathTimerFn, 0
        state.currentAlpha := state.baseAlpha
        ApplyMicAppearance(cfg, state)
        return
    }

    SetTimer state.breathTimerFn, 0
    baseX := state.savedX
    baseY := state.savedY

    fadeStep := Round(state.baseAlpha / UIConstants.FADE_STEPS)
    widthIncrement := (cfg.ShowText ? UIConstants.POP_WIDTH_INC_TEXT : UIConstants.POP_WIDTH_INC_ICON) * cfg.IndicatorScale
    heightIncrement := UIConstants.POP_HEIGHT_INC * cfg.IndicatorScale
    prevMuted := !state.isMuted

    Loop UIConstants.FADE_STEPS {
        state.currentAlpha -= fadeStep
        if (state.currentAlpha < 0)
            state.currentAlpha := 0

        popWidth := Round(state.baseWidth + (A_Index * widthIncrement))
        popHeight := Round(state.baseHeight + (A_Index * heightIncrement))
        offsetX := Round((popWidth - state.baseWidth) / 2)
        offsetY := Round((popHeight - state.baseHeight) / 2)

        ApplyMicAppearance(cfg, state, baseX - offsetX, baseY - offsetY, popWidth, popHeight, state.currentAlpha, prevMuted)
        Sleep UIConstants.FADE_SLEEP_MS
    }

    Loop UIConstants.FADE_STEPS {
        state.currentAlpha += fadeStep
        if (state.currentAlpha > state.baseAlpha)
            state.currentAlpha := state.baseAlpha

        popWidth := Round((state.baseWidth + (UIConstants.FADE_STEPS * widthIncrement)) - (A_Index * widthIncrement))
        popHeight := Round((state.baseHeight + (UIConstants.FADE_STEPS * heightIncrement)) - (A_Index * heightIncrement))
        offsetX := Round((popWidth - state.baseWidth) / 2)
        offsetY := Round((popHeight - state.baseHeight) / 2)

        ApplyMicAppearance(cfg, state, baseX - offsetX, baseY - offsetY, popWidth, popHeight, state.currentAlpha, state.isMuted)
        Sleep UIConstants.FADE_SLEEP_MS
    }

    state.currentAlpha := state.baseAlpha
    ApplyMicAppearance(cfg, state, baseX, baseY, state.baseWidth, state.baseHeight, state.currentAlpha)

    if (state.isMuted) {
        state.breathDir := cfg.AggressivePulse ? -UIConstants.PULSE_STEP_AGGRESSIVE : -UIConstants.PULSE_STEP_NORMAL
        SetTimer state.breathTimerFn, (cfg.AggressivePulse ? UIConstants.PULSE_INTERVAL_AGGRESSIVE : UIConstants.PULSE_INTERVAL_NORMAL)
    }
}

BreathingAnimation(cfg, state) {
    if (!IsObject(state.MicGui) || state.isDraggingHud)
        return

    minRatio := cfg.AggressivePulse ? UIConstants.PULSE_MIN_RATIO_AGGRESSIVE : UIConstants.PULSE_MIN_RATIO_NORMAL
    lowerBound := Round(state.baseAlpha * minRatio)
    stepAmount := cfg.AggressivePulse ? UIConstants.PULSE_STEP_AGGRESSIVE : UIConstants.PULSE_STEP_NORMAL

    state.currentAlpha += state.breathDir
    if (state.currentAlpha <= lowerBound) {
        state.currentAlpha := lowerBound
        state.breathDir := stepAmount
    } else if (state.currentAlpha >= state.baseAlpha) {
        state.currentAlpha := state.baseAlpha
        state.breathDir := -stepAmount
    }
    if (!Gdip.SetLayeredAlpha(state.MicGui.Hwnd, state.currentAlpha))
        ApplyMicAppearance(cfg, state)
}

; --- HUD DRAG & DPI HANDLERS ---
AnchorFromHwnd(state, hwnd, X, Y) {
    if (IsObject(state.RecGui) && hwnd == state.RecGui.Hwnd) {
        Y := Y + state.recHeight + state.hudGap
    } else if (IsObject(state.ChatGui) && hwnd == state.ChatGui.Hwnd) {
        X := X - state.recW - state.hudGap
        Y := Y + state.recHeight + state.hudGap
    } else if (IsObject(state.StudioGui) && hwnd == state.StudioGui.Hwnd) {
        Y := Y + state.row3Height + state.hudGap + state.recHeight + state.hudGap
    } else if (IsObject(state.SceneGui) && hwnd == state.SceneGui.Hwnd) {
        X := X - state.studioW - state.hudGap
        Y := Y + state.row3Height + state.hudGap + state.recHeight + state.hudGap
    }
    return {x: X, y: Y}
}

DragSyncTick(state) {
    if (!state.isDraggingHud || !state.activeDragHwnd)
        return
    try {
        WinGetPos(&curX, &curY,,, "ahk_id " state.activeDragHwnd)
        anchor := AnchorFromHwnd(state, state.activeDragHwnd, curX, curY)
        UpdateHudLayout(state, anchor.x, anchor.y, state.activeDragHwnd)
    }
}

WM_HUD_MOVE(state, wParam, lParam, msg, hwnd) {
    if (state.isDraggingHud && hwnd == state.activeDragHwnd)
        DragSyncTick(state)
}

WM_LBUTTONDOWN(cfg, state, wParam, lParam, msg, hwnd) {
    isHudHwnd := (IsObject(state.MicGui) && hwnd == state.MicGui.Hwnd)
        || (IsObject(state.RecGui) && hwnd == state.RecGui.Hwnd)
        || (IsObject(state.ChatGui) && hwnd == state.ChatGui.Hwnd)
        || (IsObject(state.StudioGui) && hwnd == state.StudioGui.Hwnd)
        || (IsObject(state.SceneGui) && hwnd == state.SceneGui.Hwnd)
    if (!isHudHwnd)
        return

    state.activeDragHwnd := hwnd
    state.isDraggingHud := true
    SetTimer state.dragTimerFn, UIConstants.DRAG_SYNC_INTERVAL_MS
    PostMessage(0xA1, 2,,, "ahk_id " hwnd)
    KeyWait "LButton"
    state.isDraggingHud := false
    state.activeDragHwnd := 0
    SetTimer state.dragTimerFn, 0

    WinGetPos(&X, &Y,,, "ahk_id " hwnd)
    anchor := AnchorFromHwnd(state, hwnd, X, Y)

    cfg.savedX := anchor.x
    cfg.savedY := anchor.y
    cfg.Write("Position", "X", anchor.x)
    cfg.Write("Position", "Y", anchor.y)
    UpdateHudLayout(state, anchor.x, anchor.y)
}

WM_DPICHANGED(state, wParam, lParam, msg, hwnd) {
    if (!IsObject(state.MicGui) || hwnd != state.MicGui.Hwnd)
        return
    newLeft := NumGet(lParam, 0, "Int")
    newTop := NumGet(lParam, 4, "Int")
    newRight := NumGet(lParam, 8, "Int")
    newBottom := NumGet(lParam, 12, "Int")
    state.MicGui.Move(newLeft, newTop, newRight - newLeft, newBottom - newTop)
    UpdateHudLayout(state, newLeft, newTop)
}
