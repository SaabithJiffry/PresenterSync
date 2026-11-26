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
    AssertTrue(HostCompanionBridge.HasPermissionForCmd("Presenter", "switch_scene"), "Presenter can switch_scene")
    AssertTrue(HostCompanionBridge.HasPermissionForCmd("Presenter", "transition_scene"), "Presenter can transition_scene")
    AssertTrue(HostCompanionBridge.HasPermissionForCmd("Presenter", "reset_active_scene"), "Presenter can reset_active_scene")
    AssertTrue(!HostCompanionBridge.HasPermissionForCmd("Presenter", "set_record"), "Presenter cannot set_record")
    AssertTrue(!HostCompanionBridge.HasPermissionForCmd("Presenter", "toggle_standby"), "Presenter cannot toggle_standby")
    AssertTrue(!HostCompanionBridge.HasPermissionForCmd("Presenter", "session_reset"), "Presenter cannot session_reset")
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
    hb.state := { isMuted: false, recState: 0, obsConnected: true, obsWs: { sendText: (this, m) => true }, currentSceneName: "Main" }

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
    AssertTrue(sentFrames.Length >= 1 && InStr(sentFrames[1], '"type":"ack"') > 0 && InStr(sentFrames[1], '"action":"switch_scene"') > 0, "Presenter switch_scene succeeds with ack (#3)")

    sentFrames := []
    hb._HandleWsTextMessage(presCli, '{"type":"set_record","recording":true,"cmdId":"c2b"}')
    AssertTrue(sentFrames.Length >= 1 && InStr(sentFrames[1], '"type":"nack"') > 0 && InStr(sentFrames[1], '"forbidden"') > 0, "Presenter set_record still returns forbidden nack")

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

    ; 7. M4.3 Modifier-Aware Hotkey Collision Detection
    AssertTrue(_DoHotkeysCollide("^!m", "!^M"), "M4.3: Reordered modifier chord ^!m collides with !^M")
    AssertTrue(!_DoHotkeysCollide("^!m", "m"), "M4.3: ^!m does NOT falsely collide with bare m")
    AssertTrue(!_DoHotkeysCollide("^b", "+b"), "M4.3: ^b does NOT falsely collide with +b")
    AssertTrue(_DoHotkeysCollide("F5", "$F5"), "M4.3: F5 collides with $F5")

    ; 8. v10.1.0 V2-M1: P0-2 BroadcastSessionReset, P0-4 URI C3, P1-1 Handoff aliases, P1-3 Turnover, P2-1 ObsWsPort, #1 Scene Reset, #3 no_target_scene
    hb.clients := Map("k1", presCli, "k2", dirCli)
    sentFrames := []
    resetSent := hb.BroadcastSessionReset()
    AssertEq(resetSent, 2, "P0-2: BroadcastSessionReset delivers session_reset to 2 authenticated WS clients")
    AssertTrue(sentFrames.Length = 2 && InStr(sentFrames[1], '"type":"session_reset"') > 0, "P0-2: session_reset frame emitted")

    uriNoPw := BuildHostPairingUri(hb.cfg, 4456)
    AssertTrue(!InStr(uriNoPw, "&pw="), "P0-4: BuildHostPairingUri omits &pw= even when obsPassword is configured")

    hb.cfg.ObsWsPort := 4499
    AssertEq(_HB_GetObsWsPort(hb.cfg), 4499, "P2-1: _HB_GetObsWsPort honors configured ObsWsPort=4499")
    hb.cfg.ObsWsPort := 4455

    ; #1 ExecuteHostResetActiveScene toggles ONLY sceneItemEnabled=true and restores original targetScene on mid-reset scene switch
    obsLog := []
    hb.cfg.EnableWS := true
    hb.cfg.SecondaryAudioSources := "Guest Mic"
    hb.state.obsConnected := true
    hb.state.obsWs := { sendText: (this, txt) => obsLog.Push(txt) }
    hb.state.currentSceneName := "SceneA"
    hb.state.studioModeActive := false
    hb.state.previewSceneName := ""
    hb.state.previousProgramScene := ""
    hb.state.sceneList := ["SceneA"]
    hb.state.obsTransitionFn := ""

    ; #3 no_target_scene NACK when OBS connected with single scene in non-Studio mode
    sentFrames := []
    hb._HandleWsTextMessage(presCli, '{"type":"transition_scene","cmdId":"c-no-tgt"}')
    AssertTrue(sentFrames.Length >= 1 && InStr(sentFrames[1], '"no_target_scene"') > 0, "#3: Single-scene transition returns no_target_scene instead of obs_offline")

    ; #1 Reset Active Scene flow
    sentFrames := []
    hb._HandleWsTextMessage(presCli, '{"type":"reset_active_scene","cmdId":"c-rst-1"}')
    AssertTrue(sentFrames.Length >= 1 && InStr(sentFrames[1], '"type":"ack"') > 0 && InStr(sentFrames[1], '"action":"reset_active_scene"') > 0, "#1: Presenter reset_active_scene sends ack")
    AssertTrue(obsLog.Length = 1 && InStr(obsLog[1], '"requestType":"GetSceneItemList"') > 0 && InStr(obsLog[1], '"sceneName":"SceneA"') > 0, "#1: Requested GetSceneItemList for SceneA")
    AssertTrue(!ExecuteHostResetActiveScene(hb.cfg, hb.state), "#1: Re-entrancy guard blocks concurrent reset while sceneResetInProgress")

    obsLog := []
    listResp := '{"op":7,"d":{"requestType":"GetSceneItemList","requestId":"ResetActiveSceneList","requestStatus":{"result":true,"code":100},"responseData":{"sceneItems":[{"sceneItemId":101,"sourceName":"Camera","sceneItemEnabled":true,"sceneItemTransform":{"alignment":5,"boundsHeight":0}},{"sceneItemId":102,"sourceName":"SecretNote","sceneItemEnabled":false,"sceneItemTransform":{"alignment":5}},{"sceneItemId":103,"sourceName":"Screen","sceneItemEnabled":true}]}}}'
    AssertTrue(_HandleResetActiveSceneItemList(hb.cfg, hb.state, listResp), "#1: _HandleResetActiveSceneItemList parsed nested JSON items")
    AssertEq(obsLog.Length, 2, "#1: Disabled ONLY the 2 enabled items (101 & 103), leaving hidden 102 untouched")
    AssertTrue(InStr(obsLog[1], '"sceneItemId":101') > 0 && InStr(obsLog[1], '"sceneItemEnabled":false') > 0 && InStr(obsLog[2], '"sceneItemId":103') > 0, "#1: Disabled ids 101 and 103")

    ; Simulate scene switching to SceneB during the 250ms wait -> must still re-enable on SceneA!
    hb.state.currentSceneName := "SceneB"
    obsLog := []
    tWait := A_TickCount
    while (hb.state.sceneResetInProgress && (A_TickCount - tWait < 1200))
        Sleep(25)
    AssertTrue(!hb.state.sceneResetInProgress, "#1: Reset cycle completed and unlocked")
    AssertEq(obsLog.Length, 2, "#1: Re-enabled both items after 250ms")
    AssertTrue(InStr(obsLog[1], '"sceneName":"SceneA"') > 0 && InStr(obsLog[1], '"sceneItemEnabled":true') > 0, "#1: Re-enabled on original targetScene SceneA even after switching to SceneB")

    ; P1-1 host / remote aliases
    obsLog := []
    AssertTrue(ExecuteHostAudioHandoff(hb.cfg, hb.state, "host"), "P1-1: ExecuteHostAudioHandoff accepts host alias")
    AssertTrue(ExecuteHostAudioHandoff(hb.cfg, hb.state, "remote"), "P1-1: ExecuteHostAudioHandoff accepts remote alias")

    ; P1-3 Session turnover clears slide metadata + presenterSignals + cachedSlidePreviewBuf
    hb.state.slideIndex := 4
    hb.state.slideTotal := 12
    hb.state.slideTitle := "Closing"
    hb.state.slideNotes := "Private speaker notes"
    hb.state.presenterSignals := [{ message: "Old cue" }]
    hb.cachedSlidePreviewBuf := Buffer(16, 0xAB)
    g_HostCompanionBridge := hb
    ExecuteHostSessionTurnover(hb.cfg, hb.state, false)
    AssertEq(hb.state.slideIndex, 0, "P1-3: Session turnover resets slideIndex")
    AssertEq(hb.state.slideTitle, "", "P1-3: Session turnover clears slideTitle")
    AssertEq(hb.state.slideNotes, "", "P1-3: Session turnover clears slideNotes")
    AssertEq(hb.state.presenterSignals.Length, 0, "P1-3: Session turnover clears presenterSignals")
    AssertTrue(!IsObject(hb.cachedSlidePreviewBuf), "P1-3: Session turnover clears cachedSlidePreviewBuf")

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
