; ==============================================================================
; Module: ControlCenter.ahk
; Description: Tabbed Control Center UI, Help/About/Pointer dialogs, Profiles & Diagnostics
; ==============================================================================
FormatHK(hk) {
    return FormatHkDisplayText(hk)
}

GetRoutingModeLabel(mode) {
    if (mode == 1)
        return "Mode 1: Pro OBS Setup (VB-Cable)"
    if (mode == 2)
        return "Mode 2: Standard Direct Mic (Zoom-Only)"
    if (mode == 3)
        return "Mode 3: Dual App Sync (OBS + Zoom)"
    return "Unconfigured"
}

GetRemoteSetupGuideText() {
    return "1. ENABLE OBS WEBSOCKET v5 ON HOST PC`r`n"
        . "- Open OBS Studio -> Tools -> WebSocket Server Settings.`r`n"
        . "- Check 'Enable WebSocket server' and keep Server Port at 4455.`r`n"
        . "- Check 'Enable Authentication', set or copy your password, and click Apply.`r`n"
        . "- If Windows Firewall prompts, allow Private networks (TCP port 4455 inbound).`r`n`r`n"
        . "2. CHOOSE SAME ROUTER (LAN) OR DIFFERENT NETWORKS (INTERNET)`r`n"
        . "- Right-click the PresenterSync tray icon (or any HUD pill) and open Settings -> Remote Companion Info....`r`n"
        . "- Same Router (LAN - Default): Click 'Copy Universal String to Clipboard' (includes .local mDNS + active Ethernet / Wi-Fi IPs, works across 2.4 GHz & 5 GHz SSIDs on the same router).`r`n"
        . "- Different Networks (Internet): Switch Network Mode to 'Different Networks (Internet)' and copy the Internet Pairing Code (e.g., PS-XXXX-XXXX) to bridge over HTTPS/WSS when devices are on separate routers or hotspots.`r`n`r`n"
        . "3. CONNECT PRESENTER SYNC REMOTE (SMART BOARD / 2ND PC)`r`n"
        . "- Copy PresenterSync_Remote.exe to the Smart Board (or run PresenterSync_Remote.ahk).`r`n"
        . "- Select matching Network Mode (Same Router LAN or Different Networks Internet), paste the Universal String or Internet Pairing Code, enter your OBS WebSocket Password, and match Exact Audio Source Name (default: Mic/Aux).`r`n"
        . "- Click 'Test Connection' to verify reachability, then click Connect & Start.`r`n`r`n"
        . "4. CLICKER CONTROL, REMOTE SHORTCUTS & SAFE MANUAL CLOSE`r`n"
        . "- Clicker Mute: Press your presenter mute key (default: b) to toggle OBS mic. Toggle Pointer Mute Control ON/OFF anytime on the Remote PC with Ctrl+F12 (when OFF, the HUD still displays live mic status without muting on click).`r`n"
        . "- Remote Exit & Safe Manual Close: Press Alt+Shift+F12 on the Remote PC to exit, or use 'Close Remote Companion...' in the Primary tray menu to send a confirmed shutdown signal.`r`n"
        . "- Troubleshooting: If Auth Failed (OBS Code 4009), check your password in Change OBS Connection...; if Mic Not Found, match exact Audio Source Name casing in OBS Audio Mixer."
}

BuildLiveStatusInfo(cfg, state := "") {
    ptrMode := cfg.EnablePPT ? "Full PPT + Mute" : (cfg.EnableMicOnly ? "Pointer Mute Only" : "OFF")
    syncMode := cfg.EnableWS ? "OBS WebSocket v5" : (cfg.EnableZoom ? "Zoom UIA Monitoring" : "Basic (1-Tier Mic Only)")
    connInfo := ""
    if IsObject(state) {
        if (cfg.EnableWS)
            connInfo := state.obsConnected ? " (Connected - Scene: " state.currentSceneName ")" : " (Waiting for OBS...)"
        else if (cfg.EnableZoom)
            connInfo := state.zoomConnected ? " (Active Meeting Detected)" : " (Waiting for Zoom Meeting...)"
    }
    hudStatus := (cfg.ShowIndicator ? "Visible" : "Hidden")
        . "  |  Extra HUDs: " (cfg.ShowExtraHuds ? "ON" : "OFF")
        . "  |  Labels: " (cfg.ShowText ? "ON" : "OFF")
        . "  |  Scale: " Round(cfg.IndicatorScale, 2) "x"
    themeStatus := cfg.ThemeMode " (Active: " (Theme.IsDarkMode() ? "Dark Mode" : "Light Mode") ")"
    if (ShouldEnableHostInternetRelay(cfg)) {
        relayStat := (IsObject(state) && state.HasOwnProp("relayConnected") && state.relayConnected) ? "Relay Connected" : "Relay Standby"
        modeTag := (cfg.RemoteNetworkMode = "Internet") ? "Internet Mode" : "Smart Mode 2 Relay Bridge"
        remoteHost := modeTag " (" cfg.InternetPairingCode " - " relayStat ")"
    } else {
        remoteHost := A_ComputerName ".local:4455 (LAN)  |  WS Auth: " (cfg.obsPassword != "" ? "Configured" : "None")
    }
    return {
        ptrMode: ptrMode,
        syncMode: syncMode,
        connInfo: connInfo,
        hudStatus: hudStatus,
        themeStatus: themeStatus,
        remoteHost: remoteHost
    }
}

BuildLiveStatusValues(cfg, state := "") {
    info := BuildLiveStatusInfo(cfg, state)
    return "v" UIConstants.APP_VERSION "`n"
        . GetRoutingModeLabel(cfg.AudioRoutingMode) "`n"
        . info.ptrMode "`n"
        . info.syncMode . info.connInfo "`n"
        . info.hudStatus "`n"
        . info.themeStatus "`n"
        . cfg.targetMicName "`n"
        . info.remoteHost
}

BuildLiveStatusSummary(cfg, state := "") {
    info := BuildLiveStatusInfo(cfg, state)
    return "PresenterSync Version:   v" UIConstants.APP_VERSION "`n"
        . "Audio Routing Profile:   " GetRoutingModeLabel(cfg.AudioRoutingMode) "`n"
        . "Active Pointer Mode:     " info.ptrMode "`n"
        . "Telemetry Engine:        " info.syncMode . info.connInfo "`n"
        . "HUD Overlay Status:      " info.hudStatus "`n"
        . "Application Theme:       " info.themeStatus "`n"
        . "Target OBS Mic Source:   " cfg.targetMicName "`n"
        . "Remote Companion Host:   " info.remoteHost
}

AddHelpGuideEdit(guiObj, x, y, w, h, contentText) {
    ed := guiObj.Add("Edit", Format("x{} y{} w{} h{} ReadOnly Multi -WantReturn -Tabstop VScroll", x, y, w, h), contentText)
    Theme.RegisterControl(guiObj, ed, "Edit")
    return ed
}

ShowHelpWindow(cfg, state := "", *) {
    existing := Theme.FocusExistingWindow("HelpWindow")
    if IsObject(existing) {
        if (IsObject(state) && state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn)
            try state.refreshHelpFn.Call()
        return existing
    }

    helpGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "PresenterSync v" UIConstants.APP_VERSION " - Interactive Help Center & HUD Guide")
    Theme.ApplyToWindow(helpGui)
    Theme.NamedWindows["HelpWindow"] := helpGui

    ; --- PERSISTENT TOP SEARCH BAR (visible above Tab2 across all tabs) ---
    helpGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(helpGui, helpGui.Add("Text", "x14 y15 w84 h22", "Search Help:"), "Text")
    helpGui.SetFont("s9 w400 norm", Theme.UiFont)
    edGlobalSearch := helpGui.Add("Edit", "x100 y12 w418 h26")
    Theme.RegisterControl(helpGui, edGlobalSearch, "Edit")
    DllCall("SendMessage", "Ptr", edGlobalSearch.Hwnd, "UInt", 0x1501, "Ptr", 1, "WStr", "Search HUD pills, Tray menus, OBS, Zoom, clicker, profiles...")

    btnClearSearch := helpGui.Add("Button", "x526 y12 w68 h26", "Clear")
    Theme.RegisterControl(helpGui, btnClearSearch, "Button")
    Theme.RegisterControl(helpGui, helpGui.Add("Text", "x602 y15 w224 h22 Right", "Type keyword -> Search tab"), "Text", "muted")

    tabNames := ["Visual HUD", "Tray Menus", "Features A-Z", "Search Help", "Shortcuts", "Remote Setup", "Live Status"]
    helpGui.SetFont("s9 w600 norm", Theme.UiFont)
    tabs := helpGui.Add("Tab2", "x14 y48 w812 h504 +0x0400 -0x0200", tabNames)
    tabs._tabNames := tabNames
    Theme.RegisterControl(helpGui, tabs, "Tab")

    ; =========================================================================
    ; TAB 1: VISUAL HUD ANATOMY (Interactive Clickable GDI+ Live HUD Diagram)
    ; =========================================================================
    tabs.UseTab(1)
    helpGui.SetFont("s10 w700 norm", Theme.UiFont)
    Theme.RegisterControl(helpGui, helpGui.Add("Text", "x30 y94 w780 h22", "Interactive Live HUD Anatomy - Click any pill or callout badge [1]-[8]:"), "Text", "tabText")
    helpGui.SetFont("s9 w400 norm", Theme.UiFont)

    hudAnatomy := GetPrimaryHudAnatomyItems()
    selectedHudIdx := 7 ; Start highlighting the core LIVE/MUTED Mic pill
    picHudDiagram := helpGui.Add("Picture", "x32 y118 w776 h240", "HBITMAP:" BuildPrimaryHudDiagramBitmap(cfg, selectedHudIdx, 776, 240))

    hudBtns := []
    for i, item in hudAnatomy {
        bx := 30 + (i - 1) * 98
        bCtrl := helpGui.Add("Button", Format("x{} y364 w92 h28", bx), item.tag)
        Theme.RegisterControl(helpGui, bCtrl, "Button", "tabButton")
        hudBtns.Push(bCtrl)
    }

    edHudDetail := AddHelpGuideEdit(helpGui, 30, 398, 780, 136, "")

    FormatHudAnatomyDetail(idx) {
        it := hudAnatomy[idx]
        return it.tag "  " it.pillTitle "`r`n"
            . "LAYER: " it.tier "`r`n"
            . "SUMMARY: " it.summary "`r`n`r`n"
            . "STATES:`r`n" it.states "`r`n`r`n"
            . "HOW TO USE:`r`n" it.actions "`r`n`r`n"
            . "WHERE TO CONFIGURE:`r`n" it.configWhere
    }

    SelectHudAnatomy(idx, redrawDiagram := true) {
        if (idx < 1 || idx > hudAnatomy.Length)
            return
        selectedHudIdx := idx
        edHudDetail.Value := FormatHudAnatomyDetail(idx)
        if (redrawDiagram && WinExist("ahk_id " helpGui.Hwnd))
            ApplyDiagramBitmap(picHudDiagram, BuildPrimaryHudDiagramBitmap(cfg, selectedHudIdx, 776, 240))
    }

    SelectHudAnatomy(selectedHudIdx, false)
    for idx, bCtrl in hudBtns {
        localIdx := idx
        bCtrl.OnEvent("Click", ((k, *) => SelectHudAnatomy(k, true)).Bind(localIdx))
    }

    OnPrimaryDiagramClick(ctrl, *) {
        pt := Buffer(8, 0), rc := Buffer(16, 0)
        DllCall("GetCursorPos", "Ptr", pt)
        DllCall("ScreenToClient", "Ptr", ctrl.Hwnd, "Ptr", pt)
        DllCall("GetClientRect", "Ptr", ctrl.Hwnd, "Ptr", rc)
        cw := Max(1, NumGet(rc, 8, "Int")), ch := Max(1, NumGet(rc, 12, "Int"))
        relX := NumGet(pt, 0, "Int") * (776.0 / cw)
        relY := NumGet(pt, 4, "Int") * (240.0 / ch)
        hitId := HitTestPrimaryHudDiagram(relX, relY)
        if (hitId >= 1 && hitId <= 8)
            SelectHudAnatomy(hitId, true)
    }
    picHudDiagram.OnEvent("Click", OnPrimaryDiagramClick)

    ; =========================================================================
    ; TAB 2: TRAY MENUS & SUBMENUS EXPLORER
    ; =========================================================================
    tabs.UseTab(2)
    helpGui.SetFont("s10 w700 norm", Theme.UiFont)
    Theme.RegisterControl(helpGui, helpGui.Add("Text", "x30 y94 w780 h22", "Complete System Tray & Submenu Reference (Primary & Remote):"), "Text", "tabText")
    helpGui.SetFont("s9 w400 norm", Theme.UiFont)

    trayGroups := ["All Tray Menus", "Top-Level Quick Toggles", "Indicator Appearance Submenu", "Settings Submenu", "Bottom Utilities & Exit", "Remote Companion Tray Menu"]
    ddlTrayCat := helpGui.Add("DropDownList", "x30 y122 w250 Choose1", trayGroups)
    Theme.RegisterControl(helpGui, ddlTrayCat, "DropDownList")

    edTrayFilter := helpGui.Add("Edit", "x290 y122 w308 h26")
    Theme.RegisterControl(helpGui, edTrayFilter, "Edit")
    DllCall("SendMessage", "Ptr", edTrayFilter.Hwnd, "UInt", 0x1501, "Ptr", 1, "WStr", "Filter tray items (e.g. dodge, snap, 4455, pulse)...")

    btnTrayReset := helpGui.Add("Button", "x606 y122 w76 h26", "Reset")
    Theme.RegisterControl(helpGui, btnTrayReset, "Button", "tabButton")

    lblTrayCount := helpGui.Add("Text", "x690 y125 w120 h22 Right", "")
    Theme.RegisterControl(helpGui, lblTrayCount, "Text", "tabMuted")

    lbTrayItems := helpGui.Add("ListBox", "x30 y156 w320 h378 +0x0100")
    Theme.RegisterControl(helpGui, lbTrayItems, "ListBox")
    edTrayDetail := AddHelpGuideEdit(helpGui, 362, 156, 448, 378, "")

    trayFiltered := []
    ShowTraySelection(*) {
        idx := lbTrayItems.Value
        if (idx >= 1 && idx <= trayFiltered.Length)
            edTrayDetail.Value := BuildHelpEntryDetailText(trayFiltered[idx])
        else
            edTrayDetail.Value := "No Tray menu items matched your filter. Click Reset or clear the filter box."
    }

    RefreshTrayExplorer(*) {
        allTray := SearchHelpEntries(edTrayFilter.Value, "Tray", false)
        selGrp := ddlTrayCat.Text
        trayFiltered := []
        for entry in allTray {
            if (selGrp = "All Tray Menus" || entry.group = selGrp)
                trayFiltered.Push(entry)
        }
        lblTrayCount.Value := trayFiltered.Length " items"
        PopulateHelpListBox(lbTrayItems, trayFiltered, false)
        ShowTraySelection()
    }
    ddlTrayCat.OnEvent("Change", RefreshTrayExplorer)
    edTrayFilter.OnEvent("Change", RefreshTrayExplorer)
    btnTrayReset.OnEvent("Click", (*) => (ddlTrayCat.Choose(1), edTrayFilter.Value := "", RefreshTrayExplorer()))
    lbTrayItems.OnEvent("Change", ShowTraySelection)
    RefreshTrayExplorer()

    ; =========================================================================
    ; TAB 3: FEATURES A-Z ENCYCLOPEDIA
    ; =========================================================================
    tabs.UseTab(3)
    helpGui.SetFont("s10 w700 norm", Theme.UiFont)
    Theme.RegisterControl(helpGui, helpGui.Add("Text", "x30 y94 w780 h22", "Feature Encyclopedia - Complete Plain-English Guide to Every Capability:"), "Text", "tabText")
    helpGui.SetFont("s9 w400 norm", Theme.UiFont)

    featGroups := ["All Features", "Getting Started & Overview", "Audio Routing & OBS Telemetry", "Conferencing (Zoom / Teams / Meet)", "PowerPoint & Hardware Clicker", "HUD Customization & Visuals", "Profiles, Updates & Startup"]
    ddlFeatCat := helpGui.Add("DropDownList", "x30 y122 w360 Choose1", featGroups)
    Theme.RegisterControl(helpGui, ddlFeatCat, "DropDownList")
    lblFeatCount := helpGui.Add("Text", "x402 y125 w408 h22 Right", "")
    Theme.RegisterControl(helpGui, lblFeatCount, "Text", "tabMuted")

    lbFeatItems := helpGui.Add("ListBox", "x30 y156 w300 h378 +0x0100")
    Theme.RegisterControl(helpGui, lbFeatItems, "ListBox")
    edFeatDetail := AddHelpGuideEdit(helpGui, 342, 156, 468, 378, "")

    featFiltered := []
    ShowFeatSelection(*) {
        idx := lbFeatItems.Value
        if (idx >= 1 && idx <= featFiltered.Length)
            edFeatDetail.Value := BuildHelpEntryDetailText(featFiltered[idx])
    }

    RefreshFeatureExplorer(*) {
        allFeat := SearchHelpEntries("", "Features", false)
        selGrp := ddlFeatCat.Text
        featFiltered := []
        for entry in allFeat {
            if (selGrp = "All Features" || entry.group = selGrp)
                featFiltered.Push(entry)
        }
        lblFeatCount.Value := featFiltered.Length " feature guides"
        PopulateHelpListBox(lbFeatItems, featFiltered, false)
        ShowFeatSelection()
    }
    ddlFeatCat.OnEvent("Change", RefreshFeatureExplorer)
    lbFeatItems.OnEvent("Change", ShowFeatSelection)
    RefreshFeatureExplorer()

    ; =========================================================================
    ; TAB 4: INSTANT SEARCH RESULTS
    ; =========================================================================
    tabs.UseTab(4)
    helpGui.SetFont("s10 w700 norm", Theme.UiFont)
    Theme.RegisterControl(helpGui, helpGui.Add("Text", "x30 y94 w530 h22", "Search Results - HUD Indicators, Tray Menus, Submenus, Features & Shortcuts:"), "Text", "tabText")
    helpGui.SetFont("s9 w400 norm", Theme.UiFont)
    lblSearchCount := helpGui.Add("Text", "x570 y94 w240 h22 Right", "")
    Theme.RegisterControl(helpGui, lblSearchCount, "Text", "tabMuted")

    ddlSearchScope := helpGui.Add("DropDownList", "x30 y122 w204 Choose1", ["All", "HUD", "Tray", "Features", "Shortcuts", "Remote"])
    Theme.RegisterControl(helpGui, ddlSearchScope, "DropDownList")

    quickTags := [
        { label: "Mute",       query: "mute" },
        { label: "OBS",        query: "obs" },
        { label: "Zoom/Teams", query: "zoom teams meet" },
        { label: "Clicker",    query: "clicker" },
        { label: "Snap/Dodge", query: "snap dodge" },
        { label: "Remote",     query: "remote" }
    ]
    for i, tagObj in quickTags {
        tx := 244 + (i - 1) * 95
        bt := helpGui.Add("Button", Format("x{} y121 w90 h26", tx), tagObj.label)
        Theme.RegisterControl(helpGui, bt, "Button", "tabButton")
        bt.OnEvent("Click", ((qStr, *) => (edGlobalSearch.Value := qStr, ddlSearchScope.Choose(1), tabs.Choose(4), RunGlobalSearch())).Bind(tagObj.query))
    }

    lbSearchResults := helpGui.Add("ListBox", "x30 y156 w320 h378 +0x0100")
    Theme.RegisterControl(helpGui, lbSearchResults, "ListBox")
    edSearchDetail := AddHelpGuideEdit(helpGui, 362, 156, 448, 338, "")

    btnSearchViewHud := helpGui.Add("Button", "x362 y500 w218 h34", "Jump to Visual HUD Diagram")
    btnSearchOpenCC := helpGui.Add("Button", "x592 y500 w218 h34", "Open Control Center...")
    Theme.RegisterControl(helpGui, btnSearchViewHud, "Button", "tabButton")
    Theme.RegisterControl(helpGui, btnSearchOpenCC, "Button", "tabButton")

    searchResults := []
    ShowSearchSelection(*) {
        idx := lbSearchResults.Value
        if (idx >= 1 && idx <= searchResults.Length) {
            cur := searchResults[idx]
            edSearchDetail.Value := BuildHelpEntryDetailText(cur)
        } else {
            edSearchDetail.Value := "No topics matched '" edGlobalSearch.Value "'.`r`n`r`nTry broader keywords such as: mute, obs, zoom, teams, meet, tray, stream, vcam, rec, chat, pulse, scale, theme, profile, clicker, or remote."
        }
    }

    RunGlobalSearch(*) {
        q := edGlobalSearch.Value
        scope := ddlSearchScope.Text
        searchResults := SearchHelpEntries(q, scope, false)
        lblSearchCount.Value := searchResults.Length (searchResults.Length = 1 ? " match" : " matches") (q != "" ? (" for '" q "'") : " (All)")
        PopulateHelpListBox(lbSearchResults, searchResults, true)
        ShowSearchSelection()
    }

    btnSearchViewHud.OnEvent("Click", (*) => (
        idx := lbSearchResults.Value,
        (idx >= 1 && idx <= searchResults.Length && searchResults[idx].hudId >= 1) ? SelectHudAnatomy(searchResults[idx].hudId, true) : 0,
        tabs.Choose(1)
    ))
    btnSearchOpenCC.OnEvent("Click", (*) => ShowControlCenterWindow(cfg, state))

    OnGlobalSearchEdited(*) {
        if (Trim(edGlobalSearch.Value) != "" && tabs.Value != 4)
            tabs.Choose(4)
        RunGlobalSearch()
    }
    edGlobalSearch.OnEvent("Change", OnGlobalSearchEdited)
    ddlSearchScope.OnEvent("Change", RunGlobalSearch)
    lbSearchResults.OnEvent("Change", ShowSearchSelection)
    btnClearSearch.OnEvent("Click", (*) => (edGlobalSearch.Value := "", ddlSearchScope.Choose(1), RunGlobalSearch()))
    RunGlobalSearch()

    ; =========================================================================
    ; TAB 5: SHORTCUTS (Dynamic Live Active Hotkeys & Collision Guard)
    ; =========================================================================
    tabs.UseTab(5)
    helpGui.SetFont("s10 w700 norm", Theme.UiFont)
    Theme.RegisterControl(helpGui, helpGui.Add("Text", "x30 y94 w780 h22", "Active Global App, Hardware Clicker & Fallback Shortcuts:"), "Text", "tabText")
    helpGui.SetFont("s9 w400 norm", Theme.UiFont)

    scCol1 := "Cycle Pointer Modes:`n"
        . "Toggle OBS WebSocket:`n"
        . "Toggle Conf Monitor:`n"
        . "Show / Hide HUD:`n"
        . "Suspend All Hotkeys:`n"
        . "Exit PresenterSync:`n"
        . "Clicker Mute Button:`n"
        . "Clicker OBS Transition:`n"
        . "OBS Mute / Rec / Pause:`n"
        . "OBS Transition Fallback:`n"
        . "Conf Mute / Rec / Pause:`n"
        . "Sector Z Subsystem:"
    normApp := NormalizeConferencingApp(cfg.ConferencingApp)
    activeConfKey := (normApp = "Teams") ? cfg.TeamsMuteHotkey : ((normApp = "Meet") ? cfg.MeetMuteHotkey : cfg.ZoomMuteHotkey)
    scCol2 := FormatHK(cfg.PptHotkey) "`n"
        . FormatHK(cfg.WsHotkey) "`n"
        . FormatHK(cfg.ZoomHotkey) "`n"
        . FormatHK(cfg.IndHotkey) "`n"
        . FormatHK(cfg.SuspendHotkey) "`n"
        . FormatHK(cfg.ExitHotkey) "`n"
        . FormatHK(cfg.HwMuteHotkey) (cfg.EnablePushToMute ? "  (Hold >= 350ms = Cough Mute)" : "  (Tap Toggle)") "`n"
        . FormatHK(cfg.HwTransitionHotkey) (cfg.EnablePointerTransition ? "  (Enabled)" : "  (Disabled)") "`n"
        . FormatHK(cfg.ObsMuteHotkey) "  /  " FormatHK(cfg.ObsRecHotkey) "  /  " FormatHK(cfg.ObsPauseHotkey) "`n"
        . FormatHK(cfg.ObsTransitionHotkey) "`n"
        . FormatHK(activeConfKey) "  /  " FormatHK(cfg.ZoomRecHotkey) "  /  " FormatHK(cfg.ZoomPauseHotkey) "  (" normApp ")`n"
        . "Locked [0 Credits]  (Diagnostic clearance required)"
    Theme.RegisterControl(helpGui, helpGui.Add("Text", "x30 y122 w200 h206", scCol1), "Text", "tabMuted")
    Theme.RegisterControl(helpGui, helpGui.Add("Text", "x238 y122 w572 h206", scCol2), "Text", "tabText")

    shortcutNotes := "HOW SHORTCUTS WORK`r`n"
        . "• Hardware Clicker Mute Button: Works in Full PPT + Mute and Pointer Mute Only modes, protected by a 150ms hardware debounce and automatic pause while any PresenterSync settings window is active.`r`n"
        . "• Mutual Exclusion Shield: Binding PgDn, Esc, Tab, or F5 as your Clicker Mute Button automatically excludes it from PowerPoint slide forwarding so one button press never changes a slide AND mutes at once.`r`n"
        . "• Fallback Shortcuts (OBS / Zoom / Teams / Meet): Fired automatically when OBS WebSocket Sync is disabled (Mode 1 / 3) or when syncing Conferencing mute in Mode 2 / Mode 3.`r`n"
        . "• Disable Any Key: Clear a shortcut box or enter 'None' to leave it unbound."
    AddHelpGuideEdit(helpGui, 30, 336, 780, 152, shortcutNotes)

    btnAppHk := helpGui.Add("Button", "x30 y498 w186 h34", "Edit App Shortcuts")
    btnObsHk := helpGui.Add("Button", "x228 y498 w186 h34", "Edit OBS Settings")
    btnZoomHk := helpGui.Add("Button", "x426 y498 w186 h34", "Edit Conf Shortcuts")
    btnTesterSc := helpGui.Add("Button", "x624 y498 w186 h34", "Launch Clicker Tester")
    Theme.RegisterControl(helpGui, btnAppHk, "Button", "tabButton")
    Theme.RegisterControl(helpGui, btnObsHk, "Button", "tabButton")
    Theme.RegisterControl(helpGui, btnZoomHk, "Button", "tabButton")
    Theme.RegisterControl(helpGui, btnTesterSc, "Button", "tabButton")
    btnAppHk.OnEvent("Click", (*) => ChangeAppHotkeysUI(cfg, state))
    btnObsHk.OnEvent("Click", (*) => ChangeObsSettingsUI(cfg, state))
    btnZoomHk.OnEvent("Click", (*) => ChangeZoomShortcutsUI(cfg, state))
    btnTesterSc.OnEvent("Click", (*) => ShowPointerTester())

    ; =========================================================================
    ; TAB 6: REMOTE SETUP (Smart Board & Companion Bridge Guide)
    ; =========================================================================
    tabs.UseTab(6)
    helpGui.SetFont("s10 w700 norm", Theme.UiFont)
    Theme.RegisterControl(helpGui, helpGui.Add("Text", "x30 y94 w780 h22", "Smart Board & Secondary PC Companion Setup (PresenterSync Remote):"), "Text", "tabText")
    helpGui.SetFont("s9 w400 norm", Theme.UiFont)
    AddHelpGuideEdit(helpGui, 30, 122, 780, 366, GetRemoteSetupGuideText())

    btnRemInfo := helpGui.Add("Button", "x30 y498 w252 h34", "Remote Connection Info...")
    btnRemTest := helpGui.Add("Button", "x294 y498 w252 h34", "Launch Clicker Tester")
    btnRemSearch := helpGui.Add("Button", "x558 y498 w252 h34", "Browse Remote Help Topics")
    Theme.RegisterControl(helpGui, btnRemInfo, "Button", "tabButton")
    Theme.RegisterControl(helpGui, btnRemTest, "Button", "tabButton")
    Theme.RegisterControl(helpGui, btnRemSearch, "Button", "tabButton")
    btnRemInfo.OnEvent("Click", (*) => ShowRemoteCompanionInfo(cfg, state))
    btnRemTest.OnEvent("Click", (*) => ShowPointerTester())
    btnRemSearch.OnEvent("Click", (*) => (edGlobalSearch.Value := "", ddlSearchScope.Choose(6), RunGlobalSearch(), tabs.Choose(4)))

    ; =========================================================================
    ; TAB 7: LIVE STATUS & INSTANT CONTROLS
    ; =========================================================================
    tabs.UseTab(7)
    helpGui.SetFont("s10 w700 norm", Theme.UiFont)
    Theme.RegisterControl(helpGui, helpGui.Add("Text", "x30 y94 w780 h22", "Live Configuration, Telemetry & Remote Host Diagnostics:"), "Text", "tabText")
    helpGui.SetFont("s9 w400 norm", Theme.UiFont)

    statusCol1 := "PresenterSync Version:`n"
        . "Audio Routing Profile:`n"
        . "Active Pointer Mode:`n"
        . "Telemetry Engine:`n"
        . "HUD Overlay Status:`n"
        . "Application Theme:`n"
        . "Target OBS Mic Source:`n"
        . "Remote Companion Host:"
    Theme.RegisterControl(helpGui, helpGui.Add("Text", "x30 y124 w195 h220", statusCol1), "Text", "tabMuted")
    statusValCtrl := helpGui.Add("Text", "x235 y124 w575 h220", BuildLiveStatusValues(cfg, state))
    Theme.RegisterControl(helpGui, statusValCtrl, "Text", "tabText")

    Theme.RegisterControl(helpGui, helpGui.Add("Text", "x30 y350 w780 h22", "Instant Live Toggles & Configuration Actions (No Restart Needed for Toggles):"), "Text", "tabMuted")

    btnTogExtra := helpGui.Add("Button", "x30 y382 w186 h34", "Toggle Extra HUDs")
    btnTogText := helpGui.Add("Button", "x228 y382 w186 h34", "Toggle HUD Labels")
    btnCycTheme := helpGui.Add("Button", "x426 y382 w186 h34", "Cycle Theme")
    btnResetPos := helpGui.Add("Button", "x624 y382 w186 h34", "Reset HUD Position")

    btnRefreshStatus := helpGui.Add("Button", "x30 y428 w186 h34", "Refresh Status")
    btnResetApp := helpGui.Add("Button", "x228 y428 w186 h34", "Reset Appearance")
    btnExportDiag := helpGui.Add("Button", "x426 y428 w186 h34", "Export Diagnostics...")
    btnOpenAbout := helpGui.Add("Button", "x624 y428 w186 h34", "About v" UIConstants.APP_VERSION)

    btnStatusWizard := helpGui.Add("Button", "x30 y474 w252 h34", "Run Audio Setup Wizard...")
    btnStatusMuteKey := helpGui.Add("Button", "x294 y474 w252 h34", "Change Mute Button...")
    btnStatusIntercepts := helpGui.Add("Button", "x558 y474 w252 h34", "Configure Intercepts...")

    for bLive in [btnTogExtra, btnTogText, btnCycTheme, btnResetPos, btnRefreshStatus, btnResetApp, btnExportDiag, btnOpenAbout, btnStatusWizard, btnStatusMuteKey, btnStatusIntercepts]
        Theme.RegisterControl(helpGui, bLive, "Button", "tabButton")

    RefreshHelpStatus(*) {
        if WinExist("ahk_id " helpGui.Hwnd) {
            statusValCtrl.Value := BuildLiveStatusValues(cfg, state)
            if (helpGui.HasOwnProp("_onThemeRefresh") && helpGui._onThemeRefresh)
                try helpGui._onThemeRefresh.Call()
        }
    }
    if IsObject(state)
        state.refreshHelpFn := RefreshHelpStatus

    SyncTrayAndHelp() {
        if (IsObject(state) && state.HasOwnProp("rebuildTrayFn") && state.rebuildTrayFn)
            try state.rebuildTrayFn.Call()
        RefreshHelpStatus()
    }

    OnHelpToggleExtra(*) {
        cfg.ShowExtraHuds := !cfg.ShowExtraHuds
        cfg.WriteBool("Settings", "ShowExtraHuds", cfg.ShowExtraHuds)
        if IsObject(state)
            RefreshHudAppearance(cfg, state)
        SyncTrayAndHelp()
    }

    OnHelpToggleText(*) {
        cfg.ShowText := !cfg.ShowText
        cfg.WriteBool("Settings", "ShowText", cfg.ShowText)
        if IsObject(state)
            RefreshHudAppearance(cfg, state)
        SyncTrayAndHelp()
    }

    OnHelpCycleTheme(*) {
        nextMode := (cfg.ThemeMode = "System") ? "Dark" : ((cfg.ThemeMode = "Dark") ? "Light" : "System")
        SetThemeMode(cfg, "", nextMode)
        SyncTrayAndHelp()
    }

    OnHelpResetPos(*) {
        ResetTrayPosition(cfg, state)
        SyncTrayAndHelp()
    }

    OnHelpResetAppearance(*) {
        ResetAppearance(cfg, state)
        SelectHudAnatomy(selectedHudIdx, true)
        SyncTrayAndHelp()
    }

    btnTogExtra.OnEvent("Click", OnHelpToggleExtra)
    btnTogText.OnEvent("Click", OnHelpToggleText)
    btnCycTheme.OnEvent("Click", OnHelpCycleTheme)
    btnResetPos.OnEvent("Click", OnHelpResetPos)
    btnRefreshStatus.OnEvent("Click", RefreshHelpStatus)
    btnResetApp.OnEvent("Click", OnHelpResetAppearance)
    btnExportDiag.OnEvent("Click", (*) => ExportSanitizedDiagnostics(cfg, state, "", true))
    btnOpenAbout.OnEvent("Click", (*) => ShowAboutWindow(cfg, state))
    btnStatusWizard.OnEvent("Click", (*) => PromptForSetup(cfg, false))
    btnStatusMuteKey.OnEvent("Click", (*) => ChangeHwMuteHotkeyUI(cfg, state))
    btnStatusIntercepts.OnEvent("Click", (*) => ConfigurePointerKeysUI(cfg, state))

    tabs.UseTab()

    ; Keep Visual HUD Diagram synchronized cleanly whenever Light/Dark theme refreshes
    helpGui._onThemeRefresh := (*) => (
        WinExist("ahk_id " helpGui.Hwnd) ? ApplyDiagramBitmap(picHudDiagram, BuildPrimaryHudDiagramBitmap(cfg, selectedHudIdx, 776, 240)) : 0
    )

    ; =========================================================================
    ; FOOTER BAR (Outside Tab2)
    ; =========================================================================
    helpGui.SetFont("s9 w400 norm", Theme.UiFont)
    btnOpenCC := helpGui.Add("Button", "x14 y562 w196 h34", "Open Control Center...")
    btnJumpHud := helpGui.Add("Button", "x222 y562 w188 h34", "Visual HUD Guide")
    btnJumpTray := helpGui.Add("Button", "x422 y562 w188 h34", "Browse Tray Menus")
    btnClose := helpGui.Add("Button", "x676 y562 w150 h34 Default", "Got it!")
    for bFoot in [btnOpenCC, btnJumpHud, btnJumpTray, btnClose]
        Theme.RegisterControl(helpGui, bFoot, "Button")

    CloseHelp(*) {
        if (IsObject(state) && state.HasOwnProp("refreshHelpFn"))
            state.refreshHelpFn := ""
        helpGui._onThemeRefresh := ""
        Theme.UnregisterWindow(helpGui, "HelpWindow")
        helpGui.Destroy()
    }

    btnOpenCC.OnEvent("Click", (*) => ShowControlCenterWindow(cfg, state))
    btnJumpHud.OnEvent("Click", (*) => tabs.Choose(1))
    btnJumpTray.OnEvent("Click", (*) => tabs.Choose(2))
    btnClose.OnEvent("Click", CloseHelp)
    helpGui.OnEvent("Close", CloseHelp)
    helpGui.OnEvent("Escape", CloseHelp)

    WindowFit.Show(helpGui, "w840 h612 Center")
    btnClose.Focus()
    return helpGui
}

ShowAboutWindow(cfg := "", state := "", *) {
    existing := Theme.FocusExistingWindow("AboutWindow")
    if IsObject(existing)
        return existing

    aboutGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "About PresenterSync")
    aboutGui.MarginX := 18
    aboutGui.MarginY := 16
    Theme.ApplyToWindow(aboutGui)
    Theme.NamedWindows["AboutWindow"] := aboutGui

    iconSource := A_IsCompiled ? A_ScriptFullPath : (FileExist(A_ScriptDir "\assets\PresenterSync.ico") ? A_ScriptDir "\assets\PresenterSync.ico" : A_LineFile "\..\..\assets\PresenterSync.ico")
    if FileExist(iconSource)
        aboutGui.Add("Picture", "x203 y16 w64 h64", iconSource)

    aboutGui.SetFont("s16 w700 norm", Theme.UiFont)
    Theme.RegisterControl(aboutGui, aboutGui.Add("Text", "x20 y88 w430 h30 Center", "PresenterSync"), "Text")

    aboutGui.SetFont("s10 w700 norm", Theme.UiFont)
    Theme.RegisterControl(aboutGui, aboutGui.Add("Text", "x20 y120 w430 h20 Center", "Version " UIConstants.APP_VERSION "  -  Primary Host Suite"), "Text", "accent")

    aboutGui.SetFont("s9 w400 norm", Theme.UiFont)
    Theme.RegisterControl(aboutGui, aboutGui.Add("Text", "x20 y142 w430 h20 Center", "OBS Studio WebSocket v5, UIA Meeting Telemetry & Smart Clicker Control"), "Text", "muted")

    aboutGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(aboutGui, aboutGui.Add("Text", "x20 y164 w430 h18 Center", "Created by Saabith Jiffry"), "Text")

    aboutGui.SetFont("s9 w700 norm", Theme.UiFont)
    Theme.RegisterControl(aboutGui, aboutGui.Add("Text", "x20 y192 w430 h18", "Included Primary Host Capabilities & Highlights:"), "Text")

    aboutGui.SetFont("s9 w400 norm", Theme.UiFont)
    primCapsText := "Full presenter host suite engineered for live lecturing, streaming & hybrid classrooms.`r`n`r`n"
        . "CORE PRIMARY HOST CAPABILITIES:`r`n"
        . Chr(0x2022) " 4-Tier Live HUD Stack & Secondary Mic Pill: Mic (VU bar + perimeter hold), Rec (click Start/Pause/Resume, hold Stop + OBS timer sync), Studio (hold bar), calm Scene marquee (+ right-click Live switch), read-only Stream & VCam pills, plus Secondary Mic Pill (incl. 1.25x scale).`r`n"
        . Chr(0x2022) " Director Deck, Standby BRB, Countdown Timer & Stage Nudge: Multi-device OBS scenes, chapter split/pause, synchronized timer, silent floating alerts & Push-to-Talk mode.`r`n"
        . Chr(0x2022) " Session Timeline & Chapter Export: Bounded 2,000-entry timeline exporting to Video Editor CSV chapters, Markdown tables & YouTube timestamps.`r`n"
        . Chr(0x2022) " 3 Audio Routing Modes & Clicker Control: OBS VB-Cable, Direct Conf (Zoom/Teams/Meet) & Dual Sync, 1-click Capture Keystroke buttons, Cough Hold, Mutual Exclusion Shield & PPT forwarding.`r`n"
        . Chr(0x2022) " Remote Companion Host (Bridge :4456, UDP :4457 & WAN Relay): Zero-config LAN/mDNS/QR pairing for Windows, Android & Zero-Install Browser Web Remote (favicon, About, Clean Disconnect, Direct OBS :4455 fallback).`r`n"
        . Chr(0x2022) " Reorganized Tray Menus, Custom Hex Colors, Control Center, Guided Setup Wizard & SHA-256 GitHub Self-Updater."
    AddHelpGuideEdit(aboutGui, 20, 214, 430, 224, primCapsText)

    aboutGui.SetFont("s9 w400 norm", Theme.UiFont)
    gitBtn := aboutGui.Add("Button", "x20 y450 w208 h30", "GitHub Repo")
    Theme.RegisterControl(aboutGui, gitBtn, "Button")
    gitBtn.OnEvent("Click", (*) => Run("https://github.com/SaabithJiffry/PresenterSync/"))

    updBtn := aboutGui.Add("Button", "x242 y450 w208 h30", "Check for Updates")
    Theme.RegisterControl(aboutGui, updBtn, "Button")
    updBtn.OnEvent("Click", (*) => CheckForUpdates(UIConstants.APP_VERSION, "", false, "", cfg))

    helpBtn := aboutGui.Add("Button", "x20 y488 w208 h30", "Open Help Guide")
    Theme.RegisterControl(aboutGui, helpBtn, "Button")
    CloseAbout(*) {
        Theme.UnregisterWindow(aboutGui, "AboutWindow")
        aboutGui.Destroy()
    }
    if IsObject(cfg)
        helpBtn.OnEvent("Click", (*) => (CloseAbout(), ShowHelpWindow(cfg, state)))
    else
        helpBtn.Enabled := false

    closeBtn := aboutGui.Add("Button", "x242 y488 w208 h30 Default", "Close")
    Theme.RegisterControl(aboutGui, closeBtn, "Button")
    closeBtn.OnEvent("Click", CloseAbout)
    aboutGui.OnEvent("Close", CloseAbout)
    aboutGui.OnEvent("Escape", CloseAbout)

    vaultExtraH := 0
    if (IsSet(ArcadeVault) && IsObject(cfg))
        vaultExtraH := ArcadeVault.AttachAboutVaultSection(aboutGui, cfg, state, 20, 526, 430, false, (c, s) => ShowAboutWindow(c, s))

    WindowFit.Show(aboutGui, "w470 h" (536 + vaultExtraH) " Center")
    closeBtn.Focus()
    return aboutGui
}

_ApplyLiveHotkeyRebindOrReload(state, dlg := "") {
    hasLiveRebind := (IsObject(state) && state.HasOwnProp("rebindHotkeysFn") && state.rebindHotkeysFn)
    if (!hasLiveRebind) {
        Reload()
        return
    }
    if (IsObject(dlg)) {
        if (dlg.HasOwnProp("_releaseState"))
            dlg._releaseState.Call()
        try dlg.Destroy()
    }
    try state.rebindHotkeysFn.Call()
    if (state.HasOwnProp("rebuildTrayFn") && state.rebuildTrayFn)
        try state.rebuildTrayFn.Call()
    if (state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn)
        try state.refreshHelpFn.Call()
}

ChangeAppHotkeysUI(cfg, state := "", *) {
    hasLiveRebind := (IsObject(state) && state.HasOwnProp("rebindHotkeysFn") && state.rebindHotkeysFn)
    SaveAppHk(values, ctrls, dlg) {
        cfg.PptHotkey := values["ppt"]
        cfg.WsHotkey := values["ws"]
        cfg.ZoomHotkey := values["zoom"]
        cfg.IndHotkey := values["ind"]
        cfg.SuspendHotkey := values["susp"]
        cfg.ExitHotkey := values["exit"]
        if (values.Has("remoteInfo")) {
            cfg.RemoteInfoHotkey := (Trim(values["remoteInfo"]) != "") ? Trim(values["remoteInfo"]) : "None"
            cfg.Write("Settings", "RemoteInfoHotkey", cfg.RemoteInfoHotkey)
        }
        cfg.Write("Settings", "PptHotkey", cfg.PptHotkey)
        cfg.Write("Settings", "WsHotkey", cfg.WsHotkey)
        cfg.Write("Settings", "ZoomHotkey", cfg.ZoomHotkey)
        cfg.Write("Settings", "IndHotkey", cfg.IndHotkey)
        cfg.Write("Settings", "SuspendHotkey", cfg.SuspendHotkey)
        cfg.Write("Settings", "ExitHotkey", cfg.ExitHotkey)
        _ApplyLiveHotkeyRebindOrReload(state, dlg)
    }

    elements := [
        {type: "Text", opts: "xm w160 h25 +0x200", text: "Cycle Pointer Mode:"},
        {type: "Shortcut", id: "ppt", opts: "x+10 yp w310 h25", value: cfg.PptHotkey, required: true, errorMsg: "Shortcuts cannot be left blank.", captureTitle: "Capture Cycle Pointer Mode"},
        {type: "Text", opts: "xm y+8 w160 h25 +0x200", text: "Toggle OBS WebSocket:"},
        {type: "Shortcut", id: "ws", opts: "x+10 yp w310 h25", value: cfg.WsHotkey, required: true, errorMsg: "Shortcuts cannot be left blank.", captureTitle: "Capture Toggle OBS Sync"},
        {type: "Text", opts: "xm y+8 w160 h25 +0x200", text: "Toggle Conf Monitor:"},
        {type: "Shortcut", id: "zoom", opts: "x+10 yp w310 h25", value: cfg.ZoomHotkey, required: true, errorMsg: "Shortcuts cannot be left blank.", captureTitle: "Capture Toggle Conf Monitor"},
        {type: "Text", opts: "xm y+8 w160 h25 +0x200", text: "Toggle Indicator:"},
        {type: "Shortcut", id: "ind", opts: "x+10 yp w310 h25", value: cfg.IndHotkey, required: true, errorMsg: "Shortcuts cannot be left blank.", captureTitle: "Capture Toggle Indicator"},
        {type: "Text", opts: "xm y+8 w160 h25 +0x200", text: "Suspend Hotkeys:"},
        {type: "Shortcut", id: "susp", opts: "x+10 yp w310 h25", value: cfg.SuspendHotkey, required: true, errorMsg: "Shortcuts cannot be left blank.", captureTitle: "Capture Suspend Hotkeys"},
        {type: "Text", opts: "xm y+8 w160 h25 +0x200", text: "Exit PresenterSync:"},
        {type: "Shortcut", id: "exit", opts: "x+10 yp w310 h25", value: cfg.ExitHotkey, required: true, errorMsg: "Shortcuts cannot be left blank.", captureTitle: "Capture Exit PresenterSync"},
        {type: "Text", opts: "xm y+8 w160 h25 +0x200", text: "Remote Setup / QR Info:"},
        {type: "Shortcut", id: "remoteInfo", opts: "x+10 yp w310 h25", value: cfg.RemoteInfoHotkey, captureTitle: "Capture Remote Setup Shortcut"}
    ]

    return BuildSettingsWindow("Edit App Shortcuts", elements, SaveAppHk, {
        saveBtnText: hasLiveRebind ? "Save & Apply" : "Save & Restart",
        saveBtnOpts: "xm w480 h32 Default y+16"
    })
}

SetConferencingApp(cfg, state, appName, *) {
    norm := NormalizeConferencingApp(appName)
    cfg.ConferencingApp := norm
    cfg.Write("Settings", "ConferencingApp", norm)
    if (IsObject(state)) {
        state.zoomConnected := false
        state.zoomLastMuted := -1
        state.zoomSawRecControl := false
        if (state.HasOwnProp("rebindHotkeysFn") && state.rebindHotkeysFn)
            try state.rebindHotkeysFn.Call()
        if (state.HasOwnProp("rebuildTrayFn") && state.rebuildTrayFn)
            try state.rebuildTrayFn.Call()
        if (state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn)
            try state.refreshHelpFn.Call()
    }
    return norm
}

ChangeZoomShortcutsUI(cfg, state := "", *) {
    hasLiveRebind := (IsObject(state) && state.HasOwnProp("rebindHotkeysFn") && state.rebindHotkeysFn)
    SaveZoomHk(values, ctrls, dlg) {
        cfg.ZoomMuteHotkey := values["mute"]
        cfg.Write("Settings", "ZoomMuteHotkey", cfg.ZoomMuteHotkey)
        if (values.Has("teamsMute") && values["teamsMute"] != "") {
            cfg.TeamsMuteHotkey := values["teamsMute"]
            cfg.Write("Settings", "TeamsMuteHotkey", cfg.TeamsMuteHotkey)
        }
        if (values.Has("meetMute") && values["meetMute"] != "") {
            cfg.MeetMuteHotkey := values["meetMute"]
            cfg.Write("Settings", "MeetMuteHotkey", cfg.MeetMuteHotkey)
        }
        cfg.ZoomRecHotkey := (values["rec"] != "") ? values["rec"] : "!r"
        cfg.ZoomPauseHotkey := (values["pause"] != "") ? values["pause"] : "!p"
        cfg.Write("Settings", "ZoomRecHotkey", cfg.ZoomRecHotkey)
        cfg.Write("Settings", "ZoomPauseHotkey", cfg.ZoomPauseHotkey)
        _ApplyLiveHotkeyRebindOrReload(state, dlg)
    }

    elements := [
        {type: "Text", opts: "w340", text: "Zoom Mute Shortcut (Default Alt+A):"},
        {type: "Shortcut", id: "mute", opts: "xm w340 h25", value: cfg.ZoomMuteHotkey, required: true, errorMsg: "Zoom Mute shortcut cannot be empty.", captureTitle: "Capture Zoom Mute Shortcut"},
        {type: "Text", opts: "xm w340 y+8", text: "Microsoft Teams Mute Shortcut (Default Ctrl+Shift+M):"},
        {type: "Shortcut", id: "teamsMute", opts: "xm w340 h25", value: cfg.TeamsMuteHotkey, captureTitle: "Capture Teams Mute Shortcut"},
        {type: "Text", opts: "xm w340 y+8", text: "Google Meet Mute Shortcut (Default Ctrl+D):"},
        {type: "Shortcut", id: "meetMute", opts: "xm w340 h25", value: cfg.MeetMuteHotkey, captureTitle: "Capture Meet Mute Shortcut"},
        {type: "Text", opts: "xm w340 y+8", text: "Zoom Start/Stop Recording (Default Alt+R):"},
        {type: "Shortcut", id: "rec", opts: "xm w340 h25", value: cfg.ZoomRecHotkey, captureTitle: "Capture Zoom Rec Shortcut"},
        {type: "Text", opts: "xm w340 y+8", text: "Zoom Pause/Resume Recording (Default Alt+P):"},
        {type: "Shortcut", id: "pause", opts: "xm w340 h25", value: cfg.ZoomPauseHotkey, captureTitle: "Capture Zoom Pause Shortcut"}
    ]

    return BuildSettingsWindow("Edit Conferencing Shortcuts", elements, SaveZoomHk, {
        saveBtnText: hasLiveRebind ? "Save & Apply" : "Save & Restart",
        saveBtnOpts: "xm w340 h32 Default y+14"
    })
}

SetRoutingMode(cfg, mode, state := "", *) {
    cfg.AudioRoutingMode := mode
    cfg.Write("Settings", "AudioRoutingMode", mode)
    if ((mode == 2 || mode == 3) && cfg.ZoomMuteHotkey = "") {
        cfg.ZoomMuteHotkey := "!a"
        cfg.Write("Settings", "ZoomMuteHotkey", "!a")
    }
    if (mode == 2 && (!cfg.HasOwnProp("InternetPairingCode") || cfg.InternetPairingCode = "")) {
        cfg.InternetPairingCode := GenerateInternetPairingCode()
        cfg.Write("Settings", "InternetPairingCode", cfg.InternetPairingCode)
    }
    cfg.EnableWS := (mode == 1 || mode == 3)
    cfg.EnableZoom := (mode == 2 || mode == 3)
    cfg.WriteBool("Settings", "EnableWS", cfg.EnableWS)
    cfg.WriteBool("Settings", "EnableZoom", cfg.EnableZoom)
    if (IsObject(state)) {
        if (IsSet(UpdateZoomMonitorTimer))
            try UpdateZoomMonitorTimer(cfg, state)
        if (IsSet(HostBridgeBroadcastMuteState))
            try HostBridgeBroadcastMuteState(cfg, state)
        if (state.HasOwnProp("rebuildTrayFn") && state.rebuildTrayFn)
            try state.rebuildTrayFn.Call()
        if (IsSet(RefreshHudAppearance))
            try RefreshHudAppearance(cfg, state)
    }
}

ChangeObsSettingsUI(cfg, state := "", *) {
    hasLiveRebind := (IsObject(state) && state.HasOwnProp("rebindHotkeysFn") && state.rebindHotkeysFn)
    SaveObsSettings(values, ctrls, dlg) {
        oldPw := cfg.HasOwnProp("obsPassword") ? String(cfg.obsPassword) : ""
        oldMic := cfg.HasOwnProp("targetMicName") ? String(cfg.targetMicName) : ""
        cfg.ObsMuteHotkey := (values["mute"] != "") ? values["mute"] : "None"
        cfg.ObsRecHotkey := (values["rec"] != "") ? values["rec"] : "^F9"
        cfg.ObsPauseHotkey := (values["pause"] != "") ? values["pause"] : "^F10"
        cfg.ObsTransitionHotkey := (values["transition"] != "") ? values["transition"] : "None"
        cfg.targetMicName := values["mic"]
        cfg.Write("Settings", "ObsHotkey", cfg.ObsMuteHotkey)
        cfg.Write("Settings", "ObsRecHotkey", cfg.ObsRecHotkey)
        cfg.Write("Settings", "ObsPauseHotkey", cfg.ObsPauseHotkey)
        cfg.Write("Settings", "ObsTransitionHotkey", cfg.ObsTransitionHotkey)
        cfg.Write("Settings", "TargetMicName", cfg.targetMicName)
        if (values.Has("pw")) {
            cfg.obsPassword := values["pw"]
            cfg.Write("Settings", "ObsPassword", cfg.obsPassword)
        }
        if (IsSet(ApplyHostObsCredentialsChange))
            ApplyHostObsCredentialsChange(cfg, state, oldPw, oldMic)
        _ApplyLiveHotkeyRebindOrReload(state, dlg)
    }

    elements := [
        {type: "Text", opts: "w340", text: "OBS Mute Shortcut" (cfg.EnableWS ? " (Optional with WebSocket):" : ":")},
        {type: "Shortcut", id: "mute", opts: "xm w340 h25", value: (cfg.ObsMuteHotkey != "None") ? cfg.ObsMuteHotkey : "", required: (!cfg.EnableWS && cfg.AudioRoutingMode != 2), errorMsg: "OBS Mute shortcut cannot be empty unless WebSocket Sync is enabled.", captureTitle: "Capture OBS Mute Shortcut"},
        {type: "Text", opts: "xm w340 y+10", text: "Start/Stop Recording Shortcut:"},
        {type: "Shortcut", id: "rec", opts: "xm w340 h25", value: cfg.ObsRecHotkey, captureTitle: "Capture OBS Rec Shortcut"},
        {type: "Text", opts: "xm w340 y+10", text: "Pause/Resume Recording Shortcut:"},
        {type: "Shortcut", id: "pause", opts: "xm w340 h25", value: cfg.ObsPauseHotkey, captureTitle: "Capture OBS Pause Shortcut"},
        {type: "Text", opts: "xm w340 y+10", text: "OBS Transition Shortcut (Fallback):"},
        {type: "Shortcut", id: "transition", opts: "xm w340 h25", value: (cfg.ObsTransitionHotkey != "None") ? cfg.ObsTransitionHotkey : "", captureTitle: "Capture OBS Transition Shortcut"},
        {type: "Text", opts: "xm w340 y+10", text: "Exact OBS Audio Source Name (e.g., Mic/Aux):"},
        {type: "Edit", id: "mic", opts: "xm w340", value: cfg.targetMicName, required: true, errorMsg: "Exact OBS Audio Source Name cannot be empty."},
        {type: "Text", opts: "xm w340 y+10", text: "OBS WebSocket Password (Optional):"},
        {type: "Edit", id: "pw", opts: "xm w340 Password", value: cfg.obsPassword}
    ]

    return BuildSettingsWindow("OBS Settings", elements, SaveObsSettings, {
        saveBtnText: hasLiveRebind ? "Save & Apply" : "Save & Restart",
        saveBtnOpts: "xm w340 h32 Default y+15"
    })
}

OpenPointerKeyCaptureDialog(currentKey, saveBtnLabel, onApply, dialogTitle := "Edit Pointer Mute Button", headingText := "Presentation Clicker Mute Button") {
    existing := Theme.FocusExistingWindow(dialogTitle)
    if IsObject(existing)
        return existing

    Theme.AcquireSuspend()

    dlg := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", dialogTitle)
    dlg._closed := false
    dlg.MarginX := 20
    dlg.MarginY := 18
    Theme.ApplyToWindow(dlg)
    Theme.NamedWindows[dialogTitle] := dlg

    dlg.SetFont("s10 w600", Theme.UiFont)
    Theme.RegisterControl(dlg, dlg.Add("Text", "xm w306", headingText), "Text")
    dlg.SetFont("s9 w400", Theme.UiFont)
    Theme.RegisterControl(dlg, dlg.Add("Text", "xm w306 y+4", "Press a button on your clicker, or click the box to type a custom key name:"), "Text", "muted")

    dlg.SetFont("s12 w700", Theme.UiFont)
    editKey := dlg.Add("Edit", "xm w180 h32 y+12 Center", currentKey)
    Theme.RegisterControl(dlg, editKey, "Edit", "accent")

    dlg.SetFont("s9 w600", Theme.UiFont)
    btnCapPtr := dlg.Add("Button", "x+6 yp w120 h32", "Capture Keystroke")
    Theme.RegisterControl(dlg, btnCapPtr, "Button", "tabButton")

    dlg.SetFont("s9 w400", Theme.UiFont)
    statusTxt := dlg.Add("Text", "xm w306 y+8 Center", "Listening for clicker input...")
    Theme.RegisterControl(dlg, statusTxt, "Text", "muted")

    dlg.SetFont("s10 w400", Theme.UiFont)
    btnSave := dlg.Add("Button", "xm w306 h34 y+14 Default", saveBtnLabel)
    Theme.RegisterControl(dlg, btnSave, "Button", "accent")

    ih := InputHook("L0")
    ih.KeyOpt("{All}", "N")
    ih.KeyOpt("{Enter}{NumpadEnter}{Escape}{Tab}{LShift}{RShift}{LControl}{RControl}{LAlt}{RAlt}{LWin}{RWin}", "-N V")
    ih.OnKeyDown := (ihHook, VK, SC) => (
        keyName := GetKeyName(Format("vk{:X}sc{:X}", VK, SC)),
        (keyName != "" && !dlg._closed) ? (
            editKey.Value := keyName,
            statusTxt.Value := "Captured: " keyName
        ) : 0
    )

    StartCapture(*) {
        if (dlg._closed)
            return
        try ih.Start()
        statusTxt.Value := "Listening for clicker input..."
    }

    StopCapture(*) {
        try ih.Stop()
        if (!dlg._closed && WinExist("ahk_id " dlg.Hwnd))
            statusTxt.Value := "Manual typing mode (type key name)"
    }

    editKey.OnEvent("Focus", StopCapture)
    editKey.OnEvent("LoseFocus", StartCapture)
    btnCapPtr.OnEvent("Click", (*) => (btnSave.Focus(), StartCapture()))

    OnActivateMsg(wParam, lParam, msg, hwnd) {
        try {
            if (dlg._closed || hwnd != dlg.Hwnd)
                return
        } catch {
            return
        }
        if ((wParam & 0xFFFF) == 0) {
            try ih.Stop()
        } else {
            try focused := dlg.FocusedCtrl
            catch
                focused := ""
            if (focused != editKey)
                StartCapture()
        }
    }
    OnMessage(0x0006, OnActivateMsg)

    Cleanup(*) {
        if (dlg._closed)
            return
        dlg._closed := true
        OnMessage(0x0006, OnActivateMsg, 0)
        try ih.Stop()
        Theme.UnregisterWindow(dlg, dialogTitle)
        Theme.ReleaseSuspend()
        dlg.Destroy()
    }

    SaveKey(*) {
        static dummyHotIf := (*) => false
        static dummyHandler := (*) => 0
        val := Trim(editKey.Value)
        if (val = "") {
            dlg.Opt("+OwnDialogs")
            MsgBox("Please press or enter a button name to register it.", "Error", "Icon!")
            return
        }
        if (StrLower(val) = "none") {
            Cleanup()
            onApply.Call("None")
            return
        }
        try {
            HotIf dummyHotIf
            Hotkey(val, dummyHandler, "Off")
            HotIf
        } catch {
            HotIf
            dlg.Opt("+OwnDialogs")
            MsgBox("'" val "' is not a valid AutoHotkey key name.`nExamples: b, PgDn, F12, Media_Play_Pause", "Invalid Key", "Icon!")
            return
        }
        Cleanup()
        onApply.Call(val)
    }

    btnSave.OnEvent("Click", SaveKey)
    dlg.OnEvent("Close", Cleanup)
    dlg.OnEvent("Escape", Cleanup)

    WindowFit.Show(dlg, "AutoSize Center")
    btnSave.Focus()
    StartCapture()
    return dlg
}

ChangeHwMuteHotkeyUI(cfg, state := "", *) {
    hasLiveRebind := (IsObject(state) && state.HasOwnProp("rebindHotkeysFn") && state.rebindHotkeysFn)
    btnLabel := hasLiveRebind ? "Save & Apply" : "Save & Restart"
    return OpenPointerKeyCaptureDialog(cfg.HwMuteHotkey, btnLabel, (val) => (
        cfg.HwMuteHotkey := val,
        cfg.Write("Settings", "HwMuteHotkey", val),
        _ApplyLiveHotkeyRebindOrReload(state)
    ))
}

ChangeHwTransitionHotkeyUI(cfg, state := "", *) {
    hasLiveRebind := (IsObject(state) && state.HasOwnProp("rebindHotkeysFn") && state.rebindHotkeysFn)
    btnLabel := hasLiveRebind ? "Save & Apply" : "Save & Restart"
    return OpenPointerKeyCaptureDialog(cfg.HwTransitionHotkey, btnLabel, (val) => (
        cfg.HwTransitionHotkey := val,
        cfg.Write("Settings", "HwTransitionHotkey", val),
        _ApplyLiveHotkeyRebindOrReload(state)
    ), "Edit Pointer OBS Transition Button", "Presentation Clicker OBS Transition Button")
}

ConfigurePointerKeysUI(cfg, state := "", *) {
    hasLiveRebind := (IsObject(state) && state.HasOwnProp("rebindHotkeysFn") && state.rebindHotkeysFn)
    SavePointerKeys(values, ctrls, dlg) {
        cfg.CatchArrows := !!values["arrows"]
        cfg.CatchPg := !!values["pg"]
        cfg.CatchSpace := !!values["space"]
        cfg.CatchEnter := !!values["enter"]
        cfg.CatchTab := !!values["tab"]
        cfg.CatchEsc := !!values["esc"]
        cfg.Write("Pointer", "CatchArrows", values["arrows"])
        cfg.Write("Pointer", "CatchPg", values["pg"])
        cfg.Write("Pointer", "CatchSpace", values["space"])
        cfg.Write("Pointer", "CatchEnter", values["enter"])
        cfg.Write("Pointer", "CatchTab", values["tab"])
        cfg.Write("Pointer", "CatchEsc", values["esc"])
        _ApplyLiveHotkeyRebindOrReload(state, dlg)
    }

    elements := [
        {type: "Text", opts: "w260", text: "Select which keys to intercept in Full PPT Mode:"},
        {type: "Checkbox", id: "arrows", opts: "w260", value: cfg.CatchArrows, text: "Arrow Keys (Up, Down, Left, Right)"},
        {type: "Checkbox", id: "pg", opts: "w260", value: cfg.CatchPg, text: "Page Keys (PgUp, PgDn)"},
        {type: "Checkbox", id: "space", opts: "w260", value: cfg.CatchSpace, text: "Spacebar"},
        {type: "Checkbox", id: "enter", opts: "w260", value: cfg.CatchEnter, text: "Enter Key"},
        {type: "Checkbox", id: "tab", opts: "w260", value: cfg.CatchTab, text: "Tab Key"},
        {type: "Checkbox", id: "esc", opts: "w260", value: cfg.CatchEsc, text: "Escape Key"}
    ]

    return BuildSettingsWindow("Configure Pointer Intercepts", elements, SavePointerKeys, {
        saveBtnText: hasLiveRebind ? "Save & Apply" : "Save & Restart",
        saveBtnOpts: "w260 h32 Default y+15"
    })
}

ShowPointerTester(*) {
    existing := Theme.FocusExistingWindow("PointerTester")
    if IsObject(existing)
        return existing

    Theme.AcquireSuspend()

    testerGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "Pointer Tester")
    testerGui._closed := false
    testerGui.MarginX := 20
    testerGui.MarginY := 18
    Theme.ApplyToWindow(testerGui)
    Theme.NamedWindows["PointerTester"] := testerGui

    testerGui.SetFont("s10 w400 norm", Theme.UiFont)
    Theme.RegisterControl(testerGui, testerGui.Add("Text", "xm w280 Center", "Press any button on your clicker:"), "Text", "muted")

    testerGui.SetFont("s14 w700 norm", Theme.UiFont)
    keyDisplay := testerGui.Add("Text", "xm w280 h38 y+12 Center +0x200", "Listening...")
    Theme.RegisterControl(testerGui, keyDisplay, "Text", "accent")

    testerGui.SetFont("s10 w400 norm", Theme.UiFont)
    btn := testerGui.Add("Button", "xm w280 h34 y+16 Default", "Close")
    Theme.RegisterControl(testerGui, btn, "Button")

    ih := InputHook("L0 V")
    ih.KeyOpt("{All}", "N")

    ih.OnKeyDown := (ih, VK, SC) => UpdateKeyDisplay(VK, SC)

    UpdateKeyDisplay(VK, SC) {
        keyName := GetKeyName(Format("vk{:X}sc{:X}", VK, SC))
        if WinExist("ahk_id " testerGui.Hwnd)
            keyDisplay.Value := keyName
    }

    Cleanup(*) {
        if (testerGui._closed)
            return
        testerGui._closed := true
        ih.Stop()
        Theme.UnregisterWindow(testerGui, "PointerTester")
        Theme.ReleaseSuspend()
        testerGui.Destroy()
    }

    testerGui.OnEvent("Close", Cleanup)
    testerGui.OnEvent("Escape", Cleanup)
    btn.OnEvent("Click", Cleanup)

    WindowFit.Show(testerGui, "AutoSize Center")
    ih.Start()
    return testerGui
}

ResetAutoProfileTracking(state) {
    if (!IsObject(state))
        return
    state._autoProfileBase := ""
    state._autoProfileMatched := ""
    state._autoProfileRuleProc := ""
}

ParseAutoProfileRules(rawRules) {
    out := []
    seen := Map()
    rawStr := StrReplace(StrReplace(String(rawRules), "`r", "`n"), ";", "|")
    rawStr := StrReplace(StrReplace(rawStr, ",", "|"), "`n", "|")
    for _, entry in StrSplit(rawStr, "|") {
        trimmed := Trim(entry)
        eqPos := InStr(trimmed, "=")
        if (eqPos <= 1)
            continue
        rawProc := Trim(SubStr(trimmed, 1, eqPos - 1))
        rawProf := Trim(SubStr(trimmed, eqPos + 1))
        if (rawProc = "" || rawProf = "")
            continue
        SplitPath(rawProc, &procLeaf)
        lowerProc := StrLower(Trim(procLeaf))
        cleanProf := SubStr(Trim(RegExReplace(rawProf, '[\|\[\]=`r`n`t]', "")), 1, 48)
        if (lowerProc = "" || cleanProf = "" || seen.Has(lowerProc))
            continue
        seen[lowerProc] := true
        out.Push({proc: lowerProc, profile: cleanProf})
    }
    return out
}

FormatAutoProfileRules(rules) {
    if (!IsObject(rules))
        return ""
    joined := ""
    for _, item in rules {
        if (!IsObject(item) || !item.HasOwnProp("proc") || !item.HasOwnProp("profile"))
            continue
        p := StrLower(Trim(String(item.proc)))
        prof := Trim(String(item.profile))
        if (p != "" && prof != "")
            joined .= (joined != "" ? "|" : "") p "=" prof
    }
    return joined
}

MatchAutoProfileRule(cfg, activeProcName) {
    if (!IsObject(cfg) || !cfg.HasOwnProp("AutoProfileRules") || Trim(cfg.AutoProfileRules) = "")
        return ""
    rawProc := Trim(String(activeProcName))
    if (rawProc = "")
        return ""
    SplitPath(rawProc, &leafProc)
    procLow := StrLower(Trim(leafProc))
    if (procLow = "")
        return ""
    procStem := RegExReplace(procLow, "\.exe$", "")

    rules := ParseAutoProfileRules(cfg.AutoProfileRules)
    if (rules.Length == 0)
        return ""
    avail := cfg.GetProfileNames()

    for _, rule in rules {
        ruleStem := RegExReplace(rule.proc, "\.exe$", "")
        if (rule.proc = procLow || ruleStem = procStem) {
            for _, canonical in avail {
                if (StrLower(canonical) = StrLower(rule.profile)) {
                    if (StrLower(canonical) = "default" || cfg.Read("Profile:" canonical, "__Exists", "") = "1")
                        return canonical
                }
            }
        }
    }
    return ""
}

EvaluateAutoProfileTrigger(cfg, state, activeProcName) {
    if (!IsObject(cfg) || !IsObject(state))
        return {changed: false, action: "invalid", target: "", baseProfile: ""}
    if (!cfg.HasOwnProp("EnableAutoProfileSwitch") || !cfg.EnableAutoProfileSwitch)
        return {changed: false, action: "disabled", target: cfg.ActiveProfile, baseProfile: ""}

    matchedProf := MatchAutoProfileRule(cfg, activeProcName)
    if (matchedProf != "") {
        if (!state.HasOwnProp("_autoProfileMatched") || state._autoProfileMatched = "")
            state._autoProfileBase := cfg.ActiveProfile
        if (StrLower(cfg.ActiveProfile) != StrLower(matchedProf)) {
            if (cfg.ApplyProfile(matchedProf, state)) {
                state._autoProfileMatched := cfg.ActiveProfile
                state._autoProfileRuleProc := StrLower(Trim(String(activeProcName)))
                return {changed: true, action: "switched", target: cfg.ActiveProfile, baseProfile: state._autoProfileBase}
            }
            return {changed: false, action: "apply_failed", target: matchedProf, baseProfile: state._autoProfileBase}
        }
        state._autoProfileMatched := cfg.ActiveProfile
        state._autoProfileRuleProc := StrLower(Trim(String(activeProcName)))
        return {changed: false, action: "held", target: cfg.ActiveProfile, baseProfile: state._autoProfileBase}
    }

    if (state.HasOwnProp("_autoProfileMatched") && state._autoProfileMatched != "") {
        prevBase := state.HasOwnProp("_autoProfileBase") ? state._autoProfileBase : ""
        ResetAutoProfileTracking(state)
        if (prevBase != "" && StrLower(cfg.ActiveProfile) != StrLower(prevBase)) {
            if (cfg.ApplyProfile(prevBase, state))
                return {changed: true, action: "restored", target: cfg.ActiveProfile, baseProfile: prevBase}
        }
    }
    return {changed: false, action: "none", target: cfg.ActiveProfile, baseProfile: ""}
}

PollAutoProfileTrigger(cfg, state) {
    if (!IsObject(cfg) || !IsObject(state) || !cfg.EnableAutoProfileSwitch)
        return
    try {
        fgHwnd := WinExist("A")
        if (!fgHwnd)
            return
        fgPid := WinGetPID("ahk_id " fgHwnd)
        if (fgPid == DllCall("kernel32\GetCurrentProcessId", "UInt"))
            return
        procName := WinGetProcessName("ahk_id " fgHwnd)
        res := EvaluateAutoProfileTrigger(cfg, state, procName)
        if (res.changed) {
            verb := (res.action = "restored") ? "Restored" : "Switched"
            TrayTip("Auto-Profile " verb ": " res.target, "PresenterSync Profiles", 1)
        }
    }
}

UpdateAutoProfileTimer(cfg, state) {
    if (!IsObject(state) || !state.HasOwnProp("autoProfileTimerFn") || !state.autoProfileTimerFn)
        return
    if (IsObject(cfg) && cfg.HasOwnProp("EnableAutoProfileSwitch") && cfg.EnableAutoProfileSwitch) {
        SetTimer(state.autoProfileTimerFn, 900)
    } else {
        SetTimer(state.autoProfileTimerFn, 0)
        ResetAutoProfileTracking(state)
    }
}

ToggleAutoProfileSwitch(cfg, state, *) {
    if (!IsObject(cfg))
        return
    cfg.EnableAutoProfileSwitch := !cfg.EnableAutoProfileSwitch
    cfg.WriteBool("Settings", "EnableAutoProfileSwitch", cfg.EnableAutoProfileSwitch)
    UpdateAutoProfileTimer(cfg, state)
    if (IsObject(state)) {
        if (state.HasOwnProp("rebuildTrayFn") && state.rebuildTrayFn)
            try state.rebuildTrayFn.Call()
        if (state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn)
            try state.refreshHelpFn.Call()
    }
    TrayTip(cfg.EnableAutoProfileSwitch ? "App-Trigger Auto-Profile Switching enabled." : "App-Trigger Auto-Profile Switching disabled.", "PresenterSync Profiles", 1)
}

SwitchProfileAction(cfg, state, profileName, *) {
    ResetAutoProfileTracking(state)
    if (cfg.ApplyProfile(profileName, state)) {
        TrayTip("Switched to Profile: " cfg.ActiveProfile, "PresenterSync Profiles", 1)
    }
}

ShowProfileManagerUI(cfg, state := "") {
    existing := Theme.FocusExistingWindow("PresenterSync - Profile Manager")
    if IsObject(existing)
        return existing

    Theme.AcquireSuspend()

    dlg := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "PresenterSync - Profile Manager")
    dlg._closed := false
    dlg.MarginX := 20
    dlg.MarginY := 16
    Theme.ApplyToWindow(dlg)
    Theme.NamedWindows["PresenterSync - Profile Manager"] := dlg

    dlg.SetFont("s10 w600", Theme.UiFont)
    Theme.RegisterControl(dlg, dlg.Add("Text", "xm w360", "Configuration Profiles"), "Text")
    dlg.SetFont("s9 w400", Theme.UiFont)
    lblActive := dlg.Add("Text", "xm w360 y+4", "Active Profile: " cfg.ActiveProfile)
    Theme.RegisterControl(dlg, lblActive, "Text", "accent")

    lb := dlg.Add("ListBox", "xm w220 h136 y+10", cfg.GetProfileNames())
    Theme.RegisterControl(dlg, lb, "Edit")

    btnLoad := dlg.Add("Button", "x+12 yp w128 h30 Default", "Load Profile")
    btnSave := dlg.Add("Button", "xp y+8 w128 h30", "Save Current")
    btnDel := dlg.Add("Button", "xp y+8 w128 h30", "Delete Profile")
    Theme.RegisterControl(dlg, btnLoad, "Button", "accent")
    Theme.RegisterControl(dlg, btnSave, "Button")
    Theme.RegisterControl(dlg, btnDel, "Button")

    lb.GetPos(, &lbY,, &lbH)
    dlg.SetFont("s9 w600", Theme.UiFont)
    Theme.RegisterControl(dlg, dlg.Add("Text", Format("xm w360 y{}", lbY + lbH + 12), "Save Current Settings As New Profile:"), "Text")
    dlg.SetFont("s9 w400", Theme.UiFont)
    editNew := dlg.Add("Edit", "xm w220")
    Theme.RegisterControl(dlg, editNew, "Edit")
    btnNew := dlg.Add("Button", "x+12 yp-2 w128 h28", "Save As New")
    Theme.RegisterControl(dlg, btnNew, "Button", "accent")

    btnNew.GetPos(, &bnY,, &bnH)
    dlg.SetFont("s9 w600", Theme.UiFont)
    Theme.RegisterControl(dlg, dlg.Add("Text", Format("xm w360 y{}", bnY + bnH + 12), "App-Trigger Auto-Profile Switching:"), "Text")
    dlg.SetFont("s9 w400", Theme.UiFont)
    chkAutoProf := dlg.Add("Checkbox", "xm w360 y+6" (cfg.EnableAutoProfileSwitch ? " Checked" : ""), "Auto-switch profile when matching app is active")
    Theme.RegisterControl(dlg, chkAutoProf, "Checkbox")
    Theme.RegisterControl(dlg, dlg.Add("Text", "xm w360 y+6", "Rules (proc.exe=Profile | ..., e.g. obs64.exe=OBS|Zoom.exe=Zoom):"), "Text", "muted")
    editRules := dlg.Add("Edit", "xm w220 y+6", cfg.HasOwnProp("AutoProfileRules") ? cfg.AutoProfileRules : "")
    Theme.RegisterControl(dlg, editRules, "Edit")
    DllCall("SendMessage", "Ptr", editRules.Hwnd, "UInt", 0x1501, "Ptr", 1, "WStr", "obs64.exe=OBS|Zoom.exe=Zoom|ms-teams.exe=Teams")
    btnSaveRules := dlg.Add("Button", "x+12 yp-2 w128 h28", "Save Auto Rules")
    Theme.RegisterControl(dlg, btnSaveRules, "Button")

    btnSaveRules.GetPos(, &srY,, &srH)
    lblMsg := dlg.Add("Text", Format("xm w220 y{}", srY + srH + 14), "Save presets for OBS, Zoom, Teams, or Meet.")
    Theme.RegisterControl(dlg, lblMsg, "Text", "muted")
    btnClose := dlg.Add("Button", Format("x+12 y{} w128 h30", srY + srH + 10), "Close")
    Theme.RegisterControl(dlg, btnClose, "Button")

    RefreshList(selectName := "") {
        names := cfg.GetProfileNames()
        lb.Delete()
        lb.Add(names)
        target := (selectName != "") ? selectName : cfg.ActiveProfile
        chooseIdx := 1
        for idx, n in names {
            if (StrLower(n) = StrLower(target)) {
                chooseIdx := idx
                break
            }
        }
        lb.Choose(chooseIdx)
        lblActive.Value := "Active Profile: " cfg.ActiveProfile
        btnDel.Enabled := (StrLower(lb.Text) != "default")
        chkAutoProf.Value := cfg.EnableAutoProfileSwitch ? 1 : 0
    }
    RefreshList(cfg.ActiveProfile)

    OnLoadClick(*) {
        if (lb.Text = "") {
            lblMsg.Value := "Select a profile first."
            return
        }
        ResetAutoProfileTracking(state)
        if (cfg.ApplyProfile(lb.Text, state)) {
            RefreshList(cfg.ActiveProfile)
            lblMsg.Value := "Loaded profile: " cfg.ActiveProfile
        } else {
            lblMsg.Value := "Save snapshot to '" lb.Text "' first."
        }
    }

    OnSaveClick(*) {
        if (lb.Text = "") {
            lblMsg.Value := "Select a profile first."
            return
        }
        cfg.SaveProfile(lb.Text)
        RefreshList(cfg.ActiveProfile)
        if (IsObject(state) && state.HasOwnProp("rebuildTrayFn") && state.rebuildTrayFn)
            try state.rebuildTrayFn.Call()
        lblMsg.Value := "Updated snapshot: " cfg.ActiveProfile
    }

    OnNewClick(*) {
        newName := cfg.NormalizeProfileName(editNew.Value)
        if (newName = "") {
            lblMsg.Value := "Enter a valid profile name."
            return
        }
        cfg.SaveProfile(newName)
        editNew.Value := ""
        RefreshList(cfg.ActiveProfile)
        if (IsObject(state) && state.HasOwnProp("rebuildTrayFn") && state.rebuildTrayFn)
            try state.rebuildTrayFn.Call()
        lblMsg.Value := "Created profile: " cfg.ActiveProfile
    }

    OnSaveRulesClick(*) {
        parsed := ParseAutoProfileRules(editRules.Value)
        formatted := FormatAutoProfileRules(parsed)
        cfg.EnableAutoProfileSwitch := !!chkAutoProf.Value
        cfg.AutoProfileRules := formatted
        editRules.Value := formatted
        cfg.WriteBool("Settings", "EnableAutoProfileSwitch", cfg.EnableAutoProfileSwitch)
        cfg.Write("Settings", "AutoProfileRules", formatted)
        UpdateAutoProfileTimer(cfg, state)
        if (IsObject(state) && state.HasOwnProp("rebuildTrayFn") && state.rebuildTrayFn)
            try state.rebuildTrayFn.Call()
        if (IsObject(state) && state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn)
            try state.refreshHelpFn.Call()
        lblMsg.Value := (cfg.EnableAutoProfileSwitch ? "Auto-switch ON" : "Auto-switch OFF") " (" parsed.Length " rule(s) saved)."
    }

    OnDeleteClick(*) {
        if (StrLower(lb.Text) = "default") {
            lblMsg.Value := "Default profile is protected."
            return
        }
        if (cfg.DeleteProfile(lb.Text)) {
            RefreshList(cfg.ActiveProfile)
            if (IsObject(state) && state.HasOwnProp("rebuildTrayFn") && state.rebuildTrayFn)
                try state.rebuildTrayFn.Call()
            lblMsg.Value := "Profile deleted."
        } else {
            lblMsg.Value := "Could not delete profile."
        }
    }

    lb.OnEvent("Change", (*) => (btnDel.Enabled := (StrLower(lb.Text) != "default")))
    lb.OnEvent("DoubleClick", OnLoadClick)
    btnLoad.OnEvent("Click", OnLoadClick)
    btnSave.OnEvent("Click", OnSaveClick)
    btnNew.OnEvent("Click", OnNewClick)
    btnSaveRules.OnEvent("Click", OnSaveRulesClick)
    chkAutoProf.OnEvent("Click", OnSaveRulesClick)
    btnDel.OnEvent("Click", OnDeleteClick)

    CloseProfileMgr(*) {
        if (dlg._closed)
            return
        dlg._closed := true
        Theme.UnregisterWindow(dlg, "PresenterSync - Profile Manager")
        Theme.ReleaseSuspend()
        dlg.Destroy()
    }
    btnClose.OnEvent("Click", CloseProfileMgr)
    dlg.OnEvent("Close", CloseProfileMgr)
    dlg.OnEvent("Escape", CloseProfileMgr)

    WindowFit.Show(dlg)
    return dlg
}

GetStartupRegistryValueName(cfg) {
    return (IsObject(cfg) && cfg.HasOwnProp("ConfigFile") && InStr(cfg.ConfigFile, "Remote")) ? "PresenterSyncRemote" : "PresenterSync"
}

GetStartupLaunchCommand(cfg) {
    return A_IsCompiled ? ('"' A_ScriptFullPath '"') : ('"' A_AhkPath '" "' A_ScriptFullPath '"')
}

SetStartWithWindows(cfg, state := "", enable := "", writeRegistry := true) {
    if (!IsObject(cfg))
        return false
    target := (enable = "") ? !cfg.StartWithWindows : !!enable
    cfg.StartWithWindows := target
    cfg.WriteBool("Settings", "StartWithWindows", target)
    if (writeRegistry) {
        regKey := "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run"
        valName := GetStartupRegistryValueName(cfg)
        if (target) {
            try RegWrite(GetStartupLaunchCommand(cfg), "REG_SZ", regKey, valName)
        } else {
            try RegDelete(regKey, valName)
        }
    }
    if (IsObject(state)) {
        if (state.HasOwnProp("rebuildTrayFn") && state.rebuildTrayFn)
            try state.rebuildTrayFn.Call()
        if (state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn)
            try state.refreshHelpFn.Call()
    }
    return target
}

ToggleStartWithWindows(cfg, state := "", *) {
    enabled := SetStartWithWindows(cfg, state)
    TrayTip("Start with Windows: " (enabled ? "ON" : "OFF"), "PresenterSync", 1)
    return enabled
}

_Diag_ShouldRedactKey(sectionName, keyName) {
    sec := Trim(String(sectionName))
    key := Trim(String(keyName))
    if (RegExMatch(sec, "i)^HostBridgePairedDevices$"))
        return true
    if (RegExMatch(key, "i)(password|token|secret|pairingcode|sessioncode|apikey|bearer|auth)"))
        return true
    return false
}

SanitizeDiagnosticIniValue(sectionName, keyName, val) {
    sec := Trim(String(sectionName))
    v := String(val)
    if (RegExMatch(sec, "i)^HostBridgePairedDevices$")) {
        parts := StrSplit(v, "|")
        if (parts.Length >= 4 && parts[1] = "v1") {
            if (parts[4] != "")
                parts[4] := "[REDACTED]"
            out := ""
            for idx, p in parts
                out .= (idx > 1 ? "|" : "") p
            return out
        }
        return (v != "") ? "[REDACTED]" : "(empty)"
    }
    if (_Diag_ShouldRedactKey(sec, keyName))
        return (v != "") ? "[REDACTED]" : "(empty)"
    return v
}

SanitizeIniTextForDiagnostics(rawIniText, explicitSecrets := "") {
    curSec := ""
    linesOut := []
    for _, line in StrSplit(String(rawIniText), "`n", "`r") {
        trimmed := Trim(line)
        if (trimmed = "" || SubStr(trimmed, 1, 1) = ";") {
            linesOut.Push(line)
            continue
        }
        if (RegExMatch(trimmed, "^\[([^\]]+)\]$", &mSec)) {
            curSec := Trim(mSec[1])
            linesOut.Push("[" curSec "]")
            continue
        }
        eqPos := InStr(trimmed, "=")
        if (eqPos > 1) {
            k := Trim(SubStr(trimmed, 1, eqPos - 1))
            v := SubStr(trimmed, eqPos + 1)
            linesOut.Push(k "=" SanitizeDiagnosticIniValue(curSec, k, v))
        } else {
            linesOut.Push(line)
        }
    }
    joined := ""
    for idx, l in linesOut
        joined .= (idx > 1 ? "`r`n" : "") l
    if (IsObject(explicitSecrets)) {
        for _, secVal in explicitSecrets {
            s := Trim(String(secVal))
            if (StrLen(s) >= 4)
                joined := StrReplace(joined, s, "[REDACTED]")
        }
    }
    return joined
}

BuildSanitizedDiagnosticsReport(cfg, state := "", iniTextOverride := "") {
    secrets := []
    if IsObject(cfg) {
        for _, propName in ["obsPassword", "ObsPassword", "InternetPairingCode", "SessionPairingCode", "SessionToken"] {
            if (cfg.HasOwnProp(propName)) {
                pv := Trim(String(cfg.%propName%))
                if (pv != "")
                    secrets.Push(pv)
            }
        }
    }

    epText := "(unavailable)"
    try {
        eps := GetLocalNetworkEndpoints()
        if (IsObject(eps) && eps.HasOwnProp("ips"))
            epText := eps.ips.Length " local IP(s), mDNS: " A_ComputerName ".local"
    }

    rawIni := ""
    if (iniTextOverride != "") {
        rawIni := String(iniTextOverride)
    } else if (IsObject(cfg) && cfg.HasOwnProp("ConfigFile") && cfg.ConfigFile != "" && FileExist(cfg.ConfigFile)) {
        try rawIni := FileRead(cfg.ConfigFile, "UTF-8")
    }
    safeIni := SanitizeIniTextForDiagnostics(rawIni, secrets)

    autoState := "OFF"
    if (IsObject(cfg) && cfg.HasOwnProp("EnableAutoProfileSwitch")) {
        autoState := cfg.EnableAutoProfileSwitch ? "ON" : "OFF"
        if (cfg.HasOwnProp("AutoProfileRules") && cfg.AutoProfileRules != "")
            autoState .= " (" cfg.AutoProfileRules ")"
    }

    bridgeLine := "Inactive"
    if (IsSet(g_HostCompanionBridge) && IsObject(g_HostCompanionBridge) && g_HostCompanionBridge.HasOwnProp("running") && g_HostCompanionBridge.running) {
        bridgeLine := "Listening on TCP/UDP :" g_HostCompanionBridge.boundTcpPort " (Paired devices: " g_HostCompanionBridge.pairedDevices.Count ", Active WS clients: " g_HostCompanionBridge.clients.Count ")"
    }

    summarySec := IsObject(cfg) ? BuildLiveStatusSummary(cfg, state) : ("PresenterSync Version:   v" UIConstants.APP_VERSION)
    rpt := "==============================================================================`r`n"
        . "PresenterSync Sanitized Diagnostic Bundle (All Secrets Redacted)`r`n"
        . "==============================================================================`r`n"
        . "Generated Local : " FormatTime(, "yyyy-MM-dd HH:mm:ss") "`r`n"
        . "Generated UTC   : " FormatTime(A_NowUTC, "yyyy-MM-dd HH:mm:ss") " UTC`r`n"
        . "App Version     : v" UIConstants.APP_VERSION "`r`n"
        . "AutoHotkey      : v" A_AhkVersion " (" (A_IsCompiled ? "Compiled EXE" : "Script") ")`r`n"
        . "Windows OS      : " A_OSVersion " (Host: " A_ComputerName ")`r`n"
        . "NetworkSummary  : " epText "`r`n"
        . "Auto-Profile    : " autoState "`r`n"
        . "Host Bridge     : " bridgeLine "`r`n`r`n"
        . "--- LIVE STATUS SUMMARY ---`r`n"
        . StrReplace(summarySec, "`n", "`r`n") "`r`n`r`n"
        . "--- SANITIZED CONFIGURATION (.INI) ---`r`n"
        . (safeIni != "" ? safeIni : "(no configuration file found)") "`r`n"
        . "`r`n--- PERSISTENT ERROR & DIAGNOSTIC LOG TAIL ---`r`n"
        . DiagnosticLogger.GetRecentLogTail(12000) . "`r`n"

    for _, secVal in secrets {
        s := Trim(String(secVal))
        if (StrLen(s) >= 4)
            rpt := StrReplace(rpt, s, "[REDACTED]")
    }
    return rpt
}

ExportSanitizedDiagnostics(cfg, state := "", targetPath := "", showUi := true) {
    outPath := Trim(String(targetPath))
    defaultName := "PresenterSync_Diagnostics_" FormatTime(, "yyyyMMdd_HHmmss") ".txt"
    if (outPath = "" && showUi) {
        selected := FileSelect("S16", A_Desktop "\" defaultName, "Export Sanitized Diagnostics (Secrets Redacted)", "Diagnostic Bundle (*.txt)")
        if (selected = "")
            return {ok: false, cancelled: true, path: "", error: ""}
        outPath := selected
    }
    if (outPath = "")
        outPath := A_Temp "\" defaultName

    report := BuildSanitizedDiagnosticsReport(cfg, state)
    try {
        SplitPath(outPath, , &outDir)
        if (outDir != "" && !DirExist(outDir))
            DirCreate(outDir)
        if FileExist(outPath)
            FileDelete(outPath)
        f := FileOpen(outPath, "w", "UTF-8")
        if (!IsObject(f))
            return {ok: false, cancelled: false, path: outPath, error: "Could not open file for writing."}
        f.Write(report)
        f.Close()
    } catch as e {
        if (showUi)
            MsgBox("Failed to export diagnostics:`n`n" e.Message, "Export Diagnostics", "Icon! 0x40000")
        return {ok: false, cancelled: false, path: outPath, error: e.Message}
    }

    if (showUi) {
        TrayTip("Sanitized diagnostics exported (secrets redacted): " outPath, "PresenterSync Diagnostics", 1)
    }
    return {ok: true, cancelled: false, path: outPath, report: report, error: ""}
}

_HotkeyValidatorGuard(*) => false
_HotkeyValidatorNoop(*) => 0

IsValidHotkeySpec(hk) {
    s := Trim(String(hk))
    if (s = "" || StrLower(s) = "none")
        return true
    if RegExMatch(s, "^[*~$<>^!+#]+$")
        return false
    try {
        HotIf(_HotkeyValidatorGuard)
        Hotkey(s, _HotkeyValidatorNoop, "Off")
        HotIf()
        return true
    } catch {
        HotIf()
        return false
    }
}

SyncTelemetryBackendsFromConfig(cfg, state) {
    if (!IsObject(state))
        return
    if (state.HasOwnProp("colors"))
        state.colors := UIConstants.GetColorPalette(cfg.HudColorPreset, cfg.HasOwnProp("CustomLiveHex") ? cfg.CustomLiveHex : "107C10", cfg.HasOwnProp("CustomMutedHex") ? cfg.CustomMutedHex : "C42B1C")
    if (state.HasOwnProp("baseAlpha"))
        state.baseAlpha := cfg.OpacityLevel

    if (IsSet(UpdateCoreAudioWatchdogTimer))
        UpdateCoreAudioWatchdogTimer(cfg, state)
    if (IsSet(UpdateSafetyWatchdogTimer))
        UpdateSafetyWatchdogTimer(cfg, state)

    hadObsSession := (state.HasOwnProp("obsConnected") && state.obsConnected) || (state.HasOwnProp("obsWs") && IsObject(state.obsWs))
    if (state.HasOwnProp("obsTimerFn") && state.obsTimerFn)
        SetTimer(state.obsTimerFn, cfg.EnableWS ? -50 : 0)

    if (!cfg.EnableWS) {
        if (state.HasOwnProp("obsConnected"))
            state.obsConnected := false
        if (state.HasOwnProp("obsWs") && IsObject(state.obsWs)) {
            if (IsSet(SafeCloseWebSocketDeferred))
                SafeCloseWebSocketDeferred(state.obsWs, 40)
            else
                try state.obsWs.shutdown()
            state.obsWs := ""
        }
        if (state.HasOwnProp("streamTimerFn") && state.streamTimerFn)
            SetTimer(state.streamTimerFn, 0)
        if (state.HasOwnProp("sceneMarqueeTimerFn") && state.sceneMarqueeTimerFn)
            SetTimer(state.sceneMarqueeTimerFn, 0)
        if (state.HasOwnProp("streamState"))
            SyncStreamState(cfg, state, 0)
        if (state.HasOwnProp("vcamActive"))
            SyncVCamState(cfg, state, false)
        if (state.HasOwnProp("studioModeActive"))
            SyncStudioState(cfg, state, false)
        state.currentSceneName := "Scene"
        state.sceneList := []
        if (state.HasOwnProp("recState") && hadObsSession)
            SyncRecState(cfg, state, 0, -1, "obs")
    }

    if (!cfg.EnableZoom) {
        if (state.HasOwnProp("zoomConnected"))
            state.zoomConnected := false
        if (state.HasOwnProp("zoomLastMuted"))
            state.zoomLastMuted := -1
        if (state.HasOwnProp("zoomRecGraceUntil"))
            state.zoomRecGraceUntil := 0
        if (state.HasOwnProp("zoomSawRecControl"))
            state.zoomSawRecControl := false
        if (state.HasOwnProp("unreadChatCount"))
            SyncChatState(cfg, state, 0)
        if (state.HasOwnProp("recState"))
            SyncRecState(cfg, state, 0, -1, "conf")
    }

    if (state.HasOwnProp("zoomTimerFn") && state.zoomTimerFn)
        UpdateZoomMonitorTimer(cfg, state)
    if (state.HasOwnProp("relayTimerFn"))
        UpdateHostInternetRelay(cfg, state)
    if (cfg.HasOwnProp("EnableRemoteConnections")) {
        if (!cfg.EnableRemoteConnections) {
            StopHostCompanionBridge()
            if (state.HasOwnProp("relayWs") && IsObject(state.relayWs)) {
                if (IsSet(SafeCloseWebSocketDeferred))
                    SafeCloseWebSocketDeferred(state.relayWs, 40)
                else
                    try state.relayWs.shutdown()
                state.relayWs := ""
            }
            state.relayConnected := false
        } else if (IsSet(StartHostCompanionBridge) && (!IsSet(g_HostCompanionBridge) || !IsObject(g_HostCompanionBridge) || !g_HostCompanionBridge.running)) {
            StartHostCompanionBridge(cfg, state, cfg.HasOwnProp("BridgePort") ? cfg.BridgePort : 4456)
        }
    }
    if (state.HasOwnProp("MicGui") && IsObject(state.MicGui)) {
        RefreshHudAppearance(cfg, state)
        UpdateHudVisibility(cfg, state)
        ApplyHudClickThroughStyle(cfg, state)
        UpdateVoiceMeterTimer(cfg, state)
    }
    if (state.HasOwnProp("autoDodgeTimerFn") && state.autoDodgeTimerFn)
        UpdateAutoDodgeTimer(cfg, state)
    if (state.HasOwnProp("rebindHotkeysFn") && state.rebindHotkeysFn)
        try state.rebindHotkeysFn.Call()
    if (state.HasOwnProp("rebuildTrayFn") && state.rebuildTrayFn)
        try state.rebuildTrayFn.Call()
    if (state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn)
        try state.refreshHelpFn.Call()
}

ApplyControlCenterSettings(cfg, state := "", vals := "", writeRegistry := true, invalidKeys := "") {
    if (!IsObject(cfg))
        return false

    invalidCount := 0
    oldObsPw := cfg.HasOwnProp("obsPassword") ? String(cfg.obsPassword) : ""
    oldObsMic := cfg.HasOwnProp("targetMicName") ? String(cfg.targetMicName) : ""
    if IsObject(vals) {
        if vals.HasOwnProp("AudioRoutingMode") {
            rm := Integer(vals.AudioRoutingMode)
            if (rm >= 1 && rm <= 3) {
                cfg.AudioRoutingMode := rm
                cfg.Write("Settings", "AudioRoutingMode", rm)
            }
        }
        if vals.HasOwnProp("ConferencingApp") {
            cApp := NormalizeConferencingApp(vals.ConferencingApp)
            cfg.ConferencingApp := cApp
            cfg.Write("Settings", "ConferencingApp", cApp)
        }
        if vals.HasOwnProp("targetMicName") {
            mic := Trim(vals.targetMicName) != "" ? Trim(vals.targetMicName) : "Mic/Aux"
            cfg.targetMicName := mic
            cfg.Write("Settings", "TargetMicName", mic)
        }
        if vals.HasOwnProp("SecondaryAudioSources") {
            sec := Trim(String(vals.SecondaryAudioSources))
            cfg.SecondaryAudioSources := sec
            cfg.Write("Settings", "SecondaryAudioSources", sec)
        }
        if vals.HasOwnProp("UiaMuteKeywords") {
            umk := Trim(String(vals.UiaMuteKeywords))
            cfg.UiaMuteKeywords := umk
            cfg.Write("Settings", "UiaMuteKeywords", umk)
        }
        if vals.HasOwnProp("UiaUnmuteKeywords") {
            uuk := Trim(String(vals.UiaUnmuteKeywords))
            cfg.UiaUnmuteKeywords := uuk
            cfg.Write("Settings", "UiaUnmuteKeywords", uuk)
        }
        if vals.HasOwnProp("ShowVoiceMeter") {
            cfg.ShowVoiceMeter := !!vals.ShowVoiceMeter
            cfg.WriteBool("Settings", "ShowVoiceMeter", cfg.ShowVoiceMeter)
            if (!cfg.ShowVoiceMeter && IsObject(state))
                state.voicePeak := 0.0
        }
        if vals.HasOwnProp("EnableAudioCue") {
            cfg.EnableAudioCue := !!vals.EnableAudioCue
            cfg.WriteBool("Settings", "EnableAudioCue", cfg.EnableAudioCue)
        }
        if vals.HasOwnProp("EnableMuteToast") {
            cfg.EnableMuteToast := !!vals.EnableMuteToast
            cfg.WriteBool("Settings", "EnableMuteToast", cfg.EnableMuteToast)
        }
        for cProp in ["EnableCoreAudioFallback", "EnableOsMuteDriftWatchdog", "EnableForgottenRecordWatchdog", "EnableDeadMicWatchdog", "AutoRecordOnStreamDrop", "EnableLowDiskWatchdog", "AutoMuteOnLock", "AutoMuteOnMeetingEnd", "AutoMuteOnFirstObsConnect"] {
            if vals.HasOwnProp(cProp) {
                cfg.%cProp% := !!vals.%cProp%
                cfg.WriteBool("Settings", cProp, cfg.%cProp%)
            }
        }

        ; Tab 2: OBS & Stream
        if vals.HasOwnProp("EnableWS") {
            cfg.EnableWS := !!vals.EnableWS
            cfg.WriteBool("Settings", "EnableWS", cfg.EnableWS)
        }
        if vals.HasOwnProp("EnableZoom") {
            cfg.EnableZoom := !!vals.EnableZoom
            cfg.WriteBool("Settings", "EnableZoom", cfg.EnableZoom)
        }
        if vals.HasOwnProp("obsPassword") {
            cfg.obsPassword := vals.obsPassword
            cfg.Write("Settings", "ObsPassword", cfg.obsPassword)
        }
        if vals.HasOwnProp("StandbySceneName") {
            brb := Trim(String(vals.StandbySceneName))
            cfg.StandbySceneName := (brb != "") ? brb : "BRB"
            cfg.Write("Settings", "StandbySceneName", cfg.StandbySceneName)
        }
        if vals.HasOwnProp("ShowStreamHud") {
            cfg.ShowStreamHud := !!vals.ShowStreamHud
            cfg.WriteBool("Settings", "ShowStreamHud", cfg.ShowStreamHud)
        }
        if vals.HasOwnProp("ShowRecTimer") {
            cfg.ShowRecTimer := !!vals.ShowRecTimer
            cfg.WriteBool("Settings", "ShowRecTimer", cfg.ShowRecTimer)
        }

        ; Tab 3: Pointer & Clicker
        if vals.HasOwnProp("PointerMode") {
            pm := vals.PointerMode
            if (pm = "Full PPT + Mute" || pm = 1) {
                cfg.EnablePPT := true
                cfg.EnableMicOnly := false
            } else if (pm = "Pointer Mute Only" || pm = "Mute Only" || pm = 2) {
                cfg.EnablePPT := false
                cfg.EnableMicOnly := true
            } else {
                cfg.EnablePPT := false
                cfg.EnableMicOnly := false
            }
            cfg.WriteBool("Settings", "EnablePPT", cfg.EnablePPT)
            cfg.WriteBool("Settings", "EnableMicOnly", cfg.EnableMicOnly)
        }
        if vals.HasOwnProp("EnablePushToMute") {
            cfg.EnablePushToMute := !!vals.EnablePushToMute
            cfg.WriteBool("Pointer", "EnablePushToMute", cfg.EnablePushToMute)
        }
        if vals.HasOwnProp("EnablePushToTalk") {
            cfg.EnablePushToTalk := !!vals.EnablePushToTalk
            if (cfg.EnablePushToTalk && cfg.EnablePushToMute) {
                cfg.EnablePushToMute := false
                cfg.WriteBool("Pointer", "EnablePushToMute", false)
            }
            cfg.WriteBool("Pointer", "EnablePushToTalk", cfg.EnablePushToTalk)
        }
        if vals.HasOwnProp("EnablePointerTransition") {
            cfg.EnablePointerTransition := !!vals.EnablePointerTransition
            cfg.WriteBool("Settings", "EnablePointerTransition", cfg.EnablePointerTransition)
        }
        for pKey in ["CatchArrows", "CatchPg", "CatchSpace", "CatchEnter", "CatchTab", "CatchEsc"] {
            if vals.HasOwnProp(pKey) {
                cfg.%pKey% := !!vals.%pKey%
                cfg.WriteBool("Pointer", pKey, cfg.%pKey%)
            }
        }

        ; Tab 4: HUD & Appearance
        if vals.HasOwnProp("IndicatorScale") {
            sc := Float(vals.IndicatorScale)
            if (sc >= 0.25 && sc <= 5.0) {
                cfg.IndicatorScale := sc
                cfg.Write("Settings", "IndicatorScale", sc)
            }
        }
        if vals.HasOwnProp("OpacityLevel") {
            op := Integer(vals.OpacityLevel)
            if (op >= 50 && op <= 255) {
                cfg.OpacityLevel := op
                cfg.Write("Settings", "OpacityLevel", op)
            }
        }
        if vals.HasOwnProp("CustomLiveHex") {
            cfg.CustomLiveHex := NormalizeColorHex(vals.CustomLiveHex, cfg.CustomLiveHex)
            cfg.Write("Settings", "CustomLiveHex", cfg.CustomLiveHex)
        }
        if vals.HasOwnProp("CustomMutedHex") {
            cfg.CustomMutedHex := NormalizeColorHex(vals.CustomMutedHex, cfg.CustomMutedHex)
            cfg.Write("Settings", "CustomMutedHex", cfg.CustomMutedHex)
        }
        if vals.HasOwnProp("HudColorPreset") {
            pName := NormalizeHudColorPreset(vals.HudColorPreset)
            cfg.HudColorPreset := pName
            cfg.Write("Settings", "HudColorPreset", pName)
        }
        if vals.HasOwnProp("ThemeMode") {
            tm := (vals.ThemeMode = "Dark" || vals.ThemeMode = "Light") ? vals.ThemeMode : "System"
            cfg.ThemeMode := tm
            cfg.Write("Settings", "ThemeMode", tm)
            Theme.SetMode(tm)
        }
        for bProp in ["ShowIndicator", "ShowExtraHuds", "ShowRow2RecChatHud", "ShowRow3StudioSceneHud", "ShowSecondaryMicHud", "ShowText", "MonoIcon", "SleekCorners", "AggressivePulse", "EnableHudClickActions", "EnableMagneticSnap", "HudAutoDodge", "HudClickThrough", "ExcludeFromCapture", "ExcludeSecondaryFromCapture", "ConfirmBeforeStopRecording", "ExitBrbSafelyMuted"] {
            if vals.HasOwnProp(bProp) {
                cfg.%bProp% := !!vals.%bProp%
                cfg.WriteBool("Settings", bProp, cfg.%bProp%)
            }
        }

        ; Tab 5: Remote Companion
        if vals.HasOwnProp("RemoteNetworkMode") {
            rMode := (vals.RemoteNetworkMode = "Internet" || InStr(vals.RemoteNetworkMode, "Internet")) ? "Internet" : "LAN"
            cfg.RemoteNetworkMode := rMode
            cfg.Write("Settings", "RemoteNetworkMode", rMode)
        }
        if vals.HasOwnProp("RelayBaseUrl") {
            rUrl := IsSet(NormalizeRelayBaseUrl) ? NormalizeRelayBaseUrl(vals.RelayBaseUrl) : (Trim(String(vals.RelayBaseUrl)) != "" ? RTrim(Trim(String(vals.RelayBaseUrl)), "/") : "https://ntfy.sh")
            cfg.RelayBaseUrl := rUrl
            cfg.Write("Settings", "RelayBaseUrl", rUrl)
        }
        if vals.HasOwnProp("QuickNudgePresets") {
            qn := Trim(String(vals.QuickNudgePresets))
            cfg.QuickNudgePresets := (qn != "") ? qn : "2 min left|Wrap up|Check Mic|Q&A"
            cfg.Write("Settings", "QuickNudgePresets", cfg.QuickNudgePresets)
        }
        if vals.HasOwnProp("EnableRelayEncryption") {
            cfg.EnableRelayEncryption := !!vals.EnableRelayEncryption
            cfg.WriteBool("Settings", "EnableRelayEncryption", cfg.EnableRelayEncryption)
        }
        if vals.HasOwnProp("EnableRemoteConnections") {
            cfg.EnableRemoteConnections := !!vals.EnableRemoteConnections
            cfg.WriteBool("Settings", "EnableRemoteConnections", cfg.EnableRemoteConnections)
        }
        if vals.HasOwnProp("IncludeVirtualAdapters") {
            cfg.IncludeVirtualAdapters := !!vals.IncludeVirtualAdapters
            cfg.WriteBool("Settings", "IncludeVirtualAdapters", cfg.IncludeVirtualAdapters)
        }

        ; Uniform hotkey validation & persistence (Tabs 1, 2, 3, 6)
        for hkSpec in [
            { prop: "ZoomMuteHotkey", key: "ZoomMuteHotkey", label: "Zoom Mute Hotkey" },
            { prop: "TeamsMuteHotkey", key: "TeamsMuteHotkey", label: "Teams Mute Hotkey" },
            { prop: "MeetMuteHotkey", key: "MeetMuteHotkey", label: "Meet Mute Hotkey" },
            { prop: "ZoomRecHotkey", key: "ZoomRecHotkey", label: "Conferencing Rec Hotkey" },
            { prop: "ZoomPauseHotkey", key: "ZoomPauseHotkey", label: "Conferencing Pause Hotkey" },
            { prop: "ObsMuteHotkey", key: "ObsHotkey", label: "OBS Mute Hotkey" },
            { prop: "ObsRecHotkey", key: "ObsRecHotkey", label: "OBS Rec Hotkey" },
            { prop: "ObsPauseHotkey", key: "ObsPauseHotkey", label: "OBS Pause Hotkey" },
            { prop: "ObsTransitionHotkey", key: "ObsTransitionHotkey", label: "OBS Transition Hotkey" },
            { prop: "HwMuteHotkey", key: "HwMuteHotkey", label: "Clicker Mute Button" },
            { prop: "HwTransitionHotkey", key: "HwTransitionHotkey", label: "Clicker OBS Transition Button" },
            { prop: "PptHotkey", key: "PptHotkey", label: "Cycle Pointer Mode" },
            { prop: "WsHotkey", key: "WsHotkey", label: "Toggle OBS Sync" },
            { prop: "ZoomHotkey", key: "ZoomHotkey", label: "Toggle Conf Monitor" },
            { prop: "IndHotkey", key: "IndHotkey", label: "Show / Hide HUD" },
            { prop: "SuspendHotkey", key: "SuspendHotkey", label: "Suspend All Hotkeys" },
            { prop: "ExitHotkey", key: "ExitHotkey", label: "Exit Application" },
            { prop: "RemoteInfoHotkey", key: "RemoteInfoHotkey", label: "Remote Setup & QR Info" }
        ] {
            if vals.HasOwnProp(hkSpec.prop) {
                rawHk := Trim(String(vals.%hkSpec.prop%))
                if (!IsValidHotkeySpec(rawHk)) {
                    invalidCount += 1
                    if IsObject(invalidKeys)
                        invalidKeys.Push({ prop: hkSpec.prop, label: hkSpec.label, value: rawHk })
                    continue
                }
                normHk := (rawHk = "" || StrLower(rawHk) = "none") ? "None" : rawHk
                cfg.%hkSpec.prop% := normHk
                cfg.Write("Settings", hkSpec.key, normHk)
            }
        }
        if vals.HasOwnProp("StartWithWindows") {
            SetStartWithWindows(cfg, "", !!vals.StartWithWindows, writeRegistry)
        }
        if vals.HasOwnProp("AutoCheckUpdates") {
            cfg.AutoCheckUpdates := !!vals.AutoCheckUpdates
            cfg.WriteBool("Settings", "AutoCheckUpdates", cfg.AutoCheckUpdates)
        }
    }

    if (IsSet(ApplyHostObsCredentialsChange))
        ApplyHostObsCredentialsChange(cfg, state, oldObsPw, oldObsMic)
    SyncTelemetryBackendsFromConfig(cfg, state)
    return (invalidCount == 0)
}

_AddCCCaptureBtn(guiObj, x, y, w, h, btnText, edCtrl, capTitle, allowMods := true) {
    guiObj.SetFont("s8.5 w600 norm", Theme.UiFont)
    btn := guiObj.Add("Button", Format("x{} y{} w{} h{}", x, y, w, h), btnText)
    Theme.RegisterControl(guiObj, btn, "Button", "tabButton")
    btn.OnEvent("Click", (*) => OpenShortcutCaptureDialog(edCtrl.Value, (newHk) => (edCtrl.Value := newHk), capTitle, allowMods, true))
    guiObj.SetFont("s9 w400 norm", Theme.UiFont)
    return btn
}

ShowControlCenterWindow(cfg, state := "", *) {
    existing := Theme.FocusExistingWindow("PresenterSync - Control Center")
    if IsObject(existing)
        return existing
    if (IsObject(cfg) && cfg.HasOwnProp("KioskPin") && Trim(cfg.KioskPin) != "") {
        ib := InputBox("Enter Kiosk PIN to open Control Center:", "PresenterSync Kiosk Lock", "Password w260 h120")
        if (ib.Result != "OK" || Trim(ib.Value) !== Trim(cfg.KioskPin)) {
            if (IsSet(ShowCaptureSafeMicroToast))
                try ShowCaptureSafeMicroToast("Incorrect Kiosk PIN", 2000)
            return ""
        }
    }

    Theme.AcquireSuspend()

    ccGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "PresenterSync - Control Center")
    ccGui._closed := false
    ccGui.MarginX := 16
    ccGui.MarginY := 14
    Theme.ApplyToWindow(ccGui)
    Theme.NamedWindows["PresenterSync - Control Center"] := ccGui

    tabNames := ["Audio & Conf", "OBS & Stream", "Pointer", "HUD & Theme", "Remote", "Profiles & Sys"]
    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    tabs := ccGui.Add("Tab2", "x14 y12 w692 h486 +0x0400", tabNames)
    tabs._tabNames := tabNames
    Theme.RegisterControl(ccGui, tabs, "Tab")

    ; ==========================================================================
    ; TAB 1: AUDIO & CONFERENCING
    ; ==========================================================================
    tabs.UseTab(1)
    ccGui.SetFont("s11 w700 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y60 w650", "Audio Routing Mode, Conferencing Platform & Acoustic Feedback"), "Text", "tabText")

    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y96 w210", "Audio Routing Profile:"), "Text", "tabText")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    routingLabels := [
        "1: Pro OBS Setup (VB-Cable)",
        "2: Standard Direct Mic (Conferencing-Only)",
        "3: Dual App Sync (OBS + Conferencing)"
    ]
    ddlRouting := ccGui.Add("DropDownList", "x250 y92 w430 Choose" (cfg.AudioRoutingMode >= 1 && cfg.AudioRoutingMode <= 3 ? cfg.AudioRoutingMode : 1), routingLabels)
    Theme.RegisterControl(ccGui, ddlRouting, "DropDownList")

    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y134 w210", "Conferencing Application:"), "Text", "tabText")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    confApps := GetConferencingAppNames()
    confIdx := 1
    for i, cName in confApps {
        if (NormalizeConferencingApp(cfg.ConferencingApp) = cName)
            confIdx := i
    }
    ddlConfApp := ccGui.Add("DropDownList", "x250 y130 w210 Choose" confIdx, confApps)
    Theme.RegisterControl(ccGui, ddlConfApp, "DropDownList")

    btnWizard := ccGui.Add("Button", "x472 y128 w208 h28", "Run Audio Setup Wizard...")
    Theme.RegisterControl(ccGui, btnWizard, "Button", "tabButton")
    btnWizard.OnEvent("Click", (*) => PromptForSetup(cfg, false))

    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y172 w210", "Target OBS Audio Source:"), "Text", "tabText")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    BuildMicInputChoices(stObj, curText) {
        choices := []
        seen := Map()
        if (IsObject(stObj)) {
            src := (stObj.HasOwnProp("obsAudioInputs") && IsObject(stObj.obsAudioInputs) && stObj.obsAudioInputs.Length > 0)
                ? stObj.obsAudioInputs
                : ((stObj.HasOwnProp("obsInputs") && IsObject(stObj.obsInputs)) ? stObj.obsInputs : [])
            for _, item in src {
                clean := Trim(String(item))
                if (clean != "" && !seen.Has(clean)) {
                    seen[clean] := true
                    choices.Push(clean)
                }
            }
        }
        cleanCur := Trim(String(curText))
        if (cleanCur != "" && !seen.Has(cleanCur))
            choices.Push(cleanCur)
        return choices
    }
    cbTargetMic := ccGui.Add("ComboBox", "x250 y168 w310", BuildMicInputChoices(state, cfg.targetMicName))
    cbTargetMic.Text := cfg.targetMicName
    Theme.RegisterControl(ccGui, cbTargetMic, "DropDownList")
    btnRefreshInputs := ccGui.Add("Button", "x568 y167 w112 h28", "Refresh Inputs")
    Theme.RegisterControl(ccGui, btnRefreshInputs, "Button", "tabButton")
    btnRefreshInputs.OnEvent("Click", (*) => (IsObject(state) && state.HasOwnProp("obsWs") && IsObject(state.obsWs) ? RequestObsInputList(state.obsWs, state) : 0))
    RefreshTargetMicCombo(*) {
        if (ccGui._closed)
            return
        savedText := cbTargetMic.Text
        cbTargetMic.Delete()
        newChoices := BuildMicInputChoices(state, savedText)
        if (newChoices.Length > 0)
            cbTargetMic.Add(newChoices)
        cbTargetMic.Text := savedText
    }
    prevRefreshInputsFn := (IsObject(state) && state.HasOwnProp("refreshInputsFn")) ? state.refreshInputsFn : ""
    if (IsObject(state))
        state.refreshInputsFn := RefreshTargetMicCombo

    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y212 w210", "Zoom / Teams / Meet Mute Keys:"), "Text", "tabText")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    edZoomMute := ccGui.Add("Edit", "x250 y208 w76 h26", cfg.ZoomMuteHotkey)
    edTeamsMute := ccGui.Add("Edit", "x396 y208 w76 h26", cfg.TeamsMuteHotkey)
    edMeetMute := ccGui.Add("Edit", "x542 y208 w76 h26", cfg.MeetMuteHotkey)
    Theme.RegisterControl(ccGui, edZoomMute, "Edit")
    Theme.RegisterControl(ccGui, edTeamsMute, "Edit")
    Theme.RegisterControl(ccGui, edMeetMute, "Edit")
    _AddCCCaptureBtn(ccGui, 330, 208, 58, 26, "Capture", edZoomMute, "Capture Zoom Mute Shortcut")
    _AddCCCaptureBtn(ccGui, 476, 208, 58, 26, "Capture", edTeamsMute, "Capture Teams Mute Shortcut")
    _AddCCCaptureBtn(ccGui, 622, 208, 58, 26, "Capture", edMeetMute, "Capture Meet Mute Shortcut")
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x250 y236 w138", "Zoom (e.g. !a)"), "Text", "tabMuted")
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x396 y236 w138", "Teams (e.g. ^+m)"), "Text", "tabMuted")
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x542 y236 w138", "Meet (e.g. ^d)"), "Text", "tabMuted")

    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y268 w210", "Conferencing Rec / Pause Keys:"), "Text", "tabText")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    edZoomRec := ccGui.Add("Edit", "x250 y264 w94 h26", cfg.ZoomRecHotkey)
    edZoomPause := ccGui.Add("Edit", "x470 y264 w94 h26", cfg.ZoomPauseHotkey)
    Theme.RegisterControl(ccGui, edZoomRec, "Edit")
    Theme.RegisterControl(ccGui, edZoomPause, "Edit")
    _AddCCCaptureBtn(ccGui, 348, 264, 112, 26, "Capture Keystroke", edZoomRec, "Capture Zoom Rec Shortcut")
    _AddCCCaptureBtn(ccGui, 568, 264, 112, 26, "Capture Keystroke", edZoomPause, "Capture Zoom Pause Shortcut")

    chkVoiceMeter := ccGui.Add("Checkbox", "x32 y312 w310 h22" (cfg.ShowVoiceMeter ? " Checked" : ""), "Show Live CoreAudio Voice Activity Bar on LIVE Pill")
    chkAudioCue := ccGui.Add("Checkbox", "x360 y312 w320 h22" (cfg.EnableAudioCue ? " Checked" : ""), "Play Two-Tone Acoustic Chime on Mute / Unmute")
    chkMuteToast := ccGui.Add("Checkbox", "x32 y338 w310 h22" (cfg.EnableMuteToast ? " Checked" : ""), "Show Brief Cursor Tooltip Toast on Mute Change")
    chkAutoMuteLock := ccGui.Add("Checkbox", "x360 y338 w330 h22" (cfg.AutoMuteOnLock ? " Checked" : ""), "Auto-Mute on Windows Lock")
    chkCoreAudioFallback := ccGui.Add("Checkbox", "x32 y364 w310 h22" (cfg.EnableCoreAudioFallback ? " Checked" : ""), "CoreAudio OS-Level Endpoint Mute Fallback")
    chkOsMuteDrift := ccGui.Add("Checkbox", "x360 y364 w330 h22" (cfg.EnableOsMuteDriftWatchdog ? " Checked" : ""), "Detect Hardware / OS Mic Mute Drift while LIVE")
    Theme.RegisterControl(ccGui, chkCoreAudioFallback, "Checkbox", "tabText")
    Theme.RegisterControl(ccGui, chkOsMuteDrift, "Checkbox", "tabText")
    chkForgottenRec := ccGui.Add("Checkbox", "x32 y390 w310 h22" (cfg.EnableForgottenRecordWatchdog ? " Checked" : ""), "Nudge if Presenting LIVE but Not Recording")
    chkDeadMic := ccGui.Add("Checkbox", "x360 y390 w330 h22" (cfg.EnableDeadMicWatchdog ? " Checked" : ""), "Warn if Mic is LIVE but Silent for 45s")
    chkAutoMuteMeetingEnd := ccGui.Add("Checkbox", "x32 y416 w310 h22" (cfg.AutoMuteOnMeetingEnd ? " Checked" : ""), "Auto-Mute on Meeting End")
    chkAutoMuteFirstObs := ccGui.Add("Checkbox", "x360 y416 w330 h22" (cfg.AutoMuteOnFirstObsConnect ? " Checked" : ""), "Auto-Mute on First OBS Connect")
    Theme.RegisterControl(ccGui, chkAutoMuteLock, "Checkbox", "tabText")
    Theme.RegisterControl(ccGui, chkAutoMuteMeetingEnd, "Checkbox", "tabText")
    Theme.RegisterControl(ccGui, chkAutoMuteFirstObs, "Checkbox", "tabText")
    Theme.RegisterControl(ccGui, chkForgottenRec, "Checkbox", "tabText")
    Theme.RegisterControl(ccGui, chkDeadMic, "Checkbox", "tabText")
    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y446 w210", "Secondary OBS Mics (comma):"), "Text", "tabText")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    edSecondaryAudioSources := ccGui.Add("Edit", "x250 y442 w430 h26", cfg.HasOwnProp("SecondaryAudioSources") ? cfg.SecondaryAudioSources : "")
    Theme.RegisterControl(ccGui, edSecondaryAudioSources, "Edit")
    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y473 w104", "UIA Mute Words:"), "Text", "tabText")
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x352 y473 w118", "UIA Unmute Words:"), "Text", "tabText")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    edUiaMuteKeywords := ccGui.Add("Edit", "x138 y470 w204 h24", cfg.HasOwnProp("UiaMuteKeywords") ? cfg.UiaMuteKeywords : "")
    edUiaUnmuteKeywords := ccGui.Add("Edit", "x472 y470 w208 h24", cfg.HasOwnProp("UiaUnmuteKeywords") ? cfg.UiaUnmuteKeywords : "")
    Theme.RegisterControl(ccGui, edUiaMuteKeywords, "Edit")
    Theme.RegisterControl(ccGui, edUiaUnmuteKeywords, "Edit")
    Theme.RegisterControl(ccGui, chkVoiceMeter, "Checkbox", "tabText")
    Theme.RegisterControl(ccGui, chkAudioCue, "Checkbox", "tabText")
    Theme.RegisterControl(ccGui, chkMuteToast, "Checkbox", "tabText")

    ; ==========================================================================
    ; TAB 2: OBS & LIVE STREAM
    ; ==========================================================================
    tabs.UseTab(2)
    ccGui.SetFont("s11 w700 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y60 w650", "OBS Studio WebSocket v5, Live Stream HUD & Fallback Shortcuts"), "Text", "tabText")

    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    chkEnableWS := ccGui.Add("Checkbox", "x32 y98 w310 h24" (cfg.EnableWS ? " Checked" : ""), "Enable OBS WebSocket v5 Live Sync (Port 4455)")
    chkEnableZoom := ccGui.Add("Checkbox", "x360 y98 w320 h24" (cfg.EnableZoom ? " Checked" : ""), "Enable Conferencing UIA Background Monitoring")
    Theme.RegisterControl(ccGui, chkEnableWS, "Checkbox", "tabText")
    Theme.RegisterControl(ccGui, chkEnableZoom, "Checkbox", "tabText")

    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y140 w210", "OBS WebSocket Password:"), "Text", "tabText")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    edObsPass := ccGui.Add("Edit", "x250 y136 w430 h26 Password", cfg.obsPassword)
    Theme.RegisterControl(ccGui, edObsPass, "Edit")

    chkStreamHud := ccGui.Add("Checkbox", "x32 y182 w320 h24" (cfg.ShowStreamHud ? " Checked" : ""), "Show 4th-Row Live Stream && Virtual Camera HUD")
    chkRecTimer := ccGui.Add("Checkbox", "x360 y182 w320 h24" (cfg.ShowRecTimer ? " Checked" : ""), "Show Live Elapsed Recording / Stream Timer")
    Theme.RegisterControl(ccGui, chkStreamHud, "Checkbox", "tabText")
    Theme.RegisterControl(ccGui, chkRecTimer, "Checkbox", "tabText")

    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y228 w210", "OBS Mute Fallback Shortcut:"), "Text", "tabText")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    edObsMute := ccGui.Add("Edit", "x250 y224 w306 h26", cfg.ObsMuteHotkey)
    Theme.RegisterControl(ccGui, edObsMute, "Edit")
    _AddCCCaptureBtn(ccGui, 562, 224, 118, 26, "Capture Keystroke", edObsMute, "Capture OBS Mute Shortcut")

    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y268 w210", "OBS Start/Stop Rec Shortcut:"), "Text", "tabText")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    edObsRec := ccGui.Add("Edit", "x250 y264 w306 h26", cfg.ObsRecHotkey)
    Theme.RegisterControl(ccGui, edObsRec, "Edit")
    _AddCCCaptureBtn(ccGui, 562, 264, 118, 26, "Capture Keystroke", edObsRec, "Capture OBS Rec Shortcut")

    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y308 w210", "OBS Pause Rec Shortcut:"), "Text", "tabText")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    edObsPause := ccGui.Add("Edit", "x250 y304 w306 h26", cfg.ObsPauseHotkey)
    Theme.RegisterControl(ccGui, edObsPause, "Edit")
    _AddCCCaptureBtn(ccGui, 562, 304, 118, 26, "Capture Keystroke", edObsPause, "Capture OBS Pause Shortcut")

    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y348 w210", "Standby (BRB) OBS Scene:"), "Text", "tabText")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    edStandbyScene := ccGui.Add("Edit", "x250 y344 w430 h26", cfg.StandbySceneName)
    Theme.RegisterControl(ccGui, edStandbyScene, "Edit")

    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y388 w210", "OBS Transition Shortcut (Fallback):"), "Text", "tabText")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    edObsTransition := ccGui.Add("Edit", "x250 y384 w306 h26", cfg.ObsTransitionHotkey)
    Theme.RegisterControl(ccGui, edObsTransition, "Edit")
    _AddCCCaptureBtn(ccGui, 562, 384, 118, 26, "Capture Keystroke", edObsTransition, "Capture OBS Transition Shortcut")

    chkAutoRecDrop := ccGui.Add("Checkbox", "x32 y428 w310 h24" (cfg.AutoRecordOnStreamDrop ? " Checked" : ""), "Auto-Start Local Backup Recording on Stream Drop")
    chkLowDisk := ccGui.Add("Checkbox", "x360 y428 w320 h24" (cfg.EnableLowDiskWatchdog ? " Checked" : ""), "Warn on Low Disk Space While Recording")
    chkConfirmStopRec := ccGui.Add("Checkbox", "x32 y460 w420 h24" (cfg.ConfirmBeforeStopRecording ? " Checked" : ""), "Require 2nd-Tap Confirm (3s) Before Stopping Recording")
    Theme.RegisterControl(ccGui, chkAutoRecDrop, "Checkbox", "tabText")
    Theme.RegisterControl(ccGui, chkLowDisk, "Checkbox", "tabText")
    Theme.RegisterControl(ccGui, chkConfirmStopRec, "Checkbox", "tabText")

    ; ==========================================================================
    ; TAB 3: POINTER & CLICKER
    ; ==========================================================================
    tabs.UseTab(3)
    ccGui.SetFont("s11 w700 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y60 w650", "Hardware Presentation Clicker, Cough Hold-to-Mute & Slide Routing"), "Text", "tabText")

    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y98 w210", "Active Pointer Mode:"), "Text", "tabText")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    ptrIdx := cfg.EnablePPT ? 1 : (cfg.EnableMicOnly ? 2 : 3)
    ddlPointerMode := ccGui.Add("DropDownList", "x250 y94 w430 Choose" ptrIdx, ["Full PPT + Mute", "Pointer Mute Only", "OFF"])
    Theme.RegisterControl(ccGui, ddlPointerMode, "DropDownList")

    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y138 w210", "Clicker Mute Button Key:"), "Text", "tabText")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    edHwMute := ccGui.Add("Edit", "x250 y134 w192 h26", cfg.HwMuteHotkey)
    Theme.RegisterControl(ccGui, edHwMute, "Edit")

    btnCapMute := ccGui.Add("Button", "x448 y132 w122 h28", "Capture Keystroke")
    btnPtrTester := ccGui.Add("Button", "x575 y132 w105 h28", "Clicker Tester")
    Theme.RegisterControl(ccGui, btnCapMute, "Button", "tabButton")
    Theme.RegisterControl(ccGui, btnPtrTester, "Button", "tabButton")
    btnCapMute.OnEvent("Click", (*) => OpenPointerKeyCaptureDialog(edHwMute.Value, "Use Key", (newKey) => (edHwMute.Value := newKey)))
    btnPtrTester.OnEvent("Click", (*) => ShowPointerTester())

    chkPushToMute := ccGui.Add("Checkbox", "x32 y178 w310 h24" (cfg.EnablePushToMute ? " Checked" : ""), "Cough / Push-to-Mute (Hold >= 350ms)")
    chkPushToTalk := ccGui.Add("Checkbox", "x360 y178 w320 h24" (cfg.EnablePushToTalk ? " Checked" : ""), "Push-to-Talk Mode (Hold to Unmute)")
    Theme.RegisterControl(ccGui, chkPushToMute, "Checkbox", "tabText")
    Theme.RegisterControl(ccGui, chkPushToTalk, "Checkbox", "tabText")
    chkPushToMute.OnEvent("Click", (*) => (chkPushToMute.Value ? (chkPushToTalk.Value := 0) : 0))
    chkPushToTalk.OnEvent("Click", (*) => (chkPushToTalk.Value ? (chkPushToMute.Value := 0) : 0))

    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y218 w648", "PowerPoint Background Slide Intercept Keys (Active in Full PPT + Mute Mode):"), "Text", "tabText")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    chkArrows := ccGui.Add("Checkbox", "x32 y248 w310 h24" (cfg.CatchArrows ? " Checked" : ""), "Arrow Keys (Up / Down / Left / Right)")
    chkPg := ccGui.Add("Checkbox", "x360 y248 w320 h24" (cfg.CatchPg ? " Checked" : ""), "PageUp / PageDown (Standard Clickers)")
    chkSpace := ccGui.Add("Checkbox", "x32 y280 w310 h24" (cfg.CatchSpace ? " Checked" : ""), "Spacebar (Advance Slide)")
    chkEnter := ccGui.Add("Checkbox", "x360 y280 w320 h24" (cfg.CatchEnter ? " Checked" : ""), "Enter Key (Advance / Activate Link)")
    chkTab := ccGui.Add("Checkbox", "x32 y312 w310 h24" (cfg.CatchTab ? " Checked" : ""), "Tab Key (Cycle Slide Hyperlinks)")
    chkEsc := ccGui.Add("Checkbox", "x360 y312 w320 h24" (cfg.CatchEsc ? " Checked" : ""), "Escape Key (End Slide Show)")
    for cCtrl in [chkArrows, chkPg, chkSpace, chkEnter, chkTab, chkEsc]
        Theme.RegisterControl(ccGui, cCtrl, "Checkbox", "tabText")

    chkPointerTransition := ccGui.Add("Checkbox", "x32 y352 w380 h24" (cfg.EnablePointerTransition ? " Checked" : ""), "Enable Pointer OBS Scene Transition (Tap Button to Cut)")
    Theme.RegisterControl(ccGui, chkPointerTransition, "Checkbox", "tabText")

    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y388 w210", "Clicker Transition Button Key:"), "Text", "tabText")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    edHwTransition := ccGui.Add("Edit", "x250 y384 w306 h26", cfg.HwTransitionHotkey)
    Theme.RegisterControl(ccGui, edHwTransition, "Edit")
    btnCapTransition := ccGui.Add("Button", "x562 y382 w118 h28", "Capture Keystroke")
    Theme.RegisterControl(ccGui, btnCapTransition, "Button", "tabButton")
    btnCapTransition.OnEvent("Click", (*) => OpenPointerKeyCaptureDialog(edHwTransition.Value, "Use Key", (newKey) => (edHwTransition.Value := newKey), "Edit Pointer OBS Transition Button", "Presentation Clicker OBS Transition Button"))

    ; ==========================================================================
    ; TAB 4: HUD & APPEARANCE
    ; ==========================================================================
    tabs.UseTab(4)
    ccGui.SetFont("s11 w700 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y60 w650", "HUD Scale, Color Palettes, Magnetic Snapping & Smart Visibility"), "Text", "tabText")

    scaleValues := [0.25, 0.5, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0, 5.0]
    scaleLabels := ["Tiny (0.25x)", "Small (0.5x)", "Normal (1.0x)", "Medium (1.25x)", "Large (1.5x)", "Huge (2.0x)", "Massive (2.5x)", "Colossal (3.0x)", "Gigantic (5.0x)"]
    scIdx := 3
    for idx, sv in scaleValues {
        if (Abs(cfg.IndicatorScale - sv) < 0.01)
            scIdx := idx
    }
    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y96 w130", "Indicator Scale:"), "Text", "tabText")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    ddlScale := ccGui.Add("DropDownList", "x165 y92 w175 Choose" scIdx, scaleLabels)
    Theme.RegisterControl(ccGui, ddlScale, "DropDownList")

    opIdx := (cfg.OpacityLevel == UIConstants.OPACITY_SOLID) ? 1 : ((cfg.OpacityLevel == UIConstants.OPACITY_GHOST) ? 3 : 2)
    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x360 y96 w130", "Transparency:"), "Text", "tabText")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    ddlOpacity := ccGui.Add("DropDownList", "x495 y92 w185 Choose" opIdx, ["Solid (100%)", "Frosted (85%)", "Ghost (50%)"])
    Theme.RegisterControl(ccGui, ddlOpacity, "DropDownList")

    palNames := GetHudColorPresetNames()
    palIdx := 1
    for idx, pName in palNames {
        if (StrLower(cfg.HudColorPreset) = StrLower(pName))
            palIdx := idx
    }
    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y134 w130", "Color Palette:"), "Text", "tabText")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    ddlPalette := ccGui.Add("DropDownList", "x165 y130 w175 Choose" palIdx, palNames)
    Theme.RegisterControl(ccGui, ddlPalette, "DropDownList")

    themeModes := ["System", "Dark", "Light"]
    tmIdx := (cfg.ThemeMode = "Dark") ? 2 : ((cfg.ThemeMode = "Light") ? 3 : 1)
    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x360 y134 w130", "Window Theme:"), "Text", "tabText")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    ddlTheme := ccGui.Add("DropDownList", "x495 y130 w185 Choose" tmIdx, themeModes)
    Theme.RegisterControl(ccGui, ddlTheme, "DropDownList")

    chkShowInd := ccGui.Add("Checkbox", "x32 y174 w310 h24" (cfg.ShowIndicator ? " Checked" : ""), "Show Primary Mute HUD Indicator")
    chkShowExtra := ccGui.Add("Checkbox", "x360 y174 w320 h24" (cfg.ShowExtraHuds ? " Checked" : ""), "Show Extra Telemetry HUDs (Rows 2-4)")
    chkShowText := ccGui.Add("Checkbox", "x32 y204 w310 h24" (cfg.ShowText ? " Checked" : ""), "Show Text Labels Next to Icons")
    chkMonoIcon := ccGui.Add("Checkbox", "x360 y204 w320 h24" (cfg.MonoIcon ? " Checked" : ""), "Use Monochromatic White Icons")
    chkSleek := ccGui.Add("Checkbox", "x32 y234 w310 h24" (cfg.SleekCorners ? " Checked" : ""), "Use Sleek Rounded-Square Corners")
    chkPulse := ccGui.Add("Checkbox", "x360 y234 w320 h24" (cfg.AggressivePulse ? " Checked" : ""), "Aggressive Breathing Pulse When Muted")
    chkClickPills := ccGui.Add("Checkbox", "x32 y264 w310 h24" (cfg.EnableHudClickActions ? " Checked" : ""), "Interactive Clickable HUD Pills (Quick Actions)")
    chkMagSnap := ccGui.Add("Checkbox", "x360 y264 w320 h24" (cfg.EnableMagneticSnap ? " Checked" : ""), "Magnetic Screen-Edge && App Window Snapping")
    chkAutoDodge := ccGui.Add("Checkbox", "x32 y294 w310 h24" (cfg.HudAutoDodge ? " Checked" : ""), "Auto-Dodge HUD on Mouse Hover (15% Ghost)")
    chkClickThru := ccGui.Add("Checkbox", "x360 y294 w320 h24" (cfg.HudClickThrough ? " Checked" : ""), "Click-Through HUD Mode (Hold Alt to Drag)")
    for hCtrl in [chkShowInd, chkShowExtra, chkShowText, chkMonoIcon, chkSleek, chkPulse, chkClickPills, chkMagSnap, chkAutoDodge, chkClickThru]
        Theme.RegisterControl(ccGui, hCtrl, "Checkbox", "tabText")

    btnResetPos := ccGui.Add("Button", "x32 y332 w310 h28", "Reset HUD Position to Default")
    btnResetApp := ccGui.Add("Button", "x360 y332 w320 h28", "Restore Default HUD Appearance")
    Theme.RegisterControl(ccGui, btnResetPos, "Button", "tabButton")
    Theme.RegisterControl(ccGui, btnResetApp, "Button", "tabButton")
    btnResetPos.OnEvent("Click", (*) => ResetTrayPosition(cfg, state))

    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y372 w130", "Custom Live Hex:"), "Text", "tabText")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    edCustomLive := ccGui.Add("Edit", "x165 y368 w175 h24", "#" cfg.CustomLiveHex)
    Theme.RegisterControl(ccGui, edCustomLive, "Edit")

    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x360 y372 w130", "Custom Muted Hex:"), "Text", "tabText")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    edCustomMuted := ccGui.Add("Edit", "x495 y368 w185 h24", "#" cfg.CustomMutedHex)
    Theme.RegisterControl(ccGui, edCustomMuted, "Edit")

    chkSecondaryMic := ccGui.Add("Checkbox", "x32 y402 w310 h22" (cfg.ShowSecondaryMicHud ? " Checked" : ""), "Secondary Independent Mic Pill (Mic-Only)")
    Theme.RegisterControl(ccGui, chkSecondaryMic, "Checkbox", "tabText")
    btnResetSecPos := ccGui.Add("Button", "x360 y400 w320 h26", "Reset Secondary Pill Position")
    Theme.RegisterControl(ccGui, btnResetSecPos, "Button", "tabButton")
    btnResetSecPos.OnEvent("Click", (*) => ResetSecondaryTrayPosition(cfg, state))

    chkShowRow2 := ccGui.Add("Checkbox", "x32 y430 w310 h22" (cfg.ShowRow2RecChatHud ? " Checked" : ""), "Show Recording && Chat HUD (Row 2)")
    chkShowRow3 := ccGui.Add("Checkbox", "x360 y430 w320 h22" (cfg.ShowRow3StudioSceneHud ? " Checked" : ""), "Show Studio && Scene HUD (Row 3)")
    chkExcludeCapture := ccGui.Add("Checkbox", "x32 y456 w310 h22" (cfg.ExcludeFromCapture ? " Checked" : ""), "Hide HUD from Screen Share / Capture")
    chkExcludeSecCapture := ccGui.Add("Checkbox", "x360 y456 w320 h22" (cfg.ExcludeSecondaryFromCapture ? " Checked" : ""), "Hide Secondary Pill from Capture")
    Theme.RegisterControl(ccGui, chkShowRow2, "Checkbox", "tabText")
    Theme.RegisterControl(ccGui, chkShowRow3, "Checkbox", "tabText")
    Theme.RegisterControl(ccGui, chkExcludeCapture, "Checkbox", "tabText")
    Theme.RegisterControl(ccGui, chkExcludeSecCapture, "Checkbox", "tabText")

    ; ==========================================================================
    ; TAB 5: REMOTE COMPANION
    ; ==========================================================================
    tabs.UseTab(5)
    ccGui.SetFont("s11 w700 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y60 w650", "Smart Board & Secondary Laptop Companion (1-Tier Mic HUD + Clicker Sync)"), "Text", "tabText")

    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y98 w210", "Remote Network Mode:"), "Text", "tabText")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    rNetIdx := (cfg.RemoteNetworkMode = "Internet") ? 2 : 1
    ddlRemoteNet := ccGui.Add("DropDownList", "x250 y94 w430 Choose" rNetIdx, ["Same Router (LAN)", "Different Networks (Internet)"])
    Theme.RegisterControl(ccGui, ddlRemoteNet, "DropDownList")

    if (cfg.InternetPairingCode = "") {
        cfg.InternetPairingCode := GenerateInternetPairingCode()
        cfg.Write("Settings", "InternetPairingCode", cfg.InternetPairingCode)
    }

    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y138 w210", "Internet Pairing Code:"), "Text", "tabText")
    ccGui.SetFont("s10 w700 norm", Theme.UiFont)
    edPairCode := ccGui.Add("Edit", "x250 y134 w210 h26 ReadOnly", cfg.InternetPairingCode)
    Theme.RegisterControl(ccGui, edPairCode, "Edit")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    btnCopyPair := ccGui.Add("Button", "x470 y132 w100 h28", "Copy Code")
    btnNewPair := ccGui.Add("Button", "x580 y132 w100 h28", "New Code")
    Theme.RegisterControl(ccGui, btnCopyPair, "Button", "tabButton")
    Theme.RegisterControl(ccGui, btnNewPair, "Button", "tabButton")
    btnCopyPair.OnEvent("Click", (*) => (A_Clipboard := edPairCode.Value, TrayTip("Internet Pairing Code copied to clipboard.", "PresenterSync", 1)))
    btnNewPair.OnEvent("Click", (*) => (
        cfg.InternetPairingCode := GenerateInternetPairingCode(),
        cfg.Write("Settings", "InternetPairingCode", cfg.InternetPairingCode),
        edPairCode.Value := cfg.InternetPairingCode,
        IsObject(state) ? UpdateHostInternetRelay(cfg, state) : 0
    ))
    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y178 w210", "Relay Server URL (ntfy):"), "Text", "tabText")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    edRelayBaseUrl := ccGui.Add("Edit", "x250 y174 w320 h26", cfg.HasOwnProp("RelayBaseUrl") && cfg.RelayBaseUrl != "" ? cfg.RelayBaseUrl : "https://ntfy.sh")
    Theme.RegisterControl(ccGui, edRelayBaseUrl, "Edit")
    DllCall("SendMessage", "Ptr", edRelayBaseUrl.Hwnd, "UInt", 0x1501, "Ptr", 1, "WStr", "https://ntfy.sh")
    btnResetRelayUrl := ccGui.Add("Button", "x580 y172 w100 h28", "Default")
    Theme.RegisterControl(ccGui, btnResetRelayUrl, "Button", "tabButton")
    btnResetRelayUrl.OnEvent("Click", (*) => (edRelayBaseUrl.Value := "https://ntfy.sh"))

    endpoints := GetLocalNetworkEndpoints()
    universalLanStr := A_ComputerName ".local"
    for ep in endpoints.ips
        universalLanStr .= ", " ep
    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y218 w210", "Universal LAN String:"), "Text", "tabText")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    edLanStr := ccGui.Add("Edit", "x250 y214 w320 h26 ReadOnly", universalLanStr)
    Theme.RegisterControl(ccGui, edLanStr, "Edit")
    btnCopyLan := ccGui.Add("Button", "x580 y212 w100 h28", "Copy LAN")
    Theme.RegisterControl(ccGui, btnCopyLan, "Button", "tabButton")
    btnCopyLan.OnEvent("Click", (*) => (A_Clipboard := edLanStr.Value, TrayTip("Universal LAN string copied to clipboard.", "PresenterSync", 1)))

    remNote := "Note: PresenterSync Remote stays a dedicated 1-tier Mic HUD on your secondary device. WAN Relay payloads are AES-256-GCM encrypted and work with https://ntfy.sh or a self-hosted ntfy server."
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y258 w648 h42", remNote), "Text", "tabMuted")
    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y310 w210", "Quick Nudge Presets (|):"), "Text", "tabText")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    edQuickNudgePresets := ccGui.Add("Edit", "x250 y306 w430 h26", cfg.HasOwnProp("QuickNudgePresets") && cfg.QuickNudgePresets != "" ? cfg.QuickNudgePresets : "2 min left|Wrap up|Check Mic|Q&A")
    Theme.RegisterControl(ccGui, edQuickNudgePresets, "Edit")

    btnRemDetails := ccGui.Add("Button", "x32 y346 w310 h32", "Open Full Remote Connection Dialog...")
    btnCloseRem := ccGui.Add("Button", "x360 y346 w320 h32", "Close Remote Companion on Secondary PC...")
    Theme.RegisterControl(ccGui, btnRemDetails, "Button", "tabButton")
    Theme.RegisterControl(ccGui, btnCloseRem, "Button", "tabButton")
    btnRemDetails.OnEvent("Click", (*) => ShowRemoteCompanionInfo(cfg, state))
    btnCloseRem.OnEvent("Click", (*) => PromptCloseRemoteCompanion(cfg, state))

    chkEnableRemoteConn := ccGui.Add("Checkbox", "x32 y390 w648 h24" (cfg.EnableRemoteConnections ? " Checked" : ""), "Allow Remote Companion Connections (Uncheck for Standalone Cutoff Mode)")
    chkIncludeVirtual := ccGui.Add("Checkbox", "x32 y418 w648 h24" (cfg.IncludeVirtualAdapters ? " Checked" : ""), "Include Virtual / VPN Adapters (WSL, WireGuard, Tailscale, Docker) in LAN Pairing")
    Theme.RegisterControl(ccGui, chkEnableRemoteConn, "Checkbox", "tabText")
    Theme.RegisterControl(ccGui, chkIncludeVirtual, "Checkbox", "tabText")

    ; ==========================================================================
    ; TAB 6: PROFILES, SHORTCUTS & SYSTEM
    ; ==========================================================================
    tabs.UseTab(6)
    ccGui.SetFont("s11 w700 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y60 w650", "Named Configuration Profiles, Global Hotkeys & System Startup"), "Text", "tabText")

    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y96 w140", "Active Profile:"), "Text", "tabText")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    profList := cfg.GetProfileNames()
    pChoose := 1
    for idx, pN in profList {
        if (StrLower(pN) = StrLower(cfg.ActiveProfile))
            pChoose := idx
    }
    ddlProfile := ccGui.Add("DropDownList", "x175 y92 w195 Choose" pChoose, profList)
    Theme.RegisterControl(ccGui, ddlProfile, "DropDownList")
    btnProfLoad := ccGui.Add("Button", "x380 y90 w94 h28", "Load")
    btnProfSave := ccGui.Add("Button", "x482 y90 w94 h28", "Save")
    btnProfMgr := ccGui.Add("Button", "x584 y90 w96 h28", "Manage...")
    Theme.RegisterControl(ccGui, btnProfLoad, "Button", "tabButton")
    Theme.RegisterControl(ccGui, btnProfSave, "Button", "tabButton")
    Theme.RegisterControl(ccGui, btnProfMgr, "Button", "tabButton")

    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y138 w142", "Cycle Pointer Mode:"), "Text", "tabText")
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x368 y138 w140", "Toggle OBS Sync:"), "Text", "tabText")
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y174 w142", "Toggle Conf Monitor:"), "Text", "tabText")
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x368 y174 w140", "Show / Hide HUD:"), "Text", "tabText")
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y210 w142", "Suspend All Hotkeys:"), "Text", "tabText")
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x368 y210 w140", "Exit Application:"), "Text", "tabText")
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y246 w142", "Remote Setup / QR:"), "Text", "tabText")

    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    edHkPpt := ccGui.Add("Edit", "x176 y134 w100 h26", cfg.PptHotkey)
    edHkWs := ccGui.Add("Edit", "x512 y134 w92 h26", cfg.WsHotkey)
    edHkZoom := ccGui.Add("Edit", "x176 y170 w100 h26", cfg.ZoomHotkey)
    edHkInd := ccGui.Add("Edit", "x512 y170 w92 h26", cfg.IndHotkey)
    edHkSusp := ccGui.Add("Edit", "x176 y206 w100 h26", cfg.SuspendHotkey)
    edHkExit := ccGui.Add("Edit", "x512 y206 w92 h26", cfg.ExitHotkey)
    edHkRemoteInfo := ccGui.Add("Edit", "x176 y242 w100 h26", cfg.RemoteInfoHotkey)
    for hkEd in [edHkPpt, edHkWs, edHkZoom, edHkInd, edHkSusp, edHkExit, edHkRemoteInfo]
        Theme.RegisterControl(ccGui, hkEd, "Edit")
    _AddCCCaptureBtn(ccGui, 280, 134, 72, 26, "Capture", edHkPpt, "Capture Cycle Pointer Mode")
    _AddCCCaptureBtn(ccGui, 608, 134, 72, 26, "Capture", edHkWs, "Capture Toggle OBS Sync")
    _AddCCCaptureBtn(ccGui, 280, 170, 72, 26, "Capture", edHkZoom, "Capture Toggle Conf Monitor")
    _AddCCCaptureBtn(ccGui, 608, 170, 72, 26, "Capture", edHkInd, "Capture Show / Hide HUD")
    _AddCCCaptureBtn(ccGui, 280, 206, 72, 26, "Capture", edHkSusp, "Capture Suspend All Hotkeys")
    _AddCCCaptureBtn(ccGui, 608, 206, 72, 26, "Capture", edHkExit, "Capture Exit Application")
    _AddCCCaptureBtn(ccGui, 280, 242, 72, 26, "Capture", edHkRemoteInfo, "Capture Remote Setup Shortcut")

    chkStartup := ccGui.Add("Checkbox", "x32 y286 w380 h24" (cfg.StartWithWindows ? " Checked" : ""), "Start PresenterSync Automatically with Windows (Default: OFF)")
    Theme.RegisterControl(ccGui, chkStartup, "Checkbox", "tabText")

    chkAutoUpd := ccGui.Add("Checkbox", "x32 y318 w380 h24" (cfg.AutoCheckUpdates ? " Checked" : ""), "Auto-check GitHub updates daily on startup")
    Theme.RegisterControl(ccGui, chkAutoUpd, "Checkbox", "tabText")

    btnCheckUpd := ccGui.Add("Button", "x430 y282 w250 h30", "Check for GitHub Updates...")
    Theme.RegisterControl(ccGui, btnCheckUpd, "Button", "tabButton")
    btnCheckUpd.OnEvent("Click", (*) => CheckForUpdates(UIConstants.APP_VERSION, "", false, "PresenterSync.exe", cfg))

    btnExportDiagCC := ccGui.Add("Button", "x430 y318 w250 h30", "Export Sanitized Diagnostics...")
    Theme.RegisterControl(ccGui, btnExportDiagCC, "Button", "tabButton")
    btnExportDiagCC.OnEvent("Click", (*) => ExportSanitizedDiagnostics(cfg, state, "", true))

    btnPreFlightCC := ccGui.Add("Button", "x430 y354 w250 h30", "Go Live 10-Second Rehearsal...")
    Theme.RegisterControl(ccGui, btnPreFlightCC, "Button", "tabButton")
    btnPreFlightCC.OnEvent("Click", (*) => ShowPreFlightRehearsalDialog(cfg, state))

    btnExportBundleCC := ccGui.Add("Button", "x430 y390 w122 h30", "Export Bundle...")
    btnImportBundleCC := ccGui.Add("Button", "x558 y390 w122 h30", "Import Bundle...")
    Theme.RegisterControl(ccGui, btnExportBundleCC, "Button", "tabButton")
    Theme.RegisterControl(ccGui, btnImportBundleCC, "Button", "tabButton")
    btnExportBundleCC.OnEvent("Click", (*) => ExportPortableSettingsBundleUI(cfg))
    btnImportBundleCC.OnEvent("Click", (*) => ImportPortableSettingsBundleUI(cfg, state))

    tabs.UseTab()

    ; ==========================================================================
    ; BOTTOM BAR: STATUS + APPLY & SAVE + CLOSE
    ; ==========================================================================
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    lblStatus := ccGui.Add("Text", "x20 y514 w380 h24", "Active Profile: " cfg.ActiveProfile "  |  PresenterSync v" UIConstants.APP_VERSION)
    Theme.RegisterControl(ccGui, lblStatus, "Text", "muted")

    ccGui.SetFont("s10 w600 norm", Theme.UiFont)
    btnApply := ccGui.Add("Button", "x416 y508 w140 h34 Default", "Apply && Save")
    btnClose := ccGui.Add("Button", "x566 y508 w140 h34", "Close")
    Theme.RegisterControl(ccGui, btnApply, "Button", "accent")
    Theme.RegisterControl(ccGui, btnClose, "Button")

    SyncControlsFromConfig() {
        ddlRouting.Choose(cfg.AudioRoutingMode >= 1 && cfg.AudioRoutingMode <= 3 ? cfg.AudioRoutingMode : 1)
        for i, cName in confApps {
            if (NormalizeConferencingApp(cfg.ConferencingApp) = cName)
                ddlConfApp.Choose(i)
        }
        cbTargetMic.Text := cfg.targetMicName
        edSecondaryAudioSources.Value := cfg.HasOwnProp("SecondaryAudioSources") ? cfg.SecondaryAudioSources : ""
        edUiaMuteKeywords.Value := cfg.HasOwnProp("UiaMuteKeywords") ? cfg.UiaMuteKeywords : ""
        edUiaUnmuteKeywords.Value := cfg.HasOwnProp("UiaUnmuteKeywords") ? cfg.UiaUnmuteKeywords : ""
        edZoomMute.Value := cfg.ZoomMuteHotkey
        edTeamsMute.Value := cfg.TeamsMuteHotkey
        edMeetMute.Value := cfg.MeetMuteHotkey
        edZoomRec.Value := cfg.ZoomRecHotkey
        edZoomPause.Value := cfg.ZoomPauseHotkey
        chkVoiceMeter.Value := cfg.ShowVoiceMeter ? 1 : 0
        chkAudioCue.Value := cfg.EnableAudioCue ? 1 : 0
        chkMuteToast.Value := cfg.EnableMuteToast ? 1 : 0
        chkAutoMuteLock.Value := cfg.AutoMuteOnLock ? 1 : 0
        chkAutoMuteMeetingEnd.Value := cfg.AutoMuteOnMeetingEnd ? 1 : 0
        chkAutoMuteFirstObs.Value := cfg.AutoMuteOnFirstObsConnect ? 1 : 0
        chkCoreAudioFallback.Value := cfg.EnableCoreAudioFallback ? 1 : 0
        chkOsMuteDrift.Value := cfg.EnableOsMuteDriftWatchdog ? 1 : 0
        chkForgottenRec.Value := cfg.EnableForgottenRecordWatchdog ? 1 : 0
        chkDeadMic.Value := cfg.EnableDeadMicWatchdog ? 1 : 0
        chkAutoRecDrop.Value := cfg.AutoRecordOnStreamDrop ? 1 : 0
        chkLowDisk.Value := cfg.EnableLowDiskWatchdog ? 1 : 0
        chkConfirmStopRec.Value := cfg.ConfirmBeforeStopRecording ? 1 : 0
        chkEnableWS.Value := cfg.EnableWS ? 1 : 0
        chkEnableZoom.Value := cfg.EnableZoom ? 1 : 0
        edObsPass.Value := cfg.obsPassword
        chkStreamHud.Value := cfg.ShowStreamHud ? 1 : 0
        chkRecTimer.Value := cfg.ShowRecTimer ? 1 : 0
        edObsMute.Value := cfg.ObsMuteHotkey
        edObsRec.Value := cfg.ObsRecHotkey
        edObsPause.Value := cfg.ObsPauseHotkey
        edObsTransition.Value := cfg.ObsTransitionHotkey
        edStandbyScene.Value := cfg.StandbySceneName
        ddlPointerMode.Choose(cfg.EnablePPT ? 1 : (cfg.EnableMicOnly ? 2 : 3))
        edHwMute.Value := cfg.HwMuteHotkey
        chkPointerTransition.Value := cfg.EnablePointerTransition ? 1 : 0
        edHwTransition.Value := cfg.HwTransitionHotkey
        chkPushToMute.Value := cfg.EnablePushToMute ? 1 : 0
        chkPushToTalk.Value := cfg.EnablePushToTalk ? 1 : 0
        chkArrows.Value := cfg.CatchArrows ? 1 : 0
        chkPg.Value := cfg.CatchPg ? 1 : 0
        chkSpace.Value := cfg.CatchSpace ? 1 : 0
        chkEnter.Value := cfg.CatchEnter ? 1 : 0
        chkTab.Value := cfg.CatchTab ? 1 : 0
        chkEsc.Value := cfg.CatchEsc ? 1 : 0
        for idx, sv in scaleValues {
            if (Abs(cfg.IndicatorScale - sv) < 0.01)
                ddlScale.Choose(idx)
        }
        ddlOpacity.Choose((cfg.OpacityLevel == UIConstants.OPACITY_SOLID) ? 1 : ((cfg.OpacityLevel == UIConstants.OPACITY_GHOST) ? 3 : 2))
        for idx, pName in palNames {
            if (StrLower(cfg.HudColorPreset) = StrLower(pName))
                ddlPalette.Choose(idx)
        }
        edCustomLive.Value := "#" cfg.CustomLiveHex
        edCustomMuted.Value := "#" cfg.CustomMutedHex
        ddlTheme.Choose((cfg.ThemeMode = "Dark") ? 2 : ((cfg.ThemeMode = "Light") ? 3 : 1))
        chkShowInd.Value := cfg.ShowIndicator ? 1 : 0
        chkShowExtra.Value := cfg.ShowExtraHuds ? 1 : 0
        chkShowRow2.Value := cfg.ShowRow2RecChatHud ? 1 : 0
        chkShowRow3.Value := cfg.ShowRow3StudioSceneHud ? 1 : 0
        chkSecondaryMic.Value := cfg.ShowSecondaryMicHud ? 1 : 0
        chkShowText.Value := cfg.ShowText ? 1 : 0
        chkMonoIcon.Value := cfg.MonoIcon ? 1 : 0
        chkSleek.Value := cfg.SleekCorners ? 1 : 0
        chkPulse.Value := cfg.AggressivePulse ? 1 : 0
        chkClickPills.Value := cfg.EnableHudClickActions ? 1 : 0
        chkMagSnap.Value := cfg.EnableMagneticSnap ? 1 : 0
        chkAutoDodge.Value := cfg.HudAutoDodge ? 1 : 0
        chkClickThru.Value := cfg.HudClickThrough ? 1 : 0
        chkExcludeCapture.Value := cfg.ExcludeFromCapture ? 1 : 0
        chkExcludeSecCapture.Value := cfg.ExcludeSecondaryFromCapture ? 1 : 0
        ddlRemoteNet.Choose((cfg.RemoteNetworkMode = "Internet") ? 2 : 1)
        edPairCode.Value := cfg.InternetPairingCode
        edRelayBaseUrl.Value := (cfg.HasOwnProp("RelayBaseUrl") && cfg.RelayBaseUrl != "") ? cfg.RelayBaseUrl : "https://ntfy.sh"
        edQuickNudgePresets.Value := (cfg.HasOwnProp("QuickNudgePresets") && cfg.QuickNudgePresets != "") ? cfg.QuickNudgePresets : "2 min left|Wrap up|Check Mic|Q&A"
        chkEnableRemoteConn.Value := cfg.EnableRemoteConnections ? 1 : 0
        chkIncludeVirtual.Value := cfg.IncludeVirtualAdapters ? 1 : 0
        edHkPpt.Value := cfg.PptHotkey
        edHkWs.Value := cfg.WsHotkey
        edHkZoom.Value := cfg.ZoomHotkey
        edHkInd.Value := cfg.IndHotkey
        edHkSusp.Value := cfg.SuspendHotkey
        edHkExit.Value := cfg.ExitHotkey
        edHkRemoteInfo.Value := cfg.RemoteInfoHotkey
        chkStartup.Value := cfg.StartWithWindows ? 1 : 0
        chkAutoUpd.Value := cfg.AutoCheckUpdates ? 1 : 0
        profList := cfg.GetProfileNames()
        ddlProfile.Delete()
        ddlProfile.Add(profList)
        pChoose := 1
        for idx, pN in profList {
            if (StrLower(pN) = StrLower(cfg.ActiveProfile))
                pChoose := idx
        }
        ddlProfile.Choose(pChoose)
        lblStatus.Value := "Active Profile: " cfg.ActiveProfile "  |  PresenterSync v" UIConstants.APP_VERSION
    }

    btnResetApp.OnEvent("Click", (*) => (
        ResetAppearance(cfg, state),
        SyncControlsFromConfig(),
        lblStatus.Value := "Restored default HUD appearance."
    ))

    btnProfLoad.OnEvent("Click", (*) => (
        cfg.ApplyProfile(ddlProfile.Text, state) ? (SyncControlsFromConfig(), lblStatus.Value := "Loaded profile: " cfg.ActiveProfile) : (lblStatus.Value := "Save snapshot to '" ddlProfile.Text "' first.")
    ))
    btnProfSave.OnEvent("Click", (*) => (
        OnApplyClick() ? (
            cfg.SaveProfile(ddlProfile.Text),
            SyncControlsFromConfig(),
            lblStatus.Value := "Saved settings to profile: " cfg.ActiveProfile
        ) : 0
    ))
    btnProfMgr.OnEvent("Click", (*) => ShowProfileManagerUI(cfg, state))

    OnApplyClick(*) {
        selOpacity := (ddlOpacity.Value == 1) ? UIConstants.OPACITY_SOLID : ((ddlOpacity.Value == 3) ? UIConstants.OPACITY_GHOST : UIConstants.OPACITY_FROSTED)
        vals := {
            AudioRoutingMode: ddlRouting.Value,
            ConferencingApp: ddlConfApp.Text,
            targetMicName: cbTargetMic.Text,
            SecondaryAudioSources: edSecondaryAudioSources.Value,
            UiaMuteKeywords: edUiaMuteKeywords.Value,
            UiaUnmuteKeywords: edUiaUnmuteKeywords.Value,
            ZoomMuteHotkey: edZoomMute.Value,
            TeamsMuteHotkey: edTeamsMute.Value,
            MeetMuteHotkey: edMeetMute.Value,
            ZoomRecHotkey: edZoomRec.Value,
            ZoomPauseHotkey: edZoomPause.Value,
            ShowVoiceMeter: chkVoiceMeter.Value,
            EnableAudioCue: chkAudioCue.Value,
            EnableMuteToast: chkMuteToast.Value,
            AutoMuteOnLock: chkAutoMuteLock.Value,
            AutoMuteOnMeetingEnd: chkAutoMuteMeetingEnd.Value,
            AutoMuteOnFirstObsConnect: chkAutoMuteFirstObs.Value,
            EnableCoreAudioFallback: chkCoreAudioFallback.Value,
            EnableOsMuteDriftWatchdog: chkOsMuteDrift.Value,
            EnableForgottenRecordWatchdog: chkForgottenRec.Value,
            EnableDeadMicWatchdog: chkDeadMic.Value,
            AutoRecordOnStreamDrop: chkAutoRecDrop.Value,
            EnableLowDiskWatchdog: chkLowDisk.Value,
            ConfirmBeforeStopRecording: chkConfirmStopRec.Value,
            EnableWS: chkEnableWS.Value,
            EnableZoom: chkEnableZoom.Value,
            obsPassword: edObsPass.Value,
            ShowStreamHud: chkStreamHud.Value,
            ShowRecTimer: chkRecTimer.Value,
            ObsMuteHotkey: edObsMute.Value,
            ObsRecHotkey: edObsRec.Value,
            ObsPauseHotkey: edObsPause.Value,
            ObsTransitionHotkey: edObsTransition.Value,
            StandbySceneName: edStandbyScene.Value,
            PointerMode: ddlPointerMode.Text,
            HwMuteHotkey: edHwMute.Value,
            EnablePointerTransition: chkPointerTransition.Value,
            HwTransitionHotkey: edHwTransition.Value,
            EnablePushToMute: chkPushToMute.Value,
            EnablePushToTalk: chkPushToTalk.Value,
            CatchArrows: chkArrows.Value,
            CatchPg: chkPg.Value,
            CatchSpace: chkSpace.Value,
            CatchEnter: chkEnter.Value,
            CatchTab: chkTab.Value,
            CatchEsc: chkEsc.Value,
            IndicatorScale: scaleValues[ddlScale.Value],
            OpacityLevel: selOpacity,
            HudColorPreset: ddlPalette.Text,
            CustomLiveHex: edCustomLive.Value,
            CustomMutedHex: edCustomMuted.Value,
            ThemeMode: ddlTheme.Text,
            ShowIndicator: chkShowInd.Value,
            ShowExtraHuds: chkShowExtra.Value,
            ShowRow2RecChatHud: chkShowRow2.Value,
            ShowRow3StudioSceneHud: chkShowRow3.Value,
            ShowSecondaryMicHud: chkSecondaryMic.Value,
            ShowText: chkShowText.Value,
            MonoIcon: chkMonoIcon.Value,
            SleekCorners: chkSleek.Value,
            AggressivePulse: chkPulse.Value,
            EnableHudClickActions: chkClickPills.Value,
            EnableMagneticSnap: chkMagSnap.Value,
            HudAutoDodge: chkAutoDodge.Value,
            HudClickThrough: chkClickThru.Value,
            ExcludeFromCapture: chkExcludeCapture.Value,
            ExcludeSecondaryFromCapture: chkExcludeSecCapture.Value,
            RemoteNetworkMode: (ddlRemoteNet.Value == 2) ? "Internet" : "LAN",
            RelayBaseUrl: edRelayBaseUrl.Value,
            QuickNudgePresets: edQuickNudgePresets.Value,
            EnableRemoteConnections: chkEnableRemoteConn.Value,
            IncludeVirtualAdapters: chkIncludeVirtual.Value,
            PptHotkey: edHkPpt.Value,
            WsHotkey: edHkWs.Value,
            ZoomHotkey: edHkZoom.Value,
            IndHotkey: edHkInd.Value,
            SuspendHotkey: edHkSusp.Value,
            ExitHotkey: edHkExit.Value,
            RemoteInfoHotkey: edHkRemoteInfo.Value,
            StartWithWindows: chkStartup.Value,
            AutoCheckUpdates: chkAutoUpd.Value
        }
        invalidKeys := []
        ok := ApplyControlCenterSettings(cfg, state, vals, true, invalidKeys)
        if (!ok && invalidKeys.Length > 0) {
            badLabels := ""
            for idx, item in invalidKeys
                badLabels .= (idx > 1 ? ", " : "") item.label " ('" item.value "')"
            SyncControlsFromConfig()
            lblStatus.Value := "Ignored invalid hotkey: " badLabels " (valid settings saved)."
            return false
        }
        lblStatus.Value := "All settings applied and saved live (" FormatTime(, "HH:mm:ss") ")."
        return true
    }

    CloseControlCenter(*) {
        if (ccGui._closed)
            return
        ccGui._closed := true
        if (IsObject(state) && state.HasOwnProp("refreshInputsFn"))
            state.refreshInputsFn := prevRefreshInputsFn
        Theme.UnregisterWindow(ccGui, "PresenterSync - Control Center")
        Theme.ReleaseSuspend()
        ccGui.Destroy()
    }

    btnApply.OnEvent("Click", OnApplyClick)
    btnClose.OnEvent("Click", CloseControlCenter)
    ccGui.OnEvent("Close", CloseControlCenter)
    ccGui.OnEvent("Escape", CloseControlCenter)

    WindowFit.Show(ccGui, "w720 h556")
    return ccGui
}

ExportPortableSettingsBundleUI(cfg, *) {
    if (IsSet(g_IsTestMode) && g_IsTestMode)
        return { ok: false, testMode: true }
    target := FileSelect("S16", A_ScriptDir "\PresenterSync_Bundle.json", "Export Portable Settings Bundle", "Settings Bundle (*.json; *.ini)")
    if (target = "")
        return { ok: false, cancelled: true }
    res := ExportPortableSettingsBundle(cfg, target, false)
    if (res.ok)
        TrayTip("Exported " res.count " settings to:`n" res.path, "PresenterSync Bundle", 1)
    else
        MsgBox("Export failed: " res.error, "PresenterSync Bundle", 16)
    return res
}

ImportPortableSettingsBundleUI(cfg, state := "", *) {
    if (IsSet(g_IsTestMode) && g_IsTestMode)
        return { ok: false, testMode: true }
    src := FileSelect(3, A_ScriptDir, "Import Portable Settings Bundle", "Settings Bundle (*.json; *.ini)")
    if (src = "")
        return { ok: false, cancelled: true }
    res := ImportPortableSettingsBundle(cfg, state, src)
    if (res.ok)
        TrayTip("Imported " res.appliedCount " settings from bundle.", "PresenterSync Bundle", 1)
    else
        MsgBox("Import failed: " res.error, "PresenterSync Bundle", 16)
    return res
}


