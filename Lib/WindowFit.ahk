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
    static _pendingAnchors := Map()
    static _autoEnabled := Map()
    static _hooked := false
    static MaxFraction := 0.90

    static _GetDpiScale(hwnd := 0) {
        dpi := 0
        if (hwnd)
            try dpi := DllCall("user32\GetDpiForWindow", "ptr", hwnd, "uint")
        return (dpi > 0 ? dpi : A_ScreenDPI) / 96.0
    }

    static _PruneClosedStates() {
        dead := []
        for hwnd, _ in WindowFit._states {
            if (!WinExist("ahk_id " hwnd))
                dead.Push(hwnd)
        }
        for hwnd in dead {
            try WindowFit._states.Delete(hwnd)
            try WindowFit._pendingAnchors.Delete(hwnd)
            try WindowFit._autoEnabled.Delete(hwnd)
        }
    }

    static RegisterAnchor(g, ctrl, spec) {
        if (!IsObject(g) || !IsObject(ctrl) || !ctrl.Hwnd)
            return
        hwnd := g.Hwnd
        if (!WindowFit._pendingAnchors.Has(hwnd))
            WindowFit._pendingAnchors[hwnd] := Map()
        WindowFit._pendingAnchors[hwnd][ctrl.Hwnd] := WindowFit._NormalizeSpec(spec)
    }

    static EnableAutoResponsive(g, opts := "") {
        if (!IsObject(g) || !g.Hwnd)
            return
        WindowFit._autoEnabled[g.Hwnd] := opts
    }

    static _NormalizeSpec(spec) {
        if (IsObject(spec) && spec.HasOwnProp("_isNormSpec"))
            return spec
        getNum(k) {
            if (spec is Map)
                return spec.Has(k) ? Float(spec[k]) : 0.0
            if (IsObject(spec) && spec.HasOwnProp(k))
                return Float(spec.%k%)
            return 0.0
        }
        hasKey(k) {
            if (spec is Map)
                return spec.Has(k)
            return IsObject(spec) && spec.HasOwnProp(k)
        }
        return {
            _isNormSpec: true,
            L: getNum("L"),
            R: getNum("R"),
            W: getNum("W"),
            CX: getNum("CX"),
            hasFX: hasKey("FX"),
            FX: getNum("FX"),
            hasFW: hasKey("FW"),
            FW: getNum("FW"),
            T: getNum("T"),
            B: getNum("B"),
            H: getNum("H"),
            CY: getNum("CY")
        }
    }

    static ComputeAnchoredRect(base, designW, designH, effW, effH, spec) {
        s := WindowFit._NormalizeSpec(spec)
        dw := Float(effW - designW)
        dh := Float(effH - designH)
        if (s.hasFX || s.hasFW) {
            nx := base.x + Round((s.hasFX ? s.FX : 0.0) * dw)
            nw := Max(20, base.w + Round((s.hasFW ? s.FW : 0.0) * dw))
        } else {
            nx := base.x + Round(s.R * dw + s.CX * (dw / 2.0))
            nw := Max(20, base.w + Round(s.W * dw))
        }
        ny := base.y + Round(s.B * dh + s.CY * (dh / 2.0))
        nh := Max(16, base.h + Round(s.H * dh))
        return {x: nx, y: ny, w: nw, h: nh}
    }

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
        WindowFit._PruneClosedStates()
        wantCenter := InStr(opts, "Center") != 0
        wantResp := !InStr(opts, "NoResponsive")
        if (wantResp && !WindowFit._autoEnabled.Has(g.Hwnd))
            WindowFit._autoEnabled[g.Hwnd] := opts
        try g.Opt("+Resize +0x02000000") ; +Resize + WS_CLIPCHILDREN
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
        designW := Max(1, cw)
        designH := Max(1, ch)
        wa := WindowFit.GetActiveWorkArea()
        workW := wa.r - wa.l
        workH := wa.b - wa.t
        chromeW := w - cw
        chromeH := h - ch
        contentH := WindowFit._ContentBottom(g, g.Hwnd)
        fit := WindowFit.ClampOuterSize(w, h, workW, workH, WindowFit.MaxFraction)
        nw := fit.w
        nh := fit.h
        if (fit.clamped)
            try g.Move(, , nw, nh)
        try g.Opt("+MinSize" Min(nw, 360) "x" Min(nh, 240))
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
        respItems := wantResp ? WindowFit._BuildResponsiveItems(g, designW, designH) : []
        WindowFit._states[hwnd] := {
            contentH: contentH,
            pos: 0,
            chromeH: chromeH,
            g: g,
            designW: designW,
            designH: designH,
            responsive: wantResp,
            items: respItems
        }
        WindowFit._EnsureHooks()
        if (firstTime) {
            try g.OnEvent("Size", WindowFit._OnSize.Bind(WindowFit))
            try g.OnEvent("Close", WindowFit._OnCloseCleanup.Bind(WindowFit))
            WindowFit._WireFocusScroll(g)
        }
        if (wantResp && respItems.Length > 0)
            WindowFit.ApplyResponsiveLayout(hwnd)
        WindowFit._Refresh(hwnd)
        try g.Show()
    }

    static _OnCloseCleanup(g, *) {
        try hwnd := g.Hwnd
        catch
            return 0
        try WindowFit._states.Delete(hwnd)
        try WindowFit._pendingAnchors.Delete(hwnd)
        try WindowFit._autoEnabled.Delete(hwnd)
        return 0
    }

    static _ContentBottom(g, hwnd := 0) {
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
        scale := WindowFit._GetDpiScale(hwnd ? hwnd : (IsObject(g) ? g.Hwnd : 0))
        margin := (g.MarginY > 0 ? g.MarginY : 8)
        return Round((bottom + margin) * scale)
    }

    static _BuildResponsiveItems(g, designW, designH) {
        hwnd := g.Hwnd
        explicit := WindowFit._pendingAnchors.Has(hwnd) ? WindowFit._pendingAnchors[hwnd] : Map()
        rawList := []
        try {
            for ctrl in g {
                if (!ctrl.Hwnd)
                    continue
                parentHwnd := 0
                try parentHwnd := DllCall("GetParent", "ptr", ctrl.Hwnd, "ptr")
                if (parentHwnd && parentHwnd != hwnd)
                    continue
                cx := 0, cy := 0, cw := 0, ch := 0
                try ctrl.GetPos(&cx, &cy, &cw, &ch)
                if (cw <= 0 || ch <= 0)
                    continue
                rawList.Push({
                    ctrl: ctrl,
                    hwnd: ctrl.Hwnd,
                    type: ctrl.Type,
                    base: {x: cx, y: cy, w: cw, h: ch}
                })
            }
        }

        ; Detect multi-button horizontal grid rows (2..6 buttons sharing the same Y band)
        rowSpecs := Map()
        btnRows := []
        for item in rawList {
            if (item.type != "Button" || explicit.Has(item.hwnd))
                continue
            placed := false
            for grp in btnRows {
                if (Abs(grp.y - item.base.y) <= 8) {
                    grp.items.Push(item)
                    placed := true
                    break
                }
            }
            if (!placed)
                btnRows.Push({y: item.base.y, items: [item]})
        }
        for grp in btnRows {
            cnt := grp.items.Length
            if (cnt >= 2 && cnt <= 6) {
                minX := 999999, maxR := -999999
                for bi in grp.items {
                    if (bi.base.x < minX)
                        minX := bi.base.x
                    if (bi.base.x + bi.base.w > maxR)
                        maxR := bi.base.x + bi.base.w
                }
                spanW := maxR - minX
                if (spanW >= designW * 0.55) {
                    ; Sort left-to-right to assign clean equal FX/FW columns
                    sorted := []
                    for bi in grp.items
                        sorted.Push(bi)
                    n := sorted.Length
                    Loop n {
                        i := A_Index
                        j := i + 1
                        while (j <= n) {
                            if (sorted[j].base.x < sorted[i].base.x) {
                                tmp := sorted[i], sorted[i] := sorted[j], sorted[j] := tmp
                            }
                            j++
                        }
                    }
                    isFoot := (designH >= 96 && grp.y >= designH * 0.55 && grp.y >= designH - 58)
                    for idx, bi in sorted {
                        rowSpecs[bi.hwnd] := {
                            FX: (idx - 1) / Float(n),
                            FW: 1.0 / Float(n),
                            B: isFoot ? 1.0 : 0.0
                        }
                    }
                }
            }
        }

        ; Identify rows containing a stretching left field so right-edge companion buttons stay pinned right
        items := []
        for item in rawList {
            spec := ""
            if (explicit.Has(item.hwnd)) {
                spec := explicit[item.hwnd]
            } else if (rowSpecs.Has(item.hwnd)) {
                spec := rowSpecs[item.hwnd]
            } else {
                spec := WindowFit._InferAnchor(item, rawList, designW, designH)
            }
            items.Push({
                ctrl: item.ctrl,
                hwnd: item.hwnd,
                type: item.type,
                base: item.base,
                spec: WindowFit._NormalizeSpec(spec),
                lastW: -1
            })
        }
        return items
    }

    static _InferAnchor(item, allItems, designW, designH) {
        bx := item.base.x, by := item.base.y, bw := item.base.w, bh := item.base.h
        t := item.type
        isFoot := (designH >= 96 && by >= designH * 0.55 && by >= designH - 58)

        if (t = "Tab" || t = "Tab2" || t = "Tab3")
            return {W: 1, H: 1}
        if (t = "ListView" || t = "TreeView" || t = "ListBox") {
            if (bw >= designW * 0.45 && bh >= 90)
                return {W: 1, H: 1}
            if (bw >= designW * 0.45)
                return {W: 1}
            if (bh >= 100)
                return {H: 1}
            return {}
        }
        if (t = "Edit") {
            style := 0
            try style := DllCall("GetWindowLongPtr", "ptr", item.hwnd, "int", -16, "ptr")
            isMulti := (style & 0x4) != 0
            if (isMulti && bw >= designW * 0.50 && bh >= 90)
                return {W: 1, H: 1}
            if (bw >= designW * 0.42)
                return {W: 1, B: isFoot ? 1 : 0}
            return isFoot ? {B: 1} : {}
        }
        if (t = "DDL" || t = "DropDownList" || t = "ComboBox" || t = "Slider" || t = "Progress" || t = "Hotkey") {
            if (bw >= designW * 0.45)
                return {W: 1, B: isFoot ? 1 : 0}
            return isFoot ? {B: 1} : {}
        }
        if (t = "GroupBox") {
            if (bw >= designW * 0.55)
                return {W: 1}
            return {}
        }
        if (t = "Pic") {
            if (bw >= designW * 0.65)
                return {CX: 1}
            return {}
        }
        if (t = "Text" || t = "CheckBox") {
            if (bw >= designW * 0.55)
                return {W: 1, B: isFoot ? 1 : 0}
            if (bx >= designW * 0.65 && bx + bw >= designW - 36)
                return {R: 1, B: isFoot ? 1 : 0}
            return isFoot ? {B: 1} : {}
        }
        if (t = "Button") {
            if (bw >= designW * 0.60)
                return {W: 1, B: isFoot ? 1 : 0}
            if (isFoot) {
                if (bx + bw >= designW - 44 && bx >= designW * 0.40)
                    return {R: 1, B: 1}
                return {B: 1}
            }
            if (bx >= designW * 0.55 && bx + bw >= designW - 48) {
                ; Check if another control on same Y band stretches left of this button
                for sib in allItems {
                    if (sib.hwnd != item.hwnd && Abs(sib.base.y - by) <= 10 && sib.base.x + sib.base.w <= bx + 4 && sib.base.w >= designW * 0.28)
                        return {R: 1}
                }
            }
        }
        return {}
    }

    static ApplyResponsiveLayout(hwnd) {
        if (!WindowFit._states.Has(hwnd))
            return false
        st := WindowFit._states[hwnd]
        if (!st.responsive || !IsObject(st.items) || st.items.Length == 0)
            return false
        rc := Buffer(16, 0)
        if (!DllCall("GetClientRect", "ptr", hwnd, "ptr", rc))
            return false
        curW_px := NumGet(rc, 8, "int")
        curH_px := NumGet(rc, 12, "int")
        if (curW_px <= 0 || curH_px <= 0)
            return false
        dpiScale := WindowFit._GetDpiScale(hwnd)
        effW := Max(curW_px / dpiScale, Float(st.designW))
        effH := Max(curH_px / dpiScale, Float(st.designH))

        hdwp := DllCall("user32\BeginDeferWindowPos", "int", st.items.Length, "ptr")
        tabsToResize := []
        maxBottomDip := 0
        for item in st.items {
            r := WindowFit.ComputeAnchoredRect(item.base, st.designW, st.designH, effW, effH, item.spec)
            if (r.y + r.h > maxBottomDip)
                maxBottomDip := r.y + r.h
            px := Round(r.x * dpiScale)
            py := Round(r.y * dpiScale) - st.pos
            pw := Max(8, Round(r.w * dpiScale))
            ph := Max(8, Round(r.h * dpiScale))
            if (hdwp) {
                nextDwp := DllCall("user32\DeferWindowPos", "ptr", hdwp, "ptr", item.ctrl.Hwnd, "ptr", 0, "int", px, "int", py, "int", pw, "int", ph, "uint", 0x0014, "ptr")
                if (nextDwp)
                    hdwp := nextDwp
            } else {
                DllCall("user32\SetWindowPos", "ptr", item.ctrl.Hwnd, "ptr", 0, "int", px, "int", py, "int", pw, "int", ph, "uint", 0x0014)
            }
            if ((item.type = "Tab" || item.type = "Tab2" || item.type = "Tab3") && pw != item.lastW)
                tabsToResize.Push(item.ctrl)
            item.lastW := pw
        }
        if (hdwp)
            DllCall("user32\EndDeferWindowPos", "ptr", hdwp)

        for tc in tabsToResize {
            if (IsSet(Theme) && Theme.HasMethod("RecalcTabHeaderSizes"))
                try Theme.RecalcTabHeaderSizes(tc)
        }
        margin := (IsObject(st.g) && st.g.MarginY > 0) ? st.g.MarginY : 8
        st.contentH := Round((maxBottomDip + margin) * dpiScale)
        DllCall("user32\RedrawWindow", "ptr", hwnd, "ptr", 0, "ptr", 0, "uint", 0x0185)
        return true
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
        try hwnd := g.Hwnd
        catch
            return
        if (WindowFit._states.Has(hwnd) && WindowFit._states[hwnd].responsive)
            WindowFit.ApplyResponsiveLayout(hwnd)
        WindowFit._Refresh(hwnd)
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
