; ==============================================================================
; Module: HudArcadeBase.ahk
; Description: Shared GDI+ overlay lifecycle, dual Win32 click-routing surface
;              (click-through + 0x01000000 catch-alpha interactiveMouse mode),
;              audio-safety key reservation, QPC clock, and frosted Win11 UI
;              primitives for all PresenterSync Desktop Arcade overlays.
; ==============================================================================

#Include "%A_LineFile%\..\Gdip.ahk"

class HudArcadeBase {
    static ActiveGameId := ""
    static ActiveGameObj := ""
    static _qpcFreq := 0
    static _mmTimerActive := false
    static _ptWin := Buffer(8, 0)
    static _szWin := Buffer(8, 0)
    static _ptSrc := Buffer(8, 0)
    static _blend := Buffer(4, 0)
    static _bi := Buffer(40, 0)
    static _gpBuf := Buffer(16, 0)
    static _gpDllName := ""
    static _gpDllChecked := false

    static IsAnyGameActive() {
        return (this.ActiveGameId != "") || (IsSet(HudSnake) && HudSnake.IsActive)
    }

    static RegisterActiveGame(gameObj, gameId) {
        this.ActiveGameObj := gameObj
        this.ActiveGameId := String(gameId)
    }

    static ClearActiveGame(gameId := "") {
        if (gameId = "" || this.ActiveGameId = String(gameId)) {
            this.ActiveGameId := ""
            this.ActiveGameObj := ""
        }
    }

    static StopActiveGame() {
        if (IsObject(this.ActiveGameObj)) {
            try this.ActiveGameObj.Stop()
        }
        if (IsSet(HudSnake) && HudSnake.IsActive) {
            try HudSnake.Stop()
        }
        this.ActiveGameId := ""
        this.ActiveGameObj := ""
    }

    static IsReservedAudioKey(cfg, key) {
        k := RegExReplace(Trim(String(key)), "i)\s+up$", "")
        k := RegExReplace(k, "^[~*$]+")
        if (!IsObject(cfg) || k = "")
            return false
        if (cfg.HasOwnProp("HwMuteHotkey") && cfg.HwMuteHotkey != "" && StrLower(cfg.HwMuteHotkey) != "none") {
            if (IsSet(_DoHotkeysCollide) ? _DoHotkeysCollide(k, cfg.HwMuteHotkey) : (StrLower(k) = StrLower(RegExReplace(Trim(cfg.HwMuteHotkey), "^[~*$]+"))))
                return true
        }
        if (cfg.HasOwnProp("HwTransitionHotkey") && cfg.HwTransitionHotkey != "" && StrLower(cfg.HwTransitionHotkey) != "none") {
            if (IsSet(_DoHotkeysCollide) ? _DoHotkeysCollide(k, cfg.HwTransitionHotkey) : (StrLower(k) = StrLower(RegExReplace(Trim(cfg.HwTransitionHotkey), "^[~*$]+"))))
                return true
        }
        return false
    }

    static BindKeysSafe(cfg, bindings, boundArr, condFn := "") {
        if (!IsObject(boundArr))
            return
        this.UnbindKeys(boundArr)
        if (IsObject(condFn))
            HotIf condFn
        try {
            for _, item in bindings {
                k := item.key
                if (this.IsReservedAudioKey(cfg, k))
                    continue
                try {
                    Hotkey(k, item.fn, "On")
                    boundArr.Push({ key: k, cond: condFn })
                }
            }
        } finally {
            if (IsObject(condFn))
                HotIf
        }
    }

    static UnbindKeys(boundArr) {
        if (!IsObject(boundArr))
            return
        for _, entry in boundArr {
            k := IsObject(entry) ? entry.key : entry
            condFn := (IsObject(entry) && entry.HasOwnProp("cond")) ? entry.cond : ""
            try {
                if (IsObject(condFn))
                    HotIf condFn
                Hotkey(k, "Off")
            } finally {
                if (IsObject(condFn))
                    HotIf
            }
        }
        boundArr.Length := 0
    }

    static NowUs() {
        if (!this._qpcFreq) {
            f := 0
            DllCall("QueryPerformanceFrequency", "Int64*", &f)
            this._qpcFreq := Max(1, f)
        }
        c := 0
        DllCall("QueryPerformanceCounter", "Int64*", &c)
        return (Float(c) * 1000000.0) / Float(this._qpcFreq)
    }

    static BeginHighResTimer() {
        if (!this._mmTimerActive) {
            try DllCall("winmm\timeBeginPeriod", "UInt", 1)
            this._mmTimerActive := true
        }
    }

    static EndHighResTimer() {
        if (this._mmTimerActive) {
            try DllCall("winmm\timeEndPeriod", "UInt", 1)
            this._mmTimerActive := false
        }
    }

    static LoadHighScore(cfg, gameId) {
        if (!IsObject(cfg) || !HasMethod(cfg, "Read"))
            return 0
        try return Max(0, Integer(cfg.Read("ArcadeHighScores", String(gameId), 0)))
        return 0
    }

    static SaveHighScore(cfg, gameId, score) {
        if (!IsObject(cfg) || !HasMethod(cfg, "Write"))
            return false
        try {
            cfg.Write("ArcadeHighScores", String(gameId), Integer(score))
            return true
        }
        return false
    }

    static GetLiveMicPillRect(cfg, state) {
        if (!IsObject(state) || !state.HasOwnProp("MicGui") || !IsObject(state.MicGui))
            return ""
        try {
            if (!WinExist("ahk_id " state.MicGui.Hwnd))
                return ""
            WinGetPos(&mx, &my, &mw, &mh, "ahk_id " state.MicGui.Hwnd)
            waL := 0, waT := 0, waR := A_ScreenWidth, waB := A_ScreenHeight
            try MonitorGetWorkArea(, &waL, &waT, &waR, &waB)
            return { x: mx - waL, y: my - waT, w: mw, h: mh }
        }
        return ""
    }

    static PauseHostPolling(state) {
        saved := Map()
        if (!IsObject(state))
            return saved
        for _, prop in ["obsTimerFn", "zoomTimerFn", "autoDodgeTimerFn", "mutedVoiceTimerFn"] {
            if (state.HasOwnProp(prop) && IsObject(state.%prop%)) {
                try SetTimer(state.%prop%, 0)
                saved[prop] := true
            }
        }
        return saved
    }

    static RestoreHostPolling(cfg, state, saved) {
        if (!IsObject(state) || !IsObject(saved))
            return
        if (saved.Has("obsTimerFn") && state.HasOwnProp("obsTimerFn") && IsObject(state.obsTimerFn)) {
            if (IsObject(cfg) && cfg.HasOwnProp("EnableWS") && cfg.EnableWS)
                try SetTimer(state.obsTimerFn, UIConstants.OBS_POLL_INTERVAL_MS)
        }
        if (saved.Has("zoomTimerFn") && IsSet(UpdateZoomMonitorTimer))
            try UpdateZoomMonitorTimer(cfg, state)
        if (saved.Has("autoDodgeTimerFn") && IsSet(UpdateAutoDodgeTimer))
            try UpdateAutoDodgeTimer(cfg, state)
        if (saved.Has("mutedVoiceTimerFn") && IsSet(UpdateMutedVoiceMonitorTimer))
            try UpdateMutedVoiceMonitorTimer(cfg, state)
    }

    static PollXInput() {
        if (!this._gpDllChecked) {
            this._gpDllChecked := true
            for _, dll in ["xinput1_4", "xinput9_1_0", "xinput1_3"] {
                if (DllCall("GetModuleHandle", "Str", dll, "Ptr") || DllCall("LoadLibrary", "Str", dll, "Ptr")) {
                    this._gpDllName := dll
                    break
                }
            }
        }
        if (this._gpDllName = "")
            return ""
        Loop 4 {
            idx := A_Index - 1
            NumPut("UInt", 0, "UInt", 0, "UShort", 0, "UChar", 0, "UChar", 0, this._gpBuf, 0)
            res := DllCall(this._gpDllName "\XInputGetState", "UInt", idx, "Ptr", this._gpBuf, "UInt")
            if (res == 0) {
                btn := NumGet(this._gpBuf, 4, "UShort")
                lx := NumGet(this._gpBuf, 8, "Short")
                ly := NumGet(this._gpBuf, 10, "Short")
                return { btn: btn, lx: lx, ly: ly }
            }
        }
        return ""
    }

    static CreateSurface(opts := "") {
        Gdip.Startup()
        o := IsObject(opts) ? opts : {}
        interactive := o.HasOwnProp("interactiveMouse") ? !!o.interactiveMouse : false
        cursorId := o.HasOwnProp("cursorId") ? Integer(o.cursorId) : 32512
        title := o.HasOwnProp("title") ? String(o.title) : "PresenterSyncArcade"
        headless := o.HasOwnProp("headless") ? !!o.headless : false
        onMouse := (o.HasOwnProp("onMouseEvent") && IsObject(o.onMouseEvent)) ? o.onMouseEvent : ""

        waL := 0, waT := 0, waR := A_ScreenWidth, waB := A_ScreenHeight
        try MonitorGetWorkArea(, &waL, &waT, &waR, &waB)
        W := Max(320, waR - waL)
        H := Max(240, waB - waT)

        NumPut("UInt", 40, "Int", W, "Int", -H, "UShort", 1, "UShort", 32, this._bi, 0)
        hdcScreen := DllCall("GetDC", "Ptr", 0, "Ptr")
        hdcMem := DllCall("CreateCompatibleDC", "Ptr", hdcScreen, "Ptr")
        pBits := 0
        hbm := DllCall("CreateDIBSection", "Ptr", hdcScreen, "Ptr", this._bi, "UInt", 0, "Ptr*", &pBits, "Ptr", 0, "UInt", 0, "Ptr")
        if (hdcScreen)
            DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdcScreen)
        if (!hdcMem || !hbm)
            return ""
        obm := DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hbm, "Ptr")
        pGraphics := 0
        DllCall("gdiplus\GdipCreateFromHDC", "Ptr", hdcMem, "Ptr*", &pGraphics)
        if (pGraphics) {
            DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", pGraphics, "Int", 4)
            DllCall("gdiplus\GdipSetTextRenderingHint", "Ptr", pGraphics, "Int", 4)
        }

        surf := {
            gui: "",
            hwnd: 0,
            waLeft: waL,
            waTop: waT,
            W: W,
            H: H,
            hdcMem: hdcMem,
            hbm: hbm,
            obm: obm,
            pBits: pBits,
            pGraphics: pGraphics,
            interactiveMouse: interactive,
            clearArgb: interactive ? 0x01000000 : 0x00000000,
            exStyle: interactive ? 0x08080000 : 0x00080020,
            cursorId: cursorId,
            onMouseEvent: onMouse,
            _msgHandlers: [],
            _mouseActFn: "",
            _mouseEvtFn: "",
            _cursorFn: ""
        }

        if (!headless) {
            ; Dual Win32 click-routing:
            ; interactiveMouse=false -> +E0x20 click-through with 0x00000000 clear.
            ; interactiveMouse=true  -> -E0x20 + WS_EX_NOACTIVATE (+E0x08000000) + 0x01000000 catch-alpha.
            styleStr := interactive
                ? "+AlwaysOnTop -Caption +ToolWindow +E0x80000 +E0x08000000 -DPIScale"
                : "+AlwaysOnTop -Caption +ToolWindow +E0x80000 +E0x20 -DPIScale"
            g := Gui(styleStr, title)
            g.Show("x" waL " y" waT " w" W " h" H " NoActivate")
            surf.gui := g
            surf.hwnd := g.Hwnd
            surf.exStyle := DllCall("GetWindowLongPtr", "Ptr", g.Hwnd, "Int", -20, "Ptr")
            if (IsSet(ApplyWindowCaptureAffinity)) {
                try ApplyWindowCaptureAffinity(g.Hwnd, true)
            } else {
                try DllCall("SetWindowDisplayAffinity", "Ptr", g.Hwnd, "UInt", 0x11, "Int")
            }

            if (interactive) {
                targetHwnd := g.Hwnd
                actFn := (wParam, lParam, msg, hwnd) => (hwnd == targetHwnd ? 3 : "")
                curFn := (wParam, lParam, msg, hwnd) => (hwnd == targetHwnd ? (DllCall("SetCursor", "Ptr", DllCall("LoadCursor", "Ptr", 0, "Ptr", surf.cursorId, "Ptr")), 1) : "")
                HandleMouse(wParam, lParam, msg, hwnd) {
                    if (hwnd != targetHwnd)
                        return
                    x := lParam & 0xFFFF
                    y := (lParam >> 16) & 0xFFFF
                    x := (x > 0x7FFF) ? (x - 0x10000) : x
                    y := (y > 0x7FFF) ? (y - 0x10000) : y
                    if (IsObject(surf.onMouseEvent))
                        try surf.onMouseEvent.Call(msg, x, y, wParam)
                    return 0
                }
                surf._mouseActFn := actFn
                surf._cursorFn := curFn
                surf._mouseEvtFn := HandleMouse

                OnMessage(0x0021, actFn)
                surf._msgHandlers.Push({ msg: 0x0021, fn: actFn })
                OnMessage(0x0020, curFn)
                surf._msgHandlers.Push({ msg: 0x0020, fn: curFn })
                for _, wm in [0x0200, 0x0201, 0x0202, 0x0203, 0x0204, 0x0205] {
                    OnMessage(wm, HandleMouse)
                    surf._msgHandlers.Push({ msg: wm, fn: HandleMouse })
                }
            }
        }
        return surf
    }

    static BeginFrame(surf) {
        if (!IsObject(surf) || !surf.pGraphics)
            return false
        DllCall("gdiplus\GdipGraphicsClear", "Ptr", surf.pGraphics, "UInt", surf.clearArgb)
        return true
    }

    static PresentFrame(surf, alpha := 255) {
        if (!IsObject(surf) || !surf.hwnd || !surf.hdcMem)
            return false
        NumPut("Int", Integer(surf.waLeft), "Int", Integer(surf.waTop), this._ptWin, 0)
        NumPut("Int", Integer(surf.W), "Int", Integer(surf.H), this._szWin, 0)
        NumPut("Int64", 0, this._ptSrc, 0)
        a := Max(0, Min(255, Integer(alpha)))
        NumPut("UInt", 0x01000000 | ((a & 0xFF) << 16), this._blend, 0)
        return DllCall("UpdateLayeredWindow", "Ptr", surf.hwnd, "Ptr", 0, "Ptr", this._ptWin, "Ptr", this._szWin, "Ptr", surf.hdcMem, "Ptr", this._ptSrc, "UInt", 0, "Ptr", this._blend, "UInt", 2, "Int") != 0
    }

    static DestroySurface(surf) {
        if (!IsObject(surf))
            return
        if (surf.HasOwnProp("_msgHandlers") && IsObject(surf._msgHandlers)) {
            for _, h in surf._msgHandlers {
                try OnMessage(h.msg, h.fn, 0)
            }
            surf._msgHandlers.Length := 0
        }
        if (surf.pGraphics) {
            try DllCall("gdiplus\GdipDeleteGraphics", "Ptr", surf.pGraphics)
            surf.pGraphics := 0
        }
        if (surf.hdcMem && surf.obm) {
            try DllCall("SelectObject", "Ptr", surf.hdcMem, "Ptr", surf.obm)
            surf.obm := 0
        }
        if (surf.hbm) {
            try DllCall("DeleteObject", "Ptr", surf.hbm)
            surf.hbm := 0
        }
        if (surf.hdcMem) {
            try DllCall("DeleteDC", "Ptr", surf.hdcMem)
            surf.hdcMem := 0
        }
        if (IsObject(surf.gui)) {
            try surf.gui.Destroy()
            surf.gui := ""
            surf.hwnd := 0
        }
    }

    static FillRoundedRect(pGraphics, x, y, w, h, r, argb) {
        pPath := Gdip.CreateRoundedRectPath(x, y, w, h, r)
        pBrush := 0
        try {
            if (pPath) {
                DllCall("gdiplus\GdipCreateSolidFill", "UInt", argb, "Ptr*", &pBrush)
                if (pBrush)
                    DllCall("gdiplus\GdipFillPath", "Ptr", pGraphics, "Ptr", pBrush, "Ptr", pPath)
            }
        } finally {
            if (pBrush)
                DllCall("gdiplus\GdipDeleteBrush", "Ptr", pBrush)
            if (pPath)
                DllCall("gdiplus\GdipDeletePath", "Ptr", pPath)
        }
    }

    static StrokeRoundedRect(pGraphics, x, y, w, h, r, argb, width := 1.5) {
        pPath := Gdip.CreateRoundedRectPath(x, y, w, h, r)
        pPen := 0
        try {
            if (pPath) {
                DllCall("gdiplus\GdipCreatePen1", "UInt", argb, "Float", Float(width), "Int", 2, "Ptr*", &pPen)
                if (pPen)
                    DllCall("gdiplus\GdipDrawPath", "Ptr", pGraphics, "Ptr", pPen, "Ptr", pPath)
            }
        } finally {
            if (pPen)
                DllCall("gdiplus\GdipDeletePen", "Ptr", pPen)
            if (pPath)
                DllCall("gdiplus\GdipDeletePath", "Ptr", pPath)
        }
    }

    static DrawScoreboardPill(pGraphics, W, title, statsText, hintText, isDark := true, micMuted := -1) {
        if (!pGraphics)
            return
        pillW := Min(Float(W) - 40.0, Max(420.0, Float(StrLen(statsText) + StrLen(title) + StrLen(hintText)) * 7.2 + 120.0))
        pillH := 42.0
        px := (Float(W) - pillW) / 2.0
        py := 12.0
        bgArgb := isDark ? 0xDC111622 : 0xECF8FAFC
        brdArgb := isDark ? 0x6694A3B8 : 0x80475569
        txMain := isDark ? 0xFFF1F5F9 : 0xFF0F172A
        txSub := isDark ? 0xFF94A3B8 : 0xFF475569

        this.FillRoundedRect(pGraphics, px, py, pillW, pillH, 14.0, bgArgb)
        this.StrokeRoundedRect(pGraphics, px, py, pillW, pillH, 14.0, brdArgb, 1.4)

        leftStr := title "   |   " statsText
        Gdip.DrawText(pGraphics, leftStr, "Segoe UI", 9.5, 1, txMain, px + 14.0, py, pillW - 140.0, pillH, 0, 1, 0, true)
        if (micMuted >= 0) {
            micCol := micMuted ? 0xFFEF4444 : 0xFF10B981
            micTxt := micMuted ? "MIC: MUTED" : "MIC: LIVE"
            Gdip.DrawText(pGraphics, micTxt, "Segoe UI", 8.5, 1, micCol, px + pillW - 105.0, py, 92.0, pillH, 2, 1, 0, false)
        }
        if (hintText != "")
            Gdip.DrawText(pGraphics, hintText, "Segoe UI", 8.0, 0, txSub, px, py + pillH + 3.0, pillW, 18.0, 1, 1, 0, false)
    }

    static DrawOverlayCard(pGraphics, W, H, title, subLine, hintLine, accentArgb := 0xFF38BDF8, isDark := true) {
        if (!pGraphics)
            return
        cardW := Min(Float(W) - 48.0, 420.0)
        cardH := 156.0
        cx := (Float(W) - cardW) / 2.0
        cy := (Float(H) - cardH) / 2.0
        bgArgb := isDark ? 0xEB0F141F : 0xF4F8FAFC
        txMain := isDark ? 0xFFF8FAFC : 0xFF0F172A
        txSub := isDark ? 0xFFCBD5E1 : 0xFF334155

        this.FillRoundedRect(pGraphics, cx, cy, cardW, cardH, 16.0, bgArgb)
        this.StrokeRoundedRect(pGraphics, cx, cy, cardW, cardH, 16.0, accentArgb, 2.0)
        Gdip.DrawText(pGraphics, title, "Segoe UI", 16.0, 1, accentArgb, cx + 16.0, cy + 16.0, cardW - 32.0, 34.0, 1, 1, 0, true)
        Gdip.DrawText(pGraphics, subLine, "Segoe UI", 10.5, 1, txMain, cx + 16.0, cy + 56.0, cardW - 32.0, 40.0, 1, 1, 0, true)
        Gdip.DrawText(pGraphics, hintLine, "Segoe UI", 9.0, 0, txSub, cx + 16.0, cy + 104.0, cardW - 32.0, 34.0, 1, 1, 0, true)
    }
}
