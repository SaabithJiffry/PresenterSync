; ==============================================================================
; Module: OBS_Network.ahk
; Description: OBS WebSocket v5 client connection, message handling & Zoom UIA sync
; ==============================================================================

#Include "%A_LineFile%\..\WebSocket.ahk"
#Include "%A_LineFile%\..\UIA.ahk"
#Include "%A_LineFile%\..\Crypto.ahk"
#Include "%A_LineFile%\..\JsonCodec.ahk"
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

StripHotkeyModifiers(hk, unwrapBraces := false) {
    clean := LTrim(Trim(String(hk)), "~*$")
    if (unwrapBraces)
        clean := RegExReplace(clean, "^\{(.+)\}$", "$1")
    return clean
}

ControlSendFast(hk, winTitle, pressDuration := 10, formatKey := true) {
    if (hk = "" || hk = "None" || winTitle = "")
        return false
    keys := formatKey ? FormatSendKey(hk) : String(hk)
    ok := false
    SetKeyDelay -1, pressDuration
    try {
        ControlSend keys, , winTitle
        ok := true
    } catch {
        ok := false
    } finally {
        SetKeyDelay -1, -1
    }
    return ok
}

_EngageSyncLock(state, source) {
    if (!IsObject(state))
        return
    state.IsSyncing := true
    if (state.HasOwnProp("syncSource"))
        state.syncSource := source
    if (state.HasOwnProp("releaseSyncTimerFn") && state.releaseSyncTimerFn)
        SetTimer state.releaseSyncTimerFn, -UIConstants.SYNC_LOCK_TIMEOUT_MS
}

_CommitHostSceneChange(cfg, state, sceneName) {
    if (IsSet(SyncSceneState))
        SyncSceneState(cfg, state, sceneName)
    else {
        if (state.HasOwnProp("currentSceneName") && state.currentSceneName != "" && state.currentSceneName != sceneName)
            state.previousProgramScene := state.currentSceneName
        state.currentSceneName := sceneName
    }
    BroadcastHostRelayDirectorState(cfg, state)
}

ExtractBaseKeyName(hk) {
    s := Trim(String(hk))
    if (s = "" || s = "None")
        return ""
    s := RegExReplace(s, "i)\s+up$", "")
    s := RegExReplace(s, "^[*~$<>^!+#]+(?=.+$)", "")
    return Trim(s)
}

_NormalizeCollisionKeyAlias(k) {
    static aliasMap := Map(
        "pagedown", "pgdn",
        "pageup", "pgup",
        "return", "enter",
        "escape", "esc"
    )
    low := StrLower(Trim(String(k)))
    return aliasMap.Has(low) ? aliasMap[low] : low
}

_ExtractNormalizedHotkeyMods(hk) {
    s := Trim(String(hk))
    mods := ""
    hasCtrl := false, hasAlt := false, hasShift := false, hasWin := false
    Loop Parse, s {
        ch := A_LoopField
        if (ch = "^")
            hasCtrl := true
        else if (ch = "!")
            hasAlt := true
        else if (ch = "+")
            hasShift := true
        else if (ch = "#")
            hasWin := true
        else if (ch = "$" || ch = "~" || ch = "*" || ch = "<" || ch = ">")
            continue
        else
            break
    }
    if (hasCtrl)
        mods .= "^"
    if (hasAlt)
        mods .= "!"
    if (hasShift)
        mods .= "+"
    if (hasWin)
        mods .= "#"
    return mods
}

_DoHotkeysCollide(hkA, hkB) {
    cleanA := LTrim(StripHotkeyModifiers(hkA, true), "^!+#<>")
    cleanB := LTrim(StripHotkeyModifiers(hkB, true), "^!+#<>")
    if (cleanA = "" || StrLower(cleanA) = "none" || cleanB = "" || StrLower(cleanB) = "none")
        return false
    modA := _ExtractNormalizedHotkeyMods(hkA)
    modB := _ExtractNormalizedHotkeyMods(hkB)
    if (modA != modB)
        return false
    normA := GetKeyName(cleanA)
    normB := GetKeyName(cleanB)
    keyA := _NormalizeCollisionKeyAlias(normA != "" ? normA : cleanA)
    keyB := _NormalizeCollisionKeyAlias(normB != "" ? normB : cleanB)
    return StrLower(keyA) = StrLower(keyB)
}

IsPptKeyAllowed(cfg, pptKey) {
    if (!IsObject(cfg))
        return false
    cleanPpt := StripHotkeyModifiers(pptKey, true)
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

    for _, prop in ["HwMuteHotkey", "ObsMuteHotkey", "HwTransitionHotkey", "ObsTransitionHotkey", "ZoomMuteHotkey", "TeamsMuteHotkey", "MeetMuteHotkey", "ObsRecHotkey", "ZoomRecHotkey", "ObsPauseHotkey", "ZoomPauseHotkey"] {
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

HandleWtsSessionChange(wParam, lParam, cfg, state) {
    if (Integer(wParam) == 0x7) { ; WTS_SESSION_LOCK
        if (IsObject(cfg) && (!cfg.HasOwnProp("AutoMuteOnLock") || cfg.AutoMuteOnLock)) {
            if (IsSet(DiagnosticLogger))
                try DiagnosticLogger.RecordBreadcrumb("Safety", "AutoMuteOnLock", "WTS_SESSION_LOCK")
            ExecuteHostRemoteSetMute(cfg, state, true)
            return true
        }
    }
    return false
}

CheckConfMeetingEndAutoMute(cfg, state, inMeetingNow) {
    if (!IsObject(state))
        return false
    wasIn := state.HasOwnProp("wasInConfMeeting") ? !!state.wasInConfMeeting : false
    nowIn := !!inMeetingNow
    state.wasInConfMeeting := nowIn
    if (wasIn && !nowIn && IsObject(cfg) && cfg.HasOwnProp("AutoMuteOnMeetingEnd") && cfg.AutoMuteOnMeetingEnd) {
        if (IsSet(DiagnosticLogger))
            try DiagnosticLogger.RecordBreadcrumb("Safety", "AutoMuteOnMeetingEnd", "meeting ended")
        ExecuteHostRemoteSetMute(cfg, state, true)
        return true
    }
    return false
}

DispatchCliCommandString(cmdStr, cfg, state) {
    cmd := Trim(String(cmdStr))
    if (cmd = "")
        return false
    cmdLow := StrLower(cmd)
    switch cmdLow {
        case "mute":
            ExecuteHostRemoteSetMute(cfg, state, true)
            return true
        case "unmute":
            ExecuteHostRemoteSetMute(cfg, state, false)
            return true
        case "toggle-mute":
            ExecuteHostRemoteToggleMute(cfg, state)
            return true
        case "transition":
            TriggerObsSceneTransition(cfg, state, true)
            return true
        case "standby":
            ExecuteHostToggleStandby(cfg, state)
            return true
        case "split":
            ExecuteHostSplitRecord(cfg, state)
            return true
        case "__exit__":
            if (IsObject(state) && state.HasOwnProp("cliExitFn") && IsObject(state.cliExitFn))
                state.cliExitFn.Call()
            else
                SetTimer(() => ExitApp(0), -10)
            return true
    }
    if (SubStr(cmdLow, 1, 6) = "nudge:") {
        txt := Trim(SubStr(cmd, 7))
        if (txt != "") {
            BroadcastHostStageNudge(cfg, state, txt, "CLI")
            return true
        }
        return false
    }
    if (SubStr(cmdLow, 1, 6) = "scene:") {
        sc := Trim(SubStr(cmd, 7))
        if (sc != "") {
            ExecuteHostSwitchScene(cfg, state, sc)
            return true
        }
        return false
    }
    return false
}

OnHostCopyData(cfg, state, wParam, lParam, msg, hwnd) {
    if (!lParam)
        return 0
    dwData := NumGet(lParam, 0, "UPtr")
    if (dwData != 0x5053434C) ; "PSCL"
        return 0
    cbData := NumGet(lParam, A_PtrSize, "UInt")
    lpData := NumGet(lParam, A_PtrSize * 2, "Ptr")
    if (!lpData || cbData == 0)
        return 0
    cmdStr := StrGet(lpData, cbData // 2, "UTF-16")
    cmdStr := RTrim(cmdStr, Chr(0))
    return DispatchCliCommandString(cmdStr, cfg, state) ? 1 : 0
}

ParseHostCliArgs(args) {
    if (!IsObject(args) || args.Length == 0)
        return ""
    i := 1
    while (i <= args.Length) {
        a := Trim(String(args[i]))
        aLow := StrLower(a)
        switch aLow {
            case "--mute":
                return "mute"
            case "--unmute":
                return "unmute"
            case "--toggle-mute":
                return "toggle-mute"
            case "--transition":
                return "transition"
            case "--standby":
                return "standby"
            case "--split":
                return "split"
        }
        if (SubStr(aLow, 1, 8) = "--nudge=") {
            val := Trim(SubStr(a, 9), '"')
            return (val != "") ? ("nudge:" val) : ""
        }
        if (aLow = "--nudge" && i < args.Length) {
            val := Trim(String(args[i + 1]), '"')
            return (val != "") ? ("nudge:" val) : ""
        }
        if (SubStr(aLow, 1, 8) = "--scene=") {
            val := Trim(SubStr(a, 9), '"')
            return (val != "") ? ("scene:" val) : ""
        }
        if (aLow = "--scene" && i < args.Length) {
            val := Trim(String(args[i + 1]), '"')
            return (val != "") ? ("scene:" val) : ""
        }
        i += 1
    }
    return ""
}

HasUnknownHostCliFlag(args) {
    if (!IsObject(args) || args.Length == 0)
        return false
    i := 1
    while (i <= args.Length) {
        a := Trim(String(args[i]))
        aLow := StrLower(a)
        if (aLow = "--nudge" || aLow = "--scene" || aLow = "--cleanup-old-exe" || aLow = "-cleanup-old-exe"
            || aLow = "--config" || aLow = "-config" || aLow = "--instance" || aLow = "-instance") {
            i += 2
            continue
        }
        if (aLow = "--mute" || aLow = "--unmute" || aLow = "--toggle-mute" || aLow = "--transition"
            || aLow = "--standby" || aLow = "--split"
            || SubStr(aLow, 1, 8) = "--nudge=" || SubStr(aLow, 1, 8) = "--scene="
            || RegExMatch(aLow, "^--?(cleanup-old-exe|config|instance)=")) {
            i += 1
            continue
        }
        if (SubStr(aLow, 1, 2) = "--")
            return true
        i += 1
    }
    return false
}

SendHostCliCopyData(cmdStr, targetTitle := "PresenterSync_HostIpcMsg ahk_class AutoHotkeyGUI") {
    cmd := Trim(String(cmdStr))
    if (cmd = "")
        return false
    prevDetect := A_DetectHiddenWindows
    DetectHiddenWindows(true)
    hwnd := WinExist(targetTitle)
    DetectHiddenWindows(prevDetect)
    if (!hwnd)
        return false
    cds := Buffer(A_PtrSize * 3, 0)
    NumPut("UPtr", 0x5053434C, cds, 0) ; "PSCL"
    NumPut("UInt", (StrLen(cmd) + 1) * 2, cds, A_PtrSize)
    NumPut("Ptr", StrPtr(cmd), cds, A_PtrSize * 2)
    try {
        res := SendMessage(0x004A, 0, cds.Ptr, , hwnd, , , , 3000)
        return (res == 1)
    } catch {
        return false
    }
}

GetFallbackSlideKey(exe, dir := "next") {
    exeLow := StrLower(Trim(String(exe)))
    dLow := StrLower(Trim(String(dir)))
    isPrev := (dLow = "prev" || dLow = "previous" || dLow = "{left}" || dLow = "{up}" || dLow = "{pgup}")
    if (exeLow = "acrobat.exe" || exeLow = "acrord32.exe" || exeLow = "sumatrapdf.exe" || exeLow = "foxitpdfreader.exe"
        || exeLow = "wpp.exe" || exeLow = "wps.exe" || exeLow = "soffice.bin" || exeLow = "simpress.exe"
        || exeLow = "mswhiteboard.exe" || exeLow = "whiteboard.exe" || exeLow = "onenote.exe" || exeLow = "powerpnt.exe")
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
            for _, cand in ["POWERPNT.EXE", "wpp.exe", "wps.exe", "soffice.bin", "simpress.exe", "Acrobat.exe", "AcroRd32.exe", "SumatraPDF.exe", "FoxitPDFReader.exe", "mswhiteboard.exe", "onenote.exe", "chrome.exe", "msedge.exe", "brave.exe", "firefox.exe"] {
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
        if (state.obsConnected && IsObject(state.obsWs) && SendObsToggleInputMuteGroup(cfg, state, state.obsWs, "HostClickerMute")) {
            if (IsSet(SyncUIState))
                SyncUIState(cfg, state, !state.isMuted, true)
            return true
        }
        if (!obsOpen || cfg.ObsMuteHotkey = "None" || cfg.ObsMuteHotkey = "") {
            if (TryCoreAudioFallbackMute(cfg, state, !state.isMuted, "HostToggleMode1"))
                return true
            SoundPlay "*16"
            return false
        }
        ControlSendFast(cfg.ObsMuteHotkey, "ahk_exe obs64.exe")
    } else if (cfg.AudioRoutingMode == 2) {
        if (!zoomOpen || confHk = "" || confHk = "None") {
            if (TryCoreAudioFallbackMute(cfg, state, !state.isMuted, "HostToggleMode2"))
                return true
            SoundPlay "*16"
            return false
        }
        ControlSendFast(confHk, confSpec)
    } else if (cfg.AudioRoutingMode == 3) {
        if (state.obsConnected && IsObject(state.obsWs) && SendObsToggleInputMuteGroup(cfg, state, state.obsWs, "HostClickerMute")) {
            if (IsSet(SyncUIState))
                SyncUIState(cfg, state, !state.isMuted, true)
            return true
        }
        obsCanSend := (obsOpen && cfg.ObsMuteHotkey != "None" && cfg.ObsMuteHotkey != "")
        confCanSend := (zoomOpen && confHk != "" && confHk != "None")
        if (!obsCanSend && !confCanSend) {
            if (TryCoreAudioFallbackMute(cfg, state, !state.isMuted, "HostToggleMode3"))
                return true
            SoundPlay "*16"
            return false
        }
        _EngageSyncLock(state, "manual")
        if (obsCanSend)
            ControlSendFast(cfg.ObsMuteHotkey, "ahk_exe obs64.exe")
        if (confCanSend)
            ControlSendFast(confHk, confSpec)
    } else {
        if (cfg.EnableWS && state.obsConnected && IsObject(state.obsWs) && SendObsToggleInputMuteGroup(cfg, state, state.obsWs, "HostClickerMute")) {
            if (IsSet(SyncUIState))
                SyncUIState(cfg, state, !state.isMuted, true)
            return true
        }
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

_NextRemoteBridgeCmdId(cfg, state) {
    devId := (IsObject(cfg) && cfg.HasOwnProp("DeviceId") && cfg.DeviceId != "") ? EscapeJsonStr(cfg.DeviceId) : "win-default"
    seq := IsObject(state) ? _NextRelaySequence(state) : A_TickCount
    return devId "-" seq
}

DispatchRemoteSetMute(cfg, state, targetMuted) {
    valStr := targetMuted ? "1" : "0"
    if (IsRemoteUsingInternetChannel(cfg, state)) {
        topic := GetInternetRelayTopic(cfg.InternetPairingCode)
        pktStr := BuildOutboundRelayPacket(cfg, state, "remote", "set_mute", valStr)
        mockWs := (state.HasOwnProp("relayMockWs") && IsObject(state.relayMockWs)) ? state.relayMockWs : ""
        if (!PublishInternetRelayPacket(topic, pktStr, GetEffectiveRelayBaseUrl(cfg), mockWs)) {
            ToolTip "PresenterSync Remote: Internet Relay unreachable"
            SetTimer ClearObsNetworkToolTip, -2000
            return false
        }
        if (IsSet(ApplyRemoteOptimisticMute))
            ApplyRemoteOptimisticMute(cfg, state, !!targetMuted)
        return true
    }

    if (IsRemoteUsingBridgeChannel(cfg, state)) {
        devId := (IsObject(cfg) && cfg.HasOwnProp("DeviceId") && cfg.DeviceId != "") ? EscapeJsonStr(cfg.DeviceId) : "win-default"
        cid := _NextRemoteBridgeCmdId(cfg, state)
        payload := '{"type":"set_mute","cmdId":"' cid '","isMuted":' (targetMuted ? "true" : "false") ',"deviceId":"' devId '","source":"hud"}'
        if (!TrySendWsText(state.obsWs, payload)) {
            ToolTip "PresenterSync Remote: Host Bridge disconnected"
            SetTimer ClearObsNetworkToolTip, -2000
            return false
        }
        if (IsSet(ApplyRemoteOptimisticMute))
            ApplyRemoteOptimisticMute(cfg, state, !!targetMuted)
        return true
    }

    if (!IsObject(state) || !IsObject(state.obsWs)) {
        ToolTip "PresenterSync Remote: Not connected to OBS host"
        SetTimer ClearObsNetworkToolTip, -2000
        return false
    }
    escMic := EscapeJsonStr(cfg.TargetMicName)
    if (!SendObsRequest(state.obsWs, "SetInputMute", "RemoteClickerSetMute", '{"inputName":"' escMic '","inputMuted":' (targetMuted ? "true" : "false") '}')) {
        ToolTip "PresenterSync Remote: Not connected to OBS host"
        SetTimer ClearObsNetworkToolTip, -2000
        return false
    }
    if (IsSet(ApplyRemoteOptimisticMute))
        ApplyRemoteOptimisticMute(cfg, state, !!targetMuted)
    return true
}

DispatchRemoteMuteToggle(cfg, state) {
    nextMuted := (IsObject(state) && state.HasOwnProp("isMuted")) ? !state.isMuted : true
    if (IsRemoteUsingInternetChannel(cfg, state)) {
        topic := GetInternetRelayTopic(cfg.InternetPairingCode)
        pktStr := BuildOutboundRelayPacket(cfg, state, "remote", "toggle_mute", "1")
        mockWs := (state.HasOwnProp("relayMockWs") && IsObject(state.relayMockWs)) ? state.relayMockWs : ""
        if (!PublishInternetRelayPacket(topic, pktStr, GetEffectiveRelayBaseUrl(cfg), mockWs)) {
            ToolTip "PresenterSync Remote: Internet Relay unreachable"
            SetTimer ClearObsNetworkToolTip, -2000
            return false
        }
        if (IsSet(ApplyRemoteOptimisticMute))
            ApplyRemoteOptimisticMute(cfg, state, nextMuted)
        return true
    }

    if (IsRemoteUsingBridgeChannel(cfg, state)) {
        devId := (IsObject(cfg) && cfg.HasOwnProp("DeviceId") && cfg.DeviceId != "") ? EscapeJsonStr(cfg.DeviceId) : "win-default"
        cid := _NextRemoteBridgeCmdId(cfg, state)
        payload := '{"type":"toggle_mute","cmdId":"' cid '","deviceId":"' devId '","source":"clicker"}'
        if (!TrySendWsText(state.obsWs, payload)) {
            ToolTip "PresenterSync Remote: Host Bridge disconnected"
            SetTimer ClearObsNetworkToolTip, -2000
            return false
        }
        if (IsSet(ApplyRemoteOptimisticMute))
            ApplyRemoteOptimisticMute(cfg, state, nextMuted)
        return true
    }

    if (!SendObsToggleInputMute(state.obsWs, cfg.TargetMicName, "RemoteClickerMute")) {
        ToolTip "PresenterSync Remote: Not connected to OBS host"
        SetTimer ClearObsNetworkToolTip, -2000
        return false
    }
    if (IsSet(ApplyRemoteOptimisticMute))
        ApplyRemoteOptimisticMute(cfg, state, nextMuted)
    return true
}

EscapeJsonStr(str) {
    return JsonCodec.Escape(str)
}

UnescapeJsonStr(str) {
    return JsonCodec.Unescape(str)
}

ClearObsNetworkToolTip() {
    if (IsSet(HideCaptureSafeMicroToast))
        HideCaptureSafeMicroToast()
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
    charCount := StrLen(chars)
    p1 := "", p2 := ""
    rnd := IsSet(GenerateRandomBytes) ? GenerateRandomBytes(8) : ""
    Loop 4 {
        b1 := IsObject(rnd) ? NumGet(rnd, A_Index - 1, "UChar") : Random(0, 255)
        b2 := IsObject(rnd) ? NumGet(rnd, A_Index + 3, "UChar") : Random(0, 255)
        p1 .= SubStr(chars, Mod(b1, charCount) + 1, 1)
        p2 .= SubStr(chars, Mod(b2, charCount) + 1, 1)
    }
    return "PS-" p1 "-" p2
}

NormalizeRelayBaseUrl(rawUrl := "") {
    clean := Trim(String(rawUrl))
    if (clean = "")
        return "https://ntfy.sh"
    if (RegExMatch(clean, "i)^wss://(.+)$", &m))
        clean := "https://" m[1]
    else if (RegExMatch(clean, "i)^ws://(.+)$", &m))
        clean := "http://" m[1]
    else if (!RegExMatch(clean, "i)^https?://"))
        clean := "https://" clean
    clean := RTrim(clean, "/")
    if (RegExMatch(clean, "[\s`r`n`t]") || !RegExMatch(clean, "i)^https?://[^\s/?#]+"))
        return "https://ntfy.sh"
    return clean
}

BuildRelayWsUrl(baseUrl, topic) {
    cleanTopic := Trim(String(topic), " /`t`r`n")
    if (cleanTopic = "")
        return ""
    httpBase := NormalizeRelayBaseUrl(baseUrl)
    if (RegExMatch(httpBase, "i)^https://(.+)$", &m))
        wsBase := "wss://" m[1]
    else if (RegExMatch(httpBase, "i)^http://(.+)$", &m))
        wsBase := "ws://" m[1]
    else
        wsBase := "wss://ntfy.sh"
    return wsBase "/" cleanTopic "/ws"
}

GetEffectiveRelayBaseUrl(cfg) {
    raw := (IsObject(cfg) && cfg.HasOwnProp("RelayBaseUrl")) ? cfg.RelayBaseUrl : ""
    return NormalizeRelayBaseUrl(raw)
}

_GetRelayPassword(cfg) {
    if (!IsObject(cfg))
        return ""
    if (cfg.HasOwnProp("obsPassword"))
        return String(cfg.obsPassword)
    if (cfg.HasOwnProp("ObsPassword"))
        return String(cfg.ObsPassword)
    return ""
}

ShouldUseRelayEncryption(cfg, state := "") {
    if (IsObject(cfg) && cfg.HasOwnProp("EnableRelayEncryption") && !cfg.EnableRelayEncryption)
        return false
    if (IsObject(state) && state.HasOwnProp("_relayPeerLegacy") && state._relayPeerLegacy)
        return false
    return IsSet(EncryptRelayPayload)
}

_NextRelaySequence(state := "") {
    static fallbackSeq := 0
    if (IsObject(state)) {
        if (!state.HasOwnProp("_relayOutSeq") || !IsInteger(state._relayOutSeq))
            state._relayOutSeq := 0
        state._relayOutSeq += 1
        return state._relayOutSeq
    }
    fallbackSeq += 1
    return fallbackSeq
}

_GetRelaySessionId(state := "") {
    static fallbackSid := ""
    if (IsObject(state)) {
        if (!state.HasOwnProp("_relaySessionId") || state._relaySessionId = "")
            state._relaySessionId := IsSet(GenerateRelaySessionId) ? GenerateRelaySessionId() : Format("{:08x}", Random(1, 0x7FFFFFFF))
        return state._relaySessionId
    }
    if (fallbackSid = "")
        fallbackSid := IsSet(GenerateRelaySessionId) ? GenerateRelaySessionId() : Format("{:08x}", Random(1, 0x7FFFFFFF))
    return fallbackSid
}

_GetHostSceneListForRelay(state) {
    out := []
    if (!IsObject(state))
        return out
    srcList := ""
    if (state.HasOwnProp("sceneList") && IsObject(state.sceneList))
        srcList := state.sceneList
    else if (state.HasOwnProp("scenes") && IsObject(state.scenes))
        srcList := state.scenes
    if (!IsObject(srcList))
        return out
    for _, sc in srcList {
        s := Trim(String(sc))
        if (s != "") {
            out.Push(s)
            if (out.Length >= 24)
                break
        }
    }
    return out
}

_BuildLegacyDirStatePayload(state) {
    standby := (IsObject(state) && state.HasOwnProp("isStandby") && state.isStandby) ? "1" : "0"
    recSt := (IsObject(state) && state.HasOwnProp("recState") && IsInteger(state.recState)) ? Integer(state.recState) : 0
    tSt := (IsObject(state) && state.HasOwnProp("timerState") && state.timerState != "") ? String(state.timerState) : "stopped"
    tRem := (IsObject(state) && state.HasOwnProp("timerRemainingSec") && IsInteger(state.timerRemainingSec)) ? Integer(state.timerRemainingSec) : 600
    tPre := (IsObject(state) && state.HasOwnProp("timerPresetSec") && IsInteger(state.timerPresetSec)) ? Max(60, Integer(state.timerPresetSec)) : 600
    scene := (IsObject(state) && state.HasOwnProp("currentSceneName") && state.currentSceneName != "") ? StrReplace(StrReplace(String(state.currentSceneName), "|", "/"), ";", ",") : "Scene"
    recSec := (IsObject(state) && state.HasOwnProp("recElapsedSec") && IsInteger(state.recElapsedSec)) ? Max(0, Integer(state.recElapsedSec))
        : ((IsObject(state) && state.HasOwnProp("recSeconds") && IsInteger(state.recSeconds)) ? Max(0, Integer(state.recSeconds)) : 0)
    streamDrop := (IsObject(state) && ((state.HasOwnProp("streamDropWarn") && state.streamDropWarn) || (state.HasOwnProp("streamState") && state.streamState == 2))) ? "1" : "0"
    voiceMuted := (IsObject(state) && state.HasOwnProp("voiceWhileMuted") && state.voiceWhileMuted) ? "1" : "0"
    scenesCsv := ""
    for idx, scName in _GetHostSceneListForRelay(state) {
        cleanSc := StrReplace(StrReplace(StrReplace(scName, "|", "/"), ";", " "), ",", " ")
        scenesCsv .= (idx > 1 ? "," : "") cleanSc
    }
    return standby ";" recSt ";" tSt ";" tRem ";" tPre ";" scene ";" recSec ";" streamDrop ";" voiceMuted ";" scenesCsv
}

ParseDirStatePayload(dataStr, fallbackState := "") {
    dParts := StrSplit(String(dataStr), ";")
    if (dParts.Length < 5)
        return ""
    fbRecSt := (IsObject(fallbackState) && fallbackState.HasOwnProp("recState")) ? Integer(fallbackState.recState) : 0
    fbRecSec := (IsObject(fallbackState) && fallbackState.HasOwnProp("recSeconds")) ? Integer(fallbackState.recSeconds) : 0
    fbDrop := (IsObject(fallbackState) && fallbackState.HasOwnProp("streamDropWarn")) ? !!fallbackState.streamDropWarn : false
    fbVoice := (IsObject(fallbackState) && fallbackState.HasOwnProp("voiceWhileMuted")) ? !!fallbackState.voiceWhileMuted : false
    fbRem := (IsObject(fallbackState) && fallbackState.HasOwnProp("timerRemainingSec")) ? Integer(fallbackState.timerRemainingSec) : 600
    fbPre := (IsObject(fallbackState) && fallbackState.HasOwnProp("timerPresetSec")) ? Integer(fallbackState.timerPresetSec) : 600
    fbScene := (IsObject(fallbackState) && fallbackState.HasOwnProp("activeScene")) ? String(fallbackState.activeScene) : "Scene"

    scenesArr := []
    if (dParts.Length >= 10 && Trim(dParts[10]) != "") {
        for _, scItem in StrSplit(dParts[10], ",") {
            scTrim := Trim(scItem)
            if (scTrim != "")
                scenesArr.Push(scTrim)
        }
    }
    return {
        isStandby: (dParts[1] = "1" || StrLower(dParts[1]) = "true"),
        recState: IsInteger(dParts[2]) ? Integer(dParts[2]) : fbRecSt,
        timerState: (dParts[3] != "" ? dParts[3] : "stopped"),
        timerRemainingSec: IsInteger(dParts[4]) ? Integer(dParts[4]) : fbRem,
        timerPresetSec: IsInteger(dParts[5]) ? Max(60, Integer(dParts[5])) : fbPre,
        activeScene: (dParts.Length >= 6 && dParts[6] != "") ? dParts[6] : fbScene,
        recSeconds: (dParts.Length >= 7 && IsInteger(dParts[7])) ? Max(0, Integer(dParts[7])) : fbRecSec,
        streamDropWarn: (dParts.Length >= 8) ? (dParts[8] = "1" || StrLower(dParts[8]) = "true") : fbDrop,
        voiceWhileMuted: (dParts.Length >= 9) ? (dParts[9] = "1" || StrLower(dParts[9]) = "true") : fbVoice,
        scenes: scenesArr
    }
}

FormatRelayStatePayload(cfg, state, cmd := "state", seq := 0, ts := 0, sid := "") {
    pairCode := StrUpper(Trim((IsObject(cfg) && cfg.HasOwnProp("InternetPairingCode")) ? cfg.InternetPairingCode : ""))
    auth := GetInternetRelayAuthToken(pairCode, _GetRelayPassword(cfg))
    isMuted := (IsObject(state) && state.HasOwnProp("isMuted") && state.isMuted) ? true : false
    isStandby := (IsObject(state) && state.HasOwnProp("isStandby") && state.isStandby) ? true : false
    recSt := (IsObject(state) && state.HasOwnProp("recState") && IsInteger(state.recState)) ? Integer(state.recState) : 0
    recSec := (IsObject(state) && state.HasOwnProp("recElapsedSec") && IsInteger(state.recElapsedSec)) ? Max(0, Integer(state.recElapsedSec))
        : ((IsObject(state) && state.HasOwnProp("recSeconds") && IsInteger(state.recSeconds)) ? Max(0, Integer(state.recSeconds)) : 0)
    streamDrop := (IsObject(state) && ((state.HasOwnProp("streamDropWarn") && state.streamDropWarn) || (state.HasOwnProp("streamState") && state.streamState == 2))) ? true : false
    voiceMuted := (IsObject(state) && state.HasOwnProp("voiceWhileMuted") && state.voiceWhileMuted) ? true : false
    osDrift := (IsObject(state) && state.HasOwnProp("osMicMutedDrift") && state.osMicMutedDrift) ? true : false
    lowDiskLvl := (IsObject(state) && state.HasOwnProp("lowDiskWarnLevel") && IsInteger(state.lowDiskWarnLevel)) ? Integer(state.lowDiskWarnLevel) : 0
    lowDiskMb := (IsObject(state) && state.HasOwnProp("lowDiskMb") && IsInteger(state.lowDiskMb)) ? Integer(state.lowDiskMb) : -1
    deadMic := (IsObject(state) && state.HasOwnProp("deadMicWarn") && state.deadMicWarn) ? true : false
    sIdx := (IsObject(state) && state.HasOwnProp("slideIndex") && IsInteger(state.slideIndex)) ? Max(0, Integer(state.slideIndex)) : 0
    sTot := (IsObject(state) && state.HasOwnProp("slideTotal") && IsInteger(state.slideTotal)) ? Max(0, Integer(state.slideTotal)) : 0
    sTitle := (IsObject(state) && state.HasOwnProp("slideTitle")) ? SubStr(Trim(String(state.slideTitle)), 1, 120) : ""
    tSt := (IsObject(state) && state.HasOwnProp("timerState") && state.timerState != "") ? String(state.timerState) : "stopped"
    tRem := (IsObject(state) && state.HasOwnProp("timerRemainingSec") && IsInteger(state.timerRemainingSec)) ? Integer(state.timerRemainingSec) : 600
    tPre := (IsObject(state) && state.HasOwnProp("timerPresetSec") && IsInteger(state.timerPresetSec)) ? Max(60, Integer(state.timerPresetSec)) : 600
    activeScene := (IsObject(state) && state.HasOwnProp("currentSceneName") && state.currentSceneName != "") ? String(state.currentSceneName) : "Scene"

    sceneList := _GetHostSceneListForRelay(state)
    dataStr := (cmd = "state") ? (isMuted ? "1" : "0") : ""
    seqNum := (seq > 0) ? Integer(seq) : _NextRelaySequence(state)
    tsNum := (ts > 0) ? Integer(ts) : (IsSet(GetCurrentUnixEpochSec) ? GetCurrentUnixEpochSec() : A_TickCount)
    sidStr := (sid != "") ? String(sid) : _GetRelaySessionId(state)

    buildJson(scArr, titleStr) {
        scJson := "["
        for idx, scName in scArr
            scJson .= (idx > 1 ? "," : "") '"' EscapeJsonStr(scName) '"'
        scJson .= "]"
        return '{"v":2,"src":"host","cmd":"' EscapeJsonStr(cmd) '","data":"' EscapeJsonStr(dataStr) '","seq":' seqNum ',"ts":' tsNum ',"sid":"' EscapeJsonStr(sidStr) '","auth":"' EscapeJsonStr(auth) '"'
            . ',"isMuted":' (isMuted ? "true" : "false")
            . ',"isStandby":' (isStandby ? "true" : "false")
            . ',"recState":' recSt
            . ',"recSeconds":' recSec
            . ',"streamDropWarn":' (streamDrop ? "true" : "false")
            . ',"voiceWhileMuted":' (voiceMuted ? "true" : "false")
            . ',"osMicMutedDrift":' (osDrift ? "true" : "false")
            . ',"lowDiskWarnLevel":' lowDiskLvl
            . ',"lowDiskMb":' lowDiskMb
            . ',"deadMicWarn":' (deadMic ? "true" : "false")
            . ',"slideIndex":' sIdx
            . ',"slideTotal":' sTot
            . ',"slideTitle":"' EscapeJsonStr(titleStr) '"'
            . ',"timerState":"' EscapeJsonStr(tSt) '"'
            . ',"timerRemainingSec":' tRem
            . ',"timerPresetSec":' tPre
            . ',"activeScene":"' EscapeJsonStr(activeScene) '"'
            . ',"scenes":' scJson '}'
    }

    outJson := buildJson(sceneList, sTitle)
    if (StrLen(outJson) > 2500) {
        sTitle := SubStr(sTitle, 1, 48)
        while (sceneList.Length > 12 && StrLen(buildJson(sceneList, sTitle)) > 2500)
            sceneList.Pop()
        outJson := buildJson(sceneList, sTitle)
    }
    return outJson
}

FormatEncryptedRelayPacket(src, cmd, data, pairingCode, password := "", state := "", ivOverride := "") {
    cleanCode := StrUpper(Trim(String(pairingCode)))
    auth := GetInternetRelayAuthToken(cleanCode, password)
    seqNum := _NextRelaySequence(state)
    tsNum := IsSet(GetCurrentUnixEpochSec) ? GetCurrentUnixEpochSec() : A_TickCount
    sidStr := _GetRelaySessionId(state)
    plainJson := '{"v":1,"src":"' EscapeJsonStr(src) '","cmd":"' EscapeJsonStr(cmd) '","data":"' EscapeJsonStr(data) '","seq":' seqNum ',"ts":' tsNum ',"sid":"' EscapeJsonStr(sidStr) '","auth":"' EscapeJsonStr(auth) '"}'
    return EncryptRelayPayload(plainJson, cleanCode, password, ivOverride)
}

BuildOutboundRelayPacket(cfg, state, src, cmd, data) {
    pairCode := (IsObject(cfg) && cfg.HasOwnProp("InternetPairingCode")) ? StrUpper(Trim(cfg.InternetPairingCode)) : ""
    pw := _GetRelayPassword(cfg)
    if (ShouldUseRelayEncryption(cfg, state)) {
        env := FormatEncryptedRelayPacket(src, cmd, data, pairCode, pw, state)
        if (env != "")
            return env
    }
    authTok := GetInternetRelayAuthToken(pairCode, pw)
    return FormatRelayPacket(src, cmd, data, authTok)
}

_RelayJsonExtractStr(jsonStr, key) {
    return JsonCodec.GetStr(jsonStr, key, "")
}

_RelayJsonExtractBool(jsonStr, key, defaultVal := false) {
    return JsonCodec.GetBool(jsonStr, key, defaultVal)
}

_RelayJsonExtractInt(jsonStr, key, defaultVal := 0) {
    return JsonCodec.GetInt(jsonStr, key, defaultVal)
}

_RelayJsonExtractStrArray(jsonStr, key) {
    return JsonCodec.GetStrArray(jsonStr, key)
}

ParseRelayEnvelope(rawMsg, pairingCode := "", password := "", replayGuard := "", allowLegacy := false, nowEpochSec := "") {
    msg := (Type(rawMsg) == "Buffer") ? StrGet(rawMsg, "UTF-8") : String(rawMsg)
    if ((InStr(msg, "PSGCM2|") || InStr(msg, "PSGCM1|")) && IsSet(DecryptRelayPayload)) {
        decOk := false
        plain := DecryptRelayPayload(msg, StrUpper(Trim(String(pairingCode))), password, &decOk)
        if (!decOk || plain = "")
            return { ok: false, encrypted: true, authError: true, replayRejected: false, clockSkewRejected: false, error: "decrypt_failed" }

        src := _RelayJsonExtractStr(plain, "src")
        cmd := _RelayJsonExtractStr(plain, "cmd")
        data := _RelayJsonExtractStr(plain, "data")
        auth := _RelayJsonExtractStr(plain, "auth")
        sid := _RelayJsonExtractStr(plain, "sid")
        seq := _RelayJsonExtractInt(plain, "seq", 0)
        ts := _RelayJsonExtractInt(plain, "ts", 0)

        if (src = "" || cmd = "")
            return { ok: false, encrypted: true, authError: true, replayRejected: false, clockSkewRejected: false, error: "malformed_json" }

        if (IsObject(replayGuard)) {
            senderKey := src (sid != "" ? (":" sid) : "")
            if (!replayGuard.Accept(senderKey, seq, ts, nowEpochSec)) {
                isSkew := (replayGuard.HasOwnProp("lastRejectReason") && replayGuard.lastRejectReason = "clock_skew")
                return { ok: false, encrypted: true, authError: false, replayRejected: !isSkew, clockSkewRejected: isSkew, error: (isSkew ? "clock_skew" : "replay_rejected"), src: src, cmd: cmd, seq: seq }
            }
        }

        hasTelemetry := (InStr(plain, '"recSeconds"') || InStr(plain, '"streamDropWarn"') || InStr(plain, '"voiceWhileMuted"') || InStr(plain, '"scenes"') || InStr(plain, '"activeScene"') || InStr(plain, '"osMicMutedDrift"') || InStr(plain, '"slideIndex"'))
        hasMutedField := (InStr(plain, '"isMuted"') != 0)
        return {
            ok: true,
            encrypted: true,
            authError: false,
            replayRejected: false,
            clockSkewRejected: false,
            src: src,
            cmd: cmd,
            data: data,
            auth: auth,
            seq: seq,
            ts: ts,
            sid: sid,
            hasMutedField: hasMutedField,
            isMuted: hasMutedField ? _RelayJsonExtractBool(plain, "isMuted", false) : (data = "1" || StrLower(data) = "true"),
            hasTelemetry: hasTelemetry,
            isStandby: _RelayJsonExtractBool(plain, "isStandby", false),
            recState: _RelayJsonExtractInt(plain, "recState", 0),
            recSeconds: Max(0, _RelayJsonExtractInt(plain, "recSeconds", 0)),
            streamDropWarn: _RelayJsonExtractBool(plain, "streamDropWarn", false),
            voiceWhileMuted: _RelayJsonExtractBool(plain, "voiceWhileMuted", false),
            osMicMutedDrift: _RelayJsonExtractBool(plain, "osMicMutedDrift", false),
            lowDiskWarnLevel: _RelayJsonExtractInt(plain, "lowDiskWarnLevel", 0),
            lowDiskMb: _RelayJsonExtractInt(plain, "lowDiskMb", -1),
            deadMicWarn: _RelayJsonExtractBool(plain, "deadMicWarn", false),
            slideIndex: Max(0, _RelayJsonExtractInt(plain, "slideIndex", 0)),
            slideTotal: Max(0, _RelayJsonExtractInt(plain, "slideTotal", 0)),
            slideTitle: _RelayJsonExtractStr(plain, "slideTitle"),
            timerState: _RelayJsonExtractStr(plain, "timerState"),
            timerRemainingSec: _RelayJsonExtractInt(plain, "timerRemainingSec", 600),
            timerPresetSec: Max(60, _RelayJsonExtractInt(plain, "timerPresetSec", 600)),
            activeScene: _RelayJsonExtractStr(plain, "activeScene"),
            scenes: _RelayJsonExtractStrArray(plain, "scenes")
        }
    }

    if (!allowLegacy)
        return ""
    pkt := ParseRelayPacket(msg)
    if (!IsObject(pkt))
        return ""
    return {
        ok: true,
        encrypted: false,
        authError: false,
        replayRejected: false,
        clockSkewRejected: false,
        src: pkt.src,
        cmd: pkt.cmd,
        data: pkt.data,
        auth: pkt.auth,
        seq: 0,
        ts: 0,
        sid: "",
        hasMutedField: (pkt.cmd = "state"),
        isMuted: (pkt.data = "1" || StrLower(pkt.data) = "true"),
        hasTelemetry: false,
        scenes: []
    }
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
    static lastHttpWarnTick := 0
    if (topic = "" || packetStr = "")
        return false
    if IsObject(mockTargetWs)
        return TrySendWsText(mockTargetWs, packetStr)
    ; Check any completed prior async requests for HTTP 429/413 rate-limit or payload warnings
    for _, prevWhr in activeRequests {
        try {
            if (prevWhr.WaitForResponse(0)) {
                stCode := Integer(prevWhr.Status)
                if ((stCode == 429 || stCode == 413) && (lastHttpWarnTick == 0 || (A_TickCount - lastHttpWarnTick) >= 30000)) {
                    lastHttpWarnTick := A_TickCount
                    if (IsSet(DiagnosticLogger))
                        try DiagnosticLogger.RecordBreadcrumb("Relay", "Http" stCode, "WAN Relay returned HTTP " stCode)
                    if (!IsSet(g_IsTestMode) || !g_IsTestMode)
                        try TrayTip(stCode == 429 ? "WAN Relay rate limited (HTTP 429) — slowing updates." : "WAN Relay message rejected (HTTP 413 too large).", "PresenterSync", 2)
                }
            }
        }
    }
    try {
        baseUrl := NormalizeRelayBaseUrl(relayBaseUrl)
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
    pairCode := cfg.HasOwnProp("InternetPairingCode") ? StrUpper(Trim(cfg.InternetPairingCode)) : ""
    topic := GetInternetRelayTopic(pairCode)
    if (topic = "")
        return false
    pw := _GetRelayPassword(cfg)
    if (ShouldUseRelayEncryption(cfg, state)) {
        jsonPayload := FormatRelayStatePayload(cfg, state, "dir_state")
        pkt := EncryptRelayPayload(jsonPayload, pairCode, pw)
        if (pkt = "")
            return false
    } else {
        auth := GetInternetRelayAuthToken(pairCode, pw)
        pkt := FormatRelayPacket("host", "dir_state", _BuildLegacyDirStatePayload(state), auth)
    }
    mockWs := (state.HasOwnProp("relayMockWs") && IsObject(state.relayMockWs)) ? state.relayMockWs : ""
    return PublishInternetRelayPacket(topic, pkt, GetEffectiveRelayBaseUrl(cfg), mockWs)
}

BroadcastHostRelayMuteState(cfg, state) {
    if (!IsObject(cfg) || !IsObject(state))
        return false
    HostBridgeBroadcastMuteState(cfg, state)
    if (!ShouldEnableHostInternetRelay(cfg))
        return false
    pairCode := cfg.HasOwnProp("InternetPairingCode") ? StrUpper(Trim(cfg.InternetPairingCode)) : ""
    topic := GetInternetRelayTopic(pairCode)
    if (topic = "")
        return false
    pw := _GetRelayPassword(cfg)
    if (ShouldUseRelayEncryption(cfg, state)) {
        jsonPayload := FormatRelayStatePayload(cfg, state, "state")
        pkt := EncryptRelayPayload(jsonPayload, pairCode, pw)
        if (pkt = "")
            return false
    } else {
        auth := GetInternetRelayAuthToken(pairCode, pw)
        pkt := FormatRelayPacket("host", "state", state.isMuted ? "1" : "0", auth)
    }
    mockWs := (state.HasOwnProp("relayMockWs") && IsObject(state.relayMockWs)) ? state.relayMockWs : ""
    return PublishInternetRelayPacket(topic, pkt, GetEffectiveRelayBaseUrl(cfg), mockWs)
}

UpdateHostInternetRelay(cfg, state) {
    if (!IsObject(cfg) || !IsObject(state))
        return
    if (state.HasOwnProp("relayTimerFn") && state.relayTimerFn)
        SetTimer state.relayTimerFn, 0
    if (ShouldEnableHostInternetRelay(cfg)) {
        desiredWsUrl := BuildRelayWsUrl(GetEffectiveRelayBaseUrl(cfg), GetInternetRelayTopic(cfg.HasOwnProp("InternetPairingCode") ? cfg.InternetPairingCode : ""))
        urlChanged := (state.HasOwnProp("_activeRelayWsUrl") && state._activeRelayWsUrl != "" && desiredWsUrl != "" && state._activeRelayWsUrl != desiredWsUrl)
        if (urlChanged) {
            state.relayConnected := false
            state._activeRelayWsUrl := ""
            if IsObject(state.relayWs) {
                try state.relayWs.shutdown()
                state.relayWs := ""
            }
        }
        if (!state.relayConnected && state.HasOwnProp("relayTimerFn") && state.relayTimerFn)
            SetTimer state.relayTimerFn, -80
    } else {
        state.relayConnected := false
        state._activeRelayWsUrl := ""
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
    wsUrl := BuildRelayWsUrl(GetEffectiveRelayBaseUrl(cfg), topic)
    if (wsUrl = "")
        return
    state._activeRelayWsUrl := wsUrl
    try {
        state.relayWs := WebSocket(wsUrl, {
            message: HandleHostRelayMessage.Bind(cfg, state),
            close: HandleHostRelayClose.Bind(cfg, state)
        }, true, "", 4000)
    } catch {
        state.relayWs := ""
        state._activeRelayWsUrl := ""
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
    state._activeRelayWsUrl := ""
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

    if (!state.HasOwnProp("relayReplayGuard") || !IsObject(state.relayReplayGuard)) {
        if (IsSet(RelayReplayGuard))
            state.relayReplayGuard := RelayReplayGuard()
    }
    guard := (state.HasOwnProp("relayReplayGuard") && IsObject(state.relayReplayGuard)) ? state.relayReplayGuard : ""
    pw := _GetRelayPassword(cfg)
    allowLegacy := (IsObject(cfg) && cfg.HasOwnProp("AllowLegacyPlaintextRelay") && cfg.AllowLegacyPlaintextRelay) ? true : false
    pkt := ParseRelayEnvelope(msg, cfg.InternetPairingCode, pw, guard, allowLegacy)
    if (!IsObject(pkt))
        return
    if (!pkt.ok) {
        if (IsSet(DiagnosticLogger))
            try DiagnosticLogger.RecordBreadcrumb("Relay", (pkt.HasOwnProp("clockSkewRejected") && pkt.clockSkewRejected) ? "ClockSkewRejected" : (pkt.replayRejected ? "ReplayRejected" : "DecryptRejected"), pkt.error)
        if (pkt.HasOwnProp("clockSkewRejected") && pkt.clockSkewRejected && (!IsSet(g_IsTestMode) || !g_IsTestMode)) {
            if (!state.HasOwnProp("_lastSkewWarnTick") || (A_TickCount - state._lastSkewWarnTick) >= 60000) {
                state._lastSkewWarnTick := A_TickCount
                try TrayTip("WAN Relay message rejected (>5 min clock skew). Sync system clock on Host and Remote.", "PresenterSync", 2)
            }
        }
        return
    }
    if (pkt.src != "remote")
        return

    topic := GetInternetRelayTopic(cfg.InternetPairingCode)
    expectedAuth := GetInternetRelayAuthToken(cfg.InternetPairingCode, pw)
    mockWs := (state.HasOwnProp("relayMockWs") && IsObject(state.relayMockWs)) ? state.relayMockWs : ""
    if (pkt.auth != expectedAuth) {
        PublishInternetRelayPacket(topic, FormatRelayPacket("host", "auth_error", "0", "none"), GetEffectiveRelayBaseUrl(cfg), mockWs)
        return
    }

    state._relayPeerLegacy := (allowLegacy && !pkt.encrypted)

    if (pkt.cmd = "sync_req") {
        BroadcastHostRelayMuteState(cfg, state)
        if (state._relayPeerLegacy) {
            hasDirActivity := (state.HasOwnProp("isStandby") && state.isStandby)
                || (state.HasOwnProp("timerState") && state.timerState != "stopped")
                || (state.HasOwnProp("recState") && state.recState > 0)
                || (state.HasOwnProp("streamDropWarn") && state.streamDropWarn)
                || (state.HasOwnProp("voiceWhileMuted") && state.voiceWhileMuted)
                || (_GetHostSceneListForRelay(state).Length > 0)
            if (hasDirActivity)
                BroadcastHostRelayDirectorState(cfg, state)
        }
    } else if (pkt.cmd = "toggle_mute") {
        ExecuteHostRemoteToggleMute(cfg, state)
    } else if (pkt.cmd = "set_mute") {
        wantMuted := (StrLower(Trim(String(pkt.data))) = "1" || StrLower(Trim(String(pkt.data))) = "true")
        ExecuteHostRemoteSetMute(cfg, state, wantMuted)
    } else if (pkt.cmd = "ppt_next") {
        ExecuteHostRemotePptCommand(cfg, state, "next")
    } else if (pkt.cmd = "ppt_prev") {
        ExecuteHostRemotePptCommand(cfg, state, "prev")
    } else if (pkt.cmd = "slide_start") {
        if (IsSet(StartPowerPointSlideshow))
            StartPowerPointSlideshow()
        BroadcastHostRelayMuteState(cfg, state)
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
    if (cfg.AudioRoutingMode != 2 && state.obsConnected && IsObject(state.obsWs) && SendObsToggleInputMuteGroup(cfg, state, state.obsWs, "HostClickerMute")) {
        if (IsSet(SyncUIState))
            SyncUIState(cfg, state, !state.isMuted, true)
        return true
    }
    return _DispatchHostRemoteControlSend(cfg, state, !state.isMuted)
}

ExecuteHostRemoteSetMute(cfg, state, targetMuted) {
    if (!IsObject(cfg) || !IsObject(state))
        return false
    wantMuted := !!targetMuted
    if (cfg.AudioRoutingMode != 2 && state.obsConnected && IsObject(state.obsWs) && SendObsSetInputMuteGroup(cfg, state.obsWs, wantMuted, "HostRemoteSetMute")) {
        if (IsSet(SyncUIState))
            SyncUIState(cfg, state, wantMuted, true)
        if (!!state.isMuted = wantMuted)
            BroadcastHostRelayMuteState(cfg, state)
        return true
    }
    if (!!state.isMuted != wantMuted)
        return _DispatchHostRemoteControlSend(cfg, state, wantMuted)
    BroadcastHostRelayMuteState(cfg, state)
    return true
}

_DispatchZoomOrLocalRecordState(cfg, state, targetState) {
    if (cfg.EnableZoom && state.zoomConnected && cfg.HasOwnProp("ZoomRecHotkey") && cfg.ZoomRecHotkey != "" && cfg.ZoomRecHotkey != "None") {
        confSpec := GetConferencingWindowSpec(cfg.HasOwnProp("ConferencingApp") ? cfg.ConferencingApp : "Zoom")
        ControlSendFast(cfg.ZoomRecHotkey, confSpec)
        state.zoomRecGraceUntil := A_TickCount + UIConstants.ZOOM_REC_GRACE_MS
    }
    SyncRecState(cfg, state, targetState)
    return true
}

ExecuteHostToggleRecord(cfg, state, requireStopConfirm := false) {
    if (!IsObject(cfg) || !IsObject(state))
        return false
    isRecording := (state.HasOwnProp("recState") && state.recState != 0) || (state.HasOwnProp("obsRecState") && state.obsRecState != 0)
    if (requireStopConfirm && isRecording && IsSet(TryConfirmStopRecording) && !TryConfirmStopRecording(cfg, state))
        return false
    if (cfg.EnableWS && state.obsConnected && IsObject(state.obsWs))
        return SendObsRequest(state.obsWs, "ToggleRecord", "ClickToggleRec")
    return _DispatchZoomOrLocalRecordState(cfg, state, state.recState == 0 ? 1 : 0)
}

ExecuteHostStartRecord(cfg, state) {
    if (!IsObject(cfg) || !IsObject(state))
        return false
    if (cfg.EnableWS && state.obsConnected && IsObject(state.obsWs))
        return SendObsRequest(state.obsWs, "StartRecord", "ClickStartRec")
    if (state.HasOwnProp("recState") && state.recState != 0)
        return false
    return _DispatchZoomOrLocalRecordState(cfg, state, 1)
}

ExecuteHostStopRecord(cfg, state) {
    if (!IsObject(cfg) || !IsObject(state))
        return false
    if (cfg.EnableWS && state.obsConnected && IsObject(state.obsWs))
        return SendObsRequest(state.obsWs, "StopRecord", "HoldStopRec")
    return _DispatchZoomOrLocalRecordState(cfg, state, 0)
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
        _CommitHostSceneChange(cfg, state, clean)
        return true
    }
    if (cfg.EnableWS && state.obsConnected && IsObject(state.obsWs)) {
        ok := SendObsRequest(state.obsWs, "SetCurrentProgramScene", "SwitchScene", '{"sceneName":"' EscapeJsonStr(clean) '"}')
        if (ok)
            _CommitHostSceneChange(cfg, state, clean)
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
            if (targetScene = "" && state.HasOwnProp("sceneList") && IsObject(state.sceneList) && state.sceneList.Length >= 2) {
                curIdx := 0
                for idx, scName in state.sceneList {
                    if (scName == curScene) {
                        curIdx := idx
                        break
                    }
                }
                nextIdx := (curIdx > 0) ? (Mod(curIdx, state.sceneList.Length) + 1) : 1
                cand := state.sceneList[nextIdx]
                if (cand == curScene && state.sceneList.Length >= 2)
                    cand := state.sceneList[(Mod(nextIdx, state.sceneList.Length) + 1)]
                if (cand != "" && cand != curScene)
                    targetScene := cand
            }
            if (targetScene != "") {
                dispatched := SendObsRequest(state.obsWs, "SetCurrentProgramScene", "HostSceneTransition", '{"sceneName":"' EscapeJsonStr(targetScene) '"}')
                detail := "ws:SetCurrentProgramScene:" targetScene
            }
        }
    }
    if (!dispatched && WinExist("ahk_exe obs64.exe") && cfg.HasOwnProp("ObsTransitionHotkey") && cfg.ObsTransitionHotkey != "None" && cfg.ObsTransitionHotkey != "") {
        ControlSendFast(cfg.ObsTransitionHotkey, "ahk_exe obs64.exe", 10)
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
        reqName := (state.recState == 1) ? "PauseRecord" : ((state.recState == 2) ? "ResumeRecord" : "ToggleRecordPause")
        ok := SendObsRequest(state.obsWs, reqName, "HostPauseRec")
        if (ok && (state.recState == 1 || state.recState == 2))
            SyncRecState(cfg, state, state.recState == 1 ? 2 : 1)
        return ok
    }
    if (cfg.EnableZoom && state.zoomConnected && cfg.HasOwnProp("ZoomPauseHotkey") && cfg.ZoomPauseHotkey != "" && cfg.ZoomPauseHotkey != "None") {
        confSpec := GetConferencingWindowSpec(cfg.HasOwnProp("ConferencingApp") ? cfg.ConferencingApp : "Zoom")
        ControlSendFast(cfg.ZoomPauseHotkey, confSpec)
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
        safeExitMuted := (!cfg.HasOwnProp("ExitBrbSafelyMuted") || cfg.ExitBrbSafelyMuted)
        state.isStandby := false
        state.standbySnapshot := ""
        if (IsObject(snap)) {
            if (snap.HasOwnProp("scene") && snap.scene != "" && ((cfg.EnableWS && state.obsConnected && IsObject(state.obsWs)) || (state.HasOwnProp("obsSceneSwitchFn") && IsObject(state.obsSceneSwitchFn))))
                ExecuteHostSwitchScene(cfg, state, snap.scene)
            if (snap.HasOwnProp("recWasActive") && snap.recWasActive && state.HasOwnProp("recState") && state.recState == 2)
                ExecuteHostPauseRecord(cfg, state)
        }
        if (safeExitMuted) {
            if (!state.isMuted)
                ExecuteHostRemoteSetMute(cfg, state, true)
        } else if (IsObject(snap) && snap.HasOwnProp("muted")) {
            ExecuteHostRemoteSetMute(cfg, state, snap.muted)
        }
        if (IsSet(ShowStageNudgeBanner) && (!state.HasOwnProp("suppressNudgeBanners") || !state.suppressNudgeBanners))
            ShowStageNudgeBanner(safeExitMuted ? "Standby Mode OFF — Session Restored (Mic Kept Safely Muted)" : "Standby Mode OFF — Session Restored", "10B981", 3200, "Director")
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
        HostBridgeBroadcastMuteState(cfg, state)
        BroadcastHostRelayDirectorState(cfg, state)
        return true
    }
    if (prevRem == 121 && state.timerRemainingSec == 120) {
        BroadcastHostStageNudge(cfg, state, "2:00 Remaining", "Timer", "F59E0B")
        HostBridgeBroadcastMuteState(cfg, state)
        BroadcastHostRelayDirectorState(cfg, state)
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

BroadcastHostStageNudge(cfg, state, message, sender := "Stage", accentHex := "F59E0B", opts := "") {
    msgClean := SubStr(Trim(String(message)), 1, 140)
    if (msgClean = "")
        return false
    senderClean := SubStr(Trim(String(sender)), 1, 40)
    if (senderClean = "")
        senderClean := "Stage"
    accClean := IsSet(NormalizeColorHex) ? NormalizeColorHex(accentHex, "F59E0B") : "F59E0B"
    if (IsSet(ShowStageNudgeBanner) && (!IsObject(state) || !state.HasOwnProp("suppressNudgeBanners") || !state.suppressNudgeBanners))
        ShowStageNudgeBanner(msgClean, accClean, 4500, senderClean)
    HostBridgeBroadcastStageNudge(cfg, state, msgClean, senderClean, accClean, opts)
    if (IsSet(SessionTimeline))
        SessionTimeline.Record("Intercom", "Stage Cue (" senderClean "): " msgClean, state)
    if (ShouldEnableHostInternetRelay(cfg)) {
        topic := GetInternetRelayTopic(cfg.HasOwnProp("InternetPairingCode") ? cfg.InternetPairingCode : "")
        if (topic != "") {
            safeMsg := StrReplace(StrReplace(msgClean, "|", "/"), ";", ",")
            safeSender := StrReplace(StrReplace(senderClean, "|", "/"), ";", ",")
            pkt := BuildOutboundRelayPacket(cfg, state, "host", "nudge", safeSender ";" safeMsg)
            mockWs := (IsObject(state) && state.HasOwnProp("relayMockWs") && IsObject(state.relayMockWs)) ? state.relayMockWs : ""
            PublishInternetRelayPacket(topic, pkt, GetEffectiveRelayBaseUrl(cfg), mockWs)
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
    if (cfg.AudioRoutingMode == 3 && (obsCanSend || confCanSend))
        _EngageSyncLock(state, "manual")
    if (obsCanSend)
        sentObs := ControlSendFast(cfg.ObsMuteHotkey, "ahk_exe obs64.exe")
    if (confCanSend)
        sentConf := ControlSendFast(confHk, confSpec)
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
        mockWs := (IsObject(state) && state.HasOwnProp("relayMockWs") && IsObject(state.relayMockWs)) ? state.relayMockWs : ""
        if (topic != "")
            sentWan := PublishInternetRelayPacket(topic, BuildOutboundRelayPacket(cfg, state, "host", "close_remote", "1"), GetEffectiveRelayBaseUrl(cfg), mockWs)
    }

    return (sentLan || sentWan || sentBridge)
}

FormatPassthroughHook(hk) {
    return "~$" StripHotkeyModifiers(hk)
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

ApplyHostObsCredentialsChange(cfg, state, oldPw, oldMic := "") {
    if (!IsObject(cfg))
        return false
    pwChanged := (String(cfg.obsPassword) !== String(oldPw))
    micChanged := (oldMic != "" && String(cfg.targetMicName) !== String(oldMic))
    if (!pwChanged && !micChanged)
        return false
    if (IsSet(DiagnosticLogger))
        try DiagnosticLogger.RecordBreadcrumb("OBS", "CredentialsChangedReconnect", "pw=" (pwChanged ? 1 : 0) " mic=" (micChanged ? 1 : 0))
    if (IsObject(state) && cfg.HasOwnProp("EnableWS") && cfg.EnableWS) {
        if (state.HasOwnProp("obsWs") && IsObject(state.obsWs)) {
            SafeCloseWebSocketDeferred(state.obsWs, 40)
            state.obsWs := ""
        }
        if (state.HasOwnProp("obsConnected"))
            state.obsConnected := false
        if (state.HasOwnProp("obsTimerFn") && state.obsTimerFn)
            SetTimer(state.obsTimerFn, -100)
    }
    if (IsSet(HostBridgeBroadcastObsFallback))
        try HostBridgeBroadcastObsFallback(cfg)
    if (IsObject(state))
        try BroadcastHostRelayMuteState(cfg, state)
    return true
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
                if (IsSet(HostBridgeBroadcastObsFallback))
                    try HostBridgeBroadcastObsFallback(cfg)
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
        if (IsObject(state) && state.HasOwnProp("obsTimerFn") && IsObject(state.obsTimerFn))
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
        if (!(state.HasOwnProp("hasEverConnectedObsThisRun") && state.hasEverConnectedObsThisRun)) {
            state.hasEverConnectedObsThisRun := true
            if (IsObject(cfg) && cfg.HasOwnProp("AutoMuteOnFirstObsConnect") && cfg.AutoMuteOnFirstObsConnect) {
                if (IsSet(DiagnosticLogger))
                    try DiagnosticLogger.RecordBreadcrumb("Safety", "AutoMuteOnFirstObsConnect", "first OBS Identified")
                ExecuteHostRemoteSetMute(cfg, state, true)
            }
        }
        if state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn
            try state.refreshHelpFn.Call()
    }
    else if (opCode == 5) {
        if (RegExMatch(msg, '"eventType"\s*:\s*"InputMuteStateChanged"')) {
            if (RegExMatch(msg, '"inputName"\s*:\s*"((?:[^"\\]|\\.)*)"', &matchInput) && UnescapeJsonStr(matchInput[1]) == cfg.targetMicName) {
                if (RegExMatch(msg, '"inputMuted"\s*:\s*(true|false)', &matchMuted)) {
                    isMutedOBS := (matchMuted[1] == "true")
                    SyncUIState(cfg, state, isMutedOBS)
                    PushObsMuteToZoom(cfg, state, isMutedOBS)
                }
            }
        }
        else if (InStr(msg, '"eventType":"RecordStateChanged"') || InStr(msg, '"eventType": "RecordStateChanged"')) {
            if (RegExMatch(msg, '"outputState"\s*:\s*"([^"]+)"', &matchRecOut)) {
                outState := matchRecOut[1]
                if (outState = "OBS_WEBSOCKET_OUTPUT_STARTED" || outState = "OBS_WEBSOCKET_OUTPUT_RESUMED") {
                    SyncRecState(cfg, state, 1)
                    if (IsObject(ws))
                        SendObsRequest(ws, "GetRecordStatus", "SyncRecStatus")
                } else if (outState = "OBS_WEBSOCKET_OUTPUT_PAUSED") {
                    SyncRecState(cfg, state, 2)
                    if (IsObject(ws))
                        SendObsRequest(ws, "GetRecordStatus", "SyncRecStatus")
                } else if (outState = "OBS_WEBSOCKET_OUTPUT_STOPPED") {
                    SyncRecState(cfg, state, 0)
                }
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
            if (parsedScenes.Length > 0) {
                state.sceneList := parsedScenes
                HostBridgeBroadcastMuteState(cfg, state)
                BroadcastHostRelayDirectorState(cfg, state)
            } else if IsObject(ws) {
                SendObsRequest(ws, "GetSceneList", "InitSceneList")
            }
        }
    }
    else if (opCode == 7) {
        if (InStr(msg, '"requestId":"InitState"') || InStr(msg, '"requestId": "InitState"')
            || InStr(msg, '"requestId":"ReconcileObsMute"') || InStr(msg, '"requestId": "ReconcileObsMute"')) {
            if (RegExMatch(msg, '"result"\s*:\s*false')) {
                if (InStr(msg, "InitState"))
                    TrayTip("Audio source '" cfg.targetMicName "' was not found in OBS Studio.", "PresenterSync", 2)
                else if (IsSet(RollbackHostOptimisticMute))
                    RollbackHostOptimisticMute(cfg, state, "OBS rejected mute query")
            } else if (RegExMatch(msg, '"inputMuted"\s*:\s*(true|false)', &matchMuted)) {
                isMutedOBS := (matchMuted[1] == "true")
                PushObsMuteToZoom(cfg, state, isMutedOBS)
                SyncUIState(cfg, state, isMutedOBS, false)
                BroadcastHostRelayMuteState(cfg, state)
            }
        }
        else if (InStr(msg, '"requestId":"HostClickerMute"') || InStr(msg, '"requestId": "HostClickerMute"')
            || InStr(msg, '"requestId":"HostRemoteSetMute"') || InStr(msg, '"requestId": "HostRemoteSetMute"')
            || InStr(msg, '"requestId":"RemoteClickerMute"') || InStr(msg, '"requestId": "RemoteClickerMute"')
            || InStr(msg, '"requestId":"RemoteClickerSetMute"') || InStr(msg, '"requestId": "RemoteClickerSetMute"')) {
            if (RegExMatch(msg, '"result"\s*:\s*false')) {
                if (IsSet(ShowCaptureSafeMicroToast))
                    ShowCaptureSafeMicroToast("PresenterSync: Audio source '" cfg.targetMicName "' not found in OBS", 2500)
                if (IsSet(RollbackHostOptimisticMute))
                    RollbackHostOptimisticMute(cfg, state, "OBS returned an error")
            }
        }
        else if (InStr(msg, '"requestId":"HostSceneTransition"') || InStr(msg, '"requestId": "HostSceneTransition"')) {
            if (RegExMatch(msg, '"result"\s*:\s*false')) {
                if (IsSet(DiagnosticLogger))
                    DiagnosticLogger.RecordBreadcrumb("OBS", "HostSceneTransitionFailed", SubStr(msg, 1, 200))
                if (!IsSet(g_IsTestMode) || !g_IsTestMode) {
                    if (IsSet(ShowCaptureSafeMicroToast))
                        ShowCaptureSafeMicroToast("PresenterSync: OBS scene transition failed (check Studio Mode / scenes)", 2500)
                }
            }
        }
        else if (InStr(msg, '"requestId":"InitRecState"') || InStr(msg, '"requestId": "InitRecState"')
            || InStr(msg, '"requestId":"SyncRecStatus"') || InStr(msg, '"requestId": "SyncRecStatus"')
            || InStr(msg, '"requestId":"PollRecStatus"') || InStr(msg, '"requestId": "PollRecStatus"')) {
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
                BroadcastHostRelayDirectorState(cfg, state)
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

    _EngageSyncLock(state, "obs")
    targetWin := zoomState.micHwnd ? ("ahk_id " zoomState.micHwnd) : confSpec
    if (IsObject(sendFn)) {
        sendFn.Call(FormatSendKey(confHk), targetWin)
    } else {
        ControlSendFast(confHk, targetWin)
    }
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
    CheckConfMeetingEndAutoMute(cfg, state, zoomInfo.hasMic)
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
            if (!sentObs && cfg.ObsMuteHotkey != "None" && cfg.ObsMuteHotkey != "" && WinExist("ahk_exe obs64.exe"))
                sentObs := ControlSendFast(cfg.ObsMuteHotkey, "ahk_exe obs64.exe")
            if (sentObs)
                _EngageSyncLock(state, "zoom")
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
    if (!IsObject(state) || !state.HasOwnProp("zoomTimerFn") || !IsObject(state.zoomTimerFn))
        return
    if (cfg.EnableZoom || cfg.AudioRoutingMode == 3)
        SetTimer state.zoomTimerFn, UIConstants.ZOOM_POLL_INTERVAL_MS
    else
        SetTimer state.zoomTimerFn, 0
}
