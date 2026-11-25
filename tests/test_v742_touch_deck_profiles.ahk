; ==============================================================================
; Test Suite: test_v742_touch_deck_profiles.ahk
; Description: Verifies v7.4.2 GetRemoteConnectionModeLabel, ParsePairingUri,
;              and Saved Host Profiles (save/load/list/apply/delete).
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

; 1. GetRemoteConnectionModeLabel across Bridge, Direct OBS, WAN, and Disconnected
AssertTrue(GetRemoteConnectionModeLabel({ obsConnected: false }) = "Disconnected", "Mode label Disconnected when obsConnected=false")
AssertTrue(GetRemoteConnectionModeLabel({ obsConnected: true, usingBridge: true, usingDirectObsFallback: false, usingRelayFallback: false }) = "Host Bridge :4456", "Mode label Host Bridge :4456")
AssertTrue(GetRemoteConnectionModeLabel({ obsConnected: true, usingBridge: false, usingDirectObsFallback: true, usingRelayFallback: false }) = "Direct OBS :4455", "Mode label Direct OBS :4455")
AssertTrue(GetRemoteConnectionModeLabel({ obsConnected: true, usingBridge: false, usingDirectObsFallback: false, usingRelayFallback: true }) = "WAN Relay", "Mode label WAN Relay")

; 2. ParsePairingUri
lanUri := "presentersync://pair?host=192.168.10.5&bp=4458&code=K7M-9P2&obsPort=4455&obsPass=My%20Pass%21%261"
pLan := ParsePairingUri(lanUri)
AssertTrue(pLan.ok == true && pLan.host = "192.168.10.5" && pLan.bridgePort = "4458" && pLan.code = "K7M-9P2" && pLan.obsPort = "4455" && pLan.obsPass = "My Pass!&1", "ParsePairingUri parses LAN URI + bp=4458 + URL-encoded obsPass")

wanUri := "presentersync://pair?wan=ABCD-1234"
pWan := ParsePairingUri(wanUri)
AssertTrue(pWan.ok == true && pWan.wanCode = "ABCD-1234" && pWan.host = "", "ParsePairingUri parses WAN URI")

pBadScheme := ParsePairingUri("https://example.com/?host=1.2.3.4")
AssertTrue(pBadScheme.ok == false, "ParsePairingUri rejects non-presentersync:// URI")

pEmpty := ParsePairingUri("presentersync://pair?")
AssertTrue(pEmpty.ok == false, "ParsePairingUri rejects URI missing host/code/wan")

; 3. Saved Host Profiles save/load/list/apply/delete roundtrip
tmpIni := A_Temp "\PresenterSync_v742_prof_" A_TickCount ".ini"
if FileExist(tmpIni)
    FileDelete(tmpIni)
if FileExist(tmpIni ".bak")
    FileDelete(tmpIni ".bak")

cfg := Config(tmpIni)
AssertTrue(LoadSavedHostProfiles(cfg).Length == 0, "LoadSavedHostProfiles starts empty")

okSave1 := SaveHostProfile(cfg, "Hall A", { host: "10.0.0.10", bridgePort: "4456", obsPort: "4455", code: "AAA-111", wanCode: "", obsPass: "sec&1", networkMode: "LAN" })
okSave2 := SaveHostProfile(cfg, "Hall B", { host: "", bridgePort: "4458", obsPort: "4455", code: "", wanCode: "WAN-999", obsPass: "", networkMode: "Internet" })
AssertTrue(okSave1 && okSave2, "SaveHostProfile persists two room profiles")

profs := LoadSavedHostProfiles(cfg)
AssertTrue(profs.Length == 2 && profs[1].name = "Hall A" && profs[1].obsPass = "sec&1" && profs[2].name = "Hall B" && profs[2].networkMode = "Internet", "LoadSavedHostProfiles restores both profiles with special chars")

cfg.SessionToken := "stale-token-999"
cfg.PairedHostUuid := "stale-uuid-999"
st := { lastRxTick: 12345, reconnecting: true, obsConnected: true, obsWs: "", reconnectCalls: 0 }
okApply := ApplyHostProfile(cfg, st, "Hall A")
AssertTrue(okApply == true && cfg.HostAddress = "10.0.0.10" && cfg.BridgePort == 4456 && cfg.SessionPairingCode = "AAA-111" && cfg.ObsPassword = "sec&1" && cfg.SessionToken = "" && cfg.PairedHostUuid = "" && st.lastRxTick == 0 && !st.reconnecting, "ApplyHostProfile updates config, clears stale token/uuid, and resets connection state")
AssertTrue(IniRead(tmpIni, "Connection", "HostAddress", "") = "10.0.0.10" && IniRead(tmpIni, "Settings", "HostAddress", "") = "", "ApplyHostProfile persists to [Connection] section")

; 4. ParseHostBridgeWsEvent parses M1.4 extended telemetry fields
rawBridgeEv := '{"type":"mute_state","isMuted":true,"osMicMutedDrift":true,"lowDiskWarnLevel":2,"lowDiskMb":256,"deadMicWarn":true,"quickNudges":["Hold","Wrap"],"slideIndex":3,"slideTotal":12,"slideTitle":"Agenda","slideNotes":"Say hi","obsConnected":true,"obsRecState":1,"confRecState":0,"recSourceTag":"OBS","conferencingApp":"Zoom","detectedConfApp":"Zoom","meetBgTabWarn":true}'
evParsed := ParseHostBridgeWsEvent(rawBridgeEv)
AssertTrue(IsObject(evParsed) && evParsed.osMicMutedDrift && evParsed.lowDiskWarnLevel == 2 && evParsed.lowDiskMb == 256 && evParsed.deadMicWarn && evParsed.quickNudges.Length == 2 && evParsed.slideIndex == 3 && evParsed.slideTotal == 12 && evParsed.slideTitle = "Agenda" && evParsed.slideNotes = "Say hi" && evParsed.obsConnected && evParsed.obsRecState == 1 && evParsed.recSourceTag = "OBS" && evParsed.meetBgTabWarn, "ParseHostBridgeWsEvent extracts all extended telemetry fields")

okDel := DeleteHostProfile(cfg, "Hall A")
AssertTrue(okDel == true && LoadSavedHostProfiles(cfg).Length == 1 && LoadSavedHostProfiles(cfg)[1].name = "Hall B", "DeleteHostProfile removes only target profile")

cfg.DeleteFile()

try FileAppend("PASS=" passed " FAIL=" failed "`n", "*")
ExitApp(failed > 0 ? 1 : 0)
