; ==============================================================================
; Test Suite: test_v703_hud_visuals.ahk
; Description: Verifies v7.0.3 HUD Visuals & Dynamic Tier Stacking (#1, #4, #5, #6):
;              VOICE_METER_INTERVAL_MS == 25, ShowRow2RecChatHud &
;              ShowRow3StudioSceneHud Config/Profile persistence, GetHudTierFlags,
;              ComputeHudLayout gapless stacking, and ApplyControlCenterSettings.
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

; 1. VOICE_METER_INTERVAL_MS == 25 (40 FPS)
AssertTrue(UIConstants.VOICE_METER_INTERVAL_MS == 25, "VOICE_METER_INTERVAL_MS is 25ms (40 FPS)")

; 2. ShowRow2RecChatHud & ShowRow3StudioSceneHud Config load/save & GetProfileFieldSpecs()
tmpIni := A_Temp "\PresenterSync_v703_test_" A_TickCount ".ini"
if FileExist(tmpIni)
    FileDelete(tmpIni)

cfg := Config(tmpIni)
AssertTrue(cfg.ShowRow2RecChatHud == true, "ShowRow2RecChatHud defaults to true")
AssertTrue(cfg.ShowRow3StudioSceneHud == true, "ShowRow3StudioSceneHud defaults to true")

cfg.ShowRow2RecChatHud := false
cfg.ShowRow3StudioSceneHud := true
cfg.WriteBool("Settings", "ShowRow2RecChatHud", false)
cfg.WriteBool("Settings", "ShowRow3StudioSceneHud", true)

cfgReloaded := Config(tmpIni)
AssertTrue(cfgReloaded.ShowRow2RecChatHud == false, "Config persists ShowRow2RecChatHud=false")
AssertTrue(cfgReloaded.ShowRow3StudioSceneHud == true, "Config persists ShowRow3StudioSceneHud=true")

specs := cfg.GetProfileFieldSpecs()
specKeys := Map()
for _, sp in specs
    specKeys[sp.prop] := true
AssertTrue(specKeys.Has("ShowRow2RecChatHud"), "GetProfileFieldSpecs includes ShowRow2RecChatHud")
AssertTrue(specKeys.Has("ShowRow3StudioSceneHud"), "GetProfileFieldSpecs includes ShowRow3StudioSceneHud")

; 3. GetHudTierFlags(cfg) & ComputeHudLayout(state, 100, 500, cfg) dynamic gapless stacking
cfg.EnableWS := true
cfg.ShowExtraHuds := true
cfg.ShowRow2RecChatHud := false
cfg.ShowRow3StudioSceneHud := true
cfg.ShowStreamHud := false

tiers := GetHudTierFlags(cfg)
AssertTrue(tiers.row2 == false && tiers.row3 == true && tiers.row4 == false, "GetHudTierFlags reflects Row 1 + Row 3 only")

st := OverlayState(cfg)
layout := ComputeHudLayout(st, 100, 500, cfg)
expectedRow3Y := layout.micY - st.hudGap - st.row3Height
AssertTrue(layout.studioY == expectedRow3Y, "Row 3 stacks directly above MicGui with zero gap from disabled Row 2")
AssertTrue(layout.sceneY == expectedRow3Y, "Scene pill aligns with Studio pill on Row 3")

; Also verify Row 1 + Row 4 only (Row 2 and Row 3 disabled)
cfg.ShowRow2RecChatHud := false
cfg.ShowRow3StudioSceneHud := false
cfg.ShowStreamHud := true
tiersR4 := GetHudTierFlags(cfg)
AssertTrue(tiersR4.row2 == false && tiersR4.row3 == false && tiersR4.row4 == true, "GetHudTierFlags reflects Row 1 + Row 4 only")
layoutR4 := ComputeHudLayout(st, 100, 500, cfg)
expectedRow4Y := layoutR4.micY - st.hudGap - st.row4Height
AssertTrue(layoutR4.streamY == expectedRow4Y, "Row 4 stacks directly above MicGui when Row 2 & Row 3 are disabled")

; 4. ApplyControlCenterSettings toggles both flags
okCC := ApplyControlCenterSettings(cfg, st, {
    ShowRow2RecChatHud: true,
    ShowRow3StudioSceneHud: false
}, false)
AssertTrue(okCC == true, "ApplyControlCenterSettings succeeds for tier flags")
AssertTrue(cfg.ShowRow2RecChatHud == true && cfg.ShowRow3StudioSceneHud == false, "ApplyControlCenterSettings updates ShowRow2RecChatHud and ShowRow3StudioSceneHud")

try FileDelete(tmpIni)
try FileAppend("PASS=" passed " FAIL=" failed "`n", "*")
ExitApp(failed > 0 ? 1 : 0)
