; ==============================================================================
; Module: QrCode.ahk
; Description: Zero-dependency pure AutoHotkey v2 ISO/IEC 18004 QR Code encoder
;              (Byte mode, ECC Level L, Versions 1..11) + GDI+ HBITMAP renderer.
; ==============================================================================

class QrCode {
    static _gfInitialized := false
    static _gfExp := []
    static _gfLog := []

    ; ECC Level L specs indexed by Version 1..14:
    ; [version, totalDataBytes, ecBytesPerBlock, g1Blocks, g1DataBytes, g2Blocks, g2DataBytes]
    static _SPECS := [
        [1,  19,  7,  1, 19,  0,  0],
        [2,  34,  10, 1, 34,  0,  0],
        [3,  55,  15, 1, 55,  0,  0],
        [4,  80,  20, 1, 80,  0,  0],
        [5,  108, 26, 1, 108, 0,  0],
        [6,  136, 18, 2, 68,  0,  0],
        [7,  156, 20, 2, 78,  0,  0],
        [8,  194, 24, 2, 97,  0,  0],
        [9,  232, 30, 2, 116, 0,  0],
        [10, 274, 18, 2, 68,  2, 69],
        [11, 324, 20, 4, 81,  0,  0],
        [12, 370, 24, 2, 92,  2, 93],
        [13, 428, 26, 4, 107, 0,  0],
        [14, 461, 30, 3, 115, 1, 116]
    ]

    ; ECC Level M specs indexed by Version 1..14 (for external QR decoders):
    static _SPECS_M := [
        [1,  16,  10, 1, 16, 0, 0],
        [2,  28,  16, 1, 28, 0, 0],
        [3,  44,  26, 1, 44, 0, 0],
        [4,  64,  18, 2, 32, 0, 0],
        [5,  86,  24, 2, 43, 0, 0],
        [6,  108, 16, 4, 27, 0, 0],
        [7,  124, 18, 4, 31, 0, 0],
        [8,  154, 22, 2, 38, 2, 39],
        [9,  182, 22, 3, 36, 2, 37],
        [10, 216, 26, 4, 43, 1, 44],
        [11, 254, 30, 1, 50, 4, 51],
        [12, 290, 22, 6, 36, 2, 37],
        [13, 334, 22, 8, 37, 1, 38],
        [14, 365, 24, 4, 40, 5, 41]
    ]

    static _ALIGN_COORDS := [
        [],
        [6, 18],
        [6, 22],
        [6, 26],
        [6, 30],
        [6, 34],
        [6, 22, 38],
        [6, 24, 42],
        [6, 26, 46],
        [6, 28, 50],
        [6, 30, 54],
        [6, 32, 58],
        [6, 34, 62],
        [6, 26, 46, 66]
    ]

    static _InitGf() {
        if (this._gfInitialized)
            return
        this._gfExp := []
        this._gfLog := []
        Loop 512 {
            this._gfExp.Push(0)
        }
        Loop 256 {
            this._gfLog.Push(0)
        }
        val := 1
        Loop 255 {
            i := A_Index - 1
            this._gfExp[i + 1] := val
            this._gfLog[val + 1] := i
            val <<= 1
            if (val & 0x100)
                val ^= 0x11D
        }
        Loop 255 {
            i := A_Index - 1
            this._gfExp[i + 256] := this._gfExp[i + 1]
        }
        this._gfInitialized := true
    }

    static _GfMul(a, b) {
        if (a = 0 || b = 0)
            return 0
        return this._gfExp[this._gfLog[a + 1] + this._gfLog[b + 1] + 1]
    }

    static _RsGeneratorPoly(ecCount) {
        this._InitGf()
        poly := [1]
        Loop ecCount {
            deg := A_Index - 1
            factor := this._gfExp[deg + 1]
            next := []
            Loop poly.Length + 1
                next.Push(0)
            for idx, coeff in poly {
                next[idx] ^= coeff
                next[idx + 1] ^= this._GfMul(coeff, factor)
            }
            poly := next
        }
        return poly
    }

    static _RsComputeRemainder(dataBytes, ecCount) {
        gen := this._RsGeneratorPoly(ecCount)
        work := []
        for b in dataBytes
            work.Push(b)
        Loop ecCount
            work.Push(0)

        for idx, _ in dataBytes {
            factor := work[idx]
            if (factor != 0) {
                for j, gCoeff in gen {
                    work[idx + j - 1] ^= this._GfMul(factor, gCoeff)
                }
            }
        }
        rem := []
        startIdx := dataBytes.Length + 1
        Loop ecCount {
            rem.Push(work[startIdx + A_Index - 1])
        }
        return rem
    }

    static _StringToUtf8Bytes(str) {
        if (str = "")
            return []
        needed := StrPut(str, "UTF-8")
        if (needed <= 1)
            return []
        buf := Buffer(needed, 0)
        written := StrPut(str, buf, "UTF-8")
        out := []
        Loop written - 1 {
            out.Push(NumGet(buf, A_Index - 1, "UChar"))
        }
        return out
    }

    static _SelectSpec(byteLen) {
        for spec in this._SPECS {
            ver := spec[1]
            totalData := spec[2]
            cntBits := (ver >= 10) ? 16 : 8
            overheadBits := 4 + cntBits
            capBytes := (totalData * 8 - overheadBits) // 8
            if (byteLen <= capBytes)
                return spec
        }
        throw Error("QR payload too long (" byteLen " bytes) for Versions 1..11")
    }

    static _PushBits(bitArr, val, bitLen) {
        Loop bitLen {
            shift := bitLen - A_Index
            bitArr.Push((val >> shift) & 1)
        }
    }

    static EncodeMatrix(payload) {
        bytes := this._StringToUtf8Bytes(String(payload))
        spec := this._SelectSpec(bytes.Length)
        ver := spec[1]
        totalData := spec[2]
        ecPerBlock := spec[3]
        g1Blocks := spec[4]
        g1Len := spec[5]
        g2Blocks := spec[6]
        g2Len := spec[7]

        ; 1. Build bit stream (Mode 0100 = Byte, char count, payload bytes, terminator, pad)
        bits := []
        this._PushBits(bits, 0x4, 4)
        this._PushBits(bits, bytes.Length, (ver >= 10) ? 16 : 8)
        for b in bytes
            this._PushBits(bits, b, 8)

        maxBits := totalData * 8
        termBits := Min(4, maxBits - bits.Length)
        Loop termBits
            bits.Push(0)
        while (Mod(bits.Length, 8) != 0)
            bits.Push(0)

        codewords := []
        pos := 1
        while (pos <= bits.Length) {
            byteVal := 0
            Loop 8 {
                byteVal := (byteVal << 1) | bits[pos + A_Index - 1]
            }
            codewords.Push(byteVal)
            pos += 8
        }
        padToggle := true
        while (codewords.Length < totalData) {
            codewords.Push(padToggle ? 0xEC : 0x11)
            padToggle := !padToggle
        }

        ; 2. Split into RS blocks and compute EC codewords
        blocksData := []
        blocksEc := []
        cursor := 1
        Loop g1Blocks {
            blk := []
            Loop g1Len {
                blk.Push(codewords[cursor])
                cursor++
            }
            blocksData.Push(blk)
            blocksEc.Push(this._RsComputeRemainder(blk, ecPerBlock))
        }
        Loop g2Blocks {
            blk := []
            Loop g2Len {
                blk.Push(codewords[cursor])
                cursor++
            }
            blocksData.Push(blk)
            blocksEc.Push(this._RsComputeRemainder(blk, ecPerBlock))
        }

        ; 3. Interleave data and EC codewords
        finalBytes := []
        maxDataLen := Max(g1Len, g2Len)
        Loop maxDataLen {
            colIdx := A_Index
            for blk in blocksData {
                if (colIdx <= blk.Length)
                    finalBytes.Push(blk[colIdx])
            }
        }
        Loop ecPerBlock {
            colIdx := A_Index
            for ecBlk in blocksEc {
                if (colIdx <= ecBlk.Length)
                    finalBytes.Push(ecBlk[colIdx])
            }
        }

        ; 4. Build base matrix & reserved map
        size := 4 * ver + 17
        modules := []
        isFunc := []
        Loop size {
            rowArr := []
            fnArr := []
            Loop size {
                rowArr.Push(0)
                fnArr.Push(false)
            }
            modules.Push(rowArr)
            isFunc.Push(fnArr)
        }

        SetFunc(r, col, dark) {
            if (r >= 0 && r < size && col >= 0 && col < size) {
                modules[r + 1][col + 1] := dark ? 1 : 0
                isFunc[r + 1][col + 1] := true
            }
        }

        DrawFinder(topR, leftC) {
            Loop 9 {
                dr := A_Index - 2
                Loop 9 {
                    dc := A_Index - 2
                    r := topR + dr
                    col := leftC + dc
                    if (r < 0 || r >= size || col < 0 || col >= size)
                        continue
                    inInner := (dr >= 2 && dr <= 4 && dc >= 2 && dc <= 4)
                    inOuter := (dr = 0 || dr = 6 || dc = 0 || dc = 6) && (dr >= 0 && dr <= 6 && dc >= 0 && dc <= 6)
                    SetFunc(r, col, inInner || inOuter)
                }
            }
        }
        DrawFinder(0, 0)
        DrawFinder(0, size - 7)
        DrawFinder(size - 7, 0)

        ; Alignment patterns
        coords := this._ALIGN_COORDS[ver]
        for alignRow in coords {
            for alignCol in coords {
                if (isFunc[alignRow + 1][alignCol + 1])
                    continue
                Loop 5 {
                    dr := A_Index - 3
                    Loop 5 {
                        dc := A_Index - 3
                        dark := (Max(Abs(dr), Abs(dc)) != 1)
                        SetFunc(alignRow + dr, alignCol + dc, dark)
                    }
                }
            }
        }

        ; Timing patterns
        Loop size - 16 {
            idx := A_Index + 7
            dark := (Mod(idx, 2) = 0) ? 1 : 0
            if (!isFunc[7][idx + 1])
                SetFunc(6, idx, dark)
            if (!isFunc[idx + 1][7])
                SetFunc(idx, 6, dark)
        }

        ; Dark module + reserve format info
        SetFunc(size - 8, 8, true)
        Loop 9 {
            k := A_Index - 1
            if (k != 6) {
                if (!isFunc[9][k + 1])
                    SetFunc(8, k, false)
                if (!isFunc[k + 1][9])
                    SetFunc(k, 8, false)
            }
        }
        Loop 8 {
            k := A_Index - 1
            if (k < 8 && !isFunc[9][size - k])
                SetFunc(8, size - 1 - k, false)
            if (k < 7 && !isFunc[size - k][9])
                SetFunc(size - 1 - k, 8, false)
        }

        ; Reserve + write Version info if version >= 7
        if (ver >= 7) {
            verBits := this._ComputeVersionBits(ver)
            Loop 18 {
                bitIdx := A_Index - 1
                dark := ((verBits >> bitIdx) & 1) = 1
                a := bitIdx // 3
                b := Mod(bitIdx, 3) + size - 11
                SetFunc(a, b, dark)
                SetFunc(b, a, dark)
            }
        }

        ; Place interleaved data + EC bits in zigzag
        finalBits := []
        for fb in finalBytes
            this._PushBits(finalBits, fb, 8)

        bitCursor := 1
        upward := true
        colRight := size - 1
        while (colRight > 0) {
            if (colRight = 6)
                colRight -= 1
            Loop size {
                rowStep := A_Index - 1
                r := upward ? (size - 1 - rowStep) : rowStep
                Loop 2 {
                    col := colRight - (A_Index - 1)
                    if (!isFunc[r + 1][col + 1]) {
                        bitVal := 0
                        if (bitCursor <= finalBits.Length) {
                            bitVal := finalBits[bitCursor]
                            bitCursor++
                        }
                        modules[r + 1][col + 1] := bitVal
                    }
                }
            }
            upward := !upward
            colRight -= 2
        }

        ; Evaluate all 8 masks and keep lowest penalty
        bestMask := 0
        bestScore := 0x7FFFFFFF
        Loop 8 {
            mId := A_Index - 1
            candidate := this._ApplyMaskAndFormat(modules, isFunc, size, mId)
            score := this._EvaluatePenalty(candidate, size)
            if (score < bestScore) {
                bestScore := score
                bestMask := mId
            }
        }

        bestMatrix := this._ApplyMaskAndFormat(modules, isFunc, size, bestMask)
        return { version: ver, size: size, mask: bestMask, modules: bestMatrix }
    }

    static _MaskBit(maskId, r, col) {
        switch maskId {
            case 0: return Mod(r + col, 2) = 0
            case 1: return Mod(r, 2) = 0
            case 2: return Mod(col, 3) = 0
            case 3: return Mod(r + col, 3) = 0
            case 4: return Mod((r // 2) + (col // 3), 2) = 0
            case 5: return (Mod(r * col, 2) + Mod(r * col, 3)) = 0
            case 6: return Mod(Mod(r * col, 2) + Mod(r * col, 3), 2) = 0
            case 7: return Mod(Mod(r + col, 2) + Mod(r * col, 3), 2) = 0
        }
        return false
    }

    static _ComputeFormatBits(maskId) {
        ; ECC Level L = 0b01
        data := (1 << 3) | (maskId & 7)
        rem := data
        Loop 10
            rem := (rem << 1) ^ (((rem >> 9) & 1) ? 0x537 : 0)
        return ((data << 10) | rem) ^ 0x5412
    }

    static _ComputeVersionBits(ver) {
        rem := ver
        Loop 12
            rem := (rem << 1) ^ (((rem >> 11) & 1) ? 0x1F25 : 0)
        return (ver << 12) | rem
    }

    static _ApplyMaskAndFormat(baseModules, isFunc, size, maskId) {
        mat := []
        Loop size {
            r := A_Index - 1
            rowOut := []
            Loop size {
                col := A_Index - 1
                v := baseModules[r + 1][col + 1]
                if (!isFunc[r + 1][col + 1] && this._MaskBit(maskId, r, col))
                    v := v ^ 1
                rowOut.Push(v)
            }
            mat.Push(rowOut)
        }

        fmt := this._ComputeFormatBits(maskId)
        Loop 15 {
            i := A_Index - 1
            dark := ((fmt >> i) & 1)
            ; Vertical strip
            if (i < 6)
                mat[i + 1][9] := dark
            else if (i < 8)
                mat[i + 2][9] := dark
            else
                mat[size - 15 + i + 1][9] := dark

            ; Horizontal strip
            if (i < 8)
                mat[9][size - i] := dark
            else if (i < 9)
                mat[9][15 - i + 1] := dark
            else
                mat[9][15 - i] := dark
        }
        mat[size - 7][9] := 1
        return mat
    }

    static _EvaluatePenalty(mat, size) {
        score := 0
        ; Rule 1: 5+ consecutive same color in rows and columns
        Loop size {
            r := A_Index
            runColor := -1
            runLen := 0
            Loop size {
                col := A_Index
                v := mat[r][col]
                if (v = runColor) {
                    runLen++
                } else {
                    if (runLen >= 5)
                        score += 3 + (runLen - 5)
                    runColor := v
                    runLen := 1
                }
            }
            if (runLen >= 5)
                score += 3 + (runLen - 5)
        }
        Loop size {
            col := A_Index
            runColor := -1
            runLen := 0
            Loop size {
                r := A_Index
                v := mat[r][col]
                if (v = runColor) {
                    runLen++
                } else {
                    if (runLen >= 5)
                        score += 3 + (runLen - 5)
                    runColor := v
                    runLen := 1
                }
            }
            if (runLen >= 5)
                score += 3 + (runLen - 5)
        }
        ; Rule 2: 2x2 blocks
        Loop size - 1 {
            r := A_Index
            Loop size - 1 {
                col := A_Index
                v := mat[r][col]
                if (v = mat[r][col + 1] && v = mat[r + 1][col] && v = mat[r + 1][col + 1])
                    score += 3
            }
        }
        ; Rule 4: dark ratio deviation from 50%
        darkCount := 0
        Loop size {
            r := A_Index
            Loop size
                darkCount += mat[r][A_Index]
        }
        pct := (darkCount * 100) / (size * size)
        kSteps := Abs(Floor(pct) - 50) // 5
        score += kSteps * 10
        return score
    }

    static _BuildQrGdipBitmap(payload, targetSize := 160, quiet := 4, fgArgb := 0xFF111827, bgArgb := 0xFFFFFFFF) {
        Gdip.Startup()
        qr := this.EncodeMatrix(payload)
        modCount := qr.size
        totalMods := modCount + (quiet * 2)

        pBitmap := 0
        pGraphics := 0
        pBrush := 0
        try {
            DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", targetSize, "Int", targetSize, "Int", 0, "Int", 0x26200A, "Ptr", 0, "Ptr*", &pBitmap)
            if (!pBitmap)
                return { pBitmap: 0, qr: qr }

            DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", pBitmap, "Ptr*", &pGraphics)
            if (pGraphics) {
                DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", pGraphics, "Int", 0)
                DllCall("gdiplus\GdipSetPixelOffsetMode", "Ptr", pGraphics, "Int", 3)
                DllCall("gdiplus\GdipGraphicsClear", "Ptr", pGraphics, "UInt", bgArgb)

                cellPx := Floor(targetSize / totalMods)
                if (cellPx < 1)
                    cellPx := 1
                drawSpan := cellPx * totalMods
                offsetPx := Floor((targetSize - drawSpan) / 2)

                DllCall("gdiplus\GdipCreateSolidFill", "UInt", fgArgb, "Ptr*", &pBrush)
                if (pBrush) {
                    Loop modCount {
                        r := A_Index
                        rowArr := qr.modules[r]
                        y := offsetPx + (r - 1 + quiet) * cellPx
                        Loop modCount {
                            col := A_Index
                            if (rowArr[col] = 1) {
                                x := offsetPx + (col - 1 + quiet) * cellPx
                                DllCall("gdiplus\GdipFillRectangleI", "Ptr", pGraphics, "Ptr", pBrush, "Int", x, "Int", y, "Int", cellPx, "Int", cellPx)
                            }
                        }
                    }
                }
            }
            return { pBitmap: pBitmap, qr: qr }
        } catch as err {
            if (pBitmap)
                DllCall("gdiplus\GdipDisposeImage", "Ptr", pBitmap)
            throw err
        } finally {
            if (pBrush)
                DllCall("gdiplus\GdipDeleteBrush", "Ptr", pBrush)
            if (pGraphics)
                DllCall("gdiplus\GdipDeleteGraphics", "Ptr", pGraphics)
        }
    }

    /**
     * Builds an HBITMAP of exact targetSize x targetSize pixels containing the QR code
     * with an ISO-compliant 4-module white quiet zone.
     */
    static BuildHBitmap(payload, targetSize := 180, fgArgb := 0xFF111827, bgArgb := 0xFFFFFFFF) {
        built := this._BuildQrGdipBitmap(payload, targetSize, 4, fgArgb, bgArgb)
        hBitmap := 0
        try {
            if (built.pBitmap)
                DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "Ptr", built.pBitmap, "Ptr*", &hBitmap, "UInt", bgArgb)
            return { hBitmap: hBitmap, qr: built.qr }
        } finally {
            if (built.pBitmap)
                DllCall("gdiplus\GdipDisposeImage", "Ptr", built.pBitmap)
        }
    }

    /**
     * Saves a crisp high-resolution (default 1024x1024) PNG QR image to outPath with
     * ISO 4-module quiet zone and strict GDI+ cleanup (C4).
     */
    static _SaveGdipBitmapAsPng(pBitmap, outPath, &errMsg := "") {
        errMsg := ""
        if (!pBitmap || Trim(String(outPath)) = "") {
            errMsg := "Invalid bitmap or output path"
            return false
        }
        clsid := Buffer(16, 0)
        hr := DllCall("ole32\CLSIDFromString", "WStr", "{557CF406-1A04-11D3-9A73-0000F81EF32E}", "Ptr", clsid, "Int")
        if (hr != 0) {
            errMsg := "PNG CLSID lookup failed"
            return false
        }
        try {
            if FileExist(outPath)
                FileDelete(outPath)
        }
        st := DllCall("gdiplus\GdipSaveImageToFile", "Ptr", pBitmap, "WStr", outPath, "Ptr", clsid, "Ptr", 0, "Int")
        if (st != 0 || !FileExist(outPath)) {
            errMsg := "GDI+ Save status " st
            return false
        }
        return true
    }

    static SavePng(payload, outPath, targetSize := 1024, fgArgb := 0xFF000000, bgArgb := 0xFFFFFFFF) {
        if (Trim(String(outPath)) = "")
            return { ok: false, error: "Empty output path" }
        built := this._BuildQrGdipBitmap(payload, targetSize, 4, fgArgb, bgArgb)
        if (!built.pBitmap)
            return { ok: false, error: "Failed to render QR bitmap" }
        try {
            svErr := ""
            ok := this._SaveGdipBitmapAsPng(built.pBitmap, outPath, &svErr)
            return {
                ok: ok,
                path: outPath,
                version: built.qr.version,
                size: built.qr.size,
                error: ok ? "" : svErr
            }
        } finally {
            DllCall("gdiplus\GdipDisposeImage", "Ptr", built.pBitmap)
        }
    }

    ; ==========================================================================
    ; PURE AHK v2 + GDI+ OFFLINE QR DECODER (#2C, Versions 1..14, L & M ECC)
    ; ==========================================================================

    static DecodeFromFile(filePath) {
        p := Trim(String(filePath))
        if (p = "" || !FileExist(p))
            return { ok: false, error: "QR image file not found" }
        Gdip.Startup()
        pBitmap := 0
        try {
            st := DllCall("gdiplus\GdipLoadImageFromFile", "WStr", p, "Ptr*", &pBitmap, "Int")
            if (st != 0 || !pBitmap)
                return { ok: false, error: "Could not decode image file (GDI+ status " st ")" }
            return this.DecodeFromBitmap(pBitmap)
        } finally {
            if (pBitmap)
                DllCall("gdiplus\GdipDisposeImage", "Ptr", pBitmap)
        }
    }

    static DecodeFromBitmap(pBitmap) {
        if (!pBitmap)
            return { ok: false, error: "Invalid bitmap pointer" }
        Gdip.Startup()
        imgW := 0, imgH := 0
        DllCall("gdiplus\GdipGetImageWidth", "Ptr", pBitmap, "UInt*", &imgW)
        DllCall("gdiplus\GdipGetImageHeight", "Ptr", pBitmap, "UInt*", &imgH)
        if (imgW < 21 || imgH < 21)
            return { ok: false, error: "Image too small for QR code" }

        step := (Max(imgW, imgH) > 360) ? Ceil(Max(imgW, imgH) / 360.0) : 1
        sw := Floor(imgW / step)
        sh := Floor(imgH / step)
        rect := Buffer(16, 0)
        NumPut("Int", 0, rect, 0), NumPut("Int", 0, rect, 4), NumPut("Int", imgW, rect, 8), NumPut("Int", imgH, rect, 12)
        bd := Buffer(A_PtrSize == 8 ? 32 : 24, 0)
        st := DllCall("gdiplus\GdipBitmapLockBits", "Ptr", pBitmap, "Ptr", rect, "UInt", 1, "Int", 0x26200A, "Ptr", bd, "Int")
        if (st != 0)
            return { ok: false, error: "Bitmap lock failed (" st ")" }

        gray := []
        minLum := 255, maxLum := 0
        try {
            stride := NumGet(bd, 8, "Int")
            scan0 := NumGet(bd, 16, "Ptr")
            totalPx := sw * sh
            gray.Capacity := totalPx
            Loop sh {
                sy := (A_Index - 1) * step
                rowPtr := scan0 + sy * stride
                Loop sw {
                    sx := (A_Index - 1) * step
                    px := NumGet(rowPtr + sx * 4, "UInt")
                    a := (px >> 24) & 0xFF
                    if (a < 16) {
                        lum := 255
                    } else {
                        r := (px >> 16) & 0xFF
                        g := (px >> 8) & 0xFF
                        b := px & 0xFF
                        lum := (299 * r + 587 * g + 114 * b) // 1000
                        if (a < 255)
                            lum := ((lum * a) + (255 * (255 - a))) // 255
                    }
                    if (lum < minLum)
                        minLum := lum
                    if (lum > maxLum)
                        maxLum := lum
                    gray.Push(lum)
                }
            }
        } finally {
            DllCall("gdiplus\GdipBitmapUnlockBits", "Ptr", pBitmap, "Ptr", bd)
        }

        ; Fast global threshold pass first (sub-second on crisp screenshots & saved PNGs)
        if (maxLum - minLum >= 20) {
            midT := (minLum + maxLum) // 2
            binG := []
            binGInv := []
            binG.Capacity := sw * sh
            binGInv.Capacity := sw * sh
            for _, lum in gray {
                d := (lum <= midT) ? 1 : 0
                binG.Push(d)
                binGInv.Push(d ^ 1)
            }
            res := this._DecodeBinaryGrid(binG, sw, sh)
            if (res.ok)
                return res
            res := this._DecodeBinaryGrid(binGInv, sw, sh)
            if (res.ok || (maxLum - minLum) >= 160)
                return res
        }

        ; Fallback: 2D integral image adaptive threshold for uneven lighting / photos
        integ := []
        integ.Length := (sw + 1) * (sh + 1)
        Loop (sw + 1) * (sh + 1)
            integ[A_Index] := 0
        rowW := sw + 1
        Loop sh {
            y := A_Index
            rowSum := 0
            gOff := (y - 1) * sw
            iCur := y * rowW
            iPrev := (y - 1) * rowW
            Loop sw {
                x := A_Index
                rowSum += gray[gOff + x]
                integ[iCur + x + 1] := integ[iPrev + x + 1] + rowSum
            }
        }

        rad := Max(8, Floor(Min(sw, sh) / 16))
        bin := []
        binInv := []
        bin.Capacity := sw * sh
        binInv.Capacity := sw * sh
        Loop sh {
            y := A_Index - 1
            y1 := Max(0, y - rad), y2 := Min(sh - 1, y + rad)
            y1Off := y1 * rowW, y2Off := (y2 + 1) * rowW
            gRowOff := y * sw
            Loop sw {
                x := A_Index - 1
                x1 := Max(0, x - rad), x2 := Min(sw - 1, x + rad)
                cnt := (x2 - x1 + 1) * (y2 - y1 + 1)
                sum := integ[y2Off + x2 + 2] - integ[y1Off + x2 + 2] - integ[y2Off + x1 + 1] + integ[y1Off + x1 + 1]
                lum := gray[gRowOff + x + 1]
                isDark := (lum * cnt < sum * 0.90 && lum < 210) ? 1 : 0
                bin.Push(isDark)
                binInv.Push(isDark ^ 1)
            }
        }

        res := this._DecodeBinaryGrid(bin, sw, sh)
        if (!res.ok)
            res := this._DecodeBinaryGrid(binInv, sw, sh)
        return res
    }

    static _CheckRatio5(c1, c2, c3, c4, c5) {
        tot := c1 + c2 + c3 + c4 + c5
        if (tot < 7)
            return false
        modSz := tot / 7.0
        var := modSz * 0.55
        return (Abs(c1 - modSz) < var)
            && (Abs(c2 - modSz) < var)
            && (Abs(c3 - 3.0 * modSz) < 3.0 * var)
            && (Abs(c4 - modSz) < var)
            && (Abs(c5 - modSz) < var)
    }

    static _VerifyFinderCross(bin, w, h, cx, cy, estMod) {
        maxSpan := Ceil(estMod * 5.0)
        ; Vertical run count around (cx, cy)
        yTop := cy, yBot := cy
        if (bin[cy * w + cx + 1] != 1)
            return false
        c3a := 0, r := cy
        while (r >= 0 && bin[r * w + cx + 1] = 1 && (cy - r) <= maxSpan)
            c3a++, r--
        if (r < 0)
            return false
        c2 := 0
        while (r >= 0 && bin[r * w + cx + 1] = 0 && (cy - r) <= maxSpan)
            c2++, r--
        if (r < 0)
            return false
        c1 := 0
        while (r >= 0 && bin[r * w + cx + 1] = 1 && (cy - r) <= maxSpan)
            c1++, r--
        c3b := 0, r := cy + 1
        while (r < h && bin[r * w + cx + 1] = 1 && (r - cy) <= maxSpan)
            c3b++, r++
        if (r >= h)
            return false
        c4 := 0
        while (r < h && bin[r * w + cx + 1] = 0 && (r - cy) <= maxSpan)
            c4++, r++
        if (r >= h)
            return false
        c5 := 0
        while (r < h && bin[r * w + cx + 1] = 1 && (r - cy) <= maxSpan)
            c5++, r++
        c3 := c3a + c3b
        if (!this._CheckRatio5(c1, c2, c3, c4, c5))
            return false
        vCenter := (cy - c3a + 1) + (c3 / 2.0) - 0.5
        vMod := (c1 + c2 + c3 + c4 + c5) / 7.0
        return { cy: vCenter, modSz: (estMod + vMod) / 2.0 }
    }

    static _DecodeBinaryGrid(bin, w, h) {
        centers := []
        yStep := Max(1, Floor(h / 260))
        y := 0
        while (y < h) {
            rowOff := y * w
            st := [0, 0, 0, 0, 0]
            curState := 0
            x := 0
            while (x < w) {
                pix := bin[rowOff + x + 1]
                if (pix = 1) {
                    if (curState & 1)
                        curState++
                    st[curState + 1]++
                } else {
                    if (!(curState & 1)) {
                        if (curState = 4) {
                            if (this._CheckRatio5(st[1], st[2], st[3], st[4], st[5])) {
                                tot := st[1] + st[2] + st[3] + st[4] + st[5]
                                cx := Floor(x - st[5] - st[4] - st[3] / 2.0)
                                estMod := tot / 7.0
                                if (vRes := this._VerifyFinderCross(bin, w, h, cx, y, estMod)) {
                                    cxExact := (x - st[5] - st[4] - st[3] / 2.0) - 0.5
                                    merged := false
                                    for _, existing in centers {
                                        if (Abs(existing.x - cxExact) < existing.mod * 4.0 && Abs(existing.y - vRes.cy) < existing.mod * 4.0) {
                                            n := existing.n + 1
                                            existing.x := (existing.x * existing.n + cxExact) / n
                                            existing.y := (existing.y * existing.n + vRes.cy) / n
                                            existing.mod := (existing.mod * existing.n + vRes.modSz) / n
                                            existing.n := n
                                            merged := true
                                            break
                                        }
                                    }
                                    if (!merged)
                                        centers.Push({ x: cxExact, y: vRes.cy, mod: vRes.modSz, n: 1 })
                                }
                            }
                            st[1] := st[3], st[2] := st[4], st[3] := st[5], st[4] := 1, st[5] := 0
                            curState := 3
                        } else {
                            curState++
                            st[curState + 1]++
                        }
                    } else {
                        st[curState + 1]++
                    }
                }
                x++
            }
            if (curState = 4 && this._CheckRatio5(st[1], st[2], st[3], st[4], st[5])) {
                tot := st[1] + st[2] + st[3] + st[4] + st[5]
                cx := Floor(w - st[5] - st[4] - st[3] / 2.0)
                if (vRes := this._VerifyFinderCross(bin, w, h, cx, y, tot / 7.0)) {
                    cxExact := (w - st[5] - st[4] - st[3] / 2.0) - 0.5
                    merged := false
                    for _, existing in centers {
                        if (Abs(existing.x - cxExact) < existing.mod * 4.0 && Abs(existing.y - vRes.cy) < existing.mod * 4.0) {
                            n := existing.n + 1
                            existing.x := (existing.x * existing.n + cxExact) / n
                            existing.y := (existing.y * existing.n + vRes.cy) / n
                            existing.mod := (existing.mod * existing.n + vRes.modSz) / n
                            existing.n := n
                            merged := true
                            break
                        }
                    }
                    if (!merged)
                        centers.Push({ x: cxExact, y: vRes.cy, mod: vRes.modSz, n: 1 })
                }
            }
            y += yStep
        }

        if (centers.Length < 3)
            return { ok: false, error: "Could not locate 3 QR finder patterns in image" }

        ; Pick best 3 finder patterns (highest hit counts, forming right triangle)
        Loop centers.Length {
            i := A_Index
            Loop centers.Length - i {
                j := i + A_Index
                if (centers[j].n > centers[i].n) {
                    tmp := centers[i], centers[i] := centers[j], centers[j] := tmp
                }
            }
        }

        candLimit := Min(centers.Length, 6)
        bestTri := ""
        bestErr := 1.0e9
        Loop candLimit {
            aIdx := A_Index
            bIdx := aIdx + 1
            while (bIdx <= candLimit) {
                cIdx := bIdx + 1
                while (cIdx <= candLimit) {
                    pA := centers[aIdx], pB := centers[bIdx], pC := centers[cIdx]
                    dAB := Sqrt((pB.x - pA.x)**2 + (pB.y - pA.y)**2)
                    dAC := Sqrt((pC.x - pA.x)**2 + (pC.y - pA.y)**2)
                    dBC := Sqrt((pC.x - pB.x)**2 + (pC.y - pB.y)**2)
                    if (dAB < 10 || dAC < 10 || dBC < 10) {
                        cIdx++
                        continue
                    }
                    ; Largest side = hypotenuse (TR..BL), opposite vertex = TL
                    if (dBC >= dAB && dBC >= dAC)
                        tl := pA, q1 := pB, q2 := pC, s1 := dAB, s2 := dAC
                    else if (dAC >= dAB && dAC >= dBC)
                        tl := pB, q1 := pA, q2 := pC, s1 := dAB, s2 := dBC
                    else
                        tl := pC, q1 := pA, q2 := pB, s1 := dAC, s2 := dBC

                    ratioDiff := Abs(s1 - s2) / Max(s1, s2)
                    dotCos := Abs(((q1.x - tl.x) * (q2.x - tl.x) + (q1.y - tl.y) * (q2.y - tl.y)) / (s1 * s2))
                    triErr := ratioDiff + dotCos
                    if (triErr < bestErr) {
                        bestErr := triErr
                        bestTri := { tl: tl, q1: q1, q2: q2 }
                    }
                    cIdx++
                }
                bIdx++
            }
        }
        if (!IsObject(bestTri) || bestErr > 0.45)
            return { ok: false, error: "QR finder geometry invalid" }

        tl := bestTri.tl, q1 := bestTri.q1, q2 := bestTri.q2
        ; Orientation via 2D cross product (screen Y grows downward: cross(TR-TL, BL-TL) > 0 => q1=TR, q2=BL)
        cross := (q1.x - tl.x) * (q2.y - tl.y) - (q1.y - tl.y) * (q2.x - tl.x)
        if (cross >= 0)
            tr := q1, bl := q2
        else
            tr := q2, bl := q1

        avgMod := (tl.mod + tr.mod + bl.mod) / 3.0
        span1 := Sqrt((tr.x - tl.x)**2 + (tr.y - tl.y)**2)
        span2 := Sqrt((bl.x - tl.x)**2 + (bl.y - tl.y)**2)
        estSize := Round(((span1 + span2) / 2.0) / avgMod) + 7
        ver := Round((estSize - 17) / 4.0)
        if (ver < 1)
            ver := 1
        if (ver > 14)
            return { ok: false, error: "QR Version " ver " exceeds supported decoder range (1..14)" }

        ; Try inferred version plus +/-1 in case module size estimation rounded slightly
        verCandidates := [ver]
        if (ver > 1)
            verCandidates.Push(ver - 1)
        if (ver < 14)
            verCandidates.Push(ver + 1)

        for _, vTry in verCandidates {
            sz := 4 * vTry + 17
            uX := (tr.x - tl.x) / (sz - 7.0)
            uY := (tr.y - tl.y) / (sz - 7.0)
            vX := (bl.x - tl.x) / (sz - 7.0)
            vY := (bl.y - tl.y) / (sz - 7.0)
            mat := []
            Loop sz {
                r := A_Index - 1
                rowArr := []
                Loop sz {
                    c := A_Index - 1
                    pxX := Round(tl.x + (c - 3.0) * uX + (r - 3.0) * vX)
                    pxY := Round(tl.y + (c - 3.0) * uY + (r - 3.0) * vY)
                    if (pxX < 0 || pxX >= w || pxY < 0 || pxY >= h)
                        rowArr.Push(0)
                    else
                        rowArr.Push(bin[pxY * w + pxX + 1])
                }
                mat.Push(rowArr)
            }
            dec := this._DecodeMatrix(mat, vTry, sz)
            if (dec.ok)
                return dec
        }
        return { ok: false, error: "Failed to decode QR bitstream or error correction failed" }
    }

    static _PopCount15(v) {
        c := 0
        x := v & 0x7FFF
        while (x) {
            c += x & 1
            x >>= 1
        }
        return c
    }

    static _DecodeFormatBits(fmtBits) {
        bestData := -1
        bestDist := 99
        Loop 32 {
            d := A_Index - 1
            rem := d
            Loop 10
                rem := (rem << 1) ^ (((rem >> 9) & 1) ? 0x537 : 0)
            valid := ((d << 10) | rem) ^ 0x5412
            dist := this._PopCount15(fmtBits ^ valid)
            if (dist < bestDist) {
                bestDist := dist
                bestData := d
            }
        }
        if (bestDist <= 3 && bestData >= 0) {
            return { ok: true, eccBits: (bestData >> 3) & 3, maskId: bestData & 7 }
        }
        return { ok: false }
    }

    static _DecodeMatrix(mat, ver, size) {
        ; Read 15 format bits around TL and redundant TR/BL (exact ISO 18004 LSB-first order matching _ApplyMaskAndFormat)
        fmt1 := 0
        Loop 6
            fmt1 |= (mat[A_Index][9] << (A_Index - 1))
        fmt1 |= (mat[8][9] << 6)
        fmt1 |= (mat[9][9] << 7)
        fmt1 |= (mat[9][8] << 8)
        Loop 6 {
            i := 8 + A_Index
            fmt1 |= (mat[9][15 - i] << i)
        }

        fmt2 := 0
        Loop 8 {
            i := A_Index - 1
            fmt2 |= (mat[9][size - i] << i)
        }
        Loop 7 {
            i := 7 + A_Index
            fmt2 |= (mat[size - 15 + i + 1][9] << i)
        }

        fInfo := this._DecodeFormatBits(fmt1)
        if (!fInfo.ok)
            fInfo := this._DecodeFormatBits(fmt2)
        if (!fInfo.ok)
            return { ok: false, error: "Invalid QR format info" }

        ; Map eccBits: 1=L, 0=M (ISO standard encoding)
        if (fInfo.eccBits = 1)
            spec := this._SPECS[ver]
        else if (fInfo.eccBits = 0)
            spec := this._SPECS_M[ver]
        else
            return { ok: false, error: "Unsupported ECC level in external QR" }

        ; Build exact same function mask map
        isFunc := []
        Loop size {
            fnArr := []
            Loop size
                fnArr.Push(false)
            isFunc.Push(fnArr)
        }
        MarkRect(r0, c0, hR, wC) {
            Loop hR {
                r := r0 + A_Index - 1
                if (r < 0 || r >= size)
                    continue
                Loop wC {
                    c := c0 + A_Index - 1
                    if (c >= 0 && c < size)
                        isFunc[r + 1][c + 1] := true
                }
            }
        }
        MarkRect(0, 0, 9, 9)
        MarkRect(0, size - 8, 9, 8)
        MarkRect(size - 8, 0, 8, 9)
        coords := this._ALIGN_COORDS[ver]
        for ar in coords {
            for ac in coords {
                if (!isFunc[ar + 1][ac + 1])
                    MarkRect(ar - 2, ac - 2, 5, 5)
            }
        }
        Loop size {
            idx := A_Index - 1
            isFunc[7][idx + 1] := true
            isFunc[idx + 1][7] := true
        }
        if (ver >= 7) {
            MarkRect(0, size - 11, 6, 3)
            MarkRect(size - 11, 0, 3, 6)
        }

        ; Zigzag read raw unmasked codewords
        totalBytes := spec[2] + (spec[4] + spec[6]) * spec[3]
        rawBytes := []
        curByte := 0, bitCnt := 0
        upward := true
        colRight := size - 1
        while (colRight > 0 && rawBytes.Length < totalBytes) {
            if (colRight = 6)
                colRight -= 1
            Loop size {
                rowStep := A_Index - 1
                r := upward ? (size - 1 - rowStep) : rowStep
                Loop 2 {
                    col := colRight - (A_Index - 1)
                    if (!isFunc[r + 1][col + 1]) {
                        bit := mat[r + 1][col + 1]
                        if (this._MaskBit(fInfo.maskId, r, col))
                            bit ^= 1
                        curByte := (curByte << 1) | bit
                        bitCnt++
                        if (bitCnt = 8) {
                            rawBytes.Push(curByte)
                            curByte := 0
                            bitCnt := 0
                            if (rawBytes.Length >= totalBytes)
                                break
                        }
                    }
                }
                if (rawBytes.Length >= totalBytes)
                    break
            }
            upward := !upward
            colRight -= 2
        }
        if (rawBytes.Length < totalBytes)
            return { ok: false, error: "Truncated QR codewords" }

        ; De-interleave & RS error-correct each block
        ecPerBlock := spec[3], g1Cnt := spec[4], g1Len := spec[5], g2Cnt := spec[6], g2Len := spec[7]
        totalBlocks := g1Cnt + g2Cnt
        blocksData := []
        blocksEc := []
        Loop totalBlocks {
            blocksData.Push([])
            blocksEc.Push([])
        }
        idx := 1
        maxDataLen := Max(g1Len, g2Len)
        Loop maxDataLen {
            colIdx := A_Index
            Loop totalBlocks {
                bIdx := A_Index
                bLen := (bIdx <= g1Cnt) ? g1Len : g2Len
                if (colIdx <= bLen) {
                    blocksData[bIdx].Push(rawBytes[idx])
                    idx++
                }
            }
        }
        Loop ecPerBlock {
            Loop totalBlocks {
                bIdx := A_Index
                blocksEc[bIdx].Push(rawBytes[idx])
                idx++
            }
        }

        dataStream := []
        this._InitGf()
        Loop totalBlocks {
            bIdx := A_Index
            cw := []
            for b in blocksData[bIdx]
                cw.Push(b)
            for b in blocksEc[bIdx]
                cw.Push(b)
            corrected := this._RsCorrectBlock(cw, ecPerBlock)
            if (!IsObject(corrected))
                return { ok: false, error: "QR Reed-Solomon ECC failed" }
            bDataLen := blocksData[bIdx].Length
            Loop bDataLen
                dataStream.Push(corrected[A_Index])
        }

        txt := this._ParseDataBits(dataStream, ver)
        if (!txt.ok)
            return txt
        return { ok: true, text: txt.text, version: ver, size: size, ecc: (fInfo.eccBits = 1 ? "L" : "M") }
    }

    static _GfInv(a) {
        if (a = 0)
            return 0
        return this._gfExp[255 - this._gfLog[a + 1] + 1]
    }

    static _RsCorrectBlock(codewords, ecLen) {
        n := codewords.Length
        ; Compute syndromes S_1..S_ecLen
        syn := []
        hasErr := false
        Loop ecLen {
            j := A_Index - 1
            s := 0
            for _, cw in codewords
                s := this._GfMul(s, this._gfExp[j + 1]) ^ cw
            syn.Push(s)
            if (s != 0)
                hasErr := true
        }
        if (!hasErr)
            return codewords

        ; Euclidean algorithm on GF(256) for Reed-Solomon error locator sigma and evaluator omega
        rLast := [], rCurr := []
        Loop ecLen + 1
            rLast.Push(0)
        rLast[ecLen + 1] := 1
        Loop ecLen
            rCurr.Push(syn[A_Index])
        tLast := [0], tCurr := [1]
        halfEc := ecLen // 2
        rsIter := 0
        while (this._PolyDeg(rCurr) >= halfEc && ++rsIter <= ecLen + 4) {
            rNext := []
            for _, v in rLast
                rNext.Push(v)
            q := []
            Loop rLast.Length
                q.Push(0)
            if (this._PolyDeg(rCurr) < 0)
                return ""
            denomLead := rCurr[this._PolyDeg(rCurr) + 1]
            denomInv := this._GfInv(denomLead)
            dCurr := this._PolyDeg(rCurr)
            innerIter := 0
            while (this._PolyDeg(rNext) >= dCurr && this._PolyDeg(rNext) >= 0 && ++innerIter <= 64) {
                dDiff := this._PolyDeg(rNext) - dCurr
                scale := this._GfMul(rNext[this._PolyDeg(rNext) + 1], denomInv)
                q[dDiff + 1] := q[dDiff + 1] ^ scale
                Loop dCurr + 1 {
                    idx := A_Index - 1
                    rNext[dDiff + idx + 1] := rNext[dDiff + idx + 1] ^ this._GfMul(rCurr[idx + 1], scale)
                }
            }
            ; tNext = q * tCurr + tLast
            maxT := Max(tLast.Length, q.Length + tCurr.Length)
            tNext := []
            Loop maxT
                tNext.Push(0)
            for qi, qv in q {
                if (qv = 0)
                    continue
                for ti, tv in tCurr
                    tNext[qi + ti - 1] := tNext[qi + ti - 1] ^ this._GfMul(qv, tv)
            }
            for li, lv in tLast
                tNext[li] := tNext[li] ^ lv
            rLast := rCurr, rCurr := rNext
            tLast := tCurr, tCurr := tNext
        }
        if (tCurr[1] = 0)
            return ""
        invSigma0 := this._GfInv(tCurr[1])
        sigma := [], omega := []
        for _, v in tCurr
            sigma.Push(this._GfMul(v, invSigma0))
        for _, v in rCurr
            omega.Push(this._GfMul(v, invSigma0))

        ; Chien search for roots X_k^-1 = alpha^i
        errLocs := []
        errExps := []
        Loop n {
            i := A_Index - 1
            xInv := this._gfExp[i + 1]
            eval := 0
            xPow := 1
            for _, sv in sigma {
                eval ^= this._GfMul(sv, xPow)
                xPow := this._GfMul(xPow, xInv)
            }
            if (eval = 0) {
                pos := n - i ; 1-based codeword index
                if (pos >= 1 && pos <= n) {
                    errLocs.Push(pos)
                    errExps.Push(xInv)
                }
            }
        }
        if (errLocs.Length != this._PolyDeg(sigma))
            return ""

        ; Forney error magnitudes
        out := []
        for _, v in codewords
            out.Push(v)
        for k, pos in errLocs {
            xInv := errExps[k]
            ; Evaluate omega(xInv)
            omVal := 0, xPow := 1
            for _, ov in omega {
                omVal ^= this._GfMul(ov, xPow)
                xPow := this._GfMul(xPow, xInv)
            }
            ; Formal derivative of sigma(x) = odd terms at xInv
            sigDeriv := 0, xPow := 1
            Loop sigma.Length {
                si := A_Index - 1
                if (si & 1) {
                    sigDeriv ^= this._GfMul(sigma[si + 1], xPow)
                    xPow := this._GfMul(xPow, this._GfMul(xInv, xInv))
                }
            }
            if (sigDeriv = 0)
                return ""
            ; Multiply by 1 (standard RS convention alpha^0=1 root start: e_i = X_k * omega(X_k^-1) / sigma'(X_k^-1) or omega/sigma')
            ; Because X_k = xInv^-1, magnitude = omega(xInv) / (xInv * sigDeriv) when FCR=0! Let's compute exact denominator (xInv * sigDeriv)
            mag := this._GfMul(omVal, this._GfInv(this._GfMul(xInv, sigDeriv)))
            out[pos] := out[pos] ^ mag
        }
        return out
    }

    static _PolyDeg(p) {
        i := p.Length
        while (i >= 1) {
            if (p[i] != 0)
                return i - 1
            i--
        }
        return -1
    }

    static _ParseDataBits(bytes, ver) {
        bits := []
        for _, b in bytes {
            Loop 8 {
                sh := 8 - A_Index
                bits.Push((b >> sh) & 1)
            }
        }
        pos := 1
        ReadBits(n) {
            if (pos + n - 1 > bits.Length)
                return -1
            v := 0
            Loop n {
                v := (v << 1) | bits[pos]
                pos++
            }
            return v
        }

        outStr := ""
        static alphaTable := "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:"
        while (pos + 3 <= bits.Length) {
            mode := ReadBits(4)
            if (mode <= 0)
                break
            if (mode = 4) { ; Byte (UTF-8)
                ccBits := (ver >= 10) ? 16 : 8
                cnt := ReadBits(ccBits)
                if (cnt < 0 || pos + cnt * 8 - 1 > bits.Length)
                    return { ok: false, error: "Invalid QR byte segment" }
                buf := Buffer(cnt + 1, 0)
                Loop cnt {
                    b := ReadBits(8)
                    NumPut("UChar", b, buf, A_Index - 1)
                }
                outStr .= StrGet(buf, cnt, "UTF-8")
            } else if (mode = 2) { ; Alphanumeric
                ccBits := (ver >= 10) ? 11 : 9
                cnt := ReadBits(ccBits)
                if (cnt < 0)
                    return { ok: false, error: "Invalid QR alpha segment" }
                while (cnt >= 2) {
                    v := ReadBits(11)
                    if (v < 0)
                        return { ok: false, error: "Truncated QR alpha pair" }
                    outStr .= SubStr(alphaTable, (v // 45) + 1, 1) . SubStr(alphaTable, Mod(v, 45) + 1, 1)
                    cnt -= 2
                }
                if (cnt = 1) {
                    v := ReadBits(6)
                    if (v < 0)
                        return { ok: false, error: "Truncated QR alpha char" }
                    outStr .= SubStr(alphaTable, v + 1, 1)
                }
            } else if (mode = 1) { ; Numeric
                ccBits := (ver >= 10) ? 12 : 10
                cnt := ReadBits(ccBits)
                if (cnt < 0)
                    return { ok: false, error: "Invalid QR numeric segment" }
                while (cnt >= 3) {
                    v := ReadBits(10)
                    if (v < 0)
                        return { ok: false, error: "Truncated QR numeric triplet" }
                    outStr .= Format("{:03}", v)
                    cnt -= 3
                }
                if (cnt = 2) {
                    v := ReadBits(7)
                    if (v < 0)
                        return { ok: false, error: "Truncated QR numeric pair" }
                    outStr .= Format("{:02}", v)
                } else if (cnt = 1) {
                    v := ReadBits(4)
                    if (v < 0)
                        return { ok: false, error: "Truncated QR numeric digit" }
                    outStr .= String(v)
                }
            } else {
                return { ok: false, error: "Unsupported QR mode " mode }
            }
        }
        return (outStr != "") ? { ok: true, text: outStr } : { ok: false, error: "Empty QR payload" }
    }
}
