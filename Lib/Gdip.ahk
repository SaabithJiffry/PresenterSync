; ==============================================================================
; Module: Gdip.ahk
; Description: GDI+ Layered Window rendering engine for AutoHotkey v2
; ==============================================================================

class Gdip {
    static _token := 0
    static _hModule := 0
    static _fontFamilies := Map()
    static _fonts := Map()
    static _stringFormats := Map()
    static _surfaces := Map()
    static _bi := Buffer(40, 0)
    static _ptWin := Buffer(8, 0)
    static _szWin := Buffer(8, 0)
    static _ptSrc := Buffer(8, 0)
    static _blend := Buffer(4, 0)
    static _layoutRect := Buffer(16, 0)
    static _boundRect := Buffer(16, 0)
    static _rectF := Buffer(16, 0)

    static ReleaseSurface(hwnd) {
        k := Integer(hwnd)
        if (!this._surfaces.Has(k))
            return false
        surf := this._surfaces[k]
        this._surfaces.Delete(k)
        if (surf.pGraphics)
            try DllCall("gdiplus\GdipDeleteGraphics", "Ptr", surf.pGraphics)
        if (surf.hdcMem && surf.obm)
            try DllCall("SelectObject", "Ptr", surf.hdcMem, "Ptr", surf.obm)
        if (surf.hbm)
            try DllCall("DeleteObject", "Ptr", surf.hbm)
        if (surf.hdcMem)
            try DllCall("DeleteDC", "Ptr", surf.hdcMem)
        return true
    }

    static Startup() {
        if (this._token)
            return true
        this._hModule := DllCall("LoadLibrary", "Str", "gdiplus", "Ptr")
        if (!this._hModule)
            return false
        si := Buffer(A_PtrSize == 8 ? 24 : 16, 0)
        NumPut("UInt", 1, si, 0)
        token := 0
        status := DllCall("gdiplus\GdiplusStartup", "Ptr*", &token, "Ptr", si, "Ptr", 0, "Int")
        if (status != 0) {
            DllCall("FreeLibrary", "Ptr", this._hModule)
            this._hModule := 0
            return false
        }
        this._token := token
        return true
    }

    static Shutdown() {
        surfKeys := []
        for hwndKey in this._surfaces
            surfKeys.Push(hwndKey)
        for _, hwndKey in surfKeys
            this.ReleaseSurface(hwndKey)

        for _, pFmt in this._stringFormats {
            if (pFmt)
                try DllCall("gdiplus\GdipDeleteStringFormat", "Ptr", pFmt)
        }
        this._stringFormats.Clear()

        for _, pFnt in this._fonts {
            if (pFnt)
                try DllCall("gdiplus\GdipDeleteFont", "Ptr", pFnt)
        }
        this._fonts.Clear()

        for _, pFamily in this._fontFamilies {
            if (pFamily)
                try DllCall("gdiplus\GdipDeleteFontFamily", "Ptr", pFamily)
        }
        this._fontFamilies.Clear()
        if (this._token) {
            DllCall("gdiplus\GdiplusShutdown", "Ptr", this._token)
            this._token := 0
        }
        if (this._hModule) {
            DllCall("FreeLibrary", "Ptr", this._hModule)
            this._hModule := 0
        }
    }

    static GetFontFamily(fontName) {
        if this._fontFamilies.Has(fontName)
            return this._fontFamilies[fontName]
        pFamily := 0
        DllCall("gdiplus\GdipCreateFontFamilyFromName", "WStr", fontName, "Ptr", 0, "Ptr*", &pFamily)
        if (!pFamily && fontName != "Segoe UI")
            DllCall("gdiplus\GdipCreateFontFamilyFromName", "WStr", "Segoe UI", "Ptr", 0, "Ptr*", &pFamily)
        if (!pFamily)
            DllCall("gdiplus\GdipGetGenericFontFamilySansSerif", "Ptr*", &pFamily)
        if (pFamily)
            this._fontFamilies[fontName] := pFamily
        return pFamily
    }

    static HexToArgb(hexRgb, alpha := 255) {
        if (Type(hexRgb) = "Integer") {
            rgb := hexRgb
        } else {
            clean := StrReplace(String(hexRgb), "#", "")
            if (StrLower(clean) = "white")
                rgb := 0xFFFFFF
            else if (StrLower(clean) = "black")
                rgb := 0x000000
            else if (SubStr(StrLower(clean), 1, 2) = "0x")
                rgb := Integer(clean)
            else
                rgb := Integer("0x" clean)
        }
        return ((alpha & 0xFF) << 24) | (rgb & 0xFFFFFF)
    }

    static BgrToArgb(bgrInt, alpha := 255) {
        r := bgrInt & 0xFF
        g := (bgrInt >> 8) & 0xFF
        b := (bgrInt >> 16) & 0xFF
        rgb := (r << 16) | (g << 8) | b
        return ((alpha & 0xFF) << 24) | rgb
    }

    static CreateRoundedRectPath(x, y, w, h, radius) {
        pPath := 0
        DllCall("gdiplus\GdipCreatePath", "Int", 0, "Ptr*", &pPath)
        if (!pPath)
            return 0

        maxR := Min(w, h) / 2.0
        r := Max(0.0, Min(Float(radius), maxR))
        if (r < 0.5) {
            DllCall("gdiplus\GdipAddPathRectangle", "Ptr", pPath, "Float", Float(x), "Float", Float(y), "Float", Float(w), "Float", Float(h))
            return pPath
        }

        d := r * 2.0
        DllCall("gdiplus\GdipAddPathArc", "Ptr", pPath, "Float", Float(x), "Float", Float(y), "Float", d, "Float", d, "Float", 180.0, "Float", 90.0)
        DllCall("gdiplus\GdipAddPathArc", "Ptr", pPath, "Float", Float(x + w - d), "Float", Float(y), "Float", d, "Float", d, "Float", 270.0, "Float", 90.0)
        DllCall("gdiplus\GdipAddPathArc", "Ptr", pPath, "Float", Float(x + w - d), "Float", Float(y + h - d), "Float", d, "Float", d, "Float", 0.0, "Float", 90.0)
        DllCall("gdiplus\GdipAddPathArc", "Ptr", pPath, "Float", Float(x), "Float", Float(y + h - d), "Float", d, "Float", d, "Float", 90.0, "Float", 90.0)
        DllCall("gdiplus\GdipClosePathFigure", "Ptr", pPath)
        return pPath
    }

    static CreateTypographicFormat(hAlign := 1, vAlign := 1, trimming := 0, extraFlags := 0) {
        pGeneric := 0
        pFormat := 0
        flags := 0x5000 | extraFlags
        DllCall("gdiplus\GdipStringFormatGetGenericTypographic", "Ptr*", &pGeneric)
        if (pGeneric)
            DllCall("gdiplus\GdipCloneStringFormat", "Ptr", pGeneric, "Ptr*", &pFormat)
        if (!pFormat)
            DllCall("gdiplus\GdipCreateStringFormat", "Int", flags, "UShort", 0, "Ptr*", &pFormat)
        if (pFormat) {
            ; 0x1000 = StringFormatFlagsNoWrap, 0x4000 = NoClip, optional 0x0800 = MeasureTrailingSpaces
            DllCall("gdiplus\GdipSetStringFormatFlags", "Ptr", pFormat, "Int", flags)
            DllCall("gdiplus\GdipSetStringFormatAlign", "Ptr", pFormat, "Int", hAlign)
            DllCall("gdiplus\GdipSetStringFormatLineAlign", "Ptr", pFormat, "Int", vAlign)
            DllCall("gdiplus\GdipSetStringFormatTrimming", "Ptr", pFormat, "Int", trimming)
        }
        return pFormat
    }

    static _MeasureTextWidthRaw(textStr, fontName := "Segoe UI", ptSize := 9, fontStyle := 1, extraFlags := 0, antiAlias := false) {
        if (textStr = "")
            return 0.0
        if (!this._token)
            this.Startup()

        hdcScreen := DllCall("GetDC", "Ptr", 0, "Ptr")
        if (!hdcScreen)
            return 0.0
        pGraphics := 0
        pFont := 0
        pFormat := 0
        measuredW := 0.0
        try {
            DllCall("gdiplus\GdipCreateFromHDC", "Ptr", hdcScreen, "Ptr*", &pGraphics)
            if (!pGraphics)
                return 0.0
            if (antiAlias)
                DllCall("gdiplus\GdipSetTextRenderingHint", "Ptr", pGraphics, "Int", 4)

            pFamily := this.GetFontFamily(fontName)
            if (pFamily) {
                pxSize := Float(ptSize) * (96.0 / 72.0)
                DllCall("gdiplus\GdipCreateFont", "Ptr", pFamily, "Float", pxSize, "Int", fontStyle, "Int", 2, "Ptr*", &pFont)
                if (pFont) {
                    pFormat := this.CreateTypographicFormat(0, 1, 0, extraFlags)
                    NumPut("Float", 0.0, "Float", 0.0, "Float", 4000.0, "Float", 400.0, this._layoutRect, 0)
                    NumPut("Float", 0.0, "Float", 0.0, "Float", 0.0, "Float", 0.0, this._boundRect, 0)
                    DllCall("gdiplus\GdipMeasureString", "Ptr", pGraphics, "WStr", textStr, "Int", -1, "Ptr", pFont, "Ptr", this._layoutRect, "Ptr", pFormat, "Ptr", this._boundRect, "Ptr", 0, "Ptr", 0)
                    measuredW := Float(NumGet(this._boundRect, 8, "Float"))
                }
            }
            return measuredW
        } finally {
            if (pFormat)
                DllCall("gdiplus\GdipDeleteStringFormat", "Ptr", pFormat)
            if (pFont)
                DllCall("gdiplus\GdipDeleteFont", "Ptr", pFont)
            if (pGraphics)
                DllCall("gdiplus\GdipDeleteGraphics", "Ptr", pGraphics)
            DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdcScreen)
        }
    }

    static MeasureTextWidth(textStr, fontName := "Segoe UI", ptSize := 9, fontStyle := 1) {
        return Ceil(this._MeasureTextWidthRaw(textStr, fontName, ptSize, fontStyle, 0, false))
    }

    static MeasureTextWidthFloat(textStr, fontName := "Segoe UI", ptSize := 9, fontStyle := 1, includeTrailingSpaces := true) {
        return this._MeasureTextWidthRaw(textStr, fontName, ptSize, fontStyle, includeTrailingSpaces ? 0x0800 : 0, true)
    }

    static DrawRoundedRectPerimeterProgress(pGraphics, x, y, w, h, radius, progress, argb, strokeW := 2.5) {
        p := Min(1.0, Max(0.0, Float(progress)))
        if (!pGraphics || p <= 0.001 || w <= 2 || h <= 2)
            return false

        ins := (Float(strokeW) / 2.0) + 1.0
        rx := Float(x) + ins
        ry := Float(y) + ins
        rw := Max(2.0, Float(w) - 2.0 * ins)
        rh := Max(2.0, Float(h) - 2.0 * ins)
        r := Max(0.0, Min(Float(radius), rw / 2.0, rh / 2.0))
        d := r * 2.0

        topHalf := Max(0.0, (rw - d) / 2.0)
        sideH := Max(0.0, rh - d)
        botW := Max(0.0, rw - d)
        arcLen := (r > 0.05) ? (1.5707963267948966 * r) : 0.0
        totalP := 2.0 * (rw - d) + 2.0 * (rh - d) + 4.0 * arcLen
        if (totalP <= 0.001)
            return false

        pPath := 0
        pPen := 0
        try {
            DllCall("gdiplus\GdipCreatePath", "Int", 0, "Ptr*", &pPath)
            if (!pPath)
                return false

            rem := totalP * p
            cx := rx + rw / 2.0
            hasSeg := false

            ; 1. Top-right half edge: (cx, ry) -> (rx + rw - r, ry)
            if (rem > 0.0001 && topHalf > 0.001) {
                seg := Min(rem, topHalf)
                DllCall("gdiplus\GdipAddPathLine", "Ptr", pPath, "Float", cx, "Float", ry, "Float", cx + seg, "Float", ry)
                rem -= seg
                hasSeg := true
            }
            ; 2. Top-Right 90 deg arc (-90 -> 0)
            if (rem > 0.0001 && r > 0.05 && arcLen > 0.001) {
                seg := Min(rem, arcLen)
                sweep := 90.0 * (seg / arcLen)
                DllCall("gdiplus\GdipAddPathArc", "Ptr", pPath, "Float", rx + rw - d, "Float", ry, "Float", d, "Float", d, "Float", -90.0, "Float", sweep)
                rem -= seg
                hasSeg := true
            }
            ; 3. Right edge
            if (rem > 0.0001 && sideH > 0.001) {
                seg := Min(rem, sideH)
                DllCall("gdiplus\GdipAddPathLine", "Ptr", pPath, "Float", rx + rw, "Float", ry + r, "Float", rx + rw, "Float", ry + r + seg)
                rem -= seg
                hasSeg := true
            }
            ; 4. Bottom-Right 90 deg arc (0 -> 90)
            if (rem > 0.0001 && r > 0.05 && arcLen > 0.001) {
                seg := Min(rem, arcLen)
                sweep := 90.0 * (seg / arcLen)
                DllCall("gdiplus\GdipAddPathArc", "Ptr", pPath, "Float", rx + rw - d, "Float", ry + rh - d, "Float", d, "Float", d, "Float", 0.0, "Float", sweep)
                rem -= seg
                hasSeg := true
            }
            ; 5. Bottom edge
            if (rem > 0.0001 && botW > 0.001) {
                seg := Min(rem, botW)
                DllCall("gdiplus\GdipAddPathLine", "Ptr", pPath, "Float", rx + rw - r, "Float", ry + rh, "Float", rx + rw - r - seg, "Float", ry + rh)
                rem -= seg
                hasSeg := true
            }
            ; 6. Bottom-Left 90 deg arc (90 -> 180)
            if (rem > 0.0001 && r > 0.05 && arcLen > 0.001) {
                seg := Min(rem, arcLen)
                sweep := 90.0 * (seg / arcLen)
                DllCall("gdiplus\GdipAddPathArc", "Ptr", pPath, "Float", rx, "Float", ry + rh - d, "Float", d, "Float", d, "Float", 90.0, "Float", sweep)
                rem -= seg
                hasSeg := true
            }
            ; 7. Left edge
            if (rem > 0.0001 && sideH > 0.001) {
                seg := Min(rem, sideH)
                DllCall("gdiplus\GdipAddPathLine", "Ptr", pPath, "Float", rx, "Float", ry + rh - r, "Float", rx, "Float", ry + rh - r - seg)
                rem -= seg
                hasSeg := true
            }
            ; 8. Top-Left 90 deg arc (180 -> 270)
            if (rem > 0.0001 && r > 0.05 && arcLen > 0.001) {
                seg := Min(rem, arcLen)
                sweep := 90.0 * (seg / arcLen)
                DllCall("gdiplus\GdipAddPathArc", "Ptr", pPath, "Float", rx, "Float", ry, "Float", d, "Float", d, "Float", 180.0, "Float", sweep)
                rem -= seg
                hasSeg := true
            }
            ; 9. Top-left half edge
            if (rem > 0.0001 && topHalf > 0.001) {
                seg := Min(rem, topHalf)
                DllCall("gdiplus\GdipAddPathLine", "Ptr", pPath, "Float", rx + r, "Float", ry, "Float", rx + r + seg, "Float", ry)
                hasSeg := true
            }
            if (!hasSeg)
                return false
            if (p >= 0.999)
                DllCall("gdiplus\GdipClosePathFigure", "Ptr", pPath)

            glowAlpha := Integer(((argb >> 24) & 0xFF) * 0.35) & 0xFF
            glowArgb := (glowAlpha << 24) | (argb & 0x00FFFFFF)
            for _, pass in [{ color: glowArgb, width: Float(strokeW) + 2.5 }, { color: argb, width: Float(strokeW) }] {
                DllCall("gdiplus\GdipCreatePen1", "UInt", pass.color, "Float", pass.width, "Int", 2, "Ptr*", &pPen)
                if (pPen) {
                    DllCall("gdiplus\GdipSetPenStartCap", "Ptr", pPen, "Int", 2)
                    DllCall("gdiplus\GdipSetPenEndCap", "Ptr", pPen, "Int", 2)
                    DllCall("gdiplus\GdipSetPenLineJoin", "Ptr", pPen, "Int", 2)
                    DllCall("gdiplus\GdipDrawPath", "Ptr", pGraphics, "Ptr", pPen, "Ptr", pPath)
                    DllCall("gdiplus\GdipDeletePen", "Ptr", pPen)
                    pPen := 0
                }
            }
            return true
        } finally {
            if (pPen)
                DllCall("gdiplus\GdipDeletePen", "Ptr", pPen)
            if (pPath)
                DllCall("gdiplus\GdipDeletePath", "Ptr", pPath)
        }
    }

    static _GetStringFormat(hAlign := 1, vAlign := 1, trimming := 0) {
        k := hAlign ":" vAlign ":" trimming
        if (this._stringFormats.Has(k))
            return this._stringFormats[k]
        pFmt := this.CreateTypographicFormat(hAlign, vAlign, trimming)
        if (pFmt)
            this._stringFormats[k] := pFmt
        return pFmt
    }

    static _GetCachedFont(pFamily, fontName, pxSize, fontStyle) {
        k := fontName ":" Round(Float(pxSize), 2) ":" fontStyle
        if (this._fonts.Has(k))
            return this._fonts[k]
        pFnt := 0
        DllCall("gdiplus\GdipCreateFont", "Ptr", pFamily, "Float", Float(pxSize), "Int", fontStyle, "Int", 2, "Ptr*", &pFnt)
        if (pFnt) {
            if (this._fonts.Count >= 64) {
                for _, oldF in this._fonts {
                    if (oldF)
                        try DllCall("gdiplus\GdipDeleteFont", "Ptr", oldF)
                }
                this._fonts.Clear()
            }
            this._fonts[k] := pFnt
        }
        return pFnt
    }

    static DrawText(pGraphics, textStr, fontName, ptSize, fontStyle, argbColor, x, y, w, h, hAlign := 1, vAlign := 1, trimming := 0, autoFit := true) {
        if (textStr = "" || w <= 0 || h <= 0)
            return

        pFamily := this.GetFontFamily(fontName)
        if (!pFamily)
            return

        fitPxSize := Float(ptSize) * (96.0 / 72.0)
        pFont := 0
        pFormat := 0
        pBrush := 0
        try {
            pFont := this._GetCachedFont(pFamily, fontName, fitPxSize, fontStyle)
            if (!pFont)
                return

            pFormat := this._GetStringFormat(hAlign, vAlign, trimming)

            ; Auto-fit font size if measured text or glyph width exceeds available box width w
            if (autoFit && StrLen(textStr) >= 1) {
                NumPut("Float", 0.0, "Float", 0.0, "Float", 4000.0, "Float", Float(h * 2), this._layoutRect, 0)
                NumPut("Float", 0.0, "Float", 0.0, "Float", 0.0, "Float", 0.0, this._boundRect, 0)
                DllCall("gdiplus\GdipMeasureString", "Ptr", pGraphics, "WStr", textStr, "Int", -1, "Ptr", pFont, "Ptr", this._layoutRect, "Ptr", pFormat, "Ptr", this._boundRect, "Ptr", 0, "Ptr", 0)
                measuredW := NumGet(this._boundRect, 8, "Float")
                if (measuredW > Float(w) && measuredW > 0.0) {
                    fitPxSize := Max(1.0, fitPxSize * (Float(w) / measuredW) * 0.96)
                    pFont := this._GetCachedFont(pFamily, fontName, fitPxSize, fontStyle)
                    if (!pFont)
                        return
                }
            }

            NumPut("Float", Float(x), "Float", Float(y), "Float", Float(w), "Float", Float(h), this._rectF, 0)

            DllCall("gdiplus\GdipCreateSolidFill", "UInt", argbColor, "Ptr*", &pBrush)
            if (pBrush)
                DllCall("gdiplus\GdipDrawString", "Ptr", pGraphics, "WStr", textStr, "Int", -1, "Ptr", pFont, "Ptr", this._rectF, "Ptr", pFormat, "Ptr", pBrush)
        } finally {
            if (pBrush)
                DllCall("gdiplus\GdipDeleteBrush", "Ptr", pBrush)
        }
    }

    static SetLayeredAlpha(hwnd, alpha) {
        a := Max(0, Min(255, Integer(alpha)))
        NumPut("UInt", 0x01000000 | ((a & 0xFF) << 16), this._blend, 0)
        return DllCall("UpdateLayeredWindow", "Ptr", hwnd, "Ptr", 0, "Ptr", 0, "Ptr", 0, "Ptr", 0, "Ptr", 0, "UInt", 0, "Ptr", this._blend, "UInt", 2, "Int")
    }

    static _AcquireSurface(hwnd, w, h) {
        key := Integer(hwnd)
        if (this._surfaces.Has(key)) {
            cand := this._surfaces[key]
            if (cand.w == w && cand.h == h && cand.hdcMem && cand.hbm && cand.pGraphics)
                return cand
            this.ReleaseSurface(key)
        }
        if (this._surfaces.Count >= 16) {
            stale := []
            for sk in this._surfaces {
                if (!DllCall("IsWindow", "Ptr", sk))
                    stale.Push(sk)
            }
            for _, sk in stale
                this.ReleaseSurface(sk)
        }

        NumPut("UInt", 40, "Int", w, "Int", -h, "UShort", 1, "UShort", 32, this._bi, 0)
        hdcScreen := DllCall("GetDC", "Ptr", 0, "Ptr")
        hdcMem := hdcScreen ? DllCall("CreateCompatibleDC", "Ptr", hdcScreen, "Ptr") : 0
        pBits := 0
        hbm := (hdcScreen && hdcMem) ? DllCall("CreateDIBSection", "Ptr", hdcScreen, "Ptr", this._bi, "UInt", 0, "Ptr*", &pBits, "Ptr", 0, "UInt", 0, "Ptr") : 0
        if (hdcScreen)
            DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdcScreen)
        if (!hdcMem || !hbm) {
            if (hbm)
                DllCall("DeleteObject", "Ptr", hbm)
            if (hdcMem)
                DllCall("DeleteDC", "Ptr", hdcMem)
            return ""
        }
        obm := DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hbm, "Ptr")
        pGraphics := 0
        DllCall("gdiplus\GdipCreateFromHDC", "Ptr", hdcMem, "Ptr*", &pGraphics)
        if (!pGraphics) {
            DllCall("SelectObject", "Ptr", hdcMem, "Ptr", obm)
            DllCall("DeleteObject", "Ptr", hbm)
            DllCall("DeleteDC", "Ptr", hdcMem)
            return ""
        }
        surf := { hdcMem: hdcMem, hbm: hbm, obm: obm, pGraphics: pGraphics, w: w, h: h }
        this._surfaces[key] := surf
        return surf
    }

    static RenderPill(hwnd, x, y, w, h, bgArgb, borderArgb, alpha, radius, iconCfg := "", labelCfg := "", meterLevel := 0.0, meterArgb := 0, holdProgress := 0.0, holdArgb := 0) {
        if (!this._token)
            this.Startup()
        if (!hwnd || w <= 0 || h <= 0)
            return false

        surf := this._AcquireSurface(hwnd, w, h)
        if (!IsObject(surf))
            return false

        hdcMem := surf.hdcMem
        pGraphics := surf.pGraphics
        pPath := 0
        pFill := 0
        pMeterBrush := 0
        pPen := 0
        try {
            DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", pGraphics, "Int", 4)
            DllCall("gdiplus\GdipSetTextRenderingHint", "Ptr", pGraphics, "Int", 4)
            DllCall("gdiplus\GdipResetClip", "Ptr", pGraphics)
            DllCall("gdiplus\GdipGraphicsClear", "Ptr", pGraphics, "UInt", 0)

            pad := 0.75
            pPath := this.CreateRoundedRectPath(pad, pad, w - 1.5, h - 1.5, radius)
            if (pPath) {
                DllCall("gdiplus\GdipCreateSolidFill", "UInt", bgArgb, "Ptr*", &pFill)
                if (pFill) {
                    DllCall("gdiplus\GdipFillPath", "Ptr", pGraphics, "Ptr", pFill, "Ptr", pPath)
                    DllCall("gdiplus\GdipDeleteBrush", "Ptr", pFill)
                    pFill := 0
                }

                lvl := Min(1.0, Max(0.0, Float(meterLevel)))
                if (lvl > 0.01) {
                    barH := Max(2.0, Min(4.5, h * 0.095))
                    barY := Float(h) - pad - barH
                    barW := Max(2.0, (Float(w) - 2.0 * pad) * lvl)
                    DllCall("gdiplus\GdipSetClipPath", "Ptr", pGraphics, "Ptr", pPath, "Int", 0)
                    DllCall("gdiplus\GdipCreateSolidFill", "UInt", (meterArgb ? meterArgb : 0xD8FFFFFF), "Ptr*", &pMeterBrush)
                    if (pMeterBrush) {
                        DllCall("gdiplus\GdipFillRectangle", "Ptr", pGraphics, "Ptr", pMeterBrush, "Float", Float(pad), "Float", barY, "Float", barW, "Float", barH)
                        DllCall("gdiplus\GdipDeleteBrush", "Ptr", pMeterBrush)
                        pMeterBrush := 0
                    }
                    DllCall("gdiplus\GdipResetClip", "Ptr", pGraphics)
                }

                DllCall("gdiplus\GdipCreatePen1", "UInt", borderArgb, "Float", 1.5, "Int", 2, "Ptr*", &pPen)
                if (pPen) {
                    DllCall("gdiplus\GdipDrawPath", "Ptr", pGraphics, "Ptr", pPen, "Ptr", pPath)
                    DllCall("gdiplus\GdipDeletePen", "Ptr", pPen)
                    pPen := 0
                }

                DllCall("gdiplus\GdipDeletePath", "Ptr", pPath)
                pPath := 0
            }

            if (Float(holdProgress) > 0.001) {
                holdCol := holdArgb ? holdArgb : 0xFFF59E0B
                holdStroke := Max(2.0, Min(4.0, Float(h) * 0.08))
                this.DrawRoundedRectPerimeterProgress(pGraphics, 0, 0, w, h, radius, holdProgress, holdCol, holdStroke)
            }

            if (IsObject(iconCfg) && iconCfg.text != "") {
                this.DrawText(pGraphics, iconCfg.text, iconCfg.font, iconCfg.size, 0, iconCfg.color, iconCfg.x, 0, iconCfg.w, h, 1, 1)
            }
            if (IsObject(labelCfg)) {
                hasDraws := labelCfg.HasOwnProp("draws") && IsObject(labelCfg.draws) && labelCfg.draws.Length > 0
                hasText := labelCfg.HasOwnProp("text") && labelCfg.text != ""
                if (hasDraws || hasText) {
                    style := labelCfg.HasOwnProp("bold") && labelCfg.bold ? 1 : 0
                    align := labelCfg.HasOwnProp("align") ? labelCfg.align : 0
                    autoFit := labelCfg.HasOwnProp("autoFit") ? labelCfg.autoFit : true
                    hasClip := labelCfg.HasOwnProp("clipW") && labelCfg.clipW > 0
                    if (hasClip) {
                        clipX := labelCfg.HasOwnProp("clipX") ? Float(labelCfg.clipX) : Float(labelCfg.x)
                        DllCall("gdiplus\GdipSetClipRect", "Ptr", pGraphics, "Float", clipX, "Float", 0.0, "Float", Float(labelCfg.clipW), "Float", Float(h), "Int", 0)
                    }
                    if (hasDraws) {
                        for _, dItem in labelCfg.draws {
                            if (IsObject(dItem) && dItem.text != "")
                                this.DrawText(pGraphics, dItem.text, "Segoe UI", labelCfg.size, style, labelCfg.color, Float(dItem.x), 0, Float(dItem.w), h, align, 1, 0, false)
                        }
                    } else {
                        this.DrawText(pGraphics, labelCfg.text, "Segoe UI", labelCfg.size, style, labelCfg.color, labelCfg.x, 0, labelCfg.w, h, align, 1, 0, autoFit)
                    }
                    if (hasClip) {
                        DllCall("gdiplus\GdipResetClip", "Ptr", pGraphics)
                    }
                }
            }

            DllCall("gdiplus\GdipFlush", "Ptr", pGraphics, "Int", 1)

            NumPut("Int", Integer(x), "Int", Integer(y), this._ptWin, 0)
            NumPut("Int", Integer(w), "Int", Integer(h), this._szWin, 0)
            NumPut("Int64", 0, this._ptSrc, 0)

            a := Max(0, Min(255, Integer(alpha)))
            NumPut("UInt", 0x01000000 | ((a & 0xFF) << 16), this._blend, 0)

            ok := DllCall("UpdateLayeredWindow", "Ptr", hwnd, "Ptr", 0, "Ptr", this._ptWin, "Ptr", this._szWin, "Ptr", hdcMem, "Ptr", this._ptSrc, "UInt", 0, "Ptr", this._blend, "UInt", 2, "Int")
            return ok != 0
        } finally {
            if (pPen)
                DllCall("gdiplus\GdipDeletePen", "Ptr", pPen)
            if (pMeterBrush)
                DllCall("gdiplus\GdipDeleteBrush", "Ptr", pMeterBrush)
            if (pFill)
                DllCall("gdiplus\GdipDeleteBrush", "Ptr", pFill)
            if (pPath)
                DllCall("gdiplus\GdipDeletePath", "Ptr", pPath)
        }
    }
}
