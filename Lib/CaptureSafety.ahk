; ==============================================================================
; Module: CaptureSafety.ahk
; Description: Centralized OS-build-aware screen-capture exclusion helper with
;              WDA_MONITOR fallback for legacy Windows 10 builds and diagnostic
;              error logging.
; ==============================================================================

class CaptureSafety {
    static WDA_NONE := 0x00000000
    static WDA_MONITOR := 0x00000001
    static WDA_EXCLUDEFROMCAPTURE := 0x00000011
    static MIN_EXCLUSION_BUILD := 19041

    static LastFailureCount := 0
    static LastErrorCode := 0
    static LastMode := ""
    static ProtectedWindows := Map()
    static _MicroToastGui := ""
    static _MicroToastTimerFn := ""

    static GetOsBuildNumber(osVerOverride := "") {
        verStr := (osVerOverride != "") ? String(osVerOverride) : String(A_OSVersion)
        parts := StrSplit(verStr, ".")
        if (parts.Length >= 3) {
            try return Integer(parts[3])
        }
        return 0
    }

    static ResolveDesiredAffinity(exclude := true, osBuildOverride := "") {
        if (!exclude)
            return this.WDA_NONE
        build := (osBuildOverride != "" && IsInteger(osBuildOverride)) ? Integer(osBuildOverride) : this.GetOsBuildNumber()
        return (build >= this.MIN_EXCLUSION_BUILD) ? this.WDA_EXCLUDEFROMCAPTURE : this.WDA_MONITOR
    }

    static ProtectWindow(hwnd, exclude := true, osBuildOverride := "") {
        if (!hwnd)
            return false
        desired := this.ResolveDesiredAffinity(exclude, osBuildOverride)
        applied := desired
        ok := false
        try ok := !!DllCall("user32\SetWindowDisplayAffinity", "Ptr", hwnd, "UInt", desired, "Int")
        catch
            ok := false

        if (!ok && exclude && desired == this.WDA_EXCLUDEFROMCAPTURE) {
            try ok := !!DllCall("user32\SetWindowDisplayAffinity", "Ptr", hwnd, "UInt", this.WDA_MONITOR, "Int")
            catch
                ok := false
            if (ok)
                applied := this.WDA_MONITOR
        }

        if (!ok) {
            this.LastFailureCount += 1
            this.LastErrorCode := A_LastError
            this.LastMode := "failed"
            if (IsSet(DiagnosticLogger)) {
                try DiagnosticLogger.RecordBreadcrumb("CaptureSafety", "AffinityFailed", Format("hwnd={} desired=0x{:X} err={}", hwnd, desired, this.LastErrorCode))
            }
            return false
        }

        this.LastMode := (!exclude ? "none" : (applied == this.WDA_EXCLUDEFROMCAPTURE ? "exclude" : "monitor_fallback"))
        if (exclude)
            this.ProtectedWindows[hwnd] := { exclude: true, applied: applied, tick: A_TickCount }
        else if (this.ProtectedWindows.Has(hwnd))
            this.ProtectedWindows.Delete(hwnd)
        return true
    }

    static VerifyHudProtection(hwnds, expectedExclude := true, osBuildOverride := "") {
        expected := this.ResolveDesiredAffinity(expectedExclude, osBuildOverride)
        total := 0, okCount := 0, mismatchedCount := 0, failedCount := 0
        details := []
        for _, hwnd in hwnds {
            if (!hwnd)
                continue
            total += 1
            res := this.GetWindowAffinity(hwnd)
            if (!res.ok) {
                failedCount += 1
                details.Push({ hwnd: hwnd, ok: false, affinity: 0, expected: expected })
            } else if (expectedExclude && (res.affinity == this.WDA_EXCLUDEFROMCAPTURE || res.affinity == this.WDA_MONITOR)) {
                okCount += 1
                details.Push({ hwnd: hwnd, ok: true, affinity: res.affinity, expected: expected })
            } else if (!expectedExclude && res.affinity == this.WDA_NONE) {
                okCount += 1
                details.Push({ hwnd: hwnd, ok: true, affinity: res.affinity, expected: expected })
            } else {
                mismatchedCount += 1
                details.Push({ hwnd: hwnd, ok: false, affinity: res.affinity, expected: expected })
            }
        }
        return { total: total, okCount: okCount, mismatchedCount: mismatchedCount, failedCount: failedCount, details: details }
    }

    static GetMonitorWorkAreas() {
        mons := []
        cnt := 0
        try cnt := MonitorGetCount()
        if (cnt <= 0)
            return [{ left: 0, top: 0, right: A_ScreenWidth, bottom: A_ScreenHeight }]
        Loop cnt {
            mL := 0, mT := 0, mR := 0, mB := 0
            try {
                MonitorGetWorkArea(A_Index, &mL, &mT, &mR, &mB)
                if (mR > mL && mB > mT)
                    mons.Push({ left: mL, top: mT, right: mR, bottom: mB })
            }
        }
        if (mons.Length == 0)
            mons.Push({ left: 0, top: 0, right: A_ScreenWidth, bottom: A_ScreenHeight })
        return mons
    }

    static IsRectOnAnyMonitor(x, y, w, h, monitors := "", minOverlapPx := 16) {
        mons := IsObject(monitors) ? monitors : this.GetMonitorWorkAreas()
        for _, m in mons {
            ox := Min(x + w, m.right) - Max(x, m.left)
            oy := Min(y + h, m.bottom) - Max(y, m.top)
            if (ox >= minOverlapPx && oy >= minOverlapPx)
                return true
        }
        return false
    }

    ; Preserves any rect already visible on ANY connected monitor (including extended Monitor 2),
    ; clamping only when completely off-screen (e.g. L-shaped dead corner or unplugged display).
    static ClampRectToMonitors(x, y, w, h, monitors := "") {
        mons := IsObject(monitors) ? monitors : this.GetMonitorWorkAreas()
        if (this.IsRectOnAnyMonitor(x, y, w, h, mons))
            return { x: x, y: y, clamped: false }

        bestMon := mons[1]
        bestDist := 1e15
        cx := x + (w / 2.0)
        cy := y + (h / 2.0)
        for _, m in mons {
            mcx := (m.left + m.right) / 2.0
            mcy := (m.top + m.bottom) / 2.0
            d := ((cx - mcx) ** 2) + ((cy - mcy) ** 2)
            if (d < bestDist) {
                bestDist := d
                bestMon := m
            }
        }
        nx := Max(bestMon.left, Min(x, bestMon.right - w))
        ny := Max(bestMon.top, Min(y, bestMon.bottom - h))
        return { x: nx, y: ny, clamped: true }
    }

    static GetWindowAffinity(hwnd) {
        if (!hwnd)
            return { ok: false, affinity: 0 }
        aff := 0
        ok := false
        try ok := !!DllCall("user32\GetWindowDisplayAffinity", "Ptr", hwnd, "UInt*", &aff, "Int")
        catch
            ok := false
        return { ok: ok, affinity: aff }
    }

    static GetStatusSummary(osBuildOverride := "") {
        build := (osBuildOverride != "" && IsInteger(osBuildOverride)) ? Integer(osBuildOverride) : this.GetOsBuildNumber()
        return {
            supported: (build >= this.MIN_EXCLUSION_BUILD),
            osBuild: build,
            mode: this.LastMode,
            failureCount: this.LastFailureCount,
            lastError: this.LastErrorCode
        }
    }

    static GetCaptureSafetyBannerText(exclude := true, osBuildOverride := "") {
        build := (osBuildOverride != "" && IsInteger(osBuildOverride)) ? Integer(osBuildOverride) : this.GetOsBuildNumber()
        if (!exclude)
            return "Visible in Screen Share (ExcludeFromCapture OFF)"
        if (build >= this.MIN_EXCLUSION_BUILD)
            return "Capture-Safe (Win10 " build "+ WDA_EXCLUDEFROMCAPTURE) | Tip: NDI / Game Capture hooks may still capture layered windows"
        return "Legacy Monitor Blackout (WDA_MONITOR — Win10 build " build " < 19041)"
    }

    static HideMicroToast(*) {
        if (IsObject(this._MicroToastTimerFn)) {
            try SetTimer(this._MicroToastTimerFn, 0)
        }
        if (IsObject(this._MicroToastGui)) {
            try this._MicroToastGui.Hide()
        }
    }

    static ShowMicroToast(text, durationMs := 1800, anchorHwnd := 0, exclude := true) {
        txt := Trim(String(text))
        if (txt = "") {
            this.HideMicroToast()
            return false
        }
        try {
            if (IsSet(Gdip))
                Gdip.Startup()
            if (!IsObject(this._MicroToastGui)) {
                this._MicroToastGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000 +E0x00000020 -DPIScale", "PresenterSync MicroToast")
            }
            this.ProtectWindow(this._MicroToastGui.Hwnd, exclude)

            w := 240, h := 34
            if (IsSet(Gdip)) {
                measured := Gdip.MeasureTextWidthFloat(txt, "Segoe UI", 9.5, 1)
                w := Max(110, Min(560, Round(measured) + 28))
            } else {
                w := Max(110, Min(560, StrLen(txt) * 8 + 28))
            }

            mx := 0, my := 0
            if (anchorHwnd) {
                try {
                    WinGetPos(&ax, &ay, &aw, &ah, "ahk_id " anchorHwnd)
                    mx := ax + Round((aw - w) / 2)
                    my := ay - h - 8
                }
            }
            if (mx == 0 && my == 0) {
                try {
                    CoordMode("Mouse", "Screen")
                    MouseGetPos(&curX, &curY)
                    mx := curX + 14
                    my := curY - h - 14
                } catch {
                    mx := 40, my := 40
                }
            }
            clamped := this.ClampRectToMonitors(mx, my, w, h)
            x := clamped.x, y := clamped.y

            if (IsSet(Gdip)) {
                labelCfg := { text: txt, size: 9.5, bold: true, align: 1, color: 0xFFF8FAFC, x: 10, y: 0, w: w - 20, h: h }
                Gdip.RenderPill(this._MicroToastGui.Hwnd, x, y, w, h, 0xEE1E293B, 0xFF64748B, 240, 10, "", labelCfg)
            }
            this._MicroToastGui.Show(Format("NoActivate x{} y{} w{} h{}", x, y, w, h))

            if (!IsObject(this._MicroToastTimerFn))
                this._MicroToastTimerFn := ObjBindMethod(CaptureSafety, "HideMicroToast")
            try SetTimer(this._MicroToastTimerFn, 0)
            if (durationMs > 0)
                SetTimer(this._MicroToastTimerFn, -Integer(durationMs))
            return true
        } catch {
            return false
        }
    }
}

ProtectWindowFromCapture(hwnd, exclude := true, osBuildOverride := "") => CaptureSafety.ProtectWindow(hwnd, exclude, osBuildOverride)
ShowCaptureSafeMicroToast(text, durationMs := 1800, anchorHwnd := 0, exclude := true) => CaptureSafety.ShowMicroToast(text, durationMs, anchorHwnd, exclude)
HideCaptureSafeMicroToast(*) => CaptureSafety.HideMicroToast()
