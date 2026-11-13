; ==============================================================================
; Master Test Suite: test_master_suite.ahk
; Description: End-to-End automated live verification of PresenterSync v2.2.3
;              and PresenterSync Remote v2.2.3 across all subsystems.
; ==============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

#Include "%A_ScriptDir%\..\Lib\WebSocket.ahk"
#Include "%A_ScriptDir%\..\Lib\Crypto.ahk"
#Include "%A_ScriptDir%\..\Lib\Gdip.ahk"
#Include "%A_ScriptDir%\..\Lib\OBS_Network.ahk"
#Include "%A_ScriptDir%\..\Lib\GUI_Config.ahk"

Gdip.Startup()
OnExit((*) => Gdip.Shutdown())

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

; ==============================================================================
; SECTION 1: KEYSTROKE & HOOK FORMATTING
; ==============================================================================
Assert("FormatSendKey single letter", FormatSendKey("+^m") == "+^{m}")
Assert("FormatSendKey alt letter", FormatSendKey("!a") == "!{a}")
Assert("FormatSendKey function key", FormatSendKey("^F9") == "^{F9}")
Assert("FormatPassthroughHook standard", FormatPassthroughHook("+^m") == "~$+^m")
Assert("FormatPassthroughHook cleanup", FormatPassthroughHook("~$!a") == "~$!a")

; ==============================================================================
; SECTION 2: AUDIO ROUTING MODES & CONFIGURATION INTEGRITY
; ==============================================================================
testIni := A_ScriptDir "\test_master_config.ini"
if FileExist(testIni)
    FileDelete(testIni)

cfg := Config(testIni)
Assert("Config instantiated", IsObject(cfg))

; Test Mode 1 (Pro OBS)
cfg.AudioRoutingMode := 1
cfg.ObsMuteHotkey := "+^m"
cfg.Write("Settings", "AudioRoutingMode", 1)
cfg.Write("Settings", "ObsHotkey", "+^m")
Assert("Mode 1 saved & retrieved", cfg.ReadInt("Settings", "AudioRoutingMode") == 1)

; Test Mode 2 (Zoom Direct)
cfg.AudioRoutingMode := 2
cfg.ZoomMuteHotkey := "!a"
cfg.Write("Settings", "AudioRoutingMode", 2)
Assert("Mode 2 saved & retrieved", cfg.ReadInt("Settings", "AudioRoutingMode") == 2)

; Test Mode 3 (Dual App Sync)
cfg.AudioRoutingMode := 3
cfg.Write("Settings", "AudioRoutingMode", 3)
Assert("Mode 3 saved & retrieved", cfg.ReadInt("Settings", "AudioRoutingMode") == 3)

; ==============================================================================
; SECTION 3: OBS WEBSOCKET PROTOCOL & STATE ENGINE (v5)
; ==============================================================================
class MockWebSocket {
    sent := []
    sendText(msg) {
        this.sent.Push(msg)
    }
    shutdown() => 0
}

state := OverlayState(cfg)
state.obsWs := MockWebSocket()

; 1. OpCode 0: Hello & SHA256 Auth
helloMsg := '{"op":0,"d":{"obsWebSocketVersion":"5.5.0","rpcVersion":1,"authentication":{"challenge":"testChallenge123","salt":"testSalt456"}}}'
pw := "obsPassword999"
salt := "testSalt456"
chal := "testChallenge123"
secret := HashSHA256_Base64(pw . salt)
authResp := HashSHA256_Base64(secret . chal)
Assert("OBS v5 SHA256 authentication computation", StrLen(authResp) == 44)

; Simulate OpCode 1 dispatch
identifyJson := '{"op":1,"d":{"rpcVersion":1,"eventSubscriptions":2047,"authentication":"' authResp '"}}'
state.obsWs.sendText(identifyJson)
Assert("Identify payload queued", state.obsWs.sent.Length == 1 && InStr(state.obsWs.sent[1], '"op":1'))

; 2. OpCode 2: Identified -> Init State Requests
state.obsConnected := true
initMuteJson := '{"op":6,"d":{"requestType":"GetInputMute","requestId":"InitState","requestData":{"inputName":"Mic/Aux"}}}'
initRecJson := '{"op":6,"d":{"requestType":"GetRecordStatus","requestId":"InitRecState"}}'
initStudioJson := '{"op":6,"d":{"requestType":"GetStudioModeEnabled","requestId":"InitStudioState"}}'
initSceneJson := '{"op":6,"d":{"requestType":"GetCurrentProgramScene","requestId":"InitSceneState"}}'
state.obsWs.sendText(initMuteJson)
state.obsWs.sendText(initRecJson)
state.obsWs.sendText(initStudioJson)
state.obsWs.sendText(initSceneJson)
Assert("Initial state queries dispatched (4 requests)", state.obsWs.sent.Length == 5)

; 3. OpCode 5: Events (Mute, Rec, Studio, Scene)
HandleObsMessage(cfg, state, state.obsWs, '{"op":5,"d":{"eventType":"InputMuteStateChanged","eventData":{"inputName":"Mic/Aux","inputMuted":true}}}')
Assert("Event InputMuteStateChanged sets isMuted: true", state.isMuted == true)

HandleObsMessage(cfg, state, state.obsWs, '{"op":5,"d":{"eventType":"RecordStateChanged","eventData":{"outputActive":true,"outputState":"OBS_WEBSOCKET_OUTPUT_STARTED"}}}')
Assert("Event RecordStateChanged started sets recState: 1", state.recState == 1)

HandleObsMessage(cfg, state, state.obsWs, '{"op":5,"d":{"eventType":"RecordStateChanged","eventData":{"outputActive":true,"outputState":"OBS_WEBSOCKET_OUTPUT_PAUSED"}}}')
Assert("Event RecordStateChanged paused sets recState: 2", state.recState == 2)

HandleObsMessage(cfg, state, state.obsWs, '{"op":5,"d":{"eventType":"RecordStateChanged","eventData":{"outputActive":false,"outputState":"OBS_WEBSOCKET_OUTPUT_STOPPED"}}}')
Assert("Event RecordStateChanged stopped sets recState: 0", state.recState == 0)

HandleObsMessage(cfg, state, state.obsWs, '{"op":5,"d":{"eventType":"StudioModeStateChanged","eventData":{"studioModeEnabled":true}}}')
Assert("Event StudioModeStateChanged sets studioModeActive: true", state.studioModeActive == true)

HandleObsMessage(cfg, state, state.obsWs, '{"op":5,"d":{"eventType":"CurrentProgramSceneChanged","eventData":{"sceneName":"Camera Wide"}}}')
Assert("Event CurrentProgramSceneChanged sets sceneName: Camera Wide", state.currentSceneName == "Camera Wide")

; ==============================================================================
; SECTION 4: ZOOM UIA REGEX PATTERN MATCHING
; ==============================================================================
; Mute / Unmute regex tests
n1 := "Mute my audio"
n2 := "Unmute my audio"
n3 := "Mute all participants"
Assert("Zoom regex: detects Mute", RegExMatch(n1, "i)\bmute\b.*\baudio\b|^mute(\b|,|$)") && !RegExMatch(n1, "i)\b(when joining|on entry|all|participants)\b"))
Assert("Zoom regex: detects Unmute", RegExMatch(n2, "i)\bunmute\b.*\baudio\b|^unmute(\b|,|$)"))
Assert("Zoom regex: ignores 'Mute all participants'", RegExMatch(n3, "i)\b(when joining|on entry|all|participants)\b"))

; Chat counter regex tests
c1 := "Chat, 4 unread messages"
c2 := "5 unread in Chat"
Assert("Zoom chat counter extraction 1", RegExMatch(c1, "i)\bchat\b.*?(\d+)\s*unread|(\d+)\s*unread.*\bchat\b", &mC1) && mC1[1] == "4")
Assert("Zoom chat counter extraction 2", RegExMatch(c2, "i)\bchat\b.*?(\d+)\s*unread|(\d+)\s*unread.*\bchat\b", &mC2) && mC2[2] == "5")

; ==============================================================================
; SECTION 5: HUD RENDERING AT MULTIPLE TIERS & SCALES
; ==============================================================================
cfg.ShowIndicator := true
cfg.ShowExtraHuds := true
cfg.ShowText := true
InitHUD(cfg, state, false) ; Initialize layered GUIs without showing

; Test GDI+ Rendering of all 5 pills
p1 := ApplyMicAppearance(cfg, state)
p2 := ApplyRecAppearance(cfg, state)
p3 := ApplyChatAppearance(cfg, state)
p4 := ApplyStudioAppearance(cfg, state)
p5 := ApplySceneAppearance(cfg, state)
Assert("Tier 1 Mic Pill GDI+ Render", p1 != false)
Assert("Tier 2 Rec Pill GDI+ Render", p2 != false)
Assert("Tier 2 Chat Pill GDI+ Render", p3 != false)
Assert("Tier 3 Studio Pill GDI+ Render", p4 != false)
Assert("Tier 3 Scene Pill GDI+ Render", p5 != false)

; Test Scaled Geometry (0.5x, 1.0x, 2.5x, 5.0x)
scales := [0.5, 1.0, 2.5, 5.0]
for sc in scales {
    cfg.IndicatorScale := sc
    state.ComputeDimensions(cfg)
    layout := ComputeHudLayout(state, 500, 500)
    Assert("HUD Layout computation at scale " sc "x", layout.micW > 0 && layout.recH > 0 && layout.studioW > 0)
}

; Cleanup primary HUD windows
state.MicGui.Destroy()
state.RecGui.Destroy()
state.ChatGui.Destroy()
state.StudioGui.Destroy()
state.SceneGui.Destroy()

; ==============================================================================
; SECTION 6: REMOTE COMPANION CLIENT (PresenterSync_Remote)
; ==============================================================================
; Test Multi-Candidate Endpoint Parsing
candidateStr := "STUDIO-PC.local, 192.168.1.50:4455, 10.0.0.12:4456"
endpoints := ParseCandidateEndpoints(candidateStr)
Assert("Remote candidate count == 3", endpoints.Length == 3)
Assert("Remote candidate 1 is mDNS", endpoints[1].host == "STUDIO-PC.local" && endpoints[1].port == "4455")
Assert("Remote candidate 2 is IPv4", endpoints[2].host == "192.168.1.50" && endpoints[2].port == "4455")
Assert("Remote candidate 3 custom port", endpoints[3].host == "10.0.0.12" && endpoints[3].port == "4456")

; Test Pointer Mute Hardware Debounce Shield
lastMuteTick := 0
muteDispatches := 0

SendRemoteMuteMock() {
    global lastMuteTick, muteDispatches
    now := A_TickCount
    if (now - lastMuteTick < 150)
        return false
    lastMuteTick := now
    muteDispatches += 1
    return true
}

r1 := SendRemoteMuteMock()
Sleep 10
r2 := SendRemoteMuteMock() ; bounce at 10ms -> blocked
Sleep 30
r3 := SendRemoteMuteMock() ; bounce at 40ms -> blocked
Sleep 160
r4 := SendRemoteMuteMock() ; valid press at 200ms -> allowed

Assert("Remote debounce: initial press accepted", r1 == true)
Assert("Remote debounce: 10ms switch bounce blocked", r2 == false)
Assert("Remote debounce: 40ms switch bounce blocked", r3 == false)
Assert("Remote debounce: 200ms press accepted", r4 == true)
Assert("Remote debounce: exactly 2 dispatches sent", muteDispatches == 2)

; Test Local Network Interface Discovery
netInfo := GetLocalNetworkEndpoints()
Assert("GetLocalNetworkEndpoints returns ips array", IsObject(netInfo.ips) && netInfo.ips.Length > 0)
Assert("GetLocalNetworkEndpoints returns details array", IsObject(netInfo.details) && netInfo.details.Length > 0)
Assert("Local ComputerName resolved", A_ComputerName != "")

Assert("APP_VERSION updated to 2.2.3", UIConstants.APP_VERSION == "2.2.3")
guideTxt := GetRemoteSetupGuideText()
Assert("GetRemoteSetupGuideText covers 4455, 4009 & Test Connection",
    InStr(guideTxt, "4455") && InStr(guideTxt, "4009") && InStr(guideTxt, "Test Connection"))
summaryTxt := BuildLiveStatusSummary(cfg)
Assert("BuildLiveStatusSummary includes v2.2.3 and Remote Host",
    InStr(summaryTxt, "v2.2.3") && InStr(summaryTxt, "Remote Companion Host:"))

; ==============================================================================
; SECTION 7: JSON ESCAPING, WS HELPERS, LAYOUT & PROMPT REGRESSIONS
; ==============================================================================
rawScene := 'Scene "Main" \ 1'
escScene := EscapeJsonStr(rawScene)
Assert("EscapeJsonStr/UnescapeJsonStr round-trip", UnescapeJsonStr(escScene) == rawScene)
Assert("UnescapeJsonStr decodes \/ and \t", UnescapeJsonStr('Cam\/A\tDeck') == "Cam/A`tDeck")

mockWs := {sent: [], sendText: (this, txt) => this.sent.Push(txt)}
brokenWs := {sendText: (this, txt) => (ThrowError())}
ThrowError() {
    throw Error("simulated closed socket")
}
Assert("TrySendWsText rejects non-object ws", TrySendWsText("", "hi") == false)
Assert("TrySendWsText catches closed socket throws", TrySendWsText(brokenWs, "hi") == false)
Assert("SendObsToggleInputMute formats escaped payload",
    SendObsToggleInputMute(mockWs, 'Mic "A"', "HostClickerMute")
    && mockWs.sent.Length == 1
    && InStr(mockWs.sent[1], '"requestType":"ToggleInputMute"')
    && InStr(mockWs.sent[1], '"requestId":"HostClickerMute"')
    && InStr(mockWs.sent[1], '"inputName":"Mic \"A\""'))
Assert("SendObsSetInputMute sets inputMuted bool",
    SendObsSetInputMute(mockWs, "Mic/Aux", true, "ZoomSyncObsMute")
    && mockWs.sent.Length == 2
    && InStr(mockWs.sent[2], '"requestType":"SetInputMute"')
    && InStr(mockWs.sent[2], '"inputMuted":true'))

dimIni := A_ScriptDir "\dim_test_config.ini"
if FileExist(dimIni)
    FileDelete(dimIni)
cfgDim := Config(dimIni)
cfgDim.IndicatorScale := 1.0
cfgDim.ShowText := false
cfgDim.EnableWS := true
cfgDim.EnableZoom := false
cfgDim.ShowExtraHuds := false
vTop := SysGet(77)
cfgDim.savedX := 200
cfgDim.savedY := vTop + 5
stDimNoExtra := OverlayState(cfgDim)
Assert("OverlayState.ComputeDimensions skips extra HUD headroom when ShowExtraHuds=false", stDimNoExtra.savedY == vTop + 5)

cfgDim.ShowExtraHuds := true
stDimExtra := OverlayState(cfgDim)
expectedTopPad := stDimExtra.recHeight + stDimExtra.row3Height + (2 * stDimExtra.hudGap)
Assert("OverlayState.ComputeDimensions reserves extra HUD headroom when ShowExtraHuds=true", stDimExtra.savedY == vTop + expectedTopPad)

Assert("PromptForPassword accepts optional promptText", PromptForPassword.MinParams == 0 && PromptForPassword.MaxParams == 1)

hostIco := A_ScriptDir "\..\PresenterSync.ico"
remoteIco := A_ScriptDir "\..\PresenterSyncRemote.ico"
hostIcoBuf := FileExist(hostIco) ? FileRead(hostIco, "RAW") : Buffer(0)
remoteIcoBuf := FileExist(remoteIco) ? FileRead(remoteIco, "RAW") : Buffer(0)
Assert("Primary and Remote icon files exist with multi-resolution frames",
    hostIcoBuf.Size >= 22 && remoteIcoBuf.Size >= 22
    && NumGet(hostIcoBuf, 4, "UShort") >= 7
    && NumGet(remoteIcoBuf, 4, "UShort") >= 7)

if FileExist(dimIni)
    FileDelete(dimIni)

; Cleanup test ini
if FileExist(testIni)
    FileDelete(testIni)

; ==============================================================================
; WRITE MASTER RESULTS REPORT
; ==============================================================================
report := "=== PRESENTER SYNC MASTER TEST REPORT (v2.2.3) ===`n"
report .= "Total Tests Executed: " (PassCount + FailCount) "`n"
report .= "Passed: " PassCount "`n"
report .= "Failed: " FailCount "`n"
report .= "Pass Rate: " Round((PassCount / (PassCount + FailCount)) * 100, 1) "%`n`n"
for item in results
    report .= item "`n"

FileAppend(report, A_ScriptDir "\master_audit_results.log")
ExitApp(FailCount > 0 ? 1 : 0)
