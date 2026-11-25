; ==============================================================================
; Test Suite: test_v763_preflight_nudge_bundle.ahk
; Description: Verifies v7.6.3 Go Live 10-Second Rehearsal pre-flight checks,
;              Portable Settings Bundle export/import (.json & .ini), and
;              QuickNudgePresets parsing, persistence, & HostBridge JSON.
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

tmpIni := A_Temp "\PresenterSync_v763_test_" A_TickCount ".ini"
if FileExist(tmpIni)
    FileDelete(tmpIni)
if FileExist(tmpIni ".bak")
    FileDelete(tmpIni ".bak")

cfg := Config(tmpIni)
cfg.EnableWS := true
cfg.EnableZoom := true
cfg.AudioRoutingMode := 1
cfg.targetMicName := "Mic/Aux"
cfg.ObsPassword := "TopSecret123"
st := OverlayState(cfg)
st.obsAudioInputs := ["Mic/Aux", "Desktop Audio"]

; 1. RunPreFlightRehearsalChecks: all-PASS, WARN, FAIL, & ShowPreFlightRehearsalDialog under g_IsTestMode
resPass := RunPreFlightRehearsalChecks(cfg, st, {
    obsConnected: true,
    studioModeActive: true,
    micPeak: 0.25,
    confOpen: true,
    bridgeRunning: true,
    pairedCount: 2,
    freeMB: 10240
})
AssertTrue(resPass.ok == true && resPass.failCount == 0 && resPass.checks.Length == 5, "Pre-flight all-PASS returns 5 checks with 0 FAIL")

resWarn := RunPreFlightRehearsalChecks(cfg, st, {
    obsConnected: true,
    micPeak: 0.01,
    confOpen: true,
    bridgeRunning: true,
    pairedCount: 1,
    freeMB: 1500
})
AssertTrue(resWarn.ok == true && resWarn.warnCount >= 2 && resWarn.failCount == 0, "Pre-flight low micPeak & 1500MB disk returns WARN without FAIL")

resFail := RunPreFlightRehearsalChecks(cfg, st, {
    obsConnected: false,
    micPeak: 0.0,
    confOpen: false,
    bridgeRunning: false,
    pairedCount: 0,
    freeMB: 200
})
AssertTrue(resFail.ok == false && resFail.failCount >= 2, "Pre-flight disconnected OBS/Bridge & 200MB disk returns FAIL")

dlgRes := ShowPreFlightRehearsalDialog(cfg, st, { obsConnected: true, micPeak: 0.2, confOpen: true, bridgeRunning: true, pairedCount: 1, freeMB: 5000 })
AssertTrue(dlgRes.shown == false && dlgRes.testMode == true && dlgRes.result.ok == true, "ShowPreFlightRehearsalDialog returns non-blocking testMode result")

; 2. ExportPortableSettingsBundle & ImportPortableSettingsBundle (.json and .ini)
jsonPath := A_Temp "\PresenterSync_v763_bundle_" A_TickCount ".json"
iniBundlePath := A_Temp "\PresenterSync_v763_bundle_" A_TickCount ".ini"
try FileDelete(jsonPath)
try FileDelete(iniBundlePath)

cfg.QuickNudgePresets := "Hold On|5m Left|Check Slides"
okExpJson := ExportPortableSettingsBundle(cfg, jsonPath, false)
AssertTrue((IsObject(okExpJson) ? okExpJson.ok : okExpJson) == true && FileExist(jsonPath), "ExportPortableSettingsBundle writes .json")
rawJson := FileRead(jsonPath, "UTF-8")
AssertTrue(InStr(rawJson, "PresenterSyncBundle_v1") && !InStr(rawJson, "TopSecret123"), "JSON bundle includes schema and redacts obsPassword by default")

okExpIni := ExportPortableSettingsBundle(cfg, iniBundlePath, false)
rawIni := FileExist(iniBundlePath) ? FileRead(iniBundlePath, "UTF-8") : ""
AssertTrue((IsObject(okExpIni) ? okExpIni.ok : okExpIni) == true && FileExist(iniBundlePath) && InStr(rawIni, "[Bundle]"), "ExportPortableSettingsBundle writes real .ini sections for .ini extension")

; Modify cfg, then import JSON bundle back
cfg.QuickNudgePresets := "Changed"
cfg.AudioRoutingMode := 2
impJson := ImportPortableSettingsBundle(cfg, st, jsonPath)
AssertTrue(impJson.ok == true && impJson.appliedCount > 0 && cfg.QuickNudgePresets = "Hold On|5m Left|Check Slides" && cfg.AudioRoutingMode == 1, "ImportPortableSettingsBundle restores .json bundle")
AssertTrue(FileExist(tmpIni ".bak"), "ImportPortableSettingsBundle preserves .bak backup")

; Modify cfg, then import INI bundle back
cfg.QuickNudgePresets := "Changed2"
impIni := ImportPortableSettingsBundle(cfg, st, iniBundlePath)
AssertTrue(impIni.ok == true && cfg.QuickNudgePresets = "Hold On|5m Left|Check Slides", "ImportPortableSettingsBundle restores .ini bundle")

try FileDelete(jsonPath)
try FileDelete(iniBundlePath)

; 3. ParseQuickNudgePresets, Config.QuickNudgePresets persistence, & HostBridge quickNudges JSON
qnParsed := ParseQuickNudgePresets("  2m Left | Wrap Up , Check Mic | 2m Left |  ", 6)
AssertTrue(qnParsed.Length == 3 && qnParsed[1] = "2m Left" && qnParsed[2] = "Wrap Up" && qnParsed[3] = "Check Mic", "ParseQuickNudgePresets splits |/,, trims, skips empties, deduplicates")
qnDef := ParseQuickNudgePresets("  | , ", 6)
AssertTrue(qnDef.Length == 4 && qnDef[1] = "2 min left", "ParseQuickNudgePresets falls back to 4 defaults on empty input")

reloaded := Config(tmpIni)
AssertTrue(reloaded.QuickNudgePresets = "Hold On|5m Left|Check Slides", "Config.QuickNudgePresets persists across reload")

bridge := HostCompanionBridge()
bridge.cfg := cfg
bridge.state := st
bJson := bridge._BuildMuteStateJson()
AssertTrue(InStr(bJson, '"quickNudges":["Hold On","5m Left","Check Slides"]'), "HostBridge _BuildMuteStateJson emits quickNudges JSON array")
AssertTrue(_HB_JsonEscape("a" Chr(11) "b") == "a\u000bb" && EscapeJsonStr("a" Chr(11) "b") == "a\u000bb", "JSON escapers escape control chars < 0x20 including vertical tab")

reloaded.DeleteFile()

try FileAppend("PASS=" passed " FAIL=" failed "`n", "*")
ExitApp(failed > 0 ? 1 : 0)
