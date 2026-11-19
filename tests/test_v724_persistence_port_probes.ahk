; ==============================================================================
; Test Suite: test_v724_persistence_port_probes.ahk
; Description: Verifies v7.2.4 SessionTimeline JSONL autosave/recovery,
;              Config .ini.bak backup/recovery, HostBridge port fallback
;              (4456 -> 4458..4465) + URI, and Firewall/UIPI setup probes.
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
#Include "%A_LineFile%\..\..\Lib\SessionTimeline.ahk"
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

; 1. SessionTimeline .jsonl autosave, partial/corrupt trailing line skip, ClearAutosave
origAutosaveFile := SessionTimeline.AutosaveFile
origAutosaveEnabled := SessionTimeline.EnableAutosave
tmpJsonl := A_Temp "\PresenterSync_v724_tl_" A_TickCount ".jsonl"
try FileDelete(tmpJsonl)

SessionTimeline.Entries := []
SessionTimeline.AutosaveFile := tmpJsonl
SessionTimeline.EnableAutosave := true
SessionTimeline.Record("Mute", "Muted via Clicker")
SessionTimeline.Record("Scene", "Switched to Slides")
AssertTrue(FileExist(tmpJsonl) && FileGetSize(tmpJsonl) > 0, "SessionTimeline.Record writes JSONL autosave")

; Append a corrupt/partial trailing line to simulate mid-write crash
FileAppend('{"ts":"12:00:00","cat":"Alert","msg":"broken', tmpJsonl, "UTF-8")
SessionTimeline.Entries := []
recCount := SessionTimeline.RecoverFromAutosave(tmpJsonl)
AssertTrue(recCount == 2 && SessionTimeline.Entries.Length == 2, "RecoverFromAutosave restores 2 valid entries and skips corrupt trailing line")
AssertTrue(SessionTimeline.Entries[1].category = "Mute" && SessionTimeline.Entries[2].summary = "Switched to Slides", "Recovered timeline entries preserve category and summary")

SessionTimeline.ClearAutosave(tmpJsonl)
AssertTrue(!FileExist(tmpJsonl), "ClearAutosave removes JSONL autosave file")
SessionTimeline.AutosaveFile := origAutosaveFile
SessionTimeline.EnableAutosave := origAutosaveEnabled
SessionTimeline.Entries := []

; 2. Config .ini.bak auto-backup and recovery on missing or corrupt INI
tmpIni := A_Temp "\PresenterSync_v724_cfg_" A_TickCount ".ini"
if FileExist(tmpIni)
    FileDelete(tmpIni)
if FileExist(tmpIni ".bak")
    FileDelete(tmpIni ".bak")

cfg := Config(tmpIni)
cfg.EnableWS := false
cfg.WriteBool("Settings", "EnableWS", false)
cfg.ObsPassword := "BakSecret99"
cfg.Write("Settings", "ObsPassword", "BakSecret99")
cfg.BackupToFile(true)
AssertTrue(FileExist(tmpIni ".bak") && FileGetSize(tmpIni ".bak") > 0, "Config.BackupToFile creates non-empty .bak")

; Delete primary INI -> Load should recover from .bak
FileDelete(tmpIni)
cfgRecovered := Config(tmpIni)
AssertTrue(FileExist(tmpIni) && cfgRecovered.EnableWS == false && cfgRecovered.ObsPassword = "BakSecret99", "Config.Load recovers missing INI from .bak")

; Corrupt primary INI -> Load should recover from .bak
FileDelete(tmpIni)
FileAppend("CORRUPT_GARBAGE_NO_SETTINGS_SECTION", tmpIni, "UTF-8")
cfgRecovered2 := Config(tmpIni)
AssertTrue(cfgRecovered2.EnableWS == false && cfgRecovered2.ObsPassword = "BakSecret99", "Config.Load recovers corrupt INI from .bak")
cfgRecovered2.DeleteFile()
AssertTrue(!FileExist(tmpIni) && !FileExist(tmpIni ".bak"), "Config.DeleteFile removes both INI and .bak")

; 3. GetBridgeFallbackPorts & HostCompanionBridge port conflict auto-fallback + BuildHostPairingUri
fbPorts := GetBridgeFallbackPorts(4456)
AssertTrue(fbPorts.Length == 9 && fbPorts[1] == 4456 && fbPorts[2] == 4458 && fbPorts[9] == 4465, "GetBridgeFallbackPorts returns [4456, 4458..4465]")
fbDup := GetBridgeFallbackPorts(4458)
AssertTrue(fbDup.Length == 8 && fbDup[1] == 4458 && fbDup[2] == 4459, "GetBridgeFallbackPorts deduplicates preferred port in fallback range")

; Occupy port 14488 with blocker bridge, then start second bridge requesting 14488 -> should fall back to 4458..4465
st1 := OverlayState(Config(tmpIni))
st2 := OverlayState(Config(tmpIni))
blocker := HostCompanionBridge()
fallbackBridge := HostCompanionBridge()
try {
    blocker.Start(cfg, st1, 14488, 58188)
    AssertTrue(blocker.running && blocker.boundTcpPort == 14488, "Blocker bridge binds test port 14488")

    fallbackBridge.Start(cfg, st2, 14488, 58189)
    AssertTrue(fallbackBridge.running && fallbackBridge.boundTcpPort >= 4458 && fallbackBridge.boundTcpPort <= 4465, "HostCompanionBridge falls back to 4458..4465 on port conflict")
    AssertTrue(st2.activeBridgePort == fallbackBridge.boundTcpPort, "OverlayState.activeBridgePort tracks boundTcpPort")

    uri := BuildHostPairingUri(cfg, ["192.168.1.50"], fallbackBridge.boundTcpPort)
    AssertTrue(InStr(uri, "&bp=" fallbackBridge.boundTcpPort), "BuildHostPairingUri advertises fallback boundTcpPort")
} finally {
    try fallbackBridge.Stop()
    try blocker.Stop()
    try st1.cfg.DeleteFile()
}

; 4. RunWindowsSetupProbes Firewall & UIPI checks via overrides
probeCfg := { EnableWS: true, AudioRoutingMode: 1, targetMicName: "Mic/Aux", ConferencingApp: "Zoom", ShowIndicator: true, IndicatorScale: 1.0 }
probePublicNoAdmin := RunWindowsSetupProbes(probeCfg, 0, {
    obsPortListening: true,
    audioMeterAvailable: true,
    lanIps: ["192.168.1.10"],
    bridgeSummary: { running: true, tcpPort: 4458, discoverPort: 4457 },
    firewallProfile: "Public",
    firewallBlocked: true,
    isAdmin: false
})
AssertTrue(probePublicNoAdmin.totalCount == 6 && probePublicNoAdmin.passedCount == 4, "Public firewall + non-admin leaves 4/6 passing")
AssertTrue(!probePublicNoAdmin.steps[5].ok && InStr(probePublicNoAdmin.steps[5].detail, "4458") && InStr(probePublicNoAdmin.steps[5].detail, "Public"), "Step 5 warns on Public firewall with active port")
AssertTrue(!probePublicNoAdmin.steps[6].ok && InStr(probePublicNoAdmin.steps[6].detail, "UIPI"), "Step 6 warns on non-Admin UIPI")

probePrivateAdmin := RunWindowsSetupProbes(probeCfg, 0, {
    obsPortListening: true,
    audioMeterAvailable: true,
    lanIps: ["192.168.1.10"],
    bridgeSummary: { running: true, tcpPort: 4456, discoverPort: 4457 },
    firewallProfile: "Private",
    firewallBlocked: false,
    isAdmin: true
})
AssertTrue(probePrivateAdmin.totalCount == 6 && probePrivateAdmin.passedCount == 6 && probePrivateAdmin.steps[5].ok && probePrivateAdmin.steps[6].ok, "Private firewall + Admin passes all 6 probes")

try FileAppend("PASS=" passed " FAIL=" failed "`n", "*")
ExitApp(failed > 0 ? 1 : 0)
