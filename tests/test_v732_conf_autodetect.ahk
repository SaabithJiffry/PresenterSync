; ==============================================================================
; Test Suite: test_v732_conf_autodetect.ahk
; Description: Verifies v7.3.2 Conferencing Auto-Detect ("Auto"), localized
;              UIA mute/unmute keywords, Meet background-tab warning, and
;              Config.UiaMuteKeywords / Config.UiaUnmuteKeywords persistence.
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

tmpIni := A_Temp "\PresenterSync_v732_test_" A_TickCount ".ini"
if FileExist(tmpIni)
    FileDelete(tmpIni)
if FileExist(tmpIni ".bak")
    FileDelete(tmpIni ".bak")

cfg := Config(tmpIni)
st := OverlayState(cfg)
st.suppressNudgeBanners := true

; 1. NormalizeConferencingApp & GetConferencingAppNames
apps := GetConferencingAppNames()
AssertTrue(apps.Length >= 4 && apps[1] = "Auto", "GetConferencingAppNames includes Auto first")
AssertTrue(NormalizeConferencingApp("auto") = "Auto", "NormalizeConferencingApp('auto') == 'Auto'")
AssertTrue(NormalizeConferencingApp("teams") = "Microsoft Teams", "NormalizeConferencingApp('teams') == 'Microsoft Teams'")

; 2. ResolveAutoConfAppTarget with mock winSnapshots
cfg.ConferencingApp := "Auto"
resZoom := ResolveAutoConfAppTarget(cfg, st, [{ exe: "Zoom.exe", title: "Zoom Meeting", active: false, minMax: 0 }])
AssertTrue(resZoom = "Zoom" && st.detectedConfApp = "Zoom", "Auto-detect resolves Zoom.exe")

resTeams := ResolveAutoConfAppTarget(cfg, st, [{ exe: "ms-teams.exe", title: "Standup | Microsoft Teams", active: false, minMax: 0 }])
AssertTrue(resTeams = "Teams" && st.detectedConfApp = "Teams", "Auto-detect resolves ms-teams.exe")

resMeet := ResolveAutoConfAppTarget(cfg, st, [{ exe: "chrome.exe", title: "Meet - abc-defg-hij - Google Chrome", active: false, minMax: 0 }])
AssertTrue(resMeet = "Meet" && st.detectedConfApp = "Meet", "Auto-detect resolves Google Meet in Chrome")

; Priority: active conferencing window wins over inactive/minimized ones
resPriority := ResolveAutoConfAppTarget(cfg, st, [
    { exe: "Zoom.exe", title: "Zoom Meeting", active: false, minMax: -1 },
    { exe: "ms-teams.exe", title: "Microsoft Teams", active: true, minMax: 0 },
    { exe: "chrome.exe", title: "Meet - xyz - Chrome", active: false, minMax: 0 }
])
AssertTrue(resPriority = "Teams" && st.detectedConfApp = "Teams", "Active window wins priority when multiple conferencing apps are open")

; Explicit non-Auto target overrides snapshot detection
cfg.ConferencingApp := "Zoom"
resExplicit := ResolveAutoConfAppTarget(cfg, st, [{ exe: "ms-teams.exe", title: "Microsoft Teams", active: true, minMax: 0 }])
AssertTrue(resExplicit = "Zoom", "Explicit ConferencingApp overrides Auto detection")
cfg.ConferencingApp := "Auto"

; 3. GetConfiguredUiaKeywords & ParseConferencingElementNames with custom localized keywords
cfg.UiaMuteKeywords := "Stummschalten, Silenciar"
cfg.UiaUnmuteKeywords := "Aktivieren, Activar audio"
kw := GetConfiguredUiaKeywords(cfg)
hasDeMute := false, hasDeUnmute := false
for _, m in kw.mute
    if (m = "Stummschalten")
        hasDeMute := true
for _, u in kw.unmute
    if (u = "Aktivieren")
        hasDeUnmute := true
AssertTrue(hasDeMute && hasDeUnmute, "GetConfiguredUiaKeywords merges localized mute/unmute keywords")

; When UIA button says "Stummschalten" (German for "Mute"), mic is currently unmuted (muted = false)
parsedMuteBtn := ParseConferencingElementNames(["Stummschalten", "Kamera"], "Zoom", 0, "", cfg)
AssertTrue(parsedMuteBtn.hasMic == true && parsedMuteBtn.muted == false, "ParseConferencingElementNames recognizes localized mute keyword 'Stummschalten' -> muted=false")

; When UIA button says "Aktivieren" (localized unmute), mic is currently muted (muted = true)
parsedUnmuteBtn := ParseConferencingElementNames(["Aktivieren", "Kamera"], "Zoom", 0, "", cfg)
AssertTrue(parsedUnmuteBtn.hasMic == true && parsedUnmuteBtn.muted == true, "ParseConferencingElementNames recognizes localized unmute keyword 'Aktivieren' -> muted=true")

; 4. CheckMeetBackgroundTabWarning (minimized, background tab, active foreground tab)
cfg.ConferencingApp := "Google Meet"
st.meetBgTabWarn := false
wMin := CheckMeetBackgroundTabWarning(cfg, st, [{ exe: "chrome.exe", title: "Meet - abc-defg-hij", active: false, minMax: -1 }])
AssertTrue(wMin == true && st.meetBgTabWarn == true, "CheckMeetBackgroundTabWarning warns when Meet window is minimized")

wBgTab := CheckMeetBackgroundTabWarning(cfg, st, [
    { exe: "chrome.exe", title: "Inbox - Gmail - Google Chrome", active: true, minMax: 0 }
])
AssertTrue(wBgTab == true && st.meetBgTabWarn == true, "CheckMeetBackgroundTabWarning warns when browser switched to background tab")

wFg := CheckMeetBackgroundTabWarning(cfg, st, [{ exe: "chrome.exe", title: "Meet - abc-defg-hij", active: true, minMax: 0 }])
AssertTrue(wFg == false && st.meetBgTabWarn == false, "CheckMeetBackgroundTabWarning clears when Meet tab is active foreground")

; 5. Config.UiaMuteKeywords / UiaUnmuteKeywords save/load roundtrip via ApplyControlCenterSettings
okCC := ApplyControlCenterSettings(cfg, st, { UiaMuteKeywords: "Muter", UiaUnmuteKeywords: "Activer" }, false)
AssertTrue(okCC == true && cfg.UiaMuteKeywords = "Muter" && cfg.UiaUnmuteKeywords = "Activer", "ApplyControlCenterSettings updates UIA keyword fields")
reloaded := Config(tmpIni)
AssertTrue(reloaded.UiaMuteKeywords = "Muter" && reloaded.UiaUnmuteKeywords = "Activer", "UiaMuteKeywords & UiaUnmuteKeywords persist across Config reload")
reloaded.DeleteFile()

try FileAppend("PASS=" passed " FAIL=" failed "`n", "*")
ExitApp(failed > 0 ? 1 : 0)
