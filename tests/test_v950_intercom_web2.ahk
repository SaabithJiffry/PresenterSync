#Requires AutoHotkey v2.0
#SingleInstance Off
; ============================================================================
; test_v950_intercom_web2.ahk - M5.1 Two-Way Stage Intercom, Targeted Routing & ACK
; ============================================================================

SetWorkingDir A_ScriptDir "\.."

#Include ..\Lib\WebSocket.ahk
#Include ..\Lib\UIA.ahk
#Include ..\Lib\Crypto.ahk
#Include ..\Lib\JsonCodec.ahk
#Include ..\Lib\RemoteBridgeClient.ahk
#Include ..\Lib\Gdip.ahk
#Include ..\Lib\SessionTimeline.ahk
#Include ..\Lib\OBS_Network.ahk
#Include ..\Lib\GUI_Config.ahk
#Include ..\Lib\HostBridge.ahk
#Include ..\Lib\HudRenderer.ahk

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
    hb := HostCompanionBridge()
    hb.cfg := { EnableWS: false, AudioRoutingMode: 2, targetMicName: "Mic/Aux", HostUuid: "uuid-m51" }
    hb.state := { isMuted: false, recState: 0, suppressNudgeBanners: true, presenterSignals: [] }
    hb.running := true

    rxByDev := Map("dev-a", [], "dev-b", [], "dev-dir", [])
    hb.DefineProp("_QueueWsFrame", { Call: (this, cli, op, payload) => (rxByDev.Has(cli.deviceId) ? rxByDev[cli.deviceId].Push(payload) : 0) })
    hb.DefineProp("_FlushSendQueue", { Call: (this, cli) => true })

    cA := { sock: 0, kind: "ws", authenticated: true, deviceId: "dev-a", deviceName: "Board A", platform: "Android", role: "Presenter", trustTier: "Pinned Room", allowDirectObsFallback: false, inputPaused: false, expiresAt: 0, lastRxTick: A_TickCount, cmdCache: Map() }
    cB := { sock: 0, kind: "ws", authenticated: true, deviceId: "dev-b", deviceName: "Phone B", platform: "Web", role: "Presenter", trustTier: "Ephemeral Guest", allowDirectObsFallback: false, inputPaused: false, expiresAt: 0, lastRxTick: A_TickCount, cmdCache: Map() }
    cD := { sock: 0, kind: "ws", authenticated: true, deviceId: "dev-dir", deviceName: "Director", platform: "Windows", role: "Director", trustTier: "Pinned Room", allowDirectObsFallback: true, inputPaused: false, expiresAt: 0, lastRxTick: A_TickCount, cmdCache: Map() }
    hb.clients := Map("1", cA, "2", cB, "3", cD)

    ; 1. Targeted Stage-Out routing -> only dev-a receives it
    rxByDev["dev-a"] := [], rxByDev["dev-b"] := [], rxByDev["dev-dir"] := []
    sent := hb.BroadcastStageNudge(hb.cfg, hb.state, "Check mic", "Host", "F59E0B", { nudgeId: "n-target-1", targetDeviceId: "dev-a", urgency: "urgent", requiresAck: true })
    AssertEq(sent, 1, "Targeted nudge should reach exactly 1 device")
    AssertEq(rxByDev["dev-a"].Length, 1, "dev-a receives targeted nudge")
    AssertEq(rxByDev["dev-b"].Length, 0, "dev-b does NOT receive dev-a targeted nudge")
    AssertTrue(InStr(rxByDev["dev-a"][1], '"requiresAck":true') > 0, "Urgent nudge sets requiresAck=true")
    AssertEq(hb.nudgeStatusMap["n-target-1"].status, "Delivered", "nudgeStatusMap tracks Delivered")

    ; 2. Origin echo exclusion when Director sends Stage-Out to All
    rxByDev["dev-a"] := [], rxByDev["dev-b"] := [], rxByDev["dev-dir"] := []
    hb._HandleWsTextMessage(cD, '{"type":"stage_nudge","cmdId":"c-dir-1","nudgeId":"n-all-1","direction":"stage_out","targetDeviceId":"All","message":"2 min left"}')
    ; Note: BroadcastHostStageNudge uses g_HostCompanionBridge; direct BroadcastStageNudge with originDeviceId:
    rxByDev["dev-a"] := [], rxByDev["dev-b"] := [], rxByDev["dev-dir"] := []
    sent2 := hb.BroadcastStageNudge(hb.cfg, hb.state, "2 min left", "Director", "F59E0B", { nudgeId: "n-all-2", targetDeviceId: "All", originDeviceId: "dev-dir" })
    AssertEq(sent2, 2, "Broadcast excluding origin reaches 2 other clients")
    AssertEq(rxByDev["dev-dir"].Length, 0, "Origin device dev-dir must NOT receive echo")

    ; 3. Got It ACK transitions status Delivered -> Ack'd
    hb._HandleWsTextMessage(cA, '{"type":"nudge_ack","cmdId":"ack-1","nudgeId":"n-target-1","status":"got_it"}')
    AssertEq(hb.nudgeStatusMap["n-target-1"].status, "Ack'd", "nudge_ack transitions status to Ack'd")
    AssertEq(hb.nudgeStatusMap["n-target-1"].ackedBy[1], "Board A", "ackedBy records Board A")

    ; 4. Stage-Back Presenter Signal routes to Primary Controller Inbox without echoing to other remotes
    rxByDev["dev-a"] := [], rxByDev["dev-b"] := [], rxByDev["dev-dir"] := []
    hb._HandleWsTextMessage(cA, '{"type":"stage_nudge","cmdId":"sb-1","nudgeId":"n-sb-1","direction":"stage_back","message":"Need Tech Help","urgency":"urgent"}')
    AssertEq(hb.state.presenterSignals.Length, 1, "Stage-Back signal queued in state.presenterSignals")
    AssertEq(hb.state.presenterSignals[1].message, "Need Tech Help", "Stage-Back signal text preserved")
    AssertEq(rxByDev["dev-b"].Length, 0, "Stage-Back signal must NOT echo to other Presenter remotes")

    ; 5. M5.2 Priority Alert Queue & Last-10 Cue History
    global g_StageNudgeQueue, g_StageNudgeHistory, g_StageNudgeActiveMsg
    g_StageNudgeQueue := [], g_StageNudgeHistory := []
    HideStageNudgeBanner(false)

    ShowStageNudgeBanner("Stream Dropped!", "EF4444", 0, "Watchdog", 1)
    AssertEq(g_StageNudgeActiveMsg, "Stream Dropped!", "CRITICAL alert displays immediately")
    ShowStageNudgeBanner("Manual Whisper", "F59E0B", 0, "Director", 0)
    AssertEq(g_StageNudgeActiveMsg, "Stream Dropped!", "Manual nudge MUST NOT clobber active CRITICAL alert")
    AssertEq(g_StageNudgeQueue.Length, 1, "Manual nudge queued behind CRITICAL alert")

    HideStageNudgeBanner(true)
    AssertEq(g_StageNudgeActiveMsg, "Manual Whisper", "Dismissing CRITICAL alert pops queued manual nudge")
    HideStageNudgeBanner(false)

    Loop 12
        ShowStageNudgeBanner("Hist-" A_Index, "F59E0B", 0, "Host", 0)
    HideStageNudgeBanner(false)
    hist := GetStageNudgeHistory()
    AssertEq(hist.Length, 10, "GetStageNudgeHistory caps at Last-10 cues")
    AssertEq(hist[10].message, "Hist-12", "History retains newest cue")

} catch as err {
    g_Failed++
    g_FailMessages.Push("UNCAUGHT EXCEPTION: " err.Message " (" err.File ":" err.Line ")")
}

if (g_Failed > 0) {
    for _, m in g_FailMessages
        FileAppend(m "`n", "*")
    FileAppend("M5.1 Intercom Summary: " g_Passed " passed, " g_Failed " failed.`n", "*")
    ExitApp(1)
}

FileAppend("M5.1 Intercom Summary: " g_Passed " passed, 0 failed.`n", "*")
ExitApp(0)
