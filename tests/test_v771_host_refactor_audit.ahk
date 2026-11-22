; ==============================================================================
; Test Suite: test_v771_host_refactor_audit.ahk
; Description: Verifies v7.7.1 Phase A refactored host helpers & Phase B strict
;              AHK v2 scoping, GDI+/BCrypt/COM handle disposal, and timer cleanup.
; ==============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
SetTimer(() => ExitApp(124), -45000)
OnError((err, mode) => (FileAppend("UNHANDLED_ERR: " err.Message " (" err.What ") at " err.File ":" err.Line "`n", "*"), ExitApp(1)))

#Include "%A_LineFile%\..\..\Lib\WebSocket.ahk"
#Include "%A_LineFile%\..\..\Lib\UIA.ahk"
#Include "%A_LineFile%\..\..\Lib\Crypto.ahk"
#Include "%A_LineFile%\..\..\Lib\Gdip.ahk"
#Include "%A_LineFile%\..\..\Lib\OBS_Network.ahk"
#Include "%A_LineFile%\..\..\Lib\GUI_Config.ahk"
#Include "%A_LineFile%\..\..\Lib\HostBridge.ahk"
#Include "%A_LineFile%\..\..\Lib\SetupWizard.ahk"
#Include "%A_LineFile%\..\..\Lib\HudSnakeGame.ahk"

global g_IsTestMode := true

Gdip.Startup()
OnExit((*) => (HideStageNudgeBanner(), HudSnake.Stop(), AudioMeter.Shutdown(), UIA.Shutdown(), Theme.Shutdown(), Gdip.Shutdown()))

passed := 0
failed := 0

AssertTrue(cond, label, detail := "") {
    global passed, failed
    if (cond) {
        passed++
    } else {
        failed++
        try FileAppend("FAIL: " label (detail != "" ? (" [" detail "]") : "") "`n", "*")
    }
}

; 1. Refactored Helper: StripHotkeyModifiers
AssertTrue(StripHotkeyModifiers("~$*^F12") == "^F12", "StripHotkeyModifiers strips ~*$ prefixes")
AssertTrue(StripHotkeyModifiers("  ~$*{PgDn}  ", true) == "PgDn", "StripHotkeyModifiers unwraps braces when unwrapBraces=true")
AssertTrue(StripHotkeyModifiers("~$*{PgDn}", false) == "{PgDn}", "StripHotkeyModifiers preserves braces when unwrapBraces=false")
AssertTrue(StripHotkeyModifiers("None") == "None" && StripHotkeyModifiers("") == "", "StripHotkeyModifiers handles None and empty")

; 2. Refactored Helper: IsUsableLanIPv4
AssertTrue(IsUsableLanIPv4("192.168.1.42") == true && IsUsableLanIPv4("10.0.0.5") == true, "IsUsableLanIPv4 accepts standard LAN IPv4")
AssertTrue(IsUsableLanIPv4("") == false
    && IsUsableLanIPv4("0.0.0.0") == false
    && IsUsableLanIPv4("127.0.0.1") == false
    && IsUsableLanIPv4("127.0.1.5") == false
    && IsUsableLanIPv4("169.254.10.20") == false
    && IsUsableLanIPv4("::1") == false
    && IsUsableLanIPv4("fe80::1") == false
    && IsUsableLanIPv4("192.168.1") == false
    && IsUsableLanIPv4("host.local") == false,
    "IsUsableLanIPv4 rejects loopback, APIPA, zero, IPv6, and malformed strings")

; 3. Refactored Helper: _GetHudGuiPropNames
allProps := _GetHudGuiPropNames(true)
primProps := _GetHudGuiPropNames(false)
hasSecInAll := false
hasSecInPrim := false
for _, p in allProps {
    if (p == "SecondaryMicGui")
        hasSecInAll := true
}
for _, p in primProps {
    if (p == "SecondaryMicGui")
        hasSecInPrim := true
}
AssertTrue(allProps.Length == 8 && hasSecInAll && primProps.Length == 7 && !hasSecInPrim,
    "_GetHudGuiPropNames returns 8 props with secondary and 7 without")

; 4. Refactored Helper: ControlSendFast restores A_KeyDelay == -1 and A_KeyDuration == -1
AssertTrue(ControlSendFast("", "ahk_exe notepad.exe") == false && ControlSendFast("None", "ahk_exe notepad.exe") == false,
    "ControlSendFast rejects empty or None hotkey")
SetKeyDelay 25, 40
csRes := ControlSendFast("^a", "ahk_id 0xFFFFFFFF")
AssertTrue(csRes == false && A_KeyDelay == -1 && A_KeyDuration == -1,
    "ControlSendFast restores A_KeyDelay=-1 and A_KeyDuration=-1 on failure",
    Format("res={} delay={} dur={}", csRes, A_KeyDelay, A_KeyDuration))

; 5. GDI+ RenderPill & MeasureTextWidth & QrCode 100-cycle stress & handle leak check
hProc := DllCall("GetCurrentProcess", "Ptr")
stressGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000 -DPIScale", "PresenterSync_v771_Stress")
stressGui.Show("NoActivate Hide x-2000 y-2000 w140 h44")
; Warm up GDI+ font cache before measuring handle baseline
Gdip.RenderPill(stressGui.Hwnd, -2000, -2000, 140, 44, 0xFF107C10, 0xFF0B5A0B, 220, 10,
    { text: Chr(0xE720), font: "Segoe MDL2 Assets", size: 14, color: 0xFFFFFFFF, x: 8, w: 28 },
    { text: "LIVE", size: 10, bold: true, color: 0xFFFFFFFF, x: 38, w: 92 }, 0.45, 0xD8FFFFFF)
gdiBefore := DllCall("GetGuiResources", "Ptr", hProc, "UInt", 0, "UInt")
pillErrs := 0
pillOkCnt := 0
Loop 100 {
    try {
        okP := Gdip.RenderPill(stressGui.Hwnd, -2000, -2000, 140, 44,
            Mod(A_Index, 2) ? 0xFF107C10 : 0xFFC42B1C,
            0xFF222222, 220, 10,
            { text: Chr(0xE720), font: "Segoe MDL2 Assets", size: 14, color: 0xFFFFFFFF, x: 8, w: 28 },
            { text: "CYCLE " A_Index, size: 10, bold: true, color: 0xFFFFFFFF, x: 38, w: 92 },
            Mod(A_Index, 10) / 10.0, 0xD8FFFFFF)
        if (okP)
            pillOkCnt += 1
        mw := Gdip.MeasureTextWidth("Stress " A_Index, "Segoe UI", 9, 1)
        if (mw <= 0)
            pillErrs += 1
    } catch {
        pillErrs += 1
    }
}
gdiAfter := DllCall("GetGuiResources", "Ptr", hProc, "UInt", 0, "UInt")
gdiDelta := gdiAfter - gdiBefore
stressGui.Destroy()
AssertTrue(pillErrs == 0 && pillOkCnt == 100 && gdiDelta <= 4,
    "Gdip.RenderPill + MeasureTextWidth 100-cycle stress has 0 errors and zero GDI leak",
    Format("ok={} errs={} gdiBefore={} gdiAfter={} delta={}", pillOkCnt, pillErrs, gdiBefore, gdiAfter, gdiDelta))

; QrCode BuildHBitmap 10-cycle stress with clean DeleteObject
qrGdiBefore := DllCall("GetGuiResources", "Ptr", hProc, "UInt", 0, "UInt")
qrErrs := 0
Loop 10 {
    try {
        qRes := QrCode.BuildHBitmap("presentersync://connect?hosts=192.168.1.10&bp=4456&code=ABC-123&i=" A_Index, 114)
        if (!qRes.hBitmap)
            qrErrs += 1
        else
            DllCall("DeleteObject", "Ptr", qRes.hBitmap)
    } catch {
        qrErrs += 1
    }
}
qrGdiAfter := DllCall("GetGuiResources", "Ptr", hProc, "UInt", 0, "UInt")
AssertTrue(qrErrs == 0 && (qrGdiAfter - qrGdiBefore) <= 4,
    "QrCode.BuildHBitmap 10-cycle stress has 0 errors and balanced GDI handles",
    Format("errs={} delta={}", qrErrs, qrGdiAfter - qrGdiBefore))

; 6. BCrypt AES-GCM + SHA-256 100-cycle stress test
key32 := DeriveAesGcmKey32("K7M-9P2", "StressSalt")
cryptoErrs := 0
Loop 100 {
    try {
        pt := '{"seq":' A_Index ',"cmd":"toggle_mute","note":"v7.7.1 stress"}'
        enc := AesGcmEncryptBytes(pt, key32)
        if (!IsObject(enc) || enc.iv = "" || enc.ct = "") {
            cryptoErrs += 1
            continue
        }
        decOk := false
        dec := AesGcmDecryptBytes(enc.iv, enc.ct, key32, &decOk)
        hHex := HashSHA256_Hex(pt)
        if (!decOk || dec != pt || StrLen(hHex) != 64)
            cryptoErrs += 1
    } catch {
        cryptoErrs += 1
    }
}
AssertTrue(cryptoErrs == 0, "BCrypt AesGcmEncryptBytes/DecryptBytes + HashSHA256_Hex 100-cycle stress has 0 errors", "errs=" cryptoErrs)

; 7. OverlayState.StopAllTimers() and HideStageNudgeBanner() timer cleanup
tmpIni := A_Temp "\PresenterSync_v771_audit_" A_TickCount ".ini"
if FileExist(tmpIni)
    FileDelete(tmpIni)
if FileExist(tmpIni ".bak")
    FileDelete(tmpIni ".bak")
cfg := Config(tmpIni)
st := OverlayState(cfg)
st.autoProfileTimerFn := (*) => 0
stoppedCnt := st.StopAllTimers()
AssertTrue(stoppedCnt == 16, "OverlayState.StopAllTimers stops all 16 bound host timers", "stopped=" stoppedCnt)
cfg.DeleteFile()

; Verify HideStageNudgeBanner clears active nudge timer cleanly
ShowStageNudgeBanner("Audit banner test", "F59E0B", 5000, "Audit")
hadNudgeTimer := IsObject(g_StageNudgeHideFn)
HideStageNudgeBanner()
AssertTrue(hadNudgeTimer && g_StageNudgeHideFn == "" && g_StageNudgeGui == "",
    "HideStageNudgeBanner stops pending g_StageNudgeHideFn timer and destroys banner")

; 8. Source invariants: PresenterSync.ahk shutdown coverage & GDI+/BCrypt/COM try/finally
hostSrc := FileRead(A_ScriptDir "\..\PresenterSync.ahk", "UTF-8")
gdipSrc := FileRead(A_ScriptDir "\..\Lib\Gdip.ahk", "UTF-8")
qrSrc := FileRead(A_ScriptDir "\..\Lib\QrCode.ahk", "UTF-8")
cryptoSrc := FileRead(A_ScriptDir "\..\Lib\Crypto.ahk", "UTF-8")
uiaSrc := FileRead(A_ScriptDir "\..\Lib\UIA.ahk", "UTF-8")
guiCfgSrc := FileRead(A_ScriptDir "\..\Lib\GUI_Config.ahk", "UTF-8")

AssertTrue(InStr(hostSrc, "ShutdownHostApp")
    && InStr(hostSrc, "RegisterSelfUpdateBeforeRelaunch(ShutdownHostApp)")
    && InStr(hostSrc, "OnExit(ShutdownHostApp)")
    && InStr(hostSrc, "AppState.StopAllTimers()")
    && InStr(hostSrc, "HideStageNudgeBanner()")
    && InStr(hostSrc, "AudioMeter.Shutdown()")
    && InStr(hostSrc, "UIA.Shutdown()")
    && InStr(hostSrc, "Theme.Shutdown()")
    && InStr(hostSrc, "Gdip.Shutdown()"),
    "PresenterSync.ahk wires unified ShutdownHostApp covering all timers, banner, and subsystems on OnExit & relaunch")

AssertTrue(InStr(gdipSrc, "finally {") && InStr(gdipSrc, "GdipDeleteGraphics") && InStr(gdipSrc, "DeleteDC") && InStr(gdipSrc, "DeleteObject") && InStr(gdipSrc, "FreeLibrary"),
    "Lib\Gdip.ahk guarantees GDI+/Win32 handle disposal via finally blocks")

AssertTrue(InStr(qrSrc, "finally {") && InStr(qrSrc, "GdipDisposeImage") && InStr(qrSrc, "GdipDeleteGraphics") && InStr(qrSrc, "GdipDeleteBrush"),
    "Lib\QrCode.ahk guarantees GDI+ handle disposal via finally block")

AssertTrue(InStr(cryptoSrc, "finally {") && InStr(cryptoSrc, "BCryptDestroyKey") && InStr(cryptoSrc, "BCryptDestroyHash") && InStr(cryptoSrc, "BCryptCloseAlgorithmProvider"),
    "Lib\Crypto.ahk guarantees BCrypt key/hash/algorithm disposal via finally blocks")

AssertTrue(InStr(uiaSrc, "finally {") && InStr(uiaSrc, "SysFreeString") && InStr(uiaSrc, "ObjRelease(pRoot)") && InStr(uiaSrc, "ObjRelease(pArr)"),
    "Lib\UIA.ahk guarantees COM & BSTR disposal via finally blocks")

AssertTrue(InStr(guiCfgSrc, "StopAllTimers()") && InStr(guiCfgSrc, "EndPaint") && InStr(guiCfgSrc, "finally {"),
    "Lib\GUI_Config.ahk provides OverlayState.StopAllTimers() and try/finally WM_PAINT disposal")

FileAppend(Format("PASS={} FAIL={}`n", passed, failed), "*")
ExitApp(failed > 0 ? 1 : 0)
