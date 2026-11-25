#Requires AutoHotkey v2.0
#SingleInstance Off
; ============================================================================
; test_v940_rbac.ahk - M4.1 3-Tier RBAC, Pinned Room Trust, Guest TTL & C3
; ============================================================================

SetWorkingDir A_ScriptDir "\.."

#Include ..\Lib\WebSocket.ahk
#Include ..\Lib\UIA.ahk
#Include ..\Lib\Crypto.ahk
#Include ..\Lib\JsonCodec.ahk
#Include ..\Lib\RemoteBridgeClient.ahk
#Include ..\Lib\Gdip.ahk
#Include ..\Lib\OBS_Network.ahk
#Include ..\Lib\GUI_Config.ahk
#Include ..\Lib\HostBridge.ahk

global g_Passed := 0
global g_Failed := 0
global g_FailMessages := []

AssertTrue(cond, msg) {
    global g_Passed, g_Failed, g_FailMessages
    if (cond)
        g_Passed++
    else {
        g_Failed++
        g_FailMessages.Push("FAIL: " msg)
    }
}

AssertEq(actual, expected, msg) {
    global g_Passed, g_Failed, g_FailMessages
    if (actual = expected)
        g_Passed++
    else {
        g_Failed++
        g_FailMessages.Push("FAIL: " msg " (expected='" String(expected) "', actual='" String(actual) "')")
    }
}

try {
    ; 1. Role & Permission helpers
    AssertEq(HostCompanionBridge.NormalizeRole("tally"), "Tally-Only", "NormalizeRole tally")
    AssertEq(HostCompanionBridge.NormalizeRole("director"), "Director", "NormalizeRole director")
    AssertEq(HostCompanionBridge.NormalizeRole("unknown"), "Presenter", "NormalizeRole default Presenter")
    AssertEq(HostCompanionBridge.NormalizeTrustTier("pinned"), "Pinned Room", "NormalizeTrustTier pinned")
    AssertEq(HostCompanionBridge.NormalizeTrustTier("guest"), "Ephemeral Guest", "NormalizeTrustTier guest")

    AssertTrue(!HostCompanionBridge.HasPermissionForCmd("Tally-Only", "toggle_mute"), "Tally-Only cannot mute")
    AssertTrue(HostCompanionBridge.HasPermissionForCmd("Tally-Only", "ping"), "Tally-Only can ping")
    AssertTrue(HostCompanionBridge.HasPermissionForCmd("Presenter", "toggle_mute"), "Presenter can mute")
    AssertTrue(HostCompanionBridge.HasPermissionForCmd("Presenter", "ppt_next"), "Presenter can ppt_next")
    AssertTrue(!HostCompanionBridge.HasPermissionForCmd("Presenter", "switch_scene"), "Presenter cannot switch_scene")
    AssertTrue(!HostCompanionBridge.HasPermissionForCmd("Presenter", "set_record"), "Presenter cannot set_record")
    AssertTrue(HostCompanionBridge.HasPermissionForCmd("Director", "switch_scene"), "Director can switch_scene")
    AssertTrue(HostCompanionBridge.HasPermissionForCmd("Director", "set_record"), "Director can set_record")

    ; 2. Paired device serialize/parse round-trip
    dev := {
        deviceId: "sb-room-1",
        deviceName: "Room 101 SmartBoard",
        platform: "Android",
        token: "tok-secret-123",
        pairedAt: "2026-11-25T12:00:00Z",
        ip: "192.168.1.50",
        transport: "ws",
        customName: true,
        role: "Director",
        trustTier: "Pinned Room",
        allowDirectObsFallback: true,
        paused: false,
        expiresAt: 0
    }
    ser := _HB_SerializePairedDevice(dev)
    parsed := _HB_ParsePairedDevice("sb-room-1", ser)
    AssertTrue(IsObject(parsed), "Parsed paired device should be object")
    AssertEq(parsed.role, "Director", "Round-trip role=Director")
    AssertEq(parsed.trustTier, "Pinned Room", "Round-trip trustTier=Pinned Room")
    AssertEq(parsed.allowDirectObsFallback, true, "Round-trip allowDirectObsFallback=true")
    AssertEq(parsed.token, "tok-secret-123", "Round-trip DPAPI token")

    ; Backward-compatible 8-part v1 line
    legacyVal := "v1|Legacy%20Phone|Android|" UriEncodeComponent(ConfigStore.ProtectSecret("tok-leg")) "|2026-01-01|10.0.0.5|ws|0"
    legParsed := _HB_ParsePairedDevice("leg-1", legacyVal)
    AssertEq(legParsed.role, "Presenter", "Legacy 8-part defaults to Presenter")
    AssertEq(legParsed.trustTier, "Ephemeral Guest", "Legacy 8-part defaults to Ephemeral Guest")
    AssertEq(legParsed.allowDirectObsFallback, false, "Legacy 8-part defaults allowDirectObsFallback=false")

    ; 3. C3 obsFallback.password withholding in _BuildAuthOkJson
    hb := HostCompanionBridge()
    hb.cfg := { EnableWS: true, AudioRoutingMode: 2, targetMicName: "Mic/Aux", obsPassword: "SuperSecretObsPass!", HostUuid: "uuid-1" }
    hb.cfg.DefineProp("WriteBool", { Call: (t, s, k, v) => true })
    hb.cfg.DefineProp("WriteBoolDeferred", { Call: (t, s, k, v, d := 250) => true })
    hb.state := { isMuted: false, recState: 0 }

    cPres := { sessionToken: "t1", role: "Presenter", trustTier: "Ephemeral Guest", allowDirectObsFallback: false }
    authPres := hb._BuildAuthOkJson(cPres)
    AssertTrue(!InStr(authPres, "SuperSecretObsPass!"), "C3: Presenter without opt-in MUST NOT receive obsPassword")
    AssertTrue(InStr(authPres, '"role":"Presenter"') > 0, "auth_ok includes role=Presenter")

    cPresOpt := { sessionToken: "t2", role: "Presenter", trustTier: "Pinned Room", allowDirectObsFallback: true }
    authPresOpt := hb._BuildAuthOkJson(cPresOpt)
    AssertTrue(InStr(authPresOpt, "SuperSecretObsPass!") > 0, "C3: Presenter with allowDirectObsFallback=true receives obsPassword")

    cDir := { sessionToken: "t3", role: "Director", trustTier: "Pinned Room", allowDirectObsFallback: false }
    authDir := hb._BuildAuthOkJson(cDir)
    AssertTrue(InStr(authDir, "SuperSecretObsPass!") > 0, "C3: Director always receives obsPassword")

    ; 4. Server-side RBAC enforcement in _HandleWsTextMessage (nack forbidden / input_paused / expired)
    sentFrames := []
    hb.DefineProp("_QueueWsFrame", { Call: (this, cli, opcode, payload) => sentFrames.Push(payload) })
    hb.DefineProp("_FlushSendQueue", { Call: (this, cli) => true })

    tallyCli := {
        sock: 0, kind: "ws", authenticated: true, deviceId: "tally-1", deviceName: "Tally",
        platform: "Web", role: "Tally-Only", trustTier: "Ephemeral Guest",
        allowDirectObsFallback: false, inputPaused: false, expiresAt: 0, lastRxTick: A_TickCount, cmdCache: Map()
    }
    sentFrames := []
    hb._HandleWsTextMessage(tallyCli, '{"type":"toggle_mute","cmdId":"c1"}')
    AssertTrue(sentFrames.Length >= 1 && InStr(sentFrames[1], '"type":"nack"') > 0 && InStr(sentFrames[1], '"forbidden"') > 0, "Tally-Only toggle_mute returns forbidden nack")

    presCli := {
        sock: 0, kind: "ws", authenticated: true, deviceId: "pres-1", deviceName: "Pres",
        platform: "Web", role: "Presenter", trustTier: "Ephemeral Guest",
        allowDirectObsFallback: false, inputPaused: false, expiresAt: 0, lastRxTick: A_TickCount, cmdCache: Map()
    }
    sentFrames := []
    hb._HandleWsTextMessage(presCli, '{"type":"switch_scene","sceneName":"Main","cmdId":"c2"}')
    AssertTrue(sentFrames.Length >= 1 && InStr(sentFrames[1], '"type":"nack"') > 0 && InStr(sentFrames[1], '"forbidden"') > 0, "Presenter switch_scene returns forbidden nack")

    presCli.inputPaused := true
    sentFrames := []
    hb._HandleWsTextMessage(presCli, '{"type":"toggle_mute","cmdId":"c3"}')
    AssertTrue(sentFrames.Length >= 1 && InStr(sentFrames[1], '"type":"nack"') > 0 && InStr(sentFrames[1], '"input_paused"') > 0, "Paused client returns input_paused nack")

    presCli.inputPaused := false
    presCli.expiresAt := GetCurrentUnixEpoch() - 10
    sentFrames := []
    hb._HandleWsTextMessage(presCli, '{"type":"toggle_mute","cmdId":"c4"}')
    AssertTrue(sentFrames.Length >= 1 && InStr(sentFrames[1], '"type":"auth_error"') > 0, "Expired guest returns auth_error")

    ; 5. RevokeEphemeralGuests keeps Pinned Room Smart Boards untouched
    hb.pairedDevices := Map()
    hb.validTokens := Map()
    hb.pairedDevices["pinned-sb"] := { deviceId: "pinned-sb", deviceName: "Board", platform: "Android", token: "tp", pairedAt: "x", ip: "1.1.1.1", transport: "ws", role: "Presenter", trustTier: "Pinned Room", allowDirectObsFallback: true, paused: false, expiresAt: 0, connected: false }
    hb.pairedDevices["guest-1"] := { deviceId: "guest-1", deviceName: "Guest", platform: "Web", token: "tg", pairedAt: "x", ip: "1.1.1.2", transport: "ws", role: "Presenter", trustTier: "Ephemeral Guest", allowDirectObsFallback: false, paused: false, expiresAt: 0, connected: false }
    hb.validTokens["tp"] := "pinned-sb"
    hb.validTokens["tg"] := "guest-1"

    revokedCnt := hb.RevokeEphemeralGuests()
    AssertEq(revokedCnt, 1, "RevokeEphemeralGuests should revoke 1 guest")
    AssertTrue(hb.pairedDevices.Has("pinned-sb"), "Pinned Room Smart Board must stay paired")
    AssertTrue(!hb.pairedDevices.Has("guest-1"), "Ephemeral Guest must be revoked")

    ; 6. M4.2 Action Attribution (lastActionActor) + FlashDevicePill + BroadcastObsFallbackUpdate C3
    presCli.expiresAt := 0
    presCli.inputPaused := false
    hb.state.lastActionActor := ""
    hb._HandleWsTextMessage(presCli, '{"type":"toggle_mute","cmdId":"c-attr-1"}')
    AssertEq(hb.state.lastActionActor, "Pres", "lastActionActor should be attributed to remote deviceName")
    msJson := hb._BuildMuteStateJson()
    AssertTrue(InStr(msJson, '"lastActionActor":"Pres"') > 0, "_BuildMuteStateJson should broadcast lastActionActor")

    hb.clients := Map("k1", presCli, "k2", tallyCli)
    sentFrames := []
    flashed := hb.FlashDevicePill("pres-1", 1500)
    AssertEq(flashed, 1, "FlashDevicePill should target matching deviceId")
    AssertTrue(sentFrames.Length == 1 && InStr(sentFrames[1], '"type":"flash_pill"') > 0, "FlashDevicePill sends flash_pill JSON")

    dirCli := {
        sock: 0, kind: "ws", authenticated: true, deviceId: "dir-1", deviceName: "DirectorTab",
        platform: "Android", role: "Director", trustTier: "Pinned Room",
        allowDirectObsFallback: false, inputPaused: false, expiresAt: 0, lastRxTick: A_TickCount, cmdCache: Map()
    }
    hb.clients := Map("k1", presCli, "k2", dirCli)
    sentFrames := []
    hb.running := true
    hb.BroadcastObsFallbackUpdate(hb.cfg)
    hb.running := false
    AssertEq(sentFrames.Length, 2, "BroadcastObsFallbackUpdate sends to 2 clients")
    AssertTrue(!InStr(sentFrames[1], "SuperSecretObsPass!") && InStr(sentFrames[2], "SuperSecretObsPass!") > 0, "BroadcastObsFallbackUpdate enforces C3 per client")

} catch as err {
    g_Failed++
    g_FailMessages.Push("UNCAUGHT EXCEPTION: " err.Message " (" err.File ":" err.Line ")")
}

if (g_Failed > 0) {
    for _, m in g_FailMessages
        FileAppend(m "`n", "*")
    FileAppend("M4.1 RBAC Summary: " g_Passed " passed, " g_Failed " failed.`n", "*")
    ExitApp(1)
}

FileAppend("M4.1 RBAC Summary: " g_Passed " passed, 0 failed.`n", "*")
ExitApp(0)
