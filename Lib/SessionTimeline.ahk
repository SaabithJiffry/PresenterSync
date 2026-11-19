; ==============================================================================
; Module: SessionTimeline.ahk
; Description: Bounded rolling session activity timeline and video editor chapter
;              CSV / Markdown exporter for PresenterSync Primary Host.
; ==============================================================================

class SessionTimeline {
    static MAX_ENTRIES := 2000
    static Entries := []
    static SessionStartUtc := ""
    static _NextSeq := 1
    static AutosaveFile := A_ScriptDir "\logs\SessionTimeline_active.jsonl"
    static EnableAutosave := true

    static _EnsureInit() {
        if (this.SessionStartUtc = "")
            this.SessionStartUtc := A_NowUTC
    }

    static Clear() {
        this.Entries := []
        this.SessionStartUtc := A_NowUTC
        this._NextSeq := 1
    }

    static FormatHms(totalSec) {
        s := Max(0, Integer(totalSec))
        hrs := s // 3600
        mins := Mod(s, 3600) // 60
        secs := Mod(s, 60)
        return Format("{:02}:{:02}:{:02}", hrs, mins, secs)
    }

    static FormatYouTubeTimestamp(totalSec) {
        s := Max(0, Integer(totalSec))
        hrs := s // 3600
        mins := Mod(s, 3600) // 60
        secs := Mod(s, 60)
        if (hrs > 0)
            return Format("{}:{:02}:{:02}", hrs, mins, secs)
        return Format("{:02}:{:02}", mins, secs)
    }

    static _CategoryToMarkerColor(category) {
        switch StrLower(Trim(String(category))) {
            case "recording": return "Red"
            case "scene": return "Blue"
            case "standby": return "Yellow"
            case "alert": return "Orange"
            case "slide": return "Cyan"
            case "mic": return "Green"
            case "remote": return "Purple"
            default: return "Cream"
        }
    }

    static _EscapeCsv(rawVal, guardFormula := true) {
        s := StrReplace(String(rawVal), "`r`n", " ")
        s := StrReplace(s, "`n", " ")
        s := StrReplace(s, "`r", " ")
        if (guardFormula && RegExMatch(s, "^[=+\-@\t]"))
            s := "'" s
        if (InStr(s, '"') || InStr(s, ",") || InStr(s, "`n") || InStr(s, "`r")) {
            s := StrReplace(s, '"', '""')
            return '"' s '"'
        }
        return s
    }

    static _EscapeMd(rawVal) {
        s := StrReplace(String(rawVal), "`r`n", " ")
        s := StrReplace(s, "`n", " ")
        s := StrReplace(s, "|", "\|")
        return Trim(s)
    }

    static _EscapeJson(rawVal) {
        s := String(rawVal)
        s := StrReplace(s, "\", "\\")
        s := StrReplace(s, '"', '\"')
        s := StrReplace(s, "`r", "\r")
        s := StrReplace(s, "`n", "\n")
        s := StrReplace(s, "`t", "\t")
        s := StrReplace(s, "`b", "\b")
        s := StrReplace(s, "`f", "\f")
        return s
    }

    static _UnescapeJson(str) {
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

    static _ExtractJsonStr(line, key, def := "") {
        if (RegExMatch(line, '"' key '"\s*:\s*"((?:[^"\\]|\\.)*)"', &m))
            return this._UnescapeJson(m[1])
        return def
    }

    static _ExtractJsonInt(line, key, def := 0) {
        if (RegExMatch(line, '"' key '"\s*:\s*(-?\d+)', &m)) {
            try return Integer(m[1])
        }
        return def
    }

    static _ExtractJsonBool(line, key, def := false) {
        if (RegExMatch(line, '"' key '"\s*:\s*(true|false)', &m))
            return (m[1] = "true")
        return def
    }

    static _SerializeEntryJson(entry) {
        return '{"seq":' entry.seq
            . ',"utcStr":"' this._EscapeJson(entry.utcStr) '"'
            . ',"localStr":"' this._EscapeJson(entry.localStr) '"'
            . ',"offsetSec":' entry.offsetSec
            . ',"timecode":"' this._EscapeJson(entry.timecode) '"'
            . ',"ytTimestamp":"' this._EscapeJson(entry.ytTimestamp) '"'
            . ',"recActive":' (entry.recActive ? "true" : "false")
            . ',"color":"' this._EscapeJson(entry.color) '"'
            . ',"category":"' this._EscapeJson(entry.category) '"'
            . ',"summary":"' this._EscapeJson(entry.summary) '"'
            . ',"details":"' this._EscapeJson(entry.details) '"}'
    }

    static _AppendAutosave(entry) {
        if (!this.EnableAutosave || Trim(String(this.AutosaveFile)) = "")
            return false
        try {
            SplitPath(this.AutosaveFile, , &parentDir)
            if (parentDir != "" && !DirExist(parentDir))
                DirCreate(parentDir)
            FileAppend(this._SerializeEntryJson(entry) "`n", this.AutosaveFile, "UTF-8")
            return true
        } catch {
            return false
        }
    }

    static RecoverFromAutosave(filePath := "") {
        target := (Trim(String(filePath)) != "") ? Trim(String(filePath)) : this.AutosaveFile
        if (target = "" || !FileExist(target))
            return 0
        try raw := FileRead(target, "UTF-8")
        catch
            return 0
        if (Trim(raw) = "")
            return 0
        this._EnsureInit()
        recovered := 0
        for _, rawLine in StrSplit(raw, "`n", "`r") {
            line := Trim(rawLine)
            if (line = "" || SubStr(line, 1, 1) != "{" || SubStr(line, -1) != "}")
                continue
            sumTxt := SubStr(Trim(this._ExtractJsonStr(line, "summary", "")), 1, 160)
            if (sumTxt = "")
                continue
            cat := Trim(this._ExtractJsonStr(line, "category", "System"))
            if (cat = "")
                cat := "System"
            offSec := Max(0, this._ExtractJsonInt(line, "offsetSec", 0))
            seqVal := this._ExtractJsonInt(line, "seq", this._NextSeq)
            tc := this._ExtractJsonStr(line, "timecode", "")
            if (tc = "")
                tc := this.FormatHms(offSec)
            yt := this._ExtractJsonStr(line, "ytTimestamp", "")
            if (yt = "")
                yt := this.FormatYouTubeTimestamp(offSec)
            clr := this._ExtractJsonStr(line, "color", "")
            if (clr = "")
                clr := this._CategoryToMarkerColor(cat)
            utcStr := this._ExtractJsonStr(line, "utcStr", FormatTime(A_NowUTC, "yyyy-MM-dd HH:mm:ss") " UTC")
            locStr := this._ExtractJsonStr(line, "localStr", FormatTime(, "HH:mm:ss"))
            detTxt := SubStr(Trim(this._ExtractJsonStr(line, "details", "")), 1, 240)
            recAct := this._ExtractJsonBool(line, "recActive", false)
            entry := {
                seq: seqVal,
                utcStr: utcStr,
                localStr: locStr,
                offsetSec: offSec,
                timecode: tc,
                ytTimestamp: yt,
                recActive: recAct,
                color: clr,
                category: cat,
                summary: sumTxt,
                details: detTxt
            }
            this.Entries.Push(entry)
            if (seqVal >= this._NextSeq)
                this._NextSeq := seqVal + 1
            recovered += 1
        }
        while (this.Entries.Length > this.MAX_ENTRIES)
            this.Entries.RemoveAt(1)
        return recovered
    }

    static ClearAutosave(filePath := "") {
        target := (Trim(String(filePath)) != "") ? Trim(String(filePath)) : this.AutosaveFile
        if (target = "")
            return false
        if (FileExist(target)) {
            try FileDelete(target)
            catch
                return false
        }
        return !FileExist(target)
    }

    static _ComputeOffsetSec(state := "", offsetSecOverride := -1) {
        this._EnsureInit()
        if (IsInteger(offsetSecOverride) && Integer(offsetSecOverride) >= 0)
            return Integer(offsetSecOverride)
        if (IsObject(state) && state.HasOwnProp("recState") && (state.recState == 1 || state.recState == 2) && state.HasOwnProp("recElapsedSec"))
            return Max(0, Integer(state.recElapsedSec))
        try {
            diff := Integer(DateDiff(A_NowUTC, this.SessionStartUtc, "Seconds"))
            return Max(0, diff)
        } catch {
            return 0
        }
    }

    static Record(category, summary, state := "", details := "", offsetSecOverride := -1, utcOverride := "") {
        this._EnsureInit()
        cat := Trim(String(category))
        if (cat = "")
            cat := "System"
        sumTxt := SubStr(Trim(String(summary)), 1, 160)
        if (sumTxt = "")
            return ""
        detTxt := SubStr(Trim(String(details)), 1, 240)
        offSec := this._ComputeOffsetSec(state, offsetSecOverride)
        recAct := (IsObject(state) && state.HasOwnProp("recState") && (state.recState == 1 || state.recState == 2))
        utcStr := (Trim(String(utcOverride)) != "") ? Trim(String(utcOverride)) : FormatTime(A_NowUTC, "yyyy-MM-dd HH:mm:ss") " UTC"
        locStr := FormatTime(, "HH:mm:ss")

        entry := {
            seq: this._NextSeq,
            utcStr: utcStr,
            localStr: locStr,
            offsetSec: offSec,
            timecode: this.FormatHms(offSec),
            ytTimestamp: this.FormatYouTubeTimestamp(offSec),
            recActive: recAct,
            color: this._CategoryToMarkerColor(cat),
            category: cat,
            summary: sumTxt,
            details: detTxt
        }
        this._NextSeq += 1
        this.Entries.Push(entry)
        while (this.Entries.Length > this.MAX_ENTRIES)
            this.Entries.RemoveAt(1)
        this._AppendAutosave(entry)
        return entry
    }

    static GetEntries(categoryFilter := "All") {
        f := StrLower(Trim(String(categoryFilter)))
        out := []
        for _, item in this.Entries {
            if (f = "" || f = "all" || StrLower(item.category) = f)
                out.Push(item)
        }
        return out
    }

    static ExportChapterCsv(categoryFilter := "All") {
        rows := this.GetEntries(categoryFilter)
        csv := "Timecode,Seconds,Color,Category,Marker Name,Notes`r`n"
        for _, e in rows {
            csv .= this._EscapeCsv(e.timecode, false) ","
                . e.offsetSec ","
                . this._EscapeCsv(e.color, false) ","
                . this._EscapeCsv(e.category, true) ","
                . this._EscapeCsv(e.summary, true) ","
                . this._EscapeCsv(e.details, true) "`r`n"
        }
        return csv
    }

    static ExportYouTubeChapters(categoryFilter := "All") {
        rows := this.GetEntries(categoryFilter)
        if (rows.Length = 0)
            return "00:00 Session Start"
        out := ""
        seenTs := Map()
        for _, e in rows {
            if (e.category = "Mic" || e.category = "Alert")
                continue
            ts := e.ytTimestamp
            if (!seenTs.Has(ts)) {
                seenTs[ts] := true
                out .= ts " " e.summary "`r`n"
            }
        }
        if (out = "") {
            for _, e in rows {
                ts := e.ytTimestamp
                if (!seenTs.Has(ts)) {
                    seenTs[ts] := true
                    out .= ts " " e.summary "`r`n"
                }
            }
        }
        if (out != "" && !seenTs.Has("00:00"))
            out := "00:00 Session Start`r`n" . out
        return RTrim(out, "`r`n")
    }

    static ExportMarkdownSummary(title := "PresenterSync Session Timeline Summary", categoryFilter := "All") {
        rows := this.GetEntries(categoryFilter)
        ver := IsSet(UIConstants) ? UIConstants.APP_VERSION : "7.0.0"
        md := "# " title "`r`n`r`n"
            . "- **App Version:** PresenterSync v" ver "`r`n"
            . "- **Exported (UTC):** " FormatTime(A_NowUTC, "yyyy-MM-dd HH:mm:ss") " UTC`r`n"
            . "- **Filter:** " categoryFilter " (" rows.Length " / " this.Entries.Length " logged events; cap " this.MAX_ENTRIES ")`r`n`r`n"
            . "## Video Chapters (YouTube / Timeline)`r`n`r`n"
            . "``````text`r`n"
            . this.ExportYouTubeChapters(categoryFilter) "`r`n"
            . "```````r`n`r`n"
            . "## Activity Log`r`n`r`n"
            . "| Timecode | UTC | Category | Event | Details |`r`n"
            . "| :--- | :--- | :--- | :--- | :--- |`r`n"
        for _, e in rows {
            md .= "| " e.timecode " | " e.utcStr " | " this._EscapeMd(e.category) " | " this._EscapeMd(e.summary) " | " this._EscapeMd(e.details != "" ? e.details : "-") " |`r`n"
        }
        return md
    }

    static SaveExportToFile(filePath, formatKind := "csv", categoryFilter := "All") {
        cleanPath := Trim(String(filePath))
        if (cleanPath = "")
            return false
        fmt := StrLower(Trim(String(formatKind)))
        content := (fmt = "md" || fmt = "markdown")
            ? this.ExportMarkdownSummary("PresenterSync Session Timeline Summary", categoryFilter)
            : this.ExportChapterCsv(categoryFilter)
        try {
            SplitPath(cleanPath, , &parentDir)
            if (parentDir != "" && !DirExist(parentDir))
                DirCreate(parentDir)
            if FileExist(cleanPath)
                FileDelete(cleanPath)
            FileAppend(content, cleanPath, "UTF-8")
            return FileExist(cleanPath) != ""
        } catch {
            return false
        }
    }

    static ShowTimelineWindow(cfg := "", state := "", *) {
        existing := Theme.FocusExistingWindow("PresenterSync - Session Timeline & Chapters")
        if IsObject(existing)
            return existing
        Theme.AcquireSuspend()

        tlGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "PresenterSync - Session Timeline & Chapters")
        tlGui._closed := false
        tlGui.MarginX := 16
        tlGui.MarginY := 14
        Theme.ApplyToWindow(tlGui)
        Theme.NamedWindows["PresenterSync - Session Timeline & Chapters"] := tlGui

        tlGui.SetFont("s11 w700", Theme.UiFont)
        Theme.RegisterControl(tlGui, tlGui.Add("Text", "xm w660", "Session Activity Timeline & Video Editor Chapter Exporter"), "Text")

        tlGui.SetFont("s9 w600", Theme.UiFont)
        Theme.RegisterControl(tlGui, tlGui.Add("Text", "xm y+10 w90", "Category Filter:"), "Text")
        tlGui.SetFont("s9 w400", Theme.UiFont)
        cats := ["All", "Recording", "Scene", "Standby", "Slide", "Mic", "Alert", "Remote", "System"]
        ddlCat := tlGui.Add("DropDownList", "x+8 yp-3 w160 Choose1", cats)
        Theme.RegisterControl(tlGui, ddlCat, "DropDownList")

        lblCount := tlGui.Add("Text", "x+16 yp+3 w380 Right", "")
        Theme.RegisterControl(tlGui, lblCount, "Text", "muted")

        lv := tlGui.Add("ListView", "xm y+10 w660 h300 Grid", ["Timecode", "UTC Timestamp", "Category", "Event", "Details"])
        Theme.RegisterControl(tlGui, lv, "Edit")
        lv.ModifyCol(1, 76)
        lv.ModifyCol(2, 150)
        lv.ModifyCol(3, 82)
        lv.ModifyCol(4, 180)
        lv.ModifyCol(5, 160)

        PopulateList(*) {
            lv.Delete()
            catSel := ddlCat.Text
            rows := SessionTimeline.GetEntries(catSel)
            idx := rows.Length
            while (idx >= 1) {
                e := rows[idx]
                lv.Add(, e.timecode, e.utcStr, e.category, e.summary, e.details)
                idx -= 1
            }
            lblCount.Value := rows.Length " shown (" SessionTimeline.Entries.Length " / " SessionTimeline.MAX_ENTRIES " buffered)"
        }
        PopulateList()
        ddlCat.OnEvent("Change", (*) => PopulateList())

        btnCsv := tlGui.Add("Button", "xm y+12 w158 h30", "Export Chapters (.csv)")
        btnMd := tlGui.Add("Button", "x+8 yp w158 h30", "Export Summary (.md)")
        btnYt := tlGui.Add("Button", "x+8 yp w142 h30", "Copy YouTube")
        btnRef := tlGui.Add("Button", "x+8 yp w88 h30", "Refresh")
        btnClr := tlGui.Add("Button", "x+8 yp w82 h30", "Clear")
        for b in [btnCsv, btnMd, btnYt, btnRef, btnClr]
            Theme.RegisterControl(tlGui, b, "Button")

        ExportDialog(fmtKind, filterLabel, defExt) {
            defName := "PresenterSync_" FormatTime(, "yyyyMMdd_HHmmss") "." defExt
            chosen := FileSelect("S16", A_Desktop "\" defName, "Save PresenterSync " StrUpper(defExt), filterLabel)
            if (chosen = "")
                return
            if (!RegExMatch(chosen, "i)\." defExt "$"))
                chosen .= "." defExt
            if (SessionTimeline.SaveExportToFile(chosen, fmtKind, ddlCat.Text))
                TrayTip("Exported session timeline to " chosen, "PresenterSync Timeline", 1)
        }
        btnCsv.OnEvent("Click", (*) => ExportDialog("csv", "CSV Chapter Markers (*.csv)", "csv"))
        btnMd.OnEvent("Click", (*) => ExportDialog("md", "Markdown Summary (*.md)", "md"))
        btnYt.OnEvent("Click", (*) => (A_Clipboard := SessionTimeline.ExportYouTubeChapters(ddlCat.Text), TrayTip("Copied YouTube chapters to clipboard.", "PresenterSync Timeline", 1)))
        btnRef.OnEvent("Click", (*) => PopulateList())
        btnClr.OnEvent("Click", (*) => (SessionTimeline.Clear(), PopulateList()))

        CloseTimeline(*) {
            if (tlGui._closed)
                return
            tlGui._closed := true
            Theme.UnregisterWindow(tlGui, "PresenterSync - Session Timeline & Chapters")
            Theme.ReleaseSuspend()
            tlGui.Destroy()
        }
        tlGui.OnEvent("Close", CloseTimeline)
        tlGui.OnEvent("Escape", CloseTimeline)
        tlGui.Show("AutoSize")
        return tlGui
    }
}
