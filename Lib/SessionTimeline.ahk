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
        ver := IsSet(UIConstants) ? UIConstants.APP_VERSION : "6.8.0"
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
