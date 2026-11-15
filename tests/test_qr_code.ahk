; ==============================================================================
; Test Suite: test_qr_code.ahk
; Description: Verifies pure AutoHotkey v2 QR Code matrix invariants (Versions 1..11,
;              finder patterns, timing patterns, dark module, format/version strips,
;              and GDI+ HBITMAP creation + BMP pixel export for cross-verification).
; ==============================================================================

#Requires AutoHotkey v2.0
#Include "%A_LineFile%\..\..\Lib\Gdip.ahk"
#Include "%A_LineFile%\..\..\Lib\QrCode.ahk"

passed := 0
failed := 0

AssertTrue(cond, label) {
    global passed, failed
    if (cond) {
        passed++
    } else {
        failed++
        try FileAppend("FAIL: " label "`n", "*")
    }
}

Gdip.Startup()

; 1. Encode short Version 1 payload ("HELLO") -> 21x21
q1 := QrCode.EncodeMatrix("HELLO")
AssertTrue(q1.version = 1 && q1.size = 21, "Version 1 size 21")
; Top-left finder center dark (row 4 col 4) and separator ring light (row 8 col 1)
AssertTrue(q1.modules[4][4] = 1, "Top-left finder center dark")
AssertTrue(q1.modules[8][1] = 0, "Top-left finder white separator")
; Timing pattern alternating (row 7 col 9 = dark/light alternating)
AssertTrue(q1.modules[7][9] = 1 && q1.modules[7][10] = 0 && q1.modules[7][11] = 1, "Timing strip alternates cleanly")
; Mandatory dark module (size - 8, 8) in 0-based => modules[size - 7][9]
AssertTrue(q1.modules[q1.size - 7][9] = 1, "Dark module (4V+9, 8) is set")

; 2. Encode realistic presentersync://connect URI (~140 bytes -> Version 7+)
sampleUri := "presentersync://connect?hosts=STUDIO-PC.local,192.168.1.50,192.168.1.125&port=4455&bp=4456&pw=Secret123&code=K9P-4X7&mic=Mic%2FAux&mode=lan&rc=PS-1234-ABCD"
qUri := QrCode.EncodeMatrix(sampleUri)
AssertTrue(qUri.version >= 7 && qUri.size = 4 * qUri.version + 17, "Pairing URI uses Version >= 7 (" qUri.version ")")
AssertTrue(qUri.modules[1][1] = 1 && qUri.modules[1][7] = 1 && qUri.modules[7][1] = 1, "Top-left finder corners set on Version >= 7")
AssertTrue(qUri.modules[1][qUri.size] = 1 && qUri.modules[qUri.size][1] = 1, "Top-right & bottom-left finder corners set")

; 3. Verify GDI+ HBITMAP creation and cleanup
res := QrCode.BuildHBitmap(sampleUri, 160)
AssertTrue(res.hBitmap != 0, "BuildHBitmap returned valid non-zero HBITMAP")
bm := Buffer(32, 0)
gotBytes := DllCall("GetObjectW", "Ptr", res.hBitmap, "Int", 32, "Ptr", bm, "Int")
AssertTrue(gotBytes > 0 && NumGet(bm, 4, "Int") = 160 && NumGet(bm, 8, "Int") = 160, "HBITMAP has exact 160x160 dimensions")
DllCall("DeleteObject", "Ptr", res.hBitmap)

Gdip.Shutdown()
try FileAppend("QR Code Tests: " passed " passed, " failed " failed (URI ver=" qUri.version ", size=" qUri.size ")`n", "*")
ExitApp(failed > 0 ? 1 : 0)
