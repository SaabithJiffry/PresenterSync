; ==============================================================================
; Module: GUI_Config.ahk
; Description: UIConstants, Config & OverlayState classes, Settings GUIs, HUD layout & animations
; ==============================================================================

#Include "%A_LineFile%\..\Gdip.ahk"
#Include "%A_LineFile%\..\OBS_Network.ahk"

class UIConstants {
    static APP_VERSION := "3.0.0"

    ; --- Base HUD Dimensions & Ratios ---
    static BASE_WIDTH_TEXT := 168
    static BASE_WIDTH_ICON := 80
    static BASE_HEIGHT := 40
    static HUD_GAP := 6
    static MIN_HUD_GAP := 2
    static REC_HEIGHT := 34
    static ROW3_HEIGHT := 30
    static ROW4_HEIGHT := 26
    static REC_WIDTH_RATIO := 0.54
    static STUDIO_WIDTH_RATIO := 0.38
    static STREAM_WIDTH_RATIO := 0.54
    static SCREEN_MARGIN_X := 20
    static SCREEN_MARGIN_Y := 20
    static SCREEN_MIN_PAD := 10
    static SNAP_THRESHOLD_PX := 14
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
    static ICON_OFFSET_X := 18
    static MIC_TEXT_W := 96
    static TEXT_OFFSET_X := 56
    static REC_ICON_W := 18
    static REC_ICON_X := 8
    static CHAT_ICON_W := 18
    static CHAT_ICON_X := 8
    static STUDIO_ICON_W := 18
    static STUDIO_ICON_X := 8
    static STREAM_ICON_W := 16
    static STREAM_ICON_X := 7
    static VCAM_ICON_W := 16
    static VCAM_ICON_X := 7
    static SCENE_PAD_X := 6
    static LABEL_GAP_X := 6

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
    static PUSH_TO_MUTE_HOLD_MS := 350
    static VOICE_METER_INTERVAL_MS := 65
    static STREAM_POLL_INTERVAL_MS := 5000
    static STREAM_CONGESTION_WARN := 0.35
    static DODGE_POLL_INTERVAL_MS := 80
    static DODGE_ALPHA := 45
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

    static COLOR_STREAM_OFF := "374151"
    static ICON_STREAM_OFF := "9CA3AF"
    static COLOR_STREAM_LIVE := "E11D48"
    static ICON_STREAM_LIVE := "881337"
    static COLOR_STREAM_WARN := "EA580C"
    static ICON_STREAM_WARN := "7C2D12"

    static COLOR_VCAM_OFF := "374151"
    static ICON_VCAM_OFF := "9CA3AF"
    static COLOR_VCAM_ON := "0D9488"
    static ICON_VCAM_ON := "134E4A"

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

    static RgbHexToBgrInt(rgbHex) {
        h := RegExReplace(Trim(String(rgbHex)), "^(#|0x)", "")
        if (StrLen(h) != 6)
            return 0
        return Integer("0x" SubStr(h, 5, 2) SubStr(h, 3, 2) SubStr(h, 1, 2))
    }

    static _MakePalette(liveBg, liveIc, muteBg, muteIc, recOffBg, recOffIc, recActBg, recActIc, recPauBg, recPauIc, stOffBg, stOffIc, stOnBg, stOnIc, scBg, scTxt, chClrBg, chClrIc, chAltBg, chAltIc, strmOffBg := "374151", strmOffIc := "9CA3AF", strmLiveBg := "E11D48", strmLiveIc := "881337", strmWarnBg := "EA580C", strmWarnIc := "7C2D12", vcOffBg := "374151", vcOffIc := "9CA3AF", vcOnBg := "0D9488", vcOnIc := "134E4A") {
        return {
            live: liveBg, muted: muteBg,
            borderLive: UIConstants.RgbHexToBgrInt(liveBg), borderMuted: UIConstants.RgbHexToBgrInt(muteBg),
            iconLive: liveIc, iconMuted: muteIc,
            recOff: recOffBg, recBorderOff: UIConstants.RgbHexToBgrInt(recOffBg), recIconOff: recOffIc,
            recActive: recActBg, recBorderActive: UIConstants.RgbHexToBgrInt(recActBg), recIconActive: recActIc,
            recPaused: recPauBg, recBorderPaused: UIConstants.RgbHexToBgrInt(recPauBg), recIconPaused: recPauIc,
            studioOff: stOffBg, studioBorderOff: UIConstants.RgbHexToBgrInt(stOffBg), studioIconOff: stOffIc,
            studioOn: stOnBg, studioBorderOn: UIConstants.RgbHexToBgrInt(stOnBg), studioIconOn: stOnIc,
            scene: scBg, sceneBorder: UIConstants.RgbHexToBgrInt(scBg), sceneText: scTxt,
            chatClear: chClrBg, chatBorderClear: UIConstants.RgbHexToBgrInt(chClrBg), chatIconClear: chClrIc,
            chatAlert: chAltBg, chatBorderAlert: UIConstants.RgbHexToBgrInt(chAltBg), chatIconAlert: chAltIc,
            streamOff: strmOffBg, streamBorderOff: UIConstants.RgbHexToBgrInt(strmOffBg), streamIconOff: strmOffIc,
            streamLive: strmLiveBg, streamBorderLive: UIConstants.RgbHexToBgrInt(strmLiveBg), streamIconLive: strmLiveIc,
            streamWarn: strmWarnBg, streamBorderWarn: UIConstants.RgbHexToBgrInt(strmWarnBg), streamIconWarn: strmWarnIc,
            vcamOff: vcOffBg, vcamBorderOff: UIConstants.RgbHexToBgrInt(vcOffBg), vcamIconOff: vcOffIc,
            vcamOn: vcOnBg, vcamBorderOn: UIConstants.RgbHexToBgrInt(vcOnBg), vcamIconOn: vcOnIc
        }
    }

    static GetColorPalette(presetName := "Standard") {
        switch NormalizeHudColorPreset(presetName) {
            case "Colorblind Safe":
                return UIConstants._MakePalette(
                    "0072B2", "002A45", "D55E00", "4A1E00",
                    "374151", "9CA3AF", "D55E00", "4A1E00", "E69F00", "4A3200",
                    "374151", "9CA3AF", "CC79A7", "4A1D38",
                    "1E293B", "F8FAFC",
                    "374151", "9CA3AF", "56B4E9", "0C3B54",
                    "374151", "9CA3AF", "D55E00", "4A1E00", "E69F00", "4A3200",
                    "374151", "9CA3AF", "009E73", "003828"
                )
            case "OLED Stealth":
                return UIConstants._MakePalette(
                    "0F2E22", "34D399", "3B0D14", "FB7185",
                    "141417", "71717A", "3B0D14", "F87171", "2E1F05", "FBBF24",
                    "141417", "71717A", "23163D", "C084FC",
                    "09090B", "E4E4E7",
                    "141417", "71717A", "13233A", "60A5FA",
                    "141417", "71717A", "3B0D14", "FB7185", "381F06", "FDBA74",
                    "141417", "71717A", "0B2E2B", "2DD4BF"
                )
            case "Broadcast Tally":
                return UIConstants._MakePalette(
                    "16A34A", "052E16", "DC2626", "450A0A",
                    "1F2937", "9CA3AF", "B91C1C", "450A0A", "EA580C", "431407",
                    "1F2937", "9CA3AF", "6D28D9", "2E1065",
                    "111827", "F9FAFB",
                    "1F2937", "9CA3AF", "0284C7", "082F49",
                    "1F2937", "9CA3AF", "E11D48", "4C0519", "D97706", "451A03",
                    "1F2937", "9CA3AF", "0D9488", "042F2E"
                )
            case "Cyber Ocean":
                return UIConstants._MakePalette(
                    "06B6D4", "083344", "EC4899", "500724",
                    "1E293B", "94A3B8", "F43F5E", "4C0519", "F59E0B", "451A03",
                    "1E293B", "94A3B8", "6366F1", "1E1B4B",
                    "0F172A", "E0F2FE",
                    "1E293B", "94A3B8", "0EA5E9", "082F49",
                    "1E293B", "94A3B8", "EC4899", "500724", "F97316", "431407",
                    "1E293B", "94A3B8", "14B8A6", "042F2E"
                )
            default:
                return UIConstants._MakePalette(
                    UIConstants.COLOR_LIVE, UIConstants.ICON_LIVE,
                    UIConstants.COLOR_MUTED, UIConstants.ICON_MUTED,
                    UIConstants.COLOR_REC_OFF, UIConstants.ICON_REC_OFF,
                    UIConstants.COLOR_REC_ACTIVE, UIConstants.ICON_REC_ACTIVE,
                    UIConstants.COLOR_REC_PAUSED, UIConstants.ICON_REC_PAUSED,
                    UIConstants.COLOR_STUDIO_OFF, UIConstants.ICON_STUDIO_OFF,
                    UIConstants.COLOR_STUDIO_ON, UIConstants.ICON_STUDIO_ON,
                    UIConstants.COLOR_SCENE, "FFFFFF",
                    UIConstants.COLOR_CHAT_CLEAR, UIConstants.ICON_CHAT_CLEAR,
                    UIConstants.COLOR_CHAT_ALERT, UIConstants.ICON_CHAT_ALERT,
                    UIConstants.COLOR_STREAM_OFF, UIConstants.ICON_STREAM_OFF,
                    UIConstants.COLOR_STREAM_LIVE, UIConstants.ICON_STREAM_LIVE,
                    UIConstants.COLOR_STREAM_WARN, UIConstants.ICON_STREAM_WARN,
                    UIConstants.COLOR_VCAM_OFF, UIConstants.ICON_VCAM_OFF,
                    UIConstants.COLOR_VCAM_ON, UIConstants.ICON_VCAM_ON
                )
        }
    }
}

GetHudColorPresetNames() {
    return ["Standard", "Colorblind Safe", "OLED Stealth", "Broadcast Tally", "Cyber Ocean"]
}

NormalizeHudColorPreset(name) {
    cleaned := StrLower(Trim(String(name)))
    for pName in GetHudColorPresetNames() {
        if (StrLower(pName) = cleaned)
            return pName
    }
    return "Standard"
}

class AudioMeter {
    static _enum := ""
    static _meter := ""
    static _nextRetryTick := 0

    static NormalizePeak(rawPeak) {
        p := Min(1.0, Max(0.0, Float(rawPeak)))
        return (p > 0.005) ? Min(1.0, Sqrt(p)) : 0.0
    }

    static Reset() {
        this._meter := ""
        this._enum := ""
        this._nextRetryTick := 0
    }

    static GetPeak() {
        try {
            if (!IsObject(this._meter)) {
                if (A_TickCount < this._nextRetryTick)
                    return 0.0
                if (!IsObject(this._enum))
                    this._enum := ComObject("{BCDE0395-E52F-467C-8E3D-C4579291692E}", "{A95664D2-9614-4F35-A746-DE8DB63617E6}")
                pDev := 0
                try ComCall(4, this._enum, "Int", 1, "Int", 2, "Ptr*", &pDev)
                if (!pDev)
                    try ComCall(4, this._enum, "Int", 1, "Int", 0, "Ptr*", &pDev)
                if (!pDev) {
                    this._nextRetryTick := A_TickCount + 5000
                    return 0.0
                }
                dev := ComValue(13, pDev)
                iidBuf := Buffer(16, 0)
                DllCall("ole32\CLSIDFromString", "WStr", "{C02216F6-8C67-4B5B-9D00-D008E73E0064}", "Ptr", iidBuf)
                pMeter := 0
                ComCall(3, dev, "Ptr", iidBuf, "UInt", 23, "Ptr", 0, "Ptr*", &pMeter)
                if (!pMeter) {
                    this._nextRetryTick := A_TickCount + 5000
                    return 0.0
                }
                this._meter := ComValue(13, pMeter)
            }
            peak := 0.0
            ComCall(3, this._meter, "Float*", &peak)
            return AudioMeter.NormalizePeak(peak)
        } catch {
            this._meter := ""
            this._nextRetryTick := A_TickCount + 3000
            return 0.0
        }
    }
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
        if (role = "tabButton" || role = "tabText")
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
            if (role = "tabText")
                ctrl.Opt(isDark ? ("+Background" UIConstants.DARK_SURFACE " c" UIConstants.DARK_TEXT) : ("+Background" UIConstants.LIGHT_SURFACE " c" UIConstants.LIGHT_TEXT))
            else
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

        inTab := (IsObject(ctrl) && ctrl.HasOwnProp("_inTab") && ctrl._inTab)
        parentBgBgr := parentDark ? (inTab ? UIConstants.DARK_SURFACE_BGR : UIConstants.DARK_BG_BGR) : (inTab ? UIConstants.LIGHT_SURFACE_BGR : UIConstants.LIGHT_BG_BGR)
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
    TeamsMuteHotkey := "^+m"
    MeetMuteHotkey := "^d"
    ConferencingApp := "Zoom"
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
    HudColorPreset := "Standard"
    ShowText := false
    MonoIcon := false
    SleekCorners := false
    AggressivePulse := false
    EnableAudioCue := false
    EnableMuteToast := false
    ShowVoiceMeter := true
    ShowRecTimer := true
    ShowStreamHud := true
    EnableHudClickActions := true
    EnableMagneticSnap := true
    HudClickThrough := false
    HudAutoDodge := false
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
    EnablePushToMute := false

    PptHotkey := "^F12"
    WsHotkey := "!F12"
    ZoomHotkey := "^!F12"
    IndHotkey := "^+F12"
    ExitHotkey := "!+F12"
    SuspendHotkey := "^!+F12"
    HwMuteHotkey := "b"

    RemoteNetworkMode := "LAN"
    InternetPairingCode := ""
    ActiveProfile := "Default"
    StartWithWindows := false

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
        this.TeamsMuteHotkey := this.Read("Settings", "TeamsMuteHotkey", "^+m")
        this.MeetMuteHotkey := this.Read("Settings", "MeetMuteHotkey", "^d")
        this.ConferencingApp := NormalizeConferencingApp(this.Read("Settings", "ConferencingApp", "Zoom"))
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
        this.targetMicName := Trim(this.Read("Settings", "TargetMicName", "Mic/Aux"))
        if (this.targetMicName = "")
            this.targetMicName := "Mic/Aux"

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
        this.HudColorPreset := NormalizeHudColorPreset(this.Read("Settings", "HudColorPreset", "Standard"))
        this.ShowText := this.ReadBool("Settings", "ShowText")
        this.MonoIcon := this.ReadBool("Settings", "MonoIcon")
        this.SleekCorners := this.ReadBool("Settings", "SleekCorners")
        this.AggressivePulse := this.ReadBool("Settings", "AggressivePulse")
        this.EnableAudioCue := this.ReadBool("Settings", "EnableAudioCue", false)
        this.EnableMuteToast := this.ReadBool("Settings", "EnableMuteToast", false)
        this.ShowVoiceMeter := this.ReadBool("Settings", "ShowVoiceMeter", true)
        this.ShowRecTimer := this.ReadBool("Settings", "ShowRecTimer", true)
        this.ShowStreamHud := this.ReadBool("Settings", "ShowStreamHud", true)
        this.EnableHudClickActions := this.ReadBool("Settings", "EnableHudClickActions", true)
        this.EnableMagneticSnap := this.ReadBool("Settings", "EnableMagneticSnap", true)
        this.HudClickThrough := this.ReadBool("Settings", "HudClickThrough", false)
        this.HudAutoDodge := this.ReadBool("Settings", "HudAutoDodge", false)
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
        this.EnablePushToMute := this.ReadBool("Pointer", "EnablePushToMute", false)

        this.PptHotkey := this.Read("Settings", "PptHotkey", "^F12")
        this.WsHotkey := this.Read("Settings", "WsHotkey", "!F12")
        this.ZoomHotkey := this.Read("Settings", "ZoomHotkey", "^!F12")
        this.IndHotkey := this.Read("Settings", "IndHotkey", "^+F12")
        this.ExitHotkey := this.Read("Settings", "ExitHotkey", "!+F12")
        this.SuspendHotkey := this.Read("Settings", "SuspendHotkey", "^!+F12")
        this.HwMuteHotkey := this.Read("Settings", "HwMuteHotkey", "b")

        rawNetMode := StrLower(Trim(this.Read("Settings", "RemoteNetworkMode", "LAN")))
        this.RemoteNetworkMode := (rawNetMode = "internet") ? "Internet" : "LAN"
        this.InternetPairingCode := Trim(this.Read("Settings", "InternetPairingCode", ""))
        if (this.InternetPairingCode = "") {
            this.InternetPairingCode := GenerateInternetPairingCode()
            this.Write("Settings", "InternetPairingCode", this.InternetPairingCode)
        }
        profName := this.NormalizeProfileName(this.Read("Settings", "ActiveProfile", "Default"))
        this.ActiveProfile := (profName != "") ? profName : "Default"
        this.StartWithWindows := this.ReadBool("Settings", "StartWithWindows", false)

        this.savedX := this.Read("Position", "X", "Default")
        this.savedY := this.Read("Position", "Y", "Default")
    }

    ResetAppearance() {
        this.ShowExtraHuds := true
        this.ThemeMode := "System"
        this.HudColorPreset := "Standard"
        this.ShowText := false
        this.MonoIcon := false
        this.SleekCorners := false
        this.AggressivePulse := false
        this.EnableAudioCue := false
        this.EnableMuteToast := false
        this.ShowVoiceMeter := true
        this.ShowRecTimer := true
        this.ShowStreamHud := true
        this.EnableHudClickActions := true
        this.EnableMagneticSnap := true
        this.HudClickThrough := false
        this.HudAutoDodge := false
        this.OpacityLevel := UIConstants.OPACITY_FROSTED
        this.IndicatorScale := 1.0
        this.Write("Settings", "ShowExtraHuds", 1)
        this.Write("Settings", "ThemeMode", "System")
        this.Write("Settings", "HudColorPreset", "Standard")
        this.Write("Settings", "ShowText", 0)
        this.Write("Settings", "MonoIcon", 0)
        this.Write("Settings", "SleekCorners", 0)
        this.Write("Settings", "AggressivePulse", 0)
        this.Write("Settings", "EnableAudioCue", 0)
        this.Write("Settings", "EnableMuteToast", 0)
        this.Write("Settings", "ShowVoiceMeter", 1)
        this.Write("Settings", "ShowRecTimer", 1)
        this.Write("Settings", "ShowStreamHud", 1)
        this.Write("Settings", "EnableHudClickActions", 1)
        this.Write("Settings", "EnableMagneticSnap", 1)
        this.Write("Settings", "HudClickThrough", 0)
        this.Write("Settings", "HudAutoDodge", 0)
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

    NormalizeProfileName(name) {
        clean := Trim(String(name))
        clean := RegExReplace(clean, '[\|\[\]=`r`n`t]', "")
        return SubStr(Trim(clean), 1, 48)
    }

    GetProfileFieldSpecs() {
        return [
            { sec: "Settings", key: "AudioRoutingMode", prop: "AudioRoutingMode", kind: "int" },
            { sec: "Settings", key: "ObsHotkey", prop: "ObsMuteHotkey", kind: "str" },
            { sec: "Settings", key: "ObsRecHotkey", prop: "ObsRecHotkey", kind: "str" },
            { sec: "Settings", key: "ObsPauseHotkey", prop: "ObsPauseHotkey", kind: "str" },
            { sec: "Settings", key: "ZoomMuteHotkey", prop: "ZoomMuteHotkey", kind: "str" },
            { sec: "Settings", key: "TeamsMuteHotkey", prop: "TeamsMuteHotkey", kind: "str" },
            { sec: "Settings", key: "MeetMuteHotkey", prop: "MeetMuteHotkey", kind: "str" },
            { sec: "Settings", key: "ConferencingApp", prop: "ConferencingApp", kind: "str" },
            { sec: "Settings", key: "ZoomRecHotkey", prop: "ZoomRecHotkey", kind: "str" },
            { sec: "Settings", key: "ZoomPauseHotkey", prop: "ZoomPauseHotkey", kind: "str" },
            { sec: "Settings", key: "TargetMicName", prop: "targetMicName", kind: "str" },
            { sec: "Settings", key: "EnablePPT", prop: "EnablePPT", kind: "bool" },
            { sec: "Settings", key: "EnableMicOnly", prop: "EnableMicOnly", kind: "bool" },
            { sec: "Settings", key: "EnableWS", prop: "EnableWS", kind: "bool" },
            { sec: "Settings", key: "EnableZoom", prop: "EnableZoom", kind: "bool" },
            { sec: "Settings", key: "ShowIndicator", prop: "ShowIndicator", kind: "bool" },
            { sec: "Settings", key: "ShowExtraHuds", prop: "ShowExtraHuds", kind: "bool" },
            { sec: "Settings", key: "ThemeMode", prop: "ThemeMode", kind: "str" },
            { sec: "Settings", key: "HudColorPreset", prop: "HudColorPreset", kind: "str" },
            { sec: "Settings", key: "ShowText", prop: "ShowText", kind: "bool" },
            { sec: "Settings", key: "MonoIcon", prop: "MonoIcon", kind: "bool" },
            { sec: "Settings", key: "SleekCorners", prop: "SleekCorners", kind: "bool" },
            { sec: "Settings", key: "AggressivePulse", prop: "AggressivePulse", kind: "bool" },
            { sec: "Settings", key: "EnableAudioCue", prop: "EnableAudioCue", kind: "bool" },
            { sec: "Settings", key: "EnableMuteToast", prop: "EnableMuteToast", kind: "bool" },
            { sec: "Settings", key: "ShowVoiceMeter", prop: "ShowVoiceMeter", kind: "bool" },
            { sec: "Settings", key: "ShowRecTimer", prop: "ShowRecTimer", kind: "bool" },
            { sec: "Settings", key: "ShowStreamHud", prop: "ShowStreamHud", kind: "bool" },
            { sec: "Settings", key: "EnableHudClickActions", prop: "EnableHudClickActions", kind: "bool" },
            { sec: "Settings", key: "EnableMagneticSnap", prop: "EnableMagneticSnap", kind: "bool" },
            { sec: "Settings", key: "HudClickThrough", prop: "HudClickThrough", kind: "bool" },
            { sec: "Settings", key: "HudAutoDodge", prop: "HudAutoDodge", kind: "bool" },
            { sec: "Settings", key: "OpacityLevel", prop: "OpacityLevel", kind: "int" },
            { sec: "Settings", key: "IndicatorScale", prop: "IndicatorScale", kind: "float" },
            { sec: "Settings", key: "RemoteNetworkMode", prop: "RemoteNetworkMode", kind: "str" },
            { sec: "Settings", key: "HwMuteHotkey", prop: "HwMuteHotkey", kind: "str" },
            { sec: "Pointer", key: "CatchArrows", prop: "CatchArrows", kind: "bool" },
            { sec: "Pointer", key: "CatchPg", prop: "CatchPg", kind: "bool" },
            { sec: "Pointer", key: "CatchSpace", prop: "CatchSpace", kind: "bool" },
            { sec: "Pointer", key: "CatchEnter", prop: "CatchEnter", kind: "bool" },
            { sec: "Pointer", key: "CatchTab", prop: "CatchTab", kind: "bool" },
            { sec: "Pointer", key: "CatchEsc", prop: "CatchEsc", kind: "bool" },
            { sec: "Pointer", key: "EnablePushToMute", prop: "EnablePushToMute", kind: "bool" },
            { sec: "Position", key: "X", prop: "savedX", kind: "str" },
            { sec: "Position", key: "Y", prop: "savedY", kind: "str" }
        ]
    }

    GetProfileNames() {
        raw := Trim(this.Read("Profiles", "Names", "Default"))
        names := []
        seen := Map()
        for part in StrSplit(raw, "|") {
            clean := this.NormalizeProfileName(part)
            if (clean != "" && !seen.Has(StrLower(clean))) {
                seen[StrLower(clean)] := true
                names.Push(clean)
            }
        }
        if (!seen.Has("default"))
            names.InsertAt(1, "Default")
        return names
    }

    WriteProfileList(names) {
        joined := ""
        for idx, n in names
            joined .= (idx > 1 ? "|" : "") n
        this.Write("Profiles", "Names", joined)
    }

    WriteSnapshotToSection(sectionName) {
        this.Write(sectionName, "__Exists", "1")
        for spec in this.GetProfileFieldSpecs() {
            val := this.%spec.prop%
            if (spec.kind = "bool")
                val := val ? "1" : "0"
            this.Write(sectionName, spec.sec "_" spec.key, val)
        }
    }

    SaveProfile(profileName) {
        clean := this.NormalizeProfileName(profileName)
        if (clean = "")
            return false
        if (StrLower(clean) != "default" && this.Read("Profile:Default", "__Exists", "") != "1") {
            baseCfg := Config(this.ConfigFile)
            baseCfg.WriteSnapshotToSection("Profile:Default")
        }

        names := this.GetProfileNames()
        canonical := clean
        found := false
        for idx, n in names {
            if (StrLower(n) = StrLower(clean)) {
                canonical := n
                found := true
                break
            }
        }
        if (!found)
            names.Push(canonical)
        this.WriteProfileList(names)
        this.WriteSnapshotToSection("Profile:" canonical)
        this.ActiveProfile := canonical
        this.Write("Settings", "ActiveProfile", canonical)
        return true
    }

    ApplyProfile(profileName, state := "") {
        clean := this.NormalizeProfileName(profileName)
        if (clean = "")
            return false
        canonical := ""
        for n in this.GetProfileNames() {
            if (StrLower(n) = StrLower(clean)) {
                canonical := n
                break
            }
        }
        if (canonical = "")
            return false

        secName := "Profile:" canonical
        hasSnapshot := (this.Read(secName, "__Exists", "") = "1")
        if (!hasSnapshot && StrLower(canonical) != "default")
            return false

        if (hasSnapshot) {
            for spec in this.GetProfileFieldSpecs() {
                v := this.Read(secName, spec.sec "_" spec.key, "__MISSING__")
                if (v != "__MISSING__")
                    this.Write(spec.sec, spec.key, v)
            }
        }

        this.Write("Settings", "ActiveProfile", canonical)
        this.Load()

        SyncTelemetryBackendsFromConfig(this, state)
        return true
    }

    DeleteProfile(profileName) {
        clean := this.NormalizeProfileName(profileName)
        if (clean = "" || StrLower(clean) = "default")
            return false
        names := this.GetProfileNames()
        kept := []
        removed := false
        targetName := ""
        for n in names {
            if (StrLower(n) = StrLower(clean)) {
                removed := true
                targetName := n
            } else {
                kept.Push(n)
            }
        }
        if (!removed)
            return false
        try IniDelete(this.ConfigFile, "Profile:" targetName)
        this.WriteProfileList(kept)
        if (StrLower(this.ActiveProfile) = StrLower(targetName)) {
            this.ActiveProfile := "Default"
            this.Write("Settings", "ActiveProfile", "Default")
        }
        return true
    }
}

class OverlayState {
    obsWs := ""
    obsConnected := false
    relayWs := ""
    relayConnected := false
    zoomConnected := false
    IsSyncing := false
    syncSource := ""
    zoomLastMuted := -1
    zoomRecGraceUntil := 0
    zoomSawRecControl := false

    isMuted := false
    recState := 0
    recElapsedSec := 0
    studioModeActive := false
    currentSceneName := "Scene"
    sceneList := []
    unreadChatCount := 0
    streamState := 0
    streamCongestion := 0.0
    streamSkippedFrames := 0
    streamPrevSkipped := 0
    streamReconnecting := false
    vcamActive := false

    sceneMarqueeOffset := 0
    sceneMarqueePhase := "pause_start"
    sceneMarqueeTicks := 0
    sceneMarqueeMaxOffset := 0
    sceneMarqueeTextW := 0
    sceneMarqueeFontPt := 9.0
    sceneMarqueeTimerFn := ""

    baseAlpha := 220
    currentAlpha := 220
    breathDir := -5
    animSeq := 0
    voicePeak := 0.0

    isDraggingHud := false
    activeDragHwnd := 0
    isAutoDodged := false

    dragTimerFn := ""
    breathTimerFn := ""
    autoDodgeTimerFn := ""
    voiceMeterTimerFn := ""
    recTimerFn := ""
    streamTimerFn := ""
    obsTimerFn := ""
    relayTimerFn := ""
    zoomTimerFn := ""
    releaseSyncTimerFn := ""
    rebuildTrayFn := ""
    refreshHelpFn := ""
    refreshHudFn := ""
    rebindHotkeysFn := ""
    triggerMuteFn := ""

    MicGui := ""
    RecGui := ""
    ChatGui := ""
    StudioGui := ""
    SceneGui := ""
    StreamGui := ""
    VCamGui := ""

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
    row4Height := 26
    streamW := 40
    vcamW := 34
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
        chatIconAlert: UIConstants.ICON_CHAT_ALERT,
        streamOff: UIConstants.COLOR_STREAM_OFF,
        streamBorderOff: UIConstants.RgbHexToBgrInt(UIConstants.COLOR_STREAM_OFF),
        streamIconOff: UIConstants.ICON_STREAM_OFF,
        streamLive: UIConstants.COLOR_STREAM_LIVE,
        streamBorderLive: UIConstants.RgbHexToBgrInt(UIConstants.COLOR_STREAM_LIVE),
        streamIconLive: UIConstants.ICON_STREAM_LIVE,
        streamWarn: UIConstants.COLOR_STREAM_WARN,
        streamBorderWarn: UIConstants.RgbHexToBgrInt(UIConstants.COLOR_STREAM_WARN),
        streamIconWarn: UIConstants.ICON_STREAM_WARN,
        vcamOff: UIConstants.COLOR_VCAM_OFF,
        vcamBorderOff: UIConstants.RgbHexToBgrInt(UIConstants.COLOR_VCAM_OFF),
        vcamIconOff: UIConstants.ICON_VCAM_OFF,
        vcamOn: UIConstants.COLOR_VCAM_ON,
        vcamBorderOn: UIConstants.RgbHexToBgrInt(UIConstants.COLOR_VCAM_ON),
        vcamIconOn: UIConstants.ICON_VCAM_ON
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
        this.voiceMeterTimerFn := VoiceMeterTick.Bind(cfg, this)
        this.recTimerFn := RecTimerTick.Bind(cfg, this)
        this.streamTimerFn := PollStreamStatus.Bind(cfg, this)
        this.autoDodgeTimerFn := AutoDodgeTick.Bind(cfg, this)
        this.obsTimerFn := ConnectToOBS.Bind(cfg, this)
        this.relayTimerFn := ConnectHostInternetRelay.Bind(cfg, this)
        this.sceneMarqueeTimerFn := SceneMarqueeTick.Bind(cfg, this)
        this.zoomTimerFn := ZoomStateMonitor.Bind(cfg, this)
        this.releaseSyncTimerFn := ReleaseSyncLock.Bind(this)
        this.refreshHudFn := RefreshHudAppearance.Bind(cfg, this)

        this.ComputeDimensions(cfg)
    }

    ComputeDimensions(cfg) {
        this.colors := UIConstants.GetColorPalette(cfg.HasOwnProp("HudColorPreset") ? cfg.HudColorPreset : "Standard")
        this.baseWidth := Round((cfg.ShowText ? UIConstants.BASE_WIDTH_TEXT : UIConstants.BASE_WIDTH_ICON) * cfg.IndicatorScale)
        this.baseHeight := Round(UIConstants.BASE_HEIGHT * cfg.IndicatorScale)
        this.hudGap := Max(UIConstants.MIN_HUD_GAP, Round(UIConstants.HUD_GAP * cfg.IndicatorScale))
        this.recHeight := Round(UIConstants.REC_HEIGHT * cfg.IndicatorScale)
        this.row3Height := Round(UIConstants.ROW3_HEIGHT * cfg.IndicatorScale)
        this.row4Height := Round(UIConstants.ROW4_HEIGHT * cfg.IndicatorScale)

        this.iconSize := Max(1, Round(UIConstants.MIC_ICON_SIZE * cfg.IndicatorScale))
        this.textSize := Max(1, Round(UIConstants.MIC_TEXT_SIZE * cfg.IndicatorScale))
        this.subIconSize := Max(1, Round(UIConstants.SUB_ICON_SIZE * cfg.IndicatorScale))
        this.subTextSize := Max(1, Round(UIConstants.SUB_TEXT_SIZE * cfg.IndicatorScale))
        this.miniTextSize := Max(1, Round(UIConstants.MINI_TEXT_SIZE * cfg.IndicatorScale))

        minRecW := Round((this.baseWidth - this.hudGap) * UIConstants.REC_WIDTH_RATIO)
        if (cfg.ShowText && (!cfg.HasOwnProp("ShowRecTimer") || cfg.ShowRecTimer) && this.recState != 0) {
            rIconW := Round(UIConstants.REC_ICON_W * cfg.IndicatorScale)
            rIconX := Round(UIConstants.REC_ICON_X * cfg.IndicatorScale)
            rGap := Round(UIConstants.LABEL_GAP_X * cfg.IndicatorScale)
            rSampleTxt := ((this.recState == 2) ? "PAUSED " : "REC ") FormatElapsedShort(this.recElapsedSec)
            reqRecW := rIconX + rIconW + rGap + Gdip.MeasureTextWidth(rSampleTxt, "Segoe UI", this.subTextSize, 1) + rIconX
            cIconW := Round(UIConstants.CHAT_ICON_W * cfg.IndicatorScale)
            cIconX := Round(UIConstants.CHAT_ICON_X * cfg.IndicatorScale)
            minChatW := cIconX + cIconW + rGap + Gdip.MeasureTextWidth("CHAT", "Segoe UI", this.subTextSize, 1) + cIconX
            maxRecW := Max(minRecW, this.baseWidth - this.hudGap - minChatW)
            this.recW := Min(maxRecW, Max(minRecW, reqRecW))
        } else {
            this.recW := minRecW
        }
        this.chatW := this.baseWidth - this.hudGap - this.recW

        minStudioW := Round((this.baseWidth - this.hudGap) * UIConstants.STUDIO_WIDTH_RATIO)
        if (cfg.ShowText) {
            stIconW := Round(UIConstants.STUDIO_ICON_W * cfg.IndicatorScale)
            stIconX := Round(UIConstants.STUDIO_ICON_X * cfg.IndicatorScale)
            stGap := Round(UIConstants.LABEL_GAP_X * cfg.IndicatorScale)
            stTextSize := Max(1, Round(UIConstants.STUDIO_TEXT_SIZE * cfg.IndicatorScale))
            reqStudioW := stIconX + stIconW + stGap + Gdip.MeasureTextWidth("STUDIO", "Segoe UI", stTextSize, 1) + stIconX
            this.studioW := Max(minStudioW, reqStudioW)
        } else {
            this.studioW := minStudioW
        }

        this.sceneW := Max(UIConstants.MIN_TEXT_WIDTH, this.baseWidth - this.hudGap - this.studioW)

        minStreamW := Round((this.baseWidth - this.hudGap) * UIConstants.STREAM_WIDTH_RATIO)
        if (cfg.ShowText) {
            strmIconW := Round(UIConstants.STREAM_ICON_W * cfg.IndicatorScale)
            strmIconX := Round(UIConstants.STREAM_ICON_X * cfg.IndicatorScale)
            strmGap := Round(UIConstants.LABEL_GAP_X * cfg.IndicatorScale)
            strmSampleTxt := (this.streamState == 2) ? "WARN" : ((this.streamState == 1) ? "LIVE" : "OFF")
            reqStreamW := strmIconX + strmIconW + strmGap + Gdip.MeasureTextWidth(strmSampleTxt, "Segoe UI", this.subTextSize, 1) + strmIconX
            vcIconW := Round(UIConstants.VCAM_ICON_W * cfg.IndicatorScale)
            vcIconX := Round(UIConstants.VCAM_ICON_X * cfg.IndicatorScale)
            minVCamW := vcIconX + vcIconW + strmGap + Gdip.MeasureTextWidth("VCAM", "Segoe UI", this.subTextSize, 1) + vcIconX
            maxStreamW := Max(minStreamW, this.baseWidth - this.hudGap - minVCamW)
            this.streamW := Min(maxStreamW, Max(minStreamW, reqStreamW))
        } else {
            this.streamW := minStreamW
        }
        this.vcamW := Max(UIConstants.MIN_TEXT_WIDTH, this.baseWidth - this.hudGap - this.streamW)

        extraRow2 := (cfg.ShowExtraHuds && (cfg.EnableWS || cfg.EnableZoom))
        extraRow3 := (cfg.ShowExtraHuds && cfg.EnableWS)
        extraRow4 := (extraRow3 && (!cfg.HasOwnProp("ShowStreamHud") || cfg.ShowStreamHud))
        maxRowW := this.baseWidth
        if (extraRow2)
            maxRowW := Max(maxRowW, this.recW + this.hudGap + this.chatW)
        if (extraRow3)
            maxRowW := Max(maxRowW, this.studioW + this.hudGap + this.sceneW)
        if (extraRow4)
            maxRowW := Max(maxRowW, this.streamW + this.hudGap + this.vcamW)
        extraTopPad := (extraRow2 ? (this.recHeight + this.hudGap) : 0) + (extraRow3 ? (this.row3Height + this.hudGap) : 0) + (extraRow4 ? (this.row4Height + this.hudGap) : 0)

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
    dlg.MarginX := 20
    dlg.MarginY := 16
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
            if (el.HasOwnProp("required") && el.required) {
                rawVal := String(ctrls[el.id].Value)
                isPw := el.HasOwnProp("opts") && InStr(el.opts, "Password")
                if (isPw ? (rawVal = "") : (Trim(rawVal) = "")) {
                    dlg.Opt("+OwnDialogs")
                    errTitle := el.HasOwnProp("errorTitle") ? el.errorTitle : "Error"
                    errMsg := el.HasOwnProp("errorMsg") ? el.errorMsg : "Shortcuts cannot be left blank."
                    MsgBox(errMsg, errTitle, "Icon!")
                    return false
                }
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
        {type: "Text", id: "obsLbl", opts: "w280 y+15", text: "OBS Mute Shortcut" (cfg.EnableWS ? " (Optional with WebSocket):" : ":")},
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
        . "2. CHOOSE SAME ROUTER (LAN) OR DIFFERENT NETWORKS (INTERNET)`r`n"
        . "- Right-click the PresenterSync tray icon (or any HUD pill) and open Settings -> Remote Companion Info....`r`n"
        . "- Same Router (LAN - Default): Click 'Copy Universal String to Clipboard' (includes .local mDNS + active Ethernet / Wi-Fi IPs, works across 2.4 GHz & 5 GHz SSIDs on the same router).`r`n"
        . "- Different Networks (Internet): Switch Network Mode to 'Different Networks (Internet)' and copy the Internet Pairing Code (e.g., PS-XXXX-XXXX) to bridge over HTTPS/WSS when devices are on separate routers or hotspots.`r`n`r`n"
        . "3. CONNECT PRESENTER SYNC REMOTE (SMART BOARD / 2ND PC)`r`n"
        . "- Copy PresenterSync_Remote.exe to the Smart Board (or run PresenterSync_Remote.ahk).`r`n"
        . "- Select matching Network Mode (Same Router LAN or Different Networks Internet), paste the Universal String or Internet Pairing Code, enter your OBS WebSocket Password, and match Exact Audio Source Name (default: Mic/Aux).`r`n"
        . "- Click 'Test Connection' to verify reachability, then click Connect & Start.`r`n`r`n"
        . "4. CLICKER CONTROL, REMOTE SHORTCUTS & SAFE MANUAL CLOSE`r`n"
        . "- Clicker Mute: Press your presenter mute key (default: b) to toggle OBS mic. Toggle Pointer Mute Control ON/OFF anytime on the Remote PC with Ctrl+F12 (when OFF, the HUD still displays live mic status without muting on click).`r`n"
        . "- Remote Exit & Safe Manual Close: Press Alt+Shift+F12 on the Remote PC to exit, or use 'Close Remote Companion...' in the Primary tray menu to send a confirmed shutdown signal.`r`n"
        . "- Troubleshooting: If Auth Failed (OBS Code 4009), check your password in Change OBS Connection...; if Mic Not Found, match exact Audio Source Name casing in OBS Audio Mixer."
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
    if (ShouldEnableHostInternetRelay(cfg)) {
        relayStat := (IsObject(state) && state.HasOwnProp("relayConnected") && state.relayConnected) ? "Relay Connected" : "Relay Standby"
        modeTag := (cfg.RemoteNetworkMode = "Internet") ? "Internet Mode" : "Smart Mode 2 Relay Bridge"
        remoteHost := modeTag " (" cfg.InternetPairingCode " - " relayStat ")"
    } else {
        remoteHost := A_ComputerName ".local:4455 (LAN)  |  WS Auth: " (cfg.obsPassword != "" ? "Configured" : "None")
    }
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
    btnRemInfo.OnEvent("Click", (*) => ShowRemoteCompanionInfo(cfg, state))
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
    aboutGui.MarginX := 18
    aboutGui.MarginY := 16
    Theme.ApplyToWindow(aboutGui)
    Theme.NamedWindows["AboutWindow"] := aboutGui

    iconSource := A_IsCompiled ? A_ScriptFullPath : (FileExist(A_ScriptDir "\PresenterSync.ico") ? A_ScriptDir "\PresenterSync.ico" : A_LineFile "\..\..\PresenterSync.ico")

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
    gitBtn := aboutGui.Add("Button", "w170 x18 y+16 h30", "GitHub Repo")
    Theme.RegisterControl(aboutGui, gitBtn, "Button")
    gitBtn.OnEvent("Click", (*) => Run("https://github.com/SaabithJiffry/PresenterSync/"))

    updBtn := aboutGui.Add("Button", "w170 x+14 yp h30", "Check for Updates")
    Theme.RegisterControl(aboutGui, updBtn, "Button")
    updBtn.OnEvent("Click", (*) => CheckForUpdates(UIConstants.APP_VERSION, "", false))

    helpBtn := aboutGui.Add("Button", "w170 x18 y+8 h30", "Help & Guide")
    Theme.RegisterControl(aboutGui, helpBtn, "Button")
    CloseAbout(*) {
        Theme.UnregisterWindow(aboutGui, "AboutWindow")
        aboutGui.Destroy()
    }
    if IsObject(cfg)
        helpBtn.OnEvent("Click", (*) => (CloseAbout(), ShowHelpWindow(cfg, state)))
    else
        helpBtn.Enabled := false

    closeBtn := aboutGui.Add("Button", "w170 x+14 yp h30 Default", "Close")
    Theme.RegisterControl(aboutGui, closeBtn, "Button")
    closeBtn.OnEvent("Click", CloseAbout)
    aboutGui.OnEvent("Close", CloseAbout)
    aboutGui.OnEvent("Escape", CloseAbout)

    aboutGui.Show("AutoSize Center")
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

SetConferencingApp(cfg, state, appName, *) {
    norm := NormalizeConferencingApp(appName)
    cfg.ConferencingApp := norm
    cfg.Write("Settings", "ConferencingApp", norm)
    if (IsObject(state)) {
        state.zoomConnected := false
        state.zoomLastMuted := -1
        state.zoomSawRecControl := false
        if (state.HasOwnProp("rebuildTrayFn") && state.rebuildTrayFn)
            try state.rebuildTrayFn.Call()
        if (state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn)
            try state.refreshHelpFn.Call()
    }
    return norm
}

ChangeZoomShortcutsUI(cfg, *) {
    SaveZoomHk(values, ctrls, dlg) {
        cfg.Write("Settings", "ZoomMuteHotkey", values["mute"])
        if (values.Has("teamsMute") && values["teamsMute"] != "")
            cfg.Write("Settings", "TeamsMuteHotkey", values["teamsMute"])
        if (values.Has("meetMute") && values["meetMute"] != "")
            cfg.Write("Settings", "MeetMuteHotkey", values["meetMute"])
        cfg.Write("Settings", "ZoomRecHotkey", values["rec"] != "" ? values["rec"] : "!r")
        cfg.Write("Settings", "ZoomPauseHotkey", values["pause"] != "" ? values["pause"] : "!p")
        Reload()
    }

    elements := [
        {type: "Text", opts: "w300", text: "Zoom Mute Shortcut (Default Alt+A):"},
        {type: "Hotkey", id: "mute", opts: "w300", value: cfg.ZoomMuteHotkey, required: true, errorMsg: "Zoom Mute shortcut cannot be empty."},
        {type: "Text", opts: "w300 y+8", text: "Microsoft Teams Mute Shortcut (Default Ctrl+Shift+M):"},
        {type: "Hotkey", id: "teamsMute", opts: "w300", value: cfg.TeamsMuteHotkey},
        {type: "Text", opts: "w300 y+8", text: "Google Meet Mute Shortcut (Default Ctrl+D):"},
        {type: "Hotkey", id: "meetMute", opts: "w300", value: cfg.MeetMuteHotkey},
        {type: "Text", opts: "w300 y+8", text: "Zoom Start/Stop Recording (Default Alt+R):"},
        {type: "Hotkey", id: "rec", opts: "w300", value: cfg.ZoomRecHotkey},
        {type: "Text", opts: "w300 y+8", text: "Zoom Pause/Resume Recording (Default Alt+P):"},
        {type: "Hotkey", id: "pause", opts: "w300", value: cfg.ZoomPauseHotkey}
    ]

    return BuildSettingsWindow("Edit Conferencing Shortcuts", elements, SaveZoomHk, {
        saveBtnText: "Save & Restart",
        saveBtnOpts: "w300 h32 Default y+14"
    })
}

SetRoutingMode(cfg, mode, *) {
    cfg.Write("Settings", "AudioRoutingMode", mode)
    if ((mode == 2 || mode == 3) && cfg.ZoomMuteHotkey = "")
        cfg.Write("Settings", "ZoomMuteHotkey", "!a")
    if (mode == 2 && (!cfg.HasOwnProp("InternetPairingCode") || cfg.InternetPairingCode = "")) {
        cfg.InternetPairingCode := GenerateInternetPairingCode()
        cfg.Write("Settings", "InternetPairingCode", cfg.InternetPairingCode)
    }
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
    dlg.MarginX := 20
    dlg.MarginY := 18
    Theme.ApplyToWindow(dlg)
    Theme.NamedWindows["Edit Pointer Mute Button"] := dlg

    dlg.SetFont("s10 w600", Theme.UiFont)
    Theme.RegisterControl(dlg, dlg.Add("Text", "xm w280", "Presentation Clicker Mute Button"), "Text")
    dlg.SetFont("s9 w400", Theme.UiFont)
    Theme.RegisterControl(dlg, dlg.Add("Text", "xm w280 y+4", "Press a button on your clicker, or click the box to type a custom key name:"), "Text", "muted")

    dlg.SetFont("s12 w700", Theme.UiFont)
    editKey := dlg.Add("Edit", "xm w280 h32 y+12 Center", currentKey)
    Theme.RegisterControl(dlg, editKey, "Edit", "accent")

    dlg.SetFont("s9 w400", Theme.UiFont)
    statusTxt := dlg.Add("Text", "xm w280 y+8 Center", "Listening for clicker input...")
    Theme.RegisterControl(dlg, statusTxt, "Text", "muted")

    dlg.SetFont("s10 w400", Theme.UiFont)
    btnSave := dlg.Add("Button", "xm w280 h34 y+14 Default", saveBtnLabel)
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
    testerGui.MarginX := 20
    testerGui.MarginY := 18
    Theme.ApplyToWindow(testerGui)
    Theme.NamedWindows["PointerTester"] := testerGui

    testerGui.SetFont("s10 w400 norm", Theme.UiFont)
    Theme.RegisterControl(testerGui, testerGui.Add("Text", "xm w280 Center", "Press any button on your clicker:"), "Text", "muted")

    testerGui.SetFont("s14 w700 norm", Theme.UiFont)
    keyDisplay := testerGui.Add("Text", "xm w280 h38 y+12 Center +0x200", "Listening...")
    Theme.RegisterControl(testerGui, keyDisplay, "Text", "accent")

    testerGui.SetFont("s10 w400 norm", Theme.UiFont)
    btn := testerGui.Add("Button", "xm w280 h34 y+16 Default", "Close")
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

    testerGui.Show("AutoSize Center")
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
        scheme := "ws"
        hasExplicitScheme := false
        if RegExMatch(clean, "i)^(wss|ws|https|http)://(.*)$", &sm) {
            rawScheme := StrLower(sm[1])
            scheme := (rawScheme = "wss" || rawScheme = "https") ? "wss" : "ws"
            clean := sm[2]
            hasExplicitScheme := true
        }
        clean := RTrim(clean, " ")
        if (clean = "")
            continue
        path := "/"
        if RegExMatch(clean, "^([^/]+)(/.*)$", &pm) {
            clean := pm[1]
            path := pm[2]
        } else {
            clean := RTrim(clean, "/")
        }
        host := clean
        port := (hasExplicitScheme && scheme = "wss") ? "443" : defPort
        if RegExMatch(clean, "^([^:]+):(.*)$", &m) {
            host := Trim(m[1])
            rawP := Trim(m[2])
            if (IsInteger(rawP) && Integer(rawP) >= 1 && Integer(rawP) <= 65535)
                port := String(Integer(rawP))
        }
        if (host = "")
            continue
        rawKey := (scheme = "wss" ? ("wss://" host ":" port (path != "/" ? path : "")) : (host ":" port (path != "/" ? path : "")))
        urlStr := scheme "://" host ":" port path
        if (!seen.Has(urlStr)) {
            seen[urlStr] := true
            endpoints.Push({host: host, port: port, scheme: scheme, path: path, url: urlStr, raw: rawKey})
        }
    }
    if (endpoints.Length == 0) {
        urlStr := "ws://127.0.0.1:" defPort "/"
        endpoints.Push({host: "127.0.0.1", port: defPort, scheme: "ws", path: "/", url: urlStr, raw: "127.0.0.1:" defPort})
    }
    return endpoints
}

SetRemoteNetworkMode(cfg, state, mode, *) {
    norm := (StrLower(Trim(mode)) = "internet") ? "Internet" : "LAN"
    cfg.RemoteNetworkMode := norm
    cfg.Write("Settings", "RemoteNetworkMode", norm)
    if (norm = "Internet" && cfg.InternetPairingCode = "") {
        cfg.InternetPairingCode := GenerateInternetPairingCode()
        cfg.Write("Settings", "InternetPairingCode", cfg.InternetPairingCode)
    }
    if IsObject(state) {
        UpdateHostInternetRelay(cfg, state)
        if state.HasOwnProp("rebuildTrayFn") && state.rebuildTrayFn
            try state.rebuildTrayFn.Call()
        if state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn
            try state.refreshHelpFn.Call()
    }
    TrayTip("Remote Network Mode: " (norm = "Internet" ? "Different Networks (Internet)" : "Same Router (LAN)"), "PresenterSync", 1)
}

PromptCloseRemoteCompanion(cfg, state := "", *) {
    existing := Theme.FocusExistingWindow("Close Remote Companion")
    if IsObject(existing)
        return existing

    Theme.AcquireSuspend()

    dlg := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "Close Remote Companion")
    dlg._closed := false
    dlg.MarginX := 20
    dlg.MarginY := 18
    Theme.ApplyToWindow(dlg)
    Theme.NamedWindows["Close Remote Companion"] := dlg

    dlg.SetFont("s10 w600", Theme.UiFont)
    Theme.RegisterControl(dlg, dlg.Add("Text", "xm w340", "Turn Off Secondary Remote Companion?"), "Text")

    modeDesc := (cfg.RemoteNetworkMode = "Internet")
        ? "Different Networks (Internet Relay - " cfg.InternetPairingCode ")"
        : "Same Router (LAN via OBS WebSocket)"
    dlg.SetFont("s9 w400", Theme.UiFont)
    Theme.RegisterControl(dlg, dlg.Add("Text", "xm w340 y+6", "This will send an immediate close signal to shut down PresenterSync Remote on your secondary laptop / Smart Board.`n`nActive Channel: " modeDesc), "Text", "muted")

    dlg.SetFont("s10 w400", Theme.UiFont)
    btnConfirm := dlg.Add("Button", "xm w164 h34 y+16 Default", "Turn Off Secondary")
    btnCancel := dlg.Add("Button", "x+12 yp w164 h34", "Cancel")
    Theme.RegisterControl(dlg, btnConfirm, "Button", "accent")
    Theme.RegisterControl(dlg, btnCancel, "Button")

    Cleanup(*) {
        if (dlg._closed)
            return
        dlg._closed := true
        Theme.UnregisterWindow(dlg, "Close Remote Companion")
        Theme.ReleaseSuspend()
        dlg.Destroy()
    }

    ConfirmClose(*) {
        sent := SendCloseRemoteSignal(cfg, state)
        Cleanup()
        if (sent) {
            TrayTip("Close signal sent to PresenterSync Remote.", "Remote Companion", 1)
        } else {
            TrayTip("Close signal queued. Ensure OBS WebSocket or Internet Relay is connected.", "Remote Companion", 2)
        }
    }

    btnConfirm.OnEvent("Click", ConfirmClose)
    btnCancel.OnEvent("Click", Cleanup)
    dlg.OnEvent("Close", Cleanup)
    dlg.OnEvent("Escape", Cleanup)

    dlg.Show("AutoSize Center")
    return dlg
}

ShowRemoteCompanionInfo(cfg, state := "", *) {
    existing := Theme.FocusExistingWindow("Remote Companion Connection Info")
    if IsObject(existing)
        return existing

    if (cfg.InternetPairingCode = "") {
        cfg.InternetPairingCode := GenerateInternetPairingCode()
        cfg.Write("Settings", "InternetPairingCode", cfg.InternetPairingCode)
    }

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
    dlg.MarginX := 20
    dlg.MarginY := 16
    Theme.ApplyToWindow(dlg)
    Theme.NamedWindows["Remote Companion Connection Info"] := dlg

    dlg.SetFont("s10 w600", Theme.UiFont)
    Theme.RegisterControl(dlg, dlg.Add("Text", "xm w360", "Host Details for PresenterSync Remote"), "Text")
    dlg.SetFont("s9 w400", Theme.UiFont)
    Theme.RegisterControl(dlg, dlg.Add("Text", "xm w360 y+4", "Configure how your secondary device (Smart Board / Laptop) connects:"), "Text", "muted")

    dlg.SetFont("s9 w600", Theme.UiFont)
    Theme.RegisterControl(dlg, dlg.Add("Text", "xm w360 y+10", "Remote Network Mode:"), "Text")
    dlg.SetFont("s9 w400", Theme.UiFont)
    netChoice := (cfg.RemoteNetworkMode = "Internet") ? 2 : 1
    ddlNetMode := dlg.Add("DropDownList", "xm w360 Choose" netChoice, [
        "1: Same Router / Local Wi-Fi or Ethernet (LAN - Default)",
        "2: Different Networks / Over the Internet (WAN Relay)"
    ])
    Theme.RegisterControl(dlg, ddlNetMode, "DropDownList")

    dlg.SetFont("s9 w600", Theme.UiFont)
    Theme.RegisterControl(dlg, dlg.Add("Text", "xm w360 y+10", "Different Networks - Internet Pairing Code:"), "Text")
    dlg.SetFont("s10 w700", Theme.UiFont)
    editPair := dlg.Add("Edit", "xm w180 h28 ReadOnly Center", cfg.InternetPairingCode)
    Theme.RegisterControl(dlg, editPair, "Edit", "accent")
    dlg.SetFont("s9 w400", Theme.UiFont)
    btnCopyPair := dlg.Add("Button", "x+8 yp w100 h28", "Copy Code")
    btnNewPair := dlg.Add("Button", "x+8 yp w64 h28", "New")
    Theme.RegisterControl(dlg, btnCopyPair, "Button", "accent")
    Theme.RegisterControl(dlg, btnNewPair, "Button")

    ResetCopyPairBtn(*) {
        if (!dlg._closed && WinExist("ahk_id " dlg.Hwnd))
            btnCopyPair.Text := "Copy Code"
    }
    btnCopyPair.OnEvent("Click", (*) => (
        A_Clipboard := cfg.InternetPairingCode,
        btnCopyPair.Text := "✓ Copied!",
        SetTimer(ResetCopyPairBtn, -1800),
        TrayTip("Internet Pairing Code copied to clipboard.", "Copied!", 1)
    ))
    btnNewPair.OnEvent("Click", (*) => (
        cfg.InternetPairingCode := GenerateInternetPairingCode(),
        cfg.Write("Settings", "InternetPairingCode", cfg.InternetPairingCode),
        editPair.Value := cfg.InternetPairingCode,
        (IsObject(state) ? UpdateHostInternetRelay(cfg, state) : 0),
        TrayTip("Generated new Internet Pairing Code: " cfg.InternetPairingCode, "Pairing Code Updated", 1)
    ))

    OnNetModeChanged(*) {
        newMode := (ddlNetMode.Value == 2) ? "Internet" : "LAN"
        SetRemoteNetworkMode(cfg, state, newMode)
    }
    ddlNetMode.OnEvent("Change", OnNetModeChanged)

    dlg.SetFont("s9 w600", Theme.UiFont)
    Theme.RegisterControl(dlg, dlg.Add("Text", "xm w360 y+10", "Same Router (LAN) - Computer Name (mDNS):"), "Text")
    dlg.SetFont("s9 w400", Theme.UiFont)
    editHost := dlg.Add("Edit", "xm w360 ReadOnly -Wrap", A_ComputerName ".local")
    Theme.RegisterControl(dlg, editHost, "Edit")

    ipListText := ""
    for ep in endpoints.details {
        ipListText .= (ep.isVirtual ? "[Virtual] " : "[LAN] ") ep.name ": " ep.ip "`n"
    }
    if (ipListText != "") {
        dlg.SetFont("s9 w600", Theme.UiFont)
        Theme.RegisterControl(dlg, dlg.Add("Text", "xm w360 y+8", "Detected Local IP Addresses:"), "Text")
        dlg.SetFont("s9 w400", Theme.UiFont)
        editIps := dlg.Add("Edit", "xm w360 r2 ReadOnly", RTrim(ipListText, "`n"))
        Theme.RegisterControl(dlg, editIps, "Edit")
    }

    dlg.SetFont("s9 w600", Theme.UiFont)
    Theme.RegisterControl(dlg, dlg.Add("Text", "xm w360 y+8", "Universal Connection String (Multi-Candidate LAN):"), "Text")
    dlg.SetFont("s9 w400", Theme.UiFont)
    editUniv := dlg.Add("Edit", "xm w360 ReadOnly -Wrap", universalString)
    Theme.RegisterControl(dlg, editUniv, "Edit")

    btnCopy := dlg.Add("Button", "xm w360 h30 y+8", "Copy Universal String to Clipboard")
    Theme.RegisterControl(dlg, btnCopy, "Button", "accent")
    ResetCopyBtn(*) {
        if (!dlg._closed && WinExist("ahk_id " dlg.Hwnd))
            btnCopy.Text := "Copy Universal String to Clipboard"
    }
    btnCopy.OnEvent("Click", (*) => (
        A_Clipboard := universalString,
        btnCopy.Text := "✓ Copied to Clipboard!",
        SetTimer(ResetCopyBtn, -1800),
        TrayTip("Universal connection string copied to clipboard.", "Copied!", 1)
    ))

    statusLine := "OBS Port: 4455  |  Password: " (cfg.obsPassword != "" ? "Configured" : "None") "  |  Mic: " cfg.targetMicName
    Theme.RegisterControl(dlg, dlg.Add("Text", "xm w360 y+10 Center", statusLine), "Text", "muted")

    btnCloseRemote := dlg.Add("Button", "xm w176 h32 y+10", "Close Remote Companion...")
    btnClose := dlg.Add("Button", "x+8 yp w176 h32 Default", "Close")
    Theme.RegisterControl(dlg, btnCloseRemote, "Button")
    Theme.RegisterControl(dlg, btnClose, "Button")

    Cleanup(*) {
        if (dlg._closed)
            return
        dlg._closed := true
        Theme.UnregisterWindow(dlg, "Remote Companion Connection Info")
        dlg.Destroy()
    }

    btnCloseRemote.OnEvent("Click", (*) => PromptCloseRemoteCompanion(cfg, state))
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
    if (!IsObject(state) || !state.HasOwnProp("MicGui") || !IsGuiValid(state.MicGui))
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

    meterLevel := (!mutedState && cfg.HasOwnProp("ShowVoiceMeter") && cfg.ShowVoiceMeter && state.HasOwnProp("voicePeak")) ? state.voicePeak : 0.0
    return Gdip.RenderPill(state.MicGui.Hwnd, x, y, w, h, Gdip.HexToArgb(bgRgb), Gdip.BgrToArgb(brdBgr), alpha, GetCornerRadius(cfg, h), iconCfg, labelCfg, meterLevel)
}

SyncChatState(cfg, state, newCount) {
    if (state.unreadChatCount != newCount) {
        state.unreadChatCount := newCount
        if (cfg.ShowIndicator && cfg.ShowExtraHuds)
            ApplyChatAppearance(cfg, state)
    }
}

ApplyChatAppearance(cfg, state) {
    if (!IsObject(state) || !state.HasOwnProp("ChatGui") || !IsGuiValid(state.ChatGui))
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
        cTextW := Max(UIConstants.MIN_TEXT_WIDTH, state.chatW - cTextX - cIconX)
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
    if (!IsObject(state) || !state.HasOwnProp("StudioGui") || !IsGuiValid(state.StudioGui))
        return false

    pos := ComputeHudLayout(state, state.savedX, state.savedY)
    bg := state.studioModeActive ? state.colors.studioOn : state.colors.studioOff
    brd := state.studioModeActive ? state.colors.studioBorderOn : state.colors.studioBorderOff
    ic := cfg.MonoIcon ? (state.studioModeActive ? state.colors.studioIconOn : state.colors.studioIconOff) : (state.studioModeActive ? "FFFFFF" : "D1D5DB")
    contentArgb := Gdip.HexToArgb(ic)

    if (cfg.ShowText) {
        stIconW := Round(UIConstants.STUDIO_ICON_W * cfg.IndicatorScale)
        stIconX := Round(UIConstants.STUDIO_ICON_X * cfg.IndicatorScale)
        stGap := Round(UIConstants.LABEL_GAP_X * cfg.IndicatorScale)
        stTextX := stIconX + stIconW + stGap
        stTextW := Max(UIConstants.MIN_TEXT_WIDTH, state.studioW - stTextX - stIconX)
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

ToggleStreamHud(cfg, state := "", *) {
    ToggleBoolSetting(cfg, state, "ShowStreamHud")
    if (IsObject(state) && state.HasOwnProp("refreshHudFn") && state.refreshHudFn)
        try state.refreshHudFn.Call()
}

SyncStreamState(cfg, state, newState, congestion := 0.0, skippedFrames := -1, reconnecting := false) {
    prevState := state.streamState
    if (newState == 0) {
        effectiveState := 0
        state.streamCongestion := 0.0
        state.streamSkippedFrames := 0
        state.streamPrevSkipped := 0
        state.streamReconnecting := false
    } else {
        state.streamCongestion := Max(0.0, Float(congestion))
        deltaSkip := (prevState != 0 && skippedFrames >= 0) ? Max(0, Integer(skippedFrames) - state.streamPrevSkipped) : 0
        if (skippedFrames >= 0) {
            state.streamSkippedFrames := Integer(skippedFrames)
            state.streamPrevSkipped := Integer(skippedFrames)
        }
        state.streamReconnecting := !!reconnecting
        isWarn := (newState == 2) || state.streamReconnecting || (state.streamCongestion >= UIConstants.STREAM_CONGESTION_WARN) || (deltaSkip > 0)
        effectiveState := isWarn ? 2 : 1
    }

    stateChanged := (prevState != effectiveState)
    state.streamState := effectiveState
    if (state.HasOwnProp("streamTimerFn") && state.streamTimerFn) {
        if (effectiveState != 0 && cfg.EnableWS && state.obsConnected)
            SetTimer(state.streamTimerFn, UIConstants.STREAM_POLL_INTERVAL_MS)
        else
            SetTimer(state.streamTimerFn, 0)
    }

    if (stateChanged) {
        oldW := state.streamW
        state.ComputeDimensions(cfg)
        if (cfg.ShowIndicator && cfg.ShowExtraHuds && cfg.EnableWS && (!cfg.HasOwnProp("ShowStreamHud") || cfg.ShowStreamHud)) {
            if (state.streamW != oldW && !state.isDraggingHud) {
                UpdateHudLayout(state, state.savedX, state.savedY)
                ApplyVCamAppearance(cfg, state)
            }
            ApplyStreamAppearance(cfg, state)
        }
    }
}

ApplyStreamAppearance(cfg, state) {
    if (!IsGuiValid(state.StreamGui))
        return false

    pos := ComputeHudLayout(state, state.savedX, state.savedY)
    if (state.streamState == 2) {
        bg := state.colors.streamWarn, brd := state.colors.streamBorderWarn, ic := cfg.MonoIcon ? state.colors.streamIconWarn : "FFFFFF"
        glyph := Chr(0xE7BA), lbl := "WARN"
    } else if (state.streamState == 1) {
        bg := state.colors.streamLive, brd := state.colors.streamBorderLive, ic := cfg.MonoIcon ? state.colors.streamIconLive : "FFFFFF"
        glyph := Chr(0xE93E), lbl := "LIVE"
    } else {
        bg := state.colors.streamOff, brd := state.colors.streamBorderOff, ic := cfg.MonoIcon ? state.colors.streamIconOff : "D1D5DB"
        glyph := Chr(0xE93E), lbl := "OFF"
    }
    contentArgb := Gdip.HexToArgb(ic)

    if (cfg.ShowText) {
        sIconW := Round(UIConstants.STREAM_ICON_W * cfg.IndicatorScale)
        sIconX := Round(UIConstants.STREAM_ICON_X * cfg.IndicatorScale)
        sGap := Round(UIConstants.LABEL_GAP_X * cfg.IndicatorScale)
        sTextX := sIconX + sIconW + sGap
        sTextW := Max(UIConstants.MIN_TEXT_WIDTH, state.streamW - sTextX - sIconX)
        iconCfg := {text: glyph, font: state.IconFont, size: state.subIconSize, color: contentArgb, x: sIconX, w: sIconW}
        labelCfg := {text: lbl, size: state.subTextSize, bold: true, color: contentArgb, x: sTextX, w: sTextW, align: 0, autoFit: true}
    } else {
        iconCfg := {text: glyph, font: state.IconFont, size: state.subIconSize, color: contentArgb, x: 0, w: pos.streamW}
        labelCfg := ""
    }

    return Gdip.RenderPill(state.StreamGui.Hwnd, pos.streamX, pos.streamY, pos.streamW, pos.streamH, Gdip.HexToArgb(bg), Gdip.BgrToArgb(brd), state.baseAlpha, GetCornerRadius(cfg, pos.streamH), iconCfg, labelCfg)
}

SyncVCamState(cfg, state, isActive) {
    active := !!isActive
    if (state.vcamActive != active) {
        state.vcamActive := active
        if (cfg.ShowIndicator && cfg.ShowExtraHuds && cfg.EnableWS && (!cfg.HasOwnProp("ShowStreamHud") || cfg.ShowStreamHud))
            ApplyVCamAppearance(cfg, state)
    }
}

ApplyVCamAppearance(cfg, state) {
    if (!IsGuiValid(state.VCamGui))
        return false

    pos := ComputeHudLayout(state, state.savedX, state.savedY)
    if (state.vcamActive) {
        bg := state.colors.vcamOn, brd := state.colors.vcamBorderOn, ic := cfg.MonoIcon ? state.colors.vcamIconOn : "FFFFFF"
    } else {
        bg := state.colors.vcamOff, brd := state.colors.vcamBorderOff, ic := cfg.MonoIcon ? state.colors.vcamIconOff : "D1D5DB"
    }
    contentArgb := Gdip.HexToArgb(ic)

    if (cfg.ShowText) {
        vIconW := Round(UIConstants.VCAM_ICON_W * cfg.IndicatorScale)
        vIconX := Round(UIConstants.VCAM_ICON_X * cfg.IndicatorScale)
        vGap := Round(UIConstants.LABEL_GAP_X * cfg.IndicatorScale)
        vTextX := vIconX + vIconW + vGap
        vTextW := Max(UIConstants.MIN_TEXT_WIDTH, state.vcamW - vTextX - vIconX)
        iconCfg := {text: Chr(0xE714), font: state.IconFont, size: state.subIconSize, color: contentArgb, x: vIconX, w: vIconW}
        labelCfg := {text: "VCAM", size: state.subTextSize, bold: true, color: contentArgb, x: vTextX, w: vTextW, align: 0, autoFit: true}
    } else {
        iconCfg := {text: Chr(0xE714), font: state.IconFont, size: state.subIconSize, color: contentArgb, x: 0, w: pos.vcamW}
        labelCfg := ""
    }

    return Gdip.RenderPill(state.VCamGui.Hwnd, pos.vcamX, pos.vcamY, pos.vcamW, pos.vcamH, Gdip.HexToArgb(bg), Gdip.BgrToArgb(brd), state.baseAlpha, GetCornerRadius(cfg, pos.vcamH), iconCfg, labelCfg)
}

RenderAllHudPills(cfg, state) {
    ApplyMicAppearance(cfg, state)
    ApplyRecAppearance(cfg, state)
    ApplyChatAppearance(cfg, state)
    ApplyStudioAppearance(cfg, state)
    ApplySceneAppearance(cfg, state)
    ApplyStreamAppearance(cfg, state)
    ApplyVCamAppearance(cfg, state)
}

SyncSceneState(cfg, state, sceneName) {
    if (sceneName != "" && state.currentSceneName != sceneName) {
        if (state.HasOwnProp("sceneMarqueeTimerFn") && state.sceneMarqueeTimerFn)
            SetTimer(state.sceneMarqueeTimerFn, 0)
        state.currentSceneName := sceneName
        state.sceneMarqueeOffset := 0
        state.sceneMarqueePhase := "pause_start"
        state.sceneMarqueeTicks := 0
        state.ComputeDimensions(cfg)
        if (cfg.ShowIndicator && cfg.ShowExtraHuds && !state.isDraggingHud) {
            UpdateHudLayout(state, state.savedX, state.savedY)
            ApplySceneAppearance(cfg, state)
        }
        if state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn
            try state.refreshHelpFn.Call()
    }
}

ApplySceneAppearance(cfg, state, fromMarqueeTick := false) {
    if (!IsObject(state) || !state.HasOwnProp("SceneGui") || !IsGuiValid(state.SceneGui))
        return false

    pos := ComputeHudLayout(state, state.savedX, state.savedY)
    scPad := Round(UIConstants.SCENE_PAD_X * cfg.IndicatorScale)
    availW := Max(UIConstants.MIN_TEXT_WIDTH, pos.sceneW - 2 * scPad)

    fitFontPt := Float(state.miniTextSize)
    minFontPt := Max(6.5, Round(7.5 * cfg.IndicatorScale, 1))
    fullW := Gdip.MeasureTextWidth(state.currentSceneName, "Segoe UI", fitFontPt, 1)
    while (fullW > availW && fitFontPt > minFontPt) {
        fitFontPt := Max(minFontPt, Round(fitFontPt - 0.5, 1))
        fullW := Gdip.MeasureTextWidth(state.currentSceneName, "Segoe UI", fitFontPt, 1)
    }

    sceneTextArgb := Gdip.HexToArgb(state.colors.HasOwnProp("sceneText") ? state.colors.sceneText : "FFFFFF")
    if (fullW <= availW) {
        if (state.HasOwnProp("sceneMarqueeTimerFn") && state.sceneMarqueeTimerFn)
            SetTimer(state.sceneMarqueeTimerFn, 0)
        state.sceneMarqueeMaxOffset := 0
        state.sceneMarqueeOffset := 0
        labelCfg := {
            text: state.currentSceneName,
            size: fitFontPt,
            bold: true,
            color: sceneTextArgb,
            x: scPad,
            w: availW,
            align: 1,
            autoFit: true
        }
    } else {
        marqueeFontPt := Max(7.0, Round(8.0 * cfg.IndicatorScale, 1))
        textW := Gdip.MeasureTextWidth(state.currentSceneName, "Segoe UI", marqueeFontPt, 1)
        state.sceneMarqueeFontPt := marqueeFontPt
        state.sceneMarqueeTextW := textW
        state.sceneMarqueeMaxOffset := Max(0, textW - availW)
        if (!fromMarqueeTick) {
            state.sceneMarqueeOffset := 0
            state.sceneMarqueePhase := "pause_start"
            state.sceneMarqueeTicks := 0
            if (cfg.ShowIndicator && cfg.ShowExtraHuds && cfg.EnableWS && state.HasOwnProp("sceneMarqueeTimerFn") && state.sceneMarqueeTimerFn)
                SetTimer(state.sceneMarqueeTimerFn, 40)
        }
        drawX := scPad - Round(state.sceneMarqueeOffset)
        labelCfg := {
            text: state.currentSceneName,
            size: marqueeFontPt,
            bold: true,
            color: sceneTextArgb,
            x: drawX,
            w: textW + 12,
            align: 0,
            autoFit: false,
            clipX: scPad,
            clipW: availW
        }
    }
    return Gdip.RenderPill(state.SceneGui.Hwnd, pos.sceneX, pos.sceneY, pos.sceneW, pos.sceneH, Gdip.HexToArgb(state.colors.scene), Gdip.BgrToArgb(state.colors.sceneBorder), state.baseAlpha, GetCornerRadius(cfg, pos.sceneH), "", labelCfg)
}

SceneMarqueeTick(cfg, state) {
    if (!IsObject(state.SceneGui) || !cfg.ShowIndicator || !cfg.ShowExtraHuds || !cfg.EnableWS || state.sceneMarqueeMaxOffset <= 0) {
        if (state.HasOwnProp("sceneMarqueeTimerFn") && state.sceneMarqueeTimerFn)
            SetTimer(state.sceneMarqueeTimerFn, 0)
        return
    }
    if (state.isDraggingHud)
        return

    stepPx := Max(1.0, 1.2 * cfg.IndicatorScale)
    if (state.sceneMarqueePhase = "pause_start") {
        state.sceneMarqueeTicks += 1
        if (state.sceneMarqueeTicks >= 30) {
            state.sceneMarqueeTicks := 0
            state.sceneMarqueePhase := "scroll_left"
        } else {
            return
        }
    } else if (state.sceneMarqueePhase = "scroll_left") {
        state.sceneMarqueeOffset += stepPx
        if (state.sceneMarqueeOffset >= state.sceneMarqueeMaxOffset) {
            state.sceneMarqueeOffset := state.sceneMarqueeMaxOffset
            state.sceneMarqueePhase := "pause_end"
            state.sceneMarqueeTicks := 0
        }
    } else if (state.sceneMarqueePhase = "pause_end") {
        state.sceneMarqueeTicks += 1
        if (state.sceneMarqueeTicks >= 30) {
            state.sceneMarqueeTicks := 0
            state.sceneMarqueeOffset := 0
            state.sceneMarqueePhase := "pause_start"
        } else {
            return
        }
    }
    ApplySceneAppearance(cfg, state, true)
}

FormatElapsedShort(sec) {
    s := Max(0, Integer(sec))
    hrs := s // 3600
    mins := Mod(s, 3600) // 60
    secs := Mod(s, 60)
    if (hrs > 0)
        return Format("{}:{:02}:{:02}", hrs, mins, secs)
    return Format("{:02}:{:02}", mins, secs)
}

RecTimerTick(cfg, state) {
    if (!IsObject(state) || state.recState != 1) {
        if (IsObject(state) && state.HasOwnProp("recTimerFn") && state.recTimerFn)
            SetTimer(state.recTimerFn, 0)
        return
    }
    state.recElapsedSec += 1
    if (cfg.ShowIndicator && cfg.ShowExtraHuds && (!cfg.HasOwnProp("ShowRecTimer") || cfg.ShowRecTimer) && !state.isDraggingHud && IsGuiValid(state.RecGui)) {
        if (cfg.ShowText) {
            oldW := state.recW
            state.ComputeDimensions(cfg)
            if (state.recW != oldW) {
                UpdateHudLayout(state, state.savedX, state.savedY)
                ApplyChatAppearance(cfg, state)
            }
        }
        ApplyRecAppearance(cfg, state)
    }
}

ToggleRecTimer(cfg, state := "", *) {
    ToggleBoolSetting(cfg, state, "ShowRecTimer")
    if (IsObject(state) && state.HasOwnProp("refreshHudFn") && state.refreshHudFn)
        try state.refreshHudFn.Call()
}

SyncRecState(cfg, state, newState, initialDurationMs := -1) {
    prevState := state.recState
    stateChanged := (prevState != newState)
    durProvided := (initialDurationMs >= 0)

    if (durProvided) {
        state.recElapsedSec := Max(0, Integer(initialDurationMs // 1000))
    } else if (newState == 0) {
        state.recElapsedSec := 0
    } else if (prevState == 0 && newState == 1) {
        state.recElapsedSec := 0
    }

    state.recState := newState
    if (state.HasOwnProp("recTimerFn") && state.recTimerFn) {
        if (newState == 1)
            SetTimer(state.recTimerFn, 1000)
        else
            SetTimer(state.recTimerFn, 0)
    }

    if (stateChanged || durProvided) {
        oldW := state.recW
        state.ComputeDimensions(cfg)
        if (cfg.ShowIndicator && cfg.ShowExtraHuds) {
            if (state.recW != oldW && !state.isDraggingHud) {
                UpdateHudLayout(state, state.savedX, state.savedY)
                ApplyChatAppearance(cfg, state)
            }
            ApplyRecAppearance(cfg, state)
        }
    }
}

ApplyRecAppearance(cfg, state) {
    if (!IsGuiValid(state.RecGui))
        return false

    pos := ComputeHudLayout(state, state.savedX, state.savedY)
    showTimer := (!cfg.HasOwnProp("ShowRecTimer") || cfg.ShowRecTimer) && state.HasOwnProp("recElapsedSec")
    if (state.recState == 1) {
        bg := state.colors.recActive, brd := state.colors.recBorderActive, ic := cfg.MonoIcon ? state.colors.recIconActive : "FFFFFF"
        glyph := Chr(0xE7C8)
        lbl := showTimer ? ("REC " FormatElapsedShort(state.recElapsedSec)) : "REC"
    } else if (state.recState == 2) {
        bg := state.colors.recPaused, brd := state.colors.recBorderPaused, ic := cfg.MonoIcon ? state.colors.recIconPaused : "FFFFFF"
        glyph := Chr(0xE769)
        lbl := showTimer ? ("PAUSED " FormatElapsedShort(state.recElapsedSec)) : "PAUSED"
    } else {
        bg := state.colors.recOff, brd := state.colors.recBorderOff, ic := cfg.MonoIcon ? state.colors.recIconOff : "D1D5DB"
        glyph := Chr(0xE71A), lbl := "NOT REC"
    }
    contentArgb := Gdip.HexToArgb(ic)

    if (cfg.ShowText) {
        rIconW := Round(UIConstants.REC_ICON_W * cfg.IndicatorScale)
        rIconX := Round(UIConstants.REC_ICON_X * cfg.IndicatorScale)
        rTextX := rIconX + rIconW + Round(UIConstants.LABEL_GAP_X * cfg.IndicatorScale)
        rTextW := Max(UIConstants.MIN_TEXT_WIDTH, state.recW - rTextX - rIconX)
        iconCfg := {text: glyph, font: state.IconFont, size: state.subIconSize, color: contentArgb, x: rIconX, w: rIconW}
        labelCfg := {text: lbl, size: state.subTextSize, bold: true, color: contentArgb, x: rTextX, w: rTextW, align: 0, autoFit: true}
    } else {
        iconCfg := {text: glyph, font: state.IconFont, size: state.subIconSize, color: contentArgb, x: 0, w: pos.recW}
        labelCfg := ""
    }

    return Gdip.RenderPill(state.RecGui.Hwnd, pos.recX, pos.recY, pos.recW, pos.recH, Gdip.HexToArgb(bg), Gdip.BgrToArgb(brd), state.baseAlpha, GetCornerRadius(cfg, pos.recH), iconCfg, labelCfg)
}

GetMuteAudioCueTones(isMuted) {
    return isMuted
        ? { f1: 880, d1: 65, f2: 520, d2: 95 }
        : { f1: 520, d1: 65, f2: 880, d2: 95 }
}

PlayMuteAudioCue(isMuted, async := true) {
    if (async) {
        SetTimer(() => PlayMuteAudioCue(isMuted, false), -1)
        return
    }
    tones := GetMuteAudioCueTones(isMuted)
    try {
        SoundBeep(tones.f1, tones.d1)
        SoundBeep(tones.f2, tones.d2)
    }
}

ShowMuteToast(isMuted) {
    ToolTip(isMuted ? "Mic: MUTED" : "Mic: LIVE")
    SetTimer(() => ToolTip(), -UIConstants.TOOLTIP_DURATION_MS)
}

ToggleBoolSetting(cfg, state, propName, remoteSection := "Appearance", primarySection := "Settings") {
    val := !cfg.%propName%
    cfg.%propName% := val
    section := (cfg is Config) ? primarySection : remoteSection
    cfg.WriteBool(section, propName, val)
    if (IsObject(state)) {
        if (state.HasOwnProp("rebuildTrayFn") && state.rebuildTrayFn)
            try state.rebuildTrayFn.Call()
        if (state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn)
            try state.refreshHelpFn.Call()
    }
}

ToggleAudioCue(cfg, state := "", *) {
    ToggleBoolSetting(cfg, state, "EnableAudioCue")
}

ToggleMuteToast(cfg, state := "", *) {
    ToggleBoolSetting(cfg, state, "EnableMuteToast")
}

TogglePushToMute(cfg, state := "", *) {
    ToggleBoolSetting(cfg, state, "EnablePushToMute", "Pointer", "Pointer")
}

SetHudColorPreset(cfg, state, presetName, *) {
    normalized := NormalizeHudColorPreset(presetName)
    cfg.HudColorPreset := normalized
    section := (cfg is Config) ? "Settings" : "Appearance"
    cfg.Write(section, "HudColorPreset", normalized)
    if (IsObject(state)) {
        state.colors := UIConstants.GetColorPalette(normalized)
        if (state.HasOwnProp("refreshHudFn") && state.refreshHudFn)
            try state.refreshHudFn.Call()
        if (state.HasOwnProp("rebuildTrayFn") && state.rebuildTrayFn)
            try state.rebuildTrayFn.Call()
        if (state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn)
            try state.refreshHelpFn.Call()
    }
}

IsGuiValid(guiObj) {
    if (!IsObject(guiObj))
        return false
    try return (guiObj.Hwnd != 0 && DllCall("IsWindow", "Ptr", guiObj.Hwnd) != 0)
    catch
        return false
}

UpdateVoiceMeterTimer(cfg, state) {
    if (!IsObject(state) || !state.HasOwnProp("voiceMeterTimerFn") || !state.voiceMeterTimerFn)
        return
    shouldRun := cfg.ShowIndicator && (!cfg.HasOwnProp("ShowVoiceMeter") || cfg.ShowVoiceMeter) && !state.isMuted && IsGuiValid(state.MicGui)
    if (shouldRun) {
        SetTimer(state.voiceMeterTimerFn, UIConstants.VOICE_METER_INTERVAL_MS)
    } else {
        SetTimer(state.voiceMeterTimerFn, 0)
        state.voicePeak := 0.0
    }
}

VoiceMeterTick(cfg, state, readerFn := "") {
    if (!IsGuiValid(state.MicGui) || !cfg.ShowIndicator || (cfg.HasOwnProp("ShowVoiceMeter") && !cfg.ShowVoiceMeter) || state.isMuted) {
        state.voicePeak := 0.0
        if (state.HasOwnProp("voiceMeterTimerFn") && state.voiceMeterTimerFn)
            SetTimer(state.voiceMeterTimerFn, 0)
        return
    }
    if (state.isDraggingHud)
        return
    newPeak := IsObject(readerFn) ? Float(readerFn.Call()) : AudioMeter.GetPeak()
    newPeak := Min(1.0, Max(0.0, newPeak))
    if (Abs(newPeak - state.voicePeak) >= 0.02 || (newPeak == 0.0 && state.voicePeak > 0.0)) {
        state.voicePeak := newPeak
        ApplyMicAppearance(cfg, state)
    }
}

ToggleVoiceMeter(cfg, state := "", *) {
    ToggleBoolSetting(cfg, state, "ShowVoiceMeter")
    if (IsObject(state)) {
        if (!cfg.ShowVoiceMeter)
            state.voicePeak := 0.0
        UpdateVoiceMeterTimer(cfg, state)
        if (state.HasOwnProp("refreshHudFn") && state.refreshHudFn)
            try state.refreshHudFn.Call()
    }
}

SyncUIState(cfg, state, obsIsMuted) {
    if (state.isMuted != obsIsMuted) {
        state.isMuted := obsIsMuted
        cfg.IsMuted := obsIsMuted
        cfg.WriteBool("Settings", "IsMuted", state.isMuted)
        PlayMuteAnimation(cfg, state)
        UpdateVoiceMeterTimer(cfg, state)
        if (cfg.HasOwnProp("EnableAudioCue") && cfg.EnableAudioCue)
            PlayMuteAudioCue(obsIsMuted)
        if (cfg.HasOwnProp("EnableMuteToast") && cfg.EnableMuteToast)
            ShowMuteToast(obsIsMuted)
        BroadcastHostRelayMuteState(cfg, state)
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

; --- MAGNETIC SNAP, CLICK-THROUGH & AUTO-DODGE ---
GetHudGuiList(state) {
    guis := []
    if (!IsObject(state))
        return guis
    for prop in ["MicGui", "RecGui", "ChatGui", "StudioGui", "SceneGui", "StreamGui", "VCamGui"] {
        if (state.HasOwnProp(prop) && IsGuiValid(state.%prop%))
            guis.Push(state.%prop%)
    }
    return guis
}

GetHudStackBounds(cfg, state) {
    extraTopPad := 0
    if (IsObject(cfg) && (cfg is Config)) {
        extraRow2 := (cfg.ShowExtraHuds && (cfg.EnableWS || cfg.EnableZoom))
        extraRow3 := (cfg.ShowExtraHuds && cfg.EnableWS)
        extraRow4 := (extraRow3 && (!cfg.HasOwnProp("ShowStreamHud") || cfg.ShowStreamHud))
        extraTopPad := (extraRow2 ? (state.recHeight + state.hudGap) : 0) + (extraRow3 ? (state.row3Height + state.hudGap) : 0) + (extraRow4 ? (state.row4Height + state.hudGap) : 0)
    }
    return {
        left: state.savedX,
        top: state.savedY - extraTopPad,
        right: state.savedX + state.baseWidth,
        bottom: state.savedY + state.baseHeight,
        extraTopPad: extraTopPad,
        stackW: state.baseWidth
    }
}

GetCandidateSnapWindowRects(state := "") {
    rects := []
    hudHwnds := Map()
    for g in GetHudGuiList(state)
        hudHwnds[g.Hwnd] := true
    static targetProcs := Map(
        "obs64.exe", true, "obs32.exe", true, "powerpnt.exe", true,
        "zoom.exe", true, "ms-teams.exe", true, "teams.exe", true,
        "chrome.exe", true, "msedge.exe", true, "firefox.exe", true, "brave.exe", true
    )
    for hwnd in WinGetList() {
        if (hudHwnds.Has(hwnd) || !DllCall("IsWindowVisible", "Ptr", hwnd))
            continue
        try {
            if (WinGetMinMax("ahk_id " hwnd) == -1)
                continue
            proc := StrLower(WinGetProcessName("ahk_id " hwnd))
            if (!targetProcs.Has(proc))
                continue
            buf := Buffer(16, 0)
            if (DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 9, "Ptr", buf.Ptr, "UInt", 16, "Int") == 0) {
                rl := NumGet(buf, 0, "Int"), rt := NumGet(buf, 4, "Int")
                rr := NumGet(buf, 8, "Int"), rb := NumGet(buf, 12, "Int")
            } else {
                WinGetPos(&rl, &rt, &rw, &rh, "ahk_id " hwnd)
                rr := rl + rw, rb := rt + rh
            }
            if ((rr - rl) >= 120 && (rb - rt) >= 80)
                rects.Push({ left: rl, top: rt, right: rr, bottom: rb })
        }
    }
    return rects
}

ComputeMagneticSnap(rawX, rawY, stackW, baseH, extraTopPad := 0, threshold := 14, candidateRects := "", workArea := "") {
    if (!IsObject(workArea)) {
        cx := rawX + (stackW // 2), cy := rawY + (baseH // 2)
        waIdx := 1
        monCount := MonitorGetCount()
        Loop monCount {
            MonitorGetWorkArea(A_Index, &mL, &mT, &mR, &mB)
            if (cx >= mL && cx <= mR && cy >= mT && cy <= mB) {
                waIdx := A_Index
                break
            }
        }
        MonitorGetWorkArea(waIdx, &waL, &waT, &waR, &waB)
        workArea := { left: waL, top: waT, right: waR, bottom: waB }
    }

    pad := UIConstants.SCREEN_MIN_PAD
    xTargets := [workArea.left + pad, workArea.right - pad - stackW]
    yTargets := [workArea.top + extraTopPad + pad, workArea.bottom - pad - baseH]

    if (IsObject(candidateRects)) {
        for r in candidateRects {
            xTargets.Push(r.left, r.left - stackW - 6, r.right - stackW - 6, r.right + 6)
            yTargets.Push(r.top + extraTopPad, r.bottom - baseH)
        }
    }

    bestX := rawX, bestDx := threshold + 1, didSnapX := false
    for tx in xTargets {
        dx := Abs(tx - rawX)
        if (dx <= threshold && dx < bestDx) {
            bestDx := dx
            bestX := tx
            didSnapX := true
        }
    }

    bestY := rawY, bestDy := threshold + 1, didSnapY := false
    for ty in yTargets {
        dy := Abs(ty - rawY)
        if (dy <= threshold && dy < bestDy) {
            bestDy := dy
            bestY := ty
            didSnapY := true
        }
    }

    bestX := Max(workArea.left, Min(bestX, workArea.right - stackW))
    bestY := Max(workArea.top + extraTopPad, Min(bestY, workArea.bottom - baseH))
    return { x: Round(bestX), y: Round(bestY), snappedX: didSnapX, snappedY: didSnapY }
}

ApplyHudClickThroughStyle(cfg, state, forceClickThrough := -1) {
    altHeld := GetKeyState("Alt", "P")
    wantPassThrough := (forceClickThrough != -1)
        ? !!forceClickThrough
        : (((cfg.HasOwnProp("HudClickThrough") && cfg.HudClickThrough) || (state.HasOwnProp("isAutoDodged") && state.isAutoDodged)) && !altHeld)
    styleFlag := wantPassThrough ? "+0x20" : "-0x20"
    prevDhw := DetectHiddenWindows(true)
    try {
        for g in GetHudGuiList(state) {
            try WinSetExStyle(styleFlag, "ahk_id " g.Hwnd)
        }
    } finally {
        DetectHiddenWindows(prevDhw)
    }
    return wantPassThrough
}

UpdateAutoDodgeTimer(cfg, state) {
    if (!IsObject(state) || !state.HasOwnProp("autoDodgeTimerFn") || !state.autoDodgeTimerFn)
        return
    needPoll := cfg.ShowIndicator && IsGuiValid(state.MicGui)
        && ((cfg.HasOwnProp("HudAutoDodge") && cfg.HudAutoDodge) || (cfg.HasOwnProp("HudClickThrough") && cfg.HudClickThrough))
    SetTimer(state.autoDodgeTimerFn, needPoll ? UIConstants.DODGE_POLL_INTERVAL_MS : 0)
    if (!needPoll && state.HasOwnProp("isAutoDodged") && state.isAutoDodged) {
        state.isAutoDodged := false
        state.currentAlpha := state.baseAlpha
        ApplyHudClickThroughStyle(cfg, state)
        for g in GetHudGuiList(state)
            Gdip.SetLayeredAlpha(g.Hwnd, state.currentAlpha)
    }
}

AutoDodgeTick(cfg, state, cursorPos := "", altHeldOverride := -1) {
    if (!IsObject(state) || !IsGuiValid(state.MicGui) || !cfg.ShowIndicator || state.isDraggingHud)
        return
    altHeld := (altHeldOverride != -1) ? !!altHeldOverride : GetKeyState("Alt", "P")
    dodgeEnabled := (cfg.HasOwnProp("HudAutoDodge") && cfg.HudAutoDodge)
    clickThroughEnabled := (cfg.HasOwnProp("HudClickThrough") && cfg.HudClickThrough)

    if (dodgeEnabled) {
        if (IsObject(cursorPos)) {
            mx := cursorPos.x, my := cursorPos.y
        } else {
            pt := Buffer(8, 0)
            if !DllCall("GetCursorPos", "Ptr", pt, "Int")
                return
            mx := NumGet(pt, 0, "Int"), my := NumGet(pt, 4, "Int")
        }
        bounds := GetHudStackBounds(cfg, state)
        inside := (mx >= bounds.left && mx <= bounds.right && my >= bounds.top && my <= bounds.bottom)
        wantDodged := inside && !altHeld
        if (wantDodged != state.isAutoDodged) {
            state.isAutoDodged := wantDodged
            state.currentAlpha := wantDodged ? Min(state.baseAlpha, UIConstants.DODGE_ALPHA) : state.baseAlpha
            ApplyHudClickThroughStyle(cfg, state, wantDodged ? true : (clickThroughEnabled && !altHeld))
            for g in GetHudGuiList(state)
                Gdip.SetLayeredAlpha(g.Hwnd, state.currentAlpha)
            return
        }
    }
    if (clickThroughEnabled && !state.isAutoDodged)
        ApplyHudClickThroughStyle(cfg, state, !altHeld)
}

ToggleMagneticSnap(cfg, state := "", *) {
    ToggleBoolSetting(cfg, state, "EnableMagneticSnap")
}

ToggleHudClickThrough(cfg, state := "", *) {
    ToggleBoolSetting(cfg, state, "HudClickThrough")
    if (IsObject(state)) {
        ApplyHudClickThroughStyle(cfg, state)
        UpdateAutoDodgeTimer(cfg, state)
        if (state.HasOwnProp("refreshHudFn") && state.refreshHudFn)
            try state.refreshHudFn.Call()
    }
}

ToggleHudAutoDodge(cfg, state := "", *) {
    ToggleBoolSetting(cfg, state, "HudAutoDodge")
    if (IsObject(state)) {
        if (!cfg.HudAutoDodge && state.isAutoDodged) {
            state.isAutoDodged := false
            state.currentAlpha := state.baseAlpha
        }
        UpdateAutoDodgeTimer(cfg, state)
        ApplyHudClickThroughStyle(cfg, state)
        if (state.HasOwnProp("refreshHudFn") && state.refreshHudFn)
            try state.refreshHudFn.Call()
    }
}

; --- HUD CREATION, LAYOUT & STYLING ---
InitHUD(cfg, state, showWindows := true) {
    Gdip.Startup()
    state.ComputeDimensions(cfg)

    ; Create 7 GDI+ WS_EX_LAYERED (+E0x80000) HUD windows
    state.MicGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000 -DPIScale")
    state.RecGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000 -DPIScale")
    state.ChatGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000 -DPIScale")
    state.StudioGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000 -DPIScale")
    state.SceneGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000 -DPIScale")
    state.StreamGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000 -DPIScale")
    state.VCamGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000 -DPIScale")

    RenderAllHudPills(cfg, state)

    if (showWindows) {
        UpdateHudVisibility(cfg, state)
        if (cfg.ShowIndicator && state.isMuted)
            SetTimer state.breathTimerFn, (cfg.AggressivePulse ? UIConstants.PULSE_INTERVAL_AGGRESSIVE : UIConstants.PULSE_INTERVAL_NORMAL)
    }
    ApplyHudClickThroughStyle(cfg, state)
    UpdateAutoDodgeTimer(cfg, state)

    OnMessage(0x0003, WM_HUD_MOVE.Bind(state))
    OnMessage(0x0201, WM_LBUTTONDOWN.Bind(cfg, state))
    OnMessage(0x0205, WM_RBUTTONUP.Bind(state))
    OnMessage(0x02E0, WM_DPICHANGED.Bind(state))
}

ComputeHudLayout(state, anchorX, anchorY) {
    recH := state.HasProp("recHeight") ? state.recHeight : 34
    gap := state.HasProp("hudGap") ? state.hudGap : 6
    r3H := state.HasProp("row3Height") ? state.row3Height : 30
    r4H := state.HasProp("row4Height") ? state.row4Height : 26
    recW := state.HasProp("recW") ? state.recW : 40
    chatW := state.HasProp("chatW") ? state.chatW : 34
    stuW := state.HasProp("studioW") ? state.studioW : 28
    scnW := state.HasProp("sceneW") ? state.sceneW : 46
    strmW := state.HasProp("streamW") ? state.streamW : 40
    vcW := state.HasProp("vcamW") ? state.vcamW : 34
    recY := anchorY - recH - gap
    row3Y := recY - r3H - gap
    row4Y := row3Y - r4H - gap
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
        sceneH: r3H,
        streamX: anchorX,
        streamY: row4Y,
        streamW: strmW,
        streamH: r4H,
        vcamX: anchorX + strmW + gap,
        vcamY: row4Y,
        vcamW: vcW,
        vcamH: r4H
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
    if (IsObject(state.StreamGui) && state.StreamGui.Hwnd != skipHwnd)
        state.StreamGui.Move(pos.streamX, pos.streamY, pos.streamW, pos.streamH)
    if (IsObject(state.VCamGui) && state.VCamGui.Hwnd != skipHwnd)
        state.VCamGui.Move(pos.vcamX, pos.vcamY, pos.vcamW, pos.vcamH)
}

UpdateHudVisibility(cfg, state) {
    state.animSeq += 1
    if (!cfg.ShowIndicator) {
        if (state.HasOwnProp("sceneMarqueeTimerFn") && state.sceneMarqueeTimerFn)
            SetTimer(state.sceneMarqueeTimerFn, 0)
        UpdateVoiceMeterTimer(cfg, state)
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
        if IsObject(state.StreamGui)
            state.StreamGui.Hide()
        if IsObject(state.VCamGui)
            state.VCamGui.Hide()
        UpdateAutoDodgeTimer(cfg, state)
        return
    }

    state.currentAlpha := state.baseAlpha
    pos := ComputeHudLayout(state, state.savedX, state.savedY)
    if IsObject(state.MicGui) {
        ApplyMicAppearance(cfg, state)
        state.MicGui.Show(Format("NoActivate x{} y{} w{} h{}", pos.micX, pos.micY, pos.micW, pos.micH))
    }
    UpdateVoiceMeterTimer(cfg, state)

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
        if (!cfg.HasOwnProp("ShowStreamHud") || cfg.ShowStreamHud) {
            ApplyStreamAppearance(cfg, state)
            if IsObject(state.StreamGui)
                state.StreamGui.Show(Format("NoActivate x{} y{} w{} h{}", pos.streamX, pos.streamY, pos.streamW, pos.streamH))
            ApplyVCamAppearance(cfg, state)
            if IsObject(state.VCamGui)
                state.VCamGui.Show(Format("NoActivate x{} y{} w{} h{}", pos.vcamX, pos.vcamY, pos.vcamW, pos.vcamH))
        } else {
            if IsObject(state.StreamGui)
                state.StreamGui.Hide()
            if IsObject(state.VCamGui)
                state.VCamGui.Hide()
        }
    } else {
        if (state.HasOwnProp("sceneMarqueeTimerFn") && state.sceneMarqueeTimerFn)
            SetTimer(state.sceneMarqueeTimerFn, 0)
        state.StudioGui.Hide()
        state.SceneGui.Hide()
        if IsObject(state.StreamGui)
            state.StreamGui.Hide()
        if IsObject(state.VCamGui)
            state.VCamGui.Hide()
    }
    ApplyHudClickThroughStyle(cfg, state)
    UpdateAutoDodgeTimer(cfg, state)
}

; --- HUD ANIMATIONS ---
PlayMuteAnimation(cfg, state) {
    if (!IsObject(state) || !state.HasOwnProp("MicGui") || !IsGuiValid(state.MicGui))
        return

    state.animSeq += 1
    mySeq := state.animSeq

    if (!cfg.ShowIndicator) {
        SetTimer state.breathTimerFn, 0
        state.currentAlpha := (state.HasOwnProp("activeHost") && !state.obsConnected) ? Max(60, Round(state.baseAlpha * 0.4)) : state.baseAlpha
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

    state.currentAlpha := (state.HasOwnProp("activeHost") && !state.obsConnected) ? Max(60, Round(state.baseAlpha * 0.4)) : state.baseAlpha
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
IsHudHwnd(state, hwnd) {
    if (!IsObject(state) || !hwnd)
        return false
    return (IsObject(state.MicGui) && hwnd == state.MicGui.Hwnd)
        || (IsObject(state.RecGui) && hwnd == state.RecGui.Hwnd)
        || (IsObject(state.ChatGui) && hwnd == state.ChatGui.Hwnd)
        || (IsObject(state.StudioGui) && hwnd == state.StudioGui.Hwnd)
        || (IsObject(state.SceneGui) && hwnd == state.SceneGui.Hwnd)
        || (IsObject(state.StreamGui) && hwnd == state.StreamGui.Hwnd)
        || (IsObject(state.VCamGui) && hwnd == state.VCamGui.Hwnd)
}

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
    } else if (IsObject(state.StreamGui) && hwnd == state.StreamGui.Hwnd) {
        Y := Y + state.row4Height + state.hudGap + state.row3Height + state.hudGap + state.recHeight + state.hudGap
    } else if (IsObject(state.VCamGui) && hwnd == state.VCamGui.Hwnd) {
        X := X - state.streamW - state.hudGap
        Y := Y + state.row4Height + state.hudGap + state.row3Height + state.hudGap + state.recHeight + state.hudGap
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

SwitchObsScene(cfg, state, sceneName, *) {
    if (sceneName = "")
        return false
    if (cfg.EnableWS && state.obsConnected && IsObject(state.obsWs)) {
        esc := EscapeJsonStr(sceneName)
        return SendObsRequest(state.obsWs, "SetCurrentProgramScene", "ClickSetScene", '{"sceneName":"' esc '"}')
    }
    SyncSceneState(cfg, state, sceneName)
    return true
}

BuildSceneSwitcherMenu(cfg, state, onSelectFn := "") {
    if (cfg.EnableWS && state.obsConnected && IsObject(state.obsWs))
        SendObsRequest(state.obsWs, "GetSceneList", "InitSceneList")
    Theme.ApplyMenuTheme()
    sceneMenu := Menu()
    scenes := []
    if (state.HasOwnProp("sceneList") && IsObject(state.sceneList) && state.sceneList.Length > 0) {
        for sc in state.sceneList
            scenes.Push(sc)
    } else if (state.currentSceneName != "") {
        scenes.Push(state.currentSceneName)
    }
    handler := IsObject(onSelectFn) ? onSelectFn : SwitchObsScene
    for sc in scenes {
        disp := StrReplace(sc, "&", "&&")
        sceneMenu.Add(disp, handler.Bind(cfg, state, sc))
        if (sc = state.currentSceneName)
            sceneMenu.Check(disp)
    }
    return { menu: sceneMenu, scenes: scenes }
}

ShowSceneSwitcherPopup(cfg, state) {
    built := BuildSceneSwitcherMenu(cfg, state)
    built.menu.Show()
    return built.scenes
}

HandleHudPillClick(cfg, state, hwnd) {
    if (!IsObject(cfg) || !IsObject(state) || !hwnd)
        return false
    if (cfg.HasOwnProp("EnableHudClickActions") && !cfg.EnableHudClickActions)
        return false

    if (IsObject(state.MicGui) && hwnd == state.MicGui.Hwnd) {
        if (state.HasOwnProp("triggerMuteFn") && IsObject(state.triggerMuteFn)) {
            state.triggerMuteFn.Call()
        } else {
            DispatchHostMuteToggle(cfg, state)
            if (!cfg.EnableWS || !state.obsConnected)
                SyncUIState(cfg, state, !state.isMuted)
        }
        return "mic"
    }
    if (IsObject(state.RecGui) && hwnd == state.RecGui.Hwnd) {
        if (cfg.EnableWS && state.obsConnected && IsObject(state.obsWs)) {
            SendObsRequest(state.obsWs, "ToggleRecord", "ClickToggleRec")
        } else if (cfg.EnableZoom && state.zoomConnected && cfg.ZoomRecHotkey != "" && cfg.ZoomRecHotkey != "None") {
            confSpec := GetConferencingWindowSpec(cfg.HasOwnProp("ConferencingApp") ? cfg.ConferencingApp : "Zoom")
            SetKeyDelay -1, 30
            try ControlSend(FormatSendKey(cfg.ZoomRecHotkey), , confSpec)
            SetKeyDelay 50, 50
            state.zoomRecGraceUntil := A_TickCount + UIConstants.ZOOM_REC_GRACE_MS
            SyncRecState(cfg, state, state.recState == 0 ? 1 : 0)
        } else {
            SyncRecState(cfg, state, state.recState == 0 ? 1 : 0)
        }
        return "rec"
    }
    if (IsObject(state.StudioGui) && hwnd == state.StudioGui.Hwnd) {
        nextStudio := !state.studioModeActive
        if (cfg.EnableWS && state.obsConnected && IsObject(state.obsWs))
            SendObsRequest(state.obsWs, "SetStudioModeEnabled", "ClickToggleStudio", '{"studioModeEnabled":' (nextStudio ? "true" : "false") '}')
        else
            SyncStudioState(cfg, state, nextStudio)
        return "studio"
    }
    if (IsObject(state.SceneGui) && hwnd == state.SceneGui.Hwnd) {
        ShowSceneSwitcherPopup(cfg, state)
        return "scene"
    }
    if (IsObject(state.VCamGui) && hwnd == state.VCamGui.Hwnd) {
        if (cfg.EnableWS && state.obsConnected && IsObject(state.obsWs))
            SendObsRequest(state.obsWs, "ToggleVirtualCam", "ClickToggleVCam")
        else
            SyncVCamState(cfg, state, !state.vcamActive)
        return "vcam"
    }
    if (IsObject(state.StreamGui) && hwnd == state.StreamGui.Hwnd) {
        statusLbl := (state.streamState == 2) ? "WARN" : ((state.streamState == 1) ? "LIVE" : "OFF")
        congPct := Round((state.HasOwnProp("streamCongestion") ? state.streamCongestion : 0.0) * 100, 1)
        skp := state.HasOwnProp("streamSkippedFrames") ? state.streamSkippedFrames : 0
        reconnStr := (state.HasOwnProp("streamReconnecting") && state.streamReconnecting) ? " (Reconnecting)" : ""
        tip := Format("Stream: {}{} | Congestion: {}% | Skipped Frames: {}", statusLbl, reconnStr, congPct, skp)
        ToolTip(tip)
        SetTimer(() => ToolTip(), -UIConstants.TOOLTIP_DURATION_MS)
        return "stream"
    }
    if (IsObject(state.ChatGui) && hwnd == state.ChatGui.Hwnd) {
        SyncChatState(cfg, state, 0)
        confSpec := GetConferencingWindowSpec(cfg.HasOwnProp("ConferencingApp") ? cfg.ConferencingApp : "Zoom")
        if WinExist(confSpec)
            try WinActivate(confSpec)
        return "chat"
    }
    return false
}

WM_LBUTTONDOWN(cfg, state, wParam, lParam, msg, hwnd) {
    if (!IsHudHwnd(state, hwnd))
        return

    prevX := state.savedX
    prevY := state.savedY
    prevMouseMode := A_CoordModeMouse
    CoordMode("Mouse", "Screen")
    MouseGetPos(&startMX, &startMY)
    downTick := A_TickCount

    state.animSeq += 1
    SetTimer state.breathTimerFn, 0
    state.activeDragHwnd := hwnd
    state.isDraggingHud := true
    SetTimer state.dragTimerFn, UIConstants.DRAG_SYNC_INTERVAL_MS
    PostMessage(0xA1, 2,,, "ahk_id " hwnd)
    KeyWait "LButton"
    state.isDraggingHud := false
    state.activeDragHwnd := 0
    SetTimer state.dragTimerFn, 0

    MouseGetPos(&endMX, &endMY)
    CoordMode("Mouse", prevMouseMode)
    isShortClick := (Abs(endMX - startMX) <= 3 && Abs(endMY - startMY) <= 3 && (A_TickCount - downTick) < 400)

    if (isShortClick) {
        anchor := {x: prevX, y: prevY}
    } else {
        WinGetPos(&X, &Y,,, "ahk_id " hwnd)
        anchor := AnchorFromHwnd(state, hwnd, X, Y)
        if (!cfg.HasOwnProp("EnableMagneticSnap") || cfg.EnableMagneticSnap) {
            b := GetHudStackBounds(cfg, state)
            snap := ComputeMagneticSnap(anchor.x, anchor.y, b.stackW, state.baseHeight, b.extraTopPad, UIConstants.SNAP_THRESHOLD_PX, GetCandidateSnapWindowRects(state))
            anchor.x := snap.x, anchor.y := snap.y
        }
        if (anchor.x != prevX || anchor.y != prevY) {
            cfg.savedX := anchor.x
            cfg.savedY := anchor.y
            cfg.Write("Position", "X", anchor.x)
            cfg.Write("Position", "Y", anchor.y)
        }
    }
    UpdateHudLayout(state, anchor.x, anchor.y)
    state.currentAlpha := state.baseAlpha
    ApplyMicAppearance(cfg, state)
    if (cfg.ShowIndicator && cfg.ShowExtraHuds && cfg.EnableWS) {
        ApplySceneAppearance(cfg, state)
        if (!cfg.HasOwnProp("ShowStreamHud") || cfg.ShowStreamHud)
            ApplyStreamAppearance(cfg, state)
    }
    ApplyHudClickThroughStyle(cfg, state)
    if (cfg.ShowIndicator && state.isMuted)
        SetTimer state.breathTimerFn, (cfg.AggressivePulse ? UIConstants.PULSE_INTERVAL_AGGRESSIVE : UIConstants.PULSE_INTERVAL_NORMAL)

    if (isShortClick)
        HandleHudPillClick(cfg, state, hwnd)
}

WM_RBUTTONUP(state, wParam, lParam, msg, hwnd) {
    if (IsHudHwnd(state, hwnd))
        A_TrayMenu.Show()
}

WM_DPICHANGED(state, wParam, lParam, msg, hwnd) {
    if (!IsObject(state.MicGui) || hwnd != state.MicGui.Hwnd)
        return
    newLeft := NumGet(lParam, 0, "Int")
    newTop := NumGet(lParam, 4, "Int")
    UpdateHudLayout(state, newLeft, newTop)
}

SwitchProfileAction(cfg, state, profileName, *) {
    if (cfg.ApplyProfile(profileName, state)) {
        TrayTip("Switched to Profile: " cfg.ActiveProfile, "PresenterSync Profiles", 1)
    }
}

ShowProfileManagerUI(cfg, state := "") {
    existing := Theme.FocusExistingWindow("PresenterSync - Profile Manager")
    if IsObject(existing)
        return existing

    Theme.AcquireSuspend()

    dlg := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "PresenterSync - Profile Manager")
    dlg._closed := false
    dlg.MarginX := 20
    dlg.MarginY := 16
    Theme.ApplyToWindow(dlg)
    Theme.NamedWindows["PresenterSync - Profile Manager"] := dlg

    dlg.SetFont("s10 w600", Theme.UiFont)
    Theme.RegisterControl(dlg, dlg.Add("Text", "xm w360", "Configuration Profiles"), "Text")
    dlg.SetFont("s9 w400", Theme.UiFont)
    lblActive := dlg.Add("Text", "xm w360 y+4", "Active Profile: " cfg.ActiveProfile)
    Theme.RegisterControl(dlg, lblActive, "Text", "accent")

    lb := dlg.Add("ListBox", "xm w220 h136 y+10", cfg.GetProfileNames())
    Theme.RegisterControl(dlg, lb, "Edit")

    btnLoad := dlg.Add("Button", "x+12 yp w128 h30 Default", "Load Profile")
    btnSave := dlg.Add("Button", "xp y+8 w128 h30", "Save Current")
    btnDel := dlg.Add("Button", "xp y+8 w128 h30", "Delete Profile")
    Theme.RegisterControl(dlg, btnLoad, "Button", "accent")
    Theme.RegisterControl(dlg, btnSave, "Button")
    Theme.RegisterControl(dlg, btnDel, "Button")

    dlg.SetFont("s9 w600", Theme.UiFont)
    Theme.RegisterControl(dlg, dlg.Add("Text", "xm w360 y+10", "Save Current Settings As New Profile:"), "Text")
    dlg.SetFont("s9 w400", Theme.UiFont)
    editNew := dlg.Add("Edit", "xm w220")
    Theme.RegisterControl(dlg, editNew, "Edit")
    btnNew := dlg.Add("Button", "x+12 yp-2 w128 h28", "Save As New")
    Theme.RegisterControl(dlg, btnNew, "Button", "accent")

    lblMsg := dlg.Add("Text", "xm w220 y+10", "Save presets for OBS, Zoom, Teams, or Meet.")
    Theme.RegisterControl(dlg, lblMsg, "Text", "muted")
    btnClose := dlg.Add("Button", "x+12 yp-4 w128 h30", "Close")
    Theme.RegisterControl(dlg, btnClose, "Button")

    RefreshList(selectName := "") {
        names := cfg.GetProfileNames()
        lb.Delete()
        lb.Add(names)
        target := (selectName != "") ? selectName : cfg.ActiveProfile
        chooseIdx := 1
        for idx, n in names {
            if (StrLower(n) = StrLower(target)) {
                chooseIdx := idx
                break
            }
        }
        lb.Choose(chooseIdx)
        lblActive.Value := "Active Profile: " cfg.ActiveProfile
        btnDel.Enabled := (StrLower(lb.Text) != "default")
    }
    RefreshList(cfg.ActiveProfile)

    OnLoadClick(*) {
        if (lb.Text = "") {
            lblMsg.Value := "Select a profile first."
            return
        }
        if (cfg.ApplyProfile(lb.Text, state)) {
            RefreshList(cfg.ActiveProfile)
            lblMsg.Value := "Loaded profile: " cfg.ActiveProfile
        } else {
            lblMsg.Value := "Save snapshot to '" lb.Text "' first."
        }
    }

    OnSaveClick(*) {
        if (lb.Text = "") {
            lblMsg.Value := "Select a profile first."
            return
        }
        cfg.SaveProfile(lb.Text)
        RefreshList(cfg.ActiveProfile)
        if (IsObject(state) && state.HasOwnProp("rebuildTrayFn") && state.rebuildTrayFn)
            try state.rebuildTrayFn.Call()
        lblMsg.Value := "Updated snapshot: " cfg.ActiveProfile
    }

    OnNewClick(*) {
        newName := cfg.NormalizeProfileName(editNew.Value)
        if (newName = "") {
            lblMsg.Value := "Enter a valid profile name."
            return
        }
        cfg.SaveProfile(newName)
        editNew.Value := ""
        RefreshList(cfg.ActiveProfile)
        if (IsObject(state) && state.HasOwnProp("rebuildTrayFn") && state.rebuildTrayFn)
            try state.rebuildTrayFn.Call()
        lblMsg.Value := "Created profile: " cfg.ActiveProfile
    }

    OnDeleteClick(*) {
        if (StrLower(lb.Text) = "default") {
            lblMsg.Value := "Default profile is protected."
            return
        }
        if (cfg.DeleteProfile(lb.Text)) {
            RefreshList(cfg.ActiveProfile)
            if (IsObject(state) && state.HasOwnProp("rebuildTrayFn") && state.rebuildTrayFn)
                try state.rebuildTrayFn.Call()
            lblMsg.Value := "Profile deleted."
        } else {
            lblMsg.Value := "Could not delete profile."
        }
    }

    lb.OnEvent("Change", (*) => (btnDel.Enabled := (StrLower(lb.Text) != "default")))
    lb.OnEvent("DoubleClick", OnLoadClick)
    btnLoad.OnEvent("Click", OnLoadClick)
    btnSave.OnEvent("Click", OnSaveClick)
    btnNew.OnEvent("Click", OnNewClick)
    btnDel.OnEvent("Click", OnDeleteClick)

    CloseProfileMgr(*) {
        if (dlg._closed)
            return
        dlg._closed := true
        Theme.UnregisterWindow(dlg, "PresenterSync - Profile Manager")
        Theme.ReleaseSuspend()
        dlg.Destroy()
    }
    btnClose.OnEvent("Click", CloseProfileMgr)
    dlg.OnEvent("Close", CloseProfileMgr)
    dlg.OnEvent("Escape", CloseProfileMgr)

    dlg.Show()
    return dlg
}

GetStartupRegistryValueName(cfg) {
    return (IsObject(cfg) && cfg.HasOwnProp("ConfigFile") && InStr(cfg.ConfigFile, "Remote")) ? "PresenterSyncRemote" : "PresenterSync"
}

GetStartupLaunchCommand(cfg) {
    return A_IsCompiled ? ('"' A_ScriptFullPath '"') : ('"' A_AhkPath '" "' A_ScriptFullPath '"')
}

SetStartWithWindows(cfg, state := "", enable := "", writeRegistry := true) {
    if (!IsObject(cfg))
        return false
    target := (enable = "") ? !cfg.StartWithWindows : !!enable
    cfg.StartWithWindows := target
    cfg.WriteBool("Settings", "StartWithWindows", target)
    if (writeRegistry) {
        regKey := "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run"
        valName := GetStartupRegistryValueName(cfg)
        if (target) {
            try RegWrite(GetStartupLaunchCommand(cfg), "REG_SZ", regKey, valName)
        } else {
            try RegDelete(regKey, valName)
        }
    }
    if (IsObject(state)) {
        if (state.HasOwnProp("rebuildTrayFn") && state.rebuildTrayFn)
            try state.rebuildTrayFn.Call()
        if (state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn)
            try state.refreshHelpFn.Call()
    }
    return target
}

ToggleStartWithWindows(cfg, state := "", *) {
    enabled := SetStartWithWindows(cfg, state)
    TrayTip("Start with Windows: " (enabled ? "ON" : "OFF"), "PresenterSync", 1)
    return enabled
}

CompareSemVer(vA, vB) {
    cleanA := RegExReplace(Trim(String(vA)), "^[vV]")
    cleanB := RegExReplace(Trim(String(vB)), "^[vV]")
    partsA := StrSplit(cleanA, ".")
    partsB := StrSplit(cleanB, ".")
    maxLen := Max(partsA.Length, partsB.Length, 3)
    Loop maxLen {
        nA := 0
        nB := 0
        if (A_Index <= partsA.Length && RegExMatch(partsA[A_Index], "^(\d+)", &mA))
            nA := Integer(mA[1])
        if (A_Index <= partsB.Length && RegExMatch(partsB[A_Index], "^(\d+)", &mB))
            nB := Integer(mB[1])
        if (nA > nB)
            return 1
        if (nA < nB)
            return -1
    }
    return 0
}

ParseGitHubReleaseTag(jsonStr) {
    s := String(jsonStr)
    if (RegExMatch(s, '"tag_name"\s*:\s*"([^"]+)"', &mTag)) {
        tag := UnescapeJsonStr(mTag[1])
    } else if (RegExMatch(s, '"name"\s*:\s*"(v?\d+\.\d+\.\d+[^"]*)"', &mName)) {
        tag := UnescapeJsonStr(mName[1])
    } else {
        return { ok: false, tag: "", version: "", url: "" }
    }
    ver := RegExReplace(Trim(tag), "^[vV]")
    url := ""
    if (RegExMatch(s, '"html_url"\s*:\s*"([^"]+)"', &mUrl))
        url := UnescapeJsonStr(mUrl[1])
    return { ok: (ver != ""), tag: tag, version: ver, url: url }
}

CheckForUpdates(currentVer := "", mockResponseJson := "", silent := true) {
    cur := (currentVer != "") ? RegExReplace(Trim(String(currentVer)), "^[vV]") : UIConstants.APP_VERSION
    fallbackUrl := "https://github.com/SaabithJiffry/PresenterSync/releases"
    rawJson := ""
    httpOk := false

    if (mockResponseJson != "") {
        rawJson := mockResponseJson
        httpOk := true
    } else {
        for apiUrl in [
            "https://api.github.com/repos/SaabithJiffry/PresenterSync/releases/latest",
            "https://api.github.com/repos/SaabithJiffry/PresenterSync/tags"
        ] {
            try {
                req := ComObject("WinHttp.WinHttpRequest.5.1")
                req.SetTimeouts(3000, 3000, 4000, 4000)
                req.Open("GET", apiUrl, false)
                req.SetRequestHeader("User-Agent", "PresenterSync/" cur)
                req.SetRequestHeader("Accept", "application/vnd.github+json")
                req.Send()
                if (req.Status == 200) {
                    rawJson := req.ResponseText
                    httpOk := true
                    break
                }
            } catch {
                httpOk := false
            }
        }
    }

    parsed := httpOk ? ParseGitHubReleaseTag(rawJson) : { ok: false, tag: "", version: "", url: "" }
    if (!parsed.ok) {
        if (!silent)
            MsgBox("Unable to check GitHub for updates right now (offline or rate-limited).`n`nReleases page: " fallbackUrl, "Update Check", "Icon!")
        return { ok: false, status: "error", current: cur, latest: "", updateAvailable: false, url: fallbackUrl }
    }

    relUrl := (parsed.url != "") ? parsed.url : fallbackUrl
    if (CompareSemVer(parsed.version, cur) > 0) {
        if (!silent) {
            ans := MsgBox("A new version of PresenterSync is available!`n`nCurrent Version: v" cur "`nLatest Version:  v" parsed.version "`n`nOpen the GitHub Releases page to download?", "PresenterSync Update Available", "YesNo Iconi")
            if (ans = "Yes")
                try Run(relUrl)
        }
        return { ok: true, status: "update_available", current: cur, latest: parsed.version, updateAvailable: true, url: relUrl }
    }

    if (!silent)
        MsgBox("You are running the latest version of PresenterSync (v" cur ").", "Up to Date", "Iconi")
    return { ok: true, status: "up_to_date", current: cur, latest: parsed.version, updateAvailable: false, url: relUrl }
}

CheckForUpdatesUI(currentVer := "", *) => CheckForUpdates(currentVer, "", false)

_HotkeyValidatorGuard(*) => false
_HotkeyValidatorNoop(*) => 0

IsValidHotkeySpec(hk) {
    s := Trim(String(hk))
    if (s = "" || StrLower(s) = "none")
        return true
    if RegExMatch(s, "^[*~$<>^!+#]+$")
        return false
    try {
        HotIf(_HotkeyValidatorGuard)
        Hotkey(s, _HotkeyValidatorNoop, "Off")
        HotIf()
        return true
    } catch {
        HotIf()
        return false
    }
}

SyncTelemetryBackendsFromConfig(cfg, state) {
    if (!IsObject(state))
        return
    if (state.HasOwnProp("colors"))
        state.colors := UIConstants.GetColorPalette(cfg.HudColorPreset)
    if (state.HasOwnProp("baseAlpha"))
        state.baseAlpha := cfg.OpacityLevel

    hadObsSession := (state.HasOwnProp("obsConnected") && state.obsConnected) || (state.HasOwnProp("obsWs") && IsObject(state.obsWs))
    if (state.HasOwnProp("obsTimerFn") && state.obsTimerFn)
        SetTimer(state.obsTimerFn, cfg.EnableWS ? -50 : 0)

    if (!cfg.EnableWS) {
        if (state.HasOwnProp("obsConnected"))
            state.obsConnected := false
        if (state.HasOwnProp("obsWs") && IsObject(state.obsWs)) {
            try state.obsWs.shutdown()
            state.obsWs := ""
        }
        if (state.HasOwnProp("streamTimerFn") && state.streamTimerFn)
            SetTimer(state.streamTimerFn, 0)
        if (state.HasOwnProp("sceneMarqueeTimerFn") && state.sceneMarqueeTimerFn)
            SetTimer(state.sceneMarqueeTimerFn, 0)
        if (state.HasOwnProp("streamState"))
            SyncStreamState(cfg, state, 0)
        if (state.HasOwnProp("vcamActive"))
            SyncVCamState(cfg, state, false)
        if (state.HasOwnProp("studioModeActive"))
            SyncStudioState(cfg, state, false)
        state.currentSceneName := "Scene"
        state.sceneList := []
        if (state.HasOwnProp("recState") && (hadObsSession || !cfg.EnableZoom))
            SyncRecState(cfg, state, 0)
    }

    if (!cfg.EnableZoom || cfg.EnableWS) {
        if (state.HasOwnProp("zoomConnected"))
            state.zoomConnected := false
        if (state.HasOwnProp("zoomLastMuted"))
            state.zoomLastMuted := -1
        if (state.HasOwnProp("zoomRecGraceUntil"))
            state.zoomRecGraceUntil := 0
        if (state.HasOwnProp("zoomSawRecControl"))
            state.zoomSawRecControl := false
        if (!cfg.EnableWS && !cfg.EnableZoom) {
            if (state.HasOwnProp("unreadChatCount"))
                SyncChatState(cfg, state, 0)
            if (state.HasOwnProp("recState"))
                SyncRecState(cfg, state, 0)
        }
    }

    if (state.HasOwnProp("zoomTimerFn") && state.zoomTimerFn)
        UpdateZoomMonitorTimer(cfg, state)
    if (state.HasOwnProp("relayTimerFn"))
        UpdateHostInternetRelay(cfg, state)
    if (state.HasOwnProp("MicGui") && IsObject(state.MicGui)) {
        RefreshHudAppearance(cfg, state)
        UpdateHudVisibility(cfg, state)
        ApplyHudClickThroughStyle(cfg, state)
        UpdateVoiceMeterTimer(cfg, state)
    }
    if (state.HasOwnProp("autoDodgeTimerFn") && state.autoDodgeTimerFn)
        UpdateAutoDodgeTimer(cfg, state)
    if (state.HasOwnProp("rebindHotkeysFn") && state.rebindHotkeysFn)
        try state.rebindHotkeysFn.Call()
    if (state.HasOwnProp("rebuildTrayFn") && state.rebuildTrayFn)
        try state.rebuildTrayFn.Call()
    if (state.HasOwnProp("refreshHelpFn") && state.refreshHelpFn)
        try state.refreshHelpFn.Call()
}

ApplyControlCenterSettings(cfg, state := "", vals := "", writeRegistry := true, invalidKeys := "") {
    if (!IsObject(cfg))
        return false

    invalidCount := 0
    if IsObject(vals) {
        if vals.HasOwnProp("AudioRoutingMode") {
            rm := Integer(vals.AudioRoutingMode)
            if (rm >= 1 && rm <= 3) {
                cfg.AudioRoutingMode := rm
                cfg.Write("Settings", "AudioRoutingMode", rm)
            }
        }
        if vals.HasOwnProp("ConferencingApp") {
            cApp := NormalizeConferencingApp(vals.ConferencingApp)
            cfg.ConferencingApp := cApp
            cfg.Write("Settings", "ConferencingApp", cApp)
        }
        if vals.HasOwnProp("targetMicName") {
            mic := Trim(vals.targetMicName) != "" ? Trim(vals.targetMicName) : "Mic/Aux"
            cfg.targetMicName := mic
            cfg.Write("Settings", "TargetMicName", mic)
        }
        if vals.HasOwnProp("ShowVoiceMeter") {
            cfg.ShowVoiceMeter := !!vals.ShowVoiceMeter
            cfg.WriteBool("Settings", "ShowVoiceMeter", cfg.ShowVoiceMeter)
            if (!cfg.ShowVoiceMeter && IsObject(state))
                state.voicePeak := 0.0
        }
        if vals.HasOwnProp("EnableAudioCue") {
            cfg.EnableAudioCue := !!vals.EnableAudioCue
            cfg.WriteBool("Settings", "EnableAudioCue", cfg.EnableAudioCue)
        }
        if vals.HasOwnProp("EnableMuteToast") {
            cfg.EnableMuteToast := !!vals.EnableMuteToast
            cfg.WriteBool("Settings", "EnableMuteToast", cfg.EnableMuteToast)
        }

        ; Tab 2: OBS & Stream
        if vals.HasOwnProp("EnableWS") {
            cfg.EnableWS := !!vals.EnableWS
            cfg.WriteBool("Settings", "EnableWS", cfg.EnableWS)
        }
        if vals.HasOwnProp("EnableZoom") {
            cfg.EnableZoom := cfg.EnableWS ? false : !!vals.EnableZoom
            cfg.WriteBool("Settings", "EnableZoom", cfg.EnableZoom)
        }
        if vals.HasOwnProp("obsPassword") {
            cfg.obsPassword := vals.obsPassword
            cfg.Write("Settings", "ObsPassword", cfg.obsPassword)
        }
        if vals.HasOwnProp("ShowStreamHud") {
            cfg.ShowStreamHud := !!vals.ShowStreamHud
            cfg.WriteBool("Settings", "ShowStreamHud", cfg.ShowStreamHud)
        }
        if vals.HasOwnProp("ShowRecTimer") {
            cfg.ShowRecTimer := !!vals.ShowRecTimer
            cfg.WriteBool("Settings", "ShowRecTimer", cfg.ShowRecTimer)
        }

        ; Tab 3: Pointer & Clicker
        if vals.HasOwnProp("PointerMode") {
            pm := vals.PointerMode
            if (pm = "Full PPT + Mute" || pm = 1) {
                cfg.EnablePPT := true
                cfg.EnableMicOnly := false
            } else if (pm = "Pointer Mute Only" || pm = "Mute Only" || pm = 2) {
                cfg.EnablePPT := false
                cfg.EnableMicOnly := true
            } else {
                cfg.EnablePPT := false
                cfg.EnableMicOnly := false
            }
            cfg.WriteBool("Settings", "EnablePPT", cfg.EnablePPT)
            cfg.WriteBool("Settings", "EnableMicOnly", cfg.EnableMicOnly)
        }
        if vals.HasOwnProp("EnablePushToMute") {
            cfg.EnablePushToMute := !!vals.EnablePushToMute
            cfg.WriteBool("Pointer", "EnablePushToMute", cfg.EnablePushToMute)
        }
        for pKey in ["CatchArrows", "CatchPg", "CatchSpace", "CatchEnter", "CatchTab", "CatchEsc"] {
            if vals.HasOwnProp(pKey) {
                cfg.%pKey% := !!vals.%pKey%
                cfg.WriteBool("Pointer", pKey, cfg.%pKey%)
            }
        }

        ; Tab 4: HUD & Appearance
        if vals.HasOwnProp("IndicatorScale") {
            sc := Float(vals.IndicatorScale)
            if (sc >= 0.25 && sc <= 5.0) {
                cfg.IndicatorScale := sc
                cfg.Write("Settings", "IndicatorScale", sc)
            }
        }
        if vals.HasOwnProp("OpacityLevel") {
            op := Integer(vals.OpacityLevel)
            if (op >= 50 && op <= 255) {
                cfg.OpacityLevel := op
                cfg.Write("Settings", "OpacityLevel", op)
            }
        }
        if vals.HasOwnProp("HudColorPreset") {
            pName := NormalizeHudColorPreset(vals.HudColorPreset)
            cfg.HudColorPreset := pName
            cfg.Write("Settings", "HudColorPreset", pName)
        }
        if vals.HasOwnProp("ThemeMode") {
            tm := (vals.ThemeMode = "Dark" || vals.ThemeMode = "Light") ? vals.ThemeMode : "System"
            cfg.ThemeMode := tm
            cfg.Write("Settings", "ThemeMode", tm)
            Theme.SetMode(tm)
        }
        for bProp in ["ShowIndicator", "ShowExtraHuds", "ShowText", "MonoIcon", "SleekCorners", "AggressivePulse", "EnableHudClickActions", "EnableMagneticSnap", "HudAutoDodge", "HudClickThrough"] {
            if vals.HasOwnProp(bProp) {
                cfg.%bProp% := !!vals.%bProp%
                cfg.WriteBool("Settings", bProp, cfg.%bProp%)
            }
        }

        ; Tab 5: Remote Companion
        if vals.HasOwnProp("RemoteNetworkMode") {
            rMode := (vals.RemoteNetworkMode = "Internet" || InStr(vals.RemoteNetworkMode, "Internet")) ? "Internet" : "LAN"
            cfg.RemoteNetworkMode := rMode
            cfg.Write("Settings", "RemoteNetworkMode", rMode)
        }

        ; Uniform hotkey validation & persistence (Tabs 1, 2, 3, 6)
        for hkSpec in [
            { prop: "ZoomMuteHotkey", key: "ZoomMuteHotkey", label: "Zoom Mute Hotkey" },
            { prop: "TeamsMuteHotkey", key: "TeamsMuteHotkey", label: "Teams Mute Hotkey" },
            { prop: "MeetMuteHotkey", key: "MeetMuteHotkey", label: "Meet Mute Hotkey" },
            { prop: "ZoomRecHotkey", key: "ZoomRecHotkey", label: "Conferencing Rec Hotkey" },
            { prop: "ZoomPauseHotkey", key: "ZoomPauseHotkey", label: "Conferencing Pause Hotkey" },
            { prop: "ObsMuteHotkey", key: "ObsHotkey", label: "OBS Mute Hotkey" },
            { prop: "ObsRecHotkey", key: "ObsRecHotkey", label: "OBS Rec Hotkey" },
            { prop: "ObsPauseHotkey", key: "ObsPauseHotkey", label: "OBS Pause Hotkey" },
            { prop: "HwMuteHotkey", key: "HwMuteHotkey", label: "Clicker Mute Button" },
            { prop: "PptHotkey", key: "PptHotkey", label: "Cycle Pointer Mode" },
            { prop: "WsHotkey", key: "WsHotkey", label: "Toggle OBS Sync" },
            { prop: "ZoomHotkey", key: "ZoomHotkey", label: "Toggle Conf Monitor" },
            { prop: "IndHotkey", key: "IndHotkey", label: "Show / Hide HUD" },
            { prop: "SuspendHotkey", key: "SuspendHotkey", label: "Suspend All Hotkeys" },
            { prop: "ExitHotkey", key: "ExitHotkey", label: "Exit Application" }
        ] {
            if vals.HasOwnProp(hkSpec.prop) {
                rawHk := Trim(String(vals.%hkSpec.prop%))
                if (!IsValidHotkeySpec(rawHk)) {
                    invalidCount += 1
                    if IsObject(invalidKeys)
                        invalidKeys.Push({ prop: hkSpec.prop, label: hkSpec.label, value: rawHk })
                    continue
                }
                normHk := (rawHk = "" || StrLower(rawHk) = "none") ? "None" : rawHk
                cfg.%hkSpec.prop% := normHk
                cfg.Write("Settings", hkSpec.key, normHk)
            }
        }
        if vals.HasOwnProp("StartWithWindows") {
            SetStartWithWindows(cfg, "", !!vals.StartWithWindows, writeRegistry)
        }
    }

    SyncTelemetryBackendsFromConfig(cfg, state)
    return (invalidCount == 0)
}

ShowControlCenterWindow(cfg, state := "", *) {
    existing := Theme.FocusExistingWindow("PresenterSync - Control Center")
    if IsObject(existing)
        return existing

    Theme.AcquireSuspend()

    ccGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "PresenterSync - Control Center")
    ccGui._closed := false
    ccGui.MarginX := 16
    ccGui.MarginY := 14
    Theme.ApplyToWindow(ccGui)
    Theme.NamedWindows["PresenterSync - Control Center"] := ccGui

    tabNames := ["Audio & Conf", "OBS & Stream", "Pointer", "HUD & Theme", "Remote", "Profiles & Sys"]
    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    tabs := ccGui.Add("Tab2", "x14 y12 w692 h486 +0x0400", tabNames)
    tabs._tabNames := tabNames
    Theme.RegisterControl(ccGui, tabs, "Tab")

    ; ==========================================================================
    ; TAB 1: AUDIO & CONFERENCING
    ; ==========================================================================
    tabs.UseTab(1)
    ccGui.SetFont("s11 w700 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y60 w650", "Audio Routing Mode, Conferencing Platform & Acoustic Feedback"), "Text", "tabText")

    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y96 w210", "Audio Routing Profile:"), "Text", "tabText")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    routingLabels := [
        "1: Pro OBS Setup (VB-Cable)",
        "2: Standard Direct Mic (Conferencing-Only)",
        "3: Dual App Sync (OBS + Conferencing)"
    ]
    ddlRouting := ccGui.Add("DropDownList", "x250 y92 w430 Choose" (cfg.AudioRoutingMode >= 1 && cfg.AudioRoutingMode <= 3 ? cfg.AudioRoutingMode : 1), routingLabels)
    Theme.RegisterControl(ccGui, ddlRouting, "DropDownList")

    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y134 w210", "Conferencing Application:"), "Text", "tabText")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    confApps := GetConferencingAppNames()
    confIdx := 1
    for i, cName in confApps {
        if (NormalizeConferencingApp(cfg.ConferencingApp) = cName)
            confIdx := i
    }
    ddlConfApp := ccGui.Add("DropDownList", "x250 y130 w210 Choose" confIdx, confApps)
    Theme.RegisterControl(ccGui, ddlConfApp, "DropDownList")

    btnWizard := ccGui.Add("Button", "x472 y128 w208 h28", "Run Audio Setup Wizard...")
    Theme.RegisterControl(ccGui, btnWizard, "Button", "tabButton")
    btnWizard.OnEvent("Click", (*) => PromptForSetup(cfg, false))

    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y172 w210", "Target OBS Audio Source:"), "Text", "tabText")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    edTargetMic := ccGui.Add("Edit", "x250 y168 w430 h26", cfg.targetMicName)
    Theme.RegisterControl(ccGui, edTargetMic, "Edit")

    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y212 w210", "Zoom / Teams / Meet Mute Keys:"), "Text", "tabText")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    edZoomMute := ccGui.Add("Edit", "x250 y208 w136 h26", cfg.ZoomMuteHotkey)
    edTeamsMute := ccGui.Add("Edit", "x397 y208 w136 h26", cfg.TeamsMuteHotkey)
    edMeetMute := ccGui.Add("Edit", "x544 y208 w136 h26", cfg.MeetMuteHotkey)
    Theme.RegisterControl(ccGui, edZoomMute, "Edit")
    Theme.RegisterControl(ccGui, edTeamsMute, "Edit")
    Theme.RegisterControl(ccGui, edMeetMute, "Edit")
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x250 y236 w136", "Zoom (e.g. !a)"), "Text", "tabMuted")
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x397 y236 w136", "Teams (e.g. ^+m)"), "Text", "tabMuted")
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x544 y236 w136", "Meet (e.g. ^d)"), "Text", "tabMuted")

    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y268 w210", "Conferencing Rec / Pause Keys:"), "Text", "tabText")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    edZoomRec := ccGui.Add("Edit", "x250 y264 w210 h26", cfg.ZoomRecHotkey)
    edZoomPause := ccGui.Add("Edit", "x470 y264 w210 h26", cfg.ZoomPauseHotkey)
    Theme.RegisterControl(ccGui, edZoomRec, "Edit")
    Theme.RegisterControl(ccGui, edZoomPause, "Edit")

    chkVoiceMeter := ccGui.Add("Checkbox", "x32 y314 w310 h24" (cfg.ShowVoiceMeter ? " Checked" : ""), "Show Live CoreAudio Voice Activity Bar on LIVE Pill")
    chkAudioCue := ccGui.Add("Checkbox", "x360 y314 w320 h24" (cfg.EnableAudioCue ? " Checked" : ""), "Play Two-Tone Acoustic Chime on Mute / Unmute")
    chkMuteToast := ccGui.Add("Checkbox", "x32 y346 w310 h24" (cfg.EnableMuteToast ? " Checked" : ""), "Show Brief Cursor Tooltip Toast on Mute Change")
    Theme.RegisterControl(ccGui, chkVoiceMeter, "Checkbox", "tabText")
    Theme.RegisterControl(ccGui, chkAudioCue, "Checkbox", "tabText")
    Theme.RegisterControl(ccGui, chkMuteToast, "Checkbox", "tabText")

    ; ==========================================================================
    ; TAB 2: OBS & LIVE STREAM
    ; ==========================================================================
    tabs.UseTab(2)
    ccGui.SetFont("s11 w700 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y60 w650", "OBS Studio WebSocket v5, Live Stream HUD & Fallback Shortcuts"), "Text", "tabText")

    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    chkEnableWS := ccGui.Add("Checkbox", "x32 y98 w310 h24" (cfg.EnableWS ? " Checked" : ""), "Enable OBS WebSocket v5 Live Sync (Port 4455)")
    chkEnableZoom := ccGui.Add("Checkbox", "x360 y98 w320 h24" (cfg.EnableZoom ? " Checked" : ""), "Enable Conferencing UIA Background Monitoring")
    Theme.RegisterControl(ccGui, chkEnableWS, "Checkbox", "tabText")
    Theme.RegisterControl(ccGui, chkEnableZoom, "Checkbox", "tabText")
    chkEnableWS.OnEvent("Click", (*) => (chkEnableWS.Value ? (chkEnableZoom.Value := 0) : 0))
    chkEnableZoom.OnEvent("Click", (*) => (chkEnableZoom.Value ? (chkEnableWS.Value := 0) : 0))

    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y140 w210", "OBS WebSocket Password:"), "Text", "tabText")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    edObsPass := ccGui.Add("Edit", "x250 y136 w430 h26 Password", cfg.obsPassword)
    Theme.RegisterControl(ccGui, edObsPass, "Edit")

    chkStreamHud := ccGui.Add("Checkbox", "x32 y182 w320 h24" (cfg.ShowStreamHud ? " Checked" : ""), "Show 4th-Row Live Stream & Virtual Camera HUD")
    chkRecTimer := ccGui.Add("Checkbox", "x360 y182 w320 h24" (cfg.ShowRecTimer ? " Checked" : ""), "Show Live Elapsed Recording / Stream Timer")
    Theme.RegisterControl(ccGui, chkStreamHud, "Checkbox", "tabText")
    Theme.RegisterControl(ccGui, chkRecTimer, "Checkbox", "tabText")

    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y228 w210", "OBS Mute Fallback Shortcut:"), "Text", "tabText")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    edObsMute := ccGui.Add("Edit", "x250 y224 w430 h26", cfg.ObsMuteHotkey)
    Theme.RegisterControl(ccGui, edObsMute, "Edit")

    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y268 w210", "OBS Start/Stop Rec Shortcut:"), "Text", "tabText")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    edObsRec := ccGui.Add("Edit", "x250 y264 w430 h26", cfg.ObsRecHotkey)
    Theme.RegisterControl(ccGui, edObsRec, "Edit")

    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y308 w210", "OBS Pause Rec Shortcut:"), "Text", "tabText")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    edObsPause := ccGui.Add("Edit", "x250 y304 w430 h26", cfg.ObsPauseHotkey)
    Theme.RegisterControl(ccGui, edObsPause, "Edit")

    ; ==========================================================================
    ; TAB 3: POINTER & CLICKER
    ; ==========================================================================
    tabs.UseTab(3)
    ccGui.SetFont("s11 w700 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y60 w650", "Hardware Presentation Clicker, Cough Hold-to-Mute & Slide Routing"), "Text", "tabText")

    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y98 w210", "Active Pointer Mode:"), "Text", "tabText")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    ptrIdx := cfg.EnablePPT ? 1 : (cfg.EnableMicOnly ? 2 : 3)
    ddlPointerMode := ccGui.Add("DropDownList", "x250 y94 w430 Choose" ptrIdx, ["Full PPT + Mute", "Pointer Mute Only", "OFF"])
    Theme.RegisterControl(ccGui, ddlPointerMode, "DropDownList")

    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y138 w210", "Clicker Mute Button Key:"), "Text", "tabText")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    edHwMute := ccGui.Add("Edit", "x250 y134 w200 h26", cfg.HwMuteHotkey)
    Theme.RegisterControl(ccGui, edHwMute, "Edit")

    btnCapMute := ccGui.Add("Button", "x460 y132 w105 h28", "Capture Key")
    btnPtrTester := ccGui.Add("Button", "x575 y132 w105 h28", "Clicker Tester")
    Theme.RegisterControl(ccGui, btnCapMute, "Button", "tabButton")
    Theme.RegisterControl(ccGui, btnPtrTester, "Button", "tabButton")
    btnCapMute.OnEvent("Click", (*) => OpenPointerKeyCaptureDialog(edHwMute.Value, "Use Key", (newKey) => (edHwMute.Value := newKey)))
    btnPtrTester.OnEvent("Click", (*) => ShowPointerTester())

    chkPushToMute := ccGui.Add("Checkbox", "x32 y178 w648 h24" (cfg.EnablePushToMute ? " Checked" : ""), "Enable Cough / Push-to-Mute Gesture (Holding mute button >= 350ms unmutes automatically on release)")
    Theme.RegisterControl(ccGui, chkPushToMute, "Checkbox", "tabText")

    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y218 w648", "PowerPoint Background Slide Intercept Keys (Active in Full PPT + Mute Mode):"), "Text", "tabText")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    chkArrows := ccGui.Add("Checkbox", "x32 y248 w310 h24" (cfg.CatchArrows ? " Checked" : ""), "Arrow Keys (Up / Down / Left / Right)")
    chkPg := ccGui.Add("Checkbox", "x360 y248 w320 h24" (cfg.CatchPg ? " Checked" : ""), "PageUp / PageDown (Standard Clickers)")
    chkSpace := ccGui.Add("Checkbox", "x32 y280 w310 h24" (cfg.CatchSpace ? " Checked" : ""), "Spacebar (Advance Slide)")
    chkEnter := ccGui.Add("Checkbox", "x360 y280 w320 h24" (cfg.CatchEnter ? " Checked" : ""), "Enter Key (Advance / Activate Link)")
    chkTab := ccGui.Add("Checkbox", "x32 y312 w310 h24" (cfg.CatchTab ? " Checked" : ""), "Tab Key (Cycle Slide Hyperlinks)")
    chkEsc := ccGui.Add("Checkbox", "x360 y312 w320 h24" (cfg.CatchEsc ? " Checked" : ""), "Escape Key (End Slide Show)")
    for cCtrl in [chkArrows, chkPg, chkSpace, chkEnter, chkTab, chkEsc]
        Theme.RegisterControl(ccGui, cCtrl, "Checkbox", "tabText")

    ; ==========================================================================
    ; TAB 4: HUD & APPEARANCE
    ; ==========================================================================
    tabs.UseTab(4)
    ccGui.SetFont("s11 w700 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y60 w650", "HUD Scale, Color Palettes, Magnetic Snapping & Smart Visibility"), "Text", "tabText")

    scaleValues := [0.25, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 5.0]
    scaleLabels := ["Tiny (0.25x)", "Small (0.5x)", "Normal (1.0x)", "Large (1.5x)", "Huge (2.0x)", "Massive (2.5x)", "Colossal (3.0x)", "Gigantic (5.0x)"]
    scIdx := 3
    for idx, sv in scaleValues {
        if (Abs(cfg.IndicatorScale - sv) < 0.01)
            scIdx := idx
    }
    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y96 w130", "Indicator Scale:"), "Text", "tabText")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    ddlScale := ccGui.Add("DropDownList", "x165 y92 w175 Choose" scIdx, scaleLabels)
    Theme.RegisterControl(ccGui, ddlScale, "DropDownList")

    opIdx := (cfg.OpacityLevel == UIConstants.OPACITY_SOLID) ? 1 : ((cfg.OpacityLevel == UIConstants.OPACITY_GHOST) ? 3 : 2)
    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x360 y96 w130", "Transparency:"), "Text", "tabText")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    ddlOpacity := ccGui.Add("DropDownList", "x495 y92 w185 Choose" opIdx, ["Solid (100%)", "Frosted (85%)", "Ghost (50%)"])
    Theme.RegisterControl(ccGui, ddlOpacity, "DropDownList")

    palNames := GetHudColorPresetNames()
    palIdx := 1
    for idx, pName in palNames {
        if (StrLower(cfg.HudColorPreset) = StrLower(pName))
            palIdx := idx
    }
    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y134 w130", "Color Palette:"), "Text", "tabText")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    ddlPalette := ccGui.Add("DropDownList", "x165 y130 w175 Choose" palIdx, palNames)
    Theme.RegisterControl(ccGui, ddlPalette, "DropDownList")

    themeModes := ["System", "Dark", "Light"]
    tmIdx := (cfg.ThemeMode = "Dark") ? 2 : ((cfg.ThemeMode = "Light") ? 3 : 1)
    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x360 y134 w130", "Window Theme:"), "Text", "tabText")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    ddlTheme := ccGui.Add("DropDownList", "x495 y130 w185 Choose" tmIdx, themeModes)
    Theme.RegisterControl(ccGui, ddlTheme, "DropDownList")

    chkShowInd := ccGui.Add("Checkbox", "x32 y174 w310 h24" (cfg.ShowIndicator ? " Checked" : ""), "Show Primary Mute HUD Indicator")
    chkShowExtra := ccGui.Add("Checkbox", "x360 y174 w320 h24" (cfg.ShowExtraHuds ? " Checked" : ""), "Show Extra Telemetry HUDs (Rows 2-4)")
    chkShowText := ccGui.Add("Checkbox", "x32 y204 w310 h24" (cfg.ShowText ? " Checked" : ""), "Show Text Labels Next to Icons")
    chkMonoIcon := ccGui.Add("Checkbox", "x360 y204 w320 h24" (cfg.MonoIcon ? " Checked" : ""), "Use Monochromatic White Icons")
    chkSleek := ccGui.Add("Checkbox", "x32 y234 w310 h24" (cfg.SleekCorners ? " Checked" : ""), "Use Sleek Rounded-Square Corners")
    chkPulse := ccGui.Add("Checkbox", "x360 y234 w320 h24" (cfg.AggressivePulse ? " Checked" : ""), "Aggressive Breathing Pulse When Muted")
    chkClickPills := ccGui.Add("Checkbox", "x32 y264 w310 h24" (cfg.EnableHudClickActions ? " Checked" : ""), "Interactive Clickable HUD Pills (Quick Actions)")
    chkMagSnap := ccGui.Add("Checkbox", "x360 y264 w320 h24" (cfg.EnableMagneticSnap ? " Checked" : ""), "Magnetic Screen-Edge & App Window Snapping")
    chkAutoDodge := ccGui.Add("Checkbox", "x32 y294 w310 h24" (cfg.HudAutoDodge ? " Checked" : ""), "Auto-Dodge HUD on Mouse Hover (15% Ghost)")
    chkClickThru := ccGui.Add("Checkbox", "x360 y294 w320 h24" (cfg.HudClickThrough ? " Checked" : ""), "Click-Through HUD Mode (Hold Alt to Drag)")
    for hCtrl in [chkShowInd, chkShowExtra, chkShowText, chkMonoIcon, chkSleek, chkPulse, chkClickPills, chkMagSnap, chkAutoDodge, chkClickThru]
        Theme.RegisterControl(ccGui, hCtrl, "Checkbox", "tabText")

    btnResetPos := ccGui.Add("Button", "x32 y340 w310 h30", "Reset HUD Position to Default")
    btnResetApp := ccGui.Add("Button", "x360 y340 w320 h30", "Restore Default HUD Appearance")
    Theme.RegisterControl(ccGui, btnResetPos, "Button", "tabButton")
    Theme.RegisterControl(ccGui, btnResetApp, "Button", "tabButton")
    btnResetPos.OnEvent("Click", (*) => ResetTrayPosition(cfg, state))

    ; ==========================================================================
    ; TAB 5: REMOTE COMPANION
    ; ==========================================================================
    tabs.UseTab(5)
    ccGui.SetFont("s11 w700 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y60 w650", "Smart Board & Secondary Laptop Companion (1-Tier Mic HUD + Clicker Sync)"), "Text", "tabText")

    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y98 w210", "Remote Network Mode:"), "Text", "tabText")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    rNetIdx := (cfg.RemoteNetworkMode = "Internet") ? 2 : 1
    ddlRemoteNet := ccGui.Add("DropDownList", "x250 y94 w430 Choose" rNetIdx, ["Same Router (LAN)", "Different Networks (Internet)"])
    Theme.RegisterControl(ccGui, ddlRemoteNet, "DropDownList")

    if (cfg.InternetPairingCode = "") {
        cfg.InternetPairingCode := GenerateInternetPairingCode()
        cfg.Write("Settings", "InternetPairingCode", cfg.InternetPairingCode)
    }

    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y138 w210", "Internet Pairing Code:"), "Text", "tabText")
    ccGui.SetFont("s10 w700 norm", Theme.UiFont)
    edPairCode := ccGui.Add("Edit", "x250 y134 w210 h26 ReadOnly", cfg.InternetPairingCode)
    Theme.RegisterControl(ccGui, edPairCode, "Edit")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    btnCopyPair := ccGui.Add("Button", "x470 y132 w100 h28", "Copy Code")
    btnNewPair := ccGui.Add("Button", "x580 y132 w100 h28", "New Code")
    Theme.RegisterControl(ccGui, btnCopyPair, "Button", "tabButton")
    Theme.RegisterControl(ccGui, btnNewPair, "Button", "tabButton")
    btnCopyPair.OnEvent("Click", (*) => (A_Clipboard := edPairCode.Value, TrayTip("Copied Pairing Code: " edPairCode.Value, "PresenterSync", 1)))
    btnNewPair.OnEvent("Click", (*) => (
        cfg.InternetPairingCode := GenerateInternetPairingCode(),
        cfg.Write("Settings", "InternetPairingCode", cfg.InternetPairingCode),
        edPairCode.Value := cfg.InternetPairingCode,
        IsObject(state) ? UpdateHostInternetRelay(cfg, state) : 0
    ))
    endpoints := GetLocalNetworkEndpoints()
    universalLanStr := A_ComputerName ".local"
    for ep in endpoints.ips
        universalLanStr .= ", " ep
    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y178 w210", "Universal LAN String:"), "Text", "tabText")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    edLanStr := ccGui.Add("Edit", "x250 y174 w320 h26 ReadOnly", universalLanStr)
    Theme.RegisterControl(ccGui, edLanStr, "Edit")
    btnCopyLan := ccGui.Add("Button", "x580 y172 w100 h28", "Copy LAN")
    Theme.RegisterControl(ccGui, btnCopyLan, "Button", "tabButton")
    btnCopyLan.OnEvent("Click", (*) => (A_Clipboard := edLanStr.Value, TrayTip("Copied LAN String: " edLanStr.Value, "PresenterSync", 1)))

    remNote := "Note: PresenterSync Remote stays a dedicated 1-tier Mic HUD on your secondary device. It works both with OBS Studio (LAN/Internet) and in Conferencing-Only Mode (Zoom/Teams/Meet) via the Companion Relay Bridge."
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y218 w648 h42", remNote), "Text", "tabMuted")

    btnRemDetails := ccGui.Add("Button", "x32 y272 w310 h32", "Open Full Remote Connection Dialog...")
    btnCloseRem := ccGui.Add("Button", "x360 y272 w320 h32", "Close Remote Companion on Secondary PC...")
    Theme.RegisterControl(ccGui, btnRemDetails, "Button", "tabButton")
    Theme.RegisterControl(ccGui, btnCloseRem, "Button", "tabButton")
    btnRemDetails.OnEvent("Click", (*) => ShowRemoteCompanionInfo(cfg, state))
    btnCloseRem.OnEvent("Click", (*) => PromptCloseRemoteCompanion(cfg, state))

    ; ==========================================================================
    ; TAB 6: PROFILES, SHORTCUTS & SYSTEM
    ; ==========================================================================
    tabs.UseTab(6)
    ccGui.SetFont("s11 w700 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y60 w650", "Named Configuration Profiles, Global Hotkeys & System Startup"), "Text", "tabText")

    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y96 w140", "Active Profile:"), "Text", "tabText")
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    profList := cfg.GetProfileNames()
    pChoose := 1
    for idx, pN in profList {
        if (StrLower(pN) = StrLower(cfg.ActiveProfile))
            pChoose := idx
    }
    ddlProfile := ccGui.Add("DropDownList", "x175 y92 w195 Choose" pChoose, profList)
    Theme.RegisterControl(ccGui, ddlProfile, "DropDownList")
    btnProfLoad := ccGui.Add("Button", "x380 y90 w94 h28", "Load")
    btnProfSave := ccGui.Add("Button", "x482 y90 w94 h28", "Save")
    btnProfMgr := ccGui.Add("Button", "x584 y90 w96 h28", "Manage...")
    Theme.RegisterControl(ccGui, btnProfLoad, "Button", "tabButton")
    Theme.RegisterControl(ccGui, btnProfSave, "Button", "tabButton")
    Theme.RegisterControl(ccGui, btnProfMgr, "Button", "tabButton")

    ccGui.SetFont("s9 w600 norm", Theme.UiFont)
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y138 w180", "Cycle Pointer Mode:"), "Text", "tabText")
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x368 y138 w160", "Toggle OBS Sync:"), "Text", "tabText")
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y174 w180", "Toggle Conf Monitor:"), "Text", "tabText")
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x368 y174 w160", "Show / Hide HUD:"), "Text", "tabText")
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x32 y210 w180", "Suspend All Hotkeys:"), "Text", "tabText")
    Theme.RegisterControl(ccGui, ccGui.Add("Text", "x368 y210 w160", "Exit Application:"), "Text", "tabText")

    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    edHkPpt := ccGui.Add("Edit", "x214 y134 w134 h26", cfg.PptHotkey)
    edHkWs := ccGui.Add("Edit", "x534 y134 w146 h26", cfg.WsHotkey)
    edHkZoom := ccGui.Add("Edit", "x214 y170 w134 h26", cfg.ZoomHotkey)
    edHkInd := ccGui.Add("Edit", "x534 y170 w146 h26", cfg.IndHotkey)
    edHkSusp := ccGui.Add("Edit", "x214 y206 w134 h26", cfg.SuspendHotkey)
    edHkExit := ccGui.Add("Edit", "x534 y206 w146 h26", cfg.ExitHotkey)
    for hkEd in [edHkPpt, edHkWs, edHkZoom, edHkInd, edHkSusp, edHkExit]
        Theme.RegisterControl(ccGui, hkEd, "Edit")

    chkStartup := ccGui.Add("Checkbox", "x32 y256 w380 h24" (cfg.StartWithWindows ? " Checked" : ""), "Start PresenterSync Automatically with Windows (Default: OFF)")
    Theme.RegisterControl(ccGui, chkStartup, "Checkbox", "tabText")

    btnCheckUpd := ccGui.Add("Button", "x430 y252 w250 h30", "Check for GitHub Updates...")
    Theme.RegisterControl(ccGui, btnCheckUpd, "Button", "tabButton")
    btnCheckUpd.OnEvent("Click", (*) => CheckForUpdates(UIConstants.APP_VERSION, "", false))

    tabs.UseTab()

    ; ==========================================================================
    ; BOTTOM BAR: STATUS + APPLY & SAVE + CLOSE
    ; ==========================================================================
    ccGui.SetFont("s9 w400 norm", Theme.UiFont)
    lblStatus := ccGui.Add("Text", "x20 y514 w380 h24", "Active Profile: " cfg.ActiveProfile "  |  PresenterSync v" UIConstants.APP_VERSION)
    Theme.RegisterControl(ccGui, lblStatus, "Text", "muted")

    ccGui.SetFont("s10 w600 norm", Theme.UiFont)
    btnApply := ccGui.Add("Button", "x416 y508 w140 h34 Default", "Apply && Save")
    btnClose := ccGui.Add("Button", "x566 y508 w140 h34", "Close")
    Theme.RegisterControl(ccGui, btnApply, "Button", "accent")
    Theme.RegisterControl(ccGui, btnClose, "Button")

    SyncControlsFromConfig() {
        ddlRouting.Choose(cfg.AudioRoutingMode >= 1 && cfg.AudioRoutingMode <= 3 ? cfg.AudioRoutingMode : 1)
        for i, cName in confApps {
            if (NormalizeConferencingApp(cfg.ConferencingApp) = cName)
                ddlConfApp.Choose(i)
        }
        edTargetMic.Value := cfg.targetMicName
        edZoomMute.Value := cfg.ZoomMuteHotkey
        edTeamsMute.Value := cfg.TeamsMuteHotkey
        edMeetMute.Value := cfg.MeetMuteHotkey
        edZoomRec.Value := cfg.ZoomRecHotkey
        edZoomPause.Value := cfg.ZoomPauseHotkey
        chkVoiceMeter.Value := cfg.ShowVoiceMeter ? 1 : 0
        chkAudioCue.Value := cfg.EnableAudioCue ? 1 : 0
        chkMuteToast.Value := cfg.EnableMuteToast ? 1 : 0
        chkEnableWS.Value := cfg.EnableWS ? 1 : 0
        chkEnableZoom.Value := cfg.EnableZoom ? 1 : 0
        edObsPass.Value := cfg.obsPassword
        chkStreamHud.Value := cfg.ShowStreamHud ? 1 : 0
        chkRecTimer.Value := cfg.ShowRecTimer ? 1 : 0
        edObsMute.Value := cfg.ObsMuteHotkey
        edObsRec.Value := cfg.ObsRecHotkey
        edObsPause.Value := cfg.ObsPauseHotkey
        ddlPointerMode.Choose(cfg.EnablePPT ? 1 : (cfg.EnableMicOnly ? 2 : 3))
        edHwMute.Value := cfg.HwMuteHotkey
        chkPushToMute.Value := cfg.EnablePushToMute ? 1 : 0
        chkArrows.Value := cfg.CatchArrows ? 1 : 0
        chkPg.Value := cfg.CatchPg ? 1 : 0
        chkSpace.Value := cfg.CatchSpace ? 1 : 0
        chkEnter.Value := cfg.CatchEnter ? 1 : 0
        chkTab.Value := cfg.CatchTab ? 1 : 0
        chkEsc.Value := cfg.CatchEsc ? 1 : 0
        for idx, sv in scaleValues {
            if (Abs(cfg.IndicatorScale - sv) < 0.01)
                ddlScale.Choose(idx)
        }
        ddlOpacity.Choose((cfg.OpacityLevel == UIConstants.OPACITY_SOLID) ? 1 : ((cfg.OpacityLevel == UIConstants.OPACITY_GHOST) ? 3 : 2))
        for idx, pName in palNames {
            if (StrLower(cfg.HudColorPreset) = StrLower(pName))
                ddlPalette.Choose(idx)
        }
        ddlTheme.Choose((cfg.ThemeMode = "Dark") ? 2 : ((cfg.ThemeMode = "Light") ? 3 : 1))
        chkShowInd.Value := cfg.ShowIndicator ? 1 : 0
        chkShowExtra.Value := cfg.ShowExtraHuds ? 1 : 0
        chkShowText.Value := cfg.ShowText ? 1 : 0
        chkMonoIcon.Value := cfg.MonoIcon ? 1 : 0
        chkSleek.Value := cfg.SleekCorners ? 1 : 0
        chkPulse.Value := cfg.AggressivePulse ? 1 : 0
        chkClickPills.Value := cfg.EnableHudClickActions ? 1 : 0
        chkMagSnap.Value := cfg.EnableMagneticSnap ? 1 : 0
        chkAutoDodge.Value := cfg.HudAutoDodge ? 1 : 0
        chkClickThru.Value := cfg.HudClickThrough ? 1 : 0
        ddlRemoteNet.Choose((cfg.RemoteNetworkMode = "Internet") ? 2 : 1)
        edPairCode.Value := cfg.InternetPairingCode
        edHkPpt.Value := cfg.PptHotkey
        edHkWs.Value := cfg.WsHotkey
        edHkZoom.Value := cfg.ZoomHotkey
        edHkInd.Value := cfg.IndHotkey
        edHkSusp.Value := cfg.SuspendHotkey
        edHkExit.Value := cfg.ExitHotkey
        chkStartup.Value := cfg.StartWithWindows ? 1 : 0
        profList := cfg.GetProfileNames()
        ddlProfile.Delete()
        ddlProfile.Add(profList)
        pChoose := 1
        for idx, pN in profList {
            if (StrLower(pN) = StrLower(cfg.ActiveProfile))
                pChoose := idx
        }
        ddlProfile.Choose(pChoose)
        lblStatus.Value := "Active Profile: " cfg.ActiveProfile "  |  PresenterSync v" UIConstants.APP_VERSION
    }

    btnResetApp.OnEvent("Click", (*) => (
        ResetAppearance(cfg, state),
        SyncControlsFromConfig(),
        lblStatus.Value := "Restored default HUD appearance."
    ))

    btnProfLoad.OnEvent("Click", (*) => (
        cfg.ApplyProfile(ddlProfile.Text, state) ? (SyncControlsFromConfig(), lblStatus.Value := "Loaded profile: " cfg.ActiveProfile) : (lblStatus.Value := "Save snapshot to '" ddlProfile.Text "' first.")
    ))
    btnProfSave.OnEvent("Click", (*) => (
        OnApplyClick() ? (
            cfg.SaveProfile(ddlProfile.Text),
            SyncControlsFromConfig(),
            lblStatus.Value := "Saved settings to profile: " cfg.ActiveProfile
        ) : 0
    ))
    btnProfMgr.OnEvent("Click", (*) => ShowProfileManagerUI(cfg, state))

    OnApplyClick(*) {
        selOpacity := (ddlOpacity.Value == 1) ? UIConstants.OPACITY_SOLID : ((ddlOpacity.Value == 3) ? UIConstants.OPACITY_GHOST : UIConstants.OPACITY_FROSTED)
        vals := {
            AudioRoutingMode: ddlRouting.Value,
            ConferencingApp: ddlConfApp.Text,
            targetMicName: edTargetMic.Value,
            ZoomMuteHotkey: edZoomMute.Value,
            TeamsMuteHotkey: edTeamsMute.Value,
            MeetMuteHotkey: edMeetMute.Value,
            ZoomRecHotkey: edZoomRec.Value,
            ZoomPauseHotkey: edZoomPause.Value,
            ShowVoiceMeter: chkVoiceMeter.Value,
            EnableAudioCue: chkAudioCue.Value,
            EnableMuteToast: chkMuteToast.Value,
            EnableWS: chkEnableWS.Value,
            EnableZoom: chkEnableZoom.Value,
            obsPassword: edObsPass.Value,
            ShowStreamHud: chkStreamHud.Value,
            ShowRecTimer: chkRecTimer.Value,
            ObsMuteHotkey: edObsMute.Value,
            ObsRecHotkey: edObsRec.Value,
            ObsPauseHotkey: edObsPause.Value,
            PointerMode: ddlPointerMode.Text,
            HwMuteHotkey: edHwMute.Value,
            EnablePushToMute: chkPushToMute.Value,
            CatchArrows: chkArrows.Value,
            CatchPg: chkPg.Value,
            CatchSpace: chkSpace.Value,
            CatchEnter: chkEnter.Value,
            CatchTab: chkTab.Value,
            CatchEsc: chkEsc.Value,
            IndicatorScale: scaleValues[ddlScale.Value],
            OpacityLevel: selOpacity,
            HudColorPreset: ddlPalette.Text,
            ThemeMode: ddlTheme.Text,
            ShowIndicator: chkShowInd.Value,
            ShowExtraHuds: chkShowExtra.Value,
            ShowText: chkShowText.Value,
            MonoIcon: chkMonoIcon.Value,
            SleekCorners: chkSleek.Value,
            AggressivePulse: chkPulse.Value,
            EnableHudClickActions: chkClickPills.Value,
            EnableMagneticSnap: chkMagSnap.Value,
            HudAutoDodge: chkAutoDodge.Value,
            HudClickThrough: chkClickThru.Value,
            RemoteNetworkMode: (ddlRemoteNet.Value == 2) ? "Internet" : "LAN",
            PptHotkey: edHkPpt.Value,
            WsHotkey: edHkWs.Value,
            ZoomHotkey: edHkZoom.Value,
            IndHotkey: edHkInd.Value,
            SuspendHotkey: edHkSusp.Value,
            ExitHotkey: edHkExit.Value,
            StartWithWindows: chkStartup.Value
        }
        invalidKeys := []
        ok := ApplyControlCenterSettings(cfg, state, vals, true, invalidKeys)
        if (!ok && invalidKeys.Length > 0) {
            badLabels := ""
            for idx, item in invalidKeys
                badLabels .= (idx > 1 ? ", " : "") item.label " ('" item.value "')"
            SyncControlsFromConfig()
            lblStatus.Value := "Ignored invalid hotkey: " badLabels " (valid settings saved)."
            return false
        }
        lblStatus.Value := "All settings applied and saved live (" FormatTime(, "HH:mm:ss") ")."
        return true
    }

    CloseControlCenter(*) {
        if (ccGui._closed)
            return
        ccGui._closed := true
        Theme.UnregisterWindow(ccGui, "PresenterSync - Control Center")
        Theme.ReleaseSuspend()
        ccGui.Destroy()
    }

    btnApply.OnEvent("Click", OnApplyClick)
    btnClose.OnEvent("Click", CloseControlCenter)
    ccGui.OnEvent("Close", CloseControlCenter)
    ccGui.OnEvent("Escape", CloseControlCenter)

    ccGui.Show("w720 h556")
    return ccGui
}

