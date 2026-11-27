; ==============================================================================
; Test Suite: test_v1020_audit_hardening.ahk
; Description: Verifies v10.2.0 M1A Windows Primary & Remote hardening fixes
;              (KioskPin redaction, timer cleanup, SelfUpdater/FirstRun dedup,
;               Teams/Meet hotkey lookup, HostBridge EnableWS & I/O guards,
;               and SetupWizard/LogViewer fixes).
; ==============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
SetTimer(() => ExitApp(124), -45000)
OnError((err, mode) => (FileAppend("UNHANDLED_ERR: " err.Message " (" err.What ") at " err.File ":" err.Line "`n", "*"), ExitApp(1)))

#Include "%A_LineFile%\..\..\Lib\WebSocket.ahk"
#Include "%A_LineFile%\..\..\Lib\Crypto.ahk"
#Include "%A_LineFile%\..\..\Lib\Gdip.ahk"
#Include "%A_LineFile%\..\..\Lib\UIA.ahk"
#Include "%A_LineFile%\..\..\Lib\QrCode.ahk"
#Include "%A_LineFile%\..\..\Lib\OBS_Network.ahk"
#Include "%A_LineFile%\..\..\Lib\RemoteBridgeClient.ahk"
#Include "%A_LineFile%\..\..\Lib\HostBridge.ahk"
#Include "%A_LineFile%\..\..\Lib\SelfUpdater.ahk"
#Include "%A_LineFile%\..\..\Lib\SetupWizard.ahk"
#Include "%A_LineFile%\..\..\Lib\GUI_Config.ahk"
#Include "%A_LineFile%\..\..\Lib\ControlCenter.ahk"
#Include "%A_LineFile%\..\..\Lib\DiagnosticLogger.ahk"

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

tmpIni := A_Temp "\ps_v1020_m1a_" A_TickCount ".ini"
tmpJson := A_Temp "\ps_v1020_m1a_bundle_" A_TickCount ".json"
tmpIniBundle := A_Temp "\ps_v1020_m1a_bundle_" A_TickCount ".ini"
for _, p in [tmpIni, tmpIni ".bak", tmpJson, tmpIniBundle] {
    if FileExist(p)
        try FileDelete(p)
}

; 1. KioskPin redaction in Portable Settings Bundles & Sanitized Diagnostics (AUDIT-P1-01)
cfg := Config(tmpIni)
cfg.ObsPassword := "ObsSec#991"
cfg.SessionPairingCode := "K7M-9P2"
cfg.InternetPairingCode := "PS-1122-3344"
cfg.KioskPin := "73"
cfg.Write("Settings", "KioskPin", cfg.KioskPin)

AssertTrue(_IsBundleSecretProp("KioskPin") && _IsBundleSecretProp("SessionToken"), "_IsBundleSecretProp flags KioskPin and SessionToken as secrets")
resJson := ExportPortableSettingsBundle(cfg, tmpJson, false)
resIni := ExportPortableSettingsBundle(cfg, tmpIniBundle, false)
jsonTxt := FileExist(tmpJson) ? FileRead(tmpJson, "UTF-8") : ""
iniTxt := FileExist(tmpIniBundle) ? FileRead(tmpIniBundle, "UTF-8") : ""
AssertTrue(resJson.ok && !InStr(jsonTxt, '"KioskPin"') && !InStr(jsonTxt, "73"), "JSON Portable Bundle excludes KioskPin by default")
AssertTrue(resIni.ok && !InStr(iniTxt, "KioskPin="), "INI Portable Bundle excludes KioskPin by default")

AssertTrue(_Diag_ShouldRedactKey("Settings", "KioskPin"), "_Diag_ShouldRedactKey catches short or long KioskPin values")
diagTxt := BuildSanitizedDiagnosticsReport(cfg, "", "[Settings]`r`nKioskPin=73`r`nEnableWS=1`r`n")
AssertTrue(InStr(diagTxt, "KioskPin=[REDACTED]") && !InStr(diagTxt, "KioskPin=73"), "BuildSanitizedDiagnosticsReport redacts short KioskPin values")
diagSnap := DiagnosticLogger._FormatSettingsSnapshot(cfg)
AssertTrue(InStr(diagSnap, "KioskPin") && InStr(diagSnap, "[REDACTED]") && !InStr(diagSnap, "73"), "DiagnosticLogger._FormatSettingsSnapshot redacts KioskPin")

; 2. StopAllTimers & StopAllRemoteTimers + ResetRemoteConnectionTelemetry completeness (AUDIT-P1-13, AUDIT-P2-05)
firedExtra := 0
noop := (*) => (firedExtra += 1)
stHost := OverlayState(cfg)
stHost._optimisticTimerFn := noop
stHost._brbCountdownTimerFn := noop
stHost.sceneResetWatchdogFn := noop
stHost.autoProfileTimerFn := noop
SetTimer(stHost._optimisticTimerFn, -40)
SetTimer(stHost._brbCountdownTimerFn, -40)
SetTimer(stHost.sceneResetWatchdogFn, -40)
stoppedHost := stHost.StopAllTimers()
Sleep(80)
AssertTrue(stoppedHost >= 19 && firedExtra == 0, "OverlayState.StopAllTimers stops optimistic, BRB countdown, and scene reset watchdog timers (" stoppedHost ", fired=" firedExtra ")")

stRem := {
    dragTimerFn: noop, breathTimerFn: noop, _muteAnimTimerFn: noop, autoDodgeTimerFn: noop, idleDimTimerFn: noop,
    reconnectTimerFn: noop, heartbeatTimerFn: noop, lanRepromoteTimerFn: noop, presenterTickFn: noop,
    recTickFn: noop, rebuildTrayFn: noop, sceneMarqueeTimerFn: noop, _optimisticTimerFn: noop, sceneResetWatchdogFn: noop,
    obsConnected: true, usingBridge: true, usingDirectObsFallback: false, usingRelayFallback: false,
    activeHost: "HOST", recState: 1, obsRecState: 1, confRecState: 2, recSourceTag: "OBS+ZOOM",
    recSeconds: 42, unreadChatCount: 5, streamDropWarn: true, voiceWhileMuted: true, osMicMutedDrift: true,
    lowDiskWarnLevel: 1, lowDiskMb: 100, deadMicWarn: true, meetBgTabWarn: true, isStandby: true,
    timerState: "running", scenes: ["A"], quickNudges: ["B"], slideIndex: 1, slideTotal: 2,
    slideTitle: "T", slideNotes: "N", hostBootId: "B1", lastStateSeq: 9
}
stoppedRem := StopAllRemoteTimers(stRem)
AssertTrue(stoppedRem == 14, "StopAllRemoteTimers stops all 14 remote timers including marquee/optimistic/reset watchdog (" stoppedRem ")")
ResetRemoteConnectionTelemetry(stRem, true)
AssertTrue(stRem.obsRecState == 0 && stRem.confRecState == 0 && stRem.recSourceTag == "" && stRem.unreadChatCount == 0,
    "ResetRemoteConnectionTelemetry resets obsRecState, confRecState, recSourceTag, and unreadChatCount")

; 3. HostBridge EnableWS guard on allowDirectObsFallback & /update I/O error handling (AUDIT-P2-01/02)
cfg.EnableWS := false
hb := HostCompanionBridge()
hb.cfg := cfg
hb.state := stHost
authJson := hb._BuildAuthOkJson({ role: "Director", allowDirectObsFallback: true, sessionToken: "tok1" })
AssertTrue(InStr(authJson, '"allowDirectObsFallback":false'), "_BuildAuthOkJson sets allowDirectObsFallback=false when EnableWS=false")

; 4. SetupWizard & ControlCenter dynamic ObsWsPort interpolation (AUDIT-P2-03)
cfg.ObsWsPort := 4466
cfg.RemoteNetworkMode := "LAN"
cfg.AudioRoutingMode := 1
cfg.EnableWS := true
probes := RunWindowsSetupProbes(cfg, stHost, { obsPortListening: true, firewallProfile: "Private", firewallBlocked: false, isAdmin: true, lanIps: ["192.168.1.50"], bridgeSummary: { running: true, tcpPort: 4456, discoverPort: 4457 } })
AssertTrue(InStr(probes.steps[1].title, ":4466") && InStr(probes.steps[1].detail, ":4466"), "RunWindowsSetupProbes uses dynamic cfg.ObsWsPort (4466)")
pf := RunPreFlightRehearsalChecks(cfg, { obsConnected: false, voicePeak: 0.2, enableZoom: true, zoomConnected: true }, { bridgeRunning: true, pairedCount: 1, freeMB: 4096 })
AssertTrue(InStr(pf.checks[1].name, ":4466") && InStr(pf.checks[1].detail, ":4466"), "RunPreFlightRehearsalChecks uses dynamic cfg.ObsWsPort (4466)")
ccInfo := BuildLiveStatusInfo(cfg, stHost)
AssertTrue(InStr(ccInfo.remoteHost, ":4466"), "BuildLiveStatusInfo uses dynamic cfg.ObsWsPort (4466)")

; 5. Static source verification for GUI handlers that cannot spawn modal UI in headless test mode
diagSrc := FileRead(A_LineFile "\..\..\Lib\DiagnosticLogger.ahk", "UTF-8")
updSrc := FileRead(A_LineFile "\..\..\Lib\SelfUpdater.ahk", "UTF-8")
ccSrc := FileRead(A_LineFile "\..\..\Lib\ControlCenter.ahk", "UTF-8")
wizSrc := FileRead(A_LineFile "\..\..\Lib\SetupWizard.ahk", "UTF-8")
remSrc := FileRead(A_LineFile "\..\..\PresenterSync_Remote.ahk", "UTF-8")
AssertTrue(InStr(diagSrc, "(minMax = -1) ? 0 :") && !InStr(diagSrc, "(minMax = 1) ? 0 :"), "LogViewer Size handler guards minMax = -1 (not 1)")
AssertTrue(InStr(updSrc, 'Theme.FocusExistingWindow("UpdateAvailablePrompt")'), "SelfUpdater uses matching UpdateAvailablePrompt NamedWindows key")
AssertTrue(InStr(ccSrc, 'normApp = "Microsoft Teams"') && InStr(ccSrc, 'normApp = "Google Meet"'), "ControlCenter Help Shortcuts matches normalized Microsoft Teams / Google Meet names")
AssertTrue(InStr(wizSrc, "ApplySetupWizardRole(roleChoice)") && InStr(wizSrc, "SyncTelemetryBackendsFromConfig(cfg, state)"), "SetupWizard persists and syncs telemetry backends on role/OBS toggle")
AssertTrue(InStr(remSrc, '"SessionToken"') && InStr(remSrc, '"KioskPin"') && InStr(remSrc, 'CreateThemedRemoteDialog("RemoteFirstRunWizard"'), "Remote diagnostics scrubs SessionToken/KioskPin and FirstRunWizard deduplicates/unregisters cleanly")

for _, p in [tmpIni, tmpIni ".bak", tmpJson, tmpIniBundle] {
    if FileExist(p)
        try FileDelete(p)
}

try FileAppend("PASS=" passed " FAIL=" failed "`n", "*")
ExitApp(failed > 0 ? 1 : 0)
