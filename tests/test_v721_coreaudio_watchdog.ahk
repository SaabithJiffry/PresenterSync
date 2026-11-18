; ==============================================================================
; Test Suite: test_v721_coreaudio_watchdog.ahk
; Description: Verifies v7.2.1 CoreAudio OS endpoint mute fallback and the
;              OS mic mute drift watchdog (config, mocks, drift, bridge JSON).
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

tmpIni := A_Temp "\PresenterSync_v721_test_" A_TickCount ".ini"
if FileExist(tmpIni)
    FileDelete(tmpIni)

; 1. Config defaults, persistence and GetProfileFieldSpecs
cfg := Config(tmpIni)
AssertTrue(cfg.EnableCoreAudioFallback == true && cfg.EnableOsMuteDriftWatchdog == true, "Config defaults enable CoreAudio fallback + drift watchdog")
specKeys := Map()
for spec in cfg.GetProfileFieldSpecs()
    specKeys[spec.key] := spec
AssertTrue(specKeys.Has("EnableCoreAudioFallback") && specKeys.Has("EnableOsMuteDriftWatchdog"), "GetProfileFieldSpecs includes both CoreAudio keys")

st := OverlayState(cfg)
st.suppressNudgeBanners := true
okCC := ApplyControlCenterSettings(cfg, st, { EnableCoreAudioFallback: false, EnableOsMuteDriftWatchdog: false }, false)
AssertTrue(okCC == true && cfg.EnableCoreAudioFallback == false && cfg.EnableOsMuteDriftWatchdog == false, "ApplyControlCenterSettings applies both CoreAudio flags")
cfgReloaded := Config(tmpIni)
AssertTrue(cfgReloaded.EnableCoreAudioFallback == false && cfgReloaded.EnableOsMuteDriftWatchdog == false, "Both CoreAudio flags persist to INI")
ApplyControlCenterSettings(cfg, st, { EnableCoreAudioFallback: true, EnableOsMuteDriftWatchdog: true }, false)
AssertTrue(cfg.EnableCoreAudioFallback == true && cfg.EnableOsMuteDriftWatchdog == true, "ApplyControlCenterSettings re-enables both flags")

AssertTrue(st.HasOwnProp("osMicMutedDrift") && st.osMicMutedDrift == false && st.HasOwnProp("lastOsDriftWarnTick"), "OverlayState exposes drift fields")

; 2. AudioMeter mock hooks
AudioMeter._mockOsMute := true
AssertTrue(AudioMeter.GetOsMicMute() == true, "GetOsMicMute returns true via mock")
AudioMeter._mockOsMute := false
AssertTrue(AudioMeter.GetOsMicMute() == false, "GetOsMicMute returns false via mock")
AudioMeter._mockOsMute := -1
AssertTrue(AudioMeter.GetOsMicMute() == -1, "GetOsMicMute returns -1 when unavailable")
AudioMeter._mockOsMute := ""

setCalls := []
AudioMeter._mockSetOsMuteFn := (m) => (setCalls.Push(m), true)
AssertTrue(AudioMeter.SetOsMicMute(true) == true && setCalls.Length == 1 && setCalls[1] == true, "SetOsMicMute routes through mock and returns true")

; 3. TryCoreAudioFallbackMute
st.isMuted := false
AssertTrue(TryCoreAudioFallbackMute(cfg, st, true, "test") == true && st.isMuted == true, "TryCoreAudioFallbackMute mutes and syncs UI state")
AssertTrue(setCalls.Length == 2 && setCalls[2] == true, "Fallback invoked SetOsMicMute(true)")
cfg.EnableCoreAudioFallback := false
before := setCalls.Length
AssertTrue(TryCoreAudioFallbackMute(cfg, st, false, "test") == false && setCalls.Length == before, "Fallback disabled by config does nothing")
cfg.EnableCoreAudioFallback := true
AudioMeter._mockSetOsMuteFn := (m) => false
AssertTrue(TryCoreAudioFallbackMute(cfg, st, false, "test") == false && st.isMuted == true, "Failed SetOsMicMute leaves state unchanged")
AudioMeter._mockSetOsMuteFn := ""

; 4. EvaluateOsMicDrift trigger, cooldown, clear
st.isMuted := false
st.osMicMutedDrift := false
st.lastOsDriftWarnTick := 0
AssertTrue(EvaluateOsMicDrift(cfg, st, true, 100000) == true && st.osMicMutedDrift == true && st.lastOsDriftWarnTick == 100000, "Drift triggers when OS muted while LIVE")
EvaluateOsMicDrift(cfg, st, true, 130000)
AssertTrue(st.lastOsDriftWarnTick == 100000, "Nudge respects 60s cooldown")
EvaluateOsMicDrift(cfg, st, true, 160000)
AssertTrue(st.lastOsDriftWarnTick == 160000, "Nudge re-fires after 60s")

json := ""
bridge := HostCompanionBridge()
bridge.cfg := cfg
bridge.state := st
json := bridge._BuildMuteStateJson()
AssertTrue(InStr(json, '"osMicMutedDrift":true'), "_BuildMuteStateJson reports osMicMutedDrift true")

AssertTrue(EvaluateOsMicDrift(cfg, st, false, 170000) == false && st.osMicMutedDrift == false, "Drift clears when OS unmuted")
EvaluateOsMicDrift(cfg, st, true, 400000)
st.isMuted := true
EvaluateOsMicDrift(cfg, st, true, 400100)
AssertTrue(st.osMicMutedDrift == false, "Drift clears when app is muted")
st.isMuted := false
cfg.EnableOsMuteDriftWatchdog := false
EvaluateOsMicDrift(cfg, st, true, 500000)
AssertTrue(st.osMicMutedDrift == false, "Drift not flagged when watchdog disabled")
cfg.EnableOsMuteDriftWatchdog := true

json := bridge._BuildMuteStateJson()
AssertTrue(InStr(json, '"osMicMutedDrift":false'), "_BuildMuteStateJson reports osMicMutedDrift false after clear")

try FileDelete(tmpIni)
try FileAppend("PASS=" passed " FAIL=" failed "`n", "*")
ExitApp(failed > 0 ? 1 : 0)
