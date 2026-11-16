; ==============================================================================
; Module: QrCode.ahk
; Description: Zero-dependency pure AutoHotkey v2 ISO/IEC 18004 QR Code encoder
;              (Byte mode, ECC Level L, Versions 1..11) + GDI+ HBITMAP renderer.
; ==============================================================================

class QrCode {
    static _gfInitialized := false
    static _gfExp := []
    static _gfLog := []

    ; ECC Level L specs indexed by Version 1..11:
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
        [11, 324, 20, 4, 81,  0,  0]
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
        [6, 30, 54]
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

    /**
     * Builds an HBITMAP of exact targetSize x targetSize pixels containing the QR code
     * with a 2-module crisp white quiet zone so camera scanners focus effortlessly.
     */
    static BuildHBitmap(payload, targetSize := 160, fgArgb := 0xFF111827, bgArgb := 0xFFFFFFFF) {
        Gdip.Startup()
        qr := this.EncodeMatrix(payload)
        modCount := qr.size
        quiet := 2
        totalMods := modCount + (quiet * 2)

        pBitmap := 0
        DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", targetSize, "Int", targetSize, "Int", 0, "Int", 0x26200A, "Ptr", 0, "Ptr*", &pBitmap)
        if (!pBitmap)
            return { hBitmap: 0, qr: qr }

        pGraphics := 0
        DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", pBitmap, "Ptr*", &pGraphics)
        if (pGraphics) {
            DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", pGraphics, "Int", 0)
            DllCall("gdiplus\GdipGraphicsClear", "Ptr", pGraphics, "UInt", bgArgb)

            cellPx := Floor(targetSize / totalMods)
            if (cellPx < 1)
                cellPx := 1
            drawSpan := cellPx * totalMods
            offsetPx := Floor((targetSize - drawSpan) / 2)

            pBrush := 0
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
                DllCall("gdiplus\GdipDeleteBrush", "Ptr", pBrush)
            }
            DllCall("gdiplus\GdipDeleteGraphics", "Ptr", pGraphics)
        }

        hBitmap := 0
        DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "Ptr", pBitmap, "Ptr*", &hBitmap, "UInt", bgArgb)
        DllCall("gdiplus\GdipDisposeImage", "Ptr", pBitmap)
        return { hBitmap: hBitmap, qr: qr }
    }
}
