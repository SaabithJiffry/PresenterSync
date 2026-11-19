; ==============================================================================
; Module: OBS_Network.ahk
; Description: OBS WebSocket v5 client connection, message handling & Zoom UIA sync
; ==============================================================================

#Include "%A_LineFile%\..\WebSocket.ahk"
#Include "%A_LineFile%\..\UIA.ahk"
#Include "%A_LineFile%\..\Crypto.ahk"
#Include "%A_LineFile%\..\HostBridge.ahk"

FormatSendKey(hk) {
    if RegExMatch(hk, "^(.*?)([a-zA-Z0-9_]+)$", &m) {
        key := (StrLen(m[2]) == 1) ? StrLower(m[2]) : m[2]
        return m[1] "{" key "}"
    }
    if RegExMatch(hk, "^(.*?)([{}^!+#])$", &m)
        return m[1] "{" m[2] "}"
    return hk
}

ExtractBaseKeyName(hk) {
    s := Trim(String(hk))
    if (s = "" || s = "None")
        return ""
    s := RegExReplace(s, "i)\s+up$", "")
    s := RegExReplace(s, "^[*~$<>^!+#]+(?=.+$)", "")
    return Trim(s)
}

_DoHotkeysCollide(hkA, hkB) {
    cleanA := LTrim(Trim(String(hkA)), "~*$")
    cleanB := LTrim(Trim(String(hkB)), "~*$")
    cleanA := RegExReplace(cleanA, "^\{(.+)\}$", "$1")
    cleanB := RegExReplace(cleanB, "^\{(.+)\}$", "$1")
    if (cleanA = "" || StrLower(cleanA) = "none" || cleanB = "" || StrLower(cleanB) = "none")
        return false
    normA := GetKeyName(cleanA)
    normB := GetKeyName(cleanB)
    if (normA != "" && normB != "")
        return StrLower(normA) == StrLower(normB)
    return StrLower(cleanA) == StrLower(cleanB)
}

IsPptKeyAllowed(cfg, pptKey) {
    if (!IsObject(cfg))
        return false
    cleanPpt := LTrim(Trim(String(pptKey)), "~*$")
    cleanPpt := RegExReplace(cleanPpt, "^\{(.+)\}$", "$1")
    if (cleanPpt = "" || StrLower(cleanPpt) = "none")
        return false

    switch StrLower(cleanPpt) {
        case "down", "up", "left", "right":
            if (cfg.HasOwnProp("CatchArrows") && !cfg.CatchArrows)
                return false
        case "pgdn", "pgup", "pagedown", "pageup":
            if (cfg.HasOwnProp("CatchPg") && !cfg.CatchPg)
                return false
            if (!cfg.HasOwnProp("CatchPg") && cfg.HasOwnProp("CatchPgUpDn") && !cfg.CatchPgUpDn)
                return false
        case "space":
            if (cfg.HasOwnProp("CatchSpace") && !cfg.CatchSpace)
                return false
        case "enter", "return":
            if (cfg.HasOwnProp("CatchEnter") && !cfg.CatchEnter)
                return false
        case "tab":
            if (cfg.HasOwnProp("CatchTab") && !cfg.CatchTab)
                return false
        case "esc", "escape":
            if (cfg.HasOwnProp("CatchEsc") && !cfg.CatchEsc)
                return false
    }

    for _, prop in ["HwMuteHotkey", "ObsMuteHotkey", "HwTransitionHotkey", "ObsTransitionHotkey"] {
        if (cfg.HasOwnProp(prop) && _DoHotkeysCollide(cleanPpt, cfg.%prop%))
            return false
    }
    return true
}

_WaitKeyHoldAndRelease(hk, minHoldSec := 0.35, maxWaitSec := 15, keyWaitFn := "") {
    baseKey := ExtractBaseKeyName(hk)
    if (baseKey = "")
        return false
    waitFn := IsObject(keyWaitFn) ? keyWaitFn : KeyWait
    if (minHoldSec > 0.0) {
        holdOpt := "T" Format("{:.3f}", minHoldSec)
        if (waitFn.Call(baseKey, holdOpt))
            return false
    }
    waitFn.Call(baseKey, "T" Integer(Max(1, maxWaitSec)))
    return true
}

WaitPushToMuteRelease(cfg, hk, keyWaitFn := "") {
    if (!IsObject(cfg) || !cfg.HasOwnProp("EnablePushToMute") || !cfg.EnablePushToMute)
        return false
    holdSec := (IsSet(UIConstants) && UIConstants.HasOwnProp("PUSH_TO_MUTE_HOLD_MS")) ? (UIConstants.PUSH_TO_MUTE_HOLD_MS / 1000.0) : 0.35
    return _WaitKeyHoldAndRelease(hk, holdSec, 15, keyWaitFn)
}

WaitPushToTalkRelease(cfg, hk, keyWaitFn := "") {
    if (!IsObject(cfg) || !cfg.HasOwnProp("EnablePushToTalk") || !cfg.EnablePushToTalk)
        return false
    return _WaitKeyHoldAndRelease(hk, 0.0, 30, keyWaitFn)
}

ExecutePushToTalkHoldCycle(cfg, state, setMuteFn, hk, keyWaitFn := "") {
    if (!IsObject(cfg) || !cfg.HasOwnProp("EnablePushToTalk") || !cfg.EnablePushToTalk)
        return false
    if (!IsObject(state) || !state.HasOwnProp("isMuted") || !state.isMuted)
        return false
    if (!IsObject(setMuteFn))
        return false
    setMuteFn.Call(false)
    WaitPushToTalkRelease(cfg, hk, keyWaitFn)
    setMuteFn.Call(true)
    return true
}

GetConferencingAppNames() {
    return ["Auto", "Zoom", "Microsoft Teams", "Google Meet"]
}

NormalizeConferencingApp(name) {
    cleaned := StrLower(Trim(String(name)))
    if (cleaned = "auto")
        return "Auto"
    if (InStr(cleaned, "teams"))
        return "Microsoft Teams"
    if (InStr(cleaned, "meet"))
        return "Google Meet"
    return "Zoom"
}

_CollectConfWinSnapshots() {
    snaps := []
    activeHwnd := 0
    try activeHwnd := WinExist("A")
    try {
        for hwnd in WinGetList() {
            if !DllCall("IsWindowVisible", "Ptr", hwnd)
                continue
            exe := "", title := "", mm := 0
            try exe := WinGetProcessName(hwnd)
            try title := WinGetTitle(hwnd)
            try mm := WinGetMinMax(hwnd)
            if (exe != "")
                snaps.Push({ exe: exe, title: title, active: (hwnd == activeHwnd), minMax: mm })
        }
    }
    return snaps
}

ResolveAutoConfAppTarget(cfg := "", state := "", winSnapshots := "") {
    target := "Auto"
    if (IsObject(cfg)) {
        if (cfg.HasOwnProp("ConfAppTarget") && Trim(String(cfg.ConfAppTarget)) != "")
            target := Trim(String(cfg.ConfAppTarget))
        else if (cfg.HasOwnProp("ConferencingApp") && Trim(String(cfg.ConferencingApp)) != "")
            target := Trim(String(cfg.ConferencingApp))
    }
    if (StrLower(target) != "auto") {
        norm := NormalizeConferencingApp(target)
        if (IsObject(state))
            state.detectedConfApp := norm
        return norm
    }

    snaps := IsObject(winSnapshots) ? winSnapshots : _CollectConfWinSnapshots()
    bestApp := ""
    bestScore := 0
    for _, w in snaps {
        exeLow := StrLower(w.HasOwnProp("exe") ? String(w.exe) : "")
        titleStr := w.HasOwnProp("title") ? String(w.title) : ""
        isAct := w.HasOwnProp("active") ? !!w.active : false
        mm := w.HasOwnProp("minMax") ? Integer(w.minMax) : 0

        candApp := ""
        if (exeLow = "zoom.exe") {
            candApp := "Zoom"
        } else if (exeLow = "ms-teams.exe" || exeLow = "teams.exe") {
            candApp := "Teams"
        } else if (exeLow = "chrome.exe" || exeLow = "msedge.exe" || exeLow = "brave.exe") {
            if (InStr(titleStr, "Meet -") || InStr(titleStr, "Google Meet"))
                candApp := "Meet"
        }

        if (candApp != "") {
            score := isAct ? 3 : ((mm != -1) ? 2 : 1)
            if (score > bestScore) {
                bestScore := score
                bestApp := candApp
            }
        }
    }

    if (IsObject(state))
        state.detectedConfApp := bestApp
    return bestApp
}

GetConfiguredUiaKeywords(cfg := "") {
    muteList := ["mute", "mute my audio", "mute mic", "mute microphone", "turn off microphone"]
    unmuteList := ["unmute", "unmute my audio", "unmute mic", "unmute microphone", "turn on microphone"]
    seenM := Map(), seenU := Map()
    for _, k in muteList
        seenM[StrLower(k)] := true
    for _, k in unmuteList
        seenU[StrLower(k)] := true

    if (IsObject(cfg)) {
        if (cfg.HasOwnProp("UiaMuteKeywords") && Trim(String(cfg.UiaMuteKeywords)) != "") {
            for _, raw in StrSplit(String(cfg.UiaMuteKeywords), [",", ";"]) {
                kw := Trim(raw)
                if (kw != "" && !seenM.Has(StrLower(kw))) {
                    seenM[StrLower(kw)] := true
                    muteList.Push(kw)
                }
            }
        }
        if (cfg.HasOwnProp("UiaUnmuteKeywords") && Trim(String(cfg.UiaUnmuteKeywords)) != "") {
            for _, raw in StrSplit(String(cfg.UiaUnmuteKeywords), [",", ";"]) {
                kw := Trim(raw)
                if (kw != "" && !seenU.Has(StrLower(kw))) {
                    seenU[StrLower(kw)] := true
                    unmuteList.Push(kw)
                }
            }
        }
    }
    return { mute: muteList, unmute: unmuteList }
}

CheckMeetBackgroundTabWarning(cfg, state, winSnapshots := "") {
    static lastWarnTick := 0
    if (!IsObject(state))
        return false
    resolved := ResolveAutoConfAppTarget(cfg, state, winSnapshots)
    norm := NormalizeConferencingApp(resolved)
    if (resolved = "" || norm != "Google Meet") {
        state.meetBgTabWarn := false
        return false
    }

    snaps := IsObject(winSnapshots) ? winSnapshots : _CollectConfWinSnapshots()
    hasMeetWin := false
    meetMinimized := false
    browserSwitchedTab := false
    for _, w in snaps {
        exeLow := StrLower(w.HasOwnProp("exe") ? String(w.exe) : "")
        if !(exeLow = "chrome.exe" || exeLow = "msedge.exe" || exeLow = "brave.exe" || exeLow = "firefox.exe")
            continue
        titleStr := w.HasOwnProp("title") ? String(w.title) : ""
        isAct := w.HasOwnProp("active") ? !!w.active : false
        mm := w.HasOwnProp("minMax") ? Integer(w.minMax) : 0
        if (InStr(titleStr, "Meet -") || InStr(titleStr, "Google Meet")) {
            hasMeetWin := true
            if (mm == -1)
                meetMinimized := true
        } else if (isAct) {
            browserSwitchedTab := true
        }
    }

    warn := (meetMinimized || (!hasMeetWin && browserSwitchedTab))
    state.meetBgTabWarn := warn
    if (warn && (!IsSet(g_IsTestMode) || !g_IsTestMode)) {
        now := A_TickCount
        if (lastWarnTick == 0 || (now - lastWarnTick) >= 30000) {
            lastWarnTick := now
            try TrayTip("Google Meet is minimized or in a background browser tab — UIA mute sync may pause until restored.", "PresenterSync", 2)
        }
    }
    return warn
}

_GetComItemOrIndex(col, idx) {
    if (!IsObject(col))
        return ""
    try return col.Item(idx)
    try return col[idx]
    return ""
}

PollPowerPointSlideTelemetry(state, pptApp := "") {
    if (!IsObject(state))
        return false

    app := ""
    if (IsObject(pptApp)) {
        app := pptApp
    } else {
        try app := ComObjActive("PowerPoint.Application")
        catch
            app := ""
    }

    if (IsObject(app)) {
        ssWinCount := 0
        try ssWinCount := Integer(app.SlideShowWindows.Count)
        if (ssWinCount >= 1) {
            ssWin := _GetComItemOrIndex(app.SlideShowWindows, 1)
            if (IsObject(ssWin)) {
                curIdx := 0
                total := 0
                title := ""
                notes := ""
                try {
                    view := ssWin.View
                    curIdx := Integer(view.CurrentShowPosition)
                    slideObj := view.Slide
                    try total := Integer(ssWin.Presentation.Slides.Count)
                    catch {
                        try total := Integer(app.ActivePresentation.Slides.Count)
                    }
                    try title := Trim(String(slideObj.Shapes.Title.TextFrame.TextRange.Text))
                    try {
                        ph := _GetComItemOrIndex(slideObj.NotesPage.Shapes.Placeholders, 2)
                        if (IsObject(ph))
                            notes := Trim(String(ph.TextFrame.TextRange.Text))
                    }
                    if (StrLen(notes) > 2000)
                        notes := SubStr(notes, 1, 2000)
                }
                prevIdx := state.HasOwnProp("slideIndex") ? Integer(state.slideIndex) : 0
                state.slideIndex := curIdx
                state.slideTotal := total
                state.slideTitle := title
                state.slideNotes := notes
                if (curIdx > 0 && curIdx != prevIdx && IsSet(SessionTimeline)) {
                    try SessionTimeline.Record("slide", "Slide " curIdx (total > 0 ? ("/" total) : "") (title != "" ? (" - " title) : ""), state, title)
                }
                return true
            }
        }
    }

    state.slideIndex := 0
    state.slideTotal := 0
    state.slideTitle := ""
    state.slideNotes := ""
    return false
}

StartPowerPointSlideshow(pptApp := "") {
    app := ""
    if (IsObject(pptApp)) {
        app := pptApp
    } else {
        try app := ComObjActive("PowerPoint.Application")
        catch
            app := ""
    }
    if (IsObject(app)) {
        try {
            app.ActivePresentation.SlideShowSettings.Run()
            return true
        }
    }
    if (WinExist("ahk_exe POWERPNT.EXE")) {
        try {
            WinActivate("ahk_exe POWERPNT.EXE")
            Send("{F5}")
            return true
        }
    }
    return false
}

GetFallbackSlideKey(exe, dir := "next") {
    exeLow := StrLower(Trim(String(exe)))
    dLow := StrLower(Trim(String(dir)))
    isPrev := (dLow = "prev" || dLow = "previous" || dLow = "{left}" || dLow = "{up}" || dLow = "{pgup}")
    if (exeLow = "acrobat.exe" || exeLow = "acrord32.exe" || exeLow = "sumatrapdf.exe" || exeLow = "foxitpdfreader.exe")
        return isPrev ? "{PgUp}" : "{PgDn}"
    if (exeLow = "chrome.exe" || exeLow = "msedge.exe" || exeLow = "brave.exe" || exeLow = "firefox.exe")
        return isPrev ? "{Left}" : "{Right}"
    return ""
}

TryDispatchFallbackSlideKey(dir := "next", mockWin := "", dryRun := false) {
    targetExe := ""
    targetSpec := ""
    isActive := false
    if (IsObject(mockWin)) {
        targetExe := mockWin.HasOwnProp("exe") ? String(mockWin.exe) : ""
        isActive := mockWin.HasOwnProp("active") ? !!mockWin.active : true
        targetSpec := "ahk_exe " targetExe
    } else {
        activeExe := ""
        try activeExe := WinGetProcessName("A")
        if (activeExe != "" && GetFallbackSlideKey(activeExe, dir) != "") {
            targetExe := activeExe
            targetSpec := "A"
            isActive := true
        } else {
            for _, cand in ["Acrobat.exe", "AcroRd32.exe", "SumatraPDF.exe", "FoxitPDFReader.exe", "chrome.exe", "msedge.exe", "brave.exe", "firefox.exe"] {
                if (WinExist("ahk_exe " cand)) {
                    targetExe := cand
                    targetSpec := "ahk_exe " cand
                    break
                }
            }
        }
    }
    key := GetFallbackSlideKey(targetExe, dir)
    if (key = "")
        return { handled: false, exe: "", key: "" }
    if (!dryRun && (!IsSet(g_IsTestMode) || !g_IsTestMode)) {
        if (isActive) {
            try Send(key)
        } else if (targetSpec != "") {
            try ControlSend(key, , targetSpec)
        }
    }
    return { handled: true, exe: targetExe, key: key }
}

GetConferencingWindowSpec(appType := "Zoom") {
    switch NormalizeConferencingApp(appType) {
        case "Microsoft Teams":
            if WinExist("ahk_exe ms-teams.exe")
                return "ahk_exe ms-teams.exe"
            if WinExist("ahk_exe Teams.exe")
                return "ahk_exe Teams.exe"
            return "ahk_exe ms-teams.exe"
        case "Google Meet":
            for spec in ["Meet ahk_exe chrome.exe", "Meet ahk_exe msedge.exe", "Meet ahk_exe firefox.exe", "Meet ahk_exe brave.exe"] {
                if WinExist(spec)
                    return spec
            }
            return "Meet ahk_exe chrome.exe"
        default:
            return "ahk_exe Zoom.exe"
    }
}

GetActiveConferencingMuteHotkey(cfg) {
    if (!IsObject(cfg))
        return "!a"
    appType := cfg.HasOwnProp("ConferencingApp") ? NormalizeConferencingApp(cfg.ConferencingApp) : "Zoom"
    switch appType {
        case "Microsoft Teams":
            return (cfg.HasOwnProp("TeamsMuteHotkey") && cfg.TeamsMuteHotkey != "") ? cfg.TeamsMuteHotkey : "^+m"
        case "Google Meet":
            return (cfg.HasOwnProp("MeetMuteHotkey") && cfg.MeetMuteHotkey != "") ? cfg.MeetMuteHotkey : "^d"
        default:
            return (cfg.HasOwnProp("ZoomMuteHotkey") && cfg.ZoomMuteHotkey != "") ? cfg.ZoomMuteHotkey : "!a"
    }
}

ShouldOptimisticallyFlipMute(cfg, state) {
    zoomMonActive := (IsObject(state) && state.HasOwnProp("zoomConnected") && state.zoomConnected
        && (!IsObject(cfg) || !cfg.HasOwnProp("EnableZoom") || cfg.EnableZoom)
        && (!IsObject(cfg) || !cfg.HasOwnProp("EnableWS") || !cfg.EnableWS))
    obsMonActive := (IsObject(state) && state.HasOwnProp("obsConnected") && state.obsConnected)
    mode := (IsObject(cfg) && cfg.HasOwnProp("AudioRoutingMode")) ? cfg.AudioRoutingMode : 1
    if (mode == 2)
        return !zoomMonActive
    if (mode == 3)
        return !(obsMonActive || zoomMonActive)
    return !obsMonActive
}

TryCoreAudioFallbackMute(cfg, state, targetMuted, source := "CoreAudioFallback") {
    if (!IsObject(cfg) || !IsObject(state))
        return false
    if (cfg.HasOwnProp("EnableCoreAudioFallback") && !cfg.EnableCoreAudioFallback)
        return false
    wantMuted := !!targetMuted
    if (!IsSet(AudioMeter) || !AudioMeter.SetOsMicMute(wantMuted))
        return false
    if (IsSet(DiagnosticLogger))
        try DiagnosticLogger.RecordBreadcrumb("Audio", "CoreAudioFallbackMute", "muted=" (wantMuted ? "1" : "0") " source=" String(source))
    if (IsSet(SyncUIState))
        SyncUIState(cfg, state, wantMuted)
    else {
        state.isMuted := wantMuted
        BroadcastHostRelayMuteState(cfg, state)
    }
    return true
}

DispatchHostMuteToggle(cfg, state) {
    obsOpen := WinExist("ahk_exe obs64.exe")
    appType := cfg.HasOwnProp("ConferencingApp") ? cfg.ConferencingApp : "Zoom"
    confSpec := GetConferencingWindowSpec(appType)
    confHk := GetActiveConferencingMuteHotkey(cfg)
    zoomOpen := WinExist(confSpec)

    if (cfg.AudioRoutingMode == 1) {
        if (state.obsConnected && IsObject(state.obsWs) && SendObsToggleInputMuteGroup(cfg, state, state.obsWs, "HostClickerMute"))
            return true
        if (!obsOpen || cfg.ObsMuteHotkey = "None" || cfg.ObsMuteHotkey = "") {
            if (TryCoreAudioFallbackMute(cfg, state, !state.isMuted, "HostToggleMode1"))
                return true
            SoundPlay "*16"
            return false
        }
        SetKeyDelay -1, 30
        try ControlSend FormatSendKey(cfg.ObsMuteHotkey), , "ahk_exe obs64.exe"
        SetKeyDelay 50, 50
    } else if (cfg.AudioRoutingMode == 2) {
        if (!zoomOpen || confHk = "" || confHk = "None") {
            if (TryCoreAudioFallbackMute(cfg, state, !state.isMuted, "HostToggleMode2"))
                return true
            SoundPlay "*16"
            return false
        }
        SetKeyDelay -1, 30
        try ControlSend FormatSendKey(confHk), , confSpec
        SetKeyDelay 50, 50
    } else if (cfg.AudioRoutingMode == 3) {
        if (state.obsConnected && IsObject(state.obsWs) && SendObsToggleInputMuteGroup(cfg, state, state.obsWs, "HostClickerMute"))
            return true
        obsCanSend := (obsOpen && cfg.ObsMuteHotkey != "None" && cfg.ObsMuteHotkey != "")
        confCanSend := (zoomOpen && confHk != "" && confHk != "None")
        if (!obsCanSend && !confCanSend) {
            if (TryCoreAudioFallbackMute(cfg, state, !state.isMuted, "HostToggleMode3"))
                return true
            SoundPlay "*16"
            return false
        }
        state.IsSyncing := true
        if (state.HasOwnProp("syncSource"))
            state.syncSource := "manual"
        SetKeyDelay -1, 30
        if (obsCanSend)
            try ControlSend FormatSendKey(cfg.ObsMuteHotkey), , "ahk_exe obs64.exe"
        if (confCanSend)
            try ControlSend FormatSendKey(confHk), , confSpec
        SetKeyDelay 50, 50
        SetTimer state.releaseSyncTimerFn, -UIConstants.SYNC_LOCK_TIMEOUT_MS
    } else {
        if (cfg.EnableWS && state.obsConnected && IsObject(state.obsWs) && SendObsToggleInputMuteGroup(cfg, state, state.obsWs, "HostClickerMute"))
            return true
        if (TryCoreAudioFallbackMute(cfg, state, !state.isMuted, "HostToggleMode0"))
            return true
    }

    if (ShouldOptimisticallyFlipMute(cfg, state))
        SyncUIState(cfg, state, !state.isMuted)
    return true
}

ShouldEnableHostInternetRelay(cfg) {
    if (!IsObject(cfg))
        return false
    if (cfg.HasOwnProp("EnableRemoteConnections") && !cfg.EnableRemoteConnections)
        return false
    pairCode := cfg.HasOwnProp("InternetPairingCode") ? Trim(cfg.InternetPairingCode) : ""
    if (pairCode = "")
        return false
    if (cfg.HasOwnProp("RemoteNetworkMode") && cfg.RemoteNetworkMode = "Internet")
        return true
    if (cfg.HasOwnProp("AudioRoutingMode") && cfg.AudioRoutingMode == 2)
        return true
    return false
}

IsRemoteUsingInternetChannel(cfg, state := "") {
    if (IsObject(cfg) && cfg.HasOwnProp("NetworkMode") && cfg.NetworkMode = "Internet")
        return true
    if (IsObject(state) && state.HasOwnProp("usingRelayFallback") && state.usingRelayFallback)
        return true
    return false
}

ShouldRemoteFallbackToRelay(cfg, state := "") {
    if (!IsObject(cfg))
        return false
    if (cfg.HasOwnProp("NetworkMode") && cfg.NetworkMode = "Internet")
        return false
    if (cfg.HasOwnProp("EnableRelayFallback") && !cfg.EnableRelayFallback)
        return false
    pairCode := cfg.HasOwnProp("InternetPairingCode") ? Trim(cfg.InternetPairingCode) : ""
    if (pairCode = "")
        return false
    if (IsObject(state) && state.HasOwnProp("usingRelayFallback") && state.usingRelayFallback)
        return false
    return true
}

IsRemoteUsingBridgeChannel(cfg, state := "") {
    return IsObject(state) && state.HasOwnProp("usingBridge") && state.usingBridge && state.HasOwnProp("obsConnected") && state.obsConnected && IsObject(state.obsWs)
}

IsRemoteUsingDirectObsChannel(cfg, state := "") {
    return IsObject(state) && state.HasOwnProp("obsConnected") && state.obsConnected && IsObject(state.obsWs)
        && (!state.HasOwnProp("usingBridge") || !state.usingBridge)
        && !IsRemoteUsingInternetChannel(cfg, state)
}

DispatchRemoteSetMute(cfg, state, targetMuted) {
    valStr := targetMuted ? "1" : "0"
    if (IsRemoteUsingInternetChannel(cfg, state)) {
        topic := GetInternetRelayTopic(cfg.InternetPairingCode)
        authTok := GetInternetRelayAuthToken(cfg.InternetPairingCode, cfg.ObsPassword)
        mockWs := (state.HasOwnProp("relayMockWs") && IsObject(state.relayMockWs)) ? state.relayMockWs : ""
        if (!PublishInternetRelayPacket(topic, FormatRelayPacket("remote", "set_mute", valStr, authTok), "https://ntfy.sh", mockWs)) {
            ToolTip "PresenterSync Remote: Internet Relay unreachable"
            SetTimer () => ToolTip(), -2000
            return false
        }
        return true
    }

    if (IsRemoteUsingBridgeChannel(cfg, state)) {
        devId := (IsObject(cfg) && cfg.HasOwnProp("DeviceId") && cfg.DeviceId != "") ? EscapeJsonStr(cfg.DeviceId) : "win-default"
        payload := '{"type":"set_mute","isMuted":' (targetMuted ? "true" : "false") ',"deviceId":"' devId '","source":"hud"}'
        if (!TrySendWsText(state.obsWs, payload)) {
            ToolTip "PresenterSync Remote: Host Bridge disconnected"
            SetTimer () => ToolTip(), -2000
            return false
        }
        return true
    }

    if (!IsObject(state) || !IsObject(state.obsWs)) {
        ToolTip "PresenterSync Remote: Not connected to OBS host"
        SetTimer () => ToolTip(), -2000
        return false
    }
    escMic := EscapeJsonStr(cfg.TargetMicName)
    if (!SendObsRequest(state.obsWs, "SetInputMute", "RemoteClickerSetMute", '{"inputName":"' escMic '","inputMuted":' (targetMuted ? "true" : "false") '}')) {
        ToolTip "PresenterSync Remote: Not connected to OBS host"
        SetTimer () => ToolTip(), -2000
        return false
    }
    return true
}

DispatchRemoteMuteToggle(cfg, state) {
    if (IsRemoteUsingInternetChannel(cfg, state)) {
        topic := GetInternetRelayTopic(cfg.InternetPairingCode)
        authTok := GetInternetRelayAuthToken(cfg.InternetPairingCode, cfg.ObsPassword)
        mockWs := (state.HasOwnProp("relayMockWs") && IsObject(state.relayMockWs)) ? state.relayMockWs : ""
        if (!PublishInternetRelayPacket(topic, FormatRelayPacket("remote", "toggle_mute", "1", authTok), "https://ntfy.sh", mockWs)) {
            ToolTip "PresenterSync Remote: Internet Relay unreachable"
            SetTimer () => ToolTip(), -2000
            return false
        }
        return true
    }

    if (IsRemoteUsingBridgeChannel(cfg, state)) {
        devId := (IsObject(cfg) && cfg.HasOwnProp("DeviceId") && cfg.DeviceId != "") ? EscapeJsonStr(cfg.DeviceId) : "win-default"
        payload := '{"type":"toggle_mute","deviceId":"' devId '","source":"clicker"}'
        if (!TrySendWsText(state.obsWs, payload)) {
            ToolTip "PresenterSync Remote: Host Bridge disconnected"
            SetTimer () => ToolTip(), -2000
            return false
        }
        return true
    }

    if (!SendObsToggleInputMute(state.obsWs, cfg.TargetMicName, "RemoteClickerMute")) {
        ToolTip "PresenterSync Remote: Not connected to OBS host"
        SetTimer () => ToolTip(), -2000
        return false
    }
    return true
}

EscapeJsonStr(str) {
    s := StrReplace(String(str), "\", "\\")
    s := StrReplace(s, '"', '\"')
    s := StrReplace(s, "`b", "\b")
    s := StrReplace(s, "`f", "\f")
    s := StrReplace(s, "`r", "\r")
    s := StrReplace(s, "`n", "\n")
    s := StrReplace(s, "`t", "\t")
    return s
}

UnescapeJsonStr(str) {
    s := String(str)
    out := ""
    i := 1
    len := StrLen(s)
    while (i <= len) {
        ch := SubStr(s, i, 1)
        if (ch = "\" && i < len) {
            nxt := SubStr(s, i + 1, 1)
            switch nxt {
                case '"': out .= '"'
                case "\": out .= "\"
                case "/": out .= "/"
                case "b": out .= "`b"
                case "f": out .= "`f"
                case "n": out .= "`n"
                case "r": out .= "`r"
                case "t": out .= "`t"
                case "u":
                    if (i + 5 <= len && RegExMatch(SubStr(s, i + 2, 4), "^[0-9A-Fa-f]{4}$")) {
                        out .= Chr(Integer("0x" SubStr(s, i + 2, 4)))
                        i += 6
                        continue
                    }
                    out .= "\u"
                default: out .= nxt
            }
            i += 2
        } else {
            out .= ch
            i += 1
        }
    }
    return out
}

ClearObsNetworkToolTip() {
    ToolTip()
}

TrySendWsText(ws, payload) {
    if (!IsObject(ws))
        return false
    try {
        ws.sendText(payload)
        return true
    } catch {
        return false
    }
}

SendObsRequest(ws, requestType, requestId, requestDataJson := "") {
    dataPart := (requestDataJson != "") ? (',"requestData":' requestDataJson) : ""
    payload := '{"op":6,"d":{"requestType":"' requestType '","requestId":"' requestId '"' dataPart '}}'
    return TrySendWsText(ws, payload)
}

SendObsToggleInputMute(ws, micName, requestId := "HostClickerMute") {
    escMic := EscapeJsonStr(micName)
    return SendObsRequest(ws, "ToggleInputMute", requestId, '{"inputName":"' escMic '"}')
}

SendObsSetInputMute(ws, micName, muted, requestId := "ZoomSyncObsMute") {
    escMic := EscapeJsonStr(micName)
    mutedStr := muted ? "true" : "false"
    return SendObsRequest(ws, "SetInputMute", requestId, '{"inputName":"' escMic '","inputMuted":' mutedStr '}')
}

GetAllMutedAudioSources(cfg) {
    sources := []
    seen := Map()
    if (!IsObject(cfg))
        return sources
    primary := cfg.HasOwnProp("targetMicName") ? Trim(String(cfg.targetMicName))
        : (cfg.HasOwnProp("TargetMicName") ? Trim(String(cfg.TargetMicName)) : "")
    if (primary != "") {
        sources.Push(primary)
        seen[StrLower(primary)] := true
    }
    if (cfg.HasOwnProp("SecondaryAudioSources") && Trim(String(cfg.SecondaryAudioSources)) != "") {
        for _, rawItem in StrSplit(String(cfg.SecondaryAudioSources), [",", ";"]) {
            item := Trim(rawItem)
            if (item != "" && !seen.Has(StrLower(item))) {
                seen[StrLower(item)] := true
                sources.Push(item)
            }
        }
    }
    return sources
}

SendObsSetInputMuteGroup(cfg, ws, muted, requestId := "ZoomSyncObsMute") {
    sources := GetAllMutedAudioSources(cfg)
    if (sources.Length == 0)
        return false
    anySent := false
    for idx, srcName in sources {
        reqId := (idx == 1) ? requestId : (requestId "_" idx)
        if (SendObsSetInputMute(ws, srcName, muted, reqId))
            anySent := true
    }
    return anySent
}

SendObsToggleInputMuteGroup(cfg, state, ws, requestId := "HostClickerMute") {
    sources := GetAllMutedAudioSources(cfg)
    if (sources.Length == 0)
        return false
    if (sources.Length == 1)
        return SendObsToggleInputMute(ws, sources[1], requestId)
    targetMuted := (IsObject(state) && state.HasOwnProp("isMuted")) ? !state.isMuted : true
    return SendObsSetInputMuteGroup(cfg, ws, targetMuted, requestId)
}

SendObsBroadcastCloseRemote(ws, requestId := "ManualCloseRemote") {
    return SendObsRequest(ws, "BroadcastCustomEvent", requestId, '{"eventData":{"source":"PresenterSync","command":"CloseRemote"}}')
}

; Defer WebSocket shutdown past WinHTTP's synchronous read-callback frame so
; context buffers remain valid until WINHTTP_STATUS_READ_WRITE_COMPLETE exits.
SafeCloseWebSocketDeferred(ws, delayMs := 60) {
    if (!IsObject(ws))
        return
    SetTimer(() => _TryShutdownWsDeferred(ws), -Max(15, Integer(delayMs)))
}

_TryShutdownWsDeferred(ws) {
    if (IsObject(ws))
        try ws.shutdown()
}

GenerateInternetPairingCode() {
    chars := "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
    p1 := "", p2 := ""
    Loop 4 {
        p1 .= SubStr(chars, Random(1, StrLen(chars)), 1)
        p2 .= SubStr(chars, Random(1, StrLen(chars)), 1)
    }
    return "PS-" p1 "-" p2
}

GetInternetRelayTopic(pairingCode) {
    clean := StrUpper(Trim(pairingCode))
    if (clean = "")
        return ""
    hash := HashSHA256_Base64("PresenterSync_RelayTopic_v1|" clean)
    safe := RegExReplace(hash, "[^a-zA-Z0-9]", "")
    return "psync_" SubStr(safe, 1, 28)
}

GetInternetRelayAuthToken(pairingCode, password := "") {
    clean := StrUpper(Trim(pairingCode))
    hash := HashSHA256_Base64("PresenterSync_RelayAuth_v1|" clean "|" password)
    return RegExReplace(hash, "[^a-zA-Z0-9]", "")
}

FormatRelayPacket(src, cmd, data, authToken) {
    return "PSRELAY|" src "|" cmd "|" data "|" authToken
}

ParseRelayPacket(rawMsg) {
    msg := (Type(rawMsg) == "Buffer") ? StrGet(rawMsg, "UTF-8") : String(rawMsg)
    if RegExMatch(msg, 'PSRELAY\|([^|"]*)\|([^|"]*)\|([^|"]*)\|([^|"\r\n\s}]*)', &m) {
        return {src: m[1], cmd: m[2], data: m[3], auth: m[4]}
    }
    return ""
}

PublishInternetRelayPacket(topic, packetStr, relayBaseUrl := "https://ntfy.sh", mockTargetWs := "") {
    static activeRequests := []
    if (topic = "" || packetStr = "")
        return false
    if IsObject(mockTargetWs)
        return TrySendWsText(mockTargetWs, packetStr)
    try {
        baseUrl := RTrim(relayBaseUrl != "" ? relayBaseUrl : "https://ntfy.sh", "/")
        whr := ComObject("WinHttp.WinHttpRequest.5.1")
        whr.Open("POST", baseUrl "/" topic, true)
        whr.SetRequestHeader("Cache-Control", "no-cache")
        whr.Send(packetStr)
        activeRequests.Push(whr)
        if (activeRequests.Length > 8)
            activeRequests.RemoveAt(1)
        return true
    } catch {
        return false
    }
}

BroadcastHostRelayDirectorState(cfg, state) {
    if (!IsObject(cfg) || !IsObject(state))
        return false
    if (!ShouldEnableHostInternetRelay(cfg))
        return false
    topic := GetInternetRelayTopic(cfg.HasOwnProp("InternetPairingCode") ? cfg.InternetPairingCode : "")
    if (topic = "")
        return false
    auth := GetInternetRelayAuthToken(cfg.InternetPairingCode, cfg.obsPassword)
    standby := (state.HasOwnProp("isStandby") && state.isStandby) ? "1" : "0"
    recSt := state.HasOwnProp("recState") ? Integer(state.recState) : 0
    tSt := state.HasOwnProp("timerState") ? String(state.timerState) : "stopped"
    tRem := state.HasOwnProp("timerRemainingSec") ? Integer(state.timerRemainingSec) : 600
    tPre := state.HasOwnProp("timerPresetSec") ? Integer(state.timerPresetSec) : 600
    scene := state.HasOwnProp("currentSceneName") ? StrReplace(StrReplace(String(state.currentSceneName), "|", "/"), ";", ",") : "Scene"
    payload := standby ";" recSt ";" tSt ";" tRem ";" tPre ";" scene
    pkt := FormatRelayPacket("host", "dir_state", payload, auth)
    mockWs := (state.HasOwnProp("relayMockWs") && IsObject(state.relayMockWs)) ? state.relayMockWs : ""
    return PublishInternetRelayPacket(topic, pkt, "https://ntfy.sh", mockWs)
}

BroadcastHostRelayMuteState(cfg, state) {
    if (!IsObject(cfg) || !IsObject(state))
        return false
    HostBridgeBroadcastMuteState(cfg, state)
    if (!ShouldEnableHostInternetRelay(cfg))
        return false
    topic := GetInternetRelayTopic(cfg.HasOwnProp("InternetPairingCode") ? cfg.InternetPairingCode : "")
    if (topic = "")
        return false
    auth := GetInternetRelayAuthToken(cfg.InternetPairingCode, cfg.obsPassword)
    pkt := FormatRelayPacket("host", "state", state.isMuted ? "1" : "0", auth)
    mockWs := (state.HasOwnProp("relayMockWs") && IsObject(state.relayMockWs)) ? state.relayMockWs : ""
    return PublishInternetRelayPacket(topic, pkt, "https://ntfy.sh", mockWs)
}

UpdateHostInternetRelay(cfg, state) {
    if (!IsObject(cfg) || !IsObject(state))
        return
    if (state.HasOwnProp("relayTimerFn") && state.relayTimerFn)
        SetTimer state.relayTimerFn, 0
    if (ShouldEnableHostInternetRelay(cfg)) {
        if (!state.relayConnected && state.HasOwnProp("relayTimerFn") && state.relayTimerFn)
            SetTimer state.relayTimerFn, -80
    } else {
        state.relayConnected := false
        if IsObject(state.relayWs) {
            try state.relayWs.shutdown()
            state.relayWs := ""
        }
    }
}

ConnectHostInternetRelay(cfg, state) {
    if (state.HasOwnProp("relayTimerFn") && state.relayTimerFn)
        SetTimer state.relayTimerFn, 0
    if (!ShouldEnableHostInternetRelay(cfg) || state.relayConnected)
        return
    topic := GetInternetRelayTopic(cfg.InternetPairingCode)
    if (topic = "")
        return
    if IsObject(state.relayWs) {
        try state.relayWs.shutdown()
        state.relayWs := ""
    }
    wsUrl := "wss://ntfy.sh/" topic "/ws"
    try {
        state.relayWs := WebSocket(wsUrl, {
            message: HandleHostRelayMessage.Bind(cfg, state),
            close: HandleHostRelayClose.Bind(cfg, state)
        }, true, "", 4000)
    } catch {
        state.relayWs := ""
        if (ShouldEnableHostInternetRelay(cfg) && state.HasOwnProp("relayTimerFn") && state.relayTimerFn)
            SetTimer state.relayTimerFn, -3000
    }
}

HandleHostRelayClose(cfg, state, ws, status, reason) {
    if IsObject(ws)
        try ws.shutdown()
    if (IsObject(ws) && IsObject(state.relayWs) && state.relayWs != ws)
        return
    if (state.relayWs == ws)
        state.relayWs := ""
    state.relayConnected := false
    if (state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn)
        try state.refreshHelpFn.Call()
    if (ShouldEnableHostInternetRelay(cfg) && state.HasOwnProp("relayTimerFn") && state.relayTimerFn)
        SetTimer state.relayTimerFn, -3000
}

HandleHostRelayMessage(cfg, state, ws, rawMsg) {
    if (IsObject(ws) && IsObject(state.relayWs) && ws != state.relayWs)
        return
    msg := (Type(rawMsg) == "Buffer") ? StrGet(rawMsg, "UTF-8") : String(rawMsg)
    if RegExMatch(msg, '"event"\s*:\s*"open"') {
        state.relayConnected := true
        BroadcastHostRelayMuteState(cfg, state)
        if (state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn)
            try state.refreshHelpFn.Call()
        return
    }
    pkt := ParseRelayPacket(msg)
    if (!IsObject(pkt) || pkt.src != "remote")
        return

    topic := GetInternetRelayTopic(cfg.InternetPairingCode)
    expectedAuth := GetInternetRelayAuthToken(cfg.InternetPairingCode, cfg.obsPassword)
    mockWs := (state.HasOwnProp("relayMockWs") && IsObject(state.relayMockWs)) ? state.relayMockWs : ""
    if (pkt.auth != expectedAuth) {
        PublishInternetRelayPacket(topic, FormatRelayPacket("host", "auth_error", "0", "none"), "https://ntfy.sh", mockWs)
        return
    }

    if (pkt.cmd = "sync_req") {
        BroadcastHostRelayMuteState(cfg, state)
        hasDirActivity := (state.HasOwnProp("isStandby") && state.isStandby)
            || (state.HasOwnProp("timerState") && state.timerState != "stopped")
            || (state.HasOwnProp("recState") && state.recState > 0)
        if (hasDirActivity)
            BroadcastHostRelayDirectorState(cfg, state)
    } else if (pkt.cmd = "toggle_mute") {
        ExecuteHostRemoteToggleMute(cfg, state)
    } else if (pkt.cmd = "set_mute") {
        wantMuted := (StrLower(Trim(String(pkt.data))) = "1" || StrLower(Trim(String(pkt.data))) = "true")
        ExecuteHostRemoteSetMute(cfg, state, wantMuted)
    } else if (pkt.cmd = "toggle_record") {
        ExecuteHostToggleRecord(cfg, state)
    } else if (pkt.cmd = "pause_record") {
        ExecuteHostPauseRecord(cfg, state)
    } else if (pkt.cmd = "split_record") {
        ExecuteHostSplitRecord(cfg, state)
    } else if (pkt.cmd = "toggle_standby") {
        ExecuteHostToggleStandby(cfg, state)
    } else if (pkt.cmd = "switch_scene") {
        ExecuteHostSwitchScene(cfg, state, pkt.data)
    } else if (pkt.cmd = "transition_scene") {
        if (IsObject(state) && state.HasOwnProp("triggerTransitionFn") && IsObject(state.triggerTransitionFn))
            state.triggerTransitionFn.Call()
        else
            TriggerObsSceneTransition(cfg, state, true)
    } else if (pkt.cmd = "timer_start") {
        dur := IsInteger(Trim(String(pkt.data))) ? Integer(Trim(String(pkt.data))) : 0
        StartHostPresenterTimer(cfg, state, dur)
    } else if (pkt.cmd = "timer_pause") {
        PauseHostPresenterTimer(cfg, state)
    } else if (pkt.cmd = "timer_reset") {
        dur := IsInteger(Trim(String(pkt.data))) ? Integer(Trim(String(pkt.data))) : 0
        ResetHostPresenterTimer(cfg, state, dur)
    } else if (pkt.cmd = "stage_nudge") {
        sep := InStr(pkt.data, ";")
        if (!sep)
            sep := InStr(pkt.data, "|")
        nSender := sep > 0 ? SubStr(pkt.data, 1, sep - 1) : "Remote"
        nMsg := sep > 0 ? SubStr(pkt.data, sep + 1) : pkt.data
        BroadcastHostStageNudge(cfg, state, nMsg, nSender)
    }
}

ExecuteHostRemoteToggleMute(cfg, state) {
    if (!IsObject(cfg) || !IsObject(state))
        return false
    if (cfg.AudioRoutingMode != 2 && state.obsConnected && IsObject(state.obsWs) && SendObsToggleInputMuteGroup(cfg, state, state.obsWs, "HostClickerMute"))
        return true
    return _DispatchHostRemoteControlSend(cfg, state, !state.isMuted)
}

ExecuteHostRemoteSetMute(cfg, state, targetMuted) {
    if (!IsObject(cfg) || !IsObject(state))
        return false
    wantMuted := !!targetMuted
    if (cfg.AudioRoutingMode != 2 && state.obsConnected && IsObject(state.obsWs) && SendObsSetInputMuteGroup(cfg, state.obsWs, wantMuted, "HostRemoteSetMute")) {
        if (!!state.isMuted = wantMuted)
            BroadcastHostRelayMuteState(cfg, state)
        return true
    }
    if (!!state.isMuted != wantMuted)
        return _DispatchHostRemoteControlSend(cfg, state, wantMuted)
    BroadcastHostRelayMuteState(cfg, state)
    return true
}

ExecuteHostToggleRecord(cfg, state) {
    if (!IsObject(cfg) || !IsObject(state))
        return false
    if (cfg.EnableWS && state.obsConnected && IsObject(state.obsWs)) {
        return SendObsRequest(state.obsWs, "ToggleRecord", "ClickToggleRec")
    } else if (cfg.EnableZoom && state.zoomConnected && cfg.HasOwnProp("ZoomRecHotkey") && cfg.ZoomRecHotkey != "" && cfg.ZoomRecHotkey != "None") {
        confSpec := GetConferencingWindowSpec(cfg.HasOwnProp("ConferencingApp") ? cfg.ConferencingApp : "Zoom")
        SetKeyDelay -1, 30
        try ControlSend(FormatSendKey(cfg.ZoomRecHotkey), , confSpec)
        SetKeyDelay 50, 50
        state.zoomRecGraceUntil := A_TickCount + UIConstants.ZOOM_REC_GRACE_MS
        SyncRecState(cfg, state, state.recState == 0 ? 1 : 0)
        return true
    } else {
        SyncRecState(cfg, state, state.recState == 0 ? 1 : 0)
        return true
    }
}

ExecuteHostSwitchScene(cfg, state, sceneName) {
    if (!IsObject(cfg) || !IsObject(state))
        return false
    clean := Trim(String(sceneName))
    if (clean = "")
        return false
    if (state.HasOwnProp("obsSceneSwitchFn") && IsObject(state.obsSceneSwitchFn)) {
        res := state.obsSceneSwitchFn.Call(clean)
        if (res = false)
            return false
        if (IsSet(SyncSceneState))
            SyncSceneState(cfg, state, clean)
        else {
            if (state.HasOwnProp("currentSceneName") && state.currentSceneName != "" && state.currentSceneName != clean)
                state.previousProgramScene := state.currentSceneName
            state.currentSceneName := clean
        }
        BroadcastHostRelayDirectorState(cfg, state)
        return true
    }
    if (cfg.EnableWS && state.obsConnected && IsObject(state.obsWs)) {
        ok := SendObsRequest(state.obsWs, "SetCurrentProgramScene", "SwitchScene", '{"sceneName":"' EscapeJsonStr(clean) '"}')
        if (ok) {
            if (IsSet(SyncSceneState))
                SyncSceneState(cfg, state, clean)
            else {
                if (state.HasOwnProp("currentSceneName") && state.currentSceneName != "" && state.currentSceneName != clean)
                    state.previousProgramScene := state.currentSceneName
                state.currentSceneName := clean
            }
            BroadcastHostRelayDirectorState(cfg, state)
        }
        return ok
    }
    return false
}

TriggerObsSceneTransition(cfg, state, fromHudClick := false) {
    static lastTick := 0
    if (!IsObject(cfg) || !IsObject(state))
        return false
    now := A_TickCount
    if (lastTick != 0 && (now - lastTick < 25))
        return false
    if (!fromHudClick && (!cfg.HasOwnProp("EnablePointerTransition") || !cfg.EnablePointerTransition))
        return false
    lastTick := now

    t0 := A_TickCount
    if (IsSet(DiagnosticLogger))
        DiagnosticLogger.RecordBreadcrumb("Input", "TriggerObsSceneTransition", fromHudClick ? "hud_or_remote" : "pointer")

    dispatched := false
    detail := ""
    if (state.HasOwnProp("obsConnected") && state.obsConnected && state.HasOwnProp("obsWs") && IsObject(state.obsWs)) {
        if (state.HasOwnProp("studioModeActive") && state.studioModeActive) {
            dispatched := SendObsRequest(state.obsWs, "TriggerStudioModeTransition", "HostSceneTransition")
            detail := "ws:TriggerStudioModeTransition"
        } else {
            prevScene := state.HasOwnProp("previewSceneName") ? state.previewSceneName : ""
            curScene := state.HasOwnProp("currentSceneName") ? state.currentSceneName : ""
            prevProg := state.HasOwnProp("previousProgramScene") ? state.previousProgramScene : ""
            targetScene := (prevScene != "" && prevScene != curScene) ? prevScene : prevProg
            if (targetScene != "") {
                dispatched := SendObsRequest(state.obsWs, "SetCurrentProgramScene", "HostSceneTransition", '{"sceneName":"' EscapeJsonStr(targetScene) '"}')
                detail := "ws:SetCurrentProgramScene:" targetScene
            }
        }
    } else if (WinExist("ahk_exe obs64.exe") && cfg.HasOwnProp("ObsTransitionHotkey") && cfg.ObsTransitionHotkey != "None" && cfg.ObsTransitionHotkey != "") {
        SetKeyDelay -1, 0
        try ControlSend FormatSendKey(cfg.ObsTransitionHotkey), , "ahk_exe obs64.exe"
        SetKeyDelay -1, -1
        dispatched := true
        detail := "controlsend:" cfg.ObsTransitionHotkey
    }

    if (IsSet(DiagnosticLogger))
        DiagnosticLogger.CheckLatency("Input", "TriggerObsSceneTransition", t0, 120, detail)
    return dispatched
}

ExecuteHostPauseRecord(cfg, state) {
    if (!IsObject(cfg) || !IsObject(state))
        return false
    if (state.HasOwnProp("obsRecPauseFn") && IsObject(state.obsRecPauseFn)) {
        res := state.obsRecPauseFn.Call()
        if (res = false)
            return false
        if (state.recState == 1 || state.recState == 2)
            SyncRecState(cfg, state, state.recState == 1 ? 2 : 1)
        return true
    }
    if (cfg.EnableWS && state.obsConnected && IsObject(state.obsWs)) {
        ok := SendObsRequest(state.obsWs, "ToggleRecordPause", "HostPauseRec")
        if (ok && (state.recState == 1 || state.recState == 2))
            SyncRecState(cfg, state, state.recState == 1 ? 2 : 1)
        return ok
    }
    if (cfg.EnableZoom && state.zoomConnected && cfg.HasOwnProp("ZoomPauseHotkey") && cfg.ZoomPauseHotkey != "" && cfg.ZoomPauseHotkey != "None") {
        confSpec := GetConferencingWindowSpec(cfg.HasOwnProp("ConferencingApp") ? cfg.ConferencingApp : "Zoom")
        SetKeyDelay -1, 30
        try ControlSend(FormatSendKey(cfg.ZoomPauseHotkey), , confSpec)
        SetKeyDelay 50, 50
        state.zoomRecGraceUntil := A_TickCount + UIConstants.ZOOM_REC_GRACE_MS
        if (state.recState == 1 || state.recState == 2)
            SyncRecState(cfg, state, state.recState == 1 ? 2 : 1)
        return true
    }
    return false
}

ExecuteHostSplitRecord(cfg, state) {
    if (!IsObject(cfg) || !IsObject(state))
        return false
    if (IsSet(SessionTimeline))
        SessionTimeline.Record("Recording", "Chapter Split Marker", state, cfg.targetMicName)
    if (state.HasOwnProp("obsRecSplitFn") && IsObject(state.obsRecSplitFn)) {
        res := state.obsRecSplitFn.Call()
        return (res != false)
    }
    if (cfg.EnableWS && state.obsConnected && IsObject(state.obsWs)) {
        return SendObsRequest(state.obsWs, "SplitRecordFile", "HostSplitRec")
    }
    return false
}

ExecuteHostToggleStandby(cfg, state, enterStandby := "") {
    if (!IsObject(cfg) || !IsObject(state))
        return false
    curStandby := state.HasOwnProp("isStandby") ? !!state.isStandby : false
    wantStandby := (enterStandby == "") ? !curStandby : !!enterStandby
    if (wantStandby == curStandby)
        return true

    brbScene := (cfg.HasOwnProp("StandbySceneName") && Trim(cfg.StandbySceneName) != "") ? Trim(cfg.StandbySceneName) : "BRB"
    if (wantStandby) {
        prevScene := state.HasOwnProp("currentSceneName") ? String(state.currentSceneName) : "Scene"
        state.standbySnapshot := {
            muted: (state.HasOwnProp("isMuted") ? !!state.isMuted : false),
            scene: prevScene,
            recWasActive: (state.HasOwnProp("recState") && state.recState == 1)
        }
        if (!state.isMuted)
            ExecuteHostRemoteSetMute(cfg, state, true)
        if ((cfg.EnableWS && state.obsConnected && IsObject(state.obsWs)) || (state.HasOwnProp("obsSceneSwitchFn") && IsObject(state.obsSceneSwitchFn)))
            ExecuteHostSwitchScene(cfg, state, brbScene)
        if (state.HasOwnProp("recState") && state.recState == 1)
            ExecuteHostPauseRecord(cfg, state)
        state.isStandby := true
        if (IsSet(ShowStageNudgeBanner) && (!state.HasOwnProp("suppressNudgeBanners") || !state.suppressNudgeBanners))
            ShowStageNudgeBanner("Standby Mode ON (" brbScene ") — Mic Muted & Rec Paused", "F59E0B", 3500, "Director")
    } else {
        snap := state.HasOwnProp("standbySnapshot") ? state.standbySnapshot : ""
        state.isStandby := false
        state.standbySnapshot := ""
        if (IsObject(snap)) {
            if (snap.HasOwnProp("scene") && snap.scene != "" && ((cfg.EnableWS && state.obsConnected && IsObject(state.obsWs)) || (state.HasOwnProp("obsSceneSwitchFn") && IsObject(state.obsSceneSwitchFn))))
                ExecuteHostSwitchScene(cfg, state, snap.scene)
            if (snap.HasOwnProp("recWasActive") && snap.recWasActive && state.HasOwnProp("recState") && state.recState == 2)
                ExecuteHostPauseRecord(cfg, state)
            if (snap.HasOwnProp("muted"))
                ExecuteHostRemoteSetMute(cfg, state, snap.muted)
        }
        if (IsSet(ShowStageNudgeBanner) && (!state.HasOwnProp("suppressNudgeBanners") || !state.suppressNudgeBanners))
            ShowStageNudgeBanner("Standby Mode OFF — Session Restored", "10B981", 3200, "Director")
    }
    HostBridgeBroadcastMuteState(cfg, state)
    BroadcastHostRelayDirectorState(cfg, state)
    if (IsSet(SessionTimeline))
        SessionTimeline.Record("Standby", wantStandby ? ("Standby Mode ON (" brbScene ")") : "Standby Mode OFF", state)
    if (state.HasOwnProp("rebuildTrayFn") && state.rebuildTrayFn)
        try state.rebuildTrayFn.Call()
    if (state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn)
        try state.refreshHelpFn.Call()
    return true
}

StartHostPresenterTimer(cfg, state, durationSec := 0) {
    if (!IsObject(state))
        return false
    if (Integer(durationSec) > 0) {
        state.timerPresetSec := Integer(durationSec)
        state.timerRemainingSec := Integer(durationSec)
    } else if (!state.HasOwnProp("timerState") || state.timerState = "stopped") {
        preset := (state.HasOwnProp("timerPresetSec") && Integer(state.timerPresetSec) > 0) ? Integer(state.timerPresetSec) : 600
        state.timerPresetSec := preset
        state.timerRemainingSec := preset
    }
    state.timerState := (state.timerRemainingSec <= 0) ? "overtime" : "running"
    if (state.HasOwnProp("presenterTimerFn") && state.presenterTimerFn)
        SetTimer(state.presenterTimerFn, 1000)
    HostBridgeBroadcastMuteState(cfg, state)
    BroadcastHostRelayDirectorState(cfg, state)
    if (IsSet(SessionTimeline))
        SessionTimeline.Record("Timer", "Countdown Started", state, FormatCountdownClock(state.timerRemainingSec))
    if (state.HasOwnProp("rebuildTrayFn") && state.rebuildTrayFn)
        try state.rebuildTrayFn.Call()
    return true
}

PauseHostPresenterTimer(cfg, state) {
    if (!IsObject(state))
        return false
    cur := state.HasOwnProp("timerState") ? state.timerState : "stopped"
    if (cur = "stopped")
        return StartHostPresenterTimer(cfg, state, 0)
    if (cur = "running" || cur = "overtime") {
        state.timerState := "paused"
        if (state.HasOwnProp("presenterTimerFn") && state.presenterTimerFn)
            SetTimer(state.presenterTimerFn, 0)
    } else if (cur = "paused") {
        state.timerState := (state.timerRemainingSec <= 0) ? "overtime" : "running"
        if (state.HasOwnProp("presenterTimerFn") && state.presenterTimerFn)
            SetTimer(state.presenterTimerFn, 1000)
    }
    HostBridgeBroadcastMuteState(cfg, state)
    BroadcastHostRelayDirectorState(cfg, state)
    if (IsSet(SessionTimeline))
        SessionTimeline.Record("Timer", (state.timerState = "paused") ? "Countdown Paused" : "Countdown Resumed", state, FormatCountdownClock(state.timerRemainingSec))
    if (state.HasOwnProp("rebuildTrayFn") && state.rebuildTrayFn)
        try state.rebuildTrayFn.Call()
    return true
}

ResetHostPresenterTimer(cfg, state, durationSec := 0) {
    if (!IsObject(state))
        return false
    if (state.HasOwnProp("presenterTimerFn") && state.presenterTimerFn)
        SetTimer(state.presenterTimerFn, 0)
    preset := (Integer(durationSec) > 0) ? Integer(durationSec) : ((state.HasOwnProp("timerPresetSec") && Integer(state.timerPresetSec) > 0) ? Integer(state.timerPresetSec) : 600)
    state.timerPresetSec := preset
    state.timerRemainingSec := preset
    state.timerState := "stopped"
    HostBridgeBroadcastMuteState(cfg, state)
    BroadcastHostRelayDirectorState(cfg, state)
    if (IsSet(SessionTimeline))
        SessionTimeline.Record("Timer", "Countdown Reset", state, FormatCountdownClock(preset))
    if (state.HasOwnProp("rebuildTrayFn") && state.rebuildTrayFn)
        try state.rebuildTrayFn.Call()
    return true
}

StepHostPresenterTimerTick(cfg, state) {
    if (!IsObject(state))
        return false
    cur := state.HasOwnProp("timerState") ? state.timerState : "stopped"
    if (cur != "running" && cur != "overtime")
        return false
    prevRem := Integer(state.timerRemainingSec)
    state.timerRemainingSec := prevRem - 1
    if (state.timerRemainingSec <= 0 && cur = "running") {
        state.timerState := "overtime"
        BroadcastHostStageNudge(cfg, state, "Time Up — Overtime (" FormatCountdownClock(state.timerRemainingSec) ")", "Timer", "EF4444")
        return true
    }
    if (prevRem == 121 && state.timerRemainingSec == 120) {
        BroadcastHostStageNudge(cfg, state, "2:00 Remaining", "Timer", "F59E0B")
        return true
    }
    if (Mod(Abs(state.timerRemainingSec), 5) == 0) {
        HostBridgeBroadcastMuteState(cfg, state)
        BroadcastHostRelayDirectorState(cfg, state)
    }
    return true
}

PresenterTimerTick(cfg, state) {
    if (!IsObject(state) || (state.timerState != "running" && state.timerState != "overtime")) {
        if (IsObject(state) && state.HasOwnProp("presenterTimerFn") && state.presenterTimerFn)
            SetTimer(state.presenterTimerFn, 0)
        return
    }
    StepHostPresenterTimerTick(cfg, state)
}

BroadcastHostStageNudge(cfg, state, message, sender := "Stage", accentHex := "F59E0B") {
    msgClean := SubStr(Trim(String(message)), 1, 140)
    if (msgClean = "")
        return false
    senderClean := SubStr(Trim(String(sender)), 1, 40)
    if (senderClean = "")
        senderClean := "Stage"
    accClean := IsSet(NormalizeColorHex) ? NormalizeColorHex(accentHex, "F59E0B") : "F59E0B"
    if (IsSet(ShowStageNudgeBanner) && (!IsObject(state) || !state.HasOwnProp("suppressNudgeBanners") || !state.suppressNudgeBanners))
        ShowStageNudgeBanner(msgClean, accClean, 4500, senderClean)
    HostBridgeBroadcastStageNudge(cfg, state, msgClean, senderClean, accClean)
    if (ShouldEnableHostInternetRelay(cfg)) {
        topic := GetInternetRelayTopic(cfg.HasOwnProp("InternetPairingCode") ? cfg.InternetPairingCode : "")
        if (topic != "") {
            auth := GetInternetRelayAuthToken(cfg.InternetPairingCode, cfg.obsPassword)
            safeMsg := StrReplace(StrReplace(msgClean, "|", "/"), ";", ",")
            safeSender := StrReplace(StrReplace(senderClean, "|", "/"), ";", ",")
            pkt := FormatRelayPacket("host", "nudge", safeSender ";" safeMsg, auth)
            mockWs := (IsObject(state) && state.HasOwnProp("relayMockWs") && IsObject(state.relayMockWs)) ? state.relayMockWs : ""
            PublishInternetRelayPacket(topic, pkt, "https://ntfy.sh", mockWs)
        }
    }
    return true
}

ExecuteHostRemotePptCommand(cfg, state, direction := "next") {
    if (!IsObject(cfg) || !IsObject(state))
        return false
    isPrev := (StrLower(Trim(String(direction))) = "prev")
    fnProp := isPrev ? "pptPrevFn" : "pptNextFn"
    if (state.HasOwnProp(fnProp) && IsObject(state.%fnProp%)) {
        try {
            res := state.%fnProp%.Call()
            if (res != false && IsSet(SessionTimeline))
                SessionTimeline.Record("Slide", isPrev ? "Slide Previous" : "Slide Next", state, "Remote")
            return (res != false)
        } catch {
            return false
        }
    }
    if (!cfg.HasOwnProp("EnablePPT") || !cfg.EnablePPT)
        return false
    fb := TryDispatchFallbackSlideKey(isPrev ? "prev" : "next")
    return fb.handled
}

_DispatchHostRemoteControlSend(cfg, state, nextMuted) {
    obsOpen := WinExist("ahk_exe obs64.exe")
    appType := cfg.HasOwnProp("ConferencingApp") ? cfg.ConferencingApp : "Zoom"
    confSpec := GetConferencingWindowSpec(appType)
    confHk := GetActiveConferencingMuteHotkey(cfg)
    zoomOpen := WinExist(confSpec)
    obsCanSend := ((cfg.AudioRoutingMode == 1 || cfg.AudioRoutingMode == 3) && obsOpen && cfg.ObsMuteHotkey != "None" && cfg.ObsMuteHotkey != "")
    confCanSend := ((cfg.AudioRoutingMode == 2 || cfg.AudioRoutingMode == 3) && zoomOpen && confHk != "" && confHk != "None")
    sentObs := false
    sentConf := false
    if (cfg.AudioRoutingMode == 3 && (obsCanSend || confCanSend)) {
        state.IsSyncing := true
        if (state.HasOwnProp("syncSource"))
            state.syncSource := "manual"
        if (state.HasOwnProp("releaseSyncTimerFn") && state.releaseSyncTimerFn)
            SetTimer state.releaseSyncTimerFn, -UIConstants.SYNC_LOCK_TIMEOUT_MS
    }
    if (obsCanSend) {
        SetKeyDelay -1, 30
        try {
            ControlSend FormatSendKey(cfg.ObsMuteHotkey), , "ahk_exe obs64.exe"
            sentObs := true
        }
        SetKeyDelay 50, 50
    }
    if (confCanSend) {
        SetKeyDelay -1, 30
        try {
            ControlSend FormatSendKey(confHk), , confSpec
            sentConf := true
        }
        SetKeyDelay 50, 50
    }
    if (!sentObs && !sentConf && TryCoreAudioFallbackMute(cfg, state, nextMuted, "HostRemoteControlSend"))
        return true
    if (ShouldOptimisticallyFlipMute(cfg, state))
        SyncUIState(cfg, state, nextMuted)
    else
        BroadcastHostRelayMuteState(cfg, state)
    return true
}

IsLoopbackHost(host) {
    h := StrLower(Trim(String(host), " []"))
    return (h = "127.0.0.1" || h = "localhost" || h = "::1")
}

; Fast non-blocking (<1ms) local TCP listener check so closed localhost OBS/Host ports do not freeze the AHK UI thread for 2s in WinHttpSendRequest.
; Fails open (returns true) on unexpected Win32 API errors so non-standard network stacks remain functional.
IsLocalTcpPortListening(port) {
    try targetPort := Integer(port)
    catch
        return true
    if (targetPort < 1 || targetPort > 65535)
        return false
    v4Checked := false
    for af in [2, 23] {
        sz := 0
        rc := DllCall("iphlpapi\GetExtendedTcpTable", "Ptr", 0, "UInt*", &sz, "Int", 0, "UInt", af, "Int", 3, "UInt", 0, "UInt")
        if (rc == 232 || (rc == 0 && sz <= 4)) {
            if (af == 2)
                v4Checked := true
            continue
        }
        if (af == 23 && rc != 122)
            continue
        if (rc != 122 || sz < 4)
            return true
        buf := Buffer(sz, 0)
        rc := DllCall("iphlpapi\GetExtendedTcpTable", "Ptr", buf.Ptr, "UInt*", &sz, "Int", 0, "UInt", af, "Int", 3, "UInt", 0, "UInt")
        if (rc != 0)
            return (af == 2) ? true : (v4Checked ? false : true)
        if (af == 2)
            v4Checked := true
        cnt := NumGet(buf, 0, "UInt")
        rowSize := (af == 2) ? 24 : 56
        portOff := (af == 2) ? 8 : 20
        if (buf.Size < 4 + cnt * rowSize)
            return true
        Loop cnt {
            base := 4 + (A_Index - 1) * rowSize
            rawPort := NumGet(buf, base + portOff, "UInt")
            hostPort := ((rawPort & 0xFF) << 8) | ((rawPort >> 8) & 0xFF)
            if (hostPort == targetPort)
                return true
        }
    }
    return false
}

SendCloseRemoteSignal(cfg, state) {
    sentLan := false
    sentWan := false
    sentBridge := (HostBridgeBroadcastCloseRemote() > 0)

    ; 1. Dispatch over active OBS WebSocket (LAN Mode)
    if (IsObject(state) && state.obsConnected && IsObject(state.obsWs)) {
        sentLan := SendObsBroadcastCloseRemote(state.obsWs)
    } else if (IsLocalTcpPortListening(4455)) {
        ; One-shot loopback connect to local OBS 127.0.0.1:4455 in case Host WS Sync is currently off
        try {
            tempBox := {ws: ""}
            CleanupTempWs() {
                SetTimer CleanupTempWs, 0
                if IsObject(tempBox.ws) {
                    try tempBox.ws.shutdown()
                    tempBox.ws := ""
                }
            }
            OnTempMsg(wsObj, raw) {
                m := (Type(raw) == "Buffer") ? StrGet(raw, "UTF-8") : String(raw)
                if RegExMatch(m, '"op"\s*:\s*0') {
                    authStr := ""
                    if (RegExMatch(m, '"salt"\s*:\s*"([^"]+)"', &mS) && RegExMatch(m, '"challenge"\s*:\s*"([^"]+)"', &mC)) {
                        sec := HashSHA256_Base64(cfg.obsPassword . mS[1])
                        resp := HashSHA256_Base64(sec . mC[1])
                        authStr := ',"authentication":"' resp '"'
                    }
                    TrySendWsText(wsObj, '{"op":1,"d":{"rpcVersion":1,"eventSubscriptions":0' authStr '}}')
                } else if RegExMatch(m, '"op"\s*:\s*2') {
                    SendObsBroadcastCloseRemote(wsObj)
                    SetTimer CleanupTempWs, -250
                }
            }
            tempBox.ws := WebSocket("ws://127.0.0.1:4455", {
                message: OnTempMsg,
                close: (wsObj, st, re) => CleanupTempWs()
            }, true, "", 1000)
            SetTimer CleanupTempWs, -1200
            sentLan := true
        }
    }

    ; 2. Also dispatch over Internet Relay if Internet Pairing Code is configured
    if (IsObject(cfg) && cfg.HasOwnProp("InternetPairingCode") && cfg.InternetPairingCode != "") {
        topic := GetInternetRelayTopic(cfg.InternetPairingCode)
        auth := GetInternetRelayAuthToken(cfg.InternetPairingCode, cfg.obsPassword)
        mockWs := (IsObject(state) && state.HasOwnProp("relayMockWs") && IsObject(state.relayMockWs)) ? state.relayMockWs : ""
        if (topic != "")
            sentWan := PublishInternetRelayPacket(topic, FormatRelayPacket("host", "close_remote", "1", auth), "https://ntfy.sh", mockWs)
    }

    return (sentLan || sentWan || sentBridge)
}

FormatPassthroughHook(hk) {
    return "~$" RegExReplace(hk, "^[~*$]+")
}

ConnectToOBS(cfg, state) {
    SetTimer state.obsTimerFn, 0
    if (!cfg.EnableWS || state.obsConnected)
        return

    if IsObject(state.obsWs) {
        try state.obsWs.shutdown()
        state.obsWs := ""
    }

    if (!IsLocalTcpPortListening(4455)) {
        if (cfg.EnableWS)
            SetTimer state.obsTimerFn, -UIConstants.OBS_RECONNECT_MS
        return
    }

    try {
        state.obsWs := WebSocket("ws://127.0.0.1:4455", {
            message: HandleObsMessage.Bind(cfg, state),
            close: HandleObsClose.Bind(cfg, state)
        }, true, "", 2000)
    } catch {
        state.obsWs := ""
        if (cfg.EnableWS)
            SetTimer state.obsTimerFn, -UIConstants.OBS_RECONNECT_MS
    }
}

HandleObsClose(cfg, state, ws, status, reason) {
    if IsObject(ws)
        try ws.shutdown()
    if (IsObject(ws) && IsObject(state.obsWs) && state.obsWs != ws)
        return
    if (state.obsWs == ws)
        state.obsWs := ""

    if (!cfg.EnableWS)
        return

    if (!state.obsConnected) {
        if (status == 4009) {
            SetTimer state.obsTimerFn, 0
            newPw := PromptForPassword("OBS WebSocket authentication failed or a password is required.`n`nEnter your OBS WebSocket password (or close to disable WebSocket Sync):")
            if (newPw != "") {
                cfg.obsPassword := newPw
                cfg.Write("Settings", "ObsPassword", newPw)
                BroadcastHostRelayMuteState(cfg, state)
                if state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn
                    try state.refreshHelpFn.Call()
                SetTimer state.obsTimerFn, -100
            } else {
                cfg.obsPassword := ""
                cfg.Write("Settings", "ObsPassword", "")
                cfg.EnableWS := false
                cfg.WriteBool("Settings", "EnableWS", false)
                BroadcastHostRelayMuteState(cfg, state)
                if (state.HasOwnProp("rebuildTrayFn") && state.rebuildTrayFn)
                    try state.rebuildTrayFn.Call()
                UpdateZoomMonitorTimer(cfg, state)
                RefreshHudAppearance(cfg, state)
                if state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn
                    try state.refreshHelpFn.Call()
            }
            return
        }
        SetTimer state.obsTimerFn, -UIConstants.OBS_RECONNECT_MS
        return
    }

    state.obsConnected := false
    state.recordDirectory := ""
    state.streamDropWarn := false
    state._forgotRecSinceTick := 0
    state._streamDropSinceTick := 0
    state._streamDropBackupTriggered := false
    SyncRecState(cfg, state, 0)
    SyncStreamState(cfg, state, 0)
    SyncVCamState(cfg, state, false)
    SyncStudioState(cfg, state, false)
    SyncSceneState(cfg, state, "Scene")
    state.previewSceneName := ""
    state.previousProgramScene := ""
    state.sceneList := []
    if state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn
        try state.refreshHelpFn.Call()
    SetTimer state.obsTimerFn, -UIConstants.OBS_RECONNECT_MS
}

RequestObsInputList(ws := "", state := "") {
    if (!IsObject(ws) && IsObject(state) && state.HasOwnProp("obsWs"))
        ws := state.obsWs
    if (!IsObject(ws))
        return false
    if (IsObject(state) && state.HasOwnProp("obsConnected") && !state.obsConnected)
        return false
    return SendObsRequest(ws, "GetInputList", "InitInputList")
}

IsObsAudioInputKind(kind) {
    k := StrLower(Trim(String(kind)))
    if (k = "")
        return false
    static knownAudioKinds := Map(
        "wasapi_input_capture", true,
        "wasapi_output_capture", true,
        "coreaudio_input_capture", true,
        "coreaudio_output_capture", true,
        "pulse_input_capture", true,
        "pulse_output_capture", true,
        "alsa_input_capture", true,
        "jack_input_capture", true,
        "oss_input_capture", true,
        "asio_input_capture", true,
        "dshow_input", true,
        "ffmpeg_source", true,
        "vlc_source", true,
        "ndi_source", true
    )
    if (knownAudioKinds.Has(k))
        return true
    return (InStr(k, "audio") || InStr(k, "input_capture") || InStr(k, "output_capture"))
}

ParseObsInputList(rawMsg) {
    allInputs := []
    audioInputs := []
    seenAll := Map()
    seenAudio := Map()
    pos := 1
    while (pos := RegExMatch(rawMsg, "\{[^{}]*\}", &objMatch, pos)) {
        objTxt := objMatch[0]
        if (RegExMatch(objTxt, '"inputName"\s*:\s*"((?:[^"\\]|\\.)*)"', &mName)) {
            name := UnescapeJsonStr(mName[1])
            kind := ""
            if (RegExMatch(objTxt, '"inputKind"\s*:\s*"((?:[^"\\]|\\.)*)"', &mKind))
                kind := UnescapeJsonStr(mKind[1])
            if (name != "" && !seenAll.Has(name)) {
                seenAll[name] := true
                allInputs.Push(name)
            }
            if (name != "" && IsObsAudioInputKind(kind) && !seenAudio.Has(name)) {
                seenAudio[name] := true
                audioInputs.Push(name)
            }
        }
        pos += objMatch.Len
    }
    return { all: allInputs, audio: audioInputs }
}

ParseObsSceneList(rawMsg) {
    scenes := []
    seen := Map()
    pos := 1
    while (pos := RegExMatch(rawMsg, '"sceneName"\s*:\s*"((?:[^"\\]|\\.)*)"', &m, pos)) {
        name := UnescapeJsonStr(m[1])
        if (name != "" && !seen.Has(name)) {
            scenes.Push(name)
            seen[name] := true
        }
        pos += m.Len
    }
    if (scenes.Length > 1) {
        rev := []
        Loop scenes.Length
            rev.Push(scenes[scenes.Length - A_Index + 1])
        return rev
    }
    return scenes
}

PollStreamStatus(cfg, state) {
    if (!cfg.EnableWS || !state.obsConnected || !IsObject(state.obsWs) || state.streamState == 0) {
        if (state.HasOwnProp("streamTimerFn") && state.streamTimerFn)
            SetTimer(state.streamTimerFn, 0)
        return
    }
    SendObsRequest(state.obsWs, "GetStreamStatus", "PollStreamStatus")
}

HandleObsMessage(cfg, state, ws, rawMsg) {
    if (IsObject(ws) && IsObject(state.obsWs) && ws != state.obsWs)
        return
    msg := (Type(rawMsg) == "Buffer") ? StrGet(rawMsg, "UTF-8") : String(rawMsg)

    if (!RegExMatch(msg, '"op"\s*:\s*(\d+)', &matchOp))
        return
    opCode := Integer(matchOp[1])

    if (opCode == 0) {
        authString := ""
        if (RegExMatch(msg, '"salt"\s*:\s*"([^"]+)"', &matchSalt) && RegExMatch(msg, '"challenge"\s*:\s*"([^"]+)"', &matchChallenge)) {
            salt := matchSalt[1]
            challenge := matchChallenge[1]

            secret := HashSHA256_Base64(cfg.obsPassword . salt)
            authResponse := HashSHA256_Base64(secret . challenge)
            authString := ',"authentication":"' authResponse '"'
        }

        ; 2047 = EventSubscription::All (all standard low-volume events; excludes 20Hz InputVolumeMeters)
        identifyJson := '{"op":1,"d":{"rpcVersion":1,"eventSubscriptions":2047' authString '}}'
        TrySendWsText(ws, identifyJson)
    }
    else if (opCode == 2) {
        SetTimer state.obsTimerFn, 0
        state.obsConnected := true
        escMic := EscapeJsonStr(cfg.targetMicName)
        SendObsRequest(ws, "GetInputMute", "InitState", '{"inputName":"' escMic '"}')
        SendObsRequest(ws, "GetRecordStatus", "InitRecState")
        SendObsRequest(ws, "GetRecordDirectory", "InitRecordDir")
        SendObsRequest(ws, "GetStudioModeEnabled", "InitStudioState")
        SendObsRequest(ws, "GetCurrentProgramScene", "InitSceneState")
        SendObsRequest(ws, "GetCurrentPreviewScene", "InitPreviewSceneState")
        SendObsRequest(ws, "GetSceneList", "InitSceneList")
        SendObsRequest(ws, "GetStreamStatus", "InitStreamState")
        SendObsRequest(ws, "GetVirtualCamStatus", "InitVCamState")
        RequestObsInputList(ws)
        if state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn
            try state.refreshHelpFn.Call()
    }
    else if (opCode == 5) {
        if (RegExMatch(msg, '"eventType"\s*:\s*"InputMuteStateChanged"')) {
            if (RegExMatch(msg, '"inputName"\s*:\s*"((?:[^"\\]|\\.)*)"', &matchInput) && UnescapeJsonStr(matchInput[1]) == cfg.targetMicName) {
                if (RegExMatch(msg, '"inputMuted"\s*:\s*(true|false)', &matchMuted)) {
                    isMutedOBS := (matchMuted[1] == "true")
                    PushObsMuteToZoom(cfg, state, isMutedOBS)
                    SyncUIState(cfg, state, isMutedOBS)
                }
            }
        }
        else if (InStr(msg, '"eventType":"RecordStateChanged"') || InStr(msg, '"eventType": "RecordStateChanged"')) {
            if (RegExMatch(msg, '"outputState"\s*:\s*"([^"]+)"', &matchRecOut)) {
                outState := matchRecOut[1]
                if (outState = "OBS_WEBSOCKET_OUTPUT_STARTED" || outState = "OBS_WEBSOCKET_OUTPUT_RESUMED")
                    SyncRecState(cfg, state, 1)
                else if (outState = "OBS_WEBSOCKET_OUTPUT_PAUSED")
                    SyncRecState(cfg, state, 2)
                else if (outState = "OBS_WEBSOCKET_OUTPUT_STOPPED")
                    SyncRecState(cfg, state, 0)
            }
        }
        else if (InStr(msg, '"eventType":"StreamStateChanged"') || InStr(msg, '"eventType": "StreamStateChanged"')) {
            if (RegExMatch(msg, '"outputActive"\s*:\s*(true|false)', &matchStrmAct)) {
                active := (matchStrmAct[1] == "true")
                reconn := InStr(msg, "OBS_WEBSOCKET_OUTPUT_RECONNECTING") != 0
                SyncStreamState(cfg, state, reconn ? 2 : (active ? 1 : 0), 0.0, state.HasOwnProp("streamSkippedFrames") ? state.streamSkippedFrames : 0, reconn)
            }
        }
        else if (InStr(msg, '"eventType":"VirtualcamStateChanged"') || InStr(msg, '"eventType": "VirtualcamStateChanged"')) {
            if (RegExMatch(msg, '"outputActive"\s*:\s*(true|false)', &matchVcAct)) {
                SyncVCamState(cfg, state, matchVcAct[1] == "true")
            }
        }
        else if (InStr(msg, '"eventType":"StudioModeStateChanged"') || InStr(msg, '"eventType": "StudioModeStateChanged"')) {
            if (RegExMatch(msg, '"studioModeEnabled"\s*:\s*(true|false)', &matchStudio)) {
                isStudio := (matchStudio[1] == "true")
                SyncStudioState(cfg, state, isStudio)
                if (isStudio && IsObject(ws))
                    SendObsRequest(ws, "GetCurrentPreviewScene", "InitPreviewSceneState")
            }
        }
        else if (InStr(msg, '"eventType":"CurrentProgramSceneChanged"') || InStr(msg, '"eventType": "CurrentProgramSceneChanged"')) {
            if (RegExMatch(msg, '"sceneName"\s*:\s*"((?:[^"\\]|\\.)*)"', &matchScene)) {
                SyncSceneState(cfg, state, UnescapeJsonStr(matchScene[1]))
            }
        }
        else if (InStr(msg, '"eventType":"CurrentPreviewSceneChanged"') || InStr(msg, '"eventType": "CurrentPreviewSceneChanged"')) {
            if (RegExMatch(msg, '"currentPreviewSceneName"\s*:\s*"((?:[^"\\]|\\.)*)"', &matchPrevScene) || RegExMatch(msg, '"sceneName"\s*:\s*"((?:[^"\\]|\\.)*)"', &matchPrevScene)) {
                state.previewSceneName := UnescapeJsonStr(matchPrevScene[1])
            }
        }
        else if (InStr(msg, '"eventType":"SceneListChanged"') || InStr(msg, '"eventType": "SceneListChanged"')) {
            parsedScenes := ParseObsSceneList(msg)
            if (parsedScenes.Length > 0)
                state.sceneList := parsedScenes
            else if IsObject(ws)
                SendObsRequest(ws, "GetSceneList", "InitSceneList")
        }
    }
    else if (opCode == 7) {
        if (InStr(msg, '"requestId":"InitState"') || InStr(msg, '"requestId": "InitState"')) {
            if (RegExMatch(msg, '"result"\s*:\s*false')) {
                TrayTip("Audio source '" cfg.targetMicName "' was not found in OBS Studio.", "PresenterSync", 2)
            } else if (RegExMatch(msg, '"inputMuted"\s*:\s*(true|false)', &matchMuted)) {
                isMutedOBS := (matchMuted[1] == "true")
                PushObsMuteToZoom(cfg, state, isMutedOBS)
                SyncUIState(cfg, state, isMutedOBS)
                BroadcastHostRelayMuteState(cfg, state)
            }
        }
        else if (InStr(msg, '"requestId":"HostClickerMute"') || InStr(msg, '"requestId": "HostClickerMute"')) {
            if (RegExMatch(msg, '"result"\s*:\s*false')) {
                ToolTip("PresenterSync: Audio source '" cfg.targetMicName "' not found in OBS")
                SetTimer(ClearObsNetworkToolTip, -2500)
            }
        }
        else if (InStr(msg, '"requestId":"InitRecState"') || InStr(msg, '"requestId": "InitRecState"')) {
            if (RegExMatch(msg, '"outputActive"\s*:\s*(true|false)', &matchActive)) {
                active := (matchActive[1] == "true")
                paused := false
                if (RegExMatch(msg, '"outputPaused"\s*:\s*(true|false)', &matchPaused))
                    paused := (matchPaused[1] == "true")
                durMs := -1
                if (RegExMatch(msg, '"outputDuration"\s*:\s*(\d+)', &matchDur))
                    durMs := Integer(matchDur[1])
                SyncRecState(cfg, state, active ? (paused ? 2 : 1) : 0, durMs)
            }
        }
        else if (InStr(msg, '"requestId":"InitRecordDir"') || InStr(msg, '"requestId": "InitRecordDir"')) {
            if (RegExMatch(msg, '"recordDirectory"\s*:\s*"((?:[^"\\]|\\.)*)"', &matchRecDir))
                state.recordDirectory := UnescapeJsonStr(matchRecDir[1])
        }
        else if (InStr(msg, '"requestId":"InitStreamState"') || InStr(msg, '"requestId": "InitStreamState"')
            || InStr(msg, '"requestId":"PollStreamStatus"') || InStr(msg, '"requestId": "PollStreamStatus"')) {
            if (RegExMatch(msg, '"outputActive"\s*:\s*(true|false)', &matchStrmAct)) {
                active := (matchStrmAct[1] == "true")
                reconn := false
                if (RegExMatch(msg, '"outputReconnecting"\s*:\s*(true|false)', &matchReconn))
                    reconn := (matchReconn[1] == "true")
                cong := 0.0
                if (RegExMatch(msg, '"outputCongestion"\s*:\s*([0-9.]+)', &matchCong))
                    cong := Float(matchCong[1])
                skipped := 0
                if (RegExMatch(msg, '"outputSkippedFrames"\s*:\s*(\d+)', &matchSkip))
                    skipped := Integer(matchSkip[1])
                SyncStreamState(cfg, state, reconn ? 2 : (active ? 1 : 0), cong, skipped, reconn)
            }
        }
        else if (InStr(msg, '"requestId":"InitVCamState"') || InStr(msg, '"requestId": "InitVCamState"')) {
            if (RegExMatch(msg, '"outputActive"\s*:\s*(true|false)', &matchVcAct)) {
                SyncVCamState(cfg, state, matchVcAct[1] == "true")
            }
        }
        else if (InStr(msg, '"requestId":"InitStudioState"') || InStr(msg, '"requestId": "InitStudioState"')) {
            if (RegExMatch(msg, '"studioModeEnabled"\s*:\s*(true|false)', &matchStudio)) {
                isStudio := (matchStudio[1] == "true")
                SyncStudioState(cfg, state, isStudio)
                if (isStudio && IsObject(ws))
                    SendObsRequest(ws, "GetCurrentPreviewScene", "InitPreviewSceneState")
            }
        }
        else if (InStr(msg, '"requestId":"InitSceneState"') || InStr(msg, '"requestId": "InitSceneState"')) {
            if (RegExMatch(msg, '"currentProgramSceneName"\s*:\s*"((?:[^"\\]|\\.)*)"', &matchScene) || RegExMatch(msg, '"sceneName"\s*:\s*"((?:[^"\\]|\\.)*)"', &matchScene)) {
                SyncSceneState(cfg, state, UnescapeJsonStr(matchScene[1]))
            }
        }
        else if (InStr(msg, '"requestId":"InitPreviewSceneState"') || InStr(msg, '"requestId": "InitPreviewSceneState"')) {
            if (RegExMatch(msg, '"currentPreviewSceneName"\s*:\s*"((?:[^"\\]|\\.)*)"', &matchPrevScene) || RegExMatch(msg, '"sceneName"\s*:\s*"((?:[^"\\]|\\.)*)"', &matchPrevScene)) {
                state.previewSceneName := UnescapeJsonStr(matchPrevScene[1])
            }
        }
        else if (InStr(msg, '"requestId":"InitSceneList"') || InStr(msg, '"requestId": "InitSceneList"')) {
            parsedScenes := ParseObsSceneList(msg)
            if (parsedScenes.Length > 0) {
                state.sceneList := parsedScenes
                HostBridgeBroadcastMuteState(cfg, state)
            }
        }
        else if (InStr(msg, '"requestId":"InitInputList"') || InStr(msg, '"requestId": "InitInputList"')) {
            parsedInputs := ParseObsInputList(msg)
            state.obsInputs := parsedInputs.all
            state.obsAudioInputs := parsedInputs.audio
            if (state.HasOwnProp("refreshInputsFn") && IsObject(state.refreshInputsFn))
                try state.refreshInputsFn.Call(state.obsAudioInputs, state.obsInputs)
        }
        else if (InStr(msg, '"requestId":"HostSplitRec"') || InStr(msg, '"requestId": "HostSplitRec"')) {
            if (RegExMatch(msg, '"result"\s*:\s*true') && IsSet(ShowStageNudgeBanner) && (!state.HasOwnProp("suppressNudgeBanners") || !state.suppressNudgeBanners))
                ShowStageNudgeBanner("Recording chapter file split saved", "10B981", 3000, "OBS")
        }
    }
}

ReleaseSyncLock(state) {
    state.IsSyncing := false
    if (state.HasOwnProp("syncSource"))
        state.syncSource := ""
}

PushObsMuteToZoom(cfg, state, obsIsMuted, mockZoomState := "", sendFn := "") {
    confHk := GetActiveConferencingMuteHotkey(cfg)
    curSrc := state.HasOwnProp("syncSource") ? state.syncSource : ""
    if (cfg.AudioRoutingMode != 3 || (state.IsSyncing && curSrc != "obs") || confHk = "" || confHk = "None")
        return
    appType := cfg.HasOwnProp("ConferencingApp") ? cfg.ConferencingApp : "Zoom"
    confSpec := GetConferencingWindowSpec(appType)
    if (!IsObject(mockZoomState) && !WinExist(confSpec))
        return

    zoomState := IsObject(mockZoomState) ? mockZoomState : DetectZoomStates(confSpec, appType)
    if (!zoomState.hasMic || zoomState.muted == obsIsMuted)
        return

    state.IsSyncing := true
    state.syncSource := "obs"
    targetWin := zoomState.micHwnd ? ("ahk_id " zoomState.micHwnd) : confSpec
    if (IsObject(sendFn)) {
        sendFn.Call(FormatSendKey(confHk), targetWin)
    } else {
        SetKeyDelay -1, 30
        try ControlSend FormatSendKey(confHk),, targetWin
        SetKeyDelay 50, 50
    }
    if (state.HasOwnProp("releaseSyncTimerFn") && state.releaseSyncTimerFn)
        SetTimer state.releaseSyncTimerFn, -UIConstants.SYNC_LOCK_TIMEOUT_MS
}

ParseConferencingElementNames(names, appType := "Zoom", hwnd := 0, result := "", cfg := "") {
    if (!IsObject(result))
        result := {foundWindow: false, hasMic: false, muted: false, micHwnd: 0, hasRec: false, recState: 0, hasChat: false, unreadChat: 0}
    normApp := NormalizeConferencingApp(appType)
    kwCfg := GetConfiguredUiaKeywords(cfg)
    hasCustomMute := (IsObject(cfg) && cfg.HasOwnProp("UiaMuteKeywords") && Trim(String(cfg.UiaMuteKeywords)) != "")
    hasCustomUnmute := (IsObject(cfg) && cfg.HasOwnProp("UiaUnmuteKeywords") && Trim(String(cfg.UiaUnmuteKeywords)) != "")
    for n in names {
        if (!result.hasMic && !RegExMatch(n, "i)\b(when joining|on entry|all|participants|everyone|settings)\b")) {
            nLow := StrLower(Trim(String(n)))
            matchedCustom := false
            if (hasCustomUnmute) {
                for _, uk in kwCfg.unmute {
                    if (InStr(nLow, StrLower(uk))) {
                        result.hasMic := true, result.muted := true, result.micHwnd := hwnd, matchedCustom := true
                        break
                    }
                }
            }
            if (!matchedCustom && hasCustomMute) {
                for _, mk in kwCfg.mute {
                    if (InStr(nLow, StrLower(mk))) {
                        result.hasMic := true, result.muted := false, result.micHwnd := hwnd, matchedCustom := true
                        break
                    }
                }
            }
            if (!matchedCustom) {
                if (normApp = "Microsoft Teams") {
                    if RegExMatch(n, "i)\bunmute(\b.*\bmic|\b)|^turn on microphone") {
                        result.hasMic := true, result.muted := true, result.micHwnd := hwnd
                    } else if RegExMatch(n, "i)\bmute(\b.*\bmic|\b)|^turn off microphone") {
                        result.hasMic := true, result.muted := false, result.micHwnd := hwnd
                    }
                } else if (normApp = "Google Meet") {
                    if RegExMatch(n, "i)turn on microphone|unmute microphone") {
                        result.hasMic := true, result.muted := true, result.micHwnd := hwnd
                    } else if RegExMatch(n, "i)turn off microphone|mute microphone") {
                        result.hasMic := true, result.muted := false, result.micHwnd := hwnd
                    }
                } else {
                    if RegExMatch(n, "i)\bunmute\b.*\baudio\b|^unmute(\b|,|$)") {
                        result.hasMic := true, result.muted := true, result.micHwnd := hwnd
                    } else if RegExMatch(n, "i)\bmute\b.*\baudio\b|^mute(\b|,|$)") {
                        result.hasMic := true, result.muted := false, result.micHwnd := hwnd
                    }
                }
            }
        }
        if (result.recState == 0) {
            if RegExMatch(n, "i)\bresume\b.*\brecording\b") {
                result.hasRec := true, result.recState := 2
            } else if RegExMatch(n, "i)\b(pause|stop)\b.*\brecording\b") {
                result.hasRec := true, result.recState := 1
            } else if (!result.hasRec && RegExMatch(n, "i)^record(\b|,|$)|^record (on this computer|to the cloud)|^start recording\b")) {
                result.hasRec := true, result.recState := 0
            }
        }
        if RegExMatch(n, "i)\bchat\b.*?(\d+)\s*unread|(\d+)\s*unread.*\bchat\b", &mChat) {
            result.hasChat := true
            cnt := Integer(mChat[1] != "" ? mChat[1] : mChat[2])
            if (cnt > result.unreadChat)
                result.unreadChat := cnt
        } else if (!result.hasChat && RegExMatch(n, "i)^chat(\b|,|$)|open chat|show chat|chat panel|chat with everyone")) {
            result.hasChat := true
        }
    }
    return result
}

DetectZoomStates(targetSpec := "ahk_exe Zoom.exe", appType := "Zoom", mockElementNames := "", cfg := "") {
    result := {foundWindow: false, hasMic: false, muted: false, micHwnd: 0, hasRec: false, recState: 0, hasChat: false, unreadChat: 0}
    if IsObject(mockElementNames) {
        result.foundWindow := true
        return ParseConferencingElementNames(mockElementNames, appType, 1, result, cfg)
    }

    hwndList := WinGetList(targetSpec)
    if (hwndList.Length == 0)
        return result

    result.foundWindow := true
    for hwnd in hwndList {
        if !DllCall("IsWindowVisible", "Ptr", hwnd)
            continue
        ww := 0, wh := 0
        try WinGetPos(,, &ww, &wh, hwnd)
        if (ww < 50 || wh < 50)
            continue
        names := UIA.GetWindowElementNames(hwnd, false)
        ParseConferencingElementNames(names, appType, hwnd, result, cfg)
        if (result.hasMic && result.hasRec && result.recState > 0 && result.hasChat && result.unreadChat > 0)
            break
    }
    return result
}

ZoomStateMonitor(cfg, state) {
    if (!cfg.EnableZoom && !cfg.EnableWS)
        return

    resolvedApp := ResolveAutoConfAppTarget(cfg, state)
    appType := (resolvedApp != "") ? resolvedApp : (cfg.HasOwnProp("ConferencingApp") ? cfg.ConferencingApp : "Zoom")
    CheckMeetBackgroundTabWarning(cfg, state)
    confSpec := GetConferencingWindowSpec(appType)
    zoomInfo := DetectZoomStates(confSpec, appType, "", cfg)
    if (zoomInfo.hasChat)
        SyncChatState(cfg, state, zoomInfo.unreadChat)
    else
        SyncChatState(cfg, state, 0)

    if (!zoomInfo.hasMic) {
        wasConn := state.zoomConnected
        state.zoomConnected := false
        state.zoomLastMuted := -1
        state.zoomRecGraceUntil := 0
        state.zoomSawRecControl := false
        if (cfg.EnableZoom)
            SyncRecState(cfg, state, 0, -1, "conf")
        if (wasConn && state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn)
            try state.refreshHelpFn.Call()
        return
    }

    wasConn := state.zoomConnected
    state.zoomConnected := (cfg.EnableZoom && zoomInfo.hasMic)
    if (state.zoomConnected != wasConn && state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn)
        try state.refreshHelpFn.Call()

    if (cfg.AudioRoutingMode == 3 && !state.IsSyncing) {
        if (state.zoomLastMuted != -1 && zoomInfo.muted != state.zoomLastMuted && zoomInfo.muted != state.isMuted) {
            sentObs := false
            if (cfg.EnableWS && state.obsConnected)
                sentObs := SendObsSetInputMuteGroup(cfg, state.obsWs, zoomInfo.muted)
            if (!sentObs && cfg.ObsMuteHotkey != "None" && cfg.ObsMuteHotkey != "" && WinExist("ahk_exe obs64.exe")) {
                SetKeyDelay -1, 30
                try ControlSend FormatSendKey(cfg.ObsMuteHotkey),, "ahk_exe obs64.exe"
                SetKeyDelay 50, 50
                sentObs := true
            }
            if (sentObs) {
                state.IsSyncing := true
                if (state.HasOwnProp("syncSource"))
                    state.syncSource := "zoom"
                SetTimer state.releaseSyncTimerFn, -UIConstants.SYNC_LOCK_TIMEOUT_MS
            }
        }
    }

    if (cfg.EnableZoom) {
        ; Mic mute follows Zoom only when OBS is not the mute authority; recording is tracked simultaneously.
        if (!cfg.EnableWS)
            SyncUIState(cfg, state, zoomInfo.muted)
        if (zoomInfo.hasRec) {
            state.zoomSawRecControl := true
            if (A_TickCount >= state.zoomRecGraceUntil)
                SyncRecState(cfg, state, zoomInfo.recState, -1, "conf")
        } else if (state.zoomSawRecControl && A_TickCount >= state.zoomRecGraceUntil) {
            state.zoomSawRecControl := false
            SyncRecState(cfg, state, 0, -1, "conf")
        }
    }
    state.zoomLastMuted := zoomInfo.muted
}

UpdateZoomMonitorTimer(cfg, state) {
    if (cfg.EnableZoom || cfg.EnableWS)
        SetTimer state.zoomTimerFn, UIConstants.ZOOM_POLL_INTERVAL_MS
    else
        SetTimer state.zoomTimerFn, 0
}
