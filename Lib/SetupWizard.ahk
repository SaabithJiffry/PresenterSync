; ==============================================================================
; Module: SetupWizard.ahk
; Description: Guided Setup Wizards, LAN/WAN pairing dialogs & setup probes
; ==============================================================================
; --- SETUP & SETTINGS GUIS ---
BuildSettingsWindow(title, elementsArray, onSave := "", options := "") {
    opts := IsObject(options) ? options : {}
    doSuspend := opts.HasOwnProp("suspend") ? opts.suspend : true
    doShow := opts.HasOwnProp("show") ? opts.show : true
    doWaitClose := opts.HasOwnProp("waitClose") ? opts.waitClose : false

    if (doShow) {
        existing := Theme.FocusExistingWindow(title)
        if IsObject(existing)
            return existing
    }

    if (doSuspend)
        Theme.AcquireSuspend()

    dlg := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", title)
    dlg._closed := false
    dlg.MarginX := 20
    dlg.MarginY := 16
    Theme.ApplyToWindow(dlg)
    if (doShow)
        Theme.NamedWindows[title] := dlg

    ReleaseDialogState(*) {
        if (dlg._closed)
            return
        dlg._closed := true
        Theme.UnregisterWindow(dlg, title)
        if (doSuspend)
            Theme.ReleaseSuspend()
    }
    dlg._releaseState := ReleaseDialogState

    CloseHandler(*) {
        ReleaseDialogState()
        if (opts.HasOwnProp("onClose") && opts.onClose) {
            opts.onClose.Call(dlg)
        } else {
            dlg.Destroy()
        }
    }
    dlg.OnEvent("Close", CloseHandler)
    dlg.OnEvent("Escape", CloseHandler)

    ctrls := Map()
    trackedElements := []

    HandleSave(*) {
        for el in trackedElements {
            if (el.HasOwnProp("required") && el.required) {
                rawVal := String(ctrls[el.id].Value)
                isPw := el.HasOwnProp("opts") && InStr(el.opts, "Password")
                if (isPw ? (rawVal = "") : (Trim(rawVal) = "")) {
                    dlg.Opt("+OwnDialogs")
                    errTitle := el.HasOwnProp("errorTitle") ? el.errorTitle : "Error"
                    errMsg := el.HasOwnProp("errorMsg") ? el.errorMsg : "Shortcuts cannot be left blank."
                    MsgBox(errMsg, errTitle, "Icon!")
                    return false
                }
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
        role := el.HasOwnProp("role") ? el.role : ""

        if (t = "DropDownList") {
            ctrl := dlg.Add("DropDownList", cOpts, el.items)
        } else if (t = "Checkbox") {
            chkOpt := (val != "") ? (" Checked" val) : ""
            ctrl := dlg.Add("Checkbox", cOpts chkOpt, txt)
        } else if (t = "Shortcut") {
            totalW := RegExMatch(cOpts, "i)\bw(\d+)", &wm) ? Integer(wm[1]) : 300
            ctrlH := RegExMatch(cOpts, "i)\bh(\d+)", &hm) ? Integer(hm[1]) : 25
            btnW := el.HasOwnProp("btnW") ? Integer(el.btnW) : 122
            gapPx := 6
            edW := Max(80, totalW - btnW - gapPx)
            cleanOpts := Trim(RegExReplace(RegExReplace(cOpts, "i)\bw\d+", ""), "i)\bh\d+", ""))
            edOpts := (cleanOpts != "" ? cleanOpts " " : "") "w" edW " h" ctrlH
            ctrl := dlg.Add("Edit", edOpts, val)
            btnTxt := el.HasOwnProp("btnText") ? el.btnText : "Capture Keystroke"
            capBtn := dlg.Add("Button", "x+" gapPx " yp w" btnW " h" ctrlH, btnTxt)
            Theme.RegisterControl(dlg, capBtn, "Button", "tabButton")
            if (el.HasOwnProp("id") && el.id != "")
                ctrls[el.id "_btn"] := capBtn
            allowMods := el.HasOwnProp("allowModifiers") ? el.allowModifiers : true
            allowClr := el.HasOwnProp("allowClear") ? el.allowClear : true
            capTitle := el.HasOwnProp("captureTitle") ? el.captureTitle : ("Capture Keystroke - " title)
            _BindShortcutCaptureBtn(capBtn, ctrl, capTitle, allowMods, allowClr)
            t := "Edit"
        } else if (t = "Text" || t = "Button") {
            ctrl := dlg.Add(t, cOpts, txt)
        } else {
            ctrl := dlg.Add(t, cOpts, val)
        }

        Theme.RegisterControl(dlg, ctrl, t, role)

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
        saveBtnOpts := opts.HasOwnProp("saveBtnOpts") ? opts.saveBtnOpts : "w280 h32 Default y+15"
        dlg.SetFont("s10 w400 norm", Theme.UiFont)
        saveBtn := dlg.Add("Button", saveBtnOpts, opts.saveBtnText)
        Theme.RegisterControl(dlg, saveBtn, "Button")
        saveBtn.OnEvent("Click", HandleSave)
    }

    dlg._ctrls := ctrls
    dlg._triggerSave := HandleSave

    if (opts.HasOwnProp("onInit") && opts.onInit)
        opts.onInit.Call(ctrls, dlg)

    if (doShow) {
        dlgHwnd := dlg.Hwnd
        WindowFit.Show(dlg)
        if (doWaitClose)
            WinWaitClose("ahk_id " dlgHwnd)
    }
    return dlg
}

_BindShortcutCaptureBtn(capBtn, targetCtrl, dTitle, modsOk, clrOk) {
    OnClick(*) {
        OpenShortcutCaptureDialog(targetCtrl.Value, (newHk) => (targetCtrl.Value := newHk), dTitle, modsOk, clrOk)
    }
    capBtn.OnEvent("Click", OnClick)
}

FormatAhkHotkeyHuman(hk) {
    raw := Trim(String(hk))
    if (raw = "" || StrLower(raw) = "none")
        return "None"
    i := 1
    len := StrLen(raw)
    hasCtrl := false, hasAlt := false, hasShift := false, hasWin := false
    while (i <= len) {
        ch := SubStr(raw, i, 1)
        if (ch = "^")
            hasCtrl := true
        else if (ch = "!")
            hasAlt := true
        else if (ch = "+")
            hasShift := true
        else if (ch = "#")
            hasWin := true
        else if (ch = "*" || ch = "~" || ch = "$") {
        } else
            break
        i += 1
    }
    base := Trim(SubStr(raw, i))
    if (base = "")
        return raw
    baseDisp := (StrLen(base) == 1) ? StrUpper(base) : base
    parts := []
    if (hasCtrl)
        parts.Push("Ctrl")
    if (hasAlt)
        parts.Push("Alt")
    if (hasShift)
        parts.Push("Shift")
    if (hasWin)
        parts.Push("Win")
    parts.Push(baseDisp)
    out := ""
    for idx, p in parts
        out .= (idx > 1 ? " + " : "") p
    return out
}

OpenShortcutCaptureDialog(currentHotkey, onApply, dialogTitle := "Capture Keystroke", allowModifiers := true, allowClear := true) {
    existing := Theme.FocusExistingWindow(dialogTitle)
    if IsObject(existing)
        return existing

    Theme.AcquireSuspend()

    dlg := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", dialogTitle)
    dlg._closed := false
    dlg.MarginX := 20
    dlg.MarginY := 16
    Theme.ApplyToWindow(dlg)
    Theme.NamedWindows[dialogTitle] := dlg

    dlg.SetFont("s10 w600", Theme.UiFont)
    Theme.RegisterControl(dlg, dlg.Add("Text", "xm w340", allowModifiers ? "Press any shortcut key combination" : "Press any single key or clicker button"), "Text")
    dlg.SetFont("s9 w400", Theme.UiFont)
    Theme.RegisterControl(dlg, dlg.Add("Text", "xm w340 y+4", "Hold Ctrl/Alt/Shift/Win + press a key, or edit raw AHK syntax below. Press Esc to cancel."), "Text", "muted")

    dlg.SetFont("s12 w700", Theme.UiFont)
    lblHuman := dlg.Add("Text", "xm w340 y+12 Center", FormatAhkHotkeyHuman(currentHotkey))
    Theme.RegisterControl(dlg, lblHuman, "Text", "accent")

    dlg.SetFont("s10 w600", Theme.UiFont)
    editSyntax := dlg.Add("Edit", "xm w340 h28 y+6 Center", currentHotkey)
    Theme.RegisterControl(dlg, editSyntax, "Edit")

    dlg.SetFont("s9 w400", Theme.UiFont)
    statusTxt := dlg.Add("Text", "xm w340 y+6 Center", "Listening for keystroke...")
    Theme.RegisterControl(dlg, statusTxt, "Text", "muted")

    dlg.SetFont("s9 w600", Theme.UiFont)
    btnApply := dlg.Add("Button", "xm w106 h32 y+12 Default", "Apply")
    btnReCap := dlg.Add("Button", "x+6 yp w112 h32", "Re-Capture")
    btnClear := dlg.Add("Button", "x+6 yp w110 h32" (allowClear ? "" : " Disabled"), "Clear (None)")
    Theme.RegisterControl(dlg, btnApply, "Button", "accent")
    Theme.RegisterControl(dlg, btnReCap, "Button", "tabButton")
    Theme.RegisterControl(dlg, btnClear, "Button", "tabButton")

    ih := InputHook("L0 M I2")
    ih.KeyOpt("{All}", "N")
    ih.KeyOpt("{Escape}{LShift}{RShift}{LControl}{RControl}{LAlt}{RAlt}{LWin}{RWin}", "-N V")

    OnCapturedKey(ihHook, VK, SC) {
        if (dlg._closed)
            return
        keyName := GetKeyName(Format("vk{:X}sc{:X}", VK, SC))
        if (keyName = "" || keyName ~= "^(L|R)?(Shift|Control|Ctrl|Alt|Win)$")
            return
        mods := ""
        if (allowModifiers) {
            if (GetKeyState("Ctrl", "P"))
                mods .= "^"
            if (GetKeyState("Alt", "P"))
                mods .= "!"
            if (GetKeyState("Shift", "P"))
                mods .= "+"
            if (GetKeyState("LWin", "P") || GetKeyState("RWin", "P"))
                mods .= "#"
        }
        keyOut := (StrLen(keyName) == 1) ? StrLower(keyName) : keyName
        chord := mods keyOut
        editSyntax.Value := chord
        lblHuman.Value := FormatAhkHotkeyHuman(chord)
        statusTxt.Value := "Captured: " chord "  (" lblHuman.Value ")"
    }
    ih.OnKeyDown := OnCapturedKey

    StartCapture(*) {
        if (dlg._closed)
            return
        btnApply.Focus()
        try ih.Start()
        statusTxt.Value := "Listening for keystroke..."
    }

    StopCapture(*) {
        try ih.Stop()
        if (!dlg._closed && WinExist("ahk_id " dlg.Hwnd))
            statusTxt.Value := "Manual edit mode (type AHK syntax)"
    }

    editSyntax.OnEvent("Focus", StopCapture)
    editSyntax.OnEvent("LoseFocus", StartCapture)
    editSyntax.OnEvent("Change", (*) => (lblHuman.Value := FormatAhkHotkeyHuman(editSyntax.Value)))

    Cleanup(*) {
        if (dlg._closed)
            return
        dlg._closed := true
        try ih.Stop()
        Theme.UnregisterWindow(dlg, dialogTitle)
        Theme.ReleaseSuspend()
        dlg.Destroy()
    }

    ApplyShortcut(*) {
        static dummyHotIf := (*) => false
        static dummyHandler := (*) => 0
        val := Trim(editSyntax.Value)
        if (val != "" && StrLower(val) != "none") {
            try {
                HotIf dummyHotIf
                Hotkey(val, dummyHandler, "Off")
                HotIf
            } catch {
                HotIf
                dlg.Opt("+OwnDialogs")
                MsgBox("'" val "' is not a valid AutoHotkey keystroke.`nExamples: ^!m, !a, F12, PgDn", "Invalid Keystroke", "Icon!")
                return
            }
        } else if (!allowClear) {
            dlg.Opt("+OwnDialogs")
            MsgBox("This shortcut cannot be left blank.", "Shortcut Required", "Icon!")
            return
        } else {
            val := (val = "") ? "" : "None"
        }
        Cleanup()
        onApply.Call(val)
    }

    btnApply.OnEvent("Click", ApplyShortcut)
    btnReCap.OnEvent("Click", StartCapture)
    btnClear.OnEvent("Click", (*) => (Cleanup(), onApply.Call("None")))
    dlg.OnEvent("Close", Cleanup)
    dlg.OnEvent("Escape", Cleanup)

    WindowFit.Show(dlg, "AutoSize Center")
    StartCapture()
    return dlg
}

PromptForSetup(cfg, isInitialBoot := false) {
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
        if (ctrls.Has("obsHotkey_btn"))
            ctrls["obsHotkey_btn"].Enabled := obsEnabled
        ctrls["zoomLbl"].Enabled := zoomEnabled
        ctrls["zoomHotkey"].Enabled := zoomEnabled
        if (ctrls.Has("zoomHotkey_btn"))
            ctrls["zoomHotkey_btn"].Enabled := zoomEnabled
    }

    SaveSetup(values, ctrls, dlg) {
        sel := (values["mode"] >= 1 && values["mode"] <= 3) ? values["mode"] : 1

        cfg.AudioRoutingMode := sel
        cfg.Write("Settings", "AudioRoutingMode", cfg.AudioRoutingMode)

        if (sel == 1 || sel == 3) {
            cfg.ObsMuteHotkey := (values["obsHotkey"] != "") ? values["obsHotkey"] : "None"
            cfg.Write("Settings", "ObsHotkey", cfg.ObsMuteHotkey)
        }
        if (sel == 2 || sel == 3) {
            cfg.ZoomMuteHotkey := (values["zoomHotkey"] != "") ? values["zoomHotkey"] : "!a"
            cfg.Write("Settings", "ZoomMuteHotkey", cfg.ZoomMuteHotkey)
        }

        if dlg.HasOwnProp("_releaseState")
            dlg._releaseState.Call()
        dlg.Destroy()
        if (!isInitialBoot)
            Reload()
    }

    elements := [
        {type: "Text", opts: "w340", text: "Select your Audio Routing Profile:"},
        {type: "DropDownList", id: "mode", opts: "w340 Choose" initialMode, items: modes, onChange: UpdateFieldStates},
        {type: "Text", id: "obsLbl", opts: "w340 y+15", text: "OBS Mute Shortcut" (cfg.EnableWS ? " (Optional with WebSocket):" : ":")},
        {type: "Shortcut", id: "obsHotkey", opts: "xm w340 h25", value: obsVal, captureTitle: "Capture OBS Mute Shortcut"},
        {type: "Text", id: "zoomLbl", opts: "xm w340 y+10", text: "Zoom Mute Shortcut (Default Alt+A):"},
        {type: "Shortcut", id: "zoomHotkey", opts: "xm w340 h25", value: zoomVal, captureTitle: "Capture Zoom Mute Shortcut"}
    ]

    BuildSettingsWindow("PresenterSync Audio Setup", elements, SaveSetup, {
        suspend: true,
        waitClose: true,
        onClose: isInitialBoot ? ((*) => ExitApp()) : ((dlg) => dlg.Destroy()),
        onInit: UpdateFieldStates,
        saveBtnText: isInitialBoot ? "Save & Start" : "Save & Restart",
        saveBtnOpts: "xm w340 h32 Default y+15"
    })
}

PromptForPassword(promptText := "Enter your OBS WebSocket Password:") {
    savedPw := ""

    SavePw(values, ctrls, dlg) {
        savedPw := values["password"]
        if dlg.HasOwnProp("_releaseState")
            dlg._releaseState.Call()
        dlg.Destroy()
    }

    elements := [
        {type: "Text", opts: "w250", text: promptText},
        {type: "Edit", id: "password", opts: "w250 Password", required: true, errorTitle: "Setup", errorMsg: "Password cannot be empty."}
    ]

    BuildSettingsWindow("WebSocket Setup", elements, SavePw, {
        suspend: true,
        waitClose: true,
        onClose: (dlg) => dlg.Destroy(),
        saveBtnText: "Save & Connect",
        saveBtnOpts: "w250 h32 Default y+15"
    })
    return savedPw
}

IsVirtualOrVpnAdapterName(desc) {
    clean := Trim(String(desc))
    if (clean = "")
        return false
    return !!RegExMatch(clean, "i)(virtual|vmware|vbox|virtualbox|hyper-v|vethernet|wsl|wireguard|tailscale|zerotier|wintun|nordlynx|cisco|docker|pseudo|loopback|npcap|tap-|\btun\b|\bvpn\b)")
}

GetLocalNetworkEndpoints(includeAdapterNames := true, includeVirtual := "", bypassCache := false) {
    static cachedFullPhys := "", cachedFullPhysTick := 0
    static cachedFullAll := "", cachedFullAllTick := 0
    static cachedFast := "", cachedFastTick := 0
    now := A_TickCount

    allowVirtual := (includeVirtual != "")
        ? !!includeVirtual
        : (IsSet(AppConfig) && IsObject(AppConfig) && AppConfig.HasOwnProp("IncludeVirtualAdapters") ? !!AppConfig.IncludeVirtualAdapters : false)

    if (!bypassCache) {
        if (includeAdapterNames) {
            if (allowVirtual && IsObject(cachedFullAll) && (now - cachedFullAllTick) < 10000)
                return cachedFullAll
            if (!allowVirtual && IsObject(cachedFullPhys) && (now - cachedFullPhysTick) < 10000)
                return cachedFullPhys
        } else {
            if (IsObject(cachedFast) && (now - cachedFastTick) < 10000)
                return cachedFast
        }
    }

    res := {ips: [], details: []}
    physIps := [], physDetails := []
    virtIps := [], virtDetails := []
    seen := Map()

    AppendSysLanIps(targetRes, seenMap) {
        try {
            for idx, ipVal in SysGetIPAddresses() {
                ipStr := Trim(String(ipVal))
                if (IsUsableLanIPv4(ipStr) && !seenMap.Has(ipStr)) {
                    seenMap[ipStr] := true
                    targetRes.ips.Push(ipStr)
                    targetRes.details.Push({name: "Adapter " idx, ip: ipStr, isVirtual: false})
                }
            }
        }
    }

    if (!includeAdapterNames) {
        AppendSysLanIps(res, seen)
        cachedFast := res
        cachedFastTick := now
        return res
    }

    try {
        wmi := ComObjGet("winmgmts:")
        adapters := wmi.ExecQuery("SELECT Description, IPAddress FROM Win32_NetworkAdapterConfiguration WHERE IPEnabled = True")
        for adapter in adapters {
            if !IsObject(adapter.IPAddress)
                continue
            desc := String(adapter.Description)
            isVirtual := IsVirtualOrVpnAdapterName(desc)
            for ip in adapter.IPAddress {
                ipStr := Trim(String(ip))
                if (IsUsableLanIPv4(ipStr) && !seen.Has(ipStr)) {
                    seen[ipStr] := true
                    item := {name: desc, ip: ipStr, isVirtual: isVirtual}
                    if (!isVirtual) {
                        physIps.Push(ipStr)
                        physDetails.Push(item)
                    } else {
                        virtIps.Push(ipStr)
                        virtDetails.Push(item)
                    }
                }
            }
        }
    }
    for idx, ipStr in physIps {
        res.ips.Push(ipStr)
        res.details.Push(physDetails[idx])
    }
    if (allowVirtual || res.ips.Length == 0) {
        for idx, ipStr in virtIps {
            res.ips.Push(ipStr)
            res.details.Push(virtDetails[idx])
        }
    }
    if (res.ips.Length == 0)
        AppendSysLanIps(res, seen)
    if (allowVirtual) {
        cachedFullAll := res
        cachedFullAllTick := now
    } else {
        cachedFullPhys := res
        cachedFullPhysTick := now
    }
    return res
}

ParseCandidateEndpoints(rawStr, defaultPort := "4455") {
    defPort := (IsInteger(defaultPort) && Integer(defaultPort) >= 1 && Integer(defaultPort) <= 65535) ? String(Integer(defaultPort)) : "4455"
    endpoints := []
    seen := Map()
    for item in StrSplit(rawStr, [",", ";"]) {
        clean := Trim(item)
        if (clean = "")
            continue
        scheme := "ws"
        hasExplicitScheme := false
        if RegExMatch(clean, "i)^(wss|ws|https|http)://(.*)$", &sm) {
            rawScheme := StrLower(sm[1])
            scheme := (rawScheme = "wss" || rawScheme = "https") ? "wss" : "ws"
            clean := sm[2]
            hasExplicitScheme := true
        }
        clean := RTrim(clean, " ")
        if (clean = "")
            continue
        path := "/"
        if RegExMatch(clean, "^([^/]+)(/.*)$", &pm) {
            clean := pm[1]
            path := pm[2]
        } else {
            clean := RTrim(clean, "/")
        }
        host := clean
        port := (hasExplicitScheme && scheme = "wss") ? "443" : defPort
        if RegExMatch(clean, "^([^:]+):(.*)$", &m) {
            host := Trim(m[1])
            rawP := Trim(m[2])
            if (IsInteger(rawP) && Integer(rawP) >= 1 && Integer(rawP) <= 65535)
                port := String(Integer(rawP))
        }
        if (host = "")
            continue
        rawKey := (scheme = "wss" ? ("wss://" host ":" port (path != "/" ? path : "")) : (host ":" port (path != "/" ? path : "")))
        urlStr := scheme "://" host ":" port path
        if (!seen.Has(urlStr)) {
            seen[urlStr] := true
            endpoints.Push({host: host, port: port, scheme: scheme, path: path, url: urlStr, raw: rawKey})
        }
    }
    if (endpoints.Length == 0) {
        urlStr := "ws://127.0.0.1:" defPort "/"
        endpoints.Push({host: "127.0.0.1", port: defPort, scheme: "ws", path: "/", url: urlStr, raw: "127.0.0.1:" defPort})
    }
    return endpoints
}

SetRemoteNetworkMode(cfg, state, mode, *) {
    norm := (StrLower(Trim(mode)) = "internet") ? "Internet" : "LAN"
    cfg.RemoteNetworkMode := norm
    cfg.Write("Settings", "RemoteNetworkMode", norm)
    if (norm = "Internet" && cfg.InternetPairingCode = "") {
        cfg.InternetPairingCode := GenerateInternetPairingCode()
        cfg.Write("Settings", "InternetPairingCode", cfg.InternetPairingCode)
    }
    if IsObject(state) {
        UpdateHostInternetRelay(cfg, state)
        if state.HasOwnProp("rebuildTrayFn") && state.rebuildTrayFn
            try state.rebuildTrayFn.Call()
        if state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn
            try state.refreshHelpFn.Call()
    }
    TrayTip("Remote Network Mode: " (norm = "Internet" ? "Different Networks (Internet)" : "Same Router (LAN)"), "PresenterSync", 1)
}

PromptCloseRemoteCompanion(cfg, state := "", *) {
    existing := Theme.FocusExistingWindow("Close Remote Companion")
    if IsObject(existing)
        return existing

    Theme.AcquireSuspend()

    dlg := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "Close Remote Companion")
    dlg._closed := false
    dlg.MarginX := 20
    dlg.MarginY := 18
    Theme.ApplyToWindow(dlg)
    Theme.NamedWindows["Close Remote Companion"] := dlg

    dlg.SetFont("s10 w600", Theme.UiFont)
    Theme.RegisterControl(dlg, dlg.Add("Text", "xm w340", "Turn Off Secondary Remote Companion?"), "Text")

    modeDesc := (cfg.RemoteNetworkMode = "Internet")
        ? "Different Networks (Internet Relay - " cfg.InternetPairingCode ")"
        : "Same Router (LAN via OBS WebSocket)"
    dlg.SetFont("s9 w400", Theme.UiFont)
    Theme.RegisterControl(dlg, dlg.Add("Text", "xm w340 y+6", "This will send an immediate close signal to shut down PresenterSync Remote on your secondary laptop / Smart Board.`n`nActive Channel: " modeDesc), "Text", "muted")

    dlg.SetFont("s10 w400", Theme.UiFont)
    btnConfirm := dlg.Add("Button", "xm w164 h34 y+16 Default", "Turn Off Secondary")
    btnCancel := dlg.Add("Button", "x+12 yp w164 h34", "Cancel")
    Theme.RegisterControl(dlg, btnConfirm, "Button", "accent")
    Theme.RegisterControl(dlg, btnCancel, "Button")

    Cleanup(*) {
        if (dlg._closed)
            return
        dlg._closed := true
        Theme.UnregisterWindow(dlg, "Close Remote Companion")
        Theme.ReleaseSuspend()
        dlg.Destroy()
    }

    ConfirmClose(*) {
        sent := SendCloseRemoteSignal(cfg, state)
        Cleanup()
        if (sent) {
            TrayTip("Close signal sent to PresenterSync Remote.", "Remote Companion", 1)
        } else {
            TrayTip("Close signal queued. Ensure OBS WebSocket or Internet Relay is connected.", "Remote Companion", 2)
        }
    }

    btnConfirm.OnEvent("Click", ConfirmClose)
    btnCancel.OnEvent("Click", Cleanup)
    dlg.OnEvent("Close", Cleanup)
    dlg.OnEvent("Escape", Cleanup)

    WindowFit.Show(dlg, "AutoSize Center")
    return dlg
}

ShowRemoteCompanionInfo(cfg, state := "", *) {
    existing := Theme.FocusExistingWindow("Remote Companion Connection Info")
    if IsObject(existing)
        return existing

    if (cfg.InternetPairingCode = "") {
        cfg.InternetPairingCode := GenerateInternetPairingCode()
        cfg.Write("Settings", "InternetPairingCode", cfg.InternetPairingCode)
    }

    endpoints := GetLocalNetworkEndpoints()
    candidates := [A_ComputerName ".local"]
    for ep in endpoints.ips {
        candidates.Push(ep)
    }
    universalString := ""
    local idx, cand
    for idx, cand in candidates {
        universalString .= (idx > 1 ? ", " : "") cand
    }

    dlg := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "Remote Companion Connection Info")
    dlg._closed := false
    dlg.MarginX := 20
    dlg.MarginY := 14
    Theme.ApplyToWindow(dlg)
    Theme.NamedWindows["Remote Companion Connection Info"] := dlg

    dlg.SetFont("s10 w600", Theme.UiFont)
    Theme.RegisterControl(dlg, dlg.Add("Text", "x20 y14 w700", "Host Details for PresenterSync Remote"), "Text")
    dlg.SetFont("s9 w400", Theme.UiFont)
    subLbl := dlg.Add("Text", "x20 y+2 w700", "Configure how your secondary device (Smart Board / Laptop / Android) connects:")
    Theme.RegisterControl(dlg, subLbl, "Text", "muted")
    subLbl.GetPos(, &subY, , &subH)
    colTop := subY + subH + 10

    ; --- LEFT COLUMN: NETWORK MODE, WAN CODE & LAN ENDPOINTS ---
    dlg.SetFont("s9 w600", Theme.UiFont)
    Theme.RegisterControl(dlg, dlg.Add("Text", "x20 y" colTop " w340", "Remote Network Mode:"), "Text")
    dlg.SetFont("s9 w400", Theme.UiFont)
    netChoice := (cfg.RemoteNetworkMode = "Internet") ? 2 : 1
    ddlNetMode := dlg.Add("DropDownList", "x20 y+4 w340 Choose" netChoice, [
        "1: Same Router / Local Wi-Fi or Ethernet (LAN - Default)",
        "2: Different Networks / Over the Internet (WAN Relay)"
    ])
    Theme.RegisterControl(dlg, ddlNetMode, "DropDownList")

    dlg.SetFont("s9 w600", Theme.UiFont)
    Theme.RegisterControl(dlg, dlg.Add("Text", "x20 y+10 w340", "Different Networks - Internet Pairing Code:"), "Text")
    dlg.SetFont("s10 w700", Theme.UiFont)
    editPair := dlg.Add("Edit", "x20 y+4 w180 h26 ReadOnly Center", cfg.InternetPairingCode)
    Theme.RegisterControl(dlg, editPair, "Edit", "accent")
    dlg.SetFont("s9 w400", Theme.UiFont)
    btnCopyPair := dlg.Add("Button", "x+6 yp w90 h26", "Copy Code")
    btnNewPair := dlg.Add("Button", "x+6 yp w58 h26", "New")
    Theme.RegisterControl(dlg, btnCopyPair, "Button", "accent")
    Theme.RegisterControl(dlg, btnNewPair, "Button")

    ResetCopyPairBtn(*) {
        if (!dlg._closed && WinExist("ahk_id " dlg.Hwnd))
            btnCopyPair.Text := "Copy Code"
    }
    btnCopyPair.OnEvent("Click", (*) => (
        A_Clipboard := cfg.InternetPairingCode,
        btnCopyPair.Text := "✓ Copied!",
        SetTimer(ResetCopyPairBtn, -1800),
        TrayTip("Internet Pairing Code copied to clipboard.", "Copied!", 1)
    ))
    btnNewPair.OnEvent("Click", (*) => (
        cfg.InternetPairingCode := GenerateInternetPairingCode(),
        cfg.Write("Settings", "InternetPairingCode", cfg.InternetPairingCode),
        editPair.Value := cfg.InternetPairingCode,
        (IsObject(state) ? UpdateHostInternetRelay(cfg, state) : 0),
        TrayTip("New Internet Pairing Code generated.", "Pairing Code Updated", 1)
    ))

    OnNetModeChanged(*) {
        newMode := (ddlNetMode.Value == 2) ? "Internet" : "LAN"
        SetRemoteNetworkMode(cfg, state, newMode)
    }
    ddlNetMode.OnEvent("Change", OnNetModeChanged)

    dlg.SetFont("s9 w600", Theme.UiFont)
    Theme.RegisterControl(dlg, dlg.Add("Text", "x20 y+10 w340", "Same Router (LAN) - Computer Name (mDNS):"), "Text")
    dlg.SetFont("s9 w400", Theme.UiFont)
    editHost := dlg.Add("Edit", "x20 y+4 w340 ReadOnly -Wrap", A_ComputerName ".local")
    Theme.RegisterControl(dlg, editHost, "Edit")

    ipListText := ""
    for ep in endpoints.details {
        ipListText .= (ep.isVirtual ? "[Virtual] " : "[LAN] ") ep.name ": " ep.ip "`n"
    }
    if (ipListText != "") {
        dlg.SetFont("s9 w600", Theme.UiFont)
        Theme.RegisterControl(dlg, dlg.Add("Text", "x20 y+8 w340", "Detected Local IP Addresses:"), "Text")
        dlg.SetFont("s9 w400", Theme.UiFont)
        editIps := dlg.Add("Edit", "x20 y+4 w340 r2 ReadOnly", RTrim(ipListText, "`n"))
        Theme.RegisterControl(dlg, editIps, "Edit")
    }

    dlg.SetFont("s9 w600", Theme.UiFont)
    Theme.RegisterControl(dlg, dlg.Add("Text", "x20 y+8 w340", "Universal Connection String (Multi-Candidate LAN):"), "Text")
    dlg.SetFont("s9 w400", Theme.UiFont)
    editUniv := dlg.Add("Edit", "x20 y+4 w340 ReadOnly -Wrap", universalString)
    Theme.RegisterControl(dlg, editUniv, "Edit")

    btnCopy := dlg.Add("Button", "x20 y+8 w340 h28", "Copy Universal String to Clipboard")
    Theme.RegisterControl(dlg, btnCopy, "Button", "accent")
    ResetCopyBtn(*) {
        if (!dlg._closed && WinExist("ahk_id " dlg.Hwnd))
            btnCopy.Text := "Copy Universal String to Clipboard"
    }
    btnCopy.OnEvent("Click", (*) => (
        A_Clipboard := universalString,
        btnCopy.Text := "✓ Copied to Clipboard!",
        SetTimer(ResetCopyBtn, -1800),
        TrayTip("Universal connection string copied to clipboard.", "Copied!", 1)
    ))
    btnCopy.GetPos(, &leftY, , &leftH)
    leftBottom := leftY + leftH

    activePort := (IsObject(state) && state.HasOwnProp("activeBridgePort") && state.activeBridgePort > 0) ? state.activeBridgePort : 4456
    primaryWebIp := (endpoints.ips.Length > 0) ? endpoints.ips[1] : (A_ComputerName ".local")
    webRemoteUrl := "http://" primaryWebIp ":" activePort "/"
    dlg.SetFont("s9 w600", Theme.UiFont)
    Theme.RegisterControl(dlg, dlg.Add("Text", "x20 y+8 w340", "Web Remote URL (Browser / iPad / Mac):"), "Text")
    dlg.SetFont("s9 w400", Theme.UiFont)
    editWebUrl := dlg.Add("Edit", "x20 y+4 w270 h26 ReadOnly -Wrap", webRemoteUrl)
    Theme.RegisterControl(dlg, editWebUrl, "Edit")
    btnCopyWeb := dlg.Add("Button", "x+6 yp w64 h26", "Copy")
    Theme.RegisterControl(dlg, btnCopyWeb, "Button")
    btnCopyWeb.OnEvent("Click", (*) => (
        A_Clipboard := webRemoteUrl,
        TrayTip("Web Remote URL copied to clipboard.", "Copied!", 1)
    ))
    editWebUrl.GetPos(, &webY, , &webH)
    leftBottom := webY + webH

    ; --- RIGHT COLUMN: SMART BOARD QR PAIRING & PAIRED DEVICES ---
    if (!cfg.HasOwnProp("SessionPairingCode") || cfg.SessionPairingCode = "")
        cfg.SessionPairingCode := GenerateSessionPairingCode()

    dlg.SetFont("s9 w600", Theme.UiFont)
    lblQrHdr := dlg.Add("Text", "x380 y" colTop " w340", "Smart Board Pairing (QR Code or Session Code):")
    Theme.RegisterControl(dlg, lblQrHdr, "Text")
    lblQrHdr.GetPos(, &qhY, , &qhH)
    qrTop := qhY + qhH + 4

    qrUri := BuildHostPairingUri(cfg, endpoints.ips, (IsObject(state) && state.HasOwnProp("activeBridgePort") && state.activeBridgePort > 0) ? state.activeBridgePort : 0)
    qrRes := QrCode.BuildHBitmap(qrUri, 114)
    hQrBmp := qrRes.hBitmap

    dlg.SetFont("s9 w700", Theme.UiFont)
    editSession := dlg.Add("Edit", "x380 y" qrTop " w106 h26 ReadOnly Center", cfg.SessionPairingCode)
    Theme.RegisterControl(dlg, editSession, "Edit", "accent")
    dlg.SetFont("s9 w400", Theme.UiFont)
    btnCopySession := dlg.Add("Button", "x+4 yp w54 h26", "Copy")
    btnNewSession := dlg.Add("Button", "x+4 yp w48 h26", "New")
    Theme.RegisterControl(dlg, btnCopySession, "Button")
    Theme.RegisterControl(dlg, btnNewSession, "Button")

    formatBridgeStatus := (*) => _FormatHostBridgeStatusLine(cfg)
    _BuildPairedSnapshot() {
        st := GetHostBridgeStatusSummary()
        sig := ""
        for idx, d in st.devices
            sig .= d.deviceId "|" d.deviceName "|" d.platform "|" d.ip "|" d.pairedAt "|" (d.connected ? "1" : "0") ";"
        return { summary: st, signature: sig }
    }

    dlg.SetFont("s8.5 w400", Theme.UiFont)
    lastBridgeTxt := formatBridgeStatus.Call()
    lblBridgeStatus := dlg.Add("Text", "x380 y+6 w216", lastBridgeTxt)
    Theme.RegisterControl(dlg, lblBridgeStatus, "Text", "muted")
    lblHintDev := dlg.Add("Text", "x380 y+4 w216", "Scan QR from Android Remote, or enter Session Code on LAN.")
    Theme.RegisterControl(dlg, lblHintDev, "Text", "muted")
    lblHintDev.GetPos(, &hintY, , &hintH)

    picQr := dlg.Add("Picture", "x606 y" qrTop " w114 h114 +0x800000", hQrBmp ? ("HBITMAP:" hQrBmp) : "")
    qrBottom := Max(qrTop + 114, hintY + hintH)

    dlg.SetFont("s9 w600", Theme.UiFont)
    Theme.RegisterControl(dlg, dlg.Add("Text", "x380 y" (qrBottom + 10) " w340", "Paired Devices (Online / Offline):"), "Text")
    dlg.SetFont("s8.5 w400", Theme.UiFont)
    lvDevs := dlg.Add("ListView", "x380 y+4 w340 r4 -Multi NoSortHdr Grid", ["Status", "Nickname", "Platform", "IP / Paired"])
    Theme.RegisterControl(dlg, lvDevs, "ListView")
    lvDevs.ModifyCol(1, 68)
    lvDevs.ModifyCol(2, 114)
    lvDevs.ModifyCol(3, 66)
    lvDevs.ModifyCol(4, 88)

    pairedIds := []
    lastSnapSig := "__init__"
    _PopulateDevicesList(snap) {
        selIdx := lvDevs.GetNext()
        selId := (selIdx >= 1 && selIdx <= pairedIds.Length) ? pairedIds[selIdx] : ""
        lvDevs.Delete()
        pairedIds := []
        for idx, d in snap.summary.devices {
            pairedIds.Push(d.deviceId)
            statusBadge := d.connected ? "● Online" : "○ Offline"
            ipPaired := d.ip (d.pairedAt != "" ? (" • " d.pairedAt) : "")
            rowOpts := (selId != "" && d.deviceId = selId) ? "Select Focus" : ""
            lvDevs.Add(rowOpts, statusBadge, d.deviceName, d.platform, ipPaired)
        }
        btnRenameDev.Enabled := (pairedIds.Length > 0)
        btnUnpairDev.Enabled := (pairedIds.Length > 0)
    }

    dlg.SetFont("s9 w400", Theme.UiFont)
    btnRenameDev := dlg.Add("Button", "x380 y+8 w108 h28", "Rename Device...")
    btnUnpairDev := dlg.Add("Button", "x+6 yp w106 h28", "Unpair Selected")
    btnRevokeAll := dlg.Add("Button", "x+6 yp w114 h28", "Rotate & Revoke All")
    Theme.RegisterControl(dlg, btnRenameDev, "Button")
    Theme.RegisterControl(dlg, btnUnpairDev, "Button")
    Theme.RegisterControl(dlg, btnRevokeAll, "Button")
    btnRevokeAll.GetPos(, &rightY, , &rightH)
    rightBottom := rightY + rightH

    initSnap := _BuildPairedSnapshot()
    lastSnapSig := initSnap.signature
    _PopulateDevicesList(initSnap)

    RefreshBridgeDevices(*) {
        if (dlg._closed || !WinExist("ahk_id " dlg.Hwnd))
            return
        curBridge := formatBridgeStatus.Call()
        if (curBridge != lastBridgeTxt) {
            lastBridgeTxt := curBridge
            try lblBridgeStatus.Value := curBridge
        }
        curSnap := _BuildPairedSnapshot()
        if (curSnap.signature != lastSnapSig) {
            lastSnapSig := curSnap.signature
            try _PopulateDevicesList(curSnap)
        }
    }
    SetTimer(RefreshBridgeDevices, 1000)

    RefreshQrBitmap() {
        newUri := BuildHostPairingUri(cfg, endpoints.ips, (IsObject(state) && state.HasOwnProp("activeBridgePort") && state.activeBridgePort > 0) ? state.activeBridgePort : 0)
        nextQr := QrCode.BuildHBitmap(newUri, 114)
        if (nextQr.hBitmap) {
            oldBmp := hQrBmp
            hQrBmp := nextQr.hBitmap
            try picQr.Value := "*w114 *h114 HBITMAP:" hQrBmp
            if (oldBmp)
                DllCall("DeleteObject", "Ptr", oldBmp)
        }
    }

    _SelectedDeviceEntry() {
        row := lvDevs.GetNext()
        if (row < 1 || row > pairedIds.Length)
            return ""
        targetId := pairedIds[row]
        for d in GetHostBridgeStatusSummary().devices {
            if (d.deviceId = targetId)
                return d
        }
        return ""
    }

    _OpenRenameDialog(*) {
        sel := _SelectedDeviceEntry()
        if (!IsObject(sel)) {
            TrayTip("Select a paired device in the list first.", "PresenterSync", 2)
            return
        }
        rnGui := Gui("+AlwaysOnTop +Owner" dlg.Hwnd " -MinimizeBox -MaximizeBox", "Rename Paired Device")
        rnGui.MarginX := 16
        rnGui.MarginY := 12
        Theme.ApplyToWindow(rnGui)
        Theme.RegisterControl(rnGui, rnGui.Add("Text", "xm w320", "Nickname for " sel.deviceName " (" sel.platform "):"), "Text")
        edNick := rnGui.Add("Edit", "xm w320 h26 y+6", sel.deviceName)
        Theme.RegisterControl(rnGui, edNick, "Edit")
        bOk := rnGui.Add("Button", "xm w156 h28 y+10 Default", "Save Nickname")
        bCan := rnGui.Add("Button", "x+8 yp w156 h28", "Cancel")
        Theme.RegisterControl(rnGui, bOk, "Button", "accent")
        Theme.RegisterControl(rnGui, bCan, "Button")
        _CloseRn(*) => (Theme.UnregisterWindow(rnGui), rnGui.Destroy())
        _SaveRn(*) {
            newNick := Trim(edNick.Value)
            if (newNick != "") {
                RenameHostPairedDevice(sel.deviceId, newNick)
                RefreshBridgeDevices()
            }
            _CloseRn()
        }
        bOk.OnEvent("Click", _SaveRn)
        bCan.OnEvent("Click", _CloseRn)
        rnGui.OnEvent("Close", _CloseRn)
        rnGui.OnEvent("Escape", _CloseRn)
        WindowFit.Show(rnGui, "AutoSize Center")
    }

    btnRenameDev.OnEvent("Click", _OpenRenameDialog)
    btnUnpairDev.OnEvent("Click", (*) => (
        (IsObject(sel := _SelectedDeviceEntry())
            ? (UnpairHostPairedDevice(sel.deviceId), RefreshBridgeDevices(), TrayTip("Unpaired device: " sel.deviceName, "PresenterSync", 1))
            : TrayTip("Select a paired device in the list first.", "PresenterSync", 2))
    ))
    btnRevokeAll.OnEvent("Click", (*) => (
        RotateHostSessionPairingCode(cfg, true),
        editSession.Value := cfg.SessionPairingCode,
        RefreshQrBitmap(),
        RefreshBridgeDevices(),
        TrayTip("Session Code rotated & all paired tokens revoked.", "PresenterSync", 1)
    ))

    btnCopySession.OnEvent("Click", (*) => (
        A_Clipboard := cfg.SessionPairingCode,
        TrayTip("Session Code copied to clipboard.", "PresenterSync", 1)
    ))
    btnNewSession.OnEvent("Click", (*) => (
        RotateHostSessionPairingCode(cfg, false),
        editSession.Value := cfg.SessionPairingCode,
        RefreshQrBitmap(),
        RefreshBridgeDevices(),
        TrayTip("New Session Code & QR generated.", "PresenterSync", 1)
    ))

    footerTop := Max(leftBottom, rightBottom) + 12
    statusLine := "OBS Port: 4455  |  Password: " (cfg.obsPassword != "" ? "Configured" : "None") "  |  Mic: " cfg.targetMicName
    Theme.RegisterControl(dlg, dlg.Add("Text", "x20 y" footerTop " w700 Center", statusLine), "Text", "muted")

    btnCloseRemote := dlg.Add("Button", "x20 y+8 w340 h30", "Close Remote Companion...")
    btnClose := dlg.Add("Button", "x380 yp w340 h30 Default", "Close")
    Theme.RegisterControl(dlg, btnCloseRemote, "Button")
    Theme.RegisterControl(dlg, btnClose, "Button")

    Cleanup(*) {
        if (dlg._closed)
            return
        dlg._closed := true
        SetTimer(RefreshBridgeDevices, 0)
        if (hQrBmp) {
            DllCall("DeleteObject", "Ptr", hQrBmp)
            hQrBmp := 0
        }
        Theme.UnregisterWindow(dlg, "Remote Companion Connection Info")
        dlg.Destroy()
    }

    btnCloseRemote.OnEvent("Click", (*) => PromptCloseRemoteCompanion(cfg, state))
    dlg.OnEvent("Close", Cleanup)
    dlg.OnEvent("Escape", Cleanup)
    btnClose.OnEvent("Click", Cleanup)

    WindowFit.Show(dlg, "AutoSize Center")
    return dlg
}

_GetSetupProbeOverride(overrides, key) {
    if (!IsObject(overrides))
        return { found: false, val: "" }
    if ((overrides is Map) && overrides.Has(key))
        return { found: true, val: overrides[key] }
    if (overrides.HasOwnProp(key))
        return { found: true, val: overrides.%key% }
    return { found: false, val: "" }
}

_DetectWindowsFirewallState() {
    try {
        fw := ComObject("HNetCfg.FwPolicy2")
        profMask := Integer(fw.CurrentProfileTypes)
        profile := (profMask & 4) ? "Public" : ((profMask & 2) ? "Private" : ((profMask & 1) ? "Domain" : "Unknown"))
        pubBlocked := ((profMask & 4) != 0) && !!fw.FirewallEnabled(4) && (Integer(fw.DefaultInboundAction(4)) == 0)
        return { profile: profile, blocked: pubBlocked }
    } catch {
        return { profile: "Unknown", blocked: false }
    }
}

RunWindowsSetupProbes(cfg, state := "", overrides := "") {
    obsListening := (IsObject(overrides) && overrides.HasOwnProp("obsPortListening"))
        ? !!overrides.obsPortListening
        : IsLocalTcpPortListening(4455)
    obsConnected := (IsObject(state) && state.HasOwnProp("obsConnected") && state.obsConnected)
    wsEnabled := (IsObject(cfg) && cfg.HasOwnProp("EnableWS") && cfg.EnableWS)
    s1Ok := (obsConnected || (wsEnabled && obsListening))
    s1Detail := obsConnected
        ? "Connected to OBS Studio (:4455)"
        : (obsListening ? (wsEnabled ? "OBS WS :4455 listening (connecting...)" : "OBS :4455 reachable — enable OBS WebSocket Sync in Tray") : "OBS Studio WebSocket :4455 not listening yet")

    rMode := (IsObject(cfg) && cfg.HasOwnProp("AudioRoutingMode")) ? Integer(cfg.AudioRoutingMode) : 0
    micNm := (IsObject(cfg) && cfg.HasOwnProp("targetMicName") && cfg.targetMicName != "") ? cfg.targetMicName : "Mic/Aux"
    cApp := (IsObject(cfg) && cfg.HasOwnProp("ConferencingApp") && cfg.ConferencingApp != "") ? cfg.ConferencingApp : "Zoom"
    meterOk := (IsObject(overrides) && overrides.HasOwnProp("audioMeterAvailable"))
        ? !!overrides.audioMeterAvailable
        : (IsSet(AudioMeter) ? (AudioMeter.GetPeak() >= 0.0) : false)
    s2Ok := (rMode >= 1 && rMode <= 3) && meterOk
    s2Detail := (rMode >= 1 && rMode <= 3)
        ? ("Mode " rMode " | Target: " micNm " | Conf: " cApp (meterOk ? " | CoreAudio Ready" : " | CoreAudio Idle"))
        : "Audio Routing Mode not configured yet (select Pro/Direct/Dual)"

    hudEnabled := (IsObject(cfg) && (!cfg.HasOwnProp("ShowIndicator") || cfg.ShowIndicator))
    hudGuiOk := (IsObject(state) && state.HasOwnProp("MicGui") && IsGuiValid(state.MicGui))
    s3Ok := hudEnabled && (hudGuiOk || !IsObject(state))
    s3Detail := hudEnabled
        ? (hudGuiOk ? "Floating HUD active on screen (" Round(cfg.IndicatorScale, 2) "x scale)" : "Floating HUD enabled")
        : "Floating HUD currently hidden (enable Show Mute Indicator)"

    epObj := (IsObject(overrides) && overrides.HasOwnProp("lanIps") && IsObject(overrides.lanIps))
        ? { ips: overrides.lanIps }
        : GetLocalNetworkEndpoints()
    bridgeSum := (IsObject(overrides) && overrides.HasOwnProp("bridgeSummary") && IsObject(overrides.bridgeSummary))
        ? overrides.bridgeSummary
        : GetHostBridgeStatusSummary()
    ipCount := IsObject(epObj.ips) ? epObj.ips.Length : 0
    s4Ok := (bridgeSum.running && ipCount > 0)
    s4Detail := bridgeSum.running
        ? ("Bridge TCP :" bridgeSum.tcpPort " & UDP :" bridgeSum.discoverPort " ready (" ipCount " LAN IP)")
        : "Host Bridge listener inactive"

    activeTcp := (IsObject(bridgeSum) && bridgeSum.HasOwnProp("tcpPort") && bridgeSum.tcpPort > 0) ? Integer(bridgeSum.tcpPort) : 4456
    ovFwProf := _GetSetupProbeOverride(overrides, "firewallProfile")
    ovFwBlk := _GetSetupProbeOverride(overrides, "firewallBlocked")
    fwDet := (!ovFwProf.found || !ovFwBlk.found) ? _DetectWindowsFirewallState() : { profile: "Private", blocked: false }
    fwProfile := ovFwProf.found ? String(ovFwProf.val) : fwDet.profile
    fwBlocked := ovFwBlk.found ? !!ovFwBlk.val : (ovFwProf.found ? (StrLower(fwProfile) = "public") : fwDet.blocked)
    s5Ok := !fwBlocked
    s5Detail := fwBlocked
        ? ("Public network profile active — inbound TCP :" activeTcp " & UDP :4457 may be blocked by Windows Firewall")
        : ("Network profile: " fwProfile " (TCP :" activeTcp " & UDP :4457 ready)")

    ovAdmin := _GetSetupProbeOverride(overrides, "isAdmin")
    isAdmin := ovAdmin.found ? !!ovAdmin.val : !!A_IsAdmin
    s6Ok := isAdmin
    s6Detail := isAdmin
        ? "Elevated (Admin) — Send/hotkeys can reach elevated OBS/Zoom/PPT windows"
        : "Non-Admin (UIPI active) — Run as Administrator if hotkeys fail on elevated OBS/Zoom/PPT"

    steps := [
        { id: 1, title: "1. OBS WebSocket v5 (:4455)", ok: s1Ok, detail: s1Detail },
        { id: 2, title: "2. Audio Routing & Mic Probe", ok: s2Ok, detail: s2Detail },
        { id: 3, title: "3. Floating Mic HUD Overlay", ok: s3Ok, detail: s3Detail },
        { id: 4, title: "4. Classroom UDP Discovery & QR", ok: s4Ok, detail: s4Detail },
        { id: 5, title: "5. Windows Firewall Profile (:" activeTcp "/4457)", ok: s5Ok, detail: s5Detail, profile: fwProfile, blocked: fwBlocked },
        { id: 6, title: "6. UIPI Elevation & Hotkey Access", ok: s6Ok, detail: s6Detail, isAdmin: isAdmin }
    ]
    passed := 0
    for stp in steps {
        if (stp.ok)
            passed += 1
    }
    return { passedCount: passed, totalCount: steps.Length, steps: steps, firewallProfile: fwProfile, firewallBlocked: fwBlocked, isAdmin: isAdmin }
}

ShowGuidedSetupWizard(cfg, state := "", *) {
    existing := Theme.FocusExistingWindow("PresenterSync - Guided Setup Wizard")
    if IsObject(existing)
        return existing
    Theme.AcquireSuspend()

    wGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "PresenterSync - Guided Setup Wizard")
    wGui._closed := false
    wGui.MarginX := 20
    wGui.MarginY := 16
    Theme.ApplyToWindow(wGui)
    Theme.NamedWindows["PresenterSync - Guided Setup Wizard"] := wGui

    wGui.SetFont("s11 w700", Theme.UiFont)
    Theme.RegisterControl(wGui, wGui.Add("Text", "xm w480", "PresenterSync 4-Step Live Setup Checklist"), "Text")
    wGui.SetFont("s9 w400", Theme.UiFont)
    Theme.RegisterControl(wGui, wGui.Add("Text", "xm y+4 w480", "Verify OBS WebSocket, CoreAudio routing, floating HUD visibility, and Classroom QR discovery."), "Text", "muted")

    rowCtrls := []
    Loop 6 {
        wGui.SetFont("s9 w700", Theme.UiFont)
        lblTitle := wGui.Add("Text", "xm y+12 w480", "Step " A_Index)
        Theme.RegisterControl(wGui, lblTitle, "Text")
        wGui.SetFont("s9 w400", Theme.UiFont)
        lblDet := wGui.Add("Text", "xm+14 y+2 w466", "Checking...")
        Theme.RegisterControl(wGui, lblDet, "Text", "muted")
        rowCtrls.Push({ title: lblTitle, detail: lblDet })
    }

    lblScore := wGui.Add("Text", "xm y+14 w480", "")
    Theme.RegisterControl(wGui, lblScore, "Text", "accent")

    RefreshProbes(*) {
        res := RunWindowsSetupProbes(cfg, state)
        for idx, s in res.steps {
            badge := s.ok ? "[PASS] " : "[CHECK] "
            rowCtrls[idx].title.Value := badge . s.title
            rowCtrls[idx].detail.Value := s.detail
        }
        lblScore.Value := "Readiness Score: " res.passedCount " / " res.totalCount " checks ready"
    }
    RefreshProbes()

    btnReprobe := wGui.Add("Button", "xm y+14 w112 h30", "Re-Probe All")
    btnFlash := wGui.Add("Button", "x+8 yp w112 h30", "Flash HUD Pill")
    btnQr := wGui.Add("Button", "x+8 yp w122 h30", "Show Pairing QR")
    btnCc := wGui.Add("Button", "x+8 yp w110 h30", "Control Center")
    for b in [btnReprobe, btnFlash, btnQr, btnCc]
        Theme.RegisterControl(wGui, b, "Button")

    btnFinish := wGui.Add("Button", "xm y+12 w480 h32 Default", "Save & Finish Setup")
    Theme.RegisterControl(wGui, btnFinish, "Button", "accent")

    FlashHudTest(*) {
        if (IsObject(cfg) && !cfg.ShowIndicator) {
            cfg.ShowIndicator := true
            cfg.WriteBool("Settings", "ShowIndicator", true)
        }
        if (IsObject(state) && IsGuiValid(state.MicGui)) {
            PlayMuteAnimation(cfg, state)
            TrayTip("Floating HUD indicator flashed! Drag it anywhere on screen.", "PresenterSync Setup", 1)
        } else {
            TrayTip("HUD overlay will appear when primary indicator is active.", "PresenterSync Setup", 1)
        }
        RefreshProbes()
    }

    CloseWizard(*) {
        if (wGui._closed)
            return
        wGui._closed := true
        Theme.UnregisterWindow(wGui, "PresenterSync - Guided Setup Wizard")
        Theme.ReleaseSuspend()
        wGui.Destroy()
    }

    btnReprobe.OnEvent("Click", (*) => RefreshProbes())
    btnFlash.OnEvent("Click", FlashHudTest)
    btnQr.OnEvent("Click", (*) => ShowRemoteCompanionInfo(cfg, state))
    btnCc.OnEvent("Click", (*) => ShowControlCenterWindow(cfg, state))
    btnFinish.OnEvent("Click", (*) => (
        (IsObject(cfg) ? (cfg.FirstRun := false, cfg.WriteBool("Settings", "FirstRun", false)) : 0),
        CloseWizard()
    ))
    wGui.OnEvent("Close", CloseWizard)
    wGui.OnEvent("Escape", CloseWizard)
    WindowFit.Show(wGui, "AutoSize")
    return wGui
}

_PreFlightOv(overrides, prop, defaultVal) {
    if (IsObject(overrides) && overrides.HasOwnProp(prop))
        return overrides.%prop%
    return defaultVal
}

RunPreFlightRehearsalChecks(cfg, state := "", overrides := "") {
    checks := []

    ; 1. OBS :4455, Transition & Audio Input
    obsOk := !!_PreFlightOv(overrides, "obsConnected", IsObject(state) && state.HasOwnProp("obsConnected") ? state.obsConnected : false)
    studioOn := !!_PreFlightOv(overrides, "studioModeActive", IsObject(state) && state.HasOwnProp("studioModeActive") ? state.studioModeActive : false)
    transHk := _PreFlightOv(overrides, "obsTransitionHotkey", IsObject(cfg) && cfg.HasOwnProp("ObsTransitionHotkey") ? cfg.ObsTransitionHotkey : "None")
    targetMic := _PreFlightOv(overrides, "targetMicName", IsObject(cfg) && cfg.HasOwnProp("targetMicName") ? cfg.targetMicName : "")
    inputsList := _PreFlightOv(overrides, "obsAudioInputs", IsObject(state) && state.HasOwnProp("obsAudioInputs") ? state.obsAudioInputs : (IsObject(state) && state.HasOwnProp("obsInputs") ? state.obsInputs : ""))
    micFound := true
    if (IsObject(inputsList) && inputsList.Length > 0 && targetMic != "") {
        micFound := false
        for _, inp in inputsList {
            if (StrLower(String(inp)) = StrLower(String(targetMic))) {
                micFound := true
                break
            }
        }
    }
    transReady := studioOn || (transHk != "" && transHk != "None")
    if (!obsOk)
        checks.Push({ name: "OBS :4455, Transition & Audio Input", status: "FAIL", detail: "OBS WebSocket (:4455) is not connected." })
    else if (!micFound)
        checks.Push({ name: "OBS :4455, Transition & Audio Input", status: "WARN", detail: "OBS connected, but target mic '" targetMic "' was not found in inputs." })
    else if (!transReady)
        checks.Push({ name: "OBS :4455, Transition & Audio Input", status: "WARN", detail: "OBS connected, but Studio Mode & ObsTransitionHotkey are not configured." })
    else
        checks.Push({ name: "OBS :4455, Transition & Audio Input", status: "PASS", detail: "OBS :4455 connected, transition & audio input ready." })

    ; 2. Physical Mic Signal (> 5%)
    defaultPeak := (IsObject(state) && state.HasOwnProp("voicePeak")) ? Number(state.voicePeak) : 0.0
    if (defaultPeak <= 0 && IsSet(AudioMeter) && AudioMeter.HasMethod("GetPeak"))
        try defaultPeak := Number(AudioMeter.GetPeak())
    micPeak := Number(_PreFlightOv(overrides, "micPeak", defaultPeak))
    if (micPeak >= 0.05)
        checks.Push({ name: "Physical Mic Signal (> 5%)", status: "PASS", detail: Format("Live mic peak {:.0f}% detected.", micPeak * 100) })
    else
        checks.Push({ name: "Physical Mic Signal (> 5%)", status: "WARN", detail: Format("Mic peak {:.0f}% (<= 5%). Speak into mic to verify.", micPeak * 100) })

    ; 3. Conferencing Window
    enZoom := !!_PreFlightOv(overrides, "enableZoom", IsObject(cfg) && cfg.HasOwnProp("EnableZoom") ? cfg.EnableZoom : false)
    defaultConf := (IsObject(state) && state.HasOwnProp("zoomConnected") && state.zoomConnected)
        || WinExist("ahk_exe Zoom.exe") || WinExist("ahk_exe ms-teams.exe") || WinExist("ahk_exe Teams.exe")
    confOpen := !!_PreFlightOv(overrides, "confOpen", defaultConf)
    if (!enZoom)
        checks.Push({ name: "Conferencing Window", status: "WARN", detail: "Conferencing monitor (EnableZoom) is currently OFF." })
    else if (confOpen)
        checks.Push({ name: "Conferencing Window", status: "PASS", detail: "Conferencing monitor active & window detected." })
    else
        checks.Push({ name: "Conferencing Window", status: "WARN", detail: "Conferencing monitor ON; waiting for Zoom/Teams/Meet window." })

    ; 4. Host Bridge & Paired Remotes
    defaultBrRun := IsSet(g_HostCompanionBridge) && IsObject(g_HostCompanionBridge) && g_HostCompanionBridge.HasOwnProp("running") ? !!g_HostCompanionBridge.running : false
    defaultBrPort := IsSet(g_HostCompanionBridge) && IsObject(g_HostCompanionBridge) && g_HostCompanionBridge.HasOwnProp("boundTcpPort") ? g_HostCompanionBridge.boundTcpPort : 4456
    defaultPaired := (IsSet(g_HostCompanionBridge) && IsObject(g_HostCompanionBridge) && g_HostCompanionBridge.HasMethod("GetConnectedClientCount")) ? g_HostCompanionBridge.GetConnectedClientCount() : 0
    brRun := !!_PreFlightOv(overrides, "bridgeRunning", defaultBrRun)
    brPort := Integer(_PreFlightOv(overrides, "bridgePort", defaultBrPort))
    pCount := Integer(_PreFlightOv(overrides, "pairedCount", defaultPaired))
    if (!brRun)
        checks.Push({ name: "Host Bridge & Paired Remotes", status: "FAIL", detail: "Host Companion Bridge is not running." })
    else if (pCount <= 0)
        checks.Push({ name: "Host Bridge & Paired Remotes", status: "WARN", detail: "Bridge active on :" brPort ", 0 connected remotes." })
    else
        checks.Push({ name: "Host Bridge & Paired Remotes", status: "PASS", detail: "Bridge active on :" brPort " (" pCount " connected remote(s))." })

    ; 5. Recording Disk Space
    freeMB := Number(_PreFlightOv(overrides, "freeMB", -1))
    if (freeMB < 0) {
        recDir := (IsObject(state) && state.HasOwnProp("recordDirectory") && Trim(String(state.recordDirectory)) != "") ? Trim(String(state.recordDirectory)) : A_ScriptDir
        try freeMB := Number(DriveGetSpaceFree(recDir))
        catch {
            try freeMB := Number(DriveGetSpaceFree(SubStr(recDir, 1, 3)))
            catch {
                try freeMB := Number(DriveGetSpaceFree(SubStr(A_ScriptDir, 1, 3)))
                catch
                    freeMB := 0
            }
        }
    }
    if (freeMB < 512)
        checks.Push({ name: "Recording Disk Space", status: "FAIL", detail: Format("Critical low disk space: {} MB free (< 512 MB).", Round(freeMB)) })
    else if (freeMB < 2048)
        checks.Push({ name: "Recording Disk Space", status: "WARN", detail: Format("Low disk space: {} MB free (< 2048 MB).", Round(freeMB)) })
    else
        checks.Push({ name: "Recording Disk Space", status: "PASS", detail: Format("Sufficient disk space: {} MB free.", Round(freeMB)) })

    passCount := 0, warnCount := 0, failCount := 0
    for _, chk in checks {
        if (chk.status = "PASS")
            passCount += 1
        else if (chk.status = "WARN")
            warnCount += 1
        else
            failCount += 1
    }
    return {
        ok: (failCount == 0),
        passCount: passCount,
        warnCount: warnCount,
        failCount: failCount,
        checks: checks
    }
}

ShowPreFlightRehearsalDialog(cfg, state := "", overrides := "") {
    res := RunPreFlightRehearsalChecks(cfg, state, overrides)
    if (IsSet(g_IsTestMode) && g_IsTestMode)
        return { shown: false, testMode: true, result: res }

    winTitle := "Go Live — 10-Second Rehearsal Pre-Flight"
    existing := Theme.FocusExistingWindow(winTitle)
    if (IsObject(existing))
        return { shown: true, testMode: false, result: res, gui: existing }

    Theme.AcquireSuspend()
    pfGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", winTitle)
    pfGui._closed := false
    pfGui.MarginX := 18
    pfGui.MarginY := 14
    Theme.ApplyToWindow(pfGui)
    Theme.NamedWindows[winTitle] := pfGui

    pfGui.SetFont("s10 w700", Theme.UiFont)
    Theme.RegisterControl(pfGui, pfGui.Add("Text", "xm w480", "10-Second Pre-Flight Rehearsal Check"), "Text")
    pfGui.SetFont("s9 w400", Theme.UiFont)
    lblSub := pfGui.Add("Text", "xm y+2 w480", "Verify OBS, mic signal, conferencing, paired remotes, and recording disk space before going live:")
    Theme.RegisterControl(pfGui, lblSub, "Text", "muted")

    rowCtrls := []
    Loop 5 {
        pfGui.SetFont("s9.5 w700", Theme.UiFont)
        lblT := pfGui.Add("Text", "xm y+10 w480", "")
        Theme.RegisterControl(pfGui, lblT, "Text")
        pfGui.SetFont("s8.5 w400", Theme.UiFont)
        lblD := pfGui.Add("Text", "xm+14 y+2 w466", "")
        Theme.RegisterControl(pfGui, lblD, "Text", "muted")
        rowCtrls.Push({ title: lblT, detail: lblD })
    }

    lblSummary := pfGui.Add("Text", "xm y+12 w480", "")
    Theme.RegisterControl(pfGui, lblSummary, "Text", "accent")

    RenderPreFlight(r) {
        for idx, chk in r.checks {
            rowCtrls[idx].title.Value := "[" chk.status "] " chk.name
            rowCtrls[idx].detail.Value := chk.detail
        }
        lblSummary.Value := Format("Result: {} PASS | {} WARN | {} FAIL  —  {}", r.passCount, r.warnCount, r.failCount, r.ok ? "READY TO GO LIVE" : "ACTION REQUIRED")
    }
    RenderPreFlight(res)

    btnRerun := pfGui.Add("Button", "xm y+14 w170 h32", "Re-Run 10s Check")
    btnClose := pfGui.Add("Button", "x+10 yp w120 h32 Default", "Close")
    Theme.RegisterControl(pfGui, btnRerun, "Button", "accent")
    Theme.RegisterControl(pfGui, btnClose, "Button")

    ClosePf(*) {
        if (pfGui._closed)
            return
        pfGui._closed := true
        Theme.UnregisterWindow(pfGui, winTitle)
        Theme.ReleaseSuspend()
        pfGui.Destroy()
    }
    btnRerun.OnEvent("Click", (*) => RenderPreFlight(RunPreFlightRehearsalChecks(cfg, state, overrides)))
    btnClose.OnEvent("Click", ClosePf)
    pfGui.OnEvent("Close", ClosePf)
    pfGui.OnEvent("Escape", ClosePf)

    WindowFit.Show(pfGui, "AutoSize Center")
    return { shown: true, testMode: false, result: res, gui: pfGui }
}

