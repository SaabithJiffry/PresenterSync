; ==============================================================================
; Module: DiagnosticLogger.ahk
; Description: Persistent Error, Latency & 5-Section Context Snapshot Logger
;              with rolling 5 MB rotation (.log + .jsonl) and 50-event
;              pre-error breadcrumb ring buffer.
; ==============================================================================

class DiagnosticLogger {
    static LogDir := A_ScriptDir "\logs"
    static AppName := "PresenterSync"
    static MaxLogBytes := 5242880 ; 5 MB
    static Breadcrumbs := []
    static MaxBreadcrumbs := 50
    static CfgRef := ""
    static StateRef := ""
    static Initialized := false
    static _IsLogging := false

    static Init(appName := "PresenterSync", cfg := "", state := "") {
        if (appName != "")
            this.AppName := String(appName)
        if (IsObject(cfg) || cfg != "")
            this.CfgRef := cfg
        if (IsObject(state) || state != "")
            this.StateRef := state

        if (!this.Initialized) {
            OnError((err, mode) => DiagnosticLogger.OnGlobalError(err, mode))
            this.Initialized := true
        }
    }

    static BindContext(cfg := "", state := "") {
        this.CfgRef := cfg
        this.StateRef := state
    }

    static GetLogPath() {
        return this.LogDir "\" this.AppName "_ErrorLog.log"
    }

    static GetJsonlPath() {
        return this.LogDir "\" this.AppName "_ErrorLog.jsonl"
    }

    static OnGlobalError(err, mode) {
        sev := (mode = "ExitApp") ? "CRITICAL" : "ERROR"
        msg := IsObject(err) && err.HasOwnProp("Message") ? String(err.Message) : String(err)
        this.LogIssue(sev, "GlobalOnError", msg, "Unhandled AutoHotkey v2 runtime error (mode=" String(mode) ").", err)
        return 0
    }

    static RecordBreadcrumb(category, action, detail := "") {
        entry := {
            tick: A_TickCount,
            time: FormatTime(, "HH:mm:ss"),
            category: String(category),
            action: String(action),
            detail: String(detail)
        }
        this.Breadcrumbs.Push(entry)
        while (this.Breadcrumbs.Length > this.MaxBreadcrumbs)
            this.Breadcrumbs.RemoveAt(1)
    }

    static CheckLatency(category, action, startTick, thresholdMs := 120, detail := "") {
        elapsed := A_TickCount - startTick
        this.RecordBreadcrumb(category, action, "elapsed=" elapsed "ms" (detail != "" ? (" | " detail) : ""))
        if (elapsed > thresholdMs) {
            this.LogIssue(
                "PERF_LAG",
                category,
                action " took " elapsed "ms (threshold " thresholdMs "ms)",
                "Main-thread timer, COM/WMI call, or hotkey callback exceeded " thresholdMs "ms latency budget." (detail != "" ? (" " detail) : "")
            )
        }
        return elapsed
    }

    static LogIssue(severity, subsystem, message, howItHappenedRemark := "", errObj := "") {
        if (this._IsLogging)
            return false
        this._IsLogging := true
        try {
            if (!DirExist(this.LogDir))
                DirCreate(this.LogDir)

            logPath := this.GetLogPath()
            jsonlPath := this.GetJsonlPath()
            this._RotateIfNeeded(logPath, this.LogDir "\" this.AppName "_ErrorLog.1.log")
            this._RotateIfNeeded(jsonlPath, this.LogDir "\" this.AppName "_ErrorLog.1.jsonl")

            localTs := FormatTime(, "yyyy-MM-dd HH:mm:ss")
            utcTs := FormatTime(A_NowUTC, "yyyy-MM-dd HH:mm:ss") " UTC"
            sev := StrUpper(Trim(String(severity)))
            if (sev = "")
                sev := "ERROR"

            secrets := this._CollectSecrets(this.CfgRef)

            ; --- [1. ERROR & CAUSAL REMARK] ---
            sec1 := "[1. ERROR & CAUSAL REMARK]`r`n"
                . "  Local Time      : " localTs "`r`n"
                . "  UTC Time        : " utcTs "`r`n"
                . "  Severity        : " sev "`r`n"
                . "  Subsystem       : " String(subsystem) "`r`n"
                . "  Message         : " String(message) "`r`n"
                . "  How It Happened : " (howItHappenedRemark != "" ? String(howItHappenedRemark) : "(none provided)") "`r`n"
            if (IsObject(errObj)) {
                eMsg := errObj.HasOwnProp("Message") ? String(errObj.Message) : ""
                eWhat := errObj.HasOwnProp("What") ? String(errObj.What) : ""
                eExtra := errObj.HasOwnProp("Extra") ? String(errObj.Extra) : ""
                eFile := errObj.HasOwnProp("File") ? String(errObj.File) : ""
                eLine := errObj.HasOwnProp("Line") ? String(errObj.Line) : ""
                eStack := errObj.HasOwnProp("Stack") ? String(errObj.Stack) : ""
                sec1 .= "  Exception.Msg   : " eMsg "`r`n"
                    . "  Exception.What  : " eWhat "`r`n"
                    . "  Exception.Extra : " eExtra "`r`n"
                    . "  Exception.Loc   : " eFile ":" eLine "`r`n"
                    . "  Exception.Stack : " StrReplace(StrReplace(eStack, "`r", " "), "`n", " | ") "`r`n"
            }

            ; --- [2. SYSTEM DETAILS SNAPSHOT] ---
            memKB := this._GetWorkingSetKB()
            monCount := 1
            try monCount := MonitorGetCount()
            fgTitle := ""
            fgProc := ""
            try fgTitle := WinGetTitle("A")
            try fgProc := WinGetProcessName("A")
            ipStr := this._GetLocalIPsText()

            sec2 := "[2. SYSTEM DETAILS SNAPSHOT]`r`n"
                . "  OS Version      : " A_OSVersion " (64-bit OS: " (A_Is64bitOS ? "Yes" : "No") ", Admin: " (A_IsAdmin ? "Yes" : "No") ")`r`n"
                . "  Computer Name   : " A_ComputerName "`r`n"
                . "  Working Set Mem : " memKB " KB`r`n"
                . "  Monitor Count   : " monCount "`r`n"
                . "  Foreground Win  : " (fgProc != "" ? fgProc : "(unknown)") " | " (fgTitle != "" ? fgTitle : "(untitled)") "`r`n"
                . "  Local IPs       : " ipStr "`r`n"

            ; --- [3. PROGRAM & LIVE STATE SNAPSHOT] ---
            appVer := IsSet(UIConstants) ? UIConstants.APP_VERSION : "unknown"
            suspendLocks := IsSet(Theme) ? Theme.SuspendLockCount : 0
            stateLines := this._FormatStateSnapshot(this.StateRef)

            sec3 := "[3. PROGRAM & LIVE STATE SNAPSHOT]`r`n"
                . "  App / Version   : " this.AppName " v" appVer " (Compiled: " (A_IsCompiled ? "Yes" : "No") ")`r`n"
                . "  Uptime (ms)     : " A_TickCount "`r`n"
                . "  Hotkeys Susp.   : " (A_IsSuspended ? "Yes" : "No") " (SuspendLockCount=" suspendLocks ")`r`n"
                . stateLines

            ; --- [4. SANITIZED SETTINGS SNAPSHOT] ---
            sec4 := "[4. SANITIZED SETTINGS SNAPSHOT]`r`n"
                . this._FormatSettingsSnapshot(this.CfgRef)

            ; --- [5. PRE-ERROR BREADCRUMB TRAIL (LAST 50 EVENTS)] ---
            nowTick := A_TickCount
            sec5 := "[5. PRE-ERROR BREADCRUMB TRAIL (LAST " this.MaxBreadcrumbs " EVENTS)]`r`n"
            if (this.Breadcrumbs.Length == 0) {
                sec5 .= "  (no breadcrumbs recorded)`r`n"
            } else {
                for _, bc in this.Breadcrumbs {
                    delta := nowTick - bc.tick
                    sec5 .= "  T-" delta " ms (" bc.time ") | [" bc.category "] " bc.action (bc.detail != "" ? (" | " bc.detail) : "") "`r`n"
                }
            }

            fullEntry := "==============================================================================`r`n"
                . sec1 . sec2 . sec3 . sec4 . sec5
                . "==============================================================================`r`n`r`n"
            fullEntry := this._ScrubSecrets(fullEntry, secrets)

            try FileAppend(fullEntry, logPath, "UTF-8")

            ; --- Single-line JSONL record ---
            jsonLine := "{"
                . "`"timestampLocal`":`"" this._JsonEsc(localTs) "`","
                . "`"timestampUtc`":`"" this._JsonEsc(utcTs) "`","
                . "`"severity`":`"" this._JsonEsc(sev) "`","
                . "`"subsystem`":`"" this._JsonEsc(String(subsystem)) "`","
                . "`"message`":`"" this._JsonEsc(String(message)) "`","
                . "`"remark`":`"" this._JsonEsc(String(howItHappenedRemark)) "`","
                . "`"appName`":`"" this._JsonEsc(this.AppName) "`","
                . "`"appVersion`":`"" this._JsonEsc(appVer) "`","
                . "`"osVersion`":`"" this._JsonEsc(A_OSVersion) "`","
                . "`"memKB`":" memKB ","
                . "`"uptimeMs`":" A_TickCount ","
                . "`"breadcrumbsCount`":" this.Breadcrumbs.Length
                . "}`n"
            jsonLine := this._ScrubSecrets(jsonLine, secrets)
            try FileAppend(jsonLine, jsonlPath, "UTF-8")
            return true
        } finally {
            this._IsLogging := false
        }
    }

    static GetRecentLogTail(maxChars := 12000) {
        logPath := this.GetLogPath()
        if (!FileExist(logPath))
            return "(no persistent error log entries recorded)"
        try {
            txt := FileRead(logPath, "UTF-8")
            if (Trim(txt, " `t`r`n") = "")
                return "(no persistent error log entries recorded)"
            if (StrLen(txt) > maxChars)
                return "...(truncated to last " maxChars " chars)...`r`n" SubStr(txt, StrLen(txt) - maxChars + 1)
            return txt
        } catch {
            return "(unable to read persistent error log)"
        }
    }

    static ShowLogViewerWindow(cfg := "", state := "") {
        logPath := this.GetLogPath()
        if (IsSet(g_IsTestMode) && g_IsTestMode)
            return {shown: false, testMode: true, logPath: logPath}

        winKey := "DiagnosticLogViewer"
        existing := IsSet(Theme) ? Theme.FocusExistingWindow(winKey) : ""
        if (IsObject(existing))
            return {shown: true, testMode: false, logPath: logPath, gui: existing}

        vGui := Gui("+Resize +MinSize640x420", "PresenterSync - Error & Diagnostic Log")
        vGui.MarginX := 12
        vGui.MarginY := 10
        vGui.SetFont("s9", "Consolas")

        edLog := vGui.Add("Edit", "w780 h460 ReadOnly Multi -Wrap HScroll VScroll", this.GetRecentLogTail(60000))
        vGui.SetFont("s9", "Segoe UI")
        btnRefresh := vGui.Add("Button", "x12 y+10 w95 h28", "Refresh")
        btnCopy := vGui.Add("Button", "x+8 w95 h28", "Copy Log")
        btnOpenDir := vGui.Add("Button", "x+8 w125 h28", "Open Log Folder")
        btnClear := vGui.Add("Button", "x+8 w95 h28", "Clear Log")
        btnClose := vGui.Add("Button", "x+8 w95 h28 Default", "Close")

        if (IsSet(Theme)) {
            Theme.NamedWindows[winKey] := vGui
            Theme.ApplyToWindow(vGui)
            Theme.RegisterControl(vGui, edLog, "Edit")
            for _, b in [btnRefresh, btnCopy, btnOpenDir, btnClear, btnClose]
                Theme.RegisterControl(vGui, b, "Button")
        }
        if (IsSet(ProtectWindowFromCapture))
            try ProtectWindowFromCapture(vGui.Hwnd, true)

        btnRefresh.OnEvent("Click", (*) => (edLog.Value := DiagnosticLogger.GetRecentLogTail(60000)))
        btnCopy.OnEvent("Click", (*) => (A_Clipboard := edLog.Value, TrayTip("Diagnostic log copied to clipboard.", "PresenterSync", 1)))
        btnOpenDir.OnEvent("Click", (*) => (
            (!DirExist(DiagnosticLogger.LogDir) ? DirCreate(DiagnosticLogger.LogDir) : 0),
            Run('explorer.exe "' DiagnosticLogger.LogDir '"')
        ))
        btnClear.OnEvent("Click", (*) => (
            (FileExist(DiagnosticLogger.GetLogPath()) ? FileDelete(DiagnosticLogger.GetLogPath()) : 0),
            (FileExist(DiagnosticLogger.GetJsonlPath()) ? FileDelete(DiagnosticLogger.GetJsonlPath()) : 0),
            edLog.Value := DiagnosticLogger.GetRecentLogTail(60000)
        ))
        CloseViewer(*) {
            if (IsSet(Theme))
                Theme.UnregisterWindow(vGui, winKey)
            vGui.Destroy()
        }
        btnClose.OnEvent("Click", CloseViewer)
        vGui.OnEvent("Close", CloseViewer)
        vGui.OnEvent("Escape", CloseViewer)
        vGui.OnEvent("Size", (g, minMax, w, h) => (
            (minMax = 1) ? 0 : (
                edLog.Move(12, 10, Max(300, w - 24), Max(200, h - 58)),
                btnRefresh.Move(12, h - 38),
                btnCopy.Move(115, h - 38),
                btnOpenDir.Move(218, h - 38),
                btnClear.Move(351, h - 38),
                btnClose.Move(454, h - 38)
            )
        ))

        vGui.Show("w804 h518")
        return {shown: true, testMode: false, logPath: logPath, gui: vGui}
    }

    static _RotateIfNeeded(filePath, backupPath) {
        if (FileExist(filePath)) {
            sz := 0
            try sz := FileGetSize(filePath)
            if (sz >= this.MaxLogBytes) {
                try FileMove(filePath, backupPath, 1)
            }
        }
    }

    static _GetWorkingSetKB() {
        try {
            pmcSize := (A_PtrSize = 8) ? 72 : 40
            pmc := Buffer(pmcSize, 0)
            NumPut("UInt", pmcSize, pmc, 0)
            hProc := DllCall("GetCurrentProcess", "Ptr")
            if (DllCall("psapi\GetProcessMemoryInfo", "Ptr", hProc, "Ptr", pmc, "UInt", pmcSize)) {
                wsOffset := (A_PtrSize = 8) ? 24 : 12
                return Round(NumGet(pmc, wsOffset, "UPtr") / 1024)
            }
        }
        return 0
    }

    static _GetLocalIPsText() {
        ips := []
        try {
            for _, ip in SysGetIPAddresses() {
                s := Trim(String(ip))
                isUsableV4 := IsSet(IsUsableLanIPv4) ? IsUsableLanIPv4(s) : (InStr(s, ".") && s != "127.0.0.1" && s != "0.0.0.0" && !RegExMatch(s, "^169\.254\."))
                if (isUsableV4 || (InStr(s, ":") && s != "::1"))
                    ips.Push(s)
            }
        }
        if (ips.Length == 0)
            return "(none)"
        out := ""
        for idx, ip in ips
            out .= (idx > 1 ? ", " : "") ip
        return out
    }

    static _FormatStateSnapshot(state) {
        if (!IsObject(state))
            return "  StateRef        : (uninitialized)`r`n"
        fields := ["obsConnected", "studioModeActive", "currentSceneName", "previewSceneName", "isMuted", "recState", "streamState", "zoomConnected", "IsSyncing", "usingBridge"]
        out := ""
        for _, f in fields {
            val := state.HasOwnProp(f) ? String(state.%f%) : "(n/a)"
            out .= "  " Format("{:-16}", f) ": " val "`r`n"
        }
        return out
    }

    static _FormatSettingsSnapshot(cfg) {
        if (!IsObject(cfg))
            return "  CfgRef          : (uninitialized)`r`n"
        fields := ["ActiveProfile", "AudioRoutingMode", "EnablePPT", "EnableMicOnly", "EnablePointerTransition", "HwMuteHotkey", "ObsMuteHotkey", "HwTransitionHotkey", "ObsTransitionHotkey", "EnableWS", "EnableZoom", "CatchArrows", "CatchPg", "CatchPgUpDn", "CatchSpace", "CatchEnter", "CatchTab", "CatchB", "CatchEsc", "RemoteNetworkMode", "BridgePort"]
        secretFields := ["obsPassword", "ObsPassword", "InternetPairingCode", "SessionPairingCode", "SessionToken"]
        out := ""
        for _, f in fields {
            if (cfg.HasOwnProp(f))
                out .= "  " Format("{:-18}", f) ": " String(cfg.%f%) "`r`n"
        }
        for _, sf in secretFields {
            if (cfg.HasOwnProp(sf)) {
                sv := Trim(String(cfg.%sf%))
                out .= "  " Format("{:-18}", sf) ": " (sv != "" ? "[REDACTED]" : "(empty)") "`r`n"
            }
        }
        return out
    }

    static _CollectSecrets(cfg) {
        secrets := []
        if (!IsObject(cfg))
            return secrets
        seen := Map()
        for _, sf in ["obsPassword", "ObsPassword", "InternetPairingCode", "SessionPairingCode", "SessionToken"] {
            if (cfg.HasOwnProp(sf)) {
                sv := Trim(String(cfg.%sf%))
                if (StrLen(sv) >= 4 && !seen.Has(sv)) {
                    seen[sv] := true
                    secrets.Push(sv)
                }
            }
        }
        ; Sort longest-first so shorter secrets never partially mask longer ones
        Loop secrets.Length {
            i := A_Index
            Loop (secrets.Length - i) {
                j := i + A_Index
                if (StrLen(secrets[j]) > StrLen(secrets[i])) {
                    tmp := secrets[i]
                    secrets[i] := secrets[j]
                    secrets[j] := tmp
                }
            }
        }
        return secrets
    }

    static _ScrubSecrets(txt, secrets) {
        out := String(txt)
        if (IsObject(secrets)) {
            for _, s in secrets
                out := StrReplace(out, s, "[REDACTED]")
        }
        ; Scrub AES-256-GCM relay envelopes, legacy relay auth tokens, bearer/header tokens, JSON secret fields & pairing URI params
        out := RegExReplace(out, "PSGCM1\|[A-Za-z0-9+/=]+\|[A-Za-z0-9+/=]+", "PSGCM1|[REDACTED]")
        out := RegExReplace(out, "(PSRELAY\|[^|\r\n`"]+\|[^|\r\n`"]+\|[^|\r\n`"]*\|)[^|\r\n\s`"}]+", "$1[REDACTED]")
        out := RegExReplace(out, "i)(\\`"?(?:obsPassword|password|sessionToken|token|internetPairingCode|sessionPairingCode|code|auth)\\`"?\s*:\s*\\?`")[^`"\r\n]+", "$1[REDACTED]")
        out := RegExReplace(out, "i)(X-PresenterSync-Token\s*:\s*)[^\r\n\s]+", "$1[REDACTED]")
        out := RegExReplace(out, "i)(Authorization\s*:\s*Bearer\s+)[^\r\n\s]+", "$1[REDACTED]")
        out := RegExReplace(out, "i)([?&](?:pw|password|token|code|pair)=)[^&\s`"'<>]+", "$1[REDACTED]")
        return out
    }

    static _JsonEsc(s) {
        out := String(s)
        out := StrReplace(out, "\", "\\")
        out := StrReplace(out, '"', '\"')
        out := StrReplace(out, "`r", "\r")
        out := StrReplace(out, "`n", "\n")
        out := StrReplace(out, "`t", "\t")
        return out
    }
}
