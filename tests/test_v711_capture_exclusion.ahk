; ==============================================================================
; Test Suite: test_v711_capture_exclusion.ahk
; Description: Verifies v7.1.1 Screen Share & Video Capture Exclusion:
;              ExcludeFromCapture & ExcludeSecondaryFromCapture Config/Profile
;              persistence, ApplyWindowCaptureAffinity + GetWindowDisplayAffinity,
;              ApplyControlCenterSettings updates, and SecondaryMicGui independence.
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

global g_IsTestMode := true

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

GetWinAffinity(hwnd) {
    aff := 0
    ok := DllCall("user32\GetWindowDisplayAffinity", "Ptr", hwnd, "UInt*", &aff, "Int")
    return { ok: !!ok, aff: aff }
}

; 1. Config & GetProfileFieldSpecs() persistence
tmpIni := A_Temp "\PresenterSync_v711_test_" A_TickCount ".ini"
if FileExist(tmpIni)
    FileDelete(tmpIni)

cfg := Config(tmpIni)
AssertTrue(cfg.ExcludeFromCapture == true, "ExcludeFromCapture defaults to true")
AssertTrue(cfg.ExcludeSecondaryFromCapture == true, "ExcludeSecondaryFromCapture defaults to true")

cfg.ExcludeFromCapture := false
cfg.ExcludeSecondaryFromCapture := true
cfg.WriteBool("Settings", "ExcludeFromCapture", false)
cfg.WriteBool("Settings", "ExcludeSecondaryFromCapture", true)

cfgReloaded := Config(tmpIni)
AssertTrue(cfgReloaded.ExcludeFromCapture == false, "Config persists ExcludeFromCapture=false")
AssertTrue(cfgReloaded.ExcludeSecondaryFromCapture == true, "Config persists ExcludeSecondaryFromCapture=true")

specs := cfg.GetProfileFieldSpecs()
specKeys := Map()
for _, sp in specs
    specKeys[sp.prop] := true
AssertTrue(specKeys.Has("ExcludeFromCapture"), "GetProfileFieldSpecs includes ExcludeFromCapture")
AssertTrue(specKeys.Has("ExcludeSecondaryFromCapture"), "GetProfileFieldSpecs includes ExcludeSecondaryFromCapture")

; 2. ApplyWindowCaptureAffinity(testGui.Hwnd, true/false) + GetWindowDisplayAffinity verification
testGui := Gui("+AlwaysOnTop -Caption +ToolWindow", "CaptureAffinityTest")
testGui.Show("x-32000 y-32000 w100 h40 NoActivate")

okExcl := ApplyWindowCaptureAffinity(testGui.Hwnd, true)
affOn := GetWinAffinity(testGui.Hwnd)
AssertTrue(okExcl == true, "ApplyWindowCaptureAffinity(true) returns true")
AssertTrue(affOn.ok && affOn.aff == 0x11, "GetWindowDisplayAffinity reports WDA_EXCLUDEFROMCAPTURE (0x11)")

okIncl := ApplyWindowCaptureAffinity(testGui.Hwnd, false)
affOff := GetWinAffinity(testGui.Hwnd)
AssertTrue(okIncl == true, "ApplyWindowCaptureAffinity(false) returns true")
AssertTrue(affOff.ok && affOff.aff == 0x00, "GetWindowDisplayAffinity reports WDA_NONE (0x00)")
testGui.Destroy()

; 3. ApplyControlCenterSettings updates & SecondaryMicGui independent exclusion
cfg.ExcludeFromCapture := true
cfg.ExcludeSecondaryFromCapture := true
st := OverlayState(cfg)
InitHUD(cfg, st, false)

affPrimInit := GetWinAffinity(st.MicGui.Hwnd)
affSecInit := GetWinAffinity(st.SecondaryMicGui.Hwnd)
AssertTrue(affPrimInit.ok && affPrimInit.aff == 0x11, "InitHUD excludes Primary MicGui (0x11)")
AssertTrue(affSecInit.ok && affSecInit.aff == 0x11, "InitHUD excludes SecondaryMicGui (0x11)")

okCC := ApplyControlCenterSettings(cfg, st, {
    ExcludeFromCapture: false,
    ExcludeSecondaryFromCapture: true
}, false)
AssertTrue(okCC == true && cfg.ExcludeFromCapture == false && cfg.ExcludeSecondaryFromCapture == true, "ApplyControlCenterSettings updates both capture exclusion flags")

affPrimAfter := GetWinAffinity(st.MicGui.Hwnd)
affSecAfter := GetWinAffinity(st.SecondaryMicGui.Hwnd)
AssertTrue(affPrimAfter.ok && affPrimAfter.aff == 0x00, "Primary MicGui capture exclusion disabled (0x00)")
AssertTrue(affSecAfter.ok && affSecAfter.aff == 0x11, "SecondaryMicGui remains independently excluded (0x11)")

for _, k in ["MicGui", "SecondaryMicGui", "RecGui", "ChatGui", "StudioGui", "SceneGui", "StreamGui", "VCamGui"] {
    if (st.HasOwnProp(k) && IsObject(st.%k%))
        try st.%k%.Destroy()
}

try FileDelete(tmpIni)
try FileAppend("PASS=" passed " FAIL=" failed "`n", "*")
ExitApp(failed > 0 ? 1 : 0)
