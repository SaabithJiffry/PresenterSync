; ==============================================================================
; Module: GUI_Config.ahk
; Description: UIConstants, Config & OverlayState classes, Settings GUIs, HUD layout & animations
; ==============================================================================

#Include "%A_LineFile%\..\Gdip.ahk"
#Include "%A_LineFile%\..\OBS_Network.ahk"

class UIConstants {
    static APP_VERSION := "2.2.2"

    ; --- Base HUD Dimensions & Ratios ---
    static BASE_WIDTH_TEXT := 140
    static BASE_WIDTH_ICON := 80
    static BASE_HEIGHT := 40
    static HUD_GAP := 6
    static MIN_HUD_GAP := 2
    static REC_HEIGHT := 34
    static ROW3_HEIGHT := 30
    static REC_WIDTH_RATIO := 0.53
    static STUDIO_WIDTH_RATIO := 0.38
    static SCREEN_MARGIN_X := 20
    static SCREEN_MARGIN_Y := 20
    static SCREEN_MIN_PAD := 10
    static MIN_TEXT_WIDTH := 8

    ; --- Typography & Control Offsets ---
    static MIC_ICON_SIZE := 18
    static MIC_TEXT_SIZE := 13
    static SUB_ICON_SIZE := 12
    static SUB_TEXT_SIZE := 8
    static STUDIO_ICON_SIZE_TEXT := 11
    static STUDIO_ICON_SIZE_ONLY := 12
    static STUDIO_TEXT_SIZE := 8
    static MINI_TEXT_SIZE := 9

    static MIC_ICON_W := 30
    static ICON_OFFSET_X := 15
    static MIC_TEXT_W := 80
    static TEXT_OFFSET_X := 50
    static REC_ICON_W := 14
    static REC_ICON_X := 4
    static CHAT_ICON_W := 14
    static CHAT_ICON_X := 4
    static STUDIO_ICON_W := 14
    static STUDIO_ICON_X := 4
    static SCENE_PAD_X := 4
    static LABEL_GAP_X := 2

    ; --- Animation & Timing Constants ---
    static FADE_STEPS := 10
    static FADE_SLEEP_MS := 10
    static POP_WIDTH_INC_TEXT := 1.5
    static POP_WIDTH_INC_ICON := 1.0
    static POP_HEIGHT_INC := 0.5
    static PULSE_STEP_AGGRESSIVE := 20
    static PULSE_STEP_NORMAL := 5
    static PULSE_INTERVAL_AGGRESSIVE := 15
    static PULSE_INTERVAL_NORMAL := 40
    static PULSE_MIN_RATIO_AGGRESSIVE := 0.2
    static PULSE_MIN_RATIO_NORMAL := 0.6
    static DRAG_SYNC_INTERVAL_MS := 16
    static PPT_DEBOUNCE_MS := 150
    static ZOOM_POLL_INTERVAL_MS := 500
    static ZOOM_REC_GRACE_MS := 1500
    static SYNC_LOCK_TIMEOUT_MS := 1000
    static OBS_RECONNECT_MS := 5000
    static OBS_INIT_DELAY_MS := 100
    static TOOLTIP_DURATION_MS := 2000

    ; --- Opacity Presets & Corner Constants ---
    static OPACITY_SOLID := 255
    static OPACITY_FROSTED := 220
    static OPACITY_GHOST := 127
    static CORNER_RADIUS_DEFAULT := 8
    static CORNER_RADIUS_SLEEK := 18

    ; --- Color Palette (RGB Strings & Hex Integers) ---
    static COLOR_LIVE := "22C55E"
    static COLOR_MUTED := "EF4444"
    static BORDER_LIVE := 0x5EC522
    static BORDER_MUTED := 0x4444EF
    static ICON_LIVE := "064E3B"
    static ICON_MUTED := "540808"

    static COLOR_REC_OFF := "374151"
    static BORDER_REC_OFF := 0x514137
    static ICON_REC_OFF := "9CA3AF"
    static COLOR_REC_ACTIVE := "DC2626"
    static BORDER_REC_ACTIVE := 0x2626DC
    static ICON_REC_ACTIVE := "7F1D1D"
    static COLOR_REC_PAUSED := "D97706"
    static BORDER_REC_PAUSED := 0x0677D9
    static ICON_REC_PAUSED := "78350F"

    static COLOR_STUDIO_OFF := "374151"
    static BORDER_STUDIO_OFF := 0x514137
    static ICON_STUDIO_OFF := "9CA3AF"
    static COLOR_STUDIO_ON := "7C3AED"
    static BORDER_STUDIO_ON := 0xED3A7C
    static ICON_STUDIO_ON := "4C1D95"

    static COLOR_SCENE := "1E293B"
    static BORDER_SCENE := 0x3B291E

    static COLOR_CHAT_CLEAR := "374151"
    static BORDER_CHAT_CLEAR := 0x514137
    static ICON_CHAT_CLEAR := "9CA3AF"
    static COLOR_CHAT_ALERT := "2563EB"
    static BORDER_CHAT_ALERT := 0xEB6325
    static ICON_CHAT_ALERT := "1E3A8A"

    ; --- Windows 11 Explorer / Fluent Theme Palette (Dark & Light) ---
    static DARK_BG := "202020"
    static DARK_SURFACE := "2C2C2C"
    static DARK_INPUT_BG := "2D2D2D"
    static DARK_TEXT := "FFFFFF"
    static DARK_TEXT_MUTED := "C5C5C5"
    static DARK_TEXT_DISABLED := "787878"
    static DARK_ACCENT := "60CDFF"

    static LIGHT_BG := "F3F3F3"
    static LIGHT_SURFACE := "FFFFFF"
    static LIGHT_INPUT_BG := "FBFBFB"
    static LIGHT_TEXT := "1A1A1A"
    static LIGHT_TEXT_MUTED := "5C5C5C"
    static LIGHT_TEXT_DISABLED := "9E9E9E"
    static LIGHT_ACCENT := "0067C0"

    static DARK_BG_BGR := 0x202020
    static DARK_SURFACE_BGR := 0x2C2C2C
    static DARK_TAB_ACTIVE_BGR := 0x2C2C2C
    static DARK_TAB_INACTIVE_BGR := 0x202020
    static DARK_INPUT_BG_BGR := 0x2D2D2D
    static DARK_INPUT_DISABLED_BGR := 0x242424
    static DARK_BORDER_BGR := 0x3D3D3D
    static DARK_BORDER_SUBTLE_BGR := 0x383838
    static DARK_BORDER_DISABLED_BGR := 0x303030
    static DARK_ACCENT_BGR := 0xFFCD60
    static DARK_TEXT_BGR := 0xFFFFFF
    static DARK_TEXT_MUTED_BGR := 0xC5C5C5
    static DARK_TEXT_DISABLED_BGR := 0x787878

    static LIGHT_BG_BGR := 0xF3F3F3
    static LIGHT_SURFACE_BGR := 0xFFFFFF
    static LIGHT_BORDER_BGR := 0xE5E5E5
    static LIGHT_TEXT_BGR := 0x1A1A1A
    static LIGHT_TEXT_MUTED_BGR := 0x5C5C5C
    static LIGHT_TEXT_DISABLED_BGR := 0x9E9E9E
    static LIGHT_ACCENT_BGR := 0xC06700

    static FLUENT_CORNER_RADIUS := 6.0
    static FLUENT_CARD_RADIUS := 8.0
}

class Theme {
    static OverrideMode := ""
    static OpenWindows := Map()
    static NamedWindows := Map()
    static HoverMap := Map()
    static PressMap := Map()
    static TabHoverMap := Map()
    static BoldFontCache := Map()
    static SuspendLockCount := 0
    static WasSuspendedBeforeDialogs := false
    static hUxtheme := 0
    static fnSetPreferredAppMode := 0
    static fnFlushMenuThemes := 0
    static hkSubclassPtr := 0
    static tabSubclassPtr := 0
    static staticSubclassPtr := 0
    static btnSubclassPtr := 0
    static UiFont := "Segoe UI"
    static initialized := false
    static lastIsDark := -1

    static Init(mode := "") {
        this.EnsureInitialized()
        if (mode != "")
            this.SetMode(mode, false)
        this.ApplyMenuTheme()
    }

    static Shutdown() {
        for _, hBold in this.BoldFontCache {
            if (hBold)
                DllCall("DeleteObject", "Ptr", hBold)
        }
        this.BoldFontCache.Clear()
    }

    static AcquireSuspend() {
        if (this.SuspendLockCount == 0)
            this.WasSuspendedBeforeDialogs := A_IsSuspended
        this.SuspendLockCount += 1
        Suspend(True)
    }

    static ReleaseSuspend() {
        if (this.SuspendLockCount > 0) {
            this.SuspendLockCount -= 1
            if (this.SuspendLockCount == 0 && !this.WasSuspendedBeforeDialogs)
                Suspend(False)
        }
    }

    static FocusExistingWindow(winKey) {
        if (winKey != "" && this.NamedWindows.Has(winKey)) {
            existing := this.NamedWindows[winKey]
            try {
                if (IsObject(existing) && WinExist("ahk_id " existing.Hwnd)) {
                    WinActivate("ahk_id " existing.Hwnd)
                    return existing
                }
            }
            this.NamedWindows.Delete(winKey)
        }
        return ""
    }

    static UnregisterWindow(guiObj, winKey := "") {
        if (IsObject(guiObj) && this.OpenWindows.Has(guiObj.Hwnd))
            this.OpenWindows.Delete(guiObj.Hwnd)
        if (winKey != "" && this.NamedWindows.Has(winKey))
            this.NamedWindows.Delete(winKey)
    }

    static SetMode(mode, refresh := true) {
        m := StrLower(Trim(mode))
        if (m = "dark")
            this.OverrideMode := "dark"
        else if (m = "light")
            this.OverrideMode := "light"
        else
            this.OverrideMode := ""
        if (refresh && this.initialized)
            this.RefreshOpenWindows()
    }

    static EnsureInitialized() {
        if (this.initialized)
            return
        Gdip.Startup()
        osParts := StrSplit(A_OSVersion, ".")
        buildNum := (osParts.Length >= 3) ? Integer(osParts[3]) : 0
        this.UiFont := (buildNum >= 22000) ? "Segoe UI Variable Text" : "Segoe UI"
        this.hUxtheme := DllCall("GetModuleHandle", "Str", "uxtheme", "Ptr")
        if (!this.hUxtheme)
            this.hUxtheme := DllCall("LoadLibrary", "Str", "uxtheme", "Ptr")
        if (this.hUxtheme) {
            this.fnSetPreferredAppMode := DllCall("GetProcAddress", "Ptr", this.hUxtheme, "Ptr", 135, "Ptr")
            this.fnFlushMenuThemes := DllCall("GetProcAddress", "Ptr", this.hUxtheme, "Ptr", 136, "Ptr")
        }
        this.hkSubclassPtr := CallbackCreate(HotkeyFluentSubclassProc)
        this.tabSubclassPtr := CallbackCreate(TabFluentSubclassProc)
        this.staticSubclassPtr := CallbackCreate(StaticFluentSubclassProc)
        this.btnSubclassPtr := CallbackCreate(ButtonFluentSubclassProc)
        OnMessage(0x001A, WM_SETTINGCHANGE_Theme)
        this.initialized := true
    }

    static GetFont(hwnd, boldOrWeight := false) {
        hFont := SendMessage(0x0031, 0, 0, hwnd) ; WM_GETFONT
        if (!hFont)
            hFont := DllCall("GetStockObject", "Int", 17, "Ptr") ; DEFAULT_GUI_FONT
        lf := Buffer(92, 0)
        if (DllCall("GetObjectW", "Ptr", hFont, "Int", 92, "Ptr", lf) == 0)
            return hFont
        targetWeight := (boldOrWeight is Integer && boldOrWeight > 1) ? boldOrWeight : (boldOrWeight ? 600 : 400)
        targetFace := this.UiFont
        fontKey := NumGet(lf, 0, "Int") ":" targetWeight ":" targetFace
        if this.BoldFontCache.Has(fontKey)
            return this.BoldFontCache[fontKey]
        NumPut("Int", targetWeight, lf, 16) ; fwWeight
        NumPut("UChar", 0, lf, 20)          ; lfItalic = 0 (strictly non-italic)
        NumPut("UChar", 0, lf, 21)          ; lfUnderline = 0
        NumPut("UChar", 0, lf, 22)          ; lfStrikeOut = 0
        NumPut("UChar", 5, lf, 26)          ; lfQuality = 5 (CLEARTYPE_QUALITY)
        StrPut(targetFace, lf.Ptr + 28, 32, "UTF-16")
        hNewFont := DllCall("CreateFontIndirectW", "Ptr", lf, "Ptr")
        if (hNewFont) {
            this.BoldFontCache[fontKey] := hNewFont
            return hNewFont
        }
        return hFont
    }

    static IsDarkMode() {
        if (this.OverrideMode = "dark")
            return true
        if (this.OverrideMode = "light")
            return false
        try {
            appsLight := RegRead("HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "AppsUseLightTheme", 1)
            return (appsLight == 0)
        } catch {
            return false
        }
    }

    static ApplyMenuTheme(isDark := "") {
        this.EnsureInitialized()
        if (isDark = "")
            isDark := this.IsDarkMode()
        this.lastIsDark := isDark ? 1 : 0
        if (this.fnSetPreferredAppMode)
            DllCall(this.fnSetPreferredAppMode, "Int", isDark ? 2 : 3, "Int")
        if (this.fnFlushMenuThemes)
            DllCall(this.fnFlushMenuThemes)
    }

    static ApplyTitleBarTheme(hwnd, isDark) {
        useDark := isDark ? 1 : 0
        if (DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "Int", 20, "Int*", &useDark, "Int", 4) != 0)
            DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "Int", 19, "Int*", &useDark, "Int", 4)
        ; DWMWA_WINDOW_CORNER_PREFERENCE = 33 (2 = DWMWCP_ROUND)
        cornerPref := 2
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "Int", 33, "Int*", &cornerPref, "Int", 4)
        ; DWMWA_BORDER_COLOR = 34, DWMWA_CAPTION_COLOR = 35, DWMWA_TEXT_COLOR = 36
        brdColor := isDark ? UIConstants.DARK_BORDER_DISABLED_BGR : UIConstants.LIGHT_BORDER_BGR
        capColor := isDark ? UIConstants.DARK_BG_BGR : UIConstants.LIGHT_BG_BGR
        txtColor := isDark ? UIConstants.DARK_TEXT_BGR : UIConstants.LIGHT_TEXT_BGR
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "Int", 34, "UInt*", &brdColor, "Int", 4)
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "Int", 35, "UInt*", &capColor, "Int", 4)
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "Int", 36, "UInt*", &txtColor, "Int", 4)
    }

    static ApplyToWindow(guiObj, isDark := "") {
        this.EnsureInitialized()
        if (isDark = "")
            isDark := this.IsDarkMode()
        this.ApplyMenuTheme(isDark)
        this.ApplyTitleBarTheme(guiObj.Hwnd, isDark)
        guiObj.BackColor := isDark ? UIConstants.DARK_BG : UIConstants.LIGHT_BG
        guiObj.SetFont("s10 w400 " (isDark ? "c" UIConstants.DARK_TEXT : "c" UIConstants.LIGHT_TEXT), this.UiFont)
        guiObj._isDark := isDark
        if (!guiObj.HasOwnProp("_themedCtrls"))
            guiObj._themedCtrls := []
        this.OpenWindows[guiObj.Hwnd] := guiObj
    }

    static RegisterControl(guiObj, ctrl, ctrlType := "", role := "") {
        ctrl._themeType := ctrlType
        ctrl._themeRole := role
        if (role = "tabButton")
            ctrl._inTab := true
        if (guiObj.HasOwnProp("_themedCtrls"))
            guiObj._themedCtrls.Push(ctrl)
        this.ApplyToControl(ctrl, ctrlType, guiObj.HasOwnProp("_isDark") ? guiObj._isDark : "", role)
    }

    static ApplyToControl(ctrl, ctrlType := "", isDark := "", role := "") {
        this.EnsureInitialized()
        if (!IsObject(ctrl))
            return
        if (isDark = "")
            isDark := this.IsDarkMode()
        if (ctrlType = "" && ctrl.HasOwnProp("_themeType"))
            ctrlType := ctrl._themeType
        if (role = "" && ctrl.HasOwnProp("_themeRole"))
            role := ctrl._themeRole

        if (ctrlType = "Button") {
            DllCall("uxtheme\SetWindowTheme", "Ptr", ctrl.Hwnd, "Str", isDark ? "DarkMode_Explorer" : "Explorer", "Ptr", 0)
            DllCall("comctl32\SetWindowSubclass", "Ptr", ctrl.Hwnd, "Ptr", this.btnSubclassPtr, "Ptr", 4, "Ptr", 0)
            if DllCall("IsWindowVisible", "Ptr", ctrl.Hwnd)
                DllCall("InvalidateRect", "Ptr", ctrl.Hwnd, "Ptr", 0, "Int", 1)
        } else if (ctrlType = "Checkbox") {
            ctrl.Opt(isDark ? ("+Background" UIConstants.DARK_BG " c" UIConstants.DARK_TEXT) : ("+Background" UIConstants.LIGHT_BG " c" UIConstants.LIGHT_TEXT))
            DllCall("uxtheme\SetWindowTheme", "Ptr", ctrl.Hwnd, "Str", isDark ? "DarkMode_Explorer" : "Explorer", "Ptr", 0)
        } else if (ctrlType = "Edit") {
            ctrl.Opt(isDark ? ("+Background" UIConstants.DARK_INPUT_BG " c" UIConstants.DARK_TEXT) : ("+Background" UIConstants.LIGHT_SURFACE " c" UIConstants.LIGHT_TEXT))
            DllCall("uxtheme\SetWindowTheme", "Ptr", ctrl.Hwnd, "Str", isDark ? "DarkMode_CFD" : "Explorer", "Ptr", 0)
        } else if (ctrlType = "DropDownList") {
            ctrl.Opt(isDark ? ("+Background" UIConstants.DARK_INPUT_BG " c" UIConstants.DARK_TEXT) : ("+Background" UIConstants.LIGHT_SURFACE " c" UIConstants.LIGHT_TEXT))
            DllCall("uxtheme\SetWindowTheme", "Ptr", ctrl.Hwnd, "Str", isDark ? "DarkMode_CFD" : "Explorer", "Ptr", 0)
        } else if (ctrlType = "Hotkey") {
            DllCall("comctl32\SetWindowSubclass", "Ptr", ctrl.Hwnd, "Ptr", this.hkSubclassPtr, "Ptr", 1, "Ptr", 0)
            DllCall("InvalidateRect", "Ptr", ctrl.Hwnd, "Ptr", 0, "Int", 1)
        } else if (ctrlType = "Tab") {
            rc := Buffer(16, 0)
            DllCall("GetClientRect", "Ptr", ctrl.Hwnd, "Ptr", rc)
            tw := NumGet(rc, 8, "Int")
            tabCount := SendMessage(0x1304, 0, 0, ctrl.Hwnd) ; TCM_GETITEMCOUNT
            if (tabCount > 0 && tw > 0) {
                dpiScale := A_ScreenDPI / 96.0
                itemH := Round(36 * dpiScale)
                itemW := Floor((tw - 4) / tabCount)
                SendMessage(0x1329, 0, (itemH << 16) | (itemW & 0xFFFF), ctrl.Hwnd) ; TCM_SETITEMSIZE
            }
            DllCall("comctl32\SetWindowSubclass", "Ptr", ctrl.Hwnd, "Ptr", this.tabSubclassPtr, "Ptr", 2, "Ptr", 0)
            DllCall("InvalidateRect", "Ptr", ctrl.Hwnd, "Ptr", 0, "Int", 1)
        } else if (ctrlType = "Text") {
            if (role = "accent") {
                ctrl.Opt(isDark ? ("+Background" UIConstants.DARK_BG " c" UIConstants.DARK_ACCENT) : ("+Background" UIConstants.LIGHT_BG " c" UIConstants.LIGHT_ACCENT))
            } else if (role = "tabText") {
                ctrl.Opt(isDark ? ("+Background" UIConstants.DARK_SURFACE " c" UIConstants.DARK_TEXT) : ("+Background" UIConstants.LIGHT_SURFACE " c" UIConstants.LIGHT_TEXT))
            } else if (role = "tabMuted") {
                ctrl.Opt(isDark ? ("+Background" UIConstants.DARK_SURFACE " c" UIConstants.DARK_TEXT_MUTED) : ("+Background" UIConstants.LIGHT_SURFACE " c" UIConstants.LIGHT_TEXT_MUTED))
            } else if (role = "muted") {
                ctrl.Opt(isDark ? ("+Background" UIConstants.DARK_BG " c" UIConstants.DARK_TEXT_MUTED) : ("+Background" UIConstants.LIGHT_BG " c" UIConstants.LIGHT_TEXT_MUTED))
            } else {
                ctrl.Opt(isDark ? ("+Background" UIConstants.DARK_BG " c" UIConstants.DARK_TEXT) : ("+Background" UIConstants.LIGHT_BG " c" UIConstants.LIGHT_TEXT))
            }
            DllCall("comctl32\SetWindowSubclass", "Ptr", ctrl.Hwnd, "Ptr", this.staticSubclassPtr, "Ptr", 3, "Ptr", 0)
            DllCall("InvalidateRect", "Ptr", ctrl.Hwnd, "Ptr", 0, "Int", 1)
        }
    }

    static RefreshWindow(guiObj, isDark := "") {
        if (!IsObject(guiObj) || !WinExist("ahk_id " guiObj.Hwnd))
            return
        if (isDark = "")
            isDark := this.IsDarkMode()
        this.ApplyToWindow(guiObj, isDark)
        if (guiObj.HasOwnProp("_themedCtrls")) {
            for ctrl in guiObj._themedCtrls {
                try this.ApplyToControl(ctrl, "", isDark)
            }
        }
        DllCall("SetWindowPos", "Ptr", guiObj.Hwnd, "Ptr", 0, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x0037)
        DllCall("RedrawWindow", "Ptr", guiObj.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x0585)
    }

    static RefreshOpenWindows(isDark := "") {
        if (isDark = "")
            isDark := this.IsDarkMode()
        this.ApplyMenuTheme(isDark)
        stale := []
        for hwnd, guiObj in this.OpenWindows {
            if (IsObject(guiObj) && WinExist("ahk_id " hwnd))
                this.RefreshWindow(guiObj, isDark)
            else
                stale.Push(hwnd)
        }
        for hwnd in stale
            this.OpenWindows.Delete(hwnd)
    }
}

WM_SETTINGCHANGE_Theme(wParam, lParam, msg, hwnd) {
    curDark := Theme.IsDarkMode() ? 1 : 0
    if (curDark != Theme.lastIsDark)
        Theme.RefreshOpenWindows(curDark == 1)
}

FormatHkDisplayText(hkVal) {
    if (hkVal = "" || hkVal = "None")
        return "None"
    out := ""
    i := 1
    len := StrLen(hkVal)
    hasCtrl := false, hasShift := false, hasAlt := false, hasWin := false
    while (i < len) {
        ch := SubStr(hkVal, i, 1)
        if (ch = "^")
            hasCtrl := true
        else if (ch = "+")
            hasShift := true
        else if (ch = "!")
            hasAlt := true
        else if (ch = "#")
            hasWin := true
        else if (ch = "~" || ch = "$" || ch = "*") {
        } else {
            break
        }
        i += 1
    }
    keyPart := SubStr(hkVal, i)
    if (hasCtrl)
        out .= "Ctrl + "
    if (hasShift)
        out .= "Shift + "
    if (hasAlt)
        out .= "Alt + "
    if (hasWin)
        out .= "Win + "
    if (StrLen(keyPart) == 1)
        keyPart := StrUpper(keyPart)
    return out . keyPart
}

DrawFluentRoundedBox(pGraphics, x, y, w, h, radius, fillArgb, strokeArgb := 0, bottomAccentArgb := 0) {
    pPath := Gdip.CreateRoundedRectPath(x, y, w - 1.0, h - 1.0, radius)
    if (!pPath)
        return
    pFill := 0
    DllCall("gdiplus\GdipCreateSolidFill", "UInt", fillArgb, "Ptr*", &pFill)
    if (pFill) {
        DllCall("gdiplus\GdipFillPath", "Ptr", pGraphics, "Ptr", pFill, "Ptr", pPath)
        DllCall("gdiplus\GdipDeleteBrush", "Ptr", pFill)
    }
    if (strokeArgb != 0) {
        pPen := 0
        DllCall("gdiplus\GdipCreatePen1", "UInt", strokeArgb, "Float", 1.0, "Int", 2, "Ptr*", &pPen)
        if (pPen) {
            DllCall("gdiplus\GdipDrawPath", "Ptr", pGraphics, "Ptr", pPen, "Ptr", pPath)
            DllCall("gdiplus\GdipDeletePen", "Ptr", pPen)
        }
    }
    DllCall("gdiplus\GdipDeletePath", "Ptr", pPath)

    if (bottomAccentArgb != 0) {
        pAccPath := Gdip.CreateRoundedRectPath(x + 2.0, y + h - 3.0, w - 5.0, 2.0, 1.0)
        if (pAccPath) {
            pAccFill := 0
            DllCall("gdiplus\GdipCreateSolidFill", "UInt", bottomAccentArgb, "Ptr*", &pAccFill)
            if (pAccFill) {
                DllCall("gdiplus\GdipFillPath", "Ptr", pGraphics, "Ptr", pAccFill, "Ptr", pAccPath)
                DllCall("gdiplus\GdipDeleteBrush", "Ptr", pAccFill)
            }
            DllCall("gdiplus\GdipDeletePath", "Ptr", pAccPath)
        }
    }
}

DrawFluentControlText(hdc, textStr, x, y, w, h, hFont, textColorBgr, alignFlags := 0x0025) {
    if (textStr = "" || w <= 0 || h <= 0)
        return
    tRc := Buffer(16, 0)
    NumPut("Int", Integer(x), tRc, 0)
    NumPut("Int", Integer(y), tRc, 4)
    NumPut("Int", Integer(x + w), tRc, 8)
    NumPut("Int", Integer(y + h), tRc, 12)
    oldFont := hFont ? DllCall("SelectObject", "Ptr", hdc, "Ptr", hFont, "Ptr") : 0
    DllCall("SetBkMode", "Ptr", hdc, "Int", 1) ; TRANSPARENT
    DllCall("SetTextColor", "Ptr", hdc, "UInt", textColorBgr)
    DllCall("DrawTextW", "Ptr", hdc, "WStr", textStr, "Int", -1, "Ptr", tRc, "UInt", alignFlags)
    if (oldFont)
        DllCall("SelectObject", "Ptr", hdc, "Ptr", oldFont, "Ptr")
}

ButtonFluentSubclassProc(hwnd, uMsg, wParam, lParam, uIdSubclass, dwRefData) {
    if (uMsg == 0x0082) { ; WM_NCDESTROY
        if Theme.HoverMap.Has(hwnd)
            Theme.HoverMap.Delete(hwnd)
        if Theme.PressMap.Has(hwnd)
            Theme.PressMap.Delete(hwnd)
        DllCall("comctl32\RemoveWindowSubclass", "Ptr", hwnd, "Ptr", uIdSubclass, "Ptr", dwRefData)
        return DllCall("comctl32\DefSubclassProc", "Ptr", hwnd, "UInt", uMsg, "Ptr", wParam, "Ptr", lParam, "Ptr")
    }
    if (uMsg == 0x0014) ; WM_ERASEBKGND
        return 1
    if (uMsg == 0x0113) ; WM_TIMER (suppress uxtheme BufferedPaint fade timers)
        return 0

    if (uMsg == 0x0200) { ; WM_MOUSEMOVE
        if (!Theme.HoverMap.Get(hwnd, false)) {
            Theme.HoverMap[hwnd] := true
            tme := Buffer(A_PtrSize == 8 ? 24 : 16, 0)
            NumPut("UInt", tme.Size, tme, 0)
            NumPut("UInt", 0x00000002, tme, 4) ; TME_LEAVE
            NumPut("Ptr", hwnd, tme, 8)
            DllCall("TrackMouseEvent", "Ptr", tme)
            DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", 0)
        }
    } else if (uMsg == 0x02A3) { ; WM_MOUSELEAVE
        Theme.HoverMap[hwnd] := false
        Theme.PressMap[hwnd] := false
        DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", 0)
    } else if (uMsg == 0x0201) { ; WM_LBUTTONDOWN
        Theme.PressMap[hwnd] := true
        DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", 0)
    } else if (uMsg == 0x0202) { ; WM_LBUTTONUP
        Theme.PressMap[hwnd] := false
        DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", 0)
    }

    if (uMsg == 0x000F) { ; WM_PAINT
        ps := Buffer(72, 0)
        hdc := DllCall("BeginPaint", "Ptr", hwnd, "Ptr", ps, "Ptr")
        rc := Buffer(16, 0)
        DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rc)
        w := NumGet(rc, 8, "Int"), h := NumGet(rc, 12, "Int")

        hdcMem := DllCall("CreateCompatibleDC", "Ptr", hdc, "Ptr")
        hbm := DllCall("CreateCompatibleBitmap", "Ptr", hdc, "Int", Max(1, w), "Int", Max(1, h), "Ptr")
        obm := DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hbm, "Ptr")

        ctrl := GuiCtrlFromHwnd(hwnd)
        parentDark := (IsObject(ctrl) && IsObject(ctrl.Gui) && ctrl.Gui.HasOwnProp("_isDark")) ? ctrl.Gui._isDark : Theme.IsDarkMode()
        inTab := (IsObject(ctrl) && ctrl.HasOwnProp("_inTab") && ctrl._inTab)
        parentBgBgr := parentDark ? (inTab ? UIConstants.DARK_SURFACE_BGR : UIConstants.DARK_BG_BGR) : (inTab ? UIConstants.LIGHT_SURFACE_BGR : UIConstants.LIGHT_BG_BGR)

        hBrParent := DllCall("CreateSolidBrush", "UInt", parentBgBgr, "Ptr")
        DllCall("FillRect", "Ptr", hdcMem, "Ptr", rc, "Ptr", hBrParent)
        DllCall("DeleteObject", "Ptr", hBrParent)

        style := DllCall("GetWindowLong", "Ptr", hwnd, "Int", -16, "Int") ; GWL_STYLE
        isDefaultBtn := ((style & 0x0F) == 1) || (IsObject(ctrl) && ctrl.HasOwnProp("_themeRole") && (ctrl._themeRole = "accent" || ctrl._themeRole = "primary"))
        isEnabled := DllCall("IsWindowEnabled", "Ptr", hwnd)
        isHover := Theme.HoverMap.Get(hwnd, false)
        isPress := Theme.PressMap.Get(hwnd, false)

        if (parentDark) {
            if (!isEnabled) {
                fillArgb := 0xFF252525, strokeArgb := 0xFF333333, txtBgr := UIConstants.DARK_TEXT_DISABLED_BGR
            } else if (isDefaultBtn) {
                fillArgb := isPress ? 0xFF4CC2FF : (isHover ? 0xFF72D4FF : 0xFF60CDFF)
                strokeArgb := 0xFF72D4FF
                txtBgr := 0x140E0A
            } else {
                fillArgb := isPress ? 0xFF272727 : (isHover ? 0xFF3C3C3C : 0xFF333333)
                strokeArgb := isHover ? 0xFF565656 : 0xFF454545
                txtBgr := UIConstants.DARK_TEXT_BGR
            }
        } else {
            if (!isEnabled) {
                fillArgb := 0xFFF0F0F0, strokeArgb := 0xFFE0E0E0, txtBgr := UIConstants.LIGHT_TEXT_DISABLED_BGR
            } else if (isDefaultBtn) {
                fillArgb := isPress ? 0xFF005A9E : (isHover ? 0xFF1874C4 : 0xFF0067C0)
                strokeArgb := 0xFF005A9E
                txtBgr := 0xFFFFFF
            } else {
                fillArgb := isPress ? 0xFFEFEFEF : (isHover ? 0xFFF6F6F6 : 0xFFFBFBFB)
                strokeArgb := isHover ? 0xFFC8C8C8 : 0xFFDCDCDC
                txtBgr := UIConstants.LIGHT_TEXT_BGR
            }
        }

        pGraphics := 0
        DllCall("gdiplus\GdipCreateFromHDC", "Ptr", hdcMem, "Ptr*", &pGraphics)
        if (pGraphics) {
            DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", pGraphics, "Int", 4)
            DrawFluentRoundedBox(pGraphics, 0, 0, w, h, UIConstants.FLUENT_CORNER_RADIUS, fillArgb, strokeArgb)
            DllCall("gdiplus\GdipDeleteGraphics", "Ptr", pGraphics)
        }

        btnTxt := IsObject(ctrl) ? StrReplace(ctrl.Text, "&&", "&") : ""
        hFont := Theme.GetFont(hwnd, 400)
        DrawFluentControlText(hdcMem, btnTxt, 4, 0, w - 8, h, hFont, txtBgr, 0x0825)

        DllCall("BitBlt", "Ptr", hdc, "Int", 0, "Int", 0, "Int", w, "Int", h, "Ptr", hdcMem, "Int", 0, "Int", 0, "UInt", 0x00CC0020)
        DllCall("SelectObject", "Ptr", hdcMem, "Ptr", obm)
        DllCall("DeleteObject", "Ptr", hbm)
        DllCall("DeleteDC", "Ptr", hdcMem)
        DllCall("EndPaint", "Ptr", hwnd, "Ptr", ps)
        return 0
    }

    res := DllCall("comctl32\DefSubclassProc", "Ptr", hwnd, "UInt", uMsg, "Ptr", wParam, "Ptr", lParam, "Ptr")
    if (uMsg == 0x0007 || uMsg == 0x0008 || uMsg == 0x000A || uMsg == 0x00F3 || uMsg == 0x00F4) {
        if DllCall("IsWindowVisible", "Ptr", hwnd)
            DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", 0)
    }
    return res
}

HotkeyFluentSubclassProc(hwnd, uMsg, wParam, lParam, uIdSubclass, dwRefData) {
    if (uMsg == 0x0082) { ; WM_NCDESTROY
        DllCall("comctl32\RemoveWindowSubclass", "Ptr", hwnd, "Ptr", uIdSubclass, "Ptr", dwRefData)
        return DllCall("comctl32\DefSubclassProc", "Ptr", hwnd, "UInt", uMsg, "Ptr", wParam, "Ptr", lParam, "Ptr")
    }
    if (uMsg == 0x0014) ; WM_ERASEBKGND
        return 1

    if (uMsg == 0x000F) { ; WM_PAINT
        ps := Buffer(72, 0)
        hdc := DllCall("BeginPaint", "Ptr", hwnd, "Ptr", ps, "Ptr")
        rc := Buffer(16, 0)
        DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rc)
        w := NumGet(rc, 8, "Int"), h := NumGet(rc, 12, "Int")

        hdcMem := DllCall("CreateCompatibleDC", "Ptr", hdc, "Ptr")
        hbm := DllCall("CreateCompatibleBitmap", "Ptr", hdc, "Int", Max(1, w), "Int", Max(1, h), "Ptr")
        obm := DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hbm, "Ptr")

        ctrl := GuiCtrlFromHwnd(hwnd)
        parentDark := (IsObject(ctrl) && IsObject(ctrl.Gui) && ctrl.Gui.HasOwnProp("_isDark")) ? ctrl.Gui._isDark : Theme.IsDarkMode()
        isEnabled := DllCall("IsWindowEnabled", "Ptr", hwnd)
        hasFocus := (DllCall("GetFocus", "Ptr") == hwnd)

        parentBgBgr := parentDark ? UIConstants.DARK_BG_BGR : UIConstants.LIGHT_BG_BGR
        hBrParent := DllCall("CreateSolidBrush", "UInt", parentBgBgr, "Ptr")
        DllCall("FillRect", "Ptr", hdcMem, "Ptr", rc, "Ptr", hBrParent)
        DllCall("DeleteObject", "Ptr", hBrParent)

        if (parentDark) {
            fillArgb := isEnabled ? 0xFF2D2D2D : 0xFF242424
            strokeArgb := hasFocus ? 0xFF505050 : (isEnabled ? 0xFF3D3D3D : 0xFF303030)
            accArgb := hasFocus ? 0xFF60CDFF : (isEnabled ? 0xFF686868 : 0)
            txtBgr := isEnabled ? UIConstants.DARK_TEXT_BGR : UIConstants.DARK_TEXT_DISABLED_BGR
        } else {
            fillArgb := isEnabled ? 0xFFFBFBFB : 0xFFF0F0F0
            strokeArgb := hasFocus ? 0xFFD0D0D0 : (isEnabled ? 0xFFE0E0E0 : 0xFFE8E8E8)
            accArgb := hasFocus ? 0xFF0067C0 : (isEnabled ? 0xFF8A8A8A : 0)
            txtBgr := isEnabled ? UIConstants.LIGHT_TEXT_BGR : UIConstants.LIGHT_TEXT_DISABLED_BGR
        }

        pGraphics := 0
        DllCall("gdiplus\GdipCreateFromHDC", "Ptr", hdcMem, "Ptr*", &pGraphics)
        if (pGraphics) {
            DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", pGraphics, "Int", 4)
            DrawFluentRoundedBox(pGraphics, 0, 0, w, h, UIConstants.FLUENT_CORNER_RADIUS, fillArgb, strokeArgb, accArgb)
            DllCall("gdiplus\GdipDeleteGraphics", "Ptr", pGraphics)
        }

        dispTxt := IsObject(ctrl) ? FormatHkDisplayText(ctrl.Value) : "None"
        hFont := Theme.GetFont(hwnd, false)
        DrawFluentControlText(hdcMem, dispTxt, 8, 0, w - 16, h - 2, hFont, txtBgr, 0x0024)

        DllCall("BitBlt", "Ptr", hdc, "Int", 0, "Int", 0, "Int", w, "Int", h, "Ptr", hdcMem, "Int", 0, "Int", 0, "UInt", 0x00CC0020)
        DllCall("SelectObject", "Ptr", hdcMem, "Ptr", obm)
        DllCall("DeleteObject", "Ptr", hbm)
        DllCall("DeleteDC", "Ptr", hdcMem)
        DllCall("EndPaint", "Ptr", hwnd, "Ptr", ps)
        return 0
    }

    res := DllCall("comctl32\DefSubclassProc", "Ptr", hwnd, "UInt", uMsg, "Ptr", wParam, "Ptr", lParam, "Ptr")
    if (uMsg == 0x0007 || uMsg == 0x0008 || uMsg == 0x000A || uMsg == 0x0100 || uMsg == 0x0101 || uMsg == 0x0104 || uMsg == 0x0105 || uMsg == 0x0401)
        DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", 1)
    return res
}

TabFluentSubclassProc(hwnd, uMsg, wParam, lParam, uIdSubclass, dwRefData) {
    if (uMsg == 0x0082) { ; WM_NCDESTROY
        if Theme.TabHoverMap.Has(hwnd)
            Theme.TabHoverMap.Delete(hwnd)
        DllCall("comctl32\RemoveWindowSubclass", "Ptr", hwnd, "Ptr", uIdSubclass, "Ptr", dwRefData)
        return DllCall("comctl32\DefSubclassProc", "Ptr", hwnd, "UInt", uMsg, "Ptr", wParam, "Ptr", lParam, "Ptr")
    }
    if (uMsg == 0x0014) ; WM_ERASEBKGND
        return 1

    if (uMsg == 0x0200) { ; WM_MOUSEMOVE
        hti := Buffer(12, 0)
        mx := (lParam & 0xFFFF) - ((lParam & 0x8000) << 1)
        my := ((lParam >> 16) & 0xFFFF) - (((lParam >> 16) & 0x8000) << 1)
        NumPut("Int", mx, "Int", my, hti, 0)
        hitIdx := SendMessage(0x130D, 0, hti.Ptr, hwnd) ; TCM_HITTEST
        prevHover := Theme.TabHoverMap.Get(hwnd, -1)
        if (hitIdx != prevHover) {
            Theme.TabHoverMap[hwnd] := hitIdx
            tme := Buffer(A_PtrSize == 8 ? 24 : 16, 0)
            NumPut("UInt", tme.Size, tme, 0)
            NumPut("UInt", 0x00000002, tme, 4) ; TME_LEAVE
            NumPut("Ptr", hwnd, tme, 8)
            DllCall("TrackMouseEvent", "Ptr", tme)
            hdrRc := Buffer(16, 0)
            DllCall("GetClientRect", "Ptr", hwnd, "Ptr", hdrRc)
            NumPut("Int", Round(46 * (A_ScreenDPI / 96.0)), hdrRc, 12)
            DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", hdrRc, "Int", 0)
        }
    } else if (uMsg == 0x02A3) { ; WM_MOUSELEAVE
        if (Theme.TabHoverMap.Get(hwnd, -1) != -1) {
            Theme.TabHoverMap[hwnd] := -1
            hdrRc := Buffer(16, 0)
            DllCall("GetClientRect", "Ptr", hwnd, "Ptr", hdrRc)
            NumPut("Int", Round(46 * (A_ScreenDPI / 96.0)), hdrRc, 12)
            DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", hdrRc, "Int", 0)
        }
    }

    if (uMsg == 0x000F) { ; WM_PAINT
        ps := Buffer(72, 0)
        hdc := DllCall("BeginPaint", "Ptr", hwnd, "Ptr", ps, "Ptr")
        rc := Buffer(16, 0)
        DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rc)
        w := NumGet(rc, 8, "Int"), h := NumGet(rc, 12, "Int")

        hdcMem := DllCall("CreateCompatibleDC", "Ptr", hdc, "Ptr")
        hbm := DllCall("CreateCompatibleBitmap", "Ptr", hdc, "Int", Max(1, w), "Int", Max(1, h), "Ptr")
        obm := DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hbm, "Ptr")

        ctrl := GuiCtrlFromHwnd(hwnd)
        parentDark := (IsObject(ctrl) && IsObject(ctrl.Gui) && ctrl.Gui.HasOwnProp("_isDark")) ? ctrl.Gui._isDark : Theme.IsDarkMode()
        bgBgr := parentDark ? UIConstants.DARK_BG_BGR : UIConstants.LIGHT_BG_BGR

        hBrBg := DllCall("CreateSolidBrush", "UInt", bgBgr, "Ptr")
        DllCall("FillRect", "Ptr", hdcMem, "Ptr", rc, "Ptr", hBrBg)
        DllCall("DeleteObject", "Ptr", hBrBg)

        tabCount := SendMessage(0x1304, 0, 0, hwnd)
        curSel := SendMessage(0x130B, 0, 0, hwnd)
        hoverIdx := Theme.TabHoverMap.Get(hwnd, -1)

        itemRc := Buffer(16, 0)
        panelTop := 38
        if (tabCount > 0) {
            SendMessage(0x130A, 0, itemRc.Ptr, hwnd)
            panelTop := NumGet(itemRc, 12, "Int") + 4
        }

        cardFill := parentDark ? 0xFF2C2C2C : 0xFFFFFFFF
        cardStroke := parentDark ? 0xFF3D3D3D : 0xFFE5E5E5
        tabActiveFill := parentDark ? 0xFF2C2C2C : 0xFFFFFFFF
        tabActiveStroke := parentDark ? 0xFF454545 : 0xFFDCDCDC
        tabHoverFill := parentDark ? 0xFF282828 : 0xFFEAEAEA
        tabHoverStroke := parentDark ? 0xFF383838 : 0xFFE0E0E0
        accPillArgb := parentDark ? 0xFF60CDFF : 0xFF0067C0
        txtActiveBgr := parentDark ? UIConstants.DARK_TEXT_BGR : UIConstants.LIGHT_TEXT_BGR
        txtMutedBgr := parentDark ? UIConstants.DARK_TEXT_MUTED_BGR : UIConstants.LIGHT_TEXT_MUTED_BGR

        pGraphics := 0
        DllCall("gdiplus\GdipCreateFromHDC", "Ptr", hdcMem, "Ptr*", &pGraphics)
        if (pGraphics) {
            DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", pGraphics, "Int", 4)

            ; Draw Windows 11 Explorer rounded card body
            DrawFluentRoundedBox(pGraphics, 0, panelTop, w, h - panelTop, UIConstants.FLUENT_CARD_RADIUS, cardFill, cardStroke)

            Loop tabCount {
                idx := A_Index - 1
                SendMessage(0x130A, idx, itemRc.Ptr, hwnd)
                tx := NumGet(itemRc, 0, "Int") + 2
                ty := NumGet(itemRc, 4, "Int") + 1
                tw := (NumGet(itemRc, 8, "Int") - NumGet(itemRc, 0, "Int")) - 4
                th := (NumGet(itemRc, 12, "Int") - NumGet(itemRc, 4, "Int")) - 2
                isSel := (idx == curSel)

                if (isSel) {
                    DrawFluentRoundedBox(pGraphics, tx, ty, tw, th, UIConstants.FLUENT_CORNER_RADIUS, tabActiveFill, tabActiveStroke)
                    pillW := Max(20, Round(tw * 0.42))
                    pillX := tx + Round((tw - pillW) / 2)
                    pPill := Gdip.CreateRoundedRectPath(pillX, ty + th - 3.0, pillW, 3.0, 1.5)
                    if (pPill) {
                        pPillBr := 0
                        DllCall("gdiplus\GdipCreateSolidFill", "UInt", accPillArgb, "Ptr*", &pPillBr)
                        if (pPillBr) {
                            DllCall("gdiplus\GdipFillPath", "Ptr", pGraphics, "Ptr", pPillBr, "Ptr", pPill)
                            DllCall("gdiplus\GdipDeleteBrush", "Ptr", pPillBr)
                        }
                        DllCall("gdiplus\GdipDeletePath", "Ptr", pPill)
                    }
                } else if (idx == hoverIdx) {
                    DrawFluentRoundedBox(pGraphics, tx, ty, tw, th, UIConstants.FLUENT_CORNER_RADIUS, tabHoverFill, tabHoverStroke)
                }
            }

            DllCall("gdiplus\GdipDeleteGraphics", "Ptr", pGraphics)
        }

        tabNames := (IsObject(ctrl) && ctrl.HasOwnProp("_tabNames")) ? ctrl._tabNames : []
        hFontReg := Theme.GetFont(hwnd, false)
        hFontBold := Theme.GetFont(hwnd, true)
        Loop tabCount {
            idx := A_Index - 1
            SendMessage(0x130A, idx, itemRc.Ptr, hwnd)
            tx := NumGet(itemRc, 0, "Int") + 2
            ty := NumGet(itemRc, 4, "Int") + 1
            tw := (NumGet(itemRc, 8, "Int") - NumGet(itemRc, 0, "Int")) - 4
            th := (NumGet(itemRc, 12, "Int") - NumGet(itemRc, 4, "Int")) - 2
            isSel := (idx == curSel)
            lbl := (idx + 1 <= tabNames.Length) ? tabNames[idx + 1] : ("Tab " (idx + 1))
            DrawFluentControlText(hdcMem, lbl, tx + 2, ty, tw - 4, th - 1, isSel ? hFontBold : hFontReg, isSel ? txtActiveBgr : txtMutedBgr, 0x0025)
        }

        DllCall("BitBlt", "Ptr", hdc, "Int", 0, "Int", 0, "Int", w, "Int", h, "Ptr", hdcMem, "Int", 0, "Int", 0, "UInt", 0x00CC0020)
        DllCall("SelectObject", "Ptr", hdcMem, "Ptr", obm)
        DllCall("DeleteObject", "Ptr", hbm)
        DllCall("DeleteDC", "Ptr", hdcMem)
        DllCall("EndPaint", "Ptr", hwnd, "Ptr", ps)
        return 0
    }

    res := DllCall("comctl32\DefSubclassProc", "Ptr", hwnd, "UInt", uMsg, "Ptr", wParam, "Ptr", lParam, "Ptr")
    if (uMsg == 0x0201 || uMsg == 0x130C) {
        parentHwnd := DllCall("GetParent", "Ptr", hwnd, "Ptr")
        DllCall("RedrawWindow", "Ptr", parentHwnd ? parentHwnd : hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x0185)
    }
    return res
}

StaticFluentSubclassProc(hwnd, uMsg, wParam, lParam, uIdSubclass, dwRefData) {
    if (uMsg == 0x0082) { ; WM_NCDESTROY
        DllCall("comctl32\RemoveWindowSubclass", "Ptr", hwnd, "Ptr", uIdSubclass, "Ptr", dwRefData)
        return DllCall("comctl32\DefSubclassProc", "Ptr", hwnd, "UInt", uMsg, "Ptr", wParam, "Ptr", lParam, "Ptr")
    }
    if (uMsg == 0x000F && !DllCall("IsWindowEnabled", "Ptr", hwnd)) {
        ps := Buffer(72, 0)
        hdc := DllCall("BeginPaint", "Ptr", hwnd, "Ptr", ps, "Ptr")
        rc := Buffer(16, 0)
        DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rc)
        ctrl := GuiCtrlFromHwnd(hwnd)
        parentDark := (IsObject(ctrl) && IsObject(ctrl.Gui) && ctrl.Gui.HasOwnProp("_isDark")) ? ctrl.Gui._isDark : Theme.IsDarkMode()
        role := (IsObject(ctrl) && ctrl.HasOwnProp("_themeRole")) ? ctrl._themeRole : ""
        inTab := (role = "tabText" || role = "tabMuted")
        bgBgr := parentDark ? (inTab ? UIConstants.DARK_SURFACE_BGR : UIConstants.DARK_BG_BGR) : (inTab ? UIConstants.LIGHT_SURFACE_BGR : UIConstants.LIGHT_BG_BGR)
        hBrBg := DllCall("CreateSolidBrush", "UInt", bgBgr, "Ptr")
        DllCall("FillRect", "Ptr", hdc, "Ptr", rc, "Ptr", hBrBg)
        DllCall("DeleteObject", "Ptr", hBrBg)
        txt := IsObject(ctrl) ? ctrl.Text : ""
        style := DllCall("GetWindowLong", "Ptr", hwnd, "Int", -16, "Int")
        dtFlags := ((style & 0x0200) ? 0x0024 : 0x0010) | ((style & 0x01) ? 0x01 : ((style & 0x02) ? 0x02 : 0x00))
        if (style & 0x0080)
            dtFlags |= 0x0800
        hFont := SendMessage(0x0031, 0, 0, hwnd)
        oldFont := hFont ? DllCall("SelectObject", "Ptr", hdc, "Ptr", hFont, "Ptr") : 0
        DllCall("SetBkMode", "Ptr", hdc, "Int", 1)
        DllCall("SetTextColor", "Ptr", hdc, "UInt", parentDark ? UIConstants.DARK_TEXT_DISABLED_BGR : UIConstants.LIGHT_TEXT_DISABLED_BGR)
        DllCall("DrawTextW", "Ptr", hdc, "WStr", txt, "Int", -1, "Ptr", rc, "UInt", dtFlags)
        if (oldFont)
            DllCall("SelectObject", "Ptr", hdc, "Ptr", oldFont, "Ptr")
        DllCall("EndPaint", "Ptr", hwnd, "Ptr", ps)
        return 0
    }
    res := DllCall("comctl32\DefSubclassProc", "Ptr", hwnd, "UInt", uMsg, "Ptr", wParam, "Ptr", lParam, "Ptr")
    if (uMsg == 0x000A) ; WM_ENABLE
        DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", 1)
    return res
}

class Config {
    ConfigFile := ""
    AudioRoutingMode := 0
    ObsMuteHotkey := "None"
    ObsRecHotkey := "^F9"
    ObsPauseHotkey := "^F10"
    ZoomMuteHotkey := "!a"
    ZoomRecHotkey := "!r"
    ZoomPauseHotkey := "!p"
    obsPassword := ""
    targetMicName := "Mic/Aux"

    EnablePPT := false
    EnableMicOnly := false
    EnableWS := false
    EnableZoom := false

    ShowIndicator := true
    ShowExtraHuds := true
    ThemeMode := "System"
    ShowText := false
    MonoIcon := false
    SleekCorners := false
    AggressivePulse := false
    OpacityLevel := 220
    IndicatorScale := 1.0
    FirstRun := true
    IsMuted := false

    CatchArrows := true
    CatchPg := true
    CatchSpace := true
    CatchEnter := true
    CatchTab := true
    CatchEsc := true

    PptHotkey := "^F12"
    WsHotkey := "!F12"
    ZoomHotkey := "^!F12"
    IndHotkey := "^+F12"
    ExitHotkey := "!+F12"
    SuspendHotkey := "^!+F12"
    HwMuteHotkey := "b"

    savedX := "Default"
    savedY := "Default"

    __New(filePath := "") {
        this.ConfigFile := (filePath != "") ? filePath : A_ScriptDir "\MicOverlay_Config.ini"
        this.Load()
    }

    Read(section, key, defaultVal := "") {
        return IniRead(this.ConfigFile, section, key, defaultVal)
    }

    Write(section, key, val) {
        IniWrite(val, this.ConfigFile, section, key)
    }

    ReadBool(section, key, defaultValue := 0) {
        value := IniRead(this.ConfigFile, section, key, defaultValue)
        switch (StrLower(String(value))) {
            case "1", "true", "yes", "on":
                return true
            case "0", "false", "no", "off", "":
                return false
            default:
                try return !!Integer(value)
                catch
                    return !!defaultValue
        }
    }

    ReadInt(section, key, defaultValue := 0) {
        value := IniRead(this.ConfigFile, section, key, defaultValue)
        try return Integer(value)
        catch
            return defaultValue
    }

    ReadFloat(section, key, defaultValue := 1.0) {
        value := IniRead(this.ConfigFile, section, key, defaultValue)
        try return Float(value)
        catch
            return defaultValue
    }

    WriteBool(section, key, value) {
        IniWrite(value ? 1 : 0, this.ConfigFile, section, key)
    }

    Load() {
        this.AudioRoutingMode := this.ReadInt("Settings", "AudioRoutingMode", 0)
        if (this.AudioRoutingMode < 0 || this.AudioRoutingMode > 3)
            this.AudioRoutingMode := 0
        this.ObsMuteHotkey := this.Read("Settings", "ObsHotkey", "None")
        this.ObsRecHotkey := this.Read("Settings", "ObsRecHotkey", "")
        if (this.ObsRecHotkey = "") {
            this.ObsRecHotkey := "^F9"
            this.Write("Settings", "ObsRecHotkey", this.ObsRecHotkey)
        }
        this.ObsPauseHotkey := this.Read("Settings", "ObsPauseHotkey", "")
        if (this.ObsPauseHotkey = "") {
            this.ObsPauseHotkey := "^F10"
            this.Write("Settings", "ObsPauseHotkey", this.ObsPauseHotkey)
        }
        this.ZoomMuteHotkey := this.Read("Settings", "ZoomMuteHotkey", "!a")
        this.ZoomRecHotkey := this.Read("Settings", "ZoomRecHotkey", "")
        if (this.ZoomRecHotkey = "") {
            this.ZoomRecHotkey := "!r"
            this.Write("Settings", "ZoomRecHotkey", this.ZoomRecHotkey)
        }
        this.ZoomPauseHotkey := this.Read("Settings", "ZoomPauseHotkey", "")
        if (this.ZoomPauseHotkey = "") {
            this.ZoomPauseHotkey := "!p"
            this.Write("Settings", "ZoomPauseHotkey", this.ZoomPauseHotkey)
        }
        this.obsPassword := this.Read("Settings", "ObsPassword", "")
        this.targetMicName := this.Read("Settings", "TargetMicName", "Mic/Aux")

        this.EnablePPT := this.ReadBool("Settings", "EnablePPT")
        this.EnableMicOnly := this.ReadBool("Settings", "EnableMicOnly")
        if (this.EnablePPT && this.EnableMicOnly) {
            this.EnableMicOnly := false
            this.WriteBool("Settings", "EnableMicOnly", false)
        }
        this.EnableWS := this.ReadBool("Settings", "EnableWS")
        this.EnableZoom := this.ReadBool("Settings", "EnableZoom")

        if (this.EnableWS && this.EnableZoom) {
            this.EnableZoom := false
            this.WriteBool("Settings", "EnableZoom", false)
        }

        this.ShowIndicator := this.ReadBool("Settings", "ShowIndicator", true)
        this.ShowExtraHuds := this.ReadBool("Settings", "ShowExtraHuds", true)
        rawTheme := StrLower(Trim(this.Read("Settings", "ThemeMode", "System")))
        this.ThemeMode := (rawTheme = "dark") ? "Dark" : ((rawTheme = "light") ? "Light" : "System")
        Theme.SetMode(this.ThemeMode)
        this.ShowText := this.ReadBool("Settings", "ShowText")
        this.MonoIcon := this.ReadBool("Settings", "MonoIcon")
        this.SleekCorners := this.ReadBool("Settings", "SleekCorners")
        this.AggressivePulse := this.ReadBool("Settings", "AggressivePulse")
        this.OpacityLevel := this.ReadInt("Settings", "OpacityLevel", UIConstants.OPACITY_FROSTED)
        if (this.OpacityLevel < 1 || this.OpacityLevel > 255)
            this.OpacityLevel := UIConstants.OPACITY_FROSTED
        this.IndicatorScale := this.ReadFloat("Settings", "IndicatorScale", 1.0)
        if (this.IndicatorScale <= 0.0 || this.IndicatorScale > 10.0)
            this.IndicatorScale := 1.0
        this.FirstRun := this.ReadBool("Settings", "FirstRun", true)
        this.IsMuted := this.ReadBool("Settings", "IsMuted", false)

        this.CatchArrows := this.ReadBool("Pointer", "CatchArrows", true)
        this.CatchPg := this.ReadBool("Pointer", "CatchPg", true)
        this.CatchSpace := this.ReadBool("Pointer", "CatchSpace", true)
        this.CatchEnter := this.ReadBool("Pointer", "CatchEnter", true)
        this.CatchTab := this.ReadBool("Pointer", "CatchTab", true)
        this.CatchEsc := this.ReadBool("Pointer", "CatchEsc", true)

        this.PptHotkey := this.Read("Settings", "PptHotkey", "^F12")
        this.WsHotkey := this.Read("Settings", "WsHotkey", "!F12")
        this.ZoomHotkey := this.Read("Settings", "ZoomHotkey", "^!F12")
        this.IndHotkey := this.Read("Settings", "IndHotkey", "^+F12")
        this.ExitHotkey := this.Read("Settings", "ExitHotkey", "!+F12")
        this.SuspendHotkey := this.Read("Settings", "SuspendHotkey", "^!+F12")
        this.HwMuteHotkey := this.Read("Settings", "HwMuteHotkey", "b")

        this.savedX := this.Read("Position", "X", "Default")
        this.savedY := this.Read("Position", "Y", "Default")
    }

    ResetAppearance() {
        this.ShowExtraHuds := true
        this.ThemeMode := "System"
        this.ShowText := false
        this.MonoIcon := false
        this.SleekCorners := false
        this.AggressivePulse := false
        this.OpacityLevel := UIConstants.OPACITY_FROSTED
        this.IndicatorScale := 1.0
        this.Write("Settings", "ShowExtraHuds", 1)
        this.Write("Settings", "ThemeMode", "System")
        this.Write("Settings", "ShowText", 0)
        this.Write("Settings", "MonoIcon", 0)
        this.Write("Settings", "SleekCorners", 0)
        this.Write("Settings", "AggressivePulse", 0)
        this.Write("Settings", "OpacityLevel", UIConstants.OPACITY_FROSTED)
        this.Write("Settings", "IndicatorScale", 1.0)
        Theme.SetMode("System")
    }

    ResetPosition() {
        this.savedX := "Default"
        this.savedY := "Default"
        this.Write("Position", "X", "Default")
        this.Write("Position", "Y", "Default")
    }

    DeleteFile() {
        if FileExist(this.ConfigFile)
            FileDelete(this.ConfigFile)
    }
}

class OverlayState {
    obsWs := ""
    obsConnected := false
    zoomConnected := false
    IsSyncing := false
    zoomLastMuted := -1
    zoomRecGraceUntil := 0
    zoomSawRecControl := false

    isMuted := false
    recState := 0
    studioModeActive := false
    currentSceneName := "Scene"
    unreadChatCount := 0

    baseAlpha := 220
    currentAlpha := 220
    breathDir := -5
    animSeq := 0

    isDraggingHud := false
    activeDragHwnd := 0

    dragTimerFn := ""
    breathTimerFn := ""
    obsTimerFn := ""
    zoomTimerFn := ""
    releaseSyncTimerFn := ""
    rebuildTrayFn := ""
    refreshHelpFn := ""

    MicGui := ""
    RecGui := ""
    ChatGui := ""
    StudioGui := ""
    SceneGui := ""

    IconFont := ""

    baseWidth := 80
    baseHeight := 40
    hudGap := 6
    recHeight := 34
    recW := 40
    chatW := 34
    row3Height := 30
    studioW := 28
    sceneW := 46
    iconSize := 18
    textSize := 13
    subIconSize := 12
    subTextSize := 9
    miniTextSize := 9
    savedX := 0
    savedY := 0

    colors := {
        live: UIConstants.COLOR_LIVE,
        muted: UIConstants.COLOR_MUTED,
        borderLive: UIConstants.BORDER_LIVE,
        borderMuted: UIConstants.BORDER_MUTED,
        iconLive: UIConstants.ICON_LIVE,
        iconMuted: UIConstants.ICON_MUTED,
        recOff: UIConstants.COLOR_REC_OFF,
        recBorderOff: UIConstants.BORDER_REC_OFF,
        recIconOff: UIConstants.ICON_REC_OFF,
        recActive: UIConstants.COLOR_REC_ACTIVE,
        recBorderActive: UIConstants.BORDER_REC_ACTIVE,
        recIconActive: UIConstants.ICON_REC_ACTIVE,
        recPaused: UIConstants.COLOR_REC_PAUSED,
        recBorderPaused: UIConstants.BORDER_REC_PAUSED,
        recIconPaused: UIConstants.ICON_REC_PAUSED,
        studioOff: UIConstants.COLOR_STUDIO_OFF,
        studioBorderOff: UIConstants.BORDER_STUDIO_OFF,
        studioIconOff: UIConstants.ICON_STUDIO_OFF,
        studioOn: UIConstants.COLOR_STUDIO_ON,
        studioBorderOn: UIConstants.BORDER_STUDIO_ON,
        studioIconOn: UIConstants.ICON_STUDIO_ON,
        scene: UIConstants.COLOR_SCENE,
        sceneBorder: UIConstants.BORDER_SCENE,
        chatClear: UIConstants.COLOR_CHAT_CLEAR,
        chatBorderClear: UIConstants.BORDER_CHAT_CLEAR,
        chatIconClear: UIConstants.ICON_CHAT_CLEAR,
        chatAlert: UIConstants.COLOR_CHAT_ALERT,
        chatBorderAlert: UIConstants.BORDER_CHAT_ALERT,
        chatIconAlert: UIConstants.ICON_CHAT_ALERT
    }

    __New(cfg) {
        this.isMuted := cfg.IsMuted
        this.baseAlpha := cfg.OpacityLevel
        this.currentAlpha := cfg.OpacityLevel
        this.breathDir := cfg.AggressivePulse ? -UIConstants.PULSE_STEP_AGGRESSIVE : -UIConstants.PULSE_STEP_NORMAL

        osBuild := Integer(StrSplit(A_OSVersion, ".")[3])
        this.IconFont := (osBuild >= 22000) ? "Segoe Fluent Icons" : "Segoe MDL2 Assets"

        this.dragTimerFn := DragSyncTick.Bind(this)
        this.breathTimerFn := BreathingAnimation.Bind(cfg, this)
        this.obsTimerFn := ConnectToOBS.Bind(cfg, this)
        this.zoomTimerFn := ZoomStateMonitor.Bind(cfg, this)
        this.releaseSyncTimerFn := ReleaseSyncLock.Bind(this)

        this.ComputeDimensions(cfg)
    }

    ComputeDimensions(cfg) {
        this.baseWidth := Round((cfg.ShowText ? UIConstants.BASE_WIDTH_TEXT : UIConstants.BASE_WIDTH_ICON) * cfg.IndicatorScale)
        this.baseHeight := Round(UIConstants.BASE_HEIGHT * cfg.IndicatorScale)
        this.hudGap := Max(UIConstants.MIN_HUD_GAP, Round(UIConstants.HUD_GAP * cfg.IndicatorScale))
        this.recHeight := Round(UIConstants.REC_HEIGHT * cfg.IndicatorScale)
        this.recW := Round((this.baseWidth - this.hudGap) * UIConstants.REC_WIDTH_RATIO)
        this.chatW := this.baseWidth - this.hudGap - this.recW
        this.row3Height := Round(UIConstants.ROW3_HEIGHT * cfg.IndicatorScale)

        this.iconSize := Max(1, Round(UIConstants.MIC_ICON_SIZE * cfg.IndicatorScale))
        this.textSize := Max(1, Round(UIConstants.MIC_TEXT_SIZE * cfg.IndicatorScale))
        this.subIconSize := Max(1, Round(UIConstants.SUB_ICON_SIZE * cfg.IndicatorScale))
        this.subTextSize := Max(1, Round(UIConstants.SUB_TEXT_SIZE * cfg.IndicatorScale))
        this.miniTextSize := Max(1, Round(UIConstants.MINI_TEXT_SIZE * cfg.IndicatorScale))

        minStudioW := Round((this.baseWidth - this.hudGap) * UIConstants.STUDIO_WIDTH_RATIO)
        if (cfg.ShowText) {
            stIconW := Round(UIConstants.STUDIO_ICON_W * cfg.IndicatorScale)
            stIconX := Round(UIConstants.STUDIO_ICON_X * cfg.IndicatorScale)
            stTextSize := Max(1, Round(UIConstants.STUDIO_TEXT_SIZE * cfg.IndicatorScale))
            reqStudioW := stIconX + stIconW + Gdip.MeasureTextWidth("STUDIO", "Segoe UI", stTextSize, 1) + Round(2 * UIConstants.LABEL_GAP_X * cfg.IndicatorScale)
            this.studioW := Max(minStudioW, reqStudioW)
        } else {
            this.studioW := minStudioW
        }

        minSceneW := Max(UIConstants.MIN_TEXT_WIDTH, this.baseWidth - this.hudGap - this.studioW)
        scPad := Round(UIConstants.SCENE_PAD_X * cfg.IndicatorScale)
        reqSceneW := Gdip.MeasureTextWidth(this.currentSceneName, "Segoe UI", this.miniTextSize, 1) + (2 * scPad) + Round(4 * cfg.IndicatorScale)
        this.sceneW := Max(minSceneW, reqSceneW)

        extraRow2 := (cfg.ShowExtraHuds && (cfg.EnableWS || cfg.EnableZoom))
        extraRow3 := (cfg.ShowExtraHuds && cfg.EnableWS)
        maxRowW := this.baseWidth
        if (extraRow2)
            maxRowW := Max(maxRowW, this.recW + this.hudGap + this.chatW)
        if (extraRow3)
            maxRowW := Max(maxRowW, this.studioW + this.hudGap + this.sceneW)
        extraTopPad := (extraRow2 ? (this.recHeight + this.hudGap) : 0) + (extraRow3 ? (this.row3Height + this.hudGap) : 0)

        rawX := cfg.savedX
        rawY := cfg.savedY
        if (rawX = "Default" || rawY = "Default" || !IsInteger(rawX) || !IsInteger(rawY)) {
            MonitorGetWorkArea(1, &Left, &Top, &Right, &Bottom)
            stackTopPad := UIConstants.SCREEN_MIN_PAD + extraTopPad
            this.savedX := Max(Left + UIConstants.SCREEN_MIN_PAD, Right - maxRowW - UIConstants.SCREEN_MARGIN_X)
            this.savedY := Max(Top + stackTopPad, Bottom - this.baseHeight - UIConstants.SCREEN_MARGIN_Y)
        } else {
            sx := Integer(rawX)
            sy := Integer(rawY)
            vLeft := SysGet(76), vTop := SysGet(77)
            vRight := vLeft + SysGet(78), vBottom := vTop + SysGet(79)
            this.savedX := Max(vLeft, Min(sx, vRight - maxRowW))
            this.savedY := Max(vTop + extraTopPad, Min(sy, vBottom - this.baseHeight))
        }
    }
}

SetTrayCheck(itemText, enabled) {
    if (enabled)
        A_TrayMenu.Check(itemText)
    else
        A_TrayMenu.Uncheck(itemText)
}

; --- SETUP & SETTINGS GUIS ---
BuildSettingsWindow(title, elementsArray, onSave := "", options := "") {
    opts := IsObject(options) ? options : {}
    doSuspend := opts.HasOwnProp("suspend") ? opts.suspend : true
    doShow := opts.HasOwnProp("show") ? opts.show : true
    doWaitClose := opts.HasOwnProp("waitClose") ? opts.waitClose : false

    if (doShow) {
        existing := Theme.FocusExistingWindow(title)
        if IsObject(existing)
            return existing
    }

    if (doSuspend)
        Theme.AcquireSuspend()

    dlg := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", title)
    dlg._closed := false
    Theme.ApplyToWindow(dlg)
    if (doShow)
        Theme.NamedWindows[title] := dlg

    ReleaseDialogState(*) {
        if (dlg._closed)
            return
        dlg._closed := true
        Theme.UnregisterWindow(dlg, title)
        if (doSuspend)
            Theme.ReleaseSuspend()
    }
    dlg._releaseState := ReleaseDialogState

    CloseHandler(*) {
        ReleaseDialogState()
        if (opts.HasOwnProp("onClose") && opts.onClose) {
            opts.onClose.Call(dlg)
        } else {
            dlg.Destroy()
        }
    }
    dlg.OnEvent("Close", CloseHandler)
    dlg.OnEvent("Escape", CloseHandler)

    ctrls := Map()
    trackedElements := []

    HandleSave(*) {
        for el in trackedElements {
            if (el.HasOwnProp("required") && el.required && ctrls[el.id].Value = "") {
                dlg.Opt("+OwnDialogs")
                errTitle := el.HasOwnProp("errorTitle") ? el.errorTitle : "Error"
                errMsg := el.HasOwnProp("errorMsg") ? el.errorMsg : "Shortcuts cannot be left blank."
                MsgBox(errMsg, errTitle, "Icon!")
                return false
            }
        }
        values := Map()
        for el in trackedElements {
            values[el.id] := ctrls[el.id].Value
        }
        if (onSave != "")
            onSave(values, ctrls, dlg)
        return true
    }

    for el in elementsArray {
        t := el.type
        cOpts := el.HasOwnProp("opts") ? el.opts : ""
        val := el.HasOwnProp("value") ? el.value : ""
        txt := el.HasOwnProp("text") ? el.text : ""
        role := el.HasOwnProp("role") ? el.role : ""

        if (t = "DropDownList") {
            ctrl := dlg.Add("DropDownList", cOpts, el.items)
        } else if (t = "Checkbox") {
            chkOpt := (val != "") ? (" Checked" val) : ""
            ctrl := dlg.Add("Checkbox", cOpts chkOpt, txt)
        } else if (t = "Text" || t = "Button") {
            ctrl := dlg.Add(t, cOpts, txt)
        } else {
            ctrl := dlg.Add(t, cOpts, val)
        }

        Theme.RegisterControl(dlg, ctrl, t, role)

        if (el.HasOwnProp("id") && el.id != "") {
            ctrls[el.id] := ctrl
            if (t != "Text" && t != "Button")
                trackedElements.Push(el)
        }
        if (el.HasOwnProp("onChange") && el.onChange)
            ctrl.OnEvent("Change", el.onChange.Bind(ctrls, dlg))
        if (t = "Button" && el.HasOwnProp("isSave") && el.isSave)
            ctrl.OnEvent("Click", HandleSave)
    }

    if (opts.HasOwnProp("saveBtnText") && opts.saveBtnText != "") {
        saveBtnOpts := opts.HasOwnProp("saveBtnOpts") ? opts.saveBtnOpts : "w280 h32 Default y+15"
        dlg.SetFont("s10 w400 norm", Theme.UiFont)
        saveBtn := dlg.Add("Button", saveBtnOpts, opts.saveBtnText)
        Theme.RegisterControl(dlg, saveBtn, "Button")
        saveBtn.OnEvent("Click", HandleSave)
    }

    dlg._ctrls := ctrls
    dlg._triggerSave := HandleSave

    if (opts.HasOwnProp("onInit") && opts.onInit)
        opts.onInit.Call(ctrls, dlg)

    if (doShow) {
        dlgHwnd := dlg.Hwnd
        dlg.Show()
        if (doWaitClose)
            WinWaitClose("ahk_id " dlgHwnd)
    }
    return dlg
}

PromptForSetup(cfg, isInitialBoot := false) {
    modes := [
        "1: Pro OBS Setup (VB-Cable)",
        "2: Standard Direct Mic (Zoom-Only)",
        "3: Dual App Sync (OBS + Zoom Direct)"
    ]
    initialMode := (cfg.AudioRoutingMode >= 1 && cfg.AudioRoutingMode <= 3) ? cfg.AudioRoutingMode : 1
    obsVal := (cfg.ObsMuteHotkey != "None") ? cfg.ObsMuteHotkey : ""
    zoomVal := (cfg.ZoomMuteHotkey != "") ? cfg.ZoomMuteHotkey : "!a"

    UpdateFieldStates(ctrls, dlg, *) {
        sel := ctrls["mode"].Value
        obsEnabled := (sel == 1 || sel == 3)
        zoomEnabled := (sel == 2 || sel == 3)
        ctrls["obsLbl"].Enabled := obsEnabled
        ctrls["obsHotkey"].Enabled := obsEnabled
        ctrls["zoomLbl"].Enabled := zoomEnabled
        ctrls["zoomHotkey"].Enabled := zoomEnabled
    }

    SaveSetup(values, ctrls, dlg) {
        sel := values["mode"]
        if (!cfg.EnableWS && (sel == 1 || sel == 3) && values["obsHotkey"] = "") {
            dlg.Opt("+OwnDialogs")
            MsgBox("Please enter your OBS Mute shortcut.", "Setup", "Icon!")
            return
        }
        if ((sel == 2 || sel == 3) && values["zoomHotkey"] = "") {
            dlg.Opt("+OwnDialogs")
            MsgBox("Please enter your Zoom Mute shortcut.", "Setup", "Icon!")
            return
        }

        cfg.AudioRoutingMode := sel
        cfg.Write("Settings", "AudioRoutingMode", cfg.AudioRoutingMode)

        if (sel == 1 || sel == 3) {
            cfg.ObsMuteHotkey := (values["obsHotkey"] != "") ? values["obsHotkey"] : "None"
            cfg.Write("Settings", "ObsHotkey", cfg.ObsMuteHotkey)
        }
        if (sel == 2 || sel == 3) {
            cfg.ZoomMuteHotkey := values["zoomHotkey"]
            cfg.Write("Settings", "ZoomMuteHotkey", cfg.ZoomMuteHotkey)
        }

        if dlg.HasOwnProp("_releaseState")
            dlg._releaseState.Call()
        dlg.Destroy()
        if (!isInitialBoot)
            Reload()
    }

    elements := [
        {type: "Text", opts: "w280", text: "Select your Audio Routing Profile:"},
        {type: "DropDownList", id: "mode", opts: "w280 Choose" initialMode, items: modes, onChange: UpdateFieldStates},
        {type: "Text", id: "obsLbl", opts: "w280 y+15", text: "OBS Mute Shortcut:"},
        {type: "Hotkey", id: "obsHotkey", opts: "w280", value: obsVal},
        {type: "Text", id: "zoomLbl", opts: "w280 y+10", text: "Zoom Mute Shortcut (Default Alt+A):"},
        {type: "Hotkey", id: "zoomHotkey", opts: "w280", value: zoomVal}
    ]

    BuildSettingsWindow("PresenterSync Audio Setup", elements, SaveSetup, {
        suspend: true,
        waitClose: true,
        onClose: isInitialBoot ? ((*) => ExitApp()) : ((dlg) => dlg.Destroy()),
        onInit: UpdateFieldStates,
        saveBtnText: isInitialBoot ? "Save & Start" : "Save & Restart",
        saveBtnOpts: "w280 h32 Default y+15"
    })
}

PromptForPassword(promptText := "Enter your OBS WebSocket Password:") {
    savedPw := ""

    SavePw(values, ctrls, dlg) {
        savedPw := values["password"]
        if dlg.HasOwnProp("_releaseState")
            dlg._releaseState.Call()
        dlg.Destroy()
    }

    elements := [
        {type: "Text", opts: "w250", text: promptText},
        {type: "Edit", id: "password", opts: "w250 Password", required: true, errorTitle: "Setup", errorMsg: "Password cannot be empty."}
    ]

    BuildSettingsWindow("WebSocket Setup", elements, SavePw, {
        suspend: true,
        waitClose: true,
        onClose: (dlg) => dlg.Destroy(),
        saveBtnText: "Save & Connect",
        saveBtnOpts: "w250 h32 Default y+15"
    })
    return savedPw
}

FormatHK(hk) {
    return FormatHkDisplayText(hk)
}

GetRoutingModeLabel(mode) {
    if (mode == 1)
        return "Mode 1: Pro OBS Setup (VB-Cable)"
    if (mode == 2)
        return "Mode 2: Standard Direct Mic (Zoom-Only)"
    if (mode == 3)
        return "Mode 3: Dual App Sync (OBS + Zoom)"
    return "Unconfigured"
}

GetRemoteSetupGuideText() {
    return "1. ENABLE OBS WEBSOCKET v5 ON HOST PC`r`n"
        . "- Open OBS Studio -> Tools -> WebSocket Server Settings.`r`n"
        . "- Check 'Enable WebSocket server' and keep Server Port at 4455.`r`n"
        . "- Check 'Enable Authentication', set or copy your password, and click Apply.`r`n"
        . "- If Windows Firewall prompts, allow Private networks (TCP port 4455 inbound).`r`n`r`n"
        . "2. COPY CONNECTION DETAILS FROM PRIMARY HOST`r`n"
        . "- Right-click the PresenterSync tray icon (or any HUD pill) and open Settings -> Remote Companion Info....`r`n"
        . "- Click 'Copy Universal String to Clipboard'. This includes your host's .local mDNS name plus active Ethernet / Wi-Fi IPs (for example: STUDIO-PC.local, 192.168.1.50, 192.168.1.125).`r`n`r`n"
        . "3. CONNECT PRESENTER SYNC REMOTE (SMART BOARD / 2ND PC)`r`n"
        . "- Copy PresenterSync_Remote.exe to the Smart Board (or run PresenterSync_Remote.ahk).`r`n"
        . "- Paste the Universal String into Host Address (comma-separated candidates trigger fast 2s auto-failover across LAN interfaces).`r`n"
        . "- Keep Port = 4455, enter your OBS WebSocket Password, and match Exact Audio Source Name (default: Mic/Aux, case-sensitive in OBS Audio Mixer).`r`n"
        . "- Click 'Test Connection' to verify LAN reachability and authentication, then click Connect & Start.`r`n`r`n"
        . "4. CLICKER CONTROL, HUD FEEDBACK & TROUBLESHOOTING`r`n"
        . "- Clicker Mute: Press your presenter mute key (default: b) to toggle OBS mic in <5 ms. A 150ms debounce shield prevents double toggles, and interception automatically pauses while typing inside Remote dialogs.`r`n"
        . "- HUD Feedback: Left-drag the Remote pill to reposition; right-click for the menu. The pill dims automatically while disconnected and pulses gently when OBS mic is muted.`r`n"
        . "- Searching for OBS Host: Verify both devices share the same network/subnet, OBS WebSocket server is enabled, and Windows Firewall allows TCP port 4455.`r`n"
        . "- Auth Failed (OBS Code 4009): Check the password in Change OBS Connection... (auto-retry pauses so OBS won't be flooded).`r`n"
        . "- Connected (Mic Not Found): Match exact spelling and casing of Audio Source Name in OBS Audio Mixer.`r`n"
        . "- Keep-Alive: Remote sends a GetVersion heartbeat every 30s to prevent Wi-Fi sleep drops."
}

BuildLiveStatusInfo(cfg, state := "") {
    ptrMode := cfg.EnablePPT ? "Full PPT + Mute" : (cfg.EnableMicOnly ? "Pointer Mute Only" : "OFF")
    syncMode := cfg.EnableWS ? "OBS WebSocket v5" : (cfg.EnableZoom ? "Zoom UIA Monitoring" : "Basic (1-Tier Mic Only)")
    connInfo := ""
    if IsObject(state) {
        if (cfg.EnableWS)
            connInfo := state.obsConnected ? " (Connected - Scene: " state.currentSceneName ")" : " (Waiting for OBS...)"
        else if (cfg.EnableZoom)
            connInfo := state.zoomConnected ? " (Active Meeting Detected)" : " (Waiting for Zoom Meeting...)"
    }
    hudStatus := (cfg.ShowIndicator ? "Visible" : "Hidden")
        . "  |  Extra HUDs: " (cfg.ShowExtraHuds ? "ON" : "OFF")
        . "  |  Labels: " (cfg.ShowText ? "ON" : "OFF")
        . "  |  Scale: " Round(cfg.IndicatorScale, 2) "x"
    themeStatus := cfg.ThemeMode " (Active: " (Theme.IsDarkMode() ? "Dark Mode" : "Light Mode") ")"
    remoteHost := A_ComputerName ".local:4455  |  WS Auth: " (cfg.obsPassword != "" ? "Configured" : "None")
    return {
        ptrMode: ptrMode,
        syncMode: syncMode,
        connInfo: connInfo,
        hudStatus: hudStatus,
        themeStatus: themeStatus,
        remoteHost: remoteHost
    }
}

BuildLiveStatusValues(cfg, state := "") {
    info := BuildLiveStatusInfo(cfg, state)
    return "v" UIConstants.APP_VERSION "`n"
        . GetRoutingModeLabel(cfg.AudioRoutingMode) "`n"
        . info.ptrMode "`n"
        . info.syncMode . info.connInfo "`n"
        . info.hudStatus "`n"
        . info.themeStatus "`n"
        . cfg.targetMicName "`n"
        . info.remoteHost
}

BuildLiveStatusSummary(cfg, state := "") {
    info := BuildLiveStatusInfo(cfg, state)
    return "PresenterSync Version:   v" UIConstants.APP_VERSION "`n"
        . "Audio Routing Profile:   " GetRoutingModeLabel(cfg.AudioRoutingMode) "`n"
        . "Active Pointer Mode:     " info.ptrMode "`n"
        . "Telemetry Engine:        " info.syncMode . info.connInfo "`n"
        . "HUD Overlay Status:      " info.hudStatus "`n"
        . "Application Theme:       " info.themeStatus "`n"
        . "Target OBS Mic Source:   " cfg.targetMicName "`n"
        . "Remote Companion Host:   " info.remoteHost
}

AddHelpGuideEdit(guiObj, x, y, w, h, contentText) {
    ed := guiObj.Add("Edit", Format("x{} y{} w{} h{} ReadOnly Multi -WantReturn -Tabstop VScroll", x, y, w, h), contentText)
    Theme.RegisterControl(guiObj, ed, "Edit")
    return ed
}

ShowHelpWindow(cfg, state := "", *) {
    existing := Theme.FocusExistingWindow("HelpWindow")
    if IsObject(existing) {
        if (IsObject(state) && state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn)
            try state.refreshHelpFn.Call()
        return existing
    }

    helpGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "PresenterSync v" UIConstants.APP_VERSION " - Interactive Help & Guide")
    Theme.ApplyToWindow(helpGui)
    Theme.NamedWindows["HelpWindow"] := helpGui

    tabNames := ["Shortcuts", "Pointer & PPT", "Audio & Sync", "Remote Setup", "HUD & Theme", "Live Status"]
    tabs := helpGui.Add("Tab2", "x14 y12 w664 h468 +0x0400", tabNames)
    tabs._tabNames := tabNames
    Theme.RegisterControl(helpGui, tabs, "Tab")

    ; --- TAB 1: SHORTCUTS ---
    tabs.UseTab(1)
    helpGui.SetFont("s11 w700 norm", Theme.UiFont)
    Theme.RegisterControl(helpGui, helpGui.Add("Text", "x30 y62 w632", "Global App, Clicker & Fallback Shortcuts"), "Text", "tabText")
    helpGui.SetFont("s9 w400 norm", Theme.UiFont)
    scCol1 := "Cycle Pointer Modes:`n"
        . "Toggle OBS WebSocket:`n"
        . "Toggle Zoom Monitor:`n"
        . "Show / Hide HUD:`n"
        . "Suspend All Hotkeys:`n"
        . "Exit PresenterSync:`n"
        . "Clicker Mute Button:`n"
        . "OBS Mute / Rec / Pause:`n"
        . "Zoom Mute / Rec / Pause:"
    scCol2 := FormatHK(cfg.PptHotkey) "`n"
        . FormatHK(cfg.WsHotkey) "`n"
        . FormatHK(cfg.ZoomHotkey) "`n"
        . FormatHK(cfg.IndHotkey) "`n"
        . FormatHK(cfg.SuspendHotkey) "`n"
        . FormatHK(cfg.ExitHotkey) "`n"
        . FormatHK(cfg.HwMuteHotkey) "`n"
        . FormatHK(cfg.ObsMuteHotkey) "  /  " FormatHK(cfg.ObsRecHotkey) "  /  " FormatHK(cfg.ObsPauseHotkey) "`n"
        . FormatHK(cfg.ZoomMuteHotkey) "  /  " FormatHK(cfg.ZoomRecHotkey) "  /  " FormatHK(cfg.ZoomPauseHotkey)
    Theme.RegisterControl(helpGui, helpGui.Add("Text", "x30 y94 w200 h195", scCol1), "Text", "tabMuted")
    Theme.RegisterControl(helpGui, helpGui.Add("Text", "x238 y94 w424 h195", scCol2), "Text", "tabText")

    shortcutNotes := "HOW SHORTCUTS WORK`r`n"
        . "- Clicker Mute Button: Works in Full PPT + Mute and Pointer Mute Only modes, and automatically pauses while PresenterSync settings windows are active so typing never toggles your mic.`r`n"
        . "- Fallback Shortcuts (OBS / Zoom): Triggered when OBS WebSocket Sync is disabled (Mode 1 / 3) or when syncing Zoom mic in Mode 2 / Mode 3.`r`n"
        . "- Disable Any Key: Clear a shortcut or set it to 'None' in Settings to leave it unbound."
    AddHelpGuideEdit(helpGui, 30, 296, 632, 114, shortcutNotes)

    btnAppHk := helpGui.Add("Button", "x30 y424 w200 h34", "Edit App Shortcuts")
    btnObsHk := helpGui.Add("Button", "x246 y424 w200 h34", "Edit OBS Settings")
    btnZoomHk := helpGui.Add("Button", "x462 y424 w200 h34", "Edit Zoom Shortcuts")
    Theme.RegisterControl(helpGui, btnAppHk, "Button", "tabButton")
    Theme.RegisterControl(helpGui, btnObsHk, "Button", "tabButton")
    Theme.RegisterControl(helpGui, btnZoomHk, "Button", "tabButton")
    btnAppHk.OnEvent("Click", (*) => ChangeAppHotkeysUI(cfg))
    btnObsHk.OnEvent("Click", (*) => ChangeObsSettingsUI(cfg))
    btnZoomHk.OnEvent("Click", (*) => ChangeZoomShortcutsUI(cfg))

    ; --- TAB 2: POINTER & PPT ---
    tabs.UseTab(2)
    helpGui.SetFont("s11 w700 norm", Theme.UiFont)
    Theme.RegisterControl(helpGui, helpGui.Add("Text", "x30 y62 w632", "Smart PowerPoint & Hardware Clicker Step-by-Step"), "Text", "tabText")
    helpGui.SetFont("s9 w400 norm", Theme.UiFont)
    pptGuide := "1. CHOOSE A POINTER MODE (Tray -> Pointer Controls, or press " FormatHK(cfg.PptHotkey) ")`r`n"
        . "- Full PPT + Mute: Routes slide keys (PgUp/PgDn, Arrows, Space, Enter, Tab, Esc, Shift+F5) directly to PowerPoint in the background while keeping your clicker mute button active.`r`n"
        . "- Pointer Mute Only: Leaves keyboard/navigation keys untouched for normal typing while keeping your clicker mute button armed.`r`n"
        . "- OFF: Disables clicker slide routing and mute interception.`r`n`r`n"
        . "2. DISCOVER & ASSIGN YOUR CLICKER MUTE BUTTON`r`n"
        . "- Click 'Launch Clicker Tester' below and press the key on your wireless presenter you want to assign (such as b for blank screen, Tab, or a media key).`r`n"
        . "- Click 'Change Mute Button', press that key (or click inside the text box to type any AutoHotkey key name like PgDn or F12), then click Save & Restart.`r`n`r`n"
        . "3. BACKGROUND POWERPOINT RELIABILITY & DWM ANIMATION FIX`r`n"
        . "- Hybrid Delivery: Dispatches PowerPoint COM commands first (150ms debounce shield) and falls back to ControlSend for {Tab}/{Enter} hyperlinks or cross-UAC scenarios.`r`n"
        . "- Smooth Fade/Morph Animations: In OBS Studio, capture PowerPoint via Window Capture -> Capture Method 'Windows 10 (1903 and up)', and in Windows Settings -> Display -> Graphics set POWERPNT.EXE to 'High performance'."
    AddHelpGuideEdit(helpGui, 30, 94, 632, 316, pptGuide)

    btnTester := helpGui.Add("Button", "x30 y424 w200 h34", "Launch Clicker Tester")
    btnHwMute := helpGui.Add("Button", "x246 y424 w200 h34", "Change Mute Button")
    btnIntercepts := helpGui.Add("Button", "x462 y424 w200 h34", "Configure Intercepts")
    Theme.RegisterControl(helpGui, btnTester, "Button", "tabButton")
    Theme.RegisterControl(helpGui, btnHwMute, "Button", "tabButton")
    Theme.RegisterControl(helpGui, btnIntercepts, "Button", "tabButton")
    btnTester.OnEvent("Click", (*) => ShowPointerTester())
    btnHwMute.OnEvent("Click", (*) => ChangeHwMuteHotkeyUI(cfg))
    btnIntercepts.OnEvent("Click", (*) => ConfigurePointerKeysUI(cfg))

    ; --- TAB 3: AUDIO & SYNC ---
    tabs.UseTab(3)
    helpGui.SetFont("s11 w700 norm", Theme.UiFont)
    Theme.RegisterControl(helpGui, helpGui.Add("Text", "x30 y62 w632", "Audio Routing Profiles, OBS WebSocket v5 & Zoom UIA"), "Text", "tabText")
    helpGui.SetFont("s9 w400 norm", Theme.UiFont)
    syncGuide := "1. SELECT YOUR AUDIO ROUTING PROFILE (Settings -> Audio Setup Wizard...)`r`n"
        . "- Mode 1 (Pro OBS Setup / VB-Cable): Ideal when OBS audio feeds Zoom. Toggles OBS mic directly via WebSocket ToggleInputMute (or your OBS shortcut fallback).`r`n"
        . "- Mode 2 (Standard Direct Mic / Zoom-Only): Works without OBS by dispatching your Zoom Mute shortcut (default Alt+A) cleanly to Zoom.`r`n"
        . "- Mode 3 (Dual App Sync / OBS + Zoom): Keeps OBS and Zoom microphones synchronized two-way so muting in either app mirrors cleanly.`r`n`r`n"
        . "2. OBS STUDIO WEBSOCKET v5 SETUP (Recommended for Mode 1 & Mode 3)`r`n"
        . "- In OBS Studio: Tools -> WebSocket Server Settings -> Enable WebSocket server (Port 4455).`r`n"
        . "- Enable Authentication and set a password, then open 'OBS Settings' below to enter that password and your exact OBS mic source name (default: Mic/Aux).`r`n"
        . "- Toggle with Tray -> OBS WebSocket Sync (or " FormatHK(cfg.WsHotkey) ") for live 3-tier telemetry.`r`n`r`n"
        . "3. ZOOM BACKGROUND TELEMETRY (UIA MONITORING)`r`n"
        . "- In Zoom Desktop Settings -> Accessibility, check 'Always show meeting controls'.`r`n"
        . "- Toggle with Tray -> Zoom Monitoring (or " FormatHK(cfg.ZoomHotkey) "). OBS Sync and Zoom Monitoring are mutually exclusive; Unread Chat tracking detects Zoom windows automatically."
    AddHelpGuideEdit(helpGui, 30, 94, 632, 316, syncGuide)

    btnWizard := helpGui.Add("Button", "x30 y424 w200 h34", "Audio Setup Wizard")
    btnObsCfg := helpGui.Add("Button", "x246 y424 w200 h34", "OBS Settings")
    btnZoomCfg := helpGui.Add("Button", "x462 y424 w200 h34", "Zoom Shortcuts")
    Theme.RegisterControl(helpGui, btnWizard, "Button", "tabButton")
    Theme.RegisterControl(helpGui, btnObsCfg, "Button", "tabButton")
    Theme.RegisterControl(helpGui, btnZoomCfg, "Button", "tabButton")
    btnWizard.OnEvent("Click", (*) => PromptForSetup(cfg, false))
    btnObsCfg.OnEvent("Click", (*) => ChangeObsSettingsUI(cfg))
    btnZoomCfg.OnEvent("Click", (*) => ChangeZoomShortcutsUI(cfg))

    ; --- TAB 4: REMOTE SETUP ---
    tabs.UseTab(4)
    helpGui.SetFont("s11 w700 norm", Theme.UiFont)
    Theme.RegisterControl(helpGui, helpGui.Add("Text", "x30 y62 w632", "Smart Board & Secondary PC Companion (PresenterSync Remote)"), "Text", "tabText")
    helpGui.SetFont("s9 w400 norm", Theme.UiFont)
    AddHelpGuideEdit(helpGui, 30, 94, 632, 316, GetRemoteSetupGuideText())

    btnRemInfo := helpGui.Add("Button", "x30 y424 w200 h34", "Remote Connection Info")
    btnRemObs := helpGui.Add("Button", "x246 y424 w200 h34", "Edit OBS Settings")
    btnRemTest := helpGui.Add("Button", "x462 y424 w200 h34", "Launch Clicker Tester")
    Theme.RegisterControl(helpGui, btnRemInfo, "Button", "tabButton")
    Theme.RegisterControl(helpGui, btnRemObs, "Button", "tabButton")
    Theme.RegisterControl(helpGui, btnRemTest, "Button", "tabButton")
    btnRemInfo.OnEvent("Click", (*) => ShowRemoteCompanionInfo(cfg))
    btnRemObs.OnEvent("Click", (*) => ChangeObsSettingsUI(cfg))
    btnRemTest.OnEvent("Click", (*) => ShowPointerTester())

    ; --- TAB 5: HUD & THEME ---
    tabs.UseTab(5)
    helpGui.SetFont("s11 w700 norm", Theme.UiFont)
    Theme.RegisterControl(helpGui, helpGui.Add("Text", "x30 y62 w632", "Adaptive 3-Tier HUD Overlay & Live Appearance Guide"), "Text", "tabText")
    helpGui.SetFont("s9 w400 norm", Theme.UiFont)
    hudGuide := "1. ADAPTIVE 3-TIER HUD STACK`r`n"
        . "- Row 1 (Bottom): Live (Green) / Muted (Red) Mic indicator with breathing pulse when muted.`r`n"
        . "- Row 2 (Middle - OBS / Zoom): 3-state Recording (NOT REC / REC / PAUSED) + Unread Chat badge.`r`n"
        . "- Row 3 (Top - OBS): Studio Mode badge + dynamically sized Active Program Scene pill.`r`n"
        . "- Compact Mode: Uncheck 'Show Extra HUDs' in the tray menu to show only the Mic pill while keeping telemetry active in the background.`r`n`r`n"
        . "2. MOUSE, TOUCH & SCALE CONTROLS`r`n"
        . "- Move HUD: Left-drag any HUD pill anywhere on screen (position saves automatically).`r`n"
        . "- Context Menu: Right-click any HUD pill to open the PresenterSync menu at your cursor.`r`n"
        . "- Scaling & Opacity: Pick 8 scale presets (0.25x to 5.0x for 4K / 86-inch Smart Boards) and Ghost (50%), Frosted (85%), or Solid (100%) transparency under Indicator Appearance.`r`n`r`n"
        . "3. TRY LIVE ADJUSTMENTS BELOW (APPLIES IMMEDIATELY WITHOUT RESTART):"
    AddHelpGuideEdit(helpGui, 30, 94, 632, 268, hudGuide)

    btnTogExtra := helpGui.Add("Button", "x30 y380 w308 h34", "Toggle Extra HUDs (ON/OFF)")
    btnTogText := helpGui.Add("Button", "x354 y380 w308 h34", "Toggle HUD Text Labels")
    btnCycTheme := helpGui.Add("Button", "x30 y424 w308 h34", "Cycle Theme (System/Dark/Light)")
    btnResetPos := helpGui.Add("Button", "x354 y424 w308 h34", "Reset HUD Position")
    Theme.RegisterControl(helpGui, btnTogExtra, "Button", "tabButton")
    Theme.RegisterControl(helpGui, btnTogText, "Button", "tabButton")
    Theme.RegisterControl(helpGui, btnCycTheme, "Button", "tabButton")
    Theme.RegisterControl(helpGui, btnResetPos, "Button", "tabButton")

    ; --- TAB 6: LIVE STATUS ---
    tabs.UseTab(6)
    helpGui.SetFont("s11 w700 norm", Theme.UiFont)
    Theme.RegisterControl(helpGui, helpGui.Add("Text", "x30 y62 w632", "Live Configuration, Telemetry & Remote Host Status"), "Text", "tabText")
    helpGui.SetFont("s9 w400 norm", Theme.UiFont)
    statusCol1 := "PresenterSync Version:`n"
        . "Audio Routing Profile:`n"
        . "Active Pointer Mode:`n"
        . "Telemetry Engine:`n"
        . "HUD Overlay Status:`n"
        . "Application Theme:`n"
        . "Target OBS Mic Source:`n"
        . "Remote Companion Host:"
    Theme.RegisterControl(helpGui, helpGui.Add("Text", "x30 y98 w185 h270", statusCol1), "Text", "tabMuted")
    statusValCtrl := helpGui.Add("Text", "x222 y98 w440 h270", BuildLiveStatusValues(cfg, state))
    Theme.RegisterControl(helpGui, statusValCtrl, "Text", "tabText")

    RefreshHelpStatus(*) {
        if WinExist("ahk_id " helpGui.Hwnd)
            statusValCtrl.Value := BuildLiveStatusValues(cfg, state)
    }
    if IsObject(state)
        state.refreshHelpFn := RefreshHelpStatus

    SyncTrayAndHelp() {
        if (IsObject(state) && state.HasOwnProp("rebuildTrayFn") && state.rebuildTrayFn)
            try state.rebuildTrayFn.Call()
        RefreshHelpStatus()
    }

    OnHelpToggleExtra(*) {
        cfg.ShowExtraHuds := !cfg.ShowExtraHuds
        cfg.WriteBool("Settings", "ShowExtraHuds", cfg.ShowExtraHuds)
        if IsObject(state)
            RefreshHudAppearance(cfg, state)
        SyncTrayAndHelp()
    }

    OnHelpToggleText(*) {
        cfg.ShowText := !cfg.ShowText
        cfg.WriteBool("Settings", "ShowText", cfg.ShowText)
        if IsObject(state)
            RefreshHudAppearance(cfg, state)
        SyncTrayAndHelp()
    }

    OnHelpCycleTheme(*) {
        nextMode := (cfg.ThemeMode = "System") ? "Dark" : ((cfg.ThemeMode = "Dark") ? "Light" : "System")
        SetThemeMode(cfg, "", nextMode)
        SyncTrayAndHelp()
    }

    OnHelpResetPos(*) {
        ResetTrayPosition(cfg, state)
        SyncTrayAndHelp()
    }

    OnHelpResetAppearance(*) {
        ResetAppearance(cfg, state)
        SyncTrayAndHelp()
    }

    btnTogExtra.OnEvent("Click", OnHelpToggleExtra)
    btnTogText.OnEvent("Click", OnHelpToggleText)
    btnCycTheme.OnEvent("Click", OnHelpCycleTheme)
    btnResetPos.OnEvent("Click", OnHelpResetPos)

    btnRefreshStatus := helpGui.Add("Button", "x30 y424 w200 h34", "Refresh Status")
    btnResetApp := helpGui.Add("Button", "x246 y424 w200 h34", "Reset Appearance")
    btnOpenAbout := helpGui.Add("Button", "x462 y424 w200 h34", "About v" UIConstants.APP_VERSION)
    Theme.RegisterControl(helpGui, btnRefreshStatus, "Button", "tabButton")
    Theme.RegisterControl(helpGui, btnResetApp, "Button", "tabButton")
    Theme.RegisterControl(helpGui, btnOpenAbout, "Button", "tabButton")
    btnRefreshStatus.OnEvent("Click", RefreshHelpStatus)
    btnResetApp.OnEvent("Click", OnHelpResetAppearance)
    btnOpenAbout.OnEvent("Click", (*) => ShowAboutWindow(cfg, state))

    tabs.UseTab()

    helpGui.SetFont("s10 w400 norm", Theme.UiFont)
    btn := helpGui.Add("Button", "w140 x276 y492 h34 Default", "Got it!")
    Theme.RegisterControl(helpGui, btn, "Button")
    CloseHelp(*) {
        if (IsObject(state) && state.HasOwnProp("refreshHelpFn"))
            state.refreshHelpFn := ""
        Theme.UnregisterWindow(helpGui, "HelpWindow")
        helpGui.Destroy()
    }
    btn.OnEvent("Click", CloseHelp)
    helpGui.OnEvent("Close", CloseHelp)
    helpGui.OnEvent("Escape", CloseHelp)

    helpGui.Show("w692 h540")
    btn.Focus()
    return helpGui
}

ShowAboutWindow(cfg := "", state := "", *) {
    existing := Theme.FocusExistingWindow("AboutWindow")
    if IsObject(existing)
        return existing

    aboutGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "About PresenterSync")
    Theme.ApplyToWindow(aboutGui)
    Theme.NamedWindows["AboutWindow"] := aboutGui

    iconSource := A_IsCompiled ? A_ScriptFullPath : A_ScriptDir "\PresenterSync.ico"

    if FileExist(iconSource) {
        aboutGui.Add("Picture", "x158 y15 w64 h64", iconSource)
    }

    aboutGui.SetFont("s16 w700 norm", Theme.UiFont)
    Theme.RegisterControl(aboutGui, aboutGui.Add("Text", "x10 w360 Center y+12", "PresenterSync"), "Text")

    aboutGui.SetFont("s10 w700 norm", Theme.UiFont)
    Theme.RegisterControl(aboutGui, aboutGui.Add("Text", "x10 w360 Center y+4", "Version " UIConstants.APP_VERSION), "Text", "accent")

    aboutGui.SetFont("s9 w400 norm", Theme.UiFont)
    Theme.RegisterControl(aboutGui, aboutGui.Add("Text", "x20 w340 Center y+8", "OBS Studio WebSocket v5, Zoom UIA Telemetry & Smart PowerPoint Control Suite"), "Text", "muted")

    aboutGui.SetFont("s10 w400 norm", Theme.UiFont)
    Theme.RegisterControl(aboutGui, aboutGui.Add("Text", "x10 w360 Center y+12", "Created by Saabith Jiffry"), "Text")

    aboutGui.SetFont("s10 w400 norm", Theme.UiFont)
    gitBtn := aboutGui.Add("Button", "w110 x18 y+20 h32", "GitHub Repo")
    Theme.RegisterControl(aboutGui, gitBtn, "Button")
    gitBtn.OnEvent("Click", (*) => Run("https://github.com/SaabithJiffry/PresenterSync/"))

    helpBtn := aboutGui.Add("Button", "w110 x+12 h32", "Help & Guide")
    Theme.RegisterControl(aboutGui, helpBtn, "Button")
    if IsObject(cfg)
        helpBtn.OnEvent("Click", (*) => ShowHelpWindow(cfg, state))
    else
        helpBtn.Enabled := false

    closeBtn := aboutGui.Add("Button", "w110 x+12 h32 Default", "Close")
    Theme.RegisterControl(aboutGui, closeBtn, "Button")
    CloseAbout(*) {
        Theme.UnregisterWindow(aboutGui, "AboutWindow")
        aboutGui.Destroy()
    }
    closeBtn.OnEvent("Click", CloseAbout)
    aboutGui.OnEvent("Close", CloseAbout)
    aboutGui.OnEvent("Escape", CloseAbout)

    aboutGui.Show("AutoSize")
    return aboutGui
}

ChangeAppHotkeysUI(cfg, *) {
    SaveAppHk(values, ctrls, dlg) {
        cfg.Write("Settings", "PptHotkey", values["ppt"])
        cfg.Write("Settings", "WsHotkey", values["ws"])
        cfg.Write("Settings", "ZoomHotkey", values["zoom"])
        cfg.Write("Settings", "IndHotkey", values["ind"])
        cfg.Write("Settings", "SuspendHotkey", values["susp"])
        cfg.Write("Settings", "ExitHotkey", values["exit"])
        Reload()
    }

    elements := [
        {type: "Text", opts: "xm w160 h25 +0x200", text: "Cycle Pointer Mode:"},
        {type: "Hotkey", id: "ppt", opts: "x+10 yp w130 h25", value: cfg.PptHotkey, required: true, errorMsg: "Shortcuts cannot be left blank."},
        {type: "Text", opts: "xm y+8 w160 h25 +0x200", text: "Toggle OBS WebSocket:"},
        {type: "Hotkey", id: "ws", opts: "x+10 yp w130 h25", value: cfg.WsHotkey, required: true, errorMsg: "Shortcuts cannot be left blank."},
        {type: "Text", opts: "xm y+8 w160 h25 +0x200", text: "Toggle Zoom Monitor:"},
        {type: "Hotkey", id: "zoom", opts: "x+10 yp w130 h25", value: cfg.ZoomHotkey, required: true, errorMsg: "Shortcuts cannot be left blank."},
        {type: "Text", opts: "xm y+8 w160 h25 +0x200", text: "Toggle Indicator:"},
        {type: "Hotkey", id: "ind", opts: "x+10 yp w130 h25", value: cfg.IndHotkey, required: true, errorMsg: "Shortcuts cannot be left blank."},
        {type: "Text", opts: "xm y+8 w160 h25 +0x200", text: "Suspend Hotkeys:"},
        {type: "Hotkey", id: "susp", opts: "x+10 yp w130 h25", value: cfg.SuspendHotkey, required: true, errorMsg: "Shortcuts cannot be left blank."},
        {type: "Text", opts: "xm y+8 w160 h25 +0x200", text: "Exit PresenterSync:"},
        {type: "Hotkey", id: "exit", opts: "x+10 yp w130 h25", value: cfg.ExitHotkey, required: true, errorMsg: "Shortcuts cannot be left blank."}
    ]

    return BuildSettingsWindow("Edit App Shortcuts", elements, SaveAppHk, {
        saveBtnText: "Save & Restart",
        saveBtnOpts: "xm w300 h32 Default y+16"
    })
}

ChangeZoomShortcutsUI(cfg, *) {
    SaveZoomHk(values, ctrls, dlg) {
        cfg.Write("Settings", "ZoomMuteHotkey", values["mute"])
        cfg.Write("Settings", "ZoomRecHotkey", values["rec"] != "" ? values["rec"] : "!r")
        cfg.Write("Settings", "ZoomPauseHotkey", values["pause"] != "" ? values["pause"] : "!p")
        Reload()
    }

    elements := [
        {type: "Text", opts: "w300", text: "Zoom Mute Shortcut (Default Alt+A):"},
        {type: "Hotkey", id: "mute", opts: "w300", value: cfg.ZoomMuteHotkey, required: true, errorMsg: "Zoom Mute shortcut cannot be empty."},
        {type: "Text", opts: "w300 y+10", text: "Start/Stop Recording Shortcut (Default Alt+R):"},
        {type: "Hotkey", id: "rec", opts: "w300", value: cfg.ZoomRecHotkey},
        {type: "Text", opts: "w300 y+10", text: "Pause/Resume Recording Shortcut (Default Alt+P):"},
        {type: "Hotkey", id: "pause", opts: "w300", value: cfg.ZoomPauseHotkey}
    ]

    return BuildSettingsWindow("Edit Zoom Shortcuts", elements, SaveZoomHk, {
        saveBtnText: "Save & Restart",
        saveBtnOpts: "w300 h32 Default y+15"
    })
}

SetRoutingMode(cfg, mode, *) {
    cfg.Write("Settings", "AudioRoutingMode", mode)
    if ((mode == 2 || mode == 3) && cfg.ZoomMuteHotkey = "")
        cfg.Write("Settings", "ZoomMuteHotkey", "!a")
    Reload()
}

ChangeObsSettingsUI(cfg, *) {
    SaveObsSettings(values, ctrls, dlg) {
        cfg.Write("Settings", "ObsHotkey", values["mute"] != "" ? values["mute"] : "None")
        cfg.Write("Settings", "ObsRecHotkey", values["rec"] != "" ? values["rec"] : "^F9")
        cfg.Write("Settings", "ObsPauseHotkey", values["pause"] != "" ? values["pause"] : "^F10")
        cfg.Write("Settings", "TargetMicName", values["mic"])
        if (values.Has("pw"))
            cfg.Write("Settings", "ObsPassword", values["pw"])
        Reload()
    }

    elements := [
        {type: "Text", opts: "w280", text: "OBS Mute Shortcut" (cfg.EnableWS ? " (Optional with WebSocket):" : ":")},
        {type: "Hotkey", id: "mute", opts: "w280", value: (cfg.ObsMuteHotkey != "None") ? cfg.ObsMuteHotkey : "", required: (!cfg.EnableWS && cfg.AudioRoutingMode != 2), errorMsg: "OBS Mute shortcut cannot be empty unless WebSocket Sync is enabled."},
        {type: "Text", opts: "w280 y+10", text: "Start/Stop Recording Shortcut:"},
        {type: "Hotkey", id: "rec", opts: "w280", value: cfg.ObsRecHotkey},
        {type: "Text", opts: "w280 y+10", text: "Pause/Resume Recording Shortcut:"},
        {type: "Hotkey", id: "pause", opts: "w280", value: cfg.ObsPauseHotkey},
        {type: "Text", opts: "w280 y+10", text: "Exact OBS Audio Source Name (e.g., Mic/Aux):"},
        {type: "Edit", id: "mic", opts: "w280", value: cfg.targetMicName, required: true, errorMsg: "Exact OBS Audio Source Name cannot be empty."},
        {type: "Text", opts: "w280 y+10", text: "OBS WebSocket Password (Optional):"},
        {type: "Edit", id: "pw", opts: "w280 Password", value: cfg.obsPassword}
    ]

    return BuildSettingsWindow("OBS Settings", elements, SaveObsSettings, {
        saveBtnText: "Save & Restart",
        saveBtnOpts: "w280 h32 Default y+15"
    })
}

OpenPointerKeyCaptureDialog(currentKey, saveBtnLabel, onApply) {
    existing := Theme.FocusExistingWindow("Edit Pointer Mute Button")
    if IsObject(existing)
        return existing

    Theme.AcquireSuspend()

    dlg := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "Edit Pointer Mute Button")
    dlg._closed := false
    Theme.ApplyToWindow(dlg)
    Theme.NamedWindows["Edit Pointer Mute Button"] := dlg

    dlg.SetFont("s10 w600", Theme.UiFont)
    Theme.RegisterControl(dlg, dlg.Add("Text", "w280", "Presentation Clicker Mute Button"), "Text")
    dlg.SetFont("s9 w400", Theme.UiFont)
    Theme.RegisterControl(dlg, dlg.Add("Text", "w280 y+4", "Press a button on your clicker, or click the box to type a custom key name:"), "Text", "muted")

    editKey := dlg.Add("Edit", "w280 y+12 Center", currentKey)
    editKey.SetFont("s12 w700", Theme.UiFont)
    Theme.RegisterControl(dlg, editKey, "Edit", "accent")

    statusTxt := dlg.Add("Text", "w280 y+6 Center", "Listening for clicker input...")
    Theme.RegisterControl(dlg, statusTxt, "Text", "muted")

    btnSave := dlg.Add("Button", "w280 h32 y+12 Default", saveBtnLabel)
    Theme.RegisterControl(dlg, btnSave, "Button", "accent")

    ih := InputHook("L0")
    ih.KeyOpt("{All}", "N")
    ih.KeyOpt("{Enter}{NumpadEnter}{Escape}{Tab}{LShift}{RShift}{LControl}{RControl}{LAlt}{RAlt}{LWin}{RWin}", "-N V")
    ih.OnKeyDown := (ihHook, VK, SC) => (
        keyName := GetKeyName(Format("vk{:X}sc{:X}", VK, SC)),
        (keyName != "" && !dlg._closed) ? (
            editKey.Value := keyName,
            statusTxt.Value := "Captured: " keyName
        ) : 0
    )

    StartCapture(*) {
        if (dlg._closed)
            return
        try ih.Start()
        statusTxt.Value := "Listening for clicker input..."
    }

    StopCapture(*) {
        try ih.Stop()
        if (!dlg._closed && WinExist("ahk_id " dlg.Hwnd))
            statusTxt.Value := "Manual typing mode (type key name)"
    }

    editKey.OnEvent("Focus", StopCapture)
    editKey.OnEvent("LoseFocus", StartCapture)

    OnActivateMsg(wParam, lParam, msg, hwnd) {
        if (dlg._closed || hwnd != dlg.Hwnd)
            return
        if ((wParam & 0xFFFF) == 0) {
            try ih.Stop()
        } else {
            try focused := dlg.FocusedCtrl
            catch
                focused := ""
            if (focused != editKey)
                StartCapture()
        }
    }
    OnMessage(0x0006, OnActivateMsg)

    Cleanup(*) {
        if (dlg._closed)
            return
        dlg._closed := true
        OnMessage(0x0006, OnActivateMsg, 0)
        try ih.Stop()
        Theme.UnregisterWindow(dlg, "Edit Pointer Mute Button")
        Theme.ReleaseSuspend()
        dlg.Destroy()
    }

    SaveKey(*) {
        static dummyHotIf := (*) => false
        static dummyHandler := (*) => 0
        val := Trim(editKey.Value)
        if (val = "") {
            dlg.Opt("+OwnDialogs")
            MsgBox("Please press or enter a button name to register it.", "Error", "Icon!")
            return
        }
        if (StrLower(val) = "none") {
            Cleanup()
            onApply.Call("None")
            return
        }
        try {
            HotIf dummyHotIf
            Hotkey(val, dummyHandler, "Off")
            HotIf
        } catch {
            HotIf
            dlg.Opt("+OwnDialogs")
            MsgBox("'" val "' is not a valid AutoHotkey key name.`nExamples: b, PgDn, F12, Media_Play_Pause", "Invalid Key", "Icon!")
            return
        }
        Cleanup()
        onApply.Call(val)
    }

    btnSave.OnEvent("Click", SaveKey)
    dlg.OnEvent("Close", Cleanup)
    dlg.OnEvent("Escape", Cleanup)

    dlg.Show("AutoSize Center")
    btnSave.Focus()
    StartCapture()
    return dlg
}

ChangeHwMuteHotkeyUI(cfg, *) {
    return OpenPointerKeyCaptureDialog(cfg.HwMuteHotkey, "Save & Restart", (val) => (
        cfg.HwMuteHotkey := val,
        cfg.Write("Settings", "HwMuteHotkey", val),
        Reload()
    ))
}

ConfigurePointerKeysUI(cfg, *) {
    SavePointerKeys(values, ctrls, dlg) {
        cfg.Write("Pointer", "CatchArrows", values["arrows"])
        cfg.Write("Pointer", "CatchPg", values["pg"])
        cfg.Write("Pointer", "CatchSpace", values["space"])
        cfg.Write("Pointer", "CatchEnter", values["enter"])
        cfg.Write("Pointer", "CatchTab", values["tab"])
        cfg.Write("Pointer", "CatchEsc", values["esc"])
        Reload()
    }

    elements := [
        {type: "Text", opts: "w260", text: "Select which keys to intercept in Full PPT Mode:"},
        {type: "Checkbox", id: "arrows", opts: "w260", value: cfg.CatchArrows, text: "Arrow Keys (Up, Down, Left, Right)"},
        {type: "Checkbox", id: "pg", opts: "w260", value: cfg.CatchPg, text: "Page Keys (PgUp, PgDn)"},
        {type: "Checkbox", id: "space", opts: "w260", value: cfg.CatchSpace, text: "Spacebar"},
        {type: "Checkbox", id: "enter", opts: "w260", value: cfg.CatchEnter, text: "Enter Key"},
        {type: "Checkbox", id: "tab", opts: "w260", value: cfg.CatchTab, text: "Tab Key"},
        {type: "Checkbox", id: "esc", opts: "w260", value: cfg.CatchEsc, text: "Escape Key"}
    ]

    return BuildSettingsWindow("Configure Pointer Intercepts", elements, SavePointerKeys, {
        saveBtnText: "Save & Restart",
        saveBtnOpts: "w260 h32 Default y+15"
    })
}

ShowPointerTester(*) {
    existing := Theme.FocusExistingWindow("PointerTester")
    if IsObject(existing)
        return existing

    Theme.AcquireSuspend()

    testerGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "Pointer Tester")
    testerGui._closed := false
    Theme.ApplyToWindow(testerGui)
    Theme.NamedWindows["PointerTester"] := testerGui

    testerGui.SetFont("s10 norm", Theme.UiFont)
    Theme.RegisterControl(testerGui, testerGui.Add("Text", "w250 Center", "Press any button on your clicker."), "Text")

    keyDisplay := testerGui.Add("Text", "w250 Center y+15", "Listening...")
    keyDisplay.SetFont("s14 w700 norm", Theme.UiFont)
    Theme.RegisterControl(testerGui, keyDisplay, "Text", "accent")

    testerGui.SetFont("s10 w400 norm", Theme.UiFont)
    btn := testerGui.Add("Button", "w110 x70 y+20 h32 Default", "Close")
    Theme.RegisterControl(testerGui, btn, "Button")

    ih := InputHook("L0 V")
    ih.KeyOpt("{All}", "N")

    ih.OnKeyDown := (ih, VK, SC) => UpdateKeyDisplay(VK, SC)

    UpdateKeyDisplay(VK, SC) {
        keyName := GetKeyName(Format("vk{:X}sc{:X}", VK, SC))
        if WinExist("ahk_id " testerGui.Hwnd)
            keyDisplay.Value := keyName
    }

    Cleanup(*) {
        if (testerGui._closed)
            return
        testerGui._closed := true
        ih.Stop()
        Theme.UnregisterWindow(testerGui, "PointerTester")
        Theme.ReleaseSuspend()
        testerGui.Destroy()
    }

    testerGui.OnEvent("Close", Cleanup)
    testerGui.OnEvent("Escape", Cleanup)
    btn.OnEvent("Click", Cleanup)

    testerGui.Show("AutoSize")
    ih.Start()
    return testerGui
}

GetLocalNetworkEndpoints() {
    res := {ips: [], details: []}
    seen := Map()
    try {
        wmi := ComObjGet("winmgmts:")
        adapters := wmi.ExecQuery("SELECT Description, IPAddress FROM Win32_NetworkAdapterConfiguration WHERE IPEnabled = True")
        for adapter in adapters {
            if !IsObject(adapter.IPAddress)
                continue
            desc := String(adapter.Description)
            isVirtual := RegExMatch(desc, "i)(virtual|vmware|vbox|hyper-v|pseudo|loopback|npcap|tap-)")
            for ip in adapter.IPAddress {
                ipStr := String(ip)
                if (InStr(ipStr, ".") && !seen.Has(ipStr) && ipStr != "127.0.0.1" && !RegExMatch(ipStr, "^169\.254\.")) {
                    seen[ipStr] := true
                    item := {name: desc, ip: ipStr, isVirtual: isVirtual}
                    if (!isVirtual) {
                        res.ips.InsertAt(1, ipStr)
                        res.details.InsertAt(1, item)
                    } else {
                        res.ips.Push(ipStr)
                        res.details.Push(item)
                    }
                }
            }
        }
    }
    if (res.ips.Length == 0) {
        Loop 4 {
            ipVal := A_IPAddress%A_Index%
            if (ipVal != "" && ipVal != "127.0.0.1" && ipVal != "0.0.0.0" && !seen.Has(ipVal)) {
                seen[ipVal] := true
                res.ips.Push(ipVal)
                res.details.Push({name: "Adapter " A_Index, ip: ipVal, isVirtual: false})
            }
        }
    }
    return res
}

ParseCandidateEndpoints(rawStr, defaultPort := "4455") {
    defPort := (IsInteger(defaultPort) && Integer(defaultPort) >= 1 && Integer(defaultPort) <= 65535) ? String(Integer(defaultPort)) : "4455"
    endpoints := []
    seen := Map()
    for item in StrSplit(rawStr, [",", ";"]) {
        clean := Trim(item)
        if (clean = "")
            continue
        clean := RegExReplace(clean, "i)^wss?://", "")
        clean := RTrim(clean, "/ ")
        if (clean = "")
            continue
        host := clean
        port := defPort
        if RegExMatch(clean, "^(.*?):(\d+)$", &m) {
            host := m[1]
            port := m[2]
        }
        if (host = "")
            continue
        key := host ":" port
        if (!seen.Has(key)) {
            seen[key] := true
            endpoints.Push({host: host, port: port, raw: key})
        }
    }
    if (endpoints.Length == 0)
        endpoints.Push({host: "127.0.0.1", port: defPort, raw: "127.0.0.1:" defPort})
    return endpoints
}

ShowRemoteCompanionInfo(cfg, *) {
    existing := Theme.FocusExistingWindow("Remote Companion Connection Info")
    if IsObject(existing)
        return existing

    endpoints := GetLocalNetworkEndpoints()
    candidates := [A_ComputerName ".local"]
    for ep in endpoints.ips {
        candidates.Push(ep)
    }
    universalString := ""
    for idx, c in candidates {
        universalString .= (idx > 1 ? ", " : "") c
    }

    dlg := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "Remote Companion Connection Info")
    dlg._closed := false
    Theme.ApplyToWindow(dlg)
    Theme.NamedWindows["Remote Companion Connection Info"] := dlg

    dlg.SetFont("s10 w600", Theme.UiFont)
    Theme.RegisterControl(dlg, dlg.Add("Text", "w360", "Host Details for PresenterSync Remote"), "Text")
    dlg.SetFont("s9 w400", Theme.UiFont)
    Theme.RegisterControl(dlg, dlg.Add("Text", "w360 y+4", "Enter these details on your secondary device (Smart Board / Laptop):"), "Text", "muted")

    dlg.SetFont("s9 w600", Theme.UiFont)
    Theme.RegisterControl(dlg, dlg.Add("Text", "w360 y+12", "Computer Name (mDNS):"), "Text")
    dlg.SetFont("s9 w400", Theme.UiFont)
    editHost := dlg.Add("Edit", "w360 ReadOnly -Wrap", A_ComputerName ".local")
    Theme.RegisterControl(dlg, editHost, "Edit")

    ipListText := ""
    for ep in endpoints.details {
        ipListText .= (ep.isVirtual ? "[Virtual] " : "[LAN] ") ep.name ": " ep.ip "`n"
    }
    if (ipListText != "") {
        dlg.SetFont("s9 w600", Theme.UiFont)
        Theme.RegisterControl(dlg, dlg.Add("Text", "w360 y+8", "Detected Local IP Addresses:"), "Text")
        dlg.SetFont("s9 w400", Theme.UiFont)
        editIps := dlg.Add("Edit", "w360 r3 ReadOnly", RTrim(ipListText, "`n"))
        Theme.RegisterControl(dlg, editIps, "Edit")
    }

    dlg.SetFont("s9 w600", Theme.UiFont)
    Theme.RegisterControl(dlg, dlg.Add("Text", "w360 y+8", "Universal Connection String (Multi-Candidate):"), "Text")
    dlg.SetFont("s9 w400", Theme.UiFont)
    editUniv := dlg.Add("Edit", "w360 ReadOnly -Wrap", universalString)
    Theme.RegisterControl(dlg, editUniv, "Edit")

    btnCopy := dlg.Add("Button", "w360 h30 y+10", "Copy Universal String to Clipboard")
    Theme.RegisterControl(dlg, btnCopy, "Button", "accent")
    ResetCopyBtn(*) {
        if (!dlg._closed && WinExist("ahk_id " dlg.Hwnd))
            btnCopy.Text := "Copy Universal String to Clipboard"
    }
    btnCopy.OnEvent("Click", (*) => (
        A_Clipboard := universalString,
        btnCopy.Text := "✓ Copied to Clipboard!",
        SetTimer(ResetCopyBtn, -1800),
        TrayTip("Copied!", "Universal connection string copied to clipboard.", 1)
    ))

    statusLine := "OBS Port: 4455  |  Password: " (cfg.obsPassword != "" ? "Configured" : "None") "  |  Mic: " cfg.targetMicName
    Theme.RegisterControl(dlg, dlg.Add("Text", "w360 y+12 Center", statusLine), "Text", "muted")

    btnClose := dlg.Add("Button", "w360 h32 y+12 Default", "Close")
    Theme.RegisterControl(dlg, btnClose, "Button")

    Cleanup(*) {
        if (dlg._closed)
            return
        dlg._closed := true
        Theme.UnregisterWindow(dlg, "Remote Companion Connection Info")
        dlg.Destroy()
    }

    dlg.OnEvent("Close", Cleanup)
    dlg.OnEvent("Escape", Cleanup)
    btnClose.OnEvent("Click", Cleanup)

    dlg.Show("AutoSize Center")
    return dlg
}

; --- HUD STATE SYNCHRONIZATION & APPEARANCE ---
GetCornerRadius(cfg, h) {
    return cfg.SleekCorners ? (h / 2.0) : Min(UIConstants.CORNER_RADIUS_DEFAULT * cfg.IndicatorScale, h / 2.0)
}

ApplyMicAppearance(cfg, state, customX := "", customY := "", customW := "", customH := "", customAlpha := "", overrideMuted := "") {
    if (!IsObject(state.MicGui))
        return false

    pos := ComputeHudLayout(state, state.savedX, state.savedY)
    x := (customX != "") ? customX : pos.micX
    y := (customY != "") ? customY : pos.micY
    w := (customW != "") ? customW : pos.micW
    h := (customH != "") ? customH : pos.micH
    alpha := (customAlpha != "") ? customAlpha : state.currentAlpha
    mutedState := (overrideMuted != "") ? overrideMuted : state.isMuted

    bgRgb := mutedState ? state.colors.muted : state.colors.live
    brdBgr := mutedState ? state.colors.borderMuted : state.colors.borderLive
    icHex := cfg.MonoIcon ? (mutedState ? state.colors.iconMuted : state.colors.iconLive) : "FFFFFF"
    glyph := mutedState ? Chr(0xF781) : Chr(0xE720)
    lbl := mutedState ? "MUTED" : "LIVE"
    contentArgb := Gdip.HexToArgb(icHex)

    if (cfg.ShowText) {
        offsetX := Round((w - state.baseWidth) / 2)
        iconW := Round(UIConstants.MIC_ICON_W * cfg.IndicatorScale)
        iconX := offsetX + Round(UIConstants.ICON_OFFSET_X * cfg.IndicatorScale)
        textW := Round(UIConstants.MIC_TEXT_W * cfg.IndicatorScale)
        textX := offsetX + Round(UIConstants.TEXT_OFFSET_X * cfg.IndicatorScale)
        iconCfg := {text: glyph, font: state.IconFont, size: state.iconSize, color: contentArgb, x: iconX, w: iconW}
        labelCfg := {text: lbl, size: state.textSize, bold: true, color: contentArgb, x: textX, w: textW, align: 0}
    } else {
        iconCfg := {text: glyph, font: state.IconFont, size: state.iconSize, color: contentArgb, x: 0, w: w}
        labelCfg := ""
    }

    return Gdip.RenderPill(state.MicGui.Hwnd, x, y, w, h, Gdip.HexToArgb(bgRgb), Gdip.BgrToArgb(brdBgr), alpha, GetCornerRadius(cfg, h), iconCfg, labelCfg)
}

SyncChatState(cfg, state, newCount) {
    if (state.unreadChatCount != newCount) {
        state.unreadChatCount := newCount
        if (cfg.ShowIndicator && cfg.ShowExtraHuds)
            ApplyChatAppearance(cfg, state)
    }
}

ApplyChatAppearance(cfg, state) {
    if (!IsObject(state.ChatGui))
        return false

    pos := ComputeHudLayout(state, state.savedX, state.savedY)
    hasUnread := (state.unreadChatCount > 0)
    bg := hasUnread ? state.colors.chatAlert : state.colors.chatClear
    brd := hasUnread ? state.colors.chatBorderAlert : state.colors.chatBorderClear
    ic := cfg.MonoIcon ? (hasUnread ? state.colors.chatIconAlert : state.colors.chatIconClear) : (hasUnread ? "FFFFFF" : "D1D5DB")
    contentArgb := Gdip.HexToArgb(ic)

    if (cfg.ShowText) {
        cIconW := Round(UIConstants.CHAT_ICON_W * cfg.IndicatorScale)
        cIconX := Round(UIConstants.CHAT_ICON_X * cfg.IndicatorScale)
        cTextX := cIconX + cIconW + Round(UIConstants.LABEL_GAP_X * cfg.IndicatorScale)
        cTextW := Max(UIConstants.MIN_TEXT_WIDTH, state.chatW - cTextX - Round(UIConstants.LABEL_GAP_X * cfg.IndicatorScale))
        lbl := hasUnread ? (state.unreadChatCount " NEW") : "CHAT"
        iconCfg := {text: Chr(0xE8BD), font: state.IconFont, size: state.subIconSize, color: contentArgb, x: cIconX, w: cIconW}
        labelCfg := {text: lbl, size: state.subTextSize, bold: true, color: contentArgb, x: cTextX, w: cTextW, align: 0}
    } else if (hasUnread) {
        iconCfg := ""
        labelCfg := {text: String(state.unreadChatCount), size: state.subTextSize, bold: true, color: contentArgb, x: 0, w: pos.chatW, align: 1}
    } else {
        iconCfg := {text: Chr(0xE8BD), font: state.IconFont, size: state.subIconSize, color: contentArgb, x: 0, w: pos.chatW}
        labelCfg := ""
    }

    return Gdip.RenderPill(state.ChatGui.Hwnd, pos.chatX, pos.chatY, pos.chatW, pos.chatH, Gdip.HexToArgb(bg), Gdip.BgrToArgb(brd), state.baseAlpha, GetCornerRadius(cfg, pos.chatH), iconCfg, labelCfg)
}

SyncStudioState(cfg, state, isEnabled) {
    if (state.studioModeActive != isEnabled) {
        state.studioModeActive := isEnabled
        if (cfg.ShowIndicator && cfg.ShowExtraHuds)
            ApplyStudioAppearance(cfg, state)
    }
}

ApplyStudioAppearance(cfg, state) {
    if (!IsObject(state.StudioGui))
        return false

    pos := ComputeHudLayout(state, state.savedX, state.savedY)
    bg := state.studioModeActive ? state.colors.studioOn : state.colors.studioOff
    brd := state.studioModeActive ? state.colors.studioBorderOn : state.colors.studioBorderOff
    ic := cfg.MonoIcon ? (state.studioModeActive ? state.colors.studioIconOn : state.colors.studioIconOff) : (state.studioModeActive ? "FFFFFF" : "D1D5DB")
    contentArgb := Gdip.HexToArgb(ic)

    if (cfg.ShowText) {
        stIconW := Round(UIConstants.STUDIO_ICON_W * cfg.IndicatorScale)
        stIconX := Round(UIConstants.STUDIO_ICON_X * cfg.IndicatorScale)
        stTextX := stIconX + stIconW
        stTextW := Max(UIConstants.MIN_TEXT_WIDTH, state.studioW - stTextX - Round(UIConstants.LABEL_GAP_X * cfg.IndicatorScale))
        stIconSize := Max(1, Round(UIConstants.STUDIO_ICON_SIZE_TEXT * cfg.IndicatorScale))
        stTextSize := Max(1, Round(UIConstants.STUDIO_TEXT_SIZE * cfg.IndicatorScale))
        iconCfg := {text: Chr(0xE7F4), font: state.IconFont, size: stIconSize, color: contentArgb, x: stIconX, w: stIconW}
        labelCfg := {text: "STUDIO", size: stTextSize, bold: true, color: contentArgb, x: stTextX, w: stTextW, align: 0}
    } else {
        stIconSize := Max(1, Round(UIConstants.STUDIO_ICON_SIZE_ONLY * cfg.IndicatorScale))
        iconCfg := {text: Chr(0xE7F4), font: state.IconFont, size: stIconSize, color: contentArgb, x: 0, w: pos.studioW}
        labelCfg := ""
    }

    return Gdip.RenderPill(state.StudioGui.Hwnd, pos.studioX, pos.studioY, pos.studioW, pos.studioH, Gdip.HexToArgb(bg), Gdip.BgrToArgb(brd), state.baseAlpha, GetCornerRadius(cfg, pos.studioH), iconCfg, labelCfg)
}

RenderAllHudPills(cfg, state) {
    ApplyMicAppearance(cfg, state)
    ApplyRecAppearance(cfg, state)
    ApplyChatAppearance(cfg, state)
    ApplyStudioAppearance(cfg, state)
    ApplySceneAppearance(cfg, state)
}

SyncSceneState(cfg, state, sceneName) {
    if (sceneName != "" && state.currentSceneName != sceneName) {
        state.currentSceneName := sceneName
        state.ComputeDimensions(cfg)
        if (cfg.ShowIndicator && cfg.ShowExtraHuds && !state.isDraggingHud) {
            UpdateHudLayout(state, state.savedX, state.savedY)
            RenderAllHudPills(cfg, state)
        }
        if state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn
            try state.refreshHelpFn.Call()
    }
}

ApplySceneAppearance(cfg, state) {
    if (!IsObject(state.SceneGui))
        return false

    pos := ComputeHudLayout(state, state.savedX, state.savedY)
    scPad := Round(UIConstants.SCENE_PAD_X * cfg.IndicatorScale)
    labelCfg := {
        text: state.currentSceneName,
        size: state.miniTextSize,
        bold: true,
        color: Gdip.HexToArgb("FFFFFF"),
        x: scPad,
        w: Max(UIConstants.MIN_TEXT_WIDTH, pos.sceneW - 2 * scPad),
        align: 1
    }
    return Gdip.RenderPill(state.SceneGui.Hwnd, pos.sceneX, pos.sceneY, pos.sceneW, pos.sceneH, Gdip.HexToArgb(state.colors.scene), Gdip.BgrToArgb(state.colors.sceneBorder), state.baseAlpha, GetCornerRadius(cfg, pos.sceneH), "", labelCfg)
}

SyncRecState(cfg, state, newState) {
    if (state.recState != newState) {
        state.recState := newState
        if (cfg.ShowIndicator && cfg.ShowExtraHuds)
            ApplyRecAppearance(cfg, state)
    }
}

ApplyRecAppearance(cfg, state) {
    if (!IsObject(state.RecGui))
        return false

    pos := ComputeHudLayout(state, state.savedX, state.savedY)
    if (state.recState == 1) {
        bg := state.colors.recActive, brd := state.colors.recBorderActive, ic := cfg.MonoIcon ? state.colors.recIconActive : "FFFFFF"
        glyph := Chr(0xE7C8), lbl := "REC"
    } else if (state.recState == 2) {
        bg := state.colors.recPaused, brd := state.colors.recBorderPaused, ic := cfg.MonoIcon ? state.colors.recIconPaused : "FFFFFF"
        glyph := Chr(0xE769), lbl := "PAUSED"
    } else {
        bg := state.colors.recOff, brd := state.colors.recBorderOff, ic := cfg.MonoIcon ? state.colors.recIconOff : "D1D5DB"
        glyph := Chr(0xE71A), lbl := "NOT REC"
    }
    contentArgb := Gdip.HexToArgb(ic)

    if (cfg.ShowText) {
        rIconW := Round(UIConstants.REC_ICON_W * cfg.IndicatorScale)
        rIconX := Round(UIConstants.REC_ICON_X * cfg.IndicatorScale)
        rTextX := rIconX + rIconW + Round(UIConstants.LABEL_GAP_X * cfg.IndicatorScale)
        rTextW := Max(UIConstants.MIN_TEXT_WIDTH, state.recW - rTextX - Round(UIConstants.LABEL_GAP_X * cfg.IndicatorScale))
        iconCfg := {text: glyph, font: state.IconFont, size: state.subIconSize, color: contentArgb, x: rIconX, w: rIconW}
        labelCfg := {text: lbl, size: state.subTextSize, bold: true, color: contentArgb, x: rTextX, w: rTextW, align: 0}
    } else {
        iconCfg := {text: glyph, font: state.IconFont, size: state.subIconSize, color: contentArgb, x: 0, w: pos.recW}
        labelCfg := ""
    }

    return Gdip.RenderPill(state.RecGui.Hwnd, pos.recX, pos.recY, pos.recW, pos.recH, Gdip.HexToArgb(bg), Gdip.BgrToArgb(brd), state.baseAlpha, GetCornerRadius(cfg, pos.recH), iconCfg, labelCfg)
}

SyncUIState(cfg, state, obsIsMuted) {
    if (state.isMuted != obsIsMuted) {
        state.isMuted := obsIsMuted
        cfg.IsMuted := obsIsMuted
        cfg.WriteBool("Settings", "IsMuted", state.isMuted)
        PlayMuteAnimation(cfg, state)
    }
}

; --- HUD APPEARANCE & CONFIG HELPERS ---
RefreshHudAppearance(cfg, state) {
    state.animSeq += 1
    state.baseAlpha := cfg.OpacityLevel
    state.currentAlpha := cfg.OpacityLevel
    state.breathDir := cfg.AggressivePulse ? -UIConstants.PULSE_STEP_AGGRESSIVE : -UIConstants.PULSE_STEP_NORMAL
    state.ComputeDimensions(cfg)
    UpdateHudLayout(state, state.savedX, state.savedY)
    UpdateHudVisibility(cfg, state)
    if (cfg.ShowIndicator && state.isMuted)
        SetTimer state.breathTimerFn, (cfg.AggressivePulse ? UIConstants.PULSE_INTERVAL_AGGRESSIVE : UIConstants.PULSE_INTERVAL_NORMAL)
    else
        SetTimer state.breathTimerFn, 0
}

SetThemeMode(cfg, themeMenu, mode, *) {
    cfg.ThemeMode := mode
    cfg.Write("Settings", "ThemeMode", mode)
    if IsObject(themeMenu) {
        themeMenu.Uncheck("Follow System")
        themeMenu.Uncheck("Dark Mode")
        themeMenu.Uncheck("Light Mode")
        if (mode = "Dark")
            themeMenu.Check("Dark Mode")
        else if (mode = "Light")
            themeMenu.Check("Light Mode")
        else
            themeMenu.Check("Follow System")
    }
    Theme.SetMode(mode)
}

SetScale(cfg, state, val, *) {
    cfg.IndicatorScale := val
    cfg.Write("Settings", "IndicatorScale", val)
    if IsObject(state)
        RefreshHudAppearance(cfg, state)
}

ResetAppearance(cfg, state := "", *) {
    cfg.ResetAppearance()
    if IsObject(state)
        RefreshHudAppearance(cfg, state)
}

ResetSettings(cfg, *) {
    cfg.DeleteFile()
    Reload()
}

ResetTrayPosition(cfg, state := "", *) {
    cfg.ResetPosition()
    if IsObject(state)
        RefreshHudAppearance(cfg, state)
}

; --- HUD CREATION, LAYOUT & STYLING ---
InitHUD(cfg, state, showWindows := true) {
    Gdip.Startup()
    state.ComputeDimensions(cfg)

    ; Create 5 GDI+ WS_EX_LAYERED (+E0x80000) HUD windows
    state.MicGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000 -DPIScale")
    state.RecGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000 -DPIScale")
    state.ChatGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000 -DPIScale")
    state.StudioGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000 -DPIScale")
    state.SceneGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000 -DPIScale")

    RenderAllHudPills(cfg, state)

    if (showWindows) {
        UpdateHudVisibility(cfg, state)
        if (cfg.ShowIndicator && state.isMuted)
            SetTimer state.breathTimerFn, (cfg.AggressivePulse ? UIConstants.PULSE_INTERVAL_AGGRESSIVE : UIConstants.PULSE_INTERVAL_NORMAL)
    }

    OnMessage(0x0003, WM_HUD_MOVE.Bind(state))
    OnMessage(0x0201, WM_LBUTTONDOWN.Bind(cfg, state))
    OnMessage(0x0205, WM_RBUTTONUP.Bind(state))
    OnMessage(0x02E0, WM_DPICHANGED.Bind(state))
}

ComputeHudLayout(state, anchorX, anchorY) {
    recH := state.HasProp("recHeight") ? state.recHeight : 34
    gap := state.HasProp("hudGap") ? state.hudGap : 6
    r3H := state.HasProp("row3Height") ? state.row3Height : 30
    recW := state.HasProp("recW") ? state.recW : 40
    chatW := state.HasProp("chatW") ? state.chatW : 34
    stuW := state.HasProp("studioW") ? state.studioW : 28
    scnW := state.HasProp("sceneW") ? state.sceneW : 46
    recY := anchorY - recH - gap
    row3Y := recY - r3H - gap
    return {
        micX: anchorX,
        micY: anchorY,
        micW: state.baseWidth,
        micH: state.baseHeight,
        recX: anchorX,
        recY: recY,
        recW: recW,
        recH: recH,
        chatX: anchorX + recW + gap,
        chatY: recY,
        chatW: chatW,
        chatH: recH,
        studioX: anchorX,
        studioY: row3Y,
        studioW: stuW,
        studioH: r3H,
        sceneX: anchorX + stuW + gap,
        sceneY: row3Y,
        sceneW: scnW,
        sceneH: r3H
    }
}

UpdateHudLayout(state, anchorX := "", anchorY := "", skipHwnd := 0) {
    if (anchorX = "" || anchorY = "") {
        if (IsObject(state.MicGui) && DllCall("IsWindowVisible", "Ptr", state.MicGui.Hwnd))
            try WinGetPos(&anchorX, &anchorY,,, state.MicGui.Hwnd)
        if (anchorX = "" || anchorY = "")
            anchorX := state.savedX, anchorY := state.savedY
    }
    state.savedX := anchorX, state.savedY := anchorY
    pos := ComputeHudLayout(state, anchorX, anchorY)
    if (IsObject(state.MicGui) && state.MicGui.Hwnd != skipHwnd)
        state.MicGui.Move(pos.micX, pos.micY, pos.micW, pos.micH)
    if (IsObject(state.RecGui) && state.RecGui.Hwnd != skipHwnd)
        state.RecGui.Move(pos.recX, pos.recY, pos.recW, pos.recH)
    if (IsObject(state.ChatGui) && state.ChatGui.Hwnd != skipHwnd)
        state.ChatGui.Move(pos.chatX, pos.chatY, pos.chatW, pos.chatH)
    if (IsObject(state.StudioGui) && state.StudioGui.Hwnd != skipHwnd)
        state.StudioGui.Move(pos.studioX, pos.studioY, pos.studioW, pos.studioH)
    if (IsObject(state.SceneGui) && state.SceneGui.Hwnd != skipHwnd)
        state.SceneGui.Move(pos.sceneX, pos.sceneY, pos.sceneW, pos.sceneH)
}

UpdateHudVisibility(cfg, state) {
    state.animSeq += 1
    if (!cfg.ShowIndicator) {
        if IsObject(state.MicGui)
            state.MicGui.Hide()
        if IsObject(state.RecGui)
            state.RecGui.Hide()
        if IsObject(state.ChatGui)
            state.ChatGui.Hide()
        if IsObject(state.StudioGui)
            state.StudioGui.Hide()
        if IsObject(state.SceneGui)
            state.SceneGui.Hide()
        return
    }

    state.currentAlpha := state.baseAlpha
    pos := ComputeHudLayout(state, state.savedX, state.savedY)
    if IsObject(state.MicGui) {
        ApplyMicAppearance(cfg, state)
        state.MicGui.Show(Format("NoActivate x{} y{} w{} h{}", pos.micX, pos.micY, pos.micW, pos.micH))
    }

    if (cfg.ShowExtraHuds && (cfg.EnableWS || cfg.EnableZoom)) {
        ApplyRecAppearance(cfg, state)
        state.RecGui.Show(Format("NoActivate x{} y{} w{} h{}", pos.recX, pos.recY, pos.recW, pos.recH))
        ApplyChatAppearance(cfg, state)
        state.ChatGui.Show(Format("NoActivate x{} y{} w{} h{}", pos.chatX, pos.chatY, pos.chatW, pos.chatH))
    } else {
        state.RecGui.Hide()
        state.ChatGui.Hide()
    }

    if (cfg.ShowExtraHuds && cfg.EnableWS) {
        ApplyStudioAppearance(cfg, state)
        state.StudioGui.Show(Format("NoActivate x{} y{} w{} h{}", pos.studioX, pos.studioY, pos.studioW, pos.studioH))
        ApplySceneAppearance(cfg, state)
        state.SceneGui.Show(Format("NoActivate x{} y{} w{} h{}", pos.sceneX, pos.sceneY, pos.sceneW, pos.sceneH))
    } else {
        state.StudioGui.Hide()
        state.SceneGui.Hide()
    }
}

; --- HUD ANIMATIONS ---
PlayMuteAnimation(cfg, state) {
    if (!IsObject(state.MicGui))
        return

    state.animSeq += 1
    mySeq := state.animSeq

    if (!cfg.ShowIndicator) {
        SetTimer state.breathTimerFn, 0
        state.currentAlpha := state.baseAlpha
        ApplyMicAppearance(cfg, state)
        return
    }

    SetTimer state.breathTimerFn, 0
    baseX := state.savedX
    baseY := state.savedY

    fadeStep := Round(state.baseAlpha / UIConstants.FADE_STEPS)
    widthIncrement := (cfg.ShowText ? UIConstants.POP_WIDTH_INC_TEXT : UIConstants.POP_WIDTH_INC_ICON) * cfg.IndicatorScale
    heightIncrement := UIConstants.POP_HEIGHT_INC * cfg.IndicatorScale
    prevMuted := !state.isMuted

    Loop UIConstants.FADE_STEPS {
        if (state.animSeq != mySeq || state.isDraggingHud)
            return
        state.currentAlpha -= fadeStep
        if (state.currentAlpha < 0)
            state.currentAlpha := 0

        popWidth := Round(state.baseWidth + (A_Index * widthIncrement))
        popHeight := Round(state.baseHeight + (A_Index * heightIncrement))
        offsetX := Round((popWidth - state.baseWidth) / 2)
        offsetY := Round((popHeight - state.baseHeight) / 2)

        ApplyMicAppearance(cfg, state, baseX - offsetX, baseY - offsetY, popWidth, popHeight, state.currentAlpha, prevMuted)
        Sleep UIConstants.FADE_SLEEP_MS
    }

    Loop UIConstants.FADE_STEPS {
        if (state.animSeq != mySeq || state.isDraggingHud)
            return
        state.currentAlpha += fadeStep
        if (state.currentAlpha > state.baseAlpha)
            state.currentAlpha := state.baseAlpha

        popWidth := Round((state.baseWidth + (UIConstants.FADE_STEPS * widthIncrement)) - (A_Index * widthIncrement))
        popHeight := Round((state.baseHeight + (UIConstants.FADE_STEPS * heightIncrement)) - (A_Index * heightIncrement))
        offsetX := Round((popWidth - state.baseWidth) / 2)
        offsetY := Round((popHeight - state.baseHeight) / 2)

        ApplyMicAppearance(cfg, state, baseX - offsetX, baseY - offsetY, popWidth, popHeight, state.currentAlpha, state.isMuted)
        Sleep UIConstants.FADE_SLEEP_MS
    }

    if (state.animSeq != mySeq)
        return

    state.currentAlpha := state.baseAlpha
    ApplyMicAppearance(cfg, state, state.savedX, state.savedY, state.baseWidth, state.baseHeight, state.currentAlpha)

    if (state.isMuted && cfg.ShowIndicator && (!state.HasOwnProp("activeHost") || state.obsConnected)) {
        state.breathDir := cfg.AggressivePulse ? -UIConstants.PULSE_STEP_AGGRESSIVE : -UIConstants.PULSE_STEP_NORMAL
        SetTimer state.breathTimerFn, (cfg.AggressivePulse ? UIConstants.PULSE_INTERVAL_AGGRESSIVE : UIConstants.PULSE_INTERVAL_NORMAL)
    } else {
        SetTimer state.breathTimerFn, 0
    }
}

BreathingAnimation(cfg, state) {
    if (!IsObject(state.MicGui) || state.isDraggingHud)
        return

    minRatio := cfg.AggressivePulse ? UIConstants.PULSE_MIN_RATIO_AGGRESSIVE : UIConstants.PULSE_MIN_RATIO_NORMAL
    lowerBound := Round(state.baseAlpha * minRatio)
    stepAmount := cfg.AggressivePulse ? UIConstants.PULSE_STEP_AGGRESSIVE : UIConstants.PULSE_STEP_NORMAL

    state.currentAlpha += state.breathDir
    if (state.currentAlpha <= lowerBound) {
        state.currentAlpha := lowerBound
        state.breathDir := stepAmount
    } else if (state.currentAlpha >= state.baseAlpha) {
        state.currentAlpha := state.baseAlpha
        state.breathDir := -stepAmount
    }
    if (!Gdip.SetLayeredAlpha(state.MicGui.Hwnd, state.currentAlpha))
        ApplyMicAppearance(cfg, state)
}

; --- HUD DRAG & DPI HANDLERS ---
AnchorFromHwnd(state, hwnd, X, Y) {
    if (IsObject(state.RecGui) && hwnd == state.RecGui.Hwnd) {
        Y := Y + state.recHeight + state.hudGap
    } else if (IsObject(state.ChatGui) && hwnd == state.ChatGui.Hwnd) {
        X := X - state.recW - state.hudGap
        Y := Y + state.recHeight + state.hudGap
    } else if (IsObject(state.StudioGui) && hwnd == state.StudioGui.Hwnd) {
        Y := Y + state.row3Height + state.hudGap + state.recHeight + state.hudGap
    } else if (IsObject(state.SceneGui) && hwnd == state.SceneGui.Hwnd) {
        X := X - state.studioW - state.hudGap
        Y := Y + state.row3Height + state.hudGap + state.recHeight + state.hudGap
    }
    return {x: X, y: Y}
}

DragSyncTick(state) {
    if (!state.isDraggingHud || !state.activeDragHwnd)
        return
    try {
        WinGetPos(&curX, &curY,,, "ahk_id " state.activeDragHwnd)
        anchor := AnchorFromHwnd(state, state.activeDragHwnd, curX, curY)
        UpdateHudLayout(state, anchor.x, anchor.y, state.activeDragHwnd)
    }
}

WM_HUD_MOVE(state, wParam, lParam, msg, hwnd) {
    if (state.isDraggingHud && hwnd == state.activeDragHwnd)
        DragSyncTick(state)
}

WM_LBUTTONDOWN(cfg, state, wParam, lParam, msg, hwnd) {
    isHudHwnd := (IsObject(state.MicGui) && hwnd == state.MicGui.Hwnd)
        || (IsObject(state.RecGui) && hwnd == state.RecGui.Hwnd)
        || (IsObject(state.ChatGui) && hwnd == state.ChatGui.Hwnd)
        || (IsObject(state.StudioGui) && hwnd == state.StudioGui.Hwnd)
        || (IsObject(state.SceneGui) && hwnd == state.SceneGui.Hwnd)
    if (!isHudHwnd)
        return

    prevX := state.savedX
    prevY := state.savedY
    state.activeDragHwnd := hwnd
    state.isDraggingHud := true
    SetTimer state.dragTimerFn, UIConstants.DRAG_SYNC_INTERVAL_MS
    PostMessage(0xA1, 2,,, "ahk_id " hwnd)
    KeyWait "LButton"
    state.isDraggingHud := false
    state.activeDragHwnd := 0
    SetTimer state.dragTimerFn, 0

    WinGetPos(&X, &Y,,, "ahk_id " hwnd)
    anchor := AnchorFromHwnd(state, hwnd, X, Y)

    if (anchor.x != prevX || anchor.y != prevY) {
        cfg.savedX := anchor.x
        cfg.savedY := anchor.y
        cfg.Write("Position", "X", anchor.x)
        cfg.Write("Position", "Y", anchor.y)
    }
    UpdateHudLayout(state, anchor.x, anchor.y)
    state.currentAlpha := state.baseAlpha
    ApplyMicAppearance(cfg, state)
    if (cfg.ShowIndicator && state.isMuted)
        SetTimer state.breathTimerFn, (cfg.AggressivePulse ? UIConstants.PULSE_INTERVAL_AGGRESSIVE : UIConstants.PULSE_INTERVAL_NORMAL)
}

WM_RBUTTONUP(state, wParam, lParam, msg, hwnd) {
    isHudHwnd := (IsObject(state.MicGui) && hwnd == state.MicGui.Hwnd)
        || (IsObject(state.RecGui) && hwnd == state.RecGui.Hwnd)
        || (IsObject(state.ChatGui) && hwnd == state.ChatGui.Hwnd)
        || (IsObject(state.StudioGui) && hwnd == state.StudioGui.Hwnd)
        || (IsObject(state.SceneGui) && hwnd == state.SceneGui.Hwnd)
    if (isHudHwnd)
        A_TrayMenu.Show()
}

WM_DPICHANGED(state, wParam, lParam, msg, hwnd) {
    if (!IsObject(state.MicGui) || hwnd != state.MicGui.Hwnd)
        return
    newLeft := NumGet(lParam, 0, "Int")
    newTop := NumGet(lParam, 4, "Int")
    UpdateHudLayout(state, newLeft, newTop)
}
