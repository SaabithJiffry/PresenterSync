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
        return true
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
}

ProtectWindowFromCapture(hwnd, exclude := true, osBuildOverride := "") => CaptureSafety.ProtectWindow(hwnd, exclude, osBuildOverride)
