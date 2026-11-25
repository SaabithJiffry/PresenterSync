#Requires AutoHotkey v2.0
; ============================================================================
; WindowFit.ahk - v9.7 (Live Finding B)
; Work-area-clamped, resizable, auto-scrolling dialog helper.
;
; Usage: replace  dlg.Show(opts)  with  WindowFit.Show(dlg, opts)
;  - Clamps outer size to <= 90% of the active monitor work area (DPI-aware, physical px)
;  - Enables +Resize with a sane MinSize
;  - When content is taller than the viewport, shows a vertical scrollbar and wires
;    WM_VSCROLL / WM_MOUSEWHEEL / keyboard focus-into-view so every control (incl. footer
;    Save / Connect / Close buttons) stays reachable on 768p and 125%-175% DPI laptops.
;  - Keeps the window fully on one monitor (never clips off-screen).
; Does not touch HUD / -Caption windows. Safe no-op on invalid input.
; ============================================================================

class WindowFit {
    static _states := Map()
    static _hooked := false
    static MaxFraction := 0.90

    ; Pure helper (unit-testable): clamp outer size to a fraction of the work area.
    ; Returns {w, h, clamped}
    static ClampOuterSize(outerW, outerH, workW, workH, fraction := 0.90) {
        maxW := Max(320, Floor(workW * fraction))
        maxH := Max(240, Floor(workH * fraction))
        nw := Min(outerW, maxW)
        nh := Min(outerH, maxH)
        return {w: nw, h: nh, clamped: (nw != outerW || nh != outerH)}
    }

    ; Pure helper: keep rect inside work area (top-left clamp). Returns {x, y}
    static ClampPosition(x, y, w, h, wl, wt, wr, wb) {
        nx := Min(x, wr - w)
        ny := Min(y, wb - h)
        nx := Max(nx, wl)
        ny := Max(ny, wt)
        return {x: nx, y: ny}
    }

    ; Pure helper: scroll position clamp.
    static ClampScrollPos(pos, contentH, viewH) {
        maxPos := Max(0, contentH - viewH)
        return Max(0, Min(pos, maxPos))
    }

    static GetActiveWorkArea() {
        try {
            CoordMode("Mouse", "Screen")
            MouseGetPos(&mx, &my)
            count := MonitorGetCount()
            Loop count {
                MonitorGet(A_Index, &l, &t, &r, &b)
                if (mx >= l && mx < r && my >= t && my < b) {
                    MonitorGetWorkArea(A_Index, &wl, &wt, &wr, &wb)
                    return {l: wl, t: wt, r: wr, b: wb}
                }
            }
        }
        try {
            MonitorGetWorkArea(MonitorGetPrimary(), &wl, &wt, &wr, &wb)
            return {l: wl, t: wt, r: wr, b: wb}
        }
        return {l: 0, t: 0, r: A_ScreenWidth, b: A_ScreenHeight - 40}
    }

    static Show(g, opts := "") {
        if (!IsObject(g))
            return
        wantCenter := InStr(opts, "Center") != 0
        try g.Opt("+Resize")
        try g.Show(opts " Hide")
        catch {
            try g.Show(opts)
            return
        }
        try {
            g.GetPos(&x, &y, &w, &h)
            g.GetClientPos(, , &cw, &ch)
        } catch {
            try g.Show()
            return
        }
        wa := WindowFit.GetActiveWorkArea()
        workW := wa.r - wa.l
        workH := wa.b - wa.t
        chromeW := w - cw
        chromeH := h - ch
        contentH := WindowFit._ContentBottom(g)
        fit := WindowFit.ClampOuterSize(w, h, workW, workH, WindowFit.MaxFraction)
        nw := fit.w
        nh := fit.h
        if (fit.clamped)
            try g.Move(, , nw, nh)
        try g.Opt("+MinSize" Min(nw, 360) "x" Min(nh, 240) )
        if (wantCenter || fit.clamped || x < wa.l || y < wa.t || x + nw > wa.r || y + nh > wa.b) {
            if (wantCenter || fit.clamped) {
                nx := wa.l + (workW - nw) // 2
                ny := wa.t + (workH - nh) // 2
            } else {
                nx := x
                ny := y
            }
            pos := WindowFit.ClampPosition(nx, ny, nw, nh, wa.l, wa.t, wa.r, wa.b)
            try g.Move(pos.x, pos.y)
        }
        hwnd := g.Hwnd
        firstTime := !WindowFit._states.Has(hwnd)
        WindowFit._states[hwnd] := {contentH: contentH, pos: 0, chromeH: chromeH, g: g}
        WindowFit._EnsureHooks()
        if (firstTime) {
            try g.OnEvent("Size", WindowFit._OnSize.Bind(WindowFit))
            WindowFit._WireFocusScroll(g)
        }
        WindowFit._Refresh(hwnd)
        try g.Show()
    }

    static _OnCloseCleanup(g, *) {
        try WindowFit._states.Delete(g.Hwnd)
        return 0
    }

    static _ContentBottom(g) {
        bottom := 0
        try {
            for ctrl in g {
                try {
                    ctrl.GetPos(, &cy, , &chh)
                    if (cy + chh > bottom)
                        bottom := cy + chh
                }
            }
        }
        return bottom + Round((g.MarginY > 0 ? g.MarginY : 8) * (A_ScreenDPI / 96))
    }

    static _EnsureHooks() {
        if (WindowFit._hooked)
            return
        WindowFit._hooked := true
        OnMessage(0x0115, WindowFit._OnVScroll.Bind(WindowFit))   ; WM_VSCROLL
        OnMessage(0x020A, WindowFit._OnMouseWheel.Bind(WindowFit)) ; WM_MOUSEWHEEL
    }

    static _OnSize(g, minMax, w, h) {
        if (minMax = -1)
            return
        WindowFit._Refresh(g.Hwnd)
    }

    static _ViewH(hwnd) {
        try {
            rc := Buffer(16, 0)
            DllCall("GetClientRect", "ptr", hwnd, "ptr", rc)
            return NumGet(rc, 12, "int")
        }
        return 0
    }

    static _Refresh(hwnd) {
        if (!WindowFit._states.Has(hwnd))
            return
        st := WindowFit._states[hwnd]
        viewH := WindowFit._ViewH(hwnd)
        needScroll := (viewH > 0 && st.contentH > viewH + 1)
        if (!needScroll) {
            if (st.pos != 0)
                WindowFit._ScrollTo(hwnd, 0)
            WindowFit._SetInfo(hwnd, 0, 0, 0, 0, false)
            return
        }
        newPos := WindowFit.ClampScrollPos(st.pos, st.contentH, viewH)
        if (newPos != st.pos)
            WindowFit._ScrollTo(hwnd, newPos)
        WindowFit._SetInfo(hwnd, 0, st.contentH - 1, viewH, st.pos, true)
    }

    static _SetInfo(hwnd, nMin, nMax, nPage, nPos, enable) {
        si := Buffer(28, 0)
        NumPut("uint", 28, si, 0)
        NumPut("uint", 0x07, si, 4)  ; SIF_RANGE | SIF_PAGE | SIF_POS
        NumPut("int", nMin, si, 8)
        NumPut("int", enable ? nMax : 0, si, 12)
        NumPut("uint", enable ? nPage : 0, si, 16)
        NumPut("int", nPos, si, 20)
        DllCall("SetScrollInfo", "ptr", hwnd, "int", 1, "ptr", si, "int", true)
        if (!enable)
            DllCall("ShowScrollBar", "ptr", hwnd, "int", 1, "int", false)
    }

    static _ScrollTo(hwnd, newPos) {
        if (!WindowFit._states.Has(hwnd))
            return
        st := WindowFit._states[hwnd]
        viewH := WindowFit._ViewH(hwnd)
        newPos := WindowFit.ClampScrollPos(newPos, st.contentH, viewH)
        dy := st.pos - newPos
        if (dy = 0)
            return
        ; SW_SCROLLCHILDREN(1) | SW_INVALIDATE(2) | SW_ERASE(4)
        DllCall("ScrollWindowEx", "ptr", hwnd, "int", 0, "int", dy, "ptr", 0, "ptr", 0, "ptr", 0, "ptr", 0, "uint", 0x7)
        st.pos := newPos
        si := Buffer(28, 0)
        NumPut("uint", 28, si, 0)
        NumPut("uint", 0x04, si, 4)
        NumPut("int", newPos, si, 20)
        DllCall("SetScrollInfo", "ptr", hwnd, "int", 1, "ptr", si, "int", true)
    }

    static _OnVScroll(wParam, lParam, msg, hwnd) {
        if (!WindowFit._states.Has(hwnd) || lParam != 0)
            return
        st := WindowFit._states[hwnd]
        viewH := WindowFit._ViewH(hwnd)
        code := wParam & 0xFFFF
        line := Round(20 * (A_ScreenDPI / 96))
        newPos := st.pos
        switch code {
            case 0: newPos := st.pos - line
            case 1: newPos := st.pos + line
            case 2: newPos := st.pos - viewH
            case 3: newPos := st.pos + viewH
            case 4, 5: newPos := (wParam >> 16) & 0xFFFF
            case 6: newPos := 0
            case 7: newPos := st.contentH
            default: return 0
        }
        if (code = 4 || code = 5) {
            si := Buffer(28, 0)
            NumPut("uint", 28, si, 0)
            NumPut("uint", 0x10, si, 4)
            if (DllCall("GetScrollInfo", "ptr", hwnd, "int", 1, "ptr", si))
                newPos := NumGet(si, 24, "int")
        }
        WindowFit._ScrollTo(hwnd, newPos)
        return 0
    }

    static _OnMouseWheel(wParam, lParam, msg, hwnd) {
        try {
            MouseGetPos(, , &winId, &ctrlHwnd, 2)
        } catch {
            return
        }
        if (!WindowFit._states.Has(winId))
            return
        ; Let native scrollable controls (multiline Edit, ListView, ListBox, TreeView, ComboBox list) handle their own wheel.
        cls := ""
        try cls := WinGetClass("ahk_id " ctrlHwnd)
        if (RegExMatch(cls, "i)^(SysListView32|SysTreeView32|ListBox|ComboLBox)$"))
            return
        if (cls = "Edit" && (DllCall("GetWindowLongPtr", "ptr", ctrlHwnd, "int", -16, "ptr") & 0x4))  ; ES_MULTILINE
            return
        st := WindowFit._states[winId]
        viewH := WindowFit._ViewH(winId)
        if (st.contentH <= viewH + 1)
            return
        delta := (wParam >> 16) & 0xFFFF
        if (delta > 0x7FFF)
            delta -= 0x10000
        step := Round(60 * (A_ScreenDPI / 96))
        WindowFit._ScrollTo(winId, st.pos - (delta > 0 ? step : -step) * Max(1, Abs(delta) // 120))
        return 0
    }

    static _WireFocusScroll(g) {
        try {
            for ctrl in g {
                try ctrl.OnEvent("Focus", WindowFit._OnCtrlFocus.Bind(WindowFit, g))
            }
        }
    }

    static _OnCtrlFocus(wf, g, ctrl, *) {
        try {
            hwnd := g.Hwnd
            if (!WindowFit._states.Has(hwnd))
                return
            st := WindowFit._states[hwnd]
            viewH := WindowFit._ViewH(hwnd)
            if (st.contentH <= viewH + 1)
                return
            ctrl.GetPos(, &cy, , &chh)
            if (cy < 0)
                WindowFit._ScrollTo(hwnd, st.pos + cy - 8)
            else if (cy + chh > viewH)
                WindowFit._ScrollTo(hwnd, st.pos + (cy + chh - viewH) + 8)
        }
    }
}
