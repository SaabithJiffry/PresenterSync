; ==============================================================================
; Test Suite: test_v722_safety_watchdogs.ahk
; Description: Verifies v7.2.2 Forgotten-Record, Stream-Drop Auto-Backup,
;              Low-Disk and Dead-Mic watchdogs (config, evaluators, bridge JSON).
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

class MockObsWs {
    sent := []
    sendText(txt) {
        this.sent.Push(txt)
        return true
    }
}

tmpIni := A_Temp "\PresenterSync_v722_test_" A_TickCount ".ini"
if FileExist(tmpIni)
    FileDelete(tmpIni)

; 1. Config defaults, GetProfileFieldSpecs, ApplyControlCenterSettings
cfg := Config(tmpIni)
AssertTrue(cfg.EnableForgottenRecordWatchdog && cfg.AutoRecordOnStreamDrop && cfg.EnableLowDiskWatchdog && cfg.EnableDeadMicWatchdog, "Config defaults enable all four safety watchdogs")
specKeys := Map()
for spec in cfg.GetProfileFieldSpecs()
    specKeys[spec.key] := spec
AssertTrue(specKeys.Has("EnableForgottenRecordWatchdog") && specKeys.Has("AutoRecordOnStreamDrop") && specKeys.Has("EnableLowDiskWatchdog") && specKeys.Has("EnableDeadMicWatchdog"), "GetProfileFieldSpecs includes all four watchdog keys")

st := OverlayState(cfg)
st.suppressNudgeBanners := true
okCC := ApplyControlCenterSettings(cfg, st, { EnableForgottenRecordWatchdog: false, AutoRecordOnStreamDrop: false, EnableLowDiskWatchdog: false, EnableDeadMicWatchdog: false }, false)
AssertTrue(okCC == true && !cfg.EnableForgottenRecordWatchdog && !cfg.AutoRecordOnStreamDrop && !cfg.EnableLowDiskWatchdog && !cfg.EnableDeadMicWatchdog, "ApplyControlCenterSettings applies all four flags")
reloaded := Config(tmpIni)
AssertTrue(!reloaded.EnableForgottenRecordWatchdog && !reloaded.AutoRecordOnStreamDrop && !reloaded.EnableLowDiskWatchdog && !reloaded.EnableDeadMicWatchdog, "All four flags persist to INI")
ApplyControlCenterSettings(cfg, st, { EnableForgottenRecordWatchdog: true, AutoRecordOnStreamDrop: true, EnableLowDiskWatchdog: true, EnableDeadMicWatchdog: true }, false)
AssertTrue(cfg.EnableForgottenRecordWatchdog && cfg.AutoRecordOnStreamDrop && cfg.EnableLowDiskWatchdog && cfg.EnableDeadMicWatchdog, "ApplyControlCenterSettings re-enables all four flags")
AssertTrue(st.HasOwnProp("lowDiskWarnLevel") && st.lowDiskWarnLevel == 0 && st.lowDiskMb == -1 && st.deadMicWarn == false && st.streamDropWarn == false, "OverlayState exposes watchdog fields")

; 2. Forgotten-record watchdog (15s grace, 120s cooldown)
cfg.AudioRoutingMode := 1
st.isMuted := false
st.obsRecState := 0
AssertTrue(EvaluateForgottenRecordWatchdog(cfg, st, true, 1000) == false, "Forgotten-record starts grace without firing")
AssertTrue(EvaluateForgottenRecordWatchdog(cfg, st, true, 15999) == false, "Forgotten-record silent before 15s grace")
AssertTrue(EvaluateForgottenRecordWatchdog(cfg, st, true, 16000) == true, "Forgotten-record fires after 15s grace")
AssertTrue(EvaluateForgottenRecordWatchdog(cfg, st, true, 100000) == false, "Forgotten-record respects 120s cooldown")
AssertTrue(EvaluateForgottenRecordWatchdog(cfg, st, true, 136000) == true, "Forgotten-record re-fires after 120s")
st.obsRecState := 1
EvaluateForgottenRecordWatchdog(cfg, st, true, 140000)
st.obsRecState := 0
AssertTrue(EvaluateForgottenRecordWatchdog(cfg, st, true, 141000) == false, "Recording active resets grace timer")
cfg.AudioRoutingMode := 2
st.obsRecState := 0
AssertTrue(EvaluateForgottenRecordWatchdog(cfg, st, true, 500000) == false && EvaluateForgottenRecordWatchdog(cfg, st, true, 600000) == false, "Forgotten-record ignores routing modes outside [1,3]")
cfg.AudioRoutingMode := 1

; 3. Stream-drop auto-backup (10s continuous reconnect)
ws := MockObsWs()
st.obsWs := ws
st.obsRecState := 0
st.streamState := 2
AssertTrue(EvaluateStreamDropWatchdog(cfg, st, 1000) == false && ws.sent.Length == 0, "Stream-drop starts timer without firing")
AssertTrue(EvaluateStreamDropWatchdog(cfg, st, 10999) == false && ws.sent.Length == 0, "Stream-drop silent before 10s")
AssertTrue(EvaluateStreamDropWatchdog(cfg, st, 11000) == true, "Stream-drop fires after 10s continuous reconnect")
AssertTrue(ws.sent.Length == 1 && InStr(ws.sent[1], "StartRecord") && st.streamDropWarn == true, "Stream-drop sends StartRecord and sets streamDropWarn")
EvaluateStreamDropWatchdog(cfg, st, 12000)
AssertTrue(ws.sent.Length == 1, "Stream-drop sends StartRecord only once per drop")
st.streamState := 1
EvaluateStreamDropWatchdog(cfg, st, 13000)
AssertTrue(st.streamDropWarn == false, "Stream recovery clears streamDropWarn")
st.streamState := 2
st.obsRecState := 1
EvaluateStreamDropWatchdog(cfg, st, 20000)
EvaluateStreamDropWatchdog(cfg, st, 40000)
AssertTrue(ws.sent.Length == 1, "Stream-drop does not start recording when OBS already recording")
st.streamState := 0
st.obsRecState := 0

; 4. Low-disk watchdog
AssertTrue(EvaluateLowDiskWatchdog(cfg, st, 4096, 1000) == 0 && st.lowDiskWarnLevel == 0 && st.lowDiskMb == 4096, "Low-disk >= 2048 MB is level 0")
AssertTrue(EvaluateLowDiskWatchdog(cfg, st, 2047, 2000) == 1 && st.lowDiskWarnLevel == 1, "Low-disk < 2048 MB is level 1 (amber)")
AssertTrue(EvaluateLowDiskWatchdog(cfg, st, 511, 3000) == 2 && st.lowDiskWarnLevel == 2 && st.lowDiskMb == 511, "Low-disk < 512 MB is level 2 (red)")
AssertTrue(EvaluateLowDiskWatchdog(cfg, st, 3000, 4000) == 0 && st.lowDiskWarnLevel == 0, "Low-disk clears when space recovers")
AssertTrue(EvaluateLowDiskWatchdog(cfg, st, -1, 5000) == 0 && st.lowDiskMb == -1, "Low-disk ignores unavailable (-1) reading")
cfg.EnableLowDiskWatchdog := false
AssertTrue(EvaluateLowDiskWatchdog(cfg, st, 100, 6000) == 0 && st.lowDiskWarnLevel == 0, "Low-disk disabled by config")
cfg.EnableLowDiskWatchdog := true

; 5. Dead-mic watchdog (45s silence while LIVE and presenting)
st.isMuted := false
AssertTrue(EvaluateDeadMicWatchdog(cfg, st, 0.001, true, 1000) == false && st.deadMicWarn == false, "Dead-mic starts timer without warning")
EvaluateDeadMicWatchdog(cfg, st, 0.001, true, 45999)
AssertTrue(st.deadMicWarn == false, "Dead-mic silent before 45s")
EvaluateDeadMicWatchdog(cfg, st, 0.001, true, 46000)
AssertTrue(st.deadMicWarn == true, "Dead-mic warns after 45s continuous silence")
EvaluateDeadMicWatchdog(cfg, st, 0.2, true, 47000)
AssertTrue(st.deadMicWarn == false, "Dead-mic clears when audio returns")
EvaluateDeadMicWatchdog(cfg, st, 0.001, true, 50000)
EvaluateDeadMicWatchdog(cfg, st, 0.001, false, 100000)
AssertTrue(st.deadMicWarn == false, "Dead-mic not flagged when not presenting")
st.isMuted := true
EvaluateDeadMicWatchdog(cfg, st, 0.001, true, 200000)
EvaluateDeadMicWatchdog(cfg, st, 0.001, true, 300000)
AssertTrue(st.deadMicWarn == false, "Dead-mic not flagged while app is muted")
st.isMuted := false

; 6. HostBridge JSON fields
st.streamDropWarn := true
st.lowDiskWarnLevel := 2
st.lowDiskMb := 300
st.deadMicWarn := true
bridge := HostCompanionBridge()
bridge.cfg := cfg
bridge.state := st
json := bridge._BuildMuteStateJson()
AssertTrue(InStr(json, '"streamDropWarn":true'), "_BuildMuteStateJson includes streamDropWarn")
AssertTrue(InStr(json, '"lowDiskWarnLevel":2'), "_BuildMuteStateJson includes lowDiskWarnLevel")
AssertTrue(InStr(json, '"lowDiskMb":300'), "_BuildMuteStateJson includes lowDiskMb")
AssertTrue(InStr(json, '"deadMicWarn":true'), "_BuildMuteStateJson includes deadMicWarn")

; 7. M1.4 BRB Standby suppression & Solo Primary Voice-While-Muted monitor
st.isMuted := true
st.isStandby := true
st.voiceWhileMuted := false
st.mutedVoiceAboveSince := 0
EvaluateMutedVoiceAlert(cfg, st, 0.85, 1000)
EvaluateMutedVoiceAlert(cfg, st, 0.85, 3000)
AssertTrue(!st.voiceWhileMuted, "EvaluateMutedVoiceAlert suppressed during BRB standby")
st.isStandby := false
AssertTrue(EvaluateMutedVoiceAlert(cfg, st, 0.85, 4000) == false && EvaluateMutedVoiceAlert(cfg, st, 0.85, 5600) == true && st.voiceWhileMuted, "Voice-While-Muted resumes once BRB ends")
st.isMuted := true
st.voiceWhileMuted := false
st.mutedVoiceAboveSince := 0
MutedVoiceMonitorTick(cfg, st, (*) => 0.60)
AssertTrue(st.mutedVoiceAboveSince > 0, "MutedVoiceMonitorTick evaluates solo Primary mic signal even with 0 remote clients")
st.isMuted := false
EvaluateMutedVoiceAlert(cfg, st, 0.0, 5700)

try FileDelete(tmpIni)
try FileAppend("PASS=" passed " FAIL=" failed "`n", "*")
ExitApp(failed > 0 ? 1 : 0)
