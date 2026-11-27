; ==============================================================================
; Test Suite: test_v1020_qr_crossnet_codec.ahk
; Description: M6B Tier 2 verification for #2A/#2B/#2C:
;   - Compact zero-obsPassword BuildHostPairingUri (C3, mode, rc, relay, rpw=1)
;   - ISO quiet-zone 4 QrCode.SavePng (1024x1024)
;   - Pure AHK v2 + GDI+ offline QrCode.DecodeFromFile round-trips (0, 90, 180 deg)
;   - Non-QR graceful failure + ParsePairingUri across all 5 payload formats
; ==============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Off
SetWorkingDir A_ScriptDir "\.."

#Include ..\Lib\WebSocket.ahk
#Include ..\Lib\UIA.ahk
#Include ..\Lib\Crypto.ahk
#Include ..\Lib\JsonCodec.ahk
#Include ..\Lib\RemoteBridgeClient.ahk
#Include ..\Lib\Gdip.ahk
#Include ..\Lib\QrCode.ahk
#Include ..\Lib\OBS_Network.ahk
#Include ..\Lib\GUI_Config.ahk
#Include ..\Lib\HostBridge.ahk

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

AssertEq(actual, expected, label) {
    global passed, failed
    if (actual = expected) {
        passed++
    } else {
        failed++
        try FileAppend("FAIL: " label " (expected='" String(expected) "', actual='" String(actual) "')`n", "*")
    }
}

RotatePngFile(srcPath, dstPath, rotateFlipEnum) {
    pBmp := 0
    if (DllCall("gdiplus\GdipCreateBitmapFromFile", "WStr", srcPath, "Ptr*", &pBmp) != 0 || !pBmp)
        return false
    try {
        DllCall("gdiplus\GdipImageRotateFlip", "Ptr", pBmp, "Int", rotateFlipEnum)
        return QrCode._SaveGdipBitmapAsPng(pBmp, dstPath)
    } finally {
        DllCall("gdiplus\GdipDisposeImage", "Ptr", pBmp)
    }
}

CheckPngDimensions(pngPath, &outW, &outH) {
    outW := 0, outH := 0
    pBmp := 0
    if (DllCall("gdiplus\GdipCreateBitmapFromFile", "WStr", pngPath, "Ptr*", &pBmp) != 0 || !pBmp)
        return false
    try {
        DllCall("gdiplus\GdipGetImageWidth", "Ptr", pBmp, "UInt*", &outW)
        DllCall("gdiplus\GdipGetImageHeight", "Ptr", pBmp, "UInt*", &outH)
        return true
    } finally {
        DllCall("gdiplus\GdipDisposeImage", "Ptr", pBmp)
    }
}

Gdip.Startup()

tmpDir := A_Temp "\ps_v1020_qr_test_" A_TickCount
DirCreate(tmpDir)

try {
    ; 1. BuildHostPairingUri compact + WAN + zero obsPassword (C3)
    cfg := {
        RemoteNetworkMode: "Internet",
        ObsPort: 4455,
        ObsPassword: "SuperSecretObsPassword!99",
        BridgePort: 4456,
        SessionPairingCode: "K9P-4X7",
        InternetPairingCode: "PS-12AB-34CD",
        RelayBaseUrl: "https://relay.example.org",
        TargetMicName: "Mic/Aux",
        ActivePalette: "Cyan"
    }
    uri := BuildHostPairingUri(cfg, ["192.168.1.50", "172.25.0.1", "10.0.0.8"], 4456)
    AssertTrue(!InStr(uri, "SuperSecretObsPassword"), "C3: obsPassword never embedded in pairing URI")
    AssertTrue(!InStr(uri, "&pw=") && !InStr(uri, "?pw="), "C3: pw= key omitted from pairing URI")
    AssertTrue(InStr(uri, "mode=internet") > 0, "WAN mode included")
    AssertTrue(InStr(uri, "rc=PS-12AB-34CD") > 0, "WAN pairing code rc= included")
    AssertTrue(InStr(uri, "rpw=1") > 0, "Non-secret rpw=1 flag set when Host password configured")
    AssertTrue(InStr(uri, "relay=") > 0, "Custom RelayBaseUrl included")
    AssertTrue(!InStr(uri, "port=4455"), "Default OBS port omitted for compact QR density")
    AssertTrue(!InStr(uri, "bp=4456"), "Default Bridge port omitted for compact QR density")
    AssertTrue(!InStr(uri, "mic="), "Default Mic/Aux omitted for compact QR density")

    cfgNoPw := { RemoteNetworkMode: "LAN", ObsPort: 4455, ObsPassword: "", BridgePort: 4456, SessionPairingCode: "AAA-BBB", InternetPairingCode: "", RelayBaseUrl: "https://ntfy.sh", TargetMicName: "Mic/Aux" }
    uriNoPw := BuildHostPairingUri(cfgNoPw, ["192.168.1.50"], 4456)
    AssertTrue(!InStr(uriNoPw, "rpw=1"), "rpw=1 omitted when Host OBS password blank")
    AssertTrue(!InStr(uriNoPw, "relay="), "Default ntfy.sh relay omitted")

    ; 2. ISO quiet-4 1024x1024 SavePng & Offline DecodeFromFile round-trip (LAN + WAN URI)
    pngWan := tmpDir "\wan_qr.png"
    sv1 := QrCode.SavePng(uri, pngWan, 1024)
    AssertTrue(sv1.ok && FileExist(pngWan), "SavePng created 1024x1024 PNG")
    w := 0, h := 0
    AssertTrue(CheckPngDimensions(pngWan, &w, &h) && w = 1024 && h = 1024, "Saved PNG has exact 1024x1024 pixels")

    dec1 := QrCode.DecodeFromFile(pngWan)
    AssertTrue(dec1.ok, "DecodeFromFile succeeds on compact WAN URI (" (dec1.HasOwnProp("error") ? dec1.error : "") ")")
    AssertEq(dec1.text, uri, "DecodeFromFile exact round-trip on WAN URI")

    ; 3. Rotated PNG tests (90 deg CW = 1, 180 deg = 2)
    png90 := tmpDir "\wan_qr_90.png"
    AssertTrue(RotatePngFile(pngWan, png90, 1), "Created 90-deg rotated PNG")
    dec90 := QrCode.DecodeFromFile(png90)
    AssertTrue(dec90.ok && dec90.text = uri, "DecodeFromFile succeeds on 90-deg rotated QR PNG")

    png180 := tmpDir "\wan_qr_180.png"
    AssertTrue(RotatePngFile(pngWan, png180, 2), "Created 180-deg rotated PNG")
    dec180 := QrCode.DecodeFromFile(png180)
    AssertTrue(dec180.ok && dec180.text = uri, "DecodeFromFile succeeds on 180-deg rotated QR PNG")

    ; 4. Web Remote HTTP URL + Bare PS code QR round-trips
    httpUrl := "http://192.168.1.50:4456/?code=K9P-4X7&rc=PS-12AB-34CD&mode=internet&rpw=1"
    pngHttp := tmpDir "\http_qr.png"
    AssertTrue(QrCode.SavePng(httpUrl, pngHttp, 640).ok, "Saved HTTP pairing URL QR")
    decHttp := QrCode.DecodeFromFile(pngHttp)
    AssertTrue(decHttp.ok && decHttp.text = httpUrl, "DecodeFromFile round-trips HTTP Web Remote URL")

    bareWan := "PS-8899-WXYZ"
    pngBare := tmpDir "\bare_wan.png"
    AssertTrue(QrCode.SavePng(bareWan, pngBare, 512).ok, "Saved bare PS-XXXX-XXXX QR")
    decBare := QrCode.DecodeFromFile(pngBare)
    AssertTrue(decBare.ok && decBare.text = bareWan, "DecodeFromFile round-trips Version 1 bare WAN code")

    ; 5. Non-QR blank bitmap graceful failure
    blankPng := tmpDir "\blank.png"
    pBlank := 0, pBlankG := 0
    DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", 256, "Int", 256, "Int", 0, "Int", 0x26200A, "Ptr", 0, "Ptr*", &pBlank)
    if (pBlank) {
        DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", pBlank, "Ptr*", &pBlankG)
        if (pBlankG) {
            DllCall("gdiplus\GdipGraphicsClear", "Ptr", pBlankG, "UInt", 0xFFFFFFFF)
            DllCall("gdiplus\GdipDeleteGraphics", "Ptr", pBlankG)
        }
        QrCode._SaveGdipBitmapAsPng(pBlank, blankPng)
        DllCall("gdiplus\GdipDisposeImage", "Ptr", pBlank)
    }
    decBlank := QrCode.DecodeFromFile(blankPng)
    AssertTrue(!decBlank.ok, "Blank non-QR PNG fails gracefully without exception")

    ; 6. ParsePairingUri universal format validation
    pWan := ParsePairingUri(dec1.text)
    AssertTrue(pWan.ok, "ParsePairingUri accepts WAN URI")
    AssertEq(pWan.mode, "internet", "ParsePairingUri extracts mode=internet")
    AssertEq(pWan.wanCode, "PS-12AB-34CD", "ParsePairingUri extracts wanCode")
    AssertEq(pWan.relayBaseUrl, "https://relay.example.org", "ParsePairingUri extracts relayBaseUrl")
    AssertTrue(pWan.requiresRelayPassword = true, "ParsePairingUri extracts requiresRelayPassword=true")

    pHttp := ParsePairingUri(decHttp.text)
    AssertTrue(pHttp.ok && pHttp.host = "192.168.1.50" && pHttp.code = "K9P-4X7" && pHttp.wanCode = "PS-12AB-34CD" && pHttp.mode = "internet" && pHttp.requiresRelayPassword, "ParsePairingUri parses HTTP URL with WAN + rpw")

    pJson := ParsePairingUri('{"hosts":"10.1.2.3","port":4455,"bp":4456,"code":"XYZ-123","mode":"internet","rc":"PS-0011-2233","relay":"https://r.test","rpw":1}')
    AssertTrue(pJson.ok && pJson.host = "10.1.2.3" && pJson.mode = "internet" && pJson.wanCode = "PS-0011-2233" && pJson.relayBaseUrl = "https://r.test" && pJson.requiresRelayPassword, "ParsePairingUri parses JSON with WAN + relay + rpw")

    pBare := ParsePairingUri("ps-1122-ab34")
    AssertTrue(pBare.ok && pBare.wanCode = "PS-1122-AB34" && pBare.mode = "internet", "ParsePairingUri normalizes bare PS code")

    pBad := ParsePairingUri("https://example.com/not-presentersync")
    AssertTrue(!pBad.ok, "ParsePairingUri rejects unrelated HTTPS URLs")
} finally {
    try DirDelete(tmpDir, true)
    Gdip.Shutdown()
}

try FileAppend("PASS=" passed " FAIL=" failed "`n", "*")
ExitApp (failed > 0 ? 1 : 0)
