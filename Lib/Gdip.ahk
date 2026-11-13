; ==============================================================================
; Module: Gdip.ahk
; Description: GDI+ Layered Window rendering engine for AutoHotkey v2
; ==============================================================================

class Gdip {
    static _token := 0
    static _hModule := 0
    static _fontFamilies := Map()
    static _bi := Buffer(40, 0)
    static _ptWin := Buffer(8, 0)
    static _szWin := Buffer(8, 0)
    static _ptSrc := Buffer(8, 0)
    static _blend := Buffer(4, 0)
    static _layoutRect := Buffer(16, 0)
    static _boundRect := Buffer(16, 0)
    static _rectF := Buffer(16, 0)

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
        if (status != 0)
            return false
        this._token := token
        return true
    }

    static Shutdown() {
        for _, pFamily in this._fontFamilies {
            if (pFamily)
                DllCall("gdiplus\GdipDeleteFontFamily", "Ptr", pFamily)
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

    static CreateTypographicFormat(hAlign := 1, vAlign := 1, trimming := 0) {
        pGeneric := 0
        pFormat := 0
        DllCall("gdiplus\GdipStringFormatGetGenericTypographic", "Ptr*", &pGeneric)
        if (pGeneric)
            DllCall("gdiplus\GdipCloneStringFormat", "Ptr", pGeneric, "Ptr*", &pFormat)
        if (!pFormat)
            DllCall("gdiplus\GdipCreateStringFormat", "Int", 0x5000, "UShort", 0, "Ptr*", &pFormat)
        if (pFormat) {
            ; 0x1000 = StringFormatFlagsNoWrap, 0x4000 = StringFormatFlagsNoClip
            DllCall("gdiplus\GdipSetStringFormatFlags", "Ptr", pFormat, "Int", 0x5000)
            DllCall("gdiplus\GdipSetStringFormatAlign", "Ptr", pFormat, "Int", hAlign)
            DllCall("gdiplus\GdipSetStringFormatLineAlign", "Ptr", pFormat, "Int", vAlign)
            DllCall("gdiplus\GdipSetStringFormatTrimming", "Ptr", pFormat, "Int", trimming)
        }
        return pFormat
    }

    static MeasureTextWidth(textStr, fontName := "Segoe UI", ptSize := 9, fontStyle := 1) {
        if (textStr = "")
            return 0
        if (!this._token)
            this.Startup()

        hdcScreen := DllCall("GetDC", "Ptr", 0, "Ptr")
        if (!hdcScreen)
            return 0
        pGraphics := 0
        DllCall("gdiplus\GdipCreateFromHDC", "Ptr", hdcScreen, "Ptr*", &pGraphics)
        if (!pGraphics) {
            DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdcScreen)
            return 0
        }

        pFamily := this.GetFontFamily(fontName)
        measuredW := 0
        if (pFamily) {
            pFont := 0
            DllCall("gdiplus\GdipCreateFont", "Ptr", pFamily, "Float", Float(ptSize), "Int", fontStyle, "Int", 3, "Ptr*", &pFont)
            if (pFont) {
                pFormat := this.CreateTypographicFormat(0, 1, 0)
                NumPut("Float", 0.0, "Float", 0.0, "Float", 4000.0, "Float", 400.0, this._layoutRect, 0)
                NumPut("Float", 0.0, "Float", 0.0, "Float", 0.0, "Float", 0.0, this._boundRect, 0)
                DllCall("gdiplus\GdipMeasureString", "Ptr", pGraphics, "WStr", textStr, "Int", -1, "Ptr", pFont, "Ptr", this._layoutRect, "Ptr", pFormat, "Ptr", this._boundRect, "Ptr", 0, "Ptr", 0)
                measuredW := Ceil(NumGet(this._boundRect, 8, "Float"))
                if (pFormat)
                    DllCall("gdiplus\GdipDeleteStringFormat", "Ptr", pFormat)
                DllCall("gdiplus\GdipDeleteFont", "Ptr", pFont)
            }
        }

        DllCall("gdiplus\GdipDeleteGraphics", "Ptr", pGraphics)
        DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdcScreen)
        return measuredW
    }

    static DrawText(pGraphics, textStr, fontName, ptSize, fontStyle, argbColor, x, y, w, h, hAlign := 1, vAlign := 1, trimming := 0) {
        if (textStr = "" || w <= 0 || h <= 0)
            return

        pFamily := this.GetFontFamily(fontName)
        if (!pFamily)
            return

        fitPtSize := Float(ptSize)
        pFont := 0
        DllCall("gdiplus\GdipCreateFont", "Ptr", pFamily, "Float", fitPtSize, "Int", fontStyle, "Int", 3, "Ptr*", &pFont)
        if (!pFont)
            return

        pFormat := this.CreateTypographicFormat(hAlign, vAlign, trimming)

        ; Auto-fit font size if measured multi-character text width exceeds available box width w
        if (StrLen(textStr) > 1) {
            NumPut("Float", 0.0, "Float", 0.0, "Float", 4000.0, "Float", Float(h * 2), this._layoutRect, 0)
            NumPut("Float", 0.0, "Float", 0.0, "Float", 0.0, "Float", 0.0, this._boundRect, 0)
            DllCall("gdiplus\GdipMeasureString", "Ptr", pGraphics, "WStr", textStr, "Int", -1, "Ptr", pFont, "Ptr", this._layoutRect, "Ptr", pFormat, "Ptr", this._boundRect, "Ptr", 0, "Ptr", 0)
            measuredW := NumGet(this._boundRect, 8, "Float")
            if (measuredW > Float(w) && measuredW > 0.0) {
                fitPtSize := Max(1.0, fitPtSize * (Float(w) / measuredW) * 0.96)
                DllCall("gdiplus\GdipDeleteFont", "Ptr", pFont)
                pFont := 0
                DllCall("gdiplus\GdipCreateFont", "Ptr", pFamily, "Float", fitPtSize, "Int", fontStyle, "Int", 3, "Ptr*", &pFont)
                if (!pFont) {
                    if (pFormat)
                        DllCall("gdiplus\GdipDeleteStringFormat", "Ptr", pFormat)
                    return
                }
            }
        }

        NumPut("Float", Float(x), "Float", Float(y), "Float", Float(w), "Float", Float(h), this._rectF, 0)

        pBrush := 0
        DllCall("gdiplus\GdipCreateSolidFill", "UInt", argbColor, "Ptr*", &pBrush)
        if (pBrush) {
            DllCall("gdiplus\GdipDrawString", "Ptr", pGraphics, "WStr", textStr, "Int", -1, "Ptr", pFont, "Ptr", this._rectF, "Ptr", pFormat, "Ptr", pBrush)
            DllCall("gdiplus\GdipDeleteBrush", "Ptr", pBrush)
        }

        if (pFormat)
            DllCall("gdiplus\GdipDeleteStringFormat", "Ptr", pFormat)
        DllCall("gdiplus\GdipDeleteFont", "Ptr", pFont)
    }

    static SetLayeredAlpha(hwnd, alpha) {
        a := Max(0, Min(255, Integer(alpha)))
        NumPut("UInt", 0x01000000 | ((a & 0xFF) << 16), this._blend, 0)
        return DllCall("UpdateLayeredWindow", "Ptr", hwnd, "Ptr", 0, "Ptr", 0, "Ptr", 0, "Ptr", 0, "Ptr", 0, "UInt", 0, "Ptr", this._blend, "UInt", 2, "Int")
    }

    static RenderPill(hwnd, x, y, w, h, bgArgb, borderArgb, alpha, radius, iconCfg := "", labelCfg := "") {
        if (!this._token)
            this.Startup()
        if (!hwnd || w <= 0 || h <= 0)
            return false

        NumPut("UInt", 40, "Int", w, "Int", -h, "UShort", 1, "UShort", 32, this._bi, 0)

        hdcScreen := DllCall("GetDC", "Ptr", 0, "Ptr")
        hdcMem := DllCall("CreateCompatibleDC", "Ptr", hdcScreen, "Ptr")
        pBits := 0
        hbm := DllCall("CreateDIBSection", "Ptr", hdcScreen, "Ptr", this._bi, "UInt", 0, "Ptr*", &pBits, "Ptr", 0, "UInt", 0, "Ptr")
        DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdcScreen)

        if (!hdcMem || !hbm) {
            if (hbm)
                DllCall("DeleteObject", "Ptr", hbm)
            if (hdcMem)
                DllCall("DeleteDC", "Ptr", hdcMem)
            return false
        }

        obm := DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hbm, "Ptr")
        pGraphics := 0
        DllCall("gdiplus\GdipCreateFromHDC", "Ptr", hdcMem, "Ptr*", &pGraphics)

        if (pGraphics) {
            DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", pGraphics, "Int", 4)
            DllCall("gdiplus\GdipSetTextRenderingHint", "Ptr", pGraphics, "Int", 4)
            DllCall("gdiplus\GdipGraphicsClear", "Ptr", pGraphics, "UInt", 0)

            pad := 0.75
            pPath := this.CreateRoundedRectPath(pad, pad, w - 1.5, h - 1.5, radius)
            if (pPath) {
                pFill := 0
                DllCall("gdiplus\GdipCreateSolidFill", "UInt", bgArgb, "Ptr*", &pFill)
                if (pFill) {
                    DllCall("gdiplus\GdipFillPath", "Ptr", pGraphics, "Ptr", pFill, "Ptr", pPath)
                    DllCall("gdiplus\GdipDeleteBrush", "Ptr", pFill)
                }

                pPen := 0
                DllCall("gdiplus\GdipCreatePen1", "UInt", borderArgb, "Float", 1.5, "Int", 2, "Ptr*", &pPen)
                if (pPen) {
                    DllCall("gdiplus\GdipDrawPath", "Ptr", pGraphics, "Ptr", pPen, "Ptr", pPath)
                    DllCall("gdiplus\GdipDeletePen", "Ptr", pPen)
                }

                DllCall("gdiplus\GdipDeletePath", "Ptr", pPath)
            }

            if (IsObject(iconCfg) && iconCfg.text != "") {
                this.DrawText(pGraphics, iconCfg.text, iconCfg.font, iconCfg.size, 0, iconCfg.color, iconCfg.x, 0, iconCfg.w, h, 1, 1)
            }
            if (IsObject(labelCfg) && labelCfg.text != "") {
                style := labelCfg.HasOwnProp("bold") && labelCfg.bold ? 1 : 0
                align := labelCfg.HasOwnProp("align") ? labelCfg.align : 0
                this.DrawText(pGraphics, labelCfg.text, "Segoe UI", labelCfg.size, style, labelCfg.color, labelCfg.x, 0, labelCfg.w, h, align, 1)
            }

            DllCall("gdiplus\GdipDeleteGraphics", "Ptr", pGraphics)
        }

        NumPut("Int", Integer(x), "Int", Integer(y), this._ptWin, 0)
        NumPut("Int", Integer(w), "Int", Integer(h), this._szWin, 0)
        NumPut("Int64", 0, this._ptSrc, 0)

        a := Max(0, Min(255, Integer(alpha)))
        NumPut("UInt", 0x01000000 | ((a & 0xFF) << 16), this._blend, 0)

        ok := DllCall("UpdateLayeredWindow", "Ptr", hwnd, "Ptr", 0, "Ptr", this._ptWin, "Ptr", this._szWin, "Ptr", hdcMem, "Ptr", this._ptSrc, "UInt", 0, "Ptr", this._blend, "UInt", 2, "Int")

        DllCall("SelectObject", "Ptr", hdcMem, "Ptr", obm)
        DllCall("DeleteObject", "Ptr", hbm)
        DllCall("DeleteDC", "Ptr", hdcMem)
        return ok != 0
    }
}
