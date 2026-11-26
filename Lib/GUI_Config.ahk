; ==============================================================================
; Module: GUI_Config.ahk
; Description: UIConstants, Config & OverlayState classes, Settings GUIs, HUD layout & animations
; ==============================================================================

global g_IsTestMode := false

#Include "%A_LineFile%\..\Crypto.ahk"
#Include "%A_LineFile%\..\Gdip.ahk"
#Include "%A_LineFile%\..\QrCode.ahk"
#Include "%A_LineFile%\..\OBS_Network.ahk"
#Include "%A_LineFile%\..\HelpCenter.ahk"
#Include "%A_LineFile%\..\DiagnosticLogger.ahk"
#Include "%A_LineFile%\..\ConfigStore.ahk"
#Include "%A_LineFile%\..\WindowFit.ahk"

class UIConstants {
    static APP_VERSION := "9.7.0"

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
    static VOICE_METER_INTERVAL_MS := 50
    static MUTED_VOICE_THRESHOLD := 0.12
    static MUTED_VOICE_TRIGGER_MS := 1500
    static MUTED_VOICE_CLEAR_MS := 1500
    static MUTED_VOICE_POLL_MS := 250
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
    static MIC_LONG_PRESS_MS := 600
    static STUDIO_LONG_PRESS_MS := 600
    static REC_STOP_LONG_PRESS_MS := 900
    static STOP_RECORD_CONFIRM_WINDOW_MS := 3000

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

    static GetColorPalette(presetName := "Standard", customLiveHex := "107C10", customMutedHex := "C42B1C") {
        switch NormalizeHudColorPreset(presetName) {
            case "Custom":
                cLive := NormalizeColorHex(customLiveHex, "107C10")
                cMuted := NormalizeColorHex(customMutedHex, "C42B1C")
                return UIConstants._MakePalette(
                    cLive, PickReadableIconHex(cLive),
                    cMuted, PickReadableIconHex(cMuted),
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

NormalizeColorHex(rawHex, fallback := "107C10") {
    clean := RegExReplace(Trim(String(rawHex)), "^(#|0x|0X)", "")
    if RegExMatch(clean, "^[0-9A-Fa-f]{6}$")
        return StrUpper(clean)
    fb := RegExReplace(Trim(String(fallback)), "^(#|0x|0X)", "")
    return RegExMatch(fb, "^[0-9A-Fa-f]{6}$") ? StrUpper(fb) : "107C10"
}

_SrgbLinearize(channel255) {
    chNorm := Float(channel255) / 255.0
    return (chNorm <= 0.03928) ? (chNorm / 12.92) : (((chNorm + 0.055) / 1.055) ** 2.4)
}

ColorRelativeLuminance(hexStr) {
    h := NormalizeColorHex(hexStr, "000000")
    r := _SrgbLinearize(Integer("0x" SubStr(h, 1, 2)))
    g := _SrgbLinearize(Integer("0x" SubStr(h, 3, 2)))
    b := _SrgbLinearize(Integer("0x" SubStr(h, 5, 2)))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b
}

PickReadableIconHex(bgHex) {
    lumBg := ColorRelativeLuminance(bgHex)
    lumDark := 0.008568 ; Relative luminance of #111827
    contrastWhite := 1.05 / (lumBg + 0.05)
    contrastDark := (Max(lumBg, lumDark) + 0.05) / (Min(lumBg, lumDark) + 0.05)
    return (contrastDark > contrastWhite) ? "111827" : "FFFFFF"
}

GetHudColorPresetNames() {
    return ["Standard", "Colorblind Safe", "OLED Stealth", "Broadcast Tally", "Cyber Ocean", "Custom"]
}

NormalizeHudVisibilityMode(mode) {
    m := StrLower(Trim(String(mode)))
    if (m = "mutedoralert")
        return "MutedOrAlert"
    if (m = "cornertallydot")
        return "CornerTallyDot"
    return "Always"
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
    static IID_IAudioEndpointVolume := "{5CDF2C82-841E-4546-9722-0CF74078229A}"
    static _enum := ""
    static _meter := ""
    static _nextRetryTick := 0
    static _epVol := ""
    static _nextEpRetryTick := 0
    static _activeDeviceId := ""
    static _lastHotSwapCheckTick := 0
    static _mockOsMute := ""
    static _mockSetOsMuteFn := ""

    static NormalizePeak(rawPeak) {
        p := Min(1.0, Max(0.0, Float(rawPeak)))
        return (p > 0.005) ? Min(1.0, Sqrt(p)) : 0.0
    }

    static Shutdown() {
        this._meter := ""
        this._epVol := ""
        this._enum := ""
        this._nextRetryTick := 0
        this._nextEpRetryTick := 0
        this._activeDeviceId := ""
    }

    static GetDefaultCaptureDeviceId() {
        try {
            if (!IsObject(this._enum))
                this._enum := ComObject("{BCDE0395-E52F-467C-8E3D-C4579291692E}", "{A95664D2-9614-4F35-A746-DE8DB63617E6}")
            pDev := 0
            try ComCall(4, this._enum, "Int", 1, "Int", 2, "Ptr*", &pDev)
            if (!pDev)
                try ComCall(4, this._enum, "Int", 1, "Int", 0, "Ptr*", &pDev)
            if (!pDev)
                return ""
            dev := ComValue(13, pDev)
            pId := 0
            try ComCall(5, dev, "Ptr*", &pId) ; IMMDevice::GetId
            if (pId) {
                idStr := StrGet(pId, "UTF-16")
                DllCall("ole32\CoTaskMemFree", "Ptr", pId)
                return idStr
            }
        }
        return ""
    }

    static CheckHotSwapRebind(nowTick := "") {
        if (nowTick = "")
            nowTick := A_TickCount
        if (nowTick - this._lastHotSwapCheckTick < 3000)
            return false
        this._lastHotSwapCheckTick := nowTick
        curId := this.GetDefaultCaptureDeviceId()
        if (curId != "" && this._activeDeviceId != "" && curId != this._activeDeviceId) {
            this.Shutdown()
            this._activeDeviceId := curId
            if (IsSet(DiagnosticLogger))
                try DiagnosticLogger.RecordBreadcrumb("Audio", "CoreAudioHotSwapRebind", "newDev=" SubStr(curId, 1, 24))
            return true
        }
        if (curId != "" && this._activeDeviceId = "")
            this._activeDeviceId := curId
        return false
    }

    static Reset() {
        this.Shutdown()
    }

    static _ActivateCaptureInterface(iidStr, retryProp := "_nextEpRetryTick") {
        if (A_TickCount < this.%retryProp%)
            return ""
        try {
            if (!IsObject(this._enum))
                this._enum := ComObject("{BCDE0395-E52F-467C-8E3D-C4579291692E}", "{A95664D2-9614-4F35-A746-DE8DB63617E6}")
            pDev := 0
            try ComCall(4, this._enum, "Int", 1, "Int", 2, "Ptr*", &pDev)
            if (!pDev)
                try ComCall(4, this._enum, "Int", 1, "Int", 0, "Ptr*", &pDev)
            if (!pDev) {
                this.%retryProp% := A_TickCount + 5000
                return ""
            }
            dev := ComValue(13, pDev)
            iidBuf := Buffer(16, 0)
            hrGuid := DllCall("ole32\CLSIDFromString", "WStr", iidStr, "Ptr", iidBuf, "Int")
            if (hrGuid != 0) {
                this.%retryProp% := A_TickCount + 5000
                return ""
            }
            pIface := 0
            ComCall(3, dev, "Ptr", iidBuf, "UInt", 23, "Ptr", 0, "Ptr*", &pIface)
            if (!pIface) {
                this.%retryProp% := A_TickCount + 5000
                return ""
            }
            return ComValue(13, pIface)
        } catch {
            this._enum := ""
            this.%retryProp% := A_TickCount + 3000
            return ""
        }
    }

    static _EnsureEndpointVolume() {
        if (IsObject(this._epVol))
            return this._epVol
        epVol := this._ActivateCaptureInterface(this.IID_IAudioEndpointVolume, "_nextEpRetryTick")
        if (IsObject(epVol))
            this._epVol := epVol
        return this._epVol
    }

    static GetOsMicMute() {
        if (Type(this._mockOsMute) != "String" || this._mockOsMute != "") {
            m := this._mockOsMute
            if (m == -1 || m = "-1")
                return -1
            if (m = "0" || (Type(m) = "String" && StrLower(Trim(m)) = "false"))
                return false
            return !!m
        }
        epVol := this._EnsureEndpointVolume()
        if (!IsObject(epVol))
            return -1
        try {
            isMuted := 0
            hr := ComCall(15, epVol, "Int*", &isMuted)
            if (hr != 0)
                return -1
            return !!isMuted
        } catch {
            this._epVol := ""
            this._enum := ""
            this._nextEpRetryTick := A_TickCount + 3000
            return -1
        }
    }

    static SetOsMicMute(muted) {
        target := !!muted
        if (IsObject(this._mockSetOsMuteFn)) {
            try return !!this._mockSetOsMuteFn.Call(target)
            catch
                return false
        }
        epVol := this._EnsureEndpointVolume()
        if (!IsObject(epVol))
            return false
        try {
            hr := ComCall(14, epVol, "Int", target ? 1 : 0, "Ptr", 0)
            return (hr == 0)
        } catch {
            this._epVol := ""
            this._enum := ""
            this._nextEpRetryTick := A_TickCount + 3000
            return false
        }
    }

    static GetPeak() {
        try {
            if (!IsObject(this._meter)) {
                meter := this._ActivateCaptureInterface("{C02216F6-8C67-4B5B-9D00-D008E73E0064}", "_nextRetryTick")
                if (!IsObject(meter))
                    return 0.0
                this._meter := meter
            }
            peak := 0.0
            ComCall(3, this._meter, "Float*", &peak)
            return AudioMeter.NormalizePeak(peak)
        } catch {
            this._meter := ""
            this._enum := ""
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
    static _uxthemeLoaded := false
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
        try OnMessage(0x001A, WM_SETTINGCHANGE_Theme, 0)
        for _, propName in ["hkSubclassPtr", "tabSubclassPtr", "staticSubclassPtr", "btnSubclassPtr"] {
            if (this.%propName%) {
                try CallbackFree(this.%propName%)
                this.%propName% := 0
            }
        }
        if (this._uxthemeLoaded && this.hUxtheme) {
            DllCall("FreeLibrary", "Ptr", this.hUxtheme)
            this.hUxtheme := 0
            this._uxthemeLoaded := false
        }
        this.initialized := false
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
        if (!this.hUxtheme) {
            this.hUxtheme := DllCall("LoadLibrary", "Str", "uxtheme", "Ptr")
            this._uxthemeLoaded := (this.hUxtheme != 0)
        }
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

    static IsHighContrastActive() {
        buf := Buffer(16, 0)
        NumPut("UInt", 16, buf, 0)
        try {
            if (DllCall("user32\SystemParametersInfoW", "UInt", 0x0042, "UInt", 16, "Ptr", buf.Ptr, "UInt", 0, "Int"))
                return !!(NumGet(buf, 4, "UInt") & 0x1)
        }
        return false
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

    static ApplyToWindow(guiObj, isDark := "", excludeFromCapture := "") {
        this.EnsureInitialized()
        if (isDark = "")
            isDark := this.IsDarkMode()
        this.ApplyMenuTheme(isDark)
        this.ApplyTitleBarTheme(guiObj.Hwnd, isDark)
        shouldExclude := (excludeFromCapture != "") ? !!excludeFromCapture : true
        if (IsSet(ProtectWindowFromCapture))
            try ProtectWindowFromCapture(guiObj.Hwnd, shouldExclude)
        try guiObj.Opt("+0x02000000") ; WS_CLIPCHILDREN prevents parent redraw from erasing themed children
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
        } else if (ctrlType = "ListBox" || ctrlType = "ListView") {
            ctrl.Opt(isDark ? ("+Background" UIConstants.DARK_INPUT_BG " c" UIConstants.DARK_TEXT) : ("+Background" UIConstants.LIGHT_SURFACE " c" UIConstants.LIGHT_TEXT))
            DllCall("uxtheme\SetWindowTheme", "Ptr", ctrl.Hwnd, "Str", isDark ? "DarkMode_Explorer" : "Explorer", "Ptr", 0)
        } else if (ctrlType = "DropDownList") {
            ctrl.Opt(isDark ? ("+Background" UIConstants.DARK_INPUT_BG " c" UIConstants.DARK_TEXT) : ("+Background" UIConstants.LIGHT_SURFACE " c" UIConstants.LIGHT_TEXT))
            DllCall("uxtheme\SetWindowTheme", "Ptr", ctrl.Hwnd, "Str", isDark ? "DarkMode_CFD" : "Explorer", "Ptr", 0)
        } else if (ctrlType = "Hotkey") {
            DllCall("comctl32\SetWindowSubclass", "Ptr", ctrl.Hwnd, "Ptr", this.hkSubclassPtr, "Ptr", 1, "Ptr", 0)
            DllCall("InvalidateRect", "Ptr", ctrl.Hwnd, "Ptr", 0, "Int", 1)
        } else if (ctrlType = "Tab") {
            try ctrl.Opt("-0x0200") ; strip TCS_MULTILINE to keep a clean single row
            rc := Buffer(16, 0)
            DllCall("GetClientRect", "Ptr", ctrl.Hwnd, "Ptr", rc)
            tw := NumGet(rc, 8, "Int")
            tabCount := SendMessage(0x1304, 0, 0, ctrl.Hwnd) ; TCM_GETITEMCOUNT
            if (tabCount > 0 && tw > 0) {
                dpiScale := A_ScreenDPI / 96.0
                itemH := Round(36 * dpiScale)
                itemW := Max(24, Floor((tw - 14) / tabCount))
                SendMessage(0x1329, 0, (itemH << 16) | (itemW & 0xFFFF), ctrl.Hwnd) ; TCM_SETITEMSIZE
                Loop 24 {
                    if (SendMessage(0x132C, 0, 0, ctrl.Hwnd) <= 1 || itemW <= 24) ; TCM_GETROWCOUNT
                        break
                    itemW -= 2
                    SendMessage(0x1329, 0, (itemH << 16) | (itemW & 0xFFFF), ctrl.Hwnd)
                }
            }
            DllCall("comctl32\SetWindowSubclass", "Ptr", ctrl.Hwnd, "Ptr", this.tabSubclassPtr, "Ptr", 2, "Ptr", 0)
            if (!ctrl.HasOwnProp("_fluentChangeHooked")) {
                ctrl._fluentChangeHooked := true
                ctrl.OnEvent("Change", (tc, *) => DllCall("RedrawWindow", "Ptr", tc.Gui.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x0185))
            }
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
            try WinSetStyle("+0x80", ctrl.Hwnd) ; SS_NOPREFIX so literal '&' renders cleanly
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
        if (guiObj.HasOwnProp("_onThemeRefresh") && guiObj._onThemeRefresh) {
            try guiObj._onThemeRefresh.Call()
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
    pPen := 0
    pAccPath := 0
    pAccFill := 0
    try {
        DllCall("gdiplus\GdipCreateSolidFill", "UInt", fillArgb, "Ptr*", &pFill)
        if (pFill)
            DllCall("gdiplus\GdipFillPath", "Ptr", pGraphics, "Ptr", pFill, "Ptr", pPath)
        if (strokeArgb != 0) {
            DllCall("gdiplus\GdipCreatePen1", "UInt", strokeArgb, "Float", 1.0, "Int", 2, "Ptr*", &pPen)
            if (pPen)
                DllCall("gdiplus\GdipDrawPath", "Ptr", pGraphics, "Ptr", pPen, "Ptr", pPath)
        }
        if (bottomAccentArgb != 0) {
            pAccPath := Gdip.CreateRoundedRectPath(x + 2.0, y + h - 3.0, w - 5.0, 2.0, 1.0)
            if (pAccPath) {
                DllCall("gdiplus\GdipCreateSolidFill", "UInt", bottomAccentArgb, "Ptr*", &pAccFill)
                if (pAccFill)
                    DllCall("gdiplus\GdipFillPath", "Ptr", pGraphics, "Ptr", pAccFill, "Ptr", pAccPath)
            }
        }
    } finally {
        if (pAccFill)
            DllCall("gdiplus\GdipDeleteBrush", "Ptr", pAccFill)
        if (pAccPath)
            DllCall("gdiplus\GdipDeletePath", "Ptr", pAccPath)
        if (pPen)
            DllCall("gdiplus\GdipDeletePen", "Ptr", pPen)
        if (pFill)
            DllCall("gdiplus\GdipDeleteBrush", "Ptr", pFill)
        DllCall("gdiplus\GdipDeletePath", "Ptr", pPath)
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
    try {
        DllCall("SetBkMode", "Ptr", hdc, "Int", 1) ; TRANSPARENT
        DllCall("SetTextColor", "Ptr", hdc, "UInt", textColorBgr)
        DllCall("DrawTextW", "Ptr", hdc, "WStr", textStr, "Int", -1, "Ptr", tRc, "UInt", alignFlags)
    } finally {
        if (oldFont)
            DllCall("SelectObject", "Ptr", hdc, "Ptr", oldFont, "Ptr")
    }
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
        hdcMem := 0
        hbm := 0
        obm := 0
        hBrParent := 0
        pGraphics := 0
        try {
            if (!hdc)
                return 0
            rc := Buffer(16, 0)
            DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rc)
            w := NumGet(rc, 8, "Int"), h := NumGet(rc, 12, "Int")

            hdcMem := DllCall("CreateCompatibleDC", "Ptr", hdc, "Ptr")
            hbm := DllCall("CreateCompatibleBitmap", "Ptr", hdc, "Int", Max(1, w), "Int", Max(1, h), "Ptr")
            if (!hdcMem || !hbm)
                return 0
            obm := DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hbm, "Ptr")

            ctrl := GuiCtrlFromHwnd(hwnd)
            parentDark := (IsObject(ctrl) && IsObject(ctrl.Gui) && ctrl.Gui.HasOwnProp("_isDark")) ? ctrl.Gui._isDark : Theme.IsDarkMode()
            inTab := (IsObject(ctrl) && ctrl.HasOwnProp("_inTab") && ctrl._inTab)
            parentBgBgr := parentDark ? (inTab ? UIConstants.DARK_SURFACE_BGR : UIConstants.DARK_BG_BGR) : (inTab ? UIConstants.LIGHT_SURFACE_BGR : UIConstants.LIGHT_BG_BGR)

            hBrParent := DllCall("CreateSolidBrush", "UInt", parentBgBgr, "Ptr")
            if (hBrParent)
                DllCall("FillRect", "Ptr", hdcMem, "Ptr", rc, "Ptr", hBrParent)

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

            DllCall("gdiplus\GdipCreateFromHDC", "Ptr", hdcMem, "Ptr*", &pGraphics)
            if (pGraphics) {
                DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", pGraphics, "Int", 4)
                DrawFluentRoundedBox(pGraphics, 0, 0, w, h, UIConstants.FLUENT_CORNER_RADIUS, fillArgb, strokeArgb)
                DllCall("gdiplus\GdipDeleteGraphics", "Ptr", pGraphics)
                pGraphics := 0
            }

            btnTxt := IsObject(ctrl) ? StrReplace(ctrl.Text, "&&", "&") : ""
            hFont := Theme.GetFont(hwnd, 400)
            DrawFluentControlText(hdcMem, btnTxt, 4, 0, w - 8, h, hFont, txtBgr, 0x0825)

            DllCall("BitBlt", "Ptr", hdc, "Int", 0, "Int", 0, "Int", w, "Int", h, "Ptr", hdcMem, "Int", 0, "Int", 0, "UInt", 0x00CC0020)
            return 0
        } finally {
            if (pGraphics)
                DllCall("gdiplus\GdipDeleteGraphics", "Ptr", pGraphics)
            if (hBrParent)
                DllCall("DeleteObject", "Ptr", hBrParent)
            if (hdcMem && obm)
                DllCall("SelectObject", "Ptr", hdcMem, "Ptr", obm)
            if (hbm)
                DllCall("DeleteObject", "Ptr", hbm)
            if (hdcMem)
                DllCall("DeleteDC", "Ptr", hdcMem)
            DllCall("EndPaint", "Ptr", hwnd, "Ptr", ps)
        }
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
        hdcMem := 0
        hbm := 0
        obm := 0
        hBrParent := 0
        pGraphics := 0
        try {
            if (!hdc)
                return 0
            rc := Buffer(16, 0)
            DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rc)
            w := NumGet(rc, 8, "Int"), h := NumGet(rc, 12, "Int")

            hdcMem := DllCall("CreateCompatibleDC", "Ptr", hdc, "Ptr")
            hbm := DllCall("CreateCompatibleBitmap", "Ptr", hdc, "Int", Max(1, w), "Int", Max(1, h), "Ptr")
            if (!hdcMem || !hbm)
                return 0
            obm := DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hbm, "Ptr")

            ctrl := GuiCtrlFromHwnd(hwnd)
            parentDark := (IsObject(ctrl) && IsObject(ctrl.Gui) && ctrl.Gui.HasOwnProp("_isDark")) ? ctrl.Gui._isDark : Theme.IsDarkMode()
            isEnabled := DllCall("IsWindowEnabled", "Ptr", hwnd)
            hasFocus := (DllCall("GetFocus", "Ptr") == hwnd)

            inTab := (IsObject(ctrl) && ctrl.HasOwnProp("_inTab") && ctrl._inTab)
            parentBgBgr := parentDark ? (inTab ? UIConstants.DARK_SURFACE_BGR : UIConstants.DARK_BG_BGR) : (inTab ? UIConstants.LIGHT_SURFACE_BGR : UIConstants.LIGHT_BG_BGR)
            hBrParent := DllCall("CreateSolidBrush", "UInt", parentBgBgr, "Ptr")
            if (hBrParent)
                DllCall("FillRect", "Ptr", hdcMem, "Ptr", rc, "Ptr", hBrParent)

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

            DllCall("gdiplus\GdipCreateFromHDC", "Ptr", hdcMem, "Ptr*", &pGraphics)
            if (pGraphics) {
                DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", pGraphics, "Int", 4)
                DrawFluentRoundedBox(pGraphics, 0, 0, w, h, UIConstants.FLUENT_CORNER_RADIUS, fillArgb, strokeArgb, accArgb)
                DllCall("gdiplus\GdipDeleteGraphics", "Ptr", pGraphics)
                pGraphics := 0
            }

            dispTxt := IsObject(ctrl) ? FormatHkDisplayText(ctrl.Value) : "None"
            hFont := Theme.GetFont(hwnd, false)
            DrawFluentControlText(hdcMem, dispTxt, 8, 0, w - 16, h - 2, hFont, txtBgr, 0x0024)

            DllCall("BitBlt", "Ptr", hdc, "Int", 0, "Int", 0, "Int", w, "Int", h, "Ptr", hdcMem, "Int", 0, "Int", 0, "UInt", 0x00CC0020)
            return 0
        } finally {
            if (pGraphics)
                DllCall("gdiplus\GdipDeleteGraphics", "Ptr", pGraphics)
            if (hBrParent)
                DllCall("DeleteObject", "Ptr", hBrParent)
            if (hdcMem && obm)
                DllCall("SelectObject", "Ptr", hdcMem, "Ptr", obm)
            if (hbm)
                DllCall("DeleteObject", "Ptr", hbm)
            if (hdcMem)
                DllCall("DeleteDC", "Ptr", hdcMem)
            DllCall("EndPaint", "Ptr", hwnd, "Ptr", ps)
        }
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
        hdcMem := 0
        hbm := 0
        obm := 0
        hBrBg := 0
        pGraphics := 0
        pPill := 0
        pPillBr := 0
        try {
            if (!hdc)
                return 0
            rc := Buffer(16, 0)
            DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rc)
            w := NumGet(rc, 8, "Int"), h := NumGet(rc, 12, "Int")

            hdcMem := DllCall("CreateCompatibleDC", "Ptr", hdc, "Ptr")
            hbm := DllCall("CreateCompatibleBitmap", "Ptr", hdc, "Int", Max(1, w), "Int", Max(1, h), "Ptr")
            if (!hdcMem || !hbm)
                return 0
            obm := DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hbm, "Ptr")

            ctrl := GuiCtrlFromHwnd(hwnd)
            parentDark := (IsObject(ctrl) && IsObject(ctrl.Gui) && ctrl.Gui.HasOwnProp("_isDark")) ? ctrl.Gui._isDark : Theme.IsDarkMode()
            bgBgr := parentDark ? UIConstants.DARK_BG_BGR : UIConstants.LIGHT_BG_BGR

            hBrBg := DllCall("CreateSolidBrush", "UInt", bgBgr, "Ptr")
            if (hBrBg)
                DllCall("FillRect", "Ptr", hdcMem, "Ptr", rc, "Ptr", hBrBg)

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
                            DllCall("gdiplus\GdipCreateSolidFill", "UInt", accPillArgb, "Ptr*", &pPillBr)
                            if (pPillBr) {
                                DllCall("gdiplus\GdipFillPath", "Ptr", pGraphics, "Ptr", pPillBr, "Ptr", pPill)
                                DllCall("gdiplus\GdipDeleteBrush", "Ptr", pPillBr)
                                pPillBr := 0
                            }
                            DllCall("gdiplus\GdipDeletePath", "Ptr", pPill)
                            pPill := 0
                        }
                    } else if (idx == hoverIdx) {
                        DrawFluentRoundedBox(pGraphics, tx, ty, tw, th, UIConstants.FLUENT_CORNER_RADIUS, tabHoverFill, tabHoverStroke)
                    }
                }

                DllCall("gdiplus\GdipDeleteGraphics", "Ptr", pGraphics)
                pGraphics := 0
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
                DrawFluentControlText(hdcMem, lbl, tx + 2, ty, tw - 4, th - 1, isSel ? hFontBold : hFontReg, isSel ? txtActiveBgr : txtMutedBgr, 0x0825)
            }

            DllCall("BitBlt", "Ptr", hdc, "Int", 0, "Int", 0, "Int", w, "Int", h, "Ptr", hdcMem, "Int", 0, "Int", 0, "UInt", 0x00CC0020)
            return 0
        } finally {
            if (pPillBr)
                DllCall("gdiplus\GdipDeleteBrush", "Ptr", pPillBr)
            if (pPill)
                DllCall("gdiplus\GdipDeletePath", "Ptr", pPill)
            if (pGraphics)
                DllCall("gdiplus\GdipDeleteGraphics", "Ptr", pGraphics)
            if (hBrBg)
                DllCall("DeleteObject", "Ptr", hBrBg)
            if (hdcMem && obm)
                DllCall("SelectObject", "Ptr", hdcMem, "Ptr", obm)
            if (hbm)
                DllCall("DeleteObject", "Ptr", hbm)
            if (hdcMem)
                DllCall("DeleteDC", "Ptr", hdcMem)
            DllCall("EndPaint", "Ptr", hwnd, "Ptr", ps)
        }
    }

    res := DllCall("comctl32\DefSubclassProc", "Ptr", hwnd, "UInt", uMsg, "Ptr", wParam, "Ptr", lParam, "Ptr")
    if (uMsg == 0x0201 || uMsg == 0x0202 || uMsg == 0x130C || uMsg == 0x1330 || ((uMsg == 0x0100 || uMsg == 0x0101) && (wParam == 0x25 || wParam == 0x27 || wParam == 0x09))) {
        parentHwnd := DllCall("GetParent", "Ptr", hwnd, "Ptr")
        targetHwnd := parentHwnd ? parentHwnd : hwnd
        DllCall("RedrawWindow", "Ptr", targetHwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x0185)
        if (uMsg == 0x130C || uMsg == 0x1330)
            SetTimer(() => (WinExist("ahk_id " targetHwnd) ? DllCall("RedrawWindow", "Ptr", targetHwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x0185) : 0), -1)
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
        hBrBg := 0
        oldFont := 0
        try {
            if (!hdc)
                return 0
            rc := Buffer(16, 0)
            DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rc)
            ctrl := GuiCtrlFromHwnd(hwnd)
            parentDark := (IsObject(ctrl) && IsObject(ctrl.Gui) && ctrl.Gui.HasOwnProp("_isDark")) ? ctrl.Gui._isDark : Theme.IsDarkMode()
            role := (IsObject(ctrl) && ctrl.HasOwnProp("_themeRole")) ? ctrl._themeRole : ""
            inTab := (role = "tabText" || role = "tabMuted")
            bgBgr := parentDark ? (inTab ? UIConstants.DARK_SURFACE_BGR : UIConstants.DARK_BG_BGR) : (inTab ? UIConstants.LIGHT_SURFACE_BGR : UIConstants.LIGHT_BG_BGR)
            hBrBg := DllCall("CreateSolidBrush", "UInt", bgBgr, "Ptr")
            if (hBrBg)
                DllCall("FillRect", "Ptr", hdc, "Ptr", rc, "Ptr", hBrBg)
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
            return 0
        } finally {
            if (hdc && oldFont)
                DllCall("SelectObject", "Ptr", hdc, "Ptr", oldFont, "Ptr")
            if (hBrBg)
                DllCall("DeleteObject", "Ptr", hBrBg)
            DllCall("EndPaint", "Ptr", hwnd, "Ptr", ps)
        }
    }
    res := DllCall("comctl32\DefSubclassProc", "Ptr", hwnd, "UInt", uMsg, "Ptr", wParam, "Ptr", lParam, "Ptr")
    if (uMsg == 0x000A) ; WM_ENABLE
        DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", 1)
    return res
}

GenerateHostUuid() {
    b := Buffer(16, 0)
    ok := false
    try {
        if (DllCall("bcrypt\BCryptGenRandom", "Ptr", 0, "Ptr", b.Ptr, "UInt", 16, "UInt", 2, "Int") == 0)
            ok := true
    } catch {
        ok := false
    }
    if (!ok) {
        Loop 16
            NumPut("UChar", Random(0, 255), b, A_Index - 1)
    }
    NumPut("UChar", (NumGet(b, 6, "UChar") & 0x0F) | 0x40, b, 6)
    NumPut("UChar", (NumGet(b, 8, "UChar") & 0x3F) | 0x80, b, 8)
    hex := ""
    Loop 16
        hex .= Format("{:02x}", NumGet(b, A_Index - 1, "UChar"))
    return SubStr(hex, 1, 8) "-" SubStr(hex, 9, 4) "-" SubStr(hex, 13, 4) "-" SubStr(hex, 17, 4) "-" SubStr(hex, 21, 12)
}

#Include "%A_LineFile%\..\SessionTimeline.ahk"

class Config {
    ConfigFile := ""
    AudioRoutingMode := 0
    ObsMuteHotkey := "None"
    ObsTransitionHotkey := "None"
    ObsRecHotkey := "^F9"
    ObsPauseHotkey := "^F10"
    ZoomMuteHotkey := "!a"
    TeamsMuteHotkey := "^+m"
    MeetMuteHotkey := "^d"
    ConferencingApp := "Zoom"
    ZoomRecHotkey := "!r"
    ZoomPauseHotkey := "!p"
    UiaMuteKeywords := ""
    UiaUnmuteKeywords := ""
    obsPassword := ""
    targetMicName := "Mic/Aux"
    SecondaryAudioSources := ""

    EnablePPT := false
    EnableMicOnly := false
    EnablePointerTransition := false
    EnableWS := false
    EnableZoom := false

    ShowIndicator := true
    ShowPillMiniBadges := true
    ShowExtraHuds := true
    ShowRow2RecChatHud := true
    ShowRow3StudioSceneHud := true
    ShowSecondaryMicHud := false
    HudVisibilityMode := "Always"
    ThemeMode := "System"
    HudColorPreset := "Standard"
    CustomLiveHex := "107C10"
    CustomMutedHex := "C42B1C"
    StandbySceneName := "BRB"
    ExitBrbSafelyMuted := true
    BrbUnmuteCountdownSec := 0
    PanicSceneName := ""
    PanicStopVCam := true
    PanicPauseRecord := true
    BreakCountdownObsTextSource := ""
    CaptureDeviceId := ""
    RunOfShowMacros := ""
    ShowText := false
    MonoIcon := false
    SleekCorners := false
    AggressivePulse := false
    EnableAudioCue := false
    EnableMuteToast := false
    EnableVoiceWhileMutedAlert := true
    EnableCoreAudioFallback := true
    EnableOsMuteDriftWatchdog := true
    EnableForgottenRecordWatchdog := true
    AutoRecordOnStreamDrop := true
    ConfirmBeforeStopRecording := true
    ConfirmBeforeLiveCut := true
    AutoMuteOnLock := true
    AutoMuteOnMeetingEnd := false
    AutoMuteOnFirstObsConnect := false
    EnableLowDiskWatchdog := true
    EnableDeadMicWatchdog := true
    ShowVoiceMeter := true
    ShowRecTimer := true
    ShowStreamHud := true
    EnableHudClickActions := true
    EnableMagneticSnap := true
    HudClickThrough := false
    HudAutoDodge := false
    ExcludeFromCapture := true
    ExcludeSecondaryFromCapture := true
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
    EnablePushToTalk := false

    PptHotkey := "^F12"
    WsHotkey := "!F12"
    ZoomHotkey := "^!F12"
    IndHotkey := "^+F12"
    ExitHotkey := "!+F12"
    SuspendHotkey := "^!+F12"
    RemoteInfoHotkey := "None"
    EnableRemoteConnections := true
    IncludeVirtualAdapters := false
    HwMuteHotkey := "b"
    HwTransitionHotkey := "None"

    RemoteNetworkMode := "LAN"
    InternetPairingCode := ""
    RelayBaseUrl := "https://ntfy.sh"
    QuickNudgePresets := "2 min left|Wrap up|Check Mic|Q&A"
    EnableRelayEncryption := true
    AllowLegacyPlaintextRelay := false
    SessionPairingCode := ""
    HostUuid := ""
    BridgePort := 4456
    ActiveProfile := "Default"
    EnableAutoProfileSwitch := false
    AutoProfileRules := ""
    StartWithWindows := false
    AutoCheckUpdates := true
    LastUpdateCheckEpoch := 0
    SkippedUpdateVersion := ""

    savedX := "Default"
    savedY := "Default"
    savedSecondaryX := "Default"
    savedSecondaryY := "Default"
    _lastBackupTick := 0
    _deferredWrites := Map()
    _deferredWriteTimerFn := ""

    __New(filePath := "") {
        this.ConfigFile := (filePath != "") ? filePath : ConfigStore.ResolveDataDir(A_ScriptDir) "\MicOverlay_Config.ini"
        ConfigStore.EnsureParentDir(this.ConfigFile)
        this.Load()
    }

    IsValidConfigFile(filePath := "") {
        p := (filePath != "") ? filePath : this.ConfigFile
        return ConfigStore.IsValidIniFile(p, "Settings")
    }

    BackupToFile(force := true) {
        if (this.ConfigFile = "")
            return false
        now := A_TickCount
        if (!force && this._lastBackupTick != 0 && (now - this._lastBackupTick) < 5000)
            return false
        if (ConfigStore.BackupIniFile(this.ConfigFile, "Settings")) {
            this._lastBackupTick := now
            return true
        }
        return false
    }

    Read(section, key, defaultVal := "") {
        k := section "`n" key
        if (this._deferredWrites.Has(k))
            raw := String(this._deferredWrites[k].val)
        else
            raw := IniRead(this.ConfigFile, section, key, defaultVal)
        if (ConfigStore.IsSecretKey(section, key))
            return ConfigStore.UnprotectSecret(raw, section "." key)
        return raw
    }

    Write(section, key, val) {
        k := section "`n" key
        if (this._deferredWrites.Has(k))
            this._deferredWrites.Delete(k)
        ConfigStore.EnsureParentDir(this.ConfigFile)
        writeVal := ConfigStore.IsSecretKey(section, key) ? ConfigStore.ProtectSecret(val) : val
        IniWrite(writeVal, this.ConfigFile, section, key)
        this.BackupToFile(false)
    }

    ReadBool(section, key, defaultValue := 0) {
        k := section "`n" key
        value := this._deferredWrites.Has(k) ? this._deferredWrites[k].val : IniRead(this.ConfigFile, section, key, defaultValue)
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
        value := this.Read(section, key, defaultValue)
        try return Integer(value)
        catch
            return defaultValue
    }

    ReadFloat(section, key, defaultValue := 1.0) {
        value := this.Read(section, key, defaultValue)
        try return Float(value)
        catch
            return defaultValue
    }

    WriteBool(section, key, value) {
        k := section "`n" key
        if (this._deferredWrites.Has(k))
            this._deferredWrites.Delete(k)
        ConfigStore.EnsureParentDir(this.ConfigFile)
        IniWrite(value ? 1 : 0, this.ConfigFile, section, key)
        this.BackupToFile(false)
    }

    WriteBoolDeferred(section, key, value, delayMs := 250) {
        k := section "`n" key
        this._deferredWrites[k] := { sec: section, key: key, val: (value ? 1 : 0) }
        if (!IsObject(this._deferredWriteTimerFn))
            this._deferredWriteTimerFn := ObjBindMethod(this, "FlushDeferredWrites")
        SetTimer(this._deferredWriteTimerFn, -Max(1, Integer(delayMs)))
    }

    FlushDeferredWrites() {
        if (IsObject(this._deferredWriteTimerFn))
            try SetTimer(this._deferredWriteTimerFn, 0)
        if (this._deferredWrites.Count == 0)
            return 0
        pending := this._deferredWrites
        this._deferredWrites := Map()
        ConfigStore.EnsureParentDir(this.ConfigFile)
        written := 0
        for _, entry in pending {
            try {
                wVal := ConfigStore.IsSecretKey(entry.sec, entry.key) ? ConfigStore.ProtectSecret(entry.val) : entry.val
                IniWrite(wVal, this.ConfigFile, entry.sec, entry.key)
                written += 1
            }
        }
        if (written > 0)
            try this.BackupToFile(false)
        return written
    }

    Load() {
        ConfigStore.RecoverIniFromBackup(this.ConfigFile, "Settings")
        ConfigStore.MigrateIniSchema(this.ConfigFile, "Settings")
        this.AudioRoutingMode := this.ReadInt("Settings", "AudioRoutingMode", 0)
        if (this.AudioRoutingMode < 0 || this.AudioRoutingMode > 3)
            this.AudioRoutingMode := 0
        this.ObsMuteHotkey := this.Read("Settings", "ObsHotkey", "None")
        this.ObsTransitionHotkey := Trim(this.Read("Settings", "ObsTransitionHotkey", ""))
        if (this.ObsTransitionHotkey = "") {
            this.ObsTransitionHotkey := "None"
            this.Write("Settings", "ObsTransitionHotkey", this.ObsTransitionHotkey)
        }
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
        this.UiaMuteKeywords := Trim(this.Read("Settings", "UiaMuteKeywords", ""))
        this.UiaUnmuteKeywords := Trim(this.Read("Settings", "UiaUnmuteKeywords", ""))
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
        this.SecondaryAudioSources := Trim(this.Read("Settings", "SecondaryAudioSources", ""))
        rawBrb := Trim(this.Read("Settings", "StandbySceneName", "BRB"))
        this.StandbySceneName := (rawBrb != "") ? rawBrb : "BRB"

        this.EnablePPT := this.ReadBool("Settings", "EnablePPT")
        this.EnableMicOnly := this.ReadBool("Settings", "EnableMicOnly")
        rawPtrTrans := Trim(this.Read("Settings", "EnablePointerTransition", ""))
        if (rawPtrTrans = "") {
            this.EnablePointerTransition := false
            this.WriteBool("Settings", "EnablePointerTransition", false)
        } else {
            this.EnablePointerTransition := this.ReadBool("Settings", "EnablePointerTransition", false)
        }
        if (this.EnablePPT && this.EnableMicOnly) {
            this.EnableMicOnly := false
            this.WriteBool("Settings", "EnableMicOnly", false)
        }
        this.EnableWS := this.ReadBool("Settings", "EnableWS")
        this.EnableZoom := this.ReadBool("Settings", "EnableZoom")

        ; OBS WebSocket and Conferencing (Zoom/Teams) tracking may now run simultaneously.

        this.ShowIndicator := this.ReadBool("Settings", "ShowIndicator", true)
        this.ShowPillMiniBadges := this.ReadBool("Settings", "ShowPillMiniBadges", true)
        this.ShowExtraHuds := this.ReadBool("Settings", "ShowExtraHuds", true)
        this.ShowRow2RecChatHud := this.ReadBool("Settings", "ShowRow2RecChatHud", true)
        this.ShowRow3StudioSceneHud := this.ReadBool("Settings", "ShowRow3StudioSceneHud", true)
        this.ShowSecondaryMicHud := this.ReadBool("Settings", "ShowSecondaryMicHud", false)
        this.HudVisibilityMode := NormalizeHudVisibilityMode(this.Read("Settings", "HudVisibilityMode", "Always"))
        rawTheme := StrLower(Trim(this.Read("Settings", "ThemeMode", "System")))
        this.ThemeMode := (rawTheme = "dark") ? "Dark" : ((rawTheme = "light") ? "Light" : "System")
        Theme.SetMode(this.ThemeMode)
        this.HudColorPreset := NormalizeHudColorPreset(this.Read("Settings", "HudColorPreset", "Standard"))
        this.CustomLiveHex := NormalizeColorHex(this.Read("Settings", "CustomLiveHex", "107C10"), "107C10")
        this.CustomMutedHex := NormalizeColorHex(this.Read("Settings", "CustomMutedHex", "C42B1C"), "C42B1C")
        this.ShowText := this.ReadBool("Settings", "ShowText")
        this.MonoIcon := this.ReadBool("Settings", "MonoIcon")
        this.SleekCorners := this.ReadBool("Settings", "SleekCorners")
        this.AggressivePulse := this.ReadBool("Settings", "AggressivePulse")
        this.EnableAudioCue := this.ReadBool("Settings", "EnableAudioCue", false)
        this.EnableMuteToast := this.ReadBool("Settings", "EnableMuteToast", false)
        this.EnableVoiceWhileMutedAlert := this.ReadBool("Settings", "EnableVoiceWhileMutedAlert", true)
        this.EnableCoreAudioFallback := this.ReadBool("Settings", "EnableCoreAudioFallback", true)
        this.EnableOsMuteDriftWatchdog := this.ReadBool("Settings", "EnableOsMuteDriftWatchdog", true)
        this.EnableForgottenRecordWatchdog := this.ReadBool("Settings", "EnableForgottenRecordWatchdog", true)
        this.AutoRecordOnStreamDrop := this.ReadBool("Settings", "AutoRecordOnStreamDrop", true)
        this.ConfirmBeforeStopRecording := this.ReadBool("Settings", "ConfirmBeforeStopRecording", true)
        this.ExitBrbSafelyMuted := this.ReadBool("Settings", "ExitBrbSafelyMuted", true)
        this.BrbUnmuteCountdownSec := Max(0, Min(15, this.ReadInt("Settings", "BrbUnmuteCountdownSec", 0)))
        this.PanicSceneName := Trim(this.Read("Settings", "PanicSceneName", ""))
        this.PanicStopVCam := this.ReadBool("Settings", "PanicStopVCam", true)
        this.PanicPauseRecord := this.ReadBool("Settings", "PanicPauseRecord", true)
        this.BreakCountdownObsTextSource := Trim(this.Read("Settings", "BreakCountdownObsTextSource", ""))
        this.CaptureDeviceId := Trim(this.Read("Settings", "CaptureDeviceId", ""))
        this.RunOfShowMacros := Trim(this.Read("Settings", "RunOfShowMacros", ""))
        this.AutoMuteOnLock := this.ReadBool("Settings", "AutoMuteOnLock", true)
        this.AutoMuteOnMeetingEnd := this.ReadBool("Settings", "AutoMuteOnMeetingEnd", false)
        this.AutoMuteOnFirstObsConnect := this.ReadBool("Settings", "AutoMuteOnFirstObsConnect", false)
        this.EnableLowDiskWatchdog := this.ReadBool("Settings", "EnableLowDiskWatchdog", true)
        this.EnableDeadMicWatchdog := this.ReadBool("Settings", "EnableDeadMicWatchdog", true)
        this.ShowVoiceMeter := this.ReadBool("Settings", "ShowVoiceMeter", true)
        this.ShowRecTimer := this.ReadBool("Settings", "ShowRecTimer", true)
        this.ShowStreamHud := this.ReadBool("Settings", "ShowStreamHud", true)
        this.EnableHudClickActions := this.ReadBool("Settings", "EnableHudClickActions", true)
        this.EnableMagneticSnap := this.ReadBool("Settings", "EnableMagneticSnap", true)
        this.HudClickThrough := this.ReadBool("Settings", "HudClickThrough", false)
        this.HudAutoDodge := this.ReadBool("Settings", "HudAutoDodge", false)
        this.ExcludeFromCapture := this.ReadBool("Settings", "ExcludeFromCapture", true)
        this.ExcludeSecondaryFromCapture := this.ReadBool("Settings", "ExcludeSecondaryFromCapture", true)
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
        this.EnablePushToTalk := this.ReadBool("Pointer", "EnablePushToTalk", false)
        if (this.EnablePushToTalk && this.EnablePushToMute) {
            this.EnablePushToMute := false
            this.WriteBool("Pointer", "EnablePushToMute", false)
        }

        this.PptHotkey := this.Read("Settings", "PptHotkey", "^F12")
        this.WsHotkey := this.Read("Settings", "WsHotkey", "!F12")
        this.ZoomHotkey := this.Read("Settings", "ZoomHotkey", "^!F12")
        this.IndHotkey := this.Read("Settings", "IndHotkey", "^+F12")
        this.ExitHotkey := this.Read("Settings", "ExitHotkey", "!+F12")
        this.RemoteInfoHotkey := this.Read("Settings", "RemoteInfoHotkey", "None")
        this.EnableRemoteConnections := this.ReadBool("Settings", "EnableRemoteConnections", true)
        this.IncludeVirtualAdapters := this.ReadBool("Settings", "IncludeVirtualAdapters", false)
        this.SuspendHotkey := this.Read("Settings", "SuspendHotkey", "^!+F12")
        this.HwMuteHotkey := this.Read("Settings", "HwMuteHotkey", "b")
        this.HwTransitionHotkey := Trim(this.Read("Settings", "HwTransitionHotkey", ""))
        if (this.HwTransitionHotkey = "") {
            this.HwTransitionHotkey := "None"
            this.Write("Settings", "HwTransitionHotkey", this.HwTransitionHotkey)
        }

        rawNetMode := StrLower(Trim(this.Read("Settings", "RemoteNetworkMode", "LAN")))
        this.RemoteNetworkMode := (rawNetMode = "internet") ? "Internet" : "LAN"
        rawRelayUrl := Trim(this.Read("Settings", "RelayBaseUrl", "https://ntfy.sh"))
        this.QuickNudgePresets := this.Read("Settings", "QuickNudgePresets", "2 min left|Wrap up|Check Mic|Q&A")
        this.RelayBaseUrl := IsSet(NormalizeRelayBaseUrl) ? NormalizeRelayBaseUrl(rawRelayUrl) : (rawRelayUrl != "" ? RTrim(rawRelayUrl, "/") : "https://ntfy.sh")
        this.EnableRelayEncryption := this.ReadBool("Settings", "EnableRelayEncryption", true)
        this.AllowLegacyPlaintextRelay := this.ReadBool("Settings", "AllowLegacyPlaintextRelay", false)
        this.InternetPairingCode := Trim(this.Read("Settings", "InternetPairingCode", ""))
        if (this.InternetPairingCode = "") {
            this.InternetPairingCode := GenerateInternetPairingCode()
            this.Write("Settings", "InternetPairingCode", this.InternetPairingCode)
        }
        this.BridgePort := this.ReadInt("Settings", "BridgePort", 4456)
        if (this.BridgePort < 1 || this.BridgePort > 65535)
            this.BridgePort := 4456
        this.SessionPairingCode := Trim(this.Read("Settings", "SessionPairingCode", ""))
        if (this.SessionPairingCode = "") {
            this.SessionPairingCode := GenerateSessionPairingCode()
            this.Write("Settings", "SessionPairingCode", this.SessionPairingCode)
        }
        this.HostUuid := Trim(this.Read("Settings", "HostUuid", ""))
        if (this.HostUuid = "") {
            this.HostUuid := GenerateHostUuid()
            this.Write("Settings", "HostUuid", this.HostUuid)
        }
        profName := this.NormalizeProfileName(this.Read("Settings", "ActiveProfile", "Default"))
        this.ActiveProfile := (profName != "") ? profName : "Default"
        this.EnableAutoProfileSwitch := this.ReadBool("Settings", "EnableAutoProfileSwitch", false)
        this.AutoProfileRules := Trim(this.Read("Settings", "AutoProfileRules", ""))
        this.StartWithWindows := this.ReadBool("Settings", "StartWithWindows", false)
        this.AutoCheckUpdates := this.ReadBool("Settings", "AutoCheckUpdates", true)
        lastUpd := Trim(this.Read("Settings", "LastUpdateCheckEpoch", "0"))
        this.LastUpdateCheckEpoch := IsInteger(lastUpd) ? Integer(lastUpd) : 0
        this.SkippedUpdateVersion := Trim(this.Read("Settings", "SkippedUpdateVersion", ""))

        this.savedX := this.Read("Position", "X", "Default")
        this.savedY := this.Read("Position", "Y", "Default")
        this.savedSecondaryX := this.Read("SecondaryPosition", "X", "Default")
        this.savedSecondaryY := this.Read("SecondaryPosition", "Y", "Default")
        if (FileExist(this.ConfigFile)) {
            if (Trim(IniRead(this.ConfigFile, "ConfigMeta", "SchemaVersion", "")) = "")
                try IniWrite(ConfigStore.CURRENT_SCHEMA_VERSION, this.ConfigFile, "ConfigMeta", "SchemaVersion")
        }
        this.BackupToFile(true)
    }

    ResetAppearance() {
        this.ShowExtraHuds := true
        this.ShowRow2RecChatHud := true
        this.ShowRow3StudioSceneHud := true
        this.ThemeMode := "System"
        this.HudColorPreset := "Standard"
        this.CustomLiveHex := "107C10"
        this.CustomMutedHex := "C42B1C"
        this.ShowText := false
        this.MonoIcon := false
        this.SleekCorners := false
        this.AggressivePulse := false
        this.EnableAudioCue := false
        this.EnableMuteToast := false
        this.EnableVoiceWhileMutedAlert := true
        this.ShowVoiceMeter := true
        this.ShowRecTimer := true
        this.ShowStreamHud := true
        this.EnableHudClickActions := true
        this.EnableMagneticSnap := true
        this.HudClickThrough := false
        this.HudAutoDodge := false
        this.ExcludeFromCapture := true
        this.ExcludeSecondaryFromCapture := true
        this.OpacityLevel := UIConstants.OPACITY_FROSTED
        this.IndicatorScale := 1.0
        this.Write("Settings", "ShowExtraHuds", 1)
        this.Write("Settings", "ShowRow2RecChatHud", 1)
        this.Write("Settings", "ShowRow3StudioSceneHud", 1)
        this.Write("Settings", "ThemeMode", "System")
        this.Write("Settings", "HudColorPreset", "Standard")
        this.Write("Settings", "CustomLiveHex", "107C10")
        this.Write("Settings", "CustomMutedHex", "C42B1C")
        this.Write("Settings", "ShowText", 0)
        this.Write("Settings", "MonoIcon", 0)
        this.Write("Settings", "SleekCorners", 0)
        this.Write("Settings", "AggressivePulse", 0)
        this.Write("Settings", "EnableAudioCue", 0)
        this.Write("Settings", "EnableMuteToast", 0)
        this.Write("Settings", "EnableVoiceWhileMutedAlert", 1)
        this.Write("Settings", "ShowVoiceMeter", 1)
        this.Write("Settings", "ShowRecTimer", 1)
        this.Write("Settings", "ShowStreamHud", 1)
        this.Write("Settings", "EnableHudClickActions", 1)
        this.Write("Settings", "EnableMagneticSnap", 1)
        this.Write("Settings", "HudClickThrough", 0)
        this.Write("Settings", "HudAutoDodge", 0)
        this.Write("Settings", "ExcludeFromCapture", 1)
        this.Write("Settings", "ExcludeSecondaryFromCapture", 1)
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

    ResetSecondaryPosition() {
        this.savedSecondaryX := "Default"
        this.savedSecondaryY := "Default"
        this.Write("SecondaryPosition", "X", "Default")
        this.Write("SecondaryPosition", "Y", "Default")
    }

    DeleteFile() {
        if FileExist(this.ConfigFile)
            try FileDelete(this.ConfigFile)
        if FileExist(this.ConfigFile ".bak")
            try FileDelete(this.ConfigFile ".bak")
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
            { sec: "Settings", key: "ObsTransitionHotkey", prop: "ObsTransitionHotkey", kind: "str" },
            { sec: "Settings", key: "ObsRecHotkey", prop: "ObsRecHotkey", kind: "str" },
            { sec: "Settings", key: "ObsPauseHotkey", prop: "ObsPauseHotkey", kind: "str" },
            { sec: "Settings", key: "ZoomMuteHotkey", prop: "ZoomMuteHotkey", kind: "str" },
            { sec: "Settings", key: "TeamsMuteHotkey", prop: "TeamsMuteHotkey", kind: "str" },
            { sec: "Settings", key: "MeetMuteHotkey", prop: "MeetMuteHotkey", kind: "str" },
            { sec: "Settings", key: "ConferencingApp", prop: "ConferencingApp", kind: "str" },
            { sec: "Settings", key: "UiaMuteKeywords", prop: "UiaMuteKeywords", kind: "str" },
            { sec: "Settings", key: "UiaUnmuteKeywords", prop: "UiaUnmuteKeywords", kind: "str" },
            { sec: "Settings", key: "ZoomRecHotkey", prop: "ZoomRecHotkey", kind: "str" },
            { sec: "Settings", key: "ZoomPauseHotkey", prop: "ZoomPauseHotkey", kind: "str" },
            { sec: "Settings", key: "TargetMicName", prop: "targetMicName", kind: "str" },
            { sec: "Settings", key: "SecondaryAudioSources", prop: "SecondaryAudioSources", kind: "str" },
            { sec: "Settings", key: "EnablePPT", prop: "EnablePPT", kind: "bool" },
            { sec: "Settings", key: "EnableMicOnly", prop: "EnableMicOnly", kind: "bool" },
            { sec: "Settings", key: "EnablePointerTransition", prop: "EnablePointerTransition", kind: "bool" },
            { sec: "Settings", key: "EnableWS", prop: "EnableWS", kind: "bool" },
            { sec: "Settings", key: "EnableZoom", prop: "EnableZoom", kind: "bool" },
            { sec: "Settings", key: "ShowIndicator", prop: "ShowIndicator", kind: "bool" },
            { sec: "Settings", key: "ShowPillMiniBadges", prop: "ShowPillMiniBadges", kind: "bool" },
            { sec: "Settings", key: "ShowExtraHuds", prop: "ShowExtraHuds", kind: "bool" },
            { sec: "Settings", key: "ShowRow2RecChatHud", prop: "ShowRow2RecChatHud", kind: "bool" },
            { sec: "Settings", key: "ShowRow3StudioSceneHud", prop: "ShowRow3StudioSceneHud", kind: "bool" },
            { sec: "Settings", key: "ShowSecondaryMicHud", prop: "ShowSecondaryMicHud", kind: "bool" },
            { sec: "Settings", key: "ThemeMode", prop: "ThemeMode", kind: "str" },
            { sec: "Settings", key: "HudColorPreset", prop: "HudColorPreset", kind: "str" },
            { sec: "Settings", key: "CustomLiveHex", prop: "CustomLiveHex", kind: "str" },
            { sec: "Settings", key: "CustomMutedHex", prop: "CustomMutedHex", kind: "str" },
            { sec: "Settings", key: "StandbySceneName", prop: "StandbySceneName", kind: "str" },
            { sec: "Settings", key: "ExitBrbSafelyMuted", prop: "ExitBrbSafelyMuted", kind: "bool" },
            { sec: "Settings", key: "BrbUnmuteCountdownSec", prop: "BrbUnmuteCountdownSec", kind: "int" },
            { sec: "Settings", key: "PanicSceneName", prop: "PanicSceneName", kind: "str" },
            { sec: "Settings", key: "PanicStopVCam", prop: "PanicStopVCam", kind: "bool" },
            { sec: "Settings", key: "PanicPauseRecord", prop: "PanicPauseRecord", kind: "bool" },
            { sec: "Settings", key: "BreakCountdownObsTextSource", prop: "BreakCountdownObsTextSource", kind: "str" },
            { sec: "Settings", key: "CaptureDeviceId", prop: "CaptureDeviceId", kind: "str" },
            { sec: "Settings", key: "RunOfShowMacros", prop: "RunOfShowMacros", kind: "str" },
            { sec: "Settings", key: "ShowText", prop: "ShowText", kind: "bool" },
            { sec: "Settings", key: "MonoIcon", prop: "MonoIcon", kind: "bool" },
            { sec: "Settings", key: "SleekCorners", prop: "SleekCorners", kind: "bool" },
            { sec: "Settings", key: "AggressivePulse", prop: "AggressivePulse", kind: "bool" },
            { sec: "Settings", key: "EnableAudioCue", prop: "EnableAudioCue", kind: "bool" },
            { sec: "Settings", key: "EnableMuteToast", prop: "EnableMuteToast", kind: "bool" },
            { sec: "Settings", key: "EnableVoiceWhileMutedAlert", prop: "EnableVoiceWhileMutedAlert", kind: "bool" },
            { sec: "Settings", key: "EnableCoreAudioFallback", prop: "EnableCoreAudioFallback", kind: "bool" },
            { sec: "Settings", key: "EnableOsMuteDriftWatchdog", prop: "EnableOsMuteDriftWatchdog", kind: "bool" },
            { sec: "Settings", key: "EnableForgottenRecordWatchdog", prop: "EnableForgottenRecordWatchdog", kind: "bool" },
            { sec: "Settings", key: "AutoRecordOnStreamDrop", prop: "AutoRecordOnStreamDrop", kind: "bool" },
            { sec: "Settings", key: "ConfirmBeforeStopRecording", prop: "ConfirmBeforeStopRecording", kind: "bool" },
            { sec: "Settings", key: "AutoMuteOnLock", prop: "AutoMuteOnLock", kind: "bool" },
            { sec: "Settings", key: "AutoMuteOnMeetingEnd", prop: "AutoMuteOnMeetingEnd", kind: "bool" },
            { sec: "Settings", key: "AutoMuteOnFirstObsConnect", prop: "AutoMuteOnFirstObsConnect", kind: "bool" },
            { sec: "Settings", key: "EnableLowDiskWatchdog", prop: "EnableLowDiskWatchdog", kind: "bool" },
            { sec: "Settings", key: "EnableDeadMicWatchdog", prop: "EnableDeadMicWatchdog", kind: "bool" },
            { sec: "Settings", key: "ShowVoiceMeter", prop: "ShowVoiceMeter", kind: "bool" },
            { sec: "Settings", key: "ShowRecTimer", prop: "ShowRecTimer", kind: "bool" },
            { sec: "Settings", key: "ShowStreamHud", prop: "ShowStreamHud", kind: "bool" },
            { sec: "Settings", key: "EnableHudClickActions", prop: "EnableHudClickActions", kind: "bool" },
            { sec: "Settings", key: "EnableMagneticSnap", prop: "EnableMagneticSnap", kind: "bool" },
            { sec: "Settings", key: "HudClickThrough", prop: "HudClickThrough", kind: "bool" },
            { sec: "Settings", key: "HudAutoDodge", prop: "HudAutoDodge", kind: "bool" },
            { sec: "Settings", key: "ExcludeFromCapture", prop: "ExcludeFromCapture", kind: "bool" },
            { sec: "Settings", key: "ExcludeSecondaryFromCapture", prop: "ExcludeSecondaryFromCapture", kind: "bool" },
            { sec: "Settings", key: "OpacityLevel", prop: "OpacityLevel", kind: "int" },
            { sec: "Settings", key: "IndicatorScale", prop: "IndicatorScale", kind: "float" },
            { sec: "Settings", key: "RemoteNetworkMode", prop: "RemoteNetworkMode", kind: "str" },
            { sec: "Settings", key: "RelayBaseUrl", prop: "RelayBaseUrl", kind: "str" },
            { sec: "Settings", key: "QuickNudgePresets", prop: "QuickNudgePresets", kind: "str" },
            { sec: "Settings", key: "EnableRelayEncryption", prop: "EnableRelayEncryption", kind: "bool" },
            { sec: "Settings", key: "AllowLegacyPlaintextRelay", prop: "AllowLegacyPlaintextRelay", kind: "bool" },
            { sec: "Settings", key: "EnableRemoteConnections", prop: "EnableRemoteConnections", kind: "bool" },
            { sec: "Settings", key: "IncludeVirtualAdapters", prop: "IncludeVirtualAdapters", kind: "bool" },
            { sec: "Settings", key: "RemoteInfoHotkey", prop: "RemoteInfoHotkey", kind: "str" },
            { sec: "Settings", key: "HwMuteHotkey", prop: "HwMuteHotkey", kind: "str" },
            { sec: "Settings", key: "HwTransitionHotkey", prop: "HwTransitionHotkey", kind: "str" },
            { sec: "Pointer", key: "CatchArrows", prop: "CatchArrows", kind: "bool" },
            { sec: "Pointer", key: "CatchPg", prop: "CatchPg", kind: "bool" },
            { sec: "Pointer", key: "CatchSpace", prop: "CatchSpace", kind: "bool" },
            { sec: "Pointer", key: "CatchEnter", prop: "CatchEnter", kind: "bool" },
            { sec: "Pointer", key: "CatchTab", prop: "CatchTab", kind: "bool" },
            { sec: "Pointer", key: "CatchEsc", prop: "CatchEsc", kind: "bool" },
            { sec: "Pointer", key: "EnablePushToMute", prop: "EnablePushToMute", kind: "bool" },
            { sec: "Pointer", key: "EnablePushToTalk", prop: "EnablePushToTalk", kind: "bool" },
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

ParseQuickNudgePresets(rawStr, maxCount := 6) {
    out := []
    seen := Map()
    for _, part in StrSplit(String(rawStr), ["|", ","]) {
        clean := Trim(part)
        if (clean != "" && !seen.Has(clean)) {
            seen[clean] := true
            out.Push(clean)
            if (out.Length >= maxCount)
                break
        }
    }
    if (out.Length == 0)
        return ["2 min left", "Wrap up", "Check Mic", "Q&A"]
    return out
}

class OverlayState {
    obsWs := ""
    obsConnected := false
    relayWs := ""
    relayConnected := false
    _activeRelayWsUrl := ""
    relayReplayGuard := ""
    _relayOutSeq := 0
    _relaySessionId := ""
    _relayPeerLegacy := false
    zoomConnected := false
    meetBgTabWarn := false
    detectedConfApp := ""
    slideIndex := 0
    slideTotal := 0
    slideTitle := ""
    slideNotes := ""
    hasEverConnectedObsThisRun := false
    wasInConfMeeting := false
    ipcMsgGui := ""
    IsSyncing := false
    syncSource := ""
    zoomLastMuted := -1
    zoomRecGraceUntil := 0
    zoomSawRecControl := false

    isMuted := false
    recState := 0
    recElapsedSec := 0
    obsRecState := 0
    obsRecElapsedSec := 0
    obsRecAnchorMs := 0
    obsRecAnchorTick := 0
    confRecState := 0
    confRecElapsedSec := 0
    recSourceTag := ""
    stopRecConfirmUntil := 0
    studioModeActive := false
    currentSceneName := "Scene"
    previewSceneName := ""
    previousProgramScene := ""
    sceneList := []
    obsInputs := []
    obsAudioInputs := []
    refreshInputsFn := ""
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
    sceneMarqueeSpan := 0
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
    mutedVoiceTimerFn := ""
    recTimerFn := ""
    presenterTimerFn := ""
    isStandby := false
    standbySnapshot := ""
    timerState := "stopped"
    timerPresetSec := 600
    timerRemainingSec := 600
    voiceWhileMuted := false
    mutedVoiceAboveSince := 0
    mutedVoiceQuietSince := 0
    osMicMutedDrift := false
    lastOsDriftWarnTick := 0
    coreAudioWatchdogFn := ""
    recordDirectory := ""
    lowDiskMb := -1
    lowDiskWarnLevel := 0
    streamDropWarn := false
    deadMicWarn := false
    activeBridgePort := 0
    safetyWatchdogFn := ""
    _forgotRecSinceTick := 0
    _lastForgotRecWarnTick := 0
    _streamDropSinceTick := 0
    _streamDropBackupTriggered := false
    _lastLowDiskPollTick := 0
    _lastLowDiskWarnTick := 0
    _deadMicSinceTick := 0
    _lastDeadMicWarnTick := 0
    pptNextFn := ""
    pptPrevFn := ""
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
    triggerTransitionFn := ""
    autoProfileTimerFn := ""
    _autoProfileBase := ""
    _autoProfileMatched := ""
    _autoProfileRuleProc := ""

    MicGui := ""
    SecondaryMicGui := ""
    RecGui := ""
    ChatGui := ""
    StudioGui := ""
    SceneGui := ""
    StreamGui := ""
    VCamGui := ""

    isDraggingSecondaryHud := false
    secondaryIsAutoDodged := false
    secondaryCurrentAlpha := 220
    _breathStepAlpha := 220

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
    savedSecondaryX := 0
    savedSecondaryY := 0

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
        this.hudCfg := cfg
        this.isMuted := cfg.IsMuted
        this.baseAlpha := cfg.OpacityLevel
        this.currentAlpha := cfg.OpacityLevel
        this.secondaryCurrentAlpha := cfg.OpacityLevel
        this._breathStepAlpha := cfg.OpacityLevel
        this.micHoldProgress := 0.0
        this.secondaryMicHoldProgress := 0.0
        this.recHoldProgress := 0.0
        this.studioHoldProgress := 0.0
        this.sceneMarqueeLastTick := 0
        this.breathDir := cfg.AggressivePulse ? -UIConstants.PULSE_STEP_AGGRESSIVE : -UIConstants.PULSE_STEP_NORMAL

        osBuild := Integer(StrSplit(A_OSVersion, ".")[3])
        this.IconFont := (osBuild >= 22000) ? "Segoe Fluent Icons" : "Segoe MDL2 Assets"

        this.dragTimerFn := DragSyncTick.Bind(this)
        this.breathTimerFn := BreathingAnimation.Bind(cfg, this)
        this.voiceMeterTimerFn := VoiceMeterTick.Bind(cfg, this)
        this.mutedVoiceTimerFn := MutedVoiceMonitorTick.Bind(cfg, this)
        this.coreAudioWatchdogFn := CoreAudioWatchdogTick.Bind(cfg, this)
        this.safetyWatchdogFn := SafetyWatchdogTick.Bind(cfg, this)
        this.recTimerFn := RecTimerTick.Bind(cfg, this)
        this.presenterTimerFn := PresenterTimerTick.Bind(cfg, this)
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

    StopAllTimers() {
        static timerProps := [
            "dragTimerFn", "breathTimerFn", "_muteAnimTimerFn", "voiceMeterTimerFn", "mutedVoiceTimerFn",
            "coreAudioWatchdogFn", "safetyWatchdogFn", "recTimerFn", "presenterTimerFn",
            "streamTimerFn", "autoDodgeTimerFn", "obsTimerFn", "relayTimerFn",
            "sceneMarqueeTimerFn", "zoomTimerFn", "releaseSyncTimerFn", "autoProfileTimerFn"
        ]
        stopped := 0
        for _, prop in timerProps {
            if (this.HasOwnProp(prop) && IsObject(this.%prop%)) {
                try SetTimer(this.%prop%, 0)
                stopped += 1
            }
        }
        return stopped
    }

    ComputeDimensions(cfg) {
        cLive := (IsObject(cfg) && cfg.HasOwnProp("CustomLiveHex")) ? cfg.CustomLiveHex : "107C10"
        cMuted := (IsObject(cfg) && cfg.HasOwnProp("CustomMutedHex")) ? cfg.CustomMutedHex : "C42B1C"
        this.colors := UIConstants.GetColorPalette(cfg.HasOwnProp("HudColorPreset") ? cfg.HudColorPreset : "Standard", cLive, cMuted)
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
            rSampleTxt := GetRecLabelPrefix(cfg, this) ((this.recState == 2) ? "PAUSED " : "REC ") FormatElapsedShort(this.recElapsedSec)
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
        if (IsSet(GetHudTierFlags)) {
            tierFlags := GetHudTierFlags(cfg)
            extraRow2 := tierFlags.row2, extraRow3 := tierFlags.row3, extraRow4 := tierFlags.row4
        }
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
        ComputeSecondaryMicLayout(cfg, this)
    }
}

SetTrayCheck(itemText, enabled) {
    if (enabled)
        A_TrayMenu.Check(itemText)
    else
        A_TrayMenu.Uncheck(itemText)
}

_BundleJsonUnescape(s) {
    return IsSet(UnescapeJsonStr) ? UnescapeJsonStr(s) : s
}

_IsBundleSecretProp(prop) {
    pLow := StrLower(String(prop))
    return (pLow = "obspassword" || pLow = "bridgetoken" || pLow = "sessionpairingcode" || pLow = "internetpairingcode")
}

ExportPortableSettingsBundle(cfg, targetPath, includeSecrets := false) {
    if (!IsObject(cfg) || targetPath = "")
        return { ok: false, path: targetPath, count: 0, error: "Invalid config or target path." }
    specs := cfg.GetProfileFieldSpecs()
    isIni := (StrLower(SubStr(targetPath, -4)) = ".ini")
    count := 0
    try {
        try FileDelete(targetPath)
        if (isIni) {
            IniWrite("PresenterSyncBundle_v1", targetPath, "Bundle", "Schema")
            IniWrite(UIConstants.APP_VERSION, targetPath, "Bundle", "AppVersion")
            for spec in specs {
                if (!includeSecrets && _IsBundleSecretProp(spec.prop))
                    continue
                if (!cfg.HasOwnProp(spec.prop))
                    continue
                val := cfg.%spec.prop%
                if (spec.kind = "bool")
                    val := val ? 1 : 0
                IniWrite(String(val), targetPath, spec.sec, spec.key)
                count += 1
            }
        } else {
            utc := FormatTime(A_NowUTC, "yyyy-MM-ddTHH:mm:ssZ")
            settingsJson := ""
            for spec in specs {
                if (!includeSecrets && _IsBundleSecretProp(spec.prop))
                    continue
                if (!cfg.HasOwnProp(spec.prop))
                    continue
                rawVal := cfg.%spec.prop%
                if (spec.kind = "bool")
                    valToken := rawVal ? "true" : "false"
                else if (spec.kind = "int")
                    valToken := String(IsInteger(rawVal) ? Integer(rawVal) : 0)
                else if (spec.kind = "float")
                    valToken := String(IsNumber(rawVal) ? Number(rawVal) : 0.0)
                else
                    valToken := '"' EscapeJsonStr(String(rawVal)) '"'
                settingsJson .= (count > 0 ? "," : "") . '`r`n    "' EscapeJsonStr(spec.prop) '": ' valToken
                count += 1
            }
            payload := '{"schema": "PresenterSyncBundle_v1", "appVersion": "' EscapeJsonStr(UIConstants.APP_VERSION) '", "exportedUtc": "' utc '", "settings": {' settingsJson '`r`n  }`r`n}'
            FileAppend(payload, targetPath, "UTF-8")
        }
        return { ok: true, path: targetPath, count: count, error: "" }
    } catch as err {
        return { ok: false, path: targetPath, count: 0, error: err.Message }
    }
}

ImportPortableSettingsBundle(cfg, state, sourcePath) {
    if (!IsObject(cfg) || sourcePath = "" || !FileExist(sourcePath))
        return { ok: false, appliedCount: 0, error: "Bundle file not found." }
    specs := cfg.GetProfileFieldSpecs()
    applied := 0
    try {
        raw := FileRead(sourcePath, "UTF-8")
        isIni := (StrLower(SubStr(sourcePath, -4)) = ".ini") || RegExMatch(LTrim(raw), "^\[")
        if (isIni) {
            for spec in specs {
                if (_IsBundleSecretProp(spec.prop))
                    continue
                v := IniRead(sourcePath, spec.sec, spec.key, "__MISSING__")
                if (v = "__MISSING__")
                    continue
                if (spec.kind = "bool") {
                    b := (StrLower(Trim(v)) = "1" || StrLower(Trim(v)) = "true" || StrLower(Trim(v)) = "yes")
                    cfg.%spec.prop% := b
                    cfg.WriteBool(spec.sec, spec.key, b)
                } else if (spec.kind = "int") {
                    if (!IsInteger(v))
                        continue
                    iv := Integer(v)
                    cfg.%spec.prop% := iv
                    cfg.Write(spec.sec, spec.key, iv)
                } else if (spec.kind = "float") {
                    if (!IsNumber(v))
                        continue
                    fv := Number(v)
                    cfg.%spec.prop% := fv
                    cfg.Write(spec.sec, spec.key, fv)
                } else {
                    cfg.%spec.prop% := v
                    cfg.Write(spec.sec, spec.key, v)
                }
                applied += 1
            }
        } else {
            if (!InStr(raw, "PresenterSyncBundle_v1") || !InStr(raw, '"settings"'))
                return { ok: false, appliedCount: 0, error: "Invalid bundle schema." }
            for spec in specs {
                if (_IsBundleSecretProp(spec.prop))
                    continue
                patKey := '"' spec.prop '"\s*:\s*'
                if (spec.kind = "bool") {
                    if (RegExMatch(raw, patKey '(true|false|1|0)', &m)) {
                        b := (m[1] = "true" || m[1] = "1")
                        cfg.%spec.prop% := b
                        cfg.WriteBool(spec.sec, spec.key, b)
                        applied += 1
                    }
                } else if (spec.kind = "int") {
                    if (RegExMatch(raw, patKey '(-?\d+)', &m)) {
                        iv := Integer(m[1])
                        cfg.%spec.prop% := iv
                        cfg.Write(spec.sec, spec.key, iv)
                        applied += 1
                    }
                } else if (spec.kind = "float") {
                    if (RegExMatch(raw, patKey '(-?\d+(?:\.\d+)?)', &m)) {
                        fv := Number(m[1])
                        cfg.%spec.prop% := fv
                        cfg.Write(spec.sec, spec.key, fv)
                        applied += 1
                    }
                } else {
                    if (RegExMatch(raw, patKey '"((?:[^"\\]|\\.)*)"', &m)) {
                        sv := _BundleJsonUnescape(m[1])
                        cfg.%spec.prop% := sv
                        cfg.Write(spec.sec, spec.key, sv)
                        applied += 1
                    }
                }
            }
        }
        try cfg.BackupToFile(true)
        if (IsObject(state)) {
            if (state.HasOwnProp("rebindHotkeysFn") && state.rebindHotkeysFn)
                try state.rebindHotkeysFn.Call()
            if (state.HasOwnProp("rebuildTrayFn") && state.rebuildTrayFn)
                try state.rebuildTrayFn.Call()
        }
        return { ok: true, appliedCount: applied, error: "" }
    } catch as err {
        return { ok: false, appliedCount: 0, error: err.Message }
    }
}
#Include "%A_LineFile%\..\CaptureSafety.ahk"
#Include "%A_LineFile%\..\HudRenderer.ahk"
#Include "%A_LineFile%\..\SetupWizard.ahk"
#Include "%A_LineFile%\..\ControlCenter.ahk"
#Include "%A_LineFile%\..\SelfUpdater.ahk"

