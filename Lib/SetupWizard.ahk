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
        dlg.Show()
        if (doWaitClose)
            WinWaitClose("ahk_id " dlgHwnd)
    }
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
        ctrls["zoomLbl"].Enabled := zoomEnabled
        ctrls["zoomHotkey"].Enabled := zoomEnabled
    }

    SaveSetup(values, ctrls, dlg) {
        sel := values["mode"]
        if (!cfg.EnableWS && (sel == 1 || sel == 3) && values["obsHotkey"] = "") {
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
            cfg.ObsMuteHotkey := (values["obsHotkey"] != "") ? values["obsHotkey"] : "None"
            cfg.Write("Settings", "ObsHotkey", cfg.ObsMuteHotkey)
        }
        if (sel == 2 || sel == 3) {
            cfg.ZoomMuteHotkey := values["zoomHotkey"]
            cfg.Write("Settings", "ZoomMuteHotkey", cfg.ZoomMuteHotkey)
        }

        if dlg.HasOwnProp("_releaseState")
            dlg._releaseState.Call()
        dlg.Destroy()
        if (!isInitialBoot)
            Reload()
    }

    elements := [
        {type: "Text", opts: "w280", text: "Select your Audio Routing Profile:"},
        {type: "DropDownList", id: "mode", opts: "w280 Choose" initialMode, items: modes, onChange: UpdateFieldStates},
        {type: "Text", id: "obsLbl", opts: "w280 y+15", text: "OBS Mute Shortcut" (cfg.EnableWS ? " (Optional with WebSocket):" : ":")},
        {type: "Hotkey", id: "obsHotkey", opts: "w280", value: obsVal},
        {type: "Text", id: "zoomLbl", opts: "w280 y+10", text: "Zoom Mute Shortcut (Default Alt+A):"},
        {type: "Hotkey", id: "zoomHotkey", opts: "w280", value: zoomVal}
    ]

    BuildSettingsWindow("PresenterSync Audio Setup", elements, SaveSetup, {
        suspend: true,
        waitClose: true,
        onClose: isInitialBoot ? ((*) => ExitApp()) : ((dlg) => dlg.Destroy()),
        onInit: UpdateFieldStates,
        saveBtnText: isInitialBoot ? "Save & Start" : "Save & Restart",
        saveBtnOpts: "w280 h32 Default y+15"
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

GetLocalNetworkEndpoints() {
    res := {ips: [], details: []}
    seen := Map()
    try {
        wmi := ComObjGet("winmgmts:")
        adapters := wmi.ExecQuery("SELECT Description, IPAddress FROM Win32_NetworkAdapterConfiguration WHERE IPEnabled = True")
        for adapter in adapters {
            if !IsObject(adapter.IPAddress)
                continue
            desc := String(adapter.Description)
            isVirtual := RegExMatch(desc, "i)(virtual|vmware|vbox|hyper-v|pseudo|loopback|npcap|tap-)")
            for ip in adapter.IPAddress {
                ipStr := String(ip)
                if (InStr(ipStr, ".") && !seen.Has(ipStr) && ipStr != "127.0.0.1" && !RegExMatch(ipStr, "^169\.254\.")) {
                    seen[ipStr] := true
                    item := {name: desc, ip: ipStr, isVirtual: isVirtual}
                    if (!isVirtual) {
                        res.ips.InsertAt(1, ipStr)
                        res.details.InsertAt(1, item)
                    } else {
                        res.ips.Push(ipStr)
                        res.details.Push(item)
                    }
                }
            }
        }
    }
    if (res.ips.Length == 0) {
        Loop 4 {
            ipVal := A_IPAddress%A_Index%
            if (ipVal != "" && ipVal != "127.0.0.1" && ipVal != "0.0.0.0" && !seen.Has(ipVal)) {
                seen[ipVal] := true
                res.ips.Push(ipVal)
                res.details.Push({name: "Adapter " A_Index, ip: ipVal, isVirtual: false})
            }
        }
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

    dlg.Show("AutoSize Center")
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
        TrayTip("Generated new Internet Pairing Code: " cfg.InternetPairingCode, "Pairing Code Updated", 1)
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

    ; --- RIGHT COLUMN: SMART BOARD QR PAIRING & PAIRED DEVICES ---
    if (!cfg.HasOwnProp("SessionPairingCode") || cfg.SessionPairingCode = "")
        cfg.SessionPairingCode := GenerateSessionPairingCode()

    dlg.SetFont("s9 w600", Theme.UiFont)
    lblQrHdr := dlg.Add("Text", "x380 y" colTop " w340", "Smart Board Pairing (QR Code or Session Code):")
    Theme.RegisterControl(dlg, lblQrHdr, "Text")
    lblQrHdr.GetPos(, &qhY, , &qhH)
    qrTop := qhY + qhH + 4

    qrUri := BuildHostPairingUri(cfg, endpoints.ips)
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
        newUri := BuildHostPairingUri(cfg, endpoints.ips)
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
        rnGui.Show("AutoSize Center")
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
        TrayTip("Copied Session Code: " cfg.SessionPairingCode, "PresenterSync", 1)
    ))
    btnNewSession.OnEvent("Click", (*) => (
        RotateHostSessionPairingCode(cfg, false),
        editSession.Value := cfg.SessionPairingCode,
        RefreshQrBitmap(),
        RefreshBridgeDevices(),
        TrayTip("Generated new Session Code & QR: " cfg.SessionPairingCode, "PresenterSync", 1)
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

    dlg.Show("AutoSize Center")
    return dlg
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

    steps := [
        { id: 1, title: "1. OBS WebSocket v5 (:4455)", ok: s1Ok, detail: s1Detail },
        { id: 2, title: "2. Audio Routing & Mic Probe", ok: s2Ok, detail: s2Detail },
        { id: 3, title: "3. Floating Mic HUD Overlay", ok: s3Ok, detail: s3Detail },
        { id: 4, title: "4. Classroom UDP Discovery & QR", ok: s4Ok, detail: s4Detail }
    ]
    passed := 0
    for stp in steps {
        if (stp.ok)
            passed += 1
    }
    return { passedCount: passed, totalCount: steps.Length, steps: steps }
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
    Loop 4 {
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
    wGui.Show("AutoSize")
    return wGui
}

