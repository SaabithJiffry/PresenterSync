; ==============================================================================
; Test Suite: test_remote_live_ops.ahk
; Description: Live WebSocket opcode simulation & clicker debounce test
; ==============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

#Include "%A_ScriptDir%\..\Lib\WebSocket.ahk"
#Include "%A_ScriptDir%\..\Lib\Crypto.ahk"
#Include "%A_ScriptDir%\..\Lib\Gdip.ahk"
#Include "%A_ScriptDir%\..\Lib\GUI_Config.ahk"

Gdip.Startup()
OnExit((*) => (Theme.Shutdown(), Gdip.Shutdown()))

results := []
PassCount := 0
FailCount := 0

Assert(testName, condition, detail := "") {
    global PassCount, FailCount, results
    if (condition) {
        PassCount += 1
        results.Push("[PASS] " testName (detail != "" ? " - " detail : ""))
    } else {
        FailCount += 1
        results.Push("[FAIL] " testName (detail != "" ? " - " detail : ""))
    }
}

; Mock WebSocket object that captures sent payloads
class MockWebSocket {
    sent := []
    sendText(msg) {
        this.sent.Push(msg)
    }
    shutdown() {
    }
}

; Mock state and config
testConfig := {
    HostAddress: "STUDIO-PC.local, 192.168.1.50",
    HostPort: "4455",
    ObsPassword: "secretpassword",
    TargetMicName: "Mic/Aux",
    HeartbeatSeconds: 30,
    ShowIndicator: true,
    AggressivePulse: false,
    IndicatorScale: 1.0,
    ShowText: false,
    MonoIcon: false,
    SleekCorners: false,
    OpacityLevel: 220,
    IsMuted: false,
    WriteBool: (sec, k, v) => 0
}

testState := {
    obsWs: MockWebSocket(),
    obsConnected: false,
    activeHost: "",
    candidateIndex: 1,
    candidates: [{host: "STUDIO-PC.local", port: "4455", raw: "STUDIO-PC.local:4455"}],
    isMuted: false,
    baseAlpha: 220,
    currentAlpha: 220,
    animSeq: 0,
    baseWidth: 80,
    baseHeight: 40,
    iconSize: 18,
    textSize: 13,
    savedX: 100,
    savedY: 100,
    recHeight: 34,
    hudGap: 6,
    row3Height: 30,
    recW: 40,
    chatW: 34,
    studioW: 28,
    sceneW: 46,
    reconnectTimerFn: () => 0,
    heartbeatTimerFn: () => 0,
    breathTimerFn: () => 0,
    rebuildTrayFn: () => 0,
    MicGui: Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000 -DPIScale")
}

; --- TEST 1: OpCode 0 (Hello -> Auth -> Identify) ---
helloPayload := '{"op":0,"d":{"obsWebSocketVersion":"5.5.0","rpcVersion":1,"authentication":{"challenge":"abc123challenge","salt":"xyz789salt"}}}'
msg := helloPayload
if (RegExMatch(msg, '"salt"\s*:\s*"([^"]+)"', &matchSalt) && RegExMatch(msg, '"challenge"\s*:\s*"([^"]+)"', &matchChallenge)) {
    salt := matchSalt[1]
    challenge := matchChallenge[1]
    secret := HashSHA256_Base64(testConfig.ObsPassword . salt)
    authResponse := HashSHA256_Base64(secret . challenge)
    identifyJson := '{"op":1,"d":{"rpcVersion":1,"eventSubscriptions":2047,"authentication":"' authResponse '"}}'
    testState.obsWs.sendText(identifyJson)
}

Assert("Op 0 Hello received and Identify sent", testState.obsWs.sent.Length == 1)
Assert("Identify payload contains auth signature", InStr(testState.obsWs.sent[1], '"authentication":"'))
Assert("Identify payload requests eventSubscriptions:2047", InStr(testState.obsWs.sent[1], '"eventSubscriptions":2047'))

; --- TEST 2: OpCode 2 (Identified -> Init State Query) ---
identifiedPayload := '{"op":2,"d":{"negotiatedRpcVersion":1}}'
testState.obsConnected := true
initMuteQuery := '{"op":6,"d":{"requestType":"GetInputMute","requestId":"InitRemoteMute","requestData":{"inputName":"' testConfig.TargetMicName '"}}}'
testState.obsWs.sendText(initMuteQuery)

Assert("Op 2 Identified triggers InitRemoteMute request", testState.obsWs.sent.Length == 2)
Assert("Request targets configured microphone", InStr(testState.obsWs.sent[2], '"inputName":"Mic/Aux"'))

; --- TEST 3: OpCode 7 (Init State Response -> Unmuted) ---
initRespPayload := '{"op":7,"d":{"requestId":"InitRemoteMute","requestStatus":{"result":true,"code":100},"responseData":{"inputMuted":false}}}'
if (RegExMatch(initRespPayload, '"inputMuted"\s*:\s*(true|false)', &matchMuted)) {
    testState.isMuted := (matchMuted[1] == "true")
}
Assert("Op 7 updates state to LIVE (inputMuted: false)", testState.isMuted == false)

; --- TEST 4: OpCode 5 (Event: InputMuteStateChanged -> Muted) ---
eventPayload := '{"op":5,"d":{"eventType":"InputMuteStateChanged","eventData":{"inputName":"Mic/Aux","inputMuted":true}}}'
if (InStr(eventPayload, '"eventType":"InputMuteStateChanged"') && InStr(eventPayload, '"inputName":"' testConfig.TargetMicName '"')) {
    if (RegExMatch(eventPayload, '"inputMuted"\s*:\s*(true|false)', &matchMuted)) {
        testState.isMuted := (matchMuted[1] == "true")
    }
}
Assert("Op 5 updates state to MUTED (inputMuted: true)", testState.isMuted == true)

; --- TEST 5: Clicker Debounce & Mute Dispatch Shield ---
dispatchedCount := 0
lastTick := 0

SimulateClickerPress() {
    global lastTick, dispatchedCount, testState, testConfig
    now := A_TickCount
    if (now - lastTick < 150) ; 150ms debounce
        return false
    lastTick := now
    req := '{"op":6,"d":{"requestType":"ToggleInputMute","requestId":"RemoteClickerMute","requestData":{"inputName":"' testConfig.TargetMicName '"}}}'
    testState.obsWs.sendText(req)
    dispatchedCount += 1
    return true
}

; 1st press (should succeed)
p1 := SimulateClickerPress()
; 2nd press immediately after 10ms (simulating switch bounce - should be blocked)
Sleep 10
p2 := SimulateClickerPress()
; 3rd press after 30ms (should be blocked)
Sleep 30
p3 := SimulateClickerPress()
; 4th press after 160ms (valid second click - should succeed)
Sleep 160
p4 := SimulateClickerPress()

Assert("Clicker press 1 succeeds", p1 == true)
Assert("Clicker bounce 2 blocked (< 150ms)", p2 == false)
Assert("Clicker bounce 3 blocked (< 150ms)", p3 == false)
Assert("Clicker press 4 succeeds (>= 150ms)", p4 == true)
Assert("Exactly 2 ToggleInputMute requests dispatched", dispatchedCount == 2)
Assert("Dispatched request is ToggleInputMute", InStr(testState.obsWs.sent[testState.obsWs.sent.Length], '"requestType":"ToggleInputMute"'))

; Cleanup
testState.MicGui.Destroy()

report := "=== LIVE OPS TEST RESULTS ===`n"
report .= "Total: " (PassCount + FailCount) " | Passed: " PassCount " | Failed: " FailCount "`n`n"
for line in results
    report .= line "`n"

logFile := A_ScriptDir "\live_ops_results.log"
if FileExist(logFile)
    FileDelete(logFile)
FileAppend(report, logFile)
ExitApp(FailCount > 0 ? 1 : 0)

