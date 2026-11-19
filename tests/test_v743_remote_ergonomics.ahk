; ==============================================================================
; Test Suite: test_v743_remote_ergonomics.ahk
; Description: Verifies v7.4.3 Remote Ergonomics Parity (ratio position,
;              pill mini-badges, amber alert border, ShowPillMiniBadges config).
; ==============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
SetTimer(() => ExitApp(124), -45000)
OnError((err, mode) => (FileAppend("UNHANDLED_ERR: " err.Message " (" err.What ") at " err.File ":" err.Line "`n", "*"), ExitApp(1)))

#Include "%A_LineFile%\..\..\Lib\WebSocket.ahk"
#Include "%A_LineFile%\..\..\Lib\UIA.ahk"
#Include "%A_LineFile%\..\..\Lib\Crypto.ahk"
#Include "%A_LineFile%\..\..\Lib\RemoteBridgeClient.ahk"
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

; 1. ComputePositionRatio & ResolvePositionFromRatio (standard + negative-origin multi-monitor)
rStd := ComputePositionRatio(960, 540, 0, 0, 1920, 1080)
AssertTrue(Abs(rStd.xRatio - 0.5) < 0.01 && Abs(rStd.yRatio - 0.5) < 0.01, "ComputePositionRatio computes 0.5,0.5 for center of 1920x1080")
pStd := ResolvePositionFromRatio(rStd.xRatio, rStd.yRatio, 120, 44, 0, 0, 1920, 1080)
AssertTrue(pStd.x == 960 && pStd.y == 540, "ResolvePositionFromRatio restores 960,540 on 1920x1080")

rNeg := ComputePositionRatio(-960, 270, -1920, 0, 0, 1080)
AssertTrue(Abs(rNeg.xRatio - 0.5) < 0.01 && Abs(rNeg.yRatio - 0.25) < 0.01, "ComputePositionRatio supports negative-origin secondary monitor")
pNeg := ResolvePositionFromRatio(rNeg.xRatio, rNeg.yRatio, 120, 44, -1920, 0, 0, 1080)
AssertTrue(pNeg.x == -960 && pNeg.y == 270, "ResolvePositionFromRatio restores -960,270 on negative-origin monitor")

; 2. BuildRemotePillBadgeText
cfgBadge := { ShowPillMiniBadges: true }
AssertTrue(BuildRemotePillBadgeText(cfgBadge, { timerState: "running", timerRemainingSec: 120, isStandby: false, recState: 0 }) = "02:00", "BuildRemotePillBadgeText formats countdown 02:00")
AssertTrue(BuildRemotePillBadgeText(cfgBadge, { timerState: "overtime", timerRemainingSec: -15, isStandby: false, recState: 0 }) = "-00:15", "BuildRemotePillBadgeText formats overtime -00:15")
AssertTrue(BuildRemotePillBadgeText(cfgBadge, { timerState: "stopped", isStandby: true, recState: 1 }) = "BRB REC", "BuildRemotePillBadgeText formats BRB + REC")
AssertTrue(BuildRemotePillBadgeText({ ShowPillMiniBadges: false }, { timerState: "running", timerRemainingSec: 120, isStandby: true, recState: 1 }) = "", "BuildRemotePillBadgeText returns empty when ShowPillMiniBadges=false")

; 3. GetRemotePillAlertBorderArgb
AssertTrue(GetRemotePillAlertBorderArgb(cfgBadge, { voiceWhileMuted: true, isMuted: true }) == 0xFFF59E0B, "GetRemotePillAlertBorderArgb returns amber 0xFFF59E0B when speaking while muted")
AssertTrue(GetRemotePillAlertBorderArgb(cfgBadge, { voiceWhileMuted: false, isMuted: true }) == 0, "GetRemotePillAlertBorderArgb returns 0 when voiceWhileMuted=false")
AssertTrue(GetRemotePillAlertBorderArgb({ ShowPillMiniBadges: false }, { voiceWhileMuted: true, isMuted: true }) == 0, "GetRemotePillAlertBorderArgb returns 0 when ShowPillMiniBadges=false")

; 4. Config.ShowPillMiniBadges persistence
tmpIni := A_Temp "\PresenterSync_v743_test_" A_TickCount ".ini"
if FileExist(tmpIni)
    FileDelete(tmpIni)
if FileExist(tmpIni ".bak")
    FileDelete(tmpIni ".bak")

cfg := Config(tmpIni)
AssertTrue(cfg.ShowPillMiniBadges == true, "Config.ShowPillMiniBadges defaults to true")
cfg.ShowPillMiniBadges := false
cfg.WriteBool("Settings", "ShowPillMiniBadges", false)
reloaded := Config(tmpIni)
AssertTrue(reloaded.ShowPillMiniBadges == false, "Config.ShowPillMiniBadges persists false across reload")
reloaded.DeleteFile()

try FileAppend("PASS=" passed " FAIL=" failed "`n", "*")
ExitApp(failed > 0 ? 1 : 0)
