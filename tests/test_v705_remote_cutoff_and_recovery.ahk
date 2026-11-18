; ==============================================================================
; Test Suite: test_v705_remote_cutoff_and_recovery.ahk
; Description: Verifies v7.0.5 Issues #9, #11, #14:
;              EnableRemoteConnections & RemoteInfoHotkey persistence,
;              ApplyControlCenterSettings cutoff/restart of HostCompanionBridge,
;              HostBridge DEAD_CLIENT_TIMEOUT_MS == 55000 & duplicate-deviceId eviction,
;              and RemoteBridgeConstants PONG_TIMEOUT_MS == 2500 / WAKE_STALENESS_MS == 25000.
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
OnExit((*) => StopHostCompanionBridge())

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

; 1. Config persistence & GetProfileFieldSpecs() for EnableRemoteConnections & RemoteInfoHotkey
tmpIni := A_Temp "\PresenterSync_v705_test_" A_TickCount ".ini"
if FileExist(tmpIni)
    FileDelete(tmpIni)

cfg := Config(tmpIni)
AssertTrue(cfg.EnableRemoteConnections == true, "EnableRemoteConnections defaults to true")
AssertTrue(cfg.RemoteInfoHotkey = "None", "RemoteInfoHotkey defaults to None")

cfg.EnableRemoteConnections := false
cfg.RemoteInfoHotkey := "^+q"
cfg.WriteBool("Settings", "EnableRemoteConnections", false)
cfg.Write("Settings", "RemoteInfoHotkey", "^+q")

cfgReloaded := Config(tmpIni)
AssertTrue(cfgReloaded.EnableRemoteConnections == false, "Config persists EnableRemoteConnections=false")
AssertTrue(cfgReloaded.RemoteInfoHotkey = "^+q", "Config persists RemoteInfoHotkey=^+q")

specs := cfg.GetProfileFieldSpecs()
specKeys := Map()
for _, sp in specs
    specKeys[sp.prop] := true
AssertTrue(specKeys.Has("EnableRemoteConnections"), "GetProfileFieldSpecs includes EnableRemoteConnections")
AssertTrue(specKeys.Has("RemoteInfoHotkey"), "GetProfileFieldSpecs includes RemoteInfoHotkey")

; 2. ApplyControlCenterSettings cutoff (false -> stops bridge) and re-enable (true -> starts bridge)
cfg.BridgePort := 0 ; ephemeral port for clean loopback test
st := OverlayState(cfg)
okStart := ApplyControlCenterSettings(cfg, st, {
    EnableRemoteConnections: true,
    RemoteInfoHotkey: "!+r"
}, false)
AssertTrue(okStart == true && cfg.EnableRemoteConnections == true && cfg.RemoteInfoHotkey = "!+r", "ApplyControlCenterSettings enables EnableRemoteConnections and updates RemoteInfoHotkey")
AssertTrue(IsSet(g_HostCompanionBridge) && IsObject(g_HostCompanionBridge) && g_HostCompanionBridge.running, "HostCompanionBridge starts when EnableRemoteConnections=true")

okCutoff := ApplyControlCenterSettings(cfg, st, {
    EnableRemoteConnections: false
}, false)
AssertTrue(okCutoff == true && cfg.EnableRemoteConnections == false, "ApplyControlCenterSettings disables EnableRemoteConnections")
AssertTrue(!IsObject(g_HostCompanionBridge), "HostCompanionBridge stops and releases ports on cutoff")

okRestart := ApplyControlCenterSettings(cfg, st, {
    EnableRemoteConnections: true
}, false)
AssertTrue(okRestart == true && IsObject(g_HostCompanionBridge) && g_HostCompanionBridge.running, "HostCompanionBridge restarts when EnableRemoteConnections toggled back to true")
StopHostCompanionBridge()

; 3. HostBridge DEAD_CLIENT_TIMEOUT_MS == 55000 & duplicate-deviceId eviction
AssertTrue(HostBridgeConstants.DEAD_CLIENT_TIMEOUT_MS == 55000, "HostBridgeConstants.DEAD_CLIENT_TIMEOUT_MS is 55000")

b := HostCompanionBridge()
cOld := { key: "k1", sock: 0, kind: "ws", authenticated: true, deviceId: "dev-smartboard-1", ip: "192.168.1.50" }
cNew := { key: "k2", sock: 0, kind: "ws", authenticated: true, deviceId: "dev-smartboard-1", ip: "192.168.1.51" }
b.clients["k1"] := cOld
b.clients["k2"] := cNew
b._EvictStaleDeviceSockets(cNew, "dev-smartboard-1")
AssertTrue(!b.clients.Has("k1") && b.clients.Has("k2"), "_EvictStaleDeviceSockets evicts old duplicate-deviceId socket and keeps new socket")

; 4. RemoteBridgeConstants PONG_TIMEOUT_MS == 2500 & WAKE_STALENESS_MS == 25000
AssertTrue(RemoteBridgeConstants.PONG_TIMEOUT_MS == 2500, "RemoteBridgeConstants.PONG_TIMEOUT_MS is 2500")
AssertTrue(RemoteBridgeConstants.WAKE_STALENESS_MS == 25000, "RemoteBridgeConstants.WAKE_STALENESS_MS is 25000")

try FileDelete(tmpIni)
try FileAppend("PASS=" passed " FAIL=" failed "`n", "*")
ExitApp(failed > 0 ? 1 : 0)
