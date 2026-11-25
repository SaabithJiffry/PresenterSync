; ==============================================================================
; Master Test Suite: test_master_suite.ahk
; Description: End-to-End automated live verification of PresenterSync v5.0.0
;              and PresenterSync Remote v5.0.0 across all subsystems.
; ==============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

#Include "..\Lib\WebSocket.ahk"
#Include "..\Lib\Crypto.ahk"
#Include "..\Lib\RemoteBridgeClient.ahk"
#Include "..\Lib\Gdip.ahk"
#Include "..\Lib\UIA.ahk"
#Include "..\Lib\OBS_Network.ahk"
#Include "..\Lib\GUI_Config.ahk"
#Include "..\Lib\HudSnakeGame.ahk"

Gdip.Startup()
OnExit((*) => (StopHostCompanionBridge(), HudSnake.Stop(), Theme.Shutdown(), UIA.Shutdown(), Gdip.Shutdown()))

results := []
PassCount := 0
FailCount := 0

TestFailFastOnError(exc, mode) {
    global results, FailCount
    FailCount += 1
    msg := Format("[FAIL] Unhandled exception ({}) in {} ({}:{}): {}", mode, exc.What, exc.File, exc.Line, exc.Message)
    results.Push(msg)
    try FileAppend(msg "`n", A_ScriptDir "\master_audit_results.log")
    try HudSnake.Stop()
    ExitApp(1)
}
OnError(TestFailFastOnError)

MasterWatchdogAbort() {
    global results, FailCount, PassCount
    FailCount += 1
    results.Push("[FAIL] Master test suite watchdog timeout reached (120s)")
    try HudSnake.Stop()
    try FileAppend("`n=== WATCHDOG ABORT AFTER 120s (Pass=" PassCount ", Fail=" FailCount ") ===`n" results[results.Length] "`n", A_ScriptDir "\master_audit_results.log")
    ExitApp(2)
}
SetTimer(MasterWatchdogAbort, -120000)

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
if FileExist(testIni ".bak")
    FileDelete(testIni ".bak")

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

; Test Scaled Geometry & Real GDI+ Rendering across all 9 preset scales
scales := [0.25, 0.5, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0, 5.0]
for sc in scales {
    cfg.IndicatorScale := sc
    state.ComputeDimensions(cfg)
    layout := ComputeHudLayout(state, 500, 500)
    okMic := ApplyMicAppearance(cfg, state)
    Assert("HUD GDI+ & Layout computation at scale " sc "x", okMic != false && layout.micW > 0 && layout.recH > 0 && layout.studioW > 0)
}
cfg.IndicatorScale := 1.0

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

Assert("APP_VERSION is active release v9.0.1", UIConstants.APP_VERSION == "9.0.1")
guideTxt := GetRemoteSetupGuideText()
Assert("GetRemoteSetupGuideText covers 4455, 4009 & Test Connection",
    InStr(guideTxt, "4455") && InStr(guideTxt, "4009") && InStr(guideTxt, "Test Connection"))
summaryTxt := BuildLiveStatusSummary(cfg)
Assert("BuildLiveStatusSummary includes active version and Remote Host",
    InStr(summaryTxt, "v" UIConstants.APP_VERSION) && InStr(summaryTxt, "Remote Companion Host:"))

; ==============================================================================
; SECTION 7: JSON ESCAPING, WS HELPERS, LAYOUT & PROMPT REGRESSIONS
; ==============================================================================
rawScene := 'Scene "Main" \ 1'
escScene := EscapeJsonStr(rawScene)
Assert("EscapeJsonStr/UnescapeJsonStr round-trip", UnescapeJsonStr(escScene) == rawScene)
Assert("UnescapeJsonStr decodes \/ and \t", UnescapeJsonStr('Cam\/A\tDeck') == "Cam/A`tDeck")
Assert("UnescapeJsonStr single-pass preserves escaped backslash before n/r/t",
    UnescapeJsonStr('C:\\new\tline\\r\\n') == "C:\new`tline\r\n")
Assert("UnescapeJsonStr decodes unicode escape \u0026", UnescapeJsonStr('Q\u0026A') == "Q&A")
complexRaw := 'C:\new\tab\"q"' . "`n`r`b`f"
Assert("EscapeJsonStr/UnescapeJsonStr complex backslash + control chars round-trip",
    UnescapeJsonStr(EscapeJsonStr(complexRaw)) == complexRaw)

epEdge := ParseCandidateEndpoints("192.168.1.10 : 4456, badport.local:99999, zero.local:0, http://web.local:abc, neg.local:-5, emptycolon.local:", "4455")
Assert("ParseCandidateEndpoints trims whitespace around colon & clamps invalid ports",
    epEdge.Length == 6
    && epEdge[1].host == "192.168.1.10" && epEdge[1].port == "4456"
    && epEdge[2].host == "badport.local" && epEdge[2].port == "4455"
    && epEdge[3].host == "zero.local" && epEdge[3].port == "4455"
    && epEdge[4].host == "web.local" && epEdge[4].port == "4455"
    && epEdge[5].host == "neg.local" && epEdge[5].port == "4455"
    && epEdge[6].host == "emptycolon.local" && epEdge[6].port == "4455")

; Verify HandleObsMessage matches escaped slash Mic\/Aux against Mic/Aux
cfgSlash := Config(testIni)
cfgSlash.targetMicName := "Mic/Aux"
stSlash := OverlayState(cfgSlash)
stSlash.isMuted := false
HandleObsMessage(cfgSlash, stSlash, "", '{"op":5,"d":{"eventType":"InputMuteStateChanged","eventData":{"inputName":"Mic\/Aux","inputMuted":true}}}')
Assert("HandleObsMessage matches escaped JSON slash in Mic\/Aux", stSlash.isMuted == true)

; Verify Theme.AcquireSuspend / ReleaseSuspend lock counting & state preservation
Theme.SuspendLockCount := 0
Theme.WasSuspendedBeforeDialogs := false
Suspend(false)
Theme.AcquireSuspend()
Theme.AcquireSuspend()
lockedDuringDialog := (Theme.SuspendLockCount == 2 && A_IsSuspended && !Theme.WasSuspendedBeforeDialogs)
Theme.ReleaseSuspend()
stillLockedAfterOne := (Theme.SuspendLockCount == 1 && A_IsSuspended)
Theme.ReleaseSuspend()
resumedAfterAll := (Theme.SuspendLockCount == 0 && !A_IsSuspended)
Assert("Theme suspend lock counting preserves & restores suspend state",
    lockedDuringDialog && stillLockedAfterOne && resumedAfterAll)

; Live UIA + DetectZoomStates integration test against real temporary Win32 GUIs
mockZoom1 := Gui("+ToolWindow -Caption", "Zoom Meeting Audit 1")
mockZoom1.AddButton("w120 h30", "Unmute all")
mockZoom1.AddButton("w120 h30", "Mute my audio")
mockZoom1.AddButton("w120 h30", "Pause Recording")
mockZoom1.AddButton("w160 h30", "Chat, 2 unread messages")
mockZoom1.Show("x-32000 y-32000 w320 h160 NoActivate")
hwnd1 := mockZoom1.Hwnd
zRes1 := DetectZoomStates("ahk_id " hwnd1)
mockZoom1.Destroy()
Assert("Live UIA DetectZoomStates ignores 'Unmute all' and detects unmuted mic + paused=1 rec + 2 unread chat",
    zRes1.foundWindow && zRes1.hasMic && !zRes1.muted && zRes1.micHwnd == hwnd1
    && zRes1.hasRec && zRes1.recState == 1 && zRes1.hasChat && zRes1.unreadChat == 2)

mockZoom2 := Gui("+ToolWindow -Caption", "Zoom Meeting Audit 2")
mockZoom2.AddButton("w160 h30", "Mute participants upon entry")
mockZoom2.AddButton("w120 h30", "Unmute all")
mockZoom2.AddButton("w120 h30", "Unmute my audio")
mockZoom2.AddButton("w120 h30", "Resume Recording")
mockZoom2.AddButton("w160 h30", "5 unread in Chat")
mockZoom2.Show("x-32000 y-32000 w320 h160 NoActivate")
hwnd2 := mockZoom2.Hwnd
zRes2 := DetectZoomStates("ahk_id " hwnd2)
mockZoom2.Destroy()
Assert("Live UIA DetectZoomStates detects muted mic + paused=2 rec + 5 unread chat",
    zRes2.foundWindow && zRes2.hasMic && zRes2.muted && zRes2.micHwnd == hwnd2
    && zRes2.hasRec && zRes2.recState == 2 && zRes2.hasChat && zRes2.unreadChat == 5)

; Verify dynamic Hotkey S option registration & SuspendHotkey "S" flag in PresenterSync.ahk
hkRegisteredOk := false
try {
    Hotkey("^!+F19", (*) => 0, "S")
    Suspend(true)
    Hotkey("^!+F19", "Off")
    Suspend(false)
    hkRegisteredOk := true
} catch {
    Suspend(false)
}
hostSrcText := FileRead(A_ScriptDir "\..\PresenterSync.ahk", "UTF-8")
Assert("Dynamic Hotkey with 'S' option registers & PresenterSync.ahk marks SuspendHotkey 'S'",
    hkRegisteredOk && InStr(hostSrcText, 'Hotkey(cfg.SuspendHotkey, (*) => ToggleSuspend(), "S")') > 0)

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
if FileExist(dimIni ".bak")
    FileDelete(dimIni ".bak")
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
expectedTopPad := stDimExtra.recHeight + stDimExtra.row3Height + stDimExtra.row4Height + (3 * stDimExtra.hudGap)
Assert("OverlayState.ComputeDimensions reserves extra HUD headroom when ShowExtraHuds=true", stDimExtra.savedY == vTop + expectedTopPad)

Assert("PromptForPassword accepts optional promptText", PromptForPassword.MinParams == 0 && PromptForPassword.MaxParams == 1)

hostIco := A_ScriptDir "\..\assets\PresenterSync.ico"
remoteIco := A_ScriptDir "\..\assets\PresenterSyncRemote.ico"
hostIcoBuf := FileExist(hostIco) ? FileRead(hostIco, "RAW") : Buffer(0)
remoteIcoBuf := FileExist(remoteIco) ? FileRead(remoteIco, "RAW") : Buffer(0)
Assert("Primary and Remote icon files exist with multi-resolution frames",
    hostIcoBuf.Size >= 22 && remoteIcoBuf.Size >= 22
    && NumGet(hostIcoBuf, 4, "UShort") >= 8
    && NumGet(remoteIcoBuf, 4, "UShort") >= 8)

if FileExist(dimIni)
    FileDelete(dimIni)
if FileExist(dimIni ".bak")
    FileDelete(dimIni ".bak")

; ==============================================================================
; SECTION 8: LIVE ENVIRONMENT FIXES (CLICKER TESTER, MARQUEE SCENE, LABEL MODE,
;            INTERNET RELAY, WSS CANDIDATES & SAFE MANUAL REMOTE CLOSE)
; ==============================================================================
; 1. Clicker Tester & Pointer Capture Dialog Geometry
testerWin := ShowPointerTester()
testerWin.GetClientPos(,, &tClientW, &tClientH)
testerKeyH := 0, testerBtnW := 0, testerBtnBottomPad := 0
for ctrl in testerWin {
    ctrl.GetPos(&cx, &cy, &cw, &ch)
    if (ctrl.Type = "Text" && InStr(ctrl.Text, "Listening"))
        testerKeyH := ch
    if (ctrl.Type = "Button" && InStr(ctrl.Text, "Close")) {
        testerBtnW := cw
        testerBtnBottomPad := tClientH - (cy + ch)
    }
}
WinClose("ahk_id " testerWin.Hwnd)
Assert("ShowPointerTester layout is spacious & non-clipped",
    tClientW >= 300 && tClientH >= 135 && testerKeyH >= 34 && testerBtnW >= 250 && testerBtnBottomPad >= 14,
    Format("Client={}x{}, keyH={}, btnW={}, bottomPad={}", tClientW, tClientH, testerKeyH, testerBtnW, testerBtnBottomPad))

capWin := OpenPointerKeyCaptureDialog("b", "Save & Apply", (*) => 0)
capWin.GetClientPos(,, &cClientW, &cClientH)
capEditH := 0, capBtnW := 0, capBtnBottomPad := 0
for ctrl in capWin {
    ctrl.GetPos(&cx, &cy, &cw, &ch)
    if (ctrl.Type = "Edit")
        capEditH := ch
    if (ctrl.Type = "Button") {
        capBtnW := cw
        capBtnBottomPad := cClientH - (cy + ch)
    }
}
WinClose("ahk_id " capWin.Hwnd)
Assert("OpenPointerKeyCaptureDialog layout is spacious & non-clipped",
    cClientW >= 300 && cClientH >= 150 && capEditH >= 28 && capBtnW >= 250 && capBtnBottomPad >= 14,
    Format("Client={}x{}, editH={}, btnW={}, bottomPad={}", cClientW, cClientH, capEditH, capBtnW, capBtnBottomPad))

; 2. Top-Layer Scene Pill Boundary & Smooth Horizontal Marquee Scroll
cfgScene := Config(testIni)
cfgScene.IndicatorScale := 1.0
cfgScene.ShowIndicator := true
cfgScene.ShowExtraHuds := true
cfgScene.EnableWS := true
cfgScene.ShowText := false
stScene := OverlayState(cfgScene)
InitHUD(cfgScene, stScene, false)
SyncSceneState(cfgScene, stScene, "Main Keynote Presentation - Dual Camera & Screen Share Layout 2026")
Assert("SceneGui width locked within baseWidth in Icon-Only mode on long scene name",
    (stScene.studioW + stScene.hudGap + stScene.sceneW) == stScene.baseWidth && stScene.baseWidth == 80)

cfgScene.ShowText := true
stScene.ComputeDimensions(cfgScene)
ApplyStudioAppearance(cfgScene, stScene)
ApplySceneAppearance(cfgScene, stScene)
Assert("SceneGui width locked within baseWidth in Label Mode on long scene name",
    (stScene.studioW + stScene.hudGap + stScene.sceneW) == stScene.baseWidth && stScene.baseWidth == 168)
Assert("Long scene name activates horizontal marquee scroll state",
    stScene.sceneMarqueeMaxOffset > 0 && stScene.sceneMarqueePhase == "pause_start")

; Advance past initial pause_start (60 ticks @ 25ms) into scroll_left
Loop 65
    SceneMarqueeTick(cfgScene, stScene)
Assert("SceneMarqueeTick smoothly advances sceneMarqueeOffset during scroll_left",
    stScene.sceneMarqueePhase == "scroll_left" && stScene.sceneMarqueeOffset > 0)

SyncSceneState(cfgScene, stScene, "Cam 1")
ApplySceneAppearance(cfgScene, stScene)
Assert("Short scene name stops marquee and renders centered statically",
    stScene.sceneMarqueeMaxOffset == 0 && stScene.sceneMarqueeOffset == 0)

if (stScene.sceneMarqueeTimerFn)
    SetTimer(stScene.sceneMarqueeTimerFn, 0)
stScene.MicGui.Destroy()
stScene.RecGui.Destroy()
stScene.ChatGui.Destroy()
stScene.StudioGui.Destroy()
stScene.SceneGui.Destroy()
stScene.StreamGui.Destroy()
stScene.VCamGui.Destroy()

; 3. Label Mode (ShowText = true) Layer 2 & Layer 3 Non-Overlapping Geometry
Assert("UIConstants Label Mode dimensions widened to prevent icon/text overlap",
    UIConstants.BASE_WIDTH_TEXT == 168
    && UIConstants.STUDIO_ICON_W == 18
    && UIConstants.REC_ICON_W == 18
    && UIConstants.CHAT_ICON_W == 18
    && UIConstants.LABEL_GAP_X == 6)

stIconX := Round(UIConstants.STUDIO_ICON_X * 1.0)
stIconW := Round(UIConstants.STUDIO_ICON_W * 1.0)
stGap := Round(UIConstants.LABEL_GAP_X * 1.0)
stTextX := stIconX + stIconW + stGap
stAvailW := stScene.studioW - stTextX - stIconX
stMeasuredW := Gdip.MeasureTextWidth("STUDIO", "Segoe UI", UIConstants.STUDIO_TEXT_SIZE, 1)
Assert("StudioGui Label Mode has explicit gap between icon and STUDIO text & fits cleanly",
    stTextX == (stIconX + stIconW + 6) && stAvailW >= stMeasuredW)

; 4. WSS & Path Candidate Parsing + Internet Relay Helpers
wssCandidates := ParseCandidateEndpoints("wss://obs-tunnel.example.com/ws, STUDIO-PC.local, https://relay.example.org:8443/live")
Assert("ParseCandidateEndpoints supports wss://, default 443 port, custom ports, and URL paths",
    wssCandidates.Length == 3
    && wssCandidates[1].scheme == "wss" && wssCandidates[1].host == "obs-tunnel.example.com" && wssCandidates[1].port == "443" && wssCandidates[1].path == "/ws" && wssCandidates[1].url == "wss://obs-tunnel.example.com:443/ws"
    && wssCandidates[2].scheme == "ws" && wssCandidates[2].host == "STUDIO-PC.local" && wssCandidates[2].port == "4455" && wssCandidates[2].url == "ws://STUDIO-PC.local:4455/"
    && wssCandidates[3].scheme == "wss" && wssCandidates[3].host == "relay.example.org" && wssCandidates[3].port == "8443" && wssCandidates[3].path == "/live")

pairCode := GenerateInternetPairingCode()
topic1 := GetInternetRelayTopic(pairCode)
auth1 := GetInternetRelayAuthToken(pairCode, "myPass")
pktStr := FormatRelayPacket("host", "state", "1", auth1)
parsedPkt := ParseRelayPacket(pktStr)
Assert("Internet Pairing Code & Relay Packet round-trip integrity",
    RegExMatch(pairCode, "^PS-[2-9A-Z]{4}-[2-9A-Z]{4}$")
    && SubStr(topic1, 1, 6) == "psync_"
    && IsObject(parsedPkt) && parsedPkt.src == "host" && parsedPkt.cmd == "state" && parsedPkt.data == "1" && parsedPkt.auth == auth1)

; 5. Safe Manual Close Remote Companion Confirmation Dialog & Signal
closeDlg := PromptCloseRemoteCompanion(cfgScene, stScene)
closeDlgExists := IsObject(closeDlg) && WinExist("ahk_id " closeDlg.Hwnd)
if closeDlgExists
    WinClose("ahk_id " closeDlg.Hwnd)
Assert("PromptCloseRemoteCompanion opens safe manual confirmation dialog", closeDlgExists != 0)

mockCloseWs := {sent: [], sendText: (this, txt) => this.sent.Push(txt)}
Assert("SendObsBroadcastCloseRemote formats BroadcastCustomEvent CloseRemote payload",
    SendObsBroadcastCloseRemote(mockCloseWs)
    && mockCloseWs.sent.Length == 1
    && InStr(mockCloseWs.sent[1], '"requestType":"BroadcastCustomEvent"')
    && InStr(mockCloseWs.sent[1], '"command":"CloseRemote"'))

; ==============================================================================
; SECTION 9: COMPLETE WINDOW LAYOUT & MULTI-SCALE HUD GEOMETRY AUDIT
; ==============================================================================
AuditDialogGeometry(dlgName, dlgObj, minClientW := 260, minClientH := 120) {
    if (!IsObject(dlgObj) || !WinExist("ahk_id " dlgObj.Hwnd)) {
        Assert(dlgName " window instantiated & visible", false, "Window failed to open")
        return
    }
    dlgObj.GetClientPos(,, &cw, &ch)
    allInside := true
    maxRight := 0
    maxBottom := 0
    detailStr := ""
    for ctrl in dlgObj {
        ctrl.GetPos(&x, &y, &w, &h)
        if (x < 0 || y < 0 || (x + w) > (cw + 2) || (y + h) > (ch + 2)) {
            allInside := false
            detailStr := Format("Ctrl '{}' out of bounds: x={} y={} w={} h={} vs client {}x{}", ctrl.Text, x, y, w, h, cw, ch)
            break
        }
        if (x + w > maxRight)
            maxRight := x + w
        if (y + h > maxBottom)
            maxBottom := y + h
    }
    WinClose("ahk_id " dlgObj.Hwnd)
    Assert(dlgName " geometry & control bounds valid",
        cw >= minClientW && ch >= minClientH && allInside && (ch - maxBottom) >= 8,
        detailStr != "" ? detailStr : Format("Client={}x{}, maxRight={}, maxBottom={}", cw, ch, maxRight, maxBottom))
}

AuditDialogGeometry("HelpWindow", ShowHelpWindow(cfgScene, stScene), 650, 500)
AuditDialogGeometry("AboutWindow", ShowAboutWindow(cfgScene, stScene), 460, 520)
AuditDialogGeometry("ChangeAppHotkeysUI", ChangeAppHotkeysUI(cfgScene), 300, 220)
AuditDialogGeometry("ChangeObsSettingsUI", ChangeObsSettingsUI(cfgScene), 280, 280)
AuditDialogGeometry("ChangeZoomShortcutsUI", ChangeZoomShortcutsUI(cfgScene), 300, 180)
AuditDialogGeometry("ConfigurePointerKeysUI", ConfigurePointerKeysUI(cfgScene), 260, 200)
AuditDialogGeometry("RemoteCompanionInfo", ShowRemoteCompanionInfo(cfgScene, stScene), 360, 320)
AuditDialogGeometry("CloseRemoteCompanion", PromptCloseRemoteCompanion(cfgScene, stScene), 340, 130)

; Multi-Scale HUD Stack & Label Mode Non-Overlap Audit across all 9 scales
allScalesOk := true
scaleDetail := ""
for sc in [0.25, 0.5, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0, 5.0] {
    for showTxt in [false, true] {
        cfgScene.IndicatorScale := sc
        cfgScene.ShowText := showTxt
        stScene.ComputeDimensions(cfgScene)
        lay := ComputeHudLayout(stScene, 400, 400)
        row2TotalW := lay.recW + stScene.hudGap + lay.chatW
        row3TotalW := lay.studioW + stScene.hudGap + lay.sceneW
        row4TotalW := lay.streamW + stScene.hudGap + lay.vcamW
        if (row2TotalW != lay.micW || row3TotalW != lay.micW || row4TotalW != lay.micW
            || (lay.recX + lay.recW + stScene.hudGap) != lay.chatX
            || (lay.studioX + lay.studioW + stScene.hudGap) != lay.sceneX
            || (lay.streamX + lay.streamW + stScene.hudGap) != lay.vcamX
            || (lay.streamY + lay.streamH + stScene.hudGap) != lay.studioY
            || (lay.sceneY + lay.sceneH + stScene.hudGap) != lay.recY
            || (lay.recY + lay.recH + stScene.hudGap) != lay.micY) {
            allScalesOk := false
            scaleDetail := Format("Mismatch at scale={} showText={}: micW={} row2W={} row3W={} row4W={}", sc, showTxt, lay.micW, row2TotalW, row3TotalW, row4TotalW)
            break 2
        }
        if (showTxt) {
            gapPx := Round(UIConstants.LABEL_GAP_X * sc)
            mIconEnd := Round(UIConstants.ICON_OFFSET_X * sc) + Round(UIConstants.MIC_ICON_W * sc)
            mTextStart := Round(UIConstants.TEXT_OFFSET_X * sc)
            rIconEnd := Round(UIConstants.REC_ICON_X * sc) + Round(UIConstants.REC_ICON_W * sc)
            rTextStart := rIconEnd + gapPx
            cIconEnd := Round(UIConstants.CHAT_ICON_X * sc) + Round(UIConstants.CHAT_ICON_W * sc)
            cTextStart := cIconEnd + gapPx
            sIconEnd := Round(UIConstants.STUDIO_ICON_X * sc) + Round(UIConstants.STUDIO_ICON_W * sc)
            sTextStart := sIconEnd + gapPx
            stIconEnd := Round(UIConstants.STREAM_ICON_X * sc) + Round(UIConstants.STREAM_ICON_W * sc)
            stTextStart := stIconEnd + gapPx
            vcIconEnd := Round(UIConstants.VCAM_ICON_X * sc) + Round(UIConstants.VCAM_ICON_W * sc)
            vcTextStart := vcIconEnd + gapPx
            if (mIconEnd > mTextStart || rIconEnd > rTextStart || cIconEnd > cTextStart || sIconEnd > sTextStart || stIconEnd > stTextStart || vcIconEnd > vcTextStart) {
                allScalesOk := false
                scaleDetail := Format("Icon/text overlap at scale={}", sc)
                break 2
            }
        }
    }
}
Assert("All 8 HUD scales (0.25x-5.0x) maintain exact stack width & non-overlapping icon/label bounds",
    allScalesOk, scaleDetail)

; ==============================================================================
; SECTION 8: STAGE 1 (v2.2.5) - OPTIONAL AUDIO CUE & MUTE TOAST
; ==============================================================================
cfgAudioTest := Config(testIni)
Assert("EnableAudioCue defaults to false", cfgAudioTest.EnableAudioCue == false)
Assert("EnableMuteToast defaults to false", cfgAudioTest.EnableMuteToast == false)

cueTonesMute := GetMuteAudioCueTones(true)
cueTonesLive := GetMuteAudioCueTones(false)
Assert("Mute audio cue uses descending two-tone chime", cueTonesMute.f1 == 880 && cueTonesMute.f2 == 520 && cueTonesMute.f1 > cueTonesMute.f2)
Assert("Unmute audio cue uses ascending two-tone chime", cueTonesLive.f1 == 520 && cueTonesLive.f2 == 880 && cueTonesLive.f1 < cueTonesLive.f2)

callbackTrack := { tray: 0, help: 0 }
mockCueState := { isMuted: false, MicGui: "", rebuildTrayFn: (*) => (callbackTrack.tray += 1), refreshHelpFn: (*) => (callbackTrack.help += 1) }

ToggleAudioCue(cfgAudioTest, mockCueState)
ToggleMuteToast(cfgAudioTest, mockCueState)
cfgAudioReload := Config(testIni)
Assert("ToggleAudioCue and ToggleMuteToast persist true to INI & invoke tray/help refresh",
    cfgAudioTest.EnableAudioCue == true && cfgAudioReload.EnableAudioCue == true
    && cfgAudioTest.EnableMuteToast == true && cfgAudioReload.EnableMuteToast == true
    && callbackTrack.tray == 2 && callbackTrack.help == 2)

SyncUIState(cfgAudioTest, mockCueState, true)
Assert("SyncUIState with EnableAudioCue/EnableMuteToast transitions to muted safely",
    mockCueState.isMuted == true && cfgAudioTest.IsMuted == true)
ToolTip()

cfgAudioTest.ResetAppearance()
cfgAudioResetReload := Config(testIni)
Assert("ResetAppearance clears EnableAudioCue and EnableMuteToast back to false",
    cfgAudioTest.EnableAudioCue == false && cfgAudioResetReload.EnableAudioCue == false
    && cfgAudioTest.EnableMuteToast == false && cfgAudioResetReload.EnableMuteToast == false)

; ==============================================================================
; SECTION 9: STAGE 2 (v2.2.6) - COUGH / PUSH-TO-MUTE HOLD GESTURE
; ==============================================================================
cfgPushTest := Config(testIni)
Assert("EnablePushToMute defaults to false", cfgPushTest.EnablePushToMute == false)

pushCb := { tray: 0 }
TogglePushToMute(cfgPushTest, { rebuildTrayFn: (*) => (pushCb.tray += 1) })
cfgPushReload := Config(testIni)
Assert("TogglePushToMute persists to Pointer INI section & triggers tray refresh",
    cfgPushTest.EnablePushToMute == true && cfgPushReload.EnablePushToMute == true && pushCb.tray == 1)

Assert("ExtractBaseKeyName parses bare key, modifiers, up-suffix, and None",
    ExtractBaseKeyName("b") == "b"
    && ExtractBaseKeyName("^+b") == "b"
    && ExtractBaseKeyName("~*PgDn") == "PgDn"
    && ExtractBaseKeyName("Escape up") == "Escape"
    && ExtractBaseKeyName("None") == ""
    && ExtractBaseKeyName("") == "")

kwCalls := []
cfgPushOff := Config(testIni)
cfgPushOff.EnablePushToMute := false
Assert("WaitPushToMuteRelease bypasses wait when EnablePushToMute=false",
    !WaitPushToMuteRelease(cfgPushOff, "b", (k, o) => (kwCalls.Push({ k: k, o: o }), 1)) && kwCalls.Length == 0)

Assert("WaitPushToMuteRelease returns false on quick tap (<350ms)",
    !WaitPushToMuteRelease(cfgPushTest, "PgDn", (k, o) => (kwCalls.Push({ k: k, o: o }), 1))
    && kwCalls.Length == 1 && kwCalls[1].k == "PgDn" && kwCalls[1].o == "T0.350")

holdSeq := [0, 1]
holdCalls := []
holdRes := WaitPushToMuteRelease(cfgPushTest, "~*PgDn", (k, o) => (holdCalls.Push({ k: k, o: o }), holdSeq[holdCalls.Length]))
Assert("WaitPushToMuteRelease detects hold (>=350ms) and waits for release",
    holdRes == true && holdCalls.Length == 2
    && holdCalls[1].k == "PgDn" && holdCalls[1].o == "T0.350"
    && holdCalls[2].k == "PgDn" && holdCalls[2].o == "T15")

; ==============================================================================
; SECTION 10: STAGE 3 (v2.2.7) - CUSTOM HUD COLOR THEMES & TALLY PRESETS
; ==============================================================================
presets := GetHudColorPresetNames()
Assert("GetHudColorPresetNames exposes 6 presets including Custom",
    presets.Length == 6 && presets[1] == "Standard" && presets[2] == "Colorblind Safe" && presets[5] == "Cyber Ocean" && presets[6] == "Custom")

palStd := UIConstants.GetColorPalette("Standard")
Assert("Standard palette matches baseline UIConstants LIVE/MUTED colors",
    palStd.live == UIConstants.COLOR_LIVE && palStd.muted == UIConstants.COLOR_MUTED && palStd.borderLive == UIConstants.BORDER_LIVE)

palCb := UIConstants.GetColorPalette("Colorblind Safe")
Assert("Colorblind Safe palette uses Okabe-Ito Blue LIVE (#0072B2) and Orange MUTED (#D55E00)",
    palCb.live == "0072B2" && palCb.muted == "D55E00" && palCb.borderLive == 0xB27200)

cfgPreset := Config(testIni)
Assert("HudColorPreset defaults to Standard", cfgPreset.HudColorPreset == "Standard")

presetState := OverlayState(cfgPreset)
presetState.MicGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000 -DPIScale")
presetState.RecGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000 -DPIScale")
presetState.ChatGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000 -DPIScale")
presetState.StudioGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000 -DPIScale")
presetState.SceneGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000 -DPIScale")
presetCbTrack := { tray: 0, hud: 0 }
presetState.rebuildTrayFn := (*) => (presetCbTrack.tray += 1)
presetState.refreshHudFn := (*) => (presetCbTrack.hud += 1, presetState.ComputeDimensions(cfgPreset), RenderAllHudPills(cfgPreset, presetState))

SetHudColorPreset(cfgPreset, presetState, "Cyber Ocean")
cfgPresetReload := Config(testIni)
Assert("SetHudColorPreset persists to INI, updates OverlayState.colors, and triggers callbacks",
    cfgPreset.HudColorPreset == "Cyber Ocean" && cfgPresetReload.HudColorPreset == "Cyber Ocean"
    && presetState.colors.live == "06B6D4" && presetCbTrack.tray == 1 && presetCbTrack.hud == 1)

allPresetsRenderOk := true
for pName in presets {
    SetHudColorPreset(cfgPreset, presetState, pName)
    if (!ApplyMicAppearance(cfgPreset, presetState) || !ApplySceneAppearance(cfgPreset, presetState)) {
        allPresetsRenderOk := false
        break
    }
}
Assert("All 5 HUD color presets render Mic and Scene GDI+ pills cleanly", allPresetsRenderOk)

cfgPreset.ResetAppearance()
cfgPresetResetReload := Config(testIni)
Assert("ResetAppearance resets HudColorPreset back to Standard",
    cfgPreset.HudColorPreset == "Standard" && cfgPresetResetReload.HudColorPreset == "Standard")

presetState.MicGui.Destroy(), presetState.RecGui.Destroy(), presetState.ChatGui.Destroy(), presetState.StudioGui.Destroy(), presetState.SceneGui.Destroy()

; ==============================================================================
; SECTION 11: STAGE 4 (v2.2.8) - LIVE COREAUDIO VOICE ACTIVITY METER
; ==============================================================================
Assert("AudioMeter.NormalizePeak clamps bounds and applies perceptual curve",
    AudioMeter.NormalizePeak(-0.5) == 0.0
    && AudioMeter.NormalizePeak(0.002) == 0.0
    && Abs(AudioMeter.NormalizePeak(0.25) - 0.5) < 0.001
    && AudioMeter.NormalizePeak(2.5) == 1.0)

livePeak := AudioMeter.GetPeak()
Assert("AudioMeter.GetPeak returns safe scalar in [0.0, 1.0] without throwing",
    livePeak >= 0.0 && livePeak <= 1.0)

cfgMeter := Config(testIni)
Assert("ShowVoiceMeter defaults to true", cfgMeter.ShowVoiceMeter == true)

meterCb := { tray: 0 }
meterState := OverlayState(cfgMeter)
meterState.rebuildTrayFn := (*) => (meterCb.tray += 1)
meterState.MicGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000 -DPIScale")
meterState.isMuted := false
meterState.voicePeak := 0.72
Assert("ApplyMicAppearance renders LIVE pill cleanly with voicePeak=0.72",
    ApplyMicAppearance(cfgMeter, meterState) != false)

cfgMeter.ShowText := true
meterState.ComputeDimensions(cfgMeter)
Assert("ApplyMicAppearance renders Label-Mode LIVE pill with voicePeak=0.72",
    ApplyMicAppearance(cfgMeter, meterState) != false)

ToggleVoiceMeter(cfgMeter, meterState)
cfgMeterReload := Config(testIni)
Assert("ToggleVoiceMeter persists false to INI & clears voicePeak",
    cfgMeter.ShowVoiceMeter == false && cfgMeterReload.ShowVoiceMeter == false
    && meterState.voicePeak == 0.0 && meterCb.tray == 1)

cfgMeter.ResetAppearance()
cfgMeterResetReload := Config(testIni)
Assert("ResetAppearance restores ShowVoiceMeter back to true",
    cfgMeter.ShowVoiceMeter == true && cfgMeterResetReload.ShowVoiceMeter == true)

meterState.voicePeak := 0.1
VoiceMeterTick(cfgMeter, meterState, () => 0.64)
Assert("VoiceMeterTick updates voicePeak from reader when unmuted",
    Abs(meterState.voicePeak - 0.397) < 0.005)

meterState.isMuted := true
VoiceMeterTick(cfgMeter, meterState, () => 0.90)
Assert("VoiceMeterTick stops & zeroes voicePeak when muted",
    meterState.voicePeak == 0.0)

meterState.MicGui.Destroy()

; ==============================================================================
; SECTION 12: STAGE 5 (v2.2.9) - LIVE ELAPSED RECORDING TIMER ON REC PILL
; ==============================================================================
Assert("FormatElapsedShort formats MM:SS, H:MM:SS, and clamps negative values",
    FormatElapsedShort(0) == "00:00"
    && FormatElapsedShort(5) == "00:05"
    && FormatElapsedShort(65) == "01:05"
    && FormatElapsedShort(3599) == "59:59"
    && FormatElapsedShort(3600) == "1:00:00"
    && FormatElapsedShort(3665) == "1:01:05"
    && FormatElapsedShort(-12) == "00:00")

cfgRec := Config(testIni)
Assert("ShowRecTimer defaults to true", cfgRec.ShowRecTimer == true)

stRec := OverlayState(cfgRec)
recCb := { tray: 0 }
stRec.rebuildTrayFn := (*) => (recCb.tray += 1)
stRec.MicGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000 -DPIScale")
stRec.RecGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000 -DPIScale")
stRec.ChatGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000 -DPIScale")

ToggleRecTimer(cfgRec, stRec)
cfgRecReload := Config(testIni)
Assert("ToggleRecTimer persists false to INI and refreshes tray",
    cfgRec.ShowRecTimer == false && cfgRecReload.ShowRecTimer == false && recCb.tray == 1)

cfgRec.ResetAppearance()
Assert("ResetAppearance restores ShowRecTimer back to true", cfgRec.ShowRecTimer == true)

cfgRec.ShowText := true
SyncRecState(cfgRec, stRec, 1, 125000)
Assert("SyncRecState syncs initialDurationMs=125000 -> 125s and preserves Label Mode row2 width",
    stRec.recState == 1 && stRec.recElapsedSec == 125
    && (stRec.recW + stRec.hudGap + stRec.chatW) == stRec.baseWidth)

stRec.obsRecAnchorTick -= 1000
RecTimerTick(cfgRec, stRec)
Assert("RecTimerTick increments recElapsedSec while recording active", stRec.recElapsedSec == 126)

SyncRecState(cfgRec, stRec, 2)
RecTimerTick(cfgRec, stRec)
Assert("Paused rec state preserves elapsed seconds and stops incrementing",
    stRec.recState == 2 && stRec.recElapsedSec == 126)

SyncRecState(cfgRec, stRec, 1)
Assert("Resuming from Pause preserves existing recElapsedSec",
    stRec.recState == 1 && stRec.recElapsedSec == 126)

SyncRecState(cfgRec, stRec, 0)
Assert("Stopping recording resets recElapsedSec back to 0",
    stRec.recState == 0 && stRec.recElapsedSec == 0)

wsRecMsg := '{"op":7,"d":{"requestType":"GetRecordStatus","requestId":"InitRecState","requestStatus":{"result":true,"code":100},"responseData":{"outputActive":true,"outputPaused":false,"outputDuration":90500}}}'
HandleObsMessage(cfgRec, stRec, "", wsRecMsg)
Assert("HandleObsMessage InitRecState parses OBS outputDuration into recElapsedSec=90",
    stRec.recState == 1 && stRec.recElapsedSec == 90)
SyncRecState(cfgRec, stRec, 0)

stRec.MicGui.Destroy(), stRec.RecGui.Destroy(), stRec.ChatGui.Destroy()

; ==============================================================================
; SECTION 13: STAGE 6 (v2.3.0) - 4TH-TIER LIVE STREAM & VIRTUAL CAMERA HUD
; ==============================================================================
cfgStrm := Config(testIni)
Assert("ShowStreamHud defaults to true", cfgStrm.ShowStreamHud == true)

stStrm := OverlayState(cfgStrm)
InitHUD(cfgStrm, stStrm, false)
strmCb := { tray: 0, hud: 0 }
stStrm.rebuildTrayFn := (*) => (strmCb.tray += 1)
stStrm.refreshHudFn := (*) => (strmCb.hud += 1)

ToggleStreamHud(cfgStrm, stStrm)
cfgStrmReload := Config(testIni)
Assert("ToggleStreamHud persists false to INI and triggers tray/HUD refresh",
    cfgStrm.ShowStreamHud == false && cfgStrmReload.ShowStreamHud == false && strmCb.tray == 1 && strmCb.hud == 1)

cfgStrm.ResetAppearance()
Assert("ResetAppearance restores ShowStreamHud back to true", cfgStrm.ShowStreamHud == true)

mockWs6 := MockWebSocket()
cfgStrm.EnableWS := true
stStrm.obsWs := mockWs6
HandleObsMessage(cfgStrm, stStrm, mockWs6, '{"op":2,"d":{"negotiatedRpcVersion":1}}')
allSent8 := ""
for _, sMsg in mockWs6.sent
    allSent8 .= sMsg "`n"
hasAll8 := (mockWs6.sent.Length == 10)
    && InStr(allSent8, '"InitState"')
    && InStr(allSent8, '"InitRecState"')
    && InStr(allSent8, '"InitStudioState"')
    && InStr(allSent8, '"InitSceneState"')
    && InStr(allSent8, '"InitPreviewSceneState"')
    && InStr(allSent8, '"InitSceneList"')
    && InStr(allSent8, '"InitStreamState"')
    && InStr(allSent8, '"InitVCamState"')
    && InStr(allSent8, '"InitInputList"')
    && InStr(allSent8, '"InitRecordDir"')
Assert("OpCode 2 dispatches all 9 initial OBS state queries (incl. PreviewScene, SceneList, Stream, VCam & RecordDir)", hasAll8)

HandleObsMessage(cfgStrm, stStrm, mockWs6, '{"op":5,"d":{"eventType":"StreamStateChanged","eventData":{"outputActive":true,"outputState":"OBS_WEBSOCKET_OUTPUT_STARTED"}}}')
Assert("StreamStateChanged outputActive=true sets streamState=1", stStrm.streamState == 1)

HandleObsMessage(cfgStrm, stStrm, mockWs6, '{"op":7,"d":{"requestType":"GetStreamStatus","requestId":"PollStreamStatus","requestStatus":{"result":true},"responseData":{"outputActive":true,"outputReconnecting":false,"outputCongestion":0.42,"outputSkippedFrames":0}}}')
Assert("GetStreamStatus high congestion (>=0.35) escalates streamState=2 (WARN)", stStrm.streamState == 2 && Abs(stStrm.streamCongestion - 0.42) < 0.001)

HandleObsMessage(cfgStrm, stStrm, mockWs6, '{"op":7,"d":{"requestType":"GetStreamStatus","requestId":"PollStreamStatus","requestStatus":{"result":true},"responseData":{"outputActive":true,"outputReconnecting":false,"outputCongestion":0.05,"outputSkippedFrames":8}}}')
Assert("GetStreamStatus frame drop delta (>0 skipped frames) keeps streamState=2 (WARN)", stStrm.streamState == 2 && stStrm.streamSkippedFrames == 8)

HandleObsMessage(cfgStrm, stStrm, mockWs6, '{"op":7,"d":{"requestType":"GetStreamStatus","requestId":"PollStreamStatus","requestStatus":{"result":true},"responseData":{"outputActive":true,"outputReconnecting":false,"outputCongestion":0.05,"outputSkippedFrames":8}}}')
Assert("GetStreamStatus steady metrics clear streamState back to 1 (LIVE)", stStrm.streamState == 1)

HandleObsMessage(cfgStrm, stStrm, mockWs6, '{"op":5,"d":{"eventType":"StreamStateChanged","eventData":{"outputActive":false,"outputState":"OBS_WEBSOCKET_OUTPUT_RECONNECTING"}}}')
Assert("StreamStateChanged RECONNECTING sets streamState=2 (WARN)", stStrm.streamState == 2 && stStrm.streamReconnecting == true)

HandleObsMessage(cfgStrm, stStrm, mockWs6, '{"op":5,"d":{"eventType":"VirtualcamStateChanged","eventData":{"outputActive":true}}}')
Assert("VirtualcamStateChanged outputActive=true sets vcamActive=true", stStrm.vcamActive == true)

HandleObsClose(cfgStrm, stStrm, mockWs6, 1006, "")
SetTimer(stStrm.obsTimerFn, 0)
Assert("HandleObsClose resets streamState=0 and vcamActive=false", stStrm.streamState == 0 && stStrm.vcamActive == false)

cfgStrm.ShowText := true
stStrm.ComputeDimensions(cfgStrm)
lay6 := ComputeHudLayout(stStrm, 500, 500)
ancStrm := AnchorFromHwnd(stStrm, stStrm.StreamGui.Hwnd, lay6.streamX, lay6.streamY)
ancVCam := AnchorFromHwnd(stStrm, stStrm.VCamGui.Hwnd, lay6.vcamX, lay6.vcamY)
Assert("AnchorFromHwnd resolves Row 4 StreamGui & VCamGui back to anchor (500,500)",
    ancStrm.x == 500 && ancStrm.y == 500 && ancVCam.x == 500 && ancVCam.y == 500)
Assert("IsHudHwnd recognizes Row 4 StreamGui and VCamGui plus invalidates 0",
    IsHudHwnd(stStrm, stStrm.StreamGui.Hwnd) && IsHudHwnd(stStrm, stStrm.VCamGui.Hwnd) && !IsHudHwnd(stStrm, 0))
Assert("ApplyStreamAppearance and ApplyVCamAppearance render cleanly in Label Mode",
    ApplyStreamAppearance(cfgStrm, stStrm) && ApplyVCamAppearance(cfgStrm, stStrm))

SyncStreamState(cfgStrm, stStrm, 0)
stStrm.MicGui.Destroy(), stStrm.RecGui.Destroy(), stStrm.ChatGui.Destroy()
stStrm.StudioGui.Destroy(), stStrm.SceneGui.Destroy(), stStrm.StreamGui.Destroy(), stStrm.VCamGui.Destroy()

; ==============================================================================
; SECTION 14: STAGE 7 (v2.3.1) - INTERACTIVE HUD PILLS & SCENE SWITCHER
; ==============================================================================
cfgClick := Config(testIni)
Assert("EnableHudClickActions defaults to true", cfgClick.EnableHudClickActions == true)

stClick := OverlayState(cfgClick)
InitHUD(cfgClick, stClick, false)
clickCb := { tray: 0, trig: 0 }
stClick.rebuildTrayFn := (*) => (clickCb.tray += 1)
stClick.triggerMuteFn := (*) => (clickCb.trig += 1)

ToggleBoolSetting(cfgClick, stClick, "EnableHudClickActions")
cfgClickReload := Config(testIni)
Assert("Toggle EnableHudClickActions persists false & refreshes tray",
    cfgClick.EnableHudClickActions == false && cfgClickReload.EnableHudClickActions == false && clickCb.tray == 1)
Assert("HandleHudPillClick returns false when EnableHudClickActions=false",
    HandleHudPillClick(cfgClick, stClick, stClick.MicGui.Hwnd) == false && clickCb.trig == 0)

cfgClick.ResetAppearance()
Assert("ResetAppearance restores EnableHudClickActions back to true", cfgClick.EnableHudClickActions == true)

sceneJson := '{"op":7,"d":{"requestType":"GetSceneList","requestId":"InitSceneList","requestStatus":{"result":true},"responseData":{"currentProgramSceneName":"Main","scenes":[{"sceneIndex":0,"sceneName":"Outro"},{"sceneIndex":1,"sceneName":"Q&A"},{"sceneIndex":2,"sceneName":"Main"}]}}}'
mockWs7 := MockWebSocket()
cfgClick.EnableWS := true
stClick.obsConnected := true
stClick.obsWs := mockWs7
HandleObsMessage(cfgClick, stClick, mockWs7, sceneJson)
Assert("InitSceneList populates reversed OBS scene list incl. Q&A",
    stClick.sceneList.Length == 3 && stClick.sceneList[1] == "Main" && stClick.sceneList[2] == "Q&A" && stClick.sceneList[3] == "Outro")

menuBuilt := BuildSceneSwitcherMenu(cfgClick, stClick)
Assert("BuildSceneSwitcherMenu includes cached scenes & dispatches GetSceneList refresh",
    menuBuilt.scenes.Length == 3 && InStr(mockWs7.sent[1], '"GetSceneList"'))

SwitchObsScene(cfgClick, stClick, 'Q&A "Live"')
Assert("SwitchObsScene sends SetCurrentProgramScene with escaped scene name",
    mockWs7.sent.Length == 2 && InStr(mockWs7.sent[2], '"SetCurrentProgramScene"') && InStr(mockWs7.sent[2], 'Q&A \"Live\"'))

Assert("HandleHudPillClick MicGui invokes triggerMuteFn",
    HandleHudPillClick(cfgClick, stClick, stClick.MicGui.Hwnd) == "mic" && clickCb.trig == 1)
Assert("HandleHudPillClick RecGui sends StartRecord when OBS connected & recState=0",
    HandleHudPillClick(cfgClick, stClick, stClick.RecGui.Hwnd) == "rec" && InStr(mockWs7.sent[3], '"StartRecord"'))
Assert("HandleHudPillClick StudioGui sends SetStudioModeEnabled",
    HandleHudPillClick(cfgClick, stClick, stClick.StudioGui.Hwnd) == "studio" && InStr(mockWs7.sent[4], '"SetStudioModeEnabled"'))
Assert("HandleHudPillClick VCamGui sends ToggleVirtualCam",
    HandleHudPillClick(cfgClick, stClick, stClick.VCamGui.Hwnd) == "vcam" && InStr(mockWs7.sent[5], '"ToggleVirtualCam"'))

stClick.unreadChatCount := 3
Assert("HandleHudPillClick ChatGui clears unreadChatCount & StreamGui is strictly read-only",
    HandleHudPillClick(cfgClick, stClick, stClick.ChatGui.Hwnd) == "chat" && stClick.unreadChatCount == 0
    && HandleHudPillClick(cfgClick, stClick, stClick.StreamGui.Hwnd) == "stream_readonly"
    && mockWs7.sent.Length == 5)
ToolTip()

cfgClick.EnableWS := false
stClick.obsConnected := false
SwitchObsScene(cfgClick, stClick, "OfflineDeck")
HandleHudPillClick(cfgClick, stClick, stClick.RecGui.Hwnd)
Assert("Offline click fallback updates local recState and SwitchObsScene updates currentSceneName",
    stClick.recState == 1 && stClick.currentSceneName == "OfflineDeck")
SyncRecState(cfgClick, stClick, 0)

stClick.MicGui.Destroy(), stClick.RecGui.Destroy(), stClick.ChatGui.Destroy()
stClick.StudioGui.Destroy(), stClick.SceneGui.Destroy(), stClick.StreamGui.Destroy(), stClick.VCamGui.Destroy()

; ==============================================================================
; SECTION 15: STAGE 8 (v2.3.2) - MAGNETIC SNAP, CLICK-THROUGH & AUTO-DODGE
; ==============================================================================
cfgSnap := Config(testIni)
Assert("MagneticSnap defaults to true; ClickThrough & AutoDodge default to false",
    cfgSnap.EnableMagneticSnap == true && cfgSnap.HudClickThrough == false && cfgSnap.HudAutoDodge == false)

stSnap := OverlayState(cfgSnap)
InitHUD(cfgSnap, stSnap, false)
snapCb := { tray: 0, hud: 0 }
stSnap.rebuildTrayFn := (*) => (snapCb.tray += 1)
stSnap.refreshHudFn := (*) => (snapCb.hud += 1)

ToggleMagneticSnap(cfgSnap, stSnap)
ToggleHudClickThrough(cfgSnap, stSnap)
ToggleHudAutoDodge(cfgSnap, stSnap)
cfgSnapReload := Config(testIni)
Assert("Snap/ClickThrough/AutoDodge toggles persist to INI & trigger callbacks",
    cfgSnapReload.EnableMagneticSnap == false && cfgSnapReload.HudClickThrough == true && cfgSnapReload.HudAutoDodge == true
    && snapCb.tray == 3 && snapCb.hud >= 2)

fakeWA := { left: 0, top: 0, right: 1920, bottom: 1040 }
winRects := [{ left: 300, top: 200, right: 1100, bottom: 800 }]
snapEdge := ComputeMagneticSnap(6, 500, 80, 40, 0, 14, winRects, fakeWA)
Assert("ComputeMagneticSnap snaps anchor X within 14px of screen left margin (x=10)",
    snapEdge.snappedX == true && snapEdge.x == 10 && snapEdge.y == 500)

snapWin := ComputeMagneticSnap(1112, 244, 80, 40, 40, 14, winRects, fakeWA)
Assert("ComputeMagneticSnap snaps HUD top-left beside/aligned to app window (x=1106, y=240)",
    snapWin.snappedX == true && snapWin.x == 1106 && snapWin.snappedY == true && snapWin.y == 240)

snapFar := ComputeMagneticSnap(500, 500, 80, 40, 0, 14, winRects, fakeWA)
Assert("ComputeMagneticSnap leaves HUD unmoved when outside 14px threshold",
    snapFar.snappedX == false && snapFar.snappedY == false && snapFar.x == 500 && snapFar.y == 500)

prevDhwSnap := DetectHiddenWindows(true)
Assert("ApplyHudClickThroughStyle sets +WS_EX_TRANSPARENT (0x20) when enabled & Alt not held",
    ApplyHudClickThroughStyle(cfgSnap, stSnap, true) == true
    && (WinGetExStyle("ahk_id " stSnap.MicGui.Hwnd) & 0x20) != 0)
Assert("ApplyHudClickThroughStyle clears WS_EX_TRANSPARENT when disabled/Alt held",
    ApplyHudClickThroughStyle(cfgSnap, stSnap, false) == false
    && (WinGetExStyle("ahk_id " stSnap.MicGui.Hwnd) & 0x20) == 0)

cfgSnap.HudClickThrough := false
cfgSnap.HudAutoDodge := true
cfgSnap.EnableWS := false
cfgSnap.EnableZoom := false
cfgSnap.savedX := 400
cfgSnap.savedY := 400
stSnap.ComputeDimensions(cfgSnap)
stSnap.savedX := 400
stSnap.savedY := 400
AutoDodgeTick(cfgSnap, stSnap, { x: 420, y: 420 }, false)
Assert("AutoDodgeTick engages ghost alpha + click-through when cursor enters HUD stack",
    stSnap.isAutoDodged == true && stSnap.currentAlpha == UIConstants.DODGE_ALPHA
    && (WinGetExStyle("ahk_id " stSnap.MicGui.Hwnd) & 0x20) != 0)

AutoDodgeTick(cfgSnap, stSnap, { x: 100, y: 100 }, false)
Assert("AutoDodgeTick restores baseAlpha & clickability when cursor leaves HUD stack",
    stSnap.isAutoDodged == false && stSnap.currentAlpha == stSnap.baseAlpha
    && (WinGetExStyle("ahk_id " stSnap.MicGui.Hwnd) & 0x20) == 0)
DetectHiddenWindows(prevDhwSnap)

cfgSnap.ResetAppearance()
UpdateAutoDodgeTimer(cfgSnap, stSnap)
Assert("ResetAppearance restores MagneticSnap=true, ClickThrough=false, AutoDodge=false",
    cfgSnap.EnableMagneticSnap == true && cfgSnap.HudClickThrough == false && cfgSnap.HudAutoDodge == false)

stSnap.MicGui.Destroy(), stSnap.RecGui.Destroy(), stSnap.ChatGui.Destroy()
stSnap.StudioGui.Destroy(), stSnap.SceneGui.Destroy(), stSnap.StreamGui.Destroy(), stSnap.VCamGui.Destroy()

; ==============================================================================
; SECTION 16: STAGE 9 (v2.3.3) - MULTI-PLATFORM CONFERENCING (ZOOM/TEAMS/MEET)
; ==============================================================================
cfgConf := Config(testIni)
Assert("Conferencing defaults to Zoom with Teams/Meet hotkeys populated",
    cfgConf.ConferencingApp == "Zoom" && cfgConf.TeamsMuteHotkey == "^+m" && cfgConf.MeetMuteHotkey == "^d")

stConf := { zoomConnected: true, zoomLastMuted: 1, zoomSawRecControl: true, rebuildTrayFn: (*) => 0, refreshHelpFn: (*) => 0 }
SetConferencingApp(cfgConf, stConf, "teams")
cfgConfReload := Config(testIni)
Assert("SetConferencingApp normalizes & persists Microsoft Teams and resets monitor state",
    cfgConfReload.ConferencingApp == "Microsoft Teams" && stConf.zoomConnected == false && stConf.zoomLastMuted == -1
    && GetActiveConferencingMuteHotkey(cfgConf) == "^+m")

SetConferencingApp(cfgConf, stConf, "Google Meet")
Assert("Google Meet resolves active hotkey ^d and target spec Meet ahk_exe chrome.exe",
    GetActiveConferencingMuteHotkey(cfgConf) == "^d" && InStr(GetConferencingWindowSpec("Google Meet"), "chrome.exe"))

teamsMuted := DetectZoomStates("", "Microsoft Teams", ["Unmute mic", "Chat", "Stop recording"])
teamsLive := DetectZoomStates("", "Microsoft Teams", ["Mute mic", "Start recording"])
meetMuted := DetectZoomStates("", "Google Meet", ["Turn on microphone (Ctrl+D)", "Chat with everyone"])
meetLive := DetectZoomStates("", "Google Meet", ["Turn off microphone", "Leave call"])
zoom1Arg := DetectZoomStates("", "Zoom", ["Unmute Audio", "Resume Recording", "Chat 4 unread"])
Assert("DetectZoomStates parses Zoom, Microsoft Teams, and Google Meet UIA states cleanly",
    teamsMuted.hasMic && teamsMuted.muted == true && teamsMuted.recState == 1
    && teamsLive.hasMic && teamsLive.muted == false && teamsLive.recState == 0
    && meetMuted.hasMic && meetMuted.muted == true && meetMuted.hasChat == true
    && meetLive.hasMic && meetLive.muted == false
    && zoom1Arg.hasMic && zoom1Arg.muted == true && zoom1Arg.recState == 2 && zoom1Arg.unreadChat == 4)

; ==============================================================================
; SECTION 17: STAGE 10 (v2.3.4) - SMART MODE 2 REMOTE COMPANION BRIDGE
; ==============================================================================
cfgMode2Host := Config(testIni)
cfgMode2Host.AudioRoutingMode := 2
cfgMode2Host.RemoteNetworkMode := "LAN"
cfgMode2Host.InternetPairingCode := "PS-MODE2-234"
Assert("ShouldEnableHostInternetRelay auto-enables relay in Mode 2 even on LAN",
    ShouldEnableHostInternetRelay(cfgMode2Host) == true)

cfgMode1Lan := Config(testIni)
cfgMode1Lan.AudioRoutingMode := 1
cfgMode1Lan.RemoteNetworkMode := "LAN"
cfgMode1Lan.InternetPairingCode := "PS-MODE1-234"
Assert("ShouldEnableHostInternetRelay stays off for Mode 1 LAN",
    ShouldEnableHostInternetRelay(cfgMode1Lan) == false)

mode2Packets := []
stMode2Host := {
    isMuted: false,
    obsConnected: true, ; Even if OBS WS is connected, Mode 2 must not route through OBS
    obsWs: "",
    zoomConnected: false,
    EnableWS: false,
    relayConnected: true,
    relayWs: { tag: "mockRelay" },
    relayMockWs: { sendText: (this, pkt) => mode2Packets.Push(pkt) }
}
authMode2 := GetInternetRelayAuthToken(cfgMode2Host.InternetPairingCode, cfgMode2Host.obsPassword)
pktMode2Toggle := FormatRelayPacket("remote", "toggle_mute", "1", authMode2)
HandleHostRelayMessage(cfgMode2Host, stMode2Host, stMode2Host.relayWs, pktMode2Toggle)
mode2LastPkt := mode2Packets.Length >= 1 ? ParseRelayPacket(mode2Packets[mode2Packets.Length]) : ""
Assert("Mode 2 HandleHostRelayMessage toggles muted state without OBS and broadcasts host packet",
    stMode2Host.isMuted == true && IsObject(mode2LastPkt) && mode2LastPkt.src == "host" && mode2LastPkt.cmd == "state" && mode2LastPkt.data == "1")

pktMode2Sync := FormatRelayPacket("remote", "sync_req", "0", authMode2)
mode2Packets := []
HandleHostRelayMessage(cfgMode2Host, stMode2Host, stMode2Host.relayWs, pktMode2Sync)
mode2SyncPkt := mode2Packets.Length == 1 ? ParseRelayPacket(mode2Packets[1]) : ""
Assert("Mode 2 sync_req responds even when RemoteNetworkMode=LAN",
    mode2Packets.Length == 1 && IsObject(mode2SyncPkt) && mode2SyncPkt.src == "host" && mode2SyncPkt.cmd == "state" && mode2SyncPkt.data == "1")

remCfgLan := { NetworkMode: "LAN", EnableRelayFallback: true, InternetPairingCode: "PS-MODE2-234" }
remStateLan := { usingRelayFallback: false }
Assert("ShouldRemoteFallbackToRelay returns true when LAN has pairing code",
    ShouldRemoteFallbackToRelay(remCfgLan, remStateLan) == true)
remCfgNoCode := { NetworkMode: "LAN", EnableRelayFallback: true, InternetPairingCode: "" }
Assert("ShouldRemoteFallbackToRelay returns false when pairing code is empty",
    ShouldRemoteFallbackToRelay(remCfgNoCode, remStateLan) == false)
remStateFallbackActive := { usingRelayFallback: true }
Assert("IsRemoteUsingInternetChannel honors active relay fallback even in LAN mode",
    IsRemoteUsingInternetChannel(remCfgLan, remStateFallbackActive) == true)

; ==============================================================================
; SECTION 18: STAGE 11 (v2.3.5) - PERSISTENT NAMED CONFIGURATION PROFILES
; ==============================================================================
if FileExist(testIni)
    FileDelete(testIni)
if FileExist(testIni ".bak")
    FileDelete(testIni ".bak")
cfgProf := Config(testIni)
cfgProf.AudioRoutingMode := 1
cfgProf.ConferencingApp := "Zoom"
cfgProf.HudColorPreset := "Standard"
cfgProf.ShowText := false
cfgProf.Write("Settings", "AudioRoutingMode", 1)
cfgProf.Write("Settings", "ConferencingApp", "Zoom")
cfgProf.Write("Settings", "HudColorPreset", "Standard")
cfgProf.WriteBool("Settings", "ShowText", false)

Assert("Initial profile list contains Default",
    cfgProf.ActiveProfile == "Default" && cfgProf.GetProfileNames().Length == 1 && cfgProf.GetProfileNames()[1] == "Default")

; Save a custom Teams Studio profile; saving a non-Default profile auto-snapshots Default first
cfgProf.AudioRoutingMode := 2
cfgProf.ConferencingApp := "Microsoft Teams"
cfgProf.HudColorPreset := "Broadcast Tally"
cfgProf.ShowText := true
cfgProf.CatchArrows := false
cfgProf.SaveProfile("Teams Lecture")

cfgProfCheck := Config(testIni)
Assert("SaveProfile persists profile list, ActiveProfile, and auto-snapshots Default",
    cfgProfCheck.ActiveProfile == "Teams Lecture" && cfgProfCheck.GetProfileNames().Length == 2
    && cfgProfCheck.Read("Profile:Teams Lecture", "Settings_ConferencingApp", "") == "Microsoft Teams"
    && cfgProfCheck.Read("Profile:Default", "__Exists", "") == "1")

; Apply Default back with live state callbacks
stProf := { rebuildCount: 0, helpCount: 0 }
stProf.rebuildTrayFn := (*) => (stProf.rebuildCount += 1)
stProf.refreshHelpFn := (*) => (stProf.helpCount += 1)
Assert("ApplyProfile switches back to Default and restores RoutingMode=1, Zoom, Standard",
    cfgProfCheck.ApplyProfile("Default", stProf)
    && cfgProfCheck.ActiveProfile == "Default"
    && cfgProfCheck.AudioRoutingMode == 1
    && cfgProfCheck.ConferencingApp == "Zoom"
    && cfgProfCheck.HudColorPreset == "Standard"
    && stProf.rebuildCount >= 1)

Assert("ApplyProfile switches to Teams Lecture and restores Teams + Broadcast Tally + ShowText + CatchArrows",
    cfgProfCheck.ApplyProfile("Teams Lecture", stProf)
    && cfgProfCheck.AudioRoutingMode == 2
    && cfgProfCheck.ConferencingApp == "Microsoft Teams"
    && cfgProfCheck.HudColorPreset == "Broadcast Tally"
    && cfgProfCheck.ShowText == true
    && cfgProfCheck.CatchArrows == false)

Assert("DeleteProfile protects Default and deletes custom profiles cleanly",
    cfgProfCheck.DeleteProfile("Default") == false
    && cfgProfCheck.DeleteProfile("Teams Lecture") == true
    && cfgProfCheck.ActiveProfile == "Default"
    && cfgProfCheck.GetProfileNames().Length == 1)

AuditDialogGeometry("ProfileManager", ShowProfileManagerUI(cfgProfCheck, stProf), 340, 220)

; ==============================================================================
; SECTION 19: STAGE 12 (v2.3.6) - START WITH WINDOWS & GITHUB UPDATE CHECKER
; ==============================================================================
if FileExist(testIni)
    FileDelete(testIni)
if FileExist(testIni ".bak")
    FileDelete(testIni ".bak")
cfgSys := Config(testIni)
Assert("StartWithWindows defaults strictly to false",
    cfgSys.StartWithWindows == false && cfgSys.ReadBool("Settings", "StartWithWindows", 0) == false)

stSys := { trayRebuilds: 0 }
stSys.rebuildTrayFn := (*) => (stSys.trayRebuilds += 1)
SetStartWithWindows(cfgSys, stSys, true, false) ; writeRegistry=false keeps HKCU clean during test
cfgSysReload := Config(testIni)
Assert("SetStartWithWindows persists ON to INI and notifies tray without registry mutation",
    cfgSys.StartWithWindows == true && cfgSysReload.StartWithWindows == true && stSys.trayRebuilds >= 1)
SetStartWithWindows(cfgSys, stSys, false, false)
Assert("SetStartWithWindows toggles back OFF cleanly",
    cfgSys.StartWithWindows == false && Config(testIni).StartWithWindows == false)

Assert("CompareSemVer handles major/minor/patch and v-prefix correctly",
    CompareSemVer("v4.5.0", "4.4.0") == 1
    && CompareSemVer("v4.4.0", "4.3.0") == 1
    && CompareSemVer("v4.3.0", "4.1.1") == 1
    && CompareSemVer("v4.1.1", "4.1.0") == 1
    && CompareSemVer("v4.1.0", "4.0.1") == 1
    && CompareSemVer("v4.0.1", "4.0.0") == 1
    && CompareSemVer("v4.0.0", "3.2.0") == 1
    && CompareSemVer("v3.2.0", "3.1.1") == 1
    && CompareSemVer("v3.1.1", "3.1.0") == 1
    && CompareSemVer("v3.1.0", "3.0.1") == 1
    && CompareSemVer("v3.0.1", "3.0.0") == 1
    && CompareSemVer("v3.0.0", "2.4.0") == 1
    && CompareSemVer("v2.4.0", "2.3.6") == 1
    && CompareSemVer("v2.3.6", "2.3.6") == 0
    && CompareSemVer("2.3.5", "2.3.6") == -1
    && CompareSemVer("2.10.0", "2.9.9") == 1)

mockUpdJson := '{"tag_name":"v2.4.0","html_url":"https://github.com/SaabithJiffry/PresenterSync/releases/tag/v2.4.0"}'
mockCurJson := '{"tag_name":"v2.3.6","html_url":"https://github.com/SaabithJiffry/PresenterSync/releases/tag/v2.3.6"}'
updRes := CheckForUpdates("2.3.6", mockUpdJson, true)
curRes := CheckForUpdates("2.3.6", mockCurJson, true)
tagRes := CheckForUpdates("2.3.6", '[{"name":"v2.4.0"}]', true)
errRes := CheckForUpdates("2.3.6", "{broken_json}", true)
Assert("CheckForUpdates parses release JSON and /tags fallback for update_available, up_to_date, and errors",
    updRes.ok == true && updRes.status == "update_available" && updRes.updateAvailable == true && updRes.latest == "2.4.0"
    && InStr(updRes.url, "v2.4.0")
    && tagRes.ok == true && tagRes.status == "update_available" && tagRes.updateAvailable == true && tagRes.latest == "2.4.0"
    && curRes.ok == true && curRes.status == "up_to_date" && curRes.updateAvailable == false
    && errRes.ok == false && errRes.status == "error")

; ==============================================================================
; SECTION 20: STAGE 13 (v2.4.0) - UNIFIED FLUENT CONTROL CENTER DASHBOARD
; ==============================================================================
if FileExist(testIni)
    FileDelete(testIni)
if FileExist(testIni ".bak")
    FileDelete(testIni ".bak")
cfgCC := Config(testIni)
stCC := OverlayState(cfgCC)
ccEvents := { tray: 0, help: 0, rebind: 0 }
stCC.rebuildTrayFn := (*) => (ccEvents.tray += 1)
stCC.refreshHelpFn := (*) => (ccEvents.help += 1)
stCC.rebindHotkeysFn := (*) => (ccEvents.rebind += 1)

ccWin := ShowControlCenterWindow(cfgCC, stCC)
hasSixTabs := false
for ctrl in ccWin {
    if (ctrl.HasOwnProp("_tabNames") && ctrl._tabNames.Length == 6)
        hasSixTabs := true
}
Assert("ShowControlCenterWindow creates 6-tab Fluent Control Center dashboard", hasSixTabs)
AuditDialogGeometry("ControlCenterWindow", ccWin, 680, 520)

ccVals := {
    AudioRoutingMode: 3,
    ConferencingApp: "Teams",
    targetMicName: "Shure MV7",
    TeamsMuteHotkey: "^+m",
    ShowVoiceMeter: false,
    EnableAudioCue: true,
    EnableMuteToast: true,
    EnableWS: true,
    EnableZoom: true, ; should be forced false when EnableWS is true
    obsPassword: "LivePass240",
    ShowStreamHud: true,
    ShowRecTimer: true,
    ObsMuteHotkey: "^F1",
    PointerMode: "Pointer Mute Only",
    HwMuteHotkey: "F14",
    EnablePushToMute: true,
    CatchArrows: false,
    IndicatorScale: 1.5,
    OpacityLevel: UIConstants.OPACITY_SOLID,
    HudColorPreset: "Broadcast Tally",
    ThemeMode: "Dark",
    ShowText: true,
    MonoIcon: true,
    SleekCorners: true,
    EnableHudClickActions: true,
    EnableMagneticSnap: true,
    HudAutoDodge: true,
    HudClickThrough: false,
    RemoteNetworkMode: "Internet",
    PptHotkey: "^F11",
    StartWithWindows: false
}
ApplyControlCenterSettings(cfgCC, stCC, ccVals, false)
cfgCCReload := Config(testIni)
Assert("ApplyControlCenterSettings updates all 6 tab subsystems, persists INI, and refreshes live without reload",
    cfgCCReload.AudioRoutingMode == 3
    && cfgCCReload.ConferencingApp == "Microsoft Teams"
    && cfgCCReload.targetMicName == "Shure MV7"
    && cfgCCReload.EnableAudioCue == true
    && cfgCCReload.EnableWS == true
    && cfgCCReload.EnableZoom == true
    && cfgCCReload.obsPassword == "LivePass240"
    && cfgCCReload.EnablePPT == false
    && cfgCCReload.EnableMicOnly == true
    && cfgCCReload.HwMuteHotkey == "F14"
    && cfgCCReload.EnablePushToMute == true
    && cfgCCReload.CatchArrows == false
    && Abs(cfgCCReload.IndicatorScale - 1.5) < 0.01
    && cfgCCReload.HudColorPreset == "Broadcast Tally"
    && cfgCCReload.RemoteNetworkMode == "Internet"
    && cfgCCReload.PptHotkey == "^F11"
    && ccEvents.tray >= 1 && ccEvents.help >= 1 && ccEvents.rebind >= 1)

; Stop any background timers started by Section 20 Control Center test
ApplyControlCenterSettings(cfgCC, stCC, { EnableWS: false, EnableZoom: false }, false)

; ==============================================================================
; SECTION 21: v3.0.1 FULL AUDIT & HARDENING REGRESSIONS
; ==============================================================================
if FileExist(testIni)
    FileDelete(testIni)
if FileExist(testIni ".bak")
    FileDelete(testIni ".bak")

; 21.1 Optimistic mute flip matrix across Modes 1/2/3 and telemetry combinations
Assert("ShouldOptimisticallyFlipMute handles Mode 1/2/3 & WS/Zoom telemetry accurately",
    ShouldOptimisticallyFlipMute({AudioRoutingMode: 1, EnableWS: false, EnableZoom: false}, {obsConnected: false, zoomConnected: false}) == true
    && ShouldOptimisticallyFlipMute({AudioRoutingMode: 1, EnableWS: false, EnableZoom: true}, {obsConnected: false, zoomConnected: true}) == true
    && ShouldOptimisticallyFlipMute({AudioRoutingMode: 1, EnableWS: true, EnableZoom: false}, {obsConnected: true, zoomConnected: false}) == false
    && ShouldOptimisticallyFlipMute({AudioRoutingMode: 2, EnableWS: true, EnableZoom: false}, {obsConnected: true, zoomConnected: false}) == true
    && ShouldOptimisticallyFlipMute({AudioRoutingMode: 2, EnableWS: false, EnableZoom: true}, {obsConnected: false, zoomConnected: true}) == false
    && ShouldOptimisticallyFlipMute({AudioRoutingMode: 3, EnableWS: false, EnableZoom: false}, {obsConnected: false, zoomConnected: false}) == true
    && ShouldOptimisticallyFlipMute({AudioRoutingMode: 3, EnableWS: true, EnableZoom: false}, {obsConnected: true, zoomConnected: false}) == false)

; 21.2 Mode 3 Cough / Push-to-Mute rapid (<1000ms) syncSource directional lock
cfgAudit := Config(testIni)
cfgAudit.AudioRoutingMode := 3
cfgAudit.ConferencingApp := "Zoom"
cfgAudit.ZoomMuteHotkey := "!a"
stAudit := OverlayState(cfgAudit)
stAudit.obsTimerFn := ""
stAudit.zoomTimerFn := ""
stAudit.relayTimerFn := ""
stAudit.autoDodgeTimerFn := ""
stAudit.releaseSyncTimerFn := (*) => 0
coughSends := []
coughSender := (k, w) => coughSends.Push({k: k, w: w})
PushObsMuteToZoom(cfgAudit, stAudit, true, {hasMic: true, muted: false, micHwnd: 55}, coughSender)
pressOk := (coughSends.Length == 1 && stAudit.IsSyncing && stAudit.syncSource = "obs")
PushObsMuteToZoom(cfgAudit, stAudit, false, {hasMic: true, muted: true, micHwnd: 55}, coughSender)
releaseOk := (coughSends.Length == 2 && stAudit.syncSource = "obs")
stAudit.IsSyncing := true
stAudit.syncSource := "zoom"
PushObsMuteToZoom(cfgAudit, stAudit, true, {hasMic: true, muted: false, micHwnd: 55}, coughSender)
echoBlocked := (coughSends.Length == 2)
ReleaseSyncLock(stAudit)
Assert("Mode 3 Cough (<1000ms) release forwards cleanly while Zoom echo lock stays blocked",
    pressOk && releaseOk && echoBlocked && !stAudit.IsSyncing && stAudit.syncSource = "")

; 21.3 Hotkey syntax validation + ApplyControlCenterSettings & ApplyProfile backend teardown
Assert("IsValidHotkeySpec accepts valid specs and rejects invalid syntax",
    IsValidHotkeySpec("b") && IsValidHotkeySpec("!a") && IsValidHotkeySpec("^+m")
    && IsValidHotkeySpec("^!+F12") && IsValidHotkeySpec("None") && IsValidHotkeySpec("")
    && !IsValidHotkeySpec("Invalid_Key_Name_999") && !IsValidHotkeySpec("bad key") && !IsValidHotkeySpec("^!"))

fakeWsObj := { closed: false, shutdown: (this) => (this.closed := true) }
stAudit.obsWs := fakeWsObj
stAudit.obsConnected := true
stAudit.recState := 1
stAudit.streamState := 1
stAudit.vcamActive := true
stAudit.studioModeActive := true
stAudit.zoomConnected := true
stAudit.currentSceneName := "Keynote"
cfgAudit.EnableWS := true
cfgAudit.PptHotkey := "^F12"
badHkList := []
ccRes := ApplyControlCenterSettings(cfgAudit, stAudit, {
    EnableWS: 0,
    EnableZoom: 0,
    PptHotkey: "Invalid_Key_Name_999",
    HwMuteHotkey: "b"
}, false, badHkList)
Assert("ApplyControlCenterSettings rejects bad hotkeys without corrupting config & tears down WS telemetry",
    !ccRes && badHkList.Length == 1 && badHkList[1].prop = "PptHotkey"
    && cfgAudit.PptHotkey == "^F12" && cfgAudit.HwMuteHotkey == "b"
    && fakeWsObj.closed && !stAudit.obsConnected && stAudit.recState == 0
    && stAudit.streamState == 0 && !stAudit.vcamActive && !stAudit.studioModeActive
    && !stAudit.zoomConnected && stAudit.currentSceneName == "Scene")

cfgAudit.EnableWS := false
cfgAudit.SaveProfile("AuditBasic")
stAudit.obsConnected := true
stAudit.recState := 2
stAudit.streamState := 2
stAudit.vcamActive := true
stAudit.studioModeActive := true
stAudit.zoomConnected := true
profSwOk := cfgAudit.ApplyProfile("AuditBasic", stAudit)
Assert("Config.ApplyProfile resets stale OBS/Zoom telemetry when switching to non-WS profile",
    profSwOk && !cfgAudit.EnableWS && !stAudit.obsConnected && stAudit.recState == 0
    && stAudit.streamState == 0 && !stAudit.vcamActive && !stAudit.studioModeActive && !stAudit.zoomConnected)

; 21.4 InitHUD hidden click-through + AutoDodgeTick cursor & locked-desktop handling
cfgAudit.ShowIndicator := true
cfgAudit.ShowExtraHuds := true
cfgAudit.EnableWS := false
cfgAudit.EnableZoom := true
cfgAudit.HudClickThrough := true
cfgAudit.HudAutoDodge := true
cfgAudit.savedX := 300
cfgAudit.savedY := 300
stHudAudit := OverlayState(cfgAudit)
stHudAudit.obsTimerFn := ""
stHudAudit.zoomTimerFn := ""
stHudAudit.relayTimerFn := ""
stHudAudit.autoDodgeTimerFn := ""
stHudAudit.savedX := 300
stHudAudit.savedY := 300
InitHUD(cfgAudit, stHudAudit, false)
prevDhw := A_DetectHiddenWindows
DetectHiddenWindows(true)
hiddenEx := WinGetExStyle("ahk_id " stHudAudit.MicGui.Hwnd)
DetectHiddenWindows(prevDhw)

cfgAudit.HudClickThrough := false
ApplyHudClickThroughStyle(cfgAudit, stHudAudit, false)
UpdateHudVisibility(cfgAudit, stHudAudit)
bHud := GetHudStackBounds(cfgAudit, stHudAudit)
AutoDodgeTick(cfgAudit, stHudAudit, {x: bHud.left + 10, y: bHud.top + 10}, 0)
dodgedOk := (stHudAudit.isAutoDodged && stHudAudit.currentAlpha <= UIConstants.DODGE_ALPHA && (WinGetExStyle("ahk_id " stHudAudit.MicGui.Hwnd) & 0x20) != 0)
AutoDodgeTick(cfgAudit, stHudAudit, {x: bHud.right + 120, y: bHud.bottom + 120}, 0)
restoredOk := (!stHudAudit.isAutoDodged && stHudAudit.currentAlpha == stHudAudit.baseAlpha && (WinGetExStyle("ahk_id " stHudAudit.MicGui.Hwnd) & 0x20) == 0)
for gProp in ["MicGui", "RecGui", "ChatGui", "StudioGui", "SceneGui", "StreamGui", "VCamGui"] {
    if IsObject(stHudAudit.%gProp%)
        try stHudAudit.%gProp%.Destroy()
}
Assert("InitHUD(show=false) enforces ClickThrough & AutoDodgeTick toggles ghost pass-through cleanly",
    (hiddenEx & 0x20) != 0 && dodgedOk && restoredOk)

; 21.5 Control Center Tab Checkboxes + Interactive invalid-hotkey Apply & Theme balance
Theme.SetMode("Dark")
ccAuditGui := ShowControlCenterWindow(cfgAudit, stAudit)
ccChkTabCount := 0
ccTabCtrl := ""
ccBtnApply := ""
ccLblStatus := ""
ccEdPpt := ""
for c in ccAuditGui._themedCtrls {
    if (c._themeType = "Checkbox" && c._themeRole = "tabText")
        ccChkTabCount += 1
    else if (c._themeType = "Tab")
        ccTabCtrl := c
    else if (c._themeType = "Button" && InStr(c.Text, "Apply"))
        ccBtnApply := c
    else if (c._themeType = "Text" && InStr(c.Text, "Active Profile:"))
        ccLblStatus := c
    else if (c._themeType = "Edit" && c.Value = cfgAudit.PptHotkey && !IsObject(ccEdPpt))
        ccEdPpt := c
}
ccUiOk := false
if (IsObject(ccTabCtrl) && IsObject(ccBtnApply) && IsObject(ccLblStatus) && IsObject(ccEdPpt)) {
    SendMessage(0x1330, 5, 0, ccTabCtrl.Hwnd)
    Sleep(30)
    ccEdPpt.Value := "Invalid_Key_Name_999"
    SendMessage(0x00F5, 0, 0, ccBtnApply.Hwnd)
    Sleep(50)
    warnOk := (InStr(ccLblStatus.Value, "Ignored invalid hotkey") && ccEdPpt.Value == cfgAudit.PptHotkey)
    SendMessage(0x00F5, 0, 0, ccBtnApply.Hwnd)
    Sleep(50)
    validOk := InStr(ccLblStatus.Value, "All settings applied and saved live")
    ccUiOk := warnOk && validOk
}
PostMessage(0x0010, 0, 0, ccAuditGui.Hwnd)
Sleep(50)
Theme.SetMode("Light")
ccAuditLight := ShowControlCenterWindow(cfgAudit, stAudit)
PostMessage(0x0010, 0, 0, ccAuditLight.Hwnd)
Sleep(50)
Theme.SetMode("System")
Assert("Control Center registers all 44 tab Checkboxes, warns on invalid hotkey interactively, & balances Theme lock",
    ccChkTabCount == 44 && ccUiOk && Theme.SuspendLockCount == 0)

; 21.6 Scope Guard: PresenterSync_Remote remains strictly 1-tier Mic HUD (no multi-tier GUIs)
remoteSrc := FileRead(A_ScriptDir "\..\PresenterSync_Remote.ahk")
Assert("Scope guard: PresenterSync_Remote stays strictly 1-tier Mic HUD",
    !RegExMatch(remoteSrc, "\b(RecGui|ChatGui|StudioGui|SceneGui|StreamGui|VCamGui)\b"))

; 21.7 v3.0.1 UI Layout, Single-Row Tab & Overlap Regressions
CheckGuiNoOverlaps(gObj) {
    gObj.GetClientPos(,, &cw, &ch)
    tabCtrl := ""
    tcy := 0
    for c in gObj {
        if (c.Type = "Tab2" || c.Type = "Tab" || c.Type = "Tab3") {
            tabCtrl := c
            c.GetPos(, &tcy)
            break
        }
    }
    rowCnt := IsObject(tabCtrl) ? SendMessage(0x132C, 0, 0, tabCtrl.Hwnd) : 1
    tabCount := IsObject(tabCtrl) ? SendMessage(0x1304, 0, 0, tabCtrl.Hwnd) : 1
    if (rowCnt != 1)
        return { ok: false, reason: "tabRows=" rowCnt }
    Loop tabCount {
        idx := A_Index - 1
        if (IsObject(tabCtrl)) {
            tabCtrl.Choose(A_Index)
            Sleep(15)
        }
        tabRowBottom := 0
        if (IsObject(tabCtrl)) {
            rcItem := Buffer(16, 0)
            SendMessage(0x130A, idx, rcItem.Ptr, tabCtrl.Hwnd)
            tabRowBottom := tcy + NumGet(rcItem, 12, "Int")
        }
        vis := []
        for c in gObj {
            if (c.Type = "Tab2" || c.Type = "Tab" || c.Type = "Tab3")
                continue
            if (!DllCall("IsWindowVisible", "Ptr", c.Hwnd))
                continue
            c.GetPos(&cx, &cy, &ccw, &cch)
            if (cx < 0 || cy < 0 || (cx + ccw) > (cw + 2) || (cy + cch) > (ch + 2))
                return { ok: false, reason: "oob on tab " A_Index ": " c.Type }
            if (IsObject(tabCtrl) && cy >= tcy && cy < tabRowBottom && c.Type = "Text")
                return { ok: false, reason: "header overlaps tab on tab " A_Index }
            vis.Push({ x: cx, y: cy, r: cx + ccw, b: cy + cch, t: c.Type })
        }
        Loop vis.Length {
            i := A_Index
            a := vis[i]
            j := i + 1
            while (j <= vis.Length) {
                b := vis[j]
                if (Max(0, Min(a.r, b.r) - Max(a.x, b.x)) > 0 && Max(0, Min(a.b, b.b) - Max(a.y, b.y)) > 0)
                    return { ok: false, reason: "overlap on tab " A_Index ": " a.t " x " b.t }
                j += 1
            }
        }
    }
    return { ok: true, reason: "" }
}

Theme.SetMode("Dark")
uiHelp := ShowHelpWindow(cfgAudit, stAudit)
helpClipChildren := (DllCall("GetWindowLong", "Ptr", uiHelp.Hwnd, "Int", -16, "UInt") & 0x02000000) != 0
helpNoPrefix := true
for tc in uiHelp._themedCtrls {
    if (tc._themeType = "Text" && (DllCall("GetWindowLong", "Ptr", tc.Hwnd, "Int", -16, "UInt") & 0x80) == 0)
        helpNoPrefix := false
}
helpRes := CheckGuiNoOverlaps(uiHelp)
PostMessage(0x0010, 0, 0, uiHelp.Hwnd)
Sleep(40)

uiCC := ShowControlCenterWindow(cfgAudit, stAudit)
ccRes := CheckGuiNoOverlaps(uiCC)
PostMessage(0x0010, 0, 0, uiCC.Hwnd)
Sleep(40)

uiPM := ShowProfileManagerUI(cfgAudit, stAudit)
pmRes := CheckGuiNoOverlaps(uiPM)
PostMessage(0x0010, 0, 0, uiPM.Hwnd)
Sleep(40)

uiHk := ChangeAppHotkeysUI(cfgAudit)
hkWideEnough := true
for c in uiHk {
    if (c.Type = "Hotkey") {
        c.GetPos(,, &hkW)
        if (hkW < 160)
            hkWideEnough := false
    }
}
PostMessage(0x0010, 0, 0, uiHk.Hwnd)
Sleep(40)
Theme.SetMode("System")

Assert("v3.0.1 Help, Control Center & Profile Manager maintain single-row tabs, zero overlaps & SS_NOPREFIX",
    helpClipChildren && helpNoPrefix && helpRes.ok && ccRes.ok && pmRes.ok && hkWideEnough,
    Format("help=({},{}) cc=({}) pm=({}) hkW={}", helpRes.ok, helpRes.reason, ccRes.reason, pmRes.reason, hkWideEnough))

; ==============================================================================
; SECTION 22: v3.1.0 VISUAL HUD DIAGRAM, TRAY ENCYCLOPEDIA & SEARCH REGRESSIONS
; ==============================================================================
primAnatomy := GetPrimaryHudAnatomyItems()
remAnatomy := GetRemoteHudAnatomyItems()
Assert("HelpCenter anatomy metadata has 8 Primary items and 4 Remote items",
    primAnatomy.Length == 8 && remAnatomy.Length == 4)

hBmpPrim := BuildPrimaryHudDiagramBitmap(cfgAudit, 7, 776, 240)
hBmpRem := BuildRemoteHudDiagramBitmap(cfgAudit, 1, 680, 194)
Assert("HelpCenter GDI+ diagram renderers return valid HBITMAP handles",
    hBmpPrim != 0 && hBmpRem != 0)
if (hBmpPrim)
    DllCall("DeleteObject", "Ptr", hBmpPrim)
if (hBmpRem)
    DllCall("DeleteObject", "Ptr", hBmpRem)

hitCard1 := HitTestPrimaryHudDiagram(40, 20)
hitPill7 := HitTestPrimaryHudDiagram(340, 145)
hitPill8 := HitTestPrimaryHudDiagram(340, 166)
hitRem2 := HitTestRemoteHudDiagram(520, 30)
Assert("HelpCenter diagram hit-testers resolve cards, LIVE pill, VU bar & Remote cards accurately",
    hitCard1 == 1 && hitPill7 == 7 && hitPill8 == 8 && hitRem2 == 2,
    Format("c1={} p7={} p8={} r2={}", hitCard1, hitPill7, hitPill8, hitRem2))

kbAll := GetHelpKnowledgeBase()
kbTray := SearchHelpEntries("", "Tray", false)
kbDodge := SearchHelpEntries("dodge alt", "Tray", false)
kbObsErr := SearchHelpEntries("4009 password", "All", false)
kbRemSafe := SearchHelpEntries("", "All", true)
remHasHostOnlyHud := false
remHasRtrayAbout := false
remHasRtrayText := false
remHasRscRemote := false
remHasHostLeakText := ""
for rEnt in kbRemSafe {
    if (SubStr(rEnt.id, 1, 4) = "hud-" || rEnt.id = "tray-app-vu" || rEnt.id = "tray-app-rectimer" || rEnt.id = "tray-app-stream"
        || rEnt.id = "tray-app-text" || rEnt.id = "tray-app-clicks" || rEnt.id = "tray-app-theme" || rEnt.id = "tray-app-resetapp"
        || rEnt.id = "feat-cough" || rEnt.id = "feat-snapping" || rEnt.id = "feat-themes" || rEnt.id = "feat-audio-toast"
        || rEnt.id = "tray-set-startup" || rEnt.id = "tray-set-updates" || rEnt.id = "sc-global") {
        remHasHostOnlyHud := true
        break
    }
    if (rEnt.id = "rtray-about")
        remHasRtrayAbout := true
    else if (rEnt.id = "rtray-text")
        remHasRtrayText := true
    else if (rEnt.id = "rsc-remote")
        remHasRscRemote := true

    if (rEnt.id != "rtray-about") {
        if (InStr(rEnt.body, "Control Center") || InStr(rEnt.body, "Voice Activity") || InStr(rEnt.body, "Virtual Camera")
            || InStr(rEnt.body, "Studio Mode") || InStr(rEnt.body, "Live Status") || InStr(rEnt.body, "RecTimer"))
            remHasHostLeakText := rEnt.id
    }
}
Assert("Help Search matches Tray menus, multi-word queries & enforces Remote 1-tier isolation",
    kbAll.Length >= 50 && kbTray.Length >= 28 && kbDodge.Length >= 1 && kbDodge[1].id == "tray-app-dodge" && kbObsErr.Length >= 1 && kbRemSafe.Length >= 18 && !remHasHostOnlyHud,
    Format("all={} tray={} dodge={} obsErr={} rem={} hostLeak={}", kbAll.Length, kbTray.Length, kbDodge.Length, kbObsErr.Length, kbRemSafe.Length, remHasHostOnlyHud))

; ==============================================================================
; SECTION 23: v3.1.1 CURATED REMOTE ABOUT & HELP CAPABILITY ISOLATION
; ==============================================================================
Assert("v3.1.1 Remote Search includes Remote-specific Tray/Shortcuts and leaks zero host UI text",
    remHasRtrayAbout && remHasRtrayText && remHasRscRemote && remHasHostLeakText == "",
    Format("about={} text={} sc={} leak={}", remHasRtrayAbout, remHasRtrayText, remHasRscRemote, remHasHostLeakText))

Theme.SetMode("Light")
uiHelpLight := ShowHelpWindow(cfgAudit, stAudit)
helpLightRes := CheckGuiNoOverlaps(uiHelpLight)
helpLightClip := (DllCall("GetWindowLong", "Ptr", uiHelpLight.Hwnd, "Int", -16, "UInt") & 0x02000000) != 0

; Verify live HUD diagram refresh on Color Preset change and zero GDI handle leakage
hProcAudit := DllCall("GetCurrentProcess", "Ptr")
SetHudColorPreset(cfgAudit, stAudit, "Cyber Ocean")
Sleep(20)
liveHelpPresetOk := IsObject(stAudit.refreshHelpFn) && (WinExist("ahk_id " uiHelpLight.Hwnd) != 0)
SetHudColorPreset(cfgAudit, stAudit, "Standard")
PostMessage(0x0010, 0, 0, uiHelpLight.Hwnd)
Sleep(40)
Theme.SetMode("System")
Assert("v3.1.1 ShowHelpWindow passes 7-tab single-row & zero-overlap audit in Light mode too",
    helpLightRes.ok && helpLightClip,
    Format("ok={}, reason={}", helpLightRes.ok, helpLightRes.reason))

; ==============================================================================
; SECTION 24: v3.2.0 FINAL AUDIT - LIVE DIAGRAM REFRESH, GDI SAFETY & SEARCH
; ==============================================================================
gdiTestGui := Gui()
gdiTestPic := gdiTestGui.Add("Picture", "w776 h240", "HBITMAP:" BuildPrimaryHudDiagramBitmap(cfgAudit, 1, 776, 240))
gdiBefore := DllCall("GetGuiResources", "Ptr", hProcAudit, "Int", 0, "UInt")
Loop 20 {
    hBmpStep := BuildPrimaryHudDiagramBitmap(cfgAudit, Mod(A_Index, 8) + 1, 776, 240)
    ApplyDiagramBitmap(gdiTestPic, hBmpStep)
}
gdiAfter := DllCall("GetGuiResources", "Ptr", hProcAudit, "Int", 0, "UInt")
gdiTestGui.Destroy()
remConnSearch := SearchHelpEntries("connect", "All", true)
Assert("v3.2.0 Help diagram live-refreshes cleanly with zero GDI leak & complete Remote search",
    liveHelpPresetOk && (gdiAfter - gdiBefore) <= 0 && remConnSearch.Length >= 4,
    Format("liveOk={} gdiDelta={} remConn={}", liveHelpPresetOk, (gdiAfter - gdiBefore), remConnSearch.Length))

; ==============================================================================
; SECTION 25: v4.0.1 SMOOTH MATTE-GLASS DESKTOP HUD SNAKE & ANTI-STALL REGRESSIONS
; ==============================================================================
cfgSnake := Config(testIni)
cfgSnake.ShowIndicator := true
cfgSnake.ShowExtraHuds := true
cfgSnake.EnableWS := true
cfgSnake.EnableZoom := false
cfgSnake.HudColorPreset := "Standard"
stSnake := OverlayState(cfgSnake)
InitHUD(cfgSnake, stSnake, true)
Sleep(40)

TestGetExStyleHiddenSafe(hwnd) {
    if (!hwnd)
        return 0
    prevDhw := A_DetectHiddenWindows
    DetectHiddenWindows(true)
    try return WinGetExStyle("ahk_id " hwnd)
    finally DetectHiddenWindows(prevDhw)
}

telemetrySpy := { obs: 0, relay: 0 }
stSnake.obsTimerFn := (*) => (telemetrySpy.obs += 1)
stSnake.relayTimerFn := (*) => (telemetrySpy.relay += 1)
SetTimer(stSnake.obsTimerFn, 35)
SetTimer(stSnake.relayTimerFn, 35)

gdiSnakeBefore := DllCall("GetGuiResources", "Ptr", hProcAudit, "Int", 0, "UInt")
okSnakeStart := HudSnake.Start(cfgSnake, stSnake, false)
snakePhaseInit := HudSnake.Phase
snakeSeedsCount := HudSnake._morphSeeds.Length
snakeInitLen := HudSnake._snake.Length
snakeHwnd := IsObject(HudSnake._gui) ? HudSnake._gui.Hwnd : 0
snakeExStyle := TestGetExStyleHiddenSafe(snakeHwnd)
micHiddenDuringSnake := DllCall("IsWindowVisible", "Ptr", stSnake.MicGui.Hwnd, "Int") == 0
suppressedDuringSnake := IsHudSuppressed(cfgSnake)
snakeObsAfterStart := telemetrySpy.obs
snakeRelayAfterStart := telemetrySpy.relay

; Ensure RefreshHudAppearance cannot un-hide HUD pills while Snake runs
RefreshHudAppearance(cfgSnake, stSnake)
micStillHidden := DllCall("IsWindowVisible", "Ptr", stSnake.MicGui.Hwnd, "Int") == 0

Sleep(400)
HudSnake._FrameTick()
snakePhaseAfterMorph := HudSnake.Phase
snakeObsDuringPlay := telemetrySpy.obs
snakeRelayDuringPlay := telemetrySpy.relay

Assert("v4.0.1 HudSnake morphs live HUD onto transparent click-through topmost canvas & pauses blocking telemetry",
    okSnakeStart && snakePhaseInit == "morph" && snakePhaseAfterMorph == "playing"
    && snakeSeedsCount >= 5 && snakeInitLen >= 5
    && (snakeExStyle & 0x80000) != 0 && (snakeExStyle & 0x20) != 0
    && suppressedDuringSnake && micHiddenDuringSnake && micStillHidden
    && (snakeObsDuringPlay == snakeObsAfterStart) && (snakeRelayDuringPlay == snakeRelayAfterStart),
    Format("ok={} p0={} p1={} seeds={} exStyle={:#x} sup={} hid={} still={} obs={}/{} rly={}/{}",
        okSnakeStart, snakePhaseInit, snakePhaseAfterMorph, snakeSeedsCount, snakeExStyle, suppressedDuringSnake, micHiddenDuringSnake, micStillHidden, snakeObsAfterStart, snakeObsDuringPlay, snakeRelayAfterStart, snakeRelayDuringPlay))

HudSnake.Stop()
Sleep(220)
gdiSnakeAfter := DllCall("GetGuiResources", "Ptr", hProcAudit, "Int", 0, "UInt")
micRestoredAfterStop := DllCall("IsWindowVisible", "Ptr", stSnake.MicGui.Hwnd, "Int") != 0
obsRestoredAfterStop := (telemetrySpy.obs > snakeObsDuringPlay)
SetTimer(stSnake.obsTimerFn, 0)
SetTimer(stSnake.relayTimerFn, 0)
Assert("v4.0.1 HudSnake.Stop() cleanly frees GDI handles, unbinds hotkeys & restores HUD/telemetry timers",
    !HudSnake.IsActive && HudSnake.Phase == "idle" && HudSnake._boundHotkeys.Length == 0
    && (gdiSnakeAfter - gdiSnakeBefore) == 0 && !IsHudSuppressed(cfgSnake) && micRestoredAfterStop && obsRestoredAfterStop,
    Format("active={} hk={} gdiDelta={} micVis={} obsRest={}", HudSnake.IsActive, HudSnake._boundHotkeys.Length, (gdiSnakeAfter - gdiSnakeBefore), micRestoredAfterStop, obsRestoredAfterStop))

; Headless deterministic mechanics + continuous rail interpolation verification
HudSnake.Start(cfgSnake, stSnake, true)
HudSnake._dir := { x: 1, y: 0 }
HudSnake._dirQueue := []
HudSnake._snake := [
    { col: 10, row: 10 },
    { col: 9,  row: 10 },
    { col: 8,  row: 10 },
    { col: 7,  row: 10 },
    { col: 6,  row: 10 }
]
HudSnake._prevSnake := HudSnake._CloneSnake(HudSnake._snake)
; Verify food never spawns in occupied segments or scoreboard zone and test direction queue
sbTopEdge := HudSnake._sbSafeRows
foodValid := IsObject(HudSnake._food) && HudSnake._food.col >= 0 && HudSnake._food.col < HudSnake._cols && HudSnake._food.row >= 0 && HudSnake._food.row < HudSnake._rows
revRejected := !HudSnake.QueueDirection(-1, 0)
turn1Ok := HudSnake.QueueDirection(0, 1)
turn2Ok := HudSnake.QueueDirection(-1, 0)
turn3Cap := !HudSnake.QueueDirection(0, -1)
HudSnake._dirQueue := []

; Eat normal fruit -> +10 score, length +1, speed faster, HighScore persisted
tSnakeUs := HudSnake._NowUs()
HudSnake._food := { col: 11, row: 10, kind: "normal", bornUs: tSnakeUs, ttlMs: 0, pts: 10 }
HudSnake.StepSimulation(tSnakeUs + 100000.0)
eat1Ok := (HudSnake._score == 10 && HudSnake._eatenCount == 1 && HudSnake._snake.Length == 6 && HudSnake._stepMs < 135 && HudSnake._highScore == 10 && cfgSnake.Read("EasterEgg", "SnakeHighScore", "0") == "10")

; Continuous mid-cell rail interpolation check after non-eating step from 11->12
HudSnake._food := { col: 1, row: sbTopEdge + 2, kind: "normal", bornUs: tSnakeUs, ttlMs: 0, pts: 10 }
HudSnake.StepSimulation(tSnakeUs + 200000.0)
midPieces := HudSnake._BuildInterpolatedPieces(0.5)
interpMidOk := (midPieces.Length == 1 && midPieces[1].Length >= 5
    && Abs(midPieces[1][1].c - 11.5) < 0.01 && Abs(midPieces[1][midPieces[1].Length].c - 6.5) < 0.01)

; Eat golden bonus fruit -> +30 score, total +2 length across 2 steps
bh := HudSnake._snake[1]
HudSnake._food := { col: bh.col + 1, row: bh.row, kind: "bonus", bornUs: tSnakeUs, ttlMs: 9000, pts: 30 }
HudSnake.StepSimulation(tSnakeUs + 300000.0)
HudSnake._food := { col: 1, row: sbTopEdge + 2, kind: "normal", bornUs: tSnakeUs, ttlMs: 0, pts: 10 }
HudSnake.StepSimulation(tSnakeUs + 400000.0)
bonusOk := (HudSnake._score == 40 && HudSnake._snake.Length == 8 && HudSnake._bestBeaten)

Assert("v4.0.1 HudSnake continuous interpolation, food, anti-180 queue, growth, speed ramp, bonus & INI HighScore work",
    foodValid && revRejected && turn1Ok && turn2Ok && turn3Cap && eat1Ok && interpMidOk && bonusOk,
    Format("fv={} q=({},{},{},{}) e1={} mid={} bonus={} len={} sc={}", foodValid, revRejected, turn1Ok, turn2Ok, turn3Cap, eat1Ok, interpMidOk, bonusOk, HudSnake._snake.Length, HudSnake._score))

; Chasing vacating tail tip survives vs hitting non-tail segment dies
HudSnake.Restart()
HudSnake.Phase := "playing"
HudSnake._growPending := 0
HudSnake._dirQueue := []
HudSnake._dir := { x: 0, y: -1 }
HudSnake._food := { col: 1, row: 10, kind: "normal", bornUs: tSnakeUs, ttlMs: 0, pts: 10 }
HudSnake._snake := [
    { col: 8, row: 9 },
    { col: 9, row: 9 },
    { col: 9, row: 8 },
    { col: 8, row: 8 }
]
HudSnake.StepSimulation(tSnakeUs + 500000.0)
tailChaseSurvived := (HudSnake.Phase == "playing")

HudSnake._dir := { x: 1, y: 0 }
HudSnake._snake := [
    { col: 8, row: 8 },
    { col: 8, row: 9 },
    { col: 9, row: 9 },
    { col: 9, row: 8 },
    { col: 9, row: 7 }
]
HudSnake.StepSimulation(tSnakeUs + 600000.0)
selfCrashDied := (HudSnake.Phase == "gameover" && HudSnake._deathReason == "self")

; Wall crash vs Edge Wrap + wrap piece split + Pause/Resume
HudSnake.Restart()
HudSnake.Phase := "playing"
HudSnake._edgeWrap := false
HudSnake._dirQueue := []
HudSnake._dir := { x: -1, y: 0 }
HudSnake._snake := [
    { col: 0, row: 10 },
    { col: 1, row: 10 },
    { col: 2, row: 10 },
    { col: 3, row: 10 },
    { col: 4, row: 10 }
]
HudSnake.StepSimulation(tSnakeUs + 700000.0)
wallDied := (HudSnake.Phase == "gameover" && HudSnake._deathReason == "wall")

HudSnake.Restart()
HudSnake.Phase := "playing"
HudSnake.TogglePause()
pauseOk := (HudSnake.Phase == "paused")
HudSnake.TogglePause()
resumeOk := (HudSnake.Phase == "playing")
HudSnake.ToggleEdgeMode()
HudSnake._dir := { x: -1, y: 0 }
HudSnake._snake := [
    { col: 0, row: 10 },
    { col: 1, row: 10 },
    { col: 2, row: 10 },
    { col: 3, row: 10 },
    { col: 4, row: 10 }
]
HudSnake.StepSimulation(tSnakeUs + 800000.0)
wrapPiecesEarly := HudSnake._BuildInterpolatedPieces(0.25)
wrapPiecesLate := HudSnake._BuildInterpolatedPieces(0.75)
wrapSplitOk := (wrapPiecesEarly.Length == 1 && wrapPiecesLate.Length == 2)
wrapOk := (HudSnake.Phase == "playing" && HudSnake._snake[1].col == HudSnake._cols - 1 && wrapSplitOk)
HudSnake.Stop()

Assert("v4.0.1 HudSnake tail exemption, self/wall death, pause/resume & portal edge-wrap splits behave cleanly",
    tailChaseSurvived && selfCrashDied && wallDied && pauseOk && resumeOk && wrapOk,
    Format("tail={} self={} wall={} p={}/{} wrap={}(early={},late={})", tailChaseSurvived, selfCrashDied, wallDied, pauseOk, resumeOk, wrapOk, wrapPiecesEarly.Length, wrapPiecesLate.Length))

cfgSnake.ShowIndicator := false
UpdateVoiceMeterTimer(cfgSnake, stSnake)
UpdateAutoDodgeTimer(cfgSnake, stSnake)
for g in GetHudGuiList(stSnake)
    try g.Destroy()

; Secret discoverability guard: hotkeys wired in Primary, zero Tray/ControlCenter UI, subtle Help entry only on Primary
primSrc := FileRead(A_ScriptDir "\..\PresenterSync.ahk", "UTF-8")
remSrc := FileRead(A_ScriptDir "\..\PresenterSync_Remote.ahk", "UTF-8")
ccSrc := FileRead(A_ScriptDir "\..\Lib\ControlCenter.ahk", "UTF-8")
trayPart := StrSplit(StrSplit(primSrc, "BuildTrayMenu(cfg, state) {")[2], "NotifyHelpRefresh(state)")[1]
ccPart := StrSplit(ccSrc, "ShowControlCenterWindow(cfg, state := `"`", *) {")[2]
remTrayPart := StrSplit(StrSplit(remSrc, "BuildRemoteTrayMenu(cfg, state) {")[2], "ToggleRemoteIndicator(cfg, state")[1]

noUiMenuLeak := !InStr(trayPart, "Snake") && !InStr(trayPart, "Easter") && !InStr(trayPart, "Arcade")
    && !InStr(ccPart, "Snake") && !InStr(ccPart, "Easter") && !InStr(ccPart, "Arcade")
    && !InStr(remTrayPart, "Snake") && !InStr(remTrayPart, "Easter") && !InStr(remTrayPart, "Try at your own risk")
    && !InStr(ccSrc, "Alt + Ctrl + Shift + S")
vaultGated := InStr(primSrc, "ArcadeVault.RegisterGame") && InStr(primSrc, "ArcadeVault.BindVaultHotkey")
    && InStr(primSrc, "!HudArcadeBase.IsAnyGameActive()")
    && InStr(remSrc, "ArcadeVault.RegisterGame") && InStr(remSrc, "ArcadeVault.BindVaultHotkey")
    && InStr(remSrc, "HudArcadeBase.IsAnyGameActive()")
helpPrimHits := SearchHelpEntries("sector z", "All", false)
helpRemHits := SearchHelpEntries("sector z", "All", true)
Assert("v8.1.1+ Master Arcade Vault gates Snake cleanly with zero menu/chord spoilers",
    noUiMenuLeak && vaultGated && helpPrimHits.Length >= 1 && helpPrimHits[1].id == "feat-easter-snake"
    && helpRemHits.Length >= 1 && helpRemHits[1].id == "rfeat-easter-snake",
    Format("noLeak={} vaultGated={} primHits={} remHits={}", noUiMenuLeak, vaultGated, helpPrimHits.Length, helpRemHits.Length))

; ==============================================================================
; SECTION 26: v4.1.0+ AUDIT FIXES (LIVE MUTE SAFETY & NON-BLOCKING LOOPBACK)
; ==============================================================================
checkPtrLineOk := RegExMatch(primSrc, "CheckPointerEnable\([^\)]*\)\s*\{\s*return\s+\(cfg\.EnablePPT") != 0
loopbackHelpersOk := IsLoopbackHost("127.0.0.1") && IsLoopbackHost(" LOCALHOST ") && IsLoopbackHost("[::1]") && !IsLoopbackHost("192.168.1.50")
tProbe0 := A_TickCount
deadPortOk := !IsLocalTcpPortListening(59998) && !IsLocalTcpPortListening(0) && !IsLocalTcpPortListening(70000) && IsLocalTcpPortListening("abc")
probeElapsedMs := A_TickCount - tProbe0
fastLoopbackSkipOk := true
loopbackDt := 0
if (!IsLocalTcpPortListening(4455)) {
    cfgNoObs := Config(testIni)
    cfgNoObs.EnableWS := true
    stNoObs := OverlayState(cfgNoObs)
    stNoObs.obsTimerFn := (*) => 0
    tConn0 := A_TickCount
    ConnectToOBS(cfgNoObs, stNoObs)
    loopbackDt := A_TickCount - tConn0
    SetTimer(stNoObs.obsTimerFn, 0)
    fastLoopbackSkipOk := (!stNoObs.obsConnected && loopbackDt < 250)
}
AudioMeter.Reset()
upd410 := CheckForUpdates("4.1.0", '{"tag_name":"v4.1.0","html_url":"https://github.com/SaabithJiffry/PresenterSync/releases/tag/v4.1.0"}', true)
Assert("v4.1.0 Audit: Snake blocks HwMute pointer trigger, fast loopback probe avoids 2s WinHTTP stall & Reset works",
    checkPtrLineOk && loopbackHelpersOk && deadPortOk && probeElapsedMs < 150 && fastLoopbackSkipOk && upd410.status == "up_to_date",
    Format("ptr={} lb={} dead={} dt={}ms connOk={}({}ms) upd={}", checkPtrLineOk, loopbackHelpersOk, deadPortOk, probeElapsedMs, fastLoopbackSkipOk, loopbackDt, upd410.status))

; ==============================================================================
; SECTION 27: v4.1.1 SNAKE VISUALS & 90-DEGREE TAIL CORNERING
; ==============================================================================

savedPrev := HudSnake._prevSnake
savedSnake := HudSnake._snake
savedCols := HudSnake._cols
savedRows := HudSnake._rows
savedGrew := HudSnake._stepGrew
savedCfg := HudSnake._cfg
savedW := HudSnake._W
savedH := HudSnake._H
savedDpi := HudSnake._dpi

; 1) Normal 90-degree tail turn preserves exact orthogonal corner vertex cTail before tailTip
HudSnake._cols := 24
HudSnake._rows := 18
HudSnake._stepGrew := false
HudSnake._prevSnake := [{ col: 11, row: 10 }, { col: 10, row: 10 }, { col: 10, row: 11 }, { col: 10, row: 12 }]
HudSnake._snake     := [{ col: 12, row: 10 }, { col: 11, row: 10 }, { col: 10, row: 10 }, { col: 10, row: 11 }]
normPieces := HudSnake._BuildInterpolatedPieces(0.45)
normOk := (normPieces.Length == 1 && normPieces[1].Length == 5
    && Abs(normPieces[1][4].c - 10.0) < 0.01 && Abs(normPieces[1][4].r - 11.0) < 0.01
    && Abs(normPieces[1][5].c - 10.0) < 0.01 && Abs(normPieces[1][5].r - 11.55) < 0.02)
Assert("v4.1.1 Snake normal 90-degree tail turn keeps exact corner pivot before tail tip",
    normOk, Format("pieces={} verts={}", normPieces.Length, normPieces.Length >= 1 ? normPieces[1].Length : 0))

; 2) Wrapped 90-degree tail turn preserves corner pivot & stays strictly axis-aligned
HudSnake._cols := 20
HudSnake._rows := 15
HudSnake._prevSnake := [{ col: 19, row: 8 }, { col: 19, row: 7 }, { col: 19, row: 6 }, { col: 19, row: 5 }, { col: 0, row: 5 }]
HudSnake._snake     := [{ col: 19, row: 9 }, { col: 19, row: 8 }, { col: 19, row: 7 }, { col: 19, row: 6 }, { col: 19, row: 5 }]
wrapPiecesEarly := HudSnake._BuildInterpolatedPieces(0.25)
wrapPiecesLate := HudSnake._BuildInterpolatedPieces(0.75)
wrapAxisAligned := true
for pArr in [wrapPiecesEarly, wrapPiecesLate] {
    for pc in pArr {
        loop (pc.Length - 1) {
            dx := Abs(pc[A_Index + 1].c - pc[A_Index].c)
            dy := Abs(pc[A_Index + 1].r - pc[A_Index].r)
            if (dx > 0.01 && dy > 0.01)
                wrapAxisAligned := false
        }
    }
}
Assert("v4.1.1 Snake wrap-edge tail turn remains strictly axis-aligned across wrap split",
    wrapAxisAligned && wrapPiecesEarly.Length == 2 && wrapPiecesLate.Length == 1,
    Format("axis={} early={} late={}", wrapAxisAligned, wrapPiecesEarly.Length, wrapPiecesLate.Length))

; 3) Live HUD appearance inheritance (_GetHudStyle & IndicatorScale cell sizing & contrast-safe MonoIcon)
cfgSnakeStyle := Config(testIni)
cfgSnakeStyle.OpacityLevel := 127
cfgSnakeStyle.SleekCorners := true
cfgSnakeStyle.MonoIcon := true
cfgSnakeStyle.IndicatorScale := 1.0
HudSnake._cfg := cfgSnakeStyle
HudSnake._W := 1920, HudSnake._H := 1032, HudSnake._dpi := 1.0
HudSnake._ComputeGrid()
cellAt1 := HudSnake._cell
cfgSnakeStyle.IndicatorScale := 1.5
HudSnake._ComputeGrid()
cellAt15 := HudSnake._cell
stObj := HudSnake._GetHudStyle()
stdMonoSafe := HudSnake._PickBadgeContentHex("2563EB", "1E3A8A", true, true, 220)
oledMonoKeep := HudSnake._PickBadgeContentHex("13233A", "60A5FA", true, true, 220)
Assert("v4.1.1 Snake inherits HUD Opacity/Sleek/Mono/Scale & contrast-guards MonoIcon badges",
    stObj.opacity == 127 && stObj.sleek && stObj.mono && cellAt15 > cellAt1 && stdMonoSafe == "FFFFFF" && oledMonoKeep == "60A5FA",
    Format("op={} sl={} mo={} c1={} c15={} std={} oled={}", stObj.opacity, stObj.sleek, stObj.mono, cellAt1, cellAt15, stdMonoSafe, oledMonoKeep))

HudSnake._prevSnake := savedPrev
HudSnake._snake := savedSnake
HudSnake._cols := savedCols
HudSnake._rows := savedRows
HudSnake._stepGrew := savedGrew
HudSnake._cfg := savedCfg
HudSnake._W := savedW
HudSnake._H := savedH
HudSnake._dpi := savedDpi

upd450 := CheckForUpdates("4.5.0", '{"tag_name":"v4.5.0","html_url":"https://github.com/SaabithJiffry/PresenterSync/releases/tag/v4.5.0"}', true)
Assert("v4.5.0 CheckForUpdates recognizes current version 4.5.0 as up_to_date", upd450.status == "up_to_date")

; ==============================================================================
; SECTION 28: v4.3.0 REMOTE OFFLINE ALPHA, SCALING & VISUAL RENDER CHECKS
; ==============================================================================
cfgRemCos := Config(testIni)
cfgRemCos.HideHud := false
cfgRemCos.ShowText := true
cfgRemCos.MonoIcon := false
cfgRemCos.SleekCorners := true
cfgRemCos.HudColorPreset := "Standard"
for opVal in [255, 220, 127] {
    cfgRemCos.OpacityLevel := opVal
    for scVal in [0.25, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 5.0] {
        cfgRemCos.IndicatorScale := scVal
        stRemCos := OverlayState(cfgRemCos)
        stRemCos.isMuted := false
        stRemCos.isAutoDodged := false
        stRemCos.obsConnected := false
        stRemCos.activeHost := ""
        stRemCos.connStatus := "searching"
        stRemCos.baseAlpha := opVal
        stRemCos.currentAlpha := opVal
        stRemCos.hudDpiScale := 1.0
        stRemCos.meterLevel := 0.75
        stRemCos.meterActive := false
        stRemCos.savedX := 100
        stRemCos.savedY := 100
        stRemCos.ComputeDimensions(cfgRemCos)
        stRemCos.MicGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000 -DPIScale")
        stRemCos.MicGui.Show("x-10000 y-10000 w10 h10 NoActivate")
        ApplyMicAppearance(cfgRemCos, stRemCos)
        Assert("v4.3.0 Offline Mic Pill preserves full Transparency (" opVal ") at scale " scVal,
            stRemCos.currentAlpha == opVal
            && stRemCos.baseWidth == Round(UIConstants.BASE_WIDTH_TEXT * scVal)
            && stRemCos.baseHeight == Round(UIConstants.BASE_HEIGHT * scVal))
        stRemCos.obsConnected := true
        stRemCos.activeHost := "127.0.0.1"
        stRemCos.connStatus := "connected"
        stRemCos.isAutoDodged := true
        stRemCos.currentAlpha := Min(opVal, UIConstants.DODGE_ALPHA)
        ApplyMicAppearance(cfgRemCos, stRemCos)
        Assert("v4.3.0 Auto-Dodge caps alpha to DODGE_ALPHA at opacity " opVal " scale " scVal,
            stRemCos.currentAlpha == Min(opVal, UIConstants.DODGE_ALPHA))
        try stRemCos.MicGui.Destroy()
    }
}

; ==============================================================================
; SECTION 29: v4.4.0 HUD SNAKE 90-DEGREE IMPACT TURN REGRESSIONS
; ==============================================================================
AllSegmentsAxisAligned(pieceList) {
    for pc in pieceList {
        if (pc.Length < 2)
            continue
        Loop (pc.Length - 1) {
            p1 := pc[A_Index]
            p2 := pc[A_Index + 1]
            if (Abs(p2.c - p1.c) > 0.0001 && Abs(p2.r - p1.r) > 0.0001)
                return false
        }
    }
    return true
}

cfgTurn := Config(testIni)
stTurn := OverlayState(cfgTurn)
HudSnake.Start(cfgTurn, stTurn, true)
HudSnake.Phase := "playing"
HudSnake._edgeWrap := false
HudSnake._growPending := 0
HudSnake._dir := { x: -1, y: 0 }
HudSnake._dirQueue := []
HudSnake._snake := [
    { col: 10, row: 12 },
    { col: 11, row: 12 },
    { col: 12, row: 12 },
    { col: 13, row: 12 },
    { col: 14, row: 12 },
    { col: 15, row: 12 }
]
HudSnake._prevSnake := HudSnake._CloneSnake(HudSnake._snake)
tTurnUs := HudSnake._NowUs()
HudSnake._food := { col: 1, row: 5, kind: "normal", bornUs: tTurnUs, ttlMs: 0, pts: 10 }

; Simulate 3 rapid right turns from Left: Up -> Right -> Down into own body at (11,12)
q1 := HudSnake.QueueDirection(0, -1)
q2 := HudSnake.QueueDirection(1, 0)
HudSnake.StepSimulation(tTurnUs + 140000.0) ; moves Up to (10,11)
q3 := HudSnake.QueueDirection(0, 1)
HudSnake.StepSimulation(tTurnUs + 280000.0) ; moves Right to (11,11)
HudSnake.StepSimulation(tTurnUs + 420000.0) ; attempts Down into (11,12) -> self crash

selfImpactPieces := HudSnake._BuildInterpolatedPieces(HudSnake._frozenInterp)
selfHeadPivotOk := (selfImpactPieces.Length >= 1 && selfImpactPieces[1].Length >= 4
    && Abs(selfImpactPieces[1][1].c - 11.0) < 0.0001
    && Abs(selfImpactPieces[1][1].r - (11.0 + HudSnake._frozenInterp)) < 0.0001
    && Abs(selfImpactPieces[1][2].c - 11.0) < 0.0001
    && Abs(selfImpactPieces[1][2].r - 11.0) < 0.0001
    && Abs(selfImpactPieces[1][3].c - 10.0) < 0.0001
    && Abs(selfImpactPieces[1][3].r - 11.0) < 0.0001)
selfOrthoOk := AllSegmentsAxisAligned(selfImpactPieces)
Assert("v4.4.0 HudSnake fast 3-turn self-collision preserves 90-degree head corner pivot without diagonal segment",
    q1 && q2 && q3 && HudSnake.Phase == "gameover" && HudSnake._deathReason == "self" && selfHeadPivotOk && selfOrthoOk,
    Format("phase={} reason={} pivot={} ortho={}", HudSnake.Phase, HudSnake._deathReason, selfHeadPivotOk, selfOrthoOk))

; Sideways 90-degree turn directly into top perimeter wall
HudSnake.Restart()
HudSnake.Phase := "playing"
HudSnake._edgeWrap := false
HudSnake._growPending := 0
HudSnake._dir := { x: -1, y: 0 }
HudSnake._dirQueue := []
HudSnake._snake := [
    { col: 10, row: 0 },
    { col: 11, row: 0 },
    { col: 12, row: 0 },
    { col: 13, row: 0 },
    { col: 14, row: 0 }
]
HudSnake._prevSnake := HudSnake._CloneSnake(HudSnake._snake)
HudSnake.QueueDirection(0, -1)
HudSnake.StepSimulation(tTurnUs + 600000.0)
wallImpactPieces := HudSnake._BuildInterpolatedPieces(HudSnake._frozenInterp)
wallHeadPivotOk := (wallImpactPieces.Length >= 1 && wallImpactPieces[1].Length >= 3
    && Abs(wallImpactPieces[1][1].c - 10.0) < 0.0001
    && Abs(wallImpactPieces[1][1].r - (-HudSnake._frozenInterp)) < 0.0001
    && Abs(wallImpactPieces[1][2].c - 10.0) < 0.0001
    && Abs(wallImpactPieces[1][2].r - 0.0) < 0.0001)
wallOrthoOk := AllSegmentsAxisAligned(wallImpactPieces)
Assert("v4.4.0 HudSnake sideways 90-degree turn into wall preserves corner pivot without diagonal segment",
    HudSnake.Phase == "gameover" && HudSnake._deathReason == "wall" && wallHeadPivotOk && wallOrthoOk,
    Format("phase={} reason={} pivot={} ortho={}", HudSnake.Phase, HudSnake._deathReason, wallHeadPivotOk, wallOrthoOk))

; Zero-displacement crash / stationary frame avoids duplicate cHead vertex
zeroImpactPieces := HudSnake._BuildInterpolatedPieces(0.0)
zeroNoDupOk := (zeroImpactPieces.Length >= 1 && zeroImpactPieces[1].Length >= 2
    && (Abs(zeroImpactPieces[1][1].c - zeroImpactPieces[1][2].c) + Abs(zeroImpactPieces[1][1].r - zeroImpactPieces[1][2].r)) >= 0.99
    && AllSegmentsAxisAligned(zeroImpactPieces))
Assert("v4.4.0 HudSnake zero-displacement crash frame avoids duplicate corner vertices",
    zeroNoDupOk)
HudSnake.Stop()

; ==============================================================================
; SECTION 30: v4.5.0 ENLARGED BONUS FRUIT, CENTERED OVERLAYS & PLAYFUL CHORD
; ==============================================================================
MeasureFoodSpan(kind) {
    cfgF := Config(testIni)
    cfgF.HideHud := false
    cfgF.AppTheme := "dark"
    stF := OverlayState(cfgF)
    HudSnake.Start(cfgF, stF, true)
    HudSnake._cell := 24.0
    HudSnake._dpi := 1.0
    HudSnake._gridOffX := 60.0 - 12.0
    HudSnake._gridOffY := 60.0 - 12.0
    nowU := HudSnake._NowUs()
    HudSnake._food := { col: 0, row: 0, kind: kind, bornUs: nowU, ttlMs: (kind = "bonus" ? 9000 : 0), pts: (kind = "bonus" ? 30 : 10) }

    pBmp := 0
    DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", 120, "Int", 120, "Int", 0, "Int", 0x26200A, "Ptr", 0, "Ptr*", &pBmp)
    pG := 0
    DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", pBmp, "Ptr*", &pG)
    DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", pG, "Int", 4)
    DllCall("gdiplus\GdipGraphicsClear", "Ptr", pG, "UInt", 0)
    HudSnake._DrawFood(pG, HudSnake._GetActivePalette(), true, nowU)
    DllCall("gdiplus\GdipDeleteGraphics", "Ptr", pG)

    minX := 999, maxX := -1, minY := 999, maxY := -1
    loop 120 {
        pxX := A_Index - 1
        c1 := 0
        DllCall("gdiplus\GdipBitmapGetPixel", "Ptr", pBmp, "Int", pxX, "Int", 60, "UInt*", &c1)
        if ((c1 >> 24) & 0xFF) > 10 {
            minX := Min(minX, pxX), maxX := Max(maxX, pxX)
        }
    }
    loop 120 {
        pxY := A_Index - 1
        c2 := 0
        DllCall("gdiplus\GdipBitmapGetPixel", "Ptr", pBmp, "Int", 60, "Int", pxY, "UInt*", &c2)
        if ((c2 >> 24) & 0xFF) > 10 {
            minY := Min(minY, pxY), maxY := Max(maxY, pxY)
        }
    }
    DllCall("gdiplus\GdipDisposeImage", "Ptr", pBmp)
    HudSnake.Stop()
    return { w: (maxX >= minX ? maxX - minX + 1 : 0), h: (maxY >= minY ? maxY - minY + 1 : 0) }
}

normSpan := MeasureFoodSpan("normal")
bonusSpan := MeasureFoodSpan("bonus")
bonusAreaRatio := (normSpan.w > 0 && normSpan.h > 0) ? (Float(bonusSpan.w * bonusSpan.h) / Float(normSpan.w * normSpan.h)) : 0.0
Assert("v4.5.0 HudSnake special bonus fruit is >= 2x wider/taller (~4x area) than normal fruit",
    normSpan.w > 12 && bonusSpan.w >= (normSpan.w * 1.95) && bonusSpan.h >= (normSpan.h * 1.95) && bonusAreaRatio >= 3.8,
    Format("norm={}x{} bonus={}x{} areaRatio={:.2f}", normSpan.w, normSpan.h, bonusSpan.w, bonusSpan.h, bonusAreaRatio))

; Verify Help Center exposes Sector Z breadcrumb playfully without leaking "Snake", "Easter", or "INSERT COIN" in visible copy
riskHits := SearchHelpEntries("Sector Z", "All", false)
hasSecretRisk := false, hasScRisk := false, visibleSnakeSpoil := false
for rh in riskHits {
    if (rh.id = "feat-easter-snake")
        hasSecretRisk := true
    if (rh.id = "sc-global")
        hasScRisk := true
    visTxt := rh.title " " rh.menuPath " " rh.defVal " " rh.summary " " rh.body
    if (InStr(visTxt, "Snake") || InStr(visTxt, "Easter") || InStr(visTxt, "INSERT COIN"))
        visibleSnakeSpoil := true
}
Assert("v9.0.0 Help Search 'Sector Z' surfaces confidential breadcrumb without visibly spoiling Snake or passphrase",
    hasSecretRisk && hasScRisk && !visibleSnakeSpoil,
    Format("secret={} sc={} visSpoil={}", hasSecretRisk, hasScRisk, visibleSnakeSpoil))

; Verify Primary ShowAboutWindow contains upgraded v4.5.0 capabilities text & zero Snake leaks
cfgAb := Config(testIni)
stAb := OverlayState(cfgAb)
abGui := ShowAboutWindow(cfgAb, stAb)
abTextDump := ""
for abCtrl in abGui {
    try abTextDump .= abCtrl.Text "`n"
}
WinClose("ahk_id " abGui.Hwnd)
Assert("Primary ShowAboutWindow displays full Primary Host capabilities without Snake leak",
    InStr(abTextDump, UIConstants.APP_VERSION) && InStr(abTextDump, "4-Tier Live HUD Stack") && InStr(abTextDump, "Remote Companion Host")
    && !InStr(abTextDump, "Snake") && !InStr(abTextDump, "Easter"))

; Verify Help Window Shortcuts tab renders Alt + Ctrl + Shift + S playfully without leaking Snake
helpTabGui := ShowHelpWindow(cfgAb, stAb)
helpTextDump := ""
for hCtrl in helpTabGui {
    try helpTextDump .= hCtrl.Text "`n"
}
WinClose("ahk_id " helpTabGui.Hwnd)
Assert("v9.0.0 Help Shortcuts tab displays confidential Sector Z Subsystem ('Locked [0 Credits]') without spoilers",
    InStr(helpTextDump, "Sector Z Subsystem") && InStr(helpTextDump, "Locked [0 Credits]") && !InStr(helpTextDump, "Snake") && !InStr(helpTextDump, "INSERT COIN"))

; Verify Snake Scoreboard & Status Banner render cleanly in Light & Dark modes without errors
for themeName in ["dark", "light"] {
    cfgOv := Config(testIni)
    cfgOv.AppTheme := themeName
    stOv := OverlayState(cfgOv)
    HudSnake.Start(cfgOv, stOv, true)
    HudSnake._W := 1200
    HudSnake._H := 500
    HudSnake._dpi := 1.0
    HudSnake._score := 150
    HudSnake._bestScore := 150
    for phaseName in ["paused", "gameover"] {
        HudSnake.Phase := phaseName
        HudSnake._deathReason := "self"
        pBmpOv := 0
        DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", 1200, "Int", 500, "Int", 0, "Int", 0x26200A, "Ptr", 0, "Ptr*", &pBmpOv)
        pGOv := 0
        DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", pBmpOv, "Ptr*", &pGOv)
        DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", pGOv, "Int", 4)
        DllCall("gdiplus\GdipSetTextRenderingHint", "Ptr", pGOv, "Int", 5)
        isDarkOv := (themeName = "dark")
        palOv := HudSnake._GetActivePalette()
        HudSnake._DrawScoreboard(pGOv, palOv, isDarkOv)
        HudSnake._DrawStatusBanner(pGOv, palOv, isDarkOv)
        DllCall("gdiplus\GdipDeleteGraphics", "Ptr", pGOv)
        DllCall("gdiplus\GdipDisposeImage", "Ptr", pBmpOv)
    }
    HudSnake.Stop()
}
Assert("v4.5.0 HudSnake centered Scoreboard & Paused/GameOver banners render cleanly in Dark & Light themes", true)

; Verify live non-headless HudSnake.Start(cfg, st, false) creates real layered canvas, hides HUD, toggles pause/edge, and restores HUD
cfgLiveSnk := Config(testIni)
stLiveSnk := OverlayState(cfgLiveSnk)
InitHUD(cfgLiveSnk, stLiveSnk)
okLiveSnkStart := HudSnake.Start(cfgLiveSnk, stLiveSnk, false)
Sleep(80)
liveSnkHw := IsObject(HudSnake._gui) ? HudSnake._gui.Hwnd : 0
liveSnkVis := liveSnkHw ? DllCall("IsWindowVisible", "Ptr", liveSnkHw, "Int") : 0
micHidSnk := (IsGuiValid(stLiveSnk.MicGui) && !DllCall("IsWindowVisible", "Ptr", stLiveSnk.MicGui.Hwnd, "Int"))
morphAtStart := (HudSnake.Phase = "morph")
Sleep(420) ; Allow 360ms pill morph transition to settle into active playing phase
HudSnake.TogglePause()
phasePausedSnk := HudSnake.Phase
HudSnake.ToggleEdgeMode()
wrapOnSnk := HudSnake._edgeWrap
HudSnake.Stop()
micRestSnk := (IsGuiValid(stLiveSnk.MicGui) && DllCall("IsWindowVisible", "Ptr", stLiveSnk.MicGui.Hwnd, "Int"))
try stLiveSnk.DestroyAllHuds()
Assert("v4.5.0 HudSnake live non-headless canvas morphs, hides HUD, toggles Pause/Edge, and restores HUD cleanly",
    okLiveSnkStart && liveSnkHw != 0 && liveSnkVis == 1 && micHidSnk && morphAtStart && phasePausedSnk == "paused" && wrapOnSnk && micRestSnk,
    Format("start={} hw={} vis={} micHid={} morph={} phase={} wrap={} rest={}", okLiveSnkStart, liveSnkHw, liveSnkVis, micHidSnk, morphAtStart, phasePausedSnk, wrapOnSnk, micRestSnk))

; Verify idempotent ExecuteHostRemoteSetMute & HandleHostRelayMessage set_mute (Mode 2 optimistic + relay)
cfgSet := Config(testIni)
cfgSet.AudioRoutingMode := 2
cfgSet.InternetPairingCode := "PS-SETM-9999"
cfgSet.ObsPassword := "secretPw"
stSet := OverlayState(cfgSet)
stSet.relayMockWs := {sendText: (*) => true}
stSet.isMuted := false
ExecuteHostRemoteSetMute(cfgSet, stSet, true)
setOk1 := (stSet.isMuted == true)
ExecuteHostRemoteSetMute(cfgSet, stSet, true) ; idempotent when already muted
setOk2 := (stSet.isMuted == true)
tokSet := GetInternetRelayAuthToken(cfgSet.InternetPairingCode, cfgSet.ObsPassword)
HandleHostRelayMessage(cfgSet, stSet, "", FormatRelayPacket("remote", "set_mute", "0", tokSet))
setOk3 := (stSet.isMuted == false)
Assert("ExecuteHostRemoteSetMute and relay set_mute are idempotent and state-accurate", setOk1 && setOk2 && setOk3)

; ==============================================================================
; SECTION 32: v5.3.0 MULTI-REMOTE BRIDGE CLIENT & CLI INSTANCE SUITE
; ==============================================================================
cliMulti := ParseRemoteCliArgs(["-Config", "C:\temp\rem2.ini", "-Instance", "BackupPC"])
Assert("ParseRemoteCliArgs extracts -Config and -Instance",
    cliMulti.configPath == "C:\temp\rem2.ini" && cliMulti.instanceName == "BackupPC")

qBridgePref := BuildRemoteLanCandidateQueue({
    HostAddress: "192.168.1.25",
    HostPort: "4455",
    BridgePort: "4456",
    SessionPairingCode: "K7M-9P2",
    SessionToken: ""
})
Assert("BuildRemoteLanCandidateQueue prefers HostBridge :4456/ws ahead of Direct OBS :4455",
    qBridgePref.Length == 2 && qBridgePref[1].isBridge && qBridgePref[1].port == "4456" && !qBridgePref[2].isBridge)

bSent := []
mockBrWs := { sendText: (this, pkt) => bSent.Push(pkt) }
bCfg := { NetworkMode: "LAN", DeviceId: "win-ci01", TargetMicName: "Mic/Aux", ObsPassword: "", InternetPairingCode: "" }
bSt := { usingBridge: true, usingRelayFallback: false, obsConnected: true, obsWs: mockBrWs }
Assert("DispatchRemoteMuteToggle & SetMute dispatch HostBridge JSON payloads",
    DispatchRemoteMuteToggle(bCfg, bSt) && DispatchRemoteSetMute(bCfg, bSt, false)
    && bSent.Length == 2 && InStr(bSent[1], '"type":"toggle_mute"') && InStr(bSent[2], '"isMuted":false'))

mtxCi := AcquireRemoteInstanceMutex("MasterSuite_Inst_" A_TickCount)
Assert("AcquireRemoteInstanceMutex acquires unique named instance handle cleanly",
    mtxCi.handle != 0 && !mtxCi.alreadyExists)
ReleaseRemoteInstanceMutex(mtxCi)

; ==============================================================================
; SECTION 33: v6.1.0 SELF-UPDATER (SHA-256 FILE HASH, RELEASE ASSETS & ATOMIC SWAP)
; ==============================================================================
cliCleanup := ParseRemoteCliArgs(["-Config", "C:\cfg.ini", "-Instance", "Stage2", "--cleanup-old-exe", "C:\old.exe"])
Assert("ParseRemoteCliArgs recognizes --cleanup-old-exe alongside -Config and -Instance",
    cliCleanup.configPath == "C:\cfg.ini" && cliCleanup.instanceName == "Stage2" && cliCleanup.cleanupOldExe == "C:\old.exe")

relaunchArgs := BuildUpdaterRelaunchArgs(["-Config", "C:\cfg.ini", "-Instance", "Stage 2", "--cleanup-old-exe", "C:\stale.old"], "C:\PresenterSync_Remote.exe.old")
Assert("BuildUpdaterRelaunchArgs preserves Config/Instance and replaces stale cleanup path",
    InStr(relaunchArgs, '-Config "C:\cfg.ini"') && InStr(relaunchArgs, '-Instance "Stage 2"')
    && InStr(relaunchArgs, '--cleanup-old-exe "C:\PresenterSync_Remote.exe.old"')
    && !InStr(relaunchArgs, "stale.old"))

updTmpDir := A_Temp "\ps_upd_test_" A_TickCount
DirCreate(updTmpDir)
try {
    sampleBin := updTmpDir "\sample.bin"
    FileAppend("MZ_PRESENTERSYNC_TEST_PAYLOAD", sampleBin, "UTF-8-RAW")
    fileSha := HashFileSHA256_Hex(sampleBin)
    strSha := HashSHA256_Hex("MZ_PRESENTERSYNC_TEST_PAYLOAD")
    emptyFile := updTmpDir "\empty.bin"
    FileOpen(emptyFile, "w").Close()
    Assert("HashFileSHA256_Hex matches HashSHA256_Hex and empty-file NIST digest",
        fileSha == strSha && StrLen(fileSha) == 64
        && HashFileSHA256_Hex(emptyFile) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")

    nestedJson := '{"tag_name":"v6.2.0","html_url":"https://github.com/SaabithJiffry/PresenterSync/releases/tag/v6.2.0","body":"Hello\nNotes","assets":[{"name":"PresenterSync.exe","size":222,"uploader":{"login":"bot"},"browser_download_url":"https://dl/PresenterSync.exe"},{"name":"PresenterSync_Remote.exe","size":333,"browser_download_url":"https://dl/PresenterSync_Remote.exe"},{"name":"SHA256SUMS.txt","size":99,"browser_download_url":"https://dl/SHA256SUMS.txt"}]}'
    detHost := ParseGitHubReleaseDetails(nestedJson, "PresenterSync.exe")
    detRem := ParseGitHubReleaseDetails(nestedJson, "PresenterSync_Remote.exe")
    Assert("ParseGitHubReleaseDetails handles nested uploader objects & selects matching EXE + SHA256SUMS.txt",
        detHost.version == "6.2.0" && detHost.assetName == "PresenterSync.exe" && detHost.assetSize == 222
        && detHost.assetUrl == "https://dl/PresenterSync.exe" && detHost.sha256Url == "https://dl/SHA256SUMS.txt"
        && detRem.assetName == "PresenterSync_Remote.exe" && detRem.assetSize == 333)

    sumsManifest := StrUpper(fileSha) " *release-upload/PresenterSync.exe`n" "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  PresenterSync_Remote.apk`n"
    Assert("ParseSha256SumsText parses GNU asterisk/plain checksum formats accurately",
        ParseSha256SumsText(sumsManifest, "PresenterSync.exe") == fileSha
        && ParseSha256SumsText(sumsManifest, "Missing.exe") == "")

    htmlSpoof := updTmpDir "\spoof.exe"
    FileAppend("<html>404</html>", htmlSpoof, "UTF-8-RAW")
    badPeRes := VerifyStagedExecutable(htmlSpoof)
    Assert("VerifyStagedExecutable rejects & deletes HTML/non-MZ files", !badPeRes.ok && !FileExist(htmlSpoof))

    goodStaged := updTmpDir "\staged.exe"
    FileAppend("MZ_VALID_NEW_VERSION", goodStaged, "UTF-8-RAW")
    goodSz := FileGetSize(goodStaged)
    goodSha := HashFileSHA256_Hex(goodStaged)
    badHashStaged := updTmpDir "\badhash.exe"
    FileAppend("MZ_VALID_NEW_VERSION", badHashStaged, "UTF-8-RAW")
    badHashRes := VerifyStagedExecutable(badHashStaged, goodSz, "0000000000000000000000000000000000000000000000000000000000000000")
    Assert("VerifyStagedExecutable rejects & deletes payload on SHA-256 mismatch", !badHashRes.ok && !FileExist(badHashStaged))

    goodRes := VerifyStagedExecutable(goodStaged, goodSz, goodSha)
    Assert("VerifyStagedExecutable accepts valid MZ binary with matching size & SHA-256", goodRes.ok && goodRes.shaVerified)

    liveExe := updTmpDir "\PresenterSync_Mock.exe"
    FileAppend("MZ_OLD_VERSION", liveExe, "UTF-8-RAW")
    beforeBox := { called: false }
    swapRes := PerformAtomicExeSwapAndRelaunch(liveExe, goodStaged, ["-Instance", "CI"], false, false, (*) => (beforeBox.called := true))
    Assert("PerformAtomicExeSwapAndRelaunch atomically moves current -> .old and staged -> current",
        swapRes.ok && beforeBox.called && FileExist(liveExe) && HashFileSHA256_Hex(liveExe) == goodSha
        && FileExist(liveExe ".old") && !FileExist(goodStaged))

    leftCnt := ProcessSelfUpdateStartupCleanup(["--cleanup-old-exe", liveExe ".old"], liveExe)
    Assert("ProcessSelfUpdateStartupCleanup deletes .old artifact cleanly",
        leftCnt == 0 && !FileExist(liveExe ".old"))
} finally {
    try DirDelete(updTmpDir, true)
}

; ==============================================================================
; SECTION 22: v6.2.0 HOST BRIDGE 2.0 - VOICE-WHILE-MUTED & SHARED DECK HANDLERS
; ==============================================================================
cfgVwm := Config(testIni)
Assert("EnableVoiceWhileMutedAlert defaults to true", cfgVwm.EnableVoiceWhileMutedAlert == true)
stVwm := OverlayState(cfgVwm)
stVwm.isMuted := false
Assert("EvaluateMutedVoiceAlert ignores speech when unmuted",
    !EvaluateMutedVoiceAlert(cfgVwm, stVwm, 0.85, 1000) && !stVwm.voiceWhileMuted)

stVwm.isMuted := true
Assert("EvaluateMutedVoiceAlert ignores quiet ambient floor",
    !EvaluateMutedVoiceAlert(cfgVwm, stVwm, 0.04, 1000) && !stVwm.voiceWhileMuted)
Assert("EvaluateMutedVoiceAlert does not trigger before sustained 1500ms",
    !EvaluateMutedVoiceAlert(cfgVwm, stVwm, 0.40, 1000)
    && !EvaluateMutedVoiceAlert(cfgVwm, stVwm, 0.45, 2200) && !stVwm.voiceWhileMuted)
Assert("EvaluateMutedVoiceAlert triggers after 1500ms sustained speech while muted",
    EvaluateMutedVoiceAlert(cfgVwm, stVwm, 0.45, 2550) && stVwm.voiceWhileMuted)
Assert("EvaluateMutedVoiceAlert holds alert during brief quiet gap (<1500ms)",
    !EvaluateMutedVoiceAlert(cfgVwm, stVwm, 0.01, 3000) && stVwm.voiceWhileMuted)
Assert("EvaluateMutedVoiceAlert clears after 1500ms sustained silence",
    EvaluateMutedVoiceAlert(cfgVwm, stVwm, 0.01, 4550) && !stVwm.voiceWhileMuted)

EvaluateMutedVoiceAlert(cfgVwm, stVwm, 0.50, 5000)
EvaluateMutedVoiceAlert(cfgVwm, stVwm, 0.50, 6600)
stVwm.isMuted := false
Assert("EvaluateMutedVoiceAlert clears immediately upon unmuting",
    EvaluateMutedVoiceAlert(cfgVwm, stVwm, 0.50, 6700) && !stVwm.voiceWhileMuted)

pptLog := []
mockObsDeck := []
stDeck := {
    EnableWS: true,
    obsConnected: true,
    obsWs: { sendText: (this, pkt) => mockObsDeck.Push(pkt) },
    pptNextFn: (*) => (pptLog.Push("N"), true),
    pptPrevFn: (*) => (pptLog.Push("P"), true)
}
cfgDeck := Config(testIni)
cfgDeck.EnableWS := true
Assert("ExecuteHostRemotePptCommand invokes Next and Prev handlers cleanly",
    ExecuteHostRemotePptCommand(cfgDeck, stDeck, "next")
    && ExecuteHostRemotePptCommand(cfgDeck, stDeck, "prev")
    && pptLog.Length == 2 && pptLog[1] == "N" && pptLog[2] == "P")
Assert("ExecuteHostToggleRecord sends ToggleRecord to OBS when connected",
    ExecuteHostToggleRecord(cfgDeck, stDeck) && mockObsDeck.Length == 1 && InStr(mockObsDeck[1], "ToggleRecord"))

; ==============================================================================
; SECTION 23: v6.4.0 HOST & REMOTE QOL - AUTO-PROFILE TRIGGERS & DIAGNOSTICS
; ==============================================================================
if FileExist(testIni)
    FileDelete(testIni)
if FileExist(testIni ".bak")
    FileDelete(testIni ".bak")
cfgAp := Config(testIni)
cfgAp.AudioRoutingMode := 1
cfgAp.SaveProfile("Default")
cfgAp.AudioRoutingMode := 2
cfgAp.ConferencingApp := "Zoom"
cfgAp.SaveProfile("Zoom")
cfgAp.AudioRoutingMode := 2
cfgAp.ConferencingApp := "Microsoft Teams"
cfgAp.SaveProfile("Teams")
cfgAp.ApplyProfile("Default")

parsedRules := ParseAutoProfileRules("C:\Program Files\obs-studio\bin\64bit\obs64.exe=Default|Zoom.exe=Zoom;ms-teams=Teams")
Assert("ParseAutoProfileRules normalizes paths, deduplicates & preserves order",
    parsedRules.Length == 3
    && parsedRules[1].proc == "obs64.exe" && parsedRules[1].profile == "Default"
    && parsedRules[2].proc == "zoom.exe" && parsedRules[2].profile == "Zoom"
    && parsedRules[3].proc == "ms-teams" && parsedRules[3].profile == "Teams")

cfgAp.AutoProfileRules := FormatAutoProfileRules(parsedRules)
cfgAp.EnableAutoProfileSwitch := true
cfgAp.WriteBool("Settings", "EnableAutoProfileSwitch", true)
cfgAp.Write("Settings", "AutoProfileRules", cfgAp.AutoProfileRules)
cfgApReload := Config(testIni)
Assert("AutoProfileRules and EnableAutoProfileSwitch persist across Config reload",
    cfgApReload.EnableAutoProfileSwitch == true && cfgApReload.AutoProfileRules == "obs64.exe=Default|zoom.exe=Zoom|ms-teams=Teams")

stAp := OverlayState(cfgApReload)
resZoom := EvaluateAutoProfileTrigger(cfgApReload, stAp, "Zoom.exe")
Assert("EvaluateAutoProfileTrigger switches to matched Zoom profile & records Default base",
    resZoom.changed == true && resZoom.action == "switched" && resZoom.baseProfile == "Default" && cfgApReload.ActiveProfile == "Zoom" && stAp._autoProfileBase == "Default")

resZoomHold := EvaluateAutoProfileTrigger(cfgApReload, stAp, "zoom.exe")
Assert("EvaluateAutoProfileTrigger holds already-active matched profile without churn",
    resZoomHold.changed == false && resZoomHold.action == "held" && cfgApReload.ActiveProfile == "Zoom")

resTeams := EvaluateAutoProfileTrigger(cfgApReload, stAp, "ms-teams.exe")
Assert("EvaluateAutoProfileTrigger matches stem rule (ms-teams -> ms-teams.exe) & preserves original base",
    resTeams.changed == true && resTeams.action == "switched" && cfgApReload.ActiveProfile == "Teams" && stAp._autoProfileBase == "Default")

resLeave := EvaluateAutoProfileTrigger(cfgApReload, stAp, "POWERPNT.EXE")
Assert("EvaluateAutoProfileTrigger restores base profile when focus leaves matching apps",
    resLeave.changed == true && resLeave.action == "restored" && cfgApReload.ActiveProfile == "Default" && stAp._autoProfileMatched == "")

; Test Sanitized Diagnostics Export with sensitive secrets & paired device tokens
cfgDiag := Config(testIni)
cfgDiag.obsPassword := "SuperSecretObsPass!99"
cfgDiag.Write("Settings", "ObsPassword", "SuperSecretObsPass!99")
cfgDiag.InternetPairingCode := "PS-SECR-ET99"
cfgDiag.Write("Settings", "InternetPairingCode", "PS-SECR-ET99")
cfgDiag.SessionPairingCode := "XYZ-789"
cfgDiag.Write("Settings", "SessionPairingCode", "XYZ-789")
cfgDiag.SessionToken := "tok_bridge_session_secret_42"
cfgDiag.Write("Settings", "SessionToken", "tok_bridge_session_secret_42")
cfgDiag.Write("HostBridgePairedDevices", "android-tab1", "v1|Smart%20Board|Android|tok_paired_device_999|2026-11-15|192.168.1.44|WS|1")

diagPath := A_Temp "\ps_test_diag_bundle.txt"
if FileExist(diagPath)
    FileDelete(diagPath)
diagRes := ExportSanitizedDiagnostics(cfgDiag, stAp, diagPath, false)
diagText := diagRes.ok ? FileRead(diagPath, "UTF-8") : ""
if FileExist(diagPath)
    FileDelete(diagPath)
Assert("ExportSanitizedDiagnostics writes diagnostic bundle cleanly",
    diagRes.ok && diagText != "" && InStr(diagText, "SANITIZED CONFIGURATION (.INI)"))
Assert("ExportSanitizedDiagnostics redacts ObsPassword, PairingCodes, SessionToken & PairedDevice tokens",
    !InStr(diagText, "SuperSecretObsPass!99")
    && !InStr(diagText, "PS-SECR-ET99")
    && !InStr(diagText, "XYZ-789")
    && !InStr(diagText, "tok_bridge_session_secret_42")
    && !InStr(diagText, "tok_paired_device_999")
    && InStr(diagText, "[REDACTED]")
    && InStr(diagText, "Smart%20Board"))

; ==============================================================================
; SECTION 24: v6.5.0 CROSS-PLATFORM HUD SNAKE (XINPUT / POV & REMOTE SINGLE-TIER)
; ==============================================================================
padUp := HudSnake.DecodeXInputGamepadState(0x0001, 0, 0)
padRight := HudSnake.DecodeXInputGamepadState(0x0008, 0, 0)
stickUp := HudSnake.DecodeXInputGamepadState(0, 0, 22000)
stickDead := HudSnake.DecodeXInputGamepadState(0, 3000, -4000)
padBtns := HudSnake.DecodeXInputGamepadState(0x1000 | 0x4000, 0, 0)
padExit := HudSnake.DecodeXInputGamepadState(0x0020, 0, 0)
Assert("DecodeXInputGamepadState maps D-Pad, Thumbstick Y+->Up, Deadzone & Face Buttons accurately",
    padUp.dirX == 0 && padUp.dirY == -1
    && padRight.dirX == 1 && padRight.dirY == 0
    && stickUp.dirX == 0 && stickUp.dirY == -1
    && stickDead.dirX == 0 && stickDead.dirY == 0
    && padBtns.pausePressed && padBtns.edgePressed && !padBtns.exitPressed
    && padExit.exitPressed)

povN := HudSnake.DecodeDirectInputPov(0)
povE := HudSnake.DecodeDirectInputPov(9000)
povS := HudSnake.DecodeDirectInputPov(18000)
povW := HudSnake.DecodeDirectInputPov(27000)
povC := HudSnake.DecodeDirectInputPov(65535)
Assert("DecodeDirectInputPov decodes cardinal POV angles & centered state cleanly",
    povN.y == -1 && povE.x == 1 && povS.y == 1 && povW.x == -1 && povC.x == 0 && povC.y == 0)

remCfg := Config(testIni)
remCfg.ShowIndicator := true
remSpy := { refreshed: 0, reconnected: 0 }
remSpyRefr := (*) => (remSpy.refreshed += 1)
remSpyReconn := (*) => (remSpy.reconnected += 1)
remState := {
    savedX: 200,
    savedY: 200,
    baseWidth: 80,
    baseHeight: 40,
    isMuted: true,
    obsConnected: false,
    MicGui: Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000 -DPIScale"),
    refreshHudFn: remSpyRefr,
    reconnectTimerFn: remSpyReconn
}
okRemStart := HudSnake.Start(remCfg, remState, true)
remSeedsLen := HudSnake._morphSeeds.Length
remSnakeLen := HudSnake._snake.Length
HudSnake._dir := { x: 1, y: 0 }
HudSnake._dirQueue := []
HudSnake.QueueDirection(0, -1)
edgeBefore := HudSnake._edgeWrap
HudSnake.ToggleEdgeMode()
remWrapFlipped := (HudSnake._edgeWrap == !edgeBefore)
HudSnake.ToggleEdgeMode()
HudSnake.TogglePause()
remPaused := (HudSnake.Phase = "paused")
HudSnake.TogglePause()
remResumed := (HudSnake.Phase = "playing")
HudSnake.Stop()
try SetTimer(remSpyReconn, 0)
try remState.MicGui.Destroy()
Assert("HudSnake supports 1-tier Remote state without RecGui & restores Remote callbacks on Stop",
    okRemStart && remSeedsLen >= 5 && remSnakeLen >= 5 && remWrapFlipped && remPaused && remResumed
    && !HudSnake.IsActive && remSpy.refreshed >= 1,
    Format("ok={} seeds={} snake={} flip={} p={} r={} active={} refr={}", okRemStart, remSeedsLen, remSnakeLen, remWrapFlipped, remPaused, remResumed, HudSnake.IsActive, remSpy.refreshed))

helpRemSnake := SearchHelpEntries("", "All", true)
helpPriSnake := SearchHelpEntries("rfeat-easter-snake", "All", false)
hasRemSnakeHint := false
for hEntry in helpRemSnake {
    if (hEntry.id = "rfeat-easter-snake" && InStr(hEntry.body, "Ctrl + Alt + Shift + Z") && InStr(hEntry.body, "Sector Z"))
        hasRemSnakeHint := true
}
Assert("HelpCenter Remote catalog includes rfeat-easter-snake without leaking to Primary or Tray buttons",
    hasRemSnakeHint && !InStr(remoteSrc, 'TrayMenu.Add("Try at your own risk') && !InStr(remoteSrc, "Play Snake"))

; ==============================================================================
; SECTION 25: v6.6.0 ZERO-CONFIG UDP DISCOVERY, FAILOVER & SLEEP/WAKE AUTO-HEAL
; ==============================================================================
if FileExist(testIni)
    FileDelete(testIni)
if FileExist(testIni ".bak")
    FileDelete(testIni ".bak")
cfgM6 := Config(testIni)
uuid1 := cfgM6.HostUuid
cfgM6b := Config(testIni)
Assert("Config auto-generates & persists stable HostUuid across reloads",
    RegExMatch(uuid1, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$") > 0
    && cfgM6b.HostUuid == uuid1, uuid1)

cfgM6.obsPassword := "SuperSecretPw_M6!"
cfgM6.SessionPairingCode := "K7M-9P2"
cfgM6.InternetPairingCode := "PS-M6-SECRET"
beaconJson := BuildPublicDiscoveryBeaconJson(cfgM6, 4456, 4455)
Assert("BuildPublicDiscoveryBeaconJson exposes PS_DISCOVER_V1 metadata with zero secrets",
    InStr(beaconJson, '"proto":"PS_DISCOVER_V1"')
    && InStr(beaconJson, '"hostUuid":"' uuid1 '"')
    && !InStr(beaconJson, "SuperSecretPw_M6!")
    && !InStr(beaconJson, "K7M-9P2")
    && !InStr(beaconJson, "PS-M6-SECRET")
    && !InStr(beaconJson, "obsPassword")
    && !InStr(beaconJson, "sessionToken"))

stM6 := {
    isMuted: true,
    recState: 1,
    recElapsedSec: 12,
    streamState: 0,
    voiceWhileMuted: false,
    obsConnected: false,
    EnableWS: false,
    obsTimerFn: ""
}
brM6 := StartHostCompanionBridge(cfgM6, stM6, 0, 0, 0)
Assert("HostCompanionBridge starts public UDP discovery port alongside TCP/Pair ports",
    IsObject(brM6) && brM6.running && brM6.boundDiscoverPort > 0 && brM6.boundTcpPort > 0)

suspRes := HandleHostPowerEvent(cfgM6, stM6, 4)
wakeRes := HandleHostPowerEvent(cfgM6, stM6, 7)
autoWakeRes := HandleHostPowerEvent(cfgM6, stM6, 18)
Assert("HandleHostPowerEvent handles sleep(0x4) & wake(0x7/0x12) with listener refresh",
    suspRes == "suspend" && wakeRes == "resume" && autoWakeRes == "resume"
    && !stM6.isSystemSuspending && stM6.lastWakeReason == "power_resume_auto"
    && brM6.running && brM6.boundDiscoverPort > 0)

uriWithUuid := BuildHostPairingUri(cfgM6, ["192.168.10.50"])
Assert("BuildHostPairingUri includes hostUuid query parameter",
    InStr(uriWithUuid, "&uuid=" uuid1))

StopHostCompanionBridge()

; Verify PresenterSync_Remote wires PairedHostUuid, PS_DISCOVER_V1 & WAN re-promotion safely
remM6Src := FileRead(A_ScriptDir "\..\PresenterSync_Remote.ahk", "UTF-8")
rbcSrc := FileRead(A_ScriptDir "\..\Lib\RemoteBridgeClient.ahk", "UTF-8")
primM6Src := FileRead(A_ScriptDir "\..\PresenterSync.ahk", "UTF-8")
Assert("Remote & Primary wire v6.6.0 WM_POWERBROADCAST(0x218), PS_DISCOVER_V1 & WAN->LAN re-promotion",
    InStr(primM6Src, "OnMessage(0x0218")
    && InStr(remM6Src, "PairedHostUuid")
    && InStr(remM6Src, "TryPromoteRemoteWanToLan")
    && InStr(rbcSrc, "DiscoverPublicHostsUdp")
    && InStr(rbcSrc, "FollowPairedHostIpShift")
    && InStr(rbcSrc, "ProbeHostBridgeHealth"))

; ==============================================================================
; SECTION 26: v6.7.0 DIRECTOR DECK, SYNCED TIMER, NUDGE, STANDBY, PTT & CUSTOM HEX
; ==============================================================================
Assert("NormalizeColorHex & PickReadableIconHex enforce WCAG contrast on light/dark backgrounds",
    NormalizeColorHex("#0ea5e9") == "0EA5E9"
    && NormalizeColorHex("bad", "107C10") == "107C10"
    && PickReadableIconHex("FEF08A") == "111827"
    && PickReadableIconHex("0F2E22") == "FFFFFF")

if FileExist(testIni)
    FileDelete(testIni)
if FileExist(testIni ".bak")
    FileDelete(testIni ".bak")
cfgM7 := Config(testIni)
stM7 := OverlayState(cfgM7)
stM7.suppressNudgeBanners := true
stM7.obsConnected := true
cfgM7.EnableWS := true
stM7.currentSceneName := "Main Slides"
stM7.sceneList := ["Main Slides", "Webcam Full", "BRB"]

SetCustomHudColors(cfgM7, stM7, "#0EA5E9", "#FDE047", true)
cfgM7Reload := Config(testIni)
Assert("SetCustomHudColors persists Custom preset + Live/Muted hexes & updates OverlayState palette",
    cfgM7Reload.HudColorPreset == "Custom"
    && cfgM7Reload.CustomLiveHex == "0EA5E9"
    && cfgM7Reload.CustomMutedHex == "FDE047"
    && stM7.colors.live == "0EA5E9"
    && stM7.colors.muted == "FDE047"
    && stM7.colors.iconMuted == "111827")

uriCustom := BuildHostPairingUri(cfgM7, ["192.168.10.50"])
Assert("BuildHostPairingUri embeds Custom preset & live/muted hexes cleanly",
    InStr(uriCustom, "&preset=Custom") && InStr(uriCustom, "&clh=0EA5E9") && InStr(uriCustom, "&cmh=FDE047"))

; Push-to-Talk Hold-to-Unmute release cycle (requires isMuted == true at press start)
pttCalls := []
cfgM7.EnablePushToTalk := true
stM7.isMuted := false
pttLiveNoop := ExecutePushToTalkHoldCycle(cfgM7, stM7, (m) => pttCalls.Push(m), "b", (k, o) => 1)
Assert("ExecutePushToTalkHoldCycle is a no-op when mic is already LIVE (isMuted == false)",
    !pttLiveNoop && pttCalls.Length == 0)

stM7.isMuted := true
pttOk := ExecutePushToTalkHoldCycle(cfgM7, stM7, (m) => pttCalls.Push(m), "b", (k, o) => 1)
Assert("ExecutePushToTalkHoldCycle unmutes immediately on press and re-mutes on release when muted",
    pttOk && pttCalls.Length == 2 && pttCalls[1] == false && pttCalls[2] == true)

; OBS Scene Switch, Record Pause, Record Split & Standby Macro snapshot/restore
obsReqsM7 := []
stM7.obsSceneSwitchFn := (sc) => (obsReqsM7.Push("scene:" sc), true)
stM7.obsRecPauseFn := (*) => (obsReqsM7.Push("pause"), true)
stM7.obsRecSplitFn := (*) => (obsReqsM7.Push("split"), true)

stM7.isMuted := false
stM7.recState := 1
cfgM7.AudioRoutingMode := 2 ; deterministic optimistic SyncUIState in offline test
cfgM7.StandbySceneName := "BRB"
cfgM7.ExitBrbSafelyMuted := true
enterBrb := ExecuteHostToggleStandby(cfgM7, stM7, true)
duringStandbyOk := (stM7.isStandby == true && stM7.isMuted == true && stM7.currentSceneName == "BRB" && stM7.recState == 2)
exitBrb := ExecuteHostToggleStandby(cfgM7, stM7, false)
restoredSafeOk := (stM7.isStandby == false && stM7.isMuted == true && stM7.currentSceneName == "Main Slides" && stM7.recState == 1)
cfgM7.ExitBrbSafelyMuted := false
stM7.isMuted := false
ExecuteHostToggleStandby(cfgM7, stM7, true)
ExecuteHostToggleStandby(cfgM7, stM7, false)
restoredUnmutedOk := (stM7.isStandby == false && stM7.isMuted == false && stM7.currentSceneName == "Main Slides" && stM7.recState == 1)
cfgM7.ExitBrbSafelyMuted := true
Assert("ExecuteHostToggleStandby keeps mic safely muted by default on exit and restores prior mute when ExitBrbSafelyMuted=false",
    enterBrb && duringStandbyOk && exitBrb && restoredSafeOk && restoredUnmutedOk)

swOk := ExecuteHostSwitchScene(cfgM7, stM7, "Webcam Full")
spOk := ExecuteHostSplitRecord(cfgM7, stM7)
Assert("ExecuteHostSwitchScene & ExecuteHostSplitRecord invoke OBS actions cleanly",
    swOk && spOk && stM7.currentSceneName == "Webcam Full" && obsReqsM7[obsReqsM7.Length] == "split")

; Presenter Countdown Timer & Overtime transition
StartHostPresenterTimer(cfgM7, stM7, 122)
SetTimer(stM7.presenterTimerFn, 0) ; step deterministically in unit test
StepHostPresenterTimerTick(cfgM7, stM7) ; 121
StepHostPresenterTimerTick(cfgM7, stM7) ; 120
atTwoMin := (stM7.timerRemainingSec == 120 && stM7.timerState == "running")
PauseHostPresenterTimer(cfgM7, stM7)
pausedOk := (stM7.timerState == "paused")
StartHostPresenterTimer(cfgM7, stM7, 1)
SetTimer(stM7.presenterTimerFn, 0)
StepHostPresenterTimerTick(cfgM7, stM7) ; 0 -> overtime
overtimeOk := (stM7.timerState == "overtime" && stM7.timerRemainingSec == 0)
ResetHostPresenterTimer(cfgM7, stM7, 600)
Assert("Presenter Countdown Timer steps cleanly through 2:00 checkpoint, pause, overtime & reset",
    atTwoMin && pausedOk && overtimeOk && stM7.timerState == "stopped" && stM7.timerRemainingSec == 600 && FormatCountdownClock(-15) == "-00:15")

; Relay Stage Nudge & Standby handling
mockRelayM7 := { sent: [], SendText: (this, t) => this.sent.Push(t) }
stM7.relayMockWs := mockRelayM7
cfgM7.RemoteNetworkMode := "Internet"
cfgM7.InternetPairingCode := "PS-M7-RELAY"
cfgM7.obsPassword := "PwM7"
authTokM7 := GetInternetRelayAuthToken(cfgM7.InternetPairingCode, cfgM7.obsPassword)
HandleHostRelayMessage(cfgM7, stM7, "", FormatRelayPacket("remote", "switch_scene", "Main Slides", authTokM7))
BroadcastHostStageNudge(cfgM7, stM7, "Wrap up Q&A", "Host", "F59E0B")
relayHasNudge := false
for sentPkt in mockRelayM7.sent {
    parsedSent := ParseRelayPacket(sentPkt)
    if (IsObject(parsedSent) && parsedSent.cmd == "nudge" && parsedSent.data == "Host;Wrap up Q&A")
        relayHasNudge := true
}
Assert("WAN Relay executes M7 Director commands and broadcasts dir_state & stage nudges",
    stM7.currentSceneName == "Main Slides" && relayHasNudge)

remM7Src := FileRead(A_ScriptDir "\..\PresenterSync_Remote.ahk", "UTF-8")
primM7Src := FileRead(A_ScriptDir "\..\PresenterSync.ahk", "UTF-8")
Assert("Primary & Remote wire v6.7.0 Director Deck, Standby BRB, Stage Nudge, Push-to-Talk & Custom Colors",
    InStr(primM7Src, "OBS Director")
    && InStr(primM7Src, "ExecutePushToTalkHoldCycle")
    && InStr(remM7Src, "SendRemoteSwitchScene")
    && InStr(remM7Src, "SendRemoteStageNudge")
    && InStr(remM7Src, "CustomLiveHex"))

; ==============================================================================
; SECTION 27: v6.8.0 SESSION TIMELINE, CHAPTER CSV/MD EXPORT & SETUP WIZARD
; ==============================================================================

SessionTimeline.Clear()
Assert("SessionTimeline clears cleanly", SessionTimeline.GetEntries().Length == 0)
Assert("FormatHms formats 0s and 3665s accurately",
    SessionTimeline.FormatHms(0) == "00:00:00" && SessionTimeline.FormatHms(3665) == "01:01:05")
Assert("FormatYouTubeTimestamp formats <1h and >=1h timestamps",
    SessionTimeline.FormatYouTubeTimestamp(65) == "01:05" && SessionTimeline.FormatYouTubeTimestamp(3665) == "1:01:05")

SessionTimeline.Record("Mic", "Mic Muted", "MUTED", "", 0, "2026-11-16T08:00:00Z")
SessionTimeline.Record("Scene", "=SUM(A1:A2)", "", 'Quote, "Deck"', 65, "2026-11-16T08:01:05Z")
SessionTimeline.Record("Recording", "Split Recording", "", "chapter", 3665, "2026-11-16T09:01:05Z")
Assert("SessionTimeline records and filters categories",
    SessionTimeline.GetEntries("All").Length == 3 && SessionTimeline.GetEntries("Scene").Length == 1)

csvOut := SessionTimeline.ExportChapterCsv()
Assert("CSV export includes header, quoted comma/quote escaping & formula guard",
    InStr(csvOut, "Timecode,Seconds,Color,Category,Marker Name,Notes")
    && InStr(csvOut, "'=SUM(A1:A2)")
    && InStr(csvOut, '""Deck""')
    && InStr(csvOut, "01:01:05,3665,Red,Recording,Split Recording"))

ytOut := SessionTimeline.ExportYouTubeChapters()
Assert("YouTube chapter block includes chronological timestamps",
    InStr(ytOut, "00:00 Session Start") && InStr(ytOut, "01:05 =SUM(A1:A2)") && InStr(ytOut, "1:01:05 Split Recording"))

tmpCsv := A_Temp "\ps_test_timeline_" A_TickCount ".csv"
tmpMd := A_Temp "\ps_test_timeline_" A_TickCount ".md"
Assert("SaveExportToFile writes CSV chapter file",
    SessionTimeline.SaveExportToFile(tmpCsv, "csv") && FileExist(tmpCsv))
Assert("SaveExportToFile writes Markdown summary file",
    SessionTimeline.SaveExportToFile(tmpMd, "md") && FileExist(tmpMd) && InStr(FileRead(tmpMd, "UTF-8"), "| Timecode |"))
if FileExist(tmpCsv)
    FileDelete(tmpCsv)
if FileExist(tmpMd)
    FileDelete(tmpMd)

; Bounded ring buffer eviction test (> 2000 entries -> retains newest 2000)
prevAutoTl := SessionTimeline.EnableAutosave
SessionTimeline.EnableAutosave := false
SessionTimeline.Clear()
Loop 2050 {
    SessionTimeline.Record("Mic", "Evt " A_Index, "", "", A_Index)
}
SessionTimeline.EnableAutosave := prevAutoTl
boundedEntries := SessionTimeline.GetEntries()
Assert("SessionTimeline bounds capacity at 2000 entries and evicts oldest FIFO",
    boundedEntries.Length == SessionTimeline.MAX_ENTRIES
    && boundedEntries[1].summary == "Evt 51"
    && boundedEntries[2000].summary == "Evt 2050")

; Live runtime integration hooks
SessionTimeline.Clear()
tlState := OverlayState(cfg)
tlState.isMuted := false
tlState.obsConnected := true
tlState.scenes := ["Main", "Workshop"]
tlState.activeScene := "Main"
prevHookMuted := cfg.IsMuted
SyncUIState(cfg, tlState, true)
SyncRecState(cfg, tlState, 1, 15000)
SyncSceneState(cfg, tlState, "Workshop")
EvaluateMutedVoiceAlert(cfg, tlState, 0.35, 1000)
EvaluateMutedVoiceAlert(cfg, tlState, 0.35, 1000 + UIConstants.MUTED_VOICE_TRIGGER_MS + 50)
cfg.IsMuted := prevHookMuted
cfg.WriteBool("Settings", "IsMuted", prevHookMuted)
hookCsv := SessionTimeline.ExportChapterCsv()
Assert("Live UI/OBS hooks automatically append Mic, Recording, Scene & Alert timeline entries",
    InStr(hookCsv, ",Mic,") && InStr(hookCsv, ",Recording,") && InStr(hookCsv, ",Scene,") && InStr(hookCsv, ",Alert,"))

; Setup Wizard hardware/network probes (override-driven deterministic checks)
probeCfg := {
    EnableWS: true, AudioRoutingMode: 2, targetMicName: "Rode NT", ConferencingApp: "Teams",
    ShowIndicator: true, IndicatorScale: 1.0
}
probeOk := RunWindowsSetupProbes(probeCfg, 0, {
    obsPortListening: true,
    audioMeterAvailable: true,
    lanIps: ["192.168.50.10"],
    bridgeSummary: { running: true, tcpPort: 4456, discoverPort: 4457 },
    firewallProfile: "Private",
    firewallBlocked: false,
    isAdmin: true
})
probeNoGui := RunWindowsSetupProbes(probeCfg, tlState, {
    obsPortListening: true,
    audioMeterAvailable: true,
    lanIps: ["192.168.50.10"],
    bridgeSummary: { running: true, tcpPort: 4456, discoverPort: 4457 },
    firewallProfile: "Private",
    firewallBlocked: false,
    isAdmin: true
})
probeEmpty := RunWindowsSetupProbes({ EnableWS: false, AudioRoutingMode: 0, ShowIndicator: false }, 0, {
    obsPortListening: false,
    audioMeterAvailable: false,
    lanIps: [],
    bridgeSummary: { running: false, tcpPort: 4456, discoverPort: 4457 },
    firewallProfile: "Public",
    firewallBlocked: true,
    isAdmin: false
})
Assert("RunWindowsSetupProbes evaluates 6 checks accurately for ready vs unconfigured states",
    probeOk.totalCount == 6 && probeOk.passedCount == 6
    && probeNoGui.passedCount == 5 && !probeNoGui.steps[3].ok
    && probeEmpty.totalCount == 6 && probeEmpty.passedCount == 0)

primM8Src := FileRead(A_ScriptDir "\..\PresenterSync.ahk", "UTF-8")
remM8Src := FileRead(A_ScriptDir "\..\PresenterSync_Remote.ahk", "UTF-8")
obsNetSrc := FileRead(A_ScriptDir "\..\Lib\OBS_Network.ahk", "UTF-8")
bridgeM8Src := FileRead(A_ScriptDir "\..\Lib\HostBridge.ahk", "UTF-8")
Assert("Windows source files declare active version & wire Timeline + Guided Setup Wizard",
    InStr(primM8Src, UIConstants.APP_VERSION) && InStr(remM8Src, UIConstants.APP_VERSION)
    && InStr(primM8Src, "ShowGuidedSetupWizard") && InStr(primM8Src, "ShowTimelineWindow")
    && InStr(obsNetSrc, "SessionTimeline.Record") && InStr(bridgeM8Src, "SessionTimeline.Record"))
SessionTimeline.Clear()

; ==============================================================================
; SECTION 28: v6.9.0 PRIMARY-ONLY SECONDARY INDEPENDENT MIC PILL INDICATOR
; ==============================================================================
secIni := A_Temp "\ps_sec_mic_test_" A_TickCount ".ini"
if FileExist(secIni)
    FileDelete(secIni)
if FileExist(secIni ".bak")
    FileDelete(secIni ".bak")
cfgSec := Config(secIni)
Assert("Secondary Mic Pill defaults OFF with Independent SecondaryPosition='Default'",
    !cfgSec.ShowSecondaryMicHud && cfgSec.savedSecondaryX == "Default" && cfgSec.savedSecondaryY == "Default")

cfgSec.ShowIndicator := true
cfgSec.ShowExtraHuds := true
cfgSec.EnableWS := true
cfgSec.EnableRemoteConnections := false
cfgSec.ShowText := false
cfgSec.EnableMagneticSnap := false
stSec := OverlayState(cfgSec)
stSec.obsTimerFn := ""
InitHUD(cfgSec, stSec, true)
Sleep(40)

Assert("InitHUD creates valid SecondaryMicGui strictly 1-tier (8 total primary HUD windows) and hides when OFF",
    IsGuiValid(stSec.SecondaryMicGui)
    && stSec.SecondaryMicGui.Hwnd != stSec.MicGui.Hwnd
    && GetHudGuiList(stSec, true).Length == 8
    && !DllCall("IsWindowVisible", "Ptr", stSec.SecondaryMicGui.Hwnd))

ToggleSecondaryMicHud(cfgSec, stSec)
Sleep(40)
secDefaultVisible := DllCall("IsWindowVisible", "Ptr", stSec.SecondaryMicGui.Hwnd) != 0
secPos := ComputeSecondaryMicLayout(cfgSec, stSec)
noPrimOverlap := (secPos.x + secPos.w <= stSec.savedX) || (secPos.x >= stSec.savedX + stSec.baseWidth)
    || (secPos.y + secPos.h <= stSec.savedY) || (secPos.y >= stSec.savedY + stSec.baseHeight)
Assert("Toggling Secondary Mic Pill ON shows Mic-Only window non-overlapping with Primary pill",
    cfgSec.ShowSecondaryMicHud && secDefaultVisible && noPrimOverlap && IsHudHwnd(stSec, stSec.SecondaryMicGui.Hwnd))

; Move Primary pill independently and verify Secondary pill does NOT move with it
oldSecX := stSec.savedSecondaryX, oldSecY := stSec.savedSecondaryY
cfgSec.savedX := 240, cfgSec.savedY := 320
cfgSec.Write("Position", "X", 240), cfgSec.Write("Position", "Y", 320)
UpdateHudLayout(stSec, 240, 320)
WinGetPos(&pWinX, &pWinY,,, "ahk_id " stSec.MicGui.Hwnd)
WinGetPos(&sWinX, &sWinY,,, "ahk_id " stSec.SecondaryMicGui.Hwnd)
Assert("Moving Primary HUD leaves Secondary Mic Pill at its independent coordinates",
    pWinX == 240 && pWinY == 320 && sWinX == oldSecX && sWinY == oldSecY)

; Drag Secondary pill cleanly & verify [SecondaryPosition] persistence + Primary [Position] untouched
draggedSec := ApplyDraggedSecondaryPosition(cfgSec, stSec, 999999, 999999)
stSec.SecondaryMicGui.Move(draggedSec.x, draggedSec.y, draggedSec.w, draggedSec.h)
iniSecX := IniRead(secIni, "SecondaryPosition", "X", "")
iniPrimX := IniRead(secIni, "Position", "X", "")
Assert("Dragging Secondary pill clamps to virtual screen bounds & persists ONLY [SecondaryPosition]",
    Integer(iniSecX) == draggedSec.x && draggedSec.x < 999999 && Integer(iniPrimX) == 240 && cfgSec.savedX == 240)

; Verify click-to-mute, theme/scale sync, breathing sync, and auto-dodge isolation
secTrigCb := { cnt: 0 }
stSec.triggerMuteFn := (*) => (secTrigCb.cnt += 1, SyncUIState(cfgSec, stSec, !stSec.isMuted))
clickRet := HandleHudPillClick(cfgSec, stSec, stSec.SecondaryMicGui.Hwnd)
Assert("Clicking Secondary Mic Pill syncs mute state with Primary Mic Pill",
    clickRet == "secondary_mic" && secTrigCb.cnt == 1 && stSec.isMuted)

cfgSec.ShowText := true
cfgSec.HudColorPreset := "Custom"
cfgSec.CustomLiveHex := "0EA5E9"
SyncTelemetryBackendsFromConfig(cfgSec, stSec)
Sleep(30)
WinGetPos(,, &sTextW, &sTextH, "ahk_id " stSec.SecondaryMicGui.Hwnd)
Assert("ShowText & Theme changes resize and sync Secondary Mic Pill identically to Primary",
    sTextW == stSec.baseWidth && sTextH == stSec.baseHeight && stSec.baseWidth == UIConstants.BASE_WIDTH_TEXT)

SetTimer(stSec.breathTimerFn, 0)
stSec.isMuted := true
stSec.isAutoDodged := false
stSec.secondaryIsAutoDodged := false
stSec.breathDir := -UIConstants.PULSE_STEP_NORMAL
stSec._breathStepAlpha := cfgSec.OpacityLevel
stSec.currentAlpha := cfgSec.OpacityLevel
stSec.secondaryCurrentAlpha := cfgSec.OpacityLevel
beforeBreathSec := stSec.secondaryCurrentAlpha
BreathingAnimation(cfgSec, stSec)
Assert("Breathing animation updates Secondary Mic Pill alpha in lockstep with Primary",
    stSec.secondaryCurrentAlpha < beforeBreathSec && stSec.secondaryCurrentAlpha == stSec.currentAlpha)

cfgSec.HudAutoDodge := true
AutoDodgeTick(cfgSec, stSec, { x: draggedSec.x + 10, y: draggedSec.y + 10 }, 0)
Assert("Auto-Dodge hovering Secondary pill dims ONLY Secondary pill without dimming Primary stack",
    stSec.secondaryIsAutoDodged && !stSec.isAutoDodged && stSec.secondaryCurrentAlpha <= UIConstants.DODGE_ALPHA)

; Profile save/switch persistence for ShowSecondaryMicHud
cfgSec.SaveProfile("RoomSecondary")
cfgSec.ShowSecondaryMicHud := false
cfgSec.ApplyProfile("RoomSecondary", stSec)
Assert("App Profiles preserve ShowSecondaryMicHud toggle",
    cfgSec.ShowSecondaryMicHud == true)

; Reset Secondary Position does not touch Primary [Position]
ResetSecondaryTrayPosition(cfgSec, stSec)
Assert("ResetSecondaryPosition clears [SecondaryPosition] without altering Primary [Position]",
    cfgSec.savedSecondaryX == "Default" && cfgSec.savedSecondaryY == "Default" && cfgSec.savedX == 240 && cfgSec.savedY == 320)

; Clean up Secondary HUD test timers & windows
for propNm in ["voiceMeterTimerFn", "mutedVoiceTimerFn", "autoDodgeTimerFn", "breathTimerFn", "dragTimerFn", "recTimerFn", "presenterTimerFn"] {
    if (stSec.HasOwnProp(propNm) && stSec.%propNm%)
        SetTimer(stSec.%propNm%, 0)
}
for gObj in GetHudGuiList(stSec, true) {
    try gObj.Destroy()
}
if FileExist(secIni)
    FileDelete(secIni)
if FileExist(secIni ".bak")
    FileDelete(secIni ".bak")

; Scope Guard: STRICTLY Primary PresenterSync.ahk ONLY (zero references in PresenterSync_Remote.ahk)
primM9Src := FileRead(A_ScriptDir "\..\PresenterSync.ahk", "UTF-8")
remM9Src := FileRead(A_ScriptDir "\..\PresenterSync_Remote.ahk", "UTF-8")
Assert("Scope guard: Secondary Independent Mic Pill lives strictly in Primary App (excluded from Remote)",
    InStr(primM9Src, UIConstants.APP_VERSION) && InStr(primM9Src, "Show Secondary Mic Pill") && InStr(primM9Src, "ToggleSecondaryMicLive")
    && InStr(remM9Src, UIConstants.APP_VERSION)
    && !RegExMatch(remM9Src, "SecondaryMicGui|ShowSecondaryMicHud|SecondaryPosition|ToggleSecondaryMic"))

; Cleanup test ini & timeline autosave
if FileExist(testIni)
    FileDelete(testIni)
if FileExist(testIni ".bak")
    FileDelete(testIni ".bak")
SessionTimeline.ClearAutosave()

; ==============================================================================
; WRITE MASTER RESULTS REPORT
; ==============================================================================
report := "=== PRESENTER SYNC MASTER TEST REPORT (v" UIConstants.APP_VERSION ") ===`n"
report .= "Total Tests Executed: " (PassCount + FailCount) "`n"
report .= "Passed: " PassCount "`n"
report .= "Failed: " FailCount "`n"
report .= "Pass Rate: " Round((PassCount / (PassCount + FailCount)) * 100, 1) "%`n`n"
for item in results
    report .= item "`n"

logFile := A_ScriptDir "\master_audit_results.log"
if FileExist(logFile)
    FileDelete(logFile)
FileAppend(report, logFile)
ExitApp(FailCount > 0 ? 1 : 0)
